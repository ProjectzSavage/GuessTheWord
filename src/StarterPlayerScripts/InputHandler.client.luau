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

	REQUIRED UI (see docs/UI_HIERARCHY.md) - must exist in StarterGui:
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
		-- InteractionFrame moved out of GameUI (see below)
	NotificationInteractionGUI  (ScreenGui)  -- shares it with the notifications
		  └── Frame  (Frame)
		        ├── Holder  (Frame)           -- notifications (NotificationController)
		        └── InteractionFrame  (Frame)
		              └── PlayVsBotButton (TextButton)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Letter images (fill in your asset IDs here).
local LetterImages = require(ReplicatedStorage:WaitForChild("LetterImages"))
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))
local SFX = require(ReplicatedStorage:WaitForChild("SFX"))

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
local PowerupUse = Events:WaitForChild("PowerupUse")
local PowerupGrant = Events:WaitForChild("PowerupGrant")
local PurchasePowerup = Events:WaitForChild("PurchasePowerup")
local LeaveSeat = Events:WaitForChild("LeaveSeat")
local QuickPlayRequest = Events:WaitForChild("QuickPlayRequest")
local QuickPlayResult = Events:WaitForChild("QuickPlayResult")
local CashReroll = Events:WaitForChild("CashReroll")
local MatchCancelled = Events:WaitForChild("MatchCancelled")
local SpectatorGuess = Events:WaitForChild("SpectatorGuess")

-- UI references (fail loudly if the hierarchy is wrong - easy to debug).
local GameUI = PlayerGui:WaitForChild("GameUI")
local TopBar = GameUI:WaitForChild("TopBar")
local TimerLabel = TopBar:WaitForChild("TimerLabel")
local PlayerHeartContainer = TopBar:WaitForChild("PlayerHeartContainer")
local OpponentHeartContainer = TopBar:WaitForChild("OpponentHeartContainer")
local PuzzleArea = GameUI:WaitForChild("PuzzleArea")
local ImageGrid = PuzzleArea:FindFirstChild("ImageGrid")
local AnswerBox = PuzzleArea:WaitForChild("AnswerBox")
local ScrambledBank = PuzzleArea:WaitForChild("ScrambledBank")
-- Powerup frame inside PuzzleArea (built by you) with two buttons.
local PowerupFrame = PuzzleArea:FindFirstChild("PowerupFrame")
local RevealLetterBtn = PowerupFrame and PowerupFrame:FindFirstChild("RevealLetterBtn")
local RevealWordBtn = PowerupFrame and PowerupFrame:FindFirstChild("RevealWordBtn")
-- Each button has a PriceLbl inside it (shows "N Use" or the robux price).
local RevealLetterPrice = RevealLetterBtn and RevealLetterBtn:FindFirstChild("PriceLbl")
local RevealWordPrice = RevealWordBtn and RevealWordBtn:FindFirstChild("PriceLbl")

