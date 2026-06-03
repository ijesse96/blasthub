--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local bgShared = ServerScriptService:WaitForChild("BattleGroundsShared")
local shared = ReplicatedStorage:WaitForChild("Shared")
local BattleGridConfig = require(bgShared:WaitForChild("BattleGridConfig"))
local BattleGridSides = require(bgShared:WaitForChild("BattleGridSides"))
local BattleCombatEngine = require(bgShared:WaitForChild("BattleCombatEngine"))
local BattleLayoutTypes = require(shared:WaitForChild("BattleLayoutTypes"))
local BattleUnitStats = require(shared:WaitForChild("BattleUnitStats"))
local FishCollectionService = require(shared:WaitForChild("FishCollectionService"))
local SplashFishCatalog = require(shared:WaitForChild("SplashFishCatalog"))

type BattleSide = BattleLayoutTypes.BattleSide
type PlacementUnit = BattleLayoutTypes.PlacementUnit
type SideLayout = BattleLayoutTypes.SideLayout
type BattlePlacementStatePayload = BattleLayoutTypes.BattlePlacementStatePayload
type BattleResultPayload = BattleLayoutTypes.BattleResultPayload
type BattleCombatUpdatePayload = BattleLayoutTypes.BattleCombatUpdatePayload
type BattleCombatEvent = BattleLayoutTypes.BattleCombatEvent

type BenchEntry = {
	imageId: string,
	level: number,
	manaCost: number,
}

local BOT_USER_ID = 0
local IS_STUDIO = RunService:IsStudio()
local STUDIO_FISH_PER_TIER = 2

local REMOTES_NAME = "BattleGroundsRemotes"
local REMOTE_JOIN = "JoinBattleQueue"
local REMOTE_LEAVE = "LeaveBattleQueue"
local REMOTE_MATCH_FOUND = "MatchFound"
local REMOTE_STATE = "BattlePlacementState"
local REMOTE_RESULT = "BattleResult"
local REMOTE_QUEUE_STATUS = "BattleQueueStatus"
local REMOTE_COMBAT_UPDATE = "BattleCombatUpdate"

type BattleSession = {
	id: string,
	userIdA: number,
	userIdB: number,
	layoutA: SideLayout,
	layoutB: SideLayout,
	benchA: { BenchEntry },
	benchB: { BenchEntry },
	readyA: boolean,
	readyB: boolean,
	phase: "placement" | "combat" | "ended",
	botSideB: boolean,
	combatState: BattleCombatEngine.CombatState?,
	combatLoopId: number?,
	accumulatedEvents: { BattleCombatEvent }?,
}

local queue: { number } = {}
local sessionByUserId: { [number]: BattleSession } = {}
local sessionIdCounter = 0
local didBind = false

local M = {}

local function getRemotesFolder(): Folder
	return ReplicatedStorage:WaitForChild(REMOTES_NAME) :: Folder
end

local function getRemote(name: string): RemoteEvent
	return getRemotesFolder():WaitForChild(name) :: RemoteEvent
end

local function nextSessionId(): string
	sessionIdCounter += 1
	return "bg_" .. tostring(sessionIdCounter) .. "_" .. tostring(math.floor(os.clock() * 1000))
end

local function getOwnedMap(userId: number): { [string]: number }
	local snapshot = FishCollectionService.getCachedSnapshot(userId)
	return snapshot[BattleGridConfig.MAP_ID] or {}
end

local function countOwnedFish(userId: number): number
	local owned = getOwnedMap(userId)
	local n = 0
	for _, count in owned do
		if count > 0 then
			n += 1
		end
	end
	return n
end

