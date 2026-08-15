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
Unit tests live in `src/tests/*.spec.lua` and run automatically on server startup via `src/tests/runner.server.lua`, which bootstraps TestEZ if present in `ReplicatedStorage` (silently skips otherwise). These only execute inside a running Roblox server session (Studio or a live server) — there's no CLI runner for them.

For the pure game-math in `src/shared/GameLogic.lua` specifically, `test/gameLogic.test.luau` runs headlessly via [Lune](https://lune-org.github.io/docs) (`brew install lune`, then `lune run test/gameLogic.test.luau`) — no Studio needed. This works because `GameLogic.lua`'s one `require` call branches on whether the Roblox-only `script` global exists, falling back to a Lune-style relative require otherwise; the file is otherwise unmodified between the two runtimes. `test/` lives outside `src/` on purpose so Rojo never syncs it into the Roblox place.

### Pending work (from GEMINI.md roadmap)
- Global leaderboard UI on the client (server-side plumbing already exists in `LeaderboardManager`).
- Audio feedback for clicks/purchases.
- Prestige system (permanent multiplier on reset).

## Development workflow

`main` is the deployable branch — it should always be in a known-good, tested state. Work happens on short-lived branches, one per issue or fix, merged back via PR:

1. Branch off the latest `main`: `git checkout -b fix/<short-description>` (or `feature/`, `chore/` for non-bug work).
2. Make the change. Run `lune run test/gameLogic.test.luau` and `rojo build default.project.json -o /tmp/check.rbxlx` locally before pushing.
3. Open a PR — against `main`, or against a longer-lived integration branch if one's in use (`.github/PULL_REQUEST_TEMPLATE.md` has the checklist). GitHub Actions (`.github/workflows/ci.yml`) runs the same two checks automatically on every PR, regardless of target branch, plus every push to `main`, using `lune`/`rojo` versions pinned in that file — a local `brew install lune`/`brew install rojo` tracks whatever's current in Homebrew instead, so if a Lune/Rojo upgrade ever changes behavior, CI and a local run can disagree until `ci.yml`'s pinned versions are bumped to match.
4. `main` has branch protection requiring a PR (not a direct push) and a passing CI run before merging. Repo settings only allow squash-merging and auto-delete the branch afterward, enforcing that step too rather than relying on remembering to do it manually.
5. Prefer reviewing the diff (manually or via the `/code-review` skill) before merging, especially for anything touching `src/server/` — this codebase has already hit real concurrency bugs (shared per-player session state mutated from multiple RemoteEvent handlers/DataStore callbacks) that surfaced only under review, not from casual reading.

**The `dev` branch is not part of this project.** It diverged at the very first commit and contains an unrelated Python OCR-based screen-automation tool (`main.py`, `logger.py`, `ocr_detector.py`) that happens to share this repo by name collision. Don't merge it into or base work off of it.
