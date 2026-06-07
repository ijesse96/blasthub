local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local HIT_FLASH_REMOTE_NAME = "AntiAirConveyorHitFlash"
local HIT_FLASH_VFX_REMOTE_NAME = "AntiAirConveyorHitFlashVfx"
local CASH_FLY_VFX_REMOTE_NAME = "CashFlyVfx"
local SPLASH_KILL_FISH_VFX_REMOTE_NAME = "SplashKillFishVfx"
local SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME = "SplashKillFishPreload"
local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SplashKillFishFrames"))
local SplashReelConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirSplashReelConfig"))
local SPLASH_KILL_FISH_IMAGE_ID_ATTRIBUTE = SplashKillFishFrames.IMAGE_ID_ATTRIBUTE
local SPLASH_KILL_FISH_RARITY_ATTRIBUTE = SplashKillFishFrames.RARITY_ATTRIBUTE
local Money = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Money"))
local FishCollectionService = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FishCollectionService"))
local MatchRoundBridge = require(script.Parent:WaitForChild("MatchRoundBridge"))
local ConveyorAntiAirBridge = require(script.Parent:WaitForChild("ConveyorAntiAirBridge") :: ModuleScript)

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

ensureRemoteEvent(HIT_FLASH_REMOTE_NAME)
ensureRemoteEvent(HIT_FLASH_VFX_REMOTE_NAME)
ensureRemoteEvent(CASH_FLY_VFX_REMOTE_NAME)
ensureRemoteEvent(SPLASH_KILL_FISH_VFX_REMOTE_NAME)
ensureRemoteEvent(SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME)

local CONVEYOR_ITEMS_FOLDER = "ConveyorItems"
local ACTIVE_ITEMS_FOLDER = "ConveyorActiveItems"
-- When false, no arena targets spawn (no templates, no fallback crates). Hit/cash wiring still loads.
local CONVEYOR_ARENA_TARGETS_ENABLED = false
-- Arena edges from Workspace.BulletArenaBoundaries AABB: Left=min X, Right=max X, Top=max Z, Bottom=min Z.
local BOUNDARY_FOLDER_NAME = "BulletArenaBoundaries"
local SPAWN_MARGIN = 8

local SPAWN_INTERVAL = 1.2
local CONVEYOR_SPEED = 11
local MAX_ACTIVE_ITEMS = 28
local TARGET_ACTIVE_ITEMS = 14
-- Relative spawn frequency for: L→R, R→L, Top→Bottom, Bottom→Top, TL→BR, BL→TR
local PATH_WEIGHTS: { number } = { 1, 1, 1, 1, 1, 1 }
local ITEM_SPACING = 20
local END_REACHED_THRESHOLD = 3
local Y_OFFSET = 2.5
local TARGET_ITEM_MAX_AXIS_STUDS = 40
local MAX_ITEM_BOUNDS_STUDS = 40
local BASE_TEMPLATE_MAX_AXIS_STUDS = 2.5
local MAX_PART_AXIS_STUDS = 40
local MAX_SPECIAL_MESH_AXIS_SCALE = 40
local SCALE_ATTRIBUTE = "ConveyorSpawnScale"
local SPAWN_RELATIVE_SIZE_ATTRIBUTE = "ConveyorSpawnRelativeSize"
local SPAWN_RELATIVE_SIZE_MIN = 0.01
local SPAWN_RELATIVE_SIZE_MAX = 3
-- Binary `shark fin.rbxm` cannot carry repo-edited attributes; default when attribute is unset.
local SHARK_FIN_TEMPLATE_NAME_LOWER = "shark fin"
local SHARK_FIN_DEFAULT_RELATIVE_SIZE = 0.45
-- Set true to include `shark fin` from ServerStorage.ConveyorItems in the random spawn pool.
local ENABLE_SHARK_FIN_CONVEYOR_TEMPLATE = false
local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"
local CONVEYOR_HEALTH_ATTRIBUTE = "ConveyorHealth"
local CONVEYOR_MAX_HEALTH_ATTRIBUTE = "ConveyorMaxHealth"
local CONVEYOR_HEALTH_MIN = 1
local CONVEYOR_HEALTH_MAX = 20
local CONVEYOR_HIT_DAMAGE_MIN = 1
local CONVEYOR_HIT_DAMAGE_MAX = 1
local RARE_GLOW_ROLL_MAX = 100
local RARE_GOLD_GLOW_CHANCE_PERCENT = 1
local RARE_PURPLE_GLOW_CHANCE_PERCENT = 10
local RARE_BLUE_GLOW_CHANCE_PERCENT = 20
local CONVEYOR_RARE_GOLD_ATTRIBUTE = "ConveyorRareGoldGlow"
local GOLD_TIER_HEALTH_MIN = 50
local GOLD_TIER_HEALTH_MAX = 100
local CONVEYOR_RARE_PURPLE_ATTRIBUTE = "ConveyorRarePurpleGlow"
local CONVEYOR_RARE_BLUE_ATTRIBUTE = "ConveyorRareBlueGlow"
local PURPLE_TIER_HEALTH_MIN = 25
local PURPLE_TIER_HEALTH_MAX = 50
local BLUE_TIER_HEALTH_MIN = 10
local BLUE_TIER_HEALTH_MAX = 30
local CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE = "ConveyorItemCashReward"
local NO_GLOW_CASH_MIN = 1
local NO_GLOW_CASH_MAX = 20
local NO_GLOW_HIGH_HP_CASH_MIN = 10
local NO_GLOW_HIGH_HP_CASH_MAX = 30
local NO_GLOW_HIGH_HP_THRESHOLD = 10
local BLUE_CASH_MIN = 25
local BLUE_CASH_MAX = 50
local PURPLE_CASH_MIN = 50
local PURPLE_CASH_MAX = 75
local GOLD_CASH_MIN = 100
local GOLD_CASH_MAX = 150
local TURRET_FLOAT_GOAL_HEIGHT = 6
local FLOAT_TO_TURRET_SECONDS = 1.9
local FLOAT_SHRINK_END_SCALE = 0.1
local CASH_POP_RISE_STUDS = 8
local CASH_POP_DURATION = 1.5
local CASH_POP_FADE_START_ALPHA = 0.42
local CASH_POP_TEXT_COLOR = Color3.fromRGB(72, 235, 130)
local CASH_POP_STROKE_COLOR = Color3.fromRGB(14, 72, 36)
local FLASH_DEBOUNCE_ATTRIBUTE = "ConveyorHitFlashActive"
local FLASH_BLINK_COUNT = 1
local FLASH_ON_TIME = 0.12
local FLASH_OFF_TIME = 0.04
-- Red hit-net PNG stays on longer than the part/decal flash tint.
local FISH_NET_RED_PULSE_SEC = 0.16
-- Fish net uses BillboardGui; keep it longer than the red flash so it reads clearly.
local FISH_NET_VISIBLE_SEC = 0.45
-- Player harpoon kill: reel catch to muzzle this long before payout.
local HARPOON_REEL_KILL_DURATION_SEC = 2.1
-- Nearly-invisible BaseParts (e.g. water splash anchors) still get a readable red tint during flash.
local FLASH_VIS_MAX_TRANSPARENCY = 0.32
-- flashModelRed spawns a brief fish-net overlay on every conveyor anti-air hit.
local HIT_FISH_NET_FOLDER_NAME = "HitFishNet"
-- Full "rbxassetid://..." or numeric id string; leave nil for procedural beam crosshatch.
local WATER_SPLASH_NET_TEXTURE_ID: string? = "rbxassetid://135625585340416"
-- Must match WaterSplashSpawner / JungleSplashTargetSpawner hit attributes.
local IS_WATER_SPLASH_ATTRIBUTE = "IsWaterSplash"
local SPLASH_HIT_COLLIDER_NAME = "SplashHitCollider"
local WATER_SPLASHES_FOLDER_NAME = "WaterSplashes"
local ANTI_AIR_MODEL_NAME = "Anti Air"
local DEBUG_FLASH = true

