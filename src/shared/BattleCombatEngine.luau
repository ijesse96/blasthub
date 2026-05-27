--!strict
local RunService = game:GetService("RunService")
local BattleGridConfig = require(script.Parent:WaitForChild("BattleGridConfig"))
local BattleGridSides = require(script.Parent:WaitForChild("BattleGridSides"))
local BattleLayoutTypes = require(script.Parent:WaitForChild("BattleLayoutTypes"))
local BattleUnitStats = require(script.Parent:WaitForChild("BattleUnitStats"))
type BattleSide = BattleLayoutTypes.BattleSide
type SideLayout = BattleLayoutTypes.SideLayout
type PlacementUnit = BattleLayoutTypes.PlacementUnit
type BattleCombatEvent = BattleLayoutTypes.BattleCombatEvent
type CombatUnitSnapshot = BattleLayoutTypes.CombatUnitSnapshot

export type CombatUnit = {
	uid: number,
	side: BattleSide,
	col: number,
	row: number,
	imageId: string,
	level: number,
	hp: number,
	maxHp: number,
	atk: number,
}

export type PendingSummon = {
	side: BattleSide,
	col: number,
	row: number,
	imageId: string,
	level: number,
	manaCost: number,
}

export type CombatState = {
	tick: number,
	units: { CombatUnit },
	uidCounter: number,
	baseHpA: number,
	baseHpB: number,
	manaA: number,
	manaB: number,
	pendingSummons: { PendingSummon },
}

local BattleCombatEngine = {}

-- Bump when changing base-damage rules; printed at combat start so Studio sync can be verified.
BattleCombatEngine.COMBAT_RULES_VERSION = "base-last-row-v5"

local function manhattan(aCol: number, aRow: number, bCol: number, bRow: number): number
	return math.abs(aCol - bCol) + math.abs(aRow - bRow)
end

local function isInBounds(col: number, row: number): boolean
	return col >= 0 and col < BattleGridConfig.COLS and row >= 0 and row < BattleGridConfig.ROWS
end

local function victimSideFor(side: BattleSide): BattleSide
	return if side == "A" then "B" else "A"
end

local function statsFromPlaced(placed: PlacementUnit): (number, number, number)
	return BattleUnitStats.getStatsForFish(BattleGridConfig.MAP_ID, placed.imageId, placed.level)
end

local function countLivingOnSide(state: CombatState, side: BattleSide): number
	local n = 0
	for _, u in state.units do
		if u.side == side and u.hp > 0 then
			n += 1
		end
	end
	return n
end

local function countPresentOnSide(state: CombatState, side: BattleSide): number
	local n = countLivingOnSide(state, side)
	for _, p in state.pendingSummons do
		if p.side == side then
			n += 1
		end
	end
	return n
end

local function hasLivingEnemy(state: CombatState, side: BattleSide): boolean
	local enemySide = victimSideFor(side)
	if countLivingOnSide(state, enemySide) > 0 then
		return true
	end
	for _, p in state.pendingSummons do
		if p.side == enemySide then
			return true
		end
	end
	return false
end

local function enemyHadUnitsAtTickStart(livingAtTickStart: { [BattleSide]: number }, side: BattleSide): boolean
	return livingAtTickStart[victimSideFor(side)] > 0
end

local function countOnField(state: CombatState, side: BattleSide): number
	local n = countLivingOnSide(state, side)
	for _, p in state.pendingSummons do
		if p.side == side then
			n += 1
		end
	end
	return n
end

local function isCellOccupied(state: CombatState, col: number, row: number, excludeUid: number?): boolean
	for _, u in state.units do
		if u.hp > 0 and u.col == col and u.row == row and u.uid ~= excludeUid then
			return true
		end
	end
	for _, p in state.pendingSummons do
		if p.col == col and p.row == row then
			return true
		end
	end
	return false
end

