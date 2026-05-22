local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FishCollectionService = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FishCollectionService"))

FishCollectionService.start()
