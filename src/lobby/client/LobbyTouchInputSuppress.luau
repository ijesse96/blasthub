--!strict
-- Disables Roblox mobile thumbstick/jump while lobby modal UI is open.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local holders: { [string]: true } = {}
local suppressing = false
local savedTouchGuiEnabled: boolean? = nil
local savedTouchControlsEnabled: boolean? = nil
local touchGuiSuppressConn: RBXScriptConnection? = nil

local M = {}

local function getPlayerGui(): PlayerGui
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

local function holderCount(): number
	local n = 0
	for _ in holders do
		n += 1
	end
	return n
end

local function beginSuppress()
	if suppressing or not UserInputService.TouchEnabled then
		return
	end
	suppressing = true

	local okTc, curTc = pcall(function()
		return GuiService.TouchControlsEnabled
	end)
	if okTc and typeof(curTc) == "boolean" then
		savedTouchControlsEnabled = curTc
		pcall(function()
			GuiService.TouchControlsEnabled = false
		end)
	end

	local tg = getPlayerGui():FindFirstChild("TouchGui")
	if tg and tg:IsA("ScreenGui") then
		if savedTouchGuiEnabled == nil then
			savedTouchGuiEnabled = tg.Enabled
		end
		tg.Enabled = false
	end

	if touchGuiSuppressConn then
		return
	end
	touchGuiSuppressConn = RunService.RenderStepped:Connect(function()
		if not suppressing then
			return
		end
		local t = getPlayerGui():FindFirstChild("TouchGui")
		if t and t:IsA("ScreenGui") and t.Enabled then
			t.Enabled = false
		end
	end)
end

local function endSuppress()
	if not suppressing then
		return
	end
	suppressing = false

	if touchGuiSuppressConn then
		touchGuiSuppressConn:Disconnect()
		touchGuiSuppressConn = nil
	end

	local tg = getPlayerGui():FindFirstChild("TouchGui")
	if tg and tg:IsA("ScreenGui") then
		tg.Enabled = if savedTouchGuiEnabled == nil then true else savedTouchGuiEnabled
	end
	savedTouchGuiEnabled = nil

	if savedTouchControlsEnabled ~= nil then
		local restoreTc = savedTouchControlsEnabled
		savedTouchControlsEnabled = nil
		pcall(function()
			GuiService.TouchControlsEnabled = restoreTc
		end)
	end
end

local function syncSuppressState()
	if holderCount() > 0 then
		beginSuppress()
	else
		endSuppress()
	end
end

function M.setHolder(holderId: string, active: boolean)
	if active then
		if holders[holderId] then
			return
		end
		holders[holderId] = true
	else
		if not holders[holderId] then
			return
		end
		holders[holderId] = nil
	end
	syncSuppressState()
end

return M
