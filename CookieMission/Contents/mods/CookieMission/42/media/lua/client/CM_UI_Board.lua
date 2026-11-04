-- Cookie Mission - player board (3 daily cards) + sidebar icon
require "CM_UI_Kit"
require "CM_UI_HUD"

local C = CMUI.C
local T = CMC.txt

CMBoard = CMBoard or {}
CMBoard.Win = CMUI.Window:derive("CMBoard_Win")
local BW = CMBoard.Win

local confirm = { slot = 0, at = 0 }

function BW:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = T("IGUI_CM_Title")
    o.subtitle = T("IGUI_CM_Subtitle")
    o.titleIcon = "cm_icon"
    o.bgAlpha = 0.78
    return o
end

-- reward lines of a tier, straight from CM.DROPS so the board never lies
local function rewardLines(tier)
    local out = {}
    for _, d in ipairs(CM.DROPS[tier] or {}) do
        local name = T("IGUI_CM_Pool_" .. d.p)
        local s
        if d.c >= 100 then s = name .. " x" .. tostring(d.r)
        else s = T("IGUI_CM_Chance", name, d.c) end
        if d.alt and d.c < 100 then s = s .. " " .. T("IGUI_CM_Else", T("IGUI_CM_Pool_" .. d.alt)) end
        out[#out + 1] = s
    end
    return out
end
CMBoard.rewardLines = rewardLines

local function statusBadge(win, x, y, c)
    if c.status == "open" then
        return CMUI.badge(win, x, y, T("IGUI_CM_St_open"), C.good)
    elseif c.status == "live" then
        local left = CMC.left(c.left, CMC.pubAt) or 0
        return CMUI.badge(win, x, y, T("IGUI_CM_St_live", c.n or 0, c.cap or 0, CM.clock(left)), C.gold)
    elseif c.status == "cool" then
        local left = CMC.left(c.coolLeft, CMC.pubAt) or 0
        return CMUI.badge(win, x, y, T("IGUI_CM_St_cool", CM.clock(left)), C.dim)
    end
    return CMUI.badge(win, x, y, T("IGUI_CM_St_none"), C.bad)
end

-- small glass stat chip: LABEL over value; returns nothing
local function chip(win, x, y, w, h, label, value, tc)
    CMUI.glass(win, x, y, w, h, { tint = C.dark, a = 0.45, rad = 6, rim = tc, rimA = 0.22, shine = 0.3 })
    local fs = UIFont.Small
    CMUI.textC(win, CMUI.fit(label, fs, w - 6), x + w / 2, y + CMUI.S(4), C.faint, 1, fs)
    CMUI.textC(win, CMUI.fit(value, fs, w - 6), x + w / 2, y + CMUI.S(4) + CMUI.fh(fs), C.text, 1, fs)
end

local function drawCard(win, x, y, w, h, c)
    local S = CMUI.S
    local tier = c.tier or c.slot
    local tc = CMUI.tierColor(tier)
    local fs, fm = UIFont.Small, UIFont.Medium
    local lh = CMUI.fh(fs) + S(3)
    local myRun = CMC.run()
    local mine = myRun and myRun.slot == c.slot
    local hot = win:isMouseOver() and win:getMouseX() >= x and win:getMouseX() < x + w and win:getMouseY() >= y and win:getMouseY() < y + h
    -- glass card with the tier's light on top
    CMUI.glow(win, x + w / 2, y + S(6), w * 0.55, S(70), tc, (mine or hot) and 0.30 or 0.18)
    CMUI.glass(win, x, y, w, h, { tint = C.panel, a = 0.50, rad = 10, rim = tc, rimA = (mine or hot) and 0.85 or 0.40 })
    CMUI.brackets(win, x, y, w, h, tc, (mine or hot) and 1 or 0.65, S(14), 2)
    local ix = x + S(14)
    local iw = w - S(28)
    -- header: rank name + pips
    local cy = y + S(12)
    CMUI.text(win, CMC.tierName(tier), ix, cy, tc, 1, fm)
    local ps = S(12)
    for i = 1, tier do
        local px = ix + iw - i * (ps + S(4)) + S(4)
        CMUI.icon(win, tier == 3 and "cm_skull" or "cm_pip", px, cy + (CMUI.fh(fm) - ps) / 2, ps, tier == 3 and C.bad or tc, 1)
    end
    cy = cy + CMUI.fh(fm) + S(8)
    CMUI.hline(win, ix - S(6), cy, iw + S(12), tc, 0.9)
    cy = cy + S(10)
    if c.status == "none" or not c.type then
        CMUI.para(win, T("IGUI_CM_NoPlaceLong"), ix, cy, iw, C.dim, fs, 6)
        statusBadge(win, ix, y + h - S(46) - CMUI.fh(fs) - S(12), c)
        CMUI.btn(win, ix, y + h - S(46), iw, S(32), T("IGUI_CM_NotNow"), nil, "primary", { disabled = true })
        return
    end
    -- mission type with its icon in a lit frame
    local is = S(46)
    CMUI.glow(win, ix + is / 2, cy + is / 2, is * 0.9, is * 0.9, tc, 0.32)
    CMUI.rbox(win, ix, cy, is, is, C.dark, 0.55, 10)
    CMUI.rborder(win, ix, cy, is, is, tc, 0.6, 10)
    if not CMUI.icon(win, "cm_t_" .. c.type, ix + S(5), cy + S(5), is - S(10), tc, 1) then
        CMUI.textC(win, "?", ix + is / 2, cy + (is - CMUI.fh(fm)) / 2, tc, 1, fm)
    end
    local tx = ix + is + S(12)
    CMUI.text(win, CMUI.fit(CMC.typeName(c.type), fm, iw - is - S(12)), tx, cy, C.white, 1, fm)
    CMUI.para(win, CMC.goalText(c.type, c.goal), tx, cy + CMUI.fh(fm) + S(3), iw - is - S(12), C.dim, fs, 3)
    cy = cy + math.max(is, CMUI.fh(fm) + S(3) + CMUI.paraH(CMC.goalText(c.type, c.goal), iw - is - S(12), fs, 3)) + S(12)
    -- where
    local place = CMC.placeText(c)
    if (c.floors or 1) > 1 then place = place .. "  " .. T("IGUI_CM_Floors", c.floors) end
    if c.pinned then place = place .. "  " .. T("IGUI_CM_Pinned") end
    CMUI.text(win, CMUI.fit(place, fs, iw), ix, cy, C.gold)
    cy = cy + lh + S(6)
    -- stat chips
    local chH = CMUI.fh(fs) * 2 + S(10)
    local gap = S(6)
    local cw = math.floor((iw - gap * 2) / 3)
    chip(win, ix, cy, cw, chH, T("IGUI_CM_LblTime"), T("IGUI_CM_ValMin", math.floor((c.limit or 0) / 60)), tc)
    chip(win, ix + cw + gap, cy, cw, chH, T("IGUI_CM_LblTeam"), T("IGUI_CM_ValTeam", c.cap or 0), tc)
    chip(win, ix + (cw + gap) * 2, cy, cw, chH, T("IGUI_CM_LblSize"), T("IGUI_CM_ValSize", c.area or 0), tc)
    cy = cy + chH + S(12)
    -- threat meter
    local thr = ({ 0.34, 0.67, 1.0 })[tier] or 0.34
    CMUI.text(win, T("IGUI_CM_Threat"), ix, cy, C.dim)
    CMUI.textR(win, T("IGUI_CM_Horde", CM.int(CM.tierVal(tier, "Alive"), 35)), ix + iw, cy, tier == 3 and C.bad or C.dim)
    cy = cy + CMUI.fh(fs) + S(4)
    CMUI.segbar(win, ix, cy, iw, S(6), thr, tier == 3 and C.bad or tc, 15)
    cy = cy + S(6) + S(14)
    -- loot
    cy = cy + CMUI.section(win, ix, cy, iw, T("IGUI_CM_Rewards"), C.gold)
    local bs = S(7)
    for _, line in ipairs(rewardLines(tier)) do
        CMUI.icon(win, "cm_pip", ix + S(2), cy + (CMUI.fh(fs) - bs) / 2, bs, tc, 0.9)
        cy = cy + CMUI.para(win, line, ix + S(16), cy, iw - S(16), C.text, fs, 2) + S(2)
    end
    -- bottom: status + action
    local btnH = S(34)
    local by = y + h - btnH - S(14)
    local py = by - CMUI.fh(fs) - S(16)
    local bw = statusBadge(win, ix, py, c)
    if CMC.claimed(c.id) then
        CMUI.badge(win, ix + bw + S(6), py, T("IGUI_CM_Claimed"), C.purple)
    elseif c.last and c.status ~= "live" then
        CMUI.textR(win, T(c.last.res == "ok" and "IGUI_CM_LastOk" or "IGUI_CM_LastFail"), ix + iw, py + S(3), C.faint)
    end
    local label, style, dis, tip = T("IGUI_CM_Accept"), "primary", false, T("IGUI_CM_AcceptTip")
    if mine then label, style, dis = T("IGUI_CM_InThis"), "sel", true
    elseif myRun then label, dis = T("IGUI_CM_InOther"), true
    elseif c.status == "live" then label = T("IGUI_CM_Join")
        if (c.n or 0) >= (c.cap or 0) then label, dis = T("IGUI_CM_Full"), true end
    elseif c.status ~= "open" then label, dis = T("IGUI_CM_NotNow"), true end
    if not dis and confirm.slot == c.slot and CMC.ms() - confirm.at < 4000 then
        label, style = T("IGUI_CM_Confirm"), "good"
    end
    CMUI.btn(win, ix, by, iw, btnH, label, function()
        if confirm.slot == c.slot and CMC.ms() - confirm.at < 4000 then
            confirm.slot = 0
            CMC.send("accept", { slot = c.slot })
            if CMBoard.win then CMBoard.win:close() end
        else
            confirm.slot = c.slot
            confirm.at = CMC.ms()
        end
    end, style, { disabled = dis, tip = tip, font = UIFont.Small, rad = 8 })
end

function BW:drawBody()
    local S = CMUI.S
    local pad = S(18)
    local top = self.headerH + S(12)
    local pub = CMC.pub
    local w = self.width
    if not pub then
        CMUI.textC(self, T("IGUI_CM_Loading"), w / 2, top + S(40), C.dim, 1, UIFont.Medium)
        return
    end
    local reset = CMC.left(pub.reset, CMC.pubAt) or 0
    CMUI.badge(self, pad, top, T("IGUI_CM_Today", CM.dayText(pub.day or 0)), C.accent)
    CMUI.textR(self, T("IGUI_CM_ResetIn", CM.clock(reset)), w - pad, top + S(3), C.dim)
    top = top + CMUI.fh(UIFont.Small) + S(20)
    local foot = CMUI.paraH(T("IGUI_CM_Rules"), w - pad * 2, UIFont.Small, 3) + S(14)
    local gap = S(16)
    local cw = math.floor((w - pad * 2 - gap * 2) / 3)
    local ch = self.height - top - foot - S(12)
    for s = 1, 3 do
        local c = pub.cards and pub.cards[s] or { slot = s, status = "none" }
        c.slot = c.slot or s
        drawCard(self, pad + (s - 1) * (cw + gap), top, cw, ch, c)
    end
    CMUI.hline(self, pad, self.height - foot - S(4), w - pad * 2, C.line, 0.5)
    CMUI.para(self, T("IGUI_CM_Rules"), pad, self.height - foot + S(4), w - pad * 2, C.faint, UIFont.Small, 3)
end

function BW:onClosed()
    CMBoard.win = nil
end

function CMBoard.open()
    if CMBoard.win then CMBoard.win:bringToTop(); return end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(960, 620)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = BW:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    win:show()
    CMBoard.win = win
    CMIcon.markSeen()
    if not CMC.pub then CMC.send("hello", {}) end
end

function CMBoard.toggle()
    if CMBoard.win then CMBoard.win:close() else CMBoard.open() end
end

-- ===================================================================== sidebar icon
CMIcon = CMIcon or {}

local function signature()
    local pub = CMC.pub
    if not pub or not pub.cards then return "" end
    local parts = {}
    for s = 1, 3 do local c = pub.cards[s]; if c and c.id then parts[#parts + 1] = c.id end end
    return table.concat(parts, ",")
end

function CMIcon.markSeen() CMIcon.seen = signature() end
function CMIcon.hasNew()
    local sig = signature()
    return sig ~= "" and sig ~= CMIcon.seen
end

function CMIcon.tooltip()
    local t = T("IGUI_CM_IconTip")
    local run = CMC.run()
    if run then t = t .. "\n" .. T("IGUI_CM_IconActive", CMC.typeName(run.type)) end
    return t
end

function CMIcon.click() CMBoard.toggle() end

function CMIcon.draw(el, w, h, over)
    local live = CMC.run() ~= nil
    local tex = CMUI.tex("cm_icon")
    local s = math.min(w, h)
    local x, y = (w - s) / 2, (h - s) / 2
    local a = 1
    if live then a = 0.75 + 0.25 * math.sin(CMC.ms() / 220) end
    if tex then el:drawTextureScaledAspect(tex, x, y, s, s, a, 1, 1, 1)
    else el:drawRect(x + 4, y + 4, s - 8, s - 8, 0.9, C.t3[1], C.t3[2], C.t3[3]) end
    if over then el:drawRectBorder(x + 1, y + 1, s - 2, s - 2, 0.6, C.accent[1], C.accent[2], C.accent[3]) end
    if CMIcon.hasNew() then
        local d = math.max(8, math.floor(s * 0.22))
        el:drawRect(x + s - d - 2, y + 2, d, d, 1, C.bad[1], C.bad[2], C.bad[3])
    end
end

function CMIcon.context()
    local ctx = ISContextMenu.get(0, getMouseX(), getMouseY())
    ctx:addOption(T("IGUI_CM_Ctx_Open"), nil, function() CMBoard.open() end)
    if CMC.isAdmin() then
        ctx:addOption(T("IGUI_CM_Ctx_Admin"), nil, function() if CMAdmin then CMAdmin.toggle() end end)
    end
end

-- floating fallback when the sidebar is already too long for the screen
CMIcon.Float = ISPanel:derive("CMIcon_Float")
local F = CMIcon.Float
function F:new(x, y, s)
    local o = ISPanel.new(self, x, y, s, s)
    o.background = false
    return o
end
function F:prerender() end
function F:render() CMIcon.draw(self, self.width, self.height, self:isMouseOver()) end
function F:onMouseDown(x, y) self.held = true; self.moved = false; return true end
function F:onMouseMove(dx, dy)
    if self.held then
        self.moved = true
        self:setX(self:getX() + dx); self:setY(self:getY() + dy)
    end
end
F.onMouseMoveOutside = F.onMouseMove
function F:onMouseUp(x, y)
    if not self.moved then CMIcon.click() end
    self.held = false; self.moved = false
    return true
end
function F:onMouseUpOutside() self.held = false; self.moved = false end
function F:onRightMouseUp() CMIcon.context(); return true end

local function makeSide(inst)
    if not inst then return nil end
    if inst.cmBtn then return inst.cmBtn end
    local ref = inst.invBtn
    local w = ref and ref:getWidth() or 48
    local h = ref and ref:getHeight() or 48
    local x = ref and ref:getX() or 2
    local btn = ISButton:new(x, inst:getHeight() + 12, w, h, "", nil, function() CMIcon.click() end)
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)
    btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.internal = "CookieMissionBtn"
    btn.render = function(self)
        self.tooltip = CMIcon.tooltip()
        CMIcon.draw(self, self:getWidth(), self:getHeight(), self:isMouseOver())
        if ISButton.updateTooltip then ISButton.updateTooltip(self) end
    end
    btn.onRightMouseUp = function() CMIcon.context(); return true end
    inst:addChild(btn)
    inst.cmBtn = btn
    if inst:getHeight() < btn:getBottom() then inst:setHeight(btn:getBottom()) end
    return btn
end

function CMIcon.apply()
    local inst = ISEquippedItem and ISEquippedItem.instance
    local btn = inst and makeSide(inst)
    local float = false
    if btn then
        local ok, bottom = pcall(function() return btn:getAbsoluteY() + btn:getHeight() end)
        if ok and bottom and bottom > getCore():getScreenHeight() - 4 then float = true end
    else
        float = true
    end
    if float then
        if btn then btn:setVisible(false) end
        if not CMIcon.float then
            local s = btn and btn:getWidth() or 48
            CMIcon.float = F:new(getCore():getScreenWidth() - s - 60, 200, s)
            CMIcon.float:initialise()
            CMIcon.float:instantiate()
            CMIcon.float:addToUIManager()
        end
        CMIcon.float:setVisible(true)
    else
        if btn then btn:setVisible(true) end
        if CMIcon.float then CMIcon.float:setVisible(false) end
    end
end

local pending = false
local function onTickInstall()
    if not pending then return end
    if not (ISEquippedItem and ISEquippedItem.instance) then return end
    pending = false
    Events.OnTick.Remove(onTickInstall)
    pcall(CMIcon.apply)
end

Events.OnCreatePlayer.Add(function(playerNum)
    if playerNum ~= 0 then return end
    pending = true
    Events.OnTick.Add(onTickInstall)
end)

Events.OnResolutionChange.Add(function()
    if ISEquippedItem and ISEquippedItem.instance and ISEquippedItem.instance.cmBtn then pcall(CMIcon.apply) end
end)

-- new day / board changed while open: nothing to do, the window redraws every frame
CMC.on(function(what)
    if what == "warp" and CMBoard.win then CMBoard.win:close() end
end)

return CMBoard
