--!strict
-- Demo castle entries for the lobby battle world map UI.

export type CastleEntry = {
	id: string,
	playerName: string,
	castleLevel: number,
	power: number,
	region: string,
	gridCol: number,
	gridRow: number,
	isLocalPlayer: boolean?,
}

local CASTLES: { CastleEntry } = {
	{
		id = "local",
		playerName = "You",
		castleLevel = 4,
		power = 950,
		region = "Sunlit Plains",
		gridCol = 1,
		gridRow = 1,
		isLocalPlayer = true,
	},
	{
		id = "iron_wolf",
		playerName = "IronWolf",
		castleLevel = 7,
		power = 2100,
		region = "Northern Highlands",
		gridCol = 0,
		gridRow = 0,
	},
	{
		id = "coral_queen",
		playerName = "CoralQueen",
		castleLevel = 5,
		power = 1400,
		region = "Azure Coast",
		gridCol = 2,
		gridRow = 0,
	},
	{
		id = "shadow_knight",
		playerName = "ShadowKnight",
		castleLevel = 9,
		power = 3200,
		region = "Dark Marsh",
		gridCol = 0,
		gridRow = 2,
	},
	{
		id = "ember_sage",
		playerName = "EmberSage",
		castleLevel = 3,
		power = 720,
		region = "Volcanic Ridge",
		gridCol = 2,
		gridRow = 1,
	},
	{
		id = "frost_mage",
		playerName = "FrostMage",
		castleLevel = 6,
		power = 1800,
		region = "Glacial Peaks",
		gridCol = 1,
		gridRow = 0,
	},
	{
		id = "thorn_ranger",
		playerName = "ThornRanger",
		castleLevel = 2,
		power = 480,
		region = "Whisperwood",
		gridCol = 0,
		gridRow = 1,
	},
	{
		id = "golden_tide",
		playerName = "GoldenTide",
		castleLevel = 8,
		power = 2600,
		region = "Golden Bay",
		gridCol = 2,
		gridRow = 2,
	},
}

local BattleMapDemoData = {}

function BattleMapDemoData.getCastles(): { CastleEntry }
	local out: { CastleEntry } = {}
	for _, castle in CASTLES do
		table.insert(out, {
			id = castle.id,
			playerName = castle.playerName,
			castleLevel = castle.castleLevel,
			power = castle.power,
			region = castle.region,
			gridCol = castle.gridCol,
			gridRow = castle.gridRow,
			isLocalPlayer = castle.isLocalPlayer,
		})
	end
	return out
end

function BattleMapDemoData.getCastleById(id: string): CastleEntry?
	for _, castle in CASTLES do
		if castle.id == id then
			return {
				id = castle.id,
				playerName = castle.playerName,
				castleLevel = castle.castleLevel,
				power = castle.power,
				region = castle.region,
				gridCol = castle.gridCol,
				gridRow = castle.gridRow,
				isLocalPlayer = castle.isLocalPlayer,
			}
		end
	end
	return nil
end

return BattleMapDemoData
