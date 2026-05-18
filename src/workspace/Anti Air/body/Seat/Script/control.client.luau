wait(0.20)
local HEARTBEAT_SHOT_INTERVAL = 0.2
local RELOAD_SOUND_CUTOFF = 0.08
local CROSSHAIR_DISTANCE = 5000
local FIRE_REMOTE_NAME = "AntiAirPlayerFire"
local SPLASH_REEL_TAP_REMOTE_NAME = "AntiAirSplashReelTap"
local SPLASH_REEL_METER_REMOTE_NAME = "AntiAirSplashReelMeterState"
local PLAYER_PROJECTILES_FOLDER_NAME = "AntiAirPlayerProjectiles"

local function resolveGunModel(): Model?
	local valueObject = script:FindFirstChild("Value")
	if valueObject and valueObject:IsA("ObjectValue") and valueObject.Value and valueObject.Value:IsA("Model") then
		return valueObject.Value
	end

	local seatScript = script.Parent
	if seatScript and seatScript:IsA("Script") then
		local seat = seatScript.Parent
		if seat and seat:IsA("Seat") then
			local model = seat:FindFirstAncestorOfClass("Model")
			if model then
				return model
			end
		end
	end

	return nil
end

local gun = resolveGunModel()
if not gun then
	warn("[AntiAirFlashClient] Could not resolve turret model from control script")
	return
end

local player = game.Players.LocalPlayer
local mouse = player:GetMouse()
mouse.TargetFilter = gun
local running = false
local holdingFire = false
local shootHeld = false
local SPAWN = gun.body:GetPrimaryPartCFrame()
local initialGunPart = gun:FindFirstChild("gun", true) and gun.gun:FindFirstChild("gunpart")
local aimpos = if initialGunPart and initialGunPart:IsA("BasePart")
	then initialGunPart.Position + (initialGunPart.CFrame.LookVector * 5000)
	else Vector3.new(0, 0, 0)
local runService = game:GetService("RunService")
local rs = runService.RenderStepped
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")
local originalMouseIcon = mouse.Icon
local replicatedStorage = game:GetService("ReplicatedStorage")
local userInputService = game:GetService("UserInputService")
local contextActionService = game:GetService("ContextActionService")
local tweenService = game:GetService("TweenService")
local USE_TOUCH_STYLE_CONTROLS_FOR_TESTING = false
local isTouchDevice = USE_TOUCH_STYLE_CONTROLS_FOR_TESTING or userInputService.TouchEnabled
local fireRemote = replicatedStorage:WaitForChild(FIRE_REMOTE_NAME, 30)
if not fireRemote or not fireRemote:IsA("RemoteEvent") then
	warn("[AntiAirFlashClient] Missing RemoteEvent", FIRE_REMOTE_NAME, "- turret client disabled")
	return
end

local splashTapInst = replicatedStorage:WaitForChild(SPLASH_REEL_TAP_REMOTE_NAME, 30)
local splashMeterInst = replicatedStorage:WaitForChild(SPLASH_REEL_METER_REMOTE_NAME, 30)
local splashTapRemote: RemoteEvent? = if splashTapInst:IsA("RemoteEvent") then splashTapInst else nil
local splashMeterRemote: RemoteEvent? = if splashMeterInst:IsA("RemoteEvent") then splashMeterInst else nil
if not splashTapRemote or not splashMeterRemote then
	warn("[AntiAirFlashClient] Missing splash reel RemoteEvents — reel meter UI disabled")
end

local MATCH_ROUND_REMOTES_NAME = "MatchRoundRemotes"
local MATCH_ROUND_STATE_NAME = "RoundState"
local matchRoundPhase = "Idle"
local matchRoundLeaderboard: { any } = {}
local matchRoundStateConn: RBXScriptConnection? = nil
local matchRoundFolder = replicatedStorage:FindFirstChild(MATCH_ROUND_REMOTES_NAME)
if not matchRoundFolder then
	matchRoundFolder = replicatedStorage:WaitForChild(MATCH_ROUND_REMOTES_NAME, 20)
end
if matchRoundFolder and matchRoundFolder:IsA("Folder") then
	local roundStateEv = matchRoundFolder:WaitForChild(MATCH_ROUND_STATE_NAME, 20)
	if roundStateEv and roundStateEv:IsA("RemoteEvent") then
		matchRoundStateConn = roundStateEv.OnClientEvent:Connect(function(payload: any)
			if typeof(payload) ~= "table" then
				return
			end
			if typeof(payload.phase) == "string" then
				matchRoundPhase = payload.phase
			end
			if typeof(payload.leaderboard) == "table" then
				matchRoundLeaderboard = payload.leaderboard
			end
		end)
	end
end

local function localPlayerIsMatchRoundLeaderboardParticipant(): boolean
	for _, row in matchRoundLeaderboard do
		if typeof(row) == "table" and row.userId == player.UserId then
			return true
		end
	end
	return false
end

local function canShootByMatchRoundState(): boolean
	if matchRoundStateConn == nil then
		return true
	end
	return matchRoundPhase == "ActiveRound" and localPlayerIsMatchRoundLeaderboardParticipant()
end

