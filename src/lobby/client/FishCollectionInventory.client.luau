--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local MatchMaps = require(shared:WaitForChild("MatchMaps"))
local RewardUiColors = require(shared:WaitForChild("RewardUiColors"))
local SplashFishCatalog = require(shared:WaitForChild("SplashFishCatalog"))
local SplashKillFishFrames = require(shared:WaitForChild("SplashKillFishFrames"))

type FishTier = SplashFishCatalog.FishTier

local TIERS: { FishTier } = SplashFishCatalog.getOrderedTiers()

local TIER_DISPLAY: { [FishTier]: string } = {
	common = "Common",
	rare = "Rare",
	legendary = "Legendary",
	jackpot = "Jackpot",
}

local TIER_ACCENT: { [FishTier]: Color3 } = {
	common = RewardUiColors.FISH_COMMON_GREEN,
	rare = RewardUiColors.FISH_RARE_BLUE,
	legendary = RewardUiColors.FISH_LEGENDARY_PURPLE,
	jackpot = RewardUiColors.FISH_JACKPOT_GOLD,
}

local CARD_W = 100
local CARD_H = 130
local CARD_PAD = 8
local GRID_COLUMNS = 5

type OwnedByMap = { [string]: { [string]: number } }

local ownedByMap: OwnedByMap = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeMapId = "main"
local panelOpen = false

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FishCollectionInventory"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 55
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenCollection"
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 20, 1, -20)
openButton.Size = UDim2.fromOffset(140, 36)
openButton.BackgroundColor3 = Color3.fromRGB(24, 38, 30)
openButton.BackgroundTransparency = 0.1
openButton.Font = Enum.Font.GothamBold
openButton.TextSize = 18
openButton.TextColor3 = RewardUiColors.PROFIT_GREEN
openButton.Text = "Collection"
openButton.AutoButtonColor = true
openButton.Parent = screenGui

local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 8)
openCorner.Parent = openButton

local openStroke = Instance.new("UIStroke")
openStroke.Color = RewardUiColors.PROFIT_STROKE
openStroke.Thickness = 1.5
openStroke.Transparency = 0.35
openStroke.Parent = openButton

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(6, 10, 14)
backdrop.BackgroundTransparency = 0.15
backdrop.Visible = false
backdrop.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.92, 0, 0.88, 0)
panel.BackgroundColor3 = Color3.fromRGB(14, 20, 26)
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = backdrop

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(40, 58, 48)
panelStroke.Thickness = 2
panelStroke.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundTransparency = 1
header.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Position = UDim2.fromOffset(20, 8)
titleLabel.Size = UDim2.new(1, -160, 1, -8)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 28
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = Color3.fromRGB(235, 245, 240)
titleLabel.Text = "Collection"
titleLabel.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -16, 0.5, 0)
closeButton.Size = UDim2.fromOffset(36, 36)
closeButton.BackgroundColor3 = Color3.fromRGB(32, 42, 50)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 22
closeButton.TextColor3 = Color3.fromRGB(220, 230, 235)
closeButton.Text = "X"
closeButton.Parent = header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

local mapTabBar = Instance.new("Frame")
mapTabBar.Name = "MapTabs"
mapTabBar.Position = UDim2.fromOffset(16, 56)
mapTabBar.Size = UDim2.new(1, -32, 0, 36)
mapTabBar.BackgroundTransparency = 1
mapTabBar.Parent = panel

local mapTabLayout = Instance.new("UIListLayout")
mapTabLayout.FillDirection = Enum.FillDirection.Horizontal
mapTabLayout.Padding = UDim.new(0, 8)
mapTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
mapTabLayout.Parent = mapTabBar

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Body"
scroll.Position = UDim2.fromOffset(12, 100)
scroll.Size = UDim2.new(1, -24, 1, -148)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 95)
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.Padding = UDim.new(0, 16)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Parent = scroll

local footer = Instance.new("TextLabel")
footer.Name = "Footer"
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 20, 1, -12)
footer.Size = UDim2.new(1, -40, 0, 28)
footer.BackgroundTransparency = 1
footer.Font = Enum.Font.GothamMedium
footer.TextSize = 18
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextColor3 = RewardUiColors.PROFIT_GREEN
footer.Text = "Collected 0 / 0"
footer.Parent = panel

local mapTabsById: { [string]: TextButton } = {}

