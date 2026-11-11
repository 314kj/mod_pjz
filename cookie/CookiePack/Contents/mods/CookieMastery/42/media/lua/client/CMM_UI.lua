-- Cookie Mastery - "Mastery" tab beside the Skills tab of the character window (glass, Lite)
if isServer() and not isClient() then return end

require "CMM_Client"
require "CM_UI_Kit"
require "CMM_Tree"
require "XpSystem/ISUI/ISCharacterInfoWindow"

CMMUI = CMMUI or {}
local C = CMUI.C
local S = CMUI.S
local T = CMMC.txt

local FT = UIFont.Title or UIFont.Large

CMMUI.View = CMUI.Window:derive("CMMUI_View")
local V = CMMUI.View

function V:new(x, y, w, h, playerNum)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.playerNum = playerNum or 0
    o.headerH = 0
    o.anchorRight = true
    o.anchorBottom = false   -- the tab sets the window height itself (fitHeight), like the vanilla tabs
    o.sel = nil          -- branch shown in the detail panel
    o.confirm = nil      -- { what, until }
    return o
end

function V:keepOnScreen() end

-- Like the vanilla tabs (ISCharacterInfo: setHeightAndParentHeight(min(y, 800))), this tab sizes the
-- character window to its content, up to 800 and the bottom of the screen; anything taller scrolls.
-- Without it the tab kept the height of whatever tab was open before, so the bottom could sit
-- below the window with nothing to scroll.
function V:fitHeight()
    local a
    for i = 1, #(self.scrollAreas or {}) do
        if self.scrollAreas[i].key == "main" then a = self.scrollAreas[i] end
    end
    if not a then return end
    local contentH = (a.maxY + (a.off or 0)) - a.y
    local want = contentH + S(10) * 2 + S(6)
    local okY, absY = pcall(function() return self:getAbsoluteY() end)
    local screenH = getCore():getScreenHeight()
    local cap = S(800)
    if okY and absY then cap = math.min(cap, screenH - absY - S(24)) end
    want = math.floor(math.max(S(240), math.min(want, cap)))
    if math.abs(want - self.height) >= 2 then
        if self.setHeightAndParentHeight then self:setHeightAndParentHeight(want) else self:setHeight(want) end
    end
end

function V:prerender()
    CMUI.Window.prerender(self)
    local ok, err = pcall(self.fitHeight, self)
    if not ok and not self.fitWarned then
        self.fitWarned = true
        CMM.log("tab height error: " .. tostring(err))
    end
end

function V:onMouseDown(x, y)
    local h = self:findHit(x, y)
    if h then self.pressed = h end
    return true
end

function V:drawFrame()
    CMUI.rbox(self, 0, 0, self.width, self.height, C.bg, 0.55, 0)
    CMUI.texBox(self, "cm_grad", 0, 0, self.width, math.min(self.height * 0.4, 200), C.accent, 0.10)
end

local function armed(self, what)
    local c = self.confirm
    return c and c.what == what and CMMC.ms() < c.untilMs
end

local function arm(self, what)
    self.confirm = { what = what, untilMs = CMMC.ms() + 4000 }
end

local function me() return CMMC.me end

