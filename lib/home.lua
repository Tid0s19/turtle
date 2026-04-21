local state = require("lib.state")
local movement = require("lib.movement")

local M = {}

function M.deposit(ctx)
  local home = state.load_current().home
  ctx.nav.goTo(home.x, home.y, home.z)
  ctx.nav.face(2)
  ctx.inv.deposit_all_keep()
  ctx.inv.refuel_from_slot(ctx.config.fuel.refuel_below * 2)
  ctx.nav.face(home.facing or 0)
end

function M.excursion(ctx)
  local here = movement.getPos()
  M.deposit(ctx)
  ctx.nav.goTo(here.x, here.y, here.z)
  ctx.nav.face(here.facing)
end

return M
