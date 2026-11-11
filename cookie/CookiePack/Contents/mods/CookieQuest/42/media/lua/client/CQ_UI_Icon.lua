-- Cookie Quest - sidebar icon (same slot style as the old challenges calendar) or a floating icon
require "CQ_UI_Kit"

CQIcon = CQIcon or {}
local C = CQUI.C
local T = CQC.txt

-- ===================================================================== state
function CQIcon.signature()
    local parts = {}
    local pub = CQC.pub
    if pub then
        for _, e in ipairs(pub.events or {}) do
            if e.status == "sched" or e.status == "live" then parts[#parts + 1] = e.id .. e.status end
        end
        for _, b in ipairs(pub.board or {}) do parts[#parts + 1] = b.id end
    end
    for _, i in ipairs(CQC.activeInst()) do parts[#parts + 1] = i.id end
    return table.concat(parts, ",")
end

function CQIcon.isOn()
    local pub = CQC.pub
    if pub then
        if pub.buffs and #pub.buffs > 0 then return true end
        for _, e in ipairs(pub.events or {}) do
            if e.status == "sched" or e.status == "live" then return true end
        end
    end
    if #CQC.activeInst() > 0 then return true end
    if CQC.me and CQC.me.pen then return true end
    return false
end

function CQIcon.hasNew()
    local sig = CQIcon.signature()
    return sig ~= "" and sig ~= (CQC.cfg.seen or "")
end

function CQIcon.markSeen()
    CQC.cfg.seen = CQIcon.signature()
    CQC.saveCfg()
end

function CQIcon.tooltip()
    local t = T("IGUI_CQ_IconTip")
    local nAct = #CQC.activeInst()
    if nAct > 0 then t = t .. "\n" .. T("IGUI_CQ_IconActive", nAct) end
    return t
end

function CQIcon.click()
    if CQBoard and CQBoard.toggle then CQBoard.toggle() end
end

function CQIcon.draw(el, w, h, over)
    local tex = CQUI.tex(CQIcon.isOn() and "cq_icon_on" or "cq_icon_off")
    local s = math.min(w, h)
    local x, y = (w - s) / 2, (h - s) / 2
    local a = 1
    local isNew = CQIcon.hasNew()
    if isNew then
        local t = getTimestampMs() / 260
        a = 0.75 + 0.25 * math.sin(t)
    end
    if tex then
        el:drawTextureScaledAspect(tex, x, y, s, s, a, 1, 1, 1)
    else
        el:drawRect(x + 4, y + 4, s - 8, s - 8, 0.9, C.accent[1], C.accent[2], C.accent[3])
    end
    if over then el:drawRectBorder(x + 1, y + 1, s - 2, s - 2, 0.6, C.accent[1], C.accent[2], C.accent[3]) end
    if isNew then
        local d = math.max(8, math.floor(s * 0.22))
        el:drawRect(x + s - d - 2, y + 2, d, d, 1, C.bad[1], C.bad[2], C.bad[3])
    end
end

function CQIcon.context()
    local ctx = ISContextMenu.get(0, getMouseX(), getMouseY())
    ctx:addOption(T("IGUI_CQ_Ctx_Open"), nil, function() CQIcon.click() end)
    if CQC.isAdmin() then
        ctx:addOption(T("IGUI_CQ_Ctx_Admin"), nil, function() if CQAdmin then CQAdmin.toggle() end end)
    end
    if CQC.cfg.icon == "float" then
        ctx:addOption(T("IGUI_CQ_Ctx_ToSidebar"), nil, function() CQIcon.setMode("side") end)
    else
        ctx:addOption(T("IGUI_CQ_Ctx_ToFloat"), nil, function() CQIcon.setMode("float") end)
    end
    local hudOn = CQC.cfg.hud ~= "0"
    ctx:addOption(T(hudOn and "IGUI_CQ_Ctx_HudOff" or "IGUI_CQ_Ctx_HudOn"), nil, function()
        CQC.cfgSet("hud", hudOn and "0" or "1")
    end)
end

-- ===================================================================== floating icon
CQIcon.Float = ISPanel:derive("CQIcon_Float")
local F = CQIcon.Float

function F:new(x, y, s)
    local o = ISPanel.new(self, x, y, s, s)
    o.background = false
    return o
end

function F:prerender() end

function F:render()
    CQIcon.draw(self, self.width, self.height, self:isMouseOver())
    if self:isMouseOver() and not self.held then
        local tip = CQIcon.tooltip()
        local lines = CQUI.wrap(tip, UIFont.Small, 240)
        local lh = CQUI.fh(UIFont.Small) + 2
        local w = 0
        for i = 1, #lines do w = math.max(w, CQUI.tw(UIFont.Small, lines[i])) end
        local bx = self.width + 6
        CQUI.rbox(self, bx, 0, w + 14, #lines * lh + 8, C.dark, 0.92, 5)
        for i = 1, #lines do CQUI.text(self, lines[i], bx + 7, 4 + (i - 1) * lh, C.text) end
    end
end

function F:onMouseDown(x, y)
    self.held = true
    self.moved = false
    self.sx, self.sy = getMouseX(), getMouseY()
    return true
end

function F:onMouseMove(dx, dy)
    if self.held then
        if not self.moved and math.abs(getMouseX() - self.sx) + math.abs(getMouseY() - self.sy) > 4 then self.moved = true end
        if self.moved then
            self:setX(self:getX() + dx)
            self:setY(self:getY() + dy)
        end
    end
end
F.onMouseMoveOutside = F.onMouseMove

function F:onMouseUp(x, y)
    local moved = self.moved
    self.held = false
    self.moved = false
    if moved then
        CQC.cfg.iconX = tostring(math.floor(self:getX()))
        CQC.cfg.iconY = tostring(math.floor(self:getY()))
        CQC.saveCfg()
    else
        CQIcon.click()
    end
    return true
end

function F:onMouseUpOutside(x, y)
    if self.moved then
        CQC.cfg.iconX = tostring(math.floor(self:getX()))
        CQC.cfg.iconY = tostring(math.floor(self:getY()))
        CQC.saveCfg()
    end
    self.held = false
    self.moved = false
end

function F:onRightMouseUp(x, y)
    CQIcon.context()
    return true
end

-- ===================================================================== sidebar button
local function sideSize(inst)
    local ref = inst and inst.invBtn
    local w = ref and ref:getWidth() or 48
    local h = ref and ref:getHeight() or 48
    return w, h, (ref and ref:getX()) or 2
end

local function makeSide(inst)
    if not inst then return nil end
    if inst.cqBtn then return inst.cqBtn end
    local w, h, x = sideSize(inst)
    local y = inst:getHeight() + 12
    local btn = ISButton:new(x, y, w, h, "", nil, function() CQIcon.click() end)
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)
    btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.internal = "CookieQuestBtn"
    btn.tooltip = CQIcon.tooltip()
    btn.render = function(self)
        self.tooltip = CQIcon.tooltip()
        CQIcon.draw(self, self:getWidth(), self:getHeight(), self:isMouseOver())
        if ISButton.updateTooltip then ISButton.updateTooltip(self) end
    end
    btn.onRightMouseUp = function(self, mx, my)
        CQIcon.context()
        return true
    end
    inst:addChild(btn)
    inst.cqBtn = btn
    if inst:getHeight() < btn:getBottom() then inst:setHeight(btn:getBottom()) end
    return btn
end

function CQIcon.apply()
    local inst = ISEquippedItem and ISEquippedItem.instance
    local mode = CQC.cfg.icon or "side"
    local btn = inst and makeSide(inst)
    -- sidebar too long for this screen (small resolution / many mod buttons): float instead
    if btn and CQC.cfg.icon == nil then
        local ok, bottom = pcall(function() return btn:getAbsoluteY() + btn:getHeight() end)
        if ok and bottom and bottom > getCore():getScreenHeight() - 4 then
            mode = "float"
            CQ.log("sidebar too long, using floating icon")
        end
    end
    if mode == "float" then
        if btn then btn:setVisible(false) end
        if not CQIcon.float then
            local s = btn and btn:getWidth() or 48
            local x = CQC.cfgNum("iconX", getCore():getScreenWidth() - s - 60)
            local y = CQC.cfgNum("iconY", 140)
            CQIcon.float = F:new(CQ.clamp(x, 0, getCore():getScreenWidth() - s), CQ.clamp(y, 0, getCore():getScreenHeight() - s), s)
            CQIcon.float:initialise()
            CQIcon.float:instantiate()
            CQIcon.float:addToUIManager()
        end
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        local f = CQIcon.float
        f:setX(CQ.clamp(f:getX(), 0, math.max(0, sw - f.width)))
        f:setY(CQ.clamp(f:getY(), 0, math.max(0, sh - f.height)))
        f:setVisible(true)
    else
        if btn then btn:setVisible(true) end
        if CQIcon.float then CQIcon.float:setVisible(false) end
    end
end

function CQIcon.setMode(mode)
    CQC.cfgSet("icon", mode)
    CQIcon.apply()
end

local pending = false
local function onTickInstall()
    if not pending then return end
    if not (ISEquippedItem and ISEquippedItem.instance) then return end
    pending = false
    Events.OnTick.Remove(onTickInstall)
    CQIcon.apply()
    if not CQIcon._wrapped and ISEquippedItem then
        CQIcon._wrapped = true
        local orig = ISEquippedItem.initialise
        ISEquippedItem.initialise = function(self, ...)
            local r = orig and orig(self, ...)
            if self.playerNum == 0 or self.playerNum == nil then
                self.cqBtn = nil
                pending = true
                Events.OnTick.Add(onTickInstall)
            end
            return r
        end
    end
end

-- window resized / resolution changed: re-check whether the sidebar slot is still on screen
Events.OnResolutionChange.Add(function()
    if ISEquippedItem and ISEquippedItem.instance and ISEquippedItem.instance.cqBtn then CQIcon.apply() end
end)

Events.OnCreatePlayer.Add(function(playerNum, player)
    if playerNum ~= 0 then return end
    CQC.loadCfg()
    pending = true
    Events.OnTick.Add(onTickInstall)
end)

return CQIcon
