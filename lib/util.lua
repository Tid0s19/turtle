local M = {}

function M.matches_any(name, exact, patterns)
  if exact then
    for _, n in ipairs(exact) do if n == name then return true end end
  end
  if patterns then
    for _, p in ipairs(patterns) do if name:match(p) then return true end end
  end
  return false
end

function M.deep_clone(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = M.deep_clone(x) end
  return out
end

local function is_array(t)
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n > 0
end

function M.deep_merge(dst, src)
  local out = M.deep_clone(dst)
  for k, v in pairs(src) do
    if type(v) == "table" and type(out[k]) == "table"
       and not is_array(v) and not is_array(out[k]) then
      out[k] = M.deep_merge(out[k], v)
    else
      out[k] = M.deep_clone(v)
    end
  end
  return out
end

function M.now_epoch_s()
  if os.epoch then
    return math.floor(os.epoch("utc") / 1000)
  end
  return os.time()
end

return M
