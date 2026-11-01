-- Cookie Helper : UI kit (chocolate-cookie theme, flat rects only -> cheap to draw)
if isServer() then return end

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "CookieHelper/CH_Shared"

CHelp.UI = CHelp.UI or {}
local UI = CHelp.UI

local TM = getTextManager()
UI.FONT_S = UIFont.Small
UI.FONT_M = UIFont.Medium
UI.HS = TM:getFontHeight(UIFont.Small)
UI.HM = TM:getFontHeight(UIFont.Medium)
UI.BTN_H = UI.HS + 8
UI.PAD = 10
UI.HEAD_H = UI.HM + 12

UI.C = {
    bg      = { 0.17, 0.11, 0.08, 0.95 },
    head    = { 0.43, 0.27, 0.15, 1.00 },
    card    = { 0.25, 0.17, 0.12, 0.96 },
    cardHi  = { 0.34, 0.23, 0.15, 0.98 },
    line    = { 0.62, 0.42, 0.25, 0.85 },
    text    = { 1.00, 0.94, 0.84, 1.00 },
    muted   = { 0.80, 0.69, 0.56, 1.00 },
    mint    = { 0.56, 0.88, 0.63, 1.00 },
    gold    = { 1.00, 0.80, 0.38, 1.00 },
    red     = { 0.96, 0.46, 0.44, 1.00 },
    btn     = { 0.47, 0.30, 0.17, 1.00 },
    btnHi   = { 0.60, 0.40, 0.22, 1.00 },
    btnMint = { 0.24, 0.52, 0.33, 1.00 },
    btnRed  = { 0.55, 0.20, 0.18, 1.00 },
}

function CHelp.t(key, ...)
    local k = "IGUI_CH_" .. key
    return getText(k, ...) or k
end
local t = CHelp.t

function UI.rect(el, x, y, w, h, c, aMul)
    el:drawRect(x, y, w, h, c[4] * (aMul or 1), c[1], c[2], c[3])
end

function UI.border(el, x, y, w, h, c)
    el:drawRectBorder(x, y, w, h, c[4], c[1], c[2], c[3])
end

function UI.text(el, s, x, y, c, font)
    el:drawText(tostring(s), x, y, c[1], c[2], c[3], c[4], font or UI.FONT_S)
end

function UI.textR(el, s, x, y, c, font)
    el:drawTextRight(tostring(s), x, y, c[1], c[2], c[3], c[4], font or UI.FONT_S)
end

function UI.textC(el, s, x, y, c, font)
    el:drawTextCentre(tostring(s), x, y, c[1], c[2], c[3], c[4], font or UI.FONT_S)
end

-- cut a string so it fits w pixels (results cached: rows redraw every frame)
local fitCache, fitCount = {}, 0
function UI.fit(s, w, font)
    s = tostring(s or "")
    font = font or UI.FONT_S
    w = math.floor(w)
    local key = s .. "\1" .. w .. "\1" .. tostring(font)
    local hit = fitCache[key]
    if hit then return hit end
    local out = s
    if TM:MeasureStringX(font, s) > w then
        out = ".."
        local lo, hi = 1, string.len(s) - 1
        while lo <= hi do       -- binary search on the cut point
            local mid = math.floor((lo + hi) / 2)
            local m = mid
            -- never split a multi-byte UTF-8 character (Thai is 3 bytes)
            while m > 0 do
                local nb = string.byte(s, m + 1)
                if nb and nb >= 128 and nb < 192 then m = m - 1 else break end
            end
            local cut = string.sub(s, 1, m) .. ".."
            if TM:MeasureStringX(font, cut) <= w then out = cut lo = mid + 1 else hi = mid - 1 end
        end
    end
    fitCount = fitCount + 1
    if fitCount > 3000 then fitCache, fitCount = {}, 0 end
    fitCache[key] = out
    return out
end

function UI.style(btn, kind)
    local c = UI.C.btn
    if kind == "mint" then c = UI.C.btnMint elseif kind == "red" then c = UI.C.btnRed end
    btn:setBackgroundRGBA(c[1], c[2], c[3], 1)
    local h = UI.C.btnHi
    if kind == "mint" then h = { 0.32, 0.64, 0.42 } elseif kind == "red" then h = { 0.70, 0.28, 0.25 } end
    btn:setBackgroundColorMouseOverRGBA(h[1], h[2], h[3], 1)
    btn:setBorderRGBA(UI.C.line[1], UI.C.line[2], UI.C.line[3], 0.9)
    btn.textColor = { r = UI.C.text[1], g = UI.C.text[2], b = UI.C.text[3], a = 1 }
end

function UI.button(parent, x, y, w, title, target, onclick, kind, h)
    local b = ISButton:new(x, y, w, h or UI.BTN_H, title, target, onclick)
    b:initialise()
    b:instantiate()
    UI.style(b, kind)
    parent:addChild(b)
    return b
end

