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
	  * VISIT   (blue, enabled)    -- social: press to "visit" an owner
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
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local gui     = player:WaitForChild("PlayerGui")
local gameGui = gui:WaitForChild("GameUI")

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
local SocialVisit        = Events:WaitForChild("SocialVisit")
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
local REWARD_IMAGES = {
	letter_1 = "rbxassetid://REVEAL_LETTER_1",
	letter_2 = "rbxassetid://REVEAL_LETTER_2",
	letter_3 = "rbxassetid://REVEAL_LETTER_3",
	word_1   = "rbxassetid://REVEAL_WORD_1",
	word_2   = "rbxassetid://REVEAL_WORD_2",
	word_3   = "rbxassetid://REVEAL_WORD_3",
}
local REWARD_PATTERNS = {
	{ pattern = "+1 Reveal Letter", image = "letter_1" },
	{ pattern = "+2 Reveal Letter", image = "letter_2" },
	{ pattern = "+3 Reveal Letter", image = "letter_3" },
	{ pattern = "+1 Reveal Word",   image = "word_1" },
	{ pattern = "+2 Reveal Word",   image = "word_2" },
	{ pattern = "+3 Reveal Word",   image = "word_3" },
}

local payload   = nil
local activeCat = "playtime"
local isOpen    = false

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
		btn.Text = "VISIT"
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
				pcall(function()
					SocialService:PromptGameInvite(player)
				end)
				SocialVisit:FireServer(row.id)
				setMsg("Visited! Wait a moment, then claim.")
				task.delay(1, requestSync)
				task.delay(6, requestSync)
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

local function refreshSubtitle()
	if not payload then subLbl.Text = "Waiting for server sync..."; return end
	if activeCat == "robuxspent" then
		subLbl.Text = "Total Robux spent: R$" .. tostring(payload.robuxSpentTotal or 0)
	elseif activeCat == "playtime" then
		subLbl.Text = "You played for " .. tostring(math.floor((payload.totalPlaytime or 0) / 60)) .. " minutes"
	elseif activeCat == "daily" then
		subLbl.Text = (payload.dailyCountdown or 0) > 0 and "Ready in a few hours" or "Daily reward ready"
	elseif activeCat == "social" then
		subLbl.Text = "Visit the owners and claim your rewards!"
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
	root.Visible = true
	root.Active = true
	isOpen = true
	requestSync()
	render()
end

local function onClose()
	root.Visible = false
	root.Active = false
	isOpen = false
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
	if isOpen then render() end
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
_G.RewardsAPI = RewardsAPI

requestSync()
