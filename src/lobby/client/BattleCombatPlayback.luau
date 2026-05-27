--!strict
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:WaitForChild("Shared")
local BattleCombatPlaybackConfig = require(shared:WaitForChild("BattleCombatPlaybackConfig"))
local BattleCombatSim = require(shared:WaitForChild("BattleCombatSim"))
local BattleLayoutTypes = require(shared:WaitForChild("BattleLayoutTypes"))
local SplashKillFishFrames = require(shared:WaitForChild("SplashKillFishFrames"))

local BattlePlacementHud = require(script.Parent:WaitForChild("BattlePlacementHud"))

type BattleSide = BattleLayoutTypes.BattleSide
type SideLayout = BattleLayoutTypes.SideLayout
type BattleCombatEvent = BattleLayoutTypes.BattleCombatEvent
type GridLayoutInfo = BattlePlacementHud.GridLayoutInfo

type UnitWidget = {
	uid: number?,
	root: Frame,
	hpFill: Frame,
	side: BattleSide,
	col: number,
	row: number,
	hp: number,
	maxHp: number,
}

export type PlayOptions = {
	layoutA: SideLayout,
	layoutB: SideLayout,
	eventLog: { BattleCombatEvent },
	grid: GridLayoutInfo,
	onComplete: () -> (),
}

local M = {}

local activeCancel: (() -> boolean)? = nil
local skipButton: TextButton? = nil

type LiveSession = {
	widgetsByUid: { [number]: UnitWidget },
	layoutWidgets: { [string]: UnitWidget },
	overlay: Frame,
	cellSize: number,
	pad: number,
	onBaseHpChanged: ((number, number) -> ())?,
}

local liveSession: LiveSession? = nil

local function unitKey(side: BattleSide, col: number, row: number): string
	return side .. ":" .. tostring(col) .. ":" .. tostring(row)
end

local function widgetKeyFor(uid: number?, side: BattleSide, col: number, row: number): string
	if uid ~= nil then
		return "uid:" .. tostring(uid)
	end
	return unitKey(side, col, row)
end

