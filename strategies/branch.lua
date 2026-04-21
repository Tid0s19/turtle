local M = {
  name = "branch", display = "Branch",
  description = "Main tunnel with perpendicular branches every N blocks.",
}

function M.promptParams(defaults)
  defaults = defaults or {}
  return {
    main_length   = defaults.main_length   or 32,
    branch_length = defaults.branch_length or 8,
    branch_spacing= defaults.branch_spacing or 3,
  }
end

function M.estimate(params)
  local num_branches = math.floor(params.main_length / params.branch_spacing)
  local blocks = params.main_length * 2
    + num_branches * params.branch_length * 2 * 2
  local fuel = params.main_length * 2
    + num_branches * params.branch_length * 4
  return { fuel = fuel, blocks = blocks, seconds = math.floor(blocks * 0.2) }
end

function M.preflight(params)
  if params.main_length < 1 or params.branch_length < 0 or params.branch_spacing < 1 then
    return false, "invalid params"
  end
  return true
end

local function carve_branch_at(z, params, ctx, dir)
  ctx.nav.goTo(0, 0, z)
  ctx.nav.face(dir)
  for step = 1, params.branch_length do
    if ctx.shouldStop() then return false, "stopped" end
    local ok, err = require("lib.movement").forward()
    if not ok then return false, err end
    require("lib.movement").digUp()
    ctx.inv.handle_junk_by_policy()
  end
  ctx.nav.goTo(0, 0, z)
end

local function run_body(params, ctx, start_z, start_side)
  local num_branches = math.floor(params.main_length / params.branch_spacing)
  for b = math.floor(start_z / params.branch_spacing), num_branches - 1 do
    local z = (b + 1) * params.branch_spacing
    ctx.nav.goTo(0, 0, z)
    require("lib.movement").digUp()
    if start_side ~= "right" then carve_branch_at(z, params, ctx, 3) end
    carve_branch_at(z, params, ctx, 1)
    start_side = nil
    ctx.saveProgress({ branch_idx = b, direction = "done" })
  end
  ctx.nav.goTo(0, 0, 0)
  ctx.nav.face(2)
  ctx.inv.deposit_all_keep()
  ctx.nav.face(0)
  return true
end

function M.run(params, ctx) return run_body(params, ctx, 0, nil) end

function M.resume(params, progress, ctx)
  local start_idx = (progress.branch_idx or -1) + 1
  local start_z = start_idx * params.branch_spacing
  return run_body(params, ctx, start_z, nil)
end

function M.expectedCell(params, progress)
  if progress.branch_idx == nil then return nil end
  return { x = 0, y = 0, z = (progress.branch_idx + 1) * params.branch_spacing }
end

return M
