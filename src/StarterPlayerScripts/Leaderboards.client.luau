--[[
	Leaderboards.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Fills the world-anchored leaderboard boards you built in StarterGui:

		Leaderboards (ScreenGui)
		├── CashLeaderboard    (SurfaceGui, Adornee = a part in your map)
		├── StreaksLeaderboard (SurfaceGui, Adornee = a part)
		└── WinsLeaderboard    (SurfaceGui, Adornee = a part)

	Each SurfaceGui contains:
		Root (Frame)
		├── ColumnHeader (Frame)  > Name / Rank / Value (TextLabel)
		├── Header (Frame)        > Title / Subtitle (TextLabel)
		└── ListScroll (ScrollingFrame)
		    ├── UIListLayout / UIPadding / UIStroke
		    └── RowTemplate (Frame)
		        ├── UIStroke
		        ├── Avatar (ImageLabel)
		        └── Name / Rank / Value (TextLabel)

	HOW IT WORKS
	  * Rows are clones of RowTemplate (the template itself is hidden).
	  * Top 6 players per board, refreshed every 2 seconds (live).
	  * Cash + Wins come from each player's leaderstats, Streak from the
	    "Stats" folder — all of it replicates, so every client shows the
	    same boards.
	  * Your own row is highlighted with a gold stroke.

	Nothing else to do in Studio — name the three SurfaceGuis exactly as
	above and point their Adornee at the parts you want them on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOP_N = 6
local REFRESH_SECONDS = 2

-------------------------------------------------------------------------------
-- BOARD CONFIG (SurfaceGui name -> what it shows)
-------------------------------------------------------------------------------
local BOARDS = {
	CashLeaderboard = {
		from = "leaderstats",
		stat = "Cash",
		title = "CASH",
		subtitle = "Top cash",
		columnValue = "Cash",
		formatValue = function(v)
			return NumberFormat.currency(v, true)
		end,
	},
	StreaksLeaderboard = {
		from = "Stats",
		stat = "Streak",
		title = "STREAKS",
		subtitle = "Top streaks",
		columnValue = "Streak",
		formatValue = function(v)
			return "x" .. tostring(math.floor(v))
		end,
	},
	WinsLeaderboard = {
		from = "leaderstats",
		stat = "Wins",
		title = "WINS",
		subtitle = "Top winners",
		columnValue = "Wins",
		formatValue = function(v)
			return NumberFormat.commas(v)
		end,
	},
}

-------------------------------------------------------------------------------
-- HEADSHOTS (Players:GetUserThumbnailAsync — works everywhere, cached)
-------------------------------------------------------------------------------
local headshotCache = {} -- userId -> image url

local function getHeadshot(p)
	local cached = headshotCache[p.UserId]
	if cached then
		return cached
	end
	local ok, cap = pcall(function()
		return Players:GetUserThumbnailAsync(
			p.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size48x48
		)
	end)
	local img = (ok and cap and cap.Image) or ""
	if img ~= "" then
		headshotCache[p.UserId] = img
	end
	return img
end

-------------------------------------------------------------------------------
-- READ A PLAYER'S STAT
-------------------------------------------------------------------------------
local function getStatValue(p, from, stat)
	local folder = p:FindFirstChild(from)
	local val = folder and folder:FindFirstChild(stat)
	if val and val:IsA("ValueBase") then
		local n = tonumber(val.Value)
		if n then
			return n
		end
	end
	return 0
end

-------------------------------------------------------------------------------
-- BUILD ONE BOARD (find the pieces, hide the template)
-------------------------------------------------------------------------------
local function buildBoard(surface, cfg)
	local root = surface:FindFirstChild("Root") or surface:FindFirstChild("Root", true)
	if not root or not root:IsA("Frame") then
		return nil
	end

	local header = root:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	local subtitle = header and header:FindFirstChild("Subtitle")

	local colHeader = root:FindFirstChild("ColumnHeader")
	local colValue = colHeader and colHeader:FindFirstChild("Value")

	local list = root:FindFirstChild("ListScroll")
	local template = list and (list:FindFirstChild("RowTemplate") or list:FindFirstChild("RowTemplate", true))
	if not (list and template and template:IsA("Frame")) then
		return nil
	end

	-- Labels: fill the ones you left empty, keep what you wrote.
	if title and title:IsA("TextLabel") and title.Text == "" then
		title.Text = cfg.title
	end
	if subtitle and subtitle:IsA("TextLabel") and subtitle.Text == "" then
		subtitle.Text = cfg.subtitle
	end
	if colValue and colValue:IsA("TextLabel") and colValue.Text == "" then
		colValue.Text = cfg.columnValue
	end

	-- Make sure the list can scroll if it wasn't set up to auto-size.
	if list:IsA("ScrollingFrame")
		and list.AutomaticCanvasSize == Enum.AutomaticSize.None
		and list.CanvasSize == UDim2.new() then
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end

	template.Visible = false

	return {
		list = list,
		template = template,
	}
end

-------------------------------------------------------------------------------
-- REFRESH ONE BOARD (top N rows, live values)
-------------------------------------------------------------------------------
local function refreshBoard(board, cfg)
	local entries = {}
	for _, p in Players:GetPlayers() do
		table.insert(entries, {
			player = p,
			value = getStatValue(p, cfg.from, cfg.stat),
		})
	end
	table.sort(entries, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.player.DisplayName < b.player.DisplayName
	end)

	-- Remove previous rows (keep the template + layout objects).
	for _, child in board.list:GetChildren() do
		if child:IsA("Frame") and child ~= board.template then
			child:Destroy()
		end
	end

	for i = 1, math.min(TOP_N, #entries) do
		local e = entries[i]
		local row = board.template:Clone()
		row.Name = "Row" .. i
		row.Visible = true

		local avatar = row:FindFirstChild("Avatar")
		if avatar and avatar:IsA("ImageLabel") then
			avatar.Image = getHeadshot(e.player)
		end

		local nameLbl = row:FindFirstChild("Name")
		if nameLbl and nameLbl:IsA("TextLabel") then
			nameLbl.Text = e.player.DisplayName
		end

		local rankLbl = row:FindFirstChild("Rank")
		if rankLbl and rankLbl:IsA("TextLabel") then
			rankLbl.Text = tostring(i)
		end

		local valueLbl = row:FindFirstChild("Value")
		if valueLbl and valueLbl:IsA("TextLabel") then
			valueLbl.Text = cfg.formatValue(e.value)
		end

		-- Highlight your own row.
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke and e.player == player then
			stroke.Color = Color3.fromRGB(255, 200, 80)
			stroke.Transparency = 0
		end

		row.Parent = board.list
	end
end

-------------------------------------------------------------------------------
-- WIRE UP + UPDATE LOOP
-------------------------------------------------------------------------------
local gui = playerGui:WaitForChild("Leaderboards", 15)
if not gui then
	warn("[Leaderboards] 'Leaderboards' ScreenGui not found in PlayerGui. "
		.. "Create it in StarterGui with the 3 SurfaceGuis (see script header).")
	return
end

local boards = {}
for surfaceName, cfg in pairs(BOARDS) do
	local surface = gui:FindFirstChild(surfaceName)
	if surface then
		local board = buildBoard(surface, cfg)
		if board then
			boards[surfaceName] = board
		else
			warn("[Leaderboards] " .. surfaceName .. " is missing Root/ListScroll/RowTemplate — skipping it.")
		end
	end
end

task.spawn(function()
	while true do
		for surfaceName, board in pairs(boards) do
			refreshBoard(board, BOARDS[surfaceName])
		end
		task.wait(REFRESH_SECONDS)
	end
end)
