-- Cookie Helper : theme (dark teal + mint) and drawing helpers
-- The only place that defines colours. Flat, no borders: layers differ by surface brightness.
--   rounded corners -> white quarter-circle textures (rc_*) tinted when drawn
--   circles / avatars -> circle.png tinted
--   UI icons        -> white line icons (ic_*) tinted; item-ish icons are pixel art (px_*), drawn as-is
-- A missing texture falls back to plain rectangles, so the UI never breaks, it only looks flatter.
if isServer() then return end

require "CookieHelper/CH_Shared"

CHelp.Th = CHelp.Th or {}
local T = CHelp.Th
local floor = math.floor

local function rgb(hex)
    return { tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255 }
end
T.rgb = rgb

T.C = {
    bar    = rgb("0A1B1E"),   -- header strip, inputs, slots
    bg     = rgb("0F2528"),   -- window
    surf   = rgb("173337"),   -- cards, rows
    surf2  = rgb("1F3F42"),   -- secondary buttons, chips
    surf3  = rgb("284B4E"),   -- hover, tooltips
    line   = rgb("2E5357"),   -- the few outlines we keep (empty slots, off toggles)
    text   = rgb("EEF6F3"),
    text2  = rgb("A9C0BC"),
    text3  = rgb("86A19D"),
    acc    = rgb("5BD69A"),   -- mint: primary buttons, ok, selected
    acc2   = rgb("7DE2B2"),
    accD   = rgb("1C4A3C"),
    onAcc  = rgb("0A1B1E"),   -- text on mint
    warn   = rgb("FFC56B"),   -- Link, warnings
    warnD  = rgb("3D3119"),
    bad    = rgb("FF8C82"),
    badD   = rgb("44252A"),
    info   = rgb("7CBCFF"),
    infoD  = rgb("18344F"),
    peach  = rgb("FFB27A"),
    peachD = rgb("3F2D1E"),
    white  = { 1, 1, 1 },
    black  = { 0, 0, 0 },
    pill   = rgb("E6F2EE"),   -- the white pill
}

-- per-house colours: the player's own list order picks the colour, so it never changes between windows
T.HOUSE = { rgb("5BD69A"), rgb("7CBCFF"), rgb("C3A6FF"), rgb("FFB27A"), rgb("FFC56B"), rgb("FF8C82"), rgb("6FE0D6"), rgb("F59AD0") }
T.HOUSE_NAMES = { "Green", "Blue", "Purple", "Orange", "Yellow", "Red", "Teal", "Pink" }
T.AVATAR = T.HOUSE

-- ------------------------------------------------------------------ fonts
T.FS = UIFont.Small
T.FM = UIFont.Medium
T.FL = UIFont.Large
local TM = getTextManager()
function T.th(f) return TM:getFontHeight(f or T.FS) end
function T.tw(s, f) return TM:MeasureStringX(f or T.FS, tostring(s)) end

-- cut a string so it fits w pixels (cached; never splits a multi-byte UTF-8 character)
local fitCache, fitCount = {}, 0
function T.fit(s, w, font)
    s = tostring(s or "")
    font = font or T.FS
    w = floor(w)
    if w <= 8 then return "" end
    local key = s .. "\1" .. w .. "\1" .. tostring(font)
    local hit = fitCache[key]
    if hit then return hit end
    local out = s
    if TM:MeasureStringX(font, s) > w then
        out = ".."
        local lo, hi = 1, string.len(s) - 1
        while lo <= hi do
            local mid = floor((lo + hi) / 2)
            local m = mid
            while m > 0 do
                local nb = string.byte(s, m + 1)
                if nb and nb >= 128 and nb < 192 then m = m - 1 else break end
            end
            local cut = string.sub(s, 1, m) .. ".."
            if TM:MeasureStringX(font, cut) <= w then out = cut lo = mid + 1 else hi = mid - 1 end
        end
    end
    fitCount = fitCount + 1
    if fitCount > 4000 then fitCache, fitCount = {}, 0 end
    fitCache[key] = out
    return out
end

-- Thai vowel/tone marks sit on the letter before them: a line must never start with one,
-- and a leading vowel (เ แ โ ใ ไ) must stay with the letter after it.
-- In the game strings are Java strings (string.byte = UTF-16 unit); plain Lua 5.1 sees UTF-8 bytes.
local function charAt(s, i)
    local b = string.byte(s, i)
    if not b then return nil end
    if b >= 224 and b < 240 then
        local b2, b3 = string.byte(s, i + 1, i + 2)
        if b2 and b3 and b2 >= 128 and b2 < 192 then return (b - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128) end
    end
    return b
