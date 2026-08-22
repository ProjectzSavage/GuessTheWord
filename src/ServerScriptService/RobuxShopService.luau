--!strict
-- RobuxShopService.luau
-- Server script managing catalog synchronization, Gamepass checks, and Developer Product purchases.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local Events = RS:FindFirstChild("Events")
if not Events then
	Events = Instance.new("Folder")
	Events.Name = "Events"
	Events.Parent = RS
end

local function ensureEvent(name: string): RemoteEvent
	local e = (Events :: Folder):FindFirstChild(name)
	if e and e:IsA("RemoteEvent") then
		return e
	end
	local newEvent = Instance.new("RemoteEvent")
	newEvent.Name = name
	newEvent.Parent = Events
	return newEvent
end

local ShopSync = ensureEvent("ShopSync")
local ShopRequestRefresh = ensureEvent("ShopRequestRefresh")
local AddRobuxSpent = ensureEvent("AddRobuxSpent")
local NotifyPlayer = ensureEvent("NotifyPlayer")

local PurchaseHistoryStore = DataStoreService:GetDataStore("PurchaseHistory_V1")

local CATALOG = {
	-- Gamepasses
	vip_pack       = { id = 1839628382, kind = "gamepass" },
	double_streak  = { id = 1840844336, kind = "gamepass" },
	double_cash    = { id = 1841496309, kind = "gamepass" },
	double_wins    = { id = 1841592323, kind = "gamepass" },

	-- Dev Products: Cash
	cash_300       = { id = 3537248109, kind = "devproduct", cash = 300, robux = 29 },
	cash_1000      = { id = 3537248110, kind = "devproduct", cash = 1000, robux = 79 },
	cash_2500      = { id = 3537248111, kind = "devproduct", cash = 2500, robux = 149 },
	cash_5000      = { id = 3537248112, kind = "devproduct", cash = 5000, robux = 249 },

	-- Dev Products: Wins
	wins_10        = { id = 3537248113, kind = "devproduct", wins = 10, robux = 49 },
	wins_25        = { id = 3537248114, kind = "devproduct", wins = 25, robux = 99 },
	wins_50        = { id = 3537248115, kind = "devproduct", wins = 50, robux = 179 },
	wins_100       = { id = 3537248116, kind = "devproduct", wins = 100, robux = 299 },
}

local function ensurePlayerPerks(plr: Player): Folder
	local perks = plr:FindFirstChild("ShopPerks") :: Folder?
	if not perks then
		perks = Instance.new("Folder")
		perks.Name = "ShopPerks"
		perks.Parent = plr
	end
	return perks
end

local function applyGamepassPerk(plr: Player, passKey: string)
	local perks = ensurePlayerPerks(plr)
	local perkVal = perks:FindFirstChild(passKey) :: BoolValue?
	if not perkVal then
		perkVal = Instance.new("BoolValue")
		perkVal.Name = passKey
		perkVal.Value = true
		perkVal.Parent = perks
	else
		perkVal.Value = true
	end
end

local function getOwnedGamepasses(plr: Player): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for key, item in pairs(CATALOG) do
		if item.kind == "gamepass" then
			local ok, hasPass = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, item.id)
			end)
			if ok and hasPass then
				owned[key] = true
				applyGamepassPerk(plr, key)
			end
		end
	end
	return owned
end

local function syncShop(plr: Player)
	local owned = getOwnedGamepasses(plr)
	ShopSync:FireClient(plr, {
		catalog = CATALOG,
		owned = owned,
	})
end

ShopRequestRefresh.OnServerEvent:Connect(function(plr: Player)
	syncShop(plr)
end)

Players.PlayerAdded:Connect(function(plr: Player)
	task.delay(1.5, function()
		if plr.Parent then
			syncShop(plr)
		end
	end)
end)

-- Process Developer Product Purchases
MarketplaceService.ProcessReceipt = function(receiptInfo: any): Enum.ProductPurchaseDecision
	local plr = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not plr then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = "rcpt_" .. tostring(receiptInfo.PurchaseId)
	local alreadyHandled = false
	pcall(function()
		alreadyHandled = PurchaseHistoryStore:GetAsync(key) == true
	end)

	if alreadyHandled then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local prodDef: any = nil
	for _, item in pairs(CATALOG) do
		if item.kind == "devproduct" and item.id == receiptInfo.ProductId then
			prodDef = item
			break
		end
	end

	local stats = plr:FindFirstChild("leaderstats")
	if prodDef then
		if prodDef.cash and prodDef.cash > 0 then
			local cash = stats and stats:FindFirstChild("Cash") :: IntValue?
			if cash and cash:IsA("IntValue") then
				cash.Value += prodDef.cash
			end
		end

		if prodDef.wins and prodDef.wins > 0 then
			local wins = stats and stats:FindFirstChild("Wins") :: IntValue?
			if wins and wins:IsA("IntValue") then
				wins.Value += prodDef.wins
			end
		end

		if prodDef.robux and prodDef.robux > 0 then
			AddRobuxSpent:FireClient(plr, prodDef.robux)
		end
	end

	pcall(function()
		PurchaseHistoryStore:SetAsync(key, true)
	end)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print("[RobuxShopService] Ready")
