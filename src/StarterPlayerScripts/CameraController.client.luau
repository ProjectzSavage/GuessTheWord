--[[
	CameraController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	When a match is about to start with two players (or a player + bot) seated
	at the same table, move BOTH players' cameras to a fixed point in the middle
	of the table, so each sees the same "board view" instead of their own back.

	HOW IT FINDS THE SPOT
	The player's seat (Humanoid.SeatPart) is walked up to its "TableN" folder
	under Workspace.GameArea. Then:
	  * if the folder contains a Part named "CameraAnchor", the camera is placed
	    there (put it above/behind the table, looking at the action);
	  * otherwise the camera sits at the folder's "Table" model center, offset
	    back, looking at it.
	If neither exists, the camera targets the midpoint of the two seats.

	CONTROL
	While focused, the camera is set to Scriptable and held on the target each
	frame. On GameOver it smoothly returns to the player.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Events = ReplicatedStorage:WaitForChild("Events")

local focused = false
local desiredCFrame = nil
local renderConn = nil
local lastTarget = nil -- cache the last good table view (fallback on rematch)

local function findTableFolder()
	local char = player.Character
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local node = seat and seat.Parent
	-- Walk up until we hit a "TableN" folder.
	while node do
		if node:IsA("Folder") and string.sub(node.Name, 1, 5) == "Table" then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function computeTarget()
	local folder = findTableFolder()
	if not folder then
		return nil
	end

	-- Look target: center of the table (or midpoint of the two seats).
	local lookAt
	local tableModel = folder:FindFirstChild("Table")
	if tableModel and tableModel:IsA("Model") and tableModel.PrimaryPart then
		lookAt = tableModel.PrimaryPart.Position
	elseif tableModel and tableModel:IsA("BasePart") then
		lookAt = tableModel.Position
	else
		-- Midpoint of the seats.
		local seats = {}
		for _, c in folder:GetChildren() do
			if (c:IsA("Seat") or c:IsA("VehicleSeat")) and c.Occupant then
				table.insert(seats, c)
			end
		end
		if #seats >= 2 then
			lookAt = (seats[1].Position + seats[2].Position) / 2
		end
	end
	if not lookAt then
		return nil
	end

	-- Camera position: use CameraAnchor part if provided (its own CFrame gives
	-- both position and orientation for fine aiming), else offset back.
	local camAnchor = folder:FindFirstChild("CameraAnchor")
	if camAnchor and camAnchor:IsA("BasePart") then
		return camAnchor.CFrame
	end

	-- Default: place the camera behind/above the table looking at it.
	return CFrame.lookAt(lookAt + Vector3.new(0, 2.5, 6), lookAt)
end

local function startFocus()
	-- Always recompute the target so the camera re-focuses the table on a
	-- rematch too. If seat detection fails (e.g. mid-rematch), fall back to the
	-- last known good table view.
	desiredCFrame = computeTarget() or lastTarget
	if not desiredCFrame then
		return
	end
	lastTarget = desiredCFrame
	focused = true
	Camera.CameraType = Enum.CameraType.Scriptable

	-- Smoothly tween the camera into the table view, then hold it each frame.
	TweenService:Create(
		Camera,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
	-- Re-snap the player camera to their character.
	if player.Character then
		Camera.CFrame = player.Character:GetPivot()
	end
end

-- Match starts at the first countdown tick (n==3). Re-focus each new match
-- (including a replay from the pause menu).
Events:WaitForChild("Countdown").OnClientEvent:Connect(function(n)
	if n == 3 then
		startFocus()
	end
end)

-- Belt-and-suspenders: also re-focus when a round actually starts, in case the
-- countdown n==3 was missed (e.g. on a fast replay). Always re-run so the
-- camera snaps back to the table on every rematch.
Events:WaitForChild("RoundStart").OnClientEvent:Connect(function()
	startFocus()
end)

-- On game over, release the camera back to the player.
Events:WaitForChild("GameOver").OnClientEvent:Connect(function()
	stopFocus()
end)

-- On a cancelled match (someone left during the countdown) release it too,
-- so the leaver is never stuck on the table view.
Events:WaitForChild("MatchCancelled").OnClientEvent:Connect(function()
	stopFocus()
end)

-- If the character dies/respawns mid-game, drop the camera gracefully.
player.CharacterAdded:Connect(function()
	if focused then
		stopFocus()
	end
end)
