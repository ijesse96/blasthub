--!strict
-- Column territories: Side A (blue) west cols, Side B (red) east cols.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local rsShared = ReplicatedStorage:WaitForChild("Shared")
local BattleGridConfig = require(script.Parent:WaitForChild("BattleGridConfig"))
local BattleLayoutTypes = require(rsShared:WaitForChild("BattleLayoutTypes"))

type BattleSide = BattleLayoutTypes.BattleSide

local M = {}

function M.cellInSide(col: number, row: number, side: BattleSide): boolean
	if col < 0 or col >= BattleGridConfig.COLS or row < 0 or row >= BattleGridConfig.ROWS then
		return false
	end
	local split = BattleGridConfig.SIDE_SPLIT_COL
	if side == "A" then
		return col < split
	end
	return col >= split
end

function M.sideForCell(col: number, _row: number): BattleSide
	if col >= BattleGridConfig.SIDE_SPLIT_COL then
		return "B"
	end
	return "A"
end

function M.enemyLastCol(attackerSide: BattleSide): number
	if attackerSide == "A" then
		return BattleGridConfig.COLS - 1
	end
	return 0
end

function M.enemyLastRow(_attackerSide: BattleSide): number
	return 0
end

function M.enemyBaseRow(_side: BattleSide): number
	return math.floor(BattleGridConfig.ROWS / 2)
end

function M.isMidlineRow(_row: number): boolean
	return false
end

function M.isOnEnemyLastRow(_row: number, _attackerSide: BattleSide): boolean
	return false
end

function M.isOnEnemyBaseRow(_row: number, _attackerSide: BattleSide): boolean
	return false
end

function M.canDealBaseDamage(col: number, row: number, attackerSide: BattleSide): boolean
	if col ~= M.enemyLastCol(attackerSide) then
		return false
	end
	local victim: BattleSide = if attackerSide == "A" then "B" else "A"
	return M.cellInSide(col, row, victim)
end

return M
