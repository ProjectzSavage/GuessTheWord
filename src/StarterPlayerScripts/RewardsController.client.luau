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
-- Each reward can grant powerup uses: powerup = "Letter"/"Word", uses = amount.
-- Claiming a reward adds those uses to the player's hidden Stats folder, which
-- the powerup buttons' PriceLbl reflects ("N Use" when they have uses).
-- ---------------------------------------------------------------------------
local REWARDS = {
	Daily = {
		{ label = "Log in for 1 day",    reward = "rbxassetid://DAILY_1", claimed = false, powerup = "Letter", uses = 1 },
		{ label = "Log in for 3 days",   reward = "rbxassetid://DAILY_3", claimed = false, powerup = "Word",   uses = 1 },
		{ label = "Log in for 7 days",   reward = "rbxassetid://DAILY_7", claimed = false, powerup = "Letter", uses = 3 },
	},
	Group = {
		{ label = "Join the group",      reward = "rbxassetid://GROUP_JOIN", claimed = false, powerup = "Letter", uses = 2 },
	},
	Playtime = {
		{ label = "Play for 1 hour",     reward = "rbxassetid://TIME_1H", claimed = false, powerup = "Letter", uses = 2 },
		{ label = "Play for 5 hours",    reward = "rbxassetid://TIME_5H", claimed = false, powerup = "Word", uses = 1 },
	},
	RobuxSpent = {
		{ label = "Spend 100 Robux",     reward = "rbxassetid://RBX_100", claimed = false, powerup = "Word", uses = 2 },
	},
	Social = {
		{ label = "Follow on X",         reward = "rbxassetid://SOCIAL_X", claimed = false, powerup = "Letter", uses = 1 },
		{ label = "Subscribe on YouTube",reward = "rbxassetid://SOCIAL_YT", claimed = false, powerup = "Letter", uses = 2 },
	},
	VipDaily = {
		{ label = "VIP daily reward",    reward = "rbxassetid://VIP_DAILY", claimed = false, powerup = "Letter", uses = 5 },
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
	-- Wait up to 10s for it to appear (rewards frame is inside GameUI).
	for _, child in PlayerGui:GetChildren() do
		local rf = child:FindFirstChild("RewardsF", true)
		if rf then
			return rf
		end
	end
	-- Fallback: wait on GameUI.RewardsF
	local gameUI = PlayerGui:WaitForChild("GameUI", 10)
	return gameUI and gameUI:WaitForChild("RewardsF", 5)
end

RewardsF = findRewardsUI()

-- Forward-declared so makeRow() below can call it (defined further down).
local setMsg

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

-- Grant powerup uses to the player's Stats folder.
local function grantPowerupUses(powerup, uses)
	local stats = player:FindFirstChild("Stats")
	if not stats then
		return
	end
	local useName = (powerup == "Word") and "RevealWordUses" or "RevealLetterUses"
	local val = stats:FindFirstChild(useName)
	if val then
		val.Value = val.Value + (uses or 1)
	end
end

-- Clone RowTemplate and fill one reward row.
local function makeRow(scroll, rowTemplate, data)
	local row = rowTemplate:Clone()
	row.Name = "RewardRow"
	row.Visible = true

	local left = row:WaitForChild("LeftLbl")
	left.Text = data.label

	local container = row:WaitForChild("RewardsContainer")
	local img = container:WaitForChild("ImageTemplate")
	img.Image = data.reward
	img.Visible = true

	local claim = row:WaitForChild("ClaimBtn")
	claim.Visible = true

	local function refreshClaimUI()
		if data.claimed then
			claim.Text = "Claimed"
			claim.Interactable = false
		else
			claim.Text = "Claim"
			claim.Interactable = true
		end
	end
	refreshClaimUI()

	claim.Activated:Connect(function()
		if not data.claimed then
			data.claimed = true
			-- Grant the powerup uses to the player (updates the buttons' PriceLbl).
			if data.powerup then
				grantPowerupUses(data.powerup, data.uses)
			end
			refreshClaimUI()
			setMsg("Claimed! Powerup uses added.")
		end
	end)

	row.Parent = scroll
	return row
end

-- Show a tab's rewards.
local function showTab(tabName)
	if not RewardsF then
		return
	end
	local content = RewardsF:WaitForChild("Content")
	local title = content:WaitForChild("CategoryTitle")
	local subtitle = content:WaitForChild("CategorySubtitle")
	local scroll = content:WaitForChild("RowsScroll")

	title.Text = TITLE_MAP[tabName] or tabName
	subtitle.Text = SUBTITLE_MAP[tabName] or ""

	clearRows(scroll)
	local rowTemplate = scroll:WaitForChild("RowTemplate")
	for _, data in REWARDS[tabName] or {} do
		makeRow(scroll, rowTemplate, data)
	end
end

function setMsg(text)
	if RewardsF then
		local msg = RewardsF:WaitForChild("MsgLbl")
		msg.Text = text
		task.delay(3, function()
			if msg then
				msg.Text = ""
			end
		end)
	end
end

-------------------------------------------------------------------------------
-- WIRE UI
-------------------------------------------------------------------------------
if RewardsF then
	local leftTabs = RewardsF:WaitForChild("LeftTabs")
	for btnName, tabName in pairs(TAB_MAP) do
		local btn = leftTabs:FindFirstChild(btnName)
		if btn and btn:IsA("GuiButton") then
			btn.Activated:Connect(function()
				showTab(tabName)
			end)
		end
	end

	local close = RewardsF:WaitForChild("CloseBtn")
	close.Activated:Connect(function()
		RewardsF.Visible = false
	end)

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
