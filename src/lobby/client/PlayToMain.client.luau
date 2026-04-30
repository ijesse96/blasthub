local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_NAME = "LobbyRemotes"
local JOIN_RESULT_NAME = "LobbyJoinResult"
local MESSAGE_LIFETIME_SECONDS = 2.5

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local lobbyRemotes = ReplicatedStorage:WaitForChild(REMOTES_NAME)
local joinResultRemote = lobbyRemotes:WaitForChild(JOIN_RESULT_NAME)

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyJoinFeedback"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 120
gui.Parent = playerGui

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "Message"
messageLabel.AnchorPoint = Vector2.new(0.5, 0)
messageLabel.Position = UDim2.new(0.5, 0, 0, 28)
messageLabel.Size = UDim2.fromOffset(420, 42)
messageLabel.BackgroundColor3 = Color3.fromRGB(32, 20, 20)
messageLabel.BackgroundTransparency = 0.2
messageLabel.Font = Enum.Font.GothamBold
messageLabel.TextSize = 24
messageLabel.TextColor3 = Color3.fromRGB(255, 180, 180)
messageLabel.TextStrokeTransparency = 0.55
messageLabel.Visible = false
messageLabel.Parent = gui

local messageToken = 0

local function showMessage(text: string)
	messageToken += 1
	local token = messageToken
	messageLabel.Text = text
	messageLabel.Visible = true
	task.delay(MESSAGE_LIFETIME_SECONDS, function()
		if token ~= messageToken then
			return
		end
		messageLabel.Visible = false
	end)
end

joinResultRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local ok = payload.ok == true
	if ok then
		return
	end

	local message = payload.message
	if typeof(message) == "string" and message ~= "" then
		showMessage(message)
	else
		showMessage("Unable to enter right now.")
	end
end)
