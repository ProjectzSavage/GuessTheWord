--[[
	RewardsService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	Server-authoritative rewards. The SERVER owns all reward state (claimed,
	playtime, robux spent, daily reset), validates claims, and sends a `payload`
	the client renders.

	REWARDS
	Each reward can grant CASH (leaderstats.Cash), powerup uses
	(RevealLetterUses / RevealWordUses), or random chairs.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))
local PlayerPerks = require(ServerStorage.Modules.PlayerPerks)
local ProfileStore = require(ServerStorage.Modules.ProfileStore)

local Events = ReplicatedStorage:WaitForChild("Events")

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
local GROUP_ID = 35973544
local SOCIAL_OWNERS = {
	{ username = "TheCoolBaconHairIsMe", userId = 3107183806 },
	{ username = "YurisMatrix",          userId = 3721585498 },
}
local DAILY_SECONDS = 24 * 60 * 60
local FOLLOW_CHECK_TTL = 60
local FOLLOW_API = "https://friends.roproxy.com/v1/users/%d/followings"

local CHEAP_CHAIRS = { "Broken", "Steel", "Icey", "Thunder", "Toxic" }

-- PLAYTIME rewards: requiredMin in minutes
local PLAYTIME = {
	{ id = "pt_5",    requiredMin = 5,    cash = 200, rewards = "+$200" },
	{ id = "pt_10",   requiredMin = 10,   powerup = "Letter", uses = 1, rewards = "+1 Reveal Letter" },
	{ id = "pt_30",   requiredMin = 30,   cash = 300, powerup = "Letter", uses = 1, rewards = "+$300, +1 Reveal Letter" },
	{ id = "pt_60",   requiredMin = 60,   powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "pt_300",  requiredMin = 300,  cash = 500, powerup = "Word", uses = 1, rewards = "+$500, +1 Reveal Word" },
	{ id = "pt_600",  requiredMin = 600,  powerup = "Word", uses = 2, rewards = "+2 Reveal Word" },
	{ id = "pt_1440", requiredMin = 1440, cash = 1000, powerup = "Word", uses = 3, rewards = "+$1000, +3 Reveal Word" },
}

local DAILY = {
	{ id = "d1", cash = 200, rewards = "+$200" },
	{ id = "d2", powerup = "Letter", uses = 1, rewards = "+1 Reveal Letter" },
	{ id = "d3", cash = 300, rewards = "+$300" },
	{ id = "d4", powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "d5", chair = true, rewards = "Random Chair" },
	{ id = "d6", cash = 500, powerup = "Word", uses = 1, rewards = "+$500, +1 Reveal Word" },
	{ id = "d7", cash = 1000, powerup = "Word", uses = 3, rewards = "+$1000, +3 Reveal Word" },
}

local ROBUX_SPENT = {
	{ id = "rb_50",   required = 50,    cash = 200, rewards = "+$200" },
	{ id = "rb_250",  required = 250,   powerup = "Letter", uses = 2, rewards = "+2 Reveal Letter" },
	{ id = "rb_1000", required = 1000,  cash = 1000, powerup = "Word", uses = 1, rewards = "+$1000, +1 Reveal Word" },
	{ id = "rb_5000", required = 5000,  powerup = "Word", uses = 2, rewards = "+2 Reveal Word" },
	{ id = "rb_10000",required = 10000, cash = 1000, powerup = "Word", uses = 3, chair = true, rewards = "+$1000, +3 Reveal Word, Random Chair" },
}

-------------------------------------------------------------------------------
-- DATA
-------------------------------------------------------------------------------
local playerData = {}

-- Persist through the shared profile DataStore (ProfileStore module).
local function saveData(player)
	ProfileStore.save(player.UserId)
end

