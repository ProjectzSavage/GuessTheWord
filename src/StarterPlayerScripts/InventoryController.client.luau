--[[
	InventoryController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives the chair inventory panel. Each owned chair is shown in a cell of a
	ScrollingFrame grid, with a **3D ViewportFrame preview** of the chair model
	plus its name and an Equip button.

	REQUIRED UI (in GameUI - the panel you built):
		ChairInvPanel  (Frame, Visible=false)
		├── Grid  (ScrollingFrame)
		│   ├── UIGridLayout
		│   ├── UIPadding
		│   └── Template  (Frame, Visible=false)   -- cloned per chair
		│       ├── EquipBtn  (TextButton)
		│       └── NameLbl   (TextLabel)
		├── CloseBtn  (TextButton)
		│   └── Icon  (ImageLabel)
		└── TitleLbl  (TextLabel)

	The script AUTO-ADDS a `ViewportFrame` (named "ChairPreview") into each cell
	to render the 3D chair. Chair models come from ReplicatedStorage.Chairs
	(named like the ChairsConfig keys).

	NOTE: if the panel is named `InventoryF` instead (older layout), it still
	works and auto-builds a grid.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local gameGui = PlayerGui:WaitForChild("GameUI")

local Events = ReplicatedStorage:WaitForChild("Events")
local EquipChair = Events:WaitForChild("EquipChair")
local ChairSync = Events:WaitForChild("ChairSync")
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))
local ChairsConfig = require(ReplicatedStorage:WaitForChild("ChairsConfig"))

-- Chair model templates live here (client can read ReplicatedStorage).
local ChairModels = ReplicatedStorage:FindFirstChild("Chairs")

-- The inventory panel (either the new ChairInvPanel or older InventoryF).
local Panel = gameGui:FindFirstChild("ChairInvPanel") or gameGui:FindFirstChild("InventoryF")

local InventoryAPI = {}

-------------------------------------------------------------------------------
-- FALLBACK: auto-create a simple grid panel if neither exists.
-------------------------------------------------------------------------------
local function ensurePanel()
	if Panel then return end
	Panel = Instance.new("Frame")
	Panel.Name = "ChairInvPanel"
	Panel.Size = UDim2.new(0.5, 0, 0.6, 0)
	Panel.Position = UDim2.new(0.25, 0, 0.2, 0)
	Panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	Panel.Visible = false
	Panel.Parent = gameGui

	local title = Instance.new("TextLabel")
	title.Name = "TitleLbl"
	title.Size = UDim2.new(1, 0, 0.08, 0)
	title.BackgroundTransparency = 1
	title.Text = "Chair Inventory"
	title.TextScaled = true
	title.Parent = Panel

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, 0, 0.84, 0)
	grid.Position = UDim2.new(0, 0, 0.1, 0)
	grid.Parent = Panel

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.3, 0, 0.45, 0)
	layout.CellPadding = UDim2.new(0.03, 0, 0.03, 0)
	layout.Parent = grid

	-- Template
	local template = Instance.new("Frame")
	template.Name = "Template"
	template.Size = UDim2.new(1, 0, 1, 0)
	template.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	template.Visible = false
	template.Parent = grid

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "NameLbl"
	nameLbl.Size = UDim2.new(1, 0, 0.2, 0)
	nameLbl.Position = UDim2.new(0, 0, 0.75, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.TextScaled = true
	nameLbl.Parent = template

	local equipBtn = Instance.new("TextButton")
	equipBtn.Name = "EquipBtn"
	equipBtn.Size = UDim2.new(1, 0, 0.2, 0)
	equipBtn.Position = UDim2.new(0, 0, 0.9, 0)
	equipBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 70)
	equipBtn.Text = "EQUIP"
	equipBtn.TextScaled = true
	equipBtn.Parent = template

	local close = Instance.new("TextButton")
	close.Name = "CloseBtn"
	close.Size = UDim2.new(0.2, 0, 0.08, 0)
	close.Position = UDim2.new(0.8, 0, 0, 0)
	close.Text = "X"
	close.Parent = Panel
	close.Activated:Connect(function()
		InventoryAPI.close()
	end)
end
ensurePanel()

local Grid = Panel and Panel:FindFirstChild("Grid")
local Template = Grid and Grid:FindFirstChild("Template")
local CloseBtn = Panel and Panel:FindFirstChild("CloseBtn")

-- Declared BEFORE renderChairPreview (which inserts into it).
local rotatingPreviews = {} -- { world, pivotCF, angle }

-------------------------------------------------------------------------------
-- 3D PREVIEW (ViewportFrame)
-------------------------------------------------------------------------------
-- Ensure a cell's template has a ViewportFrame (added as the FIRST child so the
-- user's NameLbl/EquipBtn render on top of it).
local function ensurePreviewFrame(template)
	local vf = template:FindFirstChild("ChairPreview")
	if not vf then
		vf = Instance.new("ViewportFrame")
		vf.Name = "ChairPreview"
		vf.Size = UDim2.new(1, 0, 0.75, 0)
		vf.Position = UDim2.new(0, 0, 0, 0)
		vf.BackgroundTransparency = 1 -- transparent background
		vf.CurrentCamera = nil
		-- Insert as first child so it sits behind NameLbl/EquipBtn.
		vf.ZIndex = 1
		vf.Parent = template
	end
	local world = vf:FindFirstChildOfClass("WorldModel")
	if not world then
		world = Instance.new("WorldModel")
		world.Name = "World"
		world.Parent = vf
	end
	-- Give the ViewportFrame its own camera.
	if not vf:FindFirstChildOfClass("Camera") then
		local cam = Instance.new("Camera")
		cam.Name = "Cam"
		cam.Parent = vf
	end
	vf.CurrentCamera = vf:FindFirstChildOfClass("Camera")
	return vf, world
