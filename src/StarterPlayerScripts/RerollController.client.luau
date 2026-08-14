--[[
	RerollController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays the cash-reward REROLL on the table (all in-world, lucky-block style):
	1. The 6 reward models cycle on the table at the CashAnchor (one after
	   another, decelerating) - like a slot machine.
	2. It lands on the chosen reward with a ScaleTo "pop" (lucky block open).
	3. An OUTRO plays: the winner holds briefly, then fades/sinks away as the
	   game GUI pops up. Plays the SFX "cash" sound when it lands.

	ANIMATION (Model:ScaleTo)
	Each reward is shown by SCALING it up from 0 to 1 (and scaled back to 0 when
	hidden), so only ONE model is ever at full size - no leftover/overlap.

	SETUP
	* Put the 6 models in ReplicatedStorage.CashRewards named
	  Cash100, Cash350, Cash750, Cash1500, Cash3500, Cash5000.
	* In each TableN folder, add ONE part named `CashAnchor` (the block).
	Actual Cash is awarded server-side (GameManager.runCashReroll).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")
local SFX = require(ReplicatedStorage:WaitForChild("SFX"))

local REROLL_DURATION = 3 -- match the server's REROLL_DURATION

local CashRewardsFolder = ReplicatedStorage:FindFirstChild("CashRewards")

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

-- Set a model's scale instantly via Model:ScaleTo (lucky-block scaling).
local function setModelScale(model, scale)
	if model and model.ScaleTo then
		model:ScaleTo(math.max(scale, 0.001))
	end
end

-- Spawn all reward models at the SAME spot on the anchor, scaled to ~0.
local function spawnRewards(anchor, rewardList)
	local entries = {}
	local spawnPivot = anchor.CFrame * CFrame.new(0, 1, 0)
	for _, value in rewardList do
		local template = CashRewardsFolder and CashRewardsFolder:FindFirstChild("Cash" .. value)
		if template then
			local model = template:Clone()
			model.Name = "CashReward"
			model:PivotTo(spawnPivot)
			model.Parent = workspace
			local parts = collectParts(model)
			setModelScale(model, 0.001) -- collapse to nothing initially
			setPartsTransparency(parts, 1) -- also fully invisible
			for _, b in model:GetDescendants() do
				if b:IsA("BillboardGui") then
					b.Enabled = false
				end
			end
			table.insert(entries, {
				value = value,
				model = model,
				parts = parts,
				basePivot = spawnPivot,
				scaleConn = nil, -- active scale animation for this model
			})
		end
	end
	return entries
end

-- Animate a model's scale from -> to over duration (with easing + optional
-- overshoot bounce). Cancels any running scale tween on that entry first.
local function animateScale(entry, toScale, duration, overshoot)
	if entry.scaleConn then
		entry.scaleConn:Disconnect()
		entry.scaleConn = nil
	end
	local model = entry.model
	local fromScale = 0.001 -- always start from nothing for a clean pop

	local t0 = os.clock()
	entry.scaleConn = RunService.Heartbeat:Connect(function()
		local p = (os.clock() - t0) / duration
		if p >= 1 then
			if entry.scaleConn then
				entry.scaleConn:Disconnect()
				entry.scaleConn = nil
			end
			setModelScale(model, toScale)
			return
		end
		-- easeOutBack for an overshooty pop
		local c1 = 1.70158
		local c3 = c1 + 1
		local p1 = p - 1
		local eased = 1 + c3 * p1 ^ 3 + c1 * p1 ^ 2
		local s = fromScale + (toScale - fromScale) * eased
		setModelScale(model, s)
	end)
end

-- Show ONLY the given entry (scale it up); collapse every other to ~0.
local function showOnly(entries, showEntry)
	for _, e in entries do
		local visible = (e == showEntry)
		if visible then
			animateScale(e, 1, 0.22, true)
			setPartsTransparency(e.parts, 0)
			for _, b in e.model:GetDescendants() do
				if b:IsA("BillboardGui") then
					b.Enabled = true
				end
			end
		else
			if e.scaleConn then
				e.scaleConn:Disconnect()
				e.scaleConn = nil
			end
			setModelScale(e.model, 0.001)
			setPartsTransparency(e.parts, 1)
			for _, b in e.model:GetDescendants() do
				if b:IsA("BillboardGui") then
					b.Enabled = false
				end
			end
		end
	end
end

-- Cleanup a previous animation if one is still running.
local activeConn = nil
local activeEntries = {}
local function clearActive()
	if activeConn then
		activeConn:Disconnect()
		activeConn = nil
	end
	for _, e in activeEntries do
		if e.scaleConn then
			e.scaleConn:Disconnect()
			e.scaleConn = nil
		end
		if e.model and e.model.Parent then
			e.model:Destroy()
		end
	end
	activeEntries = {}
end

local function runReroll(chosen, rewardList)
	clearActive()
	local folder = findTableFolder()
	local anchor = folder and folder:FindFirstChild("CashAnchor")
	if not anchor or not anchor:IsA("BasePart") or not CashRewardsFolder then
		return
	end

	local entries = spawnRewards(anchor, rewardList)
	if #entries == 0 then
		return
	end
	activeEntries = entries

	-- Hide the countdown frame so the countdown "ends" before the roll.
	local gameUI = PlayerGui:FindFirstChild("GameUI")
	local countdown = gameUI and gameUI:FindFirstChild("CountdownFrame")
	if countdown then
		countdown.Visible = false
	end

	-- Hide everything initially.
	showOnly(entries, nil)

	-- Play the "spinning/cycling" sound while the roll is happening.
	SFX.play("cashRoll")

	local t = os.clock()
	local current = 1
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local progress = (os.clock() - t) / REROLL_DURATION
		if progress >= 1 then
			if conn then
				conn:Disconnect()
				activeConn = nil
			end
			-- LAND: collapse ALL, then pop up ONLY the winner.
			showOnly(entries, nil)
			local winner
			for _, e in entries do
				if e.value == chosen then
					winner = e
				end
			end
			if winner then
				setPartsTransparency(winner.parts, 0)
				for _, b in winner.model:GetDescendants() do
					if b:IsA("BillboardGui") then
						b.Enabled = true
					end
				end
				-- Lucky-block open: big overshoot pop to 1.25, then settle to 1.
				animateScale(winner, 1.25, 0.25, true)
				task.delay(0.25, function()
					animateScale(winner, 1, 0.18, true)
				end)
				SFX.play("cash")
			end

			-- OUTRO: hold the winner ~1s, then fade/sink all models away.
			task.delay(1.1, function()
				local sinkStart = os.clock()
				local sink
				sink = RunService.Heartbeat:Connect(function()
					local p = (os.clock() - sinkStart) / 0.5
					if p >= 1 then
						if sink then
							sink:Disconnect()
						end
						for _, e in entries do
							if e.scaleConn then
								e.scaleConn:Disconnect()
								e.scaleConn = nil
							end
							setModelScale(e.model, 0.001)
							setPartsTransparency(e.parts, 1)
						end
						return
					end
					for _, e in entries do
						setPartsTransparency(e.parts, p)
					end
				end)
				task.delay(0.7, function()
					for _, e in entries do
						if e.model and e.model.Parent then
							e.model:Destroy()
						end
					end
					activeEntries = {}
				end)
			end)
			return
		end

		-- Decelerating cycle: interval grows as progress increases.
		local interval = 0.03 + progress * 0.12
		if (os.clock() - t) >= current * interval then
			current = current + 1
			local idx = ((current - 1) % #entries) + 1
			showOnly(entries, entries[idx]) -- show only this one
		end
	end)
	activeConn = conn
end

Events:WaitForChild("CashReroll").OnClientEvent:Connect(function(chosen, rewardList)
	runReroll(chosen, rewardList)
end)
