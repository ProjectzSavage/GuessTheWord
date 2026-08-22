--!strict
-- StatsShopQuickAccess.luau
-- Quick-access buttons from StatsPanel directly opening and scrolling Shop items

local Players = game:GetService("Players")
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

local gameGui = resolveGameUI()

local function findFirst(parent: Instance, names: { string }): Instance?
	for _, n in ipairs(names) do
		local obj = parent:FindFirstChild(n, true)
		if obj then
			return obj
		end
	end
	return nil
end

local statsFrame = findFirst(gameGui, { "StatsPanel", "StatsFrame", "StatsBar" })
local shopFrame = findFirst(gameGui, { "ShopF", "ShopFrame", "ShopPanel" })
local scroll = shopFrame and (findFirst(shopFrame, { "Scroll", "ScrollingFrame" }) :: ScrollingFrame?)
local openShopBtn = findFirst(gameGui, { "OpenShopBtn", "ShopBtn" }) :: GuiButton?

if not statsFrame or not shopFrame or not scroll then
	return
end

local cashBtn = findFirst(statsFrame, { "CashShopBtn", "OpenCashShopBtn", "CashBtn", "AddCashBtn" }) :: GuiButton?
local winsBtn = findFirst(statsFrame, { "WinsShopBtn", "OpenWinsShopBtn", "WinsBtn", "AddWinsBtn" }) :: GuiButton?

local cashAnchor = findFirst(scroll, { "Cash300", "Cash1000", "Cash2500", "Cash5000" }) :: GuiObject?
local winsAnchor = findFirst(scroll, { "Wins10", "Wins25", "Wins50", "Wins100" }) :: GuiObject?

local function openShop()
	if _G.UIWindows and _G.UIWindows.open then
		_G.UIWindows.open("shop")
	else
		if shopFrame and not (shopFrame :: GuiObject).Visible and openShopBtn then
			(openShopBtn :: any):Activate()
		end
	end
end

local function scrollTo(guiObject: GuiObject?)
	if not guiObject or not scroll then
		return
	end

	task.wait(0.18)

	local y = guiObject.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
	scroll.CanvasPosition = Vector2.new(0, math.max(0, math.floor(y - 8)))
end

if cashBtn and cashBtn:IsA("GuiButton") then
	cashBtn.MouseButton1Click:Connect(function()
		openShop()
		scrollTo(cashAnchor)
	end)
end

if winsBtn and winsBtn:IsA("GuiButton") then
	winsBtn.MouseButton1Click:Connect(function()
		openShop()
		scrollTo(winsAnchor)
	end)
end

print("[StatsShopQuickAccess] Ready")
