-- Cookie On the Way : the autopilot (runs on the driver's client: vehicle physics live there)
-- Speed: the vehicle's own cruise control (regulator), force brake when slower is needed.
-- Steering: wheels cannot be turned from Lua, so the car is yawed with an equal and opposite side
-- impulse at its front and rear (a pure turning couple) under a yaw-rate controller that follows a
-- point a little way ahead on the route (kept right of the centre line on two-lane roads).
-- Safety: the road ahead (as long as the braking distance) is sampled square by square for walls,
-- cars, people and zombies. Obstacles brake the car; zombies only slow it (push through).
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
    ERR_SLOW    = 1.0,
    STOP_GAP    = 3,      -- tiles kept between the bumper and an obstacle
    BRAKE_OVER  = 3,      -- km/h over the target speed before the brakes come on (below: cruise control eases off)    -- rad of heading error at which the car is down to crawling speed
    HEAD_GAIN   = 2.0,    -- yaw rate (rad/s) asked per rad of heading error
    LAT_ACCEL   = 4.0,    -- m/s^2 allowed sideways (caps the yaw rate at speed)
    TURN_ACCEL  = 3.0,    -- m/s^2 used to pick a corner speed
    SENSE_EVERY = 4,      -- ticks between road scans
    STUCK_MS    = 10000,  -- crawling < 1.5 km/h this long with nothing blocking = stuck
    PROG_MS     = 500,
    LEAD_STALE  = 3000,
}
D.TUNE = TUNE

local st = nil
D.steerSign = D.steerSign or 1      -- learnt once per session, kept for later trips

-- ------------------------------------------------------------------------------
-- route geometry
-- ------------------------------------------------------------------------------
local function prepare(route)
    local n = #route.x
    local x, y, w = {}, {}, {}
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
    end
    local cum = { 0 }
    for i = 2, n do cum[i] = cum[i - 1] + COTW.dist(x[i - 1], y[i - 1], x[i], y[i]) end
    return { x = x, y = y, w = w, cum = cum, n = n, len = cum[n] }
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

-- project (px, py) on segments near idx: pos along route, distance off it, segment
local function locate(R, px, py, idx)
    local best, bpos, bk = nil, 0, idx
    for k = math.max(1, idx - 2), math.min(R.n - 1, idx + 20) do
        local x1, y1, x2, y2 = R.x[k], R.y[k], R.x[k + 1], R.y[k + 1]
        local vx, vy = x2 - x1, y2 - y1
        local L2 = vx * vx + vy * vy
        local t = 0
        if L2 > 0 then t = math.max(0, math.min(1, ((px - x1) * vx + (py - y1) * vy) / L2)) end
        local d = COTW.dist(px, py, x1 + vx * t, y1 + vy * t)
        if not best or d < best then
            best, bk = d, k
            bpos = R.cum[k] + t * math.sqrt(L2)
        end
    end
    return bpos, best or 0, bk
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
-- road scan
-- ------------------------------------------------------------------------------
local function call(o, fn, ...)
    if not o or not o[fn] then return nil end
    local ok, r = pcall(o[fn], o, ...)
    if ok then return r end
    return nil
end

