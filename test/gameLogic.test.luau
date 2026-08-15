-- Headless test runner for src/shared/GameLogic.lua, run via: lune run test/gameLogic.test.luau
-- Exercises the pure game-math shared between server validation and client
-- display, without needing a Roblox Studio session.
local process = require("@lune/process")
local GameLogic = require("../src/shared/GameLogic")
local NumberFormat = require("../src/shared/NumberFormat")
local SpeedCalculator = require("../src/shared/SpeedCalculator")

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

local function session(overrides: { [string]: any }?)
	local base = {
		score = 0,
		autoClickerCount = 0,
		megaClickerCount = 0,
		clickPowerCount = 0,
		multiplierCount = 0,
		rebirthCount = 0,
		totalClicks = 0,
		useBaseSpeed = true,
		speedSliderPercent = 100,
	}
	for key, value in pairs(overrides or {}) do
		base[key] = value
	end
	return base
end

print("GameLogic (Lune)")

test("GetDefaultSession returns the documented defaults", function()
	local default = GameLogic.GetDefaultSession()
	for key, value in pairs(session()) do
		assertEqual(default[key], value, "GetDefaultSession()." .. key)
	end
end)

test("ResetProgress zeroes score and upgrades but preserves clicks/rebirths/settings", function()
	local before = session({
		score = 5000,
		autoClickerCount = 3,
		megaClickerCount = 2,
		clickPowerCount = 1,
		multiplierCount = 4,
		rebirthCount = 2,
		totalClicks = 777,
		useBaseSpeed = false,
		speedSliderPercent = 42,
	})
	local after = GameLogic.ResetProgress(before)

	assertEqual(after.score, 0, "score")
	assertEqual(after.autoClickerCount, 0, "autoClickerCount")
	assertEqual(after.megaClickerCount, 0, "megaClickerCount")
	assertEqual(after.clickPowerCount, 0, "clickPowerCount")
	assertEqual(after.multiplierCount, 0, "multiplierCount")
	assertEqual(after.rebirthCount, 2, "rebirthCount preserved")
	assertEqual(after.totalClicks, 777, "totalClicks preserved")
	assertEqual(after.useBaseSpeed, false, "useBaseSpeed preserved")
	assertEqual(after.speedSliderPercent, 42, "speedSliderPercent preserved")
end)

