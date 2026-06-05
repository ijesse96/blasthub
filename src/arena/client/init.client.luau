-- Arena client bootstrap: runs before other ArenaClient LocalScripts (alphabetical).
-- Turret control: Workspace > Anti Air > body > Seat > Script > control

local Players = game:GetService("Players")

local MatchRoundHudBootstrap = require(script.Parent:WaitForChild("MatchRoundHudBootstrap"))

local player = Players.LocalPlayer

local function runLegacyCleanup()
	MatchRoundHudBootstrap.destroyLegacyScripts(player)
end

player:WaitForChild("PlayerScripts")
runLegacyCleanup()
task.defer(runLegacyCleanup)

player.CharacterAdded:Connect(runLegacyCleanup)
