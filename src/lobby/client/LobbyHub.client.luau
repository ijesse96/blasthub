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
local LobbyTouchInputSuppress = require(script.Parent:WaitForChild("LobbyTouchInputSuppress"))
local BattleMapUi = require(script.Parent:WaitForChild("BattleMapUi"))
local BattleQueue = require(script.Parent:WaitForChild("BattleQueue"))

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

type SubPanelId = "daily" | "shop" | nil

local activeSubPanel: SubPanelId = nil
local activeModeSelect = false
local activeMapSelect = false
local mapSelectMode: "join" | "collection" = "join"
local spinBusy = false
local joiningMapId: string? = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LobbyHub"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = LobbyUiConfig.DISPLAY_ORDER_HUB
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

LobbyTouchInputSuppress.setHolder("lobby-hub", true)

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
	image: string?,
}

local function makeHubMenuButton(options: HubMenuButtonOptions): TextButton
	local theme = options.theme
	local button = Instance.new("TextButton")
	button.Name = options.name
	button.Size = UDim2.fromOffset(options.width, options.height)
	button.Text = ""
	button.LayoutOrder = options.layoutOrder
	button.ZIndex = LobbyUiConfig.Z_BUTTONS
	button.Parent = options.parent

	local image = options.image
	if image and image ~= "" then
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false

		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.Size = UDim2.fromScale(1, 1)
		art.BackgroundTransparency = 1
		art.Image = image
		art.ScaleType = Enum.ScaleType.Fit
		art.ZIndex = LobbyUiConfig.Z_BUTTONS + 1
		art.Parent = button

		return button
	end

	button.BackgroundColor3 = theme.color
	button.BackgroundTransparency = 0
	button.AutoButtonColor = true
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
	parent = buttonLayer,
	titleSize = 26,
})
playButton.AnchorPoint = Vector2.new(0.5, 0.5)
playButton.Position = LobbyUiConfig.PLAY_BUTTON_POSITION

local dailyButtonSize = LobbyUiConfig.DAILY_BUTTON_SIZE
local dailyButton = makeHubMenuButton({
	name = "Daily",
	title = "Daily",
	theme = LobbyUiConfig.DAILY_BUTTON,
	width = dailyButtonSize,
	height = dailyButtonSize,
	layoutOrder = 2,
	parent = buttonLayer,
	titleSize = 14,
})
dailyButton.AnchorPoint = Vector2.new(1, 0)
dailyButton.Position = LobbyUiConfig.DAILY_BUTTON_POSITION

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
	title = "",
	theme = LobbyUiConfig.COLLECTION_BUTTON,
	image = LobbyUiConfig.COLLECTION_BUTTON_IMAGE,
	width = hubButtonWidth,
	height = LobbyUiConfig.PLAY_BUTTON_HEIGHT,
	layoutOrder = 4,
	parent = buttonLayer,
})
collectionButton.AnchorPoint = Vector2.new(0.5, 0.5)
collectionButton.Position = LobbyUiConfig.COLLECTION_BUTTON_POSITION

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

type ModePanelOptions = {
	name: string,
	label: string,
	image: string,
	placeholderColor: Color3,
	layoutOrder: number,
	parent: Instance,
	zIndex: number,
}

