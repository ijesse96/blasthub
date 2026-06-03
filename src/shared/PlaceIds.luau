-- Place IDs for cross-place TeleportService flows (lobby <-> main).
-- TeleportService:TeleportAsync only works between places in the *same experience*
-- (same universe). Add the lobby as a second Place under your experience in Creator
-- Dashboard, then paste both place IDs here. Replace zeros before testing teleports.

export type PlaceIds = {
	Lobby: number,
	MainGame: number,
	BattleGrounds: number,
	KingOfTheJungle: number,
	DragonQuest: number,
}

local PlaceIds: PlaceIds = {
	Lobby = 80900269298159,
	MainGame = 130112747036452,
	BattleGrounds = 95970165088118,
	KingOfTheJungle = 82834864756259,
	DragonQuest = 130967805909090,
}

return PlaceIds
