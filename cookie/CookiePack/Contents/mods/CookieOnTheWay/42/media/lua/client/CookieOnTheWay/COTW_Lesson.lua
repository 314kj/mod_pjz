-- Cookie On the Way : teach scenes (admins)
-- Stand on one corner of a piece of road and press, then on the opposite corner (at most 60 x 60
-- tiles): the box gets a dotted frame on the ground and is scanned the way the autopilot sees it
-- (solid tiles, walls / fences on tile edges, bushes, water, the floor sprite, parked cars, zombies)
-- with the graph roads that cross it. Squares not loaded yet are scanned when they load (the car
-- brings them in). Then the admin, in the car inside the box, presses start and drives through;
-- every 0.1 s the car's place, heading, speed and summed part condition are kept. Leaving the box, a
-- teleport, leaving the seat or 5 minutes stop it and save. The file is written on this computer only
-- (Zomboid/Lua/COTW_lesson_<time>.json, ASCII), to compare the autopilot with the admin's drive offline.

require "CookieOnTheWay/COTW_Client"
require "CookieOnTheWay/COTW_Driver"

COTW.Lesson = COTW.Lesson or {}
local LS = COTW.Lesson

local MAX = 60              -- tiles per side at most
local MIN = 6               -- tiles per side at least
local FRAME_MS = 100
local MAX_FRAMES = 3000     -- 5 minutes
local FILL = 400            -- squares not loaded at scan time tried again per 0.1 s
local WARP = 30             -- tiles between two frames = teleport
local FRAME_STEP = 3        -- tiles between the dots of the frame on the ground
local COL = { 0.25, 0.75, 1.0 }

local S = nil   -- { phase = "c1" | "ready" | "rec", x1, y1, x2, y2, scene, frames, t0, lastT, lx, ly }
local dots = {}

local function clearDots()
    for i = #dots, 1, -1 do
        pcall(function() dots[i]:remove() end)
        dots[i] = nil
    end
end

