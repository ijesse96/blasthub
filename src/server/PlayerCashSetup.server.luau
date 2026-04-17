local Players = game:GetService("Players")

local moneyModule = script.Parent:FindFirstChild("Money") or script.Parent:WaitForChild("Money", 30)
if not moneyModule or not moneyModule:IsA("ModuleScript") then
	warn("[PlayerCashSetup] Missing sibling ModuleScript 'Money' — cash leaderstats will not be created.")
	return
end
local Money = require(moneyModule)

local function onPlayerAdded(player: Player)
	Money.setupPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
