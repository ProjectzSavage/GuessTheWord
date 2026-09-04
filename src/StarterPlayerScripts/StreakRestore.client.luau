--[[
	StreakRestore.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	When your streak is broken (you lose a match or it's a draw), the server
	fires RestoreStreakPrompt and this script pops up the "Restore" frame for
	5 SECONDS. Clicking the button prompts the buy-back dev product (the
	server picks which one based on how big your lost streak was: under 10
	uses one product, 10+ uses the other). If you don't buy in time, the
	frame outros on its own. On a confirmed purchase the server restores the
	streak and fires RestoreStreakResult, which closes the frame.

	HIERARCHY (in StarterGui.GameUI):
		GameUI  (ScreenGui)
		└── Restore  (Frame)
		    └── TextButton  (TextButton)   the buy button (your label/look)
		        └── PriceLbl  (TextLabel)  auto-filled with the real product price
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SFX = require(ReplicatedStorage:WaitForChild("SFX"))
local UIFX = require(ReplicatedStorage:WaitForChild("UIFX"))

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local GameUI = PlayerGui:WaitForChild("GameUI")
local RestoreFrame = GameUI:WaitForChild("Restore", 10)
if not RestoreFrame then
	warn("[StreakRestore] GameUI.Restore frame not found - streak restore UI disabled.")
	return
end

-- The buy button: named "TextButton", but fall back to whatever TextButton
-- is inside Restore (recursive).
local buyButton = RestoreFrame:FindFirstChild("TextButton")
		or RestoreFrame:FindFirstChildOfClass("TextButton")
		or RestoreFrame:FindFirstChildWhichIsA("TextButton", true)
if not buyButton or not buyButton:IsA("GuiButton") then
	warn("[StreakRestore] Restore.TextButton (the buy button) not found - streak restore UI disabled.")
	return
end
local priceLbl = buyButton:FindFirstChild("PriceLbl", true)

local PROMPT_SECONDS = 5

local Events = ReplicatedStorage:WaitForChild("Events")
local RestoreStreakPrompt = Events:FindFirstChild("RestoreStreakPrompt")
local RestoreStreakResult = Events:FindFirstChild("RestoreStreakResult")
local RoundStart = Events:FindFirstChild("RoundStart")

-- Generation counter: an old 5-second timer must never outro a NEW prompt.
local gen = 0
local currentProductId = nil

local function fetchPriceText(productId)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
	end)
	if ok and type(info) == "table" then
		-- PriceInRobux / Price are ALREADY in Robux (not cents).
		local robux = tonumber(info.PriceInRobux) or tonumber(info.Price)
		if robux then
			return "R$" .. math.floor(robux)
		end
	end
	return nil
end

local function showPrompt(lostStreak, productId)
	gen += 1
	local g = gen
	currentProductId = productId

	SFX.play("notify")

	if priceLbl then
		task.spawn(function()
			local text = fetchPriceText(productId)
			if text and priceLbl.Parent then
				priceLbl.Text = text
			end
		end)
	end

	RestoreFrame.Visible = true
	UIFX.popIn(RestoreFrame)

	-- 5 seconds without a purchase -> outro.
	task.delay(PROMPT_SECONDS, function()
		if gen ~= g then
			return -- a newer prompt (or a manual hide) took over
		end
		gen += 1
		currentProductId = nil
		UIFX.popOut(RestoreFrame)
	end)
end

local function hidePrompt()
	gen += 1
	currentProductId = nil
	if RestoreFrame.Visible then
		UIFX.popOut(RestoreFrame)
	end
end

-- The script owns visibility - start hidden.
RestoreFrame.Visible = false

buyButton.Activated:Connect(function()
	if not currentProductId or currentProductId <= 0 then
		return
	end
	SFX.play("robuxClick")
	MarketplaceService:PromptProductPurchase(player, currentProductId)
	-- The frame stays up while the purchase dialog is open (a newer prompt
	-- or the timer closes it); a confirmed purchase closes it via
	-- RestoreStreakResult. Cancelling the dialog = no restore, frame closes
	-- on its own when the timer runs out.
end)

if RestoreStreakPrompt then
	RestoreStreakPrompt.OnClientEvent:Connect(function(lostStreak, productId)
		showPrompt(tonumber(lostStreak) or 0, tonumber(productId) or 0)
	end)
end

if RestoreStreakResult then
	RestoreStreakResult.OnClientEvent:Connect(function(_success, _restored)
		hidePrompt()
	end)
end

-- A new match starts -> the prompt is stale, close it.
if RoundStart then
	RoundStart.OnClientEvent:Connect(function()
		hidePrompt()
	end)
end
