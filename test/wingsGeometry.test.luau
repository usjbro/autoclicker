-- Headless test runner for src/shared/WingsGeometry.lua, run via:
-- lune run test/wingsGeometry.test.luau
-- Exercises the pure direction-blend math WingsVisualSystem.lua's
-- fanCFrame builds wing geometry from, without needing a Roblox Studio
-- session. This exact class of math (which axis a rotation applies to,
-- which sign points which way) has already shipped one real bug in this
-- codebase's history -- see CLAUDE.md's WingsVisualSystem.lua bullet --
-- these tests are what actually prevent the next one.
local process = require("@lune/process")
local WingsGeometry = require("../src/shared/WingsGeometry")

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

local function assertNear(actual: number, expected: number, epsilon: number, message: string?)
	if math.abs(actual - expected) > epsilon then
		error(("%s (expected ~%s, got %s)"):format(message or "values differ", tostring(expected), tostring(actual)))
	end
end

local EPSILON = 1e-9

print("WingsGeometry (Lune)")

test("FanDirection points straight up at spreadDeg=0, regardless of side", function()
	for _, side in ipairs({ -1, 1 }) do
		local x, y, z = WingsGeometry.FanDirection(0, side)
		assertNear(x, 0, EPSILON, "x")
		assertNear(y, 1, EPSILON, "y")
		assertNear(z, 0, EPSILON, "z")
	end
end)

test("FanDirection points straight lateral (mirrored by side) at spreadDeg=90", function()
	local x, y, z = WingsGeometry.FanDirection(90, 1)
	assertNear(x, 0, EPSILON, "x")
	assertNear(y, 0, EPSILON, "y")
	assertNear(z, 1, EPSILON, "z")

	x, y, z = WingsGeometry.FanDirection(90, -1)
	assertNear(x, 0, EPSILON, "x")
	assertNear(y, 0, EPSILON, "y")
	assertNear(z, -1, EPSILON, "z")
end)

test("FanDirection blends evenly at spreadDeg=45", function()
	local x, y, z = WingsGeometry.FanDirection(45, 1)
	local expected = math.sqrt(2) / 2
	assertNear(x, 0, EPSILON, "x")
	assertNear(y, expected, EPSILON, "y")
	assertNear(z, expected, EPSILON, "z")
end)

test("FanDirection always returns a unit vector", function()
	for _, side in ipairs({ -1, 1 }) do
		for _, spreadDeg in ipairs({ 0, 15, 37, 60, 90 }) do
			local x, y, z = WingsGeometry.FanDirection(spreadDeg, side)
			local magnitude = math.sqrt(x * x + y * y + z * z)
			assertNear(magnitude, 1, EPSILON, ("magnitude at spreadDeg=%d side=%d"):format(spreadDeg, side))
		end
	end
end)

test("FanDirection mirrors z across side, keeping y identical", function()
	for _, spreadDeg in ipairs({ 15, 37, 60 }) do
		local _, yPos, zPos = WingsGeometry.FanDirection(spreadDeg, 1)
		local _, yNeg, zNeg = WingsGeometry.FanDirection(spreadDeg, -1)
		assertNear(yPos, yNeg, EPSILON, "y should match regardless of side")
		assertNear(zPos, -zNeg, EPSILON, "z should mirror across side")
	end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
