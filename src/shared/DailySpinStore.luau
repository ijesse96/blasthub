local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local STORE_NAME = "DailySpinLastDate_v1"

-- Dev/testing: set false before release to enforce one spin per UTC day.
local DISABLE_DAILY_SPIN_LIMIT = true

local store = DataStoreService:GetDataStore(STORE_NAME)

local DailySpinStore = {}

local function ensureServer()
	if not RunService:IsServer() then
		error("[DailySpinStore] Server-only module.")
	end
end

local function keyForUserId(userId: number): string
	return string.format("spin_%d", userId)
end

-- Calendar day in UTC (matches typical Roblox server expectations).
local function todayUtcString(): string
	return DateTime.now():FormatUniversalTime("YYYY-MM-DD", "en-us")
end

-- Returns: claimedOk (grant cash), alreadySpunToday, storeFailed
function DailySpinStore.tryClaimTodayAsync(userId: number): (boolean, boolean, boolean)
	ensureServer()
	if DISABLE_DAILY_SPIN_LIMIT then
		return true, false, false
	end

	local todayStr = todayUtcString()
	local key = keyForUserId(userId)

	-- If any transform invocation advances lastSpin from "not today" to today, grant once.
	-- Retries that only see last == todayStr do not clear this flag.
	local shouldGrant = false

	local ok, err = pcall(function()
		store:UpdateAsync(key, function(current: unknown)
			local last = if typeof(current) == "string" then current :: string else ""
			if last == todayStr then
				return last
			end
			shouldGrant = true
			return todayStr
		end)
	end)

	if not ok then
		warn(string.format("[DailySpinStore] tryClaimTodayAsync failed for %d: %s", userId, tostring(err)))
		return false, false, true
	end

	if shouldGrant then
		return true, false, false
	end

	return false, true, false
end

return DailySpinStore
