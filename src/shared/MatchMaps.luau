local PlaceIds = require(script.Parent:WaitForChild("PlaceIds"))

export type MatchMap = {
	id: string,
	displayName: string,
	placeId: number,
	entryFee: number,
	firstPlaceBonus: number,
}

local mapsById: { [string]: MatchMap } = {
	main = {
		id = "main",
		displayName = "Fish Frenzy",
		placeId = PlaceIds.MainGame,
		entryFee = 25,
		firstPlaceBonus = 100,
	},
}

local MatchMaps = {}

function MatchMaps.getMapById(mapId: string): MatchMap?
	return mapsById[mapId]
end

function MatchMaps.getAll(): { MatchMap }
	local list: { MatchMap } = {}
	for _, map in mapsById do
		table.insert(list, map)
	end
	return list
end

return MatchMaps
