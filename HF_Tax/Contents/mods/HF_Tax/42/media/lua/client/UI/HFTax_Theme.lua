-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Original work: Copyright (c) 2026 matasa. All Rights Reserved.
-- UI revision: AKA (LOOKCHINNOL), published with the author's permission.
--
-- HFTax_Theme.lua -- one file owns every colour, font and draw helper.
--
-- Nothing else in the mod is allowed to write a raw colour literal. Change a
-- value here and the whole UI moves together; there is no second place that
-- can be forgotten.
--
-- Engine rules this file exists to enforce:
--   * square corners only            (drawRect has no radius and never will)
--   * flat fills, no shadow/gradient (layers separate by background lightness)
--   * four font steps only           (Small / Medium / Large / Massive)
--   * every height comes from T.h(font), never from a typed-in pixel number
-- =============================================================================

---@diagnostic disable: undefined-global
HFTaxUI = HFTaxUI or {}

-- Re-entry guard. Other files require() this one so they do not depend on
-- alphabetical load order, and PZ will still walk the folder and load it a
-- second time by itself. Without the guard that second pass rebuilds the
-- tables other files are already holding references to.
if HFTaxUI.Theme and HFTaxUI.Theme.__ready then return HFTaxUI.Theme end

HFTaxUI.Theme = HFTaxUI.Theme or {}
local T = HFTaxUI.Theme

-- ---------------------------------------------------------------- colours ---
local function hex(h)
    return {
        r = tonumber(string.sub(h, 1, 2), 16) / 255,
        g = tonumber(string.sub(h, 3, 4), 16) / 255,
        b = tonumber(string.sub(h, 5, 6), 16) / 255,
    }
end

T.C = {
    bg0        = hex("0a0b14"),
    bg1        = hex("111220"),
    card       = hex("1a1b29"),
    raise      = hex("1d1f2d"),
    raise2     = hex("212135"),
    line       = hex("2f2f4d"),
    line2      = hex("32324f"),

    purple     = hex("9184d9"),
    purpleLite = hex("b8b5e0"),
    purplePale = hex("d2cefd"),
    purpleDeep = hex("423a6a"),

    green      = hex("7fd18f"),
    greenDeep  = hex("1e5c34"),
    redBg      = hex("6b2734"),
    redFg      = hex("ffc7c7"),
    redDeep    = hex("8e2030"),

    cyan       = hex("46c2dd"),
    cyanDeep   = hex("1b4358"),
    amber      = hex("c4884e"),
    amberDeep  = hex("5c452a"),
    orange     = hex("e2704f"),

    text       = hex("cfd0e0"),
    textHi     = hex("e2e3f2"),
    textDim    = hex("8a8ba4"),
    textFaint  = hex("5f6080"),
    grey       = hex("6a6a80"),
}

-- Status colour of a bill. One function, called from every place that needs it,
-- so a new status can never be half-added.
T.STATUS = {
    none  = { c = T.C.grey,    label = "PENDING" },
    due   = { c = T.C.orange,  label = "DUE" },
    late  = { c = hex("c8384a"), label = "OVERDUE" },
    cut   = { c = T.C.redDeep, label = "CUT OFF" },
    paid  = { c = T.C.green,   label = "PAID" },
    sent  = { c = T.C.purple,  label = "NUDGED" },
    queued= { c = T.C.grey,    label = "QUEUED" },
}

function T.status(k)
    return T.STATUS[k] or T.STATUS.none
end

-- ------------------------------------------------------------------ fonts ---
-- Only these four. PZ scales them by the player's UI scale setting, which is
-- exactly why no layout number below is allowed to be a typed-in pixel value.
T.F = {
    S  = UIFont and UIFont.Small   or "Small",
    M  = UIFont and UIFont.Medium  or "Medium",
    L  = UIFont and UIFont.Large   or "Large",
    XL = UIFont and UIFont.Massive or "Massive",
}

function T.h(font)
    return getTextManager():getFontHeight(font)
end

function T.w(font, s)
    return getTextManager():MeasureStringX(font, tostring(s))
end

-- Spacing unit derived from the small font, so padding grows with UI scale too.
function T.pad()
    return math.floor(T.h(T.F.S) * 0.55)
