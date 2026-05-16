local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyStore = require(shared:WaitForChild("EconomyStore"))
local LobbyCoinProducts = require(shared:WaitForChild("LobbyCoinProducts"))
local Money = require(shared:WaitForChild("Money"))

local REMOTES_NAME = "LobbyRemotes"
local PURCHASE_RESULT_NAME = "AtmPurchaseResult"

local RECEIPT_STORE_NAME = "ProcessedReceipts_v1"
local DEBOUNCE_SECONDS = 2

local receiptStore = DataStoreService:GetDataStore(RECEIPT_STORE_NAME)
local lastRequestAtByUserId: { [number]: number } = {}
local didBindReceipt = false

local M = {}

local function getOrCreateRemotesFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = REMOTES_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensurePurchaseResultRemote(): RemoteEvent
	local folder = getOrCreateRemotesFolder()
	local existing = folder:FindFirstChild(PURCHASE_RESULT_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = PURCHASE_RESULT_NAME
	remote.Parent = folder
	return remote
end

local function firePurchaseResult(player: Player, payload: { [string]: unknown })
	ensurePurchaseResultRemote():FireClient(player, payload)
end

local function receiptKey(purchaseId: string): string
	return string.format("receipt_%s", purchaseId)
end

-- Returns true if this invocation should grant (first time seeing this PurchaseId).
local function tryClaimReceiptAsync(purchaseId: string): (boolean, boolean)
	local shouldGrant = false
	local ok, err = pcall(function()
		receiptStore:UpdateAsync(receiptKey(purchaseId), function(current)
			if current == true then
				return true
			end
			shouldGrant = true
			return true
		end)
	end)
	if not ok then
		warn(string.format("[LobbyCoinPurchase] tryClaimReceiptAsync failed: %s", tostring(err)))
		return false, false
	end
	return true, shouldGrant
end

local function getCoinAmountForProduct(productId: number): number?
	if productId == LobbyCoinProducts.COIN_PACK_PRODUCT_ID then
		return LobbyCoinProducts.COIN_PACK_AMOUNT
	end
	return nil
end

local function syncPlayerCash(player: Player, newBalance: number)
	local cash = Money.setupPlayer(player)
	cash.Value = math.max(0, math.floor(newBalance + 0.5))
end

local function grantPurchaseToPlayer(playerId: number, amount: number): (boolean, number)
	local credited, newBalance = EconomyStore.addCashAsync(playerId, amount)
	if not credited then
		return false, newBalance
	end

	local player = Players:GetPlayerByUserId(playerId)
	if player then
		syncPlayerCash(player, newBalance)
	end

	return true, newBalance
end

function M.bindProcessReceipt()
	if didBindReceipt then
		return
	end
	didBindReceipt = true

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local purchaseId = receiptInfo.PurchaseId
		local playerId = receiptInfo.PlayerId
		local productId = receiptInfo.ProductId

		local coinAmount = getCoinAmountForProduct(productId)
		if not coinAmount then
			warn(string.format("[LobbyCoinPurchase] Unknown product id %d", productId))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local claimOk, shouldGrant = tryClaimReceiptAsync(purchaseId)
		if not claimOk then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if not shouldGrant then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local granted, _newBalance = grantPurchaseToPlayer(playerId, coinAmount)
		if not granted then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local player = Players:GetPlayerByUserId(playerId)
		if player then
			firePurchaseResult(player, {
				ok = true,
				amount = coinAmount,
				message = string.format("You received $%d!", coinAmount),
			})
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

function M.requestPurchase(player: Player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local userId = player.UserId
	local now = os.clock()
	if (lastRequestAtByUserId[userId] or 0) + DEBOUNCE_SECONDS > now then
		return
	end
	lastRequestAtByUserId[userId] = now

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, LobbyCoinProducts.COIN_PACK_PRODUCT_ID)
	end)

	if not ok then
		warn(string.format("[LobbyCoinPurchase] PromptProductPurchase failed for %s: %s", player.Name, tostring(err)))
		firePurchaseResult(player, {
			ok = false,
			message = "Purchase unavailable. Try again.",
		})
	end
end

return M