-- Placeholder robux prices (later the price comes from the product id directly).
local POWERUP_PRICE = { Letter = 10, Word = 25 }
-- The InteractionFrame was moved out of GameUI into the combined
-- NotificationInteractionGUI ScreenGui (Frame > InteractionFrame), which it
-- now shares with the notifications Holder. Tolerant lookup: old spot first,
-- then the new combined GUI (recursive, so the wrapper depth doesn't matter).
local function resolveInteractionFrame(): GuiObject?
	local function scan()
		local direct = GameUI:FindFirstChild("InteractionFrame")
		if direct and direct:IsA("GuiObject") then
			return direct :: GuiObject
		end
		local combined = PlayerGui:FindFirstChild("NotificationInteractionGUI")
		if combined then
			local found = combined:FindFirstChild("InteractionFrame", true)
			if found and found:IsA("GuiObject") then
				return found :: GuiObject
			end
		end
		return nil
	end
	local frame = scan()
	local startTime = os.clock()
	while not frame and (os.clock() - startTime) < 10 do
		frame = scan()
		task.wait(0.1)
	end
	return frame
end
local InteractionFrame = resolveInteractionFrame()
if not InteractionFrame then
	error("InputHandler: could not find InteractionFrame (checked GameUI and NotificationInteractionGUI)")
end
local PlayVsBotButton = InteractionFrame:WaitForChild("PlayVsBotButton")
-- Difficulty selector (inside InteractionFrame, shown when PlayVsBot is clicked).
local DifficultySelector = InteractionFrame:FindFirstChild("DifficultySelector")
-- Difficulty buttons live inside a nested "Difficulties" frame; use recursive
-- lookup so Easy/Medium/Hard are found regardless of the nesting.
local DifficultyEasy = DifficultySelector and DifficultySelector:FindFirstChild("EasyBtn", true)
local DifficultyMedium = DifficultySelector and DifficultySelector:FindFirstChild("MediumBtn", true)
local DifficultyHard = DifficultySelector and DifficultySelector:FindFirstChild("HardBtn", true)
local DifficultyClose = DifficultySelector and DifficultySelector:FindFirstChild("CloseBtn", true)
local DifficultyBack = DifficultySelector and DifficultySelector:FindFirstChild("BackBtn", true)
-- Quick play: a duplicate of PlayVsBotButton + a duplicate of the
-- DifficultySelector (QuickPlaySelector) with a "Mode" frame holding the two
-- mode buttons (Bot / Player).
local QuickPlayButton = InteractionFrame:FindFirstChild("QuickPlay")
local QuickPlaySelector = InteractionFrame:FindFirstChild("QuickPlaySelector")
local QuickModeFrame = QuickPlaySelector and QuickPlaySelector:FindFirstChild("Mode", true)

local function findQuickBtn(nameList)
	local root = QuickModeFrame or QuickPlaySelector
	if not root then
		return nil
	end
	for _, name in nameList do
		local btn = root:FindFirstChild(name, true)
		if btn and btn:IsA("GuiButton") then
			return btn
		end
	end
	return nil
end
local QuickBotBtn = findQuickBtn({ "Bot", "BotBtn", "BotButton" })
local QuickPlayerBtn = findQuickBtn({ "Player", "PlayerBtn", "PlayerButton" })
local QuickCloseBtn = QuickPlaySelector and QuickPlaySelector:FindFirstChild("CloseBtn", true)

-- QuickPlay is available at ALL TIMES — even right after joining, before
-- sitting at any table (that's the point: play immediately). It's hidden
-- during a match, while a selector is open, and while a GUI window (Shop /
-- Rewards / Inventory) is open — when a window opens the button SLIDES DOWN
-- out of the way, and slides back up when the window closes.
local quickStateVisible = false -- match/lobby state (see setQuickPlayVisible)
local quickGuiShifted = false   -- a GUI window is open (see _G.SetQuickPlayShiftedByGui)
local quickMatchStarting = false -- a QuickPlay Bot/Player match is in progress
local quickGen = 0              -- invalidates pending slide-out tweens
local quickRestingPos = QuickPlayButton and QuickPlayButton.Position or nil
local QUICK_SLIDE_OFFSET = UDim2.new(0, 0, 0.45, 0) -- screen fraction to slide down
local quickSeatHide = false -- seated: QuickPlay disappears instantly (no slide)

local function applyQuickPlayState()
	if not QuickPlayButton then
		return
	end
	-- quickMatchStarting: right after a QuickPlay Bot/Player pick, the seat
	-- event (OpponentState) tries to pop the waiting buttons back in - keep
	-- them down so they simply never reappear until the flow decides to.
	local want = quickStateVisible and not quickGuiShifted and not quickMatchStarting
	if QuickPlayButton.Visible == want then
		return
	end
	quickGen += 1
	local gen = quickGen
	if want then
		QuickPlayButton.Visible = true
		if quickRestingPos then
			QuickPlayButton.Position = quickRestingPos + QUICK_SLIDE_OFFSET
			TweenService:Create(
				QuickPlayButton,
				TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = quickRestingPos }
			):Play()
		end
	else
		if quickSeatHide then
			-- Seated: just disappear instantly (no slide animation).
			QuickPlayButton.Visible = false
			if quickRestingPos then
				QuickPlayButton.Position = quickRestingPos
			end
		elseif quickRestingPos then
			local t = TweenService:Create(
				QuickPlayButton,
				TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
				{ Position = quickRestingPos + QUICK_SLIDE_OFFSET }
			)
			t:Play()
			t.Completed:Connect(function()
				if gen == quickGen then
					QuickPlayButton.Visible = false
					QuickPlayButton.Position = quickRestingPos
				end
			end)
		else
			QuickPlayButton.Visible = false
		end
	end
end

-- `instant` = hide right away without the slide-down (used when seated:
-- the button should simply vanish, not animate).
local function setQuickPlayVisible(v, instant)
	if not QuickPlayButton then
		return
	end
	local selectorOpen = (QuickPlaySelector and QuickPlaySelector.Visible)
		or (DifficultySelector and DifficultySelector.Visible)
	local want = v and not selectorOpen
	if want ~= quickStateVisible then
		quickStateVisible = want
		quickSeatHide = (not want) and (instant and true or false) or false
		applyQuickPlayState()
	end
end

-- Called by UIFX on every window open/close transition: the button slides
-- down while a GUI window (Shop / Rewards / Inventory) is open, and back.
_G.SetQuickPlayShiftedByGui = function(shifted)
	quickGuiShifted = shifted and true or false
	applyQuickPlayState()
end
-- Countdown frame (big 3-2-1-GO!) - built into the hierarchy by you.
local CountdownFrame = GameUI:FindFirstChild("CountdownFrame")
local CountdownLabel = CountdownFrame and CountdownFrame:FindFirstChild("CountdownLabel")
-- Round timer bar (shrinks under the TimerLabel).
local TimerBar = TopBar:FindFirstChild("TimerBar")
local TimerFill = TimerBar and TimerBar:FindFirstChild("TimerFill")
-- Celebration overlay + text (built by you - the script only animates them).
local CelebrationOverlay = GameUI:FindFirstChild("CelebrationOverlay")
local CelebrationText = CelebrationOverlay and CelebrationOverlay:FindFirstChild("CelebrationText")
-- Pause / rematch overlay.
local PauseOverlay = GameUI:FindFirstChild("PauseOverlay")
local PauseLabel = PauseOverlay and PauseOverlay:FindFirstChild("PauseLabel")
local RematchButton = PauseOverlay and PauseOverlay:FindFirstChild("RematchButton")

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
	-- Skip frames that aren't actually visible: a blind popOut on every
	-- state change used to churn the old FX counter (and could flash a
	-- frame's scale while it was already hidden).
	if gui and gui:IsA("GuiObject") and gui.Visible then
		UIFX.popOut(gui)
	end
end

-------------------------------------------------------------------------------
-- TOPBAR SLIDE ANIMATION
-- TopBar is anchored at its resting position (you set it, e.g. AnchorPoint
-- {0.5, 0} near the top). It slides DOWN→UP in, and UP→DOWN out.
-------------------------------------------------------------------------------
local topBarRestingPos = TopBar.Position
-- Slide distance in SCALE (fraction of the screen height) so it looks the same
-- on every display size.
local TOPBAR_SLIDE_SCALE = 0.15

local function slideTopBarIn()
	if TopBar.Visible and TopBar.Position == topBarRestingPos then
		return -- already shown at rest
	end
	TopBar.Visible = true
	-- Start below the resting spot, then glide up to rest.
	TopBar.Position = topBarRestingPos + UDim2.new(0, 0, TOPBAR_SLIDE_SCALE, 0)
	TweenService:Create(
		TopBar,
		TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = topBarRestingPos }
	):Play()
end

local function slideTopBarOut()
	local endPos = topBarRestingPos + UDim2.new(0, 0, TOPBAR_SLIDE_SCALE, 0)
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
-- CINEMATIC EFFECT (background blur + FOV)
-- When the match is active, blur the background and smoothly raise the camera
-- FOV. Delegated to UIFX so the match cinematic and the window FX share ONE
-- derived state machine. (Two systems tweening the same camera/blur
-- independently was part of why the screen could get stuck blurred + zoomed:
-- whichever tween finished last won, and the result depended on timing.)
-------------------------------------------------------------------------------
local function setCinematic(level)
	UIFX.setCinematic(level)
end

-------------------------------------------------------------------------------
-- COUNTDOWN FRAME (3-2-1-GO! pulse + colors)
-------------------------------------------------------------------------------
local COUNTDOWN_COLORS = {
	["3"] = Color3.fromRGB(255, 60, 60),   -- red
	["2"] = Color3.fromRGB(255, 160, 50),  -- orange
	["1"] = Color3.fromRGB(255, 220, 60),  -- yellow
	["GO!"] = Color3.fromRGB(80, 255, 120), -- green
}

-- A cool pulsing countdown pop: the label scales in with an overshoot, then
-- "pulses" (bounces slightly) while on screen. Cinematic (blur+FOV) is active
-- during the countdown too.
local function showCountdown(text)
	if not CountdownFrame then
		return
	end
	CountdownFrame.Visible = true
	setCinematic(1)

	if CountdownLabel then
		CountdownLabel.Text = text
		CountdownLabel.TextColor3 = COUNTDOWN_COLORS[text] or Color3.new(1, 1, 1)
		local s = CountdownLabel:FindFirstChildOfClass("UIScale")
		if not s then
			s = Instance.new("UIScale")
			s.Parent = CountdownLabel
		end

		-- Pop in with a big overshoot.
		s.Scale = 0.3
		TweenService:Create(
			s,
			TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()

		-- Continuous gentle pulse while the number is on screen.
		local pulses = 2
		for i = 1, pulses do
			task.delay(0.4 * i, function()
				if CountdownLabel and CountdownLabel.Parent then
					local us = CountdownLabel:FindFirstChildOfClass("UIScale")
					if us then
						TweenService:Create(
							us,
							TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ Scale = 1.12 }
						):Play()
						task.delay(0.15, function()
							if us then
								TweenService:Create(
									us,
									TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
									{ Scale = 1 }
								):Play()
							end
						end)
					end
				end
			end)
		end
	end
end

local function hideCountdown()
	if not CountdownFrame then
		return
	end
	CountdownFrame.Visible = false
	-- NOTE: no setCinematic(false) here - the cinematic should persist through
	-- the countdown->round transition and only ease out at game end.
end

local function setWaitingUI(waiting)
	hideCountdown()
	if waiting then
		setCinematic(0)
		showFrame(InteractionFrame)
		-- Don't pop the waiting buttons in while a selector is open or a
		-- QuickPlay match is starting: a late OpponentState event (e.g. right
		-- after a QuickPlay teleport) used to bring PlayVsBot + QuickPlay back
		-- on top of the difficulty selector / in the middle of the flow.
		local selectorOpen = (QuickPlaySelector and QuickPlaySelector.Visible)
			or (DifficultySelector and DifficultySelector.Visible)
		if not selectorOpen and not quickMatchStarting then
			showFrame(PlayVsBotButton)
		end
		-- Seated + waiting (PlayVsBot is up): QuickPlay disappears INSTANTLY.
		-- It comes back in the lobby (stand up / leave the seat).
		setQuickPlayVisible(false, true)
		hideFrame(PuzzleArea)
		slideTopBarOut()
	else
		-- "Not waiting" means a match is starting/running — hide the whole
		-- frame. (Standing back up to the lobby is handled by enterLobby(),
		-- which keeps QuickPlay available.)
		hideFrame(InteractionFrame)
		hideFrame(PlayVsBotButton)
	end
end

-- Lobby state (not in a match): the interaction frame is up with QuickPlay
-- immediately available — no need to walk to a table and sit first. PlayVsBot
-- only makes sense when actually seated and waiting, so it stays hidden here.
local function enterLobby()
	if not InteractionFrame.Visible then
		showFrame(InteractionFrame)
	else
		local s = InteractionFrame:FindFirstChildOfClass("UIScale")
		if s then
			s.Scale = 1
		end
	end
	setQuickPlayVisible(true)
	if PlayVsBotButton and PlayVsBotButton.Visible then
		PlayVsBotButton.Visible = false
	end
end

-- Forward-declared here so revealRoundUI (below) can call it; it's defined
-- later in the file. Declared BEFORE use to satisfy the type checker.
local animateClueIntro

-- Only show PuzzleArea + TopBar AFTER the countdown finishes. This is also
-- where the puzzle's entrance animations play (now that it's actually visible).
local function revealRoundUI()
	hideCountdown()
	slideTopBarIn()
	showFrame(PuzzleArea)
	setCinematic(2) -- round in-play: FOV punches in further
	hideFrame(InteractionFrame)

	-- Tile cascade intro.
	local tiles = {}
	for _, child in ScrambledBank:GetChildren() do
		if child:IsA("ImageButton") then
			table.insert(tiles, child)
		end
	end
	UIFX.staggerIn(tiles, { duration = 0.24, stagger = 0.06 })

	-- Clue image pop/fade intro.
	animateClueIntro()

	-- GUI just popped up after the game started.
	SFX.play("uiPop")
