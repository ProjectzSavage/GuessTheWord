--[[
	RewardsController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Renders the server-driven RewardsF window. The SERVER (RewardsService) sends
	a `payload` with categories + rows (id, left, rewards, claimed, ready). This
	client clones the RowTemplate per row and styles the ClaimBtn:
	  * CLAIMED (green, disabled)  -- already claimed
	  * CLAIM   (green, enabled)   -- ready to claim
	  * FOLLOW  (blue, enabled)    -- social: you must follow the owner on Roblox
	  * NOT READY (grey, disabled) -- requirement not met / on cooldown

	MUTUAL EXCLUSIVITY:
	When opening Rewards, it automatically closes Shop and Inventory so frames
	never overlap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player  = Players.LocalPlayer
local gui     = player:WaitForChild("PlayerGui")
local gameGui = gui:WaitForChild("GameUI", 10) or gui:FindFirstChildWhichIsA("ScreenGui")

local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))

-- TWEAKS: size of the reward icons inside each rewards row (pixels).
-- Raise ICON_SIZE for bigger icons (e.g. 64), lower it if they overflow
-- the row on small screens.
local ICON_SIZE = 56
local ICON_SPACING = 12

local root     = gameGui and (gameGui:FindFirstChild("RewardsF", true) or gameGui:WaitForChild("RewardsF", 8))
local closeBtn = root and (root:FindFirstChild("CloseBtn", true) :: GuiButton?)

-- Tolerant label lookup: try the documented name first, then common variants,
-- so the "Total Robux spent" / category text works even if the label was
-- renamed in Studio.
local function findTextLabel(parent, names)
	if not parent then return nil end
	for _, name in ipairs(names) do
		local found = parent:FindFirstChild(name, true)
		if found and found:IsA("TextLabel") then
			return found
		end
	end
	return nil
end

local leftTabs    = root and (root:FindFirstChild("LeftTabs", true) :: GuiObject?)
local content     = root and (root:FindFirstChild("Content", true) :: GuiObject?)
local titleLbl    = findTextLabel(content, { "CategoryTitle", "Title", "TitleLbl" })
local subLbl      = findTextLabel(content, { "CategorySubtitle", "Subtitle", "SubtitleLbl", "SubLbl", "TotalSpentLbl" })
local rowsScroll  = content and (content:FindFirstChild("RowsScroll", true) :: ScrollingFrame?)
local rowTemplate = rowsScroll and (rowsScroll:FindFirstChild("RowTemplate", true) :: GuiObject?)

local Events             = ReplicatedStorage:WaitForChild("Events", 15)
local RewardSync         = Events and (Events:FindFirstChild("RewardSync") or Events:WaitForChild("RewardSync", 10))
local RewardClaim        = Events and (Events:FindFirstChild("RewardClaim") or Events:WaitForChild("RewardClaim", 10))
local RewardRequestSync  = Events and (Events:FindFirstChild("RewardRequestSync") or Events:WaitForChild("RewardRequestSync", 10))
local NotifyPlayer       = Events and (Events:FindFirstChild("NotifyPlayer") or Events:WaitForChild("NotifyPlayer", 10))

local TAB_TO_CAT = {
	PlaytimeBtn   = "playtime",
	DailyBtn      = "daily",
	GroupBtn      = "group",
	SocialBtn     = "social",
	VipDailyBtn   = "vipdaily",
	RobuxSpentBtn = "robuxspent",
}

local CAT_TITLE = {
	playtime   = "Playtime Rewards",
	daily      = "Daily Rewards",
	group      = "Group Rewards",
	social     = "Social Rewards",
	vipdaily   = "VIP Daily Rewards",
	robuxspent = "Robux Spent Rewards",
}

local REWARD_IMAGES = {
	letter_1 = "rbxassetid://106595471170578",
	letter_2 = "rbxassetid://92700052607893",
	letter_3 = "rbxassetid://104052674943721",
	word_1   = "rbxassetid://95488023650173",
	word_2   = "rbxassetid://102920484565439",
	word_3   = "rbxassetid://78172314776394",
	cash_200 = "rbxassetid://73475281808267",
	cash_300 = "rbxassetid://72562550267593",
	cash_500 = "rbxassetid://121749597294959",
	cash_1000 = "rbxassetid://105125784128656",
	chair    = "rbxassetid://133477499555789",
}

