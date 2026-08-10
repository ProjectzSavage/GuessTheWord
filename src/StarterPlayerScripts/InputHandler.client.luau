--[[
	InputHandler.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	RESPONSIBILITIES
	* HYBRID INPUT:
	    - CLICK: clicking a letter tile animates it flying into the answer box.
	    - TYPE:  pressing a keyboard A-Z key appends that letter.
	    - BACKSPACE removes the last letter.
	    - SUBMIT: when the answer reaches the round's word length, it
	      automatically fires SubmitGuess to the server for validation.
	* SCRAMBLED BANK (12 letters): the server sends a 12-letter bank (the word's
	  letters + random fillers). Tiles are built from a "TileTemplate" ImageButton
	  inside a UIGridLayout (or programmatically if no template).
	* ANSWER BOX: one centered slot per letter. Empty slots show the underscore
	  image; filled slots show the letter image.
	* FLYING LETTER ANIMATION: clicking a tile flies a copy of it to the target
	  slot before the slot updates.
	* TOPBAR HEARTS: fills PlayerHeartContainer + OpponentHeartContainer from
	  HeartUpdate / OpponentHeartUpdate, animating the removed heart out.
	* ROUND FLOW: on a correct answer the server hides the PuzzleArea, then the
	  loser's heart leaves, then the next round reshores the puzzle.

	REQUIRED UI (see docs/UI_HIERARCHY.md) - must exist in StarterGui.GameUI:
		GameUI  (ScreenGui)
		  ├── TopBar  (Frame)
		  │     ├── OpponentHeartContainer (Folder)  Heart1/2/3 (ImageLabel)
		  │     ├── TimerLabel (TextLabel)
		  │     └── PlayerHeartContainer (Folder)    Heart1/2/3 (ImageLabel)
		  ├── PuzzleArea  (Frame)
		  │     ├── AnswerBox (Frame)
		  │     └── ScrambledBank (Frame)
		  │           ├── UIGridLayout  (optional, recommended)
		  │           └── TileTemplate  (ImageButton, optional, Visible=false)
		  └── InteractionFrame  (Frame)
		        └── PlayVsBotButton (TextButton)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Letter images (fill in your asset IDs here).
local LetterImages = require(ReplicatedStorage:WaitForChild("LetterImages"))
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))

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
local WrongGuess = Events:WaitForChild("WrongGuess")

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
-- Countdown frame (big 3-2-1-GO!) - built into the hierarchy by you.
local CountdownFrame = GameUI:FindFirstChild("CountdownFrame")
local CountdownLabel = CountdownFrame and CountdownFrame:FindFirstChild("CountdownLabel")

if AnswerBox:IsA("TextBox") then
	warn("[InputHandler] AnswerBox must be a Frame (it now renders ImageLabels), " ..
		"not a TextBox. See docs/UI_HIERARCHY.md.")
end

-------------------------------------------------------------------------------
-- UI VISIBILITY
-- GameUI is a ScreenGui -> uses .Enabled. Frames use .Visible.
-------------------------------------------------------------------------------
GameUI.Enabled = true

-- Visibility with open/close animations (via UIFX). These animate a UIScale, so
-- they don't reflow layout. We only animate frames we have references to; the
-- game still works if some are missing.
local function showFrame(gui)
	if gui and gui:IsA("GuiObject") then
		UIFX.popIn(gui)
	end
end

local function hideFrame(gui)
	if gui and gui:IsA("GuiObject") then
		UIFX.popOut(gui)
	end
end

-------------------------------------------------------------------------------
-- TOPBAR SLIDE ANIMATION
-- TopBar is anchored at its resting position (you set it, e.g. AnchorPoint
-- {0.5, 0} near the top). It slides DOWN→UP in, and UP→DOWN out.
-------------------------------------------------------------------------------
local topBarRestingPos = TopBar.Position
local TOPBAR_SLIDE = 220 -- px the bar travels when sliding in/out

local function slideTopBarIn()
	if TopBar.Visible and TopBar.Position == topBarRestingPos then
		return -- already shown at rest
	end
	TopBar.Visible = true
	-- Start below the resting spot, then glide up to rest.
	TopBar.Position = topBarRestingPos + UDim2.new(0, 0, 0, TOPBAR_SLIDE)
	TweenService:Create(
		TopBar,
		TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = topBarRestingPos }
	):Play()
end

