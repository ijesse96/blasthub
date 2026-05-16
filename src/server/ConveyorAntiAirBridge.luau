--!strict
-- Lets other server scripts report conveyor hits from simulated projectiles (same as touch-based hits).

local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"

export type PostHitRetract = {
	retractDuration: number?,
	retractFollowModel: Model?,
	retractFollowOffset: CFrame?,
	onRetractComplete: (() -> ())?,
	-- When true: ricochet sim stops at hit and waits for beginDeferredRetract (splash reel meter).
	deferSplashReelMeter: boolean?,
}

local handler: ((Model, BasePart, Player?) -> PostHitRetract?)?

local function getConveyorModelFromInstance(instance: Instance): Model?
	local current: Instance? = instance
	while current do
		if current:IsA("Model") and current:GetAttribute(CONVEYOR_ITEM_ATTRIBUTE) == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

local M = {}

function M.setProjectileConveyorHitHandler(fn: (model: Model, projectile: BasePart, shooter: Player?) -> PostHitRetract?)
	handler = fn
end

function M.notifyProjectileConveyorHit(hitPart: BasePart, projectile: BasePart, shooter: Player?): PostHitRetract?
	local model = getConveyorModelFromInstance(hitPart)
	if model and handler then
		return handler(model, projectile, shooter)
	end
	return nil
end

return M
