-- Cookie Mission - task minigames: one window each, the world (and the horde) keeps running behind it
-- wire = match the wires, safe = pick the lock, pipe = turn the pipes, board = nail the plank, trap = repeat the code
require "CM_UI_Kit"

CMGame = CMGame or {}
CMGame.KINDS = CMGame.KINDS or {}
local C = CMUI.C
local T = CMC.txt
local PI = 3.14159265

local function S(n) return CMUI.S(n) end
local function rnd(n) if n <= 1 then return 0 end return ZombRand(n) end
local function sfx(name) pcall(function() getSoundManager():playUISound(name) end) end
local function mix(a, b, k) return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k } end

-- ===================================================================== drawing helpers
-- thick straight line (a solid quad), any angle
function CMUI.line(win, x1, y1, x2, y2, th, c, a)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return end
    local nx, ny = -dy / len * th / 2, dx / len * th / 2
    if win.grow then win:grow(math.max(y1, y2) + th) end
    local jo = win.javaObject
    if jo then
        -- the 4-point DrawTexture takes screen coords (unlike drawRect), so shift by the window's place on screen
        local ox, oy = jo:getAbsoluteX(), jo:getAbsoluteY() + jo:getYScroll()
        x1, y1, x2, y2 = x1 + ox, y1 + oy, x2 + ox, y2 + oy
        jo:DrawTexture(nil, x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny, c[1], c[2], c[3], a or 1)
    elseif win.drawLineQuad then
        win:drawLineQuad(x1, y1, x2, y2, th, c, a)
    end
end

function CMUI.disc(win, cx, cy, r, c, a)
    if not CMUI.texBox(win, "cm_disc", cx - r, cy - r, r * 2, r * 2, c, a) then
        win:drawRect(cx - r, cy - r, r * 2, r * 2, a or 1, c[1], c[2], c[3])
    end
end

function CMUI.ring(win, cx, cy, r, c, a)
    if not CMUI.texBox(win, "cm_ring", cx - r, cy - r, r * 2, r * 2, c, a) then
        win:drawRectBorder(cx - r, cy - r, r * 2, r * 2, a or 1, c[1], c[2], c[3])
    end
end

-- point on a circle; deg 0 = right, 90 = up (screen y grows down)
local function polar(cx, cy, r, deg)
    local rad = deg * PI / 180
    return cx + math.cos(rad) * r, cy - math.sin(rad) * r
end

local function shuffle(n)
    local a = {}
    for i = 1, n do a[i] = i end
    for i = n, 2, -1 do
        local j = rnd(i) + 1
        a[i], a[j] = a[j], a[i]
    end
    return a
end

-- ===================================================================== base window
CMGame.Win = CMUI.Window:derive("CMGame_Win")
local G = CMGame.Win