local function isAntiAirModelName(name: string): boolean
	return string.find(name, "^" .. ANTI_AIR_MODEL_NAME) ~= nil
end

local function debugLog(...)
	if DEBUG_FLASH then
		warn("[AntiAirFlashServer]", ...)
	end
end

warn("[AntiAirFlashServer] Arena boundary target system started")

type ArenaBounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	beltY: number,
	widthX: number,
	depthZ: number,
}

type ActiveArenaItem = {
	model: Model,
	dir: Vector3,
	spawnOrigin: Vector3,
	distanceS: number,
	pathLength: number,
}

type ArenaRunnerState = {
	activeItems: { ActiveArenaItem },
	nextSpawnTime: number,
	templateBag: { Instance },
	templateBagIndex: number,
}

local arenaRunnerRef: ArenaRunnerState? = nil

local function registerArenaRunner(state: ArenaRunnerState)
	arenaRunnerRef = state
end

local function removeConveyorItemFromTracking(model: Model)
	local runner = arenaRunnerRef
	if not runner then
		return
	end
	for i = #runner.activeItems, 1, -1 do
		if runner.activeItems[i].model == model then
			table.remove(runner.activeItems, i)
			return
		end
	end
end

local function clearAllConveyorFish()
	local runner = arenaRunnerRef
	if runner then
		for i = #runner.activeItems, 1, -1 do
			local item = runner.activeItems[i].model
			if item and item.Parent then
				item:Destroy()
			end
			table.remove(runner.activeItems, i)
		end
	end

	local activeFolder = Workspace:FindFirstChild(ACTIVE_ITEMS_FOLDER)
	if activeFolder and activeFolder:IsA("Folder") then
		for _, child in activeFolder:GetChildren() do
			child:Destroy()
		end
	end
end

local function getOrCreateDeathVfxFolder(): Folder
	local existing = Workspace:FindFirstChild("ConveyorDeathVFX")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "ConveyorDeathVFX"
	folder.Parent = Workspace
	return folder
end

local function spawnWorldCashPopBillboard(worldPos: Vector3, amount: number)
	local anchor = Instance.new("Part")
	anchor.Name = "ConveyorCashPop"
	anchor.Size = Vector3.new(0.15, 0.15, 0.15)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local startPos = worldPos + Vector3.new(0, 2, 0)
	anchor.Position = startPos
	anchor.Parent = getOrCreateDeathVfxFolder()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CashPop"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 450
	billboard.Size = UDim2.fromOffset(140, 44)
	billboard.StudsOffsetWorldSpace = Vector3.zero
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = CASH_POP_TEXT_COLOR
	label.TextStrokeColor3 = CASH_POP_STROKE_COLOR
	label.TextStrokeTransparency = 0.35
	label.TextTransparency = 0
	label.Text = string.format("+$%d", amount)
	label.Parent = billboard

	local sizeCap = Instance.new("UITextSizeConstraint")
	sizeCap.MaxTextSize = 30
	sizeCap.MinTextSize = 14
	sizeCap.Parent = label

	local goalPos = startPos + Vector3.new(0, CASH_POP_RISE_STUDS, 0)
	local moveTween = TweenService:Create(
		anchor,
		TweenInfo.new(CASH_POP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = goalPos }
	)
	moveTween:Play()

	local fadeDuration = CASH_POP_DURATION * (1 - CASH_POP_FADE_START_ALPHA)
	task.delay(CASH_POP_DURATION * CASH_POP_FADE_START_ALPHA, function()
		if not label.Parent then
			return
		end
		local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)

	Debris:AddItem(anchor, CASH_POP_DURATION + 0.35)
end

local function fireSplashKillFishPreload(player: Player?, imageId: string)
	if not player or not player.Parent then
		return
	end
	local remote = ReplicatedStorage:FindFirstChild(SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, imageId)
	end
end

local SPLASH_KILL_FISH_VFX_PHASE_PREPARE = "prepare"
local SPLASH_KILL_FISH_VFX_PHASE_REVEAL = "reveal"

local function fireSplashKillFishVfxPhase(
	player: Player?,
	imageId: string,
	payout: number,
	phase: string,
	showWave: boolean?
)
	if not player or not player.Parent then
		return
	end
	local remote = ReplicatedStorage:FindFirstChild(SPLASH_KILL_FISH_VFX_REMOTE_NAME)
	if remote and remote:IsA("RemoteEvent") then
		if showWave == nil then
			remote:FireClient(player, imageId, payout, phase)
		else
			remote:FireClient(player, imageId, payout, phase, showWave)
		end
	end
end

local function getSplashKillFishImageId(model: Model): string
	local attr = model:GetAttribute(SPLASH_KILL_FISH_IMAGE_ID_ATTRIBUTE)
	if typeof(attr) == "string" and attr ~= "" then
		return attr
	end
	local imageId, _tier = SplashKillFishFrames.pickGameplayFish()
	return imageId
end

local function ensureSplashKillFishAttributes(model: Model): (string, string)
	local imageAttr = model:GetAttribute(SPLASH_KILL_FISH_IMAGE_ID_ATTRIBUTE)
	if typeof(imageAttr) == "string" and imageAttr ~= "" then
		local imageId = imageAttr
		local rarityAttr = model:GetAttribute(SPLASH_KILL_FISH_RARITY_ATTRIBUTE)
		if typeof(rarityAttr) == "string" and rarityAttr ~= "" then
			return imageId, rarityAttr
		end
		local tier = SplashKillFishFrames.inferTierForImageId(imageId)
		model:SetAttribute(SPLASH_KILL_FISH_RARITY_ATTRIBUTE, tier)
		return imageId, tier
	end
	local imageId, tier = SplashKillFishFrames.pickGameplayFish()
	model:SetAttribute(SPLASH_KILL_FISH_IMAGE_ID_ATTRIBUTE, imageId)
	model:SetAttribute(SPLASH_KILL_FISH_RARITY_ATTRIBUTE, tier)
	return imageId, tier
end

local function preloadActiveSplashFishForPlayer(player: Player)
	local folder = Workspace:FindFirstChild(WATER_SPLASHES_FOLDER_NAME)
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local imageId = child:GetAttribute(SPLASH_KILL_FISH_IMAGE_ID_ATTRIBUTE)
			if typeof(imageId) == "string" and imageId ~= "" then
				fireSplashKillFishPreload(player, imageId)
			end
		end
	end
end

local function getSplashKillFishPayout(model: Model): number
	local payoutAttr = model:GetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE)
	return if typeof(payoutAttr) == "number" then payoutAttr else 0
end

local function assignAndPrepareSplashKillFishVfx(model: Model, rewardPlayer: Player)
	local imageId, _tier = ensureSplashKillFishAttributes(model)
	fireSplashKillFishVfxPhase(rewardPlayer, imageId, getSplashKillFishPayout(model), SPLASH_KILL_FISH_VFX_PHASE_PREPARE)
end

