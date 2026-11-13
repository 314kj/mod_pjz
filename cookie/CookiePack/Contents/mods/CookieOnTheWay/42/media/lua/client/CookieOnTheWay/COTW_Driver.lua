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
-- circle. Getting past: side positions off the lane line are tried (cheapest = closest to the lane);
-- the first one whose path is clear becomes the plan and the car eases over to it, slowing first when
-- the gap needs a short swerve. Nothing clear: stop before it. Moving cars are followed, not passed;
-- zombies only slow the car (push through).
-- Holding a drive key for 1 s hands the car back (counts as arrived); the HUD "stop here" button stops
-- and charges by distance + EmergencyFeePct.

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
    STOP_GAP    = 1.5,    -- tiles kept between the bumper and something the car stops for
    BRAKE_OVER  = 3,      -- km/h over the target speed before the brakes come on (below: cruise control eases off)
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
    AVOID_MAX   = 6,      -- tiles the car may leave its lane line by to get past something
    ROAD_EDGE   = 1.5,    -- tiles past the road edge the car centre may go
    SIDE_STEP   = 0.5,    -- tiles between the side positions tried
    SIDE_ACCEL  = 2.5,    -- m/s^2 sideways while moving over
    SWERVE_KMH  = { 12, 5 },  -- slower (shorter) swerves tried when the gap is too close at speed
    AVOID_KMH   = 30,     -- top speed while off the lane line
    MOVING_KMH  = 3,      -- cars faster than this are followed, not driven round
    CAR_TTL     = 3000,   -- ms a "which car is on this tile" answer is kept (found cars are re-read every scan)
}
D.TUNE = TUNE

local st = nil
D.steerSign = D.steerSign or 1      -- learnt once per session, kept for later trips

-- ------------------------------------------------------------------------------
-- route geometry
-- ------------------------------------------------------------------------------
local function prepare(route)
    local n = #route.x
    local x, y, w, lane = {}, {}, {}, {}
    for i = 1, n do
        local a = math.max(1, i - 1)
        local b = math.min(n, i + 1)
        local dx, dy = route.x[b] - route.x[a], route.y[b] - route.y[a]
        local L = math.sqrt(dx * dx + dy * dy)
        local width = route.w[math.min(i, n - 1)] or 8
        local off = width >= 6 and math.min(TUNE.LANE_MAX, width / 4) or 0
        if i == n then off = 0 end
        if L > 0 then
            -- right of the travel direction (world y grows south)
            x[i] = route.x[i] - dy / L * off
            y[i] = route.y[i] + dx / L * off
        else
            x[i], y[i] = route.x[i], route.y[i]
        end
        w[i] = width
        lane[i] = off
    end
    local cum = { 0 }
    for i = 2, n do cum[i] = cum[i - 1] + COTW.dist(x[i - 1], y[i - 1], x[i], y[i]) end
    return { x = x, y = y, w = w, lane = lane, cum = cum, n = n, len = cum[n] }
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

-- slowest corner speed (km/h) we must be able to reach within the next stretch of road
local function cornerCap(R, pos, idx, decel)
    local cap = 999
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
                local vt = math.sqrt(TUNE.TURN_ACCEL * math.max(r, 2))
                local dist = math.max(0, R.cum[k] - pos - 2)
                local v = math.sqrt(vt * vt + 2 * decel * dist) * 3.6
                if v < cap then cap = v end
            end
        end
        k = k + 1
    end
    return cap
end