local REWARD_PATTERNS = {
	{ pattern = "+1 Reveal Letter", image = "letter_1" },
	{ pattern = "+2 Reveal Letter", image = "letter_2" },
	{ pattern = "+3 Reveal Letter", image = "letter_3" },
	{ pattern = "+1 Reveal Word",   image = "word_1" },
	{ pattern = "+2 Reveal Word",   image = "word_2" },
	{ pattern = "+3 Reveal Word",   image = "word_3" },
	{ pattern = "+$200",            image = "cash_200" },
	{ pattern = "+$300",            image = "cash_300" },
	{ pattern = "+$500",            image = "cash_500" },
	{ pattern = "+$1000",           image = "cash_1000" },
	{ pattern = "Random Chair",     image = "chair" },
}

local payload   = nil
local activeCat = "playtime"
local isOpen    = false
local syncedAt = os.clock()
local syncedPlaytime = 0
local syncedDaily = 0

local function requestSync()
	if RewardRequestSync then
		RewardRequestSync:FireServer()
	end
end

local function setMsg(text)
	local msg = root and root:FindFirstChild("MsgLbl", true) :: TextLabel?
	if msg and msg:IsA("TextLabel") then
		msg.Text = text
		task.delay(3, function()
			if msg then msg.Text = "" end
		end)
	end
end

local function clearRows()
	if not rowsScroll then return end
	for _, c in ipairs(rowsScroll:GetChildren()) do
		if c:IsA("Frame") and c ~= rowTemplate then
			c:Destroy()
		end
	end
end

local function styleClaim(btn, row, categoryId)
	btn.AutoButtonColor = false
	if row.claimed then
		btn.Text = "CLAIMED"
		btn.BackgroundColor3 = Color3.fromRGB(60, 220, 60)
		btn.Active = false
	elseif row.ready then
		btn.Text = "CLAIM"
		btn.BackgroundColor3 = Color3.fromRGB(60, 220, 60)
		btn.Active = true
	elseif categoryId == "social" then
		btn.Text = "FOLLOW"
		btn.BackgroundColor3 = Color3.fromRGB(70, 140, 255)
		btn.Active = true
	else
		btn.Text = "NOT READY"
		btn.BackgroundColor3 = Color3.fromRGB(140, 140, 140)
		btn.Active = false
	end
end

local function parseRewardImages(rewardsText)
	local images = {}
	local txt = tostring(rewardsText or "")
	for _, p in ipairs(REWARD_PATTERNS) do
		if txt:find(p.pattern) then
			table.insert(images, p.image)
		end
	end
	return images
end

