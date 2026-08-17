--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local SessionStoreType = require(script.Parent:WaitForChild("SessionStore"))
type SessionStoreModule = SessionStoreType.SessionStoreModule

local LeaderboardUpdate = ReplicatedStorage:WaitForChild("LeaderboardUpdate")

-- Fallback safely if DataStoreService cannot load (e.g., API access not enabled in Studio)
local LeaderboardStore = nil
pcall(function()
	LeaderboardStore = DataStoreService:GetOrderedDataStore(GameConstants.LEADERBOARD_KEY)
end)

local LeaderboardManager = {}

export type LeaderboardEntry = {
	userId: number,
	username: string,
	score: number,
	totalClicks: number,
}

local cachedLeaderboard: {LeaderboardEntry} = {}
local usernameCache: {[number]: string} = {}

-- Cached with a TTL rather than indefinitely: a game can run multiple server
-- instances at once, and totalClicks can change on a *different* server the
-- player is active on right now, or after they rejoin *this* server, click
-- more, and leave again -- an indefinite cache would never see that update.
-- The TTL bounds staleness across servers; PlayerAdded below also drops the
-- entry immediately so a local rejoin always gets a fresh read once they
-- leave again.
local OFFLINE_CACHE_TTL_SECONDS = 300
local offlineTotalClicksCache: {[number]: { value: number, cachedAt: number }} = {}
local sessionStoreRef: SessionStoreModule? = nil

-- totalClicks isn't in the OrderedDataStore (that only sorts by score), so
-- pull it from the live session if the player's online, otherwise fall back
-- to their last save (cached briefly, see above). Never errors -- worst case
-- a leaderboard row shows 0 or a slightly stale value.
local function getTotalClicks(userId: number): number
	if sessionStoreRef then
		local session = sessionStoreRef.Peek(userId)
		if session then
			return session.totalClicks
		end
	end

	local cached = offlineTotalClicksCache[userId]
	if cached and (os.time() - cached.cachedAt) < OFFLINE_CACHE_TTL_SECONDS then
		return cached.value
	end

	local saved = DataManager.LoadRaw(userId)
	if saved then
		offlineTotalClicksCache[userId] = { value = saved.totalClicks, cachedAt = os.time() }
		return saved.totalClicks
	end

	-- DataStore failed right now -- an expired-but-present cached value is
	-- still better than showing 0.
	return cached and cached.value or 0
end

-- Helper to retrieve a player's username (with caching to avoid network limit throttling)
local function getUsername(userId: number): string
	if usernameCache[userId] then
		return usernameCache[userId]
	end

	-- Check if player is currently in this server instance
	local activePlayer = Players:GetPlayerByUserId(userId)
	if activePlayer then
		usernameCache[userId] = activePlayer.Name
		return activePlayer.Name
	end

	-- Attempt to fetch name via asynchronous web API
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	if success and name then
		usernameCache[userId] = name
		return name
	else
		return "Player_" .. tostring(userId)
	end
end

-- Refreshes the leaderboard from the OrderedDataStore and broadcasts the new data to all clients
function LeaderboardManager.Refresh(): {LeaderboardEntry}
	if not LeaderboardStore then
		warn("LeaderboardStore is not initialized. Skipping Refresh.")
		return cachedLeaderboard
	end

	local success, pages = pcall(function()
		return LeaderboardStore:GetSortedAsync(false, 10) -- top 10 descending
	end)

	if not success or not pages then
		warn("Failed to retrieve sorted leaderboard data: " .. tostring(pages))
		return cachedLeaderboard
	end

	local page = pages:GetCurrentPage()
	local newList: {LeaderboardEntry} = {}

	for _, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		if userId then
			local username = getUsername(userId)
			table.insert(newList, {
				userId = userId,
				username = username,
				score = tonumber(entry.value) or 0,
				totalClicks = getTotalClicks(userId),
			})
		end
	end

	cachedLeaderboard = newList
	-- Broadcast updated list to all players
	LeaderboardUpdate:FireAllClients(cachedLeaderboard)

	return cachedLeaderboard
end

