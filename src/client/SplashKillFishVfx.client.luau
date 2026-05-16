--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local RewardUiColors = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RewardUiColors"))
local CashFlyVfxUtil = require(script.Parent:WaitForChild("CashFlyVfxUtil"))

local SPLASH_KILL_FISH_VFX_REMOTE_NAME = "SplashKillFishVfx"
local COMMON_SPLASH_FISH_FRAMES_FOLDER = "commonsplashfishframes"
local DISPLAY_SEC = 1.4
local IMAGE_PX = 100
local PANEL_BG_COLOR = Color3.fromRGB(0, 0, 0)

local REWARD_GREEN = RewardUiColors.PROFIT_GREEN
local REWARD_GREEN_BRIGHT = Color3.fromRGB(200, 255, 220)

local GLOW_OUTER_SCALE = 1.35
local GLOW_FISH_SCALE = 1.12
local GLOW_OUTER_BASE_TRANSPARENCY = 0.80
local GLOW_FISH_BASE_TRANSPARENCY = 0.80
local PANEL_STROKE_THICKNESS = 11
local PANEL_STROKE_TRANSPARENCY = 0.18
local POP_IN_SEC = 0.3
local SPARKLE_SPEED = 6
local CASH_POP_RISE_PX = 28
local CASH_POP_DURATION = 1.5
local CASH_POP_FADE_START_ALPHA = 0.42
local CASH_POP_STROKE = Color3.fromRGB(14, 72, 36)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local joinPreloadStarted = false

local function collectFrameIdsFromFolder(folder: Instance): { string }
	local rows: { { name: string, id: string } } = {}
	for _, ch in folder:GetChildren() do
		if ch:IsA("StringValue") then
			local v = ch.Value
			if typeof(v) == "string" and v ~= "" then
				table.insert(rows, { name = ch.Name, id = v })
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	local out: { string } = {}
	for _, r in rows do
		table.insert(out, r.id)
	end
	return out
end

local function preloadAssets(assets: { string })
	if #assets == 0 then
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)
end

local function startJoinPreload()
	if joinPreloadStarted then
		return
	end
	joinPreloadStarted = true
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(COMMON_SPLASH_FISH_FRAMES_FOLDER, 60)
		if not folder then
			return
		end
		preloadAssets(collectFrameIdsFromFolder(folder))
	end)
end

startJoinPreload()

local remote = ReplicatedStorage:WaitForChild(SPLASH_KILL_FISH_VFX_REMOTE_NAME, 60)
if not remote or not remote:IsA("RemoteEvent") then
	warn("[SplashKillFishVfx] Missing RemoteEvent", SPLASH_KILL_FISH_VFX_REMOTE_NAME)
	return
end

local function runSparkleLoop(
	gui: ScreenGui,
	glowOuter: Frame,
	glowFish: ImageLabel,
	glowFishScale: UIScale,
	durationSec: number
)
	local deadline = os.clock() + durationSec
	task.spawn(function()
		while os.clock() < deadline and gui.Parent and glowOuter.Parent and glowFish.Parent do
			local t = os.clock() * SPARKLE_SPEED
			local pulse = 0.5 + 0.5 * math.sin(t)
			local shimmer = 0.5 + 0.5 * math.sin(t * 2.4 + 0.8)

			glowOuter.BackgroundTransparency = math.clamp(
				GLOW_OUTER_BASE_TRANSPARENCY - 0.12 * pulse + 0.06 * math.sin(t * 3.2),
				0.65,
				0.90
			)
			glowOuter.BackgroundColor3 = REWARD_GREEN:Lerp(REWARD_GREEN_BRIGHT, shimmer * 0.35)

			glowFish.ImageTransparency = math.clamp(
				GLOW_FISH_BASE_TRANSPARENCY - 0.1 * pulse,
				0.68,
				0.85
			)
			glowFishScale.Scale = math.clamp(
				GLOW_FISH_SCALE + 0.06 * pulse + 0.04 * math.sin(t * 3.8),
				1.06,
				1.22
			)
			glowFish.ImageColor3 = REWARD_GREEN:Lerp(REWARD_GREEN_BRIGHT, shimmer * 0.4)

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
	label.TextColor3 = REWARD_GREEN
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

remote.OnClientEvent:Connect(function(imageId: any, payout: any)
	if typeof(imageId) ~= "string" or imageId == "" then
		return
	end
	local amount = if typeof(payout) == "number" then math.floor(payout) else 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "SplashKillFishOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 85
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	local outerPx = math.ceil(IMAGE_PX * GLOW_OUTER_SCALE)
	local root = Instance.new("Frame")
	root.Name = "CatchRoot"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(outerPx, outerPx)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui

	local rootScale = Instance.new("UIScale")
	rootScale.Scale = 0.88
	rootScale.Parent = root

	local glowOuter = Instance.new("Frame")
	glowOuter.Name = "GlowOuter"
	glowOuter.AnchorPoint = Vector2.new(0.5, 0.5)
	glowOuter.Position = UDim2.fromScale(0.5, 0.5)
	glowOuter.Size = UDim2.fromOffset(outerPx, outerPx)
	glowOuter.BackgroundColor3 = REWARD_GREEN
	glowOuter.BackgroundTransparency = GLOW_OUTER_BASE_TRANSPARENCY
	glowOuter.BorderSizePixel = 0
	glowOuter.ZIndex = 0
	glowOuter.Parent = root

	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(0, 6)
	outerCorner.Parent = glowOuter

	local glowFish = Instance.new("ImageLabel")
	glowFish.Name = "GlowFish"
	glowFish.BackgroundTransparency = 1
	glowFish.AnchorPoint = Vector2.new(0.5, 0.5)
	glowFish.Position = UDim2.fromScale(0.5, 0.5)
	glowFish.Size = UDim2.fromOffset(IMAGE_PX, IMAGE_PX)
	glowFish.ZIndex = 1
	glowFish.Image = imageId
	glowFish.ScaleType = Enum.ScaleType.Fit
	glowFish.ImageTransparency = GLOW_FISH_BASE_TRANSPARENCY
	glowFish.ImageColor3 = REWARD_GREEN
	glowFish.Parent = root

	local glowFishScale = Instance.new("UIScale")
	glowFishScale.Scale = GLOW_FISH_SCALE
	glowFishScale.Parent = glowFish

	local panel = Instance.new("Frame")
	panel.Name = "FishPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(IMAGE_PX, IMAGE_PX)
	panel.BackgroundColor3 = PANEL_BG_COLOR
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = root

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Name = "RewardStroke"
	panelStroke.Color = REWARD_GREEN
	panelStroke.Thickness = PANEL_STROKE_THICKNESS
	panelStroke.Transparency = PANEL_STROKE_TRANSPARENCY
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	panelStroke.LineJoinMode = Enum.LineJoinMode.Round
	panelStroke.Parent = panel

	local img = Instance.new("ImageLabel")
	img.Name = "Fish"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = 1
	img.Image = imageId
	img.ScaleType = Enum.ScaleType.Fit
	img.ImageTransparency = 0
	img.Parent = panel

	pcall(function()
		ContentProvider:PreloadAsync({ imageId })
	end)
	pcall(function()
		ContentProvider:PreloadAsync({ img })
	end)

	gui.Enabled = true

	local popInfo = TweenInfo.new(POP_IN_SEC, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(rootScale, popInfo, { Scale = 1 }):Play()

	runSparkleLoop(gui, glowOuter, glowFish, glowFishScale, DISPLAY_SEC)

	playCashRewardFromFrame(root, amount)

	Debris:AddItem(gui, DISPLAY_SEC + 0.25)
end)
