-- Cookie Mission - player board (3 daily cards) + sidebar icon
require "CM_UI_Kit"
require "CM_UI_HUD"

local C = CMUI.C
local T = CMC.txt

CMBoard = CMBoard or {}
CMBoard.Win = CMUI.Window:derive("CMBoard_Win")
local BW = CMBoard.Win

local confirm = { slot = 0, at = 0 }

function BW:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = T("IGUI_CM_Title")
    o.titleIcon = "cm_icon"
    o.bgAlpha = 0.78
    return o
end

-- the big font for numbers (falls back when a build lacks it)
local function bigFont() return UIFont.Title or UIFont.Large end

-- reward lines of a tier, straight from CM.DROPS so the board never lies (tooltip)
local function rewardLines(tier)
    local out = {}
    for _, d in ipairs(CM.DROPS[tier] or {}) do
        local c = CM.dropChance(d)
        if c > 0 or d.alt then
            local name = T("IGUI_CM_Pool_" .. d.p)
            local s
            if c >= 100 then s = name .. " x" .. tostring(d.r)
            else s = T("IGUI_CM_Chance", name, c) end
            if d.alt and c < 100 then s = s .. " " .. T("IGUI_CM_Else", T("IGUI_CM_Pool_" .. d.alt)) end
            out[#out + 1] = s
        end
    end
    return out
end
CMBoard.rewardLines = rewardLines

-- short reward tags of a tier: one per pool, in drop order
local function rewardTags(tier)
    local out, seen = {}, {}
    for _, d in ipairs(CM.DROPS[tier] or {}) do
        local c = CM.dropChance(d)
        if not seen[d.p] and (c > 0 or d.alt) then
            seen[d.p] = true
            out[#out + 1] = { k = d.p, s = T("IGUI_CM_Tag_" .. d.p), rare = c < 100 }
        end
    end
    return out
end
CMBoard.rewardTagsOf = rewardTags

-- tiny status in the card corner: glowing dot + a few words
local function statusDot(win, rx, y, c)
    local col, text = C.good, T("IGUI_CM_Dot_open")
    if c.status == "live" then
        col = C.gold
        text = tostring(c.n or 0) .. "/" .. tostring(c.cap or 0) .. "  " .. CM.clock(CMC.left(c.left, CMC.pubAt) or 0)
    elseif c.status == "cool" then
        col = C.dim
        text = T("IGUI_CM_Dot_cool", CM.clock(CMC.left(c.coolLeft, CMC.pubAt) or 0))
    elseif c.status ~= "open" then
        col, text = C.bad, T("IGUI_CM_Dot_none")
    end
    local fs = UIFont.Small
    local tw = CMUI.tw(fs, text)
    local d = math.max(5, math.floor(CMUI.fh(fs) / 3))
    local dx = rx - tw - d - 6
    local dy = y + (CMUI.fh(fs) - d) / 2
    CMUI.glow(win, dx + d / 2, dy + d / 2, d * 2, d * 2, col, 0.7)
    win:drawRect(dx, dy, d, d, 1, col[1], col[2], col[3])
    CMUI.text(win, text, rx - tw, y, col, 1, fs)
end

local function drawCard(win, x, y, w, h, c)
    local S = CMUI.S
    local tier = c.tier or c.slot
    local tc = CMUI.tierColor(tier)
    local fs, fm, fl, fb = UIFont.Small, UIFont.Medium, UIFont.Large, bigFont()
    local myRun = CMC.run()
    local mine = myRun and myRun.slot == c.slot
    local mx, my = win:getMouseX(), win:getMouseY()
    local hot = win:isMouseOver() and mx >= x and mx < x + w and my >= y and my < y + h
    local lit = mine or hot
    CMUI.glow(win, x + w / 2, y + h * 0.30, w * 0.55, h * 0.30, tc, lit and 0.30 or 0.16)
    CMUI.glass(win, x, y, w, h, { tint = C.panel, a = 0.45, rad = 12, rim = tc, rimA = lit and 0.9 or 0.35 })
    CMUI.brackets(win, x, y, w, h, tc, lit and 1 or 0.55, S(14), 2)
    local pad = S(16)
    local ix, iw = x + pad, w - pad * 2
    local cx = x + w / 2
    -- top row: rank pips + name, status dot
    local cy = y + S(14)
    local ps = S(10)
    for i = 1, tier do
        CMUI.icon(win, tier == 3 and "cm_skull" or "cm_pip", ix + (i - 1) * (ps + S(3)), cy + (CMUI.fh(fs) - ps) / 2, ps,
            tier == 3 and C.bad or tc, 1)
    end
    CMUI.text(win, CMC.tierName(tier), ix + tier * (ps + S(3)) + S(4), cy, tc, 1, fs)
    statusDot(win, ix + iw, cy, c)
    cy = cy + CMUI.fh(fs) + S(14)
    if c.status == "none" or not c.type then
        CMUI.textC(win, "?", cx, cy + S(30), C.faint, 1, fb)
        CMUI.textC(win, T("IGUI_CM_NoPlaceShort"), cx, cy + S(30) + CMUI.fh(fb) + S(10), C.dim, 1, fm)
        CMUI.btn(win, ix, y + h - S(52), iw, S(38), T("IGUI_CM_NotNow"), nil, "primary", { disabled = true, rad = 10 })
        return
    end
    -- the content block sits in the middle of the space between the top row and the button
    local is = S(64)
    local th = CMUI.fh(fs) + S(6)
    local btnH = S(38)
    local by = y + h - btnH - S(14)
    local blockH = is + S(12) + CMUI.fh(fl) + S(3) + CMUI.fh(fs) + S(18) + CMUI.fh(fb) + S(4) + CMUI.fh(fs) + S(14)
        + S(5) + S(14) + CMUI.fh(fs) + S(12) + th
    local room = by - S(16) - CMUI.fh(fs) - cy
    if room > blockH then cy = cy + math.floor((room - blockH) / 2) end
    -- the mission: big lit icon, name, where
    CMUI.glow(win, cx, cy + is / 2, is * 1.2, is * 1.1, tc, lit and 0.55 or 0.40)
    CMUI.icon(win, "cm_t_" .. c.type, cx - is / 2, cy, is, tc, 1)
    cy = cy + is + S(12)
    CMUI.textC(win, CMUI.fit(CMC.typeName(c.type), fl, iw), cx, cy, C.white, 1, fl)
    cy = cy + CMUI.fh(fl) + S(3)
    CMUI.textC(win, CMUI.fit(CMC.placeText(c), fs, iw), cx, cy, C.dim, 1, fs)
    cy = cy + CMUI.fh(fs) + S(16)
    -- the goal as one big number
    local num = tostring(c.type == "survive" and math.floor((c.goal or 0) / 60) or (c.goal or 0))
    local unit = T("IGUI_CM_Unit_" .. c.type)
    local verb = T("IGUI_CM_Verb_" .. c.type)
    local nw = CMUI.tw(fb, num)
    local uw = CMUI.tw(fm, unit)
    local gx = cx - (nw + S(8) + uw) / 2
    CMUI.text(win, num, gx, cy, tc, 1, fb)
    CMUI.text(win, unit, gx + nw + S(8), cy + CMUI.fh(fb) - CMUI.fh(fm) - S(3), C.text, 1, fm)
    cy = cy + CMUI.fh(fb) + S(4)
    CMUI.textC(win, verb, cx, cy, C.faint, 1, fs)
    cy = cy + CMUI.fh(fs) + S(12)
    -- danger bar (no words needed: longer = harder)
    CMUI.segbar(win, ix + S(10), cy, iw - S(20), S(5), ({ 0.34, 0.67, 1.0 })[tier] or 0.34, tier == 3 and C.bad or tc, 15)
    cy = cy + S(5) + S(14)
    -- time + team on one line
    CMUI.textC(win, T("IGUI_CM_StatLine", math.floor((c.limit or 0) / 60), c.cap or 0), cx, cy, C.dim, 1, fs)
    cy = cy + CMUI.fh(fs) + S(12)
    -- reward tags (details on hover)
    local tags = rewardTags(tier)
    local tws, total = {}, 0
    for i, tg in ipairs(tags) do
        tws[i] = CMUI.tw(fs, tg.s) + S(16)
        total = total + tws[i] + (i > 1 and S(6) or 0)
    end
    local tx = cx - total / 2
    win:hit(tx, cy, total, th, nil, T("IGUI_CM_RewardTip") .. "\n" .. table.concat(rewardLines(tier), "\n"))
    for i, tg in ipairs(tags) do
        local col = tg.k == "legend" and C.purple or (tg.rare and C.dim or C.gold)
        CMUI.rbox(win, tx, cy, tws[i], th, col, 0.14, math.floor(th / 2))
        CMUI.rborder(win, tx, cy, tws[i], th, col, tg.rare and 0.35 or 0.6, math.floor(th / 2))
        CMUI.textC(win, tg.s, tx + tws[i] / 2, cy + S(3), col, 1, fs)
        tx = tx + tws[i] + S(6)
    end
    -- action
    if CMC.claimed(c.id) then
        CMUI.textC(win, T("IGUI_CM_ClaimedShort"), cx, by - CMUI.fh(fs) - S(6), C.purple, 1, fs)
    end
    local label, style, dis = T("IGUI_CM_Go"), "primary", false
    if mine then label, style, dis = T("IGUI_CM_InThis"), "sel", true
    elseif myRun then label, dis = T("IGUI_CM_InOther"), true
    elseif c.status == "live" then label = T("IGUI_CM_JoinShort")
        if (c.n or 0) >= (c.cap or 0) then label, dis = T("IGUI_CM_Full"), true end
    elseif c.status ~= "open" then label, dis = T("IGUI_CM_NotNow"), true end
    if not dis and confirm.slot == c.slot and CMC.ms() - confirm.at < 4000 then
        label, style = T("IGUI_CM_ConfirmShort"), "good"
    end
    CMUI.btn(win, ix, by, iw, btnH, label, function()
        if confirm.slot == c.slot and CMC.ms() - confirm.at < 4000 then
            confirm.slot = 0
            CMC.send("accept", { slot = c.slot })
            if CMBoard.win then CMBoard.win:close() end
        else
            confirm.slot = c.slot
            confirm.at = CMC.ms()
        end
    end, style, { disabled = dis, tip = T("IGUI_CM_AcceptTip"), font = UIFont.Medium, rad = 10 })
end

function BW:drawBody()
    local S = CMUI.S
    local pad = S(18)
    local top = self.headerH + S(16)
    local pub = CMC.pub
    local w = self.width
    if not pub then
        CMUI.textC(self, T("IGUI_CM_Loading"), w / 2, top + S(40), C.dim, 1, UIFont.Medium)
        return
    end
    -- header extras: reset timer + "?" with the rules
    local reset = CMC.left(pub.reset, CMC.pubAt) or 0
    local cs = self.headerH - 16
    local qx = w - cs * 2 - 18
    local over = self:hit(qx, 8, cs, cs, nil, T("IGUI_CM_Rules"))
    CMUI.rbox(self, qx, 8, cs, cs, over and C.panel3 or C.panel2, 0.45, 6)
    CMUI.rborder(self, qx, 8, cs, cs, C.line, 0.6, 6)
    CMUI.textC(self, "?", qx + cs / 2, 8 + (cs - CMUI.fh(UIFont.Small)) / 2 - 1, C.gold, 1, UIFont.Small)
    CMUI.textR(self, T("IGUI_CM_ResetShort", CM.clock(reset)), qx - S(10), (self.headerH - CMUI.fh(UIFont.Small)) / 2, C.dim)
    local gap = S(18)
    local cw = math.floor((w - pad * 2 - gap * 2) / 3)
    local ch = self.height - top - S(18)
    for s = 1, 3 do
        local c = pub.cards and pub.cards[s] or { slot = s, status = "none" }
        c.slot = c.slot or s
        drawCard(self, pad + (s - 1) * (cw + gap), top, cw, ch, c)
    end
end

function BW:onClosed()
    CMBoard.win = nil
end

function CMBoard.open()
    if CMBoard.win then CMBoard.win:bringToTop(); return end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(900, 560)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = BW:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    win:show()
    CMBoard.win = win
    CMIcon.markSeen()
    if not CMC.pub then CMC.send("hello", {}) end
end

function CMBoard.toggle()
    if CMBoard.win then CMBoard.win:close() else CMBoard.open() end
end

-- ===================================================================== sidebar icon
CMIcon = CMIcon or {}

local function signature()
    local pub = CMC.pub
    if not pub or not pub.cards then return "" end
    local parts = {}
    for s = 1, 3 do local c = pub.cards[s]; if c and c.id then parts[#parts + 1] = c.id end end
    return table.concat(parts, ",")
end

function CMIcon.markSeen() CMIcon.seen = signature() end
function CMIcon.hasNew()
    local sig = signature()
    return sig ~= "" and sig ~= CMIcon.seen
end

function CMIcon.tooltip()
    local t = T("IGUI_CM_IconTip")
    local run = CMC.run()
    if run then t = t .. "\n" .. T("IGUI_CM_IconActive", CMC.typeName(run.type)) end
    return t
end

function CMIcon.click() CMBoard.toggle() end

function CMIcon.draw(el, w, h, over)
    local live = CMC.run() ~= nil
    local tex = CMUI.tex("cm_icon")
    local s = math.min(w, h)
    local x, y = (w - s) / 2, (h - s) / 2
    local a = 1
    if live then a = 0.75 + 0.25 * math.sin(CMC.ms() / 220) end
    if tex then el:drawTextureScaledAspect(tex, x, y, s, s, a, 1, 1, 1)
    else el:drawRect(x + 4, y + 4, s - 8, s - 8, 0.9, C.t3[1], C.t3[2], C.t3[3]) end
    if over then el:drawRectBorder(x + 1, y + 1, s - 2, s - 2, 0.6, C.accent[1], C.accent[2], C.accent[3]) end
    if CMIcon.hasNew() then
        local d = math.max(8, math.floor(s * 0.22))
        el:drawRect(x + s - d - 2, y + 2, d, d, 1, C.bad[1], C.bad[2], C.bad[3])
    end
end

function CMIcon.context()
    local ctx = ISContextMenu.get(0, getMouseX(), getMouseY())
    ctx:addOption(T("IGUI_CM_Ctx_Open"), nil, function() CMBoard.open() end)
    if CMC.isAdmin() then
        ctx:addOption(T("IGUI_CM_Ctx_Admin"), nil, function() if CMAdmin then CMAdmin.toggle() end end)
    end
end

-- the screen button itself lives in CM_Dock.lua (one dock button groups the other mods' buttons)

-- new day / board changed while open: nothing to do, the window redraws every frame
CMC.on(function(what)
    if what == "warp" and CMBoard.win then CMBoard.win:close() end
end)

return CMBoard
