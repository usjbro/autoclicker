--!strict
-- Pure maze-geometry math extracted from MapBuilder.lua so it's
-- independently testable under Lune (test/mazeGeometry.test.luau) without
-- a running Roblox engine -- the same "pure logic in src/shared, if script
-- then ... else ... end" pattern GameLogic.lua/NumberFormat.lua/
-- SpeedCalculator.lua already use. Deliberately has zero references to
-- Roblox-only globals (Color3, Random, Instance) so it loads cleanly under
-- both Rojo and a standalone Luau runtime; MapBuilder.lua owns everything
-- Roblox-specific (part creation, wing theme colors, the Random seed used
-- to actually generate a maze grid's cell layout).
local MazeGeometry = {}

MazeGeometry.WALL_HEIGHT = 16
MazeGeometry.THICKNESS = 2 -- floor/ceiling thickness
MazeGeometry.BASE_Y = 20 -- the tile's walkable height

-- Every wing's maze fills the exact same fixed footprint (issue #60) --
-- difficulty comes entirely from cell density within that fixed footprint
-- (WING_CONFIGS below), not from a bigger or smaller plot of land.
-- gridSize * cellSize == this for every entry in WING_CONFIGS.
MazeGeometry.TILE_FOOTPRINT = 2048

-- Per-wing difficulty: a smaller cellSize packs more (smaller) cells into
-- the same TILE_FOOTPRINT, meaning more turns/decisions to reach the goal.
-- North (easiest) through West (hardest). Geometry only -- MapBuilder.lua's
-- own WING_CONFIGS adds each wing's theme colors on top of these same
-- numbers, rather than duplicating them.
export type WingGeometryConfig = {
	gridSize: number, -- cells per side -- every tile is a square grid
	cellSize: number, -- studs per cell; gridSize * cellSize == TILE_FOOTPRINT
}
local WING_CONFIGS: { [string]: WingGeometryConfig } = {
	MazeN = { gridSize = 16, cellSize = 128 },
	MazeS = { gridSize = 32, cellSize = 64 },
	MazeE = { gridSize = 64, cellSize = 32 },
	MazeW = { gridSize = 128, cellSize = 16 },
}
MazeGeometry.WING_CONFIGS = WING_CONFIGS

-- Each wing's tile is a self-contained pocket, not physically connected to
-- the shared hub -- these are just world-space anchor points (the tile's
-- own center) kept far apart so tiles can never overlap. Still one per
-- compass direction, matching the wing names, but now purely for spacing,
-- not for defining which way a corridor "extends" (nothing extends from
-- the hub anymore -- see MapBuilder.lua's wirePortal).
export type WingAnchor = { x: number, z: number }
local WING_ANCHORS: { [string]: WingAnchor } = {
	MazeN = { x = 0, z = -5000 },
	MazeE = { x = 5000, z = 0 },
	MazeS = { x = 0, z = 5000 },
	MazeW = { x = -5000, z = 0 },
}
MazeGeometry.WING_ANCHORS = WING_ANCHORS

-- The center of grid cell (col, row) of an N-by-N grid centered on
-- (anchorX, anchorZ) -- col/row both 1..gridSize. For an odd gridSize, the
-- center cell (see CenterCell below) sits exactly on the anchor. For an
-- even gridSize -- every real WING_CONFIGS entry today (16/32/64/128) --
-- there's no single cell exactly at the true geometric center (it falls
-- on a cell *boundary*, not inside any one cell), so the chosen center
-- cell is offset from the anchor by half a cellSize in both X and Z; this
-- is expected, not a bug -- confirmed in test/mazeGeometry.test.luau for
-- both an odd and an even gridSize, since only testing the odd case would
-- give false confidence about the even case every real tile actually
-- uses. Either way, this is where the player spawns (issue #60's "center
-- spawn").
function MazeGeometry.TileCellCenter(anchorX: number, anchorZ: number, col: number, row: number, gridSize: number, cellSize: number): (number, number)
	local worldX = anchorX + (col - (gridSize + 1) / 2) * cellSize
	local worldZ = anchorZ + (row - (gridSize + 1) / 2) * cellSize
	return worldX, worldZ
end

-- The 1-indexed column/row of an N-by-N grid's own center cell -- the
-- single source of truth both MapBuilder.lua (to place the player there)
-- and FarthestCell's caller (to BFS from there) read from, so they can
-- never disagree on which cell is "the center."
function MazeGeometry.CenterCell(gridSize: number): (number, number)
	local center = math.ceil((gridSize + 1) / 2)
	return center, center
end

-- Untyped-value cells ({[string]: boolean}, not a fixed record) so
-- FarthestCell below can index by a direction name held in a variable
-- ("north"/"south"/"east"/"west") -- Luau's strict mode only allows
-- dynamic string-keyed indexing against an index-signature type like this,
-- not a record type with fixed field names. Matches how MapBuilder.lua's
-- own maze-generation carving already stores a cell: each of the four
-- directions is set independently and symmetrically on both cells of a
-- carved connection (carving a passage east from (col,row) sets BOTH
-- grid[col][row].east AND grid[col+1][row].west), so adjacency in any
-- direction is always a direct flag check on the current cell, never a
-- lookup against a neighbor's own flags.
export type MazeCell = { [string]: boolean }
export type MazeGrid = { [number]: { [number]: MazeCell } }

-- Breadth-first search from (startCol, startRow) over grid's actual
-- carved connectivity, returning the column/row/path-distance of
-- whichever reachable cell ends up farthest away. Every cell in a perfect
-- maze (generateMaze's design -- a spanning tree, no loops) is reachable
-- from any other, so this always finds a real farthest cell, never falls
-- through with none found. Used to place the goal (issue #60: "the goal is
-- whichever reachable cell ends up farthest away, by maze-path distance,
-- not straight-line") -- deliberately BFS over the grid graph, not any
-- kind of straight-line/Euclidean distance calculation.
function MazeGeometry.FarthestCell(grid: MazeGrid, startCol: number, startRow: number): (number, number, number)
	local distance: { [number]: { [number]: number } } = {}
	distance[startCol] = { [startRow] = 0 }

	local queue = { { col = startCol, row = startRow } }
	local queueHead = 1
	local farthestCol, farthestRow, farthestDistance = startCol, startRow, 0

	local neighborOffsets = {
		{ open = "east", dCol = 1, dRow = 0 },
		{ open = "west", dCol = -1, dRow = 0 },
		{ open = "south", dCol = 0, dRow = 1 },
		{ open = "north", dCol = 0, dRow = -1 },
	}

	while queueHead <= #queue do
		local current = queue[queueHead]
		queueHead += 1
		local currentDistance = distance[current.col][current.row]
		local cell = grid[current.col][current.row]

		for _, offset in ipairs(neighborOffsets) do
			if cell[offset.open] then
				local nCol, nRow = current.col + offset.dCol, current.row + offset.dRow
				if not distance[nCol] then
					distance[nCol] = {}
				end
				if distance[nCol][nRow] == nil then
					local nextDistance = currentDistance + 1
					distance[nCol][nRow] = nextDistance
					table.insert(queue, { col = nCol, row = nRow })
					if nextDistance > farthestDistance then
						farthestDistance = nextDistance
						farthestCol, farthestRow = nCol, nRow
					end
				end
			end
		end
	end

	return farthestCol, farthestRow, farthestDistance
end

return MazeGeometry