-- ===================================================================== header
local function drawHeader(self, x, y, w)
    local m = me()
    local h = S(92)
    local br = m and m.br
    local col = br and CMM.colorOf(br) or C.gold
    CMUI.glass(self, x, y, w, h, { tint = C.panel, a = 0.55, rad = 10, rim = col, rimA = 0.55 })
    CMUI.glow(self, x + S(46), y + h / 2, S(56), S(52), col, 0.22)
    local lv, into, need = CMM.level(m and m.pts or 0)
    -- level medallion
    local mx, my, msz = x + S(14), y + (h - S(64)) / 2, S(64)
    CMUI.rbox(self, mx, my, msz, msz, C.dark, 0.75, 12)
    CMUI.rborder(self, mx, my, msz, msz, col, 0.85, 12)
    CMUI.textC(self, T("IGUI_CMM_Lv"), mx + msz / 2, my + S(4), C.dim, 1, UIFont.Small)
    CMUI.textC(self, tostring(lv), mx + msz / 2, my + S(4) + CMUI.fh(UIFont.Small) - 2, col, 1, FT)
    local tx = mx + msz + S(14)
    local tw = x + w - tx - S(12)
    if not br then
        CMUI.text(self, T("IGUI_CMM_NoBranch"), tx, y + S(14), C.text, 1, UIFont.Medium)
        CMUI.para(self, T("IGUI_CMM_NoBranchTip"), tx, y + S(16) + CMUI.fh(UIFont.Medium), tw, C.dim, UIFont.Small, 3)
        return h
    end
    local side = CMM.sideOf(br)
    CMUI.text(self, CMMC.brName(br), tx, y + S(10), C.text, 1, UIFont.Large)
    CMUI.text(self, CMMC.sideName(side and side.id), tx + CMUI.tw(UIFont.Large, CMMC.brName(br)) + S(8),
        y + S(10) + CMUI.fh(UIFont.Large) - CMUI.fh(UIFont.Small) - 1, col, 1, UIFont.Small)
    local by = y + S(14) + CMUI.fh(UIFont.Large)
    if lv >= 10 then
        CMUI.segbar(self, tx, by, tw, S(8), 1, col, 24)
        CMUI.text(self, T("IGUI_CMM_Max"), tx, by + S(12), col, 1, UIFont.Small)
    else
        CMUI.segbar(self, tx, by, tw, S(8), into / math.max(1, need), col, 24)
        CMUI.text(self, T("IGUI_CMM_Next", CMMC.num(into), CMMC.num(need), lv + 1), tx, by + S(12), C.dim, 1, UIFont.Small)
    end
    local pw = CMUI.pill(self, tx, by + S(14) + CMUI.fh(UIFont.Small), T("IGUI_CMM_Wallet", CMMC.num(m.wal)), C.gold, UIFont.Small)
    if m.life and m.life > 1 then
        CMUI.text(self, T("IGUI_CMM_Life", m.life), tx + pw + S(8), by + S(15) + CMUI.fh(UIFont.Small), C.faint, 1, UIFont.Small)
    end
    return h
end

-- ===================================================================== tree (3 sides x 3 branches x 4 tiers)
local function pips(self, x, y, size, bid, lv, chosen, col)
    local gap = S(4)
    for i = 1, #CMM.TIERS do
        local t = CMM.TIERS[i]
        local px = x + (i - 1) * (size + gap)
        local on = chosen and lv >= t
        local live = CMM.nodeLive(bid, t)
        -- the same pip art the mission board uses; dim = locked, grey = node still "soon"
        local c = on and col or (live and col or C.faint)
        local a = on and 1 or (live and 0.55 or 0.25)
        if not CMUI.icon(self, "cm_pip", px, y, size, c, a) then CMUI.rect(self, px, y, size, size, c, a) end
    end
    return #CMM.TIERS * (size + gap) - gap
end

