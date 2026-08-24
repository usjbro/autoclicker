--!strict
-- Reset/Rebirth orchestration extracted from GameService.server.lua's
-- ResetEvent/RebirthEvent handlers (Tier 3 of the test-automation plan) so
-- the *sequencing* of their side effects -- which of them fire, in which
-- order, under which conditions -- is directly unit-testable under Lune
-- (test/gameHandlers.test.luau) with fake dependencies, instead of only
-- ever exercisable by a human clicking Reset/Rebirth in Studio. Every real
-- side effect (DataStore saves, the leaderboard write, syncing the client,
-- reapplying a live cosmetic) is injected via the Deps tables below rather
-- than called directly, so this module itself never touches Instance/game
-- and needs no Roblox engine to run -- same "if script then ... else ...
-- end" Lune/Rojo dual-load pattern as GameLogic.lua/MazeGeometry.lua.
local GameLogic
if script then
	GameLogic = require(script.Parent.GameLogic)
else
	GameLogic = require("./GameLogic")
end

-- Deliberately duplicated from GameLogic.lua's own `export type Session`,
-- not imported from it: luau-lsp can't carry an exported type through
-- GameLogic's multi-branch require assignment above (its inferred type
-- collapses to `any`, and `any.Session` isn't a valid type reference) --
-- tried a `::` cast and a dead-code single-require alias first, neither
-- got luau-lsp to resolve it either. Safe to duplicate: if this ever drifts
-- out of sync with GameLogic.lua's real Session, the very next line below
-- (passing a session into GameLogic.ResetProgress/PerformRebirth/
-- CanRebirth, which take the *real* Session) fails to type-check -- caught
-- by the same `luau-lsp analyze` CI gate on every PR, not a silent risk.
type Session = {
	score: number,
	autoClickerCount: number,
	megaClickerCount: number,
	clickPowerCount: number,
	multiplierCount: number,
	rebirthCount: number,
	totalClicks: number,
	useBaseSpeed: boolean,
	speedSliderPercent: number,
	ownedWings: boolean,
	ownedWingsVoidtech: boolean,
	ownedWingsDragon: boolean,
	ownedWingsDemonic: boolean,
	ownedWingsFae: boolean,
	ownedFlameTrail: boolean,
	ownedLightTrail: boolean,
	equippedCosmetic: "None" | "FlameTrail" | "LightTrail",
	equippedWings: "None" | "Classic" | "Voidtech" | "Dragon" | "Demonic" | "Fae",
	completedMazeNorth: boolean,
	completedMazeSouth: boolean,
	completedMazeEast: boolean,
	completedMazeWest: boolean,
}

local GameHandlers = {}

-- Copies every field from newValues into session in place, rather than
-- replacing the stored session with a new table outright -- callers (e.g.
-- RobuxPurchaseManager) can hold a reference to a player's session across a
-- yield; replacing the table wholesale would silently orphan that reference
-- from a concurrent Reset/Rebirth. Moved here from GameService.server.lua
-- along with the two handlers that used it.
local function applyInPlace(session: Session, newValues: Session)
	for key, value in pairs(newValues) do
		(session :: any)[key] = value
	end
end

export type ResetDeps = {
	-- Called (with force = true) only when the player had progress worth
	-- wiping -- see HandleReset's own hadProgress check.
	saveScore: (session: Session, force: boolean) -> (),
	sync: (session: Session) -> (),
	saveSession: (session: Session) -> (),
}

-- Zeroes score/upgrades (preserving totalClicks/rebirthCount/settings/items,
-- see GameLogic.ResetProgress), then: force-saves the leaderboard entry only
-- if the player actually had a nonzero score to wipe (a player who never
-- played shouldn't get a spurious "0 score" row -- see LeaderboardManager.
-- SaveScore's own <=0 guard), syncs the client, then durably saves. Always
-- proceeds -- Reset has no eligibility gate, unlike Rebirth below.
function GameHandlers.HandleReset(session: Session, deps: ResetDeps)
	local hadProgress = session.score > 0
	applyInPlace(session, GameLogic.ResetProgress(session))
	if hadProgress then
		deps.saveScore(session, true)
	end
	deps.sync(session)
	deps.saveSession(session)
end

export type RebirthDeps = {
	-- PerformRebirth clears owned items/equippedCosmetic in session data,
	-- but that alone doesn't touch whatever's already live on the player's
	-- currently-spawned character -- this reapplies it immediately rather
	-- than leaving a stale visible trail until their next respawn.
	applyCosmetic: (session: Session) -> (),
	saveScore: (session: Session, force: boolean) -> (),
	sync: (session: Session) -> (),
	saveSession: (session: Session) -> (),
}

-- Same shape as HandleReset, gated on GameLogic.CanRebirth and always
-- force-saving the leaderboard when it proceeds (a rebirth always wipes
-- score, so there's no "hadProgress" case to skip). Returns whether it
-- actually happened, so a caller (or a test) can tell a no-op apart from a
-- real rebirth without re-deriving CanRebirth itself.
function GameHandlers.HandleRebirth(session: Session, deps: RebirthDeps): boolean
	if not GameLogic.CanRebirth(session) then
		return false
	end

	applyInPlace(session, GameLogic.PerformRebirth(session))
	deps.applyCosmetic(session)
	deps.saveScore(session, true)
	deps.sync(session)
	deps.saveSession(session)
	return true
end

return GameHandlers