local function makeModePanel(options: ModePanelOptions): TextButton
	local tileZ = options.zIndex
	local tile = Instance.new("TextButton")
	tile.Name = options.name
	tile.Size = UDim2.fromOffset(100, 100)
	tile.BackgroundColor3 = Color3.fromRGB(22, 28, 38)
	tile.BackgroundTransparency = 0
	tile.Text = ""
	tile.AutoButtonColor = true
	tile.LayoutOrder = options.layoutOrder
	tile.ZIndex = tileZ
	tile.Parent = options.parent
	addCorner(tile, 12)
	addStroke(tile, LobbyUiConfig.MODE_PANEL_STROKE, 2, 0.2)

	local thumbHolder = Instance.new("Frame")
	thumbHolder.Name = "Thumb"
	thumbHolder.Position = UDim2.fromOffset(8, 8)
	thumbHolder.Size = UDim2.new(1, -16, 1, -52)
	thumbHolder.BackgroundTransparency = 1
	thumbHolder.ClipsDescendants = true
	thumbHolder.Active = false
	thumbHolder.ZIndex = tileZ + 1
	thumbHolder.Parent = tile
	addCorner(thumbHolder, 10)

	if options.image ~= "" then
		local thumb = Instance.new("ImageLabel")
		thumb.Name = "Image"
		thumb.Size = UDim2.fromScale(1, 1)
		thumb.BackgroundTransparency = 1
		thumb.Image = options.image
		thumb.ScaleType = Enum.ScaleType.Fit
		thumb.ZIndex = tileZ + 2
		thumb.Parent = thumbHolder
	else
		local placeholder = Instance.new("Frame")
		placeholder.Name = "Placeholder"
		placeholder.Size = UDim2.fromScale(1, 1)
		placeholder.BackgroundColor3 = options.placeholderColor
		placeholder.BorderSizePixel = 0
		placeholder.ZIndex = tileZ + 2
		placeholder.Parent = thumbHolder
		addCorner(placeholder, 10)
	end

	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 8, 1, -8)
	footer.Size = UDim2.new(1, -16, 0, 40)
	footer.BackgroundTransparency = 1
	footer.Active = false
	footer.ZIndex = tileZ + 1
	footer.Parent = tile

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = options.label
	label.Font = LobbyUiConfig.HUB_MENU_FONT
	label.TextSize = 28
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 1
	label.ZIndex = tileZ + 3
	label.Parent = footer

	return tile
end

-- Fullscreen mode selection (Play flow step 1).
local modeInset = LobbyUiConfig.MODE_SELECT_OVERLAY_INSET
local modeSelectOverlay = Instance.new("Frame")
modeSelectOverlay.Name = "ModeSelectOverlay"
modeSelectOverlay.Size = UDim2.fromScale(1, 1)
modeSelectOverlay.BackgroundTransparency = 1
modeSelectOverlay.Visible = false
modeSelectOverlay.ZIndex = LobbyUiConfig.Z_MODE_SELECT
modeSelectOverlay.Parent = screenGui

local modeSelectScrim = Instance.new("TextButton")
modeSelectScrim.Name = "Scrim"
modeSelectScrim.Size = UDim2.fromScale(1, 1)
modeSelectScrim.BackgroundColor3 = Color3.new(0, 0, 0)
modeSelectScrim.BackgroundTransparency = LobbyUiConfig.MAP_SELECT_SCRIM_TRANSPARENCY
modeSelectScrim.Text = ""
modeSelectScrim.AutoButtonColor = false
modeSelectScrim.ZIndex = LobbyUiConfig.Z_MODE_SELECT
modeSelectScrim.Parent = modeSelectOverlay

local modeSelectContent = Instance.new("Frame")
modeSelectContent.Name = "Content"
modeSelectContent.AnchorPoint = Vector2.new(0.5, 0.5)
modeSelectContent.Position = UDim2.fromScale(0.5, 0.5)
modeSelectContent.Size = UDim2.new(1, -modeInset * 2, 1, -modeInset * 2)
modeSelectContent.BackgroundColor3 = LobbyUiConfig.MAP_SELECT_CONTENT_COLOR
modeSelectContent.BackgroundTransparency = 0
modeSelectContent.ClipsDescendants = true
modeSelectContent.ZIndex = LobbyUiConfig.Z_MODE_SELECT + 1
modeSelectContent.Parent = modeSelectOverlay
addCorner(modeSelectContent, 14)
addStroke(modeSelectContent, LobbyUiConfig.SUB_PANEL_STROKE, 2, 0.2)

local modeSelectHeader = Instance.new("Frame")
modeSelectHeader.Name = "Header"
modeSelectHeader.Size = UDim2.new(1, 0, 0, 56)
modeSelectHeader.BackgroundColor3 = LobbyUiConfig.MAP_SELECT_HEADER_COLOR
modeSelectHeader.BorderSizePixel = 0
modeSelectHeader.ZIndex = LobbyUiConfig.Z_MODE_SELECT + 2
modeSelectHeader.Parent = modeSelectContent

