-- Cookie Helper : floating cookie button at the screen edge
-- Sits right under the Cookie Express button (same strip) until you drag it somewhere else;
-- the dragged position is remembered. Badge = guests waiting for your answer.
-- Click = quick menu. Costs one small panel draw per frame.
if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISContextMenu"
require "CookieHelper/CH_Client"

CHelp.Dock = CHelp.Dock or {}
local D = CHelp.Dock
local C = CHelp.Cl
local T = CHelp.Th
local K = T.C
local UI = CHelp.UI
local t = CHelp.t
local floor = math.floor

local SIZE = 56
local POS_FILE = "CookieHelper_dock.txt"

local Btn = ISPanel:derive("CHelpDock")

function Btn:new(x, y)
    local o = ISPanel.new(self, x, y, SIZE, SIZE)
    o.background = false
    o.moveWithMouse = false
    o.pressed = false
    o.dragging = false
    o.moved = 0
    return o
end

-- under the Cookie Express button when it exists and we were never dragged away
function Btn:follow()
    if D.detached then return end
    local ok, eb = pcall(function() return CKX and CKX.UI and CKX.UI.btn end)
    if ok and eb and eb:getIsVisible() then
        local x = floor(eb:getX() + (eb.width - SIZE) / 2)
        local y = floor(eb:getY() + eb.height + 2)
        if y + SIZE > getCore():getScreenHeight() then y = floor(eb:getY() - SIZE - 2) end
        if x ~= self:getX() then self:setX(x) end
        if y ~= self:getY() then self:setY(y) end
    end
end

function Btn:clamp()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    self:setX(math.max(0, math.min(self:getX(), sw - SIZE)))
    self:setY(math.max(0, math.min(self:getY(), sh - SIZE)))
end

function Btn:prerender()
    self:follow()
    local over = self:isMouseOver()
    T.circle(self, 2, 4, SIZE - 4, K.black, 0.35)
    T.circle(self, 0, 0, SIZE - 2, (over or self.pressed) and K.acc or K.bg)
    T.circle(self, 2, 2, SIZE - 6, K.bg)
    local tx = T.tex("cookie_64")
    if tx then self:drawTextureScaled(tx, 7, 7, SIZE - 16, SIZE - 16, 1, 1, 1, 1) end
    local n = C.pendingAsks()
    if n > 0 then
        local s = n > 9 and "9+" or tostring(n)
        local bw = math.max(UI.HS + 4, T.tw(s) + 10)
        T.rrect(self, SIZE - bw + 2, -2, bw, UI.HS + 4, floor((UI.HS + 4) / 2), K.acc)
        T.textC(self, s, SIZE - bw / 2 + 2, 0, K.onAcc)
    end
    if over and not self.dragging then
        local s = t("DockTip")
        local w = T.tw(s) + 20
        local left = self:getX() > getCore():getScreenWidth() / 2
        local x = left and (-w - 8) or (SIZE + 8)
        T.rrect(self, x, floor((SIZE - UI.HS - 10) / 2), w, UI.HS + 10, 8, K.bar, 0.95)
        T.text(self, s, x + 10, floor((SIZE - UI.HS) / 2), K.text)
    end
end

function Btn:onMouseDown(x, y)
    self.pressed = true
    self.moved = 0
    return true
end

function Btn:onMouseMove(dx, dy)
    if not self.pressed then return end
    self.moved = self.moved + math.abs(dx) + math.abs(dy)
    if self.moved > 4 then self.dragging = true end
    if self.dragging then
        D.detached = true
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
end
Btn.onMouseMoveOutside = Btn.onMouseMove

function Btn:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        self.pressed = false
        self:clamp()
        D.save()
        return true
    end
    if self.pressed then
        self.pressed = false
        D.menu(self)
    end
    return true
end

function Btn:onMouseUpOutside(x, y)
    if self.dragging then
        self.dragging = false
        self:clamp()
        D.save()
    end
    self.pressed = false
end

function Btn:onRightMouseUp(x, y)
    D.menu(self)
    return true
end

-- ------------------------------------------------------------------ quick menu
local function icon(opt, name)
    local tx = T.tex(name)
    if opt and tx then opt.iconTexture = tx end
end

function D.menu(btn)
    local p = C.player()
    if not p then return end
    local ctx = ISContextMenu.get(0, btn:getAbsoluteX() + SIZE, btn:getAbsoluteY())
    icon(ctx:addOption(t("MyHouses"), nil, function() if CHelp.Houses then CHelp.Houses.open() end end), "px_key")
    local sh = C.pickSafehouse(floor(p:getX()), floor(p:getY()))
    if sh then
        icon(ctx:addOption(t("Menu_Zones"), sh, function(s) CHelp.Hub.open(s) end), "px_crate")
        icon(ctx:addOption(t("Menu_Finder"), sh, function(s) CHelp.Finder.open(s) end), "px_search")
    end
    if #C.myHouses() > 0 then
        icon(ctx:addOption(C.showArea and t("Menu_HideArea") or t("Menu_ShowArea"), nil, C.toggleArea), "px_search")
    end
    local n = C.pendingAsks()
    if n > 0 then
        icon(ctx:addOption(t("DockAsks", n), nil, function()
            for _, w in pairs(C.asks) do w:bringToTop() end
        end), "px_medkit")
    end
    if D.detached and CKX and CKX.UI and CKX.UI.btn then
        icon(ctx:addOption(t("DockAttach"), nil, function()
            D.detached = false
            D.save()
        end), "ic_link")
    end
end

-- ------------------------------------------------------------------ position file
function D.save()
    pcall(function()
        local w = getFileWriter(POS_FILE, true, false)
        if not w then return end
        local b = D.btn
        w:write((D.detached and "1" or "0") .. "|" .. tostring(b and b:getX() or 0) .. "|" .. tostring(b and b:getY() or 0) .. "\n")
        w:close()
    end)
end

function D.load()
    local x, y = 12, floor(getCore():getScreenHeight() * 0.42)
    pcall(function()
        local r = getFileReader(POS_FILE, false)
        if not r then return end
        local line = r:readLine()
        r:close()
        if not line then return end
        local d, sx, sy = string.match(line, "^(%d)|([%-%d%.]+)|([%-%d%.]+)")
        if d then
            D.detached = d == "1"
            x, y = floor(tonumber(sx) or x), floor(tonumber(sy) or y)
        end
    end)
    return x, y
end

function D.show()
    if D.btn then return end
    local x, y = D.load()
    D.btn = Btn:new(x, y)
    D.btn:initialise()
    D.btn:addToUIManager()
    D.btn:setVisible(true)
    D.btn:clamp()
end

Events.OnGameStart.Add(function() D.show() end)
Events.OnResolutionChange.Add(function() if D.btn then D.btn:clamp() end end)
