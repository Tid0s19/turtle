-- Aggregates every tests/test_*.lua file and runs them.
package.path = "./?.lua;./lib/?.lua;./tests/?.lua;" .. package.path

local runner = require("tests.runner")

local p = io.popen("ls tests/test_*.lua 2>/dev/null")
if p then
  for line in p:lines() do
    local mod = line:gsub("%.lua$", ""):gsub("/", ".")
    require(mod)
  end
  p:close()
end

runner.run()
