--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local BattleElementTags = require(shared:WaitForChild("BattleElementTags"))
local BattleGridConfig = require(shared:WaitForChild("BattleGridConfig"))
local BattleGridSides = require(shared:WaitForChild("BattleGridSides"))
local BattleLayoutTypes = require(shared:WaitForChild("BattleLayoutTypes"))
local BattleGridProjection = require(shared:WaitForChild("BattleGridProjection"))
local BattleUiConfig = require(shared:WaitForChild("BattleUiConfig"))
local LobbyUiConfig = require(shared:WaitForChild("LobbyUiConfig"))
local SplashKillFishFrames = require(shared:WaitForChild("SplashKillFishFrames"))

local BattleUnitStats = require(shared:WaitForChild("BattleUnitStats"))
local BattleCollectionCards = require(script.Parent:WaitForChild("BattleCollectionCards"))
local FishCollectionInventory = require(script.Parent:WaitForChild("FishCollectionInventory"))
local LobbyModalInputBlock = require(script.Parent:WaitForChild("LobbyModalInputBlock"))
local LobbyTouchInputSuppress = require(script.Parent:WaitForChild("LobbyTouchInputSuppress"))

type BattlePlacementStatePayload = BattleLayoutTypes.BattlePlacementStatePayload
type BattleSide = BattleLayoutTypes.BattleSide
type PlacementUnit = BattleLayoutTypes.PlacementUnit
type CombatUnitSnapshot = BattleLayoutTypes.CombatUnitSnapshot

local REMOTES_NAME = "LobbyRemotes"
local REMOTE_ACTION = "BattlePlacementAction"
local REMOTE_READY = "BattleSetReady"
local REMOTE_SUMMON = "BattleSummon"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local M = {}

local screenGui: ScreenGui
local root: Frame
local headerBar: Frame
local bodyRow: Frame
local leftPanel: Frame
local centerPanel: Frame
local rightPanel: Frame
local footerBar: Frame
local timerLabel: TextLabel
local baseHpLabel: TextLabel
local manaLabel: TextLabel
local placedLabel: TextLabel
local enemyPlacedLabel: TextLabel
local readyButton: TextButton
local collectionScroll: ScrollingFrame
local enemyScroll: ScrollingFrame
local collectionEmptyLabel: TextLabel
local gridHost: Frame
local combatOverlay: Frame
local cellButtons: { [string]: TextButton } = {}
local hidePlacementArt = false
local selectedImageId: string? = nil
local currentState: BattlePlacementStatePayload? = nil
local ownedByImageId: { [string]: number } = {}
local combatFieldImageIds: { [string]: boolean } = {}
local placementOnFieldImageIds: { [string]: boolean } = {}
local onCloseCallback: (() -> ())? = nil
local didBuild = false
local timerConnection: RBXScriptConnection? = nil
local viewportConnection: RBXScriptConnection? = nil
local bodySizeConnection: RBXScriptConnection? = nil
local centerSizeConnection: RBXScriptConnection? = nil
local layoutRetryToken = 0
local currentCellSize = 44
local currentGridPad = BattleUiConfig.GRID_PAD
local currentLayoutMetrics: BattleGridProjection.LayoutMetrics = BattleGridProjection.computeLayoutMetrics(
	44,
	BattleUiConfig.GRID_PAD,
	BattleGridConfig.COLS,
	BattleGridConfig.ROWS
)

local function cellKey(col: number, row: number): string
	return tostring(col) .. "_" .. tostring(row)
end

local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(REMOTES_NAME):WaitForChild(name) :: RemoteEvent
end

local function fireAction(payload: { [string]: any })
	getRemote(REMOTE_ACTION):FireServer(payload)
end

local function fireSummon(payload: { [string]: any })
	getRemote(REMOTE_SUMMON):FireServer(payload)
end

local function isCompactViewport(): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local v = camera.ViewportSize
	return v.X < BattleUiConfig.COMPACT_VIEWPORT_X or v.Y < BattleUiConfig.COMPACT_VIEWPORT_Y
end

local function seedOwnedFromInventory()
	local cached = FishCollectionInventory.getOwnedForMap(BattleGridConfig.MAP_ID)
	table.clear(ownedByImageId)
	for imageId, count in cached do
		if count > 0 then
			ownedByImageId[imageId] = count
		end
	end
end

local function clearScrollChildren(scroll: ScrollingFrame)
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") and not child:IsA("UIGridLayout") and child.Name ~= "Empty" then
			child:Destroy()
		end
	end
end

local function getCardSize(): (number, number)
	if isCompactViewport() then
		return BattleUiConfig.CARD_WIDTH_COMPACT, BattleUiConfig.CARD_HEIGHT_COMPACT
	end
	return BattleUiConfig.CARD_WIDTH, BattleUiConfig.CARD_HEIGHT
end

local function syncPlacementOnFieldFromState()
	table.clear(placementOnFieldImageIds)
	if not currentState or currentState.phase ~= "placement" then
		return
	end
	local side = currentState.localSide
	local layout = if side == "A" then currentState.layoutA else currentState.layoutB
	for _, unit in layout do
		placementOnFieldImageIds[unit.imageId] = true
	end
end

