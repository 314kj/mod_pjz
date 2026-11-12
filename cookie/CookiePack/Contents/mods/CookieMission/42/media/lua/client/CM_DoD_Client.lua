-- Cookie Mission - Die or Die (client): lobby window, loading screen, ready check, match HUD, team tags over heads
require "CM_UI_Kit"
require "CM_UI_Squad"
require "CM_DoD"

local C = CMUI.C
local T = CMC.txt
local D = CM.DOD

CMDoDc = CMDoDc or {}
CMDoDc.snap = nil
CMDoDc.at = 0

local function S(n) return CMUI.S(n) end
local function lobby() return CMDoDc.snap and CMDoDc.snap.lobby or nil end
local function left(v) return CMC.left(v, CMDoDc.at) or 0 end

-- am I in the match right now (warped or about to be)?
local function inMatch()
    local lb = lobby()
    local p = CMC.player()
    if not lb or not lb.me or lb.phase == "lobby" or not p then return false end
    local me = CM.ukey(p:getUsername())
    for _, m in ipairs(lb.members or {}) do
        if m.st == "in" and CM.ukey(m.n) == me then return true end
    end
    return false
end
CMDoDc.inMatch = inMatch

-- ===================================================================== lobby window
CMDoDc.Win = CMUI.Window:derive("CMDoD_Win")
local DW = CMDoDc.Win

function DW:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = T("IGUI_CM_Dod_title")
    o.titleIcon = "cm_skull"
    o.bgAlpha = 0.9
    return o
end

function DW:createChildren()
    CMUI.Window.createChildren(self)
    -- admin: name + description of the spot to save
    self.nameBox = ISTextEntryBox:new("", S(18), 0, S(220), S(26))
    self.nameBox:initialise(); self.nameBox:instantiate()
    self:addChild(self.nameBox)
    self.descBox = ISTextEntryBox:new("", S(246), 0, S(330), S(26))
    self.descBox:initialise(); self.descBox:instantiate()
    self:addChild(self.descBox)
    self.nameBox:setVisible(false)
    self.descBox:setVisible(false)
end

local function swatch(win, x, y, s, c)
    CMUI.rbox(win, x, y, s, s, c, 1, 4)
    CMUI.rborder(win, x, y, s, s, C.white, 0.4, 4)
end

