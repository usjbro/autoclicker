--!strict
local DataStoreService = game:GetService("DataStoreService")
local GameConstants = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConstants"))

-- Fallback safely if DataStoreService cannot load (e.g., unpublished place or API access not enabled in Studio)
local PlayerDataStore = nil
do
	local success, result = pcall(function()
		return DataStoreService:GetDataStore(GameConstants.STORAGE_KEY)
	end)
	if success then
		PlayerDataStore = result
	else
		warn("DataStoreService unavailable, player data will not persist: " .. tostring(result))
	end
end

local DataManager = {}

export type PlayerData = {
	score: number,
	autoClickerCount: number,
	megaClickerCount: number,
	clickPowerCount: number,
	multiplierCount: number,
}

local defaultData: PlayerData = {
	score = 0,
	autoClickerCount = 0,
	megaClickerCount = 0,
	clickPowerCount = 0,
	multiplierCount = 0,
}

function DataManager.Load(player: Player): PlayerData
	local success, result = false, nil
	if PlayerDataStore then
		success, result = pcall(function()
			return PlayerDataStore:GetAsync(tostring(player.UserId))
		end)
	end

	if success and result then
		-- Field-by-field fallback so saves from before an upgrade was added still load cleanly.
		return {
			score = result.score or defaultData.score,
			autoClickerCount = result.autoClickerCount or defaultData.autoClickerCount,
			megaClickerCount = result.megaClickerCount or defaultData.megaClickerCount,
			clickPowerCount = result.clickPowerCount or defaultData.clickPowerCount,
			multiplierCount = result.multiplierCount or defaultData.multiplierCount,
		}
	else
		return {
			score = defaultData.score,
			autoClickerCount = defaultData.autoClickerCount,
			megaClickerCount = defaultData.megaClickerCount,
			clickPowerCount = defaultData.clickPowerCount,
			multiplierCount = defaultData.multiplierCount,
		}
	end
end

function DataManager.Save(player: Player, data: PlayerData)
	if not PlayerDataStore then return end

	local success, err = pcall(function()
		PlayerDataStore:SetAsync(tostring(player.UserId), data)
	end)

	if not success then
		warn("Failed to save data for player " .. player.Name .. ": " .. tostring(err))
	end
end

return DataManager