local modeSelectHeaderCorner = Instance.new("UICorner")
modeSelectHeaderCorner.CornerRadius = UDim.new(0, 14)
modeSelectHeaderCorner.Parent = modeSelectHeader

local modeSelectTitle = Instance.new("TextLabel")
modeSelectTitle.Name = "Title"
modeSelectTitle.Position = UDim2.fromOffset(20, 10)
modeSelectTitle.Size = UDim2.new(1, -72, 1, -12)
modeSelectTitle.TextXAlignment = Enum.TextXAlignment.Left
modeSelectTitle.TextColor3 = LobbyUiConfig.SUB_TITLE_TEXT
modeSelectTitle.Text = LobbyUiConfig.MODE_SELECT_TITLE
styleLabel(modeSelectTitle, 26, true)
modeSelectTitle.Parent = modeSelectHeader

local modeSelectClose = Instance.new("TextButton")
modeSelectClose.Name = "Close"
modeSelectClose.AnchorPoint = Vector2.new(1, 0.5)
modeSelectClose.Position = UDim2.new(1, -14, 0.5, 0)
modeSelectClose.Size = UDim2.fromOffset(40, 40)
modeSelectClose.BackgroundColor3 = Color3.fromRGB(80, 95, 115)
modeSelectClose.Font = Enum.Font.GothamBold
modeSelectClose.TextSize = 22
modeSelectClose.TextColor3 = Color3.fromRGB(255, 255, 255)
modeSelectClose.Text = "X"
modeSelectClose.ZIndex = LobbyUiConfig.Z_MODE_SELECT + 4
modeSelectClose.AutoButtonColor = true
modeSelectClose.Parent = modeSelectHeader
addCorner(modeSelectClose, 8)

local modePanelBody = Instance.new("Frame")
modePanelBody.Name = "ModePanels"
modePanelBody.Position = UDim2.fromOffset(24, 72)
modePanelBody.Size = UDim2.new(1, -48, 1, -96)
modePanelBody.BackgroundTransparency = 1
modePanelBody.ZIndex = LobbyUiConfig.Z_MODE_SELECT + 2
modePanelBody.Parent = modeSelectContent

local modePanelZ = LobbyUiConfig.Z_MODE_SELECT + 4
local collectModePanel = makeModePanel({
	name = "Collect",
	label = LobbyUiConfig.MODE_PANEL_COLLECT_LABEL,
	image = LobbyUiConfig.MODE_PANEL_COLLECT_IMAGE,
	placeholderColor = LobbyUiConfig.MODE_PANEL_COLLECT_PLACEHOLDER_COLOR,
	layoutOrder = 1,
	parent = modePanelBody,
	zIndex = modePanelZ,
})

local battleModePanel = makeModePanel({
	name = "Battle",
	label = LobbyUiConfig.MODE_PANEL_BATTLE_LABEL,
	image = LobbyUiConfig.MODE_PANEL_BATTLE_IMAGE,
	placeholderColor = LobbyUiConfig.MODE_PANEL_BATTLE_PLACEHOLDER_COLOR,
	layoutOrder = 2,
	parent = modePanelBody,
	zIndex = modePanelZ,
})
battleModePanel.AutoButtonColor = true
battleModePanel.Active = LobbyUiConfig.SHOW_BATTLE_MODE

local function isCompactModeSelect(): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local viewport = camera.ViewportSize
	return viewport.X < 700 or viewport.Y < 500
end

