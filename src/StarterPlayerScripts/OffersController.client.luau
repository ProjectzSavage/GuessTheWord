--[[
	OffersController.client.luau
	----------------------------------------------------------------------------
	Run this as a **LocalScript** in StarterPlayerScripts.

	PURPOSE
	Drives the OffersUi HUD (RightStack and StarterPopup):
	  * CycleGpBtn: Automatically cycles through all gamepasses in the game
	    (VIP, 2x Streak, 2x Cash, 2x Wins) with smooth fade + bounce transitions.
	    Clicking prompts the purchase for the currently displayed gamepass.
	  * StarterPackBtn: Opens the Starter Pack popup displaying reward cards.
	  * StarterPopup: Displays rewards and allows purchasing the Starter Pack.

	HIERARCHY:
		GameUI (ScreenGui)
		└── OffersUi (Frame)
		    ├── RightStack (Frame)
		    │   ├── UIListLayout (UIListLayout)
		    │   ├── CycleGpBtn (TextButton)
		    │   │   ├── PriceWrap (Frame)
		    │   │   │   ├── Coin (ImageLabel)
		    │   │   │   └── PriceLbl (TextLabel)
		    │   │   ├── OfferIcon (ImageLabel)
		    │   │   └── NameLbl (TextLabel)
		    │   └── StarterPackBtn (TextButton)
		    │       ├── PriceWrap (Frame)
		    │       │   ├── Coin (ImageLabel)
		    │       │   └── PriceLbl (TextLabel)
		    │       ├── OfferIcon (ImageLabel)
		    │       └── NameLbl (TextLabel)
		    └── StarterPopupBg (Frame)
		        └── StarterPopup (ImageLabel)
		            ├── IconRow (Frame)
		            │   ├── UIListLayout (UIListLayout)
		            │   ├── RewardCard1 (Frame)
		            │   │   ├── Icon (ImageLabel)
		            │   │   └── Text (TextLabel)
		            │   ├── RewardCard2 (Frame)
		            │   └── RewardCard3 (Frame)
		            ├── BuyBtn (TextButton)
		            │   ├── BuyCoin (ImageLabel)
		            │   └── BuyPrice (TextLabel)
		            ├── CloseBtn (TextButton)
		            └── Title (TextLabel)
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SFX = require(ReplicatedStorage:WaitForChild("SFX"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Safely locate GameUI
local function resolveGameUI(): Instance
	local target = playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("GameGui")
	if target then
		return target
	end

	local startTime = os.clock()
	while (os.clock() - startTime) < 10 do
		target = playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("GameGui")
		if target then
			return target
		end
		task.wait(0.1)
	end

	return playerGui:FindFirstChildWhichIsA("ScreenGui") or playerGui
end

local gameUI = resolveGameUI()

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

local offersUi = findObject(gameUI, { "OffersUi", "OffersFrame", "Offers" }) :: GuiObject?
if not offersUi then
	local ok, res = pcall(function()
		return gameUI:WaitForChild("OffersUi", 8)
	end)
	if ok and res then
		offersUi = res :: GuiObject
	end
end

if not offersUi then
	warn("[OffersController] OffersUi not found in GameUI")
	return
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local STARTER_PACK_GAMEPASS_ID = 1958400378 -- GamePass id (Creator Hub)
local STARTER_PACK_PRICE = "3" -- edit this to your real price (Creator Hub)

local GAMEPASS_OFFERS = {
	{ id = 1960374374, name = "VIP",       priceText = "189", icon = "rbxassetid://76065691872422" },
	{ id = 1958292387, name = "2x Streak", priceText = "45",  icon = "rbxassetid://98967636309470" },
	{ id = 1958940384, name = "2x Cash",   priceText = "49",  icon = "rbxassetid://84241673549927" },
	{ id = 1960056393, name = "2x Wins",   priceText = "59",  icon = "rbxassetid://138458249983109" },
}

local STARTER_REWARDS = {
	{ icon = "rbxassetid://106595471170578", text = "+1 Reveal Letter" },
	{ icon = "rbxassetid://133477499555789", text = "Random Chair" },
	{ icon = "rbxassetid://121749597294959", text = "+$500 CASH" },
}

-- ============================================================================
-- HIERARCHY REFERENCES
-- ============================================================================
local rightStack = findObject(offersUi, { "RightStack", "Stack" }) :: GuiObject?

local starterBtn = rightStack and (findObject(rightStack, { "StarterPackBtn", "StarterBtn" }) :: GuiButton?)
local cycleGpBtn = rightStack and (findObject(rightStack, { "CycleGpBtn", "GamepassBtn" }) :: GuiButton?)

local starterOfferIcon = starterBtn and (findObject(starterBtn, { "OfferIcon", "Icon" }) :: ImageLabel?)
local starterPriceWrap = starterBtn and (findObject(starterBtn, { "PriceWrap", "PriceFrame" }) :: GuiObject?)
local starterPriceLbl = starterPriceWrap and (findObject(starterPriceWrap, { "PriceLbl", "PriceText" }) :: TextLabel?)
local starterNameLbl = starterBtn and (findObject(starterBtn, { "NameLbl", "TitleLbl" }) :: TextLabel?)

local gpOfferIcon = cycleGpBtn and (findObject(cycleGpBtn, { "OfferIcon", "Icon" }) :: ImageLabel?)
local gpPriceWrap = cycleGpBtn and (findObject(cycleGpBtn, { "PriceWrap", "PriceFrame" }) :: GuiObject?)
local gpPriceLbl = gpPriceWrap and (findObject(gpPriceWrap, { "PriceLbl", "PriceText" }) :: TextLabel?)
local gpNameLbl = cycleGpBtn and (findObject(cycleGpBtn, { "NameLbl", "TitleLbl" }) :: TextLabel?)

local popupBg = findObject(offersUi, { "StarterPopupBg", "PopupBg", "StarterBackground" }) :: GuiObject?
local popup = popupBg and (findObject(popupBg, { "StarterPopup", "Popup" }) :: GuiObject?)
local popupTitle = popup and (findObject(popup, { "Title", "TitleLbl" }) :: TextLabel?)
local closeBtn = popup and (findObject(popup, { "CloseBtn", "Close", "XBtn" }) :: GuiButton?)

local iconRow = popup and (findObject(popup, { "IconRow", "RewardsRow" }) :: GuiObject?)
local rewardCard1 = iconRow and (findObject(iconRow, { "RewardCard1", "Card1" }) :: GuiObject?)
local rewardCard2 = iconRow and (findObject(iconRow, { "RewardCard2", "Card2" }) :: GuiObject?)
local rewardCard3 = iconRow and (findObject(iconRow, { "RewardCard3", "Card3" }) :: GuiObject?)

local buyBtn = popup and (findObject(popup, { "BuyBtn", "PurchaseBtn" }) :: GuiButton?)
local buyPrice = buyBtn and (findObject(buyBtn, { "BuyPrice", "PriceLbl" }) :: TextLabel?)

-- ============================================================================
-- SETUP & POPULATE LABELS
-- ============================================================================
if starterNameLbl then starterNameLbl.Text = "Starter Pack" end
if popupTitle then popupTitle.Text = "STARTER PACK!" end

-- Set the starter pack price in BOTH spots (the button + the popup BuyBtn).
-- The text comes from STARTER_PACK_PRICE in the CONFIG above (edit it there).
local function setStarterPrice(priceNumber)
	local text = tostring(priceNumber)
	if starterPriceLbl then starterPriceLbl.Text = text end
	if buyPrice then buyPrice.Text = "R$ " .. text end
end
setStarterPrice(STARTER_PACK_PRICE)

local rewardCards = { rewardCard1, rewardCard2, rewardCard3 }
for i, card in ipairs(rewardCards) do
	local data = STARTER_REWARDS[i]
	if card and data then
		local icon = findObject(card, { "Icon", "RewardIcon" }) :: ImageLabel?
		local text = findObject(card, { "Text", "RewardText" }) :: TextLabel?
		if icon and icon:IsA("ImageLabel") then
			icon.Image = data.icon
		end
		if text and text:IsA("TextLabel") then
			text.Text = data.text
		end
	end
end

-- ============================================================================
-- STARTER PACK POPUP INTERACTIONS
-- ============================================================================
if popupBg then
	popupBg.Visible = false
end

if starterBtn then
	starterBtn.Activated:Connect(function()
		if not popupBg or not popup then return end
		popupBg.Visible = true
		popup.Visible = true

		local s = popup:FindFirstChildOfClass("UIScale")
		if not s then
			s = Instance.new("UIScale")
			s.Parent = popup
		end
		s.Scale = 0.8
		TweenService:Create(
			s,
			TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end)
end

if closeBtn then
	closeBtn.Activated:Connect(function()
		if popupBg then
			popupBg.Visible = false
		end
	end)
end

if buyBtn then
	buyBtn.Activated:Connect(function()
		if STARTER_PACK_GAMEPASS_ID > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, STARTER_PACK_GAMEPASS_ID)
			end)
			if ok and owns then
				return -- already owned (the rewards were granted on purchase)
			end
		SFX.play("robuxClick")
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, STARTER_PACK_GAMEPASS_ID)
		end)
		end
	end)
end

-- ============================================================================
-- GAMEPASS CYCLER (Cycles all gamepasses every 3.8 seconds)
-- ============================================================================
local gpIndex = 1

local gpScale = cycleGpBtn and cycleGpBtn:FindFirstChildOfClass("UIScale")
if cycleGpBtn and not gpScale then
	gpScale = Instance.new("UIScale")
	gpScale.Scale = 1
	gpScale.Parent = cycleGpBtn
end

local function renderCurrentGp()
	local gp = GAMEPASS_OFFERS[gpIndex] or GAMEPASS_OFFERS[1]
	if not gp then return end

	if gpOfferIcon then
		gpOfferIcon.Image = gp.icon
	end
	if gpNameLbl then
		gpNameLbl.Text = gp.name
	end
	if gpPriceLbl then
		gpPriceLbl.Text = gp.priceText
	end
end

local function animateGpChange()
	if not cycleGpBtn then return end

	local tweensOut = {}
	if gpOfferIcon then table.insert(tweensOut, TweenService:Create(gpOfferIcon, TweenInfo.new(0.12), { ImageTransparency = 0.4 })) end
	if gpNameLbl then table.insert(tweensOut, TweenService:Create(gpNameLbl, TweenInfo.new(0.12), { TextTransparency = 0.4 })) end
	if gpPriceLbl then table.insert(tweensOut, TweenService:Create(gpPriceLbl, TweenInfo.new(0.12), { TextTransparency = 0.4 })) end

	for _, tw in ipairs(tweensOut) do tw:Play() end
	task.wait(0.12)

	renderCurrentGp()

	local tweensIn = {}
	if gpOfferIcon then table.insert(tweensIn, TweenService:Create(gpOfferIcon, TweenInfo.new(0.12), { ImageTransparency = 0 })) end
	if gpNameLbl then table.insert(tweensIn, TweenService:Create(gpNameLbl, TweenInfo.new(0.12), { TextTransparency = 0 })) end
	if gpPriceLbl then table.insert(tweensIn, TweenService:Create(gpPriceLbl, TweenInfo.new(0.12), { TextTransparency = 0 })) end

	for _, tw in ipairs(tweensIn) do tw:Play() end

	if gpScale then
		local p1 = TweenService:Create(gpScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.06 })
		local p2 = TweenService:Create(gpScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.0 })
		p1:Play()
		p1.Completed:Connect(function()
			p2:Play()
		end)
	end