local function getOnFieldImageIds(): { [string]: boolean }
	if not currentState then
		return {}
	end
	if currentState.phase == "combat" then
		return combatFieldImageIds
	end
	return placementOnFieldImageIds
end

local function getMyLayout(): SideLayout
	if not currentState then
		return {}
	end
	if currentState.localSide == "A" then
		return currentState.layoutA
	end
	return currentState.layoutB
end

local function setMyLayout(layout: SideLayout)
	if not currentState then
		return
	end
	if currentState.localSide == "A" then
		currentState.layoutA = layout
	else
		currentState.layoutB = layout
	end
	syncPlacementOnFieldFromState()
end

local function renderCollection()
	if not collectionScroll then
		return
	end
	clearScrollChildren(collectionScroll)

	local filter: BattleElementTags.BattleFilterId = "all"
	local onField = getOnFieldImageIds()
	local ids: { string } = {}
	for imageId, count in ownedByImageId do
		if count > 0
			and not onField[imageId]
			and BattleElementTags.fishMatchesFilter(BattleGridConfig.MAP_ID, imageId, filter)
		then
			table.insert(ids, imageId)
		end
	end
	table.sort(ids)

	if selectedImageId and onField[selectedImageId] then
		selectedImageId = nil
	end

	collectionEmptyLabel.Visible = #ids == 0

	local cardW, cardH = getCardSize()
	local grid = collectionScroll:FindFirstChildOfClass("UIGridLayout")
	if not grid then
		grid = Instance.new("UIGridLayout")
		grid.Name = "GridLayout"
		grid.Parent = collectionScroll
	end
	grid.CellSize = UDim2.fromOffset(cardW, cardH)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.FillDirectionMaxCells = BattleUiConfig.CARD_GRID_COLUMNS

	for _, imageId in ids do
		local count = ownedByImageId[imageId] or 1
		local manaCost: number? = nil
		if currentState and currentState.phase == "combat" then
			manaCost = BattleUnitStats.getManaCostForFish(BattleGridConfig.MAP_ID, imageId)
		end
		local card = BattleCollectionCards.makeCard({
			imageId = imageId,
			copyCount = count,
			mapId = BattleGridConfig.MAP_ID,
			width = cardW,
			height = cardH,
			selected = selectedImageId == imageId,
			manaCost = manaCost,
			onClick = function()
				selectedImageId = if selectedImageId == imageId then nil else imageId
				renderCollection()
			end,
		})
		card.Parent = collectionScroll
	end
end

local function makeEnemyChip(unit: PlacementUnit, cardW: number, cardH: number): Frame
	local chip = Instance.new("Frame")
	chip.Name = "EnemyChip"
	chip.Size = UDim2.fromOffset(cardW, cardH)
	chip.BackgroundColor3 = Color3.fromRGB(36, 28, 32)
	chip.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = chip

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.42)
	art.Size = UDim2.fromOffset(cardW * 0.65, cardH * 0.5)
	art.BackgroundTransparency = 1
	art.Image = unit.imageId
	art.ImageTransparency = 0.5
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = chip
	SplashKillFishFrames.applyFullImageToLabel(art)

	local overlay = Instance.new("Frame")
	overlay.Name = "HiddenOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(12, 10, 14)
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Parent = chip

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 8)
	overlayCorner.Parent = overlay

	local q = Instance.new("TextLabel")
	q.Size = UDim2.fromScale(1, 1)
	q.BackgroundTransparency = 1
	q.Font = Enum.Font.GothamBold
	q.TextSize = math.floor(cardH * 0.4)
	q.TextColor3 = Color3.fromRGB(180, 170, 190)
	q.Text = "?"
	q.Parent = overlay

	local lvl = Instance.new("TextLabel")
	lvl.AnchorPoint = Vector2.new(0, 0)
	lvl.Position = UDim2.fromOffset(4, 4)
	lvl.Size = UDim2.fromOffset(28, 16)
	lvl.BackgroundColor3 = Color3.fromRGB(48, 32, 40)
	lvl.BackgroundTransparency = 0.1
	lvl.Font = Enum.Font.GothamBold
	lvl.TextSize = 11
	lvl.TextColor3 = Color3.fromRGB(255, 200, 200)
	lvl.Text = "L" .. tostring(unit.level)
	lvl.Parent = chip

	return chip
end

