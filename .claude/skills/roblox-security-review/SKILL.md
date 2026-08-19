---
name: roblox-security-review
description: Use for a security review of Autoclicker Void's server-authoritative code — src/server/*.lua and any RemoteEvent handling. Triggers on "security review", "check for exploits", "vulnerability scan", "can this be exploited", or before merging any change to src/server/. Distinct from the generic security-review skill (which targets web vulns like SQLi/XSS/secrets) — this checks Roblox-specific exploit surface: a modified client can call RemoteEvent:FireServer with arbitrary args, bypassing the UI entirely. Read-only — reports findings, does not fix them.
allowed-tools: Read, Grep, Glob
---

# Roblox security review (Autoclicker Void)

This game is server-authoritative: the server is the only thing that can be trusted,
because a modified/exploited client can fire any `RemoteEvent` with any arguments,
skipping the UI entirely. Don't apply generic web-vuln checklists (SQLi/XSS/secrets) —
there's no SQL, no browser, and this project's DataStore keys aren't secrets. The real
threat model is: **what happens if a hostile client sends the worst possible arguments
to every RemoteEvent, as fast as possible, right now?**

## Scope

Read and check every handler in:
- `src/server/GameService.server.lua` (`ClickEvent`, `PurchaseEvent`, `ResetEvent`,
  `RebirthEvent`, `UpdateSpeedSettingsEvent`, `PurchaseItemEvent`, `EquipCosmeticEvent`,
  `ActivateFlightEvent`)
- `src/server/RobuxPurchaseManager.lua` (`MarketplaceService.ProcessReceipt`)
- `src/server/MovementSystem.lua`, `DataManager.lua`, `LeaderboardManager.lua`,
  `SessionStore.lua`, `CosmeticsSystem.lua`, `FlightSystem.lua`
- `src/shared/GameHandlers.lua` — pure orchestration extracted out of
  `ResetEvent`/`RebirthEvent` (no RemoteEvent-facing arguments of its own, so it adds
  no new input-validation surface by itself, but check that `GameService.server.lua`'s
  dep-closures still wire it to the real, session-locked calls).

## Checklist

Walk every `OnServerEvent:Connect` handler and `ProcessReceipt` callback against all of
these — don't stop at the first pass/fail per handler, check every item per handler:

1. **Type-checked args**: is every argument received from the client explicitly
   checked with `typeof(x) == "..."` before being used, stored, or passed onward?
   Anything used without a preceding `typeof` check is a finding.

2. **Numeric range/NaN**: is every numeric arg clamped (`math.clamp`) to a sane range
   and checked for NaN (`x == x`, false for NaN) before being stored or used in
   arithmetic? An unclamped number can corrupt session state or downstream math
   (e.g. `SpeedCalculator`).

3. **No client-trusted costs/prices**: does any handler use a cost, price, or amount
   the client supplied, instead of recomputing it from `GameConstants`/`GameLogic`
   server-side? (`PurchaseEvent`'s `GameLogic.GetUpgradeCost` is the correct pattern
   to compare against.)

4. **No client-trusted results**: does any handler take a *computed result* from the
   client (a speed, a score delta, a multiplier) instead of recomputing it
   server-side? (`WalkSpeed` always being recomputed via `MovementSystem`, with only a
   *preference* accepted from `UpdateSpeedSettingsEvent`, is the correct pattern.)

5. **Locking discipline**: does every session read/write route through
   `SessionStore.With`/`Peek`/`Install`/`Remove`? Flag any direct access to session
   state outside those, and flag any `Peek` used where the session is being *mutated*
   (only safe for reads — see `SessionStore.lua`'s own comments on which call sites are
   justified).

6. **Rate-of-fire / flood risk**: does the handler have any debounce/throttle
   protecting against a modified client firing it in a tight loop? This was a real,
   previously-shipped gap in `ResetEvent`/`RebirthEvent` (both call `DataManager.Save`,
   a real DataStore write, on every accepted fire — a flood could exhaust the whole
   server's shared DataStore request budget) — since fixed (see
   `RESET_REBIRTH_COOLDOWN_SECONDS`/`isOnResetRebirthCooldown` in
   `GameService.server.lua`): a shared per-userId cooldown, checked *and stamped*
   **before** `SessionStore.With` is even entered, not inside its callback — stamping
   inside the callback would let two fires that both pass the check while queued
   behind a contended lock both go on to run and both hit `DataManager.Save`,
   defeating the cooldown entirely. Use this as the reference pattern for any new
   handler that does a real DataStore write on every fire. Two more established idioms
   worth checking for on handlers that DON'T write to DataStore but still do
   non-trivial work per fire: `PurchaseItemEvent`'s "already owned, no-op" guard and
   `EquipCosmeticEvent`'s "already in that requested state, no-op" guard (the latter
   was itself a real shipped gap — every fire, even a repeat of the current value, re-
   ran `CosmeticsSystem.ApplyEquippedCosmetic`'s full `Instance.new`/`Destroy` churn
   plus a whole-session `SyncState` broadcast, until fixed). `ActivateFlightEvent` is
   separately protected by `FlightSystem`'s own cooldown. `ClickEvent` deliberately has
   none of this — unlimited clicking only affects that one player's own score/
   leaderboard standing, not shared server resources, an accepted design tradeoff, not
   an oversight to flag.

7. **Atomic receipt claims**: for any DataStore-backed purchase/grant path, is the
   claim atomic (`UpdateAsync`, check-and-set in one call) rather than a separate
   `GetAsync` then `SetAsync` (a check-then-act race across concurrent server
   instances)? Compare against `RobuxPurchaseManager.claimReceipt`.

8. **Failure handling on paid grants**: does a failure partway through a grant
   correctly `unclaimReceipt` (so the purchase can retry) rather than leaving a
   receipt marked processed with nothing granted? Does the `pcall` boundary match the
   "returning normally means success, `error()` means failure" contract
   `RobuxPurchaseManager` uses, with no swallowed errors that silently corrupt state?

9. **Untrusted text into RichText**: currently not exploitable — usernames come from
   `Players.Name`/`Players:GetNameFromUserIdAsync` (Roblox-controlled, not raw client
   text) and no `TextLabel` in `src/client/init.client.lua` sets `RichText = true`. Only
   re-flag this if a future change adds free-text client input (chat, custom titles)
   rendered through a `TextLabel` with `RichText` enabled.

10. **Hard-coded secrets**: scan for any API key, webhook URL, or credential
    committed in `src/`. DataStore/OrderedDataStore key names (`GameConstants.STORAGE_KEY`
    etc.) are not secrets and are not findings.

## Output

Report findings as a list, most-severe first, each with: file, the specific handler/
line, what a hostile client could send, and what actually happens as a result. Don't
report an item as a finding just because it's theoretically incomplete — confirm there's
a concrete way to trigger the bad outcome before including it.
