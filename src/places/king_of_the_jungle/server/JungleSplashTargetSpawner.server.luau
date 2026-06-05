--!strict
-- King of the Jungle (82834864756259): PNG billboard spawn targets. Registered at ServerScriptService root in Rojo.

local KING_PLACE_ID = 82834864756259
local LOG = "[JungleSplashTargetSpawner]"
local SCRIPT_VERSION = 8

print(LOG, "v" .. SCRIPT_VERSION, "loaded PlaceId=" .. tostring(game.PlaceId))

if game.PlaceId ~= KING_PLACE_ID then
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

local kingSplash = MatchSplashConfig.getForMapId("king_of_the_jungle")
local JUNGLE_SPLASH_IMAGE = kingSplash.imageId or "rbxassetid://110419001189017"
local BILLBOARD_STUDS = kingSplash.billboardStuds or 14
local FISH_BILLBOARD_SCALE = kingSplash.fishBillboardScale or 0.45
local BILLBOARD_BASE_PX = math.floor(BILLBOARD_STUDS * 10)

local SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME = "SplashKillFishPreload"

local TEMPLATE_NAME = "JungleBillboardSplash"
local TEMPLATE_HOLDER_NAME = "JungleSplashTemplate"
local ACTIVE_FOLDER_NAME = "WaterSplashes"
local MAX_ACTIVE_SPLASHES = 8
local SPAWN_INTERVAL = 0.65
local SPAWN_MARGIN = 6
local MIN_SPACING_STUDS = 10
local MAX_SPAWN_ATTEMPTS = 12
local SCALE_MIN, SCALE_MAX = 0.7, 1.3
local FADE_IN_SECONDS = 0.3
local HOLD_SECONDS = 6.0
local FADE_OUT_SECONDS = 0.8
local Y_OFFSET = 0.02
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

type ArenaBounds = SplashArenaInterior.SpawnBounds

