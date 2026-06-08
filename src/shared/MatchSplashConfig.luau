--!strict
-- Per-map splash spawn visuals (floor target that players shoot).
-- King of the Jungle: delete Workspace.Water in Studio; spawner builds billboard PNGs from config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchMaps = require(script.Parent:WaitForChild("MatchMaps"))

export type SplashVisualMode = "water_template" | "billboard_png"

export type SplashVisual = {
	mode: SplashVisualMode,
	workspaceTemplateName: string?,
	imageId: string?,
	splashFrameIds: { string }?,
	billboardStuds: number?,
	fishBillboardScale: number?,
	hitNetTextureId: string?,
	hitNetTextureIdRed: string?,
	-- Override hit-net BillboardGui pixel size (bbox-based sizing uses huge flat-decal anchors).
	hitNetBillboardPx: number?,
	sandCoverImageId: string?,
	reelLeafImageId: string?,
	scrollWaterBackground: boolean,
	-- Fish Frenzy rare target (shark): animated cover + swim drift instead of water splash.
	rareTargetFrameIds: { string }?,
	rareTargetSpawnChance: number?,
	commonTargetStuds: number?,
	rareTargetStuds: number?,
	rareTargetArtYawOffsetRad: number?,
	rareTargetSwimSpeedStudsPerSec: number?,
	commonTargetCashMin: number?,
	commonTargetCashMax: number?,
	largeTargetCashMin: number?,
	largeTargetCashMax: number?,
	rareTargetCashMin: number?,
	rareTargetCashMax: number?,
	legendaryTargetCashMin: number?,
	legendaryTargetCashMax: number?,
	-- Future: separate cover PNG targets for legendary / jackpot.
	legendaryTargetImageId: string?,
	legendaryTargetImageIdInverted: string?,
	legendaryTargetStormImageId: string?,
	legendaryTargetStormImageIdInverted: string?,
	legendaryTargetStuds: number?,
	legendaryTargetRespawnDelayMinSec: number?,
	legendaryTargetRespawnDelayMaxSec: number?,
	legendaryTargetArtYawOffsetRad: number?,
	legendaryTargetSwimSpeedStudsPerSec: number?,
	legendaryTargetHealthMin: number?,
	legendaryTargetHealthMax: number?,
	legendaryTargetWakeFrameIds: { string }?,
	legendaryTargetFrameIds: { string }?,
	jackpotTargetEmergenceFrameIds: { string }?,
	jackpotTargetStuds: number?,
	jackpotTargetRespawnDelayMinSec: number?,
	jackpotTargetRespawnDelayMaxSec: number?,
	jackpotTargetHealthMin: number?,
	jackpotTargetHealthMax: number?,
	jackpotTargetCycleCount: number?,
	baseplateStormFrameIds: { string }?,
	baseplateStormChopRepeatCount: number?,
	baseplateStormFrameStepSec: number?,
	baseplateNormalTextureId: string?,
	baseplateStormColor: { number }?,
	baseplateStormBrightness: number?,
	baseplateStormAmbient: { number }?,
}

local ACTIVE_MAP_ID_NAME = "ActiveMapId"
local DEFAULT_MAP_ID = "main"

