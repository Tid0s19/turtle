local util = require("lib.util")
local state = require("lib.state")

local M = {}

local cfg = nil
local inv = nil
local enter_hooks, exit_hooks = {}, {}

local pos = { x = 0, y = 0, z = 0 }
local facing = 0

local DX = {[0]=0,[1]=1,[2]=0,[3]=-1}
local DZ = {[0]=1,[1]=0,[2]=-1,[3]=0}

local function sleep_safe(s)
  if os and os.sleep then os.sleep(s) elseif _G.sleep then _G.sleep(s) end
end

function M.configure(opts)
  cfg = opts.config
  inv = opts.inventory
  enter_hooks, exit_hooks = {}, {}
  local c = state.load_current()
  if c then
    pos = util.deep_clone(c.pos); facing = c.facing
  else
    pos = { x = 0, y = 0, z = 0 }; facing = 0
  end
end

function M.onEnterCell(fn) table.insert(enter_hooks, fn) end
function M.onExitCell(fn)  table.insert(exit_hooks, fn)  end

function M.getPos() return { x = pos.x, y = pos.y, z = pos.z, facing = facing } end

local function fire_exit()
  local cell = { pos = util.deep_clone(pos), facing = facing }
  for _, fn in ipairs(exit_hooks) do pcall(fn, cell) end
end

local function fire_enter()
  local cell = { pos = util.deep_clone(pos), facing = facing }
  for _, fn in ipairs(enter_hooks) do pcall(fn, cell) end
end

local function classify_block(data)
  if not data then return "air" end
  local name = data.name or ""
  if util.matches_any(name, cfg.safety.bedrock_names, {}) or
     util.matches_any(name, {}, cfg.safety.bedrock_names) then
    return "bedrock"
  end
  if cfg.safety.seal_lava and util.matches_any(name, {}, cfg.safety.dangerous_liquids) then
    return "liquid"
  end
  if name == "minecraft:gravel" or name == "minecraft:sand" then
    return "falling"
  end
  return "block"
end

local function try_move(dir_move, dir_inspect, dir_dig, dir_seal, axis_delta)
  fire_exit()
  if dir_move() then
    pos.x = pos.x + axis_delta.x
    pos.y = pos.y + axis_delta.y
    pos.z = pos.z + axis_delta.z
    state.persist_position(pos, facing)
    fire_enter()
    return true
  end

  local ok, data = dir_inspect()
  local kind = ok and classify_block(data) or "unknown"

  if kind == "bedrock" then return false, "bedrock" end

  if kind == "liquid" then
    if not dir_seal() then return false, "no_seal" end
    dir_dig()
    if dir_move() then
      pos.x = pos.x + axis_delta.x
      pos.y = pos.y + axis_delta.y
      pos.z = pos.z + axis_delta.z
      state.persist_position(pos, facing)
      fire_enter()
      return true
    end
    return false, "no_seal"
  end

  if kind == "falling" then
    for _ = 1, cfg.safety.max_redig_attempts do
      dir_dig()
      sleep_safe(0.2)
      if dir_move() then
        pos.x = pos.x + axis_delta.x
        pos.y = pos.y + axis_delta.y
        pos.z = pos.z + axis_delta.z
        state.persist_position(pos, facing)
        fire_enter()
        return true
      end
    end
    return false, "falling_cap"
  end

  dir_dig()
  if dir_move() then
    pos.x = pos.x + axis_delta.x
    pos.y = pos.y + axis_delta.y
    pos.z = pos.z + axis_delta.z
    state.persist_position(pos, facing)
    fire_enter()
    return true
  end
  for _ = 1, cfg.safety.max_attack_attempts do
    turtle.attack()
    if dir_move() then
      pos.x = pos.x + axis_delta.x
      pos.y = pos.y + axis_delta.y
      pos.z = pos.z + axis_delta.z
      state.persist_position(pos, facing)
      fire_enter()
      return true
    end
  end
  return false, "blocked"
end

function M.forward()
  local d = { x = DX[facing], y = 0, z = DZ[facing] }
  return try_move(turtle.forward, turtle.inspect, turtle.dig,
    function() return inv.place_seal_forward() end, d)
end

function M.up()
  return try_move(turtle.up, turtle.inspectUp, turtle.digUp,
    function() return inv.place_seal_up() end, { x=0, y=1, z=0 })
end

function M.down()
  return try_move(turtle.down, turtle.inspectDown, turtle.digDown,
    function() return inv.place_seal_down() end, { x=0, y=-1, z=0 })
end

function M.back()
  fire_exit()
  if turtle.back() then
    pos.x = pos.x - DX[facing]
    pos.z = pos.z - DZ[facing]
    state.persist_position(pos, facing)
    fire_enter()
    return true
  end
  return false, "blocked"
end

function M.turnLeft()
  fire_exit()
  turtle.turnLeft()
  facing = (facing + 3) % 4
  state.persist_position(pos, facing)
  fire_enter()
  return true
end

function M.turnRight()
  fire_exit()
  turtle.turnRight()
  facing = (facing + 1) % 4
  state.persist_position(pos, facing)
  fire_enter()
  return true
end

function M.face(dir)
  local diff = (dir - facing) % 4
  if diff == 1 then M.turnRight()
  elseif diff == 2 then M.turnRight(); M.turnRight()
  elseif diff == 3 then M.turnLeft()
  end
  return true
end

function M.dig()     return turtle.dig()     end
function M.digUp()   return turtle.digUp()   end
function M.digDown() return turtle.digDown() end

function M.inspect()     return turtle.inspect()     end
function M.inspectUp()   return turtle.inspectUp()   end
function M.inspectDown() return turtle.inspectDown() end

return M
