--[[
	StatsPanel.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives HUD panel (top-left) showing the player's Cash and Wins.
	Features:
	  * Number formatting with NumberFormat (compact/commas).
	  * Money gain animation: smooth number lerp, pop/punch scale bounce, color glow, and floating "+$X" popup.
	  * StatsPanel sliding: animates UP when any GUI opens, and BACK down when closed.
	  * "+" button next to Cash / Wins opens the Shop or Rewards window.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))
local SFX = require(ReplicatedStorage:WaitForChild("SFX"))

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Locate the StatsPanel: prefer the "Currency" ScreenGui, else "GameUI".
local function findPanelGui()
	for _, name in ipairs({ "Currency"}) do
		local gui = PlayerGui:FindFirstChild(name)
		if gui then
			local panel = gui:WaitForChild("StatsPanel")
			if panel then
				return gui, panel
			end
		end
	end
	return PlayerGui:WaitForChild("Currency")
end

local panelGui = findPanelGui()
local PanelRoot = panelGui or Instance.new("ScreenGui")

-------------------------------------------------------------------------------
-- BUILD / AUTO-CREATE
-------------------------------------------------------------------------------
local function ensureRow(panel, rowName, title)
	local row = panel:FindFirstChild(rowName)
	if not row then
		row = Instance.new("Frame")
		row.Name = rowName
		row.Size = UDim2.new(1, 0, 0.5, 0)
		row.BackgroundTransparency = 1
		row.Parent = panel
	end

	local icon = row:FindFirstChild("Icon")
	if not icon then
		icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.2, 0, 1, 0)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.GothamBold
		icon.Text = title
		icon.TextColor3 = Color3.fromRGB(255, 200, 90)
		icon.TextScaled = true
		icon.Parent = row
	end

	local label = row:FindFirstChild("Value")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Value"
		label.Size = UDim2.new(0.55, 0, 1, 0)
		label.Position = UDim2.new(0.2, 0, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = "$0"
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Parent = row
	end

	local plus = row:FindFirstChild("Plus")
	if not plus then
		plus = Instance.new("TextButton")
		plus.Name = "Plus"
		plus.Size = UDim2.new(0.25, 0, 1, 0)
		plus.Position = UDim2.new(0.75, 0, 0, 0)
		plus.BackgroundColor3 = Color3.fromRGB(60, 140, 70)
		plus.Font = Enum.Font.GothamBlack
		plus.Text = "+"
		plus.TextColor3 = Color3.new(1, 1, 1)
		plus.TextScaled = true
		plus.Parent = row
	end

	return icon, label, plus
end

local function buildPanel()
	local panel = PanelRoot:FindFirstChild("StatsPanel")
	if not panel then
		panel = Instance.new("Frame")
		panel.Name = "StatsPanel"
		panel.Size = UDim2.new(0.2, 0, 0.09, 0)
		panel.Position = UDim2.new(0.02, 0, 0.02, 0)
		panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		panel.BackgroundTransparency = 0.4
		if not PanelRoot.Parent then
			PanelRoot.Name = "Currency"
			PanelRoot.Parent = PlayerGui
		end
		panel.Parent = PanelRoot
	end

	local layout = panel:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, 4)
		layout.Parent = panel
	end

	local cashIcon, cashVal, cashPlus = ensureRow(panel, "CashRow", "$")
	local winIcon, winVal, winPlus = ensureRow(panel, "WinRow", "W")

	return panel, cashVal, cashPlus, winVal, winPlus
end

local panel, cashValue, cashPlus, winValue, winPlus = buildPanel()

-------------------------------------------------------------------------------
-- STATSPANEL SLIDING (UP when GUI opens, BACK DOWN when closed)
-------------------------------------------------------------------------------
local panelRestPos = panel.Position
local SLIDE_UP_POS = UDim2.new(panelRestPos.X.Scale, panelRestPos.X.Offset, 0, -100)
local isPanelSlidUp = false

local function setStatsPanelUp(up: boolean)
	if not panel then return end
	if isPanelSlidUp == up then return end
	isPanelSlidUp = up

	local targetPos = up and SLIDE_UP_POS or panelRestPos
	TweenService:Create(
		panel,
		TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = targetPos }
	):Play()
end

_G.SetStatsPanelUp = setStatsPanelUp

-------------------------------------------------------------------------------
-- MONEY FORMATTING & ANIMATIONS
-------------------------------------------------------------------------------
local displayedCash = 0
local cashCounterConn: RBXScriptConnection? = nil
local defaultCashColor = cashValue and cashValue.TextColor3 or Color3.new(1, 1, 1)

-- Ensure UIScale on cashValue for punch/bounce animation
local cashScale: UIScale? = nil
if cashValue then
	cashScale = cashValue:FindFirstChild("CashScale") :: UIScale?
	if not cashScale then
		cashScale = Instance.new("UIScale")
		cashScale.Name = "CashScale"
		cashScale.Scale = 1
		cashScale.Parent = cashValue
	end