local function drawTree(self, x, y, w)
    local m = me()
    local elig = CMMC.eligible()
    local lv = CMM.level(m and m.pts or 0)
    local cols = #CMM.SIDES
    local gap = S(8)
    local cw = math.floor((w - gap * (cols - 1)) / cols)
    local ch = S(50)
    local fh = CMUI.fh(UIFont.Small)
    local maxY = y
    for c = 1, cols do
        local side = CMM.SIDES[c]
        local cx = x + (c - 1) * (cw + gap)
        CMUI.textC(self, CMMC.sideName(side.id), cx + cw / 2, y, side.color, 1, UIFont.Small)
        CMUI.hline(self, cx + S(6), y + fh + S(2), cw - S(12), side.color, 0.6)
        local yy = y + fh + S(8)
        for b = 1, #side.branches do
            local bid = side.branches[b]
            local chosen = m and m.br == bid
            local can = m and not m.br and elig[bid]
            local selected = self.sel == bid
            local over = self:hit(cx, yy, cw, ch, function() self.sel = bid end, nil)
            local tint = chosen and C.accentD or C.panel
            local alpha = (chosen or can or selected) and 0.70 or 0.40
            if over then alpha = alpha + 0.12 end
            if chosen then CMUI.glow(self, cx + cw / 2, yy + ch / 2, cw * 0.6, ch * 0.9, side.color, 0.25) end
            CMUI.rbox(self, cx, yy, cw, ch, tint, alpha, 8)
            local rimC = (chosen or selected) and side.color or (can and side.color or C.line)
            local rimA = chosen and 0.95 or (selected and 0.75 or (can and 0.55 or 0.25))
            CMUI.rborder(self, cx, yy, cw, ch, rimC, rimA, 8)
            local nameC = (chosen or can) and C.text or (m and m.br and C.faint or C.dim)
            CMUI.textC(self, CMUI.fit(CMMC.brName(bid), UIFont.Small, cw - S(8)), cx + cw / 2, yy + S(6), nameC, 1, UIFont.Small)
            local ps = S(10)
            local pw = #CMM.TIERS * (ps + S(4)) - S(4)
            pips(self, cx + (cw - pw) / 2, yy + ch - ps - S(9), ps, bid, lv, chosen, side.color)
            if can then
                CMUI.rbox(self, cx + cw - S(12), yy + S(5), S(7), S(7), C.good, 0.95, 3)
            end
            yy = yy + ch + S(6)
        end
        if yy > maxY then maxY = yy end
    end
    return maxY - y
end

-- ===================================================================== detail of one branch
local function drawDetail(self, x, y, w)
    local m = me()
    local bid = self.sel
    if not bid or not CMM.BRANCH[bid] then return 0 end
    local col = CMM.colorOf(bid)
    local lv = CMM.level(m and m.pts or 0)
    local chosen = m and m.br == bid
    local pad = S(12)
    local fh = CMUI.fh(UIFont.Small)
    -- measure
    local rows = {}
    local tw = w - pad * 2 - S(54)
    local total = S(10) + CMUI.fh(UIFont.Medium) + S(6) + CMUI.paraH(T("IGUI_CMM_Perks_" .. bid), w - pad * 2, UIFont.Small, 2) + S(8)
    for i = 1, #CMM.TIERS do
        local t = CMM.TIERS[i]
        local s = T("IGUI_CMM_N_" .. bid .. "_" .. t)
        local extra = ""
        if t == 3 then extra = T("IGUI_CMM_N_all_3") end
        if t == 5 then extra = T("IGUI_CMM_N_all_5") end
        if t == 10 then extra = T("IGUI_CMM_N_all_10") end
        local rh = CMUI.paraH(s, tw, UIFont.Small, 4) + S(8)
        if extra ~= "" then rh = rh + CMUI.paraH(extra, tw, UIFont.Small, 3) end
        rows[i] = { t = t, s = s, extra = extra, h = math.max(S(34), rh) }
        total = total + rows[i].h + S(4)
    end
    local canPick = m and not m.br and CMMC.eligible()[bid]
    if canPick then total = total + S(40) end
    CMUI.glass(self, x, y, w, total, { tint = C.panel, a = 0.50, rad = 10, rim = col, rimA = 0.45 })
    local yy = y + S(10)
    CMUI.text(self, CMMC.brName(bid), x + pad, yy, col, 1, UIFont.Medium)
    yy = yy + CMUI.fh(UIFont.Medium) + S(6)
    yy = yy + CMUI.para(self, T("IGUI_CMM_Perks_" .. bid), x + pad, yy, w - pad * 2, C.faint, UIFont.Small, 2) + S(8)
    for i = 1, #rows do
        local r = rows[i]
        local on = chosen and lv >= r.t
        local bx = x + pad
        CMUI.rbox(self, bx, yy, S(42), S(26), on and col or C.panel2, on and 0.90 or 0.55, 6)
        CMUI.rborder(self, bx, yy, S(42), S(26), col, on and 1 or 0.45, 6)
        CMUI.textC(self, T("IGUI_CMM_TierLv", r.t), bx + S(21), yy + (S(26) - fh) / 2, on and C.dark or C.text, 1, UIFont.Small)
        local tx = bx + S(54)
        local used = CMUI.para(self, r.s, tx, yy, tw, on and C.text or C.dim, UIFont.Small, 4)
        if r.extra ~= "" then CMUI.para(self, r.extra, tx, yy + used, tw, on and C.gold or C.faint, UIFont.Small, 3) end
        if not CMM.nodeLive(bid, r.t) then
            CMUI.textR(self, T("IGUI_CMM_Soon"), x + w - pad, yy, C.faint, 1, UIFont.Small)
        end
        yy = yy + r.h + S(4)
    end
    if canPick then
        local label = armed(self, "pick" .. bid) and T("IGUI_CMM_PickConfirm") or T("IGUI_CMM_Pick", CMMC.brName(bid))
        CMUI.btn(self, x + pad, yy + S(2), w - pad * 2, S(30), label, function()
            if armed(self, "pick" .. bid) then
                self.confirm = nil
                CMMC.send("pick", { br = bid })
            else
                arm(self, "pick" .. bid)
            end
        end, armed(self, "pick" .. bid) and "good" or "primary")
    end
    return total
