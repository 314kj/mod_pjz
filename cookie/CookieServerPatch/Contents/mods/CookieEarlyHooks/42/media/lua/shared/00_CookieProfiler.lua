-- Cookie Profiler (part of Cookie - Server Patches, in the CookieEarlyHooks mod)
--
-- Measures how much time each mod's Lua takes, so we know which mods make the
-- game stutter (for example while driving, when the map loads square by square).
-- It changes nothing in the game. It is OFF unless a flag file exists.
--
-- Turn on (then restart the game, or the server for the server side):
--   client: create  Zomboid\Lua\CookieProfile_client.txt  (empty file is fine)
--   server: create  Zomboid\Lua\CookieProfile_server.txt  in the server's Zomboid folder
-- Turn off: delete the file and restart.
--
-- Output (every minute, in the same Zomboid\Lua folder):
--   CookieProfile_<side>_report.txt   ranking since start (by mod, by handler, by event)
--   CookieProfile_<side>_minutes.txt  one line per minute: fps, moved tiles, time in a
--                                     vehicle, top mods that minute
--
-- What is measured:
--   - every function a mod adds with Events.<Name>.Add after this file has loaded
--     (keep CookieEarlyHooks at the TOP of the mod list so all mods load after it)
--   - client: render / prerender / update of every class with a Type field
--     (UI windows, HUD, timed actions), including vanilla ones
-- Not measured: vanilla event handlers (they load before any mod).
-- Clock times in the files are UTC (Thailand = UTC+7).
-- Times are "self" time: when a measured function calls another measured one,
-- the inner time is counted for the inner one only.
-- Timer: Java millisecond clock. Single calls are below 1 ms, but the sum over
-- many calls is right on average; the report shows the clock step.
-- While on, a Lua error inside a measured function also shows this file in the
-- stack trace (one extra line); the error itself comes from the mod above it.

local SIDE = "client"
if isServer and isServer() then SIDE = "server" end
local FLAG = "CookieProfile_" .. SIDE .. ".txt"
local REPORT = "CookieProfile_" .. SIDE .. "_report.txt"
local MINUTES = "CookieProfile_" .. SIDE .. "_minutes.txt"
-- The same file is in the Cookie Slicer mod (it is moving there from CSP); only
-- this line differs. Whichever copy loads first measures, the other does nothing.
local OWNER = "CookieEarlyHooks"
local TAG = (OWNER == "CookieSlicer" and "[CookieSlicer]" or "[CookieServerPatch]") .. " profiler"

local function flagOn()
    if not getFileReader then return false end
    local ok, r = pcall(getFileReader, FLAG, false)
    if ok and r then
        pcall(function() r:close() end)
        return true
    end
    return false
end

if not Events or not getTimestampMs or not flagOn() then
    return
end
if CookieProfiler ~= nil then
    print(TAG .. ": already loaded by " .. tostring(CookieProfiler.owner) .. ", this copy does nothing")
    return
end

local now = getTimestampMs
local floor = math.floor

-- ------------------------------------------------------------------ helpers
local function r1(x) return floor(x * 10 + 0.5) / 10 end
local function r2(x) return floor(x * 100 + 0.5) / 100 end
local function pad(s, n)
    s = tostring(s)
    if #s < n then return s .. string.rep(" ", n - #s) end
    return s
end
local function lpad(s, n)
    s = tostring(s)
    if #s < n then return string.rep(" ", n - #s) .. s end
    return s
