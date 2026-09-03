--[[
	Preloader.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Warms up the game's image assets so they don't pop in/flicker mid-round.
	It preloads:
	  * every letter image from ReplicatedStorage.LetterImages (A-Z + underscore)
	  * the heart images used by the TopBar (Player/Opponent heart containers)
	  * the clue images in PuzzleArea.ImageGrid

	Uses ContentProvider:PreloadAsync, which caches the assets on the client.

	NOTE
	You can extend this to preload anything else you want (sound ids, models, the
	HeartHUD assets, etc.) - just add them to the `assets` / `instances` lists.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Preload an array of content strings (e.g. "rbxassetid://...") AND/OR instances.
local function preload(content)
	if type(content) ~= "table" or #content == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(content)
		end)
		if not ok then
			warn("[Preloader] PreloadAsync failed: ", err)
		end
	end)
end

local player = Players.LocalPlayer

-------------------------------------------------------------------------------
-- 1) Letter images (strings)
-------------------------------------------------------------------------------
local content = {}
local function addContent(id)
	if type(id) == "string" and id ~= "" and string.find(id, "rbxassetid://") then
		table.insert(content, id)
	end
end

local LetterImages = require(ReplicatedStorage:WaitForChild("LetterImages"))
for _, id in pairs(LetterImages) do
	addContent(id)
end

-------------------------------------------------------------------------------
-- 2) Heart + clue images (instances) from the player's GameUI
-------------------------------------------------------------------------------
local function waitGui()
	return player:WaitForChild("PlayerGui"):WaitForChild("GameUI")
end

local function collectImages(root, out)
	if not root then
		return
	end
	-- GetDescendants includes all descendants (direct children too).
	for _, child in root:GetDescendants() do
		if child:IsA("ImageLabel") and child.Image ~= "" then
			table.insert(out, child)
		end
	end
end

local GameUI = waitGui()
local TopBar = GameUI:FindFirstChild("TopBar")
local PuzzleArea = GameUI:FindFirstChild("PuzzleArea")

local instances = {}
if TopBar then
	collectImages(TopBar:FindFirstChild("PlayerHeartContainer"), instances)
	collectImages(TopBar:FindFirstChild("OpponentHeartContainer"), instances)
end
if PuzzleArea then
	collectImages(PuzzleArea:FindFirstChild("ImageGrid"), instances)
end

-- Merge strings + instances into one list (PreloadAsync accepts both).
local all = {}
for _, c in content do
	table.insert(all, c)
end
for _, inst in instances do
	table.insert(all, inst)
end

-------------------------------------------------------------------------------
-- LOAD REPORT (one-time, PER CLIENT)
-- Each client preloads every asset individually (so one dead id can't abort
-- the batch) and prints exactly what it cached to its OWN Output window.
-- In Studio: open the Output of BOTH clients and compare - that's how you
-- verify the images loaded for both parties.
-- --------------------------------------------------------------------------
local function uniqueIds(items)
	local seen, ids = {}, {}
	for _, item in items do
		local id
		if type(item) == "string" then
			id = item
		elseif typeof(item) == "Instance" and item:IsA("GuiObject") then
			id = item.Image
		end
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	return ids
end

local function reportAssets(ids, label)
	task.spawn(function()
		local hasIsPreloaded = nil
		local failed, checked = {}, 0
		for _, id in ids do
			local ok = pcall(function()
				ContentProvider:PreloadAsync({ id })
			end)
			if hasIsPreloaded == nil then
				hasIsPreloaded = pcall(function()
					return ContentProvider:IsPreloaded(id)
				end)
			end
			-- IsPreloaded is the definitive cache check; fall back to the
			-- preload pcall result on engines that don't have it.
			local loaded = ok
			if hasIsPreloaded then
				local ok2, cached = pcall(function()
					return ContentProvider:IsPreloaded(id)
				end)
				if ok2 then
					loaded = cached == true
				end
			end
			checked = checked + 1
			if not loaded then
				table.insert(failed, id)
			end
		end
		if #failed > 0 then
			warn("[Preloader] ", label, ": ", #failed, " of ", checked, " did NOT load: ",
				table.concat(failed, ", "))
		else
			warn("[Preloader] ", label, ": all ", checked, " loaded OK on this client.")
		end
	end)
end

reportAssets(uniqueIds(all), "Images (letters/hearts/grid)")



-- Preload all clue image IDs the server sends at join (so clue images are
-- already cached when a round starts) + report per-client load status.
local Events = ReplicatedStorage:WaitForChild("Events")
local clueReported = false
Events:WaitForChild("PreloadClueImages").OnClientEvent:Connect(function(ids)
	preload(ids)
	if not clueReported then
		clueReported = true
		reportAssets(uniqueIds(ids or {}), "Clue images")
	end
end)

-- Also preload a round's clue images + letter bank the moment they arrive.
Events:WaitForChild("RoundStart").OnClientEvent:Connect(function(_, letterBank, images)
	local toPreload = {}
	if type(images) == "table" then
		for _, id in images do
			table.insert(toPreload, id)
		end
	end
	if type(letterBank) == "table" then
		local LetterImages = require(ReplicatedStorage:WaitForChild("LetterImages"))
		for _, ch in letterBank do
			local id = LetterImages[ch]
			if type(id) == "string" and id ~= "" then
				table.insert(toPreload, id)
			end
		end
	end
	preload(toPreload)
end)
