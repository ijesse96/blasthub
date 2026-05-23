--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local MatchMaps = require(shared:WaitForChild("MatchMaps"))
local LobbyCoinProducts = require(shared:WaitForChild("LobbyCoinProducts"))
local LobbyUiConfig = require(shared:WaitForChild("LobbyUiConfig"))
local RewardUiColors = require(shared:WaitForChild("RewardUiColors"))

local FishCollectionInventory = require(script.Parent:WaitForChild("FishCollectionInventory"))
local LobbyHubActions = require(script.Parent:WaitForChild("LobbyHubActions"))

local REMOTES_NAME = "LobbyRemotes"
local REQUEST_JOIN_MAP = "RequestJoinMap"
local REQUEST_COIN_PURCHASE = "RequestCoinPurchase"
local REQUEST_DAILY_SPIN = "RequestDailySpin"
local SPIN_RESULT_NAME = "DailySpinResult"
local JOIN_RESULT_NAME = "LobbyJoinResult"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local requestJoinMap: RemoteEvent? = nil
local requestCoinPurchase: RemoteEvent? = nil
local requestDailySpin: RemoteEvent? = nil

type SubPanelId = "play" | "daily" | "shop" | nil

local activeSubPanel: SubPanelId = nil
local spinBusy = false
local joiningMapId: string? = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LobbyHub"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number?, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1.5
	stroke.Transparency = transparency or 0.35
	stroke.Parent = parent
end

local function styleLabel(label: TextLabel, textSize: number, bold: boolean?)
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextStrokeTransparency = 0.65
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 2
end

type HubMenuButtonTheme = LobbyUiConfig.HubMenuButtonTheme

type HubMenuButtonOptions = {
	name: string,
	title: string,
	subtitle: string?,
	theme: HubMenuButtonTheme,
	width: number,
	height: number,
	layoutOrder: number,
	parent: Instance,
	titleSize: number?,
}

local function makeHubMenuButton(options: HubMenuButtonOptions): TextButton
	local theme = options.theme
	local button = Instance.new("TextButton")
	button.Name = options.name
	button.Size = UDim2.fromOffset(options.width, options.height)
	button.BackgroundColor3 = theme.color
	button.BackgroundTransparency = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.LayoutOrder = options.layoutOrder
	button.ZIndex = LobbyUiConfig.Z_BUTTONS
	button.Parent = options.parent
	addCorner(button, LobbyUiConfig.BUTTON_CORNER_RADIUS)
	addStroke(button, theme.stroke, LobbyUiConfig.BUTTON_OUTER_STROKE_THICKNESS, 0.15)

	local inset = LobbyUiConfig.BUTTON_INNER_INSET
	local innerBorder = Instance.new("Frame")
	innerBorder.Name = "InnerBorder"
	innerBorder.AnchorPoint = Vector2.new(0.5, 0.5)
	innerBorder.Position = UDim2.fromScale(0.5, 0.5)
	innerBorder.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	innerBorder.BackgroundTransparency = 1
	innerBorder.Active = false
	innerBorder.ZIndex = LobbyUiConfig.Z_BUTTONS + 1
	innerBorder.Parent = button
	addCorner(innerBorder, 10)
	addStroke(innerBorder, LobbyUiConfig.BUTTON_INNER_STROKE_COLOR, LobbyUiConfig.BUTTON_INNER_STROKE_THICKNESS, 0.1)

	local titleSize = options.titleSize or 20

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = LobbyUiConfig.HUB_MENU_FONT
	titleLabel.TextSize = titleSize
	titleLabel.TextColor3 = theme.text
	titleLabel.Text = options.title
	titleLabel.ZIndex = LobbyUiConfig.Z_BUTTONS + 2
	titleLabel.Parent = button

	if options.subtitle then
		titleLabel.Position = UDim2.new(0.5, 0, 0.42, 0)
		titleLabel.Size = UDim2.new(1, -24, 0, 36)

		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.Name = "Subtitle"
		subtitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		subtitleLabel.Position = UDim2.new(0.5, 0, 0.72, 0)
		subtitleLabel.Size = UDim2.new(1, -24, 0, 22)
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Font = LobbyUiConfig.HUB_MENU_FONT
		subtitleLabel.TextSize = 13
		subtitleLabel.TextColor3 = theme.subtitle or theme.text
		subtitleLabel.Text = options.subtitle
		subtitleLabel.ZIndex = LobbyUiConfig.Z_BUTTONS + 2
		subtitleLabel.Parent = button
	else
		titleLabel.Position = UDim2.fromScale(0.5, 0.5)
		titleLabel.Size = UDim2.new(1, -24, 1, -12)
	end

	return button
