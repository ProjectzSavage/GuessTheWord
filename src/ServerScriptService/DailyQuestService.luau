--!strict
-- DailyQuestService.luau
-- Server script managing persistent daily quests and friend quests

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

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

local DailyQuestSync = ensureEvent("DailyQuestSync")
local DailyQuestClaim = ensureEvent("DailyQuestClaim")
local NotifyPlayer = ensureEvent("NotifyPlayer")

local STORE = DataStoreService:GetDataStore("DailyQuestData_V2")
local CYCLE_SECONDS = 7 * 60 * 60 -- 7 hour cycle

type QuestState = {
	cycleStart: number,
	claimed: { [string]: boolean },
	winsAtCycleStart: number,
	playedWithFriend: boolean,
	wonWithFriend: boolean,
}

local states: { [number]: QuestState } = {}

local QUESTS = {
	{
		id = "win_1",
		title = "Win a game",
		required = 1,
		reward = 700,
		getProgress = function(stats: Folder?, st: QuestState): number
			local wins = stats and stats:FindFirstChild("Wins") :: IntValue?
			local currentWins = (wins and wins.Value) or 0
			return math.max(0, currentWins - (st.winsAtCycleStart or 0))
		end,
	},
	{
		id = "streak_3",
		title = "Win 3 games in a row",
		required = 3,
		reward = 500,
		getProgress = function(stats: Folder?, _st: QuestState): number
			local ws = stats and stats:FindFirstChild("Winstreak") :: IntValue?
			return (ws and ws.Value) or 0
		end,
	},
	{
		id = "play_friend",
		title = "Play with a friend",
		required = 1,
		reward = 400,
		getProgress = function(_stats: Folder?, st: QuestState): number
			return st.playedWithFriend and 1 or 0
		end,
	},
	{
		id = "win_friend",
		title = "Win against a friend",
		required = 1,
		reward = 600,
		getProgress = function(_stats: Folder?, st: QuestState): number
			return st.wonWithFriend and 1 or 0
		end,
	},
}

local function currentCycleStart(): number
	local now = os.time()
	return now - (now % CYCLE_SECONDS)
end

local function saveState(plr: Player)
	local st = states[plr.UserId]
	if not st then
		return
	end

	local payload = {
		cycleStart = st.cycleStart,
		claimed = st.claimed,
		winsAtCycleStart = st.winsAtCycleStart or 0,
		playedWithFriend = st.playedWithFriend == true,
		wonWithFriend = st.wonWithFriend == true,
	}

	pcall(function()
		STORE:SetAsync("dq_" .. plr.UserId, payload)
	end)
end

local function loadState(plr: Player): QuestState
	local stats = plr:FindFirstChild("leaderstats") :: Folder?
	local wins = stats and stats:FindFirstChild("Wins") :: IntValue?
	local currentWins = (wins and wins.Value) or 0

	local st: QuestState = {
		cycleStart = currentCycleStart(),
		claimed = {},
		winsAtCycleStart = currentWins,
		playedWithFriend = false,
		wonWithFriend = false,
	}

	local ok, data = pcall(function()
		return STORE:GetAsync("dq_" .. plr.UserId)
	end)

	if ok and type(data) == "table" then
		st.cycleStart = tonumber(data.cycleStart) or st.cycleStart
		st.claimed = (type(data.claimed) == "table") and data.claimed or {}
		st.winsAtCycleStart = tonumber(data.winsAtCycleStart) or currentWins
		st.playedWithFriend = (data.playedWithFriend == true)
		st.wonWithFriend = (data.wonWithFriend == true)
	end

	return st
end

local function rolloverIfNeeded(plr: Player, st: QuestState): boolean
	local c = currentCycleStart()
	if st.cycleStart == c then
		return false
	end

	local stats = plr:FindFirstChild("leaderstats") :: Folder?
	local wins = stats and stats:FindFirstChild("Wins") :: IntValue?
	local currentWins = (wins and wins.Value) or 0

	st.cycleStart = c
	st.claimed = {}
	st.winsAtCycleStart = currentWins
	st.playedWithFriend = false
	st.wonWithFriend = false
	return true
