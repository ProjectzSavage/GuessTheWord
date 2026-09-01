--[[
	StealPromptHide.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Roblox ProximityPrompts cannot be hidden per-player from the server.
	TheftService.server.luau puts a "Steal" prompt on EVERY player's head so
	other players can see it. This LocalScript disables that prompt on YOUR
	own head - locally only, so it never affects other players.

	Result: you see the "Steal" prompt above every OTHER player, and never on
	yourself. Without this script the prompt would also show on your own head
	(you still couldn't trigger it on yourself - the server blocks that - but
	you'd see it, which is why this script exists).
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local announced = false

local function hideOwnPrompt(character)
	task.spawn(function()
		local head = character:WaitForChild("Head", 10)
		if not head then
			return
		end
		local prompt = head:WaitForChild("StealPrompt", 10)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false -- local only; every other player still sees it
			if not announced then
				announced = true
				warn("[StealPromptHide] Active - the Steal prompt is hidden on your own head, so it only shows above other players.")
			end
		end
	end)
end

if player.Character then
	hideOwnPrompt(player.Character)
end
player.CharacterAdded:Connect(hideOwnPrompt)
