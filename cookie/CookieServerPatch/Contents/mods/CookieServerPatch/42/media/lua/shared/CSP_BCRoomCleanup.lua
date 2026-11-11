-- CookieServerPatch: clean up Building Clipboard room numbers after the mod is removed.
--
-- Squares in pasted buildings keep the number of the room Building Clipboard made
-- for them. Once the mod is gone that room no longer exists, so the square points
-- at nothing (the game then fails every frame in IsoTree.isPlayerInsideARoom and
-- logs "invalid room metaID"). When a square loads pointing at a room the map does
-- not have, set it back to "no room" so the game treats the building like a
-- player-built one.
--
-- Does nothing while Building Clipboard is loaded (its rooms are real then).
-- Logs "bc-room-cleanup on" at start and the number of squares fixed (once a minute).

local TAG = "[CookieServerPatch] bc-room-cleanup"

if BuildingClipboard ~= nil then
    print(TAG .. " off (Building Clipboard is loaded)")
    return
end

local fixed, reported = 0, 0

local function roomExists(id)
    local ok, def = pcall(function() return getWorld():getMetaGrid():getRoomByID(id) end)
    if not ok then return true end -- cannot tell: leave the square alone
    return def ~= nil
end

Events.LoadGridsquare.Add(function(square)
    if not square then return end
    local id = square:getRoomID()
    if id == nil or id == -1 then return end
    if roomExists(id) then return end
    local ok = pcall(function()
        square:setRoomID(-1)
        square:setRoom(nil)
    end)
    if ok then fixed = fixed + 1 end
end)

Events.EveryOneMinute.Add(function()
    if fixed ~= reported then
        reported = fixed
        print(TAG .. ": " .. fixed .. " square(s) pointed at a room that no longer exists - set to no room")
    end
end)

print(TAG .. " on")
