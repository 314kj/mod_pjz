-- Cookie Mission - in-game admin panel (cards, places, reward pools, log)
require "CM_UI_Kit"
require "CM_UI_Board"

local C = CMUI.C
local T = CMC.txt

CMAdmin = CMAdmin or {}
CMAdmin.Win = CMUI.Window:derive("CMAdmin_Win")
local AW = CMAdmin.Win

local TYPES = CM.TYPES

function AW:new(x, y, w, h)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = T("IGUI_CM_AdminTitle")
    o.titleIcon = "cm_icon"
    o.tab = "cards"
    o.pool = "guns"
    o.pinTiers = { true, true, true }
    o.typeSel = { 1, 1, 1 }
    return o
end

local function send(cmd, args) CMC.send(cmd, args or {}) end

local armed = { key = nil, at = 0 }
-- a button that needs a second click within 4 s (dangerous actions)
local function danger(win, x, y, h, key, label, fn, opts)
    local hot = armed.key == key and CMC.ms() - armed.at < 4000
    return CMUI.btnA(win, x, y, h, hot and T("IGUI_CM_Sure") or label, function()
        if armed.key == key and CMC.ms() - armed.at < 4000 then
            armed.key = nil
            fn()
        else
            armed.key = key; armed.at = CMC.ms()
        end
    end, hot and "danger" or "ghost", opts)
end

