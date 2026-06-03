--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BattleGroundsCombatPlayback = require(script.Parent:WaitForChild("BattleGroundsCombatPlayback"))
local BattleGroundsGridScreen = require(script.Parent:WaitForChild("BattleGroundsGridScreen"))
local BattleGroundsMatchHud = require(script.Parent:WaitForChild("BattleGroundsMatchHud"))
local BattleGroundsResults = require(script.Parent:WaitForChild("BattleGroundsResults"))

local REMOTES_NAME = "BattleGroundsRemotes"
local REMOTE_JOIN = "JoinBattleQueue"
local REMOTE_STATE = "BattlePlacementState"
local REMOTE_RESULT = "BattleResult"
local REMOTE_COMBAT_UPDATE = "BattleCombatUpdate"
local REMOTE_QUEUE_STATUS = "BattleQueueStatus"

local player = Players.LocalPlayer

local didBind = false
local combatSessionId: string? = nil

local M = {}

local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(REMOTES_NAME):WaitForChild(name) :: RemoteEvent
end

local function startLiveCombat(state: any)
	combatSessionId = state.sessionId
	BattleGroundsMatchHud.onBattleStarted()

	local function tryBegin(): boolean
		local grid = BattleGroundsGridScreen.getGridLayout()
		if not grid then
			return false
		end
		BattleGroundsCombatPlayback.beginLive({
			layoutA = state.layoutA,
			layoutB = state.layoutB,
			grid = grid,
		})
		return true
	end

	if not tryBegin() then
		task.spawn(function()
			for _ = 1, 30 do
				if tryBegin() then
					return
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end
end

local function bindRemotes()
	if didBind then
		return
	end
	didBind = true

	getRemote(REMOTE_STATE).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		combatSessionId = payload.sessionId
		BattleGroundsGridScreen.ensureBattleLayout()
		if payload.phase == "combat" then
			startLiveCombat(payload)
		end
	end)

	getRemote(REMOTE_COMBAT_UPDATE).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.sessionId then
			combatSessionId = payload.sessionId
		end
		if combatSessionId and payload.sessionId and payload.sessionId ~= combatSessionId then
			return
		end
		BattleGroundsCombatPlayback.applyLiveTick(payload)
	end)

	getRemote(REMOTE_RESULT).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		combatSessionId = nil
		BattleGroundsCombatPlayback.cancel()
		BattleGroundsMatchHud.onBattleEnded()
		BattleGroundsResults.show(payload, player.UserId)
	end)

	getRemote(REMOTE_QUEUE_STATUS).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local message = payload.message
		if typeof(message) == "string" and string.find(message, "fish", 1, true) then
			task.delay(1.5, function()
				getRemote(REMOTE_JOIN):FireServer()
			end)
		end
	end)
end

function M.init()
	task.spawn(function()
		BattleGroundsMatchHud.init()
		bindRemotes()
		BattleGroundsResults.setOnDismiss(function()
			BattleGroundsMatchHud.onBattleEnded()
			getRemote(REMOTE_JOIN):FireServer()
		end)
	end)
end

return M
