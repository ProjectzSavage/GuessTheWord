--[[
	PlayerPerks.luau  (ModuleScript)  -- ServerStorage.Modules
	----------------------------------------------------------------------------
	Shared, CACHED gamepass ownership for the perk gamepasses. Every server
	system (cash multipliers, win/streak multipliers, VIP nametag, VIP chairs)
	reads perks through this module so ownership is checked consistently and
	UserOwnsGamePassAsync stays cheap (60s cache per player, invalidated the
	moment the player buys any gamepass).

	PERKS
	  VIP        1960374374  -> x1.5 cash, [VIP] nametag, exclusive VIP chairs
	  DoubleCash 1958940384  -> x2 cash (stacks with VIP => x3)
	  DoubleStreak 1958292387 -> streak grows by 2 per win
	  DoubleWins 1960056393  -> wins grow by 2 per win

	USAGE
		local PlayerPerks = require(ServerStorage.Modules.PlayerPerks)
		PlayerPerks.cashMult(player)      -- 1 / 1.5 / 2 / 3
		PlayerPerks.winsMult(player)      -- 1 or 2
		PlayerPerks.streakMult(player)    -- 1 or 2
		PlayerPerks.owns(player, "VIP")   -- bool (yields)
]]

local MarketplaceService = game:GetService("MarketplaceService")

local PlayerPerks = {}

PlayerPerks.IDS = {
	VIP = 1960374374,
	DoubleCash = 1958940384,
	DoubleStreak = 1958292387,
	DoubleWins = 1960056393,
}

PlayerPerks.MULTIPLIERS = {
	VIP_CASH = 1.5,
	DOUBLE_CASH = 2,
	DOUBLE_WINS = 2,
	DOUBLE_STREAK = 2,
}

-------------------------------------------------------------------------------
-- CACHED OWNERSHIP
-------------------------------------------------------------------------------
local CACHE_TTL = 60 -- seconds
local cache = {} -- userId -> { owned = {[key] = bool}, at = os.clock() }

-- The moment a gamepass purchase is completed in-game, drop that player's
-- cached ownership so the new pass takes effect immediately (no TTL wait).
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if wasPurchased and player then
		cache[player.UserId] = nil
	end
end)

local function entryFor(player)
	local e = cache[player.UserId]
	if e and (os.clock() - e.at) < CACHE_TTL then
		return e
	end
	return nil
end

-- Does `player` own the gamepass for `key` (one of PlayerPerks.IDS)?
-- Yields. Returns false on any error (e.g. Studio without API access).
function PlayerPerks.owns(player, key)
	local passId = PlayerPerks.IDS[key]
	if not passId or not player then
		return false
	end
	local e = entryFor(player)
	if e then
		return e.owned[key] == true
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	local result = ok and owns or false
	local entry = entryFor(player) or { owned = {}, at = os.clock() }
	entry.owned[key] = result
	cache[player.UserId] = entry
	return result
end

-------------------------------------------------------------------------------
-- MULTIPLIERS
-------------------------------------------------------------------------------
-- Total cash multiplier for this player (VIP x1.5, 2x Cash x2, stackable).
function PlayerPerks.cashMult(player)
	local mult = 1
	if PlayerPerks.owns(player, "VIP") then
		mult = mult * PlayerPerks.MULTIPLIERS.VIP_CASH
	end
	if PlayerPerks.owns(player, "DoubleCash") then
		mult = mult * PlayerPerks.MULTIPLIERS.DOUBLE_CASH
	end
	return mult
end

-- Wins gained per win (2x Wins pass => 2).
function PlayerPerks.winsMult(player)
	if PlayerPerks.owns(player, "DoubleWins") then
		return PlayerPerks.MULTIPLIERS.DOUBLE_WINS
	end
	return 1
end

-- Streak gained per win (2x Streak pass => 2).
function PlayerPerks.streakMult(player)
	if PlayerPerks.owns(player, "DoubleStreak") then
		return PlayerPerks.MULTIPLIERS.DOUBLE_STREAK
	end
	return 1
end

-- Convenience for UI/server: the gamepass id for a key (0 if unknown).
function PlayerPerks.id(key)
	return PlayerPerks.IDS[key] or 0
end

return PlayerPerks