local function finishSplashKillAtTurret(rewardPlayer: Player?, model: Model, payout: number)
	if rewardPlayer and rewardPlayer.Parent and payout > 0 then
		Money.addCash(rewardPlayer, payout)
		MatchRoundBridge.recordCoinWon(rewardPlayer, payout)
	end
	if rewardPlayer and rewardPlayer.Parent then
		local imageId = getSplashKillFishImageId(model)
		local mapId = SplashKillFishFrames.getActiveMapId()
		local _ok, _newCount, wasFirstDiscovery = FishCollectionService.grantFishToPlayer(rewardPlayer, mapId, imageId)
		fireSplashKillFishVfxPhase(
			rewardPlayer,
			imageId,
			payout,
			SPLASH_KILL_FISH_VFX_PHASE_REVEAL,
			wasFirstDiscovery
		)
	end
	local fishNet = model:FindFirstChild(HIT_FISH_NET_FOLDER_NAME)
	if fishNet then
		fishNet:Destroy()
	end
	if model.Parent then
		model:Destroy()
	end
end

local function isMonsterSplashTarget(model: Model): boolean
	return model:GetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE) == SplashKillFishFrames.TARGET_KIND_MONSTER
end

local function beginMonsterSubmerge(model: Model)
	model:SetAttribute(SplashKillFishFrames.MONSTER_PHASE_ATTRIBUTE, SplashKillFishFrames.MONSTER_PHASE_SUBMERGE)
	local hit = model:FindFirstChild(SPLASH_HIT_COLLIDER_NAME)
	if hit and hit:IsA("BasePart") then
		hit.CanQuery = false
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanQuery = false
		end
	end
end

local function getMonsterSubmergeDurationSec(): number
	return MatchSplashConfig.getJackpotTargetSubmergeDurationSec(MatchSplashConfig.getActiveMapId())
end

