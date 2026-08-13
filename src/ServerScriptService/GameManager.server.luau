--[[
	GameManager.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	RESPONSIBILITIES
	* Watch Workspace.GameArea.Table1, Table2, ... (folders containing a Table
	  and 2 Seats). No new seats are created - existing seats are referenced.
	* Detect players sitting via Humanoid.Seated / Seat.Occupant.
	* Offer an immediate "Play vs Bot" option to a lone player (no timer wait).
	* Run the 1v1 match: 3 hearts each, 15s rounds, guess correct -> opponent
	  -1 heart, timeout -> both -1 heart. Survivor wins.
	* Validate every guess on the server against the server-side Dictionary.
	  The client is never trusted.

	REQUIRED STRUCTURE (see docs/UI_HIERARCHY.md):
		Workspace.GameArea.Table1 (Folder)
		  |-- Table (Model/Part)
		  |-- Seat1 / Seat2 (Seat or VehicleSeat)

	Events are referenced from ReplicatedStorage.Events (auto-created by
	SetupEvents.server.luau).
]]

-------------------------------------------------------------------------------
-- SERVICES / REFERENCES
-------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local Dictionary = require(ServerStorage.Modules.Dictionary)
local HeartHUDManager = require(ServerStorage.Modules.HeartHUDManager)

local Events = ReplicatedStorage:WaitForChild("Events")
local PlayVsBotRequest = Events:WaitForChild("PlayVsBotRequest")
local SubmitGuess = Events:WaitForChild("SubmitGuess")
local TimerUpdate = Events:WaitForChild("TimerUpdate")
local Countdown = Events:WaitForChild("Countdown")
local HeartUpdate = Events:WaitForChild("HeartUpdate")
local OpponentHeartUpdate = Events:WaitForChild("OpponentHeartUpdate")
local RoundStart = Events:WaitForChild("RoundStart")
local RoundEnd = Events:WaitForChild("RoundEnd")
local GameOver = Events:WaitForChild("GameOver")
local OpponentState = Events:WaitForChild("OpponentState")
local WrongGuess = Events:WaitForChild("WrongGuess")
local PreloadClueImages = Events:WaitForChild("PreloadClueImages")

-------------------------------------------------------------------------------
-- CONFIG
-------------------------------------------------------------------------------
local HEARTS_PER_PLAYER = 3
local ROUND_TIME = 15            -- seconds per round
local START_COUNTDOWN = 3        -- 3..2..1 before the match begins
-- Bot is a placeholder random-guessing opponent (difficulty is a future update).
-- To keep it clearly beatable, it guesses slowly and only ~50% of the time.
local BOT_THINK_TIME = 1.1       -- seconds between bot guesses
local BOT_GUESS_CHANCE = 0.5     -- probability the bot actually guesses each tick
local POLL_INTERVAL = 0.2        -- how often we poll seats for a sitting player
-- Correct-answer dramatic beat: hide puzzle -> pause -> loser's heart blinks out
-- -> pause -> show next round. Timings in seconds.
local CORRECT_REVEAL_HIDE = 1.2
local CORRECT_HEART_DELAY = 1.6

local TABLE_AREA = Workspace:WaitForChild("GameArea")

-- Forward declarations for mutually-referencing functions.
-- In Luau a `local function` is only in scope from its declaration onward, so
-- calling one that is defined LATER from an EARLIER function would silently
-- resolve to a global nil and error at runtime. Declaring the names up front
-- (and defining them below with plain `function ... =` style assignments)
-- guarantees every name is in scope everywhere. Functions NOT listed here have
-- no forward references and keep normal `local function` definitions.
local handleGuess, gameOver, startRound, startMatch, assignPlayer, releasePlayer,
	handleMatchEndDramatics, despawnBot, awardMatchOutcome


-------------------------------------------------------------------------------
-- TABLE STATE
-- We derive "Table" folders as any child of GameArea whose name starts with
-- "Table" (Table1, Table2, ...). Each gets its own match state.
-------------------------------------------------------------------------------
local tableStates = {} -- folderName -> { seats, occupants, hearts, ... }

