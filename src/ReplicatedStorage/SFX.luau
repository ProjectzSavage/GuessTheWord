--[[
	SFX.luau  (ModuleScript)  -- place in ReplicatedStorage
	----------------------------------------------------------------------------
	PURPOSE
	The game's sound effects. Any script can call:
	    SFX.play("letter")        -- on demand
	    SFX.play("uiPop")         -- etc.
	It ALSO auto-wires sounds to the game's RemoteEvents (countdown, round, etc.).

	FILL IN YOUR SOUNDS
	Use the FULL format "rbxassetid://117751546358455". Leave unused ones as "".
	Countdown has separate 3 / 2 / 1 / GO! sounds (count3, count2, count1, go).
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local SFX = {}

-- ---------------------------------------------------------------------------
-- SOUND CONFIG - fill in the IDs you have. Use "rbxassetid://..." full form.
-- ---------------------------------------------------------------------------
SFX.Sounds = {
	count3       = "", -- countdown "3"
	count2       = "", -- countdown "2"
	count1       = "", -- countdown "1"
	go           = "", -- "GO!" at round start
	uiPop        = "", -- GUI pops up after the game starts
	correct      = "", -- correct answer / reveal
	timeout      = "", -- round timed out
	wrong        = "", -- wrong full-length guess (with the shake)
	heartDanger  = "", -- about to lose a heart (last one / warning)
	heartLoss    = "", -- a heart blinks out and disappears
	heartRestore = "", -- a new round's hearts refresh
	win          = "", -- you win the match
	lose         = "", -- you lose the match
	draw         = "", -- the match was a draw
	letter       = "", -- a letter flies into the answer box
	hover        = "", -- hovering over a tile/button
	click        = "", -- clicking the Play vs Bot button
	botSpawn     = "", -- the bot rig spawns in the chair
	botDespawn   = "", -- the bot despawns after the match
	winJingle    = "", -- victory fanfare after winning
}

-- Preload all provided sound IDs so they play instantly.
local function preloadSounds()
	local ids = {}
	for _, id in pairs(SFX.Sounds) do
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

-- Play a sound by name. Each call makes a NEW independent Sound so clips can
-- overlap. Roblox queues playback until the clip is loaded, so we call :Play()
-- immediately (no Loaded race) and clean up when it ends.
function SFX.play(name, opts)
	opts = opts or {}
	local id = SFX.Sounds[name]
	if type(id) ~= "string" or id == "" then
		return
	end

	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = opts.volume or 0.6
	if opts.speed then
		s.PlaybackSpeed = opts.speed
	end
	-- Do not roll off for UI sounds (they're close to the camera anyway).
	s.Parent = SoundService

	local function cleanup()
		if s and s.Parent then
			s:Destroy()
		end
	end
	s.Ended:Connect(cleanup)

	-- Play immediately; the engine starts playback once loaded. This guarantees
	-- every call produces audible sound and overlapping sounds overlap.
	s:Play()

	task.delay(10, cleanup) -- safety (longer than before)
end

preloadSounds()

-- ---------------------------------------------------------------------------
-- AUTO-WIRED GAME EVENT SOUNDS
-- ---------------------------------------------------------------------------
local Events = ReplicatedStorage:WaitForChild("Events")

Events:WaitForChild("Countdown").OnClientEvent:Connect(function(n)
	if n == 3 then
		SFX.play("count3", { volume = 0.6 })
	elseif n == 2 then
		SFX.play("count2", { volume = 0.6 })
	elseif n == 1 then
		SFX.play("count1", { volume = 0.6 })
	end
end)

Events:WaitForChild("RoundStart").OnClientEvent:Connect(function()
	SFX.play("go")
end)

Events:WaitForChild("RoundEnd").OnClientEvent:Connect(function(result)
	if result == "correct" then
		SFX.play("correct")
	else
		SFX.play("timeout")
	end
end)

Events:WaitForChild("WrongGuess").OnClientEvent:Connect(function()
	SFX.play("wrong")
end)

-- Heart sounds: on a loss play heartLoss; on reaching the last heart also play
-- heartDanger; on restore play heartRestore.
local lastHeartCount = 3
Events:WaitForChild("HeartUpdate").OnClientEvent:Connect(function(count)
	count = count or 0
	if count < lastHeartCount then
		SFX.play("heartLoss")
		if count <= 1 then
			SFX.play("heartDanger")
		end
	elseif count > lastHeartCount then
		SFX.play("heartRestore")
	end
	lastHeartCount = count
end)

local lastOppHeartCount = 3
Events:WaitForChild("OpponentHeartUpdate").OnClientEvent:Connect(function(count)
	count = count or 0
	if count < lastOppHeartCount then
		SFX.play("heartLoss")
	elseif count > lastOppHeartCount then
		SFX.play("heartRestore")
	end
	lastOppHeartCount = count
end)

Events:WaitForChild("GameOver").OnClientEvent:Connect(function(_, youWon, isDraw)
	if isDraw then
		SFX.play("draw")
	elseif youWon then
		SFX.play("win")
		SFX.play("winJingle")
	else
		SFX.play("lose")
	end
end)

return SFX