local function getConveyorItemsFolder(): Folder?
	local folder = ServerStorage:FindFirstChild(CONVEYOR_ITEMS_FOLDER)
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function getOrCreateActiveFolder(): Folder
	local existing = Workspace:FindFirstChild(ACTIVE_ITEMS_FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = ACTIVE_ITEMS_FOLDER
	folder.Parent = Workspace
	return folder
end

local function getOrCreateHitFlashRemote(): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(HIT_FLASH_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = HIT_FLASH_REMOTE_NAME
	remote.Parent = ReplicatedStorage
	return remote
end

local function getOrCreateHitFlashVfxRemote(): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(HIT_FLASH_VFX_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = HIT_FLASH_VFX_REMOTE_NAME
	remote.Parent = ReplicatedStorage
	return remote
end

local function getTemplatePool(): { Instance }
	local pool = {}
	local itemsFolder = getConveyorItemsFolder()
	if not itemsFolder then
		return pool
	end

	for _, child in itemsFolder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			if
				not ENABLE_SHARK_FIN_CONVEYOR_TEMPLATE
				and string.lower(child.Name) == SHARK_FIN_TEMPLATE_NAME_LOWER
			then
				continue
			end
			table.insert(pool, child)
		end
	end

	return pool
end

local function createFallbackItem(): Model
	local model = Instance.new("Model")
	model.Name = "FallbackCrate"

	local part = Instance.new("Part")
	part.Name = "Primary"
	part.Size = Vector3.new(3, 3, 3)
	part.Color = Color3.fromRGB(190, 124, 66)
	part.Material = Enum.Material.WoodPlanks
	part.Anchored = true
	part.CanCollide = true
	part.Parent = model

	model.PrimaryPart = part
	return model
end

local function normalizeSpawnedModel(instance: Instance): Model
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

local function chooseRandomTemplate(pool: { Instance }): Instance?
	if #pool == 0 then
		return nil
	end

	local index = math.random(1, #pool)
	return pool[index]
end

local function buildShuffledTemplateBag(pool: { Instance }): { Instance }
	local bag = {}
	for _, template in pool do
		table.insert(bag, template)
	end

	for i = #bag, 2, -1 do
		local j = math.random(1, i)
		bag[i], bag[j] = bag[j], bag[i]
	end

	return bag
end

local function getNextTemplate(runner: ArenaRunnerState, pool: { Instance }): Instance?
	if #pool == 0 then
		return nil
	end

	if #runner.templateBag == 0 or runner.templateBagIndex > #runner.templateBag then
		runner.templateBag = buildShuffledTemplateBag(pool)
		runner.templateBagIndex = 1
	end

	local template = runner.templateBag[runner.templateBagIndex]
	runner.templateBagIndex += 1
	return template
end

local function getClampedScaleForBounds(model: Model, desiredScale: number): number
	local size = model:GetExtentsSize()
	local largestAxis = math.max(size.X, size.Y, size.Z)
	if largestAxis <= 0 then
		return desiredScale
	end

	local maxAllowedScale = MAX_ITEM_BOUNDS_STUDS / largestAxis
	if desiredScale > maxAllowedScale then
		return maxAllowedScale
	end

	return desiredScale
end

local function getLargestModelAxis(model: Model): number
	local size = model:GetExtentsSize()
	return math.max(size.X, size.Y, size.Z)
end

local function getNormalizedDesiredScale(model: Model, randomScale: number): number
	local largestAxis = getLargestModelAxis(model)
	if largestAxis <= 0 then
		return randomScale
	end

	-- Normalize all templates to a similar baseline size before variation.
	local baseNormalizeScale = BASE_TEMPLATE_MAX_AXIS_STUDS / largestAxis
	return randomScale * baseNormalizeScale
end

local function getUniformScaleForTargetSize(model: Model): number
	local largestAxis = getLargestModelAxis(model)
	if largestAxis <= 0 then
		return 1
	end

	return TARGET_ITEM_MAX_AXIS_STUDS / largestAxis
end

local function sanitizeSpawnedModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		elseif descendant:IsA("BasePart") then
			local largestPartAxis = math.max(descendant.Size.X, descendant.Size.Y, descendant.Size.Z)
			if largestPartAxis > MAX_PART_AXIS_STUDS and largestPartAxis > 0 then
				local ratio = MAX_PART_AXIS_STUDS / largestPartAxis
				descendant.Size = descendant.Size * ratio
			end
		elseif descendant:IsA("SpecialMesh") then
			local largestMeshAxis = math.max(descendant.Scale.X, descendant.Scale.Y, descendant.Scale.Z)
			if largestMeshAxis > MAX_SPECIAL_MESH_AXIS_SCALE and largestMeshAxis > 0 then
				local ratio = MAX_SPECIAL_MESH_AXIS_SCALE / largestMeshAxis
				descendant.Scale = descendant.Scale * ratio
			end
		end
	end
end

local function getAntiAirTurretModelFromProjectile(part: BasePart): Model?
	local bulletTag = part:FindFirstChild("bullet")
	if not bulletTag then
		return nil
	end

	local sourcePartRef = bulletTag:FindFirstChild("Value")
	if not sourcePartRef or not sourcePartRef:IsA("ObjectValue") then
		return nil
	end

	local sourcePart = sourcePartRef.Value
	if not sourcePart or not sourcePart:IsA("BasePart") then
		return nil
	end

	local current = sourcePart.Parent
	while current do
		if current:IsA("Model") and isAntiAirModelName(current.Name) then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function isAntiAirTurretProjectile(part: BasePart): boolean
	return getAntiAirTurretModelFromProjectile(part) ~= nil
end

local function getAntiAirTurretModelForPlayer(player: Player): Model?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.SeatPart then
		return nil
	end

	local current = humanoid.SeatPart.Parent
	while current do
		if current:IsA("Model") and isAntiAirModelName(current.Name) then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function getTurretGunnerPlayer(turretModel: Model?): Player?
	if not turretModel or not turretModel.Parent then
		return nil
	end

	local seat: Seat? = nil
	local preferred = turretModel:FindFirstChild("Seat", true)
	if preferred and preferred:IsA("Seat") then
		seat = preferred
	else
		for _, d in turretModel:GetDescendants() do
			if d:IsA("Seat") then
				seat = d
				break
			end
		end
	end

	if not seat then
		return nil
	end

	local humanoid = seat.Occupant
	if not humanoid then
		return nil
	end

	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function getTurretBillboardWorldPosition(turretModel: Model): Vector3?
	local ok, cf, size = pcall(function()
		return turretModel:GetBoundingBox()
	end)
	if ok and cf and size then
		local topY = cf.Position.Y + size.Y * 0.5
		return Vector3.new(cf.Position.X, topY + TURRET_FLOAT_GOAL_HEIGHT, cf.Position.Z)
	end

	if turretModel.PrimaryPart then
		return turretModel.PrimaryPart.Position + Vector3.new(0, TURRET_FLOAT_GOAL_HEIGHT, 0)
	end

	local anyPart = turretModel:FindFirstChildWhichIsA("BasePart", true)
	return anyPart and (anyPart.Position + Vector3.new(0, TURRET_FLOAT_GOAL_HEIGHT, 0)) or nil
end

local function floatConveyorModelTowardTurret(model: Model, turretModel: Model, onArrived: (() -> ())?)
	if not turretModel.Parent then
		if onArrived then
			onArrived()
		elseif model.Parent then
			model:Destroy()
		end
		return
	end

	local goalPos = getTurretBillboardWorldPosition(turretModel)
	if not goalPos then
		goalPos = turretModel:GetPivot().Position + Vector3.new(0, TURRET_FLOAT_GOAL_HEIGHT, 0)
	end

	task.spawn(function()
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end

		local spawnScale = model:GetAttribute(SCALE_ATTRIBUTE)
		if typeof(spawnScale) ~= "number" or spawnScale <= 0 then
			spawnScale = 1
		end

		local startPivot = model:GetPivot()
		local sx, sy, sz = startPivot:ToOrientation()
		local startPos = startPivot.Position
		local duration = FLOAT_TO_TURRET_SECONDS
		local elapsed = 0

		while elapsed < duration and model.Parent do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local eased = 1 - (1 - alpha) * (1 - alpha)
			local newPos = startPos:Lerp(goalPos, eased)
			local scaleMult = 1 + (FLOAT_SHRINK_END_SCALE - 1) * eased
			pcall(function()
				model:ScaleTo(spawnScale * scaleMult)
			end)
			model:PivotTo(CFrame.new(newPos) * CFrame.Angles(sx, sy, sz))
		end

		if onArrived then
			if model.Parent then
				onArrived()
			end
		elseif model.Parent then
			model:Destroy()
		end
	end)
end

local function getPartWorldCornersForNet(part: BasePart): { Vector3 }
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

-- World-space AABB for net VFX only; excludes fat invisible splash hit parts so billboard lift/size matches visuals.
local function getModelBoundingBoxForNetVfx(model: Model): (boolean, CFrame, Vector3)
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local any = false

	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and inst.Name ~= SPLASH_HIT_COLLIDER_NAME then
			for _, v in getPartWorldCornersForNet(inst) do
				any = true
				if v.X < minX then minX = v.X end
				if v.X > maxX then maxX = v.X end
				if v.Y < minY then minY = v.Y end
				if v.Y > maxY then maxY = v.Y end
				if v.Z < minZ then minZ = v.Z end
				if v.Z > maxZ then maxZ = v.Z end
			end
		end
	end

	if not any or minX >= maxX or minY >= maxY or minZ >= maxZ then
		return false, CFrame.new(), Vector3.zero
	end

	local center = Vector3.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
	local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	return true, CFrame.new(center), size
end

local function normalizeRbxAssetId(id: string?): string?
	if not id or id == "" then
		return nil
	end
	if string.sub(id, 1, 13) == "rbxassetid://" then
		return id
	end
	return "rbxassetid://" .. id
end

local function resolveNetTextureId(): string?
	local id = MatchSplashConfig.getForActiveMap().hitNetTextureId or WATER_SPLASH_NET_TEXTURE_ID
	return normalizeRbxAssetId(id)
end

local function resolveNetTextureIdRed(): string?
	local visual = MatchSplashConfig.getForActiveMap()
	local id = visual.hitNetTextureIdRed or MatchSplashConfig.DEFAULT_HIT_NET_RED
	return normalizeRbxAssetId(id)
end

local function findHitNetImageLabel(model: Model): ImageLabel?
	local folder = model:FindFirstChild(HIT_FISH_NET_FOLDER_NAME)
	if not folder then
		return nil
	end
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("ImageLabel") and descendant.Name == "NetImage" then
			return descendant
		end
	end
	return nil
end

local function modelHasVisibleHitFlashParts(model: Model): boolean
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= SPLASH_HIT_COLLIDER_NAME then
			if descendant.Transparency < 0.95 then
				return true
			end
		end
	end
	return false
end

local function resolveHitNetBillboardPx(model: Model, bboxSize: Vector3): number
	local visual = MatchSplashConfig.getForActiveMap()
	local overridePx = visual.hitNetBillboardPx
	if typeof(overridePx) == "number" and overridePx > 0 then
		return math.clamp(math.floor(overridePx), 80, 380)
	end

	local targetKind = model:GetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE)
	if targetKind == SplashKillFishFrames.TARGET_KIND_SHARK then
		local mapId = MatchSplashConfig.getActiveMapId()
		local spreadStuds = MatchSplashConfig.getCommonTargetStuds(mapId)
		local sizeTier = model:GetAttribute(SplashKillFishFrames.TARGET_SIZE_TIER_ATTRIBUTE)
		if sizeTier == SplashKillFishFrames.TARGET_SIZE_COMMON then
			return math.clamp(math.floor(spreadStuds * 7), 80, 380)
		end
		return math.clamp(math.floor(spreadStuds * 10), 120, 380)
	end
	if targetKind == SplashKillFishFrames.TARGET_KIND_BOAT then
		local spreadStuds = MatchSplashConfig.getCommonTargetStuds(MatchSplashConfig.getActiveMapId())
		return math.clamp(math.floor(spreadStuds * 10), 120, 380)
	end
	if targetKind == SplashKillFishFrames.TARGET_KIND_MONSTER then
		local spreadStuds = MatchSplashConfig.getCommonTargetStuds(MatchSplashConfig.getActiveMapId())
		return math.clamp(math.floor(spreadStuds * 10), 120, 380)
	end

	local spread = math.max(bboxSize.X, bboxSize.Y, bboxSize.Z)
	return math.clamp(math.floor(spread * 10), 120, 380)
end

local function attachSplashFishNetHitFx(model: Model)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		return
	end

	local old = model:FindFirstChild(HIT_FISH_NET_FOLDER_NAME)
	if old then
		old:Destroy()
	end

	local okVfx, cf, size = getModelBoundingBoxForNetVfx(model)
	if not okVfx then
		local ok, cfFull, sizeFull = pcall(function()
			return model:GetBoundingBox()
		end)
		if not ok or typeof(cfFull) ~= "CFrame" or typeof(sizeFull) ~= "Vector3" then
			return
		end
		cf = cfFull
		size = sizeFull
	end

	local folder = Instance.new("Folder")
	folder.Name = HIT_FISH_NET_FOLDER_NAME
	folder.Parent = model

	local hx = math.max(size.X, 4) * 1.05
	local hz = math.max(size.Z, 4) * 1.05

	local texId = resolveNetTextureId()
	if texId then
		-- World-space billboard above bbox center so the net faces the camera (flat Texture Top was often edge-on).
		local liftStuds = math.max(size.Y * 0.42, 1) + 0.35
		local anchor = Instance.new("Part")
		anchor.Name = "NetBillboardAnchor"
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(cf.Position + Vector3.new(0, liftStuds, 0))
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Massless = true
		anchor.Transparency = 1
		anchor.Parent = folder

		local anchorWeld = Instance.new("WeldConstraint")
		anchorWeld.Part0 = anchor
		anchorWeld.Part1 = primary
		anchorWeld.Parent = anchor

		local px = resolveHitNetBillboardPx(model, size)

		local bb = Instance.new("BillboardGui")
		bb.Name = "HitFishNetBillboard"
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 550
		bb.Size = UDim2.fromOffset(px, px)
		bb.StudsOffsetWorldSpace = Vector3.zero
		bb.Parent = anchor

		local img = Instance.new("ImageLabel")
		img.Name = "NetImage"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = texId
		img.ImageTransparency = 0.08
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = bb
	else
		local plate = Instance.new("Part")
		plate.Name = "NetPlane"
		plate.Size = Vector3.new(hx, 0.08, hz)
		plate.CFrame = cf * CFrame.new(0, size.Y * 0.5 + 0.06, 0)
		plate.Anchored = true
		plate.CanCollide = false
		plate.CanQuery = false
		plate.CanTouch = false
		plate.Massless = true
		plate.Transparency = 1
		plate.Parent = folder

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = plate
		weld.Part1 = primary
		weld.Parent = plate

		local rope = Color3.fromRGB(85, 90, 100)
		local y = plate.Size.Y * 0.5 - 0.02
		local hx2 = hx * 0.48
		local hz2 = hz * 0.48

		local function beamBetween(p0: Vector3, p1: Vector3)
			local a0 = Instance.new("Attachment")
			a0.Position = p0
			a0.Parent = plate
			local a1 = Instance.new("Attachment")
			a1.Position = p1
			a1.Parent = plate
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0 = 0.07
			beam.Width1 = 0.07
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(rope)
			beam.Transparency = NumberSequence.new(0.15)
			beam.Parent = plate
		end

		beamBetween(Vector3.new(-hx2, y, -hz2), Vector3.new(hx2, y, hz2))
		beamBetween(Vector3.new(-hx2, y, hz2), Vector3.new(hx2, y, -hz2))
		beamBetween(Vector3.new(-hx2, y, 0), Vector3.new(hx2, y, 0))
		beamBetween(Vector3.new(0, y, -hz2), Vector3.new(0, y, hz2))
	end
end

local function flashModelRed(model: Model, persistFishNet: boolean?, pulseRedNetImage: boolean?)
	if model:GetAttribute(FLASH_DEBOUNCE_ATTRIBUTE) then
		debugLog("Skipped flash (debounced)", model:GetFullName())
		return
	end
	debugLog("Flashing model", model:GetFullName())
	model:SetAttribute(FLASH_DEBOUNCE_ATTRIBUTE, true)

	local originalColors: { [BasePart]: Color3 } = {}
	local originalTransparency: { [BasePart]: number } = {}
	local originalFaceColors: { [Instance]: Color3 } = {}
	local originalVfxColorSeq: { [Instance]: ColorSequence } = {}

	local useHighlight = modelHasVisibleHitFlashParts(model)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Name == SPLASH_HIT_COLLIDER_NAME then
				continue
			end
			if descendant.Transparency >= 0.95 then
				continue
			end
			originalColors[descendant] = descendant.Color
			originalTransparency[descendant] = descendant.Transparency
			descendant.Color = Color3.fromRGB(255, 110, 110)
			descendant.Transparency = math.min(descendant.Transparency, FLASH_VIS_MAX_TRANSPARENCY)
		elseif useHighlight and (descendant:IsA("Decal") or descendant:IsA("Texture")) then
			originalFaceColors[descendant] = descendant.Color3
			descendant.Color3 = Color3.fromRGB(255, 110, 110)
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			originalVfxColorSeq[descendant] = descendant.Color
			descendant.Color = ColorSequence.new(Color3.fromRGB(255, 110, 110))
		end
	end

	local highlight: Highlight? = nil
	if useHighlight then
		local h = Instance.new("Highlight")
		h.Name = "HitFlash"
		h.Adornee = model
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.FillColor = Color3.fromRGB(255, 110, 110)
		h.OutlineColor = Color3.fromRGB(255, 170, 170)
		h.FillTransparency = 0.25
		h.OutlineTransparency = 0.1
		h.Enabled = true
		h.Parent = model
		highlight = h
	end

	attachSplashFishNetHitFx(model)

	if pulseRedNetImage and not persistFishNet then
		local img = findHitNetImageLabel(model)
		local redId = resolveNetTextureIdRed()
		local normalId = resolveNetTextureId()
		if img and redId and normalId then
			img.Image = redId
			task.delay(FISH_NET_RED_PULSE_SEC, function()
				if img.Parent and model.Parent then
					img.Image = normalId
				end
			end)
		end
	end

	if not persistFishNet then
		task.delay(FISH_NET_VISIBLE_SEC, function()
			if not model.Parent then
				return
			end
			local fishNet = model:FindFirstChild(HIT_FISH_NET_FOLDER_NAME)
			if fishNet then
				fishNet:Destroy()
			end
		end)
	end

	task.spawn(function()
		task.wait(FLASH_ON_TIME)

		if highlight then
			highlight:Destroy()
		end
		for part, originalColor in originalColors do
			if part and part.Parent then
				part.Color = originalColor
				local ot = originalTransparency[part]
				if typeof(ot) == "number" then
					part.Transparency = ot
				end
			end
		end
		for inst, originalC in originalFaceColors do
			if inst and inst.Parent and (inst:IsA("Decal") or inst:IsA("Texture")) then
				inst.Color3 = originalC
			end
		end
		for inst, originalSeq in originalVfxColorSeq do
			if inst and inst.Parent then
				if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
					inst.Color = originalSeq
				end
			end
		end

		if model.Parent then
			model:SetAttribute(FLASH_DEBOUNCE_ATTRIBUTE, nil)
		end
	end)
end

local function applyRandomHitDamage(
	model: Model,
	turretModel: Model?,
	rewardPlayer: Player?,
	attackerPlayer: Player?,
	projectilePart: BasePart?
): ConveyorAntiAirBridge.PostHitRetract?
	local current = model:GetAttribute(CONVEYOR_HEALTH_ATTRIBUTE)
	local maxHealth = model:GetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE)
	if typeof(current) ~= "number" or typeof(maxHealth) ~= "number" then
		assignRandomConveyorHealth(model)
		current = model:GetAttribute(CONVEYOR_HEALTH_ATTRIBUTE)
		maxHealth = model:GetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE)
	end
	if typeof(current) ~= "number" then
		return nil
	end

	local damage = math.random(CONVEYOR_HIT_DAMAGE_MIN, CONVEYOR_HIT_DAMAGE_MAX)
	local newHealth = math.max(0, current - damage)
	model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, newHealth)

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid and humanoid.MaxHealth > 0 then
		humanoid.Health = math.clamp(newHealth, 0, humanoid.MaxHealth)
	end

	local isWaterSplash = model:GetAttribute(IS_WATER_SPLASH_ATTRIBUTE) == true
	local isMonster = isMonsterSplashTarget(model)
	local monsterSubmergeSec = if isMonster then getMonsterSubmergeDurationSec() else 0

	if newHealth <= 0 then
		if isMonster then
			beginMonsterSubmerge(model)
		end

		local payoutAttr = model:GetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE)
		local payout = if typeof(payoutAttr) == "number" then payoutAttr else 0

		if isWaterSplash and rewardPlayer and rewardPlayer.Parent then
			assignAndPrepareSplashKillFishVfx(model, rewardPlayer)
		end

		local shouldReel = projectilePart ~= nil
			and attackerPlayer ~= nil
			and turretModel ~= nil
			and turretModel.Parent ~= nil

		if shouldReel then
			removeConveyorItemFromTracking(model)
			model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, nil)
			model.Parent = getOrCreateDeathVfxFolder()

			local capturedTurret = turretModel :: Model
			local capturedReward = rewardPlayer
			local capturedPayout = payout
			local capturedModel = model
			local reelDuration = HARPOON_REEL_KILL_DURATION_SEC + monsterSubmergeSec

			return {
				retractDuration = reelDuration,
				retractFollowModel = model,
				retractFollowOffset = CFrame.new(0, 1.25, -14),
				deferSplashReelMeter = isWaterSplash and SplashReelConfig.TAP_TO_REEL_ENABLED,
				onRetractComplete = function()
					local isSplashKill = capturedModel:GetAttribute(IS_WATER_SPLASH_ATTRIBUTE) == true
					if isSplashKill then
						finishSplashKillAtTurret(capturedReward, capturedModel, capturedPayout)
						return
					end
					local payPos = getTurretBillboardWorldPosition(capturedTurret)
					if not payPos then
						payPos = capturedTurret:GetPivot().Position + Vector3.new(0, TURRET_FLOAT_GOAL_HEIGHT, 0)
					end
					if capturedPayout > 0 then
						spawnWorldCashPopBillboard(payPos, capturedPayout)
						if capturedReward and capturedReward.Parent then
							Money.addCash(capturedReward, capturedPayout)
							MatchRoundBridge.recordCoinWon(capturedReward, capturedPayout)
							local flyRemote = ReplicatedStorage:FindFirstChild(CASH_FLY_VFX_REMOTE_NAME)
							if flyRemote and flyRemote:IsA("RemoteEvent") then
								flyRemote:FireClient(capturedReward, payPos, capturedPayout)
							end
						end
					end
					local fishNet = capturedModel:FindFirstChild(HIT_FISH_NET_FOLDER_NAME)
					if fishNet then
						fishNet:Destroy()
					end
					if capturedModel.Parent then
						capturedModel:Destroy()
					end
				end,
			}
		end

		if payout > 0 and not isWaterSplash then
			local worldPos = model:GetPivot().Position
			spawnWorldCashPopBillboard(worldPos, payout)
			if rewardPlayer then
				Money.addCash(rewardPlayer, payout)
				MatchRoundBridge.recordCoinWon(rewardPlayer, payout)
				local flyRemote = ReplicatedStorage:FindFirstChild(CASH_FLY_VFX_REMOTE_NAME)
				if flyRemote and flyRemote:IsA("RemoteEvent") then
					flyRemote:FireClient(rewardPlayer, worldPos, payout)
				end
			end
		end

		removeConveyorItemFromTracking(model)
		model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, nil)

		if isWaterSplash and rewardPlayer and rewardPlayer.Parent then
			local capturedReward = rewardPlayer
			local capturedModel = model
			local capturedPayout = payout
			local capturedTurret = turretModel

			local function beginSplashKillFlow()
				if not capturedModel.Parent then
					return
				end
				capturedModel.Parent = getOrCreateDeathVfxFolder()
				if capturedTurret and capturedTurret.Parent then
					floatConveyorModelTowardTurret(capturedModel, capturedTurret, function()
						finishSplashKillAtTurret(capturedReward, capturedModel, capturedPayout)
					end)
				else
					finishSplashKillAtTurret(capturedReward, capturedModel, capturedPayout)
				end
			end

			if monsterSubmergeSec > 0 then
				task.delay(monsterSubmergeSec, beginSplashKillFlow)
			else
				beginSplashKillFlow()
			end
		elseif turretModel and turretModel.Parent then
			model.Parent = getOrCreateDeathVfxFolder()
			floatConveyorModelTowardTurret(model, turretModel)
		else
			if monsterSubmergeSec > 0 then
				task.delay(monsterSubmergeSec, function()
					if model.Parent then
						model:Destroy()
					end
				end)
			else
				model:Destroy()
			end
		end
	end

	return nil
