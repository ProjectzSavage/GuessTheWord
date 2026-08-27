--[[
	SFX.luau  (ModuleScript)  -- place in ReplicatedStorage
	----------------------------------------------------------------------------
	PURPOSE
	The game's sound effects. Any script can call:
	    SFX.play("letter")        -- on demand
	    SFX.play("uiPop")         -- etc.
	It ALSO auto-wires sounds to the game's RemoteEvents (countdown, round, etc.).

	FILL IN YOUR SOUNDS
	Use the FULL format "rbxassetid://117751546358455" (a bare number also
	works - the "rbxassetid://" prefix is added automatically).
	Leave unused ones as "". Countdown has separate 3 / 2 / 1 / GO! sounds
	(count3, count2, count1, go).

	BROKEN IDS
	At startup every filled-in id is validated (and preloaded). A dead/invalid
	asset (deleted, mistyped, not owned) warns ONCE with the key name:
	    [SFX] Failed to load sound 'shopOpen' (rbxassetid://...): ...
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local SFX = {}

-- ---------------------------------------------------------------------------
-- SOUND CONFIG - fill in the IDs you have. Use "rbxassetid://..." (or a bare
-- number - the prefix is added automatically).
-- ---------------------------------------------------------------------------
SFX.Sounds = {
	count3       = "rbxassetid://117751546358455", -- countdown "3"
	count2       = "rbxassetid://117751546358455", -- countdown "2"
	count1       = "rbxassetid://117751546358455", -- countdown "1"
	go           = "rbxassetid://117751546358455", -- "GO!" at round start
	uiPop        = "rbxassetid://70452176150315", -- GUI pops up after the game starts
	correct      = "rbxassetid://130206997868957", -- correct answer / reveal
	timeout      = "rbxassetid://117751546358455", -- round timed out
	wrong        = "rbxassetid://137327891291996", -- wrong full-length guess (with the shake)
	heartDanger  = "rbxassetid://139481207162657", -- about to lose a heart (last one / warning)
	heartLoss    = "", -- a heart blinks out and disappears
	heartRestore = "", -- a new round's hearts refresh
	win          = "rbxassetid://127039883737564", -- you win the match
	lose         = "rbxassetid://125623877509633", -- you lose the match
	draw         = "rbxassetid://86611831132015", -- the match was a draw
	letter       = "rbxassetid://106456870308007", -- a letter flies into the answer box
	hover        = "rbxassetid://139800881181209", -- hovering over a tile/clue (the classic hover)
	click        = "rbxassetid://139719503904449", -- clicking the Play vs Bot button
	cash         = "", -- cash reward lands on the reroll / any money gain
	cashRoll     = "", -- cash reward reroll spinning/cycling
	botSpawn     = "", -- the bot rig spawns in the chair
	botDespawn   = "", -- the bot despawns after the match
	winJingle    = "", -- victory fanfare after winning

	-- Commerce / feedback sounds
	shopOpen     = "", -- the Shop UI opens (separate sound from uiPop)
	guiOpen      = "", -- any GUI window opens (Shop / Rewards / Inventory)
	buttonHover  = "", -- hovering over ANY button (wired globally)
	robuxClick   = "", -- clicking ANY button that opens a Robux buy prompt
	purchase     = "", -- a Robux purchase just completed (plays with the confetti)
	notify       = "", -- a normal notification popup appears
	notifyError  = "", -- an ERROR notification (not enough coins, failed buy, ...)
}

-- SoundId accepts a bare number ("12345") or the full form
-- ("rbxassetid://12345") - normalize so both work.
local function normalizeId(raw)
	if string.find(raw, "^rbxassetid://", 1, true) then
		return raw
	end
	return "rbxassetid://" .. raw
end

-- Preload all provided sound IDs so they play instantly.
local function preloadSounds()
	local ids = {}
	for _, id in pairs(SFX.Sounds) do
		if type(id) == "string" and id ~= "" then
			table.insert(ids, normalizeId(id))
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

-- Validate every filled-in id (preloading it in the process). A dead/invalid
-- asset errors during the per-id preload, so we warn ONCE with the key name -
-- broken sounds are easy to find in the Output instead of the cryptic
-- "Failed to load sound ..." Roblox prints.
task.spawn(function()
	for key, raw in pairs(SFX.Sounds) do
		if type(raw) == "string" and raw ~= "" then
			local id = normalizeId(raw)
			local ok = pcall(function()
				ContentProvider:PreloadAsync({ id })
			end)
			if not ok then
				warn("[SFX] Failed to load sound '" .. tostring(key) .. "' (" .. id .. "): the asset is dead or invalid - replace that id in the SFX.Sounds table.")
			end
		end
	end
end)

-- Persistent base Sounds keep each clip loaded in memory, so playing a clone
-- starts INSTANTLY (no first-play load delay) while still allowing overlap.
local bases = {}

local function baseFor(id)
	local base = bases[id]
	if not base then
		base = Instance.new("Sound")
		base.Name = "SFXBase"
		base.SoundId = id
		base.Parent = SoundService
		-- Keep the clip loaded by leaving it parented (Engine caches it).
		bases[id] = base
	end
	return base
end

-- Play a sound by name. Clones a loaded base (so no load delay), plays it, and
-- cleans it up when it ends. Each call is an independent Sound -> they overlap.
function SFX.play(name, opts)
	opts = opts or {}
	local raw = SFX.Sounds[name]
	if type(raw) ~= "string" or raw == "" then
		return
	end
	local id = normalizeId(raw)

	local base = baseFor(id)
	local s = base:Clone()
	s.Parent = SoundService
	s.Volume = opts.volume or 0.6
	if opts.speed then
		s.PlaybackSpeed = opts.speed
	end

	local function cleanup()
		if s and s.Parent then
			s:Destroy()
		end
	end
	s.Ended:Connect(cleanup)

	s:Play()

	task.delay(10, cleanup) -- safety
end

preloadSounds()

-- ---------------------------------------------------------------------------
-- CONFETTI (celebration on purchase)
-- ---------------------------------------------------------------------------
local PlayersService = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 120),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(120, 255, 150),
	Color3.fromRGB(90, 180, 255),
	Color3.fromRGB(255, 140, 240),
	Color3.fromRGB(255, 255, 255),
}

local confettiGui = nil

-- Spawns a burst of falling, spinning, fading confetti across the whole
-- screen. Every piece cleans itself up when its fall finishes.
function SFX.confetti(count)
	local gui = confettiGui
	if not gui or not gui.Parent then
		gui = Instance.new("ScreenGui")
		gui.Name = "ConfettiGui"
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 100
		gui.ResetOnSpawn = false
		gui.Parent = PlayersService.LocalPlayer:WaitForChild("PlayerGui")
		confettiGui = gui
	end
	for i = 1, (count or 40) do
		task.spawn(function()
			local piece = Instance.new("Frame")
			piece.Size = UDim2.fromOffset(math.random(6, 12), math.random(8, 16))
			piece.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
			piece.BorderSizePixel = 0
			piece.Position = UDim2.new(math.random(), 0, -0.06, 0)
			piece.Rotation = math.random(0, 360)
			piece.Parent = gui
			local fall = TweenService:Create(
				piece,
				TweenInfo.new(math.random(14, 24) / 10 + 0.7, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
				{
					Position = piece.Position + UDim2.new(0, (math.random() - 0.5) * 260, 1.1, 0),
					Rotation = piece.Rotation + math.random(-540, 540),
					BackgroundTransparency = 1,
				}
			)
			fall:Play()
			fall.Completed:Connect(function()
				if piece.Parent then
					piece:Destroy()
				end
			end)
			task.delay(4, function()
				if piece.Parent then
					piece:Destroy()
				end
			end)
		end)
	end
end

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

-- Purchase celebration: special sound + confetti + a "Purchase Successful!"
-- notification (the server sends the product / reward name). The event is
-- created here if missing so the client never blocks on an old setup.
-- (The notification sound itself is played by the NotificationController,
-- based on the notification's kind.)
local PurchaseSuccess = Events:FindFirstChild("PurchaseSuccess")
if not PurchaseSuccess then
	PurchaseSuccess = Instance.new("RemoteEvent")
	PurchaseSuccess.Name = "PurchaseSuccess"
	PurchaseSuccess.Parent = Events
end
PurchaseSuccess.OnClientEvent:Connect(function(label)
	SFX.play("purchase")
	SFX.confetti(45)
	if _G.Notify then
		_G.Notify({
			title = "Purchase Successful!",
			message = (typeof(label) == "string" and label ~= "") and label or "Thanks for your purchase!",
			kind = "success",
			duration = 3,
		})
	end
end)

return SFX
