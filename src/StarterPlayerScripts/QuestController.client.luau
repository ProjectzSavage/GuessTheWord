--[[
	QuestController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Renders the DAILY QUESTS gui and drives its toggle. The server (QuestService)
	sends a `payload` with quests (desc, progress, target, reward, claimed, done)
	and a reset countdown. This client fills the Quest gui rows, wires ClaimBtns,
	and slides the panel closed/opened via ToggleBtn.

	REQUIRED UI:
		GameUI
		└── DailyQuestsF  (Frame, Position {0.776,0},{0.034,0})
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

local Events = ReplicatedStorage:WaitForChild("Events", 15)
local QuestSync = Events and (Events:FindFirstChild("QuestSync") or Events:WaitForChild("QuestSync", 10))
local QuestClaim = Events and (Events:FindFirstChild("QuestClaim") or Events:WaitForChild("QuestClaim", 10))

-- Safely locate GameUI inside PlayerGui (with fallback search)
local function resolveGameUI(): Instance
	local target = PlayerGui:FindFirstChild("GameUI") or PlayerGui:FindFirstChild("GameGui")
	if target then
		return target
	end

	local startTime = os.clock()
	while (os.clock() - startTime) < 10 do
		target = PlayerGui:FindFirstChild("GameUI") or PlayerGui:FindFirstChild("GameGui")
		if target then
			return target
		end
		task.wait(0.1)
	end

	-- Search across all ScreenGuis for DailyQuestsF
	for _, child in ipairs(PlayerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child:FindFirstChild("DailyQuestsF", true) then
			return child
		end
	end

	return PlayerGui:FindFirstChildWhichIsA("ScreenGui") or PlayerGui
end

local gameUI = resolveGameUI()

-- Safely locate DailyQuestsF inside GameUI
local function resolvePanel(): GuiObject?
	local f = gameUI:FindFirstChild("DailyQuestsF", true) or gameUI:FindFirstChild("DailyQuestF", true)
	if f and f:IsA("GuiObject") then
		return f
	end

	-- Check PlayerGui as fallback
	f = PlayerGui:FindFirstChild("DailyQuestsF", true) or PlayerGui:FindFirstChild("DailyQuestF", true)
	if f and f:IsA("GuiObject") then
		return f
	end

	-- Wait with timeout
	local ok, res = pcall(function()
		return gameUI:WaitForChild("DailyQuestsF", 8)
	end)
	if ok and res and res:IsA("GuiObject") then
		return res
	end

	return nil
end

local Panel = resolvePanel()
if not Panel then
	warn("[Quest] DailyQuestsF not found in GameUI.")
	return
end

local Quest = Panel:FindFirstChild("Quest") or Panel:FindFirstChild("Quests") or Panel
local ToggleBtn = Panel:FindFirstChild("ToggleBtn", true) :: TextButton?
local TitleLbl = Panel:FindFirstChild("TitleLbl", true) :: TextLabel?

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

		local desc = row:FindFirstChild("DescLbl", true) :: TextLabel?
		if desc and desc:IsA("TextLabel") then desc.Text = q.desc end

		local prog = row:FindFirstChild("ProgressLbl", true) :: TextLabel?
		if prog and prog:IsA("TextLabel") then prog.Text = tostring(q.progress) .. " / " .. tostring(q.target) end

		local rw = row:FindFirstChild("RewardLbl", true) :: TextLabel?
		if rw and rw:IsA("TextLabel") then rw.Text = q.reward end

		local claim = row:FindFirstChild("ClaimBtn", true) :: TextButton?
		if claim and claim:IsA("TextButton") then
			if q.claimed then
				claim.Text = "CLAIMED"
				claim.Active = false
				claim.AutoButtonColor = false
				claim.BackgroundColor3 = Color3.fromRGB(40, 190, 70)
			elseif q.done then
				claim.Text = "CLAIM"
				claim.Active = true
				claim.AutoButtonColor = true
				claim.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
			else
				claim.Text = "NOT DONE"
				claim.Active = false
				claim.AutoButtonColor = false
				claim.BackgroundColor3 = Color3.fromRGB(80, 80, 85)
			end

			if not row:GetAttribute("ClaimBound") then
				claim.Activated:Connect(function()
					if q.done and not q.claimed and QuestClaim then
						claim.Text = "..."
						QuestClaim:FireServer(q.id)
					end
				end)
				row:SetAttribute("ClaimBound", true)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- TIMER + SYNC
-------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	if not payload then return end
	local secsLeft = (payload.resetAt or 0) - os.time()
	if TitleLbl then
		TitleLbl.Text = "DAILY QUESTS (" .. formatCountdown(secsLeft) .. ")"
	end
end)

if QuestSync then
	QuestSync.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		payload = data
		render(data.quests or {})
	end)
end

setOpen(true)
print("[QuestController] Ready - Loaded successfully from GameUI")
