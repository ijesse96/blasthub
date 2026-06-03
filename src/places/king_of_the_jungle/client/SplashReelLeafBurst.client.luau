--!strict
-- Leaf ring burst on jungle splash billboards while they reel to the turret.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))

local LEAF_IMAGE = MatchSplashConfig.getReelLeafImageId()
if not LEAF_IMAGE or LEAF_IMAGE == "" then
	return
end

local DEATH_VFX_FOLDER_NAME = "ConveyorDeathVFX"
local IS_WATER_SPLASH_ATTRIBUTE = "IsWaterSplash"
local REEL_LEAF_BURST_ATTRIBUTE = "ReelLeafBurstPlayed"

local HARPOON_REEL_DURATION_SEC = 2.1
local LEAF_BILLBOARD_SCALE = 1.25
local LEAF_PX = 28
local BURST_DURATION_SEC = 1.05
local LEAF_STAGGER_SEC = 0.11
local BURST_EASING = Enum.EasingStyle.Sine
local BURST_DIRECTION = Enum.EasingDirection.Out

local BURST_WAVES = {
	{ delay = 0, count = 8, startRadius = 0.34, endRadius = 0.92, lift = 0.06 },
	{ delay = 0.55, count = 5, startRadius = 0.30, endRadius = 0.78, lift = 0.05 },
	{ delay = 1.15, count = 4, startRadius = 0.28, endRadius = 0.68, lift = 0.04 },
}

local trackedModels: { [Model]: boolean } = {}

local function getSplashAnchor(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local anchor = model:FindFirstChild("Anchor")
	if anchor and anchor:IsA("BasePart") then
		return anchor
	end
	return nil
end

local function ensureLeafBillboard(anchor: BasePart, splashBillboard: BillboardGui): BillboardGui
	local existing = anchor:FindFirstChild("ReelLeafBurst")
	if existing and existing:IsA("BillboardGui") then
		return existing
	end

	local splashPx = splashBillboard.Size.X.Offset
	if splashPx <= 0 then
		splashPx = 90
	end
	local leafPx = math.floor(splashPx * LEAF_BILLBOARD_SCALE)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ReelLeafBurst"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = splashBillboard.MaxDistance
	billboard.Size = UDim2.fromOffset(leafPx, leafPx)
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.Parent = anchor
	return billboard
end

local function spawnSingleLeaf(
	billboard: BillboardGui,
	wave: typeof(BURST_WAVES[1]),
	index: number,
	total: number
)
	local angle = ((index - 1) / total) * math.pi * 2 + (math.random() - 0.5) * 0.35
	local startX = 0.5 + math.cos(angle) * wave.startRadius
	local startY = 0.5 + math.sin(angle) * wave.startRadius
	local endX = 0.5 + math.cos(angle) * wave.endRadius
	local endY = 0.5 + math.sin(angle) * wave.endRadius - wave.lift

	local leafSize = LEAF_PX + math.random(-4, 6)
	local spin = (math.random() - 0.5) * 140

	local leaf = Instance.new("ImageLabel")
	leaf.Name = "Leaf"
	leaf.BackgroundTransparency = 1
	leaf.Image = LEAF_IMAGE
	leaf.ImageTransparency = 0.05
	leaf.ScaleType = Enum.ScaleType.Fit
	leaf.AnchorPoint = Vector2.new(0.5, 0.5)
	leaf.Position = UDim2.fromScale(startX, startY)
	leaf.Size = UDim2.fromOffset(leafSize, leafSize)
	leaf.Rotation = spin
	leaf.ZIndex = 1
	leaf.Parent = billboard

	local endSize = leafSize + math.random(2, 8)
	local duration = BURST_DURATION_SEC + math.random() * 0.18
	local tween = TweenService:Create(
		leaf,
		TweenInfo.new(duration, BURST_EASING, BURST_DIRECTION),
		{
			Position = UDim2.fromScale(endX, endY),
			Rotation = spin + (math.random() - 0.5) * 120,
			ImageTransparency = 1,
			Size = UDim2.fromOffset(endSize, endSize),
		}
	)
	tween.Completed:Connect(function()
		leaf:Destroy()
	end)
	tween:Play()
end

local function spawnLeafWave(billboard: BillboardGui, wave: typeof(BURST_WAVES[1]))
	for index = 1, wave.count do
		local leafDelay = (index - 1) * LEAF_STAGGER_SEC
		task.delay(leafDelay, function()
			if not billboard.Parent then
				return
			end
			spawnSingleLeaf(billboard, wave, index, wave.count)
		end)
	end
end

local function playReelLeafBurst(model: Model)
	local anchor = getSplashAnchor(model)
	if not anchor then
		return
	end

	local splashBillboard = anchor:FindFirstChild("SplashBillboard")
	if not splashBillboard or not splashBillboard:IsA("BillboardGui") then
		return
	end

	local leafBillboard = ensureLeafBillboard(anchor, splashBillboard)

	for _, wave in BURST_WAVES do
		task.delay(wave.delay, function()
			if not model.Parent or not leafBillboard.Parent then
				return
			end
			spawnLeafWave(leafBillboard, wave)
		end)
	end

	task.delay(HARPOON_REEL_DURATION_SEC + 0.8, function()
		if leafBillboard.Parent then
			leafBillboard:Destroy()
		end
	end)
end

local function tryPlayForSplashModel(model: Model)
	if trackedModels[model] then
		return
	end
	if model:GetAttribute(IS_WATER_SPLASH_ATTRIBUTE) ~= true then
		return
	end

	trackedModels[model] = true
	model:SetAttribute(REEL_LEAF_BURST_ATTRIBUTE, true)

	model.Destroying:Connect(function()
		trackedModels[model] = nil
	end)

	task.defer(function()
		if model.Parent then
			playReelLeafBurst(model)
		end
	end)
end

local function hookDeathFolder(folder: Folder)
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			tryPlayForSplashModel(child)
		end
	end)

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			tryPlayForSplashModel(child)
		end
	end
end

task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ LEAF_IMAGE })
	end)
end)

local existing = Workspace:FindFirstChild(DEATH_VFX_FOLDER_NAME)
if existing and existing:IsA("Folder") then
	hookDeathFolder(existing)
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == DEATH_VFX_FOLDER_NAME and child:IsA("Folder") then
		hookDeathFolder(child)
	end
end)
