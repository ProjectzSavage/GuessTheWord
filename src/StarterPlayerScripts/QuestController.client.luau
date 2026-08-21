--[[
	QuestController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Renders the DAILY QUESTS gui and drives its toggle. The server (QuestService)
	sends a `payload` with quests (desc, progress, target, reward, claimed, done)
	and a reset countdown. This client fills the Quest gui rows, wires ClaimBtns,
	and slides the panel closed/opened via ToggleBtn.

	REQUIRED UI (the Quest gui you built, e.g. in a ScreenGui):
		DailyQuestsF  (Frame, Position {0.776,0},{0.034,0})
		└── Quest  (Frame)
		    ├── UIListLayout
		    ├── Quest1  (Frame)
		    │   ├── ClaimBtn (TextButton), DescLbl, ProgressLbl, RewardLbl
		    ├── Quest2  (Frame)  (same children)
		    ├── ToggleBtn (TextButton)
		    └── TitleLbl  (TextLabel)   shows "DAILY QUESTS (07:00:00)"
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local QuestSync = Events:WaitForChild("QuestSync")
local QuestClaim = Events:WaitForChild("QuestClaim")

-- Find the DailyQuestsF panel anywhere in PlayerGui.
local Panel
for _, gui in PlayerGui:GetChildren() do
	local f = gui:FindFirstChild("DailyQuestsF", true)
	if f then Panel = f; break end
end
if not Panel then
	warn("[Quest] DailyQuestsF not found in PlayerGui.")
	return
end

local Quest = Panel:FindFirstChild("Quest")
local ToggleBtn = Panel:FindFirstChild("ToggleBtn")
local TitleLbl = Panel:FindFirstChild("TitleLbl")

-- The panel's resting position + slide-out position (to the right).
local REST_POS = Panel.Position
local CLOSED_POS = REST_POS + UDim2.new(0.22, 0, 0, 0)
local isOpen = true
local payload = nil

-------------------------------------------------------------------------------
-- TOGGLE (slide closed/opened to the right)
-------------------------------------------------------------------------------
local function setOpen(open)
	isOpen = open
	if ToggleBtn then
		ToggleBtn.Text = open and ">" or "<"
	end
	TweenService:Create(
		Panel,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = open and REST_POS or CLOSED_POS }
	):Play()
end

if ToggleBtn then
	ToggleBtn.Activated:Connect(function()
		setOpen(not isOpen)
	end)
end

-------------------------------------------------------------------------------
-- RENDER QUESTS
-------------------------------------------------------------------------------
local function formatCountdown(secs)
	secs = math.max(0, math.floor(secs))
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function clearRows()
	if not Quest then return end
	for _, c in Quest:GetChildren() do
		if c:IsA("Frame") and c.Name:match("^Quest%d+$") then
			c:Destroy()
		end
	end
end

local function render(quests)
	clearRows()
	if not Quest then return end
	for _, q in quests do
		-- Find an existing QuestN frame to reuse (there should be 2 pre-made).
		local row = nil
		for _, c in Quest:GetChildren() do
			if c:IsA("Frame") and c.Name:match("^Quest%d+$") and not c:GetAttribute("Used") then
				row = c
				c:SetAttribute("Used", true)
				break
			end
		end
		-- If no free pre-made row, build one by cloning a used row.
		if not row then
			local anyRow
			for _, c in Quest:GetChildren() do
				if c:IsA("Frame") and c.Name:match("^Quest%d+$") then anyRow = c break end
			end
			if not anyRow then break end
			row = anyRow:Clone()
			row.Parent = Quest
		end
		row.Visible = true

		local desc = row:FindFirstChild("DescLbl")
		if desc then desc.Text = q.desc end
		local prog = row:FindFirstChild("ProgressLbl")
		if prog then prog.Text = tostring(q.progress) .. " / " .. tostring(q.target) end
		local rw = row:FindFirstChild("RewardLbl")
		if rw then rw.Text = q.reward end
		local claim = row:FindFirstChild("ClaimBtn")
		if claim then
			if q.claimed then
				claim.Text = "CLAIMED"
				claim.Active = false
			elseif q.done then
				claim.Text = "CLAIM"
				claim.Active = true
			else
				claim.Text = "NOT DONE"
				claim.Active = false
			end
			claim.Activated:Connect(function()
				if q.done and not q.claimed then
					QuestClaim:FireServer(q.id)
				end
			end)
		end
	end
end

-------------------------------------------------------------------------------
-- TIMER + SYNC
-------------------------------------------------------------------------------
-- Live reset countdown in the title.
RunService.Heartbeat:Connect(function()
	if not payload then return end
	local secsLeft = (payload.resetAt or 0) - os.time()
	if TitleLbl then
		TitleLbl.Text = "DAILY QUESTS (" .. formatCountdown(secsLeft) .. ")"
	end
end)

QuestSync.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	payload = data
	render(data.quests or {})
end)

-- Start closed if it should be.
setOpen(true)