end

local function onConveyorAntiAirHit(model: Model, attackerPlayer: Player?, projectilePart: BasePart?): ConveyorAntiAirBridge.PostHitRetract?
	local turretModel: Model? = nil
	if attackerPlayer then
		turretModel = getAntiAirTurretModelForPlayer(attackerPlayer)
	end
	if not turretModel and projectilePart then
		turretModel = getAntiAirTurretModelFromProjectile(projectilePart)
	end

	local rewardPlayer = attackerPlayer
	if not rewardPlayer then
		rewardPlayer = getTurretGunnerPlayer(turretModel)
	end

	local reelOpts = applyRandomHitDamage(model, turretModel, rewardPlayer, attackerPlayer, projectilePart)
	if model.Parent then
		local hp = model:GetAttribute(CONVEYOR_HEALTH_ATTRIBUTE)
		local isNonKill = typeof(hp) == "number" and hp > 0
		flashModelRed(model, reelOpts ~= nil, isNonKill)
	end
	return reelOpts
end

local function isConveyorItemModel(instance: Instance): boolean
	if not instance:IsA("Model") then
		return false
	end

	return instance:GetAttribute(CONVEYOR_ITEM_ATTRIBUTE) == true
end

local function getConveyorItemModelFromInstance(instance: Instance): Model?
	local current = instance
	while current do
		if current:IsA("Model") and isConveyorItemModel(current) then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function setupHitFlash(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Touched:Connect(function(otherPart)
				if not otherPart or not otherPart:IsA("BasePart") then
					return
				end

				if isAntiAirTurretProjectile(otherPart) then
					onConveyorAntiAirHit(model, nil, otherPart)
				end
			end)
		end
	end
end

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

local function expandPartXZBounds(part: BasePart, minX: number, maxX: number, minZ: number, maxZ: number): (number, number, number, number)
	local mnX, mxX, mnZ, mxZ = minX, maxX, minZ, maxZ
	for _, v in getPartWorldCorners(part) do
		mnX = math.min(mnX, v.X)
		mxX = math.max(mxX, v.X)
		mnZ = math.min(mnZ, v.Z)
		mxZ = math.max(mxZ, v.Z)
	end
	return mnX, mxX, mnZ, mxZ
end

local function partWorldMinCornerY(part: BasePart): number
	local minY = math.huge
	for _, v in getPartWorldCorners(part) do
		minY = math.min(minY, v.Y)
	end
	return minY
end

local function getWorkspaceBaseplateTopY(): number?
	local bp = Workspace:FindFirstChild("Baseplate")
	if bp and bp:IsA("BasePart") then
		return bp.Position.Y + bp.Size.Y * 0.5
	end
	return nil
end

local function computeArenaBounds(): ArenaBounds?
	local folder = Workspace:FindFirstChild(BOUNDARY_FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		warn("ArenaTargets: Workspace folder '" .. BOUNDARY_FOLDER_NAME .. "' not found; targets disabled.")
		return nil
	end

	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local minCornerY = math.huge
	local partCount = 0

	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") then
			minX, maxX, minZ, maxZ = expandPartXZBounds(desc, minX, maxX, minZ, maxZ)
			minCornerY = math.min(minCornerY, partWorldMinCornerY(desc))
			partCount += 1
		end
	end

	if partCount == 0 or minX >= maxX - 1e-4 or minZ >= maxZ - 1e-4 then
		warn("ArenaTargets: BulletArenaBoundaries has no BaseParts or degenerate XZ bounds; targets disabled.")
		return nil
	end

	-- Tall walls used average part center Y and floated targets. Prefer Workspace.Baseplate top; else lowest boundary corner Y.
	local baseTop = getWorkspaceBaseplateTopY()
	local floorY = if baseTop ~= nil then baseTop else minCornerY
	local beltY = floorY + Y_OFFSET
	local widthX = maxX - minX
	local depthZ = maxZ - minZ

	return {
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
		beltY = beltY,
		widthX = widthX,
		depthZ = depthZ,
	}
end

local function xzHorizontalDist(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function pickWeightedPathIndex(): number
	local total = 0
	for _, w in PATH_WEIGHTS do
		total += w
	end
	if total <= 0 then
		return math.random(1, 6)
	end
	local r = math.random(1, total)
	local acc = 0
	for i, w in PATH_WEIGHTS do
		acc += w
		if r <= acc then
			return i
		end
	end
	return #PATH_WEIGHTS
end

local function computeSpawnForPath(bounds: ArenaBounds, pathIndex: number, margin: number): (Vector3, Vector3, number)
	local minX, maxX, minZ, maxZ = bounds.minX, bounds.maxX, bounds.minZ, bounds.maxZ
	local beltY = bounds.beltY
	local widthX = bounds.widthX
	local depthZ = bounds.depthZ

	if pathIndex == 1 then
		local z = minZ + math.random() * depthZ
		local spawn = Vector3.new(minX - margin, beltY, z)
		local dir = Vector3.new(1, 0, 0)
		return spawn, dir, widthX + 2 * margin
	elseif pathIndex == 2 then
		local z = minZ + math.random() * depthZ
		local spawn = Vector3.new(maxX + margin, beltY, z)
		local dir = Vector3.new(-1, 0, 0)
		return spawn, dir, widthX + 2 * margin
	elseif pathIndex == 3 then
		local x = minX + math.random() * widthX
		local spawn = Vector3.new(x, beltY, maxZ + margin)
		local dir = Vector3.new(0, 0, -1)
		return spawn, dir, depthZ + 2 * margin
	elseif pathIndex == 4 then
		local x = minX + math.random() * widthX
		local spawn = Vector3.new(x, beltY, minZ - margin)
		local dir = Vector3.new(0, 0, 1)
		return spawn, dir, depthZ + 2 * margin
	elseif pathIndex == 5 then
		local planar = Vector3.new(widthX, 0, minZ - maxZ)
		local dir = planar.Unit
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local jitterRange = math.min(widthX, depthZ) * 0.25
		local jitter = (math.random() * 2 - 1) * jitterRange
		local corner = Vector3.new(minX, beltY, maxZ)
		local spawn = corner - dir * margin + perp * jitter
		return spawn, dir, planar.Magnitude + 2 * margin
	else
		local planar = Vector3.new(widthX, 0, maxZ - minZ)
		local dir = planar.Unit
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local jitterRange = math.min(widthX, depthZ) * 0.25
		local jitter = (math.random() * 2 - 1) * jitterRange
		local corner = Vector3.new(minX, beltY, minZ)
		local spawn = corner - dir * margin + perp * jitter
		return spawn, dir, planar.Magnitude + 2 * margin
	end
end

local function anchorModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
		end
	end
end

local function getModelPosition(model: Model): Vector3
	if model.PrimaryPart then
		return model.PrimaryPart.Position
	end

	local fallbackPart = model:FindFirstChildWhichIsA("BasePart", true)
	return fallbackPart and fallbackPart.Position or Vector3.zero
end

local function setModelPosition(model: Model, position: Vector3)
	local pivot = model:GetPivot()
	local _, yaw, _ = pivot:ToOrientation()
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
end

local function snapModelToBelt(model: Model, beltY: number)
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local bottomY = bboxCFrame.Position.Y - (bboxSize.Y * 0.5)
	local yDelta = beltY - bottomY
	if math.abs(yDelta) > 0.001 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, yDelta, 0))
	end
end

local function isSpawnBlockedBySpacing(spawnXZ: Vector3, spawnScale: number, activeItems: { ActiveArenaItem }): boolean
	for _, entry in activeItems do
		local pos = getModelPosition(entry.model)
		local theirScale = entry.model:GetAttribute(SCALE_ATTRIBUTE)
		local ts = typeof(theirScale) == "number" and theirScale or 1
		local need = ITEM_SPACING * math.max(spawnScale, ts, 1)
		if xzHorizontalDist(spawnXZ, pos) < need then
			return true
		end
	end
	return false
end

local function setConveyorModelHealth(model: Model, maxHealth: number)
	model:SetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE, maxHealth)
	model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, maxHealth)

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
	end
