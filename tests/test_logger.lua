package.path = "./?.lua;./lib/?.lua;" .. package.path
local t = require("tests.runner")

_G.fs = require("tests.mocks.fs")
_G.os.epoch = function(_) return 1713648063000 end

local logger = require("lib.logger")

local function reset()
  _G.fs._reset()
  logger.configure({ level = "info", file_path = "/logs/run.log" })
end

t.describe("logger levels", function()
  t.it("suppresses messages below configured level", function()
    reset()
    local captured = {}
    logger.addSink(function(e) table.insert(captured, e) end)
    logger.configure({ level = "warn" })
    logger.info("nope")
    logger.warn("yes")
    t.assert_eq(#captured, 1)
    t.assert_eq(captured[1].level, "warn")
  end)
  t.it("emits info/warn/error at info level", function()
    reset()
    local count = 0
    logger.addSink(function() count = count + 1 end)
    logger.debug("x") logger.info("y") logger.warn("z") logger.error("w")
    t.assert_eq(count, 3)
  end)
end)

t.describe("logger file sink", function()
  t.it("appends timestamped lines to file", function()
    reset()
    logger.info("hello world")
    local contents = _G.fs.open("/logs/run.log", "r").readAll()
    t.assert_true(contents:match("hello world") ~= nil)
    t.assert_true(contents:match("INFO") ~= nil)
  end)
end)

t.describe("logger.addSink", function()
  t.it("forwards events to all registered sinks", function()
    reset()
    local a, b = {}, {}
    logger.addSink(function(e) table.insert(a, e.msg) end)
    logger.addSink(function(e) table.insert(b, e.msg) end)
    logger.info("fan")
    t.assert_eq(a[1], "fan")
    t.assert_eq(b[1], "fan")
  end)
end)
