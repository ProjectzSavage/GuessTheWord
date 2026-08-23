--[[
	ButtonsController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Wires the "Buttons" ScreenGui -> Features frame:
	  * Inventory  -> opens the chair inventory (via _G.InventoryAPI).
	  * Rewards    -> opens the RewardsF window (via _G.RewardsAPI).
	  * Shop       -> opens the ShopF window (via _G.ShopAPI) + looping pulse.

	MUTUAL EXCLUSION:
	Opening any of the 3 panels automatically closes the other 2 immediately,
	ensuring frames never overlap on top or behind each other.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Buttons = PlayerGui:WaitForChild("Buttons")
local Features = Buttons:WaitForChild("Features")

local InventoryBtn = Features:FindFirstChild("Inventory")
local RewardsBtn = Features:FindFirstChild("Rewards")
local ShopBtn = Features:FindFirstChild("Shop")

-- Central toggle registry: each panel exposes open/close/isOpen.
-- Clicking a button toggles ITS panel, and closes the other panels (only 1 open at a time).
local PANELS = {
	{ name = "Rewards",   api = function() return _G.RewardsAPI end },
	{ name = "Inventory", api = function() return _G.InventoryAPI end },
	{ name = "Shop",      api = function() return _G.ShopAPI end },
}

local function closeOthers(exceptApi)
	for _, p in ipairs(PANELS) do
		local api = p.api()
		if api and api ~= exceptApi then
			if api.isOpen and api.isOpen() and api.close then
				api.close()
			end
		end
	end
end

local function togglePanel(api)
	if not api then return end
	if api.isOpen and api.isOpen() then
		if api.close then
			api.close() -- already open -> close it
		end
	else
		closeOthers(api) -- close the others first so they NEVER overlap
		if api.open then
			api.open()
		end
	end
end

-- Rewards button opens/toggles the rewards window.
if RewardsBtn then
	RewardsBtn.Activated:Connect(function()
		togglePanel(_G.RewardsAPI)
	end)
end

-- Inventory toggles the chair inventory.
if InventoryBtn then
	InventoryBtn.Activated:Connect(function()
		togglePanel(_G.InventoryAPI)
	end)
end

-- Shop: toggles the ShopF window + looping scale pulse.
if ShopBtn then
	ShopBtn.Activated:Connect(function()
		togglePanel(_G.ShopAPI)
	end)

	local us = ShopBtn:FindFirstChildOfClass("UIScale")
	if not us then
		us = Instance.new("UIScale")
		us.Scale = 1
		us.Parent = ShopBtn
	end
	RunService.Heartbeat:Connect(function()
		local t = (os.clock() % 1.2) / 1.2
		us.Scale = 1 + 0.06 * (0.5 - 0.5 * math.cos(t * math.pi * 2))
	end)
end