local function sanitizeOwnedSnapshot(raw: unknown): OwnedByMap
	if typeof(raw) ~= "table" then
		return {}
	end
	local out: OwnedByMap = {}
	for mapId, mapData in raw :: { [string]: any } do
		if typeof(mapId) ~= "string" or typeof(mapData) ~= "table" then
			continue
		end
		local owned: { [string]: number } = {}
		for imageId, count in mapData do
			if typeof(imageId) == "string" and typeof(count) == "number" and count > 0 then
				owned[imageId] = math.floor(count)
			end
		end
		if next(owned) ~= nil then
			out[mapId] = owned
		end
	end
	return out
end

local function getOwnedForMap(mapId: string): { [string]: number }
	return ownedByMap[mapId] or {}
end

local function countOwnedInMap(mapId: string): number
	local owned = getOwnedForMap(mapId)
	local count = 0
	for imageId in owned do
		if owned[imageId] > 0 then
			count += 1
		end
	end
	return count
end

local function clearScrollChildren()
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") and child ~= bodyLayout then
			child:Destroy()
		end
	end
end

local function applyTabStyle(tab: TextButton, selected: boolean)
	if selected then
		tab.BackgroundColor3 = Color3.fromRGB(36, 58, 46)
		tab.TextColor3 = RewardUiColors.PROFIT_GREEN
	else
		tab.BackgroundColor3 = Color3.fromRGB(26, 34, 42)
		tab.TextColor3 = Color3.fromRGB(170, 180, 190)
	end
end

local function refreshMapTabs()
	for mapId, tab in mapTabsById do
		applyTabStyle(tab, mapId == activeMapId)
	end
end

local function makeCard(imageId: string, copyCount: number): Frame
	local owned = copyCount > 0

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = if owned then Color3.fromRGB(28, 40, 34) else Color3.fromRGB(20, 24, 30)
	card.BorderSizePixel = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = if owned then Color3.fromRGB(60, 100, 72) else Color3.fromRGB(40, 44, 52)
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = if owned then 0.2 else 0.5
	cardStroke.Parent = card

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.48)
	art.Size = UDim2.fromOffset(72, 72)
	art.BackgroundTransparency = 1
	art.Image = imageId
	art.ImageTransparency = if owned then 0 else 0.84
	art.ImageColor3 = if owned then Color3.new(1, 1, 1) else Color3.fromRGB(68, 72, 82)
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = card
	SplashKillFishFrames.applyFullImageToLabel(art)

	if not owned then
		local lockOverlay = Instance.new("Frame")
		lockOverlay.Name = "LockOverlay"
		lockOverlay.Size = UDim2.fromScale(1, 1)
		lockOverlay.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
		lockOverlay.BackgroundTransparency = 0.3
		lockOverlay.BorderSizePixel = 0
		lockOverlay.Parent = card

		local lockCorner = Instance.new("UICorner")
		lockCorner.CornerRadius = UDim.new(0, 8)
		lockCorner.Parent = lockOverlay

		local lockLabel = Instance.new("TextLabel")
		lockLabel.Size = UDim2.fromScale(1, 1)
		lockLabel.BackgroundTransparency = 1
		lockLabel.Font = Enum.Font.GothamBold
		lockLabel.TextSize = 64
		lockLabel.TextColor3 = Color3.fromRGB(120, 128, 140)
		lockLabel.Text = "?"
		lockLabel.Parent = lockOverlay
	elseif copyCount > 1 then
		local badge = Instance.new("TextLabel")
		badge.Name = "CountBadge"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -6, 0, 6)
		badge.Size = UDim2.fromOffset(32, 22)
		badge.BackgroundColor3 = Color3.fromRGB(18, 32, 24)
		badge.BackgroundTransparency = 0.1
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 14
		badge.TextColor3 = RewardUiColors.PROFIT_GREEN
		badge.Text = "x" .. tostring(copyCount)
		badge.Parent = card

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 6)
		badgeCorner.Parent = badge
	end

	return card
end

