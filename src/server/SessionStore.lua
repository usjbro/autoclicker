--!strict
-- Owns `activeSessions` privately. Every other server module must read or
-- write a player's session through one of the accessors below -- none of
-- them ever hand back the table itself, so it's structurally impossible for
-- a future call site to bypass SessionLock and silently reintroduce the race
-- class #17 closed (see SessionLock.lua for the concurrency reasoning this
-- all builds on: SessionLock.Run serializes every operation touching a given
-- player's session through one critical section, and errors loudly rather
-- than deadlocking on a same-stack reentrant call for the same userId -- so
-- nothing below may call another lock-taking SessionStore accessor for the
-- SAME userId from inside its own callback).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local SessionLock = require(script.Parent:WaitForChild("SessionLock"))

local SessionStore = {}

-- Module-private. Never exported, returned, or otherwise handed out by
-- reference -- see the accessors below.
local activeSessions: { [number]: GameLogic.Session } = {}

-- The primary accessor: acquires the per-player lock, looks up the session,
-- and calls fn(session) only if one currently exists. This is what almost
-- every read-modify-write in the codebase should go through -- it replaces
-- GameService.server.lua's old local `withSession` helper, generalized so
-- every module (not just GameService) can use it.
function SessionStore.With(userId: number, fn: (GameLogic.Session) -> ())
	SessionLock.Run(userId, function()
		local session = activeSessions[userId]
		if session then
			fn(session)
		end
	end)
end

-- For PlayerAdded: `loader` is called *inside* the lock and must return the
-- session to install; SessionStore then stores it and, still inside the same
-- critical section, calls `afterInstall(session)` if given. Doing the load
-- itself inside the lock (not just the install) is what guarantees
-- PlayerRemoving can never run in the gap between the load finishing and the
-- session actually being installed -- a fast join-then-leave could otherwise
-- let PlayerRemoving's session-not-found no-op run before this installs one.
function SessionStore.Install(
	userId: number,
	loader: () -> GameLogic.Session,
	afterInstall: ((GameLogic.Session) -> ())?
)
	SessionLock.Run(userId, function()
		local session = loader()
		activeSessions[userId] = session
		if afterInstall then
			afterInstall(session)
		end
	end)
end

-- For PlayerRemoving: acquires the lock, calls `beforeRemove(session)` (e.g.
-- a final DataStore save) if a session exists, then removes it -- all inside
-- one critical section, mirroring the old withSession-then-nil-out pattern
-- GameService used to hand-roll.
function SessionStore.Remove(userId: number, beforeRemove: ((GameLogic.Session) -> ())?)
	SessionLock.Run(userId, function()
		local session = activeSessions[userId]
		if session then
			if beforeRemove then
				beforeRemove(session)
			end
			activeSessions[userId] = nil
		end
	end)
end

-- Unlocked bare read of a single session. Justified ONLY for reads that are
-- not part of a read-modify-write and don't need a multi-field-consistent
-- snapshot -- every write to a session goes through With/Install (both
-- lock-covered), so this can only ever observe a fully-committed session
-- table, never a torn write; it can just be up to one in-flight-operation
-- stale. Current callers:
--   - GameService's syncPlayer: fire-and-forget read right before
--     SyncState:FireClient, called from inside handlers that are already
--     holding the lock for this same userId (so re-locking would deadlock).
--   - LeaderboardManager's totalClicks lookup for an online player: display
--     only.
--   - MovementSystem's CharacterAdded hook: reads speed-preference fields to
--     compute WalkSpeed; doesn't mutate the session, so routing it through
--     With would only add lock contention (e.g. waiting on an in-flight
--     Robux-purchase save) with no correctness benefit.
--   - RobuxPurchaseManager's grant flow: already runs inside its OWN
--     SessionLock.Run(userId, ...) for reasons specific to its receipt-claim
--     bookkeeping (see RobuxPurchaseManager.lua), so calling SessionStore.With
--     there would be a reentrant, deadlocking double-lock; Peek gives it the
--     table access it needs without that.
-- Do NOT use this for anything that reads a value and later writes back
-- based on it.
function SessionStore.Peek(userId: number): GameLogic.Session?
	return activeSessions[userId]
end

-- Snapshot of the currently-active userIds, as a plain array. Used by the
-- idle-gain tick loop, which must snapshot before iterating: pairs() is only
-- guaranteed safe across keys *removed* during iteration, not keys *added*,
-- and the loop body yields (SessionLock.Run can wait on task.wait() when
-- contended).
function SessionStore.UserIds(): { number }
	local userIds = {}
	for userId in pairs(activeSessions) do
		table.insert(userIds, userId)
	end
	return userIds
end

-- Unlocked bulk read, without ever exposing activeSessions itself: invokes
-- fn(userId, session) once per currently-active session. This is the one
-- other unlocked-bare-read case in the codebase (LeaderboardManager's
-- periodic per-player score save) -- already established as safe unlocked
-- per #17's resolution, since nothing in this codebase mutates a session's
-- `score` field across a yield (every multi-step read-modify-write holds
-- SessionLock for its own duration), so a bare read here can't observe a
-- torn write, only a value that's up to one operation stale. `fn` must not
-- yield and must not mutate the session -- it runs synchronously against the
-- live table, not a copy.
function SessionStore.ForEachSession(fn: (userId: number, session: GameLogic.Session) -> ())
	for userId, session in pairs(activeSessions) do
		fn(userId, session)
	end
end

export type SessionStoreModule = typeof(SessionStore)

return SessionStore
