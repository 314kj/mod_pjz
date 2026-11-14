-- Cookie On the Way : trouble spots (shared maths; the server keeps the list, the graph routes round it)
-- A trip that ends blocked, stuck or off its route leaves a hit on the route where the car gave up.
-- Hits fade by half every ClosedHalfLifeHours of real time. A spot whose hits add up to ON, from two
-- trips or more, is closed: routes go round it when the other way is less than COST tiles longer, and
-- still go through when there is none (booking is never refused for it). A trip that gets past a spot
-- clears it, so a road that opens again comes back on its own; a spot no trip reaches fades away.

require "CookieOnTheWay/COTW_Const"

COTW.Closed = COTW.Closed or {}
local K = COTW.Closed

K.NEAR       = 6          -- tiles from the route: a spot counts as on it
K.OFF_NEAR   = 25         -- an off-route end is put back on the route when the car is this close to it
K.MIN_DRIVEN = 20         -- tiles a trip must have driven before it may leave a hit (not stuck leaving home)
K.MERGE      = 8          -- a hit this close to a spot adds to it
K.MAX        = 200        -- spots kept at most (the lightest goes first)
K.HITS       = 8          -- hits kept per spot
K.HIT_GAP_MS = 300000     -- one hit per player per spot this often
K.ON         = 1.5        -- weight of a closed spot (two hits within a half-life)
K.DROP       = 0.3        -- weight under which a spot is forgotten
K.COST       = 3000       -- route cost (tiles of road) of going through a closed spot
K.PASS_R     = 5          -- tiles: the car came this close to the spot ...
K.PASS_ON    = 15         -- ... and then reached the route this far past it = the spot is clear

local LN2 = math.log(2)

function K.halfLifeMs() return math.max(1, COTW.opt("ClosedHalfLifeHours")) * 3600000 end

function K.weight(spot, now)
    local hl, w = K.halfLifeMs(), 0
    for _, h in ipairs(spot.hits or {}) do w = w + math.exp(-LN2 * math.max(0, now - h.t) / hl) end
    return w
end

function K.isClosed(spot, now) return #(spot.hits or {}) >= 2 and K.weight(spot, now) >= K.ON end

-- a number for a player name (the list never keeps names)
function K.hash(name)
    local h = 5381
    name = tostring(name or "")
    for i = 1, #name do h = (h * 33 + string.byte(name, i)) % 2147483647 end
    return h
end

-- distance from (px, py) to a route { x = {}, y = {} } and the road position of the closest point
function K.toRoute(r, px, py)
    local best, bpos, cum = nil, 0, 0
    for k = 1, #r.x - 1 do
        local x1, y1, x2, y2 = r.x[k], r.y[k], r.x[k + 1], r.y[k + 1]
        local vx, vy = x2 - x1, y2 - y1
        local L2 = vx * vx + vy * vy
        local seg = math.sqrt(L2)
        local t = 0
        if L2 > 0 then
            t = ((px - x1) * vx + (py - y1) * vy) / L2
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
        end
        local d = COTW.dist(px, py, x1 + vx * t, y1 + vy * t)
        if not best or d < best then best, bpos = d, cum + seg * t end
        cum = cum + seg
    end
    return best or math.huge, bpos
end