local function layoutModeSelectPanels()
	local compact = isCompactModeSelect()
	local overlayInset = if compact
		then LobbyUiConfig.MODE_SELECT_OVERLAY_INSET_MOBILE
		else LobbyUiConfig.MODE_SELECT_OVERLAY_INSET
	modeSelectContent.Size = UDim2.new(1, -overlayInset * 2, 1, -overlayInset * 2)

	local bodyPadX = if compact then 12 else 24
	local bodyPadTop = if compact then 60 else 72
	local bodyPadBottom = if compact then 72 else 96
	modePanelBody.Position = UDim2.fromOffset(bodyPadX, bodyPadTop)
	modePanelBody.Size = UDim2.new(1, -bodyPadX * 2, 1, -(bodyPadTop + bodyPadBottom))

	local bodySize = modePanelBody.AbsoluteSize
	if bodySize.X < 2 or bodySize.Y < 2 then
		return
	end

	local gap = if compact then 12 else LobbyUiConfig.MODE_PANEL_GAP
	local maxHeight = LobbyUiConfig.MODE_PANEL_HEIGHT
	local panelHeight = math.clamp(math.min(maxHeight, bodySize.Y), LobbyUiConfig.MODE_PANEL_MIN_HEIGHT, maxHeight)
	local panelWidth = math.max(80, math.floor((bodySize.X - gap) / 2))

	local totalWidth = panelWidth * 2 + gap
	local originX = math.floor((bodySize.X - totalWidth) / 2)
	local originY = math.floor((bodySize.Y - panelHeight) / 2)

	collectModePanel.Size = UDim2.fromOffset(panelWidth, panelHeight)
	collectModePanel.Position = UDim2.fromOffset(originX, originY)
	battleModePanel.Size = UDim2.fromOffset(panelWidth, panelHeight)
	battleModePanel.Position = UDim2.fromOffset(originX + panelWidth + gap, originY)

	local labelSize = if compact then 18 elseif panelHeight < 200 then 22 else 28
	for _, panel in { collectModePanel, battleModePanel } do
		local footer = panel:FindFirstChild("Footer")
		if footer then
			local title = footer:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.TextSize = labelSize
			end
		end
	end
end

modePanelBody:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutModeSelectPanels)

-- Fullscreen map selection (Play flow step 2).
local inset = LobbyUiConfig.MAP_SELECT_OVERLAY_INSET
local mapSelectOverlay = Instance.new("Frame")
mapSelectOverlay.Name = "MapSelectOverlay"
mapSelectOverlay.Size = UDim2.fromScale(1, 1)
mapSelectOverlay.BackgroundTransparency = 1
mapSelectOverlay.Visible = false
mapSelectOverlay.ZIndex = LobbyUiConfig.Z_MAP_SELECT
mapSelectOverlay.Parent = screenGui

local mapSelectScrim = Instance.new("TextButton")
mapSelectScrim.Name = "Scrim"
mapSelectScrim.Size = UDim2.fromScale(1, 1)
mapSelectScrim.BackgroundColor3 = Color3.new(0, 0, 0)
mapSelectScrim.BackgroundTransparency = LobbyUiConfig.MAP_SELECT_SCRIM_TRANSPARENCY
mapSelectScrim.Text = ""
mapSelectScrim.AutoButtonColor = false
mapSelectScrim.ZIndex = LobbyUiConfig.Z_MAP_SELECT
mapSelectScrim.Parent = mapSelectOverlay

local mapSelectContent = Instance.new("Frame")
mapSelectContent.Name = "Content"
mapSelectContent.AnchorPoint = Vector2.new(0.5, 0.5)
mapSelectContent.Position = UDim2.fromScale(0.5, 0.5)
mapSelectContent.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
mapSelectContent.BackgroundColor3 = LobbyUiConfig.MAP_SELECT_CONTENT_COLOR
mapSelectContent.BackgroundTransparency = 0
mapSelectContent.ZIndex = LobbyUiConfig.Z_MAP_SELECT + 1
mapSelectContent.Parent = mapSelectOverlay
addCorner(mapSelectContent, 14)
addStroke(mapSelectContent, LobbyUiConfig.SUB_PANEL_STROKE, 2, 0.2)

local mapSelectHeader = Instance.new("Frame")
mapSelectHeader.Name = "Header"
mapSelectHeader.Size = UDim2.new(1, 0, 0, 56)
mapSelectHeader.BackgroundColor3 = LobbyUiConfig.MAP_SELECT_HEADER_COLOR
mapSelectHeader.BorderSizePixel = 0
mapSelectHeader.ZIndex = LobbyUiConfig.Z_MAP_SELECT + 2
mapSelectHeader.Parent = mapSelectContent

local mapSelectHeaderCorner = Instance.new("UICorner")
mapSelectHeaderCorner.CornerRadius = UDim.new(0, 14)
mapSelectHeaderCorner.Parent = mapSelectHeader

