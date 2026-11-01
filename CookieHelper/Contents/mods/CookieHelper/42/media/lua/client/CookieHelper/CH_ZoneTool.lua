-- Cookie Helper : zone drawing tool (walk from one corner to the other, like the vanilla zone tools)
if isServer() then return end

require "CookieHelper/CH_Client"

CHelp.ZoneTool = CHelp.ZoneTool or {}
local ZT = CHelp.ZoneTool
local C = CHelp.Cl
local UI = CHelp.UI
local t = CHelp.t
local floor = math.floor

local W = UI.Window:derive("CHelpZoneTool")

function W:createChildren()
    UI.Window.createChildren(self)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + UI.PAD
    self.kindCount = UI.button(self, x, y, floor(w / 2) - 3, t("KindCount"), self, W.onKind)
    self.kindCount.kind = CHelp.ZONE_COUNT
    self.kindVeh = UI.button(self, x + floor(w / 2) + 3, y, floor(w / 2) - 3, t("KindVehicle"), self, W.onKind)
    self.kindVeh.kind = CHelp.ZONE_VEHICLE
    y = y + UI.BTN_H + 8
    self.name = UI.entry(self, x, y, w, "")
    self.name:setPlaceholderText(t("ZoneNameHint"))
    y = y + UI.BTN_H + 8
    self.yInfo = y
    y = y + UI.HS * 4 + 16
    UI.button(self, x, y, w, t("SetCorner"), self, W.onCorner)
    y = y + UI.BTN_H + 6
    self.saveBtn = UI.button(self, x, y, floor(w / 2) - 3, t("Save"), self, W.onSave, "mint")
    UI.button(self, x + floor(w / 2) + 3, y, floor(w / 2) - 3, t("Cancel"), self, W.onCancelBtn, "red")
    self:onCorner()
    self:paintKind()
end

function W:paintKind()
    UI.style(self.kindCount, self.kind == CHelp.ZONE_COUNT and "mint" or nil)
    UI.style(self.kindVeh, self.kind == CHelp.ZONE_VEHICLE and "mint" or nil)
end

function W:onKind(btn)
    self.kind = btn.kind
    self:paintKind()
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
        addAreaHighlight(r.x1, r.y1, r.x2, r.y2, self.sz, 1.0, 0.35, 0.35, 0.35)
    else
        addAreaHighlight(r.x1, r.y1, r.x2, r.y2, self.sz, 0.45, 1.0, 0.55, 0.35)
    end
    local x, y = UI.PAD, self.yInfo
    UI.text(self, t("ZoneStep"), x, y, UI.C.muted)
    UI.text(self, t("ZoneStart", self.sx, self.sy, self.sz), x, y + UI.HS + 4, UI.C.text)
    UI.text(self, t("ZoneSize", r.x2 - r.x1, r.y2 - r.y1), x, y + (UI.HS + 4) * 2, UI.C.text)
    UI.text(self, UI.fit(bad or t("ZoneOk"), self.width - 20), x, y + (UI.HS + 4) * 3, bad and UI.C.red or UI.C.mint)
    self.saveBtn:setEnable(bad == nil)
end

function W:onSave()
    local r = self:rect()
    if self:problem(r) then return end
    CHelp.toServer("zoneAdd", {
        sh = CHelp.shKey(self.sh), kind = self.kind, name = self.name:getInternalText(),
        x1 = r.x1, y1 = r.y1, x2 = r.x2, y2 = r.y2, z = self.sz,
    })
    self:close()
end

function W:onCancelBtn() self:close() end

function ZT.open(sh, kind)
    if ZT.instance then ZT.instance:close() end
    local w, h = 330, UI.HEAD_H + UI.PAD + (UI.BTN_H + 8) * 2 + UI.HS * 4 + 16 + (UI.BTN_H + 6) * 2 + UI.PAD
    local win = W:new(40, 140, w, h, t("NewZoneTitle"))
    win.sh = sh
    win.kind = kind or CHelp.ZONE_COUNT
    win:show()
    ZT.instance = win
end
