--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Bootstrap TestEZ, vendored under src/Packages/TestEZ (see
-- THIRD_PARTY_NOTICES.md) and synced by Rojo to ReplicatedStorage.TestEZ, so
-- this suite runs on every Studio playtest. The enforced CI surface is still
-- the standalone Lune suite (test/gameLogic.test.luau), which doesn't need
-- Studio at all -- this print/skip path is now just a defensive fallback for
-- a sync that hasn't picked up the Packages folder yet (e.g. a stale Rojo
-- session), not the expected common case.
task.defer(function()
	local testEZModule = ReplicatedStorage:FindFirstChild("TestEZ", true)
	if not testEZModule then
		print("TestEZ not found in ReplicatedStorage -- skipping in-Studio tests (re-sync via `rojo serve`? see test/gameLogic.test.luau for the enforced CI suite).")
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
