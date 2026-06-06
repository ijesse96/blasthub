--!strict
-- Fish Frenzy (130112747036452): shark swim targets + singleton legendary boat. Synced via default.project.json PlaceServer only.

local FISH_FRENZY_PLACE_ID = 130112747036452
local LOG_PREFIX = "[WaterSplashSpawner]"
local SCRIPT_VERSION = 4

print(LOG_PREFIX, "v" .. SCRIPT_VERSION, "loaded PlaceId=" .. tostring(game.PlaceId))

if game.PlaceId ~= FISH_FRENZY_PLACE_ID then
	return
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BUILD_TAG = "fish-frenzy-shark-boat-v12"

local shared = ReplicatedStorage:WaitForChild("Shared")
local MatchSplashConfig = require(shared:WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(shared:WaitForChild("SplashKillFishFrames"))
local SplashSpawnExclusions = require(shared:WaitForChild("SplashSpawnExclusions"))
local SplashArenaInterior = require(shared:WaitForChild("SplashArenaInterior"))

local SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME = "SplashKillFishPreload"

local SHARK_TEMPLATE_NAME = "SharkBillboardSplash"
local BOAT_TEMPLATE_NAME = "BoatBillboardSplash"
local TEMPLATE_HOLDER_NAME = "WaterTemplate"
local ACTIVE_FOLDER_NAME = "WaterSplashes"
local MAX_ACTIVE_SPLASHES = 12
local SPAWN_INTERVAL = 0.5
local SPAWN_MARGIN = 6
local MIN_SPACING_STUDS = 10
local MAX_SPAWN_ATTEMPTS = 12

local SCALE_MIN, SCALE_MAX = 0.7, 1.3

local FADE_IN_SECONDS = 0.3
local BOUNDARY_EXIT_GLIDE_SECONDS = 1.0
local SHARK_MAX_LIFETIME_SECONDS = 120
local Y_OFFSET = 0.02
local BOAT_RENDER_LIFT = 0.06
local SPAWN_LIFT_ABOVE_BASEPLATE = 2.5

local HIT_COLLIDER_RADIUS = 14
local HIT_COLLIDER_HEIGHT = 4
local HIT_COLLIDER_NAME = "SplashHitCollider"

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

local TARGET_SURFACE_GUI_NAME = "TargetSurfaceGui"
local COVER_IMAGE_NAME = "CoverImage"
local FISH_IMAGE_NAME = "FishImage"
local SURFACE_PIXELS_PER_STUD = 32
local DEFAULT_FISH_BILLBOARD_SCALE = 0.45
local MAP_ID = "main"

local activeBoat: Model? = nil
local boatRespawnPending = false

local function getActiveBoatExclusionRadiusStuds(): number
	local boatStuds = MatchSplashConfig.getLegendaryTargetStuds(MAP_ID)
	return boatStuds * 0.5 + 6
end

local function isNearActiveBoat(pos: Vector3): boolean
	if not activeBoat or not activeBoat.Parent then
		return false
	end
	local boatPos = activeBoat:GetPivot().Position
	local radius = getActiveBoatExclusionRadiusStuds()
	local dx = pos.X - boatPos.X
	local dz = pos.Z - boatPos.Z
	return dx * dx + dz * dz < radius * radius
end

type BoatHealthMemory = {
	health: number,
	maxHealth: number,
}

local boatHealthMemory: BoatHealthMemory? = nil

local function clearBoatHealthMemory()
	boatHealthMemory = nil
end

local function persistBoatHealthFromModel(model: Model)
	local health = model:GetAttribute(CONVEYOR_HEALTH_ATTRIBUTE)
	local maxHealth = model:GetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE)
	if typeof(health) == "number" and typeof(maxHealth) == "number" and health > 0 then
		boatHealthMemory = { health = health, maxHealth = maxHealth }
	else
		clearBoatHealthMemory()
	end
end

local function resolveBoatSpawnHealth(): (number, number)
	if boatHealthMemory then
		return boatHealthMemory.health, boatHealthMemory.maxHealth
	end
	local hpMin = MatchSplashConfig.getLegendaryTargetHealthMin(MAP_ID)
	local hpMax = MatchSplashConfig.getLegendaryTargetHealthMax(MAP_ID)
	local maxHealth = math.random(hpMin, math.max(hpMax, hpMin))
	return maxHealth, maxHealth
