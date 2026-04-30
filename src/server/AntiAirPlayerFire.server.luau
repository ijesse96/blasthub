--!strict
-- Spawns player anti-air projectiles on the server so all clients see them and ricochets stay authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Ricochet = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirRicochetProjectile") :: ModuleScript)
local ConveyorAntiAirBridge = require(script.Parent:WaitForChild("ConveyorAntiAirBridge") :: ModuleScript)
local MatchRoundBridge = require(script.Parent:WaitForChild("MatchRoundBridge"))

local FIRE_REMOTE_NAME = "AntiAirPlayerFire"
local BULLET_SPEED = 600
local BULLET_LIFETIME_SEC = 7
local CROSSHAIR_DISTANCE = 5000
local MIN_FIRE_INTERVAL = 0.2
local ANTI_AIR_NAME_PREFIX = "Anti Air"
-- Client-only turret rotation does not replicate; they send spawn + aim. Reject absurd values.
local MAX_SPAWN_OFFSET_FROM_SERVER_GUNPART = 85
local MAX_AIM_DIRECTION_Y = 0.42
local PLAYER_PROJECTILES_FOLDER_NAME = "AntiAirPlayerProjectiles"

local function getOrCreatePlayerProjectilesFolder(): Folder
	local existing = Workspace:FindFirstChild(PLAYER_PROJECTILES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = PLAYER_PROJECTILES_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local playerProjectilesFolder = getOrCreatePlayerProjectilesFolder()

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

local lastFireAtByUserId: { [number]: number } = {}

local function isAntiAirTurretModel(model: Model): boolean
	return string.find(model.Name, "^" .. ANTI_AIR_NAME_PREFIX) ~= nil
end

local function getPlayerTurretModel(player: Player): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.SeatPart then
		return nil
	end
	local current: Instance? = humanoid.SeatPart.Parent
	while current do
		if current:IsA("Model") and isAntiAirTurretModel(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function attachBulletTag(projectile: BasePart, sourcePart: BasePart)
	local bullet = Instance.new("Folder")
	bullet.Name = "bullet"
	local value = Instance.new("ObjectValue")
	value.Name = "Value"
	value.Value = sourcePart
	value.Parent = bullet
	bullet.Parent = projectile
end

local function fireForPlayer(player: Player, clientSpawnPos: Vector3?, clientAimUnit: Vector3?, clientPredictSeq: number?)
	if not MatchRoundBridge.allowShooting(player) then
		return
	end

	local turret = getPlayerTurretModel(player)
	if not turret then
		return
	end

	local gunFolder = turret:FindFirstChild("gun")
	if not gunFolder or not gunFolder:IsA("Model") then
		return
	end

	local gunpart = gunFolder:FindFirstChild("gunpart")
	if not gunpart or not gunpart:IsA("BasePart") then
		return
	end

	local now = os.clock()
	local last = lastFireAtByUserId[player.UserId]
	if last and (now - last) < MIN_FIRE_INTERVAL then
		return
	end

	local aimLook: Vector3
	if typeof(clientAimUnit) == "Vector3" and clientAimUnit.Magnitude > 1e-4 then
		aimLook = clientAimUnit.Unit
	else
		aimLook = gunpart.CFrame.LookVector
		if aimLook.Magnitude > 1e-5 then
			aimLook = aimLook.Unit
		else
			aimLook = Vector3.new(0, 0, -1)
		end
	end

	if math.abs(aimLook.Y) > MAX_AIM_DIRECTION_Y then
		return
	end

	local spawnPos: Vector3
	if typeof(clientSpawnPos) == "Vector3" then
		if (clientSpawnPos - gunpart.Position).Magnitude > MAX_SPAWN_OFFSET_FROM_SERVER_GUNPART then
			return
		end
		spawnPos = clientSpawnPos
	else
		spawnPos = gunpart.Position + (gunpart.CFrame.LookVector * 5)
	end

	lastFireAtByUserId[player.UserId] = now

	local effect = gunFolder:FindFirstChild("effect")
	if effect then
		local bam = effect:FindFirstChild("bam")
		if bam and bam:IsA("Sound") then
			bam:Play()
		end
	end

	local aimPoint = spawnPos + aimLook * CROSSHAIR_DISTANCE

	local projectile = Instance.new("Part")
	projectile.Name = "AntiAirPlayerProjectile"
	projectile.Size = Vector3.new(0.4, 0.4, 22)
	projectile.CFrame = CFrame.new(spawnPos, aimPoint)
	projectile.BrickColor = BrickColor.new("Really red")
	projectile.Material = Enum.Material.Neon
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.Anchored = true

	projectile:SetAttribute("AntiAirPredictOwner", player.UserId)
	if typeof(clientPredictSeq) == "number" and clientPredictSeq > 0 and clientPredictSeq == math.floor(clientPredictSeq) then
		projectile:SetAttribute("AntiAirPredictSeq", clientPredictSeq)
	end

	local direction = aimLook

	attachBulletTag(projectile, gunpart)

	local raycastExclude: { Instance } = { turret }
	if player.Character then
		table.insert(raycastExclude, player.Character)
	end

	projectile.Parent = playerProjectilesFolder

	Ricochet.start(projectile, direction, Workspace, RunService, {
		speed = BULLET_SPEED,
		maxLifetimeSeconds = BULLET_LIFETIME_SEC,
		raycastExclude = raycastExclude,
		onConveyorHit = function(hitPart: BasePart)
			ConveyorAntiAirBridge.notifyProjectileConveyorHit(hitPart, projectile, player)
		end,
	})
end

fireRemote.OnServerEvent:Connect(function(player: Player, clientSpawnPos: unknown?, clientAimUnit: unknown?, clientPredictSeq: unknown?)
	if not player or not player:IsA("Player") then
		return
	end
	fireForPlayer(
		player,
		if typeof(clientSpawnPos) == "Vector3" then clientSpawnPos else nil,
		if typeof(clientAimUnit) == "Vector3" then clientAimUnit else nil,
		if typeof(clientPredictSeq) == "number" then clientPredictSeq else nil
	)
end)

Players.PlayerRemoving:Connect(function(player)
	lastFireAtByUserId[player.UserId] = nil
end)
