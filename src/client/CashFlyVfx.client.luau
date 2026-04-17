local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CASH_FLY_VFX_REMOTE_NAME = "CashFlyVfx"
local COIN_SIZE = 22
local TWEEN_TIME = 0.62
local STAGGER = 0.045
local MAX_COINS = 10
local MIN_COINS = 2

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local layer = Instance.new("ScreenGui")
layer.Name = "CashFlyVfxLayer"
layer.ResetOnSpawn = false
layer.IgnoreGuiInset = true
layer.DisplayOrder = 80
layer.Parent = playerGui

local function getCashLabel(): TextLabel?
	local hud = playerGui:FindFirstChild("CashHud")
	if not hud then
		return nil
	end
	local lbl = hud:FindFirstChild("CashText")
	if lbl and lbl:IsA("TextLabel") then
		return lbl
	end
	return nil
end

local function coinCountForAmount(amount: number): number
	return math.clamp(math.ceil(amount / 2), MIN_COINS, MAX_COINS)
end

local function spawnOneCoin(startX: number, startY: number, targetX: number, targetY: number, delaySec: number)
	local coin = Instance.new("Frame")
	coin.Name = "FlyCoin"
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Size = UDim2.fromOffset(COIN_SIZE, COIN_SIZE)
	coin.Position = UDim2.fromOffset(startX, startY)
	coin.BackgroundColor3 = Color3.fromRGB(255, 210, 70)
	coin.BorderSizePixel = 0
	coin.Parent = layer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = coin

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 130, 20)
	stroke.Thickness = 1.5
	stroke.Parent = coin

	local midX = (startX + targetX) * 0.5 + (math.random() - 0.5) * 120
	local midY = math.min(startY, targetY) - 80 - math.random() * 60

	task.delay(delaySec, function()
		if not coin.Parent then
			return
		end
		local tInfo = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local posTween = TweenService:Create(coin, tInfo, {
			Position = UDim2.fromOffset(targetX, targetY),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
		})
		TweenService:Create(stroke, tInfo, { Transparency = 1 }):Play()
		posTween:Play()
		posTween.Completed:Connect(function()
			coin:Destroy()
		end)
	end)
end

local function playFlyFromWorld(worldPos: Vector3, amount: number)
	local label = getCashLabel()
	local cam = Workspace.CurrentCamera
	if not label or not cam then
		return
	end

	local target = label.AbsolutePosition + label.AbsoluteSize * 0.5
	local targetX, targetY = target.X, target.Y

	local viewportPoint, onScreen = cam:WorldToViewportPoint(worldPos)
	local startX: number
	local startY: number
	if onScreen and viewportPoint.Z > 0 then
		startX = viewportPoint.X + (math.random() - 0.5) * 36
		startY = viewportPoint.Y + (math.random() - 0.5) * 36
	else
		local vs = cam.ViewportSize
		startX = vs.X * (0.2 + math.random() * 0.6)
		startY = vs.Y * (0.35 + math.random() * 0.35)
	end

	local n = coinCountForAmount(amount)
	for i = 1, n do
		local ox = (math.random() - 0.5) * 48
		local oy = (math.random() - 0.5) * 48
		spawnOneCoin(startX + ox, startY + oy, targetX, targetY, (i - 1) * STAGGER)
	end
end

local remote = ReplicatedStorage:WaitForChild(CASH_FLY_VFX_REMOTE_NAME, 60)
if not remote or not remote:IsA("RemoteEvent") then
	warn("[CashFlyVfx] Missing RemoteEvent", CASH_FLY_VFX_REMOTE_NAME)
	return
end

remote.OnClientEvent:Connect(function(worldPos: Vector3, amount: any)
	if typeof(worldPos) ~= "Vector3" then
		return
	end
	if typeof(amount) ~= "number" or amount <= 0 then
		return
	end
	playFlyFromWorld(worldPos, amount)
end)
