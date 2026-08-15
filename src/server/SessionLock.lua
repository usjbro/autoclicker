--!strict
-- A player's session table has multiple independent writers across this
-- codebase (click/purchase/reset/rebirth/speed-setting handlers, the save on
-- disconnect, the periodic leaderboard save, the idle-gain tick, and the
-- Robux grant flow -- including two concurrent Robux purchases for the same
-- player) that can each yield on a DataStore call mid-operation. Without
-- coordination, two of them can interleave on the same table -- e.g. a Reset
-- zeroing fields while a Robux grant's save is still in flight, or a
-- disconnect racing a purchase's rollback, or two purchases racing each
-- other. SessionLock.Run serializes every session-touching operation for a
-- given player through one critical section, so only one such operation is
-- ever in progress for that player at a time. Different players never block
-- each other.
local SessionLock = {}

local locks: { [number]: boolean } = {}
local lockOwner: { [number]: thread } = {}

function SessionLock.Run(userId: number, fn: () -> ())
	-- A same-stack nested call for the same userId would otherwise deadlock
	-- forever (the inner wait can never see the outer lock clear). Detect it
	-- and fail loudly instead of hanging that player's session permanently.
	if locks[userId] and lockOwner[userId] == coroutine.running() then
		error("SessionLock.Run called reentrantly for userId " .. tostring(userId), 0)
	end

	while locks[userId] do
		task.wait()
	end
	locks[userId] = true
	lockOwner[userId] = coroutine.running()

	local ok, err = pcall(fn)

	locks[userId] = nil
	lockOwner[userId] = nil

	if not ok then
		error(err, 0)
	end
end

return SessionLock
