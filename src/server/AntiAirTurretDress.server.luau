local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiAirTurretDress = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirTurretDress") :: ModuleScript)

local ANTI_AIR_NAME_PREFIX = "Anti Air"
local STARTUP_DELAY = 0.25

local function isAntiAirTurretModel(instance: Instance): boolean
	return instance:IsA("Model") and string.find(instance.Name, "^" .. ANTI_AIR_NAME_PREFIX) ~= nil
end

local function applyDressIfTurret(instance: Instance)
	if isAntiAirTurretModel(instance) then
		AntiAirTurretDress.apply(instance :: Model)
	end
end

local function dressAllTurrets(): number
	local count = 0
	for _, child in Workspace:GetChildren() do
		if isAntiAirTurretModel(child) then
			if AntiAirTurretDress.apply(child :: Model) then
				count += 1
			end
		end
	end
	return count
end

local function start()
	task.wait(STARTUP_DELAY)

	local dressed = dressAllTurrets()
	if dressed == 0 then
		warn("[AntiAirTurretDress] No Anti Air turrets found in Workspace")
	end

	Workspace.ChildAdded:Connect(function(child)
		task.defer(applyDressIfTurret, child)
	end)
end

task.defer(start)