-- ===================================================================== tab: cards
local function drawCards(win, x, y, w, adm)
    local S = CMUI.S
    local fs = UIFont.Small
    local lh = CMUI.fh(fs) + S(4)
    local bh = S(24)
    local reset = CMC.left(adm.reset, CMC.admAt) or 0
    CMUI.text(win, T("IGUI_CM_Today", CM.dayText(adm.day or 0)) .. "   " .. T("IGUI_CM_ResetIn", CM.clock(reset)), x, y, C.text)
    danger(win, x + w - S(150), y - S(3), bh, "rerollAll", T("IGUI_CM_RerollAll"), function() send("reroll", { slot = 0 }) end,
        { minW = S(150) })
    y = y + bh + S(6)
    local ls = adm.stats and adm.stats.lastScan
    if ls then
        local s = T("IGUI_CM_ScanInfo", ls.tier or 0, ls.found or 0, ls.tries or 0)
        if ls.grid == false then s = s .. "  " .. T("IGUI_CM_NoGrid") end
        CMUI.text(win, s, x, y, ls.grid == false and C.bad or C.faint)
        y = y + lh
    end
    if adm.stats and adm.stats.spawnErr then
        CMUI.text(win, CMUI.fit(T("IGUI_CM_SpawnErr", adm.stats.spawnErr), fs, w), x, y, C.bad)
        y = y + lh
    end
    if adm.stats then
        CMUI.text(win, T("IGUI_CM_KillSrc", adm.stats.killsServer or 0, adm.stats.killsClient or 0, adm.stats.rewarded or 0),
            x, y, C.faint)
        y = y + lh
    end
    y = y + S(4)
    for s = 1, 3 do
        local c = adm.cards[s] or { slot = s, status = "none" }
        local tc = CMUI.tierColor(s)
        local top = y
        local boxH = win.cardH and win.cardH[s] or S(120)
        CMUI.rbox(win, x, top, w, boxH, C.panel, 1, 6)
        CMUI.rect(win, x, top, 4, boxH, tc, 1)
        local ix, iw = x + S(12), w - S(24)
        y = top + S(8)
        local head = CMC.tierName(s) .. "  " .. (c.type and CMC.typeName(c.type) or "-") .. "   [" .. T("IGUI_CM_Stat_" .. tostring(c.status)) .. "]"
        CMUI.text(win, head, ix, y, tc, 1, UIFont.Medium)
        y = y + CMUI.fh(UIFont.Medium) + S(4)
        if c.site then
            local st = c.site
            CMUI.text(win, CMUI.fit(CMC.placeText(c) .. "   #" .. tostring(st.bid) .. "   " .. T("IGUI_CM_Size", st.area or 0,
                st.floors or 1) .. (st.pinned and ("  " .. T("IGUI_CM_Pinned")) or ""), fs, iw), ix, y, C.gold)
            y = y + lh
            local co = tostring(st.ax or 0) .. "," .. tostring(st.ay or 0) .. "   [" .. tostring(st.x1 or 0) .. "," ..
                tostring(st.y1 or 0) .. " - " .. tostring(st.x2 or 0) .. "," .. tostring(st.y2 or 0) .. "]"
            CMUI.text(win, T("IGUI_CM_Coords", co), ix, y, C.faint)
            y = y + lh
        end
        CMUI.text(win, CMC.goalText(c.type, c.goal) .. "   " .. T("IGUI_CM_TimeLimit", math.floor((c.limit or 0) / 60)) ..
            "   " .. T("IGUI_CM_TeamCap", c.cap or 0), ix, y, C.dim)
        y = y + lh
        local run = c.run
        if run then
            local prog
            if c.type == "survive" then prog = CM.clock(run.held or 0) .. "/" .. CM.clock(c.goal or 0)
            elseif c.type == "find" then prog = tostring(run.found or 0) .. "/" .. tostring(run.caches or 0)
            elseif c.type == "gang" then prog = tostring(run.gang or 0) .. "/" .. tostring(c.goal or 0)
            elseif CM.isTask(c.type) then prog = tostring(run.tdone or 0) .. "/" .. tostring(run.tasks or 0)
            else prog = tostring(run.kills or 0) .. "/" .. tostring(c.goal or 0) end
            CMUI.text(win, T("IGUI_CM_RunInfo", run.id, prog, run.alive or 0, run.spawned or 0) .. "  [" ..
                T("IGUI_CM_Phase_" .. tostring(run.phase)) .. "]", ix, y, C.text)
            y = y + lh
            local names = {}
            for _, m in ipairs(run.members or {}) do
                names[#names + 1] = tostring(m.n) .. " (" .. tostring(m.st) .. ", " .. tostring(m.k) .. "k, " .. tostring(m.d) .. "m)"
            end
            if #names > 0 then
                y = y + CMUI.para(win, table.concat(names, "  "), ix, y, iw, C.dim, fs, 3)
            end
        end
        y = y + S(4)
        -- actions
        local bx = ix
        local sel = win.typeSel[s] or 1
        CMUI.cycle(win, bx, y, S(130), bh, CMC.typeName(TYPES[sel]),
            function() win.typeSel[s] = CM.mod(sel - 2, #TYPES) + 1 end,
            function() win.typeSel[s] = CM.mod(sel, #TYPES) + 1 end)
        bx = bx + S(136)
        bx = bx + danger(win, bx, y, bh, "rr" .. s, T("IGUI_CM_RerollAs"), function()
            send("reroll", { slot = s, type = TYPES[win.typeSel[s] or 1] })
        end) + S(6)
        bx = bx + danger(win, bx, y, bh, "rn" .. s, T("IGUI_CM_Reroll"), function() send("reroll", { slot = s }) end) + S(6)
        if c.site then
            bx = bx + danger(win, bx, y, bh, "ban" .. s, T("IGUI_CM_BanCard"), function() send("banCard", { slot = s }) end) + S(6)
        end
        if run and run.phase == "live" then
            bx = bx + danger(win, bx, y, bh, "ok" .. s, T("IGUI_CM_ForceOk"), function() send("forceEnd", { slot = s, ok = true }) end) + S(6)
            bx = bx + danger(win, bx, y, bh, "end" .. s, T("IGUI_CM_ForceEnd"), function() send("forceEnd", { slot = s }) end) + S(6)
        end
        if c.status == "cool" then
            bx = bx + CMUI.btnA(win, bx, y, bh, T("IGUI_CM_OpenNow"), function() send("openNow", { slot = s }) end, "ghost") + S(6)
        end
        y = y + bh + S(8)
        win.cardH = win.cardH or {}
        win.cardH[s] = y - top
        y = y + S(8)
    end
    return y
end

-- ===================================================================== tab: places
local function drawPlaces(win, x, y, w, adm)
    local S = CMUI.S
    local fs = UIFont.Small
    local lh = CMUI.fh(fs) + S(4)
    local bh = S(26)
    y = y + CMUI.para(win, T("IGUI_CM_PlacesHelp"), x, y, w, C.dim, fs, 4) + S(6)
    local bx = x
    bx = bx + CMUI.btnA(win, bx, y, bh, T("IGUI_CM_PinHere"), function()
        local tiers = {}
        for t = 1, 3 do if win.pinTiers[t] then tiers[#tiers + 1] = t end end
        send("pinHere", { tiers = tiers })
    end, "primary") + S(10)
    for t = 1, 3 do
        bx = bx + CMUI.toggle(win, bx, y + S(4), CMC.tierName(t), win.pinTiers[t], function() win.pinTiers[t] = not win.pinTiers[t] end) + S(10)
    end
    danger(win, x + w - S(160), y, bh, "banHere", T("IGUI_CM_BanHere"), function() send("banHere", {}) end, { minW = S(160) })
    y = y + bh + S(8)
    -- the building under the admin's feet, read from the map on this client
    local p = CMC.player()
    local here = p and CM.siteAt(p:getX(), p:getY()) or nil
    if here then
        local fits = {}
        for t = 1, 3 do if CM.siteFits(here, t) then fits[#fits + 1] = CMC.tierName(t) end end
        local s = T("IGUI_CM_Here", CMC.kindName(here.kind) .. " - " .. tostring(here.town) .. "  #" .. here.bid,
            T("IGUI_CM_Size", here.area, here.floors), #fits > 0 and table.concat(fits, ", ") or T("IGUI_CM_FitsNone"))
        y = y + CMUI.para(win, s, x, y, w, #fits > 0 and C.good or C.bad, fs, 2) + S(6)
    else
        CMUI.text(win, T("IGUI_CM_HereNone"), x, y, C.faint)
        y = y + lh + S(6)
    end
    y = y + CMUI.section(win, x, y, w, T("IGUI_CM_Pins", #(adm.pins or {})))
    for _, pn in ipairs(adm.pins or {}) do
        CMUI.text(win, CMUI.fit(CMC.kindName(pn.kind) .. " - " .. tostring(pn.town) .. "   #" .. pn.bid .. "   " ..
            T("IGUI_CM_Size", pn.area or 0, 1) .. "   " .. tostring(pn.by or ""), fs, w - S(90)), x, y + S(3), C.text)
        CMUI.btnA(win, x + w - S(80), y, S(22), T("IGUI_CM_Remove"), function() send("unpin", { bid = pn.bid }) end, "ghost",
            { minW = S(80) })
        y = y + S(26)
    end
    y = y + S(8)
    y = y + CMUI.section(win, x, y, w, T("IGUI_CM_Bans", #(adm.bans or {})))
    for _, b in ipairs(adm.bans or {}) do
        CMUI.text(win, CMUI.fit(CMC.kindName(b.kind) .. " - " .. tostring(b.town) .. "   #" .. b.bid .. "   " ..
            tostring(b.by or ""), fs, w - S(90)), x, y + S(3), C.text)
        CMUI.btnA(win, x + w - S(80), y, S(22), T("IGUI_CM_Unban"), function() send("unban", { bid = b.bid }) end, "ghost",
            { minW = S(80) })
        y = y + S(26)
    end
    local _ = lh
    return y
end

-- ===================================================================== tab: rewards
local function heldType()
    local p = CMC.player()
    local it = p and p:getPrimaryHandItem()
    if not it then it = p and p:getSecondaryHandItem() end
    return it and it:getFullType() or nil
end

local function drawRewards(win, x, y, w, adm)
    local S = CMUI.S
    local fs = UIFont.Small
    local bh = S(24)
    local items = {}
    for _, n in ipairs(CM.POOLS) do
        items[#items + 1] = { key = n, label = T("IGUI_CM_Pool_" .. n), badge = tostring(#((adm.pools or {})[n] or {})) }
    end
    CMUI.tabs(win, x, y, w, S(30), items, win.pool, function(k) win.pool = k end)
    y = y + S(38)
    y = y + CMUI.para(win, T("IGUI_CM_PoolHelp"), x, y, w, C.dim, fs, 3) + S(6)
    local held = heldType()
    local bx = x
    bx = bx + CMUI.btnA(win, bx, y, bh, held and T("IGUI_CM_AddHeld", CMC.itemName(held)) or T("IGUI_CM_HoldSomething"), function()
        local ft = heldType()
        if ft then send("poolAdd", { pool = win.pool, t = ft, w = 10, n = 1 }) end
    end, held and "primary" or "ghost", { disabled = held == nil }) + S(8)
    bx = bx + danger(win, bx, y, bh, "preset" .. win.pool, T(win.pool == "legend" and "IGUI_CM_Rescan" or "IGUI_CM_PoolReset"),
        function() send("poolReset", { pool = win.pool }) end) + S(8)
    for t = 1, 3 do
        bx = bx + CMUI.btnA(win, bx, y, bh, T("IGUI_CM_TestReward", t), function() send("testReward", { tier = t }) end, "ghost") + S(4)
    end
    y = y + bh + S(10)
    local list = (adm.pools or {})[win.pool] or {}
    if #list == 0 then
        CMUI.text(win, T("IGUI_CM_PoolEmpty"), x, y, C.faint)
        y = y + S(24)
    end
    for _, e in ipairs(list) do
        local col = e.ok and C.text or C.bad
        local nm = e.ok and CMC.itemName(e.t) or (T("IGUI_CM_Missing") .. " ")
        CMUI.text(win, CMUI.fit(nm .. "   " .. e.t, fs, w - S(330)), x, y + S(4), col)
        local sx = x + w - S(320)
        CMUI.stepper(win, sx, y, S(120), S(22), T("IGUI_CM_Weight", e.w),
            function() send("poolSet", { pool = win.pool, i = e.i, t = e.t, w = math.max(1, e.w - 5) }) end,
            function() send("poolSet", { pool = win.pool, i = e.i, t = e.t, w = e.w + 5 }) end)
        CMUI.stepper(win, sx + S(126), y, S(100), S(22), "x" .. tostring(e.n),
            function() send("poolSet", { pool = win.pool, i = e.i, t = e.t, n = math.max(1, e.n - 1) }) end,
            function() send("poolSet", { pool = win.pool, i = e.i, t = e.t, n = e.n + 1 }) end)
        CMUI.btnA(win, x + w - S(84), y, S(22), T("IGUI_CM_Remove"), function()
            send("poolDel", { pool = win.pool, i = e.i, t = e.t })
        end, "ghost", { minW = S(84) })
        y = y + S(27)
    end
    return y
end

-- ===================================================================== tab: log
local function drawLog(win, x, y, w, adm)
    local S = CMUI.S
    local fs = UIFont.Small
    local lh = CMUI.fh(fs) + S(3)
    y = y + CMUI.section(win, x, y, w, T("IGUI_CM_History"))
    for _, h in ipairs(adm.hist or {}) do
        local s = CMC.tierName(h.slot or 1) .. " " .. CMC.typeName(h.type) .. " @ " .. tostring(h.place) .. " -> " ..
            tostring(h.res) .. "  (" .. table.concat(h.who or {}, ", ") .. ")"
        CMUI.text(win, CMUI.fit(s, fs, w), x, y, h.res == "ok" and C.good or C.dim)
        y = y + lh
    end
    y = y + S(8)
    y = y + CMUI.section(win, x, y, w, T("IGUI_CM_Log") .. "  " .. tostring(adm.build or ""))
    for _, l in ipairs(adm.log or {}) do
        CMUI.text(win, CMUI.fit(l.s, fs, w), x, y, C.faint)
        y = y + lh
    end
    return y
end

function AW:drawBody()
    local S = CMUI.S
    local pad = S(14)
    local top = self.headerH + S(10)
    local w = self.width - pad * 2
    local adm = CMC.adm
    if not CMC.isAdmin() then
        CMUI.text(self, T("IGUI_CM_NotAdmin"), pad, top, C.bad)
        return
    end
    local tabs = {
        { key = "cards", label = T("IGUI_CM_Tab_cards") },
        { key = "places", label = T("IGUI_CM_Tab_places") },
        { key = "rewards", label = T("IGUI_CM_Tab_rewards") },
        { key = "log", label = T("IGUI_CM_Tab_log") },
    }
    CMUI.tabs(self, pad, top, w, S(32), tabs, self.tab, function(k) self.tab = k end)
    top = top + S(42)
    if not adm then
        CMUI.text(self, T("IGUI_CM_Loading"), pad, top, C.dim)
        return
    end
    local h = self.height - top - S(10)
    self:form("adm_" .. self.tab, pad, top, w - S(10), h, function(y)
        if self.tab == "cards" then drawCards(self, pad, y, w - S(12), adm)
        elseif self.tab == "places" then drawPlaces(self, pad, y, w - S(12), adm)
        elseif self.tab == "rewards" then drawRewards(self, pad, y, w - S(12), adm)
        else drawLog(self, pad, y, w - S(12), adm) end
    end)
end

function AW:onClosed()
    CMAdmin.win = nil
    send("admClose", {})
end

function CMAdmin.open()
    if not CMC.isAdmin() then return end
    if CMAdmin.win then CMAdmin.win:bringToTop(); return end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(860, 640)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = AW:new(math.floor((sw - w) / 2) + 40, math.floor((sh - h) / 2), w, h)
    win:show()
    CMAdmin.win = win
    send("admOpen", {})
end

function CMAdmin.close()
    if CMAdmin.win then CMAdmin.win:close() end
end

function CMAdmin.toggle()
    if CMAdmin.win then CMAdmin.close() else CMAdmin.open() end
end

return CMAdmin
