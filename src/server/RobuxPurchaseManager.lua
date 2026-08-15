--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local GameLogic = require(Shared:WaitForChild("GameLogic"))

local RobuxPurchaseManager = {}

-- Real-money purchases must never be silently lost or double-granted across
-- retries/server restarts, so processed receipts are tracked in their own
-- DataStore (separate from player saves/leaderboard). Degrades gracefully
-- like DataManager/LeaderboardManager if DataStore access isn't available.
local ReceiptStore = nil
do
	local success, result = pcall(function()
		return DataStoreService:GetDataStore(GameConstants.RECEIPT_STORE_KEY)
	end)
	if success then
		ReceiptStore = result
	else
		warn("DataStoreService unavailable, Robux receipts cannot be tracked: " .. tostring(result))
	end
end

-- Reverse lookup: DevProductId -> upgrade id, built once from GameConstants.
local productIdToUpgrade: { [number]: string } = {}
for upgradeId, upgrade in pairs(GameConstants.UPGRADES) do
	if upgrade.DevProductId and upgrade.DevProductId ~= 0 then
		productIdToUpgrade[upgrade.DevProductId] = upgradeId
	end
end

local function wasReceiptProcessed(receiptId: string): boolean
	if not ReceiptStore then return false end
	local success, result = pcall(function()
		return ReceiptStore:GetAsync(receiptId)
	end)
	return success and result == true
end

local function markReceiptProcessed(receiptId: string)
	if not ReceiptStore then return end
	local success, err = pcall(function()
		ReceiptStore:SetAsync(receiptId, true)
	end)
	if not success then
		warn("Failed to record processed receipt " .. receiptId .. ": " .. tostring(err))
	end
end

-- getActiveSessions/syncPlayer are injected the same way LeaderboardManager.Start
-- is wired up in GameService.server.lua, so this module doesn't need its own
-- copy of session state.
function RobuxPurchaseManager.Start(
	getActiveSessions: () -> { [number]: GameLogic.Session },
	syncPlayer: (player: Player) -> ()
)
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local upgradeId = productIdToUpgrade[receiptInfo.ProductId]
		if not upgradeId then
			-- Unknown product id (e.g. a placeholder 0 was somehow purchased) --
			-- nothing to grant, but still acknowledge so it doesn't retry forever.
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		if wasReceiptProcessed(receiptInfo.PurchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			-- Player isn't online right now; ask Roblox to retry later instead
			-- of losing the purchase.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local session = getActiveSessions()[receiptInfo.PlayerId]
		if not session then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local field = GameConstants.UPGRADE_FIELDS[upgradeId]
		session[field] += 1
		syncPlayer(player)

		markReceiptProcessed(receiptInfo.PurchaseId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return RobuxPurchaseManager
