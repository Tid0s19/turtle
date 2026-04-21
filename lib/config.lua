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
      "minecraft:cobbled_deepslate", "minecraft:dirt",
    },
    seal_patterns = { ".*:dirt$" },
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
    bucket_lava = true,
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
  if util.matches_any(name, inv.fuel, inv.fuel_patterns) then return "fuel" end
  if util.matches_any(name, inv.seal, inv.seal_patterns) then return "seal" end
  if util.matches_any(name, inv.junk, inv.junk_patterns) then return "junk" end
  return "keep"
end

return M