end

local function fireSplashKillFishPreloadToAll(imageId: string)
	local remote = ReplicatedStorage:FindFirstChild(SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME)
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	for _, plr in Players:GetPlayers() do
		remote:FireClient(plr, imageId)
	end
end

type ArenaBounds = SplashArenaInterior.SpawnBounds

type ActiveRecord = {
	model: Model,
	position: Vector3,
}

type BoatPatrol = {
	laneX: number,
	northZ: number,
	southZ: number,
	zSign: number,
	speed: number,
}

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

local function getFishBillboardScale(visual: MatchSplashConfig.SplashVisual): number
	return visual.fishBillboardScale or DEFAULT_FISH_BILLBOARD_SCALE
end

local function getModelYawFromSwimYaw(swimYaw: number, artYawOffset: number): number
	local vx = math.sin(swimYaw)
	local vz = math.cos(swimYaw)
	return math.atan2(vx, vz) + artYawOffset + math.pi
end

local function mountCoverSurfaceGui(
	anchor: BasePart,
	footprintStuds: number,
	coverImageId: string,
	fishImageId: string,
	fishScale: number
): SurfaceGui
	local existing = anchor:FindFirstChild(TARGET_SURFACE_GUI_NAME)
	if existing then
		existing:Destroy()
	end

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = TARGET_SURFACE_GUI_NAME
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = SURFACE_PIXELS_PER_STUD
	surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surfaceGui.Parent = anchor

	local canvasSize = footprintStuds * SURFACE_PIXELS_PER_STUD
	surfaceGui.CanvasSize = Vector2.new(canvasSize, canvasSize)

	local fishImage = Instance.new("ImageLabel")
	fishImage.Name = FISH_IMAGE_NAME
	fishImage.BackgroundTransparency = 1
	fishImage.AnchorPoint = Vector2.new(0.5, 0.5)
	fishImage.Position = UDim2.fromScale(0.5, 0.5)
	fishImage.Size = UDim2.fromScale(fishScale, fishScale)
	fishImage.Image = fishImageId
	fishImage.ScaleType = Enum.ScaleType.Fit
	fishImage.ZIndex = 1
	fishImage.Parent = surfaceGui

	local coverImage = Instance.new("ImageLabel")
	coverImage.Name = COVER_IMAGE_NAME
	coverImage.BackgroundTransparency = 1
	coverImage.AnchorPoint = Vector2.new(0.5, 0.5)
	coverImage.Position = UDim2.fromScale(0.5, 0.5)
	coverImage.Size = UDim2.fromScale(1, 1)
	coverImage.Image = coverImageId
	coverImage.ScaleType = Enum.ScaleType.Fit
	coverImage.ZIndex = 3
	coverImage.Parent = surfaceGui

	return surfaceGui
end

local function buildSharkSplashTemplate(visual: MatchSplashConfig.SplashVisual): Model?
	local frames = visual.rareTargetFrameIds
	if not frames or #frames == 0 then
		return nil
	end

	local studs = MatchSplashConfig.getCommonTargetStuds(MAP_ID)
	local fishScale = getFishBillboardScale(visual)

	local model = Instance.new("Model")
	model.Name = SHARK_TEMPLATE_NAME

	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(studs, 0.2, studs)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.Parent = model
	model.PrimaryPart = anchor

	mountCoverSurfaceGui(anchor, studs, frames[1], SplashKillFishFrames.FALLBACK_IMAGE_ID, fishScale)

	model.Parent = ensureTemplateHolder()
	return model
end

local function buildBoatSplashTemplate(visual: MatchSplashConfig.SplashVisual): Model?
	local coverId = MatchSplashConfig.getLegendaryTargetImageId(MAP_ID)
	if not coverId then
		return nil
	end

	local studs = MatchSplashConfig.getLegendaryTargetStuds(MAP_ID)
	local fishScale = getFishBillboardScale(visual)

	local model = Instance.new("Model")
	model.Name = BOAT_TEMPLATE_NAME

	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(studs, 0.2, studs)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.Parent = model
	model.PrimaryPart = anchor

	mountCoverSurfaceGui(anchor, studs, coverId, SplashKillFishFrames.FALLBACK_IMAGE_ID, fishScale)

	model.Parent = ensureTemplateHolder()
	return model
end

