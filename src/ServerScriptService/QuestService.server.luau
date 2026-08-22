--[[
	QuestService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	Server-authoritative DAILY QUESTS. Each player gets a set of active quests
	that refresh after a timer (default 7 hours). The server tracks progress,
	validates claims, and sends a `payload` the client renders in the Quest gui.

	QUESTS
	Progress is driven by match completions and game events:
	  * win_match      - win any match
	  * win_bot        - win any bot match
	  * win_bot_hard   - win a HARD bot match
	  * win_friend     - win a match against another player (not a bot)
	  * play_matches   - play any number of matches (win or lose)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Events")

local function ensureEvent(name)
	local e = Events:FindFirstChild(name)
	if e and e:IsA("RemoteEvent") then return e end
	local newEvent = Instance.new("RemoteEvent")
	newEvent.Name = name
	newEvent.Parent = Events
	return newEvent
end

local QuestSync  = ensureEvent("QuestSync")
local QuestClaim = ensureEvent("QuestClaim")
local QuestRequestSync = ensureEvent("QuestRequestSync")

local RESET_SECONDS = 7 * 60 * 60 -- 7 hours

-- Quest definitions (per refresh)
local QUEST_DEFS = {
	{ id = "q1", type = "win_friend",   target = 1, cash = 500, reward = "+$500", desc = "Win against a friend" },
	{ id = "q2", type = "win_bot_hard", target = 1, powerup = "Word", uses = 1, reward = "+1 Reveal Word", desc = "Win a HARD bot match" },
	{ id = "q3", type = "play_matches", target = 3, cash = 300, reward = "+$300", desc = "Play 3 matches" },
	{ id = "q4", type = "win_bot",      target = 2, powerup = "Letter", uses = 2, reward = "+2 Reveal Letter", desc = "Win 2 bot matches" },
	{ id = "q5", type = "win_match",    target = 1, cash = 200, reward = "+$200", desc = "Win a match" },
}

local playerQuest = {} -- userId -> { resetAt, progress = {id=count}, claimed = {id=true} }

local function descFor(def)
	if def.desc then return def.desc end
	if def.type == "win_match" then return "Win a match"
	elseif def.type == "win_bot" then return "Win a bot match"
	elseif def.type == "win_bot_hard" then return "Win a HARD bot match"
	elseif def.type == "win_friend" then return "Win against a friend"
	elseif def.type == "play_matches" then return "Play " .. def.target .. " matches"
	end
	return "Quest"
end

local function ensureState(player)
	local st = playerQuest[player.UserId]
	if not st then
		st = { resetAt = os.time() + RESET_SECONDS, progress = {}, claimed = {} }
		-- Initialize default progress for all active quests to 0
		for _, def in ipairs(QUEST_DEFS) do
			st.progress[def.id] = st.progress[def.id] or 0
		end
		playerQuest[player.UserId] = st
	end
	return st
end

-- Handle quest reset on timer.
local function checkReset(st)
	local now = os.time()
	if now >= st.resetAt then
		st.resetAt = now + RESET_SECONDS
		st.progress = {}
		st.claimed = {}
		for _, def in ipairs(QUEST_DEFS) do
			st.progress[def.id] = 0
		end
	end
end

local function buildPayload(player)
	local st = ensureState(player)
	checkReset(st)
	local quests = {}
	for _, def in ipairs(QUEST_DEFS) do
		local cur = st.progress[def.id] or 0
		table.insert(quests, {
			id = def.id,
			desc = descFor(def),
			progress = cur,
			target = def.target,
			reward = def.reward,
			claimed = st.claimed[def.id] == true,
			done = cur >= def.target,
		})
	end
	return {
		resetAt = st.resetAt,
		resetSeconds = RESET_SECONDS,
		quests = quests,
	}
end

local function syncPlayer(player)
	if not player or not player.Parent then return end
	local payload = buildPayload(player)
	QuestSync:FireClient(player, payload)
end

-- Record progress for a quest type.
local function addProgress(player, qtype, amount)
	local st = ensureState(player)
	checkReset(st)
	local changed = false
	for _, def in ipairs(QUEST_DEFS) do
		if def.type == qtype then
			st.progress[def.id] = (st.progress[def.id] or 0) + amount
			changed = true
		end
	end
	if changed then
		syncPlayer(player)
	end
end

local function grantReward(player, def)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if def.cash and cash and cash:IsA("IntValue") then
		cash.Value = cash.Value + def.cash
	end
	if def.powerup then
		local stats = player:FindFirstChild("Stats")
		if stats then
			local useName = (def.powerup == "Word") and "RevealWordUses" or "RevealLetterUses"
			local val = stats:FindFirstChild(useName)
			if not val then
				val = Instance.new("IntValue")
				val.Name = useName
				val.Parent = stats
			end
			val.Value = val.Value + (def.uses or 1)
		end
	end
end

-------------------------------------------------------------------------------
-- MATCH RESULTS (called directly by GameManager via the _G bridge)
-------------------------------------------------------------------------------
_G.QuestOnMatchEnded = function(player, info)
	if not player or type(info) ~= "table" then return end
	local won = info.won
	local vsBot = info.vsBot
	local difficulty = info.difficulty

	if won then
		addProgress(player, "win_match", 1)
		if vsBot then
			addProgress(player, "win_bot", 1)
			if difficulty == "Hard" then
				addProgress(player, "win_bot_hard", 1)
			end
		else
			addProgress(player, "win_friend", 1)
		end
	end
	addProgress(player, "play_matches", 1)
end

-------------------------------------------------------------------------------
-- CLAIM
-------------------------------------------------------------------------------
QuestClaim.OnServerEvent:Connect(function(player, questId)
	if typeof(questId) ~= "string" then return end
	local st = ensureState(player)
	checkReset(st)
	local def = nil
	for _, d in ipairs(QUEST_DEFS) do
		if d.id == questId then
			def = d
			break
		end
	end
	if not def then return end
	if st.claimed[def.id] then return end
	if (st.progress[def.id] or 0) < def.target then return end

	st.claimed[def.id] = true
	grantReward(player, def)
	syncPlayer(player)
end)

QuestRequestSync.OnServerEvent:Connect(function(player)
	syncPlayer(player)
end)

-------------------------------------------------------------------------------
-- PLAYER JOIN / LEAVE
-------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	ensureState(player)
	task.delay(0.5, function()
		if player.Parent then
			syncPlayer(player)
		end
	end)
	task.delay(2, function()
		if player.Parent then
			syncPlayer(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerQuest[player.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(60)
		for _, p in ipairs(Players:GetPlayers()) do
			local st = playerQuest[p.UserId]
			if st then checkReset(st) end
			syncPlayer(p)
		end
	end
end)

print("[QuestService] Ready - Active quests configured and synced")
