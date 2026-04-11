-- ============================================================================
-- Turtle Excavate & Fill Tool
-- For CC Tweaked (Minecraft)
-- Place a chest behind the turtle before starting.
-- ============================================================================

-- ========================== Section 1: Config ===============================

local MARKER_BLOCKS = {
    ["computercraft:wired_modem"] = true,
    ["computercraft:cable"] = true,
    ["computercraft:wired_modem_full"] = true,
}

local REPLACEABLE_PATTERNS = {
    "flower", "fern", "sapling", "vine", "leaves", "log", "wood",
    "mushroom", "dead_bush", "tall_grass", "seagrass", "kelp", "bamboo",
    "azalea", "moss", "lichen", "dripleaf", "spore_blossom", "hanging_roots",
    "mangrove_roots", "sugar_cane", "cactus", "sweet_berry", "cave_vines",
    "glow_berries", "weeping_vines", "twisting_vines", "crimson_roots",
    "warped_roots", "nether_sprouts", "chorus_plant", "chorus_flower",
    "short_grass", "poppy", "dandelion", "blue_orchid", "allium",
    "azure_bluet", "tulip", "oxeye_daisy", "cornflower", "lily_of_the_valley",
    "wither_rose", "sunflower", "lilac", "rose_bush", "peony", "pitcher_plant",
    "torchflower", "pink_petals", "lily_pad", "snow", "cobweb",
}

local COLLECTIBLE_PATTERNS = {
    "torch",
}

local FUEL_WARNING = 500

-- ====================== Section 2: State & Movement =========================

local pos = { x = 0, y = 0, z = 0 }
local facing = 0 -- 0=north(+Z), 1=east(+X), 2=south(-Z), 3=west(-X)

local dx = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
local dz = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }

local function turnLeft()
    turtle.turnLeft()
    facing = (facing + 3) % 4
end

local function turnRight()
    turtle.turnRight()
    facing = (facing + 1) % 4
end

local function face(dir)
    dir = dir % 4
    while facing ~= dir do
        turnRight()
    end
end

local function forward()
    local tries = 0
    while not turtle.forward() do
        if turtle.detect() then
            turtle.dig()
        else
            turtle.attack()
        end
        tries = tries + 1
        if tries > 30 then
            return false
        end
        os.sleep(0.2)
    end
    pos.x = pos.x + dx[facing]
    pos.z = pos.z + dz[facing]
    return true
end

local function back()
    if turtle.back() then
        pos.x = pos.x - dx[facing]
        pos.z = pos.z - dz[facing]
        return true
    end
    turnRight()
    turnRight()
    local ok = forward()
    turnRight()
    turnRight()
    return ok
end

local function up()
    local tries = 0
    while not turtle.up() do
        if turtle.detectUp() then
            turtle.digUp()
        else
            turtle.attackUp()
        end
        tries = tries + 1
        if tries > 30 then
            return false
        end
        os.sleep(0.2)
    end
    pos.y = pos.y + 1
    return true
end

local function down()
    local tries = 0
    while not turtle.down() do
        if turtle.detectDown() then
            turtle.digDown()
        else
            turtle.attackDown()
        end
        tries = tries + 1
        if tries > 30 then
            return false
        end
        os.sleep(0.2)
    end
    pos.y = pos.y - 1
    return true
end

local function moveTo(tx, ty, tz)
    -- Move Y first (up before lateral, down after)
    if ty > pos.y then
        while pos.y < ty do up() end
    end
    -- Move X
    if tx > pos.x then
        face(1)
        while pos.x < tx do forward() end
    elseif tx < pos.x then
        face(3)
        while pos.x > tx do forward() end
    end
    -- Move Z
    if tz > pos.z then
        face(0)
        while pos.z < tz do forward() end
    elseif tz < pos.z then
        face(2)
        while pos.z > tz do forward() end
    end
    -- Move Y down after lateral
    if ty < pos.y then
        while pos.y > ty do down() end
    end
end

local function returnHome()
    moveTo(0, 0, 0)
    face(0)
end

-- ================== Section 3: Inventory & Fuel =============================

local function refuel()
    local fuelSlot = 16
    local prev = turtle.getSelectedSlot()
    turtle.select(fuelSlot)
    turtle.refuel()
    turtle.select(prev)
end

local function refuelFromChest()
    local sx, sy, sz, sf = pos.x, pos.y, pos.z, facing
    returnHome()
    face(2) -- face chest

    turtle.select(16)
    -- Use any fuel already in slot 16
    turtle.refuel()
    -- Drop leftovers (non-fuel) back to chest
    turtle.drop()

    -- Pull fuel from chest until we have enough
    while true do
        local level = turtle.getFuelLevel()
        if level == "unlimited" or level >= FUEL_WARNING then
            break
        end
        if not turtle.suck(1) then
            break -- chest empty
        end
        if turtle.refuel() then
            -- It was fuel, grab more of the same
            turtle.suck()
            turtle.refuel()
        else
            -- Not fuel, put it back
            turtle.drop()
        end
    end

    turtle.select(1)
    face(0)
    moveTo(sx, sy, sz)
    face(sf)
end

local function checkFuel(needed)
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return true end
    if level < needed then
        refuel()
        level = turtle.getFuelLevel()
    end
    if level < FUEL_WARNING then
        refuelFromChest()
        level = turtle.getFuelLevel()
    end
    return level >= FUEL_WARNING
end

local function isInventoryFull()
    for i = 1, 15 do
        if turtle.getItemCount(i) == 0 then
            return false
        end
    end
    return true
end

