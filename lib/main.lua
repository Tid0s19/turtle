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

local NUMBER_KEY_NAMES = {
  one = 1, two = 2, three = 3, four = 4, five = 5,
  six = 6, seven = 7, eight = 8, nine = 9, zero = 0,
}

local function read_key()
  while true do
    local ev, key = os.pullEvent("key")
    return key
  end
end

local function read_key_name()
  local k = read_key()
  return keys.getName and keys.getName(k) or tostring(k)
end

local function key_to_digit(ch)
  if ch and ch:match("^%d$") then return tonumber(ch) end
  return NUMBER_KEY_NAMES[ch or ""]
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
  ui.print_line(4, ui.center_text("Mining Turtle", 39))
  local strats = loader.list()
  local row = 6
  for i, n in ipairs(strats) do
    local s = loader.load(n)
    local desc = s.description or ""
    if #desc > 22 then desc = desc:sub(1, 21) .. "~" end
    ui.print_line(row, string.format("  [%d] %-7s %s", i, s.display, desc))
    row = row + 1
  end
  ui.hr(row); row = row + 1
  ui.print_line(row,   "  [L] Learn blocks")
  ui.print_line(row+1, "  [S] Settings")
  ui.print_line(row+2, "  [H] Home calibrate")
  ui.hr(row+3)
  ui.print_line(row+4, "  [Q] Quit")
  while true do
    local ch = read_key_name()
    local idx = key_to_digit(ch)
    if idx and strats[idx] then return "strategy", strats[idx] end
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

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function format_value(item)
  local v = item.get()
  if item.kind == "bool" then return v and "on" or "off" end
  if item.kind == "enum" then return tostring(v) end
  if item.kind == "float" then return string.format(item.fmt or "%.2f", v) end
  return tostring(v)
end

