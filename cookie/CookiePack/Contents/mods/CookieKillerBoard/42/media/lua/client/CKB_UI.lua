-- Cookie Killer Board - floating skull button + the board (style A4: gradient ribbons for ranks 1-3)
-- The button is a plain floating element, so Cookie Dock can group it like any other mod button.
if isServer() and not isClient() then return end

require "ISUI/ISPanel"
require "CM_UI_Kit"
require "CKB_Client"

CKBUI = CKBUI or {}
local C = CMUI.C
local T = CKBC.txt
local S = CMUI.S
local CFG_FILE = "CookieKillerBoard.txt"

local NAVY = { 0.039, 0.075, 0.161 }
local RIM = { 0.329, 0.522, 0.922 }
local CYAN = { 0.561, 0.859, 1.000 }
local DIM = { 0.600, 0.690, 0.840 }
local BOX = { 0.067, 0.114, 0.235 }
local INK = { 0.031, 0.024, 0.118 }
local WHITE = { 1, 1, 1 }
local SHADOW = { 0, 0, 0 }
local RIB_FALLBACK = { { 0.72, 0.23, 0.91 }, { 0.32, 0.27, 0.88 }, { 0.11, 0.47, 0.79 } }

-- ===================================================================== settings (this machine)
CKBUI.cfg = CKBUI.cfg or {}

function CKBUI.load()
    CKBUI.cfg = {}
    pcall(function()
        local r = getFileReader(CFG_FILE, false)
        if not r then return end
        while true do
            local line = r:readLine()
            if not line then break end
            local eq = string.find(line, "=", 1, true)
            if eq then CKBUI.cfg[string.sub(line, 1, eq - 1)] = string.sub(line, eq + 1) end
        end
        r:close()
    end)
end

function CKBUI.save()
    pcall(function()
        local w = getFileWriter(CFG_FILE, true, false)
        for _, k in ipairs(CM.sortedKeys(CKBUI.cfg)) do w:writeln(k .. "=" .. tostring(CKBUI.cfg[k])) end
        w:close()
    end)
end

local function screen()
    local c = getCore()
    return c:getScreenWidth(), c:getScreenHeight()
end

-- ===================================================================== small drawing helpers
local function shadowText(win, s, x, y, c, font, align)
    s = tostring(s or "")
    local draw = CMUI.text
    if align == "r" then draw = CMUI.textR elseif align == "c" then draw = CMUI.textC end
    draw(win, s, x + 1, y + 1, SHADOW, 0.45, font)
    draw(win, s, x, y, c, 1, font)
end

-- weapon picture in a small box; nil weapon shows the skull, dimmed
local function weaponBox(win, ft, x, y, bs, fill, fillA, rim, rimA)
    CMUI.rbox(win, x, y, bs, bs, fill, fillA, 6)
    CMUI.rborder(win, x, y, bs, bs, rim, rimA, 6)
    local tex = CKBC.weaponTex(ft)
    local a = 1
    if not tex then
        tex = CKBC.tex("kb_skull")
        a = 0.35
    end
    local is = math.floor(bs * 0.72)
    if tex then win:drawTextureScaledAspect(tex, x + (bs - is) / 2, y + (bs - is) / 2, is, is, a, 1, 1, 1) end
    local name = CKBC.weaponName(ft)
    if name then win:hit(x, y, bs, bs, nil, name) end
end

local function valueOf(r, tab)
    if tab == "all" then return CM.num(r.t, 0) end
    return CM.num(r.l, 0)
end

local function subOf(r, tab)
    if tab == "all" then return T("IGUI_CKB_SubAll", CKB.fmt(r.l), CKB.fmt(r.d)) end
    return T("IGUI_CKB_SubLife", CKB.fmt(r.t), CKB.fmt(r.d))
end

-- ===================================================================== layout
local function metrics()
    local fhS, fhM = CMUI.fh(UIFont.Small), CMUI.fh(UIFont.Medium)
    local sw = screen()
    return {
        pad = S(12),
        w = math.min(S(320), sw - 20),
        hh = math.max(S(28), fhM + 6),          -- header row
        tabH = math.max(S(30), fhS + S(12)),
        r1 = math.max(S(54), fhM + fhS + S(14)), -- ribbon rows (ranks 1-3)
        r2 = math.max(S(40), fhS * 2 + S(8)),    -- plain rows
        me = math.max(S(44), fhS * 2 + S(10)),   -- your row
        gap = S(10),
        g1 = S(8),
        g2 = S(2),
    }
end
CKBUI.metrics = metrics

