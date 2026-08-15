--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local SpeedCalculator = require(Shared:WaitForChild("SpeedCalculator"))

local MovementSystem = {}

-- Sets the character's actual WalkSpeed from the server-computed effective
-- speed. This is the only place WalkSpeed gets set -- the client only ever
-- sends a preference (see UpdateSpeedSettingsEvent in GameService), never a
-- speed value, so it can't be spoofed into moving faster than allowed.
function MovementSystem.ApplyEffectiveSpeed(player: Player, session: GameLogic.Session)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.WalkSpeed = SpeedCalculator.CalculateEffectiveSpeed(session)
end

-- WalkSpeed doesn't survive a respawn (a fresh Humanoid resets to the Roblox
-- default), so reapply it every time a character is (re)created.
function MovementSystem.Start(getActiveSessions: () -> { [number]: GameLogic.Session })
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local session = getActiveSessions()[player.UserId]
			if session then
				MovementSystem.ApplyEffectiveSpeed(player, session)
			end
		end)
	end)
end

return MovementSystem
