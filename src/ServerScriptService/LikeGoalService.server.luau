--[[
	LikeGoalService.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	A "like the game" goal: while the game's Roblox LIKE count climbs toward
	LIKE_GOAL, the bar on the LikeGoal part fills up and the label shows the
	progress ("0/10"). When the goal is reached, the Collect ProximityPrompt
	on the part turns ON and every player can claim the reward (x2 Reveal
	Words) exactly ONCE.

	YOU can change the goal and the reward in the CONFIG block below.

	ANTI-EXPLOIT
	* The like count is fetched SERVER-SIDE from Roblox's own API
	  (games.roblox.com) - the client never sends or controls it, so a hacker
	  cannot fake the goal.
	* The Collect prompt's Enabled is only ever toggled by this script.
	* The claim handler re-verifies the goal with a fresh API check AND
	  enforces once-per-player, persisted in the ProfileStore DataStore -
	  rejoining cannot re-claim, and firing the prompt from an exploit just
	  hits the same server checks.

	WORKSPACE SETUP (the part you built):
		Workspace.LikeGoal (Part)
		├── SurfaceGui (SurfaceGui)
		│   └── Frame (Frame)
		│       └── Bar (Frame)
		│           ├── Fill (Frame)         -- Size.X animates 0 -> 1 as we near the goal
		│           └── LikeCount (TextLabel) -- "0/10"
		└── Collect (ProximityPrompt)       -- Enabled=false until the goal is reached
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local ProfileStore = require(ServerStorage.Modules.ProfileStore)
local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))

local Events = ReplicatedStorage:WaitForChild("Events")
local NotifyPlayer = Events:WaitForChild("NotifyPlayer")

-------------------------------------------------------------------------------
-- CONFIG (edit me)
-------------------------------------------------------------------------------
local LIKE_GOAL = 10                 -- <- change your like goal HERE
local REWARD_USES = 2                -- <- reward: this many Reveal Word uses
local CHECK_INTERVAL = 60            -- seconds between like-count API checks

-------------------------------------------------------------------------------
-- FIND THE PART (fail loudly if missing)
-------------------------------------------------------------------------------
local goalPart = Workspace:WaitForChild("LikeGoal", 15)
if not goalPart then
	warn("[LikeGoalService] Workspace.LikeGoal part not found - like goal disabled.")
	return
end

local surface = goalPart:FindFirstChild("SurfaceGui")
	or goalPart:FindFirstChildWhichIsA("SurfaceGui", true)
local fill = surface and surface:FindFirstChild("Fill", true)
local likeLabel = surface and surface:FindFirstChild("LikeCount", true)

local collect = goalPart:FindFirstChild("Collect")
if not (collect and collect:IsA("ProximityPrompt")) then
	collect = goalPart:FindFirstChildWhichIsA("ProximityPrompt", true)
end
if not collect or not collect:IsA("ProximityPrompt") then
	warn("[LikeGoalService] LikeGoal.Collect (ProximityPrompt) not found - collecting disabled.")
	return
end
if not (fill or likeLabel) then
	warn("[LikeGoalService] LikeGoal SurfaceGui Fill/LikeCount not found - bar visuals disabled.")
end

-- The script owns the prompt's Enabled state - start locked.
collect.Enabled = false

-------------------------------------------------------------------------------
-- LIKE COUNT (Roblox API, server-side only)
-------------------------------------------------------------------------------
local PLACE_DETAILS_URL = "https://games.roblox.com/v1/games/multiget-place-details?placeIds=%d"
local VOTES_URL = "https://games.roblox.com/v1/games/%d/votes"

local cachedUniverseId = nil
local lastLikes = nil
local lastFetchedAt = 0

local function jsonGet(url)
	local ok, response = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not ok or type(response) ~= "string" then
		return nil
	end
	local ok2, decoded = pcall(function()
		return HttpService:JSONDecode(response)
	end)
	if ok2 and type(decoded) == "table" then
		return decoded
	end
	return nil
end

local function getUniverseId()
	if cachedUniverseId then
		return cachedUniverseId
	end
	local json = jsonGet(string.format(PLACE_DETAILS_URL, game.PlaceId))
	if json and type(json.data) == "table" and #json.data > 0 and type(json.data[1]) == "table" then
		cachedUniverseId = tonumber(json.data[1].universeId)
	end
	return cachedUniverseId
