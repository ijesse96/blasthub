--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashHudBar = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CashHudBar"))
local CoinPurchaseClient = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CoinPurchaseClient"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local firePurchaseRequest = CoinPurchaseClient.createRequestPurchase("EconomyRemotes")

local mount = CashHudBar.mount(playerGui, {
	onPlusClick = firePurchaseRequest,
})

CashHudBar.bindCash(mount.amountLabel, player)
