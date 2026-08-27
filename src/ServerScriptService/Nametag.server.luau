--[[
	Nametag.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService (e.g. inside
	your "Scripts" folder). Uses a **BillboardGui template** you build.

	REQUIRED TEMPLATE (optional) - a BillboardGui named `Nametag` as a child of
	this script:
		Nametag  (BillboardGui)
		  ├── PlayerName  (TextLabel)          -- player's name
		  ├── Icons  (Frame)                   -- optional icon row
		  │     ├── Premium  (ImageLabel, Visible=false)
		  │     ├── Owner    (ImageLabel, Visible=false)
		  │     └── Admin    (ImageLabel, Visible=false)
		  └── StreakRow  (Frame)               -- optional streak row
		        ├── StreakIcon (ImageLabel)     -- the milestone icon
		        └── Streak     (TextLabel)      -- the number ("10")

	If you don't build a template (or leave out StreakRow), the script auto-creates
	everything needed. All auto-created sizes/positions are in SCALE (never offset).

	STREAK + MILESTONES
	The streak shows as an icon + number (e.g. a flame + "10"). As the player's
	streak passes each milestone threshold in `StreakMilestones`, the ICON swaps to
	that milestone's `icon` image. Fill in your own image IDs. The first milestone
	(threshold 1) is the default flame; later ones are the "cooler" icons.
]]

local PlayersService = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local PlayerPerks = require(ServerStorage.Modules.PlayerPerks)
local VIP_PASS_ID = PlayerPerks.IDS.VIP
local VIP_PREFIX = "[VIP] "
local VIP_COLOR = Color3.fromRGB(255, 210, 60) -- the [VIP] tag is yellow

-- VIP nametag state: Player -> { label = TextLabel, base = plain name }
-- (Roblox system chat can't be modified by game code, so the [VIP] tag is
-- shown on the overhead nametag instead - visible to everyone in the game.)
local vipTags = {}

local function applyVipTag(Player)
	local t = vipTags[Player]
	if t and t.label and t.label.Parent then
		t.label.Text = VIP_PREFIX .. t.base
		t.label.TextColor3 = VIP_COLOR
		t.label.TextStrokeColor3 = Color3.fromRGB(90, 60, 0)
	end
end

-- Live update: the tag flips on the moment VIP is bought via the in-game
-- prompt (VIP can't be un-owned, so it never flips back off).
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(Player, passId, wasPurchased)
	if wasPurchased and passId == VIP_PASS_ID then
		applyVipTag(Player)
	end
end)

