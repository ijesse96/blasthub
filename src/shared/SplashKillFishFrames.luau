--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FRAMES_FOLDER_NAME = "commonsplashfishframes"
local FALLBACK_IMAGE_ID = "rbxassetid://134499702905260"
local IMAGE_ID_ATTRIBUTE = "SplashKillFishImageId"

local frameIdsCache: { string }? = nil
local warnedMissingFrames = false

local function getFrameIds(): { string }
	if frameIdsCache ~= nil then
		return frameIdsCache
	end
	local folder = ReplicatedStorage:FindFirstChild(FRAMES_FOLDER_NAME)
	if not folder then
		frameIdsCache = {}
		return frameIdsCache
	end
	type FrameRow = { name: string, id: string }
	local rows: { FrameRow } = {}
	for _, ch in folder:GetChildren() do
		if ch:IsA("StringValue") then
			local v = ch.Value
			if typeof(v) == "string" and v ~= "" then
				table.insert(rows, { name = ch.Name, id = v })
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	local out: { string } = {}
	for _, r in rows do
		table.insert(out, r.id)
	end
	frameIdsCache = out
	return out
end

local function pickImageId(): string
	local frames = getFrameIds()
	if #frames >= 1 then
		return frames[math.random(1, #frames)]
	end
	if not warnedMissingFrames then
		warnedMissingFrames = true
		warn("[SplashKillFishFrames] commonsplashfishframes missing or empty; using fallback")
	end
	return FALLBACK_IMAGE_ID
end

return {
	FRAMES_FOLDER_NAME = FRAMES_FOLDER_NAME,
	FALLBACK_IMAGE_ID = FALLBACK_IMAGE_ID,
	IMAGE_ID_ATTRIBUTE = IMAGE_ID_ATTRIBUTE,
	getFrameIds = getFrameIds,
	pickImageId = pickImageId,
}
