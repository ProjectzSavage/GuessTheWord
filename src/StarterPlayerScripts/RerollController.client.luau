--[[
	RerollController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	CLIENT SIDE of the cash reroll. The in-world roll animation itself is now
	RUN ON THE SERVER (ServerStorage.Modules.CashRerollFX) so that EVERY
	player in the game can see it - not just the two seated at the table.

	This client script only:
	  * hides the countdown frame when the roll starts,
	  * plays the "cashRoll" sound while the roll cycles,
	  * plays the "cash" sound when the roll lands (CashAwarded).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")
local SFX = require(ReplicatedStorage:WaitForChild("SFX"))

Events:WaitForChild("CashReroll").OnClientEvent:Connect(function(chosen, rewardList)
	-- The world animation is server-side (visible to everyone). Hide the
	-- countdown "ends" before the roll, and play the rolling sound.
	local gameUI = PlayerGui:FindFirstChild("GameUI")
	local countdown = gameUI and gameUI:FindFirstChild("CountdownFrame")
	if countdown then
		countdown.Visible = false
	end
	SFX.play("cashRoll")
end)

Events:WaitForChild("CashAwarded").OnClientEvent:Connect(function(reward)
	SFX.play("cash")
end)
