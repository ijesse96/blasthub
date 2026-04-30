local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local MatchMaps = require(shared:WaitForChild("MatchMaps"))
local Money = require(shared:WaitForChild("Money"))
local PlaceIds = require(shared:WaitForChild("PlaceIds"))
local MatchRoundBridge = require(script.Parent:WaitForChild("MatchRoundBridge"))

local INTERMISSION_SECONDS = 5
local ROUND_SECONDS = 120
local CONTINUE_PROMPT_SECONDS = 10
local MIN_HUMANS_FOR_FIRST_PLACE_BONUS = 2
local MIN_CONTINUE_YES_TO_START_NEXT_ROUND = 2

local REMOTES_FOLDER_NAME = "MatchRoundRemotes"
local STATE_EVENT_NAME = "RoundState"
local CONTINUE_PROMPT_EVENT_NAME = "ContinuePrompt"
local CONTINUE_RESPONSE_EVENT_NAME = "ContinueResponse"

type TeleportData = {
	kind: string?,
	mapId: string?,
}

local phase = "Idle"
local currentMapId: string? = nil
local currentRoundEndServerTime = 0
local lastLiveRoundBroadcastAt = 0

local pendingParticipants: { [number]: true } = {}
local activeRoundParticipants: { [number]: true } = {}
local skipOneContinueForUserId: { [number]: true } = {}
local continueChoiceByUserId: { [number]: boolean } = {}
local continueEligibleByUserId: { [number]: true } = {}
local coinsWonByUserId: { [number]: number } = {}
local coinsSpentByUserId: { [number]: number } = {}

type LeaderboardRow = {
	userId: number,
	name: string,
	netProfit: number,
}

local function getOrCreateRemotesFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local folder = getOrCreateRemotesFolder()
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	if remote then
		remote:Destroy()
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local stateEvent = ensureRemoteEvent(STATE_EVENT_NAME)
local continuePromptEvent = ensureRemoteEvent(CONTINUE_PROMPT_EVENT_NAME)
local continueResponseEvent = ensureRemoteEvent(CONTINUE_RESPONSE_EVENT_NAME)

local function parseTeleportData(player: Player): TeleportData
	local joinData = player:GetJoinData()
	local raw = if joinData then joinData.TeleportData else nil
	if typeof(raw) == "table" then
		local data = raw :: { [any]: any }
		return {
			kind = if typeof(data.kind) == "string" then data.kind else nil,
			mapId = if typeof(data.mapId) == "string" then data.mapId else nil,
		}
	end
	if typeof(raw) == "string" and raw == "from_lobby" then
		return { kind = "match", mapId = "main" }
	end
	return {}
end

local function isMatchJoin(player: Player): (boolean, string?)
	local data = parseTeleportData(player)
	if data.kind == "match" and data.mapId and MatchMaps.getMapById(data.mapId) then
		return true, data.mapId
	end
	return false, nil
end

local function broadcastState(extra: { [string]: any }?)
	local payload = {
		phase = phase,
		mapId = currentMapId,
		roundEndServerTime = currentRoundEndServerTime,
	}
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	stateEvent:FireAllClients(payload)
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local function teleportPlayersToLobby(playersList: { Player })
	if #playersList == 0 then
		return
	end
	if PlaceIds.Lobby == 0 then
		warn("[MatchRoundSession] PlaceIds.Lobby is 0; cannot teleport players to lobby.")
		return
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(PlaceIds.Lobby, playersList)
	end)
	if not ok then
		warn(string.format("[MatchRoundSession] teleport to lobby failed: %s", tostring(err)))
	end
end

local function countSet(setMap: { [number]: true }): number
	local count = 0
	for _ in setMap do
		count += 1
	end
	return count
end

local function getNetProfitForUserId(userId: number): number
	return (coinsWonByUserId[userId] or 0) - (coinsSpentByUserId[userId] or 0)
end