local function slideTopBarOut()
	local endPos = topBarRestingPos + UDim2.new(0, 0, 0, TOPBAR_SLIDE)
	local t = TweenService:Create(
		TopBar,
		TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{ Position = endPos }
	)
	t:Play()
	t.Completed:Connect(function()
		TopBar.Visible = false
		TopBar.Position = topBarRestingPos
	end)
end

-------------------------------------------------------------------------------
-- COUNTDOWN FRAME (3-2-1-GO! pulse)
-------------------------------------------------------------------------------
local function showCountdown(text)
	if not CountdownFrame then
		return
	end
	CountdownFrame.Visible = true
	if CountdownLabel then
		CountdownLabel.Text = text
		local s = CountdownLabel:FindFirstChildOfClass("UIScale")
		if not s then
			s = Instance.new("UIScale")
			s.Parent = CountdownLabel
		end
		s.Scale = 0
		TweenService:Create(
			s,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
end

local function hideCountdown()
	if not CountdownFrame then
		return
	end
	CountdownFrame.Visible = false
end

local function setWaitingUI(waiting)
	hideCountdown()
	if waiting then
		showFrame(InteractionFrame)
		showFrame(PlayVsBotButton)
		hideFrame(PuzzleArea)
		slideTopBarOut()
	else
		hideFrame(InteractionFrame)
		hideFrame(PlayVsBotButton)
	end
end

-- Only show PuzzleArea + TopBar AFTER the countdown finishes.
local function revealRoundUI()
	hideCountdown()
	slideTopBarIn()
	showFrame(PuzzleArea)
	hideFrame(InteractionFrame)
end

local function showTopBarOnly()
	-- Used on correct answer / game over: keep the timer + hearts, hide the
	-- puzzle so everyone can watch the loser's heart blink out.
	hideCountdown()
	slideTopBarIn()
	PuzzleArea.Visible = false      -- immediate hide so the heart loss is visible
	hideFrame(InteractionFrame)
end

-------------------------------------------------------------------------------
-- STATE
-------------------------------------------------------------------------------
local wordLength = 0
local currentGuess = ""      -- letters typed so far
local buttonMap = {}         -- tile -> letter
local slots = {}             -- index -> ImageLabel slot
local usedTiles = {}         -- tiles already flown to the answer (grayed out)
local roundActive = false
local flyingLetters = {}     -- in-flight flying clones (for cleanup)

setWaitingUI(false) -- start hidden until the server says otherwise

local function clearFlying()
	for _, f in flyingLetters do
		if f and f.Parent then
			f:Destroy()
		end
	end
	flyingLetters = {}
end

-------------------------------------------------------------------------------
-- TOPBAR HEARTS
-------------------------------------------------------------------------------
-- Blink the heart (appear/disappear a few times) then fade it out and hide.
local function blinkHeartThenHide(heart)
	local us = heart:FindFirstChildOfClass("UIScale")
	if not us then
		us = Instance.new("UIScale")
		us.Scale = 1
		us.Parent = heart
	end

	local blinks = 3        -- how many times it appears/disappears
	local step = 0
	heart.Visible = true

	local function tick()
		step = step + 1
		if step <= blinks * 2 then
			heart.Visible = (step % 2 == 0)
			task.delay(0.12, tick)
		else
			-- Done blinking: shrink out.
			local t = TweenService:Create(
				us,
				TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Scale = 0 }
			)
			t:Play()
			t.Completed:Connect(function()
				heart.Visible = false
				us.Scale = 1
			end)
		end
	end
	tick()
end

local function setHeartsInContainer(container, count)
	count = math.clamp(count, 0, 3)
	for i = 1, 3 do
		local heart = container:FindFirstChild("Heart" .. i)
		if heart then
			if i <= count then
				heart.Visible = true
				local us = heart:FindFirstChildOfClass("UIScale")
				if us then
					us.Scale = 1
				end
			elseif heart.Visible then
				blinkHeartThenHide(heart)
			else
				heart.Visible = false
			end
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
-- SCRAMBLED BANK (12-letter tiles)
-------------------------------------------------------------------------------
local function buildBank(letterBank)
	clearFlying()
	for _, child in ScrambledBank:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "TileTemplate" then
			child:Destroy()
		end
	end
	buttonMap = {}
	usedTiles = {}

	-- Ensure a UIGridLayout exists (use the user's if they added one).
	if not ScrambledBank:FindFirstChildOfClass("UIGridLayout") then
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0, 44, 0, 44)
		grid.CellPadding = UDim2.new(0, 8, 0, 8)
		grid.Parent = ScrambledBank
	end

	local template = ScrambledBank:FindFirstChild("TileTemplate")
	if template and template:IsA("GuiButton") then
		template.Visible = false
	end

	for i, letter in letterBank do
		local tile
		if template then
			tile = template:Clone()
			tile.Visible = true
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

	-- Round-start intro: tiles cascade in one by one.
	local tiles = {}
	for _, child in ScrambledBank:GetChildren() do
		if child:IsA("ImageButton") then
			table.insert(tiles, child)
		end
	end
	UIFX.staggerIn(tiles, { duration = 0.24, stagger = 0.06 })
