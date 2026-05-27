--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local BattleGridConfig = require(shared:WaitForChild("BattleGridConfig"))
local BattleGridSides = require(shared:WaitForChild("BattleGridSides"))
local BattleCombatEngine = require(shared:WaitForChild("BattleCombatEngine"))
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

local BOT_USER_ID = 0
local IS_STUDIO = RunService:IsStudio()
local STUDIO_BOT_DELAY_SECONDS = 1.5

local REMOTES_NAME = "LobbyRemotes"
local REMOTE_JOIN = "JoinBattleQueue"
local REMOTE_LEAVE = "LeaveBattleQueue"
local REMOTE_MATCH_FOUND = "MatchFound"
local REMOTE_STATE = "BattlePlacementState"
local REMOTE_ACTION = "BattlePlacementAction"
local REMOTE_READY = "BattleSetReady"
local REMOTE_RESULT = "BattleResult"
local REMOTE_QUEUE_STATUS = "BattleQueueStatus"
local REMOTE_COMBAT_UPDATE = "BattleCombatUpdate"
local REMOTE_SUMMON = "BattleSummon"

type BattleSession = {
	id: string,
	userIdA: number,
	userIdB: number,
	layoutA: SideLayout,
	layoutB: SideLayout,
	readyA: boolean,
	readyB: boolean,
	phase: "placement" | "combat" | "ended",
	placementEndServerTime: number,
	botSideB: boolean,
	combatState: BattleCombatEngine.CombatState?,
	combatLoopId: number?,
	accumulatedEvents: { BattleCombatEvent }?,
}

local queue: { number } = {}
local sessionByUserId: { [number]: BattleSession } = {}
local sessionIdCounter = 0
local lastActionAtByUserId: { [number]: number } = {}
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
	return "battle_" .. tostring(sessionIdCounter) .. "_" .. tostring(math.floor(os.clock() * 1000))
end

local function countOwnedFish(userId: number): number
	local snapshot = FishCollectionService.getCachedSnapshot(userId)
	local mapData = snapshot[BattleGridConfig.MAP_ID]
	if not mapData then
		return 0
	end
	local n = 0
	for _, count in mapData do
		if count > 0 then
			n += 1
		end
	end
	return n
end

local function getOwnedMap(userId: number): { [string]: number }
	local snapshot = FishCollectionService.getCachedSnapshot(userId)
	return snapshot[BattleGridConfig.MAP_ID] or {}
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

local function layoutForSide(session: BattleSession, side: BattleSide): SideLayout
	if side == "A" then
		return session.layoutA
	end
	return session.layoutB
end

local function setLayoutForSide(session: BattleSession, side: BattleSide, layout: SideLayout)
	if side == "A" then
		session.layoutA = layout
	else
		session.layoutB = layout
	end
end

local function countLayout(layout: SideLayout): number
	return #layout
end

local function findAt(layout: SideLayout, col: number, row: number): PlacementUnit?
	for _, unit in layout do
		if unit.col == col and unit.row == row then
			return unit
		end
	end
	return nil
end

local function findByImageId(layout: SideLayout, imageId: string): PlacementUnit?
	for _, unit in layout do
		if unit.imageId == imageId then
			return unit
		end
	end
	return nil
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
		placementEndServerTime = session.placementEndServerTime,
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
	if session.userIdA > 0 then
		local plr = Players:GetPlayerByUserId(session.userIdA)
		if plr then
			local payload = buildStateForPlayer(session, session.userIdA)
			if payload then
				remote:FireClient(plr, payload)
			end
		end
	end
	if not session.botSideB and session.userIdB > 0 then
		local plr = Players:GetPlayerByUserId(session.userIdB)
		if plr then
			local payload = buildStateForPlayer(session, session.userIdB)
			if payload then
				remote:FireClient(plr, payload)
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
	if session.userIdA > 0 then
		local plr = Players:GetPlayerByUserId(session.userIdA)
		if plr then
			remote:FireClient(plr, payload)
		end
	end
	if not session.botSideB and session.userIdB > 0 then
		local plr = Players:GetPlayerByUserId(session.userIdB)
		if plr then
			remote:FireClient(plr, payload)
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

	local result: BattleResultPayload = {
		sessionId = session.id,
		winnerSide = winnerSide,
		winnerUserId = winnerUserId,
		reason = reason,
		eventLog = session.accumulatedEvents or {},
		finalBaseHpA = finalBaseHpA,
		finalBaseHpB = finalBaseHpB,
	}
	fireResult(session, result)
	endSession(session)
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

