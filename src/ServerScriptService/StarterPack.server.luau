--[[
	StarterPack.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	The Starter Pack is a GAMEPASS (id below). Gamepasses have no ProcessReceipt,
	so this script grants the pack's rewards itself, exactly ONCE per player:

	  * +$500 Cash
	  * +1 Reveal Letter
	  * Random Chair (one of the cheap chairs)

	GRANT TIMING
	  * Player joins ALREADY owning the gamepass (rejoin) -> granted on join.
	  * Player buys it mid-session -> granted via GamePassPurchaseProcessed.

	PERSISTENCE
	"Granted" is stored in a DataStore so a server restart never re-grants the
 pack. If DataStores are unavailable (Studio without API access), it falls back
 to an in-memory set for the session - the pack still works, it just could
 re-grant after a restart in that configuration.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

-------------------------------------------------------------------------------
-- CONFIG
-------------------------------------------------------------------------------
local STARTER_PACK_GAMEPASS_ID = 1958400378

local STARTER_PACK_CASH = 500
local STARTER_PACK_LETTER_USES = 1
local CHEAP_CHAIRS = { "Broken", "Steel", "Icey", "Thunder", "Toxic" }

-------------------------------------------------------------------------------
-- PERSISTENCE (DataStore with in-memory fallback)
-------------------------------------------------------------------------------
local grantedThisSession = {}

local store = nil
local okStore = pcall(function()
	store = DataStoreService:GetDataStore("StarterPack_v1")
end)
if not okStore then
	store = nil
end

local function hasClaimed(userId)
	if store then
		local ok, v = pcall(function()
			return store:GetAsync(userId)
		end)
		if ok then
			return v == true
		end
	end
	return grantedThisSession[userId] == true
end

local function markClaimed(userId)
	grantedThisSession[userId] = true
	if store then
		pcall(function()
			store:SetAsync(userId, true)
		end)
	end
end

-------------------------------------------------------------------------------
-- GRANTING
-------------------------------------------------------------------------------
local function grantStarterPack(player)
	-- +Cash
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") then
		cash.Value = cash.Value + STARTER_PACK_CASH
	end

	-- +Reveal Letter uses (ensure the hidden Stats folder/values exist)
	local stats = player:FindFirstChild("Stats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "Stats"
		stats.Parent = player
	end
	local uses = stats:FindFirstChild("RevealLetterUses")
	if not uses then
		uses = Instance.new("IntValue")
		uses.Name = "RevealLetterUses"
		uses.Value = 0
		uses.Parent = stats
	end
	uses.Value = uses.Value + STARTER_PACK_LETTER_USES

	-- Random chair (ChairService may load after us - retry briefly)
	task.spawn(function()
		for _ = 1, 10 do
			if _G.ChairsGetOwned and _G.ChairsGrant then
				local owned = _G.ChairsGetOwned(player)
				local pool = {}
				for _, name in ipairs(CHEAP_CHAIRS) do
					if not owned[name] then
						table.insert(pool, name)
					end
				end
				if #pool > 0 then
					_G.ChairsGrant(player, pool[math.random(1, #pool)])
				end
				return
			end
			task.wait(1)
		end
	end)

	-- Tell the player what they got.
	local events = ReplicatedStorage:FindFirstChild("Events")
	local notify = events and events:FindFirstChild("NotifyPlayer")
	if notify then
		notify:FireClient(player, {
			title = "Starter Pack",
			message = "+$" .. STARTER_PACK_CASH .. ", +1 Reveal Letter, Random Chair",
			kind = "success",
			duration = 4,
		})
	end
end

local function tryGrantIfOwned(player)
	if not player or not player.Parent then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, STARTER_PACK_GAMEPASS_ID)
	end)
	if not (ok and owns) then
		return
	end
	if hasClaimed(player.UserId) then
		return
	end
	markClaimed(player.UserId)
	grantStarterPack(player)
end

-------------------------------------------------------------------------------
-- EVENTS
-------------------------------------------------------------------------------
-- Buying the pack mid-session.
MarketplaceService.GamePassPurchaseProcessed:Connect(function(player, gamePassId)
	if gamePassId ~= STARTER_PACK_GAMEPASS_ID then
		return
	end
	if hasClaimed(player.UserId) then
		return
	end
	markClaimed(player.UserId)
	grantStarterPack(player)
end)

-- Rejoins of players who already own it.
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		tryGrantIfOwned(player)
	end)
end)
