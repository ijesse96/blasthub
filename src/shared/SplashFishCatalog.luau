--!strict
-- Per-map splash fish image ids by rarity tier. Paste new ids into the matching tier table.

export type FishTier = "common" | "rare" | "legendary" | "jackpot"

export type MapFishTiers = {
	common: { string },
	rare: { string },
	legendary: { string },
	jackpot: { string },
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
		rare = {
			"rbxassetid://111162978627012",
			"rbxassetid://79031258793570",
			"rbxassetid://122270730023094",
			"rbxassetid://94375524542480",
			"rbxassetid://105043130273934",
			"rbxassetid://96346424247791",
			"rbxassetid://117559905044863",
			"rbxassetid://123788664302447",
			"rbxassetid://72728233354395",
			"rbxassetid://106508951049354",
			"rbxassetid://107791960260541",
			"rbxassetid://71281858170011",
			"rbxassetid://122210234798379",
			"rbxassetid://114733843330061",
			"rbxassetid://107979171859424",
			"rbxassetid://94134562492456",
			"rbxassetid://101029661281387",
			"rbxassetid://102582417501584",
			"rbxassetid://134928608897254",
			"rbxassetid://116510172120294",
			"rbxassetid://134793144313869",
			"rbxassetid://99699629165694",
			"rbxassetid://102975214008656",
			"rbxassetid://104151122024871",
			"rbxassetid://83125949242482",
			"rbxassetid://94100815689815",
			"rbxassetid://78201873379326",
			"rbxassetid://88326700093005",
			"rbxassetid://99097060536642",
			"rbxassetid://80975049373810",
			"rbxassetid://133099212511972",
			"rbxassetid://137998891674251",
			"rbxassetid://135148362535701",
			"rbxassetid://116202927773022",
			"rbxassetid://100302825512373",
			"rbxassetid://125838247762876",
			"rbxassetid://106562282855025",
			"rbxassetid://119324407982126",
			"rbxassetid://126850424308429",
			"rbxassetid://127867128314098",
			"rbxassetid://78040307143054",
			"rbxassetid://131082067982357",
			"rbxassetid://105673734419036",
			"rbxassetid://127829564733478",
			"rbxassetid://72633228578754",
			"rbxassetid://116182745721730",
			"rbxassetid://140149792233957",
			"rbxassetid://93271341692412",
			"rbxassetid://139734585167839",
			"rbxassetid://130890978801370",
			"rbxassetid://110538054555198",
			"rbxassetid://97222885561314",
			"rbxassetid://114343808913438",
			"rbxassetid://120635152926303",
			"rbxassetid://123620658862994",
			"rbxassetid://122359984327555",
		},
		jackpot = {
			"rbxassetid://107917045018097",
		},
		legendary = {
			"rbxassetid://87992282626603",
			"rbxassetid://135039847776430",
			"rbxassetid://73704405720748",
			"rbxassetid://138815690227766",
			"rbxassetid://93614571753602",
			"rbxassetid://76273687220643",
			"rbxassetid://110781888130848",
			"rbxassetid://78582381787224",
			"rbxassetid://76030769874788",
			"rbxassetid://118591774049006",
			"rbxassetid://84156003958485",
			"rbxassetid://95196073674268",
			"rbxassetid://133961169627867",
			"rbxassetid://99545440979598",
			"rbxassetid://79588954987149",
			"rbxassetid://128698527410655",
			"rbxassetid://106734458693548",
			"rbxassetid://122921781604823",
			"rbxassetid://84495546354654",
			"rbxassetid://115173049189528",
			"rbxassetid://130058565487419",
			"rbxassetid://90168051882744",
			"rbxassetid://136804484001349",
			"rbxassetid://107867082020840",
			"rbxassetid://138192492834845",
			"rbxassetid://90430512038146",
			"rbxassetid://126635814476270",
			"rbxassetid://111565943200697",
			"rbxassetid://103251400279676",
			"rbxassetid://110640882590220",
			"rbxassetid://108262349173801",
			"rbxassetid://95373006703722",
			"rbxassetid://81479143876377",
			"rbxassetid://88838977283975",
			"rbxassetid://132216284825145",
			"rbxassetid://134844165127345",
			"rbxassetid://118213653020939",
			"rbxassetid://92717659172223",
			"rbxassetid://85712994978243",
		},
	},
	dragon_quest = {
		common = {
			"rbxassetid://126542915573192",
			"rbxassetid://95369015830134",
			"rbxassetid://84645361926026",
			"rbxassetid://130073935229189",
			"rbxassetid://124853581664932",
			"rbxassetid://120549918862846",
			"rbxassetid://90749149386011",
			"rbxassetid://116190331892170",
			"rbxassetid://128984474199358",
			"rbxassetid://84028785082295",
			"rbxassetid://92413854374097",
			"rbxassetid://94026374185851",
			"rbxassetid://93399021155349",
			"rbxassetid://125860013987184",
			"rbxassetid://111616194903543",
			"rbxassetid://107024053980836",
			"rbxassetid://113166263057856",
			"rbxassetid://89246231917420",
			"rbxassetid://76518366079069",
			"rbxassetid://123978881849044",
			"rbxassetid://80184023203965",
			"rbxassetid://80511255200291",
			"rbxassetid://90160696727438",
			"rbxassetid://95638805421631",
			"rbxassetid://107028972510357",
			"rbxassetid://75884104337997",
			"rbxassetid://81405174797763",
			"rbxassetid://113647779902033",
			"rbxassetid://124926118016730",
			"rbxassetid://119254764363621",
			"rbxassetid://107943227600217",
			"rbxassetid://77545192436480",
			"rbxassetid://112392268222173",
			"rbxassetid://95988880836476",
			"rbxassetid://96600229414057",
		},
		rare = {},
		legendary = {},
		jackpot = {},
	},
	king_of_the_jungle = {
		common = {
			"rbxassetid://82261341033005",
			"rbxassetid://93476782599301",
			"rbxassetid://75897069297338",
			"rbxassetid://131957458823867",
			"rbxassetid://121655970279001",
			"rbxassetid://87731744941453",
			"rbxassetid://94118252921451",
			"rbxassetid://74289251670867",
			"rbxassetid://113362970126620",
			"rbxassetid://120373773021461",
			"rbxassetid://107305875338379",
			"rbxassetid://81598734162239",
			"rbxassetid://119346183672853",
			"rbxassetid://123972071062017",
			"rbxassetid://131314519420473",
			"rbxassetid://86552091688217",
			"rbxassetid://70411470200583",
			"rbxassetid://76687916486105",
			"rbxassetid://79171366891140",
			"rbxassetid://139209419791065",
			"rbxassetid://109146826856087",
			"rbxassetid://117926897115467",
			"rbxassetid://116840279356700",
			"rbxassetid://139517144272501",
			"rbxassetid://90871029255144",
			"rbxassetid://95929658425621",
			"rbxassetid://126043487935118",
			"rbxassetid://109291292133840",
			"rbxassetid://102329122055941",
			"rbxassetid://130028936586498",
			"rbxassetid://99919283461138",
			"rbxassetid://76010812173259",
			"rbxassetid://89866339647216",
			"rbxassetid://90531235663327",
			"rbxassetid://85576450253206",
			"rbxassetid://110774446555973",
			"rbxassetid://98778972516942",
			"rbxassetid://99537888129392",
			"rbxassetid://96577817208583",
			"rbxassetid://103878121902829",
			"rbxassetid://129620092148220",
			"rbxassetid://125968664704175",
			"rbxassetid://138146020712494",
			"rbxassetid://71992744652439",
			"rbxassetid://104506113693189",
			"rbxassetid://125128251084550",
			"rbxassetid://87697695236346",
			"rbxassetid://132198100015543",
			"rbxassetid://100638014291054",
			"rbxassetid://92507149751680",
			"rbxassetid://107587116522257",
			"rbxassetid://109151727206184",
			"rbxassetid://84764859285949",
			"rbxassetid://115087802255882",
		},
		rare = {},
		legendary = {},
		jackpot = {},
	},
}

