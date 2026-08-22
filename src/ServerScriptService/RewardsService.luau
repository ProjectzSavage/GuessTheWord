--!strict
-- RewardsService.luau
-- Server script managing all reward categories (Playtime, Daily, Group, Social, VIP Daily, Robux Spent)
-- Features:
-- 1. Formats playtime >= 60 minutes in hours ("1 hr", "1 hr 30 min", "2 hrs").
-- 2. Data persistence with DataStoreService.
-- 3. Live countdowns, rollover handling, and powerups.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RS = game:GetService("ReplicatedStorage")

local NumberFormat = require(RS:WaitForChild("NumberFormat"))

local Events = RS:FindFirstChild("Events")
if not Events then
	Events = Instance.new("Folder")
	Events.Name = "Events"
	Events.Parent = RS
end

local function ensureEvent(name: string): RemoteEvent
	local e = (Events :: Folder):FindFirstChild(name)
	if e and e:IsA("RemoteEvent") then
		return e
	end
	local newEvent = Instance.new("RemoteEvent")
	newEvent.Name = name
	newEvent.Parent = Events
	return newEvent
end

local RewardSync = ensureEvent("RewardSync")
local RewardClaim = ensureEvent("RewardClaim")
local NotifyPlayer = ensureEvent("NotifyPlayer")
local AddRobuxSpent = ensureEvent("AddRobuxSpent")
local UsePowerup = ensureEvent("UsePowerup")
local RewardRequestSync = ensureEvent("RewardRequestSync")
local SocialVisit = ensureEvent("SocialVisit")

local RewardDataStore = DataStoreService:GetDataStore("RewardsData_V1")

local SOCIAL_TARGETS = {
	{
		id = 3107183806,
		title = "Visit Owner",
		rewards = "+$500, +1 Magnifier",
	},
	{
		id = 3721585498,
		title = "Visit Co-Owner",
		rewards = "+$500, +1 Hook",
	},
}

local DAILY_SECONDS = 24 * 60 * 60
local SOCIAL_CLAIM_DELAY = 5

local playerData: { [number]: any } = {}

-- Playtime tiers (requiredMin in minutes)
local PLAYTIME = {
	{ id = "pt_5",   rewards = "+$250", requiredMin = 5 },
	{ id = "pt_10",  rewards = "+$250, x2 5min", requiredMin = 10 },
	{ id = "pt_15",  rewards = "+$300, +1 Magnifier", requiredMin = 15 },
	{ id = "pt_20",  rewards = "+$300, +1 Magnifier, +1 Hook", requiredMin = 20 },
	{ id = "pt_30",  rewards = "+$300, +1 Magnifier, +2 Hook, x2 15min", requiredMin = 30 },
	{ id = "pt_45",  rewards = "+$500, +2 Magnifier, +2 Hook", requiredMin = 45 },
	{ id = "pt_60",  rewards = "+$600, +1 Mystery", requiredMin = 60 },
	{ id = "pt_90",  rewards = "+$800, +2 Magnifier, +1 Mystery", requiredMin = 90 },
	{ id = "pt_120", rewards = "+$1200, +2 Mystery, x2 15min", requiredMin = 120 },
}

local DAILY = {
	{ id = "d1", rewards = "+$300" },
	{ id = "d2", rewards = "+$400, +1 Magnifier, +1 Hook, +1 Mystery" },
	{ id = "d3", rewards = "+$350, +1 Hook" },
	{ id = "d4", rewards = "+$450, x2 5min" },
	{ id = "d5", rewards = "+$600" },
	{ id = "d6", rewards = "+$650, +2 Hook, x2 15min" },
	{ id = "d7", rewards = "+$800, +1 Magnifier, +1 Hook, +1 Mystery" },
}

