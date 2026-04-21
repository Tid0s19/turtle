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
