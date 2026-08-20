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

	SETUP (hierarchy in docs/UI_HIERARCHY.md):
	  RewardsF (in GameUI)
	    ├── CloseBtn, MsgLbl, TitleLbl
	    ├── LeftTabs: DailyBtn, GroupBtn, PlaytimeBtn, RobuxSpentBtn, SocialBtn, VipDailyBtn
	    └── Content: CategoryTitle, CategorySubtitle, RowsScroll (RowTemplate)
	RowTemplate: LeftLbl, RewardsContainer (ImageTemplate), ClaimBtn.

	REWARD IMAGES: fill REWARD_PATTERNS/REWARD_IMAGES below so reward text like
	"+1 Reveal Letter" maps to your icon.
]]

local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local gui     = player:WaitForChild("PlayerGui")
local gameGui = gui:WaitForChild("GameUI")

local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))

local root     = gameGui:WaitForChild("RewardsF")
local closeBtn = root:WaitForChild("CloseBtn")

local leftTabs    = root:WaitForChild("LeftTabs")
local content     = root:WaitForChild("Content")
local titleLbl    = content:WaitForChild("CategoryTitle")
local subLbl      = content:WaitForChild("CategorySubtitle")
local rowsScroll  = content:WaitForChild("RowsScroll")
local rowTemplate = rowsScroll:WaitForChild("RowTemplate")

local Events             = ReplicatedStorage:WaitForChild("Events")
local RewardSync         = Events:WaitForChild("RewardSync")
local RewardClaim        = Events:WaitForChild("RewardClaim")
local RewardRequestSync  = Events:WaitForChild("RewardRequestSync")
local NotifyPlayer       = Events:WaitForChild("NotifyPlayer")

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

-- Reward image ids (fill in your assets). Pattern text is matched against the
-- server's `rewards` string.
-- IMPORTANT: These reward images are PLACEHOLDER asset ids. They will NOT show
-- until you replace each `rbxassetid://...` with a REAL asset id you uploaded.
-- (letter = reveal-letter icon, word = reveal-word icon, cash = cash icon,
--  chair = random-chair icon.)
local REWARD_IMAGES = {
	letter_1 = "rbxassetid://REVEAL_LETTER_1",
	letter_2 = "rbxassetid://REVEAL_LETTER_2",
	letter_3 = "rbxassetid://REVEAL_LETTER_3",
	word_1   = "rbxassetid://REVEAL_WORD_1",
	word_2   = "rbxassetid://REVEAL_WORD_2",
	word_3   = "rbxassetid://REVEAL_WORD_3",
	cash_100 = "rbxassetid://CASH_100",
	cash_300 = "rbxassetid://CASH_300",
	cash_500 = "rbxassetid://CASH_500",
	cash_1000 = "rbxassetid://CASH_1000",
	chair    = "rbxassetid://RANDOM_CHAIR",
}
local REWARD_PATTERNS = {
	{ pattern = "+1 Reveal Letter", image = "letter_1" },
	{ pattern = "+2 Reveal Letter", image = "letter_2" },
	{ pattern = "+3 Reveal Letter", image = "letter_3" },
	{ pattern = "+1 Reveal Word",   image = "word_1" },
	{ pattern = "+2 Reveal Word",   image = "word_2" },
	{ pattern = "+3 Reveal Word",   image = "word_3" },
	{ pattern = "+$100",            image = "cash_100" },
	{ pattern = "+$300",            image = "cash_300" },
	{ pattern = "+$500",            image = "cash_500" },
	{ pattern = "+$1000",           image = "cash_1000" },
	{ pattern = "Random Chair",     image = "chair" },
}

local payload   = nil
local activeCat = "playtime"
local isOpen    = false
-- Live timer tracking so playtime/daily countdown actually count while open.
local syncedAt = os.clock()
local syncedPlaytime = 0
local syncedDaily = 0

local function requestSync()
	RewardRequestSync:FireServer()
end

local function setMsg(text)
	local msg = root:FindFirstChild("MsgLbl")
	if msg then
		msg.Text = text
		task.delay(3, function()
			if msg then msg.Text = "" end
		end)
	end
end

