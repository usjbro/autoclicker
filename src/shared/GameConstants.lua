--!strict
local GameConstants = {
	STORAGE_KEY = "autoclicker-save",
	LEADERBOARD_KEY = "autoclicker-leaderboard",
	TICK_RATE = 1,

	-- Flat prices: cost never scales with how many a player owns.
	UPGRADES = {
		AutoClicker = { Cost = 10, Rate = 1 },
		MegaClicker = { Cost = 150, Rate = 10 },
		ClickPower = { Cost = 25, Bonus = 1 },
		Multiplier = { Cost = 500, Bonus = 0.10 },
	},
}

-- Maps each upgrade id to the session field it increments on purchase.
GameConstants.UPGRADE_FIELDS = {
	AutoClicker = "autoClickerCount",
	MegaClicker = "megaClickerCount",
	ClickPower = "clickPowerCount",
	Multiplier = "multiplierCount",
}

return GameConstants