end

local function showTopBarOnly()
	-- Used on correct answer / game over: keep the timer + hearts, hide the
	-- puzzle so everyone can watch the loser's heart blink out.
	hideCountdown()
	slideTopBarIn()
	PuzzleArea.Visible = false      -- immediate hide so the heart loss is visible
	setCinematic(0)
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
local matchInProgress = false -- true during an active match (jump locked)
local flyingLetters = {}     -- in-flight flying clones (for cleanup)

-- Forward declarations for helpers that are CALLED early (by the Countdown
-- handler) but DEFINED later in the file.
local lockJump, getHumanoid, onLeftSeat, setupCharacterJump

-- Spawn state: lobby. QuickPlay is available immediately when you join (no
-- need to walk to a table and sit first); PlayVsBot stays hidden until
-- actually seated.
hideCountdown()
enterLobby()

-- The PuzzleArea behaves like an OPEN WINDOW for the environment FX: the
-- moment it pops in (after the money roll, when the round UI appears) the
-- StatsPanel slides up and the DailyQuestsF collapses — exactly the same
-- reaction as opening the Shop — and everything eases back when the puzzle
-- hides (correct answer / game over).
UIFX.registerWindow(PuzzleArea)
hideFrame(PuzzleArea) -- never start from a lingering puzzle (Studio default)

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
		-- Scale-based so the 12 tiles lay out correctly on any screen size.
		grid.CellSize = UDim2.new(0.16, 0, 0.3, 0)
		grid.CellPadding = UDim2.new(0.02, 0, 0.04, 0)
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

	-- NOTE: tile cascade intro is triggered in revealRoundUI() (after the
	-- puzzle is actually visible), not here - otherwise it plays while hidden.
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

-- Live typing feed for spectators: the server stores this and re-broadcasts
-- the table's state to everyone (so other tables' spectators see it in real
-- time). Only send during an actual match.
local function pushLiveGuess()
	if matchInProgress then
		SpectatorGuess:FireServer(currentGuess)
	end
end

-- Restore a used bank tile matching `letter` (un-gray it) so it can be reused.
local function restoreTileFor(letter)
	for tile, l in pairs(buttonMap) do
		if l == letter and usedTiles[tile] then
			usedTiles[tile] = nil
			tile.ImageColor3 = Color3.new(1, 1, 1)
			tile.ImageTransparency = 0
			tile.BackgroundColor3 = Color3.fromRGB(70, 90, 140)
			tile.AutoButtonColor = true
			return tile
		end
	end
	return nil
