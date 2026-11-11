-- Cookie Express : delivery window (glass screen) + floating house button
if isServer() then return end

require "ISUI/ISPanel"
require "CookieExpress/CKX_Theme"
require "CookieExpress/CKX_Client"

CKX.UI = CKX.UI or {}
local UI = CKX.UI
local T = CKX.T
local Cl = CKX.Cl
local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local W, SY, RH, GAP, VIS = 460, 84, 52, 6, 4
local LIST_Y = SY + 8
local BUSY_MS = 6000

local function screenW() return getCore():getScreenWidth() end
local function screenH() return getCore():getScreenHeight() end

-- ================================================================== window
CKXWindow = ISPanel:derive("CKXWindow")

function CKXWindow:new()
    local o = ISPanel.new(self, floor((screenW() - W) / 2), floor(screenH() / 2 - 170), W, 300)
    o.background = false
    o.moveWithMouse = false
    o.scroll = 0
    o.maxScroll = 0
    o.busy = {}
    o.allBusy = nil
    o.press = nil
    o.dragging = false
    o.userMoved = false
    o.msg = nil
    o.msgUntil = 0
    o.openAt = 0
    o.burstAt = 0
    return o
end

function CKXWindow:rowsShown()
    local n = #Cl.entries
    if n < 1 then n = 1 end
    if n > VIS then n = VIS end
    return n
end

function CKXWindow:listH()
    local n = self:rowsShown()
    return n * RH + (n - 1) * GAP
end

function CKXWindow:footY()
    return SY + self:listH() + 16 + 10
end

function CKXWindow:layout()
    local h = self:footY() + 24 + 14
    if h ~= self.height then self:setHeight(h) end
    local total = #Cl.entries * (RH + GAP) - GAP
    self.maxScroll = max(0, total - self:listH())
    if self.scroll > self.maxScroll then self.scroll = self.maxScroll end
    if self.scroll < 0 then self.scroll = 0 end
    if not self.userMoved then
        self:setX(floor((screenW() - W) / 2))
        self:setY(floor((screenH() - h) / 2))
    end
    local now = CKX.nowMs()
    for k, t in pairs(self.busy) do
        if now - t > BUSY_MS then self.busy[k] = nil end
    end
    if self.allBusy and now - self.allBusy > BUSY_MS then self.allBusy = nil end
end

function CKXWindow:rowY(i)
    return LIST_Y + (i - 1) * (RH + GAP) - self.scroll
end

local function keyOf(e) return tostring(e.o) .. "#" .. tostring(e.i) end

function CKXWindow:targetAt(mx, my)
    if T.hit(mx, my, W - 46, 12, 22, 22) then return "close" end
    local fy = self:footY()
    if #Cl.entries > 0 and T.hit(mx, my, W - 16 - 150, fy, 150, 24) then return "all" end
    if T.hit(mx, my, W - 16 - 150 - 8 - 100, fy, 100, 24) then return "later" end
    local lh = self:listH()
    if my >= LIST_Y and my < LIST_Y + lh then
        for i = 1, #Cl.entries do
            local ry = self:rowY(i)
            if T.hit(mx, my, 20 + (W - 40) - 88, ry + 8, 80, 36) then return "claim:" .. i end
        end
    end
    if my < 70 then return "drag" end
    return nil
end

function CKXWindow:activate(target)
    local now = CKX.nowMs()
    if target == "close" or target == "later" then
        UI.close()
    elseif target == "all" then
        if not self.allBusy and #Cl.entries > 0 then
            self.allBusy = now
            for _, e in ipairs(Cl.entries) do self.busy[keyOf(e)] = now end
            T.playSound("UIActivateButton")
            CKX.toServer("claimAll", {})
        end
    elseif string.sub(target, 1, 6) == "claim:" then
        local e = Cl.entries[tonumber(string.sub(target, 7))]
        if e and not self.busy[keyOf(e)] then
            self.busy[keyOf(e)] = now
            T.playSound("UIActivateButton")
            CKX.toServer("claim", { o = e.o, i = e.i })
        end
    end
end

function CKXWindow:onMouseDown(x, y)
    self.press = self:targetAt(x, y)
    if self.press == "drag" then self.dragging = true end
    return true
end

function CKXWindow:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
        self.userMoved = true
    end
end
CKXWindow.onMouseMoveOutside = CKXWindow.onMouseMove

function CKXWindow:onMouseUp(x, y)
    local was = self.press
    self.press = nil
    self.dragging = false
    if was and was ~= "drag" and self:targetAt(x, y) == was then self:activate(was) end
    return true
end

function CKXWindow:onMouseUpOutside()
    self.press = nil
    self.dragging = false
end

function CKXWindow:onMouseWheel(del)
    self.scroll = min(self.maxScroll, max(0, self.scroll + del * (RH + GAP)))
    return true
