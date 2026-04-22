--!strict
-- Moves a non-physical bullet by raycasting each frame; reflects off Workspace.BulletArenaBoundaries
-- and Anti Air turret geometry using RaycastResult.Normal; stops and reports conveyor hits via callback.

local BOUNDARY_FOLDER_NAME = "BulletArenaBoundaries"
local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"
local ANTI_AIR_NAME_PREFIX = "Anti Air"
local HORIZONTAL_SURFACE_NORMAL_Y_MIN = 0.9

export type RicochetOptions = {
	speed: number,
	maxLifetimeSeconds: number,
	raycastExclude: { Instance },
	onConveyorHit: (hitPart: BasePart) -> (),
}

local function isBoundaryPart(part: BasePart): boolean
	local folder = part:FindFirstAncestor(BOUNDARY_FOLDER_NAME)
	return folder ~= nil and folder:IsA("Folder")
end

local function isTurretPart(part: BasePart): boolean
	local current: Instance? = part
	while current do
		if current:IsA("Model") then
			local modelName = string.lower(current.Name)
			local turretPrefix = string.lower(ANTI_AIR_NAME_PREFIX)
			if modelName:sub(1, #turretPrefix) == turretPrefix then
				return true
			end
		end
		current = current.Parent
	end
	return false
end

local function getConveyorHitPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		local current: Instance? = instance
		while current do
			if current:IsA("Model") and current:GetAttribute(CONVEYOR_ITEM_ATTRIBUTE) == true then
				return instance
			end
			current = current.Parent
		end
	end
	return nil
end

local function reflectDirection(incidentUnit: Vector3, surfaceNormal: Vector3): Vector3
	local n = surfaceNormal.Unit
	local v = incidentUnit.Unit
	local vn = v:Dot(n)
	if math.abs(vn) < 1e-4 then
		return v
	end
	if vn > 0 then
		n = -n
		vn = -vn
	end
	local r = v - 2 * vn * n
	if r.Magnitude < 1e-4 then
		return v
	end
	return r.Unit
end

local function getBounceNormal(incidentUnit: Vector3, surfaceNormal: Vector3): Vector3
	local n = surfaceNormal.Unit
	if incidentUnit.Unit:Dot(n) > 0 then
		return -n
	end
	return n
end

local function getStableRicochetDirection(incidentUnit: Vector3, bounceNormal: Vector3): Vector3
	local reflected = reflectDirection(incidentUnit, bounceNormal)
	if math.abs(bounceNormal.Y) < HORIZONTAL_SURFACE_NORMAL_Y_MIN then
		-- Wall/slanted-wall ricochets should stay level in anti-air mode.
		local flattened = Vector3.new(reflected.X, 0, reflected.Z)
		if flattened.Magnitude > 1e-4 then
			return flattened.Unit
		end
		return incidentUnit.Unit
	end
	return reflected
end

local function getStableSeparationNormal(bounceNormal: Vector3): Vector3
	if math.abs(bounceNormal.Y) < HORIZONTAL_SURFACE_NORMAL_Y_MIN then
		local lateral = Vector3.new(bounceNormal.X, 0, bounceNormal.Z)
		if lateral.Magnitude > 1e-4 then
			return lateral.Unit
		end
	end
	return bounceNormal
end

local function buildRaycastParams(projectile: BasePart, exclude: { Instance }): RaycastParams
	local list = table.clone(exclude)
	table.insert(list, projectile)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = list
	return p
end

-- Returns disconnect function to stop the simulation early.
local function start(
	projectile: BasePart,
	facingUnit: Vector3,
	workspaceInst: Workspace,
	runService: RunService,
	options: RicochetOptions
): () -> ()
	local rayParams = buildRaycastParams(projectile, options.raycastExclude)
	local dir = facingUnit.Unit
	local alive = true
	local t0 = os.clock()

	local function destroyProjectile()
		if projectile.Parent then
			projectile:Destroy()
		end
	end

	local conn: RBXScriptConnection
	conn = runService.Heartbeat:Connect(function(dt)
		if not alive or not projectile.Parent then
			if alive then
				alive = false
				conn:Disconnect()
			end
			return
		end

		if os.clock() - t0 >= options.maxLifetimeSeconds then
			alive = false
			conn:Disconnect()
			destroyProjectile()
			return
		end

		local remaining = options.speed * math.clamp(dt, 0, 1 / 15)
		local pos = projectile.Position
		local iterations = 0

		while remaining > 1e-4 and iterations < 12 do
			iterations += 1
			local cast = dir * remaining
			local hit = workspaceInst:Raycast(pos, cast, rayParams)

			if not hit then
				pos = pos + cast
				remaining = 0
				break
			end

			local seg = (hit.Position - pos).Magnitude
			remaining -= seg
			local inst = hit.Instance
			if inst:IsA("BasePart") and (isBoundaryPart(inst) or isTurretPart(inst)) then
				local bounceNormal = getBounceNormal(dir, hit.Normal)
				local separationNormal = getStableSeparationNormal(bounceNormal)
				dir = getStableRicochetDirection(dir, bounceNormal)
				-- Keep the projectile outside the collider along the same normal used for reflection.
				pos = hit.Position + separationNormal * 0.35 + dir * 0.25
			else
				local convPart = getConveyorHitPart(inst)
				if convPart then
					pos = hit.Position - dir * 0.1
					projectile.CFrame = CFrame.new(pos, pos + dir)
					alive = false
					conn:Disconnect()
					options.onConveyorHit(convPart)
					destroyProjectile()
					return
				else
					pos = hit.Position - dir * 0.05
					projectile.CFrame = CFrame.new(pos, pos + dir)
					alive = false
					conn:Disconnect()
					destroyProjectile()
					return
				end
			end
		end

		projectile.CFrame = CFrame.new(pos, pos + dir)
	end)

	return function()
		if alive then
			alive = false
			conn:Disconnect()
		end
	end
end

return {
	start = start,
}
