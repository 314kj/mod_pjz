-- Cookie Helper : zone drawing tool (stand on one corner, walk to the other, save)
if isServer() then return end

require "CookieHelper/CH_Client"

CHelp.ZoneTool = CHelp.ZoneTool or {}
local ZT = CHelp.ZoneTool
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local t = CHelp.t
local floor = math.floor

local W = UI.Window:derive("CHelpZoneTool")

function W:createChildren()
    UI.Window.createChildren(self)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + 2
    self.kinds = UI.tabs(self, x, y, { { id = CHelp.ZONE_COUNT, label = t("KindCount") }, { id = CHelp.ZONE_VEHICLE, label = t("KindVehicle") } },
        self.kind, self, W.onKind)
    y = y + self.kinds.height + 12
    self.name = UI.entry(self, x, y, w, self.presetName or "")
    self.name:setPlaceholderText(t("ZoneNameHint"))
    y = y + UI.BTN_H + 12
    self.yInfo = y
    y = y + (UI.HS + 6) * 4 + 10
    local corner = UI.button(self, x, y, w, t("SetCorner"), self, W.onCorner, "sec")
    corner:setIcon("refresh")
    y = y + UI.BTN_H + 8
    local half = floor((w - 8) / 2)
    UI.button(self, x, y, half, t("Cancel"), self, W.onCancelBtn, "ghost")
    self.saveBtn = UI.button(self, x + half + 8, y, w - half - 8, t("Save"), self, W.onSave, "pri")
    self:onCorner()
end

function W:onKind(id)
    self.kind = id
end

function W:onCorner()
    local p = C.player()
    if not p then return end
    self.sx, self.sy, self.sz = floor(p:getX()), floor(p:getY()), floor(p:getZ())
end

function W:rect()
    local p = C.player()
    local cx, cy = floor(p:getX()), floor(p:getY())
    return {
        x1 = math.min(self.sx, cx), y1 = math.min(self.sy, cy),
        x2 = math.max(self.sx, cx) + 1, y2 = math.max(self.sy, cy) + 1,
    }
end

function W:problem(r)
    local side = CHelp.svInt("MaxZoneSide", 2, 200)
    if r.x2 - r.x1 > side or r.y2 - r.y1 > side then return t("Msg_ZoneTooBig", side) end
    if not CHelp.rectInside(r, CHelp.shRect(self.sh)) then return t("Msg_ZoneOutside") end
    local p = C.player()
    if floor(p:getZ()) ~= self.sz then return t("ZoneSameFloor") end
    return nil
end

function W:drawBody()
    local p = C.player()
    if not p or not self.sx then return end
    local r = self:rect()
    local bad = self:problem(r)
    if bad then
        addAreaHighlight(r.x1, r.y1, r.x2, r.y2, self.sz, K.bad[1], K.bad[2], K.bad[3], 0.35)
    else
        addAreaHighlight(r.x1, r.y1, r.x2, r.y2, self.sz, K.acc[1], K.acc[2], K.acc[3], 0.35)
    end
    local x, y, w = UI.PAD, self.yInfo, self.width - UI.PAD * 2
    T.rrect(self, x, y - 6, w, (UI.HS + 6) * 4 + 6, UI.RC, K.surf)
    T.text(self, T.fit(t("ZoneStep"), w - 20), x + 10, y, K.text3)
    T.text(self, t("ZoneStart", self.sx, self.sy, self.sz), x + 10, y + UI.HS + 6, K.text)
    T.text(self, t("ZoneSize", r.x2 - r.x1, r.y2 - r.y1), x + 10, y + (UI.HS + 6) * 2, K.text)
    T.icon(self, bad and "warn" or "check", x + 10, y + (UI.HS + 6) * 3 + 1, UI.HS - 2, bad and K.bad or K.acc)
    T.text(self, T.fit(bad or t("ZoneOk"), w - 40), x + 14 + UI.HS, y + (UI.HS + 6) * 3, bad and K.bad or K.acc)
    self.saveBtn:setEnable(bad == nil)
end

function W:onSave()
    local r = self:rect()
    if self:problem(r) then return end
    CHelp.toServer("zoneAdd", {
        sh = CHelp.shKey(self.sh), kind = self.kind, name = self.name:getInternalText(),
        x1 = r.x1, y1 = r.y1, x2 = r.x2, y2 = r.y2, z = self.sz, replace = self.replaceId,
    })
    self:close()
end

function W:onCancelBtn() self:close() end

function ZT.open(sh, kind, name, replaceId)
    if ZT.instance then ZT.instance:close() end
    local w = 360
    local h = UI.HEAD_H + 2 + UI.BTN_H + 4 + 12 + UI.BTN_H + 12 + (UI.HS + 6) * 4 + 10 + (UI.BTN_H + 8) * 2 + UI.PAD
    local win = W:new(40, 140, w, h, t("NewZoneTitle"))
    win.subtitle = sh:getTitle()
    win.sh = sh
    win.kind = kind or CHelp.ZONE_COUNT
    win.presetName = name
    win.replaceId = replaceId
    win:show()
    ZT.instance = win
end
