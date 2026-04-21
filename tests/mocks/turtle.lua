-- A tiny grid-world turtle. (x,y,z) starts at (0,0,0) facing 0 (+Z).
local M = {}

local pos, facing = {x=0,y=0,z=0}, 0
local blocks = {}
local inventory = {}
local selected = 1
local fuel = 1000
local fuel_limit = "unlimited"

local DX = {[0]=0,[1]=1,[2]=0,[3]=-1}
local DZ = {[0]=1,[1]=0,[2]=-1,[3]=0}

local function key(x,y,z) return x..","..y..","..z end
local function frontPos() return pos.x + DX[facing], pos.y, pos.z + DZ[facing] end

function M._reset()
  pos = {x=0,y=0,z=0}; facing = 0; blocks = {}; inventory = {}
  selected = 1; fuel = 1000; fuel_limit = "unlimited"
end
function M._setBlock(x,y,z,data) blocks[key(x,y,z)] = data end
function M._getBlock(x,y,z) return blocks[key(x,y,z)] end
function M._setPos(x,y,z,f) pos={x=x,y=y,z=z}; facing = f or 0 end
function M._getPos() return {x=pos.x, y=pos.y, z=pos.z}, facing end
function M._setInv(slot, item) inventory[slot] = item end
function M._getInv() local c={}; for k,v in pairs(inventory) do c[k]={name=v.name,count=v.count} end; return c end
function M._setFuel(n) fuel = n end
function M._setFuelLimit(n) fuel_limit = n end

local function inspectAt(x,y,z)
  local b = blocks[key(x,y,z)]
  if b then return true, b else return false, "No block to inspect" end
end

function M.inspect() local fx,fy,fz = frontPos(); return inspectAt(fx,fy,fz) end
function M.inspectUp() return inspectAt(pos.x, pos.y+1, pos.z) end
function M.inspectDown() return inspectAt(pos.x, pos.y-1, pos.z) end

local function moveTo(nx, ny, nz)
  if blocks[key(nx,ny,nz)] then return false, "Movement obstructed" end
  if fuel_limit ~= "unlimited" and fuel <= 0 then return false, "Out of fuel" end
  pos.x, pos.y, pos.z = nx, ny, nz
  if fuel_limit ~= "unlimited" then fuel = fuel - 1 end
  return true
end

function M.forward() local fx,fy,fz = frontPos(); return moveTo(fx,fy,fz) end
function M.back()
  return moveTo(pos.x - DX[facing], pos.y, pos.z - DZ[facing])
end
function M.up() return moveTo(pos.x, pos.y+1, pos.z) end
function M.down() return moveTo(pos.x, pos.y-1, pos.z) end

function M.turnLeft() facing = (facing + 3) % 4; return true end
function M.turnRight() facing = (facing + 1) % 4; return true end

local function digAt(x,y,z)
  local b = blocks[key(x,y,z)]
  if not b then return false, "Nothing to dig" end
  blocks[key(x,y,z)] = nil
  for i = 1, 16 do
    if not inventory[i] then
      inventory[i] = {name = b.name, count = 1}
      return true
    end
  end
  return true
end
function M.dig() local fx,fy,fz = frontPos(); return digAt(fx,fy,fz) end
function M.digUp() return digAt(pos.x, pos.y+1, pos.z) end
function M.digDown() return digAt(pos.x, pos.y-1, pos.z) end

function M.select(s) selected = s; return true end
function M.getSelectedSlot() return selected end
function M.getItemCount(s) return (inventory[s] and inventory[s].count) or 0 end
function M.getItemDetail(s)
  if not inventory[s] then return nil end
  return { name = inventory[s].name, count = inventory[s].count }
end

function M.getFuelLevel() return fuel_limit == "unlimited" and "unlimited" or fuel end

local function placeAt(x,y,z)
  local item = inventory[selected]
  if not item or item.count == 0 then return false, "No items" end
  if blocks[key(x,y,z)] then return false, "Occupied" end
  blocks[key(x,y,z)] = { name = item.name }
  item.count = item.count - 1
  if item.count == 0 then inventory[selected] = nil end
  return true
end
function M.place() local fx,fy,fz = frontPos(); return placeAt(fx,fy,fz) end
function M.placeUp() return placeAt(pos.x, pos.y+1, pos.z) end
function M.placeDown() return placeAt(pos.x, pos.y-1, pos.z) end

function M.drop(n)
  local fx,fy,fz = frontPos()
  local b = blocks[key(fx,fy,fz)]
  if not b or not b.is_chest then return false, "No chest" end
  local item = inventory[selected]
  if not item then return false, "Empty slot" end
  n = n or item.count
  b.contents = b.contents or {}
  table.insert(b.contents, { name = item.name, count = math.min(n, item.count) })
  item.count = item.count - math.min(n, item.count)
  if item.count <= 0 then inventory[selected] = nil end
  return true
end

function M.suck(n)
  local fx,fy,fz = frontPos()
  local b = blocks[key(fx,fy,fz)]
  if not b or not b.contents or #b.contents == 0 then return false end
  local item = table.remove(b.contents, 1)
  for i = 1, 16 do
    if not inventory[i] then
      inventory[i] = {name = item.name, count = item.count}
      return true
    end
  end
  return false
end

function M.refuel(n)
  local item = inventory[selected]
  if not item then return false end
  local add = (item.name:match("coal") and 80) or (item.name:match("charcoal") and 80) or 0
  if add == 0 then return false end
  n = n or item.count
  if fuel_limit ~= "unlimited" then fuel = fuel + add * n end
  item.count = item.count - n
  if item.count <= 0 then inventory[selected] = nil end
  return true
end

function M.attack() return false, "Nothing to attack" end

return M
