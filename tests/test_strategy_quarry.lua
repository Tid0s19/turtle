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
  t.it("mines a 2x2 area down to bedrock and returns", function()
    local ctx = fresh_ctx()
    for x = 0, 1 do for z = 0, 1 do
      _G.turtle._setBlock(x, -3, z, { name = "minecraft:bedrock" })
      _G.turtle._setBlock(x, -1, z, { name = "minecraft:stone" })
      _G.turtle._setBlock(x, -2, z, { name = "minecraft:stone" })
    end end
    local q = load_quarry()
    q.run({ width = 2, length = 2, depth = "bedrock" }, ctx)
    local p = state.load_current().pos
    t.assert_true(math.abs(p.x) <= 1 and math.abs(p.z) <= 1 and p.y >= -1)
  end)
end)
