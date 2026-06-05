--!strict
-- Hides Anti Air 3D visuals and mounts a top-down PNG SurfaceGui that swivels with body yaw.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirTurretDressConfig") :: ModuleScript)

local ANTI_AIR_NAME_PREFIX = "Anti Air"
local DRESS_VERSION_ATTRIBUTE = "AntiAirDressVersion"
local DRESS_FOLDER_NAME = "AntiAirDress"
local ANCHOR_NAME = "AntiAirDressAnchor"
local SURFACE_GUI_NAME = "AntiAirDressSurface"

local AntiAirTurretDress = {}

local function isAntiAirTurretModel(model: Model): boolean
	return string.find(model.Name, "^" .. ANTI_AIR_NAME_PREFIX) ~= nil
end

local function hideVisualParts(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			continue
		end
		if descendant.Name == "gunpart" then
			continue
		end
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("SurfaceGui") then
			descendant.Enabled = false
		end
	end
end

local function resolveFootprint(size: Vector3): (number, number)
	local scale = Config.footprintSizeMultiplier
	local footprintW = math.max(size.X * scale, 2)
	local footprintD = math.max(size.Z * scale, 2)
	return footprintW, footprintD
end

local function resolveFlatLook(bodyPart: BasePart): Vector3
	local flatLook = Vector3.new(bodyPart.CFrame.LookVector.X, 0, bodyPart.CFrame.LookVector.Z)
	if flatLook.Magnitude < 1e-4 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	local yawOffset = math.rad(Config.yawOffsetDegrees)
	if math.abs(yawOffset) > 1e-6 then
		local c = math.cos(yawOffset)
		local s = math.sin(yawOffset)
		flatLook = Vector3.new(flatLook.X * c - flatLook.Z * s, 0, flatLook.X * s + flatLook.Z * c)
	end

	return flatLook
end

function AntiAirTurretDress.apply(model: Model): boolean
	if not isAntiAirTurretModel(model) then
		return false
	end

	local currentVersion = model:GetAttribute(DRESS_VERSION_ATTRIBUTE)
	if typeof(currentVersion) == "number" and currentVersion == Config.dressVersion then
		return false
	end

	local body = model:FindFirstChild("body")
	local gun = model:FindFirstChild("gun")
	local base = model:FindFirstChild("base")
	if not body or not body:IsA("Model") or not gun or not gun:IsA("Model") or not base or not base:IsA("BasePart") then
		warn("[AntiAirTurretDress] Missing body/gun/base for", model:GetFullName())
		return false
	end

	local bodyPart = body.PrimaryPart
	if not bodyPart then
		warn("[AntiAirTurretDress] body PrimaryPart missing for", model:GetFullName())
		return false
	end

	local dressImageId = Config.dressImageId
	if typeof(dressImageId) ~= "string" or dressImageId == "" then
		warn("[AntiAirTurretDress] dressImageId not configured")
		return false
	end

	if Config.hideBaseMesh then
		hideVisualParts(body)
		hideVisualParts(gun)
		base.Transparency = 1
	end

	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then
		warn("[AntiAirTurretDress] GetBoundingBox failed for", model:GetFullName())
		return false
	end

	local existingFolder = model:FindFirstChild(DRESS_FOLDER_NAME)
	if existingFolder then
		existingFolder:Destroy()
	end

	local footprintW, footprintD = resolveFootprint(size)
	local thickness = Config.anchorThickness
	local center = cf.Position + Config.studsOffsetWorldSpace
	local flatLook = resolveFlatLook(bodyPart)

	local folder = Instance.new("Folder")
	folder.Name = DRESS_FOLDER_NAME
	folder.Parent = model

	local anchor = Instance.new("Part")
	anchor.Name = ANCHOR_NAME
	anchor.Size = Vector3.new(footprintW, thickness, footprintD)
	anchor.CFrame = CFrame.lookAt(center, center + flatLook, Vector3.yAxis)
	anchor.Anchored = false
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = folder

	local anchorWeld = Instance.new("WeldConstraint")
	anchorWeld.Part0 = anchor
	anchorWeld.Part1 = bodyPart
	anchorWeld.Parent = anchor

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = SURFACE_GUI_NAME
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.LightInfluence = Config.lightInfluence
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = Config.surfacePixelsPerStud
	surfaceGui.AlwaysOnTop = false
	surfaceGui.Parent = anchor

	local image = Instance.new("ImageLabel")
	image.Name = "DressImage"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = dressImageId
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = surfaceGui

	model:SetAttribute(DRESS_VERSION_ATTRIBUTE, Config.dressVersion)
	return true
end

return AntiAirTurretDress
