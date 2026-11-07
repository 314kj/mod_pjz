-- Cookie Helper : zone drawing tool - click one corner on the ground, click the other, save.
-- "Add a part" keeps the rectangle and picks another one: L / Z shapes or two rooms in one zone.
-- Zones may overlap each other.
-- While picking, a see-through layer over the world catches the clicks (so the character does
-- not walk / swing), the tile under the mouse lights up and the rectangle follows the mouse.
-- Right-click or Esc stops picking. The zone is on the floor the character stands on.
if isServer() then return end

require "ISUI/ISUIElement"
require "CookieHelper/CH_Client"

CHelp.ZoneTool = CHelp.ZoneTool or {}
local ZT = CHelp.ZoneTool
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local t = CHelp.t
local floor = math.floor

-- a zone table from a list of rectangles (first + parts)
local function asZone(all)
    local z = { x1 = all[1].x1, y1 = all[1].y1, x2 = all[1].x2, y2 = all[1].y2, parts = {} }
    for i = 2, #all do z.parts[#z.parts + 1] = all[i] end
    return z
end

-- ------------------------------------------------------------------ the click-catching layer
local Pick = ISUIElement:derive("CHelpZonePick")

function Pick:new(tool)
    local o = ISUIElement:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    setmetatable(o, self)
    self.__index = self
    o.tool = tool
    o:setAnchorRight(true)
    o:setAnchorBottom(true)
    return o
end

-- world tile under the mouse on the tool's floor
function Pick:tile()
    local z = self.tool.sz
    local mx, my = getMouseX(), getMouseY()   -- raw pixels: screenToIso applies the zoom itself
    local ok, wx, wy = pcall(function() return screenToIsoX(0, mx, my, z), screenToIsoY(0, mx, my, z) end)
    if not ok or not wx then return nil end
    return floor(wx), floor(wy)
end

function Pick:prerender() end

function Pick:render()
    local x, y = self:tile()
    self.hx, self.hy = x, y
    if not x then return end
    local tool = self.tool
    local label = tool.ax and t("ZonePickB") or t("ZonePickA")
    local mx, my = self:getMouseX(), self:getMouseY()
    local w = T.tw(label) + 20
    T.rrect(self, mx + 18, my + 14, w, UI.HS + 10, 8, K.surf, 0.92)
    T.text(self, label, mx + 28, my + 19, K.text)
end

function Pick:onMouseDown(x, y)
    local tx, ty = self:tile()
    if tx then self.tool:onPicked(tx, ty) end
    return true
end

function Pick:onMouseUp() return true end
function Pick:onRightMouseDown() return true end
function Pick:onRightMouseUp()
    self.tool:stopPicking()
    return true
end
function Pick:onMouseWheel() return false end

-- ------------------------------------------------------------------ the tool window
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
    local half0 = floor((w - 8) / 2)
    self.pickBtn = UI.button(self, x, y, half0, t("ZonePickAgain"), self, W.onPickBtn, "sec")
    self.pickBtn:setIcon("refresh")
    self.partBtn = UI.button(self, x + half0 + 8, y, w - half0 - 8, t("ZoneAddPart"), self, W.onAddPart, "soft")
    self.partBtn:setIcon("plus")
    self.partBtn.tooltip = t("ZoneAddPartTip")
    y = y + UI.BTN_H + 8
    local half = floor((w - 8) / 2)
    UI.button(self, x, y, half, t("Cancel"), self, W.onCancelBtn, "ghost")
    self.saveBtn = UI.button(self, x + half + 8, y, w - half - 8, t("Save"), self, W.onSave, "pri")
    local p = C.player()
    self.sz = p and floor(p:getZ()) or 0
    self.parts = {}
    self:startPicking()
end

function W:onKind(id)
    self.kind = id
end