local function makeTierSection(tier: FishTier, imageIds: { string }, owned: { [string]: number }): Frame
	local section = Instance.new("Frame")
	section.Name = tier .. "Section"
	section.Size = UDim2.new(1, -8, 0, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.BackgroundTransparency = 1

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.Padding = UDim.new(0, 8)
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Parent = section

	local tierHeader = Instance.new("TextLabel")
	tierHeader.Name = "TierHeader"
	tierHeader.Size = UDim2.new(1, 0, 0, 28)
	tierHeader.BackgroundTransparency = 1
	tierHeader.Font = Enum.Font.GothamBold
	tierHeader.TextSize = 20
	tierHeader.TextXAlignment = Enum.TextXAlignment.Left
	tierHeader.TextColor3 = TIER_ACCENT[tier]
	tierHeader.Text = TIER_DISPLAY[tier]
	tierHeader.LayoutOrder = 0
	tierHeader.Parent = section

	if #imageIds == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 24)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 16
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.TextColor3 = Color3.fromRGB(110, 118, 128)
		empty.Text = "No cards yet"
		empty.LayoutOrder = 1
		empty.Parent = section
		return section
	end

	local gridHost = Instance.new("Frame")
	gridHost.Name = "Grid"
	gridHost.Size = UDim2.new(1, 0, 0, 0)
	gridHost.AutomaticSize = Enum.AutomaticSize.Y
	gridHost.BackgroundTransparency = 1
	gridHost.LayoutOrder = 1
	gridHost.Parent = section

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	grid.CellPadding = UDim2.fromOffset(CARD_PAD, CARD_PAD)
	grid.FillDirectionMaxCells = GRID_COLUMNS
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridHost

	local rowCount = math.ceil(#imageIds / GRID_COLUMNS)
	gridHost.Size = UDim2.new(1, 0, 0, rowCount * (CARD_H + CARD_PAD) + CARD_PAD)

	for i, imageId in imageIds do
		local copies = owned[imageId] or 0
		local card = makeCard(imageId, copies)
		card.LayoutOrder = i
		card.Parent = gridHost
	end

	return section
end

local function renderCollection()
	clearScrollChildren()

	local owned = getOwnedForMap(activeMapId)
	local total = SplashFishCatalog.countCardsForMap(activeMapId)
	local ownedUnique = countOwnedInMap(activeMapId)

	footer.Text = string.format("Collected %d / %d", ownedUnique, total)

	for order, tier in TIERS do
		local ids = SplashFishCatalog.getIdsForTier(activeMapId, tier)
		local section = makeTierSection(tier, ids, owned)
		section.LayoutOrder = order
		section.Parent = scroll
	end

	refreshMapTabs()
end

local function applyOwnedSnapshot(snapshot: unknown)
	ownedByMap = sanitizeOwnedSnapshot(snapshot)
	if panelOpen then
		renderCollection()
	end
end

local function buildMapTabs()
	for _, tab in mapTabsById do
		tab:Destroy()
	end
	table.clear(mapTabsById)

	local maps = MatchMaps.getAll()
	table.sort(maps, function(a, b)
		return a.displayName < b.displayName
	end)

	for i, map in maps do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. map.id
		tab.Size = UDim2.fromOffset(120, 32)
		tab.BackgroundColor3 = Color3.fromRGB(26, 34, 42)
		tab.Font = Enum.Font.GothamBold
		tab.TextSize = 16
		tab.Text = map.displayName
		tab.LayoutOrder = i
		tab.AutoButtonColor = true
		tab.Parent = mapTabBar

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 8)
		tabCorner.Parent = tab

		mapTabsById[map.id] = tab

		tab.MouseButton1Click:Connect(function()
			activeMapId = map.id
			renderCollection()
		end)
	end

	if maps[1] and mapTabsById[maps[1].id] then
		activeMapId = maps[1].id
	end
end

local function setPanelOpen(open: boolean)
	panelOpen = open
	backdrop.Visible = open
	panel.Visible = open
	if open then
		renderCollection()
	end
end

openButton.MouseButton1Click:Connect(function()
	setPanelOpen(not panelOpen)
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelOpen(false)
end)

local snapshotRemote = ReplicatedStorage:WaitForChild("FishCollectionSnapshot", 60)
if snapshotRemote and snapshotRemote:IsA("RemoteEvent") then
	snapshotRemote.OnClientEvent:Connect(function(snapshot: unknown)
		applyOwnedSnapshot(snapshot)
	end)
else
	warn("[FishCollectionInventory] Missing RemoteEvent FishCollectionSnapshot")
end

buildMapTabs()
renderCollection()
