-- Cookie On the Way : on-screen strip (top centre) + bill / group invite popups
-- UI v2 look (COTW_UI): the next turn in a hexagon, distance left, a speed gauge, progress bars, why
-- the car is slower (amber) and a red "stop here" / "stop navigating" button.
-- Navigator: re-routes when 25 tiles off the line, ends 15 tiles from the pin.
-- Autopilot: same strip from the autopilot's own lane line, plus the hold-to-take-over bar. Booked
-- trips, riding and the last trip's summary (10 s) show as a short strip.

require "CookieOnTheWay/COTW_Driver"
require "CookieOnTheWay/COTW_UI"
require "ISUI/ISPanel"
require "ISUI/ISModalDialog"

COTWHud = ISPanel:derive("COTWHud")

local U = COTW.UI
local K = U.C
local W = 390
local CUT = 14
local REROUTE = 25
local NAV_DONE = 15
local TURN_ANGLE = 0.6       -- rad: smaller bends are "keep going"
local TURN_SHOW = 300        -- tiles: a turn further than this shows as "straight on"
local SUMMARY_MS = 10000
local WHY_ICON = { zombie = "zombie", obstacle = "warn", avoid = "swerve", group = "convoy", unloaded = "clock", offroute = "pin", emergency = "stop" }

local function T(key, ...) return getText(key, ...) end

