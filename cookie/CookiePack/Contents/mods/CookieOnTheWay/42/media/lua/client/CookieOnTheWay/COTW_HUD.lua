-- Cookie On the Way : on-screen strip (top centre) + bill / group invite popups
-- Navigator: an arrow relative to where the car (or player) faces, the next turn and the distance
-- left; re-routes when 25 tiles off the line, ends 15 tiles from the pin.
-- Autopilot: distance left, target speed and why it is slower, the hold-to-take-over bar and the
-- "stop here" button. The last trip's summary stays for 10 s.

require "CookieOnTheWay/COTW_Driver"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"

COTWHud = ISPanel:derive("COTWHud")

local FONT_S = getTextManager():getFontHeight(UIFont.Small)
local FONT_M = getTextManager():getFontHeight(UIFont.Medium)
local W, H = 360, FONT_M + FONT_S * 2 + 22
local REROUTE = 25
local NAV_DONE = 15
local TURN_ANGLE = 0.6       -- rad: smaller bends are "keep going"
local SUMMARY_MS = 10000

local function T(key, ...) return getText(key, ...) end

local function wrap(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

-- ------------------------------------------------------------------------------
-- navigator maths
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

-- next real turn after segment k: distance to it and "left" / "right"
local function nextTurn(nav, pos, k)
    local r, cum = nav.route, navCum(nav)
    for i = k + 1, #r.x - 1 do
        local a = math.atan2(r.y[i] - r.y[i - 1], r.x[i] - r.x[i - 1])
        local b = math.atan2(r.y[i + 1] - r.y[i], r.x[i + 1] - r.x[i])
        local d = wrap(b - a)
        if math.abs(d) > TURN_ANGLE then
            return cum[i] - pos, d > 0 and "right" or "left"
        end
    end
    return nil
end

local function facing(p)
    local v = p:getVehicle()
    if v then
        local f = v:getForwardVector(Vector3f.new())
        return math.atan2(f:z(), f:x())
    end
    local dir = p:getForwardDirection()
    return math.atan2(dir:getY(), dir:getX())
end

-- ------------------------------------------------------------------------------
-- panel
-- ------------------------------------------------------------------------------
function COTWHud:new()
    local o = ISPanel.new(self, getCore():getScreenWidth() / 2 - W / 2, 20, W, H)
    o.backgroundColor = { r = 0.08, g = 0.07, b = 0.06, a = 0.85 }
    o.borderColor = { r = 0.85, g = 0.6, b = 0.25, a = 1 }
    o.lastReroute = 0
    return o
end

function COTWHud:createChildren()
    ISPanel.createChildren(self)
    self.stopBtn = ISButton:new(self.width - 98, self.height - 30, 90, 24, T("IGUI_COTW_StopHere"), self, COTWHud.onStop)
    self.stopBtn:initialise()
    self:addChild(self.stopBtn)
end

function COTWHud:onStop()
    if COTW.Driver.running() then COTW.Driver.emergency() else COTW.stopNav() end
end

function COTWHud:arrow(cx, cy, ang, size)
    -- ang 0 = straight up on screen (= where we face)
    local s, c = math.sin(ang), math.cos(ang)
    local function pt(x, y) return cx + x * c - y * s, cy + x * s + y * c end
    local tx, ty = pt(0, -size)
    local rx, ry = pt(size * 0.6, size * 0.7)
    local mx, my = pt(0, size * 0.3)
    local lx, ly = pt(-size * 0.6, size * 0.7)
    self.javaObject:DrawTexture(nil, tx, ty, rx, ry, mx, my, lx, ly, 1, 0.8, 0.35, 1)
end

-- hidden (and not catching clicks) whenever there is nothing to show
local function wanted()
    local C = COTW.C
    if not COTW.player() then return false end
    return COTW.Driver.running() or C.nav ~= nil or (C.trip ~= nil and C.trip.state ~= "driving") or C.riding ~= nil
        or (C.lastEnd ~= nil and getTimestampMs() - C.lastEnd.t < SUMMARY_MS)
end

function COTWHud:render()
    local C = COTW.C
    local p = COTW.player()
    if not p then return end
    local st = COTW.Driver.status()
    local now = getTimestampMs()
    self.stopBtn:setVisible(false)

    if st then
        self.stopBtn:setVisible(not st.emergency)
        self.stopBtn:setTitle(T("IGUI_COTW_StopHere"))
        self:drawText(T("IGUI_COTW_Hud_Auto", string.format("%.1f", st.rem / 1000)), 10, 6, 1, 0.8, 0.4, 1, UIFont.Medium)
        local why = st.why and T("IGUI_COTW_Why_" .. st.why) or ""
        self:drawText(T("IGUI_COTW_Hud_Speed", tostring(math.floor(st.target))) .. "  " .. why, 10, 8 + FONT_M, 1, 1, 1, 1, UIFont.Small)
        self:drawText(T("IGUI_COTW_Hud_Hold"), 10, 10 + FONT_M + FONT_S, 0.7, 0.7, 0.7, 1, UIFont.Small)
        if st.hold > 0 then
            self:drawRect(10, self.height - 6, (self.width - 20) * math.min(1, st.hold), 3, 1, 0.9, 0.3, 0.2)
        end
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
        -- arrow toward a point a little ahead on the route (or the pin itself near the end)
        local r = nav.route
        local ax, ay = nav.destX, nav.destY
        local ahead = pos + 12
        for i = k + 1, #r.x do
            if cum[i] >= ahead then ax, ay = r.x[i], r.y[i]; break end
        end
        local ang = wrap(math.atan2(ay - p:getY(), ax - p:getX()) - facing(p))
        self:arrow(30, self.height / 2, ang, 16)
        local dist, side = nextTurn(nav, pos, k)
        local text = dist and T("IGUI_COTW_Turn_" .. side, tostring(math.floor(dist))) or T("IGUI_COTW_Straight")
        self:drawText(text, 60, 6, 1, 1, 1, 1, UIFont.Medium)
        self:drawText(T("IGUI_COTW_Hud_Left", string.format("%.1f", rem / 1000)), 60, 8 + FONT_M, 0.8, 0.8, 0.8, 1, UIFont.Small)
        self.stopBtn:setVisible(true)
        self.stopBtn:setTitle(T("IGUI_COTW_NavStop"))
        return
    end

    if C.trip then
        self:drawText(T("IGUI_COTW_State_" .. C.trip.state), 10, 6, 1, 0.8, 0.4, 1, UIFont.Medium)
        return
    end
    if C.riding then
        self:drawText(T("IGUI_COTW_Riding", C.riding.booker), 10, 6, 1, 0.8, 0.4, 1, UIFont.Medium)
        return
    end
    local e = C.lastEnd
    if e and now - e.t < SUMMARY_MS then
        self:drawText(T("IGUI_COTW_End_" .. tostring(e.reason)), 10, 6, 1, 0.8, 0.4, 1, UIFont.Medium)
        local money = e.free and T("IGUI_COTW_Free") or T("IGUI_COTW_End_Money", COTW.money(e.paid or 0), COTW.money(e.back or 0))
        self:drawText(T("IGUI_COTW_End_Dist", string.format("%.1f", (e.driven or 0) / 1000), string.format("%.1f", (e.len or 0) / 1000)) .. "  " .. money,
            10, 8 + FONT_M, 1, 1, 1, 1, UIFont.Small)
    end
end

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
