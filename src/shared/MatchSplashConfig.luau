--!strict
-- Per-map splash spawn visuals (floor target that players shoot).
-- King of the Jungle: delete Workspace.Water in Studio; spawner builds billboard PNGs from config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchMaps = require(script.Parent:WaitForChild("MatchMaps"))

export type SplashVisualMode = "water_template" | "billboard_png"

export type SplashVisual = {
	mode: SplashVisualMode,
	workspaceTemplateName: string?,
	imageId: string?,
	splashFrameIds: { string }?,
	billboardStuds: number?,
	fishBillboardScale: number?,
	hitNetTextureId: string?,
	-- Override hit-net BillboardGui pixel size (bbox-based sizing uses huge flat-decal anchors).
	hitNetBillboardPx: number?,
	sandCoverImageId: string?,
	reelLeafImageId: string?,
	scrollWaterBackground: boolean,
}

local ACTIVE_MAP_ID_NAME = "ActiveMapId"
local DEFAULT_MAP_ID = "main"

local FISH_FRENZY_SPLASH_FRAME_RIPPLE = "rbxassetid://91096902597254"
local FISH_FRENZY_SPLASH_FRAME_MID = "rbxassetid://98880235729019"
local FISH_FRENZY_SPLASH_FRAME_FULL = "rbxassetid://112577396294090"
local FISH_FRENZY_SPLASH_FRAMES = {
	FISH_FRENZY_SPLASH_FRAME_RIPPLE,
	FISH_FRENZY_SPLASH_FRAME_MID,
	FISH_FRENZY_SPLASH_FRAME_FULL,
}
local JUNGLE_SPLASH_IMAGE = "rbxassetid://110419001189017"
local DEFAULT_HIT_NET = "rbxassetid://135625585340416"
local DEFAULT_SAND_COVER = "rbxassetid://122141499309246"
local JUNGLE_SAND_COVER = "rbxassetid://74096649335349"

local byMapId: { [string]: SplashVisual } = {
	main = {
		mode = "billboard_png",
		workspaceTemplateName = nil,
		imageId = FISH_FRENZY_SPLASH_FRAME_RIPPLE,
		splashFrameIds = FISH_FRENZY_SPLASH_FRAMES,
		billboardStuds = 8,
		fishBillboardScale = 0.08,
		hitNetTextureId = DEFAULT_HIT_NET,
		sandCoverImageId = DEFAULT_SAND_COVER,
		scrollWaterBackground = true,
	},
	king_of_the_jungle = {
		mode = "billboard_png",
		workspaceTemplateName = nil,
		imageId = JUNGLE_SPLASH_IMAGE,
		billboardStuds = 9,
		hitNetTextureId = DEFAULT_HIT_NET,
		sandCoverImageId = JUNGLE_SAND_COVER,
		reelLeafImageId = "rbxassetid://85727082053287",
		scrollWaterBackground = false,
	},
	dragon_quest = {
		mode = "billboard_png",
		workspaceTemplateName = nil,
		imageId = "rbxassetid://117255021260624",
		billboardStuds = 14,
		fishBillboardScale = 0.05,
		hitNetTextureId = DEFAULT_HIT_NET,
		hitNetBillboardPx = 110,
		sandCoverImageId = DEFAULT_SAND_COVER,
		scrollWaterBackground = true,
	},
}

local MatchSplashConfig = {}

function MatchSplashConfig.resolveMapIdFromPlaceId(placeId: number): string?
	for _, map in MatchMaps.getAll() do
		if map.placeId == placeId and map.placeId ~= 0 then
			return map.id
		end
	end
	return nil
end

function MatchSplashConfig.getActiveMapId(): string
	-- Published place id wins over a copied Fish Frenzy ActiveMapId ("main").
	local fromPlace = MatchSplashConfig.resolveMapIdFromPlaceId(game.PlaceId)
	if fromPlace then
		return fromPlace
	end
	local ch = ReplicatedStorage:FindFirstChild(ACTIVE_MAP_ID_NAME)
	if ch and ch:IsA("StringValue") and ch.Value ~= "" then
		return ch.Value
	end
	return DEFAULT_MAP_ID
end

function MatchSplashConfig.ensureActiveMapIdOnServer(): ()
	local mapId = MatchSplashConfig.getActiveMapId()
	local ch = ReplicatedStorage:FindFirstChild(ACTIVE_MAP_ID_NAME)
	if not ch or not ch:IsA("StringValue") then
		ch = Instance.new("StringValue")
		ch.Name = ACTIVE_MAP_ID_NAME
		ch.Parent = ReplicatedStorage
	end
	local sv = ch :: StringValue
	if sv.Value ~= mapId then
		sv.Value = mapId
	end
end

function MatchSplashConfig.getForMapId(mapId: string): SplashVisual
	local config = byMapId[mapId]
	if config then
		return config
	end
	return byMapId[DEFAULT_MAP_ID]
end

function MatchSplashConfig.getForActiveMap(): SplashVisual
	return MatchSplashConfig.getForMapId(MatchSplashConfig.getActiveMapId())
end

function MatchSplashConfig.isBillboardMode(visual: SplashVisual): boolean
	return visual.mode == "billboard_png"
end

function MatchSplashConfig.getSandCoverImageId(): string
	local visual = MatchSplashConfig.getForActiveMap()
	return visual.sandCoverImageId or DEFAULT_SAND_COVER
end

function MatchSplashConfig.getReelLeafImageId(): string?
	local visual = MatchSplashConfig.getForActiveMap()
	return visual.reelLeafImageId
end

function MatchSplashConfig.getSplashFrameIds(mapId: string?): { string }?
	local visual = MatchSplashConfig.getForMapId(mapId or MatchSplashConfig.getActiveMapId())
	local frames = visual.splashFrameIds
	if frames and #frames >= 2 then
		return frames
	end
	return nil
end

return MatchSplashConfig
