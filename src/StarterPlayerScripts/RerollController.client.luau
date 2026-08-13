--[[
	RerollController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays the cash-reward REROLL on the table (all in-world, smooth):
	1. The 6 reward models cycle on the table at the CashAnchor (one after
	   another, decelerating) - like a slot machine.
	2. It lands on the chosen reward (only the winner is visible).
	3. An OUTRO plays: the winner holds briefly, then fades/sinks away as the
	   game GUI pops up. Plays the SFX "cash" sound when it lands.
	The countdown frame is hidden when the roll starts (countdown ends first).

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

-- Spawn all reward models at the SAME spot on the anchor, all hidden initially.
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
			setPartsTransparency(parts, 1) -- start hidden
			table.insert(entries, {
				value = value,
				model = model,
				parts = parts,
				basePivot = spawnPivot,
			})
		end
	end
	return entries
end

-- Show ONLY the given entry; hide every other.
local function showOnly(entries, showEntry)
	for _, e in entries do
		local visible = (e == showEntry)
		setPartsTransparency(e.parts, visible and 0 or 1)
		e.model:PivotTo(e.basePivot * (visible and CFrame.new(0, 0.7, 0) or CFrame.new()))
		for _, b in e.model:GetDescendants() do
			if b:IsA("BillboardGui") then
				b.Enabled = visible
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
			-- LAND: show ONLY the chosen reward.
			local winner
			for _, e in entries do
				if e.value == chosen then
					winner = e
				end
			end
			showOnly(entries, winner) -- hides all others, shows + lifts winner
			SFX.play("cash")

			-- OUTRO: hold ~1s, then fade/sink all models away.
			task.delay(1.0, function()
				local sinkStart = os.clock()
				local sink
				sink = RunService.Heartbeat:Connect(function()
					local p = (os.clock() - sinkStart) / 0.5
					if p >= 1 then
						if sink then
							sink:Disconnect()
						end
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
