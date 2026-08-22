--!strict
-- RewardsBadgeController.luau
-- Manages ready badge indicators on OpenRewardsBtn and Category Tabs

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

-- Safely resolve GameUI / GameGui ScreenGui
local function resolveGameUI(): Instance
	local target = gui:FindFirstChild("GameUI") or gui:FindFirstChild("GameGui")
	if target then
		return target
	end

	local startTime = os.clock()
	while (os.clock() - startTime) < 10 do
		target = gui:FindFirstChild("GameUI") or gui:FindFirstChild("GameGui")
		if target then
			return target
		end
		task.wait(0.1)
	end

	return gui:FindFirstChildWhichIsA("ScreenGui") or gui
end

local gameGui = resolveGameUI()

-- Helper to find GUI element by names
local function findObject(parent: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local found = parent:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return nil
end

local events = RS:WaitForChild("Events", 15)
local RewardSync = events and (events:FindFirstChild("RewardSync") or events:WaitForChild("RewardSync", 10)) :: RemoteEvent?
local RewardClaim = events and (events:FindFirstChild("RewardClaim") or events:WaitForChild("RewardClaim", 10)) :: RemoteEvent?
local RewardRequestSync = events and (events:FindFirstChild("RewardRequestSync") or events:WaitForChild("RewardRequestSync", 10)) :: RemoteEvent?

local openRewardsBtn = findObject(gameGui, { "OpenRewardsBtn", "RewardsBtn" }) :: GuiObject?
local rewardsF = findObject(gameGui, { "RewardsF", "RewardsFrame", "RewardsPanel" }) :: GuiObject?
local leftTabs = rewardsF and (findObject(rewardsF, { "LeftTabs", "Tabs" }) :: GuiObject?)

local TAB_TO_CAT = {
	PlaytimeBtn   = "playtime",
	DailyBtn      = "daily",
	GroupBtn      = "group",
	SocialBtn     = "social",
	VipDailyBtn   = "vipdaily",
	RobuxSpentBtn = "robuxspent",
}

local lastPayload: any = nil

local function setBadgeVisible(parentObj: Instance?, visible: boolean)
	if not parentObj then
		return
	end
	local badge = parentObj:FindFirstChild("ReadyBadge", true) :: GuiObject?
	if badge and badge:IsA("GuiObject") then
		badge.Visible = visible
	end
end

local function categoryHasReady(rows: any): boolean
	if type(rows) ~= "table" then
		return false
	end
	for _, row in ipairs(rows) do
		if type(row) == "table" and row.ready == true and row.claimed ~= true then
			return true
		end
	end
	return false
end

local function updateBadges(payload: any)
	if type(payload) ~= "table" then
		return
	end
	lastPayload = payload

	local categories = payload.categories or payload
	local anyReady = false

	if leftTabs then
		for btnName, cat in pairs(TAB_TO_CAT) do
			local btn = leftTabs:FindFirstChild(btnName, true)
			local hasReady = categoryHasReady(categories[cat])
			setBadgeVisible(btn, hasReady)
			if hasReady then
				anyReady = true
			end
		end
	end

	setBadgeVisible(openRewardsBtn, anyReady)
end

if RewardSync and RewardSync:IsA("RemoteEvent") then
	RewardSync.OnClientEvent:Connect(function(payload)
		updateBadges(payload)
	end)
end

if RewardClaim and RewardClaim:IsA("RemoteEvent") then
	RewardClaim.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			updateBadges(payload)
		elseif lastPayload then
			updateBadges(lastPayload)
		end
	end)
end

task.defer(function()
	if RewardRequestSync and RewardRequestSync:IsA("RemoteEvent") then
		RewardRequestSync:FireServer()
	end
end)

print("[RewardsBadgeController] Ready")
