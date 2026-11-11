-- Cookie Quest - small immediate-mode UI kit (all drawing + click regions in one pass)
require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "CQ_Client"

CQUI = CQUI or {}

CQUI.C = {
    bg     = { 0.070, 0.075, 0.110 },
    panel  = { 0.115, 0.120, 0.175 },
    panel2 = { 0.155, 0.160, 0.230 },
    panel3 = { 0.200, 0.205, 0.290 },
    line   = { 0.250, 0.270, 0.370 },
    text   = { 0.960, 0.940, 0.890 },
    dim    = { 0.640, 0.660, 0.740 },
    faint  = { 0.420, 0.440, 0.520 },
    accent = { 1.000, 0.620, 0.240 },
    accentD= { 0.420, 0.250, 0.100 },
    gold   = { 1.000, 0.840, 0.350 },
    good   = { 0.400, 0.880, 0.600 },
    bad    = { 0.980, 0.400, 0.400 },
    purple = { 0.680, 0.500, 0.980 },
    blue   = { 0.450, 0.750, 1.000 },
    ink    = { 0.200, 0.120, 0.060 },
    dark   = { 0.080, 0.060, 0.040 },
}
local C = CQUI.C

CQUI.FS = UIFont.Small
CQUI.FM = UIFont.Medium
CQUI.FL = UIFont.Large

local TM = nil
local function tm()
    if not TM then TM = getTextManager() end
    return TM
end

function CQUI.fh(font) return tm():getFontHeight(font or UIFont.Small) end
function CQUI.tw(font, s) return tm():MeasureStringX(font or UIFont.Small, tostring(s or "")) end

local texCache = {}
function CQUI.tex(name)
    local t = texCache[name]
    if t == nil then
        t = getTexture("media/textures/CookieQuest/" .. name .. ".png") or false
        texCache[name] = t
    end
    return t or nil
end

-- ===================================================================== text utilities
local function isCombining(code)
    return code == 0x0E31 or (code >= 0x0E34 and code <= 0x0E3A) or (code >= 0x0E47 and code <= 0x0E4E)
end
local function isLeading(code)
    return code >= 0x0E40 and code <= 0x0E44
end

local wrapCache, wrapCount = {}, 0

