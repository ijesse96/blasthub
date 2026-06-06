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
	-- Future: separate cover PNG targets for legendary / jackpot.
	legendaryTargetImageId: string?,
	legendaryTargetStuds: number?,
	legendaryTargetRespawnDelayMinSec: number?,
	legendaryTargetRespawnDelayMaxSec: number?,
	legendaryTargetArtYawOffsetRad: number?,
	legendaryTargetSwimSpeedStudsPerSec: number?,
	legendaryTargetHealthMin: number?,
	legendaryTargetHealthMax: number?,
	legendaryTargetWakeFrameIds: { string }?,
	legendaryTargetFrameIds: { string }?,
	jackpotTargetFrameIds: { string }?,
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
local DEFAULT_LEGENDARY_TARGET_STUDS = 50
local DEFAULT_LEGENDARY_RESPAWN_DELAY_MIN = 15
local DEFAULT_LEGENDARY_RESPAWN_DELAY_MAX = 30
local DEFAULT_LEGENDARY_SWIM_SPEED = 8
local DEFAULT_LEGENDARY_TARGET_HEALTH_MIN = 100
local DEFAULT_LEGENDARY_TARGET_HEALTH_MAX = 150
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
		legendaryTargetImageId = LEGENDARY_BOAT_IMAGE,
		legendaryTargetStuds = DEFAULT_LEGENDARY_TARGET_STUDS,
		legendaryTargetRespawnDelayMinSec = DEFAULT_LEGENDARY_RESPAWN_DELAY_MIN,
		legendaryTargetRespawnDelayMaxSec = DEFAULT_LEGENDARY_RESPAWN_DELAY_MAX,
		legendaryTargetArtYawOffsetRad = 0,
		legendaryTargetSwimSpeedStudsPerSec = DEFAULT_LEGENDARY_SWIM_SPEED,
		legendaryTargetHealthMin = DEFAULT_LEGENDARY_TARGET_HEALTH_MIN,
		legendaryTargetHealthMax = DEFAULT_LEGENDARY_TARGET_HEALTH_MAX,
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

function MatchSplashConfig.getLegendaryTargetImageId(mapId: string?): string?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
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

MatchSplashConfig.DEFAULT_HIT_NET_RED = DEFAULT_HIT_NET_RED

return MatchSplashConfig
