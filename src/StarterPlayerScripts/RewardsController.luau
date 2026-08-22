--!strict
-- RewardsController.luau
-- Client controller for Rewards system (Playtime, Daily, Group, Social, VIP, Robux Spent)
-- Features:
-- 1. Playtime formatting in hours if >= 60 minutes ("1 hr", "1 hr 30 min", "2 hrs", etc.).
-- 2. Clean integration with UIWindowsController for reliable open/close toggling.
-- 3. Robust GameUI resolution and responsive UI updates.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local RS = game:GetService("ReplicatedStorage")

local NumberFormat = require(RS:WaitForChild("NumberFormat"))

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

-- Safely locate GameUI / GameGui ScreenGui
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

local openBtn = findObject(gameGui, { "OpenRewardsBtn", "RewardsBtn" }) :: GuiButton?
local root = findObject(gameGui, { "RewardsF", "RewardsFrame", "RewardsPanel" }) :: GuiObject?

if not root then
	local ok, res = pcall(function()
		return gameGui:WaitForChild("RewardsF", 8)
	end)
	if ok and res then
		root = res :: GuiObject
	end
end

if not root then
	warn("[RewardsController] RewardsF not found in GameUI")
	return
end

local closeBtn = findObject(root, { "CloseBtn", "Close", "XBtn" }) :: GuiButton?
local leftTabs = findObject(root, { "LeftTabs", "Tabs" }) :: GuiObject?
local content = findObject(root, { "Content", "ContentFrame" }) :: GuiObject?
local titleLbl = content and (findObject(content, { "CategoryTitle", "TitleLbl" }) :: TextLabel?)
local subLbl = content and (findObject(content, { "CategorySubtitle", "SubLbl", "SubtitleLbl" }) :: TextLabel?)
local rowsScroll = content and (findObject(content, { "RowsScroll", "Scroll", "RowsContainer" }) :: ScrollingFrame?)
local rowTemplate = rowsScroll and (findObject(rowsScroll, { "RowTemplate", "Template" }) :: GuiObject?)

local Events = RS:WaitForChild("Events", 15)
local RewardSync = Events and (Events:FindFirstChild("RewardSync") or Events:WaitForChild("RewardSync", 10)) :: RemoteEvent?
local RewardClaim = Events and (Events:FindFirstChild("RewardClaim") or Events:WaitForChild("RewardClaim", 10)) :: RemoteEvent?
local RewardRequestSync = Events and (Events:FindFirstChild("RewardRequestSync") or Events:WaitForChild("RewardRequestSync", 10)) :: RemoteEvent?
local SocialVisit = Events and (Events:FindFirstChild("SocialVisit") or Events:WaitForChild("SocialVisit", 10)) :: RemoteEvent?

local TAB_TO_CAT = {
	PlaytimeBtn   = "playtime",
	DailyBtn      = "daily",
	GroupBtn      = "group",
	SocialBtn     = "social",
	VipDailyBtn   = "vipdaily",
	RobuxSpentBtn = "robuxspent",
}

local CAT_TITLE = {
	playtime   = "Playtime Rewards",
	daily      = "Daily Rewards",
	group      = "Group Rewards",
	social     = "Social Rewards",
	vipdaily   = "VIP Daily Rewards",
	robuxspent = "Robux Spent Rewards",
}

local SOCIAL_DEVS = {
	{ username = "TheCoolBaconHairIsMe", userId = 3107183806 },
	{ username = "YurisMatrix",          userId = 3721585498 },
}

local REWARD_IMAGES = {
	["cash_200"]    = "rbxassetid://73475281808267",
	["cash_250"]    = "rbxassetid://95709817514797",
	["cash_300"]    = "rbxassetid://72562550267593",
	["cash_350"]    = "rbxassetid://136984600835859",
	["cash_400"]    = "rbxassetid://111851628253582",
	["cash_450"]    = "rbxassetid://127353088289605",
	["cash_500"]    = "rbxassetid://121749597294959",
	["cash_600"]    = "rbxassetid://88543138919395",
	["cash_650"]    = "rbxassetid://133672122839712",
	["cash_800"]    = "rbxassetid://125003786053473",
	["cash_1000"]   = "rbxassetid://105125784128656",
	["cash_2000"]   = "rbxassetid://108333874006118",
	["cash_4000"]   = "rbxassetid://118689386769573",
	["cash_8000"]   = "rbxassetid://109102845128329",
	["cash_15000"]  = "rbxassetid://132457307373540",
	["cash_30000"]  = "rbxassetid://136730063156531",
	["magnifier_1"] = "rbxassetid://118444404126569",
	["magnifier_2"] = "rbxassetid://71274466836275",
	["hook_1"]      = "rbxassetid://134060934663289",
	["hook_2"]      = "rbxassetid://98436490057054",
	["mystery_1"]   = "rbxassetid://133477499555789",
	["mystery_2"]   = "rbxassetid://97784274802455",
	["time_5min"]   = "rbxassetid://134246698110119",
	["time_15min"]  = "rbxassetid://74897415127747",
}

