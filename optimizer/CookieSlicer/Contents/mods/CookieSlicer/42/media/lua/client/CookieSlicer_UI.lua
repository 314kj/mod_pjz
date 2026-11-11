-- Cookie Slicer (client): the window (black / mint), the "Cookie Slicer" button on the
-- MAIN MENU and the in-game key (F8 by default, Options > Mods to change it).
-- Left: menu (Performance / Shader / Version Slicer).
-- Performance: "your PC now" (point at a number to see what it means and how yours
-- looks) + what the chosen settings should save, and the settings (levels + switches).
-- Sizes come from the game's fonts: big fonts when the window fits the screen, the
-- smaller set otherwise (1366x768).
-- Text comes from Translate/<language>/UI.json (Thai and English).
-- Copyright (c) AKA / Cookie Cheetah. See workshop.txt for the license.
if isServer() then return end

require "ISUI/ISPanel"

local CS = CookieSlicer
if not CS then return end

local function T(key, a, b, c, d)
    if d ~= nil then return getText("UI_CookieSlicer_" .. key, a, b, c, d) end
    if c ~= nil then return getText("UI_CookieSlicer_" .. key, a, b, c) end
    if b ~= nil then return getText("UI_CookieSlicer_" .. key, a, b) end
    if a ~= nil then return getText("UI_CookieSlicer_" .. key, a) end
    return getText("UI_CookieSlicer_" .. key)
end
local function fh(font) return getTextManager():getFontHeight(font) end
local function tw(text, font) return getTextManager():MeasureStringX(font, text) end
local function round(v) return math.floor(v + 0.5) end
local function round1(v) return math.floor(v * 10 + 0.5) / 10 end
local function gb(mb) return tostring(round1((tonumber(mb) or 0) / 1024)) end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

-- black / mint
local C = {
    bg = { 0.027, 0.039, 0.039 }, head = { 0.039, 0.067, 0.063 }, nav = { 0.020, 0.027, 0.027 },
    card = { 0.047, 0.075, 0.071 }, line = { 0.122, 0.180, 0.169 }, line2 = { 0.184, 0.290, 0.267 },
    track = { 0.102, 0.149, 0.141 }, trackOld = { 0.180, 0.259, 0.243 }, btn = { 0.063, 0.102, 0.094 },
    btnHover = { 0.090, 0.150, 0.138 }, off = { 0.133, 0.188, 0.176 },
    text = { 0.910, 0.953, 0.941 }, bright = { 0.949, 1.0, 0.984 }, soft = { 0.812, 0.890, 0.867 },
    dim = { 0.616, 0.702, 0.678 }, faint = { 0.486, 0.573, 0.549 },
    mint = { 0.310, 0.961, 0.784 }, mintDark = { 0.118, 0.561, 0.455 }, knob = { 0.910, 1.0, 0.973 },
    onText = { 0.012, 0.078, 0.059 }, warn = { 1.0, 0.784, 0.341 }, bad = { 1.0, 0.420, 0.400 },
}

local FONTS_BIG = { title = UIFont.Large, body = UIFont.Medium, small = UIFont.Small, num = UIFont.Massive }
local FONTS_SMALL = { title = UIFont.Medium, body = UIFont.Small, small = UIFont.Small, num = UIFont.Large }

local function keyName()
    local name = "F8"
    pcall(function() name = Keyboard.getKeyName(CS.openKey()) end)
    return name
end

