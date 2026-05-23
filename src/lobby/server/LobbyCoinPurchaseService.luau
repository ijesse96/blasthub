local CoinPurchaseService = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CoinPurchaseService"))

local service = CoinPurchaseService.new("LobbyRemotes")

local M = {}

function M.bindProcessReceipt()
	service:bindProcessReceipt()
end

function M.bindRequestRemotes()
	service:bindRequestRemotes()
end

function M.requestPurchase(player: Player)
	service:requestPurchase(player)
end

return M
