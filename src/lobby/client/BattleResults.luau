--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local BattleLayoutTypes = require(shared:WaitForChild("BattleLayoutTypes"))
local LobbyUiConfig = require(shared:WaitForChild("LobbyUiConfig"))

local BattlePlacementHud = require(script.Parent:WaitForChild("BattlePlacementHud"))
local LobbyModalInputBlock = require(script.Parent:WaitForChild("LobbyModalInputBlock"))
local LobbyTouchInputSuppress = require(script.Parent:WaitForChild("LobbyTouchInputSuppress"))

type BattleResultPayload = BattleLayoutTypes.BattleResultPayload

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local M = {}

local screenGui: ScreenGui
local titleLabel: TextLabel
local detailLabel: TextLabel
local onDismiss: (() -> ())? = nil
local didBuild = false

local function buildUi()
	if didBuild then
		return
	end
	didBuild = true

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BattleResults"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = LobbyUiConfig.DISPLAY_ORDER_HUB_OVERLAY + 3
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	LobbyModalInputBlock.create(screenGui, {
		name = "InputBlocker",
		zIndex = 1,
		backgroundTransparency = 0.45,
	})

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(360, 200)
	panel.BackgroundColor3 = Color3.fromRGB(28, 36, 48)
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.ZIndex = 2
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0, 64)
	titleLabel.Position = UDim2.fromOffset(0, 24)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 32
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Text = "Victory!"
	titleLabel.Parent = panel

	detailLabel = Instance.new("TextLabel")
	detailLabel.Size = UDim2.new(1, -24, 0, 40)
	detailLabel.Position = UDim2.fromOffset(12, 96)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Font = Enum.Font.GothamMedium
	detailLabel.TextSize = 16
	detailLabel.TextColor3 = Color3.fromRGB(200, 210, 220)
	detailLabel.TextWrapped = true
	detailLabel.Text = ""
	detailLabel.Parent = panel

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -16)
	btn.Size = UDim2.fromOffset(160, 40)
	btn.BackgroundColor3 = Color3.fromRGB(55, 120, 220)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 18
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "Continue"
	btn.Active = true
	btn.ZIndex = 3
	btn.Parent = panel

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = btn

	btn.Activated:Connect(function()
		M.close()
	end)
end

function M.show(result: BattleResultPayload, localUserId: number)
	buildUi()
	local won = result.winnerUserId == localUserId
	if result.reason == "tie" or result.winnerSide == nil then
		titleLabel.Text = "Draw"
		titleLabel.TextColor3 = Color3.fromRGB(220, 220, 120)
	elseif won then
		titleLabel.Text = "Victory!"
		titleLabel.TextColor3 = Color3.fromRGB(72, 255, 140)
	else
		titleLabel.Text = "Defeat"
		titleLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	end
	if result.reason == "forfeit" then
		detailLabel.Text = "Opponent left the match."
	elseif result.reason == "base_destroyed" then
		detailLabel.Text = if won then "Enemy base destroyed!" else "Your base was destroyed."
	elseif result.reason == "tie" then
		detailLabel.Text = "Stalemate — bases held."
	else
		detailLabel.Text = string.format("Battle ended (%s).", result.reason)
	end
	screenGui.Enabled = true
	LobbyTouchInputSuppress.setHolder("battle-results", true)
	LobbyModalInputBlock.setLobbyHubBlocked("battle-results", true)
end

function M.close()
	if screenGui then
		screenGui.Enabled = false
	end
	LobbyTouchInputSuppress.setHolder("battle-results", false)
	LobbyModalInputBlock.setLobbyHubBlocked("battle-results", false)
	BattlePlacementHud.releaseLobbyHubSuppression()
	if onDismiss then
		onDismiss()
	end
end

function M.setOnDismiss(callback: () -> ())
	onDismiss = callback
end

return M
