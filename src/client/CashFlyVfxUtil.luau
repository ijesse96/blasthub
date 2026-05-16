--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local COIN_SIZE = 22
local TWEEN_TIME = 0.62
local STAGGER = 0.045
local MAX_COINS = 10
local MIN_COINS = 2
local LAYER_NAME = "CashFlyVfxLayer"
local LAYER_DISPLAY_ORDER = 80

export type CashFlyUtil = {
	getOrCreateLayer: (playerGui: PlayerGui) -> ScreenGui,
	getCashLabel: (playerGui: PlayerGui) -> TextLabel?,
	playFlyFromScreen: (playerGui: PlayerGui, startX: number, startY: number, amount: number) -> (),
	playFlyFromWorld: (playerGui: PlayerGui, worldPos: Vector3, amount: number) -> (),
}

local CashFlyVfxUtil: CashFlyUtil = {} :: any

function CashFlyVfxUtil.getCashLabel(playerGui: PlayerGui): TextLabel?
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

function CashFlyVfxUtil.getOrCreateLayer(playerGui: PlayerGui): ScreenGui
	local existing = playerGui:FindFirstChild(LAYER_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end

	local layer = Instance.new("ScreenGui")
	layer.Name = LAYER_NAME
	layer.ResetOnSpawn = false
	layer.IgnoreGuiInset = true
	layer.DisplayOrder = LAYER_DISPLAY_ORDER
	layer.Parent = playerGui
	return layer
end

local function coinCountForAmount(amount: number): number
	return math.clamp(math.ceil(amount / 2), MIN_COINS, MAX_COINS)
end

local function spawnOneCoin(
	layer: ScreenGui,
	startX: number,
	startY: number,
	targetX: number,
	targetY: number,
	delaySec: number
)
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

function CashFlyVfxUtil.playFlyFromScreen(playerGui: PlayerGui, startX: number, startY: number, amount: number)
	local label = CashFlyVfxUtil.getCashLabel(playerGui)
	if not label then
		return
	end

	local target = label.AbsolutePosition + label.AbsoluteSize * 0.5
	local targetX, targetY = target.X, target.Y
	local layer = CashFlyVfxUtil.getOrCreateLayer(playerGui)

	local n = coinCountForAmount(amount)
	for i = 1, n do
		local ox = (math.random() - 0.5) * 40
		local oy = (math.random() - 0.5) * 40
		spawnOneCoin(layer, startX + ox, startY + oy, targetX, targetY, (i - 1) * STAGGER)
	end
end

function CashFlyVfxUtil.playFlyFromWorld(playerGui: PlayerGui, worldPos: Vector3, amount: number)
	local label = CashFlyVfxUtil.getCashLabel(playerGui)
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

	CashFlyVfxUtil.playFlyFromScreen(playerGui, startX, startY, amount)
end

return CashFlyVfxUtil
