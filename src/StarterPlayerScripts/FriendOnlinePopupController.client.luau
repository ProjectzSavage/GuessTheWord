--[[
	FriendOnlinePopupController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Detects when friends come online and presents a compact, non-intrusive popup
	directly UNDER the StatsPanel in the top-left corner.
	Includes an INVITE button (SocialService:PromptGameInvite), avatar thumbnail,
	reward text, and a sleek auto-closing countdown bar.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SocialService = game:GetService("SocialService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Locate GameUI / Currency ScreenGui
local function resolveParentGui(): Instance
	return playerGui:FindFirstChild("GameUI")
		or playerGui:FindFirstChild("Currency")
		or playerGui:FindFirstChild("GameGui")
		or playerGui:WaitForChild("GameUI", 10)
end

local parentGui = resolveParentGui()

local POPUP_NAME = "FriendOnlinePopup"
local POPUP_SECONDS = 10
local REWARD_TEXT = "+$50 CASH"

local POLL_INTERVAL = 15
local GLOBAL_POPUP_COOLDOWN = 60
local PER_FRIEND_COOLDOWN = 600
local MAX_POPUPS_PER_SESSION = 8
local MAX_QUEUE_SIZE = 6

-- Positions (under StatsPanel at top-left)
local REST_POS = UDim2.new(0.02, 0, 0.12, 0)
local HIDDEN_POS = UDim2.new(-0.25, 0, 0.12, 0)
local SLIDE_UP_POS = UDim2.new(0.02, 0, -0.15, 0)

local popup, titleLbl, closeBtn, avatarImg, rewardLbl, inviteBtn, countdownFill, countdownText
local countdownConn: RBXScriptConnection? = nil

local knownOnline = {}
local queuedById = {}
local queue = {}

local lastPopupAt = 0
local popupCount = 0
local lastShownByFriend = {}
local isPanelSlidUp = false

local function makeCornerScale(inst: GuiObject, scaleRadius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scaleRadius, 0)
	c.Parent = inst
	return c
end

local function makeStroke(inst: GuiObject, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = inst
	return s
end

local function createGui()
	if not parentGui then return end
	local old = parentGui:FindFirstChild(POPUP_NAME)
	if old then old:Destroy() end

	popup = Instance.new("Frame")
	popup.Name = POPUP_NAME
	popup.Position = HIDDEN_POS
	popup.Size = UDim2.new(0.2, 0, 0.075, 0) -- compact under StatsPanel
	popup.BackgroundColor3 = Color3.fromRGB(25, 28, 42)
	popup.BackgroundTransparency = 0.15
	popup.Visible = false
	popup.ZIndex = 50
	popup.Parent = parentGui
	makeCornerScale(popup, 0.15)
	makeStroke(popup, Color3.fromRGB(75, 220, 120), 1.5)

	-- Avatar Thumbnail
	avatarImg = Instance.new("ImageLabel")
	avatarImg.Name = "AvatarImage"
	avatarImg.BackgroundColor3 = Color3.fromRGB(15, 17, 27)
	avatarImg.Position = UDim2.new(0.03, 0, 0.12, 0)
	avatarImg.Size = UDim2.new(0.18, 0, 0.65, 0)
	avatarImg.Image = "rbxassetid://0"
	avatarImg.ZIndex = 51
	avatarImg.Parent = popup
	makeCornerScale(avatarImg, 0.2)

	-- Online Dot
	local onlineDot = Instance.new("Frame")
	onlineDot.Name = "OnlineDot"
	onlineDot.AnchorPoint = Vector2.new(1, 0)
	onlineDot.Position = UDim2.new(1, 0, 0, 0)
	onlineDot.Size = UDim2.new(0.28, 0, 0.28, 0)
	onlineDot.BackgroundColor3 = Color3.fromRGB(73, 255, 67)
	onlineDot.ZIndex = 52
	onlineDot.Parent = avatarImg
	makeCornerScale(onlineDot, 1)

	-- Header Title (Friend is online)
	titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "HeaderTitle"
	titleLbl.BackgroundTransparency = 1
	titleLbl.Position = UDim2.new(0.24, 0, 0.1, 0)
	titleLbl.Size = UDim2.new(0.55, 0, 0.35, 0)
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextScaled = true
	titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Text = "Friend is online!"
	titleLbl.ZIndex = 51
	titleLbl.Parent = popup

	-- Reward Subtitle
	rewardLbl = Instance.new("TextLabel")
	rewardLbl.Name = "RewardText"
	rewardLbl.BackgroundTransparency = 1
	rewardLbl.Position = UDim2.new(0.24, 0, 0.45, 0)
	rewardLbl.Size = UDim2.new(0.38, 0, 0.3, 0)
	rewardLbl.Font = Enum.Font.GothamBold
	rewardLbl.TextScaled = true
	rewardLbl.TextColor3 = Color3.fromRGB(255, 225, 75)
	rewardLbl.TextXAlignment = Enum.TextXAlignment.Left
	rewardLbl.Text = REWARD_TEXT
	rewardLbl.ZIndex = 51
	rewardLbl.Parent = popup

	-- Invite Button
	inviteBtn = Instance.new("TextButton")
	inviteBtn.Name = "InviteBtn"
	inviteBtn.Position = UDim2.new(0.64, 0, 0.42, 0)
	inviteBtn.Size = UDim2.new(0.22, 0, 0.38, 0)
	inviteBtn.BackgroundColor3 = Color3.fromRGB(60, 210, 80)
	inviteBtn.Text = "INVITE"
	inviteBtn.Font = Enum.Font.GothamBlack
	inviteBtn.TextScaled = true
	inviteBtn.TextColor3 = Color3.fromRGB(15, 30, 15)
	inviteBtn.ZIndex = 52
	inviteBtn.Parent = popup
	makeCornerScale(inviteBtn, 0.25)

	-- Close "X" Button
	closeBtn = Instance.new("TextButton")
	closeBtn.Name = "PopupCloseBtn"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(0.97, 0, 0.08, 0)
	closeBtn.Size = UDim2.new(0.08, 0, 0.32, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextScaled = true
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.ZIndex = 52
	closeBtn.Parent = popup
	makeCornerScale(closeBtn, 0.3)

	-- Countdown Progress Bar
	local countdownBar = Instance.new("Frame")
	countdownBar.Name = "CountdownBar"
	countdownBar.Position = UDim2.new(0.03, 0, 0.88, 0)
	countdownBar.Size = UDim2.new(0.94, 0, 0.06, 0)
	countdownBar.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
	countdownBar.ZIndex = 51
	countdownBar.Parent = popup
	makeCornerScale(countdownBar, 1)

	countdownFill = Instance.new("Frame")
	countdownFill.Name = "CountdownFill"
	countdownFill.Size = UDim2.new(1, 0, 1, 0)
	countdownFill.BackgroundColor3 = Color3.fromRGB(80, 220, 255)
	countdownFill.ZIndex = 52
	countdownFill.Parent = countdownBar
	makeCornerScale(countdownFill, 1)
end

local function setAvatar(userId: number)
	local ok, thumb = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)
	if avatarImg then
		avatarImg.Image = (ok and thumb) or "rbxassetid://0"
	end
end

local function hidePopup()
	if countdownConn then
		countdownConn:Disconnect()
		countdownConn = nil
	end

	if popup and popup.Visible then
		local tw = TweenService:Create(
			popup,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = HIDDEN_POS }
		)
		tw:Play()
		tw.Completed:Connect(function()
			popup.Visible = false
		end)
	end
end

local function showPopup(friendName: string, friendUserId: number)
	lastPopupAt = tick()
	popupCount += 1
	lastShownByFriend[friendUserId] = tick()

	if titleLbl then
		titleLbl.Text = string.format("%s online!", friendName)
	end
	if rewardLbl then
		rewardLbl.Text = REWARD_TEXT
	end
	setAvatar(friendUserId)

	popup.Position = HIDDEN_POS
	popup.Visible = true

	local targetPos = isPanelSlidUp and SLIDE_UP_POS or REST_POS
	TweenService:Create(
		popup,
		TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = targetPos }
	):Play()

	local started = tick()
	if countdownFill then
		countdownFill.Size = UDim2.new(1, 0, 1, 0)
	end

	if countdownConn then countdownConn:Disconnect() end
	countdownConn = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - started
		local left = math.max(0, POPUP_SECONDS - elapsed)
		local ratio = left / POPUP_SECONDS

		if countdownFill then
			countdownFill.Size = UDim2.new(ratio, 0, 1, 0)
		end

		if left <= 0 then
			hidePopup()
		end
	end)
end

local function fetchFriendsOnline()
	local ok, list = pcall(function()
		return player:GetFriendsOnline(200)
	end)
	if not ok or type(list) ~= "table" then
		return {}
	end
	return list
end

local function enqueueFriend(name: string, userId: number)
	if queuedById[userId] then return end
	if #queue >= MAX_QUEUE_SIZE then return end
	queuedById[userId] = true
	table.insert(queue, { name = name, userId = userId })
end

local function canShow(userId: number): boolean
	local now = tick()
	if popupCount >= MAX_POPUPS_PER_SESSION then return false end
	if (now - lastPopupAt) < GLOBAL_POPUP_COOLDOWN then return false end
	local prev = lastShownByFriend[userId] or 0
	if (now - prev) < PER_FRIEND_COOLDOWN then return false end
	return true
end

local function tryShowFromQueue()
	if popup and popup.Visible then return end
	if #queue == 0 then return end

	local item = table.remove(queue, 1)
	if not item then return end
	queuedById[item.userId] = nil

	if canShow(item.userId) then
		showPopup(item.name, item.userId)
	end
end

local function bootstrapPresence()
	for _, entry in ipairs(fetchFriendsOnline()) do
		if entry.IsOnline and entry.VisitorId then
			knownOnline[entry.VisitorId] = true
		end
	end
end

local function pollForNewOnlineFriend()
	local list = fetchFriendsOnline()
	local nowOnline = {}

	for _, entry in ipairs(list) do
		local uid = entry.VisitorId
		if entry.IsOnline and uid then
			nowOnline[uid] = true
			local wasOnline = (knownOnline[uid] == true)
			if not wasOnline then
				enqueueFriend(entry.UserName or "Friend", uid)
			end
		end
	end

	knownOnline = nowOnline
	tryShowFromQueue()
end

createGui()

if inviteBtn then
	inviteBtn.MouseButton1Click:Connect(function()
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end)
end

if closeBtn then
	closeBtn.MouseButton1Click:Connect(hidePopup)
end

bootstrapPresence()

task.spawn(function()
	while true do
		pollForNewOnlineFriend()
		task.wait(POLL_INTERVAL)
	end
end)

print("[FriendOnlinePopupController] Ready - Compact under StatsPanel")
