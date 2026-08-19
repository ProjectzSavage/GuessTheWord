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
-- Cache: seat -> the active chair Model currently shown there.
local activeChair = {}

-- Find a chair model at a seat: look for a Model sibling in the seat's parent
-- whose name is a valid chair name (e.g. the default "Wooden").
local function findSeatChair(seat)
	local parent = seat.Parent
	if not parent then return nil end
	for _, child in parent:GetChildren() do
		if child:IsA("Model") and CHAIR_NAMES[child.Name] then
			return child
		end
	end
	return nil
end

local function cloneChair(name, seat)
	if not ChairModels then return nil end
	local template = ChairModels:FindFirstChild(name)
	if not template then return nil end
	local clone = template:Clone()
	clone.Name = name
	clone:PivotTo(seat.CFrame * CFrame.new(0, 1, 0)) -- sit above the seat
	clone.Parent = seat.Parent or Workspace
	return clone
end

-- Apply the equipped chair to a seat.
local function applyChairToSeat(player, seat)
	local state = ensureState(player)
	local equipped = state.equipped or "Wooden"

	-- Remove the previous active chair clone at this seat (if any).
	local old = activeChair[seat]
	if old then
		if old.Parent then old:Destroy() end
		activeChair[seat] = nil
	end

	-- Hide the default chair model if it exists and differs.
	local default = findSeatChair(seat)
	if default and default.Name ~= equipped then
		default.Transparency = 1
		-- Also hide any BaseParts inside the default model.
		for _, p in default:GetDescendants() do
			if p:IsA("BasePart") then p.Transparency = 1 end
		end
	end

	-- If equipped is Wooden (or default), nothing extra to spawn.
	if equipped == "Wooden" then
		if default then
			for _, p in default:GetDescendants() do
				if p:IsA("BasePart") then p.Transparency = 0 end
			end
			default.Transparency = 0
		end
		return
	end

	local newChair = cloneChair(equipped, seat)
	if newChair then
		activeChair[seat] = newChair
	end
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
		humanoid.Seated:Connect(function(seated)
			if seated then
				local seat = humanoid.SeatPart
				if seat and isGameSeat(seat) then
					applyChairToSeat(player, seat)
				end
			end
		end)
	end)

	-- Send the client their initial chair data.
	task.delay(1, function()
		syncClient(player)
	end)
end)

-- On player leave, clean up their active chairs.
Players.PlayerRemoving:Connect(function(player)
	local state = playerChair[player.UserId]
	if state then
		playerChair[player.UserId] = nil
	end
end)

print("[ChairService] Ready")
