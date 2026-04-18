local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MAP_FOLDER_NAME = "Map"
local RENDER_BIND_NAME = "BlastHubArenaSkyCam"
local ACTION_NAME = "BlastHubArenaSkyView"
local TOGGLE_KEY = Enum.KeyCode.M

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local skyViewActive = false
local skyCFrame: CFrame? = nil
local savedCameraType: Enum.CameraType = Enum.CameraType.Custom
local savedCameraSubject: Instance? = nil

local function accumulatePartAABB(cf: CFrame, size: Vector3, minV: Vector3, maxV: Vector3): (Vector3, Vector3)
	local half = size * 0.5
	local minOut, maxOut = minV, maxV
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local localCorner = Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
				local world = cf * localCorner
				minOut = minOut:Min(world)
				maxOut = maxOut:Max(world)
			end
		end
	end
	return minOut, maxOut
end

local function getMapAABB(map: Instance): (Vector3?, Vector3?)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false

	for _, inst in map:GetDescendants() do
		if inst:IsA("BasePart") then
			any = true
			minV, maxV = accumulatePartAABB(inst.CFrame, inst.Size, minV, maxV)
		end
	end

	if not any then
		return nil, nil
	end
	return minV, maxV
end

local function computeSkyCFrame(map: Instance): CFrame?
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end

	local minV, maxV = getMapAABB(map)
	if not minV or not maxV then
		return nil
	end

	local center = (minV + maxV) * 0.5
	local extents = maxV - minV
	local extentX, extentY, extentZ = extents.X, extents.Y, extents.Z

	-- Worst-case XZ footprint is the diagonal (max(X,Z) over-shoots long thin arenas).
	local planarHalfDiagonal = 0.5 * math.sqrt(extentX * extentX + extentZ * extentZ)

	local vp = cam.ViewportSize
	local aspect = if vp.Y > 1 then vp.X / vp.Y else 16 / 9
	local tanHalf = math.tan(math.rad(cam.FieldOfView) * 0.5)
	-- Looking straight down, horizontal screen pixels cover more world studs (× aspect).
	local groundHalfPerStudUp = math.max(tanHalf * aspect, 0.001)

	-- Small padding only; Y term is a slight cushion so lane props do not clip the frustum edge.
	local altitude = planarHalfDiagonal / groundHalfPerStudUp + extentY * 0.08 + 6

	local eye = center + Vector3.new(0, altitude, 0)
	return CFrame.lookAt(eye, center)
end

local function applySkyCamera()
	if skyCFrame and camera then
		camera.CFrame = skyCFrame
	end
end

local function enableSkyView(map: Instance)
	camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local cf = computeSkyCFrame(map)
	if not cf then
		warn("[ArenaSkyCam] Map folder has no BaseParts; cannot frame sky view.")
		return
	end

	savedCameraType = camera.CameraType
	savedCameraSubject = camera.CameraSubject

	skyCFrame = cf
	skyViewActive = true
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	applySkyCamera()

	RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Camera.Value + 20, applySkyCamera)
end

local function disableSkyView()
	if not skyViewActive then
		return
	end

	skyViewActive = false
	skyCFrame = nil

	-- Unbind is a no-op if this name was never bound (no IsBoundToRenderStep in engine).
	RunService:UnbindFromRenderStep(RENDER_BIND_NAME)

	camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = savedCameraType
	camera.CameraSubject = savedCameraSubject

	if camera.CameraSubject == nil and camera.CameraType == Enum.CameraType.Custom then
		local character = player.Character
		local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArenaSkyCamGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 45
screenGui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "SkyViewToggle"
button.AnchorPoint = Vector2.new(0, 0)
button.Position = UDim2.new(0, 16, 0, 16)
button.Size = UDim2.fromOffset(120, 36)
button.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
button.BackgroundTransparency = 0.15
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.TextSize = 16
button.TextColor3 = Color3.fromRGB(220, 235, 255)
button.Text = "Sky view"
button.AutoButtonColor = true
button.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = button

local function refreshButtonLabel()
	if skyViewActive then
		button.Text = "Close sky"
	else
		button.Text = "Sky view"
	end
end

local function toggleSkyView()
	local map = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	if not map then
		warn("[ArenaSkyCam] Workspace.Map not found.")
		return
	end

	if skyViewActive then
		disableSkyView()
	else
		enableSkyView(map)
	end

	refreshButtonLabel()
end

local function onBoundAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if UserInputService:GetFocusedTextBox() ~= nil then
		return Enum.ContextActionResult.Pass
	end
	toggleSkyView()
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(ACTION_NAME, onBoundAction, true, TOGGLE_KEY)

button.MouseButton1Click:Connect(function()
	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	toggleSkyView()
end)

player.CharacterRemoving:Connect(function()
	if skyViewActive then
		disableSkyView()
		refreshButtonLabel()
	end
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = Workspace.CurrentCamera
	if skyViewActive and camera then
		RunService:UnbindFromRenderStep(RENDER_BIND_NAME)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil
		RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Camera.Value + 20, applySkyCamera)
	end
end)
