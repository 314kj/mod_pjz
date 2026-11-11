-- CookieEarlyHooks (part of CookieServerPatch): REVIVAL (JaxeRevival 1.5.3)
-- zombie handler, cheaper. Shared.
--
-- Revival's shared/JaxeRevival/State.lua adds a local OnZombieUpdate handler.
-- On a player's game it runs for every zombie, every frame:
--   isServer(), zombie:getTarget(), and unless the zombie is after a standing
--   player: zombie:setEatBodyTarget(nil, true) + zombie:setTarget(nil).
-- On the server it only calls isServer() for every zombie and returns.
--
-- In the 42.21 IsoZombie class both setters do nothing when the value is
-- already nil, so for an idle zombie all those calls are wasted. This file
-- takes Revival's handler out and adds one that looks first and only calls a
-- setter when there is something to clear. On the server nothing is added.
-- Zombies behave exactly as with Revival's own handler (they still never eat
-- bodies or keep a non-player target on the machine that runs them).
--
-- Load order: B42 loads Lua mod by mod in mod-list order (8 Nov log:
-- JaxeRevival #105, CookieServerPatch #206), so this lives in its own small
-- mod that sits above REVIVAL in the list (loadModBefore=\JaxeRevival).
-- If Revival still got there first, nothing is changed and the log says so.
--
-- Log: "[CSP] revival-lite on" once, then every 10 min
--      "[CSP] revival-lite: calls=.. idle=.. cleared=.. player=.."
--      (idle = zombies where Revival would have made 2 setter calls for nothing)
-- If the new handler ever stops halfway (error), Revival's own handler is put
-- back and "[CSP] revival-lite: error, back to Revival's handler" is printed once.
-- To undo: remove this file.

local TAG = "[CSP] revival-lite"

local function modOn(id)
    local mods = getActivatedMods()
    return mods:contains(id) or mods:contains("\\" .. id)
end

if not modOn("JaxeRevival") then return end

if JaxeRevival and JaxeRevival.State then
    print(TAG .. ": Revival loaded before this file, nothing changed")
    return
end

local ev = Events.OnZombieUpdate
local realAdd = ev.Add
local original
local busy = false
local calls, idle, cleared, player = 0, 0, 0, 0
local nextReport = 0

local function report()
    local now = getTimestampMs()
    if now < nextReport then return end
    if nextReport > 0 then
        print(TAG .. ": calls=" .. calls .. " idle=" .. idle .. " cleared=" .. cleared .. " player=" .. player)
        calls, idle, cleared, player = 0, 0, 0, 0
    end
    nextReport = now + 600000
end

local lite

local function backToOriginal()
    ev.Remove(lite)
    realAdd(original)
    print(TAG .. ": error, back to Revival's handler")
end

lite = function(zombie)
    if busy then
        -- the last call never reached the end
        busy = false
        backToOriginal()
        original(zombie)
        return
    end
    busy = true
    calls = calls + 1

    local target = zombie:getTarget()
    if target then
        if instanceof(target, "IsoPlayer") and not JaxeRevival.Incapacitation.isActive(target) then
            player = player + 1
        else
            zombie:setEatBodyTarget(nil, true)
            zombie:setTarget(nil)
            cleared = cleared + 1
        end
    elseif zombie:getEatBodyTarget() then
        zombie:setEatBodyTarget(nil, true)
        cleared = cleared + 1
    else
        idle = idle + 1
    end

    if calls % 4096 == 0 then report() end
    busy = false
end

local function install()
    ev.Add = realAdd
    if isServer() then
        print(TAG .. " on (server: Revival's zombie handler removed, it only returned here)")
        return
    end
    realAdd(lite)
    report()
    print(TAG .. " on")
end

-- Revival's State.lua defines its functions first and adds the zombie
-- handler on its last line, so the first OnZombieUpdate handler added after
-- JaxeRevival.State.getMaxRecovery exists is Revival's.
ev.Add = function(fn)
    if not original and JaxeRevival and JaxeRevival.State and JaxeRevival.State.getMaxRecovery then
        original = fn
        install()
        return
    end
    return realAdd(fn)
end

Events.OnGameBoot.Add(function()
    if original then return end
    ev.Add = realAdd
    print(TAG .. ": Revival's zombie handler not seen, nothing changed")
end)