local function getOrCreateSharkTemplate(visual: MatchSplashConfig.SplashVisual): Model?
	local frames = visual.rareTargetFrameIds
	if not frames or #frames == 0 then
		return nil
	end
	local holder = ensureTemplateHolder()
	local cached = holder:FindFirstChild(SHARK_TEMPLATE_NAME)
	if cached then
		cached:Destroy()
	end
	return buildSharkSplashTemplate(visual)
end

local function getOrCreateBoatTemplate(visual: MatchSplashConfig.SplashVisual): Model?
	if not MatchSplashConfig.getLegendaryTargetImageId(MAP_ID) then
		return nil
	end
	local holder = ensureTemplateHolder()
	local cached = holder:FindFirstChild(BOAT_TEMPLATE_NAME)
	if cached then
		cached:Destroy()
	end
	return buildBoatSplashTemplate(visual)
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
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = true
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local function snapToFloor(model: Model, floorY: number, extraY: number)
	local cf, size = model:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y * 0.5
	local delta = (floorY + extraY) - bottomY
	if math.abs(delta) > 0.001 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, delta, 0))
	end
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

local active: { ActiveRecord } = {}

local function isBlockedBySpacing(pos: Vector3): boolean
	local r2 = MIN_SPACING_STUDS * MIN_SPACING_STUDS
	for _, rec in active do
		local dx = pos.X - rec.position.X
		local dz = pos.Z - rec.position.Z
		if (dx * dx + dz * dz) < r2 then
			return true
		end
	end
	return false
end

local function removeRecord(model: Model)
	for i = #active, 1, -1 do
		if active[i].model == model then
			table.remove(active, i)
			return
		end
	end
end

local function safeScaleTo(model: Model, scale: number)
	pcall(function()
		model:ScaleTo(scale)
	end)
end

local function normalizeToModel(instance: Instance): Model
	if instance:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		wrapper.Name = instance.Name
		instance.Parent = wrapper
		wrapper.PrimaryPart = instance
		return wrapper
	end

	local model = instance :: Model
	if not model.PrimaryPart then
		local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			model.PrimaryPart = firstPart
		end
	end
	return model
end

local function repositionHitCollider(model: Model, hit: BasePart, surfaceY: number)
	local splashCenter = model:GetPivot().Position
	hit.CFrame = CFrame.new(
		splashCenter.X,
		surfaceY + HIT_COLLIDER_HEIGHT * 0.5,
		splashCenter.Z
	)
end

local function swimYawForZSign(zSign: number): number
	return if zSign > 0 then 0 else math.pi
end

local function attachHitCollider(model: Model, surfaceY: number): BasePart
	local splashCenter = model:GetPivot().Position
	local hit = Instance.new("Part")
	hit.Name = HIT_COLLIDER_NAME
	hit.Size = Vector3.new(HIT_COLLIDER_RADIUS * 2, HIT_COLLIDER_HEIGHT, HIT_COLLIDER_RADIUS * 2)
	hit.CFrame = CFrame.new(
		splashCenter.X,
		surfaceY + HIT_COLLIDER_HEIGHT * 0.5,
		splashCenter.Z
	)
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanQuery = true
	hit.CanTouch = false
	hit.Massless = true
	hit.Transparency = 1
	hit.Parent = model
	return hit
end

local function getSurfaceFadeLabels(model: Model): { ImageLabel }
	local labels: { ImageLabel } = {}
	local anchor = model.PrimaryPart
	if not anchor or not anchor:IsA("BasePart") then
		local found = model:FindFirstChild("Anchor")
		if found and found:IsA("BasePart") then
			anchor = found
		else
			return labels
		end
	end

	local surfaceGui = anchor:FindFirstChild(TARGET_SURFACE_GUI_NAME)
	if not surfaceGui or not surfaceGui:IsA("SurfaceGui") then
		return labels
	end

	for _, name in { COVER_IMAGE_NAME, FISH_IMAGE_NAME } do
		local label = surfaceGui:FindFirstChild(name)
		if label and label:IsA("ImageLabel") then
			table.insert(labels, label)
		end
	end

	return labels
end

