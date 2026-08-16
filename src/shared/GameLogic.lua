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
	}
end

-- Zeroes score + all upgrade counts, but preserves totalClicks (a lifetime
-- achievement stat, not tied to movement speed -- see SpeedCalculator, which
-- is score-based and so resets to base speed along with score), rebirthCount,
-- and speed preferences -- a progress reset shouldn't erase those. Used by
-- both the Reset and Rebirth handlers.
function GameLogic.ResetProgress(session: Session): Session
	local reset = GameLogic.GetDefaultSession()
	reset.rebirthCount = session.rebirthCount
	reset.totalClicks = session.totalClicks
	reset.useBaseSpeed = session.useBaseSpeed
	reset.speedSliderPercent = session.speedSliderPercent
	return reset
end

-- Same as ResetProgress, plus incrementing rebirthCount.
function GameLogic.PerformRebirth(session: Session): Session
	local reset = GameLogic.ResetProgress(session)
	reset.rebirthCount += 1
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

-- Points earned from idle auto-clickers (both tiers) over deltaTime seconds.
-- AutoClicker/MegaClicker Rate constants are per-minute, so divide by 60 to
-- get the per-second rate the tick loop (deltaTime in real seconds) needs.
function GameLogic.CalculateIdleGain(session: Session, deltaTime: number): number
	local ratePerMinute = session.autoClickerCount * GameConstants.UPGRADES.AutoClicker.Rate
		+ session.megaClickerCount * GameConstants.UPGRADES.MegaClicker.Rate
	local ratePerSecond = ratePerMinute / 60
	return ratePerSecond * GameLogic.CalculateMultiplier(session) * deltaTime
end

return GameLogic