function UI.entry(parent, x, y, w, text)
    local e = ISTextEntryBox:new(text or "", x, y, w, UI.BTN_H)
    e:initialise()
    e:instantiate()
    e.backgroundColor = { r = 0.10, g = 0.07, b = 0.05, a = 1 }
    e.borderColor = { r = UI.C.line[1], g = UI.C.line[2], b = UI.C.line[3], a = 0.9 }
    parent:addChild(e)
    return e
end

-- ------------------------------------------------------------------ window
UI.Window = ISPanel:derive("CHelpWindow")

function UI.Window:new(x, y, w, h, title)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title = title or "Cookie Helper"
    o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.subtitle = nil
    return o
end

function UI.Window:createChildren()
    ISPanel.createChildren(self)
    local s = UI.HEAD_H - 8
    self.closeBtn = UI.button(self, self.width - s - 5, 4, s, "x", self, UI.Window.onCloseClick, "red", s)
    self.closeBtn.anchorLeft = false
    self.closeBtn.anchorRight = true
end

function UI.Window:onCloseClick()
    self:close()
end

function UI.Window:close()
    if self.onClose then self:onClose() end
    self:setVisible(false)
    self:removeFromUIManager()
end

function UI.Window:prerender()
    UI.rect(self, 0, 0, self.width, self.height, UI.C.bg)
    UI.rect(self, 0, 0, self.width, UI.HEAD_H, UI.C.head)
    -- three little cookie crumbs on the header
    UI.rect(self, 10, 9, 5, 5, UI.C.gold)
    UI.rect(self, 18, 15, 4, 4, UI.C.gold, 0.8)
    UI.rect(self, 12, UI.HEAD_H - 11, 4, 4, UI.C.gold, 0.7)
    UI.text(self, UI.fit(self.title, self.width - 90, UI.FONT_M), 30, 6, UI.C.text, UI.FONT_M)
    UI.border(self, 0, 0, self.width, self.height, UI.C.line)
    if self.drawBody then self:drawBody() end
end

function UI.Window:show()
    self:initialise()
    self:addToUIManager()
    self:setVisible(true)
    self:bringToTop()
    return self
end

function UI.center(w, h)
    return math.floor((getCore():getScreenWidth() - w) / 2), math.floor((getCore():getScreenHeight() - h) / 2)
end

-- ------------------------------------------------------------------ list with custom rows
UI.List = ISScrollingListBox:derive("CHelpList")

function UI.List:new(x, y, w, h, rowH)
    local o = ISScrollingListBox:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.font = UI.FONT_S
    o.fontHgt = UI.HS
    o.itemheight = rowH or (UI.HS + 10)
    o.backgroundColor = { r = 0.10, g = 0.07, b = 0.05, a = 0.85 }
    o.borderColor = { r = UI.C.line[1], g = UI.C.line[2], b = UI.C.line[3], a = 0.6 }
    o.drawBorder = true
    o.selected = 0
    return o
end

function UI.List:doDrawItem(y, item, alt)
    local h = item.height or self.itemheight
    if y + h < -self:getYScroll() or y > -self:getYScroll() + self.height then return y + h end
    local hover = self.mouseoverselected == item.index
    UI.rect(self, 2, y + 1, self.width - 4, h - 2, (hover or self.selected == item.index) and UI.C.cardHi or UI.C.card)
    if self.drawRow then
        self.drawRow(self.rowTarget, self, item.item, 2, y, self.width - 4, h, hover)
    else
        UI.text(self, UI.fit(item.text, self.width - 20), 10, y + (h - UI.HS) / 2, UI.C.text)
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
    parent:addChild(l)
    return l
end

-- ------------------------------------------------------------------ toast (top centre, fades out)
UI.Toast = ISPanel:derive("CHelpToast")
UI.toasts = {}

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
    UI.rect(self, 0, 0, self.width, self.height, UI.C.bg, a)
    UI.rect(self, 0, 0, 5, self.height, self.good and UI.C.mint or UI.C.red, a)
    self:drawRectBorder(0, 0, self.width, self.height, 0.8 * a, UI.C.line[1], UI.C.line[2], UI.C.line[3])
    self:drawText(self.msg, 14, (self.height - UI.HS) / 2, UI.C.text[1], UI.C.text[2], UI.C.text[3], a, UI.FONT_S)
end

function UI.toast(msg, good)
    msg = tostring(msg)
    local w = math.min(getCore():getScreenWidth() - 40, TM:MeasureStringX(UI.FONT_S, msg) + 30)
    local h = UI.HS + 14
    local y = 70 + #UI.toasts * (h + 6)
    local o = ISPanel:new(math.floor((getCore():getScreenWidth() - w) / 2), y, w, h)
    setmetatable(o, UI.Toast)
    UI.Toast.__index = UI.Toast
    o.msg = UI.fit(msg, w - 24)
    o.good = good ~= false
    o.born = CHelp.nowMs()
    o.life = 4500
    o.moveWithMouse = false
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    UI.toasts[#UI.toasts + 1] = o
    return o
end
