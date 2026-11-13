-- Cookie On the Way : UI v2 drawing kit (black panel, glowing green edge, cut corners, line icons)
-- Shapes are solid quads: UIElement.DrawTexture with no texture takes screen coordinates, so every
-- helper here adds the element's absolute position (rects and textures stay element-relative).
-- Icons are white line art in media/ui/cotw/, tinted when drawn.
-- COTWBtn: an ISButton drawn in one of the styles below; clicks and hit-testing stay ISButton's.

require "ISUI/ISButton"

COTW.UI = COTW.UI or {}
local U = COTW.UI

local function rgb(h)
    return { tonumber(string.sub(h, 1, 2), 16) / 255, tonumber(string.sub(h, 3, 4), 16) / 255, tonumber(string.sub(h, 5, 6), 16) / 255 }
end

U.C = {
    panel = rgb("101814"), panel2 = rgb("15211b"), line = rgb("23362c"), map = rgb("0d1612"),
    g = rgb("2fe37a"), g2 = rgb("1aa556"), gLight = rgb("46f08c"), gEdge = rgb("1c5a35"),
    ink = rgb("e8f3ec"), mute = rgb("8aa396"), dark = rgb("04140a"), off = rgb("55675d"), offIcon = rgb("3a4a41"),
    amber = rgb("ffb547"), red = rgb("ff4d4d"), red1 = rgb("ff6b6b"), red2 = rgb("c42f2f"),
    road = rgb("1f3328"), roadDash = rgb("2a4537"), black = { 0, 0, 0 }, white = { 1, 1, 1 },
}
local C = U.C

U.FONT_S = getTextManager():getFontHeight(UIFont.Small)
U.FONT_M = getTextManager():getFontHeight(UIFont.Medium)
U.FONT_L = getTextManager():getFontHeight(UIFont.Large)

function U.textW(text, font) return getTextManager():MeasureStringX(font or UIFont.Small, text) end

-- words to lines no wider than maxW
function U.wrap(text, maxW, font)
    local lines, cur = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if cur ~= "" and U.textW(try, font) > maxW then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

-- ------------------------------------------------------------------------------
-- shapes (x, y relative to el)
-- ------------------------------------------------------------------------------
function U.quad(el, x1, y1, x2, y2, x3, y3, x4, y4, c, a)
    local ax, ay = el:getAbsoluteX(), el:getAbsoluteY()
    el.javaObject:DrawTexture(nil, ax + x1, ay + y1, ax + x2, ay + y2, ax + x3, ay + y3, ax + x4, ay + y4, c[1], c[2], c[3], a or 1)
end

function U.rect(el, x, y, w, h, c, a)
    if w <= 0 or h <= 0 then return end
    el:drawRect(x, y, w, h, a or 1, c[1], c[2], c[3])
end

-- top-left and bottom-right corners cut (the frame, buttons, tiles)
function U.chamfer(el, x, y, w, h, cut, c, a)
    local k = math.min(cut, w / 2, h / 2)
    U.quad(el, x + k, y, x + w, y, x + w, y + k, x, y + k, c, a)
    U.rect(el, x, y + k, w, h - 2 * k, c, a)
    U.quad(el, x, y + h - k, x + w, y + h - k, x + w - k, y + h, x, y + h, c, a)
end

-- a 1 px-ish outline of the same shape (edge in c, inside left alone)
function U.chamferLine(el, x, y, w, h, cut, c, a, t)
    t = t or 1
    local k = math.min(cut, w / 2, h / 2)
    U.line(el, x + k, y + t / 2, x + w, y + t / 2, t, c, a)
    U.line(el, x + w - t / 2, y, x + w - t / 2, y + h - k, t, c, a)
    U.line(el, x + w, y + h - k, x + w - k, y + h, t, c, a)
    U.line(el, x + w - k, y + h - t / 2, x, y + h - t / 2, t, c, a)
    U.line(el, x + t / 2, y + h, x + t / 2, y + k, t, c, a)
    U.line(el, x, y + k, x + k, y, t, c, a)
end

-- both bottom corners cut (the on-screen strip)
function U.strip(el, x, y, w, h, cut, c, a)
    U.rect(el, x, y, w, h - cut, c, a)
    U.quad(el, x, y + h - cut, x + w, y + h - cut, x + w - cut, y + h, x + cut, y + h, c, a)
