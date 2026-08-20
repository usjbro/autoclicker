--!strict
-- `script` only exists under Roblox/Rojo; the else branch lets this same file
-- load under a standalone Luau runtime (Lune) for headless testing.
local GameConstants
if script then
	GameConstants = require(script.Parent.GameConstants)
else
	GameConstants = require("./GameConstants")
end

local GameLogic = {}

export type Session = {
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

-- The single source of truth for what a blank session looks like: used both
-- for a brand-new save (DataManager) and as the basis for ResetProgress below.
function GameLogic.GetDefaultSession(): Session
	return {
		score = 0,
		autoClickerCount = 0,
		megaClickerCount = 0,
		clickPowerCount = 0,
		multiplierCount = 0,
		rebirthCount = 0,
		totalClicks = 0,
		useBaseSpeed = true,
		speedSliderPercent = 100,
		ownedWings = false,
		ownedWingsVoidtech = false,
		ownedWingsDragon = false,
		ownedWingsDemonic = false,
		ownedWingsFae = false,
		ownedFlameTrail = false,
		ownedLightTrail = false,
		equippedCosmetic = "None",
		equippedWings = "None",
		completedMazeNorth = false,
		completedMazeSouth = false,
		completedMazeEast = false,
		completedMazeWest = false,
	}
end

-- Zeroes score + all upgrade counts, but preserves totalClicks (a lifetime
-- achievement stat, not tied to movement speed -- see SpeedCalculator, which
-- is score-based and so resets to base speed along with score), rebirthCount,
-- speed preferences, and owned items (Wings/cosmetics survive an ordinary
-- Reset -- they're only cleared by Rebirth, see PerformRebirth below) -- a
-- progress reset shouldn't erase those. Used by both the Reset and Rebirth
-- handlers.
function GameLogic.ResetProgress(session: Session): Session
	local reset = GameLogic.GetDefaultSession()
	reset.rebirthCount = session.rebirthCount
	reset.totalClicks = session.totalClicks
	reset.useBaseSpeed = session.useBaseSpeed
	reset.speedSliderPercent = session.speedSliderPercent
	reset.ownedWings = session.ownedWings
	reset.ownedWingsVoidtech = session.ownedWingsVoidtech
	reset.ownedWingsDragon = session.ownedWingsDragon
	reset.ownedWingsDemonic = session.ownedWingsDemonic
	reset.ownedWingsFae = session.ownedWingsFae
	reset.ownedFlameTrail = session.ownedFlameTrail
	reset.ownedLightTrail = session.ownedLightTrail
	reset.equippedCosmetic = session.equippedCosmetic
	reset.equippedWings = session.equippedWings
	return reset
end

-- Same as ResetProgress, plus incrementing rebirthCount and clearing owned
-- items -- unlike an ordinary Reset, a Rebirth does take Wings/cosmetics
-- away (re-buyable afterward), by design.
function GameLogic.PerformRebirth(session: Session): Session
	local reset = GameLogic.ResetProgress(session)
	reset.rebirthCount += 1
	reset.ownedWings = false
	reset.ownedWingsVoidtech = false
	reset.ownedWingsDragon = false
	reset.ownedWingsDemonic = false
	reset.ownedWingsFae = false
	reset.ownedFlameTrail = false
	reset.ownedLightTrail = false
	reset.equippedCosmetic = "None"
	reset.equippedWings = "None"
	return reset
end

-- Whether a session has enough score to rebirth.
function GameLogic.CanRebirth(session: Session): boolean
	return session.score >= GameConstants.REBIRTH.Threshold
end

-- Flat cost lookup: prices never scale with how many the player already owns.
function GameLogic.GetUpgradeCost(upgradeId: string): number
	local upgrade = GameConstants.UPGRADES[upgradeId]
	if not upgrade then
		error("Unknown upgrade id: " .. tostring(upgradeId))
	end
	return upgrade.Cost
end

-- Combined income multiplier from Global Multiplier upgrades and rebirths.
function GameLogic.CalculateMultiplier(session: Session): number
	return 1
		+ session.multiplierCount * GameConstants.UPGRADES.Multiplier.Bonus
		+ session.rebirthCount * GameConstants.REBIRTH.Bonus
end

-- Points earned from a single manual click, including Click Power and the multiplier.
function GameLogic.CalculateClickGain(session: Session): number
	local base = 1 + session.clickPowerCount * GameConstants.UPGRADES.ClickPower.Bonus
	return base * GameLogic.CalculateMultiplier(session)
end

-- Sum of permanent click/minute bonuses from completed maze wings (see
-- GameConstants.MAZE_GOALS) -- 0 if none completed yet. Factored out of
-- CalculateIdleGain so it's independently testable. Written as explicit
-- per-field checks rather than looping over MAZE_GOALS and indexing Session
-- by a dynamic string key -- Session is a fixed-field record type, not an
-- index-signature type, so a dynamic-key lookup wouldn't type-check under
-- --!strict (see MapBuilder.lua's MazeCell for the index-signature
-- alternative this deliberately isn't using).
function GameLogic.CalculateMazeBonusRate(session: Session): number
	local bonus = 0
	if session.completedMazeNorth then
		bonus += GameConstants.MAZE_GOALS.MazeNGoal.RewardPerMinute
	end
	if session.completedMazeSouth then
		bonus += GameConstants.MAZE_GOALS.MazeSGoal.RewardPerMinute
	end
	if session.completedMazeEast then
		bonus += GameConstants.MAZE_GOALS.MazeEGoal.RewardPerMinute
	end
	if session.completedMazeWest then
		bonus += GameConstants.MAZE_GOALS.MazeWGoal.RewardPerMinute
	end
	return bonus
end

-- Points earned from idle auto-clickers (both tiers) over deltaTime seconds.
-- AutoClicker/MegaClicker Rate constants are per-minute, so divide by 60 to
-- get the per-second rate the tick loop (deltaTime in real seconds) needs.
-- Completed-maze bonuses (also per-minute) are added into the same rate,
-- subject to the same multiplier as everything else -- no special case.
function GameLogic.CalculateIdleGain(session: Session, deltaTime: number): number
	local ratePerMinute = session.autoClickerCount * GameConstants.UPGRADES.AutoClicker.Rate
		+ session.megaClickerCount * GameConstants.UPGRADES.MegaClicker.Rate
		+ GameLogic.CalculateMazeBonusRate(session)
	local ratePerSecond = ratePerMinute / 60
	return ratePerSecond * GameLogic.CalculateMultiplier(session) * deltaTime
end

return GameLogic
