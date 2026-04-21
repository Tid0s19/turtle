local M = {
  name = "strip", display = "Strip",
  description = "Dig a straight 1-wide, 2-tall tunnel of a given length.",
}

function M.promptParams(defaults)
  defaults = defaults or {}
  return { length = defaults.length or 64 }
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
  for z = start_z, params.length do
    if ctx.shouldStop() then return false, "stopped" end
    local ok, err = ctx.nav.goTo(0, 0, z)
    if not ok then return false, err end
    movement.digUp()
    ctx.inv.handle_junk_by_policy()
    ctx.saveProgress({ length_done = z, direction = "outbound" })
  end
  ctx.nav.goTo(0, 0, 0)
  ctx.nav.face(2)
  ctx.inv.deposit_all_keep()
  ctx.nav.face(0)
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
