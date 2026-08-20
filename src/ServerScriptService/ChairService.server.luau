--[[
	ChairService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	Handles the chair system:
	  1. Buying  - each display chair in Workspace.DisplayChairs has a
	              ProximityPrompt. Interacting deducts Cash (leaderstats.Cash)
	              and adds the chair to the player's owned list.
	  2. Equip   - the client tells the server which owned chair to equip.
	  3. Replace - when a player sits on a game seat (Seat1/Seat2 in a TableN
	              folder), the chair model at that seat is replaced with the
	              player's equipped chair (Wooden is the default/basic).

	MODELS (you create these):
	  * ReplicatedStorage.Chairs  (Folder)  - the chair Models, named exactly
	    like the keys in ChairsConfig (Gamer, ProGamer, SuperFire, ...).
	  * Workspace.DisplayChairs   (Folder)  - the on-display chairs (these get
	    the ProximityPrompt). Names must match the config too.

	OWNERSHIP
	Owned chairs + equipped chair are stored in-memory per player session
	(resets on server restart) AND mirrored into a `Chairs` folder on the player
	so the client Inventory can read them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ChairsConfig = require(ReplicatedStorage:WaitForChild("ChairsConfig"))
local CHAIR_NAMES = ChairsConfig.Chairs

local Events = ReplicatedStorage:WaitForChild("Events")
local BuyChair = Events:WaitForChild("BuyChair")
local EquipChair = Events:WaitForChild("EquipChair")
local ChairSync = Events:WaitForChild("ChairSync")
local NotifyPlayer = Events:WaitForChild("NotifyPlayer")

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

local function ensureState(player)
	if not playerChair[player.UserId] then
		playerChair[player.UserId] = { owned = { Wooden = true }, equipped = "Wooden" }
	end
	return playerChair[player.UserId]
end

-- Mirror state into a folder on the player (for the client Inventory).
local function syncChairFolder(player, state)
	local folder = player:FindFirstChild("Chairs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Chairs"
		folder.Parent = player
	end
	-- Owned booleans.
	for name in pairs(state.owned) do
		if not folder:FindFirstChild(name) then
			local bv = Instance.new("BoolValue")
			bv.Name = name
			bv.Value = true
			bv.Parent = folder
		end
	end
	-- Equipped string.
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

local function notify(player, message)
	NotifyPlayer:FireClient(player, { title = "Chairs", message = message, kind = "info", duration = 3 })
end

-------------------------------------------------------------------------------
-- BUY (via display chairs)
-------------------------------------------------------------------------------
-- Handle a purchase for a player + chair name.
local function processBuy(player, chairName)
	if typeof(chairName) ~= "string" then return end
	local price = CHAIR_NAMES[chairName]
	if not price then
		notify(player, "Unknown chair.")
		return
	end
	local state = ensureState(player)
	if state.owned[chairName] then
		notify(player, "You already own " .. chairName .. ".")
		return
	end
	if getCash(player) < price then
		notify(player, "Not enough cash for " .. chairName .. " (R$" .. price .. ").")
		return
	end
	setCash(player, getCash(player) - price)
	state.owned[chairName] = true
	syncClient(player)
	notify(player, "Bought " .. chairName .. "!")
end

-- Add a ProximityPrompt to each display chair in Workspace.DisplayChairs.
-- Triggering it buys that chair (server-authoritative).
local DISPLAY = Workspace:WaitForChild("DisplayChairs")
local function setupDisplayChairs()
	for _, display in DISPLAY:GetChildren() do
		if display:IsA("Model") then
			-- Use the display model's name as the chair name (e.g. "Gamer").
			local chairName = display.Name
			-- The prompt can be on the PrimaryPart or any BasePart.
			local promptPart = display.PrimaryPart or display:FindFirstChildWhichIsA("BasePart")
			if promptPart then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "BuyPrompt"
				prompt.ObjectText = "Buy " .. chairName
				prompt.ActionText = "Buy"
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
setupDisplayChairs()

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
		notify(player, "You don't own " .. chairName .. ".")
		return
	end
	state.equipped = chairName
	syncClient(player)
	notify(player, "Equipped " .. chairName .. ".")
end)

-------------------------------------------------------------------------------
-- REPLACE CHAIR ON SIT
-- When a player sits on a game seat, swap the seat's chair model to their
-- equipped chair.
-------------------------------------------------------------------------------
-- Cache: seat -> { equipped = name, base = defaultChairModel, spawned = spawnedChairModel }
local seatChairState = {}

-- Hide/show every BasePart (and its surfaces) of a model by Transparency.
local function setModelHidden(model, hidden)
	if not model then return end
	local t = hidden and 1 or 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = t
		end
	end
	-- Model itself has no Transparency; toggle via a root part if present.
	if model:IsA("BasePart") then
		model.Transparency = t
	end
end

-- Find the default/base chair model at a seat. We pick the Model sibling in
-- the seat's parent that is CLOSEST to the seat, excluding the Table, the seats
-- themselves, and the spawned equipped-chair clones. This handles base chairs
-- named anything ("Chair1", "Chair2", "Wooden", ...).
local function findSeatChair(seat)
	local parent = seat.Parent
	if not parent then return nil end
	local best, bestDist
	local seatPos = seat.Position
	for _, child in parent:GetChildren() do
		if child:IsA("Model")
			and not child:IsA("Seat")
			and not child:IsA("VehicleSeat")
			and child.Name ~= "Table"
			and child.Name ~= "SpawnedChair"
		then
			local root = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
			if root then
				local d = (root.Position - seatPos).Magnitude
				if not bestDist or d < bestDist then
					best = child
					bestDist = d
				end
			end
		end
	end
	return best
end

-- Clone an equipped chair at a given CFrame (position + orientation). If a base
-- chair exists, we use ITS pivot so the equipped chair lands exactly where the
-- base chair was - inheriting its correct facing and ground level. Otherwise we
-- fall back to the seat's CFrame.
local function cloneChairAt(name, cf)
	if not ChairModels then return nil end
	local template = ChairModels:FindFirstChild(name)
	if not template then return nil end
	local clone = template:Clone()
	clone.Name = "SpawnedChair" -- excluded from findSeatChair
	clone:PivotTo(cf)
	clone.Parent = Workspace
	return clone
end

-- Apply the equipped chair to a seat, replacing the base chair.
-- IDEMPOTENT: if this seat is already showing the player's equipped chair,
-- it does nothing (so the poll loop doesn't re-clone every 0.5s).
local function applyChairToSeat(player, seat)
	local state = ensureState(player)
	local equipped = state.equipped or "Wooden"

	local st = seatChairState[seat] or {}
	seatChairState[seat] = st

	-- No change needed if we already applied this equipped chair.
	if st.appliedFor == player and st.appliedEquipped == equipped then
		return
	end
	st.appliedFor = player
	st.appliedEquipped = equipped

	-- Capture the base chair once.
	if st.base == nil then
		st.base = findSeatChair(seat)
	end

	-- Remove any previously spawned equipped chair.
	if st.spawned then
		if st.spawned.Parent then st.spawned:Destroy() end
		st.spawned = nil
	end

	-- Base chair: show only if we're using Wooden (the default).
	if st.base then
		setModelHidden(st.base, equipped ~= "Wooden")
	end

	-- Spawn the equipped chair (if not the default Wooden).
	if equipped ~= "Wooden" then
		-- Place it exactly where the base chair is (inherits facing + ground
		-- level). If no base chair was found, use the seat's CFrame.
		local cf
		if st.base then
			cf = st.base:GetPivot()
		else
			cf = seat.CFrame
		end
		local newChair = cloneChairAt(equipped, cf)
		if newChair then
			st.spawned = newChair
		end
	end
end

-- Restore the base chair and remove any spawned one when the player stands up.
local function restoreChair(seat)
	local st = seatChairState[seat]
	if not st then return end
	if st.spawned then
		if st.spawned.Parent then st.spawned:Destroy() end
		st.spawned = nil
	end
	if st.base then
		setModelHidden(st.base, false)
	end
	-- Reset the applied marker so re-sitting re-applies.
	st.appliedFor = nil
	st.appliedEquipped = nil
end

-- Detect sitting on game seats (same layout as GameManager: GameArea.TableN).
local GAME_AREA = Workspace:WaitForChild("GameArea")
local function isGameSeat(seat)
	local node = seat.Parent
	while node do
		if node:IsA("Folder") and string.sub(node.Name, 1, 5) == "Table" then
			return true
		end
		node = node.Parent
	end
	return false
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end

		-- Apply the equipped chair when sitting, restore the base when standing.
		humanoid.Seated:Connect(function(seated)
			local seat = humanoid.SeatPart
			if seat and isGameSeat(seat) then
				if seated then
					applyChairToSeat(player, seat)
				else
					restoreChair(seat)
				end
			end
		end)
	end)

	-- Send the client their initial chair data.
	task.delay(1, function()
		syncClient(player)
	end)
end)

-- Also poll seats (same approach as GameManager) so the chair swaps even if
-- Humanoid.Seated misses the event, and restore when the seat empties.
local function seatOccupiedBy(seat)
	local h = seat.Occupant
	return h and Players:GetPlayerFromCharacter(h.Parent) or nil
end

task.spawn(function()
	while true do
		task.wait(0.5)
		for _, tableFolder in GAME_AREA:GetChildren() do
			if tableFolder:IsA("Folder") and string.sub(tableFolder.Name, 1, 5) == "Table" then
				for _, seat in tableFolder:GetChildren() do
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
end)

-- On player leave, clean up their active chairs.
Players.PlayerRemoving:Connect(function(player)
	local state = playerChair[player.UserId]
	if state then
		playerChair[player.UserId] = nil
	end
end)

print("[ChairService] Ready")