local function tweenProps(
	instance: Instance,
	props: { [string]: any },
	duration: number,
	easingStyle: Enum.EasingStyle?,
	easingDirection: Enum.EasingDirection?
): Tween
	local info = TweenInfo.new(
		duration,
		easingStyle or Enum.EasingStyle.Quad,
		easingDirection or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

local function waitTween(tween: Tween, cancelled: (() -> boolean)?): boolean
	if cancelled then
		while tween.PlaybackState == Enum.PlaybackState.Playing do
			if cancelled() then
				tween:Cancel()
				return false
			end
			task.wait()
		end
		return true
	end
	tween.Completed:Wait()
	return true
end

local function waitSeconds(seconds: number, cancelled: () -> boolean): boolean
	local elapsed = 0
	while elapsed < seconds do
		if cancelled() then
			return false
		end
		local dt = task.wait()
		elapsed += dt
	end
	return true
end

local function makeUnitWidget(
	overlay: Frame,
	side: BattleSide,
	col: number,
	row: number,
	imageId: string,
	hp: number,
	maxHp: number,
	cellSize: number,
	uid: number?
): UnitWidget
	local cx, cy = BattlePlacementHud.cellCenterOffset(col, row)

	local root = Instance.new("Frame")
	root.Name = "Unit_" .. widgetKeyFor(uid, side, col, row)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(cellSize * 0.88, cellSize * 0.88)
	root.Position = UDim2.fromOffset(cx, cy)
	root.BackgroundTransparency = 1
	root.ZIndex = 2
	root.Parent = overlay

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.Size = UDim2.fromScale(0.85, 0.85)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.BackgroundTransparency = 1
	art.Image = imageId
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = root
	SplashKillFishFrames.applyFullImageToLabel(art)

	local hpBg = Instance.new("Frame")
	hpBg.Name = "HpBg"
	hpBg.AnchorPoint = Vector2.new(0.5, 1)
	hpBg.Position = UDim2.new(0.5, 0, 1, -2)
	hpBg.Size = UDim2.new(0.85, 0, 0, 5)
	hpBg.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	hpBg.BorderSizePixel = 0
	hpBg.Parent = root

	local hpBgCorner = Instance.new("UICorner")
	hpBgCorner.CornerRadius = UDim.new(0, 2)
	hpBgCorner.Parent = hpBg

	local hpFill = Instance.new("Frame")
	hpFill.Name = "HpFill"
	hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
	hpFill.BackgroundColor3 = if side == "A" then Color3.fromRGB(80, 180, 255) else Color3.fromRGB(255, 90, 90)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBg

	local hpFillCorner = Instance.new("UICorner")
	hpFillCorner.CornerRadius = UDim.new(0, 2)
	hpFillCorner.Parent = hpFill

	return {
		uid = uid,
		root = root,
		hpFill = hpFill,
		side = side,
		col = col,
		row = row,
		hp = hp,
		maxHp = maxHp,
	}
end

local function positionUnitAt(widget: UnitWidget, col: number, row: number)
	local cx, cy = BattlePlacementHud.cellCenterOffset(col, row)
	widget.col = col
	widget.row = row
	widget.root.Position = UDim2.fromOffset(cx, cy)
end

local function updateHpBar(widget: UnitWidget, hp: number, duration: number)
	widget.hp = hp
	local ratio = if widget.maxHp > 0 then math.clamp(hp / widget.maxHp, 0, 1) else 0
	tweenProps(widget.hpFill, { Size = UDim2.fromScale(ratio, 1) }, duration)
end

local function spawnDamagePopup(overlay: Frame, col: number, row: number, damage: number, cellSize: number)
	local tile = BattlePlacementHud.cellSizeAt(col, row)
	local cx, cy = BattlePlacementHud.cellCenterOffset(col, row)
	local label = Instance.new("TextLabel")
	label.Name = "DamagePopup"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(cx, cy - tile * 0.2)
	label.Size = UDim2.fromOffset(48, 24)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = math.max(14, math.floor(tile * 0.32))
	label.TextColor3 = Color3.fromRGB(255, 90, 70)
	label.TextStrokeTransparency = 0.4
	label.Text = "-" .. tostring(damage)
	label.ZIndex = 20
	label.Parent = overlay

	tweenProps(
		label,
		{ Position = UDim2.fromOffset(cx, cy - tile * 0.55) },
		BattleCombatPlaybackConfig.DAMAGE_POPUP_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	tweenProps(
		label,
		{ TextTransparency = 1, TextStrokeTransparency = 1 },
		BattleCombatPlaybackConfig.DAMAGE_POPUP_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	task.delay(BattleCombatPlaybackConfig.DAMAGE_POPUP_DURATION, function()
		label:Destroy()
	end)
end

local function flashCell(overlay: Frame, col: number, row: number, cellSize: number, _pad: number)
	local x, y = BattlePlacementHud.cellTopLeft(col, row)
	local tile = BattlePlacementHud.cellSizeAt(col, row)
	local flash = Instance.new("Frame")
	flash.Name = "CellFlash"
	flash.Position = UDim2.fromOffset(x, y)
	flash.Size = UDim2.fromOffset(tile, tile)
	flash.BackgroundColor3 = Color3.fromRGB(255, 120, 80)
	flash.BackgroundTransparency = 0.5
	flash.BorderSizePixel = 0
	flash.ZIndex = 1
	flash.Parent = overlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = flash

	local tween = tweenProps(
		flash,
		{ BackgroundTransparency = 1 },
		BattleCombatPlaybackConfig.CELL_FLASH_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	tween.Completed:Connect(function()
		flash:Destroy()
	end)
end

local function removeUnitWidget(widget: UnitWidget)
	local tween = tweenProps(
		widget.root,
		{ Size = UDim2.fromOffset(0, 0) },
		BattleCombatPlaybackConfig.DEATH_FADE_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.In
	)
	tween.Completed:Connect(function()
		widget.root:Destroy()
	end)
end

local function ensureSkipButton(parent: Frame): TextButton
	if skipButton and skipButton.Parent then
		skipButton.Visible = true
		return skipButton
	end
	local btn = Instance.new("TextButton")
	btn.Name = "SkipCombat"
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -12, 0, 8)
	btn.Size = UDim2.fromOffset(100, 32)
	btn.BackgroundColor3 = Color3.fromRGB(48, 52, 64)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.TextColor3 = Color3.fromRGB(220, 220, 230)
	btn.Text = "SKIP"
	btn.ZIndex = 50
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	skipButton = btn
	return btn
end

local function buildInitialUnits(
	overlay: Frame,
	layoutA: SideLayout,
	layoutB: SideLayout,
	cellSize: number
): { [string]: UnitWidget }
	local widgets: { [string]: UnitWidget } = {}
	for _, sim in BattleCombatSim.buildUnitsFromLayout("A", layoutA) do
		local w = makeUnitWidget(overlay, "A", sim.col, sim.row, sim.imageId, sim.hp, sim.maxHp, cellSize, nil)
		widgets[unitKey("A", sim.col, sim.row)] = w
	end
	for _, sim in BattleCombatSim.buildUnitsFromLayout("B", layoutB) do
		local w = makeUnitWidget(overlay, "B", sim.col, sim.row, sim.imageId, sim.hp, sim.maxHp, cellSize, nil)
		widgets[unitKey("B", sim.col, sim.row)] = w
	end
	return widgets
end

local function spawnLayoutUnits(
	session: LiveSession,
	layoutA: SideLayout,
	layoutB: SideLayout
)
	for _, sim in BattleCombatSim.buildUnitsFromLayout("A", layoutA) do
		local w = makeUnitWidget(
			session.overlay,
			"A",
			sim.col,
			sim.row,
			sim.imageId,
			sim.hp,
			sim.maxHp,
			session.cellSize,
			nil
		)
		session.layoutWidgets[unitKey("A", sim.col, sim.row)] = w
	end
	for _, sim in BattleCombatSim.buildUnitsFromLayout("B", layoutB) do
		local w = makeUnitWidget(
			session.overlay,
			"B",
			sim.col,
			sim.row,
			sim.imageId,
			sim.hp,
			sim.maxHp,
			session.cellSize,
			nil
		)
		session.layoutWidgets[unitKey("B", sim.col, sim.row)] = w
	end
end

local function adoptLayoutWidget(session: LiveSession, snap: BattleLayoutTypes.CombatUnitSnapshot): UnitWidget?
	local key = unitKey(snap.side, snap.col, snap.row)
	local widget = session.layoutWidgets[key]
	if not widget then
		return nil
	end
	session.layoutWidgets[key] = nil
	widget.uid = snap.uid
	session.widgetsByUid[snap.uid] = widget
	return widget
end

local function clearLayoutWidgets(session: LiveSession)
	for _, widget in session.layoutWidgets do
		if widget.root.Parent then
			widget.root:Destroy()
		end
	end
	table.clear(session.layoutWidgets)
end

local function playAttackLunge(
	attacker: UnitWidget,
	attackerCol: number,
	attackerRow: number,
	targetCol: number,
	targetRow: number,
	attackDur: number,
	isCancelled: (() -> boolean)?
): boolean
	local atkCx, atkCy = BattlePlacementHud.cellCenterOffset(attackerCol, attackerRow)
	local tgtCx, tgtCy = BattlePlacementHud.cellCenterOffset(targetCol, targetRow)
	local lungeX = atkCx + (tgtCx - atkCx) * 0.35
	local lungeY = atkCy + (tgtCy - atkCy) * 0.35
	local lungeTween = tweenProps(
		attacker.root,
		{ Position = UDim2.fromOffset(lungeX, lungeY) },
		attackDur * 0.45,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	if isCancelled and not waitTween(lungeTween, isCancelled) then
		return false
	elseif not isCancelled then
		waitTween(lungeTween, nil)
	end
	local returnTween = tweenProps(
		attacker.root,
		{ Position = UDim2.fromOffset(atkCx, atkCy) },
		attackDur * 0.55,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	if isCancelled and not waitTween(returnTween, isCancelled) then
		return false
	elseif not isCancelled then
		waitTween(returnTween, nil)
	end
	positionUnitAt(attacker, attackerCol, attackerRow)
	return true
end

local function processEvent(
	ev: BattleCombatEvent,
	widgets: { [string]: UnitWidget },
	overlay: Frame,
	cellSize: number,
	pad: number,
	moveDur: number,
	attackDur: number,
	hitPause: number,
	isCancelled: (() -> boolean)?,
	onBaseHpChanged: ((number, number) -> ())?
): boolean
	if isCancelled and isCancelled() then
		return false
	end

	if ev.kind == "summon" then
		local uid = (ev :: any).uid
		local key = widgetKeyFor(uid, ev.side, ev.col, ev.row)
		if not widgets[key] then
			widgets[key] = makeUnitWidget(overlay, ev.side, ev.col, ev.row, ev.imageId, ev.hp, ev.maxHp, cellSize, uid)
		end
		if isCancelled then
			return waitSeconds(hitPause, isCancelled)
		end
		return true
	elseif ev.kind == "baseDamage" then
		local atkKey = unitKey(ev.attackerSide, ev.attackerCol, ev.attackerRow)
		local attacker = widgets[atkKey]
		if attacker then
			if
				not playAttackLunge(
					attacker,
					ev.attackerCol,
					ev.attackerRow,
					ev.targetCol,
					ev.targetRow,
					attackDur,
					isCancelled
				)
			then
				return false
			end
		end

		flashCell(overlay, ev.targetCol, ev.targetRow, cellSize, pad)
		spawnDamagePopup(overlay, ev.targetCol, ev.targetRow, ev.damage, cellSize)

		if isCancelled then
			return waitSeconds(hitPause, isCancelled)
		end
		return true
	elseif ev.kind == "move" then
		local key = unitKey(ev.side, ev.fromCol, ev.fromRow)
		local widget = widgets[key]
		if widget then
			widgets[key] = nil
			local newKey = unitKey(ev.side, ev.toCol, ev.toRow)
			widgets[newKey] = widget
			local fromCx, fromCy = BattlePlacementHud.cellCenterOffset(ev.fromCol, ev.fromRow)
			local toCx, toCy = BattlePlacementHud.cellCenterOffset(ev.toCol, ev.toRow)
			widget.root.Position = UDim2.fromOffset(fromCx, fromCy)
			local tween = tweenProps(
				widget.root,
				{ Position = UDim2.fromOffset(toCx, toCy) },
				moveDur,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			if isCancelled and not waitTween(tween, isCancelled) then
				return false
			elseif not isCancelled then
				waitTween(tween, nil)
			end
			positionUnitAt(widget, ev.toCol, ev.toRow)
		end
		if isCancelled then
			return waitSeconds(hitPause, isCancelled)
		end
		return true
	elseif ev.kind == "attack" then
		local atkKey = unitKey(ev.attackerSide, ev.attackerCol, ev.attackerRow)
		local attacker = widgets[atkKey]
		local target: UnitWidget? = nil
		local tgtKey: string? = nil
		for key, widget in widgets do
			if widget.col == ev.targetCol and widget.row == ev.targetRow then
				target = widget
				tgtKey = key
				break
			end
		end

		if attacker then
			if
				not playAttackLunge(
					attacker,
					ev.attackerCol,
					ev.attackerRow,
					ev.targetCol,
					ev.targetRow,
					attackDur,
					isCancelled
				)
			then
				return false
			end
		end

		flashCell(overlay, ev.targetCol, ev.targetRow, cellSize, pad)
		spawnDamagePopup(overlay, ev.targetCol, ev.targetRow, ev.damage, cellSize)

		if target and tgtKey then
			updateHpBar(target, ev.targetHpAfter, attackDur * 0.5)
			if ev.targetHpAfter <= 0 then
				widgets[tgtKey] = nil
				task.delay(attackDur * 0.5, function()
					if target.root.Parent then
						removeUnitWidget(target)
					end
				end)
			end
		end
		if isCancelled then
			return waitSeconds(hitPause, isCancelled)
		end
		return true
	end
	return true
end

local function computeEventDuration(eventLog: { BattleCombatEvent }): number
	local moveCost = BattleCombatPlaybackConfig.MOVE_DURATION + BattleCombatPlaybackConfig.HIT_PAUSE
	local attackCost = BattleCombatPlaybackConfig.ATTACK_LUNGE_DURATION
		+ BattleCombatPlaybackConfig.HIT_PAUSE
	local total = 0
	for _, ev in eventLog do
		if ev.kind == "move" then
			total += moveCost
		elseif ev.kind == "attack" then
			total += attackCost
		elseif ev.kind == "summon" then
			total += moveCost
		elseif ev.kind == "baseDamage" then
			total += attackCost
		end
	end
	return total
end

function M.cancel()
	if activeCancel then
		activeCancel()
		activeCancel = nil
	end
	M.endLive()
	if skipButton then
		skipButton.Visible = false
	end
end

function M.isLive(): boolean
	return liveSession ~= nil
end

export type BeginLiveOptions = {
	layoutA: SideLayout,
	layoutB: SideLayout,
	grid: GridLayoutInfo,
	onBaseHpChanged: ((number, number) -> ())?,
}

function M.beginLive(options: BeginLiveOptions)
	M.endLive()
	local grid = options.grid
	liveSession = {
		widgetsByUid = {},
		layoutWidgets = {},
		overlay = grid.combatOverlay,
		cellSize = grid.cellSize,
		pad = grid.pad,
		onBaseHpChanged = options.onBaseHpChanged,
	}
	spawnLayoutUnits(liveSession, options.layoutA, options.layoutB)
end

function M.endLive()
	if liveSession then
		for _, widget in liveSession.widgetsByUid do
			if widget.root.Parent then
				widget.root:Destroy()
			end
		end
		clearLayoutWidgets(liveSession)
		liveSession = nil
	end
end

local function processLiveEvent(
	ev: BattleCombatEvent,
	widgetsByUid: { [number]: UnitWidget },
	overlay: Frame,
	cellSize: number,
	pad: number,
	moveDur: number,
	attackDur: number,
	hitPause: number,
	isCancelled: (() -> boolean)?
): boolean
	if isCancelled and isCancelled() then
		return false
	end

	if ev.kind == "summon" then
		local uid = (ev :: any).uid
		if typeof(uid) == "number" and not widgetsByUid[uid] then
			widgetsByUid[uid] = makeUnitWidget(overlay, ev.side, ev.col, ev.row, ev.imageId, ev.hp, ev.maxHp, cellSize, uid)
		end
		if isCancelled then
			return waitSeconds(hitPause, isCancelled)
		end
		return true
	elseif ev.kind == "move" then
		local uid = (ev :: any).uid
		if typeof(uid) == "number" then
			local widget = widgetsByUid[uid]
			if widget then
				local fromCx, fromCy = BattlePlacementHud.cellCenterOffset(ev.fromCol, ev.fromRow)
				local toCx, toCy = BattlePlacementHud.cellCenterOffset(ev.toCol, ev.toRow)
				widget.root.Position = UDim2.fromOffset(fromCx, fromCy)
				local tween = tweenProps(
					widget.root,
					{ Position = UDim2.fromOffset(toCx, toCy) },
					moveDur,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				)
				if isCancelled and not waitTween(tween, isCancelled) then
					return false
				elseif not isCancelled then
					waitTween(tween, nil)
				end
				positionUnitAt(widget, ev.toCol, ev.toRow)
			end
		end
		if isCancelled then
			return waitSeconds(hitPause, isCancelled)
		end
		return true
	elseif ev.kind == "attack" then
		local attackerUid = (ev :: any).attackerUid
		local targetUid = (ev :: any).targetUid
		local attacker = if typeof(attackerUid) == "number" then widgetsByUid[attackerUid] else nil
		local target = if typeof(targetUid) == "number" then widgetsByUid[targetUid] else nil

		if attacker then
			if not playAttackLunge(attacker, ev.attackerCol, ev.attackerRow, ev.targetCol, ev.targetRow, attackDur, isCancelled) then
				return false
			end
		end

		flashCell(overlay, ev.targetCol, ev.targetRow, cellSize, pad)
		spawnDamagePopup(overlay, ev.targetCol, ev.targetRow, ev.damage, cellSize)

		if target then
			updateHpBar(target, ev.targetHpAfter, attackDur * 0.5)
			if ev.targetHpAfter <= 0 then
				widgetsByUid[targetUid :: number] = nil
				task.delay(attackDur * 0.5, function()
					if target.root.Parent then
						removeUnitWidget(target)
					end
				end)
			end
		end

		if isCancelled then
			return waitSeconds(hitPause, isCancelled)
		end
		return true
	elseif ev.kind == "baseDamage" then
		local attackerUid = (ev :: any).attackerUid
		local attacker = if typeof(attackerUid) == "number" then widgetsByUid[attackerUid] else nil
		if attacker then
			if not playAttackLunge(attacker, ev.attackerCol, ev.attackerRow, ev.targetCol, ev.targetRow, attackDur, isCancelled) then
				return false
			end
		end

		flashCell(overlay, ev.targetCol, ev.targetRow, cellSize, pad)
		spawnDamagePopup(overlay, ev.targetCol, ev.targetRow, ev.damage, cellSize)

		if isCancelled then
			return waitSeconds(hitPause, isCancelled)
		end
		return true
	end

	return true
end

function M.applyLiveTick(update: BattleLayoutTypes.BattleCombatUpdatePayload)
	local session = liveSession
	if not session then
		return
	end
	local moveDur = BattleCombatPlaybackConfig.LIVE_MOVE_DURATION
	local attackDur = BattleCombatPlaybackConfig.LIVE_ATTACK_DURATION
	local hitPause = BattleCombatPlaybackConfig.LIVE_HIT_PAUSE

	task.spawn(function()
		-- Track which units are animated by events this tick,
		-- so we don't "snap" them back to snapshots mid-animation.
		local animatedThisTick: { [number]: true } = {}
		for _, ev in update.events do
			if ev.kind == "move" then
				local uid = (ev :: any).uid
				if typeof(uid) == "number" then
					animatedThisTick[uid] = true
				end
			elseif ev.kind == "attack" then
				local attackerUid = (ev :: any).attackerUid
				local targetUid = (ev :: any).targetUid
				if typeof(attackerUid) == "number" then
					animatedThisTick[attackerUid] = true
				end
				if typeof(targetUid) == "number" then
					animatedThisTick[targetUid] = true
				end
			elseif ev.kind == "baseDamage" then
				local attackerUid = (ev :: any).attackerUid
				if typeof(attackerUid) == "number" then
					animatedThisTick[attackerUid] = true
				end
			end
		end

		for _, ev in update.events do
			if
				not processLiveEvent(
					ev,
					session.widgetsByUid,
					session.overlay,
					session.cellSize,
					session.pad,
					moveDur,
					attackDur,
					hitPause,
					nil
				)
			then
				break
			end
		end

		-- Reconcile from authoritative snapshots so we never keep "ghost" units.
		local seen: { [number]: true } = {}
		for _, snap in update.units do
			seen[snap.uid] = true
			local widget = session.widgetsByUid[snap.uid]
			if not widget then
				widget = adoptLayoutWidget(session, snap)
			end
			if not widget then
				widget = makeUnitWidget(
					session.overlay,
					snap.side,
					snap.col,
					snap.row,
					snap.imageId,
					snap.hp,
					snap.maxHp,
					session.cellSize,
					snap.uid
				)
				session.widgetsByUid[snap.uid] = widget
			end
			widget.side = snap.side
			widget.maxHp = snap.maxHp
			-- Smoothly correct position/HP for units not actively animated by events.
			if not animatedThisTick[snap.uid] then
				local cx, cy = BattlePlacementHud.cellCenterOffset(snap.col, snap.row)
				tweenProps(
					widget.root,
					{ Position = UDim2.fromOffset(cx, cy) },
					math.max(0.05, moveDur * 0.75),
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				)
				widget.col = snap.col
				widget.row = snap.row
				updateHpBar(widget, snap.hp, 0.06)
			else
				-- Still keep internal state consistent (without snapping visuals).
				widget.col = snap.col
				widget.row = snap.row
				widget.hp = snap.hp
			end
		end
		for uid, widget in session.widgetsByUid do
			if not seen[uid] then
				session.widgetsByUid[uid] = nil
				if widget.root.Parent then
					widget.root:Destroy()
				end
			end
		end
		clearLayoutWidgets(session)

		if session.onBaseHpChanged then
			session.onBaseHpChanged(update.baseHpA, update.baseHpB)
		end
	end)
end

function M.play(options: PlayOptions)
	M.cancel()

	local grid = options.grid
	local overlay = grid.combatOverlay
	local cellSize = grid.cellSize
	local pad = grid.pad
	local eventLog = options.eventLog

	local cancelled = false
	local function isCancelled(): boolean
		return cancelled
	end

	activeCancel = function()
		cancelled = true
		return true
	end

	local skip = ensureSkipButton(overlay.Parent :: Frame)
	skip.MouseButton1Click:Connect(function()
		M.cancel()
	end)

	local widgets = buildInitialUnits(overlay, options.layoutA, options.layoutB, cellSize)

	local baseDuration = computeEventDuration(eventLog)
	local speedMult = 1
	if baseDuration > BattleCombatPlaybackConfig.MAX_PLAYBACK_SECONDS and baseDuration > 0 then
		speedMult = baseDuration / BattleCombatPlaybackConfig.MAX_PLAYBACK_SECONDS
	end

	local moveDur = BattleCombatPlaybackConfig.MOVE_DURATION / speedMult
	local attackDur = BattleCombatPlaybackConfig.ATTACK_LUNGE_DURATION / speedMult
	local hitPause = BattleCombatPlaybackConfig.HIT_PAUSE / speedMult

	task.spawn(function()
		for _, ev in eventLog do
			if not processEvent(ev, widgets, overlay, cellSize, pad, moveDur, attackDur, hitPause, isCancelled, nil) then
				break
			end
		end

		M.endLive()
		activeCancel = nil
		for _, widget in widgets do
			if widget.root.Parent then
				widget.root:Destroy()
			end
		end
		options.onComplete()
	end)
end

return M
