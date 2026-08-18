-- Headless test runner for src/shared/MazeGeometry.lua, run via:
-- lune run test/mazeGeometry.test.luau
-- Exercises the pure maze-geometry math shared with MapBuilder.lua's actual
-- part-building code, without needing a Roblox Studio session. See the
-- test-automation plan's "Tier 1" section for why this exists: these are
-- exactly the bounds/overlap properties that were previously only checked
-- by a runtime assert inside MapBuilder.Build()'s pcall -- i.e. only ever
-- actually executed when a human pressed Play in Studio.
local process = require("@lune/process")
local MazeGeometry = require("../src/shared/MazeGeometry")

local passed = 0
local failed = 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(("  [PASS] %s"):format(name))
	else
		failed += 1
		print(("  [FAIL] %s -- %s"):format(name, tostring(err)))
	end
end

local function assertEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(("%s (expected %s, got %s)"):format(message or "values differ", tostring(expected), tostring(actual)))
	end
end

print("MazeGeometry (Lune)")

-- Mirrors MapBuilder.lua's SPAWN_CLEAR_RADIUS (32) / SPAWN_RING_PADDING (4)
-- -- not part of MazeGeometry itself (they're also used by non-maze spawn
-- ring decoration), duplicated here only as the comparison assertMazeConstants
-- makes against MazeGeometry.GateClearance().
local SPAWN_CLEAR_RADIUS = 32
local SPAWN_RING_PADDING = 4

test("GateClearance clears the spawn ring with margin", function()
	local clearance = MazeGeometry.GateClearance()
	if clearance <= SPAWN_CLEAR_RADIUS + SPAWN_RING_PADDING + 2 then
		error(("gate clearance %s does not clear the spawn ring (%s) with margin"):format(clearance, SPAWN_CLEAR_RADIUS + SPAWN_RING_PADDING + 2))
	end
end)

test("every WING_CONFIGS entry's lateral half-extent stays under ENTRY_DEPTH", function()
	for wingName, config in pairs(MazeGeometry.WING_CONFIGS) do
		local halfExtent = MazeGeometry.WingHalfExtent(config.gridWidth)
		if halfExtent >= MazeGeometry.ENTRY_DEPTH - 10 then
			error(("%s: half-extent %s does not stay clear of ENTRY_DEPTH (%s)"):format(wingName, halfExtent, MazeGeometry.ENTRY_DEPTH))
		end
	end
end)

test("LEVEL_HEIGHT clears a level's ceiling from the next level's floor", function()
	if MazeGeometry.LEVEL_HEIGHT <= MazeGeometry.WALL_HEIGHT + 2 * MazeGeometry.THICKNESS then
		error("LEVEL_HEIGHT too small: a level's ceiling would collide with the next level's floor")
	end
end)

test("LocalToWorld maps +Z outward with lateral as X", function()
	local x, z = MazeGeometry.LocalToWorld("+Z", 5, 10)
	assertEqual(x, 5, "x")
	assertEqual(z, 10, "z")
end)

test("LocalToWorld maps -Z outward with lateral as X, depth negated", function()
	local x, z = MazeGeometry.LocalToWorld("-Z", 5, 10)
	assertEqual(x, 5, "x")
	assertEqual(z, -10, "z")
end)

test("LocalToWorld maps +X outward with lateral as Z", function()
	local x, z = MazeGeometry.LocalToWorld("+X", 5, 10)
	assertEqual(x, 10, "x")
	assertEqual(z, 5, "z")
end)

test("LocalToWorld maps -X outward with lateral as Z, depth negated", function()
	local x, z = MazeGeometry.LocalToWorld("-X", 5, 10)
	assertEqual(x, -10, "x")
	assertEqual(z, 5, "z")
end)

test("LateralOffset centers on the grid's own width", function()
	-- gridWidth 5 (odd): column 3 is dead center -> offset 0.
	assertEqual(MazeGeometry.LateralOffset(3, 5), 0, "center column")
	assertEqual(MazeGeometry.LateralOffset(1, 5), -2 * MazeGeometry.CELL_SPACING, "leftmost column")
	assertEqual(MazeGeometry.LateralOffset(5, 5), 2 * MazeGeometry.CELL_SPACING, "rightmost column")
end)

test("DepthOffset is 0 at row 1 and increases outward", function()
	assertEqual(MazeGeometry.DepthOffset(1), 0, "row 1")
	assertEqual(MazeGeometry.DepthOffset(3), 2 * MazeGeometry.CELL_SPACING, "row 3")
end)

test("CellCenter combines LocalToWorld/LateralOffset/DepthOffset starting at ENTRY_DEPTH", function()
	local x, z = MazeGeometry.CellCenter("+Z", 3, 1, 5)
	assertEqual(x, 0, "center column, row 1 -> lateral 0")
	assertEqual(z, MazeGeometry.ENTRY_DEPTH, "row 1 sits exactly at ENTRY_DEPTH")
end)

test("no two wings' lateral spreads can overlap the origin-adjacent gap", function()
	-- Every wing's own parts only start beyond ENTRY_DEPTH along its own
	-- outward axis (see CellCenter above), so as long as every wing's
	-- halfExtent stays under ENTRY_DEPTH (checked above), two wings on
	-- perpendicular axes can never geometrically intersect near the origin.
	for wingName, config in pairs(MazeGeometry.WING_CONFIGS) do
		local halfExtent = MazeGeometry.WingHalfExtent(config.gridWidth)
		if halfExtent >= MazeGeometry.ENTRY_DEPTH then
			error(("%s: half-extent %s reaches ENTRY_DEPTH, could overlap a perpendicular wing"):format(wingName, halfExtent))
		end
	end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
