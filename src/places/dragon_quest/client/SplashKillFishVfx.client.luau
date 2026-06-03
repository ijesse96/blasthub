--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RewardUiColors = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RewardUiColors"))

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local CashFlyVfxUtil = require(playerScripts:WaitForChild("ArenaClient"):WaitForChild("CashFlyVfxUtil"))
local SplashFishCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SplashFishCatalog"))
local SplashKillFishFrames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SplashKillFishFrames"))

type FishTier = SplashFishCatalog.FishTier

type TierAccentColors = {
	stroke: Color3,
	glow: Color3,
	glowBright: Color3,
}

local SPLASH_KILL_FISH_VFX_REMOTE_NAME = "SplashKillFishVfx"
local SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME = "SplashKillFishPreload"
local VFX_PHASE_PREPARE = "prepare"
local VFX_PHASE_REVEAL = "reveal"
local DISPLAY_SEC = 1.4
local IMAGE_PX = 100
local PANEL_BG_COLOR = Color3.fromRGB(0, 0, 0)

local COMMON_ACCENT: TierAccentColors = {
	stroke = RewardUiColors.FISH_COMMON_GREEN,
	glow = RewardUiColors.FISH_COMMON_GREEN,
	glowBright = RewardUiColors.FISH_COMMON_GREEN_BRIGHT,
}

local RARE_ACCENT: TierAccentColors = {
	stroke = RewardUiColors.FISH_RARE_BLUE,
	glow = RewardUiColors.FISH_RARE_BLUE,
	glowBright = RewardUiColors.FISH_RARE_BLUE_BRIGHT,
}

local LEGENDARY_ACCENT: TierAccentColors = {
	stroke = RewardUiColors.FISH_LEGENDARY_PURPLE,
	glow = RewardUiColors.FISH_LEGENDARY_PURPLE,
	glowBright = RewardUiColors.FISH_LEGENDARY_PURPLE_BRIGHT,
}

local JACKPOT_ACCENT: TierAccentColors = {
	stroke = RewardUiColors.FISH_JACKPOT_GOLD,
	glow = RewardUiColors.FISH_JACKPOT_GOLD,
	glowBright = RewardUiColors.FISH_JACKPOT_GOLD_BRIGHT,
}

local GLOW_OUTER_SCALE = 1.35
local GLOW_OUTER_BASE_TRANSPARENCY = 0.80
local REVEAL_SETTLE_FRAME_COUNT = 4
local PANEL_STROKE_THICKNESS = 11
local PANEL_STROKE_TRANSPARENCY = 0.18
local POP_IN_SEC = 0.3
local SPARKLE_SPEED = 6
local CASH_POP_RISE_PX = 28
local CASH_POP_DURATION = 1.5
local CASH_POP_FADE_START_ALPHA = 0.42
local CASH_POP_STROKE = Color3.fromRGB(14, 72, 36)
local JOIN_WARMUP_BATCH_PAUSE_EVERY = 2
local PREPARE_LOAD_TIMEOUT_SEC = 10
local WAVE_WIPE_IMAGE_ID = "rbxassetid://93697217392256"
local SAND_COVER_IMAGE_ID = "rbxassetid://122141499309246"
local WAVE_WIPE_DURATION_SEC = 2.5
local REVEAL_PAUSE_BEFORE_WIPE_SEC = 1
local WAVE_WIPE_WIDTH_SCALE = 2.2
local WAVE_WIPE_HEIGHT_SCALE = 2.0
-- Lower starting Y so more wave is visible on panel during the pre-wipe pause.
local WAVE_WIPE_START_Y_SCALE = 0.15
local WAVE_WIPE_END_Y_SCALE = 1.55
local WAVE_DRIFT_X_START_SCALE = 0.34
local WAVE_DRIFT_X_END_SCALE = 0.66
-- One left-right leg of the ping-pong drift (repeats until reveal ends).
local WAVE_DRIFT_LEG_DURATION_SEC = 0.5
local PANEL_CORNER_RADIUS = UDim.new(0, 6)

