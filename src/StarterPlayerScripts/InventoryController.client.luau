--[[
	InventoryController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives the chair inventory panel and 3D chair displays.
	Each owned chair is shown in a cell of a ScrollingFrame grid with a
	3D ViewportFrame preview that floats UP and DOWN while ROTATING smoothly.

	Also animates in-world Workspace.DisplayChairs with floating bob + spin.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local gameGui = PlayerGui:WaitForChild("GameUI", 10) or PlayerGui:FindFirstChildWhichIsA("ScreenGui")

local Events = ReplicatedStorage:WaitForChild("Events", 15)
local EquipChair = Events and (Events:FindFirstChild("EquipChair") or Events:WaitForChild("EquipChair", 10))
local ChairSync = Events and (Events:FindFirstChild("ChairSync") or Events:WaitForChild("ChairSync", 10))
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))
local ChairsConfig = require(ReplicatedStorage:WaitForChild("ChairsConfig"))

local ChairModels = ReplicatedStorage:FindFirstChild("Chairs")
local Panel = gameGui and (gameGui:FindFirstChild("ChairInvPanel", true) or gameGui:FindFirstChild("InventoryF", true))

local InventoryAPI = {}

local function ensurePanel()
	if Panel then return end
	if not gameGui then return end
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

local Grid = Panel and (Panel:FindFirstChild("Grid", true) :: ScrollingFrame?)
local Template = Grid and (Grid:FindFirstChild("Template", true) :: GuiObject?)
local CloseBtn = Panel and (Panel:FindFirstChild("CloseBtn", true) :: GuiButton?)

local rotatingPreviews = {} -- { world, pivotCF, angle }

local function ensurePreviewFrame(template: GuiObject)
	local vf = template:FindFirstChild("ChairPreview") :: ViewportFrame?
	if not vf then
		vf = Instance.new("ViewportFrame")
		vf.Name = "ChairPreview"
		vf.Size = UDim2.new(1, 0, 0.75, 0)
		vf.Position = UDim2.new(0, 0, 0, 0)
		vf.BackgroundTransparency = 1
		vf.ZIndex = 1
		vf.Parent = template
	end
	local world = vf:FindFirstChildOfClass("WorldModel")
	if not world then
		world = Instance.new("WorldModel")
		world.Name = "World"
		world.Parent = vf
	end
	if not vf:FindFirstChildOfClass("Camera") then
		local cam = Instance.new("Camera")
		cam.Name = "Cam"
		cam.Parent = vf
	end
	vf.CurrentCamera = vf:FindFirstChildOfClass("Camera")
	return vf, world
end

local function renderChairPreview(vf: ViewportFrame, world: WorldModel, chairName: string)
	for _, c in ipairs(world:GetChildren()) do c:Destroy() end
	if not ChairModels then return end
	local template = ChairModels:FindFirstChild(chairName)
	if not template then return end

	local clone = template:Clone()
	clone:PivotTo(CFrame.identity)
	clone.Parent = world

	table.insert(rotatingPreviews, { world = world, pivotCF = CFrame.identity, angle = math.random() * math.pi })

	local cam = vf.CurrentCamera
	if not cam or not world.GetBoundingBox then return end
	local ok, cf, size = pcall(function()
		return world:GetBoundingBox()
	end)
	if not ok or not cf then return end
	local maxDim = math.max(size.X, math.max(size.Y, size.Z)) or 1
	local dist = maxDim * 2.2 + 2
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, 0.2, dist), cf.Position)
end

-------------------------------------------------------------------------------
-- ROTATING + BOBBING UP & DOWN ANIMATION
-------------------------------------------------------------------------------
local lastRotate = os.clock()
local inWorldDisplayPivots = {}

