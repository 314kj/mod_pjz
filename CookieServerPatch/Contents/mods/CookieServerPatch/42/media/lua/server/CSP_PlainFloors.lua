-- CookieServerPatch: ground floors built from the build menu -> plain floors.
-- Server only.
--
-- Why: the profiler (26 Oct) showed the lag comes from the game removing
-- "entities" one by one when areas unload; every grass/dirt/street tile laid
-- with the build menu is an entity. A plain floor with the same tile looks the
-- same and is not an entity. Tested 26 Oct on the live server: two converted
-- tiles (blends_natural_01_16, blends_street_01_55) stayed plain after a restart.
--
-- What it does: when a ground square loads and its floor is an entity whose
-- tile is in TILESETS, the square is queued; a few squares per tick are swapped
-- for a plain floor with the same tile (+ its overlays and mod data), the same
-- way the floor test did. Done floors are plain, so nothing is re-done.
-- Floors laid after this runs are converted the next time their area loads.
-- Walls, doors, windows, furniture and upper floors are not touched.
--
-- v2 (26 Oct, 22:40): quiet mode. v1 sent every swap to nearby players
-- (2 packets per floor); the first pass did ~60,000 swaps in 10 minutes and
-- players near them dropped while the server itself stayed at 10 FPS. Now the
-- swap is done on the server only and nothing is sent: players already see
-- the same tile, and they get the plain floor the next time that area loads
-- for them. Also slower: 10 per tick instead of 25.
--
-- Every 10 minutes: [CookieServerPatch] plainfloors: converted=N queued=N failed=N
-- plus entity floors left alone, by tileset (so the list can be extended).
-- To undo: remove this file (already converted floors stay plain).
-- No next() (Kahlua).

if not isServer() then return end

local TAG = "[CookieServerPatch] plainfloors"
local TILESETS = { "blends_natural", "blends_street", "floors_exterior_natural" }
local GROUND_ONLY = true
local PER_TICK = 10
local TRANSMIT = false   -- true = also send each swap to nearby players (v1)
local REPORT_MS = 10 * 60 * 1000

local queue, queued = {}, {}
local head = 1
local stats = { converted = 0, failed = 0, gone = 0 }
local skipped = {}       -- tileset -> entity floors left alone
local nextReport = 0
local errorsLogged = 0

local function spriteName(obj)
    local ok, name = pcall(function() return obj:getSprite():getName() end)
    if ok and type(name) == "string" then return name end
    return nil
end

local function isEntity(obj)
    local ok, sc = pcall(function() return obj:getSpriteConfig() end)
    return ok and sc ~= nil
end

local function wanted(name)
    for i = 1, #TILESETS do
        local p = TILESETS[i]
        if string.sub(name, 1, #p) == p then return true end
    end
    return false
end

local function tileset(name)
    return string.match(name, "^(.*)_%d+$") or name
end

local function onLoadGridsquare(square)
    if not square then return end
    if GROUND_ONLY and square:getZ() ~= 0 then return end
    local floor = square:getFloor()
    if not floor or not isEntity(floor) then return end
    local name = spriteName(floor)
    if not name then return end
    if not wanted(name) then
        local t = tileset(name)
        skipped[t] = (skipped[t] or 0) + 1
        return
    end
    local key = square:getX() .. "," .. square:getY() .. "," .. square:getZ()
    if queued[key] then return end
    queued[key] = true
    queue[#queue + 1] = { x = square:getX(), y = square:getY(), z = square:getZ() }
end

local function copyOverlays(from, to)
    local ok, list = pcall(function() return from:getAttachedAnimSprite() end)
    if not ok or not list then return end
    for i = 0, list:size() - 1 do
        pcall(function()
            local inst = list:get(i)
            local parent = inst and inst:getParentSprite()
            if parent then to:AttachExistingAnim(parent, 0, 0, false, 0, false, 0) end
        end)
    end
end

local function copyModData(from, to)
    pcall(function()
        if not from:hasModData() then return end
        local src, dst = from:getModData(), to:getModData()
        for k, v in pairs(src) do
            local tv = type(v)
            if tv == "string" or tv == "number" or tv == "boolean" then dst[k] = v end
        end
    end)
end

local function convert(item)
    local square = getCell():getGridSquare(item.x, item.y, item.z)
    if not square then stats.gone = stats.gone + 1 return end
    local old = square:getFloor()
    if not old or not isEntity(old) then return end
    local name = spriteName(old)
    if not name or not wanted(name) then return end
    local okT, fullType = pcall(function() return old:getEntityFullTypeDebug() end)
    local ok, err = pcall(function()
        local plain = IsoObject.new(getCell(), square, getSprite(name))
        copyOverlays(old, plain)
        copyModData(old, plain)
        -- remember what it was, for a later "dismantle" option
        plain:getModData().CSP_plainFrom = (okT and type(fullType) == "string" and fullType ~= "") and fullType or name
        if TRANSMIT then square:transmitRemoveItemFromSquare(old) end
        square:RemoveTileObject(old)
        square:AddTileObject(plain, 0)
        square:RecalcAllWithNeighbours(true)
        if TRANSMIT then plain:transmitCompleteItemToClients() end
    end)
    if ok then
        stats.converted = stats.converted + 1
    else
        stats.failed = stats.failed + 1
        if errorsLogged < 5 then
            errorsLogged = errorsLogged + 1
            print(TAG .. " failed at " .. item.x .. "," .. item.y .. "," .. item.z .. ": " .. tostring(err))
        end
    end
end

local function top(tbl, n)
    local list = {}
    for k, v in pairs(tbl) do list[#list + 1] = { k = k, v = v } end
    table.sort(list, function(a, b) return a.v > b.v end)
    local parts = {}
    for i = 1, math.min(n, #list) do parts[#parts + 1] = list[i].k .. "=" .. list[i].v end
    return table.concat(parts, "  ")
end

local function onTick()
    local n = 0
    while head <= #queue and n < PER_TICK do
        local item = queue[head]
        queue[head] = nil
        head = head + 1
        queued[item.x .. "," .. item.y .. "," .. item.z] = nil
        convert(item)
        n = n + 1
    end
    if head > #queue and head > 1 then queue, head = {}, 1 end

    local now = getTimestampMs()
    if nextReport == 0 then nextReport = now + REPORT_MS end
    if now >= nextReport then
        nextReport = now + REPORT_MS
        print(TAG .. ": converted=" .. stats.converted .. " queued=" .. (#queue - head + 1) ..
            " failed=" .. stats.failed .. " unloadedBeforeTurn=" .. stats.gone)
        print(TAG .. " entity floors left alone: " .. top(skipped, 10))
    end
end

Events.LoadGridsquare.Add(onLoadGridsquare)
Events.OnTick.Add(onTick)
print(TAG .. " on v2 (tilesets: " .. table.concat(TILESETS, ", ") .. ", " .. PER_TICK .. " per tick, send to players=" .. tostring(TRANSMIT) .. ")")
