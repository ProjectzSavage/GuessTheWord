--[[
	RewardsService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	Server-authoritative rewards system (ported from the old gmc project):
	the SERVER owns all reward state (claimed, playtime, robux spent, daily reset,
	social visits), validates claims, persists to a DataStore, and sends a
	`payload` the client renders. Rewards grant Reveal Letter / Reveal Word uses
	(written to the player's Stats folder, which the powerup buttons read).

	CATEGORIES: playtime, daily, group, social, vipdaily, robuxspent.

	EVENTS (in ReplicatedStorage.Events):
	  RewardSync (S->C payload), RewardClaim (C->S cat,id),
	  RewardRequestSync (C->S), SocialVisit (C->S rowId), AddRobuxSpent (C->S),
	  NotifyPlayer (S->C).

	SETUP
	  * Set GROUP_ID (your group).
	  * Set VIP_GAMEPASS_ID (your VIP gamepass id).
	  * Fill SOCIAL_OWNERS with the owner usernames/userIds to follow.
	  * Reward image ids live in REWARD_IMAGES (fill in your assets).
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
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
local SocialVisit       = ensureEvent("SocialVisit")

-------------------------------------------------------------------------------
-- CONFIG
-------------------------------------------------------------------------------
local GROUP_ID = 3597354        -- your group
local VIP_GAMEPASS_ID = 0       -- set your VIP gamepass id
local SOCIAL_OWNERS = {
	{ username = "TheCoolBaconHairIsMe", userId = 3107183806 },
	{ username = "YurisMatrix",          userId = 3721585498 },
}
local SOCIAL_CLAIM_DELAY = 5    -- seconds after visiting before you can claim
local DAILY_SECONDS = 24 * 60 * 60

-- Reward image ids (fill in your assets).
local REWARD_IMAGES = {
	letter_1 = "rbxassetid://REVEAL_LETTER_1",
	letter_3 = "rbxassetid://REVEAL_LETTER_3",
	word_1   = "rbxassetid://REVEAL_WORD_1",
}

-- Reward definitions. rewards is a text that the client parses to pick icons
-- (via REWARD_PATTERNS). Each grants powerup uses server-side on claim.
local PLAYTIME = {
	{ id = "pt_1",  requiredMin = 1,  powerup = "Letter", uses = 1, rewards = "+1 Reveal Letter" },
	{ id = "pt_3",  requiredMin = 3,  powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "pt_10", requiredMin = 10, powerup = "Word",   uses = 1, rewards = "+1 Reveal Word" },
}

local DAILY = {
	{ id = "d1", powerup = "Letter", uses = 1, rewards = "+1 Reveal Letter" },
	{ id = "d2", powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "d3", powerup = "Letter", uses = 1, rewards = "+1 Reveal Letter" },
	{ id = "d4", powerup = "Word",   uses = 1, rewards = "+1 Reveal Word" },
	{ id = "d5", powerup = "Letter", uses = 3, rewards = "+3 Reveal Letter" },
	{ id = "d6", powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "d7", powerup = "Word",   uses = 2, rewards = "+2 Reveal Word" },
}

local ROBUX_SPENT = {
	{ id = "rb_50",   required = 50,   powerup = "Letter", uses = 1, rewards = "+1 Reveal Letter" },
	{ id = "rb_250",  required = 250,  powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "rb_1000", required = 1000, powerup = "Word",   uses = 1, rewards = "+1 Reveal Word" },
	{ id = "rb_5000", required = 5000, powerup = "Word",   uses = 2, rewards = "+2 Reveal Word" },
	{ id = "rb_10000",required = 10000,powerup = "Word",   uses = 3, rewards = "+3 Reveal Word" },
}

-------------------------------------------------------------------------------
-- DATA STORE
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
		data.lastClaimDate = data.lastClaimDate or os.date("%Y-%m-%d")
		data.totalPlaytime = data.totalPlaytime or 0
		data.socialVisitAt = data.socialVisitAt or {}
		return data
	end
	return {
		claimed = {}, lastDailyClaim = 0, dailyDay = 1, robuxSpent = 0,
		lastClaimDate = os.date("%Y-%m-%d"), totalPlaytime = 0, socialVisitAt = {},
	}
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
-- GRANTING REWARDS
-------------------------------------------------------------------------------
local function grantPowerupUses(player, powerup, uses)
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

local function markClaimed(player, id, def)
	local data = ensureData(player)
	data.claimed[id] = true
	if def and def.powerup then
		grantPowerupUses(player, def.powerup, def.uses)
	end
	saveData(player)
end

-------------------------------------------------------------------------------
-- PROGRESS / READINESS
-------------------------------------------------------------------------------
local function isDailyId(id)
	return type(id) == "string" and string.sub(id, 1, 1) == "d"
end

local function checkDailyReset(player, data)
	local today = os.date("%Y-%m-%d")
	if data.lastClaimDate == today then return end
	for id in pairs(data.claimed) do
		if isDailyId(id) then
			data.claimed[id] = nil
		end
	end
	data.lastClaimDate = today
	data.lastDailyClaim = 0
	data.dailyDay = data.dailyDay or 1
	saveData(player)
end

local function buildPayload(player, data)
	checkDailyReset(player, data)
	local playMin = math.floor((data.totalPlaytime or 0) / 60)
	local dailyLeft = math.max(0, DAILY_SECONDS - (os.time() - (data.lastDailyClaim or 0)))
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
			id = row.id, rewards = row.rewards,
			claimed = data.claimed[row.id] == true,
			ready = (data.dailyDay == i and dailyLeft <= 0 and not data.claimed[row.id]),
		})
	end

	-- Group
	local ok, inGroup = pcall(function() return player:IsInGroup(GROUP_ID) end)
	local groupClaimed = data.claimed["group_main"] == true
	table.insert(categories.group, {
		id = "group_main", rewards = "+2 Reveal Letter",
		claimed = groupClaimed, ready = (ok and inGroup) and not groupClaimed,
	})

	-- VIP
	local ownsVip = false
	if VIP_GAMEPASS_ID > 0 then
		local vok, v = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, VIP_GAMEPASS_ID)
		end)
		ownsVip = vok and v
	end
	local vipClaimed = data.claimed["vip_main"] == true
	table.insert(categories.vipdaily, {
		id = "vip_main", rewards = "+3 Reveal Letter",
		claimed = vipClaimed, ready = ownsVip and not vipClaimed,
	})

	-- Social (visit each owner, wait a delay, then ready)
	for _, dev in ipairs(SOCIAL_OWNERS) do
		local qid = "social_" .. tostring(dev.userId)
		local visitAt = (data.socialVisitAt and data.socialVisitAt[qid]) or 0
		local waitLeft = 0
		if visitAt > 0 then
			waitLeft = math.max(0, SOCIAL_CLAIM_DELAY - (os.time() - visitAt))
		end
		table.insert(categories.social, {
			id = qid, left = "@" .. dev.username, rewards = "+1 Reveal Letter",
			claimed = data.claimed[qid] == true,
			ready = (visitAt > 0 and waitLeft <= 0 and not data.claimed[qid]),
			waitLeft = waitLeft, devUsername = dev.username, devUserId = dev.userId,
		})
	end

	-- Robux spent
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
SocialVisit.OnServerEvent:Connect(function(player, rowId)
	local data = ensureData(player)
	rowId = tostring(rowId or "")
	if rowId == "" then return end
	data.socialVisitAt = data.socialVisitAt or {}
	data.socialVisitAt[rowId] = os.time()
	saveData(player)
	syncPlayer(player)
end)

