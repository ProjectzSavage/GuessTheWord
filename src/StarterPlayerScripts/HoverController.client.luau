--[[
	HoverController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Applies the HoverFX pop effect to:
	  * The 4 clue images in GameUI.PuzzleArea.ImageGrid (Clue1..Clue4).
	  * Every letter tile in GameUI.PuzzleArea.ScrambledBank (including tiles
	    that InputHandler creates dynamically each round, via ChildAdded).

	This script is separate from InputHandler so you can tune the feel here
	without touching the game logic. Adjust the per-element options (scale /
	duration) to taste.

	REQUIRED UI:
		GameUI.PuzzleArea.ImageGrid      (Frame holding Clue1..Clue4 ImageLabels)
		GameUI.PuzzleArea.ScrambledBank  (Frame holding the letter tiles)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local HoverFX = require(ReplicatedStorage:WaitForChild("HoverFX"))
local SFX = require(ReplicatedStorage:WaitForChild("SFX"))

-- Play the hover sound when the mouse first enters an element.
local function applyHoverSound(element)
	element.MouseEnter:Connect(function()
		SFX.play("hover")
	end)
end

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")
local PuzzleArea = GameUI:WaitForChild("PuzzleArea")
local InteractionFrame = GameUI:WaitForChild("InteractionFrame")

local ImageGrid = PuzzleArea:WaitForChild("ImageGrid")
local ScrambledBank = PuzzleArea:WaitForChild("ScrambledBank")

-------------------------------------------------------------------------------
-- CLUE IMAGES (Clue1..Clue4)
-------------------------------------------------------------------------------
local function applyToClue(clue)
	if not clue:IsA("ImageLabel") then
		return
	end
	HoverFX.applyTo(clue, { scale = 1.12, duration = 0.18 })
	applyHoverSound(clue)
end

-- Existing clues.
for _, clue in ImageGrid:GetChildren() do
	applyToClue(clue)
end

-- Clues added later (in case you spawn them).
ImageGrid.ChildAdded:Connect(function(clue)
	applyToClue(clue)
end)

-------------------------------------------------------------------------------
-- SCRAMBLED BANK TILES (created dynamically by InputHandler)
-------------------------------------------------------------------------------
local function applyToTile(tile)
	if not tile:IsA("ImageButton") then
		return
	end
	HoverFX.applyTo(tile, { scale = 1.22, duration = 0.16 })
	applyHoverSound(tile)
end

ScrambledBank.ChildAdded:Connect(function(tile)
	applyToTile(tile)
end)

-------------------------------------------------------------------------------
-- PLAY VS BOT BUTTON
-------------------------------------------------------------------------------
local PlayVsBotButton = InteractionFrame:FindFirstChild("PlayVsBotButton")
if PlayVsBotButton and PlayVsBotButton:IsA("GuiButton") then
	HoverFX.applyTo(PlayVsBotButton, { scale = 1.15, duration = 0.18 })
	applyHoverSound(PlayVsBotButton)
end
