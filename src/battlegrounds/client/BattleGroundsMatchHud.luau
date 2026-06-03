--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTES_NAME = "BattleGroundsRemotes"
local REMOTE_JOIN = "JoinBattleQueue"
local REMOTE_LEAVE = "LeaveBattleQueue"
local REMOTE_QUEUE_STATUS = "BattleQueueStatus"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local M = {}

local screenGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local joinButton: TextButton? = nil
local inQueue = false
local battleActive = false
local didBind = false

local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(REMOTES_NAME):WaitForChild(name) :: RemoteEvent
end

local function setVisible(visible: boolean)
	if screenGui then
		screenGui.Enabled = visible and not battleActive
	end
end

local function ensureUi()
	if screenGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BattleGroundsMatchHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 15
	gui.Parent = playerGui
	screenGui = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -24)
	bar.Size = UDim2.fromOffset(280, 96)
	bar.BackgroundColor3 = Color3.fromRGB(20, 26, 36)
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -16, 0, 28)
	statusLabel.Position = UDim2.fromOffset(8, 8)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 14
	statusLabel.TextWrapped = true
	statusLabel.TextColor3 = Color3.fromRGB(200, 210, 220)
	statusLabel.Text = "Tap below to start a battle."
	statusLabel.Parent = bar

	joinButton = Instance.new("TextButton")
	joinButton.Name = "Join"
	joinButton.Position = UDim2.fromOffset(12, 44)
	joinButton.Size = UDim2.new(1, -24, 0, 40)
	joinButton.BackgroundColor3 = Color3.fromRGB(55, 120, 220)
	joinButton.Font = Enum.Font.GothamBold
	joinButton.TextSize = 18
	joinButton.TextColor3 = Color3.new(1, 1, 1)
	joinButton.Text = "FIND MATCH"
	joinButton.AutoButtonColor = true
	joinButton.Parent = bar

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = joinButton

	joinButton.Activated:Connect(function()
		if statusLabel then
			statusLabel.Text = "Joining queue..."
		end
		getRemote(REMOTE_JOIN):FireServer()
	end)
end

local function bindRemotes()
	if didBind then
		return
	end
	didBind = true

	getRemote(REMOTE_QUEUE_STATUS).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or not statusLabel then
			return
		end
		inQueue = payload.inQueue == true
		if payload.message then
			statusLabel.Text = tostring(payload.message)
		elseif inQueue then
			statusLabel.Text = "Searching for opponent..."
		else
			statusLabel.Text = "Tap below to start a battle."
		end
	end)
end

function M.init()
	ensureUi()
	bindRemotes()
	setVisible(true)

	if RunService:IsStudio() then
		task.delay(2, function()
			getRemote(REMOTE_JOIN):FireServer()
		end)
	end
end

function M.onBattleStarted()
	battleActive = true
	inQueue = false
	setVisible(false)
end

function M.onBattleEnded()
	battleActive = false
	inQueue = false
	setVisible(true)
	if statusLabel then
		statusLabel.Text = "Tap below to start a battle."
	end
end

return M
