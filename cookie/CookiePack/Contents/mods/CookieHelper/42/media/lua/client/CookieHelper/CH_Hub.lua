-- Cookie Helper : zones of one house as slots (workshops + garages)
-- Hover a slot = what it does. Click = open. Right click = rename / delete.
-- Each zone is counted when the window opens and every 10 s while it stays open (you nearby only).
if isServer() then return end

require "ISUI/ISContextMenu"
require "CookieHelper/CH_Client"
require "CookieHelper/CH_Scan"

CHelp.Hub = CHelp.Hub or {}
local Hub = CHelp.Hub
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local Scan = CHelp.Scan
local t = CHelp.t
local floor = math.floor

local W = UI.Window:derive("CHelpHub")
local COLS = 3
local CARD_H = 184

function W:createChildren()
    UI.Window.createChildren(self)
    local hr = self:headRight()
    self.areaBtn = UI.button(self, hr - 190, floor((UI.HEAD_H - UI.BTN_H) / 2), 190, "", self, W.onArea, "sec")
    self.areaBtn:setIcon("eye")
    self.headTextRight = self.areaBtn:getX() - 10
    self.info = {}
    self.lastInfo = 0
    self.hits = {}
    C.on("zones", self, W.onZones)
    C.on("safehouses", self, W.onZones)
    C.on("highlight", self, W.paintArea)
    self:paintArea()
end

function W:onClose()
    C.off(self)
    if Hub.instance == self then Hub.instance = nil end
end

function W:paintArea()
    local lit = C.hl[self.key] == true
    self.areaBtn:setTitle(lit and t("HideHouseArea") or t("ShowHouseArea"))
    self.areaBtn:setKind(lit and "soft" or "sec")
end

function W:onArea()
    local sh = CHelp.shByKey(self.key)
    if sh then C.toggleHouse(sh) end
end

function W:onZones()
    self.sh = CHelp.shByKey(self.key)
    if not self.sh then return self:close() end
    self.lastInfo = 0
    self.countQ = nil
end

function W:near()
    local p = C.player()
    if not p or not self.sh then return false end
    return CHelp.shDist(self.sh, floor(p:getX()), floor(p:getY())) <= 30
end

