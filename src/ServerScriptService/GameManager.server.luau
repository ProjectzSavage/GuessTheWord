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

local Events = ReplicatedStorage:WaitForChild("Events")
local PlayVsBotRequest = Events:WaitForChild("PlayVsBotRequest")
local SubmitGuess = Events:WaitForChild("SubmitGuess")
local TimerUpdate = Events:WaitForChild("TimerUpdate")
local HeartUpdate = Events:WaitForChild("HeartUpdate")
local RoundStart = Events:WaitForChild("RoundStart")
local RoundEnd = Events:WaitForChild("RoundEnd")
local GameOver = Events:WaitForChild("GameOver")
local OpponentState = Events:WaitForChild("OpponentState")

-------------------------------------------------------------------------------
-- CONFIG
-------------------------------------------------------------------------------
local HEARTS_PER_PLAYER = 3
local ROUND_TIME = 15            -- seconds per round
local BOT_THINK_TIME = 0.45      -- seconds between bot guesses
local REMATCH_DELAY = 5          -- seconds before auto-rematch

local TABLE_AREA = Workspace:WaitForChild("GameArea")

-- Forward declarations for mutually-referencing functions.
-- In Luau a `local function` is only in scope from its declaration onward, so
-- calling one that is defined LATER from an EARLIER function would silently
-- resolve to a global nil and error at runtime. Declaring the names up front
-- (and defining them below with plain `function ... =` style assignments)
-- guarantees every name is in scope everywhere. Functions NOT listed here have
-- no forward references and keep normal `local function` definitions.
local handleGuess, gameOver, startRound, startMatch, assignPlayer, releasePlayer


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
					roundConn = nil,       -- timer connection
					botConn = nil,         -- bot loop connection
					rematchConn = nil,     -- rematch timer
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

local function broadcastHearts(tableState)
	-- Send each real player their own current heart count.
	for seatIndex, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			HeartUpdate:FireClient(occ, tableState.hearts[seatIndex] or 0)
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
-- Build a minimal but valid rig so the bot can sit and stand out physically.
local function buildBotRig(seat)
	local model = Instance.new("Model")
	model.Name = "Bot"
	model.Parent = Workspace

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = false
	root.CanCollide = false
	root.Transparency = 0.5
	root.Parent = model
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	-- Place at the seat, slightly above so it looks seated.
	local seatCFrame = seat.CFrame * CFrame.new(0, 1.2, 0)
	model:PivotTo(seatCFrame)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
	model.Parent = Workspace
	humanoid.Sit = true

	return humanoid
end

-- The bot guesses a random permutation of the letter bank. It never knows the
-- real answer - this is a placeholder "random guessing" AI (difficulty selection
-- is a future update).
local function startBotLoop(tableState, seatIndex)
	if tableState.botConn then
		tableState.botConn:Disconnect()
	end

	tableState.attemptedGuesses = {}
	local bank = tableState.letterBank

	local function botThink()
		if not tableState.matchActive or not tableState.currentWord then
			return
		end
		if tableState.hearts[seatIndex] and tableState.hearts[seatIndex] <= 0 then
			return
		end

		-- Build a random permutation of the bank (a candidate word).
		local order = {}
		for i = 1, #bank do
			order[i] = i
		end
		for i = #order, 2, -1 do
			local j = math.random(1, i)
			order[i], order[j] = order[j], order[i]
		end

		local candidate = ""
		for _, idx in order do
			candidate = candidate .. bank[idx]
		end

		-- Avoid repeating a permutation the bot already tried this round.
		if not tableState.attemptedGuesses[candidate] then
			tableState.attemptedGuesses[candidate] = true
			-- Same validation path as a real player (server side).
			handleGuess(tableState, seatIndex, candidate)
		end
	end

	tableState.botConn = task.loop(BOT_THINK_TIME, botThink)
end

-------------------------------------------------------------------------------
-- ROUND / MATCH FLOW
-------------------------------------------------------------------------------
function gameOver(tableState, winnerSeatIndex)
	-- winnerSeatIndex = nil means a draw (both ran out of hearts on a timeout).
	tableState.matchActive = false

	if tableState.roundConn then
		tableState.roundConn:Disconnect()
		tableState.roundConn = nil
	end
	if tableState.botConn then
		tableState.botConn:Disconnect()
		tableState.botConn = nil
	end

	for seatIndex, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			if winnerSeatIndex == nil then
				GameOver:FireClient(occ, "", false, true) -- draw
			else
				local won = (seatIndex == winnerSeatIndex)
				local winnerName = tableState.occupants[winnerSeatIndex] ~= "BOT"
					and (tableState.occupants[winnerSeatIndex] :: Player).Name
					or "Bot"
				GameOver:FireClient(occ, winnerName, won, false)
			end
			OpponentState:FireClient(occ, true) -- allow sit-out/rematch UI
		end
	end

	-- Auto-rematch: if both seats are still occupied after a short delay.
	tableState.rematchConn = task.delay(REMATCH_DELAY, function()
		local stillFull = tableState.occupants[1] and tableState.occupants[2]
		if stillFull then
			startMatch(tableState)
		end
	end)
