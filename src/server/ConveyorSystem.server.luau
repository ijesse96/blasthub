local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local HIT_FLASH_REMOTE_NAME = "AntiAirConveyorHitFlash"
local CASH_FLY_VFX_REMOTE_NAME = "CashFlyVfx"
local SHOT_COST_AMOUNT = 1
local SHOT_COST_DEBOUNCE_SECONDS = 0.12

local moneyModule = script.Parent:FindFirstChild("Money") or script.Parent:WaitForChild("Money", 30)
if not moneyModule or not moneyModule:IsA("ModuleScript") then
	error(
		"[ConveyorSystem] Expected ModuleScript 'Money' as a sibling under ServerScriptService.Server (add src/server/Money.luau and sync with Rojo)."
	)
end
local Money = require(moneyModule)

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
ensureRemoteEvent(CASH_FLY_VFX_REMOTE_NAME)

local CONVEYOR_ITEMS_FOLDER = "ConveyorItems"
local ACTIVE_ITEMS_FOLDER = "ConveyorActiveItems"
local CONVEYOR_NAME_PREFIX = "Conveyor"

local SPAWN_INTERVAL = 2.1
local CONVEYOR_SPEED = 11
local MAX_ACTIVE_ITEMS_PER_CONVEYOR = 16
local TARGET_ACTIVE_ITEMS_PER_CONVEYOR = 9
local ITEM_SPACING = 26
local END_REACHED_THRESHOLD = 3
local Y_OFFSET = 2.5
local TARGET_ITEM_MAX_AXIS_STUDS = 40
local MAX_ITEM_BOUNDS_STUDS = 40
local BASE_TEMPLATE_MAX_AXIS_STUDS = 2.5
local MAX_PART_AXIS_STUDS = 40
local MAX_SPECIAL_MESH_AXIS_SCALE = 40
local SCALE_ATTRIBUTE = "ConveyorSpawnScale"
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
local GOLD_TIER_HEALTH_MIN = 500
local GOLD_TIER_HEALTH_MAX = 1000
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
local PURPLE_CASH_MAX = 100
local GOLD_CASH_REWARD = 500
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
local ANTI_AIR_MODEL_NAME = "Anti Air"
local DEBUG_FLASH = true

local function isAntiAirModelName(name: string): boolean
	return string.find(name, "^" .. ANTI_AIR_MODEL_NAME) ~= nil
end

local function isPlayerInAllowedTurret(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not humanoid.SeatPart then
		return false
	end

	local current: Instance? = humanoid.SeatPart.Parent
	while current do
		if current:IsA("Model") and isAntiAirModelName(current.Name) then
			return true
		end
		current = current.Parent
	end

	return false
end

local function debugLog(...)
	if DEBUG_FLASH then
		warn("[AntiAirFlashServer]", ...)
	end
end

warn("[AntiAirFlashServer] ConveyorSystem started")

type ConveyorState = {
	model: Model,
	startPart: BasePart,
	endPart: BasePart,
	dir: Vector3,
	length: number,
	beltY: number,
	activeItems: { Model },
	nextSpawnTime: number,
	templateBag: { Instance },
	templateBagIndex: number,
}

local conveyorStatesRef: { ConveyorState } = {}

local function registerConveyorStatesForTracking(states: { ConveyorState })
	conveyorStatesRef = states
end

local function removeConveyorItemFromTracking(model: Model)
	for _, conveyor in conveyorStatesRef do
		local items = conveyor.activeItems
		for i = #items, 1, -1 do
			if items[i] == model then
				table.remove(items, i)
				return
			end
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

local function getTemplatePool(): { Instance }
	local pool = {}
	local itemsFolder = getConveyorItemsFolder()
	if not itemsFolder then
		return pool
	end

	for _, child in itemsFolder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
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

local function getNextTemplate(conveyor: ConveyorState, pool: { Instance }): Instance?
	if #pool == 0 then
		return nil
	end

	if #conveyor.templateBag == 0 or conveyor.templateBagIndex > #conveyor.templateBag then
		conveyor.templateBag = buildShuffledTemplateBag(pool)
		conveyor.templateBagIndex = 1
	end

	local template = conveyor.templateBag[conveyor.templateBagIndex]
	conveyor.templateBagIndex += 1
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

local function floatConveyorModelTowardTurret(model: Model, turretModel: Model)
	if not turretModel.Parent then
		model:Destroy()
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

		if model.Parent then
			model:Destroy()
		end
	end)
end

