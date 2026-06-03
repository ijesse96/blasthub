-- Mount grid UI first; battle modules wait on ReplicatedStorage.Shared separately.
local BattleGroundsGridScreen = require(script.Parent:WaitForChild("BattleGroundsGridScreen"))

BattleGroundsGridScreen.mount()

task.spawn(function()
	local ok, err = pcall(function()
		local BattleGroundsQueue = require(script.Parent:WaitForChild("BattleGroundsQueue"))
		BattleGroundsQueue.init()
	end)
	if not ok then
		warn("[BattleGrounds] Queue init failed:", err)
	end
end)
