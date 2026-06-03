--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local BattleMapDemoData = require(shared:WaitForChild("BattleMapDemoData"))
local LobbyUiConfig = require(shared:WaitForChild("LobbyUiConfig"))

local LobbyModalInputBlock = require(script.Parent:WaitForChild("LobbyModalInputBlock"))
local LobbyTouchInputSuppress = require(script.Parent:WaitForChild("LobbyTouchInputSuppress"))

type CastleEntry = BattleMapDemoData.CastleEntry

local REMOTES_NAME = "LobbyRemotes"
local REMOTE_ATTACK_CASTLE = "AttackCastle"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local M = {}

local screenGui: ScreenGui? = nil
local mapScroll: ScrollingFrame? = nil
local mapCanvas: Frame? = nil
local mapScale: UIScale? = nil
local sidePanel: Frame? = nil
local searchBox: TextBox? = nil
local statusLabel: TextLabel? = nil
local detailLabels: { [string]: TextLabel } = {}
local attackButton: TextButton? = nil

local castles: { CastleEntry } = {}
local castleMarkers: { [string]: TextButton } = {}
local gridCells: { [string]: Frame } = {}
local selectedCastleId: string? = nil
local zoomLevel = LobbyUiConfig.BATTLE_MAP_DEFAULT_ZOOM
local isOpen = false
local onCloseCallback: (() -> ())? = nil

local canvasSize = LobbyUiConfig.BATTLE_MAP_CANVAS_SIZE

local function gridCellKey(col: number, row: number): string
	return tostring(col) .. "_" .. tostring(row)
end

local function getGridMetrics(): (number, number, number, number)
	local cols = LobbyUiConfig.BATTLE_MAP_GRID_COLS
	local rows = LobbyUiConfig.BATTLE_MAP_GRID_ROWS
	local cellW = canvasSize.X / cols
	local cellH = canvasSize.Y / rows
	return cols, rows, cellW, cellH
end

local function getCastleCenterOffset(castle: CastleEntry): (number, number)
	local _, _, cellW, cellH = getGridMetrics()
	local cx = (castle.gridCol + 0.5) * cellW
	local cy = (castle.gridRow + 0.5) * cellH
	return cx, cy
end

local function buildMapGrid(parent: Frame)
	table.clear(gridCells)
	local cols, rows, cellW, cellH = getGridMetrics()

	local gridLayer = Instance.new("Frame")
	gridLayer.Name = "MapGrid"
	gridLayer.Size = UDim2.fromScale(1, 1)
	gridLayer.BackgroundTransparency = 1
	gridLayer.BorderSizePixel = 0
	gridLayer.ZIndex = parent.ZIndex + 1
	gridLayer.Parent = parent

	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local cell = Instance.new("Frame")
			cell.Name = "Cell_" .. gridCellKey(col, row)
			cell.Size = UDim2.fromOffset(cellW, cellH)
			cell.Position = UDim2.fromOffset(col * cellW, row * cellH)
			cell.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_GRID_CELL_FILL
			cell.BackgroundTransparency = LobbyUiConfig.BATTLE_MAP_GRID_CELL_FILL_TRANSPARENCY
			cell.BorderSizePixel = 0
			cell.ClipsDescendants = false
			cell.ZIndex = gridLayer.ZIndex
			cell.Parent = gridLayer

			local stroke = Instance.new("UIStroke")
			stroke.Color = LobbyUiConfig.BATTLE_MAP_GRID_STROKE
			stroke.Transparency = LobbyUiConfig.BATTLE_MAP_GRID_STROKE_TRANSPARENCY
			stroke.Thickness = 1
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = cell

			gridCells[gridCellKey(col, row)] = cell
		end
	end
end

local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(REMOTES_NAME):WaitForChild(name) :: RemoteEvent
end

local function requestAttackCastle(castleId: string)
	getRemote(REMOTE_ATTACK_CASTLE):FireServer({ castleId = castleId })
