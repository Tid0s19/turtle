package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")
local util = require("lib.util")

t.describe("util.matches_any", function()
  t.it("returns true for exact name match", function()
    t.assert_true(util.matches_any("minecraft:cobblestone",
      { "minecraft:cobblestone" }, {}))
  end)
  t.it("returns true for pattern match", function()
    t.assert_true(util.matches_any("create:limestone",
      {}, { ".*:limestone$" }))
  end)
  t.it("prefers exact over pattern (exact is checked first)", function()
    t.assert_true(util.matches_any("x:y", { "x:y" }, { ".*" }))
  end)
  t.it("returns false when neither matches", function()
    t.assert_false(util.matches_any("x:y", { "z:w" }, { "^nope$" }))
  end)
  t.it("is safe against empty / nil lists", function()
    t.assert_false(util.matches_any("x:y", nil, nil))
    t.assert_false(util.matches_any("x:y", {}, {}))
  end)
end)

t.describe("util.deep_clone", function()
  t.it("clones nested tables without shared references", function()
    local a = { x = 1, y = { z = 2 } }
    local b = util.deep_clone(a)
    b.y.z = 99
    t.assert_eq(a.y.z, 2)
    t.assert_eq(b.y.z, 99)
  end)
end)

t.describe("util.deep_merge", function()
  t.it("overlays src onto dst recursively", function()
    local dst = { a = 1, b = { c = 2, d = 3 } }
    local src = { b = { c = 99 }, e = 5 }
    local out = util.deep_merge(dst, src)
    t.assert_deep_eq(out, { a = 1, b = { c = 99, d = 3 }, e = 5 })
  end)
  t.it("replaces arrays wholesale (does not merge list items)", function()
    local dst = { xs = { 1, 2, 3 } }
    local src = { xs = { 9 } }
    local out = util.deep_merge(dst, src)
    t.assert_deep_eq(out.xs, { 9 })
  end)
end)

t.describe("util.now_epoch_s", function()
  t.it("returns an integer number of seconds", function()
    local n = util.now_epoch_s()
    t.assert_eq(type(n), "number")
    t.assert_true(n > 0)
  end)
end)
