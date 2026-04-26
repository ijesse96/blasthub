wait(0.20)
local HEARTBEAT_SHOT_INTERVAL = 0.2
local RELOAD_SOUND_CUTOFF = 0.08
local CROSSHAIR_DISTANCE = 5000
local FIRE_REMOTE_NAME = "AntiAirPlayerFire"
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
local USE_TOUCH_STYLE_CONTROLS_FOR_TESTING = false
local isTouchDevice = USE_TOUCH_STYLE_CONTROLS_FOR_TESTING or userInputService.TouchEnabled
local fireRemote = replicatedStorage:WaitForChild(FIRE_REMOTE_NAME, 30)
if not fireRemote or not fireRemote:IsA("RemoteEvent") then
	warn("[AntiAirFlashClient] Missing RemoteEvent", FIRE_REMOTE_NAME, "- turret client disabled")
	return
end
local Ricochet = require(replicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirRicochetProjectile") :: ModuleScript)

local BULLET_SPEED = 600
local BULLET_LIFETIME_SEC = 7
local PREDICT_RECONCILE_TIMEOUT_SEC = 0.55

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
local DISABLE_JUMP_ACTION = "AntiAirDisableJump"
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
local skyKeyboardFireBeganConn: RBXScriptConnection? = nil
local skyKeyboardFireEndConn: RBXScriptConnection? = nil
local touchStartConn: RBXScriptConnection? = nil
local touchMoveConn: RBXScriptConnection? = nil
local touchEndConn: RBXScriptConnection? = nil
mouse.Icon = ""

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

local function fireOnce()
	if not shootHeld then
		return
	end

	-- Aim is applied locally only; server must use our barrel pose (spawn + look) for the replicated projectile.
	local gunPart = gun.gun.gunpart
	local aimLook = gunPart.CFrame.LookVector
	if aimLook.Magnitude > 1e-5 then
		aimLook = aimLook.Unit
	else
		aimLook = Vector3.new(0, 0, -1)
	end
	local spawnPosition = gunPart.Position + (aimLook * 5)

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

	local rayExclude: { Instance } = { gun, predictPart }
	if player.Character then
		table.insert(rayExclude, player.Character)
	end
	local cancelRicochet = Ricochet.start(predictPart, aimLook, workspace, runService, {
		speed = BULLET_SPEED,
		maxLifetimeSeconds = BULLET_LIFETIME_SEC,
		raycastExclude = rayExclude,
		onConveyorHit = function(_hitPart: BasePart) end,
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
		fireRemote:FireServer(spawnPosition, aimLook, shotSeq)
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
	clearAllPredictions()
	if skyViewAttrConn then
		skyViewAttrConn:Disconnect()
		skyViewAttrConn = nil
	end
	if skyKeyboardFireBeganConn then
		skyKeyboardFireBeganConn:Disconnect()
		skyKeyboardFireBeganConn = nil
	end
	if skyKeyboardFireEndConn then
		skyKeyboardFireEndConn:Disconnect()
		skyKeyboardFireEndConn = nil
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

	local function unbindSkyKeyboardStyleFire()
		if skyKeyboardFireBeganConn then
			skyKeyboardFireBeganConn:Disconnect()
			skyKeyboardFireBeganConn = nil
		end
		if skyKeyboardFireEndConn then
			skyKeyboardFireEndConn:Disconnect()
			skyKeyboardFireEndConn = nil
		end
	end

	local function bindSkyKeyboardStyleFire()
		unbindSkyKeyboardStyleFire()
		skyKeyboardFireBeganConn = userInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if not isArenaSkyViewActive() or gameProcessed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				shootHeld = true
				holdingFire = true
				startFiring()
			end
		end)
		skyKeyboardFireEndConn = userInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
			if not isArenaSkyViewActive() then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
		if player:GetAttribute(ARENA_SKY_VIEW_ATTR) == true then
			activeAimTouch = nil
			lastAimTouchScreen = nil
			if mobileFireGui then
				mobileFireGui.Enabled = false
			end
			bindSkyKeyboardStyleFire()
		else
			unbindSkyKeyboardStyleFire()
			if mobileFireGui then
				mobileFireGui.Enabled = true
			end
		end
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
		if input == activeAimTouch then
			activeAimTouch = nil
			lastAimTouchScreen = nil
		end
	end)
else
	mouse.Button1Down:Connect(function()
		shootHeld = true
		holdingFire = true
		startFiring()
	end)
	mouse.Button1Up:Connect(function()
		shootHeld = false
		stopFiring()
	end)
end

-- Intersect viewport ray with horizontal plane through pivot so camera pitch does not change yaw aim.
local function worldPointOnPivotPlaneFromViewportRay(pivotWorld: Vector3, screenX: number, screenY: number): Vector3?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end

	local ray = cam:ViewportPointToRay(screenX, screenY)
	local origin = ray.Origin
	local dir = ray.Direction
	if dir.Magnitude < 1e-6 then
		return nil
	end
	dir = dir.Unit

	local dy = dir.Y
	if math.abs(dy) < 1e-4 then
		local flat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if flat.Magnitude < 1e-4 then
			return nil
		end
		return pivotWorld + flat.Unit * CROSSHAIR_DISTANCE
	end

	local t = (pivotWorld.Y - origin.Y) / dy
	if t < 0 then
		local flat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if flat.Magnitude < 1e-4 then
			return nil
		end
		return pivotWorld + flat.Unit * CROSSHAIR_DISTANCE
	end

	return origin + dir * t
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

while rs:Wait() do
	updateCrosshairFromBarrel()
	local pivotWorld = gun.body:GetPrimaryPartCFrame().Position
	if not isTouchDevice or isArenaSkyViewActive() then
		local mouseLoc = userInputService:GetMouseLocation()
		local planeHit = worldPointOnPivotPlaneFromViewportRay(pivotWorld, mouseLoc.X, mouseLoc.Y)
		if planeHit then
			aimpos = planeHit
		else
			aimpos = mouse.Hit.p
		end
	else
		aimpos = pivotWorld + touchAimDirXZ * 5000
	end
	aimpos = flattenAimToYaw(aimpos, pivotWorld)

	if (aimpos - gun.base.Position).magnitude > 3 then
		local c = aimpos
		local x = (gun.gun:GetPrimaryPartCFrame() * CFrame.new(0, 0, -100000)).x
		local y = (SPAWN * CFrame.new(0, 0, -100000)).y
		local z = (gun.gun:GetPrimaryPartCFrame() * CFrame.new(0, 0, -100000)).z
		local A = Vector3.new(x, y, z)
		if c then
			gun.gun:SetPrimaryPartCFrame(CFrame.new(gun.body:GetPrimaryPartCFrame().p, c))
			gun.body:SetPrimaryPartCFrame(CFrame.new(SPAWN.p, A))
		else
			gun:SetPrimaryPartCFrame(gun.body:GetPrimaryPartCFrame())
			gun.body:SetPrimaryPartCFrame(CFrame.new(SPAWN.p, A))
		end
	end
end
