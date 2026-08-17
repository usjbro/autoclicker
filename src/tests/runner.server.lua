--!strict
local ServerStorage = game:GetService("ServerStorage")

-- Bootstrap TestEZ, vendored under src/Packages/TestEZ (see
-- THIRD_PARTY_NOTICES.md) and synced by Rojo to ServerStorage.TestEZ (not
-- ReplicatedStorage -- it's server-only tooling, no reason to replicate a
-- ~2000-line test framework to every connecting client), so this suite runs
-- on every Studio playtest. The enforced CI surface is still the standalone
-- Lune suite (test/gameLogic.test.luau), which doesn't need Studio at all --
-- this warn/skip path is now just a defensive fallback for a sync that
-- hasn't picked up the Packages folder yet (e.g. a stale Rojo session), not
-- the expected common case, so it warns rather than just prints.
task.defer(function()
	local testEZModule = ServerStorage:FindFirstChild("TestEZ", true)
	if not testEZModule then
		warn("TestEZ not found in ServerStorage -- skipping in-Studio tests (re-sync via `rojo serve`? see test/gameLogic.test.luau for the enforced CI suite).")
		return
	end
	
	local TestEZ = require(testEZModule)
	local results = TestEZ.TestBootstrap:run({script.Parent})
	
	if results.errors and #results.errors > 0 then
		error("Automated tests failed!")
	else
		print("All automated tests passed!")
	end
end)