end

-- Full-screen background (hides 3D lobby).
local backgroundLayer = Instance.new("Frame")
backgroundLayer.Name = "BackgroundLayer"
backgroundLayer.Size = UDim2.fromScale(1, 1)
backgroundLayer.BackgroundTransparency = 1
backgroundLayer.ZIndex = LobbyUiConfig.Z_BACKGROUND
backgroundLayer.Parent = screenGui

local bgImage = Instance.new("ImageLabel")
bgImage.Name = "BgImage"
bgImage.Size = UDim2.fromScale(1, 1)
bgImage.BackgroundColor3 = LobbyUiConfig.BACKGROUND_FALLBACK_COLOR
bgImage.BackgroundTransparency = 0
bgImage.Image = LobbyUiConfig.BACKGROUND_IMAGE
bgImage.ScaleType = Enum.ScaleType.Crop
bgImage.ZIndex = LobbyUiConfig.Z_BACKGROUND
bgImage.Parent = backgroundLayer

local bgDim = Instance.new("Frame")
bgDim.Name = "BgDim"
bgDim.Size = UDim2.fromScale(1, 1)
bgDim.BackgroundColor3 = Color3.new(0, 0, 0)
bgDim.BackgroundTransparency = LobbyUiConfig.BACKGROUND_DIM_TRANSPARENCY
bgDim.BorderSizePixel = 0
bgDim.Active = false
bgDim.ZIndex = LobbyUiConfig.Z_BACKGROUND + 1
bgDim.Parent = backgroundLayer

local buttonLayer = Instance.new("Frame")
buttonLayer.Name = "ButtonLayer"
buttonLayer.Size = UDim2.fromScale(1, 1)
buttonLayer.BackgroundTransparency = 1
buttonLayer.ZIndex = LobbyUiConfig.Z_BUTTONS
buttonLayer.Parent = screenGui

local buttonColumn = Instance.new("Frame")
buttonColumn.Name = "ButtonColumn"
buttonColumn.AnchorPoint = Vector2.new(0.5, 0.5)
buttonColumn.Position = LobbyUiConfig.HUB_BUTTON_COLUMN_POSITION
buttonColumn.Size = UDim2.fromOffset(LobbyUiConfig.HUB_BUTTON_WIDTH, 0)
buttonColumn.AutomaticSize = Enum.AutomaticSize.Y
buttonColumn.BackgroundTransparency = 1
buttonColumn.ZIndex = LobbyUiConfig.Z_BUTTONS
buttonColumn.Parent = buttonLayer

local columnLayout = Instance.new("UIListLayout")
columnLayout.FillDirection = Enum.FillDirection.Vertical
columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
columnLayout.Padding = UDim.new(0, LobbyUiConfig.HUB_BUTTON_GAP)
columnLayout.Parent = buttonColumn

local hubButtonWidth = LobbyUiConfig.HUB_BUTTON_WIDTH

