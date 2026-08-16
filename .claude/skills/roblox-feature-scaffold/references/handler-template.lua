--[[
	Annotated template for a new session-mutating RemoteEvent handler in
	src/server/GameService.server.lua. Not a real module — copy the shape, not
	this file, into GameService.server.lua alongside the existing handlers.

	Mirrors the real ClickEvent/PurchaseEvent/UpdateSpeedSettingsEvent handlers.
	Swap NewFeatureEvent, args, and the body for your feature.
]]

-- 1. Declared in default.project.json under ReplicatedStorage as:
--    "NewFeatureEvent": { "$className": "RemoteEvent" }
-- local NewFeatureEvent = ReplicatedStorage:WaitForChild("NewFeatureEvent")

NewFeatureEvent.OnServerEvent:Connect(function(player, someClientArg)
	-- Every mutation goes through SessionStore.With: it acquires the lock,
	-- looks up the session, and no-ops if the player has none (e.g. a race
	-- with PlayerRemoving). Never touch a session any other way.
	SessionStore.With(player.UserId, function(session)
		-- Validate BEFORE using anything from the client. Bail out silently
		-- (return) rather than erroring — a malformed/malicious arg should
		-- never crash the handler for other players.
		if typeof(someClientArg) ~= "number" then
			return
		end
		if someClientArg ~= someClientArg then -- NaN check
			return
		end
		local clamped = math.clamp(someClientArg, 0, 100)

		-- Recompute anything cost/result-shaped server-side. Never do:
		--   session.score -= someClientSuppliedCost
		-- Do:
		--   local cost = GameLogic.GetUpgradeCost(upgradeId)
		--   if session.score >= cost then session.score -= cost end

		-- ... mutate session fields here ...

		-- Always resync after mutating.
		syncPlayer(player)

		-- Only if this mutation must survive an unclean disconnect
		-- (Reset/Rebirth/Robux-grant style durability):
		-- DataManager.Save(player, session)
	end)
end)
