-- CookieServerPatch: Building Clipboard room guard. Client side.
--
-- Problem (42.21 MP, Building Clipboard 1.9.4, 30 Oct 2026):
--  Game crashes back to the main menu while loading the map near pasted
--  buildings: IsoLightSwitch.chunkLoaded -> IsoRoom.hasLightSwitches,
--  "this.def is null". Seen with and without PZ Optimization.
--  Building Clipboard's own notes (BC_Client.lua): changing room definitions
--  retires the old live rooms (their def becomes nil). A chunk that was loading
--  in the background at that moment still points its squares at the retired
--  room, and the game crashes when the chunk is placed. 1.9.4 waits for nearby
--  chunks to finish loading before it removes rooms, but the game also rebuilds
--  its own stand-in rooms for built walls, and chunks keep loading while driving.
--
-- Fix: when a square loads pointing at a retired room, point it at the room the
--  map has there now (same repair Building Clipboard's refreshRoomSquares does
--  for squares that are already loaded). Nothing else is changed.
--
-- Diagnostics (log only, nothing changed):
--  * every Building Clipboard room change on this game (addRooms / removeRooms /
--    reconcileRooms) is logged with its position and whether the map near the
--    player was still loading, so a crash right after one can be traced.
--  * whether Building Clipboard's saved room list for this server was found when
--    the map loaded (1.9.4 prints "Put in N pasted building(s)" only when it is),
--    and whether the list's file name is still the same once in game.
--
-- Log lines start with "[CookieServerPatch] bc-room-guard".

if isServer() then return end

local TAG = "[CookieServerPatch] bc-room-guard"
local MAX_REPAIR_LINES = 20
local MAX_BC_LINES = 40
local repairLines = 0
local bcLines = 0
local fixed = 0

-- ---------------------------------------------------------------------------
-- Repair squares that load pointing at a retired room.

local function repair(square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local rd = getWorld():getMetaGrid():getRoomAt(x, y, z)
    local live = nil
    if rd then live = rd:getIsoRoom() end
    if rd then square:setRoomID(rd:getID()) else square:setRoomID(-1) end
    square:setRoom(live)
    if live then live:addSquare(square) end
    square:RecalcAllWithNeighbours(true)
    fixed = fixed + 1
    if repairLines < MAX_REPAIR_LINES then
        repairLines = repairLines + 1
        local what = "no room"
        if live then what = "room " .. tostring(rd:getID()) end
        print(TAG .. ": repaired retired room at " .. x .. "," .. y .. "," .. z .. " -> " .. what .. " (total " .. fixed .. ")")
    end
end

Events.LoadGridsquare.Add(function(square)
    if not square then return end
    local room = square:getRoom()
    if room and room:getRoomDef() == nil then
        local ok, err = pcall(repair, square)
        if not ok and repairLines < MAX_REPAIR_LINES then
            repairLines = repairLines + 1
            print(TAG .. ": repair failed: " .. tostring(err))
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Log Building Clipboard room changes.

local function firstRect(rooms, ox, oy)
    if type(rooms) ~= "table" then return "?" end
    for _, r in ipairs(rooms) do
        if type(r) == "table" and type(r.rects) == "table" and r.rects[1] then
            local q = r.rects[1]
            return tostring((ox or 0) + (q.x or 0)) .. "," .. tostring((oy or 0) + (q.y or 0)) .. "," .. tostring(r.z)
        end
    end
    return "none"
end

local function mapLoading()
    local B = BuildingClipboard
    if not B or type(B.loadingAreas) ~= "function" then return "?" end
    local ok, areas = pcall(B.loadingAreas)
    if not ok or type(areas) ~= "table" then return "?" end
    for _, a in ipairs(areas) do
        if a.loading then return "yes" end
    end
    return "no"
end

local function logBC(what, where)
    if bcLines >= MAX_BC_LINES then return end
    bcLines = bcLines + 1
    local loading = "?"
    pcall(function() loading = mapLoading() end)
    print(TAG .. ": BC " .. what .. " at " .. where .. " (map near player still loading: " .. loading .. ")")
end

local function wrapBC()
    local B = BuildingClipboard
    if not B then
        print(TAG .. ": Building Clipboard not loaded, room-change log off")
        return
    end
    if B.CSP_RoomLogWrapped then return end
    B.CSP_RoomLogWrapped = true
    local addRooms, removeRooms, reconcileRooms = B.addRooms, B.removeRooms, B.reconcileRooms
    if type(addRooms) == "function" then
        B.addRooms = function(rooms, x, y)
            pcall(logBC, "addRooms", firstRect(rooms, x, y))
            return addRooms(rooms, x, y)
        end
    end
    if type(removeRooms) == "function" then
        B.removeRooms = function(x, y, rooms)
            pcall(logBC, "removeRooms", firstRect(rooms, x, y))
            return removeRooms(x, y, rooms)
        end
    end
    if type(reconcileRooms) == "function" then
        B.reconcileRooms = function(before, after)
            pcall(logBC, "reconcileRooms", firstRect(before) .. " -> " .. firstRect(after))
            return reconcileRooms(before, after)
        end
    end
end
wrapBC()

-- ---------------------------------------------------------------------------
-- Building Clipboard's saved room list (same file name rule as BC_Client.lua).

local function bcListName()
    local function s(v) return (tostring(v or ""):gsub("[^%w]", "_")) end
    local ok, name = pcall(function()
        return "BuildingClipboard_rooms_" .. s(getServerIP()) .. "_" .. s(getServerPort()) .. "_" .. s(getServerName()) .. ".txt"
    end)
    if ok then return name end
    return nil
end

local function listExists(name)
    if not name then return false end
    local reader = nil
    pcall(function() reader = getFileReader(name, false) end)
    if reader then
        pcall(function() reader:close() end)
        return true
    end
    return false
end

local nameAtLoad = nil
Events.OnLoadedMapZones.Add(function()
    if not isClient() then return end
    nameAtLoad = bcListName()
    local found = "missing"
    if listExists(nameAtLoad) then found = "found" end
    print(TAG .. ": BC saved room list at map load: " .. found .. " (" .. tostring(nameAtLoad) .. ")")
end)

local checkAt = nil
Events.OnGameStart.Add(function()
    if isClient() then checkAt = getTimestampMs() + 60000 end
end)
Events.OnTick.Add(function()
    if not checkAt or getTimestampMs() < checkAt then return end
    checkAt = nil
    local now = bcListName()
    local found = "missing"
    if listExists(now) then found = "found" end
    local same = "same name as at map load"
    if now ~= nameAtLoad then same = "DIFFERENT name from map load (" .. tostring(nameAtLoad) .. ")" end
    print(TAG .. ": BC saved room list 1 min in game: " .. found .. " (" .. tostring(now) .. ") - " .. same)
end)

print(TAG .. " on")