-- counts per zone (only squares that are loaded: you must be near)
-- one zone per frame (a full pass every 10 s) so a big house never hitches
function W:pumpCount()
    local ms = CHelp.nowMs()
    if not self.countQ or #self.countQ == 0 then
        if ms - self.lastInfo < 10000 then return end
        self.lastInfo = ms
        self.countQ = {}
        for _, z in ipairs(C.zonesOf(self.sh)) do self.countQ[#self.countQ + 1] = z end
        return
    end
    local z = table.remove(self.countQ, 1)
    local ok, err = pcall(function() self:recountOne(z) end)
    if not ok then CHelp.log("zone count failed: " .. tostring(err)) end
end

function W:recountOne(z)
    do
        local entries = Scan.containers(z, z.z, z.kind == CHelp.ZONE_VEHICLE)
        local map, total = Scan.count(entries)
        local boxes = 0
        for _, e in ipairs(entries) do if not e.veh then boxes = boxes + 1 end end
        local inf = { total = total, boxes = boxes, chips = {} }
        if z.kind == CHelp.ZONE_VEHICLE then
            for _, v in ipairs(Scan.vehicles(z, z.z)) do
                local sc = v:getScript()
                if sc then
                    local short = sc:getName()
                    local nm = getTextOrNull("IGUI_VehicleName" .. short) or short
                    inf.chips[#inf.chips + 1] = { label = nm, px = "car", white = true }
                end
            end
        else
            local st = Scan.stations(z, z.z)
            for _, b in ipairs(st.benches) do
                inf.chips[#inf.chips + 1] = { label = b.name, px = CHelp.Count.stationPx(b.name) }
            end
            if #st.surfaces > 0 then inf.chips[#inf.chips + 1] = { label = t("TablesN", #st.surfaces), px = "table" } end
            for _, m in ipairs(st.machines) do inf.chips[#inf.chips + 1] = { label = m.name, px = "furnace", dim = true } end
        end
        self.info[z.id] = inf
    end
end

local function slotsFor(self, kind)
    local list = {}
    for _, z in ipairs(C.zonesOf(self.sh)) do
        if (z.kind == CHelp.ZONE_VEHICLE) == (kind == CHelp.ZONE_VEHICLE) then list[#list + 1] = { zone = z } end
    end
    local limit = kind == CHelp.ZONE_VEHICLE and CHelp.svInt("VehicleZonesPerSafehouse", 0, 20) or CHelp.svInt("CountZonesPerSafehouse", 0, 20)
    local used = #list
    for _ = used + 1, limit do list[#list + 1] = { empty = true } end
    if used >= limit then list[#list + 1] = { locked = true } end
    return list, used, limit
end

function W:drawSection(y, kind)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local list, used, limit = slotsFor(self, kind)
    local title = kind == CHelp.ZONE_VEHICLE and t("Garages") or t("Workshops")
    T.text(self, title, x, y, K.text)
    local tw = T.tw(title) + 8
    tw = tw + T.pill(self, x + tw, y - 1, used .. "/" .. limit, K.text2, K.surf2) + 8
    T.text(self, T.fit(kind == CHelp.ZONE_VEHICLE and t("GaragesSub") or t("WorkshopsSub"), w - tw), x + tw, y, K.text3)
    y = y + UI.HS + 10
    local cw = floor((w - (COLS - 1) * 14) / COLS)
    local mx, my = self:getMouseX(), self:getMouseY()
    local rows = math.ceil(#list / COLS)
    for i, s in ipairs(list) do
        local col = (i - 1) % COLS
        local row = floor((i - 1) / COLS)
        local cx = x + col * (cw + 14)
        local cy = y + row * (CARD_H + 14)
        local r = { x = cx, y = cy, w = cw, h = CARD_H }
        local hov = T.hot(r, mx, my)
        if s.zone then
            self:drawZoneCard(s.zone, r, hov)
            self.hits[#self.hits + 1] = { r = r, zone = s.zone }
        elseif s.empty then
            T.rrect(self, cx, cy, cw, CARD_H, UI.RC, hov and K.acc or K.line)
            T.rrect(self, cx + 2, cy + 2, cw - 4, CARD_H - 4, UI.RC - 2, K.bg)
            T.circle(self, cx + cw / 2 - 22, cy + 34, 44, K.surf2)
            T.icon(self, "plus", cx + cw / 2 - 11, cy + 45, 22, K.acc)
            T.textC(self, t("EmptySlot"), cx + cw / 2, cy + 90, K.text)
            local bl = kind == CHelp.ZONE_VEHICLE and t("NewGarage") or t("NewWorkshop")
            local bw = T.tw(bl) + 28
            T.rrect(self, cx + (cw - bw) / 2, cy + 116, bw, UI.BTN_H, 8, hov and K.surf3 or K.surf2)
            T.textC(self, bl, cx + cw / 2, cy + 116 + floor((UI.BTN_H - UI.HS) / 2), K.text)
            self.hits[#self.hits + 1] = { r = r, newKind = kind }
        else
            T.rrect(self, cx, cy, cw, CARD_H, UI.RC, K.surf, 0.45)
            T.circle(self, cx + cw / 2 - 22, cy + 34, 44, K.surf)
            T.icon(self, "lock", cx + cw / 2 - 11, cy + 45, 22, K.text3)
            T.textC(self, t("LockedSlot"), cx + cw / 2, cy + 90, K.text2)
            T.textC(self, t("LockedSub"), cx + cw / 2, cy + 92 + UI.HS, K.text3)
            self.hits[#self.hits + 1] = { r = r, locked = true }
        end
        if hov then self.hover = { r = r, s = s, kind = kind } end
    end
    return y + rows * (CARD_H + 14) + 6
end

function W:drawZoneCard(z, r, hov)
    local x, y, w, h = r.x, r.y, r.w, r.h
    if hov then T.rring(self, x, y, w, h, UI.RC, K.acc, K.surf, 2) else T.rrect(self, x, y, w, h, UI.RC, K.surf) end
    local veh = z.kind == CHelp.ZONE_VEHICLE
    T.slot(self, x + 14, y + 14, 44, nil, veh and "car" or "crate")
    T.text(self, T.fit(z.name, w - 80), x + 70, y + 16, K.text)
    local meta = (z.parts and #z.parts > 0) and t("ZoneMetaParts", CHelp.zoneTiles(z), #z.parts + 1, z.z)
        or t("ZoneMeta", z.x2 - z.x1, z.y2 - z.y1, z.z)
    T.text(self, T.fit(meta, w - 80), x + 70, y + 18 + UI.HS, K.text3)
    local inf = self.info[z.id]
    local ny = y + 70
    if inf then
        local a = tostring(inf.total)
        local b = tostring(inf.boxes)
        T.text(self, a, x + 14, ny, K.text, T.FL)
        local ax = x + 14 + T.tw(a, T.FL) + 4
        T.text(self, veh and t("UnitParts") or t("UnitItems"), ax, ny + UI.HL - UI.HS - 2, K.text3)
        local bx = ax + T.tw(veh and t("UnitParts") or t("UnitItems")) + 18
        T.text(self, b, bx, ny, K.text, T.FL)
        T.text(self, t("UnitBoxes"), bx + T.tw(b, T.FL) + 4, ny + UI.HL - UI.HS - 2, K.text3)
        local cx = x + 14
        local cy = ny + UI.HL + 8
        for _, c in ipairs(inf.chips) do
            local label = T.fit(c.label, w - 60)
            local cw = T.pillW(label, T.FS, { px = c.px })
            if cx + cw > x + w - 10 then break end
            if c.white then T.pill(self, cx, cy, label, K.bg, K.pill, T.FS, { px = c.px })
            elseif c.dim then T.pill(self, cx, cy, label, K.text2, K.surf2, T.FS, { px = c.px })
            else T.pill(self, cx, cy, label, K.acc, K.accD, T.FS, { px = c.px }) end
            cx = cx + cw + 6
        end
    else
        T.text(self, self:near() and t("Counting") or t("CountFar"), x + 14, ny + 4, K.text3)
    end
    -- open button look
    local bl = t("Open")
    local bw = T.tw(bl) + 28
    local by = y + h - UI.BTN_H - 12
    T.text(self, veh and t("GarageFoot") or t("WorkshopFoot"), x + 14, by + floor((UI.BTN_H - UI.HS) / 2), K.text3)
    T.rrect(self, x + w - bw - 12, by, bw, UI.BTN_H, 8, K.acc)
    T.textC(self, bl, x + w - 12 - bw / 2, by + floor((UI.BTN_H - UI.HS) / 2), K.onAcc)
end

function W:drawBody()
    local ms = CHelp.nowMs()
    if not self.shMs or ms - self.shMs > 1000 then
        self.shMs = ms
        self.sh = CHelp.shByKey(self.key)
    end
    if not self.sh then return end
    if self:near() then self:pumpCount() end
    self.hits = {}
    self.hover = nil
    local y = UI.HEAD_H + 2
    T.text(self, T.fit(t("ZonesHelp"), self.width - UI.PAD * 2), UI.PAD, y, K.text3)
    y = y + UI.HS + 14
    y = self:drawSection(y, CHelp.ZONE_COUNT)
    y = self:drawSection(y + 6, CHelp.ZONE_VEHICLE)
    local need = math.min(y + UI.PAD, getCore():getScreenHeight() - 20)
    if math.abs(need - self.height) > 2 then self:setHeight(need) end
end

local function tipFor(s, kind, info)
    if s.zone then
        local z = s.zone
        if z.kind == CHelp.ZONE_VEHICLE then
            return t("TipGarageTitle", z.name), { t("TipGarage1"), t("TipGarage2"), t("TipGarage3"), t("TipGarage4") }, t("TipZoneFoot")
        end
        local lines = { t("TipWork1"), t("TipWork2"), t("TipWork3"), t("TipWork4") }
        if info and #info.chips > 0 then
            local names = {}
            for _, c in ipairs(info.chips) do names[#names + 1] = c.label end
            lines[2] = t("TipWorkStations", table.concat(names, ", "))
        end
        return t("TipWorkTitle", z.name), lines, t("TipZoneFoot")
    elseif s.empty then
        return t("TipNewTitle"), { t("TipNew1"), t("TipNew2", CHelp.svInt("MaxZoneSide", 2, 200)), t("TipNew3") }, nil
    end
    return t("TipLockedTitle"), { t("TipLocked1", CHelp.svInt("CountZonesPerSafehouse", 0, 20), CHelp.svInt("VehicleZonesPerSafehouse", 0, 20)), t("TipLocked2") }, nil
end

function W:drawOver()
    local hv = self.hover
    if not hv then return end
    local title, lines, foot = tipFor(hv.s, hv.kind, hv.s.zone and self.info[hv.s.zone.id])
    local tw = 320
    local ty = hv.r.y + hv.r.h + 8
    if ty + 170 > self.height then ty = hv.r.y - 170 end
    UI.drawTip(self, hv.r.x, ty, tw, title, lines, foot)
end

function W:onMouseDown(x, y)
    for _, h in ipairs(self.hits or {}) do
        if T.hot(h.r, x, y) then
            if h.zone then
                local z = h.zone
                if z.kind == CHelp.ZONE_VEHICLE then CHelp.Veh.open(self.sh, z) else CHelp.Count.open(self.sh, z) end
            elseif h.newKind then
                if CHelp.ZoneTool then CHelp.ZoneTool.open(self.sh, h.newKind) end
            end
            getSoundManager():playUISound("UISelectListItem")
            return true
        end
    end
    return ISPanel.onMouseDown(self, x, y)
end

function W:onRightMouseDown(x, y)
    for _, h in ipairs(self.hits or {}) do
        if T.hot(h.r, x, y) and h.zone then
            local z = h.zone
            local ctx = ISContextMenu.get(0, getMouseX(), getMouseY())
            ctx:addOption(t("Rename"), self, W.onRename, z)
            ctx:addOption(t("Redraw"), self, W.onRedraw, z)
            ctx:addOption(t("ShowOnFloor"), self, W.onShow, z)
            ctx:addOption(t("Delete"), self, W.onDelete, z)
            return true
        end
    end
    return false
end

function W:onRename(z)
    local key = self.key
    UI.prompt(t("Rename"), t("RenameZoneAsk"), z.name, t("Save"), self, function(_, text)
        CHelp.toServer("zoneRename", { sh = key, id = z.id, name = text })
    end)
end

function W:onRedraw(z)
    if CHelp.ZoneTool then CHelp.ZoneTool.open(self.sh, z.kind, z.name, z.id) end
end

function W:onShow(z)
    C.clearMarks("zone")
    for i, r in ipairs(CHelp.zoneRects(z)) do
        C.mark(r.x1, r.y1, r.x2, r.y2, z.z, K.acc[1], K.acc[2], K.acc[3], 0.35, 4000, i == 1 and z.name or nil, "zone")
    end
end

function W:onDelete(z)
    local key = self.key
    UI.confirm(t("Delete"), t("ConfirmDelete", z.name), t("Delete"), true, self, function()
        CHelp.toServer("zoneDel", { sh = key, id = z.id })
    end)
end

function Hub.open(sh)
    if not sh then return end
    if Hub.instance then Hub.instance:close() end
    local sw, shh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w = math.min(820, sw - 20)
    local h = math.min(UI.HEAD_H + UI.HS + 16 + (UI.HS + 10 + CARD_H + 20) * 2 + 40 + UI.HS, shh - 20)
    local x, y = UI.center(w, h)
    local win = W:new(x, y, w, h, t("ZonesTitle"))
    win.subtitle = sh:getTitle()
    win.sh = sh
    win.key = CHelp.shKey(sh)
    win:show()
    Hub.instance = win
    CHelp.toServer("zonesReq", { sh = win.key })
end