local function verLess(a, b)
    local function parts(v)
        local t = {}
        for n in string.gmatch(tostring(v or ""), "%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p < q end
    end
    return false
end

-- ================================================================ window

CookieSlicerWindow = ISPanel:derive("CookieSlicerWindow")

function CookieSlicerWindow:new(x, y, fonts, screenW)
    local width = math.min(1780, screenW - 40)
    local o = ISPanel:new(x, y, width, 400)
    setmetatable(o, self)
    self.__index = self
    o.F = fonts
    o.pad = math.max(14, math.floor(fh(fonts.body) * 0.8))
    o.gap = math.max(10, math.floor(fh(fonts.body) * 0.6))
    o.headH = fh(fonts.title) + 22
    o.navW = clamp(math.floor(width * 0.19), 220, 340)
    o.colW = math.floor((width - 2 * o.pad - o.navW - 2 * o.gap) / 2)
    o.page = CS.settings.page
    if o.page ~= "shader" and o.page ~= "version" then o.page = "perf" end
    o.lastH = {}
    o.hits, o.tips = {}, {}
    o.backgroundColor = { r = C.bg[1], g = C.bg[2], b = C.bg[3], a = 0.97 }
    o.borderColor = { r = C.line[1], g = C.line[2], b = C.line[3], a = 1 }
    o.dragHead = false
    return o
end

-- ---------------------------------------------------------------- drawing helpers
-- (self.dry = measure only: used once to pick the font size that fits the screen)

function CookieSlicerWindow:rect(x, y, w, h, c, a)
    if self.dry then return end
    self:drawRect(x, y, w, h, a or 1, c[1], c[2], c[3])
end

function CookieSlicerWindow:frame(x, y, w, h, c, a, t)
    if self.dry then return end
    t = t or 1
    if t <= 1 then
        self:drawRectBorder(x, y, w, h, a or 1, c[1], c[2], c[3])
        return
    end
    self:rect(x, y, w, t, c, a)
    self:rect(x, y + h - t, w, t, c, a)
    self:rect(x, y, t, h, c, a)
    self:rect(x + w - t, y, t, h, c, a)
end

function CookieSlicerWindow:text(s, x, y, c, font)
    if self.dry then return end
    self:drawText(s, x, y, c[1], c[2], c[3], 1, font)
end

function CookieSlicerWindow:textC(s, cx, y, c, font)
    if self.dry then return end
    self:drawTextCentre(s, cx, y, c[1], c[2], c[3], 1, font)
end

function CookieSlicerWindow:textR(s, rx, y, c, font)
    self:text(s, rx - tw(s, font), y, c, font)
end

-- drop the last character (in byte strings never leave half a UTF-8 character)
local function dropLast(s)
    s = string.sub(s, 1, #s - 1)
    while #s > 0 do
        local c = string.byte(s, #s)
        if c >= 128 and c < 192 then
            s = string.sub(s, 1, #s - 1)
        elseif c >= 192 and c < 256 then
            s = string.sub(s, 1, #s - 1)
            break
        else
            break
        end
    end
    return s
end

-- cut text that does not fit
local function fit(s, font, maxW)
    if tw(s, font) <= maxW then return s end
    local cut = s
    while #cut > 1 and tw(cut .. "...", font) > maxW do cut = dropLast(cut) end
    return cut .. "..."
end

-- break text at spaces into lines that fit (our Thai texts put spaces between phrases)
local function wrap(s, font, maxW)
    local lines, line = {}, ""
    for word in string.gmatch(s, "%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and tw(try, font) > maxW then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    for i, l in ipairs(lines) do lines[i] = fit(l, font, maxW) end
    return lines
end

-- a paragraph; returns the y below it
function CookieSlicerWindow:para(s, x, y, w, c, font)
    for _, l in ipairs(wrap(s, font, w)) do
        self:text(l, x, y, c, font)
        y = y + fh(font) + 2
    end
    return y
end

function CookieSlicerWindow:mouseIn(x, y, w, h)
    if self.dry then return false end
    local mx, my = self:getMouseX(), self:getMouseY()
    return mx >= x and mx < x + w and my >= y and my < y + h
end

function CookieSlicerWindow:hit(x, y, w, h, fn, arg)
    table.insert(self.hits, { x = x, y = y, w = w, h = h, fn = fn, arg = arg })
end

function CookieSlicerWindow:tipAt(x, y, w, h, id)
    table.insert(self.tips, { x = x, y = y, w = w, h = h, id = id })
end

-- style: "primary" (mint), "normal", "ghost"
function CookieSlicerWindow:button(x, y, w, h, label, font, fn, arg, style)
    local hover = self:mouseIn(x, y, w, h)
    if style == "primary" then
        self:rect(x, y, w, h, C.mint, hover and 0.85 or 1)
        self:textC(label, x + w / 2, y + math.floor((h - fh(font)) / 2), C.onText, font)
    else
        if style ~= "ghost" or hover then self:rect(x, y, w, h, hover and C.btnHover or C.btn) end
        self:frame(x, y, w, h, hover and C.mint or C.line2, 1)
        self:textC(label, x + w / 2, y + math.floor((h - fh(font)) / 2), C.text, font)
    end
    self:hit(x, y, w, h, fn, arg)
end

-- card: background, thin frame, mint corner marks
function CookieSlicerWindow:card(x, y, w, h)
    self:rect(x, y, w, h, C.card)
    self:frame(x, y, w, h, C.line)
    local L, t = 16, 3
    self:rect(x, y, L, t, C.mint); self:rect(x, y, t, L, C.mint)
    self:rect(x + w - L, y, L, t, C.mint); self:rect(x + w - t, y, t, L, C.mint)
    self:rect(x, y + h - t, L, t, C.mint); self:rect(x, y + h - L, t, L, C.mint)
    self:rect(x + w - L, y + h - t, L, t, C.mint); self:rect(x + w - t, y + h - L, t, L, C.mint)
end

-- small "i" box after a label (there is an explanation when you point at it)
function CookieSlicerWindow:info(x, y, font)
    local s = math.max(12, fh(font) - 8)
    local yy = y + math.floor((fh(font) - s) / 2)
    self:frame(x, yy, s, s, C.faint, 1)
    self:textC("i", x + s / 2, yy + math.floor((s - fh(UIFont.Small)) / 2), C.faint, UIFont.Small)
    return s
end

-- title with a small English tag after it
function CookieSlicerWindow:heading(title, tag, x, y)
    local F = self.F
    self:text(title, x, y, C.text, F.title)
    if tag then
        self:text(tag, x + tw(title, F.title) + 12, y + fh(F.title) - fh(F.small) - 2, C.faint, F.small)
    end
    return y + fh(F.title) + self.gap
end

-- ---------------------------------------------------------------- your PC now

local function levelColor(level)
    if level == "good" then return C.mint elseif level == "ok" then return C.warn end
    return C.bad
end

-- the four numbers from the helper ("--" when it is not running)
local function metrics()
    local pc = CS.pc
    local m = {
        { id = "ram", label = T("M_ram") }, { id = "pcram", label = T("M_pcram") },
        { id = "cpu", label = T("M_cpu") }, { id = "main", label = T("M_main") },
    }
    for _, it in ipairs(m) do it.value = "--" end
    if not pc.fresh then return m end
    local used = tonumber(pc.heap_live_mb)
    if not used or used == 0 then used = tonumber(pc.heap_used_mb) end
    local max = tonumber(pc.heap_max_mb)
    if used and max and max > 0 then
        m[1].value = T("V_ram", gb(used), gb(max))
        m[1].frac = used / max
        m[1].color = m[1].frac > 0.85 and C.warn or C.mint
    end
    local free, total = tonumber(pc.ram_free_mb), tonumber(pc.ram_total_mb)
    if free and total and total > 0 then
        m[2].value = T("V_pcram", gb(free), gb(total))
        m[2].frac = (total - free) / total
        m[2].color = free < 1500 and C.warn or C.mint
    end
    local cpu = tonumber(pc.cpu_total)
    if cpu then
        m[3].value = tostring(cpu) .. "%"
        m[3].frac = cpu / 100
        m[3].color = cpu > 90 and C.warn or C.mint
    end
    local main = tonumber(pc.main_thread)
    if main then
        m[4].value = tostring(main) .. "%"
        m[4].frac = main / 100
        m[4].color = main >= 80 and C.warn or C.mint
        if main >= 80 then m[4].vc = C.warn end
    end
    return m
end

function CookieSlicerWindow:drawLive(x, y0, w)
    local F, p, gap = self.F, self.pad, self.gap
    self:card(x, y0, w, self.lastH.live or 300)
    local cx, cw = x + p, w - 2 * p
    local y = y0 + p
    -- title
    self:text(T("Live"), cx, y, C.text, F.title)
    local lx = cx + tw(T("Live"), F.title) + 12
    local ty = y + fh(F.title) - fh(F.small) - 2
    self:text("LIVE", lx, ty, C.faint, F.small)
    local hint = T("LiveHint")
    if lx + tw("LIVE", F.small) + 24 + tw(hint, F.small) <= cx + cw then
        self:textR(hint, cx + cw, ty, C.dim, F.small)
    end
    y = y + fh(F.title) + gap

    -- FPS and the one-word level
    local level, tip = CS.verdict()
    self.tip = tip
    local f = CS.fps
    local playing = getPlayer() ~= nil and f.n > 0
    local num = playing and tostring(round(f.avg)) or "--"
    self:text(num, cx, y, C.bright, F.num)
    local nx = cx + tw(num, F.num) + 12
    local sub = playing and T("FpsLine", tostring(round(f.min))) or T("FpsMenu")
    local subY = y + fh(F.num) - fh(F.body) - 4
    self:text(sub, nx, subY, C.dim, F.body)
    local iw = self:info(nx + tw(sub, F.body) + 8, subY, F.body)
    self:tipAt(cx, y, nx + tw(sub, F.body) + 8 + iw - cx, fh(F.num), "fps")
    local word = T(level == "good" and "Good" or (level == "ok" and "Ok" or "Heavy"))
    local lc = levelColor(level)
    local pw, ph = tw(word, F.body) + 32, fh(F.body) + 12
    local px, py = cx + cw - pw, y + math.floor((fh(F.num) - ph) / 2)
    self:rect(px, py, pw, ph, lc, 0.12)
    self:frame(px, py, pw, ph, lc, 1, 2)
    self:textC(word, px + pw / 2, py + 6, lc, F.body)
    self:tipAt(px, py, pw, ph, "state")
    y = y + fh(F.num) + gap

    -- the four numbers, two per row
    local half = math.floor((cw - gap) / 2)
    local cellH = fh(F.body) + 6 + 10
    for i, it in ipairs(metrics()) do
        local mx = cx + ((i - 1) % 2) * (half + gap)
        local my = y + math.floor((i - 1) / 2) * (cellH + gap)
        self:text(it.label, mx, my, C.text, F.body)
        self:info(mx + tw(it.label, F.body) + 6, my, F.body)
        self:textR(it.value, mx + half, my, it.vc or C.text, F.body)
        self:rect(mx, my + fh(F.body) + 6, half, 10, C.track)
        if it.frac then
            self:rect(mx, my + fh(F.body) + 6, math.floor(half * clamp(it.frac, 0, 1)), 10, it.color)
        end
        self:tipAt(mx, my, half, cellH, it.id)
    end
    y = y + 2 * cellH + gap + 4

    local pc = CS.pc
    if not pc.fresh then
        y = self:para(T(pc.present and "HelperStopped" or "NoHelper"), cx, y, cw, C.dim, F.small) + gap - 2
    end
    -- more RAM for the game (only when the helper says the game is short of it)
    if pc.heap_next_mb and tonumber(pc.heap_next_mb) then self.fixDone = T("RamQueued", gb(pc.heap_next_mb)) end
    local rec, max = tonumber(pc.heap_recommend_mb), tonumber(pc.heap_max_mb) or 0
    if self.fixDone then
        y = self:para(self.fixDone, cx, y, cw, C.mint, F.small) + gap - 2
    elseif tip == "ram_heap" and rec and rec > max then
        local label = T("FixRam", gb(rec))
        local bh = fh(F.body) + 14
        self:button(cx, y, math.min(cw, tw(label, F.body) + 40), bh, label, F.body, CookieSlicerWindow.onFix, rec, "primary")
        y = y + bh + gap
    end

    -- what the settings on the right should save
    self:rect(cx, y, cw, 1, C.line)
    y = y + gap
    local tag = T("EstTag")
    local tagW = tw(tag, F.small) + 20
    self:text(fit(T("Est"), F.body, cw - tagW - 12), cx, y, C.text, F.body)
    self:frame(cx + cw - tagW, y + 2, tagW, fh(F.small) + 4, C.line2, 1)
    self:textC(tag, cx + cw - tagW / 2, y + 4, C.soft, F.small)
    y = y + fh(F.body) + gap

    local e = CS.tuneEstimate()
    local ms = CS.measure
    local function row(label, value, valueColor, before, after)
        self:text(fit(label, F.body, cw - tw(value, F.body) - 16), cx, y, valueColor == C.dim and C.dim or C.text, F.body)
        self:textR(value, cx + cw, y, valueColor or C.bright, F.body)
        y = y + fh(F.body) + 4
        if before and after then
            self:rect(cx, y, cw, 12, C.track)
            self:rect(cx, y, math.floor(cw * clamp(before, 0, 1)), 12, C.trackOld)
            self:rect(cx, y, math.floor(cw * clamp(after, 0, 1)), 12, C.mint)
            y = y + 12
        end
        y = y + gap - 2
    end
    if not e.changed then
        y = self:para(T("EstNone"), cx, y, cw, C.dim, F.body) + gap - 2
    else
        local mb = ms and ms.mainBefore
        if mb then
            local after = round(mb * (1 - e.saving))
            row(T("E_main"), T("E_mainFromTo", tostring(mb), tostring(after)), nil, mb / 100, after / 100)
        else
            row(T("E_main"), T("E_mainPct", tostring(math.max(1, round(e.saving * 100)))))
        end
        local fbo = false
        pcall(function() fbo = getCore():getOptionUIFBO() end)
        local ui = e.uifps
        if ui and fbo and tonumber(ui.prev) and tonumber(ui.now) and tonumber(ui.prev) > 0 then
            row(T("E_ui"), T("E_perSec", ui.prev, tostring(ui.now)), nil, 1, tonumber(ui.now) / tonumber(ui.prev))
        end
        local li = e.lighting
        if li and tonumber(li.prev) and tonumber(li.now) and tonumber(li.prev) > 0 then
            row(T("E_light"), T("E_perSec", li.prev, tostring(li.now)), nil, 1, tonumber(li.now) / tonumber(li.prev))
        end
        if e.clothes then row(T("E_clothes"), T("E_clothesV")) end
        if e.vram then row(T("E_vram"), T("E_vramLess")) else row(T("E_vram"), T("E_vramSame"), C.dim) end
    end

    -- measured: FPS before / after
    local mline
    local inGame = getPlayer() ~= nil
    if ms and ms.before and ms.after then
        mline = T("MeasDone", tostring(round(ms.before)), tostring(round(ms.after)))
    elseif ms and ms.before then
        mline = T("MeasWait", tostring(round(ms.before)))
    elseif ms and ms.after then
        mline = T("MeasAfterOnly", tostring(round(ms.after)))
    elseif not inGame then
        mline = T("MeasMenu")
    elseif ms then
        mline = T("MeasNoBefore")
    else
        mline = T("MeasNone")
    end
    local label = T("Meas") .. " "
    local lw = tw(label, F.body)
    local ml = wrap(mline, F.body, cw - 28 - lw)
    local nl = wrap(T("EstNote"), F.small, cw - 28)
    local bh = 12 + #ml * (fh(F.body) + 2) + 4 + #nl * (fh(F.small) + 2) + 10
    self:rect(cx, y, cw, bh, C.nav)
    self:frame(cx, y, cw, bh, C.line)
    self:text(label, cx + 14, y + 12, C.mint, F.body)
    local yy = self:para(mline, cx + 14 + lw, y + 12, cw - 28 - lw, C.text, F.body)
    self:para(T("EstNote"), cx + 14, yy + 4, cw - 28, C.dim, F.small)
    y = y + bh + p
    self.lastH.live = y - y0
    return y
end

-- ---------------------------------------------------------------- settings

function CookieSlicerWindow:drawTune(x, y0, w)
    local F, p, gap = self.F, self.pad, self.gap
    self:card(x, y0, w, self.lastH.tune or 300)
    local cx, cw = x + p, w - 2 * p
    local y = self:heading(T("Tune"), "PRESET", cx, y0 + p)

    -- levels
    local cur = CS.tuneCurrentPreset()
    local n = #CS.PRESETS
    local segW = math.floor(cw / n)
    local segH = fh(F.body) + 22
    for i, id in ipairs(CS.PRESETS) do
        local sx = cx + (i - 1) * segW
        local sw = (i == n) and (cx + cw - sx) or segW
        self:button(sx, y, sw, segH, T("P_" .. id), F.body, CookieSlicerWindow.onPreset, id, cur == id and "primary" or "normal")
    end
    y = y + segH + 8
    y = self:para(T("PD_" .. cur), cx, y, cw, C.soft, F.small) + gap - 2

    -- switches
    local rowH = fh(F.body) + 18
    local trackW, trackH = math.floor(fh(F.body) * 2.4), fh(F.body) + 4
    local function group(weak)
        self:text(T(weak and "AfterRestart" or "NowGroup"), cx, y, C.dim, F.small)
        y = y + fh(F.small) + 6
        self:rect(cx, y, cw, 1, C.track)
        for _, item in ipairs(CS.TUNE) do
            if (item.weak == true) == weak then
                local good = CS.tuneIsGood(item)
                local hover = self:mouseIn(cx, y, cw, rowH)
                if hover and good ~= nil then self:rect(cx, y + 1, cw, rowH - 1, C.btnHover, 0.6) end
                local ly = y + math.floor((rowH - fh(F.body)) / 2)
                if good == nil then
                    self:text(fit(T("Tune_" .. item.id), F.body, cw - tw(T("NA"), F.small) - 16), cx + 4, ly, C.dim, F.body)
                    self:textR(T("NA"), cx + cw, y + math.floor((rowH - fh(F.small)) / 2), C.faint, F.small)
                else
                    local word = T(good and "On" or "Off")
                    local tx = cx + cw - trackW
                    local tyy = y + math.floor((rowH - trackH) / 2)
                    self:text(fit(T("Tune_" .. item.id), F.body, cw - trackW - tw(word, F.body) - 28), cx + 4, ly, C.text, F.body)
                    self:textR(word, tx - 10, ly, good and C.mint or C.dim, F.body)
                    self:rect(tx, tyy, trackW, trackH, good and C.mintDark or C.off)
                    local k = trackH - 6
                    self:rect(good and (tx + trackW - k - 3) or (tx + 3), tyy + 3, k, k, good and C.knob or C.faint)
                    self:hit(cx, y, cw, rowH, CookieSlicerWindow.onToggle, item.id)
                end
                y = y + rowH
                self:rect(cx, y, cw, 1, C.track)
            end
        end
        y = y + gap
    end
    group(false)
    group(true)
    if self.tuneMsg then
        y = self:para(self.tuneMsg, cx, y, cw, C.mint, F.small) + gap - 2
    end
    y = y + p - gap
    self.lastH.tune = y - y0
    return y
end

-- ---------------------------------------------------------------- shader page

-- a little scene in a look's colours (the look cards)
function CookieSlicerWindow:miniScene(px, py, pw, ph, s, id)
    self:rect(px, py, pw, ph, { s[1] * 1.35, s[2] * 1.35, s[3] * 1.35 })
    local gh = math.floor(ph * 0.38)
    self:rect(px, py + ph - gh, pw, gh, { s[1] * 0.7, s[2] * 0.7, s[3] * 0.7 })
    local hw, hh = math.floor(pw * 0.18), math.floor(ph * 0.36)
    local hx, hy = px + math.floor((pw - hw) / 2), py + ph - gh - hh + math.floor(gh / 3)
    self:rect(hx, hy, hw, hh, { s[1] * 0.45, s[2] * 0.45, s[3] * 0.45 })
    if id == "cinema" then
        self:rect(px, py, pw, 5, { 0, 0, 0 })
        self:rect(px, py + ph - 5, pw, 5, { 0, 0, 0 })
    elseif id == "glow" or id == "dark" or id == "golden" then
        local g = id == "glow" and 10 or 6
        self:rect(hx + math.floor(hw / 2) - g, hy + 4 - math.floor(g / 2), g * 2, g * 2, C.warn, 0.35)
        self:rect(hx + math.floor(hw / 2) - 3, hy + 6, 6, 6, C.warn)
    end
end

local function paramById(id)
    for _, prm in ipairs(CS.SH_PARAMS) do
        if prm.id == id then return prm end
    end
end

local function fmtParam(id, v)
    if id == "exp" or id == "warm" then return string.format("%+.1f", v) end
    if id == "con" or id == "sat" then return string.format("x%.2f", v) end
    return tostring(round(v * 100)) .. "%"
end

-- one slider row: name, -, bar (click or drag), +, value
function CookieSlicerWindow:slider(x, y, w, prm, lookId)
    local F = self.F
    local v = CS.shaderParam(lookId, prm.id)
    local rowH = fh(F.body) + 12
    local labelW = math.floor(w * 0.3)
    local valW = tw("x1.00", F.body) + 12
    local bs = rowH - 6
    self:text(fit(T("SP_" .. prm.id), F.body, labelW - 8), x, y + 6, C.text, F.body)
    local bx = x + labelW
    self:button(bx, y + 3, bs, bs, "-", F.body, CookieSlicerWindow.onParam, { id = prm.id, d = -prm.step }, "normal")
    local barX = bx + bs + 12
    local barW = x + w - valW - bs - 12 - barX
    local by = y + math.floor(rowH / 2) - 3
    self:rect(barX, by, barW, 6, C.track)
    local look = CS.shaderLook(lookId)
    local d0 = clamp(((look.p[prm.id] or 0) - prm.min) / (prm.max - prm.min), 0, 1)
    self:rect(barX + math.floor(barW * d0) - 1, by - 5, 2, 16, C.faint) -- the look's own value
    local t = clamp((v - prm.min) / (prm.max - prm.min), 0, 1)
    self:rect(barX, by, math.floor(barW * t), 6, C.mint)
    self:rect(barX + math.floor(barW * t) - 5, by - 7, 10, 20, C.knob)
    self:hit(barX - 8, y, barW + 16, rowH, CookieSlicerWindow.onParamBar, { id = prm.id, x = barX, w = barW })
    self:button(barX + barW + 12, y + 3, bs, bs, "+", F.body, CookieSlicerWindow.onParam, { id = prm.id, d = prm.step }, "normal")
    self:textR(fmtParam(prm.id, v), x + w, y + 6, C.bright, F.body)
    return y + rowH + 4
end

-- an on / off switch row (the same look as the settings on the Performance page)
function CookieSlicerWindow:switchRow(x, y, w, label, on, fn, arg)
    local F = self.F
    local rowH = fh(F.body) + 18
    local trackW, trackH = math.floor(fh(F.body) * 2.4), fh(F.body) + 4
    if self:mouseIn(x, y, w, rowH) then self:rect(x, y, w, rowH, C.btnHover, 0.6) end
    local ly = y + math.floor((rowH - fh(F.body)) / 2)
    local word = T(on and "On" or "Off")
    local tx = x + w - trackW
    local ty = y + math.floor((rowH - trackH) / 2)
    self:text(fit(label, F.body, w - trackW - tw(word, F.body) - 28), x + 4, ly, C.text, F.body)
    self:textR(word, tx - 10, ly, on and C.mint or C.dim, F.body)
    self:rect(tx, ty, trackW, trackH, on and C.mintDark or C.off)
    local k = trackH - 6
    self:rect(on and (tx + trackW - k - 3) or (tx + 3), ty + 3, k, k, on and C.knob or C.faint)
    self:hit(x, y, w, rowH, fn, arg)
    return y + rowH
end

-- left card: can this PC run it, on / off, quality, recommend, compare
function CookieSlicerWindow:drawShaderReq(x, y0, w)
    local F, p, gap = self.F, self.pad, self.gap
    self:card(x, y0, w, self.lastH.shreq or 300)
    local cx, cw = x + p, w - 2 * p
    local y = self:heading(T("SReq"), "SHADER", cx, y0 + p)
    local rows, worst = CS.shaderCheck()
    local waiting = false
    for _, r in ipairs(rows) do if r.state == "wait" then waiting = true end end
    local vkey = worst == "bad" and "V_bad" or (worst == "warn" and "V_warn" or (waiting and "V_wait" or "V_ok"))
    local vc = worst == "bad" and C.bad or (worst == "warn" and C.warn or C.mint)
    y = self:para(T(vkey), cx, y, cw, vc, F.body) + 8
    local labelW = math.floor(cw * 0.28)
    for _, r in ipairs(rows) do
        local sc = r.state == "ok" and C.mint or (r.state == "warn" and C.warn or (r.state == "bad" and C.bad or C.faint))
        self:rect(cx, y + math.floor((fh(F.body) - 10) / 2), 10, 10, sc)
        self:text(fit(T("Req_" .. r.id), F.body, labelW - 22), cx + 18, y, C.dim, F.body)
        local val = r.b ~= nil and T(r.key, r.a or "", r.b) or (r.a ~= nil and T(r.key, r.a) or T(r.key))
        y = self:para(val, cx + labelW, y, cw - labelW, C.text, F.body) + 6
    end
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    local mb = math.floor(sw * sh * 4 * 1.34 / 1048576 + 0.5)
    y = self:para(T("SVram", tostring(mb), tostring(sw) .. "x" .. tostring(sh)), cx, y + 2, cw, C.dim, F.small) + gap
    self:rect(cx, y, cw, 1, C.line)
    y = y + gap

    if not CS.helperCanShade() then
        y = self:para(T("SBasicWhy"), cx, y, cw, C.soft, F.body) + gap
    else
        y = self:switchRow(cx, y, cw, T("SOn"), CS.shaderOn(), CookieSlicerWindow.onShaderOn) + gap
        -- quality
        self:text(T("SQual"), cx, y, C.dim, F.small)
        y = y + fh(F.small) + 6
        local cur = tostring(CS.settings.sh_q or "auto")
        local opts = { "auto", "0", "1", "2" }
        local segW = math.floor(cw / #opts)
        local segH = fh(F.body) + 18
        for i, q in ipairs(opts) do
            local sx = cx + (i - 1) * segW
            local sw2 = (i == #opts) and (cx + cw - sx) or segW
            self:button(sx, y, sw2, segH, T("SQ_" .. q), F.body, CookieSlicerWindow.onShaderQ, q, cur == q and "primary" or "normal")
        end
        y = y + segH + gap
        local rl = T("SRec")
        local rh = fh(F.body) + 18
        self:button(cx, y, cw, rh, rl, F.body, CookieSlicerWindow.onRecommend, nil, "primary")
        y = y + rh + 6
        if self.recMsg then y = self:para(self.recMsg, cx, y, cw, C.mint, F.small) + 4 end
        y = self:para(T("SRecHelp"), cx, y, cw, C.dim, F.small) + gap
        if getPlayer() then
            self:button(cx, y, cw, rh, T("Cmp"), F.body, CookieSlicerWindow.onCompare, nil, "normal")
            y = y + rh + gap
        else
            y = self:para(T("CmpMenu"), cx, y, cw, C.dim, F.small) + gap
        end
    end
    y = y + p - gap
    self.lastH.shreq = y - y0
    return y
end

-- right card with the helper: the looks and their sliders
function CookieSlicerWindow:drawShaderLooks(x, y0, w)
    local F, p, gap = self.F, self.pad, self.gap
    self:card(x, y0, w, self.lastH.shlooks or 300)
    local cx, cw = x + p, w - 2 * p
    local y = self:heading(T("SLooks"), "LOOK", cx, y0 + p)
    local cols = 4
    local cardW = math.floor((cw - (cols - 1) * gap) / cols)
    local prevH = math.floor(cardW * 0.36)
    local cardH = prevH + 8 + fh(F.body) + fh(F.small) + 10
    local cur = CS.shaderLookId()
    for i, look in ipairs(CS.SHADER_LOOKS) do
        local lx = cx + ((i - 1) % cols) * (cardW + gap)
        local ly = y + math.floor((i - 1) / cols) * (cardH + gap)
        local sel = cur == look.id
        local hover = self:mouseIn(lx, ly, cardW, cardH)
        self:rect(lx, ly, cardW, cardH, hover and C.btnHover or C.btn)
        self:miniScene(lx + 4, ly + 4, cardW - 8, prevH, look.swatch, look.id)
        local ny = ly + 4 + prevH + 4
        self:textC(fit(T("SLook_" .. look.id), F.body, cardW - 8), lx + cardW / 2, ny, C.text, F.body)
        self:textC(fit(T("SLookDesc_" .. look.id), F.small, cardW - 8), lx + cardW / 2, ny + fh(F.body), C.dim, F.small)
        if sel then self:frame(lx, ly, cardW, cardH, C.mint, 1, 2) else self:frame(lx, ly, cardW, cardH, C.line2, 1) end
        self:hit(lx, ly, cardW, cardH, CookieSlicerWindow.onShaderLook, look.id)
    end
    y = y + math.ceil(#CS.SHADER_LOOKS / cols) * (cardH + gap) + 4
    self:rect(cx, y, cw, 1, C.line)
    y = y + gap
    local look = CS.shaderLook(cur)
    self:text(T("SParams"), cx, y, C.text, F.body)
    self:text(T("SLook_" .. look.id), cx + tw(T("SParams"), F.body) + 12, y, C.mint, F.body)
    y = y + fh(F.body) + 8
    if look.off then
        y = self:para(T("SNatural"), cx, y, cw, C.dim, F.body) + gap
    else
        for _, prm in ipairs(CS.SH_PARAMS) do y = self:slider(cx, y, cw, prm, cur) end
        y = y + 6
        local rl = T("SResetLook")
        local rh = fh(F.body) + 14
        self:button(cx, y, tw(rl, F.body) + 40, rh, rl, F.body, CookieSlicerWindow.onResetLook, nil, "normal")
        y = y + rh + gap
    end
    y = y + p - gap
    self.lastH.shlooks = y - y0
    return y
end

-- right card without the helper: the simple colour layers (no install needed)
function CookieSlicerWindow:drawBasicLooks(x, y0, w)
    local F, p, gap = self.F, self.pad, self.gap
    self:card(x, y0, w, self.lastH.shbasic or 300)
    local cx, cw = x + p, w - 2 * p
    local y = y0 + p
    self:text(T("SBasic"), cx, y, C.text, F.title)
    y = y + fh(F.title) + 2
    y = self:para(T("NoCost"), cx, y, cw, C.dim, F.small) + gap
    local cols = 2
    local cardW = math.floor((cw - (cols - 1) * gap) / cols)
    local prevH = math.floor(cardW * 0.3)
    local cardH = prevH + 8 + fh(F.body) + fh(F.small) + 10
    for i, look in ipairs(CS.LOOKS) do
        local lx = cx + ((i - 1) % cols) * (cardW + gap)
        local ly = y + math.floor((i - 1) / cols) * (cardH + gap)
        local sel = CS.settings.look == look.id
        local hover = self:mouseIn(lx, ly, cardW, cardH)
        self:rect(lx, ly, cardW, cardH, hover and C.btnHover or C.btn)
        self:miniScene(lx + 4, ly + 4, cardW - 8, prevH, look.swatch, look.id)
        local ny = ly + 4 + prevH + 4
        self:textC(T("Look_" .. look.id), lx + cardW / 2, ny, C.text, F.body)
        self:textC(T("LookDesc_" .. look.id), lx + cardW / 2, ny + fh(F.body), C.dim, F.small)
        if sel then self:frame(lx, ly, cardW, cardH, C.mint, 1, 2) else self:frame(lx, ly, cardW, cardH, C.line2, 1) end
        self:hit(lx, ly, cardW, cardH, CookieSlicerWindow.onLook, look.id)
    end
    y = y + math.ceil(#CS.LOOKS / cols) * (cardH + gap) + 4

    -- brightness: - / + and three check squares as they look in the world now
    self:rect(cx, y, cw, 1, C.line)
    y = y + gap
    local b = tonumber(CS.settings.bright) or 0
    local bs = fh(F.title) + 14
    self:text(T("Bright"), cx, y + math.floor((bs - fh(F.title)) / 2), C.text, F.title)
    local bx = cx + tw(T("Bright"), F.title) + 20
    self:button(bx, y, bs, bs, "-", F.title, CookieSlicerWindow.onBright, -1, "normal")
    self:textC((b > 0 and "+" or "") .. tostring(b), bx + bs + 30, y + math.floor((bs - fh(F.title)) / 2), C.bright, F.title)
    self:button(bx + bs + 60, y, bs, bs, "+", F.title, CookieSlicerWindow.onBright, 1, "normal")
    local qx = bx + 2 * bs + 60 + 20
    local night = CS.nightNow()
    local q = math.min(bs, math.floor((cx + cw - qx - 12) / 3))
    for i, v in ipairs({ 0.0, 0.035, 0.09 }) do
        local r, g, bb = CS.through(v, v, v, night)
        self:rect(qx + (i - 1) * (q + 4), y + math.floor((bs - q) / 2), q, q, { r, g, bb })
        self:frame(qx + (i - 1) * (q + 4), y + math.floor((bs - q) / 2), q, q, C.line2, 1)
    end
    y = y + bs + 6
    y = self:para(T("BrightHelp"), cx, y, cw, C.dim, F.small) + gap
    local rl = T("Reset")
    local rh = fh(F.body) + 14
    self:button(cx, y, tw(rl, F.body) + 40, rh, rl, F.body, CookieSlicerWindow.onReset, nil, "normal")
    y = y + rh + p
    self.lastH.shbasic = y - y0
    return y
end

function CookieSlicerWindow:drawShader(x, y0, w)
    local half = math.floor((w - self.gap) / 2)
    local b1 = self:drawShaderReq(x, y0, half)
    local b2
    if CS.helperCanShade() then
        b2 = self:drawShaderLooks(x + half + self.gap, y0, w - half - self.gap)
    else
        b2 = self:drawBasicLooks(x + half + self.gap, y0, w - half - self.gap)
    end
    return math.max(b1, b2)
end

-- compare: the window sits on the left, the game on the right shows before | after
function CookieSlicerWindow:drawCompare()
    local F, pad, gap, W = self.F, self.pad, self.gap, self.width
    local hh = self.headH
    self:rect(0, 0, W, hh, C.head)
    self:rect(0, hh, W, 2, C.mint)
    local ty = math.floor((hh - fh(F.title)) / 2)
    self:rect(pad, ty + 3, 8, fh(F.title) - 6, C.mint)
    self:text("SHADER", pad + 20, ty, C.mint, F.title)
    local cl = T("CmpExit")
    local bw, bh = tw(cl, F.body) + 30, fh(F.body) + 12
    self:button(W - pad - bw, math.floor((hh - bh) / 2), bw, bh, cl, F.body, CookieSlicerWindow.onCompare, nil, "ghost")
    local cx, cw = pad, W - 2 * pad
    local y = hh + 2 + gap
    -- the looks, two per row
    local cur = CS.shaderLookId()
    local rowH = fh(F.body) + 16
    local colW = math.floor((cw - gap) / 2)
    for i, look in ipairs(CS.SHADER_LOOKS) do
        local lx = cx + ((i - 1) % 2) * (colW + gap)
        local ly = y + math.floor((i - 1) / 2) * (rowH + 6)
        local sel = cur == look.id
        local hover = self:mouseIn(lx, ly, colW, rowH)
        self:rect(lx, ly, colW, rowH, hover and C.btnHover or C.btn)
        self:miniScene(lx + 4, ly + 4, rowH * 2 - 8, rowH - 8, look.swatch, look.id)
        self:text(fit(T("SLook_" .. look.id), F.body, colW - rowH * 2 - 12), lx + rowH * 2 + 4, ly + 8, C.text, F.body)
        if sel then self:frame(lx, ly, colW, rowH, C.mint, 1, 2) else self:frame(lx, ly, colW, rowH, C.line2, 1) end
        self:hit(lx, ly, colW, rowH, CookieSlicerWindow.onShaderLook, look.id)
    end
    y = y + math.ceil(#CS.SHADER_LOOKS / 2) * (rowH + 6) + gap
    local look = CS.shaderLook(cur)
    if look.off then
        y = self:para(T("SNatural"), cx, y, cw, C.dim, F.body) + gap
    else
        for _, prm in ipairs(CS.SH_PARAMS) do y = self:slider(cx, y, cw, prm, cur) end
        y = y + 6
    end
    -- what it costs, measured
    local ms = tonumber(CS.pc.shader_ms)
    if ms and tonumber(CS.pc.shader_active) == 1 then
        local ok = ms <= CS.shaderBudget()
        y = self:para(T(ok and "Req_costOk" or "Req_costHigh", string.format("%.2f", ms), string.format("%.1f", CS.shaderBudget())),
            cx, y, cw, ok and C.mint or C.warn, F.small) + 4
    end
    y = self:para(T("CmpHint"), cx, y, cw, C.dim, F.small)
    -- the labels on the game, at the line
    local sw = getCore():getScreenWidth()
    if CS.shaderSplit and CS.shaderSplit > 0 then
        local lx = math.floor(CS.shaderSplit * sw) - self.x
        local b, a = T("Before"), T("After")
        local bw1, bw2 = tw(b, F.title) + 28, tw(a, F.title) + 28
        local th = fh(F.title) + 10
        self:rect(lx - bw1 - 12, 24, bw1, th, C.nav, 0.85)
        self:text(b, lx - bw1 + 2, 29, C.text, F.title)
        self:rect(lx + 12, 24, bw2, th, C.nav, 0.85)
        self:frame(lx + 12, 24, bw2, th, C.mint, 1)
        self:text(a, lx + 26, 29, C.mint, F.title)
    end
end

-- ---------------------------------------------------------------- version page

function CookieSlicerWindow:drawVersion(x, y0, w)
    local F, p, gap = self.F, self.pad, self.gap
    self:card(x, y0, w, self.lastH.version or 300)
    local cx, cw = x + p, w - 2 * p
    local y = self:heading("Version Slicer", nil, cx, y0 + p)
    local labelW = math.floor(cw * 0.3)
    local vx, vw = cx + labelW + gap, cw - labelW - gap
    local function row(label, value, color, note)
        self:rect(cx, y, cw, 1, C.track)
        y = y + gap
        self:text(fit(label, F.body, labelW), cx, y, C.dim, F.body)
        -- long values break at " | "
        local line = ""
        for part in string.gmatch(value .. " | ", "(.-) | ") do
            local try = line == "" and part or (line .. "  |  " .. part)
            if line ~= "" and tw(try, F.body) > vw then
                self:text(line, vx, y, color or C.text, F.body)
                y = y + fh(F.body) + 2
                line = part
            else
                line = try
            end
        end
        self:text(fit(line, F.body, vw), vx, y, color or C.text, F.body)
        y = y + fh(F.body) + 2
        if note then
            self:text(fit(note, F.small, vw), vx, y, C.dim, F.small)
            y = y + fh(F.small) + 2
        end
        y = y + gap - 2
    end
    local pc = CS.pc
    row(T("Ver_mod"), "v" .. CS.VERSION, C.mint, T("Ver_modNote"))
    if pc.fresh and pc.helper then
        if verLess(pc.helper, CS.HELPER_LATEST) then
            row(T("Ver_helper"), T("Ver_helperOld", tostring(pc.helper), CS.HELPER_LATEST), C.warn)
        else
            row(T("Ver_helper"), T("Ver_helperOn", tostring(pc.helper)), C.mint)
        end
    elseif pc.present then
        row(T("Ver_helper"), T("Ver_helperStopped"), C.warn)
    else
        row(T("Ver_helper"), T("Ver_helperNone"), C.dim)
    end
    local max, nxt = tonumber(pc.heap_max_mb), tonumber(pc.heap_next_mb)
    if pc.fresh and max then
        row(T("Ver_heap"), nxt and T("Ver_heapNext", gb(max), gb(nxt)) or T("Ver_heapV", gb(max)))
    else
        row(T("Ver_heap"), "--", C.dim)
    end
    row(T("Ver_key"), T("Ver_keyV", keyName()))
    row(T("Ver_setup"), T("Ver_setupV"))
    row(T("Ver_file"), "Zomboid/Lua/CookieSlicer_client.txt")
    self:rect(cx, y, cw, 1, C.track)
    y = y + p
    self.lastH.version = y - y0
    return y
end

-- ---------------------------------------------------------------- menu (left)

function CookieSlicerWindow:drawNav(x, y0, w, h)
    local F = self.F
    self:rect(x, y0, w, h, C.nav)
    self:frame(x, y0, w, h, C.line)
    local y = y0 + 12
    self:text("MENU", x + 14, y, C.faint, F.small)
    y = y + fh(F.small) + 8
    local look = CS.lookById and CS.lookById(CS.settings.look) or { id = "natural" }
    local b = tonumber(CS.settings.bright) or 0
    local helperOld = CS.pc.fresh and CS.pc.helper and verLess(CS.pc.helper, CS.HELPER_LATEST)
    local items = {
        { id = "perf", title = T("Nav_perf"), sub = T("NavSub_perf", T("P_" .. CS.tuneCurrentPreset())), sc = C.soft },
        { id = "shader", title = "Shader", sc = CS.shaderActive() and C.mint or C.dim,
          sub = CS.shaderActive() and T("NavSub_shaderOn", T("SLook_" .. CS.shaderLookId()))
                or T("NavSub_shader", T("Look_" .. look.id), (b > 0 and "+" or "") .. tostring(b)) },
        { id = "version", title = "Version Slicer", sub = helperOld and T("NavSub_versionUpdate") or T("NavSub_version", CS.VERSION), sc = helperOld and C.warn or C.mint },
    }
    local ih = fh(F.title) + fh(F.small) + 26
    for _, it in ipairs(items) do
        local ix, iw = x + 10, w - 20
        local sel = self.page == it.id
        local hover = self:mouseIn(ix, y, iw, ih)
        if sel then
            self:rect(ix, y, iw, ih, C.mint, 0.10)
            self:frame(ix, y, iw, ih, C.mint, 1, 2)
        elseif hover then
            self:rect(ix, y, iw, ih, C.btnHover)
        end
        self:rect(ix + 14, y + 11 + math.floor((fh(F.title) - 10) / 2), 10, 10, sel and C.mint or C.faint)
        self:text(fit(it.title, F.title, iw - 50), ix + 34, y + 11, C.text, F.title)
        self:text(fit(it.sub, F.small, iw - 44), ix + 34, y + 13 + fh(F.title), it.sc, F.small)
        self:hit(ix, y, iw, ih, CookieSlicerWindow.onPage, it.id)
        y = y + ih + 8
    end
    -- bottom: which key closes it
    local ky = y0 + h - 14 - fh(F.small) * 2 - 10
    self:rect(x + 10, ky - 10, w - 20, 1, C.line)
    local k = keyName()
    local kw = math.max(56, tw(k, F.small) + 16)
    self:frame(x + 16, ky - 1, kw, fh(F.small) + 2, C.line2, 1)
    self:textC(k, x + 16 + kw / 2, ky, C.text, F.small)
    self:text(fit(T("NavKeyClose"), F.small, w - kw - 40), x + 16 + kw + 10, ky, C.soft, F.small)
    self:text(fit(T("NavClick"), F.small, w - 32), x + 16, ky + fh(F.small) + 10, C.dim, F.small)
    return y
end

-- ---------------------------------------------------------------- explanations

local function levelWord(level)
    return T(level == "good" and "Good" or (level == "ok" and "Ok" or "Heavy"))
end

local function yoursText(self, id)
    local pc, f = CS.pc, CS.fps
    local playing = getPlayer() ~= nil and f.n > 0
    if id == "fps" then
        if not playing then return T("Y_fps_menu") end
        local q = f.avg >= 45 and T("Q_good") or (f.avg >= 25 and T("Q_ok") or T("Q_heavy"))
        local s = T("Y_fps", tostring(round(f.avg)), q)
        if f.min < f.avg * 0.65 then s = s .. T("Y_fps_spiky", tostring(round(f.min))) end
        return s
    elseif id == "state" then
        local key = "Y_state_" .. (self.tip or "fine")
        local s = T(key)
        if s == "UI_CookieSlicer_" .. key then s = T("Y_state_other") end
        return s
    end
    if not pc.fresh then return T("Y_noHelper") end
    if id == "ram" then
        local used = tonumber(pc.heap_live_mb)
        if not used or used == 0 then used = tonumber(pc.heap_used_mb) end
        local max = tonumber(pc.heap_max_mb)
        if not used or not max or max <= 0 then return "--" end
        local pct = round(used * 100 / max)
        return T("Y_ram", tostring(pct), T(pct < 70 and "Y_q_enough" or (pct <= 85 and "Y_q_tight" or "Y_q_full")))
    elseif id == "pcram" then
        local free = tonumber(pc.ram_free_mb)
        if not free then return "--" end
        return T(free >= 1500 and "Y_pcram_ok" or "Y_pcram_low", gb(free))
    elseif id == "cpu" then
        local cpu = tonumber(pc.cpu_total)
        if not cpu then return "--" end
        return T(cpu <= 90 and "Y_cpu_ok" or "Y_cpu_full", tostring(cpu))
    elseif id == "main" then
        local main = tonumber(pc.main_thread)
        if not main then return "--" end
        return T(main < 70 and "Y_main_ok" or (main < 90 and "Y_main_busy" or "Y_main_full"), tostring(main))
    end
    return ""
end

function CookieSlicerWindow:drawTip(t)
    local F = self.F
    local title = T("TipT_" .. t.id, levelWord((CS.verdict())))
    local lines = {}
    for line in string.gmatch(T("TipB_" .. t.id) .. "\n", "(.-)\n") do lines[#lines + 1] = line end
    local yl = T("Yours") .. " "
    local yours = yoursText(self, t.id)
    local w = tw(title, F.body)
    for _, l in ipairs(lines) do w = math.max(w, tw(l, F.small)) end
    w = math.max(w, tw(yl, F.small) + tw(yours, F.small))
    w = math.min(w + 32, self.width - 16)
    local lh = fh(F.small) + 2
    local h = 12 + fh(F.body) + 6 + #lines * lh + 8 + 1 + 8 + fh(F.small) + 12
    local x = t.x
    if x + w > self.width - 8 then x = self.width - 8 - w end
    if x < 8 then x = 8 end
    local y = t.y + t.h + 8
    if y + h > self.height - 8 then y = t.y - h - 8 end
    self:rect(x, y, w, h, C.nav)
    self:frame(x, y, w, h, C.mint, 1)
    local yy = y + 12
    self:text(title, x + 16, yy, C.mint, F.body)
    yy = yy + fh(F.body) + 6
    for _, l in ipairs(lines) do
        self:text(l, x + 16, yy, C.soft, F.small)
        yy = yy + lh
    end
    yy = yy + 8
    self:rect(x + 16, yy, w - 32, 1, C.line)
    yy = yy + 8
    self:text(yl, x + 16, yy, C.mint, F.small)
    self:text(fit(yours, F.small, w - 32 - tw(yl, F.small)), x + 16 + tw(yl, F.small), yy, C.text, F.small)
end

-- ---------------------------------------------------------------- frame

function CookieSlicerWindow:render()
    ISPanel.render(self)
    self.hits, self.tips = {}, {}
    if self.compare then
        self:drawCompare()
        return
    end
    local F, pad, gap, W = self.F, self.pad, self.gap, self.width
    -- header
    local hh = self.headH
    self:rect(0, 0, W, hh, C.head)
    self:rect(0, hh, W, 2, C.mint)
    local ty = math.floor((hh - fh(F.title)) / 2)
    self:rect(pad, ty + 3, 8, fh(F.title) - 6, C.mint)
    self:text("COOKIE SLICER", pad + 20, ty, C.mint, F.title)
    local sy = ty + fh(F.title) - fh(F.small) - 2
    self:text(T("Sub"), pad + 20 + tw("COOKIE SLICER", F.title) + 16, sy, C.dim, F.small)
    local cl = T("Close", keyName())
    local bw, bh = tw(cl, F.body) + 36, fh(F.body) + 12
    self:button(W - pad - bw, math.floor((hh - bh) / 2), bw, bh, cl, F.body, CookieSlicerWindow.onClose, nil, "ghost")
    self:textR("v" .. CS.VERSION, W - pad - bw - 16, sy, C.faint, F.small)

    -- body
    local top = hh + 2 + pad
    local x1 = pad + self.navW + gap
    local bottom
    if self.page == "shader" then
        bottom = self:drawShader(x1, top, self.colW * 2 + gap)
    elseif self.page == "version" then
        bottom = self:drawVersion(x1, top, self.colW * 2 + gap)
    else
        local b1 = self:drawLive(x1, top, self.colW)
        local b2 = self:drawTune(x1 + self.colW + gap, top, self.colW)
        bottom = math.max(b1, b2)
    end
    local navMin = 20 + fh(F.small) + 3 * (fh(F.title) + fh(F.small) + 34) + 2 * fh(F.small) + 40
    bottom = math.max(bottom, top + navMin)
    -- same window size on every page (the tallest one); cards fill it
    if self.minH then bottom = math.max(bottom, self.minH - pad) end
    if not self.dry then
        if self.page == "perf" then
            self.lastH.live, self.lastH.tune = bottom - top, bottom - top
        elseif self.page == "shader" then
            self.lastH.shreq, self.lastH.shlooks, self.lastH.shbasic = bottom - top, bottom - top, bottom - top
        else
            self.lastH[self.page] = bottom - top
        end
    end
    self:drawNav(pad, top, self.navW, bottom - top)

    -- the explanation under the mouse
    if not self.dry then
        local mx, my = self:getMouseX(), self:getMouseY()
        for _, t in ipairs(self.tips) do
            if mx >= t.x and mx < t.x + t.w and my >= t.y and my < t.y + t.h then
                self:drawTip(t)
                break
            end
        end
    end

    -- grow / shrink to what is shown; stay on screen
    local need = bottom + pad
    if math.abs(need - self.height) > 1 then
        self:setHeight(need)
        local sh = getCore():getScreenHeight()
        if self.y + need > sh then self:setY(math.max(0, sh - need)) end
    end
end

-- ---------------------------------------------------------------- clicks

function CookieSlicerWindow:onClose()
    if self.compare then CS.shaderSetSplit(-1) end
    self:setVisible(false)
    self:removeFromUIManager()
    CookieSlicerWindow.instance = nil
end

function CookieSlicerWindow:onPage(id)
    self.page = id
    CS.settings.page = id
    CS.saveSettings()
end

function CookieSlicerWindow:onPreset(id)
    local n, restart = CS.tunePreset(id)
    self.tuneMsg = restart and T("TuneRestart") or nil
end

function CookieSlicerWindow:onToggle(id)
    local changed, restart = CS.tuneToggle(id)
    if restart then self.tuneMsg = T("TuneRestart") end
end

function CookieSlicerWindow:onLook(id)
    CS.settings.look = id
    CS.saveSettings()
end

function CookieSlicerWindow:onBright(d)
    local b = (tonumber(CS.settings.bright) or 0) + d
    CS.settings.bright = clamp(b, CS.BRIGHT_MIN, CS.BRIGHT_MAX)
    CS.saveSettings()
end

function CookieSlicerWindow:onReset()
    CS.settings.look = "natural"
    CS.settings.bright = 0
    CS.saveSettings()
end

function CookieSlicerWindow:onShaderLook(id)
    CS.shaderSet("look", id)
end

function CookieSlicerWindow:onShaderOn()
    CS.shaderSet("on", CS.shaderOn() and "0" or "1")
end

function CookieSlicerWindow:onShaderQ(q)
    CS.shaderSet("q", q)
    self.recMsg = nil
end

function CookieSlicerWindow:onRecommend()
    local q, why = CS.shaderRecommend()
    self.recMsg = T("SRecDone", T("SQ_" .. tostring(q)), T(why))
end

function CookieSlicerWindow:onParam(a)
    local id = CS.shaderLookId()
    CS.shaderSetParam(id, a.id, CS.shaderParam(id, a.id) + a.d)
end

function CookieSlicerWindow:onParamBar(a, mx)
    local prm = paramById(a.id)
    if not prm then return end
    local t = clamp(((mx or a.x) - a.x) / math.max(1, a.w), 0, 1)
    CS.shaderSetParam(CS.shaderLookId(), a.id, prm.min + t * (prm.max - prm.min))
    self.dragBar = a
    self:setCapture(true)
end

function CookieSlicerWindow:onResetLook()
    CS.shaderResetLook(CS.shaderLookId())
end

function CookieSlicerWindow:onCompare()
    self:setCompare(not self.compare)
end

-- compare: the window moves to the left edge (full height), the game on the right shows
-- the line: left of it as the game draws it, right of it with the look
function CookieSlicerWindow:setCompare(on)
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    if on then
        if not getPlayer() or self.compare then return end
        self.normalGeom = { x = self.x, y = self.y, w = self.width, h = self.height }
        self.compare = true
        local w = math.max(480, math.min(math.floor(sw * 0.34), 720))
        self:setX(0)
        self:setY(0)
        self:setWidth(w)
        self:setHeight(sh)
        CS.shaderSetSplit((w + (sw - w) / 2) / sw)
    else
        if not self.compare then return end
        self.compare = false
        local g = self.normalGeom
        if g then
            self:setX(g.x)
            self:setY(g.y)
            self:setWidth(g.w)
            self:setHeight(g.h)
        end
        CS.shaderSetSplit(-1)
    end
end

function CookieSlicerWindow:onFix(mb)
    if mb and mb > 0 then
        CS.requestHeap(mb)
        self.fixDone = T("RamQueued", gb(mb))
    end
end

function CookieSlicerWindow:onMouseDown(x, y)
    self:bringToTop()
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
            h.fn(self, h.arg, x, y)
            return true
        end
    end
    if y < self.headH and not self.compare then
        self.dragHead = true
        self:setCapture(true)
    end
    return true
end

function CookieSlicerWindow:onMouseMove(dx, dy)
    if self.dragBar then
        self:onParamBar(self.dragBar, self:getMouseX())
    elseif self.dragHead and not self.compare then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end

function CookieSlicerWindow:onMouseMoveOutside(dx, dy) self:onMouseMove(dx, dy) end

function CookieSlicerWindow:onMouseUp(x, y)
    self.dragHead = false
    self.dragBar = nil
    self:setCapture(false)
    return true
end

function CookieSlicerWindow:onMouseUpOutside(x, y)
    self.dragHead = false
    self.dragBar = nil
    self:setCapture(false)
end

-- big fonts when the tallest page fits the screen, the smaller set otherwise
function CookieSlicerWindow.toggle()
    local w = CookieSlicerWindow.instance
    if w then
        w:onClose()
        return
    end
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    local function make(fonts)
        local o = CookieSlicerWindow:new(0, 0, fonts, sw)
        o:initialise()
        o.dry = true
        local page = o.page
        local tallest = 0
        for _, p in ipairs({ "perf", "shader", "version" }) do
            o.page = p
            o:render()
            o:render()
            tallest = math.max(tallest, o.height)
        end
        o.page = page
        o.dry = false
        o.minH = tallest
        o:setHeight(tallest)
        return o
    end
    w = make(FONTS_BIG)
    if w.height > sh - 40 or w.colW < 420 then w = make(FONTS_SMALL) end
    w:setX(math.floor((sw - w.width) / 2))
    w:setY(math.max(0, math.floor((sh - w.height) / 2)))
    w:addToUIManager()
    w:bringToTop()
    CookieSlicerWindow.instance = w
end

-- ================================================================ button

CookieSlicerButton = ISPanel:derive("CookieSlicerButton")

local BUTTON_FONT = UIFont.Medium

function CookieSlicerButton:new(x, y)
    local label = T("Button")
    local o = ISPanel:new(x, y, tw(label, BUTTON_FONT) + 34, fh(BUTTON_FONT) + 14)
    setmetatable(o, self)
    self.__index = self
    o.label = label
    o.backgroundColor = { r = C.head[1], g = C.head[2], b = C.head[3], a = 0.92 }
    o.borderColor = { r = C.mint[1], g = C.mint[2], b = C.mint[3], a = 0.9 }
    o.down, o.moved = false, 0
    return o
end

function CookieSlicerButton:render()
    ISPanel.render(self)
    local level = CS.verdict()
    local c = levelColor(level)
    self:drawRect(10, math.floor(self.height / 2) - 4, 8, 8, 1, c[1], c[2], c[3])
    self:drawText(self.label, 24, 7, C.text[1], C.text[2], C.text[3], 1, BUTTON_FONT)
end

function CookieSlicerButton:onMouseDown(x, y)
    self.down, self.moved = true, 0
    self:setCapture(true)
    return true
end

function CookieSlicerButton:onMouseMove(dx, dy)
    if not self.down then return end
    self.moved = self.moved + math.abs(dx) + math.abs(dy)
    if self.moved > 4 then
        local core = getCore()
        local nx = math.max(0, math.min(core:getScreenWidth() - self.width, self.x + dx))
        local ny = math.max(0, math.min(core:getScreenHeight() - self.height, self.y + dy))
        self:setX(nx)
        self:setY(ny)
    end
end

function CookieSlicerButton:onMouseMoveOutside(dx, dy) self:onMouseMove(dx, dy) end

function CookieSlicerButton:finish()
    if not self.down then return end
    self.down = false
    self:setCapture(false)
    if self.moved > 4 then
        CS.settings.bx, CS.settings.by = math.floor(self.x), math.floor(self.y)
        CS.saveSettings()
    else
        CookieSlicerWindow.toggle()
    end
end

function CookieSlicerButton:onMouseUp(x, y) self:finish(); return true end
function CookieSlicerButton:onMouseUpOutside(x, y) self:finish() end

-- ================================================================ main menu button

-- shown only on the main menu itself (not in its sub-screens, not in game)
local function onMainMenu()
    local core = getCore()
    if CookieSlicerButton.instance then
        CookieSlicerButton.instance:removeFromUIManager()
        CookieSlicerButton.instance = nil
    end
    local btn = CookieSlicerButton:new(0, 0)
    local bx, by = tonumber(CS.settings.bx) or -1, tonumber(CS.settings.by) or -1
    if bx < 0 or by < 0 or bx > core:getScreenWidth() - btn.width or by > core:getScreenHeight() - btn.height then
        bx, by = core:getScreenWidth() - btn.width - 24, 24 -- top right; drag it anywhere
    end
    btn:setX(bx)
    btn:setY(by)
    btn:initialise()
    btn:addToUIManager()
    CookieSlicerButton.instance = btn
    if (tonumber(CS.settings.seen) or 0) < 1 then
        CS.settings.seen = 1
        CS.saveSettings()
        CookieSlicerWindow.toggle()
    end
end

local function mainMenuShowing()
    local ms = MainScreen and MainScreen.instance
    if not ms or ms.inGame or getPlayer() then return false end
    if not ms:isVisible() then return false end
    return ms.bottomPanel == nil or ms.bottomPanel:isVisible()
end

local function onFETick()
    local btn = CookieSlicerButton.instance
    if not btn then return end
    local show = mainMenuShowing() or CookieSlicerWindow.instance ~= nil
    if btn:isVisible() ~= show then btn:setVisible(show) end
end

-- ================================================================ in game: key

-- Options > Mods > Cookie Slicer: the key (F8; F1-F7, F9-F11 are taken by the game / mods)
if PZAPI and PZAPI.ModOptions then
    local opts = PZAPI.ModOptions:create("CookieSlicer", "Cookie Slicer")
    CS.keyOption = opts:addKeyBind("openKey", T("Key"), Keyboard.KEY_F8)
end

function CS.openKey()
    local k = CS.keyOption and CS.keyOption:getValue()
    if type(k) ~= "number" then k = Keyboard.KEY_F8 end
    return k
end

local function onKeyPressed(key)
    if not getPlayer() or key ~= CS.openKey() or key == 0 then return end
    CookieSlicerWindow.toggle()
end

local function onGameStart()
    if CookieSlicerWindow.instance then CookieSlicerWindow.instance:onClose() end
    if CookieSlicerButton.instance then
        CookieSlicerButton.instance:removeFromUIManager()
        CookieSlicerButton.instance = nil
    end
    -- once: tell the player which key opens it
    if (tonumber(CS.settings.keyhint) or 0) < 1 then
        CS.settings.keyhint = 1
        CS.saveSettings()
        pcall(function() getPlayer():setHaloNote(T("KeyHint", keyName()), 79, 245, 200, 900) end)
    end
end

Events.OnMainMenuEnter.Add(onMainMenu)
Events.OnFETick.Add(onFETick)
Events.OnKeyPressed.Add(onKeyPressed)
Events.OnGameStart.Add(onGameStart)
