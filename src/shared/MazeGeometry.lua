--!strict
-- Pure maze-geometry math extracted from MapBuilder.lua (see that file's own
-- WING_CONFIGS/mazeLocalToWorld/mazeCellCenter/assertMazeConstants, which
-- this is the single source of truth for) so it's independently testable
-- under Lune (test/mazeGeometry.test.luau) without a running Roblox engine
-- -- the same "pure logic in src/shared, if script then ... else ... end"
-- pattern GameLogic.lua/NumberFormat.lua/SpeedCalculator.lua already use.
-- Deliberately has zero references to Roblox-only globals (Color3, Random,
-- Instance) so it loads cleanly under both Rojo and a standalone Luau
-- runtime; MapBuilder.lua owns everything Roblox-specific (part creation,
-- wing theme colors, the Random seed used to actually generate a maze
-- grid's cell layout).
local MazeGeometry = {}

MazeGeometry.CELL_SIZE = 18 -- also each cell's run length before the next wall/junction
MazeGeometry.CELL_SPACING = MazeGeometry.CELL_SIZE -- cells touch edge-to-edge -- floor is contiguous, walls (not gaps) carve the maze
MazeGeometry.WALL_HEIGHT = 16
MazeGeometry.THICKNESS = 2 -- floor/ceiling thickness
MazeGeometry.BASE_Y = 20 -- Level 1's walkable height
MazeGeometry.LEVEL_HEIGHT = 40 -- vertical gap between consecutive levels
MazeGeometry.GATE_DEPTH = 50
MazeGeometry.GATE_SPAN = 28
MazeGeometry.RAMP_START_DEPTH = 75
MazeGeometry.ENTRY_DEPTH = 160

-- Per-wing difficulty: grid size and level count scale up from North
-- (easiest/smallest) through West (hardest/largest). Geometry only --
-- MapBuilder.lua's own WING_CONFIGS adds each wing's theme colors on top of
-- these same numbers, rather than duplicating them.
export type WingGeometryConfig = {
	gridWidth: number, -- cells across, lateral (perpendicular to the wing's outward direction)
	gridDepth: number, -- cells deep, outward from spawn
	levelCount: number,
}
local WING_CONFIGS: { [string]: WingGeometryConfig } = {
	MazeN = { gridWidth = 5, gridDepth = 8, levelCount = 1 },
	MazeS = { gridWidth = 7, gridDepth = 16, levelCount = 2 },
	MazeE = { gridWidth = 9, gridDepth = 20, levelCount = 3 },
	MazeW = { gridWidth = 11, gridDepth = 26, levelCount = 5 },
}
MazeGeometry.WING_CONFIGS = WING_CONFIGS

export type MazeDirection = "+X" | "-X" | "+Z" | "-Z"

-- Which world axis is "depth" for each compass direction, and which sign
-- along that axis is "outward" -- the single source of truth every other
-- maze function reads from.
local DIRECTION_INFO: { [MazeDirection]: { axis: "X" | "Z", sign: number } } = {
	["+Z"] = { axis = "Z", sign = 1 },
	["-Z"] = { axis = "Z", sign = -1 },
	["+X"] = { axis = "X", sign = 1 },
	["-X"] = { axis = "X", sign = -1 },
}
MazeGeometry.DIRECTION_INFO = DIRECTION_INFO

-- Maps a wing-local (lateral, depth) offset -- lateral perpendicular to the
-- wing's outward direction, depth increasing away from spawn -- into world
-- X/Z.
function MazeGeometry.LocalToWorld(direction: MazeDirection, lateral: number, depth: number): (number, number)
	local info = MazeGeometry.DIRECTION_INFO[direction]
	local signedDepth = info.sign * depth
	if info.axis == "Z" then
		return lateral, signedDepth
	else
		return signedDepth, lateral
	end
end

-- The lateral offset of grid column `col`, centered on the grid's own width.
function MazeGeometry.LateralOffset(col: number, gridWidth: number): number
	return (col - (gridWidth + 1) / 2) * MazeGeometry.CELL_SPACING
end

-- The depth offset of grid row `row`, 0 at row 1 (nearest spawn) and
-- increasing outward.
function MazeGeometry.DepthOffset(row: number): number
	return (row - 1) * MazeGeometry.CELL_SPACING
end

-- The center of grid cell (col, row) in a wing extending in `direction` from
-- the origin -- col is 1..gridWidth (lateral), row is 1..gridDepth (1 =
-- nearest spawn).
function MazeGeometry.CellCenter(direction: MazeDirection, col: number, row: number, gridWidth: number): (number, number)
	return MazeGeometry.LocalToWorld(direction, MazeGeometry.LateralOffset(col, gridWidth), MazeGeometry.ENTRY_DEPTH + MazeGeometry.DepthOffset(row))
end

-- How far a wing extending `gridWidth` cells across spreads sideways from
-- its own centerline. A wing's parts only start existing beyond depth
-- ENTRY_DEPTH along its own outward axis, so as long as no wing's halfExtent
-- reaches that far, two wings can never geometrically intersect -- see
-- MapBuilder.lua's assertMazeConstants, which asserts this same value stays
-- under ENTRY_DEPTH - 10 for every WING_CONFIGS entry.
function MazeGeometry.WingHalfExtent(gridWidth: number): number
	return gridWidth * MazeGeometry.CELL_SPACING / 2
end

-- Distance from the origin to one of a wing's gate pillars (span GATE_SPAN,
-- depth GATE_DEPTH) -- MapBuilder.lua's assertMazeConstants checks this
-- clears the spawn ring's own radius with margin.
function MazeGeometry.GateClearance(): number
	return math.sqrt((MazeGeometry.GATE_SPAN / 2) ^ 2 + MazeGeometry.GATE_DEPTH ^ 2)
end

return MazeGeometry
