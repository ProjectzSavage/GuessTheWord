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
local MarketplaceService = game:GetService("MarketplaceService")

local Dictionary = require(ServerStorage.Modules.Dictionary)
local HeartHUDManager = require(ServerStorage.Modules.HeartHUDManager)
local PlayerPerks = require(ServerStorage.Modules.PlayerPerks)
local CashRerollFX = require(ServerStorage.Modules.CashRerollFX)
local ReceiptRouter = require(ServerStorage.Modules.ReceiptRouter)
local ProfileStore = require(ServerStorage.Modules.ProfileStore)

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
local MatchCancelled = Events:WaitForChild("MatchCancelled")
local SpectatorData = Events:WaitForChild("SpectatorData")
local SpectatorGuess = Events:WaitForChild("SpectatorGuess")
local OpponentState = Events:WaitForChild("OpponentState")
local WrongGuess = Events:WaitForChild("WrongGuess")
local PreloadClueImages = Events:WaitForChild("PreloadClueImages")
local CashReroll = Events:WaitForChild("CashReroll")
local CashAwarded = Events:WaitForChild("CashAwarded")
local PowerupUse = Events:WaitForChild("PowerupUse")
local PowerupGrant = Events:WaitForChild("PowerupGrant")
local PurchasePowerup = Events:WaitForChild("PurchasePowerup")
local NotifyPlayer = Events:WaitForChild("NotifyPlayer")
local RestoreStreakPrompt = Events:WaitForChild("RestoreStreakPrompt")
local RestoreStreakResult = Events:WaitForChild("RestoreStreakResult")

-------------------------------------------------------------------------------
-- CONFIG
-------------------------------------------------------------------------------
local HEARTS_PER_PLAYER = 3
local ROUND_TIME = 15            -- seconds per round
local START_COUNTDOWN = 3        -- 3..2..1 before the match begins
-- Bot difficulty config. maxCash caps the cash-reward roll for that difficulty.
-- The bot builds guesses from the WORD's own letters (permuting them), so it can
-- actually solve; difficulty tunes speed/consistency.
-- warmup: seconds the bot ALWAYS waits after a round starts before its first
-- guess. Without it, Hard (fast thinkTime) could solve the round before the
-- players even saw the board.
local BOT_DIFFICULTIES = {
	Easy =   { thinkTime = 1.4, warmup = 4,   guessChance = 0.6, maxCash = 100, name = "Easy" },
	Medium = { thinkTime = 1.0, warmup = 3,   guessChance = 0.8, maxCash = 350, name = "Medium" },
	Hard =   { thinkTime = 0.7, warmup = 2.5, guessChance = 1.0, maxCash = 750, name = "Hard" },
}
local DEFAULT_DIFFICULTY = "Easy"
local POLL_INTERVAL = 0.2        -- how often we poll seats for a sitting player

-- Cash reward table: value + weighted chance (weights are percentages, summing
-- to 100). The last (5000) is 1%. Edit freely - the server picks proportionally.
local CASH_REWARDS = {
	{ value = 100,  weight = 30 },
	{ value = 350,  weight = 25 },
	{ value = 750,  weight = 20 },
	{ value = 1500, weight = 15 },
	{ value = 3500, weight = 9 },
	{ value = 5000, weight = 1 }, -- rarest: 1%
}
local REROLL_DURATION = 3 -- seconds the client shows the reroll animation
local REWARD_SHOW_WAIT = 1.5 -- extra wait after the reward is revealed before the round starts
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
	handleMatchEndDramatics, despawnBot, awardMatchOutcome, publishSpectator


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
					countdownActive = false, -- pre-match 3..2..1 is running (exiting cancels)
					matchGen = 0,           -- bumped on cancel; kills the running startMatch thread
					liveGuesses = {},      -- seatIndex -> in-progress guess (spectators)
					lastGuess = nil,       -- last submitted guess (spectators)
					lastMarks = {},        -- index -> true where lastGuess matched the word
					cooldownUntil = 0,      -- time before a fresh auto-match can start
					cashPrize = 0,          -- rolled cash prize (awarded to the winner)
					currentWord = nil,
					letterBank = {},
					roundConn = nil,       -- round timer thread
					roundActive = false,   -- is the round timer running?
					roundGen = 0,          -- increments each round; kills stale threads
					botConn = nil,         -- bot loop thread
					botActive = false,     -- is the bot thinking loop running?
					botDifficulty = "Easy", -- current bot difficulty
					attemptedGuesses = {}, -- bot: tried permutations
					revealedIndices = {}, -- Reveal Letter: which word indices are revealed
				}
			end
		end
	end
end

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------
-- Forward-declared: playerOnSeat is defined further down but used by
-- seatedSeatOf() below.
local playerOnSeat

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

-- Fallback seat lookup: find which of this table's seats the player's character
-- is physically sitting in. This stays correct even if the occupants table went
-- stale (e.g. right after a match ended / a winner stayed seated).
local function seatedSeatOf(tableState, player)
	for seatIndex, seat in tableState.seats do
		if playerOnSeat(seat) == player then
			return seatIndex
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
	publishSpectator(tableState) -- hearts changed: refresh the spectator view
end