local function isRibbon(r)
    local rank = tonumber(r.i)
    return rank ~= nil and rank >= 1 and rank <= 3 and not r.hid
end

-- ===================================================================== the board
CKBUI.Win = CMUI.Window:derive("CKB_Board")
local W = CKBUI.Win

function W:new(x, y)
    local o = CMUI.Window.new(self, x, y, 320, 300)
    o.title = "KILLER BOARD"
    o.tab = CKBUI.cfg.tab == "all" and "all" or "life"
    o.rowHits = {}
    return o
end

function W:layoutH(m)
    local h = m.pad + m.hh + m.gap + m.tabH + m.gap
    local d = CKBC.data[self.tab]
    if not d or #d.rows == 0 then
        h = h + m.r2
    else
        for i = 1, #d.rows do
            if isRibbon(d.rows[i]) then h = h + m.r1 + m.g1 else h = h + m.r2 + m.g2 end
        end
    end
    if d and d.me then h = h + m.gap + 1 + m.gap + m.me end
    return h + m.pad
end

function W:setTab(k)
    k = k == "all" and "all" or "life"
    if self.tab == k then return end
    self.tab = k
    CKBUI.cfg.tab = k
    CKBUI.save()
    local d = CKBC.data[k]
    if not d or CKBC.ms() - (d.at or 0) > 2000 then CKBC.ask(k) end
end

function W:prerender()
    CMUI.k = CMUI.fontScale()
    local m = metrics()
    self.m = m
    local h = self:layoutH(m)
    if self.width ~= m.w then self:setWidth(m.w) end
    if self.height ~= h then
        -- sitting above the button: grow upward so it never covers the button
        if self.keepBottom then self:setY(self:getY() + self.height - h) end
        self:setHeight(h)
    end
    self.headerH = m.pad + m.hh
    local t = CKBC.ms()
    if t - (CKBC.askedAt[self.tab] or 0) > 5000 then CKBC.ask(self.tab) end
    CMUI.Window.prerender(self)
end

function W:onMouseMove(dx, dy)
    if self.dragging then self.keepBottom = false end
    CMUI.Window.onMouseMove(self, dx, dy)
end

function W:onMouseMoveOutside(dx, dy)
    if self.dragging then self.keepBottom = false end
    CMUI.Window.onMouseMoveOutside(self, dx, dy)
end

function W:drawFrame()
    local w, h, m = self.width, self.height, self.m
    CMUI.rbox(self, 0, 0, w, h, NAVY, 0.95, 12)
    CMUI.texBox(self, "cm_grad", 1, 1, w - 2, math.min(h * 0.4, S(160)), C.accent, 0.10)
    CMUI.rborder(self, 0, 0, w, h, RIM, 0.55, 12)
    CMUI.texBox(self, "cm_hline", 20, 0, w - 40, 1, C.blue, 0.8)
    local x, y = m.pad, m.pad
    local is = S(22)
    local sk = CKBC.tex("kb_skull")
    if sk then self:drawTextureScaledAspect(sk, x, y + (m.hh - is) / 2, is, is, 1, 1, 1, 1) end
    CMUI.text(self, T("IGUI_CKB_Title"), x + is + S(8), y + (m.hh - CMUI.fh(UIFont.Medium)) / 2, CYAN, 1, UIFont.Medium)
    local cs = m.hh
    local cx = w - m.pad - cs
    local over = self:hit(cx, y, cs, cs, function() self:close() end)
    CMUI.rbox(self, cx, y, cs, cs, over and C.bad or BOX, over and 0.55 or 0.6, 6)
    CMUI.rborder(self, cx, y, cs, cs, over and C.bad or RIM, 0.45, 6)
    CMUI.textC(self, "x", cx + cs / 2, y + (cs - CMUI.fh(UIFont.Small)) / 2 - 1, C.text, 1, UIFont.Small)
end

