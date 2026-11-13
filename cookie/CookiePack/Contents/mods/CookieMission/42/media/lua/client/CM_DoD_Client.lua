-- Cookie Mission - Die or Die (client), military look: floating button, teams window (teams / room /
-- scoreboard / admin spot setup), insertion screen, radio arrival effect, match HUD, debrief cards
require "CM_UI_Kit"
require "CM_UI_Squad"
require "CM_UI_Games"
require "CM_DoD"

local T = CMC.txt
local D = CM.DOD

CMDoDc = CMDoDc or {}
CMDoDc.snap = nil
CMDoDc.at = 0

local function S(n) return CMUI.S(n) end
local function left(v) return CMC.left(v, CMDoDc.at) or 0 end
local function team() return CMDoDc.snap and CMDoDc.snap.team or nil end

-- ===================================================================== look
local K = {
    bg = { 0.03, 0.04, 0.03 }, panel = { 0.07, 0.09, 0.06 }, panel2 = { 0.10, 0.13, 0.08 },
    line = { 0.17, 0.22, 0.14 }, line2 = { 0.24, 0.29, 0.17 },
    g = { 0.65, 0.89, 0.29 }, gHov = { 0.78, 0.96, 0.48 }, gDim = { 0.40, 0.55, 0.20 },
    text = { 0.90, 0.92, 0.87 }, dim = { 0.54, 0.58, 0.50 }, faint = { 0.36, 0.40, 0.32 },
    amber = { 0.85, 0.64, 0.23 }, red = { 0.88, 0.35, 0.28 }, ink = { 0.04, 0.05, 0.04 }, purple = { 0.66, 0.50, 0.94 },
}
CMDoDc.K = K
local TIER_COL = { K.dim, K.g, K.red }

local function rect(win, x, y, w, h, c, a) win:drawRect(x, y, w, h, a or 1, c[1], c[2], c[3]) end
local function border(win, x, y, w, h, c, a) win:drawRectBorder(x, y, w, h, a or 1, c[1], c[2], c[3]) end
local function tex(win, name, x, y, w, h, a, c)
    local t = CMUI.tex(name)
    if not t then return false end
    c = c or { 1, 1, 1 }
    win:drawTextureScaled(t, x, y, w, h, a or 1, c[1], c[2], c[3])
    return true
end

-- a location picture with a dark fade at the bottom; grey = not available
local function locPic(win, id, x, y, w, h, grey, fade)
    local l = D.LOC[id]
    if not (l and tex(win, l.tex, x, y, w, h, grey and 0.35 or 1, grey and { 0.5, 0.5, 0.5 } or nil)) then
        rect(win, x, y, w, h, K.panel2, 1)
    end
    if fade then
        local steps = 8
        for i = 0, steps - 1 do
            rect(win, x, y + h * (0.45 + 0.55 * i / steps), w, h * 0.55 / steps + 1, K.bg, 0.12 + 0.1 * i)
        end
    end
end

-- sharp military button: kind = go (green), ghost, on (selected), red
local function mbtn(win, x, y, w, h, label, fn, kind, opts)
    opts = opts or {}
    local dis = opts.disabled == true
    local over, pressed = win:hit(x, y, w, h, (not dis) and fn or nil, opts.tip)
    local yo = pressed and 1 or 0
    local font = opts.font or UIFont.Small
    local bg, fg, rim = K.panel, K.text, K.line2
    if kind == "go" then bg, fg, rim = over and K.gHov or K.g, K.ink, K.g
    elseif kind == "on" then bg, fg, rim = K.panel2, K.g, K.g
    elseif kind == "red" then bg, fg, rim = over and { 0.30, 0.09, 0.07 } or { 0.20, 0.06, 0.05 }, { 1, 0.75, 0.70 }, K.red
    elseif over then bg = K.panel2 end
    if dis then bg, fg, rim = K.panel, K.faint, K.line end
    rect(win, x, y + yo, w, h, bg, dis and 0.6 or 0.95)
    border(win, x, y + yo, w, h, rim, 1)
    if kind == "go" and not dis then
        -- the cut corner
        rect(win, x + w - S(10), y + yo + h - S(3), S(10), S(3), K.bg, 1)
        rect(win, x + w - S(3), y + yo + h - S(10), S(3), S(10), K.bg, 1)
    end
    CMUI.textC(win, CMUI.fit(label, font, w - 8), x + w / 2, y + yo + (h - CMUI.fh(font)) / 2, fg, 1, font)
    return over
end
CMDoDc.btn = mbtn

-- crosshair drawn with lines (no texture needed)
local function crosshair(win, cx, cy, r, c, th)
    th = th or 2
    CMUI.ring(win, cx, cy, r * 0.62, c, 1)
    rect(win, cx - th / 2, cy - r, th, r * 0.5, c, 1)
    rect(win, cx - th / 2, cy + r * 0.5, th, r * 0.5, c, 1)
    rect(win, cx - r, cy - th / 2, r * 0.5, th, c, 1)
    rect(win, cx + r * 0.5, cy - th / 2, r * 0.5, th, c, 1)
    rect(win, cx - th, cy - th, th * 2, th * 2, c, 1)
end

-- the faded fence picture behind the team screens: grey picture, dark on the left, green to the right
local function backdrop(win, x, y, w, h, op)
    op = op or 1
    rect(win, x, y, w, h, K.bg, op)
    tex(win, "dod_bg", x, y, w, h, 0.45 * op, { 0.62, 0.70, 0.58 })
    local steps = 16
    for i = 0, steps - 1 do
        local k = i / (steps - 1)
        rect(win, x + w * i / steps, y, w / steps + 1, h, K.bg, (0.96 - 0.62 * k) * op)
        rect(win, x + w * i / steps, y, w / steps + 1, h, K.gDim, 0.16 * k * op)
    end
    for i = 0, 5 do rect(win, x, y + h - h * 0.3 * (i + 1) / 6, w, h * 0.05 + 1, K.bg, 0.12 * op) end
    for yy = y, y + h, S(4) do rect(win, x, yy, w, 1, K.g, 0.025 * op) end
end

-- background opacity of the Die or Die window (per player, this machine)
local BG_FILE = "CookieMission_dod.txt"
local BG_STEPS = { 1, 0.85, 0.7, 0.55, 0.4 }
local function bgLoad()
    CMDoDc.bg = 1
    pcall(function()
        local r = getFileReader(BG_FILE, false)
        if not r then return end
        local v = tonumber(r:readLine() or "")
        r:close()
        if v then CMDoDc.bg = math.max(0.4, math.min(1, v)) end
    end)
end

