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
	  * GLOBAL mode (default): the GlobalLeaderboards server script keeps the
	    all-time world top lists in a DataStore and pushes them to every
	    client, so EVERY server shows the same world ranking.
	    - Cash = all-time cash, Wins = all-time wins,
	      Streak = biggest streak ever reached.
	    - Until the first list arrives, the subtitle shows "Loading..." and
	      the rows are this server's players, so the boards are never empty.
	  * FALLBACK mode: if GlobalLeaderboards.server.luau is not running (the
	    GlobalLeaderboardsPush event is missing), the boards simply show this
	    server's top players from their leaderstats / Stats values.
	  * Rows are clones of RowTemplate (the template itself is hidden).
	  * Top 6 rows per board. The server pushes a fresh list every
	    REFRESH_SECONDS (30s) and the client re-renders on the same 30s
	    phase-locked tick, so the boards flip at the same moment on every
	    server.
	  * Your own row is highlighted with a gold stroke.
	  * Also drives the Workspace.RefreshPart "Count" label ("Refreshes in:
	    M:SS") so the sign always matches the real refresh time.

	Nothing else to do in Studio — name the three SurfaceGuis exactly as
	above and point their Adornee at the parts you want them on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NumberFormat = require(ReplicatedStorage:WaitForChild("NumberFormat"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOP_N = 6
local REFRESH_SECONDS = 30

-------------------------------------------------------------------------------
-- BOARD CONFIG (SurfaceGui name -> what it shows)
-------------------------------------------------------------------------------
local BOARDS = {
	CashLeaderboard = {
		boardKey = "cash",
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
		boardKey = "streak",
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
		boardKey = "wins",
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
-- GLOBAL DATA (pushed from the GlobalLeaderboards server script)
-------------------------------------------------------------------------------
local Events = ReplicatedStorage:FindFirstChild("Events") or ReplicatedStorage:WaitForChild("Events", 10)
local pushEvent = Events and Events:FindFirstChild("GlobalLeaderboardsPush")
local useGlobal = pushEvent ~= nil

local globalLists = {} -- boardKey ("cash"/"wins"/"streak") -> {userId, name, value} list
local hasData = {}     -- boardKey -> true once at least one push has arrived

if useGlobal then
	warn("[Leaderboards] Global mode: boards show the all-time world top lists (GlobalLeaderboards server script).")
else
	warn("[Leaderboards] GlobalLeaderboardsPush event not found - boards fall back to this server's players. Paste GlobalLeaderboards.server.luau (ServerScriptService) to make them global.")
end

-------------------------------------------------------------------------------
-- HEADSHOTS (Players:GetUserThumbnailAsync — works everywhere, cached)
-------------------------------------------------------------------------------
local headshotCache = {} -- userId -> image url

local function getHeadshot(userId)
	local cached = headshotCache[userId]
	if cached then
		return cached
	end
	local ok, cap = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size48x48
		)
	end)
	local img = (ok and cap) or ""
	if img ~= "" then
		headshotCache[userId] = img
	end
	return img
end

-------------------------------------------------------------------------------
-- READ A PLAYER'S STAT (per-server fallback only)
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
		subtitle = subtitle and subtitle:IsA("TextLabel") and subtitle or nil,
		-- Subtitle to show once data is flowing (keeps custom text you wrote).
		subtitleDefault = (subtitle and subtitle:IsA("TextLabel") and subtitle.Text ~= "") and subtitle.Text or cfg.subtitle,
	}
end

-------------------------------------------------------------------------------
-- REFRESH ONE BOARD (top N rows)
-------------------------------------------------------------------------------
local function refreshBoard(board, cfg)
	local globalList = globalLists[cfg.boardKey]
	local usingGlobal = useGlobal and globalList ~= nil and #globalList > 0

	if board.subtitle then
		-- "Loading..." until the first usable global list has arrived.
		board.subtitle.Text = (useGlobal and not usingGlobal) and "Loading..." or board.subtitleDefault
	end

	local entries
	if usingGlobal then
		entries = globalList
	else
		-- This server's players: shown before the first global push and when
		-- GlobalLeaderboards.server.luau is not running.
		entries = {}
		for _, p in Players:GetPlayers() do
			table.insert(entries, {
				userId = p.UserId,
				name = p.DisplayName,
				value = getStatValue(p, cfg.from, cfg.stat),
			})
		end
	end

	table.sort(entries, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return tostring(a.name) < tostring(b.name)
	end)

	-- Remove previous rows (keep the template + layout objects).
	for _, child in board.list:GetChildren() do
		if child:IsA("Frame") and child ~= board.template then
			child:Destroy()
		end
	end

	for i = 1, math.min(TOP_N, #entries) do
		local e = entries[i]
		local uid = tonumber(e.userId)
		local row = board.template:Clone()
		row.Name = "Row" .. i
		row.Visible = true

		local avatar = row:FindFirstChild("Avatar")
		if avatar and avatar:IsA("ImageLabel") then
			avatar.Image = uid and getHeadshot(uid) or ""
		end

		local nameLbl = row:FindFirstChild("Name")
		if nameLbl and nameLbl:IsA("TextLabel") then
			nameLbl.Text = e.name or "?"
			-- Top 3 get distinct name colors (gold / silver / bronze); rows
			-- 4+ keep the template's default color.
			if i == 1 then
				nameLbl.TextColor3 = Color3.fromRGB(255, 199, 44)
			elseif i == 2 then
				nameLbl.TextColor3 = Color3.fromRGB(192, 199, 212)
			elseif i == 3 then
				nameLbl.TextColor3 = Color3.fromRGB(205, 127, 50)
			end
		end

		local rankLbl = row:FindFirstChild("Rank")
		if rankLbl and rankLbl:IsA("TextLabel") then
			rankLbl.Text = tostring(i)
		end

		local valueLbl = row:FindFirstChild("Value")
		if valueLbl and valueLbl:IsA("TextLabel") then
			valueLbl.Text = cfg.formatValue(tonumber(e.value) or 0)
		end

		-- Highlight your own row.
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke and uid and uid == player.UserId then
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

local function refreshAll()
	for surfaceName, board in pairs(boards) do
		refreshBoard(board, BOARDS[surfaceName])
	end
end

-- The server re-sends the FULL list on every push, so connecting here (after
-- the build) is safe: a push that arrived earlier is covered by the next
-- one. The first usable list re-renders immediately; later updates land on
-- the 30s phase tick below.
if pushEvent then
	pushEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local reRender = false
		for key, list in payload do
			if type(list) == "table" then
				local wasShowing = hasData[key] and globalLists[key] ~= nil and #globalLists[key] > 0
				globalLists[key] = list
				hasData[key] = true
				if not wasShowing and #list > 0 then
					reRender = true
				end
			end
		end
		if reRender then
			refreshAll()
		end
	end)
end

task.spawn(function()
	refreshAll()
	-- Phase-locked to the GLOBAL clock: everyone refreshes on the same
	-- second (unix time crossing a multiple of REFRESH_SECONDS), and the
	-- wait time is re-computed from the clock each pass so drift
	-- self-corrects. The RefreshPart sign below uses the same phase.
	while true do
		local intoPhase = os.time() % REFRESH_SECONDS
		task.wait(math.max(REFRESH_SECONDS - intoPhase, 0.1))
		refreshAll()
	end
end)

-- RefreshPart countdown sign: Workspace.RefreshPart > SurfaceGui > Frame >
-- Count. Updated from the shared wall clock, so it always shows exactly how
-- long until the boards above refresh (same phase as the loop above).
task.spawn(function()
	while true do
		local part = Workspace:FindFirstChild("RefreshPart")
		local count = part and part:FindFirstChild("Count", true)
		if count and count:IsA("TextLabel") then
			local rem = REFRESH_SECONDS - (os.time() % REFRESH_SECONDS)
			count.Text = "Refreshes in: " .. string.format("%d:%02d", math.floor(rem / 60), rem % 60)
		end
		task.wait(1)
	end
end)
