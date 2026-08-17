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
-- South zone: a multi-level, 3D-chess-style maze (issue #41). Each level is
-- an independently generated perfect maze (recursive backtracker -- every
-- cell reachable, no loops, exactly width*height-1 passages), stacked
-- directly above the one below and connected by a staircase shaft in a
-- different corner each transition, so reaching the top requires actually
-- crossing each level's maze rather than climbing a single elevator column.
-- Regenerated fresh every time Build() runs (a freshly-seeded Random() each
-- server start, no stored seed -- no new persistent gameplay state), so the
-- layout varies session to session.
--------------------------------------------------------------------------------

local MAZE_WIDTH = 4
local MAZE_HEIGHT = 4
local MAZE_CELL_SIZE = 14
local MAZE_CELL_GAP = 6
local MAZE_CELL_SPACING = MAZE_CELL_SIZE + MAZE_CELL_GAP
local MAZE_BRIDGE_WIDTH = 6
local MAZE_THICKNESS = 2

-- Untyped-value cells ({[string]: boolean}, not a fixed record) so the
-- carve loop below can index by a direction name held in a variable
-- ("north"/"south"/"east"/"west") -- Luau's strict mode only allows dynamic
-- string-keyed indexing against an index-signature type like this, not a
-- record type with fixed field names.
type MazeCell = { [string]: boolean }
type MazeGrid = { [number]: { [number]: MazeCell } }

-- The center point of grid cell (cellX, cellZ) in a width x height grid
-- centered on (originX, originZ). Shared by every maze-geometry function
-- below so they all agree on exactly the same cell positions.
local function mazeCellCenter(width: number, height: number, originX: number, originZ: number, cellX: number, cellZ: number): (number, number)
	local cx = originX + (cellX - (width + 1) / 2) * MAZE_CELL_SPACING
	local cz = originZ + (cellZ - (height + 1) / 2) * MAZE_CELL_SPACING
	return cx, cz
end

-- Randomized recursive backtracker (iterative, explicit stack -- doesn't
-- rely on Luau's native call-stack depth for a larger grid): carves a
-- perfect maze into a width x height grid. Cells are 1-indexed, {col, row},
-- matching Lua array convention.
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

-- Turns a generated maze grid into a platform per cell plus a bridge
-- wherever the grid carved a passage. Only ever bridges toward east/south
-- from each cell -- the matching west/north flag on the neighbor is set by
-- the same carve, so checking one direction per pair is enough and avoids
-- building the same bridge twice.
local function buildMazeLevel(
	folder: Folder,
	namePrefix: string,
	grid: MazeGrid,
	width: number,
	height: number,
	originX: number,
	originZ: number,
	topY: number
)
	-- Precompute every cell's center once -- each interior cell's center
	-- would otherwise be recomputed a second time when its west/north
	-- neighbor's own bridge check looks it up, since mazeCellCenter is a
	-- pure function of (x, z) already being called for every cell anyway.
	local centersX: { [number]: { [number]: number } } = {}
	local centersZ: { [number]: { [number]: number } } = {}
	for x = 1, width do
		centersX[x] = {}
		centersZ[x] = {}
		for z = 1, height do
			centersX[x][z], centersZ[x][z] = mazeCellCenter(width, height, originX, originZ, x, z)
		end
	end

	for x = 1, width do
		for z = 1, height do
			local cx, cz = centersX[x][z], centersZ[x][z]
			createPlatform(folder, namePrefix .. "Cell" .. x .. "_" .. z, cx, topY, cz, MAZE_CELL_SIZE, MAZE_THICKNESS, MAZE_CELL_SIZE)

			local cell = grid[x][z]
			if cell.east and x < width then
				createPlatform(folder, namePrefix .. "Bridge" .. x .. "_" .. z .. "E", (cx + centersX[x + 1][z]) / 2, topY, cz, MAZE_CELL_GAP + 4, MAZE_THICKNESS, MAZE_BRIDGE_WIDTH)
			end
			if cell.south and z < height then
				createPlatform(folder, namePrefix .. "Bridge" .. x .. "_" .. z .. "S", cx, topY, (cz + centersZ[x][z + 1]) / 2, MAZE_BRIDGE_WIDTH, MAZE_THICKNESS, MAZE_CELL_GAP + 4)
			end
		end
	end
end

-- Connects the same (cellX, cellZ) grid coordinate between two vertically
-- stacked maze levels with a staircase running outward from the grid --
-- never back through it, which is why the caller must pick a shaft cell on
-- an edge/corner and a `direction` pointing away from the grid's interior.
-- Lands on a small platform that's then bridged back to the same cell one
-- level up, so a small mismatch between the staircase's exact landing spot
-- and the cell's own footprint can never leave a gap.
local function buildMazeShaft(
	folder: Folder,
	namePrefix: string,
	width: number,
	height: number,
	originX: number,
	originZ: number,
	cellX: number,
	cellZ: number,
	lowerY: number,
	upperY: number,
	direction: "+X" | "-X" | "+Z" | "-Z"
)
	-- direction must point away from the grid's interior, or the staircase
	-- climbs straight back through this level's own cell platforms/bridges
	-- instead of away from them -- fail loudly (caught by Build()'s pcall)
	-- rather than silently building broken/overlapping geometry.
	local isOutwardEdge = (direction == "+X" and cellX == width)
		or (direction == "-X" and cellX == 1)
		or (direction == "+Z" and cellZ == height)
		or (direction == "-Z" and cellZ == 1)
	assert(
		isOutwardEdge,
		string.format(
			"buildMazeShaft: cell (%d, %d) with direction %s doesn't face outward on a %dx%d grid -- the staircase would run back through the grid",
			cellX,
			cellZ,
			direction,
			width,
			height
		)
	)

	local cx, cz = mazeCellCenter(width, height, originX, originZ, cellX, cellZ)
	local axis: "X" | "Z" = if direction == "+X" or direction == "-X" then "X" else "Z"
	local sign = if direction == "+X" or direction == "+Z" then 1 else -1

	-- 30-step climb sized to exactly cover the level-to-level height
	-- difference. Steeper than NorthStair's own ramp/stair style (that one
	-- optimizes for a grand, sweeping entrance; this is a narrower
	-- connector, not meant to be another showcase climb) but each
	-- individual step still only rises ~1.3 studs, comfortably within
	-- Roblox's default auto-step-up range.
	local steps = 30
	local stepRun = 3
	local stepRise = (upperY - lowerY) / steps

	local landing = createStaircase(folder, namePrefix .. "Stair", Vector3.new(cx, lowerY, cz), axis, sign, steps, stepRun, stepRise, MAZE_CELL_SIZE)
	createPlatform(folder, namePrefix .. "Landing", landing.X, landing.Y, landing.Z, MAZE_CELL_SIZE, MAZE_THICKNESS, MAZE_CELL_SIZE)

	local runLength = steps * stepRun
	if axis == "X" then
		createPlatform(folder, namePrefix .. "LandingBridge", (cx + landing.X) / 2, upperY, cz, runLength + 4, MAZE_THICKNESS, MAZE_BRIDGE_WIDTH)
	else
		createPlatform(folder, namePrefix .. "LandingBridge", cx, upperY, (cz + landing.Z) / 2, MAZE_BRIDGE_WIDTH, MAZE_THICKNESS, runLength + 4)
	end
end

function MapBuilder.Build(): (boolean, string?)
	local ok, err = pcall(function()
		local folder = Instance.new("Folder")
		folder.Name = "Map"
		folder.Parent = workspace

		-- === North zone: ramp up to Platform A, then stairs further up to
		-- the higher Platform A2. Demonstrates both connector types in one
		-- continuous path. ===
		createArch(folder, "NorthGate", Vector3.new(0, 0, -28), "Z", 28, 20)
		createRamp(folder, "NorthRamp", Vector3.new(0, 0, -35), Vector3.new(0, 20, -95), 26, 3)
		createPlatform(folder, "PlatformA", 0, 20, -130, 70, 3, 70)

		local stairLanding = createStaircase(folder, "NorthStair", Vector3.new(0, 20, -165), "Z", -1, 10, 9, 1.5, 30)
		createPlatform(folder, "PlatformA2", stairLanding.X, stairLanding.Y, stairLanding.Z - 25, 50, 3, 50)

		-- === East zone: gentle ramp up to Platform B, then a chain of
		-- smaller floating stepping-stone platforms continuing further east
		-- to a small overlook platform -- a jump-across connector instead of
		-- a ramp/stair, for variety. ===
		createRamp(folder, "EastRamp", Vector3.new(35, 0, 0), Vector3.new(140, 22, 0), 24, 3)
		createPlatform(folder, "PlatformB", 167.5, 22, 0, 55, 3, 55)

		createFloatingPlatform(folder, "SteppingStone1", Vector3.new(212, 23, 12), 14, 2, 14, true)
		createFloatingPlatform(folder, "SteppingStone2", Vector3.new(236, 24.5, -6), 14, 2, 14, true)
		createFloatingPlatform(folder, "SteppingStone3", Vector3.new(260, 26, 10), 14, 2, 14, true)
		createPlatform(folder, "OverlookPlatform", 292, 27, 0, 26, 3, 26)

		-- === West zone: a wider, taller ramp to Platform C, framed by an
		-- entrance arch, for a third distinct elevated area. ===
		createArch(folder, "WestGate", Vector3.new(-28, 0, 0), "X", 28, 22)
		createRamp(folder, "WestRamp", Vector3.new(-35, 0, 0), Vector3.new(-150, 26, 0), 28, 3)
		createPlatform(folder, "PlatformC", -180, 26, 0, 60, 3, 60)

		-- === South zone: multi-level 3D-chess-style maze (issue #41). Entry
		-- gate/ramp mirrors the other three zones', landing at the near
		-- edge of Level 1's maze; two staircase shafts (different corners,
		-- both running further away from spawn so neither can cross back
		-- through a grid) carry the path up through Level 2 to Level 3. ===
		local mazeRng = Random.new()
		local mazeOriginX, mazeOriginZ = 0, 150
		local mazeLevel1Y, mazeLevel2Y, mazeLevel3Y = 20, 60, 100

		createArch(folder, "SouthGate", Vector3.new(0, 0, 28), "Z", 28, 20)
		local mazeEntryX, mazeEntryZ = mazeCellCenter(MAZE_WIDTH, MAZE_HEIGHT, mazeOriginX, mazeOriginZ, 2, 1)
		-- Narrower than the other zones' ramps (those land on 50-70-stud
		-- platforms with plenty of room) -- this one lands on a single
		-- MAZE_CELL_SIZE-wide maze cell, so its width has to stay safely
		-- inside that footprint rather than overhanging into cell (1,1) or
		-- (3,1) on either side.
		createRamp(folder, "SouthRamp", Vector3.new(0, 0, 35), Vector3.new(mazeEntryX, mazeLevel1Y, mazeEntryZ), MAZE_CELL_SIZE - 4, 3)

		local mazeLevel1 = generateMaze(MAZE_WIDTH, MAZE_HEIGHT, mazeRng)
		local mazeLevel2 = generateMaze(MAZE_WIDTH, MAZE_HEIGHT, mazeRng)
		local mazeLevel3 = generateMaze(MAZE_WIDTH, MAZE_HEIGHT, mazeRng)

		buildMazeLevel(folder, "MazeL1", mazeLevel1, MAZE_WIDTH, MAZE_HEIGHT, mazeOriginX, mazeOriginZ, mazeLevel1Y)
		buildMazeLevel(folder, "MazeL2", mazeLevel2, MAZE_WIDTH, MAZE_HEIGHT, mazeOriginX, mazeOriginZ, mazeLevel2Y)
		buildMazeLevel(folder, "MazeL3", mazeLevel3, MAZE_WIDTH, MAZE_HEIGHT, mazeOriginX, mazeOriginZ, mazeLevel3Y)

		-- Corner (MAZE_WIDTH, MAZE_HEIGHT) for the first shaft, the opposite
		-- corner (1, MAZE_HEIGHT) for the second, so climbing from Level 1
		-- to Level 3 forces crossing Level 2's maze from one side to the
		-- other rather than landing right next to the next shaft up.
		buildMazeShaft(folder, "MazeShaft1", MAZE_WIDTH, MAZE_HEIGHT, mazeOriginX, mazeOriginZ, MAZE_WIDTH, MAZE_HEIGHT, mazeLevel1Y, mazeLevel2Y, "+Z")
		buildMazeShaft(folder, "MazeShaft2", MAZE_WIDTH, MAZE_HEIGHT, mazeOriginX, mazeOriginZ, 1, MAZE_HEIGHT, mazeLevel2Y, mazeLevel3Y, "+Z")

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
		-- movement. ===
		createFloatingPlatform(folder, "SkylineA", Vector3.new(-90, 70, -190), 30, 2.5, 20, false)
		createFloatingPlatform(folder, "SkylineB", Vector3.new(220, 95, -120), 22, 2.5, 22, false)
		createFloatingPlatform(folder, "SkylineC", Vector3.new(-230, 80, 60), 26, 2.5, 18, false)
		createFloatingPlatform(folder, "SkylineD", Vector3.new(60, 110, -260), 20, 2.5, 26, false)
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

return MapBuilder
