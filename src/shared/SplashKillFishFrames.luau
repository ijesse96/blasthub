--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SplashFishCatalog = require(script.Parent:WaitForChild("SplashFishCatalog"))

export type FishTier = SplashFishCatalog.FishTier

local DEFAULT_MAP_ID = "main"
local ACTIVE_MAP_ID_NAME = "ActiveMapId"
local FALLBACK_IMAGE_ID = "rbxassetid://72177555306292"
local IMAGE_ID_ATTRIBUTE = "SplashKillFishImageId"
local RARITY_ATTRIBUTE = "SplashKillFishRarity"
-- Deprecated: atlas frame index; kept for old models, ignored by client VFX.
local FRAME_INDEX_ATTRIBUTE = "SplashKillFishFrameIndex"
local TARGET_KIND_ATTRIBUTE = "SplashTargetKind"
local SWIM_YAW_ATTRIBUTE = "SplashSwimYaw"
local TARGET_KIND_WATER = "water"
local TARGET_KIND_SHARK = "shark"
local TARGET_KIND_BOAT = "boat"
local TARGET_KIND_MONSTER = "monster"
local TARGET_SIZE_TIER_ATTRIBUTE = "SplashTargetSizeTier"
local TARGET_SIZE_COMMON = "common"
local TARGET_SIZE_RARE = "rare"
local TARGET_SIZE_LEGENDARY = "legendary"
local TARGET_SIZE_JACKPOT = "jackpot"
local MONSTER_EVENT_ACTIVE_ATTRIBUTE = "SplashMonsterEventActive"
local BOAT_CALM_COVER_IMAGE_ID_ATTRIBUTE = "SplashBoatCalmCoverImageId"
local MONSTER_PHASE_ATTRIBUTE = "SplashMonsterPhase"
local MONSTER_PHASE_EMERGE = "emerge"
local MONSTER_PHASE_IDLE = "idle"
local MONSTER_PHASE_SUBMERGE = "submerge"

local DEFAULT_TIER: FishTier = "common"

local function getActiveMapId(): string
	local ch = ReplicatedStorage:FindFirstChild(ACTIVE_MAP_ID_NAME)
	if ch and ch:IsA("StringValue") and ch.Value ~= "" then
		return ch.Value
	end
	return DEFAULT_MAP_ID
end

local function getTierList(mapId: string, tier: FishTier): { string }
	local ids = SplashFishCatalog.getIdsForTier(mapId, tier)
	if #ids > 0 then
		return ids
	end
	if tier ~= DEFAULT_TIER then
		return SplashFishCatalog.getIdsForTier(mapId, DEFAULT_TIER)
	end
	return {}
end

