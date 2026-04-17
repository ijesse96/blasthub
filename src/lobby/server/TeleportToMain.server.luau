local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local PlaceIds = require(ReplicatedStorage.Shared:WaitForChild("PlaceIds"))

local REMOTES_NAME = "LobbyRemotes"
local REQUEST_NAME = "RequestTeleportToMain"

local TELEPORT_COOLDOWN = 2.5
local TELEPORT_DATA = "from_lobby"

local lastRequestAt: { [Player]: number } = {}

local function getOrCreateRemotes(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = REMOTES_NAME
	folder.Parent = ReplicatedStorage

	local remote = Instance.new("RemoteEvent")
	remote.Name = REQUEST_NAME
	remote.Parent = folder

	return folder
end

local function ensureRequestRemote(): RemoteEvent
	local folder = getOrCreateRemotes()
	local remote = folder:FindFirstChild(REQUEST_NAME)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	if remote then
		remote:Destroy()
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = REQUEST_NAME
	remote.Parent = folder
	return remote
end

local function teleportPlayerToMain(player: Player)
	if PlaceIds.MainGame == 0 then
		warn("[Lobby] Set PlaceIds.MainGame in src/shared/PlaceIds.luau before teleporting.")
		return
	end

	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < TELEPORT_COOLDOWN then
		return
	end
	lastRequestAt[player] = now

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(TELEPORT_DATA)

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(PlaceIds.MainGame, { player }, options)
	end)

	if not ok then
		warn(`[Lobby] Teleport failed for {player.Name}: {err}`)
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
end)

ensureRequestRemote().OnServerEvent:Connect(function(player: Player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end
	teleportPlayerToMain(player)
end)
