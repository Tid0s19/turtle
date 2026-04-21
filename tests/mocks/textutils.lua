-- Minimal textutils mock. Serialise produces a Lua-loadable string.
local M = {}

local function ser(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "nil" then return "nil" end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t == "table" then
    local parts = {"{"}
    local ni = indent .. "  "
    for k, val in pairs(v) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. ser(k, ni) .. "]"
      end
      table.insert(parts, ni .. key .. " = " .. ser(val, ni) .. ",")
    end
    table.insert(parts, indent .. "}")
    return table.concat(parts, "\n")
  end
  error("cannot serialise " .. t)
end

function M.serialise(v) return ser(v) end
M.serialize = M.serialise

function M.unserialise(s)
  if not s or s == "" then return nil end
  local f = load("return " .. s, "unserialise", "t", {})
  if not f then return nil end
  local ok, v = pcall(f)
  if not ok then return nil end
  return v
end
M.unserialize = M.unserialise

function M.serialiseJSON(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
  if t == "table" then
    local parts, is_array, n = {}, true, 0
    for k, _ in pairs(v) do
      n = n + 1
      if type(k) ~= "number" then is_array = false end
    end
    if is_array then
      for i = 1, n do table.insert(parts, M.serialiseJSON(v[i])) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, val in pairs(v) do
        table.insert(parts,
          string.format("%q", tostring(k)) .. ":" .. M.serialiseJSON(val))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  error("JSON: cannot serialise " .. t)
end
M.serializeJSON = M.serialiseJSON

return M
