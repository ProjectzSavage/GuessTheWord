--[[
	Dictionary.luau  (ModuleScript)
	----------------------------------------------------------------------------
	Place this ModuleScript in ServerStorage.Modules.Dictionary  (the folder
	"Modules" can be created inside ServerStorage).

	SECURITY NOTE
	This dictionary is required and read ONLY by the server. The client never
	sees it. When a player submits a guess, the server compares it against the
	active round's word - it does NOT trust the client's spelling or validation.

	Each entry:
		word    -> lowercase word used for the answer.
		images  -> 4 image IDs shown as the 4 image clues (placeholders - swap
		           them for your own). rbxassetid://YOUR_IMAGE_ID
]]

local Dictionary = {}

Dictionary.Entries = {
	{
		word = "star",
		images = {
			"rbxassetid://YOUR_STAR_IMAGE_1",
			"rbxassetid://YOUR_STAR_IMAGE_2",
			"rbxassetid://YOUR_STAR_IMAGE_3",
			"rbxassetid://YOUR_STAR_IMAGE_4",
		},
	},
	{
		word = "boat",
		images = {
			"rbxassetid://YOUR_BOAT_IMAGE_1",
			"rbxassetid://YOUR_BOAT_IMAGE_2",
			"rbxassetid://YOUR_BOAT_IMAGE_3",
			"rbxassetid://YOUR_BOAT_IMAGE_4",
		},
	},
	{
		word = "tree",
		images = {
			"rbxassetid://YOUR_TREE_IMAGE_1",
			"rbxassetid://YOUR_TREE_IMAGE_2",
			"rbxassetid://YOUR_TREE_IMAGE_3",
			"rbxassetid://YOUR_TREE_IMAGE_4",
		},
	},
	{
		word = "fish",
		images = {
			"rbxassetid://YOUR_FISH_IMAGE_1",
			"rbxassetid://YOUR_FISH_IMAGE_2",
			"rbxassetid://YOUR_FISH_IMAGE_3",
			"rbxassetid://YOUR_FISH_IMAGE_4",
		},
	},
	{
		word = "ball",
		images = {
			"rbxassetid://YOUR_BALL_IMAGE_1",
			"rbxassetid://YOUR_BALL_IMAGE_2",
			"rbxassetid://YOUR_BALL_IMAGE_3",
			"rbxassetid://YOUR_BALL_IMAGE_4",
		},
	},
	{
		word = "cake",
		images = {
			"rbxassetid://YOUR_CAKE_IMAGE_1",
			"rbxassetid://YOUR_CAKE_IMAGE_2",
			"rbxassetid://YOUR_CAKE_IMAGE_3",
			"rbxassetid://YOUR_CAKE_IMAGE_4",
		},
	},
	{
		word = "moon",
		images = {
			"rbxassetid://YOUR_MOON_IMAGE_1",
			"rbxassetid://YOUR_MOON_IMAGE_2",
			"rbxassetid://YOUR_MOON_IMAGE_3",
			"rbxassetid://YOUR_MOON_IMAGE_4",
		},
	},
	{
		word = "bird",
		images = {
			"rbxassetid://YOUR_BIRD_IMAGE_1",
			"rbxassetid://YOUR_BIRD_IMAGE_2",
			"rbxassetid://YOUR_BIRD_IMAGE_3",
			"rbxassetid://YOUR_BIRD_IMAGE_4",
		},
	},
	{
		word = "lock",
		images = {
			"rbxassetid://YOUR_LOCK_IMAGE_1",
			"rbxassetid://YOUR_LOCK_IMAGE_2",
			"rbxassetid://YOUR_LOCK_IMAGE_3",
			"rbxassetid://YOUR_LOCK_IMAGE_4",
		},
	},
	{
		word = "rock",
		images = {
			"rbxassetid://YOUR_ROCK_IMAGE_1",
			"rbxassetid://YOUR_ROCK_IMAGE_2",
			"rbxassetid://YOUR_ROCK_IMAGE_3",
			"rbxassetid://YOUR_ROCK_IMAGE_4",
		},
	},
	{
		word = "ship",
		images = {
			"rbxassetid://YOUR_SHIP_IMAGE_1",
			"rbxassetid://YOUR_SHIP_IMAGE_2",
			"rbxassetid://YOUR_SHIP_IMAGE_3",
			"rbxassetid://YOUR_SHIP_IMAGE_4",
		},
	},
	{
		word = "coin",
		images = {
			"rbxassetid://YOUR_COIN_IMAGE_1",
			"rbxassetid://YOUR_COIN_IMAGE_2",
			"rbxassetid://YOUR_COIN_IMAGE_3",
			"rbxassetid://YOUR_COIN_IMAGE_4",
		},
	},
}

-- Fisher-Yates shuffle (local helper).
local function shuffle(list)
	local t = {}
	for _, v in list do
		table.insert(t, v)
	end
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- Returns a random entry: { word = "...", images = { ... } }
function Dictionary.randomEntry()
	return Dictionary.Entries[math.random(1, #Dictionary.Entries)]
end

-- Returns a shuffled (scrambled) list of the letters of a word.
function Dictionary.scrambleWord(word)
	local letters = {}
	for i = 1, #word do
		table.insert(letters, string.sub(word, i, i))
	end
	return shuffle(letters)
end

-- Returns true if a given word exists in the dictionary (server-side validation).
function Dictionary.contains(word)
	for _, entry in Dictionary.Entries do
		if entry.word == word then
			return true
		end
	end
	return false
end

return Dictionary
