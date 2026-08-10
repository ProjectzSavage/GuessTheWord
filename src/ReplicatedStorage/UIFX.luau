--[[
	UIFX.luau  (ModuleScript)
	----------------------------------------------------------------------------
	Place in: ReplicatedStorage.UIFX

	PURPOSE
	Reusable open/close / pop-in animations for GuiObjects. It scales the element
	via a child `UIScale` (so layout doesn't reflow) and, for elements that have
	a transparent background, also fades them in/out.

	USAGE
		local UIFX = require(ReplicatedStorage.UIFX)
		UIFX.popIn(myFrame)
		UIFX.popOut(myFrame)          -- hides it when done
		UIFX.staggerIn(listOfTiles)   -- staggered pop-in for a group
]]

local TweenService = game:GetService("TweenService")

local UIFX = {}

-- Ensure a UIScale child exists on a GuiObject.
local function ensureScale(gui)
	local s = gui:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Parent = gui
	end
	return s
end

-- Pop the element in (grows with a bouncy Back ease). Sets Visible = true.
function UIFX.popIn(gui, opts)
	opts = opts or {}
	local scaleFrom = opts.scaleFrom or 0.6
	local duration = opts.duration or 0.28

	local s = ensureScale(gui)
	gui.Visible = true
	s.Scale = scaleFrom
	TweenService:Create(
		s,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

-- Shrink the element out, then set Visible = false.
function UIFX.popOut(gui, opts)
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
		gui.Visible = false
	end)
	return t
end

-- Fade the element's transparency in (opaque -> transparent target). Only
-- affects the element's own background; children keep theirs.
function UIFX.fadeIn(gui, opts)
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
-- Each element pops in one after another for a cascading effect.
function UIFX.staggerIn(elements, opts)
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
