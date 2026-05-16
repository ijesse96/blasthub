--!strict
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local WATER_TEMPLATE_NAME = "Water"
local TEMPLATE_HOLDER_NAME = "WaterTemplate"
local ACTIVE_FOLDER_NAME = "WaterSplashes"
local BOUNDARY_FOLDER_NAME = "BulletArenaBoundaries"

local MAX_ACTIVE_SPLASHES = 18
local SPAWN_INTERVAL = 0.35
local SPAWN_MARGIN = 6
local MIN_SPACING_STUDS = 10
local MAX_SPAWN_ATTEMPTS = 6

local SCALE_MIN, SCALE_MAX = 0.7, 1.3

local FADE_IN_SECONDS = 0.3
local HOLD_SECONDS = 6.0
local FADE_OUT_SECONDS = 0.8
-- Tiny lift so visuals don't z-fight with Baseplate.WaterBackground texture.
local Y_OFFSET = 0.02
-- Raise splashes above the baseplate top so mostly-horizontal anti-air raycasts
-- intersect the hit volume instead of skimming the flat floor behind the effect.
local SPAWN_LIFT_ABOVE_BASEPLATE = 2.5

-- Invisible hit collider sits over each splash so bullets reliably register hits
-- regardless of how small/thin the visual splash mesh is.
local HIT_COLLIDER_RADIUS = 14
-- Wide footprint only; keep Y short so hits feel horizontal, not a tall column.
local HIT_COLLIDER_HEIGHT = 4
local HIT_COLLIDER_NAME = "SplashHitCollider"

-- Attribute names must match ConveyorSystem so anti-air projectiles recognize splashes.
local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"
local CONVEYOR_HEALTH_ATTRIBUTE = "ConveyorHealth"
local CONVEYOR_MAX_HEALTH_ATTRIBUTE = "ConveyorMaxHealth"
local CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE = "ConveyorItemCashReward"
local CONVEYOR_SCALE_ATTRIBUTE = "ConveyorSpawnScale"
-- ConveyorSystem: splash kill VFX above turret reads this attribute.
local IS_WATER_SPLASH_ATTRIBUTE = "IsWaterSplash"

local SPLASH_HEALTH_MIN = 1
local SPLASH_HEALTH_MAX = 3
local SPLASH_CASH_MIN = 1
local SPLASH_CASH_MAX = 5

type ArenaBounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	floorY: number,
	widthX: number,
	depthZ: number,
}

type ActiveRecord = {
	model: Model,
	position: Vector3,
}

local function getPartWorldCorners(part: BasePart): { Vector3 }
	local cf = part.CFrame
	local h = part.Size * 0.5
	return {
		cf * Vector3.new(-h.X, -h.Y, -h.Z),
		cf * Vector3.new(h.X, -h.Y, -h.Z),
		cf * Vector3.new(-h.X, h.Y, -h.Z),
		cf * Vector3.new(h.X, h.Y, -h.Z),
		cf * Vector3.new(-h.X, -h.Y, h.Z),
		cf * Vector3.new(h.X, -h.Y, h.Z),
		cf * Vector3.new(-h.X, h.Y, h.Z),
		cf * Vector3.new(h.X, h.Y, h.Z),
	}
end

local function getWorkspaceBaseplateTopY(): number?
	local bp = Workspace:FindFirstChild("Baseplate")
	if bp and bp:IsA("BasePart") then
		return bp.Position.Y + bp.Size.Y * 0.5
	end
	return nil
end

local function computeBounds(): ArenaBounds?
	local folder = Workspace:FindFirstChild(BOUNDARY_FOLDER_NAME)
	if not folder then
		warn("[WaterSplashSpawner] Workspace folder '" .. BOUNDARY_FOLDER_NAME .. "' not found; spawner disabled.")
		return nil
	end

	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local minCornerY = math.huge
	local partCount = 0

	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") then
			for _, v in getPartWorldCorners(desc) do
				if v.X < minX then minX = v.X end
				if v.X > maxX then maxX = v.X end
				if v.Z < minZ then minZ = v.Z end
				if v.Z > maxZ then maxZ = v.Z end
				if v.Y < minCornerY then minCornerY = v.Y end
			end
			partCount += 1
		end
	end

	if partCount == 0 or minX >= maxX - 1e-4 or minZ >= maxZ - 1e-4 then
		warn("[WaterSplashSpawner] BulletArenaBoundaries has no BaseParts or degenerate bounds; spawner disabled.")
		return nil
	end

	local baseTop = getWorkspaceBaseplateTopY()
	local floorY = if baseTop ~= nil then baseTop else minCornerY

	return {
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
		floorY = floorY,
		widthX = maxX - minX,
		depthZ = maxZ - minZ,
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

local function findAndStashTemplate(): Instance?
	local existing = ServerStorage:FindFirstChild(TEMPLATE_HOLDER_NAME)
	if existing then
		local cached = existing:FindFirstChild(WATER_TEMPLATE_NAME)
		if cached then
			return cached
		end
	end

	local template = Workspace:WaitForChild(WATER_TEMPLATE_NAME, 30)
	if not template then
		warn("[WaterSplashSpawner] Workspace.Water not found within 30s; spawner disabled.")
		return nil
	end
	if not (template:IsA("Model") or template:IsA("BasePart")) then
		warn("[WaterSplashSpawner] Workspace.Water must be a Model or BasePart; spawner disabled.")
		return nil
	end

	template.Parent = ensureTemplateHolder()
	return template
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
			-- CanQuery must be true so anti-air raycasts in AntiAirRicochetProjectile hit splashes.
			descendant.CanQuery = true
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local SPLASH_WHITE_COLOR_SEQ = ColorSequence.new(Color3.fromRGB(255, 255, 255))
local SPLASH_OPAQUE_TRANSPARENCY_SEQ = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 0),
})