function W:startPicking()
    self.ax, self.ay, self.bx, self.by = nil, nil, nil, nil
    local p = C.player()
    -- every part of a zone is on one floor: the floor is fixed once the first part is kept
    if p and #(self.parts or {}) == 0 then self.sz = floor(p:getZ()) end
    if not self.picker then
        self.picker = Pick:new(self)
        self.picker:initialise()
        self.picker:addToUIManager()
    end
    self.picker:setVisible(true)
    self:bringToTop()
end

function W:stopPicking()
    if self.picker then
        self.picker:setVisible(false)
        self.picker:removeFromUIManager()
        self.picker = nil
    end
end

function W:onPicked(x, y)
    if not self.ax then
        self.ax, self.ay = x, y
        getSoundManager():playUISound("UISelectListItem")
        return
    end
    self.bx, self.by = x, y
    getSoundManager():playUISound("UISelectListItem")
    self:stopPicking()
end

-- start over: every part goes
function W:onPickBtn()
    self.parts = {}
    self:startPicking()
end

-- keep this rectangle and pick one more
function W:onAddPart()
    local r = self:rect()
    if not r or self:problem(r) or #self.parts + 2 > CHelp.ZONE_MAX_PARTS then return end
    self.parts[#self.parts + 1] = r
    self:startPicking()
end

-- rectangle from corner A to corner B (or to the tile under the mouse while picking)
function W:rect()
    if not self.ax then return nil end
    local bx, by = self.bx, self.by
    if not bx and self.picker then bx, by = self.picker.hx, self.picker.hy end
    if not bx then bx, by = self.ax, self.ay end
    return {
        x1 = math.min(self.ax, bx), y1 = math.min(self.ay, by),
        x2 = math.max(self.ax, bx) + 1, y2 = math.max(self.ay, by) + 1,
    }
end

function W:problem(r)
    if not r then return t("ZonePickA") end
    local side = CHelp.svInt("MaxZoneSide", 2, 200)
    if r.x2 - r.x1 > side or r.y2 - r.y1 > side then return t("Msg_ZoneTooBig", side) end
    if not CHelp.rectInside(r, CHelp.shRect(self.sh)) then return t("Msg_ZoneOutside") end
    if not self.bx then return t("ZonePickB") end
    return nil
end

function W:drawBody()
    local p = C.player()
    if not p then return end
    -- the house outline, so it is clear where the zone may go
    local hr = CHelp.shRect(self.sh)
    addAreaHighlight(hr.x1, hr.y1, hr.x2, hr.y2, self.sz, K.text3[1], K.text3[2], K.text3[3], 0.12)
    local hx, hy = self.picker and self.picker.hx, self.picker and self.picker.hy
    if hx and not self.ax then
        addAreaHighlight(hx, hy, hx + 1, hy + 1, self.sz, K.acc[1], K.acc[2], K.acc[3], 0.6)
    end
    for _, pr in ipairs(self.parts) do
        addAreaHighlight(pr.x1, pr.y1, pr.x2, pr.y2, self.sz, K.acc[1], K.acc[2], K.acc[3], 0.35)
    end
    local r = self:rect()
    local bad = self:problem(r)
    if r then
        local col = (bad and self.bx) and K.bad or K.acc
        if bad and not self.bx and (r.x2 - r.x1 > CHelp.svInt("MaxZoneSide", 2, 200) or not CHelp.rectInside(r, hr)) then col = K.bad end
        addAreaHighlight(r.x1, r.y1, r.x2, r.y2, self.sz, col[1], col[2], col[3], 0.35)
    end
    -- picking an extra part: the parts so far already make a valid zone
    if not r and #self.parts > 0 then bad = self.picker and t("ZonePickAPart") or nil end
    local x, y, w = UI.PAD, self.yInfo, self.width - UI.PAD * 2
    T.rrect(self, x, y - 6, w, (UI.HS + 6) * 4 + 6, UI.RC, K.surf)
    T.text(self, T.fit(t("ZoneStepMouse"), w - 20), x + 10, y, K.text3)
    if self.ax then
        T.text(self, t("ZoneStart", self.ax, self.ay, self.sz), x + 10, y + UI.HS + 6, K.text)
    else
        T.text(self, t("ZoneFloor", self.sz), x + 10, y + UI.HS + 6, K.text)
    end
    if #self.parts > 0 then
        local all = self:allRects()
        if #all > 0 then T.text(self, t("ZoneSizeParts", CHelp.zoneTiles(asZone(all)), #all), x + 10, y + (UI.HS + 6) * 2, K.text) end
    elseif r then T.text(self, t("ZoneSize", r.x2 - r.x1, r.y2 - r.y1), x + 10, y + (UI.HS + 6) * 2, K.text) end
    local waiting = self.picker ~= nil and bad ~= nil and (bad == t("ZonePickA") or bad == t("ZonePickB") or bad == t("ZonePickAPart"))
    local ic, col = bad and "warn" or "check", bad and K.bad or K.acc
    if waiting then ic, col = "dot", K.warn end
    T.icon(self, ic, x + 10, y + (UI.HS + 6) * 3 + 1, UI.HS - 2, col)
    T.text(self, T.fit(bad or t("ZoneOk"), w - 40), x + 14 + UI.HS, y + (UI.HS + 6) * 3, col)
    -- savable: at least one finished rectangle and the one being picked (if complete) is fine
    self.saveBtn:setEnable(#self:allRects() > 0 and not (r and self.bx and bad))
    self.pickBtn:setTitle(self.picker and t("ZonePicking") or t("ZonePickAgain"))
    self.partBtn:setEnable(r ~= nil and bad == nil and self.bx ~= nil and #self.parts + 2 <= CHelp.ZONE_MAX_PARTS)
    self.partBtn:setTitle(t("ZoneAddPartN", #self.parts + 2))
end

-- the finished parts + the rectangle being picked (when it is complete)
function W:allRects()
    local out = {}
    for _, pr in ipairs(self.parts) do out[#out + 1] = pr end
    local r = self:rect()
    if r and self.bx and not self:problem(r) then out[#out + 1] = r end
    return out
end

function W:onSave()
    local all = self:allRects()
    if #all == 0 then return end
    local r = self:rect()
    if r and self.bx and self:problem(r) then return end
    local first = all[1]
    local parts = {}
    for i = 2, #all do parts[#parts + 1] = { x1 = all[i].x1, y1 = all[i].y1, x2 = all[i].x2, y2 = all[i].y2 } end
    CHelp.toServer("zoneAdd", {
        sh = CHelp.shKey(self.sh), kind = self.kind, name = self.name:getInternalText(),
        x1 = first.x1, y1 = first.y1, x2 = first.x2, y2 = first.y2, z = self.sz, replace = self.replaceId,
        parts = (#parts > 0) and parts or nil,
    })
    self:close()
end

function W:onCancelBtn() self:close() end

function W:onClose()
    self:stopPicking()
    if ZT.instance == self then ZT.instance = nil end
end

function W:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE and self.picker ~= nil
end

function W:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE and self.picker then self:stopPicking() end
end

function ZT.open(sh, kind, name, replaceId)
    if ZT.instance then ZT.instance:close() end
    local w = 380
    local h = UI.HEAD_H + 2 + UI.BTN_H + 4 + 12 + UI.BTN_H + 12 + (UI.HS + 6) * 4 + 10 + (UI.BTN_H + 8) * 2 + UI.PAD
    local win = W:new(40, 140, 420, h, t("NewZoneTitle"))
    win.subtitle = sh:getTitle()
    win.sh = sh
    win.kind = kind or CHelp.ZONE_COUNT
    win.presetName = name
    win.replaceId = replaceId
    win:show()
    win:setWantKeyEvents(true)
    ZT.instance = win
end
