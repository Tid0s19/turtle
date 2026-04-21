local M = {}

local REQUIRED = { "name", "display", "description",
                   "promptParams", "estimate", "preflight", "run", "resume" }

local function load_file(path)
  local h = fs.open(path, "r")
  if not h then error("cannot read " .. path) end
  local src = h.readAll(); h.close()
  local chunk, err = load(src, path, "t", _ENV or _G)
  if not chunk then error("parse error in " .. path .. ": " .. tostring(err)) end
  local ok, v = pcall(chunk)
  if not ok then error("exec error in " .. path .. ": " .. tostring(v)) end
  return v
end

function M.list()
  local out = {}
  if not fs.list then return out end
  for _, f in ipairs(fs.list("/strategies")) do
    if f:match("%.lua$") and not f:match("^_") then
      table.insert(out, (f:gsub("%.lua$", "")))
    end
  end
  table.sort(out)
  return out
end

function M.load(name)
  local path = "/strategies/" .. name .. ".lua"
  local strat = load_file(path)
  if type(strat) ~= "table" then error("strategy did not return a table: " .. path) end
  for _, key in ipairs(REQUIRED) do
    if strat[key] == nil then
      error("strategy " .. name .. " missing required field: " .. key)
    end
  end
  strat.name = strat.name or name
  return strat
end

return M
