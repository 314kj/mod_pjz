-- CookieServerPatch: Daily Challenge System 2.0.4 ([B42]DailyChallengeSystem),
-- no per-square pin scan on players' games. Shared, so the hook is in place
-- before DCS's client files load.
--
-- DCS client/DCS_ObjectOverlay.lua adds a local LoadGridsquare handler that
-- goes through every object on every square that loads (hasModData on each)
-- just to find challenge pins. Driving loads thousands of squares a second.
--
-- Pins are only drawn within 5 tiles of the player, and the same DCS file
-- already rescans a radius of 6 around the player every 60 ticks once the
-- player moves (plus radius 12 a few times after challenges or objects sync).
-- Objects the server places later arrive over the network, not through
-- LoadGridsquare, so those scans are what find them anyway.
--
-- This file keeps that one handler from being added on players' games.
-- Change (OK'd by Pie 8 Nov): a pin can show up to about 1 s later when you
-- walk up to it. The server side (watch list in DCS_ObjectManager) is untouched.
--
-- Log: "[CSP] dcs-lite on" once, then every 10 min "[CSP] dcs-lite: squares skipped=N"
-- To undo: remove this file.

if isServer() then return end

local TAG = "[CSP] dcs-lite"

local function modOn(id)
    local mods = getActivatedMods()
    return mods:contains(id) or mods:contains("\\" .. id)
end

if not modOn("[B42]DailyChallengeSystem") then return end

local ev = Events.LoadGridsquare
local realAdd = ev.Add
local caught = false
local skipped = 0
local nextReport = 0

local function count()
    skipped = skipped + 1
    if skipped % 4096 ~= 0 then return end
    local now = getTimestampMs()
    if now < nextReport then return end
    print(TAG .. ": squares skipped=" .. skipped)
    skipped = 0
    nextReport = now + 600000
end

-- DCS_ObjectOverlay.lua builds its table first and adds the square handler
-- near the end, so the first LoadGridsquare handler added once
-- DCS_ObjectOverlay.refreshAll exists is that one.
ev.Add = function(fn)
    local o = DCS_ObjectOverlay
    if not caught and o and o.refreshAll and o.applyOverlay then
        caught = true
        ev.Add = realAdd
        realAdd(count)
        nextReport = getTimestampMs() + 600000
        print(TAG .. " on")
        return
    end
    return realAdd(fn)
end

Events.OnGameStart.Add(function()
    if caught then return end
    ev.Add = realAdd
    print(TAG .. ": DCS square handler not seen, nothing changed")
end)