local function dumpToChest()
    local sx, sy, sz, sf = pos.x, pos.y, pos.z, facing
    returnHome()
    face(2) -- face backward (behind = south if we started facing north)
    for i = 1, 15 do
        turtle.select(i)
        turtle.drop()
    end
    turtle.select(1)
    face(0)
    moveTo(sx, sy, sz)
    face(sf)
end

local function loadFromChest()
    local sx, sy, sz, sf = pos.x, pos.y, pos.z, facing
    returnHome()
    face(2) -- face backward toward chest
    for i = 1, 15 do
        turtle.select(i)
        turtle.suck()
    end
    turtle.select(1)
    face(0)
    moveTo(sx, sy, sz)
    face(sf)
end

local function dumpAndLoad()
    local sx, sy, sz, sf = pos.x, pos.y, pos.z, facing
    returnHome()
    face(2)
    for i = 1, 15 do
        turtle.select(i)
        turtle.drop()
    end
    for i = 1, 15 do
        turtle.select(i)
        turtle.suck()
    end
    turtle.select(1)
    face(0)
    moveTo(sx, sy, sz)
    face(sf)
end

local function scanChest()
    -- Look at items in chest to register valid fill block types
    local validBlocks = {}
    local sx, sy, sz, sf = pos.x, pos.y, pos.z, facing
    returnHome()
    face(2)
    -- Suck one item at a time to identify types
    for i = 1, 15 do
        turtle.select(i)
        if turtle.suck(1) then
            local detail = turtle.getItemDetail()
            if detail then
                validBlocks[detail.name] = true
            end
            turtle.drop()
        end
    end
    turtle.select(1)
    face(0)
    moveTo(sx, sy, sz)
    face(sf)
    return validBlocks
end

local function getFillBlockCount(validBlocks)
    local count = 0
    for i = 1, 15 do
        local detail = turtle.getItemDetail(i)
        if detail and validBlocks[detail.name] then
            count = count + turtle.getItemCount(i)
        end
    end
    return count
end

local function selectFillBlock(validBlocks)
    for i = 1, 15 do
        local detail = turtle.getItemDetail(i)
        if detail and validBlocks[detail.name] and turtle.getItemCount(i) > 0 then
            turtle.select(i)
            return true
        end
    end
    return false
end

-- ================== Section 4: Block Classification =========================

local function isMarker(blockData)
    if not blockData or not blockData.name then return false end
    return MARKER_BLOCKS[blockData.name] == true
end

local function matchesAny(name, patterns)
    for _, pat in ipairs(patterns) do
        if string.find(name, pat, 1, true) then
            return true
        end
    end
    return false
end

local function isReplaceable(blockData)
    if not blockData or not blockData.name then return false end
    return matchesAny(blockData.name, REPLACEABLE_PATTERNS)
end

local function isCollectible(blockData)
    if not blockData or not blockData.name then return false end
    return matchesAny(blockData.name, COLLECTIBLE_PATTERNS)
end

local function isSolidGround(blockData)
    if not blockData or not blockData.name then return false end
    if blockData.name == "minecraft:air" then return false end
    if isReplaceable(blockData) then return false end
    if isCollectible(blockData) then return false end
    if isMarker(blockData) then return false end
    return true
end

-- =================== Section 5: Area Definition =============================

-- Key for coordinate pairs
local function posKey(x, z)
    return x .. "," .. z
end

-- ---- Rectangle Mode ----

