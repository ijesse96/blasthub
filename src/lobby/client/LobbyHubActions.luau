--!strict
-- Shared callbacks from LobbyHub for other lobby client UI (e.g. CashHud + button).
local LobbyHubActions = {}

local openBuyCoinsCallback: (() -> ())? = nil

function LobbyHubActions.registerOpenBuyCoins(callback: () -> ())
	openBuyCoinsCallback = callback
end

function LobbyHubActions.openBuyCoins()
	if openBuyCoinsCallback then
		openBuyCoinsCallback()
	end
end

return LobbyHubActions