local function canAct(player: Player): boolean
	local now = os.clock()
	local last = lastActionAtByUserId[player.UserId]
	if last and now - last < BattleGridConfig.REMOTE_COOLDOWN_SECONDS then
		return false
	end
	lastActionAtByUserId[player.UserId] = now
	return true
end

local function tryBotSummon(session: BattleSession)
	if not session.botSideB or not session.combatState then
		return
	end
	local state = session.combatState
	local owned = getOwnedMap(session.userIdA)
	local ids: { string } = {}
	for imageId, count in owned do
		if count > 0 then
			table.insert(ids, imageId)
		end
	end
	if #ids == 0 then
		return
	end

	local emptyCells: { { col: number, row: number } } = {}
	for col = 0, BattleGridConfig.COLS - 1 do
		for row = 0, BattleGridConfig.SIDE_B_MAX_ROW do
			local occupied = false
			for _, u in state.units do
				if u.hp > 0 and u.col == col and u.row == row then
					occupied = true
					break
				end
			end
			if not occupied then
				for _, p in state.pendingSummons do
					if p.col == col and p.row == row then
						occupied = true
						break
					end
				end
			end
			if not occupied then
				table.insert(emptyCells, { col = col, row = row })
			end
		end
	end
	if #emptyCells == 0 then
		return
	end

	table.sort(ids)
	local imageId = ids[math.random(1, #ids)]
	local _, copyCount = validateOwnedFish(session.userIdA, imageId)
	local level = BattleUnitStats.getLevelFromCopyCount(copyCount)
	local manaCost = BattleUnitStats.getManaCostForFish(BattleGridConfig.MAP_ID, imageId)
	if BattleCombatEngine.getMana(state, "B") < manaCost then
		return
	end
	local cell = emptyCells[math.random(1, #emptyCells)]
	BattleCombatEngine.tryQueueSummon(state, "B", imageId, cell.col, cell.row, level, manaCost)
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
	print("[Battle] Combat rules:", BattleCombatEngine.COMBAT_RULES_VERSION)
	broadcastState(session)
	-- Tick 0: units still at placement cells before the first sim step.
	fireCombatUpdate(session, {})

	task.spawn(function()
		while session.phase == "combat" and session.combatLoopId == loopId and session.combatState do
			task.wait(BattleGridConfig.COMBAT_TICK_INTERVAL)
			if session.phase ~= "combat" or session.combatLoopId ~= loopId or not session.combatState then
				break
			end

			if session.botSideB and session.combatState.tick % BattleGridConfig.BOT_SUMMON_EVERY_TICKS == 0 then
				tryBotSummon(session)
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

local function bothReady(session: BattleSession): boolean
	return session.readyA and session.readyB
end

local function tryStartCombat(session: BattleSession)
	if session.phase ~= "placement" then
		return
	end
	local timerExpired = BattleGridConfig.PLACEMENT_TIMER_ENABLED
		and Workspace:GetServerTimeNow() >= session.placementEndServerTime
	if bothReady(session) or timerExpired then
		runCombatLoop(session)
	end
end

local function runBotPlacement(session: BattleSession)
	if not session.botSideB then
		return
	end
	local owned = getOwnedMap(session.userIdA)
	local ids: { string } = {}
	for imageId, count in owned do
		if count > 0 then
			table.insert(ids, imageId)
		end
	end
	if #ids == 0 then
		session.readyB = true
		return
	end

	local layout: SideLayout = {}
	local maxPlace = math.min(BattleGridConfig.MAX_UNITS_PER_SIDE, math.min(6, #ids))
	for i = 1, maxPlace do
		local imageId = ids[((i - 1) % #ids) + 1]
		local _, copyCount = validateOwnedFish(session.userIdA, imageId)
		local level = BattleUnitStats.getLevelFromCopyCount(copyCount)
		local col = (i - 1) % BattleGridConfig.COLS
		local row = math.floor((i - 1) / BattleGridConfig.COLS) % (BattleGridConfig.SIDE_B_MAX_ROW + 1)
		table.insert(layout, {
			imageId = imageId,
			col = col,
			row = row,
			level = level,
		})
	end
	session.layoutB = layout
	session.readyB = true
	broadcastState(session)
	tryStartCombat(session)
end

function M.createSession(userIdA: number, userIdB: number, botSideB: boolean)
	local session: BattleSession = {
		id = nextSessionId(),
		userIdA = userIdA,
		userIdB = if botSideB then BOT_USER_ID else userIdB,
		layoutA = {},
		layoutB = {},
		readyA = false,
		readyB = false,
		phase = "placement",
		placementEndServerTime = if BattleGridConfig.PLACEMENT_TIMER_ENABLED
			then Workspace:GetServerTimeNow() + BattleGridConfig.PLACEMENT_SECONDS
			else Workspace:GetServerTimeNow() + 86400 * 365,
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
	if not botSideB then
		local plrB = Players:GetPlayerByUserId(userIdB)
		if plrB then
			matchRemote:FireClient(plrB, { sessionId = session.id, opponentUserId = userIdA })
		end
	end

	broadcastState(session)

	if botSideB then
		task.delay(STUDIO_BOT_DELAY_SECONDS, function()
			if sessionByUserId[userIdA] == session and session.phase == "placement" then
				runBotPlacement(session)
			end
		end)
	end

	if BattleGridConfig.PLACEMENT_TIMER_ENABLED then
		task.delay(BattleGridConfig.PLACEMENT_SECONDS + 0.25, function()
			if session.phase == "placement" and (sessionByUserId[userIdA] == session or sessionByUserId[session.userIdB] == session) then
				session.readyA = true
				session.readyB = true
				tryStartCombat(session)
			end
		end)
	end
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

local function tryStudioBotPair(userId: number)
	if not IS_STUDIO then
		return
	end
	task.delay(2, function()
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
	if countOwnedFish(player.UserId) < 1 then
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
	tryStudioBotPair(player.UserId)
end

function M.onLeaveQueue(player: Player)
	removeFromQueue(player.UserId)
	fireQueueStatus(player, false, nil)
end

function M.onSetReady(player: Player)
	local session = sessionByUserId[player.UserId]
	if not session or session.phase ~= "placement" then
		return
	end
	local side = sideForUser(session, player.UserId)
	if side == "A" then
		session.readyA = true
	elseif side == "B" then
		session.readyB = true
	end
	broadcastState(session)
	tryStartCombat(session)
end

function M.onPlacementAction(player: Player, payload: any)
	if not canAct(player) then
		return
	end
	local session = sessionByUserId[player.UserId]
	if not session or session.phase ~= "placement" then
		return
	end
	local side = sideForUser(session, player.UserId)
	if not side then
		return
	end
	if (side == "A" and session.readyA) or (side == "B" and session.readyB) then
		return
	end

	if typeof(payload) ~= "table" then
		return
	end
	local action = payload.action
	local layout = layoutForSide(session, side)
	local newLayout: SideLayout = {}
	for _, u in layout do
		table.insert(newLayout, u)
	end

	if action == "place" then
		local imageId = payload.imageId
		local col = payload.col
		local row = payload.row
		if typeof(imageId) ~= "string" or typeof(col) ~= "number" or typeof(row) ~= "number" then
			return
		end
		col = math.floor(col)
		row = math.floor(row)
		if not BattleGridSides.cellInSide(col, row, side) then
			return
		end
		if countLayout(newLayout) >= BattleGridConfig.MAX_UNITS_PER_SIDE then
			return
		end
		if findAt(newLayout, col, row) or findByImageId(newLayout, imageId) then
			return
		end
		local ok, copyCount = validateOwnedFish(player.UserId, imageId)
		if not ok then
			return
		end
		table.insert(newLayout, {
			imageId = imageId,
			col = col,
			row = row,
			level = BattleUnitStats.getLevelFromCopyCount(copyCount),
		})
	elseif action == "remove" then
		local col = payload.col
		local row = payload.row
		if typeof(col) ~= "number" or typeof(row) ~= "number" then
			return
		end
		col = math.floor(col)
		row = math.floor(row)
		local filtered: SideLayout = {}
		for _, u in newLayout do
			if not (u.col == col and u.row == row) then
				table.insert(filtered, u)
			end
		end
		newLayout = filtered
	elseif action == "move" then
		local fromCol = payload.fromCol
		local fromRow = payload.fromRow
		local toCol = payload.toCol
		local toRow = payload.toRow
		if typeof(fromCol) ~= "number" or typeof(fromRow) ~= "number" or typeof(toCol) ~= "number" or typeof(toRow) ~= "number" then
			return
		end
		fromCol = math.floor(fromCol)
		fromRow = math.floor(fromRow)
		toCol = math.floor(toCol)
		toRow = math.floor(toRow)
		if not BattleGridSides.cellInSide(toCol, toRow, side) then
			return
		end
		local unit = findAt(newLayout, fromCol, fromRow)
		if not unit or findAt(newLayout, toCol, toRow) then
			return
		end
		local moved: SideLayout = {}
		for _, u in newLayout do
			if u.col == fromCol and u.row == fromRow then
				table.insert(moved, {
					imageId = u.imageId,
					col = toCol,
					row = toRow,
					level = u.level,
				})
			else
				table.insert(moved, u)
			end
		end
		newLayout = moved
	else
		return
	end

	setLayoutForSide(session, side, newLayout)
	broadcastState(session)
end

function M.onBattleSummon(player: Player, payload: any)
	if not canAct(player) then
		return
	end
	local session = sessionByUserId[player.UserId]
	if not session or session.phase ~= "combat" or not session.combatState then
		return
	end
	local side = sideForUser(session, player.UserId)
	if not side then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local imageId = payload.imageId
	local col = payload.col
	local row = payload.row
	if typeof(imageId) ~= "string" or typeof(col) ~= "number" or typeof(row) ~= "number" then
		return
	end
	col = math.floor(col)
	row = math.floor(row)
	local ok, copyCount = validateOwnedFish(player.UserId, imageId)
	if not ok then
		return
	end
	local level = BattleUnitStats.getLevelFromCopyCount(copyCount)
	local manaCost = BattleUnitStats.getManaCostForFish(BattleGridConfig.MAP_ID, imageId)
	if not BattleCombatEngine.tryQueueSummon(session.combatState, side, imageId, col, row, level, manaCost) then
		return
	end
	broadcastState(session)
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
	local opponentId = if player.UserId == session.userIdA then session.userIdB else session.userIdA
	endSession(session)
	if opponentId > 0 and not session.botSideB then
		local winPayload: BattleResultPayload = {
			sessionId = session.id,
			winnerSide = if player.UserId == session.userIdA then "B" else "A",
			winnerUserId = opponentId,
			reason = "forfeit",
			eventLog = {},
		}
		local plr = Players:GetPlayerByUserId(opponentId)
		if plr then
			getRemote(REMOTE_RESULT):FireClient(plr, winPayload)
		end
	end
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
	getRemote(REMOTE_READY).OnServerEvent:Connect(function(player: Player)
		M.onSetReady(player)
	end)
	getRemote(REMOTE_ACTION).OnServerEvent:Connect(function(player: Player, payload: any)
		M.onPlacementAction(player, payload)
	end)
	getRemote(REMOTE_SUMMON).OnServerEvent:Connect(function(player: Player, payload: any)
		M.onBattleSummon(player, payload)
	end)

	Players.PlayerRemoving:Connect(M.onPlayerRemoving)
end

return M
