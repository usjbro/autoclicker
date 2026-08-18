-- Open Cloud Luau-execution feasibility spike (Tier 2, see the test-automation
-- plan). Not run by any CLI/CI here -- this is the payload submitted via
-- test/openCloudSpike.sh to Roblox's Open Cloud API, executed inside a real
-- Roblox engine session against the published place. Proves the round trip
-- actually reaches this place's real content (not a blank template) by
-- checking for GameLogic under ReplicatedStorage.Shared and listing the
-- declared RemoteEvents, rather than just returning a trivial literal.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage:FindFirstChild("Shared")

local remoteEventNames = {}
for _, child in ipairs(ReplicatedStorage:GetChildren()) do
	if child:IsA("RemoteEvent") then
		table.insert(remoteEventNames, child.Name)
	end
end

return {
	placeId = game.PlaceId,
	gameId = game.GameId,
	hasSharedGameLogic = shared ~= nil and shared:FindFirstChild("GameLogic") ~= nil,
	remoteEventNames = remoteEventNames,
}