local mapSelectTitle = Instance.new("TextLabel")
mapSelectTitle.Name = "Title"
mapSelectTitle.Position = UDim2.fromOffset(20, 10)
mapSelectTitle.Size = UDim2.new(1, -72, 1, -12)
mapSelectTitle.TextXAlignment = Enum.TextXAlignment.Left
mapSelectTitle.TextColor3 = LobbyUiConfig.SUB_TITLE_TEXT
mapSelectTitle.Text = LobbyUiConfig.MAP_SELECT_TITLE
styleLabel(mapSelectTitle, 26, true)
mapSelectTitle.Parent = mapSelectHeader

local mapSelectClose = Instance.new("TextButton")
mapSelectClose.Name = "Close"
mapSelectClose.AnchorPoint = Vector2.new(1, 0.5)
mapSelectClose.Position = UDim2.new(1, -14, 0.5, 0)
mapSelectClose.Size = UDim2.fromOffset(40, 40)
mapSelectClose.BackgroundColor3 = Color3.fromRGB(80, 95, 115)
mapSelectClose.Font = Enum.Font.GothamBold
mapSelectClose.TextSize = 22
mapSelectClose.TextColor3 = Color3.fromRGB(255, 255, 255)
mapSelectClose.Text = "X"
mapSelectClose.ZIndex = LobbyUiConfig.Z_MAP_SELECT + 4
mapSelectClose.AutoButtonColor = true
mapSelectClose.Parent = mapSelectHeader
addCorner(mapSelectClose, 8)

local mapScroll = Instance.new("ScrollingFrame")
mapScroll.Name = "MapScroll"
mapScroll.Position = UDim2.fromOffset(16, 64)
mapScroll.Size = UDim2.new(1, -32, 1, -80)
mapScroll.BackgroundTransparency = 1
mapScroll.BorderSizePixel = 0
mapScroll.ScrollBarThickness = 8
mapScroll.CanvasSize = UDim2.new()
mapScroll.ZIndex = LobbyUiConfig.Z_MAP_SELECT + 2
mapScroll.Parent = mapSelectContent

local mapGrid = Instance.new("Frame")
mapGrid.Name = "MapGrid"
mapGrid.Size = UDim2.new(1, 0, 0, 0)
mapGrid.AutomaticSize = Enum.AutomaticSize.Y
mapGrid.BackgroundTransparency = 1
mapGrid.ZIndex = LobbyUiConfig.Z_MAP_SELECT + 3
mapGrid.Parent = mapScroll

local mapGridLayout = Instance.new("UIGridLayout")
mapGridLayout.CellSize = UDim2.fromOffset(LobbyUiConfig.MAP_TILE_WIDTH, LobbyUiConfig.MAP_TILE_HEIGHT)
mapGridLayout.CellPadding = UDim2.fromOffset(LobbyUiConfig.MAP_TILE_PADDING, LobbyUiConfig.MAP_TILE_PADDING)
mapGridLayout.FillDirectionMaxCells = LobbyUiConfig.MAP_SELECT_COLUMNS
mapGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
mapGridLayout.Parent = mapGrid

local wheelSpinTween: Tween? = nil

local function setStatus(text: string?, visible: boolean?)
	if text and text ~= "" then
		statusLabel.Text = text
		statusLabel.Visible = visible ~= false
	else
		statusLabel.Visible = false
	end
end

local function syncHubDisplayOrder()
	local overlayOpen = activeModeSelect or activeMapSelect or activeSubPanel ~= nil
	screenGui.DisplayOrder = if overlayOpen
		then LobbyUiConfig.DISPLAY_ORDER_HUB_OVERLAY
		else LobbyUiConfig.DISPLAY_ORDER_HUB
end

local function hideAllSubHosts()
	dailyHost.Visible = false
	shopHost.Visible = false
end

local function closeMapSelect()
	activeMapSelect = false
	mapSelectOverlay.Visible = false
	syncHubDisplayOrder()
end

local function closeModeSelect()
	activeModeSelect = false
	modeSelectOverlay.Visible = false
	syncHubDisplayOrder()
end

