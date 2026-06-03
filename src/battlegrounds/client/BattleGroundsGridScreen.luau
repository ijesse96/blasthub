--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BattleGroundsGridLayout = require(script.Parent:WaitForChild("BattleGroundsGridLayout"))
local BattleGroundsUiConfig = require(script.Parent:WaitForChild("BattleGroundsUiConfig"))

type LayoutMetrics = BattleGroundsGridLayout.LayoutMetrics

export type GridLayoutInfo = {
	gridHost: Frame,
	combatOverlay: Frame,
	cellSize: number,
	pad: number,
	cellCenterOffset: (number, number) -> (number, number),
	cellTopLeft: (number, number) -> (number, number),
	cellSizeAt: (number, number) -> number,
}

local SCREEN_GUI_NAME = "BattleScene"

local didMount = false
local screenGui: ScreenGui? = nil
local gridRoot: Frame? = nil
local gridHost: Frame? = nil
local combatOverlay: Frame? = nil
local layoutMetrics: LayoutMetrics? = nil
local cellFrames: { [string]: Frame } = {}
local resizeConnection: RBXScriptConnection? = nil
local viewportConnection: RBXScriptConnection? = nil
local layoutRetryToken = 0

local M = {}

local function cellKey(col: number, row: number): string
	return tostring(col) .. "_" .. tostring(row)
end

local function strokeColorForCol(col: number, splitCol: number): Color3
	if col < splitCol then
		return BattleGroundsUiConfig.SIDE_A_STROKE_COLOR
	end
	return BattleGroundsUiConfig.SIDE_B_STROKE_COLOR
end

local function makeCell(col: number, row: number, metrics: LayoutMetrics): Frame
	local x, y = BattleGroundsGridLayout.cellTopLeft(col, row, metrics)
	local size = metrics.cellSize

	local cell = Instance.new("Frame")
	cell.Name = "Cell_" .. cellKey(col, row)
	cell.Size = UDim2.fromOffset(size, size)
	cell.Position = UDim2.fromOffset(x, y)
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.ZIndex = 1

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Border"
	stroke.Color = strokeColorForCol(col, metrics.splitCol)
	stroke.Transparency = BattleGroundsUiConfig.CELL_STROKE_TRANSPARENCY
	stroke.Thickness = BattleGroundsUiConfig.CELL_STROKE_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = cell

	return cell
end

local function buildBackground(parent: Instance)
	local backgroundLayer = Instance.new("Frame")
	backgroundLayer.Name = "BackgroundLayer"
	backgroundLayer.Size = UDim2.fromScale(1, 1)
	backgroundLayer.BackgroundTransparency = 1
	backgroundLayer.BorderSizePixel = 0
	backgroundLayer.ZIndex = BattleGroundsUiConfig.Z_BACKGROUND
	backgroundLayer.Parent = parent

	local bgImage = Instance.new("ImageLabel")
	bgImage.Name = "BgImage"
	bgImage.Size = UDim2.fromScale(1, 1)
	bgImage.BorderSizePixel = 0
	bgImage.ScaleType = Enum.ScaleType.Crop
	bgImage.ZIndex = BattleGroundsUiConfig.Z_BACKGROUND
	bgImage.Parent = backgroundLayer

	if BattleGroundsUiConfig.BACKGROUND_IMAGE ~= "" then
		bgImage.Image = BattleGroundsUiConfig.BACKGROUND_IMAGE
		bgImage.BackgroundColor3 = BattleGroundsUiConfig.BACKGROUND_FALLBACK_COLOR
		bgImage.BackgroundTransparency = 0.15
	else
		bgImage.Image = ""
		bgImage.BackgroundColor3 = BattleGroundsUiConfig.BACKGROUND_FALLBACK_COLOR
		bgImage.BackgroundTransparency = 0
	end
end

local function getViewportSize(): Vector2
	local gui = screenGui
	if gui then
		local guiSize = gui.AbsoluteSize
		if guiSize.X >= 8 and guiSize.Y >= 8 then
			return guiSize
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function clearGrid()
	for _, cell in cellFrames do
		cell:Destroy()
	end
	table.clear(cellFrames)
end

