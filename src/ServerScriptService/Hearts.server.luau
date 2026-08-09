--[[
	Hearts.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	Clones a BillboardGui template from ServerStorage onto each player's
	character Head, showing that player's 3 hearts above their head. Everyone in
	the game (including the opponent) can see these hearts.

	It listens to the HeartUpdate RemoteEvent (fired by GameManager) to keep the
	BillboardGui's hearts in sync with the player's actual health (3 = all hearts
	visible, 1 = only Heart1 visible).

	REQUIRED TEMPLATE (create once, manually, in ServerStorage):
		ServerStorage.HeartHUD  (BillboardGui)
		   -- Size: UDim2.new(0, 150, 0, 40) ; StudsOffset: Vector3.new(0,3,0)
		   -- AlwaysOnTop: true
		   └── HeartFrame (Frame)  -- BackgroundTransparency 1
		        ├── UIListLayout    (FillDirection = Horizontal, Padding = 6)
		        ├── Heart1 (ImageLabel)  Image = rbxassetid://... your heart
		        ├── Heart2 (ImageLabel)  Image = rbxassetid://... your heart
		        └── Heart3 (ImageLabel)  Image = rbxassetid://... your heart

	The template lives in ServerStorage (not the player) so it can be cloned
	repeatedly and stays hidden from clients until attached to a character.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Events = ReplicatedStorage:WaitForChild("Events")
local HeartUpdate = Events:WaitForChild("HeartUpdate")

local TEMPLATE = ServerStorage:WaitForChild("HeartHUD", 30)
if not TEMPLATE then
	warn("[Hearts] ServerStorage.HeartHUD (BillboardGui) was not found. " ..
		"Create it before running this script.")
	return
end

-- Map player -> the BillboardGui currently attached to their head.
local playerBillboards = {}

-- Set visible hearts based on count (clamp to 0..3).
local function setHearts(billboard, heartCount)
	heartCount = math.clamp(heartCount, 0, 3)
	local frame = billboard:FindFirstChild("HeartFrame")
	if not frame then
		warn("[Hearts] HeartHUD template is missing 'HeartFrame'.")
		return
	end
	for i = 1, 3 do
		local heart = frame:FindFirstChild("Heart" .. i)
		if heart then
			heart.Visible = (i <= heartCount)
		end
	end
end

-- Attach a cloned BillboardGui to a character's head.
local function attachToCharacter(player, character)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end

	-- Remove any previously attached billboard for this player.
	local old = playerBillboards[player]
	if old then
		old:Destroy()
		playerBillboards[player] = nil
	end

	local billboard = TEMPLATE:Clone()
	billboard.Parent = head
	playerBillboards[player] = billboard

	-- Initialize at full hearts (3). GameManager will correct it shortly.
	setHearts(billboard, 3)
end

-- On character spawn, attach the billboard.
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		attachToCharacter(player, character)
	end)

	-- In case the player already has a character on join.
	if player.Character then
		attachToCharacter(player, player.Character)
	end
end)

-- Keep hearts in sync when GameManager fires HeartUpdate.
HeartUpdate.OnServerEvent:Connect(function(player, heartCount)
	if typeof(heartCount) ~= "number" then
		return
	end
	local billboard = playerBillboards[player]
	if billboard then
		setHearts(billboard, heartCount)
	end
end)
