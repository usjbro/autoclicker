--!strict
-- Builds a static, explorable layout of platforms/portals/decoration inside
-- the VoidBox for Movement mode. Pure geometry -- no gameplay state, no
-- RemoteEvents. Mirrors the pcall-wrapped-and-report-failure pattern
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

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MazeGeometry = require(Shared:WaitForChild("MazeGeometry"))
local NeonScript = require(Shared:WaitForChild("NeonScript"))

local DARK = Color3.fromHex("1e1e2f")
local PANEL = Color3.fromHex("2a2a3f")
local ACCENT = Color3.fromHex("6c5ce7")

-- VoidSpawn sits at the origin (see GameService.server.lua); keep a clear
-- radius around it so nothing built here ever overlaps a spawning player.
local SPAWN_CLEAR_RADIUS = 32
-- How far outside SPAWN_CLEAR_RADIUS the spawn ring's own pillars sit --
-- shared by the ring-building code and assertMazeConstants below.
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

-- A flat elevated platform. `topY` is the walkable surface height; the part
-- itself is centered `thickness/2` below that so callers can reason about
-- surfaces landing exactly on it instead of the part's center.
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
-- them. `axis` is the direction of travel through the opening -- pillars
-- flank PERPENDICULAR to it, not along it. Getting this backwards silently
-- plants a pillar on the path's own centerline instead of beside it. Used
-- decoratively to frame each portal pad below, not as a walk-through gate
-- (portals are stepped onto, not walked through).
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
-- The map: four self-contained maze tiles (issue #60, superseding #55's
-- multi-level-per-wing design), one per difficulty, reached from the hub via
-- a teleport portal rather than a walk-in gate. Each tile is its own
-- isolated pocket, far from the hub and every other tile (see
-- MazeGeometry.WING_ANCHORS) -- nothing physically connects them. The
-- player spawns in the tile's own grid-center cell (issue #60's "center
-- spawn") and the goal sits at whichever reachable cell ends up farthest
-- away by maze-path distance (MazeGeometry.FarthestCell, a BFS over the
-- maze's real carved connectivity, not straight-line distance). Touching
-- the goal grants that wing's permanent click-rate bonus (once) and
-- teleports back to the hub (every time) -- both wired by
-- GameService.server.lua, which finds this file's named parts after
-- Build() returns; this file stays pure geometry, no gameplay state or
-- RemoteEvents of its own.
--
-- Every tile fills the exact same fixed footprint (MazeGeometry.
-- TILE_FOOTPRINT) regardless of difficulty -- difficulty is expressed
-- entirely through cell density within that fixed space (MazeGeometry.
-- WING_CONFIGS' per-wing cellSize), not a bigger or smaller plot of land.
-- Each tile's maze is one independently generated perfect maze (randomized
-- recursive backtracker -- every cell reachable, no loops), regenerated
-- fresh every time Build() runs (a freshly-seeded Random() each server
-- start, no stored seed), so the layout varies session to session.
--
-- Each tile's floor and ceiling are each one continuous platform --
-- connectivity between cells is expressed entirely by walls (see
-- buildMazeWall/buildMazeLevel below), not by gaps in the floor. A wall
-- reaches from floor to ceiling with no gap, so nothing can slip sideways
-- between a wall's top and the ceiling's underside -- containment comes
-- from the full floor-wall-ceiling enclosure, not from wall height alone
-- (an earlier design's mistake, see issue #40/#50's history for this class
-- of bug). Every boundary edge of the grid is always walled -- there's no
-- special opening anywhere, since entry/exit is by teleport, not by
-- walking through a gap in the wall.
--------------------------------------------------------------------------------

local MAZE_WALL_THICKNESS = 2
local MAZE_WALL_HEIGHT = MazeGeometry.WALL_HEIGHT
local MAZE_THICKNESS = MazeGeometry.THICKNESS
local MAZE_BASE_Y = MazeGeometry.BASE_Y

-- Wing theme colors -- gridSize/cellSize come from MazeGeometry.WING_CONFIGS
-- (the single source of truth, shared with the Lune-testable geometry
-- math); only the colors are this file's own.
local WING_THEME_COLORS: { [string]: { structuralColor: Color3, trimColor: Color3 } } = {
	MazeN = { structuralColor = Color3.fromHex("2ecc71"), trimColor = Color3.fromHex("6fe8a0") },
	MazeS = { structuralColor = Color3.fromHex("f1c40f"), trimColor = Color3.fromHex("f7dc6f") },
	MazeE = { structuralColor = Color3.fromHex("e67e22"), trimColor = Color3.fromHex("f0a860") },
	MazeW = { structuralColor = Color3.fromHex("e74c3c"), trimColor = Color3.fromHex("f17d72") },
}

-- Portal pads sit just outside the spawn ring, one per compass direction --
-- purely for a familiar hub layout; nothing about a tile's own geometry
-- depends on which compass direction its portal happens to be in anymore.
local PORTAL_DEPTH = 50
local PORTAL_POSITIONS: { [string]: { x: number, z: number, axis: "X" | "Z" } } = {
	MazeN = { x = 0, z = -PORTAL_DEPTH, axis = "Z" },
	MazeE = { x = PORTAL_DEPTH, z = 0, axis = "X" },
	MazeS = { x = 0, z = PORTAL_DEPTH, axis = "Z" },
	MazeW = { x = -PORTAL_DEPTH, z = 0, axis = "X" },
}

local WING_NAMES = { "MazeN", "MazeE", "MazeS", "MazeW" }
local DIFFICULTY_LABELS: { [string]: string } = {
	MazeN = "EASY",
	MazeS = "MEDIUM",
	MazeE = "HARD",
	MazeW = "VERY HARD",
}

-- Sanity checks on the constants above, run from inside Build()'s own
-- pcall (not at module load, which would otherwise crash
-- GameService.server.lua's unprotected `require(MapBuilder)` and take down
-- every RemoteEvent handler in the game, not just the map, if any check
-- ever failed).
local function assertMazeConstants()
	for wingName, config in pairs(MazeGeometry.WING_CONFIGS) do
		assert(
			config.gridSize * config.cellSize == MazeGeometry.TILE_FOOTPRINT,
			string.format("%s: gridSize * cellSize does not equal TILE_FOOTPRINT", wingName)
		)
	end

	-- Tiles are far enough apart that their footprints can never overlap:
	-- every pairwise anchor distance must clear twice the footprint's half-
	-- width (each tile's own half-width, plus the other's).
	local halfFootprint = MazeGeometry.TILE_FOOTPRINT / 2
	for i = 1, #WING_NAMES do
		for j = i + 1, #WING_NAMES do
			local a, b = MazeGeometry.WING_ANCHORS[WING_NAMES[i]], MazeGeometry.WING_ANCHORS[WING_NAMES[j]]
			local dx, dz = a.x - b.x, a.z - b.z
			local distance = math.sqrt(dx * dx + dz * dz)
			assert(
				distance > halfFootprint * 2,
				string.format("%s and %s tile anchors are too close, footprints could overlap", WING_NAMES[i], WING_NAMES[j])
			)
		end
	end

	-- Every portal pad clears the spawn ring's own radius with margin.
	for wingName, pos in pairs(PORTAL_POSITIONS) do
		local distance = math.sqrt(pos.x ^ 2 + pos.z ^ 2)
		assert(
			distance > SPAWN_CLEAR_RADIUS + SPAWN_RING_PADDING + 2,
			string.format("%s portal too close to spawn ring", wingName)
		)
	end
end

type MazeGrid = MazeGeometry.MazeGrid

-- Randomized recursive backtracker (iterative, explicit stack -- doesn't
-- rely on Luau's native call-stack depth for a larger grid): carves a
-- perfect maze into a gridSize x gridSize grid. Cells are 1-indexed,
-- {col, row}, matching Lua array convention.
local function generateMaze(gridSize: number, rng: Random): MazeGrid
	local grid: MazeGrid = {}
	local visited: { [number]: { [number]: boolean } } = {}
	for x = 1, gridSize do
		grid[x] = {}
		visited[x] = {}
		for z = 1, gridSize do
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

	local startX, startZ = rng:NextInteger(1, gridSize), rng:NextInteger(1, gridSize)
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
			if nx >= 1 and nx <= gridSize and nz >= 1 and nz <= gridSize and not visited[nx][nz] then
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

-- One continuous platform spanning a whole tile's grid -- cell connectivity
-- is expressed entirely by walls (see buildMazeWall/buildMazeLevel below),
-- not by gaps in the floor, so the floor itself never needs to be
-- segmented per cell. Every tile is a square, so this is a single square
-- platform of side gridSize * cellSize (== TILE_FOOTPRINT), centered on
-- the tile's own anchor.
local function buildMazeFloor(folder: Folder, name: string, anchorX: number, anchorZ: number, topY: number, gridSize: number, cellSize: number)
	local extent = gridSize * cellSize
	createPlatform(folder, name, anchorX, topY, anchorZ, extent, MAZE_THICKNESS, extent)
end

local WALL_SIDE_INFO: { [string]: { axis: "X" | "Z", sign: number } } = {
	east = { axis = "X", sign = 1 },
	west = { axis = "X", sign = -1 },
	south = { axis = "Z", sign = 1 },
	north = { axis = "Z", sign = -1 },
}

-- A wall segment blocking movement across grid cell (col, row)'s named
-- side. MAZE_WALL_HEIGHT comfortably exceeds Roblox's default jump height,
-- so a wall can't just be jumped over; every non-open connection is
-- genuinely impassable.
local function buildMazeWall(folder: Folder, name: string, anchorX: number, anchorZ: number, topY: number, col: number, row: number, side: "north" | "south" | "east" | "west", gridSize: number, cellSize: number)
	local cellX, cellZ = MazeGeometry.TileCellCenter(anchorX, anchorZ, col, row, gridSize, cellSize)
	local info = WALL_SIDE_INFO[side]
	local wx = if info.axis == "X" then cellX + info.sign * cellSize / 2 else cellX
	local wz = if info.axis == "Z" then cellZ + info.sign * cellSize / 2 else cellZ
	local sizeX = if info.axis == "X" then MAZE_WALL_THICKNESS else cellSize
	local sizeZ = if info.axis == "Z" then MAZE_WALL_THICKNESS else cellSize

	newPart(folder, name, {
		Size = Vector3.new(sizeX, MAZE_WALL_HEIGHT, sizeZ),
		CFrame = CFrame.new(wx, topY + MAZE_WALL_HEIGHT / 2, wz),
		Color = DARK,
	})
end

-- Builds one tile's floor, ceiling, and every wall the maze grid requires.
-- Only cell.east/cell.south are checked for internal walls (not
-- cell.west/cell.north) -- generateMaze sets both cells' flags
-- symmetrically on every carved connection, so "cell (col,row)'s west wall"
-- and "cell (col-1,row)'s east wall" are the same physical wall; checking
-- east/south only (and west/north only at the grid's own outer boundary,
-- col==1/row==1) builds each wall exactly once instead of twice.
local function buildMazeLevel(folder: Folder, namePrefix: string, grid: MazeGrid, anchorX: number, anchorZ: number, topY: number, gridSize: number, cellSize: number)
	buildMazeFloor(folder, namePrefix .. "Floor", anchorX, anchorZ, topY, gridSize, cellSize)
	-- A solid ceiling with its underside flush against every wall's top --
	-- see buildMazeFloor's own use for the floor at a lower topY.
	buildMazeFloor(folder, namePrefix .. "Ceiling", anchorX, anchorZ, topY + MAZE_WALL_HEIGHT + MAZE_THICKNESS, gridSize, cellSize)

	for col = 1, gridSize do
		for row = 1, gridSize do
			local cell = grid[col][row]

			if col == gridSize or not cell.east then
				buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "E", anchorX, anchorZ, topY, col, row, "east", gridSize, cellSize)
			end
			if col == 1 then
				buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "W", anchorX, anchorZ, topY, col, row, "west", gridSize, cellSize)
			end
			if row == gridSize or not cell.south then
				buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "S", anchorX, anchorZ, topY, col, row, "south", gridSize, cellSize)
			end
			if row == 1 then
				buildMazeWall(folder, namePrefix .. "Wall" .. col .. "_" .. row .. "N", anchorX, anchorZ, topY, col, row, "north", gridSize, cellSize)
			end
		end
	end