end
-- Largest n items of list by key(item), largest first. Avoids table.sort
-- (Kahlua's table.sort is a recursive quicksort that degrades on equal values).
local function topN(list, n, key)
    local out = {}
    for i = 1, #list do
        local it = list[i]
        local v = key(it)
        local cnt = #out
        if cnt < n or v > key(out[cnt]) then
            local pos = cnt + 1
            while pos > 1 and key(out[pos - 1]) < v do
                out[pos] = out[pos - 1]
                pos = pos - 1
            end
            out[pos] = it
            if #out > n then out[#out] = nil end
        end
    end
    return out
end

-- os.date in Kahlua gives UTC
local function clock()
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M")
    if ok and s then return s .. " UTC" end
    return ""
end
local function hhmm()
    local ok, s = pcall(os.date, "%H:%M")
    if ok and s then return s .. "z" end
    return ""
end

-- Millisecond step of the Java clock (1 ms on most PCs, 15-16 ms on some).
local function measureStep()
    local best = nil
    local last = now()
    local changes, iter = 0, 0
    while changes < 4 and iter < 2000000 do
        local t = now()
        if t ~= last then
            if changes > 0 then
                local d = t - last
                if not best or d < best then best = d end
            end
            changes = changes + 1
            last = t
        end
        iter = iter + 1
    end
    return best or 0
end

-- Where a function comes from: mod folder, workshop id, client/server/shared, file, line.
local function describe(fn)
    local file, line = "?", 0
    if getFilenameOfClosure then
        local ok, f = pcall(getFilenameOfClosure, fn)
        if ok and f then file = tostring(f) end
    end
    if getFirstLineOfClosure then
        local ok, l = pcall(getFirstLineOfClosure, fn)
        if ok and l then line = l end
    end
    local p = string.gsub(file, "\\", "/")
    local wid = string.match(p, "/108600/(%d+)/") or ""
    local mod = string.match(p, "/mods/([^/]+)/")
    if not mod then
        if string.match(p, "media/lua/") then mod = "vanilla" else mod = "?" end
    end
    local side = string.match(p, "/media/lua/(%a+)/") or "?"
    local base = string.match(p, "([^/]+)$") or p
    return mod, wid, side, base, line
end

-- ------------------------------------------------------------------ stats
local stats = {}      -- key -> record
local statList = {}   -- array of records
local MOVING = false
local depth = 0
local childMs = {}

-- Other Cookie files can say "count this function as that mod's":
-- CookieProfiler.alias[fn] = { fn = original, tag = "lite" }
CookieProfiler = { alias = {}, owner = OWNER }

local function statFor(label, fn)
    local src = CookieProfiler.alias[fn]
    local mod, wid, side, base, line = describe(src and src.fn or fn)
    if src and src.tag then base = base .. " (" .. src.tag .. ")" end
    local key = label .. "|" .. mod .. "|" .. base .. ":" .. tostring(line)
    local s = stats[key]
    if not s then
        s = { ev = label, mod = mod, wid = wid, side = side, file = base, line = line,
              c = 0, m = 0, mx = 0, mv = 0, st = 0, c0 = 0, m0 = 0 }
        stats[key] = s
        statList[#statList + 1] = s
    end
    return s
end

-- Wrap one function. Results are passed through (up to 4 values).
local function wrap(label, fn)
    local s = statFor(label, fn)
    return function(...)
        depth = depth + 1
        local my = depth
        childMs[my] = 0
        local t0 = now()
        local a, b, c, d = fn(...)
        local dt = now() - t0
        local own = dt - childMs[my]
        depth = my - 1
        if depth > 0 then childMs[depth] = childMs[depth] + dt end
        s.c = s.c + 1
        if own > 0 then
            s.m = s.m + own
            if MOVING then s.mv = s.mv + own else s.st = s.st + own end
        end
        if dt > s.mx then s.mx = dt end
        return a, b, c, d
    end
end
CookieProfiler.wrap = wrap

-- ------------------------------------------------------------------ Events.*.Add
local patched = {}
local patchedCount = 0
local wrappedCount = 0

local function patchEvent(name, ev)
    if type(ev) ~= "table" or patched[ev] then return end
    local add = rawget(ev, "Add")
    local remove = rawget(ev, "Remove")
    if not add or not remove then return end
    patched[ev] = { add = add, remove = remove }
    patchedCount = patchedCount + 1
    local map = {}
    rawset(ev, "Add", function(fn, ...)
        if type(fn) ~= "function" then return add(fn, ...) end
        local w = map[fn]
        if not w then
            w = wrap(name, fn)
            map[fn] = w
            wrappedCount = wrappedCount + 1
        end
        return add(w)
    end)
    rawset(ev, "Remove", function(fn, ...)
        local w = nil
        if type(fn) == "function" then w = map[fn] end
        if w then return remove(w) end
        return remove(fn, ...)
    end)
end

local function patchAllEvents()
    for name, ev in pairs(Events) do
        patchEvent(name, ev)
    end
end

-- our own handlers use the original Add so they are not measured
local origTickAdd = rawget(Events.OnTick, "Add")
local origBootAdd = Events.OnGameBoot and rawget(Events.OnGameBoot, "Add")
local origStartAdd = Events.OnGameStart and rawget(Events.OnGameStart, "Add")

patchAllEvents()

-- ------------------------------------------------------------------ class methods (client)
local METHODS = { "prerender", "render", "update" }
local classWrapped = {}

local function scanClasses()
    if SIDE ~= "client" then return 0 end
    local n = 0
    for _, t in pairs(_G) do
        if type(t) == "table" and type(rawget(t, "Type")) == "string" then
            for i = 1, #METHODS do
                local m = METHODS[i]
                local f = rawget(t, m)
                if type(f) == "function" and not classWrapped[f] then
                    -- vanilla update() runs ~17k times a second and is cheap;
                    -- measuring it costs more than it tells
                    if m == "update" and describe(f) == "vanilla" then
                        classWrapped[f] = true
                    else
                        local w = wrap("class " .. m, f)
                        classWrapped[w] = true
                        rawset(t, m, w)
                        n = n + 1
                    end
                end
            end
        end
    end
    return n
end

-- ------------------------------------------------------------------ session counters
local step = measureStep()
local startMs = now()
local startClock = clock()
local frames, framesMin = 0, 0
local movedTiles, movedMin = 0, 0
local vehSec, vehSecMin = 0, 0
local moveSec, standSec = 0, 0
local lastSecond = startMs
local lastMinute = startMs
local lastX, lastY = nil, nil

local function writeLines(name, lines, append)
    local ok, w = pcall(getFileWriter, name, true, append)
    if not ok or not w then return false end
    for i = 1, #lines do w:writeln(lines[i]) end
    w:close()
    return true
end

local function modTotals(field)
    local byMod, list = {}, {}
    for i = 1, #statList do
        local s = statList[i]
        local v = s[field]
        if v > 0 then
            local k = s.mod
            local t = byMod[k]
            if not t then
                t = { mod = s.mod, wid = s.wid, ms = 0, ev = {} }
                byMod[k] = t
                list[#list + 1] = t
            end
            t.ms = t.ms + v
            t.ev[s.ev] = (t.ev[s.ev] or 0) + v
        end
    end
    return list
end

local function topEvents(t, n)
    local evs = {}
    for k, v in pairs(t.ev) do evs[#evs + 1] = { k = k, v = v } end
    evs = topN(evs, n, function(e) return e.v end)
    local out = {}
    for i = 1, #evs do out[#out + 1] = evs[i].k end
    return table.concat(out, ", ")
end

local function writeReport()
    local t = now()
    local runMs = math.max(1, t - startMs)
    local runMin = runMs / 60000
    local moveMs = math.max(1, moveSec * 1000)
    local standMs = math.max(1, standSec * 1000)
    local L = {}
    L[#L + 1] = "Cookie profiler (" .. SIDE .. ") - " .. OWNER
    L[#L + 1] = "started " .. startClock .. "   running " .. r1(runMin) .. " min   clock step " .. tostring(step) .. " ms"
    L[#L + 1] = "frames/s avg " .. r1(frames / (runMs / 1000)) .. "   events patched " .. patchedCount .. "   functions measured " .. #statList
    if SIDE == "client" then
        L[#L + 1] = "moving " .. r1(moveSec / 60) .. " min (vehicle " .. r1(vehSec / 60) .. " min)   standing " .. r1(standSec / 60) .. " min   moved " .. floor(movedTiles) .. " tiles"
    end
    L[#L + 1] = "% core = share of one CPU core (the game's main thread). move% / stand% = same, only while moving / standing."
    L[#L + 1] = "Not measured: vanilla event handlers, and mods that load before " .. OWNER .. "."
    L[#L + 1] = ""

    local total = 0
    for i = 1, #statList do total = total + statList[i].m end
    L[#L + 1] = "Measured Lua in total: " .. r1(total / runMs * 100) .. "% core"
    L[#L + 1] = ""

    L[#L + 1] = "== By mod =="
    L[#L + 1] = lpad("%core", 7) .. lpad("move%", 7) .. lpad("stand%", 7) .. "  " .. pad("mod", 34) .. pad("workshop", 12) .. "biggest events"
    local mods = topN(modTotals("m"), 40, function(m) return m.ms end)
    local mv, st = {}, {}
    for i = 1, #statList do
        local s = statList[i]
        mv[s.mod] = (mv[s.mod] or 0) + s.mv
        st[s.mod] = (st[s.mod] or 0) + s.st
    end
    for i = 1, #mods do
        local m = mods[i]
        L[#L + 1] = lpad(r2(m.ms / runMs * 100), 7) .. lpad(r2((mv[m.mod] or 0) / moveMs * 100), 7) .. lpad(r2((st[m.mod] or 0) / standMs * 100), 7)
            .. "  " .. pad(m.mod, 34) .. pad(m.wid, 12) .. topEvents(m, 3)
    end
    L[#L + 1] = ""

    L[#L + 1] = "== Top functions =="
    L[#L + 1] = lpad("%core", 7) .. lpad("move%", 7) .. lpad("calls/s", 9) .. lpad("max ms", 8) .. "  " .. pad("event", 24) .. pad("mod", 30) .. pad("side", 7) .. "file:line"
    local sorted = {}
    for i = 1, #statList do if statList[i].m > 0 then sorted[#sorted + 1] = statList[i] end end
    sorted = topN(sorted, 60, function(x) return x.m end)
    for i = 1, #sorted do
        local s = sorted[i]
        L[#L + 1] = lpad(r2(s.m / runMs * 100), 7) .. lpad(r2(s.mv / moveMs * 100), 7) .. lpad(r1(s.c / (runMs / 1000)), 9) .. lpad(s.mx, 8)
            .. "  " .. pad(s.ev, 24) .. pad(s.mod, 30) .. pad(s.side, 7) .. s.file .. ":" .. tostring(s.line)
    end
    L[#L + 1] = ""

    L[#L + 1] = "== By event =="
    local byEv, evList = {}, {}
    for i = 1, #statList do
        local s = statList[i]
        local e = byEv[s.ev]
        if not e then e = { ev = s.ev, ms = 0, c = 0, n = 0 }; byEv[s.ev] = e; evList[#evList + 1] = e end
        e.ms = e.ms + s.m; e.c = e.c + s.c; e.n = e.n + 1
    end
    evList = topN(evList, 40, function(e) return e.ms end)
    for i = 1, #evList do
        local e = evList[i]
        if e.ms > 0 then
            L[#L + 1] = lpad(r2(e.ms / runMs * 100), 7) .. "  " .. pad(e.ev, 28) .. "functions " .. e.n .. "   calls/s " .. r1(e.c / (runMs / 1000))
        end
    end
    writeLines(REPORT, L, false)
end

local function writeMinute()
    local t = now()
    local spanMs = math.max(1, t - lastMinute)
    local byMod, list = {}, {}
    for i = 1, #statList do
        local s = statList[i]
        local dm = s.m - s.m0
        s.m0 = s.m
        s.c0 = s.c
        if dm > 0 then
            local k = s.ev .. "/" .. s.mod
            local e = byMod[k]
            if not e then e = { k = k, ms = 0 }; byMod[k] = e; list[#list + 1] = e end
            e.ms = e.ms + dm
        end
    end
    local total = 0
    for i = 1, #list do total = total + list[i].ms end
    list = topN(list, 8, function(e) return e.ms end)
    local parts = {}
    for i = 1, #list do
        parts[#parts + 1] = list[i].k .. " " .. r1(list[i].ms / spanMs * 100) .. "%"
    end
    local head = hhmm() .. " fps " .. r1(framesMin / (spanMs / 1000)) .. " lua " .. r1(total / spanMs * 100) .. "%"
    if SIDE == "client" then
        head = head .. " moved " .. floor(movedMin) .. " vehicle " .. vehSecMin .. "s"
    else
        local n = 0
        if getOnlinePlayers then
            local ok, p = pcall(getOnlinePlayers)
            if ok and p then n = p:size() end
        end
        head = head .. " players " .. n
    end
    writeLines(MINUTES, { head .. " | " .. table.concat(parts, " | ") }, true)
    framesMin, movedMin, vehSecMin = 0, 0, 0
    lastMinute = t
end

-- ------------------------------------------------------------------ per-tick bookkeeping
local function everySecond()
    if SIDE ~= "client" or not getPlayer then
        standSec = standSec + 1
        return
    end
    local p = getPlayer()
    local moved = 0
    local inVehicle = false
    if p then
        local x, y = p:getX(), p:getY()
        if lastX then
            local dx, dy = x - lastX, y - lastY
            local d = math.sqrt(dx * dx + dy * dy)
            if d < 300 then moved = d end   -- ignore teleports
        end
        lastX, lastY = x, y
        inVehicle = p:getVehicle() ~= nil
    end
    movedTiles = movedTiles + moved
    movedMin = movedMin + moved
    if inVehicle then vehSec = vehSec + 1; vehSecMin = vehSecMin + 1 end
    MOVING = inVehicle or moved > 2
    if MOVING then moveSec = moveSec + 1 else standSec = standSec + 1 end
end

local function onTick()
    depth = 0            -- a Lua error inside a measured function can leave depth > 0
    frames = frames + 1
    framesMin = framesMin + 1
    local t = now()
    if t - lastSecond >= 1000 then
        lastSecond = t
        everySecond()
    end
    if t - lastMinute >= 60000 then
        patchAllEvents()  -- events a mod created at runtime
        scanClasses()     -- class methods replaced at runtime
        writeMinute()
        writeReport()
    end
end

origTickAdd(onTick)

local function onStart()
    local n = scanClasses()
    print(TAG .. ": class methods measured " .. n)
end
if SIDE == "client" and origStartAdd then
    origStartAdd(onStart)
end
if origBootAdd then
    origBootAdd(function()
        print(TAG .. ": " .. wrappedCount .. " functions added so far")
    end)
end

writeLines(MINUTES, { "", "== session " .. startClock .. " (" .. SIDE .. ") clock step " .. tostring(step) .. " ms ==" }, true)
print(TAG .. " on (" .. SIDE .. "): events patched " .. patchedCount .. ", clock step " .. tostring(step) .. " ms, report every minute in Zomboid/Lua/" .. REPORT)
