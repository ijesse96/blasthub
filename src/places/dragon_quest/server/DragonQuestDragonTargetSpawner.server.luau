--!strict
-- Dragon Quest (130967805909090): moving flat-decal dragon targets (shoot / reel like jungle).

local DRAGON_QUEST_PLACE_ID = 130967805909090
local LOG = "[DragonQuestDragonSpawner]"
local SCRIPT_VERSION = 5

print(LOG, "v" .. SCRIPT_VERSION, "loaded PlaceId=" .. tostring(game.PlaceId))

if game.PlaceId ~= DRAGON_QUEST_PLACE_ID then
	return
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not shared then
	warn(LOG, "ReplicatedStorage.Shared missing")
	return
end

local MatchSplashConfig = require(shared:WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(shared:WaitForChild("SplashKillFishFrames"))
local SplashSpawnExclusions = require(shared:WaitForChild("SplashSpawnExclusions"))
local SplashArenaInterior = require(shared:WaitForChild("SplashArenaInterior"))

local dragonSplash = MatchSplashConfig.getForMapId("dragon_quest")
local DRAGON_IMAGE = dragonSplash.imageId or "rbxassetid://117255021260624"
local BILLBOARD_STUDS = dragonSplash.billboardStuds or 14
local FOOTPRINT_BASE_STUDS = BILLBOARD_STUDS * 2
local ANCHOR_THICKNESS = 0.08
local DRAGON_SPLASH_TRANSPARENCY = 0
local FISH_IMAGE_SCALE = dragonSplash.fishBillboardScale or 0.05
local SURFACE_GUI_NAME = "DragonSplashSurface"
local SURFACE_PIXELS_PER_STUD = 32

-- PNG head at image bottom-left (~SW at yaw 0). +180° so head leads travel, not tail.
local ART_YAW_OFFSET_RAD = math.rad(225)

local SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME = "SplashKillFishPreload"

local TEMPLATE_NAME = "DragonFlatSplash"
local STALE_TEMPLATE_NAMES = { "DragonBillboardSplash", "DragonFlatSplash" }
local TEMPLATE_HOLDER_NAME = "DragonSplashTemplate"
local ACTIVE_FOLDER_NAME = "WaterSplashes"

local PATROL_COUNT = 12
local SPAWN_MARGIN = 6
local Y_OFFSET = 0.02
local SPAWN_LIFT_ABOVE_BASEPLATE = 2.5
local HIT_COLLIDER_RADIUS = 14
local HIT_COLLIDER_HEIGHT = 4
local HIT_COLLIDER_NAME = "SplashHitCollider"
local RESPAWN_DELAY_SEC = 1.0

local SCALE_MIN, SCALE_MAX = 0.85, 1.15

local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"
local CONVEYOR_HEALTH_ATTRIBUTE = "ConveyorHealth"
local CONVEYOR_MAX_HEALTH_ATTRIBUTE = "ConveyorMaxHealth"
local CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE = "ConveyorItemCashReward"
local CONVEYOR_SCALE_ATTRIBUTE = "ConveyorSpawnScale"
local IS_WATER_SPLASH_ATTRIBUTE = "IsWaterSplash"

local SPLASH_HEALTH_MIN = 1
local SPLASH_HEALTH_MAX = 3
local SPLASH_CASH_MIN = 1
local SPLASH_CASH_MAX = 5

type PatrolSlot = {
	omegaU: number,
	omegaV: number,
	phaseU: number,
	phaseV: number,
	centerFracX: number,
	centerFracZ: number,
	ampScale: number,
}

local function buildPatrolSlots(count: number): { PatrolSlot }
	local slots: { PatrolSlot } = table.create(count)
	for i = 1, count do
		local seed = i * 2.399963
		slots[i] = {
			omegaU = 0.08 + (i % 5) * 0.018,
			omegaV = 0.09 + (i % 4) * 0.022,
			phaseU = seed * 1.17,
			phaseV = seed * 1.93,
			centerFracX = math.cos(seed) * 0.38,
			centerFracZ = math.sin(seed * 1.31) * 0.38,
			ampScale = 0.62 + (i % 4) * 0.09,
		}
	end
	return slots
end

local PATROL_SLOTS = buildPatrolSlots(PATROL_COUNT)

for _, inst in game:GetDescendants() do
	if inst.Name == "WaterSplashSpawner" and inst:IsA("Script") then
		inst.Enabled = false
		inst:Destroy()
	end
end

MatchSplashConfig.ensureActiveMapIdOnServer()

local function fireSplashKillFishPreloadToAll(imageId: string)
	local remote = ReplicatedStorage:FindFirstChild(SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME)
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	for _, plr in Players:GetPlayers() do
		remote:FireClient(plr, imageId)
	end
end

type ArenaBounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	floorY: number,
	widthX: number,
	depthZ: number,
	centerX: number,
	centerZ: number,
	ampX: number,
	ampZ: number,
	surfaceY: number,
}

