-- Cookie Pace (part of Cookie Slicer), players' games only.
--
-- Some mods run Lua for every zombie every frame (OnZombieUpdate) or run Lua every
-- frame (OnTick). For a zombie far away that nobody looks at, doing that work every
-- frame changes nothing a player can see. Cookie Pace runs a LISTED handler less often:
--   OnZombieUpdate, per zombie:
--     within NEAR (12) tiles of a player in this game     every update
--     on screen                                            1 frame in 3
--     off screen                                           1 frame in 7
--     off screen while more than CROWD (300) are loaded    1 frame in 15
--     zombies take turns by the game's object id (and each listed handler has its own
--     turn), so every frame only a share of them run it; nothing is kept per zombie.
--     The counts are odd on purpose: the game itself may update a zombie only every
--     2nd / 4th / 8th / 16th frame, in a fixed slot taken from the same object id
--     (MovingObjectUpdateScheduler). With 8 or 16 here most of those zombies would
--     never get their turn; with an odd count every zombie does, every 3 / 7 / 15 of
--     its own updates (so a handler on the list must be fine waiting several seconds,
--     up to about 8 s at 30 fps, for a zombie off screen).
--   OnTick: at most once every entry.ms
-- Only the handlers in LIST run less often, matched by mod folder, the end of the file
-- path and the function's first line (the file:line the Cookie Profiler report shows).
-- Every other handler runs exactly as before.
--
-- Before adding a handler, read it. It must NOT move a zombie, change its speed /
-- target / animation, send packets or change a value the game syncs: players would
-- see zombies jump or see different things. It must not count frames or add up time
-- per call either. When the mod updates, its line moves and the entry simply stops
-- matching (the log at game start says which entries matched): read it again.
--
-- Off for everyone: sandbox Cookie Slicer > Pace listed mod handlers. Off in this game
-- only (admins, to measure with / without, back on at the next start): the switch on
-- the Speed Slicer page, which also shows how many zombie updates fall in each band.
-- Log: "[CookieSlicer] pace: ...".

local TAG = "[CookieSlicer] pace"
if isServer and isServer() then return end
if CookiePace ~= nil then return end
if not Events or not getTimestampMs then return end
local evZ, evT = Events.OnZombieUpdate, Events.OnTick
if not evZ or not evT or not rawget(evZ, "Add") or not rawget(evZ, "Remove")
        or not rawget(evT, "Add") or not rawget(evT, "Remove") then
    return
end

local NEAR = 12           -- tiles
local EVERY_SEEN = 3      -- odd (see above)
local EVERY_UNSEEN = 7
local EVERY_CROWD = 15
local CROWD = 300         -- zombies loaded in this game
local TICK_MS = 100       -- OnTick entries without ms

-- { ev = "OnZombieUpdate", mod = "<mod folder>", file = "<end of the path>", line = <n>, why = "<what it does>" }
-- { ev = "OnTick", mod = "<mod folder>", file = "<end of the path>", line = <n>, ms = <n>, why = "<what it does>" }
-- Only functions the mod adds once (a named / module function). A handler made anew each
-- time it is added would get a new record every time.
local LIST = {
}

local function norm(s)
    return string.lower((string.gsub(tostring(s or ""), "[%s_%-]", "")))
end

local function prepare(e)
    e.key = norm(e.mod)
    e.tail = "/" .. string.gsub(tostring(e.file or ""), "\\", "/")
    return e
end
for _, e in ipairs(LIST) do prepare(e) end

-- mod folder (normalised) and the file path with "/" separators
local function whereFrom(fn)
    if not getFilenameOfClosure then return nil, nil end
    local ok, path = pcall(getFilenameOfClosure, fn)
    if not ok or not path then return nil, nil end
    local p = string.gsub(tostring(path), "\\", "/")
    return norm(string.match(p, "/mods/([^/]+)/") or ""), p
end

local function firstLine(fn)
    if not getFirstLineOfClosure then return nil end
    local ok, l = pcall(getFirstLineOfClosure, fn)
    if ok then return tonumber(l) end
    return nil
end

local function entryFor(evName, fn)
    local mod, path = nil, nil
    local line, lineRead = nil, false
    for _, e in ipairs(LIST) do
        if e.ev == evName then
            if e.fn ~= nil then
                if e.fn == fn then return e end
            else
                if path == nil then
                    mod, path = whereFrom(fn)
                    if not path then path = false end   -- file unknown: only fn entries can match
                end
                if path and e.key == mod and string.sub(path, -string.len(e.tail)) == e.tail then
                    if e.line == nil then return e end
                    if not lineRead then line, lineRead = firstLine(fn), true end
                    if line == e.line then return e end
                end
            end
        end
    end
    return nil
