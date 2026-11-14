-- Cookie On the Way : the autopilot (runs on the driver's client: vehicle physics live there)
-- Speed: the vehicle's own cruise control (regulator), force brake when slower is needed.
-- Steering: wheels cannot be turned from Lua, so the car is yawed with a side push on a long lever
-- under a yaw-rate controller that follows a point a little way ahead on the route (kept right of the
-- centre line on two-lane roads). B42 addImpulse keeps one push per frame (a second equal one is
-- dropped) and gives it to Bullet as force + torque for that frame only, so the push is sized
-- inertia * wanted yaw-rate change / frame time.
-- Road scan: rows across the road from behind the car to the braking distance, checked only where the
-- body (car width + a small margin) would pass. Walls, fences, trees and solid objects count by their
-- tile (fences by the tile edge they sit on), other cars by their own box, people on foot as a small
-- circle. Bushes and water count as solid too; grass and dirt beside the road are drivable.
-- Getting past: side positions off the lane line are tried every quarter tile up to the shoulder and
-- grass beside the road (cheapest = closest to the lane, on the road); each is tried straight on and
-- as a detour that comes back to the lane once the body is past what blocks it. The first clear one
-- becomes the plan and the car eases over to it, slowing first when the gap needs a short swerve.
-- Nothing clear: stop before it, planned on a weaker brake than the car has plus a reaction gap.
-- Moving cars are followed, not passed; zombies only slow the car (push through). A zombie pushed
-- along on the bumper is shaken off: a hard brake, then (still there) a quick wiggle.
-- Sharp bends into narrow roads: the car aims at the bend itself and rounds it close, slower the
-- narrower the road, instead of cutting the corner.
-- Holding a drive key for 1 s hands the car back (counts as arrived); the HUD "stop here" button stops
-- and charges by distance + EmergencyFeePct.
-- Braking: the first clean full brake of a trip (straight on, no trailer, nothing knocking the car) is
-- measured and sent to the server, which nudges the model's braking toward it (brakeObs).

require "CookieOnTheWay/COTW_Client"

COTW.Driver = COTW.Driver or {}
local D = COTW.Driver

local TUNE = {
    HOLD_MS     = 1000,   -- drive key held this long = player takes over
    ARRIVE      = 6,      -- tiles left on the route = there
    OFFROUTE    = 15,     -- tiles off the route = stop and end by distance
    LANE_MAX    = 2.5,    -- keep right by up to this many tiles on roads 6+ wide
    STEER_GAIN  = 0.15,   -- share of the yaw-rate error corrected per tick
    YAW_I       = 3.0,    -- integral gain on the yaw-rate error
    PROBE_TICKS = 12,     -- first trip: fixed push this many ticks to learn the steering sign
    PROBE_STEP  = 0.03,   -- rad/s per tick asked during that push
    PROBE_MIN   = 0.02,   -- rad/s the push must change the yaw rate by, else the probe runs again
    PROBE_WAIT  = 60,     -- ticks before a weak probe runs again
    DW_MAX      = 0.15,   -- rad/s of yaw-rate change asked in one tick at most
    LEVER       = 20,     -- m: lever of the side push (long = mostly turn, little sideways shove)
    ERR_SLOW    = 1.0,    -- rad of heading error at which the car is down to crawling speed
    STOP_GAP    = 2.0,    -- tiles kept between the bumper and something the car stops for
    BRAKE_SAFE  = 0.7,    -- share of the car's braking counted on when stopping for something
    REACT       = 0.35,   -- s of driving on before the brakes bite (scan interval + brake response)
    BRAKE_OVER  = 3,      -- km/h over the target speed before the brakes come on (below: cruise control eases off)
    BRAKE_OVER_HIT = 0.5, -- the same while stopping for something in the way (no coasting into it)
    HEAD_GAIN   = 2.0,    -- yaw rate (rad/s) asked per rad of heading error
    LAT_ACCEL   = 4.0,    -- m/s^2 allowed sideways (caps the yaw rate at speed)
    TURN_ACCEL  = 3.0,    -- m/s^2 used to pick a corner speed
    SENSE_EVERY = 4,      -- ticks between road scans
    STUCK_MS    = 10000,  -- crawling < 1.5 km/h this long with nothing blocking = stuck
    PROG_MS     = 500,
    LEAD_STALE  = 3000,
    -- road scan / getting past things
    MARGIN      = 0.15,   -- m kept clear on each side of the body (+ up to one CELL)
    NEAR        = 2,      -- tiles past the bumper checked against the bare body (pulling away from a fence close by)
    ROW         = 0.75,   -- m between scanned rows (shorter than anything the car must not hit)
    CELL        = 0.25,   -- m between points across a row
    SCAN_MAX    = 70,     -- tiles scanned ahead at most
    AVOID_MAX   = 8,      -- tiles the car may leave its lane line by to get past something
    ROAD_EDGE   = 4.5,    -- tiles past the road edge the car centre may go (shoulder, grass)
    OFFROAD_COST = 2,     -- plan cost per tile of body off the road (on-road gaps first)
    SIDE_STEP   = 0.25,   -- tiles between the side positions tried
    BESIDE_PAD  = 0.25,   -- extra tiles kept from things beside the body when moving over toward them
    SIDE_ACCEL  = 2.5,    -- m/s^2 sideways while moving over
    SWERVE_KMH  = { 12, 5 },  -- slower (shorter) swerves tried when the gap is too close at speed
    AVOID_KMH   = 30,     -- top speed while off the lane line
    OFFROAD_KMH = 20,     -- top speed with the body off the road
    MOVING_KMH  = 3,      -- cars faster than this are followed, not driven round
    CAR_TTL     = 3000,   -- ms a "which car is on this tile" answer is kept (found cars are re-read every scan)
    -- bends into narrow roads
    BEND_ANGLE  = 0.5,    -- rad: a sharper bend between roads narrower than BEND_WIDTH shortens the look-ahead
    BEND_WIDTH  = 8,
    BEND_AHEAD  = 3,      -- tiles looked ahead at least while rounding such a bend
    -- a zombie stuck on the front bumper
    SHAKE_PUSH  = 2.5,    -- tiles the same zombie was pushed along at the bumper
    SHAKE_BRAKE_MS  = 700,
    SHAKE_SWERVE_MS = 900,
    SHAKE_YAW   = 0.8,    -- rad/s added to the asked yaw rate, one way then the other
    SHAKE_RESET_MS  = 4000,   -- no shake this long: the next one starts with the brake again
    -- measuring real braking (only ticks with the force brake on count, the autopilot brakes in pulses)
    BM_KMH      = 8,      -- km/h at least while measuring
    BM_MS       = 1000,   -- ms of braking added up before the measure is sent
    BM_KNOCK    = 3,      -- km/h lost in one tick: something hit the car, start over
    BM_HEAD     = 0.15,   -- rad of heading error at most (straight on)
}
D.TUNE = TUNE

local st = nil
D.steerSign = D.steerSign or 1      -- learnt once per session, kept for later trips

-- ------------------------------------------------------------------------------
-- route geometry
-- ------------------------------------------------------------------------------
-- route.w has the width of the road each point was put down by (the road leading in to it; a
-- junction carries the road it ends), so segment k (point k to k + 1) is road route.w[k + 1].
-- R.w = per point (as given), R.sw = per segment (what the car on segment k drives on).
local function prepare(route)
    local n = #route.x
    local x, y, w, sw, lane = {}, {}, {}, {}, {}
    for i = 1, n do w[i] = route.w[i] or route.w[i - 1] or 8 end
    for k = 1, n - 1 do sw[k] = w[k + 1] end
    sw[n] = sw[n - 1] or w[n]
    for i = 1, n do
        local a = math.max(1, i - 1)
        local b = math.min(n, i + 1)
        local dx, dy = route.x[b] - route.x[a], route.y[b] - route.y[a]
        local L = math.sqrt(dx * dx + dy * dy)
        -- a junction keeps right only as far as the narrower of its two roads does, so the lane
        -- line enters a side street in its middle instead of slanting across its mouth
        local laneW = math.min(w[i], sw[i])
        local off = laneW >= 6 and math.min(TUNE.LANE_MAX, laneW / 4) or 0
        if i == n then off = 0 end
        if L > 0 then
            -- right of the travel direction (world y grows south)
            x[i] = route.x[i] - dy / L * off
            y[i] = route.y[i] + dx / L * off
        else
            x[i], y[i] = route.x[i], route.y[i]
        end
        lane[i] = off
    end
    local cum = { 0 }
    for i = 2, n do cum[i] = cum[i - 1] + COTW.dist(x[i - 1], y[i - 1], x[i], y[i]) end
    return { x = x, y = y, w = w, sw = sw, lane = lane, cum = cum, n = n, len = cum[n] }
end

-- point and unit direction at distance pos along the prepared route
local function pointAt(R, pos, hint)
    if pos <= 0 then pos = 0 end
    if pos >= R.len then pos = R.len end
    local k = math.max(1, (hint or 1) - 1)
    while k < R.n - 1 and R.cum[k + 1] < pos do k = k + 1 end
    while k > 1 and R.cum[k] > pos do k = k - 1 end
    local seg = R.cum[k + 1] - R.cum[k]
    local t = seg > 0 and (pos - R.cum[k]) / seg or 0
    local dx, dy = R.x[k + 1] - R.x[k], R.y[k + 1] - R.y[k]
    local L = math.sqrt(dx * dx + dy * dy)
    if L == 0 then L = 1 end
    return R.x[k] + dx * t, R.y[k] + dy * t, dx / L, dy / L, k
end

-- project (px, py) on segments near idx: pos along route, distance off it, segment, side (+ = right)
local function locate(R, px, py, idx)
    local best, bpos, bk, side = nil, 0, idx, 0
    for k = math.max(1, idx - 2), math.min(R.n - 1, idx + 20) do
        local x1, y1, x2, y2 = R.x[k], R.y[k], R.x[k + 1], R.y[k + 1]
        local vx, vy = x2 - x1, y2 - y1
        local L2 = vx * vx + vy * vy
        local t = 0
        if L2 > 0 then t = math.max(0, math.min(1, ((px - x1) * vx + (py - y1) * vy) / L2)) end
        local d = COTW.dist(px, py, x1 + vx * t, y1 + vy * t)
        if not best or d < best then
            best, bk = d, k
            local L = math.sqrt(L2)
            bpos = R.cum[k] + t * L
            side = L > 0 and ((px - x1) * -vy + (py - y1) * vx) / L or 0
        end
    end
    return bpos, best or 0, bk, side
end

local function wrap(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

-- slowest corner speed (km/h) we must be able to reach within the next stretch of road, and
-- whether that corner is a bend into / out of a narrow road
local function cornerCap(R, pos, idx, decel)
    local cap, tight = 999, false
    local k = idx + 1
    while k < R.n and R.cum[k] - pos < 70 do
        local ax, ay = R.x[k] - R.x[k - 1], R.y[k] - R.y[k - 1]
        local bx, by = R.x[k + 1] - R.x[k], R.y[k + 1] - R.y[k]
        local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
        if la > 0 and lb > 0 then
            local ang = math.abs(wrap(math.atan2(by, bx) - math.atan2(ay, ax)))
            if ang > 0.15 then
                -- radius of the arc that cuts this corner using the shorter neighbouring leg
                local r = math.min(la, lb, 12) / (2 * math.tan(ang / 2))
                -- and no wider than the narrower road leaves room for: an arc of radius r strays
                -- r * (1 / cos(ang / 2) - 1) inside the corner, the body leaves (width - 2) / 2
                local wN = math.min(R.w[k] or 8, R.w[k + 1] or R.w[k] or 8)
                local stray = 1 / math.cos(ang / 2) - 1
                if stray > 0.01 then r = math.min(r, math.max(2, (wN - 2) / 2 / stray)) end
                local vt = math.sqrt(TUNE.TURN_ACCEL * math.max(r, 2))
                local dist = math.max(0, R.cum[k] - pos - 2)
                local v = math.sqrt(vt * vt + 2 * decel * dist) * 3.6
                if wN < TUNE.BEND_WIDTH then
                    -- into / out of a narrow road: be down to speed in time on a weaker brake, after
                    -- a moment of driving on (as when stopping for something)
                    local a = decel * TUNE.BRAKE_SAFE
                    local v0 = math.sqrt(vt * vt + 2 * a * dist)
                    v = math.sqrt(vt * vt + 2 * a * math.max(0, dist - TUNE.REACT * v0)) * 3.6
                end
                if v < cap then cap, tight = v, wN < TUNE.BEND_WIDTH end
            end
        end
        k = k + 1
    end
    return cap, tight
end

-- the next sharp bend within maxD where a narrow road starts or ends: distance to it and the
-- narrower width, nil = none
local function nextBend(R, pos, idx, maxD)
    local k = idx + 1
    while k < R.n and R.cum[k] - pos <= maxD do
        if R.cum[k] > pos then
            local wN = math.min(R.w[k] or 8, R.w[k + 1] or R.w[k] or 8)
            if wN < TUNE.BEND_WIDTH then
                local a = math.atan2(R.y[k] - R.y[k - 1], R.x[k] - R.x[k - 1])
                local b = math.atan2(R.y[k + 1] - R.y[k], R.x[k + 1] - R.x[k])
                if math.abs(wrap(b - a)) > TUNE.BEND_ANGLE then return R.cum[k] - pos, wN end
            end
        end
        k = k + 1
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- plan: where across the road the car drives (tiles right of the lane line)
-- { s0 = route pos it was made at, d0 = side then, c = side to reach, T = tiles used to get there,
--   v = speed (m/s) T was sized for, back = route pos where it heads back to the lane line (detour),
--   T2 = tiles used for that }; nil = on the lane line
-- ------------------------------------------------------------------------------
local function smooth(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return t * t * (3 - 2 * t)
end

local function offsetAt(P, pos)
    if not P then return 0 end
    if P.back and pos > P.back then
        local ob = P.d0 + (P.c - P.d0) * smooth((P.back - P.s0) / P.T)
        return ob * (1 - smooth((pos - P.back) / P.T2))
    end
    return P.d0 + (P.c - P.d0) * smooth((pos - P.s0) / P.T)
end

-- route pos where plan P is done with (back on the lane line and settled), nil = holds its side
local function planEnd(P)
    if P.back then return P.back + P.T2 end
    if P.c == 0 then return P.s0 + P.T end
    return nil
end

-- tiles of road an S-shaped move of `delta` tiles takes at vms (sideways pull capped at SIDE_ACCEL)
local function moveLen(delta, vms)
    local a = math.abs(delta)
    if a < 0.3 then return 2 end
    return math.max(3 + a, vms * math.sqrt(2 * math.pi * a / TUNE.SIDE_ACCEL))
end

-- fastest speed (km/h) that still stops within room tiles: counting on a weaker brake than the
-- car has and a moment of driving on first; lead = m/s the thing ahead moves away at
local function stopKmh(room, decel, lead)
    local a = decel * TUNE.BRAKE_SAFE
    local v = a * (math.sqrt(TUNE.REACT * TUNE.REACT + 2 * math.max(0, room) / a) - TUNE.REACT)
    if lead and lead > 0 then v = math.sqrt(v * v + lead * lead) end
    return v * 3.6
end

-- ------------------------------------------------------------------------------
-- road scan
-- ------------------------------------------------------------------------------
local NONE = {}

-- what stands on a square: s = solid (whole tile: also trees of any size and bushes), wet = water
-- (solid only off the road: a road over water is a bridge), n / w = wall or fence on the north / west
-- edge. NONE = nothing. tileInfo keeps it for the trip (nil = not loaded, not kept)
local function readTile(sq)
    local ok, s, n, w = pcall(function()
        return sq:isSolid() or sq:isSolidTrans() or sq:HasTree(), sq:has(IsoFlagType.collideN), sq:has(IsoFlagType.collideW)
    end)
    -- bushes / water on their own, so a flag this build lacks cannot hide the walls above
    local wet = false
    if ok and not s then
        local ok2, bush, water = pcall(function()
            return IsoFlagType.canBeCut ~= nil and sq:has(IsoFlagType.canBeCut), IsoFlagType.water ~= nil and sq:has(IsoFlagType.water)
        end)
        if ok2 then s, wet = bush or false, water or false end
    end
    if ok and (s or n or w or wet) then return { s = s, n = n, w = w, wet = wet } end
    return NONE
end
D.readTile = readTile     -- teach scenes record tiles the same way

local function tileInfo(cell, x, y)
    local key = x * 100000 + y
    local t = st.tiles[key]
    if t ~= nil then return t end
    local sq = cell:getGridSquare(x, y, 0)
    if not sq then return nil end
    t = readTile(sq)
    st.tileCount = st.tileCount + 1
    if st.tileCount > 30000 then st.tiles, st.tileCount = {}, 0 end
    st.tiles[key] = t
    return t
end

-- remember any car standing on this tile (asked again after CAR_TTL)
local function findCar(cell, x, y, now)
    local key = x * 100000 + y
    local seen = st.carTiles[key]
    if seen and now - seen < TUNE.CAR_TTL then return end
    st.carTiles[key] = now
    st.carTileCount = st.carTileCount + 1
    if st.carTileCount > 6000 then st.carTiles, st.carTileCount = {}, 0 end
    local sq = cell:getGridSquare(x, y, 0)
    local car = sq and sq:getVehicleContainer()
    if car then st.cars[car] = true end
end

local function carBox(car)
    local f = car:getForwardVector(Vector3f.new())
    local fx, fy = f:x(), f:z()
    local L = math.sqrt(fx * fx + fy * fy)
    if L < 0.01 then fx, fy, L = 1, 0, 1 end
    local ext = car:getScript():getExtents()
    local kmh = car:getCurrentSpeedKmHour()
    return {
        x = car:getX(), y = car:getY(), fx = fx / L, fy = fy / L, hw = ext:x() / 2, hl = ext:z() / 2,
        v = kmh / 3.6, moving = math.abs(kmh) > TUNE.MOVING_KMH,
    }
end

-- cars close enough to row i to matter
local function rowBoxes(sc, i)
    local list = sc.rowBoxes[i]
    if list then return list end
    list = {}
    local row = sc.rows[i]
    for _, b in ipairs(sc.boxes) do
        if COTW.dist(row.x, row.y, b.x, b.y) < sc.reach + b.hl + b.hw then list[#list + 1] = b end
    end
    sc.rowBoxes[i] = list
    return list
end

-- is world point (wx, wy) inside something? true, the car's box, or false. moving = count cars that
-- are driving too. A wall / fence is a band tn (north edge) / tw (west edge) thick on each side of its
-- tile edge: thin across the road, thick enough along it that no row of points steps over it.
-- onRoad = the point is on the road surface (water there is under a bridge)
local function hitAt(sc, wx, wy, moving, boxes, tn, tw, onRoad)
    local tx, ty = math.floor(wx), math.floor(wy)
    local fx, fy = wx - tx, wy - ty
    local t = tileInfo(sc.cell, tx, ty)
    if t == nil then
        sc.unloaded = true
    elseif t ~= NONE then
        if (t.s or (t.wet and not onRoad)) and fx > 0.1 and fx < 0.9 and fy > 0.1 and fy < 0.9 then return true end
        if t.n and fy < tn then return true end
        if t.w and fx < tw then return true end
    end
    -- the neighbours' north / west edges are this tile's south / east edges
    if fy > 1 - tn then
        local u = tileInfo(sc.cell, tx, ty + 1)
        if u and u.n then return true end
    end
    if fx > 1 - tw then
        local u = tileInfo(sc.cell, tx + 1, ty)
        if u and u.w then return true end
    end
    for i = 1, #boxes do
        local b = boxes[i]
        if moving or not b.moving then
            local ex, ey = wx - b.x, wy - b.y
            if math.abs(ex * b.fx + ey * b.fy) < b.hl and math.abs(ey * b.fx - ex * b.fy) < b.hw then return b end
        end
    end
    for i = 1, #sc.people do
        local p = sc.people[i]
        local ex, ey = wx - p.x, wy - p.y
        if ex * ex + ey * ey < 0.2 then return true end
    end
    return false
end

-- row i, point j (j * CELL tiles right of the lane line), remembered for this scan
local function occ(sc, i, j, moving)
    local memo = moving and sc.occM or sc.occ
    local key = i * 2000 + j
    local v = memo[key]
    if v == nil then
        local row = sc.rows[i]
        local d = j * TUNE.CELL
        local tn = math.max(0.2, TUNE.ROW / 2 * math.abs(row.dy) + 0.05)
        local tw = math.max(0.2, TUNE.ROW / 2 * math.abs(row.dx) + 0.05)
        -- on the road surface by the lane offset at both ends of the segment (it changes along a
        -- segment next to a junction), so water just off the road never passes for a bridge
        local R, k = st.R, row.k
        local roadHalf = (R.sw[k] or 8) / 2
        local onRoad = math.abs(d + (R.lane[k] or 0)) <= roadHalf and math.abs(d + (R.lane[k + 1] or R.lane[k] or 0)) <= roadHalf
        v = hitAt(sc, row.x - row.dy * d, row.y + row.dx * d, moving, rowBoxes(sc, i), tn, tw, onRoad)
        memo[key] = v
    end
    return v
end

-- side position of plan P at s tiles ahead of the car (behind: where the car is now)
local function sideAt(sc, P, s)
    if s <= 0 then return sc.d end
    return offsetAt(P, st.pos + s)
end

-- first row the body (and trailer) would touch something on plan P: its s, index and what (true or a
-- car box); nil = clear to the end
local function firstHit(sc, P, moving)
    local hw, half, rear, cell = sc.hw, sc.half, sc.rear, TUNE.CELL
    for i = 1, sc.n do
        local r = sc.rows[i].s
        -- the body covers this row while its centre is between r - half and r + rear
        local a, b = sideAt(sc, P, r - half), sideAt(sc, P, r + rear)
        local near = r >= half and r < half + TUNE.NEAR
        local w = near and sc.body or hw
        local lo, hi = math.min(a, b) - w, math.max(a, b) + w
        -- beside the body now: only room it would newly swing into (the body's own band plus one
        -- point is skipped, so something already close beside the car never counts for staying put)
        local skipLo, skipHi = 1, 0
        if r < half then
            skipLo, skipHi = sc.d - hw - cell, sc.d + hw + cell
            -- moving over while alongside something: extra room on the side it moves to
            if math.min(a, b) < sc.d - 0.01 then lo = lo - TUNE.BESIDE_PAD end
            if math.max(a, b) > sc.d + 0.01 then hi = hi + TUNE.BESIDE_PAD end
        end
        -- one point past each edge so nothing slips in between the points and the body; just past
        -- the bumper only points on the body itself (every plan still starts where the car is)
        local j1, j2 = math.floor(lo / cell), math.ceil(hi / cell)
        if near then j1, j2 = math.ceil(lo / cell), math.floor(hi / cell) end
        local memo = moving and sc.occM or sc.occ
        for j = j1, j2 do
            local dj = j * cell
            if dj < skipLo or dj > skipHi then
                -- the remembered answer first (most points are asked by many plans)
                local what = memo[i * 2000 + j]
                if what == nil then what = occ(sc, i, j, moving) end
                if what then return r, i, what end
            end
        end
    end
    return nil
end

-- is row i blocked right across lo..hi (side positions) plus the body: no run of free points wide
-- enough for the body anywhere, so no plan gets past it
local function wallRow(sc, i, lo, hi)
    local cell = TUNE.CELL
    local need, run = 2 * sc.hw, 0
    for j = math.floor((lo - sc.hw) / cell), math.ceil((hi + sc.hw) / cell) do
        if occ(sc, i, j) then run = 0 else run = run + 1 end
        if (run - 1) * cell >= need then return false end
    end
    return true
end

local function makePlan(sc, c, vms)
    return { s0 = st.pos, d0 = sc.d, c = c, T = moveLen(c - sc.d, vms), v = vms }
end

-- s of the last row of what blocks the lane line (parked things only), once the body would fit in
-- the clear stretch after it; nil = lane clear, or blocked to the end of the scan
local function laneBlockEnd(sc)
    local cell = TUNE.CELL
    local j1, j2 = math.floor(-sc.hw / cell), math.ceil(sc.hw / cell)
    local last = nil
    for i = 1, sc.n do
        local r = sc.rows[i].s
        local hit = false
        for j = j1, j2 do
            if occ(sc, i, j) then hit = true; break end
        end
        if hit then
            last = r
        elseif last and r - last > sc.half + sc.rear + 1 then
            return last
        end
    end
    return nil
end

-- side position c straight on, and (when that runs into something) as a detour heading back to
-- the lane line at `back`: the plan that gets furthest, and its hit (nil = clear)
local function tryPlan(sc, c, vms, back)
    local Q = makePlan(sc, c, vms)
    local h = firstHit(sc, Q)
    if not h or not back or math.abs(c) < 0.01 or back <= st.pos then return Q, h end
    -- the detour is the same plan until the body reaches `back`: a hit before that stays
    if st.pos + h + sc.rear < back then return Q, h end
    local B = makePlan(sc, c, vms)
    B.back, B.T2 = back, moveLen(c, vms)
    local h2 = firstHit(sc, B)
    if not h2 or h2 > h then return B, h2 end
    return Q, h
end

-- pick where to drive: { plan, hit } (hit = s the plan runs into, nil when clear), plus `slow`:
-- a plan that only works after slowing to slow.v
local function choose(sc, vms)
    local P = st.plan or makePlan(sc, 0, vms)
    local k = st.idx
    local lim = (st.R.sw[k] or 8) / 2 + TUNE.ROAD_EDGE
    local lane = st.R.lane[k] or 0
    local lo = math.max(-TUNE.AVOID_MAX, -lim - lane)
    local hi = math.min(TUNE.AVOID_MAX, lim - lane)
    -- cost: off the lane line, away from the current plan, and the body hanging off the road
    local roadHalf = (st.R.sw[k] or 8) / 2
    local body = (st.prof.w or 2) / 2
    local list = {}
    local function add(c)
        local over = math.max(0, math.abs(c + lane) + body - roadHalf)
        list[#list + 1] = { c = c, cost = math.abs(c) + 0.6 * math.abs(c - P.c) + TUNE.OFFROAD_COST * over }
    end
    local c = math.ceil(lo / TUNE.SIDE_STEP) * TUNE.SIDE_STEP
    while c <= hi + 0.001 do
        add(c)
        c = c + TUNE.SIDE_STEP
    end
    -- and straight on from where the car is (never sweeps into anything beside it)
    if math.abs(sc.d - P.c) >= 0.01 then add(sc.d) end
    table.sort(list, function(a, b) return a.cost < b.cost end)

    -- the plan we have, unless something closer to the lane line is clear
    local curHit, curI = firstHit(sc, P)
    -- blocked right across everything the car may use (a fence over the road): nothing to try
    if curHit and curHit >= sc.half and wallRow(sc, curI, lo, hi) then return { plan = P, hit = curHit } end
    local pCost = math.abs(P.c)
    local best, bestHit = P, curHit
    -- where a detour may head back: once the rear is past what blocks the lane line
    local back = curHit and laneBlockEnd(sc)
    if back then back = st.pos + back + sc.rear + 0.5 end
    -- something beside the car counts as worse than anything ahead (braking does not help there)
    local function score(h) return h < sc.half and h - 100 or h end
    -- a side position already reached before the row the current plan hits, and blocked on that
    -- row: it can be neither clear nor get further (the body itself, inner points only)
    local function deadAt(c)
        if not curHit or curHit < sc.half or moveLen(c - sc.d, vms) > curHit - sc.half then return false end
        -- its detour may already be on the way back to the lane line by that row
        if back and st.pos + curHit + sc.rear >= back then return false end
        local cell = TUNE.CELL
        for j = math.ceil((c - sc.body) / cell), math.floor((c + sc.body) / cell) do
            if occ(sc, curI, j) then return true end
        end
        return false
    end
    for _, e in ipairs(list) do
        if not curHit and e.cost >= pCost then return { plan = P } end
        if (math.abs(e.c - P.c) >= 0.01 or (curHit and back and not P.back)) and not deadAt(e.c) then
            local Q, h = tryPlan(sc, e.c, vms, back)
            if not h then return { plan = Q } end
            e.h, e.T = h, Q.T
            -- nothing clear: the side position that gets clearly furthest
            if curHit and score(h) > score(bestHit) + 2 then best, bestHit = Q, h end
        end
    end
    if not curHit then return { plan = P } end
    -- too close for a swerve at this speed: one after slowing down? (only where the full-speed try
    -- ran into something while still moving over; slowing does not help past that)
    for _, kmh in ipairs(TUNE.SWERVE_KMH) do
        local vs = kmh / 3.6
        if vs < vms - 0.3 then
            for _, e in ipairs(list) do
                if e.h and e.h <= e.T + sc.half + 2 then
                    local Q, h = tryPlan(sc, e.c, vs, back)
                    if not h then return { plan = P, hit = curHit, slow = Q } end
                end
            end
        end
    end
    return { plan = best, hit = bestHit }
end

local function findPeople(sc, v, look)
    local list = getOnlinePlayers and getOnlinePlayers()
    if not list then return end
    local me = getSpecificPlayer(0)
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p ~= me and not p:getVehicle() and COTW.dist(p:getX(), p:getY(), v:getX(), v:getY()) < look + 10 then
            sc.people[#sc.people + 1] = { x = p:getX(), y = p:getY() }
        end
    end
end

-- zombies under the planned path (they slow the car, never stop it)
local function countZombies(sc, P)
    local n, seen = 0, {}
    local edge = sc.hw - 0.3
    for i = 1, sc.n, 2 do
        local row = sc.rows[i]
        if row.s >= sc.half then
            local c = sideAt(sc, P, row.s)
            for o = -1, 1 do
                local d = c + o * edge
                local x, y = math.floor(row.x - row.dy * d), math.floor(row.y + row.dx * d)
                local key = x * 100000 + y
                if not seen[key] then
                    seen[key] = true
                    local sq = sc.cell:getGridSquare(x, y, 0)
                    local movers = sq and sq:getMovingObjects()
                    if movers then
                        for m = 0, movers:size() - 1 do
                            local z = movers:get(m)
                            if instanceof(z, "IsoZombie") and not z:isDead() then n = n + 1 end
                        end
                    end
                end
            end
        end
    end
    return n
end

-- zombies pressed on the front bumper while the car goes on (pushed along instead of knocked
-- down): tiles the car has pushed the longest-held one. Kept per zombie between scans in st.pushed.
local function frontZombies(sc, v)
    local f = v:getForwardVector(Vector3f.new())
    local fx, fy = f:x(), f:z()
    local L = math.sqrt(fx * fx + fy * fy)
    if L < 0.01 then return 0 end
    fx, fy = fx / L, fy / L
    local cx, cy = v:getX(), v:getY()
    local mx, my = cx + fx * (sc.half + 0.5), cy + fy * (sc.half + 0.5)
    local prev, seen, worst = st.pushed or {}, {}, 0
    for x = math.floor(mx - 1.5), math.floor(mx + 1.5) do
        for y = math.floor(my - 1.5), math.floor(my + 1.5) do
            local sq = sc.cell:getGridSquare(x, y, 0)
            local movers = sq and sq:getMovingObjects()
            if movers then
                for m = 0, movers:size() - 1 do
                    local z = movers:get(m)
                    if instanceof(z, "IsoZombie") and not z:isDead() then
                        local ex, ey = z:getX() - cx, z:getY() - cy
                        local along = ex * fx + ey * fy
                        if along > sc.half - 0.4 and along < sc.half + 1.2 and math.abs(ey * fx - ex * fy) < sc.body + 0.3 then
                            local at = prev[z] or st.pos
                            seen[z] = at
                            if st.pos - at > worst then worst = st.pos - at end
                        end
                    end
                end
            end
        end
    end
    st.pushed = seen
    return worst
end

-- room for a short wiggle to side dir (+1 right, -1 left) of where the car is now: it moves the car
-- about 0.7 tiles over within the next few tiles
local function sideRoom(sc, dir)
    local cell = TUNE.CELL
    for i = 1, sc.n do
        if sc.rows[i].s > sc.half + 5 then break end
        for o = 1, 4 do
            if occ(sc, i, math.floor((sc.d + dir * (sc.hw + o * cell)) / cell + 0.5)) then return false end
        end
    end
    return true
end

local function sense(v, trailer)
    local R, prof = st.R, st.prof
    local vms = math.abs(v:getCurrentSpeedKmHour()) / 3.6
    local decel = prof.decel or 6
    local half = (prof.l or 4) / 2
    local look = math.min(TUNE.SCAN_MAX, vms * vms / (2 * decel * TUNE.BRAKE_SAFE) + vms * TUNE.REACT + half + 12)
    local now = getTimestampMs()
    local sc = {
        cell = getCell(), half = half, rear = half + (prof.tl and prof.tl + 1 or 0),
        body = (prof.w or 2) / 2, hw = (prof.w or 2) / 2 + TUNE.MARGIN, d = st.side or 0,
        rows = {}, occ = {}, occM = {}, boxes = {}, rowBoxes = {}, people = {},
    }
    sc.reach = TUNE.AVOID_MAX + sc.hw + 1
    local s, n, k = -sc.rear, 0, st.idx
    while s <= look do
        local x, y, dx, dy, kk = pointAt(R, st.pos + s, k)
        k = kk
        n = n + 1
        sc.rows[n] = { s = s, x = x, y = y, dx = dx, dy = dy, k = kk }
        s = s + TUNE.ROW
    end
    sc.n = n

    -- cars: every third scan look for new ones on tiles fixed along the route (every 1.5 tiles),
    -- then re-read all the known ones every scan
    st.scans = st.scans + 1
    if st.scans % 3 == 1 then
        local wide = TUNE.AVOID_MAX + sc.hw + 2
        local a = math.ceil((st.pos - sc.rear) / 1.5) * 1.5
        k = st.idx
        while a <= st.pos + look do
            local x, y, dx, dy, kk = pointAt(R, a, k)
            k = kk
            local o = -wide
            while o <= wide do
                findCar(sc.cell, math.floor(x - dy * o), math.floor(y + dx * o), now)
                o = o + 1.5
            end
            a = a + 1.5
        end
    end
    for car in pairs(st.cars) do
        local keep = car ~= v and car ~= trailer and not car:isRemovedFromWorld()
            and COTW.dist(car:getX(), car:getY(), v:getX(), v:getY()) < look + 20
        if keep then
            local ok, box = pcall(carBox, car)
            if ok then
                sc.boxes[#sc.boxes + 1] = box
                if box.moving then sc.anyMoving = true end
            end
        else
            st.cars[car] = nil
        end
    end
    findPeople(sc, v, look)

    local pick = choose(sc, vms)
    local P = pick.plan
    local res = { limit = 999, plan = P }
    local function cap(limit, why)
        if limit < res.limit then res.limit, res.why = limit, why end
    end
    -- something ahead on the way: stop before it (beside the car braking does not help; the plan
    -- that sweeps into it was already passed over)
    if pick.hit and pick.hit >= half then
        local room = math.max(0, pick.hit - half - TUNE.STOP_GAP)
        res.stopFor = stopKmh(room, decel)
        cap(res.stopFor, "obstacle")
        res.blocked = room < 1
    end
    if pick.slow then
        -- reach the slower swerve speed while there is still room to swerve
        local vs = pick.slow.v
        local room = math.max(0, (pick.hit or look) - half - pick.slow.T - 1)
        cap(math.max(vs * 3.6, math.sqrt(vs * vs + 2 * decel * room) * 3.6), "avoid")
        res.slow = pick.slow
    end
    -- driving cars on the path: follow (as 0.2.0 did), able to stop by the time we reach where it
    -- will have stopped: its own speed along our way counts
    local mh, mi, what
    if sc.anyMoving then mh, mi, what = firstHit(sc, P, true) end
    if mh and mh >= half and (not pick.hit or mh < pick.hit) then
        local room = math.max(0, mh - half - TUNE.STOP_GAP)
        local lead = 0
        if type(what) == "table" then
            local row = sc.rows[mi]
            lead = math.max(0, what.v * (what.fx * row.dx + what.fy * row.dy))
        end
        cap(stopKmh(room, decel, lead), "obstacle")
    end
    -- off the lane line now or just ahead, or moving over (out, or back on a detour)
    local offNow, offAhead = offsetAt(P, st.pos), offsetAt(P, st.pos + half + 6)
    if math.max(math.abs(offNow), math.abs(offAhead)) > 1 then cap(TUNE.AVOID_KMH, "avoid") end
    local shifting = (math.abs(P.c - P.d0) > 0.5 and st.pos < P.s0 + P.T)
        or (P.back and st.pos > P.back - half - 6 and st.pos < P.back + P.T2)
    if shifting then cap(math.max(TUNE.SWERVE_KMH[1], P.v * 3.6 + 3), "avoid") end
    -- the body over the road edge (shoulder, grass)
    local lane, roadHalf = R.lane[st.idx] or 0, (R.sw[st.idx] or 8) / 2
    if math.max(math.abs(offNow + lane), math.abs(offAhead + lane)) + sc.body > roadHalf + 0.5 then cap(TUNE.OFFROAD_KMH, "avoid") end
    local zombies = countZombies(sc, P)
    if zombies > 0 then cap(COTW.opt("ZombieSpeed"), "zombie"); res.zombies = zombies end
    -- a zombie stuck on the bumper: how long it has been pushed, and which way a wiggle has room
    res.pushed = frontZombies(sc, v)
    if res.pushed >= TUNE.SHAKE_PUSH then res.room = { [1] = sideRoom(sc, 1), [-1] = sideRoom(sc, -1) } end
    if sc.unloaded then cap(25, "unloaded") end
    return res
end

-- ------------------------------------------------------------------------------
-- control
-- ------------------------------------------------------------------------------
local function keys()
    if not st.keys then
        st.keys = {}
        for _, name in ipairs({ "Forward", "Backward", "Left", "Right" }) do
            local k = getCore():getKey(name)
            if k and k > 0 then st.keys[#st.keys + 1] = k end
        end
    end
    for _, k in ipairs(st.keys) do
        if isKeyDown(k) then return true end
    end
    return false
end

local function release(v)
    if not v then return end
    pcall(function() v:setRegulator(false) end)
end

-- real braking: the speed lost over ticks that followed a clean full brake (straight on, not moving
-- off the lane line, no zombie on the bumper, no trailer) is added up until BM_MS of braking, then sent once.
-- braking = the force brake goes on this tick (this tick's speed shows what the last one did)
local function brakeMeasure(braking, aspeed, now)
    if st.brakeSent or st.trailer then return end
    local bm = st.bm
    if bm and bm.on then
        local dv, dt = bm.v - aspeed, now - bm.t
        if dv > TUNE.BM_KNOCK or dv < -0.5 then
            bm.sv, bm.st = 0, 0      -- knocked or pushed: not a brake, start over
        elseif dt > 0 and dt < 100 then
            bm.sv, bm.st = bm.sv + dv, bm.st + dt
            if bm.st >= TUNE.BM_MS and bm.sv > 5 then
                st.brakeSent = true
                COTW.send("brakeObs", { decel = bm.sv / 3.6 / (bm.st / 1000) })
                return
            end
        end
    end
    bm = bm or { sv = 0, st = 0 }
    st.bm = bm
    local P = st.plan     -- (a plan that keeps the lane line is fine: stopping before something)
    local swerve = P and (math.abs(P.c or 0) > 0.3 or math.abs(P.d0 or 0) > 0.3)
    bm.on = braking and aspeed > TUNE.BM_KMH and not swerve and not st.shake and math.abs(st.err or 0) < TUNE.BM_HEAD
    bm.v, bm.t = aspeed, now
end

local function finishTrip(reason)
    if not st or st.ending then return end
    st.ending = true
    COTW.send("finish", { reason = reason })
    release(COTW.driving())
    st = nil
end

-- returns the heading error (rad) so the speed control can slow down while the car is still turning.
-- bias = yaw rate (rad/s) asked on top (shaking a zombie off)
local function steer(v, tx, ty, speed, dt, bias)
    local fwd = v:getForwardVector(Vector3f.new())
    local fx, fz = fwd:x(), fwd:z()
    local fl = math.sqrt(fx * fx + fz * fz)
    if fl < 0.01 then return 0 end
    fx, fz = fx / fl, fz / fl
    local heading = math.atan2(fz, fx)
    local yaw = st.lastHead and wrap(heading - st.lastHead) / dt or 0
    st.lastHead = heading
    local err = wrap(math.atan2(ty - v:getY(), tx - v:getX()) - heading)
    if speed < 0 then err = -err end
    local vms = math.abs(speed) / 3.6
    if vms < 0.5 then st.yawInt = 0; return err end
    local prof = st.prof
    local dw   -- yaw-rate change (rad/s) asked this tick
    if not D.signLearnt then
        -- which way the push turns the car depends on the physics frame: the car rolls off straight,
        -- gets a short fixed push and we see which way the yaw rate goes (flip once if the other way).
        -- No other steering until then, so nothing else moves the yaw rate. Too small a change (grip,
        -- a bump) teaches nothing: wait a moment and push again.
        if vms < 1.5 or st.ticks < (st.probeWait or 0) or (not st.probe and math.abs(yaw) > 0.05) then return err end
        st.probe = st.probe or { n = 0, y0 = yaw }
        st.probe.n = st.probe.n + 1
        if st.probe.n <= TUNE.PROBE_TICKS then
            dw = TUNE.PROBE_STEP
        else
            local got = yaw - st.probe.y0
            st.probe = nil
            if math.abs(got) < TUNE.PROBE_MIN then
                st.probeTries = (st.probeTries or 0) + 1
                st.probeWait = st.ticks + TUNE.PROBE_WAIT
                if st.probeTries <= 3 then COTW.log("steering probe too weak (yaw " .. string.format("%.3f", got) .. "), again") end
                return err
            end
            D.signLearnt = true
            if got < 0 then D.steerSign = -D.steerSign end
            COTW.log("steering sign " .. D.steerSign .. " (probe yaw " .. string.format("%.3f", got) .. ")")
        end
    end
    if not dw then
        local maxYaw = math.min(1.2, TUNE.LAT_ACCEL / math.max(vms, 1))
        local want = math.max(-maxYaw, math.min(maxYaw, err * TUNE.HEAD_GAIN + (bias or 0)))
        -- PI on the yaw rate: the integral makes up for tyre grip that keeps pulling the turn back
        st.yawInt = math.max(-1, math.min(1, (st.yawInt or 0) + (want - yaw) * dt))
        dw = TUNE.STEER_GAIN * (prof.steer or 1) * ((want - yaw) + TUNE.YAW_I * st.yawInt)
        if vms < 3 then dw = dw * vms / 3 end
    end
    dw = math.max(-TUNE.DW_MAX, math.min(TUNE.DW_MAX, dw))
    -- yaw inertia of the car (box) plus a towed trailer hanging off the back
    local L, Wd = prof.l or 4, prof.w or 2
    local inertia = (prof.cmass or prof.mass or 1000) * (L * L + Wd * Wd) / 12 + (prof.tmass or 0) * L * L / 4
    local J = inertia * dw / dt / TUNE.LEVER * D.steerSign
    local rx, rz = -fz, fx
    pcall(function() v:addImpulse(Vector3f.new(rx * J, 0, rz * J), Vector3f.new(fx * TUNE.LEVER, 0, fz * TUNE.LEVER)) end)
    return err
end

local function tick()
    if not st then return end
    local v = COTW.driving()
    if not v then finishTrip("left"); return end
    local now = getTimestampMs()
    local dt = math.max(0.005, math.min(0.1, (now - (st.lastT or now)) / 1000))
    st.lastT = now
    st.ticks = st.ticks + 1

    local down = keys()
    if not down then st.armed = true end
    if down and st.armed then st.holdMs = st.holdMs + dt * 1000 else st.holdMs = 0 end
    if st.holdMs >= TUNE.HOLD_MS then finishTrip("intervene"); return end

    local R = st.R
    local pos, off, k, side = locate(R, v:getX(), v:getY(), st.idx)
    st.pos, st.off, st.idx, st.side = pos, off, k, side
    local rem = R.len - pos
    st.rem = rem
    local speed = v:getCurrentSpeedKmHour()
    local aspeed = math.abs(speed)
    local decel = st.prof.decel or 6
    local trailer = st.trailer

    if now - st.lastProg >= TUNE.PROG_MS then
        st.lastProg = now
        COTW.send("prog", { rem = math.floor(rem), spd = math.floor(aspeed) })
    end

    -- how fast may we go
    local target = COTW.speedCap(R.sw[k], trailer ~= nil)
    st.why = nil
    local bend, tight = cornerCap(R, pos, k, decel)
    target = math.min(target, bend)
    if rem <= TUNE.ARRIVE then target = 0
    else target = math.min(target, math.sqrt(2 * decel * (rem - TUNE.ARRIVE)) * 3.6 + 3) end
    if st.ticks % TUNE.SENSE_EVERY == 1 or not st.sense then
        st.sense = sense(v, trailer)
        st.plan = st.sense.plan
        -- back on the lane line and settled: no plan
        local done = st.plan and planEnd(st.plan)
        if done and pos > done then st.plan = nil end
    end
    if st.sense.limit < target then target = st.sense.limit; st.why = st.sense.why end

    -- a zombie stuck on the bumper and pushed along: brake hard; still there next time, a quick
    -- wiggle toward a side with room (brake again when neither has room)
    local sh = st.shake
    if sh and now - sh.t0 > (sh.mode == "brake" and TUNE.SHAKE_BRAKE_MS or TUNE.SHAKE_SWERVE_MS) then st.shake, sh = nil, nil end
    if not sh and (st.sense.pushed or 0) >= TUNE.SHAKE_PUSH and aspeed > 3 then
        if now - (st.shakeT or 0) > TUNE.SHAKE_RESET_MS then st.shakes = 0 end
        st.shakes = (st.shakes or 0) + 1
        local room = st.sense.room or {}
        local dir = room[1] and 1 or (room[-1] and -1 or nil)
        if room[1] and room[-1] and st.shakes % 4 == 0 then dir = -1 end
        sh = { mode = (st.shakes % 2 == 0 and dir) and "swerve" or "brake", t0 = now, dir = dir }
        st.shake, st.shakeT, st.pushed = sh, now, {}
        st.sense.pushed = 0
    end
    if sh and sh.mode == "brake" then target = 0; st.why = "zombie" end

    local C = COTW.C
    if C.trip and C.trip.gid and (C.trip.order or 1) > 1 then
        local lead = C.lead
        if lead and now - lead.t < TUNE.LEAD_STALE then
            local gap = rem - lead.rem - COTW.opt("GroupGap")
            local v2 = gap <= 0 and 0 or math.min(lead.spd + gap * 2, math.sqrt(2 * decel * gap) * 3.6 + lead.spd)
            if v2 < target then target = v2; st.why = "group" end
        elseif lead or now - st.t0 < 5000 then
            if 0 < target then target = 0; st.why = "group" end
        end
    end
    -- still pointing the wrong way (corner just passed, overshoot): slow down until lined up again
    local errCap = math.max(8, COTW.opt("MaxSpeed") * (1 - math.abs(st.err) / TUNE.ERR_SLOW))
    if errCap < target then target = errCap end
    if off > TUNE.OFFROUTE then target = 0; st.why = "offroute" end
    if st.emergency then target = 0; st.why = "emergency" end
    st.target = target

    -- speed (stopping for something in the way or slowing for a narrow bend: brake as soon as over,
    -- no coasting into it)
    local over = TUNE.BRAKE_OVER
    if (st.sense.stopFor and st.sense.stopFor <= target + 0.01) or (tight and bend <= target + 0.01) then over = TUNE.BRAKE_OVER_HIT end
    local braking = target < 1 or aspeed > target + over
    brakeMeasure(braking, aspeed, now)
    if braking then
        pcall(function() v:setRegulator(false); v:setForceBrake() end)
        if trailer then pcall(function() trailer:setForceBrake() end) end
    else
        -- the dashboard prints the cruise speed as is: whole km/h only
        local kmh = math.max(1, math.floor(target + 0.5))
        pcall(function() v:setRegulator(true); v:setRegulatorSpeed(kmh) end)
    end

    -- steering toward a point ahead on the plan (further at speed, further still with a trailer;
    -- closer while moving over so the car follows the S instead of cutting it)
    local P = st.plan
    local ahead = math.max(6, math.min(22, 5 + aspeed * 0.2))
    local shifting = P and ((math.abs(P.c - P.d0) > 0.5 and pos < P.s0 + P.T) or (P.back and pos > P.back - 4 and pos < P.back + P.T2))
    if shifting then ahead = math.max(4, math.min(12, 3 + aspeed * 0.2)) end
    ahead = ahead + (trailer and 4 or 0)
    -- a sharp bend into or out of a narrow road close ahead: aim at the bend itself, then round it
    -- close, so the car follows the road into a side street instead of cutting the corner
    local bd, bw = nextBend(R, pos, k, ahead)
    if bd then
        local close = math.max(TUNE.BEND_AHEAD, math.min(6, bw * 0.75)) + (trailer and 1 or 0)
        ahead = math.min(ahead, math.max(bd, close))
    end
    local tx, ty, tdx, tdy = pointAt(R, pos + ahead, k)
    local o = offsetAt(P, pos + ahead)
    local bias = nil
    if sh and sh.mode == "swerve" then bias = sh.dir * TUNE.SHAKE_YAW * (now - sh.t0 < TUNE.SHAKE_SWERVE_MS / 2 and 1 or -1) end
    st.err = steer(v, tx - tdy * o, ty + tdx * o, speed, dt, bias)

    -- how it ends
    if aspeed < 2 then
        if st.emergency then finishTrip("emergency"); return end
        if rem < TUNE.ARRIVE then finishTrip("arrive"); return end
        if off > TUNE.OFFROUTE then finishTrip("offroute"); return end
        if st.sense.blocked then
            st.blockedAt = st.blockedAt or now
            if now - st.blockedAt > COTW.opt("BlockedSeconds") * 1000 then finishTrip("blocked"); return end
        else
            st.blockedAt = nil
        end
    else
        st.blockedAt = nil
    end
    if aspeed < 1.5 and target > 3 then
        st.crawlAt = st.crawlAt or now
        if now - st.crawlAt > TUNE.STUCK_MS then finishTrip("stuck"); return end
    else
        st.crawlAt = nil
    end
end

function D.start(route)
    local v = COTW.driving()
    if not v or not route or not route.x or #route.x < 2 then
        COTW.send("finish", { reason = "left" })
        return
    end
    local prof = COTW.profileFor(v) or {}
    local trailer = nil
    pcall(function() trailer = v:getVehicleTowing() end)
    st = {
        R = prepare(route), prof = prof, trailer = trailer,
        idx = 1, pos = 0, rem = route.len, holdMs = 0, ticks = 0,
        lastProg = 0, t0 = getTimestampMs(), yawInt = 0, err = 0,
        tiles = {}, tileCount = 0, carTiles = {}, carTileCount = 0, cars = {}, scans = 0, pushed = {},
    }
    if trailer then
        local tp = COTW.profileFor(trailer)
        -- the pair brakes like the weaker of the two and is as long as both
        if tp then
            prof = { w = math.max(prof.w or 2, tp.w or 2), l = prof.l, mass = (prof.mass or 1000) + (tp.mass or 500),
                     cmass = prof.mass or 1000, tmass = tp.mass or 500, decel = math.min(prof.decel or 6, tp.decel or 6) * 0.8, steer = prof.steer, tl = tp.l }
            st.prof = prof
        end
    end
    pcall(function() v:setRegulator(true) end)
end

function D.stop()
    if st then release(COTW.driving()) end
    st = nil
end

function D.emergency()
    if st then st.emergency = true end
end

function D.running() return st ~= nil end

-- side position (tiles right of the lane line) the car aims for at route position pos
function D.sideAt(pos)
    return st and offsetAt(st.plan, pos) or 0
end

-- what the HUD shows
function D.status()
    if not st then return nil end
    return {
        target = st.target or 0, why = st.why, hold = st.holdMs / TUNE.HOLD_MS, rem = st.rem or 0,
        emergency = st.emergency, R = st.R, idx = st.idx, pos = st.pos, len = st.R.len,
    }
end

Events.OnTick.Add(function()
    local ok, err = pcall(tick)
    if not ok then
        COTW.log("autopilot error: " .. tostring(err))
        finishTrip("error")     -- by distance like blocked, but no trouble spot: the road did nothing
    end
end)