end

-- ===================================================================== mentor / apprentice / book
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

local function drawSocial(self, x, y, w)
    local m = me()
    if not m then return 0 end
    local lv = CMM.level(m.pts)
    local fh = CMUI.fh(UIFont.Small)
    local pad = S(12)
    local bh = S(26)
    local lines = {}
    if m.inv then lines[#lines + 1] = "inv" end
    if m.mentor then lines[#lines + 1] = "mentor" end
    if m.br and lv >= 3 then lines[#lines + 1] = "appr" end
    if m.br and lv >= 5 then lines[#lines + 1] = "book" end
    if m.buff then lines[#lines + 1] = "buff" end
    if #lines == 0 then return 0 end
    local rowH = math.max(bh, fh) + S(8)
    local hh = S(10) + fh + S(8) + #lines * rowH + S(4)
    CMUI.glass(self, x, y, w, hh, { tint = C.panel, a = 0.45, rad = 10 })
    CMUI.text(self, T("IGUI_CMM_Social"), x + pad, y + S(8), C.gold, 1, UIFont.Small)
    local yy = y + S(10) + fh + S(8)
    local right = x + w - pad
    for i = 1, #lines do
        local k = lines[i]
        local ty = yy + (bh - fh) / 2
        if k == "inv" then
            CMUI.text(self, CMUI.fit(T("IGUI_CMM_Invite", m.inv.from, CMMC.brName(m.inv.br)), UIFont.Small, w - S(170)), x + pad, ty, C.text, 1, UIFont.Small)
            local b1 = CMUI.btnA(self, right - S(140), yy, bh, T("IGUI_CMM_Accept"), function() CMMC.send("answer", { ok = true }) end, "good", { minW = S(66) })
            CMUI.btnA(self, right - S(140) + b1 + S(6), yy, bh, T("IGUI_CMM_Decline"), function() CMMC.send("answer", { ok = false }) end, "ghost", { minW = S(60) })
        elseif k == "mentor" then
            CMUI.text(self, T("IGUI_CMM_MyMentor", m.mentor), x + pad, ty, C.text, 1, UIFont.Small)
            local lab = armed(self, "leave") and T("IGUI_CMM_Sure") or T("IGUI_CMM_Leave")
            local bw = CMUI.tw(UIFont.Small, lab) + S(22)
            CMUI.btn(self, right - bw, yy, bw, bh, lab, function()
                if armed(self, "leave") then self.confirm = nil; CMMC.send("leave", {}) else arm(self, "leave") end
            end, "flat")
        elseif k == "appr" then
            if m.appr then
                CMUI.text(self, T("IGUI_CMM_MyAppr", m.appr), x + pad, ty, C.text, 1, UIFont.Small)
                local lab = armed(self, "drop") and T("IGUI_CMM_Sure") or T("IGUI_CMM_Drop")
                local bw = CMUI.tw(UIFont.Small, lab) + S(22)
                CMUI.btn(self, right - bw, yy, bw, bh, lab, function()
                    if armed(self, "drop") then self.confirm = nil; CMMC.send("leave", {}) else arm(self, "drop") end
                end, "flat")
            else
                local near = nearbyPlayers()
                if #near == 0 then
                    CMUI.text(self, T("IGUI_CMM_NoAppr"), x + pad, ty, C.dim, 1, UIFont.Small)
                else
                    CMUI.text(self, T("IGUI_CMM_TakeAppr"), x + pad, ty, C.dim, 1, UIFont.Small)
                    local bx = right
                    for j = #near, 1, -1 do
                        local n = near[j]
                        local bw = math.min(S(110), CMUI.tw(UIFont.Small, n) + S(22))
                        bx = bx - bw
                        CMUI.btn(self, bx, yy, bw, bh, n, function() CMMC.send("invite", { name = n }) end, "primary")
                        bx = bx - S(6)
                    end
                end
            end
        elseif k == "book" then
            local wait = CMM.sv("BookDays") * 86400
            local since = CM.num(m.now, 0) - CM.num(m.bookAt, 0) + CMMC.age(CMMC.meAt)
            CMUI.text(self, T("IGUI_CMM_Book"), x + pad, ty, C.text, 1, UIFont.Small)
            if m.bookAt and since < wait then
                CMUI.textR(self, T("IGUI_CMM_BookIn", CMMC.dur(wait - since)), right, ty, C.dim, 1, UIFont.Small)
            else
                local lab = T("IGUI_CMM_BookWrite")
                local bw = CMUI.tw(UIFont.Small, lab) + S(22)
                CMUI.btn(self, right - bw, yy, bw, bh, lab, function() CMMC.send("book", {}) end, "good")
            end
        elseif k == "buff" then
            local left = CM.num(m.buff.left, 0) - CMMC.age(CMMC.meAt)
            CMUI.text(self, CMUI.fit(T("IGUI_CMM_Buff", m.buff.by, CMMC.brName(m.buff.br), CM.num(m.buff.pct, 0)), UIFont.Small, w - S(120)), x + pad, ty, C.good, 1, UIFont.Small)
            CMUI.textR(self, CMMC.dur(left), right, ty, C.dim, 1, UIFont.Small)
        end
        yy = yy + rowH
    end
    return hh
end

-- banked overflow before a branch is chosen
local function drawBanked(self, x, y, w)
    local m = me()
    if not m or m.br or type(m.pre) ~= "table" or not CM.any(m.pre) then return 0 end
    local fh = CMUI.fh(UIFont.Small)
    local keys = CM.sortedKeys(m.pre)
    local h = S(10) + fh * (#keys + 1) + S(10)
    CMUI.glass(self, x, y, w, h, { tint = C.panel, a = 0.40, rad = 10 })
    CMUI.text(self, T("IGUI_CMM_Banked"), x + S(12), y + S(8), C.gold, 1, UIFont.Small)
    for i = 1, #keys do
        local k = keys[i]
        CMUI.text(self, CMMC.brName(k), x + S(12), y + S(8) + fh * i, C.text, 1, UIFont.Small)
        CMUI.textR(self, CMMC.num(m.pre[k]), x + w - S(12), y + S(8) + fh * i, C.dim, 1, UIFont.Small)
    end
    return h
end

-- buttons left to right, wrapping into rows that fit maxW
local function flowRows(items, maxW, gap)
    local rows, row, rw = {}, {}, 0
    for i = 1, #items do
        local it = items[i]
        it.w = CMUI.tw(UIFont.Small, it.label) + 22
        if #row > 0 and rw + gap + it.w > maxW then
            rows[#rows + 1] = row
            row, rw = {}, 0
        end
        rw = rw + (#row > 0 and gap or 0) + it.w
        row[#row + 1] = it
    end
    if #row > 0 then rows[#rows + 1] = row end
    return rows
end

local function drawRows(self, rows, x, y, bh, gap)
    for r = 1, #rows do
        local bx = x
        for i = 1, #rows[r] do
            local it = rows[r][i]
            CMUI.btn(self, bx, y, it.w, bh, it.label, it.fn, it.style)
            bx = bx + it.w + gap
        end
        y = y + bh + gap
    end
    return y
end

local function adm(op, extra)
    return function()
        local a = { op = op }
        for k2, v in pairs(extra or {}) do a[k2] = v end
        CMMC.send("adm", a)
    end
end

-- admin tools; test mode = a throw-away copy of the record (any branch, any level), real one kept
local function drawAdmin(self, x, y, w)
    if not CMMC.isAdmin() then return 0 end
    local m = me() or {}
    local fh = CMUI.fh(UIFont.Small)
    local bh = S(24)
    local gap = S(6)
    local inner = w - S(20)
    local lv = CMMC.lv()
    local brRows, rows = nil, nil
    if m.test then
        local brs = {}
        for _, side in ipairs(CMM.SIDES) do
            for _, bid in ipairs(side.branches) do
                brs[#brs + 1] = { label = CMMC.brName(bid), fn = adm("br", { br = bid }), style = (m.br == bid) and "sel" or "ghost" }
            end
        end
        brRows = flowRows(brs, inner, gap)
        rows = flowRows({
            { label = T("IGUI_CMM_AdmLvDown"), fn = adm("lv", { n = math.max(0, lv - 1) }), style = "purple" },
            { label = T("IGUI_CMM_AdmLv"), fn = adm("lv", { n = math.min(10, lv + 1) }), style = "purple" },
            { label = T("IGUI_CMM_AdmLv10"), fn = adm("lv", { n = 10 }), style = "purple" },
            { label = T("IGUI_CMM_AdmBar"), fn = adm("bar", { n = 1 }), style = "purple" },
            { label = T("IGUI_CMM_AdmBook"), fn = adm("book"), style = "purple" },
            { label = T("IGUI_CMM_AdmUnpick"), fn = adm("unpick"), style = "purple" },
            { label = T("IGUI_CMM_AdmTestReset"), fn = adm("reset"), style = "danger" },
            { label = T("IGUI_CMM_AdmTestOff"), fn = adm("testoff"), style = "good" },
        }, inner, gap)
    else
        rows = flowRows({
            { label = T("IGUI_CMM_AdmTest"), fn = adm("test"), style = "primary" },
            { label = T("IGUI_CMM_AdmBar"), fn = adm("bar", { n = 1 }), style = "purple" },
            { label = T("IGUI_CMM_AdmLv"), fn = adm("lv", { n = math.min(10, lv + 1) }), style = "purple" },
            { label = T("IGUI_CMM_AdmUnpick"), fn = adm("unpick"), style = "purple" },
            { label = T("IGUI_CMM_AdmBook"), fn = adm("book"), style = "purple" },
            { label = T("IGUI_CMM_AdmReset"), fn = adm("reset"), style = "purple" },
        }, inner, gap)
    end
    local h = S(8) + fh * 2 + S(8)
    if m.test then h = h + fh + S(4) + fh + S(4) + #brRows * (bh + gap) + S(4) end
    h = h + #rows * (bh + gap) + S(4)
    CMUI.rbox(self, x, y, w, h, C.dark, 0.55, 8)
    CMUI.rborder(self, x, y, w, h, C.purple, m.test and 0.85 or 0.40, 8)
    local ty = y + S(6)
    if m.test then
        CMUI.text(self, CMUI.fit(T("IGUI_CMM_TestOn"), UIFont.Small, inner), x + S(10), ty, C.purple, 1, UIFont.Small)
        ty = ty + fh + S(4)
    end
    CMUI.text(self, T("IGUI_CMM_Probe", CMMC.num(m.x10), CM.num(m.seen, 0)), x + S(10), ty, C.purple, 1, UIFont.Small)
    CMUI.text(self, T("IGUI_CMM_Probe2", CMMC.num(m.got)), x + S(10), ty + fh, C.faint, 1, UIFont.Small)
    local by = ty + fh * 2 + S(8)
    if m.test then
        CMUI.text(self, T("IGUI_CMM_TestBr"), x + S(10), by, C.dim, 1, UIFont.Small)
        by = drawRows(self, brRows, x + S(10), by + fh + S(4), bh, gap) + S(4)
    end
    drawRows(self, rows, x + S(10), by, bh, gap)
    return h
end

function V:drawBody()
    local m = me()
    local pad = S(10)
    local w = self.width - pad * 2 - S(8)
    if not self.sel then self.sel = (m and m.br) or "build" end
    self:form("main", pad, pad, w, self.height - pad * 2, function(top)
        local y = top
        if not m then
            CMUI.textC(self, T("IGUI_CMM_Wait"), pad + w / 2, y + S(40), C.dim, 1, UIFont.Medium)
            return
        end
        if not CMM.sv("Enabled") then
            CMUI.textC(self, T("IGUI_CMM_Off"), pad + w / 2, y + S(40), C.dim, 1, UIFont.Medium)
            return
        end
        if m.test then
            -- admin test mode: say so on top, the controls are at the bottom of the tab
            local fh = CMUI.fh(UIFont.Small)
            CMUI.rbox(self, pad, y, w, fh + S(10), C.purple, 0.22, 8)
            CMUI.rborder(self, pad, y, w, fh + S(10), C.purple, 0.75, 8)
            CMUI.text(self, CMUI.fit(T("IGUI_CMM_TestBanner"), UIFont.Small, w - S(20)), pad + S(10), y + S(5), C.text, 1, UIFont.Small)
            y = y + fh + S(10) + S(8)
        end
        y = y + drawHeader(self, pad, y, w) + S(10)
        -- the big skill tree window
        local ob = S(34)
        CMUI.glow(self, pad + w / 2, y + ob / 2, w * 0.45, ob, C.accent, 0.18)
        CMUI.btn(self, pad, y, w, ob, T("IGUI_CMM_OpenTree"), function()
            CMMT.open(self.sel and { kind = "node", bid = self.sel, tier = 1 } or nil)
        end, "primary")
        y = y + ob + S(12)
        local bk = drawBanked(self, pad, y, w)
        if bk > 0 then y = y + bk + S(10) end
        y = y + drawTree(self, pad, y, w) + S(6)
        y = y + drawDetail(self, pad, y, w) + S(10)
        local so = drawSocial(self, pad, y, w)
        if so > 0 then y = y + so + S(10) end
        local ad = drawAdmin(self, pad, y, w)
        if ad > 0 then y = y + ad + S(10) end
    end)
end

-- ===================================================================== install the tab
CMMUI.views = CMMUI.views or {}

local function addTab(win)
    if not win or not win.panel or win.cmmView then return end
    local view = V:new(0, 8, win.width, win.height - 8, win.playerNum)
    view:initialise()
    view:instantiate()
    win.panel:addView(T("IGUI_CMM_Tab"), view)
    win.cmmView = view
    CMMUI.views[#CMMUI.views + 1] = view
end
CMMUI.addTab = addTab

if not ISCharacterInfoWindow.__cmmWrapped then
    ISCharacterInfoWindow.__cmmWrapped = true
    local orig = ISCharacterInfoWindow.createChildren
    function ISCharacterInfoWindow:createChildren()
        orig(self)
        local ok, err = pcall(addTab, self)
        if not ok then CMM.log("tab install error: " .. tostring(err)) end
    end
end

-- the character window may already exist (Lua reload)
Events.OnGameStart.Add(function()
    local win = ISCharacterInfoWindow.instance
    if win then pcall(addTab, win) end
end)

return CMMUI
