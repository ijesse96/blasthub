local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Money = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Money"))

local SAVE_DEBOUNCE_SECONDS = 1.5

local saveTokenByUserId: { [number]: number } = {}
local cashChangedConnectionByUserId: { [number]: RBXScriptConnection } = {}

local function scheduleSave(player: Player)
	local userId = player.UserId
	local nextToken = (saveTokenByUserId[userId] or 0) + 1
	saveTokenByUserId[userId] = nextToken

	task.delay(SAVE_DEBOUNCE_SECONDS, function()
		if saveTokenByUserId[userId] ~= nextToken then
			return
		end
		if not player:IsDescendantOf(Players) then
			return
		end
		Money.saveCashToStoreAsync(player)
	end)
end

local function onPlayerAdded(player: Player)
	local cash = Money.setupPlayer(player)
	Money.loadCashFromStoreAsync(player)

	local conn = cash:GetPropertyChangedSignal("Value"):Connect(function()
		scheduleSave(player)
	end)
	cashChangedConnectionByUserId[player.UserId] = conn
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	local userId = player.UserId
	local conn = cashChangedConnectionByUserId[userId]
	if conn then
		conn:Disconnect()
		cashChangedConnectionByUserId[userId] = nil
	end

	saveTokenByUserId[userId] = nil
	Money.saveCashToStoreAsync(player)
end)
