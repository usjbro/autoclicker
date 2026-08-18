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
-- runs (a freshly-seeded Random() each server start, no stored seed -- no
-- new persistent gameplay state), so the layout varies session to session.
--------------------------------------------------------------------------------

local MAZE_GRID_WIDTH = 5 -- cells across, lateral (perpendicular to a wing's outward direction)
local MAZE_GRID_DEPTH = 8 -- cells deep, outward from spawn
local MAZE_CELL_SIZE = 14
local MAZE_CELL_GAP = 6
local MAZE_CELL_SPACING = MAZE_CELL_SIZE + MAZE_CELL_GAP
local MAZE_BRIDGE_WIDTH = 6
local MAZE_THICKNESS = 2
local MAZE_LEVEL_COUNT = 3
local MAZE_BASE_Y = 20 -- Level 1's walkable height
local MAZE_LEVEL_HEIGHT = 40 -- vertical gap between consecutive levels

-- Depths (distance from the origin, along a wing's own outward axis) for
-- its gate, the ground-level start of its entry ramp, and Level 1's near
-- row -- in that order, each a bit further out than the last, sized so the
-- entry ramp's slope (rise MAZE_BASE_Y over run ENTRY_DEPTH - CELL_SIZE/2 -
-- RAMP_START_DEPTH) comes out close to 14 degrees, matching the gentle
-- slope every ramp elsewhere in this file already uses -- an earlier
-- version of these constants only fixed GATE_DEPTH's own clearance (see
-- below) without re-deriving the ramp run that depends on it, which
-- doubled the ramp's steepness to ~28 degrees as a side effect.
local MAZE_GATE_DEPTH = 50
local MAZE_RAMP_START_DEPTH = 55
local MAZE_ENTRY_DEPTH = 140

