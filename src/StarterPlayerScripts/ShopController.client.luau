--[[
	ShopController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives the ShopF window: opens/closes it (with UIFX intro/outro), wires the
	CloseBtn, and makes every item's BuyBtn start a REAL Robux purchase
	(MarketplaceService:PromptProductPurchase or PromptGamePassPurchase).
	Each item frame's NAME maps to a dev product or gamepass id in PRODUCT_IDS.

	MUTUAL EXCLUSIVITY:
	When opening Shop, it automatically closes Rewards and Inventory so frames
	never overlap.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))
local ChairsConfig = require(ReplicatedStorage:WaitForChild("ChairsConfig"))

local PRODUCT_IDS = {
	-- Dev Products
	Cash5000  = 0,
	Cash1000  = 0,
	Cash2500  = 0,
	Cash300   = 0,
	Wins10    = 0,
	Wins25    = 0,
	Wins50    = 0,
	Wins100   = 0,

	-- Gamepasses
	DoubleCash   = 0,
	DoubleStreak = 0,
	DoubleWins   = 0,
	VIPPack      = 0,

	-- Robux Exclusive Chairs (Gamepasses)
	HackerChair  = 0,
	SpacialMist  = 0,
	PinkVortex   = 0,
}

local GAMEPASS_NAMES = {
	DoubleCash = true,
	DoubleStreak = true,
	DoubleWins = true,
	VIPPack = true,
	HackerChair = true,
	SpacialMist = true,
	PinkVortex = true,
}

if ChairsConfig.GamepassChairs then
	for k, v in pairs(ChairsConfig.GamepassChairs) do
		if v and v > 0 then
			PRODUCT_IDS[k] = v
		end
	end
end

local gameGui = PlayerGui:WaitForChild("GameUI", 10) or PlayerGui:FindFirstChildWhichIsA("ScreenGui")
local ShopF = gameGui and (gameGui:FindFirstChild("ShopF", true) or gameGui:WaitForChild("ShopF", 8))

local ShopAPI = {}

local closeBtn = ShopF and (ShopF:FindFirstChild("CloseBtn", true) :: GuiButton?)
if closeBtn then
	closeBtn.Activated:Connect(function()
		ShopAPI.close()
	end)
end

local function handlePurchase(itemName: string, productId: number)
	if not productId or productId == 0 then
		warn("[Shop] No ID configured for:", itemName)
		if _G.Notify then
			_G.Notify({
				title = "Shop",
				message = "Configure the Gamepass / Product ID in ShopController!",
				kind = "warn",
			})
		end
		return
	end

	local isGamepass = GAMEPASS_NAMES[itemName] == true
	if isGamepass then
		MarketplaceService:PromptGamePassPurchase(player, productId)
	else
		MarketplaceService:PromptProductPurchase(player, productId)
	end
end

local function wireBuyButtons()
	if not ShopF then return end
	for _, item in ipairs(ShopF:GetDescendants()) do
		if item:IsA("GuiButton") and (item.Name == "BuyBtn" or item.Name == "PurchaseBtn") then
			local itemFrame = item.Parent
			local itemName = itemFrame and itemFrame.Name
			local productId = itemName and PRODUCT_IDS[itemName]

			if not item:GetAttribute("BuyBound") then
				item.Activated:Connect(function()
					handlePurchase(itemName, productId)
				end)
				item:SetAttribute("BuyBound", true)
			end
		end
	end
end
wireBuyButtons()

if ShopF then
	ShopF.DescendantAdded:Connect(function(item)
		if item:IsA("GuiButton") and (item.Name == "BuyBtn" or item.Name == "PurchaseBtn") then
			local itemFrame = item.Parent
			local itemName = itemFrame and itemFrame.Name
			local productId = itemName and PRODUCT_IDS[itemName]

			if not item:GetAttribute("BuyBound") then
				item.Activated:Connect(function()
					handlePurchase(itemName, productId)
				end)
				item:SetAttribute("BuyBound", true)
			end
		end
	end)
end

function ShopAPI.open()
	if not ShopF then return end
	-- Automatically close Rewards and Inventory if open
	if _G.RewardsAPI and _G.RewardsAPI.isOpen and _G.RewardsAPI.isOpen() and _G.RewardsAPI.close then
		_G.RewardsAPI.close()
	end
	if _G.InventoryAPI and _G.InventoryAPI.isOpen and _G.InventoryAPI.isOpen() and _G.InventoryAPI.close then
		_G.InventoryAPI.close()
	end

	ShopF.Visible = true
	UIFX.popIn(ShopF)
end

function ShopAPI.close()
	if not ShopF then return end
	UIFX.popOut(ShopF)
end

function ShopAPI.isAvailable()
	return ShopF ~= nil
end

function ShopAPI.isOpen()
	return ShopF ~= nil and ShopF.Visible
end

_G.ShopAPI = ShopAPI

