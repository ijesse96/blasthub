--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local RewardUiColors = require(shared:WaitForChild("RewardUiColors"))
local SplashFishCatalog = require(shared:WaitForChild("SplashFishCatalog"))
local SplashKillFishFrames = require(shared:WaitForChild("SplashKillFishFrames"))
local BattleUnitStats = require(shared:WaitForChild("BattleUnitStats"))

type FishTier = SplashFishCatalog.FishTier

local TIER_ACCENT: { [FishTier]: Color3 } = {
	common = RewardUiColors.FISH_COMMON_GREEN,
	rare = RewardUiColors.FISH_RARE_BLUE,
	legendary = RewardUiColors.FISH_LEGENDARY_PURPLE,
	jackpot = RewardUiColors.FISH_JACKPOT_GOLD,
}

export type BattleCardOptions = {
	imageId: string,
	copyCount: number,
	mapId: string,
	width: number?,
	height: number?,
	selected: boolean?,
	manaCost: number?,
	onClick: (() -> ())?,
}

local M = {}

function M.getTierAccent(mapId: string, imageId: string): Color3
	local tier = SplashFishCatalog.getTierForImageId(mapId, imageId)
	if tier then
		return TIER_ACCENT[tier]
	end
	return Color3.fromRGB(120, 128, 140)
end

function M.makeCard(options: BattleCardOptions): TextButton
	local w = options.width or 88
	local h = options.height or 108
	local mapId = options.mapId
	local imageId = options.imageId
	local copyCount = options.copyCount
	local level = BattleUnitStats.getLevelFromCopyCount(copyCount)
	local tier = SplashFishCatalog.getTierForImageId(mapId, imageId)
	local hp, atk = BattleUnitStats.getStatsForFish(mapId, imageId, copyCount)

	local isSelected = options.selected == true

	local card = Instance.new("TextButton")
	card.Name = "BattleCard"
	card.Size = UDim2.fromOffset(w, h)
	card.Text = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = if isSelected then Color3.fromRGB(40, 58, 72) else Color3.fromRGB(28, 40, 34)
	card.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = if isSelected then Color3.fromRGB(255, 220, 80) else M.getTierAccent(mapId, imageId)
	stroke.Thickness = if isSelected then 3 else 1.5
	stroke.Parent = card

	if isSelected then
		local selectedBadge = Instance.new("TextLabel")
		selectedBadge.Name = "SelectedBadge"
		selectedBadge.AnchorPoint = Vector2.new(1, 0)
		selectedBadge.Position = UDim2.new(1, -4, 0, 4)
		selectedBadge.Size = UDim2.fromOffset(52, 14)
		selectedBadge.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
		selectedBadge.BackgroundTransparency = 0.1
		selectedBadge.Font = Enum.Font.GothamBold
		selectedBadge.TextSize = 9
		selectedBadge.TextColor3 = Color3.fromRGB(24, 20, 8)
		selectedBadge.Text = "SELECTED"
		selectedBadge.Parent = card

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 3)
		badgeCorner.Parent = selectedBadge
	end

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.42)
	art.Size = UDim2.fromOffset(56, 56)
	art.BackgroundTransparency = 1
	art.Image = imageId
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = card
	SplashKillFishFrames.applyFullImageToLabel(art)

	local levelBadge = Instance.new("TextLabel")
	levelBadge.Name = "Level"
	levelBadge.AnchorPoint = Vector2.new(0, 0)
	levelBadge.Position = UDim2.fromOffset(6, 4)
	levelBadge.Size = UDim2.fromOffset(32, 18)
	levelBadge.BackgroundColor3 = Color3.fromRGB(18, 32, 48)
	levelBadge.BackgroundTransparency = 0.15
	levelBadge.Font = Enum.Font.GothamBold
	levelBadge.TextSize = 12
	levelBadge.TextColor3 = Color3.fromRGB(255, 220, 100)
	levelBadge.Text = "L" .. tostring(level)
	levelBadge.Parent = card

	local levelCorner = Instance.new("UICorner")
	levelCorner.CornerRadius = UDim.new(0, 4)
	levelCorner.Parent = levelBadge

	local stats = Instance.new("TextLabel")
	stats.Name = "Stats"
	stats.AnchorPoint = Vector2.new(0.5, 1)
	stats.Position = UDim2.new(0.5, 0, 1, -6)
	stats.Size = UDim2.new(1, -8, 0, 28)
	stats.BackgroundTransparency = 1
	stats.Font = Enum.Font.GothamMedium
	stats.TextSize = 11
	stats.TextColor3 = Color3.fromRGB(200, 210, 220)
	if options.manaCost then
		stats.Text = string.format("♥%d  ⚔%d  ◆%d", hp, atk, options.manaCost)
	else
		stats.Text = string.format("♥%d  ⚔%d", hp, atk)
	end
	stats.Parent = card

	if options.onClick then
		card.MouseButton1Click:Connect(options.onClick)
	end

	return card
end

return M
