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
  term.setCursorPos(1, 12)
  if not confirm(" Start?", true) then return end

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
    if choice == "strategy"       then run_strategy(arg)
    elseif choice == "learn"      then learn_screen()
    elseif choice == "settings"   then settings_screen()
    elseif choice == "home_calibrate" then home_calibrate_screen()
    elseif choice == "quit"       then return end
  end
end

M.boot = boot
return M
