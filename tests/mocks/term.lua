local M = {}
local buf = {}
function M._reset() buf = {} end
function M._capture() return table.concat(buf, "\n") end
function M.clear() buf = {} end
function M.setCursorPos(_,_) end
function M.write(s) table.insert(buf, tostring(s)) end
function M.setTextColor(_) end
function M.setBackgroundColor(_) end
function M.isColor() return false end
function M.isColour() return false end
function M.getSize() return 39, 13 end
return M