end

-- Floating "+$Amount" gain effect
local function spawnFloatingCashGain(amount: number)
	if not cashValue or amount <= 0 then return end
	local container = panel

	local floatLbl = Instance.new("TextLabel")
	floatLbl.Name = "CashGainPopup"
	floatLbl.BackgroundTransparency = 1
	floatLbl.Size = UDim2.new(0, 120, 0, 26)
	floatLbl.Position = UDim2.new(0.5, 0, 0.2, 0)
	floatLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	floatLbl.Font = cashValue.Font or Enum.Font.GothamBold
	floatLbl.TextSize = 24
	floatLbl.TextColor3 = Color3.fromRGB(80, 255, 120)
	floatLbl.TextStrokeTransparency = 0.1
	floatLbl.TextStrokeColor3 = Color3.fromRGB(0, 60, 10)
	floatLbl.Text = "+$" .. NumberFormat.commas(amount)
	floatLbl.ZIndex = 50
	floatLbl.Parent = container

	local endPos = UDim2.new(0.5, 0, -0.6, 0)
	local tween = TweenService:Create(
		floatLbl,
		TweenInfo.new(1.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{
			Position = endPos,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	tween:Play()
	tween.Completed:Connect(function()
		floatLbl:Destroy()
	end)
end

-- Scale bounce / punch animation
local function playCashGainPunch()
	if not cashValue or not cashScale then return end

	cashScale.Scale = 1.28
	local popTween = TweenService:Create(
		cashScale,
		TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	popTween:Play()

	cashValue.TextColor3 = Color3.fromRGB(255, 230, 80)
	local colorTween = TweenService:Create(
		cashValue,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextColor3 = defaultCashColor }
	)
	colorTween:Play()
end

-- Number counter lerp
local function animateCashCounter(fromVal: number, toVal: number)
	if cashCounterConn then
		cashCounterConn:Disconnect()
		cashCounterConn = nil
	end

	local duration = 0.4
	local elapsed = 0
	local diff = toVal - fromVal

	cashCounterConn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local alpha = math.clamp(elapsed / duration, 0, 1)
		local eased = 1 - (1 - alpha) * (1 - alpha)
		local current = math.floor(fromVal + diff * eased)
		displayedCash = current

		if cashValue then
			cashValue.Text = "$" .. NumberFormat.compact(current)
		end

		if alpha >= 1 then
			if cashCounterConn then
				cashCounterConn:Disconnect()
				cashCounterConn = nil
			end
			displayedCash = toVal
			if cashValue then
				cashValue.Text = "$" .. NumberFormat.compact(toVal)
			end
		end
	end)
end

local function onCashChanged(newVal: number)
	local diff = newVal - displayedCash
	if diff > 0 then
		playCashGainPunch()
		spawnFloatingCashGain(diff)
		animateCashCounter(displayedCash, newVal)
		SFX.play("cash")
	else
		if cashCounterConn then
			cashCounterConn:Disconnect()
			cashCounterConn = nil
		end
		displayedCash = newVal
		if cashValue then
			cashValue.Text = "$" .. NumberFormat.compact(newVal)
		end
	end
end

local function updateWins(newVal: number)
	if winValue then
		winValue.Text = NumberFormat.compact(newVal)
	end
end

local ls = player:WaitForChild("leaderstats", 10)
if ls then
	local cash = ls:FindFirstChild("Cash")
	local wins = ls:FindFirstChild("Wins")

	if cash then
		displayedCash = cash.Value
		if cashValue then
			cashValue.Text = "$" .. NumberFormat.compact(displayedCash)
		end
		cash.Changed:Connect(function(v)
			onCashChanged(v)
		end)
	end

	if wins then
		updateWins(wins.Value)
		wins.Changed:Connect(function(v)
			updateWins(v)
		end)
	end
end

-- NOTE: the panel slide is driven ONLY by window open/close (UIFX calls
-- _G.SetStatsPanelUp). It used to also slide on CashAwarded / GameOver, which
-- made it jump "at the wrong time" (e.g. just sitting in a chair fired the
-- waiting-state UI and slid it up without any game starting).

-------------------------------------------------------------------------------
-- "+" BUTTONS (Shop / Rewards access)
-------------------------------------------------------------------------------
local function openShopOrRewards()
	if _G.ShopAPI and _G.ShopAPI.open then
		_G.ShopAPI.open()
	elseif _G.RewardsAPI and _G.RewardsAPI.open then
		_G.RewardsAPI.open()
	end
end

if cashPlus then
	cashPlus.Activated:Connect(function()
		openShopOrRewards()
	end)
end
if winPlus then
	winPlus.Activated:Connect(function()
		openShopOrRewards()
	end)
end


