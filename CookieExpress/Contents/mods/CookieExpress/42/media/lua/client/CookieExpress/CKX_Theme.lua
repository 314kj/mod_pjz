-- Cookie Express : pixel-glass theme helpers (textures are drawn 1:1 so the pixels stay crisp)
if isServer() then return end

require "CookieExpress/CKX_Shared"
require "CookieExpress/CKX_TextMetrics"

CKX.T = CKX.T or {}
local T = CKX.T
local floor = math.floor

T.BASE = "media/ui/CookieExpress/"
T.cache = {}

function T.tex(name)
    local t = T.cache[name]
    if t == nil then
        t = getTexture(T.BASE .. name .. ".png") or false
        T.cache[name] = t
    end
    return t or nil
end

local function c255(r, g, b) return { r / 255, g / 255, b / 255 } end

-- same bands as tools/art/gen_art.py WIN_BANDS (corner pieces are baked with the first/last)
T.WIN_BANDS = {
    c255(255, 218, 236), c255(252, 222, 242), c255(244, 226, 248), c255(234, 230, 250),
    c255(226, 236, 250), c255(218, 242, 248), c255(210, 246, 244), c255(204, 248, 240),
}
T.WIN_ALPHA = 236 / 255
T.ROW_BANDS = { c255(255, 255, 255) }
-- v2 glass screen (tools/art/gen_art_v2.py HEAD / SCR_BANDS)
T.HEAD = { c255(255, 241, 247) }
T.HEAD_ALPHA = 244 / 255
T.SCR_BANDS = {
    c255(168, 228, 255), c255(158, 222, 255), c255(148, 216, 254),
    c255(138, 210, 252), c255(130, 204, 250), c255(122, 198, 248),
}
T.SCR_ALPHA = 150 / 255
T.ROW_ALPHA, T.ROWH_ALPHA = 212 / 255, 232 / 255
T.TXT  = c255(92, 38, 92)
T.TXT2 = c255(132, 92, 150)
T.PINK = c255(255, 64, 142)
T.WHITE = { 1, 1, 1 }
T.BTN_TEXT = { p = { 1, 1, 1 }, t = { 1, 1, 1 }, w = c255(110, 70, 130) }

function T.fillBands(el, x, y, w, h, cw, rim, bands, alpha)
    local n = #bands
    local function fill(x0, y0, x1, y1)
        if x1 <= x0 then return end
        for i = 1, n do
            local by0 = y + floor(h * (i - 1) / n)
            local by1 = y + floor(h * i / n)
            local a0 = by0 > y0 and by0 or y0
            local a1 = by1 < y1 and by1 or y1
            if a1 > a0 then
                local c = bands[i]
                el:drawRect(x0, a0, x1 - x0, a1 - a0, alpha, c[1], c[2], c[3])
            end
        end
    end
    fill(x + cw, y + rim, x + w - cw, y + h - rim)
    fill(x + rim, y + cw, x + cw, y + h - cw)
    fill(x + w - cw, y + cw, x + w - rim, y + h - cw)
end

-- 9-slice glass card. prefix: ckx_win (cw 16, rim 4) / ckx_row, ckx_rowh (cw 8, rim 4)
function T.nine(el, prefix, x, y, w, h, cw, rim, bands, alpha, fade)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    fade = fade or 1
    T.fillBands(el, x, y, w, h, cw, rim, bands, alpha * fade)
    local t = T.tex
    el:drawTextureScaled(t(prefix .. "_t"), x + cw, y, w - 2 * cw, rim, fade, 1, 1, 1)
    el:drawTextureScaled(t(prefix .. "_b"), x + cw, y + h - rim, w - 2 * cw, rim, fade, 1, 1, 1)
    el:drawTextureScaled(t(prefix .. "_l"), x, y + cw, rim, h - 2 * cw, fade, 1, 1, 1)
    el:drawTextureScaled(t(prefix .. "_r"), x + w - rim, y + cw, rim, h - 2 * cw, fade, 1, 1, 1)
    el:drawTexture(t(prefix .. "_tl"), x, y, fade, 1, 1, 1)
    el:drawTexture(t(prefix .. "_tr"), x + w - cw, y, fade, 1, 1, 1)
    el:drawTexture(t(prefix .. "_bl"), x, y + h - cw, fade, 1, 1, 1)
    el:drawTexture(t(prefix .. "_br"), x + w - cw, y + h - cw, fade, 1, 1, 1)
end

