local config_mod = require("lib.config")

local M = {}
local cfg = nil

function M.configure(opts) cfg = opts.config end

function M.classify_slots()
  local tags = {}
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then tags[i] = config_mod.classify(d.name, cfg) end
  end
  return tags
end

function M.count_by_tag()
  local c = { keep = 0, junk = 0, fuel = 0, seal = 0, empty = 0 }
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then
      local tag = config_mod.classify(d.name, cfg)
      c[tag] = (c[tag] or 0) + 1
    else
      c.empty = c.empty + 1
    end
  end
  return c
end

function M.should_go_home()
  return M.count_by_tag().keep >= cfg.inventory.keep_slots_before_home
end

function M.is_full()
  return M.count_by_tag().empty == 0
end

function M.drop_junk_in_place()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and config_mod.classify(d.name, cfg) == "junk" then
      turtle.select(i)
      turtle.dropDown()
    end
  end
  turtle.select(1)
end

function M.refuel_from_slot(target)
  local slot = cfg.inventory.reserved_fuel_slot
  local prev = turtle.getSelectedSlot()
  turtle.select(slot)
  local ok = turtle.refuel()
  turtle.select(prev)
  if not ok then return false end
  while turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < target do
    turtle.select(slot)
    if not turtle.refuel() then turtle.select(prev); return false end
  end
  turtle.select(prev)
  return true
end

local function find_slot_by_tag(tag)
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and config_mod.classify(d.name, cfg) == tag then return i end
  end
  return nil
end

local function do_place_seal(place_fn)
  local s = find_slot_by_tag("seal")
  if not s then return false end
  local prev = turtle.getSelectedSlot()
  turtle.select(s)
  local ok = place_fn()
  turtle.select(prev)
  return ok
end

function M.place_seal_forward() return do_place_seal(turtle.place) end
function M.place_seal_up()      return do_place_seal(turtle.placeUp) end
function M.place_seal_down()    return do_place_seal(turtle.placeDown) end

function M.deposit_all_keep()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then
      local tag = config_mod.classify(d.name, cfg)
      if tag == "keep" then
        turtle.select(i)
        while not turtle.drop() do
          return false, "chest_full", i
        end
      end
    end
  end
  turtle.select(1)
  return true
end

function M.handle_junk_by_policy()
  local policy = cfg.inventory.junk_policy
  if policy == "drop" then
    M.drop_junk_in_place()
  elseif policy == "keep" then
    -- no-op; junk deposited at home like keep
  elseif policy == "overflow" then
    if M.is_full() then M.drop_junk_in_place() end
  end
end

return M
