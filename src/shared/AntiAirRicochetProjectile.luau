--!strict
-- Moves a non-physical bullet by raycasting each frame; reflects off Workspace.BulletArenaBoundaries
-- and Anti Air turret geometry using RaycastResult.Normal; stops and reports conveyor hits via callback.

local BOUNDARY_FOLDER_NAME = "BulletArenaBoundaries"
local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"
local ANTI_AIR_NAME_PREFIX = "Anti Air"
local HORIZONTAL_SURFACE_NORMAL_Y_MIN = 0.9

-- Set to true to restore bouncing off BulletArenaBoundaries and Anti Air turret geometry.
local ANTI_AIR_RICOCHET_ENABLED = false

export type PostHitRetract = {
	retractDuration: number?,
	retractFollowModel: Model?,
	-- Local offset from projectile CFrame for the catch model pivot (default applied in retract).
	retractFollowOffset: CFrame?,
	onRetractComplete: (() -> ())?,
	deferSplashReelMeter: boolean?,
}

export type RicochetOptions = {
	speed: number,
	maxLifetimeSeconds: number,
	raycastExclude: { Instance },
	onConveyorHit: (hitPart: BasePart) -> PostHitRetract?,
	-- Optional: tween toward muzzle before destroy (harpoon retract).
	retractToPart: BasePart?,
	retractDuration: number?,
	retractMuzzleStuds: number?,
	-- Optional: world-space kink for polyline rope (arena / turret bounces).
	onBounce: ((worldCorner: Vector3) -> ())?,
	-- When true with retract fields set: lifetime timeout skips retract (instant destroy).
	retractOnlyOnHit: boolean?,
	-- Called when deferSplashReelMeter is set on hit; retract runs after beginDeferredRetract.
	onSplashReelMeterPending: ((projectile: BasePart, merge: PostHitRetract) -> ())?,
}

type DeferredRetractRow = {
	merge: PostHitRetract,
	retractToPart: BasePart,
	retractMuzzleStuds: number,
	runService: RunService,
}

local deferredByProjectile: { [BasePart]: DeferredRetractRow } = {}

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

local function hardDestroyProjectile(projectile: BasePart)
	if projectile.Parent then
		projectile:Destroy()
	end
end

local function runRetractTween(
	projectile: BasePart,
	merge: PostHitRetract?,
	retractPart: BasePart,
	muzzleStuds: number,
	dur: number,
	runService: RunService
)
	local followModel = merge and merge.retractFollowModel
	local followOffset = if merge and merge.retractFollowOffset then merge.retractFollowOffset else CFrame.new(0, 0, -12)
	local onRetractComplete = merge and merge.onRetractComplete
	local startPos = projectile.Position
	local tRetract0 = os.clock()
	if followModel and followModel.Parent then
		pcall(function()
			followModel:PivotTo(projectile.CFrame * followOffset)
		end)
	end
	local connR: RBXScriptConnection
	connR = runService.Heartbeat:Connect(function()
		if not projectile.Parent then
			connR:Disconnect()
			if onRetractComplete then
				task.defer(onRetractComplete)
			end
			return
		end
		if not retractPart.Parent then
			connR:Disconnect()
			if onRetractComplete then
				task.defer(onRetractComplete)
			end
			hardDestroyProjectile(projectile)
			return
		end
		local look = retractPart.CFrame.LookVector
		if look.Magnitude < 1e-5 then
			look = Vector3.new(0, 0, -1)
		else
			look = look.Unit
		end
		local goal = retractPart.Position + look * muzzleStuds
		local elapsed = os.clock() - tRetract0
		local alpha = math.clamp(elapsed / dur, 0, 1)
		local pos = startPos:Lerp(goal, alpha)
		projectile.CFrame = CFrame.lookAt(pos, goal)
		if followModel and followModel.Parent then
			pcall(function()
				followModel:PivotTo(projectile.CFrame * followOffset)
			end)
		end
		if alpha >= 1 then
			connR:Disconnect()
			if onRetractComplete then
				task.defer(onRetractComplete)
			end
			hardDestroyProjectile(projectile)
		end
	end)