local Ricochet = require(replicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirRicochetProjectile") :: ModuleScript)
local HarpoonVisual = require(replicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirHarpoonProjectileVisual") :: ModuleScript)

local BULLET_SPEED = 280
local BULLET_LIFETIME_SEC = 7
local PREDICT_RECONCILE_TIMEOUT_SEC = 0.55
local HARPOON_RETRACT_DURATION_SEC = 0.38
local MUZZLE_OFFSET_STUDS = 5
-- Must match AntiAirPlayerFire.server.luau
local MAX_AIM_DIRECTION_Y = 0.42
local IS_WATER_SPLASH_ATTRIBUTE = "IsWaterSplash"
local SPLASH_HIT_COLLIDER_NAME = "SplashHitCollider"
local SPLASH_RAYCAST_MAX_DISTANCE = 2000
-- Forgiving screen-space hit test so top-down clicks feel like buttons.
local SPLASH_SCREEN_PICK_RADIUS_PX = 72

type PredictPending = {
	cancelRicochet: () -> (),
	part: BasePart,
}

local pendingPredictionBySeq: { [number]: PredictPending } = {}
local predictShotSeq = 0
local predictReconcileConn: RBXScriptConnection? = nil

local function clearAllPredictions()
	for _, pending in pairs(pendingPredictionBySeq) do
		pending.cancelRicochet()
		if pending.part.Parent then
			pending.part:Destroy()
		end
	end
	table.clear(pendingPredictionBySeq)
end

local function tryReconcileWithServerProjectile(inst: BasePart)
	local ownerId = inst:GetAttribute("AntiAirPredictOwner")
	local seq = inst:GetAttribute("AntiAirPredictSeq")
	if ownerId ~= player.UserId or typeof(seq) ~= "number" then
		return
	end
	local pending = pendingPredictionBySeq[seq :: number]
	if not pending then
		return
	end
	pendingPredictionBySeq[seq :: number] = nil
	pending.cancelRicochet()
	if pending.part.Parent then
		pending.part:Destroy()
	end
end

-- Never use Workspace.DescendantAdded for this: it runs for every part/model in the game (huge cost).
local projectileFolder = workspace:WaitForChild(PLAYER_PROJECTILES_FOLDER_NAME, 45)
if not projectileFolder or not projectileFolder:IsA("Folder") then
	warn("[AntiAirFlashClient] Missing folder", PLAYER_PROJECTILES_FOLDER_NAME, "- prediction reconcile disabled (server should create it).")
else
	predictReconcileConn = projectileFolder.ChildAdded:Connect(function(inst)
		if not inst:IsA("BasePart") or inst.Name ~= "AntiAirPlayerProjectile" then
			return
		end
		tryReconcileWithServerProjectile(inst)
	end)
end

local function playerHasBlockingHarpoonShot(): boolean
	for _ in pairs(pendingPredictionBySeq) do
		return true
	end
	if projectileFolder and projectileFolder:IsA("Folder") then
		for _, child in projectileFolder:GetChildren() do
			if child:IsA("BasePart") and child.Name == "AntiAirPlayerProjectile" then
				if child:GetAttribute("AntiAirPredictOwner") == player.UserId then
					return true
				end
			end
		end
	end
	return false
end

local DEBUG_FLASH = true

local function debugLog(...)
	if DEBUG_FLASH then
		warn("[AntiAirFlashClient]", ...)
	end
end

warn("[AntiAirFlashClient] control script started")

local function createCrosshair()
	local crosshairGui = Instance.new("ScreenGui")
	crosshairGui.Name = "AntiAirCrosshair"
	crosshairGui.ResetOnSpawn = false
	crosshairGui.IgnoreGuiInset = true
	crosshairGui.Parent = playerGui

	local center = Instance.new("Frame")
	center.Name = "Center"
	center.Size = UDim2.new(0, 4, 0, 4)
	center.Position = UDim2.new(0.5, -2, 0.5, -2)
	center.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	center.BorderSizePixel = 0
	center.Parent = crosshairGui

	local horizontal = Instance.new("Frame")
	horizontal.Name = "Horizontal"
	horizontal.Size = UDim2.new(0, 24, 0, 2)
	horizontal.Position = UDim2.new(0.5, -12, 0.5, -1)
	horizontal.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	horizontal.BorderSizePixel = 0
	horizontal.Parent = crosshairGui

	local vertical = Instance.new("Frame")
	vertical.Name = "Vertical"
	vertical.Size = UDim2.new(0, 2, 0, 24)
	vertical.Position = UDim2.new(0.5, -1, 0.5, -12)
	vertical.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	vertical.BorderSizePixel = 0
	vertical.Parent = crosshairGui

	return crosshairGui, center, horizontal, vertical
end

local crosshairGui, crosshairCenter, crosshairHorizontal, crosshairVertical = createCrosshair()
local mobileFireGui: ScreenGui? = nil
local mobileShootButton: TextButton? = nil
local splashReelGui: ScreenGui? = nil
local splashReelFill: Frame? = nil
local splashMeterVisible = false
local splashMeterConn: RBXScriptConnection? = nil
local splashDesktopInputConn: RBXScriptConnection? = nil

local function destroySplashReelGui()
	splashMeterVisible = false
	if splashReelGui then
		splashReelGui:Destroy()
		splashReelGui = nil
	end
	splashReelFill = nil
end

local function setSplashReelMeterFill(m: number)
	if splashReelFill and splashReelFill.Parent then
		splashReelFill.Size = UDim2.new(math.clamp(m, 0, 1), 0, 1, 0)
	end
end

local function requestSplashReelTap()
	if splashTapRemote then
		splashTapRemote:FireServer()
	end
end

local function showSplashReelGui(initialMeter: number)
	destroySplashReelGui()
	splashMeterVisible = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "AntiAirSplashReelMeter"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.Parent = playerGui

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -120)
	holder.Size = UDim2.fromOffset(280, 72)
	holder.BackgroundTransparency = 1
	holder.Parent = gui

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.Size = UDim2.new(1, 0, 0, 18)
	barBack.Position = UDim2.new(0, 0, 0, 0)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	barBack.BorderSizePixel = 0
	barBack.Parent = holder
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barBack

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(math.clamp(initialMeter, 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
	fill.BorderSizePixel = 0
	fill.Parent = barBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local tapBtn = Instance.new("TextButton")
	tapBtn.Name = "TapReel"
	tapBtn.Size = UDim2.new(1, 0, 0, 42)
	tapBtn.Position = UDim2.new(0, 0, 0, 28)
	tapBtn.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
	tapBtn.Text = "TAP TO REEL"
	tapBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	tapBtn.Font = Enum.Font.GothamBold
	tapBtn.TextSize = 18
	tapBtn.BorderSizePixel = 0
	tapBtn.AutoButtonColor = true
	tapBtn.Parent = holder
	local tapCorner = Instance.new("UICorner")
	tapCorner.CornerRadius = UDim.new(0, 8)
	tapCorner.Parent = tapBtn

	tapBtn.MouseButton1Click:Connect(function()
		requestSplashReelTap()
	end)

	splashReelGui = gui
	splashReelFill = fill
end

if splashMeterRemote then
	splashMeterConn = splashMeterRemote.OnClientEvent:Connect(function(visible: unknown, meter: unknown)
		if visible ~= true then
			destroySplashReelGui()
			return
		end
		local m = if typeof(meter) == "number" then meter else 0
		if splashReelGui and splashReelFill then
			setSplashReelMeterFill(m)
		else
			showSplashReelGui(m)
		end
		splashMeterVisible = true
	end)
end

splashDesktopInputConn = userInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if not splashMeterVisible then
		return
	end
	if
		input.KeyCode == Enum.KeyCode.F
		or input.KeyCode == Enum.KeyCode.R
		or input.KeyCode == Enum.KeyCode.Space
	then
		requestSplashReelTap()
	end
end)

local DISABLE_JUMP_ACTION = "AntiAirDisableJump"
local DEBUG_FLASH = true
local humanoid: Humanoid? = nil
local previousJumpPower = 50
local previousJumpHeight = 7.2
local hadJumpingStateEnabled = true
local playerControls = nil
local didDisableDefaultTouchControls = false
local activeAimTouch: InputObject? = nil
local lastAimTouchScreen: Vector2? = nil
-- World XZ unit direction; updated by horizontal drag in left aim zone only (camera-independent).
local touchAimDirXZ = Vector3.new(0, 0, -1)
local MOBILE_YAW_SENSITIVITY = 0.0045
local ARENA_SKY_VIEW_ATTR = "ArenaSkyView"
local skyViewAttrConn: RBXScriptConnection? = nil
local arenaPointerInputBeganConn: RBXScriptConnection? = nil
local touchStartConn: RBXScriptConnection? = nil
local touchMoveConn: RBXScriptConnection? = nil
local touchEndConn: RBXScriptConnection? = nil
-- Sky/generic touch fire skipped when TouchStarted already fired at a splash button.
local splashButtonTouchIds: { [InputObject]: boolean } = {}
mouse.Icon = ""

local splashRaycastParams = RaycastParams.new()
splashRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function rebuildSplashRaycastExclude()
	local exclude: { Instance } = { gun }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	if projectileFolder and projectileFolder:IsA("Folder") then
		table.insert(exclude, projectileFolder)
	end
	splashRaycastParams.FilterDescendantsInstances = exclude
end

-- GetMouseLocation / touch Position use screen pixels; ScreenPointToRay matches that space.
local function screenPointToUnitRay(screenX: number, screenY: number): Ray?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	return cam:ScreenPointToRay(screenX, screenY)
end

local function buildSplashPickRaycastParams(): RaycastParams
	local splashFolder = workspace:FindFirstChild("WaterSplashes")
	if splashFolder and splashFolder:IsA("Folder") then
		local includeOnly = RaycastParams.new()
		includeOnly.FilterType = Enum.RaycastFilterType.Include
		includeOnly.FilterDescendantsInstances = { splashFolder }
		return includeOnly
	end
	rebuildSplashRaycastExclude()
	return splashRaycastParams
end

local function findWaterSplashModel(instance: Instance): Model?
	local current: Instance? = instance
	while current do
		if current:IsA("Model") and current:GetAttribute(IS_WATER_SPLASH_ATTRIBUTE) == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getSplashAimWorldPoint(splashModel: Model): Vector3
	local hit = splashModel:FindFirstChild(SPLASH_HIT_COLLIDER_NAME, true)
	if hit and hit:IsA("BasePart") then
		return hit.Position
	end
	return splashModel:GetPivot().Position
end

-- Desktop: mouse.Target; top-down: nearest splash on screen; then physics raycast.
local function pickWaterSplashAtScreen(screenX: number, screenY: number): (Model?, Vector3?)
	if userInputService.MouseEnabled then
		local target = mouse.Target
		if target then
			local splashModel = findWaterSplashModel(target)
			if splashModel then
				return splashModel, getSplashAimWorldPoint(splashModel)
			end
		end
	end

	local cam = workspace.CurrentCamera
	local splashFolder = workspace:FindFirstChild("WaterSplashes")
	if cam and splashFolder and splashFolder:IsA("Folder") then
		local bestModel: Model? = nil
		local bestDist2 = SPLASH_SCREEN_PICK_RADIUS_PX * SPLASH_SCREEN_PICK_RADIUS_PX
		for _, child in splashFolder:GetChildren() do
			if child:IsA("Model") and child:GetAttribute(IS_WATER_SPLASH_ATTRIBUTE) == true then
				local worldPoint = getSplashAimWorldPoint(child)
				local screenPoint, onScreen = cam:WorldToScreenPoint(worldPoint)
				if onScreen and screenPoint.Z > 0 then
					local dx = screenPoint.X - screenX
					local dy = screenPoint.Y - screenY
					local dist2 = dx * dx + dy * dy
					if dist2 < bestDist2 then
						bestDist2 = dist2
						bestModel = child
					end
				end
			end
		end
		if bestModel then
			return bestModel, getSplashAimWorldPoint(bestModel)
		end
	end

	local ray = screenPointToUnitRay(screenX, screenY)
	if not ray then
		return nil, nil
	end
	local dir = ray.Direction * SPLASH_RAYCAST_MAX_DISTANCE
	local includeParams = buildSplashPickRaycastParams()
	local result = workspace:Raycast(ray.Origin, dir, includeParams)
	if not result then
		rebuildSplashRaycastExclude()
		result = workspace:Raycast(ray.Origin, dir, splashRaycastParams)
	end
	if result then
		local splashModel = findWaterSplashModel(result.Instance)
		if splashModel then
			return splashModel, getSplashAimWorldPoint(splashModel)
		end
	end
	return nil, nil
end

local function raycastWaterSplashAtScreen(screenX: number, screenY: number): Vector3?
	local ray = screenPointToUnitRay(screenX, screenY)
	if not ray then
		return nil
	end
	local dir = ray.Direction * SPLASH_RAYCAST_MAX_DISTANCE

	local includeParams = buildSplashPickRaycastParams()
	local result = workspace:Raycast(ray.Origin, dir, includeParams)
	if result and findWaterSplashModel(result.Instance) then
		return result.Position
	end

	rebuildSplashRaycastExclude()
	result = workspace:Raycast(ray.Origin, dir, splashRaycastParams)
	if result and findWaterSplashModel(result.Instance) then
		return result.Position
	end
	return nil
end

local function getHorizontalPlanePointFromScreen(screenX: number, screenY: number, planeY: number): Vector3?
	local ray = screenPointToUnitRay(screenX, screenY)
	if not ray then
		return nil
	end
	local dy = ray.Direction.Y
	if math.abs(dy) < 1e-5 then
		return nil
	end
	local t = (planeY - ray.Origin.Y) / dy
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local function getArenaFloorY(): number
	local bp = workspace:FindFirstChild("Baseplate")
	if bp and bp:IsA("BasePart") then
		return bp.Position.Y + bp.Size.Y * 0.5
	end
	return gun.body:GetPrimaryPartCFrame().Position.Y
end

local function getSkyAimPointFromScreen(screenX: number, screenY: number): Vector3?
	local _, splashPoint = pickWaterSplashAtScreen(screenX, screenY)
	if splashPoint then
		return splashPoint
	end
	return getHorizontalPlanePointFromScreen(screenX, screenY, getArenaFloorY())
end

local function computeYawAimLookToward(worldPoint: Vector3): Vector3
	local gunPart = gun.gun.gunpart
	local offset = Vector3.new(worldPoint.X - gunPart.Position.X, 0, worldPoint.Z - gunPart.Position.Z)
	if offset.Magnitude < 1e-4 then
		local flat = Vector3.new(gunPart.CFrame.LookVector.X, 0, gunPart.CFrame.LookVector.Z)
		if flat.Magnitude < 1e-4 then
			return Vector3.new(0, 0, -1)
		end
		return flat.Unit
	end
	return offset.Unit
end

local function finalizeAimLook(aimLook: Vector3, preservePitch: boolean): Vector3
	if aimLook.Magnitude < 1e-5 then
		return Vector3.new(0, 0, -1)
	end
	if not preservePitch then
		local flatAim = Vector3.new(aimLook.X, 0, aimLook.Z)
		if flatAim.Magnitude > 1e-5 then
			return flatAim.Unit
		end
		return aimLook.Unit
	end
	local unit = aimLook.Unit
	if math.abs(unit.Y) <= MAX_AIM_DIRECTION_Y then
		return unit
	end
	local signY = if unit.Y > 0 then 1 else -1
	local xz = Vector3.new(unit.X, 0, unit.Z)
	local xzMag = xz.Magnitude
	if xzMag < 1e-5 then
		return Vector3.new(0, signY * MAX_AIM_DIRECTION_Y, 0).Unit
	end
	local xzScale = math.sqrt(math.max(0, 1 - MAX_AIM_DIRECTION_Y * MAX_AIM_DIRECTION_Y))
	xz = xz.Unit * xzScale
	return Vector3.new(xz.X, signY * MAX_AIM_DIRECTION_Y, xz.Z).Unit
end

local function computeAimLookTowardSplash(worldPoint: Vector3): Vector3
	local gunPart = gun.gun.gunpart
	local offset = worldPoint - gunPart.Position
	if offset.Magnitude < 1e-4 then
		return computeYawAimLookToward(worldPoint)
	end
	return finalizeAimLook(offset, true)
end

local function isScreenPointOverBlockingGui(screenX: number, screenY: number): boolean
	local guiObjects = playerGui:GetGuiObjectsAtPosition(screenX, screenY)
	for _, obj in guiObjects do
		if obj:IsA("GuiObject") and obj.Visible then
			local sg = obj:FindFirstAncestorOfClass("ScreenGui")
			if
				sg
				and (
					sg.Name == "AntiAirMobileControls"
					or sg.Name == "AntiAirSplashReelMeter"
					or sg.Name == "ArenaSkyCamGui"
				)
			then
				return true
			end
		end
	end
	return false
end

-- Yaw only: aim stays in the horizontal plane through the body pivot (no pitch).
local function flattenAimToYaw(aimWorld: Vector3, pivotWorld: Vector3): Vector3
	local offset = Vector3.new(aimWorld.X - pivotWorld.X, 0, aimWorld.Z - pivotWorld.Z)
	local dist = offset.Magnitude
	if dist < 1e-4 then
		local look = gun.gun:GetPrimaryPartCFrame().LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 1e-4 then
			flatLook = Vector3.new(0, 0, -1)
		else
			flatLook = flatLook.Unit
		end
		return pivotWorld + flatLook * 100
	end
	return pivotWorld + offset.Unit * math.max(dist, 5)
end

local function applyTurretAimTowardWorld(worldPoint: Vector3)
	local pivotWorld = gun.body:GetPrimaryPartCFrame().Position
	local c = flattenAimToYaw(worldPoint, pivotWorld)
	aimpos = c
	local offset = Vector3.new(c.X - pivotWorld.X, 0, c.Z - pivotWorld.Z)
	if offset.Magnitude > 1e-5 then
		touchAimDirXZ = offset.Unit
	end
	if (c - gun.base.Position).Magnitude <= 3 then
		return
	end
	local x = (gun.gun:GetPrimaryPartCFrame() * CFrame.new(0, 0, -100000)).X
	local y = (SPAWN * CFrame.new(0, 0, -100000)).Y
	local z = (gun.gun:GetPrimaryPartCFrame() * CFrame.new(0, 0, -100000)).Z
	local A = Vector3.new(x, y, z)
	gun.gun:SetPrimaryPartCFrame(CFrame.new(gun.body:GetPrimaryPartCFrame().Position, c))
	gun.body:SetPrimaryPartCFrame(CFrame.new(SPAWN.Position, A))
end

local function createMobileControls()
	local controlsGui = Instance.new("ScreenGui")
	controlsGui.Name = "AntiAirMobileControls"
	controlsGui.ResetOnSpawn = false
	controlsGui.IgnoreGuiInset = true
	controlsGui.DisplayOrder = 50
	controlsGui.Parent = playerGui

	local shootGui = controlsGui
	shootGui.ResetOnSpawn = false
	shootGui.IgnoreGuiInset = true

	local shootButton = Instance.new("TextButton")
	shootButton.Name = "Shoot"
	shootButton.AnchorPoint = Vector2.new(1, 1)
	shootButton.Size = UDim2.fromOffset(120, 36)
	shootButton.Position = UDim2.new(1, -16, 1, -60)
	shootButton.BackgroundColor3 = Color3.fromRGB(212, 50, 50)
	shootButton.BackgroundTransparency = 0.2
	shootButton.BorderSizePixel = 0
	shootButton.Text = "SHOOT"
	shootButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	shootButton.TextSize = 16
	shootButton.Font = Enum.Font.GothamBold
	shootButton.AutoButtonColor = true
	shootButton.Parent = shootGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = shootButton

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = shootButton

	return shootGui, shootButton
end

local function disableJumpInput()
	contextActionService:BindActionAtPriority(DISABLE_JUMP_ACTION, function()
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.PlayerActions.CharacterJump)
end

local function enableJumpInput()
	contextActionService:UnbindAction(DISABLE_JUMP_ACTION)
end

local function setCrosshairScreenPosition(viewportX, viewportY)
	crosshairCenter.Position = UDim2.new(0, viewportX - 2, 0, viewportY - 2)
	crosshairHorizontal.Position = UDim2.new(0, viewportX - 12, 0, viewportY - 1)
	crosshairVertical.Position = UDim2.new(0, viewportX - 1, 0, viewportY - 12)
end

local function updateCrosshairFromBarrel()
	if not crosshairGui or not camera then
		return
	end

	local gunPart = gun.gun.gunpart
	if not gunPart then
		return
	end

	local targetWorldPoint = gunPart.Position + (gunPart.CFrame.LookVector * CROSSHAIR_DISTANCE)
	local projectedPoint, onScreen = camera:WorldToViewportPoint(targetWorldPoint)
	local visible = onScreen and projectedPoint.Z > 0

	crosshairCenter.Visible = visible
	crosshairHorizontal.Visible = visible
	crosshairVertical.Visible = visible

	if visible then
		setCrosshairScreenPosition(projectedPoint.X, projectedPoint.Y)
	end
end

local function fireOnce(
	forceShoot: boolean?,
	aimLookOverride: Vector3?,
	chosenSplash: Model?,
	preservePitch: boolean?
)
	if not forceShoot and not shootHeld then
		return
	end
	if not canShootByMatchRoundState() then
		return
	end
	if playerHasBlockingHarpoonShot() then
		return
	end

	-- Aim is applied locally only; server must use our barrel pose (spawn + look) for the replicated projectile.
	local gunPart = gun.gun.gunpart
	local aimLook = aimLookOverride
	if not aimLook or aimLook.Magnitude < 1e-5 then
		aimLook = gunPart.CFrame.LookVector
	end
	aimLook = finalizeAimLook(aimLook, preservePitch == true)
	local spawnPosition = gunPart.Position + (aimLook * MUZZLE_OFFSET_STUDS)

	-- Local prediction: instant tracer for the shooter only; removed when the server projectile replicates in.
	predictShotSeq += 1
	local shotSeq = predictShotSeq
	local predictPart = Instance.new("Part")
	predictPart.Name = "AntiAirPredictTracer"
	predictPart.Size = Vector3.new(0.4, 0.4, 22)
	predictPart.CFrame = CFrame.new(spawnPosition, spawnPosition + aimLook * CROSSHAIR_DISTANCE)
	predictPart.BrickColor = BrickColor.new("Really red")
	predictPart.Material = Enum.Material.Neon
	predictPart.CanCollide = false
	predictPart.CanTouch = false
	predictPart.Anchored = true
	predictPart.Parent = workspace

	local rope = HarpoonVisual.createRopeController(predictPart, gunPart, {
		muzzleStuds = MUZZLE_OFFSET_STUDS,
	})

	local rayExclude: { Instance } = { gun, predictPart }
	if player.Character then
		table.insert(rayExclude, player.Character)
	end
	local cancelRicochet = Ricochet.start(predictPart, aimLook, workspace, runService, {
		speed = BULLET_SPEED,
		maxLifetimeSeconds = BULLET_LIFETIME_SEC,
		raycastExclude = rayExclude,
		chosenWaterSplash = chosenSplash,
		onConveyorHit = function(_hitPart: BasePart)
			return nil
		end,
		retractToPart = gunPart,
		retractDuration = HARPOON_RETRACT_DURATION_SEC,
		retractMuzzleStuds = MUZZLE_OFFSET_STUDS,
		retractOnlyOnHit = true,
		onBounce = function(worldCorner: Vector3)
			rope.addCorner(worldCorner)
		end,
	})
	pendingPredictionBySeq[shotSeq] = {
		cancelRicochet = cancelRicochet,
		part = predictPart,
	}
	task.delay(PREDICT_RECONCILE_TIMEOUT_SEC, function()
		local pending = pendingPredictionBySeq[shotSeq]
		if not pending or pending.part ~= predictPart then
			return
		end
		pendingPredictionBySeq[shotSeq] = nil
		pending.cancelRicochet()
		if predictPart.Parent then
			predictPart:Destroy()
		end
	end)

	if fireRemote and fireRemote:IsA("RemoteEvent") then
		fireRemote:FireServer(spawnPosition, aimLook, shotSeq, chosenSplash)
	end
	debugLog("Shot requested (server-spawned projectile + local predict)")
	spawn(function()
		gun.gun.barrel.Mesh.Offset = Vector3.new(0, -4, 0)
		gun.gun.barrelb.Mesh.Offset = Vector3.new(0, -1, 0)
		gun.gun.endp.Mesh.Offset = Vector3.new(0, -1, 0)

		for i = 1, 20 do
			gun.gun.barrel.Mesh.Offset = Vector3.new(0, (-4 + (i / 5)), 0)
			gun.gun.barrelb.Mesh.Offset = Vector3.new(0, (-1 + (i / 20)), 0)
			gun.gun.endp.Mesh.Offset = Vector3.new(0, -1 + (i / 20), 0)
			rs:Wait()
		end
	end)

	gun.gun.effect.reload:Play()
	task.delay(RELOAD_SOUND_CUTOFF, function()
		if gun.gun.effect.reload.IsPlaying then
			gun.gun.effect.reload:Stop()
		end
	end)
end

local PRESS_RING_START_DIAMETER = 5
local PRESS_RING_END_DIAMETER = 16
local PRESS_RING_DURATION = 0.38
local SPLASH_PRESS_COLOR = Color3.fromRGB(130, 235, 255)
local GROUND_PRESS_COLOR = Color3.fromRGB(200, 210, 225)

local function playScreenPressRipple(screenX: number, screenY: number, isSplash: boolean)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SplashPressRipple"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 85
	gui.Parent = playerGui

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(28, 28)
	ring.Position = UDim2.fromOffset(screenX, screenY)
	ring.BackgroundTransparency = 1
	ring.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = if isSplash then SPLASH_PRESS_COLOR else GROUND_PRESS_COLOR
	stroke.Transparency = 0.1
	stroke.Parent = ring

	local expand = tweenService:Create(
		ring,
		TweenInfo.new(PRESS_RING_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(76, 76) }
	)
	local fade = tweenService:Create(
		stroke,
		TweenInfo.new(PRESS_RING_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	)
	expand:Play()
	fade:Play()
	task.delay(PRESS_RING_DURATION + 0.05, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

local function playWorldPressRing(worldPoint: Vector3, isSplash: boolean)
	local ring = Instance.new("Part")
	ring.Name = "SplashPressRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = if isSplash then SPLASH_PRESS_COLOR else GROUND_PRESS_COLOR
	ring.Transparency = 0.35
	local y = getArenaFloorY() + 0.12
	ring.Size = Vector3.new(PRESS_RING_START_DIAMETER, 0.18, PRESS_RING_START_DIAMETER)
	ring.CFrame = CFrame.new(worldPoint.X, y, worldPoint.Z)
	ring.Parent = workspace

	local expand = tweenService:Create(
		ring,
		TweenInfo.new(PRESS_RING_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(PRESS_RING_END_DIAMETER, 0.14, PRESS_RING_END_DIAMETER),
			Transparency = 1,
		}
	)
	expand:Play()
	expand.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

local function playPressFeedback(
	screenX: number?,
	screenY: number?,
	worldPoint: Vector3,
	isSplash: boolean
)
	if typeof(screenX) == "number" and typeof(screenY) == "number" then
		playScreenPressRipple(screenX, screenY, isSplash)
	end
	playWorldPressRing(worldPoint, isSplash)
end

local function fireAtWorldPoint(
	worldPoint: Vector3,
	aimLookOverride: Vector3?,
	screenX: number?,
	screenY: number?,
	isSplash: boolean?,
	chosenSplash: Model?
)
	if typeof(screenX) == "number" and typeof(screenY) == "number" then
		playPressFeedback(screenX, screenY, worldPoint, isSplash == true)
	else
		playPressFeedback(nil, nil, worldPoint, isSplash == true)
	end
	applyTurretAimTowardWorld(worldPoint)
	local aimLook = aimLookOverride
	if not aimLook then
		if chosenSplash then
			aimLook = computeAimLookTowardSplash(worldPoint)
		else
			aimLook = computeYawAimLookToward(worldPoint)
		end
	end
	local prevShootHeld = shootHeld
	shootHeld = true
	fireOnce(true, aimLook, chosenSplash, chosenSplash ~= nil)
	shootHeld = prevShootHeld
end

-- Splash as button: tap/click selects splash, turret + harpoon lock to its center.
local function tryPressSplashButton(screenX: number, screenY: number): boolean
	if splashMeterVisible then
		return false
	end
	if isScreenPointOverBlockingGui(screenX, screenY) then
		return false
	end
	local splashModel, splashPoint = pickWaterSplashAtScreen(screenX, screenY)
	if not splashModel or not splashPoint then
		return false
	end
	if not canShootByMatchRoundState() then
		return false
	end
	if playerHasBlockingHarpoonShot() then
		return false
	end
	fireAtWorldPoint(
		splashPoint,
		computeAimLookTowardSplash(splashPoint),
		screenX,
		screenY,
		true,
		splashModel
	)
	return true
end

-- Sky / top-down: splash button first, else ground tap.
local function tryArenaSkyFireFromScreen(screenX: number, screenY: number): boolean
	if splashMeterVisible then
		return false
	end
	if isScreenPointOverBlockingGui(screenX, screenY) then
		return false
	end
	if not canShootByMatchRoundState() then
		return false
	end
	if playerHasBlockingHarpoonShot() then
		return false
	end
	local splashModel, splashPoint = pickWaterSplashAtScreen(screenX, screenY)
	local worldPoint = splashPoint
	if not worldPoint then
		worldPoint = getHorizontalPlanePointFromScreen(screenX, screenY, getArenaFloorY())
	end
	if not worldPoint then
		return false
	end
	local isSplash = splashModel ~= nil
	local aimLook = if splashModel
		then computeAimLookTowardSplash(worldPoint)
		else computeYawAimLookToward(worldPoint)
	fireAtWorldPoint(worldPoint, aimLook, screenX, screenY, isSplash, splashModel)
	return true
end

local function startFiring()
	if running then
		return
	end

	running = true
	task.spawn(function()
		while holdingFire do
			fireOnce()
			task.wait(HEARTBEAT_SHOT_INTERVAL)
		end
		running = false
	end)
end

local function stopFiring()
	holdingFire = false
end

local function cleanup()
	enableJumpInput()
	if predictReconcileConn then
		predictReconcileConn:Disconnect()
		predictReconcileConn = nil
	end
	if matchRoundStateConn then
		matchRoundStateConn:Disconnect()
		matchRoundStateConn = nil
	end
	clearAllPredictions()
	if skyViewAttrConn then
		skyViewAttrConn:Disconnect()
		skyViewAttrConn = nil
	end
	if arenaPointerInputBeganConn then
		arenaPointerInputBeganConn:Disconnect()
		arenaPointerInputBeganConn = nil
	end
	if didDisableDefaultTouchControls and playerControls then
		playerControls:Enable()
		didDisableDefaultTouchControls = false
	end

	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, hadJumpingStateEnabled)
		humanoid.JumpPower = previousJumpPower
		humanoid.JumpHeight = previousJumpHeight
	end

	gun.gun.barrel.Mesh.Offset = Vector3.new(0, 0, 0)
	gun.gun.barrelb.Mesh.Offset = Vector3.new(0, 0, 0)
	gun.gun.endp.Mesh.Offset = Vector3.new(0, 0, 0)
	mouse.TargetFilter = nil
	mouse.Icon = originalMouseIcon
	if crosshairGui then
		crosshairGui:Destroy()
		crosshairGui = nil
	end
	if mobileFireGui then
		mobileFireGui:Destroy()
		mobileFireGui = nil
		mobileShootButton = nil
	end
	if splashMeterConn then
		splashMeterConn:Disconnect()
		splashMeterConn = nil
	end
	if splashDesktopInputConn then
		splashDesktopInputConn:Disconnect()
		splashDesktopInputConn = nil
	end
	destroySplashReelGui()
	if touchStartConn then
		touchStartConn:Disconnect()
		touchStartConn = nil
	end
	if touchMoveConn then
		touchMoveConn:Disconnect()
		touchMoveConn = nil
	end
	if touchEndConn then
		touchEndConn:Disconnect()
		touchEndConn = nil
	end
	activeAimTouch = nil
	lastAimTouchScreen = nil
	script:Destroy()
end

local person = player.Character or player.CharacterAdded:Wait()
humanoid = person:WaitForChild("Humanoid")
previousJumpPower = humanoid.JumpPower
previousJumpHeight = humanoid.JumpHeight
hadJumpingStateEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)

humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
humanoid.JumpPower = 0
humanoid.JumpHeight = 0
disableJumpInput()

humanoid.Jumping:Connect(function(active)
	if active then
		humanoid.Jump = false
	end
end)

local function isArenaSkyViewActive(): boolean
	return player:GetAttribute(ARENA_SKY_VIEW_ATTR) == true
end

local function setCrosshairVisible(visible: boolean)
	if crosshairGui then
		crosshairGui.Enabled = visible
	end
end

local function unbindArenaSplashPointerInput()
	if arenaPointerInputBeganConn then
		arenaPointerInputBeganConn:Disconnect()
		arenaPointerInputBeganConn = nil
	end
end

-- Sky / top-down: tap or click fires (splash preferred, else ground plane under pointer).
local function bindArenaSplashPointerInput()
	unbindArenaSplashPointerInput()
	arenaPointerInputBeganConn = userInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		if not isArenaSkyViewActive() then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.Position
			tryArenaSkyFireFromScreen(pos.X, pos.Y)
		end
	end)
end

local function applySkyViewInputMode()
	if isArenaSkyViewActive() then
		setCrosshairVisible(false)
		activeAimTouch = nil
		lastAimTouchScreen = nil
		if mobileFireGui then
			mobileFireGui.Enabled = false
		end
		bindArenaSplashPointerInput()
	else
		setCrosshairVisible(true)
		unbindArenaSplashPointerInput()
		if mobileFireGui then
			mobileFireGui.Enabled = true
		end
	end
end

if isTouchDevice then
	local gunPartInit = gun.gun:FindFirstChild("gunpart")
	if gunPartInit and gunPartInit:IsA("BasePart") then
		local l = gunPartInit.CFrame.LookVector
		local f = Vector3.new(l.X, 0, l.Z)
		if f.Magnitude > 1e-4 then
			touchAimDirXZ = f.Unit
		end
	end

	mobileFireGui, mobileShootButton = createMobileControls()
	if mobileShootButton then
		mobileShootButton.InputBegan:Connect(function(input)
			if isArenaSkyViewActive() then
				return
			end
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				shootHeld = true
				holdingFire = true
				startFiring()
			end
		end)
		mobileShootButton.InputEnded:Connect(function(input)
			if isArenaSkyViewActive() then
				return
			end
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				shootHeld = false
				stopFiring()
			end
		end)
	end

	local function applyMobileMovementForSkyView()
		if not playerControls then
			return
		end
		if player:GetAttribute(ARENA_SKY_VIEW_ATTR) == true then
			playerControls:Disable()
			didDisableDefaultTouchControls = true
		else
			playerControls:Enable()
			didDisableDefaultTouchControls = false
		end
	end

	local function onSkyViewAttrChanged()
		applyMobileMovementForSkyView()
		applySkyViewInputMode()
	end

	local playerScripts = player:FindFirstChild("PlayerScripts")
	if playerScripts then
		local playerModule = playerScripts:FindFirstChild("PlayerModule")
		if playerModule then
			local ok, controlsOrErr = pcall(function()
				local module = require(playerModule)
				return module:GetControls()
			end)
			if ok and controlsOrErr then
				playerControls = controlsOrErr
			else
				warn("[AntiAirFlashClient] Unable to get PlayerModule controls", controlsOrErr)
			end
		end
	end

	skyViewAttrConn = player:GetAttributeChangedSignal(ARENA_SKY_VIEW_ATTR):Connect(onSkyViewAttrChanged)
	onSkyViewAttrChanged()

	touchStartConn = userInputService.TouchStarted:Connect(function(input: InputObject, gameProcessed: boolean)
		if isArenaSkyViewActive() then
			return
		end
		if gameProcessed or activeAimTouch then
			return
		end
		if tryPressSplashButton(input.Position.X, input.Position.Y) then
			splashButtonTouchIds[input] = true
			return
		end
		local viewport = camera and camera.ViewportSize or Vector2.new(0, 0)
		if viewport.X < 1 then
			return
		end
		if input.Position.X <= (viewport.X * 0.5) then
			activeAimTouch = input
			lastAimTouchScreen = input.Position
		end
	end)

	touchMoveConn = userInputService.TouchMoved:Connect(function(input: InputObject, _gameProcessed: boolean)
		if isArenaSkyViewActive() then
			return
		end

		if input ~= activeAimTouch or not lastAimTouchScreen then
			return
		end
		local now = input.Position
		local delta = now - lastAimTouchScreen
		lastAimTouchScreen = now

		local yaw = -delta.X * MOBILE_YAW_SENSITIVITY
		local lookFlat = Vector3.new(touchAimDirXZ.X, 0, touchAimDirXZ.Z)
		if lookFlat.Magnitude < 1e-5 then
			lookFlat = Vector3.new(0, 0, -1)
		else
			lookFlat = lookFlat.Unit
		end
		local baseCf = CFrame.lookAt(Vector3.zero, lookFlat)
		local rotated = CFrame.fromAxisAngle(Vector3.yAxis, yaw) * baseCf
		local newLook = rotated.LookVector
		newLook = Vector3.new(newLook.X, 0, newLook.Z)
		if newLook.Magnitude > 1e-5 then
			touchAimDirXZ = newLook.Unit
		end
	end)

	touchEndConn = userInputService.TouchEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		splashButtonTouchIds[input] = nil
		if input == activeAimTouch then
			activeAimTouch = nil
			lastAimTouchScreen = nil
		end
	end)
