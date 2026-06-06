--!strict
-- Fish Frenzy: sharks-only arena targets; water splash ripple animation disabled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))

if MatchSplashConfig.getActiveMapId() ~= "main" then
	return
end

return