task.spawn(function()
	local displayFolder = Workspace:FindFirstChild("DisplayChairs") or Workspace:WaitForChild("DisplayChairs", 5)
	if displayFolder then
		for _, m in ipairs(displayFolder:GetChildren()) do
			if m:IsA("Model") then
				inWorldDisplayPivots[m] = m:GetPivot()
			end
		end
	end
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local dt = now - lastRotate
	lastRotate = now

	-- 1. ViewportFrame In-Display Chairs (Inventory)
	for _, p in ipairs(rotatingPreviews) do
		if p and p.world and p.world.Parent then
			p.angle = (p.angle or 0) + dt * 0.8
			local bobY = math.sin(p.angle * 2.2) * 0.15
			p.world:PivotTo(p.pivotCF * CFrame.new(0, bobY, 0) * CFrame.Angles(0, p.angle, 0))
		end
	end

	-- 2. In-World Display Chairs (Workspace.DisplayChairs)
	for model, basePivot in pairs(inWorldDisplayPivots) do
		if model and model.Parent then
			local bobY = math.sin(now * 2.0) * 0.25
			local rotAngle = now * 0.7
			model:PivotTo(basePivot * CFrame.new(0, bobY, 0) * CFrame.Angles(0, rotAngle, 0))
		end
	end
end)

local function clearGrid()
	rotatingPreviews = {}
	if not Grid then return end
	for _, c in ipairs(Grid:GetChildren()) do
		if c:IsA("Frame") and c ~= Template then
			c:Destroy()
		end
	end
end

local function makeCell(chairName: string, equipped: string)
	if not Template then return end
	local cell = Template:Clone()
	cell.Name = "Cell_" .. chairName
	cell.Visible = true

	local nameLbl = cell:FindFirstChild("NameLbl", true) :: TextLabel?
	if nameLbl and nameLbl:IsA("TextLabel") then
		nameLbl.Text = chairName
	end

	local equipBtn = cell:FindFirstChild("EquipBtn", true) :: TextButton?
	if equipBtn and equipBtn:IsA("TextButton") then
		equipBtn.Text = (equipped == chairName) and "EQUIPPED" or "EQUIP"
		equipBtn.BackgroundColor3 = (equipped == chairName) and Color3.fromRGB(40, 180, 60) or Color3.fromRGB(60, 140, 70)
		equipBtn.Activated:Connect(function()
			if EquipChair then
				EquipChair:FireServer(chairName)
			end
		end)
	end

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

local function render(owned: { string }, equipped: string)
	clearGrid()
	if not Grid then return end
	for _, name in ipairs(owned) do
		makeCell(name, equipped)
	end
end

local function readFromFolder()
	local folder = player:FindFirstChild("Chairs")
	if not folder then return {}, "Wooden" end
	local owned = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BoolValue") and child.Value then
			table.insert(owned, child.Name)
		end
	end
	local eq = folder:FindFirstChild("Equipped") :: StringValue?
	return owned, (eq and eq.Value) or "Wooden"
end

if ChairSync then
	ChairSync.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		render(data.owned or {}, data.equipped or "Wooden")
	end)
end

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
	if Panel.Visible then return end -- already open (idempotent — no double FX)
	-- Auto-close Shop and Rewards if open
	if _G.ShopAPI and _G.ShopAPI.isOpen and _G.ShopAPI.isOpen() and _G.ShopAPI.close then
		_G.ShopAPI.close()
	end
	if _G.RewardsAPI and _G.RewardsAPI.isOpen and _G.RewardsAPI.isOpen() and _G.RewardsAPI.close then
		_G.RewardsAPI.close()
	end

	UIFX.openWindow(Panel)
	local owned, equipped = readFromFolder()
	render(owned, equipped)
end

function InventoryAPI.close()
	-- Guard: a stray close on an already-closed window is a no-op.
	if not Panel or not Panel.Visible then return end
	UIFX.closeWindow(Panel)
end

function InventoryAPI.isAvailable()
	return Panel ~= nil
end

function InventoryAPI.isOpen()
	return Panel ~= nil and Panel.Visible
end

_G.InventoryAPI = InventoryAPI

