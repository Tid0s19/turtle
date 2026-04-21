-- Minimal test runner. No external deps. Compatible with Lua 5.2+.
local M = {}

local tests = {}
local current_suite = nil

function M.describe(name, fn)
  current_suite = name
  fn()
  current_suite = nil
end

function M.it(name, fn)
  table.insert(tests, { suite = current_suite or "(no suite)", name = name, fn = fn })
end

function M.assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s",
      msg or "assert_eq",
      tostring(expected), tostring(actual)), 2)
  end
end

function M.assert_true(cond, msg)
  if not cond then error(msg or "expected truthy, got " .. tostring(cond), 2) end
end

function M.assert_false(cond, msg)
  if cond then error(msg or "expected falsy, got " .. tostring(cond), 2) end
end

function M.assert_nil(x, msg)
  if x ~= nil then error((msg or "expected nil") .. ", got " .. tostring(x), 2) end
end

function M.assert_deep_eq(a, b, msg)
  local function deq(x, y)
    if type(x) ~= type(y) then return false end
    if type(x) ~= "table" then return x == y end
    for k, v in pairs(x) do if not deq(v, y[k]) then return false end end
    for k, _ in pairs(y) do if x[k] == nil then return false end end
    return true
  end
  if not deq(a, b) then
    error((msg or "assert_deep_eq") ..
      " failed: " .. tostring(a) .. " vs " .. tostring(b), 2)
  end
end

function M.assert_error(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then error((msg or "expected error") .. " but none raised", 2) end
  if pattern and not tostring(err):match(pattern) then
    error(string.format("error did not match %q: got %q", pattern, tostring(err)), 2)
  end
end

function M.run()
  local passed, failed = 0, {}
  for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
      passed = passed + 1
      io.write("."); io.flush()
    else
      table.insert(failed, { suite = t.suite, name = t.name, err = err })
      io.write("F"); io.flush()
    end
  end
  io.write("\n\n")
  for _, f in ipairs(failed) do
    print(string.format("FAIL [%s] %s", f.suite, f.name))
    print("  " .. tostring(f.err))
  end
  print(string.format("\n%d passed, %d failed", passed, #failed))
  os.exit(#failed == 0 and 0 or 1)
end

return M