else
	mouse.Button1Down:Connect(function()
		local mouseLoc = userInputService:GetMouseLocation()
		if isArenaSkyViewActive() then
			tryArenaSkyFireFromScreen(mouseLoc.X, mouseLoc.Y)
			return
		end
		if tryPressSplashButton(mouseLoc.X, mouseLoc.Y) then
			return
		end
		shootHeld = true
		holdingFire = true
		startFiring()
	end)
	mouse.Button1Up:Connect(function()
		if isArenaSkyViewActive() then
			return
		end
		shootHeld = false
		stopFiring()
	end)
	skyViewAttrConn = player:GetAttributeChangedSignal(ARENA_SKY_VIEW_ATTR):Connect(function()
		applySkyViewInputMode()
	end)
	applySkyViewInputMode()
end

while rs:Wait() do
	if isArenaSkyViewActive() then
		local mouseLoc = userInputService:GetMouseLocation()
		local aimPoint = getSkyAimPointFromScreen(mouseLoc.X, mouseLoc.Y)
		if aimPoint then
			applyTurretAimTowardWorld(aimPoint)
		end
	else
		updateCrosshairFromBarrel()
		local pivotWorld = gun.body:GetPrimaryPartCFrame().Position
		local aimSource = pivotWorld + touchAimDirXZ * 5000
		if not isTouchDevice then
			local mouseLoc = userInputService:GetMouseLocation()
			local splashHitPos = raycastWaterSplashAtScreen(mouseLoc.X, mouseLoc.Y)
			if splashHitPos then
				aimSource = splashHitPos
			else
				aimSource = mouse.Hit.Position
			end
		end
		if (aimSource - gun.base.Position).Magnitude > 3 then
			applyTurretAimTowardWorld(aimSource)
		end
	end
end