type PatrolDragon = {
	model: Model,
	slotIndex: number,
	hitCollider: BasePart,
	lastPos: Vector3?,
	lastYaw: number,
}

local function buildPatrolBounds(): ArenaBounds?
	local inner = SplashArenaInterior.getSpawnBounds()
	if not inner then
		return nil
	end

	local centerX = (inner.minX + inner.maxX) * 0.5
	local centerZ = (inner.minZ + inner.maxZ) * 0.5
	local ampX = math.max(inner.widthX * 0.5 - SPAWN_MARGIN, 8)
	local ampZ = math.max(inner.depthZ * 0.5 - SPAWN_MARGIN, 8)
	local surfaceY = inner.floorY + SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET

	return {
		minX = inner.minX,
		maxX = inner.maxX,
		minZ = inner.minZ,
		maxZ = inner.maxZ,
		floorY = inner.floorY,
		widthX = inner.widthX,
		depthZ = inner.depthZ,
		centerX = centerX,
		centerZ = centerZ,
		ampX = ampX,
		ampZ = ampZ,
		surfaceY = surfaceY,
	}
end

local function ensureTemplateHolder(): Folder
	local existing = ServerStorage:FindFirstChild(TEMPLATE_HOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = TEMPLATE_HOLDER_NAME
	folder.Parent = ServerStorage
	return folder
end

local function buildFlatDragonTemplate(): Model
	local model = Instance.new("Model")
	model.Name = TEMPLATE_NAME

	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(FOOTPRINT_BASE_STUDS, ANCHOR_THICKNESS, FOOTPRINT_BASE_STUDS)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.CastShadow = false
	anchor.Parent = model
	model.PrimaryPart = anchor

	-- Fish preview on SurfaceGui (rotates with patrol yaw).
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = SURFACE_GUI_NAME
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = SURFACE_PIXELS_PER_STUD
	surfaceGui.Parent = anchor

	local fishImage = Instance.new("ImageLabel")
	fishImage.Name = "FishImage"
	fishImage.BackgroundTransparency = 1
	fishImage.AnchorPoint = Vector2.new(0.5, 0.5)
	fishImage.Position = UDim2.fromScale(0.5, 0.5)
	fishImage.Size = UDim2.fromScale(FISH_IMAGE_SCALE, FISH_IMAGE_SCALE)
	fishImage.Image = SplashKillFishFrames.FALLBACK_IMAGE_ID
	fishImage.ScaleType = Enum.ScaleType.Fit
	fishImage.ZIndex = 1
	fishImage.Parent = surfaceGui

	-- Top Decal for dragon silhouette (world-flat; orientation tuned via ART_YAW_OFFSET_RAD).
	local decal = Instance.new("Decal")
	decal.Name = "DragonDecal"
	decal.Face = Enum.NormalId.Top
	decal.Texture = DRAGON_IMAGE
	decal.Transparency = DRAGON_SPLASH_TRANSPARENCY
	decal.Parent = anchor

	return model
end

local function applySpawnFishImage(model: Model, fishImageId: string)
	local anchor = model.PrimaryPart
	if not anchor then
		return
	end
	local surfaceGui = anchor:FindFirstChild(SURFACE_GUI_NAME)
	if not surfaceGui or not surfaceGui:IsA("SurfaceGui") then
		return
	end
	local fishImage = surfaceGui:FindFirstChild("FishImage")
	if fishImage and fishImage:IsA("ImageLabel") then
		fishImage.Image = fishImageId
	end
end

local function getSpawnTemplate(): Model
	local holder = ensureTemplateHolder()
	for _, name in STALE_TEMPLATE_NAMES do
		local stale = holder:FindFirstChild(name)
		if stale then
			stale:Destroy()
		end
	end
	local built = buildFlatDragonTemplate()
	built.Parent = holder
	return built
end

local function sanitizeModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		end
	end
end

local function configureSplashParts(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= HIT_COLLIDER_NAME then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local function applySpawnScale(model: Model, scale: number)
	local anchor = model.PrimaryPart
	if not anchor or not anchor:IsA("BasePart") then
		return
	end
	local footprint = FOOTPRINT_BASE_STUDS * scale
	anchor.Size = Vector3.new(footprint, ANCHOR_THICKNESS, footprint)
end

local function getOrCreateActiveFolder(): Folder
	local existing = Workspace:FindFirstChild(ACTIVE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = ACTIVE_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local PATROL_TURRET_PHASE_STEP = 0.75

local function patrolPosition(bounds: ArenaBounds, slotIndex: number, t: number): Vector3
	local slot = PATROL_SLOTS[slotIndex] or PATROL_SLOTS[((slotIndex - 1) % #PATROL_SLOTS) + 1]
	local cx = bounds.centerX + bounds.ampX * slot.centerFracX
	local cz = bounds.centerZ + bounds.ampZ * slot.centerFracZ
	local ax = bounds.ampX * slot.ampScale
	local az = bounds.ampZ * slot.ampScale
	local x = cx + ax * math.cos(slot.omegaU * t + slot.phaseU)
	local z = cz + az * math.sin(slot.omegaV * t + slot.phaseV)
	x = math.clamp(x, bounds.minX + SPAWN_MARGIN, bounds.maxX - SPAWN_MARGIN)
	z = math.clamp(z, bounds.minZ + SPAWN_MARGIN, bounds.maxZ - SPAWN_MARGIN)
	return Vector3.new(x, bounds.surfaceY, z)
end

local function findPatrolSpawnPosition(bounds: ArenaBounds, slotIndex: number): Vector3
	local t0 = Workspace:GetServerTimeNow()
	for attempt = 0, 10 do
		local t = t0 + attempt * PATROL_TURRET_PHASE_STEP
		local pos = patrolPosition(bounds, slotIndex, t)
		if not SplashSpawnExclusions.isNearTurret(pos) and SplashArenaInterior.isInsideArena(pos) then
			return pos
		end
	end
	return patrolPosition(bounds, slotIndex, t0)
end

local patrolDragons: { PatrolDragon } = {}
local boundsRef: ArenaBounds? = nil
local templateRef: Model? = nil
local activeFolderRef: Folder? = nil
local totalSpawned = 0

local function removePatrolRecord(model: Model)
	for i = #patrolDragons, 1, -1 do
		if patrolDragons[i].model == model then
			table.remove(patrolDragons, i)
			return
		end
	end
end

local function updateHitCollider(hit: BasePart, pos: Vector3)
	hit.CFrame = CFrame.new(pos.X, pos.Y + HIT_COLLIDER_HEIGHT * 0.5, pos.Z)
end

-- ConveyorSystem clears IsConveyorItem when health hits 0 (reel / kill); stop patrol then.
local function isDragonPatrolActive(model: Model): boolean
	if model:GetAttribute(CONVEYOR_ITEM_ATTRIBUTE) ~= true then
		return false
	end
	local hp = model:GetAttribute(CONVEYOR_HEALTH_ATTRIBUTE)
	if typeof(hp) == "number" and hp <= 0 then
		return false
	end
	return true
end

local function spawnPatrolDragon(slotIndex: number): PatrolDragon?
	local bounds = boundsRef
	local template = templateRef
	local activeFolder = activeFolderRef
	if not bounds or not template or not activeFolder then
		return nil
	end

	local clone = template:Clone()
	local model = clone :: Model
	if not model.PrimaryPart then
		model:Destroy()
		return nil
	end

	sanitizeModel(model)
	configureSplashParts(model)

	local scale = SCALE_MIN + (slotIndex - 1) * ((SCALE_MAX - SCALE_MIN) / math.max(PATROL_COUNT - 1, 1))
	applySpawnScale(model, scale)

	local hp = math.random(SPLASH_HEALTH_MIN, SPLASH_HEALTH_MAX)
	model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, true)
	model:SetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE, hp)
	model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, hp)
	model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(SPLASH_CASH_MIN, SPLASH_CASH_MAX))
	model:SetAttribute(CONVEYOR_SCALE_ATTRIBUTE, scale)
	model:SetAttribute(IS_WATER_SPLASH_ATTRIBUTE, true)
	local splashFishImageId, splashFishTier = SplashKillFishFrames.pickGameplayFish("dragon_quest")
	model:SetAttribute(SplashKillFishFrames.IMAGE_ID_ATTRIBUTE, splashFishImageId)
	model:SetAttribute(SplashKillFishFrames.RARITY_ATTRIBUTE, splashFishTier)
	fireSplashKillFishPreloadToAll(splashFishImageId)
	applySpawnFishImage(model, splashFishImageId)

	local pos = findPatrolSpawnPosition(bounds, slotIndex)
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, ART_YAW_OFFSET_RAD, 0))

	local hit = Instance.new("Part")
	hit.Name = HIT_COLLIDER_NAME
	hit.Size = Vector3.new(HIT_COLLIDER_RADIUS * 2, HIT_COLLIDER_HEIGHT, HIT_COLLIDER_RADIUS * 2)
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanQuery = true
	hit.CanTouch = false
	hit.Massless = true
	hit.Transparency = 1
	updateHitCollider(hit, pos)
	hit.Parent = model

	model.Name = TEMPLATE_NAME .. "_" .. slotIndex
	model.Parent = activeFolder

	local record: PatrolDragon = {
		model = model,
		slotIndex = slotIndex,
		hitCollider = hit,
		lastPos = pos,
		lastYaw = 0,
	}
	table.insert(patrolDragons, record)

	totalSpawned += 1
	if totalSpawned <= PATROL_COUNT or totalSpawned % 4 == 0 then
		print(LOG, "spawned patrol slot", slotIndex, "at", pos)
	end

	model.Destroying:Connect(function()
		removePatrolRecord(model)
		task.delay(RESPAWN_DELAY_SEC, function()
			if boundsRef and templateRef and activeFolderRef then
				spawnPatrolDragon(slotIndex)
			end
		end)
	end)

	return record