local ROBUX_SPENT = {
	{ id = "rb_100",   rewards = "+$500, +1 Magnifier", required = 100 },
	{ id = "rb_250",   rewards = "+$1000, +1 Magnifier, +1 Hook", required = 250 },
	{ id = "rb_500",   rewards = "+$2000, +1 Magnifier, +2 Hook", required = 500 },
	{ id = "rb_1000",  rewards = "+$4000, +2 Magnifier, +2 Hook", required = 1000 },
	{ id = "rb_2500",  rewards = "+$8000, +1 Mystery", required = 2500 },
	{ id = "rb_5000",  rewards = "+$15000, +2 Mystery", required = 5000 },
	{ id = "rb_10000", rewards = "+$30000, +2 Magnifier, +2 Hook, +2 Mystery", required = 10000 },
}

local function isDailyId(id: string): boolean
	if type(id) ~= "string" then
		return false
	end
	if string.sub(id, 1, 1) ~= "d" then
		return false
	end
	return tonumber(string.sub(id, 2)) ~= nil
end

local function loadData(plr: Player): any
	local ok, data = pcall(function()
		return RewardDataStore:GetAsync("player_" .. plr.UserId)
	end)

	if ok and type(data) == "table" then
		data.claimed = data.claimed or {}
		data.lastDailyClaim = data.lastDailyClaim or 0
		data.dailyDay = data.dailyDay or 1
		data.robuxSpent = data.robuxSpent or 0
		data.lastClaimDate = data.lastClaimDate or os.date("%Y-%m-%d")
		data.totalPlaytime = data.totalPlaytime or 0
		data.socialVisitAt = data.socialVisitAt or {}

		data.powerups = data.powerups or {}
		data.powerups.magnifier = data.powerups.magnifier or 0
		data.powerups.hook = data.powerups.hook or 0
		data.powerups.mystery = data.powerups.mystery or 0
		data.powerups.boost2x = data.powerups.boost2x or 0
		data.powerups.boost2xExpiry = data.powerups.boost2xExpiry or 0

		return data
	end

	return {
		claimed = {},
		lastDailyClaim = 0,
		dailyDay = 1,
		robuxSpent = 0,
		lastClaimDate = os.date("%Y-%m-%d"),
		totalPlaytime = 0,
		socialVisitAt = {},
		powerups = {
			magnifier = 0,
			hook = 0,
			mystery = 0,
			boost2x = 0,
			boost2xExpiry = 0,
		},
	}
end

local function saveData(plr: Player)
	local data = playerData[plr.UserId]
	if not data then
		return
	end

	pcall(function()
		RewardDataStore:SetAsync("player_" .. plr.UserId, data)
	end)
end

local function ensureData(plr: Player): any
	if not playerData[plr.UserId] then
		playerData[plr.UserId] = loadData(plr)
	end
	return playerData[plr.UserId]
end

local function addCash(plr: Player, amount: number)
	local ls = plr:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash") :: IntValue?
	if cash and cash:IsA("IntValue") then
		cash.Value += amount
	end
end

local function markClaimed(plr: Player, id: string, rewards: string)
	local data = ensureData(plr)
	data.claimed[id] = true

	if string.find(rewards, "Magnifier") then
		local count = tonumber(string.match(rewards, "%+(%d+) Magnifier")) or 1
		data.powerups.magnifier = (data.powerups.magnifier or 0) + count
	end

	if string.find(rewards, "Hook") then
		local count = tonumber(string.match(rewards, "%+(%d+) Hook")) or 1
		data.powerups.hook = (data.powerups.hook or 0) + count
	end

	if string.find(rewards, "x2") then
		local minutes = tonumber(string.match(rewards, "x2 (%d+)min")) or 5
		local expiry = os.time() + (minutes * 60)
		if expiry > (data.powerups.boost2xExpiry or 0) then
			data.powerups.boost2xExpiry = expiry
			data.powerups.boost2x = 1
		end
	end

	local cashAmount = tonumber(string.match(rewards, "%+%$(%d+)"))
	if cashAmount then
		addCash(plr, cashAmount)
	end

	saveData(plr)
end

