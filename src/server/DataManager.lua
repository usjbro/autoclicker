--!strict
local DataStoreService = game:GetService("DataStoreService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))

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

local defaultData: GameLogic.Session = GameLogic.GetDefaultSession()

-- `or` would incorrectly override a legitimately-saved `false` (e.g.
-- useBaseSpeed) with the default, so fall back on nil specifically.
local function fallback<T>(value: T?, default: T): T
	if value == nil then
		return default
	end
	return value
end

-- Returns nil if there's no save or it couldn't be loaded (caller decides the fallback).
local function loadByUserId(userId: number): GameLogic.Session?
	local success, result = false, nil
	if PlayerDataStore then
		success, result = pcall(function()
			return PlayerDataStore:GetAsync(tostring(userId))
		end)
	end

	if not (success and result) then
		return nil
	end

	-- Field-by-field fallback so saves from before an upgrade was added still load cleanly.
	return {
		score = fallback(result.score, defaultData.score),
		autoClickerCount = fallback(result.autoClickerCount, defaultData.autoClickerCount),
		megaClickerCount = fallback(result.megaClickerCount, defaultData.megaClickerCount),
		clickPowerCount = fallback(result.clickPowerCount, defaultData.clickPowerCount),
		multiplierCount = fallback(result.multiplierCount, defaultData.multiplierCount),
		rebirthCount = fallback(result.rebirthCount, defaultData.rebirthCount),
		totalClicks = fallback(result.totalClicks, defaultData.totalClicks),
		useBaseSpeed = fallback(result.useBaseSpeed, defaultData.useBaseSpeed),
		speedSliderPercent = fallback(result.speedSliderPercent, defaultData.speedSliderPercent),
	}
end

function DataManager.Load(player: Player): GameLogic.Session
	return loadByUserId(player.UserId) or GameLogic.GetDefaultSession()
end

-- For players who aren't currently online (e.g. leaderboard entries for
-- offline players). Returns nil if there's no save or it couldn't be loaded.
function DataManager.LoadRaw(userId: number): GameLogic.Session?
	return loadByUserId(userId)
end

function DataManager.Save(player: Player, data: GameLogic.Session)
	if not PlayerDataStore then return end

	local success, err = pcall(function()
		PlayerDataStore:SetAsync(tostring(player.UserId), data)
	end)

	if not success then
		warn("Failed to save data for player " .. player.Name .. ": " .. tostring(err))
	end
end

return DataManager