local function ensureData(player)
	if not playerData[player.UserId] then
		local data = {
			claimed = {}, lastDailyClaim = 0, dailyClaimedCount = 0, robuxSpent = 0, totalPlaytime = 0,
		}
		local saved = ProfileStore.load(player.UserId).rewards
		if type(saved) == "table" then
			if type(saved.claimed) == "table" then
				data.claimed = saved.claimed
			end
			data.lastDailyClaim = tonumber(saved.lastDailyClaim) or 0
			data.robuxSpent = tonumber(saved.robuxSpent) or 0
			-- Legacy migration (the OLD dailies were a 7-day CYCLE whose
			-- claims lived in the claimed map): fold the old d* claims
			-- into the new chain counter and drop them. Runs once per
			-- player - after this save, no d* ids remain in the map.
			local legacyCount = 0
			for id in pairs(data.claimed) do
				if string.sub(id, 1, 1) == "d" then
					legacyCount += 1
					data.claimed[id] = nil
				end
			end
			data.dailyClaimedCount = tonumber(saved.dailyClaimedCount) or legacyCount
			-- totalPlaytime is a SESSION counter - it starts at 0 on every
			-- join (playtime rewards are per-session).
		end
		playerData[player.UserId] = data
		ProfileStore.setSection(player.UserId, "rewards", function()
			local d = playerData[player.UserId]
			if not d then
				return nil
			end
			return {
				claimed = d.claimed or {},
				lastDailyClaim = d.lastDailyClaim or 0,
				dailyClaimedCount = d.dailyClaimedCount or 0,
				robuxSpent = d.robuxSpent or 0,
			}
		end)
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
		-- Gamepass cash perks apply (VIP x1.5 / 2x Cash x2, stackable).
		cash.Value = cash.Value + math.floor(amount * PlayerPerks.cashMult(player))
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

