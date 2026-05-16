--!strict
-- Polyline Beam rope: muzzle -> optional corner anchors (world-fixed) -> moving tip + wedge arrow.

local DEFAULT_LINE_COLOR = Color3.fromRGB(220, 60, 55)
local BEAM_WIDTH = 0.65
local WEDGE_SIZE = Vector3.new(0.85, 0.65, 1.35)

export type RopeOpts = {
	lineColor: Color3?,
	muzzleStuds: number?,
	halfLengthStuds: number?,
}

export type RopeController = {
	addCorner: (worldPosition: Vector3) -> (),
}

local function beamStyle(beam: Beam, lineColor: Color3)
	beam.Width0 = BEAM_WIDTH
	beam.Width1 = BEAM_WIDTH
	beam.FaceCamera = true
	beam.LightEmission = 0.35
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(lineColor)
	beam.Transparency = NumberSequence.new(0.05)
end

-- Corners + segment beams live in a sibling Folder so they stay world-fixed while the projectile moves.
local function createRopeController(projectile: BasePart, gunPart: BasePart, opts: RopeOpts?): RopeController
	local lineColor = if opts and opts.lineColor then opts.lineColor else DEFAULT_LINE_COLOR
	local muzzleStuds = if opts and opts.muzzleStuds then opts.muzzleStuds else 5
	local halfLen = if opts and opts.halfLengthStuds
		then opts.halfLengthStuds
		else projectile.Size.Z * 0.5

	projectile.Transparency = 1
	projectile.CastShadow = false
	projectile.LocalTransparencyModifier = 0

	local parentInst = projectile.Parent
	assert(parentInst, "[AntiAirHarpoonProjectileVisual] Parent projectile before createRopeController")
	local artifactsFolder = Instance.new("Folder")
	artifactsFolder.Name = "HarpoonRopeArtifacts"
	artifactsFolder.Parent = parentInst

	local attBarrel = Instance.new("Attachment")
	attBarrel.Name = "HarpoonBarrel"
	attBarrel.Position = gunPart.CFrame:VectorToObjectSpace(gunPart.CFrame.LookVector * muzzleStuds)
	attBarrel.Parent = gunPart

	local attTip = Instance.new("Attachment")
	attTip.Name = "HarpoonTip"
	attTip.Position = Vector3.new(0, 0, -halfLen)
	attTip.Parent = projectile

	local tailBeam = Instance.new("Beam")
	tailBeam.Name = "HarpoonTail"
	tailBeam.Attachment0 = attBarrel
	tailBeam.Attachment1 = attTip
	beamStyle(tailBeam, lineColor)
	tailBeam.Parent = artifactsFolder

	local lastChainAttachment: Attachment = attBarrel
	local cornerIndex = 0

	local wedge = Instance.new("WedgePart")
	wedge.Name = "HarpoonArrow"
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.CanQuery = false
	wedge.CanTouch = false
	wedge.CastShadow = false
	wedge.Material = Enum.Material.Neon
	wedge.Color = lineColor
	wedge.Size = WEDGE_SIZE
	wedge.Transparency = 0.1
	wedge.CFrame = projectile.CFrame * CFrame.new(0, 0, -halfLen - wedge.Size.Z * 0.35) * CFrame.Angles(0, math.pi, 0)
	wedge.Parent = projectile

	local alignConn: RBXScriptConnection
	alignConn = projectile:GetPropertyChangedSignal("CFrame"):Connect(function()
		if not wedge.Parent then
			alignConn:Disconnect()
			return
		end
		wedge.CFrame = projectile.CFrame * CFrame.new(0, 0, -halfLen - wedge.Size.Z * 0.35) * CFrame.Angles(0, math.pi, 0)
	end)

	local function addCorner(worldPosition: Vector3)
		cornerIndex += 1
		local corner = Instance.new("Part")
		corner.Name = "HarpoonCorner" .. tostring(cornerIndex)
		corner.Size = Vector3.new(0.08, 0.08, 0.08)
		corner.Transparency = 1
		corner.Anchored = true
		corner.CanCollide = false
		corner.CanQuery = false
		corner.CanTouch = false
		corner.CFrame = CFrame.new(worldPosition)
		corner.Parent = artifactsFolder

		local attCorner = Instance.new("Attachment")
		attCorner.Name = "HarpoonCornerAtt"
		attCorner.Parent = corner

		local segBeam = Instance.new("Beam")
		segBeam.Name = "HarpoonSeg" .. tostring(cornerIndex)
		segBeam.Attachment0 = lastChainAttachment
		segBeam.Attachment1 = attCorner
		beamStyle(segBeam, lineColor)
		segBeam.Parent = artifactsFolder

		tailBeam.Attachment0 = attCorner
		lastChainAttachment = attCorner
	end

	projectile.Destroying:Connect(function()
		if artifactsFolder.Parent then
			artifactsFolder:Destroy()
		end
		if attBarrel.Parent then
			attBarrel:Destroy()
		end
		alignConn:Disconnect()
	end)

	return {
		addCorner = addCorner,
	}
end

return {
	createRopeController = createRopeController,
}
