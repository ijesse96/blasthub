--!strict
local SplashFishCatalog = require(script.Parent:WaitForChild("SplashFishCatalog"))

export type BattleFilterId = "all" | "common" | "rare" | "legendary" | "jackpot"

local BattleElementTags = {}

local FILTERS: { BattleFilterId } = { "all", "common", "rare", "legendary", "jackpot" }

local FILTER_LABEL: { [BattleFilterId]: string } = {
	all = "ALL",
	common = "C",
	rare = "R",
	legendary = "L",
	jackpot = "J",
}

function BattleElementTags.getFilters(): { BattleFilterId }
	return FILTERS
end

function BattleElementTags.getFilterLabel(filterId: BattleFilterId): string
	return FILTER_LABEL[filterId] or "?"
end

function BattleElementTags.fishMatchesFilter(mapId: string, imageId: string, filterId: BattleFilterId): boolean
	if filterId == "all" then
		return true
	end
	return SplashFishCatalog.getTierForImageId(mapId, imageId) == filterId
end

return BattleElementTags