-- Built at center during reel (gui disabled); revealed after retract.
local CENTER_ROOT_POSITION = UDim2.fromScale(0.5, 0.5)

local playerGui = player:WaitForChild("PlayerGui")

type PendingCatch = {
	gui: ScreenGui,
	root: Frame,
	rootCanvas: CanvasGroup,
	rootScale: UIScale,
	glowOuter: Frame,
	fishPanel: Frame,
	fishImage: ImageLabel,
	amount: number,
}

type RevealJob = {
	imageId: string,
	amount: number,
	showWave: any,
}

-- One celebration on screen at a time; additional reveals wait in line.
local revealQueue: { RevealJob } = {}
local revealDrainRunning = false
local activeCatch: PendingCatch? = nil
-- Prepare only warms assets; full overlay is built when a reveal job runs.
local preparedAmountByImageId: { [string]: number } = {}
-- Session-only until FishCollectionStore; then server drives showWave on reveal.
local seenFishImageIdsSession: { [string]: boolean } = {}

local warmedLabelCache: { [string]: ImageLabel } = {}
local warmingImageIds: { [string]: boolean } = {}

local warmupGui = Instance.new("ScreenGui")
warmupGui.Name = "SplashKillFishWarmup"
warmupGui.ResetOnSpawn = false
warmupGui.IgnoreGuiInset = true
warmupGui.DisplayOrder = -100
warmupGui.Enabled = true
warmupGui.Parent = playerGui

local function waitForImageLabelLoaded(label: ImageLabel, timeoutSec: number): boolean
	if label.IsLoaded then
		return true
	end
	local deadline = os.clock() + timeoutSec
	while os.clock() < deadline do
		if label.IsLoaded then
			return true
		end
		if not label.Parent then
			return false
		end
		RunService.Heartbeat:Wait()
	end
	return label.IsLoaded
end

local function waitFrames(frameCount: number)
	for _ = 1, frameCount do
		RunService.Heartbeat:Wait()
	end
end

local function cacheKeyForImageId(imageId: string): string
	return string.gsub(imageId, "[^%w]", "_")
end

local function getOrCreateWarmLabel(imageId: string): ImageLabel
	local existing = warmedLabelCache[imageId]
	if existing then
		return existing
	end

	local slotIndex = 0
	for _ in warmedLabelCache do
		slotIndex += 1
	end

	local host = Instance.new("Frame")
	host.Name = "Slot_" .. cacheKeyForImageId(imageId)
	host.BackgroundTransparency = 1
	host.Size = UDim2.fromOffset(IMAGE_PX, IMAGE_PX)
	host.Position = UDim2.fromOffset(-IMAGE_PX * 4, -IMAGE_PX * 4 - slotIndex * (IMAGE_PX + 4))
	host.Parent = warmupGui

	local label = Instance.new("ImageLabel")
	label.Name = "Warm"
	label.BackgroundTransparency = 1
	label.ImageTransparency = 0
	label.Size = UDim2.fromScale(1, 1)
	label.ScaleType = Enum.ScaleType.Fit
	label.Parent = host

	warmedLabelCache[imageId] = label
	return label
end

local function warmImageIdInPoolAsync(imageId: string)
	if warmingImageIds[imageId] then
		return
	end
	warmingImageIds[imageId] = true

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ imageId })
		end)

		local label = getOrCreateWarmLabel(imageId)
		label.Image = imageId
		waitForImageLabelLoaded(label, PREPARE_LOAD_TIMEOUT_SEC)
		warmingImageIds[imageId] = nil
	end)
end

local function createFishImageLabel(imageId: string): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Image = imageId
	label.BackgroundTransparency = 1
	label.ImageTransparency = 0
	label.ScaleType = Enum.ScaleType.Fit
	SplashKillFishFrames.applyFullImageToLabel(label)
	return label
