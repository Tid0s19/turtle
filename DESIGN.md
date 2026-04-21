# Mining Turtle — Design

**Target:** Minecraft 1.21.1 (NeoForge) + CC:Tweaked.
**Scope:** a modular, solo mining turtle program. Interactive menu, robust state persistence, pluggable strategies. Heavily-modded environments supported via pattern-matched block classification.

This document is the spec. No implementation yet. Sections are ordered so each depends only on those above it.

---

## 1. Module Layout

Pure Lua, CC:T standard library only. Single turtle. One executable (`mine`) composed of modules loaded via `require`. Strictly layered; each upper layer only knows the one below it.

```
┌─────────────────────────────────────────────────────┐
│  main.lua          ← menu, orchestration, pre-flight │
├─────────────────────────────────────────────────────┤
│  strategies/       ← strip.lua / branch.lua /        │
│                     quarry.lua — pluggable           │
├─────────────────────────────────────────────────────┤
│  navigator.lua     ← goTo(x,y,z), panicHome(),       │
│                     serpentine helpers               │
├─────────────────────────────────────────────────────┤
│  inventory.lua     ← classify, dump-junk-in-place,   │
│                     deposit-at-home, refuel-from-slot│
├─────────────────────────────────────────────────────┤
│  movement.lua      ← transactional forward/up/down/  │
│                     turn/dig; obstacle handling;     │
│                     onEnterCell/onExitCell hooks     │
├─────────────────────────────────────────────────────┤
│  state.lua         ← pos, facing, strategy snapshot; │
│                     write-after-success persistence  │
├─────────────────────────────────────────────────────┤
│  config.lua        ← load/save Lua-table config      │
│  logger.lua        ← timestamped append-only logfile │
│  util.lua          ← block-name predicates, timers   │
└─────────────────────────────────────────────────────┘
```

### Layering rules (enforced by convention, not the language)

- `movement` never reaches above itself. It calls `state.persistPosition()` after every successful cell move.
- `navigator` never calls `turtle.*` directly — everything goes through `movement`.
- `strategies` never call `turtle.*` or `state.*` — only `navigator`, `inventory`, and their own stored context.
- `main` owns the menu and the run loop; strategies are a pluggable array it iterates.

### Repository layout on the turtle

```
/mine                      ← launcher (thin, requires lib/main)
/lib/main.lua
/lib/movement.lua
/lib/navigator.lua
/lib/inventory.lua
/lib/state.lua
/lib/config.lua
/lib/logger.lua
/lib/util.lua
/strategies/quarry.lua
/strategies/strip.lua
/strategies/branch.lua
/config.lua                ← user-editable config (Lua table)
/state/current.lua         ← persisted position + run metadata
/state/strategy.lua        ← persisted strategy-specific progress
/logs/run-<timestamp>.log
/logs/unknown-blocks.log
```

Two state files because strategy state (branch index, vein bookmarks, etc.) has a different schema per strategy and a different write frequency than raw position.

---

## 2. Movement API Contract

The transactional keystone of the whole system. Everything above depends on this being right.

### Coordinate system

- Origin = startup position.
- `+Z` = forward (away from the chest placed behind the turtle).
- `+X` = right.
- `+Y` = up.
- `facing` ∈ `{0=+Z, 1=+X, 2=-Z, 3=-X}`.

This matches the convention of the existing `mine.lua` and `turtle_tool.lua`, so muscle memory and physical setups transfer.

### Public surface (`movement.lua`)

All move/dig functions return `(ok:boolean, err:string|nil)`. Nothing `error()`s except on genuine programmer bugs (bad argument type). Callers decide fatality.

```lua
-- Movement
movement.forward()
movement.back()
movement.up()
movement.down()
movement.turnLeft()
movement.turnRight()
movement.face(dir)       -- 0..3, shortest rotation

-- Digging (separate from move; strategies need both)
movement.dig()
movement.digUp()
movement.digDown()

-- Observation (no state mutation)
movement.getPos()        -- returns {x, y, z, facing}
movement.inspect()       -- ok, blockdata (forward)
movement.inspectUp()
movement.inspectDown()

-- Hooks (for future torch module, etc.)
movement.onEnterCell(fn) -- fn({x,y,z,facing}) after each successful move
movement.onExitCell(fn)  -- fn({x,y,z,facing}) before each move attempt
```