local function getDailyCountdown(data: any): number
	if (data.lastDailyClaim or 0) <= 0 then
		return 0
	end
	return math.max(0, DAILY_SECONDS - (os.time() - data.lastDailyClaim))
end

local function checkDailyReset(plr: Player, data: any)
	local today = os.date("%Y-%m-%d")
	if data.lastClaimDate == today then
		return
	end

	for id in pairs(data.claimed) do
		if isDailyId(id) or id == "vip_daily_main" then
			data.claimed[id] = nil
		end
	end

	data.lastClaimDate = today
	data.lastDailyClaim = 0
	data.dailyDay = data.dailyDay or 1

	saveData(plr)
end

local function buildPayload(plr: Player, data: any): any
	local totalPlaytime = data.totalPlaytime or 0
	local playMin = math.floor(totalPlaytime / 60)
	local dailyLeft = getDailyCountdown(data)
	local robuxSpent = data.robuxSpent or 0

	local categories = {
		playtime = {},
		daily = {},
		group = {},
		social = {},
		vipdaily = {},
		robuxspent = {},
	}

	-- REQUIREMENT: Format playtime requirements in hours if >= 60 minutes!
	for _, row in ipairs(PLAYTIME) do
		local claimed = (data.claimed[row.id] == true)
		table.insert(categories.playtime, {
			id = row.id,
			left = NumberFormat.formatPlaytimeRequirement(row.requiredMin),
			requiredMin = row.requiredMin,
			rewards = row.rewards,
			claimed = claimed,
			ready = (playMin >= row.requiredMin) and not claimed,
		})
	end

	for _, t in ipairs(SOCIAL_TARGETS) do
		local qid = "social_" .. tostring(t.id)
		local claimed = (data.claimed[qid] == true)
		local visitAt = (data.socialVisitAt and data.socialVisitAt[qid]) or 0
		local waitLeft = (visitAt > 0) and math.max(0, SOCIAL_CLAIM_DELAY - (os.time() - visitAt)) or 0

		table.insert(categories.social, {
			id = qid,
			left = t.title,
			rewards = t.rewards,
			claimed = claimed,
			ready = (visitAt > 0 and waitLeft <= 0 and not claimed),
			waitLeft = waitLeft,
		})
	end

	for idx, row in ipairs(DAILY) do
		local claimed = (data.claimed[row.id] == true)
		table.insert(categories.daily, {
			id = row.id,
			rewards = row.rewards,
			claimed = claimed,
			ready = (data.dailyDay == idx and dailyLeft <= 0 and not claimed),
		})
	end

	local groupReady = false
	local ok, inGroup = pcall(function()
		return plr:IsInGroup(35973544)
	end)
	if ok and inGroup then
		groupReady = true
	end

	local groupClaimed = (data.claimed["group_main"] == true)
	table.insert(categories.group, {
		id = "group_main",
		rewards = "+$200, +1 Magnifier, +1 Hook",
		claimed = groupClaimed,
		ready = groupReady and not groupClaimed,
	})

	local perks = plr:FindFirstChild("ShopPerks")
	local vip = perks and perks:FindFirstChild("VIPPack") :: BoolValue?
	local vipReady = (vip and vip:IsA("BoolValue") and vip.Value == true) or false
	local vipClaimed = (data.claimed["vip_daily_main"] == true)

	table.insert(categories.vipdaily, {
		id = "vip_daily_main",
		rewards = "+$300, +1 Magnifier, +2 Hook",
		claimed = vipClaimed,
		ready = vipReady and not vipClaimed,
	})

	for _, row in ipairs(ROBUX_SPENT) do
		local claimed = (data.claimed[row.id] == true)
		table.insert(categories.robuxspent, {
			id = row.id,
			rewards = row.rewards,
			left = row.required,
			claimed = claimed,
			ready = (robuxSpent >= row.required) and not claimed,
		})
	end

	return {
		totalPlaytime = totalPlaytime,
		dailyCountdown = dailyLeft,
		categories = categories,
		robuxSpentTotal = robuxSpent,
		powerups = data.powerups or {},
	}
