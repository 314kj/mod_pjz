-- Cookie Square Queue (part of Cookie Slicer; the same file is still in CSP's CookieEarlyHooks until it moves)
--
-- Every time a square of the map loads, some mods run Lua for it at once. While
-- driving, thousands of squares load each second and all of that lands on the
-- frame (players) or the tick (server): the picture stutters, the server falls
-- behind and the map shows up late. Measured 10 Nov 2026 with the Cookie Profiler.
--
-- This file changes HOW and WHEN LoadGridsquare handlers of mods run. What they
-- do stays the same:
--   queue  in a player's game, EVERY mod's handler (the ones listed below and all
--          others, whatever mods are installed; not the game's own) runs from a
--          queue a few frames later instead of in the frame the square arrives:
--          2 ms per frame, +1 ms per 1000 squares waiting, at most 6 ms; squares
--          that unload before their turn are skipped, and during the loading
--          screen nothing waits. Since 10 Nov (Pie OK) the server no longer
--          freezes while cells load (Cookie Slicer), so squares now arrive at a
--          steady rate and all mods together in one frame made the picture jerk.
--          On the dedicated server nothing is queued here.
--   lite   same result, without work that cannot change it (no pcall per
--          object, no empty modData table made for every object on the map,
--          no scan whose result nothing in this game reads); in a player's game
--          the lite version runs from the queue too
--   later  the rules below with action "later" (machine lights, drying rack /
--          grow light art, old fog leftovers): the queue, listed by name
--   now    on the dedicated server: handlers that must run while the chunk is
--          being added, before the game fills its rooms with zombies and stories
--          (AliveJeem's base zombie safety marks NPC compound rooms and watches
--          the zombies created for a new chunk). Cookie Slicer (server java agent)
--          runs LoadGridsquare / LoadChunk later; it also fires OnCookieSquareNow /
--          OnCookieChunkNow at the original moment, and these handlers run there
--          and are skipped when the late event comes. Without the agent (or with
--          it switched off) they simply run from LoadGridsquare / LoadChunk.
--   skip   in a player's game only: handlers that change nothing there (the
--          Kentucky Cannabis plumbing list and drying-rack tracking, the
--          ZVirusVaccine compost-bin list, Daily Challenge object placement:
--          only the server reads them or they return at once on a client)
--   parked in a player's game: squares inside buildings, above the ground
--          floor or in basements wait while the player's vehicle moves (10
--          km/h+). They run when it slows down for 1.5 s or the player gets
--          out, if the square is still loaded; buildings only driven past
--          usually unload first and are not processed then (they are the next
--          time they load). Test 10 Nov: about 90% of parked squares were never
--          needed. The same was tried on the server (rules "server" + "park"
--          below, now removed): the server keeps those squares loaded, so it
--          only moved the work a few seconds later and saved nothing.
-- A handler is recognised by its mod folder + file name when the mod adds it,
-- which is why this mod must be at the top of the mod list. If a lite
-- version hits an error, or a mod update removes something it relies on, the
-- mod's own function is used from then on. Nothing here is saved or sent over
-- the network.
--
-- Log: "[CookieSlicer] square-queue on (client|server): ..." (with the mods
-- whose handlers run from the queue) plus a line per listed handler. To undo:
-- remove this file.

-- The same file is in the Cookie Slicer mod (it is moving there from CSP); only
-- this line differs. Whichever copy loads first works, the other one does
-- nothing, so either mod order is safe.
local OWNER = "CookieSlicer"
local TAG = (OWNER == "CookieSlicer" and "[CookieSlicer]" or "[CookieServerPatch]") .. " square-queue"
if CookieSquareQueue ~= nil then
    print(TAG .. ": already loaded by " .. tostring(CookieSquareQueue.owner) .. ", this copy does nothing")
    return
end
local ev = Events and Events.LoadGridsquare
if not ev or not rawget(ev, "Add") or not rawget(ev, "Remove") then return end

local IS_CLIENT = isClient and isClient() or false
local IS_SERVER = isServer and isServer() or false
local SIDE = IS_SERVER and "server" or (IS_CLIENT and "client" or "sp")
local BUDGET_MS = IS_SERVER and 4 or 2      -- per frame (player) / per tick (server)
local BUDGET_MAX_MS = IS_SERVER and 4 or 6  -- a long queue gets up to this (+1 ms per 1000 waiting)

