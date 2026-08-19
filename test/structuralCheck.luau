-- Tier 2 structural instance test (test-automation plan). Submitted via
-- Open Cloud's Luau Execution API (test/openCloudStructuralCheck.sh) to run
-- inside a real Roblox engine session against the published place --
-- exercises true Instance.new/Parent assignment via a real
-- MapBuilder.Build() call, not just Tier 1's pure-math predictions
-- (test/mazeGeometry.test.luau), and asserts structural properties no
-- other tooling in this repo can check: every wing's goal part actually
-- exists and is named correctly, ReplicatedStorage has exactly the
-- RemoteEvents this repo declares, and no two wings' *actual* built
-- bounding boxes overlap (catching any drift between MazeGeometry's math
-- prediction and what MapBuilder really built).
--
-- Every Open Cloud Luau Execution task starts a fresh, isolated session
-- (not the live player-facing server), so calling MapBuilder.Build() here
-- is safe -- there's no pre-existing "Map" folder or live players to
-- collide with, unlike calling it against an already-running server.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapBuilder = require(ServerScriptService.Server.MapBuilder)

local failures: { string } = {}
local function check(condition: boolean, message: string)
	if not condition then
		table.insert(failures, message)
	end
end

local buildOk, buildErr = MapBuilder.Build()
check(buildOk, "MapBuilder.Build() failed: " .. tostring(buildErr))

if buildOk then
	local mapFolder = workspace:FindFirstChild("Map")
	check(mapFolder ~= nil, "workspace.Map folder not found after Build()")

	if mapFolder then
		-- wingName -> goal part name, matching GameConstants.MAZE_GOALS.
		local wings = {
			MazeN = "MazeNGoal",
			MazeS = "MazeSGoal",
			MazeE = "MazeEGoal",
			MazeW = "MazeWGoal",
		}

		-- Per-part world X/Z AABBs for every BasePart actually built for
		-- each wing -- computed from live Instances, not predicted math.
		-- Kept per-part (not collapsed into one box per wing) because a
		-- wing's true footprint is L-shaped, not rectangular: a narrow
		-- gate/ramp near the origin (see MAZE_GATE_DEPTH/MAZE_RAMP_START_
		-- DEPTH in MapBuilder.lua) connects to a much wider corridor
		-- further out. A single bounding box per wing would cover that
		-- entire L's rectangular hull, including empty space no real part
		-- occupies -- exactly the kind of thing that would make two
		-- wings' near-origin corners look like they overlap when no real
		-- geometry does.
		local wingParts: { [string]: { { minX: number, maxX: number, minZ: number, maxZ: number } } } = {}

		for wingName, goalName in pairs(wings) do
			local wingFolder = mapFolder:FindFirstChild(wingName)
			check(wingFolder ~= nil, wingName .. " folder not found under workspace.Map")
			if wingFolder then
				local goalPart = wingFolder:FindFirstChild(goalName, true)
				check(goalPart ~= nil, goalName .. " goal part not found under " .. wingName)
				check(goalPart ~= nil and goalPart:IsA("BasePart"), goalName .. " is not a BasePart")
				check(goalPart ~= nil and goalPart.Parent ~= nil, goalName .. " has no Parent")

				local parts = {}
				for _, descendant in ipairs(wingFolder:GetDescendants()) do
					if descendant:IsA("BasePart") then
						local pos = descendant.Position
						local half = descendant.Size / 2
						table.insert(parts, {
							minX = pos.X - half.X,
							maxX = pos.X + half.X,
							minZ = pos.Z - half.Z,
							maxZ = pos.Z + half.Z,
						})
					end
				end
				check(#parts > 0, wingName .. " has no BasePart descendants to measure")
				wingParts[wingName] = parts
			end
		end

		-- Broad phase: a cheap union AABB per wing. Two wings whose union
		-- boxes don't overlap at all can *never* have any real part
		-- overlap, so most wing pairs (perpendicular ones, and opposite
		-- ones across the origin) skip the expensive check entirely.
		local function unionBounds(parts)
			local u = nil
			for _, p in ipairs(parts) do
				if not u then
					u = { minX = p.minX, maxX = p.maxX, minZ = p.minZ, maxZ = p.maxZ }
				else
					u.minX = math.min(u.minX, p.minX)
					u.maxX = math.max(u.maxX, p.maxX)
					u.minZ = math.min(u.minZ, p.minZ)
					u.maxZ = math.max(u.maxZ, p.maxZ)
				end
			end
			return u
		end

		local function boundsOverlap(a, b)
			return a.minX < b.maxX and b.minX < a.maxX and a.minZ < b.maxZ and b.minZ < a.maxZ
		end

		local wingNames = { "MazeN", "MazeS", "MazeE", "MazeW" }
		local wingUnion = {}
		for _, wingName in ipairs(wingNames) do
			if wingParts[wingName] then
				wingUnion[wingName] = unionBounds(wingParts[wingName])
			end
		end

		for i = 1, #wingNames do
			for j = i + 1, #wingNames do
				local nameA, nameB = wingNames[i], wingNames[j]
				local unionA, unionB = wingUnion[nameA], wingUnion[nameB]
				if unionA and unionB and boundsOverlap(unionA, unionB) then
					-- Narrow phase: the coarse union boxes overlap, so
					-- check every real part pair between these two wings
					-- for a genuine overlap before reporting anything.
					local realOverlap = false
					for _, partA in ipairs(wingParts[nameA]) do
						for _, partB in ipairs(wingParts[nameB]) do
							if boundsOverlap(partA, partB) then
								realOverlap = true
								break
							end
						end
						if realOverlap then
							break
						end
					end
					check(not realOverlap, nameA .. " and " .. nameB .. " have overlapping built geometry")
				end
			end
		end
	end
end

local expectedRemoteEvents = {
	"ClickEvent",
	"PurchaseEvent",
	"ResetEvent",
	"RebirthEvent",
	"UpdateSpeedSettingsEvent",
	"PurchaseItemEvent",
	"EquipCosmeticEvent",
	"ActivateFlightEvent",
	"SyncState",
	"LeaderboardUpdate",
}
for _, name in ipairs(expectedRemoteEvents) do
	local instance = ReplicatedStorage:FindFirstChild(name)
	check(instance ~= nil, "Missing RemoteEvent under ReplicatedStorage: " .. name)
	check(instance ~= nil and instance:IsA("RemoteEvent"), name .. " exists but is not a RemoteEvent")
end

return {
	success = #failures == 0,
	failures = failures,
}
