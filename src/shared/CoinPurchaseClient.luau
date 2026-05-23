--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REQUEST_PURCHASE_NAME = "RequestCoinPurchase"

local CoinPurchaseClient = {}

function CoinPurchaseClient.createRequestPurchase(remotesFolderName: string): () -> ()
	local cachedRemote: RemoteEvent? = nil

	local function fire()
		if cachedRemote then
			cachedRemote:FireServer()
			return
		end
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild(remotesFolderName, 30)
			if not folder or not folder:IsA("Folder") then
				return
			end
			local remote = folder:WaitForChild(REQUEST_PURCHASE_NAME, 15)
			if remote and remote:IsA("RemoteEvent") then
				cachedRemote = remote
				remote:FireServer()
			end
		end)
	end

	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(remotesFolderName, 30)
		if folder and folder:IsA("Folder") then
			local remote = folder:WaitForChild(REQUEST_PURCHASE_NAME, 15)
			if remote and remote:IsA("RemoteEvent") then
				cachedRemote = remote
			end
		end
	end)

	return fire
end

return CoinPurchaseClient
