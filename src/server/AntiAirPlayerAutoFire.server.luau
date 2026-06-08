--!strict
-- Server-side auto-aim and auto-fire for player-seated Anti Air turrets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoFireConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirAutoFireConfig"))
local AutoTarget = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AntiAirAutoTarget"))
local Money = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Money"))
local FireLib = require(script.Parent:WaitForChild("AntiAirPlayerFireLib"))
local MatchRoundBridge = require(script.Parent:WaitForChild("MatchRoundBridge"))

local CROSSHAIR_DISTANCE = 5000

local lastFireByUserId: { [number]: number } = {}

local function isAutoFireEnabled(player: Player): boolean
	if player:GetAttribute(AutoFireConfig.AUTO_FIRE_PLAYER_ATTR) == false then
		return false
	end
	return AutoFireConfig.defaultAutoFireEnabled
end

local function computeAimLook(from: Vector3, to: Vector3): Vector3?
	local offset = to - from
	if offset.Magnitude < 1e-4 then
		return nil
	end
	local look = offset.Unit
	if math.abs(look.Y) > FireLib.MAX_AIM_DIRECTION_Y then
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude < 1e-4 then
			return nil
		end
		look = flat.Unit
	end
	return look
end

local function aimTurretToward(turret: Model, aimPos: Vector3)
	local body = turret:FindFirstChild("body")
	local gunFolder = turret:FindFirstChild("gun")
	local base = turret:FindFirstChild("base")
	if not body or not body:IsA("Model") or not gunFolder or not gunFolder:IsA("Model") or not base or not base:IsA("BasePart") then
		return
	end
	if not body.PrimaryPart or not gunFolder.PrimaryPart then
		return
	end
	if (aimPos - base.Position).Magnitude <= 3 then
		return
	end

	local spawn = body:GetPrimaryPartCFrame()
	local farGun = gunFolder:GetPrimaryPartCFrame() * CFrame.new(0, 0, -100000)
	local targetA = Vector3.new(farGun.X, (spawn * CFrame.new(0, 0, -100000)).Y, farGun.Z)
	gunFolder:SetPrimaryPartCFrame(CFrame.new(body:GetPrimaryPartCFrame().Position, aimPos))
	body:SetPrimaryPartCFrame(CFrame.new(spawn.Position, targetA))
end

local function tryAutoFireForPlayer(player: Player, now: number)
	if not isAutoFireEnabled(player) then
		return
	end
	if not MatchRoundBridge.allowShooting(player) then
		return
	end
	if FireLib.playerHasLiveProjectile(player.UserId) then
		return
	end

	local cash = Money.setupPlayer(player)
	if cash.Value < FireLib.SHOT_COST_AMOUNT then
		return
	end

	local turret = FireLib.getPlayerTurretModel(player)
	if not turret then
		return
	end

	local gunFolder = turret:FindFirstChild("gun")
	if not gunFolder or not gunFolder:IsA("Model") then
		return
	end
	local gunpart = gunFolder:FindFirstChild("gunpart")
	if not gunpart or not gunpart:IsA("BasePart") then
		return
	end

	local target = AutoTarget.pickNearestTarget(gunpart.Position)
	if not target then
		return
	end

	local aimPos = target.worldPoint
	local fallbackAim = gunpart.Position + gunpart.CFrame.LookVector * CROSSHAIR_DISTANCE
	aimTurretToward(turret, aimPos)

	local aimLook = computeAimLook(gunpart.Position, aimPos)
	if not aimLook then
		aimLook = computeAimLook(gunpart.Position, fallbackAim)
	end
	if not aimLook then
		return
	end

	local lastFire = lastFireByUserId[player.UserId] or 0
	if now - lastFire < AutoFireConfig.FIRE_INTERVAL_SEC then
		return
	end
	lastFireByUserId[player.UserId] = now

	FireLib.fireForPlayer(player, nil, aimLook, nil, target.splashModel)
end

local function onPlayerAdded(player: Player)
	if player:GetAttribute(AutoFireConfig.AUTO_FIRE_PLAYER_ATTR) == nil then
		player:SetAttribute(AutoFireConfig.AUTO_FIRE_PLAYER_ATTR, AutoFireConfig.defaultAutoFireEnabled)
	end
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player: Player)
	lastFireByUserId[player.UserId] = nil
end)

task.spawn(function()
	while true do
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			tryAutoFireForPlayer(player, now)
		end
		task.wait(AutoFireConfig.AIM_INTERVAL_SEC)
	end
end)
