--!strict
-- Fish Frenzy: continuous water ripple splash frame loop on billboard PNG (ripple → mid → full → mid → ripple).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))

if MatchSplashConfig.getActiveMapId() ~= "main" then
	return
end

local frames = MatchSplashConfig.getSplashFrameIds("main")
if not frames then
	return
end

local ACTIVE_FOLDER_NAME = "WaterSplashes"
local STEP_SEC = 0.18

local tracked: { [ImageLabel]: boolean } = {}

local function buildPingPongSequence(source: { string }): { string }
	if #source < 2 then
		return source
	end
	local seq: { string } = {}
	for i = 1, #source do
		table.insert(seq, source[i])
	end
	for i = #source - 1, 2, -1 do
		table.insert(seq, source[i])
	end
	return seq
end

local RIPPLE_SEQUENCE = buildPingPongSequence(frames)

local function getSplashImageLabel(model: Model): ImageLabel?
	local anchor = model.PrimaryPart
	if not anchor or not anchor:IsA("BasePart") then
		local found = model:FindFirstChild("Anchor")
		if found and found:IsA("BasePart") then
			anchor = found
		else
			return nil
		end
	end

	local splashBillboard = anchor:FindFirstChild("SplashBillboard")
	if not splashBillboard or not splashBillboard:IsA("BillboardGui") then
		return nil
	end

	local splashImage = splashBillboard:FindFirstChild("SplashImage")
	if splashImage and splashImage:IsA("ImageLabel") then
		return splashImage
	end

	return nil
end

local function playRippleLoop(label: ImageLabel)
	if tracked[label] then
		return
	end
	tracked[label] = true

	label.Destroying:Connect(function()
		tracked[label] = nil
	end)

	task.spawn(function()
		while label.Parent do
			for _, id in RIPPLE_SEQUENCE do
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
	local imageLabel = getSplashImageLabel(model)
	if not imageLabel then
		return
	end
	playRippleLoop(imageLabel)
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
