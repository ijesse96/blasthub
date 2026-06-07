local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SplashKillFishFrames"))

local BASEPLATE_NAME = "Baseplate"
local TEXTURE_NAME = "WaterBackground"
-- Studs per second; tweak for stronger / calmer motion
local SPEED_U = 3
local SPEED_V = 1.5

local baseplate = Workspace:WaitForChild(BASEPLATE_NAME, 120)
if not baseplate or not baseplate:IsA("BasePart") then
	warn("[WaterBackgroundScroll] Baseplate missing or not a BasePart; skipping.")
	return
end

local texture = baseplate:WaitForChild(TEXTURE_NAME, 30)
if not texture or not texture:IsA("Texture") then
	warn("[WaterBackgroundScroll] Expected Texture named " .. TEXTURE_NAME .. " under Baseplate; skipping.")
	return
end

if not MatchSplashConfig.getForActiveMap().scrollWaterBackground then
	return
end

RunService.Heartbeat:Connect(function(dt: number)
	if Workspace:GetAttribute(SplashKillFishFrames.MONSTER_EVENT_ACTIVE_ATTRIBUTE) == true then
		return
	end
	texture.OffsetStudsU += SPEED_U * dt
	texture.OffsetStudsV += SPEED_V * dt
end)