end

renderCurrentGp()

	if cycleGpBtn then
		cycleGpBtn.Activated:Connect(function()
			local gp = GAMEPASS_OFFERS[gpIndex] or GAMEPASS_OFFERS[1]
			if gp and gp.id and gp.id > 0 then
				SFX.play("robuxClick")
				pcall(function()
					MarketplaceService:PromptGamePassPurchase(player, gp.id)
				end)
			end
		end)
	end

-- Automatic gamepass cycling loop
task.spawn(function()
	while offersUi and offersUi.Parent do
		task.wait(3.8)
		gpIndex = (gpIndex % #GAMEPASS_OFFERS) + 1
		animateGpChange()
	end
end)

-- Gentle sway animation for offer buttons
if starterBtn or cycleGpBtn then
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if starterBtn then
			starterBtn.Rotation = math.sin(t * 2.0) * 2.5
		end
		if cycleGpBtn then
			cycleGpBtn.Rotation = math.sin(t * 2.0 + 1.2) * 2.5
		end
	end)
end

-- ============================================================================
-- PRICES
-- No live price fetching - the RightStack prices are the text in this
-- script's CONFIG above, which you edit to match Creator Hub:
--   * GAMEPASS_OFFERS: the `priceText` field of each entry (cycling button)
--   * STARTER_PACK_PRICE: the starter pack (button + popup BuyPrice)
-- The purchase itself always uses the real id, so Roblox charges whatever
-- price you set in Creator Hub for that pass.
-- ============================================================================


