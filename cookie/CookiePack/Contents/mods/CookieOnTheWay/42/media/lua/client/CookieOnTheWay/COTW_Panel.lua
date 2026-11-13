-- Cookie On the Way : the booking window (vehicle radial menu "Cookie On the Way")
-- Where to (map / My Home / My Pin 1-5), the fare the server quotes (trip, trailer, each rider with
-- "I pay" / "send bill" and the baby seat), Group Trip, then Autopilot (after a consent box) or
-- navigate for free. Admins also get Scan vehicle and Record road here.

require "CookieOnTheWay/COTW_Client"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"
require "Vehicles/ISUI/ISVehicleMenu"

COTWPanel = ISPanel:derive("COTWPanel")

local FONT_S = getTextManager():getFontHeight(UIFont.Small)
local FONT_M = getTextManager():getFontHeight(UIFont.Medium)
local ROW = math.max(FONT_S + 8, 24)
local PAD = 12
local W = 400
local REQUOTE_MS = 5000

local function T(key, ...) return getText(key, ...) end

local function btn(self, x, y, w, title, fn)
    local b = ISButton:new(x, y, w, ROW, title, self, fn)
    b:initialise()
    self:addChild(b)
    return b
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
    o.backgroundColor = { r = 0.08, g = 0.07, b = 0.06, a = 0.92 }
    o.borderColor = { r = 0.85, g = 0.6, b = 0.25, a = 1 }
    o.bill = {}          -- rider name -> true: send them a bill
    o.baby = nil         -- rider name in the baby seat
    o.group = false
    o.gid = nil          -- joining someone's group trip
    o.riderBtns = {}
    o.lastQuote = 0
    return o
end

