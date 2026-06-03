--!strict
-- King of the Jungle only: removes stale WaterSplashSpawner copies pasted from Fish Frenzy.

local KING_PLACE_ID = 82834864756259
local LOG = "[KillLegacyWaterSplash]"

if game.PlaceId ~= KING_PLACE_ID then
	return
end

local removed = 0
for _, inst in game:GetDescendants() do
	if inst.Name == "WaterSplashSpawner" and inst:IsA("Script") then
		inst.Enabled = false
		warn(LOG, "Removing", inst:GetFullName())
		inst:Destroy()
		removed += 1
	end
end

print(string.format("%s Done (removed %d). PlaceId=%s", LOG, removed, tostring(game.PlaceId)))