local function ensureBattleFish(player: Player): boolean
	if countOwnedFish(player.UserId) >= 1 then
		return true
	end
	if not IS_STUDIO then
		return false
	end

	for _, tier in SplashFishCatalog.getOrderedTiers() do
		local ids = SplashFishCatalog.getIdsForTier(BattleGridConfig.MAP_ID, tier)
		if #ids == 0 then
			continue
		end
		for i = 1, math.min(STUDIO_FISH_PER_TIER, #ids) do
			FishCollectionService.grantFishToPlayer(player, BattleGridConfig.MAP_ID, ids[i])
		end
	end

	local species = countOwnedFish(player.UserId)
	print(string.format("[BattleGrounds] Studio fish seed for %s: %d species", player.Name, species))
	return species >= 1
end

local function validateOwnedFish(userId: number, imageId: string): (boolean, number)
	local owned = getOwnedMap(userId)
	local count = owned[imageId]
	if not count or count <= 0 then
		return false, 0
	end
	if not SplashFishCatalog.getTierForImageId(BattleGridConfig.MAP_ID, imageId) then
		return false, 0
	end
	return true, count
end

local function sideForUser(session: BattleSession, userId: number): BattleSide?
	if userId == session.userIdA then
		return "A"
	end
	if userId == session.userIdB then
		return "B"
	end
	return nil
end

local function sideCells(side: BattleSide): { { col: number, row: number } }
	local cells: { { col: number, row: number } } = {}
	for row = 0, BattleGridConfig.ROWS - 1 do
		for col = 0, BattleGridConfig.COLS - 1 do
			if BattleGridSides.cellInSide(col, row, side) then
				table.insert(cells, { col = col, row = row })
			end
		end
	end
	return cells
end

local function buildFieldAndBench(userId: number, side: BattleSide): (SideLayout, { BenchEntry })
	local owned = getOwnedMap(userId)
	local entries: { { imageId: string, count: number } } = {}
	for imageId, count in owned do
		if count > 0 then
			table.insert(entries, { imageId = imageId, count = count })
		end
	end
	table.sort(entries, function(a, b)
		return a.count > b.count
	end)

	local cells = sideCells(side)
	local layout: SideLayout = {}
	local bench: { BenchEntry } = {}

	for i, entry in entries do
		local level = BattleUnitStats.getLevelFromCopyCount(entry.count)
		local manaCost = BattleUnitStats.getManaCostForFish(BattleGridConfig.MAP_ID, entry.imageId)
		if i <= #cells then
			local cell = cells[i]
			table.insert(layout, {
				imageId = entry.imageId,
				col = cell.col,
				row = cell.row,
				level = level,
			})
		else
			table.insert(bench, {
				imageId = entry.imageId,
				level = level,
				manaCost = manaCost,
			})
		end
	end

	return layout, bench
end

local function countLayout(layout: SideLayout): number
	return #layout
end

local function playerInfo(userId: number, layout: SideLayout, ready: boolean, isBot: boolean?): BattleLayoutTypes.PlayerBattleInfo
	local name = "Bot"
	if userId > 0 then
		local plr = Players:GetPlayerByUserId(userId)
		name = if plr then plr.DisplayName else ("Player" .. tostring(userId))
	end
	return {
		userId = userId,
		name = name,
		placedCount = countLayout(layout),
		ready = ready,
		isBot = isBot,
	}
end

local function buildStateForPlayer(session: BattleSession, userId: number): BattlePlacementStatePayload?
	local side = sideForUser(session, userId)
	if not side then
		return nil
	end
	local payload: BattlePlacementStatePayload = {
		sessionId = session.id,
		mode = "live_1v1",
		phase = session.phase,
		localSide = side,
		placementEndServerTime = 0,
		playerA = playerInfo(session.userIdA, session.layoutA, session.readyA, false),
		playerB = playerInfo(session.userIdB, session.layoutB, session.readyB, session.botSideB),
		layoutA = session.layoutA,
		layoutB = session.layoutB,
		maxBaseHp = BattleGridConfig.STARTING_BASE_HP,
		maxMana = BattleGridConfig.MAX_MANA,
	}
	if session.combatState then
		payload.baseHpA = session.combatState.baseHpA
		payload.baseHpB = session.combatState.baseHpB
		payload.manaA = session.combatState.manaA
		payload.manaB = session.combatState.manaB
	end
	return payload
end

local function broadcastState(session: BattleSession)
	local remote = getRemote(REMOTE_STATE)
	for _, userId in { session.userIdA, session.userIdB } do
		if userId > 0 and (userId ~= session.userIdB or not session.botSideB) then
			local plr = Players:GetPlayerByUserId(userId)
			if plr then
				local payload = buildStateForPlayer(session, userId)
				if payload then
					remote:FireClient(plr, payload)
				end
			end
		end
	end
end

local function removeFromQueue(userId: number)
	for i = #queue, 1, -1 do
		if queue[i] == userId then
			table.remove(queue, i)
		end
	end
end

local function stopCombatLoop(session: BattleSession)
	session.combatLoopId = (session.combatLoopId or 0) + 1
	session.combatState = nil
end

local function endSession(session: BattleSession)
	stopCombatLoop(session)
	session.phase = "ended"
	if session.userIdA > 0 then
		sessionByUserId[session.userIdA] = nil
	end
	if session.userIdB > 0 then
		sessionByUserId[session.userIdB] = nil
	end
end

local function fireCombatUpdate(session: BattleSession, events: { BattleCombatEvent })
	if not session.combatState then
		return
	end
	local payload: BattleCombatUpdatePayload = {
		sessionId = session.id,
		tick = session.combatState.tick,
		baseHpA = session.combatState.baseHpA,
		baseHpB = session.combatState.baseHpB,
		manaA = session.combatState.manaA,
		manaB = session.combatState.manaB,
		maxBaseHp = BattleGridConfig.STARTING_BASE_HP,
		maxMana = BattleGridConfig.MAX_MANA,
		units = BattleCombatEngine.buildUnitSnapshots(session.combatState),
		events = events,
	}
	local remote = getRemote(REMOTE_COMBAT_UPDATE)
	for _, userId in { session.userIdA, session.userIdB } do
		if userId > 0 and (userId ~= session.userIdB or not session.botSideB) then
			local plr = Players:GetPlayerByUserId(userId)
			if plr then
				remote:FireClient(plr, payload)
			end
		end
	end
end

local function fireResult(session: BattleSession, payload: BattleResultPayload)
	local remote = getRemote(REMOTE_RESULT)
	for _, userId in { session.userIdA, session.userIdB } do
		if userId > 0 then
			local plr = Players:GetPlayerByUserId(userId)
			if plr then
				remote:FireClient(plr, payload)
			end
		end
	end
end

local function finishCombat(session: BattleSession, winnerSide: BattleSide?, reason: string)
	if session.phase ~= "combat" then
		return
	end
	local winnerUserId: number? = nil
	if winnerSide == "A" then
		winnerUserId = session.userIdA
	elseif winnerSide == "B" then
		winnerUserId = if session.botSideB then BOT_USER_ID else session.userIdB
	elseif reason ~= "forfeit" then
		reason = "tie"
	end

	local finalBaseHpA: number? = nil
	local finalBaseHpB: number? = nil
	if session.combatState then
		finalBaseHpA = session.combatState.baseHpA
		finalBaseHpB = session.combatState.baseHpB
	end

	fireResult(session, {
		sessionId = session.id,
		winnerSide = winnerSide,
		winnerUserId = winnerUserId,
		reason = reason,
		eventLog = session.accumulatedEvents or {},
		finalBaseHpA = finalBaseHpA,
		finalBaseHpB = finalBaseHpB,
	})
	endSession(session)
end

local function isCellOccupiedInState(state: BattleCombatEngine.CombatState, col: number, row: number): boolean
	for _, u in state.units do
		if u.hp > 0 and u.col == col and u.row == row then
			return true
		end
	end
	for _, p in state.pendingSummons do
		if p.col == col and p.row == row then
			return true
		end
	end
	return false
end

local function tryAutoSummonFromBench(session: BattleSession, side: BattleSide)
	if not session.combatState then
		return
	end
	local bench = if side == "A" then session.benchA else session.benchB
	if #bench == 0 then
		return
	end

	local state = session.combatState
	local entry = bench[1]
	if BattleCombatEngine.getMana(state, side) < entry.manaCost then
		return
	end

	local emptyCells: { { col: number, row: number } } = {}
	for _, cell in sideCells(side) do
		if not isCellOccupiedInState(state, cell.col, cell.row) then
			table.insert(emptyCells, cell)
		end
	end
	if #emptyCells == 0 then
		return
	end

	local cell = emptyCells[math.random(1, #emptyCells)]
	if BattleCombatEngine.tryQueueSummon(state, side, entry.imageId, cell.col, cell.row, entry.level, entry.manaCost) then
		table.remove(bench, 1)
	end
end

local function runCombatLoop(session: BattleSession)
	if session.phase ~= "placement" then
		return
	end
	session.phase = "combat"
	session.combatState = BattleCombatEngine.createState(session.layoutA, session.layoutB)
	session.accumulatedEvents = {}
	session.combatLoopId = (session.combatLoopId or 0) + 1
	local loopId = session.combatLoopId
	print("[BattleGrounds] Combat rules:", BattleCombatEngine.COMBAT_RULES_VERSION)
	broadcastState(session)
	fireCombatUpdate(session, {})

	task.spawn(function()
		while session.phase == "combat" and session.combatLoopId == loopId and session.combatState do
			task.wait(BattleGridConfig.COMBAT_TICK_INTERVAL)
			if session.phase ~= "combat" or session.combatLoopId ~= loopId or not session.combatState then
				break
			end

			if session.combatState.tick % BattleGridConfig.BOT_SUMMON_EVERY_TICKS == 0 then
				tryAutoSummonFromBench(session, "A")
				tryAutoSummonFromBench(session, "B")
			end

			local events, winnerSide = BattleCombatEngine.step(session.combatState)
			for _, ev in events do
				table.insert(session.accumulatedEvents, ev)
			end
			fireCombatUpdate(session, events)
			broadcastState(session)

			if winnerSide then
				local reason = if session.combatState.baseHpA <= 0 or session.combatState.baseHpB <= 0
					then "base_destroyed"
					else "combat"
				finishCombat(session, winnerSide, reason)
				break
			elseif session.combatState.tick >= BattleGridConfig.MAX_COMBAT_TICKS then
				local timeoutWinner = BattleCombatEngine.resolveTimeoutWinner(session.combatState)
				finishCombat(session, timeoutWinner, if timeoutWinner then "combat" else "tie")
				break
			end
		end
	end)
end

local function autoFillAndStart(session: BattleSession, userIdA: number, userIdB: number, botSideB: boolean)
	local layoutA, benchA = buildFieldAndBench(userIdA, "A")
	session.layoutA = layoutA
	session.benchA = benchA
	session.readyA = true

	local benchSourceId = if botSideB then userIdA else userIdB
	local layoutB, benchB = buildFieldAndBench(benchSourceId, "B")
	session.layoutB = layoutB
	session.benchB = benchB
	session.readyB = true

	broadcastState(session)
	if IS_STUDIO then
		print(
			"[BattleGrounds] Battle started — field units A:",
			#layoutA,
			" B:",
			#layoutB,
			" bench A:",
			#benchA,
			" bench B:",
			#benchB
		)
	end
	runCombatLoop(session)
end

function M.createSession(userIdA: number, userIdB: number, botSideB: boolean)
	local session: BattleSession = {
		id = nextSessionId(),
		userIdA = userIdA,
		userIdB = if botSideB then BOT_USER_ID else userIdB,
		layoutA = {},
		layoutB = {},
		benchA = {},
		benchB = {},
		readyA = false,
		readyB = false,
		phase = "placement",
		botSideB = botSideB,
		combatState = nil,
		combatLoopId = 0,
		accumulatedEvents = {},
	}
	sessionByUserId[userIdA] = session
	if not botSideB then
		sessionByUserId[userIdB] = session
	end

	local matchRemote = getRemote(REMOTE_MATCH_FOUND)
	local plrA = Players:GetPlayerByUserId(userIdA)
	if plrA then
		matchRemote:FireClient(plrA, { sessionId = session.id, opponentUserId = session.userIdB })
	end

	task.defer(function()
		if sessionByUserId[userIdA] == session then
			autoFillAndStart(session, userIdA, userIdB, botSideB)
		end
	end)
end

local function tryPairQueue()
	while #queue >= 2 do
		local a = table.remove(queue, 1)
		local b = table.remove(queue, 1)
		if a and b then
			local plrA = Players:GetPlayerByUserId(a)
			local plrB = Players:GetPlayerByUserId(b)
			if plrA and plrB then
				M.createSession(a, b, false)
			else
				if plrA then
					table.insert(queue, 1, a)
				end
				if plrB then
					table.insert(queue, 1, b)
				end
				break
			end
		end
	end
end

local function trySoloBotPair(userId: number)
	task.delay(3, function()
		if sessionByUserId[userId] then
			return
		end
		local stillQueued = false
		for _, id in queue do
			if id == userId then
				stillQueued = true
				break
			end
		end
		if stillQueued then
			removeFromQueue(userId)
			M.createSession(userId, BOT_USER_ID, true)
		end
	end)
end

local function fireQueueStatus(player: Player, inQueue: boolean, message: string?)
	getRemote(REMOTE_QUEUE_STATUS):FireClient(player, {
		inQueue = inQueue,
		message = message,
	})
end

function M.onJoinQueue(player: Player)
	if sessionByUserId[player.UserId] then
		fireQueueStatus(player, false, "Already in a battle.")
		return
	end
	if not ensureBattleFish(player) then
		fireQueueStatus(player, false, "Collect at least one fish before battling.")
		return
	end
	for _, id in queue do
		if id == player.UserId then
			fireQueueStatus(player, true, nil)
			return
		end
	end
	table.insert(queue, player.UserId)
	fireQueueStatus(player, true, nil)
	tryPairQueue()
	trySoloBotPair(player.UserId)
end

function M.onLeaveQueue(player: Player)
	removeFromQueue(player.UserId)
	fireQueueStatus(player, false, nil)
end

function M.onPlayerRemoving(player: Player)
	removeFromQueue(player.UserId)
	local session = sessionByUserId[player.UserId]
	if not session then
		return
	end
	if session.phase == "combat" then
		local winnerSide: BattleSide = if player.UserId == session.userIdA then "B" else "A"
		finishCombat(session, winnerSide, "forfeit")
		return
	end
	endSession(session)
end

function M.bindRemotes()
	if didBind then
		return
	end
	didBind = true

	getRemote(REMOTE_JOIN).OnServerEvent:Connect(function(player: Player)
		M.onJoinQueue(player)
	end)
	getRemote(REMOTE_LEAVE).OnServerEvent:Connect(function(player: Player)
		M.onLeaveQueue(player)
	end)
	Players.PlayerRemoving:Connect(M.onPlayerRemoving)
end

return M
