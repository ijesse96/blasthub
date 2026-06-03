--!strict
-- Battle Grounds grid: 16x12 viewport grid, west/east column split.
local BattleGridConfig = {
	MAP_ID = "main",
	COLS = 16,
	ROWS = 12,
	SIDE_SPLIT_COL = 8,
	SIDE_B_MAX_ROW = 11,
	SIDE_A_MIN_ROW = 0,
	SIDE_B_BASE_ROW = 0,
	SIDE_A_BASE_ROW = 11,
	MAX_UNITS_PER_SIDE = 96,
	MAX_UNITS_ON_FIELD = 96,
	PLACEMENT_SECONDS = 18,
	PLACEMENT_TIMER_ENABLED = false,
	REMOTE_COOLDOWN_SECONDS = 0.08,
	MAX_COMBAT_TICKS = 600,
	ATTACK_RANGE = 1,
	MOVE_STEPS_PER_TICK = 1,
	STARTING_BASE_HP = 100,
	MAX_MANA = 10,
	STARTING_MANA = 4,
	MANA_REGEN_PER_TICK = 0.5,
	COMBAT_TICK_INTERVAL = 0.5,
	BASE_DAMAGE_PER_TICK = 2,
	BOT_SUMMON_EVERY_TICKS = 4,
	MANA_COST_BY_TIER = {
		common = 2,
		rare = 3,
		legendary = 4,
		jackpot = 5,
	},
}

return BattleGridConfig
