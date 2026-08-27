--[[
	TheftService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService (e.g.
	inside your "Scripts" folder).

	PURPOSE
	Every player gets a "Steal" ProximityPrompt on their character that shows
	how much CASH they're carrying. When ANOTHER player uses the prompt, a
	ROBUX dev-product purchase is prompted - the price tier scales with how
	much cash the victim carries. On a successful purchase the victim's cash
	is moved to the thief (victim ends at $0) and BOTH get a notification.

	TIERS (victim's cash when the prompt is used)
		under $500   -> 3710136562
		under $1,000 -> 3710136669
		under $3,000 -> 3710136888
		under $5,000 -> 3710136918
		$5,000 and up -> 3710136971
	The 5 dev products must exist in Creator Hub with exactly those ids.

	The products are processed through the shared ReceiptRouter
	(ServerStorage.Modules) - the same single ProcessReceipt ShopService
	uses, so the two systems never overwrite each other.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ReceiptRouter = require(ServerStorage.Modules.ReceiptRouter)

local Events = ReplicatedStorage:WaitForChild("Events")
local NotifyPlayer = Events:WaitForChild("NotifyPlayer")

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

local PROMPT_NAME = "StealPrompt"
local PROMPT_HOLD = 0.5  -- seconds the thief must hold the key
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
	if _G.RewardsAddRobuxSpent then
		_G.RewardsAddRobuxSpent(thief, receiptInfo.PriceInRobux)
	end

	notify(thief, "Heist Successful!", "You stole $" .. amount .. " from " .. victim.Name .. "!", "success")
	notify(victim, "Robbed!", "Someone stole $" .. amount .. " from you!", "warn")
end

for _, tier in ipairs(TIER_PRODUCTS) do
	ReceiptRouter.register(tier.id, onTheftReceipt)
end

-------------------------------------------------------------------------------
-- PROMPT (on every player's character)
-------------------------------------------------------------------------------
local function updatePromptText(prompt, victim)
	prompt.ObjectText = "Steal $" .. getCash(victim) .. " from " .. victim.Name
	prompt.ActionText = "Steal"
end

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

local function attachPrompt(player)
	local function onCharacter(character)
		task.spawn(function()
			local hrp = character:WaitForChild("HumanoidRootPart", 10)
			if not hrp or not player.Parent then
				return
			end
			local prompt = hrp:FindFirstChild(PROMPT_NAME) or Instance.new("ProximityPrompt")
			prompt.Name = PROMPT_NAME
			prompt.ObjectText = "Steal"
			prompt.ActionText = "Steal"
			prompt.HoldDuration = PROMPT_HOLD
			prompt.MaxActivationDistance = 15
			prompt.RequiresLineOfSight = false
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerPlayer
			prompt.KeyboardKeyCode = Enum.KeyCode.F -- E is used for typing letters
			prompt.Parent = hrp

			updatePromptText(prompt, player)

			prompt.Triggered:Connect(function(thief)
				if thief == player then
					return -- you can't steal from yourself
				end
				attemptTheft(thief, player)
			end)

			-- Keep the shown amount live while the prompt exists.
			local ls = player:FindFirstChild("leaderstats")
			local cash = ls and ls:FindFirstChild("Cash")
			if cash then
				cash.Changed:Connect(function()
					if prompt.Parent then
						updatePromptText(prompt, player)
					end
				end)
			end
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(attachPrompt)
for _, player in ipairs(Players:GetPlayers()) do
	attachPrompt(player)
end