local function findSeats(tableFolder)
	local seats = {}
	for _, child in tableFolder:GetChildren() do
		if child:IsA("Seat") or child:IsA("VehicleSeat") then
			table.insert(seats, child)
		end
	end
	table.sort(seats, function(a, b)
		return a.Name < b.Name
	end)
	return seats
end

local function discoverTables()
	tableStates = {}
	for _, folder in TABLE_AREA:GetChildren() do
		if folder:IsA("Folder") and string.sub(folder.Name, 1, 5) == "Table" then
			local seats = findSeats(folder)
			if #seats >= 2 then
				tableStates[folder.Name] = {
					folder = folder,
					seats = seats,
					occupants = {},        -- seatIndex -> Player | "BOT"
					hearts = {},           -- seatIndex -> number
					matchActive = false,
					currentWord = nil,
					letterBank = {},
					roundConn = nil,       -- round timer thread
					roundActive = false,   -- is the round timer running?
					roundGen = 0,          -- increments each round; kills stale threads
					botConn = nil,         -- bot loop thread
					botActive = false,     -- is the bot thinking loop running?
					attemptedGuesses = {}, -- bot: tried permutations
				}
			end
		end
	end
end

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------
local function playerInMatch(tableState, player)
	for _, occ in tableState.occupants do
		if occ == player then
			return true
		end
	end
	return false
end

local function seatOfPlayer(tableState, player)
	for i, occ in tableState.occupants do
		if occ == player then
			return i
		end
	end
	return nil
end

local function opponentSeat(seatIndex)
	return seatIndex == 1 and 2 or 1
end

-- Tell ONE real player on a seat their own heart count (HeartUpdate) and their
-- opponent's count (OpponentHeartUpdate), so the client can fill the two TopBar
-- heart containers (PlayerHeartContainer + OpponentHeartContainer).
local function sendClientHearts(tableState, seatIndex)
	local occ = tableState.occupants[seatIndex]
	if not occ or occ == "BOT" then
		return
	end
	local oppIdx = opponentSeat(seatIndex)
	HeartUpdate:FireClient(occ, tableState.hearts[seatIndex] or 0)
	OpponentHeartUpdate:FireClient(occ, tableState.hearts[oppIdx] or 0)
end

local function broadcastHearts(tableState)
	-- Update the above-head billboard hearts (server-side) for each character
	-- (player or bot), and send both real players their own + opponent's hearts.
	for seatIndex, occ in tableState.occupants do
		if occ then
			local count = tableState.hearts[seatIndex] or 0
			if occ == "BOT" then
				if tableState.botModel then
					HeartHUDManager.setHearts(tableState.botModel, count)
				end
			else
				HeartHUDManager.setHearts(occ, count) -- shows billboard + count
				sendClientHearts(tableState, seatIndex)
			end
		end
	end
end

local function notifyWaiting(tableState)
	-- A lone human occupant should be told it can click "Play vs Bot".
	for _, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			OpponentState:FireClient(occ, tableState.matchActive == false)
		end
	end
end

-------------------------------------------------------------------------------
-- BOT
-------------------------------------------------------------------------------
-- BOT RIG TEMPLATE
-- If you provide a rig in ServerStorage named "BotRig" (a Model with a
-- Humanoid + a "Head" part), it will be cloned and placed on the opponent seat.
-- This is the recommended approach - it gives the bot a visible body AND a head
-- (so the Hearts billboard can attach to it too). If no template exists, we
-- fall back to a minimal programmatic rig (HumanoidRootPart + Humanoid) so the
-- bot can still sit and guess, but it will have no visible body or hearts.
local BotRigTemplate = ServerStorage:FindFirstChild("BotRig")

