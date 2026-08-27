--[[
	SpeechBubble.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	During a match, a comic speech bubble floats above YOUR character's head
	at the table, showing WHAT YOU ARE TYPING IN REAL TIME:
	  * the letters you've placed in the answer box so far
	  * your hearts (red = remaining, grey = lost)
	  * the round timer

	Because the bubble is in the 3D world above your head, YOUR OPPONENT (and
	anyone else who can see the table) watches your guess build up live -
	without either of you having to break focus on your own puzzle.

	No Studio setup needed - the bubble is built automatically. It pops in
	with a bounce, bobs gently up and down, and pops out when the match ends.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")

local LetterImages = require(ReplicatedStorage:WaitForChild("LetterImages"))

local RoundStart = Events:WaitForChild("RoundStart")
local HeartUpdate = Events:WaitForChild("HeartUpdate")
local TimerUpdate = Events:WaitForChild("TimerUpdate")
local GameOver = Events:WaitForChild("GameOver")

local MAX_HEARTS = 3

local billboard = nil
local bubbleScale = nil -- UIScale child (BillboardGui has no Scale property)
local bubbleFrame = nil
local heartLabels = {}
local typedLabel = nil
local timerLabel = nil
local bobConn = nil
local typedConn = nil
local bobBase = Vector3.new(0, 3.6, 0)
local shown = false
local t0 = os.clock()

-------------------------------------------------------------------------------
-- TYPING READER (decodes the AnswerBox slot images into letters)
-------------------------------------------------------------------------------
local letterByImage = {}
for i = 1, 26 do
	local l = string.char(96 + i)
	local img = LetterImages[l]
	if type(img) == "string" and img ~= "" then
		letterByImage[img] = l
	end
end

local gameGui = PlayerGui:FindFirstChild("GameUI")
	or PlayerGui:FindFirstChild("GameGui")
	or PlayerGui:FindFirstChildWhichIsA("ScreenGui")
local puzzleArea = gameGui and gameGui:FindFirstChild("PuzzleArea", true)
local answerBox = puzzleArea and puzzleArea:FindFirstChild("AnswerBox", true)

local function readTypedLetters()
	if not answerBox then
		return ""
	end
	local out = {}
	for i = 1, 13 do
		local slot = answerBox:FindFirstChild("Slot" .. i)
		if not slot then
			break
		end
		local ch = letterByImage[slot.Image] or "_"
		table.insert(out, ch)
	end
	return table.concat(out, " ")
end

-------------------------------------------------------------------------------
-- BUILD
-------------------------------------------------------------------------------
local function buildBillboard(character)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	billboard = Instance.new("BillboardGui")
	billboard.Name = "SpeechBubble"
	billboard.Size = UDim2.fromScale(0.26, 0.18)
	billboard.StudsOffset = bobBase
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 250
	billboard.Adornee = head

	-- Pop in/out animation lives on a UIScale child of the billboard.
	bubbleScale = Instance.new("UIScale")
	bubbleScale.Name = "BubbleScale"
	bubbleScale.Scale = 0
	bubbleScale.Parent = billboard

	-- Tail: a rotated square sticking out below the bubble. The bubble is
	-- drawn on top of it (higher ZIndex), so only the bottom edges show.
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.Size = UDim2.fromOffset(16, 16)
	tail.Position = UDim2.new(0.5, -8, 1, -8)
	tail.Rotation = 45
	tail.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tail.ZIndex = 1
	local tailStroke = Instance.new("UIStroke")
	tailStroke.Color = Color3.fromRGB(40, 40, 50)
	tailStroke.Thickness = 2
	tailStroke.Parent = tail
	tail.Parent = billboard

	bubbleFrame = Instance.new("Frame")
	bubbleFrame.Name = "Bubble"
	bubbleFrame.Size = UDim2.fromScale(1, 1)
	bubbleFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bubbleFrame.ZIndex = 2
	bubbleFrame.Parent = billboard
	local bubbleCorner = Instance.new("UICorner")
	bubbleCorner.CornerRadius = UDim.new(0.12, 0)
	bubbleCorner.Parent = bubbleFrame
	local bubbleStroke = Instance.new("UIStroke")
	bubbleStroke.Color = Color3.fromRGB(40, 40, 50)
	bubbleStroke.Thickness = 2.5
	bubbleStroke.Parent = bubbleFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bubbleFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = bubbleFrame

	-- Row 1: what you're typing (live)
	typedLabel = Instance.new("TextLabel")
	typedLabel.Name = "TypedLbl"
	typedLabel.LayoutOrder = 1
	typedLabel.BackgroundTransparency = 1
	typedLabel.Size = UDim2.new(1, 0, 0, 34)
	typedLabel.Font = Enum.Font.GothamBlack
	typedLabel.TextScaled = true
	typedLabel.TextColor3 = Color3.fromRGB(40, 40, 55)
	typedLabel.Text = "(typing...)"
	typedLabel.Parent = bubbleFrame

	-- Row 2: hearts
	local heartRow = Instance.new("Frame")
	heartRow.Name = "HeartRow"
	heartRow.LayoutOrder = 2
	heartRow.BackgroundTransparency = 1
	heartRow.Size = UDim2.new(1, 0, 0, 24)
	heartRow.Parent = bubbleFrame
	local heartLayout = Instance.new("UIListLayout")
	heartLayout.FillDirection = Enum.FillDirection.Horizontal
	heartLayout.Padding = UDim.new(0, 6)
	heartLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	heartLayout.Parent = heartRow
	heartLabels = {}
	for i = 1, MAX_HEARTS do
		local h = Instance.new("TextLabel")
		h.BackgroundTransparency = 1
		h.Size = UDim2.fromOffset(26, 24)
		h.Font = Enum.Font.GothamBlack
		h.TextSize = 22
		h.Text = "♥"
		h.TextColor3 = Color3.fromRGB(230, 60, 80)
		h.LayoutOrder = i
		h.Parent = heartRow
		table.insert(heartLabels, h)
	end

	-- Row 3: timer
	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLbl"
	timerLabel.LayoutOrder = 3
	timerLabel.BackgroundTransparency = 1
	timerLabel.Size = UDim2.new(1, 0, 0, 22)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 20
	timerLabel.TextColor3 = Color3.fromRGB(60, 60, 75)
	timerLabel.Text = ""
	timerLabel.Parent = bubbleFrame

	billboard.Parent = character
end

-------------------------------------------------------------------------------
-- SHOW / HIDE (pop in with a bounce, pop out on match end)
-------------------------------------------------------------------------------
local function startBob()
	if bobConn then
		return
	end
	bobConn = RunService.Heartbeat:Connect(function()
		if not billboard or not billboard.Parent then
			return
		end
		local t = os.clock() - t0
		billboard.StudsOffset = bobBase + Vector3.new(0, math.sin(t * 2.1) * 0.18, 0)
	end)
end

local function stopBob()
	if bobConn then
		bobConn:Disconnect()
		bobConn = nil
	end
end

local function startTypedWatch()
	if typedConn then
		return
	end
	local last = nil
	local stamp = 0
	typedConn = RunService.Heartbeat:Connect(function()
		if not shown or not typedLabel or not typedLabel.Parent then
			return
		end
		local now = os.clock()
		if now - stamp < 0.12 then
			return
		end
		stamp = now
		local text = readTypedLetters()
		if text ~= last then
			last = text
			typedLabel.Text = (text == "") and "(typing...)" or text
		end
	end)
end

local function stopTypedWatch()
	if typedConn then
		typedConn:Disconnect()
		typedConn = nil
	end
end

local function showBubble()
	if shown then
		return
	end
	local character = player.Character
	if not character or not character:FindFirstChild("Head") then
		return
	end
	if not billboard or not billboard.Parent then
		billboard = nil -- died with a respawned character
		buildBillboard(character)
		if not billboard then
			return
		end
	end
	billboard.Adornee = character:FindFirstChild("Head")
	billboard.Parent = character
	shown = true
	bubbleScale.Scale = 0
	TweenService:Create(
		bubbleScale,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
	startBob()
	startTypedWatch()
end

local function hideBubble()
	if not shown then
		return
	end
	shown = false
	stopBob()
	stopTypedWatch()
	local b = billboard
	local sc = bubbleScale
	billboard = nil
	bubbleScale = nil
	if not b or not b.Parent then
		return
	end
	if sc and sc.Parent then
		local t = TweenService:Create(
			sc,
			TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Scale = 0 }
		)
		t:Play()
		t.Completed:Connect(function()
			if b.Parent then
				b:Destroy()
			end
		end)
	end
	task.delay(1, function()
		if b.Parent then
			b:Destroy()
		end
	end)
end

-------------------------------------------------------------------------------
-- CONTENT UPDATES
-------------------------------------------------------------------------------
local function setHearts(count)
	count = math.clamp(count or 0, 0, MAX_HEARTS)
	for i, lbl in ipairs(heartLabels) do
		lbl.TextColor3 = (i <= count) and Color3.fromRGB(230, 60, 80) or Color3.fromRGB(210, 210, 218)
	end
end

-------------------------------------------------------------------------------
-- EVENTS
-------------------------------------------------------------------------------
RoundStart.OnClientEvent:Connect(function(wordLength)
	showBubble()
	setHearts(MAX_HEARTS)
end)

HeartUpdate.OnClientEvent:Connect(function(count)
	setHearts(count)
end)

TimerUpdate.OnClientEvent:Connect(function(seconds)
	if timerLabel then
		timerLabel.Text = tostring(seconds or 0) .. "s"
	end
end)

GameOver.OnClientEvent:Connect(function()
	hideBubble()
end)

-- Respawn during a match: re-attach the bubble to the new character's head.
player.CharacterAdded:Connect(function(character)
	if not shown then
		return
	end
	task.spawn(function()
		local head = character:WaitForChild("Head", 10)
		if head and shown then
			billboard = nil -- the old one died with the old character
			showBubble()
		end
	end)
end)
