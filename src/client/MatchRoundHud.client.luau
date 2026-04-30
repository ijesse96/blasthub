local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTES_FOLDER_NAME = "MatchRoundRemotes"
local STATE_EVENT_NAME = "RoundState"
local CONTINUE_PROMPT_EVENT_NAME = "ContinuePrompt"
local CONTINUE_RESPONSE_EVENT_NAME = "ContinueResponse"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
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

local panel = Instance.new("Frame")
panel.Name = "RoundPanel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 14)
panel.Size = UDim2.fromOffset(420, 150)
panel.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
panel.BackgroundTransparency = 0.2
panel.Parent = screenGui

local phaseLabel = Instance.new("TextLabel")
phaseLabel.BackgroundTransparency = 1
phaseLabel.Position = UDim2.fromOffset(12, 8)
phaseLabel.Size = UDim2.fromOffset(396, 26)
phaseLabel.Font = Enum.Font.GothamBold
phaseLabel.TextSize = 22
phaseLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
phaseLabel.TextXAlignment = Enum.TextXAlignment.Left
phaseLabel.Text = "Phase: Idle"
phaseLabel.Parent = panel

local timerLabel = Instance.new("TextLabel")
timerLabel.BackgroundTransparency = 1
timerLabel.Position = UDim2.fromOffset(12, 36)
timerLabel.Size = UDim2.fromOffset(396, 22)
timerLabel.Font = Enum.Font.Gotham
timerLabel.TextSize = 18
timerLabel.TextColor3 = Color3.fromRGB(210, 220, 245)
timerLabel.TextXAlignment = Enum.TextXAlignment.Left
timerLabel.Text = "Timer: --"
timerLabel.Parent = panel

local profitLabel = Instance.new("TextLabel")
profitLabel.BackgroundTransparency = 1
profitLabel.Position = UDim2.fromOffset(12, 58)
profitLabel.Size = UDim2.fromOffset(396, 22)
profitLabel.Font = Enum.Font.Gotham
profitLabel.TextSize = 18
profitLabel.TextColor3 = Color3.fromRGB(120, 230, 150)
profitLabel.TextXAlignment = Enum.TextXAlignment.Left
profitLabel.Text = "Net Profit: $0"
profitLabel.Parent = panel

local leaderboardLabel = Instance.new("TextLabel")
leaderboardLabel.BackgroundTransparency = 1
leaderboardLabel.Position = UDim2.fromOffset(12, 82)
leaderboardLabel.Size = UDim2.fromOffset(396, 60)
leaderboardLabel.Font = Enum.Font.Gotham
leaderboardLabel.TextSize = 16
leaderboardLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
leaderboardLabel.TextXAlignment = Enum.TextXAlignment.Left
leaderboardLabel.TextYAlignment = Enum.TextYAlignment.Top
leaderboardLabel.TextWrapped = true
leaderboardLabel.Text = "Leaderboard: waiting..."
leaderboardLabel.Parent = panel

local continueFrame = Instance.new("Frame")
continueFrame.Name = "ContinuePrompt"
continueFrame.AnchorPoint = Vector2.new(0.5, 1)
continueFrame.Position = UDim2.new(0.5, 0, 1, -24)
continueFrame.Size = UDim2.fromOffset(460, 130)
continueFrame.BackgroundColor3 = Color3.fromRGB(18, 24, 20)
continueFrame.BackgroundTransparency = 0.2
continueFrame.Visible = false
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

local phaseValue = "Idle"
local roundEndServerTime = 0
local promptEndServerTime = 0
local promptEntryFee = 0
local promptCanAfford = false
local currentLeaderboard: { [number]: { userId: number, name: string, netProfit: number } } = {}

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

local function updateLeaderboardLabel()
	if #currentLeaderboard == 0 then
		leaderboardLabel.Text = "Leaderboard: waiting..."
		return
	end

	local lines = {}
	for i = 1, math.min(4, #currentLeaderboard) do
		local row = currentLeaderboard[i]
		table.insert(lines, string.format("%d) %s   $%d", i, row.name, row.netProfit))
	end
	leaderboardLabel.Text = "Leaderboard:\n" .. table.concat(lines, "\n")
end

roundStateEvent.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.phase) == "string" then
		phaseValue = payload.phase
		phaseLabel.Text = "Phase: " .. phaseValue
	end
	if typeof(payload.roundEndServerTime) == "number" then
		roundEndServerTime = payload.roundEndServerTime
	end
	if typeof(payload.leaderboard) == "table" then
		currentLeaderboard = payload.leaderboard
		updateLeaderboardLabel()

		local localNet = 0
		for _, row in currentLeaderboard do
			if typeof(row) == "table" and row.userId == player.UserId then
				localNet = if typeof(row.netProfit) == "number" then row.netProfit else 0
				break
			end
		end
		profitLabel.Text = string.format("Net Profit: $%d", localNet)
	end
	if typeof(payload.winnerName) == "string" and payload.winnerName ~= "" and typeof(payload.bonusAmount) == "number" then
		leaderboardLabel.Text = string.format("Winner: %s (+$%d bonus)", payload.winnerName, payload.bonusAmount)
	end
end)

continuePromptEvent.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.visible ~= true then
		continueFrame.Visible = false
		promptEndServerTime = 0
		return
	end

	local seconds = if typeof(payload.seconds) == "number" then payload.seconds else 10
	local now = Workspace:GetServerTimeNow()
	promptEndServerTime = now + seconds
	promptEntryFee = if typeof(payload.entryFee) == "number" then payload.entryFee else 0
	promptCanAfford = payload.canAfford == true

	continueFrame.Visible = true
	continueLabel.Text = string.format("Continue for $%d? (%ds)", promptEntryFee, math.max(0, math.ceil(seconds)))
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
	if roundEndServerTime > 0 then
		timerLabel.Text = "Timer: " .. formatSeconds(roundEndServerTime - now)
	else
		timerLabel.Text = "Timer: --"
	end

	if continueFrame.Visible and promptEndServerTime > 0 then
		local secondsLeft = math.max(0, math.ceil(promptEndServerTime - now))
		continueLabel.Text = string.format("Continue for $%d? (%ds)", promptEntryFee, secondsLeft)
		if secondsLeft <= 0 then
			continueFrame.Visible = false
		end
	end
end)