local function buildBotRig(seat)
	local model

	if BotRigTemplate then
		model = BotRigTemplate:Clone()
		model.Name = "Bot"
		model.Parent = Workspace
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			warn("[GameManager] ServerStorage.BotRig has no Humanoid; " ..
				"the bot cannot sit.")
			model:Destroy()
			return nil
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		-- Place the rig right on the seat, then Sit=true so the Humanoid finds
		-- and sits in the nearest seat (there is no Humanoid:TakeSeat() in Roblox).
		model:PivotTo(seat.CFrame * CFrame.new(0, 0.6, 0))
		model.Parent = Workspace
		task.wait(0.15)
		humanoid.Sit = true
		-- Give the bot hearts above its head (if its rig has a Head part).
		HeartHUDManager.register(model, model)
		return humanoid
	end

	-- Fallback: minimal rig (no template provided). Still gets a Head so the
	-- Hearts billboard can attach (above-head hearts always work for the bot).
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = false
	root.CanCollide = false
	root.Transparency = 0.5

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1, 1, 1)
	head.Transparency = 0.5
	head.Anchored = false
	head.CanCollide = false

	local humanoid = Instance.new("Humanoid")

	model = Instance.new("Model")
	model.Name = "Bot"
	model.PrimaryPart = root
	root.Parent = model
	humanoid.Parent = model
	head.Parent = model

	local seatCFrame = seat.CFrame * CFrame.new(0, 0.6, 0)
	model:PivotTo(seatCFrame)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
	model.Parent = Workspace
	task.wait(0.15)
	humanoid.Sit = true
	-- Give the bot above-head hearts even with the fallback rig.
	HeartHUDManager.register(model, model)

	return humanoid
end

-- The bot guesses a random permutation of the letter bank. It never knows the
-- real answer - this is a placeholder "random guessing" AI (difficulty selection
-- is a future update).
--
-- NOTE: Roblox's `task` library has NO `task.loop`. Loops are run with
-- `task.spawn` + a flag-controlled `while`, and stopped with `task.cancel`.
local function stopBot(tableState)
	tableState.botActive = false
	if tableState.botConn then
		local t = tableState.botConn
		tableState.botConn = nil
		-- Never cancel the CURRENTLY running thread (e.g. the bot's own loop when
		-- it just guessed correctly -> endRound -> stopBot). That would error.
		if t ~= coroutine.running() then
			task.cancel(t)
		end
	end
end

local function stopRound(tableState)
	tableState.roundActive = false
	if tableState.roundConn then
		local t = tableState.roundConn
		tableState.roundConn = nil
		if t ~= coroutine.running() then
			task.cancel(t)
		end
	end
end

local function startBotLoop(tableState, seatIndex)
	stopBot(tableState)

	tableState.attemptedGuesses = {}
	local bank = tableState.letterBank
	local gen = tableState.roundGen   -- capture current round generation
	tableState.botActive = true

	tableState.botConn = task.spawn(function()
		while tableState.botActive do
			task.wait(BOT_THINK_TIME)
			if not tableState.botActive then
				break
			end
			-- If a new round has started, this stale bot thread must die.
			if tableState.roundGen ~= gen then
				break
			end
			if not tableState.matchActive or not tableState.currentWord then
				break
			end
			if tableState.hearts[seatIndex] and tableState.hearts[seatIndex] <= 0 then
				break
			end
			-- The bot hesitates sometimes (keeps it clearly beatable).
			if math.random() <= BOT_GUESS_CHANCE then
				-- The bank holds 12 letters (word letters + fillers). The bot
				-- guesses a word of the CORRECT length by picking `wordLen`
				-- distinct letters from the bank in a random order.
				local wordLen = #tableState.currentWord
				local order = {}
				for i = 1, #bank do
					order[i] = i
				end
				for i = #order, 2, -1 do
					local j = math.random(1, i)
					order[i], order[j] = order[j], order[i]
				end

				local candidate = ""
				for k = 1, wordLen do
					candidate = candidate .. bank[order[k]]
				end

				-- Avoid repeating a candidate the bot already tried this round.
				if not tableState.attemptedGuesses[candidate] then
					tableState.attemptedGuesses[candidate] = true
					-- Same validation path as a real player (server side).
					handleGuess(tableState, seatIndex, candidate)
				end
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- ROUND / MATCH FLOW
-------------------------------------------------------------------------------
function gameOver(tableState, winnerSeatIndex)
	-- winnerSeatIndex = nil means a draw (both ran out of hearts on a timeout).
	tableState.matchActive = false
	stopRound(tableState)
	stopBot(tableState)

	-- Update the Wins/Streak leaderboard BEFORE firing GameOver, so clients read
	-- the fresh streak in their celebration. Also covers "opponent left
	-- mid-match" (releasePlayer calls gameOver with the remaining player as the
	-- winner), so they win exactly like a normal victory.
	awardMatchOutcome(tableState, winnerSeatIndex)

	-- Was this match against a bot? (drives the "Play vs Bot again" pause button)
	local isBotMatch = false
	for _, occ in tableState.occupants do
		if occ == "BOT" then
			isBotMatch = true
			break
		end
	end

	for seatIndex, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			if winnerSeatIndex == nil then
				GameOver:FireClient(occ, "", false, true, isBotMatch) -- draw
			else
				local won = (seatIndex == winnerSeatIndex)
				local winnerName = tableState.occupants[winnerSeatIndex] ~= "BOT"
					and (tableState.occupants[winnerSeatIndex] :: Player).Name
					or "Bot"
				GameOver:FireClient(occ, winnerName, won, false, isBotMatch)
			end
			OpponentState:FireClient(occ, false) -- hide the toggle; game is over
		end
	end

	-- NOTE: no auto-rematch. The match genuinely ENDS here (a player lost all 3
	-- hearts). The client shows a "Play vs Bot again" pause screen instead.

	-- Dramatic end: only the loser ragdolls then respawns. The winner stays in
	-- their chair (a fresh bot match starts from the pause button).
	handleMatchEndDramatics(tableState, winnerSeatIndex)

	-- After the drama, return everything to normal: despawn the bot, hide all
	-- above-head hearts. Capture THIS bot's model so a fast replay (new bot) is
	-- not clobbered by this delayed cleanup.
	local capturedBot = tableState.botModel
	task.delay(2.5, function()
		if tableState.botModel == capturedBot then
			despawnBot(tableState)
		end
		for _, occ in tableState.occupants do
			if occ ~= "BOT" and occ then
				HeartHUDManager.hide(occ)
			end
		end
	end)