end

-- Fly a copy of the letter from an answer slot BACK to the bank.
local function flyLetterBack(letter, fromSlot, toTile)
	local flying = Instance.new("ImageLabel")
	flying.Name = "FlyingLetter"
	flying.Image = LetterImages[letter] or ""
	flying.ScaleType = Enum.ScaleType.Fit
	flying.BackgroundTransparency = 1
	flying.ZIndex = 100

	local fromSize = fromSlot.AbsoluteSize
	flying.Size = UDim2.fromOffset(fromSize.X, fromSize.Y)
	flying.Position = UDim2.fromOffset(fromSlot.AbsolutePosition.X, fromSlot.AbsolutePosition.Y)
	flying.Parent = GameUI
	table.insert(flyingLetters, flying)

	-- Target: the restored tile, or the ScrambledBank center.
	local tx, ty, tsz
	if toTile and toTile.Parent then
		local tp = toTile.AbsolutePosition
		tsz = toTile.AbsoluteSize
		tx, ty = tp.X, tp.Y
	else
		local bp = ScrambledBank.AbsolutePosition
		tsz = fromSize
		tx = bp.X + ScrambledBank.AbsoluteSize.X / 2 - fromSize.X / 2
		ty = bp.Y + ScrambledBank.AbsoluteSize.Y / 2 - fromSize.Y / 2
	end

	local fly = TweenService:Create(
		flying,
		TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut),
		{
			Position = UDim2.fromOffset(tx, ty),
			Size = UDim2.fromOffset(tsz.X, tsz.Y),
			Rotation = -12,
		}
	)
	fly:Play()
	fly.Completed:Connect(function()
		flying:Destroy()
	end)
end

-- Remove the letter at `index` in the answer, sending it back to the bank.
local function removeLetterAt(index)
	if not roundActive or index < 1 or index > wordLength then
		return
	end
	local ch = string.sub(currentGuess, index, index)
	if ch == "" then
		return
	end
	currentGuess = string.sub(currentGuess, 1, index - 1) .. string.sub(currentGuess, index + 1)
	local fromSlot = slots[index]
	local toTile = restoreTileFor(ch)
	if fromSlot then
		flyLetterBack(ch, fromSlot, toTile)
	end
	refreshSlots()
	pushLiveGuess()
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
		-- Use an ImageButton so the player can CLICK a placed letter to send it
		-- back to the bank (with a fly-back animation).
		-- SIZED IN SCALE (relative to the AnswerBox) so it looks right on every
		-- device, including mobile.
		local slot = Instance.new("ImageButton")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.new(0.09, 0, 0.7, 0)
		slot.BackgroundTransparency = 1
		slot.ScaleType = Enum.ScaleType.Fit
		slot.Image = LetterImages.underscore or ""
		slot.Parent = AnswerBox
		slots[i] = slot

		slot.Activated:Connect(function()
			removeLetterAt(i)
		end)
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
	SFX.play("letter")
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
		-- Only bank tiles get grayed; powerup buttons are not in buttonMap.
		if fromTile and fromTile.Parent and buttonMap[fromTile] then
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
	pushLiveGuess()
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

-------------------------------------------------------------------------------
-- POWERUPS (Reveal Letter / Reveal Word)
-- The server validates the powerup use and reveals the correct letter/word.
-------------------------------------------------------------------------------
-- Find an unused (not already placed) bank tile matching `letter`, if any.
-- This lets powerup reveals animate from the bank like the player chose it.
local function findBankTile(letter)
	for tile, l in pairs(buttonMap) do
		if l == letter and not usedTiles[tile] then
			return tile
		end
	end
	return nil
end

-- Set a character of currentGuess at a specific 1-based index.
local function setGuessAt(index, ch)
	if index < 1 or index > wordLength then
		return
	end
	currentGuess = string.sub(currentGuess, 1, index - 1)
		.. ch
		.. string.sub(currentGuess, index + 1)
	pushLiveGuess()
end

-- Place a revealed letter at its CORRECT index, animating from a matching bank
-- tile (exactly as if the player clicked that letter themselves).
local function placeRevealedLetter(letter, index)
	if not roundActive then
		return
	end
	if index == nil or index < 1 or index > wordLength then
		-- fallback: next empty slot
		index = #currentGuess + 1
	end
	setGuessAt(index, letter)
	local tile = findBankTile(letter)
	if tile and slots[index] then
		animateLetterToSlot(letter, tile, slots[index])
	else
		refreshSlots()
	end
	checkAutoSubmit()
end

-- Place the full revealed word, one letter at a time (fast but sequential),
-- each animated from a matching bank tile like the player chose it.
local function placeRevealedWord(word)
	if not roundActive then
		return
	end
	roundActive = false -- lock input during the reveal
	for i = 1, #word do
		local ch = string.sub(word, i, i)
		local tile = findBankTile(ch)
		task.delay((i - 1) * 0.18, function()
			if not roundActive then
				-- word reveal keeps running even though we locked input
			end
			setGuessAt(i, ch)
			if tile and slots[i] then
				animateLetterToSlot(ch, tile, slots[i])
			else
				local s = slots[i]
				if s then
					s.Image = LetterImages[ch] or ""
				end
			end
		end)
	end
	-- After all letters placed, submit.
	task.delay(#word * 0.18 + 0.3, function()
		roundActive = false
		SubmitGuess:FireServer(word)
	end)
end

-- Robux purchase prompt (placeholder - you build BuyPrompt in the hierarchy).
local BuyPrompt = GameUI:FindFirstChild("BuyPrompt")
local BuyMsg = BuyPrompt and BuyPrompt:FindFirstChild("BuyMsg")
local BuyConfirm = BuyPrompt and BuyPrompt:FindFirstChild("BuyConfirm")
local BuyCancel = BuyPrompt and BuyPrompt:FindFirstChild("BuyCancel")
local pendingBuyType = nil

local function promptBuy(powerupType)
	if not BuyPrompt then
		-- No BuyPrompt built in the hierarchy: no "no uses left" dialog -
		-- go straight to the real Robux purchase prompt.
		SFX.play("robuxClick")
		PurchasePowerup:FireServer(powerupType)
		return
	end
	pendingBuyType = powerupType
	BuyPrompt.Visible = true
	if BuyMsg then
		BuyMsg.Text = "Buy " .. (powerupType == "Word" and "Reveal Word" or "Reveal Letter")
			.. " for Robux?"
	end