local function runSwimOffExitGlide(
	model: Model,
	isAlive: () -> boolean,
	surfaceY: number,
	hit: BasePart?,
	moveDir: Vector3,
	speed: number,
	modelYaw: number,
	record: ActiveRecord?
)
	if hit then
		hit.CanQuery = false
	end

	local fadeLabels = getSurfaceFadeLabels(model)
	local glideStart = os.clock()

	while isAlive() do
		local elapsed = os.clock() - glideStart
		if elapsed >= BOUNDARY_EXIT_GLIDE_SECONDS then
			break
		end

		local dt = RunService.Heartbeat:Wait()
		local t = math.clamp((os.clock() - glideStart) / BOUNDARY_EXIT_GLIDE_SECONDS, 0, 1)
		local fadeT = 1 - (1 - t) * (1 - t)
		for _, label in fadeLabels do
			if label.Parent then
				label.ImageTransparency = fadeT
			end
		end

		local pivot = model:GetPivot()
		local nextPos = pivot.Position + moveDir * speed * dt
		model:PivotTo(CFrame.new(nextPos) * CFrame.Angles(0, modelYaw, 0))
		if record then
			record.position = nextPos
		end
		if hit and hit.Parent then
			repositionHitCollider(model, hit, surfaceY)
		end
	end

	if isAlive() then
		model:Destroy()
	end
end

local function runSharkLifecycle(
	model: Model,
	position: Vector3,
	activeFolder: Folder,
	surfaceY: number,
	sharkDrift: { swimYaw: number, swimSpeed: number }
)
	local record: ActiveRecord = { model = model, position = position }
	table.insert(active, record)

	local hitPart = model:FindFirstChild(HIT_COLLIDER_NAME)
	local hit = if hitPart and hitPart:IsA("BasePart") then hitPart else nil

	local aborted = false
	local ancestryConn: RBXScriptConnection
	ancestryConn = model.AncestryChanged:Connect(function(_, parent)
		if parent ~= activeFolder then
			aborted = true
			removeRecord(model)
			ancestryConn:Disconnect()
		end
	end)

	local function isAlive(): boolean
		return not aborted and model.Parent == activeFolder
	end

	task.spawn(function()
		local tIntro = os.clock()
		while os.clock() - tIntro < FADE_IN_SECONDS and isAlive() do
			RunService.Heartbeat:Wait()
		end
		if not isAlive() then
			return
		end

		local swimVelocity = Vector3.new(math.sin(sharkDrift.swimYaw), 0, math.cos(sharkDrift.swimYaw))
		local artOffset = MatchSplashConfig.getRareTargetArtYawOffsetRad(MAP_ID)
		local modelYaw = getModelYawFromSwimYaw(sharkDrift.swimYaw, artOffset)
		local lifetimeEnd = os.clock() + SHARK_MAX_LIFETIME_SECONDS

		while isAlive() and os.clock() < lifetimeEnd do
			local dt = RunService.Heartbeat:Wait()
			local pivot = model:GetPivot()
			local nextPos = pivot.Position + swimVelocity * sharkDrift.swimSpeed * dt

			if isNearActiveBoat(nextPos) then
				model:PivotTo(CFrame.new(nextPos) * CFrame.Angles(0, modelYaw, 0))
				record.position = nextPos
				if hit then
					repositionHitCollider(model, hit, surfaceY)
				end
				runSwimOffExitGlide(
					model,
					isAlive,
					surfaceY,
					hit,
					swimVelocity,
					sharkDrift.swimSpeed,
					modelYaw,
					record
				)
				return
			end

			if not SplashArenaInterior.isInsideArena(nextPos) then
				model:PivotTo(CFrame.new(nextPos) * CFrame.Angles(0, modelYaw, 0))
				record.position = nextPos
				if hit then
					repositionHitCollider(model, hit, surfaceY)
				end
				runSwimOffExitGlide(
					model,
					isAlive,
					surfaceY,
					hit,
					swimVelocity,
					sharkDrift.swimSpeed,
					modelYaw,
					record
				)
				return
			end

			model:PivotTo(CFrame.new(nextPos) * CFrame.Angles(0, modelYaw, 0))
			record.position = nextPos
			if hit then
				repositionHitCollider(model, hit, surfaceY)
			end
		end
		if isAlive() then
			model:Destroy()
		end
	end)
end