end

-- Match-end drama:
--   * The winning real player stands up (leaves the chair).
--   * The losing real player ragdolls on the chair, then respawns.
--   * A bot never "respaws" - if the bot loses it is simply left (cleaned on
--     rematch); if the bot wins, the human loser ragdolls + respawns.
function handleMatchEndDramatics(tableState, winnerSeatIndex)
	-- Only the loser (when there's a clear winner) respawns. The winner stays
	-- seated in their chair for the rematch.
	-- NOTE: no ragdoll here - the Realism Mod handles that.
	if winnerSeatIndex == nil then
		return -- draw: no drama, everyone stays seated
	end

	local function respawnLoser(player)
		task.delay(1.6, function()
			if player.Parent then
				player:LoadCharacter()
			end
		end)
	end

	for seatIndex, occ in tableState.occupants do
		if occ ~= "BOT" and occ and seatIndex ~= winnerSeatIndex then
			respawnLoser(occ)
		end
	end
end

-- Remove the bot rig and its hearts so the game returns to normal.
function despawnBot(tableState)
	if tableState.botModel then
		HeartHUDManager.remove(tableState.botModel)
		if tableState.botModel.Parent then
			tableState.botModel:Destroy()
		end
		tableState.botModel = nil
		tableState.botHumanoid = nil
	end
	for i, occ in tableState.occupants do
		if occ == "BOT" then
			tableState.occupants[i] = nil
		end
	end
end

local function loseHeart(tableState, seatIndex, reason)
	if not tableState.hearts[seatIndex] then
		return
	end
	tableState.hearts[seatIndex] = tableState.hearts[seatIndex] - 1

	local occ = tableState.occupants[seatIndex]
	if occ == "BOT" then
		if tableState.botModel then
			HeartHUDManager.setHearts(tableState.botModel, tableState.hearts[seatIndex])
		end
	elseif occ then
		HeartHUDManager.setHearts(occ, tableState.hearts[seatIndex])
	end

	-- A heart loss changes what BOTH players see (the loser's own count, and the
	-- opponent's view of that count), so refresh both real players.
	for i = 1, 2 do
		sendClientHearts(tableState, i)
	end

	if tableState.hearts[seatIndex] <= 0 then
		return true -- dead
	end
	return false
end

local function endRound(tableState, result, correctWord)
	-- result: "correct" (guesserId) or "timeout"
	stopRound(tableState)
	stopBot(tableState)

	for _, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			if result == "correct" then
				RoundEnd:FireClient(occ, "correct", correctWord)
			else
				RoundEnd:FireClient(occ, "timeout", correctWord)
			end
		end
	end
end

-- Server-side guess validation + round outcome.
function handleGuess(tableState, seatIndex, guess)
	if not tableState.matchActive or not tableState.currentWord then
		return
	end

	-- Normalize: lowercase, letters only, cap length to be safe.
	if typeof(guess) ~= "string" then
		return
	end
	guess = string.lower(guess)
	guess = string.gsub(guess, "[^%a]", "")

	local word = tableState.currentWord

	if guess == word then
		-- Guesser is correct. Dramatic beat:
		--   1) endRound fires "correct" -> clients hide the PuzzleArea.
		--   2) pause, then the opponent loses a heart (that heart fades out).
		--   3) pause again, then continue (or end the game).
		local opponentIdx = opponentSeat(seatIndex)
		endRound(tableState, "correct", word)

		task.wait(CORRECT_REVEAL_HIDE)
		local dead = loseHeart(tableState, opponentIdx, "guess")

		task.wait(CORRECT_HEART_DELAY)
		if dead then
			gameOver(tableState, seatIndex)
		else
			startRound(tableState) -- clients reshow the PuzzleArea on RoundStart
		end
		return true
	end
	return false -- wrong guess (no heart loss; client shows a shake/flash)
