--[[
	ProfileStore.luau  (ModuleScript)  -- place in ServerStorage.Modules
	----------------------------------------------------------------------------
	PURPOSE
	The single DataStore owner for ALL player progress:
	  * chairs  - owned + equipped chair
	  * rewards - claimed rewards, daily state, total Robux spent
	  * quests  - active quest pair, progress, claims (7h cycle)
	  * stats   - hidden Stats: Streak + Reveal Letter/Word uses

	One profile per player (key = userId), written with UpdateAsync.
	Each system registers a "section getter" (a function returning a
	serializable table of its LIVE state); a save merges every registered
	section into ONE profile write, so the systems never fight over the key.

	STUDIO FALLBACK
	If DataStores are unavailable (Studio without "Enable Studio Access to
	API Services"), everything degrades to in-memory for the session - the
	game still works, progress just doesn't survive a restart in that config.

	USAGE (per system):
		local ProfileStore = require(ServerStorage.Modules.ProfileStore)
		-- on join:
		local profile = ProfileStore.load(player.UserId)
		-- ...apply profile.<section> to your in-memory state...
		ProfileStore.setSection(player.UserId, "<section>", function()
			return { ...live state... }
		end)
		-- on important changes and on leave:
		ProfileStore.save(player.UserId)
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ProfileStore = {}

local STORE_NAME = "GuessTheWordProfile_v1"
local AUTOSAVE_SECONDS = 30

local store = nil
local okStore = pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)
if not okStore then
	store = nil
	warn("[ProfileStore] DataStore unavailable - progress is in-memory only this session. "
		.."Enable 'Studio Access to API Services' (Game Settings > Security) to persist in Studio.")
end

local profiles = {} -- userId -> profile table (session cache)
local getters = {}  -- userId -> { section = function() -> table? }

local function defaultProfile()
	return {
		v = 1,
		chairs  = { owned = { Wooden = true }, equipped = "Wooden" },
		rewards = { claimed = {}, lastDailyClaim = 0, dailyDay = 1, robuxSpent = 0 },
		quests  = { resetAt = 0, activeIds = {}, progress = {}, claimed = {} },
		stats   = { Streak = 0, RevealLetterUses = 0, RevealWordUses = 0 },
	}
end

-- Load (and cache) a player's profile. DataStore first, in-memory fallback.
function ProfileStore.load(userId)
	local p = profiles[userId]
	if p then
		return p
	end
	p = defaultProfile()
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync(userId)
		end)
		if ok and type(saved) == "table" then
			for section, value in pairs(saved) do
				if type(value) == "table" then
					p[section] = value
				end
			end
		end
	end
	profiles[userId] = p
	return p
end

-- Register a live-state getter for one section of the profile.
function ProfileStore.setSection(userId, section, getter)
	if typeof(getter) ~= "function" then
		return
	end
	local sections = getters[userId]
	if not sections then
		sections = {}
		getters[userId] = sections
	end
	sections[section] = getter
end

-- Merge every registered section's live state into the profile, then write
-- it (UpdateAsync). Safe to call often; failures are swallowed silently
-- (Studio throttling / offline) - the next autosave retries.
function ProfileStore.save(userId)
	local p = profiles[userId]
	if not p then
		return
	end
	local sections = getters[userId]
	if sections then
		for name, getter in pairs(sections) do
			local ok, value = pcall(getter)
			if ok and type(value) == "table" then
				p[name] = value
			end
		end
	end
	if store then
		pcall(function()
			store:UpdateAsync(userId, function()
				return p
			end)
		end)
	end
end

-- Save every present player's profile (autosave loop).
function ProfileStore.saveAll()
	for userId in pairs(profiles) do
		if Players:GetPlayerByUserId(userId) then
			ProfileStore.save(userId)
		end
	end
end

-- Drop the session cache for a player (after their leave-save).
function ProfileStore.forget(userId)
	profiles[userId] = nil
	getters[userId] = nil
end

-- Periodic autosave so a server crash loses at most ~30s of progress.
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		ProfileStore.saveAll()
	end
end)

-- When a player leaves, give the other services' leave-save handlers a beat
-- to run, then drop the session cache.
Players.PlayerRemoving:Connect(function(player)
	task.delay(1, function()
		ProfileStore.forget(player.UserId)
	end)
end)

return ProfileStore