local function runBoatPatrolLifecycle(
	model: Model,
	activeFolder: Folder,
	surfaceY: number,
	boatRenderY: number,
	patrol: BoatPatrol,
	onRemoved: () -> ()
)
	local hitPart = model:FindFirstChild(HIT_COLLIDER_NAME)
	local hit = if hitPart and hitPart:IsA("BasePart") then hitPart else nil

	local aborted = false
	local ancestryConn: RBXScriptConnection
	ancestryConn = model.AncestryChanged:Connect(function(_, parent)
		if parent ~= activeFolder then
			aborted = true
			ancestryConn:Disconnect()
			onRemoved()
		end
	end)

	local function isAlive(): boolean
		return not aborted and model.Parent == activeFolder
	end

	task.spawn(function()
		local tIntro = os.clock()
		while os.clock() - tIntro < FADE_IN_SECONDS and isAlive() do
			RunService.Heartbeat:Wait()
		end
		if not isAlive() then
			return
		end

		local artOffset = MatchSplashConfig.getLegendaryTargetArtYawOffsetRad(MAP_ID)
		local exitDir = Vector3.new(0, 0, patrol.zSign)

		while isAlive() do
			local dt = RunService.Heartbeat:Wait()
			local pivot = model:GetPivot()
			local pos = pivot.Position
			local rawNextZ = pos.Z + patrol.zSign * patrol.speed * dt
			local nextZ = math.min(patrol.southZ, rawNextZ)

			local swimYaw = swimYawForZSign(patrol.zSign)
			local modelYaw = getModelYawFromSwimYaw(swimYaw, artOffset)
			model:PivotTo(CFrame.new(patrol.laneX, boatRenderY, nextZ) * CFrame.Angles(0, modelYaw, 0))
			if hit then
				repositionHitCollider(model, hit, surfaceY)
			end

			if rawNextZ >= patrol.southZ - 0.05 then
				runSwimOffExitGlide(
					model,
					isAlive,
					surfaceY,
					hit,
					exitDir,
					patrol.speed,
					modelYaw,
					nil
				)
				return
			end
		end
	end)
end

local function trySpawn(
	sharkTemplate: Model,
	bounds: ArenaBounds,
	activeFolder: Folder,
	splashVisual: MatchSplashConfig.SplashVisual
): boolean
	local innerWidth = math.max(bounds.widthX - 2 * SPAWN_MARGIN, 0)
	local innerDepth = math.max(bounds.depthZ - 2 * SPAWN_MARGIN, 0)

	local surfaceY = bounds.floorY + SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET
	local spawnRare = math.random() < MatchSplashConfig.getRareTargetSpawnChance(MAP_ID)
	local footprintStuds = if spawnRare
		then MatchSplashConfig.getRareTargetStuds(MAP_ID)
		else MatchSplashConfig.getCommonTargetStuds(MAP_ID)
	local sizeTier = if spawnRare
		then SplashKillFishFrames.TARGET_SIZE_RARE
		else SplashKillFishFrames.TARGET_SIZE_COMMON

	for _ = 1, MAX_SPAWN_ATTEMPTS do
		local x = bounds.minX + SPAWN_MARGIN + math.random() * innerWidth
		local z = bounds.minZ + SPAWN_MARGIN + math.random() * innerDepth
		local pos = Vector3.new(x, surfaceY, z)
		if not isBlockedBySpacing(pos) and not SplashSpawnExclusions.isNearTurret(pos) and not isNearActiveBoat(pos) and SplashArenaInterior.isInsideArena(pos) then
			local clone = sharkTemplate:Clone()
			local model = normalizeToModel(clone)
			if not model.PrimaryPart then
				model:Destroy()
				return false
			end

			sanitizeModel(model)
			configureSplashParts(model)

			local scale = SCALE_MIN + math.random() * (SCALE_MAX - SCALE_MIN)
			safeScaleTo(model, scale)

			local hp = math.random(SPLASH_HEALTH_MIN, SPLASH_HEALTH_MAX)
			model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, true)
			model:SetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE, hp)
			model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, hp)
			model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(SPLASH_CASH_MIN, SPLASH_CASH_MAX))
			model:SetAttribute(CONVEYOR_SCALE_ATTRIBUTE, scale)
			model:SetAttribute(IS_WATER_SPLASH_ATTRIBUTE, true)
			model:SetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE, SplashKillFishFrames.TARGET_KIND_SHARK)
			model:SetAttribute(SplashKillFishFrames.TARGET_SIZE_TIER_ATTRIBUTE, sizeTier)

			local swimYaw = math.random() * math.pi * 2
			model:SetAttribute(SplashKillFishFrames.SWIM_YAW_ATTRIBUTE, swimYaw)

			local splashFishImageId: string
			local splashFishTier: string
			if spawnRare then
				splashFishImageId, splashFishTier = SplashKillFishFrames.pickRareSplashFish(MAP_ID)
			else
				splashFishImageId, splashFishTier = SplashKillFishFrames.pickCommonSplashFish(MAP_ID)
			end

			model:SetAttribute(SplashKillFishFrames.IMAGE_ID_ATTRIBUTE, splashFishImageId)
			model:SetAttribute(SplashKillFishFrames.RARITY_ATTRIBUTE, splashFishTier)
			fireSplashKillFishPreloadToAll(splashFishImageId)

			local anchor = model.PrimaryPart
			if anchor then
				anchor.Size = Vector3.new(footprintStuds, 0.2, footprintStuds)
				local frames = splashVisual.rareTargetFrameIds
				local coverId = if frames and #frames > 0 then frames[1] else ""
				local fishScale = getFishBillboardScale(splashVisual)
				mountCoverSurfaceGui(anchor, footprintStuds, coverId, splashFishImageId, fishScale)
			end

			local artOffset = MatchSplashConfig.getRareTargetArtYawOffsetRad(MAP_ID)
			local modelYaw = getModelYawFromSwimYaw(swimYaw, artOffset)
			model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, modelYaw, 0))
			snapToFloor(model, bounds.floorY, SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET)
			attachHitCollider(model, surfaceY)

			local sharkDrift = {
				swimYaw = swimYaw,
				swimSpeed = MatchSplashConfig.getRareTargetSwimSpeedStudsPerSec(MAP_ID),
			}

			model.Parent = activeFolder
			runSharkLifecycle(model, pos, activeFolder, surfaceY, sharkDrift)
			return true
		end
	end
	return false