end

local function isFirstDiscoverySession(imageId: string): boolean
	return not seenFishImageIdsSession[imageId]
end

local function markFishDiscoveredSession(imageId: string)
	seenFishImageIdsSession[imageId] = true
end

local function shouldPlayWaveWipe(imageId: string, serverFlag: any): boolean
	if serverFlag == true then
		return true
	end
	if serverFlag == false then
		return false
	end
	return isFirstDiscoverySession(imageId)
end

local function playWaveWipeInsidePanel(fishImage: ImageLabel, panel: Frame): ()
	if not panel.Parent or not fishImage.Parent then
		fishImage.ImageTransparency = 0
		return
	end

	-- Keep fish hidden until sand is covering the panel (avoids a one-frame flash on reveal).
	fishImage.ImageTransparency = 1

	local revealClip = Instance.new("Frame")
	revealClip.Name = "RevealClip"
	revealClip.BackgroundTransparency = 1
	revealClip.BorderSizePixel = 0
	revealClip.ClipsDescendants = true
	revealClip.Size = UDim2.fromScale(1, 1)
	revealClip.ZIndex = 3
	revealClip.Parent = panel

	-- Sand + wave share one parent so they move at identical speed (same tween as the old wave sweep).
	local revealGroup = Instance.new("Frame")
	revealGroup.Name = "RevealGroup"
	revealGroup.BackgroundTransparency = 1
	revealGroup.BorderSizePixel = 0
	revealGroup.AnchorPoint = Vector2.new(0.5, 0)
	revealGroup.Position = UDim2.fromScale(0.5, WAVE_WIPE_START_Y_SCALE)
	revealGroup.Size = UDim2.fromOffset(IMAGE_PX, IMAGE_PX)
	revealGroup.ZIndex = 1
	revealGroup.Parent = revealClip

	local sand = Instance.new("ImageLabel")
	sand.Name = "SandCover"
	sand.BackgroundTransparency = 1
	sand.BorderSizePixel = 0
	sand.Image = SAND_COVER_IMAGE_ID
	sand.ScaleType = Enum.ScaleType.Crop
	sand.AnchorPoint = Vector2.new(0.5, 0)
	sand.Position = UDim2.fromScale(0.5, 0)
	sand.Size = UDim2.fromOffset(IMAGE_PX, IMAGE_PX)
	sand.ZIndex = 1
	sand.Parent = revealGroup

	local wave = Instance.new("ImageLabel")
	wave.Name = "Wave"
	wave.BackgroundTransparency = 1
	wave.BorderSizePixel = 0
	wave.Image = WAVE_WIPE_IMAGE_ID
	wave.ScaleType = Enum.ScaleType.Fit
	wave.AnchorPoint = Vector2.new(0.5, 0.5)
	wave.Size = UDim2.fromOffset(
		math.ceil(IMAGE_PX * WAVE_WIPE_WIDTH_SCALE),
		math.ceil(IMAGE_PX * WAVE_WIPE_HEIGHT_SCALE)
	)
	wave.Position = UDim2.fromScale(WAVE_DRIFT_X_START_SCALE, 0)
	wave.ZIndex = 2
	wave.Parent = revealGroup

	waitForImageLabelLoaded(sand, PREPARE_LOAD_TIMEOUT_SEC)
	waitForImageLabelLoaded(wave, PREPARE_LOAD_TIMEOUT_SEC)
	waitFrames(1)

	fishImage.ImageTransparency = 0

	local driftLegInfo = TweenInfo.new(
		WAVE_DRIFT_LEG_DURATION_SEC,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.InOut,
		-1,
		true
	)
	local driftTween = TweenService:Create(wave, driftLegInfo, {
		Position = UDim2.fromScale(WAVE_DRIFT_X_END_SCALE, 0),
	})
	driftTween:Play()

	task.wait(REVEAL_PAUSE_BEFORE_WIPE_SEC)

	local moveInfo = TweenInfo.new(WAVE_WIPE_DURATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local moveTween = TweenService:Create(revealGroup, moveInfo, { Position = UDim2.fromScale(0.5, WAVE_WIPE_END_Y_SCALE) })
	moveTween:Play()
	moveTween.Completed:Wait()

	if revealClip.Parent then
		revealClip:Destroy()
	end
end

local function getAccentColorsForTier(tier: FishTier): TierAccentColors
	if tier == "jackpot" then
		return JACKPOT_ACCENT
	end
	if tier == "legendary" then
		return LEGENDARY_ACCENT
	end
	if tier == "rare" then
		return RARE_ACCENT
	end
	return COMMON_ACCENT
end

local function resolveTierForImageId(imageId: string): FishTier
	return SplashKillFishFrames.inferTierForImageId(imageId)
end

local function destroyActiveCatch()
	local pending = activeCatch
	if pending then
		if pending.gui.Parent then
			pending.gui:Destroy()
		end
		activeCatch = nil
	end
end

local function buildCatchOverlay(imageId: string, amount: number, tier: FishTier): PendingCatch
	local accent = getAccentColorsForTier(tier)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SplashKillFishOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 85
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = playerGui

	local outerPx = math.ceil(IMAGE_PX * GLOW_OUTER_SCALE)
	local root = Instance.new("Frame")
	root.Name = "CatchRoot"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = CENTER_ROOT_POSITION
	root.Size = UDim2.fromOffset(outerPx, outerPx)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui

	local rootCanvas = Instance.new("CanvasGroup")
	rootCanvas.Name = "CatchCanvas"
	rootCanvas.GroupTransparency = 1
	rootCanvas.Size = UDim2.fromScale(1, 1)
	rootCanvas.BackgroundTransparency = 1
	rootCanvas.Parent = root

	local rootScale = Instance.new("UIScale")
	rootScale.Scale = 0.88
	rootScale.Parent = rootCanvas

	local glowOuter = Instance.new("Frame")
	glowOuter.Name = "GlowOuter"
	glowOuter.AnchorPoint = Vector2.new(0.5, 0.5)
	glowOuter.Position = UDim2.fromScale(0.5, 0.5)
	glowOuter.Size = UDim2.fromOffset(outerPx, outerPx)
	glowOuter.BackgroundColor3 = accent.glow
	glowOuter.BackgroundTransparency = GLOW_OUTER_BASE_TRANSPARENCY
	glowOuter.BorderSizePixel = 0
	glowOuter.ZIndex = 0
	glowOuter.Parent = rootCanvas

	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(0, 6)
	outerCorner.Parent = glowOuter

	local panel = Instance.new("Frame")
	panel.Name = "FishPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(IMAGE_PX, IMAGE_PX)
	panel.BackgroundColor3 = PANEL_BG_COLOR
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.ZIndex = 2
	panel.Parent = rootCanvas

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = PANEL_CORNER_RADIUS
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Name = "RewardStroke"
	panelStroke.Color = accent.stroke
	panelStroke.Thickness = PANEL_STROKE_THICKNESS
	panelStroke.Transparency = PANEL_STROKE_TRANSPARENCY
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	panelStroke.LineJoinMode = Enum.LineJoinMode.Round
	panelStroke.Parent = panel

	local img = createFishImageLabel(imageId)
	img.Name = "Fish"
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 1
	img.Parent = panel

	-- Invisible at center so Roblox decodes at final layout; revealed after retract.
	waitForImageLabelLoaded(img, PREPARE_LOAD_TIMEOUT_SEC)

	return {
		gui = gui,
		root = root,
		rootCanvas = rootCanvas,
		rootScale = rootScale,
		glowOuter = glowOuter,
		fishPanel = panel,
		fishImage = img,
		amount = amount,
	}
end

local function runSparkleLoop(gui: ScreenGui, glowOuter: Frame, durationSec: number, accent: TierAccentColors)
	local deadline = os.clock() + durationSec
	task.spawn(function()
		while os.clock() < deadline and gui.Parent and glowOuter.Parent do
			local t = os.clock() * SPARKLE_SPEED
			local pulse = 0.5 + 0.5 * math.sin(t)
			local shimmer = 0.5 + 0.5 * math.sin(t * 2.4 + 0.8)

			glowOuter.BackgroundTransparency = math.clamp(
				GLOW_OUTER_BASE_TRANSPARENCY - 0.12 * pulse + 0.06 * math.sin(t * 3.2),
				0.65,
				0.90
			)
			glowOuter.BackgroundColor3 = accent.glow:Lerp(accent.glowBright, shimmer * 0.35)

			RunService.Heartbeat:Wait()
		end
	end)
end

local function spawnScreenCashPop(root: Frame, amount: number)
	local label = Instance.new("TextLabel")
	label.Name = "CashPop"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 6)
	label.Size = UDim2.fromOffset(120, 32)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = RewardUiColors.PROFIT_GREEN
	label.TextStrokeColor3 = CASH_POP_STROKE
	label.TextStrokeTransparency = 0.35
	label.TextTransparency = 0
	label.Text = string.format("+$%d", amount)
	label.ZIndex = 3
	label.Parent = root

	local sizeCap = Instance.new("UITextSizeConstraint")
	sizeCap.MaxTextSize = 26
	sizeCap.MinTextSize = 14
	sizeCap.Parent = label

	local startPos = label.Position
	local goalPos = startPos + UDim2.fromOffset(0, -CASH_POP_RISE_PX)
	local moveTween = TweenService:Create(
		label,
		TweenInfo.new(CASH_POP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = goalPos }
	)
	moveTween:Play()

	local fadeDuration = CASH_POP_DURATION * (1 - CASH_POP_FADE_START_ALPHA)
	task.delay(CASH_POP_DURATION * CASH_POP_FADE_START_ALPHA, function()
		if not label.Parent then
			return
		end
		local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

local function playCashRewardFromFrame(root: Frame, amount: number)
	if amount <= 0 then
		return
	end

	spawnScreenCashPop(root, amount)

	task.defer(function()
		if not root.Parent then
			return
		end
		local center = root.AbsolutePosition + root.AbsoluteSize * 0.5
		CashFlyVfxUtil.playFlyFromScreen(playerGui, center.X, center.Y, amount)
	end)
end

local function prepareCatch(imageId: string, amount: number)
	warmImageIdInPoolAsync(imageId)
	pcall(function()
		ContentProvider:PreloadAsync({ imageId, WAVE_WIPE_IMAGE_ID, SAND_COVER_IMAGE_ID })
	end)
	preparedAmountByImageId[imageId] = amount
end

local function playRevealCelebration(pending: PendingCatch, tier: FishTier, sparkleDurationSec: number?)
	local popInfo = TweenInfo.new(POP_IN_SEC, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(pending.rootScale, popInfo, { Scale = 1 }):Play()
	local sparkleSec = sparkleDurationSec or DISPLAY_SEC
	runSparkleLoop(pending.gui, pending.glowOuter, sparkleSec, getAccentColorsForTier(tier))
	playCashRewardFromFrame(pending.root, pending.amount)
end

-- Runs synchronously until this catch's full sequence finishes (for queue draining).
local function runRevealCelebration(job: RevealJob)
	local imageId = job.imageId
	local amount = job.amount
	local showWaveFlag = job.showWave

	local preparedAmount = preparedAmountByImageId[imageId]
	preparedAmountByImageId[imageId] = nil
	destroyActiveCatch()

	if amount <= 0 and typeof(preparedAmount) == "number" and preparedAmount > 0 then
		amount = preparedAmount
	end

	local tier = resolveTierForImageId(imageId)
	activeCatch = buildCatchOverlay(imageId, amount, tier)
	local pending = activeCatch
	if not pending or not pending.gui.Parent then
		activeCatch = nil
		return
	end

	pending.amount = amount
	waitForImageLabelLoaded(pending.fishImage, PREPARE_LOAD_TIMEOUT_SEC)

	local playWave = shouldPlayWaveWipe(imageId, showWaveFlag)
	if playWave then
		pending.fishImage.ImageTransparency = 1
	end

	pending.rootCanvas.GroupTransparency = 0
	waitFrames(REVEAL_SETTLE_FRAME_COUNT)
	waitForImageLabelLoaded(pending.fishImage, PREPARE_LOAD_TIMEOUT_SEC)

	if playWave then
		playRevealCelebration(pending, tier, WAVE_WIPE_DURATION_SEC)
		playWaveWipeInsidePanel(pending.fishImage, pending.fishPanel)
		markFishDiscoveredSession(imageId)
		destroyActiveCatch()
	else
		task.wait(REVEAL_PAUSE_BEFORE_WIPE_SEC)
		pending.fishImage.ImageTransparency = 0
		playRevealCelebration(pending, tier)
		task.wait(DISPLAY_SEC + 0.25)
		destroyActiveCatch()
	end
end

local function drainRevealQueue()
	if revealDrainRunning then
		return
	end
	revealDrainRunning = true
	task.spawn(function()
		while #revealQueue > 0 do
			local job = table.remove(revealQueue, 1)
			runRevealCelebration(job)
		end
		revealDrainRunning = false
	end)
end

local function enqueueReveal(imageId: string, amount: number, showWaveFlag: any)
	table.insert(revealQueue, {
		imageId = imageId,
		amount = amount,
		showWave = showWaveFlag,
	})
	drainRevealQueue()
end

local function startJoinWarmup()
	task.spawn(function()
		local ids = SplashKillFishFrames.getFrameIds()
		if #ids == 0 then
			warmImageIdInPoolAsync(SplashKillFishFrames.FALLBACK_IMAGE_ID)
			return
		end
		pcall(function()
			ContentProvider:PreloadAsync(ids)
		end)
		pcall(function()
			ContentProvider:PreloadAsync({ WAVE_WIPE_IMAGE_ID, SAND_COVER_IMAGE_ID })
		end)
		for index, id in ids do
			warmImageIdInPoolAsync(id)
			if index % JOIN_WARMUP_BATCH_PAUSE_EVERY == 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

startJoinWarmup()

local preloadRemote = ReplicatedStorage:WaitForChild(SPLASH_KILL_FISH_PRELOAD_REMOTE_NAME, 60)
if preloadRemote and preloadRemote:IsA("RemoteEvent") then
	preloadRemote.OnClientEvent:Connect(function(imageId: any)
		if typeof(imageId) == "string" and imageId ~= "" then
			warmImageIdInPoolAsync(imageId)
		end
	end)
end

local remote = ReplicatedStorage:WaitForChild(SPLASH_KILL_FISH_VFX_REMOTE_NAME, 60)
if not remote or not remote:IsA("RemoteEvent") then
	return
end

local function parseVfxPhase(phase: any): string
	if phase == VFX_PHASE_PREPARE or phase == VFX_PHASE_REVEAL then
		return phase
	end
	return VFX_PHASE_REVEAL
end

remote.OnClientEvent:Connect(function(imageId: any, payout: any, phase: any, showWave: any)
	if typeof(imageId) ~= "string" or imageId == "" then
		return
	end
	local amount = if typeof(payout) == "number" then math.floor(payout) else 0
	local resolvedPhase = parseVfxPhase(phase)

	if resolvedPhase == VFX_PHASE_PREPARE then
		prepareCatch(imageId, amount)
	else
		enqueueReveal(imageId, amount, showWave)
	end
end)
