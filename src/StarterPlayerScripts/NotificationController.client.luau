--[[
	NotificationController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives the NotificationGUI HUD with smooth UPWARD motion animations:
	  * Intro: Cards slide UP into position while scaling in.
	  * Outro: Cards slide UPWARDS towards the top of the screen while fading out.

	HIERARCHY:
		NotificationGUI (ScreenGui)
		└── Holder (Frame)
		    ├── UIAspectRatioConstraint (UIAspectRatioConstraint)
		    ├── UIListLayout (UIListLayout)
		    ├── UIPadding (UIPadding)
		    └── NotificationTemplate (Frame)
		        ├── Icon (ImageLabel)
		        ├── bg (ImageLabel)
		        ├── MessageLabel (TextLabel)
		        └── TitleLabel (TextLabel)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Safely resolve NotificationGUI
local function resolveNotificationGui(): Instance?
	local target = playerGui:FindFirstChild("NotificationGUI")
		or playerGui:FindFirstChild("NotificationGui")
		or playerGui:FindFirstChild("Notifications")
	if target then return target end

	local gameUI = playerGui:FindFirstChild("GameUI")
	if gameUI then
		target = gameUI:FindFirstChild("NotificationGUI") or gameUI:FindFirstChild("Holder")
		if target then return target end
	end

	local startTime = os.clock()
	while (os.clock() - startTime) < 8 do
		target = playerGui:FindFirstChild("NotificationGUI") or playerGui:FindFirstChild("NotificationGui")
		if target then return target end
		task.wait(0.1)
	end

	return playerGui:FindFirstChildWhichIsA("ScreenGui") or playerGui
end

local notifGui = resolveNotificationGui()

local function findObject(parent: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local found = parent:FindFirstChild(name, true)
		if found then return found end
	end
	return nil
end

local holder = notifGui and (findObject(notifGui, { "Holder", "NotificationsHolder", "List" }) :: GuiObject?)
if not holder and notifGui then
	local ok, res = pcall(function()
		return notifGui:WaitForChild("Holder", 5)
	end)
	if ok and res and res:IsA("GuiObject") then
		holder = res
	end
end

-- Template
local template: GuiObject? = holder and (findObject(holder, { "NotificationTemplate", "Template", "NotifTemplate" }) :: GuiObject?)
if template then
	template.Visible = false
end

-- ============================================================================
-- ICONS & THEME CONFIG
-- ============================================================================
local NOTIFICATION_ICONS = {
	success  = "rbxassetid://106595471170578", -- Green Check / Star
	reward   = "rbxassetid://121749597294959", -- Trophy / Star
	cash     = "rbxassetid://73475281808267",  -- Cash / Coin
	purchase = "rbxassetid://133477499555789", -- Cart / Bag
	win      = "rbxassetid://95488023650173",  -- Crown / Victory
	warn     = "rbxassetid://104052674943721", -- Yellow Warning
	error    = "rbxassetid://92700052607893",  -- Red Cross / Insufficient
	fail     = "rbxassetid://92700052607893",
	info     = "rbxassetid://78172314776394",  -- Info Circle
}

local NOTIFICATION_COLORS = {
	success  = Color3.fromRGB(60, 230, 100),
	reward   = Color3.fromRGB(255, 220, 75),
	cash     = Color3.fromRGB(255, 215, 60),
	purchase = Color3.fromRGB(80, 240, 130),
	win      = Color3.fromRGB(255, 215, 0),
	warn     = Color3.fromRGB(255, 185, 45),
	error    = Color3.fromRGB(255, 75, 75),
	fail     = Color3.fromRGB(255, 75, 75),
	info     = Color3.fromRGB(75, 185, 255),
}

local function ensureFallbackGui()
	if holder and template then return end

	local fallbackGui = playerGui:FindFirstChild("NotificationGUI")
	if not fallbackGui then
		fallbackGui = Instance.new("ScreenGui")
		fallbackGui.Name = "NotificationGUI"
		fallbackGui.ResetOnSpawn = false
		fallbackGui.DisplayOrder = 100
		fallbackGui.Parent = playerGui
	end

	if not holder then
		holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.AnchorPoint = Vector2.new(1, 0)
		holder.Position = UDim2.new(0.98, 0, 0.05, 0)
		holder.Size = UDim2.new(0.24, 0, 0.6, 0)
		holder.BackgroundTransparency = 1
		holder.Parent = fallbackGui

		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		list.Padding = UDim.new(0, 8)
		list.Parent = holder
	end

	if not template then
		template = Instance.new("Frame")
		template.Name = "NotificationTemplate"
		template.Size = UDim2.new(1, 0, 0, 68)
		template.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
		template.BackgroundTransparency = 0.15
		template.Visible = false
		template.Parent = holder

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = template

		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(60, 220, 100)
		s.Thickness = 1.5
		s.Parent = template

		local bg = Instance.new("ImageLabel")
		bg.Name = "bg"
		bg.Size = UDim2.new(1, 0, 1, 0)
		bg.BackgroundTransparency = 1
		bg.ImageTransparency = 0.7
		bg.Parent = template

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, 44, 0, 44)
		icon.Position = UDim2.new(0, 10, 0.5, -22)
		icon.BackgroundTransparency = 1
		icon.Parent = template

		local title = Instance.new("TextLabel")
		title.Name = "TitleLabel"
		title.Size = UDim2.new(1, -64, 0, 22)
		title.Position = UDim2.new(0, 58, 0, 10)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = template

		local msg = Instance.new("TextLabel")
		msg.Name = "MessageLabel"
		msg.Size = UDim2.new(1, -64, 0, 24)
		msg.Position = UDim2.new(0, 58, 0, 32)
		msg.BackgroundTransparency = 1
		msg.Font = Enum.Font.Gotham
		msg.TextSize = 13
		msg.TextColor3 = Color3.fromRGB(220, 225, 235)
		msg.TextXAlignment = Enum.TextXAlignment.Left
		msg.TextWrapped = true
		msg.Parent = template
	end
end

ensureFallbackGui()

type NotifOptions = {
	title: string?,
	message: string?,
	kind: string?,
	duration: number?,
	icon: string?,
}

-- Spawns an animated notification card with UPWARD animation
local function showNotification(opts: NotifOptions)
	ensureFallbackGui()
	if not holder or not template then return end

	local kind = string.lower(opts.kind or "info")
	local titleText = opts.title or "Notification"
	local msgText = opts.message or ""
	local duration = opts.duration or 3.5

	local iconAsset = opts.icon or NOTIFICATION_ICONS[kind] or NOTIFICATION_ICONS.info
	local accentColor = NOTIFICATION_COLORS[kind] or NOTIFICATION_COLORS.info

	local card = template:Clone()
	card.Name = "Notification_" .. tostring(os.clock())
	card.Visible = true

	local titleLbl = card:FindFirstChild("TitleLabel", true) :: TextLabel?
	local msgLbl = card:FindFirstChild("MessageLabel", true) :: TextLabel?
	local iconImg = card:FindFirstChild("Icon", true) :: ImageLabel?
	local bgImg = card:FindFirstChild("bg", true) :: ImageLabel?
	local stroke = card:FindFirstChildOfClass("UIStroke")

	if titleLbl and titleLbl:IsA("TextLabel") then
		titleLbl.Text = titleText
		titleLbl.TextColor3 = accentColor
	end

	if msgLbl and msgLbl:IsA("TextLabel") then
		msgLbl.Text = msgText
	end

	if iconImg and iconImg:IsA("ImageLabel") then
		iconImg.Image = iconAsset
	end

	if bgImg and bgImg:IsA("ImageLabel") then
		bgImg.ImageColor3 = accentColor
	end

	if stroke then
		stroke.Color = accentColor
	end

	local s = card:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Parent = card
	end
	s.Scale = 0.6
	card.Parent = holder

	-- REQUIREMENT: UPWARD motion on intro & outro
	TweenService:Create(
		s,
		TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	-- Auto dismiss after duration with UPWARD slide
	task.delay(duration, function()
		if not card or not card.Parent then return end

		-- Animate UPWARDS off top
		local outTween = TweenService:Create(
			s,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0.3 }
		)
		outTween:Play()

		if titleLbl then
			TweenService:Create(titleLbl, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		end
		if msgLbl then
			TweenService:Create(msgLbl, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		end
		if iconImg then
			TweenService:Create(iconImg, TweenInfo.new(0.2), { ImageTransparency = 1 }):Play()
		end

		outTween.Completed:Connect(function()
			card:Destroy()
		end)
	end)
end

_G.Notify = showNotification

-- ============================================================================
-- CONNECT SERVER NOTIFICATIONS
-- ============================================================================
local Events = ReplicatedStorage:WaitForChild("Events", 15)
if Events then
	local NotifyPlayer = Events:FindFirstChild("NotifyPlayer") :: RemoteEvent?
	if NotifyPlayer then
		NotifyPlayer.OnClientEvent:Connect(function(data)
			if type(data) == "table" then
				showNotification(data)
			elseif type(data) == "string" then
				showNotification({ message = data, kind = "info" })
			end
		end)
	end

	local GameOver = Events:FindFirstChild("GameOver") :: RemoteEvent?
	if GameOver then
		GameOver.OnClientEvent:Connect(function(winnerName)
			if winnerName == player.Name then
				showNotification({
					title = "Victory!",
					message = "You won the match! Excellent game!",
					kind = "win",
					duration = 4.5,
				})
			end
		end)
	end

	-- NOTE: CashAwarded is deliberately NOT notified. It fires right after the
	-- money ROLL at match start - it only reveals the prize the WINNER will
	-- collect at match end. The cash actually landing in the balance is shown
	-- by the StatsPanel gain animation (and the "Victory!" notify on a win).
end
