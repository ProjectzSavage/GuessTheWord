--[[
	SpectatorClient.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Spectator Mode. While another table has a match in progress:
	  * a "SPECTATE" button floats above that table;
	  * clicking the button — OR clicking the table itself — focuses your
	    camera on the match and opens a spectator HUD showing the letter bank
	    and both players' guesses IN REAL TIME (plus hearts + last guess).

	Leaving: the "Leave" button in the HUD, the Escape key, or clicking a
	different table's SPECTATE button (switches focus). If YOU start your own
	match, spectating stops automatically.

	DATA FLOW
	The server (GameManager) broadcasts SpectatorData for every table whenever
	something changes (match start/end, new round, hearts, submitted guesses,
	and each player's live typing relayed via SpectatorGuess). Participants
	ignore the feed — this script only renders OTHER tables.

	Nothing to build in Studio: the HUD is created in code.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterImages = require(ReplicatedStorage:WaitForChild("LetterImages"))
local SFX = require(ReplicatedStorage:WaitForChild("SFX"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera
local Events = ReplicatedStorage:WaitForChild("Events")

local SpectatorData = Events:WaitForChild("SpectatorData")
local Countdown = Events:WaitForChild("Countdown")

-------------------------------------------------------------------------------
-- STATE
-------------------------------------------------------------------------------
local spectatingId = nil -- table folder name currently being watched
local tableData = {}     -- tableId -> latest SpectatorData payload
local billboards = {}    -- tableId -> { gui, btn }
local focused = false
local desiredCFrame = nil
local renderConn = nil

-------------------------------------------------------------------------------
-- TABLE LOOKUP (mirrors GameManager: tables live under Workspace.GameArea)
-------------------------------------------------------------------------------
local function tableArea()
	return workspace:FindFirstChild("GameArea")
		or workspace:FindFirstChild("Tables")
		or workspace
end

local function findTableFolder(name)
	local area = tableArea()
	local folder = area:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

-- The TableN folder the LOCAL player is currently seated in (if any). We
-- never offer spectating on your own match.
local function myTableId()
	local char = player.Character
	local h = char and char:FindFirstChildOfClass("Humanoid")
	local seat = h and h.SeatPart
	local node = seat and seat.Parent
	while node do
		if node:IsA("Folder") and string.sub(node.Name, 1, 5) == "Table" then
			return node.Name
		end
		node = node.Parent
	end
	return nil
end

local function tableAdornee(folder)
	local model = folder:FindFirstChild("Table")
	if model and model:IsA("Model") then
		if model.PrimaryPart then
			return model.PrimaryPart
		end
		local part = model:FindFirstChildOfClass("BasePart")
		if part then
			return part
		end
	end
	for _, c in folder:GetChildren() do
		if c:IsA("Seat") or c:IsA("VehicleSeat") or c:IsA("BasePart") then
			return c
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- SPECTATOR CAMERA (same table view as the in-match camera)
-------------------------------------------------------------------------------
local function computeTarget(tableId)
	local folder = findTableFolder(tableId)
	if not folder then
		return nil
	end

	-- Fine-aimed spot if you placed one (same convention as the match camera).
	local camAnchor = folder:FindFirstChild("CameraAnchor")
	if camAnchor and camAnchor:IsA("BasePart") then
		return camAnchor.CFrame
	end

	local lookAt
	local model = folder:FindFirstChild("Table")
	if model and model:IsA("Model") and model.PrimaryPart then
		lookAt = model.PrimaryPart.Position
	elseif model and model:IsA("BasePart") then
		lookAt = model.Position
	else
		local a, b
		for _, c in folder:GetChildren() do
			if c:IsA("Seat") or c:IsA("VehicleSeat") then
				if not a then
					a = c.Position
				else
					b = c.Position
				end
			end
		end
		if a and b then
			lookAt = (a + b) / 2
		end
	end
	if not lookAt then
		return nil
	end

	return CFrame.lookAt(lookAt + Vector3.new(0, 2.5, 6), lookAt)
end

local function startFocus(tableId)
	desiredCFrame = computeTarget(tableId)
	if not desiredCFrame then
		return false
	end
	focused = true
	Camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(
		Camera,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = desiredCFrame }
	):Play()
	if renderConn then
		renderConn:Disconnect()
	end
	renderConn = RunService.RenderStepped:Connect(function()
		if focused and desiredCFrame then
			Camera.CFrame = desiredCFrame
		end
	end)
	return true
end

local function stopFocus()
	if not focused then
		return
	end
	focused = false
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	Camera.CameraType = Enum.CameraType.Custom
	local char = player.Character
	if char then
		Camera.CFrame = char:GetPivot()
	end
end

-------------------------------------------------------------------------------
-- SPECTATOR HUD (built in code — nothing to make in Studio)
-------------------------------------------------------------------------------
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "SpectatorHUD"
hudGui.ResetOnSpawn = false
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Enabled = false
hudGui.Parent = playerGui

local function newCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(470, 316)
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0.03, 0)
panel.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = hudGui
newCorner(panel, 12)
local pStroke = Instance.new("UIStroke")
pStroke.Color = Color3.fromRGB(95, 115, 165)
pStroke.Thickness = 1.5
pStroke.Transparency = 0.3
pStroke.Parent = panel
local pLayout = Instance.new("UIListLayout")
pLayout.FillDirection = Enum.FillDirection.Vertical
pLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pLayout.VerticalAlignment = Enum.VerticalAlignment.Top
pLayout.SortOrder = Enum.SortOrder.LayoutOrder
pLayout.Padding = UDim.new(0, 7)
pLayout.Parent = panel
local pPad = Instance.new("UIPadding")
pPad.PaddingTop = UDim.new(0, 14)
pPad.PaddingBottom = UDim.new(0, 14)
pPad.PaddingLeft = UDim.new(0, 16)
pPad.PaddingRight = UDim.new(0, 16)
pPad.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, 0, 0, 22)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 15
titleLabel.TextColor3 = Color3.fromRGB(140, 205, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "SPECTATING"
titleLabel.LayoutOrder = 0
titleLabel.Parent = panel

local SLOT = UDim2.fromOffset(28, 36)
local TILE = UDim2.fromOffset(32, 42)

local function makeRow(order, label, labelText)
	local row = Instance.new("Frame")
	row.Name = label
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = panel

	local name = Instance.new("TextLabel")
	name.Name = "NameLabel"
	name.Size = UDim2.new(0, 128, 1, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamMedium
	name.TextSize = 14
	name.TextColor3 = Color3.fromRGB(205, 212, 230)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = labelText
	name.Parent = row

	local slots = Instance.new("Frame")
	slots.Name = "Slots"
	slots.Size = UDim2.new(1, -132, 1, 0)
	slots.BackgroundTransparency = 1
	slots.Parent = row

	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	sl.VerticalAlignment = Enum.VerticalAlignment.Center
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Padding = UDim.new(0, 3)
	sl.Parent = slots

	return row, name, slots
end

-- Letter tiles (bank + guess slots) use the same images as the player UI.
local function letterImage(ch)
	if ch == "_" or ch == "" then
		return LetterImages.underscore or ""
	end
	return LetterImages[ch] or LetterImages.underscore or ""
end

local function makeTile(image, size, marked)
	local t = Instance.new("ImageLabel")
	t.Size = size
	t.BackgroundColor3 = Color3.fromRGB(30, 35, 52)
	t.BorderSizePixel = 0
	t.Image = image
	t.ImageRectOffset = Vector2.new()
	t.LayoutOrder = t.LayoutOrder or 0
	newCorner(t, 6)
	if marked then
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(90, 225, 130)
		s.Thickness = 2
		s.Parent = t
	end
	return t
end

local function rebuildSlots(frame, chars, marks)
	for _, child in frame:GetChildren() do
		if child:IsA("ImageLabel") then
			child:Destroy()
		end
	end
	for i, ch in ipairs(chars) do
		local tile = makeTile(letterImage(ch), SLOT, marks and marks[i])
		tile.LayoutOrder = i
		tile.Parent = frame
	end
end

local bankRow = Instance.new("Frame")
bankRow.Name = "BankRow"
bankRow.Size = UDim2.new(1, 0, 0, 44)
bankRow.BackgroundTransparency = 1
bankRow.LayoutOrder = 10
bankRow.Parent = panel
local bankLayout = Instance.new("UIListLayout")
bankLayout.FillDirection = Enum.FillDirection.Horizontal
bankLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
bankLayout.VerticalAlignment = Enum.VerticalAlignment.Center
bankLayout.SortOrder = Enum.SortOrder.LayoutOrder
bankLayout.Padding = UDim.new(0, 3)
bankLayout.Parent = bankRow

local function rebuildBank(chars)
	for _, child in bankRow:GetChildren() do
		if child:IsA("ImageLabel") then
			child:Destroy()
		end
	end
	for i, ch in ipairs(chars) do
		local tile = makeTile(letterImage(ch), TILE, false)
		tile.LayoutOrder = i
		tile.Parent = bankRow
	end
end

local p1Row, p1Name, p1Slots = makeRow(20, "Player1Row", "Player 1")
local p2Row, p2Name, p2Slots = makeRow(30, "Player2Row", "Player 2")
local lastRow, lastName, lastSlots = makeRow(40, "LastGuessRow", "Last guess")
lastName.TextColor3 = Color3.fromRGB(150, 158, 178)
lastRow.Visible = false

local leaveButton = Instance.new("TextButton")
leaveButton.Name = "LeaveButton"
leaveButton.Size = UDim2.fromOffset(190, 34)
leaveButton.BackgroundColor3 = Color3.fromRGB(40, 48, 74)
leaveButton.Text = "Leave  (Esc)"
leaveButton.TextColor3 = Color3.fromRGB(225, 230, 245)
leaveButton.Font = Enum.Font.GothamBold
leaveButton.TextSize = 14
leaveButton.AutoButtonColor = false
leaveButton.LayoutOrder = 50
leaveButton.Parent = panel
newCorner(leaveButton, 8)

local hudScale = Instance.new("UIScale")
hudScale.Scale = 0.9
hudScale.Parent = panel

local function guessChars(guess, length)
	local out = {}
	guess = tostring(guess or "")
	for i = 1, length do
		out[i] = string.sub(guess, i, i)
	end
	return out
end

local function heartsText(n)
	n = math.clamp(tonumber(n) or 0, 0, 3)
	return string.rep("♥", n) .. string.rep("·", 3 - n)
end

-- Render the latest payload for the table being watched.
local function refreshHud(data)
	if not data or not panel then
		return
	end
	titleLabel.Text = "SPECTATING  —  " .. string.upper(tostring(data.id or ""))
	rebuildBank(data.bank or {})

	local length = tonumber(data.wordLength) or 0
	local rows = { { p1Name, p1Slots }, { p2Name, p2Slots } }
	for i = 1, 2 do
		local name = (data.names and data.names[i]) or ("Player " .. i)
		rows[i][1].Text = name .. "   " .. heartsText(data.hearts and data.hearts[i])
		rebuildSlots(rows[i][2], guessChars(data.guesses and data.guesses[i], length), nil)
	end

	if data.lastGuess and tostring(data.lastGuess) ~= "" then
		lastRow.Visible = true
		rebuildSlots(lastSlots, guessChars(data.lastGuess, length), data.lastMarks or {})
	else
		lastRow.Visible = false
	end
end

local function showHud(data)
	hudGui.Enabled = true
	panel.Visible = true
	refreshHud(data)
	TweenService:Create(hudScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	SFX.play("uiPop")
end

local function hideHud()
	panel.Visible = false
	hudGui.Enabled = false
	hudScale.Scale = 0.9
end

-------------------------------------------------------------------------------
-- SPECTATE START / STOP / SWITCH
-------------------------------------------------------------------------------
local function stopSpectating()
	if not spectatingId then
		return
	end
	spectatingId = nil
	stopFocus()
	hideHud()
end

local function startSpectating(tableId)
	local data = tableData[tableId]
	if not data or not data.active then
		return
	end
	if tableId == myTableId() then
		return -- it's your own match
	end

	if spectatingId == tableId then
		return -- already watching it
	elseif spectatingId then
		-- Switch tables: re-target the camera, refresh the HUD.
		spectatingId = tableId
		local cf = computeTarget(tableId)
		if cf and focused then
			desiredCFrame = cf
			TweenService:Create(Camera, TweenInfo.new(0.7, Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out), { CFrame = cf }):Play()
		end
		refreshHud(data)
		return
	end

	if not startFocus(tableId) then
		return -- couldn't find the table
	end
	spectatingId = tableId
	showHud(data)
end

leaveButton.Activated:Connect(function()
	SFX.play("click")
	stopSpectating()
end)

-------------------------------------------------------------------------------
-- FLOATING "SPECTATE" BUTTONS ABOVE ACTIVE TABLES
-------------------------------------------------------------------------------
local function makeBillboard(tableId, adornee)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Spectate_" .. tableId
	gui.Size = UDim2.fromOffset(122, 36)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.MaxDistance = 250
	gui.AlwaysOnTop = true
	gui.Adornee = adornee
	gui.Parent = adornee

	local btn = Instance.new("TextButton")
	btn.Name = "Button"
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
	btn.Text = "SPECTATE"
	btn.TextColor3 = Color3.fromRGB(120, 205, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = false
	btn.Parent = gui
	newCorner(btn, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 205, 255)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.25
	stroke.Parent = btn
	local hover = Instance.new("UIScale")
	hover.Scale = 1
	hover.Parent = btn

	btn.MouseEnter:Connect(function()
		TweenService:Create(hover, TweenInfo.new(0.12), { Scale = 1.08 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(hover, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	btn.Activated:Connect(function()
		SFX.play("click")
		task.spawn(startSpectating, tableId)
	end)

	return { gui = gui, btn = btn }
end

-- Keep one button per active (non-own) table.
task.spawn(function()
	while true do
		task.wait(0.5)
		local wanted = {}
		local own = myTableId()
		for id, data in tableData do
			if data.active and id ~= own then
				wanted[id] = true
			end
		end
		for id, entry in billboards do
			if not wanted[id] then
				entry.gui:Destroy()
				billboards[id] = nil
			end
		end
		for id in wanted do
			local existing = billboards[id]
			if not existing or not existing.gui or not existing.gui.Parent then
				-- (re)create; also covers an adornee part that got destroyed
				if existing and existing.gui then
					existing.gui:Destroy()
				end
				local folder = findTableFolder(id)
				local adornee = folder and tableAdornee(folder)
				if adornee and adornee.Parent then
					billboards[id] = makeBillboard(id, adornee)
				else
					billboards[id] = nil
				end
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- SERVER FEED
-------------------------------------------------------------------------------
SpectatorData.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or not data.id then
		return
	end
	tableData[data.id] = data
	if not data.active then
		if spectatingId == data.id then
			stopSpectating() -- that match just ended
		end
		return
	end
	if spectatingId == data.id then
		refreshHud(data) -- live update while watching
	end
end)

-- Stop spectating the moment your own match starts (countdown or round),
-- so the in-match camera takes over cleanly.
Countdown.OnClientEvent:Connect(function(n)
	if n == 3 and spectatingId then
		stopSpectating()
	end
end)

-- If the character respawns, drop the camera gracefully.
player.CharacterAdded:Connect(function()
	if focused then
		stopSpectating()
	end
end)

-------------------------------------------------------------------------------
-- INPUT: click a table directly, or Esc to leave
-------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.IgnoreWater = true
		local result = workspace:Raycast(ray.Origin, ray.Direction, params)
		if result then
			local node = result.Instance
			while node and node ~= workspace do
				if node:IsA("Folder") and string.sub(node.Name, 1, 5) == "Table" then
					local id = node.Name
					local data = tableData[id]
					if data and data.active and id ~= myTableId() then
						SFX.play("click")
						task.spawn(startSpectating, id)
					end
					break
				end
				node = node.Parent
			end
		end
	elseif input.UserInputType == Enum.UserInputType.Keyboard
		and input.KeyCode == Enum.KeyCode.Escape then
		if spectatingId then
			SFX.play("click")
			stopSpectating()
		end
	end
end)
