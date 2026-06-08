--!strict
-- Horizontal exclusion zones around Anti Air turrets so splash spawners avoid overlapping them.

local Workspace = game:GetService("Workspace")

local ANTI_AIR_NAME_PREFIX = "Anti Air"
local TURRET_EXCLUSION_PADDING = 22

export type TurretExclusionZone = {
	centerX: number,
	centerZ: number,
	radiusSq: number,
}

local zones: { TurretExclusionZone } = {}

local refreshScheduled = false

local function isAntiAirTurretModel(model: Model): boolean
	return string.find(model.Name, "^" .. ANTI_AIR_NAME_PREFIX) ~= nil
end

local function zoneRadius(zone: TurretExclusionZone): number
	return math.sqrt(zone.radiusSq)
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

function SplashSpawnExclusions.getNearestZone(pos: Vector3): TurretExclusionZone?
	local best: TurretExclusionZone? = nil
	local bestDistSq = math.huge
	for _, zone in zones do
		local dx = pos.X - zone.centerX
		local dz = pos.Z - zone.centerZ
		local distSq = dx * dx + dz * dz
		if distSq < bestDistSq then
			bestDistSq = distSq
			best = zone
		end
	end
	return best
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

-- Steer a unit XZ velocity away from turret zones; clamp position to the zone edge.
function SplashSpawnExclusions.deflectPosition(
	pos: Vector3,
	velocity: Vector3,
	speed: number,
	dt: number
): (Vector3, Vector3)
	local nextPos = pos + velocity * speed * dt
	local newVel = velocity

	for _, zone in zones do
		local dx = nextPos.X - zone.centerX
		local dz = nextPos.Z - zone.centerZ
		local distSq = dx * dx + dz * dz
		if distSq < zone.radiusSq then
			local radius = zoneRadius(zone)
			local nx: number
			local nz: number
			if distSq > 1e-8 then
				local dist = math.sqrt(distSq)
				nx = dx / dist
				nz = dz / dist
			else
				local dx0 = pos.X - zone.centerX
				local dz0 = pos.Z - zone.centerZ
				local dist0Sq = dx0 * dx0 + dz0 * dz0
				if dist0Sq > 1e-8 then
					local dist0 = math.sqrt(dist0Sq)
					nx = dx0 / dist0
					nz = dz0 / dist0
				else
					nx = 1
					nz = 0
				end
			end

			local vx = newVel.X
			local vz = newVel.Z
			local dot = vx * nx + vz * nz
			if dot < 0 then
				local rx = vx - 2 * dot * nx
				local rz = vz - 2 * dot * nz
				local rMag = math.sqrt(rx * rx + rz * rz)
				if rMag > 1e-4 then
					newVel = Vector3.new(rx / rMag, 0, rz / rMag)
				end
			end

			nextPos = Vector3.new(zone.centerX + nx * radius, pos.Y, zone.centerZ + nz * radius)
		end
	end

	return nextPos, newVel
end

function SplashSpawnExclusions.getZoneCount(): number
	return #zones
end

local function scheduleRefresh(): ()
	if refreshScheduled then
		return
	end
	refreshScheduled = true
	task.defer(function()
		refreshScheduled = false
		SplashSpawnExclusions.refresh()
	end)
end

Workspace.ChildAdded:Connect(function(child: Instance)
	if child:IsA("Model") and isAntiAirTurretModel(child) then
		scheduleRefresh()
	end
end)

Workspace.ChildRemoved:Connect(function(child: Instance)
	if child:IsA("Model") and isAntiAirTurretModel(child) then
		scheduleRefresh()
	end
end)

return SplashSpawnExclusions