local FISH_FRENZY_SPLASH_FRAME_RIPPLE = "rbxassetid://91096902597254"
local FISH_FRENZY_SPLASH_FRAME_MID = "rbxassetid://98880235729019"
local FISH_FRENZY_SPLASH_FRAME_FULL = "rbxassetid://112577396294090"
local FISH_FRENZY_SPLASH_FRAMES = {
	FISH_FRENZY_SPLASH_FRAME_RIPPLE,
	FISH_FRENZY_SPLASH_FRAME_MID,
	FISH_FRENZY_SPLASH_FRAME_FULL,
}
local FISH_FRENZY_SHARK_FRAMES = {
	"rbxassetid://128051809532541",
	"rbxassetid://127513203106192",
	"rbxassetid://117980877467930",
	"rbxassetid://139225187109469",
}
local DEFAULT_RARE_TARGET_SPAWN_CHANCE = 0.40
local DEFAULT_COMMON_TARGET_STUDS = 13
local DEFAULT_RARE_TARGET_STUDS = 28
local DEFAULT_RARE_TARGET_SWIM_SPEED = 10
local LEGENDARY_BOAT_IMAGE = "rbxassetid://89496466764948"
local LEGENDARY_BOAT_IMAGE_INVERTED = "rbxassetid://79516053583456"
local LEGENDARY_BOAT_STORM_IMAGE = "rbxassetid://112303721335839"
local LEGENDARY_BOAT_STORM_IMAGE_INVERTED = "rbxassetid://117101987723528"
local DEFAULT_LEGENDARY_TARGET_STUDS = 64
local DEFAULT_LEGENDARY_RESPAWN_DELAY_MIN = 15
local DEFAULT_LEGENDARY_RESPAWN_DELAY_MAX = 30
local DEFAULT_LEGENDARY_SWIM_SPEED = 8
local DEFAULT_TEST_TARGET_HEALTH_MIN = 1
local DEFAULT_TEST_TARGET_HEALTH_MAX = 3
local DEFAULT_COMMON_TARGET_CASH_MIN = 1
local DEFAULT_COMMON_TARGET_CASH_MAX = 5
local DEFAULT_LARGE_TARGET_CASH_MIN = 8
local DEFAULT_LARGE_TARGET_CASH_MAX = 15
local DEFAULT_RARE_TARGET_CASH_MIN = 10
local DEFAULT_RARE_TARGET_CASH_MAX = 20
local DEFAULT_LEGENDARY_TARGET_CASH_MIN = 25
local DEFAULT_LEGENDARY_TARGET_CASH_MAX = 40
local DEFAULT_LEGENDARY_TARGET_HEALTH_MIN = 30
local DEFAULT_LEGENDARY_TARGET_HEALTH_MAX = 50
local JACKPOT_MONSTER_FRAMES = {
	"rbxassetid://124555826257310",
	"rbxassetid://79722962327885",
	"rbxassetid://80374052051181",
	"rbxassetid://92917272030555",
	"rbxassetid://124722726896606",
}
local DEFAULT_JACKPOT_TARGET_STUDS = 72
local DEFAULT_JACKPOT_RESPAWN_DELAY_MIN = 15
local DEFAULT_JACKPOT_RESPAWN_DELAY_MAX = 30
local DEFAULT_JACKPOT_TARGET_HEALTH_MIN = 100
local DEFAULT_JACKPOT_TARGET_HEALTH_MAX = 100
local JACKPOT_MONSTER_FRAME_STEP_SEC = 0.18
local JACKPOT_MONSTER_IDLE_FRAME_STEP_SEC = 0.45
local DEFAULT_JACKPOT_IDLE_LIFETIME_SEC = 5
local DEFAULT_JACKPOT_CYCLE_COUNT = 5
local BASEPLATE_STORM_FRAMES = {
	"rbxassetid://73257635473989",
	"rbxassetid://122115755994510",
	"rbxassetid://130565108026527",
	"rbxassetid://114932975478478",
	"rbxassetid://70939061678969",
	"rbxassetid://112415082476366",
	"rbxassetid://84374742726760",
	"rbxassetid://80617259726816",
}
local DEFAULT_BASEPLATE_STORM_CHOP_REPEAT = 3
local DEFAULT_BASEPLATE_STORM_FRAME_STEP_SEC = 0.15
local BASEPLATE_NORMAL_TEXTURE = "rbxassetid://110147544715077"
local BASEPLATE_STORM_COLOR = { 0.12, 0.16, 0.22 }
local DEFAULT_BASEPLATE_STORM_BRIGHTNESS = 1.3
local BASEPLATE_STORM_AMBIENT = { 0.15, 0.18, 0.25 }
local JUNGLE_SPLASH_IMAGE = "rbxassetid://110419001189017"
local DEFAULT_HIT_NET = "rbxassetid://135625585340416"
local DEFAULT_HIT_NET_RED = "rbxassetid://106446005308723"
local DEFAULT_SAND_COVER = "rbxassetid://122141499309246"
local JUNGLE_SAND_COVER = "rbxassetid://74096649335349"

