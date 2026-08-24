# Additional Wings styles for purchase

Resolves #71.

## Context

The current "Wings" item (`GameConstants.ITEMS.Wings`, `session.ownedWings`)
grants the flight ability (`FlightSystem.TryActivate`) but has **no visual
model at all** — no wing geometry is ever attached to the character. This
was confirmed by grepping `src/server/` for any wing-shaped `Instance`
construction: none exists. So "additional Wings styles" isn't a re-skin of
something that exists — it's building wing geometry from scratch for the
first time, for every style including the current one.

Five total visual styles, agreed through discussion:

1. **Classic Feathered** — the existing "Wings" item, now with a visual
   for the first time. White/cream, layered feather fan, thin gold trim.
2. **Voidtech** (new) — angular blocky mechanical panels with glowing
   purple (`#6c5ce7`) Neon seam lines, tying directly into this game's
   existing accent color used everywhere else (UI, portal signs).
3. **Dragon** (new) — a jagged fan of dark wedges suggesting a solid
   reptilian membrane, deep red/black.
4. **Demonic** (new) — visually distinct from Dragon, not a recolor of the
   same shape: sparse jagged **bone/skeletal** spines (not a solid
   membrane) wreathed in dark smoke, black with glowing red accents, plus
   small ember/`Fire` particles trailing off the spines. Matches how City
   of Heroes' own wing catalog treats "burned/bone" as a separate category
   from "dragon" — researched as a reference during design.
5. **Fae** (new) — small, translucent, double-lobed (four-wing,
   dragonfly-style) panels, high transparency + Neon material for a
   delicate glowing look, distinct in silhouette/material from the other
   three "big bold wings" styles.

