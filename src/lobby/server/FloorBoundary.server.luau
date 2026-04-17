local Workspace = game:GetService("Workspace")

local FLOOR_NAME = "model floor"
local BOUNDARY_FOLDER_NAME = "LobbyBoundaries"

local WALL_HEIGHT = 40
local WALL_THICKNESS = 6
local WALL_PADDING = 0
local SAFETY_FLOOR_DROP = 12
local DEBUG_SHOW_BOUNDARIES = true

local function normalizeName(name: string): string
	return string.lower((name:gsub("%s+", "")))
end

local function findFloorTarget(): PVInstance?
	local wanted = normalizeName(FLOOR_NAME)
	for _, inst in Workspace:GetDescendants() do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and normalizeName(inst.Name) == wanted then
			return inst
		end
	end
	return nil
end

local function getOrCreateBoundaryFolder(): Folder
	local folder = Workspace:FindFirstChild(BOUNDARY_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		folder:ClearAllChildren()
		return folder
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = BOUNDARY_FOLDER_NAME
	newFolder.Parent = Workspace
	return newFolder
end

local function makeWall(name: string, size: Vector3, cframe: CFrame, parent: Instance)
	local wall = Instance.new("Part")
	wall.Name = name
	wall.Size = size
	wall.CFrame = cframe
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = false
	wall.CanTouch = false
	wall.Transparency = DEBUG_SHOW_BOUNDARIES and 0.55 or 1
	wall.Material = DEBUG_SHOW_BOUNDARIES and Enum.Material.ForceField or Enum.Material.SmoothPlastic
	wall.Color = DEBUG_SHOW_BOUNDARIES and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
	wall.Locked = true
	wall.Parent = parent
end

local function getTargetBounds(target: PVInstance): (CFrame, Vector3)
	if target:IsA("Model") then
		return target:GetBoundingBox()
	end
	local basePart = target :: BasePart
	return basePart.CFrame, basePart.Size
end

local floorTarget = findFloorTarget()
if not floorTarget then
	warn("[Lobby] Could not find floor target named 'model floor' (Model or Part).")
	return
end

local center, size = getTargetBounds(floorTarget)
local halfX = size.X * 0.5 + WALL_PADDING
local halfZ = size.Z * 0.5 + WALL_PADDING

local wallsFolder = getOrCreateBoundaryFolder()

makeWall(
	"NorthWall",
	Vector3.new(size.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
	center * CFrame.new(0, size.Y * 0.5 + WALL_HEIGHT * 0.5, -(halfZ + WALL_THICKNESS * 0.5)),
	wallsFolder
)

makeWall(
	"SouthWall",
	Vector3.new(size.X + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
	center * CFrame.new(0, size.Y * 0.5 + WALL_HEIGHT * 0.5, halfZ + WALL_THICKNESS * 0.5),
	wallsFolder
)

makeWall(
	"WestWall",
	Vector3.new(WALL_THICKNESS, WALL_HEIGHT, size.Z + WALL_THICKNESS * 2),
	center * CFrame.new(-(halfX + WALL_THICKNESS * 0.5), size.Y * 0.5 + WALL_HEIGHT * 0.5, 0),
	wallsFolder
)

makeWall(
	"EastWall",
	Vector3.new(WALL_THICKNESS, WALL_HEIGHT, size.Z + WALL_THICKNESS * 2),
	center * CFrame.new(halfX + WALL_THICKNESS * 0.5, size.Y * 0.5 + WALL_HEIGHT * 0.5, 0),
	wallsFolder
)

-- Backup catch floor in case physics pushes a player outside the wall volume.
makeWall(
	"SafetyFloor",
	Vector3.new(size.X + WALL_THICKNESS * 2, WALL_THICKNESS, size.Z + WALL_THICKNESS * 2),
	center * CFrame.new(0, -(size.Y * 0.5 + SAFETY_FLOOR_DROP), 0),
	wallsFolder
)
