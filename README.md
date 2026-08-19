# autoclicker

**Autoclicker Void** — a Roblox idle-clicker game built with Luau and synced via [Rojo](https://rojo.space/). Click to earn points, spend them on upgrades that grow your score over time, rebirth for a permanent multiplier, and compete on a global leaderboard. A separate Movement mode lets you explore a procedurally-generated maze on foot; one-time shop items (Wings, cosmetic trails) add a short flight burst and visual flair, bought with points or Robux.

See `CLAUDE.md` for architecture and the development workflow.

## Running it

```sh
rojo serve
```

Then connect via the Rojo Studio plugin.

## Tests

Run all three checks before opening a PR (see `CLAUDE.md`'s Development workflow for the full commands): the headless logic suite, a Rojo build check, and Luau static analysis.

```sh
lune run test/gameLogic.test.luau
rojo build default.project.json -o /tmp/check.rbxlx
```
