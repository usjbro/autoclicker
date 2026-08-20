-- Headless test runner for src/shared/NeonScript.lua, run via:
-- lune run test/neonScript.test.luau
-- Exercises the pure cursive-glyph geometry behind the portal signs'
-- neon-tube lettering, without needing a Roblox Studio session.
local process = require("@lune/process")
local NeonScript = require("../src/shared/NeonScript")

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

local function assertNear(actual: number, expected: number, epsilon: number, message: string?)
	if math.abs(actual - expected) > epsilon then
		error(("%s (expected ~%s, got %s)"):format(message or "values differ", tostring(expected), tostring(actual)))
	end
end

print("NeonScript (Lune)")

test("ArcPoints returns segments+1 points", function()
	local points = NeonScript.ArcPoints(0, 0, 1, 0, 90, 4)
	assertEqual(#points, 5, "point count")
end)

test("ArcPoints starts and ends at the expected coordinates", function()
	local points = NeonScript.ArcPoints(0, 0, 1, 0, 90, 4)
	assertNear(points[1].x, 1, 1e-9, "start x")
	assertNear(points[1].y, 0, 1e-9, "start y")
	assertNear(points[#points].x, 0, 1e-9, "end x")
	assertNear(points[#points].y, 1, 1e-9, "end y")
end)

test("ArcPoints midpoint lands on the circle at the expected angle", function()
	local points = NeonScript.ArcPoints(5, -5, 2, 0, 180, 2)
	-- midpoint (i=1 of 2) is at 90 degrees: (5 + 2*cos(90), -5 + 2*sin(90))
	assertNear(points[2].x, 5, 1e-9, "midpoint x")
	assertNear(points[2].y, -3, 1e-9, "midpoint y")
end)

test("every glyph needed by EASY/MEDIUM/HARD/VERY HARD exists", function()
	for _, letter in ipairs({ "E", "A", "S", "Y", "M", "D", "I", "U", "H", "R", "V" }) do
		local glyph = NeonScript.GLYPHS[letter]
		assertEqual(glyph ~= nil, true, letter .. " glyph exists")
		if glyph then
			assertEqual(#glyph > 0, true, letter .. " glyph has points")
		end
	end
end)

test("WordPath produces one run per space-separated word", function()
	local result = NeonScript.WordPath("HI", 0.1)
	assertEqual(#result.runs, 1, "one run, no space in HI")

	local twoWordResult = NeonScript.WordPath("A I", 0.1)
	assertEqual(#twoWordResult.runs, 2, "two runs, split at the space")
end)

test("WordPath's total width grows with more letters", function()
	local short = NeonScript.WordPath("HI", 0.1)
	local long = NeonScript.WordPath("HIHI", 0.1)
	if long.width <= short.width then
		error(("expected HIHI (%s) to be wider than HI (%s)"):format(long.width, short.width))
	end
end)

test("WordPath is case-insensitive", function()
	local lower = NeonScript.WordPath("hi", 0.1)
	local upper = NeonScript.WordPath("HI", 0.1)
	assertEqual(lower.width, upper.width, "same width regardless of case")
	assertEqual(#lower.runs, #upper.runs, "same run count regardless of case")
end)

test("WordPath skips unknown characters without erroring", function()
	local result = NeonScript.WordPath("H!I", 0.1)
	assertEqual(#result.runs, 1, "unknown char doesn't split into a new run")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