end

function startRound(tableState)
	stopRound(tableState)
	tableState.roundGen = tableState.roundGen + 1 -- new generation
	local gen = tableState.roundGen

	local entry = Dictionary.randomEntry()
	tableState.currentWord = entry.word
	tableState.letterBank = Dictionary.buildBank(entry.word)

	local wordLength = #entry.word

	-- Send a fresh copy of the bank to each client (RemoteEvents need a copy
	-- anyway; sharing the same table across two clients is avoided).
	local function bankForClient()
		local copy = {}
		for i, v in tableState.letterBank do
			copy[i] = v
		end
		return copy
	end

	-- Tell both real players a new round is live.
	for _, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			RoundStart:FireClient(occ, wordLength, bankForClient(), entry.images)
		end
	end

	-- Start bot thinking if one is seated.
	for i, occ in tableState.occupants do
		if occ == "BOT" then
			startBotLoop(tableState, i)
		end
	end

	-- Round timer (15s countdown). Uses task.spawn + flag loop (no task.loop).
	tableState.roundActive = true
	tableState.roundConn = task.spawn(function()
		local timeLeft = ROUND_TIME
		while tableState.roundActive do
			task.wait(1)
			if not tableState.roundActive then
				break
			end
			-- If a new round replaced this one, this stale timer thread must die.
			if tableState.roundGen ~= gen then
				break
			end
			timeLeft = timeLeft - 1
			if timeLeft <= 0 then
				-- Timeout: both players lose a heart.
				-- Clear the connection FIRST so endRound's stopRound() doesn't
				-- task.cancel() this very thread (which would raise on the next
				-- yield below). endRound is safe to call once roundConn is nil.
				tableState.roundActive = false
				tableState.roundConn = nil
				endRound(tableState, "timeout", tableState.currentWord)

				local dead1 = loseHeart(tableState, 1, "timeout")
				local dead2 = loseHeart(tableState, 2, "timeout")

				if dead1 and dead2 then
					gameOver(tableState, nil) -- draw
				elseif dead1 then
					gameOver(tableState, 2)
				elseif dead2 then
					gameOver(tableState, 1)
				else
					task.wait(1.0)
					startRound(tableState)
				end
			else
				for _, occ in tableState.occupants do
					if occ ~= "BOT" and occ then
						TimerUpdate:FireClient(occ, timeLeft)
					end
				end
			end
		end
	end)
end

function startMatch(tableState)
	tableState.matchActive = true
	tableState.hearts[1] = HEARTS_PER_PLAYER
	tableState.hearts[2] = HEARTS_PER_PLAYER
	broadcastHearts(tableState) -- also reveals the above-head hearts
	notifyWaiting(tableState)   -- hides the "Play vs Bot" button

	-- 3..2..1 countdown before the match begins.
	for i = START_COUNTDOWN, 1, -1 do
		for _, occ in tableState.occupants do
			if occ ~= "BOT" and occ then
				Countdown:FireClient(occ, i)
			end
		end
		task.wait(1)
	end

	startRound(tableState)
