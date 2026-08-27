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
     { type = "powerup", use = "Word", amount = 3 }
       -- use = "Word"   -> +amount RevealWordUses
       -- use = "Letter" -> +amount RevealLetterUses
	3. Enable HTTP/... (dev products need nothing special, just the ProductIds).

	NOTE
	ProcessReceipt MUST return Enum.ProductPurchaseDecision.PurchaseGranted
	exactly once per valid receipt.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- PurchaseSuccess tells the client a Robux purchase just completed (the
-- client plays the special sound + confetti + a notification). Created here
-- if missing so this script never blocks on an old Events folder.
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end
local PurchaseSuccess = eventsFolder:FindFirstChild("PurchaseSuccess")
if not PurchaseSuccess then
	PurchaseSuccess = Instance.new("RemoteEvent")
	PurchaseSuccess.Name = "PurchaseSuccess"
	PurchaseSuccess.Parent = eventsFolder
end

-------------------------------------------------------------------------------
-- DEV PRODUCT CATALOG  (fill productId = the id from Creator Hub)
-------------------------------------------------------------------------------
local DEV_PRODUCTS = {
	-- [PRODUCT_ID] = reward

	-- Cash
	[3709926017] = { type = "cash", amount = 5000 }, -- Cash5000
	[3709926097] = { type = "cash", amount = 2500 }, -- Cash2500
	[3709926131] = { type = "cash", amount = 1000 }, -- Cash1000
	[3709926166] = { type = "cash", amount = 300 },  -- Cash300

	-- Wins
	[3709926266] = { type = "wins", amount = 100 }, -- Wins100
	[3709926317] = { type = "wins", amount = 50 },  -- Wins50
	[3709926374] = { type = "wins", amount = 25 },  -- Wins25
	[3709926411] = { type = "wins", amount = 10 },  -- Wins10

	-- Reveal Words / Reveal Letters (shop frames RevealWords / RevealLetters,
	-- items RevealW1/RevealW3/RevealW5 and RevealL1/RevealL3/RevealL5).
	-- use = "Word" grants RevealWordUses, use = "Letter" grants RevealLetterUses.
	[3709926691] = { type = "powerup", use = "Word",   amount = 1 }, -- RevealW1
	[3709926626] = { type = "powerup", use = "Word",   amount = 3 }, -- RevealW3
	[3709926546] = { type = "powerup", use = "Word",   amount = 5 }, -- RevealW5
	[3709926777] = { type = "powerup", use = "Letter", amount = 1 }, -- RevealL1
	[3709926836] = { type = "powerup", use = "Letter", amount = 3 }, -- RevealL3
	[3709927106] = { type = "powerup", use = "Letter", amount = 5 }, -- RevealL5

	-- NOTE: VIP / 2x Streak / 2x Cash / 2x Wins / the exclusive chairs are
	-- GAMEPASSES (see ShopController.PRODUCT_IDS, ChairsConfig.GamepassChairs
	-- and OffersController) - they never hit ProcessReceipt, so no entry here.
}

-- Track processed receipts (avoid double-granting across resets in this session).
local processedReceipts = {}

-- Gamepass purchases (VIP / 2x Streak / 2x Cash / 2x Wins / exclusive chairs /
-- starter pack) never hit ProcessReceipt, so count them toward the total
-- robux-spent tracker HERE - otherwise the "Total Robux spent" in the Rewards
-- UI only moved on dev-product purchases.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased or not player then
		return
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(gamePassId, Enum.InfoType.GamePass)
	end)
	local passName = (ok and type(info) == "table" and info.Name) or ""
	if ok and type(info) == "table" and info.Price then
		if _G.RewardsAddRobuxSpent then
			_G.RewardsAddRobuxSpent(player, math.floor(info.Price / 100))
		end
	end
	-- Client celebration: special purchase sound + confetti + notification.
	PurchaseSuccess:FireClient(player, passName)
end)

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
	elseif reward.type == "powerup" then
		-- Grant powerup uses (Reveal Word / Reveal Letter). The values live in
		-- the hidden "Stats" folder (created by GameManager on join); make
		-- sure they exist so a purchase can never be lost.
		local stats = player:FindFirstChild("Stats")
		if not stats then
			stats = Instance.new("Folder")
			stats.Name = "Stats"
			stats.Parent = player
		end
		local useName = (reward.use == "Letter" and "RevealLetterUses") or "RevealWordUses"
		local val = stats:FindFirstChild(useName)
		if not val then
			val = Instance.new("IntValue")
			val.Name = useName
			val.Value = 0
			val.Parent = stats
		end
		val.Value = val.Value + (reward.amount or 1)
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

-- Human-readable summary of what the purchase granted (shown in the client's
-- "Purchase Successful!" notification).
local function rewardLabel(reward)
	if reward.type == "cash" then
		return "+$" .. tostring(reward.amount) .. " cash"
	elseif reward.type == "wins" then
		return "+" .. tostring(reward.amount) .. " Wins"
	elseif reward.type == "powerup" then
		local what = (reward.use == "Letter") and "Reveal Letter" or "Reveal Word"
		return "+" .. tostring(reward.amount or 1) .. " " .. what .. " use(s)"
	elseif reward.type == "perk" then
		return tostring(reward.perk)
	end
	return ""
end

-- Receipts are routed through the shared ReceiptRouter module so other
-- systems (TheftService's theft tiers) can register their own dev products
-- on the same single ProcessReceipt without overwriting each other.
local ReceiptRouter = require(ServerStorage.Modules.ReceiptRouter)

local function onShopReceipt(receiptInfo, player)
	local reward = DEV_PRODUCTS[receiptInfo.ProductId]
	if not reward then
		warn("[ShopService] No dev product config for id", receiptInfo.ProductId)
		return
	end

	-- Idempotency: don't grant twice for the same receipt.
	if processedReceipts[receiptInfo.PurchaseId] then
		return
	end
	processedReceipts[receiptInfo.PurchaseId] = true

	grantReward(player, reward)

	-- Add the Robux spent to the rewards system (for robux-spent rewards).
	if _G.RewardsAddRobuxSpent then
		_G.RewardsAddRobuxSpent(player, receiptInfo.PriceInRobux)
	end

	-- Client celebration: special purchase sound + confetti + notification.
	PurchaseSuccess:FireClient(player, rewardLabel(reward))

	warn("[ShopService] Granted product", receiptInfo.ProductId, "to", player.Name)
end

for productId in pairs(DEV_PRODUCTS) do
	ReceiptRouter.register(productId, onShopReceipt)
end


