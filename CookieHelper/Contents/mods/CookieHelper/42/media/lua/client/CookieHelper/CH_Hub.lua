-- Cookie Helper : main window (members, offline add, guests, zones)
if isServer() then return end

require "ISUI/ISTextBox"
require "ISUI/ISModalDialog"
require "CookieHelper/CH_Client"

CHelp.Hub = CHelp.Hub or {}
local Hub = CHelp.Hub
local C = CHelp.Cl
local UI = CHelp.UI
local t = CHelp.t
local floor = math.floor

local W = UI.Window:derive("CHelpHub")

local LIST_M = 108
local LIST_G = 72
local LIST_Z = 108

function W:createChildren()
    UI.Window.createChildren(self)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + UI.PAD + UI.HS * 2 + 10

    local bw = floor((w - 12) / 3)
    self.areaBtn = UI.button(self, x, y, bw, t("Menu_ShowArea"), self, W.onArea)
    UI.button(self, x + bw + 6, y, bw, t("Menu_Finder"), self, W.onFinder)
    UI.button(self, x + (bw + 6) * 2, y, bw, t("Refresh"), self, W.onRefresh)
    y = y + UI.BTN_H + 12

    self.yMembers = y
    y = y + UI.HS + 4
    self.members = UI.makeList(self, x, y, w, LIST_M, UI.HS + 8, self, W.drawMember)
    y = y + LIST_M + 4
    self.addBtn = UI.button(self, x, y, w, t("AddMember"), self, W.onAddMember, "mint")
    y = y + UI.BTN_H + 12

    self.yGuests = y
    y = y + UI.HS + 4
    self.guests = UI.makeList(self, x, y, w - 130, LIST_G, UI.HS + 8, self, W.drawGuest)
    self.kickBtn = UI.button(self, x + w - 124, y, 124, t("KickGuest"), self, W.onKick, "red")
    y = y + LIST_G + 12

    self.yZones = y
    y = y + UI.HS + 4
    self.zones = UI.makeList(self, x, y, w, LIST_Z, UI.HS + 8, self, W.drawZone)
    y = y + LIST_Z + 4
    local zb = floor((w - 12) / 3)
    UI.button(self, x, y, zb, t("Open"), self, W.onZoneOpen, "mint")
    UI.button(self, x + zb + 6, y, zb, t("Rename"), self, W.onZoneRename)
    UI.button(self, x + (zb + 6) * 2, y, zb, t("Delete"), self, W.onZoneDelete, "red")
    y = y + UI.BTN_H + 6
    local hb = floor((w - 6) / 2)
    self.addCountBtn = UI.button(self, x, y, hb, t("NewCountZone"), self, W.onNewZone)
    self.addCountBtn.kind = CHelp.ZONE_COUNT
    self.addVehBtn = UI.button(self, x + hb + 6, y, hb, t("NewVehicleZone"), self, W.onNewZone)
    self.addVehBtn.kind = CHelp.ZONE_VEHICLE

    C.on("zones", self, W.fill)
    C.on("guests", self, W.fill)
    C.on("safehouses", self, W.fill)
    self:fill()
end

function W:onClose()
    C.off(self)
    if Hub.instance == self then Hub.instance = nil end
end

function W:isOwnerOrAdmin()
    return CHelp.isOwner(self.sh, C.me()) or C.isAdmin()
end

local function keepSel(list, pick)
    local it = list.items[list.selected]
    return it and pick(it.item) or nil
end

local function restoreSel(list, pick, want)
    list.selected = 0
    if want == nil then return end
    for i, it in ipairs(list.items) do
        if pick(it.item) == want then list.selected = i return end
    end
end

local function byName(d) return d.name end
local function byId(z) return z.id end

