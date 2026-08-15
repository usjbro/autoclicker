--!strict
-- A player's session table has multiple independent writers across this
-- codebase (click/purchase/reset/rebirth/speed-setting handlers, the save on
-- disconnect, the Robux grant flow) that can each yield on a DataStore call
-- mid-operation. Without coordination, two of them can interleave on the
-- same table -- e.g. a Reset zeroing fields while a Robux grant's save is
-- still in flight, or a disconnect-triggered save racing a purchase's
-- rollback. SessionLock.Run serializes every session-touching operation for
-- a given player through one critical section, so only one such operation
-- is ever in progress for that player at a time. Different players never
-- block each other.
local SessionLock = {}

local locks: { [number]: boolean } = {}

function SessionLock.Run(userId: number, fn: () -> ())
	while locks[userId] do
		task.wait()
	end
	locks[userId] = true

	local ok, err = pcall(fn)

	locks[userId] = nil

	if not ok then
		error(err, 0)
	end
end

return SessionLock