end

-- ------------------------------------------------------------------- draw ---
function T.fill(e, x, y, w, h, c, a)
    e:drawRect(x, y, w, h, a or 1.0, c.r, c.g, c.b)
end

function T.line_(e, x, y, w, h, c, a)
    e:drawRectBorder(x, y, w, h, a or 1.0, c.r, c.g, c.b)
end

---Filled panel with a border. The pair is always drawn together; drawing one
---without the other is the usual way a panel ends up looking unfinished.
function T.panel(e, x, y, w, h, fillC, lineC, a)
    T.fill(e, x, y, w, h, fillC or T.C.card, a or 1.0)
    T.line_(e, x, y, w, h, lineC or T.C.line, 1.0)
end

function T.text(e, s, x, y, c, font, a)
    c = c or T.C.text
    e:drawText(tostring(s), x, y, c.r, c.g, c.b, a or 1.0, font or T.F.S)
end

function T.textR(e, s, xRight, y, c, font, a)
    T.text(e, s, xRight - T.w(font or T.F.S, s), y, c, font, a)
end

function T.textC(e, s, xCentre, y, c, font, a)
    c = c or T.C.text
    e:drawTextCentre(tostring(s), xCentre, y, c.r, c.g, c.b, a or 1.0, font or T.F.S)
end

