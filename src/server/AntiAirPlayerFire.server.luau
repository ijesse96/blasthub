--!strict
-- Spawns player anti-air projectiles on the server so all clients see them and ricochets stay authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Ricochet = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirRicochetProjectile") :: ModuleScript)
local SplashReelConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirSplashReelConfig"))
local HarpoonVisual = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirHarpoonProjectileVisual") :: ModuleScript)
local Money = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Money") :: ModuleScript)
local ConveyorAntiAirBridge = require(script.Parent:WaitForChild("ConveyorAntiAirBridge") :: ModuleScript)
local MatchRoundBridge = require(script.Parent:WaitForChild("MatchRoundBridge"))

local FIRE_REMOTE_NAME = "AntiAirPlayerFire"
local SPLASH_REEL_TAP_REMOTE_NAME = "AntiAirSplashReelTap"
local SPLASH_REEL_METER_REMOTE_NAME = "AntiAirSplashReelMeterState"
local SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME = "SplashKillFishPreload"
local SPLASH_KILL_FISH_IMAGE_ID_ATTRIBUTE = "SplashKillFishImageId"

local BULLET_SPEED = 280
local BULLET_LIFETIME_SEC = 7
local CROSSHAIR_DISTANCE = 5000
local HARPOON_RETRACT_DURATION_SEC = 0.38
local MUZZLE_OFFSET_STUDS = 5
local ANTI_AIR_NAME_PREFIX = "Anti Air"
-- Client-only turret rotation does not replicate; they send spawn + aim. Reject absurd values.
local MAX_SPAWN_OFFSET_FROM_SERVER_GUNPART = 85
local MAX_AIM_DIRECTION_Y = 0.42
local PLAYER_PROJECTILES_FOLDER_NAME = "AntiAirPlayerProjectiles"
local SHOT_COST_AMOUNT = 1
local IS_WATER_SPLASH_ATTRIBUTE = "IsWaterSplash"
local WATER_SPLASHES_FOLDER_NAME = "WaterSplashes"
local MAX_CHOSEN_SPLASH_DISTANCE_FROM_GUN = 500

local METER_START = 0.15
local TAP_GAIN = 0.12
local DECAY_PER_SECOND = 0.1
local TAP_COOLDOWN_SEC = 0.07
local METER_FULL_EPS = 0.001
local METER_EMPTY_EPS = 0.001

type SplashMeterSession = {
	playerUserId: number,
	projectile: BasePart,
	merge: ConveyorAntiAirBridge.PostHitRetract,
	meter: number,
	lastTapClock: number,
	lastMeterSentClock: number,
}

type PlayerSessionRow = {
	player: Player,
	session: SplashMeterSession,
}

local pendingSplashByUserId: { [number]: SplashMeterSession } = {}

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
ensureRemoteEvent(SPLASH_REEL_TAP_REMOTE_NAME)
ensureRemoteEvent(SPLASH_REEL_METER_REMOTE_NAME)

local fireRemote = ReplicatedStorage:WaitForChild(FIRE_REMOTE_NAME) :: RemoteEvent
local splashReelTapRemote = ReplicatedStorage:WaitForChild(SPLASH_REEL_TAP_REMOTE_NAME) :: RemoteEvent
local splashReelMeterRemote = ReplicatedStorage:WaitForChild(SPLASH_REEL_METER_REMOTE_NAME) :: RemoteEvent

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

local function fireMeterUpdate(player: Player, session: SplashMeterSession, force: boolean)
	local now = os.clock()
	if not force and (now - session.lastMeterSentClock) < 0.06 then
		return
	end
	session.lastMeterSentClock = now
	splashReelMeterRemote:FireClient(player, true, session.meter)
end

local function forfeitSplashSession(player: Player, session: SplashMeterSession)
	Ricochet.releaseDeferredRetract(session.projectile)
	local fm = session.merge.retractFollowModel
	if fm and fm.Parent then
		fm:Destroy()
	end
	if session.projectile.Parent then
		session.projectile:Destroy()
	end
	if pendingSplashByUserId[player.UserId] == session then
		pendingSplashByUserId[player.UserId] = nil
	end
	splashReelMeterRemote:FireClient(player, false, 0)
end

local function completeSplashSession(player: Player, session: SplashMeterSession)
	if pendingSplashByUserId[player.UserId] ~= session then
		return
	end
	pendingSplashByUserId[player.UserId] = nil
	splashReelMeterRemote:FireClient(player, false, 0)
	local followModel = session.merge.retractFollowModel
	if followModel and followModel:IsA("Model") then
		local imageId = followModel:GetAttribute(SPLASH_KILL_FISH_IMAGE_ID_ATTRIBUTE)
		if typeof(imageId) == "string" and imageId ~= "" then
			local preloadRemote = ReplicatedStorage:FindFirstChild(SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME)
			if preloadRemote and preloadRemote:IsA("RemoteEvent") then
				preloadRemote:FireClient(player, imageId)
			end
		end
	end
	Ricochet.beginDeferredRetract(session.projectile)
