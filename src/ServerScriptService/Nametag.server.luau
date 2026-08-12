--[[
	Nametag.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService (e.g. inside
	your "Scripts" folder).

	PURPOSE
	Puts a small BillboardGui above every player's head showing their name and
	their current win STREAK as "🔥N" (e.g. "TheCoolBaconHairIsMe" + "🔥10").
	The streak updates live from leaderstats.Streak (created by GameManager).

	It is self-contained: the BillboardGui is built in code, so you don't need
	to create any GUI by hand. Tweak the fonts/colors/offsets below to taste.
]]

local Players = game:GetService("Players")

local NAME_BG = Color3.fromRGB(20, 20, 25)
local NAME_TEXT = Color3.new(1, 1, 1)
local STREAK_TEXT = Color3.fromRGB(255, 150, 40) -- warm orange for the flame
local BG_TRANSPARENCY = 0.25
local OFFSET_Y = 3.2 -- how high above the head the tag sits

-- Build a fresh nametag BillboardGui for a character.
local function buildNametag(player)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Nametag"
	bb.Size = UDim2.new(0, 140, 0, 60)
	bb.StudsOffset = Vector3.new(0, OFFSET_Y, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 300
	bb.LightInfluence = 1

	-- Player name label.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundColor3 = NAME_BG
	nameLabel.BackgroundTransparency = BG_TRANSPARENCY
	nameLabel.BorderSizePixel = 0
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = player.Name
	nameLabel.TextColor3 = NAME_TEXT
	nameLabel.TextScaled = true
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Parent = bb

	-- Streak label ("🔥N").
	local streakLabel = Instance.new("TextLabel")
	streakLabel.Name = "Streak"
	streakLabel.Size = UDim2.new(1, 0, 0, 30)
	streakLabel.Position = UDim2.new(0, 0, 0, 30)
	streakLabel.BackgroundTransparency = 1
	streakLabel.Font = Enum.Font.GothamBlack
	streakLabel.Text = "🔥0"
	streakLabel.TextColor3 = STREAK_TEXT
	streakLabel.TextScaled = true
	streakLabel.TextStrokeTransparency = 0.4
	streakLabel.Parent = bb

	return bb, nameLabel, streakLabel
end

local function setStreak(streakLabel, value)
	if streakLabel then
		streakLabel.Text = "🔥" .. (value or 0)
	end
end

local function attach(player, character)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Hide the default player nametag so ours is the only one.
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local bb, nameLabel, streakLabel = buildNametag(player)
	bb.Adornee = head
	bb.Parent = character

	-- Live-update the streak from leaderstats.Streak.
	local leaderstats = player:WaitForChild("leaderstats", 10)
	local streakVal = leaderstats and leaderstats:FindFirstChild("Streak")
	setStreak(streakLabel, streakVal and streakVal.Value or 0)
	if streakVal then
		streakVal.Changed:Connect(function()
			setStreak(streakLabel, streakVal.Value)
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		attach(player, character)
	end)
	if player.Character then
		attach(player, player.Character)
	end
end)