function W:drawRibbon(r, rank, x, y, w, h)
    local fhS, fhM, fhL = CMUI.fh(UIFont.Small), CMUI.fh(UIFont.Medium), CMUI.fh(UIFont.Large)
    -- the texture is a 296 x 54 ribbon with a 10 px glow margin all round
    local gx = w * 10 / 296
    local gy = h * 10 / 54
    local tex = CKBC.tex("kb_rib" .. rank)
    if tex then
        self:drawTextureScaled(tex, x - gx, y - gy, w + gx * 2, h + gy * 2, 1, 1, 1, 1)
    else
        CMUI.rbox(self, x, y, w, h, RIB_FALLBACK[rank], 1, 6)
    end
    -- rank (crown over number one)
    local cx = x + S(27)
    local crownW, crownH = S(16), S(10)
    local stack = fhL
    if rank == 1 then stack = stack + crownH + 1 end
    local ty = y + (h - stack) / 2
    if rank == 1 then
        local cr = CKBC.tex("kb_crown")
        if cr then self:drawTextureScaled(cr, cx - crownW / 2, ty, crownW, crownH, 1, 1, 1, 1) end
        ty = ty + crownH + 1
    end
    shadowText(self, tostring(rank), cx, ty, WHITE, UIFont.Large, "c")
    -- weapon
    local bs = S(28)
    local bx = x + S(46)
    weaponBox(self, r.w, bx, y + (h - bs) / 2, bs, INK, 0.45, WHITE, 0.55)
    -- value, name, sub line
    local val = CKB.fmt(valueOf(r, self.tab))
    local vr = x + w - S(24)
    local vw = CMUI.tw(UIFont.Large, val)
    shadowText(self, val, vr, y + (h - fhL) / 2, WHITE, UIFont.Large, "r")
    local nx = bx + bs + S(9)
    local nw = math.max(S(40), vr - vw - S(8) - nx)
    local ny = y + (h - fhM - fhS) / 2
    shadowText(self, CMUI.fit(r.n, UIFont.Medium, nw), nx, ny, WHITE, UIFont.Medium)
    shadowText(self, CMUI.fit(subOf(r, self.tab), UIFont.Small, nw), nx, ny + fhM, WHITE, UIFont.Small)
end

function W:drawPlain(r, x, y, w, h)
    local fhS, fhM = CMUI.fh(UIFont.Small), CMUI.fh(UIFont.Medium)
    local over = self:isMouseOver() and self:getMouseY() >= y and self:getMouseY() < y + h
    if over then CMUI.rbox(self, x, y, w, h, C.panel3, 0.35, 6) end
    CMUI.textC(self, tostring(r.i or "-"), x + S(15), y + (h - fhS) / 2, DIM, 1, UIFont.Small)
    local bs = S(28)
    local bx = x + S(30)
    weaponBox(self, r.w, bx, y + (h - bs) / 2, bs, BOX, 1, RIM, 0.35)
    local val = CKB.fmt(valueOf(r, self.tab))
    local vr = x + w - S(4)
    local vw = CMUI.tw(UIFont.Medium, val)
    CMUI.textR(self, val, vr, y + (h - fhM) / 2, C.text, 1, UIFont.Medium)
    local nx = bx + bs + S(8)
    local nw = math.max(S(40), vr - vw - S(8) - nx)
    local ny = y + (h - fhS * 2) / 2
    local name = tostring(r.n or "?")
    if r.hid then
        local tag = " " .. T("IGUI_CKB_Hidden")
        name = CMUI.fit(name, UIFont.Small, nw - CMUI.tw(UIFont.Small, tag))
        CMUI.text(self, name, nx, ny, C.text, 0.6, UIFont.Small)
        CMUI.text(self, tag, nx + CMUI.tw(UIFont.Small, name), ny, C.bad, 0.9, UIFont.Small)
    else
        local mine = self.meKey ~= nil and r.k == self.meKey
        CMUI.text(self, CMUI.fit(name, UIFont.Small, nw), nx, ny, mine and CYAN or C.text, 1, UIFont.Small)
    end
    CMUI.text(self, CMUI.fit(subOf(r, self.tab), UIFont.Small, nw), nx, ny + fhS, DIM, 1, UIFont.Small)
end

function W:drawMe(r, x, y, w, h)
    local fhS, fhM = CMUI.fh(UIFont.Small), CMUI.fh(UIFont.Medium)
    CMUI.rbox(self, x, y, w, h, C.accent, 0.14, 8)
    CMUI.rborder(self, x, y, w, h, C.accent, 0.45, 8)
    local rk = r.i and ("#" .. tostring(r.i)) or "#-"
    CMUI.text(self, rk, x + S(8), y + (h - fhS) / 2, CYAN, 1, UIFont.Small)
    local rw = math.max(S(30), CMUI.tw(UIFont.Small, rk) + S(6))
    local bs = S(28)
    local bx = x + S(8) + rw
    weaponBox(self, r.w, bx, y + (h - bs) / 2, bs, BOX, 1, RIM, 0.35)
    local val = CKB.fmt(valueOf(r, self.tab))
    local vr = x + w - S(10)
    local vw = CMUI.tw(UIFont.Medium, val)
    CMUI.textR(self, val, vr, y + (h - fhM) / 2, C.text, 1, UIFont.Medium)
    local nx = bx + bs + S(8)
    local nw = math.max(S(40), vr - vw - S(8) - nx)
    local ny = y + (h - fhS * 2) / 2
    local life = CM.num(r.d, 0) + 1
    local sub
    if self.tab == "all" then
        sub = T("IGUI_CKB_MeAll", CKB.fmt(r.l), CKB.fmt(r.d), life)
    else
        sub = T("IGUI_CKB_MeLife", CKB.fmt(r.t), CKB.fmt(r.d), life)
    end
    CMUI.text(self, CMUI.fit(T("IGUI_CKB_You", r.n), UIFont.Small, nw), nx, ny, C.text, 1, UIFont.Small)
    CMUI.text(self, CMUI.fit(sub, UIFont.Small, nw), nx, ny + fhS, DIM, 1, UIFont.Small)
