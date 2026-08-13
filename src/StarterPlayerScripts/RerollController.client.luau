--[[
	RerollController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Plays the cash-reward REROLL animation on the table (like opening a lucky
	block): after the countdown, the 6 reward models cycle/swap around, then the
	chosen reward is highlighted, then the GUI pops up. The actual Cash is
	awarded server-side (see GameManager.runCashReroll).

	HOW TO SET UP YOUR MODELS
	Inside each Table folder (Workspace.GameArea.Table1, Table2, ...) add 6
	models/parts named exactly:
	    Cash100, Cash350, Cash750, Cash1500, Cash3500, Cash5000
	They can be small pickup-looking models (coin stacks, cash bundles, etc.).
	The script hides all of them, then shows them one at a time as the reroll
	cycles, ending on the winning one (which gets a highlight + scale pop).

	If the models aren't found, the script falls back to showing a simple
	screen message instead (so nothing errors).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Events = ReplicatedStorage:WaitForChild("Events")

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

-- Collect the 6 cash models from a table folder by name.
local function collectRewardModels(folder, rewardList)
	local models = {}
	for _, value in rewardList do
		local m = folder and folder:FindFirstChild("Cash" .. value)
		if m then
			table.insert(models, { value = value, model = m })
		end
	end
	return models
end

-- Make a model look "highlighted" (scale up + lift) vs normal.
local function setModelHighlight(model, on)
	if not model then
		return
	end
	if on then
		TweenService:Create(model, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = model.Size * 1.6 }):Play()
	else
		TweenService:Create(model, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = model.Size }):Play()
	end
end

local function setModelVisible(model, visible)
	if not model then
		return
	end
	if model:IsA("Model") then
		model:PivotTo(model:GetPivot() * CFrame.new(0, visible and 0 or -10, 0))
	elseif model:IsA("BasePart") then
		model.CFrame = model.CFrame * CFrame.new(0, visible and 0 or -10, 0)
	end
end

-- Run the reroll animation. rewardList is the cycle order; chosen is the winner.
local function runReroll(chosen, rewardList)
	local folder = findTableFolder()
	local models = collectRewardModels(folder, rewardList)

	if #models == 0 then
		-- Fallback: nothing to animate; do nothing (server still awards cash).
		return
	end

	-- Reset all models to the table at normal size.
	for _, m in models do
		setModelVisible(m.model, true)
		setModelHighlight(m.model, false)
	end

	local current = 1
	local cycles = math.max(8, #models * 2)
	local t = os.clock()
	local duration = 3 -- match REROLL_DURATION on the server

	-- Cycle through the models quickly, decelerating.
	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		local progress = (os.clock() - t) / duration
		if progress >= 1 then
			conn:Disconnect()
			-- Land on the chosen reward, highlight it.
			for _, m in models do
				setModelHighlight(m.model, m.value == chosen)
			end
			return
		end
		-- Increase interval as we decelerate.
		local interval = 0.05 + progress * 0.25
		if (os.clock() - t) >= current * interval then
			for _, m in models do
				setModelHighlight(m.model, false)
			end
			current = current + 1
			local idx = ((current - 1) % #models) + 1
			setModelHighlight(models[idx].model, true)
		end
	end)

	-- After the animation, leave the winner highlighted for a moment.
	task.delay(duration + 0.6, function()
		for _, m in models do
			setModelHighlight(m.model, false)
		end
	end)
end

Events:WaitForChild("CashReroll").OnClientEvent:Connect(function(chosen, rewardList)
	runReroll(chosen, rewardList)
end)

-- (Optional) On award, you could flash "+$X" on screen. Leave for now.
