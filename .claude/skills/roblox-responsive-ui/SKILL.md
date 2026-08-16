---
name: roblox-responsive-ui
description: Use when adding or modifying UI in src/client/init.client.lua that needs to scale or reflow across screen sizes — new panels, popups, HUD elements, or any change to an existing element's Size/Position. Triggers on "add a new screen/panel", "make this responsive", "fix UI overlap", "resize", or any change touching UDim2 Size/Position in the client. Not for pure text/color/copy tweaks that don't touch layout.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(lune *), Bash(rojo *)
---

# Roblox responsive UI (Autoclicker Void)

This project's GUI is built entirely programmatically in `src/client/init.client.lua`
and must hold up across screen sizes (see CLAUDE.md's "Responsive sizing" note). The
established pattern — scale-based `UDim2` `Size`, clamped via the `addSizeConstraint`
helper, `makeLabel`'s `TextWrapped`+`AutomaticSize.Y`, popup windows sized on both axes
with a scrolling body — already shipped once (#39, fixing #24) and still produced four
real bugs across two review passes plus one production incident, each from the same
handful of gotchas. Check every one of these on any layout-affecting UI change, not
just new panels.

## Pattern to follow

- New panel/popup Size: scale-based `UDim2` (e.g. `UDim2.new(0.75, 0, 0, 0)`), clamped
  with `addSizeConstraint(instance, minSize, maxSize)` — never a flat pixel `Size`.
- Labels: use the existing `makeLabel` helper (sets `TextWrapped` + `AutomaticSize.Y`)
  so wrapped text grows a row instead of clipping or overlapping its neighbor.
- Popups: use `createPopupWindow` — scale-sized on both axes, clamped, with a
  `ScrollingFrame` body (`AutomaticCanvasSize = Y`) below a fixed-height title bar so
  overflow content scrolls instead of pushing the window off-screen.
- Elements that must always stay clickable above a popup (like the nav stack): give
  them an explicit `ZIndex`, relying on the `ScreenGui`'s `ZIndexBehavior.Global`.

## Checklist — gotchas that have already caused real bugs here

1. **A property's Enum type doesn't always match its name.** `ScrollingFrame`'s
   `AutomaticCanvasSize` property is typed `Enum.AutomaticSize` — the same enum
   `GuiObject.AutomaticSize` uses — there is no separate `Enum.AutomaticCanvasSize`
   class. Indexing a nonexistent `Enum.*` class throws immediately at runtime. This is
   the most severe class of bug in this list: because GUI-building code runs top to
   bottom at script load, one bad enum reference partway through can throw and abort
   the *entire* script before later code (every click handler, `SyncState
   .OnClientEvent`) ever connects — not just break the one element being configured.
   That's exactly what happened in #39: the whole GUI shipped dead on arrival (every
   button rendered but did nothing) from one line, and it wasn't caught until a live
   player reported it. Before setting any `Enum.X.Y`, confirm `Enum.X` is the actual
   type the property/method expects (check Roblox's API docs/autocomplete) rather than
   assuming the property's name and its enum class name match.

2. **Press/hover/click animations under a `UISizeConstraint`**: if the element (or an
   ancestor) has a `UISizeConstraint`, do NOT animate by tweening `Size` directly — once
   the element is at its clamped min/max, a `Size` tween gets silently clamped right
   back and the animation has zero visible effect. Animate a `UIScale` instead (see
   `clickButton`'s click-shrink animation for the reference pattern). This is easy to
   miss because it only breaks at the screen sizes where the clamp is actually active —
   it looks fine at a normal desktop window.

3. **Removing/bypassing `UIListLayout`**: if you replace a `UIListLayout`-managed
   arrangement with manual `Position` math (e.g. a fixed-height title bar above a
   `ScrollingFrame`), explicitly carry over whatever gap/padding the layout used to
   give you for free. Removing a layout object silently removes its spacing too — the
   popup title-vs-content gap regression (#39) was exactly this.

4. **Overlap/collision-avoidance thresholds between two panels** (e.g. hide one panel
   below some `ScreenGui.AbsoluteSize` so it doesn't collide with another): derive the
   threshold from the panels' actual clamped widths/positions — their `UDim2`
   scale/offset plus `UISizeConstraint` min/max — not a flat pixel magic number that
   "looks about right." Work through the edge-position math (or test at several real
   viewport widths spanning each panel's clamp breakpoints), because a threshold picked
   without doing that math can leave a wide, common range of window sizes still
   overlapping (#40 — a 550x500 threshold didn't actually stop the overlap until
   ~900px).

5. **Test at more than one size.** This class of bug (correct at the exact window size
   you eyeballed in Studio, broken at another) doesn't show up from a single visual
   check — verify at least a small/portrait size and a typical desktop size, and reason
   through the clamp breakpoints in between rather than assuming linear scaling holds.

6. **`lune`/`rojo build` do NOT execute client Luau code, and will not catch gotcha #1
   or #2 above.** `lune run test/gameLogic.test.luau` only exercises the pure-logic
   shared modules (`GameLogic`/`NumberFormat`/`SpeedCalculator`); `rojo build` only
   compiles the place file structure. Neither runs `init.client.lua`'s actual code
   against Roblox's real API surface, so an invalid `Enum` reference or a
   clamp-defeated animation sails through both checks clean — as #39 did. Still run
   both before opening a PR (they catch real things: shared-logic regressions, Rojo
   project/sync errors), just don't mistake a pass on either for proof the GUI runs:
   ```sh
   lune run test/gameLogic.test.luau
   rojo build default.project.json -o /tmp/check.rbxlx
   ```

7. **Get this actually running in Studio or a live server before merging** — Play the
   place and click every button this change touches. This is the only check in this
   list that would have caught #39's `Enum.AutomaticCanvasSize` crash (gotcha #1);
   everything else here (review, lune, rojo build) missed it and it reached a live
   player instead. A code-review pass (the `code-review` skill) still catches gotchas
   #2-#5, which are visual/layout issues a script won't throw on — get one before
   merging any layout-affecting change, but treat it as a complement to a live check,
   not a substitute for one.

## Output

When presenting a UI change, note which of the above gotchas were checked and which
don't apply to this change, so a reviewer isn't starting from zero.
