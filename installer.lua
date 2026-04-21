-- Installs the modular mining turtle onto this CC:Tweaked turtle.
-- Usage: wget run https://raw.githubusercontent.com/Tid0s19/turtle/main/installer.lua

local BASE = "https://raw.githubusercontent.com/Tid0s19/turtle/main/"

local FILES = {
  "mine",
  "lib/util.lua",
  "lib/logger.lua",
  "lib/config.lua",
  "lib/state.lua",
  "lib/movement.lua",
  "lib/inventory.lua",
  "lib/navigator.lua",
  "lib/strategy_loader.lua",
  "lib/ui.lua",
  "lib/main.lua",
  "strategies/quarry.lua",
  "strategies/strip.lua",
  "strategies/branch.lua",
}

print("Downloading Mining Turtle (" .. #FILES .. " files)...")

for _, path in ipairs(FILES) do
  local url = BASE .. path .. "?cachebust=" .. tostring(os.epoch("utc"))
  local resp, err = http.get(url)
  if not resp then
    printError("  FAIL  " .. path .. "  (" .. tostring(err) .. ")")
    return
  end
  local body = resp.readAll()
  resp.close()

  local dir = path:match("(.+)/[^/]+$")
  if dir and not fs.exists(dir) then fs.makeDir(dir) end
  if fs.exists(path) then fs.delete(path) end
  local h = fs.open(path, "w")
  h.write(body)
  h.close()
  print("  " .. path)
end

print("")
print("Installed. Run with: mine")
