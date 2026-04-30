local LEADERSTATS_NAME = "leaderstats"
local CASH_NAME = "Cash"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local EconomyStore = require(sharedFolder:WaitForChild("EconomyStore"))

local Money = {}

function Money.setupPlayer(player: Player, initialCash: number?): IntValue
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
		local startingCash = if typeof(initialCash) == "number" then initialCash else EconomyStore.getStartingCash()
		cash.Value = math.max(0, math.floor(startingCash + 0.5))
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

function Money.loadCashFromStoreAsync(player: Player): number
	local cash = Money.setupPlayer(player)
	local amount = EconomyStore.loadCashAsync(player.UserId)
	cash.Value = amount
	return amount
end

function Money.saveCashToStoreAsync(player: Player): boolean
	local cash = Money.setupPlayer(player)
	return EconomyStore.setCashAsync(player.UserId, cash.Value)
end

function Money.tryDebitEntryFeeAsync(userId: number, fee: number): (boolean, number)
	return EconomyStore.tryDebitEntryFeeAsync(userId, fee)
end

return Money
