-- Cookie Helper : UI kit on top of the vanilla widgets, drawn in the teal theme (CH_Theme)
-- Windows, buttons, lists and inputs keep the vanilla behaviour (clicks, focus, scrolling);
-- only how they look is replaced. Everything is flat + rounded, cheap to draw.
if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "CookieHelper/CH_Shared"
require "CookieHelper/CH_Theme"

CHelp.UI = CHelp.UI or {}
local UI = CHelp.UI
local T = CHelp.Th
local C = T.C
local floor = math.floor

UI.FONT_S = T.FS
UI.FONT_M = T.FM
UI.FONT_L = T.FL
UI.HS = T.th(T.FS)
UI.HM = T.th(T.FM)
UI.HL = T.th(T.FL)
UI.BTN_H = UI.HS + 14
UI.PAD = 16
UI.GAP = 10
UI.HEAD_H = math.max(58, UI.HM + UI.HS + 20)
UI.R = 14             -- window corner
UI.RC = 12            -- card corner

-- old colour names used around the mod, mapped onto the new palette
UI.C = {
    bg = C.bg, head = C.bar, card = C.surf, cardHi = C.surf3, line = C.line,
    text = C.text, muted = C.text3, mint = C.acc, gold = C.warn, red = C.bad,
}

function CHelp.t(key, ...)
    local k = "IGUI_CH_" .. key
    return getText(k, ...) or k
end
local t = CHelp.t

UI.fit = T.fit
function UI.text(el, s, x, y, c, font) T.text(el, s, x, y, c, font) end
function UI.textR(el, s, x, y, c, font) T.textR(el, s, x, y, c, font) end
function UI.textC(el, s, x, y, c, font) T.textC(el, s, x, y, c, font) end
function UI.rect(el, x, y, w, h, c, a) T.rect(el, x, y, w, h, c, a) end

function UI.center(w, h)
    return floor((getCore():getScreenWidth() - w) / 2), floor((getCore():getScreenHeight() - h) / 2)
end

function UI.keepOnScreen(win)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = math.max(0, math.min(win:getX(), sw - math.min(win.width, sw)))
    local y = math.max(0, math.min(win:getY(), sh - math.min(win.height, sh)))
    if x ~= win:getX() then win:setX(x) end
    if y ~= win:getY() then win:setY(y) end
end

-- ------------------------------------------------------------------ button
-- kind: pri (mint) / sec (dark) / bad (red text) / ghost / tab / tabOn / chip / chipOn / close / link
UI.Btn = ISButton:derive("CHelpBtn")

local KIND = {
    pri    = { bg = C.acc,   hov = C.acc2,  fg = C.onAcc, bold = true },
    sec    = { bg = C.surf2, hov = C.surf3, fg = C.text },
    bad    = { bg = C.badD,  hov = T.rgb("5A2C33"), fg = C.bad, bold = true },
    ghost  = { bg = nil,     hov = C.surf2, fg = C.text2 },
    tab    = { bg = nil,     hov = C.surf2, fg = C.text2, pill = true },
    tabOn  = { bg = C.acc,   hov = C.acc,   fg = C.onAcc, pill = true, bold = true },
    chip   = { bg = C.surf2, hov = C.surf3, fg = C.text2, pill = true },
    chipOn = { bg = C.acc,   hov = C.acc,   fg = C.onAcc, pill = true, bold = true },
    close  = { bg = C.surf2, hov = C.surf3, fg = C.text2, round = true },
    soft   = { bg = C.accD,  hov = T.rgb("235A49"), fg = C.acc, bold = true },
    off    = { bg = C.surf,  hov = C.surf,  fg = C.text3 },
}
UI.KIND = KIND

local OLD = { mint = "pri", red = "bad" }

function UI.Btn:setKind(kind)
    self.kind = OLD[kind] or kind or "sec"
end

function UI.Btn:setIcon(name, isPx)
    self.chIcon = name
    self.chIconPx = isPx == true
end

