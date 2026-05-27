--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local BattleLayoutTypes = require(shared:WaitForChild("BattleLayoutTypes"))
local LobbyUiConfig = require(shared:WaitForChild("LobbyUiConfig"))

local BattleCombatPlayback = require(script.Parent:WaitForChild("BattleCombatPlayback"))
local BattlePlacementHud = require(script.Parent:WaitForChild("BattlePlacementHud"))
local BattleResults = require(script.Parent:WaitForChild("BattleResults"))
local LobbyModalInputBlock = require(script.Parent:WaitForChild("LobbyModalInputBlock"))
local LobbyTouchInputSuppress = require(script.Parent:WaitForChild("LobbyTouchInputSuppress"))

type BattlePlacementStatePayload = BattleLayoutTypes.BattlePlacementStatePayload
type BattleResultPayload = BattleLayoutTypes.BattleResultPayload
type BattleCombatUpdatePayload = BattleLayoutTypes.BattleCombatUpdatePayload

local REMOTES_NAME = "LobbyRemotes"
local REMOTE_JOIN = "JoinBattleQueue"
local REMOTE_LEAVE = "LeaveBattleQueue"
local REMOTE_STATE = "BattlePlacementState"
local REMOTE_RESULT = "BattleResult"
local REMOTE_COMBAT_UPDATE = "BattleCombatUpdate"
local REMOTE_QUEUE_STATUS = "BattleQueueStatus"
local SNAPSHOT_REMOTE = "FishCollectionSnapshot"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local inQueue = false
local queueGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local didBind = false
local lastPlacementState: BattlePlacementStatePayload? = nil
local liveCombatActive = false
local combatSessionId: string? = nil

local M = {}

local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(REMOTES_NAME):WaitForChild(name) :: RemoteEvent
end

local function setQueueUiEnabled(enabled: boolean)
	if queueGui then
		queueGui.Enabled = enabled
	end
	LobbyTouchInputSuppress.setHolder("battle-queue", enabled)
	LobbyModalInputBlock.setLobbyHubBlocked("battle-queue", enabled)
end

local function closeQueuePanel()
	inQueue = false
	getRemote(REMOTE_LEAVE):FireServer()
	setQueueUiEnabled(false)
end

local function bindPressOnce(gui: GuiButton, onPress: () -> ())
	gui.Active = true
	gui.Selectable = true
	local busy = false
	gui.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		onPress()
		task.defer(function()
			busy = false
		end)
	end)
end

local function ensureQueueUi()
	if queueGui then
		return
	end
	queueGui = Instance.new("ScreenGui")
	queueGui.Name = "BattleQueue"
	queueGui.ResetOnSpawn = false
	queueGui.IgnoreGuiInset = true
	queueGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	queueGui.DisplayOrder = LobbyUiConfig.DISPLAY_ORDER_HUB_OVERLAY + 1
	queueGui.Enabled = false
	queueGui.Parent = playerGui

	LobbyModalInputBlock.create(queueGui, {
		name = "Scrim",
		zIndex = 1,
		backgroundTransparency = 0.4,
		onScrimPress = closeQueuePanel,
	})

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(320, 220)
	panel.BackgroundColor3 = Color3.fromRGB(28, 36, 48)
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Active = true
	panel.Parent = queueGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 48)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "FIND MATCH"
	title.Parent = panel

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -24, 0, 48)
	statusLabel.Position = UDim2.fromOffset(12, 56)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 16
	statusLabel.TextWrapped = true
	statusLabel.TextColor3 = Color3.fromRGB(200, 210, 220)
	statusLabel.Text = "Tap FIND MATCH to enter the queue."
	statusLabel.Parent = panel

	local findBtn = Instance.new("TextButton")
	findBtn.Name = "FindMatch"
	findBtn.Position = UDim2.fromOffset(24, 120)
	findBtn.Size = UDim2.new(1, -48, 0, 40)
	findBtn.BackgroundColor3 = Color3.fromRGB(55, 120, 220)
	findBtn.Font = Enum.Font.GothamBold
	findBtn.TextSize = 18
	findBtn.TextColor3 = Color3.new(1, 1, 1)
	findBtn.Text = "FIND MATCH"
	findBtn.ZIndex = 3
	findBtn.Parent = panel

	local findCorner = Instance.new("UICorner")
	findCorner.CornerRadius = UDim.new(0, 8)
	findCorner.Parent = findBtn

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "Cancel"
	cancelBtn.Position = UDim2.fromOffset(24, 168)
	cancelBtn.Size = UDim2.new(1, -48, 0, 36)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(60, 68, 80)
	cancelBtn.Font = Enum.Font.GothamBold
	cancelBtn.TextSize = 16
	cancelBtn.TextColor3 = Color3.new(1, 1, 1)
	cancelBtn.Text = "CANCEL"
	cancelBtn.ZIndex = 3
	cancelBtn.Parent = panel

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 8)
	cancelCorner.Parent = cancelBtn

	bindPressOnce(findBtn, function()
		getRemote(REMOTE_JOIN):FireServer()
	end)
	bindPressOnce(cancelBtn, closeQueuePanel)
