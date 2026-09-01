--[[
	TheftService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService (e.g.
	inside your "Scripts" folder).

	PURPOSE
	The SERVER authority for the cash-theft system. This script places a real
	ProximityPrompt named "StealPrompt" on EVERY player's head (visible to all
	players within 20 studs - the victim sees it too, but pressing it just
	gets a friendly "can't steal yourself" toast). The ActionText shows the
	victim's LIVE cash ("Steal $1,250"). When a thief activates it, this
	script prompts a ROBUX dev-product purchase, tiered by how much cash the
	victim is carrying:

		under $500   -> 3710136562
		under $1,000 -> 3710136669
		under $3,000 -> 3710136888
		under $5,000 -> 3710136918
		$5,000 and up -> 3710136971

	On a successful purchase the victim's cash is moved to the thief (victim
	ends at $0), BOTH get a notification, and the Robux counts toward the
	thief's Total Robux spent. The products are processed through the shared
	ReceiptRouter (ServerStorage.Modules) - the same single ProcessReceipt
	ShopService uses, so the two systems never overwrite each other.

	The 5 dev products must exist in Creator Hub with exactly those ids.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ReceiptRouter = require(ServerStorage.Modules.ReceiptRouter)

local Events = ReplicatedStorage:WaitForChild("Events")
local NotifyPlayer = Events:WaitForChild("NotifyPlayer")
local StealRequest = Events:FindFirstChild("StealRequest")
if not StealRequest then
	StealRequest = Instance.new("RemoteEvent")
	StealRequest.Name = "StealRequest"
	StealRequest.Parent = Events
end

-------------------------------------------------------------------------------
-- TIER CONFIG
-- Checked in order: the first tier whose `max` is greater than the victim's
-- cash wins ("under $500" = cash < 500, and so on).
-------------------------------------------------------------------------------
local TIER_PRODUCTS = {
	{ max = 500,     id = 3710136562 },
	{ max = 1000,    id = 3710136669 },
	{ max = 3000,    id = 3710136888 },
	{ max = 5000,    id = 3710136918 },
	{ max = math.huge, id = 3710136971 },
}

local PENDING_TIMEOUT = 600 -- a pending theft older than this is stale

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------
local function getCash(player)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	return (cash and cash.Value) or 0
end