function COTWPanel:createChildren()
    ISPanel.createChildren(self)
    self.closeBtn = btn(self, self.width - PAD - 24, PAD - 2, 24, "X", COTWPanel.close)
    local y = PAD + FONT_M + 10 + FONT_S + 8
    local half = (self.width - PAD * 3) / 2
    self.mapBtn = btn(self, PAD, y, half, T("IGUI_COTW_PickMap"), COTWPanel.onPickMap)
    self.homeBtn = btn(self, PAD * 2 + half, y, half, T("IGUI_COTW_Home"), COTWPanel.onHome)
    y = y + ROW + 4
    self.pinBtns = {}
    local pw = (self.width - PAD * 2 - 4 * (COTW.PINS - 1)) / COTW.PINS
    for i = 1, COTW.PINS do
        local b = btn(self, PAD + (i - 1) * (pw + 4), y, pw, tostring(i), COTWPanel.onPin)
        b.pinIndex = i
        self.pinBtns[i] = b
    end
    self.infoY = y + ROW + 10

    self.groupBtn = btn(self, PAD, 0, half, "", COTWPanel.onGroup)
    self.goBtn = btn(self, PAD, 0, half, "", COTWPanel.onAutopilot)
    self.navBtn = btn(self, PAD * 2 + half, 0, half, T("IGUI_COTW_NavFree"), COTWPanel.onNav)
    self.cancelBtn = btn(self, PAD, 0, half, T("IGUI_COTW_CancelTrip"), COTWPanel.onCancel)
    self.startBtn = btn(self, PAD * 2 + half, 0, half, T("IGUI_COTW_GroupStart"), COTWPanel.onGroupStart)
    self.scanBtn = btn(self, PAD, 0, half, T("IGUI_COTW_Scan"), COTWPanel.onScan)
    self.recBtn = btn(self, PAD * 2 + half, 0, half, "", COTWPanel.onRecord)
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
        self.bill[name] = not self.bill[name] or nil
    else
        self.baby = self.baby ~= name and name or nil
        self:requote()
    end
    self:layout()
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
    local text = T("IGUI_COTW_Consent", COTW.money(q.total))
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
-- layout (buttons move with the number of riders)
-- ------------------------------------------------------------------------------
function COTWPanel:layout()
    local C = COTW.C
    for i = 1, COTW.PINS do
        local pin = C.pins[i]
        local title = pin and pin.n or (tostring(i) .. ".")
        if #title > 8 then title = string.sub(title, 1, 7) .. "." end
        self.pinBtns[i]:setTitle(title)
    end
    for _, b in ipairs(self.riderBtns) do self:removeChild(b) end
    self.riderBtns = {}

    local y = self.infoY + (FONT_S + 2) * 5
    local q = C.quote
    local half = (self.width - PAD * 3) / 2
    self.riderY = y
    if q and not q.err and q.riders then
        for _, r in ipairs(q.riders) do
            local bx = self.width - PAD - 80
            local b = btn(self, bx, y, 80, self.bill[r.name] and T("IGUI_COTW_SendBill") or T("IGUI_COTW_IPay"), COTWPanel.onRider)
            b.riderName, b.kind = r.name, "bill"
            b:setEnable(not r.babySeat)
            self.riderBtns[#self.riderBtns + 1] = b
            if r.baby then
                local bb = btn(self, bx - 86, y, 82, (self.baby == r.name) and T("IGUI_COTW_BabyOn") or T("IGUI_COTW_BabyOff"), COTWPanel.onRider)
                bb.riderName, bb.kind = r.name, "baby"
                self.riderBtns[#self.riderBtns + 1] = bb
            end
            y = y + ROW + 2
        end
    end
    y = y + FONT_S + 10      -- total line

    local trip = C.trip
    local busy = trip ~= nil
    self.groupBtn:setY(y)
    self.groupBtn:setTitle((self.group or self.gid) and T("IGUI_COTW_GroupOn") or T("IGUI_COTW_GroupOff"))
    self.groupBtn:setVisible(not busy and self.gid == nil)
    y = y + ROW + 6
    self.goBtn:setY(y)
    self.navBtn:setY(y)
    self.goBtn:setTitle(q and not q.err and q.total and T("IGUI_COTW_Autopilot", q.free and T("IGUI_COTW_Free") or COTW.money(q.total)) or T("IGUI_COTW_AutopilotNo"))
    self.goBtn:setEnable(q ~= nil and not q.err and C.dest ~= nil)
    self.goBtn:setVisible(not busy)
    self.navBtn:setEnable(C.dest ~= nil)
    self.navBtn:setVisible(not busy)
    self.cancelBtn:setY(y)
    self.cancelBtn:setVisible(busy and trip.state ~= "driving")
    self.startBtn:setY(y)
    self.startBtn:setVisible(busy and trip.state == "ready" and trip.gid ~= nil and (trip.order or 1) == 1)
    y = y + ROW + 6

    local admin = COTW.isAdmin()
    self.scanBtn:setVisible(admin)
    self.recBtn:setVisible(admin)
    if admin then
        self.scanBtn:setY(y)
        self.recBtn:setY(y)
        self.recBtn:setTitle(COTW.Admin.recording() and T("IGUI_COTW_RecStop") or T("IGUI_COTW_RecStart"))
        y = y + ROW + 6
    end
    self.statusY = y
    self:setHeight(y + FONT_S + PAD + 4)
end

-- ------------------------------------------------------------------------------
-- drawing
-- ------------------------------------------------------------------------------
function COTWPanel:prerender()
    ISPanel.prerender(self)
    local C = COTW.C
    if C.quote ~= self.shownQuote or (C.trip and C.trip.state) ~= self.shownState then
        self.shownQuote = C.quote
        self.shownState = C.trip and C.trip.state
        self:layout()
    end
    if C.dest and not C.trip and getTimestampMs() - self.lastQuote > REQUOTE_MS then self:requote() end
end

function COTWPanel:render()
    ISPanel.render(self)
    local C = COTW.C
    local q = C.quote
    self:drawText(T("IGUI_COTW_Title"), PAD, PAD, 1, 0.8, 0.4, 1, UIFont.Medium)
    local y = PAD + FONT_M + 8
    local dest = C.dest and (C.dest.name or string.format("%d, %d", C.dest.x, C.dest.y)) or T("IGUI_COTW_NoDest")
    self:drawText(T("IGUI_COTW_Where", dest), PAD, y, 1, 1, 1, 1, UIFont.Small)

    y = self.infoY
    local line = FONT_S + 2
    local function row(label, value, r, g, b)
        self:drawText(label, PAD, y, 0.85, 0.85, 0.85, 1, UIFont.Small)
        if value then self:drawTextRight(value, self.width - PAD, y, r or 1, g or 1, b or 1, 1, UIFont.Small) end
        y = y + line
    end
    if q and q.err then
        row(T("IGUI_COTW_Err_" .. q.err), nil)
    elseif q and q.len then
        local km = q.len / 1000
        local mins = math.ceil(km / (COTW.opt("CitySpeed") * 0.8) * 60)
        row(T("IGUI_COTW_Distance"), string.format("%.1f", km) .. " km · ~" .. tostring(mins) .. " min")
        row(T("IGUI_COTW_BaseFare"), COTW.money(q.base))
        row(T("IGUI_COTW_TrailerFee"), q.trailerFee > 0 and ("+" .. COTW.money(q.trailerFee)) or "-")
        row(T("IGUI_COTW_SeatFare", tostring(COTW.opt("PassengerPct"))), "+" .. COTW.money(q.seat))
        if q.endGap and q.endGap > 15 then row(T("IGUI_COTW_OffRoad", tostring(math.floor(q.endGap))), nil, 0.9, 0.7, 0.3) end
    elseif not COTW.driving() then
        row(T("IGUI_COTW_Err_not_driver"), nil)
    end
    y = self.riderY
    if q and not q.err and q.riders then
        for _, r in ipairs(q.riders) do
            local fare = r.babySeat and T("IGUI_COTW_Free") or COTW.money(r.fare)
            self:drawText(r.name .. "  " .. fare, PAD, y + 4, 1, 1, 1, 1, UIFont.Small)
            y = y + ROW + 2
        end
        -- what the booker pays now: trip + trailer + every rider not billed
        local mine = q.base + q.trailerFee
        for _, r in ipairs(q.riders) do if not self.bill[r.name] then mine = mine + r.fare end end
        self:drawText(T("IGUI_COTW_Total", COTW.money(q.total), COTW.money(mine)), PAD, y + 2, 1, 0.8, 0.4, 1, UIFont.Small)
    end

    local status = nil
    local trip = C.trip
    if trip then status = T("IGUI_COTW_State_" .. trip.state) end
    if COTW.Admin.scanning() then status = T("IGUI_COTW_Scan_Running") end
    local recOn, recN = COTW.Admin.recording()
    if recOn then status = T("IGUI_COTW_Rec_Running", tostring(recN)) end
    if self.gid then status = (status and status .. "  " or "") .. T("IGUI_COTW_Joining") end
    if status then self:drawText(status, PAD, self.statusY, 0.6, 0.9, 0.6, 1, UIFont.Small) end
end

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
