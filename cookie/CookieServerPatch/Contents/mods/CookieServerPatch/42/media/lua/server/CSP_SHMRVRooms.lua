-- CookieServerPatch: Silent Hill Monsters (SilentHillMonsters 0.18.11) puts no
-- new monster in Project RV Interior's room area.
--
-- The server picks each monster's spot from loaded ground-floor squares that
-- have a floor, are free and are far enough from players. RV Interior's rooms
-- are a map of their own far to the south-east, loaded around anyone inside a
-- room; the empty rooms next to it pass that check, so monsters were put among
-- the rooms.
--
-- Here SHM's spot check (SHM_ServerMonsters.engine.safe) answers "not this
-- tile" for squares RV counts as inside its rooms (x > 22500 and y > 12000, the
-- same line RV uses for its Get out menu), only while Project RV Interior is
-- on. SHM then tries its other spots as for any unusable tile; a monster home
-- with no other spot waits for its next respawn time. Everywhere else monsters
-- are placed as before. Monsters already in the room area are not touched.
-- save-bound: no
--
-- Log: "[CSP] shm-rv-rooms on (...)" at server start, then once per run
--   "[CSP] shm-rv-rooms: first spot refused at <x>,<y>".
-- To undo: remove this file.

if not isServer() then return end

local TAG = "[CSP] shm-rv-rooms"
local MIN_X, MIN_Y = 22500, 12000

local CSPSHMRVRooms = {}

function CSPSHMRVRooms.inRooms(square)
    return square:getX() > MIN_X and square:getY() > MIN_Y
end

local installed = false
function CSPSHMRVRooms.install()
    if installed then return end
    installed = true
    local mods = getActivatedMods()
    if not mods or not mods:contains("PROJECTRVInterior42") then
        print(TAG .. ": Project RV Interior off, patch off")
        return
    end
    local E = type(SHM_ServerMonsters) == "table" and SHM_ServerMonsters.engine or nil
    if type(E) ~= "table" or type(E.safe) ~= "function" then
        print(TAG .. ": Silent Hill Monsters spot check not found, patch off")
        return
    end
    local orig = E.safe
    local said = false
    E.safe = function(square, ...)
        if square and CSPSHMRVRooms.inRooms(square) then
            if not said then
                said = true
                print(TAG .. ": first spot refused at " .. square:getX() .. "," .. square:getY())
            end
            return false, "tile"
        end
        return orig(square, ...)
    end
    print(TAG .. " on (room area x > " .. MIN_X .. ", y > " .. MIN_Y .. ")")
end

Events.OnServerStarted.Add(CSPSHMRVRooms.install)

return CSPSHMRVRooms