local function buildLeaderboardRows(): { LeaderboardRow }
	local rows: { LeaderboardRow } = {}
	for userId in activeRoundParticipants do
		local player = getPlayerByUserId(userId)
		table.insert(rows, {
			userId = userId,
			name = if player then player.Name else tostring(userId),
			netProfit = getNetProfitForUserId(userId),
		})
	end
	table.sort(rows, function(a, b)
		if a.netProfit == b.netProfit then
			return a.userId < b.userId
		end
		return a.netProfit > b.netProfit
	end)
	return rows
end

local function maybeBroadcastActiveRoundState()
	if phase ~= "ActiveRound" then
		return
	end
	local now = os.clock()
	if now - lastLiveRoundBroadcastAt < 0.5 then
		return
	end
	lastLiveRoundBroadcastAt = now
	broadcastState({
		seconds = math.max(0, currentRoundEndServerTime - Workspace:GetServerTimeNow()),
		participantCount = countSet(activeRoundParticipants),
		leaderboard = buildLeaderboardRows(),
	})
end

local function startIntermission()
	phase = "Intermission"
	currentRoundEndServerTime = Workspace:GetServerTimeNow() + INTERMISSION_SECONDS
	broadcastState({
		seconds = INTERMISSION_SECONDS,
		leaderboard = {},
	})
	task.wait(INTERMISSION_SECONDS)
end

local function startActiveRound()
	phase = "ActiveRound"
	activeRoundParticipants = {}
	coinsWonByUserId = {}
	coinsSpentByUserId = {}
	lastLiveRoundBroadcastAt = 0
	for userId in pendingParticipants do
		activeRoundParticipants[userId] = true
		coinsWonByUserId[userId] = 0
		coinsSpentByUserId[userId] = 0
	end
	pendingParticipants = {}
	currentRoundEndServerTime = Workspace:GetServerTimeNow() + ROUND_SECONDS
	broadcastState({
		seconds = ROUND_SECONDS,
		participantCount = countSet(activeRoundParticipants),
		leaderboard = buildLeaderboardRows(),
	})
	task.wait(ROUND_SECONDS)
end

local function resolveContinuePhase(mapId: string)
	local map = MatchMaps.getMapById(mapId)
	if not map then
		return
	end

	phase = "ContinuePromptPhase"
	currentRoundEndServerTime = Workspace:GetServerTimeNow() + CONTINUE_PROMPT_SECONDS
	continueChoiceByUserId = {}
	continueEligibleByUserId = {}

	for userId in activeRoundParticipants do
		local player = getPlayerByUserId(userId)
		if player and player:IsDescendantOf(Players) then
			continueEligibleByUserId[userId] = true
			local cash = Money.setupPlayer(player)
			continuePromptEvent:FireClient(player, {
				visible = true,
				seconds = CONTINUE_PROMPT_SECONDS,
				entryFee = map.entryFee,
				canAfford = cash.Value >= map.entryFee,
				mapId = map.id,
			})
		end
	end

	broadcastState({
		seconds = CONTINUE_PROMPT_SECONDS,
	})

	task.wait(CONTINUE_PROMPT_SECONDS)

	local toLobby: { Player } = {}
	local continueCount = 0
	local justContinued: { [number]: true } = {}

	for userId in continueEligibleByUserId do
		local player = getPlayerByUserId(userId)
		if not player then
			continue
		end
		local wantsContinue = continueChoiceByUserId[userId] == true
		if wantsContinue then
			local debited, balanceAfter = Money.tryDebitEntryFeeAsync(userId, map.entryFee)
			if debited then
				local cash = Money.setupPlayer(player)
				cash.Value = balanceAfter
				justContinued[userId] = true
				continueCount += 1
			else
				table.insert(toLobby, player)
			end
		else
			table.insert(toLobby, player)
		end
	end

	if continueCount < MIN_CONTINUE_YES_TO_START_NEXT_ROUND then
		for userId in justContinued do
			local player = getPlayerByUserId(userId)
			if player then
				table.insert(toLobby, player)
			end
			justContinued[userId] = nil
		end
	end

	for userId in justContinued do
		pendingParticipants[userId] = true
	end

	for userId in skipOneContinueForUserId do
		local player = getPlayerByUserId(userId)
		if player and player:IsDescendantOf(Players) then
			pendingParticipants[userId] = true
			skipOneContinueForUserId[userId] = nil
		end
	end

	teleportPlayersToLobby(toLobby)
