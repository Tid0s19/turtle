local state = require("lib.state")
local movement = require("lib.movement")

local M = {}

local function currentPos() return movement.getPos() end

function M.face(dir) return movement.face(dir) end

function M.goTo(tx, ty, tz)
  while currentPos().y < ty do
    local ok, err = movement.up()
    if not ok then return false, err end
  end
  while currentPos().y > ty do
    local ok, err = movement.down()
    if not ok then return false, err end
  end
  local p = currentPos()
  if p.x ~= tx then
    movement.face(p.x < tx and 1 or 3)
    while currentPos().x ~= tx do
      local ok, err = movement.forward()
      if not ok then return false, err end
    end
  end
  p = currentPos()
  if p.z ~= tz then
    movement.face(p.z < tz and 0 or 2)
    while currentPos().z ~= tz do
      local ok, err = movement.forward()
      if not ok then return false, err end
    end
  end
  return true
end

function M.panicHome()
  local c = state.load_current()
  if not c then return false, "no_state" end
  local p = currentPos()
  while p.y < c.home.y do
    if not movement.up() then break end
    p = currentPos()
  end
  local ok = M.goTo(c.home.x, c.home.y, c.home.z)
  if ok then movement.face(c.home.facing) end
  return ok
end

function M.serpentine(width, length)
  local i = 0
  local total = width * length
  return function()
    if i >= total then return nil end
    local col = math.floor(i / length)
    local row_in_col = i % length
    local x = col
    local z = (col % 2 == 0) and row_in_col or (length - 1 - row_in_col)
    i = i + 1
    return { x = x, z = z, col = col, row = row_in_col }
  end
end

return M