function UI.Btn:prerender()
    if not self:getIsVisible() then return end
    local st = KIND[self.enable and self.kind or "off"] or KIND.sec
    local hov = self.enable and self:isMouseOver()
    local bg = hov and st.hov or st.bg
    if self.selected and self.kind == "chip" then bg = C.acc end
    if self.drawFn then
        self.drawFn(self, self.width, self.height, hov)
        self:updateTooltip()
        return
    end
    if bg then
        local r = st.pill and floor(self.height / 2) or (st.round and floor(self.height / 2) or math.min(10, floor(self.height / 3)))
        T.rrect(self, 0, 0, self.width, self.height, r, bg, self.pressed and 0.8 or 1)
    end
    self:updateTooltip()
end

function UI.Btn:render()
    if self.drawFn then return end
    local st = KIND[self.enable and self.kind or "off"] or KIND.sec
    local fg = st.fg
    local h = self.height
    local isz = self.chIcon and math.min(h - 10, UI.HS + 2) or 0
    if self.chIconPx and self.chIcon then isz = (h >= 40) and 32 or 16 end
    local label = self.title or ""
    local f = self.font or T.FS
    local room = self.width - 14 - isz - ((label ~= "" and isz > 0) and 6 or 0)
    label = T.fit(label, room, f)
    local tw = (label ~= "") and T.tw(label, f) or 0
    local gap = (label ~= "" and isz > 0) and 6 or 0
    local total = isz + gap + tw
    local x = floor((self.width - total) / 2)
    if self.chIcon then
        if self.chIconPx then T.px(self, self.chIcon, x, floor((h - isz) / 2), isz)
        else T.icon(self, self.chIcon, x, floor((h - isz) / 2), isz, fg) end
    end
    if label ~= "" then
        T.text(self, label, x + isz + gap, floor((h - T.th(f)) / 2), fg, f)
    end
    if self.badge and self.badge > 0 then
        local s = tostring(self.badge)
        local bw = math.max(UI.HS + 2, T.tw(s) + 10)
        local bh = UI.HS + 2
        T.rrect(self, self.width - bw + 4, -4, bw, bh, floor(bh / 2), C.acc)
        T.textC(self, s, self.width - bw / 2 + 4, -3, C.onAcc)
    end
end

function UI.button(parent, x, y, w, title, target, onclick, kind, h)
    local b = UI.Btn:new(x, y, w, h or UI.BTN_H, title, target, onclick)
    b:initialise()
    b:instantiate()
    b:setKind(kind)
    b.font = T.FS
    if parent then parent:addChild(b) end
    return b
end

function UI.iconButton(parent, x, y, size, icon, target, onclick, kind, tip)
    local b = UI.button(parent, x, y, size, "", target, onclick, kind or "close", size)
    b:setIcon(icon)
    if tip then b.tooltip = tip end
    return b
end

function UI.style(btn, kind) btn:setKind(kind) end

-- ------------------------------------------------------------------ text entry (rounded dark field)
UI.Entry = ISTextEntryBox:derive("CHelpEntry")

function UI.Entry:prerender()
    local focus = self.javaObject and self.javaObject:isFocused()
    T.rrect(self, 0, 0, self.width, self.height, 10, focus and C.surf or C.bar)
    if focus then
        T.rect(self, 8, self.height - 2, self.width - 16, 2, C.acc)
    end
    local bg, bd = self.backgroundColor, self.borderColor
    self.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    ISTextEntryBox.prerender(self)
    self.backgroundColor, self.borderColor = bg, bd
end

function UI.entry(parent, x, y, w, text, h)
    local e = UI.Entry:new(text or "", x, y, w, h or UI.BTN_H)
    e:initialise()
    e:instantiate()
    e.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    e.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    if parent then parent:addChild(e) end
    return e
end

-- ------------------------------------------------------------------ window
UI.Window = ISPanel:derive("CHelpWindow")

function UI.Window:new(x, y, w, h, title)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title = title or "Cookie Helper"
    o.subtitle = nil
    o.headIcon = "cookie_64"
    o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

function UI.Window:createChildren()
    ISPanel.createChildren(self)
    local s = 32
    self.closeBtn = UI.iconButton(self, self.width - s - 14, floor((UI.HEAD_H - s) / 2), s, "close", self, UI.Window.onCloseClick, "close")
    self.closeBtn.anchorLeft = false
    self.closeBtn.anchorRight = true