end

local function assignRandomConveyorHealth(model: Model)
	local maxHealth = math.random(CONVEYOR_HEALTH_MIN, CONVEYOR_HEALTH_MAX)
	setConveyorModelHealth(model, maxHealth)
end

local function maybeApplyRareGlow(model: Model)
	local roll = math.random(1, RARE_GLOW_ROLL_MAX)
	local goldThreshold = RARE_GOLD_GLOW_CHANCE_PERCENT
	local purpleThreshold = goldThreshold + RARE_PURPLE_GLOW_CHANCE_PERCENT
	local blueThreshold = purpleThreshold + RARE_BLUE_GLOW_CHANCE_PERCENT
	local glowName = ""
	local fillColor = Color3.fromRGB(255, 200, 40)
	local outlineColor = Color3.fromRGB(255, 235, 140)

	if roll <= goldThreshold then
		model:SetAttribute(CONVEYOR_RARE_GOLD_ATTRIBUTE, true)
		glowName = "ConveyorRareGoldGlow"
	elseif roll <= purpleThreshold then
		model:SetAttribute(CONVEYOR_RARE_PURPLE_ATTRIBUTE, true)
		glowName = "ConveyorRarePurpleGlow"
		fillColor = Color3.fromRGB(165, 95, 255)
		outlineColor = Color3.fromRGB(210, 170, 255)
	elseif roll <= blueThreshold then
		model:SetAttribute(CONVEYOR_RARE_BLUE_ATTRIBUTE, true)
		glowName = "ConveyorRareBlueGlow"
		fillColor = Color3.fromRGB(75, 170, 255)
		outlineColor = Color3.fromRGB(170, 220, 255)
	else
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = glowName
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = fillColor
	highlight.OutlineColor = outlineColor
	highlight.FillTransparency = 0.52
	highlight.OutlineTransparency = 0.12
	highlight.Parent = model