local function adjust(item, direction)
  local v = item.get()
  if item.kind == "bool" then item.set(not v); return end
  if item.kind == "enum" then
    local idx = 1
    for i, val in ipairs(item.values) do if val == v then idx = i; break end end
    idx = ((idx - 1 + direction) % #item.values) + 1
    item.set(item.values[idx])
    return
  end
  local step = item.step or 1
  item.set(clamp(v + direction * step, item.min, item.max))
end

local function edit_page(title, items)
  local cursor = 1
  while true do
    render_header("settings > " .. title)
    for i, item in ipairs(items) do
      local prefix = (i == cursor) and ">" or " "
      ui.print_line(3 + i, string.format(" %s %-18s %s",
        prefix, item.label, format_value(item)))
    end
    ui.hr(12)
    ui.print_line(13, " up/dn move  L/R adjust  Q back")
    local ch = read_key_name()
    if ch == "up" then cursor = math.max(1, cursor - 1)
    elseif ch == "down" then cursor = math.min(#items, cursor + 1)
    elseif ch == "left" then adjust(items[cursor], -1)
    elseif ch == "right" or ch == "enter" or ch == "space" then
      adjust(items[cursor], 1)
    elseif ch == "q" or ch == "backspace" then
      config.save(CONFIG_PATH, cfg)
      return
    end
  end
end

local function inventory_settings_page()
  edit_page("inventory", {
    { label = "junk policy", kind = "enum",
      values = { "drop", "keep", "overflow" },
      get = function() return cfg.inventory.junk_policy end,
      set = function(v) cfg.inventory.junk_policy = v end },
    { label = "keep for home", kind = "int", min = 1, max = 15, step = 1,
      get = function() return cfg.inventory.keep_slots_before_home end,
      set = function(v) cfg.inventory.keep_slots_before_home = v end },
    { label = "reserved fuel slot", kind = "int", min = 1, max = 16, step = 1,
      get = function() return cfg.inventory.reserved_fuel_slot end,
      set = function(v) cfg.inventory.reserved_fuel_slot = v end },
  })
end

local function fuel_settings_page()
  edit_page("fuel", {
    { label = "refuel below", kind = "int", min = 0, max = 100000, step = 500,
      get = function() return cfg.fuel.refuel_below end,
      set = function(v) cfg.fuel.refuel_below = v end },
    { label = "reserve home mult", kind = "float", min = 1.0, max = 3.0, step = 0.25,
      fmt = "%.2f",
      get = function() return cfg.fuel.reserve_for_home end,
      set = function(v) cfg.fuel.reserve_for_home = v end },
    { label = "abort below", kind = "int", min = 0, max = 10000, step = 100,
      get = function() return cfg.fuel.abort_below end,
      set = function(v) cfg.fuel.abort_below = v end },
  })
end

local function safety_settings_page()
  edit_page("safety", {
    { label = "seal lava", kind = "bool",
      get = function() return cfg.safety.seal_lava end,
      set = function(v) cfg.safety.seal_lava = v end },
    { label = "seal water", kind = "bool",
      get = function() return cfg.safety.seal_water end,
      set = function(v) cfg.safety.seal_water = v end },
    { label = "max redig", kind = "int", min = 1, max = 100, step = 5,
      get = function() return cfg.safety.max_redig_attempts end,
      set = function(v) cfg.safety.max_redig_attempts = v end },
    { label = "max attack", kind = "int", min = 1, max = 100, step = 1,
      get = function() return cfg.safety.max_attack_attempts end,
      set = function(v) cfg.safety.max_attack_attempts = v end },
  })
end

local function logging_settings_page()
  edit_page("logging", {
    { label = "level", kind = "enum",
      values = { "debug", "info", "warn", "error" },
      get = function() return cfg.logging.level end,
      set = function(v)
        cfg.logging.level = v
        logger.configure({ level = v })
      end },
    { label = "keep runs", kind = "int", min = 1, max = 100, step = 1,
      get = function() return cfg.logging.keep_runs end,
      set = function(v) cfg.logging.keep_runs = v end },
  })
end

local function ui_settings_page()
  edit_page("ui", {
    { label = "confirm destructive", kind = "bool",
      get = function() return cfg.ui.confirm_destructive end,
      set = function(v) cfg.ui.confirm_destructive = v end },
    { label = "show estimate detail", kind = "bool",
      get = function() return cfg.ui.show_estimate_detail end,
      set = function(v) cfg.ui.show_estimate_detail = v end },
  })
end

local function settings_screen()
  while true do
    render_header("settings")
    ui.print_line(4, " Pick a category:")
    ui.print_line(6,  "  [1] Inventory")
    ui.print_line(7,  "  [2] Fuel")
    ui.print_line(8,  "  [3] Safety")
    ui.print_line(9,  "  [4] Logging")
    ui.print_line(10, "  [5] UI")
    ui.hr(12)
    ui.print_line(13, " [Q] back to main menu")
    local ch = read_key_name()
    local n = key_to_digit(ch)
    if     n == 1 then inventory_settings_page()
    elseif n == 2 then fuel_settings_page()
    elseif n == 3 then safety_settings_page()
    elseif n == 4 then logging_settings_page()
    elseif n == 5 then ui_settings_page()
    elseif ch == "q" or ch == "backspace" then return end
  end
end

local function home_calibrate_screen()
  render_header("home calibrate")
  ui.print_line(4, " Checking chest behind turtle...")
  _G.turtle.turnRight(); _G.turtle.turnRight()
  local ok_back, data_back = _G.turtle.inspect()
  _G.turtle.turnRight(); _G.turtle.turnRight()
  if ok_back and data_back.name:match("chest") then
    ui.print_line(6, "  OK  chest detected behind")
  else
    ui.print_line(6, "  X   no chest behind; place + retry")
  end
  ui.print_line(13, " [any] back")
  read_key()
end

local function recovery_menu()
  local c = state.load_current()
  local s = state.load_strategy()
  render_header("recovery")
  ui.print_line(4,  " [!] Previous run did not complete")
  ui.print_line(6,  string.format("  strategy: %s", c and c.strategy or "?"))
  ui.print_line(7,  string.format("  phase:    %s", c and c.phase or "?"))
  ui.print_line(8,  string.format("  pos:      (%d,%d,%d)",
    c and c.pos.x or 0, c and c.pos.y or 0, c and c.pos.z or 0))
  ui.print_line(10, "  [R] resume   [H] panic home")
  ui.print_line(11, "  [W] wipe     [Q] quit")
  local countdown = 10
  ui.print_line(13, string.format("  auto-resuming in %2ds... (any key cancels)", countdown))
  local timer = os.startTimer(1)
  while true do
    local ev, arg = os.pullEvent()
    if ev == "timer" and arg == timer then
      countdown = countdown - 1
      if countdown <= 0 then return "resume", c, s end
      ui.print_line(13, string.format("  auto-resuming in %2ds... (any key cancels)", countdown))
      timer = os.startTimer(1)
    elseif ev == "key" then
      ui.print_line(13, string.rep(" ", 39))
      local ch = keys.getName and keys.getName(arg) or ""
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
