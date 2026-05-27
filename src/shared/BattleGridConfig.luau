--!strict
local BattleGridConfig = {
	MAP_ID = "main",
	COLS = 12,
	ROWS = 12,
	-- Row split: B (red) rows 0..5, A (blue) rows 6..11; midline at rows 5 and 6.
	SIDE_B_MAX_ROW = 5,
	SIDE_A_MIN_ROW = 6,
	SIDE_B_BASE_ROW = 0,
	SIDE_A_BASE_ROW = 11,
	MAX_UNITS_PER_SIDE = 10,
	MAX_UNITS_ON_FIELD = 12,
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