end

-- Clone a chair model into a WorldModel, frame the camera on it, and register
-- it for rotation.
local function renderChairPreview(vf, world, chairName)
	for _, c in world:GetChildren() do c:Destroy() end
	if not ChairModels then return end
	local template = ChairModels:FindFirstChild(chairName)
	if not template then return end
	local clone = template:Clone()
	clone:PivotTo(CFrame.identity)
	clone.Parent = world

	-- Register for rotation (reset angle + store pivot).
	rotatingPreviews[world] = nil -- remove stale entry
	table.insert(rotatingPreviews, { world = world, pivotCF = CFrame.identity, angle = 0 })

	local cam = vf.CurrentCamera
	if not cam or not world.GetBoundingBox then return end
	local ok, cf, size = pcall(function()
		return world:GetBoundingBox()
	end)
	if not ok or not cf then return end
	local maxDim = math.max(size.X, math.max(size.Y, size.Z)) or 1
	local dist = maxDim * 2.2 + 2
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, 0, dist), cf.Position)
end

-------------------------------------------------------------------------------
-- ROTATING 3D PREVIEWS
-- Each cell's chair rotates slowly. We store the WorldModel's root so we can
-- rotate it each frame. Uses os.clock() delta (no GetLastFrameTime - it's not
-- a valid RunService member).
-------------------------------------------------------------------------------
local lastRotate = os.clock()
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local dt = now - lastRotate
	lastRotate = now
	for _, p in rotatingPreviews do
		if p and p.world and p.world.Parent then
			p.angle = (p.angle or 0) + dt * 0.6
			p.world:PivotTo(p.pivotCF * CFrame.Angles(0, p.angle, 0))
		end
	end
end)

-------------------------------------------------------------------------------
-- BUILD CELLS
-------------------------------------------------------------------------------
local function clearGrid()
	rotatingPreviews = {}
	if not Grid then return end
	for _, c in Grid:GetChildren() do
		if c:IsA("Frame") and c ~= Template then
			c:Destroy()
		end
	end
end

local function makeCell(chairName, equipped)
	if not Template then return end
	local cell = Template:Clone()
	cell.Name = "Cell_" .. chairName
	cell.Visible = true

	-- Name label.
	local nameLbl = cell:FindFirstChild("NameLbl")
	if nameLbl and nameLbl:IsA("TextLabel") then
		nameLbl.Text = chairName
	end

	-- Equip button.
	local equipBtn = cell:FindFirstChild("EquipBtn")
	if equipBtn and equipBtn:IsA("TextButton") then
		equipBtn.Text = (equipped == chairName) and "EQUIPPED" or "EQUIP"
		equipBtn.Activated:Connect(function()
			EquipChair:FireServer(chairName)
		end)
	end

	-- 3D preview (grows on hover).
	local vf, world = ensurePreviewFrame(cell)
	renderChairPreview(vf, world, chairName)
	local us = vf:FindFirstChildOfClass("UIScale")
	if not us then
		us = Instance.new("UIScale")
		us.Scale = 1
		us.Parent = vf
	end
	vf.MouseEnter:Connect(function()
		TweenService:Create(us, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1.1 }):Play()
	end)
	vf.MouseLeave:Connect(function()
		TweenService:Create(us, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end)

	cell.Parent = Grid
	return cell
end

local function render(owned, equipped)
	clearGrid()
	if not Grid then return end
	for _, name in owned do
		makeCell(name, equipped)
	end
end

-------------------------------------------------------------------------------
-- SYNC
-------------------------------------------------------------------------------
local function readFromFolder()
	local folder = player:FindFirstChild("Chairs")
	if not folder then return {}, nil end
	local owned = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BoolValue") and child.Value then
			table.insert(owned, child.Name)
		end
	end
	local eq = folder:FindFirstChild("Equipped")
	return owned, eq and eq.Value or "Wooden"
end

ChairSync.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	render(data.owned or {}, data.equipped)
end)

player.ChildAdded:Connect(function(child)
	if child.Name == "Chairs" then
		local owned, equipped = readFromFolder()
		render(owned, equipped)
	end
end)

if CloseBtn then
	CloseBtn.Activated:Connect(function()
		InventoryAPI.close()
	end)
end

local owned0, equipped0 = readFromFolder()
render(owned0, equipped0)

function InventoryAPI.open()
	if not Panel then return end
	Panel.Visible = true
	UIFX.popIn(Panel)
	local owned, equipped = readFromFolder()
	render(owned, equipped)
end

function InventoryAPI.close()
	if not Panel then return end
	UIFX.popOut(Panel)
end

function InventoryAPI.isAvailable()
	return Panel ~= nil
end

function InventoryAPI.isOpen()
	return Panel ~= nil and Panel.Visible
end

_G.InventoryAPI = InventoryAPI