function W:fill()
    self.sh = CHelp.shByKey(self.key)
    if not self.sh then return self:close() end
    local selG = keepSel(self.guests, byName)
    local selZ = keepSel(self.zones, byId)
    self.members:clear()
    self.members:addItem(self.sh:getOwner(), { name = self.sh:getOwner(), owner = true })
    local players = self.sh:getPlayers()
    for i = 0, players:size() - 1 do
        local n = players:get(i)
        if n ~= self.sh:getOwner() then
            self.members:addItem(n, { name = n, guest = C.guestOf(n, self.key) })
        end
    end
    self.members.selected = 0
    self.guests:clear()
    for user, g in pairs(C.guests) do
        if g.sh == self.key then self.guests:addItem(user, { name = user, g = g }) end
    end
    restoreSel(self.guests, byName, selG)
    self.zones:clear()
    local nc, nv = 0, 0
    for _, z in ipairs(C.zonesOf(self.sh)) do
        self.zones:addItem(z.name, z)
        if z.kind == CHelp.ZONE_VEHICLE then nv = nv + 1 else nc = nc + 1 end
    end
    restoreSel(self.zones, byId, selZ)
    local mc = CHelp.svInt("CountZonesPerSafehouse", 0, 20)
    local mv = CHelp.svInt("VehicleZonesPerSafehouse", 0, 20)
    self.addCountBtn:setTitle(t("NewCountZone") .. " (" .. nc .. "/" .. mc .. ")")
    self.addVehBtn:setTitle(t("NewVehicleZone") .. " (" .. nv .. "/" .. mv .. ")")
    self.addCountBtn:setEnable(nc < mc)
    self.addVehBtn:setEnable(nv < mv)
    self.addBtn:setVisible(self:isOwnerOrAdmin() and (CHelp.sv("AllowOfflineAdd") or C.isAdmin()))
end

function W:drawBody()
    local x = UI.PAD
    local y = UI.HEAD_H + UI.PAD
    UI.text(self, UI.fit(t("HubOwner", self.sh:getOwner()), self.width - 20), x, y, UI.C.text)
    UI.text(self, t("HubSize", self.sh:getW(), self.sh:getH(), self.sh:getX(), self.sh:getY()), x, y + UI.HS + 2, UI.C.muted)
    UI.text(self, t("SecMembers"), x, self.yMembers, UI.C.gold)
    UI.text(self, t("SecGuests", CHelp.svInt("GuestMinutes", 1, 240)), x, self.yGuests, UI.C.gold)
    UI.text(self, t("SecZones"), x, self.yZones, UI.C.gold)
    self.areaBtn:setTitle(C.showArea and t("Menu_HideArea") or t("Menu_ShowArea"))
end

function W.drawMember(self, list, d, x, y, w, h)
    local col = d.owner and UI.C.gold or (d.guest and UI.C.muted or UI.C.text)
    UI.text(list, UI.fit(d.name, w - 120), x + 8, y + 4, col)
    local tag = d.owner and t("TagOwner") or (d.guest and t("TagGuest") or t("TagMember"))
    UI.textR(list, tag, x + w - 8, y + 4, UI.C.muted)
end

function W.drawGuest(self, list, d, x, y, w, h)
    local left = math.max(0, floor(d.g.exp - C.serverNow()))
    local s = tostring(floor(left / 60)) .. ":" .. ((left % 60) < 10 and "0" or "") .. tostring(left % 60)
    UI.text(list, UI.fit(d.name, w - 160), x + 8, y + 4, UI.C.text)
    UI.textR(list, C.roleName(d.g.role) .. "  " .. s, x + w - 8, y + 4, UI.C.mint)
end

function W.drawZone(self, list, z, x, y, w, h)
    local kind = z.kind == CHelp.ZONE_VEHICLE and t("KindVehicle") or t("KindCount")
    UI.text(list, kind, x + 8, y + 4, z.kind == CHelp.ZONE_VEHICLE and UI.C.gold or UI.C.mint)
    UI.text(list, UI.fit(z.name, w - 230), x + 90, y + 4, UI.C.text)
    UI.textR(list, (z.x2 - z.x1) .. "x" .. (z.y2 - z.y1) .. "  " .. t("Floor", z.z), x + w - 8, y + 4, UI.C.muted)
end

function W:selZone()
    local it = self.zones.items[self.zones.selected]
    return it and it.item or nil
end

function W:onArea() C.toggleArea() end
function W:onFinder() CHelp.Finder.open(self.sh) end
function W:onRefresh()
    CHelp.toServer("zonesReq", { sh = self.key })
    self:fill()
end

function W:onAddMember()
    if Hub.openAdd then Hub.openAdd(self.sh) end
end

function W:onKick()
    local it = self.guests.items[self.guests.selected]
    if not it then return end
    local m = ISModalDialog:new(self.x + 60, self.y + 160, 320, 150, t("ConfirmKick", it.item.name), true, self, W.onKickDone)
    m.guestName = it.item.name
    m:initialise()
    m:addToUIManager()
end

function W:onKickDone(button)
    if button.internal ~= "YES" then return end
    CHelp.toServer("guestEnd", { user = button.parent.guestName })
end

