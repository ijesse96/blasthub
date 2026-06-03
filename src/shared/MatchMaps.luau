local PlaceIds = require(script.Parent:WaitForChild("PlaceIds"))

export type MatchMap = {
	id: string,
	displayName: string,
	placeId: number,
	entryFee: number,
	firstPlaceBonus: number,
	-- Lower = further left in lobby map grid
	sortOrder: number,
	-- rbxassetid://... ; nil or omit = placeholder tile in lobby map grid
	thumbnailImage: string?,
	-- Lobby collection picker + inventory tabs (even at 0 collected).
	collectionEnabled: boolean?,
}

local mapsById: { [string]: MatchMap } = {
	main = {
		id = "main",
		displayName = "Fish Frenzy",
		placeId = PlaceIds.MainGame,
		entryFee = 25,
		firstPlaceBonus = 100,
		sortOrder = 1,
		thumbnailImage = "rbxassetid://118675753644542",
		collectionEnabled = true,
	},
	king_of_the_jungle = {
		id = "king_of_the_jungle",
		displayName = "King of the Jungle",
		placeId = PlaceIds.KingOfTheJungle,
		entryFee = 50,
		firstPlaceBonus = 0,
		sortOrder = 2,
		thumbnailImage = "rbxassetid://110244679893761",
		collectionEnabled = true,
	},
	dragon_quest = {
		id = "dragon_quest",
		displayName = "Dragon Quest",
		placeId = PlaceIds.DragonQuest,
		entryFee = 100,
		firstPlaceBonus = 0,
		sortOrder = 3,
		thumbnailImage = "rbxassetid://71683561033302",
		collectionEnabled = true,
	},
	haunted_mansion = {
		id = "haunted_mansion",
		displayName = "Haunted Mansion",
		placeId = 0,
		entryFee = 150,
		firstPlaceBonus = 0,
		sortOrder = 4,
		thumbnailImage = "rbxassetid://73962958806065",
	},
	pharaohs_tomb = {
		id = "pharaohs_tomb",
		displayName = "Pharaohs Tomb",
		placeId = 0,
		entryFee = 200,
		firstPlaceBonus = 0,
		sortOrder = 5,
		thumbnailImage = "rbxassetid://86601530885201",
	},
	sweet_dreams = {
		id = "sweet_dreams",
		displayName = "Sweet Dreams",
		placeId = 0,
		entryFee = 250,
		firstPlaceBonus = 0,
		sortOrder = 6,
		thumbnailImage = "rbxassetid://125939841856904",
	},
}

local MatchMaps = {}

MatchMaps.DEFAULT_MAP_ID = "main"

function MatchMaps.getMapById(mapId: string): MatchMap?
	return mapsById[mapId]
end

function MatchMaps.getAll(): { MatchMap }
	local list: { MatchMap } = {}
	for _, map in mapsById do
		table.insert(list, map)
	end
	table.sort(list, function(a, b)
		if a.sortOrder ~= b.sortOrder then
			return a.sortOrder < b.sortOrder
		end
		return a.displayName < b.displayName
	end)
	return list
end

function MatchMaps.getCollectionEnabledMaps(): { MatchMap }
	local list: { MatchMap } = {}
	for _, map in mapsById do
		if map.collectionEnabled then
			table.insert(list, map)
		end
	end
	table.sort(list, function(a, b)
		if a.sortOrder ~= b.sortOrder then
			return a.sortOrder < b.sortOrder
		end
		return a.displayName < b.displayName
	end)
	return list
end

return MatchMaps
