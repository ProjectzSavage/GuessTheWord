--[[
	ShopService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	Handles real Robux purchases for the Shop. Each item is a DEV PRODUCT.
	The client calls MarketplaceService:PromptProductPurchase(player, productId),
	and this script's ProcessReceipt grants the item (Cash / Wins / gamepass-perk)
	and adds to the player's robux-spent total (for the rewards system).

	SETUP
	1. Create dev products in Creator Hub (Robux -> Developer Products) for each
	   shop item.
	2. Fill DEV_PRODUCTS below: productId (from Creator Hub) -> reward.
	   Available reward types:
	     { type = "cash", amount = 5000 }
	     { type = "wins", amount = 10 }
	     { type = "perk", perk = "DoubleCash" }   -- sets a BoolValue on the player
	3. Enable HTTP/... (dev products need nothing special, just the ProductIds).

	NOTE
	ProcessReceipt MUST return Enum.ProductPurchaseDecision.PurchaseGranted
	exactly once per valid receipt.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-------------------------------------------------------------------------------
-- DEV PRODUCT CATALOG  (fill productId = the id from Creator Hub)
-------------------------------------------------------------------------------
local DEV_PRODUCTS = {
	-- [PRODUCT_ID] = reward
	--[123456789] = { type = "cash", amount = 5000 },
	--[123456790] = { type = "cash", amount = 1000 },
	--[123456791] = { type = "wins", amount = 10 },
	--[123456792] = { type = "perk", perk = "DoubleCash" },
}

-- Track processed receipts (avoid double-granting across resets in this session).
local processedReceipts = {}

local function grantReward(player, reward)
	if reward.type == "cash" then
		local ls = player:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Cash")
		if cash and cash:IsA("IntValue") then
			cash.Value = cash.Value + reward.amount
		end
	elseif reward.type == "wins" then
		local ls = player:FindFirstChild("leaderstats")
		local wins = ls and ls:FindFirstChild("Wins")
		if wins and wins:IsA("IntValue") then
			wins.Value = wins.Value + reward.amount
		end
	elseif reward.type == "perk" then
		-- Store a BoolValue on the player so other systems can read it
		-- (e.g. rewards VIP/group checks, double-cash multipliers).
		local perks = player:FindFirstChild("ShopPerks")
		if not perks then
			perks = Instance.new("Folder")
			perks.Name = "ShopPerks"
			perks.Parent = player
		end
		local existing = perks:FindFirstChild(reward.perk)
		if not existing then
			local bv = Instance.new("BoolValue")
			bv.Name = reward.perk
			bv.Value = true
			bv.Parent = perks
		else
			existing.Value = true
		end
	end
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local reward = DEV_PRODUCTS[receiptInfo.ProductId]
	if not reward then
		warn("[ShopService] No dev product config for id", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Idempotency: don't grant twice for the same receipt.
	if processedReceipts[receiptInfo.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	processedReceipts[receiptInfo.PurchaseId] = true

	grantReward(player, reward)

	-- Add the Robux spent to the rewards system (for robux-spent rewards).
	if _G.RewardsAddRobuxSpent then
		_G.RewardsAddRobuxSpent(player, receiptInfo.PriceInRobux)
	end

	warn("[ShopService] Granted product", receiptInfo.ProductId, "to", player.Name)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print("[ShopService] Ready")
