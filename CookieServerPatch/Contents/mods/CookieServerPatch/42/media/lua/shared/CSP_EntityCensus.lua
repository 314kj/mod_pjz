-- CookieServerPatch: entity census (diagnostic, server only, log-only).
--
-- The profiler (26 Oct) showed the server spends most of its lag time removing
-- "entities" one by one when map areas unload. This counts which objects in
-- loaded areas are entities (have a SpriteConfig component), by type, so we
-- know what to fix. It changes nothing in the world.
--
-- Every 10 minutes it prints to server-console:
--   [CookieServerPatch] census: squares=N objects=N entities=N (unique squares since boot)
--   [CookieServerPatch] census top: <type> = <count> ...
-- Each square is counted once per boot; reloads are counted separately.
-- Remove this file once we have the numbers. No next() (Kahlua).

if not isServer() then return end

local TAG = "[CookieServerPatch] census"
local REPORT_MS = 10 * 60 * 1000

local seen = {}          -- "x:y:z" -> true
local byType = {}        -- type -> unique entity objects
local reloadsByType = {} -- type -> entity objects seen again on a later load
local stats = { squares = 0, objects = 0, entities = 0, reloads = 0 }
local api = { spriteConfig = true, fullType = true }
local nextReport = 0

local function entityType(obj)
    if api.fullType then
        local ok, t = pcall(function() return obj:getEntityFullTypeDebug() end)
        if ok and type(t) == "string" and t ~= "" then return t end
        if not ok then api.fullType = false end
    end
    local okS, name = pcall(function() return obj:getSprite():getName() end)
    if okS and type(name) == "string" then
        local base = string.match(name, "^(.*)_%d+$")
        return "sprite:" .. (base or name)
    end
    return "unknown"
end

local function isEntity(obj)
    if not api.spriteConfig then return false end
    local ok, sc = pcall(function() return obj:getSpriteConfig() end)
    if not ok then
        api.spriteConfig = false
        print(TAG .. " getSpriteConfig() not available - census off")
        return false
    end
    return sc ~= nil
end

local function onLoadGridsquare(square)
    if not square or not api.spriteConfig then return end
    local key = square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
    local first = not seen[key]
    if first then
        seen[key] = true
        stats.squares = stats.squares + 1
    end
    local objects = square:getObjects()
    if not objects then return end
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if first then stats.objects = stats.objects + 1 end
        if obj and isEntity(obj) then
            local t = entityType(obj)
            if first then
                stats.entities = stats.entities + 1
                byType[t] = (byType[t] or 0) + 1
            else
                stats.reloads = stats.reloads + 1
                reloadsByType[t] = (reloadsByType[t] or 0) + 1
            end
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

local function report()
    print(TAG .. ": squares=" .. stats.squares .. " objects=" .. stats.objects ..
        " entities=" .. stats.entities .. " entityReloads=" .. stats.reloads ..
        " (api spriteConfig=" .. tostring(api.spriteConfig) .. " fullType=" .. tostring(api.fullType) .. ")")
    print(TAG .. " top: " .. top(byType, 15))
    print(TAG .. " top reloads: " .. top(reloadsByType, 10))
end

local function onTick()
    local now = getTimestampMs()
    if nextReport == 0 then nextReport = now + REPORT_MS return end
    if now >= nextReport then
        nextReport = now + REPORT_MS
        report()
    end
end

Events.LoadGridsquare.Add(onLoadGridsquare)
Events.OnTick.Add(onTick)
print(TAG .. " on (report every 10 min)")
