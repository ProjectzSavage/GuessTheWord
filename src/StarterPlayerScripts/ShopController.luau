--!strict
-- ShopController.luau
-- Client controller for in-game Robux Shop
-- Features:
-- 1. Syncs catalog and owned Gamepasses / Products.
-- 2. Integrates cleanly with UIWindowsController for mutual exclusion, blur, FOV, and StatsPanel sliding.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

-- Safely resolve GameUI / GameGui ScreenGui
local function resolveGameUI(): Instance
	local target = gui:FindFirstChild("GameUI") or gui:FindFirstChild("GameGui")
	if target then
		return target
	end

	local startTime = os.clock()
	while (os.clock() - startTime) < 10 do
		target = gui:FindFirstChild("GameUI") or gui:FindFirstChild("GameGui")
		if target then
			return target
		end
		task.wait(0.1)
	end

	return gui:FindFirstChildWhichIsA("ScreenGui") or gui
end

local gameGui = resolveGameUI()

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

local shop = findObject(gameGui, { "ShopF", "ShopFrame", "ShopPanel" }) :: GuiObject?
if not shop then
	local ok, res = pcall(function()
		return gameGui:WaitForChild("ShopF", 8)
	end)
	if ok and res then
		shop = res :: GuiObject
	end
end

if not shop then
	warn("[ShopController] ShopF not found in GameUI")
	return
end

local scroll = findObject(shop, { "Scroll", "ScrollingFrame", "ContentScroll" }) :: ScrollingFrame?

local Events = RS:WaitForChild("Events", 15)
local ShopSync = Events and (Events:FindFirstChild("ShopSync") or Events:WaitForChild("ShopSync", 10)) :: RemoteEvent?
local ShopRequestRefresh = Events and (Events:FindFirstChild("ShopRequestRefresh") or Events:WaitForChild("ShopRequestRefresh", 10)) :: RemoteEvent?

local FRAME_TO_KEY = {
	VIPPack = "vip_pack",
	DoubleStreak = "double_streak",
	DoubleCash = "double_cash",
	DoubleWins = "double_wins",

	Cash300 = "cash_300",
	Cash1000 = "cash_1000",
	Cash2500 = "cash_2500",
	Cash5000 = "cash_5000",

	Wins10 = "wins_10",
	Wins25 = "wins_25",
	Wins50 = "wins_50",
	Wins100 = "wins_100",
}

type CatalogItem = {
	id: number,
	kind: string,
	price: number?,
}

local catalog: { [string]: CatalogItem } = {}
local owned: { [string]: boolean } = {}
local refs: { [string]: { row: GuiObject, buyBtn: TextButton? } } = {}
local priceCache: { [string]: string } = {}

if scroll then
	for frameName, key in pairs(FRAME_TO_KEY) do
		local row = scroll:FindFirstChild(frameName, true) :: GuiObject?
		if row and row:IsA("GuiObject") then
			refs[key] = {
				row = row,
				buyBtn = findObject(row, { "BuyBtn", "PurchaseBtn", "Buy" }) :: TextButton?,
			}
		end
	end
end

local function getRobuxPrice(kind: string, id: number): string
	local cacheKey = tostring(kind) .. ":" .. tostring(id)
	if priceCache[cacheKey] then
		return priceCache[cacheKey]
	end

	local infoType = (kind == "gamepass") and Enum.InfoType.GamePass or Enum.InfoType.Product
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, infoType)
	end)

	local text = "R$ ?"
	if ok and info then
		local p = info.PriceInRobux or info.Price
		if typeof(p) == "number" then
			text = tostring(p)
		end
	end

	priceCache[cacheKey] = text
	return text
end

local function promptPurchase(key: string)
	local def = catalog[key]
	if not def then
		return
	end

	if def.kind == "gamepass" then
		MarketplaceService:PromptGamePassPurchase(player, def.id)
	elseif def.kind == "devproduct" or def.kind == "product" then
		MarketplaceService:PromptProductPurchase(player, def.id)
	end
end

local function applyRowState(key: string)
	local def = catalog[key]
	local r = refs[key]
	if not def or not r or not r.buyBtn or not r.buyBtn:IsA("TextButton") then
		return
	end

	if def.kind == "gamepass" and owned[key] == true then
		r.buyBtn.Text = "OWN"
		r.buyBtn.Active = false
		r.buyBtn.AutoButtonColor = false
		r.buyBtn.BackgroundColor3 = Color3.fromRGB(50, 190, 70)
		return
	end

	r.buyBtn.Text = getRobuxPrice(def.kind, def.id)
	r.buyBtn.Active = true
	r.buyBtn.AutoButtonColor = true
	r.buyBtn.BackgroundColor3 = Color3.fromRGB(45, 225, 70)
end

for key, r in pairs(refs) do
	if r.buyBtn and r.buyBtn:IsA("TextButton") then
		r.buyBtn.MouseButton1Click:Connect(function()
			promptPurchase(key)
		end)
	end
end

if ShopSync and ShopSync:IsA("RemoteEvent") then
	ShopSync.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		catalog = payload.catalog or {}
		owned = payload.owned or {}

		for key in pairs(refs) do
			applyRowState(key)
		end
	end)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, _passId, wasPurchased)
	if p ~= player or not wasPurchased then
		return
	end
	task.delay(0.3, function()
		if ShopRequestRefresh and ShopRequestRefresh:IsA("RemoteEvent") then
			ShopRequestRefresh:FireServer()
		end
	end)
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _prodId, wasPurchased)
	if userId ~= player.UserId or not wasPurchased then
		return
	end
	task.delay(0.3, function()
		if ShopRequestRefresh and ShopRequestRefresh:IsA("RemoteEvent") then
			ShopRequestRefresh:FireServer()
		end
	end)
end)

-- Initial refresh
if ShopRequestRefresh and ShopRequestRefresh:IsA("RemoteEvent") then
	ShopRequestRefresh:FireServer()
end

print("[ShopController] Ready - Shop catalog & purchases synchronized")
