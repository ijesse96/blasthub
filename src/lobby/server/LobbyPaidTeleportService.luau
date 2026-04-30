local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyStore = require(shared:WaitForChild("EconomyStore"))
local Money = require(shared:WaitForChild("Money"))
local MatchMaps = require(shared:WaitForChild("MatchMaps"))

local REMOTES_NAME = "LobbyRemotes"
local REQUEST_LEGACY_NAME = "RequestTeleportToMain"
local REQUEST_JOIN_MAP_NAME = "RequestJoinMap"
local JOIN_RESULT_NAME = "LobbyJoinResult"

local TELEPORT_COOLDOWN_SECONDS = 2.5

local cooldownByUserId: { [number]: number } = {}
local didBind = false

local M = {}

local function getOrCreateRemotesFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = REMOTES_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local folder = getOrCreateRemotesFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function fireJoinResult(player: Player, ok: boolean, message: string?)
	local resultRemote = ensureRemoteEvent(JOIN_RESULT_NAME)
	resultRemote:FireClient(player, {
		ok = ok,
		message = message,
	})
end

local function canRequestNow(player: Player): boolean
	local now = os.clock()
	local last = cooldownByUserId[player.UserId]
	if last and now - last < TELEPORT_COOLDOWN_SECONDS then
		return false
	end
	cooldownByUserId[player.UserId] = now
	return true
end

function M.attemptJoinMap(player: Player, mapId: string, requestSource: string?)
	if not player or not player:IsDescendantOf(Players) then
		return
	end
	if not canRequestNow(player) then
		return
	end

	local map = MatchMaps.getMapById(mapId)
	if not map then
		fireJoinResult(player, false, "Map unavailable.")
		return
	end
	if map.placeId == 0 then
		warn(string.format("[Lobby] map '%s' has placeId=0", mapId))
		fireJoinResult(player, false, "Map unavailable.")
		return
	end

	local debited, balanceAfter = EconomyStore.tryDebitEntryFeeAsync(player.UserId, map.entryFee)
	if not debited then
		fireJoinResult(player, false, "Not enough coins to enter.")
		return
	end

	local cash = Money.setupPlayer(player)
	cash.Value = math.max(0, math.floor(balanceAfter + 0.5))

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		kind = "match",
		mapId = map.id,
		source = requestSource or "lobby",
	})

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(map.placeId, { player }, options)
	end)
	if not ok then
		warn(string.format("[Lobby] Teleport failed for %s (%s): %s", player.Name, map.id, tostring(err)))
		-- Teleport failed after debit; tell user. Refund policy can be added later.
		fireJoinResult(player, false, "Teleport failed. Try again.")
	end
end

function M.bindRequestRemotes()
	if didBind then
		return
	end
	didBind = true

	local legacyRemote = ensureRemoteEvent(REQUEST_LEGACY_NAME)
	legacyRemote.OnServerEvent:Connect(function(player: Player)
		M.attemptJoinMap(player, "main", "legacy_remote")
	end)

	local joinMapRemote = ensureRemoteEvent(REQUEST_JOIN_MAP_NAME)
	joinMapRemote.OnServerEvent:Connect(function(player: Player, mapId: unknown)
		local requestedMapId = if typeof(mapId) == "string" and mapId ~= "" then mapId else "main"
		M.attemptJoinMap(player, requestedMapId, "join_map_remote")
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		cooldownByUserId[player.UserId] = nil
	end)
end

return M
