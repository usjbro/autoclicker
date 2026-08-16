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
		local topY = i * stepRise
		local offset = sign * (stepRun * i - stepRun / 2)
		local centerX = if axis == "X" then origin.X + offset else origin.X
		local centerZ = if axis == "Z" then origin.Z + offset else origin.Z
		local sizeX = if axis == "X" then stepRun else width
		local sizeZ = if axis == "Z" then stepRun else width
		newPart(folder, name .. i, {
			Size = Vector3.new(sizeX, topY, sizeZ),
			CFrame = CFrame.new(centerX, topY / 2, centerZ),
			Color = if i % 2 == 0 then PANEL else DARK,
		})
	end
	local finalOffset = sign * (stepRun * steps)
	local landX = if axis == "X" then origin.X + finalOffset else origin.X
	local landZ = if axis == "Z" then origin.Z + finalOffset else origin.Z
	return Vector3.new(landX, steps * stepRise, landZ)
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
-- them. `axis` is the direction the arch's opening faces along.
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

function MapBuilder.Build(): (boolean, string?)
	local ok, err = pcall(function()
		local folder = Instance.new("Folder")
		folder.Name = "Map"
		folder.Parent = workspace

		-- === North zone: ramp up to Platform A, then stairs further up to
		-- the higher Platform A2. Demonstrates both connector types in one
		-- continuous path. ===
		createArch(folder, "NorthGate", Vector3.new(0, 0, -28), "X", 28, 20)
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
		createArch(folder, "WestGate", Vector3.new(-28, 0, 0), "Z", 28, 22)
		createRamp(folder, "WestRamp", Vector3.new(-35, 0, 0), Vector3.new(-150, 26, 0), 28, 3)
		createPlatform(folder, "PlatformC", -180, 26, 0, 60, 3, 60)

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
