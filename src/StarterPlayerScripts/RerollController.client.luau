--[[
	RerollController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays the cash-reward REROLL animation on the table (like a lucky block):
	after the countdown, the 6 reward models cycle at the table's CashAnchor
	block, then the chosen one is highlighted with sparkles and a "+$X" flash.
	Actual Cash is awarded server-side (GameManager.runCashReroll).

	SETUP (no models inside each table folder!)
	* Put your 6 reward models in ReplicatedStorage.CashRewards, named:
	      Cash100, Cash350, Cash750, Cash1500, Cash3500, Cash5000
	* In each TableN folder, add ONE part named `CashAnchor` (a block where the
	  reroll happens). The script clones the models there for the animation.
	If either is missing, the script silently skips (cash still awards).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")

-- The central pool of cash reward models.
local CashRewardsFolder = ReplicatedStorage:FindFirstChild("CashRewards")

-- Find the "TableN" folder the local player is seated at.
local function findTableFolder()
	local char = player.Character
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local node = seat and seat.Parent
	while node do
		if node:IsA("Folder") and string.sub(node.Name, 1, 5) == "Table" then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Clone the reward models from ReplicatedStorage.CashRewards at the anchor.
local function spawnRewards(anchor, rewardList)
	local spawned = {}
	for _, value in rewardList do
		if CashRewardsFolder then
			local template = CashRewardsFolder:FindFirstChild("Cash" .. value)
			if template then
				local clone = template:Clone()
				clone.Name = "CashReward"
				-- Place at the anchor block.
				clone:PivotTo(anchor.CFrame * CFrame.new(0, 1, 0))
				clone.Parent = workspace
				table.insert(spawned, { value = value, model = clone })
			end
		end
	end
	return spawned
end

-- Highlight (scale up + lift) a model.
local function setHighlight(model, on, baseCF)
	if not model then
		return
	end
	local cf = baseCF or model:GetPivot()
	if on then
		TweenService:Create(model, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = cf * CFrame.new(0, 0.6, 0) }):Play()
	else
		TweenService:Create(model, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = cf }):Play()
	end
end

-- Burst of sparkle particles on the winning model.
local function sparkle(model)
	if not model then
		return
	end
	local primary = model.PrimaryPart
	if not primary then
		primary = model:FindFirstChildWhichIsA("BasePart")
	end
	if not primary then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://243660179" -- star sparkle
	emitter.Enabled = true
	emitter.Rate = 200
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(0, 360)
	emitter.Size = NumberSequence.new(0.4)
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = primary
	task.delay(0.6, function()
		emitter.Rate = 0
	end)
	task.delay(1.5, function()
		if emitter then
			emitter:Destroy()
		end
	end)
end

-- Flash "+$X" in the middle of the screen.
local function flashCash(value)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CashFlash"
	gui.IgnoreGuiInset = true
	gui.Parent = PlayerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.5, 0, 0.15, 0)
	label.Position = UDim2.new(0.25, 0, 0.4, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = "+$" .. value
	label.TextColor3 = Color3.fromRGB(80, 255, 120)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.3
	label.ZIndex = 50
	label.Parent = gui

	local us = Instance.new("UIScale")
	us.Scale = 0
	us.Parent = label

	-- Pop in, float up, fade out.
	TweenService:Create(us, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	local up = TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.25, 0, 0.32, 0) })
	up:Play()
	task.delay(1.1, function()
		TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ TextTransparency = 1 }):Play()
	end)
	task.delay(1.6, function()
		gui:Destroy()
	end)
end

-- Run the reroll animation.
local function runReroll(chosen, rewardList)
	local folder = findTableFolder()
	local anchor = folder and folder:FindFirstChild("CashAnchor")
	if not anchor or not anchor:IsA("BasePart") or not CashRewardsFolder then
		return -- nothing to animate; server still awards cash
	end

	local spawned = spawnRewards(anchor, rewardList)
	if #spawned == 0 then
		return
	end
	local baseCFs = {}
	for _, m in spawned do
		baseCFs[m.model] = m.model:GetPivot()
	end

	local current = 1
	local t = os.clock()
	local duration = 3 -- match REROLL_DURATION on the server

	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		local progress = (os.clock() - t) / duration
		if progress >= 1 then
			conn:Disconnect()
			-- Land on the chosen reward.
			for _, m in spawned do
				setHighlight(m.model, m.value == chosen, baseCFs[m.model])
			end
			-- Winner gets sparkles + a "+$X" flash.
			for _, m in spawned do
				if m.value == chosen then
					sparkle(m.model)
					break
				end
			end
			flashCash(chosen)
			return
		end
		local interval = 0.05 + progress * 0.3 -- decelerate
		if (os.clock() - t) >= current * interval then
			for _, m in spawned do
				setHighlight(m.model, false, baseCFs[m.model])
			end
			current = current + 1
			local idx = ((current - 1) % #spawned) + 1
			setHighlight(spawned[idx].model, true, baseCFs[spawned[idx].model])
		end
	end)

	-- Clean up spawned clones after the animation.
	task.delay(duration + 1.5, function()
		for _, m in spawned do
			if m.model and m.model.Parent then
				m.model:Destroy()
			end
		end
	end)
end

Events:WaitForChild("CashReroll").OnClientEvent:Connect(function(chosen, rewardList)
	runReroll(chosen, rewardList)
end)
