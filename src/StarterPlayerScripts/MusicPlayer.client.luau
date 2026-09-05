--[[
	MusicPlayer.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Background music that cycles through your list:
	  * Plays SONG_IDS in order.
	  * When a song finishes, the next one starts.
	  * When the last one finishes, it loops back to the first (forever).
	  * The "Music" ImageButton in GameUI toggles pause / resume.

	YOU DO:
	  1. Paste your music asset ids into SONG_IDS below (plain numbers or
	     "rbxassetid://..." strings - both work).
	  2. (Optional) set PLAY_ICON / MUTE_ICON to the button images you want.
	     Leave "" to keep whatever image you set on the button in Studio.
	  3. Make sure your GameUI has an ImageButton named exactly "Music".

	2026 ENGINE NOTE
	  The old `Audio` class was removed from the current engine, so this uses
	  the new audio system: AudioPlayer -> Wire -> AudioDeviceOutput (the
	  official pattern). Each player hears their own music (it's a
	  LocalScript), and the button only pauses/resumes for that player.
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-------------------------------------------------------------------------------
-- CONFIG (edit me)
-------------------------------------------------------------------------------
local SONG_IDS = {
	0, -- <- your music id #1
	0, -- <- your music id #2
	0, -- <- your music id #3
}

-- Button images (optional - "" = keep the image you set in Studio).
local PLAY_ICON = "" -- image shown while music PLAYS (e.g. "rbxassetid://123456")
local MUTE_ICON = "" -- image shown while music is PAUSED (e.g. "rbxassetid://654321")

local VOLUME = 0.5   -- 0 = silent, 1 = full

-------------------------------------------------------------------------------
-- SET-UP
-------------------------------------------------------------------------------
local function toAssetId(id)
	local s = tostring(id)
	if s:match("^rbxassetid://") then
		return s
	end
	if s:match("^%d+$") and s ~= "0" then -- 0 = "not filled in yet"
		return "rbxassetid://" .. s
	end
	return nil
end

-- Normalize the playlist: keep only valid ids.
local urls = {}
for _, id in ipairs(SONG_IDS) do
	local u = toAssetId(id)
	if u then
		table.insert(urls, u)
	end
end

if #urls == 0 then
	warn("[MusicPlayer] SONG_IDS is empty (or every entry is invalid) - paste your "
		.. "music ids into the CONFIG block at the top to start the music.")
	return
end

-- The button is needed for the pause toggle, but the music itself plays
-- even without it (we just tell you in Output).
local gui = playerGui:WaitForChild("GameUI", 15)
local button = gui and (gui:FindFirstChild("Music") or gui:FindFirstChild("Music", true))
if button and not button:IsA("GuiButton") then
	button = nil
end
if not button then
	warn("[MusicPlayer] No button named 'Music' found inside GameUI - the music "
		.. "will still play, but there is no pause button.")
end

-- Build the new-audio graph (2026 engine):
--   AudioPlayer (the track) --Wire--> AudioDeviceOutput (your speakers).
local audioPlayer, deviceOutput, wire
local okGraph, graphErr = pcall(function()
	audioPlayer = Instance.new("AudioPlayer")
	deviceOutput = Instance.new("AudioDeviceOutput")
	wire = Instance.new("Wire")
end)
if not okGraph or not audioPlayer then
	warn("[MusicPlayer] The new audio system (AudioPlayer) is unavailable in this "
		.. "engine (" .. tostring(graphErr) .. ") - music disabled.")
	return
end

audioPlayer.Name = "MusicAudio"
audioPlayer.Volume = VOLUME
audioPlayer.Looping = false -- this script advances the playlist manually
audioPlayer.Parent = playerGui

deviceOutput.Name = "MusicDeviceOutput"
deviceOutput.Parent = playerGui

wire.Name = "MusicWire"
wire.Parent = playerGui
wire.SourceInstance = audioPlayer
wire.TargetInstance = deviceOutput

-- The 2026 engine names the asset property `Asset`; `AssetId` is the
-- classic name (deprecated but still accepted) - try the new one first.
local function setAsset(pl, url)
	local ok = pcall(function()
		pl.Asset = url
	end)
	if not ok then
		pl.AssetId = url
	end
end

-- How long to wait for a track to load / start before calling it dead.
local READY_TIMEOUT = 8
local START_TIMEOUT = 8

local index = 1
local paused = false
local savedPosition = 0
local deadInARow = 0
local finishedAll = false

local function setButtonImage()
	if not button then
		return
	end
	local icon = paused and MUTE_ICON or PLAY_ICON
	if icon ~= "" then
		button.Image = icon
	end
end

-- Load + start track #i. A dead id never becomes Ready, so bad ids get
-- skipped (with one warn if the WHOLE list is dead) instead of stalling
-- the playlist. Yields while waiting.
local function playTrack(i)
	if finishedAll then
		return
	end
	index = i
	savedPosition = 0
	local url = urls[i]
	setAsset(audioPlayer, url)

	-- 1) Wait for the asset to become ready.
	local ok = true
	local deadline = os.clock() + READY_TIMEOUT
	while not audioPlayer.IsReady do
		if os.clock() > deadline or index ~= i then
			ok = false
			break
		end
		task.wait(0.1)
	end

	-- 2) Start it (unless paused) and confirm it actually begins playing.
	if ok and not paused then
		audioPlayer:Play()
		local startDeadline = os.clock() + START_TIMEOUT
		while not audioPlayer.IsPlaying do
			if os.clock() > startDeadline or index ~= i or paused then
				break
			end
			task.wait(0.05)
		end
		if not audioPlayer.IsPlaying then
			ok = false
		end
	end

	if not ok then
		if index ~= i or paused then
			return -- superseded or paused mid-load - nothing to fix here
		end
		deadInARow = deadInARow + 1
		if deadInARow >= #urls then
			finishedAll = true
			warn("[MusicPlayer] None of the SONG_IDS could be loaded - check the ids "
				.. "in the CONFIG block.")
			return
		end
		task.defer(playTrack, i % #urls + 1)
		return
	end
	deadInARow = 0
end

-- A song finished: advance to the next one (wraps to the first).
audioPlayer.Ended:Connect(function()
	if paused or finishedAll then
		return
	end
	task.defer(playTrack, index % #urls + 1)
end)

if button then
	button.Activated:Connect(function()
		paused = not paused
		if paused then
			if audioPlayer.IsPlaying then
				savedPosition = audioPlayer.TimePosition
				audioPlayer:Stop()
			end
		elseif not audioPlayer.IsPlaying then
			if audioPlayer.IsReady then
				-- Resume where we paused (TimePosition restore may be a
				-- no-op on engines where it's read-only - then it just
				-- restarts the track, which is fine).
				pcall(function()
					audioPlayer.TimePosition = savedPosition
				end)
				audioPlayer:Play()
			else
				-- Nothing loaded yet (paused mid-load) - redo the load.
				task.defer(playTrack, index)
			end
		end
		setButtonImage()
	end)
	setButtonImage()
end

-- Respawn guard: if the audio stops while the character is dead (e.g. the
-- player's rig gets replaced mid-track), restart the CURRENT track once the
-- new character has arrived - instead of the playlist dying forever.
player.CharacterAdded:Connect(function()
	if paused or finishedAll then
		return
	end
	task.wait(1)
	if audioPlayer and audioPlayer.Parent and not audioPlayer.IsPlaying then
		task.defer(playTrack, index)
	end
end)

task.defer(playTrack, 1)