local function closeSubPanel()
	activeSubPanel = nil
	subBackdrop.Visible = false
	subPanel.Visible = false
	hideAllSubHosts()
	closeModeSelect()
	closeMapSelect()
	setStatus(nil, false)
	syncHubDisplayOrder()
end

local function openSubPanel(panelId: SubPanelId, title: string)
	closeModeSelect()
	closeMapSelect()
	activeSubPanel = panelId
	subTitle.Text = title
	hideAllSubHosts()
	subBackdrop.Visible = true
	subPanel.Visible = true

	if panelId == "daily" then
		dailyHost.Visible = true
	elseif panelId == "shop" then
		shopHost.Visible = true
	end
	syncHubDisplayOrder()
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

local function mapNameAbbrev(displayName: string): string
	local words = string.split(displayName, " ")
	if #words >= 2 then
		local abbrev = ""
		for _, word in words do
			if word ~= "" then
				abbrev ..= string.sub(word, 1, 1)
			end
		end
		if #abbrev >= 2 then
			return string.upper(abbrev)
		end
	end
	return string.upper(string.sub(displayName, 1, 2))
end

local function hasMapThumbnail(map: MatchMaps.MatchMap): boolean
	local image = map.thumbnailImage
	return typeof(image) == "string" and image ~= ""
end

local function updateMapScrollCanvas(mapCount: number)
	local columns = LobbyUiConfig.MAP_SELECT_COLUMNS
	local pad = LobbyUiConfig.MAP_TILE_PADDING
	local tileH = LobbyUiConfig.MAP_TILE_HEIGHT
	local rowCount = math.max(1, math.ceil(math.max(mapCount, 1) / columns))
	local gridHeight = rowCount * (tileH + pad) + pad
	mapGrid.Size = UDim2.new(1, 0, 0, gridHeight)
	mapScroll.CanvasSize = UDim2.new(0, 0, 0, gridHeight)
end

local function getMapsForSelect(): { MatchMaps.MatchMap }
	if mapSelectMode == "collection" then
		local collectedIds = FishCollectionInventory.getCollectedMapIds()
		local idSet: { [string]: boolean } = {}
		for _, map in MatchMaps.getCollectionEnabledMaps() do
			idSet[map.id] = true
		end
		for _, id in collectedIds do
			idSet[id] = true
		end
		local filtered: { MatchMaps.MatchMap } = {}
		for _, map in MatchMaps.getAll() do
			if idSet[map.id] then
				table.insert(filtered, map)
			end
		end
		return filtered
	end
	return MatchMaps.getAll()
end