local REWARD_PATTERNS = {
	{ pattern = "+%$200",       image = "cash_200" },
	{ pattern = "+%$250",       image = "cash_250" },
	{ pattern = "+%$300",       image = "cash_300" },
	{ pattern = "+%$350",       image = "cash_350" },
	{ pattern = "+%$400",       image = "cash_400" },
	{ pattern = "+%$450",       image = "cash_450" },
	{ pattern = "+%$500",       image = "cash_500" },
	{ pattern = "+%$600",       image = "cash_600" },
	{ pattern = "+%$650",       image = "cash_650" },
	{ pattern = "+%$800",       image = "cash_800" },
	{ pattern = "+%$1000",      image = "cash_1000" },
	{ pattern = "+%$2000",      image = "cash_2000" },
	{ pattern = "+%$4000",      image = "cash_4000" },
	{ pattern = "+%$8000",      image = "cash_8000" },
	{ pattern = "+%$15000",     image = "cash_15000" },
	{ pattern = "+%$30000",     image = "cash_30000" },
	{ pattern = "+1 Magnifier", image = "magnifier_1" },
	{ pattern = "+2 Magnifier", image = "magnifier_2" },
	{ pattern = "+1 Hook",      image = "hook_1" },
	{ pattern = "+2 Hook",      image = "hook_2" },
	{ pattern = "+1 Mystery",   image = "mystery_1" },
	{ pattern = "+2 Mystery",   image = "mystery_2" },
	{ pattern = "x2 5min",      image = "time_5min" },
	{ pattern = "x2 15min",     image = "time_15min" },
}

local payload: any = nil
local activeCat = "playtime"
local playtimeSeconds = 0
local dailyCountdown = 0
local lastTick = tick()
local updateConn: RBXScriptConnection? = nil
local rowPageState: { [string]: { page: number } } = {}

local function requestSync()
	if RewardRequestSync and RewardRequestSync:IsA("RemoteEvent") then
		RewardRequestSync:FireServer()
	end
end

local function stopLiveUpdater()
	if updateConn then
		updateConn:Disconnect()
		updateConn = nil
	end
end

local function clearRows()
	if not rowsScroll then
		return
	end
	for _, c in ipairs(rowsScroll:GetChildren()) do
		if c:IsA("Frame") and c ~= rowTemplate then
			c:Destroy()
		end
	end
end

local function parseRewardImages(rewardsText: string): { string }
	local images = {}
	local txt = tostring(rewardsText or "")
	for _, p in ipairs(REWARD_PATTERNS) do
		if string.find(txt, p.pattern, 1, true) or string.find(txt, p.pattern) then
			table.insert(images, p.image)
		end
	end
	return images
end

local function styleClaim(btn: TextButton, row: any, categoryId: string)
	if row.claimed then
		btn.Text = "CLAIMED"
		btn.BackgroundColor3 = Color3.fromRGB(60, 220, 60)
		btn.Active = false
		btn.AutoButtonColor = false
	elseif row.ready then
		btn.Text = "CLAIM"
		btn.BackgroundColor3 = Color3.fromRGB(60, 220, 60)
		btn.Active = true
		btn.AutoButtonColor = true
	elseif categoryId == "social" then
		btn.Text = "VISIT"
		btn.BackgroundColor3 = Color3.fromRGB(70, 140, 255)
		btn.Active = true
		btn.AutoButtonColor = true
	else
		btn.Text = "NOT READY"
		btn.BackgroundColor3 = Color3.fromRGB(140, 140, 140)
		btn.Active = false
		btn.AutoButtonColor = false
	end
	btn.ZIndex = 20
