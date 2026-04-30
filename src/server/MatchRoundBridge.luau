local callbacks = {
	allowFishSpawn = function(): boolean
		return false
	end,
	allowShooting = function(_player: Player?): boolean
		return false
	end,
	recordCoinWon = function(_player: Player, _amount: number)
	end,
	recordCoinSpent = function(_player: Player, _amount: number)
	end,
	clearFishNow = function()
	end,
}

local M = {}

function M.setCallbacks(nextCallbacks: {
	allowFishSpawn: (() -> boolean)?,
	allowShooting: ((Player?) -> boolean)?,
	recordCoinWon: ((Player, number) -> ())?,
	recordCoinSpent: ((Player, number) -> ())?,
	clearFishNow: (() -> ())?,
})
	if nextCallbacks.allowFishSpawn then
		callbacks.allowFishSpawn = nextCallbacks.allowFishSpawn
	end
	if nextCallbacks.allowShooting then
		callbacks.allowShooting = nextCallbacks.allowShooting
	end
	if nextCallbacks.recordCoinWon then
		callbacks.recordCoinWon = nextCallbacks.recordCoinWon
	end
	if nextCallbacks.recordCoinSpent then
		callbacks.recordCoinSpent = nextCallbacks.recordCoinSpent
	end
	if nextCallbacks.clearFishNow then
		callbacks.clearFishNow = nextCallbacks.clearFishNow
	end
end

function M.allowFishSpawn(): boolean
	return callbacks.allowFishSpawn()
end

function M.allowShooting(player: Player?): boolean
	return callbacks.allowShooting(player)
end

function M.recordCoinWon(player: Player, amount: number)
	callbacks.recordCoinWon(player, amount)
end

function M.recordCoinSpent(player: Player, amount: number)
	callbacks.recordCoinSpent(player, amount)
end

function M.clearFishNow()
	callbacks.clearFishNow()
end

return M