function W:onZoneOpen()
    local z = self:selZone()
    if not z then return end
    C.mark(z.x1, z.y1, z.x2, z.y2, z.z, 1.0, 0.8, 0.4, 0.35, 3000)
    if z.kind == CHelp.ZONE_VEHICLE then CHelp.Veh.open(self.sh, z) else CHelp.Count.open(self.sh, z) end
end

function W:onZoneRename()
    local z = self:selZone()
    if not z then return end
    local box = ISTextBox:new(self.x + 60, self.y + 120, 280, 180, t("Rename"), z.name, self, W.onRenameDone)
    box.zoneId = z.id
    box:initialise()
    box:addToUIManager()
end

function W:onRenameDone(button)
    if button.internal ~= "OK" then return end
    CHelp.toServer("zoneRename", { sh = self.key, id = button.parent.zoneId, name = button.parent.entry:getText() })
end

function W:onZoneDelete()
    local z = self:selZone()
    if not z then return end
    local m = ISModalDialog:new(self.x + 60, self.y + 160, 320, 150, t("ConfirmDelete", z.name), true, self, W.onDeleteDone)
    m.zoneId = z.id
    m:initialise()
    m:addToUIManager()
end

function W:onDeleteDone(button)
    if button.internal ~= "YES" then return end
    CHelp.toServer("zoneDel", { sh = self.key, id = button.parent.zoneId })
end

function W:onNewZone(btn)
    if CHelp.ZoneTool then CHelp.ZoneTool.open(self.sh, btn.kind) end
end

function Hub.open(sh)
    if not sh then return end
    if Hub.instance then Hub.instance:close() end
    local w = 480
    local h = UI.HEAD_H + UI.PAD + UI.HS * 2 + 10 + UI.BTN_H + 12
        + UI.HS + 4 + LIST_M + 4 + UI.BTN_H + 12
        + UI.HS + 4 + LIST_G + 12
        + UI.HS + 4 + LIST_Z + 4 + UI.BTN_H + 6 + UI.BTN_H + UI.PAD
    local x, y = UI.center(w, h)
    local win = W:new(x, y, w, h, "Cookie Helper  -  " .. sh:getTitle())
    win.sh = sh
    win.key = CHelp.shKey(sh)
    win:show()
    Hub.instance = win
    CHelp.toServer("zonesReq", { sh = win.key })
end

-- ------------------------------------------------------------------ add member (offline ok)
local A = UI.Window:derive("CHelpAddMember")

function A:createChildren()
    UI.Window.createChildren(self)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + UI.PAD + UI.HS * 2 + 8
    self.entry = UI.entry(self, x, y, w, "")
    self.entry.onTextChange = function() self:fill() end
    y = y + UI.BTN_H + 6
    self.list = UI.makeList(self, x, y, w, self.height - y - UI.BTN_H - UI.PAD - 8, UI.HS + 8, self, nil, A.onPick)
    local by = self.height - UI.BTN_H - UI.PAD
    UI.button(self, x, by, floor(w / 2) - 3, t("Add"), self, A.onAdd, "mint")
    UI.button(self, x + floor(w / 2) + 3, by, floor(w / 2) - 3, t("Cancel"), self, A.onCancel, "red")
    self.known = {}
    C.on("known", self, A.onKnown)
    CHelp.toServer("knownReq", {})
end

function A:onClose() C.off(self) end

function A:onKnown(list)
    self.known = list or {}
    self:fill()
end

function A:fill()
    local q = string.lower(self.entry:getInternalText() or "")
    self.list:clear()
    for _, n in ipairs(self.known) do
        if (q == "" or string.find(string.lower(n), q, 1, true)) and not self.sh:playerAllowed(n) then
            self.list:addItem(n, n)
        end
    end
end

function A:onPick(name)
    self.entry:setText(name)
end

function A:onAdd()
    local name = self.entry:getInternalText()
    if not name or name == "" then return end
    CHelp.toServer("addMember", { sh = CHelp.shKey(self.sh), name = name })
    self:close()
end

function A:onCancel() self:close() end

function A:drawBody()
    UI.text(self, UI.fit(t("AddHelp1"), self.width - 20), UI.PAD, UI.HEAD_H + UI.PAD, UI.C.text)
    UI.text(self, UI.fit(t("AddHelp2"), self.width - 20), UI.PAD, UI.HEAD_H + UI.PAD + UI.HS + 2, UI.C.muted)
end

function Hub.openAdd(sh)
    local w, h = 360, 380
    local x, y = UI.center(w, h)
    local win = A:new(x + 40, y + 20, w, h, t("AddMember"))
    win.sh = sh
    win:show()
end