local playButton = makeHubMenuButton({
	name = "Play",
	title = "PLAY",
	theme = LobbyUiConfig.PLAY_BUTTON,
	width = hubButtonWidth,
	height = LobbyUiConfig.PLAY_BUTTON_HEIGHT,
	layoutOrder = 1,
	parent = buttonColumn,
	titleSize = 26,
})

local dailyButton = makeHubMenuButton({
	name = "Daily",
	title = "Daily Rewards",
	theme = LobbyUiConfig.DAILY_BUTTON,
	width = hubButtonWidth,
	height = LobbyUiConfig.MENU_BUTTON_HEIGHT,
	layoutOrder = 2,
	parent = buttonColumn,
	titleSize = 17,
})

local shopButton = makeHubMenuButton({
	name = "Shop",
	title = "Buy Coins",
	theme = LobbyUiConfig.SHOP_BUTTON,
	width = hubButtonWidth,
	height = LobbyUiConfig.MENU_BUTTON_HEIGHT,
	layoutOrder = 3,
	parent = buttonColumn,
	titleSize = 17,
})

local collectionButton = makeHubMenuButton({
	name = "Collection",
	title = "Collection",
	theme = LobbyUiConfig.COLLECTION_BUTTON,
	width = hubButtonWidth,
	height = LobbyUiConfig.MENU_BUTTON_HEIGHT,
	layoutOrder = 4,
	parent = buttonColumn,
	titleSize = 17,
})

dailyButton.Visible = LobbyUiConfig.SHOW_DAILY_BUTTON
shopButton.Visible = LobbyUiConfig.SHOW_SHOP_BUTTON
collectionButton.Visible = LobbyUiConfig.SHOW_COLLECTION_BUTTON

-- Sub-panel overlay (play / daily / shop) — panel is sibling of scrim, not child.
local subBackdrop = Instance.new("Frame")
subBackdrop.Name = "SubBackdrop"
subBackdrop.Size = UDim2.fromScale(1, 1)
subBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
subBackdrop.BackgroundTransparency = LobbyUiConfig.SUB_BACKDROP_TRANSPARENCY
subBackdrop.Active = false
subBackdrop.Visible = false
subBackdrop.ZIndex = LobbyUiConfig.Z_SUB_BACKDROP
subBackdrop.Parent = screenGui

local panelSize = LobbyUiConfig.SUB_PANEL_SIZE
local subPanel = Instance.new("Frame")
subPanel.Name = "SubPanel"
subPanel.AnchorPoint = Vector2.new(0.5, 0.5)
subPanel.Position = UDim2.fromScale(0.5, 0.5)
subPanel.Size = UDim2.fromOffset(panelSize.X, panelSize.Y)
subPanel.BackgroundColor3 = LobbyUiConfig.SUB_PANEL_COLOR
subPanel.BackgroundTransparency = LobbyUiConfig.SUB_PANEL_TRANSPARENCY
subPanel.ClipsDescendants = false
subPanel.Visible = false
subPanel.ZIndex = LobbyUiConfig.Z_SUB_PANEL
subPanel.Parent = screenGui
addCorner(subPanel, 12)
addStroke(subPanel, LobbyUiConfig.SUB_PANEL_STROKE, 2, 0.2)

local subHeader = Instance.new("Frame")
subHeader.Name = "Header"
subHeader.Size = UDim2.new(1, 0, 0, 56)
subHeader.BackgroundColor3 = LobbyUiConfig.SUB_HEADER_COLOR
subHeader.BackgroundTransparency = 0
subHeader.BorderSizePixel = 0
subHeader.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 1
subHeader.Parent = subPanel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 12)
headerCorner.Parent = subHeader

local subTitle = Instance.new("TextLabel")
subTitle.Name = "Title"
subTitle.Position = UDim2.fromOffset(20, 10)
subTitle.Size = UDim2.new(1, -72, 1, -12)
subTitle.TextXAlignment = Enum.TextXAlignment.Left
subTitle.TextColor3 = LobbyUiConfig.SUB_TITLE_TEXT
subTitle.Text = "Menu"
styleLabel(subTitle, 26, true)
subTitle.Parent = subHeader

