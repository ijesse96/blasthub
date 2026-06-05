--!strict
-- Fish Frenzy (130112747036452): billboard PNG splash targets. Synced via default.project.json PlaceServer only.

local FISH_FRENZY_PLACE_ID = 130112747036452
local LOG_PREFIX = "[WaterSplashSpawner]"
local SCRIPT_VERSION = 1

print(LOG_PREFIX, "v" .. SCRIPT_VERSION, "loaded PlaceId=" .. tostring(game.PlaceId))

if game.PlaceId ~= FISH_FRENZY_PLACE_ID then
	return
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BUILD_TAG = "fish-frenzy-water-v4"

local shared = ReplicatedStorage:WaitForChild("Shared")
local MatchSplashConfig = require(shared:WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(shared:WaitForChild("SplashKillFishFrames"))
local SplashSpawnExclusions = require(shared:WaitForChild("SplashSpawnExclusions"))
local SplashArenaInterior = require(shared:WaitForChild("SplashArenaInterior"))

local SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME = "SplashKillFishPreload"

local WATER_TEMPLATE_NAME = "Water"
local BILLBOARD_TEMPLATE_NAME = "BillboardSplash"
local TEMPLATE_HOLDER_NAME = "WaterTemplate"
local ACTIVE_FOLDER_NAME = "WaterSplashes"
local MAX_ACTIVE_SPLASHES = 12
local SPAWN_INTERVAL = 0.5
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

local FISH_BILLBOARD_NAME = "SplashBillboard"
local DEFAULT_BILLBOARD_STUDS = 14
local DEFAULT_FISH_BILLBOARD_SCALE = 0.45

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

local function getFishBillboardScale(visual: MatchSplashConfig.SplashVisual): number
	return visual.fishBillboardScale or DEFAULT_FISH_BILLBOARD_SCALE
end

local function mountLayeredFishBillboard(
	adornee: BasePart,
	billboardPx: number,
	fishImageId: string,
	coverImageId: string?,
	fishScale: number
): BillboardGui
	local existing = adornee:FindFirstChild(FISH_BILLBOARD_NAME)
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = FISH_BILLBOARD_NAME
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.LightInfluence = 0
	billboard.MaxDistance = 450
	billboard.Size = UDim2.fromOffset(billboardPx, billboardPx)
	billboard.Parent = adornee

	local fishImage = Instance.new("ImageLabel")
	fishImage.Name = "FishImage"
	fishImage.BackgroundTransparency = 1
	fishImage.AnchorPoint = Vector2.new(0.5, 0.5)
	fishImage.Position = UDim2.fromScale(0.5, 0.5)
	fishImage.Size = UDim2.fromScale(fishScale, fishScale)
	fishImage.Image = fishImageId
	fishImage.ScaleType = Enum.ScaleType.Fit
	fishImage.ZIndex = 1
	fishImage.Parent = billboard

	if coverImageId and coverImageId ~= "" then
		local splashImage = Instance.new("ImageLabel")
		splashImage.Name = "SplashImage"
		splashImage.BackgroundTransparency = 1
		splashImage.Size = UDim2.fromScale(1, 1)
		splashImage.Image = coverImageId
		splashImage.ScaleType = Enum.ScaleType.Fit
		splashImage.ZIndex = 2
		splashImage.Parent = billboard
	end

	return billboard
end

local function buildBillboardSplashTemplate(visual: MatchSplashConfig.SplashVisual): Model?
	local imageId = visual.imageId
	if not imageId or imageId == "" then
		warn(LOG_PREFIX .. " billboard_png map has no imageId; spawner disabled.")
		return nil
	end

	local studs = visual.billboardStuds or 14
	local px = math.floor(studs * 10)

	local model = Instance.new("Model")
	model.Name = BILLBOARD_TEMPLATE_NAME

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

	mountLayeredFishBillboard(anchor, px, SplashKillFishFrames.FALLBACK_IMAGE_ID, imageId, getFishBillboardScale(visual))

	model.Parent = ensureTemplateHolder()
	return model
end

local function findAndStashWaterTemplate(workspaceName: string): Instance?
	local holder = ensureTemplateHolder()
	local cached = holder:FindFirstChild(WATER_TEMPLATE_NAME)
	if cached then
		return cached
	end

	local template = Workspace:WaitForChild(workspaceName, 30)
	if not template then
		warn(string.format("%s Workspace.%s not found within 30s; spawner disabled.", LOG_PREFIX, workspaceName))
		return nil
	end
	if not (template:IsA("Model") or template:IsA("BasePart")) then
		warn(string.format("%s Workspace.%s must be a Model or BasePart; spawner disabled.", LOG_PREFIX, workspaceName))
		return nil
	end

	template.Name = WATER_TEMPLATE_NAME
	template.Parent = holder
	return template
end

local function resolveSpawnTemplate(visual: MatchSplashConfig.SplashVisual): (Instance?, boolean)
	if MatchSplashConfig.isBillboardMode(visual) then
		local holder = ensureTemplateHolder()
		local cached = holder:FindFirstChild(BILLBOARD_TEMPLATE_NAME)
		if cached then
			return cached, true
		end
		local built = buildBillboardSplashTemplate(visual)
		return built, true
	end

	local workspaceName = visual.workspaceTemplateName or WATER_TEMPLATE_NAME
	local template = findAndStashWaterTemplate(workspaceName)
	return template, false
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

local function trySpawn(
	template: Instance,
	bounds: ArenaBounds,
	activeFolder: Folder,
	useBillboardVisual: boolean,
	splashVisual: MatchSplashConfig.SplashVisual
): boolean
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
			if not useBillboardVisual then
				forceWhiteOpaqueEmitters(model)
			end

			local scale = SCALE_MIN + math.random() * (SCALE_MAX - SCALE_MIN)
			safeScaleTo(model, scale)

			local hp = math.random(SPLASH_HEALTH_MIN, SPLASH_HEALTH_MAX)
			model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, true)
			model:SetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE, hp)
			model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, hp)
			model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(SPLASH_CASH_MIN, SPLASH_CASH_MAX))
			model:SetAttribute(CONVEYOR_SCALE_ATTRIBUTE, scale)
			model:SetAttribute(IS_WATER_SPLASH_ATTRIBUTE, true)
			local splashFishImageId, splashFishTier = SplashKillFishFrames.pickGameplayFish()
			model:SetAttribute(SplashKillFishFrames.IMAGE_ID_ATTRIBUTE, splashFishImageId)
			model:SetAttribute(SplashKillFishFrames.RARITY_ATTRIBUTE, splashFishTier)
			fireSplashKillFishPreloadToAll(splashFishImageId)

			local anchor = model.PrimaryPart
			if anchor then
				local billboardPx = math.floor((splashVisual.billboardStuds or DEFAULT_BILLBOARD_STUDS) * 10)
				local fishScale = getFishBillboardScale(splashVisual)
				if useBillboardVisual then
					local splashBillboard = anchor:FindFirstChild(FISH_BILLBOARD_NAME)
					if splashBillboard and splashBillboard:IsA("BillboardGui") then
						splashBillboard.Size = UDim2.fromOffset(billboardPx, billboardPx)
						local fishImage = splashBillboard:FindFirstChild("FishImage")
						if fishImage and fishImage:IsA("ImageLabel") then
							fishImage.Image = splashFishImageId
							fishImage.Size = UDim2.fromScale(fishScale, fishScale)
						end
					end
				else
					-- Workspace.Water: keep fish ImageLabel for preload, hidden behind 3D water.
					local billboard = mountLayeredFishBillboard(anchor, billboardPx, splashFishImageId, nil, fishScale)
					local fishImage = billboard:FindFirstChild("FishImage")
					if fishImage and fishImage:IsA("ImageLabel") then
						fishImage.ImageTransparency = 1
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
			runLifecycle(model, scale, pos, activeFolder)
			return true
		end
	end
	return false
end


local function start()
	print(string.format("%s build=%s PlaceId=%s", LOG_PREFIX, BUILD_TAG, tostring(game.PlaceId)))

	MatchSplashConfig.ensureActiveMapIdOnServer()

	local splashVisual = MatchSplashConfig.getForMapId("main")
	local template, useBillboardVisual = resolveSpawnTemplate(splashVisual)
	if not template then
		warn(string.format(
			"%s No spawn template for map=main mode=%s (PlaceId=%s)",
			LOG_PREFIX,
			splashVisual.mode,
			tostring(game.PlaceId)
		))
		return
	end

	print(string.format(
		"%s Started map=main mode=%s billboard=%s",
		LOG_PREFIX,
		splashVisual.mode,
		tostring(useBillboardVisual)
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

	task.spawn(function()
		while true do
			if #active < MAX_ACTIVE_SPLASHES then
				trySpawn(template, bounds, activeFolder, useBillboardVisual, splashVisual)
			end
			task.wait(SPAWN_INTERVAL)
		end
	end)

end

start()