end

local function spawnArenaItem(
	runner: ArenaRunnerState,
	bounds: ArenaBounds,
	templates: { Instance },
	activeFolder: Folder
): boolean
	if #runner.activeItems >= MAX_ACTIVE_ITEMS then
		return false
	end

	local pathIndex = pickWeightedPathIndex()
	local spawnOrigin, dir, pathLength = computeSpawnForPath(bounds, pathIndex, SPAWN_MARGIN)
	local spawnXZ = Vector3.new(spawnOrigin.X, bounds.beltY, spawnOrigin.Z)

	local template = getNextTemplate(runner, templates)
	local instance: Instance
	if template then
		instance = template:Clone()
	else
		instance = createFallbackItem()
	end

	local model = normalizeSpawnedModel(instance)
	if not model.PrimaryPart then
		model:Destroy()
		return false
	end

	sanitizeSpawnedModel(model)
	local spawnScale = getUniformScaleForTargetSize(model)
	spawnScale = getClampedScaleForBounds(model, spawnScale)
	local relativeSize = model:GetAttribute(SPAWN_RELATIVE_SIZE_ATTRIBUTE)
	if typeof(relativeSize) ~= "number" or relativeSize <= 0 then
		if string.lower(model.Name) == SHARK_FIN_TEMPLATE_NAME_LOWER then
			relativeSize = SHARK_FIN_DEFAULT_RELATIVE_SIZE
		end
	end
	if typeof(relativeSize) == "number" and relativeSize > 0 then
		spawnScale *= math.clamp(relativeSize, SPAWN_RELATIVE_SIZE_MIN, SPAWN_RELATIVE_SIZE_MAX)
		spawnScale = getClampedScaleForBounds(model, spawnScale)
	end
	model:ScaleTo(spawnScale)
	model:SetAttribute(SCALE_ATTRIBUTE, spawnScale)

	if isSpawnBlockedBySpacing(spawnXZ, spawnScale, runner.activeItems) then
		model:Destroy()
		return false
	end

	model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, true)
	assignRandomConveyorHealth(model)

	anchorModel(model)
	model.Parent = activeFolder
	setupHitFlash(model)
	maybeApplyRareGlow(model)
	if model:GetAttribute(CONVEYOR_RARE_GOLD_ATTRIBUTE) == true then
		setConveyorModelHealth(model, math.random(GOLD_TIER_HEALTH_MIN, GOLD_TIER_HEALTH_MAX))
	elseif model:GetAttribute(CONVEYOR_RARE_PURPLE_ATTRIBUTE) == true then
		setConveyorModelHealth(model, math.random(PURPLE_TIER_HEALTH_MIN, PURPLE_TIER_HEALTH_MAX))
	elseif model:GetAttribute(CONVEYOR_RARE_BLUE_ATTRIBUTE) == true then
		setConveyorModelHealth(model, math.random(BLUE_TIER_HEALTH_MIN, BLUE_TIER_HEALTH_MAX))
	end

	if model:GetAttribute(CONVEYOR_RARE_GOLD_ATTRIBUTE) == true then
		model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(GOLD_CASH_MIN, GOLD_CASH_MAX))
	elseif model:GetAttribute(CONVEYOR_RARE_PURPLE_ATTRIBUTE) == true then
		model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(PURPLE_CASH_MIN, PURPLE_CASH_MAX))
	elseif model:GetAttribute(CONVEYOR_RARE_BLUE_ATTRIBUTE) == true then
		model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(BLUE_CASH_MIN, BLUE_CASH_MAX))
	else
		local spawnMaxHp = model:GetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE)
		if typeof(spawnMaxHp) == "number" and spawnMaxHp > NO_GLOW_HIGH_HP_THRESHOLD then
			model:SetAttribute(
				CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE,
				math.random(NO_GLOW_HIGH_HP_CASH_MIN, NO_GLOW_HIGH_HP_CASH_MAX)
			)
		else
			model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, math.random(NO_GLOW_CASH_MIN, NO_GLOW_CASH_MAX))
		end
	end

	setModelPosition(model, spawnXZ)
	snapModelToBelt(model, bounds.beltY)

	table.insert(runner.activeItems, {
		model = model,
		dir = dir,
		spawnOrigin = spawnXZ,
		distanceS = 0,
		pathLength = pathLength,
	})
	return true
