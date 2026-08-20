# 5 Purchasable Wings Styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the "Wings" item five distinct, purchasable visual styles (Classic Feathered, Voidtech, Dragon, Demonic, Fae), each independently granting flight, each equippable independently of ownership.

**Architecture:** Extends the existing `GameConstants.ITEMS`/`ITEM_FIELDS`/owned-boolean pattern (already used for FlameTrail/LightTrail) with 4 new items and a new `equippedWings` session field mirroring `equippedCosmetic`. A new `WingsVisualSystem.lua` (same shape as `CosmeticsSystem.lua`) builds each style's wing geometry from stock `Part`/`WedgePart` primitives, welded onto `HumanoidRootPart`. A new `EquipWingsEvent` RemoteEvent, kept separate from `EquipCosmeticEvent` since trail and wings are independent equip slots. `FlightSystem.TryActivate`'s single-field ownership check becomes a check across all five owned-wings fields.

**Tech Stack:** Luau (`--!strict`), Rojo, Lune (headless tests for pure logic), TestEZ (in-Studio tests), stock Roblox `Part`/`WedgePart`/`WeldConstraint`/`Fire` primitives only — no custom Texture/Image/mesh assets.

**Spec:** `docs/superpowers/specs/2026-08-20-wings-styles-design.md`

## Global Constraints