end

local function loadProfileImage(imageLabel: ImageLabel, userId: number)
	if userId == 0 then
		imageLabel.Image = "rbxassetid://0"
		return
	end
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)
	imageLabel.Image = (ok and url) or "rbxassetid://0"
end

local function ensureBottomOwnerLabel(rowObj: GuiObject): TextLabel
	local bottomLbl = rowObj:FindFirstChild("BottomOwnerLbl") :: TextLabel?
	if not bottomLbl then
		bottomLbl = Instance.new("TextLabel")
		bottomLbl.Name = "BottomOwnerLbl"
		bottomLbl.BackgroundTransparency = 1
		bottomLbl.Size = UDim2.new(0.3, 0, 0.28, 0)
		bottomLbl.Position = UDim2.new(0.03, 0, 0.68, 0)
		bottomLbl.Font = Enum.Font.GothamBold
		bottomLbl.TextScaled = true
		bottomLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		bottomLbl.TextStrokeTransparency = 0.5
		bottomLbl.Parent = rowObj
	end
	return bottomLbl
end

local function buildRewardPager(container: GuiObject, template: ImageLabel, rowKey: string, rewardImageKeys: { string })
	for _, c in ipairs(container:GetChildren()) do
		if c:GetAttribute("RewardClone") == true then
			c:Destroy()
		end
	end

	local leftBtn = container:FindFirstChild("LeftBtn") :: TextButton?
	local rightBtn = container:FindFirstChild("RightBtn") :: TextButton?
	local pageLbl = container:FindFirstChild("PageLbl") :: TextLabel?

	local count = #rewardImageKeys
	if count == 0 then
		if leftBtn then leftBtn.Visible = false end
		if rightBtn then rightBtn.Visible = false end
		if pageLbl then pageLbl.Visible = false end
		return
	end

	local iconSize = 64
	local spacing = 8
	local containerWidth = container.AbsoluteSize.X > 0 and container.AbsoluteSize.X or 220
	local iconsPerPage = math.max(1, math.floor((containerWidth + spacing) / (iconSize + spacing)))
	local totalPages = math.max(1, math.ceil(count / iconsPerPage))

	local rowState = rowPageState[rowKey] or { page = 1 }
	rowPageState[rowKey] = rowState

	local function renderPage()
		for _, c in ipairs(container:GetChildren()) do
			if c:GetAttribute("RewardClone") == true then
				c:Destroy()
			end
		end

		rowState.page = math.clamp(rowState.page, 1, totalPages)
		local startIdx = (rowState.page - 1) * iconsPerPage + 1
		local endIdx = math.min(count, startIdx + iconsPerPage - 1)
		local visible = endIdx - startIdx + 1
		local totalW = visible * iconSize + (visible - 1) * spacing
		local startX = math.max(0, (container.AbsoluteSize.X - totalW) / 2)

		for i = startIdx, endIdx do
			local li = i - startIdx + 1
			local img = template:Clone()
			img.Visible = true
			img.Image = REWARD_IMAGES[rewardImageKeys[i]] or rewardImageKeys[i]
			img.Size = UDim2.new(0, iconSize, 0, iconSize)
			img.Position = UDim2.new(0, startX + (li - 1) * (iconSize + spacing), 0.5, -iconSize / 2)
			img.ZIndex = 3
			img.Active = false
			img:SetAttribute("RewardClone", true)
			img.Parent = container
		end

		if leftBtn then
			leftBtn.Visible = totalPages > 1
			leftBtn.Active = rowState.page > 1
			leftBtn.TextTransparency = leftBtn.Active and 0 or 0.5
		end
		if rightBtn then
			rightBtn.Visible = totalPages > 1
			rightBtn.Active = rowState.page < totalPages
			rightBtn.TextTransparency = rightBtn.Active and 0 or 0.5
		end
		if pageLbl then
			pageLbl.Visible = totalPages > 1
			pageLbl.Text = string.format("%d/%d", rowState.page, totalPages)
		end
	end

	if leftBtn and not leftBtn:GetAttribute("PagerBound") then
		leftBtn.MouseButton1Click:Connect(function()
			local st = rowPageState[rowKey] or { page = 1 }
			st.page -= 1
			rowPageState[rowKey] = st
			renderPage()
		end)
		leftBtn:SetAttribute("PagerBound", true)
	end

	if rightBtn and not rightBtn:GetAttribute("PagerBound") then
		rightBtn.MouseButton1Click:Connect(function()
			local st = rowPageState[rowKey] or { page = 1 }
			st.page += 1
			rowPageState[rowKey] = st
			renderPage()
		end)
		rightBtn:SetAttribute("PagerBound", true)
	end

	renderPage()
