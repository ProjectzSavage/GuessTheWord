--[[
	ReceiptRouter.luau  (ModuleScript)  -- place in ServerStorage.Modules
	----------------------------------------------------------------------------
	PURPOSE
	The single owner of MarketplaceService.ProcessReceipt.

	Roblox only allows ONE ProcessReceipt handler for the whole game, but
	multiple systems sell dev products (ShopService sells shop items,
	TheftService sells the theft tiers, ...). Each system registers its
	product ids here, and the router dispatches every receipt to the matching
	handler. The first registration installs the shared ProcessReceipt.

	USAGE
		local ReceiptRouter = require(ServerStorage.Modules.ReceiptRouter)
		ReceiptRouter.register(PRODUCT_ID, function(receiptInfo, player)
			-- grant the purchase for `player`
		end)
]]

local ReceiptRouter = {}

local handlers = {} -- productId -> function(receiptInfo, player)
local installed = false

local function install()
	if installed then
		return
	end
	installed = true

	local Players = game:GetService("Players")
	local MarketplaceService = game:GetService("MarketplaceService")

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local handler = handlers[receiptInfo.ProductId]
		if not handler then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local ok = pcall(handler, receiptInfo, player)
		if not ok then
			warn("[ReceiptRouter] Handler for product", receiptInfo.ProductId,
				"errored - receipt left unprocessed.")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

-- Register the handler for a dev product id (also installs the shared
-- ProcessReceipt on the first call, whoever registers first).
function ReceiptRouter.register(productId, handler)
	if typeof(productId) ~= "number" or typeof(handler) ~= "function" then
		return
	end
	handlers[productId] = handler
	install()
end

return ReceiptRouter
