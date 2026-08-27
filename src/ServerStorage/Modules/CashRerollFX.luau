--[[
	CashRerollFX.luau  (ModuleScript)  -- place in ServerStorage.Modules
	----------------------------------------------------------------------------
	PURPOSE
	The SERVER-SIDE cash-reroll animation. Because the models are parented to
	Workspace BY THE SERVER, the roll is visible to EVERY player in the game -
	not just the two players seated at the table.

	Animation (same feel as the old client version):
	  1. The eligible cash models cycle on the CashAnchor (slot-machine style,
	     decelerating) - one model at a full size, the rest collapsed.
	  2. Lands on the chosen reward with a lucky-block overshoot pop.
	  3. Outro: the winner holds briefly, then fades/sinks away.

	USAGE (GameManager)
		local CashRerollFX = require(ServerStorage.Modules.CashRerollFX)
		CashRerollFX.roll(cashAnchorPart, chosenValue, rewardList)
	Fire-and-forget: the animation runs in its own task. Sound effects are
	played by the CLIENT (RerollController) on the CashReroll/CashAwarded
	events, so this module stays silent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CashRerollFX = {}

local REROLL_DURATION = 3 -- keep in sync with GameManager.REROLL_DURATION

local CashRewardsFolder = ReplicatedStorage:FindFirstChild("CashRewards")

local function collectParts(model)
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	return parts
end

local function setPartsTransparency(parts, alpha)
	for _, p in parts do
		p.Transparency = alpha
	end
end

local function setModelScale(model, scale)
	if model and model.ScaleTo then
		model:ScaleTo(math.max(scale, 0.001))
	end
end

-- Spawn all reward models at the SAME spot on the anchor, collapsed to ~0.
local function spawnRewards(anchor, rewardList)
	local entries = {}
	local spawnPivot = anchor.CFrame * CFrame.new(0, 1, 0)
	for _, value in rewardList do
		local template = CashRewardsFolder and CashRewardsFolder:FindFirstChild("Cash" .. value)
		if template then
			local model = template:Clone()
			model.Name = "CashReward"
			model:PivotTo(spawnPivot)
			model.Parent = workspace -- server-parented -> visible to everyone
			local parts = collectParts(model)
			setModelScale(model, 0.001)
			setPartsTransparency(parts, 1)
			for _, b in model:GetDescendants() do
				if b:IsA("BillboardGui") then
					b.Enabled = false
				end
			end
			table.insert(entries, {
				value = value,
				model = model,
				parts = parts,
				scaleConn = nil,
			})
		end
	end
	return entries
end

-- Animate a model's scale from ~0 to `toScale` over `duration` (easeOutBack
-- overshoot). Cancels any scale animation running on that entry first.
local function animateScale(entry, toScale, duration)
	if entry.scaleConn then
		entry.scaleConn:Disconnect()
		entry.scaleConn = nil
	end
	local model = entry.model
	local fromScale = 0.001

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
			animateScale(e, 1, 0.22)
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

-- Run the full roll on `anchor` and land on `chosen` (fire-and-forget).
function CashRerollFX.roll(anchor, chosen, rewardList)
	if not anchor or not anchor:IsA("BasePart") or not CashRewardsFolder then
		return
	end
	if not (chosen and type(rewardList) == "table" and #rewardList > 0) then
		return
	end

	task.spawn(function()
		local entries = spawnRewards(anchor, rewardList)
		if #entries == 0 then
			return
		end

		showOnly(entries, nil)

		local t = os.clock()
		local current = 1
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local progress = (os.clock() - t) / REROLL_DURATION
			if progress >= 1 then
				if conn then
					conn:Disconnect()
					conn = nil
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
					-- Lucky-block open: overshoot pop to 1.25, settle to 1.
					animateScale(winner, 1.25, 0.25)
					task.delay(0.25, function()
						animateScale(winner, 1, 0.18)
					end)
				end

				-- OUTRO: hold ~1.1s, then fade/sink everything away.
				task.delay(1.1, function()
					local sinkStart = os.clock()
					local sink
					sink = RunService.Heartbeat:Connect(function()
						local p = (os.clock() - sinkStart) / 0.5
						if p >= 1 then
							if sink then
								sink:Disconnect()
								sink = nil
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
					end)
				end)
				return
			end

			-- Decelerating cycle: interval grows as progress increases.
			local interval = 0.03 + progress * 0.12
			if (os.clock() - t) >= current * interval then
				current = current + 1
				local idx = ((current - 1) % #entries) + 1
				showOnly(entries, entries[idx])
			end
		end)
	end)
end

return CashRerollFX