local function scanRectangle()
    -- Move forward until we find a marker (that's the length)
    local length = 0
    while true do
        local ok, data = turtle.inspect()
        if ok and isMarker(data) then
            break
        end
        forward()
        length = length + 1
        if length > 256 then
            return nil, nil, "No marker found within 256 blocks"
        end
    end

    -- Turn right and scan for width marker
    turnRight()
    local width = 0
    while true do
        local ok, data = turtle.inspect()
        if ok and isMarker(data) then
            break
        end
        forward()
        width = width + 1
        if width > 256 then
            -- Go back home
            returnHome()
            return length, nil, "No width marker found within 256 blocks"
        end
    end

    -- Return home
    returnHome()
    return length, width, nil
end

local function buildRectArea(length, width)
    local area = {}
    local workOrder = {}
    for z = 1, length do
        if z % 2 == 1 then
            for x = 0, width - 1 do
                local key = posKey(x, z)
                area[key] = true
                table.insert(workOrder, { x = x, z = z })
            end
        else
            for x = width - 1, 0, -1 do
                local key = posKey(x, z)
                area[key] = true
                table.insert(workOrder, { x = x, z = z })
            end
        end
    end
    return area, workOrder, length * width
end

-- ---- Custom Shape Mode ----

local function tracePerimeter()
    -- Step 1: Move forward until we hit a marker block
    local startX, startZ, startFacing
    local found = false
    for i = 1, 256 do
        local ok, data = turtle.inspect()
        if ok and isMarker(data) then
            found = true
            break
        end
        forward()
    end
    if not found then
        return nil, "No marker block found within 256 blocks"
    end

    -- The block in front is a marker. Record it.
    local markers = {}
    local markerSet = {}

    local function recordMarkerInFront()
        local mx = pos.x + dx[facing]
        local mz = pos.z + dz[facing]
        local key = posKey(mx, mz)
        if not markerSet[key] then
            markerSet[key] = true
            table.insert(markers, { x = mx, z = mz })
        end
    end

    recordMarkerInFront()
    startX = pos.x
    startZ = pos.z
    startFacing = facing

    -- Step 2: Wall-following — keep the marker wall on the right
    -- We are facing the wall. Turn left so wall is on our right.
    turnLeft()

    local steps = 0
    local maxSteps = 10000

    while steps < maxSteps do
        -- Check right: is there a marker to the right?
        turnRight()
        local ok, data = turtle.inspect()
        if ok and isMarker(data) then
            -- Wall on right, record it
            recordMarkerInFront()
            -- Turn back left (wall is beside us, keep going forward)
            turnLeft()
            -- Now try to move forward
            local okF, dataF = turtle.inspect()
            if okF and isMarker(dataF) then
                -- Wall in front too, record it
                recordMarkerInFront()
                -- Turn left to follow the wall
                turnLeft()
            else
                forward()
                steps = steps + 1
            end
        else
            -- No wall on right, step right (wall ended, go around corner)
            forward()
            steps = steps + 1
            -- Check if wall is on right again after stepping
            turnRight()
            local okR, dataR = turtle.inspect()
            if okR and isMarker(dataR) then
                recordMarkerInFront()
            end
            turnLeft()
        end

        -- Check if we've returned to start position and facing
        if pos.x == startX and pos.z == startZ and facing == startFacing and steps > 2 then
            break
        end
    end

    if steps >= maxSteps then
        return nil, "Perimeter trace exceeded maximum steps"
    end

    return markers, nil
end

local function buildShapeFromPerimeter(markers)
    -- Find bounding box
    local minX, maxX, minZ, maxZ = markers[1].x, markers[1].x, markers[1].z, markers[1].z
    for _, m in ipairs(markers) do
        if m.x < minX then minX = m.x end
        if m.x > maxX then maxX = m.x end
        if m.z < minZ then minZ = m.z end
        if m.z > maxZ then maxZ = m.z end
    end

    -- Build set of marker positions for fast lookup
    local markerSet = {}
    for _, m in ipairs(markers) do
        markerSet[posKey(m.x, m.z)] = true
    end

    -- Ray-casting (point-in-polygon) to classify interior points
    -- For each point, cast a ray in +X direction and count marker crossings
    -- Build edge segments from markers for ray casting
    -- Simpler approach: for each row (z), sort marker x positions
    -- A point is inside if it has markers on both sides

    -- Build sorted marker x positions per z-row
    local markersByZ = {}
    for _, m in ipairs(markers) do
        if not markersByZ[m.z] then
            markersByZ[m.z] = {}
        end
        table.insert(markersByZ[m.z], m.x)
    end
    for z, xs in pairs(markersByZ) do
        table.sort(xs)
    end

    -- Ray-cast: for each candidate point, cast ray in +X, count marker hits
    -- Use the "crossing number" variant adapted for grid:
    -- A point (px, pz) is inside if:
    --   casting a ray from px in +X direction crosses an odd number of
    --   boundary "walls" (transitions from marker to non-marker on adjacent z rows)

    -- Simpler grid flood-fill approach from outside:
    -- 1. Expand bounding box by 1
    -- 2. Flood fill from a corner (guaranteed outside)
    -- 3. Everything not reached and not a marker is interior

    local expandedMinX = minX - 1
    local expandedMaxX = maxX + 1
    local expandedMinZ = minZ - 1
    local expandedMaxZ = maxZ + 1

    local outside = {}
    local queue = {}
    local head = 1
    local startKey = posKey(expandedMinX, expandedMinZ)
    outside[startKey] = true
    table.insert(queue, { x = expandedMinX, z = expandedMinZ })

    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        local neighbors = {
            { x = cur.x + 1, z = cur.z },
            { x = cur.x - 1, z = cur.z },
            { x = cur.x, z = cur.z + 1 },
            { x = cur.x, z = cur.z - 1 },
        }
        for _, n in ipairs(neighbors) do
            if n.x >= expandedMinX and n.x <= expandedMaxX
                and n.z >= expandedMinZ and n.z <= expandedMaxZ then
                local nk = posKey(n.x, n.z)
                if not outside[nk] and not markerSet[nk] then
                    outside[nk] = true
                    table.insert(queue, n)
                end
            end
        end
    end

    -- Interior = within original bounding box, not marker, not outside
    local area = {}
    local count = 0
    for z = minZ, maxZ do
        for x = minX, maxX do
            local key = posKey(x, z)
            if not markerSet[key] and not outside[key] then
                area[key] = true
                count = count + 1
            end
        end
    end

    -- Build serpentine work order
    local workOrder = {}
    local row = 0
    for z = minZ, maxZ do
        row = row + 1
        if row % 2 == 1 then
            for x = minX, maxX do
                local key = posKey(x, z)
                if area[key] then
                    table.insert(workOrder, { x = x, z = z })
                end
            end
        else
            for x = maxX, minX, -1 do
                local key = posKey(x, z)
                if area[key] then
                    table.insert(workOrder, { x = x, z = z })
                end
            end
        end
    end

    return area, workOrder, count
end

-- ---- Corner Marker Mode ----

local function bresenhamLine(x1, z1, x2, z2)
    local points = {}
    local dx = math.abs(x2 - x1)
    local dz = math.abs(z2 - z1)
    local sx = x1 < x2 and 1 or -1
    local sz = z1 < z2 and 1 or -1
    local err = dx - dz
    local cx, cz = x1, z1
    while true do
        table.insert(points, { x = cx, z = cz })
        if cx == x2 and cz == z2 then break end
        local e2 = 2 * err
        if e2 > -dz then
            err = err - dz
            cx = cx + sx
        end
        if e2 < dx then
            err = err + dx
            cz = cz + sz
        end
    end
    return points
end

local function findLCorner(blocks)
    -- Find the bend point of an L-shape: the block with
    -- cable neighbors in two perpendicular directions
    local blockSet = {}
    for _, b in ipairs(blocks) do
        blockSet[posKey(b.x, b.z)] = true
    end
    for _, b in ipairs(blocks) do
        local hasNS = blockSet[posKey(b.x, b.z + 1)]
                   or blockSet[posKey(b.x, b.z - 1)]
        local hasEW = blockSet[posKey(b.x + 1, b.z)]
                   or blockSet[posKey(b.x - 1, b.z)]
        if hasNS and hasEW then
            return b
        end
    end
    return blocks[math.ceil(#blocks / 2)]
end

local function followCornerRoute()
    local approachDir = facing
    -- Walk forward at y=0 until finding a cable block
    local found = false
    for i = 1, 256 do
        local ok, data = turtle.inspect()
        if ok and data.name == "computercraft:cable" then
            found = true
            break
        end
        forward()
    end
    if not found then
        return nil, nil, "No cable found within 256 blocks"
    end

    -- Go up to y=1 and move above the cable
    refuel()
    if not up() then
        return nil, nil, "Cannot move up (check fuel)"
    end
    forward()

    local firstX, firstZ = pos.x, pos.z
    local globalVisited = {}
    local allCableBlocks = {}
    local corners = {}

    -- Check if position has cable below (moves turtle there)
    local function hasCableAt(x, z)
        checkFuel(FUEL_WARNING)
        moveTo(x, 1, z)
        local ok, data = turtle.inspectDown()
        return ok and data.name == "computercraft:cable"
    end

    -- BFS: find all cable blocks connected to starting position
    local function traverseL(sx, sz)
        local blocks = {}
        local queue = { { x = sx, z = sz } }
        local head = 1
        globalVisited[posKey(sx, sz)] = true
        table.insert(blocks, { x = sx, z = sz })

        while head <= #queue do
            local cur = queue[head]
            head = head + 1
            local neighbors = {
                { x = cur.x + 1, z = cur.z },
                { x = cur.x - 1, z = cur.z },
                { x = cur.x, z = cur.z + 1 },
                { x = cur.x, z = cur.z - 1 },
            }
            for _, n in ipairs(neighbors) do
                local key = posKey(n.x, n.z)
                if not globalVisited[key] then
                    if hasCableAt(n.x, n.z) then
                        globalVisited[key] = true
                        table.insert(queue, n)
                        table.insert(blocks, { x = n.x, z = n.z })
                    end
                end
            end
        end

        return blocks
    end

    -- Find exit direction from an L-shape
    -- approachX/Z = where the turtle came from (before the L)
    -- Exit tip = the tip FARTHEST from the approach position
    local function findExitInfo(blocks, approachX, approachZ)
        local blockSet = {}
        for _, b in ipairs(blocks) do
            blockSet[posKey(b.x, b.z)] = true
        end

        -- Tips: blocks with 0 or 1 cable neighbors
        local tips = {}
        for _, b in ipairs(blocks) do
            local nc = 0
            if blockSet[posKey(b.x + 1, b.z)] then nc = nc + 1 end
            if blockSet[posKey(b.x - 1, b.z)] then nc = nc + 1 end
            if blockSet[posKey(b.x, b.z + 1)] then nc = nc + 1 end
            if blockSet[posKey(b.x, b.z - 1)] then nc = nc + 1 end
            if nc <= 1 then
                table.insert(tips, b)
            end
        end

        -- Pick the tip farthest from approach position as exit
        local exitTip = nil
        local maxDist = -1
        for _, tip in ipairs(tips) do
            local d = math.abs(tip.x - approachX)
                    + math.abs(tip.z - approachZ)
            if d > maxDist then
                maxDist = d
                exitTip = tip
            end
        end

        if not exitTip then return nil, nil, nil end

        -- Get outward direction from exit tip
        local nx, nz
        if blockSet[posKey(exitTip.x + 1, exitTip.z)] then
            nx, nz = exitTip.x + 1, exitTip.z
        elseif blockSet[posKey(exitTip.x - 1, exitTip.z)] then
            nx, nz = exitTip.x - 1, exitTip.z
        elseif blockSet[posKey(exitTip.x, exitTip.z + 1)] then
            nx, nz = exitTip.x, exitTip.z + 1
        elseif blockSet[posKey(exitTip.x, exitTip.z - 1)] then
            nx, nz = exitTip.x, exitTip.z - 1
        end

        if not nx then return nil, nil, nil end

        local outDX = exitTip.x - nx
        local outDZ = exitTip.z - nz
        return outDX, outDZ, exitTip
    end

    -- Process first L-shape
    local blocks = traverseL(firstX, firstZ)
    for _, b in ipairs(blocks) do
        table.insert(allCableBlocks, b)
    end
    local corner = findLCorner(blocks)
    table.insert(corners, corner)

    -- Approach position = one step back from first cable in approach dir
    local approachX = firstX - dx[approachDir]
    local approachZ = firstZ - dz[approachDir]
    local exitDX, exitDZ, exitTip = findExitInfo(blocks, approachX, approachZ)

    term.setCursorPos(1, 6)
    term.clearLine()
    term.write("L#1: " .. #blocks .. " cables")
    if exitDX then
        term.setCursorPos(1, 7)
        term.clearLine()
        term.write("Exit: " .. exitDX .. "," .. exitDZ)
    end

    if not exitDX then
        moveTo(0, 1, 0)
        down()
        face(0)
        return nil, nil, "Could not determine exit direction"
    end

    -- Follow the route: walk gaps, traverse L-shapes
    local maxGap = 256
    local lCount = 1

    while true do
        local searchX = exitTip.x + exitDX
        local searchZ = exitTip.z + exitDZ
        local foundNext = false
        local loopComplete = false

        term.setCursorPos(1, 8)
        term.clearLine()
        term.write("Walking gap...")

        for gap = 1, maxGap do
            local key = posKey(searchX, searchZ)
            if globalVisited[key] then
                -- Hit a previously visited cable block = back at start
                loopComplete = true
                foundNext = true
                break
            end
            if hasCableAt(searchX, searchZ) then
                foundNext = true
                break
            end
            searchX = searchX + exitDX
            searchZ = searchZ + exitDZ
        end

        if not foundNext then
            moveTo(0, 1, 0)
            down()
            face(0)
            return nil, nil, "Gap between corners too large"
        end

        if loopComplete then
            term.setCursorPos(1, 8)
            term.clearLine()
            term.write("Route complete!")
            break
        end

        -- Traverse new L-shape
        blocks = traverseL(searchX, searchZ)
        for _, b in ipairs(blocks) do
            table.insert(allCableBlocks, b)
        end
        corner = findLCorner(blocks)
        table.insert(corners, corner)

        -- Approach position = one step back from found cable
        approachX = searchX - exitDX
        approachZ = searchZ - exitDZ
        exitDX, exitDZ, exitTip = findExitInfo(blocks, approachX, approachZ)

        lCount = lCount + 1
        term.setCursorPos(1, 6)
        term.clearLine()
        term.write("L#" .. lCount .. ": " .. #blocks .. " cables")
        if exitDX then
            term.setCursorPos(1, 7)
            term.clearLine()
            term.write("Exit: " .. exitDX .. "," .. exitDZ)
        end

        if not exitDX then
            moveTo(0, 1, 0)
            down()
            face(0)
            return nil, nil, "Could not determine exit direction"
        end
    end

    -- Return home
    moveTo(0, 1, 0)
    down()
    face(0)

    return corners, allCableBlocks, nil
end

local function buildPerimeterFromCorners(corners)
    local perimSet = {}
    local perim = {}
    for i = 1, #corners do
        local next = (i % #corners) + 1
        local pts = bresenhamLine(
            corners[i].x, corners[i].z,
            corners[next].x, corners[next].z
        )
        for _, p in ipairs(pts) do
            local key = posKey(p.x, p.z)
            if not perimSet[key] then
                perimSet[key] = true
                table.insert(perim, { x = p.x, z = p.z })
            end
        end
    end
    return perim
end

local function removeMarkers(cableBlocks)
    -- Fly at y=1 to each cable position and dig from above
    moveTo(pos.x, 1, pos.z)
    for _, cb in ipairs(cableBlocks) do
        moveTo(cb.x, 1, cb.z)
        if turtle.detectDown() then
            turtle.digDown()
        end
    end
end

-- =================== Section 6: Excavate Mode ===============================

local function excavate(workOrder, depth, totalPositions)
    local processed = 0
    for _, wp in ipairs(workOrder) do
        -- Check fuel
        if not checkFuel(FUEL_WARNING) then
            -- Try to refuel, if still low warn but continue
        end

        -- Move to column position at surface level (y=0)
        moveTo(wp.x, 0, wp.z)

        -- Dig down to depth
        for d = 1, depth do
            -- Dig down
            if turtle.detectDown() then
                turtle.digDown()
            end
            down()

            -- Check inventory
            if isInventoryFull() then
                dumpToChest()
            end
        end

        -- Return to surface
        moveTo(wp.x, 0, wp.z)

        processed = processed + 1

        -- Progress update on terminal
        if processed % 10 == 0 or processed == totalPositions then
            local pct = math.floor((processed / totalPositions) * 100)
            term.setCursorPos(1, 13)
            term.clearLine()
            term.write("Progress: " .. processed .. "/" .. totalPositions .. " (" .. pct .. "%)")
        end
    end
end

-- ==================== Section 7: Fill Mode ==================================

local function fill(workOrder, totalPositions, validBlocks, protectMarkers)
    local processed = 0
    local maxDescend = 64

    for _, wp in ipairs(workOrder) do
        if not checkFuel(FUEL_WARNING) then
            -- Low fuel warning
        end

        -- Travel at y=1 to avoid destroying markers, then descend
        if protectMarkers then
            moveTo(wp.x, 1, wp.z)
        end
        moveTo(wp.x, 0, wp.z)

        -- Descend, inspecting each block below
        local fillPositions = {} -- list of Y levels that need filling
        local descended = 0

        while descended < maxDescend do
            local ok, data = turtle.inspectDown()
            if not ok then
                -- Air below, record for filling, keep going
                table.insert(fillPositions, pos.y - 1)
                down()
                descended = descended + 1
            elseif isReplaceable(data) then
                -- Break replaceable, record for filling
                turtle.digDown()
                table.insert(fillPositions, pos.y - 1)
                down()
                descended = descended + 1
            elseif isCollectible(data) then
                -- Break and collect (torch etc), record for filling
                turtle.digDown()
                table.insert(fillPositions, pos.y - 1)
                down()
                descended = descended + 1
            elseif isSolidGround(data) then
                -- Hit solid ground, stop descending
                break
            else
                -- Unknown, treat as solid
                break
            end
        end

        -- Ascend, placing fill blocks below as we go up
        -- Last placement is at y=-1 (when turtle reaches y=0)
        -- y=0 (marker level) stays clear
        while pos.y < 0 do
            up()
            if selectFillBlock(validBlocks) then
                turtle.placeDown()
            end
        end

        -- Make sure we're back at surface
        moveTo(wp.x, 0, wp.z)

        processed = processed + 1

        -- Check if we need more blocks
        if getFillBlockCount(validBlocks) < 10 then
            if protectMarkers then
                up() -- go to y=1 so home trip avoids markers
            end
            dumpAndLoad()
            if protectMarkers then
                down()
            end
        end

        -- Progress
        if processed % 10 == 0 or processed == totalPositions then
            local pct = math.floor((processed / totalPositions) * 100)
            term.setCursorPos(1, 13)
            term.clearLine()
            term.write("Progress: " .. processed .. "/" .. totalPositions .. " (" .. pct .. "%)")
        end
    end
end

-- ======================== Section 8: GUI ====================================

local W, H = 39, 13

local function setColor(fg, bg)
    if term.isColor() then
        if fg then term.setTextColor(fg) end
        if bg then term.setBackgroundColor(bg) end
    end
end

local function clearScreen()
    setColor(colors.white, colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function centerText(y, text)
    local x = math.floor((W - #text) / 2) + 1
    term.setCursorPos(x, y)
    term.write(text)
end

local function drawHeader(title)
    setColor(colors.yellow)
    centerText(1, "=== " .. title .. " ===")
    setColor(colors.white)
end

local function drawProgressBar(y, current, total)
    local barWidth = W - 2
    local filled = math.floor((current / total) * barWidth)
    term.setCursorPos(1, y)
    term.write("[")
    setColor(colors.green)
    term.write(string.rep("=", filled))
    setColor(colors.gray)
    term.write(string.rep("-", barWidth - filled))
    setColor(colors.white)
    term.write("]")
end

local function promptNumber(prompt, y)
    setColor(colors.lightGray)
    term.setCursorPos(1, y)
    term.write(prompt)
    setColor(colors.white)
    local input = read()
    return tonumber(input)
end

local function waitForEnter(y)
    setColor(colors.lightGray)
    term.setCursorPos(1, y)
    term.write("Press ENTER to continue...")
    read()
end

local function showHelp()
    clearScreen()
    drawHeader("HELP")
    setColor(colors.lightGray)
    term.setCursorPos(1, 3)
    term.write("SETUP:")
    term.setCursorPos(1, 4)
    term.write(" Chest BEHIND turtle. Turtle")
    term.setCursorPos(1, 5)
    term.write(" faces the work area.")
    term.setCursorPos(1, 6)
    term.write("RECTANGLE: dimensions or scan.")
    term.setCursorPos(1, 7)
    term.write("CUSTOM FULL: CC blocks around")
    term.setCursorPos(1, 8)
    term.write(" entire perimeter.")
    term.setCursorPos(1, 9)
    term.write("CORNERS: Cable L-shapes at")
    term.setCursorPos(1, 10)
    term.write(" corners. Turtle follows route")
    term.setCursorPos(1, 11)
    term.write(" & removes markers when done.")
    term.setCursorPos(1, 12)
    term.write("Fill leaves marker level clear.")
    waitForEnter(13)
end

local function showProgressScreen(mode, processed, total)
    local pct = 0
    if total > 0 then
        pct = math.floor((processed / total) * 100)
    end
    term.setCursorPos(1, 8)
    term.clearLine()
    setColor(colors.white)
    term.write("Mode: " .. mode)
    term.setCursorPos(1, 9)
    term.clearLine()
    term.write("Pos: " .. pos.x .. "," .. pos.y .. "," .. pos.z)
    term.setCursorPos(1, 10)
    term.clearLine()
    term.write(processed .. "/" .. total .. " (" .. pct .. "%)")
    drawProgressBar(11, processed, total)
    term.setCursorPos(1, 12)
    term.clearLine()
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then
        term.write("Fuel: unlimited")
    else
        if fuel < FUEL_WARNING then
            setColor(colors.red)
        end
        term.write("Fuel: " .. fuel)
        setColor(colors.white)
    end
end

-- ---- Area Mode Selection ----

local function selectAreaMode()
    clearScreen()
    drawHeader("SELECT AREA MODE")
    setColor(colors.white)
    term.setCursorPos(1, 4)
    term.write("[1] Rectangle")
    term.setCursorPos(1, 5)
    term.write("    Enter dimensions or scan.")
    term.setCursorPos(1, 7)
    term.write("[2] Custom Shape")
    term.setCursorPos(1, 8)
    term.write("    Trace CC block perimeter.")
    setColor(colors.lightGray)
    term.setCursorPos(1, 10)
    term.write("Choose [1/2]: ")
    setColor(colors.white)
    while true do
        local _, key = os.pullEvent("char")
        if key == "1" then return "rectangle"
        elseif key == "2" then return "custom"
        end
    end
end

-- ---- Rectangle Setup ----

local function setupRectangle()
    clearScreen()
    drawHeader("RECTANGLE SETUP")
    setColor(colors.white)
    term.setCursorPos(1, 3)
    term.write("[1] Enter dimensions manually")
    term.setCursorPos(1, 4)
    term.write("[2] Scan for marker block")
    setColor(colors.lightGray)
    term.setCursorPos(1, 6)
    term.write("Choose [1/2]: ")
    setColor(colors.white)

    local choice
    while true do
        local _, key = os.pullEvent("char")
        if key == "1" then choice = "manual"; break
        elseif key == "2" then choice = "scan"; break
        end
    end

    local length, width

    if choice == "manual" then
        clearScreen()
        drawHeader("ENTER DIMENSIONS")
        length = promptNumber("Length (forward): ", 4)
        width = promptNumber("Width (right):    ", 5)
        if not length or not width or length < 1 or width < 1 then
            setColor(colors.red)
            term.setCursorPos(1, 7)
            term.write("Invalid dimensions!")
            os.sleep(2)
            return nil
        end
    else
        clearScreen()
        drawHeader("SCANNING")
        setColor(colors.lightGray)
        term.setCursorPos(1, 3)
        term.write("Place CC block at opposite")
        term.setCursorPos(1, 4)
        term.write("corner of rectangle.")
        term.setCursorPos(1, 6)
        term.write("Turtle will scan forward")
        term.setCursorPos(1, 7)
        term.write("then right to find it.")
        waitForEnter(9)

        clearScreen()
        drawHeader("SCANNING...")
        term.setCursorPos(1, 4)
        term.write("Searching for markers...")

        local err
        length, width, err = scanRectangle()
        if err then
            setColor(colors.red)
            term.setCursorPos(1, 6)
            term.write("Error: " .. err)
            os.sleep(3)
            return nil
        end

        setColor(colors.green)
        term.setCursorPos(1, 6)
        term.write("Found: " .. length .. " x " .. width)
        os.sleep(1)
    end

    return { length = length, width = width }
end

-- ---- Custom Shape Setup ----

local function setupCustomShape()
    clearScreen()
    drawHeader("CUSTOM SHAPE SETUP")
    setColor(colors.white)
    term.setCursorPos(1, 3)
    term.write("[1] Full perimeter")
    term.setCursorPos(1, 4)
    term.write("    CC blocks on every edge")
    term.setCursorPos(1, 5)
    term.write("    block.")
    term.setCursorPos(1, 7)
    term.write("[2] Corners only")
    term.setCursorPos(1, 8)
    term.write("    CC blocks at corners,")
    term.setCursorPos(1, 9)
    term.write("    turtle connects the dots.")
    setColor(colors.lightGray)
    term.setCursorPos(1, 11)
    term.write("Choose [1/2]: ")
    setColor(colors.white)

    local choice
    while true do
        local _, key = os.pullEvent("char")
        if key == "1" then choice = "full"; break
        elseif key == "2" then choice = "corners"; break
        end
    end

    if choice == "full" then
        -- Existing full-perimeter trace flow
        clearScreen()
        drawHeader("FULL PERIMETER SETUP")
        setColor(colors.lightGray)
        term.setCursorPos(1, 3)
        term.write("Place CC blocks around the")
        term.setCursorPos(1, 4)
        term.write("FULL perimeter of your shape.")
        term.setCursorPos(1, 6)
        term.write("Shape can be any form:")
        term.setCursorPos(1, 7)
        term.write("rectangle, L, circle, etc.")
        term.setCursorPos(1, 9)
        term.write("Turtle must face toward the")
        term.setCursorPos(1, 10)
        term.write("shape with chest behind it.")
        waitForEnter(12)

        clearScreen()
        drawHeader("TRACING PERIMETER")
        term.setCursorPos(1, 4)
        term.write("Walking to find perimeter...")

        local markers, err = tracePerimeter()
        if err then
            setColor(colors.red)
            term.setCursorPos(1, 6)
            term.write("Error: " .. err)
            os.sleep(3)
            returnHome()
            return nil
        end

        setColor(colors.green)
        term.setCursorPos(1, 6)
        term.write("Found " .. #markers .. " markers.")
        term.setCursorPos(1, 7)
        term.write("Building shape map...")
        os.sleep(1)

        returnHome()
        return { markers = markers }

    else
        -- Corners-only mode: follow L-shaped cable markers
        clearScreen()
        drawHeader("CORNER ROUTE SETUP")
        setColor(colors.lightGray)
        term.setCursorPos(1, 3)
        term.write("Place cable blocks in L shapes")
        term.setCursorPos(1, 4)
        term.write("at each corner (min 3).")
        term.setCursorPos(1, 5)
        term.write("Each L points to the next.")
        term.setCursorPos(1, 7)
        term.write("Turtle must face toward the")
        term.setCursorPos(1, 8)
        term.write("nearest corner L.")
        waitForEnter(10)

        clearScreen()
        drawHeader("FOLLOWING ROUTE")
        term.setCursorPos(1, 4)
        term.write("Tracing corner route...")

        local rawCorners, cableBlocks, err = followCornerRoute()
        if err then
            setColor(colors.red)
            term.setCursorPos(1, 6)
            term.write("Error: " .. err)
            os.sleep(3)
            returnHome()
            return nil
        end

        if #rawCorners < 3 then
            setColor(colors.red)
            term.setCursorPos(1, 6)
            term.write("Found " .. #rawCorners .. " corners.")
            term.setCursorPos(1, 7)
            term.write("Need at least 3!")
            os.sleep(3)
            return nil
        end

        local perim = buildPerimeterFromCorners(rawCorners)

        setColor(colors.green)
        term.setCursorPos(1, 6)
        term.write("Found " .. #rawCorners .. " corners.")
        term.setCursorPos(1, 7)
        term.write("Perimeter: " .. #perim .. " blocks.")
        os.sleep(1)

        return { markers = perim, cableBlocks = cableBlocks }
    end
end

-- ---- Pre-flight Check ----

local function preflightCheck(mode, totalPositions, depth)
    clearScreen()
    drawHeader("PRE-FLIGHT CHECK")
    setColor(colors.white)
    term.setCursorPos(1, 3)
    term.write("Mode: " .. mode)
    term.setCursorPos(1, 4)
    term.write("Positions: " .. totalPositions)
    if depth then
        term.setCursorPos(1, 5)
        term.write("Depth: " .. depth)
    end
    local fuel = turtle.getFuelLevel()
    term.setCursorPos(1, 6)
    if fuel == "unlimited" then
        term.write("Fuel: unlimited")
    else
        local estimated = totalPositions * (depth or 10) * 4
        term.write("Fuel: " .. fuel)
        term.setCursorPos(1, 7)
        if fuel < estimated then
            setColor(colors.red)
            term.write("WARNING: May need ~" .. estimated)
        else
            setColor(colors.green)
            term.write("Fuel looks sufficient")
        end
    end
    setColor(colors.white)
    term.setCursorPos(1, 9)
    term.write("[Y] Start  [N] Cancel")
    while true do
        local _, key = os.pullEvent("char")
        if key == "y" then return true
        elseif key == "n" then return false
        end
    end
end

-- ======================== Section 9: Main Program ===========================

local function runExcavate()
    local areaMode = selectAreaMode()
    local workOrder, totalPositions, area, depth

    if areaMode == "rectangle" then
        local rect = setupRectangle()
        if not rect then return end

        clearScreen()
        drawHeader("EXCAVATE DEPTH")
        depth = promptNumber("Depth to dig: ", 4)
        if not depth or depth < 1 then
            setColor(colors.red)
            term.setCursorPos(1, 6)
            term.write("Invalid depth!")
            os.sleep(2)
            return
        end

        area, workOrder, totalPositions = buildRectArea(rect.length, rect.width)
    else
        local shape = setupCustomShape()
        if not shape then return end

        clearScreen()
        drawHeader("EXCAVATE DEPTH")
        depth = promptNumber("Depth to dig: ", 4)
        if not depth or depth < 1 then
            setColor(colors.red)
            term.setCursorPos(1, 6)
            term.write("Invalid depth!")
            os.sleep(2)
            return
        end

        area, workOrder, totalPositions = buildShapeFromPerimeter(shape.markers)
    end

    if totalPositions == 0 then
        clearScreen()
        setColor(colors.red)
        centerText(6, "No interior positions found!")
        os.sleep(3)
        return
    end

    if not preflightCheck("Excavate", totalPositions, depth) then
        return
    end

    -- Run excavation
    clearScreen()
    drawHeader("EXCAVATING")
    setColor(colors.white)
    term.setCursorPos(1, 3)
    term.write("Area: " .. totalPositions .. " columns")
    term.setCursorPos(1, 4)
    term.write("Depth: " .. depth .. " blocks")

    excavate(workOrder, depth, totalPositions)

    returnHome()

    clearScreen()
    drawHeader("COMPLETE")
    setColor(colors.green)
    centerText(6, "Excavation finished!")
    setColor(colors.white)
    centerText(7, totalPositions .. " columns x " .. depth .. " deep")
    waitForEnter(10)
end

local function runFill()
    local areaMode = selectAreaMode()
    local workOrder, totalPositions, area
    local cableBlocks = nil

    if areaMode == "rectangle" then
        local rect = setupRectangle()
        if not rect then return end
        area, workOrder, totalPositions = buildRectArea(rect.length, rect.width)
    else
        local shape = setupCustomShape()
        if not shape then return end
        area, workOrder, totalPositions = buildShapeFromPerimeter(shape.markers)
        cableBlocks = shape.cableBlocks
    end

    if totalPositions == 0 then
        clearScreen()
        setColor(colors.red)
        centerText(6, "No interior positions found!")
        os.sleep(3)
        return
    end

    -- Scan chest for valid fill blocks
    clearScreen()
    drawHeader("SCANNING CHEST")
    term.setCursorPos(1, 4)
    term.write("Identifying fill blocks...")

    local validBlocks = scanChest()
    local blockTypes = 0
    for _ in pairs(validBlocks) do blockTypes = blockTypes + 1 end

    if blockTypes == 0 then
        setColor(colors.red)
        term.setCursorPos(1, 6)
        term.write("No blocks found in chest!")
        os.sleep(3)
        return
    end

    setColor(colors.green)
    term.setCursorPos(1, 6)
    term.write("Found " .. blockTypes .. " block type(s)")
    os.sleep(1)

    if not preflightCheck("Fill", totalPositions, nil) then
        return
    end

    -- Load initial fill blocks
    loadFromChest()

    -- Run fill (protect markers if corner mode)
    local protectMarkers = cableBlocks and #cableBlocks > 0
    clearScreen()
    drawHeader("FILLING")
    setColor(colors.white)
    term.setCursorPos(1, 3)
    term.write("Area: " .. totalPositions .. " columns")
    term.setCursorPos(1, 4)
    term.write("Descending to find ground...")

    fill(workOrder, totalPositions, validBlocks, protectMarkers)

    -- Remove corner markers after fill is complete
    if protectMarkers then
        term.setCursorPos(1, 13)
        term.clearLine()
        term.write("Removing corner markers...")
        removeMarkers(cableBlocks)
    end

    returnHome()
    dumpToChest()

    clearScreen()
    drawHeader("COMPLETE")
    setColor(colors.green)
    centerText(6, "Fill finished!")
    setColor(colors.white)
    centerText(7, totalPositions .. " columns processed")
    waitForEnter(10)
end

local function mainMenu()
    while true do
        clearScreen()
        setColor(colors.yellow)
        centerText(1, "======================")
        centerText(2, " TURTLE EXCAVATE/FILL ")
        centerText(3, "======================")
        setColor(colors.white)
        term.setCursorPos(1, 5)
        term.write("  [1] Excavate")
        term.setCursorPos(1, 6)
        term.write("      Dig out an area")
        term.setCursorPos(1, 8)
        term.write("  [2] Fill")
        term.setCursorPos(1, 9)
        term.write("      Fill holes/gaps")
        term.setCursorPos(1, 11)
        term.write("  [3] Help")
        setColor(colors.lightGray)
        term.setCursorPos(1, 13)
        term.write("Choose [1/2/3]: ")
        setColor(colors.white)

        while true do
            local _, key = os.pullEvent("char")
            if key == "1" then
                runExcavate()
                break
            elseif key == "2" then
                runFill()
                break
            elseif key == "3" then
                showHelp()
                break
            end
        end
    end
end

-- Entry point
mainMenu()