-- the route point at road position pos (clamped to the ends)
function K.pointAt(r, pos)
    local cum = 0
    for k = 1, #r.x - 1 do
        local seg = COTW.dist(r.x[k], r.y[k], r.x[k + 1], r.y[k + 1])
        if pos <= cum + seg then
            local t = seg > 0 and math.max(0, pos - cum) / seg or 0
            return r.x[k] + (r.x[k + 1] - r.x[k]) * t, r.y[k] + (r.y[k + 1] - r.y[k]) * t
        end
        cum = cum + seg
    end
    return r.x[#r.x], r.y[#r.y]
end

-- where a trip that ended for `reason` at (x, y) after `driven` tiles leaves its hit: x, y on the route, or nil
function K.hitPoint(r, reason, x, y, driven)
    if reason ~= "blocked" and reason ~= "stuck" and reason ~= "offroute" then return nil end
    if not x or (driven or 0) <= K.MIN_DRIVEN or not r or not r.x or #r.x < 2 then return nil end
    local d, pos = K.toRoute(r, x, y)
    if d > (reason == "offroute" and K.OFF_NEAR or K.NEAR) then return nil end
    return K.pointAt(r, pos)
end

local function remove(list, spot)
    for i = #list, 1, -1 do
        if list[i] == spot then table.remove(list, i); return true end
    end
    return false
end

-- one hit at (x, y) by player hash `who`. Returns the spot (nil when the same player hit it a moment ago)
function K.record(list, x, y, who, now)
    local spot, bd = nil, K.MERGE
    for _, s in ipairs(list) do
        local d = COTW.dist(s.x, s.y, x, y)
        if d < bd then spot, bd = s, d end
    end
    if spot then
        for _, h in ipairs(spot.hits) do
            if h.who == who and now - h.t < K.HIT_GAP_MS then return nil end
        end
        -- the spot moves toward where cars really give up
        local n = #spot.hits
        spot.x = math.floor((spot.x * n + x) / (n + 1) + 0.5)
        spot.y = math.floor((spot.y * n + y) / (n + 1) + 0.5)
    else
        if #list >= K.MAX then
            local lw, li = nil, nil
            for i, s in ipairs(list) do
                local w = K.weight(s, now)
                if not lw or w < lw then lw, li = w, i end
            end
            table.remove(list, li)
        end
        spot = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), hits = {} }
        list[#list + 1] = spot
    end
    spot.hits[#spot.hits + 1] = { t = now, who = who }
    while #spot.hits > K.HITS do table.remove(spot.hits, 1) end
    return spot
end

-- a trip got past this spot: forget it
function K.clear(list, spot) return remove(list, spot) end

-- fade: forget light spots and flag which are closed now. Returns true when the closed set changed.
function K.refresh(list, now)
    local changed = false
    for i = #list, 1, -1 do
        local s = list[i]
        local on = K.isClosed(s, now)
        if K.weight(s, now) < K.DROP then
            table.remove(list, i)
            if s.on then changed = true end
        else
            if (s.on == true) ~= on then changed = true end
            s.on = on
        end
    end
    return changed
end

-- what clients get: { { x, y, w = weight, on = closed, t = last hit } }
function K.export(list, now)
    local out = {}
    for i, s in ipairs(list) do
        local last = s.hits[#s.hits]
        out[i] = { x = s.x, y = s.y, w = math.floor(K.weight(s, now) * 10 + 0.5) / 10, on = s.on == true, t = last and last.t or 0 }
    end
    return out
end

-- spots near a route, each with the route point PASS_ON past it: what a trip watches while it drives
function K.watch(list, r)
    local out = {}
    for _, s in ipairs(list) do
        local d, pos = K.toRoute(r, s.x, s.y)
        if d <= K.NEAR then
            local px, py = K.pointAt(r, pos + K.PASS_ON)
            out[#out + 1] = { spot = s, px = px, py = py }
        end
    end
    return out
end

-- distance from (px, py) to the segment (x1, y1) - (x2, y2)
local function segDist(px, py, x1, y1, x2, y2)
    local vx, vy = x2 - x1, y2 - y1
    local L2 = vx * vx + vy * vy
    local t = 0
    if L2 > 0 then
        t = ((px - x1) * vx + (py - y1) * vy) / L2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    return COTW.dist(px, py, x1 + vx * t, y1 + vy * t)
end

-- the car moved (x1, y1) -> (x2, y2): returns the watched spots it has now got past (removed from watch)
function K.passed(watch, x1, y1, x2, y2)
    local out = {}
    for i = #watch, 1, -1 do
        local w = watch[i]
        if not w.seen and segDist(w.spot.x, w.spot.y, x1, y1, x2, y2) < K.PASS_R then w.seen = true end
        if w.seen and segDist(w.px, w.py, x1, y1, x2, y2) < K.NEAR then
            out[#out + 1] = w.spot
            table.remove(watch, i)
        end
    end
    return out
end