end

local function setupRowContent(clone: GuiObject, categoryId: string, rowIndex: number, rowData: any)
	local leftLbl = clone:FindFirstChild("LeftLbl", true) :: TextLabel?
	local container = clone:FindFirstChild("RewardsContainer", true) :: GuiObject?
	if not container then
		return
	end

	local template = container:FindFirstChild("ImageTemplate") :: ImageLabel?
	if not template or not template:IsA("ImageLabel") then
		return
	end
	template.Visible = false
	template.ZIndex = 3

	local bottomLbl = ensureBottomOwnerLabel(clone)
	bottomLbl.Visible = false
	bottomLbl.Text = ""

	if leftLbl and leftLbl:IsA("TextLabel") then
		if categoryId == "playtime" then
			-- REQUIREMENT: Display in hours if >= 60 minutes!
			local rawMins = tonumber(rowData.requiredMin) or tonumber(string.match(tostring(rowData.left or ""), "(%d+)"))
			if rawMins then
				leftLbl.Text = NumberFormat.formatPlaytimeRequirement(rawMins)
			else
				leftLbl.Text = tostring(rowData.left or "")
			end
		elseif categoryId == "daily" then
			leftLbl.Text = "Day " .. tostring(rowIndex)
		elseif categoryId == "group" then
			leftLbl.Text = "Group"
		elseif categoryId == "vipdaily" then
			leftLbl.Text = "VIP"
		elseif categoryId == "robuxspent" then
			leftLbl.Text = tostring(rowData.left or "")
		elseif categoryId == "social" then
			leftLbl.Text = ""
		end
	end

	if categoryId == "social" and SOCIAL_DEVS[rowIndex] and leftLbl then
		local dev = SOCIAL_DEVS[rowIndex]
		clone:SetAttribute("SocialUserId", dev.userId)
		leftLbl.Text = ""
		leftLbl.ClipsDescendants = true

		local img = leftLbl:FindFirstChild("ProfileImage") :: ImageLabel?
		if not img then
			img = Instance.new("ImageLabel")
			img.Name = "ProfileImage"
			img.BackgroundTransparency = 1
			img.Size = UDim2.new(0.32, 0, 0.82, 0)
			img.Position = UDim2.new(0.03, 0, 0.5, 0)
			img.AnchorPoint = Vector2.new(0, 0.5)
			img.ScaleType = Enum.ScaleType.Fit
			img.Parent = leftLbl
		end

		bottomLbl.Visible = true
		bottomLbl.Text = "Owner: @" .. dev.username
		loadProfileImage(img, dev.userId)
	end

	local keys = parseRewardImages(rowData.rewards or "")
	local rowKey = tostring(categoryId) .. ":" .. tostring(rowData.id or rowIndex)
	buildRewardPager(container, template, rowKey, keys)
end

-- REQUIREMENT: Subtitle displays hours if played >= 60 minutes
local function refreshCategorySubtitle()
	if not subLbl then
		return
	end
	if not payload or not activeCat then
		subLbl.Text = ""
		return
	end

	if activeCat == "robuxspent" then
		subLbl.Text = string.format("Total Robux spent: R$%d", tonumber(payload.robuxSpentTotal) or 0)
	elseif activeCat == "playtime" then
		-- Use readable format: e.g. "You played for 1 hr 15 min 20 sec" or "You played for 25 min 10 sec"
		subLbl.Text = "You played for " .. NumberFormat.formatPlaytimePlayed(playtimeSeconds)
	elseif activeCat == "daily" then
		subLbl.Text = dailyCountdown > 0 and ("Ready to claim in " .. NumberFormat.formatTime(dailyCountdown)) or "Daily reward ready"
	elseif activeCat == "social" then
		subLbl.Text = "Visit the owners and claim your rewards!"
	elseif activeCat == "group" then
		subLbl.Text = "Like the game + Join the group"
	elseif activeCat == "vipdaily" then
		subLbl.Text = "Become VIP to claim"
	else
		subLbl.Text = ""
	end