end

function CKXWindow:prerender() end

function CKXWindow:buttonState(target, mx, my, enabled)
    if not enabled then return "off" end
    local over = self:targetAt(mx, my) == target
    if over and self.press == target then return "down" end
    if over then return "hover" end
    return nil
end

function CKXWindow:render()
    local now = CKX.nowMs()
    local fade = min(1, (now - self.openAt) / 220)
    local h = self.height
    local mx, my = self:getMouseX(), self:getMouseY()
    local fS, fM = UIFont.Small, UIFont.Medium
    local c1, c2 = T.TXT, T.TXT2

    -- frame
    self:drawRect(8, 8, W - 8, h - 4, 0.16 * fade, 0.24, 0.06, 0.26)
    T.deco(self, "ckx_ribbons", -38, -8, fade)
    local lh = self:listH()
    T.bezel(self, 0, 0, W, h, fade, { 12, SY, W - 24, lh + 16 })

    -- header
    T.deco(self, "ckx_logo", 16, 12, fade)
    T.line(self, "sub", { "subtitle" }, 22, 44, "left", fade)
    self:setStencilRect(10, 72, W - 20, 8)
    T.tile(self, "ckx_checker2", 10, 72, W - 20, 8, 16, fade)
    self:clearStencilRect()

    -- glass screen + list
    T.screen(self, 12, SY, W - 24, lh + 16, fade)
    self:setStencilRect(16, LIST_Y - 4, W - 32, lh + 8)
    if #Cl.entries == 0 then
        T.deco(self, "ckx_house_btn", floor(W / 2 - 32), LIST_Y - 14, 0.45 * fade)
        T.line(self, "body", { "empty" }, W / 2, LIST_Y + 12, "center", fade)
    end
    for i, e in ipairs(Cl.entries) do
        local ry = self:rowY(i)
        if ry + RH >= LIST_Y - 4 and ry <= LIST_Y + lh + 4 then
            local rx, rw = 20, W - 40
            local over = T.hit(mx, my, rx, ry, rw, RH) and my >= LIST_Y and my < LIST_Y + lh
            if over then
                T.nine(self, "ckx_rowh", rx, ry, rw, RH, 8, 4, T.ROW_BANDS, T.ROWH_ALPHA, fade)
            else
                T.nine(self, "ckx_row", rx, ry, rw, RH, 8, 4, T.ROW_BANDS, T.ROW_ALPHA, fade)
            end
            local inf = Cl.itemInfo(e.k, e.ft)
            T.deco(self, "ckx_slot", rx + 8, ry + 8, fade)
            if inf.tex then self:drawTextureScaledAspect(inf.tex, rx + 10, ry + 10, 32, 32, fade, 1, 1, 1) end
            self:drawText(T.fit(inf.name, fM, rw - 52 - 96), rx + 52, ry + 6, c1[1], c1[2], c1[3], fade, fM)
            local sub = "x" .. tostring(e.n)
            if e.note and e.note ~= "" then sub = sub .. "   " .. e.note end
            self:drawText(T.fit(sub, fS, rw - 52 - 96), rx + 52, ry + 29, c2[1], c2[2], c2[3], fade, fS)
            -- claim = pink check button
            local busy = self.busy[keyOf(e)] ~= nil
            local st = self:buttonState("claim:" .. i, mx, my, not busy)
            local bx, by = rx + rw - 88, ry + 8
            if st == "hover" then by = by - 1 elseif st == "down" then by = by + 1 end
            T.deco(self, "ckx_d_check", bx, by, busy and 0.45 * fade or fade)
            if st == "hover" then self:drawRect(bx + 10, by + 6, 56, 2, 0.4 * fade, 1, 1, 1) end
            if busy then T.sparkle(self, bx + 36, by + 12, now / 120, fade) end
        end
    end
    self:clearStencilRect()
    if self.maxScroll > 0 then
        local barH = max(18, floor(lh * lh / (lh + self.maxScroll)))
        local barY = LIST_Y + floor((lh - barH) * self.scroll / self.maxScroll)
        self:drawRect(W - 19, LIST_Y, 3, lh, 0.35 * fade, 1, 1, 1)
        self:drawRect(W - 19, barY, 3, barH, 0.95 * fade, 1.0, 0.25, 0.56)
    end

    -- footer
    local fy = self:footY()
    if self.msg and now < self.msgUntil then
        T.lineIn(self, "pink", self.msg, 30, fy, 24, "left", fade)
    else
        T.lineIn(self, "sub", { "waiting_a", #Cl.entries, "waiting_b" }, 30, fy, 24, "left", fade)
    end
    T.pillImg(self, "w", W - 16 - 150 - 8 - 100, fy, 100, { style = "btnp", parts = { "later" } },
        self:buttonState("later", mx, my, true), fade)
    T.pillImg(self, "t", W - 16 - 150, fy, 150, { style = "btnw", parts = { "claimall", "#(" .. #Cl.entries .. ")" } },
        self:buttonState("all", mx, my, #Cl.entries > 0 and not self.allBusy), fade)
    if self.allBusy then T.sparkle(self, W - 16 - 20, fy + 7, now / 120, fade) end

    -- decorations on top of the frame
    T.deco(self, "ckx_d_sakura", -24, -22, fade)
    T.deco(self, "ckx_d_bearpink", 352, -26, fade)
    T.deco(self, "ckx_d_cookie", W - 26, -14, fade)
    local closeHot = self:targetAt(mx, my) == "close"
    T.deco(self, "ckx_close", W - 44, 14, fade * (closeHot and 1 or 0.85))
    T.deco(self, "ckx_d_bearbrown", -10, h - 26, fade)
    for k, p in ipairs({ { 340, 44 }, { 300, 34 }, { 60, SY + 12 } }) do
        T.sparkle(self, p[1], p[2], now / 160 + k * 1.3, fade)
    end

    -- claim burst
    local bt = now - self.burstAt
    if bt < 900 then
        for k = 0, 5 do
            local ang = k * 1.047 + bt / 300
            local r = 18 + bt / 25
            T.sparkle(self, W - 90 + math.cos(ang) * r, fy + 6 + sin(ang) * r * 0.5, bt / 120 + k, 1 - bt / 900)
        end
    end
end

-- ================================================================== floating house button
CKXCookie = ISPanel:derive("CKXCookie")
UI.POS_FILE = "CookieExpress_ui.txt"
UI.BTN_W, UI.BTN_H = 76, 92

function CKXCookie:new(x, y)
    local o = ISPanel.new(self, x, y, UI.BTN_W, UI.BTN_H)
    o.background = false
    o.moveWithMouse = false
    o.pressed = false
    o.dragging = false
    o.moved = 0
    return o
end

function CKXCookie:clamp()
    local x = min(max(0, self.x), screenW() - self.width)
    local y = min(max(0, self.y), screenH() - self.height)
    self:setX(x)
    self:setY(y)
end

function CKXCookie:prerender() end

function CKXCookie:render()
    local now = CKX.nowMs()
    local n = Cl.count or 0
    local over = self:isMouseOver()
    local bob = 0
    if n > 0 and not self.dragging then bob = floor(sin(now / 280) * 2 + 0.5) end
    self:drawTextureScaled(T.tex("ckx_shadow"), 8, 78, 60, 12, 1, 1, 1, 1)
    if over or self.pressed then
        T.deco(self, "ckx_house_btn_hot", 4, 2 + bob, 1)
    else
        T.deco(self, "ckx_house_btn", 6, 4 + bob, 1)
    end
    if over and not self.dragging then
        local parts = { "tip" }
        if n > 0 then parts[2] = "#(" .. n .. ")" end
        local okK, shift = pcall(function() return isKeyDown(Keyboard.KEY_LSHIFT) end)
        local credit = okK and shift
        local tw
        if credit then
            tw = getTextManager():MeasureStringX(UIFont.Small, CKX.CREDIT .. "  " .. CKX.VERSION) + 24
        else
            tw = T.lineW("body", parts) + 20
        end
        local tx = -tw - 8
        local left = self.x + tx >= 0
        if not left then tx = self.width + 8 end
        T.nine(self, "ckx_rowh", tx, 30, tw, 28, 8, 4, T.ROW_BANDS, T.ROWH_ALPHA, 1)
        if left then T.deco(self, "ckx_tail", -9, 37, 1) end
        if credit then
            local c = T.TXT
            local fh = getTextManager():getFontHeight(UIFont.Small)
            self:drawText(CKX.CREDIT .. "  " .. CKX.VERSION, tx + 12, 30 + floor((28 - fh) / 2), c[1], c[2], c[3], 1, UIFont.Small)
        else
            T.lineIn(self, "body", parts, tx + 10, 30, 28, "left", 1)
        end
    end
    if n > 0 then
        T.sparkle(self, 2, 10 + bob, now / 150, 1)
        T.deco(self, "ckx_badge", 54, bob, 1)
        T.lineIn(self, "badge", { n > 99 and "#99+" or n }, 65, bob, 22, "center", 1)
    end
end

function CKXCookie:onMouseDown(x, y)
    self.pressed = true
    self.moved = 0
    return true
end

function CKXCookie:onMouseMove(dx, dy)
    if not self.pressed then return end
    self.moved = self.moved + math.abs(dx) + math.abs(dy)
    if self.moved > 4 then self.dragging = true end
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end
CKXCookie.onMouseMoveOutside = CKXCookie.onMouseMove

function CKXCookie:onMouseUp(x, y)
    if self.dragging then
        self:clamp()
        UI.savePos(self.x, self.y)
    elseif self.pressed then
        UI.toggle()
    end
    self.pressed = false
    self.dragging = false
    return true
end

function CKXCookie:onMouseUpOutside()
    if self.dragging then
        self:clamp()
        UI.savePos(self.x, self.y)
    end
    self.pressed = false
    self.dragging = false
end

-- ================================================================== toast (image text, top centre)
CKXToast = ISPanel:derive("CKXToast")
local TOAST_MS = 3800

function CKXToast:new()
    local o = ISPanel.new(self, 0, 110, 100, 40)
    o.background = false
    o.at = 0
    return o
end

function CKXToast:show(style, parts)
    self.style, self.parts = style, parts
    self.at = CKX.nowMs()
    local w = T.lineW(style, parts) + 44
    self:setWidth(w)
    self:setX(floor((screenW() - w) / 2))
    self:setY(110)
    self:setVisible(true)
    self:bringToTop()
end

function CKXToast:prerender() end

function CKXToast:render()
    local t = CKX.nowMs() - self.at
    if t > TOAST_MS then
        self:setVisible(false)
        return
    end
    local fade = min(1, t / 200)
    if t > TOAST_MS - 500 then fade = (TOAST_MS - t) / 500 end
    T.nine(self, "ckx_rowh", 0, 0, self.width, 40, 8, 4, T.ROW_BANDS, T.ROWH_ALPHA, fade)
    T.sparkle(self, 6, 4, t / 140, fade)
    T.lineIn(self, self.style, self.parts, self.width / 2, 0, 40, "center", fade)
end

function CKXToast:onMouseDown()
    self:setVisible(false)
    return true
end

function UI.toast(style, parts)
    if not UI.toastWin then
        UI.toastWin = CKXToast:new()
        UI.toastWin:initialise()
        UI.toastWin:addToUIManager()
    end
    UI.toastWin:show(style, parts)
end

-- ================================================================== module
function UI.savePos(x, y)
    pcall(function()
        local w = getFileWriter(UI.POS_FILE, true, false)
        w:writeln(floor(x) .. "," .. floor(y))
        w:close()
    end)
end

function UI.loadPos()
    local x, y = screenW() - UI.BTN_W - 20, floor(screenH() * 0.42)
    pcall(function()
        local r = getFileReader(UI.POS_FILE, false)
        if r then
            local line = r:readLine()
            r:close()
            if line then
                local c = string.find(line, ",", 1, true)
                if c then
                    x = tonumber(string.sub(line, 1, c - 1)) or x
                    y = tonumber(string.sub(line, c + 1)) or y
                end
            end
        end
    end)
    return x, y
end

function UI.ensure()
    if not UI.win then
        UI.win = CKXWindow:new()
        UI.win:initialise()
        UI.win:addToUIManager()
        UI.win:setVisible(false)
    end
    if not UI.btn then
        local x, y = UI.loadPos()
        UI.btn = CKXCookie:new(x, y)
        UI.btn:initialise()
        UI.btn:addToUIManager()
        UI.btn:setVisible(true)
        UI.btn:clamp()
    end
end

function UI.isOpen()
    return UI.win and UI.win:isVisible()
end

function UI.open(arrived)
    UI.ensure()
    if UI.splashWin and UI.splashWin:isVisible() and not UI.splashWin.closing then
        UI.splashWin:setVisible(false)
    end
    UI.win:layout()
    if not UI.win:isVisible() then
        UI.win.openAt = CKX.nowMs()
        UI.win:setVisible(true)
    end
    UI.win:bringToTop()
    if arrived then
        UI.win.burstAt = CKX.nowMs()
        T.playSound("UIToggleTickBox")
    end
end

function UI.close()
    if UI.win then UI.win:setVisible(false) end
end

function UI.toggle()
    if UI.isOpen() then
        UI.close()
    else
        UI.open(false)
        CKX.toServer("refresh", {})
    end
end

function UI.refresh()
    UI.ensure()
    UI.win:layout()
    if UI.splashWin and UI.splashWin:isVisible() then UI.splashWin.count = Cl.count end
end

function UI.onClaimed(ok, got, fails)
    UI.ensure()
    local w = UI.win
    w.busy = {}
    w.allBusy = nil
    local now = CKX.nowMs()
    if ok and #got > 0 then
        w.msg = { "got_a", #got, "got_b" }
        w.burstAt = now
        T.playSound("UIToggleTickBox")
    else
        w.msg = { "failed" }
    end
    w.msgUntil = now + 3500
end

Events.OnGameStart.Add(UI.ensure)
Events.OnResolutionChange.Add(function()
    if UI.btn then UI.btn:clamp() end
    if UI.win then UI.win:layout() end
    if UI.splashWin then UI.splashWin:center() end
end)
