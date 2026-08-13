--[[
	RerollController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays the cash-reward REROLL animation on the table (like a lucky block):
	after the countdown, the 6 reward models cycle at the table's CashAnchor
	block, then the chosen one is highlighted with sparkles and a "+$X" flash.
	Actual Cash is awarded server-side (GameManager.runCashReroll).

	SETUP
	* Put your 6 reward models in ReplicatedStorage.CashRewards, named:
	      Cash100, Cash350, Cash750, Cash1500, Cash3500, Cash5000
	* In each TableN folder, add ONE part named `CashAnchor` (the block).
	If either is missing, the script silently skips (cash still awards).

	OPTIMIZED
	Models are hidden/shown by toggling their parts' Transparency (never tweened
	by CFrame, which models don't have). Only ONE model is visible at a time,
	which keeps rendering light even on mobile.
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

-- Collect all BaseParts of a model (cached for cheap hide/show).
local function collectParts(model)
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	-- Ensure there's at least one (e.g. PrimaryPart).
	if #parts == 0 then
		local p = model.PrimaryPart
		if p then
			table.insert(parts, p)
		end
	end
	return parts
end

-- Hide/show a model by toggling its parts' Transparency + billboards.
local function showModel(entry)
	local model = entry.model
	if not model then
		return
	end
	for _, p in entry.parts do
		p.Transparency = 0
	end
	for _, b in entry.billboards do
		b.Enabled = true
	end
end

local function hideModel(entry)
	local model = entry.model
	if not model then
		return
	end
	for _, p in entry.parts do
		p.Transparency = 1
	end
	for _, b in entry.billboards do
		b.Enabled = false
	end
end

-- Lift the highlighted model up a bit (cheap, direct PivotTo, no tween loop).
local function setHighlight(entry, on)
	if not entry then
		return
	end
	if on then
		entry.model:PivotTo(entry.basePivot * CFrame.new(0, 0.6, 0))
	else
		entry.model:PivotTo(entry.basePivot)
	end
end

-- Clone one reward model at the anchor.
local function spawnReward(anchor, value)
	if not CashRewardsFolder then
		return nil
	end
	local template = CashRewardsFolder:FindFirstChild("Cash" .. value)
	if not template then
		return nil
	end
	local clone = template:Clone()
	clone.Name = "CashReward"
	clone:PivotTo(anchor.CFrame * CFrame.new(0, 1, 0))
	clone.Parent = workspace
	return clone
end

-- Build entries (model + parts + billboards + basePivot).
local function buildEntries(anchor, rewardList)
	local entries = {}
	for _, value in rewardList do
		local model = spawnReward(anchor, value)
		if model then
			local entry = {
				value = value,
				model = model,
				parts = collectParts(model),
				basePivot = model:GetPivot(),
				billboards = {},
			}
			for _, b in model:GetDescendants() do
				if b:IsA("BillboardGui") then
					table.insert(entry.billboards, b)
				end
			end
			table.insert(entries, entry)
		end
	end
	return entries
end

-- Burst of sparkle particles on the winning model.
local function sparkle(model)
	if not model then
		return
	end
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
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

	TweenService:Create(us, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.25, 0, 0.32, 0) }):Play()
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

	local entries = buildEntries(anchor, rewardList)
	if #entries == 0 then
		return
	end

	-- Start with all hidden.
	for _, e in entries do
		hideModel(e)
	end

	local current = 1
	local t = os.clock()
	local duration = 3 -- match REROLL_DURATION on the server

	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		local progress = (os.clock() - t) / duration
		if progress >= 1 then
			conn:Disconnect()
			-- Land on the chosen reward: hide all, show + lift the winner.
			for _, e in entries do
				hideModel(e)
			end
			local winner
			for _, e in entries do
				if e.value == chosen then
					winner = e
				end
			end
			if winner then
				showModel(winner)
				setHighlight(winner, true)
				sparkle(winner.model)
			end
			flashCash(chosen)
			return
		end
		local interval = 0.05 + progress * 0.3 -- decelerate
		if (os.clock() - t) >= current * interval then
			-- Show only the current model, hide the rest.
			local idx = ((current - 1) % #entries) + 1
			for i, e in entries do
				if i == idx then
					showModel(e)
					setHighlight(e, true)
				else
					hideModel(e)
				end
			end
			current = current + 1
		end
	end)

	-- Clean up spawned clones after the animation.
	task.delay(duration + 1.5, function()
		for _, e in entries do
			if e.model and e.model.Parent then
				e.model:Destroy()
			end
		end
	end)
end

Events:WaitForChild("CashReroll").OnClientEvent:Connect(function(chosen, rewardList)
	runReroll(chosen, rewardList)
end)
