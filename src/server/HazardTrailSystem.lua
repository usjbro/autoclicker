--!strict
local Players = game:GetService("Players")
local SessionStoreType = require(script.Parent:WaitForChild("SessionStore"))
type SessionStoreModule = SessionStoreType.SessionStoreModule

local HazardTrailSystem = {}

-- FlameTrail/LightTrail (see CosmeticsSystem.lua) are purely decorative --
-- they follow the character and have no gameplay effect. This module adds a
-- separate, independent gameplay layer on top of the same two cosmetics: a
-- physical hazard left behind on the ground while moving, damaging any
-- *other* player who touches it. Deliberately kept out of
-- CosmeticsSystem.lua -- that module is visual-only, this one is
-- damage/Touched-driven, different enough concerns to stay in their own
-- module (mirrors FlightSystem.lua being its own module rather than folded
-- into MovementSystem.lua).
local HAZARD_CHECK_INTERVAL = 0.1 -- seconds between position samples
local HAZARD_MOVE_EPSILON = 0.5 -- studs -- below this, treat as standing still (physics jitter), not real movement
local HAZARD_LIFETIME_SECONDS = 2
local HAZARD_DAMAGE = 10 -- out of Humanoid's own default MaxHealth (100) -- never changed, so this already matches "10 out of 100"
local HAZARD_WIDTH = 4 -- studs, roughly character width
local HAZARD_THICKNESS = 0.3

local HAZARD_COLORS: { [string]: Color3 } = {
	-- Solid mid-tones pulled from CosmeticsSystem.buildTrail's own gradients
	-- (a flat Part.Color can't reproduce a full ColorSequence) so the ground
	-- hazard reads as the same identity as the character-following Trail.
	FlameTrail = Color3.fromHex("ff6b1a"),
	LightTrail = Color3.fromHex("6c5ce7"),
}

-- Per-player in-memory tracking, same shape/justification as FlightSystem's
-- own lastFlightAt -- not session data, doesn't need to persist across a
-- disconnect.
local lastCheckedPosition: { [number]: Vector3 } = {}

-- Builds one thin box spanning p0->p1 -- the same
-- diff/center/CFrame.lookAt(center, center+direction, up) segment-orientation
-- technique MapBuilder.lua's buildNeonTube already uses for its tube
-- segments, reused here (not shared as a common helper -- different modules,
-- different concerns, and it's a handful of lines) so a single hazard part
-- always spans the player's actual full movement since the last tick, never
-- leaving a dodgeable gap at high movement speed.
local function buildHazardSegment(p0: Vector3, p1: Vector3, color: Color3, withFire: boolean): BasePart
	local diff = p1 - p0
	local length = math.max(diff.Magnitude, HAZARD_WIDTH)
	local center = p0 + diff / 2
	local up = Vector3.new(0, 1, 0)
	local direction = if diff.Magnitude > 0.001 then diff.Unit else Vector3.new(1, 0, 0)
	if math.abs(direction:Dot(up)) > 0.999 then
		up = Vector3.new(1, 0, 0)
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(HAZARD_WIDTH, HAZARD_THICKNESS, length)
	part.CFrame = CFrame.lookAt(center, center + direction, up)
	part.Parent = workspace

	if withFire then
		-- Instance.new("Fire") is a stock built-in Roblox effect -- no custom
		-- Texture/Image asset needed, same constraint the client's Unicode
		-- nav-glyphs and CosmeticsSystem's stock Trail/ParticleEmitter
		-- already work within.
		local fire = Instance.new("Fire")
		fire.Size = HAZARD_WIDTH
		fire.Heat = 8
		fire.Parent = part
	end

	return part
end

-- Wires damage: any player other than `ownerId` who touches this part takes
-- HAZARD_DAMAGE, once per part (a lingering player shouldn't take repeated
-- damage from a single part every physics substep). Same
-- Players:GetPlayerFromCharacter-based trust model as GameService.server.
-- lua's wireMazeGoal -- trusts a client-owned-physics Touched event for who's
-- "at" a position, an already-accepted tradeoff in this codebase.
local function wireHazardDamage(part: BasePart, ownerId: number)
	local alreadyHit: { [number]: boolean } = {}
	part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player or player.UserId == ownerId then return end
		if alreadyHit[player.UserId] then return end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		alreadyHit[player.UserId] = true
		humanoid:TakeDamage(HAZARD_DAMAGE)
	end)

	task.delay(HAZARD_LIFETIME_SECONDS, function()
		part:Destroy()
	end)
end

function HazardTrailSystem.Start(sessionStore: SessionStoreModule)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			-- A fresh spawn shouldn't draw a hazard segment back to wherever
			-- the previous character stood (e.g. after dying to a hazard, or
			-- Reset/Rebirth's own respawn) -- the next tick starts fresh once
			-- they actually move.
			lastCheckedPosition[player.UserId] = nil
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(HAZARD_CHECK_INTERVAL)

			-- Snapshot before iterating -- same reasoning as GameService.
			-- server.lua's idle-gain loop: a player joining mid-tick
			-- shouldn't be able to corrupt this traversal.
			local userIds = sessionStore.UserIds()
			for _, userId in ipairs(userIds) do
				-- Each player's tick runs in its own coroutine, same reasoning
				-- as GameService.server.lua's idle-gain loop: an error handling
				-- one player (a future edit, an unexpected Roblox API error)
				-- can't kill this loop for every other online player.
				task.spawn(function()
					local session = sessionStore.Peek(userId)
					if not session or session.equippedCosmetic == "None" then
						-- Not currently wearing a trail -- don't let a stale
						-- position from before unequipping (or from a previous
						-- equip elsewhere on the map) draw a bogus segment
						-- spanning the untracked gap on next equip.
						lastCheckedPosition[userId] = nil
						return
					end

					local player = Players:GetPlayerByUserId(userId)
					local character = player and player.Character
					local rootPart = character and character:FindFirstChild("HumanoidRootPart")

					if rootPart and rootPart:IsA("BasePart") then
						local currentPosition = rootPart.Position
						local lastPosition = lastCheckedPosition[userId]

						if lastPosition and (currentPosition - lastPosition).Magnitude > HAZARD_MOVE_EPSILON then
							local color = HAZARD_COLORS[session.equippedCosmetic] or Color3.new(1, 1, 1)
							local part = buildHazardSegment(lastPosition, currentPosition, color, session.equippedCosmetic == "FlameTrail")
							wireHazardDamage(part, userId)
						end

						lastCheckedPosition[userId] = currentPosition
					end
				end)
			end
		end
	end)
end

return HazardTrailSystem
