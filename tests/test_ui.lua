package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.term = require("tests.mocks.term")
_G.colors = setmetatable({}, { __index = function() return 1 end })

local ui = require("lib.ui")

t.describe("ui.center_text", function()
  t.it("pads to centre on a 39-wide screen", function()
    local s = ui.center_text("hi", 39)
    t.assert_eq(#s, 39)
    t.assert_true(s:match("hi") ~= nil)
  end)
end)

t.describe("ui.progress_bar", function()
  t.it("renders correct fill proportions", function()
    t.assert_eq(ui.progress_bar(0.00, 10), string.rep("\u{2591}", 10))
    t.assert_eq(ui.progress_bar(0.50, 10), string.rep("\u{2588}", 5) .. string.rep("\u{2591}", 5))
    t.assert_eq(ui.progress_bar(1.00, 10), string.rep("\u{2588}", 10))
  end)
end)

t.describe("ui.format_fuel", function()
  t.it("abbreviates thousands with k suffix", function()
    t.assert_eq(ui.format_fuel(18432), "18.4k")
    t.assert_eq(ui.format_fuel(500), "500")
    t.assert_eq(ui.format_fuel("unlimited"), "\u{221E}")
  end)
end)
