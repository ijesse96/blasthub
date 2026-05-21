--!strict
-- Per-map splash fish image ids by rarity tier. Paste new ids into the matching tier table.

export type FishTier = "common" | "rare" | "legendary"

export type MapFishTiers = {
	common: { string },
	rare: { string },
	legendary: { string },
}

local catalog: { [string]: MapFishTiers } = {
	main = {
		common = {
			"rbxassetid://72177555306292",
			"rbxassetid://122269752750112",
			"rbxassetid://125480584426747",
			"rbxassetid://105490197665891",
			"rbxassetid://124723789535564",
			"rbxassetid://97126169379906",
			"rbxassetid://81031932675072",
			"rbxassetid://135199557091955",
			"rbxassetid://75531846438830",
			"rbxassetid://138416082304482",
			"rbxassetid://91043348575217",
			"rbxassetid://101941827702897",
			"rbxassetid://125032448976909",
			"rbxassetid://92130003499553",
			"rbxassetid://78910407382117",
			"rbxassetid://124783478026253",
			"rbxassetid://116122820351287",
			"rbxassetid://114925554007613",
			"rbxassetid://78768316542000",
			"rbxassetid://86868520347981",
			"rbxassetid://102350623439781",
			"rbxassetid://98237903253107",
			"rbxassetid://116137519003371",
			"rbxassetid://97423818731413",
			"rbxassetid://120198486399242",
			"rbxassetid://135021254411046",
			"rbxassetid://118111777575295",
			"rbxassetid://122568411366642",
			"rbxassetid://138845906213886",
			"rbxassetid://117946344784536",
			"rbxassetid://84535790730571",
			"rbxassetid://101450237273733",
			"rbxassetid://84443917135890",
			"rbxassetid://95544070467501",
			"rbxassetid://139881356349437",
			"rbxassetid://138254783157299",
			"rbxassetid://138174130727637",
			"rbxassetid://72452886195915",
			"rbxassetid://118717868248667",
			"rbxassetid://135799972512167",
			"rbxassetid://136692069139683",
			"rbxassetid://117920033184567",
			"rbxassetid://73692928813145",
			"rbxassetid://120116116899948",
			"rbxassetid://119334580452184",
			"rbxassetid://120502269939926",
			"rbxassetid://93798506175362",
			"rbxassetid://105546942048120",
			"rbxassetid://118261741545907",
			"rbxassetid://70586392499334",
			"rbxassetid://88165794823993",
			"rbxassetid://90620093718156",
			"rbxassetid://83752118298194",
			"rbxassetid://139246135584328",
			"rbxassetid://111063768998196",
			"rbxassetid://98018439290627",
			"rbxassetid://87592274682175",
			"rbxassetid://111807469496436",
			"rbxassetid://99240492996636",
			"rbxassetid://130277859053099",
			"rbxassetid://79572378701133",
			"rbxassetid://72030311891673",
		},
		rare = {},
		legendary = {},
	},
}

local TIERS: { FishTier } = { "common", "rare", "legendary" }

local SplashFishCatalog = {}

function SplashFishCatalog.getMapTiers(mapId: string): MapFishTiers?
	return catalog[mapId]
end

function SplashFishCatalog.getIdsForTier(mapId: string, tier: FishTier): { string }
	local mapTiers = catalog[mapId]
	if not mapTiers then
		return {}
	end
	return mapTiers[tier]
end

function SplashFishCatalog.getAllIdsForMap(mapId: string): { string }
	local mapTiers = catalog[mapId]
	if not mapTiers then
		return {}
	end
	local out: { string } = {}
	for _, tier in TIERS do
		for _, id in mapTiers[tier] do
			table.insert(out, id)
		end
	end
	return out
end

return SplashFishCatalog
