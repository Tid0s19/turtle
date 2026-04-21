local M = {
  name = "strip", display = "Strip",
  description = "Straight 2-tall tunnel",
  paramSchema = {
    { key = "length", label = "length", kind = "int",
      min = 1, max = 256, step = 4, default = 32 },
  },
}

function M.promptParams(defaults)
  defaults = defaults or {}
  return { length = defaults.length or 32 }
end

function M.estimate(params)
  local blocks = params.length * 2
  local fuel = params.length * 2 + params.length
  return { fuel = fuel, blocks = blocks, seconds = math.floor(blocks * 0.2) }
end

function M.preflight(params)
  if not params.length or params.length < 1 then return false, "length" end
  return true
end

local function run_body(params, ctx, start_z)
  local movement = require("lib.movement")
  local home = require("lib.home")
  for z = start_z, params.length do
    if ctx.shouldStop() then return false, "stopped" end
    local ok, err = ctx.nav.goTo(0, 0, z)
    if not ok then return false, err end
    movement.digUp()
    ctx.inv.handle_junk_by_policy()
    ctx.inv.refuel_if_low()
    if ctx.inv.should_go_home() then home.excursion(ctx) end
    ctx.saveProgress({ length_done = z, direction = "outbound" })
  end
  home.deposit(ctx)
  return true
end

function M.run(params, ctx) return run_body(params, ctx, 1) end

function M.resume(params, progress, ctx)
  local start = (progress.length_done or 0) + 1
  if start > params.length then
    ctx.nav.goTo(0, 0, 0); return true
  end
  return run_body(params, ctx, start)
end

function M.expectedCell(_, progress)
  if not progress.length_done then return nil end
  return { x = 0, y = 0, z = progress.length_done }
end

return M
