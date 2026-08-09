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
	* TOPBAR HEARTS: fills PlayerHeartContainer (your hearts) and
	  OpponentHeartContainer (the enemy's) from HeartUpdate / OpponentHeartUpdate.
	* Builds the ScrambledBank tiles dynamically each round (RoundStart).

	REQUIRED UI (see docs/UI_HIERARCHY.md) - must exist in StarterGui.GameUI:
		GameUI  (ScreenGui)
		  ├── TopBar  (Frame)
		  │     ├── OpponentHeartContainer (Folder)  Heart1/2/3 (ImageLabel)
		  │     ├── TimerLabel (TextLabel)
		  │     └── PlayerHeartContainer (Folder)    Heart1/2/3 (ImageLabel)
		  ├── PuzzleArea  (Frame)
		  │     ├── AnswerBox (Frame)   -- slots are built here as ImageLabels
		  │     └── ScrambledBank (Frame)
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
-- LETTER-IMAGE BUILDERS
-------------------------------------------------------------------------------
-- Scrambled bank: create one ImageButton tile per letter.
local function buildBank(letterBank)
	-- clear old tiles
	for _, child in ScrambledBank:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	buttonMap = {}

	-- horizontal flow
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = ScrambledBank

	for i, letter in letterBank do
		local tile = Instance.new("ImageButton")
		tile.Name = "Tile" .. i
		tile.Size = UDim2.new(0, 44, 0, 44)
		tile.Image = LetterImages[letter] or ""
		tile.BackgroundColor3 = Color3.fromRGB(70, 90, 140)
		tile.BackgroundTransparency = 0.2
		tile.ScaleType = Enum.ScaleType.Fit
		tile.AutoButtonColor = true
		tile.Parent = ScrambledBank

		buttonMap[tile] = letter
	end
end

-- Answer box: rebuild one slot Frame + ImageLabel per letter position.
local function renderAnswer()
	-- clear old slots
	for _, child in AnswerBox:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- ensure a horizontal layout exists
	if not AnswerBox:FindFirstChildOfClass("UIListLayout") then
		local listLayout = Instance.new("UIListLayout")
		listLayout.FillDirection = Enum.FillDirection.Horizontal
		listLayout.Padding = UDim.new(0, 6)
		listLayout.Parent = AnswerBox
	end

	for i = 1, wordLength do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.new(0, 48, 0, 48)
		slot.BackgroundColor3 = Color3.fromRGB(35, 40, 60)
		slot.BorderSizePixel = 2
		slot.BorderColor3 = Color3.fromRGB(120, 130, 160)
		slot.Parent = AnswerBox

		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(1, -8, 1, -8)
		img.Position = UDim2.new(0, 4, 0, 4)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		local ch = string.sub(currentGuess, i, i)
		if ch ~= "" then
			img.Image = LetterImages[ch] or ""
		elseif LetterImages.underscore then
			img.Image = LetterImages.underscore
		end
		img.Parent = slot
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
	renderAnswer()

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
		renderAnswer()
	end
end

-- CLICK: wire ScrambledBank tiles.
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
	renderAnswer()
	-- (Optionally display `images` in PuzzleArea.ImageGrid here.)
	PlayVsBotButton.Visible = false
end)

RoundEnd.OnClientEvent:Connect(function(result, correctWord)
	roundActive = false
	-- Reveal the word using letter images.
	wordLength = #correctWord
	currentGuess = correctWord
	renderAnswer()
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