local function hasImageOnField(state: CombatState, side: BattleSide, imageId: string): boolean
	for _, u in state.units do
		if u.side == side and u.hp > 0 and u.imageId == imageId then
			return true
		end
	end
	for _, p in state.pendingSummons do
		if p.side == side and p.imageId == imageId then
			return true
		end
	end
	return false
end

local function findNearestTarget(attacker: CombatUnit, units: { CombatUnit }): CombatUnit?
	local best: CombatUnit? = nil
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

local function tryMoveStepToward(
	attacker: CombatUnit,
	goalCol: number,
	goalRow: number,
	units: { CombatUnit },
	preferColFirst: boolean?
): (boolean, number?, number?, number?, number?)
	local dc = goalCol - attacker.col
	local dr = goalRow - attacker.row
	local preferCol = if preferColFirst ~= nil then preferColFirst else math.abs(dc) >= math.abs(dr)

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
		for _, u in units do
			if u.hp > 0 and u.col == newCol and u.row == newRow and u.uid ~= attacker.uid then
				return false
			end
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

local function tryMoveStep(attacker: CombatUnit, target: CombatUnit, units: { CombatUnit }): (boolean, number?, number?, number?, number?)
	return tryMoveStepToward(attacker, target.col, target.row, units, nil)
end

local function checkWinner(state: CombatState): BattleSide?
	if state.baseHpA <= 0 and state.baseHpB <= 0 then
		return nil
	end
	if state.baseHpB <= 0 then
		return "A"
	end
	if state.baseHpA <= 0 then
		return "B"
	end
	return nil
end

local function enemyBackRow(attackerSide: BattleSide): number
	-- Hard-coded back edge rows (must match gold HUD rows 0 and 11).
	if attackerSide == "A" then
		return 0
	end
	return BattleGridConfig.ROWS - 1
end

local function unitMayDamageEnemyBase(unit: CombatUnit, state: CombatState): boolean
	if hasLivingEnemy(state, unit.side) then
		return false
	end
	if findNearestTarget(unit, state.units) ~= nil then
		return false
	end
	local backRow = enemyBackRow(unit.side)
	if unit.row ~= backRow then
		return false
	end
	return BattleGridSides.canDealBaseDamage(unit.col, unit.row, unit.side)
end

local function tryAttackEnemyBase(
	unit: CombatUnit,
	state: CombatState,
	tick: number,
	events: { BattleCombatEvent }
): BattleSide?
	if not unitMayDamageEnemyBase(unit, state) then
		return nil
	end

	local victim = victimSideFor(unit.side)
	if victim == "A" and state.baseHpA <= 0 then
		return nil
	end
	if victim == "B" and state.baseHpB <= 0 then
		return nil
	end

	local targetCol = unit.col
	local targetRow = enemyBackRow(unit.side)

	local damage = unit.atk
	local baseHpAfter = 0
	if victim == "A" then
		state.baseHpA = math.max(0, state.baseHpA - damage)
		baseHpAfter = state.baseHpA
	else
		state.baseHpB = math.max(0, state.baseHpB - damage)
		baseHpAfter = state.baseHpB
	end
	table.insert(events, {
		kind = "baseDamage",
		tick = tick,
		attackerSide = unit.side,
		attackerUid = unit.uid,
		attackerCol = unit.col,
		attackerRow = unit.row,
		targetCol = targetCol,
		targetRow = targetRow,
		victimSide = victim,
		damage = damage,
		baseHpAfter = baseHpAfter,
	})
	if RunService:IsStudio() then
		print(
			string.format(
				"[Battle] baseDamage %s unitRow=%d needRow=%d col=%d livingEnemy=%s",
				unit.side,
				unit.row,
				targetRow,
				unit.col,
				tostring(hasLivingEnemy(state, unit.side))
			)
		)
	end
	return checkWinner(state)
end

