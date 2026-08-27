--[[
	UIFX.luau  (ModuleScript)
	----------------------------------------------------------------------------
	Place in: ReplicatedStorage.UIFX

	PURPOSE
	Reusable open/close / pop-in animations for GuiObjects, plus the SINGLE
	owner of the environment FX:
	  * Camera FOV (zooms in while a window or match cinematic is active).
	  * Background Lighting Blur.
	  * StatsPanel sliding UP when a window opens, BACK DOWN when it closes.
	  * DailyQuestsF collapse (state-memory) via _G.SetQuestsHiddenByGui.

	DESIGN — why the screen can no longer get stuck blurred / zoomed:
	The FX state is DERIVED from its inputs every time one of them changes.
	It is NEVER incremented/decremented with a counter:

	    input 1: cinematic level  (0 idle / 1 countdown / 2 in-play)  <- match
	    input 2: registered open windows (Shop / Rewards / Inventory) <- windows
	    input 3: temporary FOV boost (win celebration punch)

	target blur = max(cinematic.blur, window.blur)
	target FOV  = base + max(cinematic.fov, window.fov, boost), capped at 90
	panel/quests up = (any registered window is open)

	Because the target is always recomputed from the actual state:
	  * opening the same window twice is a no-op (no double count),
	  * closing an already-closed window is a no-op (no stray decrement),
	  * NO event order can leave the screen blurred or zoomed in,
	  * match frames (PuzzleArea, InteractionFrame, DifficultySelector, ...)
	    animate WITHOUT ever touching the environment FX — popIn/popOut are
	    pure animation. (This is what made the screen blur + StatsPanel slide
	    up the moment a player simply sat in a chair.)

	USAGE
		local UIFX = require(ReplicatedStorage.UIFX)

		-- pure animation (no FX side effects) — used by match flow:
		UIFX.popIn(frame)
		UIFX.popOut(frame)          -- hides it when done
		UIFX.staggerIn(listOfTiles)

		-- window WITH environment FX — used by Shop / Rewards / Inventory:
		UIFX.openWindow(frame)
		UIFX.closeWindow(frame)

		-- match cinematic (called by InputHandler):
		UIFX.setCinematic(1)
		UIFX.setFovBoost(14)
]]

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local SFX = require(script.Parent:WaitForChild("SFX"))

local BASE_FOV_DEFAULT = 70
local WINDOW_FOV_DELTA = 12  -- 70 -> 82 while a window is open
local WINDOW_BLUR = 18

-- Match-flow cinematic presets (same feel as the old InputHandler cinematic).
local CINEMATIC = {
	[0] = { blur = 0,  fov = 0 },  -- normal
	[1] = { blur = 6,  fov = 3 },  -- countdown
	[2] = { blur = 12, fov = 9 },  -- round in-play
}

-- ONE shared BlurEffect for the whole game. (InputHandler used to grab/create
-- its own — two systems tweening blur independently is part of what left the
-- screen stuck.)
local blurEffect = Lighting:FindFirstChild("GuiWindowBlur")
if not blurEffect or not blurEffect:IsA("BlurEffect") then
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "GuiWindowBlur"
	blurEffect.Size = 0
	blurEffect.Enabled = false
	blurEffect.Parent = Lighting
end

-- Defensively reset the effect on load: a previously stuck state (Size > 0 /
-- Enabled = true) could have been saved straight into the place from Studio.
blurEffect.Size = 0
blurEffect.Enabled = false

local UIFX = {}

-------------------------------------------------------------------------------
-- STATE (single source of truth)
-------------------------------------------------------------------------------
local baseFOV = nil
local cinematicLevel = 0
local fovBoost = 0
local windows = {}     -- gui -> true (registered via openWindow/closeWindow)
local watchers = {}    -- gui -> { connections }
local windowOpenCount = 0

-- Capture the resting FOV as early as possible so the first refresh can't
-- bake a mid-tween value in as the "base".
local cam0 = workspace.CurrentCamera
if cam0 then
	baseFOV = cam0.FieldOfView
end

local lastApplied = {
	blur = 0,
	fov = (cam0 and cam0.FieldOfView) or BASE_FOV_DEFAULT,
	panelUp = false,
	questsHidden = false,
	quickShifted = false,
}

local function getCamera()
	return workspace.CurrentCamera
end

local function getBaseFov()
	if baseFOV == nil then
		local cam = getCamera()
		baseFOV = cam and cam.FieldOfView or BASE_FOV_DEFAULT
	end
	return baseFOV
end

