--!strict
-- Maps logical grid (col, row) to 2D screen positions for top-down or perspective square grids.

local BattleGridConfig = require(script.Parent:WaitForChild("BattleGridConfig"))
local BattleUiConfig = require(script.Parent:WaitForChild("BattleUiConfig"))

export type LayoutMetrics = {
	cellSize: number,
	pad: number,
	originX: number,
	originY: number,
	gridW: number,
	gridH: number,
	cols: number,
	rows: number,
}

local M = {}

function M.isPerspective(): boolean
	return BattleUiConfig.GRID_PROJECTION == "perspective"
end

function M.cellDepth(col: number, row: number, cols: number?): number
	if cols then
		return row * cols + col
	end
	return row * BattleGridConfig.COLS + col
end

function M.cellZIndex(baseZ: number, col: number, row: number, cols: number?): number
	return baseZ + M.cellDepth(col, row, cols)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function rowDepthT(row: number, rows: number): number
	if rows <= 1 then
		return 1
	end
	return row / (rows - 1)
end

function M.cellScaleAtRow(row: number, rows: number): number
	if not M.isPerspective() then
		return 1
	end
	local t = rowDepthT(row, rows)
	return lerp(BattleUiConfig.PERSPECTIVE_BACK_CELL_SCALE, 1, t)
end

function M.cellSizeAt(col: number, row: number, metrics: LayoutMetrics): number
	local scale = M.cellScaleAtRow(row, metrics.rows)
	return metrics.cellSize * scale
end

local function rowWidthAtRow(row: number, rows: number, frontRowWidth: number): number
	if not M.isPerspective() then
		return frontRowWidth
	end
	local t = rowDepthT(row, rows)
	return frontRowWidth * lerp(BattleUiConfig.PERSPECTIVE_TOP_WIDTH_RATIO, 1, t)
end

local function rowGap(pad: number): number
	if M.isPerspective() then
		return BattleUiConfig.PERSPECTIVE_ROW_PAD
	end
	return pad
end

local function rowCentersY(rows: number, frontCell: number, pad: number): { number }
	local centers: { number } = {}
	local gap = rowGap(pad)
	local y = pad
	for row = 0, rows - 1 do
		local cell = frontCell * M.cellScaleAtRow(row, rows)
		y += cell * 0.5
		centers[row + 1] = y
		y += cell * 0.5 + gap
	end
	return centers
end

local function cellCenterRaw(col: number, row: number, metrics: LayoutMetrics): (number, number)
	local cell = metrics.cellSize
	local pad = metrics.pad
	local cols = metrics.cols
	local rows = metrics.rows

	if not M.isPerspective() then
		local x = pad + col * (cell + pad) + cell * 0.5
		local y = pad + row * (cell + pad) + cell * 0.5
		return x, y
	end

	local frontRowWidth = cols * cell + (cols - 1) * pad
	local rowWidth = rowWidthAtRow(row, rows, frontRowWidth)
	local rowCenters = rowCentersY(rows, cell, pad)
	local cy = rowCenters[row + 1]
	local cx = pad + (col + 0.5) / cols * rowWidth + (frontRowWidth - rowWidth) * 0.5
	return cx, cy
end

local function cellBounds(col: number, row: number, metrics: LayoutMetrics): (number, number, number, number)
	local cx, cy = cellCenterRaw(col, row, metrics)
	local half = M.cellSizeAt(col, row, metrics) * 0.5
	return cx - half, cy - half, cx + half, cy + half
end

function M.estimateGridSize(cols: number, rows: number, cell: number, pad: number): (number, number)
	if not M.isPerspective() then
		return cols * (cell + pad) + pad, rows * (cell + pad) + pad
	end

	local metrics: LayoutMetrics = {
		cellSize = cell,
		pad = pad,
		originX = 0,
		originY = 0,
		gridW = 0,
		gridH = 0,
		cols = cols,
		rows = rows,
	}

	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			local x0, y0, x1, y1 = cellBounds(c, r, metrics)
			minX = math.min(minX, x0)
			maxX = math.max(maxX, x1)
			minY = math.min(minY, y0)
			maxY = math.max(maxY, y1)
		end
	end
	return maxX - minX + pad * 2, maxY - minY + pad * 2
end

function M.resolveCellSize(
	availX: number,
	availY: number,
	cols: number,
	rows: number,
	minCell: number,
	maxCell: number,
	pad: number
): number
	if not M.isPerspective() then
		local cellFromW = math.floor((availX - pad * (cols + 1)) / cols)
		local cellFromH = math.floor((availY - pad * (rows + 1)) / rows)
		return math.clamp(math.min(cellFromW, cellFromH), minCell, maxCell)
	end

	for cell = maxCell, minCell, -1 do
		local gridW, gridH = M.estimateGridSize(cols, rows, cell, pad)
		if gridW <= availX and gridH <= availY then
			return cell
		end
	end
	return minCell
end

function M.computeLayoutMetrics(cell: number, pad: number, cols: number, rows: number): LayoutMetrics
	if not M.isPerspective() then
		local gridW = cols * (cell + pad) + pad
		local gridH = rows * (cell + pad) + pad
		return {
			cellSize = cell,
			pad = pad,
			originX = 0,
			originY = 0,
			gridW = gridW,
			gridH = gridH,
			cols = cols,
			rows = rows,
		}
	end

	local metrics: LayoutMetrics = {
		cellSize = cell,
		pad = pad,
		originX = 0,
		originY = 0,
		gridW = 0,
		gridH = 0,
		cols = cols,
		rows = rows,
	}

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			local x0, y0, x1, y1 = cellBounds(c, r, metrics)
			minX = math.min(minX, x0)
			maxX = math.max(maxX, x1)
			minY = math.min(minY, y0)
			maxY = math.max(maxY, y1)
		end
	end

	return {
		cellSize = cell,
		pad = pad,
		originX = pad - minX,
		originY = pad - minY,
		gridW = maxX - minX + pad * 2,
		gridH = maxY - minY + pad * 2,
		cols = cols,
		rows = rows,
	}
end

function M.cellTopLeft(col: number, row: number, metrics: LayoutMetrics): (number, number)
	local cx, cy = cellCenterRaw(col, row, metrics)
	local half = M.cellSizeAt(col, row, metrics) * 0.5
	return cx - half + metrics.originX, cy - half + metrics.originY
end

function M.cellCenterOffset(col: number, row: number, metrics: LayoutMetrics): (number, number)
	local cx, cy = cellCenterRaw(col, row, metrics)
	return cx + metrics.originX, cy + metrics.originY
end

return M
