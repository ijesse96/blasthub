--!strict
local Workspace = game:GetService("Workspace")

local AutoFireConfig = require(script.Parent:WaitForChild("AntiAirAutoFireConfig"))

local CONVEYOR_ACTIVE_FOLDER = "ConveyorActiveItems"
local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"
local WATER_SPLASHES_FOLDER_NAME = "WaterSplashes"
local IS_WATER_SPLASH_ATTRIBUTE = "IsWaterSplash"
local SPLASH_HIT_COLLIDER_NAME = "SplashHitCollider"

export type AutoTarget = {
	worldPoint: Vector3,
	splashModel: Model?,
}

local function getSplashWorldPoint(splashModel: Model): Vector3
	local hit = splashModel:FindFirstChild(SPLASH_HIT_COLLIDER_NAME, true)
	if hit and hit:IsA("BasePart") then
		return hit.Position
	end
	return splashModel:GetPivot().Position
end

local function getNearestConveyorPosition(origin: Vector3): Vector3?
	local folder = Workspace:FindFirstChild(CONVEYOR_ACTIVE_FOLDER)
	if not folder then
		return nil
	end

	local bestPos: Vector3? = nil
	local bestDist = math.huge
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(CONVEYOR_ITEM_ATTRIBUTE) == true then
			local pos = child:GetPivot().Position
			local dist = (pos - origin).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestPos = pos
			end
		end
	end
	return bestPos
end

local function getNearestWaterSplash(origin: Vector3, maxDistance: number): (Model?, Vector3?)
	local folder = Workspace:FindFirstChild(WATER_SPLASHES_FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		return nil, nil
	end

	local bestModel: Model? = nil
	local bestPoint: Vector3? = nil
	local bestDist = math.huge
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(IS_WATER_SPLASH_ATTRIBUTE) == true then
			local pos = getSplashWorldPoint(child)
			local dist = (pos - origin).Magnitude
			if dist <= maxDistance and dist < bestDist then
				bestDist = dist
				bestModel = child
				bestPoint = pos
			end
		end
	end
	return bestModel, bestPoint
end

local function pickNearestTarget(origin: Vector3): AutoTarget?
	local maxSplashDist = AutoFireConfig.MAX_CHOSEN_SPLASH_DISTANCE_FROM_GUN
	local splashModel, splashPoint = getNearestWaterSplash(origin, maxSplashDist)
	local conveyorPoint = getNearestConveyorPosition(origin)

	local splashDist = if splashPoint then (splashPoint - origin).Magnitude else math.huge
	local conveyorDist = if conveyorPoint then (conveyorPoint - origin).Magnitude else math.huge

	if splashDist <= conveyorDist and splashPoint then
		return {
			worldPoint = splashPoint,
			splashModel = splashModel,
		}
	end
	if conveyorPoint then
		return {
			worldPoint = conveyorPoint,
			splashModel = nil,
		}
	end
	return nil
end

return {
	getNearestConveyorPosition = getNearestConveyorPosition,
	getNearestWaterSplash = getNearestWaterSplash,
	pickNearestTarget = pickNearestTarget,
	getSplashWorldPoint = getSplashWorldPoint,
}