Every style is built from stock Roblox primitives only (`Part`,
`WedgePart`, `Fire`, `ParticleEmitter`) — no custom Texture/Image/mesh
uploads, the same constraint this codebase already holds to everywhere else
(client's Unicode nav glyphs, the portal signs' neon tubes,
`CosmeticsSystem`'s trail effects).

## Decisions made during discussion

- **Ownership model**: "own multiple, equip one" — same pattern as
  FlameTrail/LightTrail, not a single exclusive lifetime choice.
- **Ability vs. cosmetic**: each of the 5 Wings items independently grants
  the flight ability (not just the base one) — buying *any* Wings item is a
  complete, standalone purchase. This is the bigger of the two options
  considered; the alternative (new styles as pure cosmetic skins requiring
  the base item first) was rejected in favor of every purchase being
  self-contained.
- **Auto-equip**: buying a Wings item does **not** auto-equip its visual —
  matches the existing, already-documented FlameTrail/LightTrail precedent
  ("a player may own both and want to keep their current pick").
- **Pricing**: a deliberate escalating tier, not flat-per-item like the
  existing trails. Points scale 10x per tier; Robux scales linearly
  (+200/tier) rather than tracking the point curve 1:1, since a strict
  10:1 ratio applied to a 2,000,000-point top tier would imply an absurd
  real-money price:

  | Style | Points | Robux |
  |---|---|---|
  | Classic Feathered | 200 | 200 |
  | Voidtech | 2,000 | 400 |
  | Dragon | 20,000 | 600 |
  | Demonic | 200,000 | 800 |
  | Fae | 2,000,000 | 1,000 |

  Note this **changes** the existing live Classic Feathered/base Wings
  price from 2000→200 points (200 Robux is new — the old item had no
  RobuxCost tier distinct from its old 2000-point price's own 10:1-derived
  200 Robux, so this Robux number is unchanged, only the point cost drops).

## Architecture

### Data model (`src/shared/GameConstants.lua`, `src/shared/GameLogic.lua`)

- `GameConstants.ITEMS`: `Wings` (existing key, cost updated to
  `{Cost = 200, RobuxCost = 200, DevProductId = 0}`), plus three new
  entries `WingsVoidtech`, `WingsDragon`, `WingsDemonic`, `WingsFae` with
  the costs above (`DevProductId = 0` placeholders, matching every other
  item's existing convention until real Developer Products are created).
- `GameConstants.ITEM_FIELDS`: `WingsVoidtech -> ownedWingsVoidtech`,
  `WingsDragon -> ownedWingsDragon`, `WingsDemonic -> ownedWingsDemonic`,
  `WingsFae -> ownedWingsFae` (existing `Wings -> ownedWings` unchanged).
- `GameLogic.Session` type: adds `ownedWingsVoidtech`, `ownedWingsDragon`,
  `ownedWingsDemonic`, `ownedWingsFae` (booleans, defaulting `false` like
  `ownedWings` already does) and a new
  `equippedWings: "None" | "Classic" | "Voidtech" | "Dragon" | "Demonic" | "Fae"`
  field (defaulting `"None"`, mirroring `equippedCosmetic`'s exact shape).
  `GetDefaultSession`/`ResetProgress` include it the same way
  `equippedCosmetic` already is (preserved across an ordinary Reset,
  cleared on Rebirth alongside the other owned-item fields).
- `FlightSystem.TryActivate`'s ownership check changes from
  `if not session.ownedWings then return false end` to checking all five
  fields explicitly (`session.ownedWings or session.ownedWingsVoidtech or
  ...`) — explicit per-field checks, not a loop indexing `Session` by a
  dynamic key, matching this codebase's established `--!strict`
  fixed-record-type reasoning (see `GameLogic.CalculateMazeBonusRate`'s own
  comment on exactly this pattern).

### Visual attachment (`src/server/WingsVisualSystem.lua`, new)

Same shape as `CosmeticsSystem.lua`:
- `ApplyEquippedWings(player, session)` clears any existing wing instances
  on `HumanoidRootPart` by fixed name, then (if `equippedWings ~= "None"`)
  builds that style's geometry and attaches it via `WeldConstraint` to
  `HumanoidRootPart` — the same attachment point every other cosmetic
  system already uses.
- `Start(sessionStore)` reapplies on every `CharacterAdded`, same pattern
  as `CosmeticsSystem.Start`/`MovementSystem.Start`.
- Geometry: one shared parametric helper per style (e.g.
  `buildFeatheredWing(side, ...)`), called twice with mirrored X-offsets
  for left/right — reusing the same "one function, parameterized, called
  per side/direction" pattern `MapBuilder.lua`'s maze-wing builder already
  established, not five one-off implementations. Each wing is a small fan
  of `Part`/`WedgePart` segments radiating from a shoulder-height weld
  point, oriented via the same `CFrame.lookAt`-between-two-points technique
  already proven for the portal signs' neon tubes.

### Equip flow

- New RemoteEvent `EquipWingsEvent`, declared in `default.project.json`
  alongside the existing ones — kept **separate** from `EquipCosmeticEvent`
  since a player can have a trail *and* wings equipped simultaneously
  (independent slots); one event per independent equip slot matches this
  codebase's existing per-concern granularity.
- `GameService.server.lua` handler mirrors `EquipCosmeticEvent`'s exact
  shape: explicit literal-assignment branches per style (not a dynamic-key
  loop, same `--!strict` reasoning as above), only lets a player equip a
  style they actually own, no-ops if already equipped (same debounce
  idiom `EquipCosmeticEvent` already uses), calls
  `WingsVisualSystem.ApplyEquippedWings` so an already-spawned character
  updates immediately.
- `PurchaseItemEvent`'s existing generic one-time-item-purchase handler
  needs no changes — already keyed generically off
  `GameConstants.ITEMS`/`ITEM_FIELDS`, so the four new items are granted
  through the exact same path as every other item.

### Client (`src/client/init.client.lua`)

- `ITEM_DISPLAY` entries gain an `EquipGroup: "Trail" | "Wings" | nil`
  field, replacing the current boolean `Cosmetic` flag (which only ever
  distinguished "has an Equip button" for the two trail items). Items in
  different groups are independently equippable, each tracked by its own
  `lastKnownEquipped*` client state and firing its own RemoteEvent
  (`EquipCosmeticEvent` for `"Trail"`, `EquipWingsEvent` for `"Wings"`).
- New item cards for Voidtech/Dragon/Demonic/Fae, added to the existing
  Shop Items section — same card layout (Buy/Owned points button, Robux
  button, Equip toggle) already used for the trails, same toggle behavior
  (clicking an already-equipped style's button un-equips it back to
  `"None"`).

## Verification

- `lune run` all four suites (the `Session` type/default-session shape
  changes are exactly the kind of thing `test/gameLogic.test.luau`'s
  `GetDefaultSession`/`ResetProgress`/`PerformRebirth` tests already cover
  — extend them for the new fields), `rojo build`, `luau-lsp analyze`.
- Manual Studio check (this is inherently visual/creative, same as the
  neon signs and cosmetic trails work this session) — buy and equip each
  of the 5 styles, confirm each reads as visually distinct, confirm flight
  works from any of them, confirm owning multiple and switching equip
  works, confirm a Reset preserves ownership/equip state while a Rebirth
  clears it (matching the existing item-field precedent).

## Rollout

Follow the normal PR flow (`CLAUDE.md`'s Development workflow section).
Given the scope (new module, new RemoteEvent, data model change, client UI
change, 5 pieces of from-scratch geometry), this is a strong candidate to
split into a few smaller PRs via `writing-plans` rather than one large one
— e.g. data model + `FlightSystem` change first, then `WingsVisualSystem`
+ geometry, then the client UI. Held for Studio verification before merge,
same as every other visual/creative change this session.
