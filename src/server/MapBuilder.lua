--!strict
-- Builds a static, explorable layout of platforms/ramps/stairs/decoration
-- inside the VoidBox for Movement mode. Pure geometry -- no gameplay state,
-- no RemoteEvents. Mirrors the pcall-wrapped-and-report-failure pattern
-- GameService.server.lua already uses for VoidBox/VoidFloor/VoidSpawn, so a
-- broken map can never take down the rest of the server's wiring.
--
-- Everything here is Anchored (static level, not physics-simulated) and
-- parented under a single "Map" Folder in workspace rather than scattered
-- loose parts alongside VoidBox/VoidFloor/VoidSpawn.
--
-- Palette matches the client UI (src/client/init.client.lua): #1e1e2f
-- (structural dark), #2a2a3f (platform/panel dark), #6c5ce7 (accent purple,
-- used sparingly via Neon trim so it reads as a highlight rather than the
-- primary material).
local MapBuilder = {}

local DARK = Color3.fromHex("1e1e2f")
local PANEL = Color3.fromHex("2a2a3f")
local ACCENT = Color3.fromHex("6c5ce7")

-- VoidSpawn sits at the origin (see GameService.server.lua); keep a clear
-- radius around it so nothing built here ever overlaps a spawning player.
local SPAWN_CLEAR_RADIUS = 32
-- How far outside SPAWN_CLEAR_RADIUS the spawn ring's own pillars sit --
-- shared by the ring-building code and assertMazeConstants below (which
-- checks every maze gate clears the ring, not just SPAWN_CLEAR_RADIUS
-- itself) so the two can't silently desync the way MAZE_GATE_SPAN's old
-- hardcoded duplicate could.
local SPAWN_RING_PADDING = 4

type PartOverrides = { [string]: any }

-- Common defaults every map part shares (Anchored, no shadows to match the
-- flat void look, SmoothPlastic base material) with per-call overrides for
-- Size/CFrame/Color/CanCollide/etc.
local function newPart(folder: Folder, name: string, overrides: PartOverrides): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = PANEL
	part.CanCollide = true
	part.Locked = true
	for key, value in pairs(overrides) do
		(part :: any)[key] = value
	end
	part.Parent = folder
	return part
end

-- A sloped slab spanning from p0 (ground-level start) to p1 (landing on the
-- platform it leads to). Oriented so its local X axis stays level
-- side-to-side while inclined front-to-back -- the standard Roblox ramp
-- technique -- so it works for any direction (not just axis-aligned) without
-- needing separate north/east/west-specific math.
local function createRamp(
	folder: Folder,
	name: string,
	p0: Vector3,
	p1: Vector3,
	width: number,
	thickness: number
): Part
	local diff = p1 - p0
	local length = diff.Magnitude
	local center = p0 + diff / 2
	local cf = CFrame.lookAt(center, center + diff.Unit, Vector3.new(0, 1, 0))
	return newPart(folder, name, {
		Size = Vector3.new(width, thickness, length),
		CFrame = cf,
		Color = PANEL,
	})
end

