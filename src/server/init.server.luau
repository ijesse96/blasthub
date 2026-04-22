local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local VEHICLE_MODEL_NAME = "Anti Air"
local MAX_SEAT_ATTEMPTS = 25
local SEAT_RETRY_DELAY = 0.12
local VEHICLE_WAIT_SECONDS = 25

local function isPlayerAntiAirModel(instance: Instance?): boolean
	return instance ~= nil and instance:IsA("Model") and string.lower(instance.Name) == string.lower(VEHICLE_MODEL_NAME)
end

local function getAllAntiAirModels(): { Model }
	local list: { Model } = {}
	for _, inst in Workspace:GetDescendants() do
		if isPlayerAntiAirModel(inst) then
			table.insert(list, inst :: Model)
		end
	end

	table.sort(list, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)

	return list
end

local function waitUntilAnyAntiAirExists(): boolean
	local deadline = os.clock() + VEHICLE_WAIT_SECONDS
	while os.clock() < deadline do
		if #getAllAntiAirModels() > 0 then
			return true
		end
		task.wait(0.15)
	end
	return false
end

local function findSeatOnVehicle(vehicle: Model): BaseSeat?
	local preferred = vehicle:FindFirstChild("Seat", true)
	if preferred and (preferred:IsA("Seat") or preferred:IsA("VehicleSeat")) then
		return preferred
	end

	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			return descendant
		end
	end

	return nil
end

local function findFreeVehicleSeat(): BaseSeat?
	if not waitUntilAnyAntiAirExists() then
		warn("[SpawnSeat] Anti Air model not found in Workspace (direct child, any casing, or nested).")
		return nil
	end

	for _, vehicle in getAllAntiAirModels() do
		local seat = findSeatOnVehicle(vehicle)
		if seat and seat.Occupant == nil then
			return seat
		end
	end

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

	for _ = 1, MAX_SEAT_ATTEMPTS do
		if isSeatedOnPlayerTurret(humanoid) then
			return
		end

		local seat = findFreeVehicleSeat()
		if not seat then
			task.wait(SEAT_RETRY_DELAY)
			continue
		end

		if seat.Occupant ~= nil and seat.Occupant ~= humanoid then
			task.wait(SEAT_RETRY_DELAY)
			continue
		end

		if humanoid.SeatPart == seat then
			return
		end

		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.CFrame = seat.CFrame * CFrame.new(0, 2.5, 0)
		seat:Sit(humanoid)
		task.wait(SEAT_RETRY_DELAY)
	end

	warn(
		"[SpawnSeat] Could not seat player on turret seat after",
		MAX_SEAT_ATTEMPTS,
		"attempts (no empty Anti Air seat, or Sit failed)."
	)
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
