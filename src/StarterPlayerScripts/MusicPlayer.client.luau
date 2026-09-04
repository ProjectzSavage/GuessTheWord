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

	Each player hears their own music (it's a LocalScript), and the button
	only pauses/resumes for that player.
]]

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")

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
if button and not button:IsA("ButtonBase") then
	button = nil
end
if not button then
	warn("[MusicPlayer] No ImageButton named 'Music' found inside GameUI - the music "
		.. "will still play, but there is no pause button.")
end

local audio = Instance.new("Audio")
audio.Name = "MusicAudio"
audio.Volume = VOLUME
audio.Loops = false -- this script advances the playlist manually
audio.Parent = playerGui

local index = 1
local paused = false
local deadInARow = 0

local function setButtonImage()
	if not button then
		return
	end
	local icon = paused and MUTE_ICON or PLAY_ICON
	if icon ~= "" then
		button.Image = icon
	end
end

-- Load + start track #i. Preloading first means a DEAD id fails instantly
-- (bad ids throw) and gets skipped, instead of stalling the whole playlist;
-- good ids start without a loading hitch.
local function playTrack(i)
	index = i
	local url = urls[i]
	local ok = pcall(function()
		ContentProvider:PreloadAsync({ url })
	end)
	if not ok then
		deadInARow = deadInARow + 1
		if deadInARow >= #urls then
			warn("[MusicPlayer] None of the SONG_IDS could be loaded - check the ids "
				.. "in the CONFIG block.")
			return
		end
		task.defer(playTrack, i % #urls + 1)
		return
	end
	deadInARow = 0
	audio.SoundId = url
	if paused then
		-- Load the track while staying paused: Play kicks the load off,
		-- Pause holds it at position 0. The button's Resume() starts it.
		audio:Play()
		audio:Pause()
	else
		audio:Play()
	end
end

-- A song finished: advance to the next one (wraps to the first).
audio.Played:Connect(function()
	if paused then
		return
	end
	playTrack(index % #urls + 1)
end)

if button then
	button.Activated:Connect(function()
		paused = not paused
		if paused then
			if audio.IsPlaying then
				audio:Pause()
			end
		elseif audio.IsLoaded then
			audio:Resume()
		else
			-- A track was loaded while paused and never started.
			audio:Play()
		end
		setButtonImage()
	end)
	setButtonImage()
end

task.defer(playTrack, 1)
