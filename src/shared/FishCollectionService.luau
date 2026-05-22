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

function FishCollectionService.pushSnapshot(player: Player, snapshot: FishCollectionSnapshot)
	if not player.Parent then
		return
	end
	local remote = ensureSnapshotRemote()
	remote:FireClient(player, snapshot)
end

function FishCollectionService.loadPlayerCollection(player: Player): FishCollectionSnapshot
	ensureServer()
	local snapshot = FishCollectionStore.loadAsync(player.UserId)
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
	if not ok then
		return false, 0, false
	end

	local snapshot = snapshotCacheByUserId[player.UserId]
	if not snapshot then
		snapshot = FishCollectionStore.loadAsync(player.UserId)
	else
		local mapOwned = snapshot[resolvedMapId]
		if not mapOwned then
			mapOwned = {}
			snapshot[resolvedMapId] = mapOwned
		end
		mapOwned[imageId] = newCount
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
