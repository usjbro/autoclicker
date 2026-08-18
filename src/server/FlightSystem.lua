--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameLogic = require(Shared:WaitForChild("GameLogic"))

local FlightSystem = {}

-- Starting values -- easy to retune. Duration/cooldown deliberately short
-- ("fly for short distances", not persistent free-flight); speed chosen to
-- clearly outpace SpeedCalculator's own capped max walk speed so a burst
-- reads as a distinct ability, not just a faster walk.
local FLIGHT_DURATION_SECONDS = 3
local FLIGHT_COOLDOWN_SECONDS = 8
local FLIGHT_FORWARD_SPEED = 60
local FLIGHT_UPWARD_SPEED = 20

-- Per-player cooldown timestamps. Module-private, in-memory, not session
-- data -- doesn't need to persist across a disconnect (same reasoning as
-- LeaderboardManager's own usernameCache/offlineTotalClicksCache: never
-- cleared on PlayerRemoving, grows by one entry per lifetime-unique player,
-- accepted as negligible per-entry cost).
local lastFlightAt: { [number]: number } = {}

-- Attempts to activate a flight burst for player, given their (already
-- session-locked, via SessionStore.With in GameService.server.lua) session.
-- Returns whether it actually activated -- false if they don't own Wings or
-- the cooldown hasn't elapsed, in which case this silently no-ops (matches
-- this codebase's existing pattern for other invalid actions, e.g. an
-- unaffordable purchase). Client never reports a duration/velocity/position
-- -- it only asks to fly; everything about the effect is computed here.
function FlightSystem.TryActivate(player: Player, session: GameLogic.Session): boolean
	if not session.ownedWings then return false end

	local now = os.clock()
	local last = lastFlightAt[player.UserId]
	if last and now - last < FLIGHT_COOLDOWN_SECONDS then
		return false
	end

	local character = player.Character
	if not character then return false end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	lastFlightAt[player.UserId] = now

	-- Forward (the character's current facing) plus a fixed upward bias, so
	-- a burst always gains height rather than being purely horizontal, or
	-- (if the player happened to be looking down) driving them into the
	-- ground.
	local direction = rootPart.CFrame.LookVector * FLIGHT_FORWARD_SPEED + Vector3.new(0, FLIGHT_UPWARD_SPEED, 0)

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = rootPart

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "FlightVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = direction
	linearVelocity.Parent = rootPart

	task.delay(FLIGHT_DURATION_SECONDS, function()
		linearVelocity:Destroy()
		attachment:Destroy()
	end)

	return true
end

return FlightSystem
