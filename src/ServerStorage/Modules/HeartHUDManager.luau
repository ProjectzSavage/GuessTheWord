--[[
	HeartHUDManager.luau  (ModuleScript)
	----------------------------------------------------------------------------
	Place in: ServerStorage.Modules.HeartHUDManager

	PURPOSE
	Owns every player's above-head hearts. It is required by BOTH server scripts:
	  * Hearts.server.luau  -> calls HeartHUDManager.register() when a character
	                           spawns (clones the BillboardGui onto the head,
	                           hidden by default).
	  * GameManager.server.luau -> calls HeartHUDManager.setHearts() whenever a
	                           player's heart count changes (start of match and
	                           every lost heart).

	This keeps heart visibility SERVER-authoritative. A plain RemoteEvent can't
	relay server->server, so both scripts share this module instead of trying to
	listen to HeartUpdate with OnServerEvent (which only receives client->server
	calls and would never fire here).

	VISIBILITY RULE
	* On spawn the billboard is cloned with Enabled = false, so hearts are NOT
	  shown while the player is idle / walking / waiting to sit.
	* The first setHearts() (fired by GameManager when the match actually starts)
	  sets Enabled = true and reveals the correct number of hearts.
	* Every player can see these hearts (the billboard sits on the character).
]]

local ServerStorage = game:GetService("ServerStorage")

local HeartHUDManager = {}

-- TEMPLATE must exist in ServerStorage (see docs/UI_HIERARCHY.md -> HeartHUD).
local TEMPLATE = ServerStorage:WaitForChild("HeartHUD", 30)

-- player -> BillboardGui currently attached to their head.
local billboards = {}

-- Attach a cloned (hidden) BillboardGui to a player's head.
function HeartHUDManager.register(player, character)
	if not TEMPLATE then
		return
	end
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end

	-- Remove any previous billboard for this player.
	local old = billboards[player]
	if old then
		old:Destroy()
		billboards[player] = nil
	end

	local bb = TEMPLATE:Clone()
	bb.Enabled = false -- hidden until the match starts
	bb.Parent = head
	billboards[player] = bb
end

-- Reveal and set the heart count (0..3) on a player's billboard.
-- Called by GameManager whenever the count changes.
function HeartHUDManager.setHearts(player, heartCount)
	local bb = billboards[player]
	if not bb then
		return
	end
	if type(heartCount) ~= "number" then
		return
	end
	heartCount = math.clamp(heartCount, 0, 3)

	local frame = bb:FindFirstChild("HeartFrame")
	if not frame then
		warn("[HeartHUDManager] HeartHUD template is missing 'HeartFrame'.")
		return
	end

	bb.Enabled = true -- the game has started -> show hearts
	for i = 1, 3 do
		local heart = frame:FindFirstChild("Heart" .. i)
		if heart then
			heart.Visible = (i <= heartCount)
		end
	end
end

-- Cleanup when a player leaves / character is destroyed.
function HeartHUDManager.remove(player)
	local bb = billboards[player]
	if bb then
		bb:Destroy()
	end
	billboards[player] = nil
end

return HeartHUDManager
