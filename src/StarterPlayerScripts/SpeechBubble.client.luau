--[[
	SpeechBubble.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	During a match, an animated COMIC SPEECH BUBBLE floats over YOUR
	character's head at the table. It shows the round at a glance:
	  * your hearts (red = remaining, grey = lost)
	  * the word progress (one slot per letter; revealed letters fill in)
	  * the round timer
	...so you can stay focused on the table and keep interacting without
	staring at the on-screen puzzle.

	No Studio setup needed - the bubble is built automatically. It pops in
	with a bounce, bobs gently up and down, and pops out when the match ends.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Events = ReplicatedStorage:WaitForChild("Events")

local RoundStart = Events:WaitForChild("RoundStart")
local HeartUpdate = Events:WaitForChild("HeartUpdate")
local TimerUpdate = Events:WaitForChild("TimerUpdate")
local PowerupGrant = Events:WaitForChild("PowerupGrant")
local GameOver = Events:WaitForChild("GameOver")

local MAX_HEARTS = 3

local billboard = nil
local bubbleScale = nil -- UIScale child (BillboardGui has no Scale property)
local bubbleFrame = nil
local heartLabels = {}
local slotLabels = {}
local timerLabel = nil
local bobConn = nil
local bobBase = Vector3.new(0, 3.4, 0)
local shown = false
local t0 = os.clock()

-------------------------------------------------------------------------------
-- BUILD
-------------------------------------------------------------------------------
local function makeSlot()
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1 / 13, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(40, 40, 50)
	stroke.Thickness = 1.5
	stroke.Parent = frame
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(120, 120, 135)
	lbl.Text = "_"
	lbl.Parent = frame
	return frame, lbl
end

local function buildBillboard(character)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	billboard = Instance.new("BillboardGui")
	billboard.Name = "SpeechBubble"
	billboard.Size = UDim2.fromScale(0.24, 0.16)
	billboard.StudsOffset = bobBase
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
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
	tail.Size = UDim2.fromOffset(14, 14)
	tail.Position = UDim2.new(0.5, -7, 1, -7)
	tail.Rotation = 45
	tail.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tail.ZIndex = 1
	local tailStroke = Instance.new("UIStroke")
	tailStroke.Color = Color3.fromRGB(40, 40, 50)
	tailStroke.Thickness = 1.5
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
	bubbleStroke.Thickness = 2
	bubbleStroke.Parent = bubbleFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bubbleFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = bubbleFrame

	-- Row 1: hearts
	local heartRow = Instance.new("Frame")
	heartRow.Name = "HeartRow"
	heartRow.LayoutOrder = 1
	heartRow.BackgroundTransparency = 1
	heartRow.Size = UDim2.new(1, 0, 0, 22)
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
		h.Size = UDim2.fromOffset(24, 22)
		h.Font = Enum.Font.GothamBlack
		h.TextSize = 20
		h.Text = "♥"
		h.TextColor3 = Color3.fromRGB(230, 60, 80)
		h.LayoutOrder = i
		h.Parent = heartRow
		table.insert(heartLabels, h)
	end

	-- Row 2: word slots (rebuilt every round)
	local slotRow = Instance.new("Frame")
	slotRow.Name = "SlotRow"
	slotRow.LayoutOrder = 2
	slotRow.BackgroundTransparency = 1
	slotRow.Size = UDim2.new(1, 0, 0, 34)
	slotRow.Parent = bubbleFrame
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.Padding = UDim.new(0, 4)
	slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	slotLayout.Parent = slotRow

	-- Row 3: timer
	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLbl"
	timerLabel.LayoutOrder = 3
	timerLabel.BackgroundTransparency = 1
	timerLabel.Size = UDim2.new(1, 0, 0, 20)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 18
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
end

local function hideBubble()
	if not shown then
		return
	end
	shown = false
	stopBob()
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

local function rebuildSlots(wordLength)
	if not bubbleFrame then
		return
	end
	local row = bubbleFrame:FindFirstChild("SlotRow")
	if not row then
		return
	end
	for _, c in ipairs(row:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	slotLabels = {}
	for i = 1, wordLength do
		local frame, lbl = makeSlot()
		frame.LayoutOrder = i
		frame.Parent = row
		table.insert(slotLabels, lbl)
	end
end

local function revealSlot(index, letter)
	local lbl = slotLabels[index]
	if lbl and typeof(letter) == "string" and letter ~= "" then
		lbl.Text = string.upper(letter:sub(1, 1))
		lbl.TextColor3 = Color3.fromRGB(40, 160, 70)
	end
end

local function revealWord(word)
	for i = 1, #slotLabels do
		local ch = word:sub(i, i)
		if ch ~= "" then
			slotLabels[i].Text = string.upper(ch)
			slotLabels[i].TextColor3 = Color3.fromRGB(40, 160, 70)
		end
	end
end

-------------------------------------------------------------------------------
-- EVENTS
-------------------------------------------------------------------------------
RoundStart.OnClientEvent:Connect(function(wordLength)
	showBubble()
	rebuildSlots(math.clamp(wordLength or 4, 1, 13))
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

PowerupGrant.OnClientEvent:Connect(function(powerupType, success, letter, index, word)
	if not success then
		return
	end
	if powerupType == "Letter" and typeof(index) == "number" then
		revealSlot(index, letter)
	elseif powerupType == "Word" and typeof(word) == "string" then
		revealWord(word)
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
