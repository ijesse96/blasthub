--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FishCollectionStore = require(script.Parent:WaitForChild("FishCollectionStore"))
local SplashKillFishFrames = require(script.Parent:WaitForChild("SplashKillFishFrames"))

export type FishCollectionSnapshot = FishCollectionStore.FishCollectionSnapshot

local SNAPSHOT_REMOTE_NAME = "FishCollectionSnapshot"

local FishCollectionService = {}

local snapshotCacheByUserId: { [number]: FishCollectionSnapshot } = {}
local snapshotRemote: RemoteEvent? = nil

local function ensureServer()
	if not RunService:IsServer() then
		error("[FishCollectionService] Server-only module.")
	end
end

local function ensureSnapshotRemote(): RemoteEvent
	if snapshotRemote and snapshotRemote.Parent then
		return snapshotRemote
	end

	local existing = ReplicatedStorage:FindFirstChild(SNAPSHOT_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		snapshotRemote = existing
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = SNAPSHOT_REMOTE_NAME
	remote.Parent = ReplicatedStorage
	snapshotRemote = remote
	return remote
end

function FishCollectionService.getSnapshotRemoteName(): string
	return SNAPSHOT_REMOTE_NAME
end

function FishCollectionService.getCachedSnapshot(userId: number): FishCollectionSnapshot
	return snapshotCacheByUserId[userId] or {}
end

local function mergeSnapshots(loaded: FishCollectionSnapshot, cached: FishCollectionSnapshot): FishCollectionSnapshot
	local merged: FishCollectionSnapshot = {}
	for mapId, mapOwned in loaded do
		local copy: { [string]: number } = {}
		for imageId, count in mapOwned do
			copy[imageId] = count
		end
		merged[mapId] = copy
	end
	for mapId, cachedOwned in cached do
		local mergedMap = merged[mapId]
		if not mergedMap then
			mergedMap = {}
			merged[mapId] = mergedMap
		end
		for imageId, count in cachedOwned do
			if count > (mergedMap[imageId] or 0) then
				mergedMap[imageId] = count
			end
		end
	end
	return merged
end

local function applyGrantToSnapshot(
	snapshot: FishCollectionSnapshot,
	mapId: string,
	imageId: string,
	newCount: number
)
	local mapOwned = snapshot[mapId]
	if not mapOwned then
		mapOwned = {}
		snapshot[mapId] = mapOwned
	end
	mapOwned[imageId] = newCount
end

function FishCollectionService.pushSnapshot(player: Player, snapshot: FishCollectionSnapshot)
	if not player.Parent then
		return
	end
	local remote = ensureSnapshotRemote()
	remote:FireClient(player, snapshot)
end

function FishCollectionService.loadPlayerCollection(player: Player): FishCollectionSnapshot
	ensureServer()
	local loaded = FishCollectionStore.loadAsync(player.UserId)
	local cached = snapshotCacheByUserId[player.UserId]
	local snapshot = if cached then mergeSnapshots(loaded, cached) else loaded
	snapshotCacheByUserId[player.UserId] = snapshot
	FishCollectionService.pushSnapshot(player, snapshot)
	return snapshot
end

function FishCollectionService.grantFishToPlayer(
	player: Player,
	mapId: string?,
	imageId: string
): (boolean, number, boolean)
	ensureServer()
	if not player.Parent or imageId == "" then
		return false, 0, false
	end

	local resolvedMapId = if typeof(mapId) == "string" and mapId ~= "" then mapId else SplashKillFishFrames.getActiveMapId()
	local ok, newCount, wasFirstDiscovery = FishCollectionStore.grantFishAsync(player.UserId, resolvedMapId, imageId)

	local snapshot = snapshotCacheByUserId[player.UserId]
	if not snapshot then
		snapshot = {}
		snapshotCacheByUserId[player.UserId] = snapshot
	end

	if ok then
		applyGrantToSnapshot(snapshot, resolvedMapId, imageId, newCount)
	else
		local mapOwned = snapshot[resolvedMapId] or {}
		local oldCount = mapOwned[imageId] or 0
		newCount = oldCount + 1
		wasFirstDiscovery = oldCount <= 0
		applyGrantToSnapshot(snapshot, resolvedMapId, imageId, newCount)
		if RunService:IsStudio() then
			warn(
				string.format(
					"[FishCollectionService] Memory-only grant for %s on %s (DataStore save failed)",
					imageId,
					player.Name
				)
			)
		end
	end

	snapshotCacheByUserId[player.UserId] = snapshot
	FishCollectionService.pushSnapshot(player, snapshot)

	return true, newCount, wasFirstDiscovery
end

function FishCollectionService.start()
	ensureServer()
	ensureSnapshotRemote()

	local function onPlayerAdded(player: Player)
		task.spawn(FishCollectionService.loadPlayerCollection, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		snapshotCacheByUserId[player.UserId] = nil
	end)
end

return FishCollectionService
