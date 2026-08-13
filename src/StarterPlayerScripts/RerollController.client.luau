--[[
	RerollController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays the cash-reward REROLL on the table (all in-world, smooth):
	1. The 6 reward models cycle on the table at the CashAnchor (one lights up
	   after another, decelerating) - like a slot machine.
	2. It lands on the chosen reward, which pops up and gets sparkles.
	3. An OUTRO plays: the winner stays highlighted for a moment, then all models
	   fade/sink away as the game GUI pops up.
	The countdown frame is hidden when the roll starts (countdown ends first).

	SETUP
	* Put the 6 models in ReplicatedStorage.CashRewards named
	  Cash100, Cash350, Cash750, Cash1500, Cash3500, Cash5000.
	* In each TableN folder, add ONE part named `CashAnchor` (the block).
	Actual Cash is awarded server-side (GameManager.runCashReroll).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")

local REROLL_DURATION = 3 -- match the server's REROLL_DURATION

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

local function collectParts(model)
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	if #parts == 0 and model.PrimaryPart then
		table.insert(parts, model.PrimaryPart)
	end
	return parts
end

local function setPartsTransparency(parts, alpha)
	for _, p in parts do
		p.Transparency = alpha
	end
end

-- Spawn all reward models at the anchor (each slightly offset so they don't
-- perfectly overlap), all hidden initially.
local function spawnRewards(anchor, rewardList)
	local entries = {}
	local n = #rewardList
	for i, value in rewardList do
		local template = CashRewardsFolder and CashRewardsFolder:FindFirstChild("Cash" .. value)
		if template then
			local model = template:Clone()
			model.Name = "CashReward"
			-- Small fan/spread so each is visible when cycling.
			model:PivotTo(anchor.CFrame * CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad((i - 1) * (360 / n)), 0))
			model.Parent = workspace
			local parts = collectParts(model)
			setPartsTransparency(parts, 1) -- start hidden
			table.insert(entries, {
				value = value,
				model = model,
				parts = parts,
				basePivot = model:GetPivot(),
			})
		end
	end
	return entries
end

-- Smoothly lift/drop the current model (tween via CFrame of the model is not
-- allowed, so we tween a welded BasePart root OR move via PivotTo). We use a
-- lightweight approach: tween a "root" part's Position if we can, else PivotTo.
local function liftModel(entry, on)
	if not entry then
		return
	end
	local target = entry.basePivot * (on and CFrame.new(0, 0.7, 0) or CFrame.new())
	entry.model:PivotTo(target)
end

local function setModelVisible(entry, visible)
	setPartsTransparency(entry.parts, visible and 0 or 1)
	for _, b in entry.model:GetDescendants() do
		if b:IsA("BillboardGui") then
			b.Enabled = visible
		end
	end
end

local function sparkle(model)
	if not model then
		return
	end
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://243660179"
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

local function runReroll(chosen, rewardList)
	local folder = findTableFolder()
	local anchor = folder and folder:FindFirstChild("CashAnchor")
	if not anchor or not anchor:IsA("BasePart") or not CashRewardsFolder then
		return -- nothing to animate; server still awards cash
	end

	local entries = spawnRewards(anchor, rewardList)
	if #entries == 0 then
		return
	end

	-- Hide the countdown frame so the countdown "ends" before the roll.
	local gameUI = PlayerGui:FindFirstChild("GameUI")
	local countdown = gameUI and gameUI:FindFirstChild("CountdownFrame")
	if countdown then
		countdown.Visible = false
	end

	local t = os.clock()
	local current = 1
	local lastLanded = nil

	-- Smooth cycle using tweens on visibility: show current, hide others.
	local function showIndex(idx)
		for i, e in entries do
			local isCurrent = (i == idx)
			setModelVisible(e, isCurrent)
			liftModel(e, isCurrent)
		end
	end

	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		local progress = (os.clock() - t) / REROLL_DURATION
		if progress >= 1 then
			conn:Disconnect()
			-- LAND on the chosen reward.
			local winner
			for _, e in entries do
				if e.value == chosen then
					winner = e
				end
			end
			if winner then
				setModelVisible(winner, true)
				liftModel(winner, true)
				sparkle(winner.model)
			end
			-- OUTRO: hold the winner ~1s, then fade/sink all models away.
			task.delay(1.0, function()
				-- Fade parts + sink via a lightweight heartbeat loop.
				local sinkStart = os.clock()
				local sink = game:GetService("RunService").Heartbeat:Connect(function()
					local p = (os.clock() - sinkStart) / 0.5
					if p >= 1 then
						sink:Disconnect()
						for _, e in entries do
							setPartsTransparency(e.parts, 1)
							e.model:PivotTo(e.basePivot)
						end
						return
					end
					for _, e in entries do
						setPartsTransparency(e.parts, p)
						e.model:PivotTo(e.basePivot * CFrame.new(0, -p * 1.2, 0))
					end
				end)
				task.delay(0.7, function()
					for _, e in entries do
						if e.model and e.model.Parent then
							e.model:Destroy()
						end
					end
				end)
			end)
			return
		end

		-- Decelerating cycle: interval grows as progress increases.
		local interval = 0.03 + progress * 0.12
		if (os.clock() - t) >= current * interval then
			current = current + 1
			local idx = ((current - 1) % #entries) + 1
			showIndex(idx)
		end
	end)
end

-- Start the roll when the server says so.
Events:WaitForChild("CashReroll").OnClientEvent:Connect(function(chosen, rewardList)
	runReroll(chosen, rewardList)
end)
