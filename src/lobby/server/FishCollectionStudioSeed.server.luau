--!strict
-- Studio-only: grant 2 fish per tier on the main map for collection / battle testing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local STUDIO_SEED_ENABLED = true
local MAP_ID = "main"
local FISH_PER_TIER = 2
local LOAD_WAIT_SECONDS = 1.5

if not STUDIO_SEED_ENABLED then
	return
end

local shared = ReplicatedStorage:WaitForChild("Shared")
local FishCollectionService = require(shared:WaitForChild("FishCollectionService"))
local SplashFishCatalog = require(shared:WaitForChild("SplashFishCatalog"))

local seededUserIds: { [number]: boolean } = {}

local function mainMapHasFish(userId: number): boolean
	local snapshot = FishCollectionService.getCachedSnapshot(userId)
	local owned = snapshot[MAP_ID]
	return owned ~= nil and next(owned) ~= nil
end

local function seedPlayerCollection(player: Player)
	if seededUserIds[player.UserId] then
		return
	end
	seededUserIds[player.UserId] = true

	task.wait(LOAD_WAIT_SECONDS)

	if not player.Parent then
		return
	end
	if mainMapHasFish(player.UserId) then
		print(string.format("[FishCollectionStudioSeed] Skipping %s — main collection already has fish", player.Name))
		return
	end

	local granted = 0
	for _, tier in SplashFishCatalog.getOrderedTiers() do
		local ids = SplashFishCatalog.getIdsForTier(MAP_ID, tier)
		if #ids == 0 then
			continue
		end
		for i = 1, FISH_PER_TIER do
			local imageId = ids[math.min(i, #ids)]
			local ok = FishCollectionService.grantFishToPlayer(player, MAP_ID, imageId)
			if ok then
				granted += 1
			end
		end
	end

	print(string.format("[FishCollectionStudioSeed] Granted %d fish to %s (2 per tier on %s)", granted, player.Name, MAP_ID))
end

local function onPlayerAdded(player: Player)
	task.spawn(seedPlayerCollection, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
