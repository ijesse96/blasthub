--!strict
-- Fish Frenzy: storm ocean on Baseplate only while jackpot monster event is active.

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchSplashConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSplashConfig"))
local SplashKillFishFrames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SplashKillFishFrames"))

local MAP_ID = "main"
if MatchSplashConfig.getActiveMapId() ~= MAP_ID then
	return
end

local frames = MatchSplashConfig.getBaseplateStormFrameIds(MAP_ID)
if not frames or #frames < 8 then
	return
end

local STEP_SEC = MatchSplashConfig.getBaseplateStormFrameStepSec(MAP_ID)
local CHOP_REPEAT = MatchSplashConfig.getBaseplateStormChopRepeatCount(MAP_ID)
local NORMAL_TEXTURE = MatchSplashConfig.getBaseplateNormalTextureId(MAP_ID)
local STORM_COLOR = MatchSplashConfig.getBaseplateStormColor(MAP_ID)
local STORM_BRIGHTNESS = MatchSplashConfig.getBaseplateStormBrightness(MAP_ID)
local STORM_AMBIENT = MatchSplashConfig.getBaseplateStormAmbient(MAP_ID)
local MONSTER_EVENT_ATTRIBUTE = SplashKillFishFrames.MONSTER_EVENT_ACTIVE_ATTRIBUTE

local BASEPLATE_NAME = "Baseplate"
local TEXTURE_NAME = "WaterBackground"

local baseplate = Workspace:WaitForChild(BASEPLATE_NAME, 120)
if not baseplate or not baseplate:IsA("BasePart") then
	return
end

local texture = baseplate:WaitForChild(TEXTURE_NAME, 30)
if not texture or not texture:IsA("Texture") then
	return
end

local calmBaseplateColor = baseplate.Color
local calmBrightness = Lighting.Brightness
local calmAmbient = Lighting.Ambient

local stormLoopGen = 0

task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync(frames)
		ContentProvider:PreloadAsync({ NORMAL_TEXTURE })
	end)
end)

local function isMonsterEventActive(): boolean
	return Workspace:GetAttribute(MONSTER_EVENT_ATTRIBUTE) == true
end

local function applyCalmOcean()
	texture.Texture = NORMAL_TEXTURE
	texture.OffsetStudsU = 0
	texture.OffsetStudsV = 0
	baseplate.Color = calmBaseplateColor
	Lighting.Brightness = calmBrightness
	Lighting.Ambient = calmAmbient
end

local function applyStormAtmosphere()
	texture.OffsetStudsU = 0
	texture.OffsetStudsV = 0
	baseplate.Color = STORM_COLOR
	Lighting.Brightness = STORM_BRIGHTNESS
	Lighting.Ambient = STORM_AMBIENT
end

local function cancelStormLoop()
	stormLoopGen += 1
end

local function setStormFrame(index: number)
	local id = frames[index]
	if id then
		texture.Texture = id
	end
end

local function runStormLoop(activeGen: number)
	applyStormAtmosphere()

	while texture.Parent and stormLoopGen == activeGen and isMonsterEventActive() do
		for i = 1, #frames do
			if not texture.Parent or stormLoopGen ~= activeGen or not isMonsterEventActive() then
				return
			end
			setStormFrame(i)
			task.wait(STEP_SEC)
		end

		for _ = 1, CHOP_REPEAT do
			for i = #frames, math.max(#frames - 2, 1), -1 do
				if not texture.Parent or stormLoopGen ~= activeGen or not isMonsterEventActive() then
					return
				end
				setStormFrame(i)
				task.wait(STEP_SEC)
			end
		end
	end
end

local function onMonsterEventChanged()
	cancelStormLoop()

	if isMonsterEventActive() then
		local activeGen = stormLoopGen
		task.spawn(function()
			runStormLoop(activeGen)
		end)
	else
		applyCalmOcean()
	end
end

Workspace:GetAttributeChangedSignal(MONSTER_EVENT_ATTRIBUTE):Connect(onMonsterEventChanged)

if isMonsterEventActive() then
	onMonsterEventChanged()
else
	applyCalmOcean()
end
