local M = {}

local W, H = 39, 13

function M.center_text(text, width)
  width = width or W
  local pad = math.max(0, width - #text)
  local left = math.floor(pad / 2)
  return string.rep(" ", left) .. text .. string.rep(" ", pad - left)
end

function M.progress_bar(frac, width)
  width = width or 14
  frac = math.max(0, math.min(1, frac))
  local filled = math.floor(frac * width + 0.5)
  return string.rep("#", filled) .. string.rep(".", width - filled)
end

function M.format_fuel(f)
  if f == "unlimited" then return "inf" end
  if f >= 1000 then return string.format("%.1fk", f / 1000) end
  return tostring(f)
end

function M.clear_screen()
  if term.clear then term.clear() end
  if term.setCursorPos then term.setCursorPos(1, 1) end
end

function M.print_line(row, text)
  if term.setCursorPos then term.setCursorPos(1, row) end
  term.write(text or "")
end

function M.hr(row, char)
  M.print_line(row, string.rep(char or "-", W))
end

function M.header(label, fuel, keep_count)
  M.print_line(1, string.format("%-14s fuel %-6s keep %d/16",
    label or "turtle", M.format_fuel(fuel or 0), keep_count or 0))
  M.hr(2)
end

function M.footer(row, text)
  M.hr(row - 1)
  M.print_line(row, text)
end

return M
