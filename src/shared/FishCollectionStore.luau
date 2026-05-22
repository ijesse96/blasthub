--!strict
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local SplashFishCatalog = require(script.Parent:WaitForChild("SplashFishCatalog"))

export type FishCollectionSnapshot = { [string]: { [string]: number } }

local STORE_NAME = "FishCollection_v1"
local MAX_COPIES_PER_FISH = 9999

local store = DataStoreService:GetDataStore(STORE_NAME)

local FishCollectionStore = {}

local function ensureServer()
	if not RunService:IsServer() then
		error("[FishCollectionStore] Server-only module.")
	end
end

local function keyForUserId(userId: number): string
	return string.format("fish_collection_%d", userId)
end

local function clampCount(amount: number): number
	return math.clamp(math.max(0, math.floor(amount + 0.5)), 0, MAX_COPIES_PER_FISH)
end

local function emptySnapshot(): FishCollectionSnapshot
	return {}
end

function FishCollectionStore.sanitizeSnapshot(raw: unknown): FishCollectionSnapshot
	if typeof(raw) ~= "table" then
		return emptySnapshot()
	end

	local snapshot: FishCollectionSnapshot = {}
	for mapId, mapData in raw :: { [string]: any } do
		if typeof(mapId) ~= "string" or mapId == "" or typeof(mapData) ~= "table" then
			continue
		end
		if #SplashFishCatalog.getAllIdsForMap(mapId) == 0 then
			continue
		end

		local owned: { [string]: number } = {}
		for imageId, count in mapData do
			if typeof(imageId) ~= "string" or imageId == "" then
				continue
			end
			if SplashFishCatalog.getTierForImageId(mapId, imageId) == nil then
				continue
			end
			if typeof(count) == "number" then
				local safe = clampCount(count)
				if safe > 0 then
					owned[imageId] = safe
				end
			end
		end

		if next(owned) ~= nil then
			snapshot[mapId] = owned
		end
	end

	return snapshot
end

function FishCollectionStore.loadAsync(userId: number): FishCollectionSnapshot
	ensureServer()
	local ok, value = pcall(function()
		return store:GetAsync(keyForUserId(userId))
	end)
	if not ok then
		warn(string.format("[FishCollectionStore] loadAsync failed for %d: %s", userId, tostring(value)))
		return emptySnapshot()
	end
	return FishCollectionStore.sanitizeSnapshot(value)
end

function FishCollectionStore.grantFishAsync(
	userId: number,
	mapId: string,
	imageId: string
): (boolean, number, boolean)
	ensureServer()

	if mapId == "" or imageId == "" then
		return false, 0, false
	end
	if SplashFishCatalog.getTierForImageId(mapId, imageId) == nil then
		warn(string.format("[FishCollectionStore] grantFishAsync rejected unknown fish %s for map %s", imageId, mapId))
		return false, 0, false
	end

	local newCount = 0
	local wasFirstDiscovery = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyForUserId(userId), function(current: unknown)
			local snapshot = FishCollectionStore.sanitizeSnapshot(current)
			local mapOwned = snapshot[mapId]
			if not mapOwned then
				mapOwned = {}
				snapshot[mapId] = mapOwned
			end

			local oldCount = mapOwned[imageId] or 0
			newCount = clampCount(oldCount + 1)
			wasFirstDiscovery = oldCount <= 0
			mapOwned[imageId] = newCount
			return snapshot
		end)
	end)

	if not ok then
		warn(string.format("[FishCollectionStore] grantFishAsync failed for %d: %s", userId, tostring(err)))
		return false, 0, false
	end

	return true, newCount, wasFirstDiscovery
end

return FishCollectionStore