end

local function closeBuy()
	if BuyPrompt then
		BuyPrompt.Visible = false
	end
	pendingBuyType = nil
end

-- Read a player's powerup-use count.
local function getPowerupUses(useName)
	local stats = player:FindFirstChild("Stats")
	local val = stats and stats:FindFirstChild(useName)
	return val and val.Value or 0
end

-- Update each powerup button's PriceLbl: show "N Use" when the player has uses,
-- otherwise show the robux price (placeholder; later from the product id).
local function updatePowerupPrices()
	local letterUses = getPowerupUses("RevealLetterUses")
	local wordUses = getPowerupUses("RevealWordUses")
	if RevealLetterPrice then
		RevealLetterPrice.Text = letterUses > 0 and (letterUses .. " Use") or ("R$" .. (POWERUP_PRICE.Letter or 0))
	end
	if RevealWordPrice then
		RevealWordPrice.Text = wordUses > 0 and (wordUses .. " Use") or ("R$" .. (POWERUP_PRICE.Word or 0))
	end
end

-- Update prices when the player's uses change (rewards grant / purchases).
local function watchUses(useName)
	local stats = player:FindFirstChild("Stats")
	local val = stats and stats:FindFirstChild(useName)
	if val then
		val.Changed:Connect(updatePowerupPrices)
	end
end
watchUses("RevealLetterUses")
watchUses("RevealWordUses")
updatePowerupPrices()

-- The R$ fallback on the price labels comes from the REAL 1-use dev products
-- (RevealL1 / RevealW1), fetched on load so it always matches Creator Hub.
local POWERUP_PRODUCT_IDS = { Letter = 3709926777, Word = 3709926691 }
task.spawn(function()
	for _, typeName in ipairs({ "Letter", "Word" }) do
		local id = POWERUP_PRODUCT_IDS[typeName]
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" then
			-- PriceInRobux / Price are ALREADY in Robux (not cents).
			local price = tonumber(info.PriceInRobux) or tonumber(info.Price)
			if price then
				POWERUP_PRICE[typeName] = math.floor(price)
			end
		end
	end
	updatePowerupPrices()
end)

-- Handle server responses for powerups.
PowerupGrant.OnClientEvent:Connect(function(powerupType, success, letter, index, word)
	if not success then
		-- No uses left -> prompt to buy with robux (future: real purchase).
		promptBuy(powerupType)
		return
	end
	if powerupType == "Letter" and typeof(letter) == "string" then
		placeRevealedLetter(letter, index)
	elseif powerupType == "Word" and typeof(word) == "string" then
		placeRevealedWord(word)
	end
	updatePowerupPrices()
end)

if BuyConfirm then
	BuyConfirm.Activated:Connect(function()
		if pendingBuyType then
			SFX.play("robuxClick")
			PurchasePowerup:FireServer(pendingBuyType)
		end
		closeBuy()
	end)
end
if BuyCancel then
	BuyCancel.Activated:Connect(function()
		closeBuy()
	end)
end

-- Wire the powerup buttons.
if RevealLetterBtn then
	RevealLetterBtn.Activated:Connect(function()
		PowerupUse:FireServer("Letter")
	end)
end
if RevealWordBtn then
	RevealWordBtn.Activated:Connect(function()
		PowerupUse:FireServer("Word")
	end)
end

local function backspace()
	if not roundActive then
		return
	end
	if #currentGuess > 0 then
		currentGuess = string.sub(currentGuess, 1, -2)
		refreshSlots()
		pushLiveGuess()
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

-- Show the pause / rematch screen after the celebration (only for bot
-- matches). Whether the player jumped out during the celebration is decided
-- by the CALLER via leftSeatAfterMatch (the live Seated state at that moment
-- is not reliable - end-of-match seat handling can disturb it).
local function showPauseScreen()
	if not PauseOverlay then
		return
	end
	PauseOverlay.Visible = true
	if PauseLabel then
		PauseLabel.Visible = true
	end
	if RematchButton then
		RematchButton.Visible = true
		UIFX.popIn(RematchButton)
	end
end

local function hidePauseScreen()
	if not PauseOverlay then
		return
	end
	PauseOverlay.Visible = false
	if PauseLabel then
		PauseLabel.Visible = false
	end
	if RematchButton then
		RematchButton.Visible = false
	end
end

-------------------------------------------------------------------------------
-- JUMP LOCK + SEAT EXIT
-- During a match the player can't jump out of their chair. Before/after a match
-- they can; when they leave the seat the relevant UI (bot toggle / pause)
-- outros cleanly.
-------------------------------------------------------------------------------
local playerHumanoid = nil

-- True while the win/lose celebration is playing (set in showCelebration).
-- Declared up here so onLeftSeat (below) can reference it.
local celebrationActive = false
-- Set when the local player jumps out of the seat DURING the celebration.
-- In that case the "Play again" pause screen must NOT appear after the
-- celebration ends - the player already chose to walk away.
local leftSeatAfterMatch = false

function getHumanoid()
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

function lockJump(locked)
	local h = getHumanoid()
	if h then
		h:SetStateEnabled(Enum.HumanoidStateType.Jumping, not locked)
	end
end

-- Handle the local player leaving their seat.
function onLeftSeat()
	if matchInProgress then
		-- Shouldn't happen (jump is locked), but re-seat defensively.
		local h = getHumanoid()
		if h then
			h.Sit = true
		end
		return
	end
	-- Left the seat during the win celebration? Remember it - the
	-- "Play again" pause screen must not appear after the celebration.
	if celebrationActive then
		leftSeatAfterMatch = true
	end
	-- Not in a match: back to the lobby - pause overlay out, QuickPlay
	-- immediately available again.
	hidePauseScreen()
	enterLobby()
end

function setupCharacterJump(char)
	local h = char:WaitForChild("Humanoid", 5)
	if not h then
		return
	end
	playerHumanoid = h
	h.Seated:Connect(function(seated)
		if not seated then
			onLeftSeat()
		end
	end)
end

-- Watch for the character (re)spawning so we can re-apply the jump lock.
player.CharacterAdded:Connect(function(char)
	setupCharacterJump(char)
end)
if player.Character then
	setupCharacterJump(player.Character)
end

-- Rematch button: re-open the difficulty selector so the player can pick the
-- difficulty again (including switching).
if RematchButton then
	RematchButton.Activated:Connect(function()
		hidePauseScreen()
		setQuickPlayVisible(false)
		if DifficultySelector then
			-- The selector lives inside InteractionFrame, so show that too.
			showFrame(InteractionFrame)
			DifficultySelector.Visible = true
			UIFX.popIn(DifficultySelector)
		else
			-- No selector built -> start a default bot match directly.
			PlayVsBotRequest:FireServer("Easy")
		end
	end)