-- ------------------------------------------------------------------------------
-- plan: where across the road the car drives (tiles right of the lane line)
-- { s0 = route pos it was made at, d0 = side then, c = side to reach, T = tiles used to get there,
--   v = speed (m/s) T was sized for }; nil = on the lane line
-- ------------------------------------------------------------------------------
local function smooth(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return t * t * (3 - 2 * t)
end

local function offsetAt(P, pos)
    if not P then return 0 end
    return P.d0 + (P.c - P.d0) * smooth((pos - P.s0) / P.T)
end

-- tiles of road an S-shaped move of `delta` tiles takes at vms (sideways pull capped at SIDE_ACCEL)
local function moveLen(delta, vms)
    local a = math.abs(delta)
    if a < 0.3 then return 2 end
    return math.max(3 + a, vms * math.sqrt(2 * math.pi * a / TUNE.SIDE_ACCEL))
end

-- ------------------------------------------------------------------------------
-- road scan
-- ------------------------------------------------------------------------------
local NONE = {}

-- what stands on a tile, kept for the trip: s = solid (whole tile), n / w = wall or fence on the
-- north / west edge. nil = not loaded (not kept)
local function tileInfo(cell, x, y)
    local key = x * 100000 + y
    local t = st.tiles[key]
    if t ~= nil then return t end
    local sq = cell:getGridSquare(x, y, 0)
    if not sq then return nil end
    local ok, s, n, w = pcall(function()
        return sq:isSolid() or sq:isSolidTrans() or sq:HasTree(), sq:has(IsoFlagType.collideN), sq:has(IsoFlagType.collideW)
    end)
    if ok and (s or n or w) then t = { s = s, n = n, w = w } else t = NONE end
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
local function hitAt(sc, wx, wy, moving, boxes, tn, tw)
    local tx, ty = math.floor(wx), math.floor(wy)
    local fx, fy = wx - tx, wy - ty
    local t = tileInfo(sc.cell, tx, ty)
    if t == nil then
        sc.unloaded = true
    elseif t ~= NONE then
        if t.s and fx > 0.1 and fx < 0.9 and fy > 0.1 and fy < 0.9 then return true end
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
        v = hitAt(sc, row.x - row.dy * d, row.y + row.dx * d, moving, rowBoxes(sc, i), tn, tw)
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
        if r < half then skipLo, skipHi = sc.d - hw - cell, sc.d + hw + cell end
        -- one point past each edge so nothing slips in between the points and the body; just past
        -- the bumper only points on the body itself (every plan still starts where the car is)
        local j1, j2 = math.floor(lo / cell), math.ceil(hi / cell)
        if near then j1, j2 = math.ceil(lo / cell), math.floor(hi / cell) end
        for j = j1, j2 do
            local dj = j * cell
            if dj < skipLo or dj > skipHi then
                local what = occ(sc, i, j, moving)
                if what then return r, i, what end
            end
        end
    end
    return nil
end

local function makePlan(sc, c, vms)
    return { s0 = st.pos, d0 = sc.d, c = c, T = moveLen(c - sc.d, vms), v = vms }
end

-- pick where to drive: { plan, hit } (hit = s the plan runs into, nil when clear), plus `slow`:
-- a plan that only works after slowing to slow.v
local function choose(sc, vms)
    local P = st.plan or makePlan(sc, 0, vms)
    local k = st.idx
    local lim = (st.R.w[k] or 8) / 2 + TUNE.ROAD_EDGE
    local lane = st.R.lane[k] or 0
    local lo = math.max(-TUNE.AVOID_MAX, -lim - lane)
    local hi = math.min(TUNE.AVOID_MAX, lim - lane)
    -- cost: off the lane line, away from the current plan, and the body hanging off the road
    local roadHalf = (st.R.w[k] or 8) / 2
    local body = (st.prof.w or 2) / 2
    local list = {}
    local function add(c)
        local over = math.max(0, math.abs(c + lane) + body - roadHalf)
        list[#list + 1] = { c = c, cost = math.abs(c) + 0.6 * math.abs(c - P.c) + over }
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
    local curHit = firstHit(sc, P)
    local pCost = math.abs(P.c)
    local best, bestHit = P, curHit
    -- something beside the car counts as worse than anything ahead (braking does not help there)
    local function score(h) return h < sc.half and h - 100 or h end
    for _, e in ipairs(list) do
        if not curHit and e.cost >= pCost then return { plan = P } end
        if math.abs(e.c - P.c) >= 0.01 then
            local Q = makePlan(sc, e.c, vms)
            local h = firstHit(sc, Q)
            if not h then return { plan = Q } end
            -- nothing clear: the side position that gets clearly furthest
            if curHit and score(h) > score(bestHit) + 2 then best, bestHit = Q, h end
        end
    end
    if not curHit then return { plan = P } end
    -- too close for a swerve at this speed: one after slowing down?
    for _, kmh in ipairs(TUNE.SWERVE_KMH) do
        local vs = kmh / 3.6
        if vs < vms - 0.3 then
            for _, e in ipairs(list) do
                if math.abs(e.c - P.c) >= 0.01 then
                    local Q = makePlan(sc, e.c, vs)
                    if not firstHit(sc, Q) then return { plan = P, hit = curHit, slow = Q } end
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

local function sense(v, trailer)
    local R, prof = st.R, st.prof
    local vms = math.abs(v:getCurrentSpeedKmHour()) / 3.6
    local decel = prof.decel or 6
    local half = (prof.l or 4) / 2
    local look = math.min(TUNE.SCAN_MAX, vms * vms / (2 * decel) + half + 12)
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
        sc.rows[n] = { s = s, x = x, y = y, dx = dx, dy = dy }
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
        cap(math.sqrt(2 * decel * room) * 3.6, "obstacle")
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
        cap(math.sqrt(lead * lead + 2 * decel * room) * 3.6, "obstacle")
    end
    -- planned off the lane line, or still moving over
    if math.abs(P.c) > 1 then cap(TUNE.AVOID_KMH, "avoid") end
    if math.abs(P.c - P.d0) > 0.5 and st.pos < P.s0 + P.T then cap(math.max(TUNE.SWERVE_KMH[1], P.v * 3.6 + 3), "avoid") end
    local zombies = countZombies(sc, P)
    if zombies > 0 then cap(COTW.opt("ZombieSpeed"), "zombie"); res.zombies = zombies end
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

local function finishTrip(reason)
    if not st or st.ending then return end
    st.ending = true
    COTW.send("finish", { reason = reason })
    release(COTW.driving())
    st = nil
end

-- returns the heading error (rad) so the speed control can slow down while the car is still turning
local function steer(v, tx, ty, speed, dt)
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
        local want = math.max(-maxYaw, math.min(maxYaw, err * TUNE.HEAD_GAIN))
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
    local target = COTW.speedCap(R.w[k], trailer ~= nil)
    st.why = nil
    target = math.min(target, cornerCap(R, pos, k, decel))
    if rem <= TUNE.ARRIVE then target = 0
    else target = math.min(target, math.sqrt(2 * decel * (rem - TUNE.ARRIVE)) * 3.6 + 3) end
    if st.ticks % TUNE.SENSE_EVERY == 1 or not st.sense then
        st.sense = sense(v, trailer)
        st.plan = st.sense.plan
        -- back on the lane line and settled: no plan
        if st.plan and st.plan.c == 0 and pos > st.plan.s0 + st.plan.T then st.plan = nil end
    end
    if st.sense.limit < target then target = st.sense.limit; st.why = st.sense.why end

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

    -- speed
    if target < 1 or aspeed > target + TUNE.BRAKE_OVER then
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
    if P and math.abs(P.c - P.d0) > 0.5 and pos < P.s0 + P.T then ahead = math.max(4, math.min(12, 3 + aspeed * 0.2)) end
    ahead = ahead + (trailer and 4 or 0)
    local tx, ty, tdx, tdy = pointAt(R, pos + ahead, k)
    local o = offsetAt(P, pos + ahead)
    st.err = steer(v, tx - tdy * o, ty + tdx * o, speed, dt)

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
        tiles = {}, tileCount = 0, carTiles = {}, carTileCount = 0, cars = {}, scans = 0,
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
        finishTrip("blocked")
    end
end)
