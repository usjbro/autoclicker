# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

This repo contains **two independent implementations of the same idle-clicker game**, at different stages of maturity:

1. **Browser version** (tracked in git: `index.html`, `script.js`, `style.css`) — a vanilla JS/HTML/CSS idle clicker. This is the original and complete implementation.
2. **Roblox conversion** ("Autoclicker Void", untracked/in-progress: `src/`, `default.project.json`, `build.rbxlx`) — a Luau/Rojo port of the same game with server-authoritative state and a global leaderboard. This is the active area of development; see `GEMINI.md` for the original design brief this conversion was built from.

`my-new-game/` is unrelated, unused Rojo scaffolding (default `rojo init` boilerplate with placeholder "Hello world" scripts) — not part of either real project. `__pycache__/` contains stale compiled artifacts with no corresponding source in the repo; ignore it.

The two implementations' economics have **intentionally diverged**: the browser version still uses the original single-upgrade formula (clicking earns 1 point, auto-clickers passively earn `count` points/sec, each additional auto-clicker costs `floor(10 * 1.15^count)`). The Roblox version instead has four upgrades (base + Mega Auto-Clicker, Click Power, Global Multiplier) all priced with **flat, non-scaling costs** — see `src/shared/GameConstants.lua`'s `UPGRADES` table. Don't assume the two need to match; check with the user before porting one implementation's formula changes to the other.

## Browser version

Run it by opening `index.html` directly, or serving statically:
```sh
python3 -m http.server
```
There is no build step, package manager, or test suite for this version — it's plain JS. State (`score`, `autoClickerCount`) lives in a single `state` object in `script.js` and is persisted to `localStorage` under key `autoclicker-save` after every mutation. The auto-clicker tick runs on a client-side `setInterval` (1s).

## Roblox conversion ("Autoclicker Void")

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

- `src/shared/GameConstants.lua` — shared constants: the `UPGRADES` table (flat `Cost` plus `Rate`/`Bonus` per upgrade id), `UPGRADE_FIELDS` (upgrade id → session field name), `TICK_RATE`, DataStore keys.
- `src/shared/GameLogic.lua` — pure functions for cost lookup (`GetUpgradeCost`), click/idle gain (`CalculateClickGain`, `CalculateIdleGain`), and the income multiplier (`CalculateMultiplier`), required by both server (validation) and client (UI display) so the math can't drift between them.
- `src/server/GameService.server.lua` — owns `activeSessions` (per-player state keyed by `UserId`), handles `ClickEvent`/`PurchaseEvent` from clients, runs the idle-gain loop (`task.spawn` loop on `GameConstants.TICK_RATE`), and pushes state to clients via the `SyncState` RemoteEvent. Loads/saves sessions via `DataManager` on player join/leave.
- `src/server/DataManager.lua` — wraps `DataStoreService` (store name = `GameConstants.STORAGE_KEY`) for per-player load/save; falls back to default `{score=0, autoClickerCount=0}` on any failure.
- `src/server/LeaderboardManager.lua` — wraps a separate `OrderedDataStore` (`GameConstants.LEADERBOARD_KEY`) for the top-10 global leaderboard. Refreshes every 60s, broadcasts via the `LeaderboardUpdate` RemoteEvent, caches usernames to avoid API throttling, and degrades gracefully (warns + serves cached data) if DataStore API access isn't available (e.g. in Studio without API access enabled).
- `src/client/init.client.lua` — builds the entire UI programmatically (no `.rbxlx`-authored UI) to visually match the browser version's theme (`#1e1e2f` background, `#6c5ce7` accent). Binds mouse click and `Space` key to `ClickEvent`; listens for `SyncState` to re-render.

RemoteEvents (`ClickEvent`, `PurchaseEvent`, `SyncState`, `LeaderboardUpdate`) are declared in `default.project.json` under `ReplicatedStorage`, not in a `.lua` file.

Environment setup done client-side: `Players.CharacterAutoLoads = false`, camera locked to `Scriptable` in a fixed position, lighting set to pitch black — the "void" aesthetic.

### Tests
Unit tests live in `src/tests/*.spec.lua` and run automatically on server startup via `src/tests/runner.server.lua`, which bootstraps TestEZ if present in `ReplicatedStorage` (silently skips otherwise). There's no CLI test runner — tests execute inside a running Roblox server session (Studio or a live server).

### Pending work (from GEMINI.md roadmap)
- Global leaderboard UI on the client (server-side plumbing already exists in `LeaderboardManager`).
- Audio feedback for clicks/purchases.
- Prestige system (permanent multiplier on reset).
