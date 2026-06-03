--!strict
-- Blink animation for the King of the Jungle splash PNG billboard (1→2→3→3→2→1).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))

if MatchSplashConfig.getActiveMapId() ~= "king_of_the_jungle" then
	return
end

local ACTIVE_FOLDER_NAME = "WaterSplashes"

local FRAME_1 = "rbxassetid://110419001189017"
local FRAME_2 = "rbxassetid://97928223869382"
local FRAME_3 = "rbxassetid://125758898438481"

local BLINK_SEQUENCE = { FRAME_1, FRAME_2, FRAME_3, FRAME_3, FRAME_2, FRAME_1 }

-- Sleepier feel: less frequent blinks, slower lids, linger on closed.
local IDLE_MIN_SEC = 2.0
local IDLE_MAX_SEC = 3.0
local STEP_SEC_MIN = 0.07
local STEP_SEC_MAX = 0.11
local STEP_HOLD_MULTIPLIER_BY_FRAME: { [string]: number } = {
	[FRAME_1] = 1.0,
	[FRAME_2] = 1.25,
	[FRAME_3] = 2.4,
}

local tracked: { [ImageLabel]: boolean } = {}

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

local function playBlinkLoop(label: ImageLabel)
	if tracked[label] then
		return
	end
	tracked[label] = true

	label.Destroying:Connect(function()
		tracked[label] = nil
	end)

	task.spawn(function()
		while label.Parent do
			task.wait(IDLE_MIN_SEC + math.random() * (IDLE_MAX_SEC - IDLE_MIN_SEC))
			if not label.Parent then
				break
			end

			for _, id in BLINK_SEQUENCE do
				if not label.Parent then
					break
				end
				label.Image = id
				local base = STEP_SEC_MIN + math.random() * (STEP_SEC_MAX - STEP_SEC_MIN)
				local mul = STEP_HOLD_MULTIPLIER_BY_FRAME[id] or 1.0
				task.wait(base * mul)
			end
		end
	end)
end

local function tryHookModel(model: Model)
	local label = getSplashImageLabel(model)
	if not label then
		return
	end
	playBlinkLoop(label)
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
		ContentProvider:PreloadAsync({ FRAME_1, FRAME_2, FRAME_3 })
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

