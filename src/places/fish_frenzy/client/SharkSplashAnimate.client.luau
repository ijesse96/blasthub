--!strict
-- Fish Frenzy: 4-frame shark swim loop on rare SurfaceGui targets.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SplashKillFishFrames"))

if MatchSplashConfig.getActiveMapId() ~= "main" then
	return
end

local frames = MatchSplashConfig.getRareTargetFrameIds("main")
if not frames or #frames == 0 then
	return
end

local ACTIVE_FOLDER_NAME = "WaterSplashes"
local TARGET_SURFACE_GUI_NAME = "TargetSurfaceGui"
local COVER_IMAGE_NAME = "CoverImage"
local STEP_SEC = 0.18

local tracked: { [ImageLabel]: boolean } = {}

local function getSharkCoverLabel(model: Model): ImageLabel?
	if model:GetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE) ~= SplashKillFishFrames.TARGET_KIND_SHARK then
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

local function playSharkLoop(label: ImageLabel)
	if tracked[label] then
		return
	end
	tracked[label] = true

	label.Destroying:Connect(function()
		tracked[label] = nil
	end)

	task.spawn(function()
		while label.Parent do
			for _, id in frames do
				if not label.Parent then
					break
				end
				label.Image = id
				task.wait(STEP_SEC)
			end
		end
	end)
end

local function tryHookModel(model: Model)
	local imageLabel = getSharkCoverLabel(model)
	if not imageLabel then
		return
	end
	playSharkLoop(imageLabel)
end

local function hookActiveFolder(folder: Folder)
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			tryHookModel(child)
		end
	end)

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			tryHookModel(child)
		end
	end
end

task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync(frames)
	end)
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