end

-------------------------------------------------------------------------------
-- SEAT DETECTION
--
-- NOTE: Seat:GetPropertyChangedSignal("Occupant") does NOT reliably fire when
-- a humanoid sits, so we cannot rely on it alone. The source of truth is a
-- reconciliation loop that polls each seat's `Seat.Occupant` every frame tick.
-- That guarantees detection no matter how/when a player sits. The property
-- signal is kept only as an instant fast-path (it's harmless to double-call
-- because reconcileSeat is idempotent).
-------------------------------------------------------------------------------

-- The real Player currently sitting on a seat, or nil.
local function playerOnSeat(seat)
	local humanoid = seat.Occupant
	if humanoid and humanoid.Parent then
		return Players:GetPlayerFromCharacter(humanoid.Parent)
	end
	return nil
end

-- Reconcile one seat against the tracked occupants. Idempotent, so it is safe
-- to call both from the poll loop and from the (unreliable) Occupant signal.
function reconcileSeat(tableState, seatIndex, seat)
	local current = playerOnSeat(seat)
	local stored = tableState.occupants[seatIndex]

	if current then
		-- A real player is sitting here.
		if stored == current then
			return -- no change
		end
		-- The occupant changed to `current`: release whoever was here before
		-- (a human that left, or a bot that got displaced), then assign.
		if stored and stored ~= "BOT" then
			releasePlayer(tableState, stored)
		end
		assignPlayer(tableState, seatIndex, current)
	else
		-- No real player in the seat. Could be a bot's humanoid, or empty.
		if stored and stored ~= "BOT" then
			-- A real player left this seat.
			releasePlayer(tableState, stored)
		elseif stored == "BOT" and not seat.Occupant then
			-- A bot's seat emptied.
			tableState.occupants[seatIndex] = nil
		end
	end
end

function assignPlayer(tableState, seatIndex, player)
	if playerInMatch(tableState, player) then
		-- Already occupying this table (e.g. they stood up in a seat briefly).
		return
	end
	local existing = tableState.occupants[seatIndex]
	if existing and existing ~= "BOT" then
		-- Seat taken by another real player.
		return
	end

	tableState.occupants[seatIndex] = player
	notifyWaiting(tableState)

	-- Two real players -> normal match.
	if tableState.occupants[1] and tableState.occupants[2] then
		startMatch(tableState)
	end
end

function releasePlayer(tableState, player)
	-- Ignore leaving while a match is running except a forfeit/quit.
	if tableState.matchActive then
		-- A real player left mid-match: give the match to the opponent.
		local seat = seatOfPlayer(tableState, player)
		if seat then
			tableState.occupants[seat] = nil
			gameOver(tableState, opponentSeat(seat))
		end
		return
	end

	for i, occ in tableState.occupants do
		if occ == player then
			tableState.occupants[i] = nil
		end
	end
	notifyWaiting(tableState)
end

-------------------------------------------------------------------------------
-- PLAY VS BOT REQUEST
-------------------------------------------------------------------------------
PlayVsBotRequest.OnServerEvent:Connect(function(player)
	if not player then
		return
	end

	-- Find the table this player currently occupies (must be seated and alone).
	for _, tableState in tableStates do
		local seatIdx = seatOfPlayer(tableState, player)
		if seatIdx and not tableState.matchActive then
			local otherIdx = opponentSeat(seatIdx)
			-- Only if the other seat is empty (no human, no bot yet).
			if not tableState.occupants[otherIdx] then
				local botHumanoid = buildBotRig(tableState.seats[otherIdx])
				if not botHumanoid then
					return -- bot rig failed to spawn
				end
				tableState.occupants[otherIdx] = "BOT"
				-- Keep references so GC keeps them; store on state.
				tableState.botHumanoid = botHumanoid
				tableState.botModel = botHumanoid.Parent
				notifyWaiting(tableState)
				startMatch(tableState)
			end
			return
		end
	end

	-- Player wasn't seated alone: silently ignore.
end)

