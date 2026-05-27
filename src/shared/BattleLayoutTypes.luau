--!strict
export type BattleSide = "A" | "B"

export type BattleMode = "live_1v1"

export type PlacementUnit = {
	imageId: string,
	col: number,
	row: number,
	level: number,
}

export type SideLayout = { PlacementUnit }

export type PlayerBattleInfo = {
	userId: number,
	name: string,
	placedCount: number,
	ready: boolean,
	isBot: boolean?,
}

export type BattlePlacementStatePayload = {
	sessionId: string,
	mode: BattleMode,
	phase: "placement" | "combat" | "ended",
	localSide: BattleSide,
	placementEndServerTime: number,
	playerA: PlayerBattleInfo,
	playerB: PlayerBattleInfo,
	layoutA: SideLayout,
	layoutB: SideLayout,
	maxBaseHp: number?,
	maxMana: number?,
	baseHpA: number?,
	baseHpB: number?,
	manaA: number?,
	manaB: number?,
}

export type BattleMoveEvent = {
	kind: "move",
	tick: number,
	side: BattleSide,
	uid: number,
	fromCol: number,
	fromRow: number,
	toCol: number,
	toRow: number,
}

export type BattleAttackEvent = {
	kind: "attack",
	tick: number,
	attackerSide: BattleSide,
	attackerUid: number,
	attackerCol: number,
	attackerRow: number,
	targetUid: number,
	targetCol: number,
	targetRow: number,
	damage: number,
	targetHpAfter: number,
}

export type BattleSummonEvent = {
	kind: "summon",
	tick: number,
	side: BattleSide,
	uid: number,
	col: number,
	row: number,
	imageId: string,
	level: number,
	hp: number,
	maxHp: number,
}

export type BattleBaseDamageEvent = {
	kind: "baseDamage",
	tick: number,
	attackerSide: BattleSide,
	attackerUid: number,
	attackerCol: number,
	attackerRow: number,
	targetCol: number,
	targetRow: number,
	victimSide: BattleSide,
	damage: number,
	baseHpAfter: number,
}

export type BattleCombatEvent = BattleMoveEvent | BattleAttackEvent | BattleSummonEvent | BattleBaseDamageEvent

export type CombatUnitSnapshot = {
	uid: number,
	side: BattleSide,
	col: number,
	row: number,
	imageId: string,
	level: number,
	hp: number,
	maxHp: number,
}

export type BattleCombatUpdatePayload = {
	sessionId: string,
	tick: number,
	baseHpA: number,
	baseHpB: number,
	manaA: number,
	manaB: number,
	maxBaseHp: number,
	maxMana: number,
	units: { CombatUnitSnapshot },
	events: { BattleCombatEvent },
}

export type BattleResultPayload = {
	sessionId: string,
	winnerSide: BattleSide?,
	winnerUserId: number?,
	reason: string,
	eventLog: { BattleCombatEvent },
	finalBaseHpA: number?,
	finalBaseHpB: number?,
}

return {}
