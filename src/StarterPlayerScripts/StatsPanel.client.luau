--[[
	StatsPanel.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives a small HUD panel (top-left) showing the player's Cash and Wins, with a
	"+" button next to each that will open a Shop later (placeholders for now).
	Uses a Frame + UIListLayout so the two rows stack cleanly and scale.

	REQUIRED UI (you build it - see docs/UI_HIERARCHY.md):
		Currency.StatsPanel  (Frame, top-left, background)
		  ├── UIListLayout      (Vertical, padding ~6)
		  ├── CashRow  (Frame)
		  │     ├── Icon        (TextLabel, optional "$")
		  │     ├── Value       (TextLabel)  "$0"   (Cash, formatted with $ + commas)
		  │     └── Plus        (TextButton) "+" -> opens shop later
		  └── WinRow   (Frame)
		        ├── Icon        (TextLabel, optional "W")
		        ├── Value       (TextLabel)  "0"   (Wins, commas only, no $)
		        └── Plus        (TextButton) "+" -> opens shop later

	The panel is found inside the "Currency" ScreenGui first, then "GameUI" as a
	fallback. If only an empty StatsPanel exists, the script auto-builds the rest
	in Scale (never offset).
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Locate the StatsPanel: prefer the "Currency" ScreenGui, else "GameUI".
local function findPanelGui()
	for _, name in ipairs({ "Currency", "GameUI" }) do
		local gui = PlayerGui:FindFirstChild(name)
		if gui then
			local panel = gui:FindFirstChild("StatsPanel")
			if panel then
				return gui, panel
			end
		end
	end
	-- Fall back to Currency if present (to hold an auto-built panel).
	return PlayerGui:FindFirstChild("Currency") or PlayerGui:FindFirstChild("GameUI")
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
-- LIVE UPDATE FROM leaderstats
-------------------------------------------------------------------------------
-- Format a number with thousands separators, e.g. 2145 -> "2,145".
local function addCommas(n)
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	-- Remove a leading comma if present (e.g. from "1000" -> "1,000" edge).
	formatted = formatted:gsub("^,", "")
	return formatted
end

local function update()
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local cash = ls:FindFirstChild("Cash")
	local wins = ls:FindFirstChild("Wins")
	if cashValue then
		-- Cash: "$" prefix + commas, e.g. "$2,145".
		cashValue.Text = "$" .. addCommas(cash and cash.Value or 0)
	end
	if winValue then
		-- Wins: commas only (no $).
		winValue.Text = addCommas(wins and wins.Value or 0)
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
-- Open the Rewards window if RewardsController is present (else placeholder).
local function openRewards()
	if _G.RewardsAPI and _G.RewardsAPI.open then
		_G.RewardsAPI.open()
	else
		print("[StatsPanel] Rewards window not found (RewardsController not set up).")
	end
end

if cashPlus then
	cashPlus.Activated:Connect(function()
		openRewards()
	end)
end
if winPlus then
	winPlus.Activated:Connect(function()
		openRewards()
	end)
end
