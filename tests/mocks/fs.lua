-- In-memory filesystem mimicking CC:T fs API.
local M = {}
local files = {}
local open_handles = {}

function M._reset() files = {}; open_handles = {} end
function M._snapshot() local s = {}; for k,v in pairs(files) do s[k] = v end; return s end
function M._inject(path, contents) files[path] = contents end
function M._exists_raw(path) return files[path] ~= nil end

function M.exists(path) return files[path] ~= nil end

function M.open(path, mode)
  if mode == "r" then
    local c = files[path]
    if not c then return nil end
    local pos = 1
    return {
      readAll = function() return c end,
      readLine = function()
        if pos > #c then return nil end
        local nl = c:find("\n", pos, true)
        local line
        if nl then line = c:sub(pos, nl-1); pos = nl+1
        else line = c:sub(pos); pos = #c+1 end
        return line
      end,
      close = function() end,
    }
  elseif mode == "w" then
    local buf = {}
    local h = {
      write = function(s) table.insert(buf, tostring(s)) end,
      writeLine = function(s) table.insert(buf, tostring(s) .. "\n") end,
      close = function() files[path] = table.concat(buf) end,
    }
    return h
  else
    error("mock fs: unsupported mode " .. tostring(mode))
  end
end

function M.delete(path) files[path] = nil end

function M.move(from, to)
  if not files[from] then error("mock fs.move: source missing: " .. from) end
  files[to] = files[from]
  files[from] = nil
end

function M.makeDir(_) end

function M.list(prefix)
  local out = {}
  for k, _ in pairs(files) do
    local p = k:match("^" .. prefix:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1") .. "/([^/]+)$")
    if p then table.insert(out, p) end
  end
  table.sort(out)
  return out
end

return M