-------------------------------------------------------------------------------
-- GUI HELPERS
-------------------------------------------------------------------------------
-- Ensure a UIScale child exists on a GuiObject.
local function ensureScale(gui: GuiObject): UIScale
	local s = gui:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "UIScale"
		s.Parent = gui
	end
	return s
end

local function windowIsOpen(gui)
	if not gui or not gui.Parent then
		return false
	end
	if gui:IsA("LayerCollector") then
		return gui.Enabled
	end
	return gui.Visible
end

-------------------------------------------------------------------------------
-- FX ENGINE
-------------------------------------------------------------------------------
local function syncWindowCount()
	windowOpenCount = 0
	for gui in pairs(windows) do
		if windowIsOpen(gui) then
			windowOpenCount += 1
		end
	end
end

local function applyTargets(t)
	local cam = getCamera()

	-- Camera FOV
	if cam and t.fov ~= lastApplied.fov then
		lastApplied.fov = t.fov
		TweenService:Create(
			cam,
			TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ FieldOfView = t.fov }
		):Play()
	end

	-- Lighting blur
	if t.blur > 0 then
		blurEffect.Enabled = true
		if t.blur ~= lastApplied.blur then
			lastApplied.blur = t.blur
			TweenService:Create(
				blurEffect,
				TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Size = t.blur }
			):Play()
		end
	elseif lastApplied.blur > 0 then
		lastApplied.blur = 0
		local done = TweenService:Create(
			blurEffect,
			TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = 0 }
		)
		done:Play()
		done.Completed:Connect(function()
			if lastApplied.blur == 0 then
				blurEffect.Enabled = false
			end
		end)
	end

	-- StatsPanel slide (windows only — NOT the match cinematic).
	-- Only mark as applied once the handler actually ran (it may load a frame
	-- later; the next refresh will retry then).
	if lastApplied.panelUp ~= t.panelUp and _G.SetStatsPanelUp then
		_G.SetStatsPanelUp(t.panelUp)
		lastApplied.panelUp = t.panelUp
	end

	-- DailyQuestsF collapse with state-memory (windows only)
	if lastApplied.questsHidden ~= t.questsHidden and _G.SetQuestsHiddenByGui then
		_G.SetQuestsHiddenByGui(t.questsHidden)
		lastApplied.questsHidden = t.questsHidden
	end

	-- QuickPlay button slides down while a window is open, back up on close
	-- (windows only — NOT the match cinematic).
	if lastApplied.quickShifted ~= t.quickShifted and _G.SetQuickPlayShiftedByGui then
		_G.SetQuickPlayShiftedByGui(t.quickShifted)
		lastApplied.quickShifted = t.quickShifted
	end
end

-- Recompute the FX targets from the current inputs and tween to them.
-- Idempotent: if nothing changed, nothing moves.
local function refresh()
	local cine = CINEMATIC[cinematicLevel] or CINEMATIC[0]
	local winOn = windowOpenCount > 0
	local targetBlur = math.max(cine.blur, winOn and WINDOW_BLUR or 0)
	local targetFov = math.min(
		getBaseFov() + math.max(cine.fov, winOn and WINDOW_FOV_DELTA or 0, fovBoost),
		90
	)
	applyTargets({
		blur = targetBlur,
		fov = targetFov,
		panelUp = winOn,
		questsHidden = winOn,
		quickShifted = winOn,
	})
end

-------------------------------------------------------------------------------
-- WINDOW REGISTRATION (Shop / Rewards / Inventory)
-------------------------------------------------------------------------------
-- Self-healing watcher: no matter HOW a registered window's visibility changes
-- (API call, direct property set, ...), the FX state re-syncs to reality.
local function watchWindow(gui)
	if watchers[gui] then
		return
	end
	local conns = {}
	local onFlip = function()
		if windows[gui] then
			syncWindowCount()
			refresh()
		end
	end
	if gui:IsA("LayerCollector") then
		table.insert(conns, gui:GetPropertyChangedSignal("Enabled"):Connect(onFlip))
	else
		table.insert(conns, gui:GetPropertyChangedSignal("Visible"):Connect(onFlip))
	end
	table.insert(conns, gui.AncestryChanged:Connect(function()
		if not gui.Parent then
			for _, c in conns do
				c:Disconnect()
			end
			watchers[gui] = nil
			if windows[gui] then
				windows[gui] = nil
				syncWindowCount()
				refresh()
			end
		end
	end))
	watchers[gui] = conns
end

