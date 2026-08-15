--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Bootstrap TestEZ if it exists in the environment
task.defer(function()
	local testEZModule = ReplicatedStorage:FindFirstChild("TestEZ", true)
	if not testEZModule then
		warn("TestEZ not found in ReplicatedStorage. Skipping tests.")
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