### Transactional semantics of `forward/up/down`

```
1. Fire onExitCell hook.
2. Try turtle.<direction>().
3. If success:
     - update in-memory pos
     - state.persistPosition()           ← write-after-success
     - fire onEnterCell hook
     - return (true, nil)
4. If blocked, classify the obstacle via inspect:
     - bedrock      → return (false, "bedrock")
     - dangerous liquid (pattern-matched, see §5) →
         inventory.placeSealForward() → retry, capped at 3 attempts
     - falling block (sand/gravel) → dig loop,
         capped at safety.max_redig_attempts (default 30)
     - mob          → attack loop,
         capped at safety.max_attack_attempts (default 10)
     - unknown      → dig() once, retry
5. If still blocked after retries: return (false, <classified reason>).
```

### Persistence semantics

"Persist" = `fs.open(path, "w")` → `write(textutils.serialise(snapshot))` → `close()`, written first to `state/current.lua.tmp` then `fs.move`d over the real path. `fs.move` is atomic in CC:T; a crash mid-write leaves the previous good version intact.

Power loss between a successful `turtle.forward()` and its `persistPosition()` call leaves the persisted position one cell behind reality. Recovery logic (§7) re-inspects surroundings and reconciles, or falls to the recovery menu.

### What `movement.*` deliberately does NOT do

