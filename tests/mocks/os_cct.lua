-- CC:T os extensions. Real os stays available.
local M = {}
local now_ms = 1713648063000
function M._setNow(ms) now_ms = ms end
function M._tick(ms) now_ms = now_ms + ms end
function M.epoch(which)
  if which == "utc" or which == "local" then return now_ms end
  return now_ms
end
function M.getComputerID() return 42 end
function M.getComputerLabel() return "test-turtle" end
function M.clock() return now_ms / 1000 end
function M.sleep(_) end
return M