end

-- Fresh fetch; on any failure keeps the last known value (never nil->junk).
local function fetchLikes()
	local universeId = getUniverseId()
	if not universeId then
		return lastLikes
	end
	local json = jsonGet(string.format(VOTES_URL, universeId))
	if json and type(json.data) == "table" then
		local upVotes
		if json.data.upVotes ~= nil then
			upVotes = json.data.upVotes
		elseif #json.data > 0 and type(json.data[1]) == "table" then
			upVotes = json.data[1].upVotes
		end
		local likes = tonumber(upVotes)
		if likes then
			lastLikes = likes
			lastFetchedAt = os.clock()
		end
	end
	return lastLikes
end

-------------------------------------------------------------------------------
-- BAR VISUALS
-------------------------------------------------------------------------------
local function updateVisual(likes)
	local shown = likes or 0
	local ratio = 0
	if LIKE_GOAL > 0 then
		ratio = math.clamp(shown / LIKE_GOAL, 0, 1)
	end
	if likeLabel and likeLabel:IsA("TextLabel") then
		likeLabel.Text = NumberFormat.commas(shown) .. "/" .. NumberFormat.commas(LIKE_GOAL)
	end
	if fill and fill:IsA("GuiObject") then
		local cur = fill.Size
		-- Keep the Fill's Y size, animate the X toward the goal.
		TweenService:Create(
			fill,
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(ratio, cur.X.Offset, cur.Y.Scale, cur.Y.Offset) }
		):Play()
	end
end

-------------------------------------------------------------------------------
-- CLAIM (once per player, persisted, server-verified)
-------------------------------------------------------------------------------
local claimedThisSession = {} -- userId -> true

local function hasClaimed(player)
	if claimedThisSession[player.UserId] then
		return true
	end
	local saved = ProfileStore.load(player.UserId).likegoal
	if type(saved) == "table" and saved.claimed == true then
		claimedThisSession[player.UserId] = true
		return true
	end
	return false
end

local function markClaimed(player)
	claimedThisSession[player.UserId] = true
	ProfileStore.save(player.UserId)
end

local function notify(player, title, message, kind)
	NotifyPlayer:FireClient(player, {
		title = title or "Like Goal",
		message = message,
		kind = kind or "info",
		duration = 4,
	})
end

collect.Triggered:Connect(function(player)
	-- 1) Re-verify the goal with a FRESH server-side like count.
	local likes = fetchLikes()
	if not likes or likes < LIKE_GOAL then
		notify(player, "Like Goal", "The goal hasn't been reached yet!", "warn")
		return
	end

	-- 2) Once per player (persisted across sessions).
	if hasClaimed(player) then
		notify(player, "Like Goal", "You already claimed this reward!", "info")
		return
	end

	-- 3) Grant the reward + persist the claim.
	markClaimed(player)

	local stats = player:FindFirstChild("Stats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "Stats"
		stats.Parent = player
	end
	local uses = stats:FindFirstChild("RevealWordUses")
	if not uses then
		uses = Instance.new("IntValue")
		uses.Name = "RevealWordUses"
		uses.Parent = stats
	end
	uses.Value = uses.Value + REWARD_USES

	-- Stay enabled: other players can still claim their own one-time reward.
	collect.Enabled = true

	notify(player, "Like Goal Reached!",
		"The game hit " .. NumberFormat.commas(LIKE_GOAL) .. " likes! You got +"
		.. REWARD_USES .. " Reveal Words.", "success")
end)

-------------------------------------------------------------------------------
-- JOIN / LEAVE (persist the claim flag in the shared profile)
-------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	if hasClaimed(player) then
		claimedThisSession[player.UserId] = true
	end
	ProfileStore.setSection(player.UserId, "likegoal", function()
		if claimedThisSession[player.UserId] then
			return { claimed = true }
		end
		return nil
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	claimedThisSession[player.UserId] = nil
end)

-------------------------------------------------------------------------------
-- MAIN LOOP: check the like count, update the bar, unlock when reached
-------------------------------------------------------------------------------
task.spawn(function()
	while true do
		local likes = fetchLikes()
		if likes ~= nil then
			updateVisual(likes)
			if likes >= LIKE_GOAL then
				collect.Enabled = true
			end
		end
		task.wait(CHECK_INTERVAL)
	end
end)
