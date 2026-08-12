--[[
	HeartHUDManager.luau  (ModuleScript)
	----------------------------------------------------------------------------
	Place in: ServerStorage.Modules.HeartHUDManager

	PURPOSE
	Owns the above-head hearts for any character (a real Player OR a bot rig).
	It is required by BOTH server scripts:
	  * Hearts.server.luau  -> calls HeartHUDManager.register() when a character
	                           spawns (clones the BillboardGui onto the head,
	                           hidden by default).
	  * GameManager.server.luau -> calls HeartHUDManager.setHearts() whenever a
	                           character's heart count changes (start of match
	                           and every lost heart) - including the bot.

	OWNER KEY
	Each billboard is keyed by an arbitrary `owner`:
	  * For a real player, pass the Player object.
	  * For the bot, pass the bot's Model (the cloned rig).
	So GameManager and Hearts.server agree on the same key for each character.

	VISIBILITY RULE
	* On spawn the billboard is cloned with Enabled = false, so hearts are NOT
	  shown while idle / walking / waiting to sit.
	* The first setHearts() (fired by GameManager when the match starts) sets
	  Enabled = true and reveals the correct number of hearts.
	* Every client can see these hearts (the billboard sits on the character).
]]

local ServerStorage = game:GetService("ServerStorage")

local HeartHUDManager = {}

-- How high above the head the hearts sit (studs). Raise/lower to move the
-- hearts up or down. Applied to every billboard on clone.
local HEART_OFFSET_Y = 3.0

-- The preferred TEMPLATE lives in ServerStorage (see docs/UI_HIERARCHY.md).
-- If you have NOT created it yet, we auto-build a working default so hearts
-- still show (using a text "♥" glyph instead of an Image). Providing your own
-- `ServerStorage.HeartHUD` with real ImageLabels overrides the default.
local TEMPLATE = ServerStorage:FindFirstChild("HeartHUD")
if not TEMPLATE then
	TEMPLATE = Instance.new("BillboardGui")
	TEMPLATE.Name = "HeartHUD"
	TEMPLATE.Size = UDim2.new(0, 150, 0, 40)
	TEMPLATE.StudsOffset = Vector3.new(0, 3, 0)
	TEMPLATE.AlwaysOnTop = true
	TEMPLATE.MaxDistance = 200

	local frame = Instance.new("Frame")
	frame.Name = "HeartFrame"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = TEMPLATE

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = frame

	for i = 1, 3 do
		local heart = Instance.new("TextLabel")
		heart.Name = "Heart" .. i
		heart.Size = UDim2.new(0, 24, 0, 24)
		heart.BackgroundTransparency = 1
		heart.Text = "♥"
		heart.TextColor3 = Color3.fromRGB(220, 40, 60)
		heart.Font = Enum.Font.GothamBold
		heart.TextScaled = true
		heart.Parent = frame
	end

	TEMPLATE.Parent = ServerStorage
	warn("[HeartHUDManager] ServerStorage.HeartHUD not found - created a " ..
		"default hearts billboard. Replace it with your own for custom images.")
end

-- ownerKey -> BillboardGui currently attached to that character's head.
local billboards = {}

-- Attach a cloned (hidden) BillboardGui to a character's head.
-- @param ownerKey - Player object or any Instance (e.g. the bot Model) to key by.
-- @param character - the rig/character that has a "Head" part.
function HeartHUDManager.register(ownerKey, character)
	if not TEMPLATE then
		return
	end
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end

	-- Remove any previous billboard for this owner.
	local old = billboards[ownerKey]
	if old then
		old:Destroy()
		billboards[ownerKey] = nil
	end

	local bb = TEMPLATE:Clone()
	bb.Enabled = false -- hidden until the match starts
	-- Control the vertical position of the hearts above the head.
	local off = bb.StudsOffset or Vector3.new()
	bb.StudsOffset = Vector3.new(off.X, HEART_OFFSET_Y, off.Z)
	bb.Parent = head
	billboards[ownerKey] = bb
end

-- Blink a heart (appear/disappear a few times), then shrink it out and hide it.
-- Runs on the server; billboard changes replicate so every client sees it.
local function blinkHeartThenHide(heart)
	local us = heart:FindFirstChildOfClass("UIScale")
	if not us then
		us = Instance.new("UIScale")
		us.Scale = 1
		us.Parent = heart
	end

	local blinks = 3
	local step = 0
	heart.Visible = true

	local function tick()
		step = step + 1
		if step <= blinks * 2 then
			heart.Visible = (step % 2 == 0)
			task.delay(0.12, tick)
		else
			-- Done blinking: shrink out and hide.
			local t = game:GetService("TweenService"):Create(
				us,
				TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Scale = 0 }
			)
			t:Play()
			t.Completed:Connect(function()
				heart.Visible = false
				us.Scale = 1
			end)
		end
	end
	tick()
end

-- Reveal and set the heart count (0..3) on an owner's billboard.
-- Called by GameManager whenever the count changes. A lost heart (one that must
-- disappear) blinks out instead of vanishing instantly.
function HeartHUDManager.setHearts(ownerKey, heartCount)
	local bb = billboards[ownerKey]
	if not bb then
		return
	end
	if type(heartCount) ~= "number" then
		return
	end
	heartCount = math.clamp(heartCount, 0, 3)

	local frame = bb:FindFirstChild("HeartFrame")
	if not frame then
		warn("[HeartHUDManager] HeartHUD template is missing 'HeartFrame'.")
		return
	end

	bb.Enabled = true -- the game has started -> show hearts
	for i = 1, 3 do
		local heart = frame:FindFirstChild("Heart" .. i)
		if heart then
			if i <= heartCount then
				heart.Visible = true
				local us = heart:FindFirstChildOfClass("UIScale")
				if us then
					us.Scale = 1
				end
			elseif heart.Visible then
				blinkHeartThenHide(heart)
			else
				heart.Visible = false
			end
		end
	end
end

-- Hide (but keep) an owner's above-head hearts. Used at match end to return
-- everything to normal without destroying the billboard.
function HeartHUDManager.hide(ownerKey)
	local bb = billboards[ownerKey]
	if bb then
		bb.Enabled = false
	end
end

-- Cleanup when an owner leaves / character is destroyed.
function HeartHUDManager.remove(ownerKey)
	local bb = billboards[ownerKey]
	if bb then
		bb:Destroy()
	end
	billboards[ownerKey] = nil
end

return HeartHUDManager