end

RunService.Heartbeat:Connect(function(dt)
	local toForfeit: { PlayerSessionRow } = {}
	local toComplete: { PlayerSessionRow } = {}
	local orphanSessions: { SplashMeterSession } = {}

	for userId, session in pairs(pendingSplashByUserId) do
		local plr = Players:GetPlayerByUserId(userId)
		if not plr then
			table.insert(orphanSessions, session)
		elseif not session.projectile.Parent or not getPlayerTurretModel(plr) then
			table.insert(toForfeit, { player = plr, session = session })
		else
			session.meter = math.max(0, session.meter - DECAY_PER_SECOND * dt)
			fireMeterUpdate(plr, session, false)
			if session.meter <= METER_EMPTY_EPS then
				table.insert(toForfeit, { player = plr, session = session })
			elseif session.meter >= 1 - METER_FULL_EPS then
				table.insert(toComplete, { player = plr, session = session })
			end
		end
	end

	for _, session in orphanSessions do
		Ricochet.releaseDeferredRetract(session.projectile)
		local fm = session.merge.retractFollowModel
		if fm and fm.Parent then
			fm:Destroy()
		end
		if session.projectile.Parent then
			session.projectile:Destroy()
		end
		pendingSplashByUserId[session.playerUserId] = nil
	end

	for _, row in toForfeit do
		if pendingSplashByUserId[row.player.UserId] == row.session then
			forfeitSplashSession(row.player, row.session)
		end
	end
	for _, row in toComplete do
		if pendingSplashByUserId[row.player.UserId] == row.session then
			completeSplashSession(row.player, row.session)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local session = pendingSplashByUserId[player.UserId]
	if session then
		Ricochet.releaseDeferredRetract(session.projectile)
		local fm = session.merge.retractFollowModel
		if fm and fm.Parent then
			fm:Destroy()
		end
		if session.projectile.Parent then
			session.projectile:Destroy()
		end
		pendingSplashByUserId[player.UserId] = nil
	end
end)

splashReelTapRemote.OnServerEvent:Connect(function(player: Player)
	if not player or not player:IsA("Player") then
		return
	end
	local session = pendingSplashByUserId[player.UserId]
	if not session then
		return
	end
	if not session.projectile.Parent or not getPlayerTurretModel(player) then
		forfeitSplashSession(player, session)
		return
	end
	local now = os.clock()
	if now - session.lastTapClock < TAP_COOLDOWN_SEC then
		return
	end
	session.lastTapClock = now
	session.meter = math.clamp(session.meter + TAP_GAIN, 0, 1)
	fireMeterUpdate(player, session, true)
	if session.meter >= 1 - METER_FULL_EPS then
		completeSplashSession(player, session)
	end
end)

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
	local chosenSplash = validateChosenWaterSplash(clientChosenSplash, gunpart)

	attachBulletTag(projectile, gunpart)

	local raycastExclude: { Instance } = { turret }
	if player.Character then
		table.insert(raycastExclude, player.Character)
	end

	projectile.Parent = playerProjectilesFolder

	local rope = HarpoonVisual.createRopeController(projectile, gunpart, {
		muzzleStuds = MUZZLE_OFFSET_STUDS,
	})

	Ricochet.start(projectile, direction, Workspace, RunService, {
		speed = BULLET_SPEED,
		maxLifetimeSeconds = BULLET_LIFETIME_SEC,
		raycastExclude = raycastExclude,
		chosenWaterSplash = chosenSplash,
		onConveyorHit = function(hitPart: BasePart)
			return ConveyorAntiAirBridge.notifyProjectileConveyorHit(hitPart, projectile, player)
		end,
		retractToPart = gunpart,
		retractDuration = HARPOON_RETRACT_DURATION_SEC,
		retractMuzzleStuds = MUZZLE_OFFSET_STUDS,
		retractOnlyOnHit = true,
		onBounce = function(worldCorner: Vector3)
			rope.addCorner(worldCorner)
		end,
		onSplashReelMeterPending = function(proj: BasePart, merge: ConveyorAntiAirBridge.PostHitRetract)
			if not SplashReelConfig.TAP_TO_REEL_ENABLED then
				Ricochet.beginDeferredRetract(proj)
				return
			end
			local startMeter = METER_START
			pendingSplashByUserId[player.UserId] = {
				playerUserId = player.UserId,
				projectile = proj,
				merge = merge,
				meter = startMeter,
				lastTapClock = 0,
				lastMeterSentClock = 0,
			}
			splashReelMeterRemote:FireClient(player, true, startMeter)
		end,
	})
end

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
	fireForPlayer(
		player,
		if typeof(clientSpawnPos) == "Vector3" then clientSpawnPos else nil,
		if typeof(clientAimUnit) == "Vector3" then clientAimUnit else nil,
		if typeof(clientPredictSeq) == "number" then clientPredictSeq else nil,
		if typeof(clientChosenSplash) == "Instance" then clientChosenSplash else nil
	)
end)