end

local function bindPressOnce(gui: GuiButton, onPress: () -> ())
	gui.Active = true
	gui.Selectable = true
	local busy = false
	gui.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		onPress()
		task.defer(function()
			busy = false
		end)
	end)
end

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function cloneCastlesForLocalPlayer(): { CastleEntry }
	local displayName = player.DisplayName
	local out: { CastleEntry } = {}
	for _, castle in BattleMapDemoData.getCastles() do
		local entry = {
			id = castle.id,
			playerName = if castle.isLocalPlayer then displayName else castle.playerName,
			castleLevel = castle.castleLevel,
			power = castle.power,
			region = castle.region,
			gridCol = castle.gridCol,
			gridRow = castle.gridRow,
			isLocalPlayer = castle.isLocalPlayer,
		}
		table.insert(out, entry)
	end
	return out
end

local function getCastleById(id: string): CastleEntry?
	for _, castle in castles do
		if castle.id == id then
			return castle
		end
	end
	return nil
end

local function getLocalCastle(): CastleEntry?
	for _, castle in castles do
		if castle.isLocalPlayer then
			return castle
		end
	end
	return nil
end

local function findCastleBySearch(query: string): CastleEntry?
	local trimmed = string.lower(string.gsub(query, "^%s*(.-)%s*$", "%1"))
	if trimmed == "" then
		return nil
	end
	for _, castle in castles do
		local nameLower = string.lower(castle.playerName)
		if nameLower == trimmed or string.find(nameLower, trimmed, 1, true) then
			return castle
		end
	end
	return nil
end

local function setStatus(message: string?)
	if not statusLabel then
		return
	end
	if message and message ~= "" then
		statusLabel.Text = message
		statusLabel.Visible = true
	else
		statusLabel.Text = ""
		statusLabel.Visible = false
	end
end

local function updateCanvasSize()
	if not mapScroll or not mapScale then
		return
	end
	mapScale.Scale = zoomLevel
	mapScroll.CanvasSize = UDim2.fromOffset(canvasSize.X * zoomLevel, canvasSize.Y * zoomLevel)
end

local function centerOnCastle(castle: CastleEntry)
	if not mapScroll then
		return
	end
	updateCanvasSize()
	local cx, cy = getCastleCenterOffset(castle)
	cx *= zoomLevel
	cy *= zoomLevel
	local viewport = mapScroll.AbsoluteSize
	local canvasW = canvasSize.X * zoomLevel
	local canvasH = canvasSize.Y * zoomLevel
	local maxX = math.max(0, canvasW - viewport.X)
	local maxY = math.max(0, canvasH - viewport.Y)
	mapScroll.CanvasPosition = Vector2.new(
		math.clamp(cx - viewport.X / 2, 0, maxX),
		math.clamp(cy - viewport.Y / 2, 0, maxY)
	)
end

local function updateMarkerHighlight()
	for id, marker in castleMarkers do
		local castle = getCastleById(id)
		if not castle then
			continue
		end
		local isSelected = id == selectedCastleId
		local icon = marker:FindFirstChild("CastleIcon")
		if icon and icon:IsA("ImageLabel") then
			icon.ImageColor3 = if isSelected then Color3.fromRGB(255, 230, 160) else Color3.new(1, 1, 1)
		end
	end
end

local function populateSidePanel(castle: CastleEntry)
	if not sidePanel then
		return
	end
	selectedCastleId = castle.id
	updateMarkerHighlight()

	if detailLabels.owner then
		detailLabels.owner.Text = castle.playerName
	end
	if detailLabels.power then
		detailLabels.power.Text = tostring(castle.power)
	end
	if detailLabels.level then
		detailLabels.level.Text = tostring(castle.castleLevel)
	end
	if detailLabels.region then
		detailLabels.region.Text = castle.region
	end

	if attackButton then
		attackButton.Visible = castle.isLocalPlayer ~= true
	end

	sidePanel.Visible = true
	setStatus(nil)
