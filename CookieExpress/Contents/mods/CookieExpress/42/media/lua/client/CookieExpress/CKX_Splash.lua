-- Cookie Express : first-impression glass screen ("your delivery is here")
-- Shown when deliveries arrive or on login; a click anywhere opens the delivery window.
if isServer() then return end

require "ISUI/ISPanel"
require "CookieExpress/CKX_Theme"
require "CookieExpress/CKX_Client"
require "CookieExpress/CKX_UI"

local UI = CKX.UI
local T = CKX.T
local Cl = CKX.Cl
local floor, min, sin = math.floor, math.min, math.sin

local SW, SH = 560, 330
local GLINT_START, GLINT_MS, GLINT_EVERY = 350, 900, 3600

CKXSplash = ISPanel:derive("CKXSplash")

function CKXSplash:new()
    local o = ISPanel.new(self, 0, 0, SW, SH)
    o.background = false
    o.moveWithMouse = false
    o.count = 0
    o.openAt = 0
    o.closing = nil
    o.pressed = false
    return o
end

function CKXSplash:center()
    self.baseX = floor((getCore():getScreenWidth() - SW) / 2)
    self.baseY = floor((getCore():getScreenHeight() - SH) / 2) - 20
    self:setX(self.baseX)
    self:setY(self.baseY)
end

function CKXSplash:show(count)
    self.count = count or 0
    self.openAt = CKX.nowMs()
    self.closing = nil
    self:center()
    self:setVisible(true)
    self:bringToTop()
end

function CKXSplash:dismiss()
    if self.closing then return end
    self.closing = CKX.nowMs()
end

function CKXSplash:onMouseDown(x, y)
    self.pressed = true
    return true
end

function CKXSplash:onMouseUp(x, y)
    if self.pressed then
        T.playSound("UIActivateButton")
        self:dismiss()
    end
    self.pressed = false
    return true
end

function CKXSplash:onMouseUpOutside()
    self.pressed = false
end

function CKXSplash:prerender() end

function CKXSplash:render()
    local now = CKX.nowMs()
    local t = now - self.openAt
    local fade = min(1, t / 260)
    if self.closing then
        local c = (now - self.closing) / 200
        if c >= 1 then
            self:setVisible(false)
            self.closing = nil
            UI.open(true)
            return
        end
        fade = fade * (1 - c)
    end
    -- slide in from slightly above
    local ease = 1 - (1 - fade) * (1 - fade)
    self:setY(self.baseY - floor((1 - ease) * 18))

    local c1, c2 = T.TXT, T.TXT2
    self:drawRect(10, 10, SW - 8, SH - 6, 0.18 * fade, 0.24, 0.06, 0.26)
    T.bezel(self, 0, 0, SW, SH, fade, { 16, 16, SW - 32, SH - 32 })
    T.screen(self, 16, 16, SW - 32, SH - 32, fade)

    -- glint sweep across the glass
    local g = t - GLINT_START
    if g >= 0 then
        local p = (g % GLINT_EVERY) / GLINT_MS
        if p <= 1 then T.glint(self, 19, 19, SW - 38, SH - 38, p, fade) end
    end

    -- house standing on the glass
    local bob = floor(sin(now / 420) * 1.5 + 0.5) * 2
    self:drawTextureScaled(T.tex("ckx_shadow"), 40, SH - 42, 150, 18, fade, 1, 1, 1)
    T.deco(self, "ckx_house_big", 30, SH - 24 - 214 + 2 + bob, fade)

    -- text column
    T.deco(self, "ckx_logo", 226, 54, fade)
    T.line(self, "title", { "arrived" }, 226, 92, "left", fade)
    T.line(self, "mid", { "count_a", self.count, "count_b" }, 232, 146, "left", fade)
    local pulse = floor(sin(now / 260) * 1.5 + 0.5)
    T.deco(self, "ckx_d_go", 232, 186 + pulse, fade)
    T.lineIn(self, "go", { "open" }, 290, 186 + pulse, 48, "left", fade)
    T.line(self, "sub", { "hint" }, 232, SH - 54, "left", fade * 0.9)

    -- decorations
    T.deco(self, "ckx_d_welcome", floor((SW - 200) / 2) + 2, -30, fade)
    T.deco(self, "ckx_d_sakura", -22, -22, fade)
    T.deco(self, "ckx_d_cookie", SW - 26, -14, fade)
    T.deco(self, "ckx_d_bearpink", SW - 58, SH - 34, fade)
    T.deco(self, "ckx_d_bearbrown", -12, SH - 30, fade)
    T.deco(self, "ckx_d_star", 196, 112 + pulse, fade)
    for k, p in ipairs({ { 40, 70 }, { 180, 90 }, { 470, 160 }, { 520, 60 }, { 214, 40 }, { 120, 40 } }) do
        T.sparkle(self, p[1], p[2], now / 170 + k * 1.7, fade)
    end
end

function UI.splash(count)
    if not UI.splashWin then
        UI.splashWin = CKXSplash:new()
        UI.splashWin:initialise()
        UI.splashWin:addToUIManager()
    end
    if UI.isOpen() then
        UI.open(true)
        return
    end
    if not UI.splashWin:isVisible() then T.playSound("UIToggleTickBox") end
    UI.splashWin:show(count)
end
