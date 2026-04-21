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
    movement.face(3)
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