local function norm(s)
    return string.lower((string.gsub(tostring(s or ""), "[%s_%-]", "")))
end

-- mod folder (normalised) and the file path with "/" separators
local function whereFrom(fn)
    if not getFilenameOfClosure then return nil, nil end
    local ok, path = pcall(getFilenameOfClosure, fn)
    if not ok or not path then return nil, nil end
    local p = string.gsub(tostring(path), "\\", "/")
    return norm(string.match(p, "/mods/([^/]+)/") or ""), p
end

local function sprite(o)
    local s = o and o:getSprite()
    return s and s:getName() or ""
end

-- ------------------------------------------------------------------ lite versions
-- Kentucky Cannabis KC_Paint: same test, but an object without modData is not
-- given an empty table just to read one key.
local function kcPaintLite(orig)
    return function(square)
        local KC = KentuckyCannabis
        local P, H, B = KC and KC.Paint, KC and KC.Hydroponics, KC and KC.Planters
        if not (P and P.refresh and H and H.isTray and B and B.isEmptySprite) then return orig(square) end
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local o = objects:get(i)
            if H.isTray(o) or B.isEmptySprite(sprite(o))
                    or (o:hasModData() and o:getModData().KCMushroomPlanter) then
                P.refresh(o)
            end
        end
    end
end

-- Dynamic Outposts territory: same checks as its reconcileLoadedSquare, using
-- the mod's own Territory functions, without pcall closures and a new modData
-- table for every object of every square.
local function outpostsLite(orig)
    return function(square)
        local T = ClaimableOutposts and ClaimableOutposts.Territory
        if not (square and instanceof and T and T.At and T.Square and T.IsSupplyCrateObject
                and T.DEDICATED_THUMP_KEY and T.DisableOutpostCrateThumping
                and T.RestoreDedicatedCrateThumping) then
            return orig(square)
        end
        local KEY = T.DEDICATED_THUMP_KEY
        local checked, claimed = false, false
        local function reconcile(obj, marked)
            if not marked and not T.IsSupplyCrateObject(obj) then return end
            local sq = T.Square(obj)
            if not sq then return end
            local outpost, state = T.At(sq:getX(), sq:getY(), sq:getZ())
            if outpost and state and T.IsSupplyCrateObject(obj) then
                T.DisableOutpostCrateThumping(obj, outpost)
            elseif marked then
                T.RestoreDedicatedCrateThumping(obj)
            end
        end
        local function visit(obj)
            if obj:hasModData() and obj:getModData()[KEY] ~= nil then
                reconcile(obj, true)
                return
            end
            if not checked then
                checked = true
                local _, state = T.At(square:getX(), square:getY(), square:getZ())
                claimed = state ~= nil
            end
            if claimed and instanceof(obj, "IsoThumpable") then reconcile(obj, false) end
        end
        local objects = square:getObjects()
        local n = objects and objects:size() or 0
        for i = 0, n - 1 do
            local o = objects:get(i)
            if o then visit(o) end
        end
        local special = square:getSpecialObjects()
        local m = special and special:size() or 0
        if m > 0 then
            local seen = {}
            for i = 0, n - 1 do seen[objects:get(i)] = true end
            for i = 0, m - 1 do
                local o = special:get(i)
                if o and not seen[o] then
                    seen[o] = true
                    visit(o)
                end
            end
        end
    end
end

-- Arcadia Lifestyle MP Optimizer object tracker: hand only objects whose sprite
-- names one of its devices to its own trackLifestyleObject, which checks them
-- again. The names are the mod's RELEVANT_CUSTOM_NAMES / RELEVANT_GROUP_NAMES.
local ARC_CUSTOM = { ["Jukebox"] = true, ["Disco Ball"] = true, ["Sculpture Ice"] = true,
    ["Sculpture Lamp"] = true, ["Disco Floor"] = true, ["Booth"] = true, ["Microphone"] = true,
    ["Hygienator"] = true, ["FoodSynthesizer"] = true, ["DrinkingBuddy"] = true }
