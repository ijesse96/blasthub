local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_NAME = "BattleGroundsRemotes"
local REMOTE_NAMES = {
	"JoinBattleQueue",
	"LeaveBattleQueue",
	"MatchFound",
	"BattlePlacementState",
	"BattleCombatUpdate",
	"BattleResult",
	"BattleQueueStatus",
}

local folder = ReplicatedStorage:FindFirstChild(REMOTES_NAME)
if folder and not folder:IsA("Folder") then
	folder:Destroy()
	folder = nil
end
if not folder then
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
