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
    t.assert_true(_G.fs.exists("/config.lua"))
  end)

  t.it("merges user overrides with defaults", function()
    reset()
    _G.fs._inject("/config.lua", [[
      return { version = 1, inventory = { junk_policy = "keep" } }
    ]])
    local cfg = config.load("/config.lua")
    t.assert_eq(cfg.inventory.junk_policy, "keep")
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