local ARC_GROUP = { ["GF Clock"] = true, ["StationWork"] = true }
local function arcadiaLite(orig)
    return function(square)
        local A = ArcadiaLifestyleMP
        local track = A and A.trackLifestyleObject
        local stats = A and A.objectTrackerStats
        if not (square and track and stats) then return orig(square) end
        local objects = square:getObjects()
        if not objects then return end
        for i = 0, objects:size() - 1 do
            local o = objects:get(i)
            local s = o and o:getSprite()
            local props = s and s:getProperties()
            if props then
                local hit = props:has("CustomName") and ARC_CUSTOM[tostring(props:get("CustomName"))]
                if not hit and props:has("GroupName") then hit = ARC_GROUP[tostring(props:get("GroupName"))] end
                if hit then track(o) end
            end
        end
        stats.squaresLoaded = (stats.squaresLoaded or 0) + 1
    end
end

-- Monorails: the scan only feeds MR_TrackServer / MR_StationServer /
-- MR_RemoveServer. When none of them exists in this Lua state, the scan's
-- result goes nowhere, so it is not made.
local function monorailsLite(orig)
    return function(square)
        if MR_TrackServer or MR_StationServer or MR_RemoveServer
                or (MR_TrackState and MR_TrackState.removed) then
            return orig(square)
        end
    end
end

-- ------------------------------------------------------------------ rules
-- side: where the rule applies: "client" = a player's game in multiplayer,
--       "server" = the dedicated server, "both" = everywhere
-- park: where its squares can be parked while driving (see the header)
-- file: the end of the file's path, so "PhunMart_Server/events.lua" is not the
--       client's events.lua
local RULES = {
    { mod = "KentuckyCannabis", file = "KC_Paint.lua", side = "both", action = "lite", make = kcPaintLite, park = "client" },
    { mod = "Dynamic Outposts", file = "ClaimableOutposts_TerritoryProtection.lua", side = "both", action = "lite", make = outpostsLite, park = "client" },
    { mod = "ArcadiaLifestyleMPOptimizer_B42", file = "01_ArcadiaLifestyleMP_ObjectTracker.lua", side = "client", action = "lite", make = arcadiaLite, park = "client" },
    { mod = "Monorails", file = "MR_TrackState.lua", side = "client", action = "lite", make = monorailsLite, park = "client" },
    { mod = "PhunMart2", file = "PhunMart_Client/lights.lua", side = "client", action = "later" },
    { mod = "Dynamic Outposts", file = "ClaimableOutposts_InfectedFog.lua", side = "client", action = "later" },
    { mod = "KentuckyCannabis", file = "KC_GrowLights.lua", side = "client", action = "later" },
    { mod = "KentuckyCannabis", file = "KC_CompactDryingRackVisuals.lua", side = "client", action = "later" },
    { mod = "KentuckyCannabis", file = "KC_DryingRack.lua", side = "client", action = "later" },
    -- skip = in a player's game the handler changes nothing (checked 10 Nov):
    -- KC_Plumbing only fills P.loaded, which only its EveryOneMinute reads, and that
    -- returns on a client (the list also kept every plumbing object a player ever
    -- drove past until the main menu); the drying-rack server file's track() returns
    -- on a client before doing anything
    { mod = "KentuckyCannabis", file = "KC_Plumbing.lua", side = "client", action = "skip" },
    { mod = "KentuckyCannabis", file = "BuildingObjects/KC_CompactDryingRackServer.lua", side = "client", action = "skip" },
    -- ZVirusVaccine: fills a compost-bin list only its EveryTenMinutes reads, which
    -- returns on a client (the list was never emptied there either)
    { mod = "ZVirusVaccine42BETA", file = "LabCompost.lua", side = "client", action = "skip" },
    -- Daily Challenge: returns at once unless DCS_Env.runsServerLogic() (server / singleplayer)
    { mod = "DailyChallengeSystem", file = "DCS_ObjectManager.lua", side = "client", action = "skip" },
    -- AliveJeem: "Mark native indoor rooms before their initial/late native population pass"
    { mod = "AliveJeemDynamicWorld", file = "ADW/BaseZombieSafety.lua", side = "server", action = "now" },
    -- Server parking (side = "server", action = "park") was tested 10 Nov with
    -- KC_Plumbing, KC_CompactDryingRackServer, KC_CropSprites, KC_HydroponicsServer,
    -- KC_PlanterSprites, PhunMart_Server/events.lua, PuffinsRetroRelics_BedSpawns,
    -- Knox WellSystem/FluidContainers: no square was unloaded before its turn and
    -- server fps did not change, so none are parked there.
}
for _, r in ipairs(RULES) do r.key = norm(r.mod); r.tail = "/" .. r.file end

local function here(where)
    return where == "both" or (where == "client" and IS_CLIENT) or (where == "server" and IS_SERVER)
