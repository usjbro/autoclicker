--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))

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
local getActiveSessionsRef: (() -> {[number]: GameLogic.Session})? = nil

-- totalClicks isn't in the OrderedDataStore (that only sorts by score), so
-- pull it from the live session if the player's online, otherwise fall back
-- to their last save (cached briefly, see above). Never errors -- worst case
-- a leaderboard row shows 0 or a slightly stale value.
local function getTotalClicks(userId: number): number
	if getActiveSessionsRef then
		local session = getActiveSessionsRef()[userId]
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

	task.spawn(function()
		local success, err = pcall(function()
			LeaderboardStore:SetAsync(tostring(player.UserId), integerScore)
		end)

		if not success then
			warn("Failed to save leaderboard score for " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

-- Starts the periodic update loop and registers joining players
function LeaderboardManager.Start(getActiveSessions: () -> {[number]: GameLogic.Session})
	getActiveSessionsRef = getActiveSessions

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
			for userId, session in pairs(getActiveSessions()) do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					LeaderboardManager.SaveScore(player, session.score)
				end
			end

			-- Query and broadcast latest leaderboard standings
			LeaderboardManager.Refresh()
		end
	end)
end

return LeaderboardManager
