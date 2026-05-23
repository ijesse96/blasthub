local CoinPurchaseService = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CoinPurchaseService"))

local service = CoinPurchaseService.new("EconomyRemotes")
service:bindProcessReceipt()
service:bindRequestRemotes()