local function sense(v, trailer)
    local R, prof = st.R, st.prof
    local speed = math.abs(v:getCurrentSpeedKmHour())
    local vms = speed / 3.6
    local decel = prof.decel or 6
    local half = (prof.l or 4) / 2
    local look = math.min(90, vms * vms / (2 * decel) + half + 10)
    local hw = (prof.w or 2) / 2 + 0.4
    local cell = getCell()
    local zombies, unloaded = 0, false
    local s = half + 0.5
    while s <= look do
        local px, py, dx, dy = pointAt(R, st.pos + s, st.idx)
        local o = -hw
        while o <= hw + 0.01 do
            local sx, sy = px - dy * o, py + dx * o
            local sq = cell:getGridSquare(math.floor(sx), math.floor(sy), 0)
            if not sq then
                unloaded = true
            else
                local hard = call(sq, "isSolid") or call(sq, "isSolidTrans") or call(sq, "HasTree")
                local car = call(sq, "getVehicleContainer")
                if car and car ~= v and car ~= trailer then hard = true end
                local movers = call(sq, "getMovingObjects")
                if movers then
                    for i = 0, movers:size() - 1 do
                        local m = movers:get(i)
                        if instanceof(m, "IsoZombie") then
                            if not call(m, "isDead") then zombies = zombies + 1 end
                        elseif instanceof(m, "IsoPlayer") and m ~= getSpecificPlayer(0) and not call(m, "getVehicle") then
                            hard = true
                        end
                    end
                end
                if hard then
                    local room = math.max(0, s - half - TUNE.STOP_GAP)
                    return { limit = math.sqrt(2 * decel * room) * 3.6, why = "obstacle", blocked = room < 3 }
                end
            end
            o = o + math.max(0.7, hw / 2)
        end
        s = s + 1
    end
    if zombies > 0 then return { limit = COTW.opt("ZombieSpeed"), why = "zombie", zombies = zombies } end
    if unloaded then return { limit = 25, why = "unloaded" } end
    return { limit = 999 }
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
    local L, Wd, mass = prof.l or 4, prof.w or 2, prof.mass or 1000
    local arm = L / 2
    local inertia = mass * (L * L + Wd * Wd) / 12
    local unit = inertia / (2 * arm)            -- couple impulse that changes the yaw rate by 1 rad/s
    local J
    if not D.signLearnt then
        -- which way a couple turns the car depends on the physics frame: on the first trip the car rolls
        -- off straight, gets a short fixed push and we see which way the yaw rate goes (flip once if the
        -- other way). No other steering until then, so nothing else moves the yaw rate.
        if vms < 1.5 or (not st.probe and math.abs(yaw) > 0.05) then return err end
        st.probe = st.probe or { n = 0, y0 = yaw }
        st.probe.n = st.probe.n + 1
        if st.probe.n <= TUNE.PROBE_TICKS then
            J = TUNE.PROBE_STEP * unit
        else
            D.signLearnt = true
            if yaw - st.probe.y0 < 0 then D.steerSign = -D.steerSign end
            COTW.log("steering sign " .. D.steerSign .. " (probe yaw " .. string.format("%.3f", yaw - st.probe.y0) .. ")")
        end
    end
    if not J then
        local maxYaw = math.min(1.2, TUNE.LAT_ACCEL / math.max(vms, 1))
        local want = math.max(-maxYaw, math.min(maxYaw, err * TUNE.HEAD_GAIN))
        -- PI on the yaw rate: the integral makes up for tyre grip that keeps pulling the turn back
        st.yawInt = math.max(-1, math.min(1, (st.yawInt or 0) + (want - yaw) * dt))
        J = TUNE.STEER_GAIN * (prof.steer or 1) * ((want - yaw) + TUNE.YAW_I * st.yawInt) * unit
        if vms < 3 then J = J * vms / 3 end
    end
    J = J * D.steerSign
    local rx, rz = -fz, fx
    pcall(function()
        v:addImpulse(Vector3f.new(rx * J, 0, rz * J), Vector3f.new(fx * arm, 0, fz * arm))
        v:addImpulse(Vector3f.new(-rx * J, 0, -rz * J), Vector3f.new(-fx * arm, 0, -fz * arm))
    end)
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
    local pos, off, k = locate(R, v:getX(), v:getY(), st.idx)
    st.pos, st.off, st.idx = pos, off, k
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
    if st.ticks % TUNE.SENSE_EVERY == 1 or not st.sense then st.sense = sense(v, trailer) end
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
        pcall(function() v:setRegulator(true); v:setRegulatorSpeed(target) end)
    end

    -- steering toward a point ahead (further at speed, further still with a trailer)
    local ahead = math.max(6, math.min(22, 5 + aspeed * 0.2)) + (trailer and 4 or 0)
    local tx, ty = pointAt(R, pos + ahead, k)
    st.err = steer(v, tx, ty, speed, dt)

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
    }
    if trailer then
        local tp = COTW.profileFor(trailer)
        -- the pair brakes like the weaker of the two and is as long as both
        if tp then
            prof = { w = math.max(prof.w or 2, tp.w or 2), l = prof.l, mass = (prof.mass or 1000) + (tp.mass or 500),
                     decel = math.min(prof.decel or 6, tp.decel or 6) * 0.8, steer = prof.steer, tl = tp.l }
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

-- what the HUD shows
function D.status()
    if not st then return nil end
    return {
        target = st.target or 0, why = st.why, hold = st.holdMs / TUNE.HOLD_MS, rem = st.rem or 0,
        emergency = st.emergency, R = st.R, idx = st.idx,
    }
end

Events.OnTick.Add(function()
    local ok, err = pcall(tick)
    if not ok then
        COTW.log("autopilot error: " .. tostring(err))
        finishTrip("blocked")
    end
end)
