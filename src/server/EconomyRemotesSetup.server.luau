-- Creates EconomyRemotes early so client CashHud is not blocked waiting for purchase handlers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_NAME = "EconomyRemotes"
local REMOTE_NAMES = {
	"RequestCoinPurchase",
	"AtmPurchaseResult",
}

local folder = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
if not folder or not folder:IsA("Folder") then
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = REMOTES_NAME
	folder.Parent = ReplicatedStorage
end

for _, remoteName in REMOTE_NAMES do
	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		continue
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = folder
end
