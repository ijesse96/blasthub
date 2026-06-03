--!strict
-- Horizontal exclusion zones around Anti Air turrets so splash spawners avoid overlapping them.

local Workspace = game:GetService("Workspace")

local ANTI_AIR_NAME_PREFIX = "Anti Air"
local TURRET_EXCLUSION_PADDING = 14

export type TurretExclusionZone = {
	centerX: number,
	centerZ: number,
	radiusSq: number,
}

local zones: { TurretExclusionZone } = {}

local function isAntiAirTurretModel(model: Model): boolean
	return string.find(model.Name, "^" .. ANTI_AIR_NAME_PREFIX) ~= nil
end

local SplashSpawnExclusions = {}

function SplashSpawnExclusions.refresh(): ()
	table.clear(zones)

	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and isAntiAirTurretModel(child) then
			local ok, cf, size = pcall(function()
				return child:GetBoundingBox()
			end)
			if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
				local radius = math.max(size.X, size.Z) * 0.5 + TURRET_EXCLUSION_PADDING
				table.insert(zones, {
					centerX = cf.Position.X,
					centerZ = cf.Position.Z,
					radiusSq = radius * radius,
				})
			end
		end
	end
end

function SplashSpawnExclusions.isNearTurret(pos: Vector3): boolean
	for _, zone in zones do
		local dx = pos.X - zone.centerX
		local dz = pos.Z - zone.centerZ
		if (dx * dx + dz * dz) < zone.radiusSq then
			return true
		end
	end
	return false
end

function SplashSpawnExclusions.getZoneCount(): number
	return #zones
end

return SplashSpawnExclusions