type ActiveRecord = {
	model: Model,
	position: Vector3,
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

local function buildBillboardSplashTemplate(): Model
	local model = Instance.new("Model")
	model.Name = TEMPLATE_NAME

	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(1, 0.2, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.Parent = model
	model.PrimaryPart = anchor

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SplashBillboard"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = true
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.LightInfluence = 0
	billboard.MaxDistance = 450
	billboard.Size = UDim2.fromOffset(BILLBOARD_BASE_PX, BILLBOARD_BASE_PX)
	billboard.Parent = anchor

	-- Debug: show the per-spawn fish PNG behind the splash.
	local fishImage = Instance.new("ImageLabel")
	fishImage.Name = "FishImage"
	fishImage.BackgroundTransparency = 1
	fishImage.AnchorPoint = Vector2.new(0.5, 0.5)
	fishImage.Position = UDim2.fromScale(0.5, 0.5)
	fishImage.Size = UDim2.fromScale(FISH_BILLBOARD_SCALE, FISH_BILLBOARD_SCALE)
	fishImage.Image = SplashKillFishFrames.FALLBACK_IMAGE_ID
	fishImage.ScaleType = Enum.ScaleType.Fit
	fishImage.ZIndex = 1
	fishImage.Parent = billboard

	local image = Instance.new("ImageLabel")
	image.Name = "SplashImage"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = JUNGLE_SPLASH_IMAGE
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 2
	image.Parent = billboard

	return model
end

local STALE_TEMPLATE_NAMES = { "JunglePngSurfaceSplash", "JungleBillboardSplash" }

local function getSpawnTemplate(): Model
	local holder = ensureTemplateHolder()
	for _, name in STALE_TEMPLATE_NAMES do
		local stale = holder:FindFirstChild(name)
		if stale then
			stale:Destroy()
		end
	end
	local built = buildBillboardSplashTemplate()
	built.Parent = holder
	return built
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
		if descendant:IsA("BasePart") and descendant.Name ~= HIT_COLLIDER_NAME then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
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

local function applySpawnScale(model: Model, scale: number)
	local anchor = model.PrimaryPart
	if anchor then
		local billboard = anchor:FindFirstChild("SplashBillboard")
		if billboard and billboard:IsA("BillboardGui") then
			local px = math.floor(BILLBOARD_BASE_PX * scale)
			billboard.Size = UDim2.fromOffset(px, px)
			return
		end
	end
	pcall(function()
		model:ScaleTo(scale)
	end)
end

local function runLifecycle(model: Model, position: Vector3, activeFolder: Folder)
	table.insert(active, { model = model, position = position })

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

local totalSpawned = 0

local function trySpawn(template: Model, bounds: ArenaBounds, activeFolder: Folder): boolean
	local innerWidth = math.max(bounds.widthX - 2 * SPAWN_MARGIN, 0)
	local innerDepth = math.max(bounds.depthZ - 2 * SPAWN_MARGIN, 0)
	local surfaceY = bounds.floorY + SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET

	for _ = 1, MAX_SPAWN_ATTEMPTS do
		local x = bounds.minX + SPAWN_MARGIN + math.random() * innerWidth
		local z = bounds.minZ + SPAWN_MARGIN + math.random() * innerDepth
		local pos = Vector3.new(x, surfaceY, z)
		if not isBlockedBySpacing(pos) and not SplashSpawnExclusions.isNearTurret(pos) and SplashArenaInterior.isInsideArena(pos) then
			local clone = template:Clone()
			local model = normalizeToModel(clone)
			if not model.PrimaryPart then
				model:Destroy()
				return false
			end

			sanitizeModel(model)
			configureSplashParts(model)

			local scale = SCALE_MIN + math.random() * (SCALE_MAX - SCALE_MIN)
			applySpawnScale(model, scale)

			local hp = math.random(SPLASH_HEALTH_MIN, SPLASH_HEALTH_MAX)
			model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, true)
			model:SetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE, hp)
			model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, hp)
			model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(SPLASH_CASH_MIN, SPLASH_CASH_MAX))
			model:SetAttribute(CONVEYOR_SCALE_ATTRIBUTE, scale)
			model:SetAttribute(IS_WATER_SPLASH_ATTRIBUTE, true)
			local splashFishImageId, splashFishTier = SplashKillFishFrames.pickGameplayFish("king_of_the_jungle")
			model:SetAttribute(SplashKillFishFrames.IMAGE_ID_ATTRIBUTE, splashFishImageId)
			model:SetAttribute(SplashKillFishFrames.RARITY_ATTRIBUTE, splashFishTier)
			fireSplashKillFishPreloadToAll(splashFishImageId)

			local anchor = model.PrimaryPart
			if anchor then
				local splashBillboard = anchor:FindFirstChild("SplashBillboard")
				if splashBillboard and splashBillboard:IsA("BillboardGui") then
					local fishImage = splashBillboard:FindFirstChild("FishImage")
					if fishImage and fishImage:IsA("ImageLabel") then
						fishImage.Image = splashFishImageId
					end
				end
			end

			local yaw = math.random() * math.pi * 2
			model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
			snapToFloor(model, bounds.floorY, SPAWN_LIFT_ABOVE_BASEPLATE + Y_OFFSET)

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
			runLifecycle(model, pos, activeFolder)
			totalSpawned += 1
			if totalSpawned <= 3 or totalSpawned % 6 == 0 then
				print(LOG, "spawned #" .. totalSpawned, "at", pos)
			end
			return true
		end
	end
	return false
end

print(LOG, "Starting PNG spawns", JUNGLE_SPLASH_IMAGE)

local template = getSpawnTemplate()
if not SplashArenaInterior.refresh() then
	warn(LOG, "Spawner disabled (arena interior bounds).")
	return
end

local bounds = SplashArenaInterior.getSpawnBounds()
if not bounds then
	return
end

SplashSpawnExclusions.refresh()

math.randomseed(os.time())

local activeFolder = getOrCreateActiveFolder()

print(
	LOG,
	"arena bounds X=",
	bounds.minX,
	bounds.maxX,
	"Z=",
	bounds.minZ,
	bounds.maxZ,
	"floorY=",
	bounds.floorY,
	"folder=",
	activeFolder:GetFullName()
)
print(LOG, "spawn loop started")

task.spawn(function()
	while true do
		if #active < MAX_ACTIVE_SPLASHES then
			trySpawn(template, bounds, activeFolder)
		end
		task.wait(SPAWN_INTERVAL)
	end
end)

task.delay(6, function()
	if totalSpawned == 0 then
		warn(LOG, "no targets spawned in 6s — is BulletArenaBoundaries in Workspace?")
	else
		print(LOG, "active targets:", #active, "total spawned:", totalSpawned)
	end
end)
