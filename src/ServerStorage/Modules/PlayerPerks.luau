--[[
	PlayerPerks.luau  (ModuleScript)  -- ServerStorage.Modules
	----------------------------------------------------------------------------
	Shared, CACHED gamepass ownership for the perk gamepasses. Every server
	system (cash multipliers, win/streak multipliers, VIP nametag, VIP chairs)
	reads perks through this module so ownership is checked consistently and
	UserOwnsGamePassAsync stays cheap (60s cache per player, and the purchase
	event itself grants the perk - required because Studio purchases are
	SIMULATED and never show up in UserOwnsGamePassAsync).

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
local CACHE_TTL = 60 -- seconds (wall clock)
local cache = {} -- userId -> { owned = {[key] = bool}, at = os.time() }
-- Passes granted through the in-game purchase event. Session-sticky and
-- never expires - a gamepass can't be un-owned, so once granted it holds
-- for the whole server. In Studio this is the ONLY source of truth:
-- simulated purchases never reach UserOwnsGamePassAsync.
local granted = {} -- userId -> { [key] = true }

-- Reverse lookup: gamepass id -> perk key.
local passIdToKey = {}
for key, id in pairs(PlayerPerks.IDS) do
	passIdToKey[id] = key
end

-- The moment a gamepass purchase is completed in-game, record it. In Studio
-- purchases are SIMULATED - UserOwnsGamePassAsync never learns about them -
-- so the perk must be granted from the purchase event itself (in live this
-- is just as correct: they really do own the pass now). Purchases of other
-- passes just clear the cache for a fresh check.
local announcedGrant = {}
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if wasPurchased and player then
		local key = passIdToKey[passId]
		if key then
			-- Sticky grant: survives the TTL cache, survives everything.
			local g = granted[player.UserId]
			if not g then
				g = {}
				granted[player.UserId] = g
			end
			g[key] = true
			-- Also feed the TTL cache so every read path sees it at once.
			local entry = cache[player.UserId] or { owned = {}, at = os.time() }
			entry.owned[key] = true
			cache[player.UserId] = entry
			if not announcedGrant[key] then
				announcedGrant[key] = true
				warn("[PlayerPerks] ", key, " is now active for ", player.Name,
					" - the multiplier applies from this purchase onwards. NOTE: in Studio, "
					.. "pass purchases are simulated and LAST ONLY THE CURRENT PLAY SESSION - "
					.. "if you bought it before applying the new scripts, buy it again in a "
					.. "fresh Play session.")
			end
		else
			cache[player.UserId] = nil
		end
	end
end)

local function entryFor(player)
	local e = cache[player.UserId]
	if e and (os.time() - e.at) < CACHE_TTL then
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
	-- 1) Granted in-session via the purchase event (Studio-proof).
	if granted[player.UserId] and granted[player.UserId][key] then
		return true
	end
	-- 2) Recent cache hit.
	local e = entryFor(player)
	if e then
		return e.owned[key] == true
	end
	-- 3) Ask the real ownership API (live purchases are caught here).
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	local result = ok and owns or false
	local entry = entryFor(player) or { owned = {}, at = os.time() }
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
