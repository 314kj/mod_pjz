-- Cookie On the Way : road graph + route search (shared: the server prices with it, clients draw with it)
-- Base roads come from COTW_RoadData (built from the server's map folders by cotw_build_roads.py).
-- Admin roads (recorded by driving them, kept in global ModData) are added on top: each end snaps onto
-- the nearest road within SNAP_END tiles, splitting that road there, so map mods whose road data does
-- not reach the main network can be linked in game.
-- Closed trouble spots (COTW_Closed, sent by the server) add a cost to the road they sit on, so a
-- route goes round them when it can.

require "CookieOnTheWay/COTW_Const"
require "CookieOnTheWay/COTW_Closed"

COTW.Graph = COTW.Graph or {}
local G = COTW.Graph

local CELL = 50
local SNAP_END = 25
local PART_GAP = 25          -- pin further than this from a cut-off start piece: route on the main network
local PART_BIG = 500         -- tiles of road: a cut-off part this big is a town, not a parking lot
local NARROW_COST = 1.15     -- prefer wide roads a little when two routes are close

local base = { nx = {}, ny = {}, edges = {} }
COTW.RoadData = {
    N = function(x, y)
        local n = #base.nx + 1
        base.nx[n] = x
        base.ny[n] = y
    end,
    E = function(a, b, w, p)
        base.edges[#base.edges + 1] = { a = a, b = b, w = w, p = p }
    end,
}

local W = nil          -- working graph: { nx, ny, edges, adj, grid }
local extra = {}       -- admin roads: { { w = width, p = { x1, y1, ... } } }
local closedPts = {}   -- trouble spots: { { x, y, on } }, only closed ones (on) count
local penDirty = false
local penOff = false   -- this search ignores trouble spots (navigator, admin fare measure)

-- ------------------------------------------------------------------------------
-- building
-- ------------------------------------------------------------------------------
local function measure(e)
    local p = e.p
    local cum = { 0 }
    local n = #p / 2
    for i = 2, n do
        local dx, dy = p[i * 2 - 1] - p[i * 2 - 3], p[i * 2] - p[i * 2 - 2]
        cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy)
    end
    e.cum = cum
    e.len = cum[n]
end

local function cellKey(cx, cy) return cx * 10000 + cy end

local function gridAdd(ei)
    local e = W.edges[ei]
    local p = e.p
    for k = 1, #p / 2 - 1 do
        local x1, y1, x2, y2 = p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2]
        for cx = math.floor(math.min(x1, x2) / CELL), math.floor(math.max(x1, x2) / CELL) do
            for cy = math.floor(math.min(y1, y2) / CELL), math.floor(math.max(y1, y2) / CELL) do
                local key = cellKey(cx, cy)
                local list = W.grid[key]
                if not list then list = {}; W.grid[key] = list end
                list[#list + 1] = ei
                list[#list + 1] = k
            end
        end
    end
end

local function addEdge(a, b, w, p)
    local e = { a = a, b = b, w = w, p = p }
    measure(e)
    W.edges[#W.edges + 1] = e
    gridAdd(#W.edges)
    return #W.edges
end

local function addNode(x, y)
    local n = #W.nx + 1
    W.nx[n] = x
    W.ny[n] = y
    return n
end

local function project(px, py, x1, y1, x2, y2)
    local vx, vy = x2 - x1, y2 - y1
    local L2 = vx * vx + vy * vy
    local t = 0
    if L2 > 0 then
        t = ((px - x1) * vx + (py - y1) * vy) / L2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local qx, qy = x1 + vx * t, y1 + vy * t
    local dx, dy = px - qx, py - qy
    return t, qx, qy, math.sqrt(dx * dx + dy * dy)
end

-- nearest point on a live road within maxR tiles: { e, k, t, x, y, d, pos }
-- part: only roads of that connected part (W.comp of a junction)
function G.nearest(x, y, maxR, part)
    G.ensure()
    local best = nil
    for cx = math.floor((x - maxR) / CELL), math.floor((x + maxR) / CELL) do
        for cy = math.floor((y - maxR) / CELL), math.floor((y + maxR) / CELL) do
            local list = W.grid[cellKey(cx, cy)]
            if list then
                for i = 1, #list, 2 do
                    local ei, k = list[i], list[i + 1]
                    local e = W.edges[ei]
                    if not e.dead and (not part or W.comp[e.a] == part) then
                        local p = e.p
                        local t, qx, qy, d = project(x, y, p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2])
                        if d <= maxR and (not best or d < best.d) then
                            best = { e = ei, k = k, t = t, x = qx, y = qy, d = d }
                        end
                    end
                end
            end
        end
    end
    if best then
        local e = W.edges[best.e]
        best.pos = e.cum[best.k] + best.t * (e.cum[best.k + 1] - e.cum[best.k])
    end
    return best
end

-- split a live edge at a nearest() hit, returns the new junction
local function splitAt(hit)
    local e = W.edges[hit.e]
    if hit.pos <= 0.5 then return e.a end
    if hit.pos >= e.len - 0.5 then return e.b end
    local n = addNode(hit.x, hit.y)
    local p1, p2 = {}, { hit.x, hit.y }
    for i = 1, hit.k * 2 do p1[i] = e.p[i] end
    p1[#p1 + 1] = hit.x
    p1[#p1 + 1] = hit.y
    for i = hit.k * 2 + 1, #e.p do p2[#p2 + 1] = e.p[i] end
    e.dead = true
    addEdge(e.a, n, e.w, p1)
    addEdge(n, e.b, e.w, p2)
    return n
end

local function addExtra(road)
    local p = road.p
    if type(p) ~= "table" or #p < 4 then return end
    local pts = {}
    for i = 1, #p do pts[i] = p[i] end
    local function endNode(x, y, atStart)
        local hit = G.nearest(x, y, SNAP_END)
        if not hit then return addNode(x, y) end
        local n = splitAt(hit)
        if atStart then
            table.insert(pts, 1, W.ny[n])
            table.insert(pts, 1, W.nx[n])
        else
            pts[#pts + 1] = W.nx[n]
            pts[#pts + 1] = W.ny[n]
        end
        return n
    end
    local a = endNode(p[1], p[2], true)
    local b = endNode(p[#p - 1], p[#p], false)
    if a ~= b then addEdge(a, b, road.w or 8, pts) end
end

function G.build()
    penDirty = false     -- (nearest() below must not lay costs on a half-built graph; ensure() does it after)
    W = { nx = {}, ny = {}, edges = {}, adj = {}, grid = {} }
    for i = 1, #base.nx do
        W.nx[i] = base.nx[i]
        W.ny[i] = base.ny[i]
    end
    for i = 1, #base.edges do
        local e = base.edges[i]
        addEdge(e.a, e.b, e.w, e.p)
    end
    for i = 1, #extra do
        local ok, err = pcall(addExtra, extra[i])
        if not ok then COTW.log("admin road " .. i .. " skipped: " .. tostring(err)) end
    end
    for ei = 1, #W.edges do
        local e = W.edges[ei]
        if not e.dead then
            W.adj[e.a] = W.adj[e.a] or {}
            W.adj[e.b] = W.adj[e.b] or {}
            table.insert(W.adj[e.a], ei)
            table.insert(W.adj[e.b], ei)
        end
    end
    -- connected parts: map mods leave small road pieces that lead nowhere (parking lots, cut-off streets)
    W.comp, W.main, W.size = {}, nil, {}
    local size = W.size
    for n = 1, #W.nx do
        if W.adj[n] and not W.comp[n] then
            W.comp[n] = n
            size[n] = 0
            local stack = { n }
            while #stack > 0 do
                local u = table.remove(stack)
                for _, ei in ipairs(W.adj[u]) do
                    local e = W.edges[ei]
                    local v = e.a == u and e.b or e.a
                    if not W.comp[v] then
                        W.comp[v] = n
                        size[n] = size[n] + e.len
                        stack[#stack + 1] = v
                    end
                end
            end
            if not W.main or size[n] > size[W.main] then W.main = n end
        end
    end
end

-- every live road within r tiles of (x, y): { [edge] = road position closest to it }
local function edgesNear(x, y, r)
    local out, best = {}, {}
    for cx = math.floor((x - r) / CELL), math.floor((x + r) / CELL) do
        for cy = math.floor((y - r) / CELL), math.floor((y + r) / CELL) do
            local list = W.grid[cellKey(cx, cy)]
            if list then
                for i = 1, #list, 2 do
                    local ei, k = list[i], list[i + 1]
                    local e = W.edges[ei]
                    if not e.dead then
                        local p = e.p
                        local t, _, _, d = project(x, y, p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2])
                        if d <= r and (not best[ei] or d < best[ei]) then
                            best[ei] = d
                            out[ei] = e.cum[k] + t * (e.cum[k + 1] - e.cum[k])
                        end
                    end
                end
            end
        end
    end
    return out
end

-- each closed spot sits on every road within PEN_R of it (a junction, two roads drawn on top of each
-- other), or on its nearest road within NEAR: e.pen = { road positions }, e.penId = { spot }
local PEN_R = 2.5
local function applyClosed()
    penDirty = false
    for i = 1, #W.edges do W.edges[i].pen, W.edges[i].penId = nil, nil end
    for id, c in ipairs(closedPts) do
        if c.on and type(c.x) == "number" and type(c.y) == "number" then
            local near = edgesNear(c.x, c.y, PEN_R)
            local any = false
            for _ in pairs(near) do any = true; break end
            if not any then
                local hit = G.nearest(c.x, c.y, COTW.Closed.NEAR)
                if hit then near[hit.e] = hit.pos end
            end
            for ei, pos in pairs(near) do
                local e = W.edges[ei]
                e.pen, e.penId = e.pen or {}, e.penId or {}
                e.pen[#e.pen + 1] = pos
                e.penId[#e.penId + 1] = id
            end
        end
    end
end

function G.ensure()
    if not W then
        G.build()
        penDirty = true
    end
    if penDirty then applyClosed() end
end

-- admin roads changed (server load / sync): rebuild on next use
function G.setExtra(list)
    extra = type(list) == "table" and list or {}
    W = nil
end

function G.extraList() return extra end

-- trouble spots changed (server refresh / sync): costs are redone on next use, the graph stays
function G.setClosed(list)
    closedPts = type(list) == "table" and list or {}
    penDirty = true
end

function G.closedList() return closedPts end

-- every live road with a point inside the box (teach scenes): { { a, b, ax, ay, bx, by, w, p } }
function G.edgesIn(x1, y1, x2, y2)
    G.ensure()
    local seen, out = {}, {}
    for cx = math.floor(math.min(x1, x2) / CELL), math.floor(math.max(x1, x2) / CELL) do
        for cy = math.floor(math.min(y1, y2) / CELL), math.floor(math.max(y1, y2) / CELL) do
            local list = W.grid[cellKey(cx, cy)]
            if list then
                for i = 1, #list, 2 do
                    local ei = list[i]
                    local e = W.edges[ei]
                    if not seen[ei] and not e.dead then
                        seen[ei] = true
                        out[#out + 1] = { a = e.a, b = e.b, ax = W.nx[e.a], ay = W.ny[e.a], bx = W.nx[e.b], by = W.ny[e.b], w = e.w or 8, p = e.p }
                    end
                end
            end
        end
    end
    return out
end

function G.stats()
    G.ensure()
    local live = 0
    for i = 1, #W.edges do if not W.edges[i].dead then live = live + 1 end end
    return #W.nx, live, #extra
end

-- ------------------------------------------------------------------------------
-- route search (A*)
-- ------------------------------------------------------------------------------
local function heapPush(h, node, f)
    local i = #h + 1
    h[i] = { node, f }
    while i > 1 do
        local up = math.floor(i / 2)
        if h[up][2] <= h[i][2] then break end
        h[up], h[i] = h[i], h[up]
        i = up
    end
end

local function heapPop(h)
    local top = h[1]
    local last = h[#h]
    h[#h] = nil
    if #h > 0 then
        h[1] = last
        local i = 1
        while true do
            local l, r, m = i * 2, i * 2 + 1, i
            if h[l] and h[l][2] < h[m][2] then m = l end
            if h[r] and h[r][2] < h[m][2] then m = r end
            if m == i then break end
            h[m], h[i] = h[i], h[m]
            i = m
        end
    end
    return top
end

local function cost(e, len) return len * ((e.w or 8) >= COTW.HIGHWAY_WIDTH and 1 or NARROW_COST) end

-- closed spots on edge e between road positions a and b (either order); ids go into set when given
local function penCount(e, a, b, set)
    local pen = e.pen
    if not pen then return 0 end
    if a > b then a, b = b, a end
    local n = 0
    for i = 1, #pen do
        if pen[i] >= a - 0.5 and pen[i] <= b + 0.5 then
            n = n + 1
            if set then set[e.penId[i]] = true end
        end
    end
    return n
end
local function pen(e, a, b) return not penOff and e.pen and penCount(e, a, b) * COTW.Closed.COST or 0 end

-- append the points of edge ei between road positions from..to (either direction) to out
local function appendSpan(out, ei, from, to)
    local e = W.edges[ei]
    local p, cum = e.p, e.cum
    local n = #p / 2
    local function at(pos)
        for k = 1, n - 1 do
            if pos <= cum[k + 1] or k == n - 1 then
                local seg = cum[k + 1] - cum[k]
                local t = seg > 0 and (pos - cum[k]) / seg or 0
                return p[k * 2 - 1] + (p[k * 2 + 1] - p[k * 2 - 1]) * t, p[k * 2] + (p[k * 2 + 2] - p[k * 2]) * t
            end
        end
        return p[n * 2 - 1], p[n * 2]
    end
    local function push(x, y)
        local m = #out.x
        if m > 0 and math.abs(out.x[m] - x) < 0.05 and math.abs(out.y[m] - y) < 0.05 then return end
        out.x[m + 1] = x
        out.y[m + 1] = y
        out.w[m + 1] = e.w or 8
    end
    local x, y = at(from)
    push(x, y)
    if to >= from then
        for k = 1, n do if cum[k] > from and cum[k] < to then push(p[k * 2 - 1], p[k * 2]) end end
    else
        for k = n, 1, -1 do if cum[k] < from and cum[k] > to then push(p[k * 2 - 1], p[k * 2]) end end
    end
    x, y = at(to)
    push(x, y)
end

-- route from (x1, y1) to (x2, y2) along roads.
-- returns { x = {}, y = {}, w = {}, len, startGap, startOff, endGap, destX, destY, closed } or nil, reason
-- (startOff = tiles from the start past the edge of its road, 0 on the road; closed = closed trouble
-- spots the route still goes through: there was no way round shorter by COTW.Closed.COST).
-- raw = true: trouble spots cost nothing (the navigator and the admin fare measure stay as they were)
function G.route(x1, y1, x2, y2, raw)
    G.ensure()
    penOff = raw == true
    local s = G.nearest(x1, y1, 80)
    if not s then return nil, "noroad_start" end
    if not G.nearest(x2, y2, 400) then return nil, "noroad_dest" end
    -- the pin snaps to a road that the start can reach. A start on a cut-off piece (parking lot) uses
    -- the main network unless the pin is right on that piece too.
    local part = W.comp[W.edges[s.e].a]
    local d = G.nearest(x2, y2, 400, part)
    if part ~= W.main and (not d or d.d > PART_GAP) then
        local sm = G.nearest(x1, y1, 80, W.main)
        local dm = sm and G.nearest(x2, y2, 400, W.main)
        if dm then
            s, d = sm, dm
        elseif W.size[part] < PART_BIG then
            d = nil      -- no main road near: a lap of the parking lot is no route
        end              -- a whole town not linked yet (Raccoon City): route inside it as before
    end
    if not d then return nil, "unreachable" end
    local out = { x = {}, y = {}, w = {}, destX = x2, destY = y2, startGap = s.d, endGap = d.d,
                  startOff = math.max(0, s.d - (W.edges[s.e].w or 8) / 2), closed = 0 }

    local hitSpots = {}
    if s.e == d.e then
        appendSpan(out, s.e, s.pos, d.pos)
        penCount(W.edges[s.e], s.pos, d.pos, hitSpots)
    else
        local se, de = W.edges[s.e], W.edges[d.e]
        local g, came, closed = {}, {}, {}
        local h = {}
        local function hcost(n) return COTW.dist(W.nx[n], W.ny[n], d.x, d.y) end
        local function relax(n, gv, from)
            if closed[n] then return end
            if not g[n] or gv < g[n] then
                g[n] = gv
                came[n] = from
                heapPush(h, n, gv + hcost(n))
            end
        end
        relax(se.a, cost(se, s.pos) + pen(se, 0, s.pos), { start = true, e = s.e, to = 0 })
        relax(se.b, cost(se, se.len - s.pos) + pen(se, s.pos, se.len), { start = true, e = s.e, to = se.len })
        local bestEnd, bestEndG = nil, nil
        while #h > 0 do
            local top = heapPop(h)
            local u = top[1]
            if not closed[u] then
                closed[u] = true
                if bestEndG and g[u] + hcost(u) >= bestEndG then break end
                if u == de.a or u == de.b then
                    local fin = g[u] + cost(de, u == de.a and d.pos or (de.len - d.pos)) + (u == de.a and pen(de, 0, d.pos) or pen(de, d.pos, de.len))
                    if not bestEndG or fin < bestEndG then bestEndG, bestEnd = fin, u end
                end
                local list = W.adj[u]
                if list then
                    for i = 1, #list do
                        local ei = list[i]
                        local e = W.edges[ei]
                        local v = e.a == u and e.b or e.a
                        relax(v, g[u] + cost(e, e.len) + pen(e, 0, e.len), { from = u, e = ei, rev = e.b == u })
                    end
                end
            end
        end
        if not bestEnd then return nil, "unreachable" end
        local steps = {}
        local n = bestEnd
        while true do
            local c = came[n]
            table.insert(steps, 1, c)
            if c.start then break end
            n = c.from
        end
        appendSpan(out, s.e, s.pos, steps[1].to)
        penCount(se, s.pos, steps[1].to, hitSpots)
        for i = 2, #steps do
            local c = steps[i]
            local e = W.edges[c.e]
            if c.rev then appendSpan(out, c.e, e.len, 0) else appendSpan(out, c.e, 0, e.len) end
            penCount(e, 0, e.len, hitSpots)
        end
        appendSpan(out, d.e, bestEnd == de.a and 0 or de.len, d.pos)
        penCount(de, bestEnd == de.a and 0 or de.len, d.pos, hitSpots)
    end

    local len = 0
    for i = 2, #out.x do len = len + COTW.dist(out.x[i - 1], out.y[i - 1], out.x[i], out.y[i]) end
    out.len = len
    for _ in pairs(hitSpots) do out.closed = out.closed + 1 end
    if #out.x < 2 then return nil, "too_short" end
    return out
end
