--[[
	GlobalLeaderboards.server.luau  (NEW - regular Script in ServerScriptService)
	----------------------------------------------------------------------------
	PURPOSE
	Maintains the GLOBAL (all servers, all time) top lists for Cash, Wins and
	Streak in a DataStore, and pushes them to every client. The in-world
	leaderboard boards (Leaderboards.client.luau) render the pushed lists, so
	every server shows the same world ranking.

	HOW IT WORKS
	  * DataStore "GuessTheWordTop_v1", keys topCash / topWins / topStreak,
	    each an array of {userId, name, value} sorted descending, capped at
	    TOP_N (boards display the top 6 of these).
	  * Every player's live Cash / Wins / Streak IntValues are watched. When a
	    value improves on the global list (or beats the list minimum) it is
	    written with UpdateAsync - atomic across servers, so two busy servers
	    can never clobber each other. Upsets that don't change the list cancel
	    the write (no rate-limit cost).
	  * Upserts are debounced (UPSERT_DEBOUNCE) so a match end (wins + streak +
	    cash in one tick) costs at most one write per stat.
	  * The lists are pushed to each client on join and every PUSH_SECONDS, so
	    a client that misses a push catches up on schedule.

	REQUIREMENTS
	  * Game Settings > Security > "Enable Studio Access to API Services" ON
	    for the DataStore in Studio (live needs nothing extra). If the store
	    is unavailable, the boards fall back to this server's players.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOP_N = 25          -- list size (the boards display the top 6 of these)
local PUSH_SECONDS = 30   -- matches the boards' 30s phase-locked refresh
local UPSERT_DEBOUNCE = 1.5 -- seconds; collapses a match end into one write per stat

local Events = ReplicatedStorage:WaitForChild("Events")
local Push = Events:FindFirstChild("GlobalLeaderboardsPush")
if not Push then
	Push = Instance.new("RemoteEvent")
	Push.Name = "GlobalLeaderboardsPush"
	Push.Parent = Events
end

local store = DataStoreService:GetDataStore("GuessTheWordTop_v1")

-- board -> DataStore key + which live IntValues feed it
local BOARDS = {
	cash = { storeKey = "topCash", folder = "leaderstats", stat = "Cash" },
	wins = { storeKey = "topWins", folder = "leaderstats", stat = "Wins" },
	streak = { storeKey = "topStreak", folder = "Stats", stat = "Streak" },
}
for _, b in BOARDS do
	b.data = {} -- current list (loaded from the store at startup)
end

local storeWarned = false
local function withStore(fn)
	local ok, result = pcall(fn)
	if not ok and not storeWarned then
		storeWarned = true
		warn("[GlobalLeaderboards] DataStore is unavailable (" .. tostring(result)
			.. ") - global boards fall back to this server's players for this session. "
			.. "Enable Game Settings > Security > 'Enable Studio Access to API Services' "
			.. "for global boards in Studio.")
	end
	return ok, result
end

-- Keep only well-formed entries, sorted descending by value.
local function sanitize(list)
	local out = {}
	for _, e in list do
		if type(e) == "table" and type(e.userId) == "number" and type(e.value) == "number" then
			table.insert(out, { userId = e.userId, name = e.name or "?", value = e.value })
		end
	end
	table.sort(out, function(a, c)
		return a.value > c.value
	end)
	return out
end

-- Pure upsert: returns the NEW list, or nil when nothing changed.
local function applyUpsert(current, userId, name, value)
	local list = sanitize(current)
	local idx
	for i, e in list do
		if e.userId == userId then
			idx = i
			break
		end
	end
	if idx then
		if list[idx].value >= value then
			return nil -- already recorded a better/equal value
		end
		list[idx].name = name
		list[idx].value = value
	else
		local last = list[#list]
		if #list >= TOP_N and last.value >= value then
			return nil -- doesn't make the cut
		end
		table.insert(list, { userId = userId, name = name, value = value })
	end
	table.sort(list, function(a, c)
		return a.value > c.value
	end)
	while #list > TOP_N do
		table.remove(list)
	end
	return list
end

-- Record (userId, name, value) into board b's global list. Atomic across
-- servers via UpdateAsync; keeps an in-memory copy when the store is down.
local function upsert(b, userId, name, value)
	local ok, result = withStore(function()
		return store:UpdateAsync(b.storeKey, function(current)
			if type(current) ~= "table" then
				current = {}
			end
			local c = applyUpsert(current, userId, name, value)
			if c == nil then
				return nil -- no change: cancel the write
			end
			return c
		end)
	end)
	if ok then
		if type(result) == "table" then
			b.data = result
		end
	else
		local c = applyUpsert(b.data, userId, name, value)
		if c then
			b.data = c
		end
	end
end

-- Load the three lists once at server start.
task.spawn(function()
	for _, b in BOARDS do
		local ok, list = withStore(function()
			return store:GetAsync(b.storeKey)
		end)
		if ok and type(list) == "table" then
			b.data = sanitize(list)
		end
	end
end)

-- Debounced upserts: a match end changes 3 stats in the same tick, so each
-- (board, player) pair is coalesced into a single write.
local pending = {} -- storeKey -> { userId -> {name, value} }
local function scheduleUpsert(b, userId, name, value)
	local bucket = pending[b.storeKey]
	if bucket then
		bucket[userId] = { name = name, value = value }
		return
	end
	bucket = { [userId] = { name = name, value = value } }
	pending[b.storeKey] = bucket
	-- Flush EVERY pending entry in the bucket: other players' stats may have
	-- piled into it while this one was still waiting.
	task.delay(UPSERT_DEBOUNCE, function()
		local up = pending[b.storeKey]
		pending[b.storeKey] = nil
		if not up then
			return
		end
		for uid, entry in up do
			upsert(b, uid, entry.name, entry.value)
		end
	end)
end

-- PUSHING
local function snapshot()
	local out = {}
	for key, b in BOARDS do
		out[key] = b.data
	end
	return out
end

local function pushTo(p)
	if p and p.Parent then
		Push:FireClient(p, snapshot())
	end
end

-- Periodic push: any client that missed one catches up on schedule.
task.spawn(function()
	while true do
		task.wait(PUSH_SECONDS)
		for _, p in Players:GetPlayers() do
			pushTo(p)
		end
	end
end)

-- WATCHING
local function watchPlayer(player)
	task.spawn(function()
		for _, b in BOARDS do
			local folder = player:WaitForChild(b.folder, 10)
			local val = folder and folder:FindFirstChild(b.stat)
			if val and val:IsA("ValueBase") then
				val.Changed:Connect(function()
					local v = tonumber(val.Value)
					if v and v > 0 then
						scheduleUpsert(b, player.UserId, player.Name, v)
					end
				end)
			end
		end
		-- Seed with the join-time values: restored all-time bests count even
		-- when the player earns nothing new this session.
		for _, b in BOARDS do
			local folder = player:FindFirstChild(b.folder)
			local val = folder and folder:FindFirstChild(b.stat)
			local v = val and tonumber(val.Value)
			if v and v > 0 then
				scheduleUpsert(b, player.UserId, player.Name, v)
			end
		end
	end)
	-- First push shortly after join (the client re-renders on its 30s phase
	-- tick; the periodic push above covers any missed delivery).
	task.delay(2, function()
		if player.Parent then
			pushTo(player)
		end
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