local subClose = Instance.new("TextButton")
subClose.Name = "Close"
subClose.AnchorPoint = Vector2.new(1, 0.5)
subClose.Position = UDim2.new(1, -14, 0.5, 0)
subClose.Size = UDim2.fromOffset(40, 40)
subClose.BackgroundColor3 = Color3.fromRGB(80, 95, 115)
subClose.Font = Enum.Font.GothamBold
subClose.TextSize = 22
subClose.TextColor3 = Color3.fromRGB(255, 255, 255)
subClose.Text = "X"
subClose.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 3
subClose.AutoButtonColor = true
subClose.Parent = subHeader
addCorner(subClose, 8)

local subBody = Instance.new("Frame")
subBody.Name = "Body"
subBody.Position = UDim2.fromOffset(14, 64)
subBody.Size = UDim2.new(1, -28, 1, -78)
subBody.BackgroundColor3 = LobbyUiConfig.SUB_BODY_COLOR
subBody.BackgroundTransparency = 0
subBody.BorderSizePixel = 0
subBody.ClipsDescendants = false
subBody.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 1
subBody.Parent = subPanel
addCorner(subBody, 8)

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
statusLabel.Position = UDim2.fromScale(0.5, 0.78)
statusLabel.Size = UDim2.fromOffset(360, 32)
statusLabel.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
statusLabel.BackgroundTransparency = 0.35
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 16
statusLabel.TextColor3 = Color3.fromRGB(220, 230, 240)
statusLabel.Text = ""
statusLabel.Visible = false
statusLabel.ZIndex = LobbyUiConfig.Z_STATUS
statusLabel.Parent = buttonLayer
addCorner(statusLabel, 8)

local mapListHost = Instance.new("Frame")
mapListHost.Name = "MapList"
mapListHost.Size = UDim2.fromScale(1, 1)
mapListHost.BackgroundTransparency = 1
mapListHost.Visible = false
mapListHost.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 2
mapListHost.Parent = subBody

local mapListLayout = Instance.new("UIListLayout")
mapListLayout.Padding = UDim.new(0, 8)
mapListLayout.SortOrder = Enum.SortOrder.LayoutOrder
mapListLayout.Parent = mapListHost

local dailyHost = Instance.new("Frame")
dailyHost.Name = "Daily"
dailyHost.Size = UDim2.fromScale(1, 1)
dailyHost.BackgroundTransparency = 1
dailyHost.Visible = false
dailyHost.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 2
dailyHost.Parent = subBody

local wheelFrame = Instance.new("Frame")
wheelFrame.Name = "Wheel"
wheelFrame.AnchorPoint = Vector2.new(0.5, 0)
wheelFrame.Position = UDim2.new(0.5, 0, 0, 8)
wheelFrame.Size = UDim2.fromOffset(140, 140)
wheelFrame.BackgroundColor3 = Color3.fromRGB(70, 82, 100)
wheelFrame.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 3
wheelFrame.Parent = dailyHost
addCorner(wheelFrame, 70)
addStroke(wheelFrame, RewardUiColors.LEGENDARY_ACCENT_GOLD, 3, 0.15)

local wheelInner = Instance.new("Frame")
wheelInner.Name = "Inner"
wheelInner.AnchorPoint = Vector2.new(0.5, 0.5)
wheelInner.Position = UDim2.fromScale(0.5, 0.5)
wheelInner.Size = UDim2.fromOffset(100, 100)
wheelInner.BackgroundColor3 = Color3.fromRGB(28, 34, 44)
wheelInner.Parent = wheelFrame
addCorner(wheelInner, 50)

