--!strict
-- Fish Frenzy: jackpot sea monster phase-driven emerge / idle / submerge (multi-cycle).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SplashKillFishFrames"))

local MAP_ID = "main"
if MatchSplashConfig.getActiveMapId() ~= MAP_ID then
	return
end

local frames = MatchSplashConfig.getJackpotTargetEmergenceFrameIds(MAP_ID)
if not frames or #frames < 5 then
	return
end

local STEP_SEC = MatchSplashConfig.getJackpotTargetAnimStepSec(MAP_ID)
local IDLE_STEP_SEC = MatchSplashConfig.getJackpotTargetIdleAnimStepSec(MAP_ID)
local IDLE_FRAME_A = frames[4]
local IDLE_FRAME_B = frames[5]

local ACTIVE_FOLDER_NAME = "WaterSplashes"
local TARGET_SURFACE_GUI_NAME = "TargetSurfaceGui"
local COVER_IMAGE_NAME = "CoverImage"
local FISH_IMAGE_NAME = "FishImage"

local tracked: { [Model]: boolean } = {}
local framesPreloaded = false

local function ensureFramesPreloaded()
	if framesPreloaded then
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync(frames)
	end)
	framesPreloaded = true
end

local function isMonsterModel(model: Model): boolean
	return model:GetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE) == SplashKillFishFrames.TARGET_KIND_MONSTER
end

local function getMonsterCoverLabel(model: Model): ImageLabel?
	if not isMonsterModel(model) then
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

local function getMonsterFishLabel(model: Model): ImageLabel?
	local anchor = model.PrimaryPart
	if not anchor or not anchor:IsA("BasePart") then
		return nil
	end
	local surfaceGui = anchor:FindFirstChild(TARGET_SURFACE_GUI_NAME)
	if not surfaceGui or not surfaceGui:IsA("SurfaceGui") then
		return nil
	end
	local fishImage = surfaceGui:FindFirstChild(FISH_IMAGE_NAME)
	if fishImage and fishImage:IsA("ImageLabel") then
		return fishImage
	end
	return nil
end

local function getMonsterPhase(model: Model): string?
	local phase = model:GetAttribute(SplashKillFishFrames.MONSTER_PHASE_ATTRIBUTE)
	if typeof(phase) == "string" then
		return phase
	end
	return nil
end

local function runMonsterAnimation(model: Model, coverLabel: ImageLabel)
	ensureFramesPreloaded()

	local genRef = { 0 }
	local generation = 0

	local function bumpGeneration(): number
		generation += 1
		genRef[1] = generation
		return generation
	end

	local function playEmerge(activeGen: number)
		local fishLabel = getMonsterFishLabel(model)
		if fishLabel and fishLabel.Parent then
			fishLabel.ImageTransparency = 1
		end
		for _, id in frames do
			if genRef[1] ~= activeGen or not coverLabel.Parent then
				return
			end
			if getMonsterPhase(model) ~= SplashKillFishFrames.MONSTER_PHASE_EMERGE then
				return
			end
			coverLabel.Image = id
			task.wait(STEP_SEC)
		end
	end

	local function playIdle(activeGen: number)
		local showFrameB = false
		while coverLabel.Parent do
			if genRef[1] ~= activeGen then
				return
			end
			if getMonsterPhase(model) ~= SplashKillFishFrames.MONSTER_PHASE_IDLE then
				return
			end
			showFrameB = not showFrameB
			coverLabel.Image = if showFrameB then IDLE_FRAME_B else IDLE_FRAME_A
			task.wait(IDLE_STEP_SEC)
		end
	end

	local function playSubmerge(activeGen: number)
		local fishLabel = getMonsterFishLabel(model)
		for i = #frames, 1, -1 do
			if genRef[1] ~= activeGen or not coverLabel.Parent then
				return
			end
			if getMonsterPhase(model) ~= SplashKillFishFrames.MONSTER_PHASE_SUBMERGE then
				return
			end
			coverLabel.Image = frames[i]
			if fishLabel and fishLabel.Parent then
				local t = 1 - (i - 1) / math.max(#frames - 1, 1)
				fishLabel.ImageTransparency = t
			end
			task.wait(STEP_SEC)
		end
	end

	local function runPhase(phase: string)
		local activeGen = bumpGeneration()
		if phase == SplashKillFishFrames.MONSTER_PHASE_EMERGE then
			playEmerge(activeGen)
		elseif phase == SplashKillFishFrames.MONSTER_PHASE_IDLE then
			playIdle(activeGen)
		elseif phase == SplashKillFishFrames.MONSTER_PHASE_SUBMERGE then
			playSubmerge(activeGen)
		end
	end

	model:GetAttributeChangedSignal(SplashKillFishFrames.MONSTER_PHASE_ATTRIBUTE):Connect(function()
		local phase = getMonsterPhase(model)
		if phase then
			runPhase(phase)
		end
	end)

	local initialPhase = getMonsterPhase(model)
	if initialPhase then
		task.spawn(function()
			runPhase(initialPhase)
		end)
	end
end

local function hookMonsterModel(model: Model, coverLabel: ImageLabel)
	if tracked[model] then
		return
	end
	tracked[model] = true
	model.Destroying:Connect(function()
		tracked[model] = nil
	end)
	runMonsterAnimation(model, coverLabel)
end

local function waitForMonsterCoverLabel(model: Model, timeoutSec: number): ImageLabel?
	local deadline = os.clock() + timeoutSec
	while model.Parent and os.clock() < deadline do
		local coverLabel = getMonsterCoverLabel(model)
		if coverLabel then
			return coverLabel
		end
		task.wait()
	end
	return nil
end

local function waitUntilMonsterModel(model: Model, timeoutSec: number): boolean
	local deadline = os.clock() + timeoutSec
	while model.Parent and os.clock() < deadline do
		local kind = model:GetAttribute(SplashKillFishFrames.TARGET_KIND_ATTRIBUTE)
		if kind == SplashKillFishFrames.TARGET_KIND_MONSTER then
			return true
		end
		if kind ~= nil then
			return false
		end
		task.wait()
	end
	return false
end

local function tryHookModel(model: Model)
	if tracked[model] then
		return
	end

	local coverLabel = getMonsterCoverLabel(model)
	if coverLabel then
		hookMonsterModel(model, coverLabel)
		return
	end

	task.spawn(function()
		if not waitUntilMonsterModel(model, 8) then
			return
		end
		if tracked[model] or not model.Parent then
			return
		end

		local descendantConn: RBXScriptConnection? = nil
		descendantConn = model.DescendantAdded:Connect(function()
			if tracked[model] or not model.Parent then
				if descendantConn then
					descendantConn:Disconnect()
				end
				return
			end
			local label = getMonsterCoverLabel(model)
			if label then
				if descendantConn then
					descendantConn:Disconnect()
				end
				hookMonsterModel(model, label)
			end
		end)

		local label = waitForMonsterCoverLabel(model, 8)
		if descendantConn then
			descendantConn:Disconnect()
		end
		if label and not tracked[model] and model.Parent then
			hookMonsterModel(model, label)
		end
	end)
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
	ensureFramesPreloaded()
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
