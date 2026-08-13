--[[
	RerollController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays the cash-reward ROULETTE on screen (like Steal a Brainrot):
	* A wheel/roulette of cash values rapidly cycles on the screen.
	* It decelerates and lands on the single chosen reward.
	* The countdown frame is hidden when the roll starts (so the countdown ends
	  FIRST, then the roll plays), and the overlay disappears when RoundStart
	  fires (the game GUI then pops up).

	Actual Cash is awarded server-side (GameManager.runCashReroll). The reward
	list + chosen value come from the CashReroll RemoteEvent.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")

local REROLL_DURATION = 3 -- match the server's REROLL_DURATION

-------------------------------------------------------------------------------
-- ROULETTE OVERLAY
-------------------------------------------------------------------------------
local overlay = nil
local cycleLabel = nil
local dimBg = nil

local function buildOverlay()
	if overlay then
		return
	end
	overlay = Instance.new("ScreenGui")
	overlay.Name = "CashRoulette"
	overlay.IgnoreGuiInset = true
	overlay.Enabled = false
	overlay.Parent = PlayerGui

	-- Dim background
	dimBg = Instance.new("Frame")
	local bg = dimBg
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BackgroundTransparency = 0.4
	bg.ZIndex = 40
	bg.Parent = overlay

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.2, 0)
	title.Position = UDim2.new(0, 0, 0.1, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "REWARD!"
	title.TextColor3 = Color3.fromRGB(255, 210, 90)
	title.TextScaled = true
	title.ZIndex = 50
	title.Parent = overlay

	-- Cycling value label (the roulette)
	cycleLabel = Instance.new("TextLabel")
	cycleLabel.Size = UDim2.new(0.6, 0, 0.4, 0)
	cycleLabel.Position = UDim2.new(0.2, 0, 0.35, 0)
	cycleLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	cycleLabel.BackgroundTransparency = 0.2
	cycleLabel.Font = Enum.Font.GothamBlack
	cycleLabel.TextColor3 = Color3.new(1, 1, 1)
	cycleLabel.TextScaled = true
	cycleLabel.TextStrokeTransparency = 0.3
	cycleLabel.ZIndex = 50
	cycleLabel.Parent = overlay

	-- Small instruction
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0.15, 0)
	hint.Position = UDim2.new(0, 0, 0.78, 0)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.Text = "Good luck!"
	hint.TextColor3 = Color3.fromRGB(200, 200, 200)
	hint.TextScaled = true
	hint.ZIndex = 50
	hint.Parent = overlay
end

-- Cycle the roulette, decelerating, and land on the chosen value.
local function runRoulette(chosen, rewardList)
	buildOverlay()
	if not overlay or not cycleLabel then
		return
	end

	-- Hide the countdown frame so the countdown "ends" before the roll.
	local gameUI = PlayerGui:FindFirstChild("GameUI")
	local countdown = gameUI and gameUI:FindFirstChild("CountdownFrame")
	if countdown then
		countdown.Visible = false
	end

	overlay.Enabled = true
	cycleLabel.Text = ""
	cycleLabel.TextColor3 = Color3.new(1, 1, 1)

	local t = os.clock()
	local current = 1
	local lastTick = 0
	local conn

	conn = game:GetService("RunService").Heartbeat:Connect(function()
		local progress = (os.clock() - t) / REROLL_DURATION
		if progress >= 1 then
			conn:Disconnect()
			-- Land on the chosen value.
			cycleLabel.Text = "$" .. chosen
			cycleLabel.TextColor3 = Color3.fromRGB(120, 255, 130)
			-- Pop the landed value.
			local us = cycleLabel:FindFirstChildOfClass("UIScale")
			if not us then
				us = Instance.new("UIScale")
				us.Parent = cycleLabel
			end
			us.Scale = 0.6
			TweenService:Create(us, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }):Play()
			-- Briefly hold the result, then fade the overlay out.
			task.delay(0.9, function()
				if overlay then
					TweenService:Create(dimBg, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
						{ BackgroundTransparency = 1 }):Play()
					TweenService:Create(cycleLabel, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
						{ TextTransparency = 1 }):Play()
				end
				task.delay(0.4, function()
					if overlay then
						overlay.Enabled = false
					end
				end)
			end)
			return
		end

		-- Decelerating cycle: interval grows as progress increases.
		local interval = 0.03 + progress * 0.12
		if (os.clock() - t) >= current * interval then
			current = current + 1
			local idx = ((current - 1) % #rewardList) + 1
			cycleLabel.Text = "$" .. rewardList[idx]
		end
	end)
end

-- Always hide the overlay when the round starts (GUI pops up).
Events:WaitForChild("RoundStart").OnClientEvent:Connect(function()
	if overlay then
		overlay.Enabled = false
	end
end)

-- Start the roll when the server says so.
Events:WaitForChild("CashReroll").OnClientEvent:Connect(function(chosen, rewardList)
	runRoulette(chosen, rewardList)
end)