local wheelAccent = Instance.new("Frame")
wheelAccent.Name = "Accent"
wheelAccent.AnchorPoint = Vector2.new(0.5, 0)
wheelAccent.Position = UDim2.new(0.5, 0, 0, 4)
wheelAccent.Size = UDim2.fromOffset(16, 36)
wheelAccent.BackgroundColor3 = RewardUiColors.LEGENDARY_ACCENT_GOLD
wheelAccent.Parent = wheelInner
addCorner(wheelAccent, 4)

local dailyDesc = Instance.new("TextLabel")
dailyDesc.Name = "Desc"
dailyDesc.Position = UDim2.fromOffset(0, 168)
dailyDesc.Size = UDim2.new(1, 0, 0, 48)
dailyDesc.TextWrapped = true
dailyDesc.TextColor3 = LobbyUiConfig.SUB_BODY_TEXT
dailyDesc.Text = "Spin once per day for $25–$150!"
styleLabel(dailyDesc, 17, false)
dailyDesc.Parent = dailyHost

local spinButton = Instance.new("TextButton")
spinButton.Name = "Spin"
spinButton.AnchorPoint = Vector2.new(0.5, 1)
spinButton.Position = UDim2.new(0.5, 0, 1, 0)
spinButton.Size = UDim2.fromOffset(200, 48)
spinButton.BackgroundColor3 = Color3.fromRGB(72, 58, 24)
spinButton.Font = Enum.Font.GothamBold
spinButton.TextSize = 20
spinButton.TextColor3 = RewardUiColors.LEGENDARY_ACCENT_GOLD
spinButton.Text = "Spin"
spinButton.AutoButtonColor = true
spinButton.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 4
spinButton.Parent = dailyHost
addCorner(spinButton, 10)
addStroke(spinButton, RewardUiColors.LEGENDARY_ACCENT_GOLD, 2, 0.3)

local shopHost = Instance.new("Frame")
shopHost.Name = "Shop"
shopHost.Size = UDim2.fromScale(1, 1)
shopHost.BackgroundTransparency = 1
shopHost.Visible = false
shopHost.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 2
shopHost.Parent = subBody

local shopDesc = Instance.new("TextLabel")
shopDesc.Name = "Desc"
shopDesc.Position = UDim2.fromOffset(0, 24)
shopDesc.Size = UDim2.new(1, 0, 0, 80)
shopDesc.TextWrapped = true
shopDesc.TextXAlignment = Enum.TextXAlignment.Center
shopDesc.TextColor3 = LobbyUiConfig.SUB_BODY_TEXT
shopDesc.Text = string.format(
	"Coin Pack\n$%d in-game cash\n(Robux purchase)",
	LobbyCoinProducts.COIN_PACK_AMOUNT
)
styleLabel(shopDesc, 19, false)
shopDesc.Parent = shopHost

local buyButton = Instance.new("TextButton")
buyButton.Name = "Buy"
buyButton.AnchorPoint = Vector2.new(0.5, 1)
buyButton.Position = UDim2.new(0.5, 0, 1, 0)
buyButton.Size = UDim2.fromOffset(220, 52)
buyButton.BackgroundColor3 = Color3.fromRGB(36, 52, 72)
buyButton.Font = Enum.Font.GothamBold
buyButton.TextSize = 20
buyButton.TextColor3 = RewardUiColors.FISH_RARE_BLUE_BRIGHT
buyButton.Text = "Buy with Robux"
buyButton.AutoButtonColor = true
buyButton.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 4
buyButton.Parent = shopHost
addCorner(buyButton, 10)
addStroke(buyButton, RewardUiColors.FISH_RARE_BLUE, 2, 0.25)

local wheelSpinTween: Tween? = nil

local function setStatus(text: string?, visible: boolean?)
	if text and text ~= "" then
		statusLabel.Text = text
		statusLabel.Visible = visible ~= false
	else
		statusLabel.Visible = false
	end
end

local function hideAllSubHosts()
	mapListHost.Visible = false
	dailyHost.Visible = false
	shopHost.Visible = false