local TIERS: { FishTier } = { "common", "rare", "legendary", "jackpot" }
local GAMEPLAY_TIERS: { FishTier } = { "common", "rare", "legendary", "jackpot" }

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

function SplashFishCatalog.getSpawnableIdsForMap(mapId: string): { string }
	local mapTiers = catalog[mapId]
	if not mapTiers then
		return {}
	end
	local out: { string } = {}
	for _, tier in GAMEPLAY_TIERS do
		for _, id in mapTiers[tier] do
			table.insert(out, id)
		end
	end
	return out
end

function SplashFishCatalog.getCommonSpawnableIdsForMap(mapId: string): { string }
	return SplashFishCatalog.getIdsForTier(mapId, "common")
end

function SplashFishCatalog.getRareSpawnableIdsForMap(mapId: string): { string }
	return SplashFishCatalog.getIdsForTier(mapId, "rare")
end

function SplashFishCatalog.getLegendarySpawnableIdsForMap(mapId: string): { string }
	return SplashFishCatalog.getIdsForTier(mapId, "legendary")
end

function SplashFishCatalog.getRarePlusSpawnableIdsForMap(mapId: string): { string }
	local mapTiers = catalog[mapId]
	if not mapTiers then
		return {}
	end
	local out: { string } = {}
	for _, tier in { "rare", "legendary", "jackpot" } :: { FishTier } do
		for _, id in mapTiers[tier] do
			table.insert(out, id)
		end
	end
	return out
end

function SplashFishCatalog.getTierForImageId(mapId: string, imageId: string): FishTier?
	local mapTiers = catalog[mapId]
	if not mapTiers then
		return nil
	end
	for _, tier in TIERS do
		for _, id in mapTiers[tier] do
			if id == imageId then
				return tier
			end
		end
	end
	return nil
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

function SplashFishCatalog.getOrderedTiers(): { FishTier }
	return TIERS
end

function SplashFishCatalog.listMapIds(): { string }
	local ids: { string } = {}
	for mapId, _ in catalog do
		table.insert(ids, mapId)
	end
	table.sort(ids)
	return ids
end

function SplashFishCatalog.countCardsForMap(mapId: string): number
	return #SplashFishCatalog.getAllIdsForMap(mapId)
end

return SplashFishCatalog
