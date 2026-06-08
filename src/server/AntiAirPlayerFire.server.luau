--!strict
-- Remote handler for client-initiated player turret shots (disabled when manual fire is off).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoFireConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirAutoFireConfig"))
local FireLib = require(script.Parent:WaitForChild("AntiAirPlayerFireLib"))

local FIRE_REMOTE_NAME = "AntiAirPlayerFire"

local function ensureRemoteEvent(name: string)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if not existing then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	elseif not existing:IsA("RemoteEvent") then
		existing:Destroy()
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
end

ensureRemoteEvent(FIRE_REMOTE_NAME)

local fireRemote = ReplicatedStorage:WaitForChild(FIRE_REMOTE_NAME) :: RemoteEvent

fireRemote.OnServerEvent:Connect(function(
	player: Player,
	clientSpawnPos: unknown?,
	clientAimUnit: unknown?,
	clientPredictSeq: unknown?,
	clientChosenSplash: unknown?
)
	if not player or not player:IsA("Player") then
		return
	end
	if not AutoFireConfig.MANUAL_FIRE_ENABLED then
		return
	end
	FireLib.fireForPlayer(
		player,
		if typeof(clientSpawnPos) == "Vector3" then clientSpawnPos else nil,
		if typeof(clientAimUnit) == "Vector3" then clientAimUnit else nil,
		if typeof(clientPredictSeq) == "number" then clientPredictSeq else nil,
		if typeof(clientChosenSplash) == "Instance" then clientChosenSplash else nil
	)
end)