end

-------------------------------------------------------------------------------
-- ANSWER BOX (centered slots with underscore)
-- refreshSlots is declared BEFORE buildSlots (which calls it) to avoid the
-- Luau forward-reference gotcha where a `local function` used earlier than its
-- declaration silently becomes a global nil.
-------------------------------------------------------------------------------
local function refreshSlots()
	clearFlying()
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

local function buildSlots()
	clearFlying()
	for _, child in AnswerBox:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	slots = {}

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

-------------------------------------------------------------------------------
-- FLYING LETTER ANIMATION (bank tile -> answer slot)
-------------------------------------------------------------------------------
local function animateLetterToSlot(letter, fromTile, targetSlot)
	-- NOTE: We do NOT refreshSlots() here. currentGuess already includes this
	-- letter, but the target slot keeps showing the underscore until the flying
	-- tile lands, so you SEE the letter fly and land into the empty slot.
	local flying = Instance.new("ImageLabel")
	flying.Name = "FlyingLetter"
	flying.Image = LetterImages[letter] or ""
	flying.ScaleType = Enum.ScaleType.Fit
	flying.BackgroundTransparency = 1
	flying.Rotation = -12
	flying.ZIndex = 100

	local fromSize = fromTile.AbsoluteSize
	flying.Size = UDim2.fromOffset(fromSize.X, fromSize.Y)
	flying.Position = UDim2.fromOffset(fromTile.AbsolutePosition.X, fromTile.AbsolutePosition.Y)
	flying.Parent = GameUI
	table.insert(flyingLetters, flying)

	local tp = targetSlot.AbsolutePosition
	local tsz = targetSlot.AbsoluteSize
	local center = tp + (tsz - fromSize) / 2

	-- ImageLabel has no `Scale` property - use a UIScale child to scale it.
	local flyScale = Instance.new("UIScale")
	flyScale.Scale = 1
	flyScale.Parent = flying

	-- A quick "lift off" pop before the flight.
	local lift = TweenService:Create(
		flyScale,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1.2 }
	)
	lift:Play()

	local fly = TweenService:Create(
		flying,
		TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut),
		{
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(tsz.X, tsz.Y),
			Rotation = 0,
		}
	)
	fly:Play()
	fly.Completed:Connect(function()
		-- Land: settle the scale back to 1.
		if targetSlot then
			targetSlot.Image = LetterImages[letter] or ""
		end
		flying:Destroy()
		-- Gray out the source tile to show it was used (and disable it).
		if fromTile and fromTile.Parent then
			usedTiles[fromTile] = true
			fromTile.ImageColor3 = Color3.fromRGB(90, 90, 90)
			fromTile.ImageTransparency = 0.7
			fromTile.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
			fromTile.AutoButtonColor = false
		end
	end)
end

-------------------------------------------------------------------------------
-- INPUT
-------------------------------------------------------------------------------
local function tryAppend(letter)
	if not roundActive or wordLength == 0 then
		return nil
	end
	if #currentGuess >= wordLength then
		return nil
	end
	currentGuess = currentGuess .. letter
	return #currentGuess
end

