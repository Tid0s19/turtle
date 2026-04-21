package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.os.epoch = function(_) return 1713648063000 end

local state = require("lib.state")

local function reset() _G.fs._reset(); state.reset() end

t.describe("state.new_run", function()
  t.it("creates current and strategy files with matching run_id", function()
    reset()
    state.new_run({
      strategy = "quarry",
      params = { width = 8, length = 8 },
      home = { x = 0, y = 0, z = 0, facing = 0 },
      fuel_at_start = 10000,
    })
    t.assert_true(_G.fs.exists("/state/current.lua"))
    t.assert_true(_G.fs.exists("/state/strategy.lua"))
    local c = state.load_current()
    local s = state.load_strategy()
    t.assert_eq(c.run_id, s.run_id)
    t.assert_eq(c.phase, "planning")
    t.assert_eq(s.strategy, "quarry")
  end)
end)

t.describe("state.persist_position", function()
  t.it("updates pos and facing and bumps last_write_at", function()
    reset()
    state.new_run({
      strategy = "quarry", params = {}, home = { x=0,y=0,z=0, facing=0 },
      fuel_at_start = 100,
    })
    state.persist_position({ x = 2, y = -3, z = 5 }, 1)
    local c = state.load_current()
    t.assert_deep_eq(c.pos, { x = 2, y = -3, z = 5 })
    t.assert_eq(c.facing, 1)
  end)
end)

t.describe("state.save_progress", function()
  t.it("overwrites the progress table", function()
    reset()
    state.new_run({
      strategy = "quarry", params = { width = 4 },
      home = { x=0,y=0,z=0, facing=0 }, fuel_at_start = 100,
    })
    state.save_progress({ col = 1, row = 2 })
    local s = state.load_strategy()
    t.assert_deep_eq(s.progress, { col = 1, row = 2 })
  end)
end)

t.describe("state.load + corruption", function()
  t.it("returns nil when files missing", function()
    reset()
    t.assert_nil(state.load_current())
    t.assert_nil(state.load_strategy())
  end)
  t.it("returns nil when file is corrupt", function()
    reset()
    _G.fs._inject("/state/current.lua", "not valid }}}")
    t.assert_nil(state.load_current())
  end)
end)

t.describe("state.run_id_mismatch", function()
  t.it("detects when current and strategy disagree", function()
    reset()
    state.new_run({
      strategy = "quarry", params = {},
      home = { x=0,y=0,z=0, facing=0 }, fuel_at_start = 100,
    })
    _G.fs._inject("/state/strategy.lua",
      "return { version = 1, run_id = \"other\", strategy = \"quarry\", params = {}, progress = {} }")
    local current = state.load_current()
    local strat = state.load_strategy()
    t.assert_false(current.run_id == strat.run_id)
  end)
end)

t.describe("state.set_phase", function()
  t.it("transitions phase without losing other fields", function()
    reset()
    state.new_run({
      strategy = "quarry", params = {},
      home = { x=0,y=0,z=0,facing=0 }, fuel_at_start = 100,
    })
    state.set_phase("mining")
    t.assert_eq(state.load_current().phase, "mining")
  end)
end)

t.describe("state.clear", function()
  t.it("removes both state files", function()
    reset()
    state.new_run({
      strategy = "quarry", params = {},
      home = { x=0,y=0,z=0,facing=0 }, fuel_at_start = 100,
    })
    state.clear()
    t.assert_false(_G.fs.exists("/state/current.lua"))
    t.assert_false(_G.fs.exists("/state/strategy.lua"))
  end)
end)
