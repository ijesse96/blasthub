local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local REMOTES_FOLDER_NAME = "MatchRoundRemotes"
local STATE_EVENT_NAME = "RoundState"
local CONTINUE_PROMPT_EVENT_NAME = "ContinuePrompt"
local CONTINUE_RESPONSE_EVENT_NAME = "ContinueResponse"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Workspace = game:GetService("Workspace")
local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local roundStateEvent = remotesFolder:WaitForChild(STATE_EVENT_NAME) :: RemoteEvent
local continuePromptEvent = remotesFolder:WaitForChild(CONTINUE_PROMPT_EVENT_NAME) :: RemoteEvent
local continueResponseEvent = remotesFolder:WaitForChild(CONTINUE_RESPONSE_EVENT_NAME) :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchRoundHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 90
screenGui.Parent = playerGui

-- Top-center round timer tab (`timerTabSubtitle` + `timerTabClock` updated in RenderStepped).
local TIMER_TAB_SIZE_COMPACT = UDim2.fromOffset(112, 36)
local TIMER_TAB_SIZE_INTERMISSION = UDim2.fromOffset(148, 56)

local roundTimerTab = Instance.new("Frame")
roundTimerTab.Name = "RoundTimerTab"
roundTimerTab.AnchorPoint = Vector2.new(0.5, 0)
roundTimerTab.Position = UDim2.new(0.5, 0, 0, 6)
roundTimerTab.Size = TIMER_TAB_SIZE_COMPACT
roundTimerTab.BackgroundColor3 = Color3.fromRGB(26, 30, 42)
roundTimerTab.BackgroundTransparency = 0.12
roundTimerTab.BorderSizePixel = 0
roundTimerTab.ZIndex = 1
roundTimerTab.Parent = screenGui

local timerTabCorner = Instance.new("UICorner")
timerTabCorner.CornerRadius = UDim.new(0, 8)
timerTabCorner.Parent = roundTimerTab

local timerTabStroke = Instance.new("UIStroke")
timerTabStroke.Color = Color3.fromRGB(90, 100, 130)
timerTabStroke.Transparency = 0.45
timerTabStroke.Thickness = 1
timerTabStroke.Parent = roundTimerTab

local timerTabPadding = Instance.new("UIPadding")
timerTabPadding.PaddingTop = UDim.new(0, 5)
timerTabPadding.PaddingBottom = UDim.new(0, 5)
timerTabPadding.PaddingLeft = UDim.new(0, 8)
timerTabPadding.PaddingRight = UDim.new(0, 8)
timerTabPadding.Parent = roundTimerTab

local timerTabListLayout = Instance.new("UIListLayout")
timerTabListLayout.Name = "TimerList"
timerTabListLayout.FillDirection = Enum.FillDirection.Vertical
timerTabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
timerTabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
timerTabListLayout.Padding = UDim.new(0, 3)
timerTabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
timerTabListLayout.Parent = roundTimerTab

local timerTabSubtitle = Instance.new("TextLabel")
timerTabSubtitle.Name = "TimerSubtitle"
timerTabSubtitle.LayoutOrder = 1
timerTabSubtitle.BackgroundTransparency = 1
timerTabSubtitle.Size = UDim2.new(1, 0, 0, 0)
timerTabSubtitle.AutomaticSize = Enum.AutomaticSize.Y
timerTabSubtitle.Font = Enum.Font.GothamBold
timerTabSubtitle.TextSize = 13
timerTabSubtitle.TextColor3 = Color3.fromRGB(190, 200, 230)
timerTabSubtitle.TextXAlignment = Enum.TextXAlignment.Center
timerTabSubtitle.TextYAlignment = Enum.TextYAlignment.Center
timerTabSubtitle.TextWrapped = true
timerTabSubtitle.Text = ""
timerTabSubtitle.Visible = false
timerTabSubtitle.Parent = roundTimerTab

local timerTabClock = Instance.new("TextLabel")
timerTabClock.Name = "TimerClock"
timerTabClock.LayoutOrder = 2
timerTabClock.BackgroundTransparency = 1
timerTabClock.Size = UDim2.new(1, 0, 1, 0)
timerTabClock.AutomaticSize = Enum.AutomaticSize.None
timerTabClock.Font = Enum.Font.GothamBold
timerTabClock.TextSize = 20
timerTabClock.TextColor3 = Color3.fromRGB(220, 230, 255)
timerTabClock.TextXAlignment = Enum.TextXAlignment.Center
timerTabClock.TextYAlignment = Enum.TextYAlignment.Center
timerTabClock.TextWrapped = false
timerTabClock.Text = "--"
timerTabClock.Parent = roundTimerTab