-- GATE_DEPTH is chosen so a gate's pillars (span 28, so offset
-- sqrt(14^2 + GATE_DEPTH^2) from the origin) clear both SPAWN_CLEAR_RADIUS
-- and the spawn ring's own radius (SPAWN_CLEAR_RADIUS + 4) with real
-- margin -- the previous South zone's gate didn't (see issue #51). Checked
-- here, at module load, rather than trusted to a comment -- a future edit
-- to either constant that breaks this now fails loudly at server start
-- instead of silently reintroducing #51.
assert(
	math.sqrt(14 ^ 2 + MAZE_GATE_DEPTH ^ 2) > SPAWN_CLEAR_RADIUS + 4 + 2,
	"MAZE_GATE_DEPTH too small: gate pillars would sit inside the spawn ring's clearance"
)

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
-- landing (which needs this same lateral value at a different depth than
-- any actual cell's center) doesn't have to duplicate the formula.
local function mazeLateralOffset(col: number): number
	return (col - (MAZE_GRID_WIDTH + 1) / 2) * MAZE_CELL_SPACING
end

-- The center of grid cell (col, row) in a wing extending in `direction`
-- from the origin -- col is 1..MAZE_GRID_WIDTH (lateral), row is
-- 1..MAZE_GRID_DEPTH (1 = nearest spawn). Shared by every maze-geometry
-- function below so they all agree on exactly the same cell positions.
local function mazeCellCenter(direction: MazeDirection, col: number, row: number): (number, number)
	local depth = MAZE_ENTRY_DEPTH + (row - 1) * MAZE_CELL_SPACING
	return mazeLocalToWorld(direction, mazeLateralOffset(col), depth)
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

-- A platform connecting two adjacent cell centers, oriented automatically
-- by whichever world axis they actually differ along -- a "col+1" (lateral)
-- neighbor and a "row+1" (depth) neighbor differ along different world axes
-- depending on the wing's direction, so this can't be hardcoded to "X gap,
-- Z width" the way a single fixed-orientation zone could.
local function buildMazeBridge(folder: Folder, name: string, topY: number, x1: number, z1: number, x2: number, z2: number)
	local dx, dz = x2 - x1, z2 - z1
	-- Every current caller passes strictly axis-aligned neighbor pairs (a
	-- col+1 or a row+1 step, never both), so exactly one of dx/dz is ever
	-- nonzero -- assert that instead of silently picking a plausible-looking
	-- orientation for a future diagonal/non-adjacent bridge that doesn't
	-- actually satisfy it.
	assert(dx == 0 or dz == 0, "buildMazeBridge: endpoints aren't axis-aligned")
	local midX, midZ = (x1 + x2) / 2, (z1 + z2) / 2
	if math.abs(dx) > math.abs(dz) then
		createPlatform(folder, name, midX, topY, midZ, MAZE_CELL_GAP + 4, MAZE_THICKNESS, MAZE_BRIDGE_WIDTH)
	else
		createPlatform(folder, name, midX, topY, midZ, MAZE_BRIDGE_WIDTH, MAZE_THICKNESS, MAZE_CELL_GAP + 4)
	end
end

-- Turns a generated maze grid into a platform per cell plus a bridge
-- wherever the grid carved a passage. Only ever bridges toward east/south
-- from each cell -- the matching west/north flag on the neighbor is set by
-- the same carve, so checking one direction per pair is enough and avoids
-- building the same bridge twice.
local function buildMazeLevel(folder: Folder, namePrefix: string, grid: MazeGrid, direction: MazeDirection, topY: number)
	for col = 1, MAZE_GRID_WIDTH do
		for row = 1, MAZE_GRID_DEPTH do
			local cx, cz = mazeCellCenter(direction, col, row)
			createPlatform(folder, namePrefix .. "Cell" .. col .. "_" .. row, cx, topY, cz, MAZE_CELL_SIZE, MAZE_THICKNESS, MAZE_CELL_SIZE)

			local cell = grid[col][row]
			if cell.east and col < MAZE_GRID_WIDTH then
				local nx, nz = mazeCellCenter(direction, col + 1, row)
				buildMazeBridge(folder, namePrefix .. "Bridge" .. col .. "_" .. row .. "E", topY, cx, cz, nx, nz)
			end
			if cell.south and row < MAZE_GRID_DEPTH then
				local nx, nz = mazeCellCenter(direction, col, row + 1)
				buildMazeBridge(folder, namePrefix .. "Bridge" .. col .. "_" .. row .. "S", topY, cx, cz, nx, nz)
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
local function buildMazeShaft(folder: Folder, namePrefix: string, direction: MazeDirection, col: number, lowerY: number, upperY: number)
	assert(
		col >= 1 and col <= MAZE_GRID_WIDTH,
		string.format("buildMazeShaft: col %d is out of range [1, %d]", col, MAZE_GRID_WIDTH)
	)

	local cx, cz = mazeCellCenter(direction, col, MAZE_GRID_DEPTH)
	local info = MAZE_DIRECTION_INFO[direction]
	local axis, sign = info.axis, info.sign

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

	-- The actual cell-center-to-landing distance the bridge below has to
	-- span, not just the staircase's own run -- it also has to cover the
	-- half-cell gap between the cell's center and edgeX/edgeZ where the
	-- staircase itself started.
	local runLength = steps * stepRun + MAZE_CELL_SIZE / 2
	if axis == "X" then
		createPlatform(folder, namePrefix .. "LandingBridge", (cx + landing.X) / 2, upperY, cz, runLength + 4, MAZE_THICKNESS, MAZE_BRIDGE_WIDTH)
	else
		createPlatform(folder, namePrefix .. "LandingBridge", cx, upperY, (cz + landing.Z) / 2, MAZE_BRIDGE_WIDTH, MAZE_THICKNESS, runLength + 4)
	end
end

-- Builds one complete wing: entry gate + ramp near spawn, MAZE_LEVEL_COUNT
-- independently generated maze levels, and a shaft connecting each
-- consecutive pair of levels. The two shafts alternate between the grid's
-- two lateral edges (col 1, then col MAZE_GRID_WIDTH) so climbing from the
-- bottom to the top forces crossing each intermediate level from one side
-- to the other, rather than landing right next to the next shaft up.
local function buildMazeWing(folder: Folder, wingName: string, direction: MazeDirection, rng: Random)
	local gateX, gateZ = mazeLocalToWorld(direction, 0, MAZE_GATE_DEPTH)
	createArch(folder, wingName .. "Gate", Vector3.new(gateX, 0, gateZ), MAZE_DIRECTION_INFO[direction].axis, 28, 20)

	local rampOriginX, rampOriginZ = mazeLocalToWorld(direction, 0, MAZE_RAMP_START_DEPTH)
	local entryCol = math.ceil((MAZE_GRID_WIDTH + 1) / 2)
	-- Land at the entry cell's near edge, not its center -- landing at the
	-- center would bury half the ramp slab inside the flat cell platform
	-- instead of meeting it cleanly at the boundary (see issue #40/#50's
	-- south-zone review for the same class of mistake).
	local entryEdgeX, entryEdgeZ = mazeLocalToWorld(direction, mazeLateralOffset(entryCol), MAZE_ENTRY_DEPTH - MAZE_CELL_SIZE / 2)
	-- Narrower than a full cell width so it can't overhang into the
	-- entry column's neighboring cells on either side.
	createRamp(folder, wingName .. "Ramp", Vector3.new(rampOriginX, 0, rampOriginZ), Vector3.new(entryEdgeX, MAZE_BASE_Y, entryEdgeZ), MAZE_CELL_SIZE - 4, 3)

	for i = 1, MAZE_LEVEL_COUNT do
		local topY = MAZE_BASE_Y + (i - 1) * MAZE_LEVEL_HEIGHT
		local grid = generateMaze(MAZE_GRID_WIDTH, MAZE_GRID_DEPTH, rng)
		buildMazeLevel(folder, wingName .. "L" .. i, grid, direction, topY)
	end

	for i = 1, MAZE_LEVEL_COUNT - 1 do
		local shaftCol = if i % 2 == 1 then 1 else MAZE_GRID_WIDTH
		local lowerY = MAZE_BASE_Y + (i - 1) * MAZE_LEVEL_HEIGHT
		local upperY = MAZE_BASE_Y + i * MAZE_LEVEL_HEIGHT
		buildMazeShaft(folder, wingName .. "Shaft" .. i, direction, shaftCol, lowerY, upperY)
	end
end

function MapBuilder.Build(): (boolean, string?)
	local ok, err = pcall(function()
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
		-- ever overlapping a spawning player. ===
		local ringRadius = SPAWN_CLEAR_RADIUS + 4
		local pillarCount = 6
		for i = 0, pillarCount - 1 do
			local angle = (i / pillarCount) * math.pi * 2
			local x = math.cos(angle) * ringRadius
			local z = math.sin(angle) * ringRadius
			createPillar(folder, "SpawnRingPillar" .. i, Vector3.new(x, 0, z), 14, 4)
		end

		-- === Background decoration: purely visual floating platforms, high
		-- up and non-collidable, scattered around the perimeter to give the
		-- skyline some silhouettes without being reachable or blocking
		-- movement. Positioned outside every wing's lateral footprint
		-- (+-47 studs either side of its own outward axis) so none of them
		-- sit inside a wing's own airspace. ===
		createFloatingPlatform(folder, "SkylineA", Vector3.new(-90, 70, -230), 30, 2.5, 20, false)
		createFloatingPlatform(folder, "SkylineB", Vector3.new(260, 95, -90), 22, 2.5, 22, false)
		createFloatingPlatform(folder, "SkylineC", Vector3.new(-270, 80, 90), 26, 2.5, 18, false)
		createFloatingPlatform(folder, "SkylineD", Vector3.new(90, 110, 300), 20, 2.5, 26, false)
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

return MapBuilder
