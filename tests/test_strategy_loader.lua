package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")

local loader = require("lib.strategy_loader")

local function reset() _G.fs._reset() end

t.describe("strategy_loader.list", function()
  t.it("lists .lua files in /strategies (ignoring underscored fixtures)", function()
    reset()
    _G.fs._inject("/strategies/quarry.lua",
      "return { name = 'quarry', display = 'Quarry', description = 'x', " ..
      "promptParams=function()end, estimate=function()return{fuel=0,blocks=0,seconds=0}end, " ..
      "preflight=function()return true end, run=function()end, resume=function()end }")
    _G.fs._inject("/strategies/_example.lua", "return {}")
    local names = loader.list()
    t.assert_eq(#names, 1)
    t.assert_eq(names[1], "quarry")
  end)
end)

t.describe("strategy_loader.load", function()
  t.it("validates the contract", function()
    reset()
    _G.fs._inject("/strategies/bad.lua", "return { name = 'bad' }")
    t.assert_error(function() loader.load("bad") end, "missing")
  end)

  t.it("loads a valid strategy", function()
    reset()
    _G.fs._inject("/strategies/ok.lua",
      "return { name='ok', display='OK', description='d', " ..
      "promptParams=function()return{}end, " ..
      "estimate=function()return{fuel=0,blocks=0,seconds=0}end, " ..
      "preflight=function()return true end, " ..
      "run=function()end, resume=function()end }")
    local s = loader.load("ok")
    t.assert_eq(s.name, "ok")
  end)
end)
