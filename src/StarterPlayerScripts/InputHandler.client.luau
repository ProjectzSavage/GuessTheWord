--[[
	InputHandler.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	RESPONSIBILITIES
	* HYBRID INPUT:
	    - CLICK: clicking a letter tile in PuzzleArea.ScrambledBank appends it.
	    - TYPE:  pressing a keyboard A-Z key appends that letter.
	    - BACKSPACE removes the last letter.
	    - SUBMIT: when the answer reaches the round's word length, it
	      automatically fires SubmitGuess to the server for validation.
	* LETTER IMAGES: the scrambled bank tiles and the answer-box slots are shown
	  as IMAGES (from ReplicatedStorage.LetterImages), not text.
	* SCRAMBLED BANK: uses a UIGridLayout + a user-made "TileTemplate" (ImageButton)
	  inside ScrambledBank; the script clones it once per letter (one tile per
	  letter of the word) and wires clicks. If no template exists, tiles are
	  built programmatically.
	* ANSWER BOX: builds one slot per letter, laid out by a CENTERED UIListLayout
	  so the whole word stays centered as you type. Empty slots show the
	  underscore image; filled slots show the letter image. The newest letter
	  fills the next slot left-to-right (like a centered word stack).
	* TOPBAR HEARTS: fills PlayerHeartContainer (your hearts) and
	  OpponentHeartContainer (the enemy's) from HeartUpdate / OpponentHeartUpdate.

	REQUIRED UI (see docs/UI_HIERARCHY.md) - must exist in StarterGui.GameUI:
		GameUI  (ScreenGui)
		  ├── TopBar  (Frame)
		  │     ├── OpponentHeartContainer (Folder)  Heart1/2/3 (ImageLabel)
		  │     ├── TimerLabel (TextLabel)
		  │     └── PlayerHeartContainer (Folder)    Heart1/2/3 (ImageLabel)
		  ├── PuzzleArea  (Frame)
		  │     ├── AnswerBox (Frame)   -- slots are built here as ImageLabels
		  │     └── ScrambledBank (Frame)
		  │           ├── UIGridLayout  (optional, recommended)
		  │           └── TileTemplate  (ImageButton, optional, Visible=false)
		  └── InteractionFrame  (Frame)
		        └── PlayVsBotButton (TextButton)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Letter images (fill in your asset IDs here).
local LetterImages = require(ReplicatedStorage:WaitForChild("LetterImages"))

local Events = ReplicatedStorage:WaitForChild("Events")
local SubmitGuess = Events:WaitForChild("SubmitGuess")
local RoundStart = Events:WaitForChild("RoundStart")
local RoundEnd = Events:WaitForChild("RoundEnd")
local Countdown = Events:WaitForChild("Countdown")
local TimerUpdate = Events:WaitForChild("TimerUpdate")
local HeartUpdate = Events:WaitForChild("HeartUpdate")
local OpponentHeartUpdate = Events:WaitForChild("OpponentHeartUpdate")
local GameOver = Events:WaitForChild("GameOver")
local OpponentState = Events:WaitForChild("OpponentState")
local PlayVsBotRequest = Events:WaitForChild("PlayVsBotRequest")

-- UI references (fail loudly if the hierarchy is wrong - easy to debug).
local GameUI = PlayerGui:WaitForChild("GameUI")
local TopBar = GameUI:WaitForChild("TopBar")
local TimerLabel = TopBar:WaitForChild("TimerLabel")
local PlayerHeartContainer = TopBar:WaitForChild("PlayerHeartContainer")
local OpponentHeartContainer = TopBar:WaitForChild("OpponentHeartContainer")
local PuzzleArea = GameUI:WaitForChild("PuzzleArea")
local AnswerBox = PuzzleArea:WaitForChild("AnswerBox")
local ScrambledBank = PuzzleArea:WaitForChild("ScrambledBank")
local InteractionFrame = GameUI:WaitForChild("InteractionFrame")
local PlayVsBotButton = InteractionFrame:WaitForChild("PlayVsBotButton")

if AnswerBox:IsA("TextBox") then
	warn("[InputHandler] AnswerBox must be a Frame (it now renders ImageLabels), " ..
		"not a TextBox. See docs/UI_HIERARCHY.md.")
end

-------------------------------------------------------------------------------
-- UI VISIBILITY
-- A Frame with Visible=false hides ALL its children, so we control the top-level
-- frames' Visible here. GameUI is a ScreenGui -> uses .Enabled, not .Visible.
-------------------------------------------------------------------------------
GameUI.Enabled = true

local function setWaitingUI(waiting)
	TopBar.Visible = false
	PuzzleArea.Visible = false
	InteractionFrame.Visible = waiting
	PlayVsBotButton.Visible = waiting
end

local function setPlayingUI()
	TopBar.Visible = true
	PuzzleArea.Visible = true
	InteractionFrame.Visible = false
end

-------------------------------------------------------------------------------
-- STATE
-------------------------------------------------------------------------------
local wordLength = 0
local currentGuess = ""      -- letters typed so far
local buttonMap = {}         -- tile -> letter
local slots = {}             -- index -> ImageLabel slot
local roundActive = false

setWaitingUI(false) -- start hidden until the server says otherwise

-------------------------------------------------------------------------------
-- TOPBAR HEARTS
-------------------------------------------------------------------------------
local function setHeartsInContainer(container, count)
	count = math.clamp(count, 0, 3)
	for i = 1, 3 do
		local heart = container:FindFirstChild("Heart" .. i)
		if heart then
			heart.Visible = (i <= count)
		end
	end
end

HeartUpdate.OnClientEvent:Connect(function(count)
	setHeartsInContainer(PlayerHeartContainer, count)
end)

OpponentHeartUpdate.OnClientEvent:Connect(function(count)
	setHeartsInContainer(OpponentHeartContainer, count)
end)

-------------------------------------------------------------------------------
-- SCRAMBLED BANK (template + UIGridLayout)
-------------------------------------------------------------------------------
local function buildBank(letterBank)
	-- Clear old tiles, but KEEP the user's TileTemplate (and any layout).
	for _, child in ScrambledBank:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "TileTemplate" then
			child:Destroy()
		end
	end
	buttonMap = {}

	-- Ensure a UIGridLayout exists (use the user's if they added one).
	if not ScrambledBank:FindFirstChildOfClass("UIGridLayout") then
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0, 44, 0, 44)
		grid.CellPadding = UDim2.new(0, 8, 0, 8)
		grid.Parent = ScrambledBank
	end

	local template = ScrambledBank:FindFirstChild("TileTemplate")
	if template and template:IsA("GuiButton") then
		template.Visible = false -- never show the template itself
	end

	-- One tile per letter in the bank (one tile per letter of the word).
	for i, letter in letterBank do
		local tile
		if template then
			tile = template:Clone()
			tile.Visible = true -- clones inherit Visible=false; force it on
		else
			tile = Instance.new("ImageButton")
			tile.BackgroundColor3 = Color3.fromRGB(70, 90, 140)
			tile.BackgroundTransparency = 0.2
			tile.AutoButtonColor = true
		end
		tile.Name = "Tile" .. i
		tile.Image = LetterImages[letter] or ""
		tile.ScaleType = Enum.ScaleType.Fit
		tile.Parent = ScrambledBank

		buttonMap[tile] = letter
	end
end

-------------------------------------------------------------------------------
-- ANSWER BOX (centered slots with underscore)
-------------------------------------------------------------------------------
-- Build one ImageLabel slot per letter, laid out by a CENTERED UIListLayout.
-- Empty slots show the underscore image; filled slots show the letter image.
local function buildSlots()
	for _, child in AnswerBox:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	slots = {}

	-- Centered horizontal layout so the whole word stays centered.
	if not AnswerBox:FindFirstChildOfClass("UIListLayout") then
		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Horizontal
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.VerticalAlignment = Enum.VerticalAlignment.Center
		ll.Padding = UDim.new(0, 6)
		ll.Parent = AnswerBox
	end

	for i = 1, wordLength do
		local slot = Instance.new("ImageLabel")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.new(0, 48, 0, 48)
		slot.BackgroundTransparency = 1
		slot.ScaleType = Enum.ScaleType.Fit
		slot.Image = LetterImages.underscore or ""
		slot.Parent = AnswerBox
		slots[i] = slot
	end

	refreshSlots()
end

-- Update each slot's image to match currentGuess (letter or underscore).
local function refreshSlots()
	for i = 1, wordLength do
		local slot = slots[i]
		if slot then
			local ch = string.sub(currentGuess, i, i)
			if ch ~= "" then
				slot.Image = LetterImages[ch] or ""
			else
				slot.Image = LetterImages.underscore or ""
			end
		end
	end
end

-------------------------------------------------------------------------------
-- INPUT
-------------------------------------------------------------------------------
local function appendLetter(letter)
	if not roundActive or wordLength == 0 then
		return
	end
	if #currentGuess >= wordLength then
		return
	end
	currentGuess = currentGuess .. letter
	refreshSlots()

	-- AUTO-SUBMIT: full length reached -> server validates.
	if #currentGuess >= wordLength then
		roundActive = false -- lock input for this round
		task.delay(0.2, function()
			SubmitGuess:FireServer(currentGuess)
		end)
	end
end

local function backspace()
	if not roundActive then
		return
	end
	if #currentGuess > 0 then
		currentGuess = string.sub(currentGuess, 1, -2)
		refreshSlots()
	end
end

-- CLICK: wire ScrambledBank tiles (both user template clones and fallbacks).
ScrambledBank.ChildAdded:Connect(function(tile)
	if not tile:IsA("ImageButton") then
		return
	end
	tile.Activated:Connect(function()
		local letter = buttonMap[tile]
		if letter then
			appendLetter(letter)
		end
	end)
end)

-- KEYBOARD: hybrid input (A-Z, Backspace, Enter to submit early).
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local key = input.KeyCode
		if key == Enum.KeyCode.Backspace then
			backspace()
			return
		end
		-- Enter = Return (main key) or KeypadEnter (numpad).
		if (key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter)
			and roundActive and #currentGuess > 0 then
			roundActive = false
			SubmitGuess:FireServer(currentGuess)
			return
		end
		local code = tostring(key)
		if #code == 1 then
			local ch = string.lower(code)
			if ch:match("%a") then
				appendLetter(ch)
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- GAME EVENTS -> UI
-------------------------------------------------------------------------------
-- Pre-match 3..2..1 countdown (shown in the timer label).
Countdown.OnClientEvent:Connect(function(n)
	setPlayingUI()
	TimerLabel.Text = tostring(n)
end)

-- Round timer tick (15 -> 0).
TimerUpdate.OnClientEvent:Connect(function(seconds)
	TimerLabel.Text = tostring(seconds)
end)

RoundStart.OnClientEvent:Connect(function(length, letterBank, images)
	setPlayingUI()
	wordLength = length
	currentGuess = ""
	roundActive = true
	buildBank(letterBank)
	buildSlots()
	-- (Optionally display `images` in PuzzleArea.ImageGrid here.)
	PlayVsBotButton.Visible = false
end)

RoundEnd.OnClientEvent:Connect(function(result, correctWord)
	roundActive = false
	-- Reveal the word using letter images.
	wordLength = #correctWord
	currentGuess = correctWord
	buildSlots()
	TimerLabel.Text = "0"
end)

GameOver.OnClientEvent:Connect(function(winnerName, youWon, isDraw)
	roundActive = false
	if isDraw then
		TimerLabel.Text = "DRAW"
	elseif youWon then
		TimerLabel.Text = "WIN"
	else
		TimerLabel.Text = "LOSE"
	end
end)

OpponentState.OnClientEvent:Connect(function(waiting)
	-- Show the "Play vs Bot" area only while waiting for an opponent.
	setWaitingUI(waiting)
end)

-------------------------------------------------------------------------------
-- PLAY VS BOT BUTTON (immediate - no timer wait)
-------------------------------------------------------------------------------
PlayVsBotButton.Activated:Connect(function()
	PlayVsBotButton.Visible = false
	PlayVsBotRequest:FireServer()
end)