end

function W:drawBody()
    local m = self.m
    local x = m.pad
    local w = self.width - m.pad * 2
    local y = m.pad + m.hh + m.gap
    CMUI.tabs(self, x, y, w, m.tabH,
        { { key = "life", label = T("IGUI_CKB_TabLife") }, { key = "all", label = T("IGUI_CKB_TabAll") } },
        self.tab, function(k) self:setTab(k) end)
    y = y + m.tabH + m.gap
    self.rowHits = {}
    local d = CKBC.data[self.tab]
    self.meKey = d and d.me and d.me.k or nil
    local fhS = CMUI.fh(UIFont.Small)
    if not d then
        CMUI.textC(self, T("IGUI_CKB_Loading"), self.width / 2, y + (m.r2 - fhS) / 2, DIM, 1, UIFont.Small)
        return
    end
    if #d.rows == 0 then
        CMUI.textC(self, T("IGUI_CKB_Empty"), self.width / 2, y + (m.r2 - fhS) / 2, DIM, 1, UIFont.Small)
        y = y + m.r2
    else
        for i = 1, #d.rows do
            local r = d.rows[i]
            if isRibbon(r) then
                self:drawRibbon(r, tonumber(r.i), x, y, w, m.r1)
                self.rowHits[#self.rowHits + 1] = { y1 = y, y2 = y + m.r1, r = r }
                y = y + m.r1 + m.g1
            else
                self:drawPlain(r, x, y, w, m.r2)
                self.rowHits[#self.rowHits + 1] = { y1 = y, y2 = y + m.r2, r = r }
                y = y + m.r2 + m.g2
            end
        end
    end
    if d.me then
        y = y + m.gap
        CMUI.hline(self, x, y, w, RIM, 0.6)
        y = y + 1 + m.gap
        self:drawMe(d.me, x, y, w, m.me)
    end
end

-- staff: right-click a row to take that player off the board (or back) or clear their bank
function W:onRightMouseUp(x, y)
    if not CKBC.isAdmin() then return true end
    local hit = nil
    for _, h in ipairs(self.rowHits or {}) do
        if y >= h.y1 and y < h.y2 then hit = h.r end
    end
    if not hit or not hit.k then return true end
    local ctx = ISContextMenu.get(0, getMouseX(), getMouseY())
    local k = hit.k
    ctx:addOption(hit.hid and T("IGUI_CKB_AdmShow", hit.n) or T("IGUI_CKB_AdmHide", hit.n), nil, function()
        CKBC.send("adm", { op = "hide", k = k })
    end)
    ctx:addOption(T("IGUI_CKB_AdmReset", hit.n), nil, function()
        CKBC.send("adm", { op = "reset", k = k })
    end)
    return true
end

-- ===================================================================== open / close
local function place(win)
    local sw, sh = screen()
    local w, h = win.width, win.height
    local fab = CKBUI.fab
    local x, y
    win.keepBottom = false
    if fab and fab:isVisible() then
        local fx, fy, fs = fab:getX(), fab:getY(), fab.width
        local gap = S(12)
        if fy - gap - h >= 8 then
            x, y = fx, fy - gap - h
            win.keepBottom = true
        elseif fy + fs + gap + h <= sh - 8 then
            x, y = fx, fy + fs + gap
        else
            -- next to the button, bottom edges lined up
            if fx + fs / 2 < sw / 2 then x = fx + fs + gap else x = fx - gap - w end
            y = fy + fs - h
        end
    else
        x, y = S(76), math.floor((sh - h) / 2)
    end
    win:setX(CM.clamp(x, 8, math.max(8, sw - w - 8)))
    win:setY(CM.clamp(y, 8, math.max(8, sh - h - 8)))
end

function CKBUI.open()
    if CKBUI.win then return CKBUI.win end
    CMUI.k = CMUI.fontScale()
    local win = CKBUI.Win:new(0, 0)
    win.m = metrics()
    win:setWidth(win.m.w)
    win:setHeight(win:layoutH(win.m))
    place(win)
    win.onClosed = function() CKBUI.win = nil end
    win:show()
    CKBUI.win = win
    CKBC.ask(win.tab)
    return win
end

function CKBUI.close()
    if CKBUI.win then CKBUI.win:close() end
end

function CKBUI.toggle()
    if CKBUI.win then CKBUI.close() else CKBUI.open() end
end

-- ===================================================================== floating skull button
CKBUI.Fab = ISPanel:derive("CKB_Fab")
local F = CKBUI.Fab

function F:new(x, y, s)
    local o = ISPanel.new(self, x, y, s, s)
    o.background = false
    o.moveWithMouse = false
    o.anchorLeft = true
    o.anchorTop = true
    o.internal = "Killer Board"       -- the name Cookie Dock lists
    o.tex = CKBC.tex("kb_skull")      -- the picture Cookie Dock shows
    return o
end

function F:clamp()
    local sw, sh = screen()
    local s = self.width
    local x = CM.clamp(self:getX(), 0, math.max(0, sw - s))
    local y = CM.clamp(self:getY(), 0, math.max(0, sh - s))
    if x ~= self:getX() then self:setX(x) end
    if y ~= self:getY() then self:setY(y) end
end

function F:prerender() end

function F:render()
    local s = math.min(self.width, self.height)
    local over = self:isMouseOver()
    local bg = CKBC.tex("kb_fab")
    if bg then
        self:drawTextureScaled(bg, 0, 0, s, s, 1, 1, 1, 1)
    else
        self:drawRect(s * 0.1, s * 0.1, s * 0.8, s * 0.8, 0.95, NAVY[1], NAVY[2], NAVY[3])
    end
    if over or CKBUI.win then
        local hi = CKBC.tex("kb_fab_hi")
        if hi then self:drawTextureScaled(hi, 0, 0, s, s, over and 1 or 0.55, 1, 1, 1) end
    end
    local i = math.floor(s * 0.58)
    if self.tex then self:drawTextureScaledAspect(self.tex, (s - i) / 2, (s - i) / 2, i, i, 1, 1, 1, 1) end
end

function F:onMouseDown(x, y)
    self.held = true
    self.moved = 0
    self.dragging = false
    return true
end

function F:onMouseMove(dx, dy)
    if not self.held then return end
    self.moved = (self.moved or 0) + math.abs(dx) + math.abs(dy)
    if self.dragging or self.moved > 4 then
        self.dragging = true
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
        self:clamp()
    end
end
F.onMouseMoveOutside = F.onMouseMove

local function endDrag(self)
    if self.dragging then
        CKBUI.cfg.x = math.floor(self:getX())
        CKBUI.cfg.y = math.floor(self:getY())
        CKBUI.save()
    end
    self.held = false
    self.dragging = false
end

function F:onMouseUp(x, y)
    local click = self.held and not self.dragging
    endDrag(self)
    if click then CKBUI.toggle() end
    return true
end

function F:onMouseUpOutside(x, y) endDrag(self) end

-- Cookie Dock calls this when the player grouped the button into the dock
function F:forceClick() CKBUI.toggle() end

function CKBUI.makeFab()
    if CKBUI.fab then return CKBUI.fab end
    CMUI.k = CMUI.fontScale()
    CKBUI.load()
    local sw, sh = screen()
    local s = S(52)
    local x = CM.num(CKBUI.cfg.x, nil)
    local y = CM.num(CKBUI.cfg.y, nil)
    if x == nil or y == nil then
        -- left side, above where the chat box sits by default
        x = S(76)
        y = math.max(S(120), sh - 400 - s - S(24))
    end
    local f = CKBUI.Fab:new(x, y, s)
    f:initialise()
    f:instantiate()
    f:addToUIManager()
    f:setVisible(true)
    f:clamp()
    CKBUI.fab = f
    return f
end

Events.OnGameStart.Add(function()
    local ok, err = pcall(CKBUI.makeFab)
    if not ok then CKB.log("button error: " .. tostring(err)) end
end)

if Events.OnResolutionChange then Events.OnResolutionChange.Add(function()
    if CKBUI.fab then pcall(function() CKBUI.fab:clamp() end) end
end) end

return CKBUI