end

print(LOG, "Starting patrol dragons", DRAGON_IMAGE)

local template = getSpawnTemplate()
if not SplashArenaInterior.refresh() then
	warn(LOG, "Spawner disabled (arena interior bounds).")
	return
end

local bounds = buildPatrolBounds()
if not bounds then
	return
end

SplashSpawnExclusions.refresh()

boundsRef = bounds
templateRef = template
activeFolderRef = getOrCreateActiveFolder()

print(
	LOG,
	"arena bounds X=",
	bounds.minX,
	bounds.maxX,
	"Z=",
	bounds.minZ,
	bounds.maxZ,
	"surfaceY=",
	bounds.surfaceY
)

for slotIndex = 1, PATROL_COUNT do
	spawnPatrolDragon(slotIndex)
end

RunService.Heartbeat:Connect(function()
	local b = boundsRef
	if not b then
		return
	end
	local t = Workspace:GetServerTimeNow()
	for _, rec in patrolDragons do
		if rec.model.Parent == nil then
			continue
		end
		if not isDragonPatrolActive(rec.model) then
			if rec.hitCollider.CanQuery then
				rec.hitCollider.CanQuery = false
			end
			continue
		end
		local desiredPos = patrolPosition(b, rec.slotIndex, t)
		local pos = desiredPos
		if rec.lastPos then
			local dx = desiredPos.X - rec.lastPos.X
			local dz = desiredPos.Z - rec.lastPos.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist > 1e-6 then
				local vel = Vector3.new(dx / dist, 0, dz / dist)
				pos = SplashSpawnExclusions.deflectPosition(rec.lastPos, vel, dist, 1)
			end
		end
		if not SplashArenaInterior.isInsideArena(pos) then
			continue
		end
		local yaw = rec.lastYaw
		if rec.lastPos then
			local dx = pos.X - rec.lastPos.X
			local dz = pos.Z - rec.lastPos.Z
			if dx * dx + dz * dz > 1e-6 then
				yaw = math.atan2(dx, dz)
				rec.lastYaw = yaw
			end
		end
		rec.model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw + ART_YAW_OFFSET_RAD, 0))
		updateHitCollider(rec.hitCollider, pos)
		rec.lastPos = pos
	end
end)

task.delay(6, function()
	if #patrolDragons == 0 then
		warn(LOG, "no patrol dragons in 6s — is BulletArenaBoundaries in Workspace?")
	else
		print(LOG, "active patrol dragons:", #patrolDragons, "total spawned:", totalSpawned)
	end
end)
