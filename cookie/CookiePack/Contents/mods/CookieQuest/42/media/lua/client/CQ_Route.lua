-- Cookie Quest - guide line on the ground ( dot - dash - dot ) toward the tracked checkpoint.
-- The way is searched over the squares loaded around the player: streets and sidewalks are
-- preferred, walls / water / furniture are avoided. It is searched again while you walk, so a
-- far target is reached piece by piece. Falls back to a straight line when no way is found.
require "CQ_UI_Kit"
require "CQ_UI_RadioText"

CQRoute = CQRoute or {}
local RT = CQRoute
local C = CQUI.C
local T = CQC.txt

RT.RADIUS = 48          -- tiles searched around the player
RT.MAX_NODES = 3500     -- squares expanded per search
RT.PER_TICK = 90        -- expansions per game tick (keeps the frame rate smooth)
RT.DRAW_TILES = 32      -- how far ahead the line is drawn
RT.UNIT = 2.6           -- pattern length in tiles: one dot + one dash
RT.SPEED = 1.3          -- tiles per second the pattern flows toward the target

RT.path = nil           -- { {x, y}, ... } tile centres from the player toward the target
RT.reached = false      -- the path ends inside the checkpoint
RT.job = nil

local floor = math.floor
local SHIFT = 65536

local function key(x, y) return x * SHIFT + y end

function RT.enabled()
    return CQC.cfg.routeOff ~= "1"
end

-- ------------------------------------------------------------------ squares
-- B42 renamed some Java methods between builds (PropertyContainer.Is -> has ...), so every
-- call goes through call(): a missing method answers nil instead of raising an error
local function call(o, m, ...)
    if o == nil then return nil end
    local f = o[m]
    if f == nil then return nil end
    local ok, r = pcall(f, o, ...)
    if ok then return r end
    return nil
end
RT.call = call

local function flag(props, name)
    if not props or not IsoFlagType then return false end
    local f = IsoFlagType[name]
    if f == nil then return false end
    if props.has then return call(props, "has", f) == true end
    if props.Is then return call(props, "Is", f) == true end
    return false
end

local function sqInfo(job, x, y)
    local k = key(x, y)
    local c = job.cache[k]
    if c ~= nil then return c end
    local info = false
    local sq = call(job.cell, "getGridSquare", x, y, job.z)
    if sq then
        local fl = call(sq, "getFloor")
        local props = call(sq, "getProperties")
        local wet = flag(props, "water")
        if fl and not wet and call(sq, "isSolid") ~= true and call(sq, "isSolidTrans") ~= true then
            local name = ""
            local spr = call(fl, "getSprite")
            local nm = spr and call(spr, "getName")
            if type(nm) == "string" then name = nm end
            local cost = 2.2
            if string.find(name, "street", 1, true) or string.find(name, "road", 1, true) then
                cost = 1.0
            elseif string.find(name, "floors_interior", 1, true) then
                cost = 1.7
            end
            if call(sq, "getTree") then cost = cost + 3 end
            info = { sq = sq, cost = cost }
        end
    end
    job.cache[k] = info
    return info
end

local function blocked(a, b)
    return call(a.sq, "isBlockedTo", b.sq) == true
end

-- ------------------------------------------------------------------ binary heap on f
local function push(job, k, f)
    local h, fv = job.heap, job.hf
    local i = #h + 1
    h[i], fv[i] = k, f
    while i > 1 do
        local p = floor(i / 2)
        if fv[p] <= fv[i] then break end
        h[p], h[i] = h[i], h[p]
        fv[p], fv[i] = fv[i], fv[p]
        i = p
    end
end

local function pop(job)
    local h, fv = job.heap, job.hf
    local n = #h
    if n == 0 then return nil end
    local top = h[1]
    h[1], fv[1] = h[n], fv[n]
    h[n], fv[n] = nil, nil
    n = n - 1
    local i = 1
    while true do
        local l, r = i * 2, i * 2 + 1
        local s = i
        if l <= n and fv[l] < fv[s] then s = l end
        if r <= n and fv[r] < fv[s] then s = r end
        if s == i then break end
        h[s], h[i] = h[i], h[s]
        fv[s], fv[i] = fv[i], fv[s]
        i = s
    end
    return top
end