end

local function clearActiveBoat(onRemoved: () -> ())
	if activeBoat then
		activeBoat = nil
	end
	onRemoved()
end

local function trySpawnBoat(
	boatTemplate: Model,
	bounds: ArenaBounds,
	activeFolder: Folder,
	splashVisual: MatchSplashConfig.SplashVisual,
	onRemoved: () -> ()
): boolean
	if activeBoat then
		return false
	end

	local surfaceY = bounds.floorY + SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET
	local boatRenderY = surfaceY + BOAT_RENDER_LIFT
	local northZ = bounds.minZ + SPAWN_MARGIN
	local southZ = bounds.maxZ - SPAWN_MARGIN
	if southZ <= northZ then
		return false
	end

	local laneX = (bounds.minX + bounds.maxX) * 0.5
	local startZ = northZ
	local zSign = 1
	local pos = Vector3.new(laneX, boatRenderY, startZ)

	if SplashSpawnExclusions.isNearTurret(pos) or not SplashArenaInterior.isInsideArena(pos) then
		return false
	end

	local clone = boatTemplate:Clone()
	local model = normalizeToModel(clone)
	if not model.PrimaryPart then
		model:Destroy()
		return false
	end

	sanitizeModel(model)
	configureSplashParts(model)

	local footprintStuds = MatchSplashConfig.getLegendaryTargetStuds(MAP_ID)
	local scale = SCALE_MIN + math.random() * (SCALE_MAX - SCALE_MIN)
	safeScaleTo(model, scale)

	local hp, maxHp = resolveBoatSpawnHealth()
	model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, true)
	model:SetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE, maxHp)
	model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, hp)
	model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(SPLASH_CASH_MIN, SPLASH_CASH_MAX))
	model:SetAttribute(CONVEYOR_SCALE_ATTRIBUTE, scale)
	model:SetAttribute(IS_WATER_SPLASH_ATTRIBUTE, true)
	model:SetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE, SplashKillFishFrames.TARGET_KIND_BOAT)
	model:SetAttribute(SplashKillFishFrames.TARGET_SIZE_TIER_ATTRIBUTE, SplashKillFishFrames.TARGET_SIZE_LEGENDARY)

	local swimYaw = swimYawForZSign(zSign)
	model:SetAttribute(SplashKillFishFrames.SWIM_YAW_ATTRIBUTE, swimYaw)

	local splashFishImageId, splashFishTier = SplashKillFishFrames.pickLegendarySplashFish(MAP_ID)
	model:SetAttribute(SplashKillFishFrames.IMAGE_ID_ATTRIBUTE, splashFishImageId)
	model:SetAttribute(SplashKillFishFrames.RARITY_ATTRIBUTE, splashFishTier)
	fireSplashKillFishPreloadToAll(splashFishImageId)

	local coverId = MatchSplashConfig.getLegendaryTargetImageId(MAP_ID) or ""
	local fishScale = getFishBillboardScale(splashVisual)

	local anchor = model.PrimaryPart
	if anchor then
		anchor.Size = Vector3.new(footprintStuds, 0.2, footprintStuds)
		mountCoverSurfaceGui(anchor, footprintStuds, coverId, splashFishImageId, fishScale)
	end

	local artOffset = MatchSplashConfig.getLegendaryTargetArtYawOffsetRad(MAP_ID)
	local modelYaw = getModelYawFromSwimYaw(swimYaw, artOffset)
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, modelYaw, 0))
	snapToFloor(model, bounds.floorY, SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET + BOAT_RENDER_LIFT)
	attachHitCollider(model, surfaceY)

	local patrol: BoatPatrol = {
		laneX = laneX,
		northZ = northZ,
		southZ = southZ,
		zSign = zSign,
		speed = MatchSplashConfig.getLegendaryTargetSwimSpeedStudsPerSec(MAP_ID),
	}

	activeBoat = model
	model.Destroying:Connect(function()
		persistBoatHealthFromModel(model)
	end)
	model.Parent = activeFolder
	runBoatPatrolLifecycle(model, activeFolder, surfaceY, boatRenderY, patrol, function()
		clearActiveBoat(onRemoved)
	end)
	return true
