local Players = game:GetService("Players")

-- Optional hook for arrivals from the lobby (or any TeleportService teleport).
-- `player:GetJoinData().TeleportData` is set from the lobby via TeleportOptions.

local function parseTeleportData(player: Player): (string?, string?)
	local joinData = player:GetJoinData()
	local raw = if joinData then joinData.TeleportData else nil

	if typeof(raw) == "table" then
		local data = raw :: { [any]: any }
		local kind = if typeof(data.kind) == "string" then data.kind else nil
		local mapId = if typeof(data.mapId) == "string" then data.mapId else nil
		return kind, mapId
	end

	if typeof(raw) == "string" and raw == "from_lobby" then
		return "match", "main"
	end

	return nil, nil
end

Players.PlayerAdded:Connect(function(player: Player)
	local kind, mapId = parseTeleportData(player)
	if kind then
		player:SetAttribute("JoinKind", kind)
		if mapId then
			player:SetAttribute("JoinMapId", mapId)
		end
	end

	if kind == "match" then
		-- Extend here (spawn location, welcome UI, analytics, etc.).
	end
end)
