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
}

-- The single source of truth for what a blank session looks like: used both
-- for a brand-new save (DataManager) and for resetting progress (GameService).
function GameLogic.GetDefaultSession(): Session
	return {
		score = 0,
		autoClickerCount = 0,
		megaClickerCount = 0,
		clickPowerCount = 0,
		multiplierCount = 0,
	}
end

-- Flat cost lookup: prices never scale with how many the player already owns.
function GameLogic.GetUpgradeCost(upgradeId: string): number
	local upgrade = GameConstants.UPGRADES[upgradeId]
	if not upgrade then
		error("Unknown upgrade id: " .. tostring(upgradeId))
	end
	return upgrade.Cost
end

-- Combined income multiplier from Global Multiplier upgrades.
function GameLogic.CalculateMultiplier(session: Session): number
	return 1 + session.multiplierCount * GameConstants.UPGRADES.Multiplier.Bonus
end

-- Points earned from a single manual click, including Click Power and the multiplier.
function GameLogic.CalculateClickGain(session: Session): number
	local base = 1 + session.clickPowerCount * GameConstants.UPGRADES.ClickPower.Bonus
	return base * GameLogic.CalculateMultiplier(session)
end

-- Points earned from idle auto-clickers (both tiers) over deltaTime seconds.
function GameLogic.CalculateIdleGain(session: Session, deltaTime: number): number
	local ratePerSecond = session.autoClickerCount * GameConstants.UPGRADES.AutoClicker.Rate
		+ session.megaClickerCount * GameConstants.UPGRADES.MegaClicker.Rate
	return ratePerSecond * GameLogic.CalculateMultiplier(session) * deltaTime
end

return GameLogic
