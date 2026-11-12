-- Cookie Mission - squads: pick a size on a card, invite or let people join, warp together when full
-- (the server keeps the queue in memory only; a restart drops it)
require "CM_UI_Kit"

local C = CMUI.C
local T = CMC.txt

CMSquad = CMSquad or {}
CMSquad.Win = CMUI.Window:derive("CMSquad_Win")
local QW = CMSquad.Win

local SIZES = { 2, 3, 4, 6 }

function QW:new(x, y, w, h, slot)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.slot = slot
    o.title = T("IGUI_CM_Sq_title")
    o.titleIcon = "cm_icon"
    o.bgAlpha = 0.86
    o.sizeSel = 1
    return o
end

local function cardOf(slot)
    local pub = CMC.pub
    return pub and pub.cards and pub.cards[slot] or nil
end

local function sizesFor(c)
    local out = {}
    for _, n in ipairs(SIZES) do
        if n <= (c and c.cap or 0) then out[#out + 1] = n end
    end
    return out
end

local function row(win, x, y, w, h, label, col)
    CMUI.rbox(win, x, y, w, h, C.panel2, 0.55, 6)
    CMUI.text(win, CMUI.fit(label, UIFont.Small, w - CMUI.S(130)), x + CMUI.S(10), y + (h - CMUI.fh(UIFont.Small)) / 2, col or C.text)
end

-- my own squad: members, countdown, invite list, leave / disband
function QW:drawMine(sq, x, y, w)
    local S = CMUI.S
    local rh = S(30)
    local fs = UIFont.Small
    local c = cardOf(sq.slot)
    local need = sq.size - #sq.members
    local head
    if sq.cd then head = T("IGUI_CM_Sq_count", math.ceil(CMC.left(sq.cd, CMC.meAt) or 0))
    elseif need > 0 then head = T("IGUI_CM_Sq_need", #sq.members, sq.size, need)
    else head = T("IGUI_CM_Sq_wait") end
    CMUI.text(self, CMUI.fit(head, UIFont.Medium, w), x, y, sq.cd and C.good or C.gold, 1, UIFont.Medium)
    y = y + CMUI.fh(UIFont.Medium) + S(4)
    if c and c.type then
        CMUI.text(self, CMUI.fit(CMC.typeName(c.type) .. " · " .. CMC.tierName(c.tier or sq.slot) .. " · " ..
            T("IGUI_CM_Sq_life", CM.clock(CMC.left(sq.left, CMC.meAt) or 0)), fs, w), x, y, C.dim)
    end
    y = y + CMUI.fh(fs) + S(10)
    for _, m in ipairs(sq.members) do
        local label = m.n
        if m.lead then label = label .. "  " .. T("IGUI_CM_Sq_leadTag") end
        if m.off then label = label .. "  " .. T("IGUI_CM_Sq_offTag") end
        row(self, x, y, w, rh, label, m.lead and C.gold or C.text)
        if sq.lead and not m.lead then
            CMUI.btn(self, x + w - S(96), y + S(3), S(90), rh - S(6), T("IGUI_CM_Sq_kick"), function()
                CMC.send("sqKick", { who = m.k })
            end, "danger")
        end
        y = y + rh + S(4)
    end
    for _ = #sq.members + 1, sq.size do
        row(self, x, y, w, rh, T("IGUI_CM_Sq_empty"), C.faint)
        y = y + rh + S(4)
    end
    y = y + S(6)
    -- the leader invites people who are online and free
    if sq.lead and sq.free then
        CMUI.text(self, T("IGUI_CM_Sq_invite"), x, y, C.dim)
        y = y + CMUI.fh(fs) + S(6)
        local bottom = self.height - S(70)
        if #sq.free == 0 then
            CMUI.text(self, T("IGUI_CM_Sq_nofree"), x, y, C.faint)
            y = y + CMUI.fh(fs) + S(6)
        end
        local cols = 2
        local cw = (w - S(8)) / cols
        local i = 0
        for _, f in ipairs(sq.free) do
            local cx = x + CM.mod(i, cols) * (cw + S(8))
            local cy = y + math.floor(i / cols) * (rh + S(4))
            if cy + rh > bottom then break end
            local label = f.inv and (f.n .. " · " .. T("IGUI_CM_Sq_sent")) or f.n
            CMUI.btn(self, cx, cy, cw, rh, CMUI.fit(label, fs, cw - S(12)), function()
                CMC.send("sqInvite", { who = f.k })
            end, f.inv and "flat" or "ghost", { disabled = f.inv })
            i = i + 1
        end
    end
    local by = self.height - S(54)
    if sq.lead then
        local bw = (w - S(10)) / 2
        CMUI.btn(self, x, by, bw, S(38), T("IGUI_CM_Sq_leave"), function() CMC.send("sqLeave", {}) end, "ghost")
        CMUI.btn(self, x + bw + S(10), by, bw, S(38), T("IGUI_CM_Sq_disband"), function() CMC.send("sqDisband", {}) end, "danger")
    else
        CMUI.btn(self, x, by, w, S(38), T("IGUI_CM_Sq_leave"), function() CMC.send("sqLeave", {}) end, "ghost")
    end
end

-- not in a squad: invites, squads on this card, make one
function QW:drawFree(c, x, y, w)
    local S = CMUI.S
    local rh = S(32)
    local fs = UIFont.Small
    local me = CMC.me or {}
    CMUI.para(self, T("IGUI_CM_Sq_about"), x, y, w, C.dim, fs, 3)
    y = y + (CMUI.fh(fs) + S(2)) * 3 + S(8)
    for _, iv in ipairs(me.inv or {}) do
        local ic = cardOf(iv.slot)
        local what = ic and ic.type and CMC.typeName(ic.type) or "?"
        row(self, x, y, w, rh, T("IGUI_CM_Sq_invited", iv.by, what, iv.n, iv.size), C.gold)
        CMUI.btn(self, x + w - S(124), y + S(3), S(58), rh - S(6), T("IGUI_CM_Sq_yes"), function()
            CMC.send("sqAnswer", { id = iv.id, yes = true })
        end, "good")
        CMUI.btn(self, x + w - S(62), y + S(3), S(58), rh - S(6), T("IGUI_CM_Sq_no"), function()
            CMC.send("sqAnswer", { id = iv.id, yes = false })
        end, "ghost")
        y = y + rh + S(4)
    end
    if not c or not c.type then
        CMUI.text(self, T("IGUI_CM_NotNow"), x, y, C.faint)
        return
    end
    local busy = CMC.run() ~= nil
    local list = c.squads or {}
    CMUI.text(self, T("IGUI_CM_Sq_onCard", #list), x, y, C.dim)
    y = y + CMUI.fh(fs) + S(6)
    for _, q in ipairs(list) do
        row(self, x, y, w, rh, T("IGUI_CM_Sq_of", q.by, q.n, q.size), C.text)
        local full = q.n >= q.size
        CMUI.btn(self, x + w - S(110), y + S(3), S(104), rh - S(6), full and T("IGUI_CM_Full") or T("IGUI_CM_Sq_join"), function()
            CMC.send("sqJoin", { id = q.id })
        end, "primary", { disabled = full or busy })
        y = y + rh + S(4)
    end
    -- make a squad: size on this card (team cap) and free seats
    local sizes = sizesFor(c)
    local by = self.height - S(54)
    if #sizes == 0 then return end
    if self.sizeSel > #sizes then self.sizeSel = #sizes end
    local n = sizes[self.sizeSel]
    local room = (c.cap or 0) - (c.n or 0) - (c.seats or 0)
    local can = not busy and (c.status == "open" or c.status == "live") and n <= room
    CMUI.cycle(self, x, by, S(150), S(38), T("IGUI_CM_Sq_size", n),
        function() self.sizeSel = CM.mod(self.sizeSel - 2, #sizes) + 1 end,
        function() self.sizeSel = CM.mod(self.sizeSel, #sizes) + 1 end)
    CMUI.btn(self, x + S(160), by, w - S(160), S(38), T("IGUI_CM_Sq_make"), function()
        CMC.send("sqNew", { slot = c.slot or self.slot, size = n })
    end, "primary", { disabled = not can, tip = T("IGUI_CM_Sq_makeTip", room) })
end

function QW:drawBody()
    local S = CMUI.S
    local pad = S(18)
    local x, w = pad, self.width - pad * 2
    local y = self.headerH + S(14)
    local me = CMC.me or {}
    if me.sq then
        self.slot = me.sq.slot
        self:drawMine(me.sq, x, y, w)
    else
        self:drawFree(cardOf(self.slot), x, y, w)
    end
end

function QW:onClosed() CMSquad.win = nil end

function CMSquad.open(slot)
    if CMSquad.win then
        CMSquad.win.slot = slot or CMSquad.win.slot
        CMSquad.win:bringToTop()
        return
    end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(480, 520)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = QW:new(math.floor((sw - w) / 2) + CMUI.S(40), math.floor((sh - h) / 2), w, h, slot or 1)
    win:show()
    CMSquad.win = win
end

-- ===================================================================== invite popup
CMSquad.Ask = CMUI.Window:derive("CMSquad_Ask")
local QA = CMSquad.Ask

function QA:new(x, y, w, h, inv)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.inv = inv
    o.title = T("IGUI_CM_Sq_title")
    o.titleIcon = "cm_icon"
    o.at = CMC.ms()
    return o
end

function QA:answer(yes)
    CMC.send("sqAnswer", { id = self.inv.id, yes = yes })
    self:close()
end

function QA:drawBody()
    local S = CMUI.S
    if CMC.ms() - self.at > 60000 then self:close(); return end
    local pad = S(16)
    local x, w = pad, self.width - pad * 2
    local y = self.headerH + S(12)
    local iv = self.inv
    local what = iv.type and (CMC.typeName(iv.type) .. " · " .. CMC.tierName(iv.tier or iv.slot)) or "?"
    CMUI.para(self, T("IGUI_CM_Sq_invited", iv.by, what, iv.n, iv.size), x, y, w, C.text, UIFont.Medium, 3)
    local by = self.height - S(52)
    local bw = (w - S(10)) / 2
    CMUI.btn(self, x, by, bw, S(36), T("IGUI_CM_Sq_yes"), function() self:answer(true) end, "good")
    CMUI.btn(self, x + bw + S(10), by, bw, S(36), T("IGUI_CM_Sq_no"), function() self:answer(false) end, "ghost")
end

function QA:onClosed()
    if CMSquad.ask == self then CMSquad.ask = nil end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CM.MOD or command ~= "sqinv" or type(args) ~= "table" then return end
    if CMSquad.ask then CMSquad.ask:close() end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(420, 200)
    local sw = getCore():getScreenWidth()
    local win = QA:new(math.floor((sw - w) / 2), CMUI.S(120), w, h, args)
    win:show()
    pcall(function() win:setAlwaysOnTop(true) end)
    CMSquad.ask = win
end)

-- the warp went: the squad window has nothing left to show
CMC.on(function(what)
    if what == "warp" and CMSquad.win then CMSquad.win:close() end
end)

return CMSquad
