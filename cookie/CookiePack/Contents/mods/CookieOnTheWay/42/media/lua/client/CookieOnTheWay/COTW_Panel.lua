-- Cookie On the Way : the booking window (vehicle radial menu "Cookie On the Way")
-- Three steps in the UI v2 look (COTW_UI): 1 where to (map / My Home / My Pin 1-5), 2 the fare the
-- server quotes (trip, trailer, each rider with "I pay" / "send bill" and the baby seat), Group Trip,
-- then Autopilot (after a consent box) or navigate for free, 3 a booked trip waiting to leave.
-- The small map draws the route the server quoted (before a quote: the one the client finds with the
-- navigator's graph); prices only ever come from the server. Admins also get Scan vehicle and Record
-- road here.

require "CookieOnTheWay/COTW_Client"
require "CookieOnTheWay/COTW_UI"
require "ISUI/ISPanel"
require "ISUI/ISModalDialog"
require "Vehicles/ISUI/ISVehicleMenu"

COTWPanel = ISPanel:derive("COTWPanel")

local U = COTW.UI
local K = U.C
local W = 400
local PAD = 14
local CUT = 14
local BTN = math.max(U.FONT_S + 14, 30)
local MAIN = math.max(U.FONT_M + 18, 46)
local TILE = 22 + U.FONT_S + 22
local REQUOTE_MS = 5000

local function T(key, ...) return getText(key, ...) end

-- text cut to fit maxW px (with an ellipsis)
local function fit(text, maxW, font)
    if U.textW(text, font) <= maxW then return text end
    local n = string.len(text)
    while n > 1 and U.textW(string.sub(text, 1, n) .. "...", font) > maxW do n = n - 1 end
    return string.sub(text, 1, n) .. "..."
end

function COTWPanel.open()
    if COTWPanel.instance then
        COTWPanel.instance:setVisible(true)
        COTWPanel.instance:refresh()
        return COTWPanel.instance
    end
    local o = COTWPanel:new(getCore():getScreenWidth() / 2 - W / 2, 120, W, 420)
    o:initialise()
    o:addToUIManager()
    COTWPanel.instance = o
    o:refresh()
    return o
end

function COTWPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.moveWithMouse = true
    o.background = false
    o.bill = {}          -- rider name -> true: send them a bill
    o.baby = nil         -- rider name in the baby seat
    o.group = false
    o.gid = nil          -- joining someone's group trip
    o.riderBtns = {}
    o.lastQuote = 0
    o.L = {}
    return o
end

function COTWPanel:createChildren()
    ISPanel.createChildren(self)
    self.btns = {}
    local function B(title, fn, style, icon)
        local b = COTWBtn:new(0, 0, 10, BTN, title, self, fn, style, icon)
        b:initialise()
        self:addChild(b)
        self.btns[#self.btns + 1] = b
        return b
    end
    self.closeBtn = B("", COTWPanel.close, "x")
    self.changeBtn = B(T("IGUI_COTW_ChangeDest"), COTWPanel.onChangeDest, "link")
    self.mapBox = B("", COTWPanel.onPickMap, "none")
    self.mapBtn = B(T("IGUI_COTW_PickMap"), COTWPanel.onPickMap, "main", "map")
    self.homeBtn = B(T("IGUI_COTW_Home"), COTWPanel.onHome, "home", "home")
    self.pinBtns = {}
    for i = 1, COTW.PINS do
        local b = B(tostring(i), COTWPanel.onPin, "tile", "pin")
        b.pinIndex = i
        self.pinBtns[i] = b
    end
    self.groupBtn = B("", COTWPanel.onGroup, "switch")
    self.goBtn = B(T("IGUI_COTW_CallAuto"), COTWPanel.onAutopilot, "main", "car")
    self.navBtn = B(T("IGUI_COTW_NavFree"), COTWPanel.onNav, "ghost", "nav")
    self.cancelBtn = B(T("IGUI_COTW_CancelTrip"), COTWPanel.onCancel, "ghost", "x")
    self.startBtn = B(T("IGUI_COTW_GroupStart"), COTWPanel.onGroupStart, "main", "convoy")
    self.scanBtn = B(T("IGUI_COTW_Scan"), COTWPanel.onScan, "admin", "scan")
    self.recBtn = B("", COTWPanel.onRecord, "admin", "rec")
end

-- ------------------------------------------------------------------------------
-- actions
-- ------------------------------------------------------------------------------
function COTWPanel:close()
    self:setVisible(false)
    self:removeFromUIManager()
    COTWPanel.instance = nil
end

function COTWPanel:onPickMap() COTW.Map.pick() end

function COTWPanel:onChangeDest() COTW.clearDest() end

function COTWPanel:onHome()
    local h = COTW.C.home
    if not h then COTW.say("IGUI_COTW_NoHome"); return end
    COTW.setDest(h.x, h.y, T("IGUI_COTW_Home"))
end

function COTWPanel:onPin(b)
    local pin = COTW.C.pins[b.pinIndex]
    if not pin then COTW.say("IGUI_COTW_NoPin"); return end
    COTW.setDest(pin.x, pin.y, pin.n)
end

function COTWPanel:onGroup() self.group = not self.group; self:layout() end

function COTWPanel:requote()
    local d = COTW.C.dest
    if not d or not COTW.driving() then return end
    self.lastQuote = getTimestampMs()
    COTW.send("quote", { x = d.x, y = d.y, baby = self.baby })
end

function COTWPanel:refresh()
    self:requote()
    self:layout()
end

function COTWPanel:onRider(b)
    local name = b.riderName
    if b.kind == "bill" then
        self.bill[name] = true
    elseif b.kind == "pay" then
        self.bill[name] = nil
    else
        self.baby = self.baby ~= name and name or nil
        self:requote()
    end
    self:layout()
end

-- what the booker's wallet holds now: trip + trailer + every rider not sent a bill (as the server does)
function COTWPanel:mine(q)
    local m = q.base + q.trailerFee
    for _, r in ipairs(q.riders or {}) do if not self.bill[r.name] then m = m + r.fare end end
    return m
end

local function onConsent(self, button)
    if button.internal ~= "YES" then return end
    local d = COTW.C.dest
    if not d then return end
    COTW.send("book", { x = d.x, y = d.y, baby = self.baby, bill = self.bill, group = self.group and not self.gid, gid = self.gid })
end

function COTWPanel:onAutopilot()
    local q = COTW.C.quote
    if not q or q.err or not COTW.C.dest then return end
    local text = T("IGUI_COTW_Consent", q.free and T("IGUI_COTW_Free") or COTW.money(self:mine(q)))
    local box = ISModalDialog:new(getCore():getScreenWidth() / 2 - 200, getCore():getScreenHeight() / 2 - 90, 400, 180, text, true, self, onConsent)
    box:initialise()
    box:addToUIManager()
end

function COTWPanel:onNav()
    local d = COTW.C.dest
    if d and COTW.startNav(d.x, d.y) then self:close() end
end

function COTWPanel:onCancel() COTW.send("cancel") end

function COTWPanel:onGroupStart()
    local t = COTW.C.trip
    if t and t.gid then COTW.send("groupStart", { gid = t.gid }) end
end

function COTWPanel:onScan() COTW.Admin.scan() end

function COTWPanel:onRecord() COTW.Admin.recordToggle(); self:layout() end

-- ------------------------------------------------------------------------------
-- layout (what shows depends on the step and the quote; buttons move with the riders)
-- ------------------------------------------------------------------------------
function COTWPanel:step()
    if COTW.C.trip then return 3 end
    if COTW.C.dest then return 2 end
    return 1
end

local function place(b, x, y, w, h)
    b:setX(x)
    b:setY(y)
    b:setWidth(w)
    b:setHeight(h)
    b:setVisible(true)
end

-- the road route for the small map: the one the server quoted, else found here once per destination
function COTWPanel:mapRoute()
    local C = COTW.C
    if C.trip and C.trip.route then return C.trip.route end
    if C.quote and C.quote.route then return C.quote.route end
    local d = C.dest
    if not d then return nil end
    local key = d.x .. "," .. d.y
    if self.routeKey ~= key then
        self.routeKey = key
        self.route = nil
        local p = COTW.player()
        if p then
            local ok, r = pcall(COTW.Graph.route, p:getX(), p:getY(), d.x, d.y)
            if ok then self.route = r end
        end
    end
    return self.route
end

function COTWPanel:layout()
    local C = COTW.C
    local w = self.width
    local inner = w - PAD * 2
    local step = self:step()
    local q = C.quote
    local L = { step = step }
    self.L = L
    for _, b in ipairs(self.btns) do b:setVisible(false) end
    for _, b in ipairs(self.riderBtns) do self:removeChild(b) end
    self.riderBtns = {}
    local function riderBtn(title, kind, name, style, x, y, bw, bh)
        local b = COTWBtn:new(x, y, bw, bh, title, self, COTWPanel.onRider, style)
        b:initialise()
        b.riderName, b.kind = name, kind
        self:addChild(b)
        self.riderBtns[#self.riderBtns + 1] = b
        return b
    end

    L.headH = math.max(38, U.FONT_M + U.FONT_S + 2) + 22
    place(self.closeBtn, w - PAD - 26, 14, 26, 26)
    if step == 2 then
        place(self.changeBtn, 66, 12 + U.FONT_M, U.textW(self.changeBtn.title) + 4, U.FONT_S + 2)
    end
    local y = L.headH + 10
    L.stepsY, L.stepsH = y, U.FONT_S + 10
    y = y + L.stepsH + 12

    if step == 1 then
        L.map = { y = y, h = 118 }
        place(self.mapBox, PAD, y, inner, 118)
        y = y + 118 + 10
        place(self.mapBtn, PAD, y, inner, MAIN)
        y = y + MAIN + 10
        L.quickY = y
        y = y + U.FONT_S + 6
        local tw = (inner - 12) / 3
        place(self.homeBtn, PAD, y, tw, TILE)
        self.homeBtn.style = C.home and "home" or "tileOff"
        for i = 1, COTW.PINS do
            local b = self.pinBtns[i]
            local col, row = i % 3, math.floor(i / 3)
            place(b, PAD + col * (tw + 6), y + row * (TILE + 6), tw, TILE)
            local pin = C.pins[i]
            b.style = pin and "tile" or "tileOff"
            b:setTitle(pin and fit(i .. " · " .. tostring(pin.n or ""), tw - 8) or T("IGUI_COTW_EmptyPin", tostring(i)))
        end
        y = y + 2 * TILE + 6
    else
        L.map = { y = y, h = 84 }
        y = y + 84 + 8
        -- chips: distance, time, warnings (wrapped)
        local chips = {}
        if q and q.err then
            chips[1] = { icon = "warn", text = T("IGUI_COTW_Err_" .. q.err), warn = true }
        elseif q and q.len then
            local km = q.len / 1000
            local mins = math.ceil(km / (COTW.opt("CitySpeed") * 0.8) * 60)
            chips[#chips + 1] = { icon = "road", text = T("IGUI_COTW_Km", string.format("%.1f", km)) }
            chips[#chips + 1] = { icon = "clock", text = T("IGUI_COTW_Min", tostring(mins)) }
            if q.endGap and q.endGap > 15 then
                chips[#chips + 1] = { icon = "pin", text = T("IGUI_COTW_OffRoad", tostring(math.floor(q.endGap))), warn = true }
            end
        elseif not COTW.driving() then
            chips[1] = { icon = "warn", text = T("IGUI_COTW_Err_not_driver"), warn = true }
        else
            chips[1] = { icon = "clock", text = T("IGUI_COTW_Quoting") }
        end
        local cx, cy = PAD, y
        local rowH = U.FONT_S + 8
        for _, c in ipairs(chips) do
            c.lines = U.wrap(c.text, inner - 32)
            local tw = 0
            for _, ln in ipairs(c.lines) do tw = math.max(tw, U.textW(ln)) end
            c.w = tw + 32
            c.h = #c.lines * U.FONT_S + 8
            if cx > PAD and cx + c.w > PAD + inner then cx, cy = PAD, cy + rowH + 6 end
            c.x, c.y = cx, cy
            cx = cx + c.w + 6
            rowH = math.max(U.FONT_S + 8, c.h)
        end
        L.chips = chips
        y = cy + rowH + 4

        local priced = q and not q.err and q.len
        if step == 2 and priced then
            L.fareY = y + 6
            y = L.fareY + U.FONT_S + 6
            L.fareRowH = U.FONT_S + 10
            L.fareRows = {
                { icon = "road", label = T("IGUI_COTW_BaseFare"), value = COTW.money(q.base) },
                { icon = "trailer", label = T("IGUI_COTW_TrailerFee"), value = q.trailerFee > 0 and ("+" .. COTW.money(q.trailerFee)) or "-" },
                { icon = "seat", label = T("IGUI_COTW_SeatLine", tostring(q.riders and #q.riders or 0), tostring(COTW.opt("PassengerPct"))), value = "+" .. COTW.money(q.seat) },
            }
            L.fareTop = y
            y = y + #L.fareRows * L.fareRowH

            -- riders: avatar, name, fare, I pay / send bill
            L.riders = {}
            if q.riders and #q.riders > 0 then
                L.ridersY = y + 8
                y = L.ridersY + U.FONT_S + 6
                local rh = math.max(32, U.FONT_S * 2 + 2) + 12
                local sw = math.max(U.textW(T("IGUI_COTW_IPay")), U.textW(T("IGUI_COTW_SendBill"))) + 16
                local bh = U.FONT_S + 8
                local eligible = {}
                for _, r in ipairs(q.riders) do
                    local billed = self.bill[r.name] and true or false
                    local bx, by = PAD + inner - 8 - sw * 2, y + (rh - bh) / 2
                    local b1 = riderBtn(T("IGUI_COTW_IPay"), "pay", r.name, billed and "seg" or "segOn", bx, by, sw, bh)
                    local b2 = riderBtn(T("IGUI_COTW_SendBill"), "bill", r.name, billed and "segOn" or "seg", bx + sw, by, sw, bh)
                    b1:setEnable(not r.babySeat)
                    b2:setEnable(not r.babySeat)
                    L.riders[#L.riders + 1] = { y = y, h = rh, r = r, segX = bx, segY = by, segW = sw * 2, segH = bh }
                    if r.baby then eligible[#eligible + 1] = r end
                    y = y + rh + 6
                end
                -- baby seat: one rider rides free
                if #eligible > 0 then
                    local bh2 = U.FONT_S + 8
                    L.baby = { y = y, h = bh2 + 12 }
                    local bx = PAD + inner - 8
                    for i = #eligible, 1, -1 do
                        local r = eligible[i]
                        local title = T("IGUI_COTW_BabyPut", r.name)
                        local bw = U.textW(title) + 18
                        bx = bx - bw
                        riderBtn(title, "baby", r.name, self.baby == r.name and "segOn" or "chip", bx, y + 6, bw, bh2)
                        bx = bx - 6
                    end
                    y = y + L.baby.h + 6
                end
            end
            -- group trip switch
            if not self.gid then
                L.groupY = y + 4
                place(self.groupBtn, PAD + inner - 40, L.groupY + (U.FONT_S + 10 - 18) / 2, 40, 18)
                self.groupBtn.on = self.group
                y = L.groupY + U.FONT_S + 10
            end
            -- total
            L.totalY = y + 8
            L.totalH = U.FONT_L + 14
            y = L.totalY + L.totalH
        end

        if step == 2 then
            place(self.goBtn, PAD, y + 10, inner, MAIN)
            self.goBtn:setEnable(priced and C.dest ~= nil and true or false)
            self.goBtn.tag = nil
            if priced then self.goBtn.tag = q.free and T("IGUI_COTW_Free") or COTW.money(self:mine(q)) end
            y = y + 10 + MAIN
            place(self.navBtn, PAD, y + 8, inner, BTN + 6)
            self.navBtn:setEnable(C.dest ~= nil)
            y = y + 8 + BTN + 6
        else
            local trip = C.trip
            L.stateY = y + 6
            y = L.stateY + U.FONT_M + 10
            if trip.state == "ready" and trip.gid ~= nil and (trip.order or 1) == 1 then
                place(self.startBtn, PAD, y, inner, MAIN)
                y = y + MAIN + 8
            end
            if trip.state ~= "driving" then
                place(self.cancelBtn, PAD, y, inner, BTN + 6)
                y = y + BTN + 6
            end
        end
    end

    if COTW.isAdmin() then
        L.adminY = y + 12
        y = L.adminY + U.FONT_S + 6
        local hw = (inner - 6) / 2
        place(self.scanBtn, PAD, y, hw, BTN + 4)
        place(self.recBtn, PAD + hw + 6, y, hw, BTN + 4)
        self.recBtn:setTitle(COTW.Admin.recording() and T("IGUI_COTW_RecStop") or T("IGUI_COTW_RecStart"))
        y = y + BTN + 4
    end
    L.statusY = y + 8
    self:setHeight(L.statusY + U.FONT_S + 16)
end

-- ------------------------------------------------------------------------------
-- drawing (all in prerender, so the buttons land on top)
-- ------------------------------------------------------------------------------
function COTWPanel:drawHead()
    local C = COTW.C
    local L, w = self.L, self.width
    local hh = L.headH
    -- green wash fading to the right
    local seg = w * 0.7 / 6
    for i = 0, 5 do
        local cut = i == 0 and CUT or 0
        U.rect(self, 2 + i * seg + cut, 2, seg - cut, hh - 2, K.g, 0.11 * (1 - i / 6))
    end
    U.rect(self, 2, hh, w - 4, 1, K.line, 1)
    local bx, by = 18, (hh - 38) / 2
    for i = 2, 1, -1 do U.hex(self, bx - i * 2, by - i * 2, 38 + i * 4, 38 + i * 4, K.g, 0.12) end
    U.hex(self, bx, by, 38, 38, K.g, 1)
    U.icon(self, "car", bx + 8, by + 8, 22, K.dark)
    local tx = 66
    if L.step == 1 then
        U.text(self, "COOKIE ON THE WAY", tx, 12, K.ink, UIFont.Medium)
        U.text(self, "AUTOPILOT · NAVIGATOR", tx, 12 + U.FONT_M, K.mute)
    else
        local d = C.dest
        local name = d and (d.name or (d.x .. ", " .. d.y)) or ""
        U.text(self, fit(name, w - tx - 56, UIFont.Medium), tx, 12, K.ink, UIFont.Medium)
        if L.step == 3 and C.trip then U.text(self, T("IGUI_COTW_State_" .. C.trip.state), tx, 12 + U.FONT_M, K.g) end
    end
end

function COTWPanel:drawSteps()
    local L = self.L
    local x, w = PAD, self.width - PAD * 2
    local names = { T("IGUI_COTW_Step_Where"), T("IGUI_COTW_Step_Price"), T("IGUI_COTW_Step_Go") }
    local sw = (w - 8) / 3
    for i = 1, 3 do
        local sx = x + (i - 1) * (sw + 4)
        local on, done = i == L.step, i < L.step
        U.tab(self, sx, L.stepsY, sw, L.stepsH, i == 1, (on or done) and K.g or K.white, on and 1 or (done and 0.2 or 0.03))
        U.textC(self, names[i], sx + sw / 2, L.stepsY + 5, on and K.dark or (done and K.g or K.mute))
    end
end

-- the small map: step 1 a sketch with "click on the map", later the real route with running dashes
function COTWPanel:drawMap()
    local L = self.L
    local x, y, w, h = PAD, L.map.y, self.width - PAD * 2, L.map.h
    U.chamfer(self, x, y, w, h, 10, K.line, 1)
    U.chamfer(self, x + 1, y + 1, w - 2, h - 2, 9.5, K.map, 1)
    local route = L.step > 1 and self:mapRoute() or nil
    if not route or not route.x or #route.x < 2 then
        local ry, rx = y + h * 0.71, x + w * 0.33
        U.rect(self, x + 1, ry - 3.5, w - 2, 7, K.road, 1)
        U.rect(self, rx - 3.5, y + 1, 7, h - 2, K.road, 1)
        for i = 0, math.floor(w / 9) - 1 do U.rect(self, x + 4 + i * 9, ry - 1, 4, 2, K.roadDash, 1) end
        for i = 0, math.floor(h / 9) - 1 do U.rect(self, rx - 1, y + 4 + i * 9, 2, 4, K.roadDash, 1) end
        if L.step == 1 then
            U.disc(self, x + w * 0.17, ry, 6, K.ink, 1)
            U.disc(self, x + w * 0.17, ry, 3, K.panel, 1)
            U.text(self, T("IGUI_COTW_YouHere"), x + w * 0.17 + 12, ry + 6, K.mute)
            U.ping(self, x + w * 0.83, y + h * 0.34, 10, K.g)
            U.textR(self, T("IGUI_COTW_PickHint"), x + w * 0.83 - 16, y + h * 0.34 - U.FONT_S - 6, K.g)
        end
        return
    end
    -- fit the route (and the pin) into the box, north up
    local d = COTW.C.dest
    local minX, maxX, minY, maxY = route.x[1], route.x[1], route.y[1], route.y[1]
    for i = 2, #route.x do
        minX, maxX = math.min(minX, route.x[i]), math.max(maxX, route.x[i])
        minY, maxY = math.min(minY, route.y[i]), math.max(maxY, route.y[i])
    end
    if d then minX, maxX, minY, maxY = math.min(minX, d.x), math.max(maxX, d.x), math.min(minY, d.y), math.max(maxY, d.y) end
    local s = math.min((w - 28) / math.max(1, maxX - minX), (h - 24) / math.max(1, maxY - minY))
    local ox = x + w / 2 - (minX + maxX) / 2 * s
    local oy = y + h / 2 - (minY + maxY) / 2 * s
    local px, py = {}, {}
    for i = 1, #route.x do
        local sx, sy = ox + route.x[i] * s, oy + route.y[i] * s
        local n = #px
        if n == 0 or i == #route.x or math.abs(sx - px[n]) + math.abs(sy - py[n]) > 3 then
            px[n + 1], py[n + 1] = sx, sy
        end
    end
    for i = 2, #px do U.line(self, px[i - 1], py[i - 1], px[i], py[i], 8, K.road, 1) end
    -- dashes running toward the pin
    local pos = -(getTimestampMs() % 1000) / 1000 * 12
    for i = 2, #px do
        local L2 = COTW.dist(px[i - 1], py[i - 1], px[i], py[i])
        local a = pos
        while a < L2 do
            local s0, s1 = math.max(0, a), math.min(L2, a + 6)
            if s1 > s0 and L2 > 0 then
                local f0, f1 = s0 / L2, s1 / L2
                U.line(self, px[i - 1] + (px[i] - px[i - 1]) * f0, py[i - 1] + (py[i] - py[i - 1]) * f0,
                    px[i - 1] + (px[i] - px[i - 1]) * f1, py[i - 1] + (py[i] - py[i - 1]) * f1, 3, K.g, 1)
            end
            a = a + 12
        end
        pos = a - L2
    end
    U.disc(self, px[1], py[1], 5, K.ink, 1)
    local ex, ey = px[#px], py[#py]
    if d then ex, ey = ox + d.x * s, oy + d.y * s end
    U.ping(self, ex, ey, 8, K.g)
    U.disc(self, ex, ey, 4, K.g, 1)
end

function COTWPanel:drawChip(c)
    local col = c.warn and K.amber or K.g
    U.chamfer(self, c.x, c.y, c.w, c.h, 6, c.warn and K.amber or K.white, c.warn and 0.1 or 0.04)
    U.icon(self, c.icon, c.x + 9, c.y + (c.h - 14) / 2, 14, col)
    for i, ln in ipairs(c.lines) do U.text(self, ln, c.x + 28, c.y + 4 + (i - 1) * U.FONT_S, c.warn and K.amber or K.ink) end
end

function COTWPanel:drawBody()
    local C = COTW.C
    local L, w = self.L, self.width
    local inner = w - PAD * 2
    local q = C.quote
    if L.step == 1 then U.label(self, T("IGUI_COTW_QuickGo"), PAD, L.quickY, inner) end
    for _, c in ipairs(L.chips or {}) do self:drawChip(c) end
    if L.fareY then
        U.label(self, T("IGUI_COTW_FareLbl"), PAD, L.fareY, inner)
        local y = L.fareTop
        for _, r in ipairs(L.fareRows) do
            U.icon(self, r.icon, PAD, y + (L.fareRowH - 16) / 2, 16, K.g)
            U.text(self, r.label, PAD + 24, y + 5, K.mute)
            U.textR(self, r.value, PAD + inner, y + 5, K.ink)
            for i = 0, math.floor(inner / 6) - 1 do U.rect(self, PAD + i * 6, y + L.fareRowH - 1, 3, 1, K.white, 0.07) end
            y = y + L.fareRowH
        end
    end
    if L.ridersY then
        U.label(self, T("IGUI_COTW_RidersLbl"), PAD, L.ridersY, inner)
        for _, e in ipairs(L.riders) do
            local r = e.r
            U.rect(self, PAD + 8, e.y, inner - 8, e.h, K.white, 0.025)
            U.quad(self, PAD + 8, e.y, PAD + 8, e.y + 8, PAD, e.y + 8, PAD, e.y + 8, K.white, 0.025)
            U.rect(self, PAD, e.y + 8, 8, e.h - 8, K.white, 0.025)
            U.hex(self, PAD + 8, e.y + (e.h - 32) / 2, 32, 32, K.g, 0.12)
            U.icon(self, "user", PAD + 15, e.y + (e.h - 18) / 2, 18, K.g)
            local fare = r.babySeat and T("IGUI_COTW_Free") or COTW.money(r.fare)
            local textY = e.y + (e.h - U.FONT_S * 2) / 2
            U.text(self, fit(r.name, e.segX - PAD - 56), PAD + 48, textY, K.ink)
            U.text(self, fit(fare, e.segX - PAD - 56), PAD + 48, textY + U.FONT_S, K.mute)
            U.chamferLine(self, e.segX, e.segY, e.segW, e.segH, 6, K.g, 0.4)
        end
        if L.baby then
            local b = L.baby
            for i = 0, math.floor(inner / 8) - 1 do
                U.rect(self, PAD + i * 8, b.y, 4, 1, K.g, 0.33)
                U.rect(self, PAD + i * 8, b.y + b.h - 1, 4, 1, K.g, 0.33)
            end
            U.icon(self, "baby", PAD + 8, b.y + (b.h - 18) / 2, 18, K.g)
            U.text(self, T("IGUI_COTW_BabyRow"), PAD + 32, b.y + (b.h - U.FONT_S) / 2, K.mute)
        end
    end
    if L.groupY and self.groupBtn:isVisible() then
        U.icon(self, "convoy", PAD, L.groupY + (U.FONT_S + 10 - 18) / 2, 18, K.g)
        U.text(self, T("IGUI_COTW_GroupRow"), PAD + 26, L.groupY + 5, K.ink)
    end
    if L.totalY and q and not q.err and q.total then
        local y, h = L.totalY, L.totalH
        local seg = inner / 5
        for i = 0, 4 do
            local cut = i == 0 and 10 or 0
            U.rect(self, PAD + i * seg + cut, y, seg - cut, h, K.g, 0.13 - i * 0.025)
        end
        U.quad(self, PAD + 10, y, PAD + 10, y + 10, PAD, y + 10, PAD, y + 10, K.g, 0.13)
        U.rect(self, PAD, y + 10, 10, h - 10, K.g, 0.13)
        U.text(self, T("IGUI_COTW_TotalLbl"), PAD + 12, y + 6, K.ink)
        local billed, names = 0, {}
        for _, r in ipairs(q.riders or {}) do
            if self.bill[r.name] then billed = billed + r.fare; names[#names + 1] = r.name end
        end
        if #names > 0 then
            U.text(self, fit(T("IGUI_COTW_BilledNote", table.concat(names, ", "), COTW.money(billed)), inner * 0.55), PAD + 12, y + 6 + U.FONT_S, K.mute)
        end
        local total = q.free and T("IGUI_COTW_Free") or COTW.money(q.total)
        U.textR(self, total, PAD + inner - 12, y + (h - U.FONT_L) / 2, K.g, UIFont.Large)
    end
    if L.stateY and C.trip then
        U.icon(self, "clock", PAD, L.stateY + (U.FONT_M - 20) / 2, 20, K.g)
        U.text(self, T("IGUI_COTW_State_" .. C.trip.state), PAD + 28, L.stateY, K.ink, UIFont.Medium)
    end
    if L.adminY then U.label(self, T("IGUI_COTW_AdminLbl"), PAD, L.adminY, inner) end

    local status = nil
    if COTW.Admin.scanning() then status = T("IGUI_COTW_Scan_Running") end
    local recOn, recN = COTW.Admin.recording()
    if recOn then status = T("IGUI_COTW_Rec_Running", tostring(recN)) end
    if self.gid then status = (status and status .. "  " or "") .. T("IGUI_COTW_Joining") end
    if status then U.text(self, status, PAD, L.statusY, K.g) end
end

function COTWPanel:prerender()
    local C = COTW.C
    if C.quote ~= self.shownQuote or (C.trip and C.trip.state) ~= self.shownState or (C.dest ~= nil) ~= self.shownDest then
        self.shownQuote = C.quote
        self.shownState = C.trip and C.trip.state
        self.shownDest = C.dest ~= nil
        self:layout()
    end
    if C.dest and not C.trip and getTimestampMs() - self.lastQuote > REQUOTE_MS then self:requote() end
    U.frame(self, self.width, self.height, CUT)
    self:drawHead()
    self:drawSteps()
    self:drawMap()
    self:drawBody()
end

function COTWPanel:render() end

-- ------------------------------------------------------------------------------
-- entry: vehicle radial menu
-- ------------------------------------------------------------------------------
local RADIAL_TEX = "media/ui/vehicles/vehicle_changeseats.png"

local origRadial = ISVehicleMenu.showRadialMenu
function ISVehicleMenu.showRadialMenu(playerObj)
    origRadial(playerObj)
    local ok, err = pcall(function()
        if not playerObj:getVehicle() then return end
        local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
        -- the closing call leaves the menu cleared; isReallyVisible is not reliable right after addToUIManager
        if not menu.slices or #menu.slices == 0 then return end
        local tex = getTexture("media/ui/COTW_Radial.png") or getTexture(RADIAL_TEX)
        menu:addSlice(getText("IGUI_COTW_Title"), tex, COTWPanel.open)
    end)
    if not ok then COTW.log("radial error: " .. tostring(err)) end
end