local function drawFrame()
    clearDots()
    local cell = getCell()
    if not cell then return end
    local function dot(x, y)
        local sq = cell:getGridSquare(x, y, 0)
        if not sq then return end
        local ok, m = pcall(function() return getWorldMarkers():addGridSquareMarker(sq, COL[1], COL[2], COL[3], false, 0.6) end)
        if ok and m then dots[#dots + 1] = m end
    end
    for x = S.x1, S.x2, FRAME_STEP do dot(x, S.y1); dot(x, S.y2) end
    for y = S.y1 + FRAME_STEP, S.y2 - 1, FRAME_STEP do dot(S.x1, y); dot(S.x2, y) end
end

-- ------------------------------------------------------------------------------
-- scanning the box
-- ------------------------------------------------------------------------------
local function floorName(sq)
    local ok, n = pcall(function()
        local f = sq:getFloor()
        return f and f:getSprite() and f:getSprite():getName()
    end)
    if ok and type(n) == "string" then return n end
    return nil
end

local function carOf(car)
    local out = nil
    pcall(function()
        local f = car:getForwardVector(Vector3f.new())
        local fx, fy = f:x(), f:z()
        local L = math.sqrt(fx * fx + fy * fy)
        if L < 0.01 then fx, fy, L = 1, 0, 1 end
        local ext = car:getScript():getExtents()
        out = { x = car:getX(), y = car:getY(), fx = fx / L, fy = fy / L, hw = ext:x() / 2, hl = ext:z() / 2,
                key = COTW.vehicleKey(car) or "?" }
    end)
    return out
end

-- one loaded square: every one is kept (even bare ones), so a replay tells scanned ground from
-- ground nobody saw. Zombies only at the first scan (later ones walked in)
local function scanTile(sc, sq, x, y, mine, zombies)
    local t = COTW.Driver.readTile(sq)
    local flags = (t.s and 1 or 0) + (t.n and 2 or 0) + (t.w and 4 or 0) + (t.wet and 8 or 0)
    local fname = floorName(sq)
    local fi = 0
    if fname then
        fi = sc.fidx[fname]
        if not fi then
            sc.floors[#sc.floors + 1] = fname
            fi = #sc.floors
            sc.fidx[fname] = fi
        end
    end
    sc.tiles[#sc.tiles + 1] = { x, y, flags, fi }
    local car = sq:getVehicleContainer()
    if car and car ~= mine and not sc.seenCar[car] then
        sc.seenCar[car] = true
        local c = carOf(car)
        if c then sc.cars[#sc.cars + 1] = c end
    end
    if zombies then
        pcall(function()
            local list = sq:getMovingObjects()
            for i = 0, list:size() - 1 do
                local o = list:get(i)
                if instanceof(o, "IsoZombie") then sc.zombies[#sc.zombies + 1] = { o:getX(), o:getY() } end
            end
        end)
    end
end

local function scan()
    local cell = getCell()
    local mine = COTW.driving()
    local sc = { tiles = {}, floors = {}, cars = {}, zombies = {}, missing = {}, fidx = {}, seenCar = {} }
    for x = S.x1, S.x2 do
        for y = S.y1, S.y2 do
            local sq = cell and cell:getGridSquare(x, y, 0)
            if sq then scanTile(sc, sq, x, y, mine, true) else sc.missing[#sc.missing + 1] = { x, y } end
        end
    end
    sc.roads = COTW.Graph.edgesIn(S.x1 - 5, S.y1 - 5, S.x2 + 5, S.y2 + 5)
    return sc
end

-- squares that were not loaded at scan time, scanned as they load (FILL tried per call, in turn)
local function fill()
    local sc, cell = S.scene, getCell()
    local miss = sc and sc.missing
    if not cell or not miss or #miss == 0 then return end
    local mine = COTW.driving()
    local k = S.fillAt or 1
    for _ = 1, math.min(#miss, FILL) do
        if #miss == 0 then break end
        if k > #miss then k = 1 end
        local m = miss[k]
        local sq = cell:getGridSquare(m[1], m[2], 0)
        if sq then
            scanTile(sc, sq, m[1], m[2], mine, false)
            miss[k] = miss[#miss]
            miss[#miss] = nil
        else
            k = k + 1
        end
    end
    S.fillAt = k
end

-- ------------------------------------------------------------------------------
-- file (plain JSON, numbers and ASCII names only)
-- ------------------------------------------------------------------------------
local function n2(v) return string.format("%.2f", v or 0) end

local function str(v)
    v = tostring(v or ""):gsub("[^%w%._%-]", "_")
    return '"' .. v .. '"'
end

local function save(reason)
    local sc, fr = S.scene, S.frames
    local out = {}
    local function put(s) out[#out + 1] = s end
    put('{"v":1,"t":' .. string.format("%.0f", S.t0) .. ',"end":' .. str(reason))
    put(',"box":[' .. S.x1 .. ',' .. S.y1 .. ',' .. S.x2 .. ',' .. S.y2 .. '],"missing":' .. #sc.missing)
    local prof = S.prof or {}
    put(',"car":{"key":' .. str(S.key) .. ',"w":' .. n2(prof.w or 2) .. ',"l":' .. n2(prof.l or 4) .. ',"decel":' .. n2(prof.decel or 6)
        .. ',"mass":' .. n2(prof.mass or 1000) .. '}')
    local parts = {}
    for i, f in ipairs(sc.floors) do parts[i] = str(f) end
    put(',"floors":[' .. table.concat(parts, ",") .. ']')
    parts = {}
    for i, t in ipairs(sc.tiles) do parts[i] = '[' .. t[1] .. ',' .. t[2] .. ',' .. t[3] .. ',' .. t[4] .. ']' end
    put(',"tiles":[' .. table.concat(parts, ",") .. ']')
    parts = {}
    -- the admin's own car, parked in the box at scan time, is not an obstacle
    local cars = {}
    for _, c in ipairs(sc.cars) do
        if not (fr[1] and COTW.dist(c.x, c.y, fr[1][2], fr[1][3]) < 3) then cars[#cars + 1] = c end
    end
    for i, c in ipairs(cars) do
        parts[i] = '[' .. n2(c.x) .. ',' .. n2(c.y) .. ',' .. n2(c.fx) .. ',' .. n2(c.fy) .. ',' .. n2(c.hw) .. ',' .. n2(c.hl) .. ',' .. str(c.key) .. ']'
    end
    put(',"cars":[' .. table.concat(parts, ",") .. ']')
    parts = {}
    for i, z in ipairs(sc.zombies) do parts[i] = '[' .. n2(z[1]) .. ',' .. n2(z[2]) .. ']' end
    put(',"zombies":[' .. table.concat(parts, ",") .. ']')
    parts = {}
    for i, e in ipairs(sc.roads) do
        local p = {}
        for k = 1, #e.p do p[k] = n2(e.p[k]) end
        parts[i] = '{"a":' .. e.a .. ',"b":' .. e.b .. ',"ax":' .. n2(e.ax) .. ',"ay":' .. n2(e.ay) .. ',"bx":' .. n2(e.bx) .. ',"by":' .. n2(e.by)
            .. ',"w":' .. n2(e.w) .. ',"p":[' .. table.concat(p, ",") .. ']}'
    end
    put(',"roads":[' .. table.concat(parts, ",") .. ']')
    parts = {}
    for i, f in ipairs(fr) do
        parts[i] = '[' .. f[1] .. ',' .. n2(f[2]) .. ',' .. n2(f[3]) .. ',' .. n2(f[4]) .. ',' .. n2(f[5]) .. ',' .. n2(f[6]) .. ',' .. n2(f[7]) .. ']'
    end
    put(',"frames":[' .. table.concat(parts, ",") .. ']}\n')
    local name = "COTW_lesson_" .. string.format("%.0f", S.t0) .. ".json"
    local ok = pcall(function()
        local w = getFileWriter(name, true, false)
        for _, s in ipairs(out) do w:write(s) end
        w:close()
    end)
    if not ok then COTW.say("IGUI_COTW_Lesson_Fail")
    elseif #sc.missing > 0 then COTW.say("IGUI_COTW_Lesson_SavedHoles", name, tostring(#sc.missing))
    else COTW.say("IGUI_COTW_Lesson_Saved", name) end
    COTW.log("teach scene " .. name .. " " .. #fr .. " frames, " .. #sc.tiles .. " tiles (" .. #sc.missing .. " never loaded), "
        .. #cars .. " cars (" .. tostring(reason) .. ")")
end

-- ------------------------------------------------------------------------------
-- steps
-- ------------------------------------------------------------------------------
local function condition(v)
    local sum = 0
    pcall(function()
        for i = 0, v:getPartCount() - 1 do
            local part = v:getPartByIndex(i)
            if part then sum = sum + part:getCondition() end
        end
    end)
    return sum
end

function LS.phase() return S and S.phase or nil end

function LS.cancel()
    clearDots()
    S = nil
end

local function stop(reason)
    local done = S
    S = nil          -- first: a failed save must not leave it recording
    clearDots()
    if done and done.frames and #done.frames > 1 then
        S = done     -- save() reads S
        local ok, err = pcall(save, reason)
        S = nil
        if not ok then
            COTW.log("teach scene save error: " .. tostring(err))
            COTW.say("IGUI_COTW_Lesson_Fail")
        end
    end
end

local function inBox(x, y) return x >= S.x1 and x < S.x2 + 1 and y >= S.y1 and y < S.y2 + 1 end

-- the panel button: corner 1, corner 2 (scan), start (in the car, inside the box), stop
function LS.press()
    local p = COTW.player()
    if not p or not COTW.isAdmin() then return end
    local x, y = math.floor(p:getX()), math.floor(p:getY())
    if not S then
        S = { phase = "c1", x1 = x, y1 = y }
        COTW.say("IGUI_COTW_Lesson_C1")
    elseif S.phase == "c1" then
        if math.abs(x - S.x1) < MIN or math.abs(y - S.y1) < MIN then COTW.say("IGUI_COTW_Lesson_Small"); return end
        if math.abs(x - S.x1) > MAX or math.abs(y - S.y1) > MAX then
            x = S.x1 + math.max(-MAX, math.min(MAX, x - S.x1))
            y = S.y1 + math.max(-MAX, math.min(MAX, y - S.y1))
            COTW.say("IGUI_COTW_Lesson_Big")
        end
        S.x1, S.x2 = math.min(S.x1, x), math.max(S.x1, x)
        S.y1, S.y2 = math.min(S.y1, y), math.max(S.y1, y)
        S.scene = scan()
        S.phase = "ready"
        drawFrame()
    elseif S.phase == "ready" then
        local v = COTW.driving()
        if not v then COTW.say("IGUI_COTW_Lesson_Car"); return end
        if not inBox(v:getX(), v:getY()) then COTW.say("IGUI_COTW_Lesson_StartOut"); return end
        fill()
        S.prof, S.key = COTW.profileFor(v)
        S.phase, S.frames, S.t0, S.lastT = "rec", {}, getTimestampMs(), 0
        S.v = v
    else
        stop("button")
    end
end

-- what the panel prints under the admin buttons
function LS.status()
    if not S then return nil end
    if S.phase == "c1" then return getText("IGUI_COTW_Lesson_C1") end
    if S.phase == "ready" then return getText("IGUI_COTW_Lesson_Ready", tostring(S.x2 - S.x1 + 1), tostring(S.y2 - S.y1 + 1)) end
    return getText("IGUI_COTW_Lesson_Rec", string.format("%.1f", (getTimestampMs() - S.t0) / 1000))
end

local function recTick()
    local now = getTimestampMs()
    if now - S.lastT < FRAME_MS then return end
    S.lastT = now
    local v = COTW.driving()
    if not v or v ~= S.v then stop("left"); return end
    local x, y = v:getX(), v:getY()
    if S.lx and COTW.dist(S.lx, S.ly, x, y) > WARP then stop("warp"); return end
    S.lx, S.ly = x, y
    if not inBox(x, y) then
        COTW.say("IGUI_COTW_Lesson_Out")
        stop("out")
        return
    end
    local f = v:getForwardVector(Vector3f.new())
    S.frames[#S.frames + 1] = { now - S.t0, x, y, f:x(), f:z(), v:getCurrentSpeedKmHour(), condition(v) }
    if #S.frames >= MAX_FRAMES then stop("long") end
end

local function onTick()
    local now = getTimestampMs()
    if now - (S.lastFill or 0) >= FRAME_MS then
        S.lastFill = now
        fill()
    end
    if S and S.phase == "rec" then recTick() end
end

Events.OnTick.Add(function()
    if not S or S.phase == "c1" then return end
    local ok, err = pcall(onTick)
    if not ok then
        COTW.log("teach scene error: " .. tostring(err))
        stop("error")
    end
end)
