--!strict
-- Full-screen input sink so modal UI does not pass taps to ScreenGuis behind it.

local Players = game:GetService("Players")

local LobbyModalInputBlock = {}

local hubBlockHolders: { [string]: true } = {}
local savedHubButtonInteractable: { [GuiButton]: boolean } = {}

export type BlockerOptions = {
	name: string?,
	zIndex: number?,
	backgroundTransparency: number?,
	dimColor: Color3?,
	onScrimPress: (() -> ())?,
}

function LobbyModalInputBlock.create(parent: Instance, options: BlockerOptions?): TextButton
	local opts = options or {}
	local blocker = Instance.new("TextButton")
	blocker.Name = opts.name or "InputBlocker"
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.Position = UDim2.fromOffset(0, 0)
	blocker.BackgroundColor3 = opts.dimColor or Color3.new(0, 0, 0)
	blocker.BackgroundTransparency = opts.backgroundTransparency or 1
	blocker.BorderSizePixel = 0
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.Active = true
	blocker.Selectable = false
	blocker.ZIndex = opts.zIndex or 1
	blocker.Parent = parent

	if opts.onScrimPress then
		local busy = false
		blocker.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			opts.onScrimPress()
			task.defer(function()
				busy = false
			end)
		end)
	end

	return blocker
end

function LobbyModalInputBlock.setSinkActive(gui: GuiObject, active: boolean)
	gui.Active = active
end

local function syncLobbyHubInteractable()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	local hubGui = playerGui:FindFirstChild("LobbyHub")
	if not hubGui then
		return
	end

	local shouldEnable = next(hubBlockHolders) == nil
	for _, inst in hubGui:GetDescendants() do
		if inst:IsA("GuiButton") then
			if shouldEnable then
				local saved = savedHubButtonInteractable[inst]
				if saved ~= nil then
					inst.Interactable = saved
					savedHubButtonInteractable[inst] = nil
				end
			else
				if savedHubButtonInteractable[inst] == nil then
					savedHubButtonInteractable[inst] = inst.Interactable
				end
				inst.Interactable = false
			end
		end
	end
end

function LobbyModalInputBlock.setLobbyHubBlocked(holderId: string, blocked: boolean)
	if blocked then
		if hubBlockHolders[holderId] then
			return
		end
		hubBlockHolders[holderId] = true
	else
		if not hubBlockHolders[holderId] then
			return
		end
		hubBlockHolders[holderId] = nil
	end
	syncLobbyHubInteractable()
end

return LobbyModalInputBlock
