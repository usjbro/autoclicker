--!strict
local GameConstants = {
	STORAGE_KEY = "autoclicker-save",
	LEADERBOARD_KEY = "autoclicker-leaderboard",
	RECEIPT_STORE_KEY = "autoclicker-processed-receipts",
	TICK_RATE = 1,

	-- Flat prices: cost never scales with how many a player owns.
	-- RobuxCost/DevProductId are the alternate Robux purchase path (see
	-- RobuxPurchaseManager.lua). DevProductId = 0 is a placeholder: create a
	-- matching Developer Product for each upgrade in the Roblox Creator
	-- Dashboard (Monetization > Developer Products) priced at RobuxCost, then
	-- paste its numeric id here. Buttons stay disabled ("Coming soon") until
	-- a real id is set.
	UPGRADES = {
		AutoClicker = { Cost = 10, Rate = 1, RobuxCost = 10, DevProductId = 0 },
		MegaClicker = { Cost = 150, Rate = 10, RobuxCost = 150, DevProductId = 0 },
		ClickPower = { Cost = 25, Bonus = 1, RobuxCost = 25, DevProductId = 0 },
		Multiplier = { Cost = 500, Bonus = 0.10, RobuxCost = 500, DevProductId = 0 },
	},

	-- Rebirth ("prestige"): resets score + upgrades for a permanent bonus.
	REBIRTH = {
		Threshold = 10000,
		Bonus = 0.25,
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