local byMapId: { [string]: SplashVisual } = {
	main = {
		mode = "billboard_png",
		workspaceTemplateName = nil,
		imageId = FISH_FRENZY_SPLASH_FRAME_RIPPLE,
		splashFrameIds = FISH_FRENZY_SPLASH_FRAMES,
		billboardStuds = 6,
		fishBillboardScale = 0.065,
		hitNetTextureId = DEFAULT_HIT_NET,
		hitNetTextureIdRed = DEFAULT_HIT_NET_RED,
		sandCoverImageId = DEFAULT_SAND_COVER,
		scrollWaterBackground = true,
		rareTargetFrameIds = FISH_FRENZY_SHARK_FRAMES,
		rareTargetSpawnChance = DEFAULT_RARE_TARGET_SPAWN_CHANCE,
		commonTargetStuds = DEFAULT_COMMON_TARGET_STUDS,
		rareTargetStuds = DEFAULT_RARE_TARGET_STUDS,
		rareTargetArtYawOffsetRad = 0,
		rareTargetSwimSpeedStudsPerSec = DEFAULT_RARE_TARGET_SWIM_SPEED,
		commonTargetCashMin = DEFAULT_COMMON_TARGET_CASH_MIN,
		commonTargetCashMax = DEFAULT_COMMON_TARGET_CASH_MAX,
		largeTargetCashMin = DEFAULT_LARGE_TARGET_CASH_MIN,
		largeTargetCashMax = DEFAULT_LARGE_TARGET_CASH_MAX,
		rareTargetCashMin = DEFAULT_RARE_TARGET_CASH_MIN,
		rareTargetCashMax = DEFAULT_RARE_TARGET_CASH_MAX,
		legendaryTargetCashMin = DEFAULT_LEGENDARY_TARGET_CASH_MIN,
		legendaryTargetCashMax = DEFAULT_LEGENDARY_TARGET_CASH_MAX,
		legendaryTargetImageId = LEGENDARY_BOAT_IMAGE,
		legendaryTargetImageIdInverted = LEGENDARY_BOAT_IMAGE_INVERTED,
		legendaryTargetStormImageId = LEGENDARY_BOAT_STORM_IMAGE,
		legendaryTargetStormImageIdInverted = LEGENDARY_BOAT_STORM_IMAGE_INVERTED,
		legendaryTargetStuds = DEFAULT_LEGENDARY_TARGET_STUDS,
		legendaryTargetRespawnDelayMinSec = DEFAULT_LEGENDARY_RESPAWN_DELAY_MIN,
		legendaryTargetRespawnDelayMaxSec = DEFAULT_LEGENDARY_RESPAWN_DELAY_MAX,
		legendaryTargetArtYawOffsetRad = 0,
		legendaryTargetSwimSpeedStudsPerSec = DEFAULT_LEGENDARY_SWIM_SPEED,
		legendaryTargetHealthMin = DEFAULT_LEGENDARY_TARGET_HEALTH_MIN,
		legendaryTargetHealthMax = DEFAULT_LEGENDARY_TARGET_HEALTH_MAX,
		jackpotTargetEmergenceFrameIds = JACKPOT_MONSTER_FRAMES,
		jackpotTargetStuds = DEFAULT_JACKPOT_TARGET_STUDS,
		jackpotTargetRespawnDelayMinSec = DEFAULT_JACKPOT_RESPAWN_DELAY_MIN,
		jackpotTargetRespawnDelayMaxSec = DEFAULT_JACKPOT_RESPAWN_DELAY_MAX,
		jackpotTargetHealthMin = DEFAULT_JACKPOT_TARGET_HEALTH_MIN,
		jackpotTargetHealthMax = DEFAULT_JACKPOT_TARGET_HEALTH_MAX,
		jackpotTargetCycleCount = DEFAULT_JACKPOT_CYCLE_COUNT,
		baseplateStormFrameIds = BASEPLATE_STORM_FRAMES,
		baseplateStormChopRepeatCount = DEFAULT_BASEPLATE_STORM_CHOP_REPEAT,
		baseplateStormFrameStepSec = DEFAULT_BASEPLATE_STORM_FRAME_STEP_SEC,
		baseplateNormalTextureId = BASEPLATE_NORMAL_TEXTURE,
		baseplateStormColor = BASEPLATE_STORM_COLOR,
		baseplateStormBrightness = DEFAULT_BASEPLATE_STORM_BRIGHTNESS,
		baseplateStormAmbient = BASEPLATE_STORM_AMBIENT,
	},
	king_of_the_jungle = {
		mode = "billboard_png",
		workspaceTemplateName = nil,
		imageId = JUNGLE_SPLASH_IMAGE,
		billboardStuds = 9,
		fishBillboardScale = 0.32,
		hitNetTextureId = DEFAULT_HIT_NET,
		hitNetTextureIdRed = DEFAULT_HIT_NET_RED,
		sandCoverImageId = JUNGLE_SAND_COVER,
		reelLeafImageId = "rbxassetid://85727082053287",
		scrollWaterBackground = false,
	},
	dragon_quest = {
		mode = "billboard_png",
		workspaceTemplateName = nil,
		imageId = "rbxassetid://117255021260624",
		billboardStuds = 14,
		fishBillboardScale = 0.05,
		hitNetTextureId = DEFAULT_HIT_NET,
		hitNetTextureIdRed = DEFAULT_HIT_NET_RED,
		hitNetBillboardPx = 110,
		sandCoverImageId = "rbxassetid://100619205187721",
		scrollWaterBackground = true,
	},
}