-- pill button 24px tall. kind: "p" pink, "t" teal, "w" white. state: nil|"hover"|"down"|"off"
function T.pill(el, kind, x, y, w, label, font, state, fade)
    x, y, w = floor(x), floor(y), floor(w)
    fade = fade or 1
    local a = fade
    if state == "off" then a = a * 0.45 end
    if state == "down" then y = y + 1 elseif state == "hover" then y = y - 1 end
    local t = T.tex
    el:drawTexture(t("ckx_btn" .. kind .. "_l"), x, y, a, 1, 1, 1)
    el:drawTextureScaled(t("ckx_btn" .. kind .. "_m"), x + 12, y, w - 24, 24, a, 1, 1, 1)
    el:drawTexture(t("ckx_btn" .. kind .. "_r"), x + w - 12, y, a, 1, 1, 1)
    if state == "hover" then
        el:drawRect(x + 6, y + 4, w - 12, 2, 0.35 * a, 1, 1, 1)
    end
    local c = T.BTN_TEXT[kind] or T.WHITE
    local fh = getTextManager():getFontHeight(font)
    el:drawTextCentre(label, x + w / 2, y + floor((24 - fh) / 2), c[1], c[2], c[3], a, font)
end

function T.tile(el, name, x, y, w, h, size, alpha)
    local tex = T.tex(name)
    if not tex then return end
    local yy = y
    while yy < y + h do
        local xx = x
        while xx < x + w do
            el:drawTexture(tex, xx, yy, alpha, 1, 1, 1)
            xx = xx + size
        end
        yy = yy + size
    end
end

function T.sparkle(el, x, y, phase, fade)
    local f = floor(phase) % 4
    el:drawTexture(T.tex("ckx_spark" .. f), floor(x), floor(y), fade or 1, 1, 1, 1)
end

