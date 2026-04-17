local LEADERSTATS_NAME = "leaderstats"
local CASH_NAME = "Cash"

local Money = {}

function Money.setupPlayer(player: Player): IntValue
	local leaderstats = player:FindFirstChild(LEADERSTATS_NAME)
	if not leaderstats or not leaderstats:IsA("Folder") then
		if leaderstats then
			leaderstats:Destroy()
		end
		leaderstats = Instance.new("Folder")
		leaderstats.Name = LEADERSTATS_NAME
		leaderstats.Parent = player
	end

	local cash = leaderstats:FindFirstChild(CASH_NAME)
	if not cash or not cash:IsA("IntValue") then
		if cash then
			cash:Destroy()
		end
		cash = Instance.new("IntValue")
		cash.Name = CASH_NAME
		cash.Value = 100
		cash.Parent = leaderstats
	end

	return cash
end

function Money.addCash(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local cash = Money.setupPlayer(player)
	cash.Value += math.floor(amount + 0.5)
end

function Money.subtractCash(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local cash = Money.setupPlayer(player)
	cash.Value -= math.floor(amount + 0.5)
end

return Money
