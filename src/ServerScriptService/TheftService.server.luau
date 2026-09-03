--[[
	TheftService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService (e.g.
	inside your "Scripts" folder).

	PURPOSE
	The SERVER authority for the cash-theft system. This script puts a real
	"Steal $X" ProximityPrompt on EVERY player's head (X = the victim's live
	cash, shown in the prompt's own text). A prompt is visible to
	everyone in range (Roblox has no per-player prompt visibility), so a
	tiny client LocalScript (StealPromptHide.client.luau) disables the prompt
	locally on YOUR OWN head - the net effect: you see the prompt on every
	OTHER player nearby, and never on yourself. When a thief presses the
	prompt on a victim, this script:
	* In STUDIO with "Enable Studio Access to API Services": the REAL Robux
	  purchase dialog (simulated - no real Robux spent in Studio).
	* In STUDIO without API access: the steal executes FREE instantly so you
	  can still test the flow.
	* In PRODUCTION: prompts a ROBUX dev-product purchase, tiered by how much
	  cash the victim is carrying:

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
local RunService = game:GetService("RunService")

local ReceiptRouter = require(ServerStorage.Modules.ReceiptRouter)
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))

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

-- Shared execution (used by both the receipt path and the Studio shortcut).
-- `spent` = Robux this heist cost (0 in Studio).
local function executeTheft(thief, victim, spent)
	-- Take the victim's CURRENT cash (it may have changed since the prompt).
	local amount = getCash(victim)
	if amount <= 0 then
		notify(thief, "Heist Failed", victim.Name .. " has no cash left to take.", "warn")
		return
	end
	addCash(victim, -amount)
	addCash(thief, amount)

	-- Count it toward the thief's Total Robux spent (rewards system).
	if spent and spent > 0 and _G.RewardsAddRobuxSpent then
		_G.RewardsAddRobuxSpent(thief, spent)
	end

	notify(thief, "Heist Successful!", "You stole $" .. amount .. " from " .. victim.Name .. "!", "success")
	notify(victim, "Robbed!", "Someone stole $" .. amount .. " from you!", "warn")
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

	local spent = receiptSpent(receiptInfo)
	if spent <= 0 then
		warn("[TheftService] Could not determine price for product", receiptInfo.ProductId,
			" — robux-spent total not updated.")
	end
	executeTheft(thief, victim, spent)
end

for _, tier in ipairs(TIER_PRODUCTS) do
	ReceiptRouter.register(tier.id, onTheftReceipt)
end

-------------------------------------------------------------------------------
-- STUDIO PURCHASE CHECK
-- In Studio, "Enable Studio Access to API Services" (Game Settings >
-- Security) makes MarketplaceService work - purchases then simulate for
-- free (no real Robux). Without it, NO purchase dialog can appear, so we
-- fall back to a free instant steal to keep testing possible.
-------------------------------------------------------------------------------
local marketplaceOk = nil
local function marketplaceAvailable()
	if marketplaceOk ~= nil then
		return marketplaceOk
	end
	if not RunService:IsStudio() then
		marketplaceOk = true
		return true
	end
	local ok = pcall(function()
		MarketplaceService:GetProductInfoAsync(TIER_PRODUCTS[1].id, Enum.InfoType.Product)
	end)
	marketplaceOk = ok
	if not ok then
		warn("[TheftService] Studio API access is OFF - steals execute FREE in this "
			.. "session. Enable Game Settings > Security > Enable Studio Access to API "
			.. "Services to test the real Robux purchase dialog.")
	end
	return ok
end

-------------------------------------------------------------------------------
-- THEFT REQUEST (legacy remote - kept as a fallback path; the normal way
-- to start a steal is now pressing the head prompt above)
-------------------------------------------------------------------------------
local function attemptTheft(thief, victim)
	local cash = getCash(victim)
	if cash <= 0 then
		notify(thief, "Steal", victim.Name .. " has no cash to steal!", "warn")
		return
	end
	-- Free steal ONLY when Studio can't show the purchase dialog (API
	-- access off). With API access on - or in a live game - the real
	-- Robux purchase flow below runs.
	if RunService:IsStudio() and not marketplaceAvailable() then
		executeTheft(thief, victim, 0)
		return
	end
	local tier = tierFor(cash)
	pendingTheft[thief.UserId] = { victim = victim, at = os.clock() }
	notify(thief, "Steal", "Confirm the purchase to steal $" .. cash .. " from " .. victim.Name .. "!", "info")
	MarketplaceService:PromptProductPurchase(thief, tier.id)
end

-------------------------------------------------------------------------------
-- STEAL PROMPTS (one per player, on their HEAD)
-- Roblox ProximityPrompts have no per-player visibility: a prompt on the
-- victim's head would also show for the victim. The fix (same trick the
-- DevForum accepts) is: put the prompt on EVERY player's head, and let each
-- player's own client (StealPromptHide.client.luau) disable it locally on
-- their own head. Result: the prompt appears above every OTHER player,
-- never above you. Triggering your own prompt is impossible (it's disabled
-- on your client) and the server rejects self-theft below anyway.
-------------------------------------------------------------------------------
local missingProps = {} -- prompt prop names this engine rejected (warned once)
local promptAnnounced = false

