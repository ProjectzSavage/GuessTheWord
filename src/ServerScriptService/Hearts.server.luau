--[[
	Hearts.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService (optionally
	inside the "Scripts" folder).

	PURPOSE
	Handles the above-head hearts. On character spawn it registers the player
	with HeartHUDManager, which clones a hidden BillboardGui from ServerStorage
	onto the player's Head. The hearts stay HIDDEN until GameManager calls
	HeartHUDManager.setHearts() when the match actually starts.

	This script does NOT listen to a RemoteEvent to update hearts. Because
	GameManager (server) and this script (server) run on the same machine, they
	share the HeartHUDManager module directly - a RemoteEvent's OnServerEvent only
	receives client->server calls and would never fire for server->server updates.

	REQUIRED TEMPLATE (create once, manually, in ServerStorage):
		ServerStorage.HeartHUD  (BillboardGui)  Enabled defaults to true in studio;
		the module clones it and sets Enabled = false until the match starts.
		   -- Size: UDim2.new(0, 150, 0, 40) ; StudsOffset: Vector3.new(0,3,0)
		   -- AlwaysOnTop: true
		   └── HeartFrame (Frame)  -- BackgroundTransparency 1
		        ├── UIListLayout    (FillDirection = Horizontal, Padding = 6)
		        ├── Heart1 (ImageLabel)
		        ├── Heart2 (ImageLabel)
		        └── Heart3 (ImageLabel)
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local HeartHUDManager = require(ServerStorage.Modules.HeartHUDManager)

Players.PlayerAdded:Connect(function(player)
	-- Attach a fresh (hidden) billboard each time the character (re)spawns.
	player.CharacterAdded:Connect(function(character)
		HeartHUDManager.register(player, character)
	end)

	-- In case the player already has a character on join.
	if player.Character then
		HeartHUDManager.register(player, player.Character)
	end
end)

-- Cleanup if a player leaves.
Players.PlayerRemoving:Connect(function(player)
	HeartHUDManager.remove(player)
end)