local function flashModelRed(model: Model)
	if model:GetAttribute(FLASH_DEBOUNCE_ATTRIBUTE) then
		debugLog("Skipped flash (debounced)", model:GetFullName())
		return
	end
	debugLog("Flashing model", model:GetFullName())
	model:SetAttribute(FLASH_DEBOUNCE_ATTRIBUTE, true)

	local originalColors = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			originalColors[descendant] = descendant.Color
			descendant.Color = Color3.fromRGB(255, 0, 0)
		end
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "HitFlash"
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 64, 64)
	highlight.FillTransparency = 0.25
	highlight.OutlineTransparency = 0.1
	highlight.Enabled = true
	highlight.Parent = model

	task.spawn(function()
		task.wait(FLASH_ON_TIME)

		highlight:Destroy()
		for part, originalColor in originalColors do
			if part and part.Parent then
				part.Color = originalColor
			end
		end

		if model.Parent then
			model:SetAttribute(FLASH_DEBOUNCE_ATTRIBUTE, nil)
		end
	end)
end

local function applyRandomHitDamage(model: Model, turretModel: Model?, rewardPlayer: Player?)
	local current = model:GetAttribute(CONVEYOR_HEALTH_ATTRIBUTE)
	local maxHealth = model:GetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE)
	if typeof(current) ~= "number" or typeof(maxHealth) ~= "number" then
		assignRandomConveyorHealth(model)
		current = model:GetAttribute(CONVEYOR_HEALTH_ATTRIBUTE)
		maxHealth = model:GetAttribute(CONVEYOR_MAX_HEALTH_ATTRIBUTE)
	end
	if typeof(current) ~= "number" then
		return
	end

	local damage = math.random(CONVEYOR_HIT_DAMAGE_MIN, CONVEYOR_HIT_DAMAGE_MAX)
	local newHealth = math.max(0, current - damage)
	model:SetAttribute(CONVEYOR_HEALTH_ATTRIBUTE, newHealth)

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid and humanoid.MaxHealth > 0 then
		humanoid.Health = math.clamp(newHealth, 0, humanoid.MaxHealth)
	end

	if newHealth <= 0 then
		local payout = model:GetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE)
		if typeof(payout) == "number" and payout > 0 then
			local worldPos = model:GetPivot().Position
			spawnWorldCashPopBillboard(worldPos, payout)
			if rewardPlayer then
				Money.addCash(rewardPlayer, payout)
				local flyRemote = ReplicatedStorage:FindFirstChild(CASH_FLY_VFX_REMOTE_NAME)
				if flyRemote and flyRemote:IsA("RemoteEvent") then
					flyRemote:FireClient(rewardPlayer, worldPos, payout)
				end
			end
		end

		removeConveyorItemFromTracking(model)
		model:SetAttribute(CONVEYOR_ITEM_ATTRIBUTE, nil)

		if turretModel and turretModel.Parent then
			model.Parent = getOrCreateDeathVfxFolder()
			floatConveyorModelTowardTurret(model, turretModel)
		else
			model:Destroy()
		end
	end
end

local function onConveyorAntiAirHit(model: Model, attackerPlayer: Player?, projectilePart: BasePart?)
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

	applyRandomHitDamage(model, turretModel, rewardPlayer)
	if model.Parent then
		flashModelRed(model)
	end
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