local function renderRow(categoryId, idx, row)
	if not rowTemplate or not rowsScroll then return end
	local clone = rowTemplate:Clone()
	clone.Visible = true
	clone.Name = "Row_" .. tostring(row.id or idx)

	local left = clone:FindFirstChild("LeftLbl", true) :: TextLabel?
	if left and left:IsA("TextLabel") then
		if categoryId == "playtime" then
			local reqMin = tonumber(row.requiredMin) or tonumber(string.match(tostring(row.left or ""), "(%d+)"))
			if reqMin then
				left.Text = NumberFormat.formatPlaytimeRequirement(reqMin)
			else
				left.Text = row.left or ""
			end
		elseif categoryId == "daily" then
			left.Text = "Day " .. tostring(idx)
		elseif categoryId == "group" then
			left.Text = "Group"
		elseif categoryId == "vipdaily" then
			left.Text = "VIP"
		elseif categoryId == "robuxspent" then
			left.Text = "R$" .. tostring(row.left or "")
		elseif categoryId == "social" then
			left.Text = row.left or ""
		end
	end

	local container = clone:FindFirstChild("RewardsContainer", true) :: GuiObject?
	local template = container and container:FindFirstChild("ImageTemplate")
	if template and template:IsA("ImageLabel") and container then
		local keys = parseRewardImages(row.rewards)
		template.Visible = false
		local iconSize = ICON_SIZE
		local spacing = ICON_SPACING
		local count = math.min(#keys, 3)
		local totalW = count * iconSize + (count - 1) * spacing
		local startX = (container.AbsoluteSize.X - totalW) / 2
		for i = 1, count do
			local key = keys[i]
			local img = template:Clone()
			img.Visible = true
			img.Image = REWARD_IMAGES[key] or key
			img.Size = UDim2.new(0, iconSize, 0, iconSize)
			img.Position = UDim2.new(0, startX + (i - 1) * (iconSize + spacing), 0.5, -iconSize / 2)
			img.Parent = container
		end
	end

	local claim = clone:FindFirstChild("ClaimBtn", true) :: TextButton?
	if claim and claim:IsA("TextButton") then
		styleClaim(claim, row, categoryId)
		claim.MouseButton1Click:Connect(function()
			if categoryId == "social" and not row.ready and not row.claimed then
				setMsg("Follow " .. (row.devUsername or "the owner") .. " on Roblox to claim!")
				return
			end
			if row.ready and not row.claimed and RewardClaim then
				RewardClaim:FireServer(categoryId, row.id)
			end
		end)
	end

	clone.Parent = rowsScroll
end

local function renderRows()
	clearRows()
	local rows = payload and payload.categories and payload.categories[activeCat] or {}
	for idx, row in ipairs(rows) do
		renderRow(activeCat, idx, row)
	end
end

local function livePlaytime()
	return syncedPlaytime + (os.clock() - syncedAt)
end

local function liveDaily()
	return math.max(0, syncedDaily - (os.clock() - syncedAt))
end

local function refreshSubtitle()
	if not subLbl then return end
	if not payload then
		subLbl.Text = "Waiting for server sync..."
		return
	end
	if activeCat == "robuxspent" then
		subLbl.Text = "Total Robux spent: R$" .. tostring(payload.robuxSpentTotal or 0)
	elseif activeCat == "playtime" then
		subLbl.Text = "Played for " .. NumberFormat.formatPlaytimePlayed(livePlaytime())
	elseif activeCat == "daily" then
		local left = liveDaily()
		if left > 0 then
			subLbl.Text = "Next daily in " .. NumberFormat.formatTime(left)
		else
			subLbl.Text = "Daily reward ready!"
		end
	elseif activeCat == "social" then
		subLbl.Text = "Follow the owners on Roblox to claim!"
	elseif activeCat == "group" then
		subLbl.Text = "Like the game + Join the group"
	elseif activeCat == "vipdaily" then
		subLbl.Text = "Become VIP to claim"
	else
		subLbl.Text = ""
	end
end

local function render()
	if not root then return end
	if titleLbl then
		titleLbl.Text = CAT_TITLE[activeCat] or "Rewards"
	end
	if not payload then
		if subLbl then subLbl.Text = "Waiting for server sync..." end
		clearRows()
		return
	end
	refreshSubtitle()
	renderRows()
end

local function selectCategory(cat)
	activeCat = cat
	if isOpen then render() end
end

local function onOpen()
	if not root then return end
	if isOpen or root.Visible then return end -- already open (idempotent)
	-- Auto-close Shop and Inventory if open
	if _G.ShopAPI and _G.ShopAPI.isOpen and _G.ShopAPI.isOpen() and _G.ShopAPI.close then
		_G.ShopAPI.close()
	end
	if _G.InventoryAPI and _G.InventoryAPI.isOpen and _G.InventoryAPI.isOpen() and _G.InventoryAPI.close then
		_G.InventoryAPI.close()
	end

	isOpen = true
	root.Active = true
	UIFX.openWindow(root)
	requestSync()
	render()
end

local function onClose()
	if not root or not isOpen then return end
	isOpen = false
	root.Active = false
	UIFX.closeWindow(root)
end

if leftTabs then
	for btnName, cat in pairs(TAB_TO_CAT) do
		local btn = leftTabs:FindFirstChild(btnName, true) :: GuiButton?
		if btn and btn:IsA("GuiButton") then
			btn.MouseButton1Click:Connect(function()
				selectCategory(cat)
			end)
		end
	end
end

if closeBtn then
	closeBtn.MouseButton1Click:Connect(onClose)
end

if RewardSync then
	RewardSync.OnClientEvent:Connect(function(newPayload)
		if type(newPayload) ~= "table" then return end
		payload = newPayload
		syncedAt = os.clock()
		syncedPlaytime = tonumber(newPayload.totalPlaytime) or 0
		syncedDaily = tonumber(newPayload.dailyCountdown) or 0
		if isOpen then render() end
	end)
end

RunService.Heartbeat:Connect(function()
	-- robuxspent is included so the "Total Robux spent" line always reflects
	-- the latest synced payload while the tab is open.
	if isOpen and (activeCat == "playtime" or activeCat == "daily" or activeCat == "robuxspent") then
		refreshSubtitle()
	end
end)

if NotifyPlayer then
	NotifyPlayer.OnClientEvent:Connect(function(info)
		if type(info) == "table" and info.message then
			setMsg(info.message)
		end
	end)
end

local RewardsAPI = {}
function RewardsAPI.open()
	onOpen()
end
function RewardsAPI.close()
	onClose()
end
function RewardsAPI.isAvailable()
	return root ~= nil
end
function RewardsAPI.isOpen()
	return root ~= nil and isOpen and root.Visible
end
_G.RewardsAPI = RewardsAPI

requestSync()