-- Open `gui` as an FX window: animates it in and applies the environment FX.
-- IDEMPOTENT: calling it while the window is already open does nothing, so a
-- stray double-open can never stack FX state (the old counter stuck then).
function UIFX.openWindow(gui, opts)
	if not gui or not gui:IsA("GuiObject") then
		return nil
	end
	if not windows[gui] then
		windows[gui] = true
		watchWindow(gui)
	end
	if windowIsOpen(gui) then
		return nil -- already open
	end
	gui.Visible = true
	SFX.play("guiOpen") -- the "GUI opened" sound (Shop / Rewards / Inventory)
	syncWindowCount()
	refresh()
	return UIFX.popIn(gui, opts)
end

-- Close `gui`: animates it out. The FX releases as soon as it actually becomes
-- invisible (the watcher) — and if it's already closed this is a no-op, so a
-- stray close can never release FX that another window still needs.
function UIFX.closeWindow(gui)
	if not gui or not gui:IsA("GuiObject") then
		return nil
	end
	if not windowIsOpen(gui) then
		return nil -- already closed
	end
	if not windows[gui] then
		windows[gui] = true
		watchWindow(gui)
	end
	return UIFX.popOut(gui)
end

-- Register `gui` as an FX window WITHOUT animating it (for GUIs that are
-- shown/hidden by other code, like the match's PuzzleArea). From then on the
-- environment FX — StatsPanel slide up, DailyQuestsF collapse, blur/FOV merge
-- — follows its visibility with EXACTLY the same reaction as opening the
-- Shop, and eases back when it hides.
function UIFX.registerWindow(gui)
	if not gui or not gui:IsA("GuiObject") then
		return
	end
	if not windows[gui] then
		windows[gui] = true
		watchWindow(gui)
		syncWindowCount()
		refresh()
	end
end

-- Match-flow cinematic level (0 = idle, 1 = countdown, 2 = round in-play).
-- Merges with window FX — whichever needs more wins, and everything eases
-- back automatically when the match ends.
function UIFX.setCinematic(level)
	level = level or 0
	if not CINEMATIC[level] then
		level = 0
	end
	if level ~= cinematicLevel then
		cinematicLevel = level
		refresh()
	end
end

-- Temporary FOV punch (win celebration). Merges with everything else, so it
-- can never leave the camera zoomed in either.
function UIFX.setFovBoost(value)
	local v = tonumber(value) or 0
	if v ~= fovBoost then
		fovBoost = v
		refresh()
	end
end

-------------------------------------------------------------------------------
-- PURE ANIMATION (no FX side effects — match frames use these)
-------------------------------------------------------------------------------

-- Pop the element in (grows with a bouncy Back ease). Sets Visible = true.
function UIFX.popIn(gui: GuiObject, opts: any?)
	opts = opts or {}
	local scaleFrom = opts.scaleFrom or 0.6
	local duration = opts.duration or 0.28

	local s = ensureScale(gui)
	if not gui:IsA("LayerCollector") then
		gui.Visible = true
	end
	s.Scale = scaleFrom

	local t = TweenService:Create(
		s,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	t:Play()
	return t
end

-- Shrink the element out, then set Visible = false.
function UIFX.popOut(gui: GuiObject, opts: any?)
	opts = opts or {}
	local duration = opts.duration or 0.18
	local targetScale = opts.scaleTo or 0

	local s = ensureScale(gui)
	local t = TweenService:Create(
		s,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Scale = targetScale }
	)
	t:Play()

	t.Completed:Connect(function()
		if not gui:IsA("LayerCollector") then
			gui.Visible = false
		end
		s.Scale = 1
	end)
	return t
end

-- Fade the element's transparency in (opaque -> transparent target).
function UIFX.fadeIn(gui: GuiObject, opts: any?)
	opts = opts or {}
	local duration = opts.duration or 0.3
	local target = opts.target or 0
	if not gui:IsA("LayerCollector") then
		gui.Visible = true
	end
	TweenService:Create(
		gui,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = target }
	):Play()
end

-- Staggered pop-in for a list of tiles (used for the scrambled-bank intro).
function UIFX.staggerIn(elements: { GuiObject }, opts: any?)
	opts = opts or {}
	local duration = opts.duration or 0.24
	local stagger = opts.stagger or 0.05
	local scaleFrom = opts.scaleFrom or 0
	local index = 0
	for _, el in elements do
		index = index + 1
		local s = ensureScale(el)
		s.Scale = scaleFrom
		task.delay(index * stagger, function()
			if el and el.Parent then
				TweenService:Create(
					s,
					TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }
				):Play()
			end
		end)
	end
end

return UIFX