local function renderEnemyPanel()
	if not enemyScroll or not currentState then
		return
	end
	clearScrollChildren(enemyScroll)

	local side = currentState.localSide
	local enemyLayout = if side == "A" then currentState.layoutB else currentState.layoutA
	enemyPlacedLabel.Text = string.format("UNITS PLACED: %d / %d", #enemyLayout, BattleGridConfig.MAX_UNITS_PER_SIDE)

	local cardW, cardH = getCardSize()
	local grid = enemyScroll:FindFirstChildOfClass("UIGridLayout")
	if not grid then
		grid = Instance.new("UIGridLayout")
		grid.Name = "GridLayout"
		grid.Parent = enemyScroll
	end
	grid.CellSize = UDim2.fromOffset(cardW, cardH)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.FillDirectionMaxCells = BattleUiConfig.CARD_GRID_COLUMNS

	for i, unit in enemyLayout do
		local chip = makeEnemyChip(unit, cardW, cardH)
		chip.LayoutOrder = i
		chip.Parent = enemyScroll
	end
end

local function findUnitAt(layout: { PlacementUnit }, col: number, row: number): PlacementUnit?
	for _, unit in layout do
		if unit.col == col and unit.row == row then
			return unit
		end
	end
	return nil
end

local function updateCellVisual(btn: TextButton, col: number, row: number)
	if not currentState then
		return
	end
	local unit = if hidePlacementArt
		then nil
		else (findUnitAt(currentState.layoutA, col, row) or findUnitAt(currentState.layoutB, col, row))
	local isBlue = BattleGridSides.sideForCell(col, row) == "A"
	local isBaseRow = row == BattleGridConfig.SIDE_B_BASE_ROW or row == BattleGridConfig.SIDE_A_BASE_ROW
	btn.BackgroundColor3 = if isBaseRow
		then Color3.fromRGB(88, 72, 28)
		elseif isBlue then Color3.fromRGB(32, 52, 88)
		else Color3.fromRGB(72, 36, 40)
	btn.BackgroundTransparency = if isBaseRow then 0.2 else 0.35

	local art = btn:FindFirstChild("UnitArt")
	if art then
		art:Destroy()
	end

	if unit then
		local img = Instance.new("ImageLabel")
		img.Name = "UnitArt"
		img.Size = UDim2.fromScale(0.85, 0.85)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.BackgroundTransparency = 1
		img.Image = unit.imageId
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = btn.ZIndex + 1
		img.Parent = btn
		SplashKillFishFrames.applyFullImageToLabel(img)
	end
end

local function refreshGrid()
	if not currentState then
		return
	end
	for col = 0, BattleGridConfig.COLS - 1 do
		for row = 0, BattleGridConfig.ROWS - 1 do
			local btn = cellButtons[cellKey(col, row)]
			if btn then
				updateCellVisual(btn, col, row)
			end
		end
	end
end

local function layoutGridCells()
	if not gridHost or not centerPanel then
		return
	end

	local avail = centerPanel.AbsoluteSize
	if avail.X < 8 or avail.Y < 8 then
		return
	end

	local pad = currentGridPad
	local cols = BattleGridConfig.COLS
	local rows = BattleGridConfig.ROWS
	local cell = BattleGridProjection.resolveCellSize(
		avail.X,
		avail.Y,
		cols,
		rows,
		BattleUiConfig.GRID_MIN_CELL,
		BattleUiConfig.GRID_MAX_CELL,
		pad
	)
	currentCellSize = cell
	currentLayoutMetrics = BattleGridProjection.computeLayoutMetrics(cell, pad, cols, rows)

	local gridW = currentLayoutMetrics.gridW
	local gridH = currentLayoutMetrics.gridH
	gridHost.AnchorPoint = Vector2.new(0, 0)
	gridHost.Size = UDim2.fromOffset(gridW, gridH)
	gridHost.BackgroundTransparency = if BattleGridProjection.isPerspective() then 1 else 0
	local offsetX = math.max(0, math.floor((avail.X - gridW) * 0.5))
	local offsetY = math.max(0, math.floor((avail.Y - gridH) * 0.5))
	gridHost.Position = UDim2.fromOffset(offsetX, offsetY)

	local baseZ = BattleUiConfig.Z_GRID + 1
	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			local btn = cellButtons[cellKey(col, row)]
			if btn then
				local x, y = BattleGridProjection.cellTopLeft(col, row, currentLayoutMetrics)
				local tile = BattleGridProjection.cellSizeAt(col, row, currentLayoutMetrics)
				btn.Size = UDim2.fromOffset(tile, tile)
				btn.Position = UDim2.fromOffset(x, y)
				btn.ZIndex = BattleGridProjection.cellZIndex(baseZ, col, row, cols)
			end
		end
	end
end

local function layoutHud()
	if not root or not bodyRow then
		return
	end

	local compact = isCompactViewport()
	local inset = BattleUiConfig.ROOT_INSET
	local headerH = if compact then BattleUiConfig.HEADER_HEIGHT_COMPACT else BattleUiConfig.HEADER_HEIGHT
	local footerH = if compact then BattleUiConfig.FOOTER_HEIGHT_COMPACT else BattleUiConfig.FOOTER_HEIGHT

	root.Position = UDim2.fromOffset(inset, inset)
	root.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)

	headerBar.Size = UDim2.new(1, 0, 0, headerH)
	footerBar.Size = UDim2.new(1, 0, 0, footerH)
	footerBar.Position = UDim2.new(0, 0, 1, -footerH)

	bodyRow.Position = UDim2.fromOffset(0, headerH)
	bodyRow.Size = UDim2.new(1, 0, 1, -(headerH + footerH))

	-- Scale-based columns: avoids wrong positions when AbsoluteSize is stale on mobile.
	local sideScale = if compact then 0.24 else BattleUiConfig.SIDE_WIDTH_SCALE
	local centerScale = math.max(0.32, 1 - sideScale * 2)

	leftPanel.Size = UDim2.new(sideScale, 0, 1, 0)
	leftPanel.Position = UDim2.fromScale(0, 0)
	centerPanel.Size = UDim2.new(centerScale, 0, 1, 0)
	centerPanel.Position = UDim2.new(sideScale, 0, 0, 0)
	rightPanel.Size = UDim2.new(sideScale, 0, 1, 0)
	rightPanel.Position = UDim2.new(1 - sideScale, 0, 0, 0)

	local scrollBar = if compact then BattleUiConfig.SCROLL_BAR_THICKNESS_COMPACT else BattleUiConfig.SCROLL_BAR_THICKNESS
	collectionScroll.ScrollBarThickness = scrollBar
	enemyScroll.ScrollBarThickness = scrollBar

	local collectionScrollTop = 32
	collectionScroll.Position = UDim2.fromOffset(6, collectionScrollTop)
	collectionScroll.Size = UDim2.new(1, -12, 1, -collectionScrollTop - 4)
	local enemyScrollTop = 50
	enemyScroll.Position = UDim2.fromOffset(6, enemyScrollTop)
	enemyScroll.Size = UDim2.new(1, -12, 1, -enemyScrollTop - 4)

	task.defer(layoutGridCells)
	task.defer(function()
		renderCollection()
		renderEnemyPanel()
	end)
