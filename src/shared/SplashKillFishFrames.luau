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
	DEFAULT_TIER = DEFAULT_TIER,
	getActiveMapId = getActiveMapId,
	getFrameIds = getFrameIds,
	inferTierForImageId = inferTierForImageId,
	pickGameplayImageId = pickGameplayImageId,
	pickGameplayFish = pickGameplayFish,
	pickImageId = pickImageId,
	getFrameCount = getFrameCount,
	applyFullImageToLabel = applyFullImageToLabel,
}