end

Countdown.OnClientEvent:Connect(function(n)
	hidePauseScreen()
	hideFrame(PuzzleArea)
	setQuickPlayVisible(false) -- a match is starting
	slideTopBarOut()
	showCountdown(tostring(n))
	-- Player can still jump out of the chair during the countdown; the jump is
	-- locked when the actual round starts (RoundStart).
end)

-- Round timer tick (15 -> 0). Also shrinks the TimerBar fill.
local timerMax = 0
TimerUpdate.OnClientEvent:Connect(function(seconds)
	seconds = seconds or 0
	TimerLabel.Text = tostring(seconds)
	if seconds > timerMax then
		timerMax = seconds
	end
	if TimerFill then
		local frac = (timerMax > 0) and (seconds / timerMax) or 0
		-- Force left-anchor so the fill depletes right→left cleanly, no
		-- matter how it was positioned in Studio.
		TimerFill.AnchorPoint = Vector2.new(0, 0.5)
		TimerFill.Position = UDim2.new(0, 0, 0.5, 0)
		TimerFill.Size = UDim2.new(frac, 0, 1, 0)
		-- Color shift: green -> yellow -> red as time runs out.
		TimerFill.BackgroundColor3 = Color3.fromHSV(frac * 0.33, 1, 0.85)
	end
end)

-- The clue images for the current round (shown with an intro on reveal).
local pendingClueImages = {}

-- Set the 4 clue images in ImageGrid (no animation - just assign).
local function setClueImages(images)
	pendingClueImages = type(images) == "table" and images or {}
	if not ImageGrid then
		return
	end
	for i = 1, 4 do
		local clue = ImageGrid:FindFirstChild("Clue" .. i)
		if clue and clue:IsA("ImageLabel") then
			clue.Image = pendingClueImages[i] or ""
		end
	end
end

-- Staggered pop/fade-in for the clue images (called on reveal, so it's visible).
function animateClueIntro()
	if not ImageGrid then
		return
	end
	for i = 1, 4 do
		local clue = ImageGrid:FindFirstChild("Clue" .. i)
		if clue and clue:IsA("ImageLabel") then
			local us = clue:FindFirstChildOfClass("UIScale")
			if not us then
				us = Instance.new("UIScale")
				us.Parent = clue
			end
			clue.ImageTransparency = 1
			us.Scale = 0
			task.delay(0.12 * i, function()
				if clue and clue.Parent then
					TweenService:Create(
						clue,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ ImageTransparency = 0 }
					):Play()
					TweenService:Create(
						us,
						TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = 1 }
					):Play()
				end
			end)
		end
	end
end

RoundStart.OnClientEvent:Connect(function(length, letterBank, images)
	wordLength = length
	currentGuess = ""
	pushLiveGuess() -- clear the spectator's view of our guess for the new round
	roundActive = true
	timerMax = 0
	-- The round is now live: lock the player into their chair.
	matchInProgress = true
	lockJump(true)
	buildBank(letterBank)
	buildSlots()
	setClueImages(images) -- show the 4 clue images for this word
	PlayVsBotButton.Visible = false

	-- Flash "GO!" on the countdown frame, then reveal the round UI.
	showCountdown("GO!")
	task.delay(0.7, function()
		revealRoundUI()
	end)
end)

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(120, 220, 90),
	Color3.fromRGB(90, 160, 255),
	Color3.fromRGB(200, 120, 255),
	Color3.fromRGB(255, 120, 200),
}