local function bgNext()
    local nxt = BG_STEPS[1]
    for i, v in ipairs(BG_STEPS) do
        if math.abs(v - (CMDoDc.bg or 1)) < 0.01 then nxt = BG_STEPS[CM.mod(i, #BG_STEPS) + 1] end
    end
    CMDoDc.bg = nxt
    pcall(function()
        local w = getFileWriter(BG_FILE, true, false)
        w:writeln(tostring(nxt))
        w:close()
    end)
end

local function sound(names)
    local p = CMC.player()
    if not p then return nil end
    for _, n in ipairs(names) do
        local ok, id = pcall(function()
            if p.playSoundLocal then return p:playSoundLocal(n) end
            return p:playSound(n)
        end)
        if ok and id and id ~= 0 then return id end
    end
    return nil
end

local function stopSound(id)
    local p = CMC.player()
    if not p or not id then return end
    local ok = pcall(function()
        local em = p:getEmitter()
        em:stopSoundLocal(id)
        em:stopSound(id)
    end)
    if not ok then pcall(function() p:stopOrTriggerSound(id) end) end
end

-- ===================================================================== the window
CMDoDc.Win = CMUI.Window:derive("CMDoD_Win")
local DW = CMDoDc.Win

function DW:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = "DIE OR DIE"
    o.tab = "teams"
    o.newLoc = nil
    o.newTier = 2
    o.newSize = 4
    o.admLoc = D.LOCS[1].id
    o.boardWeek = false
    o.boardView = "rank"
    o.boardSort = "w"
    o.histMine = false
    o.histPage = 1
    o.histSel = nil
    return o
end

function DW:drawFrame()
    local w, h = self.width, self.height
    if not CMDoDc.bg then bgLoad() end
    backdrop(self, 0, 0, w, h, CMDoDc.bg)
    border(self, 0, 0, w, h, K.line2, 1)
    local hh = self.headerH
    rect(self, 0, hh, w, 1, K.g, 0.25)
    crosshair(self, S(26), hh / 2, S(11), K.g, 2)
    CMUI.text(self, "DIE OR DIE", S(46), (hh - CMUI.fh(UIFont.Medium)) / 2, K.text, 1, UIFont.Medium)
    -- tabs
    local tx = S(46) + CMUI.tw(UIFont.Medium, "DIE OR DIE") + S(24)
    local tabs = { { "teams", T("IGUI_CM_Dod_tabTeams") }, { "board", "SCOREBOARD" } }
    if CMDoDc.snap and CMDoDc.snap.admin then tabs[#tabs + 1] = { "admin", T("IGUI_CM_Dod_tabAdmin") } end
    for _, tb in ipairs(tabs) do
        local tw = CMUI.tw(UIFont.Small, tb[2]) + S(24)
        local on = self.tab == tb[1]
        local over = self:hit(tx, S(8), tw, hh - S(16), function() self:setTab(tb[1]) end)
        if on then rect(self, tx, S(8), tw, hh - S(16), K.g, 1)
        elseif over then rect(self, tx, S(8), tw, hh - S(16), K.panel2, 1) end
        CMUI.textC(self, tb[2], tx + tw / 2, (hh - CMUI.fh(UIFont.Small)) / 2, on and K.ink or K.dim, 1, UIFont.Small)
        tx = tx + tw + S(4)
    end
    local cs = hh - S(16)
    local cx = w - cs - S(10)
    local over = self:hit(cx, S(8), cs, cs, function() self:close() end)
    rect(self, cx, S(8), cs, cs, over and K.red or K.panel, over and 0.6 or 0.9)
    border(self, cx, S(8), cs, cs, K.line2, 1)
    CMUI.textC(self, "x", cx + cs / 2, S(8) + (cs - CMUI.fh(UIFont.Small)) / 2 - 1, K.text, 1, UIFont.Small)
    -- background opacity: each press = the next step (100 / 85 / 70 / 55 / 40)
    local bl = T("IGUI_CM_Dod_bg") .. " " .. math.floor((CMDoDc.bg or 1) * 100 + 0.5) .. "%"
    local bw = CMUI.tw(UIFont.Small, bl) + S(24)
    local bx = cx - bw - S(8)
    local overB = self:hit(bx, S(8), bw, cs, bgNext)
    rect(self, bx, S(8), bw, cs, overB and K.panel2 or K.panel, 0.9)
    border(self, bx, S(8), bw, cs, K.line2, 1)
    CMUI.textC(self, bl, bx + bw / 2, S(8) + (cs - CMUI.fh(UIFont.Small)) / 2, K.dim, 1, UIFont.Small)
end

function DW:setTab(tab)
    self.tab = tab
    if tab == "board" then self:askBoard() end
end

-- the scoreboard page in view (ranking / match history); old data is dropped so it never shows under the wrong filter
function DW:askBoard()
    self.histPage, self.histSel = 1, nil
    if self.boardView == "hist" then
        CMDoDc.hist = nil
        CMC.send("dodBoard", { view = "hist", week = self.boardWeek, mine = self.histMine })
    else
        CMDoDc.board = nil
        CMC.send("dodBoard", { week = self.boardWeek, sort = self.boardSort })
    end
end

local function locState(sn, id)
    for _, l in ipairs(sn.locs or {}) do if l.id == id then return l end end
    return nil
end

local function locName(id) return D.LOC[id] and D.LOC[id].n or "?" end

-- 5 location thumbnails; pick(id) when clicked; selected = id
local function locRow(win, sn, x, y, w, selected, pick, mineId)
    local gap = S(8)
    local tw = (w - gap * 4) / 5
    local th = tw * 0.56
    for i, l in ipairs(D.LOCS) do
        local st = locState(sn, l.id) or {}
        local usable = st.ok and (not st.busy or l.id == mineId)
        local tx = x + (i - 1) * (tw + gap)
        win:hit(tx, y, tw, th, usable and pick and function() pick(l.id) end or nil, l.n)
        locPic(win, l.id, tx, y, tw, th, not usable, false)
        border(win, tx, y, tw, th, selected == l.id and K.g or K.line, 1)
        if selected == l.id then border(win, tx + 1, y + 1, tw - 2, th - 2, K.g, 1) end
        local tag = l.n
        if not st.ok then tag = T("IGUI_CM_Dod_notSet")
        elseif st.busy and l.id ~= mineId then tag = T("IGUI_CM_Dod_taken") end
        CMUI.textC(win, CMUI.fit(tag, UIFont.Small, tw), tx + tw / 2, y + th + S(4),
            selected == l.id and K.g or (usable and K.dim or K.faint), 1, UIFont.Small)
    end
    return th + S(4) + CMUI.fh(UIFont.Small)
end

local function tierRow(win, x, y, w, h, sel, pick)
    local gap = S(8)
    local bw = (w - gap * 2) / 3
    for i = 1, 3 do
        local on = sel == i
        mbtn(win, x + (i - 1) * (bw + gap), y, bw, h, D.TIER_TAG[i] .. "  -  " .. CM.dodCount(i), pick and function() pick(i) end,
            on and "on" or "ghost", { disabled = pick == nil and not on })
    end
end

-- not in a team: make one (left) or join an open one (right)
function DW:drawTeams(sn, x, y, w, h)
    local fs = UIFont.Small
    local lw = math.floor(w * 0.42)
    local ly = y
    CMUI.text(self, "SQUAD OPERATIONS", x, ly, K.g, 1, fs)
    ly = ly + CMUI.fh(fs) + S(4)
    CMUI.text(self, T("IGUI_CM_Dod_headline"), x, ly, K.text, 1, UIFont.Large)
    ly = ly + CMUI.fh(UIFont.Large) + S(6)
    CMUI.para(self, T("IGUI_CM_Dod_about2"), x, ly, lw, K.dim, fs, 3)
    ly = ly + (CMUI.fh(fs) + S(2)) * 3 + S(10)
    if not sn.on then
        CMUI.text(self, T("IGUI_CM_Dod_off_" .. tostring(sn.why or "off")), x, ly, K.red, 1, UIFont.Medium)
        return
    end
    if (sn.cool or 0) > 0 then
        CMUI.text(self, T("IGUI_CM_Dod_cool", CM.clock(left(sn.cool))), x, ly, K.amber, 1, UIFont.Medium)
        ly = ly + CMUI.fh(UIFont.Medium) + S(10)
    end
    -- new team: spot, difficulty, size
    if self.newLoc then
        local st = locState(sn, self.newLoc)
        if not st or not st.ok or st.busy then self.newLoc = nil end
    end
    if not self.newLoc then
        for _, l in ipairs(sn.locs or {}) do if l.ok and not l.busy then self.newLoc = l.id; break end end
    end
    CMUI.text(self, T("IGUI_CM_Dod_pickLoc"), x, ly, K.g, 1, fs)
    ly = ly + CMUI.fh(fs) + S(4)
    ly = ly + locRow(self, sn, x, ly, lw, self.newLoc, function(id) self.newLoc = id end) + S(10)
    tierRow(self, x, ly, lw, S(34), self.newTier, function(i) self.newTier = i end)
    ly = ly + S(42)
    CMUI.cycle(self, x, ly, S(150), S(34), T("IGUI_CM_Dod_size", self.newSize),
        function() self.newSize = D.SIZES[CM.mod(self:sizeIdx() - 2, #D.SIZES) + 1] end,
        function() self.newSize = D.SIZES[CM.mod(self:sizeIdx(), #D.SIZES) + 1] end)
    mbtn(self, x + S(160), ly - S(4), lw - S(160), S(42), "+ " .. T("IGUI_CM_Dod_make"), function()
        CMC.send("dodNew", { loc = self.newLoc, tier = self.newTier, size = self.newSize })
    end, "go", { disabled = not self.newLoc or (sn.cool or 0) > 0, font = UIFont.Medium })
    -- invites
    local rx, rw = x + lw + S(28), w - lw - S(28)
    local ry = y
    for _, iv in ipairs(sn.inv or {}) do
        rect(self, rx, ry, rw, S(40), K.panel2, 0.95)
        border(self, rx, ry, rw, S(40), K.amber, 1)
        CMUI.text(self, CMUI.fit(T("IGUI_CM_Dod_invited2", iv.by, locName(iv.loc)), fs, rw - S(200)), rx + S(10), ry + (S(40) - CMUI.fh(fs)) / 2, K.amber)
        mbtn(self, rx + rw - S(186), ry + S(6), S(88), S(28), T("IGUI_CM_Sq_yes"), function() CMC.send("dodAnswer", { id = iv.id, yes = true }) end, "go")
        mbtn(self, rx + rw - S(94), ry + S(6), S(88), S(28), T("IGUI_CM_Sq_no"), function() CMC.send("dodAnswer", { id = iv.id, yes = false }) end, "ghost")
        ry = ry + S(46)
    end
    -- open teams
    CMUI.text(self, T("IGUI_CM_Dod_open"), rx, ry, K.g, 1, fs)
    rect(self, rx + CMUI.tw(fs, T("IGUI_CM_Dod_open")) + S(10), ry + CMUI.fh(fs) / 2, rw, 1, K.g, 0.2)
    ry = ry + CMUI.fh(fs) + S(8)
    local ch = S(92)
    if #(sn.teams or {}) == 0 then
        CMUI.text(self, T("IGUI_CM_Dod_noTeams"), rx, ry, K.faint)
    end
    for _, tm in ipairs(sn.teams or {}) do
        if ry + ch > y + h then break end
        local busy = tm.phase ~= "room"
        rect(self, rx, ry, rw, ch, K.panel, 0.92)
        local pw = ch * 1.6
        locPic(self, tm.loc, rx, ry, pw, ch, busy, false)
        border(self, rx, ry, rw, ch, busy and K.line or (tm.n < tm.size and K.line2 or K.line), 1)
        local ix = rx + pw + S(14)
        CMUI.text(self, string.upper(locName(tm.loc)), ix, ry + S(10), busy and K.dim or K.text, 1, UIFont.Medium)
        local tag = D.TIER_TAG[tm.tier] .. " - " .. CM.dodCount(tm.tier)
        local tgx = ix + CMUI.tw(UIFont.Medium, string.upper(locName(tm.loc))) + S(10)
        border(self, tgx, ry + S(12), CMUI.tw(fs, tag) + S(12), CMUI.fh(fs) + S(4), TIER_COL[tm.tier], 1)
        CMUI.text(self, tag, tgx + S(6), ry + S(14), TIER_COL[tm.tier], 1, fs)
        local sub = busy and T("IGUI_CM_Dod_fighting", tm.lead or "?", CM.clock(left(tm.left))) or T("IGUI_CM_Dod_leadBy", tm.lead or "?")
        CMUI.text(self, CMUI.fit(sub, fs, rw - pw - S(180)), ix, ry + S(10) + CMUI.fh(UIFont.Medium) + S(2), K.dim, 1, fs)
        if not busy then
            for i = 1, tm.size do
                rect(self, ix + (i - 1) * S(22), ry + ch - S(20), S(18), S(6), i <= tm.n and K.g or K.line, 1)
            end
            CMUI.text(self, tm.n .. " / " .. tm.size, ix + tm.size * S(22) + S(6), ry + ch - S(24), K.dim, 1, fs)
            mbtn(self, rx + rw - S(130), ry + (ch - S(40)) / 2, S(116), S(40), T("IGUI_CM_Sq_join"), function()
                CMC.send("dodJoin", { id = tm.id })
            end, "go", { disabled = tm.n >= tm.size or (sn.cool or 0) > 0 })
        else
            CMUI.textR(self, T("IGUI_CM_Dod_taken"), rx + rw - S(16), ry + (ch - CMUI.fh(fs)) / 2, K.faint, 1, fs)
        end
        ry = ry + ch + S(8)
    end
end

function DW:sizeIdx()
    for i, n in ipairs(D.SIZES) do if n == self.newSize then return i end end
    return 2
end

-- in a team, before deploying
function DW:drawRoom(sn, tm, x, y, w, h)
    local fs = UIFont.Small
    local lw = math.floor(w * 0.52)
    local lead = tm.leadMe
    CMUI.text(self, T("IGUI_CM_Dod_spot"), x, y, K.g, 1, fs)
    if tm.closeLeft then CMUI.textR(self, T("IGUI_CM_Dod_closes", CM.clock(left(tm.closeLeft))), x + lw, y, K.dim, 1, fs) end
    local py = y + CMUI.fh(fs) + S(4)
    local ph = math.floor(lw * 0.40)
    locPic(self, tm.loc, x, py, lw, ph, false, true)
    border(self, x, py, lw, ph, K.g, 1)
    rect(self, x, py, S(16), S(3), K.g, 1); rect(self, x, py, S(3), S(16), K.g, 1)
    rect(self, x + lw - S(16), py + ph - S(3), S(16), S(3), K.g, 1); rect(self, x + lw - S(3), py + ph - S(16), S(3), S(16), K.g, 1)
    CMUI.text(self, string.upper(locName(tm.loc)), x + S(14), py + ph - CMUI.fh(UIFont.Large) - S(12), K.text, 1, UIFont.Large)
    py = py + ph + S(10)
    py = py + locRow(self, sn, x, py, lw, tm.loc, lead and function(id) CMC.send("dodSet", { loc = id }) end or nil, tm.loc) + S(10)
    CMUI.text(self, T("IGUI_CM_Dod_diff"), x, py, K.g, 1, fs)
    py = py + CMUI.fh(fs) + S(4)
    tierRow(self, x, py, lw, S(38), tm.tier, lead and function(i) CMC.send("dodSet", { tier = i }) end or nil)
    -- members
    local rx, rw = x + lw + S(28), w - lw - S(28)
    local ry = y
    CMUI.text(self, T("IGUI_CM_Dod_members"), rx, ry, K.g, 1, fs)
    CMUI.text(self, #tm.members .. " / " .. tm.size, rx + CMUI.tw(fs, T("IGUI_CM_Dod_members")) + S(10), ry - S(3), K.text, 1, UIFont.Medium)
    if lead then
        CMUI.cycle(self, rx + rw - S(130), ry - S(4), S(130), S(26), T("IGUI_CM_Dod_size", tm.size),
            function() local i = 1; for j, n in ipairs(D.SIZES) do if n == tm.size then i = j end end
                CMC.send("dodSet", { size = D.SIZES[CM.mod(i - 2, #D.SIZES) + 1] }) end,
            function() local i = 1; for j, n in ipairs(D.SIZES) do if n == tm.size then i = j end end
                CMC.send("dodSet", { size = D.SIZES[CM.mod(i, #D.SIZES) + 1] }) end)
    end
    ry = ry + CMUI.fh(UIFont.Medium) + S(8)
    local rh = S(44)
    local me = nil
    local myKey = CM.ukey(CMC.player() and CMC.player():getUsername() or "")
    for _, m in ipairs(tm.members) do
        if m.k == myKey then me = m end
        local ok = m.ready or m.lead
        rect(self, rx, ry, rw, rh, K.panel, 0.94)
        rect(self, rx, ry, S(3), rh, ok and K.g or K.amber, 1)
        rect(self, rx + S(12), ry + S(8), rh - S(16), rh - S(16), K.line, 1)
        tex(self, "dod_avatar", rx + S(12), ry + S(8), rh - S(16), rh - S(16), 0.8, K.dim)
        CMUI.text(self, CMUI.fit(m.n, UIFont.Medium, rw - S(200)), rx + rh + S(4), ry + S(4), K.text, 1, UIFont.Medium)
        if m.lead then CMUI.text(self, T("IGUI_CM_Dod_leadTag"), rx + rh + S(4), ry + S(4) + CMUI.fh(UIFont.Medium), K.g, 1, fs) end
        CMUI.textR(self, ok and "READY" or T("IGUI_CM_Dod_notReady"), rx + rw - (lead and not m.lead and S(64) or S(12)),
            ry + (rh - CMUI.fh(fs)) / 2, ok and K.g or K.amber, 1, fs)
        if lead and not m.lead then
            mbtn(self, rx + rw - S(56), ry + S(9), S(48), rh - S(18), T("IGUI_CM_Sq_kick"), function() CMC.send("dodKick", { who = m.k }) end, "ghost")
        end
        ry = ry + rh + S(6)
    end
    -- invite (leader)
    if lead and tm.free then
        local free = tm.free
        local cols = 2
        local bw = (rw - S(6)) / cols
        local i = 0
        CMUI.text(self, T("IGUI_CM_Sq_invite"), rx, ry, K.dim, 1, fs)
        ry = ry + CMUI.fh(fs) + S(4)
        for _, f in ipairs(free) do
            local cy = ry + math.floor(i / cols) * S(30)
            if cy + S(26) > y + h - S(64) then break end
            mbtn(self, rx + CM.mod(i, cols) * (bw + S(6)), cy, bw, S(26), (f.inv and (f.n .. " - " .. T("IGUI_CM_Sq_sent")) or ("+ " .. f.n)),
                function() CMC.send("dodInvite", { who = f.k }) end, "ghost", { disabled = f.inv })
            i = i + 1
        end
        if #free == 0 then CMUI.text(self, T("IGUI_CM_Sq_nofree"), rx, ry, K.faint, 1, fs) end
    end
    -- actions
    local by = y + h - S(48)
    if lead then
        mbtn(self, rx, by, S(120), S(48), T("IGUI_CM_Dod_disband"), function() CMC.send("dodDisband", {}) end, "ghost")
        mbtn(self, rx + S(128), by, rw - S(128), S(48), "DEPLOY", function() CMC.send("dodDeploy", {}) end, "go", { font = UIFont.Large })
    else
        mbtn(self, rx, by, S(120), S(48), T("IGUI_CM_Sq_leave"), function() CMC.send("dodLeave", {}) end, "ghost")
        local rdy = me and me.ready
        mbtn(self, rx + S(128), by, rw - S(128), S(48), rdy and "READY  OK" or "READY", function() CMC.send("dodReady", { yes = not rdy }) end,
            rdy and "on" or "go", { font = UIFont.Large })
    end
end

-- 12345 -> "12,345"
local function num(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s
    while true do
        local k
        out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return out
end

-- epoch seconds -> "dd/mm hh:mm" in the server's time zone
local function stamp(ts)
    local lt = math.floor(CM.num(ts, 0)) + math.floor(CM.num(CM.sv("UtcOffset", 7), 7) * 3600)
    local day = math.floor(lt / 86400)
    local _, m, d = CM.civil(day)
    local sec = lt - day * 86400
    return CM.pad2(d) .. "/" .. CM.pad2(m) .. " " .. CM.pad2(math.floor(sec / 3600)) .. ":" .. CM.pad2(math.floor(CM.mod(sec, 3600) / 60))
end

-- one table row: cols = { { label, share, right aligned } }; returns the x of each column
local function tableRow(win, cols, vals, x, iw, yy, colors, font)
    local xx = x
    for i, c in ipairs(cols) do
        local cwid = iw * c[2]
        local v = tostring(vals[i] or "")
        if c[3] then CMUI.textR(win, v, xx + cwid - S(8), yy, colors[i] or K.text, 1, font)
        else CMUI.text(win, CMUI.fit(v, font, cwid - S(6)), xx, yy, colors[i] or K.text, 1, font) end
        xx = xx + cwid
    end
end

function DW:drawBoard(x, y, w, h)
    -- page (ranking / match history) on the left, all time / this week on the right
    local function view(v) return function() self.boardView = v; self:askBoard() end end
    mbtn(self, x, y - S(4), S(140), S(28), T("IGUI_CM_Dod_sbRank"), view("rank"), self.boardView == "rank" and "on" or "ghost")
    mbtn(self, x + S(146), y - S(4), S(160), S(28), T("IGUI_CM_Dod_sbHist"), view("hist"), self.boardView == "hist" and "on" or "ghost")
    if self.boardView == "hist" then
        mbtn(self, x + S(330), y - S(4), S(110), S(28), T("IGUI_CM_Dod_sbAll"), function() self.histMine = false; self:askBoard() end,
            self.histMine and "ghost" or "on")
        mbtn(self, x + S(446), y - S(4), S(140), S(28), T("IGUI_CM_Dod_sbMyMatches"), function() self.histMine = true; self:askBoard() end,
            self.histMine and "on" or "ghost")
    end
    mbtn(self, x + w - S(250), y - S(4), S(120), S(28), T("IGUI_CM_Dod_allTime"), function() self.boardWeek = false; self:askBoard() end,
        self.boardWeek and "ghost" or "on")
    mbtn(self, x + w - S(124), y - S(4), S(124), S(28), T("IGUI_CM_Dod_thisWeek"), function() self.boardWeek = true; self:askBoard() end,
        self.boardWeek and "on" or "ghost")
    if self.boardView == "hist" then
        if self.histSel then self:drawMatch(self.histSel, x, y + S(36), w, h - S(36))
        else self:drawHist(x, y + S(36), w, h - S(36)) end
    else
        self:drawRank(x, y + S(36), w, h - S(36))
    end
end

function DW:drawRank(x, y, w, h)
    local fs = UIFont.Small
    local b = CMDoDc.board
    -- a late answer for the filter clicked before counts as not loaded yet
    if b and (b.week ~= (self.boardWeek == true) or b.sort ~= self.boardSort) then b = nil end
    if not b then CMUI.text(self, T("IGUI_CM_Loading"), x, y, K.dim); return end
    local cw = (w - S(30)) / 4
    local stats = { { T("IGUI_CM_Dod_sbTotal"), num(b.total), K.text }, { T("IGUI_CM_Dod_sbMatches"), num(b.matches), K.text },
        { T("IGUI_CM_Dod_sbDmg"), num(b.dmg), K.amber }, { T("IGUI_CM_Dod_sbMine"), b.mine and ("#" .. b.mine) or "-", K.g } }
    for i, st in ipairs(stats) do
        local sx = x + (i - 1) * (cw + S(10))
        rect(self, sx, y, cw, S(64), K.panel, 0.92)
        border(self, sx, y, cw, S(64), i == 4 and K.g or K.line, 1)
        CMUI.text(self, st[1], sx + S(12), y + S(8), i == 4 and K.g or K.faint, 1, fs)
        CMUI.text(self, st[2], sx + S(12), y + S(8) + CMUI.fh(fs), st[3], 1, UIFont.Large)
    end
    local ty = y + S(78)
    -- { label, share, right aligned, sort key }
    local cols = { { "#", 0.05 }, { T("IGUI_CM_Dod_sbPlayer"), 0.24 }, { T("IGUI_CM_Dod_sbWins"), 0.13, true },
        { T("IGUI_CM_Dod_sbSum"), 0.08, true, "w" }, { "KILL", 0.08, true, "k" }, { "DAMAGE", 0.12, true, "d" },
        { "ASSIST", 0.09, true }, { "MVP R/V/E", 0.13, true }, { "MVP", 0.08, true, "mvp" } }
    rect(self, x, ty, w, h - (ty - y), K.panel, 0.9)
    border(self, x, ty, w, h - (ty - y), K.line, 1)
    local cx = x + S(14)
    local iw = w - S(28)
    local rowH = S(34)
    -- header: the green ones sort the table (the one in use is underlined)
    local hdr, hc = {}, {}
    local hx = cx
    local hy = ty + S(10)
    for i, c in ipairs(cols) do
        hdr[i] = c[1]
        local cwid = iw * c[2]
        if c[4] then
            local on = self.boardSort == c[4]
            local over = self:hit(hx, hy - S(4), cwid, CMUI.fh(fs) + S(8), function() self.boardSort = c[4]; self:askBoard() end)
            hc[i] = (on or over) and K.g or K.gDim
            if on then rect(self, hx + S(8), hy + CMUI.fh(fs) + S(2), cwid - S(16), S(2), K.g, 1) end
        else
            hc[i] = K.faint
        end
        hx = hx + cwid
    end
    tableRow(self, cols, hdr, cx, iw, hy, hc, fs)
    local function line(i, r, ry)
        if r.me then rect(self, x + 1, ry - S(6), w - 2, rowH, K.g, 0.10); rect(self, x + 1, ry - S(6), S(3), rowH, K.g, 1) end
        local top = i <= 3
        local mt = r.mt or { 0, 0, 0 }
        tableRow(self, cols, { CM.pad2(i), r.n, r.w[1] .. "/" .. r.w[2] .. "/" .. r.w[3], r.t, num(r.kills), num(r.dmg), num(r.ast),
            mt[1] .. "/" .. mt[2] .. "/" .. mt[3], r.mvp }, cx, iw, ry,
            { top and K.g or K.dim, K.text, K.dim, K.text, K.text, K.amber, K.dim, K.dim, K.g }, top and UIFont.Medium or fs)
    end
    local ry = hy + CMUI.fh(fs) + S(12)
    -- my row stays at the bottom when I am not in the top 20
    local bottom = y + h - (b.meRow and rowH or 0)
    for i, r in ipairs(b.rows or {}) do
        if ry + rowH > bottom then break end
        line(i, r, ry)
        ry = ry + rowH
    end
    if b.meRow then
        rect(self, x + S(14), bottom - S(8), w - S(28), 1, K.line2, 1)
        line(b.mine or 0, b.meRow, bottom)
    end
    if #(b.rows or {}) == 0 then CMUI.text(self, T("IGUI_CM_Dod_sbEmpty"), cx, ry, K.faint) end
end

local function resText(res) return res == "win" and "WIN" or "LOSE" end
local function resCol(res) return res == "win" and K.g or K.red end

function DW:drawHist(x, y, w, h)
    local fs = UIFont.Small
    local hb = CMDoDc.hist
    if hb and (hb.week ~= (self.boardWeek == true) or hb.mineOnly ~= (self.histMine == true)) then hb = nil end
    if not hb then CMUI.text(self, T("IGUI_CM_Loading"), x, y, K.dim); return end
    local list = hb.hist or {}
    local cols = { { T("IGUI_CM_Dod_sbTime"), 0.14 }, { T("IGUI_CM_Dod_sbPlace"), 0.22 }, { T("IGUI_CM_Dod_sbTier"), 0.11 },
        { T("IGUI_CM_Dod_sbRes"), 0.09 }, { T("IGUI_CM_Dod_sbDur"), 0.10, true }, { "MVP (KILL / DAMAGE)", 0.30 }, { "", 0.04, true } }
    rect(self, x, y, w, h, K.panel, 0.9)
    border(self, x, y, w, h, K.line, 1)
    local cx, iw = x + S(14), w - S(28)
    local hdr = {}
    for i, c in ipairs(cols) do hdr[i] = c[1] end
    local hy = y + S(10)
    tableRow(self, cols, hdr, cx, iw, hy, { K.faint, K.faint, K.faint, K.faint, K.faint, K.g, K.faint }, fs)
    if #list == 0 then CMUI.text(self, T("IGUI_CM_Dod_sbNoHist"), cx, hy + S(40), K.faint); return end
    local rowH = S(40)
    local top = hy + CMUI.fh(fs) + S(12)
    local per = math.max(1, math.floor((y + h - S(44) - top) / rowH))
    local pages = math.max(1, math.ceil(#list / per))
    self.histPage = math.max(1, math.min(self.histPage or 1, pages))
    local ry = top
    for i = (self.histPage - 1) * per + 1, math.min(#list, self.histPage * per) do
        local e = list[i]
        local mv = nil
        for _, m in ipairs(e.m or {}) do if m.mvp then mv = m end end
        local over = self:hit(x + 1, ry - S(8), w - 2, rowH - S(2), function() self.histSel = e end)
        if over then rect(self, x + 1, ry - S(8), w - 2, rowH - S(2), K.panel2, 1) end
        if e.mine then rect(self, x + 1, ry - S(8), S(3), rowH - S(2), K.g, 1) end
        tableRow(self, cols, { stamp(e.ts), D.LOC[e.loc] and D.LOC[e.loc].n or "?", D.TIER_TAG[e.tier] or "?", resText(e.res), CM.clock(e.dur),
            mv and (mv.n .. "  (" .. mv.kills .. " / " .. num(mv.dmg) .. ")") or "-", ">" }, cx, iw, ry,
            { K.dim, K.text, TIER_COL[e.tier] or K.dim, resCol(e.res), K.dim, mv and K.g or K.faint, over and K.g or K.faint }, fs)
        ry = ry + rowH
    end
    -- pages
    local py = y + h - S(38)
    mbtn(self, cx, py, S(44), S(28), "<", function() self.histPage = self.histPage - 1 end, "ghost", { disabled = self.histPage <= 1 })
    CMUI.textC(self, self.histPage .. " / " .. pages, cx + S(90), py + (S(28) - CMUI.fh(fs)) / 2, K.dim, 1, fs)
    mbtn(self, cx + S(136), py, S(44), S(28), ">", function() self.histPage = self.histPage + 1 end, "ghost", { disabled = self.histPage >= pages })
end

-- one match: everyone's numbers, the MVP on top
function DW:drawMatch(e, x, y, w, h)
    local fs = UIFont.Small
    mbtn(self, x, y, S(110), S(30), T("IGUI_CM_Dod_sbBack"), function() self.histSel = nil end, "ghost")
    local hx = x + S(126)
    local hy = y + (S(30) - CMUI.fh(UIFont.Medium)) / 2
    local loc = D.LOC[e.loc] and D.LOC[e.loc].n or "?"
    CMUI.text(self, loc, hx, hy, K.text, 1, UIFont.Medium)
    hx = hx + CMUI.tw(UIFont.Medium, loc) + S(16)
    local tag = D.TIER_TAG[e.tier] or "?"
    CMUI.text(self, tag, hx, hy, TIER_COL[e.tier] or K.dim, 1, UIFont.Medium)
    hx = hx + CMUI.tw(UIFont.Medium, tag) + S(16)
    CMUI.text(self, resText(e.res), hx, hy, resCol(e.res), 1, UIFont.Medium)
    CMUI.textR(self, stamp(e.ts) .. "   " .. T("IGUI_CM_Dod_sbDur") .. " " .. CM.clock(e.dur), x + w, hy, K.dim, 1, fs)
    local ty = y + S(44)
    rect(self, x, ty, w, h - (ty - y), K.panel, 0.9)
    border(self, x, ty, w, h - (ty - y), K.line, 1)
    local cols = { { T("IGUI_CM_Dod_sbPlayer"), 0.36 }, { T("IGUI_CM_Dod_sbStatus"), 0.16 }, { "KILL", 0.14, true },
        { "DAMAGE", 0.18, true }, { "ASSIST", 0.16, true } }
    local cx, iw = x + S(14), w - S(28)
    local hdr = {}
    for i, c in ipairs(cols) do hdr[i] = c[1] end
    local ry = ty + S(10)
    tableRow(self, cols, hdr, cx, iw, ry, { K.faint, K.faint, K.faint, K.faint, K.faint }, fs)
    ry = ry + CMUI.fh(fs) + S(14)
    local ms = {}
    for _, m in ipairs(e.m or {}) do ms[#ms + 1] = m end
    table.sort(ms, function(a, b)
        if a.mvp ~= b.mvp then return a.mvp == true end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.dmg > b.dmg
    end)
    local rowH = S(40)
    for _, m in ipairs(ms) do
        if ry + rowH > y + h then break end
        if m.mvp then
            rect(self, x + 1, ry - S(8), w - 2, rowH - S(2), { 0.09, 0.13, 0.06 }, 1)
            border(self, x + 1, ry - S(8), w - 2, rowH - S(2), K.g, 1)
        elseif m.me then
            rect(self, x + 1, ry - S(8), w - 2, rowH - S(2), K.g, 0.10)
        end
        local f = m.mvp and UIFont.Medium or fs
        local name = m.mvp and ("MVP  " .. m.n) or m.n
        tableRow(self, cols, { name, T("IGUI_CM_Dod_st_" .. tostring(m.st)), m.kills, num(m.dmg), m.ast }, cx, iw, ry,
            { m.mvp and K.g or K.text, m.st == "in" and K.dim or K.faint, K.text, K.amber, K.dim }, f)
        ry = ry + rowH
    end
end

function DW:drawAdmin(sn, x, y, w, h)
    local fs = UIFont.Small
    local lw = math.floor(w * 0.40)
    local ly = y
    CMUI.para(self, T("IGUI_CM_Dod_admHelp"), x, ly, w, K.dim, fs, 2)
    ly = ly + (CMUI.fh(fs) + S(2)) * 2 + S(8)
    for _, l in ipairs(D.LOCS) do
        local st = locState(sn, l.id) or {}
        local on = self.admLoc == l.id
        local rh = S(48)
        self:hit(x, ly, lw, rh, function() self.admLoc = l.id end)
        rect(self, x, ly, lw, rh, on and K.panel2 or K.panel, 0.94)
        border(self, x, ly, lw, rh, on and K.g or K.line, 1)
        locPic(self, l.id, x + S(6), ly + S(6), (rh - S(12)) * 1.6, rh - S(12), false, false)
        CMUI.text(self, l.n, x + S(14) + (rh - S(12)) * 1.6, ly + (rh - CMUI.fh(UIFont.Medium)) / 2, K.text, 1, UIFont.Medium)
        local tag, col = T("IGUI_CM_Dod_notSet"), K.faint
        if st.ok then tag, col = T("IGUI_CM_Dod_ready"), K.g elseif st.safe or #(st.spawns or {}) > 0 then tag, col = T("IGUI_CM_Dod_partial"), K.amber end
        CMUI.textR(self, tag, x + lw - S(10), ly + (rh - CMUI.fh(fs)) / 2, col, 1, fs)
        ly = ly + rh + S(6)
    end
    -- the selected spot
    local st = locState(sn, self.admLoc) or {}
    local rx, rw = x + lw + S(24), w - lw - S(24)
    local ry = y + (CMUI.fh(fs) + S(2)) * 2 + S(8)
    CMUI.text(self, locName(self.admLoc), rx, ry, K.text, 1, UIFont.Large)
    ry = ry + CMUI.fh(UIFont.Large) + S(8)
    local safeS = T("IGUI_CM_Dod_noSafe")
    if st.safe then safeS = T("IGUI_CM_Dod_safeIs", st.safe.x1 .. "," .. st.safe.y1, st.safe.x2 .. "," .. st.safe.y2, st.safe.z or 0) end
    if st.c1 then safeS = T("IGUI_CM_Dod_c1Is", st.c1.x, st.c1.y) end
    CMUI.text(self, CMUI.fit(safeS, fs, rw), rx, ry, st.safe and K.g or K.amber, 1, fs)
    ry = ry + CMUI.fh(fs) + S(8)
    local bw = (rw - S(8)) / 2
    mbtn(self, rx, ry, bw, S(36), st.c1 and T("IGUI_CM_Dod_corner2") or T("IGUI_CM_Dod_corner1"), function()
        CMC.send("dodCorner", { loc = self.admLoc })
    end, "on")
    mbtn(self, rx + bw + S(8), ry, bw, S(36), T("IGUI_CM_Dod_addSpawn"), function() CMC.send("dodSpawn", { loc = self.admLoc }) end, "red")
    ry = ry + S(44)
    CMUI.text(self, T("IGUI_CM_Dod_spawns", #(st.spawns or {})), rx, ry, K.dim, 1, fs)
    ry = ry + CMUI.fh(fs) + S(4)
    for i, sp in ipairs(st.spawns or {}) do
        if ry + S(24) > y + h - S(50) then break end
        CMUI.text(self, "SP-" .. i .. "   " .. sp.x .. ", " .. sp.y .. ", " .. (sp.z or 0), rx + S(6), ry + S(4), K.text, 1, fs)
        mbtn(self, rx + rw - S(60), ry, S(60), S(24), T("IGUI_CM_Dod_del"), function() CMC.send("dodSpawnDel", { loc = self.admLoc, i = i }) end, "ghost")
        ry = ry + S(28)
    end
    local by = y + h - S(40)
    mbtn(self, rx, by, bw, S(40), T("IGUI_CM_Dod_goSee"), function() CMC.send("dodLocGo", { loc = self.admLoc }) end, "ghost")
    mbtn(self, rx + bw + S(8), by, bw, S(40), T("IGUI_CM_Dod_clearLoc"), function() CMC.send("dodLocClear", { loc = self.admLoc }) end, "red")
end

function DW:drawBody()
    local pad = S(24)
    local x, w = pad, self.width - pad * 2
    local y = self.headerH + S(18)
    local h = self.height - y - pad
    local sn = CMDoDc.snap
    if not sn then CMUI.text(self, T("IGUI_CM_Loading"), x, y, K.dim, 1, UIFont.Medium); return end
    if self.tab == "admin" and sn.admin then self:drawAdmin(sn, x, y, w, h); return end
    if self.tab == "board" then self:drawBoard(x, y, w, h); return end
    local tm = sn.team
    if tm and tm.phase == "room" then self:drawRoom(sn, tm, x, y, w, h)
    elseif tm and tm.phase ~= "over" then
        CMUI.text(self, T("IGUI_CM_Dod_inMatch"), x, y, K.g, 1, UIFont.Large)
        mbtn(self, x, y + S(50), S(320), S(44), T("IGUI_CM_Dod_quit"), function() CMC.send("dodLeave", {}) end, "red")
    else
        self:drawTeams(sn, x, y, w, h)
    end
end

function DW:onClosed()
    CMDoDc.win = nil
    CMC.send("dodClose", {})
end

function CMDoDc.open()
    if CMDoDc.win then CMDoDc.win:bringToTop(); return end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(1180, 680)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = DW:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    win:show()
    CMDoDc.win = win
    CMC.send("dodOpen", {})
end

-- admin: the safe area and spawn points of the selected spot drawn on the ground while the admin tab is open
local function adminOverlay()
    local win = CMDoDc.win
    local sn = CMDoDc.snap
    if not win or win.tab ~= "admin" or not sn or not sn.admin then return end
    local st = locState(sn, win.admLoc)
    if not st then return end
    local p = CMC.player()
    if not p then return end
    local pz = math.floor(p:getZ())
    if st.safe and (st.safe.z or 0) == pz then
        addAreaHighlight(st.safe.x1, st.safe.y1, st.safe.x2 + 1, st.safe.y2 + 1, pz, K.g[1], K.g[2], K.g[3], 0.30)
    end
    if st.c1 and st.c1.z == pz then addAreaHighlight(st.c1.x, st.c1.y, st.c1.x + 1, st.c1.y + 1, pz, K.amber[1], K.amber[2], K.amber[3], 0.6) end
    local zoom = getCore():getZoom(0)
    for i, sp in ipairs(st.spawns or {}) do
        if (sp.z or 0) == pz then
            addAreaHighlight(sp.x - 1, sp.y - 1, sp.x + 2, sp.y + 2, pz, K.red[1], K.red[2], K.red[3], 0.45)
            local sx = isoToScreenX(0, sp.x + 0.5, sp.y + 0.5, pz)
            local sy = isoToScreenY(0, sp.x + 0.5, sp.y + 0.5, pz) - 40 / zoom
            getTextManager():DrawStringCentre(UIFont.Medium, sx, sy, "SP-" .. i, K.red[1], K.red[2], K.red[3], 1)
        end
    end
end
Events.OnPreUIDraw.Add(function()
    local ok, err = pcall(adminOverlay)
    if not ok then CM.log("dod admin overlay error: " .. tostring(err)) end
end)

-- ===================================================================== floating button (right edge, drag up / down)
CMDoDc.Fab = ISPanel:derive("CMDoD_Fab")
local FB = CMDoDc.Fab

function FB:new()
    local size = S(46)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel.new(self, sw - size - S(14), math.floor(sh * 0.36), size, size)
    o.background = false
    o.moveWithMouse = false
    o.size = size
    o.internal = "Die or Die"
    o.tex = CMUI.tex("dod_avatar")
    return o
end

function FB:onMouseDown(x, y)
    self.down = { y = y, my = getMouseY(), moved = false }
    return true
end

function FB:onMouseMove(dx, dy)
    local d = self.down
    if not d then return end
    local ny = getMouseY() - d.y
    if math.abs(getMouseY() - d.my) > 4 then d.moved = true end
    if d.moved then
        local sh = getCore():getScreenHeight()
        self:setY(math.max(0, math.min(sh - self.size, ny)))
    end
end
FB.onMouseMoveOutside = FB.onMouseMove

function FB:onMouseUp(x, y)
    local d = self.down
    self.down = nil
    if d and not d.moved then
        if CMDoDc.win then CMDoDc.win:close() else CMDoDc.open() end
    end
    return true
end

function FB:onMouseUpOutside() self.down = nil end

-- the Dock's click when the button is grouped there
function FB:forceClick()
    if CMDoDc.win then CMDoDc.win:close() else CMDoDc.open() end
end

function FB:prerender() end

function FB:render()
    local s = self.size
    local sn = CMDoDc.snap
    local over = self:isMouseOver()
    local cool = sn and (sn.cool or 0) > 0
    local open = 0
    for _, tm in ipairs((sn and sn.teams) or {}) do if tm.phase == "room" then open = open + 1 end end
    local lit = (over or open > 0 or team() ~= nil) and not cool
    local pulse = 0.75 + 0.25 * math.sin(CMC.ms() / 400)
    local bg = lit and K.g or K.ink
    rect(self, 0, 0, s, s, bg, lit and (open > 0 and not over and pulse or 1) or 0.92)
    border(self, 0, 0, s, s, cool and K.line or K.line2, 1)
    rect(self, s - S(8), s - S(2), S(8), S(2), K.bg, 1)
    rect(self, s - S(2), s - S(8), S(2), S(8), K.bg, 1)
    crosshair(self, s / 2, s / 2, s * 0.32, lit and K.ink or (cool and K.faint or K.g), 2)
    if over or (open > 0 and not cool) then
        -- the label slides out to the left
        local line1 = "DIE OR DIE"
        local line2 = T("IGUI_CM_Dod_fabIdle")
        local c2 = K.g
        if cool then line2, c2 = T("IGUI_CM_Dod_fabCool", CM.clock(left(sn.cool))), K.amber
        elseif team() then line2 = T("IGUI_CM_Dod_fabTeam")
        elseif open > 0 then line2 = T("IGUI_CM_Dod_fabOpen", open) end
        local lw = math.max(CMUI.tw(UIFont.Small, line1), CMUI.tw(UIFont.Small, line2)) + S(20)
        rect(self, -lw, 0, lw, s, K.ink, 0.94)
        border(self, -lw, 0, lw + 1, s, K.line2, 1)
        local fh = CMUI.fh(UIFont.Small)
        CMUI.text(self, line1, -lw + S(10), s / 2 - fh, K.text, 1, UIFont.Small)
        CMUI.text(self, line2, -lw + S(10), s / 2, c2, 1, UIFont.Small)
    end
end

local function fabTick()
    local want = CM.dodOn() and CMC.player() ~= nil
    if want and not CMDoDc.fab then
        local f = FB:new()
        f:initialise(); f:instantiate(); f:addToUIManager(); f:setVisible(true)
        CMDoDc.fab = f
        -- the button needs the cooldown / open teams: one look at the snapshot
        CMC.send("dodOpen", {})
        if not CMDoDc.win then CMC.send("dodClose", {}) end
        CMDoDc.peek = CMC.ms()
    elseif not want and CMDoDc.fab then
        CMDoDc.fab:removeFromUIManager()
        CMDoDc.fab = nil
    end
    -- refresh the button's view now and then without keeping a watch
    if CMDoDc.fab and not CMDoDc.win and CMC.ms() - (CMDoDc.peek or 0) > 30000 then
        CMDoDc.peek = CMC.ms()
        CMC.send("dodOpen", {})
        CMC.send("dodClose", {})
    end
end

-- ===================================================================== insertion screen (full screen) + radio arrival
CMDoDc.Screen = ISPanel:derive("CMDoD_Screen")
local SC = CMDoDc.Screen

function SC:new()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel.new(self, 0, 0, sw, sh)
    o.background = false
    o.moveWithMouse = false
    return o
end

function SC:prerender() end

function SC:drawWarp(tm)
    local w, h = self.width, self.height
    rect(self, 0, 0, w, h, K.bg, 1)
    local l = D.LOC[tm.loc]
    if l then tex(self, l.tex, 0, 0, w, h, 0.35, { 0.55, 0.62, 0.5 }) end
    for i = 0, 9 do
        local k = i / 9
        rect(self, w * 0.5 * k, 0, w * (1 - k), h * 0.5 * k + 1, K.bg, 0.05)
        rect(self, w * 0.5 * k, h - h * 0.5 * k, w * (1 - k), h * 0.5 * k + 1, K.bg, 0.05)
    end
    for yy = 0, h, 3 do rect(self, 0, yy, w, 1, K.g, 0.03) end
    local tm2 = getTextManager()
    local frac = 1 - math.min(1, math.max(0, left(tm.phaseLeft) / D.WARP))
    -- smooth between snapshots
    self.frac = math.max(self.frac or 0, frac)
    local f = self.frac
    local cx, cy = w / 2, h / 2
    tm2:DrawString(UIFont.Small, S(40), S(32), "HELI INSERTION  -  " .. D.TIER_TAG[tm.tier] .. "  -  " .. (tm.target or 0), K.g[1], K.g[2], K.g[3], 1)
    tm2:DrawStringCentre(UIFont.Small, cx, cy - S(110), "DEPLOYING TO", K.dim[1], K.dim[2], K.dim[3], 1)
    tm2:DrawStringCentre(UIFont.Title or UIFont.Large, cx, cy - S(84), string.upper(l and l.n or "?"), K.text[1], K.text[2], K.text[3], 1)
    local bw, bh = math.min(S(760), w * 0.7), S(22)
    local bx, by = cx - bw / 2, cy + S(4)
    border(self, bx, by, bw, bh, K.g, 1)
    local segs = 40
    local sw2 = (bw - S(6)) / segs
    for i = 0, math.floor(segs * f) - 1 do rect(self, bx + S(3) + i * sw2, by + S(3), sw2 - S(3), bh - S(6), K.g, 1) end
    tm2:DrawStringCentre(UIFont.Title or UIFont.Large, cx, by + bh + S(16), math.floor(f * 100) .. "%", K.g[1], K.g[2], K.g[3], 1)
    tm2:DrawStringCentre(UIFont.Small, cx, by + bh + S(16) + CMUI.fh(UIFont.Title or UIFont.Large) + S(6),
        T("IGUI_CM_Dod_eta", math.ceil(left(tm.phaseLeft))), K.dim[1], K.dim[2], K.dim[3], 1)
    local names = {}
    for _, m in ipairs(tm.members or {}) do if m.st == "in" then names[#names + 1] = m.n end end
    tm2:DrawString(UIFont.Small, S(40), h - S(44), "SQUAD " .. #names .. "  -  " .. table.concat(names, " - "), K.faint[1], K.faint[2], K.faint[3], 1)
end

-- radio static: grey snow with scan lines, then a green camera tint with the place name, then gone (~2 s)
function SC:drawArrive()
    local w, h = self.width, self.height
    local t = (CMC.ms() - (CMDoDc.arriveAt or 0)) / 1000
    if t > 2.2 then return false end
    local tm = team()
    if t < 0.8 then
        local a = 1 - t / 0.8 * 0.35
        rect(self, 0, 0, w, h, { 0.08, 0.08, 0.08 }, a)
        for _ = 1, 260 do
            local g = ZombRand(100) / 100
            rect(self, ZombRand(w), ZombRand(h), S(2) + ZombRand(S(10)), S(2), { g, g, g }, 0.6)
        end
        for yy = 0, h, 3 do rect(self, 0, yy, w, 1, { 0, 0, 0 }, 0.35) end
        rect(self, 0, (CMC.ms() / 3) % h, w, S(22), { 1, 1, 1 }, 0.18)
    else
        local k = (t - 0.8) / 1.4
        rect(self, 0, 0, w, h, K.gDim, 0.35 * (1 - k))
        for yy = 0, h, 3 do rect(self, 0, yy, w, 1, { 0, 0, 0 }, 0.25 * (1 - k)) end
        if tm and k < 0.8 then
            local tm2 = getTextManager()
            tm2:DrawStringCentre(UIFont.Small, w / 2, h * 0.42, "BOOTS ON GROUND", K.g[1], K.g[2], K.g[3], 1 - k)
            tm2:DrawStringCentre(UIFont.Title or UIFont.Large, w / 2, h * 0.42 + S(22), string.upper(locName(tm.loc)), 1, 1, 1, 1 - k)
        end
    end
    getTextManager():DrawString(UIFont.Small, S(30), S(30), "REC  -  SIGNAL " .. math.min(100, math.floor(t / 2 * 100)) .. "%", K.g[1], K.g[2], K.g[3], 1)
    return true
end

function SC:render()
    local tm = team()
    if self.mode == "warp" and tm then self:drawWarp(tm)
    elseif self.mode == "arrive" then
        if not self:drawArrive() then CMDoDc.arriveAt = nil end
    end
end

-- ===================================================================== HUD (recon banner + right panel)
CMDoDc.Hud = ISPanel:derive("CMDoD_Hud")
local HU = CMDoDc.Hud

function HU:new()
    local w = S(300)
    local sw = getCore():getScreenWidth()
    -- left of the floating button's column so it never covers it
    local o = ISPanel.new(self, sw - w - S(76), S(110), w, S(420))
    o.background = false
    o.moveWithMouse = true
    return o
end

function HU:prerender() end

function HU:render()
    local tm = team()
    if not tm then return end
    local w = self.width
    local fs = UIFont.Small
    local pad = S(14)
    local y = 0
    local hh = S(40)
    rect(self, 0, 0, w, hh, K.ink, 0.88)
    border(self, 0, 0, w, hh, K.line, 1)
    crosshair(self, pad + S(8), hh / 2, S(8), K.g, 2)
    CMUI.text(self, "DIE OR DIE", pad + S(22), (hh - CMUI.fh(fs)) / 2, K.text, 1, fs)
    local clock = tm.phase == "recon" and CM.clock(left(tm.phaseLeft)) or CM.clock(left(tm.left))
    CMUI.textR(self, clock, w - pad, (hh - CMUI.fh(UIFont.Medium)) / 2, tm.phase == "recon" and K.amber or K.text, 1, UIFont.Medium)
    y = hh
    local bodyH = S(80)
    rect(self, 0, y, w, bodyH, K.ink, 0.82)
    border(self, 0, y, w, bodyH, K.line, 1)
    local target = tm.phase == "live" and math.max(tm.spawned or 0, tm.target or 0) or (tm.target or 0)
    local remain = tm.phase == "live" and math.max(0, target - (tm.dead or 0)) or target
    CMUI.text(self, T("IGUI_CM_Dod_remain"), pad, y + S(10), K.faint, 1, fs)
    local big = tostring(remain)
    CMUI.textR(self, "/ " .. target, w - pad, y + S(14), K.faint, 1, fs)
    CMUI.textR(self, big, w - pad - CMUI.tw(fs, "/ " .. target) - S(6), y + S(4), K.red, 1, UIFont.Large)
    local segs = math.max(1, target)
    local sw2 = (w - pad * 2) / segs
    for i = 1, segs do
        rect(self, pad + (i - 1) * sw2, y + S(46), math.max(1, sw2 - 2), S(6), i <= (tm.dead or 0) and K.line2 or K.red, 1)
    end
    if tm.reinf and tm.phase == "live" then CMUI.text(self, T("IGUI_CM_Dod_reinf"), pad, y + S(58), K.amber, 1, fs)
    elseif tm.phase == "recon" then CMUI.text(self, T("IGUI_CM_Dod_reconHint"), pad, y + S(58), K.amber, 1, fs) end
    y = y + bodyH
    local lh = CMUI.fh(fs) + S(6)
    local teamH = pad + lh * #(tm.members or {}) + S(8)
    rect(self, 0, y, w, teamH, K.ink, 0.82)
    border(self, 0, y, w, teamH, K.line, 1)
    local ty = y + S(8)
    for _, m in ipairs(tm.members or {}) do
        local on = m.st == "in"
        CMUI.text(self, CMUI.fit(m.n, fs, w - S(140)), pad, ty, on and K.text or K.faint, 1, fs)
        local right = on and (m.kills .. " kill") or T("IGUI_CM_Dod_st_" .. tostring(m.st))
        CMUI.textR(self, right, w - pad, ty, on and K.g or K.faint, 1, fs)
        ty = ty + lh
    end
end

-- top centre: RECON countdown, then "ENEMY INBOUND" for a few seconds
CMDoDc.Banner = ISPanel:derive("CMDoD_Banner")
local BN = CMDoDc.Banner

function BN:new()
    local w = S(520)
    local o = ISPanel.new(self, math.floor((getCore():getScreenWidth() - w) / 2), S(20), w, S(110))
    o.background = false
    o.moveWithMouse = false
    return o
end

function BN:prerender() end
function BN:onMouseDown() return false end

function BN:render()
    local tm = team()
    if not tm then return end
    local w = self.width
    if tm.phase == "recon" then
        local label, clock = "RECON", CM.clock(left(tm.phaseLeft))
        local lw = CMUI.tw(UIFont.Small, label) + S(30)
        local cw = CMUI.tw(UIFont.Large, clock) + S(40)
        local x = (w - lw - cw) / 2
        rect(self, x, 0, lw, S(42), K.ink, 0.88)
        border(self, x, 0, lw + cw, S(42), K.line2, 1)
        CMUI.textC(self, label, x + lw / 2, (S(42) - CMUI.fh(UIFont.Small)) / 2, K.amber, 1, UIFont.Small)
        rect(self, x + lw, 0, cw, S(42), K.amber, 1)
        CMUI.textC(self, clock, x + lw + cw / 2, (S(42) - CMUI.fh(UIFont.Large)) / 2, K.ink, 1, UIFont.Large)
        CMUI.textC(self, T("IGUI_CM_Dod_reconSub"), w / 2, S(48), { 1, 1, 1 }, 1, UIFont.Small)
    elseif tm.phase == "live" and CMDoDc.inboundAt and CMC.ms() - CMDoDc.inboundAt < 4000 then
        local a = math.min(1, (4000 - (CMC.ms() - CMDoDc.inboundAt)) / 800)
        rect(self, 0, S(20), w, S(56), K.ink, 0.88 * a)
        rect(self, 0, S(20), w, S(2), K.red, a)
        rect(self, 0, S(74), w, S(2), K.red, a)
        CMUI.textC(self, "ENEMY INBOUND", w / 2, S(20) + (S(56) - CMUI.fh(UIFont.Large)) / 2, K.red, a, UIFont.Large)
        CMUI.textC(self, T("IGUI_CM_Dod_inboundSub", tm.target or 0), w / 2, S(82), { 1, 1, 1 }, a, UIFont.Small)
    end
end

-- ===================================================================== debrief (team cards, MVP in the middle)
CMDoDc.Debrief = CMUI.Window:derive("CMDoD_Debrief")
local DB = CMDoDc.Debrief

function DB:new(x, y, w, h, tm)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.tm = tm
    o.t0 = CMC.ms()
    o.models = {}    -- member key -> ISUI3DModel (only for players this client has loaded)
    o.lookAt = {}    -- member key -> ms of the next look
    return o
end

-- the member's own character when this client has them loaded (near you); nil = silhouette
local function onlineChar(key)
    local me = CMC.player()
    if me and CM.ukey(me:getUsername()) == key then return me end
    local list = getOnlinePlayers and getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p and CM.ukey(p:getUsername()) == key then return p end
        end
    end
    return nil
end

function DB:model(m, x, y, w, h)
    local mo = self.models[m.k]
    if mo == nil and CMC.ms() >= (self.lookAt[m.k] or 0) then
        self.lookAt[m.k] = CMC.ms() + 1000
        local p = onlineChar(m.k)
        local okD, dead = pcall(function() return p and p:isDead() end)
        if p and okD and not dead then
            local ok, made = pcall(function()
                local a = ISUI3DModel:new(x, y, w, h)
                a:initialise()
                a:instantiate()
                a:setVisible(true)
                self:addChild(a)
                a:setState("idle")
                a:setDirection(IsoDirections.S)
                a:setIsometric(false)
                a:setCharacter(p)
                return a
            end)
            if ok and made then mo = made; self.models[m.k] = mo end
        end
    end
    if mo then
        mo:setX(x); mo:setY(y); mo:setWidth(w); mo:setHeight(h)
        return true
    end
    return false
end

function DB:drawFrame()
    local w, h = self.width, self.height
    backdrop(self, 0, 0, w, h)
    border(self, 0, 0, w, h, K.line2, 1)
end

local function card(win, x, y, w, h, m, mvp, tm)
    local down = m.st == "dead" or m.st == "left"
    rect(win, x, y, w, h, mvp and { 0.09, 0.13, 0.06 } or K.panel, 0.95)
    border(win, x, y, w, h, mvp and K.g or K.line, 1)
    if mvp then border(win, x + 1, y + 1, w - 2, h - 2, K.g, 1) end
    local ph = math.floor(h * 0.56)
    rect(win, x + S(1), y + S(1), w - S(2), ph, mvp and { 0.14, 0.22, 0.09 } or { 0.08, 0.10, 0.07 }, 1)
    if down or not win:model(m, x + S(1), y + S(1), w - S(2), ph) then
        tex(win, "dod_avatar", x + w * 0.2, y + ph * 0.12, w * 0.6, ph * 0.88, down and 0.35 or 0.9, mvp and K.g or (down and K.faint or K.dim))
    end
    if mvp then
        local lw = CMUI.tw(UIFont.Medium, "MVP") + S(24)
        rect(win, x + (w - lw) / 2, y + S(10), lw, CMUI.fh(UIFont.Medium) + S(6), K.g, 1)
        CMUI.textC(win, "MVP", x + w / 2, y + S(13), K.ink, 1, UIFont.Medium)
    end
    local cy = y + ph + S(10)
    local px = x + S(14)
    local iw = w - S(28)
    local fv = mvp and UIFont.Large or UIFont.Medium
    CMUI.text(win, CMUI.fit(m.n, UIFont.Large, iw), px, cy, mvp and K.g or (down and K.dim or K.text), 1, UIFont.Large)
    cy = cy + CMUI.fh(UIFont.Large) + S(4)
    if down then
        CMUI.text(win, T("IGUI_CM_Dod_st_" .. tostring(m.st)), px, cy, K.red, 1, UIFont.Medium)
        cy = cy + CMUI.fh(UIFont.Medium) + S(4)
    end
    local rows = { { T("IGUI_CM_Dod_kill"), m.kills or 0 }, { "Damage", m.dmg or 0 }, { "Assist", m.ast or 0 } }
    for _, r in ipairs(rows) do
        CMUI.text(win, r[1], px, cy + (CMUI.fh(fv) - CMUI.fh(UIFont.Medium)) / 2, K.dim, 1, UIFont.Medium)
        CMUI.textR(win, tostring(r[2]), px + iw, cy, mvp and K.g or K.text, 1, fv)
        cy = cy + CMUI.fh(fv) + S(4)
    end
end

function DB:drawBody()
    local tm = self.tm
    local w, h = self.width, self.height
    local win = tm.res == "win"
    local title = win and "AREA CLEARED" or ((tm.res == "abort" or tm.res == "nofight") and "MISSION ABORTED" or "MISSION FAILED")
    CMUI.textC(self, "MISSION DEBRIEF  -  " .. string.upper(locName(tm.loc)) .. "  -  " .. D.TIER_TAG[tm.tier], w / 2, S(26), K.dim, 1, UIFont.Medium)
    CMUI.textC(self, title, w / 2, S(26) + CMUI.fh(UIFont.Medium) + S(6), win and K.g or K.red, 1, UIFont.Title or UIFont.Large)
    -- cards: MVP in the middle, the others around it
    local mem = {}
    local mvpM = nil
    for _, m in ipairs(tm.members or {}) do
        if tm.mvp and m.n == tm.mvp and not mvpM then mvpM = m else mem[#mem + 1] = m end
    end
    local order = {}
    local half = math.floor(#mem / 2)
    for i = 1, half do order[#order + 1] = mem[i] end
    if mvpM then order[#order + 1] = mvpM end
    for i = half + 1, #mem do order[#order + 1] = mem[i] end
    local n = #order
    local cw, ch = S(210), S(380)
    local mw, mh = S(260), S(450)
    local gap = S(14)
    local total = (n - (mvpM and 1 or 0)) * (cw + gap) + (mvpM and (mw + gap) or 0) - gap
    -- a big team: narrower cards so all of them fit the window
    if total > w - S(40) then
        local f = (w - S(40)) / total
        cw, mw, gap = math.floor(cw * f), math.floor(mw * f), math.floor(gap * f)
        total = (n - (mvpM and 1 or 0)) * (cw + gap) + (mvpM and (mw + gap) or 0) - gap
    end
    local cx = (w - total) / 2
    local base = S(110) + mh
    for _, m in ipairs(order) do
        local isM = m == mvpM
        local ww, hh = isM and mw or cw, isM and mh or ch
        card(self, cx, base - hh, ww, hh, m, isM, tm)
        cx = cx + ww + gap
    end
    -- my rewards + close
    local names = {}
    for _, e in ipairs(tm.rw or {}) do names[#names + 1] = CMC.itemName(e.t) .. ((e.n or 1) > 1 and (" x" .. e.n) or "") end
    local rs = #names > 0 and (T("IGUI_CM_Dod_got") .. "  " .. table.concat(names, " - ")) or (win and "" or T("IGUI_CM_Dod_noReward"))
    CMUI.textC(self, CMUI.fit(rs, UIFont.Medium, w - S(320)), w / 2 - S(130), h - S(52), K.dim, 1, UIFont.Medium)
    mbtn(self, w - S(260), h - S(62), S(220), S(44), T("IGUI_CM_Dod_close"), function() self:close() end, "go", { font = UIFont.Medium })
end

function DB:onClosed()
    -- let go of the characters before the window goes
    for _, mo in pairs(self.models or {}) do
        pcall(function() mo:setCharacter(nil); self:removeChild(mo) end)
    end
    self.models = {}
    if CMDoDc.debrief == self then CMDoDc.debrief = nil end
end

local function openDebrief(tm)
    if CMDoDc.debrief then CMDoDc.debrief:close() end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(1280, 680)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = DB:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h, CM.copy(tm))
    win:show()
    CMDoDc.debrief = win
end

-- ===================================================================== screens on / off from the snapshot
local function showPanel(key, cls, on)
    local p = CMDoDc[key]
    if on and not p then
        p = cls:new()
        p:initialise(); p:instantiate(); p:addToUIManager(); p:setVisible(true)
        if key == "screen" then pcall(function() p:setAlwaysOnTop(true) end) end
        CMDoDc[key] = p
        -- a new panel lands on top: keep the floating button clickable
        if key ~= "screen" and CMDoDc.fab then pcall(function() CMDoDc.fab:bringToTop() end) end
    elseif not on and p then
        p:setVisible(false)
        p:removeFromUIManager()
        CMDoDc[key] = nil
    end
    return CMDoDc[key]
end

local frozen = false
local function setFrozen(on)
    if frozen == on then return end
    frozen = on
    local p = CMC.player()
    if p then pcall(function() p:setBlockMovement(on) end) end
end

local function myState(tm)
    local p = CMC.player()
    if not tm or not p then return nil end
    local me = CM.ukey(p:getUsername())
    for _, m in ipairs(tm.members or {}) do if m.k == me then return m.st end end
    return nil
end

local lastPhase, lastTeam = nil, nil
local function sync()
    local tm = team()
    local phase = tm and tm.phase or nil
    local mine = myState(tm) == "in"
    -- the lock first (only while the insertion screen hides the world): a broken screen must never leave you stuck
    setFrozen(mine and phase == "warp" or false)
    if tm and tm.id == lastTeam and phase ~= lastPhase then
        if lastPhase == "warp" and phase == "recon" and mine then
            CMDoDc.arriveAt = CMC.ms()
            stopSound(CMDoDc.heli); CMDoDc.heli = nil
            sound({ "RadioStatic", "RadioTalk", "UIRadioStatic" })
        elseif phase == "live" and mine then
            CMDoDc.inboundAt = CMC.ms()
        end
    end
    if phase == "warp" and mine and not CMDoDc.heli and not CMDoDc.heliFor then
        CMDoDc.heli = sound({ "Helicopter", "HelicopterFly", "HeliFlyby" })
        CMDoDc.heliFor, CMDoDc.heliAt = tm.id, CMC.ms()
    end
    if phase ~= "warp" then CMDoDc.heliFor = nil end
    if phase ~= "warp" and CMDoDc.heli then stopSound(CMDoDc.heli); CMDoDc.heli = nil end
    if phase == "over" and tm.res and CMDoDc.shownFor ~= tm.id then
        CMDoDc.shownFor = tm.id
        pcall(openDebrief, tm)
    end
    lastPhase, lastTeam = phase, tm and tm.id or nil
    local arriving = CMDoDc.arriveAt ~= nil and CMC.ms() - CMDoDc.arriveAt < 2200
    local ok1, scr = pcall(showPanel, "screen", SC, (mine and phase == "warp") or arriving)
    if ok1 and scr then scr.mode = (mine and phase == "warp") and "warp" or "arrive"; if scr.mode == "warp" then scr.frac = scr.frac or 0 end end
    pcall(showPanel, "hud", HU, mine and (phase == "recon" or phase == "live"))
    pcall(showPanel, "banner", BN, mine and (phase == "recon" or phase == "live"))
end

-- ===================================================================== invite popup (the squad one, other answer)
CMDoDc.Ask = CMSquad.Ask:derive("CMDoD_Ask")
function CMDoDc.Ask:answer(yes)
    CMC.send("dodAnswer", { id = self.inv.id, yes = yes })
    self:close()
end
function CMDoDc.Ask:drawBody()
    if CMC.ms() - self.at > 60000 then self:close(); return end
    local pad = S(16)
    local x, w = pad, self.width - pad * 2
    CMUI.para(self, T("IGUI_CM_Dod_invited2", self.inv.by, locName(self.inv.loc)), x, self.headerH + S(12), w, CMUI.C.text, UIFont.Medium, 3)
    local by = self.height - S(52)
    local bw = (w - S(10)) / 2
    mbtn(self, x, by, bw, S(36), T("IGUI_CM_Sq_yes"), function() self:answer(true) end, "go")
    mbtn(self, x + bw + S(10), by, bw, S(36), T("IGUI_CM_Sq_no"), function() self:answer(false) end, "ghost")
end

-- ===================================================================== server messages
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CM.MOD or type(args) ~= "table" then return end
    if command == "dod" then
        CMDoDc.snap = args
        CMDoDc.at = CMC.ms()
        local ok, err = pcall(sync)
        if not ok then CM.log("dod sync error: " .. tostring(err)) end
    elseif command == "dodboard" then
        if args.view == "hist" then CMDoDc.hist = args else CMDoDc.board = args end
    elseif command == "dodinv" then
        CMUI.k = CMUI.fontScale()
        local w, h = CMUI.size(420, 200)
        local win = CMDoDc.Ask:new(math.floor((getCore():getScreenWidth() - w) / 2), CMUI.S(120), w, h, args)
        win.title = "DIE OR DIE"
        win:show()
        pcall(function() win:setAlwaysOnTop(true) end)
    end
end)

-- snapshots stop when we are in no team and not watching: drop the match screens if it goes stale
local lastCheck = 0
Events.OnTick.Add(function()
    local t = CMC.ms()
    if CMDoDc.arriveAt and t - CMDoDc.arriveAt > 2300 and CMDoDc.screen and CMDoDc.screen.mode == "arrive" then
        CMDoDc.arriveAt = nil
        pcall(sync)
    end
    if CMDoDc.heli and t - (CMDoDc.heliAt or t) > (D.WARP + 2) * 1000 then
        stopSound(CMDoDc.heli); CMDoDc.heli = nil
    end
    if t - lastCheck < 1000 then return end
    lastCheck = t
    local ok, err = pcall(fabTick)
    if not ok then CM.log("dod button error: " .. tostring(err)) end
    if CMDoDc.snap and CMDoDc.snap.team and t - CMDoDc.at > 6000 then
        CMDoDc.snap.team = nil
        pcall(sync)
    end
end)

return CMDoDc
