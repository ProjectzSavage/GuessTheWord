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
local SFX = require(ReplicatedStorage:WaitForChild("SFX"))

local PRODUCT_IDS = {
	-- Dev Products
	Cash5000  = 3709926017,
	Cash1000  = 3709926131,
	Cash2500  = 3709926097,
	Cash300   = 3709926166,
	Wins10    = 3709926411,
	Wins25    = 3709926374,
	Wins50    = 3709926317,
	Wins100   = 3709926266,

	-- Reveal Words (dev products - grant RevealWord uses)
	RevealW1  = 3709926691, -- +1 Reveal Word
	RevealW3  = 3709926626, -- +3 Reveal Words
	RevealW5  = 3709926546, -- +5 Reveal Words

	-- Reveal Letters (dev products - grant RevealLetter uses)
	RevealL1  = 3709926777, -- +1 Reveal Letter
	RevealL3  = 3709926836, -- +3 Reveal Letters
	RevealL5  = 3709927106, -- +5 Reveal Letters

	-- Gamepasses
	DoubleCash   = 1958940384,
	DoubleStreak = 1958292387,
	DoubleWins   = 1960056393,
	VIPPack      = 1960374374,

	-- Robux Exclusive Chairs (Gamepasses) - auto-filled from
	-- ChairsConfig.GamepassChairs below (kept at 0 here).
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
	SFX.play("robuxClick") -- every shop buy opens a Robux purchase prompt
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

-------------------------------------------------------------------------------
-- AUTO PRICES
-- Every item frame's PriceLbl is filled from the REAL price in Creator Hub
-- (dev product or gamepass, per item name). Nothing is hardcoded - if a fetch
-- fails the label keeps whatever text you set in Studio.
-------------------------------------------------------------------------------
local function fetchPriceText(productId, isGamepass)
	local ok, info = pcall(function()
		if isGamepass then
			return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.GamePass)
		end
		return MarketplaceService:GetProductInfoAsync(productId)
	end)
	if ok and type(info) == "table" and info.Price then
		return "R$" .. tostring(math.floor(info.Price / 100))
	end
	return nil
end

local function applyItemPrices()
	if not ShopF then return end
	for _, frame in ShopF:GetDescendants() do
		if frame:IsA("Frame") then
			local hasBuy = frame:FindFirstChild("BuyBtn") ~= nil or frame:FindFirstChild("PurchaseBtn") ~= nil
			local priceLbl = frame:FindFirstChild("PriceLbl")
			if hasBuy and priceLbl and priceLbl:IsA("TextLabel") then
				local productId = PRODUCT_IDS[frame.Name]
				if productId and productId > 0 then
					local isGamepass = GAMEPASS_NAMES[frame.Name] == true
					task.spawn(function()
						local text = fetchPriceText(productId, isGamepass)
						if text and frame.Parent then
							priceLbl.Text = text
						end
					end)
				end
			end
		end
	end
end
applyItemPrices()

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
	if ShopF.Visible then return end -- already open (idempotent — no double FX)
	-- Automatically close Rewards and Inventory if open
	if _G.RewardsAPI and _G.RewardsAPI.isOpen and _G.RewardsAPI.isOpen() and _G.RewardsAPI.close then
		_G.RewardsAPI.close()
	end
	if _G.InventoryAPI and _G.InventoryAPI.isOpen and _G.InventoryAPI.isOpen() and _G.InventoryAPI.close then
		_G.InventoryAPI.close()
	end

	SFX.play("shopOpen") -- the shop's own open sound (separate from uiPop)
	UIFX.openWindow(ShopF)
end

function ShopAPI.close()
	-- Guard: a stray close on an already-closed window is a no-op (the old
	-- code fired popOut unconditionally, which skewed the FX state).
	if not ShopF or not ShopF.Visible then return end
	UIFX.closeWindow(ShopF)
end

function ShopAPI.isAvailable()
	return ShopF ~= nil
end

function ShopAPI.isOpen()
	return ShopF ~= nil and ShopF.Visible
end

_G.ShopAPI = ShopAPI