end

local function finishRound(mapId: string)
	phase = "RoundEndedResults"
	currentRoundEndServerTime = 0

	MatchRoundBridge.clearFishNow()

	local scoredHumanCount = countSet(activeRoundParticipants)
	local bonusEligible = scoredHumanCount >= MIN_HUMANS_FOR_FIRST_PLACE_BONUS
	local leaderboard = buildLeaderboardRows()
	local winnerName: string? = nil
	local winnerUserId: number? = nil
	local winnerNetProfit = 0
	local awardedBonus = 0

	if bonusEligible and #leaderboard > 0 then
		local top = leaderboard[1]
		local map = MatchMaps.getMapById(mapId)
		if map then
			local winnerPlayer = getPlayerByUserId(top.userId)
			if winnerPlayer then
				Money.addCash(winnerPlayer, map.firstPlaceBonus)
				winnerName = winnerPlayer.Name
				winnerUserId = top.userId
				winnerNetProfit = top.netProfit
				awardedBonus = map.firstPlaceBonus
			end
		end
	end

	broadcastState({
		bonusEligible = bonusEligible,
		scoredHumanCount = scoredHumanCount,
		leaderboard = leaderboard,
		winnerName = winnerName,
		winnerUserId = winnerUserId,
		winnerNetProfit = winnerNetProfit,
		bonusAmount = awardedBonus,
	})

	resolveContinuePhase(mapId)
end

continueResponseEvent.OnServerEvent:Connect(function(player: Player, wantsContinue: unknown)
	if phase ~= "ContinuePromptPhase" then
		return
	end
	if not continueEligibleByUserId[player.UserId] then
		return
	end
	continueChoiceByUserId[player.UserId] = wantsContinue == true
end)

Players.PlayerAdded:Connect(function(player: Player)
	local isMatch, mapId = isMatchJoin(player)
	if not isMatch or not mapId then
		return
	end

	currentMapId = mapId
	if phase == "ActiveRound" then
		-- Mid-round arrivals already paid lobby entry, so they skip one continue fee.
		skipOneContinueForUserId[player.UserId] = true
	else
		pendingParticipants[player.UserId] = true
	end
end)

MatchRoundBridge.setCallbacks({
	allowFishSpawn = function(): boolean
		return phase == "ActiveRound"
	end,
	allowShooting = function(player: Player?): boolean
		if phase ~= "ActiveRound" then
			return false
		end
		if not player then
			return false
		end
		return activeRoundParticipants[player.UserId] == true
	end,
	recordCoinWon = function(player: Player, amount: number)
		if phase ~= "ActiveRound" then
			return
		end
		if activeRoundParticipants[player.UserId] ~= true then
			return
		end
		coinsWonByUserId[player.UserId] = (coinsWonByUserId[player.UserId] or 0) + math.max(0, math.floor(amount + 0.5))
		maybeBroadcastActiveRoundState()
	end,
	recordCoinSpent = function(player: Player, amount: number)
		if phase ~= "ActiveRound" then
			return
		end
		if activeRoundParticipants[player.UserId] ~= true then
			return
		end
		coinsSpentByUserId[player.UserId] = (coinsSpentByUserId[player.UserId] or 0) + math.max(0, math.floor(amount + 0.5))
		maybeBroadcastActiveRoundState()
	end,
})

Players.PlayerRemoving:Connect(function(player: Player)
	local userId = player.UserId
	pendingParticipants[userId] = nil
	activeRoundParticipants[userId] = nil
	skipOneContinueForUserId[userId] = nil
	continueChoiceByUserId[userId] = nil
	continueEligibleByUserId[userId] = nil
end)

task.spawn(function()
	while true do
		if currentMapId == nil or countSet(pendingParticipants) == 0 then
			phase = "Idle"
			currentRoundEndServerTime = 0
			broadcastState()
			task.wait(1)
		else
			startIntermission()
			startActiveRound()
			finishRound(currentMapId)
		end
	end
end)