-------------------------------------------------------------------------------
-- SUBMIT GUESS (server-authoritative validation)
-------------------------------------------------------------------------------
SubmitGuess.OnServerEvent:Connect(function(player, guess)
	if typeof(guess) ~= "string" then
		return
	end
	guess = string.lower(guess):gsub("[^%a]", "")

	for _, tableState in tableStates do
		local seatIdx = seatOfPlayer(tableState, player)
		if seatIdx then
			-- Only send a wrong-guess signal for a NON-empty full-length guess
			-- that did not win. (The bot never triggers this - it uses handleGuess
			-- directly, and we only fire WrongGuess for real player submissions.)
			if guess ~= "" and #guess >= #(tableState.currentWord or "")
				and not handleGuess(tableState, seatIdx, guess) then
				WrongGuess:FireClient(player)
			end
			return
		end
	end
end)

-------------------------------------------------------------------------------
-- PLAYER JOIN / LEAVE HOOKUP
-------------------------------------------------------------------------------
-- Give every player a leaderboard: Wins and Streak (consecutive wins).
local function ensureLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local wins = leaderstats:FindFirstChild("Wins")
	if not wins then
		wins = Instance.new("IntValue")
		wins.Name = "Wins"
		wins.Value = 0
		wins.Parent = leaderstats
	end
	local streak = leaderstats:FindFirstChild("Streak")
	if not streak then
		streak = Instance.new("IntValue")
		streak.Name = "Streak"
		streak.Value = 0
		streak.Parent = leaderstats
	end
end

-- Award Wins/Streak based on a finished match.
-- winnerSeatIndex == nil => draw (streak resets). A bot winner awards nothing.
function awardMatchOutcome(tableState, winnerSeatIndex)
	if winnerSeatIndex == nil then
		-- Draw: break any streaks for real players.
		for _, occ in tableState.occupants do
			if occ ~= "BOT" and occ then
				local ls = occ:FindFirstChild("leaderstats")
				if ls then
					local streak = ls:FindFirstChild("Streak")
					if streak then
						streak.Value = 0
					end
				end
			end
		end
		return
	end

	for seatIndex, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			local ls = occ:FindFirstChild("leaderstats")
			if ls then
				local wins = ls:FindFirstChild("Wins")
				local streak = ls:FindFirstChild("Streak")
				if seatIndex == winnerSeatIndex then
					-- Winner: +1 win, +1 streak.
					if wins then
						wins.Value = wins.Value + 1
					end
					if streak then
						streak.Value = streak.Value + 1
					end
				else
					-- Loser: reset streak.
					if streak then
						streak.Value = 0
					end
				end
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	ensureLeaderstats(player)

	-- Send every unique clue image ID so the client preloads them all up front
	-- (instant display instead of popping in mid-round).
	task.spawn(function()
		local seen = {}
		local ids = {}
		for _, entry in Dictionary.Entries do
			if entry.images then
				for _, id in entry.images do
					if not seen[id] then
						seen[id] = true
						table.insert(ids, id)
					end
				end
			end
		end
		PreloadClueImages:FireClient(player, ids)
	end)

	player.CharacterRemoving:Connect(function(character)
		-- If a player disconnects or respawns, free their seat.
		for _, tableState in tableStates do
			releasePlayer(tableState, player)
		end
	end)
end)

-------------------------------------------------------------------------------
-- INIT
-------------------------------------------------------------------------------
discoverTables()
if next(tableStates) == nil then
	warn("[GameManager] No 'Table*' folders found under Workspace.GameArea. " ..
		"Create Workspace.GameArea.Table1 containing a Table and 2 Seats.")
else
	for name, ts in tableStates do
		print("[GameManager] Watching", name, "with",
			#ts.seats, "seats.")
		-- Fast-path: try the Occupant signal (may not fire for every sit).
		-- The reconciliation poll loop above is the reliable source of truth.
		for seatIndex, seat in ts.seats do
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				reconcileSeat(ts, seatIndex, seat)
			end)
		end
	end
end

-- Keep the script alive; the spawned threads run independently, but a bare
-- loop protects against any unexpected yielding.
task.spawn(function()
	while true do
		task.wait(POLL_INTERVAL)
		for _, ts in tableStates do
			for seatIndex, seat in ts.seats do
				reconcileSeat(ts, seatIndex, seat)
			end
		end
	end
end)

while true do
	task.wait(1)
end
