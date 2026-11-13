-- Cookie On the Way : the route drawn on the ground (green dots on the road ahead)
-- Autopilot: the lane line the car follows. Navigator: the route from where you are.
-- Vanilla grid-square markers (flat on the floor, under cars and walls), a small pool moved along as
-- you go; all removed when there is no route.

require "CookieOnTheWay/COTW_Driver"

COTW.Ground = COTW.Ground or {}
local GR = COTW.Ground

local AHEAD = 60       -- tiles of road shown
local START = 4        -- first dot this far ahead (not under the car)
local STEP = 3         -- tiles between dots
local SIZE = 0.35
local EVERY = 10       -- ticks between moves
local COL = { 0.20, 0.85, 0.40 }

local pool = {}
local ticks = 0

-- dots along xs/ys from the point of segment k nearest to (px, py)
local function sample(xs, ys, k, px, py)
    local out = {}
    local n = #xs
    if n < 2 then return out end
    k = math.max(1, math.min(k or 1, n - 1))
    local x1, y1 = xs[k], ys[k]
    local vx, vy = xs[k + 1] - x1, ys[k + 1] - y1
    local L2 = vx * vx + vy * vy
    local t = L2 > 0 and math.max(0, math.min(1, ((px - x1) * vx + (py - y1) * vy) / L2)) or 0
    local cx, cy = x1 + vx * t, y1 + vy * t
    local left, total, i = START, 0, k + 1
    while total < AHEAD and i <= n do
        local d = COTW.dist(cx, cy, xs[i], ys[i])
        if d >= left and d > 0 then
            local f = left / d
            cx, cy = cx + (xs[i] - cx) * f, cy + (ys[i] - cy) * f
            total = total + left
            out[#out + 1] = cx
            out[#out + 1] = cy
            left = STEP
        else
            left = left - d
            total = total + d
            cx, cy = xs[i], ys[i]
            i = i + 1
        end
    end
    return out
end

local function clear()
    for i = #pool, 1, -1 do
        pcall(function() pool[i]:remove() end)
        pool[i] = nil
    end
end
GR.clear = clear

local function place(pts)
    local n = #pts / 2
    local cell = getCell()
    for i = 1, n do
        local x, y = math.floor(pts[i * 2 - 1]), math.floor(pts[i * 2])
        local m = pool[i]
        if m then
            m:setPos(x, y, 0)
            m:setActive(true)
        else
            local sq = cell and cell:getGridSquare(x, y, 0)
            if not sq then break end      -- not loaded yet: the rest comes on a later move
            m = getWorldMarkers():addGridSquareMarker(sq, COL[1], COL[2], COL[3], false, SIZE)
            m:setScaleCircleTexture(true)
            pool[i] = m
        end
    end
    for i = n + 1, #pool do pool[i]:setActive(false) end
end

local function update()
    local p = COTW.player()
    if not p then return end
    local st = COTW.Driver.status()
    if st and st.R then
        place(sample(st.R.x, st.R.y, st.idx, p:getX(), p:getY()))
        return
    end
    local nav = COTW.C.nav
    if nav and nav.route then
        place(sample(nav.route.x, nav.route.y, COTW.C.navIdx, p:getX(), p:getY()))
        return
    end
    if #pool > 0 then clear() end
end

Events.OnTick.Add(function()
    ticks = ticks + 1
    if ticks % EVERY ~= 0 then return end
    local ok, err = pcall(update)
    if not ok and not GR.errLogged then
        GR.errLogged = true
        COTW.log("ground route error (logged once): " .. tostring(err))
        clear()
    end
end)
