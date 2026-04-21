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
    local p = state.load_current().pos
    t.assert_deep_eq(p, { x = 0, y = 0, z = 0 })
  end)
end)
