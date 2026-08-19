--[[
	ButtonsController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Wires the "Buttons" ScreenGui -> Features frame:
	  * Inventory  -> opens the inventory (setup soon; placeholder).
	  * Rewards    -> opens the RewardsF window (via _G.RewardsAPI).
	  * Shop       -> placeholder + a looping scale up/down pulse (it has a UIScale).

	REQUIRED UI:
		Buttons  (ScreenGui)
		└── Features  (Frame)
		    ├── Inventory (TextButton)
		    ├── Rewards   (TextButton)
		    └── Shop      (TextButton, contains a UIScale)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Buttons = PlayerGui:WaitForChild("Buttons")
local Features = Buttons:WaitForChild("Features")

local InventoryBtn = Features:FindFirstChild("Inventory")
local RewardsBtn = Features:FindFirstChild("Rewards")
local ShopBtn = Features:FindFirstChild("Shop")

-- Rewards button opens the rewards window.
if RewardsBtn then
	RewardsBtn.Activated:Connect(function()
		if _G.RewardsAPI and _G.RewardsAPI.open then
			_G.RewardsAPI.open()
		end
	end)
end

-- Inventory placeholder.
if InventoryBtn then
	InventoryBtn.Activated:Connect(function()
		print("[Buttons] Inventory clicked (setup soon).")
	end)
end

-- Shop: opens the ShopF window + looping scale pulse (eye-catching).
if ShopBtn then
	ShopBtn.Activated:Connect(function()
		if _G.ShopAPI and _G.ShopAPI.open then
			_G.ShopAPI.open()
		end
	end)

	-- Looping pulse using the button's existing UIScale (up + down forever).
	local us = ShopBtn:FindFirstChildOfClass("UIScale")
	if not us then
		us = Instance.new("UIScale")
		us.Scale = 1
		us.Parent = ShopBtn
	end
	RunService.Heartbeat:Connect(function()
		local t = (os.clock() % 1.2) / 1.2 -- 0..1
		-- Sine up & down between 1.0 and 1.12.
		us.Scale = 1 + 0.06 * (0.5 - 0.5 * math.cos(t * math.pi * 2))
	end)
end