local function pursueEnemyBase(
	unit: CombatUnit,
	state: CombatState,
	tick: number,
	events: { BattleCombatEvent }
): BattleSide?
	if hasLivingEnemy(state, unit.side) or findNearestTarget(unit, state.units) ~= nil then
		return nil
	end

	local goalCol = unit.col
	local goalRow = enemyBackRow(unit.side)

	if unitMayDamageEnemyBase(unit, state) then
		return tryAttackEnemyBase(unit, state, tick, events)
	end

	for _ = 1, BattleGridConfig.MOVE_STEPS_PER_TICK do
		local moved, fromCol, fromRow, toCol, toRow = tryMoveStepToward(unit, goalCol, goalRow, state.units, false)
		if not moved then
			break
		end
		table.insert(events, {
			kind = "move",
			tick = tick,
			side = unit.side,
			fromCol = fromCol,
			fromRow = fromRow,
			toCol = toCol,
			toRow = toRow,
		})
		if unit.row == goalRow then
			break
		end
	end
	if unitMayDamageEnemyBase(unit, state) then
		return tryAttackEnemyBase(unit, state, tick, events)
	end
	return nil
end

local function addUnitFromPlaced(state: CombatState, side: BattleSide, placed: PlacementUnit)
	local hp, atk, level = statsFromPlaced(placed)
	state.uidCounter += 1
	table.insert(state.units, {
		uid = state.uidCounter,
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

function BattleCombatEngine.createState(layoutA: SideLayout, layoutB: SideLayout): CombatState
	local state: CombatState = {
		tick = 0,
		units = {},
		uidCounter = 0,
		baseHpA = BattleGridConfig.STARTING_BASE_HP,
		baseHpB = BattleGridConfig.STARTING_BASE_HP,
		manaA = BattleGridConfig.STARTING_MANA,
		manaB = BattleGridConfig.STARTING_MANA,
		pendingSummons = {},
	}
	for _, placed in layoutA do
		addUnitFromPlaced(state, "A", placed)
	end
	for _, placed in layoutB do
		addUnitFromPlaced(state, "B", placed)
	end
	return state
end

function BattleCombatEngine.getMana(state: CombatState, side: BattleSide): number
	if side == "A" then
		return state.manaA
	end
	return state.manaB
end

function BattleCombatEngine.buildUnitSnapshots(state: CombatState): { CombatUnitSnapshot }
	local out: { CombatUnitSnapshot } = {}
	for _, u in state.units do
		if u.hp > 0 then
			table.insert(out, {
				uid = u.uid,
				side = u.side,
				col = u.col,
				row = u.row,
				imageId = u.imageId,
				level = u.level,
				hp = u.hp,
				maxHp = u.maxHp,
			})
		end
	end
	return out
end

function BattleCombatEngine.tryQueueSummon(
	state: CombatState,
	side: BattleSide,
	imageId: string,
	col: number,
	row: number,
	level: number,
	manaCost: number
): boolean
	if not BattleGridSides.cellInSide(col, row, side) then
		return false
	end
	if isCellOccupied(state, col, row, nil) then
		return false
	end
	if hasImageOnField(state, side, imageId) then
		return false
	end
	if countOnField(state, side) >= BattleGridConfig.MAX_UNITS_ON_FIELD then
		return false
	end
	local mana = BattleCombatEngine.getMana(state, side)
	if mana < manaCost then
		return false
	end
	if side == "A" then
		state.manaA -= manaCost
	else
		state.manaB -= manaCost
	end
	table.insert(state.pendingSummons, {
		side = side,
		col = col,
		row = row,
		imageId = imageId,
		level = level,
		manaCost = manaCost,
	})
	return true
end

local function applyPendingSummons(state: CombatState, events: { BattleCombatEvent })
	local tick = state.tick
	local i = 1
	while i <= #state.pendingSummons do
		local p = state.pendingSummons[i]
		if isCellOccupied(state, p.col, p.row, nil) then
			if p.side == "A" then
				state.manaA += p.manaCost
			else
				state.manaB += p.manaCost
			end
			table.remove(state.pendingSummons, i)
			continue
		end
		local hp, atk, level = BattleUnitStats.getStatsForFish(BattleGridConfig.MAP_ID, p.imageId, p.level)
		state.uidCounter += 1
		local uid = state.uidCounter
		table.insert(state.units, {
			uid = uid,
			side = p.side,
			col = p.col,
			row = p.row,
			imageId = p.imageId,
			level = level,
			hp = hp,
			maxHp = hp,
			atk = atk,
		})
		table.insert(events, {
			kind = "summon",
			tick = tick,
			side = p.side,
			uid = uid,
			col = p.col,
			row = p.row,
			imageId = p.imageId,
			level = level,
			hp = hp,
			maxHp = hp,
		})
		table.remove(state.pendingSummons, i)
	end
end

local function regenMana(state: CombatState)
	state.manaA = math.min(BattleGridConfig.MAX_MANA, state.manaA + BattleGridConfig.MANA_REGEN_PER_TICK)
	state.manaB = math.min(BattleGridConfig.MAX_MANA, state.manaB + BattleGridConfig.MANA_REGEN_PER_TICK)
end

function BattleCombatEngine.step(state: CombatState): ({ BattleCombatEvent }, BattleSide?)
	local events: { BattleCombatEvent } = {}
	state.tick += 1
	local tick = state.tick

	regenMana(state)
	applyPendingSummons(state, events)

	local winner = checkWinner(state)
	if winner ~= nil or (state.baseHpA <= 0 and state.baseHpB <= 0) then
		return events, winner
	end

	local order: { CombatUnit } = {}
	for _, u in state.units do
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

	local livingAtTickStart: { [BattleSide]: number } = {
		A = countPresentOnSide(state, "A"),
		B = countPresentOnSide(state, "B"),
	}
	for _, unit in order do
		if unit.hp <= 0 then
			continue
		end

		local target = findNearestTarget(unit, state.units)
		if not target then
			if not hasLivingEnemy(state, unit.side) and not enemyHadUnitsAtTickStart(livingAtTickStart, unit.side) then
				local tickWinner = pursueEnemyBase(unit, state, tick, events)
				if tickWinner ~= nil then
					winner = tickWinner
				end
			end
			continue
		end

		local dist = manhattan(unit.col, unit.row, target.col, target.row)
		if dist <= BattleGridConfig.ATTACK_RANGE then
			local damage = unit.atk
			target.hp = math.max(0, target.hp - damage)
			table.insert(events, {
				kind = "attack",
				tick = tick,
				attackerSide = unit.side,
				attackerUid = unit.uid,
				attackerCol = unit.col,
				attackerRow = unit.row,
				targetUid = target.uid,
				targetCol = target.col,
				targetRow = target.row,
				damage = damage,
				targetHpAfter = target.hp,
			})
		elseif dist > BattleGridConfig.ATTACK_RANGE then
			for _ = 1, BattleGridConfig.MOVE_STEPS_PER_TICK do
				local moved, fromCol, fromRow, toCol, toRow = tryMoveStep(unit, target, state.units)
				if not moved then
					break
				end
				table.insert(events, {
					kind = "move",
					tick = tick,
					side = unit.side,
					uid = unit.uid,
					fromCol = fromCol,
					fromRow = fromRow,
					toCol = toCol,
					toRow = toRow,
				})
				if manhattan(unit.col, unit.row, target.col, target.row) <= BattleGridConfig.ATTACK_RANGE then
					break
				end
			end
		end
	end

	return events, checkWinner(state)
end

function BattleCombatEngine.resolveTimeoutWinner(state: CombatState): BattleSide?
	if state.baseHpA > state.baseHpB then
		return "A"
	elseif state.baseHpB > state.baseHpA then
		return "B"
	end
	return nil
end

return BattleCombatEngine
