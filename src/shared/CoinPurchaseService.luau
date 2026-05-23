local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyStore = require(shared:WaitForChild("EconomyStore"))
local LobbyCoinProducts = require(shared:WaitForChild("LobbyCoinProducts"))
local Money = require(shared:WaitForChild("Money"))

local PURCHASE_RESULT_NAME = "AtmPurchaseResult"
local REQUEST_PURCHASE_NAME = "RequestCoinPurchase"

local RECEIPT_STORE_NAME = "ProcessedReceipts_v1"
local DEBOUNCE_SECONDS = 2

local receiptStore = DataStoreService:GetDataStore(RECEIPT_STORE_NAME)

export type CoinPurchaseService = {
	bindProcessReceipt: (self: CoinPurchaseService) -> (),
	bindRequestRemotes: (self: CoinPurchaseService) -> (),
	requestPurchase: (self: CoinPurchaseService, player: Player) -> (),
}

local CoinPurchaseService = {}
CoinPurchaseService.__index = CoinPurchaseService

function CoinPurchaseService.new(remotesFolderName: string): CoinPurchaseService
	local self = setmetatable({
		_remotesFolderName = remotesFolderName,
		_lastRequestAtByUserId = {} :: { [number]: number },
		_didBindReceipt = false,
		_didBindRequest = false,
	}, CoinPurchaseService)
	return self
end

function CoinPurchaseService:_getOrCreateRemotesFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(self._remotesFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = self._remotesFolderName
	folder.Parent = ReplicatedStorage
	return folder
end

function CoinPurchaseService:_ensurePurchaseResultRemote(): RemoteEvent
	local folder = self:_getOrCreateRemotesFolder()
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

function CoinPurchaseService:_firePurchaseResult(player: Player, payload: { [string]: unknown })
	self:_ensurePurchaseResultRemote():FireClient(player, payload)
end

local function receiptKey(purchaseId: string): string
	return string.format("receipt_%s", purchaseId)
end

function CoinPurchaseService:_tryClaimReceiptAsync(purchaseId: string): (boolean, boolean)
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
		warn(string.format("[CoinPurchase] tryClaimReceiptAsync failed: %s", tostring(err)))
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

function CoinPurchaseService:_grantPurchaseToPlayer(playerId: number, amount: number): (boolean, number)
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

function CoinPurchaseService:bindProcessReceipt()
	if self._didBindReceipt then
		return
	end
	self._didBindReceipt = true

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local purchaseId = receiptInfo.PurchaseId
		local playerId = receiptInfo.PlayerId
		local productId = receiptInfo.ProductId

		local coinAmount = getCoinAmountForProduct(productId)
		if not coinAmount then
			warn(string.format("[CoinPurchase] Unknown product id %d", productId))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local claimOk, shouldGrant = self:_tryClaimReceiptAsync(purchaseId)
		if not claimOk then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if not shouldGrant then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local granted, _newBalance = self:_grantPurchaseToPlayer(playerId, coinAmount)
		if not granted then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local player = Players:GetPlayerByUserId(playerId)
		if player then
			self:_firePurchaseResult(player, {
				ok = true,
				amount = coinAmount,
				message = string.format("You received $%d!", coinAmount),
			})
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

function CoinPurchaseService:_ensureRequestPurchaseRemote(): RemoteEvent
	local folder = self:_getOrCreateRemotesFolder()
	local existing = folder:FindFirstChild(REQUEST_PURCHASE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = REQUEST_PURCHASE_NAME
	remote.Parent = folder
	return remote
end

function CoinPurchaseService:bindRequestRemotes()
	if self._didBindRequest then
		return
	end
	self._didBindRequest = true

	local requestRemote = self:_ensureRequestPurchaseRemote()
	requestRemote.OnServerEvent:Connect(function(player: Player)
		self:requestPurchase(player)
	end)
end

function CoinPurchaseService:requestPurchase(player: Player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local userId = player.UserId
	local now = os.clock()
	if (self._lastRequestAtByUserId[userId] or 0) + DEBOUNCE_SECONDS > now then
		return
	end
	self._lastRequestAtByUserId[userId] = now

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, LobbyCoinProducts.COIN_PACK_PRODUCT_ID)
	end)

	if not ok then
		warn(string.format("[CoinPurchase] PromptProductPurchase failed for %s: %s", player.Name, tostring(err)))
		self:_firePurchaseResult(player, {
			ok = false,
			message = "Purchase unavailable. Try again.",
		})
	end
end

return CoinPurchaseService
