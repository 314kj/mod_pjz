-- CookieServerPatch: loot respawn in the five maps added mid-season (11 Nov 2026):
-- Frogtown, Raccoon City, Raven Creek, Constown, AnruisiTown. Server only.
--
-- Loot respawn (Java LootRespawn, 42.22.2) only refills a container when the
-- ground square under it is in a zone of type TownZone or TrailerPark.
-- In B42 those zones are not read from a map's objects.lua any more (vanilla
-- metazoneHandler.lua skips TownZone/Forest/Farm/...). They come from the
-- map's maps/biomemap_X_Y.png, are made the first time a cell loads, and are
-- then kept in the save (map_zone.bin) for good.
--
-- On our save (map_zone.bin of 11 Nov, 16:19) none of the five maps has a
-- town zone over its buildings:
--   * cells that had loaded before 11 Nov already hold vanilla forest zones
--     (DeepForest, PRForest, ...), and the game never redoes a loaded cell;
--   * AnruisiTown and Raccoon City ship no biome map, so vanilla's forest
--     biome is used for them anyway;
--   * Frogtown's biome maps are named for 300-tile cells (10_23 ... 13_25),
--     so the game does not find them for Frogtown's own cells.
-- So their houses never refill.
--
-- This file adds TownZone over every 8x8 chunk that a building of those maps
-- touches, unless the chunk is already in a TownZone/TrailerPark.
-- Zones are at most 32x32 tiles, the size of vanilla town zones (a player
-- seeing one square of a zone keeps the whole zone from refilling for
-- SeenHoursPreventLootRespawn hours, so big zones would refill less).
-- It runs once per server start, right after the save's zones are loaded
-- (OnLoadedMapZones). The game saves the zones, so after the first start it
-- only adds zones for buildings that are new (a map update).
--
-- A map that is not on the server's Map= line is left alone.
-- Log: "[CSP] map-townzones on" once, then one line per map.
-- To undo: remove this file. Zones it already added stay in the save; they
-- only make those houses refill like town houses.

if isClient() then return end

local TAG = "[CSP] map-townzones"

-- map folder as written on the Map= line, and the cells (256x256) its lots use
local MAPS = {
    { dir = "Frogtown",        cells = { { 11, 26, 15, 29 } } },
    { dir = "RaccoonCity",     cells = { { 38, 38, 40, 41 } } },
    { dir = "Raven Creek B42", cells = { { 16, 59, 23, 69 }, { 24, 56, 25, 69 } } },
    { dir = "Constown, KY",    cells = { { 19, 42, 24, 44 } } },
    { dir = "AnruisiTown",     cells = { { 46, 43, 49, 46 }, { 50, 44, 50, 46 } } },
}

local MAX_CHUNKS = 4 -- zone side in chunks (4 x 8 = 32 tiles)

local function onMapLine(dir)
    local dirs = getLotDirectories()
    for i = 0, dirs:size() - 1 do
        if dirs:get(i) == dir then return true end
    end
    return false
end

-- "cx,cy" of a 256 cell -> map entry, for the maps on the Map= line
local function cellOwners()
    local owner, maps = {}, {}
    for _, m in ipairs(MAPS) do
        if onMapLine(m.dir) then
            maps[#maps + 1] = m
            m.chunks, m.list, m.buildings = {}, {}, 0
            for _, c in ipairs(m.cells) do
                for cx = c[1], c[3] do
                    for cy = c[2], c[4] do owner[cx .. "," .. cy] = m end
                end
            end
        end
    end
    return owner, maps
end

-- every building of those maps -> the chunks it touches
local function collectChunks(defs, owner)
    for i = 0, defs:size() - 1 do
        local def = defs:get(i)
        local x, y = def:getX(), def:getY()
        local m = owner[math.floor(x / 256) .. "," .. math.floor(y / 256)]
        if m and def:getRooms():size() > 0 then
            m.buildings = m.buildings + 1
            local x2, y2 = def:getX2(), def:getY2()
            for cx = math.floor(x / 8), math.floor((x2 - 1) / 8) do
                for cy = math.floor(y / 8), math.floor((y2 - 1) / 8) do
                    local k = cx .. "," .. cy
                    if not m.chunks[k] then
                        m.chunks[k] = true
                        m.list[#m.list + 1] = { cx, cy }
                    end
                end
            end
        end
    end
end

local function isTown(zone)
    if not zone then return false end
    local t = zone:getType()
    return t == "TownZone" or t == "TownZones" or t == "TrailerPark"
end

-- group chunks into rectangles of at most MAX_CHUNKS x MAX_CHUNKS
local function rectangles(need, list)
    table.sort(list, function(a, b)
        if a[2] ~= b[2] then return a[2] < b[2] end
        return a[1] < b[1]
    end)
    local used, rects = {}, {}
    local function free(cx, cy)
        local k = cx .. "," .. cy
        return need[k] and not used[k]
    end
    for _, c in ipairs(list) do
        local cx, cy = c[1], c[2]
        if free(cx, cy) then
            local w = 1
            while w < MAX_CHUNKS and free(cx + w, cy) do w = w + 1 end
            local h = 1
            while h < MAX_CHUNKS do
                local rowFree = true
                for dx = 0, w - 1 do
                    if not free(cx + dx, cy + h) then rowFree = false; break end
                end
                if not rowFree then break end
                h = h + 1
            end
            for dx = 0, w - 1 do
                for dy = 0, h - 1 do used[(cx + dx) .. "," .. (cy + dy)] = true end
            end
            rects[#rects + 1] = { cx * 8, cy * 8, w * 8, h * 8 }
        end
    end
    return rects
end

local function fixMap(m, mg)
    local need, needList, already = {}, {}, 0
    for _, c in ipairs(m.list) do
        if isTown(mg:getZoneAt(c[1] * 8 + 4, c[2] * 8 + 4, 0)) then
            already = already + 1
        else
            need[c[1] .. "," .. c[2]] = true
            needList[#needList + 1] = c
        end
    end
    local added = 0
    for _, r in ipairs(rectangles(need, needList)) do
        if not mg:getZoneWithBoundsAndType(r[1], r[2], 0, r[3], r[4], "TownZone") then
            getWorld():registerZone("", "TownZone", r[1], r[2], 0, r[3], r[4])
            added = added + 1
        end
    end
    print(TAG .. ": " .. m.dir .. " buildings=" .. m.buildings .. " chunks=" .. #m.list
        .. " alreadyTown=" .. already .. " zonesAdded=" .. added)
    m.chunks, m.list = nil, nil
end

Events.OnLoadedMapZones.Add(function()
    local mg = getWorld():getMetaGrid()
    local owner, maps = cellOwners()
    if #maps == 0 then return end
    print(TAG .. " on")
    collectChunks(mg:getBuildings(), owner)
    for _, m in ipairs(maps) do fixMap(m, mg) end
end)
