--!strict
-- Tunables for Anti Air turret PNG dress-up (top-down SurfaceGui + optional mesh hide).

return {
	dressVersion = 7,
	dressImageId = "rbxassetid://126072062194764",
	hideBaseMesh = true,
	footprintSizeMultiplier = 3.75,
	anchorThickness = 0.08,
	surfacePixelsPerStud = 45,
	yawOffsetDegrees = 270,
	lightInfluence = 0,
	-- Lift from bbox center (studs). Tune in Studio if PNG sits too high/low.
	studsOffsetWorldSpace = Vector3.zero,
}