-- Broadcast this table's match state to EVERY client (spectator HUD data).
-- Participants simply ignore it — they render their own UI. Called whenever
-- something spectators can see changes: match start/end, new round (bank),
-- heart changes, submitted guesses, and live typing (SpectatorGuess).
function publishSpectator(tableState)
	local folder = tableState.folder
	if not folder then
		return
	end
	local bank = {}
	for i, v in tableState.letterBank or {} do
		bank[i] = v
	end
	local names = {}
	for i, occ in tableState.occupants do
		if occ == "BOT" then
			names[i] = "Bot"
		elseif occ and occ.Name then
			names[i] = occ.Name
		end
	end
	local marks = {}
	for i, v in tableState.lastMarks or {} do
		marks[i] = v
	end
	local guesses = {}
	for i, g in tableState.liveGuesses or {} do
		guesses[i] = g
	end
	SpectatorData:FireAllClients({
		id = folder.Name,
		active = tableState.matchActive == true,
		bank = bank,
		wordLength = tableState.currentWord and #tableState.currentWord or 0,
		guesses = guesses,
		names = names,
		hearts = { tableState.hearts[1] or 0, tableState.hearts[2] or 0 },
		lastGuess = tableState.lastGuess,
		lastMarks = marks,
	})
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
	local gen = tableState.roundGen   -- capture current round generation
	tableState.botActive = true

	local diff = BOT_DIFFICULTIES[tableState.botDifficulty] or BOT_DIFFICULTIES[DEFAULT_DIFFICULTY]
	local thinkTime = diff.thinkTime
	local guessChance = diff.guessChance

	-- The bot builds candidates by permuting the WORD's own letters (which are
	-- guaranteed in the 12-letter bank). This lets it actually solve a round.
	local word = tableState.currentWord
	local wordLetters = {}
	for i = 1, #word do
		table.insert(wordLetters, string.sub(word, i, i))
	end

	tableState.botConn = task.spawn(function()
		-- Warmup: the bot never answers in the first seconds of a round
		-- (a freshly started round must not be solved instantly).
		task.wait(diff.warmup or thinkTime)
		while tableState.botActive do
			task.wait(thinkTime)
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
			if math.random() > guessChance then
				-- bot hesitates this tick
			else
				-- Shuffle a copy of the word's letters into a candidate.
				local order = {}
				for i = 1, #wordLetters do
					order[i] = i
				end
				for i = #order, 2, -1 do
					local j = math.random(1, i)
					order[i], order[j] = order[j], order[i]
				end
				local candidate = ""
				for _, k in order do
					candidate = candidate .. wordLetters[k]
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
function gameOver(tableState, winnerSeatIndex, extraRecipients)
	-- winnerSeatIndex = nil means a draw (both ran out of hearts on a timeout).
	-- extraRecipients: Players who already left the table (removed from
	-- occupants before this call) and must still receive GameOver so their
	-- clients reset (camera release, jump unlock, lobby UI).
	tableState.matchActive = false
	-- Give the pause-menu replay control for a few seconds (so re-seating right
	-- after game-over doesn't auto-start a fresh match underneath it).
	tableState.cooldownUntil = os.clock() + 4
	stopRound(tableState)
	stopBot(tableState)
	publishSpectator(tableState) -- match over: spectators lose the table

	-- Update the Wins/Streak leaderboard BEFORE firing GameOver, so clients read
	-- the fresh streak in their celebration. Also covers "opponent left
	-- mid-match" (releasePlayer calls gameOver with the remaining player as the
	-- winner), so they win exactly like a normal victory.
	awardMatchOutcome(tableState, winnerSeatIndex)

	-- Was this match against a bot? Use the type locked in at startMatch
	-- (fall back to a live scan if the flag was never set). This drives the
	-- "Play vs Bot again" pause button AND the quest system (bot wins must
	-- never count as friend wins).
	local isBotMatch = tableState.wasBotMatch
	if isBotMatch == nil then
		isBotMatch = false
		for _, occ in tableState.occupants do
			if occ == "BOT" then
				isBotMatch = true
				break
			end
		end
	end
	local difficulty = isBotMatch and (tableState.botDifficulty or "Easy") or nil

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
				-- Notify the quest system (server-to-server via _G bridge).
				if _G.QuestOnMatchEnded then
					task.spawn(_G.QuestOnMatchEnded, occ, {
						won = won, vsBot = isBotMatch, difficulty = difficulty,
					})
				end
			end
			OpponentState:FireClient(occ, false) -- hide the toggle; game is over
		end
	end

	-- Players who left the table were removed from occupants above, so the
	-- loop never reaches them: fire GameOver to them too (as a loser).
	for _, extra in extraRecipients or {} do
		if extra and extra.Parent then
			if winnerSeatIndex == nil then
				GameOver:FireClient(extra, "", false, true, isBotMatch) -- draw
			else
				local winnerName = tableState.occupants[winnerSeatIndex] ~= "BOT"
					and (tableState.occupants[winnerSeatIndex] :: Player).Name
					or "Bot"
				GameOver:FireClient(extra, winnerName, false, false, isBotMatch)
			end
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

	local function respawnLoser(player, seatIndex, seat)
		task.delay(1.6, function()
			if player.Parent then
				player:LoadCharacter()
				-- Re-seat the loser once their new character spawns, so they can
				-- use the pause-menu replay (which requires being seated).
				local spawned
				spawned = player.CharacterAdded:Connect(function(character)
					if spawned then
						spawned:Disconnect()
					end
					task.wait(0.5)
					if character and character.Parent then
						local humanoid = character:FindFirstChildOfClass("Humanoid")
						local seatNow = seat or tableState.seats[seatIndex]
						if humanoid and seatNow then
							character:PivotTo(seatNow.CFrame * CFrame.new(0, 0.6, 0))
							task.wait(0.1)
							humanoid.Sit = true
						end
					end
				end)
			end
		end)
	end

	for seatIndex, occ in tableState.occupants do
		if occ ~= "BOT" and occ and seatIndex ~= winnerSeatIndex then
			respawnLoser(occ, seatIndex, tableState.seats[seatIndex])
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

-- Cancel a match while its pre-match countdown is still running: NO winner,
-- NO awards, everything back to normal. The leaver's client gets
-- MatchCancelled (releases the table camera, back to the lobby); the
-- remaining seated player(s) go back to the waiting state.
local function cancelCountdown(tableState, leaver)
	tableState.matchActive = false
	tableState.countdownActive = false
	tableState.matchGen = (tableState.matchGen or 0) + 1 -- kills the startMatch thread
	tableState.cooldownUntil = os.clock() + 2
	stopRound(tableState)
	stopBot(tableState)
	despawnBot(tableState)
	for _, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			HeartHUDManager.hide(occ)
			OpponentState:FireClient(occ, true) -- seated & waiting again
		end
	end
	if leaver and leaver.Parent then
		HeartHUDManager.hide(leaver)
		MatchCancelled:FireClient(leaver)
	end
	publishSpectator(tableState) -- cancelled: spectators lose the table
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

	-- Record the submission for spectators (last guess + correct spots).
	tableState.lastGuess = guess
	tableState.lastMarks = {}
	for i = 1, math.min(#guess, #word) do
		if string.sub(guess, i, i) == string.sub(word, i, i) then
			tableState.lastMarks[i] = true
		end
	end
	publishSpectator(tableState)

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
	tableState.revealedIndices = {} -- reset revealed letters each round
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

	-- Fresh spectator state for the new round (new bank, no guesses yet).
	tableState.liveGuesses = {}
	tableState.lastGuess = nil
	tableState.lastMarks = {}
	publishSpectator(tableState)

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

-- Pick a cash reward proportionally by weight.
local function pickCashReward()
	local total = 0
	for _, r in CASH_REWARDS do
		total = total + r.weight
	end
	local roll = math.random() * total
	for _, r in CASH_REWARDS do
		roll = roll - r.weight
		if roll <= 0 then
			return r.value
		end
	end
	return CASH_REWARDS[#CASH_REWARDS].value
end

-- Run the cash reroll: tell clients to animate, then after the animation award
-- the chosen cash to every real player seated.
-- Play the cash reroll animation, then (after it finishes and the reward is
-- shown) wait a little before the round starts. The rolled amount becomes the
-- match PRIZE: it is stored here and awarded to the match WINNER at the end
-- (not to everyone). Returns the chosen reward value.
-- Pick a reward, limited to <= maxCash (used for difficulty-limited rolls).
local function pickCashRewardCapped(maxCash)
	local eligible = {}
	local total = 0
	for _, r in CASH_REWARDS do
		if r.value <= maxCash then
			table.insert(eligible, r)
			total = total + r.weight
		end
	end
	if #eligible == 0 then
		return CASH_REWARDS[1].value
	end
	local roll = math.random() * total
	for _, r in eligible do
		roll = roll - r.weight
		if roll <= 0 then
			return r.value
		end
	end
	return eligible[#eligible].value
end

local function runCashReroll(tableState)
	-- BOT matches cap the roll by difficulty (Easy 100 / Medium 350 / Hard
	-- 750). Player-vs-player matches roll the FULL reward table (up to 5000)
	-- - the difficulty cap must not leak into real-player games.
	local maxCash
	if tableState.wasBotMatch then
		local diff = BOT_DIFFICULTIES[tableState.botDifficulty] or BOT_DIFFICULTIES[DEFAULT_DIFFICULTY]
		maxCash = diff.maxCash
	end
	local reward
	if maxCash then
		reward = pickCashRewardCapped(maxCash)
	else
		reward = pickCashReward()
	end
	local rewardList = {}
	for _, r in CASH_REWARDS do
		if not maxCash or r.value <= maxCash then
			table.insert(rewardList, r.value)
		end
	end

	tableState.cashPrize = reward -- the winner collects this at match end

	-- The world roll animation runs on the SERVER (CashRerollFX) so that
	-- EVERY player in the game can see it - not just the two seated at the
	-- table. The seated players still get the CashReroll event for the
	-- CLIENT-side sound effects.
	local anchor = tableState.folder:FindFirstChild("CashAnchor")
	if anchor and anchor:IsA("BasePart") then
		CashRerollFX.roll(anchor, reward, rewardList)
	end

	-- Fire the animation to each seated real player.
	for _, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			CashReroll:FireClient(occ, reward, rewardList)
		end
	end

	-- Wait for the animation to finish, then a little more so the reward is
	-- clearly shown before the game starts.
	task.wait(REROLL_DURATION + REWARD_SHOW_WAIT)

	-- Tell clients the roll is done (StatsPanel slides out to the top here).
	for _, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			CashAwarded:FireClient(occ, reward)
		end
	end

	return reward
end

function startMatch(tableState)
	tableState.matchActive = true
	local gen = tableState.matchGen or 0
	-- Lock in the match type NOW (a bot seat can clear mid-match; the type
	-- must not change — quests rely on this to split bot vs friend wins).
	tableState.wasBotMatch = false
	for _, occ in tableState.occupants do
		if occ == "BOT" then
			tableState.wasBotMatch = true
			break
		end
	end
	tableState.hearts[1] = HEARTS_PER_PLAYER
	tableState.hearts[2] = HEARTS_PER_PLAYER
	broadcastHearts(tableState) -- also reveals the above-head hearts
	notifyWaiting(tableState)   -- hides the "Play vs Bot" button

	-- Re-broadcast hearts shortly after (and again after the cash roll) so the
	-- bot's above-head hearts reliably appear/update, especially on rematch.
	task.delay(0.5, function()
		if tableState.matchGen == gen and tableState.matchActive then
			broadcastHearts(tableState)
		end
	end)

	-- 3..2..1 countdown before the match begins. The player can still jump
	-- out during it — that CANCELS the match for everyone (see
	-- cancelCountdown). Once the countdown finishes, the match is committed.
	tableState.countdownActive = true
	for i = START_COUNTDOWN, 1, -1 do
		if tableState.matchGen ~= gen or not tableState.matchActive then
			tableState.countdownActive = false
			return -- cancelled: someone left their seat mid-countdown
		end
		for _, occ in tableState.occupants do
			if occ ~= "BOT" and occ then
				Countdown:FireClient(occ, i)
			end
		end
		task.wait(1)
	end
	tableState.countdownActive = false

	-- Cash reroll animation plays after the countdown. The round only starts
	-- AFTER the roll finishes (and cash is awarded).
	runCashReroll(tableState)

	broadcastHearts(tableState) -- re-sync bot hearts before the round starts
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
playerOnSeat = function(seat)
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

	-- Two real players -> normal match. But if a match just ended (cooldown),
	-- let the pause-menu replay (or a fresh manual re-sit) take over instead of
	-- auto-starting.
	if tableState.occupants[1] and tableState.occupants[2] then
		if os.clock() >= tableState.cooldownUntil then
			startMatch(tableState)
		end
	end
end

function releasePlayer(tableState, player)
	-- Leaving during the pre-match countdown CANCELS the match for everyone
	-- (back to normal), instead of awarding the opponent a forfeit win.
	if tableState.countdownActive then
		local seat = seatOfPlayer(tableState, player)
		if seat then
			tableState.occupants[seat] = nil
		end
		cancelCountdown(tableState, player)
		return
	end
	-- Ignore leaving while a match is running except a forfeit/quit.
	if tableState.matchActive then
		-- A real player left mid-match: give the match to the opponent.
		local seat = seatOfPlayer(tableState, player)
		if seat then
			tableState.occupants[seat] = nil
			gameOver(tableState, opponentSeat(seat), { player })
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
PlayVsBotRequest.OnServerEvent:Connect(function(player, difficulty)
	if not player then
		return
	end
	if type(difficulty) ~= "string" or not BOT_DIFFICULTIES[difficulty] then
		difficulty = DEFAULT_DIFFICULTY
	end

	-- Find the table this player currently occupies (must be seated and alone).
	for _, tableState in tableStates do
		-- occupants first, then fall back to the physical seat (handles the
		-- winner staying seated after a match, or a stale occupants table).
		local seatIdx = seatOfPlayer(tableState, player) or seatedSeatOf(tableState, player)
		if seatIdx and not tableState.matchActive then
			local otherIdx = opponentSeat(seatIdx)
			-- On a fast replay, a stale bot from the previous match may still be
			-- in this slot (its despawn is delayed). Clear it so we can respawn.
			if tableState.occupants[otherIdx] == "BOT" then
				despawnBot(tableState)
			end
			-- Only if the other seat is empty (no human, no bot).
			if not tableState.occupants[otherIdx] then
				tableState.botDifficulty = difficulty -- set the difficulty
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

-- Player leaves their chair (used by the difficulty selector's Close button).
local LeaveSeat = Events:WaitForChild("LeaveSeat")
LeaveSeat.OnServerEvent:Connect(function(player)
	if not player then
		return
	end
	for _, tableState in tableStates do
		local seatIdx = seatOfPlayer(tableState, player)
		if seatIdx then
			-- Stand them up and free their seat.
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Sit = false
			end
			releasePlayer(tableState, player)
			return
		end
	end
end)

-- Live typing for spectators: a seated player reports their in-progress
-- guess; the server stores it and re-broadcasts the table's state to all
-- clients (spectators only ever see OTHER tables' data).
SpectatorGuess.OnServerEvent:Connect(function(player, guess)
	if not player then
		return
	end
	if typeof(guess) ~= "string" then
		return
	end
	guess = string.lower(string.gsub(guess, "[^%a]", ""))
	if #guess > 13 then
		guess = string.sub(guess, 1, 13)
	end
	for _, tableState in tableStates do
		local seatIdx = seatOfPlayer(tableState, player)
		if seatIdx and tableState.matchActive then
			tableState.liveGuesses[seatIdx] = guess
			publishSpectator(tableState)
			return
		end
	end
end)

-------------------------------------------------------------------------------
-- QUICK PLAY
-- "Bot"    : teleport the player to a table with NO other real player and
--            let the client open the difficulty selector.
-- "Player" : teleport the player to a table where a real player is ALREADY
--            waiting (the match auto-starts once the seat reconciles).
--            Falls back to an empty table (they wait there) if nobody waits.
-- The seat reconciliation poll loop (below) picks up the move within a tick:
-- the old table releases the player, the new table assigns them (and starts
-- the match when two real players end up seated together).
-------------------------------------------------------------------------------
local QuickPlayRequest = Events:WaitForChild("QuickPlayRequest")
local QuickPlayResult = Events:WaitForChild("QuickPlayResult")

-- Is this seat physically + logically free?
local function quickSeatIsFree(tableState, seatIndex)
	local seat = tableState.seats[seatIndex]
	return not playerOnSeat(seat) and tableState.occupants[seatIndex] == nil
end

-- Where can `player` sit in `tableState`? Returns a seatIndex or nil.
-- allowWaitingPlayer = true  (Player mode): the opposite seat may hold a
-- waiting real player - that's the point.
-- allowWaitingPlayer = false (Bot mode): the opposite seat must be empty or
-- hold a leftover "BOT" (the bot flow despawns stale bots on its own).
-- NOTE: the player's OWN current occupancy is ignored (other == player is
-- treated as "nobody"), so their own table is never "blocked" by themselves.
local function quickFindSeat(tableState, player, allowWaitingPlayer)
	if tableState.matchActive then
		return nil
	end
	for seatIndex = 1, #tableState.seats do
		if quickSeatIsFree(tableState, seatIndex) then
			local other = tableState.occupants[opponentSeat(seatIndex)]
			if other == player then
				other = nil
			end
			if other == nil then
				return seatIndex
			elseif other == "BOT" and not allowWaitingPlayer then
				return seatIndex -- stale bot; PlayVsBotRequest cleans it up
			elseif other ~= "BOT" and allowWaitingPlayer then
				return seatIndex -- a real player is waiting here
			end
		end
	end
	return nil
end

-- Candidate tables for a quick play, shuffled, the player's OWN table first
-- (bot mode can then avoid teleporting when they're already alone at it).
local function quickCandidates(player)
	local current = nil
	for _, tableState in tableStates do
		if seatOfPlayer(tableState, player) or seatedSeatOf(tableState, player) then
			current = tableState
			break
		end
	end
	local shuffled = {}
	for _, tableState in tableStates do
		if not tableState.matchActive and tableState ~= current then
			table.insert(shuffled, tableState)
		end
	end
	for i = #shuffled, 2, -1 do -- Fisher-Yates
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local out = {}
	if current then
		table.insert(out, current)
	end
	for _, tableState in shuffled do
		table.insert(out, tableState)
	end
	return out
end

local function quickTeleport(player, seat)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not humanoid or not hrp then
		return false
	end
	local target = seat.CFrame * CFrame.new(0, 0.6, 0)
	if humanoid.Seated then
		-- Stand up from whatever seat they're in first, or the old seat keeps
		-- the rig latched and the new one never registers.
		humanoid.Sit = false
		task.wait(0.1)
	end
	char:PivotTo(target)
	humanoid.Sit = true
	-- Humanoid.Sit only latches when the rig is settled over the seat; a bare
	-- PivotTo + Sit sometimes leaves the player standing half off the chair
	-- (and nothing starts until Seat.Occupant is set). Verify the seat
	-- actually took, re-centering + re-requesting until it does (~1.5s max).
	for _ = 1, 10 do
		task.wait(0.15)
		if not humanoid.Parent then
			return true -- rig gone (respawn) - nothing left to fix here
		end
		if humanoid.Seated and humanoid.SeatPart == seat then
			return true
		end
		if (hrp.Position - seat.Position).Magnitude > 2 then
			char:PivotTo(target)
		end
		humanoid.Sit = true
	end
	return humanoid.Seated and humanoid.SeatPart == seat
end

local function playerInActiveMatch(player)
	for _, tableState in tableStates do
		if tableState.matchActive and playerInMatch(tableState, player) then
			return true
		end
	end
	return false
end

QuickPlayRequest.OnServerEvent:Connect(function(player, mode)
	if not player or (mode ~= "Bot" and mode ~= "Player") then
		return
	end

	local chosenTable, chosenSeat

	-- 0) Already alone at a usable table? Stay put (no pointless teleport):
	--    Bot mode wants an empty table, Player mode wants a waiting player.
	local ownTable, ownSeat
	for _, tableState in tableStates do
		local s = seatOfPlayer(tableState, player) or seatedSeatOf(tableState, player)
		if s and not tableState.matchActive then
			ownTable, ownSeat = tableState, s
			break
		end
	end
	local ownOther = ownTable and ownTable.occupants[opponentSeat(ownSeat)]
	if ownTable and (
		(mode == "Bot" and (ownOther == nil or ownOther == "BOT"))
		or (mode == "Player" and ownOther ~= nil and ownOther ~= "BOT")
	) then
		chosenTable, chosenSeat = ownTable, ownSeat
	end

	-- 1) Player mode: a table with a real player already waiting.
	if not chosenTable and mode == "Player" then
		for _, cand in quickCandidates(player) do
			local seatIndex = quickFindSeat(cand, player, true)
			if seatIndex then
				local other = cand.occupants[opponentSeat(seatIndex)]
				if other ~= nil and other ~= "BOT" and other ~= player then
					chosenTable, chosenSeat = cand, seatIndex
					break
				end
			end
		end
	end

	-- 2) Bot mode (or Player mode fallback): a truly empty table. (If they're
	--    already alone at their own table, Player mode just stays put.)
	if not chosenTable and mode == "Player" and ownTable and ownOther == nil then
		chosenTable, chosenSeat = ownTable, ownSeat
	end
	if not chosenTable then
		for _, cand in quickCandidates(player) do
			local seatIndex = quickFindSeat(cand, player, false)
			if seatIndex then
				local other = cand.occupants[opponentSeat(seatIndex)]
				if other == nil or other == player then
					chosenTable, chosenSeat = cand, seatIndex
					break
				end
			end
		end
	end

	-- 3) Last resort: anywhere without a real player opposite (stale bot ok).
	if not chosenTable then
		for _, cand in quickCandidates(player) do
			local seatIndex = quickFindSeat(cand, player, false)
			if seatIndex then
				chosenTable, chosenSeat = cand, seatIndex
				break
			end
		end
	end

	if not chosenTable or not chosenSeat then
		QuickPlayResult:FireClient(player, mode, false, "No free table right now - try again")
		return
	end

	-- A match may have started on their old table between the click and now;
	-- never yank a player out of a live match.
	if playerInActiveMatch(player) then
		QuickPlayResult:FireClient(player, mode, false, "A match just started - stay seated")
		return
	end

	local seated = quickTeleport(player, chosenTable.seats[chosenSeat])
	if not seated then
		QuickPlayResult:FireClient(player, mode, false, "You need a character to quick play")
		return
	end

	-- Player mode + post-match cooldown: the auto-start on seat is skipped
	-- while the cooldown runs, so re-trigger it right after it ends (both
	-- players still seated) instead of leaving them sitting there.
	if mode == "Player" and chosenTable.cooldownUntil > os.clock() then
		task.delay(math.max(0, chosenTable.cooldownUntil - os.clock()) + 0.1, function()
			local seatNow = seatOfPlayer(chosenTable, player)
			if seatNow and not chosenTable.matchActive then
				local other = chosenTable.occupants[opponentSeat(seatNow)]
				if other ~= nil and other ~= "BOT" then
					startMatch(chosenTable)
				end
			end
		end)
	end

	if mode == "Player" then
		local other = chosenTable.occupants[opponentSeat(chosenSeat)]
		if other == nil or other == "BOT" or other == player then
			-- Nobody was waiting after all: they're now just waiting in a table.
			QuickPlayResult:FireClient(player, mode, true,
				"No player was waiting - you're now waiting in a table for one")
		else
			-- Real player opposite: the seat reconciliation auto-starts the match.
			QuickPlayResult:FireClient(player, mode, true, "")
		end
	else
		-- Bot mode: tell the client to open the difficulty selector now.
		QuickPlayResult:FireClient(player, mode, true, "")
	end
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
-- POWERUPS (Reveal Letter / Reveal Word)
-------------------------------------------------------------------------------
-- Get a player's powerup-use count.
local function getUses(player, name)
	local stats = player:FindFirstChild("Stats")
	local val = stats and stats:FindFirstChild(name)
	return val and val.Value or 0
end

local function spendUse(player, name)
	local stats = player:FindFirstChild("Stats")
	local val = stats and stats:FindFirstChild(name)
	if val and val.Value > 0 then
		val.Value = val.Value - 1
		return true
	end
	return false
end

-- Reveal the next correct letter, or the full word. A use is REQUIRED: if the
-- player has none left we tell the client (success=false) and it shows the
-- buy prompt (see PowerupGrant handler in InputHandler).
PowerupUse.OnServerEvent:Connect(function(player, powerupType)
	if typeof(powerupType) ~= "string" then
		return
	end
	-- Find the player's active table + round.
	for _, tableState in tableStates do
		local seatIdx = seatOfPlayer(tableState, player) or seatedSeatOf(tableState, player)
		if seatIdx and tableState.matchActive and tableState.currentWord then
			local word = tableState.currentWord

			if powerupType == "Letter" then
				if not spendUse(player, "RevealLetterUses") then
					PowerupGrant:FireClient(player, "Letter", false) -- client shows buy prompt
					return
				end
				-- Reveal the next unrevealed letter IN ORDER (left to right), so
				-- "ball" reveals b, then a, then l, then l.
				local i
				for k = 1, #word do
					if not tableState.revealedIndices[k] then
						i = k
						break
					end
				end
				if not i then
					return -- all letters already revealed
				end
				tableState.revealedIndices[i] = true
				local letter = string.sub(word, i, i)
				PowerupGrant:FireClient(player, "Letter", true, letter, i)
			elseif powerupType == "Word" then
				if not spendUse(player, "RevealWordUses") then
					PowerupGrant:FireClient(player, "Word", false) -- client shows buy prompt
					return
				end
				PowerupGrant:FireClient(player, "Word", true, nil, nil, word)
			end
			return
		end
	end
end)

-- Buy a powerup with robux: prompts the REAL 1-use dev product. The grant
-- happens in ShopService's ProcessReceipt when the player confirms (the
-- in-match PriceLbl refreshes automatically via the Stats value change).
local POWERUP_PRODUCT_IDS = {
	Letter = 3709926777, -- RevealL1
	Word   = 3709926691, -- RevealW1
}
PurchasePowerup.OnServerEvent:Connect(function(player, powerupType)
	if typeof(powerupType) ~= "string" then
		return
	end
	local productId = POWERUP_PRODUCT_IDS[powerupType]
	if not productId or productId == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
		if not ok then
			warn("[GameManager] Powerup purchase failed:", err)
		end
	end)
end)

-------------------------------------------------------------------------------
-- PLAYER JOIN / LEAVE HOOKUP
-------------------------------------------------------------------------------
-- Give every player a leaderboard: Wins and Streak (consecutive wins).
local function ensureLeaderstats(player)
	-- leaderstats shows in the Roblox leaderboard. Cash + Wins go here
	-- (Cash first, so it appears before Wins).
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local cash = leaderstats:FindFirstChild("Cash")
	if not cash then
		cash = Instance.new("IntValue")
		cash.Name = "Cash"
		cash.Value = 0
		cash.Parent = leaderstats
	end

	local wins = leaderstats:FindFirstChild("Wins")
	if not wins then
		wins = Instance.new("IntValue")
		wins.Name = "Wins"
		wins.Value = 0
		wins.Parent = leaderstats
	end

	-- Streak is NOT shown on the leaderboard, so it lives OUTSIDE the
	-- "leaderstats" folder (a folder named "Stats" is not auto-displayed).
	local stats = player:FindFirstChild("Stats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "Stats"
		stats.Parent = player
	end
	local streak = stats:FindFirstChild("Streak")
	if not streak then
		streak = Instance.new("IntValue")
		streak.Name = "Streak"
		streak.Value = 0
		streak.Parent = stats
	end

	-- Powerup uses (hidden from leaderboard, granted by rewards / bought).
	local function ensureUses(name)
		local u = stats:FindFirstChild(name)
		if not u then
			u = Instance.new("IntValue")
			u.Name = name
			u.Value = 0
			u.Parent = stats
		end
		return u
	end
	ensureUses("RevealLetterUses")
	ensureUses("RevealWordUses")
end

-------------------------------------------------------------------------------
-- STREAK RESTORE (buy back a lost streak)
-- When a real player's streak is broken (they lose, or the match is a draw),
-- the client pops the GameUI "Restore" frame for 5 seconds
-- (StreakRestore.client.luau). Buying back uses one of two dev products,
-- tiered by how big the lost streak was:
--
--   lost streak under 10   -> 3710848168
--   lost streak 10 or more -> 3710848228
--
-- Once the purchase is confirmed (ProcessReceipt via ReceiptRouter), the
-- exact lost streak is put back.
-------------------------------------------------------------------------------
local RESTORE_PRODUCT_UNDER_10 = 3710848168
local RESTORE_PRODUCT_10_PLUS  = 3710848228
local RESTORE_PENDING_TIMEOUT  = 60 -- seconds a pending restore stays claimable

-- userId -> { streak = number, productId = number, at = number }
local pendingRestore = {}

local function notifyPlayer(player, title, message, kind)
	NotifyPlayer:FireClient(player, {
		title = title or "Streak",
		message = message,
		kind = kind or "info",
		duration = 4,
	})
end

local function queueStreakRestore(player, lostStreak)
	if not lostStreak or lostStreak <= 0 then
		return
	end
	local productId = lostStreak < 10 and RESTORE_PRODUCT_UNDER_10 or RESTORE_PRODUCT_10_PLUS
	pendingRestore[player.UserId] = { streak = lostStreak, productId = productId, at = os.clock() }
	RestoreStreakPrompt:FireClient(player, lostStreak, productId)
end

local function onRestoreReceipt(receiptInfo, buyer)
	local record = pendingRestore[buyer.UserId]
	if not record then
		-- Nothing pending (expired or player left). Consume the receipt so
		-- ProcessReceipt stops retrying - there is nothing left to grant.
		return
	end
	if (os.clock() - record.at) > RESTORE_PENDING_TIMEOUT then
		pendingRestore[buyer.UserId] = nil
		return
	end
	pendingRestore[buyer.UserId] = nil

	local stats = buyer:FindFirstChild("Stats")
	local streak = stats and stats:FindFirstChild("Streak")
	local restored = 0
	if streak then
		if streak.Value < record.streak then
			streak.Value = record.streak
		end
		restored = streak.Value
	end

	notifyPlayer(buyer, "Streak Restored!", "Your streak of " .. restored .. " is back - keep it alive!", "success")
	RestoreStreakResult:FireClient(buyer, true, restored)
end

for _, productId in ipairs({ RESTORE_PRODUCT_UNDER_10, RESTORE_PRODUCT_10_PLUS }) do
	ReceiptRouter.register(productId, onRestoreReceipt)
end

-- If a player leaves with an unclaimed restore, drop it (the receipt is
-- consumed quietly instead of retrying forever). Also write the final
-- profile so the last match's Cash/Wins/Streak can never be lost to the
-- autosave window.
Players.PlayerRemoving:Connect(function(player)
	pendingRestore[player.UserId] = nil
	ProfileStore.save(player.UserId)
end)

-- Award Wins/Streak based on a finished match.
-- winnerSeatIndex == nil => draw (streak resets). A bot winner awards nothing.
function awardMatchOutcome(tableState, winnerSeatIndex)
	-- Read the (hidden) streak from the "Stats" folder, not leaderstats.
	local function playerStreak(player)
		local stats = player:FindFirstChild("Stats")
		return stats and stats:FindFirstChild("Streak")
	end

	if winnerSeatIndex == nil then
		-- Draw: break any streaks for real players (offer a buy-back).
		for _, occ in tableState.occupants do
			if occ ~= "BOT" and occ then
				local streak = playerStreak(occ)
				if streak then
					if streak.Value > 0 then
						queueStreakRestore(occ, streak.Value)
					end
					streak.Value = 0
				end
			end
		end
		return
	end

	local prize = tableState.cashPrize or 0

	for seatIndex, occ in tableState.occupants do
		if occ ~= "BOT" and occ then
			local ls = occ:FindFirstChild("leaderstats")
			local wins = ls and ls:FindFirstChild("Wins")
			local cash = ls and ls:FindFirstChild("Cash")
			local streak = playerStreak(occ)
			if seatIndex == winnerSeatIndex then
				-- Winner: +win, +streak, and collects the cash prize.
				-- Gamepass perks apply here (2x Wins, 2x Streak, VIP/2x Cash).
				if wins then
					wins.Value = wins.Value + PlayerPerks.winsMult(occ)
				end
				if streak then
					streak.Value = streak.Value + PlayerPerks.streakMult(occ)
				end
				if cash then
					cash.Value = cash.Value + math.floor(prize * PlayerPerks.cashMult(occ))
				end
				else
					-- Loser: reset streak (no cash) - offer a buy-back first.
					if streak then
						if streak.Value > 0 then
							queueStreakRestore(occ, streak.Value)
						end
						streak.Value = 0
					end
				end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	ensureLeaderstats(player)

	-- Restore the persisted hidden Stats (Streak + powerup uses) from the
	-- profile and keep the profile's "stats" section in sync with the live
	-- IntValues (captured on every save). Deferred so any other PlayerAdded
	-- handler (e.g. the starter pack's grant) has run first; max() keeps any
	-- grant made this join safe either way.
	task.defer(function()
		local savedStats = ProfileStore.load(player.UserId).stats
		if type(savedStats) == "table" then
			local stats = player:FindFirstChild("Stats")
			if stats then
				for _, name in ipairs({ "Streak", "RevealLetterUses", "RevealWordUses" }) do
					local val = stats:FindFirstChild(name)
					local saved = tonumber(savedStats[name])
					if val and saved and saved > val.Value then
						val.Value = math.floor(saved)
					end
				end
			end
		end
		ProfileStore.setSection(player.UserId, "stats", function()
			local s = player:FindFirstChild("Stats")
			if not s then
				return nil
			end
			local out = {}
			for _, name in ipairs({ "Streak", "RevealLetterUses", "RevealWordUses" }) do
				local v = s:FindFirstChild(name)
				if v then
					out[name] = v.Value
				end
			end
			return out
		end)

		-- Mirror the wallet (leaderstats Cash + Wins) into the profile and
		-- restore it on join. In a LIVE game leaderstats already persist by
		-- themselves; in Studio that is not reliable, so the DataStore copy
		-- is what keeps your cash across rejoin. Max rule = we never lower
		-- what's already live this join (fresh grants stay safe).
		local savedWallet = ProfileStore.load(player.UserId).wallet
		if type(savedWallet) == "table" then
			local ls = player:FindFirstChild("leaderstats")
			if ls then
				for _, name in ipairs({ "Cash", "Wins" }) do
					local val = ls:FindFirstChild(name)
					local saved = tonumber(savedWallet[name])
					if val and saved and saved > val.Value then
						val.Value = math.floor(saved)
					end
				end
			end
		end
		ProfileStore.setSection(player.UserId, "wallet", function()
			local ls = player:FindFirstChild("leaderstats")
			if not ls then
				return nil
			end
			local out = {}
			local cash = ls:FindFirstChild("Cash")
			local wins = ls:FindFirstChild("Wins")
			if cash then
				out.Cash = cash.Value
			end
			if wins then
				out.Wins = wins.Value
			end
			return out
		end)

		-- Auto-persist the leaderboard values: whenever Cash / Wins / Streak
		-- change for ANY reason (match payout, theft, free gift, shop,
		-- streak restore), schedule a debounced profile save. Without this,
		-- a session that ends inside the 30s autosave window loses the last
		-- match's values on rejoin ("leaderboards don't save").
		local watchConns = {}
		local function watchVal(obj, name)
			local v = obj and obj:FindFirstChild(name)
			if v and v:IsA("ValueBase") then
				table.insert(watchConns, v.Changed:Connect(function()
					ProfileStore.scheduleSave(player.UserId)
				end))
			end
		end
		watchVal(player:FindFirstChild("leaderstats"), "Cash")
		watchVal(player:FindFirstChild("leaderstats"), "Wins")
		watchVal(player:FindFirstChild("Stats"), "Streak")
		player.Destroying:Connect(function()
			for _, c in watchConns do
				c:Disconnect()
			end
		end)
	end)

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
-- GAMEPASS ID SANITY CHECK (one-time, server start)
-- A perk (2x Cash/Wins/Streak, VIP, the gamepass chairs) can only ever
-- activate if its configured id is a REAL gamepass of this game -
-- UserOwnsGamePassAsync always answers "no" for any other id. So validate
-- every configured gamepass id once at server start and print EXACTLY ONE
-- verdict line: either "all valid" or the list of invalid ids.
-------------------------------------------------------------------------------
task.spawn(function()
	local bad = {}
	local checked = 0
	local function check(key, id)
		if not id or id == 0 then
			return
		end
		checked += 1
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.GamePass)
		end)
		if not (ok and type(info) == "table") then
			table.insert(bad, key .. " = " .. id)
		end
	end
	for key, id in PlayerPerks.IDS do
		check(key, id)
	end
	local ChairsConfig = require(ReplicatedStorage:WaitForChild("ChairsConfig"))
	if ChairsConfig.GamepassChairs then
		for name, id in ChairsConfig.GamepassChairs do
			check(name, id)
		end
	end
	-- Always prints exactly one line so you can see the check ran:
	if #bad > 0 then
		warn("[GameManager] Gamepass ID check:", #bad, "of", checked, "configured IDs are NOT valid gamepasses:",
			table.concat(bad, ", "),
			"- perks for those can never activate. Get each pass's real id in Creator Hub (Monetization > Game passes, hover a pass > ... > Copy Asset ID) and update it in: PlayerPerks (ServerStorage.Modules), ShopController, OffersController, ChairsConfig.")
	else
		warn("[GameManager] Gamepass ID check: all", checked, "configured gamepass IDs are valid gamepasses - the perks activate for any account that OWNS (bought) the pass.")
	end
end)

-- ONE LINE PER PLAYER JOIN - the REAL ownership answer for the four perk
-- passes, straight from UserOwnsGamePassAsync. This is ground truth for
-- "does THIS account own the pass?". Creating a pass in Creator Hub does
-- NOT make your account own it - only a purchase does. If it prints NO for
-- you, the perks for that pass cannot apply until the pass is purchased
-- once (simulated buy in Studio / real buy in live).
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local parts = {}
		for key, id in PlayerPerks.IDS do
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			table.insert(parts, key .. "=" .. (ok and owns and "YES" or "NO"))
		end
		warn("[GameManager] Pass ownership for", player.Name, ":", table.concat(parts, ", "))
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