local MatchSplashConfig = {}

function MatchSplashConfig.resolveMapIdFromPlaceId(placeId: number): string?
	for _, map in MatchMaps.getAll() do
		if map.placeId == placeId and map.placeId ~= 0 then
			return map.id
		end
	end
	return nil
end

function MatchSplashConfig.getActiveMapId(): string
	-- Published place id wins over a copied Fish Frenzy ActiveMapId ("main").
	local fromPlace = MatchSplashConfig.resolveMapIdFromPlaceId(game.PlaceId)
	if fromPlace then
		return fromPlace
	end
	local ch = ReplicatedStorage:FindFirstChild(ACTIVE_MAP_ID_NAME)
	if ch and ch:IsA("StringValue") and ch.Value ~= "" then
		return ch.Value
	end
	return DEFAULT_MAP_ID
end

function MatchSplashConfig.ensureActiveMapIdOnServer(): ()
	local mapId = MatchSplashConfig.getActiveMapId()
	local ch = ReplicatedStorage:FindFirstChild(ACTIVE_MAP_ID_NAME)
	if not ch or not ch:IsA("StringValue") then
		ch = Instance.new("StringValue")
		ch.Name = ACTIVE_MAP_ID_NAME
		ch.Parent = ReplicatedStorage
	end
	local sv = ch :: StringValue
	if sv.Value ~= mapId then
		sv.Value = mapId
	end
end

function MatchSplashConfig.getForMapId(mapId: string): SplashVisual
	local config = byMapId[mapId]
	if config then
		return config
	end
	return byMapId[DEFAULT_MAP_ID]
end

function MatchSplashConfig.getForActiveMap(): SplashVisual
	return MatchSplashConfig.getForMapId(MatchSplashConfig.getActiveMapId())
end

function MatchSplashConfig.isBillboardMode(visual: SplashVisual): boolean
	return visual.mode == "billboard_png"
end

function MatchSplashConfig.getSandCoverImageId(): string
	local visual = MatchSplashConfig.getForActiveMap()
	return visual.sandCoverImageId or DEFAULT_SAND_COVER
end

function MatchSplashConfig.getReelLeafImageId(): string?
	local visual = MatchSplashConfig.getForActiveMap()
	return visual.reelLeafImageId
end

function MatchSplashConfig.getSplashFrameIds(mapId: string?): { string }?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local frames = visual.splashFrameIds
	if frames and #frames >= 2 then
		return frames
	end
	return nil
end

function MatchSplashConfig.getRareTargetFrameIds(mapId: string?): { string }?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local frames = visual.rareTargetFrameIds
	if frames and #frames >= 1 then
		return frames
	end
	return nil
end