end

local function closeSidePanel()
	selectedCastleId = nil
	updateMarkerHighlight()
	if sidePanel then
		sidePanel.Visible = false
	end
end

local function selectCastle(castle: CastleEntry)
	populateSidePanel(castle)
end

local function makeDetailRow(parent: Instance, labelText: string, y: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = labelText
	label.Position = UDim2.fromOffset(16, y)
	label.Size = UDim2.new(1, -32, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = LobbyUiConfig.BATTLE_MAP_MUTED_TEXT
	label.Text = labelText
	label.ZIndex = LobbyUiConfig.Z_BATTLE_MAP_SIDE_PANEL + 1
	label.Parent = parent

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.fromOffset(16, y + 20)
	value.Size = UDim2.new(1, -32, 0, 28)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.TextSize = 18
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextColor3 = LobbyUiConfig.BATTLE_MAP_BODY_TEXT
	value.Text = "—"
	value.ZIndex = LobbyUiConfig.Z_BATTLE_MAP_SIDE_PANEL + 1
	value.Parent = parent

	return value
end

local function makeCastleMarker(castle: CastleEntry): TextButton
	local marker = Instance.new("TextButton")
	marker.Name = "Castle_" .. castle.id
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(180, 220)
	marker.BackgroundTransparency = 1
	marker.BorderSizePixel = 0
	marker.Text = ""
	marker.AutoButtonColor = false
	marker.ZIndex = LobbyUiConfig.Z_BATTLE_MAP_SCROLL + 2

	local iconSize = LobbyUiConfig.BATTLE_MAP_CASTLE_ICON_SIZE

	local icon = Instance.new("ImageLabel")
	icon.Name = "CastleIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0)
	icon.Size = UDim2.fromOffset(iconSize, iconSize)
	icon.BackgroundTransparency = 1
	icon.Image = LobbyUiConfig.BATTLE_MAP_CASTLE_IMAGE
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = marker.ZIndex
	icon.Parent = marker

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Position = UDim2.fromOffset(0, iconSize + 4)
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Text = castle.playerName
	nameLabel.ZIndex = marker.ZIndex + 1
	nameLabel.Parent = marker

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "Stats"
	statsLabel.Position = UDim2.fromOffset(0, iconSize + 22)
	statsLabel.Size = UDim2.new(1, 0, 0, 16)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.GothamMedium
	statsLabel.TextSize = 11
	statsLabel.TextColor3 = Color3.fromRGB(230, 236, 245)
	statsLabel.TextStrokeTransparency = 0.6
	statsLabel.Text = string.format("Lv %d  |  Power %d", castle.castleLevel, castle.power)
	statsLabel.ZIndex = marker.ZIndex + 1
	statsLabel.Parent = marker

	local regionLabel = Instance.new("TextLabel")
	regionLabel.Name = "Region"
	regionLabel.Position = UDim2.fromOffset(0, iconSize + 38)
	regionLabel.Size = UDim2.new(1, 0, 0, 14)
	regionLabel.BackgroundTransparency = 1
	regionLabel.Font = Enum.Font.Gotham
	regionLabel.TextSize = 10
	regionLabel.TextColor3 = Color3.fromRGB(200, 210, 220)
	regionLabel.TextStrokeTransparency = 0.65
	regionLabel.Text = castle.region
	regionLabel.ZIndex = marker.ZIndex + 1
	regionLabel.Parent = marker

	bindPressOnce(marker, function()
		selectCastle(castle)
	end)

	return marker
end

local function rebuildCastleMarkers()
	for _, marker in castleMarkers do
		marker:Destroy()
	end
	table.clear(castleMarkers)
	for _, castle in castles do
		local cell = gridCells[gridCellKey(castle.gridCol, castle.gridRow)]
		if not cell then
			continue
		end
		local marker = makeCastleMarker(castle)
		marker.ZIndex = cell.ZIndex + 1
		marker.Parent = cell
		castleMarkers[castle.id] = marker
	end
	updateMarkerHighlight()
end

local function applyZoom(delta: number)
	zoomLevel = math.clamp(
		zoomLevel + delta,
		LobbyUiConfig.BATTLE_MAP_ZOOM_MIN,
		LobbyUiConfig.BATTLE_MAP_ZOOM_MAX
	)
	local selected = if selectedCastleId then getCastleById(selectedCastleId) else nil
	updateCanvasSize()
	if selected then
		centerOnCastle(selected)
	end
end

local function runSearch()
	if not searchBox then
		return
	end
	local found = findCastleBySearch(searchBox.Text)
	if found then
		centerOnCastle(found)
		selectCastle(found)
	else
		setStatus(LobbyUiConfig.BATTLE_MAP_SEARCH_NOT_FOUND)
	end
end

local function goToMyCastle()
	local own = getLocalCastle()
	if not own then
		return
	end
	centerOnCastle(own)
	selectCastle(own)
end

local function setUiEnabled(enabled: boolean)
	if screenGui then
		screenGui.Enabled = enabled
	end
	LobbyTouchInputSuppress.setHolder("battle-map", enabled)
	LobbyModalInputBlock.setLobbyHubBlocked("battle-map", enabled)
	isOpen = enabled
end

local function buildUi()
	if screenGui then
		return
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BattleMapUi"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = LobbyUiConfig.DISPLAY_ORDER_HUB_OVERLAY + 2
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(18, 24, 32)
	root.BorderSizePixel = 0
	root.Parent = screenGui

	local toolbar = Instance.new("Frame")
	toolbar.Name = "Toolbar"
	toolbar.Size = UDim2.new(1, 0, 0, LobbyUiConfig.BATTLE_MAP_TOOLBAR_HEIGHT)
	toolbar.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_PANEL_HEADER_COLOR
	toolbar.BorderSizePixel = 0
	toolbar.ZIndex = LobbyUiConfig.Z_BATTLE_MAP_TOOLBAR
	toolbar.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(16, 0)
	title.Size = UDim2.fromOffset(120, LobbyUiConfig.BATTLE_MAP_TOOLBAR_HEIGHT)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = LobbyUiConfig.BATTLE_MAP_TITLE_TEXT
	title.Text = "Battle Map"
	title.ZIndex = toolbar.ZIndex + 1
	title.Parent = toolbar

	searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.Position = UDim2.fromOffset(140, 10)
	searchBox.Size = UDim2.fromOffset(180, 32)
	searchBox.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_PANEL_COLOR
	searchBox.Font = Enum.Font.Gotham
	searchBox.TextSize = 14
	searchBox.TextColor3 = LobbyUiConfig.BATTLE_MAP_BODY_TEXT
	searchBox.PlaceholderText = "Search player..."
	searchBox.PlaceholderColor3 = LobbyUiConfig.BATTLE_MAP_MUTED_TEXT
	searchBox.ClearTextOnFocus = false
	searchBox.Text = ""
	searchBox.ZIndex = toolbar.ZIndex + 1
	searchBox.Parent = toolbar
	addCorner(searchBox, 6)

	local searchBtn = Instance.new("TextButton")
	searchBtn.Name = "SearchBtn"
	searchBtn.Position = UDim2.fromOffset(328, 10)
	searchBtn.Size = UDim2.fromOffset(72, 32)
	searchBtn.BackgroundColor3 = Color3.fromRGB(55, 120, 220)
	searchBtn.Font = Enum.Font.GothamBold
	searchBtn.TextSize = 14
	searchBtn.TextColor3 = Color3.new(1, 1, 1)
	searchBtn.Text = "Search"
	searchBtn.ZIndex = toolbar.ZIndex + 1
	searchBtn.Parent = toolbar
	addCorner(searchBtn, 6)

	local myCastleBtn = Instance.new("TextButton")
	myCastleBtn.Name = "MyCastle"
	myCastleBtn.Position = UDim2.fromOffset(412, 10)
	myCastleBtn.Size = UDim2.fromOffset(140, 32)
	myCastleBtn.BackgroundColor3 = Color3.fromRGB(72, 140, 90)
	myCastleBtn.Font = Enum.Font.GothamBold
	myCastleBtn.TextSize = 13
	myCastleBtn.TextColor3 = Color3.new(1, 1, 1)
	myCastleBtn.Text = "Go To My Castle"
	myCastleBtn.ZIndex = toolbar.ZIndex + 1
	myCastleBtn.Parent = toolbar
	addCorner(myCastleBtn, 6)

	local zoomOutBtn = Instance.new("TextButton")
	zoomOutBtn.Name = "ZoomOut"
	zoomOutBtn.AnchorPoint = Vector2.new(1, 0.5)
	zoomOutBtn.Position = UDim2.new(1, -96, 0.5, 0)
	zoomOutBtn.Size = UDim2.fromOffset(36, 32)
	zoomOutBtn.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_PANEL_COLOR
	zoomOutBtn.Font = Enum.Font.GothamBold
	zoomOutBtn.TextSize = 20
	zoomOutBtn.TextColor3 = LobbyUiConfig.BATTLE_MAP_BODY_TEXT
	zoomOutBtn.Text = "−"
	zoomOutBtn.ZIndex = toolbar.ZIndex + 1
	zoomOutBtn.Parent = toolbar
	addCorner(zoomOutBtn, 6)

	local zoomInBtn = Instance.new("TextButton")
	zoomInBtn.Name = "ZoomIn"
	zoomInBtn.AnchorPoint = Vector2.new(1, 0.5)
	zoomInBtn.Position = UDim2.new(1, -52, 0.5, 0)
	zoomInBtn.Size = UDim2.fromOffset(36, 32)
	zoomInBtn.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_PANEL_COLOR
	zoomInBtn.Font = Enum.Font.GothamBold
	zoomInBtn.TextSize = 20
	zoomInBtn.TextColor3 = LobbyUiConfig.BATTLE_MAP_BODY_TEXT
	zoomInBtn.Text = "+"
	zoomInBtn.ZIndex = toolbar.ZIndex + 1
	zoomInBtn.Parent = toolbar
	addCorner(zoomInBtn, 6)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(36, 32)
	closeBtn.BackgroundColor3 = Color3.fromRGB(80, 95, 115)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Text = "X"
	closeBtn.ZIndex = toolbar.ZIndex + 1
	closeBtn.Parent = toolbar
	addCorner(closeBtn, 6)

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	statusLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	statusLabel.Size = UDim2.fromOffset(200, 32)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 14
	statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	statusLabel.Text = ""
	statusLabel.Visible = false
	statusLabel.ZIndex = toolbar.ZIndex + 2
	statusLabel.Parent = toolbar

	mapScroll = Instance.new("ScrollingFrame")
	mapScroll.Name = "MapViewport"
	mapScroll.Position = UDim2.fromOffset(0, LobbyUiConfig.BATTLE_MAP_TOOLBAR_HEIGHT)
	mapScroll.Size = UDim2.new(1, 0, 1, -LobbyUiConfig.BATTLE_MAP_TOOLBAR_HEIGHT)
	mapScroll.BackgroundColor3 = Color3.fromRGB(22, 30, 38)
	mapScroll.BorderSizePixel = 0
	mapScroll.ScrollBarThickness = 8
	mapScroll.ElasticBehavior = Enum.ElasticBehavior.Never
	mapScroll.ScrollingDirection = Enum.ScrollingDirection.XY
	mapScroll.ZIndex = LobbyUiConfig.Z_BATTLE_MAP_SCROLL
	mapScroll.Parent = root

	mapCanvas = Instance.new("Frame")
	mapCanvas.Name = "MapCanvas"
	mapCanvas.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	mapCanvas.BackgroundTransparency = 1
	mapCanvas.BorderSizePixel = 0
	mapCanvas.ZIndex = mapScroll.ZIndex + 1
	mapCanvas.Parent = mapScroll

	mapScale = Instance.new("UIScale")
	mapScale.Name = "ZoomScale"
	mapScale.Scale = zoomLevel
	mapScale.Parent = mapCanvas

	local mapBackground = Instance.new("Frame")
	mapBackground.Name = "MapBackground"
	mapBackground.Size = UDim2.fromScale(1, 1)
	mapBackground.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_BACKGROUND_COLOR
	mapBackground.BorderSizePixel = 0
	mapBackground.ZIndex = mapCanvas.ZIndex
	mapBackground.Parent = mapCanvas

	if LobbyUiConfig.BATTLE_MAP_BACKGROUND_IMAGE ~= "" then
		local tileSize = LobbyUiConfig.BATTLE_MAP_TERRAIN_TILE_SIZE
		local bgImage = Instance.new("ImageLabel")
		bgImage.Name = "BgImage"
		bgImage.Size = UDim2.fromScale(1, 1)
		bgImage.BackgroundTransparency = 1
		bgImage.Image = LobbyUiConfig.BATTLE_MAP_BACKGROUND_IMAGE
		bgImage.ScaleType = Enum.ScaleType.Tile
		bgImage.TileSize = UDim2.fromOffset(tileSize.X, tileSize.Y)
		bgImage.ZIndex = mapBackground.ZIndex
		bgImage.Parent = mapBackground
	end

	buildMapGrid(mapCanvas)

	sidePanel = Instance.new("Frame")
	sidePanel.Name = "SidePanel"
	sidePanel.AnchorPoint = Vector2.new(1, 0)
	sidePanel.Position = UDim2.new(1, -8, 0, LobbyUiConfig.BATTLE_MAP_TOOLBAR_HEIGHT + 8)
	sidePanel.Size = UDim2.new(0, LobbyUiConfig.BATTLE_MAP_SIDE_PANEL_WIDTH, 1, -(LobbyUiConfig.BATTLE_MAP_TOOLBAR_HEIGHT + 16))
	sidePanel.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_PANEL_COLOR
	sidePanel.BorderSizePixel = 0
	sidePanel.Visible = false
	sidePanel.ZIndex = LobbyUiConfig.Z_BATTLE_MAP_SIDE_PANEL
	sidePanel.Parent = root
	addCorner(sidePanel, 10)
	addStroke(sidePanel, LobbyUiConfig.BATTLE_MAP_PANEL_STROKE, 2, 0.2)

	local panelHeader = Instance.new("Frame")
	panelHeader.Name = "Header"
	panelHeader.Size = UDim2.new(1, 0, 0, 44)
	panelHeader.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_PANEL_HEADER_COLOR
	panelHeader.BorderSizePixel = 0
	panelHeader.ZIndex = sidePanel.ZIndex + 1
	panelHeader.Parent = sidePanel

	local panelHeaderCorner = Instance.new("UICorner")
	panelHeaderCorner.CornerRadius = UDim.new(0, 10)
	panelHeaderCorner.Parent = panelHeader

	local panelTitle = Instance.new("TextLabel")
	panelTitle.Name = "Title"
	panelTitle.Position = UDim2.fromOffset(16, 0)
	panelTitle.Size = UDim2.new(1, -60, 1, 0)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Font = Enum.Font.GothamBold
	panelTitle.TextSize = 18
	panelTitle.TextXAlignment = Enum.TextXAlignment.Left
	panelTitle.TextColor3 = LobbyUiConfig.BATTLE_MAP_TITLE_TEXT
	panelTitle.Text = "Castle Info"
	panelTitle.ZIndex = panelHeader.ZIndex + 1
	panelTitle.Parent = panelHeader

	local panelClose = Instance.new("TextButton")
	panelClose.Name = "Close"
	panelClose.AnchorPoint = Vector2.new(1, 0.5)
	panelClose.Position = UDim2.new(1, -8, 0.5, 0)
	panelClose.Size = UDim2.fromOffset(32, 32)
	panelClose.BackgroundColor3 = Color3.fromRGB(80, 95, 115)
	panelClose.Font = Enum.Font.GothamBold
	panelClose.TextSize = 18
	panelClose.TextColor3 = Color3.new(1, 1, 1)
	panelClose.Text = "X"
	panelClose.ZIndex = panelHeader.ZIndex + 2
	panelClose.Parent = panelHeader
	addCorner(panelClose, 6)

	detailLabels.owner = makeDetailRow(sidePanel, "Owner", 56)
	detailLabels.power = makeDetailRow(sidePanel, "Power", 108)
	detailLabels.level = makeDetailRow(sidePanel, "Castle Level", 160)
	detailLabels.region = makeDetailRow(sidePanel, "Region", 212)

	attackButton = Instance.new("TextButton")
	attackButton.Name = "Attack"
	attackButton.AnchorPoint = Vector2.new(0.5, 1)
	attackButton.Position = UDim2.new(0.5, 0, 1, -16)
	attackButton.Size = UDim2.new(1, -32, 0, 44)
	attackButton.BackgroundColor3 = LobbyUiConfig.BATTLE_MAP_ATTACK_COLOR
	attackButton.Font = Enum.Font.GothamBold
	attackButton.TextSize = 18
	attackButton.TextColor3 = Color3.new(1, 1, 1)
	attackButton.Text = "Attack"
	attackButton.ZIndex = sidePanel.ZIndex + 1
	attackButton.Parent = sidePanel
	addCorner(attackButton, 8)

	bindPressOnce(searchBtn, runSearch)
	bindPressOnce(myCastleBtn, goToMyCastle)
	bindPressOnce(zoomOutBtn, function()
		applyZoom(-LobbyUiConfig.BATTLE_MAP_ZOOM_STEP)
	end)
	bindPressOnce(zoomInBtn, function()
		applyZoom(LobbyUiConfig.BATTLE_MAP_ZOOM_STEP)
	end)
	bindPressOnce(closeBtn, function()
		M.close()
	end)
	bindPressOnce(panelClose, closeSidePanel)
	bindPressOnce(attackButton, function()
		if not selectedCastleId then
			return
		end
		local castle = getCastleById(selectedCastleId)
		if not castle or castle.isLocalPlayer then
			return
		end
		M.close(false)
		requestAttackCastle(castle.id)
	end)

	searchBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			runSearch()
		end
	end)

	updateCanvasSize()
end

function M.init()
	buildUi()
end

function M.isOpen(): boolean
	return isOpen
end

function M.setOnClose(callback: (() -> ())?)
	onCloseCallback = callback
end

function M.open()
	buildUi()
	castles = cloneCastlesForLocalPlayer()
	rebuildCastleMarkers()
	closeSidePanel()
	zoomLevel = LobbyUiConfig.BATTLE_MAP_DEFAULT_ZOOM
	updateCanvasSize()
	if searchBox then
		searchBox.Text = ""
	end
	setStatus(nil)

	local BattleQueue = require(script.Parent:WaitForChild("BattleQueue"))
	BattleQueue.close()

	setUiEnabled(true)

	task.defer(function()
		local own = getLocalCastle()
		if own then
			centerOnCastle(own)
		end
	end)
end

function M.close(reopenQueue: boolean?)
	closeSidePanel()
	setUiEnabled(false)
	if reopenQueue ~= false and onCloseCallback then
		onCloseCallback()
	end
end

return M
