--[[
	StatsPanel.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives a small HUD panel (top-left) showing the player's Cash and Wins, with a
	"+" button next to each that will open a Shop later (placeholders for now).
	Uses a Frame + UIListLayout so the two rows stack cleanly and scale.

	REQUIRED UI (you build it in GameUI - see docs/UI_HIERARCHY.md):
		GameUI.StatsPanel  (Frame, top-left, background)
		  ├── UIListLayout      (Vertical, padding ~6)
		  ├── CashRow  (Frame)
		  │     ├── CashIcon   (TextLabel, optional, e.g. "$")
		  │     ├── CashLabel  (TextLabel)   "0"  (the Cash value)
		  │     └── CashPlus   (TextButton)  "+" -> opens shop later
		  └── WinRow   (Frame)
		        ├── WinIcon    (TextLabel, optional)
		        ├── WinLabel   (TextLabel)   "0"  (the Wins value)
		        └── WinPlus    (TextButton)  "+" -> opens shop later

	If you only place an empty `StatsPanel` frame, the script auto-builds the rest
	in Scale (never offset).
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")

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

	-- Icon (optional, transparent)
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

	-- Value label
	local label = row:FindFirstChild("Value")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Value"
		label.Size = UDim2.new(0.55, 0, 1, 0)
		label.Position = UDim2.new(0.2, 0, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = "0"
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Parent = row
	end

	-- "+" button (shop placeholder)
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
	local panel = GameUI:FindFirstChild("StatsPanel")
	if not panel then
		panel = Instance.new("Frame")
		panel.Name = "StatsPanel"
		panel.Size = UDim2.new(0.2, 0, 0.09, 0)
		panel.Position = UDim2.new(0.02, 0, 0.02, 0)
		panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		panel.BackgroundTransparency = 0.4
		panel.Parent = GameUI
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
-- LIVE UPDATE FROM leaderstats
-------------------------------------------------------------------------------
local function update()
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local cash = ls:FindFirstChild("Cash")
	local wins = ls:FindFirstChild("Wins")
	if cashValue then
		cashValue.Text = tostring(cash and cash.Value or 0)
	end
	if winValue then
		winValue.Text = tostring(wins and wins.Value or 0)
	end
end

local ls = player:WaitForChild("leaderstats", 10)
if ls then
	local cash = ls:FindFirstChild("Cash")
	local wins = ls:FindFirstChild("Wins")
	if cash then
		cash.Changed:Connect(update)
	end
	if wins then
		wins.Changed:Connect(update)
	end
end
update()

-------------------------------------------------------------------------------
-- "+" BUTTONS (shop placeholders)
-------------------------------------------------------------------------------
if cashPlus then
	cashPlus.Activated:Connect(function()
		print("[StatsPanel] Cash shop button clicked (shop not implemented yet).")
	end)
end
if winPlus then
	winPlus.Activated:Connect(function()
		print("[StatsPanel] Wins shop button clicked (shop not implemented yet).")
	end)
end