local continueFrame = Instance.new("Frame")
continueFrame.Name = "ContinuePrompt"
continueFrame.AnchorPoint = Vector2.new(0.5, 1)
continueFrame.Position = UDim2.new(0.5, 0, 1, -24)
continueFrame.Size = UDim2.fromOffset(460, 130)
continueFrame.BackgroundColor3 = Color3.fromRGB(18, 24, 20)
continueFrame.BackgroundTransparency = 0.2
continueFrame.Visible = false
continueFrame.ZIndex = 2
continueFrame.Parent = screenGui

local continueLabel = Instance.new("TextLabel")
continueLabel.BackgroundTransparency = 1
continueLabel.Position = UDim2.fromOffset(14, 10)
continueLabel.Size = UDim2.fromOffset(430, 48)
continueLabel.Font = Enum.Font.GothamBold
continueLabel.TextSize = 20
continueLabel.TextWrapped = true
continueLabel.TextColor3 = Color3.fromRGB(230, 245, 235)
continueLabel.Text = "Continue for $0?"
continueLabel.Parent = continueFrame

local yesButton = Instance.new("TextButton")
yesButton.Name = "Yes"
yesButton.Position = UDim2.fromOffset(24, 74)
yesButton.Size = UDim2.fromOffset(180, 40)
yesButton.BackgroundColor3 = Color3.fromRGB(46, 122, 64)
yesButton.Font = Enum.Font.GothamBold
yesButton.TextSize = 20
yesButton.TextColor3 = Color3.fromRGB(255, 255, 255)
yesButton.Text = "Yes"
yesButton.Parent = continueFrame

local noButton = Instance.new("TextButton")
noButton.Name = "No"
noButton.Position = UDim2.fromOffset(256, 74)
noButton.Size = UDim2.fromOffset(180, 40)
noButton.BackgroundColor3 = Color3.fromRGB(126, 44, 44)
noButton.Font = Enum.Font.GothamBold
noButton.TextSize = 20
noButton.TextColor3 = Color3.fromRGB(255, 255, 255)
noButton.Text = "No"
noButton.Parent = continueFrame

local PROFIT_BILLBOARD_NAME = "MatchRoundHudProfitBillboard"
local PROFIT_BILLBOARD_LABEL_NAME = "ProfitTextBillboard"
-- World profit readout: no panel fill, vivid green; enlarge BillboardGui.Size in Studio or here.
local PROFIT_TEXT_COLOR = Color3.fromRGB(72, 255, 140)
local PROFIT_TEXT_STROKE = Color3.fromRGB(0, 28, 12)
local PROFIT_BILLBOARD_SIZE = UDim2.fromOffset(110, 33)
-- Float along the board part's top normal (world +Y is wrong if the board is rotated).
local PROFIT_BILLBOARD_ABOVE_STUDS = 0.625
-- If true on the profit root (Part/Model), keep SurfaceGui on for Studio layout; default is billboard-only (no double text).
local MATCH_HUD_USE_SURFACE_GUI_ATTR = "MatchHudUseSurfaceGui"

local lastProfitBoardPayload: { [string]: any }?
local warnedMissingFloorBoard = false
local warnedMissingProfitBoardSlot: { [number]: boolean } = {}
local warnedMissingProfitBoardAdornee: { [number]: boolean } = {}
local profitBoardRetryScheduled = false

-- Matches Workspace > Floor Board children; order is first matching name per slot.
local PROFIT_BOARD_SLOTS: { { candidateNames: { string }, turretIndex: number } } = {
	{ candidateNames = { "Profit Board", "ProfitBoard" }, turretIndex = 1 },
	{ candidateNames = { "Profit Board 2" }, turretIndex = 2 },
	{ candidateNames = { "Profit Board 3" }, turretIndex = 3 },
	{ candidateNames = { "Profit Board 4" }, turretIndex = 4 },
}

local function findProfitBoardUnderFloor(floorBoard: Instance, candidateNames: { string }): Instance?
	for _, name in candidateNames do
		local inst = floorBoard:FindFirstChild(name)
		if inst and (inst:IsA("BasePart") or inst:IsA("Model")) then
			return inst
		end
	end
	return nil
end

