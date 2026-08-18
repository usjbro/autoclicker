--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local LeaderboardManager = require(script.Parent:WaitForChild("LeaderboardManager"))
local RobuxPurchaseManager = require(script.Parent:WaitForChild("RobuxPurchaseManager"))
local MovementSystem = require(script.Parent:WaitForChild("MovementSystem"))
local SessionStore = require(script.Parent:WaitForChild("SessionStore"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))

local ClickEvent = ReplicatedStorage:WaitForChild("ClickEvent")
local PurchaseEvent = ReplicatedStorage:WaitForChild("PurchaseEvent")
local ResetEvent = ReplicatedStorage:WaitForChild("ResetEvent")
local RebirthEvent = ReplicatedStorage:WaitForChild("RebirthEvent")
local UpdateSpeedSettingsEvent = ReplicatedStorage:WaitForChild("UpdateSpeedSettingsEvent")
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

-- Explorable map (platforms/ramps/stairs/decoration) for Movement mode --
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
-- on the server, not just itself. Checked (and, on an accepted fire,
-- stamped) before SessionStore.With is even entered, so a flood of
-- rejected fires doesn't also pile up needless lock contention. Shared
-- between the two events since they guard the same underlying resource.
local RESET_REBIRTH_COOLDOWN_SECONDS = 3
local lastResetOrRebirthAt: { [number]: number } = {}
local function isOnResetRebirthCooldown(userId: number): boolean
	local last = lastResetOrRebirthAt[userId]
	return last ~= nil and (os.clock() - last) < RESET_REBIRTH_COOLDOWN_SECONDS
end

-- Copies every field from newValues into session in place, rather than
-- replacing the stored session with a new table outright. Other code (e.g.
-- RobuxPurchaseManager) can hold a reference to a player's session across a
-- yield; replacing the table wholesale would silently orphan that reference
-- from a concurrent Reset/Rebirth.
local function applyInPlace(session: GameLogic.Session, newValues: GameLogic.Session)
	for key, value in pairs(newValues) do
		(session :: any)[key] = value
	end
end

-- Maze completion rewards: wired here, not in MapBuilder.lua (which stays
-- pure geometry -- see its own top-of-file comment), by finding each wing's
-- named goal part under workspace.Map (recursive find -- goal parts live
-- inside each wing's own sub-Folder, not directly under Map) and listening
-- for a player's character to touch it. isCompleted/grant are per-wing
-- closures over one concrete Session field each, rather than a generic loop
-- indexing Session by a dynamic string key from GameConstants.MAZE_GOALS --
-- Session is a fixed-field record type, not an index-signature type, so a
-- dynamic-key lookup wouldn't type-check under --!strict (same reasoning as
-- GameLogic.CalculateMazeBonusRate).
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
	partName: string,
	isCompleted: (GameLogic.Session) -> boolean,
	grant: (GameLogic.Session) -> ()
)
	local goalPart = mapFolder:FindFirstChild(partName, true)
	if not goalPart or not goalPart:IsA("BasePart") then return end

	goalPart.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		SessionStore.With(player.UserId, function(session)
			-- Already granted -- also doubles as the debounce, since Touched
			-- can fire repeatedly while a player stands on the pad; the
			-- second and later fires just no-op here.
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
-- warned above if it didn't, and there's nothing to wire goals to in that
-- case.
if mapOk then
	local mapFolder = workspace:FindFirstChild("Map")
	if mapFolder then
		wireMazeGoal(mapFolder, "MazeNGoal", function(s) return s.completedMazeNorth end, function(s) s.completedMazeNorth = true end)
		wireMazeGoal(mapFolder, "MazeSGoal", function(s) return s.completedMazeSouth end, function(s) s.completedMazeSouth = true end)
		wireMazeGoal(mapFolder, "MazeEGoal", function(s) return s.completedMazeEast end, function(s) s.completedMazeEast = true end)
		wireMazeGoal(mapFolder, "MazeWGoal", function(s) return s.completedMazeWest end, function(s) s.completedMazeWest = true end)
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
	SessionStore.With(player.UserId, function(session)
		lastResetOrRebirthAt[player.UserId] = os.clock()
		-- Captured before ResetProgress zeroes it: only force a leaderboard
		-- write for a player who actually had a nonzero score to wipe.
		-- Otherwise a player who never played (score already 0, no existing
		-- leaderboard entry) would get a spurious "0 score" row on reset --
		-- exactly what SaveScore's own <=0 guard exists to prevent.
		local hadProgress = session.score > 0
		applyInPlace(session, GameLogic.ResetProgress(session))
		if hadProgress then
			-- Force the leaderboard entry to reflect the wipe immediately --
			-- otherwise a stale pre-reset score can linger until the player
			-- earns points again (see issue #13).
			LeaderboardManager.SaveScore(player, session.score, true)
		end
		-- Sync (score/WalkSpeed reset, via syncPlayer) before the durable
		-- save below: DataManager.Save is a direct (non-task.spawn'd) yield
		-- that can take seconds under DataStore write throttling, and unlike
		-- RobuxPurchaseManager's grant flow, nothing here needs to roll back
		-- on a save failure -- so there's no reason to make the player wait
		-- for it before seeing their reset take effect.
		syncPlayer(player)
		-- Save durably right away rather than only relying on the eventual
		-- PlayerRemoving save -- a player who resets and then disconnects
		-- uncleanly (a crashed server, an abrupt Studio Stop) shouldn't get
		-- their old, pre-reset score back on next load. Mirrors the same
		-- "don't depend on a natural disconnect" durability RobuxPurchaseManager
		-- already applies to purchases. DataManager.Save already no-ops if
		-- no DataStore is available, so no separate guard is needed here.
		DataManager.Save(player, session)
	end)
end)

-- [SERVER] Handle Rebirth
RebirthEvent.OnServerEvent:Connect(function(player)
	if isOnResetRebirthCooldown(player.UserId) then return end
	SessionStore.With(player.UserId, function(session)
		if not GameLogic.CanRebirth(session) then return end
		lastResetOrRebirthAt[player.UserId] = os.clock()

		applyInPlace(session, GameLogic.PerformRebirth(session))
		-- Force the leaderboard entry to reflect the wipe immediately --
		-- otherwise a stale pre-rebirth score can linger until the player
		-- earns points again (see issue #13).
		LeaderboardManager.SaveScore(player, session.score, true)
		-- Sync before the durable save -- same reasoning as ResetEvent above.
		syncPlayer(player)
		-- Save durably right away -- same reasoning as ResetEvent above: a
		-- rebirth (and the permanent bonus it grants) shouldn't be lost to
		-- an unclean disconnect before the next natural save.
		DataManager.Save(player, session)
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

print("Autoclicker Server Initialized")
