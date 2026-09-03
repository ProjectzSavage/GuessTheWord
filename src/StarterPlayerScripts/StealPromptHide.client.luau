--[[
	StealPromptHide.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Roblox ProximityPrompts cannot be hidden per-player from the server.
	TheftService.server.luau puts a "Steal" prompt on EVERY player's torso so
	other players can see it. This LocalScript disables that prompt on YOUR
	own torso - locally only, so it never affects other players.

	Result: you see the "Steal" prompt on every OTHER player, and never on
	yourself. Without this script the prompt would also show on your own
	torso (you still couldn't trigger it on yourself - the server blocks that
	- but you'd see it, which is why this script exists).
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local announced = false

local function hideOwnPrompt(character)
	task.spawn(function()
		-- Same anchor as the server: torso (R15 = UpperTorso, R6 = Torso),
		-- head as a last resort. Must use WaitForChild (NOT FindFirstChild):
		-- at CharacterAdded the rig parts can still be loading, and a nil
		-- result here makes the hider give up on the wrong part - which is
		-- exactly how you ended up seeing the prompt on your own body.
		local anchor = character:WaitForChild("UpperTorso", 2)
			or character:WaitForChild("Torso", 2)
			or character:WaitForChild("Head", 10)
		if not anchor then
			return
		end
		local prompt = anchor:WaitForChild("StealPrompt", 15)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false -- local only; every other player still sees it
			if not announced then
				announced = true
				warn("[StealPromptHide] Active - the Steal prompt is hidden on your own torso, so it only shows on other players.")
			end
		end
	end)
end

if player.Character then
	hideOwnPrompt(player.Character)
end
player.CharacterAdded:Connect(hideOwnPrompt)
