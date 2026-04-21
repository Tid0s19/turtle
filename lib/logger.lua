local M = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local config = { level = "info", file_path = "/logs/run.log", keep_runs = 5 }
local sinks = {}
local file_error_once = false

local function now()
  if os.epoch then return math.floor(os.epoch("utc") / 1000) end
  return os.time()
end

local function format_line(event)
  return string.format("[%d] %-5s %s",
    event.ts, event.level:upper(), event.msg)
end

local log_buffer = {}
local function buffered_file_sink(event)
  if file_error_once then return end
  table.insert(log_buffer, format_line(event))
  local ok, err = pcall(function()
    local h = fs.open(config.file_path, "w")
    if not h then error("open failed") end
    for _, line in ipairs(log_buffer) do h.writeLine(line) end
    h.close()
  end)
  if not ok then
    file_error_once = true
  end
end

local function terminal_sink(event)
  print(format_line(event))
end

function M.configure(cfg)
  config.level = cfg.level or config.level
  config.file_path = cfg.file_path or config.file_path
  config.keep_runs = cfg.keep_runs or config.keep_runs
  file_error_once = false
  log_buffer = {}
end

function M.addSink(fn) table.insert(sinks, fn) end

local function emit(level, msg, data)
  if LEVELS[level] < LEVELS[config.level] then return end
  local event = { level = level, ts = now(), msg = msg, data = data }
  for _, s in ipairs(sinks) do s(event) end
end

function M.debug(msg, data) emit("debug", msg, data) end
function M.info (msg, data) emit("info",  msg, data) end
function M.warn (msg, data) emit("warn",  msg, data) end
function M.error(msg, data) emit("error", msg, data) end

M._terminal_sink = terminal_sink

table.insert(sinks, buffered_file_sink)
M.configure(config)

return M