local function checkAutoSubmit()
	if #currentGuess >= wordLength then
		roundActive = false -- lock input for this round
		task.delay(0.3, function()
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

-- CLICK: wire ScrambledBank tiles (fly the letter into the answer box).
ScrambledBank.ChildAdded:Connect(function(tile)
	if not tile:IsA("ImageButton") then
		return
	end
	tile.Activated:Connect(function()
		if usedTiles[tile] then
			return -- already used this round
		end
		local letter = buttonMap[tile]
		if not letter then
			return
		end
		local idx = tryAppend(letter)
		if idx then
			animateLetterToSlot(letter, tile, slots[idx])
			checkAutoSubmit()
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
				if tryAppend(ch) then
					refreshSlots()
					checkAutoSubmit()
				end
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- GAME EVENTS -> UI
-------------------------------------------------------------------------------
-- Pre-match 3..2..1 countdown. During the countdown, ONLY the CountdownFrame is
-- shown (big pulsing numbers). PuzzleArea/TopBar are revealed after it's done.
Countdown.OnClientEvent:Connect(function(n)
	hideFrame(PuzzleArea)
	slideTopBarOut()
	showCountdown(tostring(n))
end)

-- Round timer tick (15 -> 0).
TimerUpdate.OnClientEvent:Connect(function(seconds)
	TimerLabel.Text = tostring(seconds)
end)

RoundStart.OnClientEvent:Connect(function(length, letterBank, images)
	wordLength = length
	currentGuess = ""
	roundActive = true
	buildBank(letterBank)
	buildSlots()
	-- (Optionally display `images` in PuzzleArea.ImageGrid here.)
	PlayVsBotButton.Visible = false

	-- Flash "GO!" on the countdown frame, then reveal the round UI.
	showCountdown("GO!")
	task.delay(0.7, function()
		revealRoundUI()
	end)
end)

RoundEnd.OnClientEvent:Connect(function(result, correctWord)
	roundActive = false
	if result == "correct" then
		-- Correct answer: server hides the puzzle for the dramatic beat.
		showTopBarOnly()
	else
		-- Timeout: reveal the word (puzzle stays visible).
		wordLength = #correctWord
		currentGuess = correctWord
		buildSlots()
		TimerLabel.Text = "0"
	end
end)

-- Re-enable all used (grayed-out) tiles so the player can retry after a wrong
-- full-length guess.
local function resetTiles()
	for tile in pairs(usedTiles) do
		if tile and tile.Parent then
			tile.ImageColor3 = Color3.new(1, 1, 1)
			tile.ImageTransparency = 0
			tile.BackgroundColor3 = Color3.fromRGB(70, 90, 140)
			tile.AutoButtonColor = true
		end
	end
	usedTiles = {}
end

-- Wrong guess: shake the answer box, flash it red, reset the answer, and let
-- the player retry (the full-length submit had locked input).
WrongGuess.OnClientEvent:Connect(function()
	if not AnswerBox.Visible then
		return
	end
	-- Red flash via background color.
	AnswerBox.BackgroundColor3 = Color3.fromRGB(180, 40, 50)
	AnswerBox.BackgroundTransparency = 0.3
	TweenService:Create(
		AnswerBox,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()

	-- Horizontal shake.
	local basePos = AnswerBox.Position
	for i = 1, 3 do
		local dir = (i % 2 == 0) and -1 or 1
		task.delay(i * 0.05, function()
			if AnswerBox.Parent then
				AnswerBox.Position = basePos + UDim2.new(0, 8 * dir, 0, 0)
			end
		end)
	end
	task.delay(0.25, function()
		if AnswerBox.Parent then
			AnswerBox.Position = basePos
			AnswerBox.BackgroundColor3 = Color3.fromRGB(35, 40, 60)
			AnswerBox.BackgroundTransparency = 1
		end
	end)

	-- Reset the answer so the player can retry, and re-enable the tiles.
	task.delay(0.35, function()
		currentGuess = ""
		roundActive = true
		refreshSlots()
		resetTiles()
	end)
end)

GameOver.OnClientEvent:Connect(function(winnerName, youWon, isDraw)
	roundActive = false
	showTopBarOnly()
	if isDraw then
		TimerLabel.Text = "DRAW"
	elseif youWon then
		TimerLabel.Text = "WIN"
	else
		TimerLabel.Text = "LOSE"
	end
end)

OpponentState.OnClientEvent:Connect(function(waiting)
	setWaitingUI(waiting)
end)

-------------------------------------------------------------------------------
-- PLAY VS BOT BUTTON (immediate - no timer wait)
-------------------------------------------------------------------------------
PlayVsBotButton.Activated:Connect(function()
	-- Animate the button out, then ask the server to start a bot match.
	hideFrame(PlayVsBotButton)
	task.delay(0.15, function()
		PlayVsBotRequest:FireServer()
	end)
end)