local function toXZ(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function getConveyors(): { ConveyorState }
	local conveyors = {}
	local seenModel: { [Model]: boolean } = {}

	local function tryAddConveyor(model: Model)
		if seenModel[model] then
			return
		end

		if not string.find(model.Name, "^" .. CONVEYOR_NAME_PREFIX) then
			return
		end

		local startPart = model:FindFirstChild("Start")
		local endPart = model:FindFirstChild("End")
		if not startPart or not endPart then
			return
		end
		if not startPart:IsA("BasePart") or not endPart:IsA("BasePart") then
			return
		end

		local vector = toXZ(endPart.Position - startPart.Position)
		local length = vector.Magnitude
		if length <= 0 then
			return
		end

		seenModel[model] = true
		table.insert(conveyors, {
			model = model,
			startPart = startPart,
			endPart = endPart,
			dir = vector.Unit,
			length = length,
			beltY = startPart.Position.Y + Y_OFFSET,
			activeItems = {},
			nextSpawnTime = os.clock() + (math.random() * SPAWN_INTERVAL),
			templateBag = {},
			templateBagIndex = 1,
		})
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") then
			tryAddConveyor(descendant)
		end
	end

	return conveyors
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

local function getDistanceAlongConveyor(conveyor: ConveyorState, position: Vector3): number
	local startPlanar = Vector3.new(conveyor.startPart.Position.X, conveyor.beltY, conveyor.startPart.Position.Z)
	local planarPos = Vector3.new(position.X, conveyor.beltY, position.Z)
	return (planarPos - startPlanar):Dot(conveyor.dir)
end

local function spawnConveyorItem(conveyor: ConveyorState, templates: { Instance }, activeFolder: Folder): boolean
	if #conveyor.activeItems >= MAX_ACTIVE_ITEMS_PER_CONVEYOR then
		return false
	end

	if #conveyor.activeItems > 0 then
		local newest = conveyor.activeItems[#conveyor.activeItems]
		local distFromStart = (getModelPosition(newest) - conveyor.startPart.Position).Magnitude
		local newestScale = newest:GetAttribute(SCALE_ATTRIBUTE)
		local spacingScale = typeof(newestScale) == "number" and newestScale or 1
		if distFromStart < (ITEM_SPACING * spacingScale) then
			return false
		end
	end

	local template = getNextTemplate(conveyor, templates)
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
	model:ScaleTo(spawnScale)
	model:SetAttribute(SCALE_ATTRIBUTE, spawnScale)
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
		model:SetAttribute(CONVEYOR_ITEM_CASH_REWARD_ATTRIBUTE, GOLD_CASH_REWARD)
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
	local spawnPos = Vector3.new(conveyor.startPart.Position.X, conveyor.beltY, conveyor.startPart.Position.Z)
	setModelPosition(model, spawnPos)
	snapModelToBelt(model, conveyor.beltY)
	table.insert(conveyor.activeItems, model)
	return true
end

local function updateConveyor(conveyor: ConveyorState, dt: number)
	local i = 1
	while i <= #conveyor.activeItems do
		local item = conveyor.activeItems[i]
		if not item.Parent then
			table.remove(conveyor.activeItems, i)
			continue
		end

		local currentPosition = getModelPosition(item)
		local startPlanar = Vector3.new(conveyor.startPart.Position.X, conveyor.beltY, conveyor.startPart.Position.Z)
		local currentDistance = getDistanceAlongConveyor(conveyor, currentPosition)
		local nextDistance = currentDistance + (CONVEYOR_SPEED * dt)

		if nextDistance >= conveyor.length - END_REACHED_THRESHOLD then
			item:Destroy()
			table.remove(conveyor.activeItems, i)
			continue
		end

		local nextPosition = startPlanar + (conveyor.dir * nextDistance)
		nextPosition = Vector3.new(nextPosition.X, conveyor.beltY, nextPosition.Z)
		setModelPosition(item, nextPosition)
		snapModelToBelt(item, conveyor.beltY)

		i += 1
	end
end

local function runConveyorSystem()
	math.randomseed(DateTime.now().UnixTimestampMillis)

	local conveyors = getConveyors()
	if #conveyors == 0 then
		warn("ConveyorSystem: No conveyor models found. Expected model names starting with 'Conveyor' and direct Start/End BaseParts.")
		return
	end

	registerConveyorStatesForTracking(conveyors)

	local activeFolder = getOrCreateActiveFolder()
	local templates = getTemplatePool()
	if #templates == 0 then
		warn("ConveyorSystem: No templates in ServerStorage.ConveyorItems. Using fallback crates.")
	end

	local lastTick = os.clock()
	while true do
		local now = os.clock()
		local dt = now - lastTick
		lastTick = now

		for _, conveyor in conveyors do
			updateConveyor(conveyor, dt)

			-- Below target, never wait on an old "belt was full" spawn clock (avoids long dry spells).
			if #conveyor.activeItems < TARGET_ACTIVE_ITEMS_PER_CONVEYOR then
				conveyor.nextSpawnTime = math.min(conveyor.nextSpawnTime, now)
			end

			if #conveyor.activeItems < TARGET_ACTIVE_ITEMS_PER_CONVEYOR and now >= conveyor.nextSpawnTime then
				local didSpawn = spawnConveyorItem(conveyor, templates, activeFolder)
				if didSpawn then
					conveyor.nextSpawnTime = now + SPAWN_INTERVAL
				else
					-- Retry soon when spacing temporarily blocks spawn.
					conveyor.nextSpawnTime = now + 0.1
				end
			end
		end

		task.wait()
	end
end

local hitFlashRemote = getOrCreateHitFlashRemote()
local lastShotCostAtByUserId: { [number]: number } = {}

local function tryChargeShotCost(player: Player)
	if not isPlayerInAllowedTurret(player) then
		return
	end

	local now = os.clock()
	local last = lastShotCostAtByUserId[player.UserId]
	if last and (now - last) < SHOT_COST_DEBOUNCE_SECONDS then
		return
	end
	lastShotCostAtByUserId[player.UserId] = now
	Money.subtractCash(player, SHOT_COST_AMOUNT)
end

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
		tryChargeShotCost(player)
	end

	debugLog("Resolved conveyor model", hitModel:GetFullName())
	onConveyorAntiAirHit(hitModel, player, nil)
end)

local ConveyorAntiAirBridge = require(script.Parent:WaitForChild("ConveyorAntiAirBridge") :: ModuleScript)
ConveyorAntiAirBridge.setProjectileConveyorHitHandler(function(model: Model, projectile: BasePart, shooter: Player?)
	if shooter then
		tryChargeShotCost(shooter)
	end
	onConveyorAntiAirHit(model, shooter, projectile)
end)

task.spawn(runConveyorSystem)
