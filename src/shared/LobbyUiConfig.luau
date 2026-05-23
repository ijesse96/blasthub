--!strict
-- Lobby hub visuals (background art, button layout constants).

export type HubMenuButtonTheme = {
	color: Color3,
	stroke: Color3,
	innerStroke: Color3,
	text: Color3,
	subtitle: Color3?,
}

local LobbyUiConfig = {
	BACKGROUND_IMAGE = "rbxassetid://136855583244339",
	-- 1 = no dim overlay; lower values darken more.
	BACKGROUND_DIM_TRANSPARENCY = 1,
	BACKGROUND_FALLBACK_COLOR = Color3.fromRGB(48, 72, 96),

	HUB_BUTTON_COLUMN_POSITION = UDim2.fromScale(0.5, 0.62),
	HUB_BUTTON_WIDTH = 320,
	HUB_BUTTON_GAP = 5,
	PLAY_BUTTON_HEIGHT = 58,
	MENU_BUTTON_HEIGHT = 44,
	BUTTON_INNER_INSET = 6,
	BUTTON_INNER_STROKE_COLOR = Color3.new(0, 0, 0),
	BUTTON_CORNER_RADIUS = 14,
	HUB_MENU_FONT = Enum.Font.Arcade,
	-- Temporary: hide secondary menu buttons until features are ready.
	SHOW_DAILY_BUTTON = false,
	SHOW_SHOP_BUTTON = false,
	SHOW_COLLECTION_BUTTON = false,
	BUTTON_OUTER_STROKE_THICKNESS = 2.5,
	BUTTON_INNER_STROKE_THICKNESS = 2,

	PLAY_BUTTON = {
		color = Color3.fromRGB(255, 190, 55),
		stroke = Color3.fromRGB(160, 95, 20),
		innerStroke = Color3.fromRGB(0, 0, 0),
		text = Color3.fromRGB(45, 28, 8),
		subtitle = Color3.fromRGB(55, 38, 12),
	} :: HubMenuButtonTheme,

	DAILY_BUTTON = {
		color = Color3.fromRGB(72, 255, 140),
		stroke = Color3.fromRGB(18, 100, 48),
		innerStroke = Color3.fromRGB(0, 0, 0),
		text = Color3.fromRGB(8, 42, 22),
		subtitle = nil,
	} :: HubMenuButtonTheme,

	SHOP_BUTTON = {
		color = Color3.fromRGB(100, 175, 255),
		stroke = Color3.fromRGB(35, 90, 160),
		innerStroke = Color3.fromRGB(140, 200, 255),
		text = Color3.fromRGB(12, 28, 55),
		subtitle = nil,
	} :: HubMenuButtonTheme,

	COLLECTION_BUTTON = {
		color = Color3.fromRGB(180, 130, 255),
		stroke = Color3.fromRGB(90, 50, 140),
		innerStroke = Color3.fromRGB(210, 170, 255),
		text = Color3.fromRGB(35, 18, 55),
		subtitle = nil,
	} :: HubMenuButtonTheme,

	Z_BACKGROUND = 0,
	Z_BUTTONS = 2,
	Z_STATUS = 8,
	Z_SUB_BACKDROP = 10,
	Z_SUB_PANEL = 11,

	SUB_BACKDROP_TRANSPARENCY = 0.45,
	SUB_PANEL_COLOR = Color3.fromRGB(48, 58, 72),
	SUB_PANEL_TRANSPARENCY = 0,
	SUB_HEADER_COLOR = Color3.fromRGB(58, 70, 88),
	SUB_BODY_COLOR = Color3.fromRGB(38, 48, 62),
	SUB_PANEL_STROKE = Color3.fromRGB(140, 180, 210),
	SUB_TITLE_TEXT = Color3.fromRGB(255, 255, 255),
	SUB_BODY_TEXT = Color3.fromRGB(230, 236, 245),
	SUB_ROW_COLOR = Color3.fromRGB(62, 76, 94),
	SUB_ROW_TRANSPARENCY = 0,
	SUB_PANEL_SIZE = Vector2.new(420, 400),

	CASH_BAR_COIN_IMAGE = "rbxassetid://117865486369077",
	CASH_BAR_BG_COLOR = Color3.fromRGB(18, 24, 38),
	CASH_BAR_BG_TRANSPARENCY = 0.12,
	CASH_BAR_STROKE_COLOR = Color3.fromRGB(70, 120, 180),
	CASH_BAR_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	CASH_BAR_PLUS_BG = Color3.fromRGB(45, 75, 120),
	CASH_BAR_PLUS_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	CASH_BAR_HEIGHT = 44,
	CASH_BAR_COIN_SIZE = 32,
	CASH_BAR_PLUS_SIZE = 40,
	CASH_BAR_PADDING = 10,
	CASH_BAR_POSITION = UDim2.new(1, -16, 0, 16),
}

return LobbyUiConfig