-- wrap text to lines that fit maxW (spaces preferred; Thai text breaks between characters)
function CQUI.wrap(text, font, maxW)
    text = tostring(text or "")
    font = font or UIFont.Small
    local key = tostring(font) .. "|" .. tostring(maxW) .. "|" .. text
    local hit = wrapCache[key]
    if hit then return hit end
    local out = {}
    local paras = {}
    local s = text .. "\n"
    local pos = 1
    while true do
        local nl = string.find(s, "\n", pos, true)
        if not nl then break end
        paras[#paras + 1] = string.sub(s, pos, nl - 1)
        pos = nl + 1
    end
    for _, para in ipairs(paras) do
        para = string.gsub(para, "\r", "")
        if para == "" then
            out[#out + 1] = ""
        else
            local n = #para
            local start = 1
            while start <= n do
                if CQUI.tw(font, string.sub(para, start)) <= maxW then
                    out[#out + 1] = string.sub(para, start)
                    break
                end
                -- grow until too wide
                local i = start
                local lastSpace = nil
                local lastOk = nil
                while i <= n do
                    local e = CQ.charEnd(para, i)
                    if string.sub(para, i, e) == " " then lastSpace = i end
                    if CQUI.tw(font, string.sub(para, start, e)) > maxW then break end
                    lastOk = e
                    i = e + 1
                end
                if not lastOk then lastOk = CQ.charEnd(para, start) end
                local cut
                if lastSpace and lastSpace > start then
                    cut = lastSpace
                else
                    cut = lastOk
                    -- do not split a base char from its mark, do not end on a leading vowel
                    while cut > start do
                        local nextCode = string.byte(para, cut + 1)
                        local thisCode = string.byte(para, cut)
                        if (nextCode and isCombining(nextCode)) or (thisCode and isLeading(thisCode)) then
                            cut = cut - 1
                        else
                            break
                        end
                    end
                    if cut < start then cut = lastOk end
                end
                local line = string.sub(para, start, cut)
                line = string.gsub(line, "%s+$", "")
                out[#out + 1] = line
                start = cut + 1
                while string.sub(para, start, start) == " " do start = start + 1 end
            end
        end
    end
    wrapCount = wrapCount + 1
    if wrapCount > 300 then wrapCache = {}; wrapCount = 0 end
    wrapCache[key] = out
    return out
end

-- cut text to fit width, adds ".." when cut
function CQUI.fit(s, font, maxW)
    s = tostring(s or "")
    if CQUI.tw(font, s) <= maxW then return s end
    local n = #s
    while n > 0 and CQUI.tw(font, string.sub(s, 1, n) .. "..") > maxW do n = CQ.safeCut(s, n - 1) end
    return string.sub(s, 1, n) .. ".."
end

-- ===================================================================== drawing primitives
function CQUI.rect(win, x, y, w, h, c, a)
    win:drawRect(x, y, w, h, a or 1, c[1], c[2], c[3])
end

function CQUI.border(win, x, y, w, h, c, a)
    win:drawRectBorder(x, y, w, h, a or 1, c[1], c[2], c[3])
end

-- rounded box from 4 corner textures + 3 rects
function CQUI.rbox(win, x, y, w, h, c, a, rad)
    a = a or 1
    rad = rad or 6
    if w <= 0 or h <= 0 then return end
    if rad < 1 or w < rad * 2 or h < rad * 2 then
        win:drawRect(x, y, w, h, a, c[1], c[2], c[3])
        return
    end
    local tl, tr, bl, br = CQUI.tex("cq_c_tl"), CQUI.tex("cq_c_tr"), CQUI.tex("cq_c_bl"), CQUI.tex("cq_c_br")
    if not (tl and tr and bl and br) then
        win:drawRect(x, y, w, h, a, c[1], c[2], c[3])
        return
    end
    win:drawRect(x + rad, y, w - rad * 2, h, a, c[1], c[2], c[3])
    win:drawRect(x, y + rad, rad, h - rad * 2, a, c[1], c[2], c[3])
    win:drawRect(x + w - rad, y + rad, rad, h - rad * 2, a, c[1], c[2], c[3])
    win:drawTextureScaled(tl, x, y, rad, rad, a, c[1], c[2], c[3])
    win:drawTextureScaled(tr, x + w - rad, y, rad, rad, a, c[1], c[2], c[3])
    win:drawTextureScaled(bl, x, y + h - rad, rad, rad, a, c[1], c[2], c[3])
    win:drawTextureScaled(br, x + w - rad, y + h - rad, rad, rad, a, c[1], c[2], c[3])
end

function CQUI.text(win, s, x, y, c, a, font)
    c = c or C.text
    win:drawText(tostring(s or ""), x, y, c[1], c[2], c[3], a or 1, font or UIFont.Small)
end

function CQUI.textC(win, s, cx, y, c, a, font)
    c = c or C.text
    win:drawTextCentre(tostring(s or ""), cx, y, c[1], c[2], c[3], a or 1, font or UIFont.Small)
end

function CQUI.textR(win, s, rx, y, c, a, font)
    c = c or C.text
    win:drawTextRight(tostring(s or ""), rx, y, c[1], c[2], c[3], a or 1, font or UIFont.Small)
end

function CQUI.icon(win, name, x, y, size, c, a)
    local t = CQUI.tex(name)
    if not t then return false end
    c = c or { 1, 1, 1 }
    win:drawTextureScaled(t, x, y, size, size, a or 1, c[1], c[2], c[3])
    return true
end

-- draw wrapped lines; returns height used
function CQUI.para(win, s, x, y, w, c, font, maxLines, a)
    font = font or UIFont.Small
    local lines = CQUI.wrap(s, font, w)
    local lh = CQUI.fh(font) + 2
    local n = #lines
    if maxLines and n > maxLines then n = maxLines end
    for i = 1, n do
        local line = lines[i]
        if maxLines and i == maxLines and #lines > maxLines then line = CQUI.fit(line .. " ..", font, w) end
        CQUI.text(win, line, x, y + (i - 1) * lh, c, a, font)
    end
    return n * lh, #lines
end

function CQUI.paraH(s, w, font, maxLines)
    font = font or UIFont.Small
    local lines = CQUI.wrap(s, font, w)
    local n = #lines
    if maxLines and n > maxLines then n = maxLines end
    return n * (CQUI.fh(font) + 2)
end

-- ===================================================================== base window
CQUI.Window = ISPanel:derive("CQUI_Window")
local W = CQUI.Window

function W:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    o.moveWithMouse = false
    o.hits = {}
    o.scroll = {}
    o.scrollAreas = {}
    o.headerH = CQUI.fh(UIFont.Medium) + 16
    o.title = "Cookie Quest"
    o.titleIcon = "cq_icon_on"
    o.anchorLeft = true
    o.anchorTop = true
    return o
end

function W:hit(x, y, w, h, fn, tip)
    local rec = { x = x, y = y, w = w, h = h, fn = fn, tip = tip, clip = self.clip }
    self.hits[#self.hits + 1] = rec
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver() and mx >= x and mx < x + w and my >= y and my < y + h
    if over and self.clip then
        local c = self.clip
        over = mx >= c.x and mx < c.x + c.w and my >= c.y and my < c.y + c.h
    end
    if over and tip and tip ~= "" then self.tipText = tip end
    local pressed = over and self.pressed ~= nil and self.pressed.x == x and self.pressed.y == y and self.pressed.w == w
    return over, pressed
end

function W:findHit(x, y)
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
            local c = h.clip
            if not c or (x >= c.x and x < c.x + c.w and y >= c.y and y < c.y + c.h) then return h end
        end
    end
    return nil
end

function W:onMouseDown(x, y)
    self:bringToTop()
    local h = self:findHit(x, y)
    if h then
        self.pressed = h
        return true
    end
    if y < self.headerH then
        self.dragging = true
    end
    return true
end

function W:onMouseUp(x, y)
    local was = self.pressed
    self.pressed = nil
    self.dragging = false
    if was then
        local h = self:findHit(x, y)
        if h and h.x == was.x and h.y == was.y and h.w == was.w and h.h == was.h and h.fn then
            pcall(function() getSoundManager():playUISound("UIActivateButton") end)
            local ok, err = pcall(h.fn)
            if not ok then CQ.log("ui click error: " .. tostring(err)) end
        end
    end
    return true
end

function W:onMouseUpOutside(x, y)
    self.pressed = nil
    self.dragging = false
end

function W:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
end

function W:onMouseMoveOutside(dx, dy)
    if self.dragging then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
end

function W:onMouseWheel(del)
    local mx, my = self:getMouseX(), self:getMouseY()
    -- innermost area under the mouse that can actually scroll (a full inner list passes the wheel to its form)
    for i = #self.scrollAreas, 1, -1 do
        local a = self.scrollAreas[i]
        local c = a.clip or a
        if (a.max or 0) > 0 and mx >= c.x and mx < c.x + c.w and my >= c.y and my < c.y + c.h then
            local max = a.max or 0
            local v = (self.scroll[a.key] or 0) + del * 36
            if v < 0 then v = 0 end
            if v > max then v = max end
            self.scroll[a.key] = v
            return true
        end
    end
    return true
end

-- content height of a scroll area is measured from what is drawn in it, so forms grow a scrollbar
-- instead of running past the window when the font is big or the screen is small
function W:grow(bottom)
    local a = self.curArea
    if a and bottom > a.maxY then a.maxY = bottom end
end

function W:drawRect(x, y, w, h, ...)
    self:grow(y + h)
    return ISPanel.drawRect(self, x, y, w, h, ...)
end

function W:drawRectBorder(x, y, w, h, ...)
    self:grow(y + h)
    return ISPanel.drawRectBorder(self, x, y, w, h, ...)
end

function W:drawText(s, x, y, r, g, b, a, font)
    self:grow(y + CQUI.fh(font))
    return ISPanel.drawText(self, s, x, y, r, g, b, a, font)
end

function W:drawTextCentre(s, x, y, r, g, b, a, font)
    self:grow(y + CQUI.fh(font))
    return ISPanel.drawTextCentre(self, s, x, y, r, g, b, a, font)
end

function W:drawTextRight(s, x, y, r, g, b, a, font)
    self:grow(y + CQUI.fh(font))
    return ISPanel.drawTextRight(self, s, x, y, r, g, b, a, font)
end

function W:drawTextureScaled(tex, x, y, w, h, ...)
    self:grow(y + h)
    return ISPanel.drawTextureScaled(self, tex, x, y, w, h, ...)
end

function W:drawTextureScaledAspect(tex, x, y, w, h, ...)
    self:grow(y + h)
    return ISPanel.drawTextureScaledAspect(self, tex, x, y, w, h, ...)
end

-- begin a clipped scrolling region (may be nested); returns the current offset
function W:beginScroll(key, x, y, w, h)
    local off = self.scroll[key] or 0
    local c = { x = x, y = y, w = w, h = h }
    local p = self.clip
    if p then
        local x1, y1 = math.max(x, p.x), math.max(y, p.y)
        local x2, y2 = math.min(x + w, p.x + p.w), math.min(y + h, p.y + p.h)
        c = { x = x1, y = y1, w = math.max(0, x2 - x1), h = math.max(0, y2 - y1) }
        self:clearStencilRect()
    end
    local area = { key = key, x = x, y = y, w = w, h = h, max = 0, off = off, maxY = y, clip = c }
    self.scrollAreas[#self.scrollAreas + 1] = area
    self.clipStack[#self.clipStack + 1] = { area = self.curArea, clip = p }
    self.curArea = area
    self.clip = c
    -- one stencil level at a time: nested areas use the intersection
    self:setStencilRect(c.x, c.y, c.w, c.h)
    return off
end

function W:endScroll(contentH)
    self:clearStencilRect()
    local a = self.curArea
    local prev = table.remove(self.clipStack)
    self.clip = prev and prev.clip or nil
    self.curArea = prev and prev.area or nil
    if self.clip then self:setStencilRect(self.clip.x, self.clip.y, self.clip.w, self.clip.h) end
    if not a then return end
    contentH = math.max(contentH or 0, (a.maxY + a.off) - a.y)
    self:grow(a.y + a.h)
    local max = math.max(0, contentH - a.h)
    a.max = max
    local v = self.scroll[a.key] or 0
    if v > max then v = max; self.scroll[a.key] = v end
    if max > 0 then
        local barH = math.max(24, a.h * a.h / (contentH + 1))
        local by = a.y + (a.h - barH) * (v / max)
        CQUI.rbox(self, a.x + a.w - 5, by, 4, barH, C.accent, 0.55, 2)
    end
end

function W:drawFrame()
    local w, h = self.width, self.height
    CQUI.rbox(self, 4, 5, w, h, { 0, 0, 0 }, 0.35, 10)
    CQUI.rbox(self, 0, 0, w, h, C.bg, 0.96, 10)
    CQUI.rbox(self, 0, 0, w, self.headerH, C.panel, 1, 10)
    CQUI.rect(self, 0, self.headerH - 10, w, 10, C.panel, 1)
    CQUI.rect(self, 0, self.headerH, w, 2, C.accent, 0.85)
    local tx = 14
    if self.titleIcon and CQUI.icon(self, self.titleIcon, 10, (self.headerH - 26) / 2, 26) then tx = 42 end
    CQUI.text(self, self.title, tx, (self.headerH - CQUI.fh(UIFont.Medium)) / 2, C.text, 1, UIFont.Medium)
    if self.subtitle then
        CQUI.text(self, self.subtitle, tx + CQUI.tw(UIFont.Medium, self.title) + 10,
            (self.headerH - CQUI.fh(UIFont.Small)) / 2 + 1, C.dim, 1, UIFont.Small)
    end
    local cs = self.headerH - 14
    local over = self:hit(w - cs - 8, 7, cs, cs, function() self:close() end)
    CQUI.rbox(self, w - cs - 8, 7, cs, cs, over and C.bad or C.panel2, over and 0.9 or 1, 5)
    CQUI.textC(self, "x", w - cs / 2 - 8, 7 + (cs - CQUI.fh(UIFont.Small)) / 2 - 1, C.text, 1, UIFont.Small)
end

-- design sizes grow with the player's font size and never exceed the screen
function CQUI.fontScale()
    return math.max(1, CQUI.fh(UIFont.Small) / 16)
end

-- scale a design pixel value by the font size (cached once per frame in Window:prerender)
CQUI.k = 1
function CQUI.S(n)
    return math.floor(n * (CQUI.k or 1) + 0.5)
end

function CQUI.size(baseW, baseH)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local k = CQUI.fontScale()
    return math.min(math.floor(baseW * k), sw - 20), math.min(math.floor(baseH * k), sh - 20)
end

function W:keepOnScreen()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    if self.width > sw - 10 then self:setWidth(sw - 10) end
    if self.height > sh - 10 then self:setHeight(sh - 10) end
    local x, y = self:getX(), self:getY()
    local nx = CQ.clamp(x, 0, math.max(0, sw - self.width))
    local ny = CQ.clamp(y, 0, math.max(0, sh - self.height))
    if nx ~= x then self:setX(nx) end
    if ny ~= y then self:setY(ny) end
end

-- scrollable form: fn(top) draws from the given top; a scrollbar appears when it is taller than h
function W:form(key, x, y, w, h, fn)
    local off = self:beginScroll(key, x, y, w + 10, h)
    local ok, err = pcall(fn, y - off)
    self:endScroll(0)
    if not ok then error(err) end
end

function W:prerender()
    CQUI.k = CQUI.fontScale()
    self:keepOnScreen()
    self.hits = {}
    self.scrollAreas = {}
    self.clipStack = {}
    self.curArea = nil
    self.clip = nil
    self.tipText = nil
    self:drawFrame()
    if self.drawBody then
        local ok, err = pcall(self.drawBody, self)
        if not ok then
            if self.clip then self:clearStencilRect() end
            self.clip = nil
            self.curArea = nil
            self.clipStack = {}
            CQ.log("draw error: " .. tostring(err))
            CQUI.text(self, "UI error - see console", 14, self.headerH + 10, C.bad)
        end
    end
end

function W:render()
    if self.drawOver then pcall(self.drawOver, self) end
    if self.tipText then
        local lines = CQUI.wrap(self.tipText, UIFont.Small, 260)
        local lh = CQUI.fh(UIFont.Small) + 2
        local w = 0
        for i = 1, #lines do w = math.max(w, CQUI.tw(UIFont.Small, lines[i])) end
        w = w + 16
        local h = #lines * lh + 10
        local x = self:getMouseX() + 16
        local y = self:getMouseY() + 16
        if x + w > self.width then x = self.width - w - 4 end
        if y + h > self.height then y = self:getMouseY() - h - 6 end
        CQUI.rbox(self, x, y, w, h, C.dark, 0.95, 5)
        CQUI.border(self, x, y, w, h, C.accent, 0.5)
        for i = 1, #lines do CQUI.text(self, lines[i], x + 8, y + 5 + (i - 1) * lh, C.text) end
    end
end

function W:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if self.onClosed then pcall(self.onClosed, self) end
end

function W:show()
    self:initialise()
    self:instantiate()
    self:addToUIManager()
    self:setVisible(true)
    self:bringToTop()
end

-- ===================================================================== widgets
local STY = {
    primary = { bg = C.accent, hov = { 1.0, 0.72, 0.38 }, fg = C.dark },
    ghost   = { bg = C.panel2, hov = C.panel3, fg = C.text },
    good    = { bg = { 0.16, 0.36, 0.25 }, hov = { 0.20, 0.46, 0.32 }, fg = C.good },
    danger  = { bg = { 0.38, 0.13, 0.13 }, hov = { 0.52, 0.17, 0.17 }, fg = { 1.0, 0.78, 0.78 } },
    flat    = { bg = C.bg, hov = C.panel2, fg = C.dim },
    sel     = { bg = C.accentD, hov = { 0.52, 0.31, 0.12 }, fg = C.gold },
    purple  = { bg = { 0.30, 0.20, 0.48 }, hov = { 0.38, 0.26, 0.60 }, fg = { 0.90, 0.84, 1.0 } },
}
CQUI.STY = STY

function CQUI.btn(win, x, y, w, h, label, fn, style, opts)
    opts = opts or {}
    local st = STY[style or "ghost"] or STY.ghost
    local dis = opts.disabled == true
    local over, pressed = win:hit(x, y, w, h, (not dis) and fn or nil, opts.tip)
    local bg = st.bg
    if dis then bg = C.panel elseif over then bg = st.hov end
    local yo = pressed and 1 or 0
    CQUI.rbox(win, x, y + yo, w, h, bg, dis and 0.6 or 1, opts.rad or 5)
    local font = opts.font or UIFont.Small
    local fg = dis and C.faint or (opts.fg or st.fg)
    local iw = 0
    if opts.icon then
        local is = math.min(h - 6, 18)
        iw = is + 5
        local tw = CQUI.tw(font, label)
        local sx = x + (w - tw - iw) / 2
        CQUI.icon(win, opts.icon, sx, y + yo + (h - is) / 2, is, opts.iconColor or fg, dis and 0.5 or 1)
        CQUI.text(win, label, sx + iw, y + yo + (h - CQUI.fh(font)) / 2, fg, 1, font)
    else
        CQUI.textC(win, CQUI.fit(label, font, w - 8), x + w / 2, y + yo + (h - CQUI.fh(font)) / 2, fg, 1, font)
    end
    return over
end

-- auto-width button, returns width
function CQUI.btnA(win, x, y, h, label, fn, style, opts)
    local w = CQUI.tw((opts and opts.font) or UIFont.Small, label) + 22 + ((opts and opts.icon) and 22 or 0)
    if opts and opts.minW and w < opts.minW then w = opts.minW end
    CQUI.btn(win, x, y, w, h, label, fn, style, opts)
    return w
end

function CQUI.toggle(win, x, y, label, on, fn, opts)
    opts = opts or {}
    local font = opts.font or UIFont.Small
    local fh = CQUI.fh(font)
    local bs = math.max(14, fh - 2)
    local w = bs + 8 + CQUI.tw(font, label)
    local over = win:hit(x, y, w, math.max(bs, fh), fn, opts.tip)
    CQUI.rbox(win, x, y + (fh - bs) / 2, bs, bs, on and C.accent or (over and C.panel3 or C.panel2), 1, 4)
    if on then
        if not CQUI.icon(win, "cq_check", x + 1, y + (fh - bs) / 2 + 1, bs - 2, C.dark) then
            CQUI.textC(win, "v", x + bs / 2, y, C.dark, 1, font)
        end
    end
    CQUI.text(win, label, x + bs + 8, y, (opts.disabled and C.faint) or (on and C.text or C.dim), 1, font)
    return w
end

function CQUI.cycle(win, x, y, w, h, text, onPrev, onNext, opts)
    opts = opts or {}
    local aw = h
    local o1 = win:hit(x, y, aw, h, onPrev, opts.tip)
    local o2 = win:hit(x + w - aw, y, aw, h, onNext, opts.tip)
    local o3 = win:hit(x + aw, y, w - aw * 2, h, onNext, opts.tip)
    CQUI.rbox(win, x, y, w, h, (o3) and C.panel3 or C.panel2, 1, 5)
    CQUI.rbox(win, x, y, aw, h, o1 and C.accentD or C.panel3, 1, 5)
    CQUI.rbox(win, x + w - aw, y, aw, h, o2 and C.accentD or C.panel3, 1, 5)
    local fy = y + (h - CQUI.fh(UIFont.Small)) / 2
    CQUI.textC(win, "<", x + aw / 2, fy, C.accent)
    CQUI.textC(win, ">", x + w - aw / 2, fy, C.accent)
    CQUI.textC(win, CQUI.fit(text, UIFont.Small, w - aw * 2 - 6), x + w / 2, fy, opts.color or C.text)
end

function CQUI.stepper(win, x, y, w, h, text, onMinus, onPlus, opts)
    opts = opts or {}
    local bw = h
    local o1 = win:hit(x, y, bw, h, onMinus, opts.tip)
    local o2 = win:hit(x + w - bw, y, bw, h, onPlus, opts.tip)
    CQUI.rbox(win, x, y, w, h, C.panel2, 1, 5)
    CQUI.rbox(win, x, y, bw, h, o1 and C.accentD or C.panel3, 1, 5)
    CQUI.rbox(win, x + w - bw, y, bw, h, o2 and C.accentD or C.panel3, 1, 5)
    local fy = y + (h - CQUI.fh(UIFont.Small)) / 2
    CQUI.textC(win, "-", x + bw / 2, fy, C.accent)
    CQUI.textC(win, "+", x + w - bw / 2, fy, C.accent)
    CQUI.textC(win, CQUI.fit(text, UIFont.Small, w - bw * 2 - 4), x + w / 2, fy, opts.color or C.text)
end

-- tabs: items = { {key, label, badge} }
function CQUI.tabs(win, x, y, w, h, items, cur, onSel)
    local n = #items
    if n == 0 then return end
    local tw = w / n
    CQUI.rbox(win, x, y, w, h, C.panel, 1, 6)
    for i = 1, n do
        local it = items[i]
        local tx = x + (i - 1) * tw
        local sel = it.key == cur
        local over = win:hit(tx, y, tw, h, function() onSel(it.key) end)
        if sel then
            CQUI.rbox(win, tx + 3, y + 3, tw - 6, h - 6, C.panel3, 1, 5)
            CQUI.rect(win, tx + 10, y + h - 4, tw - 20, 2, C.accent, 1)
        elseif over then
            CQUI.rbox(win, tx + 3, y + 3, tw - 6, h - 6, C.panel2, 1, 5)
        end
        local label = it.label
        local fy = y + (h - CQUI.fh(UIFont.Small)) / 2
        if it.badge and it.badge ~= "" and it.badge ~= "0" then
            local bw = CQUI.tw(UIFont.Small, it.badge) + 10
            local lw = CQUI.tw(UIFont.Small, label)
            local sx = tx + (tw - lw - bw - 6) / 2
            CQUI.text(win, label, sx, fy, sel and C.gold or C.dim)
            CQUI.rbox(win, sx + lw + 6, fy, bw, CQUI.fh(UIFont.Small), sel and C.accent or C.panel3, 1, 6)
            CQUI.textC(win, it.badge, sx + lw + 6 + bw / 2, fy, sel and C.dark or C.text)
        else
            CQUI.textC(win, CQUI.fit(label, UIFont.Small, tw - 8), tx + tw / 2, fy, sel and C.gold or C.dim)
        end
    end
end

function CQUI.pill(win, x, y, text, c, font, fill)
    font = font or UIFont.Small
    c = c or C.accent
    local w = CQUI.tw(font, text) + 14
    local h = CQUI.fh(font) + 2
    CQUI.rbox(win, x, y, w, h, c, fill and 0.95 or 0.20, 6)
    CQUI.textC(win, text, x + w / 2, y + 1, fill and C.dark or c, 1, font)
    return w
end

function CQUI.bar(win, x, y, w, h, frac, c)
    frac = CQ.clamp(CQ.num(frac, 0), 0, 1)
    CQUI.rbox(win, x, y, w, h, C.panel3, 1, math.min(4, h / 2))
    if frac > 0 then CQUI.rbox(win, x, y, math.max(h, w * frac), h, c or C.accent, 1, math.min(4, h / 2)) end
end

function CQUI.sep(win, x, y, w)
    CQUI.rect(win, x, y, w, 1, C.line, 0.7)
end

function CQUI.section(win, x, y, w, label)
    CQUI.text(win, label, x, y, C.gold, 1, UIFont.Small)
    local lw = CQUI.tw(UIFont.Small, label)
    CQUI.rect(win, x + lw + 8, y + CQUI.fh(UIFont.Small) / 2, w - lw - 8, 1, C.line, 0.8)
    return CQUI.fh(UIFont.Small) + 6
end

-- ===================================================================== text entries (real child widgets)
function CQUI.entry(parent, x, y, w, h, opts)
    opts = opts or {}
    local e = ISTextEntryBox:new(opts.text or "", x, y, w, h)
    e.font = opts.font or UIFont.Small
    e:initialise()
    e:instantiate()
    if opts.multi then
        e:setMultipleLine(true)
        e:setMaxLines(opts.lines or 60)
    end
    if opts.num then e:setOnlyNumbers(true) end
    if opts.max then e:setMaxTextLength(opts.max) end
    e.backgroundColor = { r = 0.035, g = 0.04, b = 0.065, a = 0.95 }
    e.borderColor = { r = 0.32, g = 0.34, b = 0.46, a = 1 }
    if opts.tip then e.tooltip = opts.tip end
    parent:addChild(e)
    return e
end

function CQUI.val(e)
    if not e then return "" end
    return tostring(e:getText() or "")
end

function CQUI.setVal(e, v)
    if e then e:setText(tostring(v or "")) end
end

-- ===================================================================== formatting helpers (translated)
local T = CQC.txt

function CQUI.dur(sec)
    sec = math.max(0, math.floor(CQ.num(sec, 0)))
    if sec >= 86400 then
        local d = math.floor(sec / 86400)
        local h = math.floor(CQ.mod(sec, 86400) / 3600)
        return T("IGUI_CQ_DurDH", d, h)
    end
    return CQ.clock(sec)
end

-- minutes -> "2 h 15 min" style
function CQUI.durMin(mins)
    mins = math.max(0, math.floor(CQ.num(mins, 0)))
    local h = math.floor(mins / 60)
    local m = CQ.mod(mins, 60)
    if h >= 24 then return CQUI.dur(mins * 60) end
    if h > 0 and m > 0 then return T("IGUI_CQ_DurHM", h, m) end
    if h > 0 then return T("IGUI_CQ_DurH", h) end
    return T("IGUI_CQ_DurM", m)
end

function CQUI.dateText(ts)
    local lt = CQ.localT(ts, CQC.utc())
    return T("IGUI_CQ_Date", T("IGUI_CQ_Wd" .. lt.wday), lt.d, T("IGUI_CQ_Mon" .. lt.m), CQ.pad2(lt.hour) .. ":" .. CQ.pad2(lt.min))
end

function CQUI.dayText(day)
    local y, m, d = CQ.civil(day)
    local wd = CQ.mod(day + 4, 7)
    return T("IGUI_CQ_Day", T("IGUI_CQ_Wd" .. wd), d, T("IGUI_CQ_Mon" .. m))
end

function CQUI.itemsText(list, max)
    if type(list) ~= "table" or #list == 0 then return "" end
    local parts = {}
    for i = 1, #list do
        if max and i > max then
            parts[#parts + 1] = "+" .. tostring(#list - max)
            break
        end
        parts[#parts + 1] = CQC.itemName(list[i].t) .. " x" .. tostring(list[i].n)
    end
    return table.concat(parts, ", ")
end

function CQUI.stepLabel(st)
    if not st then return "" end
    if st.label and st.label ~= "" then return st.label end
    if st.t == "?" then return T("IGUI_CQ_StepHidden") end
    return T("IGUI_CQ_StepT_" .. tostring(st.t))
end

function CQUI.stepGoal(st)
    if not st then return "" end
    local t = st.t
    if t == "deliver" or t == "collect" then return T("IGUI_CQ_Goal_" .. t, CQC.itemName(st.item), st.n or 1) end
    if t == "kill" or t == "others" then return T("IGUI_CQ_Goal_" .. t, st.n or 1) end
    if t == "hold" then return T("IGUI_CQ_Goal_hold", CQ.clock(st.sec or 60)) end
    if t == "rescue" then return T("IGUI_CQ_Goal_rescue", st.target or "?") end
    if t == "radio" then return T("IGUI_CQ_Goal_radio", CQ.chText(st.ch)) end
    if t == "reach" then return T("IGUI_CQ_Goal_reach") end
    if t == "admin" then return T("IGUI_CQ_Goal_admin") end
    return ""
end

CQUI.STEP_ICON = {
    reach = "cq_s_reach", deliver = "cq_s_deliver", kill = "cq_s_kill", collect = "cq_s_collect",
    rescue = "cq_s_rescue", hold = "cq_s_hold", radio = "cq_s_radio", others = "cq_s_others", admin = "cq_s_admin",
}
CQUI.STEP_COLOR = {
    reach = C.blue, deliver = C.accent, kill = C.bad, collect = C.gold, rescue = C.good,
    hold = C.purple, radio = { 0.55, 0.9, 0.95 }, others = { 0.85, 0.35, 0.65 }, admin = C.dim,
}

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 then return math.atan(y / x) - math.pi end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

-- 8-way direction name from world delta (screen-oriented, iso)
function CQUI.dirKey(dx, dy)
    local sx = dx - dy
    local sy = (dx + dy) * 0.5
    local ang = atan2(-sy, sx)
    local idx = CQ.mod(math.floor((ang / (math.pi * 2)) * 8 + 0.5), 8)
    local keys = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
    return keys[idx + 1] or "N"
end

-- chain of steps as icons; returns height
function CQUI.chain(win, x, y, w, inst)
    local n = inst.nSteps or #inst.steps
    if n <= 0 then return 0 end
    local size = 20
    local gap = math.min(30, math.max(6, (w - n * size) / math.max(1, n - 1)))
    local cx = x
    for i = 1, n do
        local st = inst.steps[i] or { t = "?" }
        local done = (inst.status == "done") or i < inst.step
        local cur = (inst.status == "active") and i == inst.step
        if i > 1 then
            CQUI.rect(win, cx - gap, y + size / 2 - 1, gap, 2, done and C.good or C.line, done and 0.9 or 0.8)
        end
        local col = done and C.good or (cur and C.accent or C.panel3)
        CQUI.rbox(win, cx, y, size, size, col, cur and 1 or (done and 0.9 or 1), 10)
        local ic = CQUI.STEP_ICON[st.t]
        local icCol = (done or cur) and C.dark or C.dim
        if not (ic and CQUI.icon(win, ic, cx + 3, y + 3, size - 6, icCol)) then
            CQUI.textC(win, st.t == "?" and "?" or tostring(i), cx + size / 2, y + (size - CQUI.fh(UIFont.Small)) / 2, icCol)
        end
        cx = cx + size + gap
        if cx > x + w then break end
    end
    return size
end

-- floors: z 0 = ground = "floor 1", below ground = basement
function CQUI.floorText(z)
    z = math.floor(z or 0)
    if z >= 0 then return CQC.txt("IGUI_CQ_FloorN", z + 1) end
    return CQC.txt("IGUI_CQ_Basement", -z)
end

-- "Floor 2 (up 1)" for a checkpoint zone seen from floor pz
function CQUI.floorInfo(zone, pz)
    if not zone then return "" end
    if zone.anyZ then return CQC.txt("IGUI_CQ_FloorAny") end
    local z = zone.z or 0
    local s = CQUI.floorText(z)
    local dz = z - math.floor(pz or 0)
    if dz > 0 then s = s .. " " .. CQC.txt("IGUI_CQ_FloorUp", dz)
    elseif dz < 0 then s = s .. " " .. CQC.txt("IGUI_CQ_FloorDown", -dz) end
    return s
end

-- standing on the spot's tiles but on another floor: tell which way to go
function CQUI.wrongFloor(zone, x, y, z)
    if not zone or zone.anyZ then return nil end
    if not CQ.inZone(zone, x, y, nil) or CQ.inZone(zone, x, y, z) then return nil end
    return CQC.txt("IGUI_CQ_WrongFloor", CQUI.floorInfo(zone, z))
end

-- where a mission came from: event title, board, sheet, admin, everyone
function CQUI.sourceText(inst)
    if inst.evTitle and inst.evTitle ~= "" then return inst.evTitle, CQUI.C.good end
    local v = inst.via or ""
    if v == "board" then return CQC.txt("IGUI_CQ_Src_board"), CQUI.C.blue end
    if v == "sheet" then return CQC.txt("IGUI_CQ_Src_sheet"), CQUI.C.accent end
    if v == "admin" then return CQC.txt("IGUI_CQ_Src_admin"), CQUI.C.purple end
    if v == "everyone" then return CQC.txt("IGUI_CQ_Src_everyone"), CQUI.C.accent end
    return nil
end

return CQUI
