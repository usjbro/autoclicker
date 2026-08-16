--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Bootstrap TestEZ if it exists in the environment. TestEZ isn't vendored in
-- this repo (the enforced test surface is the standalone Lune suite --
-- test/gameLogic.test.luau -- which runs in CI without Studio), so this is
-- expected to skip in the common case; print rather than warn so it doesn't
-- read as an error in the output log.
task.defer(function()
	local testEZModule = ReplicatedStorage:FindFirstChild("TestEZ", true)
	if not testEZModule then
		print("TestEZ not found in ReplicatedStorage -- skipping optional in-Studio tests (expected; see test/gameLogic.test.luau for the enforced suite).")
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
