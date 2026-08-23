--[[
	DynamicEffectsController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Provides automatic continuous live visual effects for UI elements via
	CollectionService Tags or Attributes:

	1. CONTINUOUS ICON ROTATION / SWAY (Left & Right):
	   * Add Tag: "RotateWiggle", "IconSway", "Sway", or "Wiggle"
	   * OR Add Attribute: `RotateWiggle = true` or `Sway = true`
	   * Optional Attributes:
	     - `SwayAngle` (number, default: 8 degrees)
	     - `SwaySpeed` (number, default: 2.5)

	2. CONTINUOUS ANIMATED UIGRADIENT (Smooth continuous movement like Sway, no snap/reset):
	   * Add Tag to UIGradient: "AnimatedGradient", "GradientScroll", "LiveGradient"
	   * OR Add Attribute to UIGradient: `AnimatedGradient = true` or `LiveGradient = true`
	   * Optional Attributes on UIGradient:
	     - `GradientSpeed` (number, default: 1.2)
	     - `GradientDirection` (string: "Up", "Down", "Diagonal", default: "Up")
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local swayObjects: { [GuiObject]: { speed: number, maxAngle: number, phase: number, baseRot: number } } = {}
local gradientObjects: { [UIGradient]: { speed: number, direction: string, phase: number } } = {}

-- ============================================================================
-- 1. ICON SWAY / ROTATE (Left & Right continuously)
-- ============================================================================
local function registerSway(guiObj: Instance)
	if not guiObj:IsA("GuiObject") then return end
	if swayObjects[guiObj] then return end

	local speed = tonumber(guiObj:GetAttribute("SwaySpeed")) or 2.5
	local maxAngle = tonumber(guiObj:GetAttribute("SwayAngle")) or 8
	local phase = tonumber(guiObj:GetAttribute("SwayPhase")) or (math.random() * math.pi * 2)
	local baseRot = guiObj.Rotation

	swayObjects[guiObj] = {
		speed = speed,
		maxAngle = maxAngle,
		phase = phase,
		baseRot = baseRot,
	}

	guiObj.AncestryChanged:Connect(function(_, parent)
		if not parent then
			swayObjects[guiObj] = nil
		end
	end)
end

local function unregisterSway(guiObj: Instance)
	if not guiObj:IsA("GuiObject") then return end
	local info = swayObjects[guiObj]
	if info then
		guiObj.Rotation = info.baseRot
		swayObjects[guiObj] = nil
	end
end

-- ============================================================================
-- 2. CONTINUOUS ANIMATED UIGRADIENT (Smooth continuous flow without resetting)
-- ============================================================================
local function registerGradient(grad: Instance)
	if not grad:IsA("UIGradient") then return end
	if gradientObjects[grad] then return end

	local speed = tonumber(grad:GetAttribute("GradientSpeed")) or 1.2
	local direction = tostring(grad:GetAttribute("GradientDirection") or "Up")
	local phase = tonumber(grad:GetAttribute("GradientPhase")) or (math.random() * math.pi * 2)

	gradientObjects[grad] = {
		speed = speed,
		direction = direction,
		phase = phase,
	}

	grad.AncestryChanged:Connect(function(_, parent)
		if not parent then
			gradientObjects[grad] = nil
		end
	end)
end

local function unregisterGradient(grad: Instance)
	if not grad:IsA("UIGradient") then return end
	gradientObjects[grad] = nil
end

-- ============================================================================
-- TAGS & ATTRIBUTE LISTENERS
-- ============================================================================
local SWAY_TAGS = { "RotateWiggle", "IconSway", "Sway", "Wiggle" }
local GRADIENT_TAGS = { "AnimatedGradient", "GradientScroll", "LiveGradient", "ShimmerGradient" }

for _, tag in ipairs(SWAY_TAGS) do
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		registerSway(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(registerSway)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unregisterSway)
end

for _, tag in ipairs(GRADIENT_TAGS) do
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		registerGradient(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(registerGradient)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unregisterGradient)
end

local function inspectElement(inst: Instance)
	if inst:IsA("GuiObject") then
		if inst:GetAttribute("RotateWiggle") == true
			or inst:GetAttribute("Sway") == true
			or inst:GetAttribute("Wiggle") == true then
			registerSway(inst)
		end
	end

	if inst:IsA("UIGradient") then
		if inst:GetAttribute("AnimatedGradient") == true
			or inst:GetAttribute("Scroll") == true
			or inst:GetAttribute("LiveGradient") == true
			or inst:GetAttribute("GradientScroll") == true then
			registerGradient(inst)
		end
	end
end

for _, d in ipairs(playerGui:GetDescendants()) do
	inspectElement(d)
end

playerGui.DescendantAdded:Connect(inspectElement)

-- ============================================================================
-- MAIN HEARTBEAT RENDER LOOP
-- ============================================================================
RunService.Heartbeat:Connect(function()
	local now = os.clock()

	-- 1. Rotate Sway Icons Left & Right Continuously
	for obj, info in pairs(swayObjects) do
		if obj and obj.Parent then
			local angleOffset = math.sin(now * info.speed + info.phase) * info.maxAngle
			obj.Rotation = info.baseRot + angleOffset
		else
			swayObjects[obj] = nil
		end
	end

	-- 2. Animate UIGradients Continuously (Sine-wave smooth oscillation, no sudden resets)
	for grad, info in pairs(gradientObjects) do
		if grad and grad.Parent then
			-- Smooth continuous oscillation back and forth across [-0.75, 0.75]
			local offsetValue = math.sin(now * info.speed + info.phase) * 0.75

			if info.direction == "Diagonal" then
				grad.Offset = Vector2.new(-offsetValue, offsetValue)
			elseif info.direction == "Horizontal" then
				grad.Offset = Vector2.new(offsetValue, 0)
			else
				-- Default: Moves Up & Down continuously
				grad.Offset = Vector2.new(0, -offsetValue)
			end
		else
			gradientObjects[grad] = nil
		end
	end
end)

_G.DynamicEffects = {
	sway = registerSway,
	unsway = unregisterSway,
	animateGradient = registerGradient,
	unanimateGradient = unregisterGradient,
}
