-- QuestController.luau
-- Client controller for Daily Quests
-- Fixes: Resolves DailyQuestsF safely inside PlayerGui.GameUI (or GameGui)
-- Supports variable quest rows, live cycle countdown timer, claim handling, and sliding toggle.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Safely locate GameUI / GameGui ScreenGui
local function resolveGameUI(): Instance
	local target = playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("GameGui")
	if target then
		return target
	end

	-- Wait up to 10 seconds for GameUI or GameGui
	local startTime = os.clock()
	while (os.clock() - startTime) < 10 do
		target = playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("GameGui")
		if target then
			return target
		end
		task.wait(0.1)
	end

	-- Search all ScreenGuis in PlayerGui for DailyQuestsF
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child:FindFirstChild("DailyQuestsF", true) then
			return child
		end
	end

	return playerGui:FindFirstChildWhichIsA("ScreenGui") or playerGui
end

local gameUI = resolveGameUI()

-- Helper to find child with alternative names recursively or directly
local function findObject(parent: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local found = parent:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return nil
end

-- Safely find DailyQuestsF frame inside GameUI
local panel: GuiObject? = findObject(gameUI, { "DailyQuestsF", "DailyQuestF", "QuestsF", "DailyQuestsPanel", "QuestsPanel" }) :: GuiObject?
if not panel then
	-- Fallback check in playerGui
	panel = findObject(playerGui, { "DailyQuestsF", "DailyQuestF", "QuestsF" }) :: GuiObject?
end

if not panel then
	-- If still not found, wait briefly with timeout
	local ok, res = pcall(function()
		return gameUI:WaitForChild("DailyQuestsF", 8)
	end)
	if ok and res then
		panel = res :: GuiObject
	end
end

if not panel then
	warn("[QuestController] DailyQuestsF not found in GameUI or PlayerGui.")
	return
end

-- UI References
local titleLbl = findObject(panel, { "TitleLbl", "Title", "HeaderLbl" }) :: TextLabel?
local toggleBtn = findObject(panel, { "ToggleBtn", "OpenBtn", "CloseBtn", "SlideBtn" }) :: TextButton?
if not toggleBtn then
	toggleBtn = findObject(gameUI, { "OpenQuestsBtn", "OpenQuestBtn", "QuestToggleBtn" }) :: TextButton?
end

local Events = RS:WaitForChild("Events", 15)
local DailyQuestSync = Events and (Events:FindFirstChild("DailyQuestSync") or Events:WaitForChild("DailyQuestSync", 10))
local DailyQuestClaim = Events and (Events:FindFirstChild("DailyQuestClaim") or Events:WaitForChild("DailyQuestClaim", 10))

local cycleEndsAt = os.time()

-- Collect available quest rows safely (Quest1..Quest6 or any Frame named Quest*)
local rows: { GuiObject } = {}
for i = 1, 12 do
	local row = panel:FindFirstChild("Quest" .. i, true)
	if row and row:IsA("GuiObject") then
		table.insert(rows, row)
	end
end

-- If not found by index, look for any frames named like Quest
if #rows == 0 then
	for _, child in ipairs(panel:GetDescendants()) do
		if child:IsA("GuiObject") and string.match(child.Name, "^Quest%d+") then
			table.insert(rows, child)
		end
	end
end

local function formatTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function updateRow(row: GuiObject, q: any)
	local desc = row:FindFirstChild("DescLbl", true) :: TextLabel?
	local prog = row:FindFirstChild("ProgressLbl", true) :: TextLabel?
	local reward = row:FindFirstChild("RewardLbl", true) :: TextLabel?
	local btn = row:FindFirstChild("ClaimBtn", true) :: TextButton?

	if desc and desc:IsA("TextLabel") then
		desc.Text = tostring(q.title or "Quest")
	end
	if prog and prog:IsA("TextLabel") then
		prog.Text = tostring(q.progress or 0) .. "/" .. tostring(q.required or 1)
	end
	if reward and reward:IsA("TextLabel") then
		local rewardAmt = tonumber(q.reward) or 0
		reward.Text = "+$" .. tostring(rewardAmt)
	end

	if not (btn and btn:IsA("TextButton")) then
		return
	end

	btn.Active = (q.claimable == true and not q.claimed)
	row:SetAttribute("QuestId", q.id)

	if q.claimed then
		btn.Text = "CLAIMED"
		btn.BackgroundColor3 = Color3.fromRGB(40, 190, 70)
		btn.AutoButtonColor = false
	elseif q.claimable then
		btn.Text = "CLAIM"
		btn.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
		btn.AutoButtonColor = true
	else
		btn.Text = "LOCKED"
		btn.BackgroundColor3 = Color3.fromRGB(80, 80, 85)
		btn.AutoButtonColor = false
	end

	-- Wire claim connection once per row
	if not row:GetAttribute("Wired") then
		btn.MouseButton1Click:Connect(function()
			if btn.Text ~= "CLAIM" then
				return
			end
			local questId = row:GetAttribute("QuestId")
			if type(questId) ~= "string" or questId == "" then
				return
			end
			btn.Text = "..."
			if DailyQuestClaim and DailyQuestClaim:IsA("RemoteEvent") then
				DailyQuestClaim:FireServer(questId)
			end
		end)
		row:SetAttribute("Wired", true)
	end
end

if DailyQuestSync and DailyQuestSync:IsA("RemoteEvent") then
	DailyQuestSync.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		cycleEndsAt = tonumber(payload.cycleEndsAt) or os.time()

		local quests = payload.quests
		if type(quests) ~= "table" then
			return
		end

		for i, row in ipairs(rows) do
			local q = quests[i]
			row.Visible = (q ~= nil)
			if q then
				updateRow(row, q)
			end
		end
	end)
end

-- Live cycle countdown in header title
task.spawn(function()
	while panel and panel.Parent do
		if titleLbl and titleLbl:IsA("TextLabel") then
			local left = (tonumber(cycleEndsAt) or os.time()) - os.time()
			titleLbl.Text = "Daily Quests (" .. formatTime(left) .. ")"
		end
		task.wait(1)
	end
end)

-- Sliding toggle animation setup if ToggleBtn exists
if toggleBtn and toggleBtn:IsA("GuiButton") then
	local openPos = panel.Position
	local closedPos = UDim2.new(panel.Position.X.Scale + 0.22, panel.Position.X.Offset, panel.Position.Y.Scale, panel.Position.Y.Offset)
	local isQuestOpen = true

	local function setQuestOpen(open: boolean)
		isQuestOpen = open
		toggleBtn.Text = open and ">" or "<"
		TweenService:Create(
			panel,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = open and openPos or closedPos }
		):Play()
	end

	toggleBtn.MouseButton1Click:Connect(function()
		setQuestOpen(not isQuestOpen)
	end)
end

print("[QuestController] Ready - Loaded successfully from GameUI")