function T.fit(text, font, maxW)
    local tm = getTextManager()
    if tm:MeasureStringX(font, text) <= maxW then return text end
    local s = text
    while #s > 1 and tm:MeasureStringX(font, s .. "...") > maxW do
        s = string.sub(s, 1, #s - 1)
    end
    return s .. "..."
end

function T.hit(mx, my, x, y, w, h)
    return mx >= x and my >= y and mx < x + w and my < y + h
end

function T.playSound(name)
    pcall(function() getSoundManager():playUISound(name) end)
end

-- rect minus hole -> up to 4 rects {x0, y0, x1, y1}
local function minus(r, hole)
    if not hole then return { r } end
    local hx0, hy0, hx1, hy1 = hole[1], hole[2], hole[3], hole[4]
    if hx0 >= r[3] or hx1 <= r[1] or hy0 >= r[4] or hy1 <= r[2] then return { r } end
    local out = {}
    if hy0 > r[2] then out[#out + 1] = { r[1], r[2], r[3], hy0 } end
    if hy1 < r[4] then out[#out + 1] = { r[1], hy1, r[3], r[4] } end
    local my0, my1 = math.max(r[2], hy0), math.min(r[4], hy1)
    if hx0 > r[1] then out[#out + 1] = { r[1], my0, hx0, my1 } end
    if hx1 < r[3] then out[#out + 1] = { hx1, my0, r[3], my1 } end
    return out
end

-- pink bezel card (cw 16, rim 8) with the pale header colour inside.
-- hole = {x, y, w, h} (relative) is left unfilled so a see-through glass screen can sit there
function T.bezel(el, x, y, w, h, fade, hole)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    fade = fade or 1
    local cw, rim = 16, 8
    local hb = hole and { x + hole[1], y + hole[2], x + hole[1] + hole[3], y + hole[2] + hole[4] } or nil
    local c = T.HEAD[1]
    local a = T.HEAD_ALPHA * fade
    for _, r in ipairs({ { x + cw, y + rim, x + w - cw, y + h - rim }, { x + rim, y + cw, x + cw, y + h - cw },
                         { x + w - cw, y + cw, x + w - rim, y + h - cw } }) do
        for _, q in ipairs(minus(r, hb)) do
            if q[3] > q[1] and q[4] > q[2] then el:drawRect(q[1], q[2], q[3] - q[1], q[4] - q[2], a, c[1], c[2], c[3]) end
        end
    end
    local t = T.tex
    el:drawTextureScaled(t("ckx_bz_t"), x + cw, y, w - 2 * cw, rim, fade, 1, 1, 1)
    el:drawTextureScaled(t("ckx_bz_b"), x + cw, y + h - rim, w - 2 * cw, rim, fade, 1, 1, 1)
    el:drawTextureScaled(t("ckx_bz_l"), x, y + cw, rim, h - 2 * cw, fade, 1, 1, 1)
    el:drawTextureScaled(t("ckx_bz_r"), x + w - rim, y + cw, rim, h - 2 * cw, fade, 1, 1, 1)
    el:drawTexture(t("ckx_bz_tl"), x, y, fade, 1, 1, 1)
    el:drawTexture(t("ckx_bz_tr"), x + w - cw, y, fade, 1, 1, 1)
    el:drawTexture(t("ckx_bz_bl"), x, y + h - cw, fade, 1, 1, 1)
    el:drawTexture(t("ckx_bz_br"), x + w - cw, y + h - cw, fade, 1, 1, 1)
end

-- cyan glass screen with diagonal light streaks (cw 8, rim 4)
function T.screen(el, x, y, w, h, fade)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    T.nine(el, "ckx_scr", x, y, w, h, 8, 4, T.SCR_BANDS, T.SCR_ALPHA, fade)
    -- see-through sky-blue glass: white pixel reflections like window panes
    el:setStencilRect(x + 3, y + 3, w - 6, h - 6)
    el:drawTexture(T.tex("ckx_refl_big"), x + 6, y + 4, fade, 1, 1, 1)
    local small = T.tex("ckx_refl_small")
    local gy, row = y + 34, 0
    while gy < y + h - 10 do
        local gx = x + 120 + (row % 2) * 85
        while gx < x + w - 30 do
            el:drawTexture(small, gx, gy, fade * 0.9, 1, 1, 1)
            gx = gx + 170
        end
        gy = gy + 96
        row = row + 1
    end
    el:drawTexture(T.tex("ckx_refl_big"), x + w - 96, y + h - 92, fade * 0.7, 1, 1, 1)
    el:clearStencilRect()
end

-- bright diagonal band sweeping across a glass area; p = 0..1
function T.glint(el, x, y, w, h, p, fade)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    local g = T.tex("ckx_glint")
    if not g then return end
    el:setStencilRect(x, y, w, h)
    local gx = x - 160 + floor((w + 240) * p)
    local yy, k = y - 40, 0
    while yy < y + h do
        el:drawTexture(g, gx - k * 80, yy, fade, 1, 1, 1)
        yy = yy + 160
        k = k + 1
    end
    el:clearStencilRect()
end

function T.deco(el, name, x, y, fade)
    local t = T.tex(name)
    if t then el:drawTexture(t, floor(x), floor(y), fade or 1, 1, 1, 1) end
end

-- ================================================================== pre-rendered Thai text
-- parts: phrase keys ("waiting_a"), numbers (4) or glyph strings starting with "#" ("#(4)")
local TM = CKX.TM
local GLYPH = { ["("] = "lp", [")"] = "rp", ["+"] = "plus", ["x"] = "x" }

local function glyphNames(style, s)
    local out = {}
    for i = 1, #s do
        local ch = string.sub(s, i, i)
        local key = GLYPH[ch]
        if not key and ch >= "0" and ch <= "9" then key = "d" .. ch end
        if key then out[#out + 1] = "t_" .. style .. "_" .. key end
    end
    return out
end

local function partNames(style, p)
    if type(p) == "number" then return glyphNames(style, tostring(floor(p))) end
    if string.sub(p, 1, 1) == "#" then return glyphNames(style, string.sub(p, 2)) end
    return { "t_" .. style .. "_" .. p }
end

function T.lineH(style)
    return TM.h[style] or 20
end

function T.lineW(style, parts)
    local w = 0
    for i, p in ipairs(parts) do
        if i > 1 then w = w + (TM.space[style] or 4) end
        for _, n in ipairs(partNames(style, p)) do w = w + (TM.w[n] or 0) end
    end
    return w
end

-- draws at (x, y) = top-left of the line box; align "left" | "center" | "right"; returns width
function T.line(el, style, parts, x, y, align, fade)
    local w = T.lineW(style, parts)
    local cx = x
    if align == "center" then cx = x - floor(w / 2) elseif align == "right" then cx = x - w end
    cx = floor(cx)
    y = floor(y)
    for i, p in ipairs(parts) do
        if i > 1 then cx = cx + (TM.space[style] or 4) end
        for _, n in ipairs(partNames(style, p)) do
            local t = T.tex("txt/" .. n)
            if t then el:drawTexture(t, cx, y, fade or 1, 1, 1, 1) end
            cx = cx + (TM.w[n] or 0)
        end
    end
    return w
end

-- vertically centre a line inside a band of height bandH starting at top
function T.lineIn(el, style, parts, x, top, bandH, align, fade)
    return T.line(el, style, parts, x, top + floor((bandH - T.lineH(style)) / 2), align, fade)
end

-- pill with an image label: label = { style = "btnw", parts = {...} }
function T.pillImg(el, kind, x, y, w, label, state, fade)
    T.pill(el, kind, x, y, w, "", UIFont.Small, state, fade)
    if state == "down" then y = y + 1 elseif state == "hover" then y = y - 1 end
    local a = fade or 1
    if state == "off" then a = a * 0.45 end
    T.lineIn(el, label.style, label.parts, x + w / 2, y, 24, "center", a)
end