end

function UI.Window:onCloseClick()
    self:close()
end

function UI.Window:close()
    if self.onClose then
        local ok, err = pcall(self.onClose, self)
        if not ok then CHelp.log("onClose failed: " .. tostring(err)) end
    end
    self:setVisible(false)
    self:removeFromUIManager()
end

-- right edge of the free header space (windows put header buttons left of the close button)
function UI.Window:headRight()
    return self.width - 14 - 32 - 10
end

function UI.Window:prerender()
    UI.keepOnScreen(self)
    -- soft shadow line under the window so it separates from the world
    T.rrect(self, 0, 2, self.width, self.height, UI.R, C.black, 0.35)
    T.rrect(self, 0, 0, self.width, self.height, UI.R, C.bg, 0.98)
    local ix = 16
    local tex = T.tex(self.headIcon or "cookie_64")
    local is = 34
    if tex then
        local tc = self.headTint or C.white
        self:drawTextureScaled(tex, ix, floor((UI.HEAD_H - is) / 2), is, is, 1, tc[1], tc[2], tc[3])
        ix = ix + is + 12
    end
    local maxW = (self.headTextRight or self:headRight()) - ix
    if self.subtitle and self.subtitle ~= "" then
        local y0 = floor((UI.HEAD_H - UI.HM - UI.HS - 2) / 2)
        T.text(self, T.fit(self.title, maxW, T.FM), ix, y0, C.text, T.FM)
        T.text(self, T.fit(self.subtitle, maxW), ix, y0 + UI.HM + 2, C.text3)
    else
        T.text(self, T.fit(self.title, maxW, T.FM), ix, floor((UI.HEAD_H - UI.HM) / 2), C.text, T.FM)
    end
    if self.drawBody then
        local ok, err = pcall(self.drawBody, self)
        if not ok then
            CHelp.log("draw " .. tostring(self.Type) .. " failed: " .. tostring(err))
            self.drawBody = false   -- false, not nil: nil would fall back to the class method
        end
    end
end

function UI.Window:render()
    if self.drawOver then
        local ok, err = pcall(self.drawOver, self)
        if not ok then
            CHelp.log("drawOver " .. tostring(self.Type) .. " failed: " .. tostring(err))
            self.drawOver = false
        end
    end
end

function UI.Window:show()
    self:initialise()
    self:addToUIManager()
    self:setVisible(true)
    self:bringToTop()
    return self
end

-- ------------------------------------------------------------------ list with custom rows
UI.List = ISScrollingListBox:derive("CHelpList")

function UI.List:new(x, y, w, h, rowH)
    local o = ISScrollingListBox:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.font = T.FS
    o.fontHgt = UI.HS
    o.itemheight = rowH or (UI.HS + 14)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.drawBorder = false
    o.selected = 0
    o.rowGap = 6
    return o
end

function UI.List:doDrawItem(y, item, alt)
    local h = item.height or self.itemheight
    if y + h < -self:getYScroll() or y > -self:getYScroll() + self.height then return y + h end
    local hover = self.mouseoverselected == item.index and self:isMouseOver()
    local sel = self.selected == item.index and not self.noSelect
    local rh = h - (self.rowGap or 0)
    local rw = self.width - (self:isVScrollBarVisible() and 14 or 0)
    if not self.bare then
        if sel then
            T.rring(self, 0, y, rw, rh, UI.RC, C.acc, C.surf, 2)
        else
            T.rrect(self, 0, y, rw, rh, UI.RC, hover and C.surf3 or C.surf)
        end
    end
    if self.drawRow then
        local ok, err = pcall(self.drawRow, self.rowTarget, self, item.item, 0, y, rw, rh, hover, sel)
        if not ok then
            CHelp.log("row draw failed: " .. tostring(err))
            self.drawRow = nil
        end
    else
        T.textV(self, T.fit(item.text, rw - 24), 12, y, rh, C.text)
    end
    return y + h
end

