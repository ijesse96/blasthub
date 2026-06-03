--!strict
-- Battle Grounds scene visuals (background + grid chrome).

local BattleGroundsUiConfig = {
	BACKGROUND_IMAGE = "rbxassetid://98578303976737",
	BACKGROUND_FALLBACK_COLOR = Color3.fromRGB(28, 58, 38),

	COLS = 16,
	ROWS = 12,
	SIDE_SPLIT_COL = 8,

	CELL_STROKE_COLOR = Color3.fromRGB(255, 255, 255),
	CELL_STROKE_TRANSPARENCY = 0.45,
	CELL_STROKE_THICKNESS = 3,
	SIDE_A_STROKE_COLOR = Color3.fromRGB(72, 120, 200),
	SIDE_B_STROKE_COLOR = Color3.fromRGB(200, 88, 88),

	Z_BACKGROUND = 1,
	Z_GRID = 2,
	Z_UNITS = 10,
	Z_COMBAT = 12,
}

return BattleGroundsUiConfig