- No custom uploaded Texture/Image/mesh assets anywhere — stock Roblox instances only (matches the spec and this codebase's existing constraint everywhere else).
- Every new/changed field on `Session` must be threaded through `GetDefaultSession`, `ResetProgress`, `PerformRebirth` (`src/shared/GameLogic.lua`) and `loadByUserId`'s field-by-field fallback (`src/server/DataManager.lua`) — a field present in only some of these silently breaks save-compatibility or Reset/Rebirth semantics.
- `Session` is a fixed-field record type under `--!strict`, not an index-signature type — every place that reads/writes a field keyed by a runtime string (equip handlers, item purchase handlers) must use explicit literal branches, not a loop indexing `Session` dynamically. This is an established, repeatedly-documented pattern in this codebase (see `GameLogic.CalculateMazeBonusRate`'s and `EquipCosmeticEvent`'s own comments) — follow it exactly for the new `EquipWingsEvent` handler.
- Pricing (exact, from the spec): Classic Feathered 200pts/200 Robux (existing `Wings` item, price change from 2000), Voidtech 2,000pts/400 Robux, Dragon 20,000pts/600 Robux, Demonic 200,000pts/800 Robux, Fae 2,000,000pts/1,000 Robux (all `DevProductId = 0` placeholders, matching every other item's existing convention).
- Keep the Lune suite (`test/gameLogic.test.luau`) and the TestEZ spec (`src/tests/GameLogic.spec.lua`) in sync — both have their own `session()` test helper; both need the same new fields (CLAUDE.md already states this requirement for any change to either suite).
- Buying a Wings item does **not** auto-equip its visual (matches the existing FlameTrail/LightTrail precedent) — `equippedWings` only changes via the new `EquipWingsEvent`.

---

## Phase 1 — Data model + FlightSystem (PR 1)

Fully verifiable without Roblox Studio — Lune covers every pure-logic change in this phase.

### Task 1: Add the 4 new Wings items to GameConstants, update the base price

**Files:**
- Modify: `src/shared/GameConstants.lua:33-37` (the `ITEMS` table), `:50-54` (`ITEM_FIELDS`)

**Interfaces:**
- Produces: `GameConstants.ITEMS.WingsVoidtech`, `.WingsDragon`, `.WingsDemonic`, `.WingsFae` (each `{Cost: number, RobuxCost: number, DevProductId: number}`); `GameConstants.ITEM_FIELDS.WingsVoidtech = "ownedWingsVoidtech"` etc.

- [ ] **Step 1: Edit the `ITEMS` table**

Replace:
```lua
	ITEMS = {
		Wings = { Cost = 2000, RobuxCost = 200, DevProductId = 0 },
		FlameTrail = { Cost = 750, RobuxCost = 75, DevProductId = 0 },
		LightTrail = { Cost = 750, RobuxCost = 75, DevProductId = 0 },
	},
```
with:
```lua
	-- Wings' 5 styles (see docs/superpowers/specs/2026-08-20-wings-styles-design.md)
	-- are a deliberate escalating price ladder, not flat-per-item like the
	-- trails below -- each style independently grants flight (see
	-- FlightSystem.TryActivate), so owning any one is a complete purchase.
	-- Points scale 10x per tier; Robux scales linearly (+200/tier) rather
	-- than tracking the point curve 1:1, since a strict ratio applied to the
	-- 2,000,000-point top tier would imply an absurd real-money price.
	ITEMS = {
		Wings = { Cost = 200, RobuxCost = 200, DevProductId = 0 },
		WingsVoidtech = { Cost = 2000, RobuxCost = 400, DevProductId = 0 },
		WingsDragon = { Cost = 20000, RobuxCost = 600, DevProductId = 0 },
		WingsDemonic = { Cost = 200000, RobuxCost = 800, DevProductId = 0 },
		WingsFae = { Cost = 2000000, RobuxCost = 1000, DevProductId = 0 },
		FlameTrail = { Cost = 750, RobuxCost = 75, DevProductId = 0 },
		LightTrail = { Cost = 750, RobuxCost = 75, DevProductId = 0 },
	},
```

- [ ] **Step 2: Edit the `ITEM_FIELDS` table**

Replace:
```lua
GameConstants.ITEM_FIELDS = {
	Wings = "ownedWings",
	FlameTrail = "ownedFlameTrail",
	LightTrail = "ownedLightTrail",
}
```
with:
```lua
GameConstants.ITEM_FIELDS = {
	Wings = "ownedWings",
	WingsVoidtech = "ownedWingsVoidtech",
	WingsDragon = "ownedWingsDragon",
	WingsDemonic = "ownedWingsDemonic",
	WingsFae = "ownedWingsFae",
	FlameTrail = "ownedFlameTrail",
	LightTrail = "ownedLightTrail",
}
```

- [ ] **Step 3: Commit**

```bash
git add src/shared/GameConstants.lua
git commit -m "Add 4 new Wings item styles with an escalating price ladder"
```

---

### Task 2: Extend the Session type and GameLogic, with Lune tests

**Files:**
- Modify: `src/shared/GameLogic.lua:13-31` (`Session` type), `:35-55` (`GetDefaultSession`), `:64-75` (`ResetProgress`), `:80-88` (`PerformRebirth`)
- Test: `test/gameLogic.test.luau`

**Interfaces:**
- Consumes: nothing new from earlier tasks.
- Produces: `Session.ownedWingsVoidtech/ownedWingsDragon/ownedWingsDemonic/ownedWingsFae: boolean`, `Session.equippedWings: "None" | "Classic" | "Voidtech" | "Dragon" | "Demonic" | "Fae"`. Every later task that reads/writes `session.equippedWings` uses exactly this 6-value union, and exactly these 4 new boolean field names.

- [ ] **Step 1: Update the Lune test's `session()` helper to include the new fields (failing first)**

In `test/gameLogic.test.luau`, replace the `session()` helper's `base` table (currently ends at `completedMazeWest = false,`) with:
```lua
local function session(overrides: { [string]: any }?)
	local base = {
		score = 0,
		autoClickerCount = 0,
		megaClickerCount = 0,
		clickPowerCount = 0,
		multiplierCount = 0,
		rebirthCount = 0,
		totalClicks = 0,
		useBaseSpeed = true,
		speedSliderPercent = 100,
		ownedWings = false,
		ownedWingsVoidtech = false,
		ownedWingsDragon = false,
		ownedWingsDemonic = false,
		ownedWingsFae = false,
		ownedFlameTrail = false,
		ownedLightTrail = false,
		equippedCosmetic = "None",
		equippedWings = "None",
		completedMazeNorth = false,
		completedMazeSouth = false,
		completedMazeEast = false,
		completedMazeWest = false,
	}
	for key, value in pairs(overrides or {}) do
		base[key] = value
	end
	return base
end
```

- [ ] **Step 2: Extend the existing `ResetProgress`/`PerformRebirth` tests with wings assertions**

In the `"ResetProgress zeroes score and upgrades but preserves clicks/rebirths/settings/items"` test, add to the `before = session({...})` overrides (alongside the existing `ownedWings = true,`):
```lua
		ownedWingsDragon = true,
		equippedWings = "Dragon",
```
and after the existing `assertEqual(after.ownedWings, true, "ownedWings preserved")` line, add:
```lua
	assertEqual(after.ownedWingsDragon, true, "ownedWingsDragon preserved")
	assertEqual(after.equippedWings, "Dragon", "equippedWings preserved")
```

In the `"PerformRebirth does everything ResetProgress does, plus incrementing rebirthCount and clears owned items"` test, add to the `before = session({...})` overrides (alongside `ownedWings = true,`):
```lua
		ownedWingsFae = true,
		equippedWings = "Fae",
```
and after `assertEqual(after.ownedWings, false, "ownedWings cleared")`, add:
```lua
	assertEqual(after.ownedWingsFae, false, "ownedWingsFae cleared")
	assertEqual(after.equippedWings, "None", "equippedWings cleared")
```

- [ ] **Step 3: Run the suite to confirm it fails**

Run: `lune run test/gameLogic.test.luau`
Expected: FAIL — `GetDefaultSession()` won't have the new fields yet, so the "GetDefaultSession returns the documented defaults" test (which loops every key in `session()`) fails with a nil-vs-false mismatch. The two edited tests also fail (`GameLogic.ResetProgress`/`PerformRebirth` don't preserve/clear fields that don't exist on `Session` yet).

- [ ] **Step 4: Update `GameLogic.lua`'s `Session` type**

Replace:
```lua
export type Session = {
	score: number,
	autoClickerCount: number,
	megaClickerCount: number,
	clickPowerCount: number,
	multiplierCount: number,
	rebirthCount: number,
	totalClicks: number,
	useBaseSpeed: boolean,
	speedSliderPercent: number,
	ownedWings: boolean,
	ownedFlameTrail: boolean,
	ownedLightTrail: boolean,
	equippedCosmetic: "None" | "FlameTrail" | "LightTrail",
	completedMazeNorth: boolean,
	completedMazeSouth: boolean,
	completedMazeEast: boolean,
	completedMazeWest: boolean,
}
```
with:
```lua
export type Session = {
	score: number,
	autoClickerCount: number,
	megaClickerCount: number,
	clickPowerCount: number,
	multiplierCount: number,
	rebirthCount: number,
	totalClicks: number,
	useBaseSpeed: boolean,
	speedSliderPercent: number,
	ownedWings: boolean,
	ownedWingsVoidtech: boolean,
	ownedWingsDragon: boolean,
	ownedWingsDemonic: boolean,
	ownedWingsFae: boolean,
	ownedFlameTrail: boolean,
	ownedLightTrail: boolean,
	equippedCosmetic: "None" | "FlameTrail" | "LightTrail",
	equippedWings: "None" | "Classic" | "Voidtech" | "Dragon" | "Demonic" | "Fae",
	completedMazeNorth: boolean,
	completedMazeSouth: boolean,
	completedMazeEast: boolean,
	completedMazeWest: boolean,
}
```

- [ ] **Step 5: Update `GetDefaultSession`**

Replace:
```lua
		ownedWings = false,
		ownedFlameTrail = false,
		ownedLightTrail = false,
		equippedCosmetic = "None",
```
with:
```lua
		ownedWings = false,
		ownedWingsVoidtech = false,
		ownedWingsDragon = false,
		ownedWingsDemonic = false,
		ownedWingsFae = false,
		ownedFlameTrail = false,
		ownedLightTrail = false,
		equippedCosmetic = "None",
		equippedWings = "None",
```

- [ ] **Step 6: Update `ResetProgress`**

Replace:
```lua
	reset.ownedWings = session.ownedWings
	reset.ownedFlameTrail = session.ownedFlameTrail
	reset.ownedLightTrail = session.ownedLightTrail
	reset.equippedCosmetic = session.equippedCosmetic
	return reset
```
with:
```lua
	reset.ownedWings = session.ownedWings
	reset.ownedWingsVoidtech = session.ownedWingsVoidtech
	reset.ownedWingsDragon = session.ownedWingsDragon
	reset.ownedWingsDemonic = session.ownedWingsDemonic
	reset.ownedWingsFae = session.ownedWingsFae
	reset.ownedFlameTrail = session.ownedFlameTrail
	reset.ownedLightTrail = session.ownedLightTrail
	reset.equippedCosmetic = session.equippedCosmetic
	reset.equippedWings = session.equippedWings
	return reset
```

- [ ] **Step 7: Update `PerformRebirth`**

Replace:
```lua
	reset.rebirthCount += 1
	reset.ownedWings = false
	reset.ownedFlameTrail = false
	reset.ownedLightTrail = false
	reset.equippedCosmetic = "None"
	return reset
```
with:
```lua
	reset.rebirthCount += 1
	reset.ownedWings = false
	reset.ownedWingsVoidtech = false
	reset.ownedWingsDragon = false
	reset.ownedWingsDemonic = false
	reset.ownedWingsFae = false
	reset.ownedFlameTrail = false
	reset.ownedLightTrail = false
	reset.equippedCosmetic = "None"
	reset.equippedWings = "None"
	return reset
```

- [ ] **Step 8: Run the suite to confirm it passes**

Run: `lune run test/gameLogic.test.luau`
Expected: PASS — all tests, including the two new assertions added in Step 2.

- [ ] **Step 9: Run the other 3 Lune suites to confirm nothing else broke**

Run: `lune run test/mazeGeometry.test.luau && lune run test/gameHandlers.test.luau && lune run test/neonScript.test.luau`
Expected: PASS (unaffected by this change — sanity check only).

- [ ] **Step 10: Commit**

```bash
git add src/shared/GameLogic.lua test/gameLogic.test.luau
git commit -m "Add 4 wing-ownership fields and equippedWings to Session"
```

---

### Task 3: Keep the TestEZ spec's session() helper in sync

**Files:**
- Modify: `src/tests/GameLogic.spec.lua`

**Interfaces:**
- Consumes: the exact same `Session` field set Task 2 added.

CLAUDE.md's Tech stack section states the Lune and TestEZ suites' test cases must stay in sync when either changes — this file has its own `session()` helper (typed as `GameLogic.Session` per the fix earlier this session that pinned its type to avoid inference-widening), separate from Lune's.

- [ ] **Step 1: Update the `session()` helper's `base` table**

In `src/tests/GameLogic.spec.lua`, find the `local base: GameLogic.Session = {` table inside the `session()` helper. Replace:
```lua
			ownedWings = false,
			ownedFlameTrail = false,
			ownedLightTrail = false,
			equippedCosmetic = "None",
```
with:
```lua
			ownedWings = false,
			ownedWingsVoidtech = false,
			ownedWingsDragon = false,
			ownedWingsDemonic = false,
			ownedWingsFae = false,
			ownedFlameTrail = false,
			ownedLightTrail = false,
			equippedCosmetic = "None",
			equippedWings = "None",
```

- [ ] **Step 2: Mirror the same two test extensions Task 2 made to the Lune suite**

In the `"should zero score and upgrades but preserve clicks/rebirths/settings/items"` test (the `ResetProgress` spec), add the same `ownedWingsDragon = true, equippedWings = "Dragon",` overrides and matching `expect(after.ownedWingsDragon).to.equal(true)` / `expect(after.equippedWings).to.equal("Dragon")` assertions used in Task 2 Step 2, following this file's existing `expect(...).to.equal(...)` TestEZ syntax (not Lune's `assertEqual`).

In the `PerformRebirth` spec, mirror the `ownedWingsFae = true, equippedWings = "Fae",` override and the corresponding cleared-to-`false`/`"None"` assertions.

- [ ] **Step 3: This file can't run under Lune (uses TestEZ's `describe`/`it`/`expect` globals, which Lune doesn't provide) — verify by reading, not running**

Re-read the edited sections and confirm every field name matches Task 2's `Session` type exactly (`ownedWingsDragon`, not `ownedDragonWings` or similar typo) — a mismatch here would only surface live in Studio's TestEZ run, not in CI (CLAUDE.md's Development workflow section documents this file is excluded from the `luau-lsp analyze` CI gate, since TestEZ ships no type definitions for it).

- [ ] **Step 4: Commit**

```bash
git add src/tests/GameLogic.spec.lua
git commit -m "Mirror the new Session wings fields into the TestEZ spec"
```

---

### Task 4: Update DataManager's save-load fallback

**Files:**
- Modify: `src/server/DataManager.lua:56-74` (`loadByUserId`'s field-by-field fallback table)

**Interfaces:**
- Consumes: `Session` fields from Task 2.

Not covered by any Lune test (this function isn't in the Lune-tested surface — it does real `PlayerDataStore:GetAsync`), but skipping it means a save from before this feature shipped would silently `nil` every one of the 5 new fields on load, which would then fail to type-check as booleans/the string union when the loaded table is used as a `Session`. Every existing field already goes through `fallback(result.X, defaultData.X)` — the 5 new ones must too.

- [ ] **Step 1: Add the 5 new fields to the fallback table**

Replace:
```lua
		ownedWings = fallback(result.ownedWings, defaultData.ownedWings),
		ownedFlameTrail = fallback(result.ownedFlameTrail, defaultData.ownedFlameTrail),
		ownedLightTrail = fallback(result.ownedLightTrail, defaultData.ownedLightTrail),
		equippedCosmetic = fallback(result.equippedCosmetic, defaultData.equippedCosmetic),
```
with:
```lua
		ownedWings = fallback(result.ownedWings, defaultData.ownedWings),
		ownedWingsVoidtech = fallback(result.ownedWingsVoidtech, defaultData.ownedWingsVoidtech),
		ownedWingsDragon = fallback(result.ownedWingsDragon, defaultData.ownedWingsDragon),
		ownedWingsDemonic = fallback(result.ownedWingsDemonic, defaultData.ownedWingsDemonic),
		ownedWingsFae = fallback(result.ownedWingsFae, defaultData.ownedWingsFae),
		ownedFlameTrail = fallback(result.ownedFlameTrail, defaultData.ownedFlameTrail),
		ownedLightTrail = fallback(result.ownedLightTrail, defaultData.ownedLightTrail),
		equippedCosmetic = fallback(result.equippedCosmetic, defaultData.equippedCosmetic),
		equippedWings = fallback(result.equippedWings, defaultData.equippedWings),
```

- [ ] **Step 2: Commit**

```bash
git add src/server/DataManager.lua
git commit -m "Fall back the 5 new wings fields when loading a pre-feature save"
```

---

### Task 5: Update FlightSystem's ownership check

**Files:**
- Modify: `src/server/FlightSystem.lua:30-31`

**Interfaces:**
- Consumes: `session.ownedWings/ownedWingsVoidtech/ownedWingsDragon/ownedWingsDemonic/ownedWingsFae` from Task 2.

- [ ] **Step 1: Replace the single-field check with an any-of-five check**

Replace:
```lua
function FlightSystem.TryActivate(player: Player, session: GameLogic.Session): boolean
	if not session.ownedWings then return false end
```
with:
```lua
-- Any of the 5 Wings styles independently grants flight (see
-- docs/superpowers/specs/2026-08-20-wings-styles-design.md) -- explicit
-- per-field checks, not a loop indexing Session by a dynamic key, matching
-- this codebase's established --!strict fixed-record-type reasoning (see
-- GameLogic.CalculateMazeBonusRate's own comment on exactly this pattern).
local function hasAnyWings(session: GameLogic.Session): boolean
	return session.ownedWings
		or session.ownedWingsVoidtech
		or session.ownedWingsDragon
		or session.ownedWingsDemonic
		or session.ownedWingsFae
end

function FlightSystem.TryActivate(player: Player, session: GameLogic.Session): boolean
	if not hasAnyWings(session) then return false end
```

(`hasAnyWings` goes above `FlightSystem.TryActivate`, e.g. right after the `lastFlightAt` table declaration.)

- [ ] **Step 2: Verify via rojo build + luau-lsp (this file has no Lune coverage — uses `game:GetService`, Roblox-only)**

Run:
```bash
rojo build default.project.json -o /tmp/check.rbxlx
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
```
Expected: both succeed with zero diagnostics. Clean up `sourcemap.json`/`globalTypes.d.luau` afterward (not meant to be committed, matching how this repo's own CI generates them fresh each run).

- [ ] **Step 3: Commit**

```bash
git add src/server/FlightSystem.lua
git commit -m "Let any of the 5 Wings styles independently grant flight"
```

---

### Task 6: Phase 1 verification and PR

**Files:** none (verification only)

- [ ] **Step 1: Run every verification command from CLAUDE.md's Development workflow section**

```bash
lune run test/gameLogic.test.luau
lune run test/mazeGeometry.test.luau
lune run test/gameHandlers.test.luau
lune run test/neonScript.test.luau
rojo build default.project.json -o /tmp/check.rbxlx
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
rm -f sourcemap.json globalTypes.d.luau
```
Expected: everything passes, zero diagnostics.

- [ ] **Step 2: Push and open a PR**

```bash
git checkout -b feature/wings-styles-data-model
git push -u origin feature/wings-styles-data-model
gh pr create --title "Add 5-tier Wings data model (resolves part of #71)" --body "Phase 1 of the Wings styles feature (see docs/superpowers/specs/2026-08-20-wings-styles-design.md): 4 new purchasable items, the new equippedWings Session field, DataManager fallback, and FlightSystem's any-of-5 ownership check. No visuals yet -- WingsVisualSystem lands in a follow-up PR."
```

**PR boundary.** This phase is independently mergeable and testable: every new item is purchasable and grants flight, `equippedWings` is tracked, nothing visual has changed yet (every style looks identical to today's invisible Wings until Phase 2 ships).

---

## Phase 2 — WingsVisualSystem + geometry + equip wiring (PR 2)

### Task 7: Add the EquipWingsEvent RemoteEvent

**Files:**
- Modify: `default.project.json:27-29` (right after `EquipCosmeticEvent`)

- [ ] **Step 1: Add the new RemoteEvent declaration**

In `default.project.json`, after:
```json
      "EquipCosmeticEvent": {
        "$className": "RemoteEvent"
      },
```
add:
```json
      "EquipWingsEvent": {
        "$className": "RemoteEvent"
      },
```

- [ ] **Step 2: Verify the project still builds**

Run: `rojo build default.project.json -o /tmp/check.rbxlx`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add default.project.json
git commit -m "Declare the EquipWingsEvent RemoteEvent"
```

---

### Task 8: Create WingsVisualSystem.lua

**Files:**
- Create: `src/server/WingsVisualSystem.lua`

**Interfaces:**
- Consumes: `GameLogic.Session.equippedWings` (Task 2), `SessionStoreType.SessionStoreModule` (existing).
- Produces: `WingsVisualSystem.ApplyEquippedWings(player: Player, session: GameLogic.Session)`, `WingsVisualSystem.Start(sessionStore: SessionStoreModule)` — exact names/signatures Task 9's `GameService.server.lua` wiring depends on.

This mirrors `src/server/CosmeticsSystem.lua`'s shape (`clearX`/`buildX`/`ApplyEquippedX`/`Start`) but geometry instead of trails. Every wing style shares one low-level `weldPart` helper and is built by a per-style "one side" function called twice (mirrored) — the same "one function, parameterized, called per side" pattern `MapBuilder.lua`'s maze-wing builder already established, not five one-off implementations.

- [ ] **Step 1: Write the file**

```lua
--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameLogic = require(Shared:WaitForChild("GameLogic"))
local SessionStoreType = require(script.Parent:WaitForChild("SessionStore"))
type SessionStoreModule = SessionStoreType.SessionStoreModule

local WingsVisualSystem = {}

-- Every style's parts (both sides) live under one Folder on the character's
-- HumanoidRootPart -- clearing on re-equip/respawn is just destroying this
-- one Folder, rather than tracking a fixed list of individual instance
-- names the way CosmeticsSystem.lua has to (that file's trail/particle/
-- fire/light instances are named individually since they're not grouped
-- under a single container; wings don't need that since every wing part is
-- generated fresh from the same style table every time, nothing persists
-- individual identity across a re-equip).
local WINGS_FOLDER_NAME = "CosmeticWings"

-- Welds `part` rigidly onto `rootPart` at part's current CFrame (must be set
-- BEFORE calling this -- WeldConstraint locks in whatever relative offset
-- exists between the two parts at the moment it's created, so setting the
-- CFrame first is what determines the part's fixed position on the
-- character afterward). Every wing part goes through this, not just
-- Attachments (unlike CosmeticsSystem's trail, which only ever needs
-- Attachments -- a Trail's shape comes from Attachment motion history, but
-- a wing is real welded geometry).
local function weldPart(part: BasePart, rootPart: BasePart, folder: Folder)
	part.Anchored = false
	part.CanCollide = false
	part.CastShadow = false
	part.Locked = true
	part.Parent = folder

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = part
end

-- Classic Feathered: 5 layered feathers per side, fanning outward/upward
-- from a shoulder point, tapering shorter toward the outer edge. White/
-- cream with a thin gold Neon trim line per feather.
local function buildFeatheredSide(rootPart: BasePart, folder: Folder, side: number)
	local featherCount = 5
	for i = 1, featherCount do
		local t = (i - 1) / (featherCount - 1)
		local spreadDeg = 20 + t * 50
		local length = 2.2 - t * 0.6
		local localCFrame = CFrame.new(side * 0.3, 0.8, -0.3)
			* CFrame.Angles(0, 0, math.rad(side * spreadDeg))
			* CFrame.Angles(math.rad(-15 - t * 10), 0, 0)

		local feather = Instance.new("WedgePart")
		feather.Name = "Feather" .. i
		feather.Size = Vector3.new(0.15, 0.5, length)
		feather.Color = Color3.fromHex("f4f0e6")
		feather.Material = Enum.Material.SmoothPlastic
		feather.CFrame = rootPart.CFrame * localCFrame
		weldPart(feather, rootPart, folder)

		local trim = Instance.new("Part")
		trim.Name = "FeatherTrim" .. i
		trim.Size = Vector3.new(0.05, 0.05, length)
		trim.Color = Color3.fromHex("d4af37")
		trim.Material = Enum.Material.Neon
		trim.CFrame = feather.CFrame
		weldPart(trim, rootPart, folder)
	end
end

-- Voidtech: 3 angular blocky panels per side, glowing purple (#6c5ce7,
-- this game's own existing accent color) Neon seam line per panel.
local function buildVoidtechSide(rootPart: BasePart, folder: Folder, side: number)
	local panelCount = 3
	for i = 1, panelCount do
		local t = (i - 1) / (panelCount - 1)
		local spreadDeg = 15 + t * 45
		local length = 2.5 - t * 0.8
		local localCFrame = CFrame.new(side * 0.3, 0.9 - t * 0.3, -0.3)
			* CFrame.Angles(0, 0, math.rad(side * spreadDeg))

		local panel = Instance.new("Part")
		panel.Name = "Panel" .. i
		panel.Size = Vector3.new(0.2, 0.9, length)
		panel.Color = Color3.fromHex("1e1e2f")
		panel.Material = Enum.Material.SmoothPlastic
		panel.CFrame = rootPart.CFrame * localCFrame
		weldPart(panel, rootPart, folder)

		local seam = Instance.new("Part")
		seam.Name = "PanelSeam" .. i
		seam.Size = Vector3.new(0.06, 0.06, length)
		seam.Color = Color3.fromHex("6c5ce7")
		seam.Material = Enum.Material.Neon
		seam.CFrame = panel.CFrame * CFrame.new(0, 0.45, 0)
		weldPart(seam, rootPart, folder)
	end
end

-- Dragon: a jagged fan of 4 dark wedges per side suggesting a solid
-- reptilian membrane -- deliberately a different silhouette/material from
-- Demonic below (solid wedges vs. sparse bone spines), not a recolor of
-- the same shape.
local function buildDragonSide(rootPart: BasePart, folder: Folder, side: number)
	local spineCount = 4
	for i = 1, spineCount do
		local t = (i - 1) / (spineCount - 1)
		local spreadDeg = 10 + t * 65
		local length = 1.8 + t * 1.4
		local localCFrame = CFrame.new(side * 0.3, 0.7, -0.3)
			* CFrame.Angles(0, 0, math.rad(side * spreadDeg))
			* CFrame.Angles(math.rad(-10 - t * 25), 0, 0)

		local spine = Instance.new("WedgePart")
		spine.Name = "MembraneSpine" .. i
		spine.Size = Vector3.new(0.12, 0.35, length)
		spine.Color = Color3.fromHex("3a0a0a")
		spine.Material = Enum.Material.SmoothPlastic
		spine.CFrame = rootPart.CFrame * localCFrame
		weldPart(spine, rootPart, folder)
	end
end

-- Demonic: 3 sparse bone spines per side (not a solid membrane, unlike
-- Dragon above), a glowing red Neon ball at each tip, and a stock
-- Instance.new("Fire") at each tip for trailing embers -- same stock
-- primitive CosmeticsSystem.lua's FlameTrail already relies on for exactly
-- this reason (no custom Texture/Image assets).
local function buildDemonicSide(rootPart: BasePart, folder: Folder, side: number)
	local spineCount = 3
	for i = 1, spineCount do
		local t = (i - 1) / (spineCount - 1)
		local spreadDeg = 15 + t * 60
		local length = 2.0 + t * 1.0
		local localCFrame = CFrame.new(side * 0.3, 0.75, -0.3)
			* CFrame.Angles(0, 0, math.rad(side * spreadDeg))
			* CFrame.Angles(math.rad(-15 - t * 20), 0, 0)

		local spine = Instance.new("Part")
		spine.Name = "BoneSpine" .. i
		spine.Size = Vector3.new(0.1, 0.1, length)
		spine.Color = Color3.fromHex("0d0d0d")
		spine.Material = Enum.Material.SmoothPlastic
		spine.CFrame = rootPart.CFrame * localCFrame
		weldPart(spine, rootPart, folder)

		local glow = Instance.new("Part")
		glow.Name = "BoneSpineGlow" .. i
		glow.Shape = Enum.PartType.Ball
		glow.Size = Vector3.new(0.15, 0.15, 0.15)
		glow.Color = Color3.fromHex("ff2222")
		glow.Material = Enum.Material.Neon
		glow.CFrame = spine.CFrame * CFrame.new(0, 0, -length / 2)
		weldPart(glow, rootPart, folder)

		local embers = Instance.new("Fire")
		embers.Name = "BoneSpineEmbers" .. i
		embers.Size = 1.2
		embers.Heat = 4
		embers.Parent = glow
	end
end

-- Fae: 2 small translucent lobes per side (4 total, dragonfly-style),
-- high transparency + Neon material for a delicate glowing look --
-- deliberately a different silhouette/material from the other 3 "big
-- bold wings" styles.
local function buildFaeSide(rootPart: BasePart, folder: Folder, side: number)
	local lobes = {
		{ y = 0.9, spreadDeg = 25, length = 1.1 },
		{ y = 0.5, spreadDeg = 45, length = 0.8 },
	}
	for i, lobe in ipairs(lobes) do
		local localCFrame = CFrame.new(side * 0.25, lobe.y, -0.2)
			* CFrame.Angles(0, 0, math.rad(side * lobe.spreadDeg))

		local panel = Instance.new("Part")
		panel.Name = "Lobe" .. i
		panel.Size = Vector3.new(0.03, 0.8, lobe.length)
		panel.Color = Color3.fromHex("a29bfe")
		panel.Material = Enum.Material.Neon
		panel.Transparency = 0.55
		panel.CFrame = rootPart.CFrame * localCFrame
		weldPart(panel, rootPart, folder)
	end
end

-- Dispatch table keyed by the same string union as Session.equippedWings
-- (minus "None", which correctly finds nothing and no-ops below) -- every
-- style builds both sides via one shared per-side function, mirrored by
-- sign (-1 left, 1 right), not five one-off left+right implementations.
local SIDE_BUILDERS: { [string]: (BasePart, Folder, number) -> () } = {
	Classic = buildFeatheredSide,
	Voidtech = buildVoidtechSide,
	Dragon = buildDragonSide,
	Demonic = buildDemonicSide,
	Fae = buildFaeSide,
}

local function clearWings(rootPart: BasePart)
	local existing = rootPart:FindFirstChild(WINGS_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

-- Applies session.equippedWings to a player's current character, if any.
-- This is the only place wing geometry gets attached -- called from
-- CharacterAdded below, and directly from GameService.server.lua's
-- PurchaseItemEvent/EquipWingsEvent handlers (already inside
-- SessionStore.With) so an already-spawned character updates immediately
-- without needing to respawn -- same pattern CosmeticsSystem.
-- ApplyEquippedCosmetic already establishes.
function WingsVisualSystem.ApplyEquippedWings(player: Player, session: GameLogic.Session)
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then return end

	clearWings(rootPart)

	local buildSide = SIDE_BUILDERS[session.equippedWings]
	if not buildSide then return end -- "None"

	local folder = Instance.new("Folder")
	folder.Name = WINGS_FOLDER_NAME
	folder.Parent = rootPart

	buildSide(rootPart, folder, -1)
	buildSide(rootPart, folder, 1)
end

-- Wings don't survive a respawn (a fresh character has no welded parts at
-- all), so reapply on every character (re)creation -- same pattern
-- CosmeticsSystem.Start/MovementSystem.Start already use.
function WingsVisualSystem.Start(sessionStore: SessionStoreModule)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local session = sessionStore.Peek(player.UserId)
			if session then
				WingsVisualSystem.ApplyEquippedWings(player, session)
			end
		end)
	end)
end

return WingsVisualSystem
```

- [ ] **Step 2: Verify via rojo build + luau-lsp**

Run:
```bash
rojo build default.project.json -o /tmp/check.rbxlx
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
rm -f sourcemap.json globalTypes.d.luau
```
Expected: both succeed with zero diagnostics.

- [ ] **Step 3: Commit**

```bash
git add src/server/WingsVisualSystem.lua
git commit -m "Add WingsVisualSystem with geometry for all 5 wing styles"
```

---

### Task 9: Wire EquipWingsEvent and WingsVisualSystem.Start into GameService

**Files:**
- Modify: `src/server/GameService.server.lua:1-26` (requires/RemoteEvent locals), and the block right after the existing `EquipCosmeticEvent.OnServerEvent:Connect(...)` handler, and the `.Start(...)` calls near the bottom of the file (alongside `CosmeticsSystem.Start(SessionStore)`)

**Interfaces:**
- Consumes: `WingsVisualSystem.ApplyEquippedWings`/`.Start` (Task 8), `EquipWingsEvent` (Task 7), `session.equippedWings`/`ownedWingsX` (Task 2).

- [ ] **Step 1: Add the require and RemoteEvent local**

After:
```lua
local CosmeticsSystem = require(script.Parent:WaitForChild("CosmeticsSystem"))
```
add:
```lua
local WingsVisualSystem = require(script.Parent:WaitForChild("WingsVisualSystem"))
```

After:
```lua
local EquipCosmeticEvent = ReplicatedStorage:WaitForChild("EquipCosmeticEvent")
```
add:
```lua
local EquipWingsEvent = ReplicatedStorage:WaitForChild("EquipWingsEvent")
```

- [ ] **Step 2: Add the EquipWingsEvent handler**

Directly after the existing `EquipCosmeticEvent.OnServerEvent:Connect(function(player, cosmeticId) ... end)` handler's closing `end)`, add:
```lua
-- [SERVER] Handle switching which Wings style (if any) is equipped.
-- Explicit per-value branches (not a generic loop indexing Session by a
-- dynamic field name), same reasoning as EquipCosmeticEvent above --
-- Session is a fixed-field record type under --!strict. Each branch checks
-- ownership of that specific style before allowing the switch.
EquipWingsEvent.OnServerEvent:Connect(function(player, wingsId)
	SessionStore.With(player.UserId, function(session)
		-- Already equipped -- also this handler's debounce, same idiom as
		-- EquipCosmeticEvent's own "already equipped" guard.
		if wingsId == session.equippedWings then return end

		if wingsId == "None" then
			session.equippedWings = "None"
		elseif wingsId == "Classic" and session.ownedWings then
			session.equippedWings = "Classic"
		elseif wingsId == "Voidtech" and session.ownedWingsVoidtech then
			session.equippedWings = "Voidtech"
		elseif wingsId == "Dragon" and session.ownedWingsDragon then
			session.equippedWings = "Dragon"
		elseif wingsId == "Demonic" and session.ownedWingsDemonic then
			session.equippedWings = "Demonic"
		elseif wingsId == "Fae" and session.ownedWingsFae then
			session.equippedWings = "Fae"
		else
			return
		end

		WingsVisualSystem.ApplyEquippedWings(player, session)
		syncPlayer(player)
	end)
end)
```

- [ ] **Step 3: Start WingsVisualSystem alongside CosmeticsSystem**

After:
```lua
-- Start Cosmetics System (re-applies the equipped trail on every character (re)spawn)
CosmeticsSystem.Start(SessionStore)
```
add:
```lua

-- Start Wings Visual System (re-applies the equipped wings on every character (re)spawn)
WingsVisualSystem.Start(SessionStore)
```

- [ ] **Step 4: Verify via rojo build + luau-lsp**

Run:
```bash
rojo build default.project.json -o /tmp/check.rbxlx
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
rm -f sourcemap.json globalTypes.d.luau
```
Expected: both succeed with zero diagnostics.

- [ ] **Step 5: Commit**

```bash
git add src/server/GameService.server.lua
git commit -m "Wire EquipWingsEvent and WingsVisualSystem into GameService"
```

---

### Task 10: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (the Architecture bullet list, alongside the existing `CosmeticsSystem.lua`/`FlightSystem.lua` bullets)

- [ ] **Step 1: Add a `WingsVisualSystem.lua` bullet**

Insert a new bullet after the existing `src/server/CosmeticsSystem.lua` bullet, in the same style:

```markdown
- `src/server/WingsVisualSystem.lua` — the only place wing geometry gets attached, same shape as `CosmeticsSystem.lua`. `ApplyEquippedWings(player, session)` clears any existing wing parts on `HumanoidRootPart` (one `Folder`, not a fixed-name list -- every wing part is regenerated fresh from the current style on every equip/respawn, nothing persists individual identity across a re-equip), then (if `session.equippedWings ~= "None"`) builds that style's geometry via a shared per-side helper called twice (mirrored left/right) -- the same "one function, parameterized, called per side/direction" pattern `MapBuilder.lua`'s maze-wing builder already established. All 5 styles (Classic Feathered, Voidtech, Dragon, Demonic, Fae) are stock `Part`/`WedgePart`/`WeldConstraint` primitives only, no custom Texture/Image/mesh assets -- Demonic also uses a stock `Instance.new("Fire")` for trailing embers, the same primitive `CosmeticsSystem`'s FlameTrail already relies on. `Start` reapplies on every `CharacterAdded`; `GameService`'s `PurchaseItemEvent`/`EquipWingsEvent` handlers also call it directly (already inside `SessionStore.With`) so an already-spawned character updates without needing to respawn. `FlightSystem.TryActivate`'s ownership check now covers all 5 owned-wings fields (any one independently grants flight), not just the original `Wings` item -- see `docs/superpowers/specs/2026-08-20-wings-styles-design.md` for the full design.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document WingsVisualSystem.lua in CLAUDE.md"
```

---

### Task 11: Phase 2 verification and PR

**Files:** none (verification only)

- [ ] **Step 1: Run every verification command**

```bash
lune run test/gameLogic.test.luau
lune run test/mazeGeometry.test.luau
lune run test/gameHandlers.test.luau
lune run test/neonScript.test.luau
rojo build default.project.json -o /tmp/check.rbxlx
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
rm -f sourcemap.json globalTypes.d.luau
```
Expected: everything passes, zero diagnostics.

- [ ] **Step 2: Manual Studio check (this phase is inherently visual — no automated test can verify wing geometry actually looks right)**

In Studio: give a test session `ownedWingsDragon = true` (or buy it once Phase 1's item purchase path is live), fire `EquipWingsEvent:FireServer("Dragon")` from the command bar, confirm wing geometry appears welded to the character and moves with it. Repeat for all 5 styles including `"Classic"`. Confirm flight still works when only a non-base style (e.g. `ownedWingsFae` alone, no `ownedWings`) is owned.

- [ ] **Step 3: Push and open a PR**

```bash
git checkout -b feature/wings-styles-visuals
git push -u origin feature/wings-styles-visuals
gh pr create --title "Add WingsVisualSystem: geometry for all 5 Wings styles (resolves part of #71)" --body "Phase 2 of the Wings styles feature (see docs/superpowers/specs/2026-08-20-wings-styles-design.md, and PR for Phase 1). New WingsVisualSystem.lua builds all 5 styles from stock Part/WedgePart/WeldConstraint primitives, wired via a new EquipWingsEvent. No client UI yet -- equip only testable via command bar/RemoteEvent until Phase 3 ships the Shop cards."
```

**PR boundary.** Needs your own Studio verification before merge, same as every other visual/creative change this session — flag it explicitly and wait for confirmation, don't merge on green CI alone.

---

## Phase 3 — Client UI (PR 3)

### Task 12: Shop UI for the 4 new items + wings equip toggle

**Files:**
- Modify: `src/client/init.client.lua:1-25` (RemoteEvent locals), `:436-511` (`ITEM_DISPLAY`/`itemRows` construction), `:945-978` (the `SyncState` handler's item-row update loop)

**Interfaces:**
- Consumes: `EquipWingsEvent` (Task 7), `session.equippedWings`/`ownedWingsX` (Task 2).

The client's `ITEM_DISPLAY` currently has a boolean `Cosmetic` flag that only ever meant "show an Equip button, fire `EquipCosmeticEvent`." Generalizing this to `EquipGroup: "Trail" | "Wings" | nil` lets Wings items get their own independent Equip button/RemoteEvent/state without duplicating the whole item-card-building loop.

- [ ] **Step 1: Add the `EquipWingsEvent` client-side local**

After:
```lua
local EquipCosmeticEvent = ReplicatedStorage:WaitForChild("EquipCosmeticEvent")
```
add:
```lua
local EquipWingsEvent = ReplicatedStorage:WaitForChild("EquipWingsEvent")
```

- [ ] **Step 2: Replace `lastKnownEquipped`'s declaration with two tracked equip states**

Replace:
```lua
local lastKnownEquipped: "None" | "FlameTrail" | "LightTrail" = "None"
local ownedWings = false
```
with:
```lua
local lastKnownEquippedTrail: "None" | "FlameTrail" | "LightTrail" = "None"
local lastKnownEquippedWings: "None" | "Classic" | "Voidtech" | "Dragon" | "Demonic" | "Fae" = "None"
local ownedWings = false
```

- [ ] **Step 3: Replace `ITEM_DISPLAY` with the `EquipGroup` field and the 4 new entries**

Replace:
```lua
local ITEM_DISPLAY = {
	{ Id = "Wings", Name = "Wings", Description = "Grants a short flight burst -- press Space while airborne.", Cosmetic = false },
	{ Id = "FlameTrail", Name = "Flame Trail", Description = "A fiery trail behind you as you move.", Cosmetic = true },
	{ Id = "LightTrail", Name = "Light Trail", Description = "A glowing light trail behind you as you move.", Cosmetic = true },
}
```
with:
```lua
local ITEM_DISPLAY = {
	{ Id = "Wings", Name = "Wings -- Classic Feathered", Description = "Grants a short flight burst -- press Space while airborne.", EquipGroup = "Wings", EquipId = "Classic" },
	{ Id = "WingsVoidtech", Name = "Wings -- Voidtech", Description = "Glowing mechanical wings. Grants flight.", EquipGroup = "Wings", EquipId = "Voidtech" },
	{ Id = "WingsDragon", Name = "Wings -- Dragon", Description = "Dark reptilian membrane wings. Grants flight.", EquipGroup = "Wings", EquipId = "Dragon" },
	{ Id = "WingsDemonic", Name = "Wings -- Demonic", Description = "Bone wings wreathed in embers. Grants flight.", EquipGroup = "Wings", EquipId = "Demonic" },
	{ Id = "WingsFae", Name = "Wings -- Fae", Description = "Small, delicate, glowing wings. Grants flight.", EquipGroup = "Wings", EquipId = "Fae" },
	{ Id = "FlameTrail", Name = "Flame Trail", Description = "A fiery trail behind you as you move.", EquipGroup = "Trail", EquipId = "FlameTrail" },
	{ Id = "LightTrail", Name = "Light Trail", Description = "A glowing light trail behind you as you move.", EquipGroup = "Trail", EquipId = "LightTrail" },
}
```

(`EquipId` is what actually gets sent to the RemoteEvent — for Wings it's the style name the server's `equippedWings` field uses, e.g. `"Classic"`, distinct from the shop item id `"Wings"`; for trails `EquipId` matches `Id` exactly, same as today.)

- [ ] **Step 4: Replace the `if item.Cosmetic then` block and the `table.insert(itemRows, ...)` call**

Replace:
```lua
	local equipButton = nil
	if item.Cosmetic then
		equipButton = makeButton(buttonsRow, "Equip", UDim2.new(0, UPGRADE_BUTTON_WIDTH, 0, 36), COLOR_PANEL)
		equipButton.MouseButton1Click:Connect(function()
			-- Toggle: equipping the already-equipped cosmetic unequips it
			-- (back to "None") instead of being a no-op -- lastKnownEquipped
			-- is updated every SyncState tick, see below.
			EquipCosmeticEvent:FireServer(if lastKnownEquipped == item.Id then "None" else item.Id)
		end)
	end

	table.insert(itemRows, {
		Id = item.Id,
		Field = GameConstants.ITEM_FIELDS[item.Id],
		Cost = itemConstants.Cost,
		PtsButton = ptsButton,
		OwnedLabel = ownedLabel,
		EquipButton = equipButton,
	})
```
with:
```lua
	local equipButton = nil
	if item.EquipGroup then
		equipButton = makeButton(buttonsRow, "Equip", UDim2.new(0, UPGRADE_BUTTON_WIDTH, 0, 36), COLOR_PANEL)
		equipButton.MouseButton1Click:Connect(function()
			-- Toggle: equipping the already-equipped style/trail unequips it
			-- (back to "None") instead of being a no-op -- lastKnownEquipped*
			-- is updated every SyncState tick, see below. Each group fires
			-- its own RemoteEvent -- a trail and wings are independent equip
			-- slots, equipping one never affects the other.
			if item.EquipGroup == "Wings" then
				EquipWingsEvent:FireServer(if lastKnownEquippedWings == item.EquipId then "None" else item.EquipId)
			else
				EquipCosmeticEvent:FireServer(if lastKnownEquippedTrail == item.EquipId then "None" else item.EquipId)
			end
		end)
	end

	table.insert(itemRows, {
		Id = item.Id,
		EquipGroup = item.EquipGroup,
		EquipId = item.EquipId,
		Field = GameConstants.ITEM_FIELDS[item.Id],
		Cost = itemConstants.Cost,
		PtsButton = ptsButton,
		OwnedLabel = ownedLabel,
		EquipButton = equipButton,
	})
```

- [ ] **Step 5: Update the `SyncState` handler**

Replace:
```lua
	lastKnownEquipped = state.equippedCosmetic
	ownedWings = state.ownedWings
```
with:
```lua
	lastKnownEquippedTrail = state.equippedCosmetic
	lastKnownEquippedWings = state.equippedWings
	ownedWings = state.ownedWings or state.ownedWingsVoidtech or state.ownedWingsDragon or state.ownedWingsDemonic or state.ownedWingsFae
```

Then, in the `for _, row in ipairs(itemRows) do` loop, replace:
```lua
		if row.EquipButton then
			local isEquipped = lastKnownEquipped == row.Id
```
with:
```lua
		if row.EquipButton then
			local isEquipped = if row.EquipGroup == "Wings"
				then lastKnownEquippedWings == row.EquipId
				else lastKnownEquippedTrail == row.EquipId
```

(The rest of that `if row.EquipButton then ... end` block — the `Active`/`AutoButtonColor`/`Text`/`BackgroundColor3` assignments — is unchanged; it only reads the already-computed `isEquipped`/`owned` locals.)

- [ ] **Step 6: Verify via rojo build + luau-lsp**

Run:
```bash
rojo build default.project.json -o /tmp/check.rbxlx
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
rm -f sourcemap.json globalTypes.d.luau
```
Expected: both succeed with zero diagnostics.

- [ ] **Step 7: Commit**

```bash
git add src/client/init.client.lua
git commit -m "Add Shop cards and equip toggle for the 4 new Wings styles"
```

---

### Task 13: Phase 3 verification and PR

**Files:** none (verification only)

- [ ] **Step 1: Run every verification command**

```bash
lune run test/gameLogic.test.luau
lune run test/mazeGeometry.test.luau
lune run test/gameHandlers.test.luau
lune run test/neonScript.test.luau
rojo build default.project.json -o /tmp/check.rbxlx
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
rm -f sourcemap.json globalTypes.d.luau
```
Expected: everything passes, zero diagnostics.

- [ ] **Step 2: Manual Studio check**

In Studio, open the Shop: confirm all 5 Wings cards show with the correct prices (200/2,000/20,000/200,000/2,000,000 points), confirm buying one updates its card to "Owned" without auto-equipping, confirm the Equip button toggles correctly and is independent of the trail Equip buttons (equip a trail and a Wings style simultaneously, confirm both stay equipped), confirm the previously-existing FlameTrail/LightTrail equip behavior is completely unchanged.

- [ ] **Step 3: Push and open a PR**

```bash
git checkout -b feature/wings-styles-client-ui
git push -u origin feature/wings-styles-client-ui
gh pr create --title "Add Shop UI for the 4 new Wings styles (resolves #71)" --body "Phase 3 (final) of the Wings styles feature -- see docs/superpowers/specs/2026-08-20-wings-styles-design.md and the two prior PRs. Adds Shop cards and an independent Equip toggle for Wings, generalizing ITEM_DISPLAY's old boolean Cosmetic flag into an EquipGroup so trail and wings equip state stay independent."
```

**PR boundary.** Needs your own Studio verification before merge, same as every other visual/creative change this session. Once merged, close issue #71 referencing all 3 PRs.

---

## Self-Review Notes

- **Spec coverage:** every section of the spec (data model, visual attachment, equip flow, client UI, pricing) maps to a task above. The spec's own callout that `DataManager.lua`'s fallback needed updating (a real gap the spec's Architecture section didn't explicitly list) is covered by Task 4.
- **Type consistency:** `equippedWings`'s union (`"None" | "Classic" | "Voidtech" | "Dragon" | "Demonic" | "Fae"`) is identical everywhere it appears — `Session` type (Task 2), `WingsVisualSystem`'s `SIDE_BUILDERS` keys (Task 8), `GameService`'s `EquipWingsEvent` handler branches (Task 9), and the client's `lastKnownEquippedWings` type annotation (Task 12). `ApplyEquippedWings`/`Start`'s signatures (Task 8) match exactly how Task 9 calls them.
- **Pricing correction caught during self-review:** the Global Constraints section's first draft had a typo pricing Fae at "2,000,000... 1,000,000" Robux — corrected to the spec's actual 1,000 Robux figure.
