local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local DailySpinStore = require(shared:WaitForChild("DailySpinStore"))
local Money = require(shared:WaitForChild("Money"))

local REMOTES_NAME = "LobbyRemotes"
local SPIN_RESULT_NAME = "DailySpinResult"

local MODEL_NAME = "daily spin"
local PROMPT_NAME = "DailySpinPrompt"
local PROMPT_ACTION = "Daily Spin"
local PROMPT_OBJECT = "Wheel"
local PROMPT_HOLD_DURATION = 0.2
local PROMPT_MAX_DISTANCE = 12

local DEBOUNCE_SECONDS = 1.5
local lastTriggerAtByUserId: { [number]: number } = {}

local function normalizeName(name: string): string
	return string.lower((name:gsub("%s+", "")))
end

local function findSpinTarget(): Instance?
	local wanted = normalizeName(MODEL_NAME)
	for _, inst in Workspace:GetDescendants() do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and normalizeName(inst.Name) == wanted then
			return inst
		end
	end
	return nil
end

local function getSpinPart(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	end

	local model = target :: Model
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function getOrCreateRemotesFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = REMOTES_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureSpinResultRemote(): RemoteEvent
	local folder = getOrCreateRemotesFolder()
	local existing = folder:FindFirstChild(SPIN_RESULT_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = SPIN_RESULT_NAME
	remote.Parent = folder
	return remote
end

local function fireSpinResult(player: Player, payload: { [string]: unknown })
	ensureSpinResultRemote():FireClient(player, payload)
end

local function rollAmount(): number
	return math.random(1, 6) * 25
end

local function getOrCreatePrompt(part: BasePart): ProximityPrompt
	local existing = part:FindFirstChild(PROMPT_NAME)
	if existing and existing:IsA("ProximityPrompt") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = PROMPT_ACTION
	prompt.ObjectText = PROMPT_OBJECT
	prompt.HoldDuration = PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = PROMPT_MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = part
	return prompt
end

local spinTarget = findSpinTarget()
if not spinTarget then
	warn("[Lobby] Could not find Daily Spin model (Model or Part).")
	return
end

local spinPart = getSpinPart(spinTarget)
if not spinPart then
	warn("[Lobby] Daily Spin has no BasePart to attach prompt to.")
	return
end

getOrCreatePrompt(spinPart).Triggered:Connect(function(player: Player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local userId = player.UserId
	local now = os.clock()
	if (lastTriggerAtByUserId[userId] or 0) + DEBOUNCE_SECONDS > now then
		return
	end
	lastTriggerAtByUserId[userId] = now

	local claimedOk, alreadySpun, storeFailed = DailySpinStore.tryClaimTodayAsync(userId)

	if storeFailed then
		fireSpinResult(player, {
			ok = false,
			message = "Could not verify daily spin. Try again in a moment.",
		})
		return
	end

	if alreadySpun then
		fireSpinResult(player, {
			ok = false,
			alreadySpun = true,
			message = "You already spun today. Come back tomorrow!",
		})
		return
	end

	if not claimedOk then
		fireSpinResult(player, {
			ok = false,
			message = "Could not complete spin. Try again.",
		})
		return
	end

	local amount = rollAmount()
	Money.addCash(player, amount)

	fireSpinResult(player, {
		ok = true,
		amount = amount,
		message = string.format("You won $%d!", amount),
	})
end)