local function buildMapTiles()
	for _, child in mapGrid:GetChildren() do
		if child:IsA("GuiObject") and child ~= mapGridLayout then
			child:Destroy()
		end
	end

	local maps = getMapsForSelect()
	local tileZ = LobbyUiConfig.Z_MAP_SELECT + 4

	if mapSelectMode == "collection" and #maps == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "EmptyState"
		emptyLabel.Size = UDim2.new(1, 0, 0, 80)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Font = Enum.Font.GothamMedium
		emptyLabel.TextSize = 20
		emptyLabel.TextColor3 = LobbyUiConfig.SUB_BODY_TEXT
		emptyLabel.Text = LobbyUiConfig.COLLECTION_MAP_SELECT_EMPTY
		emptyLabel.TextWrapped = true
		emptyLabel.ZIndex = tileZ
		emptyLabel.Parent = mapGrid
		updateMapScrollCanvas(0)
		return
	end

	for i, map in maps do
		local available = if mapSelectMode == "collection" then true else map.placeId ~= 0
		local tile = Instance.new("TextButton")
		tile.Name = "Map_" .. map.id
		tile.BackgroundColor3 = if available then Color3.fromRGB(22, 28, 38) else Color3.fromRGB(26, 30, 38)
		tile.BackgroundTransparency = 0
		tile.Text = ""
		tile.Font = Enum.Font.GothamBold
		tile.TextSize = 0
		tile.AutoButtonColor = available
		tile.Active = available
		tile.LayoutOrder = i
		tile.ZIndex = tileZ
		tile.Parent = mapGrid
		addCorner(tile, 10)
		addStroke(tile, LobbyUiConfig.MAP_TILE_STROKE, 2, if available then 0.2 else 0.55)

		local thumbHolder = Instance.new("Frame")
		thumbHolder.Name = "Thumb"
		thumbHolder.Position = UDim2.fromOffset(6, 6)
		thumbHolder.Size = UDim2.new(1, -12, 1, -46)
		thumbHolder.BackgroundTransparency = 1
		thumbHolder.ClipsDescendants = true
		thumbHolder.Active = false
		thumbHolder.ZIndex = tileZ + 1
		thumbHolder.Parent = tile
		addCorner(thumbHolder, 8)

		if hasMapThumbnail(map) then
			local thumb = Instance.new("ImageLabel")
			thumb.Name = "Image"
			thumb.Size = UDim2.fromScale(1, 1)
			thumb.BackgroundTransparency = 1
			thumb.Image = map.thumbnailImage :: string
			thumb.ScaleType = Enum.ScaleType.Crop
			thumb.ZIndex = tileZ + 2
			thumb.Parent = thumbHolder
		else
			local placeholder = Instance.new("Frame")
			placeholder.Name = "Placeholder"
			placeholder.Size = UDim2.fromScale(1, 1)
			placeholder.BackgroundColor3 = LobbyUiConfig.MAP_PLACEHOLDER_COLOR
			placeholder.BorderSizePixel = 0
			placeholder.ZIndex = tileZ + 2
			placeholder.Parent = thumbHolder
			addCorner(placeholder, 8)

			local abbrevLabel = Instance.new("TextLabel")
			abbrevLabel.Size = UDim2.fromScale(1, 1)
			abbrevLabel.BackgroundTransparency = 1
			abbrevLabel.Font = Enum.Font.GothamBold
			abbrevLabel.TextSize = 32
			abbrevLabel.TextColor3 = Color3.fromRGB(120, 140, 165)
			abbrevLabel.Text = mapNameAbbrev(map.displayName)
			abbrevLabel.ZIndex = tileZ + 3
			abbrevLabel.Parent = placeholder
		end

		local footer = Instance.new("Frame")
		footer.Name = "Footer"
		footer.AnchorPoint = Vector2.new(0, 1)
		footer.Position = UDim2.new(0, 6, 1, -6)
		footer.Size = UDim2.new(1, -12, 0, 36)
		footer.BackgroundTransparency = 1
		footer.Active = false
		footer.ZIndex = tileZ + 1
		footer.Parent = tile

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Title"
		nameLabel.Size = UDim2.new(1, 0, 0, 18)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.Text = map.displayName
		nameLabel.Font = LobbyUiConfig.HUB_MENU_FONT
		nameLabel.TextSize = 15
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.ZIndex = tileZ + 3
		nameLabel.Parent = footer

		local feeRow = Instance.new("Frame")
		feeRow.Name = "Fee"
		feeRow.Position = UDim2.fromOffset(0, 18)
		feeRow.Size = UDim2.new(1, 0, 0, 16)
		feeRow.BackgroundTransparency = 1
		feeRow.ZIndex = tileZ + 3
		feeRow.Parent = footer

		local function styleFeeText(label: TextLabel)
			label.Font = Enum.Font.GothamMedium
			label.TextSize = 13
			label.TextStrokeTransparency = 0.6
			label.TextStrokeColor3 = Color3.new(0, 0, 0)
			label.BackgroundTransparency = 1
			label.ZIndex = tileZ + 3
		end

		if mapSelectMode == "collection" then
			local ownedUnique, total = FishCollectionInventory.getMapProgress(map.id)
			local feeLabel = Instance.new("TextLabel")
			feeLabel.Size = UDim2.fromScale(1, 1)
			feeLabel.TextXAlignment = Enum.TextXAlignment.Center
			feeLabel.Text = string.format("%d / %d", ownedUnique, total)
			feeLabel.TextColor3 = RewardUiColors.PROFIT_GREEN
			styleFeeText(feeLabel)
			feeLabel.Parent = feeRow
		else
			local feeLayout = Instance.new("UIListLayout")
			feeLayout.FillDirection = Enum.FillDirection.Horizontal
			feeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			feeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			feeLayout.SortOrder = Enum.SortOrder.LayoutOrder
			feeLayout.Padding = UDim.new(0, 2)
			feeLayout.Parent = feeRow

			local entryPrefix = Instance.new("TextLabel")
			entryPrefix.Name = "EntryPrefix"
			entryPrefix.AutomaticSize = Enum.AutomaticSize.XY
			entryPrefix.TextColor3 = LobbyUiConfig.SUB_BODY_TEXT
			entryPrefix.Text = "Entry:"
			entryPrefix.LayoutOrder = 1
			styleFeeText(entryPrefix)
			entryPrefix.Parent = feeRow

			local coinIcon = Instance.new("ImageLabel")
			coinIcon.Name = "CoinIcon"
			coinIcon.Size = UDim2.fromOffset(14, 14)
			coinIcon.BackgroundTransparency = 1
			coinIcon.Image = LobbyUiConfig.CASH_BAR_COIN_IMAGE
			coinIcon.ScaleType = Enum.ScaleType.Fit
			coinIcon.LayoutOrder = 2
			coinIcon.ZIndex = tileZ + 3
			coinIcon.Parent = feeRow

			local amountLabel = Instance.new("TextLabel")
			amountLabel.Name = "Amount"
			amountLabel.AutomaticSize = Enum.AutomaticSize.XY
			amountLabel.TextColor3 = LobbyUiConfig.SUB_BODY_TEXT
			amountLabel.Text = tostring(map.entryFee)
			amountLabel.LayoutOrder = 3
			styleFeeText(amountLabel)
			amountLabel.Parent = feeRow
		end

		if mapSelectMode == "collection" then
			tile.MouseButton1Click:Connect(function()
				closeMapSelect()
				FishCollectionInventory.openPanelForMap(map.id)
			end)
		elseif available then
			tile.MouseButton1Click:Connect(function()
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

	updateMapScrollCanvas(#maps)
end

local function openMapSelect()
	activeSubPanel = nil
	subBackdrop.Visible = false
	subPanel.Visible = false
	hideAllSubHosts()
	setStatus(nil, false)
	buildMapTiles()
	activeMapSelect = true
	mapSelectOverlay.Visible = true
	syncHubDisplayOrder()
end

local function openJoinMapSelect()
	mapSelectMode = "join"
	mapSelectTitle.Text = LobbyUiConfig.MAP_SELECT_TITLE
	openMapSelect()
end

local function openCollectionMapSelect()
	mapSelectMode = "collection"
	mapSelectTitle.Text = LobbyUiConfig.COLLECTION_SELECT_TITLE
	openMapSelect()
end

local function openModeSelect()
	activeSubPanel = nil
	subBackdrop.Visible = false
	subPanel.Visible = false
	hideAllSubHosts()
	closeMapSelect()
	setStatus(nil, false)
	activeModeSelect = true
	modeSelectOverlay.Visible = true
	syncHubDisplayOrder()
	task.defer(layoutModeSelectPanels)
end

playButton.MouseButton1Click:Connect(function()
	openModeSelect()
end)

collectModePanel.MouseButton1Click:Connect(function()
	closeModeSelect()
	openJoinMapSelect()
end)

battleModePanel.MouseButton1Click:Connect(function()
	closeModeSelect()
	BattleQueue.open()
end)

modeSelectClose.MouseButton1Click:Connect(closeModeSelect)
modeSelectScrim.MouseButton1Click:Connect(closeModeSelect)

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
	openCollectionMapSelect()
end)

subClose.MouseButton1Click:Connect(closeSubPanel)
mapSelectClose.MouseButton1Click:Connect(closeSubPanel)
mapSelectScrim.MouseButton1Click:Connect(closeSubPanel)

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

buildMapTiles()

task.spawn(function()
	local ok, err = pcall(function()
		FishCollectionInventory.init()
		FishCollectionInventory.setOnCloseToMapPicker(openCollectionMapSelect)
		BattleMapUi.init()
		BattleQueue.init()
		bindRemotes()
	end)
	if not ok then
		warn(string.format("[LobbyHub] init failed: %s", tostring(err)))
	end
end)