end

local function loseHeart(tableState, seatIndex, reason)
	if not tableState.hearts[seatIndex] then
		return
	end
	tableState.hearts[seatIndex] = tableState.hearts[seatIndex] - 1

	local occ = tableState.occupants[seatIndex]
	if occ ~= "BOT" and occ then
		HeartUpdate:FireClient(occ, tableState.hearts[seatIndex])
	end

	if tableState.hearts[seatIndex] <= 0 then
		return true -- dead
	end
	return false
end

local function endRound(tableState, result, correctWord)
	-- result: "correct" (guesserId) or "timeout"
	if tableState.roundConn then
		tableState.roundConn:Disconnect()
		tableState.roundConn = nil
	end
	if tableState.botConn then
		tableState.botConn:Disconnect()
		tableState.botConn = nil
	end

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
		-- Guesser is correct -> opponent loses a heart.
		local opponentIdx = opponentSeat(seatIndex)
		endRound(tableState, "correct", word)
		local dead = loseHeart(tableState, opponentIdx, "guess")

		if dead then
			gameOver(tableState, seatIndex)
		else
			-- Start next round with both still alive.
			task.wait(1.2) -- short pause so players can read the answer
			startRound(tableState)
		end
	end
	-- Wrong guesses are simply ignored (no penalty) for now.
end

function startRound(tableState)
	if tableState.roundConn then
		tableState.roundConn:Disconnect()
		tableState.roundConn = nil
	end

	local entry = Dictionary.randomEntry()
	tableState.currentWord = entry.word
	tableState.letterBank = Dictionary.scrambleWord(entry.word)

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

	-- Countdown.
	local timeLeft = ROUND_TIME
	tableState.roundConn = task.loop(1, function()
		timeLeft = timeLeft - 1
		if timeLeft <= 0 then
			-- Timeout: both players lose a heart.
			tableState.roundConn:Disconnect()
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
	end)
end

function startMatch(tableState)
	if tableState.rematchConn then
		tableState.rematchConn:Disconnect()
		tableState.rematchConn = nil
	end
	tableState.matchActive = true
	tableState.hearts[1] = HEARTS_PER_PLAYER
	tableState.hearts[2] = HEARTS_PER_PLAYER
	broadcastHearts(tableState)
	notifyWaiting(tableState)
	task.wait(0.75)
	startRound(tableState)
end

-------------------------------------------------------------------------------
-- SEAT DETECTION
-------------------------------------------------------------------------------
local function bindSeat(tableState, seatIndex, seat)
	-- Seat.Occupant changes whenever a Humanoid sits in / leaves the seat.
	-- Covers both human players and the spawned bot rig.
	local previouslySeated = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		if humanoid and humanoid.Parent then
			previouslySeated = humanoid
			local player = Players:GetPlayerFromCharacter(humanoid.Parent)
			if player then
				assignPlayer(tableState, seatIndex, player)
			end
		else
			-- Seat just emptied (player stood up or left).
			if previouslySeated and previouslySeated.Parent then
				local player = Players:GetPlayerFromCharacter(previouslySeated.Parent)
				if player then
					releasePlayer(tableState, player)
				end
			end
			previouslySeated = nil
		end
	end)
end

function assignPlayer(tableState, seatIndex, player)
	if playerInMatch(tableState, player) then
		-- Already occupying this table (e.g. they stood up in a seat briefly).
		return
	end
	if tableState.occupants[seatIndex] then
		-- Seat taken (by the other player or a bot).
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
				tableState.occupants[otherIdx] = "BOT"
				-- Keep botHumanoid referenced so GC keeps it; store on state.
				tableState.botHumanoid = botHumanoid
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
			handleGuess(tableState, seatIdx, guess)
			return
		end
	end
end)

-------------------------------------------------------------------------------
-- PLAYER LEAVE HOOKUP
-------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
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
		-- Bind the Occupant signal once per seat. It fires whenever a humanoid
		-- (player or bot) sits in / leaves the seat, for the lifetime of the place.
		for seatIndex, seat in ts.seats do
			bindSeat(ts, seatIndex, seat)
		end
	end
end

-- Keep the script alive; task.loop runs independently, but a bare loop protects
-- against any unexpected yielding.
while true do
	task.wait(1)
end
