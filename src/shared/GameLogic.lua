--!strict
local GameConstants = require(script.Parent.GameConstants)

local GameLogic = {}

export type Session = {
	score: number,
	autoClickerCount: number,
	megaClickerCount: number,
	clickPowerCount: number,
	multiplierCount: number,
}

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
