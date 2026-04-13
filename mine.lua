-- mine.lua - Column miner to bedrock
-- Usage: mine <size> or mine <width> <length>
-- Place a chest behind the turtle before starting.
-- The turtle mines forward and to the right in a serpentine pattern,
-- mining each column straight down to bedrock.

local args = {...}

local width, length

if #args == 1 then
    local size = tonumber(args[1])
    if not size or size < 1 then
        print("Size must be a positive integer")
        return
    end
    width = math.floor(size)
    length = width
elseif #args == 2 then
    width = tonumber(args[1])
    length = tonumber(args[2])
    if not width or not length or width < 1 or length < 1 then
        print("Width and length must be positive integers")
        return
    end
    width = math.floor(width)
    length = math.floor(length)
else
    print("Usage: mine <size>")
    print("       mine <width> <length>")
    print("Place a chest behind the turtle.")
    return
end

-- Position tracking (relative to starting position)
local posX, posY, posZ = 0, 0, 0
local facing = 0 -- 0=forward(+Z), 1=right(+X), 2=back(-Z), 3=left(-X)

local DX = {[0] = 0, [1] = 1, [2] = 0, [3] = -1}
local DZ = {[0] = 1, [1] = 0, [2] = -1, [3] = 0}

local totalColumns = width * length
local columnsDone = 0

-- ============ Turning ============

local function turnLeft()
    turtle.turnLeft()
    facing = (facing + 3) % 4
end

local function turnRight()
    turtle.turnRight()
    facing = (facing + 1) % 4
end

local function face(dir)
    local diff = (dir - facing) % 4
    if diff == 1 then turnRight()
    elseif diff == 2 then turnRight(); turnRight()
    elseif diff == 3 then turnLeft()
    end
end

-- ============ Block detection ============

local function isLava(inspectFn)
    local ok, data = inspectFn()
    return ok and data.name == "minecraft:lava"
end

local function isBedrock(inspectFn)
    local ok, data = inspectFn()
    return ok and data.name == "minecraft:bedrock"
end

local BUILD_BLOCKS = {
    ["minecraft:cobblestone"] = true,
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:stone"] = true,
    ["minecraft:deepslate"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:netherrack"] = true,
    ["minecraft:tuff"] = true,
    ["minecraft:granite"] = true,
    ["minecraft:diorite"] = true,
    ["minecraft:andesite"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:sand"] = true,
}

local function findBuildSlot()
    for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and BUILD_BLOCKS[d.name] then
            return i
        end
    end
    return nil
end

local function placeSeal(placeFn)
    local slot = findBuildSlot()
    if slot then
        turtle.select(slot)
        placeFn()
        turtle.select(1)
        return true
    end
    return false
end

-- ============ Movement ============

local function forceForward()
    local attempts = 0
    while not turtle.forward() do
        attempts = attempts + 1
        if attempts > 30 then return false end
        if isLava(turtle.inspect) then placeSeal(turtle.place) end
        turtle.dig()
        sleep(0.3)
    end
    posX = posX + DX[facing]
    posZ = posZ + DZ[facing]
    return true
end

local function forceUp()
    local attempts = 0
    while not turtle.up() do
        attempts = attempts + 1
        if attempts > 30 then return false end
        if isLava(turtle.inspectUp) then placeSeal(turtle.placeUp) end
        turtle.digUp()
        sleep(0.3)
    end
    posY = posY + 1
    return true
end

local function forceDown()
    local attempts = 0
    while not turtle.down() do
        attempts = attempts + 1
        if attempts > 30 then return false end
        if isBedrock(turtle.inspectDown) then return false end
        if isLava(turtle.inspectDown) then
            if not placeSeal(turtle.placeDown) then return false end
        end
        turtle.digDown()
        sleep(0.3)
    end
    posY = posY - 1
    return true
end

local function goTo(tx, ty, tz)
    while posY < ty do
        if not forceUp() then break end
    end
    while posY > ty do
        if not forceDown() then break end
    end
    if posX ~= tx then
        face(posX < tx and 1 or 3)
        while posX ~= tx do
            if not forceForward() then break end
        end
    end
    if posZ ~= tz then
        face(posZ < tz and 0 or 2)
        while posZ ~= tz do
            if not forceForward() then break end
        end
    end
end

-- ============ Lava sealing ============

local function sealLavaSides()
    for i = 1, 4 do
        if isLava(turtle.inspect) then
            placeSeal(turtle.place)
        end
        turnRight()
    end
    if isLava(turtle.inspectUp) then
        placeSeal(turtle.placeUp)
    end
end

-- ============ Fuel management ============

local function refuel()
    if turtle.getFuelLevel() == "unlimited" then return end
    for i = 1, 16 do
        if turtle.getFuelLevel() > 2000 then return end
        turtle.select(i)
        turtle.refuel()
    end
    turtle.select(1)
end

local function fuelOk(extra)
    if turtle.getFuelLevel() == "unlimited" then return true end
    local needed = math.abs(posX) + math.abs(posZ) + math.abs(posY) + (extra or 100)
    return turtle.getFuelLevel() >= needed
end

-- ============ Inventory management ============

local function inventoryFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then return false end
    end
    return true
end

local function goHomeAndDump()
    goTo(0, 0, 0)
    face(2) -- face backward toward chest
    refuel()
    local keptSlot = findBuildSlot()
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 and i ~= keptSlot then
            turtle.select(i)
            if not turtle.drop() then
                print("Chest full! Waiting...")
                while not turtle.drop() do sleep(5) end
            end
        end
    end
    turtle.select(1)
end

-- ============ Column mining ============

local function mineColumn()
    while true do
        if isBedrock(turtle.inspectDown) then break end
        if not forceDown() then break end

        sealLavaSides()

        if inventoryFull() then
            local savedY, savedX, savedZ = posY, posX, posZ
            while posY < 0 do
                if not forceUp() then break end
            end
            goHomeAndDump()
            goTo(savedX, 0, savedZ)
            while posY > savedY do
                if not forceDown() then break end
            end
        end

        if not fuelOk(100) then
            refuel()
            if not fuelOk(50) then
                print("Low fuel, aborting column")
                break
            end
        end
    end

    while posY < 0 do
        if not forceUp() then break end
    end
end

-- ============ Main ============

term.clear()
term.setCursorPos(1, 1)
print("Column Miner: " .. width .. "x" .. length .. " to bedrock")
print("Fuel: " .. tostring(turtle.getFuelLevel()))
refuel()

if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 100 then
    print("Need more fuel! Add fuel items to inventory.")
    return
end

print("Starting...")

for col = 0, width - 1 do
    local goForward = (col % 2 == 0)
    for row = 0, length - 1 do
        local z = goForward and row or (length - 1 - row)

        goTo(col, 0, z)

        if not fuelOk(500) then
            refuel()
            if not fuelOk(200) then
                goHomeAndDump()
                refuel()
                if not fuelOk(200) then
                    print("Out of fuel at column " .. (columnsDone + 1))
                    print("Pos: " .. posX .. ", " .. posY .. ", " .. posZ)
                    return
                end
                goTo(col, 0, z)
            end
        end

        if inventoryFull() then
            refuel()
            goHomeAndDump()
            goTo(col, 0, z)
        end

        mineColumn()

        columnsDone = columnsDone + 1
        local pct = math.floor(columnsDone / totalColumns * 100)
        print("[" .. pct .. "%] Column " .. columnsDone .. "/" .. totalColumns)
    end
end

refuel()
goHomeAndDump()
face(0)
print("Done! Mined " .. totalColumns .. " columns to bedrock.")
