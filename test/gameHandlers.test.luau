-- Headless test runner for src/shared/GameHandlers.lua, run via:
-- lune run test/gameHandlers.test.luau
-- Exercises the Reset/Rebirth handler *orchestration* -- which side effects
-- fire, in which order, under which conditions -- with fake dependencies,
-- without needing a Roblox Studio session. This is exactly the class of
-- thing the test-automation plan's Tier 3 called out as previously
-- untestable except by a human clicking Reset/Rebirth in Studio: "does
-- ResetEvent's handler actually force-save the leaderboard when
-- hadProgress is true".
local process = require("@lune/process")
local GameHandlers = require("../src/shared/GameHandlers")

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
		ownedWings = false,
		ownedFlameTrail = false,
		ownedLightTrail = false,
		equippedCosmetic = "None",
		completedMazeNorth = false,
		completedMazeSouth = false,
		completedMazeEast = false,
		completedMazeWest = false,
	}
	for key, value in pairs(overrides or {}) do
		base[key] = value
	end
	return base
end

-- Records every call each dep function receives, so a test can assert both
-- "did this fire" and "what was it called with" without a real mocking
-- library.
local function spyDeps()
	local calls = {
		saveScore = {},
		sync = 0,
		saveSession = 0,
		applyCosmetic = 0,
	}
	local deps = {
		saveScore = function(s, force)
			table.insert(calls.saveScore, { score = s.score, force = force })
		end,
		sync = function()
			calls.sync += 1
		end,
		saveSession = function()
			calls.saveSession += 1
		end,
		applyCosmetic = function()
			calls.applyCosmetic += 1
		end,
	}
	return deps, calls
end

print("GameHandlers (Lune)")

test("HandleReset force-saves the leaderboard when the player had progress", function()
	local s = session({ score = 500 })
	local deps, calls = spyDeps()

	GameHandlers.HandleReset(s, deps)

	assertEqual(s.score, 0, "score reset")
	assertEqual(#calls.saveScore, 1, "saveScore called exactly once")
	assertEqual(calls.saveScore[1].force, true, "forced")
	assertEqual(calls.sync, 1, "synced once")
	assertEqual(calls.saveSession, 1, "saved durably once")
end)

test("HandleReset skips the leaderboard write when the player had no progress", function()
	local s = session({ score = 0 })
	local deps, calls = spyDeps()

	GameHandlers.HandleReset(s, deps)

	assertEqual(#calls.saveScore, 0, "saveScore not called")
	assertEqual(calls.sync, 1, "still synced")
	assertEqual(calls.saveSession, 1, "still saved durably")
end)

test("HandleReset preserves totalClicks/rebirthCount/items, matching GameLogic.ResetProgress", function()
	local s = session({ score = 100, totalClicks = 42, rebirthCount = 3, ownedWings = true })
	local deps = (spyDeps())

	GameHandlers.HandleReset(s, deps)

	assertEqual(s.totalClicks, 42, "totalClicks preserved")
	assertEqual(s.rebirthCount, 3, "rebirthCount preserved")
	assertEqual(s.ownedWings, true, "items preserved on an ordinary Reset")
end)

test("HandleRebirth no-ops below the rebirth threshold", function()
	local s = session({ score = 5000 })
	local deps, calls = spyDeps()

	local happened = GameHandlers.HandleRebirth(s, deps)

	assertEqual(happened, false, "did not rebirth")
	assertEqual(s.score, 5000, "session untouched")
	assertEqual(#calls.saveScore, 0, "no leaderboard write")
	assertEqual(calls.sync, 0, "no sync")
	assertEqual(calls.saveSession, 0, "no durable save")
	assertEqual(calls.applyCosmetic, 0, "no cosmetic reapply")
end)

test("HandleRebirth applies cosmetics, force-saves, syncs, and saves when eligible", function()
	local s = session({ score = 20000, rebirthCount = 0, ownedWings = true, equippedCosmetic = "FlameTrail" })
	local deps, calls = spyDeps()

	local happened = GameHandlers.HandleRebirth(s, deps)

	assertEqual(happened, true, "rebirthed")
	assertEqual(s.score, 0, "score reset")
	assertEqual(s.rebirthCount, 1, "rebirthCount incremented")
	assertEqual(s.ownedWings, false, "items cleared on Rebirth, unlike an ordinary Reset")
	assertEqual(s.equippedCosmetic, "None", "equippedCosmetic cleared")
	assertEqual(calls.applyCosmetic, 1, "cosmetic reapplied to the live character")
	assertEqual(#calls.saveScore, 1, "saveScore called exactly once")
	assertEqual(calls.saveScore[1].force, true, "forced -- a rebirth always wipes score")
	assertEqual(calls.sync, 1, "synced once")
	assertEqual(calls.saveSession, 1, "saved durably once")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
