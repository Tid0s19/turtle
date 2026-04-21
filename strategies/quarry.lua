local function is_bedrock(ctx, inspect_fn)
  local ok, data = inspect_fn()
  if not ok then return false end
  for _, name in ipairs(ctx.config.safety.bedrock_names) do
    if data.name == name or data.name:match(name) then return true end
  end
  return false
end

local function mine_column(ctx, target_y_or_bedrock)
  local movement = require("lib.movement")
  while true do
    if ctx.shouldStop() then return false, "stopped" end
    if is_bedrock(ctx, function() return _G.turtle.inspectDown() end) then break end
    local y = movement.getPos().y
    if type(target_y_or_bedrock) == "number" and y <= target_y_or_bedrock then break end
    local ok, err = movement.down()
    if not ok then return false, err end
  end
  while require("lib.movement").getPos().y < 0 do
    local ok, err = require("lib.movement").up()
    if not ok then return false, err end
  end
  return true
end

local home_mod = require("lib.home")

local M = {
  name = "quarry",
  display = "Quarry",
  description = "Area to bedrock",
  paramSchema = {
    { key = "width",  label = "width",  kind = "int",
      min = 1, max = 64, step = 1, default = 8 },
    { key = "length", label = "length", kind = "int",
      min = 1, max = 64, step = 1, default = 8 },
    { key = "depth",  label = "depth",  kind = "int",
      min = 0, max = 256, step = 4, default = 0,
      display = function(v) return v == 0 and "bedrock" or tostring(v) end },
  },
}

function M.promptParams(defaults)
  defaults = defaults or {}
  return {
    width  = defaults.width  or 8,
    length = defaults.length or 8,
    depth  = defaults.depth  or 0,
  }
end

local function resolve_depth(d)
  if d == nil or d == 0 or d == "bedrock" then return nil end
  return tonumber(d)
end

function M.estimate(params)
  local target = resolve_depth(params.depth)
  local depth_guess = target or 64
  local cells = params.width * params.length
  local blocks = cells * depth_guess
  local fuel = cells * (depth_guess * 2) + (params.width + params.length) * 2
  return { fuel = fuel, blocks = blocks, seconds = math.floor(blocks * 0.15) }
end

function M.preflight(params)
  if params.width < 1 or params.length < 1 then return false, "bad dimensions" end
  return true
end

local function run_body(params, ctx, start_col, start_row)
  local depth_blocks = resolve_depth(params.depth)
  local target_y = depth_blocks and -depth_blocks or nil
  for col = start_col, params.width - 1 do
    local forward = col % 2 == 0
    for r = 0, params.length - 1 do
      if col == start_col and r < start_row then goto continue end
      if ctx.shouldStop() then return false, "stopped" end
      local z = forward and r or (params.length - 1 - r)
      local ok, err = ctx.nav.goTo(col, 0, z)
      if not ok then return false, err end
      if ctx.inv.should_go_home() then home_mod.excursion(ctx) end
      local mc_ok, mc_err = mine_column(ctx, target_y or "bedrock")
      if not mc_ok then return false, mc_err end
      ctx.inv.handle_junk_by_policy()
      ctx.inv.refuel_if_low()
      ctx.saveProgress({ col = col, row = r, next_action = "next_cell" })
      ::continue::
    end
  end
  home_mod.deposit(ctx)
  return true
end

function M.run(params, ctx)
  return run_body(params, ctx, 0, 0)
end

function M.resume(params, progress, ctx)
  local start_col = progress.col or 0
  local start_row = (progress.row or 0) + 1
  if start_row >= params.length then
    start_col = start_col + 1
    start_row = 0
  end
  return run_body(params, ctx, start_col, start_row)
end

function M.expectedCell(params, progress)
  if not progress.col then return nil end
  local forward = progress.col % 2 == 0
  local z = forward and progress.row or (params.length - 1 - progress.row)
  return { x = progress.col, y = 0, z = z }
end

return M