-- A single confetti piece. Parented directly to the ScreenGui (GameUI) so the
-- offset coordinates match the actual screen space (Camera.ViewportSize),
-- keeping the burst centered regardless of the overlay frame's position/size.
local function makeConfetti(x, y, size)
	local piece = Instance.new("ImageLabel")
	piece.Size = UDim2.fromOffset(size or 12, size or 12)
	piece.BackgroundColor3 = CONFETTI_COLORS[(math.random(1, #CONFETTI_COLORS))]
	piece.BackgroundTransparency = 0.1
	piece.Rotation = math.random(0, 360)
	piece.ZIndex = 100
	piece.Position = UDim2.fromOffset(x, y)
	piece.Parent = GameUI
	return piece
end

-- A small confetti "burst" from the center of the screen (used on correct answer).
local function confettiBurst(count)
	local overlay = GameUI:FindFirstChild("CelebrationOverlay")
	if not overlay or not Camera then
		return
	end
	local w = math.max(Camera.ViewportSize.X, 1)
	local h = math.max(Camera.ViewportSize.Y, 1)
	local cx = w / 2
	local cy = h / 2
	for i = 1, count do
		local piece = makeConfetti(cx - 6, cy - 6, 10)
		if piece then
			local ang = math.rad(math.random(0, 360))
			local dist = math.random(120, 320)
			local tx = cx + math.cos(ang) * dist
			local ty = cy + math.sin(ang) * dist + math.random(-20, 40) -- fall after burst
			local t = TweenService:Create(
				piece,
				TweenInfo.new(math.random(6, 9) / 10, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(tx, ty), Rotation = piece.Rotation + math.random(180, 360) }
			)
			t:Play()
			t.Completed:Connect(function()
				-- Fade the piece out before removing it (smooth disappearance).
				local fade = TweenService:Create(
					piece,
					TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
					{ ImageTransparency = 1, BackgroundTransparency = 1 }
				)
				fade:Play()
				fade.Completed:Connect(function()
					if piece then
						piece:Destroy()
					end
				end)
			end)
		end
	end
end

RoundEnd.OnClientEvent:Connect(function(result, correctWord)
	roundActive = false
	if result == "correct" then
		-- Correct answer: server hides the puzzle for the dramatic beat, and a
		-- small confetti burst pops from the center.
		confettiBurst(30)
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

-------------------------------------------------------------------------------
-- WIN / LOSE CELEBRATION
-------------------------------------------------------------------------------
local function shakeCamera(intensity, duration)
	if not Camera then
		return
	end
	local base = Camera.CFrame
	local steps = math.floor(duration / 0.05)
	for i = 1, steps do
		task.delay(i * 0.05, function()
			if Camera and Camera.Parent then
				local dx = (math.random() * 2 - 1) * intensity
				local dy = (math.random() * 2 - 1) * intensity
				Camera.CFrame = base * CFrame.new(dx, dy, 0)
			end
		end)
	end
	task.delay(duration, function()
		if Camera and Camera.Parent then
			Camera.CFrame = base
		end
	end)
end

-- Rainbow the text label's color for `duration` seconds.
local function rainbowText(label, duration)
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < duration do
			local t = (os.clock() - start) / duration
			local hue = (t * 360) % 360
			if label and label.Parent then
				label.TextColor3 = Color3.fromHSV(hue / 360, 1, 1)
			end
			task.wait(0.03)
		end
		if label and label.Parent then
			label.TextColor3 = Color3.new(1, 1, 1)
		end
	end)
end

-- Rain confetti from the top across the FULL screen width, centered.
local function spawnConfetti(count)
	local overlay = GameUI:FindFirstChild("CelebrationOverlay")
	if not overlay or not Camera then
		return
	end
	local w = math.max(Camera.ViewportSize.X, 1)
	local h = math.max(Camera.ViewportSize.Y, 1)
	for i = 1, count do
		local piece = makeConfetti(math.random(-20, w + 20), math.random(-120, -20))
		if piece then
			local fall = TweenService:Create(
				piece,
				TweenInfo.new(math.random(1, 2), Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(math.random(-20, w + 20), h + 40), Rotation = piece.Rotation + 360 }
			)
			fall:Play()
			task.delay(2.4, function()
				if piece then
					piece:Destroy()
				end
			end)
		end
	end
end


-- Slide a heart container's hearts off the screen (left or right) at game end.
local function animateHeartsAway(container, dir)
	if not container then
		return
	end
	for i = 1, 3 do
		local heart = container:FindFirstChild("Heart" .. i)
		if heart and heart.Visible then
			local base = heart.Position
			local t = TweenService:Create(
				heart,
				TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Position = base + UDim2.new(0, 140 * dir, 0, 0) }
			)
			t:Play()
			t.Completed:Connect(function()
				heart.Visible = false
				heart.Position = base
			end)
		end
	end
end



local function showCelebration(youWon, isDraw, isBotMatch)
	if celebrationActive then
		return
	end
	celebrationActive = true
	showTopBarOnly()

	-- The overlay + text are BUILT BY YOU in the hierarchy. The script only
	-- animates them.
	if CelebrationOverlay then
		CelebrationOverlay.Visible = true
	end
	if not CelebrationText then
		celebrationActive = false
		return
	end

	local message = isDraw and "DRAW!" or (youWon and "YOU WON!" or "LOSER")

	-- On a win, show the current streak ("YOU WON! — Streak ×3 🔥").
	-- Streak lives in the hidden "Stats" folder (not on the leaderboard).
	if youWon and not isDraw then
		local stats = player:FindFirstChild("Stats")
		local streak = stats and stats:FindFirstChild("Streak")
		if streak and streak.Value > 0 then
			message = message .. "\nStreak ×" .. streak.Value .. " 🔥"
		end
	end

	CelebrationText.Text = message
	CelebrationText.Visible = true

	-- Animate the TopBar hearts sliding away (player left, opponent right).
	animateHeartsAway(PlayerHeartContainer, -1)
	animateHeartsAway(OpponentHeartContainer, 1)

	-- Entrance pop.
	local us = CelebrationText:FindFirstChildOfClass("UIScale")
	if not us then
		us = Instance.new("UIScale")
		us.Parent = CelebrationText
	end
	us.Scale = 0
	TweenService:Create(
		us,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	if youWon and not isDraw then
		-- WIN: rainbow text, confetti, screen shake (while confetti falls), FOV.
		-- The FOV punch goes through the shared FX state (a temporary boost),
		-- so it merges with any window/match cinematic and always comes back.
		rainbowText(CelebrationText, 2.5)
		spawnConfetti(70)
		shakeCamera(2.6, 2.4) -- aggressive win shake, lasts while confetti falls
		UIFX.setFovBoost(14)
		task.delay(1.2, function()
			UIFX.setFovBoost(0)
		end)
	elseif isDraw then
		shakeCamera(0.5, 0.4)
	else
		-- LOSE: smaller shake.
		shakeCamera(0.6, 0.4)
		CelebrationText.TextColor3 = Color3.fromRGB(220, 60, 60)
	end

	-- Let it play, then hide the overlay, slide the TopBar out, and show the
	-- pause screen (if it was a bot match).
	task.delay(3, function()
		celebrationActive = false
		if CelebrationOverlay then
			CelebrationOverlay.Visible = false
		end
		CelebrationText.Visible = false
		CelebrationText.TextColor3 = Color3.new(1, 1, 1)
		slideTopBarOut()
		setCinematic(0)
		if isBotMatch and youWon and not isDraw and not leftSeatAfterMatch then
			-- Winner is still in the chair: "Play vs Bot again" pause screen.
			-- If they jumped out DURING the celebration, leftSeatAfterMatch
			-- is set (by onLeftSeat) and they go straight back to the lobby.
			showPauseScreen()
		else
			-- Loser (their character was just respawned back to spawn) or a
			-- human match: no pause overlay, no PlayVsBot — straight back to
			-- the lobby so QuickPlay is immediately available.
			enterLobby()
		end
	end)
end

GameOver.OnClientEvent:Connect(function(winnerName, youWon, isDraw, isBotMatch)
	roundActive = false
	matchInProgress = false -- allow the player to jump out again
	leftSeatAfterMatch = false -- reset for this match's celebration
	lockJump(false)
	setQuickPlayVisible(false) -- match just ended; re-shown via enterLobby/waiting
	showCelebration(youWon, isDraw, isBotMatch)
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

-- Match cancelled (someone left during the countdown): full reset for the
-- local player — camera release is handled by CameraController on the same
-- event; here we restore the lobby UI.
MatchCancelled.OnClientEvent:Connect(function()
	roundActive = false
	matchInProgress = false
	celebrationActive = false
	lockJump(false)
	hidePauseScreen()
	if CelebrationOverlay then
		CelebrationOverlay.Visible = false
	end
	if CelebrationText then
		CelebrationText.Visible = false
	end
	hideCountdown()
	hideFrame(PuzzleArea)
	slideTopBarOut()
	setCinematic(0)
	enterLobby()
end)

-- Countdown is over and the cash roll is playing: the match is committed, so
-- the player can no longer bail out of the chair by jumping. (RoundStart
-- re-locks too, but the roll plays BEFORE the round starts.)
CashReroll.OnClientEvent:Connect(function()
	lockJump(true)
end)

-------------------------------------------------------------------------------
-- PLAY VS BOT + DIFFICULTY SELECTOR
-------------------------------------------------------------------------------
-- Clicking PlayVsBot opens the difficulty selector (Easy/Medium/Hard + Close).
PlayVsBotButton.Activated:Connect(function()
	SFX.play("click")
	hideFrame(PlayVsBotButton)
	hideFrame(QuickPlaySelector) -- never show both selectors at once
	setQuickPlayVisible(false)
	task.delay(0.1, function()
		if DifficultySelector then
			DifficultySelector.Visible = true
			UIFX.popIn(DifficultySelector)
		else
			-- No selector built -> start a default bot match directly.
			PlayVsBotRequest:FireServer("Easy")
		end
	end)
end)

local function startBotWithDifficulty(diff)
	if DifficultySelector then
		DifficultySelector.Visible = false
	end
	setQuickPlayVisible(false)
	PlayVsBotRequest:FireServer(diff)
end

if DifficultyEasy then
	DifficultyEasy.Activated:Connect(function()
		startBotWithDifficulty("Easy")
	end)
end
if DifficultyMedium then
	DifficultyMedium.Activated:Connect(function()
		startBotWithDifficulty("Medium")
	end)
end
if DifficultyHard then
	DifficultyHard.Activated:Connect(function()
		startBotWithDifficulty("Hard")
	end)
end
-- Back button returns to the PlayVsBot button (optional).
if DifficultyBack then
	DifficultyBack.Activated:Connect(function()
		if DifficultySelector then
			DifficultySelector.Visible = false
		end
		showFrame(PlayVsBotButton)
		-- Seated + waiting: QuickPlay stays down (it comes back in the lobby).
		setQuickPlayVisible(false)
	end)
end
-- Close button: leave the chair and cancel (game never started). Standing up
-- fires onLeftSeat, which drops us into the lobby state (QuickPlay available).
if DifficultyClose then
	DifficultyClose.Activated:Connect(function()
		if DifficultySelector then
			DifficultySelector.Visible = false
		end
		LeaveSeat:FireServer()
	end)
end

-------------------------------------------------------------------------------
-- QUICK PLAY
-- QuickPlay (dup of PlayVsBotButton) -> QuickPlaySelector (dup of the
-- DifficultySelector) -> Mode frame with two buttons:
--   * Bot    : the server teleports us to an empty table, then we open the
--              difficulty selector (same as clicking Play vs Bot).
--   * Player : the server teleports us to a table where a real player is
--              already waiting; the match auto-starts on seat.
-------------------------------------------------------------------------------
local function openQuickPlaySelector()
	if QuickPlaySelector then
		QuickPlaySelector.Visible = true
		UIFX.popIn(QuickPlaySelector)
	end
end

-- Back to the waiting buttons (no seat leave - we just dismiss the picker).
local function closeQuickPlaySelector()
	if QuickPlaySelector then
		QuickPlaySelector.Visible = false
	end
	setQuickPlayVisible(true)
	-- PlayVsBotButton stays hidden: closing the QuickPlay selector ONLY brings
	-- QuickPlay back. (PlayVsBot comes back on its own when you sit down -
	-- the waiting state - or via the difficulty selector's Back button.)
	if PlayVsBotButton and PlayVsBotButton.Visible then
		PlayVsBotButton.Visible = false
	end
end

if QuickPlayButton then
	QuickPlayButton.Activated:Connect(function()
		SFX.play("click")
		hideFrame(PlayVsBotButton)
		hideFrame(DifficultySelector) -- never show both selectors at once
		setQuickPlayVisible(false)
		task.delay(0.1, openQuickPlaySelector)
	end)
end

-- Both mode picks start a QuickPlay match: keep QuickPlay + PlayVsBot DOWN
-- while the teleport/seat completes, so they never flash back on screen.
-- (The seat event OpponentState would otherwise pop them in, and they'd get
-- hidden again a moment later - the "come back then leave" flicker.)
local function startQuickPlay(mode)
	if QuickPlaySelector then
		QuickPlaySelector.Visible = false
	end
	quickMatchStarting = true
	applyQuickPlayState()
	task.delay(4, function() -- safety net: the flag must never stick
		if quickMatchStarting then
			quickMatchStarting = false
			applyQuickPlayState()
		end
	end)
	QuickPlayRequest:FireServer(mode)
end

if QuickBotBtn then
	QuickBotBtn.Activated:Connect(function()
		startQuickPlay("Bot")
	end)
end

if QuickPlayerBtn then
	QuickPlayerBtn.Activated:Connect(function()
		startQuickPlay("Player")
	end)
end

if QuickCloseBtn then
	QuickCloseBtn.Activated:Connect(function()
		closeQuickPlaySelector()
	end)
end

QuickPlayResult.OnClientEvent:Connect(function(mode, success, note)
	if not success then
		quickMatchStarting = false
		if _G.Notify then
			_G.Notify({ title = "Quick Play", message = note or "Something went wrong", kind = "warn" })
		end
		closeQuickPlaySelector()
		return
	end

	if mode == "Bot" then
		-- The server just seated us at an empty table: open the difficulty
		-- selector right away (same as clicking Play vs Bot). Slight delay so
		-- the teleport + the waiting-state UI settle first.
		task.delay(0.5, function()
			quickMatchStarting = false
			local h = getHumanoid()
			if not (h and h.Seated) then
				return -- stood up during the teleport; lobby UI is already up
			end
			if not InteractionFrame.Visible then
				showFrame(InteractionFrame)
			end
			-- Hide the lobby/waiting buttons so ONLY the difficulty selector
			-- is visible (the waiting-state event that fired when we got
			-- seated pops PlayVsBot + QuickPlay back in, so hide them again).
			setQuickPlayVisible(false)
			if PlayVsBotButton and PlayVsBotButton.Visible then
				PlayVsBotButton.Visible = false
			end
			if DifficultySelector then
				DifficultySelector.Visible = true
				UIFX.popIn(DifficultySelector)
			else
				PlayVsBotRequest:FireServer("Easy")
			end
		end)
	elseif mode == "Player" then
		quickMatchStarting = false
		-- Keep QuickPlay down until the match actually ends (no flash of the
		-- waiting buttons while the seat reconciles / countdown runs).
		setQuickPlayVisible(false)
		if note and note ~= "" and _G.Notify then
			_G.Notify({ title = "Quick Play", message = note, kind = "info" })
		end
		-- Nothing else to do: the match auto-starts once the seat reconciles.
	end
end)
