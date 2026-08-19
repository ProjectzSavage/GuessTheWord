--[[
	InventoryController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Placeholder inventory GUI for chairs. It shows a list of your OWNED chairs
	(with a button to EQUIP each). It reads the server-synced `Chairs` folder on
	the player (BoolValue per owned chair + `Equipped` StringValue).

	REQUIRED UI (in GameUI):
		InventoryF  (Frame, Visible=false)
		  ├── CloseBtn   (TextButton)
		  ├── TitleLbl   (TextLabel)
		  └── Scroll     (ScrollingFrame)
		      └── RowTemplate  (Frame, Visible=false)
		            ├── ChairName  (TextLabel)
		            └── EquipBtn   (TextButton)

	The script clones RowTemplate per owned chair and wires EquipBtn to fire
	EquipChair. If the template is missing, it auto-builds simple rows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local gameGui = PlayerGui:WaitForChild("GameUI")

local Events = ReplicatedStorage:WaitForChild("Events")
local EquipChair = Events:WaitForChild("EquipChair")
local ChairSync = Events:WaitForChild("ChairSync")

local InventoryF = gameGui:FindFirstChild("InventoryF")
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))

local InventoryAPI = {}

-- If no InventoryF, auto-create a simple one so the button still works.
local function ensureInventoryUI()
	if InventoryF then return end
	InventoryF = Instance.new("Frame")
	InventoryF.Name = "InventoryF"
	InventoryF.Size = UDim2.new(0.4, 0, 0.5, 0)
	InventoryF.Position = UDim2.new(0.3, 0, 0.25, 0)
	InventoryF.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	InventoryF.Visible = false
	InventoryF.Parent = gameGui

	local title = Instance.new("TextLabel")
	title.Name = "TitleLbl"
	title.Size = UDim2.new(1, 0, 0.1, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "Inventory"
	title.TextScaled = true
	title.Parent = InventoryF

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.new(1, 0, 0.8, 0)
	scroll.Position = UDim2.new(0, 0, 0.12, 0)
	scroll.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	scroll.Parent = InventoryF

	local close = Instance.new("TextButton")
	close.Name = "CloseBtn"
	close.Size = UDim2.new(0.3, 0, 0.08, 0)
	close.Position = UDim2.new(0.35, 0, 0.9, 0)
	close.Text = "Close"
	close.Parent = InventoryF
	close.Activated:Connect(function()
		InventoryAPI.close()
	end)
end
ensureInventoryUI()

local Scroll = InventoryF and InventoryF:FindFirstChild("Scroll")
local RowTemplate = Scroll and Scroll:FindFirstChild("RowTemplate")
local CloseBtn = InventoryF and InventoryF:FindFirstChild("CloseBtn")

local function clearRows()
	if not Scroll then return end
	for _, c in Scroll:GetChildren() do
		if c:IsA("Frame") and c ~= RowTemplate then
			c:Destroy()
		end
	end
end

-- Auto-build a simple row if no template exists.
local function makeRow(scroll, chairName, equipped)
	local row
	if RowTemplate and RowTemplate:IsA("Frame") then
		row = RowTemplate:Clone()
		row.Visible = true
		local nameLbl = row:FindFirstChild("ChairName")
		if nameLbl then nameLbl.Text = chairName end
		local btn = row:FindFirstChild("EquipBtn")
		if btn then
			btn.Text = (equipped == chairName) and "EQUIPPED" or "EQUIP"
		end
	else
		row = Instance.new("Frame")
		row.Size = UDim2.new(1, -16, 0, 50)
		row.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
		row.Parent = nil

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "ChairName"
		nameLbl.Size = UDim2.new(0.6, 0, 1, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = chairName
		nameLbl.TextScaled = true
		nameLbl.Parent = row

		local btn = Instance.new("TextButton")
		btn.Name = "EquipBtn"
		btn.Size = UDim2.new(0.4, 0, 1, 0)
		btn.Position = UDim2.new(0.6, 0, 0, 0)
		btn.Text = (equipped == chairName) and "EQUIPPED" or "EQUIP"
		btn.Parent = row
	end

	row.Name = "Row_" .. chairName
	row.Parent = scroll
	return row
end

local function render(owned, equipped)
	clearRows()
	if not Scroll then return end
	for _, name in owned do
		local row = makeRow(Scroll, name, equipped)
		local btn = row and row:FindFirstChild("EquipBtn")
		if btn then
			btn.Activated:Connect(function()
				EquipChair:FireServer(name)
			end)
		end
	end
end

-- Server sync: read owned + equipped.
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

-- Also re-render when the Chairs folder updates.
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

-- Default: read from the folder if it already exists.
local owned0, equipped0 = readFromFolder()
render(owned0, equipped0)

function InventoryAPI.open()
	if not InventoryF then return end
	InventoryF.Visible = true
	UIFX.popIn(InventoryF)
	local owned, equipped = readFromFolder()
	render(owned, equipped)
end

function InventoryAPI.close()
	if not InventoryF then return end
	UIFX.popOut(InventoryF)
end

function InventoryAPI.isAvailable()
	return InventoryF ~= nil
end

_G.InventoryAPI = InventoryAPI
