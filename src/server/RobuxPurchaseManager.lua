--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConstants = require(Shared:WaitForChild("GameConstants"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local SessionStoreType = require(script.Parent:WaitForChild("SessionStore"))
type SessionStoreModule = SessionStoreType.SessionStoreModule

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

-- Reverse lookup: DevProductId -> what to grant, built once from
-- GameConstants. Covers both UPGRADES (stacking counts, granted via +=1)
-- and ITEMS (one-time-owned flags, granted via =true) -- kept as a single
-- table (rather than two separate lookups) so ProcessReceipt has one place
-- to check regardless of which kind of product was bought.
type GrantKind = "Upgrade" | "Item"
local productIdToGrant: { [number]: { kind: GrantKind, id: string } } = {}
for upgradeId, upgrade in pairs(GameConstants.UPGRADES) do
	if upgrade.DevProductId and upgrade.DevProductId ~= 0 then
		productIdToGrant[upgrade.DevProductId] = { kind = "Upgrade", id = upgradeId }
	end
end
for itemId, item in pairs(GameConstants.ITEMS) do
	if item.DevProductId and item.DevProductId ~= 0 then
		productIdToGrant[item.DevProductId] = { kind = "Item", id = itemId }
	end
end

type ClaimResult = "Claimed" | "AlreadyProcessed" | "Error"

-- Atomically claims a receipt via UpdateAsync (not a separate
-- GetAsync-then-SetAsync, which would be a check-then-act race between
-- concurrent server instances processing the same receipt). Returns
-- "Claimed" if this call should proceed to grant the purchase,
-- "AlreadyProcessed" if some call already fully handled it, or "Error" if
-- that couldn't be determined safely right now.
local function claimReceipt(receiptId: string): ClaimResult
	if not ReceiptStore then return "Claimed" end

	local alreadyProcessed = false
	local success = pcall(function()
		ReceiptStore:UpdateAsync(receiptId, function(oldValue)
			if oldValue == true then
				alreadyProcessed = true
				return oldValue
			end
			return true
		end)
	end)

	if not success then return "Error" end
	if alreadyProcessed then return "AlreadyProcessed" end
	return "Claimed"
end

-- Releases a claim taken above, for when the grant that was supposed to
-- follow it didn't actually succeed -- otherwise the receipt would be
-- permanently stuck "processed" with nothing ever granted for it.
local function unclaimReceipt(receiptId: string)
	if not ReceiptStore then return end
	local success, err = pcall(function()
		ReceiptStore:RemoveAsync(receiptId)
	end)
	if not success then
		warn("Failed to release claim on receipt " .. receiptId .. " after a failed grant: " .. tostring(err))
	end
end

-- sessionStore/syncPlayer are injected the same way LeaderboardManager.Start
-- is wired up in GameService.server.lua, so this module doesn't need its own
-- copy of session state.
function RobuxPurchaseManager.Start(
	sessionStore: SessionStoreModule,
	syncPlayer: (player: Player) -> ()
)
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local grant = productIdToGrant[receiptInfo.ProductId]
		if not grant then
			-- Unknown product id -- e.g. a real Developer Product was bought but
			-- its id was never wired into GameConstants.UPGRADES/ITEMS. Nothing
			-- to grant, but this is a real misconfiguration a developer needs to
			-- notice and resolve (potentially refunding the player), not a
			-- silent no-op.
			warn("Received a purchase for unrecognized ProductId " .. tostring(receiptInfo.ProductId)
				.. " (PurchaseId " .. tostring(receiptInfo.PurchaseId) .. ") -- nothing granted.")
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local claim = claimReceipt(receiptInfo.PurchaseId)
		if claim == "AlreadyProcessed" then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		elseif claim == "Error" then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			-- Player isn't online right now; release the claim and ask Roblox
			-- to retry later instead of losing the purchase.
			unclaimReceipt(receiptInfo.PurchaseId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local decision = Enum.ProductPurchaseDecision.NotProcessedYet

		-- Routed through the same SessionStore (which itself takes SessionLock)
		-- as every other session-mutating handler in GameService.server.lua, so
		-- a Reset/Rebirth/disconnect-save can never interleave with this grant
		-- on the same session table.
		local sessionFound = false
		sessionStore.With(receiptInfo.PlayerId, function(session)
			sessionFound = true

			-- The pcall covers only the part that determines whether the
			-- purchase is actually committed (grant + save) -- once that
			-- succeeds, the purchase is durably done regardless of what
			-- happens next, so a later failure (e.g. syncPlayer erroring on a
			-- since-disconnected player) must NOT release the receipt claim
			-- and risk a double-grant on retry. The contract is simple and
			-- hard to get wrong by omission: returning normally means
			-- success, error(...) means failure -- there's no separate
			-- "did it work" flag to forget to set on some future added path.
			-- Explicit ...any return type so pcall's inferred return type is
			-- (boolean, ...any) -- same reasoning as SessionLock.Run's fn
			-- parameter; without it, Luau's strict-mode pcall stub trips a
			-- spurious 2-values-required error since this closure returns
			-- nothing on success.
			local ok, err = pcall(function(): ...any
				-- Grant, then durably save immediately -- real money must not
				-- depend on the player disconnecting naturally. Upgrades stack
				-- (+=1, rolled back with -=1 on a failed save); items are
				-- one-time-owned (=true, rolled back by restoring whatever the
				-- flag was before -- almost always false, but restoring the
				-- prior value rather than hardcoding false is correct even in
				-- the unlikely event this fires for an already-owned item).
				if grant.kind == "Upgrade" then
					local field = GameConstants.UPGRADE_FIELDS[grant.id]
					if not field then
						error("no UPGRADE_FIELDS entry for upgrade " .. grant.id, 0)
					end
					session[field] += 1

					if not DataManager.IsAvailable() then
						-- No DataStore access at all right now (e.g. Studio
						-- without API access) -- demanding a successful save
						-- would mean Robux purchases can never complete. Grant
						-- in-memory only, same degrade-gracefully behavior the
						-- rest of the game already has.
						return
					end

					local saveOk = DataManager.Save(player, session)
					if not saveOk then
						session[field] -= 1
						error("failed to save purchase", 0)
					end
				else
					local field = GameConstants.ITEM_FIELDS[grant.id]
					if not field then
						error("no ITEM_FIELDS entry for item " .. grant.id, 0)
					end
					local previousValue = session[field]
					session[field] = true

					if not DataManager.IsAvailable() then
						return
					end

					local saveOk = DataManager.Save(player, session)
					if not saveOk then
						session[field] = previousValue
						error("failed to save purchase", 0)
					end
				end
			end)

			if not ok then
				unclaimReceipt(receiptInfo.PurchaseId)
				warn("Robux purchase grant failed for PurchaseId " .. receiptInfo.PurchaseId
					.. ", will retry: " .. tostring(err))
			else
				decision = Enum.ProductPurchaseDecision.PurchaseGranted
				-- Best-effort UI update; a failure here doesn't affect whether
				-- the purchase itself succeeded, so it's outside the pcall above.
				syncPlayer(player)
			end
		end)

		if not sessionFound then
			-- SessionStore.With silently no-ops when there's no session for
			-- this userId (e.g. the player disconnected between the earlier
			-- online check and now) -- mirror the same unclaim-and-retry
			-- handling the grant-failure path above uses, since the receipt
			-- claim must never be left stuck "processed" with nothing granted.
			unclaimReceipt(receiptInfo.PurchaseId)
			warn("Robux purchase grant failed for PurchaseId " .. receiptInfo.PurchaseId
				.. ": no active session for player, will retry")
		end

		return decision
	end
end

return RobuxPurchaseManager