- No pathfinding (that is `navigator.lua`).
- No inventory checks before dig (that is the caller's concern via `inventory`).
- No fuel checks (that is `inventory`).
- No strategy awareness.

---

## 3. State Persistence Schema

Two files, both Lua tables, both written atomically (`*.tmp` → `fs.move`). Read via `textutils.unserialise`; a nil result means corrupt.

### `/state/current.lua` — movement + run metadata

Rewritten after every successful move **or turn** — anything that mutates `pos` or `facing`.

```lua
{
  version        = 1,
  run_id         = "2026-04-20T22:41:03Z-a1b2", -- set once per menu-confirmed run
  pos            = { x = 0, y = 0, z = 0 },
  facing         = 0,
  strategy       = "quarry",                    -- nil if idle
  phase          = "mining",                    -- "idle" | "planning" | "mining" |
                                                -- "returning_home" | "depositing" | "resuming"
  started_at     = 1713648063,                  -- epoch seconds, os.epoch("utc")/1000
  last_write_at  = 1713651201,
  fuel_at_start  = 20000,
  blocks_mined   = 1247,                        -- running count
  home           = { x = 0, y = 0, z = 0, facing = 0 },
}
```

### `/state/strategy.lua` — strategy-specific progress

Rewritten by the strategy at its own checkpoint boundaries (end of column, end of branch leg, etc.), **not** every cell.

```lua
{
  version  = 1,
  run_id   = "2026-04-20T22:41:03Z-a1b2",  -- must match current.lua
  strategy = "quarry",
  params   = { width = 16, length = 16 },  -- user-confirmed params
  progress = {                             -- opaque to the rest of the system
    -- quarry:
    col = 5, row = 12, next_action = "descend_column",
    -- strip: { length_done = 48, direction = "outbound" }
    -- branch: { branch_idx = 3, depth_in_branch = 22, direction = "outbound" }
  },
}
```

### Why `run_id`

Prevents resuming the wrong strategy after a manual config edit or partial file corruption. Both files must agree on `run_id`, or recovery refuses and prompts the user.

### Resume flow at boot

```
1. Read /state/current.lua.
   - Absent or phase=="idle"           → clean boot, show main menu.
2. Read /state/strategy.lua.
   - Missing or run_id mismatch        → recovery menu (see §7).
3. Prompt:
     "Found run <run_id>: <strategy> <params>
      phase <phase>, last seen <Δt> ago. Resume? [Y/n]"
4. Yes → strategy.resume(current, strategy) takes over.
5. No  → explicit choice: panic home / wipe / quit. Each is confirmed.
```

### Write budget

A medium quarry (say 16×16 to bedrock at Y=64) is roughly 16 × 16 × 64 ≈ 16k vertical moves plus turns and surface traversal — call it 20k writes of `current.lua`. Each write ≈ 2–4 ticks (one `fs.open`+`write`+`close`+`fs.move`). Total ~10–20 minutes of disk overhead across a multi-hour job. Acceptable. If a future profile shows this is too slow, batching `current.lua` every N moves is a tuning knob, not a re-design — at the cost of replaying up to N cells on recovery.

### What is NOT persisted

- Movement hook callbacks (re-registered on boot).
- Inventory contents (readable from `turtle.getItemDetail`).
- Log history (owned by `logger.lua`).
- Fuel level (readable from `turtle.getFuelLevel`).

---

## 4. Strategy Plugin Interface

A strategy = a single Lua file in `/strategies/`. It returns a table conforming to the contract below. `main.lua` discovers strategies by listing the directory at startup. Adding a strategy is "drop the file in" — no registry to update.

### Contract

```lua
-- /strategies/quarry.lua
return {
  -- Identity
  name        = "quarry",       -- must match filename
  display     = "Quarry",       -- shown in menu
  description = "Mine a rectangular area down to bedrock.",

  -- Interactive configuration.
  -- Called by main during the menu flow. Returns a params table or nil if cancelled.
  -- Strategy owns its own prompts; main never inspects params.
  promptParams = function(defaults) ... end,

  -- Estimation (for pre-flight). Pure function — no turtle calls.
  estimate = function(params)
    return { fuel = 12400, blocks = 48000, seconds = 7200 }
  end,

  -- Sanity check before starting. Returns (ok, errmsg).
  -- Typical checks: chest behind, fuel slot populated, seal blocks available.
  preflight = function(params) ... end,

  -- Fresh run. Strategy calls ctx.saveProgress(tbl) at sensible boundaries
  -- (end of column, branch leg, etc.).
  run = function(params, ctx) ... end,

  -- Resume a mid-run state. progress is the opaque table from the last checkpoint.
  resume = function(params, progress, ctx) ... end,

  -- Optional recovery hint. Given last-known progress, return the cell the
  -- strategy expects to be in. Used to sanity-check persisted position.
  expectedCell = function(params, progress)
    return { x = 5, y = -32, z = 12 }   -- or nil if ambiguous
  end,
}
```

### What `ctx` provides

Dependency-injected so strategies stay independently testable.

```lua
ctx = {
  nav          = navigator,   -- goTo, face, panicHome, serpentine helpers
  inv          = inventory,   -- classify, depositAtHome, refuelFromReserved, isFullOfKeep
  log          = logger,      -- log.info/warn/error with timestamps
  saveProgress = function(tbl) ... end, -- atomic write of /state/strategy.lua
  shouldStop   = function() return bool end, -- set by UI keypress handler
  shouldPause  = function() return bool end,
}
```

### Forbidden inside strategies

- Calling `turtle.*` directly (always via `movement`/`navigator`).
- Reading or writing `/state/*` directly (always via `ctx.saveProgress`).
- Requiring other strategies (each is standalone).

### MVP strategies (v1)

- **quarry** — serpentine over a `W×L` rectangle, each cell = column down to bedrock (or configured depth). Checkpoint after each column.
- **strip** — single tunnel of length `L` at current Y. Checkpoint every N cells.
- **branch** — main tunnel + perpendicular branches at configured spacing, each of configured length. Checkpoint at end of each branch leg.

### Future strategies (interface must support, no v1 code)

- 3×3 tunnel (one-block-wide main + wall-dig).
- Vein-follow (recursive ore-adjacency walk + return to tunnel).
- Geoscanner-guided (Advanced Peripherals).

The contract above is general enough that each of these slots in without touching `main`, `movement`, or the other strategies.

---

## 5. Config Schema

One file: `/config.lua`. Loaded at startup via `loadfile` in a sandboxed environment (comments preserved on manual edits). Written back via `textutils.serialise` only when the user asks the menu to save defaults — manual-edit comments survive round-trips because manual edits are never overwritten wholesale.

### Shape

```lua
-- /config.lua — CC:T Mining Turtle
-- Edit freely. Unknown keys are ignored with a warning; missing keys use defaults.
return {
  version = 1,

  -- ─── Inventory classification ──────────────────────────────
  -- Three-tier: keep / junk / fuel. Unknown items default to KEEP.
  -- Both exact names and Lua patterns are supported; exact checked first.
  inventory = {
    junk = {
      "minecraft:cobblestone", "minecraft:cobbled_deepslate",
      "minecraft:stone", "minecraft:deepslate",
      "minecraft:dirt", "minecraft:granite", "minecraft:diorite",
      "minecraft:andesite", "minecraft:tuff", "minecraft:gravel",
      "minecraft:sand", "minecraft:netherrack",
    },
    junk_patterns = {
      ".*:cobblestone$", ".*:cobbled_.*", ".*_stone$", ".*_deepslate$",
      ".*:dirt$", ".*:mud$", ".*_granite$", ".*_diorite$", ".*_andesite$",
      ".*:gravel$", ".*:sand$", ".*:tuff$", ".*:netherrack$",
    },
    fuel = {
      "minecraft:coal", "minecraft:charcoal",
      "minecraft:coal_block", "minecraft:lava_bucket",
    },
    fuel_patterns = { ".*:coal$", ".*:charcoal$" },
    seal = {
      "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:dirt",
    },
    seal_patterns = { ".*:cobblestone$", ".*:cobbled_.*", ".*:dirt$" },

    -- Policy for what happens with classified-junk items.
    --   "drop"     → dump junk in place as you go (default).
    --   "keep"     → treat junk as valuable; deposit at home chest.
    --   "overflow" → keep junk while slots are free; dump in place when
    --                keep slots fill, to make room for more keep.
    junk_policy = "drop",

    keep_slots_before_home = 12,   -- trigger home-run when keep fills ≥ this many
    reserved_fuel_slot     = 16,
  },

  -- ─── Fuel policy ───────────────────────────────────────────
  fuel = {
    refuel_below      = 2000,   -- auto-refuel when level drops below this
    reserve_for_home  = 1.25,   -- multiplier on |pos - home| manhattan distance
    abort_below       = 200,    -- below this with no refuel path → panic home
  },

  -- ─── Safety ────────────────────────────────────────────────
  safety = {
    seal_lava            = true,
    seal_water           = false,
    dangerous_liquids    = { ".*:lava$", ".*:crude_oil$", ".*:poison$" },
    bedrock_names        = { "minecraft:bedrock", ".*:bedrock$", "minecraft:barrier" },
    max_redig_attempts   = 30,   -- gravel/sand columns
    max_attack_attempts  = 10,   -- mob unblock
  },

  -- ─── Logging ───────────────────────────────────────────────
  logging = {
    level     = "info",    -- "debug" | "info" | "warn" | "error"
    keep_runs = 5,         -- rotate older run logs
  },

  -- ─── Strategy defaults (last-used values) ──────────────────
  -- Menu pre-fills from here and saves back on confirm.
  strategy_defaults = {
    quarry = { width = 8,  length = 8,  depth = "bedrock" },
    strip  = { length = 64, torch_spacing = 0 },             -- 0 disables
    branch = { main_length = 32, branch_length = 8, branch_spacing = 3 },

    -- Optional per-strategy junk_policy override.
    -- Absent = use global inventory.junk_policy.
    -- quarry = { ..., junk_policy = "overflow" },
  },

  -- ─── UI ────────────────────────────────────────────────────
  ui = {
    confirm_destructive  = true,
    show_estimate_detail = true,
  },
}
```

### Load semantics

- Missing file → write the defaults table and continue.
- Parse error → **refuse to start**, print path + line. Never silently fall back.
- Unknown keys → logged warning, ignored.
- Missing keys → filled from in-memory defaults but not written back.

### Heavily-modded environments

The pattern lists and "unknown → keep" default are the central accommodations. Additional support:

- **Unknown-block logging.** Any block name the classifier has never seen is appended to `/logs/unknown-blocks.log` with `{name, firstSeenAt, countThisRun}`. End-of-run menu summarises new names seen.
- **Learn-blocks menu.** An explicit menu option iterates current inventory, prompts `[k]eep / [j]unk / [f]uel / [s]eal / s[k]ip` per unique block name, appends to the config's exact-name lists atomically. Never touches pattern fields — those stay user-authored.

### What is NOT in config

- Strategy *selection* (runtime via menu).
- World coordinates / home position (runtime; origin = startup position).
- Heading convention (code-level: chest-behind is assumed).

---

## 6. Rednet Protocol

**v1 ships with no rednet code.** v2 (future) adds broadcast-only status reporting. Two hooks in v1 keep the seam clean:

### Hook 1: `logger.addSink(fn)`

Every status-worthy event (phase change, block milestone, inventory-full, home-run, error) flows through the logger. The logger's v1 sinks are terminal + file. A rednet sink is one future one-liner:

```lua
logger.addSink(function(event)
  rednet.broadcast(textutils.serialiseJSON(event), "turtle.status")
end)
```

### Hook 2: reserved wire format

Documented in v1 so v2 does not re-invent it. All messages are Lua tables serialised as JSON.

**Heartbeat — channel `turtle.status`, every 5s + on every `state.lua` write:**

```lua
{
  kind          = "heartbeat",
  turtle_id     = os.getComputerID(),
  label         = os.getComputerLabel(),
  run_id        = "...",
  pos           = { x=, y=, z= },
  facing        = 0,
  fuel          = 18432,
  strategy      = "quarry",
  phase         = "mining",
  progress_pct  = 37,
  inventory_pct = 62,
  blocks_mined  = 1247,
  uptime_s      = 3144,
}
```

**Event — channel `turtle.events` on notable occurrences:**

```lua
{
  kind      = "event",
  turtle_id = ...,
  level     = "warn",
  msg       = "lava sealed",
  data      = { pos = {...}, seal_slot = 2 },
}
```

Channels are protocol strings in `rednet.broadcast(msg, protocol)`. No pairing, no ack, no retries. Receiver programs (future `monitor.lua`, `pocket.lua`) subscribe with `rednet.receive` filters.

### What ships in v1

- `logger.addSink(fn)` API (unused internally).
- This protocol section, committed to the repo so v2 has a fixed contract.
- No modem code, no `rednet.open`, no network dependencies.

---

## 7. Failure & Recovery per Module

Every module has one answer to "what happens if this dies mid-op."

### `movement.lua`

- Move fails after retry cap → returns `(false, reason)`. Never throws.
- Power loss between successful `turtle.forward()` and `state.persistPosition()` → persisted pos one cell behind. Recovery re-inspects surroundings; if the block in front matches "we already dug this," advance persisted pos by one and continue. If ambiguous → recovery menu.
- Lava seal fails (no seal block) → `(false, "no_seal")`; strategy escalates to `panicHome`.
- `dig()` returns a block the classifier has never seen → block is still dug, logged to unknown-blocks, treated as keep.

### `state.lua`

- `textutils.unserialise` returns nil on either state file → corrupt. Do **not** auto-wipe. Rename to `/state/corrupt-<ts>.lua` and enter recovery menu.
- `run_id` mismatch between `current.lua` and `strategy.lua` → corrupt-strategy: offer "panic home from current.lua" or "wipe and start fresh."
- Atomic write: `*.tmp` → `fs.move`. Crash before `fs.move` leaves prior file untouched.

### `inventory.lua`

- Chest full on deposit → retry loop with 5s sleep, warn every iteration, user can interrupt via live-screen key.
- Fuel slot empty when refuel needed → if current fuel ≥ `fuel.reserve_for_home × dist_home`, log warn and keep mining (home-run will handle it). Otherwise immediate `panicHome`.
- No seal block on lava → bubble failure to movement → strategy → `panicHome`. **Never plug with a keep item.**

### `navigator.lua`

- `goTo` partial failure (blocked / out of fuel mid-traverse) → returns `(false, reason, currentPos)`. Strategy decides retry / panic / abort.
- `panicHome` itself fails (e.g. blocked by unsealeable lava) → last-ditch routine: rise to ground-level `Y = home.y`, dig straight back to `X=0`, then `Z=0`, logging every attempt. If still stuck: shut down with a loud terminal message. State preserved; next boot resumes from there.

### `strategies/*`

- Any error → `ctx.log.error`, return. Main sees non-success, presents recovery menu.
- `resume()` detects `expectedCell()` disagreeing with persisted pos → logs warn, trusts persisted pos (last-write-wins), re-probes surroundings. If re-probe consistent with expected, continue; otherwise recovery menu.

### `config.lua`

- Parse error → refuse to start. Print path + line. Never silently fall back.
- Unknown keys → warn + ignore.
- Missing keys → filled from in-memory defaults, not written back.

### `logger.lua`

- Log file write fails (disk full) → fall back to terminal-only, set an in-memory flag to suppress retry spam. Never block execution on logging.

### `main.lua`

Any unhandled error bubbles here. Recovery menu (screen shape in §8):

```
[R] Resume where we left off
[H] Panic home and stop
[W] Wipe state, start fresh          (confirms twice; type strategy name)
[Q] Quit and leave state as-is       (for debugging)
```

Typing the strategy name to confirm wipe prevents muscle-memory disasters after hours of mining.

### Recovery matrix

| Failure                     | State intact? | Default action               |
|-----------------------------|---------------|------------------------------|
| Power loss mid-move         | yes (±1 cell) | re-probe, auto-resume        |
| Corrupt current.lua         | no            | recovery menu                |
| Corrupt strategy.lua        | current good  | panic home from current      |
| Unknown block               | n/a           | keep-by-default, log         |
| Seal shortage + lava        | yes           | panic home                   |
| Fuel shortage mid-run       | yes           | home-run if reachable, else panic drop |
| Chest full at home          | yes           | wait + retry, interruptible  |
| Blocked path in goTo        | yes           | strategy decides             |

---

## 8. UX / TUI

Runs on the turtle's 39×13 terminal. Advanced turtles get colour; basic turtles get the same layout monochrome (colour calls wrapped to no-op if `term.isColor() == false`).

### Screen grammar

Every screen:

```
┌───────────────────────────────────────┐
│ ⛏ quarry-alpha   fuel 18432  keep 4/16 │  ← status header
│ ─────────────────────────────────────  │
│                                        │
│   [main content]                       │
│                                        │
│ ─────────────────────────────────────  │
│ [1] confirm   [2] back   [q] quit     │  ← action footer
└───────────────────────────────────────┘
```

Header shows turtle label (`os.getComputerLabel()` or `turtle-<id>`), fuel, keep-slot fill. Footer shows every key that does something on this screen — no hidden shortcuts.

### Boot flow

```
Boot
  │
  ├─ /state/current.lua + strategy.lua exist + phase ≠ "idle"
  │   → "Found run <run_id> — <strategy>, <phase>, last seen Δt ago.
  │      Resume? [Y] resume   [N] recovery menu"
  │
  └─ clean boot → main menu
```

### Main menu

```
                   ⛏  Mining Turtle
 ─────────────────────────────────────────
   [1] Quarry    — dig a rectangle to bedrock
   [2] Strip     — single tunnel
   [3] Branch    — main tunnel + side branches
   ─────────
   [4] Learn blocks    (scan inventory → config)
   [5] Settings        (view / edit config)
   [6] Home calibrate  (re-confirm chest & facing)
   ─────────
   [q] Quit
```

Strategy list is built at boot from `/strategies/` — each file exposes `display` and `description`. Adding a strategy = drop file, no menu edit.

### Strategy run flow

```
[1] Quarry
  → promptParams()   width? [8]  length? [8]  depth? [bedrock]
  → estimate()        fuel ~12,400   blocks ~48,000   time ~2h
  → preflight()       chest behind ✓   fuel slot ✓   seal blocks ✓
  → confirm           "Start? [Y/n]"
  → run()             live status screen
```

Empty-enter accepts a default. Invalid input re-prompts (never crashes). `[esc]` at any param returns to the main menu.

### Pre-flight summary

Always shown. Never auto-proceeds.

```
 Quarry 8×8 to bedrock
 ────────────────────────
   Estimated fuel    ~12,400     (have 18,432) ✓
   Blocks to mine    ~48,000
   Estimated time    ~2h 05m
   Seal blocks       24 cobble   ✓
   Chest behind      yes         ✓
 ────────────────────────
 Start? [Y] yes   [N] no
```

Any failing row renders red; `[Y]` is replaced with `[F] fix and retry`.

### Live status screen (during run)

```
 ⛏ quarry  18432 fuel   4/16 keep
 ────────────────────────────────
   progress   ████████░░░░░░  52%
   pos        (5, -32, 12)
   column     27 / 64
   blocks     24,910 mined
   runtime    1h 07m  (eta 0h 58m)
   last log   "sealed lava south"
 ────────────────────────────────
 [p] pause   [h] home & stop   [a] abort
```

- `[p]` pause — finishes current cell, waits for `[p]` again.
- `[h]` home-and-stop — strategy stops at next checkpoint, goes home, deposits, exits cleanly (`phase = idle`).
- `[a]` abort — double-confirmed. Stops in place; state preserved for next-boot recovery.

Keypresses run through `parallel.waitForAny({worker, keyListener})`. Strategies don't poll — they call `ctx.shouldStop()` / `ctx.shouldPause()` at checkpoints.

### Recovery menu

```
 ⚠  Problem: seal block shortage at (5,-32,12)
 ────────────────────────────────────────────
   Strategy: quarry 8×8    phase: mining
   Last write: 12s ago     run_id: a1b2c3
 ────────────────────────────────────────────
   [R] resume where we left off
   [H] panic home and stop
   [W] wipe state, start fresh (type 'quarry' to confirm)
   [Q] quit, leave state as-is
```

### Learn-blocks screen

```
 Unknown blocks seen this run: 3
 ─────────────────────────────────
   1. create:limestone          ×47
      [k] keep   [j] junk   [f] fuel   [s] seal   [x] skip
   2. biomesoplenty:mud         ×12
      ...
```

Choices append to `config.lua`'s exact-name lists atomically. Never touches pattern fields.

### Settings screen

Read-only view of loaded config plus `[e]` to launch CC:T's built-in `edit /config.lua`. We don't build a full in-TUI config editor — `edit` is strictly better than anything we'd cram into 13 rows.

### Small touches

- Every confirm defaults bracketed (`[Y]/n`).
- Every numeric prompt shows its default in `[ ]`.
- Error lines get a timestamp prefix so logs match the screen.
- `term.clear()` between screens — no scroll UIs in 13 rows.
- Bell on unexpected errors so you hear it across the room.

---

## Appendix A — Decisions locked during brainstorming

| Question                          | Choice                                        |
|-----------------------------------|-----------------------------------------------|
| Strategy invocation               | Interactive menu, solo turtle                 |
| State-persistence granularity     | Write-after-success (one write per cell)      |
| GPS                               | None. Dead-reckoning only.                    |
| MVP strategies                    | Quarry, strip, branch                         |
| Rednet reporting                  | Deferred to v2 with clean seams               |
| Inventory classification          | Three-tier keep / junk / fuel, unknown→keep   |
| Junk handling                     | Policy: drop / keep / overflow (per-strategy override) |
| Config format                     | Lua table via `textutils.serialise`/`loadfile`|
| Heading calibration               | Chest-behind convention, verified at startup  |
| Dry-run / estimate                | Always-on pre-flight, not a separate mode     |
| Torch placement                   | v1 out of scope; movement exposes cell hooks  |
| Modded-block handling             | Pattern lists + unknown-block logging + learn-blocks menu |

## Appendix B — Explicitly out of v1 scope

- Multi-turtle coordination / dispatcher.
- GPS integration and auto-calibration from satellites.
- Advanced Peripherals (geoscanner-guided mining).
- Torch placement (hooks present; module future).
- Vein-follow strategy.
- 3×3 tunnel strategy.
- Rednet reporting code (protocol reserved, not implemented).
- In-TUI config editor (delegates to `edit`).

Each of these has a documented seam so later work is additive rather than invasive.