-- Per-player write serialization for the leaderboard OrderedDataStore. Each
-- SaveScore call used to fire its own independent detached task.spawn'd
-- SetAsync -- that guarantees an attempt, but not completion order. Two
-- concurrent writes for the same player can land in either order depending
-- on network timing, so a later, correct save could be silently overwritten
-- by an earlier, now-stale one (e.g. a pre-Reset periodic-loop save)
-- completing after it (issue #29). At most one SetAsync per player now runs
-- at a time; a SaveScore call that arrives while one is already in flight
-- just updates pendingSave, which the in-flight loop picks up once it's
-- free -- so a given player's writes always apply in the order they were
-- requested, and a burst of rapid calls (e.g. mashing "Reset Progress")
-- coalesces into far fewer actual DataStore writes instead of one SetAsync
-- per call.
-- Like usernameCache/offlineTotalClicksCache above, these are never cleared
-- on PlayerRemoving, so they grow by one entry per lifetime-unique player --
-- accepted for the same reason those are: negligible per-entry cost, and
-- explicit cleanup here would race the final SaveScore call PlayerRemoving
-- itself makes, which can still be in flight after that handler returns.
local saveInFlight: {[number]: boolean} = {}
local pendingSave: {[number]: number} = {}

-- Saves a player's score to the OrderedDataStore. Scores <= 0 are skipped by
-- default so a player who joins and never plays doesn't get a spurious
-- "0 score" entry on the leaderboard. Pass force = true to bypass that guard
-- for a deliberate reset-to-0 write (Reset/Rebirth) -- those callers already
-- have a leaderboard entry from prior play that needs to reflect the wipe
-- immediately, rather than staying stuck at the pre-reset score until the
-- player earns points again.
function LeaderboardManager.SaveScore(player: Player, score: number, force: boolean?)
	if not LeaderboardStore then return end

	local integerScore = math.floor(score)
	if integerScore <= 0 and not force then return end

	local userId = player.UserId
	pendingSave[userId] = integerScore

	if saveInFlight[userId] then
		-- A write is already in progress for this player; it'll pick up this
		-- (or an even newer, if more calls land before it's free) value from
		-- pendingSave once it's done, instead of this call spawning a second
		-- concurrent, unordered write.
		return
	end

	saveInFlight[userId] = true
	task.spawn(function()
		-- The whole loop runs inside one pcall, and saveInFlight is always
		-- cleared right after regardless of outcome -- mirrors SessionLock.Run's
		-- "pcall the critical section, always release after" idiom (see
		-- SessionLock.lua). Without this, any error here that isn't the inner
		-- SetAsync pcall already catches (e.g. from a future edit) would leave
		-- saveInFlight[userId] stuck true forever, silently stranding that
		-- player's leaderboard saves for the rest of the server's uptime, since
		-- every subsequent SaveScore call would just keep updating pendingSave
		-- without ever spawning a new save to consume it.
		local ok, err = pcall(function()
			local nextScore = pendingSave[userId]
			while nextScore do
				pendingSave[userId] = nil

				local success, saveErr = pcall(function()
					LeaderboardStore:SetAsync(tostring(userId), nextScore)
				end)

				if not success then
					warn("Failed to save leaderboard score for " .. player.Name .. ": " .. tostring(saveErr))
				end

				-- Check again after the write completes: a call that landed
				-- while this SetAsync was in flight left a newer value here to
				-- pick up.
				nextScore = pendingSave[userId]
			end
		end)

		saveInFlight[userId] = false

		if not ok then
			warn("Unexpected error in leaderboard save loop for " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

-- Starts the periodic update loop and registers joining players
function LeaderboardManager.Start(sessionStore: SessionStoreModule)
	sessionStoreRef = sessionStore

	-- Send the existing cached leaderboard immediately to any player upon joining
	Players.PlayerAdded:Connect(function(player)
		-- Their totalClicks may change while online; drop any cached offline
		-- value now so the next time they're queried (after they leave again)
		-- getTotalClicks re-fetches instead of returning a stale snapshot.
		offlineTotalClicksCache[player.UserId] = nil

		LeaderboardUpdate:FireClient(player, cachedLeaderboard)
	end)

	-- Initial load delay to let server stabilize
	task.spawn(function()
		task.wait(2)
		LeaderboardManager.Refresh()
	end)

	-- Periodic update loop (refreshes every 60 seconds)
	task.spawn(function()
		while true do
			task.wait(60)

			-- Save scores for all active players. A bare field read here is
			-- always safe unlocked: nothing in this codebase mutates a
			-- session's score field across a yield (every multi-step
			-- read-modify-write, e.g. the Robux grant, holds SessionLock for
			-- its own duration), so this can never observe a torn write. The
			-- actual DataStore write happens inside SaveScore's own detached
			-- task.spawn, which a session lock here wouldn't cover anyway.
			sessionStore.ForEachSession(function(userId, session)
				local player = Players:GetPlayerByUserId(userId)
				if player then
					LeaderboardManager.SaveScore(player, session.score)
				end
			end)

			-- Query and broadcast latest leaderboard standings
			LeaderboardManager.Refresh()
		end
	end)
end

return LeaderboardManager
