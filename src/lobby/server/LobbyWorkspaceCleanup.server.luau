-- UI-only lobby: remove legacy 3D interactables and broken Studio portal scripts.
local Workspace = game:GetService("Workspace")

local LEGACY_ROOT_NAMES = {
	"Teleport Portals",
	"ATM",
	"portal blue",
	"daily spin",
}

for _, name in LEGACY_ROOT_NAMES do
	local inst = Workspace:FindFirstChild(name)
	if inst then
		inst:Destroy()
	end
end