-- A solid ascending block staircase: each "step" is a box running from the
-- ground up to that step's top height, positioned progressively further
-- along a single (axis-aligned) direction. Solid blocks rather than thin
-- tread+riser pieces so fast-moving characters can't clip through gaps.
local function createStaircase(
	folder: Folder,
	name: string,
	origin: Vector3, -- ground-level point at the near edge of the first step
	axis: "X" | "Z",
	sign: number, -- 1 or -1, direction of travel along that axis
	steps: number,
	stepRun: number,
	stepRise: number,
	width: number
): Vector3 -- returns the landing point (top of the final step)
	for i = 1, steps do
		local stepHeight = i * stepRise
		local offset = sign * (stepRun * i - stepRun / 2)
		local centerX = if axis == "X" then origin.X + offset else origin.X
		local centerZ = if axis == "Z" then origin.Z + offset else origin.Z
		local sizeX = if axis == "X" then stepRun else width
		local sizeZ = if axis == "Z" then stepRun else width
		-- Spans from origin.Y (where the staircase starts, e.g. a
		-- platform's surface) up to origin.Y + stepHeight -- not from world
		-- y=0, which would leave the whole staircase floating disconnected
		-- below wherever origin.Y actually is.
		newPart(folder, name .. i, {
			Size = Vector3.new(sizeX, stepHeight, sizeZ),
			CFrame = CFrame.new(centerX, origin.Y + stepHeight / 2, centerZ),
			Color = if i % 2 == 0 then PANEL else DARK,
		})
	end
	local finalOffset = sign * (stepRun * steps)
	local landX = if axis == "X" then origin.X + finalOffset else origin.X
	local landZ = if axis == "Z" then origin.Z + finalOffset else origin.Z
	return Vector3.new(landX, origin.Y + steps * stepRise, landZ)
end

-- A flat elevated platform. `topY` is the walkable surface height; the part
-- itself is centered `thickness/2` below that so callers can reason about
-- ramps/stairs landing exactly on the surface instead of the part's center.
local function createPlatform(
	folder: Folder,
	name: string,
	centerX: number,
	topY: number,
	centerZ: number,
	sizeX: number,
	thickness: number,
	sizeZ: number
): Part
	local platform = newPart(folder, name, {
		Size = Vector3.new(sizeX, thickness, sizeZ),
		CFrame = CFrame.new(centerX, topY - thickness / 2, centerZ),
		Color = PANEL,
	})
	-- Thin accent-colored trim along the platform's edge (a slightly
	-- oversized, very thin Neon slab just under the surface) so each
	-- platform reads with a highlight, echoing the UI's accent color.
	newPart(folder, name .. "Trim", {
		Size = Vector3.new(sizeX + 1, 0.4, sizeZ + 1),
		CFrame = CFrame.new(centerX, topY - thickness - 0.2, centerZ),
		Color = ACCENT,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	return platform
end

-- A square structural pillar (blocky rather than a Roblox default cylinder,
-- to stay consistent with the platforms' flat-panel look) with a small
-- accent-colored cap.
local function createPillar(folder: Folder, name: string, groundPos: Vector3, height: number, thickness: number)
	newPart(folder, name, {
		Size = Vector3.new(thickness, height, thickness),
		CFrame = CFrame.new(groundPos.X, height / 2, groundPos.Z),
		Color = DARK,
	})
	newPart(folder, name .. "Cap", {
		Size = Vector3.new(thickness + 1, 0.8, thickness + 1),
		CFrame = CFrame.new(groundPos.X, height + 0.4, groundPos.Z),
		Color = ACCENT,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
end

-- A doorway-style arch: two pillars plus an accent-lit lintel beam spanning
-- them. `axis` is the direction of travel through the opening (i.e. the
-- direction the connecting ramp runs along) -- pillars flank PERPENDICULAR
-- to it, not along it. Getting this backwards silently plants a pillar on
-- the path's own centerline instead of beside it.
local function createArch(folder: Folder, name: string, centerGround: Vector3, axis: "X" | "Z", span: number, height: number)
	local half = span / 2
	local pillarThickness = 4
	local p1 = if axis == "Z" then Vector3.new(centerGround.X - half, 0, centerGround.Z) else Vector3.new(centerGround.X, 0, centerGround.Z - half)
	local p2 = if axis == "Z" then Vector3.new(centerGround.X + half, 0, centerGround.Z) else Vector3.new(centerGround.X, 0, centerGround.Z + half)
	createPillar(folder, name .. "PillarA", p1, height, pillarThickness)
	createPillar(folder, name .. "PillarB", p2, height, pillarThickness)
	local beamSizeX = if axis == "Z" then span + pillarThickness else pillarThickness
	local beamSizeZ = if axis == "Z" then pillarThickness else span + pillarThickness
	newPart(folder, name .. "Lintel", {
		Size = Vector3.new(beamSizeX, 2, beamSizeZ),
		CFrame = CFrame.new(centerGround.X, height + 1, centerGround.Z),
		Color = ACCENT,
		Material = Enum.Material.Neon,
		CanCollide = true,
	})
end

-- A small platform floating with nothing supporting it. `collidable` true
-- makes it a walkable stepping stone; false makes it purely a background
-- silhouette the player paths around/under rather than into.
local function createFloatingPlatform(
	folder: Folder,
	name: string,
	pos: Vector3,
	sizeX: number,
	thickness: number,
	sizeZ: number,
	collidable: boolean
)
	newPart(folder, name, {
		Size = Vector3.new(sizeX, thickness, sizeZ),
		CFrame = CFrame.new(pos),
		Color = if collidable then PANEL else DARK,
		CanCollide = collidable,
	})
	if collidable then
		newPart(folder, name .. "Trim", {
			Size = Vector3.new(sizeX + 0.6, 0.3, sizeZ + 0.6),
			CFrame = CFrame.new(pos.X, pos.Y - thickness / 2 - 0.15, pos.Z),
			Color = ACCENT,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
	end
end

--------------------------------------------------------------------------------
-- The map: a multi-level, 3D-chess-style maze spanning the whole play area
-- (issue #41, expanded to replace the original hand-built North/East/West
-- zones entirely rather than sitting alongside them as a fourth "South"
-- zone -- see the original PR discussion). One maze "wing" extends outward
-- from spawn in each of the four compass directions. Every wing shares this
-- same generation/geometry code, parameterized by which world axis is
-- "outward" for that wing -- so the maze logic is written and verified once
-- instead of once per direction.
--
-- Each level of each wing is an independently generated perfect maze
-- (recursive backtracker -- every cell reachable, no loops, exactly
-- width*height-1 passages), stacked directly above the one below and
-- connected by a staircase shaft in a different edge each transition, so
-- reaching the top requires actually crossing each level's maze rather than
-- climbing a single elevator column. Regenerated fresh every time Build()
-- runs (a freshly-seeded Random() each server start, no stored seed), so
-- the layout varies session to session -- the geometry itself is still
-- fully stateless. Each wing has its own difficulty (grid size + level
-- count) and color theme (see WING_CONFIGS: North=smallest/easiest/green
-- through West=largest/hardest/red) and a goal marker at the top level
-- rewarding completion with a permanent click-rate bonus -- but *that*
-- reward is real player session state, tracked and granted by
-- GameService.server.lua (which finds each wing's named goal part after
-- Build() returns), not by anything in this file -- this file stays pure
-- geometry, no gameplay state or RemoteEvents of its own.
--
-- Each level's floor is one continuous platform (not one per cell) --
-- connectivity between cells is expressed entirely by walls, not by gaps in
-- the floor. An earlier version of this maze left a gap wherever two cells
-- weren't connected and relied on the gap alone to block movement; a
-- Roblox character can trivially jump a few studs, so that let a player run
-- straight from one side of the maze to the other by jumping every gap in a
-- beeline, ignoring the generated path entirely. MAZE_WALL_HEIGHT below is
-- picked to comfortably exceed Roblox's default jump height, so every
-- non-open connection is now a genuine wall, not just an inconvenience.
--------------------------------------------------------------------------------

local MAZE_CELL_SIZE = 18 -- also each cell's run length before the next wall/junction
local MAZE_CELL_SPACING = MAZE_CELL_SIZE -- cells touch edge-to-edge -- floor is contiguous, walls (not gaps) carve the maze
local MAZE_WALL_THICKNESS = 2
-- A corridor's containment comes from the ceiling (see buildMazeLevel),
-- not from making the walls tall enough that they supposedly can't be
-- jumped or seen over -- that turned out not to hold up in practice (a
-- player could still get over/see over a 12-stud wall), and "tall enough"
-- isn't something a wall alone can ever fully guarantee against a
-- controllable 3rd-person camera anyway. The wall's height only needs to
-- reach the ceiling with no gap, so nothing can slip sideways between a
-- wall's top and the ceiling's underside.
local MAZE_WALL_HEIGHT = 16
local MAZE_THICKNESS = 2 -- floor/ceiling thickness
local MAZE_BASE_Y = 20 -- Level 1's walkable height
local MAZE_LEVEL_HEIGHT = 40 -- vertical gap between consecutive levels

-- Depths (distance from the origin, along a wing's own outward axis) for
-- its gate, the ground-level start of its entry ramp, and Level 1's near
-- row -- in that order, each a bit further out than the last, sized so the
-- entry ramp's slope (rise MAZE_BASE_Y over run ENTRY_DEPTH - CELL_SIZE/2 -
-- RAMP_START_DEPTH) comes out close to 14 degrees, matching the gentle
-- slope every ramp elsewhere in this file already uses.
local MAZE_GATE_DEPTH = 50
local MAZE_GATE_SPAN = 28 -- passed to createArch below; also what the clearance check derives from
local MAZE_RAMP_START_DEPTH = 75
local MAZE_ENTRY_DEPTH = 160

-- Per-wing difficulty/theme: grid size and level count both scale up
-- (North=easiest/smallest through West=hardest/largest), and each wing
-- gets its own color pair (structural parts vs. Neon trim/accent), applied
-- by paintWing after that wing's geometry is built -- see buildMazeWing.
-- Keyed by the same wing-name prefixes Build() already passes to
-- buildMazeWing ("MazeN"/"MazeS"/"MazeE"/"MazeW"), mirroring how
-- MAZE_DIRECTION_INFO below is the single source of truth for per-direction
-- axis/sign instead of each wing re-deriving its own.
type WingConfig = {
	gridWidth: number, -- cells across, lateral (perpendicular to the wing's outward direction)
	gridDepth: number, -- cells deep, outward from spawn
	levelCount: number,
	structuralColor: Color3,
	trimColor: Color3,
}
local WING_CONFIGS: { [string]: WingConfig } = {
	MazeN = { gridWidth = 5, gridDepth = 8, levelCount = 1, structuralColor = Color3.fromHex("2ecc71"), trimColor = Color3.fromHex("6fe8a0") },
	MazeS = { gridWidth = 7, gridDepth = 16, levelCount = 2, structuralColor = Color3.fromHex("f1c40f"), trimColor = Color3.fromHex("f7dc6f") },
	MazeE = { gridWidth = 9, gridDepth = 20, levelCount = 3, structuralColor = Color3.fromHex("e67e22"), trimColor = Color3.fromHex("f0a860") },
	MazeW = { gridWidth = 11, gridDepth = 26, levelCount = 5, structuralColor = Color3.fromHex("e74c3c"), trimColor = Color3.fromHex("f17d72") },
}

-- GATE_DEPTH is chosen so a gate's pillars (span MAZE_GATE_SPAN, so offset
-- sqrt((MAZE_GATE_SPAN/2)^2 + GATE_DEPTH^2) from the origin) clear both
-- SPAWN_CLEAR_RADIUS and the spawn ring's own radius (SPAWN_CLEAR_RADIUS +
-- SPAWN_RING_PADDING) with real margin -- the previous South zone's gate
-- didn't (see issue #51). Checked in assertMazeConstants below (called
-- from inside Build()'s pcall, not at module load) so a future edit to any
-- of these constants that breaks this fails loudly but gracefully --
-- caught and warn()'d like every other Build() failure, not an uncaught
-- error that would blow up the require() call in GameService.server.lua
-- and take down every RemoteEvent handler in the game, not just the map.
local function assertMazeConstants()
	assert(
		math.sqrt((MAZE_GATE_SPAN / 2) ^ 2 + MAZE_GATE_DEPTH ^ 2) > SPAWN_CLEAR_RADIUS + SPAWN_RING_PADDING + 2,
		"MAZE_GATE_DEPTH too small: gate pillars would sit inside the spawn ring's clearance"
	)
	-- A level's ceiling spans [topY + WALL_HEIGHT, topY + WALL_HEIGHT +
	-- THICKNESS] (buildMazeFloor's topY parameter is a surface, the part
	-- extends *down* from it by THICKNESS); the next level's floor spans
	-- [topY + LEVEL_HEIGHT - THICKNESS, topY + LEVEL_HEIGHT] for the same
	-- reason. Avoiding interpenetration needs the ceiling's top at or below
	-- the next floor's bottom, i.e. LEVEL_HEIGHT >= WALL_HEIGHT +
	-- 2*THICKNESS (one THICKNESS for the ceiling's own depth, one for the
	-- floor's) -- true today only because 40 > 16 + 2*2 happens to hold; a
	-- future taller-wall or tighter-stacking edit could silently make two
	-- levels' floor/ceiling plates interpenetrate with no error, just
	-- players clipping/stuck in Studio.
	assert(
		MAZE_LEVEL_HEIGHT > MAZE_WALL_HEIGHT + 2 * MAZE_THICKNESS,
		"MAZE_LEVEL_HEIGHT too small: a level's ceiling would collide with the next level's floor"
	)
	-- Each wing's own lateral half-extent must stay well under
	-- MAZE_ENTRY_DEPTH -- that gap near the origin is what keeps different
	-- wings' perpendicular corridors from ever geometrically overlapping
	-- (a wing's parts only start existing beyond depth MAZE_ENTRY_DEPTH
	-- along its own outward axis, so as long as no wing's sideways spread
	-- reaches that far, two wings can never intersect). True today only
	-- because every WING_CONFIGS entry happens to satisfy it -- a future
	-- wider config could silently make two wings interpenetrate with no
	-- error otherwise.
	for wingName, config in pairs(WING_CONFIGS) do
		local halfExtent = config.gridWidth * MAZE_CELL_SPACING / 2
		assert(
			halfExtent < MAZE_ENTRY_DEPTH - 10,
			string.format("%s: gridWidth %d too large, wing's lateral half-extent would approach MAZE_ENTRY_DEPTH", wingName, config.gridWidth)
		)
	end
end

-- Untyped-value cells ({[string]: boolean}, not a fixed record) so the
-- carve loop below can index by a direction name held in a variable
-- ("north"/"south"/"east"/"west") -- Luau's strict mode only allows dynamic
-- string-keyed indexing against an index-signature type like this, not a
-- record type with fixed field names.
type MazeCell = { [string]: boolean }
type MazeGrid = { [number]: { [number]: MazeCell } }
type MazeDirection = "+X" | "-X" | "+Z" | "-Z"

-- Which world axis is "depth" for each compass direction, and which sign
-- along that axis is "outward" -- the single source of truth every other
-- maze function below reads from, instead of each re-deriving its own
-- "is this direction X or Z" / "is it + or -" ternary (three independent,
-- easy-to-desync copies of the same fact, before this table existed).
local MAZE_DIRECTION_INFO: { [MazeDirection]: { axis: "X" | "Z", sign: number } } = {
	["+Z"] = { axis = "Z", sign = 1 },
	["-Z"] = { axis = "Z", sign = -1 },
	["+X"] = { axis = "X", sign = 1 },
	["-X"] = { axis = "X", sign = -1 },
}

-- Maps a wing-local (lateral, depth) offset -- lateral perpendicular to the
-- wing's outward direction, depth increasing away from spawn -- into world
-- X/Z. This one function is what lets every other maze function below be
-- written once and reused for all four compass wings instead of a
-- copy-pasted block per direction.
local function mazeLocalToWorld(direction: MazeDirection, lateral: number, depth: number): (number, number)
	local info = MAZE_DIRECTION_INFO[direction]
	local signedDepth = info.sign * depth
	if info.axis == "Z" then
		return lateral, signedDepth
	else
		return signedDepth, lateral
	end
end

-- The lateral offset of grid column `col`, centered on the grid's own
-- width -- factored out of mazeCellCenter so buildMazeWing's entry-ramp
-- landing and buildMazeWall (which each need this same lateral value at a
-- different depth than any actual cell's center) don't have to duplicate
-- the formula.
local function mazeLateralOffset(col: number, gridWidth: number): number
	return (col - (gridWidth + 1) / 2) * MAZE_CELL_SPACING
end

-- The depth offset of grid row `row`, 0 at row 1 (nearest spawn) and
-- increasing outward -- mirrors mazeLateralOffset for the same reason
-- (shared by mazeCellCenter and buildMazeWall).
local function mazeDepthOffset(row: number): number
	return (row - 1) * MAZE_CELL_SPACING
end

-- The center of grid cell (col, row) in a wing extending in `direction`
-- from the origin -- col is 1..gridWidth (lateral), row is 1..gridDepth
-- (1 = nearest spawn). Shared by every maze-geometry function below so
-- they all agree on exactly the same cell positions.
local function mazeCellCenter(direction: MazeDirection, col: number, row: number, gridWidth: number): (number, number)
	return mazeLocalToWorld(direction, mazeLateralOffset(col, gridWidth), MAZE_ENTRY_DEPTH + mazeDepthOffset(row))
end

-- Randomized recursive backtracker (iterative, explicit stack -- doesn't
-- rely on Luau's native call-stack depth for a larger grid): carves a
-- perfect maze into a width x height grid. Cells are 1-indexed, {col, row},
-- matching Lua array convention. Independent of any particular wing's
-- world-space orientation -- purely a grid algorithm.
local function generateMaze(width: number, height: number, rng: Random): MazeGrid
	local grid: MazeGrid = {}
	local visited: { [number]: { [number]: boolean } } = {}
	for x = 1, width do
		grid[x] = {}
		visited[x] = {}
		for z = 1, height do
			grid[x][z] = { north = false, south = false, east = false, west = false }
			visited[x][z] = false
		end
	end

	local directions = {
		{ dx = 0, dz = -1, from = "north", to = "south" },
		{ dx = 0, dz = 1, from = "south", to = "north" },
		{ dx = 1, dz = 0, from = "east", to = "west" },
		{ dx = -1, dz = 0, from = "west", to = "east" },
	}

	local startX, startZ = rng:NextInteger(1, width), rng:NextInteger(1, height)
	visited[startX][startZ] = true
	local stack = { { x = startX, z = startZ } }

	while #stack > 0 do
		local current = stack[#stack]

		-- Visit directions in a random order each time so the maze doesn't
		-- develop a directional bias (Fisher-Yates shuffle of the 4 indices).
		local order = { 1, 2, 3, 4 }
		for i = 4, 2, -1 do
			local j = rng:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end

		local carved = false
		for _, idx in ipairs(order) do
			local dir = directions[idx]
			local nx, nz = current.x + dir.dx, current.z + dir.dz
			if nx >= 1 and nx <= width and nz >= 1 and nz <= height and not visited[nx][nz] then
				grid[current.x][current.z][dir.from] = true
				grid[nx][nz][dir.to] = true
				visited[nx][nz] = true
				table.insert(stack, { x = nx, z = nz })
				carved = true
				break
			end
		end

		if not carved then
			table.remove(stack)
		end
	end

	return grid
end

-- A platform connecting two axis-aligned points, oriented automatically by
-- whichever world axis they actually differ along. Currently only used by
-- buildMazeShaft, to bridge a staircase's landing (past the floor's outer
-- edge) back to the floor itself.
local function buildMazeBridge(folder: Folder, name: string, topY: number, x1: number, z1: number, x2: number, z2: number, width: number)
	local dx, dz = x2 - x1, z2 - z1
	assert(dx == 0 or dz == 0, "buildMazeBridge: endpoints aren't axis-aligned")
	local midX, midZ = (x1 + x2) / 2, (z1 + z2) / 2
	-- +4 so the bridge overlaps each endpoint by a couple of studs instead
	-- of meeting it exactly -- guards against a razor-thin gap from a
	-- caller's endpoint being a hair short of the actual target surface.
	local length = math.abs(dx) + math.abs(dz) + 4
	if math.abs(dx) > math.abs(dz) then
		createPlatform(folder, name, midX, topY, midZ, length, MAZE_THICKNESS, width)
	else
		createPlatform(folder, name, midX, topY, midZ, width, MAZE_THICKNESS, length)
	end
end

-- One continuous platform spanning a whole level's grid -- cell connectivity
-- is expressed entirely by walls (see buildMazeWall/buildMazeLevel below),
-- not by gaps in the floor, so the floor itself never needs to be
-- segmented per cell.
local function buildMazeFloor(folder: Folder, name: string, direction: MazeDirection, topY: number, gridWidth: number, gridDepth: number)
	-- Span from the first cell's near edge to the last cell's far edge:
	-- (N-1) center-to-center spacings between them, plus one more half-cell
	-- on each end. Written in terms of MAZE_CELL_SPACING (matching
	-- mazeLateralOffset/mazeDepthOffset, which every wall and cell position
	-- is already computed from) rather than N * MAZE_CELL_SIZE, which only
	-- happens to give the same answer today because MAZE_CELL_SPACING is
	-- currently defined equal to MAZE_CELL_SIZE -- if a gap were ever
	-- reintroduced between cells (redefining SPACING > SIZE, which is
	-- exactly what SPACING existed for before this file's walls replaced
	-- floor gaps), N * MAZE_CELL_SIZE would undershoot the real extent and
	-- leave the outermost walls floating past the floor's actual edge.
	local lateralExtent = (gridWidth - 1) * MAZE_CELL_SPACING + MAZE_CELL_SIZE
	local depthExtent = (gridDepth - 1) * MAZE_CELL_SPACING + MAZE_CELL_SIZE
	local depthCenter = MAZE_ENTRY_DEPTH + (gridDepth - 1) * MAZE_CELL_SPACING / 2
	local cx, cz = mazeLocalToWorld(direction, 0, depthCenter)
	if MAZE_DIRECTION_INFO[direction].axis == "Z" then
		createPlatform(folder, name, cx, topY, cz, lateralExtent, MAZE_THICKNESS, depthExtent)
	else
		createPlatform(folder, name, cx, topY, cz, depthExtent, MAZE_THICKNESS, lateralExtent)
	end
end

-- A wall segment blocking movement across one edge of grid cell (col, row):
-- `edgeKind` "lateral" for its east (edgeSign 1) or west (edgeSign -1) edge,
-- "depth" for its south (1) or north (-1) edge. MAZE_WALL_HEIGHT
-- comfortably exceeds Roblox's default jump height, so -- unlike the gap
-- the very first version of this maze relied on -- a wall can't just be
-- jumped over; every non-open connection is genuinely impassable.
local function buildMazeWall(folder: Folder, name: string, direction: MazeDirection, topY: number, col: number, row: number, edgeKind: "lateral" | "depth", edgeSign: number, gridWidth: number)
	local lateral = mazeLateralOffset(col, gridWidth)
	local depth = MAZE_ENTRY_DEPTH + mazeDepthOffset(row)
	if edgeKind == "lateral" then
		lateral += edgeSign * MAZE_CELL_SIZE / 2
	else
		depth += edgeSign * MAZE_CELL_SIZE / 2
	end
	local wx, wz = mazeLocalToWorld(direction, lateral, depth)

	-- The wall's long dimension runs along whichever local axis it *isn't*
	-- blocking (a lateral-facing wall spans the cell's full depth-wise
	-- footprint; a depth-facing wall spans its full lateral-wise footprint),
	-- translated to world X/Z the same way every other maze part is.
	local sizeAlongDepth = if edgeKind == "lateral" then MAZE_CELL_SIZE else MAZE_WALL_THICKNESS
	local sizeAlongLateral = if edgeKind == "lateral" then MAZE_WALL_THICKNESS else MAZE_CELL_SIZE
	local axis = MAZE_DIRECTION_INFO[direction].axis
	local sizeX = if axis == "X" then sizeAlongDepth else sizeAlongLateral
	local sizeZ = if axis == "Z" then sizeAlongDepth else sizeAlongLateral

	newPart(folder, name, {
		Size = Vector3.new(sizeX, MAZE_WALL_HEIGHT, sizeZ),
		CFrame = CFrame.new(wx, topY + MAZE_WALL_HEIGHT / 2, wz),
		Color = DARK,
	})
end

type MazeOpenEdge = { col: number, edge: "north" | "south" }

-- Builds one level's floor plus a wall on every grid edge that isn't a
-- carved passage: an internal edge between two cells gets a wall exactly
-- when the maze didn't connect them; every edge on the grid's own boundary
-- (its four sides) gets a wall too, except the specific (col, "north"/
-- "south") points listed in `openEdges`. Three distinct things put a point
-- in that list (see buildMazeWing): the entry ramp's landing cell (a
-- "north" opening, Level 1 only), a shaft's landing bridging back INTO a
-- level from below (a "south" opening), and a shaft departing UPWARD from
-- a level (also a "south" opening, at that shaft's own starting cell --
-- easy to forget since there's no "landing" involved, just the top of the
-- staircase this level's own buildMazeShaft call builds). The grid's
-- east/west boundaries are always fully walled -- nothing in this
-- design ever enters or exits a level from the side.
local function buildMazeLevel(folder: Folder, namePrefix: string, grid: MazeGrid, direction: MazeDirection, topY: number, openEdges: { MazeOpenEdge }, gridWidth: number, gridDepth: number)
	local function isOpen(col: number, edge: "north" | "south"): boolean
		for _, opening in ipairs(openEdges) do
			if opening.col == col and opening.edge == edge then
				return true
			end
		end
		return false
	end

	buildMazeFloor(folder, namePrefix .. "Floor", direction, topY, gridWidth, gridDepth)
	-- A solid ceiling with its underside flush against every wall's top
	-- (no gap for anything to slip sideways through) is what actually
	-- contains a player, not wall height alone -- see MAZE_WALL_HEIGHT's
	-- comment. Reuses buildMazeFloor's own footprint math unchanged, just
	-- at a higher topY, since a ceiling is geometrically identical to the
	-- floor -- one continuous plate spanning the whole grid.
	buildMazeFloor(folder, namePrefix .. "Ceiling", direction, topY + MAZE_WALL_HEIGHT + MAZE_THICKNESS, gridWidth, gridDepth)

	for col = 1, gridWidth do
		for row = 1, gridDepth do
			local cell = grid[col][row]

			-- col == gridWidth (the boundary) always walls, regardless of
			-- cell.east -- there's no east neighbor to have carved a
			-- passage into.
			if col == gridWidth or not cell.east then
				buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "E", direction, topY, col, row, "lateral", 1, gridWidth)
			end

			if col == 1 then
				buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "W", direction, topY, col, row, "lateral", -1, gridWidth)
			end

			if row < gridDepth then
				if not cell.south then
					buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "S", direction, topY, col, row, "depth", 1, gridWidth)
				end
			elseif not isOpen(col, "south") then
				buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "S", direction, topY, col, row, "depth", 1, gridWidth)
			end

			if row == 1 and not isOpen(col, "north") then
				buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "N", direction, topY, col, row, "depth", -1, gridWidth)
			end
		end
	end
end

-- Connects grid column `col`'s farthest-row cell between two vertically
-- stacked levels of the same wing with a staircase running further outward
-- (never back through the grid -- true by construction as long as `col` is
-- actually a valid column, asserted below, since a wing's shafts only ever
-- start at its own farthest row and climb further along the same outward
-- direction the whole wing already extends in).
-- Lands on a small platform that's then bridged back to the same cell one
-- level up, so a small mismatch between the staircase's exact landing spot
-- and the cell's own footprint can never leave a gap.
local function buildMazeShaft(folder: Folder, namePrefix: string, direction: MazeDirection, col: number, lowerY: number, upperY: number, gridWidth: number, gridDepth: number)
	assert(
		col >= 1 and col <= gridWidth,
		string.format("buildMazeShaft: col %d is out of range [1, %d]", col, gridWidth)
	)

	local cx, cz = mazeCellCenter(direction, col, gridDepth, gridWidth)
	local info = MAZE_DIRECTION_INFO[direction]
	-- Explicit "X"|"Z" annotation: axis's literal type otherwise gets widened
	-- to a plain string by the time it reaches createStaircase's typed
	-- parameter below (a Luau inference gap through the axis=="X"/=="Z"
	-- comparisons a few lines down), tripping a strict-mode type error even
	-- though the value itself is always exactly "X" or "Z" at runtime.
	local axis: "X" | "Z" = info.axis
	local sign = info.sign

	-- createStaircase's origin must be the near edge of the first step, not
	-- the cell's center (see its own doc comment) -- every ramp/staircase in
	-- this file lands at a target's edge, not its center, otherwise the
	-- first couple of steps land inside the shaft cell's own footprint
	-- instead of starting cleanly at its outward edge.
	local edgeX = if axis == "X" then cx + sign * (MAZE_CELL_SIZE / 2) else cx
	local edgeZ = if axis == "Z" then cz + sign * (MAZE_CELL_SIZE / 2) else cz

	-- 30-step climb sized to exactly cover the level-to-level height
	-- difference. Each individual step only rises ~1.3 studs, comfortably
	-- within Roblox's default auto-step-up range.
	local steps = 30
	local stepRun = 3
	local stepRise = (upperY - lowerY) / steps

	local landing = createStaircase(folder, namePrefix .. "Stair", Vector3.new(edgeX, lowerY, edgeZ), axis, sign, steps, stepRun, stepRise, MAZE_CELL_SIZE)
	createPlatform(folder, namePrefix .. "Landing", landing.X, landing.Y, landing.Z, MAZE_CELL_SIZE, MAZE_THICKNESS, MAZE_CELL_SIZE)

	-- Bridges all the way back to the cell's own center, not just to the
	-- floor's nearer edge -- deliberately overlapping the floor itself by a
	-- few studs (harmless: two coplanar walkable surfaces) so a small
	-- mismatch between the staircase's exact landing spot and the cell's
	-- own footprint can never leave a gap. The upper level's own wall-carve
	-- must leave this same cell/edge open (see buildMazeWing's openEdges)
	-- or this bridge would just dead-end into a wall.
	buildMazeBridge(folder, namePrefix .. "LandingBridge", upperY, cx, cz, landing.X, landing.Z, MAZE_CELL_SIZE)
end

-- Recolors every part built for one wing to its WingConfig theme, once
-- that wing's geometry is fully built: Neon (trim/accent) parts get the
-- theme's trimColor, everything else gets structuralColor. Cheaper and
-- less invasive than threading a color override through every low-level
-- geometry helper (createRamp/createPlatform/createStaircase/buildMazeWall
-- etc.), several of which are also shared by the spawn-ring/skyline
-- decoration in Build() below, which should keep the default DARK/PANEL/
-- ACCENT palette rather than picking up any one wing's theme.
local function paintWing(wingFolder: Folder, theme: WingConfig)
	for _, descendant in ipairs(wingFolder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant.Material == Enum.Material.Neon then
				descendant.Color = theme.trimColor
			else
				descendant.Color = theme.structuralColor
			end
		end
	end
end

-- Builds one complete wing: entry gate + ramp near spawn, config.levelCount
-- independently generated maze levels (each fully walled in except its
-- designated opening(s) -- see openEdges below), a shaft connecting each
-- consecutive pair of levels, and a goal marker on the top level. The
-- shafts alternate between the grid's two lateral edges (col 1, then col
-- config.gridWidth, and so on) so climbing from the bottom to the top
-- forces crossing each intermediate level from one side to the other,
-- rather than landing right next to the next shaft up. All of this wing's
-- parts are parented under their own sub-Folder (not directly under the
-- shared Map folder `mapFolder`) so paintWing's repaint pass at the end
-- only ever touches this wing's own geometry.
local function buildMazeWing(mapFolder: Folder, wingName: string, direction: MazeDirection, rng: Random)
	local config = WING_CONFIGS[wingName]
	local folder = Instance.new("Folder")
	folder.Name = wingName
	folder.Parent = mapFolder

	local gateX, gateZ = mazeLocalToWorld(direction, 0, MAZE_GATE_DEPTH)
	createArch(folder, wingName .. "Gate", Vector3.new(gateX, 0, gateZ), MAZE_DIRECTION_INFO[direction].axis, MAZE_GATE_SPAN, 20)

	local rampOriginX, rampOriginZ = mazeLocalToWorld(direction, 0, MAZE_RAMP_START_DEPTH)
	local entryCol = math.ceil((config.gridWidth + 1) / 2)
	-- Land at the entry cell's near edge, not its center -- landing at the
	-- center would bury half the ramp slab inside the flat cell platform
	-- instead of meeting it cleanly at the boundary (see issue #40/#50's
	-- south-zone review for the same class of mistake).
	local entryEdgeX, entryEdgeZ = mazeLocalToWorld(direction, mazeLateralOffset(entryCol, config.gridWidth), MAZE_ENTRY_DEPTH - MAZE_CELL_SIZE / 2)
	-- Narrower than a full cell width so it can't overhang into the
	-- entry column's neighboring cells on either side.
	createRamp(folder, wingName .. "Ramp", Vector3.new(rampOriginX, 0, rampOriginZ), Vector3.new(entryEdgeX, MAZE_BASE_Y, entryEdgeZ), MAZE_CELL_SIZE - 4, 3)

	-- shaftCols[i] is the column shaft i (connecting level i to level i+1)
	-- uses -- needed by both loops below, so computed once up front: each
	-- level's wall-carve has to leave the same column open that the actual
	-- shaft touching it (above and/or below) uses.
	local shaftCols = {}
	for i = 1, config.levelCount - 1 do
		shaftCols[i] = if i % 2 == 1 then 1 else config.gridWidth
	end

	for i = 1, config.levelCount do
		local openEdges: { MazeOpenEdge } = {}
		if i == 1 then
			table.insert(openEdges, { col = entryCol, edge = "north" })
		else
			-- Where shaft i-1's landing bridges back in from below.
			table.insert(openEdges, { col = shaftCols[i - 1], edge = "south" })
		end
		if shaftCols[i] then
			-- Where shaft i departs upward from this level.
			table.insert(openEdges, { col = shaftCols[i], edge = "south" })
		end

		local topY = MAZE_BASE_Y + (i - 1) * MAZE_LEVEL_HEIGHT
		local grid = generateMaze(config.gridWidth, config.gridDepth, rng)
		buildMazeLevel(folder, wingName .. "L" .. i, grid, direction, topY, openEdges, config.gridWidth, config.gridDepth)
	end

	for i = 1, config.levelCount - 1 do
		local lowerY = MAZE_BASE_Y + (i - 1) * MAZE_LEVEL_HEIGHT
		local upperY = MAZE_BASE_Y + i * MAZE_LEVEL_HEIGHT
		buildMazeShaft(folder, wingName .. "Shaft" .. i, direction, shaftCols[i], lowerY, upperY, config.gridWidth, config.gridDepth)
	end

	-- Goal marker: a bright, elevated, non-collidable pad at the top
	-- level's deepest row, at the same lateral column the entry ramp uses
	-- -- any cell works, since a perfect maze guarantees exactly one
	-- reachable path to every cell regardless of which one is chosen, so
	-- this is purely about giving the wing a recognizable endpoint. Named
	-- wingName .. "Goal" so GameService.server.lua can find it by name
	-- after Build() returns and wire the completion reward to it -- this
	-- file stays pure geometry, no gameplay state/RemoteEvents here (see
	-- the top-of-file comment). CanTouch left at its default (true) on the
	-- pad itself so a player's Humanoid overlapping it fires Touched; the
	-- beacon is a pure visual accent and explicitly can't.
	local topY = MAZE_BASE_Y + (config.levelCount - 1) * MAZE_LEVEL_HEIGHT
	local goalX, goalZ = mazeCellCenter(direction, entryCol, config.gridDepth, config.gridWidth)
	newPart(folder, wingName .. "Goal", {
		Size = Vector3.new(MAZE_CELL_SIZE - 4, 0.6, MAZE_CELL_SIZE - 4),
		CFrame = CFrame.new(goalX, topY + 0.3, goalZ),
		Color = ACCENT,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	newPart(folder, wingName .. "GoalBeacon", {
		Size = Vector3.new(2, MAZE_WALL_HEIGHT - 1, 2),
		CFrame = CFrame.new(goalX, topY + (MAZE_WALL_HEIGHT - 1) / 2, goalZ),
		Color = ACCENT,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = false,
	})

	paintWing(folder, config)
end

function MapBuilder.Build(): (boolean, string?)
	local ok, err = pcall(function()
		assertMazeConstants()

		local folder = Instance.new("Folder")
		folder.Name = "Map"
		folder.Parent = workspace

		-- === Four maze wings, one per compass direction, sharing one Random
		-- so no two wings (or two levels within a wing) can ever coincidentally
		-- generate identically. ===
		local mazeRng = Random.new()
		buildMazeWing(folder, "MazeN", "-Z", mazeRng)
		buildMazeWing(folder, "MazeE", "+X", mazeRng)
		buildMazeWing(folder, "MazeS", "+Z", mazeRng)
		buildMazeWing(folder, "MazeW", "-X", mazeRng)

		-- === Central decoration: a ring of pillars around spawn, just
		-- outside SPAWN_CLEAR_RADIUS, so the hub reads as a landmark without
		-- ever overlapping a spawning player. Offset 15 degrees off the
		-- cardinal angles (0/90/180/270, i.e. the four wings' own gate
		-- corridors, all at lateral=0) -- 6 pillars every 60 degrees would
		-- otherwise put one directly on the East and West gates' approach
		-- centerline (a real bug found by review: a player walking straight
		-- toward either gate would run straight into a pillar first). North/
		-- South weren't affected (90/270 aren't multiples of 60), but the
		-- offset is applied uniformly since it costs nothing and removes the
		-- whole class of "does some multiple of 60 degrees hit a multiple of
		-- 90" coincidence instead of relying on it not mattering by luck. ===
		local ringRadius = SPAWN_CLEAR_RADIUS + SPAWN_RING_PADDING
		local pillarCount = 6
		local ringAngleOffset = math.rad(15)
		for i = 0, pillarCount - 1 do
			local angle = (i / pillarCount) * math.pi * 2 + ringAngleOffset
			local x = math.cos(angle) * ringRadius
			local z = math.sin(angle) * ringRadius
			createPillar(folder, "SpawnRingPillar" .. i, Vector3.new(x, 0, z), 14, 4)
		end

		-- === Background decoration: purely visual floating platforms, high
		-- up and non-collidable, positioned just past the tip of each wing
		-- and off to the side (outside its +-63-stud lateral footprint) so
		-- they read as distant skyline silhouettes beyond where the maze
		-- actually ends, rather than sitting awkwardly close to the middle
		-- of it. Not reachable and don't block movement. ===
		createFloatingPlatform(folder, "SkylineA", Vector3.new(-150, 90, -600), 30, 2.5, 20, false)
		createFloatingPlatform(folder, "SkylineB", Vector3.new(600, 120, -150), 22, 2.5, 22, false)
		createFloatingPlatform(folder, "SkylineC", Vector3.new(-600, 100, 150), 26, 2.5, 18, false)
		createFloatingPlatform(folder, "SkylineD", Vector3.new(150, 140, 600), 20, 2.5, 26, false)
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

return MapBuilder
