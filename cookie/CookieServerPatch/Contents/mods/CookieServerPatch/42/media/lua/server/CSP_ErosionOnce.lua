-- CookieServerPatch: send each "erosion disableForSquare" only once per square.
--
-- Building Clipboard (BC_World.lua, stopGrass) re-runs its grass repair on every
-- pasted ground tile each time that area loads, and every run broadcasts
-- sendServerCommand("erosion","disableForSquare") to ALL players.
-- Log 25 Oct 2026: 10,189 commands in ~35 min, 400-1,600 per burst, same squares
-- again on every load. Vanilla sends this once, when the floor is built; the
-- square keeps erosion disabled in its save after that.
--
-- This file wraps the global sendServerCommand on the server: the first send for
-- a square goes through as before, repeats are dropped. The set of sent squares
-- is kept in global ModData so restarts don't resend everything.
-- Server only. No next() (Kahlua doesn't have it).

if not isServer() then return end

local MODDATA_KEY = "CookieServerPatch_ErosionSent"
local TAG = "[CookieServerPatch] erosion-once"

local persistent = nil   -- global ModData table, once loaded
local early = {}         -- squares seen before ModData was ready
local stats = { passed = 0, dropped = 0 }
local nextReport = 1

local function seenSet()
    return persistent or early
end

local function onInitGlobalModData()
    persistent = ModData.getOrCreate(MODDATA_KEY)
    local moved = 0
    for k, v in pairs(early) do
        persistent[k] = v
        moved = moved + 1
    end
    early = {}
    local total = 0
    for _ in pairs(persistent) do total = total + 1 end
    print(TAG .. " ready: " .. tostring(total) .. " squares already sent (+" .. tostring(moved) .. " early)")
end
Events.OnInitGlobalModData.Add(onInitGlobalModData)

local originalSend = sendServerCommand
if type(originalSend) ~= "function" then
    print(TAG .. " sendServerCommand not found, patch off")
    return
end

sendServerCommand = function(...)
    local module, command, args = ...
    if module == "erosion" and command == "disableForSquare" and type(args) == "table" then
        local key = tostring(args.x) .. ":" .. tostring(args.y) .. ":" .. tostring(args.z or 0)
        local set = seenSet()
        if set[key] then
            stats.dropped = stats.dropped + 1
            if stats.dropped >= nextReport then
                print(TAG .. " dropped " .. tostring(stats.dropped) .. " repeats, passed " .. tostring(stats.passed))
                nextReport = nextReport * 10
            end
            return
        end
        set[key] = true
        stats.passed = stats.passed + 1
    end
    return originalSend(...)
end

print(TAG .. " on")