local function getBillboardAdorneePart(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end
	if root:IsA("Model") then
		if root.PrimaryPart then
			return root.PrimaryPart
		end
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				return d
			end
		end
	end
	return nil
end

local function findSurfaceGuiUnderRoot(root: Instance): SurfaceGui?
	return root:FindFirstChildWhichIsA("SurfaceGui", true)
end

local function pickSurfaceProfitTextLabel(surfaceGui: SurfaceGui): TextLabel?
	local byName = surfaceGui:FindFirstChild("ProfitText", true)
	if byName and byName:IsA("TextLabel") then
		return byName
	end

	for _, ch in surfaceGui:GetChildren() do
		if ch:IsA("TextLabel") then
			return ch
		end
	end

	for _, d in surfaceGui:GetDescendants() do
		if d:IsA("TextLabel") then
			local lower = string.lower(d.Name)
			if string.find(lower, "profit", 1, true) then
				return d
			end
		end
	end

	local singleLabel: TextLabel?
	local textLabelCount = 0
	for _, d in surfaceGui:GetDescendants() do
		if d:IsA("TextLabel") then
			textLabelCount += 1
			singleLabel = d
		end
	end
	if textLabelCount == 1 and singleLabel then
		return singleLabel
	end

	return nil
end

local function setBillboardAbovePart(part: BasePart, bb: BillboardGui)
	bb.StudsOffsetWorldSpace = part.CFrame.UpVector * PROFIT_BILLBOARD_ABOVE_STUDS
end

local function clearOpaqueAncestorsToSurfaceGui(textLabel: TextLabel, surfaceGui: SurfaceGui)
	local p: Instance? = textLabel.Parent
	while p and p ~= surfaceGui do
		if p:IsA("Frame") or p:IsA("ScrollingFrame") or p:IsA("ImageLabel") or p:IsA("ImageButton") then
			local go = p :: GuiObject
			go.BackgroundTransparency = 1
			go.BorderSizePixel = 0
		end
		p = p.Parent
	end
end

local function ensureProfitBillboardLabel(part: BasePart): TextLabel
	local existing = part:FindFirstChild(PROFIT_BILLBOARD_NAME)
	if existing and existing:IsA("BillboardGui") then
		existing.Size = PROFIT_BILLBOARD_SIZE
		setBillboardAbovePart(part, existing)
		local tl = existing:FindFirstChild(PROFIT_BILLBOARD_LABEL_NAME)
		if tl and tl:IsA("TextLabel") then
			tl.BackgroundTransparency = 1
			tl.BorderSizePixel = 0
			tl.TextColor3 = PROFIT_TEXT_COLOR
			tl.TextStrokeColor3 = PROFIT_TEXT_STROKE
			tl.TextStrokeTransparency = 0.2
			return tl
		end
		local fallback = existing:FindFirstChildWhichIsA("TextLabel", true)
		if fallback and fallback:IsA("TextLabel") then
			return fallback
		end
		existing:Destroy()
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = PROFIT_BILLBOARD_NAME
	bb.Adornee = part
	bb.AlwaysOnTop = true
	bb.Size = PROFIT_BILLBOARD_SIZE
	setBillboardAbovePart(part, bb)
	bb.MaxDistance = 8000
	bb.LightInfluence = 0
	bb.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = PROFIT_BILLBOARD_LABEL_NAME
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = PROFIT_TEXT_COLOR
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = PROFIT_TEXT_STROKE
		label.Text = "Empty\n$0"
	label.Parent = bb

	return label
end

local function styleProfitBoard(label: TextLabel, surfaceGui: SurfaceGui)
	surfaceGui.Enabled = true
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 5
	surfaceGui.AlwaysOnTop = true
	surfaceGui.LightInfluence = 0

	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextTransparency = 0
	label.TextScaled = false
	label.TextSize = 15
	label.TextColor3 = PROFIT_TEXT_COLOR
	label.TextStrokeColor3 = PROFIT_TEXT_STROKE
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.GothamBlack
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.Size = UDim2.fromScale(1, 1)
end

local phaseValue = "Idle"
local roundEndServerTime = 0
local promptEndServerTime = 0
local promptEntryFee = 0
local promptCanAfford = false
local promptJoinNextRound = false

-- Block Roblox menu "Reset Character" during any non-Idle match phase (avoids breaking auto-seat).
local menuResetSink = Instance.new("BindableEvent")
menuResetSink.Event:Connect(function() end)
local menuResetPolicyToken = 0

local function clearMenuResetOverride()
	pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)
end

local function tryInstallMenuResetOverride(token: number)
	for _ = 1, 20 do
		if token ~= menuResetPolicyToken then
			return
		end
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", menuResetSink)
		end)
		if ok then
			return
		end
		task.wait(0.35)
	end
