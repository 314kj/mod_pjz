-- Cookie On the Way : the route drawn on the ground (green chevrons on the road ahead)
-- Autopilot: the path the car will really drive (its lane line plus any move round something in the
-- way). Navigator: the route from where you are. Each mark is three dots in a ">" pointing the way,
-- set at fixed spots along the route so they stay put as you drive; a brighter wave runs along them
-- toward the pin. Vanilla grid-square markers (flat on the floor, under cars and walls, whole tiles
-- only, always fading between their min and max alpha: both set to the brightness wanted). A small
-- pool is moved along as you go; all removed when there is no route.

require "CookieOnTheWay/COTW_Driver"

COTW.Ground = COTW.Ground or {}
local GR = COTW.Ground

local AHEAD = 60       -- tiles of road shown
local START = 4        -- first mark at least this far ahead (not under the car)
local STEP = 5         -- tiles between marks
local TIP, WING = 0.42, 0.3   -- dot sizes
local EVERY = 10       -- ticks between moves
local GLOW_EVERY = 3   -- ticks between brightness updates
local WAVE_MS = 260    -- ms for the bright wave to move one mark on
local WAVE_LEN = 8     -- marks between two waves
local COL = { 0.18, 0.89, 0.48 }

-- the 8 directions a chevron can point: tip one tile ahead, wings one tile back and one to each side
local SHAPES = {}
for o = 0, 7 do
    local a = o * math.pi / 4
    local ix, iy = math.floor(math.cos(a) + 0.5), math.floor(math.sin(a) + 0.5)
    SHAPES[o] = { { ix, iy, TIP }, { -ix - iy, -iy + ix, WING }, { -ix + iy, -iy - ix, WING } }
end

local pool = {}       -- markers
local marks = {}      -- per pool entry: absolute mark number (for the wave)
local ticks = 0

local function cumOf(t, xs, ys)
    if t.cum then return t.cum end
    local cum = { 0 }
    for i = 2, #xs do cum[i] = cum[i - 1] + COTW.dist(xs[i - 1], ys[i - 1], xs[i], ys[i]) end
    t.cum = cum
    return cum
end

-- route position of the point of xs/ys nearest (px, py), searching around segment k
local function project(xs, ys, cum, k, px, py)
    local best, bpos = nil, 0
    for i = math.max(1, (k or 1) - 2), math.min(#xs - 1, (k or 1) + 25) do
        local x1, y1 = xs[i], ys[i]
        local vx, vy = xs[i + 1] - x1, ys[i + 1] - y1
        local L2 = vx * vx + vy * vy
        local t = L2 > 0 and math.max(0, math.min(1, ((px - x1) * vx + (py - y1) * vy) / L2)) or 0
        local d = COTW.dist(px, py, x1 + vx * t, y1 + vy * t)
        if not best or d < best then best, bpos = d, cum[i] + t * math.sqrt(L2) end
    end
    return bpos
end

-- marks every STEP tiles of route position (fixed in the world), from pos + START to pos + AHEAD;
-- side(s) = tiles to the right of the line at route position s
local function sample(xs, ys, cum, pos, side)
    local out = {}
    local n = #xs
    if n < 2 then return out end
    local m = math.ceil((pos + START) / STEP)
    local k = 1
    while m * STEP <= math.min(pos + AHEAD, cum[n]) do
        local s = m * STEP
        while k < n - 1 and cum[k + 1] < s do k = k + 1 end
        local seg = cum[k + 1] - cum[k]
        local t = seg > 0 and (s - cum[k]) / seg or 0
        local dx, dy = xs[k + 1] - xs[k], ys[k + 1] - ys[k]
        local L = math.sqrt(dx * dx + dy * dy)
        if L > 0 then
            dx, dy = dx / L, dy / L
            local o = side and side(s) or 0
            -- +8 first: Kahlua's % truncates toward zero (-2 % 8 = -2), so keep the left side positive
            out[#out + 1] = {
                x = xs[k] + (xs[k + 1] - xs[k]) * t - dy * o, y = ys[k] + (ys[k + 1] - ys[k]) * t + dx * o,
                dir = (math.floor(math.atan2(dy, dx) / (math.pi / 4) + 0.5) + 8) % 8, m = m,
            }
        end
        m = m + 1
    end
    return out
end

local function clear()
    for i = #pool, 1, -1 do
        pcall(function() pool[i]:remove() end)
        pool[i] = nil
        marks[i] = nil
    end
end
GR.clear = clear

local function place(list)
    local cell = getCell()
    local i = 0
    for _, mk in ipairs(list) do
        local bx, by = math.floor(mk.x), math.floor(mk.y)
        for _, d in ipairs(SHAPES[mk.dir]) do
            local x, y = bx + d[1], by + d[2]
            local m = pool[i + 1]
            if m then
                m:setPos(x, y, 0)
                m:setSize(d[3])
                m:setActive(true)
            else
                local sq = cell and cell:getGridSquare(x, y, 0)
                if not sq then break end     -- not loaded yet: the rest comes on a later move
                m = getWorldMarkers():addGridSquareMarker(sq, COL[1], COL[2], COL[3], false, d[3])
                m:setScaleCircleTexture(true)
                pool[i + 1] = m
            end
            i = i + 1
            marks[i] = mk.m
        end
    end
    for j = i + 1, #pool do
        pool[j]:setActive(false)
        marks[j] = nil
    end
end

-- brightness: a wave runs from the car toward the pin
local function glow()
    local head = getTimestampMs() / WAVE_MS
    for i = 1, #pool do
        local m = marks[i]
        if m then
            local f = (head - m) % WAVE_LEN
            local lit = f < 2 and (1 - math.abs(f - 1)) or 0
            local a = 0.4 + 0.6 * lit
            local mk = pool[i]
            mk:setAlphaMin(a)
            mk:setAlphaMax(a)
            mk:setAlpha(a)
        end
    end
end

local function update()
    local p = COTW.player()
    if not p then return end
    local st = COTW.Driver.status()
    if st and st.R then
        local R = st.R
        place(sample(R.x, R.y, R.cum, st.pos, COTW.Driver.sideAt))
        return
    end
    local nav = COTW.C.nav
    if nav and nav.route then
        local r = nav.route
        local cum = cumOf(nav, r.x, r.y)
        place(sample(r.x, r.y, cum, project(r.x, r.y, cum, COTW.C.navIdx, p:getX(), p:getY())))
        return
    end
    if #pool > 0 then clear() end
end

Events.OnTick.Add(function()
    ticks = ticks + 1
    local ok, err = true, nil
    if ticks % EVERY == 0 then
        ok, err = pcall(update)
    elseif ticks % GLOW_EVERY == 0 and #pool > 0 then
        ok, err = pcall(glow)
    end
    if not ok and not GR.errLogged then
        GR.errLogged = true
        COTW.log("ground route error (logged once): " .. tostring(err))
        clear()
    end
end)