local function pickFromList(ids: { string }): string
	if #ids == 0 then
		return FALLBACK_IMAGE_ID
	end
	return ids[math.random(1, #ids)]
end

local function getFrameIds(): { string }
	return SplashFishCatalog.getSpawnableIdsForMap(getActiveMapId())
end

local function inferTierForImageId(imageId: string, mapId: string?): FishTier
	local resolvedMapId = mapId or getActiveMapId()
	return SplashFishCatalog.getTierForImageId(resolvedMapId, imageId) or DEFAULT_TIER
end

local function pickGameplayImageId(mapId: string?): string
	local resolvedMapId = mapId or getActiveMapId()
	return pickFromList(SplashFishCatalog.getSpawnableIdsForMap(resolvedMapId))
end

local function pickGameplayFish(mapId: string?): (string, FishTier)
	local imageId = pickGameplayImageId(mapId)
	local tier = inferTierForImageId(imageId, mapId)
	return imageId, tier
end

local function pickCommonSplashFish(mapId: string?): (string, FishTier)
	local resolvedMapId = mapId or getActiveMapId()
	local imageId = pickFromList(SplashFishCatalog.getCommonSpawnableIdsForMap(resolvedMapId))
	local tier = inferTierForImageId(imageId, mapId)
	return imageId, tier
end

local function pickRareTargetFish(mapId: string?): (string, FishTier)
	local resolvedMapId = mapId or getActiveMapId()
	local ids = SplashFishCatalog.getRarePlusSpawnableIdsForMap(resolvedMapId)
	if #ids == 0 then
		return pickCommonSplashFish(mapId)
	end
	local imageId = pickFromList(ids)
	local tier = inferTierForImageId(imageId, mapId)
	return imageId, tier
end

local function pickRareSplashFish(mapId: string?): (string, FishTier)
	local resolvedMapId = mapId or getActiveMapId()
	local ids = SplashFishCatalog.getRareSpawnableIdsForMap(resolvedMapId)
	if #ids == 0 then
		return pickCommonSplashFish(mapId)
	end
	local imageId = pickFromList(ids)
	local tier = inferTierForImageId(imageId, mapId)
	return imageId, tier
end

local function pickLegendarySplashFish(mapId: string?): (string, FishTier)
	local resolvedMapId = mapId or getActiveMapId()
	local ids = SplashFishCatalog.getLegendarySpawnableIdsForMap(resolvedMapId)
	if #ids == 0 then
		return pickRareSplashFish(mapId)
	end
	local imageId = pickFromList(ids)
	local tier = inferTierForImageId(imageId, mapId)
	return imageId, tier
end

local function pickJackpotSplashFish(mapId: string?): (string, FishTier)
	local resolvedMapId = mapId or getActiveMapId()
	local ids = SplashFishCatalog.getJackpotSpawnableIdsForMap(resolvedMapId)
	if #ids == 0 then
		return pickLegendarySplashFish(mapId)
	end
	local imageId = pickFromList(ids)
	local tier = inferTierForImageId(imageId, mapId)
	return imageId, tier
end

local function pickImageId(tier: FishTier?): string
	local mapId = getActiveMapId()
	local resolvedTier = tier or DEFAULT_TIER
	return pickFromList(getTierList(mapId, resolvedTier))
end

local function getFrameCount(): number
	return #getFrameIds()
end

local function applyFullImageToLabel(label: ImageLabel)
	label.ImageRectOffset = Vector2.zero
	label.ImageRectSize = Vector2.zero
end

return {
	DEFAULT_MAP_ID = DEFAULT_MAP_ID,
	ACTIVE_MAP_ID_NAME = ACTIVE_MAP_ID_NAME,
	FALLBACK_IMAGE_ID = FALLBACK_IMAGE_ID,
	IMAGE_ID_ATTRIBUTE = IMAGE_ID_ATTRIBUTE,
	RARITY_ATTRIBUTE = RARITY_ATTRIBUTE,
	FRAME_INDEX_ATTRIBUTE = FRAME_INDEX_ATTRIBUTE,
	TARGET_KIND_ATTRIBUTE = TARGET_KIND_ATTRIBUTE,
	SWIM_YAW_ATTRIBUTE = SWIM_YAW_ATTRIBUTE,
	TARGET_KIND_WATER = TARGET_KIND_WATER,
	TARGET_KIND_SHARK = TARGET_KIND_SHARK,
	TARGET_KIND_BOAT = TARGET_KIND_BOAT,
	TARGET_KIND_MONSTER = TARGET_KIND_MONSTER,
	TARGET_SIZE_TIER_ATTRIBUTE = TARGET_SIZE_TIER_ATTRIBUTE,
	TARGET_SIZE_COMMON = TARGET_SIZE_COMMON,
	TARGET_SIZE_RARE = TARGET_SIZE_RARE,
	TARGET_SIZE_LEGENDARY = TARGET_SIZE_LEGENDARY,
	TARGET_SIZE_JACKPOT = TARGET_SIZE_JACKPOT,
	MONSTER_EVENT_ACTIVE_ATTRIBUTE = MONSTER_EVENT_ACTIVE_ATTRIBUTE,
	BOAT_CALM_COVER_IMAGE_ID_ATTRIBUTE = BOAT_CALM_COVER_IMAGE_ID_ATTRIBUTE,
	MONSTER_PHASE_ATTRIBUTE = MONSTER_PHASE_ATTRIBUTE,
	MONSTER_PHASE_EMERGE = MONSTER_PHASE_EMERGE,
	MONSTER_PHASE_IDLE = MONSTER_PHASE_IDLE,
	MONSTER_PHASE_SUBMERGE = MONSTER_PHASE_SUBMERGE,
	DEFAULT_TIER = DEFAULT_TIER,
	getActiveMapId = getActiveMapId,
	getFrameIds = getFrameIds,
	inferTierForImageId = inferTierForImageId,
	pickGameplayImageId = pickGameplayImageId,
	pickGameplayFish = pickGameplayFish,
	pickCommonSplashFish = pickCommonSplashFish,
	pickRareTargetFish = pickRareTargetFish,
	pickRareSplashFish = pickRareSplashFish,
	pickLegendarySplashFish = pickLegendarySplashFish,
	pickJackpotSplashFish = pickJackpotSplashFish,
	pickImageId = pickImageId,
	getFrameCount = getFrameCount,
	applyFullImageToLabel = applyFullImageToLabel,
}
