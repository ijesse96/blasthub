-- Creates LobbyRemotes early so client UI is not blocked waiting for server handlers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_NAME = "LobbyRemotes"
local REMOTE_NAMES = {
	"RequestJoinMap",
	"RequestTeleportToMain",
	"LobbyJoinResult",
	"RequestCoinPurchase",
	"AtmPurchaseResult",
	"RequestDailySpin",
	"DailySpinResult",
	"JoinBattleQueue",
	"AttackCastle",
	"LeaveBattleQueue",
	"MatchFound",
	"BattlePlacementState",
	"BattlePlacementAction",
	"BattleSetReady",
	"BattleResult",
	"BattleQueueStatus",
	"BattleCombatUpdate",
	"BattleSummon",
	"RequestTeleportToBattleGrounds",
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
