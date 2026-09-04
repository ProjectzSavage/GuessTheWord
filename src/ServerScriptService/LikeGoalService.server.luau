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
	* The like count is fetched SERVER-SIDE from Roblox's public games API
	  (via the RoProxy mirror, because in-experience HTTP to the classic
	  roblox.com endpoints is blocked) - the client never sends or controls
	  it, so a hacker cannot fake the goal.
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

-- Your game's Roblox UNIVERSE id (a place belongs to one universe). The
-- script tries to auto-resolve it from game.PlaceId, but Roblox now
-- requires auth for that lookup from in-game, so this verified fallback is
-- what actually gets used (place 87837163852448 -> universe 16084134).
local UNIVERSE_ID_FALLBACK = 16084134

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
-- New engine builds default the prompt's line-of-sight check to ON, which
-- can hide the prompt behind terrain or your own character. Collecting a
-- world reward should never require line of sight.
pcall(function()
	collect.RequiresLineOfSight = false
end)

-------------------------------------------------------------------------------
-- LIKE COUNT (Roblox API, server-side only)
-------------------------------------------------------------------------------
-- In-experience HttpService is limited to third-party domains + a small
-- keyed Open Cloud subset (Roblox docs, Sept 2026) - the classic
-- games.roblox.com endpoints below are BLOCKED from the game server
-- ("HttpService is not allowed to access that Roblox resource"). Primary
-- route is therefore the RoProxy mirror of the same public API - the game
-- already trusts roproxy.com for the follow check, and "Allow HTTP
-- Requests" (which the game needs anyway) covers it. The direct roblox.com
-- host stays as a fallback in case Roblox ever allows these endpoints again.
local GAMES_API_HOSTS = {
	"https://games.roproxy.com/v1/games",
	"https://games.roblox.com/v1/games",
}
local PLACE_DETAILS_PATH = "/multiget-place-details?placeIds=%d"
local VOTES_PATH = "/%d/votes"

local cachedUniverseId = nil
local lastLikes = nil
local lastFetchedAt = 0
local lookupTriedAt = 0 -- os.clock() of the last universeId auto-lookup attempt

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

-- Try to resolve the universe id from game.PlaceId. Rate-limited: that
-- endpoint is currently auth-gated from in-game, so don't hammer it every
-- check. If it ever starts working again, the cached value sticks.
local function tryLookupUniverseId()
	local now = os.clock()
	if lookupTriedAt ~= 0 and now - lookupTriedAt < 900 then
		return false
	end
	lookupTriedAt = now
	for _, host in ipairs(GAMES_API_HOSTS) do
		local json = jsonGet(host .. string.format(PLACE_DETAILS_PATH, game.PlaceId))
		if type(json) ~= "table" then
			continue
		end
		local uid = nil
		if type(json.data) == "table" and type(json.data[1]) == "table" then
			uid = tonumber(json.data[1].universeId)
		end
		if not uid then
			uid = tonumber(json.universeId)
		end
		if uid then
			cachedUniverseId = uid
			return true
		end
	end
	return false
end

local function getUniverseId()
	if cachedUniverseId then
		return cachedUniverseId
	end
	if tryLookupUniverseId() then
		return cachedUniverseId
	end
	-- Auto-lookup is blocked by Roblox right now - use this game's known
	-- universe (see UNIVERSE_ID_FALLBACK in the CONFIG block).
	return UNIVERSE_ID_FALLBACK
end

-- Fresh fetch; on any failure keeps the last known value (never nil->junk).
-- VERIFIED API SHAPE: {"id":...,"upVotes":N,"downVotes":N} - upVotes is
-- TOP-LEVEL. (This endpoint has NO "data" wrapper - reading json.data
-- always gave nil, which is why the bar never moved.)
local function fetchLikes()
	local universeId = getUniverseId()
	if not universeId then
		return lastLikes
	end
	for _, host in ipairs(GAMES_API_HOSTS) do
		local json = jsonGet(host .. string.format(VOTES_PATH, universeId))
		if type(json) == "table" then
			local upVotes = tonumber(json.upVotes)
			if not upVotes and type(json.data) == "table" then
				-- Fallback if Roblox ever wraps this endpoint in "data" again.
				if json.data.upVotes ~= nil then
					upVotes = tonumber(json.data.upVotes)
				elseif #json.data > 0 and type(json.data[1]) == "table" then
					upVotes = tonumber(json.data[1].upVotes)
				end
			end
			if upVotes then
				lastLikes = upVotes
				lastFetchedAt = os.clock()
				break
			end
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
	elseif shown > 0 then
		-- LIKE_GOAL = 0 (used to test Collect) with real likes: full bar.
		ratio = 1
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
-- One-time deep diagnostic when the like count can't be read: shows exactly
-- which step fails (universeId lookup vs votes fetch) with the RAW response,
-- so we can see whether it's an HTTP block, an unpublished place, or a
-- response-shape mismatch.
local function diagnoseOnce()
	-- Test every route for BOTH calls and show exactly what each one
	-- returns, so the Output pins down which host works and which is blocked.
	for _, host in ipairs(GAMES_API_HOSTS) do
		local placeUrl = host .. string.format(PLACE_DETAILS_PATH, game.PlaceId)
		local ok, resp = pcall(function()
			return HttpService:GetAsync(placeUrl)
		end)
		if not ok or type(resp) ~= "string" then
			warn("[LikeGoalService] DIAGNOSTIC: place-details on ", host,
				" FAILED: ", tostring(resp))
		else
			warn("[LikeGoalService] DIAGNOSTIC: place-details on ", host,
				" raw: ", string.sub(resp, 1, 200))
		end
	end
	local universeId = getUniverseId()
	warn("[LikeGoalService] DIAGNOSTIC: using universeId ", tostring(universeId))
	if universeId then
		for _, host in ipairs(GAMES_API_HOSTS) do
			local votesUrl = host .. string.format(VOTES_PATH, universeId)
			local ok, resp = pcall(function()
				return HttpService:GetAsync(votesUrl)
			end)
			if not ok or type(resp) ~= "string" then
				warn("[LikeGoalService] DIAGNOSTIC: votes on ", host,
					" FAILED: ", tostring(resp))
			else
				warn("[LikeGoalService] DIAGNOSTIC: votes on ", host,
					" raw: ", string.sub(resp, 1, 200))
			end
		end
	end
end

local announced = false
task.spawn(function()
	while true do
		local likes = fetchLikes()
		if likes ~= nil then
			updateVisual(likes)
			if likes >= LIKE_GOAL then
				collect.Enabled = true
			end
			if not announced then
				announced = true
			warn("[LikeGoalService] Active - goal is " .. NumberFormat.commas(LIKE_GOAL)
				.. " likes, currently at " .. NumberFormat.commas(likes)
				.. " (Collect unlocks at the goal; likes read server-side via the roproxy mirror).")
			end
		elseif not announced then
			announced = true
			warn("[LikeGoalService] Could not read the like count - running a one-time "
				.. "diagnostic, retrying every " .. CHECK_INTERVAL .. "s.")
			task.spawn(diagnoseOnce)
		end
		task.wait(CHECK_INTERVAL)
	end
end)
