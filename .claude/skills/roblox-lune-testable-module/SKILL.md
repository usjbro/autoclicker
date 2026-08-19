---
name: roblox-lune-testable-module
description: Use when extracting pure logic (math, or handler orchestration with injected dependencies) out of a Roblox-only file into a new src/shared/*.lua module so it becomes headlessly testable under Lune, without a running Roblox engine. Triggers on "make this testable without Studio", "extract this into its own module", "this handler has real orchestration worth unit-testing", or "this maze/geometry math should have headless tests". Two real examples already shipped this way, both worth reading directly — src/shared/MazeGeometry.lua (pure math extracted from MapBuilder.lua) and src/shared/GameHandlers.lua (Reset/Rebirth orchestration extracted from GameService.server.lua, with every side effect injected as a dependency).
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(lune *), Bash(rojo *), Bash(luau-lsp *)
---

# Roblox Lune-testable module extraction (Autoclicker Void)

`GameLogic.lua`/`NumberFormat.lua`/`SpeedCalculator.lua` established the pattern this
project uses to get real, headless test coverage without a Roblox Studio session:
pure logic, zero Roblox-only globals, loadable by both Rojo (in-engine) and Lune
(headless `test/*.test.luau` files) via one require branch. `MazeGeometry.lua` (Tier 1
of the test-automation plan) and `GameHandlers.lua` (Tier 3) extended this pattern to,
respectively, pure geometry math and RemoteEvent-handler orchestration with injected
side effects. Follow the same shape for any new extraction — skipping a step here is
how the Tier 3 work spent real time rediscovering a cross-runtime type-resolution
bug that's now already solved below.

## When this applies

- **Pure math/data with no `Instance`/`game`/`workspace` references** that currently
  lives inline in a Roblox-only file (a `.server.lua`, or a `src/server/*.lua` module)
  and would benefit from headless bounds/invariant tests — see `MazeGeometry.lua`,
  extracted from `MapBuilder.lua`.
- **RemoteEvent-handler orchestration** — a handler that does more than one thing
  conditionally (e.g. "force-save the leaderboard, but only if X") where "does the
  handler actually do Y when X" is worth a real automated answer, not just manual
  Studio testing. Extract the *sequencing* into a module whose every real side effect
  (DataStore save, leaderboard write, client sync, reapplying a cosmetic, etc.) is
  passed in as an injected dependency function — never called directly — so the
  calling code in `GameService.server.lua` becomes thin wiring (acquire the lock,
  build the deps closures, delegate) and the module itself never touches `Instance`/
  `game`. See `GameHandlers.lua`'s `HandleReset`/`HandleRebirth`.

Not for logic that's inherently Roblox-only (actual `Instance.new`/physics/rendering)
— that has no Lune equivalent and stays in `src/server/`. `MapBuilder.lua` itself
(the actual part-building) is the standing example of what stays put: only the
coordinate math and config data moved out to `MazeGeometry.lua`, not the
`Instance.new` calls.

## Steps

1. **Create `src/shared/<Name>.lua`**, `--!strict`, starting with the dual-load
   require branch for anything it itself needs to require:
   ```lua
   local GameLogic
   if script then
       GameLogic = require(script.Parent.GameLogic)
   else
       GameLogic = require("./GameLogic")
   end
   ```
   If the module needs no internal requires at all (like `MazeGeometry.lua`), skip
   this — nothing to branch on.

2. **Zero Roblox-only globals inside the module.** Confirmed by direct test this
   session: `Color3`, `Random`, and `Vector3` are all `nil` under Lune (`lune run` on
   a one-liner referencing any of them throws `attempt to index nil`) — they're
   Roblox-engine globals, not standard Luau. If the logic genuinely needs one of
   these (e.g. wing theme colors), that piece stays in the Roblox-only caller
   (`MapBuilder.lua` keeps `WING_THEME_COLORS`, only the numeric `gridWidth`/
   `gridDepth`/`levelCount` moved to `MazeGeometry.WING_CONFIGS`) rather than
   forcing the whole module to stay un-extracted.

3. **If the module references an exported type from something it requires via the
   dual-load branch** (e.g. `GameLogic.Session`), don't expect `SomeModule.Session`
   to resolve under `luau-lsp analyze` the way it does when `SomeModule` comes from a
   single, unambiguous `require(...)` call — the multi-branch assignment collapses
   `luau-lsp`'s inferred type to `any`, and `any.Session` isn't a valid type
   reference. Two workarounds were tried and neither worked: a `::
   typeof(require(...))` cast on the module binding, and a dead-code
   (`if false then ... end`) single-`require` alias purely for the type checker.
   **What actually works**: duplicate the type definition directly in the new
   module, with a comment explaining why and noting it's self-checking (a future
   drift from the real type fails to type-check the very next line that passes a
   value of it into the original module's own functions — caught by the same
   `luau-lsp analyze` CI gate every PR already runs, not a silent risk). See
   `GameHandlers.lua`'s own `type Session = { ... }` for the reference example.

4. **Rebind, don't duplicate, in the Roblox-only caller.** The file the logic came
   from (`MapBuilder.lua` for `MazeGeometry.lua`, `GameService.server.lua` for
   `GameHandlers.lua`) should `require` the new module and rebind its old local
   names/functions to the new module's exports (`local MAZE_CELL_SIZE =
   MazeGeometry.CELL_SIZE`, `local mazeCellCenter = MazeGeometry.CellCenter`) so
   every existing call site elsewhere in that file stays unchanged — minimal diff,
   single source of truth, not a parallel copy that can drift.

5. **Write `test/<name>.test.luau`** (Lune, headless), matching the existing
   suites' structure exactly: `local process = require("@lune/process")`, a `test(name,
   fn)` runner with pass/fail counters, `assertEqual`/`assertNear` helpers, a final
   `process.exit(1)` if anything failed. For an orchestration module (the
   `GameHandlers.lua` shape), write a `spyDeps()` helper that returns fake dependency
   functions recording what they were called with, so a test can assert both "did
   this fire" and "what was it called with" — see `test/gameHandlers.test.luau`'s
   `spyDeps`.

6. **Add the new test file to CI**, not just your own local run —
   `.github/workflows/ci.yml`'s "Run Lune test suites" step must gain a
   `lune run test/<name>.test.luau` line, or the suite exists and passes locally
   forever without ever being enforced on a PR (a real, previously-shipped gap: CI
   only ran `test/gameLogic.test.luau` for a while after both `mazeGeometry.test.luau`
   and `gameHandlers.test.luau` were added — fixed in #77).

7. **If a TestEZ spec exists for the logic being extracted** (`src/tests/*.spec.lua`),
   keep its test cases in sync with the new Lune suite per CLAUDE.md's existing
   requirement — same case, both suites, not one and forget the other.

8. **Verify with the real tools before considering it done** — inspection isn't
   enough, the actual cross-runtime type-resolution failure above was only caught by
   really running `luau-lsp analyze`, not by reading the code:
   ```sh
   lune run test/<name>.test.luau
   rojo build default.project.json -o /tmp/check.rbxlx
   rojo sourcemap default.project.json -o sourcemap.json
   luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions globalTypes.d.luau src/server src/shared src/client
   ```

## Output

When presenting the extraction, note: what moved vs. what stayed in the Roblox-only
caller (and why), whether the exported-type gotcha applied and how it was resolved,
and confirm the new `test/*.test.luau` file was added to `ci.yml`, not just run
locally.
