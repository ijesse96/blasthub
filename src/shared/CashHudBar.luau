--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyUiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LobbyUiConfig"))

export type MountOptions = {
	onPlusClick: (() -> ())?,
	displayOrder: number?,
}

export type CashHudMount = {
	screenGui: ScreenGui,
	amountLabel: TextLabel,
	plusButton: TextButton?,
}

local CashHudBar = {}

function CashHudBar.formatCashWithCommas(amount: number): string
	local n = math.max(0, math.floor(amount))
	local s = tostring(n)
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function CashHudBar.destroyLegacyCashHud(playerGui: PlayerGui)
	for _, child in playerGui:GetChildren() do
		if child.Name == "CashHud" and child:IsA("ScreenGui") then
			child:Destroy()
		elseif child.Name == "CashText" and child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

function CashHudBar.mount(playerGui: PlayerGui, options: MountOptions?): CashHudMount
	CashHudBar.destroyLegacyCashHud(playerGui)

	local onPlusClick = if options then options.onPlusClick else nil
	local displayOrder = if options and options.displayOrder then options.displayOrder else 50

	local barHeight = LobbyUiConfig.CASH_BAR_HEIGHT
	local padding = LobbyUiConfig.CASH_BAR_PADDING
	local coinSize = LobbyUiConfig.CASH_BAR_COIN_SIZE
	local plusSize = LobbyUiConfig.CASH_BAR_PLUS_SIZE

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CashHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = displayOrder
	screenGui.Parent = playerGui

	local cashBar = Instance.new("Frame")
	cashBar.Name = "CashBar"
	cashBar.AnchorPoint = Vector2.new(1, 0)
	cashBar.Position = LobbyUiConfig.CASH_BAR_POSITION
	cashBar.Size = UDim2.fromOffset(0, barHeight)
	cashBar.AutomaticSize = Enum.AutomaticSize.X
	cashBar.BackgroundColor3 = LobbyUiConfig.CASH_BAR_BG_COLOR
	cashBar.BackgroundTransparency = LobbyUiConfig.CASH_BAR_BG_TRANSPARENCY
	cashBar.BorderSizePixel = 0
	cashBar.Parent = screenGui

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 10)
	barCorner.Parent = cashBar

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = LobbyUiConfig.CASH_BAR_STROKE_COLOR
	barStroke.Thickness = 1.5
	barStroke.Transparency = 0.2
	barStroke.Parent = cashBar

	local barPadding = Instance.new("UIPadding")
	barPadding.PaddingLeft = UDim.new(0, padding)
	barPadding.PaddingRight = UDim.new(0, padding)
	barPadding.PaddingTop = UDim.new(0, (barHeight - coinSize) / 2)
	barPadding.PaddingBottom = UDim.new(0, (barHeight - coinSize) / 2)
	barPadding.Parent = cashBar

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Padding = UDim.new(0, 8)
	barLayout.Parent = cashBar

	local coinIcon = Instance.new("ImageLabel")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.fromOffset(coinSize, coinSize)
	coinIcon.BackgroundTransparency = 1
	coinIcon.Image = LobbyUiConfig.CASH_BAR_COIN_IMAGE
	coinIcon.ScaleType = Enum.ScaleType.Fit
	coinIcon.LayoutOrder = 1
	coinIcon.Parent = cashBar

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "Amount"
	amountLabel.Size = UDim2.fromOffset(80, barHeight - padding * 2)
	amountLabel.AutomaticSize = Enum.AutomaticSize.X
	amountLabel.BackgroundTransparency = 1
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.TextSize = 22
	amountLabel.TextXAlignment = Enum.TextXAlignment.Left
	amountLabel.TextColor3 = LobbyUiConfig.CASH_BAR_TEXT_COLOR
	amountLabel.Text = "0"
	amountLabel.LayoutOrder = 2
	amountLabel.Parent = cashBar

	local plusButton: TextButton? = nil
	if onPlusClick then
		local btn = Instance.new("TextButton")
		btn.Name = "Plus"
		btn.Size = UDim2.fromOffset(plusSize, plusSize)
		btn.BackgroundColor3 = LobbyUiConfig.CASH_BAR_PLUS_BG
		btn.BackgroundTransparency = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 28
		btn.TextColor3 = LobbyUiConfig.CASH_BAR_PLUS_TEXT_COLOR
		btn.Text = "+"
		btn.AutoButtonColor = true
		btn.LayoutOrder = 3
		btn.Parent = cashBar

		local plusCorner = Instance.new("UICorner")
		plusCorner.CornerRadius = UDim.new(0, 8)
		plusCorner.Parent = btn

		btn.MouseButton1Click:Connect(onPlusClick)
		plusButton = btn
	end

	return {
		screenGui = screenGui,
		amountLabel = amountLabel,
		plusButton = plusButton,
	}
end

function CashHudBar.bindCash(amountLabel: TextLabel, player: Player)
	local bound = false

	local function bindValue(cash: IntValue)
		if bound then
			return
		end
		bound = true
		local function refresh()
			amountLabel.Text = CashHudBar.formatCashWithCommas(cash.Value)
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
			bindValue(cash)
		end
	end

	player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then
			local cash = child:WaitForChild("Cash", 15)
			if cash and cash:IsA("IntValue") then
				bindValue(cash)
			end
		end
	end)

	tryBind()
end

return CashHudBar
