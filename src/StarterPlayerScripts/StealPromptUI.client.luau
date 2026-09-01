--[[
	StealPromptUI.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Draws a floating "Steal $X" button above every OTHER player who is close
	by (within 20 studs) - NEVER above your own head (same client-side design
	as the GMC StealService - a real ProximityPrompt would show for the
	victim too, which is why this is a client button instead).

	The cash amount updates live. Clicking it fires StealRequest to the
	server (TheftService), which:
	  * in STUDIO: executes the steal directly (no purchase), and
	  * in PRODUCTION: prompts the tiered Robux purchase.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SFX = require(ReplicatedStorage:WaitForChild("SFX"))
local HoverFX = require(ReplicatedStorage:WaitForChild("HoverFX"))

local player = Players.LocalPlayer
local Events = ReplicatedStorage:WaitForChild("Events")

local StealRequest = Events:FindFirstChild("StealRequest")
if not StealRequest then
	StealRequest = Instance.new("RemoteEvent")
	StealRequest.Name = "StealRequest"
	StealRequest.Parent = Events
end

local RADIUS = 20
local billboards = {} -- victim player -> BillboardGui

warn("[StealPromptUI] Active - a 'Steal $X' button floats above other "
	.. "players within " .. RADIUS .. " studs (never above you).")

local function getCash(victim)
	local ls = victim:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	return (cash and cash.Value) or 0
end

local function makeBillboard(victim)
	local bb = Instance.new("BillboardGui")
	bb.Name = "StealPromptUI"
	bb.Size = UDim2.fromScale(0.18, 0.065)
	bb.StudsOffset = Vector3.new(0, 3.6, 0)
	bb.MaxDistance = RADIUS
	bb.AlwaysOnTop = true

	local btn = Instance.new("TextButton")
	btn.Name = "StealBtn"
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundColor3 = Color3.fromRGB(28, 28, 40)
	btn.BackgroundTransparency = 0.1
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextScaled = true
	btn.Text = "Steal $0"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 200, 80)
	stroke.Thickness = 1.5
	stroke.Parent = btn
	btn.Parent = bb

	HoverFX.applyTo(btn, { scale = 1.12, duration = 0.15 })

	local cashConn = nil
	local function refresh()
		btn.Text = "Steal $" .. getCash(victim)
	end
	local function startWatch()
		local ls = victim:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Cash")
		if cash then
			refresh()
			cashConn = cash.Changed:Connect(refresh)
		else
			task.delay(1, startWatch)
		end
	end
	startWatch()

	btn.Activated:Connect(function()
		if not victim.Parent then
			return
		end
		SFX.play("robuxClick")
		if StealRequest then
			StealRequest:FireServer(victim.UserId)
		end
	end)

	-- Keep the button honest if the cash value object gets recreated.
	victim.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" and cashConn == nil then
			task.delay(0.5, startWatch)
		end
	end)

	return bb
end

-------------------------------------------------------------------------------
-- MAIN LOOP: one floating button per nearby player (never yourself)
-------------------------------------------------------------------------------
local warnedBuild = false
task.spawn(function()
	while true do
		task.wait(0.5)
		local myChar = player.Character
		local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")

		for _, other in ipairs(Players:GetPlayers()) do
			local bb = billboards[other]

			if other == player then
				if bb and bb.Parent then
					bb:Destroy()
				end
				billboards[other] = nil
			else
				local char = other.Character
				local head = char and char:FindFirstChild("Head")
				local humanoid = char and char:FindFirstChildOfClass("Humanoid")
				local visible = false
				if head and humanoid and humanoid.Health > 0 and myHrp then
					visible = (myHrp.Position - head.Position).Magnitude <= RADIUS
				end

				if visible then
					if not bb or not bb.Parent then
						-- (Re)create it (also after a victim respawn).
						local ok, err = pcall(function()
							local newBb = makeBillboard(other)
							billboards[other] = newBb
							newBb.Adornee = head
							newBb.Parent = char
						end)
						if not ok and not warnedBuild then
							warnedBuild = true
							warn("[StealPromptUI] Could not build a steal button: " .. tostring(err))
						end
					elseif head then
						bb.Adornee = head -- track the head
					end
				elseif bb and bb.Parent then
					bb:Destroy()
					billboards[other] = nil
				end
			end
		end
	end
end)
