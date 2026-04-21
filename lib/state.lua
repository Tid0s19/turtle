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
    chunk = load("return " .. src, path, "t", {})
  end
  if not chunk then return nil end
  local ok, v = pcall(chunk)
  if not ok then return nil end
  if type(v) ~= "table" then return nil end
  return v
end

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