end

local function ruleFor(fn)
    local mod, path = whereFrom(fn)
    if not mod or not path then return nil end
    for _, r in ipairs(RULES) do
        if r.key == mod and here(r.side) and string.sub(path, -string.len(r.tail)) == r.tail then return r end
    end
    return nil
end

local function baseName(fn)
    local mod, path = whereFrom(fn)
    return (path and string.match(path, "([^/]+)$") or "?"), mod
end

-- A lite version that errors once is replaced by the mod's own function.
local function guarded(r, lite, orig)
    local broken = false
    return function(square)
        if broken then return orig(square) end
        local ok, err = pcall(lite, square)
        if not ok then
            broken = true
            print(TAG .. ": " .. r.file .. " (" .. r.mod .. ") lite failed, using the mod's own: " .. tostring(err))
            return orig(square)
        end
    end
end

-- ------------------------------------------------------------------ state
local innerAdd, innerRemove = rawget(ev, "Add"), rawget(ev, "Remove")
-- events Cookie Slicer fires at the moment the game used to fire LoadGridsquare / LoadChunk
local NOW_SQUARE, NOW_CHUNK = "OnCookieSquareNow", "OnCookieChunkNow"
local NOW_KEEP_MS = 120000   -- a "done" mark older than this is ignored
if IS_SERVER and LuaEventManager and LuaEventManager.AddEvent then
    pcall(LuaEventManager.AddEvent, NOW_SQUARE)
    pcall(LuaEventManager.AddEvent, NOW_CHUNK)
end
local nowOf = {}          -- original fn -> function added to OnCookieSquareNow
local later = {}          -- "later" functions, in the order the mods added them
local laterOf = {}        -- original fn -> entry in later
local parkFns = {}        -- functions run for a parked square (with the later ones)
local parkOf = {}         -- function added in place of a mod's -> its entry in parkFns
local qx, qy, qz = {}, {}, {}
local head, tail = 1, 0
local started = false     -- before the game starts (loading screen) nothing waits
local errors = {}
local stats = { queued = 0, run = 0, skipped = 0, maxBacklog = 0,
    parked = 0, parkRun = 0, parkSkipped = 0, parkDropped = 0, maxParked = 0 }

local function runLater(fn, square)
    local ok, err = pcall(fn, square)
    if not ok then
        local n = (errors[fn] or 0) + 1
        errors[fn] = n
        if n <= 3 then
            local file, mod = baseName(fn)
            print(TAG .. ": error in " .. tostring(file) .. " (" .. tostring(mod) .. "): " .. tostring(err))
        end
    end
end

-- ------------------------------------------------------------------ who is driving
-- Player: its own vehicle's speed. Server: every online player's position every
-- 0.5 s, speed from the distance moved. On the server a player counts as
-- driving at 8+ tiles/s (no one on foot is that fast), or at 10 km/h+ when the
-- server also sees them in a vehicle; it stops after 1.5 s below that.
local PARK_KMH = 10
local PARK_TILES_PER_S = PARK_KMH / 3.6
local FAST_TILES_PER_S = 8
local PARK_RELEASE_MS = 1500
local PARK_MAX = 50000            -- per driver; the oldest are dropped past this
local SAMPLE_MS = 500
local drivers = {}                -- owner -> { driving, slowSince, x, y, t }
local anyDriving = false
local nearby = {}                 -- server: { name, x, y, driving } of online players
local lastSample = 0
local queues = {}                 -- owner -> parked squares (see "parking" below)
local notes = 0                   -- log lines about drivers so far (capped)

local function note(text)
    if notes >= 60 then return end
    notes = notes + 1
    print(TAG .. ": " .. text .. (notes == 60 and " (no more of these lines this session)" or ""))
end

-- fast: counts as driving now; out: got out of the vehicle (stops at once)
local function setDriving(owner, d, fast, out, now, info)
    if fast then
        if not d.driving then note(owner .. " driving" .. (info or "")) end
        d.driving, d.slowSince = true, nil
    elseif d.driving then
        if out then
            d.driving, d.slowSince = false, nil
        else
            d.slowSince = d.slowSince or now
            if now - d.slowSince >= PARK_RELEASE_MS then d.driving, d.slowSince = false, nil end
        end
        if not d.driving then
            local q = queues[owner]
            note(owner .. " stopped" .. (info or "") .. ", " .. (q and (q.tail - q.head + 1) or 0) .. " squares waiting")
        end
    end
