# CLAUDE.md — Mining Turtle

Environment constraints for this repo. Read before implementing or planning.

## Target runtime

- **Minecraft 1.21.1 / NeoForge / CC:Tweaked.** All code runs inside the turtle's Lua VM, not on the host OS.
- **Pure Lua 5.2 dialect as exposed by CC:T.** No LuaRocks, no external libraries, no C bindings. Available APIs are the CC:T standard library: `turtle`, `fs`, `os`, `term`, `textutils`, `parallel`, `peripheral`, `rednet`, `colors`, `shell`, etc.
- **Terminal is 39×13** on an advanced turtle. Basic turtles the same size, monochrome. TUI must work on both.
- **Heavily-modded environment.** Block names are not limited to `minecraft:*`. Never hard-code a block-name match; always go through the pattern-aware classifier in `/config.lua` (see `DESIGN.md` §5).

## Architectural invariants (from `DESIGN.md`)

- Modules are strictly layered: `state → movement → inventory → navigator → strategies → main`. A module must not reach above itself.
- `movement.lua` is the only module that calls `turtle.forward/up/down/turn*`.
- `state.lua` is the only module that writes `/state/*`.
- Persistence is **write-after-success**: position is persisted after the move completes, not before. Atomic writes via `*.tmp` → `fs.move`.
- No GPS. Recovery reconciles persisted position against `inspect()` results, not satellite queries.
- No multi-turtle coordination. One turtle, one run, interactive menu.

## Things to avoid

- Do not introduce pathfinding libraries, Lua compilers, build steps, or any tooling outside CC:T.
- Do not hard-code vanilla block names anywhere except as seed entries in `/config.lua`. All runtime classification goes through the pattern matcher.
- Do not add `rednet.open` or network code to v1. The protocol is reserved (DESIGN §6); implementation is v2.
- Do not write position-sensitive code that assumes GPS is available.
- Do not use `turtle.*` calls outside `movement.lua`. If a new capability needs them, extend `movement.lua`'s public surface.
- Do not silently fall back on a corrupt config. Refuse to start. Silent fallbacks hide bugs.
- Do not use `error()` for recoverable conditions. Return `(ok, err)`. `error()` is for programmer bugs (bad arg types) only.

## Things to do

- Every `forward/up/down` in `movement.lua` persists state after success before returning.
- Every long-running strategy loop checks `ctx.shouldStop()` and `ctx.shouldPause()` at checkpoint boundaries.
- Every strategy checkpoints its progress table at genuine resume points (end of column, branch leg, etc.) — not every cell.
- Every user-facing error path routes through the recovery menu in `main.lua` (§7, §8). Users should never see a raw Lua error message.
- Every unknown block name encountered during mining is appended to `/logs/unknown-blocks.log` via `logger.lua`.

## Testing

- There is no automated test harness for CC:T code inside this repo. Validation is by running on a live turtle in-game.
- Strategies are the most testable unit: they consume a `ctx` table of dependencies, so a test harness (future, not v1) could hand them a mock `nav`/`inv`/`log`/`saveProgress` and assert on the recorded call sequence.
- Before claiming a strategy or module works, run it on a live turtle with at least one intentional mid-run crash (break the turtle / reboot the server / `os.reboot()`) and verify clean resume.

## File layout

Spec: `/DESIGN.md`.
Existing code (pre-this-project, not the new modular system): `/mine.lua`, `/turtle_tool.lua`. These are being superseded; keep around as reference until the new program reaches feature parity.

New code target layout (see DESIGN §1):

```
/mine                      launcher, thin
/lib/*.lua                 modules: main, movement, navigator, inventory, state, config, logger, util
/strategies/*.lua          one file per strategy
/config.lua                user-editable config
/state/current.lua         persisted position + run metadata
/state/strategy.lua        persisted per-strategy progress
/logs/                     run logs, unknown-blocks log
```

## Style

- No comments that restate what the code does. Comments allowed only for non-obvious *why*.
- No docstring blocks. Single-line comments max.
- Keep files focused; a file growing past ~300 lines is a signal to split.
- No emoji in source code.