local function forceWhiteOpaqueEmitters(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Color = SPLASH_WHITE_COLOR_SEQ
			descendant.Transparency = SPLASH_OPAQUE_TRANSPARENCY_SEQ
			-- Ignore world lighting; black Ambient + voxel shadows would otherwise tint particles gray.
			descendant.LightInfluence = 0
			descendant.LightEmission = 1
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

local function runLifecycle(model: Model, _targetScale: number, position: Vector3, activeFolder: Folder)
	local record: ActiveRecord = { model = model, position = position }
	table.insert(active, record)

	-- Abort whenever the conveyor system (or anything else) re-parents or destroys the model
	-- mid-lifecycle. On a successful "kill", ConveyorSystem moves the model to ConveyorDeathVFX
	-- for the float-to-turret animation; we must stop touching it then.
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

	task.delay(FADE_IN_SECONDS + HOLD_SECONDS + FADE_OUT_SECONDS + 0.5, function()
		if isAlive() then
			model:Destroy()
		end
	end)

	task.spawn(function()
		-- No BasePart / Decal / Texture transparency animation: lerping over the gray baseplate
		-- made white foam read as gray. Emitters keep their asset-defined curves.
		local tIntro = os.clock()
		while os.clock() - tIntro < FADE_IN_SECONDS and isAlive() do
			RunService.Heartbeat:Wait()
		end
		if not isAlive() then
			return
		end

		local holdEnd = os.clock() + HOLD_SECONDS
		while os.clock() < holdEnd and isAlive() do
			RunService.Heartbeat:Wait()
		end
		if not isAlive() then
			return
		end

		local tOutro = os.clock()
		while os.clock() - tOutro < FADE_OUT_SECONDS and isAlive() do
			RunService.Heartbeat:Wait()
		end

		if isAlive() then
			model:Destroy()
		end
	end)
end

local function trySpawn(template: Instance, bounds: ArenaBounds, activeFolder: Folder): boolean
	local innerWidth = math.max(bounds.widthX - 2 * SPAWN_MARGIN, 0)
	local innerDepth = math.max(bounds.depthZ - 2 * SPAWN_MARGIN, 0)

	local surfaceY = bounds.floorY + SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET

	for _ = 1, MAX_SPAWN_ATTEMPTS do
		local x = bounds.minX + SPAWN_MARGIN + math.random() * innerWidth
		local z = bounds.minZ + SPAWN_MARGIN + math.random() * innerDepth
		local pos = Vector3.new(x, surfaceY, z)
		if not isBlockedBySpacing(pos) then
			local clone = template:Clone()
			local model = normalizeToModel(clone)
			if not model.PrimaryPart then
				model:Destroy()
				return false
			end

			sanitizeModel(model)
			configureSplashParts(model)
			forceWhiteOpaqueEmitters(model)

			local scale = SCALE_MIN + math.random() * (SCALE_MAX - SCALE_MIN)
			safeScaleTo(model, scale)

			-- Make this splash a valid conveyor target so anti-air bullets red-flash + award cash.
			local hp = math.random(SPLASH_HEALTH_MIN, SPLASH_HEALTH_MAX)
			model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, true)
			model:SetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE, hp)
			model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, hp)
			model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(SPLASH_CASH_MIN, SPLASH_CASH_MAX))
			-- ConveyorSystem reads this when floating dead items to the turret; preserve our spawn scale.
			model:SetAttribute(CONVEYOR_SCALE_ATTRIBUTE, scale)
			model:SetAttribute(IS_WATER_SPLASH_ATTRIBUTE, true)

			local yaw = math.random() * math.pi * 2
			model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
			snapToFloor(model, bounds.floorY, SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET)

			-- Big invisible hit collider so small/thin splash meshes are still easy to shoot.
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

			model.Parent = activeFolder
			runLifecycle(model, scale, pos, activeFolder)
			return true
		end
	end
	return false
end

local template = findAndStashTemplate()
if not template then
	return
end

local bounds = computeBounds()
if not bounds then
	return
end

math.randomseed(DateTime.now().UnixTimestampMillis)

local activeFolder = getOrCreateActiveFolder()

task.spawn(function()
	while true do
		if #active < MAX_ACTIVE_SPLASHES then
			trySpawn(template, bounds, activeFolder)
		end
		task.wait(SPAWN_INTERVAL)
	end
end)
