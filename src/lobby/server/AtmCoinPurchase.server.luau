local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LobbyCoinPurchaseService = require(script.Parent:WaitForChild("LobbyCoinPurchaseService"))

local MODEL_NAME = "ATM"
local PROMPT_NAME = "AtmBuyCoinsPrompt"
local PROMPT_ACTION = "Buy Coins"
local PROMPT_OBJECT = "ATM"
local PROMPT_HOLD_DURATION = 0.2
local PROMPT_MAX_DISTANCE = 12

local function normalizeName(name: string): string
	return string.lower((name:gsub("%s+", "")))
end

local function findAtmTarget(): Instance?
	local wanted = normalizeName(MODEL_NAME)
	for _, inst in Workspace:GetDescendants() do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and normalizeName(inst.Name) == wanted then
			return inst
		end
	end
	return nil
end

local function getAtmPart(target: Instance): BasePart?
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
	prompt.ActionText = PROMPT_ACTION
	prompt.ObjectText = PROMPT_OBJECT
	prompt.HoldDuration = PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = PROMPT_MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = part
	return prompt
end

local atmTarget = findAtmTarget()
if not atmTarget then
	warn("[Lobby] Could not find ATM model (Model or Part).")
	return
end

local atmPart = getAtmPart(atmTarget)
if not atmPart then
	warn("[Lobby] ATM has no BasePart to attach prompt to.")
	return
end

getOrCreatePrompt(atmPart).Triggered:Connect(function(player: Player)
	LobbyCoinPurchaseService.requestPurchase(player)
end)