end

local function scheduleLayoutUntilReady()
	layoutRetryToken += 1
	local token = layoutRetryToken
	task.spawn(function()
		for _ = 1, 15 do
			if token ~= layoutRetryToken then
				return
			end
			if not screenGui or not screenGui.Enabled then
				return
			end
			layoutHud()
			local avail = if centerPanel then centerPanel.AbsoluteSize else Vector2.zero
			if avail.X >= 64 and avail.Y >= 64 then
				layoutGridCells()
				renderCollection()
				renderEnemyPanel()
				return
			end
			RunService.Heartbeat:Wait()
		end
		layoutGridCells()
	end)
end

local function onCellClick(col: number, row: number)
	if not currentState then
		return
	end
	local side = currentState.localSide
	if not BattleGridSides.cellInSide(col, row, side) then
		return
	end

	if currentState.phase == "combat" then
		if selectedImageId then
			fireSummon({
				imageId = selectedImageId,
				col = col,
				row = row,
			})
			selectedImageId = nil
			renderCollection()
		end
		return
	end

	if currentState.phase ~= "placement" then
		return
	end
	local layout = getMyLayout()
	local existing = findUnitAt(layout, col, row)
	if existing then
		local newLayout: SideLayout = {}
		for _, unit in layout do
			if not (unit.col == col and unit.row == row) then
				table.insert(newLayout, unit)
			end
		end
		setMyLayout(newLayout)
		renderCollection()
		refreshGrid()
		if placedLabel then
			placedLabel.Text = string.format(
				"UNITS PLACED: %d / %d",
				#newLayout,
				BattleGridConfig.MAX_UNITS_PER_SIDE
			)
		end
		fireAction({ action = "remove", col = col, row = row })
		return
	end
	if selectedImageId then
		local imageId = selectedImageId
		local copyCount = ownedByImageId[imageId] or 1
		local level = BattleUnitStats.getLevelFromCopyCount(copyCount)
		local newLayout: SideLayout = {}
		for _, unit in layout do
			table.insert(newLayout, unit)
		end
		table.insert(newLayout, {
			imageId = imageId,
			col = col,
			row = row,
			level = level,
		})
		setMyLayout(newLayout)
		selectedImageId = nil
		renderCollection()
		refreshGrid()
		if placedLabel then
			placedLabel.Text = string.format(
				"UNITS PLACED: %d / %d",
				#newLayout,
				BattleGridConfig.MAX_UNITS_PER_SIDE
			)
		end
		fireAction({
			action = "place",
			imageId = imageId,
			col = col,
			row = row,
		})
	end
end

local function buildGridCells()
	for col = 0, BattleGridConfig.COLS - 1 do
		for row = 0, BattleGridConfig.ROWS - 1 do
			local btn = Instance.new("TextButton")
			btn.Name = "Cell_" .. cellKey(col, row)
			btn.Text = ""
			btn.AutoButtonColor = false
			btn.Active = true
			btn.BorderSizePixel = 0
			btn.ZIndex = BattleUiConfig.Z_GRID + 1
			local c = col
			local r = row
			btn.MouseButton1Click:Connect(function()
				onCellClick(c, r)
			end)
			btn.Parent = gridHost
			cellButtons[cellKey(col, row)] = btn
		end
	end
end

