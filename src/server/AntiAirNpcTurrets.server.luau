local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ricochet = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirRicochetProjectile") :: ModuleScript)
local ConveyorAntiAirBridge = require(script.Parent:WaitForChild("ConveyorAntiAirBridge") :: ModuleScript)

local ANTI_AIR_NAME_PREFIX = "Anti Air"
local PLAYER_TURRET_NAME = "Anti Air"
local NPC_TURRET_COUNT = 3
local CONVEYOR_ACTIVE_FOLDER = "ConveyorActiveItems"
local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"

local NPC_NAME_PREFIX = "AntiAirNPC"
local MAX_SEAT_ATTEMPTS = 25
local SEAT_RETRY_DELAY = 0.15
local AIM_INTERVAL = 1 / 30
local FIRE_INTERVAL = 0.22
local CROSSHAIR_DISTANCE = 5000

local BULLET_SPEED = 1100
local BULLET_LIFETIME_SEC = 7

local function getAllAntiAirTurrets(): { Model }
	local turrets = {}
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and string.find(child.Name, "^" .. ANTI_AIR_NAME_PREFIX) then
			table.insert(turrets, child)
		end
	end
	table.sort(turrets, function(a, b)
		return a.Name < b.Name
	end)
	return turrets
end

local function findTurretSeat(turret: Model): Seat?
	local preferred = turret:FindFirstChild("Seat", true)
	if preferred and preferred:IsA("Seat") then
		return preferred
	end
	for _, d in turret:GetDescendants() do
		if d:IsA("Seat") then
			return d
		end
	end
	return nil
end

local function createNpcCharacter(name: string): Model
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(1)
	end)
	if not ok or not description then
		description = Instance.new("HumanoidDescription")
	end

	local npc = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	npc.Name = name
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.NameDisplayDistance = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	return npc
end

local function seatNpc(npc: Model, seat: Seat): boolean
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local rootPart = npc:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		return false
	end

	for _ = 1, MAX_SEAT_ATTEMPTS do
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.CFrame = seat.CFrame * CFrame.new(0, 2.5, 0)
		seat:Sit(humanoid)
		task.wait(SEAT_RETRY_DELAY)
		if humanoid.Sit and humanoid.SeatPart == seat then
			return true
		end
	end
	return false
end

local function attachBulletTag(projectile: BasePart, sourcePart: BasePart)
	local bullet = Instance.new("Folder")
	bullet.Name = "bullet"
	local value = Instance.new("ObjectValue")
	value.Name = "Value"
	value.Value = sourcePart
	value.Parent = bullet
	bullet.Parent = projectile
end

local function getNearestConveyorItem(origin: Vector3): Vector3?
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

local function fireProjectile(gunModel: Model, aimPoint: Vector3)
	local gunFolder = gunModel:FindFirstChild("gun")
	if not gunFolder or not gunFolder:IsA("Model") then
		return
	end

	local gunpart = gunFolder:FindFirstChild("gunpart")
	if not gunpart or not gunpart:IsA("BasePart") then
		return
	end

	local effect = gunFolder:FindFirstChild("effect")
	if effect then
		local bam = effect:FindFirstChild("bam")
		if bam and bam:IsA("Sound") then
			bam:Play()
		end
	end

	local projectile = Instance.new("Part")
	projectile.Name = "AntiAirProjectile"
	projectile.Size = Vector3.new(0.4, 0.4, 9)
	local spawnPos = gunpart.Position + (gunpart.CFrame.LookVector * 5)
	projectile.CFrame = CFrame.new(spawnPos, aimPoint)
	projectile.BrickColor = BrickColor.new("Bright yellow")
	projectile.Material = Enum.Material.Neon
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.Anchored = true

	local direction = (aimPoint - projectile.Position).Unit

	attachBulletTag(projectile, gunpart)
	projectile.Parent = Workspace

	Ricochet.start(projectile, direction, Workspace, RunService, {
		speed = BULLET_SPEED,
		maxLifetimeSeconds = BULLET_LIFETIME_SEC,
		raycastExclude = { gunModel },
		onConveyorHit = function(hitPart: BasePart)
			ConveyorAntiAirBridge.notifyProjectileConveyorHit(hitPart, projectile)
		end,
	})
end

local function runTurretNpcLoop(turret: Model, seat: Seat)
	local body = turret:FindFirstChild("body")
	local gunFolder = turret:FindFirstChild("gun")
	local base = turret:FindFirstChild("base")
	if not body or not body:IsA("Model") or not gunFolder or not gunFolder:IsA("Model") or not base or not base:IsA("BasePart") then
		warn("AntiAirNpcTurrets: Missing turret parts for", turret:GetFullName())
		return
	end
	if not body.PrimaryPart or not gunFolder.PrimaryPart then
		warn("AntiAirNpcTurrets: body/gun PrimaryPart missing for", turret:GetFullName())
		return
	end

	local gunpart = gunFolder:FindFirstChild("gunpart")
	if not gunpart or not gunpart:IsA("BasePart") then
		return
	end

	local spawn = body:GetPrimaryPartCFrame()
	local lastFire = 0

	while turret.Parent and seat.Parent do
		local occ = seat.Occupant
		if not occ then
			task.wait(0.5)
			continue
		end

		local targetPos = getNearestConveyorItem(gunpart.Position)
		local aimPos = targetPos or (gunpart.Position + gunpart.CFrame.LookVector * CROSSHAIR_DISTANCE)

		if (aimPos - base.Position).Magnitude > 3 then
			local farGun = gunFolder:GetPrimaryPartCFrame() * CFrame.new(0, 0, -100000)
			local targetA = Vector3.new(farGun.X, (spawn * CFrame.new(0, 0, -100000)).Y, farGun.Z)
			gunFolder:SetPrimaryPartCFrame(CFrame.new(body:GetPrimaryPartCFrame().Position, aimPos))
			body:SetPrimaryPartCFrame(CFrame.new(spawn.Position, targetA))
		end

		local now = os.clock()
		if targetPos and now - lastFire >= FIRE_INTERVAL then
			lastFire = now
			fireProjectile(turret, aimPos)
		end

		task.wait(AIM_INTERVAL)
	end
end

local function selectNpcTurrets(allTurrets: { Model }): { Model }
	local selected = {}
	for _, turret in allTurrets do
		if turret.Name ~= PLAYER_TURRET_NAME then
			table.insert(selected, turret)
		end
		if #selected >= NPC_TURRET_COUNT then
			break
		end
	end
	return selected
end

local function start()
	task.wait(0.25)
	local turrets = getAllAntiAirTurrets()
	if #turrets == 0 then
		warn("AntiAirNpcTurrets: No Anti Air turrets found")
		return
	end

	local npcTurrets = selectNpcTurrets(turrets)
	for idx, turret in npcTurrets do
		local seat = findTurretSeat(turret)
		if not seat then
			warn("AntiAirNpcTurrets: Seat missing for", turret:GetFullName())
			continue
		end

		local npc = createNpcCharacter(NPC_NAME_PREFIX .. tostring(idx))
		npc.Parent = Workspace
		npc:PivotTo(seat.CFrame * CFrame.new(0, 4, 0))
		if not seatNpc(npc, seat) then
			npc:Destroy()
			warn("AntiAirNpcTurrets: Could not seat NPC for", turret:GetFullName())
			continue
		end

		task.spawn(runTurretNpcLoop, turret, seat)
	end
end

task.defer(start)
