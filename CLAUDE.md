# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

This repo contains **Autoclicker Void**, a Roblox idle-clicker game: a Luau/Rojo project (`src/`, `default.project.json`) with server-authoritative state and a global leaderboard. `build.rbxlx` is a local build artifact (regenerate it with `rojo build`, don't rely on it as source of truth) and isn't tracked in git. See `GEMINI.md` for the original design brief it was built from.

`my-new-game/` is unrelated, unused Rojo scaffolding (default `rojo init` boilerplate with placeholder "Hello world" scripts) — not part of the real project. `__pycache__/` contains stale compiled artifacts with no corresponding source in the repo; ignore it.

Upgrades (base + Mega Auto-Clicker, Click Power, Global Multiplier) are all priced with **flat, non-scaling costs** — see `src/shared/GameConstants.lua`'s `UPGRADES` table — plus a rebirth/prestige system.

`AutoClicker`/`MegaClicker` `Rate` values are **per-minute**, not per-second (`GameLogic.CalculateIdleGain` divides by 60 internally); the server's idle-gain loop still ticks every `TICK_RATE` (1) second, it just adds a smaller fractional amount each tick.

## Autoclicker Void

### Tech stack
- **Luau** scripting, synced via **Rojo** (`default.project.json` maps `src/` into the Roblox instance tree).
- **TestEZ** for unit tests (`.spec.lua` files under `src/tests/`).
- **DataStoreService** for persistence.

### Sync workflow
```sh
rojo serve
```
Then connect via the Rojo Studio plugin.

### Architecture — server-authoritative state
The server is the source of truth for scores and purchases; the client only renders state pushed to it and fires input events.

- `src/shared/GameConstants.lua` — shared constants: the `UPGRADES` table (flat `Cost`/`RobuxCost`/`DevProductId` plus `Rate`/`Bonus` per upgrade id), `UPGRADE_FIELDS` (upgrade id → session field name), `REBIRTH` (threshold + permanent bonus), `TICK_RATE`, DataStore keys.
- `src/shared/GameLogic.lua` — pure functions for cost lookup (`GetUpgradeCost`), click/idle gain (`CalculateClickGain`, `CalculateIdleGain`), the income multiplier (`CalculateMultiplier`, combines Global Multiplier upgrades and rebirths), rebirth eligibility (`CanRebirth`), and the canonical blank-session shape (`GetDefaultSession`). `ResetProgress`/`PerformRebirth` are the single source of truth for "what survives a reset" — both zero score + upgrade counts but preserve `totalClicks`, `rebirthCount`, and speed preferences; `PerformRebirth` additionally increments `rebirthCount`. Required by both server (validation) and client (UI display) so the math can't drift between them.
- `src/shared/NumberFormat.lua` — `Format(n)` abbreviates large numbers (1000 → "1K", 1500000 → "1.5M", etc., continuing past T with two-letter suffixes). Used everywhere a number is displayed, client-side only.
- `src/shared/SpeedCalculator.lua` — the single centralized place movement-speed math lives: `BASE_WALK_SPEED`, `CalculateMaxSpeed(totalClicks)` (capped, clamped against invalid input), and `CalculateEffectiveSpeed(session)` (base speed if `useBaseSpeed`, otherwise interpolated between base and max by `speedSliderPercent`). Used by both `MovementSystem` (server, authoritative) and the client (display only).
- `src/server/GameService.server.lua` — owns `activeSessions` (per-player state keyed by `UserId`), handles `ClickEvent`/`PurchaseEvent`/`ResetEvent`/`RebirthEvent`/`UpdateSpeedSettingsEvent` from clients, runs the idle-gain loop (`task.spawn` loop on `GameConstants.TICK_RATE`), and pushes state to clients via the `SyncState` RemoteEvent. `ClickEvent` also increments `session.totalClicks` and reapplies movement speed when `useBaseSpeed` is false (skipped otherwise, since base speed never changes with clicks -- see `SpeedCalculator`). `UpdateSpeedSettingsEvent` only ever receives a *preference* (`useBaseSpeed`, `speedSliderPercent`, clamped/validated) — the actual `WalkSpeed` is always recomputed server-side, never taken from the client. Loads/saves sessions via `DataManager` on player join/leave. Also builds the void environment (`VoidBox`, `VoidFloor`, `VoidSpawn`) before any `Player` connections, so a joining player can never spawn before the floor exists.
- `src/server/DataManager.lua` — wraps `DataStoreService` (store name = `GameConstants.STORAGE_KEY`) for per-player load/save; falls back to `GameLogic.GetDefaultSession()` on any failure. `LoadRaw(userId)` is a `Player`-less variant (returns `nil` on failure) used by `LeaderboardManager` for offline players' stats.
- `src/server/MovementSystem.lua` — the only place `Humanoid.WalkSpeed` gets set. `ApplyEffectiveSpeed(player, session)` computes it via `SpeedCalculator` and applies it; `Start` reapplies it on every `CharacterAdded` (WalkSpeed doesn't survive a respawn). `GameService` also calls `ApplyEffectiveSpeed` directly right after loading a session, in case the character already spawned before the load finished.
- `src/server/LeaderboardManager.lua` — wraps a separate `OrderedDataStore` (`GameConstants.LEADERBOARD_KEY`) for the top-10 global leaderboard, sorted by score. Entries also include `totalClicks`, pulled from the live session if that player's online or via `DataManager.LoadRaw` otherwise. Refreshes every 60s, broadcasts via the `LeaderboardUpdate` RemoteEvent, caches usernames to avoid API throttling, and degrades gracefully (warns + serves cached data) if DataStore API access isn't available (e.g. in Studio without API access enabled).
- `src/server/RobuxPurchaseManager.lua` — handles the Robux alternate-currency path via `MarketplaceService.ProcessReceipt`, granting the matching upgrade on the player's active session. Tracks processed receipt ids in their own DataStore (`GameConstants.RECEIPT_STORE_KEY`) so a real-money purchase is never silently lost or double-granted across retries/restarts. **`DevProductId`s in `GameConstants.UPGRADES` are placeholder `0`s** — create 4 matching Developer Products in the Roblox Creator Dashboard (Monetization > Developer Products), one per upgrade, priced at that upgrade's `RobuxCost`, then paste the resulting numeric ids in; the client's Robux buy buttons stay disabled ("Coming soon") until then.
- `src/client/init.client.lua` — builds the entire UI programmatically (no `.rbxlx`-authored UI) with a dark theme (`#1e1e2f` background, `#6c5ce7` accent), driven by a single `currentScreen` state (`"Clicker" | "Shop" | "Settings" | "Movement"`) via `setScreen()` so only one screen is ever visible at once. Bottom-right: 3 stacked dark-gray icon buttons (Clicker/Shop/Settings — Unicode glyphs, since uploading custom Roblox image assets isn't available here) plus a separate blue "Toggle Moving" button. Clicker screen is a persistent-feeling top HUD (score/rate/total clicks/rebirths/click button); Shop and Settings are centered popups; Movement mode hides the nav stack and whichever panel was open, showing a minimal top stats bar and a left-side return button instead, leaving the map unobstructed. Settings has a custom drag-slider (Roblox has no built-in one) for movement speed, always echoing the server's authoritative value rather than trusting local drag state. A top-right panel renders the live leaderboard from `LeaderboardUpdate`. Binds mouse click and `Space` key (only while on the Clicker screen) to `ClickEvent`.

RemoteEvents (`ClickEvent`, `PurchaseEvent`, `ResetEvent`, `RebirthEvent`, `UpdateSpeedSettingsEvent`, `SyncState`, `LeaderboardUpdate`) are declared in `default.project.json` under `ReplicatedStorage`, not in a `.lua` file. Robux purchases go through Roblox's built-in `MarketplaceService` APIs instead, not a custom RemoteEvent.

Characters spawn normally (`Players.CharacterAutoLoads` is left at its default) and walk around a flat black floor inside a large black `VoidBox`, with Roblox's default third-person camera/movement (from `PlayerModule`/`CameraModule` under `StarterPlayerScripts`) — no custom camera code. `MovementSystem` overrides `WalkSpeed` only; movement itself is entirely stock Roblox. Health/Backpack CoreGui stay hidden client-side since this game has no combat/damage. The client's "Movement mode" toggle is a pure UI state (which panels are visible) — the character can always physically move regardless of which screen is showing.

### Tests
Unit tests live in `src/tests/*.spec.lua` (`GameLogic.spec.lua`, `NumberFormat.spec.lua`, `SpeedCalculator.spec.lua`) and run automatically on server startup via `src/tests/runner.server.lua`, which bootstraps TestEZ if present in `ReplicatedStorage` (silently skips otherwise) and auto-discovers every `.spec.lua` file under `src/tests/`. These only execute inside a running Roblox server session (Studio or a live server) — there's no CLI runner for them.

For the pure logic in `src/shared/` (`GameLogic.lua`, `NumberFormat.lua`, `SpeedCalculator.lua`) specifically, `test/gameLogic.test.luau` runs the equivalent assertions headlessly via [Lune](https://lune-org.github.io/docs) (`brew install lune`, then `lune run test/gameLogic.test.luau`) — no Studio needed. This works because `GameLogic.lua`'s one `require` call branches on whether the Roblox-only `script` global exists, falling back to a Lune-style relative require otherwise (`NumberFormat.lua`/`SpeedCalculator.lua` have no internal requires, so they need no such branch); the files are otherwise unmodified between the two runtimes. `test/` lives outside `src/` on purpose so Rojo never syncs it into the Roblox place. Keep the Lune and TestEZ suites' test cases in sync when either changes.

### Pending work
- Audio feedback for clicks/purchases — from the original GEMINI.md roadmap.
- **Create the 4 Robux Developer Products** in the Creator Dashboard and fill in the real `DevProductId`s in `GameConstants.UPGRADES` (see `RobuxPurchaseManager.lua` above) — only the user can do this, it's an external manual step.
- Movement mode is currently just an empty floor to walk on ("multiple things that might be implemented later," per the user's spec) — collectibles/interactables/unlockable areas are intentionally not built yet.

## Development workflow

`main` is the single trunk branch — it's what's kept local and deployed to Roblox, and it should always be in a known-good, tested state. There is no separate long-lived integration branch; every other branch merges directly into `main`. Work happens on short-lived branches, one per issue or fix, merged back via PR:

1. Branch off the latest `main`: `git checkout -b fix/<short-description>` (or `feature/`, `chore/` for non-bug work).
2. Make the change. Run `lune run test/gameLogic.test.luau` and `rojo build default.project.json -o /tmp/check.rbxlx` locally before pushing.
3. Open a PR against `main` (`.github/PULL_REQUEST_TEMPLATE.md` has the checklist). GitHub Actions (`.github/workflows/ci.yml`) runs the same two checks automatically on every PR, regardless of target branch, plus every push to `main`, using `lune`/`rojo` versions pinned in that file — a local `brew install lune`/`brew install rojo` tracks whatever's current in Homebrew instead, so if a Lune/Rojo upgrade ever changes behavior, CI and a local run can disagree until `ci.yml`'s pinned versions are bumped to match.
4. `main` has branch protection requiring a PR (not a direct push) and a passing CI run before merging. Repo settings only allow squash-merging and auto-delete the branch afterward, enforcing that step too rather than relying on remembering to do it manually.
5. Prefer reviewing the diff (manually or via the `/code-review` skill) before merging, especially for anything touching `src/server/` — this codebase has already hit real concurrency bugs (shared per-player session state mutated from multiple RemoteEvent handlers/DataStore callbacks) that surfaced only under review, not from casual reading.

**The `dev` branch is not part of this project.** It diverged at the very first commit and contains an unrelated Python OCR-based screen-automation tool (`main.py`, `logger.py`, `ocr_detector.py`) that happens to share this repo by name collision. Don't merge it into or base work off of it.
