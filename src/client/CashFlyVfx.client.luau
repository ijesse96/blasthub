local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashFlyVfxUtil = require(script.Parent:WaitForChild("CashFlyVfxUtil"))

local CASH_FLY_VFX_REMOTE_NAME = "CashFlyVfx"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remote = ReplicatedStorage:WaitForChild(CASH_FLY_VFX_REMOTE_NAME, 60)
if not remote or not remote:IsA("RemoteEvent") then
	warn("[CashFlyVfx] Missing RemoteEvent", CASH_FLY_VFX_REMOTE_NAME)
	return
end

remote.OnClientEvent:Connect(function(worldPos: Vector3, amount: any)
	if typeof(worldPos) ~= "Vector3" then
		return
	end
	if typeof(amount) ~= "number" or amount <= 0 then
		return
	end
	CashFlyVfxUtil.playFlyFromWorld(playerGui, worldPos, amount)
end)