end

local function syncPlayer(plr: Player)
	local data = ensureData(plr)
	checkDailyReset(plr, data)
	RewardSync:FireClient(plr, buildPayload(plr, data))
end

SocialVisit.OnServerEvent:Connect(function(plr: Player, rowId: any)
	local data = ensureData(plr)
	data.socialVisitAt = data.socialVisitAt or {}
	local sId = tostring(rowId or "")
	if sId ~= "" then
		data.socialVisitAt[sId] = os.time()
		saveData(plr)
		syncPlayer(plr)
	end
end)

RewardClaim.OnServerEvent:Connect(function(plr: Player, categoryId: any, rowId: any)
	local data = ensureData(plr)
	local catId = tostring(categoryId or "")
	local rId = tostring(rowId or "")

	local payload = buildPayload(plr, data)
	local rows = payload.categories[catId]
	if type(rows) ~= "table" then
		syncPlayer(plr)
		return
	end

	local targetRow: any = nil
	for _, r in ipairs(rows) do
		if r.id == rId then
			targetRow = r
			break
		end
	end

	if not targetRow or targetRow.claimed or not targetRow.ready then
		syncPlayer(plr)
		return
	end

	markClaimed(plr, targetRow.id, targetRow.rewards)

	if catId == "daily" then
		data.lastDailyClaim = os.time()
		data.dailyDay = (data.dailyDay or 1) % 7 + 1
		saveData(plr)
	end

	NotifyPlayer:FireClient(plr, {
		title = "Reward Claimed!",
		message = targetRow.rewards,
		kind = "success",
		duration = 3,
	})

	syncPlayer(plr)
end)

AddRobuxSpent.OnServerEvent:Connect(function(plr: Player, amount: any)
	local amt = tonumber(amount) or 0
	if amt <= 0 then
		return
	end

	local data = ensureData(plr)
	data.robuxSpent = (data.robuxSpent or 0) + amt
	saveData(plr)

	NotifyPlayer:FireClient(plr, {
		title = "Thank You For Your Purchase!",
		message = "+" .. amt .. " Robux added to your total",
		kind = "robux",
		duration = 4,
	})

	syncPlayer(plr)
end)

RewardRequestSync.OnServerEvent:Connect(function(plr: Player)
	syncPlayer(plr)
end)

UsePowerup.OnServerEvent:Connect(function(plr: Player, powerupType: any)
	local data = ensureData(plr)
	if not data.powerups then
		return
	end

	local keyMap = { magnifier = "magnifier", hook = "hook", mystery = "mystery" }
	local key = keyMap[tostring(powerupType or "")]
	if not key or (data.powerups[key] or 0) <= 0 then
		return
	end

	data.powerups[key] -= 1
	saveData(plr)

	NotifyPlayer:FireClient(plr, {
		title = "Powerup Used!",
		message = "You used 1 " .. tostring(powerupType),
		kind = "info",
		duration = 2,
	})

	syncPlayer(plr)
end)

Players.PlayerAdded:Connect(function(plr: Player)
	local data = ensureData(plr)
	data.totalPlaytime = 0
	data.claimed = data.claimed or {}
	for id in pairs(data.claimed) do
		if string.sub(id, 1, 3) == "pt_" then
			data.claimed[id] = nil
		end
	end
	saveData(plr)

	task.spawn(function()
		while plr.Parent do
			task.wait(1)
			if not playerData[plr.UserId] then
				break
			end
			data.totalPlaytime = (data.totalPlaytime or 0) + 1
			if data.totalPlaytime % 60 == 0 then
				saveData(plr)
			end
		end
	end)

	task.delay(1.5, function()
		if plr.Parent then
			syncPlayer(plr)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	saveData(plr)
	playerData[plr.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(300)
		for _, p in ipairs(Players:GetPlayers()) do
			saveData(p)
		end
	end
end)

print("[RewardsService] Ready - Playtime hours formatting & persistence active")
