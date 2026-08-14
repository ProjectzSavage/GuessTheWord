--[[
	RewardsController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives the "Rewards" window (RewardsF) with left-side tabs, a content area,
	and reward rows. It builds the reward rows from the REWARDS config below by
	cloning your RowTemplate (ImageTemplate reward icon + ClaimBtn).

	REQUIRED UI - the `RewardsF` hierarchy (build it in a ScreenGui, e.g.
	"Currency" or "RewardsGui"). See docs/UI_HIERARCHY.md for the full tree:
		RewardsF
		  ├── Content
		  │     ├── CategoryTitle
		  │     ├── CategorySubtitle
		  │     └── RowsScroll
		  │           └── RowTemplate
		  │                 ├── LeftLbl
		  │                 ├── RewardsContainer ── ImageTemplate
		  │                 └── ClaimBtn
		  ├── LeftTabs
		  │     ├── DailyBtn   GroupBtn   PlaytimeBtn
		  │     ├── RobuxSpentBtn   SocialBtn   VipDailyBtn
		  ├── CloseBtn
		  ├── MsgLbl
		  └── TitleLbl

	HOW TO ADD REWARDS
	Edit the REWARDS table below. Each tab maps a button name to a list of reward
	rows: { label (requirement text), reward (icon image id), claimed (bool) }.
	Fill in your reward image IDs.
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- REWARD CONFIG - edit here (image ids are placeholders - fill yours in).
-- ---------------------------------------------------------------------------
local REWARDS = {
	Daily = {
		{ label = "Log in for 1 day",    reward = "rbxassetid://DAILY_1", claimed = false },
		{ label = "Log in for 3 days",   reward = "rbxassetid://DAILY_3", claimed = false },
		{ label = "Log in for 7 days",   reward = "rbxassetid://DAILY_7", claimed = false },
	},
	Group = {
		{ label = "Join the group",      reward = "rbxassetid://GROUP_JOIN", claimed = false },
	},
	Playtime = {
		{ label = "Play for 1 hour",     reward = "rbxassetid://TIME_1H", claimed = false },
		{ label = "Play for 5 hours",    reward = "rbxassetid://TIME_5H", claimed = false },
	},
	RobuxSpent = {
		{ label = "Spend 100 Robux",     reward = "rbxassetid://RBX_100", claimed = false },
	},
	Social = {
		{ label = "Follow on X",         reward = "rbxassetid://SOCIAL_X", claimed = false },
		{ label = "Subscribe on YouTube",reward = "rbxassetid://SOCIAL_YT", claimed = false },
	},
	VipDaily = {
		{ label = "VIP daily reward",    reward = "rbxassetid://VIP_DAILY", claimed = false },
	},
}

-- Button -> tab name map (as named in the LeftTabs frame).
local TAB_MAP = {
	DailyBtn = "Daily",
	GroupBtn = "Group",
	PlaytimeBtn = "Playtime",
	RobuxSpentBtn = "RobuxSpent",
	SocialBtn = "Social",
	VipDailyBtn = "VipDaily",
}

local TITLE_MAP = {
	Daily = "Daily Rewards",
	Group = "Group Rewards",
	Playtime = "Playtime Rewards",
	RobuxSpent = "Robux Milestones",
	Social = "Social Rewards",
	VipDaily = "VIP Rewards",
}

local SUBTITLE_MAP = {
	Daily = "Log in each day to earn rewards!",
	Group = "Rewards for being part of the group.",
	Playtime = "Earn rewards the longer you play.",
	RobuxSpent = "Milestones for supporting the game.",
	Social = "Follow us to unlock bonus rewards.",
	VipDaily = "Exclusive daily rewards for VIPs.",
}

-------------------------------------------------------------------------------
-- FIND UI
-------------------------------------------------------------------------------
-- Search the PlayerGui for the RewardsF window.
local RewardsF
local function findRewardsUI()
	for _, child in PlayerGui:GetChildren() do
		local rf = child:FindFirstChild("RewardsF", true)
		if rf then
			return rf
		end
	end
	return nil
end

RewardsF = findRewardsUI()

-------------------------------------------------------------------------------
-- BUILD ROWS
-------------------------------------------------------------------------------
local function clearRows(scroll)
	for _, c in scroll:GetChildren() do
		if c.Name == "RewardRow" then
			c:Destroy()
		end
	end
end

-- Clone RowTemplate and fill one reward row.
local function makeRow(scroll, rowTemplate, data)
	local row = rowTemplate:Clone()
	row.Name = "RewardRow"
	row.Visible = true

	local left = row:FindFirstChild("LeftLbl")
	if left then
		left.Text = data.label
	end

	local container = row:FindFirstChild("RewardsContainer")
	local img = container and container:FindFirstChild("ImageTemplate")
	if img then
		img.Image = data.reward
		img.Visible = true
	end

	local claim = row:FindFirstChild("ClaimBtn")
	if claim then
		claim.Visible = true
		-- Already claimed?
		claim.Text = data.claimed and "Claimed" or "Claim"
		claim.Interactable = not data.claimed
		claim.Activated:Connect(function()
			if not data.claimed then
				data.claimed = true
				claim.Text = "Claimed"
				claim.Interactable = false
				setMsg("Claimed!")
			end
		end)
	end

	row.Parent = scroll
	return row
end

-- Show a tab's rewards.
local function showTab(tabName)
	if not RewardsF then
		return
	end
	local content = RewardsF:FindFirstChild("Content")
	local title = content and content:FindFirstChild("CategoryTitle")
	local subtitle = content and content:FindFirstChild("CategorySubtitle")
	local scroll = content and content:FindFirstChild("RowsScroll")

	if title then
		title.Text = TITLE_MAP[tabName] or tabName
	end
	if subtitle then
		subtitle.Text = SUBTITLE_MAP[tabName] or ""
	end

	if scroll then
		clearRows(scroll)
		local rowTemplate = scroll:FindFirstChild("RowTemplate")
		for _, data in REWARDS[tabName] or {} do
			makeRow(scroll, rowTemplate, data)
		end
	end
end

local function setMsg(text)
	if RewardsF then
		local msg = RewardsF:FindFirstChild("MsgLbl")
		if msg then
			msg.Text = text
			task.delay(3, function()
				if msg then
					msg.Text = ""
				end
			end)
		end
	end
end

-------------------------------------------------------------------------------
-- WIRE UI
-------------------------------------------------------------------------------
if RewardsF then
	local leftTabs = RewardsF:FindFirstChild("LeftTabs")
	if leftTabs then
		for btnName, tabName in pairs(TAB_MAP) do
			local btn = leftTabs:FindFirstChild(btnName)
			if btn and btn:IsA("GuiButton") then
				btn.Activated:Connect(function()
					showTab(tabName)
				end)
			end
		end
	end

	local close = RewardsF:FindFirstChild("CloseBtn")
	if close then
		close.Activated:Connect(function()
			RewardsF.Visible = false
		end)
	end

	-- Default to the Daily tab.
	RewardsF.Visible = false
	showTab("Daily")
end

-- Expose helpers for the "+" buttons (StatsPanel) to open this window.
local RewardsAPI = {}
function RewardsAPI.open()
	if RewardsF then
		RewardsF.Visible = true
		showTab("Daily")
	end
end
function RewardsAPI.isAvailable()
	return RewardsF ~= nil
end

_G.RewardsAPI = RewardsAPI
