local Players = game:GetService("Players")

-- Optional hook for arrivals from the lobby (or any TeleportService teleport).
-- `player:GetJoinData().TeleportData` is set from the lobby via TeleportOptions.

Players.PlayerAdded:Connect(function(player: Player)
	local joinData = player:GetJoinData()
	if joinData and joinData.TeleportData == "from_lobby" then
		-- Extend here (spawn location, welcome UI, analytics, etc.).
	end
end)
