--!strict
-- Row-based territories: Side B (red) top rows, Side A (blue) bottom rows.

local BattleGridConfig = require(script.Parent:WaitForChild("BattleGridConfig"))
local BattleLayoutTypes = require(script.Parent:WaitForChild("BattleLayoutTypes"))

type BattleSide = BattleLayoutTypes.BattleSide

local M = {}

function M.cellInSide(col: number, row: number, side: BattleSide): boolean
	if col < 0 or col >= BattleGridConfig.COLS or row < 0 or row >= BattleGridConfig.ROWS then
		return false
	end
	if side == "A" then
		return row >= BattleGridConfig.SIDE_A_MIN_ROW
	end
	return row <= BattleGridConfig.SIDE_B_MAX_ROW
end

function M.sideForCell(_col: number, row: number): BattleSide
	if row >= BattleGridConfig.SIDE_A_MIN_ROW then
		return "A"
	end
	return "B"
end

-- Far edge row only (not midline deployment rows). Blue marches to 0, red to ROWS-1.
function M.enemyLastRow(attackerSide: BattleSide): number
	if attackerSide == "A" then
		return BattleGridConfig.SIDE_B_BASE_ROW
	end
	return BattleGridConfig.SIDE_A_BASE_ROW
end

function M.isMidlineRow(row: number): boolean
	return row == BattleGridConfig.SIDE_B_MAX_ROW or row == BattleGridConfig.SIDE_A_MIN_ROW
end

function M.enemyBaseRow(side: BattleSide): number
	return M.enemyLastRow(side)
end

function M.isOnEnemyLastRow(row: number, attackerSide: BattleSide): boolean
	return row == M.enemyLastRow(attackerSide)
end

function M.isOnEnemyBaseRow(row: number, attackerSide: BattleSide): boolean
	return M.isOnEnemyLastRow(row, attackerSide)
end

function M.canDealBaseDamage(col: number, row: number, attackerSide: BattleSide): boolean
	local lastRow = M.enemyLastRow(attackerSide)
	if row ~= lastRow or M.isMidlineRow(row) then
		return false
	end
	local victim = if attackerSide == "A" then "B" else "A"
	return M.cellInSide(col, row, victim)
end

function M.deploymentCellsForSide(side: BattleSide): { { col: number, row: number } }
	local cells: { { col: number, row: number } } = {}
	if side == "A" then
		for row = BattleGridConfig.SIDE_A_MIN_ROW, BattleGridConfig.ROWS - 1 do
			for col = 0, BattleGridConfig.COLS - 1 do
				if M.cellInSide(col, row, side) then
					table.insert(cells, { col = col, row = row })
				end
			end
		end
	else
		for row = BattleGridConfig.SIDE_B_MAX_ROW, 0, -1 do
			for col = 0, BattleGridConfig.COLS - 1 do
				if M.cellInSide(col, row, side) then
					table.insert(cells, { col = col, row = row })
				end
			end
		end
	end
	return cells
end

function M.countCellsForSide(side: BattleSide): number
	return #M.deploymentCellsForSide(side)
end

function M.maxUnitsForSide(side: BattleSide): number
	return M.countCellsForSide(side)
end

return M
