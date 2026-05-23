local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local DailySpinStore = require(shared:WaitForChild("DailySpinStore"))
local Money = require(shared:WaitForChild("Money"))

local REMOTES_NAME = "LobbyRemotes"
local SPIN_RESULT_NAME = "DailySpinResult"
local REQUEST_SPIN_NAME = "RequestDailySpin"

local DEBOUNCE_SECONDS = 1.5
local lastTriggerAtByUserId: { [number]: number } = {}
local didBind = false

local M = {}

local function getOrCreateRemotesFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = REMOTES_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local folder = getOrCreateRemotesFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function fireSpinResult(player: Player, payload: { [string]: unknown })
	ensureRemoteEvent(SPIN_RESULT_NAME):FireClient(player, payload)
end

local function rollAmount(): number
	return math.random(1, 6) * 25
end

function M.requestSpin(player: Player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local userId = player.UserId
	local now = os.clock()
	if (lastTriggerAtByUserId[userId] or 0) + DEBOUNCE_SECONDS > now then
		return
	end
	lastTriggerAtByUserId[userId] = now

	local claimedOk, alreadySpun, storeFailed = DailySpinStore.tryClaimTodayAsync(userId)

	if storeFailed then
		fireSpinResult(player, {
			ok = false,
			message = "Could not verify daily spin. Try again in a moment.",
		})
		return
	end

	if alreadySpun then
		fireSpinResult(player, {
			ok = false,
			alreadySpun = true,
			message = "You already spun today. Come back tomorrow!",
		})
		return
	end

	if not claimedOk then
		fireSpinResult(player, {
			ok = false,
			message = "Could not complete spin. Try again.",
		})
		return
	end

	local amount = rollAmount()
	Money.addCash(player, amount)

	fireSpinResult(player, {
		ok = true,
		amount = amount,
		message = string.format("You won $%d!", amount),
	})
end

function M.bindRequestRemotes()
	if didBind then
		return
	end
	didBind = true

	local requestRemote = ensureRemoteEvent(REQUEST_SPIN_NAME)
	requestRemote.OnServerEvent:Connect(function(player: Player)
		M.requestSpin(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastTriggerAtByUserId[player.UserId] = nil
	end)
end

return M