end

-- flat-topped hexagon
function U.hex(el, x, y, w, h, c, a)
    local q = w / 4
    U.rect(el, x + q, y, w - 2 * q, h, c, a)
    U.quad(el, x + q, y, x + q, y + h, x, y + h / 2, x, y + h / 2, c, a)
    U.quad(el, x + w - q, y, x + w, y + h / 2, x + w, y + h / 2, x + w - q, y + h, c, a)
end

-- arrow-shaped step tab: notch on the left (unless first), point on the right
function U.tab(el, x, y, w, h, first, c, a)
    local p = 8
    U.rect(el, x + (first and 0 or p), y, w - p - (first and 0 or p), h, c, a)
    U.quad(el, x + w - p, y, x + w, y + h / 2, x + w, y + h / 2, x + w - p, y + h, c, a)
    if first then return end
    U.quad(el, x, y, x + p, y, x + p, y + h / 2, x + p, y + h / 2, c, a)
    U.quad(el, x + p, y + h / 2, x + p, y + h, x, y + h, x, y + h, c, a)
end

function U.line(el, x1, y1, x2, y2, w, c, a)
    local dx, dy = x2 - x1, y2 - y1
    local L = math.sqrt(dx * dx + dy * dy)
    if L < 0.01 then return end
    local nx, ny = -dy / L * w / 2, dx / L * w / 2
    U.quad(el, x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny, c, a)
end

-- ring piece from angle a0 to a1 (rad, 0 = right, clockwise on screen)
function U.arc(el, cx, cy, r, thick, a0, a1, c, a, segs)
    local n = segs or math.max(4, math.floor(math.abs(a1 - a0) / 0.15))
    local ri, ro = r - thick / 2, r + thick / 2
    local p = a0
    for i = 1, n do
        local t = a0 + (a1 - a0) * i / n
        local c0, s0, c1, s1 = math.cos(p), math.sin(p), math.cos(t), math.sin(t)
        U.quad(el, cx + c0 * ro, cy + s0 * ro, cx + c1 * ro, cy + s1 * ro, cx + c1 * ri, cy + s1 * ri, cx + c0 * ri, cy + s0 * ri, c, a)
        p = t
    end
end

function U.disc(el, cx, cy, r, c, a)
    local n = r > 6 and 16 or 10
    for i = 1, n do
        local a0, a1 = (i - 1) / n * 2 * math.pi, i / n * 2 * math.pi
        U.quad(el, cx, cy, cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r, cx, cy, c, a)
    end
end

-- expanding, fading ring (a "you are here" / pin ping)
function U.ping(el, cx, cy, r, c)
    local t = (getTimestampMs() % 1600) / 1600
    U.arc(el, cx, cy, r * (0.4 + 2 * t), 2, 0, 2 * math.pi, c, 0.9 * (1 - t), 20)
end

-- ------------------------------------------------------------------------------
-- icons and text
-- ------------------------------------------------------------------------------
local tex = {}
function U.tex(name)
    local t = tex[name]
    if t == nil then
        t = getTexture("media/ui/cotw/" .. name .. ".png") or false
        tex[name] = t
    end
    return t or nil
end

function U.icon(el, name, x, y, size, c, a)
    local t = U.tex(name)
    if t then el:drawTextureScaled(t, x, y, size, size, a or 1, c[1], c[2], c[3]) end
end

function U.text(el, text, x, y, c, font, a)
    el:drawText(text, x, y, c[1], c[2], c[3], a or 1, font or UIFont.Small)
end

function U.textR(el, text, x, y, c, font, a)
    el:drawTextRight(text, x, y, c[1], c[2], c[3], a or 1, font or UIFont.Small)
end

function U.textC(el, text, x, y, c, font, a)
    el:drawTextCentre(text, x, y, c[1], c[2], c[3], a or 1, font or UIFont.Small)
end

-- small caps-style section label with a fading rule after it
function U.label(el, text, x, y, w)
    U.text(el, text, x, y, C.mute)
    local tw = U.textW(text) + 8
    local midY = y + U.FONT_S / 2
    local seg = (w - tw) / 4
    for i = 0, 3 do U.rect(el, x + tw + i * seg, midY, seg, 1, C.line, 1 - i * 0.25) end