end

local function applyMenuResetPolicy()
	if phaseValue ~= "Idle" then
		menuResetPolicyToken += 1
		local token = menuResetPolicyToken
		task.defer(function()
			tryInstallMenuResetOverride(token)
		end)
	else
		menuResetPolicyToken += 1
		clearMenuResetOverride()
	end
end

local function isLocalPlayerInRoundLeaderboard(payload: { [string]: any }?): boolean
	if typeof(payload) ~= "table" then
		return false
	end
	local lb = payload.leaderboard
	if typeof(lb) ~= "table" then
		return false
	end
	for _, row in lb do
		if typeof(row) == "table" and row.userId == player.UserId then
			return true
		end
	end
	return false
end

local function formatSeconds(secondsLeft: number): string
	local clamped = math.max(0, math.ceil(secondsLeft))
	local minutes = math.floor(clamped / 60)
	local seconds = clamped % 60
	return string.format("%d:%02d", minutes, seconds)
end

local function updatePromptVisual()
	yesButton.AutoButtonColor = promptCanAfford
	yesButton.Active = promptCanAfford
	yesButton.BackgroundColor3 = if promptCanAfford then Color3.fromRGB(46, 122, 64) else Color3.fromRGB(70, 70, 70)
	yesButton.Text = if promptCanAfford then "Yes" else "Need More Cash"
end

local function updateOneProfitBoard(root: Instance, turretIndex: number, payload: { [string]: any })
	local adornee = getBillboardAdorneePart(root)
	if not adornee then
		if not warnedMissingProfitBoardAdornee[turretIndex] then
			warnedMissingProfitBoardAdornee[turretIndex] = true
			warn(
				string.format(
					"[MatchRoundHud] T%d profit board Model has no BasePart (set Model.PrimaryPart or add a Part).",
					turretIndex
				)
			)
		end
		return
	end

	local text = "Empty\n$0"
	local turretBoards = payload.turretBoards
	if typeof(turretBoards) == "table" then
		for _, row in turretBoards do
			if typeof(row) == "table" and row.turretIndex == turretIndex then
				local rowName = if typeof(row.name) == "string" then row.name else "Empty"
				local rowProfit = if typeof(row.netProfit) == "number" then row.netProfit else 0
				text = string.format("%s\n$%d", rowName, rowProfit)
				break
			end
		end
	end

	local billboardLabel = ensureProfitBillboardLabel(adornee)
	billboardLabel.Text = text
	-- T2/T3: 180° UI flip. T1/T4 use 0°.
	billboardLabel.Rotation = if turretIndex == 2 or turretIndex == 3 then 180 else 0
	local bbGui = adornee:FindFirstChild(PROFIT_BILLBOARD_NAME)
	if bbGui and bbGui:IsA("BillboardGui") then
		setBillboardAbovePart(adornee, bbGui)
	end

	local surfaceGui = findSurfaceGuiUnderRoot(root)
	if surfaceGui then
		local useSurfaceLayout = root:GetAttribute(MATCH_HUD_USE_SURFACE_GUI_ATTR) == true
		if useSurfaceLayout then
			surfaceGui.Enabled = true
			local surfaceLabel = pickSurfaceProfitTextLabel(surfaceGui)
			if surfaceLabel then
				clearOpaqueAncestorsToSurfaceGui(surfaceLabel, surfaceGui)
				styleProfitBoard(surfaceLabel, surfaceGui)
				surfaceLabel.Text = text
				surfaceLabel.Rotation = if turretIndex == 2 or turretIndex == 3 then 180 else 0
			end
		else
			surfaceGui.Enabled = false
		end
	end
end

