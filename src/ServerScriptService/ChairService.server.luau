--[[
	ChairService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	Handles the chair system:
	  1. Buying  - each display chair in Workspace.DisplayChairs has a
	              ProximityPrompt. Interacting deducts Cash (leaderstats.Cash)
	              and adds the chair to the player's owned list.
	  2. Gamepass Chairs - checks ownership of exclusive Robux chairs
	              (HackerChair, SpacialMist, PinkVortex) and grants them automatically.
	  2b. VIP Chair   - the special VIPChair is granted automatically to VIP
	              gamepass owners (on join and on purchase, via PlayerPerks).
	  3. Equip   - the client tells the server which owned chair to equip.
	  4. Replace - when a player sits on a game seat (Seat1/Seat2 in a TableN
	              folder), the chair model at that seat is replaced with the
	              player's equipped chair (Wooden is the default/basic).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local ChairsConfig = require(ReplicatedStorage:WaitForChild("ChairsConfig"))
local PlayerPerks = require(ServerStorage.Modules.PlayerPerks)
local CHAIR_NAMES = ChairsConfig.Chairs
local GAMEPASS_CHAIRS = ChairsConfig.GamepassChairs or {}
local VIP_CHAIRS = ChairsConfig.VIPChairs or {}
local VIP_PASS_ID = PlayerPerks.IDS.VIP

local Events = ReplicatedStorage:WaitForChild("Events")
local BuyChair = Events:WaitForChild("BuyChair")
local EquipChair = Events:WaitForChild("EquipChair")
local ChairSync = Events:WaitForChild("ChairSync")
local NotifyPlayer = Events:WaitForChild("NotifyPlayer")
-- Created if missing so the sync-request below works even on an older
-- Events folder.
local RequestChairSync = Events:FindFirstChild("RequestChairSync")
if not RequestChairSync then
	RequestChairSync = Instance.new("RemoteEvent")
	RequestChairSync.Name = "RequestChairSync"
	RequestChairSync.Parent = Events
end

-- Folder containing the actual chair models (clone source).
local ChairModels = ReplicatedStorage:FindFirstChild("Chairs")

-- In-memory player state: userId -> { owned = {name=true}, equipped = name }
local playerChair = {}

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------
local function getCash(player)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	return cash and cash.Value or 0
end

local function setCash(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") then
		cash.Value = amount
	end
end

local function checkGamepassChairs(player, state)
	for chairName, passId in pairs(GAMEPASS_CHAIRS) do
		if passId and passId > 0 and not state.owned[chairName] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if ok and owns then
				state.owned[chairName] = true
			end
		end
	end
end

local function ensureState(player)
	if not playerChair[player.UserId] then
		playerChair[player.UserId] = { owned = { Wooden = true }, equipped = "Wooden" }
		checkGamepassChairs(player, playerChair[player.UserId])
	end
	return playerChair[player.UserId]
end

-- Mirror state into a folder on the player (for client Inventory).
local function syncChairFolder(player, state)
	local folder = player:FindFirstChild("Chairs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Chairs"
		folder.Parent = player
	end
	for name in pairs(state.owned) do
		if not folder:FindFirstChild(name) then
			local bv = Instance.new("BoolValue")
			bv.Name = name
			bv.Value = true
			bv.Parent = folder
		end
	end
	local eq = folder:FindFirstChild("Equipped")
	if not eq then
		eq = Instance.new("StringValue")
		eq.Name = "Equipped"
		eq.Parent = folder
	end
	eq.Value = state.equipped
end

local function syncClient(player)
	local state = ensureState(player)
	syncChairFolder(player, state)
	local owned = {}
	for name in pairs(state.owned) do
		table.insert(owned, name)
	end
	ChairSync:FireClient(player, { owned = owned, equipped = state.equipped })
end

local function notify(player, title, message, kind)
	NotifyPlayer:FireClient(player, {
		title = title or "Chairs",
		message = message,
		kind = kind or "info",
		duration = 3.5,
	})
end

-- VIP includes the special VIP chair: grant every VIPChairs entry at once.
-- `assumeVip` is true when we KNOW the player just bought VIP (the purchase
-- itself is the proof - avoids a stale perks-cache race right after buying).
-- Returns true when at least one chair was newly granted.
local function grantVipChairs(player, state, assumeVip)
	if VIP_PASS_ID <= 0 or #VIP_CHAIRS == 0 then
		return false
	end
	local isVip = assumeVip and true or false
	if not isVip then
		local ok, owns = pcall(function()
			return PlayerPerks.owns(player, "VIP")
		end)
		isVip = ok and owns or false
	end
	if not isVip then
		return false
	end
	local granted = false
	for _, chairName in ipairs(VIP_CHAIRS) do
		if CHAIR_NAMES[chairName] and not state.owned[chairName] then
			state.owned[chairName] = true
			granted = true
			notify(player, "VIP Perks", "You unlocked the exclusive " .. chairName .. " chair!", "success")
		end
	end
	return granted
end

-------------------------------------------------------------------------------
-- BUY (via display chairs)
-------------------------------------------------------------------------------
local function processBuy(player, chairName)
	if typeof(chairName) ~= "string" then return end
	local price = CHAIR_NAMES[chairName]
	if not price then
		notify(player, "Shop", "Unknown chair.", "warn")
		return
	end
	if type(price) == "string" and price == "VIP" then
		-- VIP exclusive chair: no cash purchase - prompt the VIP gamepass.
		local state = ensureState(player)
		if state.owned[chairName] then
			notify(player, "Already Owned", "You already own " .. chairName .. "!", "info")
			return
		end
		if VIP_PASS_ID > 0 then
			MarketplaceService:PromptGamePassPurchase(player, VIP_PASS_ID)
		else
			notify(player, "VIP Exclusive", chairName .. " is a VIP exclusive chair!", "info")
		end
		return
	end
	if type(price) == "string" and price == "Gamepass" then
		local passId = GAMEPASS_CHAIRS[chairName]
		if passId and passId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, passId)
		else
			notify(player, "Exclusive Chair", chairName .. " is a Robux exclusive chair!", "info")
		end
		return
	end

	local state = ensureState(player)
	if state.owned[chairName] then
		notify(player, "Already Owned", "You already own " .. chairName .. "!", "info")
		return
	end
	if getCash(player) < price then
		notify(player, "Insufficient Funds", "Not enough cash for " .. chairName .. " ($" .. price .. ").", "warn")
		return
	end
	setCash(player, getCash(player) - price)
	state.owned[chairName] = true
	syncClient(player)
	notify(player, "Purchase Successful!", "You unlocked the " .. chairName .. " chair!", "success")
end

local DISPLAY = Workspace:FindFirstChild("DisplayChairs") or Workspace:WaitForChild("DisplayChairs", 10)
local function setupDisplayChairs()
	if not DISPLAY then return end
	for _, display in ipairs(DISPLAY:GetChildren()) do
		if display:IsA("Model") then
			local chairName = display.Name
			local promptPart = display.PrimaryPart or display:FindFirstChildWhichIsA("BasePart")
			if promptPart then
			local prompt = promptPart:FindFirstChild("BuyPrompt") or Instance.new("ProximityPrompt")
			prompt.Name = "BuyPrompt"
			local isVipChair = type(CHAIR_NAMES[chairName]) == "string" and CHAIR_NAMES[chairName] == "VIP"
			prompt.ObjectText = isVipChair and "Get the VIP " .. chairName .. " chair" or ("Buy " .. chairName)
			prompt.ActionText = isVipChair and "Get VIP" or "Buy"
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 20
				prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
				prompt.Triggered:Connect(function(plr)
					processBuy(plr, chairName)
				end)
				prompt.Parent = promptPart
			end
		end
	end
end
if DISPLAY then setupDisplayChairs() end

BuyChair.OnServerEvent:Connect(function(player, chairName)
	processBuy(player, chairName)
end)

-------------------------------------------------------------------------------
-- EQUIP
-------------------------------------------------------------------------------
EquipChair.OnServerEvent:Connect(function(player, chairName)
	if typeof(chairName) ~= "string" then return end
	local state = ensureState(player)
	if not state.owned[chairName] then
		notify(player, "Not Owned", "You don't own " .. chairName .. ".", "warn")
		return
	end
	state.equipped = chairName
	syncClient(player)
	notify(player, "Equipped", "Equipped " .. chairName .. ".", "info")
end)

-- The client asks for a fresh sync on load / when it opens the inventory.
-- This fixes "inventory empty until I buy something" on join (the initial
-- server sync can fire before the client has connected).
RequestChairSync.OnServerEvent:Connect(function(player)
	syncClient(player)
end)

-------------------------------------------------------------------------------
-- REPLACE CHAIR ON SIT
-------------------------------------------------------------------------------
local seatChairState = {}

local function setModelHidden(model, hidden)
	if not model then return end
	local t = hidden and 1 or 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = t
		end
	end
end

local function findSeatChairModel(seat)
	local p = seat.Parent
	if not p then return nil end
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("Model") and c ~= seat and string.find(string.lower(c.Name), "chair") then
			return c
		end
	end
	return nil
end

local function applyChairToSeat(player, seat)
	local state = ensureState(player)
	local equippedName = state.equipped or "Wooden"

	local cached = seatChairState[seat]
	if cached and cached.equipped == equippedName and cached.spawned and cached.spawned.Parent then
		return
	end

	local baseModel = cached and cached.base or findSeatChairModel(seat)
	if cached and cached.spawned and cached.spawned.Parent then
		cached.spawned:Destroy()
	end

	if equippedName == "Wooden" then
		setModelHidden(baseModel, false)
		seatChairState[seat] = { equipped = "Wooden", base = baseModel, spawned = nil }
		return
	end

	setModelHidden(baseModel, true)
	local template = ChairModels and ChairModels:FindFirstChild(equippedName)
	if not template then
		setModelHidden(baseModel, false)
		seatChairState[seat] = { equipped = "Wooden", base = baseModel, spawned = nil }
		return
	end

	local spawned = template:Clone()
	-- EXACT placement: the spawned chair's Pivot replaces the base chair
	-- model's (Chair1/Chair2) Pivot - identical position AND rotation.
	-- (Using a part's CFrame used to offset and tilt the chair.)
	local refCFrame = baseModel and baseModel:Pivot() or seat.CFrame
	spawned:PivotTo(refCFrame)
	for _, part in ipairs(spawned:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	spawned.Parent = seat.Parent
	seatChairState[seat] = { equipped = equippedName, base = baseModel, spawned = spawned }
end

local function restoreChair(seat)
	local cached = seatChairState[seat]
	if not cached then return end
	if cached.spawned and cached.spawned.Parent then
		cached.spawned:Destroy()
	end
	setModelHidden(cached.base, false)
	seatChairState[seat] = nil
end

-- Tables live under Workspace.GameArea (Table1, Table2, ...) - the same
-- layout GameManager uses. Fall back to the old layouts if needed.
local GAME_AREA = Workspace:WaitForChild("GameArea", 10)
	or Workspace:FindFirstChild("Tables")
	or Workspace

local function seatOccupiedBy(seat)
	local h = seat.Occupant
	return h and Players:GetPlayerFromCharacter(h.Parent) or nil
end

task.spawn(function()
	while true do
		task.wait(0.5)
		if GAME_AREA then
			for _, tableFolder in ipairs(GAME_AREA:GetChildren()) do
				if tableFolder:IsA("Folder") and string.sub(tableFolder.Name, 1, 5) == "Table" then
					for _, seat in ipairs(tableFolder:GetChildren()) do
						if (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
							local player = seatOccupiedBy(seat)
							if player then
								applyChairToSeat(player, seat)
							else
								restoreChair(seat)
							end
						end
					end
				end
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- PLAYER JOIN / LEAVE / GAMEPASS EVENTS
-------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	local state = ensureState(player)
	task.delay(1, function()
		if player.Parent then
			checkGamepassChairs(player, state)
			grantVipChairs(player, state) -- VIP pass includes the special VIP chair
			syncClient(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerChair[player.UserId] = nil
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased or not player then return end
	local state = ensureState(player)
	if passId == VIP_PASS_ID then
		grantVipChairs(player, state, true)
		syncClient(player)
		return
	end
	for chairName, id in pairs(GAMEPASS_CHAIRS) do
		if id == passId then
			state.owned[chairName] = true
			syncClient(player)
			notify(player, "Gamepass Unlocked!", "You unlocked the exclusive " .. chairName .. " chair!", "success")
			break
		end
	end
end)

-- Purchases made OUTSIDE the in-game prompt (the game's shop page, mobile
-- store) never fire the event above, so re-check VIP ownership every 60s -
-- the PlayerPerks cache (60s TTL) keeps this cheap.
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			local state = playerChair[player.UserId]
			if state then
				if grantVipChairs(player, state) then
					syncClient(player)
				end
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- PUBLIC API
-------------------------------------------------------------------------------
_G.ChairsGetOwned = function(player)
	if not player then return {} end
	local state = ensureState(player)
	local owned = {}
	for name in pairs(state.owned) do owned[name] = true end
	return owned
end

_G.ChairsGrant = function(player, chairName)
	if not player or typeof(chairName) ~= "string" then return false end
	if not CHAIR_NAMES[chairName] then return false end
	local state = ensureState(player)
	if state.owned[chairName] then return false end
	state.owned[chairName] = true
	syncClient(player)
	notify(player, "Reward Received!", "You unlocked the " .. chairName .. " chair!", "success")
	return true
end


