-- =============================================
--  CC Tweaked Area Tool v1.0
--  Excavation & Fill utility for turtles
--
--  Marker blocks: CC cable / wired modem
--  Place 2 markers to define a rectangle,
--  then excavate or fill the area.
-- =============================================

-------------------------------------------------
-- Configuration
-------------------------------------------------
local MARKER_BLOCKS = {
    ["computercraft:cable"]           = true,
    ["computercraft:wired_modem"]     = true,
    ["computercraft:wired_modem_full"] = true,
}
local MAX_SCAN = 64

-- Blocks the turtle will break during fill mode
local BREAKABLE = {
    "short_grass", "tall_grass", "grass", "fern", "large_fern",
    "flower", "poppy", "dandelion", "rose_bush", "tulip",
    "orchid", "cornflower", "lily_of_the_valley", "lily_pad",
    "azure_bluet", "allium", "oxeye_daisy", "sunflower",
    "lilac", "peony", "wither_rose", "blue_orchid",
    "mushroom", "dead_bush", "seagrass", "kelp",
    "azalea", "moss_carpet", "glow_lichen", "spore_blossom",
    "hanging_roots", "cave_vines", "dripleaf", "moss_block",
    "vine", "sugar_cane", "bamboo", "cactus", "sweet_berry",
    "pitcher_plant", "torchflower",
    "log", "wood", "stem", "stripped", "bark",
    "mangrove_roots", "leaves",
    "torch", "wall_torch", "soul_torch",
    "lantern", "soul_lantern",
    "campfire", "soul_campfire",
    "sapling", "propagule",
    "wheat", "carrots", "potatoes", "beetroots",
    "melon_stem", "pumpkin_stem", "attached",
    "cobweb", "web",
}

-------------------------------------------------
-- Terminal helpers
-------------------------------------------------
local W, H = term.getSize()
local isAdv = term.isColor()

local function setCol(fg, bg)
    if isAdv then
        if fg then term.setTextColor(fg) end
        if bg then term.setBackgroundColor(bg) end
    end
end

