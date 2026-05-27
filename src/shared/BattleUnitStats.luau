--!strict
local SplashFishCatalog = require(script.Parent:WaitForChild("SplashFishCatalog"))

local BattleUnitStats = {}

local TIER_BASE: { [SplashFishCatalog.FishTier]: { hp: number, atk: number } } = {
	common = { hp = 60, atk = 8 },
	rare = { hp = 80, atk = 12 },
	legendary = { hp = 100, atk = 16 },
	jackpot = { hp = 120, atk = 20 },
}

local LEVEL_MULTIPLIER = {
	[1] = 1,
	[2] = 1.25,
	[3] = 1.5,
}

function BattleUnitStats.getLevelFromCopyCount(copyCount: number): number
	return math.clamp(math.floor(copyCount), 1, 3)
end

function BattleUnitStats.getBaseStatsForTier(tier: SplashFishCatalog.FishTier): (number, number)
	local base = TIER_BASE[tier]
	return base.hp, base.atk
end

function BattleUnitStats.getManaCostForFish(mapId: string, imageId: string): number
	local BattleGridConfig = require(script.Parent:WaitForChild("BattleGridConfig"))
	local tier = SplashFishCatalog.getTierForImageId(mapId, imageId)
	if not tier then
		return BattleGridConfig.MANA_COST_BY_TIER.common
	end
	return BattleGridConfig.MANA_COST_BY_TIER[tier] or BattleGridConfig.MANA_COST_BY_TIER.common
end

function BattleUnitStats.getStatsForFish(mapId: string, imageId: string, copyCount: number): (number, number, number)
	local tier = SplashFishCatalog.getTierForImageId(mapId, imageId)
	if not tier then
		return 60, 8, 1
	end
	local level = BattleUnitStats.getLevelFromCopyCount(copyCount)
	local mult = LEVEL_MULTIPLIER[level] or 1
	local hp, atk = BattleUnitStats.getBaseStatsForTier(tier)
	return math.floor(hp * mult + 0.5), math.floor(atk * mult + 0.5), level
end

return BattleUnitStats