local function wrap(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

-- ------------------------------------------------------------------------------
-- route maths
-- ------------------------------------------------------------------------------
local function navCum(nav)
    if nav.cum then return nav.cum end
    local r = nav.route
    local cum = { 0 }
    for i = 2, #r.x do cum[i] = cum[i - 1] + COTW.dist(r.x[i - 1], r.y[i - 1], r.x[i], r.y[i]) end
    nav.cum = cum
    return cum
end

local function navLocate(nav, px, py)
    local r, cum = nav.route, navCum(nav)
    local idx = COTW.C.navIdx or 1
    local best, bpos, bk = nil, 0, idx
    for k = math.max(1, idx - 2), math.min(#r.x - 1, idx + 25) do
        local x1, y1, x2, y2 = r.x[k], r.y[k], r.x[k + 1], r.y[k + 1]
        local vx, vy = x2 - x1, y2 - y1
        local L2 = vx * vx + vy * vy
        local t = L2 > 0 and math.max(0, math.min(1, ((px - x1) * vx + (py - y1) * vy) / L2)) or 0
        local d = COTW.dist(px, py, x1 + vx * t, y1 + vy * t)
        if not best or d < best then best, bk, bpos = d, k, cum[k] + t * math.sqrt(L2) end
    end
    COTW.C.navIdx = bk
    return bpos, best or 0, bk
end

-- next real turn after segment k of xs/ys: distance to it and "left" / "right"
local function nextTurn(xs, ys, cum, pos, k)
    for i = k + 1, #xs - 1 do
        if cum[i] - pos > TURN_SHOW then return nil end
        local a = math.atan2(ys[i] - ys[i - 1], xs[i] - xs[i - 1])
        local b = math.atan2(ys[i + 1] - ys[i], xs[i + 1] - xs[i])
        local d = wrap(b - a)
        if math.abs(d) > TURN_ANGLE then
            return cum[i] - pos, d > 0 and "right" or "left"
        end
    end
    return nil
end

local function speedOf(p)
    local v = p:getVehicle()
    return v and math.abs(v:getCurrentSpeedKmHour()) or 0
end

-- ------------------------------------------------------------------------------
-- panel
-- ------------------------------------------------------------------------------
function COTWHud:new()
    local o = ISPanel.new(self, getCore():getScreenWidth() / 2 - W / 2, 20, W, 130)
    o.background = false
    o.lastReroute = 0
    return o
end

function COTWHud:createChildren()
    ISPanel.createChildren(self)
    self.stopBtn = COTWBtn:new(0, 0, 10, U.FONT_S + 10, T("IGUI_COTW_StopHere"), self, COTWHud.onStop, "stop", "stop")
    self.stopBtn:initialise()
    self:addChild(self.stopBtn)
end

function COTWHud:onStop()
    if COTW.Driver.running() then COTW.Driver.emergency() else COTW.stopNav() end
end

-- hidden (and not catching clicks) whenever there is nothing to show
local function wanted()
    local C = COTW.C
    if not COTW.player() then return false end
    return COTW.Driver.running() or C.nav ~= nil or (C.trip ~= nil and C.trip.state ~= "driving") or C.riding ~= nil
        or (C.lastEnd ~= nil and getTimestampMs() - C.lastEnd.t < SUMMARY_MS)
end

-- the full strip: turn, distance, gauge, progress, why, stop button
-- d = { turnDist, turnSide, mode, rem, why, speed, done (0..1), hint, stopTitle, hold }
function COTWHud:drawDrive(d)
    local w = self.width
    local sw = d.stopTitle and (U.textW(d.stopTitle) + 16 + 24) or 0
    local hint = d.hint and U.wrap(d.hint, w - 28 - sw - 10) or {}
    local footH = math.max(U.FONT_S + 10, #hint * U.FONT_S + 4)
    local h = 10 + 58 + 10 + 6 + 8 + footH + 14
    if self.height ~= h then self:setHeight(h) end
    U.stripFrame(self, w, h, CUT)

    -- turn hexagon
    local icon = d.turnSide == "left" and "turnL" or (d.turnSide == "right" and "turnR" or "up")
    for i = 3, 1, -1 do U.hex(self, 14 - i * 2, 13 - i * 2, 52 + i * 4, 52 + i * 4, K.g, 0.1) end
    U.hex(self, 14, 13, 52, 52, K.g, 1)
    U.icon(self, icon, 26, 25, 28, K.dark)

    -- turn, then mode + distance left, then why it is slower (amber)
    local tx = 80
    local big = d.turnSide and T("IGUI_COTW_Turn_" .. d.turnSide, tostring(math.floor(d.turnDist))) or T("IGUI_COTW_Straight")
    U.text(self, big, tx, 10, K.ink, UIFont.Medium)
    local sy = 12 + U.FONT_M
    U.text(self, d.mode, tx, sy, K.mute)
    local x = tx + U.textW(d.mode) + 10
    U.icon(self, "road", x, sy + (U.FONT_S - 14) / 2, 14, K.g)
    U.text(self, T("IGUI_COTW_Hud_Left", string.format("%.1f", d.rem / 1000)), x + 18, sy, K.mute)
    if d.why then
        sy = sy + U.FONT_S
        U.icon(self, WHY_ICON[d.why] or "warn", tx, sy + (U.FONT_S - 14) / 2, 14, K.amber)
        U.text(self, T("IGUI_COTW_Why_" .. d.why), tx + 18, sy, K.amber)
    end

    -- speed gauge (270 degrees open at the bottom, MaxSpeed = full)
    local gx, gy, r = w - 14 - 29, 10 + 29, 25
    local a0 = math.pi * 0.75
    U.arc(self, gx, gy, r, 5, a0, a0 + math.pi * 1.5, K.white, 0.08, 24)
    local f = math.max(0, math.min(1, d.speed / math.max(1, COTW.opt("MaxSpeed"))))
    if f > 0.005 then
        U.arc(self, gx, gy, r, 9, a0, a0 + math.pi * 1.5 * f, K.g, 0.18)
        U.arc(self, gx, gy, r, 5, a0, a0 + math.pi * 1.5 * f, K.g, 1)
    end
    U.textC(self, tostring(math.floor(d.speed + 0.5)), gx, gy - U.FONT_M / 2 - 5, K.ink, UIFont.Medium)
    U.textC(self, "km/h", gx, gy + 8, K.mute)

    -- progress: 10 slanted bars
    local by = 10 + 58 + 10
    local bw = (w - 28 - 27) / 10
    local on = math.floor(math.max(0, math.min(1, d.done)) * 10 + 0.5)
    for i = 0, 9 do
        local bx = 14 + i * (bw + 3)
        local lit = i < on
        if lit then U.quad(self, bx + 3, by - 2, bx + bw + 3, by - 2, bx + bw - 1, by + 8, bx - 1, by + 8, K.g, 0.25) end
        U.quad(self, bx + 3, by, bx + bw + 3, by, bx + bw, by + 6, bx, by + 6, lit and K.g or K.white, lit and 1 or 0.07)
    end

    -- foot: hint + stop button
    local fy = by + 6 + 8
    local sb = self.stopBtn
    sb:setTitle(d.stopTitle or "")
    sb:setX(w - 14 - sw)
    sb:setY(fy + (footH - U.FONT_S - 10) / 2)
    sb:setWidth(sw)
    sb:setHeight(U.FONT_S + 10)
    sb:setVisible(d.stopTitle ~= nil and not d.stopping)
    for i, ln in ipairs(hint) do U.text(self, ln, 14, fy + (footH - #hint * U.FONT_S) / 2 + (i - 1) * U.FONT_S, K.mute) end
    if d.hold and d.hold > 0 then
        U.rect(self, 14, h - 10, w - 28, 3, K.red, 0.13)
        U.rect(self, 14, h - 11, (w - 28) * math.min(1, d.hold), 5, K.red, 0.25)
        U.rect(self, 14, h - 10, (w - 28) * math.min(1, d.hold), 3, K.red, 1)
    end
end

-- the short strip: icon, title, a line under it
function COTWHud:drawInfo(icon, title, sub, warn)
    local w = self.width
    local h = 10 + math.max(40, U.FONT_M + U.FONT_S + 4) + 14
    if self.height ~= h then self:setHeight(h) end
    self.stopBtn:setVisible(false)
    U.stripFrame(self, w, h, CUT)
    local col = warn and K.amber or K.g
    U.hex(self, 14, 10, 40, 40, col, 1)
    U.icon(self, icon, 24, 20, 20, K.dark)
    U.text(self, title, 66, 10, warn and K.amber or K.ink, UIFont.Medium)
    if sub then U.text(self, sub, 66, 12 + U.FONT_M, K.mute) end
end

function COTWHud:prerender()
    local C = COTW.C
    local p = COTW.player()
    if not p then return end
    local st = COTW.Driver.status()
    local now = getTimestampMs()

    if st then
        local R = st.R
        local dist, side = nextTurn(R.x, R.y, R.cum, st.pos, st.idx)
        self:drawDrive({
            turnDist = dist, turnSide = side, mode = T("IGUI_COTW_Mode_auto"), rem = st.rem, why = st.why,
            speed = speedOf(p), done = st.len > 0 and st.pos / st.len or 0, hint = T("IGUI_COTW_Hud_Hold"),
            stopTitle = T("IGUI_COTW_StopHere"), stopping = st.emergency, hold = st.hold,
        })
        return
    end

    if C.nav then
        local nav = C.nav
        local pos, off, k = navLocate(nav, p:getX(), p:getY())
        local cum = navCum(nav)
        local rem = cum[#cum] - pos + COTW.dist(nav.route.x[#nav.route.x], nav.route.y[#nav.route.y], nav.destX, nav.destY)
        if COTW.dist(p:getX(), p:getY(), nav.destX, nav.destY) < NAV_DONE then
            COTW.say("IGUI_COTW_NavDone")
            COTW.stopNav()
            return
        end
        if off > REROUTE and now - self.lastReroute > 3000 then
            self.lastReroute = now
            COTW.startNav(nav.destX, nav.destY)
            C.navIdx = 1
            return
        end
        local dist, side = nextTurn(nav.route.x, nav.route.y, cum, pos, k)
        local total = cum[#cum]
        self:drawDrive({
            turnDist = dist, turnSide = side, mode = T("IGUI_COTW_Mode_nav"), rem = rem,
            speed = speedOf(p), done = total > 0 and pos / total or 0, stopTitle = T("IGUI_COTW_NavStop"),
        })
        return
    end

    if C.trip then
        local d = C.dest
        self:drawInfo("clock", T("IGUI_COTW_State_" .. C.trip.state), d and d.name or nil)
        return
    end
    if C.riding then
        self:drawInfo("car", T("IGUI_COTW_Riding", C.riding.booker), nil)
        return
    end
    local e = C.lastEnd
    if e and now - e.t < SUMMARY_MS then
        local good = e.reason == "arrive" or e.reason == "intervene" or e.reason == "emergency"
        local money = e.free and T("IGUI_COTW_Free") or T("IGUI_COTW_End_Money", COTW.money(e.paid or 0), COTW.money(e.back or 0))
        local sub = T("IGUI_COTW_End_Dist", string.format("%.1f", (e.driven or 0) / 1000), string.format("%.1f", (e.len or 0) / 1000)) .. " · " .. money
        self:drawInfo(good and "check" or "warn", T("IGUI_COTW_End_" .. tostring(e.reason)), sub, not good)
    end
end

function COTWHud:render() end

-- ------------------------------------------------------------------------------
-- bill / invite popups
-- ------------------------------------------------------------------------------
COTWBill = {}

local function onBill(_, button, id)
    if button.internal == "YES" then COTW.send("payBill", { id = id }) end
end

function COTWBill.show(args)
    local text = T("IGUI_COTW_BillAsk", args.booker, COTW.money(args.amount), tostring(args.secs))
    local box = ISModalDialog:new(getCore():getScreenWidth() / 2 - 200, getCore():getScreenHeight() / 2 - 90, 400, 160, text, true, nil, onBill, 0, args.id)
    box:initialise()
    box:addToUIManager()
end

local function onInvite(_, button, args)
    if button.internal ~= "YES" then return end
    COTW.setDest(args.x, args.y, T("IGUI_COTW_GroupOf", args.leader))
    local panel = COTWPanel.open()
    panel.gid = args.gid
    panel:layout()
end

function COTWBill.invite(args)
    local text = T("IGUI_COTW_InviteAsk", args.leader)
    local box = ISModalDialog:new(getCore():getScreenWidth() / 2 - 200, getCore():getScreenHeight() / 2 - 90, 400, 160, text, true, nil, onInvite, 0, args)
    box:initialise()
    box:addToUIManager()
end

local function onGameStart()
    local hud = COTWHud:new()
    hud:initialise()
    hud:addToUIManager()
    hud:setVisible(false)
    COTWHud.instance = hud
end

local function onTick()
    local hud = COTWHud.instance
    if not hud then return end
    local want = wanted()
    if want ~= hud:isVisible() then hud:setVisible(want) end
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
