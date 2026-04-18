wait(0.20)
local TARGET_RADIUS = 5
local MAX_SPEED = 99900
local MAX_TORQUE = Vector3.new(4e6, 4e6, 0)
local MAX_THRUST = 27500
local THRUST_P = 99900
local THRUST_D = 99900
local HEARTBEAT_SHOT_INTERVAL = 0.2
local RELOAD_SOUND_CUTOFF = 0.08
local CROSSHAIR_DISTANCE = 5000
local HIT_FLASH_REMOTE_NAME = "AntiAirConveyorHitFlash"

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
local rs = game:GetService("RunService").RenderStepped
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")
local originalMouseIcon = mouse.Icon
local replicatedStorage = game:GetService("ReplicatedStorage")
local userInputService = game:GetService("UserInputService")
local contextActionService = game:GetService("ContextActionService")
local USE_TOUCH_STYLE_CONTROLS_FOR_TESTING = false
local isTouchDevice = USE_TOUCH_STYLE_CONTROLS_FOR_TESTING or userInputService.TouchEnabled
local hitFlashRemote = replicatedStorage:WaitForChild(HIT_FLASH_REMOTE_NAME, 30)
if not hitFlashRemote or not hitFlashRemote:IsA("RemoteEvent") then
	warn("[AntiAirFlashClient] Missing RemoteEvent", HIT_FLASH_REMOTE_NAME, "- turret client disabled")
	return
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
local aimTouchPosition: Vector2? = nil
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
	shootButton.Size = UDim2.new(0, 170, 0, 170)
	shootButton.Position = UDim2.new(1, -32, 1, -36)
	shootButton.BackgroundColor3 = Color3.fromRGB(212, 50, 50)
	shootButton.BackgroundTransparency = 0.2
	shootButton.Text = "SHOOT"
	shootButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	shootButton.TextScaled = true
	shootButton.Font = Enum.Font.GothamBold
	shootButton.AutoButtonColor = true
	shootButton.Parent = shootGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
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

	gun.gun.effect.bam:Play()
	local a = Instance.new("Part")
	local gunPart = gun.gun.gunpart
	local spawnPosition = gun.gun.gunpart.Position + (gun.gun.gunpart.CFrame.lookVector * 5)
	local shotTarget = aimpos
	a.Size = Vector3.new(0.4, 0.4, 9)
	a.CFrame = CFrame.new(spawnPosition, shotTarget)
	a.BrickColor = BrickColor.new("Bright yellow")
	a.Material = "Neon"
	local rocketPropulsion = Instance.new("RocketPropulsion", a)
	rocketPropulsion.CartoonFactor = 1
	rocketPropulsion.TargetRadius = TARGET_RADIUS
	rocketPropulsion.MaxSpeed = MAX_SPEED
	rocketPropulsion.MaxTorque = MAX_TORQUE
	rocketPropulsion.MaxThrust = MAX_THRUST
	rocketPropulsion.ThrustP = THRUST_P
	rocketPropulsion.ThrustD = THRUST_D
	local direction = (shotTarget - a.Position).unit
	rocketPropulsion.TargetOffset = a.Position + (direction * 10000000)
	rocketPropulsion:Fire()
	debugLog("Shot fired", "mouseTarget=", mouse.Target and mouse.Target:GetFullName() or "nil")

	if mouse.Target and hitFlashRemote and hitFlashRemote:IsA("RemoteEvent") then
		debugLog("FireServer via mouse.Target", mouse.Target:GetFullName())
		hitFlashRemote:FireServer(mouse.Target)
	end

	a.CanCollide = false
	a.CanTouch = true
	a.Touched:Connect(function(otherPart)
		if otherPart and otherPart:IsA("BasePart") and hitFlashRemote and hitFlashRemote:IsA("RemoteEvent") then
			debugLog("FireServer via projectile touched", otherPart:GetFullName())
			hitFlashRemote:FireServer(otherPart)
		end
	end)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { gun, player.Character }
	local rayDirection = shotTarget - gunPart.Position
	local rayResult = workspace:Raycast(gunPart.Position, rayDirection, rayParams)
	if rayResult then
		if hitFlashRemote and hitFlashRemote:IsA("RemoteEvent") then
			debugLog("FireServer via raycast", rayResult.Instance:GetFullName())
			hitFlashRemote:FireServer(rayResult.Instance)
		end
	else
		debugLog("Raycast had no hit")
	end

	a.Parent = game.Workspace
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

	local bulletTemplate = script:FindFirstChild("bullet")
	if bulletTemplate and (bulletTemplate:IsA("Script") or bulletTemplate:IsA("LocalScript")) then
		local b = bulletTemplate:Clone()
		b.Parent = a
		local bulletValue = b:FindFirstChild("Value")
		if bulletValue and bulletValue:IsA("ObjectValue") then
			bulletValue.Value = gun.gun.gunpart
		end
		b.Disabled = false
	end

	game:GetService("Debris"):AddItem(a, 7)
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
	aimTouchPosition = nil
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

if isTouchDevice then
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
				playerControls:Disable()
				didDisableDefaultTouchControls = true
			else
				warn("[AntiAirFlashClient] Unable to disable default touch controls", controlsOrErr)
			end
		end
	end

	mobileFireGui, mobileShootButton = createMobileControls()
	if mobileShootButton then
		mobileShootButton.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				shootHeld = true
				holdingFire = true
				startFiring()
			end
		end)
		mobileShootButton.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				shootHeld = false
				stopFiring()
			end
		end)
	end

	touchStartConn = userInputService.TouchStarted:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or activeAimTouch then
			return
		end
		local viewport = camera and camera.ViewportSize or Vector2.new(0, 0)
		if input.Position.X <= (viewport.X * 0.5) then
			activeAimTouch = input
			aimTouchPosition = input.Position
		end
	end)

	touchMoveConn = userInputService.TouchMoved:Connect(function(input: InputObject, _gameProcessed: boolean)
		if input == activeAimTouch then
			aimTouchPosition = input.Position
		end
	end)

	touchEndConn = userInputService.TouchEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		if input == activeAimTouch then
			activeAimTouch = nil
			aimTouchPosition = nil
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
	if isTouchDevice and aimTouchPosition and camera then
		local ray = camera:ViewportPointToRay(aimTouchPosition.X, aimTouchPosition.Y)
		local rayDistance = 5000
		aimpos = ray.Origin + (ray.Direction * rayDistance)
	elseif not isTouchDevice then
		aimpos = mouse.Hit.p
	end

	local pivotWorld = gun.body:GetPrimaryPartCFrame().Position
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
