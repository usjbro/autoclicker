--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local GameHandlers = require(Shared:WaitForChild("GameHandlers"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local LeaderboardManager = require(script.Parent:WaitForChild("LeaderboardManager"))
local RobuxPurchaseManager = require(script.Parent:WaitForChild("RobuxPurchaseManager"))
local MovementSystem = require(script.Parent:WaitForChild("MovementSystem"))
local CosmeticsSystem = require(script.Parent:WaitForChild("CosmeticsSystem"))
local WingsVisualSystem = require(script.Parent:WaitForChild("WingsVisualSystem"))
local FlightSystem = require(script.Parent:WaitForChild("FlightSystem"))
local SessionStore = require(script.Parent:WaitForChild("SessionStore"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))

local ClickEvent = ReplicatedStorage:WaitForChild("ClickEvent")
local PurchaseEvent = ReplicatedStorage:WaitForChild("PurchaseEvent")
local ResetEvent = ReplicatedStorage:WaitForChild("ResetEvent")
local RebirthEvent = ReplicatedStorage:WaitForChild("RebirthEvent")
local UpdateSpeedSettingsEvent = ReplicatedStorage:WaitForChild("UpdateSpeedSettingsEvent")
local PurchaseItemEvent = ReplicatedStorage:WaitForChild("PurchaseItemEvent")
local EquipCosmeticEvent = ReplicatedStorage:WaitForChild("EquipCosmeticEvent")
local EquipWingsEvent = ReplicatedStorage:WaitForChild("EquipWingsEvent")
local ActivateFlightEvent = ReplicatedStorage:WaitForChild("ActivateFlightEvent")
local SyncState = ReplicatedStorage:WaitForChild("SyncState")

-- Environment: a large black box encloses the whole play space so the
-- backdrop is solid black instead of Roblox's default sky, with a floor and
-- SpawnLocation inside it for characters to spawn and walk on. Set up before
-- any Player connections below so a joining player can never spawn before
-- the floor exists. Wrapped in pcall so a failure here (e.g. an unsupported
-- property) can never take down the gameplay wiring that follows.
local voidBoxOk, voidBoxErr = pcall(function()
	local voidBox = Instance.new("Part")
	voidBox.Name = "VoidBox"
	voidBox.Size = Vector3.new(4000, 4000, 4000)
	voidBox.CFrame = CFrame.new(0, 0, 0)
	voidBox.Anchored = true
	voidBox.CanCollide = false
	voidBox.CastShadow = false
	voidBox.Material = Enum.Material.SmoothPlastic
	voidBox.Color = Color3.new(0, 0, 0)
	voidBox.Locked = true
	voidBox.Parent = workspace

	local floor = Instance.new("Part")
	floor.Name = "VoidFloor"
	floor.Size = Vector3.new(4000, 4, 4000)
	floor.CFrame = CFrame.new(0, -2, 0)
	floor.Anchored = true
	floor.CanCollide = true
	floor.CastShadow = false
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.new(0, 0, 0)
	floor.Locked = true
	floor.Parent = workspace

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "VoidSpawn"
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.CFrame = CFrame.new(0, 1, 0)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = true
	spawnLocation.CastShadow = false
	spawnLocation.Material = Enum.Material.SmoothPlastic
	spawnLocation.Color = Color3.new(0, 0, 0)
	spawnLocation.Transparency = 1
	spawnLocation.Locked = true
	spawnLocation.Parent = workspace
end)
if not voidBoxOk then
	warn("Failed to create void environment: " .. tostring(voidBoxErr))
end

-- Explorable map (four self-contained maze tiles plus hub decoration) for
-- Movement mode --
-- built right after the void environment succeeds, still before any Player
-- connections below, so a joining player can never spawn before the map
-- exists. A failure here is likewise non-fatal to the rest of the gameplay
-- wiring; see MapBuilder.lua.
local mapOk, mapErr = MapBuilder.Build()
if not mapOk then
	warn("Failed to build map: " .. tostring(mapErr))
end

-- Also reapplies WalkSpeed here (rather than duplicating the same check at
-- every score-mutating call site below) since every one of those sites
-- already calls syncPlayer right after mutating score -- centralizing this
-- makes it structurally impossible for a future handler to forget it, rather
-- than relying on every new score-mutating handler remembering to repeat the
-- same "if not useBaseSpeed" block. Only click/score-based speed mode can
-- actually move the needle here -- in useBaseSpeed mode, CalculateEffectiveSpeed
-- always returns the same constant regardless of score, so this is a no-op
-- there (matches the redundant-replication optimization from issue #9).
local function syncPlayer(player: Player)
	local session = SessionStore.Peek(player.UserId)
	if not session then return end

	if not session.useBaseSpeed then
		MovementSystem.ApplyEffectiveSpeed(player, session)
	end

	SyncState:FireClient(player, session)
end

-- ResetEvent/RebirthEvent both directly call DataManager.Save (a
-- synchronous SetAsync) on every accepted fire, unlike every other handler
-- below -- Roblox's DataStore request budget is shared per server
-- instance, not per player, so a modified client spamming either with no
-- cooldown could exhaust it and degrade save reliability for every player
-- on the server, not just itself. Checked and stamped before
-- SessionStore.With is even entered (not inside its callback, which can
-- yield on lock contention and let two fires race past the check before
-- either stamps), so a flood of fires -- cooldown-rejected or not -- can't
-- pile up lock contention or duplicate DataManager.Save calls. Shared
-- between the two events since they guard the same underlying resource.
local RESET_REBIRTH_COOLDOWN_SECONDS = 3
local lastResetOrRebirthAt: { [number]: number } = {}
local function isOnResetRebirthCooldown(userId: number): boolean
	local last = lastResetOrRebirthAt[userId]
	return last ~= nil and (os.clock() - last) < RESET_REBIRTH_COOLDOWN_SECONDS
end

-- How far above a teleport destination's floor position to land a
-- character -- clears the floor so they don't spawn clipped into it,
-- matching VoidSpawn's own similar clearance for the initial join spawn.
local TELEPORT_HEIGHT_OFFSET = 5

local function teleportCharacterTo(character: Instance, position: Vector3)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then return end
	rootPart.CFrame = CFrame.new(position + Vector3.new(0, TELEPORT_HEIGHT_OFFSET, 0))
end

-- Looked up fresh each call (not cached), matching wireMazeGoal/wirePortal's
-- own tolerance for a missing map -- if VoidSpawn somehow doesn't exist
-- (voidBoxOk was false), falls back to a reasonable default rather than
-- erroring the whole Touched handler.
local function hubSpawnPosition(): Vector3
	local voidSpawn = workspace:FindFirstChild("VoidSpawn")
	if voidSpawn and voidSpawn:IsA("BasePart") then
		return voidSpawn.Position
	end
	return Vector3.new(0, 5, 0)
end

-- Portal-in: finds a wing's named portal pad and its matching spawn marker
-- (both built by MapBuilder.lua -- this file stays the only place that
-- wires actual gameplay behavior onto its pure geometry, same reasoning as
-- wireMazeGoal below) and teleports a toucher's character there. No
-- SessionStore.With needed -- teleporting doesn't mutate session state.
--
-- Same accepted-gap reasoning as wireMazeGoal below: this trusts a physics
-- Touched event with no server-side check on how the toucher got there.
-- The only thing a modified client could gain by exploiting this
-- specifically is a free teleport to a maze's center -- no reward, no
-- score, nothing session-state-changing -- so the risk here is strictly
-- smaller than the goal's.
local function wirePortal(mapFolder: Instance, wingName: string)
	local portalPart = mapFolder:FindFirstChild(wingName .. "Portal", true)
	if not portalPart or not portalPart:IsA("BasePart") then return end
	local spawnMarker = mapFolder:FindFirstChild(wingName .. "Spawn", true)
	if not spawnMarker or not spawnMarker:IsA("BasePart") then return end
	local destination = spawnMarker.Position

	portalPart.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		teleportCharacterTo(character, destination)
	end)
end

-- Maze completion rewards and the maze's exit: wired here, not in
-- MapBuilder.lua (which stays pure geometry -- see its own top-of-file
-- comment), by finding each wing's named goal part under workspace.Map
-- (recursive find -- goal parts live inside each wing's own sub-Folder,
-- not directly under Map) and listening for a player's character to touch
-- it. isCompleted/grant are per-wing closures over one concrete Session
-- field each, rather than a generic loop indexing Session by a dynamic
-- string key from GameConstants.MAZE_GOALS -- Session is a fixed-field
-- record type, not an index-signature type, so a dynamic-key lookup
-- wouldn't type-check under --!strict (same reasoning as
-- GameLogic.CalculateMazeBonusRate).
--
-- The goal is now both the once-per-run reward trigger AND the always-
-- available exit (issue #60) -- touching it teleports back to the hub on
-- EVERY touch, unconditionally, even after the reward's already been
-- claimed on an earlier visit, since a player revisiting an
-- already-completed maze still needs a way out. The teleport fires first,
-- before the (possibly slower, DataStore-touching) reward grant below --
-- same "don't make the player wait" reasoning ResetEvent/RebirthEvent
-- already use for syncing before their own durable save.
--
-- Known accepted gap: unlike every RemoteEvent handler above, this trusts a
-- physics Touched event with no server-side check on how the toucher got
-- there. Characters are client-owned for network physics by default, so a
-- modified client could in principle move its own character to overlap a
-- distant goal part without walking the maze, granting that wing's reward
-- (up to West's 100,000/min) for free -- the same class of risk this
-- codebase's roblox-security-review skill flags for every other player-
-- reachable trigger. Full mitigation (server-side path verification) is out
-- of proportion for a hobby project; noted here so it's a deliberate
-- tradeoff, not an oversight, if this ever needs revisiting.
local function wireMazeGoal(
	mapFolder: Instance,
	wingName: string,
	isCompleted: (GameLogic.Session) -> boolean,
	grant: (GameLogic.Session) -> ()
)
	local goalPart = mapFolder:FindFirstChild(wingName .. "Goal", true)
	if not goalPart or not goalPart:IsA("BasePart") then return end

	goalPart.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		teleportCharacterTo(character, hubSpawnPosition())

		SessionStore.With(player.UserId, function(session)
			-- Already granted -- also doubles as the debounce, since Touched
			-- can fire repeatedly while a player stands on the pad; the
			-- second and later fires just no-op here (the teleport above
			-- still fires every time, unconditionally).
			if isCompleted(session) then return end
			grant(session)
			syncPlayer(player)
			-- Durable immediately, same reasoning as Reset/Rebirth: a rare,
			-- valuable, hard-won grant shouldn't be lost to an unclean
			-- disconnect before the next natural save.
			DataManager.Save(player, session)
		end)
	end)
end

-- Only attempted if the map actually built -- MapBuilder.Build() already
-- warned above if it didn't, and there's nothing to wire portals/goals to
-- in that case.
if mapOk then
	local mapFolder = workspace:FindFirstChild("Map")
	if mapFolder then
		wirePortal(mapFolder, "MazeN")
		wirePortal(mapFolder, "MazeE")
		wirePortal(mapFolder, "MazeS")
		wirePortal(mapFolder, "MazeW")
		wireMazeGoal(mapFolder, "MazeN", function(s) return s.completedMazeNorth end, function(s) s.completedMazeNorth = true end)
		wireMazeGoal(mapFolder, "MazeS", function(s) return s.completedMazeSouth end, function(s) s.completedMazeSouth = true end)
		wireMazeGoal(mapFolder, "MazeE", function(s) return s.completedMazeEast end, function(s) s.completedMazeEast = true end)
		wireMazeGoal(mapFolder, "MazeW", function(s) return s.completedMazeWest end, function(s) s.completedMazeWest = true end)
	end
end

-- Every handler below that touches a player's session goes through
-- SessionStore (which itself routes through SessionLock), since several of
-- these can yield on a DataStore call mid-operation (Save, in particular) --
-- without this, e.g. a Reset could zero a session's fields while
-- PlayerRemoving's save for that same player is still in flight, or a
-- disconnect could race a purchase. This must cover every reader/writer of
-- session state, not just the RemoteEvent handlers -- the idle-gain tick
-- loop and PlayerAdded/PlayerRemoving below go through SessionStore too, and
-- activeSessions itself is now private to SessionStore.lua so nothing here
-- can touch it directly even by accident.

-- [SERVER] Handle Click
ClickEvent.OnServerEvent:Connect(function(player)
	SessionStore.With(player.UserId, function(session)
		session.score += GameLogic.CalculateClickGain(session)
		session.totalClicks += 1
		syncPlayer(player)
	end)
end)

-- [SERVER] Handle Purchase
PurchaseEvent.OnServerEvent:Connect(function(player, upgradeId)
	SessionStore.With(player.UserId, function(session)
		if typeof(upgradeId) ~= "string" then return end
		local field = GameConstants.UPGRADE_FIELDS[upgradeId]
		if not field then return end

		local cost = GameLogic.GetUpgradeCost(upgradeId)
		if session.score >= cost then
			session.score -= cost
			session[field] += 1
			syncPlayer(player)
		end
	end)
end)

-- [SERVER] Handle Reset
ResetEvent.OnServerEvent:Connect(function(player)
	if isOnResetRebirthCooldown(player.UserId) then return end
	-- Stamped here, before SessionStore.With can yield waiting on the
	-- per-user lock, not inside the callback -- otherwise two fires that
	-- both pass the cooldown check while queued behind a contended lock
	-- (e.g. this player's own concurrent ClickEvent) would both go on to
	-- run the callback and both hit DataManager.Save below, defeating the
	-- cooldown entirely.
	lastResetOrRebirthAt[player.UserId] = os.clock()
	SessionStore.With(player.UserId, function(session)
		-- Orchestration (force the leaderboard write only if the player had
		-- progress worth wiping, then sync, then durably save) lives in
		-- GameHandlers.HandleReset, unit-tested headlessly under Lune
		-- (test/gameHandlers.test.luau) with fake deps -- this closure only
		-- wires each dep to this file's real Roblox-side calls. Sync
		-- (score/WalkSpeed reset, via syncPlayer) before the durable save:
		-- DataManager.Save is a direct (non-task.spawn'd) yield that can
		-- take seconds under DataStore write throttling, and unlike
		-- RobuxPurchaseManager's grant flow, nothing here needs to roll back
		-- on a save failure -- so there's no reason to make the player wait
		-- for it before seeing their reset take effect. Save durably right
		-- away rather than only relying on the eventual PlayerRemoving save
		-- -- a player who resets and then disconnects uncleanly (a crashed
		-- server, an abrupt Studio Stop) shouldn't get their old, pre-reset
		-- score back on next load.
		GameHandlers.HandleReset(session, {
			saveScore = function(s, force)
				-- Otherwise a stale pre-reset score can linger until the
				-- player earns points again (see issue #13).
				LeaderboardManager.SaveScore(player, s.score, force)
			end,
			sync = function()
				syncPlayer(player)
			end,
			saveSession = function(s)
				DataManager.Save(player, s)
			end,
		})
	end)
end)

-- [SERVER] Handle Rebirth
RebirthEvent.OnServerEvent:Connect(function(player)
	if isOnResetRebirthCooldown(player.UserId) then return end
	-- Stamped before SessionStore.With, same reasoning as ResetEvent above --
	-- covers a CanRebirth-rejected fire too, which is fine: the cooldown is
	-- guarding against lock contention and DataStore-budget spam, not
	-- specifically successful rebirths.
	lastResetOrRebirthAt[player.UserId] = os.clock()
	SessionStore.With(player.UserId, function(session)
		-- Same GameHandlers-based orchestration as ResetEvent above (see
		-- GameHandlers.HandleRebirth and its own Lune tests), plus
		-- reapplying the (now-cleared) cosmetic to the live character --
		-- PerformRebirth clears owned items/equippedCosmetic in session
		-- data, but that alone doesn't touch whatever Trail/ParticleEmitter
		-- is already live on this player's currently-spawned character;
		-- without this, a player who rebirths while a cosmetic is equipped
		-- would keep visibly trailing it until their next respawn, even
		-- though the server-authoritative session (and the Shop UI, via
		-- syncPlayer) already say it's gone.
		GameHandlers.HandleRebirth(session, {
			applyCosmetic = function(s)
				CosmeticsSystem.ApplyEquippedCosmetic(player, s)
			end,
			saveScore = function(s, force)
				-- Otherwise a stale pre-rebirth score can linger until the
				-- player earns points again (see issue #13).
				LeaderboardManager.SaveScore(player, s.score, force)
			end,
			sync = function()
				syncPlayer(player)
			end,
			saveSession = function(s)
				DataManager.Save(player, s)
			end,
		})
	end)
end)

-- [SERVER] Handle speed preference changes. The client only ever sends a
-- preference (base speed on/off, slider percent) -- the actual WalkSpeed is
-- always recomputed server-side via MovementSystem, never taken from the client.
UpdateSpeedSettingsEvent.OnServerEvent:Connect(function(player, useBaseSpeed, speedSliderPercent)
	SessionStore.With(player.UserId, function(session)
		if typeof(useBaseSpeed) == "boolean" then
			session.useBaseSpeed = useBaseSpeed
		end

		if typeof(speedSliderPercent) == "number" and speedSliderPercent == speedSliderPercent then
			session.speedSliderPercent = math.clamp(speedSliderPercent, 0, 100)
		end

		MovementSystem.ApplyEffectiveSpeed(player, session)
		syncPlayer(player)
	end)
end)

-- [SERVER] Handle one-time item purchases (Wings, cosmetic trails) -- a
-- no-op if already owned or unaffordable, distinct from PurchaseEvent above
-- (which increments a stacking count): this sets a boolean flag exactly
-- once. FlameTrail/LightTrail don't auto-equip on purchase (a player may own
-- both and want to keep their current pick) -- see EquipCosmeticEvent below.
PurchaseItemEvent.OnServerEvent:Connect(function(player, itemId)
	SessionStore.With(player.UserId, function(session)
		if typeof(itemId) ~= "string" then return end
		local field = GameConstants.ITEM_FIELDS[itemId]
		if not field then return end
		if session[field] then return end -- already owned

		local item = GameConstants.ITEMS[itemId]
		if not item then return end
		if session.score >= item.Cost then
			session.score -= item.Cost
			session[field] = true
			syncPlayer(player)
		end
	end)
end)

-- [SERVER] Handle switching which cosmetic trail (if any) is equipped.
-- Explicit per-value branches (not a generic loop indexing Session by a
-- dynamic field name) so each assigns a literal "None"/"FlameTrail"/
-- "LightTrail" into equippedCosmetic's typed union -- a validated-at-runtime
-- string variable wouldn't type-check being assigned there directly under
-- --!strict.
EquipCosmeticEvent.OnServerEvent:Connect(function(player, cosmeticId)
	SessionStore.With(player.UserId, function(session)
		-- Already equipped -- also doubles as this handler's debounce (same
		-- idiom as PurchaseItemEvent's "already owned" guard and
		-- wireMazeGoal's "already granted" check above): without it, a
		-- modified client repeatedly firing the same cosmeticId re-runs
		-- CosmeticsSystem.ApplyEquippedCosmetic's full Instance.new/Destroy
		-- churn (up to 4 instances) plus a whole-session SyncState broadcast
		-- on every single fire, unlike every other handler in this file,
		-- which only does real work once per state change.
		if cosmeticId == session.equippedCosmetic then return end

		if cosmeticId == "None" then
			session.equippedCosmetic = "None"
		elseif cosmeticId == "FlameTrail" and session.ownedFlameTrail then
			session.equippedCosmetic = "FlameTrail"
		elseif cosmeticId == "LightTrail" and session.ownedLightTrail then
			session.equippedCosmetic = "LightTrail"
		else
			return
		end

		CosmeticsSystem.ApplyEquippedCosmetic(player, session)
		syncPlayer(player)
	end)
end)

-- [SERVER] Handle switching which Wings style (if any) is equipped.
-- Explicit per-value branches (not a generic loop indexing Session by a
-- dynamic field name), same reasoning as EquipCosmeticEvent above --
-- Session is a fixed-field record type under --!strict. Each branch checks
-- ownership of that specific style before allowing the switch.
EquipWingsEvent.OnServerEvent:Connect(function(player, wingsId)
	SessionStore.With(player.UserId, function(session)
		-- Already equipped -- also this handler's debounce, same idiom as
		-- EquipCosmeticEvent's own "already equipped" guard.
		if wingsId == session.equippedWings then return end

		if wingsId == "None" then
			session.equippedWings = "None"
		elseif wingsId == "Classic" and session.ownedWings then
			session.equippedWings = "Classic"
		elseif wingsId == "Voidtech" and session.ownedWingsVoidtech then
			session.equippedWings = "Voidtech"
		elseif wingsId == "Dragon" and session.ownedWingsDragon then
			session.equippedWings = "Dragon"
		elseif wingsId == "Demonic" and session.ownedWingsDemonic then
			session.equippedWings = "Demonic"
		elseif wingsId == "Fae" and session.ownedWingsFae then
			session.equippedWings = "Fae"
		else
			return
		end

		WingsVisualSystem.ApplyEquippedWings(player, session)
		syncPlayer(player)
	end)
end)

-- [SERVER] Handle a flight-burst request. No arguments -- the client only
-- ever asks to fly; FlightSystem.TryActivate is solely responsible for
-- whether that's allowed (Wings ownership, cooldown) and what the burst
-- actually does (duration/speed/direction), the same trust boundary as
-- every other handler above. Nothing in the synced session changes on a
-- successful activation, so no syncPlayer call is needed here.
ActivateFlightEvent.OnServerEvent:Connect(function(player)
	SessionStore.With(player.UserId, function(session)
		FlightSystem.TryActivate(player, session)
	end)
end)

-- Player Lifecycle
Players.PlayerAdded:Connect(function(player)
	-- DataManager.Load happens inside the lock (unlike every other handler,
	-- which only looks up an already-present session) so a fast join-then-
	-- leave can't let PlayerRemoving's no-op (session not installed yet) run
	-- before this installs one -- PlayerRemoving would otherwise be forced to
	-- wait for this whole critical section to finish first either way, but
	-- doing the load itself inside the lock is what guarantees PlayerRemoving
	-- can never run *between* the load finishing and the session being
	-- installed.
	SessionStore.Install(player.UserId, function()
		return DataManager.Load(player)
	end, function(data)
		-- Covers the case where the character already spawned (default
		-- WalkSpeed) before DataManager.Load finished; MovementSystem.Start's
		-- CharacterAdded hook covers every subsequent (re)spawn. Deliberately
		-- kept unconditional (unlike the other handlers' now-centralized,
		-- useBaseSpeed-gated reapply inside syncPlayer below) -- if
		-- CharacterAdded fired before the session existed, its own hook
		-- silently no-ops, so this is the only thing that can correct
		-- WalkSpeed for a useBaseSpeed=true joiner who hits that race. The
		-- overlap with syncPlayer's reapply for a useBaseSpeed=false joiner
		-- is a harmless one-time redundant write on join, not a hot-path
		-- concern worth restructuring around.
		MovementSystem.ApplyEffectiveSpeed(player, data)
		syncPlayer(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	SessionStore.Remove(player.UserId, function(session)
		DataManager.Save(player, session)
		LeaderboardManager.SaveScore(player, session.score)
	end)
	-- lastResetOrRebirthAt is keyed by UserId outside SessionStore, so it
	-- needs its own cleanup here -- otherwise every distinct player who ever
	-- fires Reset/Rebirth leaves a permanent entry for the life of the
	-- server process.
	lastResetOrRebirthAt[player.UserId] = nil
end)

-- Game Loop (Auto-clickers)
task.spawn(function()
	while true do
		local deltaTime = task.wait(GameConstants.TICK_RATE)

		-- Snapshot the current userIds before looping: SessionStore.With below
		-- can yield (SessionLock.Run waits on task.wait() if contended), and
		-- Lua only guarantees pairs() stays valid across removed keys during
		-- iteration, not added ones -- a player joining mid-tick would
		-- otherwise be able to corrupt this traversal.
		local userIds = SessionStore.UserIds()

		for _, userId in ipairs(userIds) do
			-- Each player's tick runs in its own coroutine so one player's
			-- contended lock (e.g. mid Robux-purchase save) can't stall idle
			-- gain for every other online player this tick.
			task.spawn(function()
				SessionStore.With(userId, function(session)
					if session.autoClickerCount <= 0 and session.megaClickerCount <= 0 then return end

					-- Credit the session unconditionally (matches the
					-- pre-lock behavior) even if the Player object briefly
					-- doesn't resolve; only the client sync needs a player.
					session.score += GameLogic.CalculateIdleGain(session, deltaTime)
					local player = Players:GetPlayerByUserId(userId)
					if player then
						syncPlayer(player)
					end
				end)
			end)
		end
	end
end)

-- Start Global Leaderboard Manager
LeaderboardManager.Start(SessionStore)

-- Start Robux Purchase Manager
RobuxPurchaseManager.Start(SessionStore, syncPlayer)

-- Start Movement System (re-applies WalkSpeed on every character (re)spawn)
MovementSystem.Start(SessionStore)

-- Start Cosmetics System (re-applies the equipped trail on every character (re)spawn)
CosmeticsSystem.Start(SessionStore)

-- Start Wings Visual System (re-applies the equipped wings on every character (re)spawn)
WingsVisualSystem.Start(SessionStore)

print("Autoclicker Server Initialized")
