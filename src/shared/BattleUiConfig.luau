--!strict
-- Layout constants for battle placement HUD (mobile landscape + desktop).

local BattleUiConfig = {
	COMPACT_VIEWPORT_X = 700,
	COMPACT_VIEWPORT_Y = 500,

	BACKGROUND_COLOR = Color3.new(0, 0, 0),
	ROOT_INSET = 0,

	-- Side accent colors (kept in sync with grid tile colors).
	SIDE_A_ACCENT = Color3.fromRGB(32, 52, 88),
	SIDE_B_ACCENT = Color3.fromRGB(72, 36, 40),

	SHOW_BATTLE_MODE_TITLE = false,
	SHOW_PHASE_TIMER_LABEL = false,
	SHOW_ENEMY_PANEL = false,
	HEADER_HEIGHT = 44,
	HEADER_HEIGHT_COMPACT = 36,
	FOOTER_HEIGHT = 52,
	FOOTER_HEIGHT_COMPACT = 48,

	SIDE_WIDTH_SCALE = 0.22,
	SIDE_WIDTH_MIN = 140,
	SIDE_WIDTH_MAX = 220,
	SIDE_WIDTH_MAX_COMPACT = 180,

	CENTER_WIDTH_SCALE = 0.56,

	CARD_WIDTH = 88,
	CARD_HEIGHT = 108,
	CARD_WIDTH_COMPACT = 72,
	CARD_HEIGHT_COMPACT = 88,
	CARD_GRID_COLUMNS = 2,

	GRID_MIN_CELL = 28,
	GRID_MAX_CELL = 44,
	GRID_PAD = 1,

	-- "topdown" = flat grid; "perspective" = front-facing trapezoid arena
	GRID_PROJECTION = "topdown",
	PERSPECTIVE_BACK_CELL_SCALE = 0.92,
	PERSPECTIVE_TOP_WIDTH_RATIO = 0.94,
	PERSPECTIVE_ROW_PAD = 0,

	SCROLL_BAR_THICKNESS = 8,
	SCROLL_BAR_THICKNESS_COMPACT = 10,

	Z_HEADER = 20,
	Z_FOOTER = 20,
	Z_SIDEBAR = 15,
	Z_GRID = 10,
	Z_COMBAT = 200,
}

return BattleUiConfig
