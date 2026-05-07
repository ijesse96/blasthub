local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local STORE_NAME = "PlayerCash_v1"
local STARTING_CASH = 100

local store = DataStoreService:GetDataStore(STORE_NAME)

local EconomyStore = {}

local function clampCash(amount: number): number
	return math.max(0, math.floor(amount + 0.5))
end

local function keyForUserId(userId: number): string
	return string.format("cash_%d", userId)
end

local function ensureServer()
	if not RunService:IsServer() then
		error("[EconomyStore] Server-only module.")
	end
end

function EconomyStore.getStartingCash(): number
	return STARTING_CASH
end

function EconomyStore.loadCashAsync(userId: number): number
	ensureServer()
	local ok, value = pcall(function()
		return store:GetAsync(keyForUserId(userId))
	end)
	if not ok then
		warn(string.format("[EconomyStore] loadCashAsync failed for %d: %s", userId, tostring(value)))
		return STARTING_CASH
	end
	if typeof(value) ~= "number" then
		return STARTING_CASH
	end
	return clampCash(value)
end

function EconomyStore.setCashAsync(userId: number, cash: number): boolean
	ensureServer()
	local safeCash = clampCash(cash)
	local ok, err = pcall(function()
		store:SetAsync(keyForUserId(userId), safeCash)
	end)
	if not ok then
		warn(string.format("[EconomyStore] setCashAsync failed for %d: %s", userId, tostring(err)))
	end
	return ok
end

function EconomyStore.tryDebitEntryFeeAsync(userId: number, fee: number): (boolean, number)
	ensureServer()
	local safeFee = clampCash(fee)
	if safeFee <= 0 then
		return true, EconomyStore.loadCashAsync(userId)
	end

	local finalBalance = STARTING_CASH
	local debited = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyForUserId(userId), function(current)
			local currentCash = if typeof(current) == "number" then clampCash(current) else STARTING_CASH
			if currentCash < safeFee then
				finalBalance = currentCash
				debited = false
				return currentCash
			end
			finalBalance = currentCash - safeFee
			debited = true
			return finalBalance
		end)
	end)

	if not ok then
		warn(string.format("[EconomyStore] tryDebitEntryFeeAsync failed for %d: %s", userId, tostring(err)))
		return false, STARTING_CASH
	end

	return debited, finalBalance
end

function EconomyStore.refundEntryFeeAsync(userId: number, fee: number): (boolean, number)
	ensureServer()
	local safeFee = clampCash(fee)
	if safeFee <= 0 then
		return true, EconomyStore.loadCashAsync(userId)
	end

	local finalBalance = STARTING_CASH
	local ok, err = pcall(function()
		store:UpdateAsync(keyForUserId(userId), function(current)
			local currentCash = if typeof(current) == "number" then clampCash(current) else STARTING_CASH
			finalBalance = clampCash(currentCash + safeFee)
			return finalBalance
		end)
	end)

	if not ok then
		warn(string.format("[EconomyStore] refundEntryFeeAsync failed for %d: %s", userId, tostring(err)))
		return false, EconomyStore.loadCashAsync(userId)
	end

	return true, finalBalance
end

return EconomyStore