-- ------------------------------------------------------------------ search
local DIRS = {
    { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
    { 1, 1, 1.414 }, { 1, -1, 1.414 }, { -1, 1, 1.414 }, { -1, -1, 1.414 },
}

local function dist(x1, y1, x2, y2)
    local dx, dy = math.abs(x1 - x2), math.abs(y1 - y2)
    return math.max(dx, dy) + 0.414 * math.min(dx, dy)
end

local function inGoal(job, x, y)
    local z = job.zone
    return x >= z.x1 and x <= z.x2 and y >= z.y1 and y <= z.y2
end

-- distance from a square to the checkpoint rectangle
local function hGoal(job, x, y)
    local z = job.zone
    local cx = math.max(z.x1, math.min(z.x2, x))
    local cy = math.max(z.y1, math.min(z.y2, y))
    return dist(x, y, cx, cy)
end

function RT.newJob(px, py, pz, zone)
    local job = {
        sx = px, sy = py, z = pz, zone = zone, cell = getCell(), cache = {},
        heap = {}, hf = {}, g = {}, came = {}, closed = {}, n = 0,
        minX = px - RT.RADIUS, maxX = px + RT.RADIUS, minY = py - RT.RADIUS, maxY = py + RT.RADIUS,
    }
    local k = key(px, py)
    job.g[k] = 0
    job.best, job.bestH = k, hGoal(job, px, py)
    push(job, k, job.bestH)
    return job
end

-- expand up to budget squares; true when the search is over
function RT.stepJob(job, budget)
    while budget > 0 do
        local k = pop(job)
        if not k then return true end
        if not job.closed[k] then
            job.closed[k] = true
            job.n = job.n + 1
            budget = budget - 1
            local x = floor(k / SHIFT)
            local y = k - x * SHIFT
            local hh = hGoal(job, x, y)
            if hh < job.bestH then job.best, job.bestH = k, hh end
            if inGoal(job, x, y) then job.best, job.bestH = k, 0; return true end
            if job.n >= RT.MAX_NODES then return true end
            local a = sqInfo(job, x, y)
            local g0 = job.g[k]
            for i = 1, 8 do
                local d = DIRS[i]
                local nx, ny = x + d[1], y + d[2]
                if nx >= job.minX and nx <= job.maxX and ny >= job.minY and ny <= job.maxY then
                    local nk = key(nx, ny)
                    if not job.closed[nk] then
                        local b = sqInfo(job, nx, ny)
                        if b then
                            local ok
                            if not a then
                                ok = true
                            elseif d[3] == 1 then
                                ok = not blocked(a, b)
                            else
                                -- diagonal: both side squares open, no wall corner cut
                                local c1 = sqInfo(job, x + d[1], y)
                                local c2 = sqInfo(job, x, y + d[2])
                                ok = c1 and c2 and not blocked(a, c1) and not blocked(a, c2)
                                    and not blocked(c1, b) and not blocked(c2, b)
                            end
                            if ok then
                                local ng = g0 + d[3] * b.cost
                                local og = job.g[nk]
                                if og == nil or ng < og then
                                    job.g[nk] = ng
                                    job.came[nk] = k
                                    push(job, nk, ng + 1.15 * hGoal(job, nx, ny))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

function RT.finishJob(job)
    local out = {}
    local k = job.best
    local guard = 0
    while k and guard < 4000 do
        guard = guard + 1
        local x = floor(k / SHIFT)
        local y = k - x * SHIFT
        table.insert(out, 1, { x + 0.5, y + 0.5 })
        k = job.came[k]
    end
    if #out < 2 then return nil, false end
    return out, job.bestH == 0
end

-- ------------------------------------------------------------------ driving the search
local lastTick = 0

local function straight(px, py, tgt)
    return { { px, py }, { tgt.x, tgt.y } }
end

function RT.update()
    local p = CQC.player()
    local tgt = RT.enabled() and CQC.trackTarget() or nil
    if not p or p:isDead() or not tgt then
        RT.path, RT.job, RT.key, RT.tgt = nil, nil, nil, nil
        return
    end
    RT.tgt = tgt
    local px, py, pz = floor(p:getX()), floor(p:getY()), floor(p:getZ())
    local tkey = tostring(tgt.x) .. "," .. tostring(tgt.y) .. "," .. tostring(tgt.z) .. "," .. tostring(tgt.w) .. "," .. tostring(tgt.h)
    local now = getTimestampMs()
    if CQ.inZone(tgt.zone, p:getX(), p:getY(), p:getZ()) then
        RT.path, RT.job = nil, nil
        RT.key = tkey
        return
    end
    -- start a new search when the target changes, we walked away from the last start, or it got old
    if not RT.job then
        local moved = (RT.from == nil) or dist(px, py, RT.from[1], RT.from[2]) >= 4 or RT.from[3] ~= pz
        local old = now - (RT.at or 0) > 8000 and RT.from and dist(px, py, RT.from[1], RT.from[2]) >= 2
        if tkey ~= RT.key or moved or old then
            RT.key = tkey
            RT.from = { px, py, pz }
            RT.at = now
            local ok, job = pcall(RT.newJob, px, py, pz, tgt.zone)
            if ok then RT.job = job else RT.path = straight(p:getX(), p:getY(), tgt) end
        end
    end
    if RT.job then
        local ok, done = pcall(RT.stepJob, RT.job, RT.PER_TICK)
        if not ok then
            if not RT.errLogged then RT.errLogged = true; CQ.log("route search error: " .. tostring(done)) end
            RT.job = nil
            RT.path, RT.reached = straight(p:getX(), p:getY(), tgt), false
        elseif done then
            local path, reached = RT.finishJob(RT.job)
            RT.job = nil
            if path then RT.path, RT.reached = path, reached
            else RT.path, RT.reached = straight(p:getX(), p:getY(), tgt), false end
        end
    end
end

-- ------------------------------------------------------------------ drawing
local function project(x, y, z)
    return isoToScreenX(0, x, y, z), isoToScreenY(0, x, y, z)
end

local function zoom()
    local ok, z = pcall(function() return getCore():getZoom(0) end)
    if ok and type(z) == "number" and z > 0 then return z end
    return 1
end

RT.DOT_W = 15           -- px at zoom 1
RT.DASH_W = 10
RT.DASH_FROM, RT.DASH_TO = 0.75, 1.95   -- where the dash sits inside one pattern unit (tiles)

-- position at increasing distances along the polyline
local function sampler(pts)
    local i, acc = 2, 0
    local function segLen(j)
        local dx, dy = pts[j][1] - pts[j - 1][1], pts[j][2] - pts[j - 1][2]
        return math.sqrt(dx * dx + dy * dy)
    end
    local cur = segLen(2)
    return function(d)
        while i <= #pts and d > acc + cur do
            acc = acc + cur
            i = i + 1
            if i <= #pts then cur = segLen(i) end
        end
        if i > #pts then return nil end
        local a, b = pts[i - 1], pts[i]
        local t = (d - acc) / math.max(0.0001, cur)
        return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
    end
end

function RT.draw(el)
    local path = RT.path
    local tgt = RT.tgt
    if not path or not tgt then return end
    local p = CQC.player()
    if not p then return end
    local tex = CQUI.tex("cq_dot")
    if not tex then return end
    local z = RT.from and RT.from[3] or floor(p:getZ())
    local px, py = p:getX(), p:getY()
    -- start from the path node nearest to the player (the part already walked is dropped)
    local best, bestD = 1, nil
    for i = 1, math.min(#path, 40) do
        local d = dist(px, py, path[i][1], path[i][2])
        if not bestD or d < bestD then best, bestD = i, d end
    end
    local pts = { { px, py } }
    for i = best + 1, #path do pts[#pts + 1] = path[i] end
    if #pts < 2 then return end
    local total = 0
    for i = 2, #pts do
        local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
        total = total + math.sqrt(dx * dx + dy * dy)
    end
    local limit = math.min(total, RT.DRAW_TILES)
    local zm = zoom()
    local col = C.accent
    -- dots sit at flow + n * UNIT and move toward the target; a dash follows each dot
    local flow = CQ.mod(getTimestampMs() / 1000 * RT.SPEED, RT.UNIT)
    local at = sampler(pts)
    local samples = {}
    local function add(d, w)
        if d < 0.35 or d > limit then return end
        local wx, wy = at(d)
        if not wx then return end
        local a = 1
        if d > limit - 6 and limit >= RT.DRAW_TILES then a = math.max(0, (limit - d) / 6) end
        if d < 1.2 then a = a * (d / 1.2) end
        local sx, sy = project(wx, wy, z)
        samples[#samples + 1] = { sx, sy, w, a }
    end
    local spacing = 0.085
    local d0 = flow - RT.UNIT
    while d0 <= limit do
        add(d0, RT.DOT_W / zm)
        local e = d0 + RT.DASH_FROM
        while e <= d0 + RT.DASH_TO and e <= limit do
            add(e, RT.DASH_W / zm)
            e = e + spacing
        end
        d0 = d0 + RT.UNIT
    end
    -- outline first, then colour, so the pieces of a dash melt into one stroke
    for i = 1, #samples do
        local s = samples[i]
        local w, h = s[3] + 3, (s[3] + 3) * 0.55
        el:drawTextureScaled(tex, s[1] - w / 2, s[2] - h / 2 + 1, w, h, s[4] * 0.7, 0, 0, 0)
    end
    for i = 1, #samples do
        local s = samples[i]
        local w, h = s[3], s[3] * 0.55
        el:drawTextureScaled(tex, s[1] - w / 2, s[2] - h / 2, w, h, s[4], col[1], col[2], col[3])
    end
    -- at the checkpoint: which floor it is on
    if RT.reached then
        local last = pts[#pts]
        local sx, sy = project(last[1], last[2], z + 0.35)
        local txt = CQUI.floorInfo(tgt.zone, floor(p:getZ()))
        if CQRT and CQRT.outlined then CQRT.outlined(el, txt, sx, sy, C.gold, 1, UIFont.Small) end
    end
end

-- an invisible 1x1 element: draws under the windows, never catches the mouse
local R = ISUIElement:derive("CQRouteLine")

function R:new()
    local o = ISUIElement.new(self, 0, 0, 1, 1)
    o.anchorLeft, o.anchorTop = true, true
    return o
end

function R:prerender() end

function R:render()
    local ok, err = pcall(RT.draw, self)
    if not ok and not self.errLogged then
        self.errLogged = true
        CQ.log("route draw error: " .. tostring(err))
    end
end

function RT.ensure()
    if RT.el then return end
    local el = R:new()
    el:initialise()
    el:instantiate()
    el:addToUIManager()
    if el.backMost then el:backMost() end
    RT.el = el
end

Events.OnGameStart.Add(function() RT.ensure() end)
Events.OnTick.Add(function()
    local ok, err = pcall(RT.update)
    if not ok and not RT.updLogged then
        RT.updLogged = true
        CQ.log("route update error: " .. tostring(err))
    end
end)

return RT