---Cut a string down until it fits, ending in a single dot. PZ has no ellipsis
---glyph worth trusting and three dots eat more width than the character saved.
function T.clip(s, font, maxW)
    s = tostring(s)
    if T.w(font, s) <= maxW then return s end
    local out = s
    while #out > 1 and T.w(font, out .. ".") > maxW do
        out = string.sub(out, 1, #out - 1)
    end
    return out .. "."
end

-- ----------------------------------------------------------------- icons ----
local ICON_DIR = "media/textures/HFTax/ui/"
local iconCache = {}

---Size of a loaded texture.
---
---PZ's getTexture() hands back a Java Texture OBJECT. It has getWidth() and
---getHeight() METHODS -- it does not have .w / .h fields. Reading tex.w gives
---nil, and the first thing you do with that nil is multiply it, so Kahlua
---reports the failure as:
---
---    __mul not defined for operands
---
---which names the arithmetic and never names the field that was missing.
---Returns nil when the size cannot be read, so callers skip drawing instead of
---doing maths on nil.
local function texSize(tex)
    if not tex then return nil end
    local ok, w, h = pcall(function() return tex:getWidth(), tex:getHeight() end)
    if not ok or type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
        return nil
    end
    return w, h
end

---Icons are white 32x32 PNGs; the colour comes from the draw call. One file
---per shape, not one file per shape-and-colour.
function T.icon(e, name, x, y, size, c, a)
    local tex = iconCache[name]
    if tex == nil then
        tex = getTexture(ICON_DIR .. name .. ".png")
        iconCache[name] = tex or false
    end
    if not tex then return end
    c = c or T.C.textDim
    e:drawTextureScaled(tex, x, y, size, size, a or 1.0, c.r, c.g, c.b)
end

---Full-colour art (the mushroom-forest set). Drawn with a white tint so the
---artwork keeps its own colours -- the opposite of T.icon above, which expects
---a white silhouette and supplies the colour itself.
function T.art(e, name, x, y, w, h, a)
    local tex = iconCache[name]
    if tex == nil then
        tex = getTexture(ICON_DIR .. name .. ".png")
        iconCache[name] = tex or false
    end
    if not tex then return false end
    e:drawTextureScaled(tex, x, y, w, h, a or 1.0, 1, 1, 1)
    return true
end

---Art scaled to a target height, keeping its aspect. Returns the width used so
---a caller can lay things out after it without knowing the source file.
function T.artH(e, name, x, y, h, a)
    local tex = iconCache[name]
    if tex == nil then
        tex = getTexture(ICON_DIR .. name .. ".png")
        iconCache[name] = tex or false
    end
    local tw, th = texSize(tex)
    if not tw then return 0 end
    local w = math.floor(tw * h / th + 0.5)
    e:drawTextureScaled(tex, x, y, w, h, a or 1.0, 1, 1, 1)
    return w
end

---Same as T.artH but anchored to a right edge. Right-aligned art without this
---means every caller hard-codes the picture's width, which is exactly the kind
---of typed-in number that breaks the moment the art is re-exported.
function T.artRightH(e, name, xRight, y, h, a)
    local tex = iconCache[name]
    if tex == nil then
        tex = getTexture(ICON_DIR .. name .. ".png")
        iconCache[name] = tex or false
    end
    local tw, th = texSize(tex)
    if not tw then return 0 end
    local w = math.floor(tw * h / th + 0.5)
    e:drawTextureScaled(tex, xRight - w, y, w, h, a or 1.0, 1, 1, 1)
    return w
end

---Right-anchored art sized by WIDTH. Wide art (a stamp, a word) has to be
---sized by how much room it has sideways; sizing it by height makes a long
---stamp shrink to an unreadable smear.
function T.artRightW(e, name, xRight, yCentre, w, a)
    local tex = iconCache[name]
    if tex == nil then
        tex = getTexture(ICON_DIR .. name .. ".png")
        iconCache[name] = tex or false
    end
    local tw, th = texSize(tex)
    if not tw then return 0, 0 end
    local h = math.floor(th * w / tw + 0.5)
    e:drawTextureScaled(tex, xRight - w, yCentre - math.floor(h / 2), w, h, a or 1.0, 1, 1, 1)
    return w, h
end

---Art centred inside a box, scaled to fit BOTH dimensions. PZ has no clipping
---on a plain draw call, so anything sized by one axis alone will happily bleed
---out of its panel and over whatever is behind it.
function T.artFit(e, name, cx, cy, maxW, maxH, a)
    local tex = iconCache[name]
    if tex == nil then
        tex = getTexture(ICON_DIR .. name .. ".png")
        iconCache[name] = tex or false
    end
    local tw, th = texSize(tex)
    if not tw then return 0, 0 end
    local s = math.min(maxW / tw, maxH / th)
    local w = math.floor(tw * s + 0.5)
    local h = math.floor(th * s + 0.5)
    e:drawTextureScaled(tex, cx - math.floor(w / 2), cy - math.floor(h / 2), w, h,
        a or 1.0, 1, 1, 1)
    return w, h
end

---Stamps ship pre-rotated inside the PNG. drawTexture cannot rotate and there
---is no point pretending otherwise.
function T.stamp(e, kind, xRight, y, scale, a)
    scale = scale or 1.0
    local w = math.floor(96 * scale)
    local h = math.floor(30 * scale)
    local tex = iconCache["stamp_" .. kind]
    if tex == nil then
        tex = getTexture(ICON_DIR .. "stamp_" .. kind .. ".png")
        iconCache["stamp_" .. kind] = tex or false
    end
    if tex then
        e:drawTextureScaled(tex, xRight - w, y, w, h, a or 1.0, 1, 1, 1)
    else
        -- No art yet: draw the word in a box so the layout is still honest.
        local st = T.status(kind)
        T.panel(e, xRight - w, y, w, h, T.C.bg0, st.c, a or 1.0)
        T.textC(e, st.label, xRight - w / 2, y + math.floor((h - T.h(T.F.S)) / 2), st.c, T.F.S, a or 1.0)
    end
    return w, h
end

-- ------------------------------------------------------------------ chips ---
---Small label pill. Returns its own width so callers can lay chips in a row
---without knowing anything about the text inside them.
function T.chip(e, s, x, y, c, bgC, font)
    font = font or T.F.S
    local padX = math.max(4, math.floor(T.h(font) * 0.45))
    local w = T.w(font, s) + padX * 2
    local h = T.h(font) + math.floor(T.h(font) * 0.35)
    T.panel(e, x, y, w, h, bgC or T.C.raise, c or T.C.textDim, 1.0)
    T.text(e, s, x + padX, y + math.floor((h - T.h(font)) / 2), c or T.C.textDim, font)
    return w, h
end

function T.iconChip(e, iconName, s, x, y, c, bgC, font)
    font = font or T.F.S
    local ih = T.h(font)
    local padX = math.max(4, math.floor(ih * 0.45))
    local gap = math.floor(ih * 0.35)
    local w = padX + ih + gap + T.w(font, s) + padX
    local h = ih + math.floor(ih * 0.35)
    T.panel(e, x, y, w, h, bgC or T.C.raise, c or T.C.textDim, 1.0)
    T.icon(e, iconName, x + padX, y + math.floor((h - ih) / 2), ih, c or T.C.textDim)
    T.text(e, s, x + padX + ih + gap, y + math.floor((h - ih) / 2), c or T.C.textDim, font)
    return w, h
end

-- ------------------------------------------------------------------ fuse ----
---Countdown drawn as blocks that go dark. Readable out of the corner of the
---eye, which is the only thing anyone actually wants from a due date.
---@param frac number 0..1 remaining
function T.fuse(e, x, y, frac, c, segs)
    segs = segs or 8
    local sh = math.max(5, math.floor(T.h(T.F.S) * 0.6))
    local sw = math.max(6, math.floor(sh * 1.1))
    local gap = 2
    local lit = math.floor(frac * segs + 0.5)
    if frac > 0 and lit < 1 then lit = 1 end
    for i = 1, segs do
        local cx = x + (i - 1) * (sw + gap)
        if i <= lit then
            T.fill(e, cx, y, sw, sh, c)
        else
            T.fill(e, cx, y, sw, sh, T.C.raise2)
        end
    end
    return segs * (sw + gap) - gap, sh
end

-- ---------------------------------------------------------------- buttons ---
T.BTN = {
    go     = { bg = T.C.greenDeep,  line = T.C.green,      fg = hex("e6ffe9") },
    bank   = { bg = T.C.cyanDeep,   line = T.C.cyan,       fg = hex("dff6ff") },
    ghost  = { bg = hex("1b1c30"),  line = T.C.purpleDeep, fg = T.C.purpleLite },
    alt    = { bg = hex("2e2450"),  line = T.C.purple,     fg = T.C.purplePale },
    off    = { bg = hex("1b1c2b"),  line = T.C.line2,      fg = hex("55566e") },
    close  = { bg = hex("232438"),  line = T.C.line2,      fg = T.C.text },
}

---Draw a button and hand the rect back so the caller can register it as a
---click zone. The drawing and the hit box come from the same numbers -- a
---button that is visible but not clickable is not possible this way.
function T.button(e, style, s, x, y, w, h, iconName, font)
    font = font or T.F.S
    local b = T.BTN[style] or T.BTN.close
    T.panel(e, x, y, w, h, b.bg, b.line, 1.0)
    local ty = y + math.floor((h - T.h(font)) / 2)
    if iconName then
        local ih = T.h(font)
        local gap = math.floor(ih * 0.4)
        local total = ih + gap + T.w(font, s)
        local sx = x + math.floor((w - total) / 2)
        T.icon(e, iconName, sx, ty, ih, b.fg)
        T.text(e, s, sx + ih + gap, ty, b.fg, font)
    else
        T.textC(e, s, x + math.floor(w / 2), ty, b.fg, font)
    end
    return { x = x, y = y, w = w, h = h }
end

-- ------------------------------------------------------------------ money ---
---1234567 -> "1,234,567". PZ has no locale formatting and a raw seven digit
---number on a card is unreadable at a glance.
function T.money(n)
    n = math.floor(tonumber(n) or 0)
    local sign = ""
    if n < 0 then sign = "-"; n = -n end
    local s = tostring(n)
    local out = ""
    while #s > 3 do
        out = "," .. string.sub(s, -3) .. out
        s = string.sub(s, 1, #s - 3)
    end
    return sign .. "$" .. s .. out
end

---Short duration for a card. "1D 3H" not "1 Days 3 Hours" -- the font grows
---with UI scale and long strings are the first thing to overflow.
function T.dur(days)
    days = tonumber(days) or 0
    if days <= 0 then return "NOW" end
    local d = math.floor(days)
    local h = math.floor((days - d) * 24)
    if d > 0 then return tostring(d) .. "D " .. tostring(h) .. "H" end
    if h > 0 then return tostring(h) .. "H" end
    return math.max(1, math.floor((days - d) * 1440)) .. "M"
end

-- Set last: if this file blows up half way down, the next load gets to try
-- again instead of inheriting a half-built theme.
T.__ready = true

return T