local function buildUi()
	if didBuild then
		return
	end
	didBuild = true

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BattlePlacement"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ScreenInsets = Enum.ScreenInsets.None
	screenGui.DisplayOrder = LobbyUiConfig.DISPLAY_ORDER_HUB_OVERLAY + 2
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local inputBlocker = LobbyModalInputBlock.create(screenGui, {
		name = "InputBlocker",
		zIndex = 1,
		backgroundTransparency = 0.25,
	})
	inputBlocker.Active = false

	root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	root.BorderSizePixel = 0
	root.ZIndex = 2
	root.Active = false
	root.Parent = screenGui

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 8)
	rootCorner.Parent = root

	headerBar = Instance.new("Frame")
	headerBar.Name = "Header"
	headerBar.Size = UDim2.new(1, 0, 0, BattleUiConfig.HEADER_HEIGHT)
	headerBar.BackgroundTransparency = 1
	headerBar.Active = false
	headerBar.ZIndex = BattleUiConfig.Z_HEADER
	headerBar.Parent = root

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(0.5, 0, 1, 0)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 22
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.new(1, 1, 1)
	header.Text = "  BATTLE MODE"
	header.ZIndex = BattleUiConfig.Z_HEADER + 1
	header.Parent = headerBar

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.AnchorPoint = Vector2.new(1, 0.5)
	timerLabel.Position = UDim2.new(1, -8, 0.5, 0)
	timerLabel.Size = UDim2.fromOffset(240, 28)
	timerLabel.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	timerLabel.BackgroundTransparency = 0.2
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 14
	timerLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	timerLabel.Text = "PLACEMENT PHASE"
	timerLabel.ZIndex = BattleUiConfig.Z_HEADER + 1
	timerLabel.Parent = headerBar

	baseHpLabel = Instance.new("TextLabel")
	baseHpLabel.Name = "BaseHp"
	baseHpLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	baseHpLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	baseHpLabel.Size = UDim2.new(0.5, 0, 1, 0)
	baseHpLabel.BackgroundTransparency = 1
	baseHpLabel.Font = Enum.Font.GothamBold
	baseHpLabel.TextSize = 13
	baseHpLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	baseHpLabel.Text = ""
	baseHpLabel.Visible = false
	baseHpLabel.ZIndex = BattleUiConfig.Z_HEADER + 1
	baseHpLabel.Parent = headerBar

	bodyRow = Instance.new("Frame")
	bodyRow.Name = "Body"
	bodyRow.BackgroundTransparency = 1
	bodyRow.Active = false
	bodyRow.ZIndex = BattleUiConfig.Z_SIDEBAR
	bodyRow.Parent = root

	leftPanel = Instance.new("Frame")
	leftPanel.Name = "Collection"
	leftPanel.BackgroundColor3 = Color3.fromRGB(28, 34, 44)
	leftPanel.BorderSizePixel = 0
	leftPanel.ClipsDescendants = true
	leftPanel.Active = false
	leftPanel.ZIndex = BattleUiConfig.Z_SIDEBAR
	leftPanel.Parent = bodyRow

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 6)
	leftCorner.Parent = leftPanel

	local leftTitle = Instance.new("TextLabel")
	leftTitle.Size = UDim2.new(1, 0, 0, 28)
	leftTitle.BackgroundTransparency = 1
	leftTitle.Font = Enum.Font.GothamBold
	leftTitle.TextSize = 12
	leftTitle.TextColor3 = Color3.new(1, 1, 1)
	leftTitle.Text = "YOUR COLLECTION"
	leftTitle.ZIndex = BattleUiConfig.Z_SIDEBAR + 1
	leftTitle.Parent = leftPanel

	collectionScroll = Instance.new("ScrollingFrame")
	collectionScroll.Name = "Cards"
	collectionScroll.BackgroundTransparency = 1
	collectionScroll.ScrollBarThickness = BattleUiConfig.SCROLL_BAR_THICKNESS
	collectionScroll.ScrollingEnabled = true
	collectionScroll.Active = false
	collectionScroll.ClipsDescendants = true
	collectionScroll.CanvasSize = UDim2.new()
	collectionScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	collectionScroll.ZIndex = BattleUiConfig.Z_SIDEBAR + 1
	collectionScroll.Parent = leftPanel

	collectionEmptyLabel = Instance.new("TextLabel")
	collectionEmptyLabel.Name = "Empty"
	collectionEmptyLabel.Size = UDim2.new(1, -12, 0, 40)
	collectionEmptyLabel.Position = UDim2.fromOffset(6, 40)
	collectionEmptyLabel.BackgroundTransparency = 1
	collectionEmptyLabel.Font = Enum.Font.GothamMedium
	collectionEmptyLabel.TextSize = 12
	collectionEmptyLabel.TextWrapped = true
	collectionEmptyLabel.TextColor3 = Color3.fromRGB(140, 150, 165)
	collectionEmptyLabel.Text = "No fish collected yet"
	collectionEmptyLabel.Visible = false
	collectionEmptyLabel.ZIndex = BattleUiConfig.Z_SIDEBAR + 2
	collectionEmptyLabel.Parent = leftPanel

	centerPanel = Instance.new("Frame")
	centerPanel.Name = "Center"
	centerPanel.BackgroundTransparency = 1
	centerPanel.ClipsDescendants = true
	centerPanel.Active = false
	centerPanel.ZIndex = BattleUiConfig.Z_GRID
	centerPanel.Parent = bodyRow

	centerSizeConnection = centerPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGridCells)

	gridHost = Instance.new("Frame")
	gridHost.Name = "Grid"
	gridHost.AnchorPoint = Vector2.new(0, 0)
	gridHost.Position = UDim2.fromOffset(0, 0)
	gridHost.BackgroundColor3 = Color3.fromRGB(40, 55, 38)
	gridHost.BorderSizePixel = 0
	gridHost.Active = false
	gridHost.ZIndex = BattleUiConfig.Z_GRID
	gridHost.Parent = centerPanel

	local gridCorner = Instance.new("UICorner")
	gridCorner.CornerRadius = UDim.new(0, 6)
	gridCorner.Parent = gridHost

	buildGridCells()

	combatOverlay = Instance.new("Frame")
	combatOverlay.Name = "CombatOverlay"
	combatOverlay.Size = UDim2.fromScale(1, 1)
	combatOverlay.Position = UDim2.fromOffset(0, 0)
	combatOverlay.BackgroundTransparency = 1
	combatOverlay.ClipsDescendants = false
	combatOverlay.Active = false
	combatOverlay.ZIndex = BattleUiConfig.Z_GRID + 10
	combatOverlay.Parent = gridHost

	rightPanel = Instance.new("Frame")
	rightPanel.Name = "Enemy"
	rightPanel.BackgroundColor3 = Color3.fromRGB(44, 28, 32)
	rightPanel.BorderSizePixel = 0
	rightPanel.ClipsDescendants = true
	rightPanel.Active = false
	rightPanel.ZIndex = BattleUiConfig.Z_SIDEBAR
	rightPanel.Parent = bodyRow

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 6)
	rightCorner.Parent = rightPanel

	local rightTitle = Instance.new("TextLabel")
	rightTitle.Size = UDim2.new(1, 0, 0, 28)
	rightTitle.BackgroundTransparency = 1
	rightTitle.Font = Enum.Font.GothamBold
	rightTitle.TextSize = 12
	rightTitle.TextColor3 = Color3.new(1, 1, 1)
	rightTitle.Text = "ENEMY TEAM"
	rightTitle.ZIndex = BattleUiConfig.Z_SIDEBAR + 1
	rightTitle.Parent = rightPanel

	enemyPlacedLabel = Instance.new("TextLabel")
	enemyPlacedLabel.Size = UDim2.new(1, -8, 0, 0)
	enemyPlacedLabel.AutomaticSize = Enum.AutomaticSize.Y
	enemyPlacedLabel.Position = UDim2.fromOffset(4, 28)
	enemyPlacedLabel.BackgroundTransparency = 1
	enemyPlacedLabel.Font = Enum.Font.GothamMedium
	enemyPlacedLabel.TextSize = 11
	enemyPlacedLabel.TextXAlignment = Enum.TextXAlignment.Left
	enemyPlacedLabel.TextColor3 = Color3.fromRGB(220, 180, 180)
	enemyPlacedLabel.Text = "UNITS PLACED: 0 / 10"
	enemyPlacedLabel.ZIndex = BattleUiConfig.Z_SIDEBAR + 1
	enemyPlacedLabel.Parent = rightPanel

	enemyScroll = Instance.new("ScrollingFrame")
	enemyScroll.Name = "EnemyCards"
	enemyScroll.BackgroundTransparency = 1
	enemyScroll.ScrollBarThickness = BattleUiConfig.SCROLL_BAR_THICKNESS
	enemyScroll.ScrollingEnabled = true
	enemyScroll.Active = false
	enemyScroll.ClipsDescendants = true
	enemyScroll.CanvasSize = UDim2.new()
	enemyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	enemyScroll.ZIndex = BattleUiConfig.Z_SIDEBAR + 1
	enemyScroll.Parent = rightPanel

	footerBar = Instance.new("Frame")
	footerBar.Name = "Footer"
	footerBar.BackgroundColor3 = Color3.fromRGB(22, 28, 38)
	footerBar.BackgroundTransparency = 0.15
	footerBar.BorderSizePixel = 0
	footerBar.Active = false
	footerBar.ZIndex = BattleUiConfig.Z_FOOTER
	footerBar.Parent = root

	placedLabel = Instance.new("TextLabel")
	placedLabel.AnchorPoint = Vector2.new(0, 0.5)
	placedLabel.Position = UDim2.new(0, 12, 0.5, 0)
	placedLabel.Size = UDim2.new(0.45, 0, 1, 0)
	placedLabel.BackgroundTransparency = 1
	placedLabel.Font = Enum.Font.GothamMedium
	placedLabel.TextSize = 13
	placedLabel.TextXAlignment = Enum.TextXAlignment.Left
	placedLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
	placedLabel.Text = "UNITS PLACED: 0 / 10"
	placedLabel.ZIndex = BattleUiConfig.Z_FOOTER + 1
	placedLabel.Parent = footerBar

	manaLabel = Instance.new("TextLabel")
	manaLabel.AnchorPoint = Vector2.new(0, 0.5)
	manaLabel.Position = UDim2.new(0, 12, 0.5, 0)
	manaLabel.Size = UDim2.new(0.45, 0, 1, 0)
	manaLabel.BackgroundTransparency = 1
	manaLabel.Font = Enum.Font.GothamMedium
	manaLabel.TextSize = 13
	manaLabel.TextXAlignment = Enum.TextXAlignment.Left
	manaLabel.TextColor3 = Color3.fromRGB(140, 200, 255)
	manaLabel.Text = ""
	manaLabel.Visible = false
	manaLabel.ZIndex = BattleUiConfig.Z_FOOTER + 1
	manaLabel.Parent = footerBar

	readyButton = Instance.new("TextButton")
	readyButton.AnchorPoint = Vector2.new(1, 0.5)
	readyButton.Position = UDim2.new(1, -12, 0.5, 0)
	readyButton.Size = UDim2.fromOffset(180, 40)
	readyButton.BackgroundColor3 = Color3.fromRGB(55, 120, 220)
	readyButton.Font = Enum.Font.GothamBold
	readyButton.TextSize = 18
	readyButton.TextColor3 = Color3.new(1, 1, 1)
	readyButton.Text = "READY"
	readyButton.ZIndex = BattleUiConfig.Z_FOOTER + 1
	readyButton.Parent = footerBar

	local readyCorner = Instance.new("UICorner")
	readyCorner.CornerRadius = UDim.new(0, 8)
	readyCorner.Parent = readyButton

	readyButton.MouseButton1Click:Connect(function()
		getRemote(REMOTE_READY):FireServer()
	end)

	bodySizeConnection = bodyRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)

	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutHud)
	end
