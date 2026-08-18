---
name: roblox-feature-scaffold
description: Use when adding a new RemoteEvent/handler, a new upgrade or session field, or any new session-mutating server logic to Autoclicker Void. Triggers on requests like "add a new upgrade", "add a new RemoteEvent", "add a Boost/temporary-effect feature", "add a purchase type", or any change that needs a server handler mutating player session state. Not for pure client-only UI tweaks or one-line bugfixes.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(lune *), Bash(rojo *), Bash(luau-lsp *)
---

# Roblox feature scaffold (Autoclicker Void)

This project has a fixed, load-bearing shape for "add a feature that touches player
state." Skipping a step here is exactly how this codebase's past concurrency/sync bugs
happened (missed locking, missed `syncPlayer`, session shape drift between reset and
rebirth). Walk every numbered step below for any new RemoteEvent/handler/session field —
don't skip steps because "this one's simple."

See `references/handler-template.lua` for an annotated template mirroring the existing
`ClickEvent`/`PurchaseEvent`/`UpdateSpeedSettingsEvent` handlers in
`src/server/GameService.server.lua`.

## Checklist

1. **Declare the RemoteEvent** in `default.project.json` under
   `tree.ReplicatedStorage`, alongside the existing `ClickEvent`/`PurchaseEvent`/etc.
   entries (`{"$className": "RemoteEvent"}`). Skip this if the feature is a Robux
   purchase — that goes through `MarketplaceService.ProcessReceipt` in
   `RobuxPurchaseManager.lua` instead, not a custom RemoteEvent.

2. **Extend `src/shared/GameConstants.lua`** if this adds a new upgrade or priced
   item: add an entry to `UPGRADES` (flat `Cost`/`RobuxCost`/`DevProductId` — this
   project's upgrades never scale-price with quantity owned) and a matching entry in
   `UPGRADE_FIELDS` mapping the upgrade id to the session field name it increments.

3. **Extend `src/shared/GameLogic.lua`** if the session shape changes: add the new
   field to `GetDefaultSession()`, and to `ResetProgress`/`PerformRebirth` explicitly —
   decide whether it should be zeroed like score/upgrade counts, or preserved like
   `totalClicks`/`rebirthCount`. These two functions are the single source of truth for
   "what survives a reset," used by both server validation and client display — don't
   let a new field bypass them.

4. **Server handler in `src/server/GameService.server.lua`**: always shape it as
   ```lua
   SomeEvent.OnServerEvent:Connect(function(player, ...)
       SessionStore.With(player.UserId, function(session)
           -- validate, mutate, syncPlayer(player)
       end)
   end)
   ```
   Never read or write a session outside `SessionStore.With`/`Peek`/`Install`/`Remove` —
   `activeSessions` is private to `SessionStore.lua` specifically so nothing else can
   bypass the lock.

5. **Validate every client-supplied argument** before using it:
   - `typeof(x) == "..."` check first, always — see `PurchaseEvent`'s `upgradeId`
     string check and `UpdateSpeedSettingsEvent`'s boolean/number checks.
   - Numeric args: clamp with `math.clamp(x, min, max)` and reject NaN with a
     self-equality check (`x == x`, false for NaN) before storing — see
     `UpdateSpeedSettingsEvent`'s `speedSliderPercent` handling.
   - Never trust a client-supplied cost, price, or computed result. Recompute it
     server-side from `GameConstants`/`GameLogic` (e.g. `GameLogic.GetUpgradeCost`),
     the same way `WalkSpeed` is always server-recomputed via `MovementSystem`, never
     taken from the client.

6. **Call `syncPlayer(player)`** after any mutation, so the client's view and (if
   relevant) `WalkSpeed` stay consistent. This is centralized in
   `GameService.server.lua` — don't hand-roll a separate `SyncState:FireClient` call.

7. **Durable save if needed**: if this mutation shouldn't be losable to an unclean
   disconnect (like Reset/Rebirth/Robux grants), call `DataManager.Save(player,
   session)` directly right after `syncPlayer`, rather than relying only on the
   eventual `PlayerRemoving` save.

8. **Client listener in `src/client/init.client.lua`**: the client only renders state
   pushed via `SyncState` and fires input events — it never predicts or computes
   values locally that the server owns. Follow the existing `currentScreen`/
   `setScreen()` pattern if this adds a new screen/panel.

9. **Update tests in both suites** if `GameLogic.lua`/`NumberFormat.lua`/
   `SpeedCalculator.lua` logic changed:
   - `src/tests/*.spec.lua` (TestEZ, runs in a live Roblox server)
   - `test/gameLogic.test.luau` (Lune, headless) — keep test cases in sync between
     the two per CLAUDE.md; don't add a case to one and forget the other.

10. **Before opening a PR**, run all three local checks CI also runs. Neither of the
    first two executes or type-checks server/client Luau — `lune` only runs the
    specific pure-logic files it requires, `rojo build` only compiles the place-file
    structure — so a new handler with a bad `Enum` reference or an argument-type
    mismatch sails through both clean. `luau-lsp analyze` is what actually catches
    that class of bug:
    ```sh
    lune run test/gameLogic.test.luau
    rojo build default.project.json -o /tmp/check.rbxlx
    rojo sourcemap default.project.json -o sourcemap.json
    luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
    ```
    Report which steps above were touched and which were skipped (and why) when
    presenting the change.
