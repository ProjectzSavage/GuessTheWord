--[[
	ShopController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives the ShopF window: opens/closes it (with UIFX intro/outro), wires the
	CloseBtn, and makes every item's BuyBtn start a REAL Robux purchase
	(MarketplaceService:PromptProductPurchase). Each item frame's NAME maps to a
	dev product id in PRODUCT_IDS below. The actual grant happens server-side
	(ShopService.ProcessReceipt).

	REQUIRED UI (hierarchy):
		ShopF  (Frame, Visible=false)
		├── CloseBtn  (TextButton)
		├── TitleLbl  (TextLabel)
		└── Scroll  (ScrollingFrame)
		    ├── Cash5000   -> item frame with a BuyBtn
		    ├── Cash (Frame, category) -> Cash1000, Cash2500, Cash300
		    ├── Wins (Frame, category) -> Wins10, Wins25, Wins50, Wins100
		    ├── GP   (Frame, category) -> DoubleCash, DoubleStreak, DoubleWins
		    └── VIPPack -> item frame with a BuyBtn

	Every ITEM frame (has a BuyBtn) is found recursively by name and mapped to a
	dev product id via PRODUCT_IDS. Category frames (Cash/Wins/GP) are just
	containers with a UIListLayout and are ignored.

	SETUP
	* Fill PRODUCT_IDS: itemName -> devProductId (from Creator Hub).
	* Clicking Buy fires the Robux purchase prompt for that product.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))

-------------------------------------------------------------------------------
-- DEV PRODUCT MAPPING  (fill in your Creator Hub dev product ids)
-- itemFrameName = productId
-------------------------------------------------------------------------------
local PRODUCT_IDS = {
	Cash5000  = 0,
	Cash1000  = 0,
	Cash2500  = 0,
	Cash300   = 0,
	Wins10    = 0,
	Wins25    = 0,
	Wins50    = 0,
	Wins100   = 0,
	DoubleCash   = 0,
	DoubleStreak = 0,
	DoubleWins   = 0,
	VIPPack   = 0,
}

-------------------------------------------------------------------------------
-- FIND SHOPF
-------------------------------------------------------------------------------
-- Search PlayerGui for the ShopF window (in any ScreenGui).
local ShopF
for _, gui in PlayerGui:GetChildren() do
	local f = gui:FindFirstChild("ShopF", true)
	if f then
		ShopF = f
		break
	end
end

local ShopAPI = {}

-- Wire up if found.
if ShopF then
	local closeBtn = ShopF:FindFirstChild("CloseBtn", true)
	if closeBtn then
		closeBtn.Activated:Connect(function()
			ShopAPI.close()
		end)
	end

	-- Wire every item's BuyBtn to start a purchase.
	-- Item frames have a BuyBtn; category frames (Cash/Wins/GP) have a UIListLayout.
	local function wireBuyButtons()
		for _, item in ShopF:GetDescendants() do
			if item:IsA("GuiButton") and item.Name == "BuyBtn" then
				-- The item frame is the BuyBtn's parent.
				local itemFrame = item.Parent
				local itemName = itemFrame and itemFrame.Name
				local productId = itemName and PRODUCT_IDS[itemName]
				item.Activated:Connect(function()
					if not productId or productId == 0 then
						warn("[Shop] No dev product set for", itemName)
						return
					end
					MarketplaceService:PromptProductPurchase(player, productId)
				end)
			end
		end
	end
	wireBuyButtons()
end

function ShopAPI.open()
	if not ShopF then return end
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

_G.ShopAPI = ShopAPI