local function updateProfitBoardText(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local floorBoard = Workspace:FindFirstChild("Floor Board")
	if not floorBoard then
		if not warnedMissingFloorBoard then
			warnedMissingFloorBoard = true
			warn(
				'[MatchRoundHud] Workspace["Floor Board"] not found. Profit boards must live under Floor Board. '
					.. "Names are case-sensitive; if StreamingEnabled, wait until it streams in."
			)
		end
		return
	end

	for slotIndex, slot in PROFIT_BOARD_SLOTS do
		local root = findProfitBoardUnderFloor(floorBoard, slot.candidateNames)
		if not root then
			if not warnedMissingProfitBoardSlot[slotIndex] then
				warnedMissingProfitBoardSlot[slotIndex] = true
				warn(
					string.format(
						'[MatchRoundHud] T%d profit board not found under Floor Board. Expected one of: %s',
						slot.turretIndex,
						table.concat(slot.candidateNames, ", ")
					)
				)
			end
			continue
		end
		updateOneProfitBoard(root, slot.turretIndex, payload)
	end
end

local function scheduleProfitBoardRetry()
	if profitBoardRetryScheduled or not lastProfitBoardPayload then
		return
	end
	profitBoardRetryScheduled = true
	task.defer(function()
		profitBoardRetryScheduled = false
		if lastProfitBoardPayload then
			updateProfitBoardText(lastProfitBoardPayload)
		end
	end)
end

Workspace.DescendantAdded:Connect(function(inst: Instance)
	local n = inst.Name
	if
		n == "Floor Board"
		or n == "Profit Board"
		or n == "ProfitBoard"
		or n == "Profit Board 2"
		or n == "Profit Board 3"
		or n == "Profit Board 4"
	then
		scheduleProfitBoardRetry()
	end
end)

roundStateEvent.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.phase) == "string" then
		phaseValue = payload.phase
	end
	if typeof(payload.roundEndServerTime) == "number" then
		roundEndServerTime = payload.roundEndServerTime
	end
	lastProfitBoardPayload = payload
	updateProfitBoardText(payload)
	applyMenuResetPolicy()
end)

continuePromptEvent.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.visible ~= true then
		continueFrame.Visible = false
		promptEndServerTime = 0
		promptJoinNextRound = false
		return
	end

	local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 10
	local now = Workspace:GetServerTimeNow()
	promptEndServerTime = now + seconds
	promptEntryFee = if typeof(payload.entryFee) == "number" then payload.entryFee else 0
	promptCanAfford = payload.canAfford == true
	promptJoinNextRound = payload.promptReason == "join_next_round"

	continueFrame.Visible = true
	if promptJoinNextRound then
		continueLabel.Text = string.format(
			"Pay $%d to join the next round? (%ds)",
			promptEntryFee,
			math.max(0, math.ceil(seconds))
		)
	else
		continueLabel.Text = string.format("Continue for $%d? (%ds)", promptEntryFee, math.max(0, math.ceil(seconds)))
	end
	updatePromptVisual()
end)

yesButton.MouseButton1Click:Connect(function()
	if not promptCanAfford then
		return
	end
	continueResponseEvent:FireServer(true)
	continueFrame.Visible = false
end)

noButton.MouseButton1Click:Connect(function()
	continueResponseEvent:FireServer(false)
	continueFrame.Visible = false
end)

RunService.RenderStepped:Connect(function()
	local now = Workspace:GetServerTimeNow()
	local timeSegment = if roundEndServerTime > 0 then formatSeconds(roundEndServerTime - now) else "--"
	timerTabClock.Text = timeSegment

	local dualLine = phaseValue == "Intermission"
		or (phaseValue == "ActiveRound" and not isLocalPlayerInRoundLeaderboard(lastProfitBoardPayload))

	if dualLine then
		roundTimerTab.Size = TIMER_TAB_SIZE_INTERMISSION
		timerTabListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		timerTabSubtitle.Visible = true
		timerTabSubtitle.TextSize = 13
		timerTabSubtitle.Text = if phaseValue == "Intermission" then "Match begins" else "Wait for next round"
		timerTabClock.TextSize = 18
		timerTabClock.AutomaticSize = Enum.AutomaticSize.Y
		timerTabClock.Size = UDim2.new(1, 0, 0, 0)
		timerTabClock.TextYAlignment = Enum.TextYAlignment.Center
	else
		roundTimerTab.Size = TIMER_TAB_SIZE_COMPACT
		timerTabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		timerTabSubtitle.Visible = false
		timerTabSubtitle.Text = ""
		timerTabClock.TextSize = 20
		timerTabClock.AutomaticSize = Enum.AutomaticSize.None
		timerTabClock.Size = UDim2.new(1, 0, 1, 0)
		timerTabClock.TextYAlignment = Enum.TextYAlignment.Center
	end

	if continueFrame.Visible and promptEndServerTime > 0 then
		local secondsLeft = math.max(0, math.ceil(promptEndServerTime - now))
		if promptJoinNextRound then
			continueLabel.Text = string.format("Pay $%d to join the next round? (%ds)", promptEntryFee, secondsLeft)
		else
			continueLabel.Text = string.format("Continue for $%d? (%ds)", promptEntryFee, secondsLeft)
		end
		if secondsLeft <= 0 then
			continueFrame.Visible = false
			promptJoinNextRound = false
		end
	end
end)

applyMenuResetPolicy()
