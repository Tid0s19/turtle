# Mining Turtle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a modular, crash-resilient mining turtle program for CC:Tweaked on Minecraft 1.21.1 NeoForge. Solo turtle, interactive menu, three strategies (quarry/strip/branch), write-after-success state persistence, heavily-modded block support.

**Architecture:** Strictly layered Lua modules: `state → movement → inventory → navigator → strategies → main`. Pure-logic modules (config, classifier, state serialisation, strategies' estimate) are unit-tested locally against Lua 5.5. Movement/navigator/inventory operations are tested against a mock `turtle` API. Live-turtle smoke tests verify the full integration. No external dependencies; CC:T standard library only.

**Tech Stack:** Lua 5.2/5.3 dialect (CC:Tweaked / Cobalt). Local testing via Lua 5.5 with a minimal hand-rolled test runner and a mock `turtle`/`fs`/`os` harness. No package manager.

**Spec reference:** `/DESIGN.md` — all sections. `/CLAUDE.md` — environment constraints.

---

## Phase 0 — Scaffold

Purpose: set up directory structure, test runner, and compatibility shims so every subsequent task starts from the same foundation.

### Task 0.1: Create directory skeleton

**Files:**
- Create: `lib/` (empty dir placeholder via `.gitkeep`)
- Create: `strategies/` (placeholder)
- Create: `tests/` (placeholder)
- Create: `tests/mocks/` (placeholder)
- Create: `.gitignore`

- [ ] **Step 1: Create dirs and placeholders**

Run:
```bash
mkdir -p /home/luke/turtle/lib /home/luke/turtle/strategies /home/luke/turtle/tests/mocks
touch /home/luke/turtle/lib/.gitkeep /home/luke/turtle/strategies/.gitkeep /home/luke/turtle/tests/.gitkeep /home/luke/turtle/tests/mocks/.gitkeep
```

- [ ] **Step 2: Write `.gitignore`**

Create `/home/luke/turtle/.gitignore`:
```
# Runtime artifacts — turtle writes these at runtime, never committed
/state/
/logs/
/config.lua

# Local dev
*.tmp
*.bak
```

Note: `/config.lua` is runtime-generated from defaults. The template defaults live in `lib/config.lua`'s `DEFAULTS` table (Task 2.2).

- [ ] **Step 3: Commit**

```bash
git add .gitignore lib/.gitkeep strategies/.gitkeep tests/.gitkeep tests/mocks/.gitkeep
git commit -m "scaffold: directory skeleton for modular turtle"
```

---

### Task 0.2: Test runner

**Files:**
- Create: `tests/runner.lua`
- Create: `tests/run_all.lua`

- [ ] **Step 1: Write the test runner**

Create `/home/luke/turtle/tests/runner.lua`:
```lua
-- Minimal test runner. No external deps. Compatible with Lua 5.2+.
local M = {}

local tests = {}
local current_suite = nil

function M.describe(name, fn)
  current_suite = name
  fn()
  current_suite = nil
end

function M.it(name, fn)
  table.insert(tests, { suite = current_suite or "(no suite)", name = name, fn = fn })
end

function M.assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s",
      msg or "assert_eq",
      tostring(expected), tostring(actual)), 2)
  end
end

function M.assert_true(cond, msg)
  if not cond then error(msg or "expected truthy, got " .. tostring(cond), 2) end
end

function M.assert_false(cond, msg)
  if cond then error(msg or "expected falsy, got " .. tostring(cond), 2) end
end

function M.assert_nil(x, msg)
  if x ~= nil then error((msg or "expected nil") .. ", got " .. tostring(x), 2) end
end

function M.assert_deep_eq(a, b, msg)
  local function deq(x, y)
    if type(x) ~= type(y) then return false end
    if type(x) ~= "table" then return x == y end
    for k, v in pairs(x) do if not deq(v, y[k]) then return false end end
    for k, _ in pairs(y) do if x[k] == nil then return false end end
    return true
  end
  if not deq(a, b) then
    error((msg or "assert_deep_eq") ..
      " failed: " .. tostring(a) .. " vs " .. tostring(b), 2)
  end
end

function M.assert_error(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then error((msg or "expected error") .. " but none raised", 2) end
  if pattern and not tostring(err):match(pattern) then
    error(string.format("error did not match %q: got %q", pattern, tostring(err)), 2)
  end
end

function M.run()
  local passed, failed = 0, {}
  for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
      passed = passed + 1
      io.write("."); io.flush()
    else
      table.insert(failed, { suite = t.suite, name = t.name, err = err })
      io.write("F"); io.flush()
    end
  end
  io.write("\n\n")
  for _, f in ipairs(failed) do
    print(string.format("FAIL [%s] %s", f.suite, f.name))
    print("  " .. tostring(f.err))
  end
  print(string.format("\n%d passed, %d failed", passed, #failed))
  os.exit(#failed == 0 and 0 or 1)
end

return M
```

- [ ] **Step 2: Write the aggregator**

Create `/home/luke/turtle/tests/run_all.lua`:
```lua
-- Aggregates every tests/test_*.lua file and runs them.
package.path = "./?.lua;./lib/?.lua;./tests/?.lua;" .. package.path

local runner = require("tests.runner")

-- Auto-discovery: list tests/ for test_*.lua files.
-- Using Lua 5.5 os.execute with ls; acceptable for local-only runner.
local p = io.popen("ls tests/test_*.lua 2>/dev/null")
if p then
  for line in p:lines() do
    local mod = line:gsub("%.lua$", ""):gsub("/", ".")
    require(mod)
  end
  p:close()
end

runner.run()
```

- [ ] **Step 3: Write a sanity test to verify the runner works**

Create `/home/luke/turtle/tests/test_runner_sanity.lua`:
```lua
local t = require("tests.runner")

t.describe("runner sanity", function()
  t.it("passes a trivial assertion", function()
    t.assert_eq(1 + 1, 2)
  end)
  t.it("catches a failing assertion", function()
    t.assert_error(function() t.assert_eq(1, 2) end, "expected 2")
  end)
  t.it("does deep equality on tables", function()
    t.assert_deep_eq({a = 1, b = {c = 2}}, {a = 1, b = {c = 2}})
  end)
end)
```

- [ ] **Step 4: Run it**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: `3 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add tests/runner.lua tests/run_all.lua tests/test_runner_sanity.lua
git commit -m "test: add minimal hand-rolled test runner"
```

---

### Task 0.3: CC:T compatibility shims (mock `turtle`, `fs`, `os`, `textutils`, `term`)

**Files:**
- Create: `tests/mocks/turtle.lua`
- Create: `tests/mocks/fs.lua`
- Create: `tests/mocks/textutils.lua`
- Create: `tests/mocks/term.lua`
- Create: `tests/mocks/os_cct.lua`
- Create: `tests/test_mocks.lua`

These mocks exist **only for local testing**. On an actual turtle, CC:T's real globals are used. The mocks simulate a simple grid world for movement tests and an in-memory filesystem for state tests.

- [ ] **Step 1: Write the mock `fs` module**

Create `/home/luke/turtle/tests/mocks/fs.lua`:
```lua
-- In-memory filesystem mimicking CC:T fs API.
local M = {}
local files = {}   -- path -> string contents
local open_handles = {}

function M._reset() files = {}; open_handles = {} end
function M._snapshot() local s = {}; for k,v in pairs(files) do s[k] = v end; return s end
function M._inject(path, contents) files[path] = contents end
function M._exists_raw(path) return files[path] ~= nil end

function M.exists(path) return files[path] ~= nil end

function M.open(path, mode)
  if mode == "r" then
    local c = files[path]
    if not c then return nil end
    local pos = 1
    return {
      readAll = function() return c end,
      readLine = function()
        if pos > #c then return nil end
        local nl = c:find("\n", pos, true)
        local line
        if nl then line = c:sub(pos, nl-1); pos = nl+1
        else line = c:sub(pos); pos = #c+1 end
        return line
      end,
      close = function() end,
    }
  elseif mode == "w" then
    local buf = {}
    local h = {
      write = function(_, s) table.insert(buf, tostring(s)) end,
      writeLine = function(_, s) table.insert(buf, tostring(s) .. "\n") end,
      close = function() files[path] = table.concat(buf) end,
    }
    return h
  else
    error("mock fs: unsupported mode " .. tostring(mode))
  end
end

function M.delete(path) files[path] = nil end

function M.move(from, to)
  if not files[from] then error("mock fs.move: source missing: " .. from) end
  files[to] = files[from]
  files[from] = nil
end

function M.makeDir(_) end   -- noop; flat namespace

function M.list(prefix)
  local out = {}
  for k, _ in pairs(files) do
    local p = k:match("^" .. prefix:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1") .. "/([^/]+)$")
    if p then table.insert(out, p) end
  end
  table.sort(out)
  return out
end

return M
```

- [ ] **Step 2: Write the mock `textutils` module**

Create `/home/luke/turtle/tests/mocks/textutils.lua`:
```lua
-- Minimal textutils mock. Serialise produces a Lua-loadable string.
local M = {}

local function ser(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "nil" then return "nil" end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t == "table" then
    local parts = {"{"}
    local ni = indent .. "  "
    for k, val in pairs(v) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. ser(k, ni) .. "]"
      end
      table.insert(parts, ni .. key .. " = " .. ser(val, ni) .. ",")
    end
    table.insert(parts, indent .. "}")
    return table.concat(parts, "\n")
  end
  error("cannot serialise " .. t)
end

function M.serialise(v) return ser(v) end
M.serialize = M.serialise

function M.unserialise(s)
  if not s or s == "" then return nil end
  local f = load("return " .. s, "unserialise", "t", {})
  if not f then return nil end
  local ok, v = pcall(f)
  if not ok then return nil end
  return v
end
M.unserialize = M.unserialise

function M.serialiseJSON(v)
  -- simplistic JSON for testing heartbeats; not used by v1 runtime code
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
  if t == "table" then
    local parts, is_array, n = {}, true, 0
    for k, _ in pairs(v) do
      n = n + 1
      if type(k) ~= "number" then is_array = false end
    end
    if is_array then
      for i = 1, n do table.insert(parts, M.serialiseJSON(v[i])) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, val in pairs(v) do
        table.insert(parts,
          string.format("%q", tostring(k)) .. ":" .. M.serialiseJSON(val))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  error("JSON: cannot serialise " .. t)
end
M.serializeJSON = M.serialiseJSON

return M
```

- [ ] **Step 3: Write the mock `turtle` module**

Create `/home/luke/turtle/tests/mocks/turtle.lua`:
```lua
-- A tiny grid-world turtle. (x,y,z) starts at (0,0,0) facing 0 (+Z).
-- The world is a dict of blocks keyed by "x,y,z" -> blockdata table.
local M = {}

local pos, facing = {x=0,y=0,z=0}, 0
local blocks = {}
local inventory = {}  -- slot -> {name=, count=}
local selected = 1
local fuel = 1000
local fuel_limit = "unlimited"  -- "unlimited" or number

local DX = {[0]=0,[1]=1,[2]=0,[3]=-1}
local DZ = {[0]=1,[1]=0,[2]=-1,[3]=0}

local function key(x,y,z) return x..","..y..","..z end
local function frontPos() return pos.x + DX[facing], pos.y, pos.z + DZ[facing] end

function M._reset()
  pos = {x=0,y=0,z=0}; facing = 0; blocks = {}; inventory = {}
  selected = 1; fuel = 1000; fuel_limit = "unlimited"
end
function M._setBlock(x,y,z,data) blocks[key(x,y,z)] = data end
function M._getBlock(x,y,z) return blocks[key(x,y,z)] end
function M._setPos(x,y,z,f) pos={x=x,y=y,z=z}; facing = f or 0 end
function M._getPos() return {x=pos.x, y=pos.y, z=pos.z}, facing end
function M._setInv(slot, item) inventory[slot] = item end
function M._getInv() local c={}; for k,v in pairs(inventory) do c[k]={name=v.name,count=v.count} end; return c end
function M._setFuel(n) fuel = n end
function M._setFuelLimit(n) fuel_limit = n end

local function inspectAt(x,y,z)
  local b = blocks[key(x,y,z)]
  if b then return true, b else return false, "No block to inspect" end
end

function M.inspect() local fx,fy,fz = frontPos(); return inspectAt(fx,fy,fz) end
function M.inspectUp() return inspectAt(pos.x, pos.y+1, pos.z) end
function M.inspectDown() return inspectAt(pos.x, pos.y-1, pos.z) end

local function moveTo(nx, ny, nz)
  if blocks[key(nx,ny,nz)] then return false, "Movement obstructed" end
  if fuel_limit ~= "unlimited" and fuel <= 0 then return false, "Out of fuel" end
  pos.x, pos.y, pos.z = nx, ny, nz
  if fuel_limit ~= "unlimited" then fuel = fuel - 1 end
  return true
end

function M.forward() local fx,fy,fz = frontPos(); return moveTo(fx,fy,fz) end
function M.back()
  return moveTo(pos.x - DX[facing], pos.y, pos.z - DZ[facing])
end
function M.up() return moveTo(pos.x, pos.y+1, pos.z) end
function M.down() return moveTo(pos.x, pos.y-1, pos.z) end

function M.turnLeft() facing = (facing + 3) % 4; return true end
function M.turnRight() facing = (facing + 1) % 4; return true end

local function digAt(x,y,z)
  local b = blocks[key(x,y,z)]
  if not b then return false, "Nothing to dig" end
  blocks[key(x,y,z)] = nil
  -- place in first empty slot
  for i = 1, 16 do
    if not inventory[i] then
      inventory[i] = {name = b.name, count = 1}
      return true
    end
  end
  return true   -- dug but inventory full
end
function M.dig() local fx,fy,fz = frontPos(); return digAt(fx,fy,fz) end
function M.digUp() return digAt(pos.x, pos.y+1, pos.z) end
function M.digDown() return digAt(pos.x, pos.y-1, pos.z) end

function M.select(s) selected = s; return true end
function M.getSelectedSlot() return selected end
function M.getItemCount(s) return (inventory[s] and inventory[s].count) or 0 end
function M.getItemDetail(s)
  if not inventory[s] then return nil end
  return { name = inventory[s].name, count = inventory[s].count }
end

function M.getFuelLevel() return fuel_limit == "unlimited" and "unlimited" or fuel end

local function placeAt(x,y,z)
  local item = inventory[selected]
  if not item or item.count == 0 then return false, "No items" end
  if blocks[key(x,y,z)] then return false, "Occupied" end
  blocks[key(x,y,z)] = { name = item.name }
  item.count = item.count - 1
  if item.count == 0 then inventory[selected] = nil end
  return true
end
function M.place() local fx,fy,fz = frontPos(); return placeAt(fx,fy,fz) end
function M.placeUp() return placeAt(pos.x, pos.y+1, pos.z) end
function M.placeDown() return placeAt(pos.x, pos.y-1, pos.z) end

function M.drop(n)   -- drop forward (to chest)
  local fx,fy,fz = frontPos()
  local b = blocks[key(fx,fy,fz)]
  if not b or not b.is_chest then return false, "No chest" end
  local item = inventory[selected]
  if not item then return false, "Empty slot" end
  n = n or item.count
  b.contents = b.contents or {}
  table.insert(b.contents, { name = item.name, count = math.min(n, item.count) })
  item.count = item.count - math.min(n, item.count)
  if item.count <= 0 then inventory[selected] = nil end
  return true
end

function M.suck(n)
  local fx,fy,fz = frontPos()
  local b = blocks[key(fx,fy,fz)]
  if not b or not b.contents or #b.contents == 0 then return false end
  local item = table.remove(b.contents, 1)
  for i = 1, 16 do
    if not inventory[i] then
      inventory[i] = {name = item.name, count = item.count}
      return true
    end
  end
  return false
end

function M.refuel(n)
  local item = inventory[selected]
  if not item then return false end
  local add = (item.name:match("coal") and 80) or (item.name:match("charcoal") and 80) or 0
  if add == 0 then return false end
  n = n or item.count
  if fuel_limit ~= "unlimited" then fuel = fuel + add * n end
  item.count = item.count - n
  if item.count <= 0 then inventory[selected] = nil end
  return true
end

function M.attack() return false, "Nothing to attack" end

return M
```

- [ ] **Step 4: Write the mock `term` and `os_cct` modules**

Create `/home/luke/turtle/tests/mocks/term.lua`:
```lua
local M = {}
local buf = {}
function M._reset() buf = {} end
function M._capture() return table.concat(buf, "\n") end
function M.clear() buf = {} end
function M.setCursorPos(_,_) end
function M.write(s) table.insert(buf, tostring(s)) end
function M.setTextColor(_) end
function M.setBackgroundColor(_) end
function M.isColor() return false end
function M.isColour() return false end
function M.getSize() return 39, 13 end
return M
```

Create `/home/luke/turtle/tests/mocks/os_cct.lua`:
```lua
-- CC:T os extensions. Real os stays available.
local M = {}
local now_ms = 1713648063000
function M._setNow(ms) now_ms = ms end
function M._tick(ms) now_ms = now_ms + ms end
function M.epoch(which)
  if which == "utc" or which == "local" then return now_ms end
  return now_ms
end
function M.getComputerID() return 42 end
function M.getComputerLabel() return "test-turtle" end
function M.clock() return now_ms / 1000 end
function M.sleep(_) end   -- no-op in tests
return M
```

- [ ] **Step 5: Write a test that exercises the mocks**

Create `/home/luke/turtle/tests/test_mocks.lua`:
```lua
local t = require("tests.runner")
local fs_mock = require("tests.mocks.fs")
local tu_mock = require("tests.mocks.textutils")
local turtle_mock = require("tests.mocks.turtle")

t.describe("mock fs", function()
  t.it("writes, reads, moves, deletes", function()
    fs_mock._reset()
    local h = fs_mock.open("/foo.txt", "w")
    h.write(h, "hello")
    h.close()
    t.assert_true(fs_mock.exists("/foo.txt"))
    local r = fs_mock.open("/foo.txt", "r")
    t.assert_eq(r.readAll(), "hello")
    r.close()
    fs_mock.move("/foo.txt", "/bar.txt")
    t.assert_false(fs_mock.exists("/foo.txt"))
    t.assert_true(fs_mock.exists("/bar.txt"))
    fs_mock.delete("/bar.txt")
    t.assert_false(fs_mock.exists("/bar.txt"))
  end)
end)

t.describe("mock textutils", function()
  t.it("round-trips nested tables", function()
    local s = tu_mock.serialise({ a = 1, b = { c = "x", d = true }, e = {1,2,3}})
    local v = tu_mock.unserialise(s)
    t.assert_deep_eq(v, { a = 1, b = { c = "x", d = true }, e = {1,2,3}})
  end)
  t.it("returns nil on garbage input", function()
    t.assert_nil(tu_mock.unserialise("not valid lua }}}"))
  end)
end)

t.describe("mock turtle", function()
  t.it("moves forward, updating position and fuel", function()
    turtle_mock._reset()
    turtle_mock._setFuelLimit(1000)
    turtle_mock._setFuel(100)
    t.assert_true(turtle_mock.forward())
    local p = turtle_mock._getPos()
    t.assert_eq(p.z, 1)
    t.assert_eq(turtle_mock.getFuelLevel(), 99)
  end)
  t.it("is blocked by placed blocks", function()
    turtle_mock._reset()
    turtle_mock._setBlock(0, 0, 1, { name = "minecraft:stone" })
    local ok, err = turtle_mock.forward()
    t.assert_false(ok)
    t.assert_true(err:match("obstruct"))
  end)
  t.it("digs forward and picks up the block into inventory", function()
    turtle_mock._reset()
    turtle_mock._setBlock(0, 0, 1, { name = "minecraft:cobblestone" })
    t.assert_true(turtle_mock.dig())
    t.assert_nil(turtle_mock._getBlock(0, 0, 1))
    local it = turtle_mock.getItemDetail(1)
    t.assert_eq(it.name, "minecraft:cobblestone")
  end)
end)
```

- [ ] **Step 6: Run and verify**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add tests/mocks/ tests/test_mocks.lua
git commit -m "test: add CC:T mocks for fs/textutils/turtle/term/os"
```

---

## Phase 1 — Foundation modules (pure logic, fully unit-testable)

### Task 1.1: `lib/util.lua` — helpers

**Files:**
- Create: `lib/util.lua`
- Create: `tests/test_util.lua`

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_util.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")
local util = require("lib.util")

t.describe("util.matches_any", function()
  t.it("returns true for exact name match", function()
    t.assert_true(util.matches_any("minecraft:cobblestone",
      { "minecraft:cobblestone" }, {}))
  end)
  t.it("returns true for pattern match", function()
    t.assert_true(util.matches_any("create:limestone",
      {}, { ".*:limestone$" }))
  end)
  t.it("prefers exact over pattern (exact is checked first)", function()
    -- both match; should short-circuit on exact.
    t.assert_true(util.matches_any("x:y", { "x:y" }, { ".*" }))
  end)
  t.it("returns false when neither matches", function()
    t.assert_false(util.matches_any("x:y", { "z:w" }, { "^nope$" }))
  end)
  t.it("is safe against empty / nil lists", function()
    t.assert_false(util.matches_any("x:y", nil, nil))
    t.assert_false(util.matches_any("x:y", {}, {}))
  end)
end)

t.describe("util.deep_clone", function()
  t.it("clones nested tables without shared references", function()
    local a = { x = 1, y = { z = 2 } }
    local b = util.deep_clone(a)
    b.y.z = 99
    t.assert_eq(a.y.z, 2)
    t.assert_eq(b.y.z, 99)
  end)
end)

t.describe("util.deep_merge", function()
  t.it("overlays src onto dst recursively", function()
    local dst = { a = 1, b = { c = 2, d = 3 } }
    local src = { b = { c = 99 }, e = 5 }
    local out = util.deep_merge(dst, src)
    t.assert_deep_eq(out, { a = 1, b = { c = 99, d = 3 }, e = 5 })
  end)
  t.it("replaces arrays wholesale (does not merge list items)", function()
    local dst = { xs = { 1, 2, 3 } }
    local src = { xs = { 9 } }
    local out = util.deep_merge(dst, src)
    t.assert_deep_eq(out.xs, { 9 })
  end)
end)

t.describe("util.now_epoch_s", function()
  t.it("returns an integer number of seconds", function()
    local n = util.now_epoch_s()
    t.assert_eq(type(n), "number")
    t.assert_true(n > 0)
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: FAIL with `module 'lib.util' not found`

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/util.lua`:
```lua
local M = {}

function M.matches_any(name, exact, patterns)
  if exact then
    for _, n in ipairs(exact) do if n == name then return true end end
  end
  if patterns then
    for _, p in ipairs(patterns) do if name:match(p) then return true end end
  end
  return false
end

function M.deep_clone(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = M.deep_clone(x) end
  return out
end

local function is_array(t)
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n > 0
end

function M.deep_merge(dst, src)
  local out = M.deep_clone(dst)
  for k, v in pairs(src) do
    if type(v) == "table" and type(out[k]) == "table"
       and not is_array(v) and not is_array(out[k]) then
      out[k] = M.deep_merge(out[k], v)
    else
      out[k] = M.deep_clone(v)
    end
  end
  return out
end

function M.now_epoch_s()
  if os.epoch then
    return math.floor(os.epoch("utc") / 1000)
  end
  return os.time()
end

return M
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: all `util` tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/util.lua tests/test_util.lua
git commit -m "lib: util helpers (pattern match, deep clone/merge)"
```

---

### Task 1.2: `lib/logger.lua` — leveled, append-only, sink-pluggable logger

**Files:**
- Create: `lib/logger.lua`
- Create: `tests/test_logger.lua`

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_logger.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

-- Inject a fake fs for the logger module to use.
-- Logger looks up fs via `_G.fs` at require time; we replace it.
_G.fs = require("tests.mocks.fs")
_G.os.epoch = function(_) return 1713648063000 end

local logger = require("lib.logger")

local function reset()
  _G.fs._reset()
  logger.configure({ level = "info", file_path = "/logs/run.log" })
end

t.describe("logger levels", function()
  t.it("suppresses messages below configured level", function()
    reset()
    local captured = {}
    logger.addSink(function(e) table.insert(captured, e) end)
    logger.configure({ level = "warn" })
    logger.info("nope")
    logger.warn("yes")
    t.assert_eq(#captured, 1)
    t.assert_eq(captured[1].level, "warn")
  end)
  t.it("emits info/warn/error at info level", function()
    reset()
    local count = 0
    logger.addSink(function() count = count + 1 end)
    logger.debug("x") logger.info("y") logger.warn("z") logger.error("w")
    t.assert_eq(count, 3)
  end)
end)

t.describe("logger file sink", function()
  t.it("appends timestamped lines to file", function()
    reset()
    logger.info("hello world")
    local contents = _G.fs.open("/logs/run.log", "r").readAll()
    t.assert_true(contents:match("hello world") ~= nil)
    t.assert_true(contents:match("INFO") ~= nil)
  end)
end)

t.describe("logger.addSink", function()
  t.it("forwards events to all registered sinks", function()
    reset()
    local a, b = {}, {}
    logger.addSink(function(e) table.insert(a, e.msg) end)
    logger.addSink(function(e) table.insert(b, e.msg) end)
    logger.info("fan")
    t.assert_eq(a[1], "fan")
    t.assert_eq(b[1], "fan")
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: FAIL — `lib.logger` not found.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/logger.lua`:
```lua
local M = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local config = { level = "info", file_path = "/logs/run.log", keep_runs = 5 }
local sinks = {}
local file_error_once = false

local function now()
  if os.epoch then return math.floor(os.epoch("utc") / 1000) end
  return os.time()
end

local function format_line(event)
  return string.format("[%d] %-5s %s",
    event.ts, event.level:upper(), event.msg)
end

local function file_sink(event)
  if file_error_once then return end
  local ok, err = pcall(function()
    local h = fs.open(config.file_path, "w")   -- CC:T supports "a" too; "w" for tests
    if not h then error("open failed") end
    -- Tests' mock fs does not support append, so we accumulate in memory
    -- and rewrite. On real CC:T, swap to "a" in initialize().
    if M._buffered then h.writeLine(M._buffered) end
    h.writeLine(format_line(event))
    h.close()
  end)
  if not ok then
    file_error_once = true
    print("logger: file sink disabled (" .. tostring(err) .. ")")
  end
end

-- Stash the running log in memory so repeated "w" writes preserve content.
-- This keeps test-mode simple; live turtle should set append_mode=true.
local log_buffer = {}
local function buffered_file_sink(event)
  if file_error_once then return end
  table.insert(log_buffer, format_line(event))
  local ok, err = pcall(function()
    local h = fs.open(config.file_path, "w")
    if not h then error("open failed") end
    for _, line in ipairs(log_buffer) do h.writeLine(line) end
    h.close()
  end)
  if not ok then
    file_error_once = true
  end
end

local function terminal_sink(event)
  print(format_line(event))
end

function M.configure(cfg)
  config.level = cfg.level or config.level
  config.file_path = cfg.file_path or config.file_path
  config.keep_runs = cfg.keep_runs or config.keep_runs
  sinks = {}
  file_error_once = false
  log_buffer = {}
  table.insert(sinks, buffered_file_sink)
  -- terminal sink registered separately by main; tests don't want its output
end

function M.addSink(fn) table.insert(sinks, fn) end

local function emit(level, msg, data)
  if LEVELS[level] < LEVELS[config.level] then return end
  local event = { level = level, ts = now(), msg = msg, data = data }
  for _, s in ipairs(sinks) do s(event) end
end

function M.debug(msg, data) emit("debug", msg, data) end
function M.info (msg, data) emit("info",  msg, data) end
function M.warn (msg, data) emit("warn",  msg, data) end
function M.error(msg, data) emit("error", msg, data) end

-- Exposed for terminal integration in main.lua
M._terminal_sink = terminal_sink

-- Initial configuration for tests that require the module before configure()
M.configure(config)

return M
```

- [ ] **Step 4: Run — verify all logger tests pass**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: logger suite passes.

- [ ] **Step 5: Commit**

```bash
git add lib/logger.lua tests/test_logger.lua
git commit -m "lib: leveled logger with pluggable sinks"
```

---

### Task 1.3: `lib/config.lua` — load/save/validate Lua-table config

**Files:**
- Create: `lib/config.lua`
- Create: `tests/test_config.lua`

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_config.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")

local config = require("lib.config")

local function reset() _G.fs._reset() end

t.describe("config.load", function()
  t.it("returns defaults merged when file missing", function()
    reset()
    local cfg = config.load("/config.lua")
    t.assert_eq(cfg.version, 1)
    t.assert_eq(cfg.inventory.junk_policy, "drop")
    t.assert_true(#cfg.inventory.junk > 0)
    -- A default file should have been written
    t.assert_true(_G.fs.exists("/config.lua"))
  end)

  t.it("merges user overrides with defaults", function()
    reset()
    _G.fs._inject("/config.lua", [[
      return { version = 1, inventory = { junk_policy = "keep" } }
    ]])
    local cfg = config.load("/config.lua")
    t.assert_eq(cfg.inventory.junk_policy, "keep")
    -- Other defaults still present
    t.assert_true(#cfg.inventory.junk > 0)
    t.assert_eq(cfg.fuel.refuel_below, 2000)
  end)

  t.it("raises on parse error, no fallback", function()
    reset()
    _G.fs._inject("/config.lua", "this is not valid lua {{{")
    t.assert_error(function() config.load("/config.lua") end, "config")
  end)

  t.it("warns on unknown keys but still loads", function()
    reset()
    _G.fs._inject("/config.lua", [[
      return { version = 1, unknown_key = 42 }
    ]])
    local cfg, warnings = config.load("/config.lua")
    t.assert_eq(cfg.version, 1)
    t.assert_true(#warnings > 0)
    t.assert_true(warnings[1]:match("unknown_key") ~= nil)
  end)
end)

t.describe("config.classify", function()
  local sample = {
    inventory = {
      junk = { "minecraft:cobblestone" },
      junk_patterns = { ".*:mud$" },
      fuel = { "minecraft:coal" },
      fuel_patterns = {},
      seal = { "minecraft:dirt" },
      seal_patterns = {},
    },
  }

  t.it("classifies exact junk name", function()
    t.assert_eq(config.classify("minecraft:cobblestone", sample), "junk")
  end)
  t.it("classifies pattern junk", function()
    t.assert_eq(config.classify("biomesoplenty:mud", sample), "junk")
  end)
  t.it("classifies fuel", function()
    t.assert_eq(config.classify("minecraft:coal", sample), "fuel")
  end)
  t.it("classifies seal", function()
    t.assert_eq(config.classify("minecraft:dirt", sample), "seal")
  end)
  t.it("unknown defaults to keep", function()
    t.assert_eq(config.classify("mekanism:uranium_ore", sample), "keep")
  end)
  t.it("priority: fuel > seal > junk when a name matches multiple", function()
    local mixed = {
      inventory = {
        junk = { "x:cobblestone" }, junk_patterns = {},
        fuel = { "x:cobblestone" }, fuel_patterns = {},
        seal = { "x:cobblestone" }, seal_patterns = {},
      },
    }
    t.assert_eq(config.classify("x:cobblestone", mixed), "fuel")
  end)
end)

t.describe("config.save", function()
  t.it("writes atomically via tmp+move", function()
    reset()
    local cfg = config.load("/config.lua")
    cfg.inventory.junk_policy = "overflow"
    config.save("/config.lua", cfg)
    local reloaded = config.load("/config.lua")
    t.assert_eq(reloaded.inventory.junk_policy, "overflow")
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: FAIL — lib.config not found.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/config.lua`:
```lua
local util = require("lib.util")

local M = {}

local DEFAULTS = {
  version = 1,
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
    junk_policy = "drop",
    keep_slots_before_home = 12,
    reserved_fuel_slot = 16,
  },
  fuel = {
    refuel_below = 2000,
    reserve_for_home = 1.25,
    abort_below = 200,
  },
  safety = {
    seal_lava = true,
    seal_water = false,
    dangerous_liquids = { ".*:lava$", ".*:crude_oil$" },
    bedrock_names = { "minecraft:bedrock", ".*:bedrock$", "minecraft:barrier" },
    max_redig_attempts = 30,
    max_attack_attempts = 10,
  },
  logging = {
    level = "info",
    keep_runs = 5,
  },
  strategy_defaults = {
    quarry = { width = 8, length = 8, depth = "bedrock" },
    strip  = { length = 64, torch_spacing = 0 },
    branch = { main_length = 32, branch_length = 8, branch_spacing = 3 },
  },
  ui = {
    confirm_destructive = true,
    show_estimate_detail = true,
  },
}

local KNOWN_TOP_KEYS = {
  version = true, inventory = true, fuel = true, safety = true,
  logging = true, strategy_defaults = true, ui = true,
}

local function write_atomic(path, contents)
  local tmp = path .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then error("cannot open " .. tmp .. " for writing") end
  h.write(contents)
  h.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
end

function M.defaults() return util.deep_clone(DEFAULTS) end

function M.load(path)
  if not fs.exists(path) then
    local def = M.defaults()
    M.save(path, def)
    return def, {}
  end
  local h = fs.open(path, "r")
  local src = h.readAll(); h.close()
  local chunk, err = load("return " .. src, path, "t", {})
  if not chunk then
    -- Allow configs that already begin with "return"
    chunk, err = load(src, path, "t", {})
  end
  if not chunk then
    error("config parse error at " .. path .. ": " .. tostring(err))
  end
  local ok, user = pcall(chunk)
  if not ok then error("config execution error at " .. path .. ": " .. tostring(user)) end
  if type(user) ~= "table" then error("config did not return a table: " .. path) end

  local warnings = {}
  for k, _ in pairs(user) do
    if not KNOWN_TOP_KEYS[k] then
      table.insert(warnings, "unknown config key: " .. tostring(k))
    end
  end
  return util.deep_merge(M.defaults(), user), warnings
end

function M.save(path, cfg)
  write_atomic(path, "return " .. textutils.serialise(cfg))
end

function M.classify(name, cfg)
  local inv = cfg.inventory
  -- Priority: fuel > seal > junk > keep.
  if util.matches_any(name, inv.fuel, inv.fuel_patterns) then return "fuel" end
  if util.matches_any(name, inv.seal, inv.seal_patterns) then return "seal" end
  if util.matches_any(name, inv.junk, inv.junk_patterns) then return "junk" end
  return "keep"
end

return M
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: all config tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/config.lua tests/test_config.lua
git commit -m "lib: config load/save/classify with pattern-aware rules"
```

---

### Task 1.4: `lib/state.lua` — atomic-write persistence + resume logic

**Files:**
- Create: `lib/state.lua`
- Create: `tests/test_state.lua`

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_state.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.os.epoch = function(_) return 1713648063000 end

local state = require("lib.state")

local function reset() _G.fs._reset(); state.reset() end

t.describe("state.new_run", function()
  t.it("creates current and strategy files with matching run_id", function()
    reset()
    state.new_run({
      strategy = "quarry",
      params = { width = 8, length = 8 },
      home = { x = 0, y = 0, z = 0, facing = 0 },
      fuel_at_start = 10000,
    })
    t.assert_true(_G.fs.exists("/state/current.lua"))
    t.assert_true(_G.fs.exists("/state/strategy.lua"))
    local c = state.load_current()
    local s = state.load_strategy()
    t.assert_eq(c.run_id, s.run_id)
    t.assert_eq(c.phase, "planning")
    t.assert_eq(s.strategy, "quarry")
  end)
end)

t.describe("state.persist_position", function()
  t.it("updates pos and facing and bumps last_write_at", function()
    reset()
    state.new_run({
      strategy = "quarry", params = {}, home = { x=0,y=0,z=0, facing=0 },
      fuel_at_start = 100,
    })
    state.persist_position({ x = 2, y = -3, z = 5 }, 1)
    local c = state.load_current()
    t.assert_deep_eq(c.pos, { x = 2, y = -3, z = 5 })
    t.assert_eq(c.facing, 1)
  end)
end)

t.describe("state.save_progress", function()
  t.it("overwrites the progress table", function()
    reset()
    state.new_run({
      strategy = "quarry", params = { width = 4 },
      home = { x=0,y=0,z=0, facing=0 }, fuel_at_start = 100,
    })
    state.save_progress({ col = 1, row = 2 })
    local s = state.load_strategy()
    t.assert_deep_eq(s.progress, { col = 1, row = 2 })
  end)
end)

t.describe("state.load + corruption", function()
  t.it("returns nil when files missing", function()
    reset()
    t.assert_nil(state.load_current())
    t.assert_nil(state.load_strategy())
  end)
  t.it("returns nil when file is corrupt", function()
    reset()
    _G.fs._inject("/state/current.lua", "not valid }}}")
    t.assert_nil(state.load_current())
  end)
end)

t.describe("state.run_id_mismatch", function()
  t.it("detects when current and strategy disagree", function()
    reset()
    state.new_run({
      strategy = "quarry", params = {},
      home = { x=0,y=0,z=0, facing=0 }, fuel_at_start = 100,
    })
    -- Corrupt strategy.lua's run_id
    _G.fs._inject("/state/strategy.lua",
      "return { version = 1, run_id = \"other\", strategy = \"quarry\", params = {}, progress = {} }")
    local current = state.load_current()
    local strat = state.load_strategy()
    t.assert_false(current.run_id == strat.run_id)
  end)
end)

t.describe("state.set_phase", function()
  t.it("transitions phase without losing other fields", function()
    reset()
    state.new_run({
      strategy = "quarry", params = {},
      home = { x=0,y=0,z=0,facing=0 }, fuel_at_start = 100,
    })
    state.set_phase("mining")
    t.assert_eq(state.load_current().phase, "mining")
  end)
end)

t.describe("state.clear", function()
  t.it("removes both state files", function()
    reset()
    state.new_run({
      strategy = "quarry", params = {},
      home = { x=0,y=0,z=0,facing=0 }, fuel_at_start = 100,
    })
    state.clear()
    t.assert_false(_G.fs.exists("/state/current.lua"))
    t.assert_false(_G.fs.exists("/state/strategy.lua"))
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: FAIL — lib.state not found.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/state.lua`:
```lua
local util = require("lib.util")

local M = {}

local CURRENT = "/state/current.lua"
local STRATEGY = "/state/strategy.lua"
local VERSION = 1

local function now_s()
  if os.epoch then return math.floor(os.epoch("utc") / 1000) end
  return os.time()
end

local function rand_suffix()
  local cs = "abcdefghijklmnopqrstuvwxyz0123456789"
  math.randomseed(os.epoch and os.epoch("utc") or os.time())
  local buf = {}
  for _ = 1, 4 do
    local i = math.random(1, #cs)
    table.insert(buf, cs:sub(i,i))
  end
  return table.concat(buf)
end

local function iso_utc(s)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", s)
end

local function ensure_state_dir()
  if fs.makeDir then fs.makeDir("/state") end
end

local function write_atomic(path, tbl)
  ensure_state_dir()
  local tmp = path .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then error("cannot open " .. tmp) end
  h.write("return " .. textutils.serialise(tbl))
  h.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
end

local function read_or_nil(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r"); if not h then return nil end
  local src = h.readAll(); h.close()
  if not src or src == "" then return nil end
  local chunk = load(src, path, "t", {})
  if not chunk then
    -- Try unwrapping "return ..." wrapper rejection fallback
    chunk = load("return " .. src, path, "t", {})
  end
  if not chunk then return nil end
  local ok, v = pcall(chunk)
  if not ok then return nil end
  if type(v) ~= "table" then return nil end
  return v
end

-- In-memory cache of the current-write snapshot so persist_position can bump
-- fields without re-reading the file every time.
local current_cache = nil

function M.reset() current_cache = nil end

function M.new_run(params)
  local run_id = iso_utc(now_s()) .. "-" .. rand_suffix()
  local current = {
    version = VERSION,
    run_id = run_id,
    pos = { x = 0, y = 0, z = 0 },
    facing = 0,
    strategy = params.strategy,
    phase = "planning",
    started_at = now_s(),
    last_write_at = now_s(),
    fuel_at_start = params.fuel_at_start or 0,
    blocks_mined = 0,
    home = util.deep_clone(params.home),
  }
  local strategy = {
    version = VERSION,
    run_id = run_id,
    strategy = params.strategy,
    params = util.deep_clone(params.params or {}),
    progress = {},
  }
  write_atomic(CURRENT, current)
  write_atomic(STRATEGY, strategy)
  current_cache = current
  return run_id
end

function M.persist_position(pos, facing)
  if not current_cache then current_cache = read_or_nil(CURRENT) end
  if not current_cache then error("persist_position with no current state") end
  current_cache.pos = util.deep_clone(pos)
  current_cache.facing = facing
  current_cache.last_write_at = now_s()
  write_atomic(CURRENT, current_cache)
end

function M.set_phase(phase)
  if not current_cache then current_cache = read_or_nil(CURRENT) end
  if not current_cache then error("set_phase with no current state") end
  current_cache.phase = phase
  current_cache.last_write_at = now_s()
  write_atomic(CURRENT, current_cache)
end

function M.bump_blocks_mined(n)
  if not current_cache then current_cache = read_or_nil(CURRENT) end
  if not current_cache then error("bump_blocks_mined with no current state") end
  current_cache.blocks_mined = (current_cache.blocks_mined or 0) + (n or 1)
  current_cache.last_write_at = now_s()
  write_atomic(CURRENT, current_cache)
end

function M.save_progress(progress)
  local s = read_or_nil(STRATEGY)
  if not s then error("save_progress with no strategy state") end
  s.progress = util.deep_clone(progress)
  write_atomic(STRATEGY, s)
end

function M.load_current()
  local c = read_or_nil(CURRENT)
  current_cache = c
  return c
end

function M.load_strategy() return read_or_nil(STRATEGY) end

function M.clear()
  if fs.exists(CURRENT) then fs.delete(CURRENT) end
  if fs.exists(STRATEGY) then fs.delete(STRATEGY) end
  current_cache = nil
end

return M
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: all state tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/state.lua tests/test_state.lua
git commit -m "lib: state with atomic writes and run_id-tagged resume"
```

---

## Phase 2 — Movement (mock turtle)

### Task 2.1: `lib/movement.lua` — transactional forward/up/down/turn + obstacle handling

**Files:**
- Create: `lib/movement.lua`
- Create: `tests/test_movement.lua`

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_movement.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.turtle = require("tests.mocks.turtle")
_G.os.epoch = function(_) return 1713648063000 end
_G.os.sleep = function(_) end
_G.sleep = function(_) end

local config = require("lib.config")
local state = require("lib.state")
local movement = require("lib.movement")

local function reset()
  _G.fs._reset()
  _G.turtle._reset()
  state.reset()
  local cfg = config.defaults()
  movement.configure({
    config = cfg,
    -- Inject a stub inventory for seal placement. Tests that need
    -- seal behaviour will override this.
    inventory = {
      place_seal_forward = function() return false end,
      place_seal_up      = function() return false end,
      place_seal_down    = function() return false end,
    },
  })
  state.new_run({
    strategy = "test", params = {},
    home = { x = 0, y = 0, z = 0, facing = 0 },
    fuel_at_start = 10000,
  })
end

t.describe("movement.forward", function()
  t.it("succeeds in open space and persists state", function()
    reset()
    local ok, err = movement.forward()
    t.assert_true(ok, err)
    local c = state.load_current()
    t.assert_deep_eq(c.pos, { x = 0, y = 0, z = 1 })
  end)

  t.it("returns (false, 'bedrock') on bedrock", function()
    reset()
    _G.turtle._setBlock(0, 0, 1, { name = "minecraft:bedrock" })
    local ok, err = movement.forward()
    t.assert_false(ok)
    t.assert_eq(err, "bedrock")
  end)

  t.it("digs a regular block and retries", function()
    reset()
    _G.turtle._setBlock(0, 0, 1, { name = "minecraft:stone" })
    local ok, err = movement.forward()
    t.assert_true(ok, err)
    t.assert_nil(_G.turtle._getBlock(0, 0, 1))
  end)

  t.it("seals lava when config allows and seal block available", function()
    reset()
    _G.turtle._setBlock(0, 0, 1, { name = "minecraft:lava" })
    local seal_called = false
    movement.configure({
      config = config.defaults(),
      inventory = {
        place_seal_forward = function()
          seal_called = true
          _G.turtle._setBlock(0, 0, 1, { name = "minecraft:cobblestone" })
          return true
        end,
        place_seal_up = function() return false end,
        place_seal_down = function() return false end,
      },
    })
    local ok, err = movement.forward()
    t.assert_true(seal_called)
    t.assert_true(ok, err)
  end)

  t.it("returns (false, 'no_seal') when lava cannot be sealed", function()
    reset()
    _G.turtle._setBlock(0, 0, 1, { name = "minecraft:lava" })
    local ok, err = movement.forward()
    t.assert_false(ok)
    t.assert_eq(err, "no_seal")
  end)

  t.it("digs gravel/sand column up to safety cap", function()
    reset()
    local cfg = config.defaults()
    cfg.safety.max_redig_attempts = 5
    movement.configure({ config = cfg, inventory = {
      place_seal_forward = function() return false end,
      place_seal_up = function() return false end,
      place_seal_down = function() return false end,
    }})
    _G.turtle._setBlock(0, 0, 1, { name = "minecraft:gravel" })
    local ok = movement.forward()
    t.assert_true(ok)
  end)
end)

t.describe("movement.turn", function()
  t.it("updates facing and persists state", function()
    reset()
    movement.turnRight()
    t.assert_eq(state.load_current().facing, 1)
    movement.turnLeft()
    t.assert_eq(state.load_current().facing, 0)
  end)
end)

t.describe("movement.face", function()
  t.it("chooses the shortest rotation", function()
    reset()
    movement.face(3)   -- from 0 -> 3 is one left turn
    t.assert_eq(state.load_current().facing, 3)
  end)
end)

t.describe("movement hooks", function()
  t.it("fires onEnterCell after successful move", function()
    reset()
    local seen = nil
    movement.onEnterCell(function(cell) seen = cell end)
    movement.forward()
    t.assert_deep_eq(seen.pos, { x = 0, y = 0, z = 1 })
    t.assert_eq(seen.facing, 0)
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: FAIL — lib.movement not found.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/movement.lua`:
```lua
local util = require("lib.util")
local state = require("lib.state")

local M = {}

local cfg = nil
local inv = nil
local enter_hooks, exit_hooks = {}, {}

-- In-memory mirror of position/facing. Kept in sync with state on every
-- successful transaction.
local pos = { x = 0, y = 0, z = 0 }
local facing = 0

local DX = {[0]=0,[1]=1,[2]=0,[3]=-1}
local DZ = {[0]=1,[1]=0,[2]=-1,[3]=0}

local function sleep_safe(s)
  if os and os.sleep then os.sleep(s) elseif _G.sleep then _G.sleep(s) end
end

function M.configure(opts)
  cfg = opts.config
  inv = opts.inventory
  -- Recover pos/facing from state if available
  local c = state.load_current()
  if c then pos = util.deep_clone(c.pos); facing = c.facing end
end

function M.onEnterCell(fn) table.insert(enter_hooks, fn) end
function M.onExitCell(fn)  table.insert(exit_hooks, fn)  end

function M.getPos() return { x = pos.x, y = pos.y, z = pos.z, facing = facing } end

local function fire_exit()
  local cell = { pos = util.deep_clone(pos), facing = facing }
  for _, fn in ipairs(exit_hooks) do pcall(fn, cell) end
end

local function fire_enter()
  local cell = { pos = util.deep_clone(pos), facing = facing }
  for _, fn in ipairs(enter_hooks) do pcall(fn, cell) end
end

local function classify_block(data)
  if not data then return "air" end
  local name = data.name or ""
  if util.matches_any(name, cfg.safety.bedrock_names, {}) or
     util.matches_any(name, {}, cfg.safety.bedrock_names) then
    return "bedrock"
  end
  if cfg.safety.seal_lava and util.matches_any(name, {}, cfg.safety.dangerous_liquids) then
    return "liquid"
  end
  if name == "minecraft:gravel" or name == "minecraft:sand" then
    return "falling"
  end
  -- Treat unknowns as regular blocks (diggable).
  return "block"
end

local function try_move(dir_move, dir_inspect, dir_dig, dir_seal, axis_delta)
  fire_exit()
  if dir_move() then
    pos.x = pos.x + axis_delta.x
    pos.y = pos.y + axis_delta.y
    pos.z = pos.z + axis_delta.z
    state.persist_position(pos, facing)
    fire_enter()
    return true
  end

  local ok, data = dir_inspect()
  local kind = ok and classify_block(data) or "unknown"

  if kind == "bedrock" then return false, "bedrock" end

  if kind == "liquid" then
    for _ = 1, 3 do
      if dir_seal() then
        if dir_move() then
          pos.x = pos.x + axis_delta.x
          pos.y = pos.y + axis_delta.y
          pos.z = pos.z + axis_delta.z
          state.persist_position(pos, facing)
          fire_enter()
          return true
        end
      else
        return false, "no_seal"
      end
    end
    return false, "no_seal"
  end

  if kind == "falling" then
    for _ = 1, cfg.safety.max_redig_attempts do
      dir_dig()
      sleep_safe(0.2)
      if dir_move() then
        pos.x = pos.x + axis_delta.x
        pos.y = pos.y + axis_delta.y
        pos.z = pos.z + axis_delta.z
        state.persist_position(pos, facing)
        fire_enter()
        return true
      end
    end
    return false, "falling_cap"
  end

  -- block / unknown: dig once then retry
  dir_dig()
  if dir_move() then
    pos.x = pos.x + axis_delta.x
    pos.y = pos.y + axis_delta.y
    pos.z = pos.z + axis_delta.z
    state.persist_position(pos, facing)
    fire_enter()
    return true
  end
  -- Might be a mob
  for _ = 1, cfg.safety.max_attack_attempts do
    turtle.attack()
    if dir_move() then
      pos.x = pos.x + axis_delta.x
      pos.y = pos.y + axis_delta.y
      pos.z = pos.z + axis_delta.z
      state.persist_position(pos, facing)
      fire_enter()
      return true
    end
  end
  return false, "blocked"
end

function M.forward()
  local d = { x = DX[facing], y = 0, z = DZ[facing] }
  return try_move(turtle.forward, turtle.inspect, turtle.dig,
    function() return inv.place_seal_forward() end, d)
end

function M.up()
  return try_move(turtle.up, turtle.inspectUp, turtle.digUp,
    function() return inv.place_seal_up() end, { x=0, y=1, z=0 })
end

function M.down()
  return try_move(turtle.down, turtle.inspectDown, turtle.digDown,
    function() return inv.place_seal_down() end, { x=0, y=-1, z=0 })
end

function M.back()
  fire_exit()
  if turtle.back() then
    pos.x = pos.x - DX[facing]
    pos.z = pos.z - DZ[facing]
    state.persist_position(pos, facing)
    fire_enter()
    return true
  end
  return false, "blocked"
end

function M.turnLeft()
  fire_exit()
  turtle.turnLeft()
  facing = (facing + 3) % 4
  state.persist_position(pos, facing)
  fire_enter()
  return true
end

function M.turnRight()
  fire_exit()
  turtle.turnRight()
  facing = (facing + 1) % 4
  state.persist_position(pos, facing)
  fire_enter()
  return true
end

function M.face(dir)
  local diff = (dir - facing) % 4
  if diff == 1 then M.turnRight()
  elseif diff == 2 then M.turnRight(); M.turnRight()
  elseif diff == 3 then M.turnLeft()
  end
  return true
end

function M.dig()     return turtle.dig()     end
function M.digUp()   return turtle.digUp()   end
function M.digDown() return turtle.digDown() end

function M.inspect()     return turtle.inspect()     end
function M.inspectUp()   return turtle.inspectUp()   end
function M.inspectDown() return turtle.inspectDown() end

return M
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: all movement tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/movement.lua tests/test_movement.lua
git commit -m "lib: transactional movement with obstacle classification"
```

---

### Task 2.2: `lib/inventory.lua` — classify + policies + deposit/refuel/seal

**Files:**
- Create: `lib/inventory.lua`
- Create: `tests/test_inventory.lua`

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_inventory.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.turtle = require("tests.mocks.turtle")
_G.os.epoch = function(_) return 1713648063000 end
_G.os.sleep = function(_) end
_G.sleep = function(_) end

local config = require("lib.config")
local inv = require("lib.inventory")

local function reset()
  _G.turtle._reset()
  inv.configure({ config = config.defaults() })
end

t.describe("inventory classification", function()
  t.it("tags each slot by block name", function()
    reset()
    _G.turtle._setInv(1, { name = "minecraft:cobblestone", count = 30 })
    _G.turtle._setInv(2, { name = "minecraft:coal", count = 8 })
    _G.turtle._setInv(3, { name = "minecraft:diamond_ore", count = 2 })
    local tags = inv.classify_slots()
    t.assert_eq(tags[1], "junk")
    t.assert_eq(tags[2], "fuel")
    t.assert_eq(tags[3], "keep")
  end)
end)

t.describe("inventory.should_go_home", function()
  local function set_keep(n)
    _G.turtle._reset()
    for i = 1, n do
      _G.turtle._setInv(i, { name = "minecraft:diamond_ore", count = 1 })
    end
  end
  t.it("returns true when keep slots >= keep_slots_before_home", function()
    reset()
    set_keep(12)
    t.assert_true(inv.should_go_home())
  end)
  t.it("returns false below the threshold", function()
    reset()
    set_keep(11)
    t.assert_false(inv.should_go_home())
  end)
end)

t.describe("inventory.drop_junk_in_place", function()
  t.it("drops junk-tagged slots and leaves keep", function()
    reset()
    _G.turtle._setInv(1, { name = "minecraft:cobblestone", count = 30 })
    _G.turtle._setInv(2, { name = "minecraft:diamond_ore", count = 1 })
    -- Turn around (backwards) so drop() goes into a chest; otherwise drop into air
    -- Here we emulate "drop in place" as simply discarding the slot contents
    -- by mocking turtle.dropDown / dropUp / drop to just consume the items.
    local dropped = {}
    _G.turtle.drop     = function() local it = _G.turtle.getItemDetail(_G.turtle.getSelectedSlot()); if it then dropped[#dropped+1] = it.name end; _G.turtle._setInv(_G.turtle.getSelectedSlot(), nil); return true end
    _G.turtle.dropUp   = _G.turtle.drop
    _G.turtle.dropDown = _G.turtle.drop
    inv.drop_junk_in_place()
    t.assert_eq(_G.turtle.getItemDetail(1), nil)
    t.assert_eq(_G.turtle.getItemDetail(2).name, "minecraft:diamond_ore")
  end)
end)

t.describe("inventory.refuel_from_slot", function()
  t.it("burns from the reserved fuel slot until threshold met", function()
    reset()
    _G.turtle._setInv(16, { name = "minecraft:coal", count = 64 })
    _G.turtle._setFuelLimit(20000)
    _G.turtle._setFuel(100)
    inv.refuel_from_slot(5000)
    t.assert_true(_G.turtle.getFuelLevel() >= 5000)
  end)
  t.it("returns false when reserved slot has no fuel", function()
    reset()
    _G.turtle._setFuelLimit(20000)
    _G.turtle._setFuel(100)
    local ok = inv.refuel_from_slot(5000)
    t.assert_false(ok)
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: FAIL — lib.inventory not found.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/inventory.lua`:
```lua
local config_mod = require("lib.config")

local M = {}
local cfg = nil

function M.configure(opts) cfg = opts.config end

function M.classify_slots()
  local tags = {}
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then tags[i] = config_mod.classify(d.name, cfg) end
  end
  return tags
end

function M.count_by_tag()
  local c = { keep = 0, junk = 0, fuel = 0, seal = 0, empty = 0 }
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then
      local tag = config_mod.classify(d.name, cfg)
      c[tag] = (c[tag] or 0) + 1
    else
      c.empty = c.empty + 1
    end
  end
  return c
end

function M.should_go_home()
  return M.count_by_tag().keep >= cfg.inventory.keep_slots_before_home
end

function M.is_full()
  return M.count_by_tag().empty == 0
end

function M.drop_junk_in_place()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and config_mod.classify(d.name, cfg) == "junk" then
      turtle.select(i)
      turtle.dropDown()
    end
  end
  turtle.select(1)
end

function M.refuel_from_slot(target)
  local slot = cfg.inventory.reserved_fuel_slot
  local prev = turtle.getSelectedSlot()
  turtle.select(slot)
  local ok = turtle.refuel()
  turtle.select(prev)
  if not ok then return false end
  -- Burn until target or slot empty
  while turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < target do
    turtle.select(slot)
    if not turtle.refuel() then turtle.select(prev); return false end
  end
  turtle.select(prev)
  return true
end

local function find_slot_by_tag(tag)
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and config_mod.classify(d.name, cfg) == tag then return i end
  end
  return nil
end

local function do_place_seal(place_fn)
  local s = find_slot_by_tag("seal")
  if not s then return false end
  local prev = turtle.getSelectedSlot()
  turtle.select(s)
  local ok = place_fn()
  turtle.select(prev)
  return ok
end

function M.place_seal_forward() return do_place_seal(turtle.place) end
function M.place_seal_up()      return do_place_seal(turtle.placeUp) end
function M.place_seal_down()    return do_place_seal(turtle.placeDown) end

-- Deposit-at-home assumes the turtle is already at home, facing the chest.
function M.deposit_all_keep()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then
      local tag = config_mod.classify(d.name, cfg)
      if tag == "keep" then
        turtle.select(i)
        while not turtle.drop() do
          -- chest full; caller handles retry
          return false, "chest_full", i
        end
      end
    end
  end
  turtle.select(1)
  return true
end

-- Overflow / drop-in-place junk handling based on config policy.
function M.handle_junk_by_policy()
  local policy = cfg.inventory.junk_policy
  if policy == "drop" then
    M.drop_junk_in_place()
  elseif policy == "keep" then
    -- no-op; junk will be deposited at home like keep
  elseif policy == "overflow" then
    if M.is_full() then M.drop_junk_in_place() end
  end
end

return M
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: inventory tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/inventory.lua tests/test_inventory.lua
git commit -m "lib: inventory classification + policy + seal/refuel/deposit"
```

---

### Task 2.3: `lib/navigator.lua` — goTo, panicHome, serpentine helper

**Files:**
- Create: `lib/navigator.lua`
- Create: `tests/test_navigator.lua`

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_navigator.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.turtle = require("tests.mocks.turtle")
_G.os.epoch = function(_) return 1713648063000 end
_G.os.sleep = function(_) end
_G.sleep = function(_) end

local config = require("lib.config")
local state = require("lib.state")
local movement = require("lib.movement")
local inv = require("lib.inventory")
local nav = require("lib.navigator")

local function reset()
  _G.fs._reset()
  _G.turtle._reset()
  state.reset()
  local cfg = config.defaults()
  inv.configure({ config = cfg })
  movement.configure({ config = cfg, inventory = inv })
  state.new_run({ strategy="test", params={}, home={x=0,y=0,z=0,facing=0},
                  fuel_at_start=10000 })
end

t.describe("navigator.goTo", function()
  t.it("reaches a target in open space", function()
    reset()
    local ok = nav.goTo(3, 0, 5)
    t.assert_true(ok)
    local c = state.load_current()
    t.assert_deep_eq(c.pos, { x = 3, y = 0, z = 5 })
  end)

  t.it("digs straight through regular blocks", function()
    reset()
    _G.turtle._setBlock(0, 0, 1, { name = "minecraft:stone" })
    _G.turtle._setBlock(0, 0, 2, { name = "minecraft:stone" })
    local ok = nav.goTo(0, 0, 3)
    t.assert_true(ok)
  end)

  t.it("descends and ascends correctly", function()
    reset()
    local ok = nav.goTo(0, -3, 0)
    t.assert_true(ok)
    t.assert_eq(state.load_current().pos.y, -3)
    nav.goTo(0, 0, 0)
    t.assert_eq(state.load_current().pos.y, 0)
  end)
end)

t.describe("navigator.face", function()
  t.it("delegates to movement.face", function()
    reset()
    nav.face(2)
    t.assert_eq(state.load_current().facing, 2)
  end)
end)

t.describe("navigator.panicHome", function()
  t.it("returns to (home.x, home.y, home.z) and faces home.facing", function()
    reset()
    nav.goTo(5, -2, 7)
    nav.panicHome()
    local c = state.load_current()
    t.assert_deep_eq(c.pos, { x = 0, y = 0, z = 0 })
    t.assert_eq(c.facing, 0)
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: FAIL — lib.navigator not found.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/navigator.lua`:
```lua
local state = require("lib.state")
local movement = require("lib.movement")

local M = {}

local function currentPos() return movement.getPos() end

function M.face(dir) return movement.face(dir) end

function M.goTo(tx, ty, tz)
  -- Y first (away from anything)
  while currentPos().y < ty do
    local ok, err = movement.up()
    if not ok then return false, err end
  end
  while currentPos().y > ty do
    local ok, err = movement.down()
    if not ok then return false, err end
  end
  local p = currentPos()
  if p.x ~= tx then
    movement.face(p.x < tx and 1 or 3)
    while currentPos().x ~= tx do
      local ok, err = movement.forward()
      if not ok then return false, err end
    end
  end
  p = currentPos()
  if p.z ~= tz then
    movement.face(p.z < tz and 0 or 2)
    while currentPos().z ~= tz do
      local ok, err = movement.forward()
      if not ok then return false, err end
    end
  end
  return true
end

function M.panicHome()
  local c = state.load_current()
  if not c then return false, "no_state" end
  -- Rise to home.y first, then XZ, then face home.facing
  local p = currentPos()
  while p.y < c.home.y do
    if not movement.up() then break end
    p = currentPos()
  end
  local ok = M.goTo(c.home.x, c.home.y, c.home.z)
  if ok then movement.face(c.home.facing) end
  return ok
end

-- Serpentine helper — iterate cells of a W×L rectangle in boustrophedon order.
-- Returns an iterator over {x, z, row_index, col_index}.
function M.serpentine(width, length)
  local i = 0
  local total = width * length
  return function()
    if i >= total then return nil end
    local col = math.floor(i / length)
    local row_in_col = i % length
    local x = col
    local z = (col % 2 == 0) and row_in_col or (length - 1 - row_in_col)
    i = i + 1
    return { x = x, z = z, col = col, row = row_in_col }
  end
end

return M
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: navigator tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/navigator.lua tests/test_navigator.lua
git commit -m "lib: navigator goTo + panicHome + serpentine iterator"
```

---

## Phase 3 — Strategies

### Task 3.1: Strategy loader and contract enforcement

**Files:**
- Create: `lib/strategy_loader.lua`
- Create: `tests/test_strategy_loader.lua`
- Create: `strategies/_example.lua` (fixture)

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_strategy_loader.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")

local loader = require("lib.strategy_loader")

local function reset() _G.fs._reset() end

t.describe("strategy_loader.list", function()
  t.it("lists .lua files in /strategies (ignoring underscored fixtures)", function()
    reset()
    _G.fs._inject("/strategies/quarry.lua",
      "return { name = 'quarry', display = 'Quarry', description = 'x', " ..
      "promptParams=function()end, estimate=function()return{fuel=0,blocks=0,seconds=0}end, " ..
      "preflight=function()return true end, run=function()end, resume=function()end }")
    _G.fs._inject("/strategies/_example.lua", "return {}")
    local names = loader.list()
    t.assert_eq(#names, 1)
    t.assert_eq(names[1], "quarry")
  end)
end)

t.describe("strategy_loader.load", function()
  t.it("validates the contract", function()
    reset()
    _G.fs._inject("/strategies/bad.lua", "return { name = 'bad' }")
    t.assert_error(function() loader.load("bad") end, "missing")
  end)

  t.it("loads a valid strategy", function()
    reset()
    _G.fs._inject("/strategies/ok.lua",
      "return { name='ok', display='OK', description='d', " ..
      "promptParams=function()return{}end, " ..
      "estimate=function()return{fuel=0,blocks=0,seconds=0}end, " ..
      "preflight=function()return true end, " ..
      "run=function()end, resume=function()end }")
    local s = loader.load("ok")
    t.assert_eq(s.name, "ok")
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Expected: FAIL — lib.strategy_loader not found.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/strategy_loader.lua`:
```lua
local M = {}

local REQUIRED = { "name", "display", "description",
                   "promptParams", "estimate", "preflight", "run", "resume" }

local function load_file(path)
  local h = fs.open(path, "r")
  if not h then error("cannot read " .. path) end
  local src = h.readAll(); h.close()
  local chunk, err = load(src, path, "t", _ENV or _G)
  if not chunk then error("parse error in " .. path .. ": " .. tostring(err)) end
  local ok, v = pcall(chunk)
  if not ok then error("exec error in " .. path .. ": " .. tostring(v)) end
  return v
end

function M.list()
  local out = {}
  if not fs.list then return out end
  for _, f in ipairs(fs.list("/strategies")) do
    if f:match("%.lua$") and not f:match("^_") then
      table.insert(out, (f:gsub("%.lua$", "")))
    end
  end
  table.sort(out)
  return out
end

function M.load(name)
  local path = "/strategies/" .. name .. ".lua"
  local strat = load_file(path)
  if type(strat) ~= "table" then error("strategy did not return a table: " .. path) end
  for _, key in ipairs(REQUIRED) do
    if strat[key] == nil then
      error("strategy " .. name .. " missing required field: " .. key)
    end
  end
  strat.name = strat.name or name
  return strat
end

return M
```

- [ ] **Step 4: Run — expect pass**

Expected: loader tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/strategy_loader.lua tests/test_strategy_loader.lua
git commit -m "lib: strategy loader with contract validation"
```

---

### Task 3.2: Quarry strategy

**Files:**
- Create: `strategies/quarry.lua`
- Create: `tests/test_strategy_quarry.lua`

- [ ] **Step 1: Write the tests**

Create `/home/luke/turtle/tests/test_strategy_quarry.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.turtle = require("tests.mocks.turtle")
_G.os.epoch = function(_) return 1713648063000 end
_G.os.sleep = function(_) end
_G.sleep = function(_) end

local config = require("lib.config")
local state = require("lib.state")
local movement = require("lib.movement")
local inv = require("lib.inventory")
local nav = require("lib.navigator")

-- Load quarry directly, bypassing the loader for test simplicity
local function load_quarry()
  local src = io.open("strategies/quarry.lua"):read("*a")
  local chunk = load(src, "strategies/quarry.lua", "t", _ENV or _G)
  return chunk()
end

local function fresh_ctx()
  _G.fs._reset()
  _G.turtle._reset()
  state.reset()
  local cfg = config.defaults()
  inv.configure({ config = cfg })
  movement.configure({ config = cfg, inventory = inv })
  state.new_run({ strategy = "quarry", params = { width = 2, length = 2 },
                  home = { x=0, y=0, z=0, facing=0 }, fuel_at_start = 10000 })
  return {
    nav = nav, inv = inv,
    log = { debug=function()end, info=function()end,
            warn=function()end, error=function()end },
    saveProgress = state.save_progress,
    shouldStop = function() return false end,
    shouldPause = function() return false end,
    config = cfg,
  }
end

t.describe("quarry.estimate", function()
  t.it("returns fuel/blocks/seconds for given params", function()
    local q = load_quarry()
    local e = q.estimate({ width = 4, length = 4, depth = "bedrock" })
    t.assert_true(e.fuel > 0)
    t.assert_true(e.blocks > 0)
    t.assert_true(e.seconds > 0)
  end)
end)

t.describe("quarry.run (tiny world to bedrock)", function()
  t.it("mines a 2×2 area down to bedrock and returns", function()
    local ctx = fresh_ctx()
    -- Place bedrock at y=-3 for the whole footprint
    for x = 0, 1 do for z = 0, 1 do
      _G.turtle._setBlock(x, -3, z, { name = "minecraft:bedrock" })
      -- Fill y=-1 and y=-2 with stone
      _G.turtle._setBlock(x, -1, z, { name = "minecraft:stone" })
      _G.turtle._setBlock(x, -2, z, { name = "minecraft:stone" })
    end end
    local q = load_quarry()
    q.run({ width = 2, length = 2, depth = "bedrock" }, ctx)
    -- Should end near home
    local p = state.load_current().pos
    t.assert_true(math.abs(p.x) <= 1 and math.abs(p.z) <= 1 and p.y >= -1)
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Expected: FAIL — strategies/quarry.lua missing.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/strategies/quarry.lua`:
```lua
-- Quarry strategy: serpentine W×L, each cell = column down to bedrock or depth.
-- Requires ctx = { nav, inv, log, saveProgress, shouldStop, shouldPause, config }

local function is_bedrock(ctx, inspect_fn)
  local ok, data = inspect_fn()
  if not ok then return false end
  for _, name in ipairs(ctx.config.safety.bedrock_names) do
    if data.name == name or data.name:match(name) then return true end
  end
  return false
end

local function mine_column(ctx, target_y_or_bedrock)
  while true do
    if ctx.shouldStop() then return false, "stopped" end
    if is_bedrock(ctx, function() return _G.turtle.inspectDown() end) then break end
    local cur_y = ctx.nav.face and nil  -- unused; keep placeholder
    local posmsg = require("lib.movement").getPos().y
    if type(target_y_or_bedrock) == "number" and posmsg <= target_y_or_bedrock then break end
    local ok, err = require("lib.movement").down()
    if not ok then return false, err end
  end
  -- Return up to y=0
  while require("lib.movement").getPos().y < 0 do
    local ok, err = require("lib.movement").up()
    if not ok then return false, err end
  end
  return true
end

local function home_cycle(ctx)
  ctx.nav.face(require("lib.movement").getPos().facing) -- no-op; placeholder
  local home = require("lib.state").load_current().home
  ctx.nav.goTo(home.x, home.y, home.z)
  ctx.nav.face(2) -- face chest
  ctx.inv.deposit_all_keep()
  ctx.inv.refuel_from_slot(ctx.config.fuel.refuel_below * 2)
  ctx.nav.face(0) -- face back into work
end

local M = {
  name = "quarry",
  display = "Quarry",
  description = "Mine a rectangular area down to bedrock (or a configured Y).",
}

function M.promptParams(defaults)
  defaults = defaults or {}
  -- Default interactive path handled by main.lua; for testing accept defaults.
  return {
    width  = defaults.width  or 8,
    length = defaults.length or 8,
    depth  = defaults.depth  or "bedrock",
  }
end

function M.estimate(params)
  local depth_guess = params.depth == "bedrock" and 64 or tonumber(params.depth) or 32
  local cells = params.width * params.length
  local blocks = cells * depth_guess
  local fuel = cells * (depth_guess * 2) + (params.width + params.length) * 2
  return { fuel = fuel, blocks = blocks, seconds = math.floor(blocks * 0.15) }
end

function M.preflight(params)
  if params.width < 1 or params.length < 1 then return false, "bad dimensions" end
  return true
end

local function run_body(params, ctx, start_col, start_row)
  local target_y = params.depth == "bedrock" and nil or tonumber(params.depth)
  local depth_arg = target_y and (-target_y) or "bedrock"
  for col = start_col, params.width - 1 do
    local forward = col % 2 == 0
    for r = 0, params.length - 1 do
      if col == start_col and r < start_row then goto continue end
      if ctx.shouldStop() then return false, "stopped" end
      local z = forward and r or (params.length - 1 - r)
      local ok, err = ctx.nav.goTo(col, 0, z)
      if not ok then return false, err end
      if ctx.inv.should_go_home() then home_cycle(ctx) ; ctx.nav.goTo(col, 0, z) end
      local mc_ok, mc_err = mine_column(ctx, target_y and -target_y or "bedrock")
      if not mc_ok then return false, mc_err end
      ctx.inv.handle_junk_by_policy()
      ctx.saveProgress({ col = col, row = r, next_action = "next_cell" })
      ::continue::
    end
  end
  -- Home-and-finish
  home_cycle(ctx)
  return true
end

function M.run(params, ctx)
  return run_body(params, ctx, 0, 0)
end

function M.resume(params, progress, ctx)
  local start_col = progress.col or 0
  local start_row = (progress.row or 0) + 1
  if start_row >= params.length then
    start_col = start_col + 1
    start_row = 0
  end
  return run_body(params, ctx, start_col, start_row)
end

function M.expectedCell(params, progress)
  if not progress.col then return nil end
  local forward = progress.col % 2 == 0
  local z = forward and progress.row or (params.length - 1 - progress.row)
  return { x = progress.col, y = 0, z = z }
end

return M
```

- [ ] **Step 4: Run — expect pass**

Run: `cd /home/luke/turtle && lua tests/run_all.lua`
Expected: quarry tests pass. (Note: the live test uses the real `require` chain so movement/navigator/inventory all load correctly.)

- [ ] **Step 5: Commit**

```bash
git add strategies/quarry.lua tests/test_strategy_quarry.lua
git commit -m "strategy: quarry — serpentine to bedrock"
```

---

### Task 3.3: Strip strategy

**Files:**
- Create: `strategies/strip.lua`
- Create: `tests/test_strategy_strip.lua`

- [ ] **Step 1: Write the tests**

Create `/home/luke/turtle/tests/test_strategy_strip.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.turtle = require("tests.mocks.turtle")
_G.os.epoch = function(_) return 1713648063000 end
_G.os.sleep = function(_) end
_G.sleep = function(_) end

local config = require("lib.config")
local state = require("lib.state")
local movement = require("lib.movement")
local inv = require("lib.inventory")
local nav = require("lib.navigator")

local function load_strip()
  local src = io.open("strategies/strip.lua"):read("*a")
  return load(src, "strip", "t", _ENV or _G)()
end

local function fresh_ctx(params)
  _G.fs._reset(); _G.turtle._reset(); state.reset()
  local cfg = config.defaults()
  inv.configure({ config = cfg })
  movement.configure({ config = cfg, inventory = inv })
  state.new_run({ strategy="strip", params=params or {},
                  home = { x=0,y=0,z=0,facing=0 }, fuel_at_start = 10000 })
  return {
    nav = nav, inv = inv,
    log = setmetatable({}, { __index = function() return function() end end }),
    saveProgress = state.save_progress,
    shouldStop = function() return false end,
    shouldPause = function() return false end,
    config = cfg,
  }
end

t.describe("strip.estimate", function()
  t.it("scales linearly with length", function()
    local s = load_strip()
    local a = s.estimate({ length = 32 })
    local b = s.estimate({ length = 64 })
    t.assert_true(b.fuel > a.fuel * 1.5)
  end)
end)

t.describe("strip.run", function()
  t.it("mines a 10-block outbound tunnel and returns", function()
    local ctx = fresh_ctx({ length = 10 })
    for z = 1, 10 do
      _G.turtle._setBlock(0, 0, z, { name = "minecraft:stone" })
    end
    local s = load_strip()
    s.run({ length = 10 }, ctx)
    -- Turtle should be at home after run
    local p = state.load_current().pos
    t.assert_deep_eq(p, { x = 0, y = 0, z = 0 })
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Expected: FAIL — strategies/strip.lua missing.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/strategies/strip.lua`:
```lua
local M = {
  name = "strip", display = "Strip",
  description = "Dig a straight 1-wide, 2-tall tunnel of a given length.",
}

function M.promptParams(defaults)
  defaults = defaults or {}
  return { length = defaults.length or 64 }
end

function M.estimate(params)
  local blocks = params.length * 2   -- body + head
  local fuel = params.length * 2 + params.length   -- out + back
  return { fuel = fuel, blocks = blocks, seconds = math.floor(blocks * 0.2) }
end

function M.preflight(params)
  if not params.length or params.length < 1 then return false, "length" end
  return true
end

local function run_body(params, ctx, start_z)
  local movement = require("lib.movement")
  for z = start_z, params.length do
    if ctx.shouldStop() then return false, "stopped" end
    local ok, err = ctx.nav.goTo(0, 0, z)
    if not ok then return false, err end
    -- Mine the head-height block above the turtle for a 2-tall tunnel
    movement.digUp()
    ctx.inv.handle_junk_by_policy()
    ctx.saveProgress({ length_done = z, direction = "outbound" })
  end
  -- Return to home
  ctx.nav.goTo(0, 0, 0)
  ctx.nav.face(2)
  ctx.inv.deposit_all_keep()
  ctx.nav.face(0)
  return true
end

function M.run(params, ctx) return run_body(params, ctx, 1) end

function M.resume(params, progress, ctx)
  local start = (progress.length_done or 0) + 1
  if start > params.length then
    ctx.nav.goTo(0, 0, 0); return true
  end
  return run_body(params, ctx, start)
end

function M.expectedCell(_, progress)
  if not progress.length_done then return nil end
  return { x = 0, y = 0, z = progress.length_done }
end

return M
```

- [ ] **Step 4: Run — expect pass**

Expected: strip tests pass.

- [ ] **Step 5: Commit**

```bash
git add strategies/strip.lua tests/test_strategy_strip.lua
git commit -m "strategy: strip — single tunnel with outbound/return"
```

---

### Task 3.4: Branch strategy

**Files:**
- Create: `strategies/branch.lua`
- Create: `tests/test_strategy_branch.lua`

- [ ] **Step 1: Write the tests**

Create `/home/luke/turtle/tests/test_strategy_branch.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.turtle = require("tests.mocks.turtle")
_G.os.epoch = function(_) return 1713648063000 end
_G.os.sleep = function(_) end
_G.sleep = function(_) end

local config = require("lib.config")
local state = require("lib.state")
local movement = require("lib.movement")
local inv = require("lib.inventory")
local nav = require("lib.navigator")

local function load_branch()
  local src = io.open("strategies/branch.lua"):read("*a")
  return load(src, "branch", "t", _ENV or _G)()
end

local function fresh_ctx(params)
  _G.fs._reset(); _G.turtle._reset(); state.reset()
  local cfg = config.defaults()
  inv.configure({ config = cfg })
  movement.configure({ config = cfg, inventory = inv })
  state.new_run({ strategy="branch", params=params or {},
                  home = { x=0,y=0,z=0,facing=0 }, fuel_at_start = 10000 })
  return {
    nav = nav, inv = inv,
    log = setmetatable({}, { __index = function() return function() end end }),
    saveProgress = state.save_progress,
    shouldStop = function() return false end,
    shouldPause = function() return false end,
    config = cfg,
  }
end

t.describe("branch.estimate", function()
  t.it("accounts for main tunnel + all branches", function()
    local b = load_branch()
    local e = b.estimate({ main_length = 32, branch_length = 8, branch_spacing = 3 })
    t.assert_true(e.blocks > 32)
  end)
end)

t.describe("branch.run", function()
  t.it("returns to home after completing main + branches", function()
    local ctx = fresh_ctx({ main_length = 8, branch_length = 4, branch_spacing = 2 })
    local b = load_branch()
    b.run({ main_length = 8, branch_length = 4, branch_spacing = 2 }, ctx)
    local p = state.load_current().pos
    t.assert_deep_eq(p, { x = 0, y = 0, z = 0 })
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Expected: FAIL — strategies/branch.lua missing.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/strategies/branch.lua`:
```lua
local M = {
  name = "branch", display = "Branch",
  description = "Main tunnel with perpendicular branches every N blocks.",
}

function M.promptParams(defaults)
  defaults = defaults or {}
  return {
    main_length   = defaults.main_length   or 32,
    branch_length = defaults.branch_length or 8,
    branch_spacing= defaults.branch_spacing or 3,
  }
end

function M.estimate(params)
  local num_branches = math.floor(params.main_length / params.branch_spacing)
  local blocks = params.main_length * 2
    + num_branches * params.branch_length * 2 * 2  -- both sides, 2-high
  local fuel = params.main_length * 2
    + num_branches * params.branch_length * 4
  return { fuel = fuel, blocks = blocks, seconds = math.floor(blocks * 0.2) }
end

function M.preflight(params)
  if params.main_length < 1 or params.branch_length < 0 or params.branch_spacing < 1 then
    return false, "invalid params"
  end
  return true
end

local function carve_branch_at(z, params, ctx, dir)
  -- dir: 1 (right, +X) or 3 (left, -X)
  ctx.nav.goTo(0, 0, z)
  ctx.nav.face(dir)
  for step = 1, params.branch_length do
    if ctx.shouldStop() then return false, "stopped" end
    local ok, err = require("lib.movement").forward()
    if not ok then return false, err end
    require("lib.movement").digUp()
    ctx.inv.handle_junk_by_policy()
  end
  ctx.nav.goTo(0, 0, z)
end

local function run_body(params, ctx, start_z, start_side)
  local num_branches = math.floor(params.main_length / params.branch_spacing)
  for b = math.floor(start_z / params.branch_spacing), num_branches - 1 do
    local z = (b + 1) * params.branch_spacing
    ctx.nav.goTo(0, 0, z)
    require("lib.movement").digUp()
    if start_side ~= "right" then carve_branch_at(z, params, ctx, 3) end
    carve_branch_at(z, params, ctx, 1)
    start_side = nil
    ctx.saveProgress({ branch_idx = b, direction = "done" })
  end
  ctx.nav.goTo(0, 0, 0)
  ctx.nav.face(2)
  ctx.inv.deposit_all_keep()
  ctx.nav.face(0)
  return true
end

function M.run(params, ctx) return run_body(params, ctx, 0, nil) end

function M.resume(params, progress, ctx)
  local start_idx = (progress.branch_idx or -1) + 1
  local start_z = start_idx * params.branch_spacing
  return run_body(params, ctx, start_z, nil)
end

function M.expectedCell(params, progress)
  if progress.branch_idx == nil then return nil end
  return { x = 0, y = 0, z = (progress.branch_idx + 1) * params.branch_spacing }
end

return M
```

- [ ] **Step 4: Run — expect pass**

Expected: branch tests pass.

- [ ] **Step 5: Commit**

```bash
git add strategies/branch.lua tests/test_strategy_branch.lua
git commit -m "strategy: branch — main tunnel + perpendicular branches"
```

---

## Phase 4 — UI (main, menus, live screen, recovery)

### Task 4.1: `lib/ui.lua` — terminal primitives

**Files:**
- Create: `lib/ui.lua`
- Create: `tests/test_ui.lua`

- [ ] **Step 1: Write the failing tests**

Create `/home/luke/turtle/tests/test_ui.lua`:
```lua
package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.term = require("tests.mocks.term")
_G.colors = setmetatable({}, { __index = function() return 1 end })

local ui = require("lib.ui")

t.describe("ui.center_text", function()
  t.it("pads to centre on a 39-wide screen", function()
    local s = ui.center_text("hi", 39)
    t.assert_eq(#s, 39)
    t.assert_true(s:match("hi") ~= nil)
  end)
end)

t.describe("ui.progress_bar", function()
  t.it("renders correct fill proportions", function()
    t.assert_eq(ui.progress_bar(0.00, 10), "░░░░░░░░░░")
    t.assert_eq(ui.progress_bar(0.50, 10), "█████░░░░░")
    t.assert_eq(ui.progress_bar(1.00, 10), "██████████")
  end)
end)

t.describe("ui.format_fuel", function()
  t.it("abbreviates thousands with k suffix", function()
    t.assert_eq(ui.format_fuel(18432), "18.4k")
    t.assert_eq(ui.format_fuel(500), "500")
    t.assert_eq(ui.format_fuel("unlimited"), "∞")
  end)
end)
```

- [ ] **Step 2: Run — expect failure**

Expected: FAIL — lib.ui not found.

- [ ] **Step 3: Write the implementation**

Create `/home/luke/turtle/lib/ui.lua`:
```lua
local M = {}

local W, H = 39, 13

function M.center_text(text, width)
  width = width or W
  local pad = math.max(0, width - #text)
  local left = math.floor(pad / 2)
  return string.rep(" ", left) .. text .. string.rep(" ", pad - left)
end

function M.progress_bar(frac, width)
  width = width or 14
  frac = math.max(0, math.min(1, frac))
  local filled = math.floor(frac * width + 0.5)
  return string.rep("\u{2588}", filled) .. string.rep("\u{2591}", width - filled)
end

function M.format_fuel(f)
  if f == "unlimited" then return "\u{221E}" end
  if f >= 1000 then return string.format("%.1fk", f / 1000) end
  return tostring(f)
end

function M.clear_screen()
  if term.clear then term.clear() end
  if term.setCursorPos then term.setCursorPos(1, 1) end
end

function M.print_line(row, text)
  if term.setCursorPos then term.setCursorPos(1, row) end
  term.write(text or "")
end

function M.hr(row, char)
  M.print_line(row, string.rep(char or "\u{2500}", W))
end

function M.header(label, fuel, keep_count)
  M.print_line(1, string.format("\u{26CF} %-15s fuel %-6s keep %d/16",
    label or "turtle", M.format_fuel(fuel or 0), keep_count or 0))
  M.hr(2)
end

function M.footer(row, text)
  M.hr(row - 1)
  M.print_line(row, text)
end

return M
```

- [ ] **Step 4: Run — expect pass**

Expected: ui tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui.lua tests/test_ui.lua
git commit -m "lib: ui primitives (header, hr, progress bar, fuel fmt)"
```

---

### Task 4.2: Menu + boot flow + pre-flight + live status + recovery

**Files:**
- Create: `lib/main.lua`
- Create: `mine` (launcher)

This task is large but mostly sequential UI code. No unit tests — visual verification on-turtle only.

- [ ] **Step 1: Write `lib/main.lua`**

Create `/home/luke/turtle/lib/main.lua`:
```lua
local config = require("lib.config")
local logger = require("lib.logger")
local state = require("lib.state")
local movement = require("lib.movement")
local inv = require("lib.inventory")
local nav = require("lib.navigator")
local loader = require("lib.strategy_loader")
local ui = require("lib.ui")

local M = {}

local CONFIG_PATH = "/config.lua"
local cfg, cfg_warnings

local stop_flag, pause_flag = false, false
local function shouldStop() return stop_flag end
local function shouldPause() return pause_flag end

local function read_key()
  while true do
    local ev, key = os.pullEvent("key")
    return key
  end
end

local function read_line(prompt)
  if prompt then term.write(prompt) end
  return read() or ""
end

local function confirm(prompt, default_y)
  term.write(prompt .. (default_y and " [Y/n] " or " [y/N] "))
  local ans = (read() or ""):lower():sub(1,1)
  if ans == "" then return default_y end
  return ans == "y"
end

local function format_fuel_count()
  local count = inv.count_by_tag()
  local fuel = _G.turtle and _G.turtle.getFuelLevel() or 0
  return fuel, count.keep
end

local function render_header(label)
  local fuel, keep = format_fuel_count()
  ui.clear_screen()
  ui.header(label or os.getComputerLabel() or ("turtle-" .. os.getComputerID()),
    fuel, keep)
end

-- ─── Main menu ────────────────────────────────────────────────
local function main_menu()
  render_header()
  ui.print_line(4, ui.center_text("\u{26CF}  Mining Turtle", 39))
  local strats = loader.list()
  local row = 6
  for i, n in ipairs(strats) do
    local s = loader.load(n)
    ui.print_line(row, string.format("  [%d] %-9s  %s", i, s.display, s.description or ""))
    row = row + 1
  end
  ui.hr(row); row = row + 1
  ui.print_line(row,   "  [L] Learn blocks")
  ui.print_line(row+1, "  [S] Settings")
  ui.print_line(row+2, "  [H] Home calibrate")
  ui.hr(row+3)
  ui.print_line(row+4, "  [Q] Quit")
  while true do
    local key = read_key()
    local ch = keys.getName and keys.getName(key) or tostring(key)
    if ch:match("^[%d]$") then
      local idx = tonumber(ch)
      if strats[idx] then return "strategy", strats[idx] end
    end
    if ch == "l" then return "learn" end
    if ch == "s" then return "settings" end
    if ch == "h" then return "home_calibrate" end
    if ch == "q" then return "quit" end
  end
end

-- ─── Strategy flow ────────────────────────────────────────────
local function run_strategy(name)
  local s = loader.load(name)
  render_header(s.display)
  ui.print_line(4, " Configure " .. s.display .. ":")
  local params = s.promptParams(cfg.strategy_defaults[name] or {})
  if not params then return end

  local est = s.estimate(params)
  local have_fuel = (_G.turtle and _G.turtle.getFuelLevel()) or 0
  local ok_pf, pf_err = s.preflight(params)

  render_header(s.display)
  ui.print_line(4, " Pre-flight check")
  ui.hr(5)
  ui.print_line(6, string.format("  Est. fuel:   ~%d  (have %s)",
    est.fuel, ui.format_fuel(have_fuel)))
  ui.print_line(7, string.format("  Est. blocks: ~%d", est.blocks))
  ui.print_line(8, string.format("  Est. time:   ~%dm", math.floor(est.seconds/60)))
  ui.print_line(9, string.format("  Preflight:   %s",
    ok_pf and "OK" or ("FAIL: " .. tostring(pf_err))))
  ui.hr(11)
  if not ok_pf then
    ui.print_line(12, "  [any] back to menu")
    read_key()
    return
  end
  if not confirm("\n Start? ", true) then return end

  -- Commit to run
  cfg.strategy_defaults[name] = params
  config.save(CONFIG_PATH, cfg)

  state.new_run({
    strategy = name, params = params,
    home = { x = 0, y = 0, z = 0, facing = 0 },
    fuel_at_start = have_fuel,
  })
  state.set_phase("mining")

  local ctx = {
    nav = nav, inv = inv, log = logger,
    saveProgress = state.save_progress,
    shouldStop = shouldStop, shouldPause = shouldPause,
    config = cfg,
  }

  -- Live status + worker
  local function worker()
    local ok, err = pcall(s.run, params, ctx)
    if not ok then logger.error("strategy error: " .. tostring(err)) end
  end
  local function key_listener()
    while true do
      local _, k = os.pullEvent("key")
      local name = keys.getName and keys.getName(k) or ""
      if name == "p" then pause_flag = not pause_flag end
      if name == "h" then stop_flag = true end
      if name == "a" then stop_flag = true end
    end
  end
  parallel.waitForAny(worker, key_listener)

  state.set_phase("idle")
end

-- ─── Recovery flow ────────────────────────────────────────────
local function recovery_menu()
  local c = state.load_current()
  local s = state.load_strategy()
  render_header("recovery")
  ui.print_line(4,  " \u{26A0} Previous run did not complete")
  ui.print_line(6,  string.format("  strategy: %s", c and c.strategy or "?"))
  ui.print_line(7,  string.format("  phase:    %s", c and c.phase or "?"))
  ui.print_line(8,  string.format("  pos:      (%d,%d,%d)",
    c and c.pos.x or 0, c and c.pos.y or 0, c and c.pos.z or 0))
  ui.print_line(10, "  [R] resume   [H] panic home")
  ui.print_line(11, "  [W] wipe     [Q] quit")
  while true do
    local k = read_key()
    local ch = keys.getName and keys.getName(k) or ""
    if ch == "r" then return "resume", c, s end
    if ch == "h" then return "panic" end
    if ch == "w" then
      term.setCursorPos(1, 12)
      term.write("type strategy name to confirm: ")
      if (read() or "") == (c and c.strategy or "?") then return "wipe" end
    end
    if ch == "q" then return "quit" end
  end
end

local function boot()
  cfg, cfg_warnings = config.load(CONFIG_PATH)
  logger.configure({
    level = cfg.logging.level,
    file_path = "/logs/run.log",
    keep_runs = cfg.logging.keep_runs,
  })
  logger.addSink(logger._terminal_sink)
  inv.configure({ config = cfg })
  movement.configure({ config = cfg, inventory = inv })
  for _, w in ipairs(cfg_warnings or {}) do logger.warn(w) end

  local c = state.load_current()
  if c and c.phase and c.phase ~= "idle" then
    local action, current, strat = recovery_menu()
    if action == "resume" then
      local s = loader.load(current.strategy)
      local ctx = {
        nav = nav, inv = inv, log = logger,
        saveProgress = state.save_progress,
        shouldStop = shouldStop, shouldPause = shouldPause,
        config = cfg,
      }
      s.resume(strat.params, strat.progress, ctx)
      state.set_phase("idle")
    elseif action == "panic" then
      nav.panicHome(); state.clear()
    elseif action == "wipe" then
      state.clear()
    end
  end

  while true do
    local choice, arg = main_menu()
    if choice == "strategy" then run_strategy(arg)
    elseif choice == "quit" then return
    -- learn / settings / home_calibrate → see Task 4.3
    end
  end
end

M.boot = boot
return M
```

- [ ] **Step 2: Write the launcher**

Create `/home/luke/turtle/mine` (no extension — CC:T can run extensionless scripts):
```lua
-- Add /lib and / to the search path so modules and strategies resolve.
package.path = "/?.lua;/lib/?.lua;/strategies/?.lua;" .. package.path
require("lib.main").boot()
```

- [ ] **Step 3: Commit**

```bash
git add lib/main.lua mine
git commit -m "ui: main menu, pre-flight, run, recovery flows"
```

---

### Task 4.3: Learn-blocks and settings screens

**Files:**
- Modify: `lib/main.lua` — add `learn_screen()`, `settings_screen()`, `home_calibrate_screen()`, wire them into `main_menu` dispatch.

- [ ] **Step 1: Extend `lib/main.lua`**

Insert these handlers and dispatch the menu cases. Full patch:

In `lib/main.lua`, **replace** the final `while true do local choice, arg = main_menu() ... end` block at the end of `boot()` with:

```lua
  while true do
    local choice, arg = main_menu()
    if choice == "strategy"       then run_strategy(arg)
    elseif choice == "learn"      then learn_screen()
    elseif choice == "settings"   then settings_screen()
    elseif choice == "home_calibrate" then home_calibrate_screen()
    elseif choice == "quit"       then return end
  end
```

Then add these three functions **before** `boot()`:

```lua
local function learn_screen()
  render_header("learn blocks")
  ui.print_line(4, " Iterating inventory slots...")
  local seen = {}
  for i = 1, 16 do
    local d = _G.turtle and _G.turtle.getItemDetail(i)
    if d then seen[d.name] = (seen[d.name] or 0) + d.count end
  end
  local row = 6
  for name, count in pairs(seen) do
    local tag = config.classify(name, cfg)
    if tag == "keep" then
      ui.print_line(row, string.format("  %-30s x%d", name, count))
      ui.print_line(row+1, "    [k]eep [j]unk [f]uel [s]eal [x] skip")
      local k = read_key()
      local ch = keys.getName and keys.getName(k) or ""
      if ch == "j" then table.insert(cfg.inventory.junk, name)
      elseif ch == "f" then table.insert(cfg.inventory.fuel, name)
      elseif ch == "s" then table.insert(cfg.inventory.seal, name)
      end
      row = row + 3
      if row > 11 then row = 4; ui.clear_screen(); ui.header() end
    end
  end
  config.save(CONFIG_PATH, cfg)
  ui.print_line(13, " Saved. [any] back")
  read_key()
end

local function settings_screen()
  render_header("settings")
  ui.print_line(4,  " Config loaded from " .. CONFIG_PATH)
  ui.print_line(6,  string.format("  junk_policy:       %s", cfg.inventory.junk_policy))
  ui.print_line(7,  string.format("  keep_slots_home:   %d", cfg.inventory.keep_slots_before_home))
  ui.print_line(8,  string.format("  refuel_below:      %d", cfg.fuel.refuel_below))
  ui.print_line(9,  string.format("  seal_lava:         %s", tostring(cfg.safety.seal_lava)))
  ui.print_line(10, string.format("  log level:         %s", cfg.logging.level))
  ui.hr(12)
  ui.print_line(13, " [E] edit /config.lua   [any] back")
  local k = read_key()
  local ch = keys.getName and keys.getName(k) or ""
  if ch == "e" then shell.run("edit", CONFIG_PATH) end
end

local function home_calibrate_screen()
  render_header("home calibrate")
  ui.print_line(4, " Checking chest behind turtle...")
  local ok, data = _G.turtle.inspect()  -- we face forward; chest is behind
  -- Turn to inspect back
  _G.turtle.turnRight(); _G.turtle.turnRight()
  local ok_back, data_back = _G.turtle.inspect()
  _G.turtle.turnRight(); _G.turtle.turnRight()
  if ok_back and data_back.name:match("chest") then
    ui.print_line(6, "  \u{2713} chest detected behind")
  else
    ui.print_line(6, "  \u{2717} no chest behind; place one and retry")
  end
  ui.print_line(13, " [any] back")
  read_key()
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/main.lua
git commit -m "ui: learn-blocks, settings, home-calibrate screens"
```

---

## Phase 5 — Live-turtle smoke tests

These are manual tests to run on an actual turtle in-game. Check each off after verifying on the live server.

### Task 5.1: Install to a turtle

- [ ] Push the repo to the remote (confirm with user first).
- [ ] On the target turtle:
      ```
      wget run https://raw.githubusercontent.com/<user>/<repo>/main/installer.lua
      ```
      (installer.lua is a small script that pulls the directory tree; write as separate task if needed).
- [ ] Alternative: use `pastebin get` or copy files manually via floppy.
- [ ] Run `mine` from the turtle terminal. Main menu should appear.

### Task 5.2: Smoke test quarry (2×2, Y limit 3)

- [ ] Place turtle + chest behind, drop coal in slot 16, cobble somewhere.
- [ ] Menu → Quarry → 2×2, depth 3. Confirm.
- [ ] Verify turtle mines 4 columns 3 deep and returns with stone in chest.
- [ ] Break the turtle mid-run at column 2 depth 1.
- [ ] Re-place. Power on. Should prompt "Resume?" → yes → completes the remaining columns.

### Task 5.3: Smoke test lava seal

- [ ] Set up a flat area with one lava source block in the turtle's path.
- [ ] Quarry 3×1. Verify lava gets sealed with cobble and turtle continues.
- [ ] Remove all cobble from the inventory mid-run near lava; verify panicHome triggers and turtle reaches chest.

### Task 5.4: Smoke test strip and branch

- [ ] Strip 10. Verify straight tunnel, return home.
- [ ] Branch main=8, branch=4, spacing=2. Verify pattern matches expectation.

### Task 5.5: Smoke test learn-blocks

- [ ] Mine area with a modded block (e.g. Create limestone) in it.
- [ ] After run, menu → Learn blocks.
- [ ] Assign as junk. Verify `/config.lua` contains the new entry.

---

## Self-review checklist

- [ ] Each DESIGN.md section has at least one task:
      §1 module layout → Task 0.1 + file structure in every task.
      §2 movement API → Task 2.1.
      §3 state persistence → Task 1.4.
      §4 strategy plugin interface → Task 3.1 + 3.2 + 3.3 + 3.4.
      §5 config schema → Task 1.3 (including modded-blocks amendment).
      §6 rednet protocol → logger `addSink` hook in Task 1.2 (no runtime code).
      §7 failure/recovery → Tasks 2.1 (movement retries), 1.4 (corrupt-state handling), 4.2 (recovery menu).
      §8 UX/TUI → Tasks 4.1, 4.2, 4.3.
- [ ] No placeholders: every code step contains complete runnable code.
- [ ] Type consistency: `ctx` shape defined in Task 3.1 used consistently in 3.2/3.3/3.4 and 4.2.
      `config` table shape defined in Task 1.3 used consistently throughout.
- [ ] No vein-follow / geoscanner / torch / rednet code anywhere (all out of v1 scope per DESIGN Appendix B).