end

local function start()
	print(string.format("%s build=%s PlaceId=%s", LOG_PREFIX, BUILD_TAG, tostring(game.PlaceId)))

	MatchSplashConfig.ensureActiveMapIdOnServer()

	local splashVisual = MatchSplashConfig.getForMapId(MAP_ID)
	local sharkTemplate = getOrCreateSharkTemplate(splashVisual)
	if not sharkTemplate then
		warn(string.format("%s No shark template for map=%s (PlaceId=%s)", LOG_PREFIX, MAP_ID, tostring(game.PlaceId)))
		return
	end

	local boatTemplate = getOrCreateBoatTemplate(splashVisual)

	print(string.format(
		"%s Started map=%s commonStuds=%s rareStuds=%s rareChance=%s boat=%s",
		LOG_PREFIX,
		MAP_ID,
		tostring(MatchSplashConfig.getCommonTargetStuds(MAP_ID)),
		tostring(MatchSplashConfig.getRareTargetStuds(MAP_ID)),
		tostring(MatchSplashConfig.getRareTargetSpawnChance(MAP_ID)),
		tostring(boatTemplate ~= nil)
	))

	if not SplashArenaInterior.refresh() then
		warn(LOG_PREFIX .. " Spawner disabled (arena interior bounds).")
		return
	end

	local bounds = SplashArenaInterior.getSpawnBounds()
	if not bounds then
		return
	end

	SplashSpawnExclusions.refresh()

	math.randomseed(DateTime.now().UnixTimestampMillis)

	local activeFolder = getOrCreateActiveFolder()

	local function scheduleBoatRespawn()
		if not boatTemplate then
			return
		end
		if activeBoat or boatRespawnPending then
			return
		end
		boatRespawnPending = true
		local minDelay = MatchSplashConfig.getLegendaryTargetRespawnDelayMinSec(MAP_ID)
		local maxDelay = MatchSplashConfig.getLegendaryTargetRespawnDelayMaxSec(MAP_ID)
		local delaySec = minDelay + math.random() * math.max(maxDelay - minDelay, 0)
		task.delay(delaySec, function()
			boatRespawnPending = false
			if activeBoat then
				return
			end
			if trySpawnBoat(boatTemplate :: Model, bounds, activeFolder, splashVisual, scheduleBoatRespawn) then
				return
			end
			scheduleBoatRespawn()
		end)
	end

	task.spawn(function()
		while true do
			if #active < MAX_ACTIVE_SPLASHES then
				trySpawn(sharkTemplate, bounds, activeFolder, splashVisual)
			end
			task.wait(SPAWN_INTERVAL)
		end
	end)

	scheduleBoatRespawn()
end

start()