end

-- ------------------------------------------------------------------------------
-- the panel frame: glow, edge brighter at the cut corners, dark body with scan lines, corner marks
-- ------------------------------------------------------------------------------
function U.frame(el, w, h, cut)
    for i = 3, 1, -1 do U.chamfer(el, -i * 2, -i * 2, w + i * 4, h + i * 4, cut + i * 2, C.g, 0.03 * (4 - i)) end
    U.chamfer(el, 3, 8, w, h, cut, C.black, 0.45)
    U.chamfer(el, 0, 0, w, h, cut, C.gEdge, 1)
    local cw, ch = w * 0.35, h * 0.3
    U.chamfer(el, 0, 0, cw, ch, cut, C.g, 1)
    U.chamfer(el, w - cw, h - ch, cw, ch, cut, C.g, 1)
    U.chamfer(el, 1.5, 1.5, w - 3, h - 3, cut - 0.6, C.panel, 1)
    -- lighter towards the top
    local band = (h - 3) / 6
    for i = 0, 2 do U.rect(el, 1.5 + (i == 0 and cut or 0), 1.5 + i * band, w - 3 - (i == 0 and cut or 0), band, C.panel2, 0.9 - i * 0.3) end
    local bg = U.tex("bg")
    if bg then el:drawTextureTiled(bg, 2, cut, w - 4, h - 2 * cut, 1, 1, 1, 1) end
    U.rect(el, w - 18, 6, 12, 2, C.g, 0.8)
    U.rect(el, w - 8, 6, 2, 12, C.g, 0.8)
    U.rect(el, 6, h - 8, 12, 2, C.g, 0.8)
    U.rect(el, 6, h - 18, 2, 12, C.g, 0.8)
end

-- the on-screen strip: glow, dark body with scan lines, a bright line along the top
function U.stripFrame(el, w, h, cut)
    for i = 3, 1, -1 do U.strip(el, -i * 2, -i * 2, w + i * 4, h + i * 4, cut + i, C.g, 0.03 * (4 - i)) end
    U.strip(el, 0, 0, w, h, cut, C.panel2, 0.93)
    U.rect(el, 0, h * 0.5, w, h * 0.5 - cut, C.panel, 0.5)
    local bg = U.tex("bg")
    if bg then el:drawTextureTiled(bg, 0, 0, w, h - cut, 1, 1, 1, 1) end
    local seg = w / 8
    for i = 0, 7 do
        local f = 1 - math.abs((i + 0.5) / 8 - 0.5) * 2
        U.rect(el, i * seg, 0, seg, 2, C.g, f)
    end
end

-- ------------------------------------------------------------------------------
-- buttons: style = main | ghost | tile | tileOff | admin | chip | seg | segOn | stop | x | link | switch
-- ------------------------------------------------------------------------------
COTWBtn = ISButton:derive("COTWBtn")

function COTWBtn:new(x, y, w, h, title, target, fn, style, icon)
    local o = ISButton.new(self, x, y, w, h, title, target, fn)
    o.style = style or "ghost"
    o.icon = icon
    o.tag = nil          -- main: amount box on the right
    o.on = false         -- switch: state
    return o
end

