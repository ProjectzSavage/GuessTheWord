--[[
	RewardsService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	Server-authoritative rewards. The SERVER owns all reward state (claimed,
	playtime, robux spent, daily reset), validates claims, persists to a
	DataStore, and sends a `payload` the client renders.

	REWARDS
	Each reward can grant CASH (leaderstats.Cash) and/or powerup uses
	(RevealLetterUses / RevealWordUses). Reveal Letter is common; Reveal Word is
	rarer.

	SOCIAL
	Social rewards require the player to FOLLOW the owner(s) on Roblox. Since
	Roblox has no public "is following" API, we use the player being FRIENDS with
	the owner as the checkable proxy (friendship requires following on Roblox).

	TIMERS
	Playtime is accumulated live each second; the client shows it counting up.
	Daily rewards reset on a 24h timer (per-day, tracked by date + timestamp).

	SETUP (config at top):
	  * GROUP_ID         - your group id.
	  * VIP_GAMEPASS_ID  - your VIP gamepass id (0 = disabled).
	  * SOCIAL_OWNERS    - { username, userId } owners to follow.
	  * Reward tables + REWARD_IMAGES (fill your asset ids).
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Events")
local RewardDataStore = DataStoreService:GetDataStore("GuessTheWord_Rewards_V1")

local function ensureEvent(name)
	local e = Events:FindFirstChild(name)
	if e then return e end
	e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = Events
	return e
end

local RewardSync        = ensureEvent("RewardSync")
local RewardClaim       = ensureEvent("RewardClaim")
local NotifyPlayer      = ensureEvent("NotifyPlayer")
local AddRobuxSpent     = ensureEvent("AddRobuxSpent")
local RewardRequestSync = ensureEvent("RewardRequestSync")

-------------------------------------------------------------------------------
-- CONFIG
-------------------------------------------------------------------------------
local GROUP_ID = 3597354
local VIP_GAMEPASS_ID = 0
local SOCIAL_OWNERS = {
	{ username = "TheCoolBaconHairIsMe", userId = 3107183806 },
	{ username = "YurisMatrix",          userId = 3721585498 },
}
local DAILY_SECONDS = 24 * 60 * 60

-- Reward image ids (fill in your assets).
local REWARD_IMAGES = {
	letter_1 = "rbxassetid://REVEAL_LETTER_1",
	letter_2 = "rbxassetid://REVEAL_LETTER_2",
	letter_3 = "rbxassetid://REVEAL_LETTER_3",
	word_1   = "rbxassetid://REVEAL_WORD_1",
	word_2   = "rbxassetid://REVEAL_WORD_2",
	cash_100 = "rbxassetid://CASH_100",
	cash_300 = "rbxassetid://CASH_300",
	cash_500 = "rbxassetid://CASH_500",
	cash_1000 = "rbxassetid://CASH_1000",
}

-- Each reward: id, rewards (text for icon matching), and grants (cash + powerup).
-- Reveal Letter is common; Reveal Word is rarer.
local PLAYTIME = {
	{ id = "pt_1",  requiredMin = 1,  cash = 100, rewards = "+$100" },
	{ id = "pt_3",  requiredMin = 3,  powerup = "Letter", uses = 1, rewards = "+1 Reveal Letter" },
	{ id = "pt_10", requiredMin = 10, cash = 300, powerup = "Letter", uses = 2, rewards = "+$300, +2 Reveal Letter" },
	{ id = "pt_20", requiredMin = 20, powerup = "Word", uses = 1, rewards = "+1 Reveal Word" },
}

local DAILY = {
	{ id = "d1", cash = 100, rewards = "+$100" },
	{ id = "d2", powerup = "Letter", uses = 1, rewards = "+1 Reveal Letter" },
	{ id = "d3", cash = 300, rewards = "+$300" },
	{ id = "d4", powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "d5", cash = 500, rewards = "+$500" },
	{ id = "d6", powerup = "Letter", uses = 3, rewards = "+3 Reveal Letter" },
	{ id = "d7", powerup = "Word", uses = 2, cash = 500, rewards = "+$500, +2 Reveal Word" },
}

local ROBUX_SPENT = {
	{ id = "rb_50",   required = 50,   cash = 100, rewards = "+$100" },
	{ id = "rb_250",  required = 250,  powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "rb_1000", required = 1000, cash = 1000, powerup = "Letter", uses = 3, rewards = "+$1000, +3 Reveal Letter" },
	{ id = "rb_5000", required = 5000, powerup = "Word", uses = 2, rewards = "+2 Reveal Word" },
	{ id = "rb_10000",required = 10000,powerup = "Word", uses = 3, cash = 1000, rewards = "+$1000, +3 Reveal Word" },
}

-------------------------------------------------------------------------------
-- DATA
-------------------------------------------------------------------------------
local playerData = {}

local function loadData(player)
	local ok, data = pcall(function()
		return RewardDataStore:GetAsync("player_" .. player.UserId)
	end)
	if ok and type(data) == "table" then
		data.claimed = data.claimed or {}
		data.lastDailyClaim = data.lastDailyClaim or 0
		data.dailyDay = data.dailyDay or 1
		data.robuxSpent = data.robuxSpent or 0
		data.totalPlaytime = data.totalPlaytime or 0
		return data
	end
	return { claimed = {}, lastDailyClaim = 0, dailyDay = 1, robuxSpent = 0, totalPlaytime = 0 }
end

local function saveData(player)
	local data = playerData[player.UserId]
	if not data then return end
	pcall(function()
		RewardDataStore:SetAsync("player_" .. player.UserId, data)
	end)
end

local function ensureData(player)
	if not playerData[player.UserId] then
		playerData[player.UserId] = loadData(player)
	end
	return playerData[player.UserId]
end

-------------------------------------------------------------------------------
-- GRANTING
-------------------------------------------------------------------------------
local function addCash(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") and amount > 0 then
		cash.Value = cash.Value + amount
	end
end

local function grantPowerupUses(player, powerup, uses)
	if not powerup then return end
	local stats = player:FindFirstChild("Stats")
	if not stats then return end
	local useName = (powerup == "Word") and "RevealWordUses" or "RevealLetterUses"
	local val = stats:FindFirstChild(useName)
	if not val then
		val = Instance.new("IntValue")
		val.Name = useName
		val.Parent = stats
	end
	val.Value = val.Value + (uses or 1)
end

local function markClaimed(player, id, grant)
	local data = ensureData(player)
	data.claimed[id] = true
	if grant then
		if grant.cash then addCash(player, grant.cash) end
		if grant.powerup then grantPowerupUses(player, grant.powerup, grant.uses) end
	end
	saveData(player)
end

-------------------------------------------------------------------------------
-- SOCIAL (follow) + READINESS
-------------------------------------------------------------------------------
-- Roblox has no public follow-check API, so "following" is proxied by the
-- player being FRIENDS with the owner (friending requires following them).
local function isFollowing(player, ownerId)
	local ok, isFriend = pcall(function()
		return player:IsFriendsWith(ownerId)
	end)
	return ok and isFriend
end

local function isDailyId(id)
	return type(id) == "string" and string.sub(id, 1, 1) == "d"
end

local function checkDailyReset(player, data)
	local now = os.time()
	local nextClaim = (data.lastDailyClaim or 0) + DAILY_SECONDS
	if now < nextClaim then return end
	-- A new daily cycle: reset daily claims, advance the day.
	for id in pairs(data.claimed) do
		if isDailyId(id) then data.claimed[id] = nil end
	end
	data.lastDailyClaim = now
	data.dailyDay = ((data.dailyDay or 1) % 7) + 1
	saveData(player)
end

local function buildPayload(player, data)
	checkDailyReset(player, data)
	local playMin = math.floor((data.totalPlaytime or 0) / 60)
	local now = os.time()
	local dailyLeft = math.max(0, (data.lastDailyClaim or 0) + DAILY_SECONDS - now)
	local robuxSpent = data.robuxSpent or 0

	local categories = { playtime = {}, daily = {}, group = {}, social = {}, vipdaily = {}, robuxspent = {} }

	for _, row in ipairs(PLAYTIME) do
		table.insert(categories.playtime, {
			id = row.id, left = row.requiredMin .. "m", rewards = row.rewards,
			claimed = data.claimed[row.id] == true,
			ready = (playMin >= row.requiredMin) and not data.claimed[row.id],
		})
	end

	for i, row in ipairs(DAILY) do
		table.insert(categories.daily, {
			id = row.id, rewards = row.rewards, day = i,
			claimed = data.claimed[row.id] == true,
			ready = (data.dailyDay == i and dailyLeft <= 0 and not data.claimed[row.id]),
		})
	end

	local ok, inGroup = pcall(function() return player:IsInGroup(GROUP_ID) end)
	local groupClaimed = data.claimed["group_main"] == true
	table.insert(categories.group, {
		id = "group_main", rewards = "+$500, +2 Reveal Letter", left = "Join",
		claimed = groupClaimed, ready = (ok and inGroup) and not groupClaimed,
	})

	local ownsVip = false
	if VIP_GAMEPASS_ID > 0 then
		local vok, v = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, VIP_GAMEPASS_ID)
		end)
		ownsVip = vok and v
	end
	local vipClaimed = data.claimed["vip_main"] == true
	table.insert(categories.vipdaily, {
		id = "vip_main", rewards = "+3 Reveal Letter", left = "VIP",
		claimed = vipClaimed, ready = ownsVip and not vipClaimed,
	})

	for _, dev in ipairs(SOCIAL_OWNERS) do
		local qid = "social_" .. tostring(dev.userId)
		local followed = isFollowing(player, dev.userId)
		table.insert(categories.social, {
			id = qid, left = "@" .. dev.username, rewards = "+1 Reveal Letter",
			claimed = data.claimed[qid] == true,
			ready = followed and not data.claimed[qid],
			followed = followed,
			devUsername = dev.username,
		})
	end

	for _, row in ipairs(ROBUX_SPENT) do
		table.insert(categories.robuxspent, {
			id = row.id, left = row.required, rewards = row.rewards,
			claimed = data.claimed[row.id] == true,
			ready = robuxSpent >= row.required and not data.claimed[row.id],
		})
	end

	return {
		totalPlaytime = data.totalPlaytime or 0,
		dailyCountdown = dailyLeft,
		dailyDay = data.dailyDay or 1,
		robuxSpentTotal = robuxSpent,
		categories = categories,
	}
end

local function syncPlayer(player)
	local data = ensureData(player)
	RewardSync:FireClient(player, buildPayload(player, data))
end

-------------------------------------------------------------------------------
-- EVENTS
-------------------------------------------------------------------------------
RewardClaim.OnServerEvent:Connect(function(player, categoryId, rowId)
	local data = ensureData(player)
	categoryId = tostring(categoryId or "")
	rowId = tostring(rowId or "")

	-- Social requires following the owner.
	if categoryId == "social" then
		local ownerId = tonumber(rowId:match("social_(%d+)"))
		local followed = ownerId and isFollowing(player, ownerId)
		if not followed then
			NotifyPlayer:FireClient(player, { title = "Not Following", message = "Follow the owner on Roblox to claim this reward.", kind = "warn", duration = 3 })
			syncPlayer(player)
			return
		end
	end

	local payload = buildPayload(player, data)
	local rows = payload.categories[categoryId]
	if type(rows) ~= "table" then syncPlayer(player); return end

	local row
	for _, r in ipairs(rows) do
		if r.id == rowId then row = r end
	end
	if not row or row.claimed or not row.ready then syncPlayer(player); return end

	-- Determine the grant.
	local grant
	if categoryId == "social" then
		grant = { powerup = "Letter", uses = 1 }
	elseif categoryId == "group" then
		grant = { cash = 500, powerup = "Letter", uses = 2 }
	elseif categoryId == "vipdaily" then
		grant = { powerup = "Letter", uses = 3 }
	else
		local lookup = { playtime = PLAYTIME, daily = DAILY, robuxspent = ROBUX_SPENT }
		local defs = lookup[categoryId]
		if defs then
			for _, d in ipairs(defs) do
				if d.id == rowId then grant = d end
			end
		end
	end

	if not grant then syncPlayer(player); return end

	markClaimed(player, row.id, grant)

	if categoryId == "daily" then
		data.lastDailyClaim = os.time()
		saveData(player)
	end

	NotifyPlayer:FireClient(player, { title = "Reward Claimed!", message = row.rewards, kind = "success", duration = 3 })
	syncPlayer(player)
end)

AddRobuxSpent.OnServerEvent:Connect(function(player, amount)
	if type(amount) ~= "number" or amount <= 0 then return end
	local data = ensureData(player)
	data.robuxSpent = (data.robuxSpent or 0) + amount
	saveData(player)
	syncPlayer(player)
end)

RewardRequestSync.OnServerEvent:Connect(function(player)
	syncPlayer(player)
end)

-------------------------------------------------------------------------------
-- PLAYER JOIN / LEAVE
-------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	local data = ensureData(player)
	-- Playtime is session-based.
	data.totalPlaytime = 0
	data.claimed = data.claimed or {}
	for id in pairs(data.claimed) do
		if string.sub(id, 1, 3) == "pt_" then data.claimed[id] = nil end
	end
	saveData(player)

	task.spawn(function()
		while player.Parent do
			task.wait(1)
			if not playerData[player.UserId] then break end
			data.totalPlaytime = (data.totalPlaytime or 0) + 1
			-- Push a lightweight sync every 5s so playtime counts live.
			if data.totalPlaytime % 5 == 0 then
				syncPlayer(player)
			end
			if data.totalPlaytime % 60 == 0 then saveData(player) end
		end
	end)

	task.delay(1.5, function()
		if player.Parent then syncPlayer(player) end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	playerData[player.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(300)
		for _, p in ipairs(Players:GetPlayers()) do saveData(p) end
	end
end)

-- Public helper: add robux-spent on a real purchase.
_G.RewardsAddRobuxSpent = function(player, amount)
	if not player then return end
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	local data = ensureData(player)
	data.robuxSpent = (data.robuxSpent or 0) + amount
	saveData(player)
	syncPlayer(player)
end

print("[RewardsService] Ready")
