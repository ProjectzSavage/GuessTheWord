--!strict
-- UIWindowsController.luau
-- Central Window & Environment Manager for GameUI
-- Features:
-- 1. Mutual Exclusivity: Only 1 window visible at a time across Shop, Rewards, Quests/Inventory.
--    Opening one window immediately hides the previous one so they never overlap.
-- 2. Toggler Support: Clicking the toggler button when a window is open closes it cleanly (fixes Rewards toggle bug).
-- 3. Environment FX: Smoothly increases Camera FOV and enables Lighting Blur when any window opens;
--    restores FOV and removes Blur when all windows are closed.
-- 4. StatsPanel Motion: Animates StatsPanel UP when any window opens, and back down when closed.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

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

-- Remote Events
local events = RS:FindFirstChild("Events")
local ShopRequestRefresh = events and events:FindFirstChild("ShopRequestRefresh")
local RewardRequestSync = events and events:FindFirstChild("RewardRequestSync")
local RequestSync = events and events:FindFirstChild("RequestSync")

-- ============================================================================
-- ENVIRONMENT CONFIG (FOV, Blur, Tweening)
-- ============================================================================
local BASE_FOV = 70
local OPEN_FOV = 82
local OPEN_BLUR_SIZE = 18

local OPEN_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

-- Create / Locate Lighting Blur
local blurEffect: BlurEffect = Lighting:FindFirstChild("GuiWindowBlur") :: BlurEffect
if not blurEffect or not blurEffect:IsA("BlurEffect") then
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "GuiWindowBlur"
	blurEffect.Size = 0
	blurEffect.Enabled = false
	blurEffect.Parent = Lighting
end

type WindowDef = {
	id: string,
	panelNames: { string },
	openBtnNames: { string },
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

type WindowEntry = {
	id: string,
	panel: GuiObject,
	openBtn: GuiButton?,
	closeBtn: GuiButton?,
	basePosition: UDim2,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

local windows: { [string]: WindowEntry } = {}
local activeId: string? = nil
local busy = false

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================
local function findFirstByNames(root: Instance, names: { string }): Instance?
	for _, n in ipairs(names) do
		local f = root:FindFirstChild(n, true)
		if f then
			return f
		end
	end
	return nil
end

local function ensureScale(panel: GuiObject): UIScale
	local s = panel:FindFirstChild("UIWindowScale") :: UIScale?
	if not s or not s:IsA("UIScale") then
		s = Instance.new("UIScale")
		s.Name = "UIWindowScale"
		s.Scale = 1
		s.Parent = panel
	end
	return s
end

local function applyEnvironmentOpen()
	-- 1. Increase Camera FOV
	TweenService:Create(
		camera,
		TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ FieldOfView = OPEN_FOV }
	):Play()

	-- 2. Lighting Blur
	blurEffect.Enabled = true
	TweenService:Create(
		blurEffect,
		TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = OPEN_BLUR_SIZE }
	):Play()

	-- 3. StatsPanel slide UP
	if _G.SetStatsPanelUp then
		_G.SetStatsPanelUp(true)
	end
end

local function applyEnvironmentClose()
	-- 1. Restore Camera FOV
	TweenService:Create(
		camera,
		TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ FieldOfView = BASE_FOV }
	):Play()

	-- 2. Lighting Blur back to 0
	local blurTween = TweenService:Create(
		blurEffect,
		TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = 0 }
	)
	blurTween:Play()
	blurTween.Completed:Connect(function()
		if activeId == nil then
			blurEffect.Enabled = false
		end
	end)

	-- 3. StatsPanel slide BACK DOWN
	if _G.SetStatsPanelUp then
		_G.SetStatsPanelUp(false)
	end
end

-- ============================================================================
-- WINDOW ANIMATION & TRANSITIONS
-- ============================================================================
local function hideWindowImmediate(w: WindowEntry)
	if not w or not w.panel then
		return
	end
	w.panel.Visible = false
	w.panel.Position = w.basePosition
	local scale = w.panel:FindFirstChild("UIWindowScale") :: UIScale?
	if scale then
		scale.Scale = 1
	end
	if w.onClose then
		pcall(w.onClose)
	end
end

local function animateWindowOpen(w: WindowEntry)
	local panel = w.panel
	local scale = ensureScale(panel)

	panel.Visible = true
	panel.Position = w.basePosition + UDim2.fromOffset(0, 16)
	scale.Scale = 0.94

	TweenService:Create(scale, OPEN_TWEEN, { Scale = 1 }):Play()
	TweenService:Create(panel, OPEN_TWEEN, { Position = w.basePosition }):Play()

	if w.onOpen then
		pcall(w.onOpen)
	end
end

local function animateWindowClose(w: WindowEntry, onDone: (() -> ())?)
	local panel = w.panel
	local scale = ensureScale(panel)
	local endPos = w.basePosition + UDim2.fromOffset(0, 16)

	TweenService:Create(scale, CLOSE_TWEEN, { Scale = 0.94 }):Play()
	local posTween = TweenService:Create(panel, CLOSE_TWEEN, { Position = endPos })
	posTween:Play()

	posTween.Completed:Connect(function()
		panel.Visible = false
		panel.Position = w.basePosition
		scale.Scale = 1
		if w.onClose then
			pcall(w.onClose)
		end
		if onDone then
			onDone()
		end
	end)