end

local function updateCombatStats()
	if not currentState or currentState.phase ~= "combat" then
		if baseHpLabel then
			baseHpLabel.Visible = false
		end
		if manaLabel then
			manaLabel.Visible = false
		end
		return
	end
	local maxBase = currentState.maxBaseHp or BattleGridConfig.STARTING_BASE_HP
	local hpA = currentState.baseHpA or maxBase
	local hpB = currentState.baseHpB or maxBase
	local side = currentState.localSide
	local myHp = if side == "A" then hpA else hpB
	local theirHp = if side == "A" then hpB else hpA
	baseHpLabel.Visible = true
	baseHpLabel.Text = string.format("BASE  You:%d  Enemy:%d  /%d", math.floor(myHp), math.floor(theirHp), maxBase)

	local maxMana = currentState.maxMana or BattleGridConfig.MAX_MANA
	local myMana = if side == "A" then (currentState.manaA or 0) else (currentState.manaB or 0)
	manaLabel.Visible = true
	manaLabel.Text = string.format("MANA: %.1f / %d  — tap fish, then grid to summon", myMana, maxMana)
end

local function updateHud()
	if not currentState then
		return
	end
	local side = currentState.localSide
	local myLayout = if side == "A" then currentState.layoutA else currentState.layoutB
	local myInfo = if side == "A" then currentState.playerA else currentState.playerB

	if currentState.phase == "combat" then
		timerLabel.Text = "BATTLE — push fish to enemy side!"
		placedLabel.Visible = false
		readyButton.Visible = false
		updateCombatStats()
		refreshGrid()
		renderCollection()
		return
	end

	placedLabel.Visible = true
	readyButton.Visible = true
	placedLabel.Text = string.format("UNITS PLACED: %d / %d", #myLayout, BattleGridConfig.MAX_UNITS_PER_SIDE)

	if BattleGridConfig.PLACEMENT_TIMER_ENABLED then
		local remaining = math.max(0, currentState.placementEndServerTime - Workspace:GetServerTimeNow())
		timerLabel.Text = string.format("PLACEMENT PHASE  %.0fs", remaining)
	else
		timerLabel.Text = "PLACEMENT PHASE"
	end

	readyButton.Text = if myInfo.ready then "WAITING..." else "READY"
	readyButton.Active = not myInfo.ready and currentState.phase == "placement"
	updateCombatStats()
	refreshGrid()
	renderEnemyPanel()
	renderCollection()
end

local function updatePlacementTimerOnly()
	if not currentState or currentState.phase ~= "placement" or not timerLabel then
		return
	end
	if BattleGridConfig.PLACEMENT_TIMER_ENABLED then
		local remaining = math.max(0, currentState.placementEndServerTime - Workspace:GetServerTimeNow())
		timerLabel.Text = string.format("PLACEMENT PHASE  %.0fs", remaining)
	end
end

local function startTimerLoop()
	if timerConnection then
		timerConnection:Disconnect()
		timerConnection = nil
	end
	if not BattleGridConfig.PLACEMENT_TIMER_ENABLED then
		return
	end
	timerConnection = RunService.Heartbeat:Connect(function()
		if screenGui and screenGui.Enabled and currentState and currentState.phase == "placement" then
			updatePlacementTimerOnly()
		end
	end)
end

function M.applyOwnedSnapshot(snapshot: unknown)
	ownedByImageId = {}
	if typeof(snapshot) == "table" then
		local raw = snapshot :: { [string]: any }
		local mapData = raw[BattleGridConfig.MAP_ID]
		if typeof(mapData) == "table" then
			for imageId, count in mapData do
				if typeof(imageId) == "string" and typeof(count) == "number" and count > 0 then
					ownedByImageId[imageId] = math.floor(count)
				end
			end
		end
	end
	if screenGui and screenGui.Enabled then
		task.defer(renderCollection)
	end
end

local function clearCombatVisualsFromGrid()
	if not gridHost then
		return
	end
	for _, child in gridHost:GetChildren() do
		if child == combatOverlay then
			for _, overlayChild in combatOverlay:GetChildren() do
				overlayChild:Destroy()
			end
		elseif child:IsA("TextButton") then
			local art = child:FindFirstChild("UnitArt")
			if art then
				art:Destroy()
			end
		elseif child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function M.open(state: BattlePlacementStatePayload)
	buildUi()
	clearCombatVisualsFromGrid()
	currentState = state
	syncPlacementOnFieldFromState()
	seedOwnedFromInventory()
	screenGui.Enabled = true
	LobbyTouchInputSuppress.setHolder("battle-placement", true)
	LobbyModalInputBlock.setLobbyHubBlocked("battle-placement", true)
	layoutHud()
	scheduleLayoutUntilReady()
	updateHud()
	refreshGrid()
	startTimerLoop()
end

function M.update(state: BattlePlacementStatePayload)
	local wasCombat = currentState ~= nil and currentState.phase == "combat"
	currentState = state
	if wasCombat and state.phase ~= "combat" then
		M.exitCombatView()
	end
	if state.phase == "placement" then
		syncPlacementOnFieldFromState()
	elseif state.phase ~= "combat" then
		table.clear(placementOnFieldImageIds)
	end
	if state.phase ~= "combat" then
		table.clear(combatFieldImageIds)
	elseif not wasCombat then
		table.clear(combatFieldImageIds)
		local side = state.localSide
		local layout = if side == "A" then state.layoutA else state.layoutB
		for _, unit in layout do
			combatFieldImageIds[unit.imageId] = true
		end
	end
	if screenGui and screenGui.Enabled then
		updateHud()
	end
end

function M.syncCombatFieldUnits(units: { CombatUnitSnapshot })
	table.clear(combatFieldImageIds)
	if not currentState then
		return
	end
	local side = currentState.localSide
	for _, unit in units do
		if unit.side == side and unit.hp > 0 then
			combatFieldImageIds[unit.imageId] = true
		end
	end
	if screenGui and screenGui.Enabled then
		renderCollection()
	end
end

export type GridLayoutInfo = {
	gridHost: Frame,
	combatOverlay: Frame,
	cellSize: number,
	pad: number,
}

function M.getGridLayout(): GridLayoutInfo?
	if not gridHost or not combatOverlay then
		return nil
	end
	layoutGridCells()
	return {
		gridHost = gridHost,
		combatOverlay = combatOverlay,
		cellSize = currentCellSize,
		pad = currentGridPad,
	}
end

function M.cellTopLeft(col: number, row: number): (number, number)
	return BattleGridProjection.cellTopLeft(col, row, currentLayoutMetrics)
end

function M.cellCenterOffset(col: number, row: number): (number, number)
	return BattleGridProjection.cellCenterOffset(col, row, currentLayoutMetrics)
end

function M.cellSizeAt(col: number, row: number): number
	return BattleGridProjection.cellSizeAt(col, row, currentLayoutMetrics)
end

function M.cellDepth(col: number, row: number): number
	return BattleGridProjection.cellDepth(col, row, BattleGridConfig.COLS)
end

function M.cellZIndex(baseZ: number, col: number, row: number): number
	return BattleGridProjection.cellZIndex(baseZ, col, row, BattleGridConfig.COLS)
end

function M.enterCombatView()
	hidePlacementArt = true
	if rightPanel then
		rightPanel.Visible = false
	end
	if readyButton then
		readyButton.Visible = false
	end
	if placedLabel then
		placedLabel.Visible = false
	end
	if leftPanel then
		leftPanel.Visible = true
	end
	updateCombatStats()
	refreshGrid()
	renderCollection()
end

function M.updateBaseHp(baseHpA: number, baseHpB: number)
	if not currentState then
		return
	end
	currentState.baseHpA = baseHpA
	currentState.baseHpB = baseHpB
	updateCombatStats()
end

function M.updateMana(manaA: number, manaB: number)
	if not currentState then
		return
	end
	currentState.manaA = manaA
	currentState.manaB = manaB
	updateCombatStats()
end

function M.clearCombatVisuals()
	clearCombatVisualsFromGrid()
end

function M.exitCombatView()
	hidePlacementArt = false
	if leftPanel then
		leftPanel.Visible = true
	end
	if rightPanel then
		rightPanel.Visible = true
	end
	if readyButton then
		readyButton.Visible = true
	end
	if placedLabel then
		placedLabel.Visible = true
	end
	clearCombatVisualsFromGrid()
end

function M.getCurrentState(): BattlePlacementStatePayload?
	return currentState
end

function M.close()
	layoutRetryToken += 1
	M.exitCombatView()
	if timerConnection then
		timerConnection:Disconnect()
		timerConnection = nil
	end
	if screenGui then
		screenGui.Enabled = false
	end
	LobbyTouchInputSuppress.setHolder("battle-placement", false)
	LobbyModalInputBlock.setLobbyHubBlocked("battle-placement", false)
	currentState = nil
	selectedImageId = nil
	table.clear(combatFieldImageIds)
	table.clear(placementOnFieldImageIds)
	if onCloseCallback then
		onCloseCallback()
	end
end

function M.setOnClose(callback: () -> ())
	onCloseCallback = callback
end

function M.isOpen(): boolean
	return screenGui ~= nil and screenGui.Enabled
end

return M