-- ProximityPrompt property names have changed across engine versions
-- (some builds reject KeyCode / TriggerDistance / Adornee), so every
-- optional property is set through pcall: classic name first, newer name
-- as fallback, engine default if neither exists. Nothing here is fatal -
-- the prompt still shows and still triggers either way.
local function setProp(obj, name, value, fallbackName)
	local ok = pcall(function()
		obj[name] = value
	end)
	if ok then
		return
	end
	if fallbackName then
		ok = pcall(function()
			obj[fallbackName] = value
		end)
		if ok then
			return
		end
	end
	missingProps[name] = true
end

local function setupStealPrompt(character, player)
	task.spawn(function()
		local head = character:WaitForChild("Head", 10)
		if not head or not head:IsA("BasePart") then
			return
		end
		local old = head:FindFirstChild("StealPrompt")
		if old then
			old:Destroy()
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		setProp(prompt, "ActionText", "Steal")
		setProp(prompt, "ObjectText", "Steal")
		-- Its OWN key (R): the chair buy prompts use E, and with OnePerButton
		-- a closer E-prompt would steal the key and the steal prompt would
		-- never activate. AlwaysShow = the pill shows as long as you're in
		-- range, no matter what other prompts are around.
		setProp(prompt, "KeyCode", Enum.KeyCode.R, "KeyboardKeyCode")
		local okExcl, exclusivity = pcall(function()
			return Enum.ProximityPromptExclusivity.AlwaysShow
		end)
		if okExcl and exclusivity then
			setProp(prompt, "Exclusivity", exclusivity)
		end
		setProp(prompt, "HoldDuration", 0)
		setProp(prompt, "TriggerDistance", 10, "MaxActivationDistance")
		setProp(prompt, "Adornee", head, "AdorneePart")
		-- CRITICAL: new engine builds default RequiresLineOfSight to true,
		-- and the visibility raycast is blocked by YOUR OWN character when
		-- you stand next to the victim - which made the prompt on other
		-- players invisible (yours stayed visible because a prompt's
		-- raycast excludes its own parent). Stealing needs no line of sight.
		setProp(prompt, "RequiresLineOfSight", false)
		prompt.Parent = head

		-- The prompt's own text shows the victim's CURRENT cash
		-- ("Steal $1,500") and live-updates whenever it changes.
		task.spawn(function()
			local ls = player:WaitForChild("leaderstats", 10)
			local cashVal = ls and ls:WaitForChild("Cash", 10)
			if not cashVal then
				return
			end
			local function refresh()
				local t = "Steal $" .. NumberFormat.commas(getCash(player))
				pcall(function()
					prompt.ObjectText = t
					prompt.ActionText = t
				end)
			end
			refresh()
			local conn = cashVal.Changed:Connect(refresh)
			character.Destroying:Connect(function()
				conn:Disconnect()
			end)
		end)

		prompt.Triggered:Connect(function(thief)
			if not thief or thief == player then
				return -- you can't steal from yourself
			end
			if not player.Parent then
				return
			end
			attemptTheft(thief, player)
		end)

		if not promptAnnounced then
			promptAnnounced = true
			local rejected = {}
			for name in pairs(missingProps) do
				table.insert(rejected, name)
			end
			if #rejected > 0 then
				warn("[TheftService] This engine's prompt has no: " .. table.concat(rejected, ", ")
					.. " - normal on the 2026 prompt update (the prompt anchors to its parent part "
					.. "instead). Everything still works, the pill shows which key to press.")
			end
			warn("[TheftService] Steal prompts active - a 'Steal $X' pill shows above every "
				.. "OTHER player within ~10 studs (press the key the pill shows, or click it; "
				.. "hidden on your own head by StealPromptHide.client.luau - if you see it on "
				.. "yourself, that LocalScript is missing from StarterPlayerScripts).")
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupStealPrompt(character, player)
	end)
	if player.Character then
		setupStealPrompt(player.Character, player)
	end
end)

StealRequest.OnServerEvent:Connect(function(thief, victimUserId)
	if typeof(victimUserId) ~= "number" then
		return
	end
	local victim = Players:GetPlayerByUserId(victimUserId)
	if not victim or victim == thief then
		return -- you can't steal from yourself
	end
	-- Anti-cheat sanity: the thief must actually be near the victim
	-- (the prompt only triggers within 10 studs, but never trust the
	-- client).
	local tHrp = thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
	local vHrp = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not tHrp or not vHrp then
		return
	end
	if (tHrp.Position - vHrp.Position).Magnitude > 25 then
		return
	end
	attemptTheft(thief, victim)
end)