end

local function updateClient(now)
    local p = getPlayer and getPlayer()
    local v = p and p:getVehicle()
    local d = drivers["me"]
    if not d then d = {}; drivers["me"] = d end
    setDriving("me", d, v ~= nil and math.abs(v:getCurrentSpeedKmHour()) >= PARK_KMH, v == nil, now)
    anyDriving = d.driving == true
end

local function updateServer(now)
    if now - lastSample < SAMPLE_MS then return end
    local list = getOnlinePlayers and getOnlinePlayers()
    local seen, near, any = {}, {}, false
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            local name = p and p:getUsername()
            if name then
                local v = p:getVehicle()
                local inVehicle = v ~= nil
                local x, y = (v or p):getX(), (v or p):getY()
                local d = drivers[name]
                if not d then d = {}; drivers[name] = d end
                local speed = 0
                if d.t and now > d.t then
                    local dx, dy = x - d.x, y - d.y
                    speed = math.sqrt(dx * dx + dy * dy) * 1000 / (now - d.t)
                end
                local fast = speed >= FAST_TILES_PER_S or (inVehicle and speed >= PARK_TILES_PER_S)
                setDriving(name, d, fast, false, now,
                    " (" .. math.floor(speed * 3.6 + 0.5) .. " km/h, in a vehicle: " .. (inVehicle and "yes" or "no") .. ")")
                d.x, d.y, d.t = x, y, now
                seen[name] = true
                near[#near + 1] = { name = name, x = x, y = y, driving = d.driving }
                if d.driving then any = true end
            end
        end
    end
    for name, d in pairs(drivers) do
        if not seen[name] then d.driving, d.t = false, nil end   -- left the server
    end
    nearby, anyDriving = near, any
    lastSample = now
end

-- server: which driving player a square belongs to (nearest player), cached per 8x8 chunk
local cacheCX, cacheCY, cacheOwner, cacheAt = nil, nil, nil, -1
local function ownerAt(x, y)
    local cx, cy = math.floor(x / 8), math.floor(y / 8)
    if cx == cacheCX and cy == cacheCY and cacheAt == lastSample then return cacheOwner end
    local best, bestD = nil, nil
    for i = 1, #nearby do
        local p = nearby[i]
        local dx, dy = p.x - x, p.y - y
        local dd = dx * dx + dy * dy
        if not bestD or dd < bestD then best, bestD = p, dd end
    end
    cacheCX, cacheCY, cacheAt = cx, cy, lastSample
    cacheOwner = best and best.driving and best.name or nil
    return cacheOwner
end

-- ------------------------------------------------------------------ parking
-- queues: owner -> { x = {}, y = {}, z = {}, head, tail, ran, skipped }
local curSq, curParked = nil, false

local function park(owner, x, y, z)
    local q = queues[owner]
    if not q then q = { x = {}, y = {}, z = {}, head = 1, tail = 0, ran = 0, skipped = 0 }; queues[owner] = q end
    local t = q.tail + 1
    q.tail = t
    q.x[t], q.y[t], q.z[t] = x, y, z
    stats.parked = stats.parked + 1
    if t - q.head + 1 > PARK_MAX then
        q.x[q.head], q.y[q.head], q.z[q.head] = nil, nil, nil
        q.head = q.head + 1
        stats.parkDropped = stats.parkDropped + 1
    end
    local n = t - q.head + 1
    if n > stats.maxParked then stats.maxParked = n end
end

-- Added to LoadGridsquare before any mod's handler, so it runs first for each square.
local function markSquare(square)
    curSq, curParked = square, false
    if not anyDriving or not started or not square then return end
    local z = square:getZ()
    if z == 0 and square:getRoom() == nil then return end   -- outdoors, ground floor
    local x, y = square:getX(), square:getY()
    local owner = "me"
    if IS_SERVER then
        owner = ownerAt(x, y)
        if not owner then return end
    end
    curParked = true
    park(owner, x, y, z)
end

local function isParked(square)
    return curParked and square == curSq
end

-- ------------------------------------------------------------------ queue for "later"
local function collect(square)
    if not square or #later == 0 or isParked(square) then return end
    if not started then
        for i = 1, #later do runLater(later[i], square) end
        return
    end
    tail = tail + 1
    qx[tail], qy[tail], qz[tail] = square:getX(), square:getY(), square:getZ()
    stats.queued = stats.queued + 1
    local backlog = tail - head + 1
    if backlog > stats.maxBacklog then stats.maxBacklog = backlog end
end

local function compact(xs, ys, zs, h, t)
    local n = 0
    local nx, ny, nz = {}, {}, {}
    for i = h, t do
        n = n + 1
        nx[n], ny[n], nz[n] = xs[i], ys[i], zs[i]
    end
    return nx, ny, nz, 1, n
end

-- returns the number of squares handled; stops at the budget
local function drainParked(q, cell, t0, n, budget)
    while q.head <= q.tail do
        if n % 16 == 0 and n > 0 and getTimestampMs() - t0 >= budget then break end
        local h = q.head
        local x, y, z = q.x[h], q.y[h], q.z[h]
        q.x[h], q.y[h], q.z[h] = nil, nil, nil
        q.head = h + 1
        local sq = cell:getGridSquare(x, y, z)
        if sq then
            for i = 1, #parkFns do runLater(parkFns[i], sq) end
            for i = 1, #later do runLater(later[i], sq) end
            stats.parkRun = stats.parkRun + 1
            q.ran = q.ran + 1
        else
            stats.parkSkipped = stats.parkSkipped + 1
            q.skipped = q.skipped + 1
        end
        n = n + 1
    end
    if q.head > 4096 and q.head <= q.tail then
        q.x, q.y, q.z, q.head, q.tail = compact(q.x, q.y, q.z, q.head, q.tail)
    end
    return n
end

local function drain()
    local t0 = getTimestampMs()
    if started then
        if IS_SERVER then updateServer(t0) elseif IS_CLIENT then updateClient(t0) end
    end
    local cell = getCell()
    if not cell then return end
    local budget = math.min(BUDGET_MAX_MS, BUDGET_MS + math.floor((tail - head + 1) / 1000))
    local n = 0
    while head <= tail do
        local x, y, z = qx[head], qy[head], qz[head]
        qx[head], qy[head], qz[head] = nil, nil, nil
        head = head + 1
        local sq = cell:getGridSquare(x, y, z)
        if sq then
            for i = 1, #later do runLater(later[i], sq) end
            stats.run = stats.run + 1
        else
            stats.skipped = stats.skipped + 1
        end
        n = n + 1
        if n % 16 == 0 and getTimestampMs() - t0 >= budget then break end
    end
    if head > tail then
        if tail > 0 then qx, qy, qz, head, tail = {}, {}, {}, 1, 0 end
    elseif head > 4096 then
        qx, qy, qz, head, tail = compact(qx, qy, qz, head, tail)
    end
    if head <= tail then return end
    -- parked squares of drivers that stopped (or left)
    for owner, q in pairs(queues) do
        local d = drivers[owner]
        if not (d and d.driving) then
            n = drainParked(q, cell, t0, n, budget)
            if q.head > q.tail then
                queues[owner] = nil
                note(owner .. ": waiting squares done, " .. q.ran .. " run, " .. q.skipped .. " already unloaded")
            end
            if n % 16 == 0 and n > 0 and getTimestampMs() - t0 >= budget then break end
        end
    end
end

local queueOn = false
local function startQueue()
    if queueOn then return end
    queueOn = true
    if IS_CLIENT then innerAdd(collect) end
    Events.OnTick.Add(drain)
end

local function onStart() started = true end
if Events.OnGameStart then Events.OnGameStart.Add(onStart) end
if IS_SERVER and Events.OnServerStarted then Events.OnServerStarted.Add(onStart) end
if Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(function()
        started, anyDriving, curSq, curParked = false, false, nil, false
        qx, qy, qz, head, tail = {}, {}, {}, 1, 0
        queues, drivers, nearby = {}, {}, {}
    end)
end

-- decide per square, before the mods' handlers, whether it waits
-- (players only: no server rule parks anything, see RULES)
if IS_CLIENT then innerAdd(markSquare) end

-- ------------------------------------------------------------------ take over Add / Remove
local taken = {}   -- original fn -> "later" | function added in its place
local counts = { lite = 0, later = 0, park = 0, skip = 0, all = 0, now = 0 }
local allMods = {}         -- client: mods whose square work runs from the queue (not listed in RULES)

local function say(r, what)
    print(TAG .. ": " .. r.file .. " (" .. r.mod .. ") " .. what)
end

-- CookieProfiler (00_CookieProfiler.lua) exists only while profiling is on.
-- It then counts these under the mod's own file, tagged "(lite)", "(later)" ...
local function profiled(fn, orig, tag, label)
    local P = CookieProfiler
    if not (P and P.alias) then return fn end
    P.alias[fn] = { fn = orig, tag = tag }
    if label and P.wrap then return P.wrap(label, fn) end
    return fn
end

-- the function the game gets: skips parked squares, which run it from the queue
local function parkable(run, orig, tag)
    local reg = function(square)
        if isParked(square) then return end
        return run(square)
    end
    local entry = profiled(run, orig, tag .. ", parked", "LoadGridsquare")
    parkFns[#parkFns + 1] = entry
    parkOf[reg] = entry
    startQueue()
    return reg
end

-- In a player's game every mod's square work runs from the queue (see the header);
-- false for the game's own files, this mod, and a function whose file is unknown.
local function anyMod(fn)
    if not IS_CLIENT then return nil end
    local mod, path = whereFrom(fn)
    if not mod or mod == "" or not path or mod == norm("CookieEarlyHooks") or mod == norm("CookieSlicer") then return nil end
    return string.match(path, "/mods/([^/]+)/") or mod
end

local function addLater(fn, run, tag)
    local entry = profiled(run, fn, tag, "LoadGridsquare")
    taken[fn] = "later"
    laterOf[fn] = entry
    later[#later + 1] = entry
    startQueue()
end

rawset(ev, "Add", function(fn, ...)
    if type(fn) ~= "function" then return innerAdd(fn, ...) end
    local t = taken[fn]
    if t == "later" then                    -- added twice: run twice, like the game would
        later[#later + 1] = laterOf[fn]
        return
    elseif t == "skip" then
        return
    elseif t then
        return innerAdd(t)
    end
    local r = ruleFor(fn)
    if not r then
        local modName = anyMod(fn)
        if not modName then return innerAdd(fn, ...) end
        counts.all = counts.all + 1
        if not allMods[modName] then allMods[modName] = true; allMods[#allMods + 1] = modName end
        addLater(fn, fn, "later")
        return
    end
    counts[r.action] = counts[r.action] + 1
    if r.action == "skip" then
        taken[fn] = "skip"
        say(r, "not needed in a player's game, skipped")
        return
    end
    if r.action == "later" then
        addLater(fn, fn, "later")
        say(r, "runs from the queue")
        return
    end
    if r.action == "now" then
        local nowEv = Events[NOW_SQUARE]
        if not nowEv then return innerAdd(fn, ...) end
        local done = setmetatable({}, { __mode = "k" })
        local nowFn = function(square)
            if square then done[square] = { getTimestampMs(), square:getX(), square:getY(), square:getZ() } end
            return fn(square)
        end
        local reg = function(square)
            local d = square and done[square]
            if d then
                done[square] = nil
                if getTimestampMs() - d[1] < NOW_KEEP_MS and square:getX() == d[2]
                        and square:getY() == d[3] and square:getZ() == d[4] then
                    return       -- already ran when the square loaded
                end
            end
            return fn(square)
        end
        nowEv.Add(nowFn)
        nowOf[fn] = nowFn
        taken[fn] = reg
        say(r, "runs the moment the square loads (also with Cookie Slicer)")
        return innerAdd(reg)
    end
    local reg
    if r.action == "park" then
        reg = parkable(fn, fn, "park")
        profiled(reg, fn, "park")
        say(r, "waits while driving")
    else
        local lite = guarded(r, r.make(fn), fn)
        if IS_CLIENT then
            addLater(fn, lite, "lite, later")
            say(r, "lite, runs from the queue")
            return
        end
        reg = lite
        if r.park and here(r.park) then reg = parkable(reg, fn, "lite") end
        profiled(reg, fn, "lite")
        say(r, "lite")
    end
    taken[fn] = reg
    return innerAdd(reg)
end)

rawset(ev, "Remove", function(fn, ...)
    local t = nil
    if type(fn) == "function" then t = taken[fn] end
    if t == nil then return innerRemove(fn, ...) end
    taken[fn] = nil
    if t == "skip" then return end
    if nowOf[fn] then
        if Events[NOW_SQUARE] then Events[NOW_SQUARE].Remove(nowOf[fn]) end
        nowOf[fn] = nil
    end
    if t == "later" then
        local entry = laterOf[fn]
        laterOf[fn] = nil
        for i = #later, 1, -1 do
            if later[i] == entry then table.remove(later, i) end
        end
        return
    end
    local entry = parkOf[t]
    if entry then
        parkOf[t] = nil
        for i = #parkFns, 1, -1 do
            if parkFns[i] == entry then table.remove(parkFns, i) end
        end
    end
    return innerRemove(t)
end)

-- ------------------------------------------------------------------ LoadChunk "now" (server)
-- Same as action "now" above, for the LoadChunk handlers of the files listed here.
local CHUNK_NOW = {
    { mod = "AliveJeemDynamicWorld", file = "ADW/BaseZombieSafety.lua" },
}
for _, r in ipairs(CHUNK_NOW) do r.key = norm(r.mod); r.tail = "/" .. r.file end
local evc = Events and Events.LoadChunk
if IS_SERVER and evc and rawget(evc, "Add") and rawget(evc, "Remove") and Events[NOW_CHUNK] then
    local chunkAdd, chunkRemove = rawget(evc, "Add"), rawget(evc, "Remove")
    local takenC, nowOfC = {}, {}
    -- where a chunk is (Lua cannot read its fields): from one of its squares
    local function chunkKey(chunk)
        for _, z in ipairs({ 0, -1, 1 }) do
            local ok, sq = pcall(chunk.getGridSquare, chunk, 0, 0, z)
            if ok and sq then return sq:getX() .. "," .. sq:getY() end
        end
        return "?"
    end
    local function chunkRule(fn)
        local mod, path = whereFrom(fn)
        if not mod or not path then return nil end
        for _, r in ipairs(CHUNK_NOW) do
            if r.key == mod and string.sub(path, -string.len(r.tail)) == r.tail then return r end
        end
        return nil
    end
    rawset(evc, "Add", function(fn, ...)
        if type(fn) ~= "function" then return chunkAdd(fn, ...) end
        if takenC[fn] then return chunkAdd(takenC[fn]) end
        local r = chunkRule(fn)
        if not r then return chunkAdd(fn, ...) end
        local done = setmetatable({}, { __mode = "k" })
        local nowFn = function(chunk)
            if chunk then done[chunk] = { getTimestampMs(), chunkKey(chunk) } end
            return fn(chunk)
        end
        local reg = function(chunk)
            local d = chunk and done[chunk]
            if d then
                done[chunk] = nil
                if getTimestampMs() - d[1] < NOW_KEEP_MS and chunkKey(chunk) == d[2] then return end
            end
            return fn(chunk)
        end
        Events[NOW_CHUNK].Add(nowFn)
        takenC[fn], nowOfC[fn] = reg, nowFn
        counts.now = counts.now + 1
        print(TAG .. ": " .. r.file .. " (" .. r.mod .. ") LoadChunk runs the moment the chunk loads (also with Cookie Slicer)")
        return chunkAdd(reg)
    end)
    rawset(evc, "Remove", function(fn, ...)
        local t = type(fn) == "function" and takenC[fn] or nil
        if not t then return chunkRemove(fn, ...) end
        takenC[fn] = nil
        if nowOfC[fn] then Events[NOW_CHUNK].Remove(nowOfC[fn]); nowOfC[fn] = nil end
        return chunkRemove(t)
    end)
end

CookieSquareQueue = { owner = OWNER, stats = stats, counts = counts, budgetMs = BUDGET_MS,
    driving = function() return anyDriving end, drivers = function() return drivers end }

local function hello()
    print(TAG .. " on (" .. SIDE .. "): lite " .. counts.lite .. ", later " .. counts.later
        .. ", wait while driving " .. counts.park .. ", skipped " .. counts.skip
        .. (IS_SERVER and (", at load time " .. counts.now) or "")
        .. (IS_CLIENT and (", other mods' handlers from the queue " .. counts.all
            .. (#allMods > 0 and (" (" .. table.concat(allMods, ", ") .. ")") or "")) or "")
        .. (IS_CLIENT and (", indoor squares wait while driving (" .. PARK_KMH .. " km/h+)") or "")
        .. ", budget " .. BUDGET_MS .. "-" .. BUDGET_MAX_MS .. " ms")
end
if IS_SERVER then
    if Events.OnServerStarted then Events.OnServerStarted.Add(hello) end
elseif Events.OnGameStart then
    Events.OnGameStart.Add(hello)
end
