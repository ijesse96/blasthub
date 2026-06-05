--!strict
-- Shared bootstrap for MatchRoundHud: remove Studio-pasted duplicate LocalScripts.

local MatchRoundHudBootstrap = {}

local MATCH_ROUND_HUD_SCRIPT_NAME = "MatchRoundHud"
local CANONICAL_ARENA_CLIENT_FOLDER = "ArenaClient"

function MatchRoundHudBootstrap.isCanonicalScript(localScript: LocalScript): boolean
	local current: Instance? = localScript.Parent
	while current do
		if current.Name == CANONICAL_ARENA_CLIENT_FOLDER then
			return true
		end
		current = current.Parent
	end
	return false
end

function MatchRoundHudBootstrap.destroyLegacyScripts(player: Player)
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return
	end
	for _, inst in playerScripts:GetDescendants() do
		if inst:IsA("LocalScript") and inst.Name == MATCH_ROUND_HUD_SCRIPT_NAME then
			if not MatchRoundHudBootstrap.isCanonicalScript(inst) then
				inst:Destroy()
			end
		end
	end
end

return MatchRoundHudBootstrap