end
local function isThaiMark(c) return c ~= nil and (c == 3633 or (c >= 3636 and c <= 3642) or (c >= 3655 and c <= 3662)) end
local function isThaiLead(c) return c ~= nil and c >= 3648 and c <= 3652 end
local function safeCut(s, n)
    local guard = 0
    while n > 1 and guard < 12 do
        guard = guard + 1
        local nb = string.byte(s, n + 1)
        if nb and nb >= 128 and nb < 192 then n = n - 1
        elseif isThaiMark(charAt(s, n + 1)) then n = n - 1
        elseif isThaiLead(charAt(s, n)) then n = n - 1
        elseif n >= 3 and isThaiLead(charAt(s, n - 2)) and string.byte(s, n - 2) == 224 then n = n - 3
        else break end
    end
    return n
end
T.safeCut = safeCut

-- word wrap into lines that fit w (Thai has no spaces: falls back to cutting by width)
function T.wrap(s, w, font, maxLines)
    s = tostring(s or "")
    font = font or T.FS
    local lines = {}
    local cur = ""
    for word in string.gmatch(s, "%S+") do
        local try = (cur == "") and word or (cur .. " " .. word)
        if T.tw(try, font) <= w then
            cur = try
        else
            if cur ~= "" then lines[#lines + 1] = cur end
            cur = word
            while T.tw(cur, font) > w and string.len(cur) > 3 do
                local part = T.fit(cur, w, font)
                local n0 = string.len(part) - 2
                if n0 < 1 then break end
                local n = safeCut(cur, n0)
                if n < 1 then n = n0 end
                part = string.sub(cur, 1, n)
                if part == "" then break end
                lines[#lines + 1] = part
                cur = string.sub(cur, string.len(part) + 1)
            end
        end
        if maxLines and #lines >= maxLines then break end
    end
    if cur ~= "" and not (maxLines and #lines >= maxLines) then lines[#lines + 1] = cur end
    return lines
end

-- ------------------------------------------------------------------ textures (looked up once)
local texCache = {}
function T.tex(name)
    local v = texCache[name]
    if v == nil then
        local ok, tx = pcall(getTexture, "media/textures/CookieHelper/" .. name .. ".png")
        v = (ok and tx) or false
        texCache[name] = v
    end
    return v or nil
end

-- ------------------------------------------------------------------ drawing (el = any ISUIElement)
function T.rect(el, x, y, w, h, c, a)
    if w <= 0 or h <= 0 then return end
    el:drawRect(floor(x), floor(y), floor(w), floor(h), a or 1, c[1], c[2], c[3])
end

function T.rrect(el, x, y, w, h, r, c, a)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    if w <= 0 or h <= 0 then return end
    r = floor(math.min(r or 8, w / 2, h / 2))
    if r < 2 or not T.tex("rc_tl") then return T.rect(el, x, y, w, h, c, a) end
    a = a or 1
    el:drawRect(x + r, y, w - 2 * r, r, a, c[1], c[2], c[3])
    el:drawRect(x, y + r, w, h - 2 * r, a, c[1], c[2], c[3])
    el:drawRect(x + r, y + h - r, w - 2 * r, r, a, c[1], c[2], c[3])
    el:drawTextureScaled(T.tex("rc_tl"), x, y, r, r, a, c[1], c[2], c[3])
    el:drawTextureScaled(T.tex("rc_tr"), x + w - r, y, r, r, a, c[1], c[2], c[3])
    el:drawTextureScaled(T.tex("rc_bl"), x, y + h - r, r, r, a, c[1], c[2], c[3])
    el:drawTextureScaled(T.tex("rc_br"), x + w - r, y + h - r, r, r, a, c[1], c[2], c[3])
end

-- rounded card with a coloured outline (selected / hovered): outer colour, inner fill
function T.rring(el, x, y, w, h, r, ring, fill, thick)
    thick = thick or 2
    T.rrect(el, x, y, w, h, r, ring)
    T.rrect(el, x + thick, y + thick, w - thick * 2, h - thick * 2, math.max(2, (r or 8) - thick), fill)
end

function T.circle(el, x, y, d, c, a)
    local tx = T.tex("circle")
    if tx then el:drawTextureScaled(tx, floor(x), floor(y), floor(d), floor(d), a or 1, c[1], c[2], c[3])
    else T.rect(el, x, y, d, d, c, a) end
end

-- white line icon tinted
function T.icon(el, name, x, y, size, c, a)
    local tx = T.tex("ic_" .. name)
    if not tx then return false end
    c = c or T.C.text
    el:drawTextureScaled(tx, floor(x), floor(y), floor(size), floor(size), a or 1, c[1], c[2], c[3])
    return true
end

-- pixel icon as-is (sizes that are whole multiples of 16 stay crisp)
function T.px(el, name, x, y, size, a)
    local tx = T.tex("px_" .. name)
    if not tx then return false end
    el:drawTextureScaled(tx, floor(x), floor(y), floor(size), floor(size), a or 1, 1, 1, 1)
    return true
end

-- any texture (item icons from the game) fitted into a box
function T.texture(el, tx, x, y, w, h, a)
    if not tx then return false end
    el:drawTextureScaledAspect(tx, floor(x), floor(y), floor(w), floor(h), a or 1, 1, 1, 1)
    return true
end

function T.text(el, s, x, y, c, f, a)
    c = c or T.C.text
    el:drawText(tostring(s), floor(x), floor(y), c[1], c[2], c[3], a or 1, f or T.FS)
end
function T.textR(el, s, x, y, c, f, a)
    c = c or T.C.text
    el:drawTextRight(tostring(s), floor(x), floor(y), c[1], c[2], c[3], a or 1, f or T.FS)
end
function T.textC(el, s, x, y, c, f, a)
    c = c or T.C.text
    el:drawTextCentre(tostring(s), floor(x), floor(y), c[1], c[2], c[3], a or 1, f or T.FS)
end

-- text vertically centred in a box of height h
function T.textV(el, s, x, y, h, c, f, a)
    T.text(el, s, x, y + floor((h - T.th(f)) / 2), c, f, a)
end

-- small pill; icon = { px = "name" } or { ic = "name" }; returns width, height
function T.pillW(label, f, icon)
    f = f or T.FS
    local h = T.th(f) + 4
    local iw = icon and (h - 2) or 0
    return T.tw(label, f) + 16 + iw, h
end

function T.pill(el, x, y, label, fg, bg, f, icon, bgA)
    f = f or T.FS
    local w, h = T.pillW(label, f, icon)
    T.rrect(el, x, y, w, h, floor(h / 2), bg, bgA)
    local tx = x + 8
    if icon then
        local s = h - 2
        if icon.px then T.px(el, icon.px, x + 3, y + 1, s)
        elseif icon.ic then T.icon(el, icon.ic, x + 4, y + 2, s - 2, fg) end
        tx = tx + s - 3
    end
    T.text(el, label, tx, y + 2, fg, f)
    return w, h
end

-- coloured dot + label (house colour legends)
function T.dotLabel(el, x, y, c, label, fg, f)
    local h = T.th(f)
    local d = floor(h * 0.55)
    T.circle(el, x, y + floor((h - d) / 2), d, c)
    T.text(el, label, x + d + 6, y, fg or T.C.text, f)
end

function T.hot(r, mx, my)
    return r ~= nil and mx ~= nil and my ~= nil and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

-- avatar circle with the first letter, colour picked from the name (same name = same colour)
function T.avatarColor(key)
    local s, n = tostring(key or "?"), 0
    for i = 1, string.len(s) do n = (n * 31 + string.byte(s, i)) % 100003 end
    return T.AVATAR[(n % #T.AVATAR) + 1]
end

function T.avatar(el, x, y, d, name)
    T.circle(el, x, y, d, T.avatarColor(name))
    local s = tostring(name or "?")
    -- in the game strings are Java strings (1 unit = 1 letter); plain Lua sees UTF-8 bytes
    local b1 = string.byte(s, 1) or 63
    local b2 = string.byte(s, 2)
    local n = 1
    if b1 < 256 and b2 and b2 >= 128 and b2 < 192 then
        if b1 >= 240 then n = 4 elseif b1 >= 224 then n = 3 elseif b1 >= 192 then n = 2 end
    end
    local ch = string.upper(string.sub(s, 1, n))
    local f = (d >= T.th(T.FM) + 8) and T.FM or T.FS
    T.textC(el, ch, x + d / 2, y + floor((d - T.th(f)) / 2), T.C.onAcc, f)
end

-- status badge (✓ / ✕ / +) on an item slot corner
function T.badge(el, x, y, d, kind)
    local c = kind == "ok" and T.C.acc or (kind == "link" and T.C.warn or T.C.bad)
    T.circle(el, x - 2, y - 2, d + 4, T.C.surf)
    T.circle(el, x, y, d, c)
    local ic = kind == "ok" and "check" or (kind == "link" and "plus" or "close")
    T.icon(el, ic, x + 3, y + 3, d - 6, T.C.onAcc)
end

-- item slot: dark rounded square with an item / pixel icon in it
function T.slot(el, x, y, s, tex, pxName)
    T.rrect(el, x, y, s, s, floor(s / 4), T.C.bar)
    local pad = floor(s * 0.12)
    if tex then T.texture(el, tex, x + pad, y + pad, s - pad * 2, s - pad * 2)
    elseif pxName then
        local isz = s >= 40 and 32 or 16
        if s >= 56 then isz = 48 end
        T.px(el, pxName, x + floor((s - isz) / 2), y + floor((s - isz) / 2), isz)
    end
end

return T
