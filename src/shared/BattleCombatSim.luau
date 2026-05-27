--!strict
local SplashFishCatalog = require(script.Parent:WaitForChild("SplashFishCatalog"))
local BattleGridConfig = require(script.Parent:WaitForChild("BattleGridConfig"))
local BattleLayoutTypes = require(script.Parent:WaitForChild("BattleLayoutTypes"))
local BattleUnitStats = require(script.Parent:WaitForChild("BattleUnitStats"))

type BattleSide = BattleLayoutTypes.BattleSide
type PlacementUnit = BattleLayoutTypes.PlacementUnit
type SideLayout = BattleLayoutTypes.SideLayout
type BattleCombatEvent = BattleLayoutTypes.BattleCombatEvent

type SimUnit = {
	side: BattleSide,
	col: number,
	row: number,
	imageId: string,
	level: number,
	hp: number,
	maxHp: number,
	atk: number,
}

local LEVEL_MULT = { 1, 1.25, 1.5 }

local BattleCombatSim = {}

local function statsFromPlacedUnit(placed: PlacementUnit): (number, number, number)
	local tier = SplashFishCatalog.getTierForImageId(BattleGridConfig.MAP_ID, placed.imageId)
	local level = math.clamp(placed.level, 1, 3)
	local mult = LEVEL_MULT[level] or 1
	if not tier then
		return math.floor(60 * mult + 0.5), math.floor(8 * mult + 0.5), level
	end
	local baseHp, baseAtk = BattleUnitStats.getBaseStatsForTier(tier)
	return math.floor(baseHp * mult + 0.5), math.floor(baseAtk * mult + 0.5), level
end

function BattleCombatSim.buildUnitsFromLayout(side: BattleSide, layout: SideLayout): { SimUnit }
	local units: { SimUnit } = {}
	for _, placed in layout do
		local hp, atk, level = statsFromPlacedUnit(placed)
		table.insert(units, {
			side = side,
			col = placed.col,
			row = placed.row,
			imageId = placed.imageId,
			level = level,
			hp = hp,
			maxHp = hp,
			atk = atk,
		})
	end
	return units
end

local function manhattan(aCol: number, aRow: number, bCol: number, bRow: number): number
	return math.abs(aCol - bCol) + math.abs(aRow - bRow)
end

local function countLiving(units: { SimUnit }, side: BattleSide): number
	local n = 0
	for _, u in units do
		if u.side == side and u.hp > 0 then
			n += 1
		end
	end
	return n
end

local function findNearestTarget(attacker: SimUnit, units: { SimUnit }): SimUnit?
	local best: SimUnit? = nil
	local bestDist = math.huge
	for _, target in units do
		if target.side ~= attacker.side and target.hp > 0 then
			local dist = manhattan(attacker.col, attacker.row, target.col, target.row)
			if dist < bestDist then
				bestDist = dist
				best = target
			end
		end
	end
	return best
end

local function isCellOccupied(units: { SimUnit }, col: number, row: number, exclude: SimUnit?): boolean
	for _, u in units do
		if u.hp > 0 and u.col == col and u.row == row and u ~= exclude then
			return true
		end
	end
	return false
end

local function isInBounds(col: number, row: number): boolean
	return col >= 0 and col < BattleGridConfig.COLS and row >= 0 and row < BattleGridConfig.ROWS
end

local function tryMoveStep(
	attacker: SimUnit,
	target: SimUnit,
	units: { SimUnit }
): (boolean, number?, number?, number?, number?)
	local dc = target.col - attacker.col
	local dr = target.row - attacker.row
	local preferCol = math.abs(dc) >= math.abs(dr)

	local function attemptStep(useCol: boolean): (boolean, number?, number?, number?, number?)
		local newCol = attacker.col
		local newRow = attacker.row
		if useCol then
			if dc == 0 then
				return false
			end
			newCol += if dc > 0 then 1 else -1
		else
			if dr == 0 then
				return false
			end
			newRow += if dr > 0 then 1 else -1
		end
		if not isInBounds(newCol, newRow) then
			return false
		end
		if isCellOccupied(units, newCol, newRow, attacker) then
			return false
		end
		local fromCol, fromRow = attacker.col, attacker.row
		attacker.col = newCol
		attacker.row = newRow
		return true, fromCol, fromRow, newCol, newRow
	end

	local moved, fromCol, fromRow, toCol, toRow = attemptStep(preferCol)
	if moved then
		return true, fromCol, fromRow, toCol, toRow
	end
	return attemptStep(not preferCol)
end

function BattleCombatSim.simulate(
	layoutA: SideLayout,
	layoutB: SideLayout,
	_seed: number
): (BattleSide?, { BattleCombatEvent })
	local units: { SimUnit } = {}
	for _, u in BattleCombatSim.buildUnitsFromLayout("A", layoutA) do
		table.insert(units, u)
	end
	for _, u in BattleCombatSim.buildUnitsFromLayout("B", layoutB) do
		table.insert(units, u)
	end

	local eventLog: { BattleCombatEvent } = {}
	if #units == 0 then
		return nil, eventLog
	end

	local attackRange = BattleGridConfig.ATTACK_RANGE

	for tick = 1, BattleGridConfig.MAX_COMBAT_TICKS do
		if countLiving(units, "A") == 0 and countLiving(units, "B") == 0 then
			return nil, eventLog
		end
		if countLiving(units, "A") == 0 then
			return "B", eventLog
		end
		if countLiving(units, "B") == 0 then
			return "A", eventLog
		end

		local order: { SimUnit } = {}
		for _, u in units do
			if u.hp > 0 then
				table.insert(order, u)
			end
		end
		table.sort(order, function(a, b)
			if a.side ~= b.side then
				return a.side == "A"
			end
			if a.row ~= b.row then
				return a.row < b.row
			end
			return a.col < b.col
		end)

		for _, attacker in order do
			if attacker.hp <= 0 then
				continue
			end
			local target = findNearestTarget(attacker, units)
			if not target then
				continue
			end

			local dist = manhattan(attacker.col, attacker.row, target.col, target.row)

			if dist <= attackRange then
				local damage = attacker.atk
				target.hp = math.max(0, target.hp - damage)
				table.insert(eventLog, {
					kind = "attack",
					tick = tick,
					attackerSide = attacker.side,
					attackerCol = attacker.col,
					attackerRow = attacker.row,
					targetCol = target.col,
					targetRow = target.row,
					damage = damage,
					targetHpAfter = target.hp,
				})
				if countLiving(units, "A") == 0 then
					return "B", eventLog
				end
				if countLiving(units, "B") == 0 then
					return "A", eventLog
				end
			elseif dist > attackRange then
				for _ = 1, BattleGridConfig.MOVE_STEPS_PER_TICK do
					local moved, fromCol, fromRow, toCol, toRow = tryMoveStep(attacker, target, units)
					if not moved then
						break
					end
					table.insert(eventLog, {
						kind = "move",
						tick = tick,
						side = attacker.side,
						fromCol = fromCol,
						fromRow = fromRow,
						toCol = toCol,
						toRow = toRow,
					})
					if manhattan(attacker.col, attacker.row, target.col, target.row) <= attackRange then
						break
					end
				end
			end
		end
	end

	local hpA, hpB = 0, 0
	for _, u in units do
		if u.hp > 0 then
			if u.side == "A" then
				hpA += u.hp
			else
				hpB += u.hp
			end
		end
	end
	if hpA > hpB then
		return "A", eventLog
	elseif hpB > hpA then
		return "B", eventLog
	end
	return nil, eventLog
end

return BattleCombatSim