function DW:drawOutside(sn, x, y, w)
    local fs = UIFont.Small
    local lh = CMUI.fh(fs) + S(4)
    CMUI.para(self, T("IGUI_CM_Dod_about"), x, y, w, C.dim, fs, 4)
    y = y + (CMUI.fh(fs) + S(2)) * 4 + S(10)
    if not sn.on then
        CMUI.text(self, T("IGUI_CM_Dod_off_" .. tostring(sn.why or "off")), x, y, C.bad, 1, UIFont.Medium)
        y = y + CMUI.fh(UIFont.Medium) + S(10)
    elseif (sn.cool or 0) > 0 then
        CMUI.text(self, T("IGUI_CM_Dod_cool", CM.clock(left(sn.cool))), x, y, C.gold, 1, UIFont.Medium)
        y = y + CMUI.fh(UIFont.Medium) + S(10)
    end
    if sn.inv then
        CMUI.text(self, T("IGUI_CM_Dod_invited", sn.inv.by), x, y, C.gold)
        CMUI.btn(self, x + w - S(200), y - S(4), S(96), S(28), T("IGUI_CM_Sq_yes"), function() CMC.send("dodAnswer", { yes = true }) end, "good")
        CMUI.btn(self, x + w - S(98), y - S(4), S(96), S(28), T("IGUI_CM_Sq_no"), function() CMC.send("dodAnswer", { yes = false }) end, "ghost")
        y = y + S(32)
    end
    local lb = sn.lobby
    if lb and lb.phase == "lobby" then
        CMUI.text(self, T("IGUI_CM_Dod_lobbyOf", lb.lead or "?", #(lb.members or {}), D.MAX), x, y, C.text, 1, UIFont.Medium)
        CMUI.btn(self, x + w - S(160), y - S(4), S(160), S(32), T("IGUI_CM_Sq_join"), function() CMC.send("dodJoin", {}) end,
            "primary", { disabled = not sn.on or (sn.cool or 0) > 0 })
    elseif lb then
        CMUI.text(self, T("IGUI_CM_Dod_busy"), x, y, C.dim, 1, UIFont.Medium)
    else
        CMUI.btn(self, x, y, w, S(40), T("IGUI_CM_Dod_make"), function() CMC.send("dodNew", {}) end, "primary",
            { disabled = not sn.on or (sn.cool or 0) > 0, font = UIFont.Medium })
    end
    y = y + S(48)
    -- the spots (admins save them where they stand)
    CMUI.text(self, T("IGUI_CM_Dod_spots", #(sn.points or {})), x, y, C.dim)
    y = y + lh
    for _, pt in ipairs(sn.points or {}) do
        CMUI.text(self, CMUI.fit(pt.name .. "  ·  " .. CM.townAt(pt.x, pt.y), fs, w - S(110)), x + S(8), y, C.text)
        if sn.admin then
            CMUI.btn(self, x + w - S(90), y - S(2), S(90), lh, T("IGUI_CM_Dod_del"), function() CMC.send("dodDel", { id = pt.id }) end, "danger")
        end
        y = y + lh
    end
    if #(sn.points or {}) == 0 then
        CMUI.text(self, T("IGUI_CM_Dod_nospot"), x + S(8), y, C.faint)
        y = y + lh
    end
    -- admin save form
    local adm = sn.admin == true
    self.nameBox:setVisible(adm)
    self.descBox:setVisible(adm)
    if adm then
        local fy = self.height - S(60)
        CMUI.text(self, T("IGUI_CM_Dod_saveHint"), x, fy - lh, C.faint)
        self.nameBox:setY(fy); self.descBox:setY(fy)
        self.nameBox:setX(x); self.descBox:setX(x + S(228))
        self.descBox:setWidth(w - S(228) - S(130))
        CMUI.btn(self, x + w - S(122), fy, S(122), S(26), T("IGUI_CM_Dod_save"), function()
            CMC.send("dodSave", { name = self.nameBox:getText(), desc = self.descBox:getText() })
            self.nameBox:setText(""); self.descBox:setText("")
        end, "good")
    end
end

function DW:drawLobby(sn, lb, x, y, w)
    local fs = UIFont.Small
    local rh = S(30)
    local colW = math.floor(w * 0.52)
    local rx, rw = x + colW + S(16), w - colW - S(16)
    local head = lb.voteLeft and T("IGUI_CM_Dod_voting", math.ceil(left(lb.voteLeft))) or T("IGUI_CM_Dod_lobby", #lb.members, D.MAX)
    CMUI.text(self, head, x, y, lb.voteLeft and C.gold or C.text, 1, UIFont.Medium)
    CMUI.textR(self, T("IGUI_CM_Dod_tier", CMC.tierName(lb.tier), CM.dodCount(lb.tier)), x + w, y, CMUI.tierColor(lb.tier), 1, UIFont.Medium)
    y = y + CMUI.fh(UIFont.Medium) + S(10)
    local top = y
    -- members
    local mine = nil
    local myName = CM.ukey(CMC.player() and CMC.player():getUsername() or "")
    for _, m in ipairs(lb.members) do
        if CM.ukey(m.n) == myName then mine = m end
        local col = CM.dodColor(m.c)
        CMUI.rbox(self, x, y, colW, rh, C.panel2, 0.55, 6)
        swatch(self, x + S(6), y + S(6), rh - S(12), col)
        local label = "[" .. CM.dodSign(m.s) .. "] " .. m.n
        if m.lead then label = label .. "  " .. T("IGUI_CM_Sq_leadTag") end
        CMUI.text(self, CMUI.fit(label, fs, colW - S(140)), x + rh + S(4), y + (rh - CMUI.fh(fs)) / 2, col)
        CMUI.textR(self, m.ok and T("IGUI_CM_Dod_okTag") or T("IGUI_CM_Dod_noTag"), x + colW - (lb.leadMe and not m.lead and S(70) or S(8)),
            y + (rh - CMUI.fh(fs)) / 2, m.ok and C.good or C.bad)
        if lb.leadMe and not m.lead then
            CMUI.btn(self, x + colW - S(64), y + S(3), S(60), rh - S(6), T("IGUI_CM_Sq_kick"), function() CMC.send("dodKick", { who = m.k }) end, "danger")
        end
        y = y + rh + S(4)
    end
    y = y + S(6)
    -- my colour / call sign
    if mine then
        CMUI.cycle(self, x, y, S(150), S(30), T("IGUI_CM_Dod_color", mine.c),
            function() CMC.send("dodPick", { c = CM.mod(mine.c - 2, 8) + 1 }) end,
            function() CMC.send("dodPick", { c = CM.mod(mine.c, 8) + 1 }) end)
        CMUI.cycle(self, x + S(160), y, colW - S(160), S(30), CM.dodSign(mine.s),
            function() CMC.send("dodPick", { s = CM.mod(mine.s - 2, 8) + 1 }) end,
            function() CMC.send("dodPick", { s = CM.mod(mine.s, 8) + 1 }) end)
        y = y + S(38)
        -- the hardcore warning, accepted per player before the start
        CMUI.btn(self, x, y, colW, S(44), CMUI.fit(mine.ok and T("IGUI_CM_Dod_warnOk") or T("IGUI_CM_Dod_warn"), fs, colW - S(12)),
            function() CMC.send("dodWarn", { yes = not mine.ok }) end, mine.ok and "sel" or "danger")
        y = y + S(52)
    end
    -- invite (leader)
    if lb.leadMe and lb.free then
        CMUI.text(self, T("IGUI_CM_Sq_invite"), x, y, C.dim)
        y = y + CMUI.fh(fs) + S(4)
        local i = 0
        for _, f in ipairs(lb.free) do
            local cy = y + math.floor(i / 2) * (S(28) + S(4))
            if cy + S(28) > self.height - S(64) then break end
            local cx = x + CM.mod(i, 2) * (colW / 2 + S(2))
            CMUI.btn(self, cx, cy, colW / 2 - S(2), S(28), CMUI.fit(f.n, fs, colW / 2 - S(14)), function()
                CMC.send("dodInvite", { who = f.k })
            end, f.inv and "flat" or "ghost", { disabled = f.inv })
            i = i + 1
        end
    end
    -- vote (right column)
    local vy = top
    CMUI.text(self, T("IGUI_CM_Dod_vote"), rx, vy, C.dim)
    vy = vy + CMUI.fh(fs) + S(6)
    for _, pt in ipairs(sn.points or {}) do
        local n = lb.votes and lb.votes[pt.id] or 0
        local sel = lb.myVote == pt.id
        CMUI.btn(self, rx, vy, rw, S(34), CMUI.fit(pt.name .. "   (" .. tostring(n) .. ")", fs, rw - S(16)), function()
            CMC.send("dodVote", { id = pt.id })
        end, sel and "sel" or "ghost", { tip = pt.desc ~= "" and pt.desc or nil })
        vy = vy + S(38)
    end
    -- leader controls + leave
    local by = self.height - S(54)
    if lb.leadMe then
        CMUI.cycle(self, rx, by - S(42), rw, S(34), T("IGUI_CM_Dod_tier", CMC.tierName(lb.tier), CM.dodCount(lb.tier)),
            function() CMC.send("dodTier", { tier = CM.mod(lb.tier - 2, 3) + 1 }) end,
            function() CMC.send("dodTier", { tier = CM.mod(lb.tier, 3) + 1 }) end)
        local label = lb.voteLeft and T("IGUI_CM_Dod_force") or T("IGUI_CM_Dod_start")
        CMUI.btn(self, rx, by, rw, S(38), label, function() CMC.send("dodStart", { force = lb.voteLeft ~= nil }) end, "primary")
    end
    CMUI.btn(self, x, by, colW, S(38), T("IGUI_CM_Sq_leave"), function() CMC.send("dodLeave", {}) end, "ghost")
end

function DW:drawBody()
    local pad = S(18)
    local x, w = pad, self.width - pad * 2
    local y = self.headerH + S(14)
    local sn = CMDoDc.snap
    if not sn then
        CMUI.textC(self, T("IGUI_CM_Loading"), self.width / 2, y + S(40), C.dim, 1, UIFont.Medium)
        return
    end
    local lb = sn.lobby
    if lb and lb.me and lb.phase == "lobby" then
        self.nameBox:setVisible(false)
        self.descBox:setVisible(false)
        self:drawLobby(sn, lb, x, y, w)
    elseif lb and lb.me then
        self.nameBox:setVisible(false)
        self.descBox:setVisible(false)
        CMUI.text(self, T("IGUI_CM_Dod_inMatch"), x, y, C.gold, 1, UIFont.Medium)
        CMUI.btn(self, x, self.height - S(54), w, S(38), T("IGUI_CM_Dod_quit"), function() CMC.send("dodLeave", {}) end, "danger")
    else
        self:drawOutside(sn, x, y, w)
    end
end

function DW:onClosed()
    CMDoDc.win = nil
    CMC.send("dodClose", {})
end

function CMDoDc.open()
    if CMDoDc.win then CMDoDc.win:bringToTop(); return end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(780, 580)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = DW:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    win:show()
    CMDoDc.win = win
    CMC.send("dodOpen", {})
end

-- ===================================================================== loading screen / ready check / 3-2-1 (full screen)
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

function SC:render()
    local lb = lobby()
    if not lb then return end
    local w, h = self.width, self.height
    local tm = getTextManager()
    if lb.phase == "load" then
        self:drawRect(0, 0, w, h, 1, 0.02, 0.02, 0.03)
        local tex = lb.point and CMUI.tex("dod_" .. tostring(lb.point.id)) or nil
        if tex then self:drawTextureScaledAspect(tex, 0, 0, w, h, 0.55, 1, 1, 1) end
        local cx = w / 2
        local y = h * 0.28
        tm:DrawStringCentre(UIFont.Title or UIFont.Large, cx, y, tostring(lb.point and lb.point.name or "?"), 1, 0.85, 0.3, 1)
        y = y + CMUI.fh(UIFont.Title or UIFont.Large) + S(14)
        if lb.point then
            tm:DrawStringCentre(UIFont.Medium, cx, y, T("IGUI_CM_Dod_near", CM.townAt(lb.point.x, lb.point.y)), 0.8, 0.8, 0.85, 1)
            y = y + CMUI.fh(UIFont.Medium) + S(10)
            for _, line in ipairs(CMUI.wrap(lb.point.desc or "", UIFont.Medium, w * 0.6)) do
                tm:DrawStringCentre(UIFont.Medium, cx, y, line, 0.9, 0.9, 0.9, 1)
                y = y + CMUI.fh(UIFont.Medium) + S(4)
            end
        end
        y = y + S(20)
        tm:DrawStringCentre(UIFont.Large, cx, y, T("IGUI_CM_Dod_intel", lb.target or 0, lb.faction or "?"), 1, 0.4, 0.4, 1)
        y = y + CMUI.fh(UIFont.Large) + S(10)
        tm:DrawStringCentre(UIFont.Medium, cx, y, T("IGUI_CM_Dod_warnShort"), 1, 0.3, 0.3, 1)
        tm:DrawStringCentre(UIFont.Medium, cx, h - S(80), T("IGUI_CM_Dod_loading", math.ceil(left(lb.phaseLeft))), 0.7, 0.7, 0.75, 1)
    elseif lb.phase == "count" then
        tm:DrawStringCentre(UIFont.Title or UIFont.Large, w / 2, h * 0.35, tostring(math.max(1, math.ceil(left(lb.phaseLeft)))), 1, 0.3, 0.3, 1)
    end
end

-- the ready check is a small window (the world is visible behind it)
CMDoDc.Ready = CMUI.Window:derive("CMDoD_Ready")
local RW = CMDoDc.Ready

function RW:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = T("IGUI_CM_Dod_title")
    o.titleIcon = "cm_skull"
    return o
end

function RW:onClosed() if CMDoDc.ready == self then CMDoDc.ready = nil end end

function RW:drawBody()
    local lb = lobby()
    if not lb or lb.phase ~= "ready" then return end
    local pad = S(16)
    local x, w = pad, self.width - pad * 2
    local y = self.headerH + S(10)
    CMUI.text(self, T("IGUI_CM_Dod_readyHead", math.ceil(left(lb.phaseLeft))), x, y, C.gold, 1, UIFont.Medium)
    y = y + CMUI.fh(UIFont.Medium) + S(8)
    local me = nil
    local myName = CM.ukey(CMC.player() and CMC.player():getUsername() or "")
    for _, m in ipairs(lb.members) do
        if m.st == "in" then
            if CM.ukey(m.n) == myName then me = m end
            CMUI.text(self, CMUI.fit("[" .. CM.dodSign(m.s) .. "] " .. m.n, UIFont.Small, w - S(80)), x, y, CM.dodColor(m.c))
            CMUI.textR(self, m.ready and T("IGUI_CM_Dod_readyTag") or "...", x + w, y, m.ready and C.good or C.dim)
            y = y + CMUI.fh(UIFont.Small) + S(4)
        end
    end
    CMUI.btn(self, x, self.height - S(56), w, S(42), T("IGUI_CM_Dod_ready"), function() CMC.send("dodReady", {}) end,
        "good", { disabled = me and me.ready, font = UIFont.Medium })
end

-- ===================================================================== match HUD
CMDoDc.Hud = CMUI.Window:derive("CMDoD_Hud")
local HW = CMDoDc.Hud

function HW:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = T("IGUI_CM_Dod_title")
    o.titleIcon = "cm_skull"
    o.bgAlpha = 0.6
    return o
end

function HW:onClosed() if CMDoDc.hud == self then CMDoDc.hud = nil end end

function HW:drawBody()
    local lb = lobby()
    if not lb then return end
    local pad = S(12)
    local x, w = pad, self.width - pad * 2
    local y = self.headerH + S(8)
    local fs = UIFont.Small
    local lh = CMUI.fh(fs) + S(3)
    CMUI.text(self, T("IGUI_CM_Dod_kills", lb.dead or 0, lb.spawned or 0), x, y, C.bad, 1, UIFont.Medium)
    CMUI.textR(self, CM.clock(left(lb.left)), x + w, y, C.gold, 1, UIFont.Medium)
    y = y + CMUI.fh(UIFont.Medium) + S(4)
    if lb.reinf then
        CMUI.text(self, T("IGUI_CM_Dod_reinf"), x, y, C.gold)
        y = y + lh
    end
    -- team
    for _, m in ipairs(lb.members) do
        local col = m.st == "in" and CM.dodColor(m.c) or C.faint
        local s = "[" .. CM.dodSign(m.s) .. "] " .. m.n .. "  " .. tostring(m.kills or 0)
        if m.st ~= "in" then s = s .. "  " .. T("IGUI_CM_Dod_st_" .. tostring(m.st)) end
        CMUI.text(self, CMUI.fit(s, fs, w), x, y, col)
        y = y + lh
    end
    y = y + S(4)
    -- enemies: struck through when down
    for _, e in ipairs(lb.npcs or {}) do
        if y + lh > self.height - S(6) then break end
        local col = e.d and C.faint or C.text
        CMUI.text(self, CMUI.fit(e.n, fs, w), x, y, col)
        if e.d then CMUI.rect(self, x, y + CMUI.fh(fs) / 2, math.min(w, CMUI.tw(fs, e.n)), S(1), C.faint, 1) end
        y = y + lh
    end
end

-- ===================================================================== screens on / off from the snapshot
local function showScreen(on)
    if on and not CMDoDc.screen then
        local s = SC:new()
        s:initialise(); s:instantiate(); s:addToUIManager(); s:setVisible(true)
        pcall(function() s:setAlwaysOnTop(true) end)
        CMDoDc.screen = s
    elseif not on and CMDoDc.screen then
        CMDoDc.screen:setVisible(false)
        CMDoDc.screen:removeFromUIManager()
        CMDoDc.screen = nil
    end
end

local function showWin(key, cls, on, w0, h0, place)
    local win = CMDoDc[key]
    if on and not win then
        CMUI.k = CMUI.fontScale()
        local w, h = CMUI.size(w0, h0)
        local x, y = place(w, h)
        win = cls:new(x, y, w, h)
        win:show()
        CMDoDc[key] = win
    elseif not on and win then
        win:close()
        CMDoDc[key] = nil
    end
end

local frozen = false
local function setFrozen(on)
    if frozen == on then return end
    frozen = on
    local p = CMC.player()
    if p then pcall(function() p:setBlockMovement(on) end) end
end

local function sync()
    local lb = lobby()
    local mine = lb and lb.me
    local phase = mine and lb.phase or nil
    local myIn = mine and inMatch()
    -- the lock first: a broken window must never leave the player stuck
    setFrozen(myIn and (phase == "load" or phase == "ready" or phase == "count") or false)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local ok1, e1 = pcall(showScreen, myIn and (phase == "load" or phase == "count"))
    local ok2, e2 = pcall(showWin, "ready", RW, myIn and phase == "ready", 380, 320,
        function(w, h) return math.floor((sw - w) / 2), math.floor(sh * 0.62 - h / 2) end)
    local ok3, e3 = pcall(showWin, "hud", HW, mine and phase == "live", 300, 420,
        function(w, h) return sw - w - S(20), math.floor(sh * 0.22) end)
    if not (ok1 and ok2 and ok3) then CM.log("dod screens error: " .. tostring(e1 or e2 or e3)) end
end

-- ===================================================================== tags over the team's heads
local function tags()
    local lb = lobby()
    if not lb or not lb.me or lb.phase == "lobby" or lb.phase == "over" then return end
    local me = CMC.player()
    if not me then return end
    local zoom = getCore():getZoom(0)
    local tm = getTextManager()
    for _, m in ipairs(lb.members) do
        if m.st == "in" then
            local p = getPlayerFromUsername and getPlayerFromUsername(m.n)
            if p and math.abs(p:getZ() - me:getZ()) < 1 and math.abs(p:getX() - me:getX()) < 40 and math.abs(p:getY() - me:getY()) < 40 then
                local sx = isoToScreenX(0, p:getX(), p:getY(), p:getZ())
                local sy = isoToScreenY(0, p:getX(), p:getY(), p:getZ()) - 205 / zoom
                local c = CM.dodColor(m.c)
                local s = "[" .. CM.dodSign(m.s) .. "] " .. m.n
                tm:DrawStringCentre(UIFont.Small, sx + 1, sy + 1, s, 0, 0, 0, 0.85)
                tm:DrawStringCentre(UIFont.Small, sx, sy, s, c[1], c[2], c[3], 1)
            end
        end
    end
end
Events.OnPreUIDraw.Add(function()
    local ok, err = pcall(tags)
    if not ok then CM.log("dod tags error: " .. tostring(err)) end
end)

-- ===================================================================== invite popup (the squad one, other answer)
CMDoDc.Ask = CMSquad.Ask:derive("CMDoD_Ask")
function CMDoDc.Ask:answer(yes)
    CMC.send("dodAnswer", { yes = yes })
    self:close()
end
function CMDoDc.Ask:drawBody()
    if CMC.ms() - self.at > 60000 then self:close(); return end
    local pad = S(16)
    local x, w = pad, self.width - pad * 2
    CMUI.para(self, T("IGUI_CM_Dod_invited", self.inv.by), x, self.headerH + S(12), w, C.text, UIFont.Medium, 3)
    local by = self.height - S(52)
    local bw = (w - S(10)) / 2
    CMUI.btn(self, x, by, bw, S(36), T("IGUI_CM_Sq_yes"), function() self:answer(true) end, "good")
    CMUI.btn(self, x + bw + S(10), by, bw, S(36), T("IGUI_CM_Sq_no"), function() self:answer(false) end, "ghost")
end

-- ===================================================================== server messages
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CM.MOD or type(args) ~= "table" then return end
    if command == "dod" then
        CMDoDc.snap = args
        CMDoDc.at = CMC.ms()
        local ok, err = pcall(sync)
        if not ok then CM.log("dod sync error: " .. tostring(err)) end
    elseif command == "dodinv" then
        CMUI.k = CMUI.fontScale()
        local w, h = CMUI.size(420, 200)
        local win = CMDoDc.Ask:new(math.floor((getCore():getScreenWidth() - w) / 2), CMUI.S(120), w, h, args)
        win:show()
        pcall(function() win:setAlwaysOnTop(true) end)
    elseif command == "dodres" then
        local key = "IGUI_CM_Dod_res_" .. tostring(args.res)
        local names = {}
        for _, e in ipairs(args.rw or {}) do names[#names + 1] = CMC.itemName(e.t) .. (e.n > 1 and (" x" .. e.n) or "") end
        local s = T(key, args.kills or 0)
        if args.mvp then s = s .. " · " .. T("IGUI_CM_Dod_mvp", args.mvp) end
        if #names > 0 then s = s .. "\n" .. table.concat(names, ", ") end
        CMC.toast(s, args.res == "win" and "good" or "bad", 12)
    end
end)

-- nothing comes when we are not in a lobby or watching: drop the screens if the snapshot goes stale
local lastCheck = 0
Events.OnTick.Add(function()
    local t = CMC.ms()
    if t - lastCheck < 1000 then return end
    lastCheck = t
    if CMDoDc.snap and t - CMDoDc.at > 6000 then
        CMDoDc.snap.lobby = nil
        pcall(sync)
    end
end)

return CMDoDc
