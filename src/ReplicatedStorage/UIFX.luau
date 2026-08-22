--[[
	UIFX.luau  (ModuleScript)
	----------------------------------------------------------------------------
	Place in: ReplicatedStorage.UIFX

	PURPOSE
	Reusable open/close / pop-in animations for GuiObjects. It scales the element
	via a child `UIScale` (so layout doesn't reflow) and handles environment FX:
	  * Camera FOV zoom (70 -> 82 when open, back to 70 on close).
	  * Background Lighting Blur (size 0 -> 18 when open, back to 0 on close).
	  * StatsPanel sliding UP when open, and BACK down when closed.

	USAGE
		local UIFX = require(ReplicatedStorage.UIFX)
		UIFX.popIn(myFrame)
		UIFX.popOut(myFrame)          -- hides it when done
		UIFX.staggerIn(listOfTiles)   -- staggered pop-in for a group
]]

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local camera = workspace.CurrentCamera
local BASE_FOV = 70
local OPEN_FOV = 82
local OPEN_BLUR_SIZE = 18

-- Ensure BlurEffect in Lighting
local blurEffect: BlurEffect = Lighting:FindFirstChild("GuiWindowBlur") :: BlurEffect
if not blurEffect or not blurEffect:IsA("BlurEffect") then
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "GuiWindowBlur"
	blurEffect.Size = 0
	blurEffect.Enabled = false
	blurEffect.Parent = Lighting
end

local openWindowCount = 0

local UIFX = {}

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

-- Applies environment FX when a GUI window opens
function UIFX.applyOpenFX()
	openWindowCount += 1
	if openWindowCount == 1 then
		-- Increase Camera FOV
		TweenService:Create(
			camera,
			TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ FieldOfView = OPEN_FOV }
		):Play()

		-- Enable and tween Lighting Blur
		blurEffect.Enabled = true
		TweenService:Create(
			blurEffect,
			TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = OPEN_BLUR_SIZE }
		):Play()

		-- Slide StatsPanel UP
		if _G.SetStatsPanelUp then
			_G.SetStatsPanelUp(true)
		end
	end
end

-- Restores environment FX when a GUI window closes
function UIFX.applyCloseFX()
	openWindowCount = math.max(0, openWindowCount - 1)
	if openWindowCount == 0 then
		-- Restore Camera FOV
		TweenService:Create(
			camera,
			TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ FieldOfView = BASE_FOV }
		):Play()

		-- Tween Blur back to 0 and disable
		local blurTween = TweenService:Create(
			blurEffect,
			TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = 0 }
		)
		blurTween:Play()
		blurTween.Completed:Connect(function()
			if openWindowCount == 0 then
				blurEffect.Enabled = false
			end
		end)

		-- Slide StatsPanel BACK DOWN
		if _G.SetStatsPanelUp then
			_G.SetStatsPanelUp(false)
		end
	end
end

-- Pop the element in (grows with a bouncy Back ease). Sets Visible = true.
function UIFX.popIn(gui: GuiObject, opts: any?)
	opts = opts or {}
	local scaleFrom = opts.scaleFrom or 0.6
	local duration = opts.duration or 0.28

	local s = ensureScale(gui)
	gui.Visible = true
	s.Scale = scaleFrom

	UIFX.applyOpenFX()

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

	UIFX.applyCloseFX()

	t.Completed:Connect(function()
		gui.Visible = false
		s.Scale = 1
	end)
	return t
end

-- Fade the element's transparency in (opaque -> transparent target).
function UIFX.fadeIn(gui: GuiObject, opts: any?)
	opts = opts or {}
	local duration = opts.duration or 0.3
	local target = opts.target or 0
	gui.Visible = true
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