test("PerformRebirth does everything ResetProgress does, plus increments rebirthCount", function()
	local before = session({ score = 20000, autoClickerCount = 5, rebirthCount = 1, totalClicks = 100 })
	local after = GameLogic.PerformRebirth(before)

	assertEqual(after.score, 0, "score")
	assertEqual(after.autoClickerCount, 0, "autoClickerCount")
	assertEqual(after.totalClicks, 100, "totalClicks preserved")
	assertEqual(after.rebirthCount, 2, "rebirthCount incremented")
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

test("CalculateMultiplier adds 25% per rebirth", function()
	assertEqual(GameLogic.CalculateMultiplier(session({ rebirthCount = 2 })), 1.5, "2 rebirths")
end)

test("CalculateMultiplier combines Multiplier upgrades and rebirths", function()
	local result = GameLogic.CalculateMultiplier(session({ multiplierCount = 1, rebirthCount = 1 }))
	assertNear(result, 1.35, 1e-9, "1 multiplier level + 1 rebirth")
end)

test("CanRebirth is false below the threshold", function()
	assertEqual(GameLogic.CanRebirth(session({ score = 9999 })), false, "below threshold")
end)

test("CanRebirth is true at or above the threshold", function()
	assertEqual(GameLogic.CanRebirth(session({ score = 10000 })), true, "at threshold")
	assertEqual(GameLogic.CanRebirth(session({ score = 15000 })), true, "above threshold")
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

-- AutoClicker/MegaClicker Rate constants are per-minute (see GameLogic.lua),
-- so these use a 60-second deltaTime to land on clean expected values.
test("CalculateIdleGain returns 0 with no auto-clickers", function()
	assertEqual(GameLogic.CalculateIdleGain(session(), 10), 0, "idle gain with none owned")
end)

test("CalculateIdleGain scales with base auto-clickers over a minute", function()
	assertEqual(GameLogic.CalculateIdleGain(session({ autoClickerCount = 5 }), 60), 5, "5 auto-clickers over 60s")
end)

test("CalculateIdleGain weights Mega Auto-Clickers 10x a base auto-clicker over a minute", function()
	assertEqual(GameLogic.CalculateIdleGain(session({ megaClickerCount = 1 }), 60), 10, "1 mega auto-clicker over 60s")
end)

test("CalculateIdleGain combines both tiers and applies the multiplier over a minute", function()
	local result = GameLogic.CalculateIdleGain(
		session({ autoClickerCount = 2, megaClickerCount = 1, multiplierCount = 1 }),
		60
	)
	-- (2*1 + 1*10) * 1.1 = 13.2
	assertNear(result, 13.2, 1e-9, "combined idle gain")
end)

print("NumberFormat")

test("Format leaves small numbers as plain integers", function()
	assertEqual(NumberFormat.Format(0), "0", "0")
	assertEqual(NumberFormat.Format(5), "5", "5")
	assertEqual(NumberFormat.Format(999), "999", "999")
end)

test("Format abbreviates thousands/millions/billions per the spec's examples", function()
	assertEqual(NumberFormat.Format(1000), "1K", "1000")
	assertEqual(NumberFormat.Format(10000), "10K", "10000")
	assertEqual(NumberFormat.Format(100000), "100K", "100000")
	assertEqual(NumberFormat.Format(1250), "1.25K", "1250")
	assertEqual(NumberFormat.Format(1000000), "1M", "1000000")
	assertEqual(NumberFormat.Format(1500000), "1.5M", "1500000")
	assertEqual(NumberFormat.Format(1000000000), "1B", "1000000000")
	assertEqual(NumberFormat.Format(2000000000), "2B", "2000000000")
	assertEqual(NumberFormat.Format(1000000000000), "1T", "1000000000000")
end)

test("Format promotes to the K tier when rounding a sub-1000 value up to 1000", function()
	assertEqual(NumberFormat.Format(999.6), "1K", "999.6 rounds up to 1000, should show as 1K not 1000")
	assertEqual(NumberFormat.Format(999.99), "1K", "999.99 rounds up to 1000, should show as 1K not 1000")
	assertEqual(NumberFormat.Format(999.4), "999", "999.4 rounds down, stays under the threshold")
end)

test("Format continues past T with two-letter suffixes", function()
	assertEqual(NumberFormat.Format(1000000000000000), "1aa", "1e15")
end)

test("Format handles negative numbers and non-finite guards", function()
	assertEqual(NumberFormat.Format(-1500), "-1.5K", "negative")
	assertEqual(NumberFormat.Format(0 / 0), "0", "NaN")
	assertEqual(NumberFormat.Format(math.huge), "∞", "infinity")
end)

print("SpeedCalculator")

test("CalculateMaxSpeed equals base speed at 0 clicks", function()
	assertEqual(SpeedCalculator.CalculateMaxSpeed(0), SpeedCalculator.BASE_WALK_SPEED, "0 clicks")
end)

test("CalculateMaxSpeed increases with clicks but caps at a bounded value", function()
	local low = SpeedCalculator.CalculateMaxSpeed(100)
	local high = SpeedCalculator.CalculateMaxSpeed(100000)
	if not (low > SpeedCalculator.BASE_WALK_SPEED and high > low) then
		error("expected max speed to increase with clicks")
	end
	if high > SpeedCalculator.BASE_WALK_SPEED + 200 then
		error("max speed is not bounded -- got " .. tostring(high))
	end
end)

test("CalculateMaxSpeed never goes negative or NaN for invalid input", function()
	assertEqual(SpeedCalculator.CalculateMaxSpeed(-50), SpeedCalculator.BASE_WALK_SPEED, "negative clicks clamps to base")
	assertEqual(SpeedCalculator.CalculateMaxSpeed(0 / 0), SpeedCalculator.BASE_WALK_SPEED, "NaN clicks clamps to base")
end)

test("CalculateEffectiveSpeed returns base speed when useBaseSpeed is true, regardless of clicks/slider", function()
	local speed = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 100000, useBaseSpeed = true, speedSliderPercent = 100 })
	assertEqual(speed, SpeedCalculator.BASE_WALK_SPEED, "base speed override")
end)

test("CalculateEffectiveSpeed interpolates between base and max by the slider percent", function()
	local maxSpeed = SpeedCalculator.CalculateMaxSpeed(2000)
	local atZero = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 2000, useBaseSpeed = false, speedSliderPercent = 0 })
	local atHalf = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 2000, useBaseSpeed = false, speedSliderPercent = 50 })
	local atFull = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 2000, useBaseSpeed = false, speedSliderPercent = 100 })

	assertEqual(atZero, SpeedCalculator.BASE_WALK_SPEED, "0% slider")
	assertNear(atHalf, (SpeedCalculator.BASE_WALK_SPEED + maxSpeed) / 2, 1e-9, "50% slider")
	assertEqual(atFull, maxSpeed, "100% slider")
end)

test("CalculateEffectiveSpeed never exceeds the calculated max speed even with an out-of-range slider", function()
	local maxSpeed = SpeedCalculator.CalculateMaxSpeed(2000)
	local speed = SpeedCalculator.CalculateEffectiveSpeed({ totalClicks = 2000, useBaseSpeed = false, speedSliderPercent = 99999 })
	if speed > maxSpeed then
		error("effective speed exceeded max speed: " .. tostring(speed) .. " > " .. tostring(maxSpeed))
	end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
