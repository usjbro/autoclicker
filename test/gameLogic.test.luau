-- Headless test runner for src/shared/GameLogic.lua, run via: lune run test/gameLogic.test.luau
-- Exercises the pure game-math shared between server validation and client
-- display, without needing a Roblox Studio session.
local process = require("@lune/process")
local GameLogic = require("../src/shared/GameLogic")

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

local function session(overrides: { [string]: number }?)
	local base = {
		score = 0,
		autoClickerCount = 0,
		megaClickerCount = 0,
		clickPowerCount = 0,
		multiplierCount = 0,
	}
	for key, value in pairs(overrides or {}) do
		base[key] = value
	end
	return base
end

print("GameLogic (Lune)")

test("GetDefaultSession returns every field zeroed", function()
	local default = GameLogic.GetDefaultSession()
	for key, value in pairs(session()) do
		assertEqual(default[key], value, "GetDefaultSession()." .. key)
	end
end)

test("GetUpgradeCost returns the flat cost for each upgrade", function()
	assertEqual(GameLogic.GetUpgradeCost("AutoClicker"), 10, "AutoClicker cost")
	assertEqual(GameLogic.GetUpgradeCost("MegaClicker"), 150, "MegaClicker cost")
	assertEqual(GameLogic.GetUpgradeCost("ClickPower"), 25, "ClickPower cost")
	assertEqual(GameLogic.GetUpgradeCost("Multiplier"), 500, "Multiplier cost")
end)

test("GetUpgradeCost errors for an unknown upgrade id", function()
	local ok = pcall(function()
		GameLogic.GetUpgradeCost("NotAnUpgrade")
	end)
	assertEqual(ok, false, "GetUpgradeCost should throw for an unknown id")
end)

test("CalculateMultiplier is 1 with no Multiplier upgrades", function()
	assertEqual(GameLogic.CalculateMultiplier(session()), 1, "base multiplier")
end)

test("CalculateMultiplier adds 10% per Multiplier level", function()
	assertEqual(GameLogic.CalculateMultiplier(session({ multiplierCount = 3 })), 1.3, "3 multiplier levels")
end)

test("CalculateClickGain returns 1 with no Click Power upgrades", function()
	assertEqual(GameLogic.CalculateClickGain(session()), 1, "base click gain")
end)

test("CalculateClickGain scales with Click Power levels", function()
	assertEqual(GameLogic.CalculateClickGain(session({ clickPowerCount = 4 })), 5, "4 click power levels")
end)

test("CalculateClickGain applies the multiplier on top of Click Power", function()
	local result = GameLogic.CalculateClickGain(session({ clickPowerCount = 4, multiplierCount = 1 }))
	assertNear(result, 5.5, 1e-9, "click gain with multiplier")
end)

test("CalculateIdleGain returns 0 with no auto-clickers", function()
	assertEqual(GameLogic.CalculateIdleGain(session(), 10), 0, "idle gain with none owned")
end)

test("CalculateIdleGain scales with base auto-clickers over time", function()
	assertEqual(GameLogic.CalculateIdleGain(session({ autoClickerCount = 5 }), 10), 50, "5 auto-clickers over 10s")
end)

test("CalculateIdleGain weights Mega Auto-Clickers 10x a base auto-clicker", function()
	assertEqual(GameLogic.CalculateIdleGain(session({ megaClickerCount = 1 }), 1), 10, "1 mega auto-clicker over 1s")
end)

test("CalculateIdleGain combines both tiers and applies the multiplier", function()
	local result = GameLogic.CalculateIdleGain(
		session({ autoClickerCount = 2, megaClickerCount = 1, multiplierCount = 1 }),
		1
	)
	-- (2*1 + 1*10) * 1.1 = 13.2
	assertNear(result, 13.2, 1e-9, "combined idle gain")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