function COTWBtn:prerender()
    local w, h, s = self.width, self.height, self.style
    local hot = self.enable and self:isMouseOver()
    local dim = self.enable and 1 or 0.45
    if s == "main" then
        local cut = 10
        U.chamfer(self, 0, 0, w, h, cut, C.g2, dim)
        -- lighter upper half (top-left cut only)
        U.quad(self, cut, 0, w, 0, w, cut, 0, cut, C.gLight, (hot and 1 or 0.8) * dim)
        U.rect(self, 0, cut, w, h * 0.55 - cut, C.gLight, (hot and 1 or 0.8) * dim)
        if self.enable then
            -- light sweeping across now and then
            local t = (getTimestampMs() % 2600) / 2600
            if t > 0.55 then
                local p = (t - 0.55) / 0.45
                local x0 = -0.6 * w + p * 1.9 * w
                local sw, k = 0.4 * w, h * 0.35
                local function cl(x) return math.max(0, math.min(w, x)) end
                U.quad(self, cl(x0 + k), 0, cl(x0 + k + sw), 0, cl(x0 + sw), h, cl(x0), h, C.white, 0.22)
            end
        end
    elseif s == "ghost" then
        U.chamfer(self, 0, 0, w, h, 10, C.g, (hot and 0.16 or 0.08) * dim)
        U.chamferLine(self, 0, 0, w, h, 10, C.g, 0.55 * dim)
    elseif s == "tile" or s == "tileOff" or s == "home" then
        U.chamfer(self, 0, 0, w, h, 8, s == "home" and C.g or C.white, s == "home" and 0.07 or (hot and 0.07 or 0.03))
        U.chamferLine(self, 0, 0, w, h, 8, s == "home" and C.g or C.line, s == "home" and 0.55 or 1)
    elseif s == "admin" then
        U.chamfer(self, 0, 0, w, h, 8, C.amber, hot and 0.10 or 0.04)
        U.chamferLine(self, 0, 0, w, h, 8, C.line, 1)
    elseif s == "chip" then
        U.chamfer(self, 0, 0, w, h, 6, C.white, hot and 0.08 or 0.04)
    elseif s == "segOn" then
        U.rect(self, 0, 0, w, h, C.g, dim)
    elseif s == "seg" then
        U.rect(self, 0, 0, w, h, C.g, hot and 0.12 or 0)
    elseif s == "stop" then
        U.chamfer(self, 0, 0, w, h, 8, C.red2, 1)
        U.chamfer(self, 0, 0, w, h * 0.5, 8, C.red1, hot and 1 or 0.8)
    elseif s == "x" then
        U.chamfer(self, 0, 0, w, h, 6, C.white, hot and 0.08 or 0)
        U.chamferLine(self, 0, 0, w, h, 6, C.line, 1)
    elseif s == "switch" then
        U.chamfer(self, 0, 0, w, h, 5, self.on and C.g or C.white, self.on and 0.35 or 0.08)
        local kx = self.on and (w - 17) or 3
        U.rect(self, kx, 3, 14, h - 6, self.on and C.g or C.mute, 1)
    end
end

function COTWBtn:render()
    local w, h, s = self.width, self.height, self.style
    local title = self.title or ""
    local dim = self.enable and 1 or 0.45
    if s == "main" or s == "ghost" or s == "stop" or s == "chip" or s == "seg" or s == "segOn" or s == "link" then
        local font = s == "main" and UIFont.Medium or UIFont.Small
        local fh = s == "main" and U.FONT_M or U.FONT_S
        local col = (s == "main" or s == "segOn") and C.dark or (s == "stop" and C.white) or (s == "link" and C.mute) or C.g
        if s == "seg" then col = C.mute end
        local isz = s == "main" and 22 or 16
        local tagW = 0
        if self.tag then
            tagW = U.textW(self.tag, UIFont.Small) + 16
            local tx = w - tagW - 10
            U.chamfer(self, tx, (h - U.FONT_S - 6) / 2, tagW, U.FONT_S + 6, 6, C.dark, dim)
            U.textC(self, self.tag, tx + tagW / 2, (h - U.FONT_S) / 2, C.g, UIFont.Small, dim)
        end
        local tw = U.textW(title, font) + (self.icon and isz + 8 or 0)
        local x = (w - tagW - tw) / 2
        if self.icon then
            U.icon(self, self.icon, x, (h - isz) / 2, isz, col, dim)
            x = x + isz + 8
        end
        U.text(self, title, x, (h - fh) / 2, col, font, dim)
    elseif s == "tile" or s == "tileOff" or s == "home" then
        local isz = 22
        local on = s ~= "tileOff"
        U.icon(self, self.icon or "pin", (w - isz) / 2, 8, isz, on and C.g or C.offIcon)
        U.textC(self, title, w / 2, 8 + isz + 3, on and C.ink or C.off)
    elseif s == "admin" then
        local isz = 18
        local tw = U.textW(title) + isz + 6
        local x = (w - tw) / 2
        U.icon(self, self.icon, x, (h - isz) / 2, isz, C.amber)
        U.text(self, title, x + isz + 6, (h - U.FONT_S) / 2, C.amber)
    elseif s == "x" then
        U.icon(self, "x", (w - 14) / 2, (h - 14) / 2, 14, C.mute)
    end
end
