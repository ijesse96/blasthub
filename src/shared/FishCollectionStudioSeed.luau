--!strict
-- Studio-only: ensure test fish exist on the main map (collection + battle).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FishCollectionService = require(script.Parent:WaitForChild("FishCollectionService"))
local SplashFishCatalog = require(script.Parent:WaitForChild("SplashFishCatalog"))

local MAP_ID = "main"
local FISH_PER_TIER = 2
local COPIES_PER_FISH = 2

local started = false
local seededUserIds: { [number]: boolean } = {}

local M = {}

local function copyCount(userId: number, imageId: string): number
	local snapshot = FishCollectionService.getCachedSnapshot(userId)
	local owned = snapshot[MAP_ID]
	if not owned then
		return 0
	end
	return owned[imageId] or 0
end

function M.seedPlayer(player: Player): number
	if not RunService:IsStudio() or not player.Parent then
		return 0
	end

	FishCollectionService.loadPlayerCollection(player)

	local granted = 0
	for _, tier in SplashFishCatalog.getOrderedTiers() do
		local ids = SplashFishCatalog.getIdsForTier(MAP_ID, tier)
		if #ids == 0 then
			continue
		end
		for i = 1, FISH_PER_TIER do
			local imageId = ids[math.min(i, #ids)]
			while copyCount(player.UserId, imageId) < COPIES_PER_FISH do
				local ok = FishCollectionService.grantFishToPlayer(player, MAP_ID, imageId)
				if not ok then
					break
				end
				granted += 1
			end
		end
	end

	return granted
end

function M.start()
	if not RunService:IsStudio() or started then
		return
	end
	started = true

	local function onPlayerAdded(player: Player)
		if seededUserIds[player.UserId] then
			return
		end
		seededUserIds[player.UserId] = true
		task.defer(function()
			local granted = M.seedPlayer(player)
			print(
				string.format(
					"[FishCollectionStudioSeed] %s — granted %d copies (%d per tier, %d copies each on %s)",
					player.Name,
					granted,
					FISH_PER_TIER,
					COPIES_PER_FISH,
					MAP_ID
				)
			)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		seededUserIds[player.UserId] = nil
	end)
end

return M