local function grantRandomChair(player)
	if not _G.ChairsGetOwned or not _G.ChairsGrant then return end
	local owned = _G.ChairsGetOwned(player)
	local pool = {}
	for _, name in ipairs(CHEAP_CHAIRS) do
		if not owned[name] then
			table.insert(pool, name)
		end
	end
	if #pool == 0 then return false end
	local pick = pool[math.random(1, #pool)]
	return _G.ChairsGrant(player, pick)
end

local function markClaimed(player, id, grant)
	local data = ensureData(player)
	data.claimed[id] = true
	if grant then
		if grant.cash then addCash(player, grant.cash) end
		if grant.powerup then grantPowerupUses(player, grant.powerup, grant.uses) end
		if grant.chair then grantRandomChair(player) end
	end
	saveData(player)
end

-------------------------------------------------------------------------------
-- FREE GIFT (in-world part with a ProximityPrompt, tagged FreeGift)
-- The client verifies the favorite + group-join requirements and fires
-- ClaimFreeReward; the server re-checks group membership and grants the
-- one-time reward (in-memory claim state, like the other rewards).
-------------------------------------------------------------------------------
local FREE_GIFT_ID = "free_gift"
local ClaimFreeReward  = ensureEvent("ClaimFreeReward")
local FreeRewardResult = ensureEvent("FreeRewardResult")

ClaimFreeReward.OnServerEvent:Connect(function(player)
	if not player then
		return
	end
	local data = ensureData(player)
	if data.claimed[FREE_GIFT_ID] then
		FreeRewardResult:FireClient(player, false, "You already claimed the free gift!")
		return
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	if not (ok and inGroup) then
		FreeRewardResult:FireClient(player, false, "Join the group to claim the free gift!")
		return
	end
	markClaimed(player, FREE_GIFT_ID, { cash = 1000, powerup = "Word", uses = 1 })
	FreeRewardResult:FireClient(player, true, "+$1,000 + 1 Word Reveal")
end)

-------------------------------------------------------------------------------
-- SOCIAL (follow) + READINESS
-------------------------------------------------------------------------------
local followCache = {}

local function fetchFollowings(userId)
	local url = string.format(FOLLOW_API, userId)
	local ok, resp = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not ok then return nil end
	local ok2, decoded = pcall(function()
		return HttpService:JSONDecode(resp)
	end)
	if not ok2 or type(decoded) ~= "table" then return nil end
	local followed = {}
	if type(decoded.data) == "table" then
		for _, entry in ipairs(decoded.data) do
			if type(entry) == "table" and entry.id then
				followed[entry.id] = true
			end
		end
	end
	return followed
end

local function refreshFollowStatus(player)
	local followed = fetchFollowings(player.UserId)
	if followed then
		followCache[player.UserId] = { followed = followed, at = os.clock() }
	end
end

local function isFollowing(player, ownerId)
	local cached = followCache[player.UserId]
	if cached and (os.clock() - cached.at) < FOLLOW_CHECK_TTL then
		return cached.followed[ownerId] == true
	end
	local followed = fetchFollowings(player.UserId)
	if followed then
		followCache[player.UserId] = { followed = followed, at = os.clock() }
		return followed[ownerId] == true
	end
	return false
end

local function buildPayload(player, data)
	local playMin = math.floor((data.totalPlaytime or 0) / 60)
	local now = os.time()
	local robuxSpent = data.robuxSpent or 0
	-- DAILY: a sequential chain. The FIRST one is claimable immediately;
	-- each claim arms a 24h countdown for the NEXT one; missing days never
	-- lock you out (a ready daily stays ready until claimed - the check is
	-- only "has 24h passed since the last claim?"). After day 7 the chain
	-- wraps and runs again.
	local dailyCount = data.dailyClaimedCount or 0
	local dailyPos = dailyCount % 7 -- rows claimed in the current cycle (0-6)
	local dailyReady = dailyCount == 0
		or now >= (data.lastDailyClaim or 0) + DAILY_SECONDS
	local dailyLeft = dailyReady and 0
		or math.max(0, (data.lastDailyClaim or 0) + DAILY_SECONDS - now)

	local categories = { playtime = {}, daily = {}, group = {}, social = {}, vipdaily = {}, robuxspent = {} }

	-- REQUIREMENT: Format playtime >= 60 minutes in hours ("1 hr", "5 hrs", "10 hrs", "24 hrs")
	for _, row in ipairs(PLAYTIME) do
		table.insert(categories.playtime, {
			id = row.id,
			left = NumberFormat.formatPlaytimeRequirement(row.requiredMin),
			requiredMin = row.requiredMin,
			rewards = row.rewards,
			claimed = data.claimed[row.id] == true,
			ready = (playMin >= row.requiredMin) and not data.claimed[row.id],
		})
	end

	for i, row in ipairs(DAILY) do
		table.insert(categories.daily, {
			id = row.id, rewards = row.rewards, day = i,
			claimed = i <= dailyPos,
			ready = (i == dailyPos + 1) and dailyReady,
		})
	end

	local ok, inGroup = pcall(function() return player:IsInGroup(GROUP_ID) end)
	local groupClaimed = data.claimed["group_main"] == true
	table.insert(categories.group, {
		id = "group_main", rewards = "+$500, +2 Reveal Letter, Random Chair", left = "Join",
		claimed = groupClaimed, ready = (ok and inGroup) and not groupClaimed,
	})

	-- Through PlayerPerks (not a raw ownership call) so VIP purchases made
	-- in Studio - which are simulated and invisible to
	-- UserOwnsGamePassAsync - unlock the daily there too.
	local ownsVip = PlayerPerks.owns(player, "VIP")
	local vipClaimed = data.claimed["vip_main"] == true
	table.insert(categories.vipdaily, {
		id = "vip_main", rewards = "+$1000, +3 Reveal Letter, Random Chair", left = "VIP",
		claimed = vipClaimed, ready = ownsVip and not vipClaimed,
	})

	for _, dev in ipairs(SOCIAL_OWNERS) do
		local qid = "social_" .. tostring(dev.userId)
		local followed = isFollowing(player, dev.userId)
		table.insert(categories.social, {
			id = qid, left = "@" .. dev.username, rewards = "+$250, +1 Reveal Letter",
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
		dailyDay = dailyPos + 1,
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

	local grant
	if categoryId == "social" then
		grant = { cash = 250, powerup = "Letter", uses = 1 }
	elseif categoryId == "group" then
		grant = { cash = 500, powerup = "Letter", uses = 2, chair = true }
	elseif categoryId == "vipdaily" then
		grant = { cash = 1000, powerup = "Letter", uses = 3, chair = true }
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
		-- Advance the chain: this claim arms the 24h countdown for the NEXT
		-- daily. (markClaimed already saved once; save again with the fresh
		-- counter + timestamp.)
		data.dailyClaimedCount = (data.dailyClaimedCount or 0) + 1
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
			if data.totalPlaytime % 5 == 0 then
				syncPlayer(player)
			end
			if data.totalPlaytime % 60 == 0 then saveData(player) end
		end
	end)

	task.spawn(function()
		while player.Parent do
			refreshFollowStatus(player)
			if player.Parent then syncPlayer(player) end
			task.wait(FOLLOW_CHECK_TTL)
		end
	end)

	task.delay(1.5, function()
		if player.Parent then syncPlayer(player) end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	ProfileStore.save(player.UserId)
	playerData[player.UserId] = nil
	followCache[player.UserId] = nil
end)

_G.RewardsAddRobuxSpent = function(player, amount)
	if not player then return end
	amount = tonumber(amount) or 0
	if amount <= 0 then return end
	local data = ensureData(player)
	data.robuxSpent = (data.robuxSpent or 0) + amount
	saveData(player)
	syncPlayer(player)
end