local function layoutGrid()
	local root = gridRoot
	local host = gridHost
	local overlay = combatOverlay
	local gui = screenGui
	if not root or not host or not overlay or not gui then
		return false
	end

	local viewport = getViewportSize()
	if viewport.X < 8 or viewport.Y < 8 then
		return false
	end

	local metrics = BattleGroundsGridLayout.computeMetrics(viewport.X, viewport.Y)
	layoutMetrics = metrics

	clearGrid()

	local gridW = metrics.gridW
	local gridH = metrics.gridH
	local offsetX = math.floor((viewport.X - gridW) * 0.5)
	local offsetY = math.floor((viewport.Y - gridH) * 0.5)

	host.Size = UDim2.fromOffset(gridW, gridH)
	host.Position = UDim2.fromOffset(offsetX, offsetY)
	overlay.Size = UDim2.fromOffset(gridW, gridH)
	overlay.Position = UDim2.fromOffset(offsetX, offsetY)
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromScale(0, 0)
	root.AnchorPoint = Vector2.new(0, 0)

	for row = 0, metrics.rows - 1 do
		for col = 0, metrics.cols - 1 do
			local cell = makeCell(col, row, metrics)
			cell.Parent = host
			cellFrames[cellKey(col, row)] = cell
		end
	end
	return true
end

local function scheduleLayoutUntilReady()
	layoutRetryToken += 1
	local token = layoutRetryToken
	task.spawn(function()
		for _ = 1, 30 do
			if token ~= layoutRetryToken then
				return
			end
			if not screenGui or not screenGui.Enabled then
				return
			end
			if layoutGrid() then
				return
			end
			RunService.Heartbeat:Wait()
		end
		layoutGrid()
	end)
end

function M.ensureBattleLayout()
	M.mount()
	if not layoutMetrics then
		layoutGrid()
	end
end

function M.getLayoutMetrics(): LayoutMetrics?
	return layoutMetrics
end

function M.cellCenterOffset(col: number, row: number)
	if not layoutMetrics then
		return nil
	end
	return BattleGroundsGridLayout.cellCenterOffset(col, row, layoutMetrics)
end

function M.cellTopLeft(col: number, row: number)
	if not layoutMetrics then
		return nil
	end
	return BattleGroundsGridLayout.cellTopLeft(col, row, layoutMetrics)
end

function M.cellSizeAt(_col: number, _row: number): number
	if not layoutMetrics then
		return 32
	end
	return layoutMetrics.cellSize
end

function M.getGridLayout(): GridLayoutInfo?
	local metrics = layoutMetrics
	if not gridHost or not combatOverlay or not metrics then
		return nil
	end
	return {
		gridHost = gridHost,
		combatOverlay = combatOverlay,
		cellSize = metrics.cellSize,
		pad = 0,
		cellCenterOffset = function(col: number, row: number): (number, number)
			return BattleGroundsGridLayout.cellCenterOffset(col, row, metrics)
		end,
		cellTopLeft = function(col: number, row: number): (number, number)
			return BattleGroundsGridLayout.cellTopLeft(col, row, metrics)
		end,
		cellSizeAt = function(_col: number, _row: number): number
			return metrics.cellSize
		end,
	}
end

function M.mount()
	if didMount then
		layoutGrid()
		return
	end
	didMount = true

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = SCREEN_GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Enabled = true
	gui.Parent = playerGui
	screenGui = gui

	buildBackground(gui)

	local root = Instance.new("Frame")
	root.Name = "GridRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = BattleGroundsUiConfig.Z_GRID
	root.Parent = gui
	gridRoot = root

	local host = Instance.new("Frame")
	host.Name = "GridHost"
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.ClipsDescendants = false
	host.ZIndex = BattleGroundsUiConfig.Z_GRID
	host.Parent = root
	gridHost = host

	local overlay = Instance.new("Frame")
	overlay.Name = "CombatOverlay"
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ClipsDescendants = false
	overlay.Active = false
	overlay.ZIndex = BattleGroundsUiConfig.Z_COMBAT
	overlay.Parent = root
	combatOverlay = overlay

	if resizeConnection then
		resizeConnection:Disconnect()
	end
	resizeConnection = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid)

	local camera = workspace.CurrentCamera
	if camera then
		if viewportConnection then
			viewportConnection:Disconnect()
		end
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutGrid)
	end

	scheduleLayoutUntilReady()
end

return M
