--!strict
-- Playable floor region inside Workspace.BulletArenaBoundaries (not the outer wall AABB).

local Workspace = game:GetService("Workspace")

local BOUNDARY_FOLDER_NAME = "BulletArenaBoundaries"
local INTERIOR_MARGIN = 5

export type SpawnBounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	floorY: number,
	widthX: number,
	depthZ: number,
}

type HalfPlane = {
	nx: number,
	nz: number,
	minDot: number,
}

local spawnBounds: SpawnBounds? = nil
local halfPlanes: { HalfPlane } = {}

local function getPartWorldCorners(part: BasePart): { Vector3 }
	local cf = part.CFrame
	local h = part.Size * 0.5
	return {
		cf * Vector3.new(-h.X, -h.Y, -h.Z),
		cf * Vector3.new(h.X, -h.Y, -h.Z),
		cf * Vector3.new(-h.X, h.Y, -h.Z),
		cf * Vector3.new(h.X, h.Y, -h.Z),
		cf * Vector3.new(-h.X, -h.Y, h.Z),
		cf * Vector3.new(h.X, -h.Y, h.Z),
		cf * Vector3.new(-h.X, h.Y, h.Z),
		cf * Vector3.new(h.X, h.Y, h.Z),
	}
end

local function getWorkspaceBaseplateTopY(): number?
	local bp = Workspace:FindFirstChild("Baseplate")
	if bp and bp:IsA("BasePart") then
		return bp.Position.Y + bp.Size.Y * 0.5
	end
	return nil
end

local function horizontalUnit(dir: Vector3): (number?, number?, number?)
	local nx, nz = dir.X, dir.Z
	local len = math.sqrt(nx * nx + nz * nz)
	if len < 0.5 then
		return nil, nil, nil
	end
	return nx / len, nz / len, len
end

local SplashArenaInterior = {}

function SplashArenaInterior.refresh(): boolean
	table.clear(halfPlanes)
	spawnBounds = nil

	local folder = Workspace:FindFirstChild(BOUNDARY_FOLDER_NAME)
	if not folder then
		warn("[SplashArenaInterior] Workspace folder '" .. BOUNDARY_FOLDER_NAME .. "' not found.")
		return false
	end

	local outerMinX, outerMaxX = math.huge, -math.huge
	local outerMinZ, outerMaxZ = math.huge, -math.huge
	local minCornerY = math.huge
	local partCount = 0
	local sumX, sumZ = 0, 0

	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") then
			partCount += 1
			sumX += desc.Position.X
			sumZ += desc.Position.Z
			for _, v in getPartWorldCorners(desc) do
				if v.X < outerMinX then
					outerMinX = v.X
				end
				if v.X > outerMaxX then
					outerMaxX = v.X
				end
				if v.Z < outerMinZ then
					outerMinZ = v.Z
				end
				if v.Z > outerMaxZ then
					outerMaxZ = v.Z
				end
				if v.Y < minCornerY then
					minCornerY = v.Y
				end
			end
		end
	end

	if partCount == 0 or outerMinX >= outerMaxX - 1e-4 or outerMinZ >= outerMaxZ - 1e-4 then
		warn("[SplashArenaInterior] BulletArenaBoundaries has no BaseParts or degenerate bounds.")
		return false
	end

	local centerX = sumX / partCount
	local centerZ = sumZ / partCount

	local innerMinX = outerMinX
	local innerMaxX = outerMaxX
	local innerMinZ = outerMinZ
	local innerMaxZ = outerMaxZ

	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			local cf = part.CFrame
			local size = part.Size
			local faceDefs = {
				{ dir = cf.RightVector, half = size.X * 0.5 },
				{ dir = -cf.RightVector, half = size.X * 0.5 },
				{ dir = cf.LookVector, half = size.Z * 0.5 },
				{ dir = -cf.LookVector, half = size.Z * 0.5 },
			}

			for _, face in faceDefs do
				local nx, nz, _ = horizontalUnit(face.dir)
				if not nx then
					continue
				end

				local faceCenter = cf.Position + face.dir * face.half
				local toCenterX = centerX - faceCenter.X
				local toCenterZ = centerZ - faceCenter.Z
				if toCenterX * nx + toCenterZ * nz <= 0 then
					continue
				end

				local minDot = nx * faceCenter.X + nz * faceCenter.Z + INTERIOR_MARGIN
				table.insert(halfPlanes, { nx = nx, nz = nz, minDot = minDot })

				if nx > 0.9 then
					innerMinX = math.max(innerMinX, minDot)
				elseif nx < -0.9 then
					innerMaxX = math.min(innerMaxX, -minDot)
				end
				if nz > 0.9 then
					innerMinZ = math.max(innerMinZ, minDot)
				elseif nz < -0.9 then
					innerMaxZ = math.min(innerMaxZ, -minDot)
				end
			end
		end
	end

	if innerMinX >= innerMaxX - 1e-4 or innerMinZ >= innerMaxZ - 1e-4 then
		innerMinX = outerMinX + INTERIOR_MARGIN
		innerMaxX = outerMaxX - INTERIOR_MARGIN
		innerMinZ = outerMinZ + INTERIOR_MARGIN
		innerMaxZ = outerMaxZ - INTERIOR_MARGIN
	end

	if innerMinX >= innerMaxX - 1e-4 or innerMinZ >= innerMaxZ - 1e-4 then
		warn("[SplashArenaInterior] Inner spawn bounds degenerate after wall inset.")
		return false
	end

	local baseTop = getWorkspaceBaseplateTopY()
	local floorY = if baseTop ~= nil then baseTop else minCornerY

	spawnBounds = {
		minX = innerMinX,
		maxX = innerMaxX,
		minZ = innerMinZ,
		maxZ = innerMaxZ,
		floorY = floorY,
		widthX = innerMaxX - innerMinX,
		depthZ = innerMaxZ - innerMinZ,
	}

	return true
end

function SplashArenaInterior.getSpawnBounds(): SpawnBounds?
	return spawnBounds
end

function SplashArenaInterior.isInsideArena(pos: Vector3): boolean
	if not spawnBounds then
		return false
	end

	local x, z = pos.X, pos.Z
	for _, plane in halfPlanes do
		if x * plane.nx + z * plane.nz < plane.minDot - 1e-3 then
			return false
		end
	end

	return true
end

return SplashArenaInterior