function UI.makeList(parent, x, y, w, h, rowH, target, drawRow, onClick)
    local l = UI.List:new(x, y, w, h, rowH)
    l:initialise()
    l:instantiate()
    l.rowTarget = target
    l.drawRow = drawRow
    if onClick then l:setOnMouseDownFunction(target, onClick) end
    if parent then parent:addChild(l) end
    return l
end

-- ------------------------------------------------------------------ segmented tabs
UI.Tabs = ISPanel:derive("CHelpTabs")

-- items = { { id, label }, ... }
function UI.tabs(parent, x, y, items, selected, target, onChange, h)
    h = h or (UI.HS + 14)
    local widths, total = {}, 6
    for i, it in ipairs(items) do
        widths[i] = T.tw(it.label) + 28
        total = total + widths[i] + 2
    end
    local o = ISPanel:new(x, y, total, h)
    setmetatable(o, UI.Tabs)
    UI.Tabs.__index = UI.Tabs
    o.items, o.widths, o.sel = items, widths, selected
    o.target, o.onChange = target, onChange
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o:initialise()
    o:instantiate()
    if parent then parent:addChild(o) end
    return o
end

function UI.Tabs:prerender()
    T.rrect(self, 0, 0, self.width, self.height, floor(self.height / 2), C.bar)
    local x = 3
    local mx = self:isMouseOver() and self:getMouseX() or -1
    for i, it in ipairs(self.items) do
        local w = self.widths[i]
        local on = it.id == self.sel
        local hov = mx >= x and mx < x + w
        if on then T.rrect(self, x, 3, w, self.height - 6, floor((self.height - 6) / 2), C.acc)
        elseif hov then T.rrect(self, x, 3, w, self.height - 6, floor((self.height - 6) / 2), C.surf2) end
        T.textC(self, it.label, x + w / 2, floor((self.height - UI.HS) / 2), on and C.onAcc or C.text2)
        if it.badge and it.badge > 0 then
            T.textR(self, tostring(it.badge), x + w - 6, 2, on and C.onAcc or C.acc)
        end
        x = x + w + 2
    end
end

function UI.Tabs:onMouseDown(mx, my)
    local x = 3
    for i, it in ipairs(self.items) do
        local w = self.widths[i]
        if mx >= x and mx < x + w then
            if self.sel ~= it.id then
                self.sel = it.id
                getSoundManager():playUISound("UISelectListItem")
                if self.onChange then self.onChange(self.target, it.id) end
            end
            return true
        end
        x = x + w + 2
    end
    return true
end

-- ------------------------------------------------------------------ toggle switch (drawn, part of a clickable button)
function UI.drawSwitch(el, x, y, on)
    local w, h = 40, 22
    T.rrect(el, x, y, w, h, 11, on and C.acc or C.line)
    T.circle(el, x + (on and 21 or 3), y + 3, 16, C.text)
end

