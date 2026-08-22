--[[
	HoverFX.luau  (ModuleScript)
	----------------------------------------------------------------------------
	Place in: ReplicatedStorage.HoverFX

	PURPOSE
	A reusable, satisfying hover/pop effect for any GuiObject (ImageButtons,
	ImageLabels, TextButtons, Frames...). When the mouse cursor hovers over an
	element it quickly "pops" up (grows) with an overshoot bounce, and smoothly
	shrinks back when the cursor leaves.

	WHY UIScale?
	We animate a child `UIScale` instead of the element's `Size`. UIScale scales
	the visual WITHOUT changing the layout size, so tiles inside a UIGridLayout /
	UIListLayout won't reflow or jump their neighbors. This keeps a grid tidy and
	makes the pop feel much smoother.

	USAGE
		local HoverFX = require(ReplicatedStorage.HoverFX)
		HoverFX.applyTo(myButton)                       -- defaults
		HoverFX.applyTo(myButton, { scale = 1.25 })     -- stronger pop
		HoverFX.applyTo(myButton, { scale = 1.1, duration = 0.12 })
]]

local TweenService = game:GetService("TweenService")

local HoverFX = {}

local DEFAULT_SCALE = 1.18
local DEFAULT_DURATION = 0.18

-- Tween `scale.Scale` to `target`.
local function tweenScale(scale, target, duration)
	local tween = TweenService:Create(
		scale,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = target }
	)
	tween:Play()
	return tween
end

-- Apply a hover/pop effect to a GuiObject.
-- @param element - the GuiObject to affect.
-- @param opts    - optional { scale = number, duration = number }.
function HoverFX.applyTo(element, opts)
	opts = opts or {}
	local targetScale = opts.scale or DEFAULT_SCALE
	local duration = opts.duration or DEFAULT_DURATION

	-- Ensure a UIScale exists on the element (reuse if already present).
	local scale = element:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = element
	end

	element.MouseEnter:Connect(function()
		tweenScale(scale, targetScale, duration)
	end)
	element.MouseLeave:Connect(function()
		tweenScale(scale, 1, duration)
	end)
end

return HoverFX
