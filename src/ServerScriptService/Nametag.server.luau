--[[
	Nametag.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService (e.g. inside
	your "Scripts" folder). Uses a **BillboardGui template** you build.

	REQUIRED TEMPLATE
	Create a BillboardGui named `Nametag` INSIDE this script (or as a child of the
	script's object). Typical structure:
		Nametag  (BillboardGui)
		  ├── PlayerName  (TextLabel)   -- the player's name
		  └── Icons  (Frame)            -- optional icon row
		        ├── Premium  (ImageLabel, Visible=false)
		        ├── Owner    (ImageLabel, Visible=false)
		        └── Admin    (ImageLabel, Visible=false)

	ADDING THE WIN STREAK
	Option A: add a TextLabel named `Streak` anywhere inside the template (e.g. a
	child of `Icons`) - the script sets its text to "🔥10".
	Option B: if no `Streak` label exists, the script auto-creates one (a small
	"🔥N" label under the name). No manual setup needed for Option B.

	Set the template's size/StudsOffset/AlwaysOnTop in Studio to taste.
]]

local PlayersService = game:GetService("Players")

local NametagSettings = {
	ShowsDisplayName = false,
	DisplayPremium = true,
	DisplayOwner = true,
	DisplayAdmins = {
		true,
		AdminList = { "TheCoolBaconHairIsMe", "AnotherUsername" },
	},
}

-- The template sits inside this script (a child named "Nametag").
local Template = script:FindFirstChild("Nametag")

local function setStreak(label, value)
	if label then
		label.Text = "🔥" .. (value or 0)
	end
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
		Tag.Size = UDim2.new(0, 160, 0, 50)
		Tag.StudsOffset = Vector3.new(0, 3.2, 0)
		Tag.AlwaysOnTop = true
		Tag.MaxDistance = 300
	end

	-- Player name.
	local Text = Player.Name
	if NametagSettings.ShowsDisplayName then
		Text = Player.DisplayName
	end
	local nameLabel = Tag:FindFirstChild("PlayerName")
	if nameLabel then
		nameLabel.Text = Text
	else
		nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlayerName"
		nameLabel.Size = UDim2.new(1, 0, 0, 30)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = Text
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.Parent = Tag
	end

	-- Icons (Premium / Owner / Admin) - only if the template has an Icons frame.
	local Icons = Tag:FindFirstChild("Icons")
	if Icons then
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

	-- WIN STREAK ("🔥N"). Reuse a template child named "Streak" if present,
	-- otherwise auto-create one.
	local StreakLabel = Tag:FindFirstChild("Streak")
	if not StreakLabel then
		StreakLabel = Instance.new("TextLabel")
		StreakLabel.Name = "Streak"
		StreakLabel.Size = UDim2.new(1, 0, 0, 24)
		StreakLabel.Position = UDim2.new(0, 0, 1, 0)
		StreakLabel.BackgroundTransparency = 1
		StreakLabel.Font = Enum.Font.GothamBlack
		StreakLabel.TextColor3 = Color3.fromRGB(255, 150, 40)
		StreakLabel.TextScaled = true
		StreakLabel.TextStrokeTransparency = 0.4
		StreakLabel.Parent = Tag
	end

	local leaderstats = Player:WaitForChild("leaderstats", 10)
	local streakVal = leaderstats and leaderstats:FindFirstChild("Streak")
	setStreak(StreakLabel, streakVal and streakVal.Value or 0)
	if streakVal then
		streakVal.Changed:Connect(function()
			setStreak(StreakLabel, streakVal.Value)
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
