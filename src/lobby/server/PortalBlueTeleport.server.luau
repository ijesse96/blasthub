local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local PlaceIds = require(ReplicatedStorage.Shared:WaitForChild("PlaceIds"))

local PORTAL_NAME = "portal blue"
local PROMPT_NAME = "EnterMainGamePrompt"
local PROMPT_TEXT = "Enter Game"
local PROMPT_OBJECT_TEXT = "Portal"
local PROMPT_HOLD_DURATION = 0.2
local PROMPT_MAX_DISTANCE = 12

local TELEPORT_COOLDOWN = 3
local TELEPORT_DATA = "from_lobby_portal_blue"

local lastRequestAtByUserId: { [number]: number } = {}

local function normalizeName(name: string): string
	return string.lower((name:gsub("%s+", "")))
end

local function findPortalTarget(): Instance?
	local wanted = normalizeName(PORTAL_NAME)
	for _, inst in Workspace:GetDescendants() do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and normalizeName(inst.Name) == wanted then
			return inst
		end
	end
	return nil
end

local function getPortalPart(target: Instance): BasePart?
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
	prompt.ActionText = PROMPT_TEXT
	prompt.ObjectText = PROMPT_OBJECT_TEXT
	prompt.HoldDuration = PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = PROMPT_MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = part
	return prompt
end

local function teleportPlayerToMain(player: Player)
	if PlaceIds.MainGame == 0 then
		warn("[Lobby] Set PlaceIds.MainGame in src/shared/PlaceIds.luau before teleporting.")
		return
	end

	local now = os.clock()
	local last = lastRequestAtByUserId[player.UserId]
	if last and now - last < TELEPORT_COOLDOWN then
		return
	end
	lastRequestAtByUserId[player.UserId] = now

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(TELEPORT_DATA)

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(PlaceIds.MainGame, { player }, options)
	end)

	if not ok then
		warn(`[Lobby] Teleport failed for {player.Name}: {err}`)
	end
end

local portalTarget = findPortalTarget()
if not portalTarget then
	warn("[Lobby] Could not find portal target named 'portal blue' (Model or Part).")
	return
end

local portalPart = getPortalPart(portalTarget)
if not portalPart then
	warn("[Lobby] 'portal blue' has no BasePart to attach prompt to.")
	return
end

getOrCreatePrompt(portalPart).Triggered:Connect(function(player: Player)
	teleportPlayerToMain(player)
end)