end

local function updateArenaTargets(activeItems: { ActiveArenaItem }, dt: number, beltY: number)
	local i = 1
	while i <= #activeItems do
		local entry = activeItems[i]
		local item = entry.model
		if not item.Parent then
			table.remove(activeItems, i)
			continue
		end

		entry.distanceS += CONVEYOR_SPEED * dt

		if entry.distanceS >= entry.pathLength - END_REACHED_THRESHOLD then
			item:Destroy()
			table.remove(activeItems, i)
			continue
		end

		local nextPosition = entry.spawnOrigin + entry.dir * entry.distanceS
		nextPosition = Vector3.new(nextPosition.X, beltY, nextPosition.Z)
		setModelPosition(item, nextPosition)
		snapModelToBelt(item, beltY)

		i += 1
	end
end

local function runArenaTargetSystem()
	math.randomseed(DateTime.now().UnixTimestampMillis)

	local bounds = computeArenaBounds()
	if not bounds then
		return
	end

	local runner: ArenaRunnerState = {
		activeItems = {},
		nextSpawnTime = os.clock() + math.random() * SPAWN_INTERVAL,
		templateBag = {},
		templateBagIndex = 1,
	}
	registerArenaRunner(runner)

	local activeFolder = getOrCreateActiveFolder()
	local templates = getTemplatePool()
	if #templates == 0 then
		warn("ArenaTargets: No templates in ServerStorage.ConveyorItems. Using fallback crates.")
	end

	local lastTick = os.clock()
	while true do
		local now = os.clock()
		local dt = now - lastTick
		lastTick = now

		updateArenaTargets(runner.activeItems, dt, bounds.beltY)

		if #runner.activeItems < TARGET_ACTIVE_ITEMS then
			runner.nextSpawnTime = math.min(runner.nextSpawnTime, now)
		end

		if
			MatchRoundBridge.allowFishSpawn()
			and #runner.activeItems < TARGET_ACTIVE_ITEMS
			and now >= runner.nextSpawnTime
		then
			local didSpawn = spawnArenaItem(runner, bounds, templates, activeFolder)
			if didSpawn then
				runner.nextSpawnTime = now + SPAWN_INTERVAL
			else
				runner.nextSpawnTime = now + 0.1
			end
		end

		task.wait()
	end
end

local hitFlashRemote = getOrCreateHitFlashRemote()

hitFlashRemote.OnServerEvent:Connect(function(player, hitInstance)
	debugLog(
		"Remote received",
		"player=",
		player and player.Name or "nil",
		"instance=",
		(typeof(hitInstance) == "Instance" and hitInstance:GetFullName()) or tostring(hitInstance)
	)

	if typeof(hitInstance) ~= "Instance" then
		debugLog("Rejected: argument is not an Instance")
		return
	end

	local hitModel = getConveyorItemModelFromInstance(hitInstance)
	if not hitModel then
		debugLog("Rejected: no conveyor item model found in ancestors")
		return
	end

	if player then
		if not MatchRoundBridge.allowShooting(player) then
			return
		end
	end

	debugLog("Resolved conveyor model", hitModel:GetFullName())
	onConveyorAntiAirHit(hitModel, player, nil)
end)

local hitFlashVfxRemote = getOrCreateHitFlashVfxRemote()

hitFlashVfxRemote.OnServerEvent:Connect(function(player, hitInstance)
	debugLog(
		"Vfx remote received",
		"player=",
		player and player.Name or "nil",
		"instance=",
		(typeof(hitInstance) == "Instance" and hitInstance:GetFullName()) or tostring(hitInstance)
	)

	if typeof(hitInstance) ~= "Instance" then
		debugLog("Vfx rejected: argument is not an Instance")
		return
	end

	local hitModel = getConveyorItemModelFromInstance(hitInstance)
	if not hitModel then
		debugLog("Vfx rejected: no conveyor item model found in ancestors")
		return
	end

	if player and not MatchRoundBridge.allowShooting(player) then
		return
	end

	if hitModel.Parent then
		debugLog("Vfx flash only", hitModel:GetFullName())
		flashModelRed(hitModel, false, true)
	end
end)

ConveyorAntiAirBridge.setProjectileConveyorHitHandler(function(model: Model, projectile: BasePart, shooter: Player?)
	if shooter then
		if not MatchRoundBridge.allowShooting(shooter) then
			return nil
		end
	end
	return onConveyorAntiAirHit(model, shooter, projectile)
end)

MatchRoundBridge.setCallbacks({
	clearFishNow = clearAllConveyorFish,
})

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		preloadActiveSplashFishForPlayer(player)
	end)
end)

if CONVEYOR_ARENA_TARGETS_ENABLED then
	task.spawn(runArenaTargetSystem)
else
	warn("[ConveyorSystem] Arena target spawning disabled (CONVEYOR_ARENA_TARGETS_ENABLED = false)")
end