function MatchSplashConfig.getRareTargetSpawnChance(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.rareTargetSpawnChance or DEFAULT_RARE_TARGET_SPAWN_CHANCE
end

function MatchSplashConfig.getCommonTargetStuds(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.commonTargetStuds or DEFAULT_COMMON_TARGET_STUDS
end

function MatchSplashConfig.getRareTargetStuds(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.rareTargetStuds or DEFAULT_RARE_TARGET_STUDS
end

function MatchSplashConfig.getRareTargetArtYawOffsetRad(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.rareTargetArtYawOffsetRad or 0
end

function MatchSplashConfig.getRareTargetSwimSpeedStudsPerSec(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.rareTargetSwimSpeedStudsPerSec or DEFAULT_RARE_TARGET_SWIM_SPEED
end

local function rollCashReward(minCash: number?, maxCash: number?, defaultMin: number, defaultMax: number): number
	local resolvedMin = if typeof(minCash) == "number" then minCash else defaultMin
	local resolvedMax = if typeof(maxCash) == "number" then maxCash else defaultMax
	return math.random(math.floor(resolvedMin), math.max(math.floor(resolvedMax), math.floor(resolvedMin)))
end

function MatchSplashConfig.rollCommonTargetCashReward(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return rollCashReward(visual.commonTargetCashMin, visual.commonTargetCashMax, DEFAULT_COMMON_TARGET_CASH_MIN, DEFAULT_COMMON_TARGET_CASH_MAX)
end

function MatchSplashConfig.rollLargeTargetCashReward(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return rollCashReward(visual.largeTargetCashMin, visual.largeTargetCashMax, DEFAULT_LARGE_TARGET_CASH_MIN, DEFAULT_LARGE_TARGET_CASH_MAX)
end

function MatchSplashConfig.rollRareTargetCashReward(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return rollCashReward(visual.rareTargetCashMin, visual.rareTargetCashMax, DEFAULT_RARE_TARGET_CASH_MIN, DEFAULT_RARE_TARGET_CASH_MAX)
end

function MatchSplashConfig.rollLegendaryTargetCashReward(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return rollCashReward(visual.legendaryTargetCashMin, visual.legendaryTargetCashMax, DEFAULT_LEGENDARY_TARGET_CASH_MIN, DEFAULT_LEGENDARY_TARGET_CASH_MAX)
end

function MatchSplashConfig.getLegendaryTargetImageId(mapId: string?): string?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local id = visual.legendaryTargetImageId
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

function MatchSplashConfig.getBoatPatrolZSignFromSwimYaw(swimYaw: number): number
	if math.abs(swimYaw - math.pi) < math.abs(swimYaw) then
		return -1
	end
	return 1
end

function MatchSplashConfig.getLegendaryTargetCoverImageIdForZSign(
	mapId: string?,
	zSign: number,
	duringMonsterStorm: boolean?
): string?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	if duringMonsterStorm then
		if zSign < 0 then
			local stormInverted = visual.legendaryTargetStormImageIdInverted
			if typeof(stormInverted) == "string" and stormInverted ~= "" then
				return stormInverted
			end
		else
			local stormId = visual.legendaryTargetStormImageId
			if typeof(stormId) == "string" and stormId ~= "" then
				return stormId
			end
		end
	end
	if zSign < 0 then
		local inverted = visual.legendaryTargetImageIdInverted
		if typeof(inverted) == "string" and inverted ~= "" then
			return inverted
		end
	end
	local id = visual.legendaryTargetImageId
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

function MatchSplashConfig.getLegendaryTargetStuds(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.legendaryTargetStuds or DEFAULT_LEGENDARY_TARGET_STUDS
end

function MatchSplashConfig.getLegendaryTargetRespawnDelayMinSec(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.legendaryTargetRespawnDelayMinSec or DEFAULT_LEGENDARY_RESPAWN_DELAY_MIN
end

function MatchSplashConfig.getLegendaryTargetRespawnDelayMaxSec(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.legendaryTargetRespawnDelayMaxSec or DEFAULT_LEGENDARY_RESPAWN_DELAY_MAX
end

function MatchSplashConfig.getLegendaryTargetArtYawOffsetRad(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.legendaryTargetArtYawOffsetRad or 0
end

function MatchSplashConfig.getLegendaryTargetSwimSpeedStudsPerSec(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.legendaryTargetSwimSpeedStudsPerSec or DEFAULT_LEGENDARY_SWIM_SPEED
end

function MatchSplashConfig.getLegendaryTargetHealthMin(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.legendaryTargetHealthMin or DEFAULT_LEGENDARY_TARGET_HEALTH_MIN
end

function MatchSplashConfig.getLegendaryTargetHealthMax(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.legendaryTargetHealthMax or DEFAULT_LEGENDARY_TARGET_HEALTH_MAX
end

function MatchSplashConfig.getLegendaryTargetWakeFrameIds(mapId: string?): { string }?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local wake = visual.legendaryTargetWakeFrameIds
	if wake and #wake >= 1 then
		return wake
	end
	return MatchSplashConfig.getSplashFrameIds(mapId)
end

function MatchSplashConfig.getJackpotTargetEmergenceFrameIds(mapId: string?): { string }?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local frames = visual.jackpotTargetEmergenceFrameIds
	if frames and #frames >= 2 then
		return frames
	end
	return nil
end

function MatchSplashConfig.getJackpotTargetStuds(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.jackpotTargetStuds or DEFAULT_JACKPOT_TARGET_STUDS
end

function MatchSplashConfig.getJackpotTargetRespawnDelayMinSec(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.jackpotTargetRespawnDelayMinSec or DEFAULT_JACKPOT_RESPAWN_DELAY_MIN
end

function MatchSplashConfig.getJackpotTargetRespawnDelayMaxSec(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.jackpotTargetRespawnDelayMaxSec or DEFAULT_JACKPOT_RESPAWN_DELAY_MAX
end

function MatchSplashConfig.getJackpotTargetHealthMin(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.jackpotTargetHealthMin or DEFAULT_JACKPOT_TARGET_HEALTH_MIN
end

function MatchSplashConfig.getJackpotTargetHealthMax(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.jackpotTargetHealthMax or DEFAULT_JACKPOT_TARGET_HEALTH_MAX
end

function MatchSplashConfig.getJackpotTargetAnimStepSec(_mapId: string?): number
	return JACKPOT_MONSTER_FRAME_STEP_SEC
end

function MatchSplashConfig.getJackpotTargetIdleAnimStepSec(_mapId: string?): number
	return JACKPOT_MONSTER_IDLE_FRAME_STEP_SEC
end

function MatchSplashConfig.getJackpotTargetIdleLifetimeSec(_mapId: string?): number
	return DEFAULT_JACKPOT_IDLE_LIFETIME_SEC
end

function MatchSplashConfig.getJackpotTargetSubmergeDurationSec(mapId: string?): number
	local frames = MatchSplashConfig.getJackpotTargetEmergenceFrameIds(mapId)
	local count = if frames then #frames else 6
	return count * JACKPOT_MONSTER_FRAME_STEP_SEC
end

function MatchSplashConfig.getJackpotTargetCycleCount(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.jackpotTargetCycleCount or DEFAULT_JACKPOT_CYCLE_COUNT
end

function MatchSplashConfig.getBaseplateStormFrameIds(mapId: string?): { string }?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local frames = visual.baseplateStormFrameIds
	if frames and #frames >= 2 then
		return frames
	end
	return nil
end

function MatchSplashConfig.getBaseplateStormChopRepeatCount(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.baseplateStormChopRepeatCount or DEFAULT_BASEPLATE_STORM_CHOP_REPEAT
end

function MatchSplashConfig.getBaseplateStormFrameStepSec(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.baseplateStormFrameStepSec or DEFAULT_BASEPLATE_STORM_FRAME_STEP_SEC
end

function MatchSplashConfig.getBaseplateNormalTextureId(mapId: string?): string
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.baseplateNormalTextureId or BASEPLATE_NORMAL_TEXTURE
end

function MatchSplashConfig.getBaseplateStormColor(mapId: string?): Color3
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local rgb = visual.baseplateStormColor or BASEPLATE_STORM_COLOR
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

function MatchSplashConfig.getBaseplateStormBrightness(mapId: string?): number
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	return visual.baseplateStormBrightness or DEFAULT_BASEPLATE_STORM_BRIGHTNESS
end

function MatchSplashConfig.getBaseplateStormAmbient(mapId: string?): Color3
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local rgb = visual.baseplateStormAmbient or BASEPLATE_STORM_AMBIENT
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

MatchSplashConfig.DEFAULT_HIT_NET_RED = DEFAULT_HIT_NET_RED

return MatchSplashConfig
