-- Cookie Mastery - skill tree window in the Cookie Mission look:
-- navy see-through glass, LED header, blue rims, cyan highlights, rounded glass tiles joined by thin threads.
-- Tier colours read like Cookie Mission's rarity colours: Lv1 mint, Lv3 cyan, Lv5 azure, Lv10 violet.
-- Left: profile + mentor network. Middle: the tree (three sides, a root and three branches of four nodes).
-- Right: details of the selected node, laid out like a Cookie Mission card.
if isServer() and not isClient() then return end

require "CMM_Client"
require "CM_UI_Kit"

CMMT = CMMT or {}
CMMT.SEP = " - "     -- replaced by the translated middle dot once the game is up (Lua stays ASCII)
local C = CMUI.C
local S = CMUI.S
local T = CMMC.txt

-- tier -> colour and number of rank pips
CMMT.TC = { [1] = C.good, [3] = C.t1, [5] = C.t2, [10] = C.t3 }
CMMT.PIPS = { [1] = 1, [3] = 2, [5] = 3, [10] = 4 }
function CMMT.tierCol(t) return CMMT.TC[t] or C.accent end

-- ===================================================================== art
local texCache = {}
function CMMT.tex(name)
    local t = texCache[name]
    if t == nil then
        t = getTexture("media/textures/CookieMastery/" .. name .. ".png") or false
        texCache[name] = t
    end
    return t or nil
end

function CMMT.img(win, name, x, y, w, h, c, a)
    local t = CMMT.tex(name)
    if not t then return false end
    c = c or C.white
    win:drawTextureScaled(t, x, y, w, h, a or 1, c[1], c[2], c[3])
    return true
end

-- straight line between two points; dotted fallback when this build has no drawLine
function CMMT.line(win, x1, y1, x2, y2, th, c, a)
    if CMMT.lineOk ~= false and win.drawLine then
        local ok = pcall(function() win:drawLine(CMMT.tex("cmm_px"), x1, y1, x2, y2, th, a, c[1], c[2], c[3]) end)
        if ok then CMMT.lineOk = true; return end
        CMMT.lineOk = false
    end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local step = math.max(2, th + 1)
    local n = math.floor(len / step)
    local s = math.max(1, math.floor(th + 0.5))
    for i = 0, n do
        local t = i / math.max(1, n)
        win:drawRect(x1 + dx * t - s / 2, y1 + dy * t - s / 2, s, s, a, c[1], c[2], c[3])
    end
end

