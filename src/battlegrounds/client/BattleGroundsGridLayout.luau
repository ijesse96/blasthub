--!strict
local BattleGroundsUiConfig = require(script.Parent:WaitForChild("BattleGroundsUiConfig"))

export type LayoutMetrics = {
	cellSize: number,
	cols: number,
	rows: number,
	gridW: number,
	gridH: number,
	splitCol: number,
}

local M = {}

function M.getSplitCol(): number
	return BattleGroundsUiConfig.SIDE_SPLIT_COL
end

function M.computeMetrics(viewportW: number, viewportH: number): LayoutMetrics
	local rows = BattleGroundsUiConfig.ROWS
	local cols = BattleGroundsUiConfig.COLS
	local cellSize = math.max(1, math.min(math.floor(viewportW / cols), math.floor(viewportH / rows)))
	local gridW = cols * cellSize
	local gridH = rows * cellSize
	return {
		cellSize = cellSize,
		cols = cols,
		rows = rows,
		gridW = gridW,
		gridH = gridH,
		splitCol = BattleGroundsUiConfig.SIDE_SPLIT_COL,
	}
end

function M.cellTopLeft(col: number, row: number, metrics: LayoutMetrics): (number, number)
	return col * metrics.cellSize, row * metrics.cellSize
end

function M.cellCenterOffset(col: number, row: number, metrics: LayoutMetrics): (number, number)
	local x, y = M.cellTopLeft(col, row, metrics)
	local half = metrics.cellSize * 0.5
	return x + half, y + half
end

function M.cellSizeAt(_col: number, _row: number, metrics: LayoutMetrics): number
	return metrics.cellSize
end

return M
