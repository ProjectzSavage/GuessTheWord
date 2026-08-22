--!strict
-- StatsHudController.luau
-- Manages StatsPanel HUD (Cash, Wins, Winstreak)
-- Features:
-- 1. Money formatting with NumberFormat (compact/commas).
-- 2. Animated money gain: smooth number count-up, punch/pop scale bounce, color flash, and floating "+$X" gain popup.
-- 3. StatsPanel sliding: animates UP when any GUI opens, and returns BACK down when closed.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local NumberFormat = require(RS:WaitForChild("NumberFormat"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Safely resolve GameUI / GameGui ScreenGui
local function resolveGameUI(): Instance
	local target = playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("GameGui")
	if target then
		return target
	end

	local startTime = os.clock()
	while (os.clock() - startTime) < 10 do
		target = playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("GameGui")
		if target then
			return target
		end
		task.wait(0.1)
	end

	return playerGui:FindFirstChildWhichIsA("ScreenGui") or playerGui
end

local gameUI = resolveGameUI()

-- Helper to find GUI element by names
local function findObject(parent: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local found = parent:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return nil
end

local statsPanel = findObject(gameUI, { "StatsPanel", "StatsFrame", "StatsBar", "PlayerStatsPanel" }) :: GuiObject?
if not statsPanel then
	local ok, res = pcall(function()
		return gameUI:WaitForChild("StatsPanel", 8)
	end)
	if ok and res then
		statsPanel = res :: GuiObject
	else
		local ok2, res2 = pcall(function()
			return gameUI:WaitForChild("StatsFrame", 5)
		end)
		if ok2 and res2 then
			statsPanel = res2 :: GuiObject
		end
	end
end

if not statsPanel then
	warn("[StatsHudController] StatsPanel / StatsFrame not found in GameUI")
	return
end

local CashLbl = findObject(statsPanel, { "CashLbl", "CashLabel", "MoneyLbl", "CoinsLbl", "CashText" }) :: TextLabel?
local WinsLbl = findObject(statsPanel, { "WinsLbl", "WinsLabel", "WinLbl", "WinsText" }) :: TextLabel?
local StreakLbl = findObject(statsPanel, { "StreakLbl", "WinstreakLbl", "StreakLabel", "StreakText" }) :: TextLabel?

local leaderstats = player:WaitForChild("leaderstats", 15) :: Folder?
local Cash = leaderstats and (leaderstats:WaitForChild("Cash", 10) :: IntValue?)
local Wins = leaderstats and (leaderstats:WaitForChild("Wins", 10) :: IntValue?)
local Winstreak = leaderstats and (leaderstats:FindFirstChild("Winstreak") or leaderstats:FindFirstChild("Streak")) :: IntValue?

-- ============================================================================
-- 1. STATS PANEL SLIDING (UP when GUI opens, BACK DOWN when GUI closes)
-- ============================================================================
local basePosition = statsPanel.Position
local isStatsPanelUp = false

-- Calculate target UP position (slides upward out of the way)
local function getUpPosition(): UDim2
	local panelHeight = statsPanel.AbsoluteSize.Y
	if panelHeight <= 0 then
		panelHeight = 70
	end
	-- Slide upwards above the screen or offset
	return UDim2.new(basePosition.X.Scale, basePosition.X.Offset, 0, -panelHeight - 20)
end

local function setStatsPanelUp(up: boolean)
	if isStatsPanelUp == up then
		return
	end
	isStatsPanelUp = up

	local targetPos = up and getUpPosition() or basePosition
	local tweenInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(statsPanel, tweenInfo, { Position = targetPos }):Play()
end

_G.SetStatsPanelUp = setStatsPanelUp

-- ============================================================================
-- 2. MONEY FORMATTING & ANIMATION
-- ============================================================================
local displayedCash = (Cash and Cash.Value) or 0
local cashCounterConn: RBXScriptConnection? = nil
local defaultCashColor = CashLbl and CashLbl.TextColor3 or Color3.fromRGB(255, 255, 255)

-- Ensure UIScale on CashLbl for punch/bounce animation
local cashScale: UIScale? = nil
if CashLbl then
	cashScale = CashLbl:FindFirstChild("CashScale") :: UIScale?
	if not cashScale then
		cashScale = Instance.new("UIScale")
		cashScale.Name = "CashScale"
		cashScale.Scale = 1
		cashScale.Parent = CashLbl
	end
end

-- Spawns floating "+$Amount" gain effect
local function spawnFloatingCashGain(amount: number)
	if not CashLbl or amount <= 0 then
		return
	end

	local container = CashLbl.Parent
	if not container or not container:IsA("GuiObject") then
		container = statsPanel
	end

	local floatLbl = Instance.new("TextLabel")
	floatLbl.Name = "CashGainPopup"
	floatLbl.BackgroundTransparency = 1
	floatLbl.Size = UDim2.new(0, 140, 0, 30)
	floatLbl.Position = UDim2.new(CashLbl.Position.X.Scale, CashLbl.Position.X.Offset, CashLbl.Position.Y.Scale, CashLbl.Position.Y.Offset - 10)
	floatLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	floatLbl.Font = CashLbl.Font or Enum.Font.FredokaOne
	floatLbl.TextSize = 22
	floatLbl.TextColor3 = Color3.fromRGB(80, 255, 120) -- bright neon green/gold
	floatLbl.TextStrokeTransparency = 0.2
	floatLbl.TextStrokeColor3 = Color3.fromRGB(0, 50, 0)
	floatLbl.Text = "+$" .. NumberFormat.commas(amount)
	floatLbl.ZIndex = 50
	floatLbl.Parent = container

	local endPos = UDim2.new(floatLbl.Position.X.Scale, floatLbl.Position.X.Offset, floatLbl.Position.Y.Scale, floatLbl.Position.Y.Offset - 35)
	local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	local tweenMove = TweenService:Create(floatLbl, tweenInfo, {
		Position = endPos,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	tweenMove:Play()
	tweenMove.Completed:Connect(function()
		floatLbl:Destroy()
	end)
end

-- Plays scale punch/bounce animation & color pulse on cash gain
local function playCashGainPunch()
	if not CashLbl or not cashScale then
		return
	end

	-- Bounce scale: 1 -> 1.28 -> 1.0
	cashScale.Scale = 1.28
	local popTween = TweenService:Create(
		cashScale,
		TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	popTween:Play()

	-- Color flash to gold/green then back
	CashLbl.TextColor3 = Color3.fromRGB(255, 230, 80)
	local colorTween = TweenService:Create(
		CashLbl,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextColor3 = defaultCashColor }
	)
	colorTween:Play()
end

-- Smooth number counter / lerp animation from startVal to targetVal
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
		-- Ease out quad
		local eased = 1 - (1 - alpha) * (1 - alpha)
		local current = math.floor(fromVal + diff * eased)
		displayedCash = current

		if CashLbl then
			CashLbl.Text = "$" .. NumberFormat.compact(current)
		end

		if alpha >= 1 then
			if cashCounterConn then
				cashCounterConn:Disconnect()
				cashCounterConn = nil
			end
			displayedCash = toVal
			if CashLbl then
				CashLbl.Text = "$" .. NumberFormat.compact(toVal)
			end
		end
	end)
end

local function onCashChanged()
	if not Cash then
		return
	end
	local newCash = Cash.Value
	local diff = newCash - displayedCash

	if diff > 0 then
		-- Cash Gained: trigger bounce, floating gain text, and smooth number counter
		playCashGainPunch()
		spawnFloatingCashGain(diff)
		animateCashCounter(displayedCash, newCash)
	else
		-- Cash decreased or unchanged
		if cashCounterConn then
			cashCounterConn:Disconnect()
			cashCounterConn = nil
		end
		displayedCash = newCash
		if CashLbl then
			CashLbl.Text = "$" .. NumberFormat.compact(newCash)
		end
	end
end

local function updateWins()
	if WinsLbl and Wins then
		WinsLbl.Text = NumberFormat.compact(Wins.Value)
	end
end

local function updateStreak()
	if StreakLbl and Winstreak then
		StreakLbl.Text = "🔥" .. NumberFormat.compact(Winstreak.Value)
	end
end

if Cash then
	displayedCash = Cash.Value
	if CashLbl then
		CashLbl.Text = "$" .. NumberFormat.compact(displayedCash)
	end
	Cash:GetPropertyChangedSignal("Value"):Connect(onCashChanged)
end

if Wins then
	updateWins()
	Wins:GetPropertyChangedSignal("Value"):Connect(updateWins)
end

if Winstreak then
	updateStreak()
	Winstreak:GetPropertyChangedSignal("Value"):Connect(updateStreak)
end

print("[StatsHudController] Ready - Money formatting, gain animations & StatsPanel slider enabled")