end

-- ============================================================================
-- WINDOW CONTROLLER METHODS (Open, Close, Toggle)
-- ============================================================================
local function closeWindow(id: string)
	if busy then
		return
	end
	local w = windows[id]
	if not w or not w.panel then
		return
	end

	busy = true
	animateWindowClose(w, function()
		if activeId == id then
			activeId = nil
			applyEnvironmentClose()
		end
		busy = false
	end)
end

local function openWindow(id: string)
	if busy then
		return
	end
	local w = windows[id]
	if not w or not w.panel then
		return
	end

	-- TOGGLE BEHAVIOR: If already open and active, clicking toggler closes it!
	if activeId == id and w.panel.Visible then
		busy = true
		animateWindowClose(w, function()
			activeId = nil
			applyEnvironmentClose()
			busy = false
		end)
		return
	end

	busy = true

	-- MUTUAL EXCLUSIVITY: Immediately hide any previous window so they NEVER overlap
	if activeId and activeId ~= id then
		local prev = windows[activeId]
		if prev then
			hideWindowImmediate(prev)
		end
		activeId = nil
	end

	-- Safety check: hide all other registered windows
	for otherId, otherW in pairs(windows) do
		if otherId ~= id and otherW.panel and otherW.panel.Visible then
			hideWindowImmediate(otherW)
		end
	end

	activeId = id
	applyEnvironmentOpen()
	animateWindowOpen(w)

	task.delay(OPEN_TWEEN.Time + 0.02, function()
		busy = false
	end)
end

local function toggleWindow(id: string)
	openWindow(id)
end

-- ============================================================================
-- REGISTRATION
-- ============================================================================
local function registerWindow(def: WindowDef)
	local panel = findFirstByNames(gameUI, def.panelNames) :: GuiObject?
	if not panel or not panel:IsA("GuiObject") then
		warn("[UIWindowsController] Missing panel for window:", def.id)
		return
	end

	local openBtn = findFirstByNames(gameUI, def.openBtnNames) :: GuiButton?
	local closeBtn = findFirstByNames(panel, { "CloseBtn", "Close", "XBtn", "ExitBtn" }) :: GuiButton?

	local w: WindowEntry = {
		id = def.id,
		panel = panel,
		openBtn = openBtn,
		closeBtn = closeBtn,
		basePosition = panel.Position,
		onOpen = def.onOpen,
		onClose = def.onClose,
	}
	windows[def.id] = w

	panel.Visible = false
	ensureScale(panel).Scale = 1

	if openBtn and openBtn:IsA("GuiButton") then
		openBtn.MouseButton1Click:Connect(function()
			toggleWindow(def.id)
		end)
	end

	if closeBtn and closeBtn:IsA("GuiButton") then
		closeBtn.MouseButton1Click:Connect(function()
			closeWindow(def.id)
		end)
	end
end

-- 1. Shop Window
registerWindow({
	id = "shop",
	panelNames = { "ShopF", "ShopFrame", "ShopPanel" },
	openBtnNames = { "OpenShopBtn", "ShopBtn" },
	onOpen = function()
		if ShopRequestRefresh and ShopRequestRefresh:IsA("RemoteEvent") then
			ShopRequestRefresh:FireServer()
		end
	end,
})

-- 2. Rewards Window
registerWindow({
	id = "rewards",
	panelNames = { "RewardsF", "RewardsFrame", "RewardsPanel" },
	openBtnNames = { "OpenRewardsBtn", "RewardsBtn" },
	onOpen = function()
		if RewardRequestSync and RewardRequestSync:IsA("RemoteEvent") then
			RewardRequestSync:FireServer()
		end
		if _G.OnRewardsOpen then
			pcall(_G.OnRewardsOpen)
		end
	end,
	onClose = function()
		if _G.OnRewardsClose then
			pcall(_G.OnRewardsClose)
		end
	end,
})

-- 3. Quests / Inventory Window
registerWindow({
	id = "quests",
	panelNames = { "DailyQuestsF", "DailyQuestF", "QuestsF", "ChairInvPanel", "InventoryF", "InvF" },
	openBtnNames = { "OpenQuestsBtn", "OpenQuestBtn", "OpenChairInvBtn", "OpenInventoryBtn", "OpenInvBtn" },
	onOpen = function()
		if RequestSync and RequestSync:IsA("RemoteFunction") then
			pcall(function()
				RequestSync:InvokeServer()
			end)
		end
	end,
})

-- Expose global API
_G.UIWindows = {
	open = openWindow,
	close = closeWindow,
	toggle = toggleWindow,
	getActiveId = function()
		return activeId
	end,
	register = registerWindow,
}

_G.UIWindowAnimator = _G.UIWindows

print("[UIWindowsController] Ready - 3 Windows mutual exclusion, FOV, Blur, and Toggler active")