end

local function startLiveUpdater()
	stopLiveUpdater()
	lastTick = tick()

	updateConn = RunService.Heartbeat:Connect(function()
		if not payload or not activeCat then
			return
		end
		local now = tick()
		local dt = now - lastTick
		lastTick = now

		if activeCat == "playtime" then
			playtimeSeconds += dt
			refreshCategorySubtitle()
		elseif activeCat == "daily" then
			dailyCountdown = math.max(0, dailyCountdown - dt)
			refreshCategorySubtitle()
		end
	end)
end

local function renderRows()
	clearRows()
	if not rowsScroll or not rowTemplate then
		return
	end
	rowPageState = {}

	local rows = payload and payload.categories and payload.categories[activeCat] or {}
	local y = 6
	local rowH = rowTemplate.Size.Y.Offset > 0 and rowTemplate.Size.Y.Offset or 100
	local gap = 10

	for idx, row in ipairs(rows) do
		local clone = rowTemplate:Clone()
		clone.Visible = true
		clone.Name = "Row_" .. tostring(row.id or idx)
		clone.Position = UDim2.new(rowTemplate.Position.X.Scale, rowTemplate.Position.X.Offset, 0, y)
		clone.Size = UDim2.new(rowTemplate.Size.X.Scale, rowTemplate.Size.X.Offset, 0, rowH)
		clone.Parent = rowsScroll

		setupRowContent(clone, activeCat, idx, row)

		local claimBtn = clone:FindFirstChild("ClaimBtn", true) :: TextButton?
		if claimBtn and claimBtn:IsA("TextButton") then
			styleClaim(claimBtn, row, activeCat)

			claimBtn.MouseButton1Click:Connect(function()
				if activeCat == "social" and not row.ready and not row.claimed then
					pcall(function()
						SocialService:PromptGameInvite(player)
					end)
					if SocialVisit then
						SocialVisit:FireServer(row.id)
					end
					task.delay(1, requestSync)
					task.delay(3, requestSync)
					task.delay(5.5, requestSync)
					return
				end

				if row.ready and not row.claimed then
					if RewardClaim then
						RewardClaim:FireServer(activeCat, row.id)
					end
				end
			end)
		end

		y += rowH + gap
	end

	rowsScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	rowsScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(y + 8, rowsScroll.AbsoluteSize.Y + 1))
end

local function render()
	if titleLbl then
		titleLbl.Text = CAT_TITLE[activeCat] or "Rewards"
	end

	if not payload then
		stopLiveUpdater()
		if subLbl then
			subLbl.Text = "Waiting for server sync..."
		end
		clearRows()
		return
	end

	if activeCat == "playtime" then
		playtimeSeconds = tonumber(payload.totalPlaytime) or 0
		startLiveUpdater()
	elseif activeCat == "daily" then
		dailyCountdown = tonumber(payload.dailyCountdown) or 0
		startLiveUpdater()
	else
		stopLiveUpdater()
	end

	refreshCategorySubtitle()
	renderRows()
end

local function selectCategory(cat: string)
	activeCat = cat
	render()
end

-- Connect Tab buttons
if leftTabs then
	for btnName, cat in pairs(TAB_TO_CAT) do
		local btn = leftTabs:FindFirstChild(btnName, true) :: GuiButton?
		if btn and btn:IsA("GuiButton") then
			btn.MouseButton1Click:Connect(function()
				selectCategory(cat)
			end)
		end
	end
end

-- Hook global events for UIWindowsController
_G.OnRewardsOpen = function()
	if rowsScroll then
		rowsScroll.CanvasPosition = Vector2.zero
		rowsScroll.ScrollingEnabled = true
	end
	requestSync()
	render()
end

_G.OnRewardsClose = function()
	stopLiveUpdater()
	if rowsScroll then
		rowsScroll.CanvasPosition = Vector2.zero
	end
end

if RewardSync and RewardSync:IsA("RemoteEvent") then
	RewardSync.OnClientEvent:Connect(function(newPayload)
		if type(newPayload) ~= "table" then
			return
		end
		payload = newPayload
		if root.Visible then
			render()
		end
	end)
end

-- Initial sync
requestSync()

print("[RewardsController] Ready - Playtime hours formatting & window manager synced")
