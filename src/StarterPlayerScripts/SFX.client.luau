--[[
	SFX.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays all the game's sound effects on the right moments. Fill in your sound
	asset IDs in the SFX table below. Any entry you leave as "" (empty) or nil is
	simply skipped, so you can add sounds gradually.

	HOW IT WORKS
	Every sound is a `Sound` parented under `SoundService` (Volume/RollOff set
	here). On each game event, we play the matching sound if you've provided an ID.
	Sounds play on the client, so they're cheap and start instantly.

	FILL IN YOUR SOUNDS HERE (rbxassetid://...)
]]
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ---------------------------------------------------------------------------
-- SOUND CONFIG - fill in the IDs you have. Leave unused ones as "".
-- ---------------------------------------------------------------------------
local SFX = {
	countTick  = "", -- short tick during the 3-2-1 countdown
	go         = "", -- "GO!" at round start
	correct    = "", -- correct answer / reveal
	timeout    = "", -- round timed out
	wrong      = "", -- wrong full-length guess (with the shake)
	heartLoss  = "", -- a heart blinks out and disappears
	win        = "", -- you win the match
	lose       = "", -- you lose the match
	draw       = "", -- the match was a draw
	letter     = "", -- a letter flies into the answer box
	hover      = "", -- hovering over a tile/button
	click      = "", -- clicking the Play vs Bot button
}

-- ---------------------------------------------------------------------------
-- ENGINE (no need to edit below here)
-- ---------------------------------------------------------------------------
local Events = ReplicatedStorage:WaitForChild("Events")

local function ensureSound(id)
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.6
	s.Parent = SoundService
	return s
end

local function play(name, opts)
	opts = opts or {}
	local id = SFX[name]
	if type(id) ~= "string" or id == "" then
		return
	end
	local s = ensureSound(id)
	if not s then
		return
	end
	if opts.volume then
		s.Volume = opts.volume
	end
	if opts.speed then
		s.PlaybackSpeed = opts.speed
	end
	s:Play()
	-- Clean up the Sound once it finishes.
	task.delay(s.TimeLength + 0.2, function()
		s:Destroy()
	end)
end

-- ---------------------------------------------------------------------------
-- EVENT -> SOUND WIRING
-- ---------------------------------------------------------------------------
Events:WaitForChild("Countdown").OnClientEvent:Connect(function(n)
	if n <= 3 then
		play("countTick", { volume = 0.5 })
	end
end)

Events:WaitForChild("RoundStart").OnClientEvent:Connect(function()
	play("go")
end)

Events:WaitForChild("RoundEnd").OnClientEvent:Connect(function(result)
	if result == "correct" then
		play("correct")
	else
		play("timeout")
	end
end)

Events:WaitForChild("WrongGuess").OnClientEvent:Connect(function()
	play("wrong")
end)

Events:WaitForChild("HeartUpdate").OnClientEvent:Connect(function(count)
	if count < 3 then
		play("heartLoss")
	end
end)

Events:WaitForChild("OpponentHeartUpdate").OnClientEvent:Connect(function(count)
	if count < 3 then
		play("heartLoss")
	end
end)

Events:WaitForChild("GameOver").OnClientEvent:Connect(function(_, youWon, isDraw)
	if isDraw then
		play("draw")
	elseif youWon then
		play("win")
	else
		play("lose")
	end
end)