end

local function buildPayload(plr: Player): any
	local st = states[plr.UserId]
	if not st then
		return nil
	end

	local changed = rolloverIfNeeded(plr, st)
	if changed then
		saveState(plr)
	end

	local stats = plr:FindFirstChild("leaderstats") :: Folder?
	local quests = {}

	for _, q in ipairs(QUESTS) do
		local progress = math.clamp(tonumber(q.getProgress(stats, st)) or 0, 0, q.required)
		local claimed = (st.claimed[q.id] == true)

		table.insert(quests, {
			id = q.id,
			title = q.title,
			progress = progress,
			required = q.required,
			reward = q.reward,
			claimable = (progress >= q.required) and not claimed,
			claimed = claimed,
		})
	end

	return {
		cycleEndsAt = st.cycleStart + CYCLE_SECONDS,
		quests = quests,
	}
end

local function syncPlayer(plr: Player)
	local payload = buildPayload(plr)
	if payload then
		DailyQuestSync:FireClient(plr, payload)
	end
end

local function markPlayedWithFriend(plr: Player)
	if not plr then return end
	local st = states[plr.UserId]
	if not st then return end
	rolloverIfNeeded(plr, st)
	if not st.playedWithFriend then
		st.playedWithFriend = true
		saveState(plr)
		syncPlayer(plr)
	end
end

local function markWonWithFriend(plr: Player)
	if not plr then return end
	local st = states[plr.UserId]
	if not st then return end
	rolloverIfNeeded(plr, st)
	if not st.wonWithFriend then
		st.wonWithFriend = true
		saveState(plr)
		syncPlayer(plr)
	end
end

DailyQuestClaim.OnServerEvent:Connect(function(plr: Player, questId: any)
	local st = states[plr.UserId]
	if not st then
		return
	end
	rolloverIfNeeded(plr, st)

	local qId = tostring(questId or "")
	local qcfg: any = nil
	for _, q in ipairs(QUESTS) do
		if q.id == qId then
			qcfg = q
			break
		end
	end
	if not qcfg then
		return
	end
	if st.claimed[qId] then
		return
	end

	local stats = plr:FindFirstChild("leaderstats") :: Folder?
	local progress = tonumber(qcfg.getProgress(stats, st)) or 0
	if progress < qcfg.required then
		return
	end

	st.claimed[qId] = true

	local cash = stats and stats:FindFirstChild("Cash") :: IntValue?
	if cash and cash:IsA("IntValue") then
		cash.Value += qcfg.reward
	end

	saveState(plr)
	syncPlayer(plr)

	NotifyPlayer:FireClient(plr, {
		title = "Quest Complete!",
		message = qcfg.title .. " +$" .. tostring(qcfg.reward),
		kind = "success",
		duration = 3,
	})
end)

Players.PlayerAdded:Connect(function(plr: Player)
	plr:WaitForChild("leaderstats", 20)
	states[plr.UserId] = loadState(plr)

	local stats = plr:FindFirstChild("leaderstats") :: Folder?
	local wins = stats and stats:FindFirstChild("Wins") :: IntValue?
	local ws = stats and stats:FindFirstChild("Winstreak") :: IntValue?

	if wins then
		wins.Changed:Connect(function()
			syncPlayer(plr)
			saveState(plr)
		end)
	end

	if ws then
		ws.Changed:Connect(function()
			syncPlayer(plr)
			saveState(plr)
		end)
	end

	syncPlayer(plr)
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	saveState(plr)
	states[plr.UserId] = nil
end)

_G.DailyQuestMarkPlayedWithFriend = function(playerA: Player, playerB: Player)
	markPlayedWithFriend(playerA)
	markPlayedWithFriend(playerB)
end

_G.DailyQuestMarkWinWithFriend = function(winner: Player, _loser: Player)
	markWonWithFriend(winner)
end

task.spawn(function()
	while true do
		for _, p in ipairs(Players:GetPlayers()) do
			syncPlayer(p)
		end
		task.wait(30)
	end
end)

print("[DailyQuestService] Ready")