-- a thread between two nodes: a soft curve (quadratic bezier bowed sideways by `bend` of its length)
-- drawn as a network link (see CMMT.wire); lit threads also get a small spark running along them
-- r1 / r2: radius of the nodes at each end, the thread starts and stops at their edge
function CMMT.thread(win, x1, y1, x2, y2, bend, th, c, a, lit, phase, r1, r2, march)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local mx, my = (x1 + x2) / 2 - dy * bend, (y1 + y2) / 2 + dx * bend
    local t0 = math.min(0.45, (r1 or 0) / len)
    local t1 = math.max(0.55, 1 - (r2 or 0) / len)
    local n = math.max(5, math.min(12, math.floor(len / 14)))
    local pts = {}
    for i = 0, n do
        local t = t0 + (t1 - t0) * i / n
        local u = 1 - t
        pts[#pts + 1] = { u * u * x1 + 2 * u * t * mx + t * t * x2, u * u * y1 + 2 * u * t * my + t * t * y2 }
    end
    CMMT.wire(win, pts, th, c, a, lit, march)
    if lit then
        local t = CMMC.ms() / 1800 + (phase or 0)
        t = t0 + (t1 - t0) * (t - math.floor(t))
        local u = 1 - t
        local bx = u * u * x1 + 2 * u * t * mx + t * t * x2
        local by = u * u * y1 + 2 * u * t * my + t * t * y2
        CMUI.glow(win, bx, by, th * 5, th * 5, c, 0.9)
        CMUI.rect(win, bx - th, by - th, th * 2, th * 2, C.white, 0.9)
    end
end

local function fmod(v, m) return v - math.floor(v / m) * m end

-- dashed polyline; `phase` slides the pattern (negative = flows from the first point to the last)
function CMMT.dashes(win, pts, th, c, a, dash, gap, phase)
    local period = dash + gap
    local acc = fmod(phase or 0, period)
    for i = 2, #pts do
        local x1, y1, x2, y2 = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local s = 0
        while s < len do
            local on = acc < dash
            local e = math.min(len, s + (on and (dash - acc) or (period - acc)))
            if on then CMMT.line(win, x1 + dx * s / len, y1 + dy * s / len, x1 + dx * e / len, y1 + dy * e / len, th, c, a) end
            acc = acc + (e - s)
            if acc >= period then acc = acc - period end
            s = e
        end
    end
end

-- a network link: dashed while closed, solid with a halo once lit; a dot sits on each end
-- march = the dashes flow toward the far end (a path you can still walk)
function CMMT.wire(win, pts, th, c, a, lit, march)
    if #pts < 2 then return end
    if lit then
        for i = 2, #pts do
            CMMT.line(win, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], th + S(3), c, a * 0.18)
        end
        for i = 2, #pts do
            CMMT.line(win, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], th, c, a)
        end
    else
        CMMT.dashes(win, pts, th, c, a, S(5), S(4), march and -(CMMC.ms() / 70) or 0)
    end
    local ds = math.max(4, S(lit and 6 or 5))
    local dc = lit and C.white or C.text
    local da = lit and 1 or math.min(0.9, a + 0.15)
    local ends = { pts[1], pts[#pts] }
    for i = 1, 2 do
        local p = ends[i]
        if lit then CMUI.glow(win, p[1], p[2], ds * 1.6, ds * 1.6, c, 0.6) end
        CMMT.img(win, "cmm_dot", p[1] - ds / 2, p[2] - ds / 2, ds, ds, dc, da)
    end
end

-- straight link between two round-ish nodes, trimmed at their edges
function CMMT.link(win, x1, y1, x2, y2, r1, r2, th, c, a, lit, march)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= r1 + r2 + 2 then return end
    local ux, uy = dx / len, dy / len
    CMMT.wire(win, { { x1 + ux * r1, y1 + uy * r1 }, { x2 - ux * r2, y2 - uy * r2 } }, th, c, a, lit, march)
end

-- Cookie Mission glass panel with a pip section header; returns the content top
function CMMT.panel(win, x, y, w, h, label, rim, rimA)
    CMUI.glass(win, x, y, w, h, { tint = C.panel, a = 0.42, rad = 12, rim = rim or C.line, rimA = rimA or 0.40 })
    local hy = y + S(12)
    CMUI.section(win, x + S(14), hy, w - S(28), label, C.gold)
    return hy + CMUI.fh(UIFont.Small) + S(14)
end

-- Cookie Mission button: style = primary / good / ghost / flat / danger / purple
function CMMT.button(win, x, y, w, h, label, fn, style, opts)
    opts = opts or {}
    if not opts.rad then opts.rad = 8 end
    CMUI.btn(win, x, y, w, h, label, fn, style or "ghost", opts)
    return w
end

local function bw(label) return CMUI.tw(UIFont.Small, label) + S(24) end

function CMMT.icon(bid, tier)
    if tier == 3 then return "cmm_mentor" end
    return "cmm_" .. tostring(bid) .. "_" .. tostring(tier)
end

CMMT.SHARED = {
    { id = "mentor", tier = 3, icon = "cmm_mentor" },
    { id = "appr", tier = 3, icon = "cmm_appr" },
    { id = "book", tier = 5, icon = "cmm_book" },
    { id = "legacy", tier = 10, icon = "cmm_legacy" },
}

-- rank pips like the Cookie Mission cards; returns the width used
local function pips(win, x, y, n, c, ps, total)
    local w = 0
    for i = 1, (total or n) do
        local on = i <= n
        CMUI.icon(win, "cm_pip", x + (i - 1) * (ps + S(3)), y, ps, on and c or C.panel3, on and 1 or 0.9)
        w = i * (ps + S(3))
    end
    return w
end

-- ===================================================================== node state
local function me() return CMMC.me end

local function lvNow()
    local m = me()
    return (CMM.level(m and m.pts or 0))
end

local function two(n)
    n = math.floor(CM.num(n, 0))
    if n < 10 then return "0" .. n end
    return tostring(n)
end

-- relation of a node to this player: "on" unlocked / "next" your branch, not yet / "can" a branch you may
-- pick / "other"; second value = not built in this version yet
local function stateOf(bid, tier)
    local m = me()
    local soon = not CMM.nodeLive(bid, tier)
    if m and m.br == bid then
        if lvNow() >= tier then return "on", soon end
        return "next", soon
    end
    if m and not m.br and CMMT.elig and CMMT.elig[bid] then return "can", soon end
    return "other", soon
end

-- short status word + its colour
local function code(st, soon)
    if soon then return T("IGUI_CMM_Code_dev"), C.purple end
    if st == "on" or st == "root" then return T("IGUI_CMM_Code_online"), C.good end
    if st == "next" then return T("IGUI_CMM_Code_locked"), C.dim end
    if st == "can" then return T("IGUI_CMM_Code_available"), C.gold end
    return T("IGUI_CMM_Code_standby"), C.faint
end

-- ===================================================================== window
CMMT.Win = CMUI.Window:derive("CMMT_Win")
local W = CMMT.Win

function W:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = T("IGUI_CMM_TreeTitle")
    o.subtitle = T("IGUI_CMM_TreeTag") .. "  v" .. CMM.VERSION
    o.titleIcon = "cm_icon"
    o.sel = nil           -- { kind = "node", bid, tier } | { kind = "shared", id } | { kind = "side", sid } | { kind = "hub" }
    o.confirm = nil
    o.view = CMMT.lastView or "wheel"   -- wheel | rows | hof
    return o
end

local function armed(self, what)
    local c = self.confirm
    return c and c.what == what and CMMC.ms() < c.untilMs
end
local function arm(self, what) self.confirm = { what = what, untilMs = CMMC.ms() + 4000 } end

function W:defaultSel()
    local m = me()
    if m and m.br then
        local lv = lvNow()
        for i = 1, #CMM.TIERS do
            if lv < CMM.TIERS[i] then return { kind = "node", bid = m.br, tier = CMM.TIERS[i] } end
        end
        return { kind = "node", bid = m.br, tier = 10 }
    end
    if CMMT.elig then
        for _, side in ipairs(CMM.SIDES) do
            for _, bid in ipairs(side.branches) do
                if CMMT.elig[bid] then return { kind = "node", bid = bid, tier = 1 } end
            end
        end
    end
    return { kind = "hub" }
end

local function isSel(self, kind, a, b)
    local s = self.sel
    if not s or s.kind ~= kind then return false end
    if kind == "node" then return s.bid == a and s.tier == b end
    if kind == "shared" then return s.id == a end
    return s.sid == a
end

-- one node: a rounded glass tile, rim in the tier colour once it matters
-- opts: tc = tier / side colour, cap = double rim (Lv10 and roots), dot = "pick me" pip, still = no hit area
function W:node(cx, cy, size, glyph, st, selected, tip, onClick, soon, opts)
    opts = opts or {}
    local x, y = cx - size / 2, cy - size / 2
    local over = false
    if not opts.still then over = self:hit(x, y, size, size, onClick, tip) end
    local tc = opts.tc or C.accent
    local rad = math.max(6, math.floor(size * 0.22))
    local tint, fa, rim, ra, gc, ga, glow = C.panel, 0.50, C.line, 0.32, C.faint, 0.95, nil
    if st == "on" then
        tint, fa, rim, ra, gc, ga, glow = C.accentD, 0.85, tc, 1, C.white, 1, tc
    elseif st == "next" then
        tint, fa, rim, ra, gc, ga = C.panel, 0.60, tc, 0.60, C.dim, 1
    elseif st == "can" then
        tint, fa, rim, ra, gc, ga = C.panel2, 0.70, C.accent, 0.90, C.text, 1
    elseif st == "root" then
        tint, fa, rim, ra, gc, ga, glow = C.panel2, 0.80, tc, 0.95, C.white, 1, tc
    elseif st == "rootDim" then
        tint, fa, rim, ra, gc, ga = C.panel, 0.60, tc, 0.45, C.dim, 0.95
    end
    if soon then ga = ga * 0.50 end
    if over then ra = math.min(1, ra + 0.30); ga = math.min(1, ga + 0.20); fa = fa + 0.10 end
    if glow or selected or over then
        CMUI.glow(self, cx, cy, size * 0.95, size * 0.95, glow or C.gold, glow and 0.50 or 0.28)
    end
    CMUI.glass(self, x, y, size, size, { tint = tint, a = fa, rad = rad, rim = rim, rimA = ra, shine = 0.8 })
    if opts.cap then
        local i = math.max(3, S(3))
        CMUI.rborder(self, x + i, y + i, size - i * 2, size - i * 2, rim, ra * 0.55, math.max(4, rad - i))
    end
    local gs = size * (opts.cap and 0.50 or 0.56)
    CMMT.img(self, glyph, cx - gs / 2, cy - gs / 2, gs, gs, gc, ga)
    if st == "next" and not soon then
        local ls = math.max(9, size * 0.26)
        CMMT.img(self, "cmm_lock", x + size - ls * 0.85, y + size - ls * 0.85, ls, ls, C.dim, 0.95)
    end
    if opts.dot then
        local ds = math.max(6, size * 0.16)
        local p = 0.65 + 0.35 * math.sin(CMMC.ms() / 260)
        CMUI.glow(self, cx, y - ds * 0.6, ds * 1.6, ds * 1.6, C.gold, 0.5 * p)
        CMUI.icon(self, "cm_pip", cx - ds / 2, y - ds * 1.1, ds, C.gold, p)
    end
    if selected then CMUI.brackets(self, x, y, size, size, C.gold, 1, math.max(S(7), size * 0.24), 2) end
    return over
end

-- ===================================================================== shared drawing for the views
-- spoke angle of every branch (degrees, 0 = right, clockwise): each side owns 120 degrees around its centre,
-- its three branches sit 36 degrees apart so the sides read as groups
CMMT.ANGLE = {}
CMMT.SIDE_ANGLE = {}
for si = 1, #CMM.SIDES do
    local side = CMM.SIDES[si]
    local c = -90 + (si - 1) * 120
    CMMT.SIDE_ANGLE[side.id] = c
    for bi = 1, #side.branches do CMMT.ANGLE[side.branches[bi]] = c + (bi - 2) * 36 end
end
CMMT.RING = { [1] = 0.36, [3] = 0.57, [5] = 0.78, [10] = 1.0 }

local function polar(cx, cy, deg, r)
    local a = math.rad(deg)
    return cx + math.cos(a) * r, cy + math.sin(a) * r
end

function CMMT.ring(win, cx, cy, r, c, a)
    CMMT.img(win, "cmm_ring", cx - r, cy - r, r * 2, r * 2, c, a)
end

-- arc as a short polyline
function CMMT.arc(win, cx, cy, r, d0, d1, th, c, a)
    local n = math.max(6, math.floor(math.abs(d1 - d0) / 4))
    local px, py = polar(cx, cy, d0, r)
    for i = 1, n do
        local x, y = polar(cx, cy, d0 + (d1 - d0) * i / n, r)
        CMMT.line(win, px, py, x, y, th, c, a)
        px, py = x, y
    end
end

-- small rounded label chip; returns its width
local function chip(win, cx, cy, label, col, fill, font)
    font = font or UIFont.Small
    local fh = CMUI.fh(font)
    local w = CMUI.tw(font, label) + S(14)
    local h = fh + S(4)
    CMUI.rbox(win, cx - w / 2, cy - h / 2, w, h, fill or C.dark, 0.92, math.floor(h / 2))
    CMUI.rborder(win, cx - w / 2, cy - h / 2, w, h, col, 0.75, math.floor(h / 2))
    CMUI.textC(win, label, cx, cy - fh / 2, col, 1, font)
    return w
end
CMMT.chip = chip

-- the skills of a branch with this character's level: { { name, level }, ... }
function CMMT.perkLevels(bid)
    local out = {}
    local b = CMM.BRANCH[bid]
    if not b then return out end
    local p = CMMC.player()
    for i = 1, #b.perks do
        local perk = CMM.perkOf(b.perks[i])
        local name = perk and CM.call(perk, "getName") or nil
        if name == nil or name == "" then name = b.perks[i] end
        out[#out + 1] = { tostring(name), CMM.perkLevel(p, perk) }
    end
    return out
end

-- one line "Carpentry 10  Masonry 3 ..." (level 10 in green), cut at w
local function perkLine(win, bid, x, y, w)
    local list = CMMT.perkLevels(bid)
    local cx = x
    for i = 1, #list do
        local s = list[i][1] .. " " .. tostring(list[i][2])
        local tw = CMUI.tw(UIFont.Small, s)
        if cx + tw > x + w then
            if cx < x + w - S(10) then CMUI.text(win, "...", cx, y, C.faint, 1, UIFont.Small) end
            return
        end
        CMUI.text(win, s, cx, y, list[i][2] >= 10 and C.good or C.faint, 1, UIFont.Small)
        cx = cx + tw + S(10)
    end
end

-- wrapping chips with the same content; returns the height used
local function perkChips(win, bid, x, y, w)
    local list = CMMT.perkLevels(bid)
    local fh = CMUI.fh(UIFont.Small)
    local h = fh + S(6)
    local cx, cy = x, y
    for i = 1, #list do
        local ok = list[i][2] >= 10
        local s = list[i][1] .. "  " .. tostring(list[i][2])
        local cw = CMUI.tw(UIFont.Small, s) + S(16)
        if cx > x and cx + cw > x + w then cx = x; cy = cy + h + S(5) end
        local col = ok and C.good or C.line
        CMUI.rbox(win, cx, cy, cw, h, ok and C.good or C.panel2, ok and 0.16 or 0.55, math.floor(h / 2))
        CMUI.rborder(win, cx, cy, cw, h, col, ok and 0.8 or 0.45, math.floor(h / 2))
        CMUI.text(win, s, cx + S(8), cy + S(3), ok and C.good or C.dim, 1, UIFont.Small)
        cx = cx + cw + S(6)
    end
    return cy + h - y
end

-- view switch in a panel header: wheel | rows | hall of fame; returns its width
CMMT.VIEWS = { "wheel", "rows", "hof" }
function W:viewToggle(rx, y)
    local fh = CMUI.fh(UIFont.Small)
    local h = fh + S(6)
    local ws, total = {}, S(4)
    for i = 1, #CMMT.VIEWS do
        ws[i] = CMUI.tw(UIFont.Small, T("IGUI_CMM_View_" .. CMMT.VIEWS[i])) + S(20)
        total = total + ws[i]
    end
    local x = rx - total
    CMUI.rbox(self, x, y, total, h, C.dark, 0.92, math.floor(h / 2))
    CMUI.rborder(self, x, y, total, h, C.line, 0.55, math.floor(h / 2))
    local bx = x + S(2)
    for i = 1, #CMMT.VIEWS do
        local v = CMMT.VIEWS[i]
        local on = (self.view or "wheel") == v
        local over = self:hit(bx, y, ws[i], h, function()
            self.view = v
            CMMT.lastView = v
            self.confirm = nil
        end)
        if on then
            CMUI.rbox(self, bx, y + S(2), ws[i], h - S(4), C.accent, 0.85, math.floor((h - S(4)) / 2))
        elseif over then
            CMUI.rbox(self, bx, y + S(2), ws[i], h - S(4), C.panel3, 0.9, math.floor((h - S(4)) / 2))
        end
        CMUI.textC(self, T("IGUI_CMM_View_" .. v), bx + ws[i] / 2, y + S(3), on and C.white or C.dim, 1, UIFont.Small)
        bx = bx + ws[i]
    end
    return total
end

-- middle panel chrome shared by the views: glass + section header + the view switch
function W:viewPanel(px, py, pw, ph, label)
    local top = CMMT.panel(self, px, py, pw, ph, label)
    self:viewToggle(px + pw - S(12), py + S(8))
    return top
end

local function nodeClick(self, bid, t)
    return function() self.sel = { kind = "node", bid = bid, tier = t }; self.confirm = nil end
end

local function nodeTip(bid, t, soon)
    local tip = CMMC.brName(bid) .. CMMT.SEP .. T("IGUI_CMM_TierLv", t)
    if soon then tip = tip .. CMMT.SEP .. T("IGUI_CMM_Soon") end
    return tip
end

-- colour, alpha and thickness of the link that ends at tier t of a branch
local function linkStyle(bid, t, lv)
    local m = me()
    local chosen = m and m.br == bid
    local can = m and not m.br and CMMT.elig and CMMT.elig[bid]
    local lit = chosen and lv >= t
    if lit then return CMMT.tierCol(t), 0.95, math.max(1.5, S(1.6)), true, false end
    if chosen then return CMMT.tierCol(t), 0.70, math.max(1, S(1)), false, true end
    if can then return C.accent, 0.75, math.max(1, S(1)), false, true end
    return C.line, 0.38, math.max(1, S(1)), false, false
end

-- ===================================================================== view A: the wheel
-- you sit in the middle; each branch is a spoke, its tiers sit on four rings (Lv 1 inside, Lv 10 outside)
function W:drawWheel(px, py, pw, ph)
    local m = me()
    local lv = lvNow()
    local top = self:viewPanel(px, py, pw, ph, T("IGUI_CMM_H_Tree"))
    local fh = CMUI.fh(UIFont.Small)
    local ax, ay, aw, ah = px + S(10), top, pw - S(20), py + ph - top - S(10)
    local cx, cy = ax + aw / 2, ay + ah / 2 + S(4)
    local R10 = math.floor(math.min(aw / 2 - S(58), ah / 2 - fh * 2 - S(10)))
    if R10 < S(60) then R10 = S(60) end
    local ns = math.max(S(20), math.min(S(40), R10 * 0.135))
    local hs = ns * 1.16
    local hub = math.max(S(34), math.min(S(70), R10 * 0.27))
    local myBid = m and m.br or nil
    local mySide = myBid and CMM.sideOf(myBid) or nil
    -- side tint + glowing rim arc per side
    for si = 1, #CMM.SIDES do
        local side = CMM.SIDES[si]
        local c = CMMT.SIDE_ANGLE[side.id]
        local mine = mySide and mySide.id == side.id
        local gx, gy = polar(cx, cy, c, R10 * 0.58)
        CMUI.glow(self, gx, gy, R10 * 0.95, R10 * 0.95, side.color, mine and 0.13 or 0.07)
        local rr = R10 + ns * 0.5 + S(12)
        CMMT.arc(self, cx, cy, rr, c - 56, c + 56, S(5), side.color, mine and 0.22 or 0.12)
        CMMT.arc(self, cx, cy, rr, c - 56, c + 56, math.max(1.5, S(2)), side.color, mine and 0.95 or 0.55)
    end
    -- tier rings
    for _, t in ipairs(CMM.TIERS) do
        local reached = myBid and lv >= t
        CMMT.ring(self, cx, cy, R10 * CMMT.RING[t], CMMT.tierCol(t), reached and 0.38 or 0.14)
    end
    -- spokes (links) first, then nodes on top
    for bid, deg in pairs(CMMT.ANGLE) do
        local px0, py0 = polar(cx, cy, deg, hub * 0.5 + S(4))
        local prevR = 0
        for ti = 1, #CMM.TIERS do
            local t = CMM.TIERS[ti]
            local x, y = polar(cx, cy, deg, R10 * CMMT.RING[t])
            local c, a, th, lit, march = linkStyle(bid, t, lv)
            local r = (t == 10 and hs or ns) * 0.5 + S(2)
            CMMT.link(self, px0, py0, x, y, prevR, r, th, c, a, lit, march)
            px0, py0, prevR = x, y, r
        end
    end
    for bid, deg in pairs(CMMT.ANGLE) do
        for _, t in ipairs(CMM.TIERS) do
            local x, y = polar(cx, cy, deg, R10 * CMMT.RING[t])
            local st, soon = stateOf(bid, t)
            self:node(x, y, t == 10 and hs or ns, CMMT.icon(bid, t), st, isSel(self, "node", bid, t), nodeTip(bid, t, soon),
                nodeClick(self, bid, t), soon, { tc = CMMT.tierCol(t), cap = t == 10, dot = st == "can" and t == 1 })
        end
    end
    -- tier chips in the gap between the first two sides
    local gapDeg = (CMMT.SIDE_ANGLE[CMM.SIDES[1].id] + CMMT.SIDE_ANGLE[CMM.SIDES[2].id]) / 2
    for _, t in ipairs(CMM.TIERS) do
        local x, y = polar(cx, cy, gapDeg, R10 * CMMT.RING[t])
        chip(self, x, y, "Lv " .. t, CMMT.tierCol(t))
    end
    -- side names outside the rim (click = describe the side)
    for si = 1, #CMM.SIDES do
        local side = CMM.SIDES[si]
        local deg = CMMT.SIDE_ANGLE[side.id]
        local x, y = polar(cx, cy, deg, R10 + ns * 0.5 + S(30))
        local name = CMMC.sideName(side.id)
        local tw = CMUI.tw(UIFont.Small, name)
        y = y - fh / 2
        local over = self:hit(x - tw / 2 - S(4), y, tw + S(8), fh, function() self.sel = { kind = "side", sid = side.id }; self.confirm = nil end,
            T("IGUI_CMM_SideTag_" .. side.id))
        CMUI.textC(self, name, x, y, side.color, (over or isSel(self, "side", side.id)) and 1 or 0.85, UIFont.Small)
    end
    -- names only where they matter: your branch, branches you can pick, the selected one (others: hover)
    local sel = self.sel
    for bid, deg in pairs(CMMT.ANGLE) do
        local can = m and not m.br and CMMT.elig and CMMT.elig[bid]
        local show = bid == myBid or can or (sel and sel.kind == "node" and sel.bid == bid)
        if show then
            local x, y = polar(cx, cy, deg, R10)
            local s = math.sin(math.rad(deg))
            local ly = y + (s > -0.5 and (hs * 0.5 + fh * 0.5 + S(8)) or -(hs * 0.5 + fh * 0.5 + S(8)))
            local name = CMMC.brName(bid)
            local w = CMUI.tw(UIFont.Small, name) + S(14)
            x = math.max(ax + w / 2, math.min(ax + aw - w / 2, x))
            chip(self, x, ly, name, bid == myBid and C.gold or C.accent)
        end
    end
    -- the hub: you
    local hubSt = myBid and "root" or ((CMMT.elig and CM.any(CMMT.elig)) and "root" or "rootDim")
    self:node(cx, cy, hub, mySide and ("cmm_side_" .. mySide.id) or "cmm_root", hubSt, isSel(self, "hub"),
        T("IGUI_CMM_HubTitle"), function() self.sel = { kind = "hub" }; self.confirm = nil end, false,
        { tc = C.gold, cap = true })
    local label = myBid and ("Lv " .. lv) or T("IGUI_CMM_HubPick")
    CMUI.textC(self, label, cx, cy + hub * 0.5 + S(5), C.gold, 1, UIFont.Small)
end

-- ===================================================================== view B: rows
-- one row per branch, Lv 1 to Lv 10 from left to right, with the skills that count and your levels
function W:drawRows(px, py, pw, ph)
    local m = me()
    local lv = lvNow()
    local top = self:viewPanel(px, py, pw, ph, T("IGUI_CMM_H_Tree"))
    local fh = CMUI.fh(UIFont.Small)
    local ax, aw = px + S(14), pw - S(28)
    local lw = math.floor(aw * 0.42)
    local c0, c1 = ax + lw + S(24), ax + aw - S(22)
    local colX = {}
    for i = 1, #CMM.TIERS do colX[CMM.TIERS[i]] = c0 + (c1 - c0) * (i - 1) / (#CMM.TIERS - 1) end
    -- column heads
    CMUI.text(self, T("IGUI_CMM_RowsHead"), ax, top, C.dim, 1, UIFont.Small)
    for _, t in ipairs(CMM.TIERS) do
        CMUI.textC(self, "Lv " .. t, colX[t], top, CMMT.tierCol(t), 1, UIFont.Small)
    end
    local fy0 = top + fh + S(8)
    local fh2 = py + ph - fy0 - S(10)
    for _, t in ipairs(CMM.TIERS) do CMUI.rect(self, colX[t], fy0, 1, fh2, CMMT.tierCol(t), 0.10) end
    local rowH = math.max(fh * 2 + S(16), S(44))
    local ns = math.min(S(32), rowH * 0.66)
    self:form("cmmRows", ax - S(6), fy0, aw + S(12), fh2, function(yy)
        for si = 1, #CMM.SIDES do
            local side = CMM.SIDES[si]
            CMUI.text(self, CMMC.sideName(side.id), ax, yy, side.color, 1, UIFont.Small)
            CMUI.rect(self, ax, yy + fh + S(3), aw, 1, side.color, 0.35)
            yy = yy + fh + S(10)
            for bi = 1, #side.branches do
                local bid = side.branches[bi]
                local mine = m and m.br == bid
                local can = m and not m.br and CMMT.elig and CMMT.elig[bid]
                local ry = yy + rowH / 2
                if mine then
                    CMUI.rbox(self, ax - S(4), yy, aw + S(8), rowH, C.accentD, 0.45, 8)
                    CMUI.rborder(self, ax - S(4), yy, aw + S(8), rowH, C.gold, 0.55, 8)
                elseif can then
                    CMUI.rborder(self, ax - S(4), yy, aw + S(8), rowH, C.accent, 0.45, 8)
                end
                local ny = yy + (rowH - fh * 2 - S(4)) / 2
                CMUI.text(self, CMUI.fit(CMMC.brName(bid), UIFont.Small, lw - S(6)), ax + S(4), ny, mine and C.gold or (can and C.white or C.text), 1, UIFont.Small)
                perkLine(self, bid, ax + S(4), ny + fh + S(4), lw - S(6))
                local prevX, prevR = nil, 0
                for _, t in ipairs(CMM.TIERS) do
                    local size = t == 10 and ns * 1.12 or ns
                    if prevX then
                        local c, a, th, lit, march = linkStyle(bid, t, lv)
                        CMMT.link(self, prevX, ry, colX[t], ry, prevR, size * 0.5 + S(2), th, c, a, lit, march)
                    end
                    prevX, prevR = colX[t], size * 0.5 + S(2)
                end
                for _, t in ipairs(CMM.TIERS) do
                    local st, soon = stateOf(bid, t)
                    self:node(colX[t], ry, t == 10 and ns * 1.12 or ns, CMMT.icon(bid, t), st, isSel(self, "node", bid, t),
                        nodeTip(bid, t, soon), nodeClick(self, bid, t), soon, { tc = CMMT.tierCol(t), cap = t == 10 })
                end
                yy = yy + rowH + S(6)
            end
            yy = yy + S(6)
        end
    end)
end

-- ===================================================================== view C: Hall of Fame (public)
local function daysAgo(b, t)
    local d = math.floor(math.max(0, CM.num(b and b.now, 0) - CM.num(t, 0)) / 86400)
    if d < 1 then return T("IGUI_CMM_Today") end
    return T("IGUI_CMM_DaysAgo", d)
end

function CMMT.wantBoard(force)
    local t = CMMC.ms()
    if force or not CMMT.boardReq or t - CMMT.boardReq > 30000 or t < CMMT.boardReq then
        CMMT.boardReq = t
        CMMC.send("board", {})
    end
end

-- radial bars: one per branch at its wheel angle, length = share of the server's mastery points
function W:hofChart(x, y, w, h, b)
    local fh = CMUI.fh(UIFont.Small)
    local cx, cy = x + w / 2, y + h / 2 - fh / 2
    local Rm = math.max(S(40), math.min(w, h - fh * 2) / 2 - S(24))
    local r0 = Rm * 0.30
    CMMT.ring(self, cx, cy, Rm, C.line, 0.30)
    CMMT.ring(self, cx, cy, (r0 + Rm) / 2, C.line, 0.14)
    local maxv, best = 0, nil
    for bid in pairs(CMMT.ANGLE) do
        local v = CM.num(b.power and b.power[bid], 0)
        if v > maxv then maxv, best = v, bid end
    end
    local th = math.max(S(5), math.min(S(16), Rm * 0.12))
    for bid, deg in pairs(CMMT.ANGLE) do
        local side = CMM.sideOf(bid)
        local col = side and side.color or C.accent
        local v = CM.num(b.power and b.power[bid], 0)
        local x0, y0 = polar(cx, cy, deg, r0 + S(3))
        local len = r0 + S(3) + S(3)
        if maxv > 0 and v > 0 then len = r0 + S(6) + (Rm - r0 - S(6)) * math.sqrt(v / maxv) end
        local x1, y1 = polar(cx, cy, deg, len)
        if v > 0 then
            CMMT.line(self, x0, y0, x1, y1, th * 1.9, col, 0.16)
            CMMT.line(self, x0, y0, x1, y1, th, col, bid == best and 0.95 or 0.75)
            local ds = th * 0.9
            CMMT.img(self, "cmm_dot", x1 - ds / 2, y1 - ds / 2, ds, ds, C.white, 0.9)
        else
            CMMT.line(self, x0, y0, x1, y1, th, C.line, 0.35)
        end
        local ix, iy = polar(cx, cy, deg, Rm + S(16))
        local is = S(18)
        self:hit(ix - is / 2, iy - is / 2, is, is, nil, CMMC.brName(bid) .. CMMT.SEP .. CMMC.num(v))
        CMMT.img(self, "cmm_" .. bid .. "_10", ix - is / 2, iy - is / 2, is, is, col, v > 0 and 1 or 0.45)
    end
    -- centre: how many masters
    local hr = r0 - S(4)
    CMUI.glass(self, cx - hr, cy - hr, hr * 2, hr * 2, { tint = C.dark, a = 0.92, rad = math.floor(hr), rim = C.gold, rimA = 0.6 })
    local FT = UIFont.Large
    CMUI.textC(self, tostring(CM.num(b.n, 0)), cx, cy - CMUI.fh(FT) / 2 - fh / 3, C.white, 1, FT)
    CMUI.textC(self, T("IGUI_CMM_HofMasters"), cx, cy + CMUI.fh(FT) / 2 - fh / 2, C.dim, 1, UIFont.Small)
    local lead = best and T("IGUI_CMM_HofLead", CMMC.brName(best)) or T("IGUI_CMM_HofNoOne")
    local lc = best and (CMM.sideOf(best) or {}).color or C.dim
    CMUI.textC(self, lead, cx, y + h - fh, lc or C.dim, 1, UIFont.Small)
end

function W:hofLive(x, y, w, h, b)
    local fh = CMUI.fh(UIFont.Small)
    if not b.live then
        CMUI.text(self, T("IGUI_CMM_HofLiveOff"), x, y + S(6), C.faint, 1, UIFont.Small)
        return
    end
    if #b.live == 0 then
        CMUI.text(self, T("IGUI_CMM_HofNoOne"), x, y + S(6), C.faint, 1, UIFont.Small)
        return
    end
    local rh = math.max(fh * 2 + S(12), math.min(S(56), (h - S(4) * 4) / 5))
    for i = 1, math.min(5, #b.live) do
        local e = b.live[i]
        local ry = y + (i - 1) * (rh + S(4))
        local side = CMM.sideOf(e.br)
        local col = side and side.color or C.accent
        CMUI.glass(self, x, ry, w, rh, { tint = C.panel2, a = 0.55, rad = 8, rim = i == 1 and C.gold or C.line, rimA = i == 1 and 0.7 or 0.35 })
        CMUI.textC(self, tostring(i), x + S(14), ry + (rh - CMUI.fh(UIFont.Medium)) / 2, i == 1 and C.gold or C.dim, 1, UIFont.Medium)
        local is = math.min(S(24), rh - S(16))
        CMMT.img(self, "cmm_" .. tostring(e.br) .. "_10", x + S(28), ry + (rh - is) / 2, is, is, col, 1)
        local tx = x + S(28) + is + S(10)
        local chipW = CMUI.tw(UIFont.Small, "Lv 10") + S(14)
        local tw = w - (tx - x) - chipW - S(14)
        CMUI.text(self, CMUI.fit(tostring(e.n or "?"), UIFont.Small, tw), tx, ry + rh / 2 - fh - S(1), C.white, 1, UIFont.Small)
        CMUI.text(self, CMUI.fit(CMMC.brName(e.br), UIFont.Small, tw), tx, ry + rh / 2 + S(1), col, 1, UIFont.Small)
        local lv = CM.num(e.lv, 0)
        local tc = lv >= 1 and CMMT.tierCol(CMM.tierOf(lv)) or C.dim
        chip(self, x + w - S(10) - chipW / 2, ry + rh / 2 - fh * 0.35, "Lv " .. lv, tc)
        CMUI.segbar(self, x + w - S(10) - chipW, ry + rh / 2 + fh * 0.45, chipW, S(3), CM.num(e.fr, 0), C.accent, 10)
    end
end

function W:hofWall(x, y, w, h, b)
    local fh = CMUI.fh(UIFont.Small)
    local list = b.hof or {}
    if #list == 0 then
        CMUI.textC(self, T("IGUI_CMM_HofEmpty"), x + w / 2, y + h / 2 - fh / 2, C.faint, 1, UIFont.Small)
        return
    end
    local gap = S(8)
    local minW = S(118)
    local n = math.max(1, math.floor((w + gap) / (minW + gap)))
    n = math.min(n, #list)
    local cw = (w - gap * (n - 1)) / n
    if cw > S(170) then cw = S(170) end
    for i = 1, n do
        local e = list[i]
        local lv = CM.num(e.lv, 0)
        local legacy = lv >= 10
        local side = CMM.sideOf(e.br)
        local col = side and side.color or C.accent
        local x0 = x + (i - 1) * (cw + gap)
        if legacy then CMUI.glow(self, x0 + cw / 2, y + h / 2, cw * 0.9, h * 0.7, C.t3, 0.20) end
        CMUI.glass(self, x0, y, cw, h, { tint = legacy and C.panel2 or C.panel, a = 0.70, rad = 10,
            rim = legacy and C.t3 or C.line, rimA = legacy and 0.9 or 0.40 })
        local yy = y + S(8)
        if i == 1 then
            CMUI.textC(self, T("IGUI_CMM_HofFirst"), x0 + cw / 2, yy, C.gold, 1, UIFont.Small)
        end
        yy = yy + fh + S(4)
        local rr = math.max(S(16), math.min(cw * 0.26, (h - fh * 5 - S(30)) / 2))
        local rcx, rcy = x0 + cw / 2, yy + rr
        CMUI.glow(self, rcx, rcy, rr * 1.6, rr * 1.6, col, 0.18)
        CMMT.ring(self, rcx, rcy, rr, col, 0.95)
        local is = rr * 1.05
        CMMT.img(self, "cmm_" .. tostring(e.br) .. "_10", rcx - is / 2, rcy - is / 2, is, is, col, 1)
        yy = rcy + rr + S(8)
        CMUI.textC(self, CMUI.fit(tostring(e.n or "?"), UIFont.Medium, cw - S(10)), x0 + cw / 2, yy, C.white, 1, UIFont.Medium)
        yy = yy + CMUI.fh(UIFont.Medium) + S(2)
        CMUI.textC(self, CMUI.fit(CMMC.brName(e.br), UIFont.Small, cw - S(10)), x0 + cw / 2, yy, col, 1, UIFont.Small)
        yy = yy + fh + S(2)
        local tc = lv >= 1 and CMMT.tierCol(CMM.tierOf(lv)) or C.dim
        local l3 = "Lv " .. lv
        if e.life then l3 = l3 .. CMMT.SEP .. T("IGUI_CMM_HofLife", e.life) end
        CMUI.textC(self, CMUI.fit(l3, UIFont.Small, cw - S(10)), x0 + cw / 2, yy, tc, 1, UIFont.Small)
        yy = yy + fh + S(2)
        local l4 = daysAgo(b, e.t)
        if legacy then l4 = T("IGUI_CMM_HofLegacy") .. CMMT.SEP .. l4 end
        CMUI.textC(self, CMUI.fit(l4, UIFont.Small, cw - S(10)), x0 + cw / 2, yy, legacy and C.t3 or C.faint, 1, UIFont.Small)
    end
end

function W:drawHof(px, py, pw, ph)
    local top = self:viewPanel(px, py, pw, ph, T("IGUI_CMM_Hof"))
    CMMT.wantBoard(false)
    local b = CMMC.board
    local fh = CMUI.fh(UIFont.Small)
    if not b then
        CMUI.textC(self, T("IGUI_CMM_Wait"), px + pw / 2, py + ph / 2, C.dim, 1, UIFont.Medium)
        return
    end
    local x, w = px + S(16), pw - S(32)
    local bottom = py + ph - S(14)
    local topH = math.floor((bottom - top) * 0.54)
    local chartW = math.floor(math.min(w * 0.46, topH * 1.25))
    -- top left: chart
    local sh = CMUI.section(self, x, top, chartW, T("IGUI_CMM_HofPower"), C.gold)
    CMUI.textR(self, T("IGUI_CMM_HofPowerSub"), x + chartW, top, C.faint, 1, UIFont.Small)
    self:hofChart(x, top + sh + S(4), chartW, topH - sh - S(4), b)
    -- top right: living top 5
    local lx = x + chartW + S(20)
    local lw = x + w - lx
    CMUI.section(self, lx, top, lw, T("IGUI_CMM_HofLive"), C.gold)
    CMUI.textR(self, T("IGUI_CMM_HofLiveSub"), lx + lw, top, C.faint, 1, UIFont.Small)
    self:hofLive(lx, top + sh + S(4), lw, topH - sh - S(4), b)
    -- bottom: the wall
    local wy = top + topH + S(10)
    CMUI.section(self, x, wy, w, T("IGUI_CMM_HofWall"), C.t3)
    local sub = T("IGUI_CMM_HofWallSub")
    CMUI.textR(self, sub, x + w, wy, C.faint, 1, UIFont.Small)
    self:hofWall(x, wy + sh + S(6), w, bottom - wy - sh - S(6), b)
end

-- ===================================================================== profile (left panel)
local function row(self, x, y, w, k, v, vc)
    CMUI.text(self, k, x, y, C.dim, 1, UIFont.Small)
    CMUI.textR(self, v, x + w, y, vc or C.text, 1, UIFont.Small)
    CMUI.rect(self, x, y + CMUI.fh(UIFont.Small) + S(3), w, 1, C.line, 0.14)
    return CMUI.fh(UIFont.Small) + S(8)
end

function W:drawProfile(px, py, pw, ph)
    local m = me()
    local top = CMMT.panel(self, px, py, pw, ph, T("IGUI_CMM_H_Profile"))
    local x, w = px + S(14), pw - S(28)
    local fh = CMUI.fh(UIFont.Small)
    self:form("cmmProfile", x, top, w, py + ph - top - S(10), function(yy)
        local lv, into, need = CMM.level(m and m.pts or 0)
        local has = m and m.br
        -- level tile, same as the character tab
        local FT = UIFont.Title or UIFont.Large
        local ts = math.max(S(58), CMUI.fh(FT) + fh + S(10))
        if has then CMUI.glow(self, x + ts / 2, yy + ts / 2, ts * 0.8, ts * 0.8, C.accent, 0.30) end
        CMUI.glass(self, x, yy, ts, ts, { tint = C.dark, a = 0.70, rad = 10, rim = has and C.gold or C.line, rimA = has and 0.8 or 0.5 })
        CMUI.textC(self, "Lv", x + ts / 2, yy + S(4), C.dim, 1, UIFont.Small)
        CMUI.textC(self, tostring(lv), x + ts / 2, yy + S(4) + fh - S(2), has and C.white or C.dim, 1, FT)
        local bx = x + ts + S(10)
        local bwid = x + w - bx
        if has then
            local side = CMM.sideOf(m.br)
            CMUI.text(self, CMUI.fit(CMMC.brName(m.br), UIFont.Medium, bwid), bx, yy + S(2), C.white, 1, UIFont.Medium)
            local sy = yy + S(2) + CMUI.fh(UIFont.Medium) + S(1)
            CMUI.text(self, CMMC.sideName(side and side.id or "craft"), bx, sy, side and side.color or C.dim, 1, UIFont.Small)
            local ps = math.max(6, math.floor(fh * 0.55))
            local n = 0
            for i = 1, #CMM.TIERS do if lv >= CMM.TIERS[i] then n = i end end
            pips(self, bx, sy + fh + S(5), n, CMMT.tierCol(CMM.tierOf(lv)), ps, #CMM.TIERS)
        else
            CMUI.text(self, T("IGUI_CMM_LvLabel"), bx, yy + S(4), C.dim, 1, UIFont.Small)
            CMUI.para(self, T("IGUI_CMM_NoBranchShort"), bx, yy + S(6) + fh, bwid, C.text, UIFont.Small, 2)
        end
        yy = yy + ts + S(12)
        local frac = lv >= 10 and 1 or into / math.max(1, need)
        CMUI.segbar(self, x + 2, yy, w - 4, S(6), frac, has and C.accent or C.faint, 20)
        yy = yy + S(6) + S(8)
        local prog = lv >= 10 and T("IGUI_CMM_Max") or T("IGUI_CMM_Next", CMMC.num(into), CMMC.num(need), lv + 1)
        yy = yy + CMUI.para(self, prog, x, yy, w, C.dim, UIFont.Small, 2) + S(8)
        if m then
            yy = yy + row(self, x, yy, w, T("IGUI_CMM_K_points"), CMMC.num(m.wal), C.gold)
            yy = yy + row(self, x, yy, w, T("IGUI_CMM_K_life"), tostring(m.life or 1))
            if not m.br then
                local banked = 0
                for _, v in pairs(m.pre or {}) do banked = banked + CM.num(v, 0) end
                yy = yy + row(self, x, yy, w, T("IGUI_CMM_K_banked"), CMMC.num(banked), C.text)
            end
        end
        -- mentor network: the four shared nodes
        yy = yy + S(10)
        yy = yy + CMUI.section(self, x, yy, w, T("IGUI_CMM_H_Net"), C.gold) + S(10)
        local cell = w / 2
        local ns = math.min(S(42), cell * 0.5)
        local cellH = ns + fh + S(32)
        local at, sts = {}, {}
        for i = 1, #CMMT.SHARED do
            local col = (i - 1) % 2
            local rowi = math.floor((i - 1) / 2)
            at[i] = { x + cell * col + cell / 2, yy + rowi * cellH + ns / 2 }
            sts[i] = "other"
            if m and m.br then sts[i] = lvNow() >= CMMT.SHARED[i].tier and "on" or "next" end
        end
        -- links of the network: across each row, and down each column (starting under the label)
        local LINKS = { { 1, 2 }, { 3, 4 }, { 1, 3 }, { 2, 4 } }
        for k = 1, #LINKS do
            local a1, b1 = LINKS[k][1], LINKS[k][2]
            local lit = sts[a1] == "on" and sts[b1] == "on"
            local down = at[b1][2] > at[a1][2]
            local c = lit and CMMT.tierCol(CMMT.SHARED[b1].tier) or (m and m.br and C.accent or C.line)
            CMMT.link(self, at[a1][1], at[a1][2], at[b1][1], at[b1][2], down and (ns / 2 + fh + S(9)) or ns / 2 + S(4),
                ns / 2 + S(4), math.max(1, S(1)), c, lit and 0.85 or 0.55, lit, false)
        end
        for i = 1, #CMMT.SHARED do
            local sh = CMMT.SHARED[i]
            local cx, cy = at[i][1], at[i][2]
            local st = sts[i]
            self:node(cx, cy, ns, sh.icon, st, isSel(self, "shared", sh.id), T("IGUI_CMM_SN_" .. sh.id),
                function() self.sel = { kind = "shared", id = sh.id }; self.confirm = nil end, false,
                { tc = CMMT.tierCol(sh.tier), cap = sh.tier == 10, dot = sh.id == "appr" and m and m.inv ~= nil })
            CMUI.textC(self, CMUI.fit(T("IGUI_CMM_SN_" .. sh.id), UIFont.Small, cell - S(6)), cx, cy + ns / 2 + S(5),
                st == "on" and C.text or C.dim, 1, UIFont.Small)
        end
        yy = yy + cellH * 2 + S(4)
        -- live links
        if m then
            local lines = {}
            if m.inv then lines[#lines + 1] = { T("IGUI_CMM_Invite", m.inv.from, CMMC.brName(m.inv.br)), C.gold } end
            if m.mentor then lines[#lines + 1] = { T("IGUI_CMM_MyMentor", m.mentor), C.text } end
            if m.appr then lines[#lines + 1] = { T("IGUI_CMM_MyAppr", m.appr), C.text } end
            if m.buff then
                local left = CM.num(m.buff.left, 0) - CMMC.age(CMMC.meAt)
                lines[#lines + 1] = { T("IGUI_CMM_Buff", m.buff.by, CMMC.brName(m.buff.br), CM.num(m.buff.pct, 0)) .. CMMT.SEP .. CMMC.dur(left), C.good }
            end
            local ps = math.max(6, math.floor(fh * 0.5))
            for i = 1, #lines do
                CMUI.icon(self, "cm_pip", x, yy + (fh - ps) / 2, ps, lines[i][2], 0.95)
                yy = yy + CMUI.para(self, lines[i][1], x + ps + S(6), yy, w - ps - S(6), lines[i][2], UIFont.Small, 2) + S(4)
            end
            if not m.br and type(m.pre) == "table" and CM.any(m.pre) then
                yy = yy + S(6)
                local keys = CM.sortedKeys(m.pre)
                for i = 1, #keys do
                    yy = yy + row(self, x, yy, w, CMMC.brName(keys[i]), CMMC.num(m.pre[keys[i]]), C.gold)
                end
            end
        end
    end)
end

-- ===================================================================== detail (right panel)
local function nearbyPlayers()
    local out = {}
    local p = CMMC.player()
    local list = getOnlinePlayers and getOnlinePlayers()
    if not p or not list then return out end
    for i = 0, list:size() - 1 do
        local o = list:get(i)
        if o and o ~= p then
            local ok, d = pcall(function() return CMM.dist(o, p:getX(), p:getY()) end)
            if ok and d <= 6 then
                local ok2, n = pcall(function() return o:getUsername() end)
                if ok2 and n then out[#out + 1] = tostring(n) end
            end
        end
        if #out >= 3 then break end
    end
    return out
end

-- glowing status dot + word, right aligned (same as the mission cards)
local function statusDot(self, rx, y, text, col)
    local fs = UIFont.Small
    local tw = CMUI.tw(fs, text)
    local d = math.max(5, math.floor(CMUI.fh(fs) / 3))
    local dx = rx - tw - d - S(6)
    local dy = y + (CMUI.fh(fs) - d) / 2
    CMUI.glow(self, dx + d / 2, dy + d / 2, d * 2, d * 2, col, 0.7)
    self:drawRect(dx, dy, d, d, 1, col[1], col[2], col[3])
    CMUI.text(self, text, rx - tw, y, col, 1, fs)
end

-- status strip: tinted glass with a pip, stronger when unlocked
local function statusBar(self, x, y, w, label, col, strong)
    local fh = CMUI.fh(UIFont.Small)
    local h = fh + S(12)
    CMUI.rbox(self, x, y, w, h, col, strong and 0.24 or 0.10, 8)
    CMUI.rborder(self, x, y, w, h, col, strong and 0.85 or 0.45, 8)
    local ps = math.max(6, math.floor(fh * 0.55))
    CMUI.icon(self, "cm_pip", x + S(10), y + (h - ps) / 2, ps, col, 1)
    CMUI.text(self, CMUI.fit(label, UIFont.Small, w - ps - S(26)), x + S(16) + ps, y + (h - fh) / 2, strong and C.white or col, 1, UIFont.Small)
    return h
end

function W:sharedActions(id, x, y, w)
    local m = me()
    if not m then return 0 end
    local fh = CMUI.fh(UIFont.Small)
    local bh = S(28)
    local yy = y
    local lv = lvNow()
    if id == "appr" then
        if m.inv then
            yy = yy + CMUI.para(self, T("IGUI_CMM_Invite", m.inv.from, CMMC.brName(m.inv.br)), x, yy, w, C.gold, UIFont.Small, 2) + S(4)
            local a = T("IGUI_CMM_Accept")
            CMMT.button(self, x, yy, bw(a), bh, a, function() CMMC.send("answer", { ok = true }) end, "good")
            local d = T("IGUI_CMM_Decline")
            CMMT.button(self, x + bw(a) + S(6), yy, bw(d), bh, d, function() CMMC.send("answer", { ok = false }) end, "ghost")
            yy = yy + bh + S(6)
        end
        if m.mentor then
            CMUI.text(self, T("IGUI_CMM_MyMentor", m.mentor), x, yy + (bh - fh) / 2, C.text, 1, UIFont.Small)
            local sure = armed(self, "leave")
            local lab = sure and T("IGUI_CMM_Sure") or T("IGUI_CMM_Leave")
            CMMT.button(self, x + w - bw(lab), yy, bw(lab), bh, lab, function()
                if armed(self, "leave") then self.confirm = nil; CMMC.send("leave", {}) else arm(self, "leave") end
            end, sure and "danger" or "ghost")
            yy = yy + bh + S(6)
        end
        if m.br and lv >= 3 then
            if m.appr then
                CMUI.text(self, T("IGUI_CMM_MyAppr", m.appr), x, yy + (bh - fh) / 2, C.text, 1, UIFont.Small)
                local sure = armed(self, "drop")
                local lab = sure and T("IGUI_CMM_Sure") or T("IGUI_CMM_Drop")
                CMMT.button(self, x + w - bw(lab), yy, bw(lab), bh, lab, function()
                    if armed(self, "drop") then self.confirm = nil; CMMC.send("leave", {}) else arm(self, "drop") end
                end, sure and "danger" or "ghost")
                yy = yy + bh + S(6)
            else
                local near = nearbyPlayers()
                if #near == 0 then
                    yy = yy + CMUI.para(self, T("IGUI_CMM_NoAppr"), x, yy, w, C.dim, UIFont.Small, 2) + S(4)
                else
                    CMUI.text(self, T("IGUI_CMM_TakeAppr"), x, yy, C.dim, 1, UIFont.Small)
                    yy = yy + fh + S(4)
                    local bx = x
                    for j = 1, #near do
                        local n = near[j]
                        local nw = math.min(S(110), bw(n))
                        if bx + nw > x + w then break end
                        CMMT.button(self, bx, yy, nw, bh, n, function() CMMC.send("invite", { name = n }) end, "primary")
                        bx = bx + nw + S(6)
                    end
                    yy = yy + bh + S(6)
                end
            end
        end
    elseif id == "book" then
        if m.br and lv >= 5 then
            local wait = CMM.sv("BookDays") * 86400
            local since = CM.num(m.now, 0) - CM.num(m.bookAt, 0) + CMMC.age(CMMC.meAt)
            if m.bookAt and since < wait then
                yy = yy + row(self, x, yy, w, T("IGUI_CMM_Book"), CMMC.dur(wait - since), C.dim)
            else
                CMMT.button(self, x, yy, w, S(30), T("IGUI_CMM_BookWrite"), function() CMMC.send("book", {}) end, "primary")
                yy = yy + S(36)
            end
        end
        if m.buff then
            local left = CM.num(m.buff.left, 0) - CMMC.age(CMMC.meAt)
            yy = yy + CMUI.para(self, T("IGUI_CMM_Buff", m.buff.by, CMMC.brName(m.buff.br), CM.num(m.buff.pct, 0)) .. CMMT.SEP .. CMMC.dur(left),
                x, yy, w, C.good, UIFont.Small, 2) + S(4)
        end
    elseif id == "legacy" then
        local hof = m.hof or {}
        if #hof > 0 then
            yy = yy + CMUI.section(self, x, yy, w, T("IGUI_CMM_Hof"), C.t3) + S(4)
            for i = 1, math.min(5, #hof) do
                local e = hof[i]
                yy = yy + row(self, x, yy, w, two(i) .. "  " .. tostring(e.n), CMMC.brName(e.br) .. " Lv " .. tostring(e.lv), i == 1 and C.gold or C.text)
            end
        end
    end
    return yy - y
end

-- the rules in three steps + which branches this character can pick right now
function W:howTo(x, y, w)
    local m = me()
    local fh = CMUI.fh(UIFont.Small)
    local yy = y
    for i = 1, 4 do
        local col = i == 4 and C.faint or C.text
        if i < 4 then
            local d = fh + S(4)
            CMUI.rbox(self, x, yy, d, d, C.accentD, 0.9, math.floor(d / 2))
            CMUI.rborder(self, x, yy, d, d, C.gold, 0.8, math.floor(d / 2))
            CMUI.textC(self, tostring(i), x + d / 2, yy + S(2), C.gold, 1, UIFont.Small)
        end
        yy = yy + CMUI.para(self, T("IGUI_CMM_How" .. i), x + fh + S(12), yy + S(2), w - fh - S(12), col, UIFont.Small, 4) + S(10)
    end
    if m and not m.br then
        yy = yy + S(4)
        CMUI.text(self, T("IGUI_CMM_CanNow"), x, yy, C.dim, 1, UIFont.Small)
        yy = yy + fh + S(6)
        local any = false
        for _, side in ipairs(CMM.SIDES) do
            for _, bid in ipairs(side.branches) do
                if CMMT.elig and CMMT.elig[bid] then
                    any = true
                    local cw = CMUI.tw(UIFont.Small, CMMC.brName(bid)) + S(14)
                    chip(self, x + cw / 2, yy + fh / 2 + S(2), CMMC.brName(bid), C.gold)
                    local hx = x
                    self:hit(hx, yy, cw, fh + S(4), function() self.sel = { kind = "node", bid = bid, tier = 1 }; self.confirm = nil end)
                    yy = yy + fh + S(10)
                end
            end
        end
        if not any then
            yy = yy + CMUI.para(self, T("IGUI_CMM_CanNone"), x, yy, w, C.faint, UIFont.Small, 3) + S(4)
        end
    end
    return yy - y
end

function W:drawDetail(px, py, pw, ph)
    local m = me()
    local sel = self.sel
    local fh = CMUI.fh(UIFont.Small)
    local title, sub, glyph, desc, perks = "", "", "cmm_root", "", nil
    local st, soon, bid, tier, tc, cap = nil, false, nil, nil, C.accent, false
    local subC = C.dim
    if sel.kind == "node" then
        bid, tier = sel.bid, sel.tier
        local side = CMM.sideOf(bid)
        title = CMMC.brName(bid)
        sub = CMMC.sideName(side and side.id or "craft") .. CMMT.SEP .. T("IGUI_CMM_SideTag_" .. (side and side.id or "craft"))
        subC = side and side.color or C.dim
        glyph = CMMT.icon(bid, tier)
        desc = T("IGUI_CMM_N_" .. bid .. "_" .. tier)
        if tier == 3 then desc = desc .. CMMT.SEP .. T("IGUI_CMM_N_all_3")
        elseif tier == 5 then desc = desc .. " " .. T("IGUI_CMM_N_all_5")
        elseif tier == 10 then desc = desc .. " " .. T("IGUI_CMM_N_all_10") end
        perks = bid
        st, soon = stateOf(bid, tier)
        tc, cap = CMMT.tierCol(tier), tier == 10
    elseif sel.kind == "shared" then
        local sh = nil
        for i = 1, #CMMT.SHARED do if CMMT.SHARED[i].id == sel.id then sh = CMMT.SHARED[i] end end
        title = T("IGUI_CMM_SN_" .. sel.id)
        sub = T("IGUI_CMM_H_Net")
        glyph = sh.icon
        desc = T("IGUI_CMM_SD_" .. sel.id)
        tier = sh.tier
        if m and m.br then st = lvNow() >= sh.tier and "on" or "next" else st = "other" end
        tc, cap = CMMT.tierCol(tier), tier == 10
    elseif sel.kind == "hub" then
        title = T("IGUI_CMM_HubTitle")
        sub = T("IGUI_CMM_HubSub")
        glyph = (m and m.br and CMM.sideOf(m.br)) and ("cmm_side_" .. CMM.sideOf(m.br).id) or "cmm_root"
        desc = ""
        st = "root"
        tc, cap = C.gold, true
    else
        local side = nil
        for i = 1, #CMM.SIDES do if CMM.SIDES[i].id == sel.sid then side = CMM.SIDES[i] end end
        title = CMMC.sideName(side.id)
        sub = T("IGUI_CMM_SideTag_" .. side.id)
        subC = side.color
        glyph = "cmm_side_" .. side.id
        local names = {}
        for i = 1, #side.branches do names[#names + 1] = CMMC.brName(side.branches[i]) end
        desc = T("IGUI_CMM_SideDesc", table.concat(names, CMMT.SEP))
        st = "root"
        tc, cap = side.color, true
    end
    local lit = st == "on" or st == "root"
    -- the panel takes the colour of what is selected, like a mission card
    local top = CMMT.panel(self, px, py, pw, ph, T("IGUI_CMM_H_Detail"), tc, lit and 0.75 or 0.45)
    CMUI.brackets(self, px, py, pw, ph, tc, lit and 0.9 or 0.5, S(14), 2)
    local x, w = px + S(14), pw - S(28)
    local cx = x + w / 2
    local yy = top
    -- top row: rank pips + "Lv 5" on the left, status dot on the right
    local cw, cc = code(st, soon)
    if tier then
        local ps = S(10)
        local pw2 = pips(self, x, yy + (fh - ps) / 2, CMMT.PIPS[tier] or 1, tc, ps)
        CMUI.text(self, T("IGUI_CMM_TierLv", tier), x + pw2 + S(4), yy, tc, 1, UIFont.Small)
    else
        CMUI.text(self, sub, x, yy, tc, 1, UIFont.Small)
    end
    if sel.kind == "node" or sel.kind == "shared" then statusDot(self, x + w, yy, cw, cc) end
    yy = yy + fh + S(16)
    -- big lit tile, name, side
    local is = math.min(S(80), ph * 0.15)
    CMUI.glow(self, cx, yy + is / 2, is * 1.25, is * 1.05, tc, lit and 0.45 or 0.22)
    self:node(cx, yy + is / 2, is, glyph, st, false, nil, nil, soon, { tc = tc, cap = cap, still = true })
    yy = yy + is + S(14)
    CMUI.textC(self, CMUI.fit(title, UIFont.Large, w), cx, yy, C.white, 1, UIFont.Large)
    yy = yy + CMUI.fh(UIFont.Large) + S(2)
    if tier then
        CMUI.textC(self, CMUI.fit(sub, UIFont.Small, w), cx, yy, subC, 1, UIFont.Small)
        yy = yy + fh + S(10)
    end
    -- how far along you are toward a node of your own branch
    if st == "next" and m and m.br and tier then
        local frac = CM.clamp(CM.num(m.pts, 0) / math.max(1, CMM.total(tier)), 0, 1)
        CMUI.segbar(self, x + S(10), yy, w - S(20), S(5), frac, tc, 15)
        yy = yy + S(5) + S(12)
    end
    yy = yy + S(2)
    -- the rest can scroll
    self:form("cmmDetail", x, yy, w, py + ph - yy - S(58), function(fy)
        if sel.kind == "hub" then
            fy = fy + self:howTo(x, fy, w) + S(6)
            return
        end
        fy = fy + CMUI.para(self, desc, x, fy, w, C.text, UIFont.Small, 6) + S(10)
        if sel.kind ~= "side" then
            if soon then
                fy = fy + statusBar(self, x, fy, w, T("IGUI_CMM_St_soon"), C.purple, false) + S(6)
            end
            if st == "on" and not soon then
                fy = fy + statusBar(self, x, fy, w, T("IGUI_CMM_St_on"), C.good, true) + S(6)
            elseif st == "next" and not soon then
                local need = math.max(0, CMM.total(tier) - CM.num(m and m.pts, 0))
                fy = fy + statusBar(self, x, fy, w, T("IGUI_CMM_St_locked", tier, CMMC.num(need)), tc, false) + S(6)
            elseif st == "can" then
                fy = fy + statusBar(self, x, fy, w, T("IGUI_CMM_St_canpick"), C.gold, false) + S(6)
            elseif st == "other" then
                local key = (m and m.br) and "IGUI_CMM_St_other" or "IGUI_CMM_St_need"
                if sel.kind == "shared" then key = "IGUI_CMM_St_pickfirst" end
                fy = fy + statusBar(self, x, fy, w, T(key), C.faint, false) + S(6)
            end
            fy = fy + S(4)
        end
        if perks then
            CMUI.text(self, CMUI.fit(T("IGUI_CMM_PerksHead"), UIFont.Small, w), x, fy, C.dim, 1, UIFont.Small)
            fy = fy + fh + S(6)
            fy = fy + perkChips(self, perks, x, fy, w) + S(10)
        end
        if sel.kind == "shared" then
            fy = fy + self:sharedActions(sel.id, x, fy, w) + S(6)
        end
    end)
    -- bottom: pick button or "your branch"
    local bh = S(36)
    local by = py + ph - bh - S(14)
    if bid and m and not m.br and CMMT.elig and CMMT.elig[bid] then
        local key = "pick" .. bid
        local sure = armed(self, key)
        local label = sure and T("IGUI_CMM_PickConfirm") or T("IGUI_CMM_Pick", CMMC.brName(bid))
        CMMT.button(self, x, by, w, bh, label, function()
            if armed(self, key) then self.confirm = nil; CMMC.send("pick", { br = bid }) else arm(self, key) end
        end, sure and "good" or "primary", { rad = 10 })
    elseif m and m.br then
        CMUI.hline(self, x, by + S(4), w, C.accent, 0.6)
        local ps = math.max(6, math.floor(fh * 0.55))
        local txt = T("IGUI_CMM_Owned", CMMC.brName(m.br), lvNow())
        local tw = CMUI.tw(UIFont.Small, txt) + ps + S(6)
        local tx = cx - tw / 2
        CMUI.icon(self, "cm_pip", tx, by + S(16) + (fh - ps) / 2, ps, C.gold, 1)
        CMUI.text(self, CMUI.fit(txt, UIFont.Small, w - ps - S(6)), tx + ps + S(6), by + S(16), C.gold, 1, UIFont.Small)
    end
end

-- a radio tuning dial along the bottom: 0..10 is the mastery scale, the needle is this character
function W:drawDial(x, y, w, h)
    local m = me()
    local fh = CMUI.fh(UIFont.Small)
    local x0, x1 = x + S(28), x + w - S(28)
    local by = y + S(3)
    CMUI.rect(self, x0 - S(14), by, (x1 - x0) + S(28), 1, C.line, 0.30)
    for i = 0, 50 do
        local tx = x0 + (x1 - x0) * i / 50
        local major = i % 5 == 0
        CMUI.rect(self, math.floor(tx), by + 1, 1, major and S(8) or S(4), C.accent, major and 0.55 or 0.25)
        if major then
            CMUI.textC(self, tostring(i / 5), tx, by + S(9), C.faint, 1, UIFont.Small)
        end
    end
    CMUI.text(self, "Lv", x, by + S(9), C.dim, 1, UIFont.Small)
    local lv, into, need = CMM.level(m and m.pts or 0)
    local v = lv + (lv >= 10 and 0 or into / math.max(1, need))
    local nx = x0 + (x1 - x0) * math.max(0, math.min(10, v)) / 10
    local has = m and m.br
    local NEEDLE = { 1.0, 0.58, 0.26 }
    CMUI.glow(self, nx, by + S(5), S(14), S(26), NEEDLE, has and 0.55 or 0.2)
    CMUI.rect(self, nx - 1, by - S(5), 2, S(17), NEEDLE, has and 0.95 or 0.4)
end

function W:drawBody()
    local m = me()
    -- darker body behind the panels (radio-set feel, no pattern)
    CMUI.rbox(self, S(3), self.headerH, self.width - S(6), self.height - self.headerH - S(3), C.dark, 0.45, 12)
    CMMT.elig = CMMC.eligible()
    self.subtitle = T("IGUI_CMM_TreeTag") .. "  v" .. CMM.VERSION .. ((m and m.test) and ("  " .. T("IGUI_CMM_TestTag")) or "")
    if not self.sel then self.sel = self:defaultSel() end
    if not m then
        CMUI.textC(self, T("IGUI_CMM_Wait"), self.width / 2, self.height / 2, C.dim, 1, UIFont.Medium)
        return
    end
    local pad = S(14)
    local top = self.headerH + S(12)
    local dialH = CMUI.fh(UIFont.Small) + S(16)
    local bodyH = self.height - top - pad - dialH - S(4)
    local leftW = math.floor(math.min(S(232), self.width * 0.20))
    local rightW = math.floor(math.min(S(296), self.width * 0.25))
    local midW = self.width - pad * 4 - leftW - rightW
    self:drawProfile(pad, top, leftW, bodyH)
    local view = self.view or "wheel"
    if view == "hof" then
        self:drawHof(pad * 2 + leftW, top, midW + pad + rightW, bodyH)
    else
        if view == "rows" then self:drawRows(pad * 2 + leftW, top, midW, bodyH)
        else self:drawWheel(pad * 2 + leftW, top, midW, bodyH) end
        self:drawDetail(pad * 3 + leftW + midW, top, rightW, bodyH)
    end
    self:drawDial(pad, self.height - pad - dialH, self.width - pad * 2, dialH)
end

function W:close()
    CMUI.Window.close(self)
    CMMT.win = nil
end

-- ===================================================================== open / toggle
function CMMT.open(sel)
    CMUI.k = CMUI.fontScale()
    if CMMT.win then
        if sel then CMMT.win.sel = sel end
        CMMT.win:bringToTop()
        return CMMT.win
    end
    local w, h = CMUI.size(1240, 700)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = W:new((sw - w) / 2, (sh - h) / 2, w, h)
    win.sel = sel
    win:initialise()
    win:addToUIManager()
    CMMT.win = win
    if not CMMC.me then CMMC.send("hello", {}) end
    return win
end

function CMMT.toggle()
    if CMMT.win then CMMT.win:close(); return end
    CMMT.open()
end

-- a tile in the Cookie Dock tray (wraps CMDock.grouped without editing Cookie Mission)
local function hookDock()
    if not (CMDock and type(CMDock.grouped) == "function") or CMDock.__cmmTile then return end
    CMDock.__cmmTile = true
    local orig = CMDock.grouped
    CMDock.grouped = function(...)
        local out = orig(...)
        if type(out) ~= "table" then return out end
        table.insert(out, math.min(2, #out + 1), {
            id = "cmm", name = T("IGUI_CMM_Tab"), tex = CMMT.tex("cmm_root"),
            click = function() CMMT.toggle() end,
            badge = function()
                local m = CMMC.me
                if not m then return nil end
                if m.inv then return "!" end
                if not m.br and CM.any(m.pre or {}) then return "!" end
                return nil
            end,
        })
        return out
    end
end
CMMT.hookDock = hookDock

Events.OnGameStart.Add(function()
    pcall(hookDock)
    local ok, sep = pcall(T, "IGUI_CMM_Sep")
    if ok and sep and sep ~= "IGUI_CMM_Sep" then CMMT.SEP = sep end
end)
Events.OnGameBoot.Add(function() pcall(hookDock) end)

return CMMT