-- Purchases made OUTSIDE the in-game prompt (the game's shop page, mobile
-- store) never fire that event, so re-check VIP players without a tag
-- every 60s - the tag only ever turns on.
task.spawn(function()
	while true do
		task.wait(60)
		for Player, t in pairs(vipTags) do
			if t.label and t.label.Parent and string.sub(t.label.Text, 1, #VIP_PREFIX) ~= VIP_PREFIX then
				local ok, isVip = pcall(function()
					return PlayerPerks.owns(Player, "VIP")
				end)
				if ok and isVip then
					applyVipTag(Player)
				end
			end
		end
	end
end)

local NametagSettings = {
	ShowsDisplayName = false,
	DisplayPremium = true,
	DisplayOwner = true,
	DisplayAdmins = {
		true,
		AdminList = { "TheCoolBaconHairIsMe", "AnotherUsername" },
	},
}

-- Streak milestone icons (lowest threshold to highest). The first is the
-- default. The script picks the highest milestone whose threshold you've reached.
-- Replace the placeholder rbxassetid://... with your icons.
local StreakMilestones = {
	{ threshold = 1,  icon = "rbxassetid://DEFAULT_FIRE" },
	{ threshold = 10, icon = "rbxassetid://COOL_FIRE_10" },
}

-- The template sits inside this script (a child named "Nametag").
local Template = script:FindFirstChild("Nametag")

-- Pick the milestone icon for a streak value (highest threshold reached).
local function milestoneFor(value)
	local chosen = StreakMilestones[1]
	for _, m in ipairs(StreakMilestones) do
		if value >= m.threshold then
			chosen = m
		end
	end
	return chosen
end

-- Set the streak display (icon + number) for a value. Unhides the parent
-- StreakRow frame (it may be inside the Icons frame and set Visible=false).
local function setStreak(iconLabel, textLabel, value)
	value = value or 0
	if iconLabel then
		local m = milestoneFor(value)
		iconLabel.Image = m and m.icon or ""
		iconLabel.Visible = value > 0
	end
	if textLabel then
		textLabel.Text = tostring(value)
		textLabel.Visible = value > 0
	end
	-- Show/hide the row that holds them, if one exists.
	local row = iconLabel and iconLabel.Parent or (textLabel and textLabel.Parent)
	if row and row:IsA("GuiObject") and row.Name == "StreakRow" then
		row.Visible = value > 0
	end
end

-- Find a descendant by name (recursive), so it works even if the label is
-- nested inside an Icons/StreakRow frame.
local function findDesc(tag, name)
	return tag:FindFirstChild(name, true)
end

local function LoadOverhead(Player, Character)
	repeat
		task.wait()
	until not Character or Character:FindFirstChild("Head")
	local head = Character:FindFirstChild("Head")
	if not head then
		return
	end
	Character:WaitForChild("Humanoid")

	-- Build the tag: clone the template, or fall back to a simple one.
	local Tag
	if Template and Template:IsA("BillboardGui") then
		Tag = Template:Clone()
	else
		Tag = Instance.new("BillboardGui")
		Tag.Name = "Nametag"
		Tag.Size = UDim2.new(0.4, 0, 0.08, 0) -- scale-based
		Tag.StudsOffset = Vector3.new(0, 3.2, 0)
		Tag.AlwaysOnTop = true
		Tag.MaxDistance = 300
	end

	-- Player name. The [VIP] prefix is added ASYNC below (the ownership check
	-- yields, so we don't hold up the whole tag build on it).
	local baseName = Player.Name
	if NametagSettings.ShowsDisplayName then
		baseName = Player.DisplayName
	end
	local nameLabel = findDesc(Tag, "PlayerName")
	if nameLabel then
		nameLabel.Text = baseName
	else
		nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlayerName"
		nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
		nameLabel.Position = UDim2.new(0, 0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = baseName
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Parent = Tag
	end

	-- [VIP] tag for VIP gamepass owners (check on load + live on purchase).
	vipTags[Player] = { label = nameLabel, base = baseName }
	task.spawn(function()
		local ok, isVip = pcall(function()
			return PlayerPerks.owns(Player, "VIP")
		end)
		if ok and isVip then
			applyVipTag(Player)
		end
	end)

	-- Icons (Premium / Owner / Admin) - only if the template has an Icons frame.
	local Icons = findDesc(Tag, "Icons")
	if Icons and Icons:IsA("GuiObject") then
		if NametagSettings.DisplayPremium and Player.MembershipType == Enum.MembershipType.Premium then
			local prem = Icons:FindFirstChild("Premium")
			if prem then
				prem.Visible = true
			end
		end
		if NametagSettings.DisplayOwner then
			local success, result = pcall(function()
				return game.CreatorType == Enum.CreatorType.Group
					and Player:GetRolesInGroupAsync(game.CreatorId) ~= nil
					or game.CreatorId == Player.UserId
			end)
			if success and result then
				local owner = Icons:FindFirstChild("Owner")
				if owner then
					owner.Visible = true
				end
			end
		end
		if NametagSettings.DisplayAdmins[1] then
			local isAdmin = false
			for _, b in ipairs(NametagSettings.DisplayAdmins.AdminList) do
				if Player.Name == b or Player.DisplayName == b then
					isAdmin = true
					break
				end
			end
			if isAdmin then
				local admin = Icons:FindFirstChild("Admin")
				if admin then
					admin.Visible = true
				end
			end
		end
	end

	-- STREAK: look for an existing StreakIcon + Streak (anywhere in the tag).
	local StreakIcon = findDesc(Tag, "StreakIcon")
	local StreakLabel = findDesc(Tag, "Streak")

	-- If neither exists, auto-create a StreakRow (icon + number) in SCALE.
	if not StreakIcon and not StreakLabel then
		local row = Instance.new("Frame")
		row.Name = "StreakRow"
		row.Size = UDim2.new(1, 0, 0.4, 0)
		row.Position = UDim2.new(0, 0, 0.6, 0) -- below the name
		row.BackgroundTransparency = 1
		row.Parent = Tag

		StreakIcon = Instance.new("ImageLabel")
		StreakIcon.Name = "StreakIcon"
		StreakIcon.Size = UDim2.new(0.3, 0, 0.8, 0)
		StreakIcon.Position = UDim2.new(0.1, 0, 0.1, 0)
		StreakIcon.BackgroundTransparency = 1
		StreakIcon.ScaleType = Enum.ScaleType.Fit
		StreakIcon.Parent = row

		StreakLabel = Instance.new("TextLabel")
		StreakLabel.Name = "Streak"
		StreakLabel.Size = UDim2.new(0.6, 0, 0.8, 0)
		StreakLabel.Position = UDim2.new(0.4, 0, 0.1, 0)
		StreakLabel.BackgroundTransparency = 1
		StreakLabel.Font = Enum.Font.GothamBlack
		StreakLabel.TextColor3 = Color3.fromRGB(255, 170, 50)
		StreakLabel.TextScaled = true
		StreakLabel.TextStrokeTransparency = 0.4
		StreakLabel.Parent = row
	end

	-- Hide the streak entirely at 0 (so it doesn't show "0").
	if StreakIcon then
		StreakIcon.Visible = false
	end
	if StreakLabel then
		StreakLabel.Visible = false
	end

	-- Wire it up to Stats.Streak (hidden from the leaderboard, updates live).
	local stats = Player:WaitForChild("Stats", 10)
	local streakVal = stats and stats:FindFirstChild("Streak")
	setStreak(StreakIcon, StreakLabel, streakVal and streakVal.Value or 0)
	if streakVal then
		streakVal.Changed:Connect(function()
			setStreak(StreakIcon, StreakLabel, streakVal.Value)
		end)
	end

	-- Hide the default Roblox nametag; place ours on the head.
	local humanoid = Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	Tag.Adornee = head
	Tag.Parent = Character
end

PlayersService.PlayerAdded:Connect(function(Player)
	Player.CharacterAdded:Connect(function(Character)
		LoadOverhead(Player, Character)
	end)
	if Player.Character then
		LoadOverhead(Player, Player.Character)
	end
end)
