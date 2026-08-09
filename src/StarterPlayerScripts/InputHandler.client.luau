--[[
	InputHandler.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	RESPONSIBILITIES
	* Hybrid input:
	    - CLICK: clicking a letter button in PuzzleArea.ScrambledBank appends it.
	    - TYPE:  pressing a keyboard A-Z key appends that letter.
	    - BACKSPACE removes the last letter.
	    - SUBMIT: when the answer reaches the round's word length, it
	      automatically fires SubmitGuess to the server for validation.
	* Builds the ScrambledBank buttons dynamically each round (RoundStart).
	* Shows the PlayVsBot button when waiting, and fires PlayVsBotRequest.
	* Renders the letter/underscore preview in the AnswerBox.

	REQUIRED UI (see docs/UI_HIERARCHY.md) - must exist in StarterGui.GameUI:
		GameUI
		  ├── TopBar
		  │     └── TimerLabel (TextLabel)   -- shows 3..2..1 then round countdown
		  ├── PuzzleArea
		  │     ├── AnswerBox (TextBox)
		  │     └── ScrambledBank (Frame)
		  └── InteractionFrame
		        └── PlayVsBotButton (TextButton)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local SubmitGuess = Events:WaitForChild("SubmitGuess")
local RoundStart = Events:WaitForChild("RoundStart")
local RoundEnd = Events:WaitForChild("RoundEnd")
local Countdown = Events:WaitForChild("Countdown")
local TimerUpdate = Events:WaitForChild("TimerUpdate")
local GameOver = Events:WaitForChild("GameOver")
local OpponentState = Events:WaitForChild("OpponentState")
local PlayVsBotRequest = Events:WaitForChild("PlayVsBotRequest")

-- UI references (fail loudly if the hierarchy is wrong - easy to debug).
local GameUI = PlayerGui:WaitForChild("GameUI")
local TopBar = GameUI:WaitForChild("TopBar")
local TimerLabel = TopBar:WaitForChild("TimerLabel")
local PuzzleArea = GameUI:WaitForChild("PuzzleArea")
local AnswerBox = PuzzleArea:WaitForChild("AnswerBox")
local ScrambledBank = PuzzleArea:WaitForChild("ScrambledBank")
local InteractionFrame = GameUI:WaitForChild("InteractionFrame")
local PlayVsBotButton = InteractionFrame:WaitForChild("PlayVsBotButton")

-- The AnswerBox is rendered programmatically (letters + underscores), so it
-- must not accept manual text input that would fight the script's rendering.
AnswerBox.TextEditable = false

-------------------------------------------------------------------------------
-- UI VISIBILITY
-- NOTE: A Frame with Visible = false hides ALL of its children, regardless of
-- whether a child's own Visible is true. So if a frame was set Visible = false
-- in Studio, toggling a child does nothing. We therefore control the top-level
-- frames' Visible here based on game state. You can leave them Visible = false
-- in Studio; this script forces the right state at runtime.
-------------------------------------------------------------------------------
GameUI.Visible = true -- never want the whole screen hidden

local function setWaitingUI(waiting)
	-- Waiting-for-opponent state: only the "Play vs Bot" area is shown.
	TopBar.Visible = false
	PuzzleArea.Visible = false
	InteractionFrame.Visible = waiting
	PlayVsBotButton.Visible = waiting
end

local function setPlayingUI()
	-- Active match state: show the timer + puzzle, hide the interaction frame.
	TopBar.Visible = true
	PuzzleArea.Visible = true
	InteractionFrame.Visible = false
end

-------------------------------------------------------------------------------
-- STATE
-------------------------------------------------------------------------------
local wordLength = 0
local currentGuess = ""      -- letters typed so far
local buttonMap = {}         -- button -> letter
local roundActive = false

-- Start with everything hidden until the server says otherwise.
setWaitingUI(false)

local function resetBank()
	for _, child in ScrambledBank:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	buttonMap = {}
end

local function renderAnswer()
	-- Show filled letters + underscores, e.g. "_ _ a _".
	local parts = {}
	for i = 1, wordLength do
		local ch = string.sub(currentGuess, i, i)
		parts[i] = (ch ~= "") and ch or "_"
	end
	AnswerBox.Text = table.concat(parts, " ")
end

-------------------------------------------------------------------------------
-- BUILD SCRAMBLED BANK BUTTONS
-------------------------------------------------------------------------------
local function buildBank(letterBank)
	resetBank()

	-- Simple horizontal flow inside the bank frame.
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = ScrambledBank

	local xPos = 0
	for i, letter in letterBank do
		local button = Instance.new("TextButton")
		button.Name = "Letter" .. i
		button.Size = UDim2.new(0, 44, 0, 44)
		button.Position = UDim2.new(0, xPos, 0, 0)
		button.BackgroundColor3 = Color3.fromRGB(70, 90, 140)
		button.Text = letter:upper()
		button.Font = Enum.Font.GothamBold
		button.TextSize = 24
		button.TextColor3 = Color3.new(1, 1, 1)
		button.AutoButtonColor = true
		button.Parent = ScrambledBank

		buttonMap[button] = letter
		xPos = xPos + 44 + 8
	end
end

-------------------------------------------------------------------------------
-- INPUT
-------------------------------------------------------------------------------
-- Append a letter; used by both click and keyboard paths.
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

-- CLICK: wire ScrambledBank buttons.
ScrambledBank.ChildAdded:Connect(function(button)
	if not button:IsA("TextButton") then
		return
	end
	button.Activated:Connect(function()
		local letter = buttonMap[button]
		if letter then
			appendLetter(letter)
		end
	end)
end)

-- KEYBOARD: hybrid input (A-Z, Backspace, optional Enter to submit early).
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
			-- Manual early submit (optional).
			roundActive = false
			SubmitGuess:FireServer(currentGuess)
			return
		end
		local code = tostring(key)
		-- KeyCode names like "A", "B", ..., "Z" are single letters.
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
	AnswerBox.Text = ""
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
	if result == "correct" then
		AnswerBox.Text = correctWord:upper() .. "  ✓"
	else
		AnswerBox.Text = "Time's up! The word was " .. correctWord:upper()
	end
end)

GameOver.OnClientEvent:Connect(function(winnerName, youWon, isDraw)
	roundActive = false
	if isDraw then
		AnswerBox.Text = "Draw!"
	elseif youWon then
		AnswerBox.Text = "You Win!"
	else
		AnswerBox.Text = winnerName .. " Wins!"
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
