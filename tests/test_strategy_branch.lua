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