end

local function closeSubPanel()
	activeSubPanel = nil
	subBackdrop.Visible = false
	subPanel.Visible = false
	hideAllSubHosts()
	setStatus(nil, false)
end

local function openSubPanel(panelId: SubPanelId, title: string)
	activeSubPanel = panelId
	subTitle.Text = title
	hideAllSubHosts()
	subBackdrop.Visible = true
	subPanel.Visible = true

	if panelId == "play" then
		mapListHost.Visible = true
	elseif panelId == "daily" then
		dailyHost.Visible = true
	elseif panelId == "shop" then
		shopHost.Visible = true
	end
end

LobbyHubActions.registerOpenBuyCoins(function()
	closeSubPanel()
	openSubPanel("shop", "Buy Coins")
end)

local function startWheelSpin()
	if wheelSpinTween then
		wheelSpinTween:Cancel()
	end
	wheelInner.Rotation = wheelInner.Rotation % 360
	wheelSpinTween = TweenService:Create(
		wheelInner,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Rotation = wheelInner.Rotation + 720 }
	)
	wheelSpinTween:Play()
end

local function stopWheelSpin()
	if wheelSpinTween then
		wheelSpinTween:Cancel()
		wheelSpinTween = nil
	end
end

local function buildMapRows()
	for _, child in mapListHost:GetChildren() do
		if child:IsA("GuiObject") and child ~= mapListLayout then
			child:Destroy()
		end
	end

	local maps = MatchMaps.getAll()
	table.sort(maps, function(a, b)
		return a.displayName < b.displayName
	end)

	for i, map in maps do
		local available = map.placeId ~= 0
		local row = Instance.new("TextButton")
		row.Name = "Map_" .. map.id
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = if available then LobbyUiConfig.SUB_ROW_COLOR else Color3.fromRGB(26, 30, 38)
		row.BackgroundTransparency = if available then LobbyUiConfig.SUB_ROW_TRANSPARENCY else 0.15
		row.Font = Enum.Font.GothamBold
		row.TextSize = 0
		row.Text = ""
		row.AutoButtonColor = available
		row.Active = available
		row.LayoutOrder = i
		row.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 3
		row.Parent = mapListHost
		addCorner(row, 10)
		if available then
			addStroke(row, RewardUiColors.PROFIT_STROKE, 1.5, 0.45)
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Position = UDim2.fromOffset(16, 10)
		nameLabel.Size = UDim2.new(1, -32, 0, 26)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = if available then RewardUiColors.PROFIT_GREEN else Color3.fromRGB(160, 168, 178)
		nameLabel.Text = map.displayName
		styleLabel(nameLabel, 20, true)
		nameLabel.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 4
		nameLabel.Parent = row

		local feeLabel = Instance.new("TextLabel")
		feeLabel.Position = UDim2.fromOffset(16, 34)
		feeLabel.Size = UDim2.new(1, -32, 0, 22)
		feeLabel.TextXAlignment = Enum.TextXAlignment.Left
		feeLabel.TextColor3 = LobbyUiConfig.SUB_BODY_TEXT
		feeLabel.Text = if available
			then string.format("Entry fee: $%d", map.entryFee)
			else "Unavailable"
		styleLabel(feeLabel, 16, false)
		feeLabel.ZIndex = LobbyUiConfig.Z_SUB_PANEL + 4
		feeLabel.Parent = row

		if available then
			row.MouseButton1Click:Connect(function()
				if joiningMapId then
					return
				end
				local joinRemote = requestJoinMap
				if not joinRemote then
					setStatus("Connecting…", true)
					return
				end
				joiningMapId = map.id
				setStatus("Joining…", true)
				joinRemote:FireServer(map.id)
			end)
		end
	end
end

playButton.MouseButton1Click:Connect(function()
	closeSubPanel()
	openSubPanel("play", "Play")
end)

