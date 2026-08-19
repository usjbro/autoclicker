-- Headless test runner for src/shared/MazeGeometry.lua, run via:
-- lune run test/mazeGeometry.test.luau
-- Exercises the pure maze-geometry math shared with MapBuilder.lua's actual
-- part-building code, without needing a Roblox Studio session.
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

test("every WING_CONFIGS entry's footprint equals TILE_FOOTPRINT", function()
	for wingName, config in pairs(MazeGeometry.WING_CONFIGS) do
		local footprint = config.gridSize * config.cellSize
		assertEqual(footprint, MazeGeometry.TILE_FOOTPRINT, wingName .. " footprint")
	end
end)

test("every wing has a WING_ANCHORS entry", function()
	for wingName in pairs(MazeGeometry.WING_CONFIGS) do
		assertEqual(MazeGeometry.WING_ANCHORS[wingName] ~= nil, true, wingName .. " has an anchor")
	end
end)

test("wing anchors are spaced far enough apart to never overlap", function()
	local halfFootprint = MazeGeometry.TILE_FOOTPRINT / 2
	local names = { "MazeN", "MazeE", "MazeS", "MazeW" }
	for i = 1, #names do
		for j = i + 1, #names do
			local a, b = MazeGeometry.WING_ANCHORS[names[i]], MazeGeometry.WING_ANCHORS[names[j]]
			local dx, dz = a.x - b.x, a.z - b.z
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance <= halfFootprint * 2 then
				error(("%s and %s anchors are only %s studs apart, footprints could overlap"):format(names[i], names[j], distance))
			end
		end
	end
end)

test("CenterCell returns the true middle of an odd-sized grid", function()
	local col, row = MazeGeometry.CenterCell(9)
	assertEqual(col, 5, "col")
	assertEqual(row, 5, "row")
end)

test("TileCellCenter places the center cell exactly on the anchor", function()
	local centerCol, centerRow = MazeGeometry.CenterCell(9)
	local x, z = MazeGeometry.TileCellCenter(100, -200, centerCol, centerRow, 9, 18)
	assertEqual(x, 100, "x")
	assertEqual(z, -200, "z")
end)

test("TileCellCenter offsets non-center cells by cellSize per step", function()
	local x1, z1 = MazeGeometry.TileCellCenter(0, 0, 5, 5, 9, 18)
	local x2, z2 = MazeGeometry.TileCellCenter(0, 0, 6, 5, 9, 18)
	assertEqual(x2 - x1, 18, "one column step moves x by cellSize")
	assertEqual(z2 - z1, 0, "row unchanged, z unchanged")
end)

-- A hand-built 3x3 grid, connections forming a straight corridor down
-- column 2 then across row 3 -- (2,1) -> (2,2) -> (2,3) -> (3,3) -- so
-- starting at (2,1) (distance 0), the farthest cell is (3,3) at distance 3.
-- Every other cell is deliberately left disconnected (all flags false) to
-- confirm FarthestCell only walks real carved connections, not blank
-- unreachable cells.
local function buildTestGrid(): any
	local grid = {}
	for col = 1, 3 do
		grid[col] = {}
		for row = 1, 3 do
			grid[col][row] = { north = false, south = false, east = false, west = false }
		end
	end
	grid[2][1].south = true
	grid[2][2].north = true
	grid[2][2].south = true
	grid[2][3].north = true
	grid[2][3].east = true
	grid[3][3].west = true
	return grid
end

test("FarthestCell finds the true farthest reachable cell via a known path", function()
	local grid = buildTestGrid()
	local col, row, distance = MazeGeometry.FarthestCell(grid, 2, 1)
	assertEqual(col, 3, "farthest col")
	assertEqual(row, 3, "farthest row")
	assertEqual(distance, 3, "path distance")
end)

test("FarthestCell returns the start cell itself with distance 0 when nothing is reachable", function()
	local grid = {}
	for col = 1, 2 do
		grid[col] = {}
		for row = 1, 2 do
			grid[col][row] = { north = false, south = false, east = false, west = false }
		end
	end
	local col, row, distance = MazeGeometry.FarthestCell(grid, 1, 1)
	assertEqual(col, 1, "col")
	assertEqual(row, 1, "row")
	assertEqual(distance, 0, "distance")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