function G:new(kind, tier, ctx)
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(560, 500)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = CMUI.Window.new(self, math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    o.kind = kind
    o.tier = tier or 1
    o.ctx = ctx or {}
    o.title = CMC.typeName(kind)
    o.subtitle = CMC.tierName(o.tier)
    o.titleIcon = "cm_t_" .. tostring(kind)
    o.limit = CM.gameTime(kind, o.tier)
    o.t0 = CMC.ms()
    o.last = o.t0
    o.pen = 0
    o.state = "play"
    o.mdown = false
    o.msgs = {}
    o.shakeAt = 0
    o.bgAlpha = 0.9
    o.gx, o.gy, o.gw, o.gh = 0, 0, w, h
    return o
end

function G:left(t)
    return self.limit - (t - self.t0) / 1000 - self.pen
end

function G:say(s, c)
    table.insert(self.msgs, 1, { s = tostring(s), c = c or C.text, at = CMC.ms() })
    while #self.msgs > 2 do table.remove(self.msgs) end
end

function G:shake() self.shakeAt = CMC.ms() end

-- a mistake: lose seconds, shake, red text
function G:penalty(sec, text)
    self.pen = self.pen + sec
    self:shake()
    self:say(text, C.bad)
    sfx("UIActivateMainMenuItem")
end

function G:finish(ok, why)
    if self.state ~= "play" then return end
    self.state = ok and "win" or "lose"
    self.why = why or (ok and "ok" or "fail")
    self.endAt = CMC.ms() + (ok and 900 or 1600)
    self.mdown = false
    if not ok then self:shake() end
    sfx(ok and "UIActivateButton" or "UIActivateMainMenuItem")
end

function G:done()
    if self.closed then return end
    self.closed = true
    self:setVisible(false)
    self:removeFromUIManager()
    if CMGame.cur == self then CMGame.cur = nil end
    if self.cb then
        local ok, err = pcall(self.cb, self.state == "win", self.why or "cancel", self)
        if not ok then CM.log("minigame callback error: " .. tostring(err)) end
    end
end

-- the window close button and "give up" both end the game without a penalty
function G:close()
    if self.state == "play" then
        self.state = "lose"
        self.why = "cancel"
    end
    self:done()
end

-- drop the window without telling anyone (a newer game replaced it, the run ended)
function G:drop()
    self.cb = nil
    self:done()
end

function G:inGame(mx, my)
    return mx >= self.gx and mx < self.gx + self.gw and my >= self.gy and my < self.gy + self.gh
end

function G:onMouseDown(x, y)
    self:bringToTop()
    local h = self:findHit(x, y)
    if h then self.pressed = h; return true end
    if y < self.headerH then self.dragging = true; return true end
    if self.state == "play" and self:inGame(x, y) then
        self.mdown = true
        if self.press then
            local ok, err = pcall(self.press, self, x, y)
            if not ok then CM.log("minigame press error: " .. tostring(err)) end
        end
    end
    return true
end

function G:onMouseUp(x, y)
    local was = self.mdown
    self.mdown = false
    if was and self.state == "play" and self.release then
        local ok, err = pcall(self.release, self, x, y)
        if not ok then CM.log("minigame release error: " .. tostring(err)) end
    end
    return CMUI.Window.onMouseUp(self, x, y)
end

function G:onMouseUpOutside(x, y)
    local was = self.mdown
    self.mdown = false
    if was and self.state == "play" and self.release then pcall(self.release, self, x, y) end
    CMUI.Window.onMouseUpOutside(self, x, y)
end

-- still at the target, alive and on foot?
function CMGame.stillHere(ctx)
    local p = CMC.player()
    if not p then return false end
    local okD, dead = pcall(function() return p:isDead() end)
    if okD and dead then return false end
    local okV, veh = pcall(function() return p:getVehicle() end)
    if okV and veh then return false end
    if not ctx or ctx.x == nil then return true end
    local dx, dy = p:getX() - (ctx.x + 0.5), p:getY() - (ctx.y + 0.5)
    return dx * dx + dy * dy <= 3.5 * 3.5 and math.abs(p:getZ() - (ctx.z or 0)) < 1.5
end

local LOSE_KEY = { time = "IGUI_CM_G_lose_time", picks = "IGUI_CM_G_lose_picks", boom = "IGUI_CM_G_lose_boom",
    far = "IGUI_CM_G_lose_far", fail = "IGUI_CM_G_lose_time" }

function G:drawBody()
    local t = CMC.ms()
    local dt = math.min(0.1, math.max(0, (t - self.last) / 1000))
    self.last = t
    if self.state == "play" then
        if self:left(t) <= 0 then self:finish(false, "time")
        elseif not CMGame.stillHere(self.ctx) then self:finish(false, "far") end
    end
    if self.state == "play" and self.tick then self:tick(dt, t) end
    if self.state ~= "play" and t >= (self.endAt or 0) then self:done(); return end
    local pad = S(16)
    local x, w = pad, self.width - pad * 2
    local y = self.headerH + S(12)
    local tc = CMUI.tierColor(self.tier)
    -- time left
    local left = math.max(0, self:left(t))
    local lc = left <= 6 and C.bad or tc
    CMUI.segbar(self, x, y + S(6), w - S(70), S(8), left / math.max(1, self.limit), lc, 30)
    CMUI.textR(self, tostring(math.ceil(left)) .. "s", x + w, y, lc, 1, UIFont.Medium)
    y = y + S(28)
    if self.status then CMUI.text(self, CMUI.fit(self:status(), UIFont.Small, w), x, y, C.text) end
    y = y + CMUI.fh(UIFont.Small) + S(8)
    local footH = S(66)
    local gh = self.height - y - footH
    local sx = 0
    if t - self.shakeAt < 320 then sx = (rnd(9) - 4) * CMUI.k end
    CMUI.rbox(self, x, y, w, gh, C.dark, 0.72, 10)
    CMUI.rborder(self, x, y, w, gh, C.line, 0.35, 10)
    self.gx, self.gy, self.gw, self.gh = x + sx, y, w, gh
    if self.drawGame then self:drawGame(x + sx, y, w, gh, t) end
    -- short messages over the play area
    local my = y + S(10)
    for i = #self.msgs, 1, -1 do
        local m = self.msgs[i]
        local age = (t - m.at) / 1000
        if age > 1.4 then table.remove(self.msgs, i) end
    end
    for _, m in ipairs(self.msgs) do
        local age = (t - m.at) / 1000
        local a = age < 1.0 and 1 or math.max(0, 1 - (age - 1.0) / 0.4)
        CMUI.textC(self, m.s, x + w / 2, my - age * S(10), m.c, a, UIFont.Medium)
        my = my + CMUI.fh(UIFont.Medium) + S(2)
    end
    -- the end
    if self.state ~= "play" then
        local ok = self.state == "win"
        local col = ok and C.good or C.bad
        CMUI.rbox(self, x, y, w, gh, C.bg, 0.55, 10)
        CMUI.glow(self, x + w / 2, y + gh / 2, w * 0.4, gh * 0.3, col, 0.45)
        local key = ok and "IGUI_CM_G_win" or (LOSE_KEY[self.why] or "IGUI_CM_G_lose_time")
        CMUI.textC(self, T(key), x + w / 2, y + gh / 2 - CMUI.fh(UIFont.Large) / 2, col, 1, UIFont.Large)
    end
    -- help + give up
    local fy = self.height - footH + S(10)
    CMUI.para(self, T("IGUI_CM_G_help_" .. tostring(self.kind)), x, fy, w - S(124), C.dim, UIFont.Small, 2)
    CMUI.btn(self, x + w - S(112), fy + S(4), S(112), S(30), T("IGUI_CM_G_cancel"), function() self:close() end, "ghost")
end

-- ===================================================================== wire: drag each wire to the socket of its colour
local WIRE_COL = {
    { 0.95, 0.25, 0.25 }, { 0.25, 0.55, 1.00 }, { 1.00, 0.85, 0.20 },
    { 0.30, 0.90, 0.40 }, { 0.80, 0.40, 1.00 }, { 1.00, 0.55, 0.15 },
}
local WIRE_TAG = { "A", "B", "C", "D", "E", "F" }

local Wire = G:derive("CMGame_Wire")
CMGame.KINDS.wire = Wire

function Wire:setup()
    self.n = CM.gameVal("wire", "n", self.tier)
    self.L = shuffle(self.n)
    self.R = shuffle(self.n)
    self.ok = {}
    self.nOk = 0
    self.drag = nil
end

function Wire:status() return T("IGUI_CM_G_wires", self.nOk, self.n) end

-- centre of a plug (side 1) or socket (side 2) on a row
function Wire:pos(side, row)
    local rowH = self.gh / self.n
    local cx = side == 1 and (self.gx + S(52)) or (self.gx + self.gw - S(52))
    return cx, self.gy + rowH * (row - 0.5)
end

function Wire:rowOf(side, col)
    local list = side == 1 and self.L or self.R
    for r = 1, self.n do if list[r] == col then return r end end
    return 1
end

function Wire:press(mx, my)
    local r = S(26)
    for row = 1, self.n do
        local col = self.L[row]
        local cx, cy = self:pos(1, row)
        if not self.ok[col] and math.abs(mx - cx) <= r and math.abs(my - cy) <= r then
            self.drag = col
            sfx("UISelectListItem")
            return
        end
    end
end

function Wire:release(mx, my)
    local col = self.drag
    self.drag = nil
    if not col then return end
    local r = S(30)
    for row = 1, self.n do
        local cx, cy = self:pos(2, row)
        if math.abs(mx - cx) <= r and math.abs(my - cy) <= r then
            local want = self.R[row]
            if want == col then
                self.ok[col] = true
                self.nOk = self.nOk + 1
                sfx("UIActivateButton")
                if self.nOk >= self.n then self:finish(true) end
            elseif not self.ok[want] then
                self.sparkAt = CMC.ms()
                self.sparkX, self.sparkY = cx, cy
                self:penalty(2, T("IGUI_CM_G_shock", 2))
            end
            return
        end
    end
end

local function wire(win, x1, y1, x2, y2, col, k)
    local mx = x1 + (x2 - x1) * 0.5
    CMUI.line(win, x1, y1, mx, y1 + (y2 - y1) * 0.15, S(11), C.ink, 0.9)
    CMUI.line(win, mx, y1 + (y2 - y1) * 0.15, x2, y2, S(11), C.ink, 0.9)
    CMUI.line(win, x1, y1, mx, y1 + (y2 - y1) * 0.15, S(7), col, k or 1)
    CMUI.line(win, mx, y1 + (y2 - y1) * 0.15, x2, y2, S(7), col, k or 1)
end

function Wire:drawGame(x, y, w, h, t)
    -- the two terminal strips
    CMUI.rbox(self, x + S(14), y + S(8), S(76), h - S(16), C.panel2, 0.55, 8)
    CMUI.rbox(self, x + w - S(90), y + S(8), S(76), h - S(16), C.panel2, 0.55, 8)
    local pr = S(15)
    for col = 1, self.n do
        if self.ok[col] then
            local x1, y1 = self:pos(1, self:rowOf(1, col))
            local x2, y2 = self:pos(2, self:rowOf(2, col))
            wire(self, x1, y1, x2, y2, WIRE_COL[col])
        end
    end
    for row = 1, self.n do
        local col = self.L[row]
        local cx, cy = self:pos(1, row)
        local c = WIRE_COL[col]
        CMUI.line(self, x, cy, cx, cy, S(8), c, 0.85)
        CMUI.glow(self, cx, cy, pr * 2, pr * 2, c, self.ok[col] and 0.15 or 0.4)
        CMUI.disc(self, cx, cy, pr, c, 1)
        CMUI.textC(self, WIRE_TAG[col], cx, cy - CMUI.fh(UIFont.Small) / 2, C.ink, 1, UIFont.Small)
        local sx, sy = self:pos(2, row)
        local sc = WIRE_COL[self.R[row]]
        CMUI.line(self, sx, sy, x + w, sy, S(8), sc, 0.85)
        CMUI.disc(self, sx, sy, pr, C.dark, 1)
        CMUI.ring(self, sx, sy, pr, sc, 1)
        if self.ok[self.R[row]] then CMUI.disc(self, sx, sy, pr * 0.6, sc, 1) end
        CMUI.textC(self, WIRE_TAG[self.R[row]], sx, sy - CMUI.fh(UIFont.Small) / 2, sc, 1, UIFont.Small)
    end
    if self.drag then
        local x1, y1 = self:pos(1, self:rowOf(1, self.drag))
        wire(self, x1, y1, self:getMouseX(), self:getMouseY(), WIRE_COL[self.drag], 0.9)
    end
    if self.sparkAt and t - self.sparkAt < 350 then
        local k = 1 - (t - self.sparkAt) / 350
        CMUI.glow(self, self.sparkX, self.sparkY, S(60), S(60), C.white, 0.8 * k)
        for i = 0, 5 do
            local ex, ey = polar(self.sparkX, self.sparkY, S(26) + S(18) * (1 - k), i * 60 + t / 7)
            CMUI.line(self, self.sparkX, self.sparkY, ex, ey, S(3), { 1, 0.95, 0.5 }, k)
        end
    end
end

-- ===================================================================== safe: find the sweet spot, hold to turn the lock
local Safe = G:derive("CMGame_Safe")
CMGame.KINDS.safe = Safe

function Safe:setup()
    self.pins = CM.gameVal("safe", "pins", self.tier)
    self.zone = CM.gameVal("safe", "zone", self.tier)
    self.picks = CM.gameVal("safe", "picks", self.tier)
    self.pin = 1
    self.turn = 0
    self.strain = 0
    self.maxT = 0
    self.a = 90
    self:newSpot()
end

function Safe:newSpot()
    self.sweet = 12 + rnd(157)
end

function Safe:status()
    return T("IGUI_CM_G_pins", self.pin - 1, self.pins) .. "     " .. T("IGUI_CM_G_picks", self.picks)
end

-- the pick follows the mouse left-right; while turning it stays where it was
function Safe:mouseAngle()
    local a = (self:getMouseX() - self.gx - S(40)) / math.max(1, self.gw - S(80)) * 180
    return CM.clamp(a, 0, 180)
end

function Safe:press(mx, my)
    self.a = self:mouseAngle()
end

function Safe:tick(dt, t)
    if not self.mdown then self.a = self:mouseAngle() end
    if self.mdown then
        local d = math.abs(self.a - self.sweet)
        local maxT = 1
        if d > self.zone then maxT = CM.clamp(1 - (d - self.zone) / 40, 0, 1) end
        self.maxT = maxT
        if self.turn < maxT then
            self.turn = math.min(maxT, self.turn + dt * 1.15)
        end
        if self.turn >= 1 then
            self.pin = self.pin + 1
            sfx("UIActivateButton")
            if self.pin > self.pins then
                self:finish(true)
                return
            end
            self:say(T("IGUI_CM_G_click"), C.good)
            self:newSpot()
            self.turn = 0
            self.strain = 0
            self.mdown = false
        elseif self.turn >= maxT - 0.0001 then
            self.strain = self.strain + dt
            if self.strain >= 0.9 then
                self.picks = self.picks - 1
                self.strain = 0
                self.turn = 0
                self.mdown = false
                self:shake()
                self:say(T("IGUI_CM_G_snap"), C.bad)
                sfx("UIActivateMainMenuItem")
                if self.picks <= 0 then self:finish(false, "picks") end
            end
        end
    else
        self.turn = math.max(0, self.turn - dt * 2.5)
        self.strain = math.max(0, self.strain - dt * 2)
    end
end

function Safe:drawGame(x, y, w, h, t)
    local cx, cy = x + w / 2, y + h * 0.58
    local R = math.max(S(30), math.min(w * 0.26, (h * 0.58 - S(24)) / 1.42, (h * 0.42 - S(30)) / 1.08))
    -- the arc the pick moves on
    for i = 0, 36 do
        local px, py = polar(cx, cy, R * 1.42, 180 - i * 5)
        local big = CM.mod(i, 6) == 0
        CMUI.disc(self, px, py, big and S(3) or S(2), C.faint, big and 0.9 or 0.5)
    end
    -- safe door + dial
    CMUI.rbox(self, cx - R * 1.08, cy - R * 1.08, R * 2.16, R * 2.16, C.panel, 0.65, 14)
    CMUI.rborder(self, cx - R * 1.08, cy - R * 1.08, R * 2.16, R * 2.16, C.line, 0.4, 14)
    CMUI.disc(self, cx, cy, R, C.panel2, 1)
    CMUI.ring(self, cx, cy, R, C.line, 0.9)
    local rot = self.turn * 90
    for i = 0, 23 do
        local a = i * 15 + rot
        local x1, y1 = polar(cx, cy, R * 0.80, a)
        local x2, y2 = polar(cx, cy, R * (CM.mod(i, 6) == 0 and 0.66 or 0.72), a)
        CMUI.line(self, x1, y1, x2, y2, S(CM.mod(i, 6) == 0 and 4 or 2), C.dim, 0.9)
    end
    -- keyhole turns with the lock
    local kx1, ky1 = polar(cx, cy, R * 0.42, 90 + rot)
    local kx2, ky2 = polar(cx, cy, R * 0.42, 270 + rot)
    CMUI.disc(self, cx, cy, R * 0.18, C.ink, 1)
    CMUI.line(self, kx1, ky1, kx2, ky2, S(10), C.ink, 1)
    -- tension wrench at the bottom of the keyhole
    local wx, wy = polar(cx, cy, R * 0.40, 270 + rot)
    local wx2, wy2 = polar(wx, wy, R * 0.9, 300 + rot)
    CMUI.line(self, wx, wy, wx2, wy2, S(5), C.dim, 1)
    -- the pick: shakes and goes red under strain
    local jitter = self.strain > 0 and (rnd(5) - 2) * self.strain * 1.6 or 0
    local pc = mix(C.gold, C.bad, CM.clamp(self.strain / 0.9, 0, 1))
    local px, py = polar(cx, cy, R * 1.42, 180 - self.a + jitter)
    CMUI.line(self, cx, cy, px, py, S(4), pc, 1)
    CMUI.disc(self, px, py, S(6), pc, 1)
    CMUI.glow(self, px, py, S(18), S(18), pc, 0.5)
    -- pins (top left) and picks left (top right)
    for i = 1, self.pins do
        local open = i < self.pin
        local dx = x + S(22) + (i - 1) * S(22)
        CMUI.disc(self, dx, y + S(22), S(7), open and C.good or C.panel3, 1)
        if open then CMUI.glow(self, dx, y + S(22), S(14), S(14), C.good, 0.5) end
    end
    for i = 1, self.picks do
        local px2 = x + w - S(20) - (i - 1) * S(14)
        CMUI.line(self, px2, y + S(12), px2, y + S(34), S(3), C.gold, 1)
    end
    -- how far the lock turns is the only hint
    CMUI.segbar(self, x + w / 2 - S(80), y + h - S(14), S(160), S(5), self.turn, self.turn >= 0.999 and C.good or C.accent, 12)
end

-- ===================================================================== pipe: turn the pieces until water reaches the outlet
local DIRS = { "n", "e", "s", "w" }
local DX = { n = 0, e = 1, s = 0, w = -1 }
local DY = { n = -1, e = 0, s = 1, w = 0 }
local OPP = { n = "s", e = "w", s = "n", w = "e" }
local function rotCW(c) return { n = c.w, e = c.n, s = c.e, w = c.s } end

local function genPath(n, sr)
    local seen = {}
    local function key(r, c) return r * 100 + c end
    local stack = { { r = sr, c = 1 } }
    seen[key(sr, 1)] = true
    local guard = 0
    while #stack > 0 and guard < 4000 do
        guard = guard + 1
        local top = stack[#stack]
        if top.c == n then return stack end
        local opts = {}
        for _, d in ipairs(DIRS) do
            local r2, c2 = top.r + DY[d], top.c + DX[d]
            if r2 >= 1 and r2 <= n and c2 >= 1 and c2 <= n and not seen[key(r2, c2)] then
                opts[#opts + 1] = { r = r2, c = c2 }
                if d == "e" then opts[#opts + 1] = { r = r2, c = c2 } end
            end
        end
        if #opts == 0 then
            table.remove(stack)
        else
            local nx = opts[rnd(#opts) + 1]
            seen[key(nx.r, nx.c)] = true
            stack[#stack + 1] = nx
        end
    end
    local out = {}
    for c = 1, n do out[c] = { r = sr, c = c } end
    return out
end

local function dirTo(a, b)
    if b.c > a.c then return "e" elseif b.c < a.c then return "w" elseif b.r > a.r then return "s" end
    return "n"
end

local Pipe = G:derive("CMGame_Pipe")
CMGame.KINDS.pipe = Pipe

function Pipe:setup()
    local n = CM.gameVal("pipe", "n", self.tier)
    self.n = n
    self.sr = rnd(n) + 1
    local path = genPath(n, self.sr)
    self.er = path[#path].r
    self.cells = {}
    for r = 1, n do
        self.cells[r] = {}
        for c = 1, n do
            local k = rnd(100)
            local con
            if k < 45 then con = { n = true, s = true }
            elseif k < 90 then con = { n = true, e = true }
            else con = { n = true, e = true, s = true } end
            self.cells[r][c] = con
        end
    end
    for j = 1, #path do
        local p = path[j]
        local con = {}
        con[j == 1 and "w" or dirTo(p, path[j - 1])] = true
        con[j == #path and "e" or dirTo(p, path[j + 1])] = true
        self.cells[p.r][p.c] = con
    end
    self.path = path
    for r = 1, n do
        for c = 1, n do
            for _ = 1, rnd(4) do self.cells[r][c] = rotCW(self.cells[r][c]) end
        end
    end
    self:flow()
    local guard = 0
    while self.solved and guard < 8 do
        guard = guard + 1
        local p = path[rnd(#path) + 1]
        self.cells[p.r][p.c] = rotCW(self.cells[p.r][p.c])
        self:flow()
    end
end

function Pipe:flow()
    local n = self.n
    local wet = {}
    local count = 0
    local start = self.cells[self.sr][1]
    if start.w then
        local q = { { r = self.sr, c = 1 } }
        wet[self.sr * 100 + 1] = true
        local qi = 1
        while qi <= #q do
            local cur = q[qi]
            qi = qi + 1
            count = count + 1
            local con = self.cells[cur.r][cur.c]
            for _, d in ipairs(DIRS) do
                if con[d] then
                    local r2, c2 = cur.r + DY[d], cur.c + DX[d]
                    if r2 >= 1 and r2 <= n and c2 >= 1 and c2 <= n and not wet[r2 * 100 + c2] and self.cells[r2][c2][OPP[d]] then
                        wet[r2 * 100 + c2] = true
                        q[#q + 1] = { r = r2, c = c2 }
                    end
                end
            end
        end
    end
    self.wet = wet
    self.nWet = count
    self.solved = wet[self.er * 100 + n] == true and self.cells[self.er][n].e == true
    return self.solved
end

function Pipe:turn(r, c)
    if self.state ~= "play" then return end
    self.cells[r][c] = rotCW(self.cells[r][c])
    if self:flow() then self:finish(true) end
end

function Pipe:status() return T("IGUI_CM_G_water", self.nWet or 0) end

local DRY = { 0.42, 0.47, 0.56 }

function Pipe:drawGame(x, y, w, h, t)
    local n = self.n
    local cs = math.floor(math.min((w - S(90)) / n, (h - S(20)) / n))
    local ox = math.floor(x + (w - cs * n) / 2)
    local oy = math.floor(y + (h - cs * n) / 2)
    local pt = math.max(S(6), math.floor(cs * 0.24))
    local water = C.accent
    -- inlet and outlet
    local iy = oy + (self.sr - 0.5) * cs
    CMUI.rect(self, x + S(6), iy - pt / 2, ox - x - S(6), pt, water, 1)
    CMUI.glow(self, x + S(14), iy, S(20), S(20), water, 0.6)
    local ey = oy + (self.er - 0.5) * cs
    local exitWet = self.solved
    CMUI.rect(self, ox + cs * n, ey - pt / 2, x + w - S(6) - ox - cs * n, pt, exitWet and water or DRY, 1)
    CMUI.disc(self, x + w - S(14), ey, S(9), exitWet and C.good or C.bad, 1)
    for r = 1, n do
        for c = 1, n do
            local cx, cy = ox + (c - 1) * cs, oy + (r - 1) * cs
            local over = self:hit(cx + 1, cy + 1, cs - 2, cs - 2, function() self:turn(r, c) end)
            CMUI.rbox(self, cx + 2, cy + 2, cs - 4, cs - 4, over and C.panel3 or C.panel, over and 0.9 or 0.7, 6)
            local con = self.cells[r][c]
            local wetC = self.wet and self.wet[r * 100 + c]
            local col = wetC and water or DRY
            local mx, my = cx + cs / 2, cy + cs / 2
            for _, d in ipairs(DIRS) do
                if con[d] then
                    if d == "n" then CMUI.rect(self, mx - pt / 2, cy, pt, cs / 2 + pt / 2, col, 1)
                    elseif d == "s" then CMUI.rect(self, mx - pt / 2, my - pt / 2, pt, cs / 2 + pt / 2, col, 1)
                    elseif d == "w" then CMUI.rect(self, cx, my - pt / 2, cs / 2 + pt / 2, pt, col, 1)
                    else CMUI.rect(self, mx - pt / 2, my - pt / 2, cs / 2 + pt / 2, pt, col, 1) end
                end
            end
            CMUI.disc(self, mx, my, pt * 0.75, col, 1)
            if wetC then CMUI.glow(self, mx, my, cs * 0.4, cs * 0.4, water, 0.18) end
        end
    end
end

-- ===================================================================== board: hit when the needle is in the zone
local Board = G:derive("CMGame_Board")
CMGame.KINDS.board = Board

function Board:setup()
    self.nails = CM.gameVal("board", "nails", self.tier)
    self.period = CM.gameVal("board", "period", self.tier)
    self.zw = CM.gameVal("board", "zone", self.tier)
    self.cur = 1
    self.depth = {}
    for i = 1, self.nails do self.depth[i] = 0 end
    self.tp = 0
    self:newZone()
end

function Board:newZone()
    self.zc = self.zw / 2 + 0.04 + (rnd(1000) / 1000) * (1 - self.zw - 0.08)
end

function Board:needle()
    local f = CM.mod(self.tp / self.period, 2)
    if f <= 1 then return f end
    return 2 - f
end

function Board:tick(dt) self.tp = self.tp + dt end

function Board:status() return T("IGUI_CM_G_nails", self.cur - 1, self.nails) end

function Board:press(mx, my)
    local p = self:needle()
    local d = math.abs(p - self.zc)
    self.hitAt = CMC.ms()
    if d <= self.zw * 0.16 then
        self.depth[self.cur] = self.depth[self.cur] + 2
        self:say(T("IGUI_CM_G_perfect"), C.gold)
        sfx("UIActivateButton")
    elseif d <= self.zw / 2 then
        self.depth[self.cur] = self.depth[self.cur] + 1
        sfx("UISelectListItem")
    else
        self:penalty(2, T("IGUI_CM_G_bent", 2))
        return
    end
    if self.depth[self.cur] >= 2 then
        self.cur = self.cur + 1
        if self.cur > self.nails then self:finish(true); return end
        self.period = self.period * 0.94
        self:newZone()
    end
end

local WOOD = { 0.55, 0.38, 0.22 }
local WOOD_D = { 0.36, 0.24, 0.13 }
local STEEL = { 0.78, 0.82, 0.88 }

function Board:drawGame(x, y, w, h, t)
    -- window frame with the night behind it
    local fx, fy, fw, fh = x + w * 0.12, y + S(16), w * 0.76, h * 0.52
    CMUI.rbox(self, fx, fy, fw, fh, C.ink, 0.95, 6)
    CMUI.rborder(self, fx, fy, fw, fh, C.dim, 0.7, 6)
    CMUI.rect(self, fx + fw / 2 - S(2), fy, S(4), fh, C.faint, 0.8)
    CMUI.rect(self, fx, fy + fh / 2 - S(2), fw, S(4), C.faint, 0.8)
    -- plank across it
    local px, py, pw, ph = x + w * 0.06, fy + fh * 0.36, w * 0.88, fh * 0.30
    CMUI.rect(self, px, py, pw, ph, WOOD, 1)
    CMUI.rect(self, px, py + ph - S(4), pw, S(4), WOOD_D, 1)
    for i = 1, 3 do CMUI.rect(self, px + pw * i / 4, py + S(6), S(2), ph - S(12), WOOD_D, 0.5) end
    -- nails: the head sinks as it is hit
    local hammerX, hammerY = nil, nil
    for i = 1, self.nails do
        local nx = px + pw * (i - 0.5) / self.nails
        local ny = py + ph / 2
        local stick = math.max(0, 2 - self.depth[i]) * S(9)
        if self.depth[i] > 0 or i >= self.cur then
            CMUI.rect(self, nx - S(1), ny - stick, S(3), stick, STEEL, 1)
            CMUI.disc(self, nx, ny - stick, S(6), i < self.cur and C.dim or STEEL, 1)
        end
        if i == self.cur and self.state == "play" then
            CMUI.ring(self, nx, ny - stick, S(14), C.gold, 0.9)
            hammerX, hammerY = nx, ny - stick
        end
    end
    -- the hammer above the current nail, swings down on a hit
    if hammerX then
        local swing = 0
        if self.hitAt and t - self.hitAt < 220 then swing = 1 - (t - self.hitAt) / 220 end
        local hy = hammerY - S(46) + swing * S(30)
        CMUI.line(self, hammerX + S(26), hy - S(36), hammerX + S(4), hy + S(4), S(6), WOOD, 1)
        CMUI.rect(self, hammerX - S(18), hy, S(36), S(14), STEEL, 1)
    end
    -- timing bar
    local bx, bw = x + w * 0.1, w * 0.8
    local by, bh = y + h - S(54), S(26)
    CMUI.rbox(self, bx, by, bw, bh, C.panel, 0.9, 6)
    local zx = bx + bw * (self.zc - self.zw / 2)
    CMUI.rbox(self, zx, by + S(3), bw * self.zw, bh - S(6), C.good, 0.45, 4)
    local pzw = bw * self.zw * 0.32
    CMUI.rbox(self, bx + bw * self.zc - pzw / 2, by + S(3), pzw, bh - S(6), C.gold, 0.85, 3)
    local nxp = bx + bw * self:needle()
    CMUI.rect(self, nxp - S(2), by - S(6), S(4), bh + S(12), C.white, 1)
    CMUI.glow(self, nxp, by + bh / 2, S(14), bh, C.white, 0.4)
    CMUI.rborder(self, bx, by, bw, bh, C.line, 0.6, 6)
end

-- ===================================================================== trap: watch the code, type it back
local Trap = G:derive("CMGame_Trap")
CMGame.KINDS.trap = Trap

function Trap:setup()
    self.len = CM.gameVal("trap", "len", self.tier)
    self.lives = CM.gameVal("trap", "lives", self.tier)
    self.showSec = CM.gameVal("trap", "show", self.tier)
    self.seq = {}
    for i = 1, self.len do
        local k = rnd(9) + 1
        if i > 1 and k == self.seq[i - 1] then k = rnd(9) + 1 end
        self.seq[i] = k
    end
    self.L = math.min(3, self.len)
    self:startShow(0.8)
end

function Trap:startShow(delay)
    self.phase = "show"
    self.showT = -(delay or 0.6)
    self.pos = 1
    self.lit = nil
end

function Trap:tick(dt, t)
    if self.phase ~= "show" then return end
    self.showT = self.showT + dt
    local step = self.showSec + 0.18
    if self.showT < 0 then self.lit = nil; return end
    local idx = math.floor(self.showT / step) + 1
    if idx > self.L then
        self.phase = "input"
        self.pos = 1
        self.lit = nil
        return
    end
    local within = self.showT - (idx - 1) * step
    local k = within < self.showSec and self.seq[idx] or nil
    if k and k ~= self.lit then sfx("UISelectListItem") end
    self.lit = k
end

function Trap:key(k)
    if self.state ~= "play" or self.phase ~= "input" then return end
    self.flashK = k
    self.flashAt = CMC.ms()
    if self.seq[self.pos] == k then
        self.pos = self.pos + 1
        if self.pos > self.L then
            if self.L >= self.len then self:finish(true); return end
            self.L = self.L + 1
            self:say(T("IGUI_CM_G_good"), C.good)
            self:startShow(0.9)
        end
    else
        self.lives = self.lives - 1
        if self.lives <= 0 then
            self:finish(false, "boom")
            return
        end
        self:penalty(0, T("IGUI_CM_G_wrong", self.lives))
        self:startShow(1.1)
    end
end

function Trap:status()
    local ph = self.phase == "show" and T("IGUI_CM_G_watch") or T("IGUI_CM_G_yourturn")
    return T("IGUI_CM_G_round", self.L - 2, self.len - 2) .. "     " .. T("IGUI_CM_G_lives", self.lives) .. "     " .. ph
end

local KEY_COL = { 0.95, 0.30, 0.35 }

function Trap:drawGame(x, y, w, h, t)
    -- the device: a charge on the left, the keypad on the right
    local dx, dy, dw, dh = x + S(18), y + S(18), w * 0.34, h - S(36)
    for i = 0, 2 do
        CMUI.rbox(self, dx + i * dw / 3 + S(3), dy + S(20), dw / 3 - S(6), dh - S(40), { 0.62, 0.16, 0.14 }, 1, 6)
    end
    CMUI.rect(self, dx - S(4), dy + dh * 0.35, dw + S(8), S(8), C.ink, 1)
    CMUI.rect(self, dx - S(4), dy + dh * 0.65, dw + S(8), S(8), C.ink, 1)
    local blink = CM.mod(math.floor(t / 400), 2) == 0
    CMUI.disc(self, dx + dw / 2, dy + S(8), S(7), blink and C.bad or { 0.3, 0.05, 0.08 }, 1)
    if blink then CMUI.glow(self, dx + dw / 2, dy + S(8), S(22), S(22), C.bad, 0.6) end
    -- display
    local kx = x + w * 0.44
    local kw = w * 0.52
    CMUI.rbox(self, kx, y + S(14), kw, S(34), C.ink, 1, 6)
    local shown = ""
    if self.phase == "input" then
        for i = 1, self.L do shown = shown .. (i < self.pos and "*" or "_") .. " " end
    else
        shown = T("IGUI_CM_G_watch")
    end
    CMUI.textC(self, shown, kx + kw / 2, y + S(14) + (S(34) - CMUI.fh(UIFont.Medium)) / 2, C.bad, 1, UIFont.Medium)
    -- 3 x 3 keypad
    local top = y + S(60)
    local bs = math.floor(math.min((kw - S(24)) / 3, (y + h - top - S(16)) / 3))
    local ox = kx + (kw - bs * 3) / 2
    for k = 1, 9 do
        local r, c = math.floor((k - 1) / 3), CM.mod(k - 1, 3)
        local bx, by = ox + c * bs + S(4), top + r * bs + S(4)
        local b = bs - S(8)
        local lit = (self.lit == k) or (self.flashK == k and self.flashAt and t - self.flashAt < 180)
        local over = self:hit(bx, by, b, b, function() self:key(k) end)
        local col = lit and KEY_COL or (over and self.phase == "input" and C.panel3 or C.panel2)
        if lit then CMUI.glow(self, bx + b / 2, by + b / 2, b, b, KEY_COL, 0.7) end
        CMUI.rbox(self, bx, by, b, b, col, lit and 1 or 0.85, 8)
        CMUI.rborder(self, bx, by, b, b, lit and C.white or C.line, lit and 0.9 or 0.45, 8)
        CMUI.textC(self, tostring(k), bx + b / 2, by + (b - CMUI.fh(UIFont.Large)) / 2, lit and C.white or C.text, 1, UIFont.Large)
    end
end

-- ===================================================================== open
-- cb(won, why, window); why = ok | time | picks | boom | far | cancel
function CMGame.open(kind, tier, ctx, cb)
    if CMGame.cur then pcall(function() CMGame.cur:drop() end) end
    local cls = CMGame.KINDS[kind]
    if not cls then return nil end
    local g = cls:new(kind, tier, ctx)
    g.cb = cb
    if g.setup then g:setup() end
    g:show()
    pcall(function() g:setAlwaysOnTop(true) end)
    CMGame.cur = g
    return g
end

return CMGame
