local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_NAME = "LobbyRemotes"
local PURCHASE_RESULT_NAME = "AtmPurchaseResult"
local MESSAGE_LIFETIME_SECONDS = 3

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local lobbyRemotes = ReplicatedStorage:WaitForChild(REMOTES_NAME)
local purchaseResultRemote = lobbyRemotes:WaitForChild(PURCHASE_RESULT_NAME)

local gui = Instance.new("ScreenGui")
gui.Name = "AtmPurchaseFeedback"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 122
gui.Parent = playerGui

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "Message"
messageLabel.AnchorPoint = Vector2.new(0.5, 0)
messageLabel.Position = UDim2.new(0.5, 0, 0, 120)
messageLabel.Size = UDim2.fromOffset(460, 44)
messageLabel.BackgroundColor3 = Color3.fromRGB(20, 32, 24)
messageLabel.BackgroundTransparency = 0.15
messageLabel.Font = Enum.Font.GothamBold
messageLabel.TextSize = 22
messageLabel.TextColor3 = Color3.fromRGB(120, 255, 170)
messageLabel.TextStrokeTransparency = 0.55
messageLabel.Visible = false
messageLabel.Parent = gui

local messageToken = 0

local function showMessage(text: string, positive: boolean)
	messageToken += 1
	local token = messageToken
	messageLabel.Text = text
	messageLabel.TextColor3 = if positive then Color3.fromRGB(120, 255, 170) else Color3.fromRGB(255, 200, 120)
	messageLabel.Visible = true
	task.delay(MESSAGE_LIFETIME_SECONDS, function()
		if token ~= messageToken then
			return
		end
		messageLabel.Visible = false
	end)
end

purchaseResultRemote.OnClientEvent:Connect(function(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local ok = data.ok == true
	local message = data.message
	local text: string
	if typeof(message) == "string" and message ~= "" then
		text = message :: string
	elseif ok then
		text = "Purchase complete!"
	else
		text = "Purchase cancelled."
	end

	showMessage(text, ok)
end)