local function cls()
    setCol(colors.white, colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function center(y, text, fg, bg)
    local x = math.max(1, math.floor((W - #text) / 2) + 1)
    term.setCursorPos(x, y)
    setCol(fg, bg)
    term.write(text)
end

local function header(title)
    if isAdv then
        setCol(colors.white, colors.blue)
        term.setCursorPos(1, 1)
        term.write(string.rep(" ", W))
        center(1, title, colors.white, colors.blue)
    else
        center(1, "=== " .. title .. " ===")
    end
    setCol(colors.white, colors.black)
end

local function at(x, y, text, fg)
    term.setCursorPos(x, y)
    setCol(fg or colors.white, colors.black)
    term.write(text)
end

local function drawBar(y, pct)
    pct = math.min(100, math.max(0, pct))
    local bw = W - 6
    local f = math.floor(bw * pct / 100)
    term.setCursorPos(3, y)
    if isAdv then
        setCol(colors.white, colors.green)
        term.write(string.rep(" ", f))
        setCol(colors.white, colors.gray)
        term.write(string.rep(" ", bw - f))
    else
        term.write("[" .. string.rep("#", f)
            .. string.rep("-", bw - f) .. "]")
    end
    setCol(colors.white, colors.black)
end

local function readNum(y, label)
    while true do
        at(2, y, string.rep(" ", W - 2))
        at(2, y, label, colors.yellow)
        setCol(colors.white, colors.black)
        local s = read()
        local n = tonumber(s)
        if n and n > 0 and n == math.floor(n) then
            return n
        end
        at(2, y, string.rep(" ", W - 2))
        at(2, y, "Enter a positive integer!", colors.red)
        sleep(1.5)
    end
end

local function choice(y, max)
    while true do
        at(2, y, string.rep(" ", W - 2))
        at(2, y, "Select: ", colors.cyan)
        setCol(colors.white, colors.black)
        local s = read()
        local n = tonumber(s)
        if n and n >= 1 and n <= max then return n end
    end
end

local function anyKey(y)
    at(2, y or H, "Press any key...", colors.gray)
    os.pullEvent("key")
end

-------------------------------------------------
-- Block detection
-------------------------------------------------
local function matches(name, patterns)
    local lower = string.lower(name)
    for _, p in ipairs(patterns) do
        if string.find(lower, p, 1, true) then
            return true
        end
    end
    return false
end

local function isMarker(name)
    return MARKER_BLOCKS[name] == true
end

local function isBreakable(name)
    return matches(name, BREAKABLE)
end

-------------------------------------------------
-- Navigation
-------------------------------------------------
local pos = { x = 0, y = 0, z = 0 }
local dir = 0 -- 0=+Z(fwd) 1=+X(right) 2=-Z(back) 3=-X(left)

local DX = { [0] = 0, [1] = 1,  [2] = 0, [3] = -1 }
local DZ = { [0] = 1, [1] = 0,  [2] = -1, [3] = 0 }

local function turnR() turtle.turnRight(); dir = (dir + 1) % 4 end
local function turnL() turtle.turnLeft();  dir = (dir + 3) % 4 end

local function face(d)
    local diff = (d - dir) % 4
    if diff == 1 then turnR()
    elseif diff == 2 then turnR(); turnR()
    elseif diff == 3 then turnL() end
end

local function fwd()
    for _ = 1, 40 do
        if turtle.forward() then
            pos.x = pos.x + DX[dir]
            pos.z = pos.z + DZ[dir]
            return true
        end
        turtle.dig(); turtle.attack(); sleep(0.05)
    end
    return false
end

local function up()
    for _ = 1, 40 do
        if turtle.up() then
            pos.y = pos.y + 1; return true
        end
        turtle.digUp(); turtle.attackUp(); sleep(0.05)
    end
    return false
end

local function dn()
    for _ = 1, 40 do
        if turtle.down() then
            pos.y = pos.y - 1; return true
        end
        turtle.digDown(); turtle.attackDown(); sleep(0.05)
    end
    return false
end

local function goTo(tx, ty, tz)
    -- Y first
    while pos.y < ty do if not up() then return false end end
    while pos.y > ty do if not dn() then return false end end
    -- X
    if pos.x ~= tx then
        face(tx > pos.x and 1 or 3)
        while pos.x ~= tx do if not fwd() then return false end end
    end
    -- Z
    if pos.z ~= tz then
        face(tz > pos.z and 0 or 2)
        while pos.z ~= tz do if not fwd() then return false end end
    end
    return true
end

--- Navigate via the surface (Y=0) to avoid filled/unfilled columns
local function goViaSurface(tx, ty, tz)
    goTo(pos.x, 0, pos.z) -- ascend at current column
    goTo(tx, 0, tz)        -- horizontal at surface
    goTo(tx, ty, tz)        -- descend at target column
end

local function goHome()
    goTo(pos.x, 0, pos.z)
    goTo(0, 0, 0)
    face(0)
end

-------------------------------------------------
-- Fuel helper
-------------------------------------------------
local function getFuel()
    local f = turtle.getFuelLevel()
    if f == "unlimited" then return math.huge end
    return f
end

local function fuelForReturn()
    return math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z) + 20
end

-------------------------------------------------
-- Scanning
-------------------------------------------------
local function scanAxis(d)
    face(d)
    for i = 1, MAX_SCAN do
        local ok, data = turtle.inspect()
        if ok and isMarker(data.name) then
            return i -- marker is i blocks ahead of start
        end
        if not fwd() then return nil end
    end
    return nil
end

-------------------------------------------------
-- Inventory helpers
-------------------------------------------------
local function invFull()
    for s = 1, 16 do
        if turtle.getItemCount(s) == 0 then return false end
    end
    return true
end

local function selectFillBlock(reg)
    for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d and reg[d.name] then
            turtle.select(s)
            return true
        end
    end
    return false
end

local function registerChestBlocks()
    face(2) -- face chest behind start
    local reg = {}
    local total = 0
    -- Pull items out to inspect them
    for s = 1, 16 do
        turtle.select(s)
        if not turtle.suck() then break end
    end
    -- Record types + counts
    for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d then
            reg[d.name] = (reg[d.name] or 0) + d.count
            total = total + d.count
        end
    end
    -- Put everything back
    for s = 1, 16 do
        turtle.select(s)
        turtle.drop()
    end
    turtle.select(1)
    face(0)
    return reg, total
end

local function loadFromChest(reg)
    face(2)
    -- Drop non-fill items first (torches, plant drops, etc.)
    for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d and not reg[d.name] then
            turtle.select(s)
            turtle.drop()
        end
    end
    -- Fill inventory with fill blocks
    for s = 1, 16 do
        if turtle.getItemCount(s) == 0 then
            turtle.select(s)
            if not turtle.suck() then break end
        end
    end
    turtle.select(1)
    face(0)
end

local function dumpToChest()
    face(2)
    for s = 1, 16 do
        turtle.select(s)
        turtle.drop()
    end
    turtle.select(1)
    face(0)
end

-------------------------------------------------
-- Progress display
-------------------------------------------------
local prog = {}

local function showProgress()
    cls()
    header(prog.mode == "excavate" and "EXCAVATING" or "FILLING")
    local pct = prog.total > 0
        and math.floor(prog.done / prog.total * 100) or 0
    at(2, 3, prog.mode == "excavate"
        and "Excavating area..." or "Filling area...", colors.white)
    at(2, 4, "Progress: " .. pct .. "%", colors.yellow)
    drawBar(5, pct)
    if prog.mode == "excavate" then
        at(2, 7, "Layer: " .. prog.layer .. "/" .. prog.depth,
            colors.lightGray)
    end
    at(2, 8, "Columns: " .. prog.done .. "/" .. prog.total,
        colors.lightGray)
    at(2, 9, "Blocks: " .. prog.blocks, colors.lightGray)
    at(2, 10, "Fuel:   " .. getFuel(), colors.lightGray)
end

local lastTick = 0
local function tick()
    local t = os.clock()
    if t - lastTick >= 0.5 then
        showProgress()
        lastTick = t
    end
end

-------------------------------------------------
-- Excavation
-------------------------------------------------
local function doExcavate(width, length, depth)
    local fuelStart = getFuel()
    prog = {
        mode   = "excavate",
        done   = 0,
        total  = width * length,
        blocks = 0,
        layer  = 0,
        depth  = depth,
    }
    showProgress()

    for layer = 1, depth do
        prog.layer = layer
        prog.done  = 0
        showProgress()

        for x = 0, width - 1 do
            local zStart, zEnd, zStep
            if x % 2 == 0 then
                zStart, zEnd, zStep = 0, length - 1, 1
            else
                zStart, zEnd, zStep = length - 1, 0, -1
            end
            for z = zStart, zEnd, zStep do
                -- Fuel safety check
                if getFuel() < fuelForReturn() then
                    goHome()
                    return false, "Low fuel - returned home"
                end

                goTo(x, -layer, z)
                prog.done   = prog.done + 1
                prog.blocks = prog.blocks + 1
                tick()

                -- Dump inventory when full
                if invFull() then
                    local cx, cy, cz, cd = pos.x, pos.y, pos.z, dir
                    goHome()
                    dumpToChest()
                    goViaSurface(cx, cy, cz)
                    face(cd)
                end
            end
        end
    end

    -- Return home & dump remaining
    goHome()
    dumpToChest()
    prog.done = prog.total
    showProgress()
    return true, getFuel() ~= math.huge
        and (fuelStart - getFuel()) or 0
end

-------------------------------------------------
-- Fill
-------------------------------------------------
local function doFill(width, length, reg)
    local fuelStart = getFuel()
    prog = {
        mode   = "fill",
        done   = 0,
        total  = width * length,
        blocks = 0,
        layer  = 0,
        depth  = 0,
    }

    -- Load initial inventory
    goHome()
    loadFromChest(reg)
    showProgress()

    -- Resupply: save pos, go to chest, reload, return
    local function resupply()
        local cx, cy, cz, cd = pos.x, pos.y, pos.z, dir
        goViaSurface(0, 0, 0)
        face(0)
        loadFromChest(reg)
        goViaSurface(cx, cy, cz)
        face(cd)
    end

    for x = 0, width - 1 do
        local zStart, zEnd, zStep
        if x % 2 == 0 then
            zStart, zEnd, zStep = 0, length - 1, 1
        else
            zStart, zEnd, zStep = length - 1, 0, -1
        end

        for z = zStart, zEnd, zStep do
            if getFuel() < fuelForReturn() then
                goHome()
                dumpToChest()
                return false, "Low fuel - returned home"
            end

            goTo(x, 0, z)
            local startY = pos.y -- should be 0

            -- Check below: solid non-breakable = skip
            local bok, bdata = turtle.inspectDown()
            if not bok or isBreakable(bdata.name) then
                -- ---- Descend into hole ----
                while true do
                    local ok2, d2 = turtle.inspectDown()
                    if ok2 then
                        if isBreakable(d2.name) then
                            turtle.digDown()
                        else
                            break -- solid ground
                        end
                    end
                    if not dn() then break end
                    if pos.y < -256 then break end
                end

                -- ---- Ascend & fill ----
                while pos.y < startY do
                    if not selectFillBlock(reg) then
                        resupply()
                        if not selectFillBlock(reg) then
                            -- Chest empty, abort
                            goHome()
                            dumpToChest()
                            prog.done = prog.done + 1
                            showProgress()
                            return false, "Out of fill blocks"
                        end
                    end
                    up()
                    -- Re-select after moving (digUp may shift items)
                    if selectFillBlock(reg) then
                        turtle.placeDown()
                        prog.blocks = prog.blocks + 1
                    end
                end
            end

            prog.done = prog.done + 1
            tick()
        end
    end

    -- Return home & dump leftovers / collected items
    goHome()
    dumpToChest()
    prog.done = prog.total
    showProgress()
    return true, getFuel() ~= math.huge
        and (fuelStart - getFuel()) or 0
end

-------------------------------------------------
-- Help screens
-------------------------------------------------
local helpPages = {
    {
        title = "SETUP",
        lines = {
            "1. Place turtle at one corner",
            "   facing along the LENGTH.",
            "",
            "2. Place a CC cable/modem on",
            "   the ground at the far end",
            "   of the FORWARD edge.",
            "",
            "3. Place a CC cable/modem on",
            "   the ground at the far end",
            "   of the RIGHT edge.",
        },
    },
    {
        title = "MARKER DIAGRAM",
        lines = {
            "  Top-down view:",
            "",
            "    [F].............",
            "     .             .",
            "     .    AREA     .",
            "     .             .",
            "    [T].........[R]",
            "",
            "  T = Turtle (facing up)",
            "  F = Forward marker",
            "  R = Right marker",
        },
    },
    {
        title = "EXCAVATE MODE",
        lines = {
            "Digs a rectangular area down",
            "to a specified depth.",
            "",
            "Mined items are dumped into a",
            "chest behind the turtle (or",
            "on the ground if no chest).",
            "",
            "The turtle returns home when",
            "inventory is full to dump,",
            "then continues working.",
        },
    },
    {
        title = "FILL MODE",
        lines = {
            "Fills gaps/holes in the area",
            "using blocks from the chest.",
            "",
            "REQUIRES a chest behind the",
            "turtle stocked with blocks.",
            "",
            "Breaks plants, logs, torches.",
            "Torches returned to chest.",
            "Fills bottom-up per column",
            "so blocks have support.",
        },
    },
}

local function showHelp()
    local page = 1
    while true do
        cls()
        header("HELP " .. page .. "/" .. #helpPages
            .. " - " .. helpPages[page].title)
        for i, line in ipairs(helpPages[page].lines) do
            at(2, i + 2, line, colors.white)
        end
        at(2, H, "[Q]Back [<]Prev [>]Next", colors.gray)

        local _, key = os.pullEvent("key")
        if key == keys.q or key == keys.backspace then
            return
        elseif (key == keys.right or key == keys.enter)
            and page < #helpPages then
            page = page + 1
        elseif key == keys.left and page > 1 then
            page = page - 1
        end
    end
end

-------------------------------------------------
-- Area definition
-------------------------------------------------
local function defineArea()
    cls()
    header("DEFINE AREA")
    at(2, 3, "[1] Scan for markers", colors.white)
    at(2, 4, "[2] Enter manually", colors.white)
    at(2, 6, "Markers: CC cable / modem", colors.gray)
    at(2, 7, "1 ahead + 1 to the right", colors.gray)

    local c = choice(H - 1, 2)

    if c == 1 then
        -- --- Scan mode ---
        cls()
        header("SCANNING")
        at(2, 3, "Scanning forward...", colors.yellow)

        local fDist = scanAxis(0)
        if fDist then
            at(2, 4, "Length: " .. (fDist + 1) .. " blocks",
                colors.green)
        else
            at(2, 4, "No forward marker found!", colors.red)
            goHome(); anyKey(H); return nil
        end
        goHome()

        at(2, 6, "Scanning right...", colors.yellow)
        local rDist = scanAxis(1)
        if rDist then
            at(2, 7, "Width:  " .. (rDist + 1) .. " blocks",
                colors.green)
        else
            at(2, 7, "No right marker found!", colors.red)
            goHome(); anyKey(H); return nil
        end
        goHome()

        local area = { length = fDist + 1, width = rDist + 1 }
        at(2, 9, "Area: " .. area.length .. "x" .. area.width
            .. " (" .. (area.length * area.width) .. " cols)",
            colors.white)
        anyKey(H)
        return area
    else
        -- --- Manual mode ---
        cls()
        header("MANUAL AREA")
        local length = readNum(3, "Length (forward): ")
        local width  = readNum(4, "Width  (right):   ")
        at(2, 6, "Area: " .. length .. "x" .. width
            .. " (" .. (length * width) .. " cols)", colors.white)
        anyKey(H)
        return { length = length, width = width }
    end
end

-------------------------------------------------
-- Excavate setup
-------------------------------------------------
local function excavateSetup()
    local area = defineArea()
    if not area then return end

    cls()
    header("EXCAVATE")
    at(2, 3, "Area:  " .. area.length .. " x " .. area.width,
        colors.white)
    local depth = readNum(4, "Depth: ")

    local total = area.length * area.width * depth
    local est   = math.ceil(total * 1.5
        + area.width + area.length + depth + 50)
    local fuel  = getFuel()

    at(2, 6, "Blocks:     " .. total, colors.lightGray)
    at(2, 7, "Est. fuel:  ~" .. est, colors.lightGray)
    at(2, 8, "Your fuel:  " .. (fuel == math.huge
        and "unlimited" or fuel),
        fuel >= est and colors.green or colors.red)
    if fuel < est and fuel ~= math.huge then
        at(2, 9, "WARNING: may not have enough fuel",
            colors.red)
    end

    at(2, 11, "[1] Start  [2] Cancel", colors.white)
    if choice(H - 1, 2) == 2 then return end

    local ok, info = doExcavate(area.width, area.length, depth)

    cls()
    header("COMPLETE")
    if ok then
        at(2, 3, "Excavation finished!", colors.green)
    else
        at(2, 3, "Stopped: " .. tostring(info), colors.red)
    end
    at(2, 5, "Blocks dug:  " .. prog.blocks, colors.white)
    if type(info) == "number" then
        at(2, 6, "Fuel used:   " .. info, colors.white)
    end
    anyKey(H)
end

-------------------------------------------------
-- Fill setup
-------------------------------------------------
local function fillSetup()
    local area = defineArea()
    if not area then return end

    cls()
    header("FILL")
    at(2, 3, "Area: " .. area.length .. " x " .. area.width,
        colors.white)

    -- Check for chest behind turtle
    goHome()
    face(2)
    local cOk, cData = turtle.inspect()
    face(0)
    local hasChest = cOk and (
        string.find(cData.name, "chest")
        or string.find(cData.name, "barrel")
        or string.find(cData.name, "shulker")
    )

    if not hasChest then
        at(2, 5, "No chest behind turtle!", colors.red)
        at(2, 6, "Place a chest with fill", colors.yellow)
        at(2, 7, "blocks behind the turtle.", colors.yellow)
        anyKey(H)
        return
    end

    at(2, 5, "Chest: Found", colors.green)

    -- Register block types in chest
    local reg, totalCount = registerChestBlocks()
    local y = 6
    at(2, y, "Fill blocks:", colors.white); y = y + 1
    for name, count in pairs(reg) do
        if y >= H - 3 then
            at(3, y, "...", colors.lightGray)
            break
        end
        local short = string.gsub(name, "^%w+:", "")
        at(3, y, "- " .. short .. " (" .. count .. ")",
            colors.lightGray)
        y = y + 1
    end

    if totalCount == 0 then
        at(2, y, "Chest is empty!", colors.red)
        anyKey(H)
        return
    end

    at(2, H - 2, "[1] Start  [2] Cancel", colors.white)
    if choice(H - 1, 2) == 2 then return end

    local ok, info = doFill(area.width, area.length, reg)

    cls()
    header("COMPLETE")
    if ok then
        at(2, 3, "Fill finished!", colors.green)
    else
        at(2, 3, "Stopped: " .. tostring(info), colors.red)
    end
    at(2, 5, "Blocks placed: " .. prog.blocks, colors.white)
    if type(info) == "number" then
        at(2, 6, "Fuel used:     " .. info, colors.white)
    end
    anyKey(H)
end

-------------------------------------------------
-- Main menu
-------------------------------------------------
local function main()
    while true do
        cls()
        header("AREA TOOL v1.0")
        at(2, 3, "[1] Excavate", colors.white)
        at(2, 4, "[2] Fill", colors.white)
        at(2, 5, "[3] Help", colors.white)
        at(2, 6, "[4] Exit", colors.white)

        local fuel = getFuel()
        at(2, 8, "Fuel: " .. (fuel == math.huge
            and "unlimited" or tostring(fuel)), colors.yellow)

        local c = choice(H - 1, 4)
        if     c == 1 then excavateSetup()
        elseif c == 2 then fillSetup()
        elseif c == 3 then showHelp()
        elseif c == 4 then cls(); return
        end
    end
end

-- Entry point
main()
