--!strict
-- Fish Frenzy: swap boat cover PNG to storm art while monster event is active.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SplashKillFishFrames"))

local MAP_ID = "main"
if MatchSplashConfig.getActiveMapId() ~= MAP_ID then
	return
end

local ACTIVE_FOLDER_NAME = "WaterSplashes"
local TARGET_SURFACE_GUI_NAME = "TargetSurfaceGui"
local COVER_IMAGE_NAME = "CoverImage"
local MONSTER_EVENT_ATTRIBUTE = SplashKillFishFrames.MONSTER_EVENT_ACTIVE_ATTRIBUTE

local tracked: { [Model]: boolean } = {}

task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({
			"rbxassetid://89496466764948",
			"rbxassetid://79516053583456",
			"rbxassetid://112303721335839",
			"rbxassetid://117101987723528",
		})
	end)
end)

local function isMonsterEventActive(): boolean
	return Workspace:GetAttribute(MONSTER_EVENT_ATTRIBUTE) == true
end

local function getBoatCoverLabel(model: Model): ImageLabel?
	if model:GetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE) ~= SplashKillFishFrames.TARGET_KIND_BOAT then
		return nil
	end

	local anchor = model.PrimaryPart
	if not anchor or not anchor:IsA("BasePart") then
		local found = model:FindFirstChild("Anchor")
		if found and found:IsA("BasePart") then
			anchor = found
		else
			return nil
		end
	end

	local surfaceGui = anchor:FindFirstChild(TARGET_SURFACE_GUI_NAME)
	if not surfaceGui or not surfaceGui:IsA("SurfaceGui") then
		return nil
	end

	local coverImage = surfaceGui:FindFirstChild(COVER_IMAGE_NAME)
	if coverImage and coverImage:IsA("ImageLabel") then
		return coverImage
	end

	return nil
end

local function getBoatPatrolZSign(model: Model): number
	local swimYaw = model:GetAttribute(SplashKillFishFrames.SWIM_YAW_ATTRIBUTE)
	if typeof(swimYaw) == "number" then
		return MatchSplashConfig.getBoatPatrolZSignFromSwimYaw(swimYaw)
	end
	return 1
end

local function getCalmCoverId(model: Model, zSign: number): string
	local stored = model:GetAttribute(SplashKillFishFrames.BOAT_CALM_COVER_IMAGE_ID_ATTRIBUTE)
	if typeof(stored) == "string" and stored ~= "" then
		return stored
	end
	return MatchSplashConfig.getLegendaryTargetCoverImageIdForZSign(MAP_ID, zSign, false) or ""
end

local function applyBoatCoverForStormState(model: Model)
	local coverLabel = getBoatCoverLabel(model)
	if not coverLabel then
		return
	end

	local zSign = getBoatPatrolZSign(model)
	if isMonsterEventActive() then
		local stormId = MatchSplashConfig.getLegendaryTargetCoverImageIdForZSign(MAP_ID, zSign, true)
		if stormId then
			coverLabel.Image = stormId
		end
	else
		local calmId = getCalmCoverId(model, zSign)
		if calmId ~= "" then
			coverLabel.Image = calmId
		end
	end
end

local function applyStormStateToAllBoats()
	local folder = Workspace:FindFirstChild(ACTIVE_FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		return
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			applyBoatCoverForStormState(child)
		end
	end
end

local function tryHookModel(model: Model)
	if tracked[model] then
		return
	end
	if model:GetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE) ~= SplashKillFishFrames.TARGET_KIND_BOAT then
		return
	end

	tracked[model] = true
	model.Destroying:Connect(function()
		tracked[model] = nil
	end)

	applyBoatCoverForStormState(model)
end

local function hookActiveFolder(folder: Folder)
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			tryHookModel(child)
			applyBoatCoverForStormState(child)
		end
	end)

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			tryHookModel(child)
		end
	end
end

Workspace:GetAttributeChangedSignal(MONSTER_EVENT_ATTRIBUTE):Connect(function()
	applyStormStateToAllBoats()
end)

local existing = Workspace:FindFirstChild(ACTIVE_FOLDER_NAME)
if existing and existing:IsA("Folder") then
	hookActiveFolder(existing)
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == ACTIVE_FOLDER_NAME and child:IsA("Folder") then
		hookActiveFolder(child)
	end
end)

if isMonsterEventActive() then
	applyStormStateToAllBoats()
end
