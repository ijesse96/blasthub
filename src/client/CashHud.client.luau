local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CashHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "CashText"
label.AnchorPoint = Vector2.new(1, 0)
label.Position = UDim2.new(1, -20, 0, 20)
label.Size = UDim2.fromOffset(220, 40)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 26
label.TextXAlignment = Enum.TextXAlignment.Right
label.TextColor3 = Color3.fromRGB(70, 220, 120)
label.TextStrokeTransparency = 0.5
label.TextStrokeColor3 = Color3.fromRGB(0, 35, 18)
label.Text = "$0"
label.Parent = screenGui

local bound = false

local function formatCash(n: number): string
	return string.format("$%d", math.floor(n))
end

local function bindCash(cash: IntValue)
	if bound then
		return
	end
	bound = true
	local function refresh()
		label.Text = formatCash(cash.Value)
	end
	refresh()
	cash:GetPropertyChangedSignal("Value"):Connect(refresh)
end

local function tryBind()
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local cash = ls:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") then
		bindCash(cash)
	end
end

player.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then
		local cash = child:WaitForChild("Cash", 15)
		if cash and cash:IsA("IntValue") then
			bindCash(cash)
		end
	end
end)

tryBind()