dailyButton.MouseButton1Click:Connect(function()
	closeSubPanel()
	openSubPanel("daily", "Daily Rewards")
end)

shopButton.MouseButton1Click:Connect(function()
	closeSubPanel()
	openSubPanel("shop", "Buy Coins")
end)

collectionButton.MouseButton1Click:Connect(function()
	closeSubPanel()
	FishCollectionInventory.openPanel()
end)

subClose.MouseButton1Click:Connect(closeSubPanel)

spinButton.MouseButton1Click:Connect(function()
	if spinBusy then
		return
	end
	local spinRemote = requestDailySpin
	if not spinRemote then
		setStatus("Connecting…", true)
		return
	end
	spinBusy = true
	spinButton.Text = "Spinning…"
	spinButton.Active = false
	startWheelSpin()
	spinRemote:FireServer()
end)

buyButton.MouseButton1Click:Connect(function()
	local purchaseRemote = requestCoinPurchase
	if not purchaseRemote then
		setStatus("Connecting…", true)
		return
	end
	purchaseRemote:FireServer()
	setStatus("Opening purchase…", true)
	task.delay(2, function()
		if activeSubPanel == "shop" then
			setStatus(nil, false)
		end
	end)
end)

local function onSpinResult(payload: unknown)
	spinBusy = false
	stopWheelSpin()
	spinButton.Text = "Spin"
	spinButton.Active = true

	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if data.ok == true and activeSubPanel == "daily" then
		local amount = data.amount
		if typeof(amount) == "number" then
			dailyDesc.Text = string.format("You won $%d! Come back tomorrow.", math.floor(amount))
		end
	end
end

local function onJoinResult(payload: unknown)
	joiningMapId = nil
	if typeof(payload) ~= "table" then
		setStatus(nil, false)
		return
	end
	local data = payload :: { [string]: unknown }
	if data.ok == true then
		setStatus(nil, false)
		return
	end
	setStatus(nil, false)
end

local function bindRemotes()
	local lobbyRemotes = ReplicatedStorage:WaitForChild(REMOTES_NAME, 60)
	if not lobbyRemotes or not lobbyRemotes:IsA("Folder") then
		warn("[LobbyHub] LobbyRemotes folder not found — hub buttons will not work.")
		return
	end

	local joinRemote = lobbyRemotes:WaitForChild(REQUEST_JOIN_MAP, 30)
	local purchaseRemote = lobbyRemotes:WaitForChild(REQUEST_COIN_PURCHASE, 30)
	local spinRemote = lobbyRemotes:WaitForChild(REQUEST_DAILY_SPIN, 30)
	local spinResultRemote = lobbyRemotes:WaitForChild(SPIN_RESULT_NAME, 30)
	local joinResultRemote = lobbyRemotes:FindFirstChild(JOIN_RESULT_NAME)

	if joinRemote and joinRemote:IsA("RemoteEvent") then
		requestJoinMap = joinRemote
	end
	if purchaseRemote and purchaseRemote:IsA("RemoteEvent") then
		requestCoinPurchase = purchaseRemote
	end
	if spinRemote and spinRemote:IsA("RemoteEvent") then
		requestDailySpin = spinRemote
	end
	if spinResultRemote and spinResultRemote:IsA("RemoteEvent") then
		spinResultRemote.OnClientEvent:Connect(onSpinResult)
	end
	if joinResultRemote and joinResultRemote:IsA("RemoteEvent") then
		joinResultRemote.OnClientEvent:Connect(onJoinResult)
	end

	if requestJoinMap and requestCoinPurchase and requestDailySpin then
		setStatus(nil, false)
	end
end

buildMapRows()

task.spawn(function()
	local ok, err = pcall(function()
		FishCollectionInventory.init()
		bindRemotes()
	end)
	if not ok then
		warn(string.format("[LobbyHub] init failed: %s", tostring(err)))
	end
end)