end

-- Remove pending deferred retract without running the tween (e.g. fish escaped).
local function releaseDeferredRetract(projectile: BasePart): boolean
	if deferredByProjectile[projectile] then
		deferredByProjectile[projectile] = nil
		return true
	end
	return false
end

-- Run the stored retract tween after splash reel meter fills.
local function beginDeferredRetract(projectile: BasePart)
	local row = deferredByProjectile[projectile]
	if not row then
		return
	end
	deferredByProjectile[projectile] = nil
	local mergeDur = row.merge.retractDuration
	local dur = if typeof(mergeDur) == "number" and mergeDur > 1e-3 then mergeDur else 0.38
	runRetractTween(projectile, row.merge, row.retractToPart, row.retractMuzzleStuds, dur, row.runService)
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

	local function destroyProjectileAfterRetractIfConfigured(merge: PostHitRetract?)
		local retractPart = options.retractToPart
		local baseDur = options.retractDuration
		local mergeDur = merge and merge.retractDuration
		local dur = if typeof(mergeDur) == "number" and mergeDur > 1e-3
			then mergeDur
			elseif typeof(baseDur) == "number" and baseDur > 1e-3 then baseDur
			else nil
		local muzzleStuds = if typeof(options.retractMuzzleStuds) == "number" then options.retractMuzzleStuds else 5

		if merge
			and merge.deferSplashReelMeter == true
			and options.onSplashReelMeterPending
			and retractPart
			and retractPart.Parent
			and typeof(dur) == "number"
			and dur > 1e-3
		then
			local followModel = merge.retractFollowModel
			local followOffset = if merge.retractFollowOffset then merge.retractFollowOffset else CFrame.new(0, 0, -12)
			if followModel and followModel.Parent then
				pcall(function()
					followModel:PivotTo(projectile.CFrame * followOffset)
				end)
			end
			deferredByProjectile[projectile] = {
				merge = merge,
				retractToPart = retractPart,
				retractMuzzleStuds = muzzleStuds,
				runService = runService,
			}
			options.onSplashReelMeterPending(projectile, merge)
			return
		end

		if retractPart and retractPart.Parent and dur then
			runRetractTween(projectile, merge, retractPart, muzzleStuds, dur, runService)
		else
			if merge and merge.onRetractComplete then
				task.defer(merge.onRetractComplete)
			end
			hardDestroyProjectile(projectile)
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
			if options.retractOnlyOnHit == true then
				hardDestroyProjectile(projectile)
			else
				destroyProjectileAfterRetractIfConfigured()
			end
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
			if inst:IsA("BasePart") and (isBoundaryPart(inst) or isTurretPart(inst)) and ANTI_AIR_RICOCHET_ENABLED then
				local bounceNormal = getBounceNormal(dir, hit.Normal)
				local separationNormal = getStableSeparationNormal(bounceNormal)
				dir = getStableRicochetDirection(dir, bounceNormal)
				local onBounce = options.onBounce
				if onBounce then
					local cornerWorld = hit.Position + separationNormal * 0.12
					onBounce(cornerWorld)
				end
				-- Keep the projectile outside the collider along the same normal used for reflection.
				pos = hit.Position + separationNormal * 0.35 + dir * 0.25
			else
				local convPart = getConveyorHitPart(inst)
				if convPart then
					pos = hit.Position - dir * 0.1
					projectile.CFrame = CFrame.new(pos, pos + dir)
					alive = false
					conn:Disconnect()
					local postHit = options.onConveyorHit(convPart)
					destroyProjectileAfterRetractIfConfigured(postHit)
					return
				else
					pos = hit.Position - dir * 0.05
					projectile.CFrame = CFrame.new(pos, pos + dir)
					alive = false
					conn:Disconnect()
					destroyProjectileAfterRetractIfConfigured()
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
	beginDeferredRetract = beginDeferredRetract,
	releaseDeferredRetract = releaseDeferredRetract,
}
