--!strict
-- Server-authoritative player anti-air projectile spawning.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Ricochet = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirRicochetProjectile") :: ModuleScript)
local Money = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Money") :: ModuleScript)
local ConveyorAntiAirBridge = require(script.Parent:WaitForChild("ConveyorAntiAirBridge") :: ModuleScript)
local MatchRoundBridge = require(script.Parent:WaitForChild("MatchRoundBridge"))

local BULLET_SPEED = 280
local BULLET_LIFETIME_SEC = 7
local CROSSHAIR_DISTANCE = 5000
local MUZZLE_OFFSET_STUDS = 5
local ANTI_AIR_NAME_PREFIX = "Anti Air"
local MAX_SPAWN_OFFSET_FROM_SERVER_GUNPART = 85
local MAX_AIM_DIRECTION_Y = 0.42
local PLAYER_PROJECTILES_FOLDER_NAME = "AntiAirPlayerProjectiles"
local SHOT_COST_AMOUNT = 0
local IS_WATER_SPLASH_ATTRIBUTE = "IsWaterSplash"
local WATER_SPLASHES_FOLDER_NAME = "WaterSplashes"
local MAX_CHOSEN_SPLASH_DISTANCE_FROM_GUN = 500

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

local function playerHasLiveProjectile(userId: number): boolean
	for _, child in playerProjectilesFolder:GetChildren() do
		if child:IsA("BasePart") and child.Name == "AntiAirPlayerProjectile" then
			if child:GetAttribute("AntiAirPredictOwner") == userId then
				return true
			end
		end
	end
	return false
end

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

local function validateChosenWaterSplash(model: Instance?, gunpart: BasePart): Model?
	if not model or not model:IsA("Model") then
		return nil
	end
	if model:GetAttribute(IS_WATER_SPLASH_ATTRIBUTE) ~= true then
		return nil
	end
	local folder = Workspace:FindFirstChild(WATER_SPLASHES_FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		return nil
	end
	if not model:IsDescendantOf(folder) then
		return nil
	end
	if (model:GetPivot().Position - gunpart.Position).Magnitude > MAX_CHOSEN_SPLASH_DISTANCE_FROM_GUN then
		return nil
	end
	return model
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

local function fireForPlayer(
	player: Player,
	clientSpawnPos: Vector3?,
	clientAimUnit: Vector3?,
	clientPredictSeq: number?,
	clientChosenSplash: Instance?
)
	if not MatchRoundBridge.allowShooting(player) then
		return
	end

	if playerHasLiveProjectile(player.UserId) then
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

	local cash = Money.setupPlayer(player)
	if cash.Value < SHOT_COST_AMOUNT then
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
		spawnPos = gunpart.Position + (gunpart.CFrame.LookVector * MUZZLE_OFFSET_STUDS)
	end

	Money.subtractCash(player, SHOT_COST_AMOUNT)
	MatchRoundBridge.recordCoinSpent(player, SHOT_COST_AMOUNT)

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
	projectile.Size = Vector3.new(0.4, 0.4, 9)
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
	local chosenSplash = validateChosenWaterSplash(clientChosenSplash, gunpart)

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
		chosenWaterSplash = chosenSplash,
		onConveyorHit = function(hitPart: BasePart)
			return ConveyorAntiAirBridge.notifyProjectileConveyorHit(hitPart, projectile, player)
		end,
	})
end

return {
	SHOT_COST_AMOUNT = SHOT_COST_AMOUNT,
	MAX_AIM_DIRECTION_Y = MAX_AIM_DIRECTION_Y,
	fireForPlayer = fireForPlayer,
	getPlayerTurretModel = getPlayerTurretModel,
	playerHasLiveProjectile = playerHasLiveProjectile,
}