local function clearRows()
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
		-- Not following yet: the button prompts them to follow the owner.
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
	local clone = rowTemplate:Clone()
	clone.Visible = true
	clone.Name = "Row_" .. tostring(row.id or idx)

	local left = clone:FindFirstChild("LeftLbl")
	if left then
		if categoryId == "playtime" then left.Text = row.left or ""
		elseif categoryId == "daily" then left.Text = "Day " .. tostring(idx)
		elseif categoryId == "group" then left.Text = "Group"
		elseif categoryId == "vipdaily" then left.Text = "VIP"
		elseif categoryId == "robuxspent" then left.Text = "R$" .. tostring(row.left or "")
		elseif categoryId == "social" then left.Text = row.left or ""
		end
	end

	local container = clone:FindFirstChild("RewardsContainer")
	local template = container and container:FindFirstChild("ImageTemplate")
	if template and template:IsA("ImageLabel") then
		local keys = parseRewardImages(row.rewards)
		-- Show up to 3 reward icons (clone the template).
		template.Visible = false
		for i, key in ipairs(keys) do
			local img = template:Clone()
			img.Visible = true
			img.Image = REWARD_IMAGES[key] or key
			img.Position = UDim2.new(0, (i - 1) * 34, 0.5, -16)
			img.Size = UDim2.new(0, 32, 0, 32)
			img.Parent = container
			if i >= 3 then break end
		end
	end

	local claim = clone:FindFirstChild("ClaimBtn")
	if claim and claim:IsA("TextButton") then
		styleClaim(claim, row, categoryId)
		claim.MouseButton1Click:Connect(function()
			if categoryId == "social" and not row.ready and not row.claimed then
				-- Not following: tell them to follow the owner, then claim.
				setMsg("Follow " .. (row.devUsername or "the owner") .. " on Roblox to claim!")
				return
			end
			if row.ready and not row.claimed then
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

local function formatTime(secs)
	secs = math.max(0, math.floor(secs))
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

-- Compute current playtime seconds (synced base + elapsed since sync).
local function livePlaytime()
	return syncedPlaytime + (os.clock() - syncedAt)
end

-- Compute current daily countdown (synced base - elapsed since sync).
local function liveDaily()
	return math.max(0, syncedDaily - (os.clock() - syncedAt))
end

local function refreshSubtitle()
	if not payload then subLbl.Text = "Waiting for server sync..."; return end
	if activeCat == "robuxspent" then
		subLbl.Text = "Total Robux spent: R$" .. tostring(payload.robuxSpentTotal or 0)
	elseif activeCat == "playtime" then
		subLbl.Text = "Played for " .. formatTime(livePlaytime())
	elseif activeCat == "daily" then
		local left = liveDaily()
		if left > 0 then
			subLbl.Text = "Next daily in " .. formatTime(left)
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
	titleLbl.Text = CAT_TITLE[activeCat] or "Rewards"
	if not payload then
		subLbl.Text = "Waiting for server sync..."
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
	isOpen = true
	root.Active = true
	UIFX.popIn(root) -- intro animation
	requestSync()
	render()
end

local function onClose()
	if not isOpen then return end
	isOpen = false
	root.Active = false
	UIFX.popOut(root) -- outro animation (hides when done)
end

for btnName, cat in pairs(TAB_TO_CAT) do
	local btn = leftTabs:FindFirstChild(btnName)
	if btn and btn:IsA("TextButton") then
		btn.MouseButton1Click:Connect(function()
			selectCategory(cat)
		end)
	end
end

closeBtn.MouseButton1Click:Connect(onClose)

RewardSync.OnClientEvent:Connect(function(newPayload)
	if type(newPayload) ~= "table" then return end
	payload = newPayload
	-- Store timer bases for live counting.
	syncedAt = os.clock()
	syncedPlaytime = tonumber(newPayload.totalPlaytime) or 0
	syncedDaily = tonumber(newPayload.dailyCountdown) or 0
	if isOpen then render() end
end)

-- Live ticker: while the rewards window is open, keep playtime/daily counting.
game:GetService("RunService").Heartbeat:Connect(function()
	if isOpen and (activeCat == "playtime" or activeCat == "daily") then
		refreshSubtitle()
	end
end)

NotifyPlayer.OnClientEvent:Connect(function(info)
	if type(info) == "table" and info.message then
		setMsg(info.message)
	end
end)

-- The "+" buttons on StatsPanel open this via _G.RewardsAPI.
local RewardsAPI = {}
function RewardsAPI.open()
	onOpen()
end
function RewardsAPI.isAvailable()
	return root ~= nil
end
function RewardsAPI.isOpen()
	return isOpen
end
_G.RewardsAPI = RewardsAPI

requestSync()