end

local function openQueue()
	ensureQueueUi()
	setQueueUiEnabled(true)
	if statusLabel then
		statusLabel.Text = "Tap FIND MATCH to enter the queue."
	end
end

local function startLiveCombat(state: BattlePlacementStatePayload)
	if liveCombatActive and combatSessionId == state.sessionId then
		return
	end
	local grid = BattlePlacementHud.getGridLayout()
	if not grid then
		return
	end
	liveCombatActive = true
	combatSessionId = state.sessionId
	BattlePlacementHud.enterCombatView()
	BattleCombatPlayback.beginLive({
		layoutA = state.layoutA,
		layoutB = state.layoutB,
		grid = grid,
		onBaseHpChanged = function(hpA: number, hpB: number)
			BattlePlacementHud.updateBaseHp(hpA, hpB)
		end,
	})
	if state.baseHpA and state.baseHpB then
		BattlePlacementHud.updateBaseHp(state.baseHpA, state.baseHpB)
	end
	if state.manaA and state.manaB then
		BattlePlacementHud.updateMana(state.manaA, state.manaB)
	end
end

local function bindRemotes()
	if didBind then
		return
	end
	didBind = true

	getRemote(REMOTE_QUEUE_STATUS).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		inQueue = payload.inQueue == true
		if statusLabel then
			if payload.message then
				statusLabel.Text = tostring(payload.message)
			elseif inQueue then
				statusLabel.Text = "Searching for opponent..."
			else
				statusLabel.Text = "Tap FIND MATCH to enter the queue."
			end
		end
	end)

	getRemote(REMOTE_STATE).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local state = payload :: BattlePlacementStatePayload
		lastPlacementState = state
		setQueueUiEnabled(false)
		if BattlePlacementHud.isOpen() then
			BattlePlacementHud.update(state)
		else
			BattlePlacementHud.open(state)
		end
		if state.phase == "combat" then
			startLiveCombat(state)
		end
	end)

	getRemote(REMOTE_COMBAT_UPDATE).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local update = payload :: BattleCombatUpdatePayload
		if combatSessionId and update.sessionId ~= combatSessionId then
			return
		end
		if not liveCombatActive then
			local state = lastPlacementState
			if state and state.phase == "combat" then
				startLiveCombat(state)
			end
		end
		BattlePlacementHud.updateMana(update.manaA, update.manaB)
		BattlePlacementHud.syncCombatFieldUnits(update.units)
		BattleCombatPlayback.applyLiveTick(update)
	end)

	local function showResults(result: BattleResultPayload)
		liveCombatActive = false
		combatSessionId = nil
		BattleCombatPlayback.cancel()
		lastPlacementState = nil
		BattlePlacementHud.close()
		setQueueUiEnabled(false)
		BattleResults.show(result, player.UserId)
	end

	getRemote(REMOTE_RESULT).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local result = payload :: BattleResultPayload
		showResults(result)
	end)

	local snap = ReplicatedStorage:FindFirstChild(SNAPSHOT_REMOTE)
	if snap and snap:IsA("RemoteEvent") then
		snap.OnClientEvent:Connect(function(snapshot: unknown)
			BattlePlacementHud.applyOwnedSnapshot(snapshot)
		end)
	end
end

function M.init()
	bindRemotes()
	BattlePlacementHud.setOnClose(function()
		inQueue = false
		liveCombatActive = false
		combatSessionId = nil
		BattleCombatPlayback.cancel()
		getRemote(REMOTE_LEAVE):FireServer()
	end)
	BattleResults.setOnDismiss(function()
		openQueue()
	end)
end

function M.open()
	openQueue()
end

function M.close()
	setQueueUiEnabled(false)
end

return M