end

-- ------------------------------------------------------------------ state
local P = {
    LIST = LIST, NEAR = NEAR, EVERY_SEEN = EVERY_SEEN, EVERY_UNSEEN = EVERY_UNSEEN,
    EVERY_CROWD = EVERY_CROWD, CROWD = CROWD,
    on = true,            -- sandboxOn and not adminOff
    sandboxOn = true,     -- SandboxVars.CookieSlicer.PaceModHandlers
    adminOff = false,     -- the switch on the Speed Slicer page (this game only)
    paced = {},           -- one record per handler that matched an entry
    bands = { near = 0, seen = 0, unseen = 0, crowd = 0 },  -- zombie updates since the last second
    rate = { near = 0, seen = 0, unseen = 0, crowd = 0 },   -- the same, last full second
    crowd = false,
}
CookiePace = P

-- one more entry (the probe below). Handlers added before it are not paced.
function P.addEntry(e)
    LIST[#LIST + 1] = prepare(e)
    return e
end

local on = true
local frame = 0
local nPlayers, px, py = 0, {}, {}
local NEAR2 = NEAR * NEAR

-- the band of one zombie, worked out once per frame: the handlers of one zombie
-- run one after the other, so the last zombie is all that needs remembering
local lastZ, lastFrame, lastEvery, lastBase = nil, -1, 1, 0
local function bandOf(z)
    if z == lastZ and frame == lastFrame then return lastEvery, lastBase end
    local every, b = 1, P.bands
    local x, y = z:getX(), z:getY()
    local near = false
    for i = 1, nPlayers do
        local dx, dy = x - px[i], y - py[i]
        if dx * dx + dy * dy <= NEAR2 then near = true; break end
    end
    if near then
        b.near = b.near + 1
    elseif z:isOnScreen() then
        every = EVERY_SEEN
        b.seen = b.seen + 1
    elseif P.crowd then
        every = EVERY_CROWD
        b.crowd = b.crowd + 1
    else
        every = EVERY_UNSEEN
        b.unseen = b.unseen + 1
    end
    lastZ, lastFrame, lastEvery = z, frame, every
    lastBase = every > 1 and (z:getID() + frame) or 0
    return every, lastBase
end
P.bandOf = bandOf

-- CookieProfiler (00_CookieProfiler.lua) exists only while profiling is on.
-- It then counts a paced handler under the mod's own file, tagged "(paced)".
local function profiled(w, fn)
    local CP = CookieProfiler
    if CP and CP.alias then CP.alias[w] = { fn = fn, tag = "paced" } end
end

local function paceZombie(rec, fn)
    local k = rec.k
    return function(z, ...)
        if on and z then
            local every, base = bandOf(z)
            if every > 1 and (base + k) % every ~= 0 then
                rec.skips = rec.skips + 1
                return
            end
        end
        rec.runs = rec.runs + 1
        return fn(z, ...)
    end
end

local function paceTick(rec, fn)
    local ms = tonumber(rec.entry.ms) or TICK_MS
    local last = nil
    return function(...)
        if on then
            local now = getTimestampMs()
            if last and now >= last and now - last < ms then
                rec.skips = rec.skips + 1
                return
            end
            last = now
        end
        rec.runs = rec.runs + 1
        return fn(...)
    end
end

-- ------------------------------------------------------------------ Events.*.Add
local function patch(evName, ev, make)
    local innerAdd, innerRemove = rawget(ev, "Add"), rawget(ev, "Remove")
    local wrapped = {}   -- mod's function -> the one the game got
    rawset(ev, "Add", function(fn, ...)
        if type(fn) ~= "function" then return innerAdd(fn, ...) end
        local w = wrapped[fn]
        if not w then
            local e = entryFor(evName, fn)
            if not e then return innerAdd(fn, ...) end
            local rec = { entry = e, ev = evName, k = #P.paced, runs = 0, skips = 0 }
            w = make(rec, fn)
            P.paced[#P.paced + 1] = rec
            wrapped[fn] = w
            profiled(w, fn)
            if not e.quiet then
                print(TAG .. ": " .. evName .. " " .. tostring(e.mod) .. " " .. tostring(e.file)
                    .. ":" .. tostring(e.line or "*") .. " paced")
            end
        end
        return innerAdd(w)
    end)
    rawset(ev, "Remove", function(fn, ...)
        local w = nil
        if type(fn) == "function" then w = wrapped[fn] end
        if w then return innerRemove(w) end
        return innerRemove(fn, ...)
    end)
    return innerAdd, innerRemove
end

patch("OnZombieUpdate", evZ, paceZombie)
local tickAdd = patch("OnTick", evT, paceTick)   -- Cookie Pace's own OnTick goes in unpaced

-- ------------------------------------------------------------------ every frame
local function readSandbox()
    local sv = SandboxVars and SandboxVars.CookieSlicer
    local v = sv and sv.PaceModHandlers
    if type(v) == "boolean" then return v end
    return true
end

local function refresh()
    P.sandboxOn = readSandbox()
    on = P.sandboxOn and not P.adminOff
    P.on = on
end

local secondAt = 0
local function onTick()
    frame = frame + 1
    local n = 0
    local count = getNumActivePlayers and getNumActivePlayers() or 1
    for i = 0, count - 1 do
        local p = getSpecificPlayer and getSpecificPlayer(i)
        if p and not p:isDead() then
            n = n + 1
            px[n], py[n] = p:getX(), p:getY()
        end
    end
    nPlayers = n
    local now = getTimestampMs()
    if now - secondAt >= 1000 or now < secondAt then
        secondAt = now
        local cell = getCell and getCell()
        local list = cell and cell:getZombieList()
        P.zombies = list and list:size() or 0
        P.crowd = P.zombies > CROWD
        local b, r = P.bands, P.rate
        r.near, r.seen, r.unseen, r.crowd = b.near, b.seen, b.unseen, b.crowd
        b.near, b.seen, b.unseen, b.crowd = 0, 0, 0, 0
        refresh()
        P.probeTick(now)
    end
end
tickAdd(onTick)

-- ------------------------------------------------------------------ admin switch + probe
function P.isAdmin()
    if not (isClient and isClient()) then return true end   -- single player
    local ok, v = pcall(isAdmin)
    if ok and v == true then return true end
    local p = getPlayer and getPlayer()
    if p then
        local okR, role = pcall(function() return p:getRole() end)
        if okR and role then
            local okA, a = pcall(function() return role:hasAdminTool() end)
            if okA and a == true then return true end
        end
    end
    return false
end

function P.setAdminOff(off)
    P.adminOff = off == true
    refresh()
    local parts = {}
    for _, rec in ipairs(P.paced) do
        if not rec.entry.quiet then
            parts[#parts + 1] = tostring(rec.entry.mod) .. " " .. rec.runs .. "/" .. (rec.runs + rec.skips)
        end
    end
    print(TAG .. ": " .. (P.adminOff and "off" or "on") .. " in this game (admin switch), runs so far: "
        .. (#parts > 0 and table.concat(parts, ", ") or "no handlers paced"))
end

-- The probe is a handler of Cookie Pace's own, listed like any other, that only counts.
-- It is added while an admin has the Speed Slicer page open (P.wantProbe) and removed a
-- few seconds after, so the page can show that pacing works on the zombies around.
local probeRec = nil
local function probe(z) end
P.addEntry({ ev = "OnZombieUpdate", fn = probe, mod = "CookieSlicer", file = "probe", quiet = true })
P.probe = { added = false, wantAt = 0 }

function P.wantProbe()
    P.probe.wantAt = getTimestampMs()
    if P.probe.added then return end
    P.probe.added = true
    Events.OnZombieUpdate.Add(probe)
    for _, rec in ipairs(P.paced) do
        if rec.entry.fn == probe then probeRec = rec end
    end
    if probeRec then probeRec.runs, probeRec.skips = 0, 0 end
    P.probe.rec = probeRec
end

function P.probeTick(now)
    local pr = P.probe
    if pr.added and (now - pr.wantAt > 3000 or now < pr.wantAt) then
        Events.OnZombieUpdate.Remove(probe)
        pr.added = false
    end
    if probeRec then
        pr.last = { runs = probeRec.runs, skips = probeRec.skips }
        probeRec.runs, probeRec.skips = 0, 0
    end
end

local function onStart()
    refresh()
    local n, names = 0, {}
    for _, e in ipairs(LIST) do
        if not e.quiet then
            n = n + 1
            local hit = false
            for _, rec in ipairs(P.paced) do if rec.entry == e then hit = true end end
            if not hit then names[#names + 1] = tostring(e.mod) .. " " .. tostring(e.file) .. ":" .. tostring(e.line or "*") end
        end
    end
    local paced = 0
    for _, rec in ipairs(P.paced) do if not rec.entry.quiet then paced = paced + 1 end end
    print(TAG .. ": " .. (P.sandboxOn and "on" or "off (sandbox)") .. ", " .. paced .. " handler(s) paced, list "
        .. n .. (#names > 0 and (", not found (mod updated or not loaded): " .. table.concat(names, "; ")) or ""))
end
if Events.OnGameStart then Events.OnGameStart.Add(onStart) end
