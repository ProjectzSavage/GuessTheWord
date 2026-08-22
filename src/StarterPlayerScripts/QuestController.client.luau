--[[
	QuestController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Renders the DAILY QUESTS gui (strictly 2 active quests).
	Features:
	  * Displays exactly 2 quests with live progress and claim buttons.
	  * ToggleBtn manual collapse / expand.
	  * State-memory: if open when a GUI (Shop/Rewards) opens, slides closed,
	    and when that GUI closes, slides back open ONLY IF it wasn't previously
	    collapsed by the user. If already collapsed, it stays collapsed.
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
local QuestRequestSync = Events and (Events:FindFirstChild("QuestRequestSync") or Events:WaitForChild("QuestRequestSync", 10))

-- Safely locate GameUI inside PlayerGui
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

	f = PlayerGui:FindFirstChild("DailyQuestsF", true) or PlayerGui:FindFirstChild("DailyQuestF", true)
	if f and f:IsA("GuiObject") then
		return f
	end

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

-- Save a clean RowTemplate
local rowTemplate: GuiObject? = nil
if Quest then
	for _, child in ipairs(Quest:GetChildren()) do
		if child:IsA("Frame") and string.match(child.Name, "^Quest%d*") then
			rowTemplate = child:Clone()
			rowTemplate.Name = "QuestTemplate"
			rowTemplate.Visible = false
			break
		end
	end
end

-- Resting position + slide-out position (to the right)
local REST_POS = Panel.Position
local CLOSED_POS = REST_POS + UDim2.new(0.22, 0, 0, 0)

local isVisuallyOpen = true
local userWantsOpen = true -- Memory state: true if user left it open, false if user collapsed it
local payload = nil

-------------------------------------------------------------------------------
-- TOGGLE & STATE MEMORY
-------------------------------------------------------------------------------
local function setPanelOpen(open: boolean, isUserAction: boolean)
	if isUserAction then
		userWantsOpen = open
	end
	isVisuallyOpen = open

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
		setPanelOpen(not isVisuallyOpen, true)
	end)
end

-- State-Memory: only restores if user had left it open before opening GUI
_G.SetQuestsHiddenByGui = function(guiIsOpen: boolean)
	if guiIsOpen then
		if userWantsOpen and isVisuallyOpen then
			setPanelOpen(false, false)
		end
	else
		if userWantsOpen and not isVisuallyOpen then
			setPanelOpen(true, false)
		end
	end
end

-------------------------------------------------------------------------------
-- RENDER QUESTS (STRICTLY 2 QUESTS)
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
	for _, c in ipairs(Quest:GetChildren()) do
		if c:IsA("Frame") and string.match(c.Name, "^Quest%d+") then
			c:Destroy()
		end
	end
end

local function render(quests)
	if not Quest or not rowTemplate then return end
	clearRows()

	local maxQuests = math.min(#quests, 2)
	for idx = 1, maxQuests do
		local q = quests[idx]
		local row = rowTemplate:Clone()
		row.Name = "Quest" .. tostring(idx)
		row.Visible = true

		local desc = row:FindFirstChild("DescLbl", true) :: TextLabel?
		if desc and desc:IsA("TextLabel") then
			desc.Text = tostring(q.desc or "Quest")
		end

		local prog = row:FindFirstChild("ProgressLbl", true) :: TextLabel?
		if prog and prog:IsA("TextLabel") then
			prog.Text = tostring(q.progress or 0) .. " / " .. tostring(q.target or 1)
		end

		local rw = row:FindFirstChild("RewardLbl", true) :: TextLabel?
		if rw and rw:IsA("TextLabel") then
			rw.Text = tostring(q.reward or "")
		end

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

			claim.Activated:Connect(function()
				if q.done and not q.claimed and QuestClaim then
					claim.Text = "..."
					QuestClaim:FireServer(q.id)
				end
			end)
		end

		row.Parent = Quest
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

if QuestRequestSync then
	QuestRequestSync:FireServer()
end

setPanelOpen(true, true)
print("[QuestController] Ready - 2 Quests max & State-Memory toggle active")
