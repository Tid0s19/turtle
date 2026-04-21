package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.textutils = require("tests.mocks.textutils")
_G.turtle = require("tests.mocks.turtle")
_G.os.epoch = function(_) return 1713648063000 end
_G.os.sleep = function(_) end
_G.sleep = function(_) end

local config = require("lib.config")
local inv = require("lib.inventory")

local function reset()
  _G.turtle._reset()
  inv.configure({ config = config.defaults() })
end

t.describe("inventory classification", function()
  t.it("tags each slot by block name", function()
    reset()
    _G.turtle._setInv(1, { name = "minecraft:cobblestone", count = 30 })
    _G.turtle._setInv(2, { name = "minecraft:coal", count = 8 })
    _G.turtle._setInv(3, { name = "minecraft:diamond_ore", count = 2 })
    local tags = inv.classify_slots()
    t.assert_eq(tags[1], "junk")
    t.assert_eq(tags[2], "fuel")
    t.assert_eq(tags[3], "keep")
  end)
end)

t.describe("inventory.should_go_home", function()
  local function set_keep(n)
    _G.turtle._reset()
    for i = 1, n do
      _G.turtle._setInv(i, { name = "minecraft:diamond_ore", count = 1 })
    end
  end
  t.it("returns true when keep slots >= keep_slots_before_home", function()
    reset()
    set_keep(12)
    t.assert_true(inv.should_go_home())
  end)
  t.it("returns false below the threshold", function()
    reset()
    set_keep(11)
    t.assert_false(inv.should_go_home())
  end)
end)

t.describe("inventory.drop_junk_in_place", function()
  t.it("drops junk-tagged slots and leaves keep", function()
    reset()
    _G.turtle._setInv(1, { name = "minecraft:cobblestone", count = 30 })
    _G.turtle._setInv(2, { name = "minecraft:diamond_ore", count = 1 })
    local dropped = {}
    _G.turtle.drop     = function() local it = _G.turtle.getItemDetail(_G.turtle.getSelectedSlot()); if it then dropped[#dropped+1] = it.name end; _G.turtle._setInv(_G.turtle.getSelectedSlot(), nil); return true end
    _G.turtle.dropUp   = _G.turtle.drop
    _G.turtle.dropDown = _G.turtle.drop
    inv.drop_junk_in_place()
    t.assert_eq(_G.turtle.getItemDetail(1), nil)
    t.assert_eq(_G.turtle.getItemDetail(2).name, "minecraft:diamond_ore")
  end)
end)

t.describe("inventory.refuel_from_slot", function()
  t.it("burns from the reserved fuel slot until threshold met", function()
    reset()
    _G.turtle._setInv(16, { name = "minecraft:coal", count = 64 })
    _G.turtle._setFuelLimit(20000)
    _G.turtle._setFuel(100)
    inv.refuel_from_slot(5000)
    t.assert_true(_G.turtle.getFuelLevel() >= 5000)
  end)
  t.it("returns false when reserved slot has no fuel", function()
    reset()
    _G.turtle._setFuelLimit(20000)
    _G.turtle._setFuel(100)
    local ok = inv.refuel_from_slot(5000)
    t.assert_false(ok)
  end)
end)
