--[[
	SFX.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays all the game's sound effects on the right moments. Fill in your sound
	asset IDs in the SFX table below. Use the FULL format:
	    "rbxassetid://117751546358455"
	(both the prefix and the digits). Leave unused ones as "" (skipped).

	COUNTDOWN: separate sounds for 3, 2, 1 and GO! (fill each).
	  count3 = ...   count2 = ...   count1 = ...   go = ...

	HOW IT WORKS
	Each sound is parented under SoundService. On play we attach a `Loaded` handler
	and play when ready; the Sound cleans itself up when it ends. Sounds are also
	preloaded up front so they start instantly.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

-- ---------------------------------------------------------------------------
-- SOUND CONFIG - fill in the IDs you have. Use "rbxassetid://..." full form.
-- ---------------------------------------------------------------------------
local SFX = {
	count3      = "", -- countdown "3"
	count2      = "", -- countdown "2"
	count1      = "", -- countdown "1"
	go          = "", -- "GO!" at round start
	correct     = "", -- correct answer / reveal
	timeout     = "", -- round timed out
	wrong       = "", -- wrong full-length guess (with the shake)
	heartDanger = "", -- about to lose a heart (last one / warning)
	heartLoss   = "", -- a heart blinks out and disappears
	heartRestore= "", -- a new round's hearts refresh
	win         = "", -- you win the match
	lose        = "", -- you lose the match
	draw        = "", -- the match was a draw
	letter      = "", -- a letter flies into the answer box
	hover       = "", -- hovering over a tile/button
	click       = "", -- clicking the Play vs Bot button
	botSpawn    = "", -- the bot rig spawns in the chair
	botDespawn  = "", -- the bot despawns after the match
	winJingle   = "", -- victory fanfare after winning
	standUp     = "", -- player stands up at match end
	ragdoll     = "", -- loser ragdolls
}

-- ---------------------------------------------------------------------------
-- ENGINE (no need to edit below here)
-- ---------------------------------------------------------------------------
local Events = ReplicatedStorage:WaitForChild("Events")

-- Preload all provided sound IDs so they play instantly.
local function preloadSounds()
	local ids = {}
	for _, id in pairs(SFX) do
		if type(id) == "string" and id ~= "" then
			table.insert(ids, id)
		end
	end
	if #ids > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(ids)
			end)
		end)
	end
end

-- Play a sound by name. Waits for the clip to load, plays it, self-destructs.
local function play(name, opts)
	opts = opts or {}
	local id = SFX[name]
	if type(id) ~= "string" or id == "" then
		return
	end

	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = opts.volume or 0.6
	if opts.speed then
		s.PlaybackSpeed = opts.speed
	end
	s.Parent = SoundService

	local started = false
	local function cleanup()
		if s and s.Parent then
			s:Destroy()
		end
	end
	s.Ended:Connect(cleanup)

	-- Play once the clip is loaded (fresh Sounds have TimeLength 0 until loaded).
	if s.IsLoaded then
		s:Play()
	else
		s.Loaded:Connect(function()
			if not started then
				started = true
				s:Play()
			end
		end)
	end
	-- Safety cleanup in case Loaded never fires or the clip is very long.
	task.delay(8, cleanup)
end

preloadSounds()

-- ---------------------------------------------------------------------------
-- EVENT -> SOUND WIRING
-- ---------------------------------------------------------------------------
Events:WaitForChild("Countdown").OnClientEvent:Connect(function(n)
	if n == 3 then
		play("count3", { volume = 0.6 })
	elseif n == 2 then
		play("count2", { volume = 0.6 })
	elseif n == 1 then
		play("count1", { volume = 0.6 })
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

-- Heart sounds: on a loss play heartLoss; on reaching the last heart also play
-- heartDanger; on restore play heartRestore. Track state so it fires per change.
local lastHeartCount = 3
Events:WaitForChild("HeartUpdate").OnClientEvent:Connect(function(count)
	count = count or 0
	if count < lastHeartCount then
		play("heartLoss")
		if count <= 1 then
			play("heartDanger")
		end
	elseif count > lastHeartCount then
		play("heartRestore")
	end
	lastHeartCount = count
end)

local lastOppHeartCount = 3
Events:WaitForChild("OpponentHeartUpdate").OnClientEvent:Connect(function(count)
	count = count or 0
	if count < lastOppHeartCount then
		play("heartLoss")
	elseif count > lastOppHeartCount then
		play("heartRestore")
	end
	lastOppHeartCount = count
end)

Events:WaitForChild("GameOver").OnClientEvent:Connect(function(_, youWon, isDraw)
	if isDraw then
		play("draw")
	elseif youWon then
		play("win")
		play("winJingle")
	else
		play("lose")
	end
end)