RewardClaim.OnServerEvent:Connect(function(player, categoryId, rowId)
	local data = ensureData(player)
	categoryId = tostring(categoryId or "")
	rowId = tostring(rowId or "")

	-- Social requires the visit + wait.
	if categoryId == "social" then
		local visitAt = (data.socialVisitAt and data.socialVisitAt[rowId]) or 0
		local waitLeft = SOCIAL_CLAIM_DELAY - (os.time() - visitAt)
		if visitAt <= 0 or waitLeft > 0 then
			NotifyPlayer:FireClient(player, { title = "Not Ready", message = "Press VISIT first, then wait a few seconds.", kind = "warn", duration = 2.5 })
			syncPlayer(player)
			return
		end
	end

	local payload = buildPayload(player, data)
	local rows = payload.categories[categoryId]
	if type(rows) ~= "table" then syncPlayer(player); return end

	local row, def
	for _, r in ipairs(rows) do
		if r.id == rowId then row = r end
	end
	-- Find the matching definition for reward powerup data.
	local lookup = { playtime = PLAYTIME, daily = DAILY, robuxspent = ROBUX_SPENT }
	local defs = lookup[categoryId]
	if defs then
		for _, d in ipairs(defs) do
			if d.id == rowId then def = d end
		end
	end

	if not row or row.claimed or not row.ready then syncPlayer(player); return end

	-- Grant powerup uses (special-cases for group/vip/social).
	if def then
		markClaimed(player, row.id, def)
	elseif categoryId == "group" then
		markClaimed(player, row.id, { powerup = "Letter", uses = 2 })
	elseif categoryId == "vipdaily" then
		markClaimed(player, row.id, { powerup = "Letter", uses = 3 })
	elseif categoryId == "social" then
		markClaimed(player, row.id, { powerup = "Letter", uses = 1 })
	end

	if categoryId == "daily" then
		data.lastDailyClaim = os.time()
		data.dailyDay = (data.dailyDay or 1) % 7 + 1
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
		if string.sub(id, 1, 3) == "pt_" then
			data.claimed[id] = nil
		end
	end
	saveData(player)

	task.spawn(function()
		while player.Parent do
			task.wait(1)
			if not playerData[player.UserId] then break end
			data.totalPlaytime = (data.totalPlaytime or 0) + 1
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

-- Public helper so other scripts can add robux-spent on real purchases.
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