local function addCash(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") and amount ~= 0 then
		cash.Value = cash.Value + amount
	end
end

local function notify(player, title, message, kind)
	NotifyPlayer:FireClient(player, {
		title = title or "Steal",
		message = message,
		kind = kind or "info",
		duration = 4,
	})
end

local function tierFor(cash)
	for _, tier in ipairs(TIER_PRODUCTS) do
		if cash < tier.max then
			return tier
		end
	end
	return TIER_PRODUCTS[#TIER_PRODUCTS]
end

-------------------------------------------------------------------------------
-- PENDING THEFTS (thief bought the product -> grant it on ProcessReceipt)
-------------------------------------------------------------------------------
local pendingTheft = {} -- thiefUserId -> { victim = player, at = number }

-- How much Robux this receipt cost (receipt price fields vary by engine
-- version — fall back to a cached product lookup so the total never drops).
local priceCache = {}
local function receiptSpent(receiptInfo)
	local spent = tonumber(receiptInfo.PriceInRobux)
		or tonumber(receiptInfo.CurrencySpent)
		or tonumber(receiptInfo.Price)
	if not spent or spent <= 0 then
		if not priceCache[receiptInfo.ProductId] then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfoAsync(receiptInfo.ProductId, Enum.InfoType.Product)
			end)
			priceCache[receiptInfo.ProductId] = (ok and type(info) == "table")
				and tonumber(info.PriceInRobux) or 0
		end
		spent = priceCache[receiptInfo.ProductId]
	end
	return spent or 0
end

local function onTheftReceipt(receiptInfo, thief)
	local record = pendingTheft[thief.UserId]
	if not record then
		return
	end
	if (os.clock() - record.at) > PENDING_TIMEOUT then
		pendingTheft[thief.UserId] = nil
		return
	end
	local victim = record.victim
	pendingTheft[thief.UserId] = nil
	if not victim or not victim.Parent then
		return
	end

	-- Take the victim's CURRENT cash (it may have changed since the prompt).
	local amount = getCash(victim)
	if amount <= 0 then
		notify(thief, "Heist Failed", victim.Name .. " has no cash left to take.", "warn")
		return
	end
	addCash(victim, -amount)
	addCash(thief, amount)

	-- Count it toward the thief's Total Robux spent (rewards system).
	local spent = receiptSpent(receiptInfo)
	if spent > 0 then
		if _G.RewardsAddRobuxSpent then
			_G.RewardsAddRobuxSpent(thief, spent)
		end
	else
		warn("[TheftService] Could not determine price for product", receiptInfo.ProductId,
			" — robux-spent total not updated.")
	end

	notify(thief, "Heist Successful!", "You stole $" .. amount .. " from " .. victim.Name .. "!", "success")
	notify(victim, "Robbed!", "Someone stole $" .. amount .. " from you!", "warn")
end

for _, tier in ipairs(TIER_PRODUCTS) do
	ReceiptRouter.register(tier.id, onTheftReceipt)
end

-------------------------------------------------------------------------------
-- LEGACY REMOTE (kept for compatibility - the steal prompt is now the
-- server-side ProximityPrompt below; nothing fires this anymore).
-------------------------------------------------------------------------------
local function attemptTheft(thief, victim)
	local cash = getCash(victim)
	if cash <= 0 then
		notify(thief, "Steal", victim.Name .. " has no cash to steal!", "warn")
		return
	end
	local tier = tierFor(cash)
	pendingTheft[thief.UserId] = { victim = victim, at = os.clock() }
	notify(thief, "Steal", "Confirm the purchase to steal $" .. cash .. " from " .. victim.Name .. "!", "info")
	MarketplaceService:PromptProductPurchase(thief, tier.id)
end

StealRequest.OnServerEvent:Connect(function(thief, victimUserId)
	if typeof(victimUserId) ~= "number" then
		return
	end
	local victim = Players:GetPlayerByUserId(victimUserId)
	if not victim or victim == thief then
		return -- you can't steal from yourself
	end
	attemptTheft(thief, victim)
end)

-------------------------------------------------------------------------------
-- STEAL PROMPTS (server-side ProximityPrompt on every player's head)
-- A real prompt (works even if a client script is missing/stale). It shows
-- for everyone nearby - including the victim (pressing it just gets a
-- friendly "you can't steal from yourself" toast). The ActionText always
-- shows the victim's LIVE cash.
-------------------------------------------------------------------------------
local PROMPT_DISTANCE = 20

local function updateStealPrompt(victim)
	local character = victim.Character
	local head = character and character:FindFirstChild("Head")
	local prompt = head and head:FindFirstChild("StealPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ActionText = "Steal $" .. getCash(victim)
	end
end

local function setupStealPrompt(victim)
	local character = victim.Character
	if not character then
		return
	end
	local head = character:WaitForChild("Head", 5)
	if not head then
		return
	end
	local prompt = head:FindFirstChild("StealPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Steal $" .. getCash(victim)
		prompt.ObjectText = "Steal Cash"
		prompt.MaxActivationDistance = PROMPT_DISTANCE
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = head
		prompt.PromptTriggered:Connect(function(thief)
			if thief == victim then
				notify(thief, "Steal", "Nice try - you can't steal from yourself!", "warn")
				return
			end
			attemptTheft(thief, victim)
		end)
	end
	-- Keep the ActionText live with the victim's cash.
	local function watchCash()
		local ls = victim:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Cash")
		if cash then
			cash.Changed:Connect(function()
				updateStealPrompt(victim)
			end)
		else
			task.delay(1, watchCash)
		end
	end
	watchCash()
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(setupStealPrompt, player)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupStealPrompt, player)
end