end

-- Recolors every part built for one wing to its theme, once that wing's
-- geometry is fully built: Neon (trim/accent) parts get the theme's
-- trimColor, everything else gets structuralColor.
local function paintWing(wingFolder: Folder, theme: { structuralColor: Color3, trimColor: Color3 })
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

-- Builds one complete maze tile: the maze itself, a named spawn marker at
-- the grid-center cell (issue #60's "center spawn" -- GameService.server.lua
-- reads its Position as the portal's teleport destination), and a goal
-- marker at whichever cell BFS finds farthest from center by maze-path
-- distance. All of this tile's parts are parented under their own
-- sub-Folder (not directly under the shared Map folder `mapFolder`) so
-- paintWing's repaint pass only ever touches this tile's own geometry.
local function buildMazeWing(mapFolder: Folder, wingName: string, rng: Random)
	local config = MazeGeometry.WING_CONFIGS[wingName]
	local anchor = MazeGeometry.WING_ANCHORS[wingName]
	local folder = Instance.new("Folder")
	folder.Name = wingName
	folder.Parent = mapFolder

	local grid = generateMaze(config.gridSize, rng)
	buildMazeLevel(folder, wingName, grid, anchor.x, anchor.z, MAZE_BASE_Y, config.gridSize, config.cellSize)

	-- Painted before the spawn/goal markers are created (not after) so the
	-- repaint pass -- which recolors every Neon descendant to the wing's own
	-- trimColor -- can never touch them; both stay a fixed white regardless
	-- of which wing's theme they belong to, so they always read as unique
	-- landmarks rather than blending into the rest of that wing's own
	-- decoration.
	paintWing(folder, WING_THEME_COLORS[wingName])

	local centerCol, centerRow = MazeGeometry.CenterCell(config.gridSize)
	local spawnX, spawnZ = MazeGeometry.TileCellCenter(anchor.x, anchor.z, centerCol, centerRow, config.gridSize, config.cellSize)
	local MARKER_COLOR = Color3.fromHex("ffffff")
	newPart(folder, wingName .. "Spawn", {
		Size = Vector3.new(config.cellSize - 4, 0.6, config.cellSize - 4),
		CFrame = CFrame.new(spawnX, MAZE_BASE_Y + 0.3, spawnZ),
		Color = MARKER_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = false,
	})

	local goalCol, goalRow, _goalDistance = MazeGeometry.FarthestCell(grid, centerCol, centerRow)
	local goalX, goalZ = MazeGeometry.TileCellCenter(anchor.x, anchor.z, goalCol, goalRow, config.gridSize, config.cellSize)
	newPart(folder, wingName .. "Goal", {
		Size = Vector3.new(config.cellSize - 4, 0.6, config.cellSize - 4),
		CFrame = CFrame.new(goalX, MAZE_BASE_Y + 0.3, goalZ),
		Color = MARKER_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	newPart(folder, wingName .. "GoalBeacon", {
		Size = Vector3.new(2, MAZE_WALL_HEIGHT - 1, 2),
		CFrame = CFrame.new(goalX, MAZE_BASE_Y + (MAZE_WALL_HEIGHT - 1) / 2, goalZ),
		Color = MARKER_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = false,
	})
end

-- Builds one portal pad near the hub: a glowing, walkable pad (themed to
-- the destination wing's color) framed by a decorative arch, with a
-- floating neon sign above it naming the destination difficulty. Named
-- wingName .. "Portal" so GameService.server.lua can find it by name after
-- Build() returns and wire the actual teleport -- this file stays pure
-- geometry, no RemoteEvents/gameplay state of its own.
-- A thin, glowing rod-and-ball chain following `points` in order -- a small
-- Neon Ball "joint" at every point (so consecutive segments blend into one
-- smooth run instead of showing sharp corners, mimicking a real bent glass
-- tube) plus a thin Neon box between every consecutive pair, oriented via
-- the same CFrame.lookAt(center, center + diff.Unit, up) technique
-- createRamp already uses elsewhere in this file (a box, not a true
-- Enum.PartType.Cylinder, specifically to reuse that already-proven
-- orientation technique rather than work out a cylinder's own default-axis
-- convention from scratch -- a thin square rod reads the same as a round
-- glass tube at sign scale once it's glowing Neon). Falls back to a
-- different up-reference when a segment is (near-)vertical, since
-- CFrame.lookAt's direction and up vectors can't be parallel -- several of
-- the hand-authored glyphs below have exactly vertical strokes (e.g. "H"'s
-- stems), so this isn't just a theoretical edge case.
local function buildNeonTube(folder: Folder, name: string, points: { Vector3 }, radius: number, color: Color3)
	local diameter = radius * 2
	for i, point in ipairs(points) do
		newPart(folder, name .. "Joint" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(diameter, diameter, diameter),
			CFrame = CFrame.new(point),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = false,
		})
	end
	for i = 1, #points - 1 do
		local p0, p1 = points[i], points[i + 1]
		local diff = p1 - p0
		local length = diff.Magnitude
		if length > 0.001 then
			local direction = diff.Unit
			local center = p0 + diff / 2
			local up = Vector3.new(0, 1, 0)
			if math.abs(direction:Dot(up)) > 0.999 then
				up = Vector3.new(1, 0, 0)
			end
			newPart(folder, name .. "Seg" .. i, {
				Size = Vector3.new(diameter, diameter, length),
				CFrame = CFrame.lookAt(center, center + direction, up),
				Color = color,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanTouch = false,
			})
		end
	end
end

-- Maps a glyph-local (localX, localY) point -- localX horizontal along the
-- word, localY vertical, both already scaled to studs -- onto the vertical
-- plane in front of this portal, oriented to actually face the portal's
-- own approach direction. Getting this wrong is exactly the kind of thing
-- that's easy to miss when only one wing happens to test correctly by
-- coincidence: axis == "Z" wings (their approach direction runs along
-- world Z) need the sign's width running along world X at a fixed Z; axis
-- == "X" wings need the opposite (width along world Z at a fixed X) -- a
-- single hardcoded orientation would silently work for one axis and show
-- the sign edge-on, unreadable, for the other. `depthOffset` moves the
-- point along the portal's own depth axis (world Z for axis == "Z", world X
-- for axis == "X") -- 0 for the backing plate itself, a positive offset
-- (see towardSpawnOffset below) for the tubes, so they sit clearly in front
-- of the plate's face instead of embedded at its exact center depth. An
-- earlier version always passed an implicit 0 for every point, including
-- the tubes -- since the plate is only 0.5 studs thick, a tube (0.4 stud
-- diameter) centered at that same depth was almost entirely enclosed
-- inside the opaque plate, poking out by only ~0.05 studs on each face --
-- fully occluded at any real viewing distance, confirmed by a Studio
-- screenshot showing a bare plate with no letters visible at all.
-- axis == "X" negates localX (pos.z - localX, not + localX) -- confirmed
-- needed by a live Studio screenshot showing MazeE/MazeW's signs ("HARD"/
-- "VERY HARD") rendering as a horizontal mirror image of MazeN/MazeS's
-- ("EASY"/"MEDIUM", which read left-to-right correctly). Without the
-- negation, increasing localX (moving rightward through the word) maps to
-- increasing world Z for every axis == "X" portal, but the player actually
-- reads the sign's plane in the opposite screen-direction there compared to
-- an axis == "Z" portal -- a plain sign-flip the axis == "Z" branch happens
-- not to need.
local function signWorldPosition(pos: { x: number, z: number, axis: "X" | "Z" }, localX: number, localY: number, depthOffset: number): Vector3
	if pos.axis == "Z" then
		return Vector3.new(pos.x + localX, localY, pos.z + depthOffset)
	else
		return Vector3.new(pos.x + depthOffset, localY, pos.z - localX)
	end
end

-- Every portal sits directly out from the origin along one compass
-- direction (see PORTAL_POSITIONS), so "toward spawn" -- the side the
-- approaching player is actually on, and so the side the tubes need to
-- offset toward to be visible instead of embedded in the plate -- is always
-- the opposite sign of whichever coordinate is nonzero for that portal's
-- axis. Unlike a single hardcoded offset direction, this works for both
-- wings sharing an axis (e.g. MazeN at z = -50 and MazeS at z = +50 need
-- opposite offsets, since spawn at z = 0 is on the opposite side of each).
local function towardSpawnOffset(pos: { x: number, z: number, axis: "X" | "Z" }, distance: number): number
	local axisValue = if pos.axis == "Z" then pos.z else pos.x
	return if axisValue >= 0 then -distance else distance
end

local PORTAL_SIZE = 10
local SIGN_TARGET_WIDTH = 14 -- studs -- every word scales to fill this, regardless of letter count
local SIGN_CENTER_Y = 20
local SIGN_TUBE_RADIUS = 0.2
local SIGN_LETTER_SPACING = 0.08 -- in glyph-local units, same scale as NeonScript.GLYPHS' own ~0.5-wide letters
local SIGN_VERTICAL_PADDING = 1.5 -- studs of backing-plate margin above/below the tallest/lowest stroke
-- Clears the plate's own half-thickness (0.25) plus the tube's own radius
-- (0.2) plus a small visible gap, so the entire tube sits proud of the
-- plate's face rather than merely not-fully-enclosed by it.
local SIGN_TUBE_DEPTH_OFFSET = 0.6

local function buildPortal(mapFolder: Folder, wingName: string)
	local pos = PORTAL_POSITIONS[wingName]
	local theme = WING_THEME_COLORS[wingName]
	local folder = Instance.new("Folder")
	folder.Name = wingName .. "PortalDecor"
	folder.Parent = mapFolder

	newPart(folder, wingName .. "Portal", {
		Size = Vector3.new(PORTAL_SIZE, 1, PORTAL_SIZE),
		CFrame = CFrame.new(pos.x, 0.5, pos.z),
		Color = theme.structuralColor,
		Material = Enum.Material.Neon,
		CanCollide = true,
		CanTouch = true,
	})

	createArch(folder, wingName .. "PortalArch", Vector3.new(pos.x, 0, pos.z), pos.axis, PORTAL_SIZE + 4, 16)

	-- Real neon-tube signage: hand-authored cursive glyph paths
	-- (NeonScript.lua) rendered as glowing Neon rod-and-ball chains, not a
	-- flat TextLabel -- see the plan this was built from for why a
	-- TextLabel doesn't read as a neon sign at all. A dark backing plate
	-- sits behind the tubes (real neon signs are normally mounted on a
	-- dark board), sized and axis-oriented to the word's own actual scaled
	-- width via signWorldPosition, same as the tubes themselves -- not the
	-- flat, orientation-unaware plate the old sign used.
	local wordPath = NeonScript.WordPath(DIFFICULTY_LABELS[wingName], SIGN_LETTER_SPACING)
	local scale = if wordPath.width > 0 then SIGN_TARGET_WIDTH / wordPath.width else 1

	-- The word's actual rendered vertical extent, in glyph-local units --
	-- read directly from its points rather than assumed from a fixed
	-- constant. A prior version assumed glyph-y 0.3 was always the vertical
	-- center and gave the backing plate a fixed 3-stud height regardless of
	-- word/scale; since scale is driven entirely by fitting SIGN_TARGET_WIDTH
	-- (short words like "EASY"/"HARD" scale up more than long ones), that
	-- same scale also stretched the letters' height well past the fixed
	-- plate -- confirmed via a diagnostic script showing "EASY"'s tubes
	-- reaching a full stud above the plate's top edge, matching a Studio
	-- screenshot of tube fragments floating above a bare plate with no
	-- readable letters on its face. Sizing/centering the plate on the real
	-- extent makes every word fit its own sign, not just ones that happen to
	-- match the assumed range.
	local minRawY, maxRawY = math.huge, -math.huge
	for _, run in ipairs(wordPath.runs) do
		for _, p in ipairs(run) do
			minRawY = math.min(minRawY, p.y)
			maxRawY = math.max(maxRawY, p.y)
		end
	end
	local rawCenterY = if minRawY <= maxRawY then (minRawY + maxRawY) / 2 else 0.3
	local signHeight = (if minRawY <= maxRawY then (maxRawY - minRawY) * scale else 0) + SIGN_VERTICAL_PADDING

	newPart(folder, wingName .. "PortalSign", {
		Size = Vector3.new(SIGN_TARGET_WIDTH + 2, signHeight, 0.5),
		CFrame = CFrame.new(signWorldPosition(pos, 0, SIGN_CENTER_Y, 0)) * (if pos.axis == "X" then CFrame.Angles(0, math.rad(90), 0) else CFrame.Angles(0, 0, 0)),
		Color = DARK,
		CanCollide = false,
		CanTouch = false,
	})

	local tubeDepthOffset = towardSpawnOffset(pos, SIGN_TUBE_DEPTH_OFFSET)
	for runIndex, run in ipairs(wordPath.runs) do
		local worldPoints = {}
		for _, p in ipairs(run) do
			local localX = (p.x - wordPath.width / 2) * scale
			local localY = SIGN_CENTER_Y + (p.y - rawCenterY) * scale
			table.insert(worldPoints, signWorldPosition(pos, localX, localY, tubeDepthOffset))
		end
		buildNeonTube(folder, wingName .. "SignRun" .. runIndex, worldPoints, SIGN_TUBE_RADIUS, theme.trimColor)
	end
end

function MapBuilder.Build(): (boolean, string?)
	local ok, err = pcall(function()
		assertMazeConstants()

		local folder = Instance.new("Folder")
		folder.Name = "Map"
		folder.Parent = workspace

		-- === Four maze tiles, one per difficulty, each its own isolated
		-- pocket far from the hub and every other tile -- sharing one Random
		-- so no two tiles can ever coincidentally generate identically. ===
		local mazeRng = Random.new()
		for _, wingName in ipairs(WING_NAMES) do
			buildMazeWing(folder, wingName, mazeRng)
			buildPortal(folder, wingName)
		end

		-- === Central decoration: a ring of pillars around spawn, just
		-- outside SPAWN_CLEAR_RADIUS, so the hub reads as a landmark without
		-- ever overlapping a spawning player. Offset 15 degrees off the
		-- cardinal angles (0/90/180/270, i.e. the four portals' own
		-- approach centerlines, all at lateral=0) -- 6 pillars every 60
		-- degrees would otherwise put one directly on a portal's approach
		-- centerline. ===
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
		-- up and non-collidable, positioned well outside the hub and every
		-- tile's own footprint so they read as distant skyline silhouettes
		-- rather than sitting awkwardly close to any of them. Not reachable
		-- and don't block movement. ===
		createFloatingPlatform(folder, "SkylineA", Vector3.new(-1500, 90, -6000), 30, 2.5, 20, false)
		createFloatingPlatform(folder, "SkylineB", Vector3.new(6000, 120, -1500), 22, 2.5, 22, false)
		createFloatingPlatform(folder, "SkylineC", Vector3.new(-6000, 100, 1500), 26, 2.5, 18, false)
		createFloatingPlatform(folder, "SkylineD", Vector3.new(1500, 140, 6000), 20, 2.5, 26, false)
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

return MapBuilder