-- ------------------------------------------------------------------ tooltip card (call from a window's drawOver)
function UI.drawTip(el, x, y, w, title, lines, foot)
    local lh = UI.HS + 3
    local wrapped = {}
    for _, s in ipairs(lines or {}) do
        for _, l in ipairs(T.wrap("• " .. s, w - 28)) do wrapped[#wrapped + 1] = l end
    end
    local h = 14 + UI.HS + 8 + #wrapped * lh + (foot and (lh + 10) or 0) + 12
    local sw = el.width
    if x + w > sw - 4 then x = sw - w - 4 end
    if x < 4 then x = 4 end
    if y + h > el.height - 4 then y = math.max(4, el.height - h - 4) end
    T.rrect(el, x, y + 4, w, h, UI.RC, C.black, 0.4)
    T.rrect(el, x, y, w, h, UI.RC, C.surf3)
    local cy = y + 14
    T.text(el, T.fit(title, w - 28), x + 14, cy, C.acc)
    cy = cy + UI.HS + 8
    for _, l in ipairs(wrapped) do
        T.text(el, l, x + 14, cy, C.text)
        cy = cy + lh
    end
    if foot then
        T.rect(el, x + 14, cy + 4, w - 28, 1, C.text, 0.08)
        T.text(el, T.fit(foot, w - 28), x + 14, cy + 10, C.text2)
    end
end

-- ------------------------------------------------------------------ toast (top centre, fades out)
UI.Toast = ISPanel:derive("CHelpToast")
UI.toasts = UI.toasts or {}

function UI.Toast:prerender()
    local age = CHelp.nowMs() - self.born
    local a = 1
    if age > self.life - 600 then a = math.max(0, (self.life - age) / 600) end
    if age > self.life then
        self:setVisible(false)
        self:removeFromUIManager()
        for i, v in ipairs(UI.toasts) do if v == self then table.remove(UI.toasts, i) break end end
        return
    end
    T.rrect(self, 0, 0, self.width, self.height, floor(self.height / 2), C.bar, 0.96 * a)
    local d = UI.HS + 4
    local cy = floor((self.height - d) / 2)
    T.circle(self, 10, cy, d, self.good and C.acc or C.bad, a)
    T.icon(self, self.good and "check" or "close", 13, cy + 3, d - 6, C.onAcc, a)
    T.text(self, self.msg, 18 + d, floor((self.height - UI.HS) / 2), C.text, T.FS, a)
end

function UI.toast(msg, good)
    msg = tostring(msg)
    local sw = getCore():getScreenWidth()
    local w = math.min(sw - 40, T.tw(msg) + UI.HS + 44)
    local h = UI.HS + 18
    local y = 70 + #UI.toasts * (h + 8)
    local o = ISPanel:new(floor((sw - w) / 2), y, w, h)
    setmetatable(o, UI.Toast)
    UI.Toast.__index = UI.Toast
    o.msg = T.fit(msg, w - UI.HS - 40)
    o.good = good ~= false
    o.born = CHelp.nowMs()
    o.life = 4500
    o.moveWithMouse = false
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    UI.toasts[#UI.toasts + 1] = o
    return o
end

-- ------------------------------------------------------------------ confirm / prompt (small modal windows)
local Confirm = UI.Window:derive("CHelpConfirm")

function Confirm:createChildren()
    UI.Window.createChildren(self)
    local bw = floor((self.width - UI.PAD * 2 - 8) / 2)
    local by = self.height - UI.BTN_H - UI.PAD
    UI.button(self, UI.PAD, by, bw, self.cancelLabel or t("Cancel"), self, Confirm.onNo, "sec")
    UI.button(self, UI.PAD + bw + 8, by, bw, self.okLabel or t("OK"), self, Confirm.onYes, self.danger and "bad" or "pri")
    if self.withEntry then
        self.entry = UI.entry(self, UI.PAD, by - UI.BTN_H - 12, self.width - UI.PAD * 2, self.initial or "")
        self.entry:focus()
    end
end

function Confirm:drawBody()
    local y = UI.HEAD_H + 4
    for _, l in ipairs(self.lines or {}) do
        T.text(self, l, UI.PAD, y, C.text2)
        y = y + UI.HS + 3
    end
end

function Confirm:onYes()
    local fn, target = self.fn, self.target
    local val = self.entry and self.entry:getInternalText() or true
    self:close()
    if fn then fn(target, val) end
end

function Confirm:onNo() self:close() end

local function openConfirm(title, text, okLabel, danger, target, fn, withEntry, initial)
    local w = 420
    local lines = T.wrap(text or "", w - UI.PAD * 2, T.FS, 6)
    local h = UI.HEAD_H + 4 + #lines * (UI.HS + 3) + 14 + (withEntry and (UI.BTN_H + 12) or 0) + UI.BTN_H + UI.PAD
    local x, y = UI.center(w, h)
    local win = Confirm:new(x, y - 60, w, h, title)
    win.lines, win.okLabel, win.danger, win.target, win.fn = lines, okLabel, danger, target, fn
    win.withEntry, win.initial = withEntry, initial
    win.headIcon = danger and "ic_warn" or "cookie_64"
    win.headTint = danger and C.bad or nil
    win:show()
    win:setAlwaysOnTop(true)
    return win
end

function UI.confirm(title, text, okLabel, danger, target, fn)
    return openConfirm(title, text, okLabel, danger, target, fn, false)
end

-- fn(target, text) only when OK is pressed
function UI.prompt(title, text, initial, okLabel, target, fn)
    return openConfirm(title, text, okLabel, false, target, fn, true, initial)
end
