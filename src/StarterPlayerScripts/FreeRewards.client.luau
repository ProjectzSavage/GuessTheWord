--[[
	FreeRewards.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	In-world free gift. You build the parts + prompts:
	  * Put a ProximityPrompt inside a Part.
	  * Tag the Part with a `FreeGift` Attribute (boolean = true) OR an
	    Instance Tag named "FreeGift" (either works).
	When a player triggers one of those prompts, the `FreeRewardsGUI`
	ScreenGui (in StarterGui) opens, on its MainFrame.

	HIERARCHY (built by you in StarterGui):
		FreeRewardsGUI (ScreenGui)
		└── MainFrame (Frame)
		    ├── CloseButton (Button)
		    └── ClaimButton (Button)

	CLAIM REQUIREMENTS (checked client-side, group re-checked server-side):
	  1. Favorite the game  -> AvatarEditorService:PromptSetFavorite
	  2. Join the group      -> GroupService:PromptJoinAsync
	Reward (granted once per player by RewardsService): +$1,000 + 1 Word Reveal.
]]

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SFX = require(ReplicatedStorage:WaitForChild("SFX"))
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GROUP_ID = 35973544 -- keep in sync with RewardsService

-------------------------------------------------------------------------------
-- GUI (FreeRewardsGUI lives in StarterGui -> cloned into PlayerGui)
-------------------------------------------------------------------------------
local gui = playerGui:WaitForChild("FreeRewardsGUI", 15)
if not gui then
	warn("[FreeRewards] FreeRewardsGUI ScreenGui not found in PlayerGui. "
		.. "Make sure it is in StarterGui and named exactly 'FreeRewardsGUI'.")
	return
end

local MainFrame = gui:FindFirstChild("MainFrame") or gui:FindFirstChild("MainFrame", true)
if not MainFrame or not MainFrame:IsA("Frame") then
	warn("[FreeRewards] MainFrame not found inside FreeRewardsGUI.")
	return
end
MainFrame.Visible = false -- starts hidden (it may be left visible in Studio)

local CloseButton = MainFrame:FindFirstChild("CloseButton")
	or MainFrame:FindFirstChild("CloseButton", true)
local ClaimButton = MainFrame:FindFirstChild("ClaimButton")
	or MainFrame:FindFirstChild("ClaimButton", true)

local function openGiftGui()
	if MainFrame and MainFrame.Parent then
		UIFX.openWindow(MainFrame)
	end
end

local function closeGiftGui()
	if MainFrame and MainFrame.Visible then
		UIFX.closeWindow(MainFrame)
	end
end

local function notify(title, message, kind)
	if _G.Notify then
		_G.Notify({ title = title, message = message, kind = kind, duration = 4 })
	end
end

-------------------------------------------------------------------------------
-- FREE GIFT PARTS (Part with a ProximityPrompt, tagged FreeGift)
-------------------------------------------------------------------------------
local function isFreeGift(inst)
	if inst:GetAttribute("FreeGift") == true then
		return true
	end
	local attr = inst:GetAttribute("FreeGift")
	if type(attr) == "string" and attr:lower() == "true" then
		return true
	end
	return inst:HasTag("FreeGift")
end

local function bindPart(part)
	if not isFreeGift(part) then
		return
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
	end
	if not prompt then
		return
	end
	if prompt:GetAttribute("FreeGiftBound") == true then
		return
	end
	prompt:SetAttribute("FreeGiftBound", true)
	prompt.Triggered:Connect(function()
		SFX.play("click")
		task.defer(openGiftGui)
	end)
end

for _, inst in workspace:GetDescendants() do
	if inst:IsA("BasePart") then
		bindPart(inst)
	end
end
workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("BasePart") then
		bindPart(inst)
	end
end)

-------------------------------------------------------------------------------
-- CLAIM FLOW (favorite + group)
-------------------------------------------------------------------------------
local Events = ReplicatedStorage:WaitForChild("Events")
local ClaimFreeReward = Events:WaitForChild("ClaimFreeReward")
local FreeRewardResult = Events:WaitForChild("FreeRewardResult")

-- Returns true (favorited), false (not favorited), nil (couldn't determine).
local function checkFavorite()
	local ok, fav = pcall(function()
		return AvatarEditorService:GetFavoriteAsync(game.PlaceId, Enum.AvatarItemType.Asset)
	end)
	if ok and type(fav) == "boolean" then
		return fav
	end
	return nil
end

-- Shows the platform favorite prompt and waits for its result.
local function promptFavorite()
	local result = nil
	local conn = AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(res)
		if result == nil then
			result = res
		end
	end)
	local timedOut = false
	task.delay(30, function()
		timedOut = true
	end)
	local shown = pcall(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	local deadline = os.clock() + 30
	while result == nil and not timedOut and os.clock() < deadline do
		task.wait(0.1)
	end
	conn:Disconnect()
	if not shown then
		return false
	end
	return result == Enum.AvatarPromptResult.Success
end

local claiming = false

if ClaimButton then
	ClaimButton.Activated:Connect(function()
		SFX.play("click")
		if claiming or not MainFrame then
			return
		end
		claiming = true
		task.spawn(function()
			-- 1) FAVORITE THE GAME — check first, prompt if needed.
			local fav = checkFavorite()
			if fav ~= true then
				if not promptFavorite() then
					notify("Favorite the Game!",
						"Click favorite in the prompt to claim the free gift!", "warn")
					claiming = false
					return
				end
			end

			-- 2) JOIN THE GROUP — check first, prompt if needed.
			local okG, inGroup = pcall(function()
				return player:IsInGroup(GROUP_ID)
			end)
			if not (okG and inGroup) then
				local joined = false
				local jok, status = pcall(function()
					return GroupService:PromptJoinAsync(GROUP_ID)
				end)
				if jok then
					joined = (status == Enum.GroupMembershipStatus.Joined
						or status == Enum.GroupMembershipStatus.AlreadyMember)
				end
				if not joined then
					notify("Join the Group!",
						"Join the group in the prompt to claim the free gift!", "warn")
					claiming = false
					return
				end
			end

			-- 3) Both requirements met: server re-checks and grants the reward.
			ClaimFreeReward:FireServer()
			-- Safety: if the result ever fails to arrive, re-enable the button.
			task.delay(10, function()
				claiming = false
			end)
		end)
	end)
end

if CloseButton then
	CloseButton.Activated:Connect(function()
		SFX.play("click")
		closeGiftGui()
	end)
end

FreeRewardResult.OnClientEvent:Connect(function(success, message)
	claiming = false
	if success then
		notify("Free Gift Claimed!", tostring(message), "success")
		closeGiftGui()
	else
		notify("Free Gift", tostring(message), "warn")
	end
end)
