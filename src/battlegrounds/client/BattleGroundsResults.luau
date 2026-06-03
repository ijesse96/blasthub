--!strict
local Players = game:GetService("Players")

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
	screenGui.Name = "BattleGroundsResults"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 20
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 0.45
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.ZIndex = 1
	scrim.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(360, 200)
	panel.BackgroundColor3 = Color3.fromRGB(28, 36, 48)
	panel.BorderSizePixel = 0
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
	btn.ZIndex = 3
	btn.Parent = panel

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = btn

	local function dismiss()
		M.close()
		if onDismiss then
			onDismiss()
		end
	end

	btn.Activated:Connect(dismiss)
	scrim.Activated:Connect(dismiss)
end

function M.setOnDismiss(callback: () -> ())
	onDismiss = callback
end

function M.show(result: { winnerUserId: number?, reason: string? }, localUserId: number)
	buildUi()
	local won = result.winnerUserId == localUserId
	titleLabel.Text = if won then "Victory!" elseif result.reason == "tie" then "Draw" else "Defeat"
	detailLabel.Text = if result.reason == "base_destroyed"
		then "Base destroyed."
		elseif result.reason == "forfeit" then "Opponent forfeited."
		else "Battle ended."
	screenGui.Enabled = true
end

function M.close()
	if didBuild then
		screenGui.Enabled = false
	end
end

return M
