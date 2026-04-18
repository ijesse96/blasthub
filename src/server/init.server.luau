local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local VEHICLE_MODEL_NAME = "Anti Air"
local MAX_SEAT_ATTEMPTS = 25
local SEAT_RETRY_DELAY = 0.12
local VEHICLE_WAIT_SECONDS = 25

local function isPlayerAntiAirModel(instance: Instance?): boolean
	return instance ~= nil and instance:IsA("Model") and string.lower(instance.Name) == "anti air"
end

local function findVehicleModel(): Model?
	local direct = Workspace:FindFirstChild(VEHICLE_MODEL_NAME)
	if isPlayerAntiAirModel(direct) then
		return direct
	end

	for _, child in Workspace:GetChildren() do
		if isPlayerAntiAirModel(child) then
			return child
		end
	end

	for _, inst in Workspace:GetDescendants() do
		if isPlayerAntiAirModel(inst) then
			return inst
		end
	end

	return nil
end

local function waitForVehicleModel(): Model?
	local deadline = os.clock() + VEHICLE_WAIT_SECONDS
	local vehicle = findVehicleModel()
	while not vehicle and os.clock() < deadline do
		task.wait(0.15)
		vehicle = findVehicleModel()
	end
	return vehicle
end

local function findVehicleSeat(): BaseSeat?
	local vehicle = waitForVehicleModel()
	if not vehicle then
		warn("[SpawnSeat] Anti Air model not found in Workspace (direct child, any casing, or nested).")
		return nil
	end

	local preferred = vehicle:FindFirstChild("Seat", true)
	if preferred and (preferred:IsA("Seat") or preferred:IsA("VehicleSeat")) then
		return preferred
	end

	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			return descendant
		end
	end

	warn("[SpawnSeat] Anti Air model has no Seat or VehicleSeat:", vehicle:GetFullName())
	return nil
end

local function isSeatedOnPlayerTurret(humanoid: Humanoid): boolean
	local seat = humanoid.SeatPart
	if not seat or not (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
		return false
	end
	local current: Instance? = seat
	while current do
		if isPlayerAntiAirModel(current) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function seatCharacter(character: Model)
	local humanoidInst = character:WaitForChild("Humanoid", 12)
	local rootPart = character:WaitForChild("HumanoidRootPart", 12)
	if not humanoidInst or not humanoidInst:IsA("Humanoid") or not rootPart or not rootPart:IsA("BasePart") then
		return
	end
	local humanoid = humanoidInst :: Humanoid

	local seat = findVehicleSeat()
	if not seat then
		return
	end

	for _ = 1, MAX_SEAT_ATTEMPTS do
		if humanoid.SeatPart == seat then
			return
		end

		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.CFrame = seat.CFrame * CFrame.new(0, 2.5, 0)
		seat:Sit(humanoid)
		task.wait(SEAT_RETRY_DELAY)
	end

	warn("[SpawnSeat] Could not seat player on turret seat after", MAX_SEAT_ATTEMPTS, "attempts")
end

local function onCharacterAdded(character: Model)
	task.wait(0.35)
	seatCharacter(character)

	local function retryIfNeeded()
		if not character.Parent then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		if isSeatedOnPlayerTurret(humanoid) then
			return
		end
		seatCharacter(character)
	end

	task.delay(1.25, retryIfNeeded)
	task.delay(3.5, retryIfNeeded)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)

	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
