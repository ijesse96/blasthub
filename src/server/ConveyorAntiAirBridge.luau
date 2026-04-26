--!strict
-- Lets other server scripts report conveyor hits from simulated projectiles (same as touch-based hits).

local CONVEYOR_ITEM_ATTRIBUTE = "IsConveyorItem"

local handler: ((Model, BasePart, Player?) -> ())?

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

function M.setProjectileConveyorHitHandler(fn: (model: Model, projectile: BasePart, shooter: Player?) -> ())
	handler = fn
end

function M.notifyProjectileConveyorHit(hitPart: BasePart, projectile: BasePart, shooter: Player?)
	local model = getConveyorModelFromInstance(hitPart)
	if model and handler then
		handler(model, projectile, shooter)
	end
end

return M
