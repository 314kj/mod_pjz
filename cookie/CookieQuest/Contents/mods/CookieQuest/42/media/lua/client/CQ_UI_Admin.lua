-- Cookie Quest - admin window: shell, shared widgets, dashboard, buffs, radio, players, settings
require "CQ_UI_Kit"
require "CQ_UI_Map"

CQAdmin = CQAdmin or {}
local C = CQUI.C
local T = CQC.txt
local FS, FM = UIFont.Small, UIFont.Medium

CQAdmin.Win = CQUI.Window:derive("CQAdmin_Win")
local A = CQAdmin.Win
local NAV_BASE = 172

local function fh() return CQUI.fh(FS) end
local function eh() return CQUI.fh(FS) + 8 end
local S = CQUI.S
CQAdmin.fh, CQAdmin.eh = fh, eh

CQAdmin.PAGES = {
    { key = "dash", icon = "cq_s_admin" },
    { key = "plays", icon = "cq_pin" },
    { key = "events", icon = "cq_s_hold" },
    { key = "missions", icon = "cq_s_reach" },
    { key = "buffs", icon = "cq_buff_up" },
    { key = "radio", icon = "cq_s_radio" },
    { key = "players", icon = "cq_s_rescue" },
    { key = "settings", icon = "cq_s_collect" },
}

function A:new(x, y, w, h)
    local o = CQUI.Window.new(self, x, y, w, h)
    o.title = "Cookie Quest"
    o.subtitle = T("IGUI_CQ_AdminTitle")
    o.page = "dash"
    o.sub = { events = "gen", missions = "info", buffs = "now" }
    o.E = {}
    o.placed = {}
    o.loaded = {}
    o.sel = {}
    o.ed = {}
    o.dirty = {}
    o.addN = {}
    o.confirm = {}
    o.stepSel = 1
    o.roleSel = 1
    o.manual = { mult = 2, hours = 2, skills = {} }
    o.penGive = { mult = 0.5, days = 3 }
    o.pickEvent = nil
    o.pickMission = nil
    return o
end

-- ===================================================================== entries (real text boxes, placed each frame)
function A:createChildren()
    ISPanel.createChildren(self)
    local f = fh()
    local function mk(name, h, opts)
        local e = CQUI.entry(self, 0, 0, 100, h, opts)
        e:setVisible(false)
        self.E[name] = e
    end
    local h1 = eh()
    mk("evTitle", h1, { max = 80 })
    mk("evDesc", f * 6 + 10, { multi = true, lines = 60, max = 2000 })
    mk("evTime", h1, { max = 5 })
    mk("roleName", h1, { max = 40 })
    mk("phName", h1, { max = 40 })
    mk("plSearch", h1, { max = 40 })
    mk("spName", h1, { max = 40 })
    mk("roleDesc", f * 4 + 10, { multi = true, lines = 30, max = 600 })
    mk("item_kit", h1, { max = 120 })
    mk("item_rkit", h1, { max = 120 })
    mk("item_rew", h1, { max = 120 })
    mk("item_st", h1, { max = 120 })
    mk("mTitle", h1, { max = 80 })
    mk("mStory", f * 12 + 10, { multi = true, lines = 200, max = 4000 })
    mk("mRewardText", h1, { max = 160 })
    mk("stLabel", h1, { max = 120 })
    mk("stHint", h1, { max = 300 })
    mk("stTarget", h1, { max = 60 })
    mk("stCh", h1, { max = 10 })
    mk("bLabel", h1, { max = 60 })
    mk("bFrom", h1, { max = 5 })
    mk("bTo", h1, { max = 5 })
    mk("manLabel", h1, { max = 60 })
    mk("rName", h1, { max = 60 })
    mk("rCh", h1, { max = 10 })
    mk("rLines", f * 12 + 10, { multi = true, lines = 60, max = 8000 })
end

function A:place(name, x, y, w, h)
    local e = self.E[name]
    if not e then return end
    w = w or e:getWidth()
    h = h or e:getHeight()
    self:grow(y + h)
    local c = self.clip
    if c and (y < c.y - 1 or y + h > c.y + c.h + 1) then
        -- a real text box cannot be clipped: show a stand-in while it is scrolled partly out of view
        local a = self.curArea
        CQUI.rbox(self, x, y, w, h, C.dark, 0.8, 4)
        local first = string.match(CQUI.val(e) or "", "^[^\n]*") or ""
        CQUI.text(self, CQUI.fit(first, FS, w - 12), x + 6, math.max(y, c.y) + 4, C.faint)
        self:hit(x, y, w, h, function()
            if not a then return end
            local d = (y < c.y) and (y - c.y - 6) or (y + h - (c.y + c.h) + 6)
            self.scroll[a.key] = math.max(0, (self.scroll[a.key] or 0) + d)
        end)
        return
    end
    if e:getX() ~= x then e:setX(x) end
    if e:getY() ~= y then e:setY(y) end
    if w and e:getWidth() ~= w then e:setWidth(w) end
    if h and e:getHeight() ~= h then e:setHeight(h) end
    self.placed[name] = true
    if not e:isVisible() then e:setVisible(true) end
end

function A:setE(name, v)
    CQUI.setVal(self.E[name], v)
    self.loaded[name] = tostring(v or "")
end

function A:getE(name) return CQUI.val(self.E[name]) end

function A:eChanged(names)
    for i = 1, #names do
        if self:getE(names[i]) ~= (self.loaded[names[i]] or "") then return true end
    end
    return false
end

function A:prerender()
    self.placed = {}
    CQUI.Window.prerender(self)
    for name, e in pairs(self.E) do
        if not self.placed[name] and e:isVisible() then
            e:setVisible(false)
            if e.unfocus then pcall(function() e:unfocus() end) end
        end
    end
end

function A:confirmBtn(key, x, y, w, h, label, fn, style)
    local armed = self.confirm[key] and getTimestampMs() - self.confirm[key] < 3500
    if armed then
        CQUI.btn(self, x, y, w, h, T("IGUI_CQ_Sure"), function() self.confirm[key] = nil; fn() end, "danger")
    else
        CQUI.btn(self, x, y, w, h, label, function() self.confirm[key] = getTimestampMs() end, style or "ghost")
    end
end

-- ===================================================================== wrapping action bar
-- row count comes from the previous frame, so the bar can grow upward before the form is drawn
function A:barTop(key, y, h, h1)
    local rows = (self.barRows and self.barRows[key]) or 1
    return y + h - rows * (h1 + 6)
end

function A:barBegin(key, x, y, w, h1, rightW)
    self.bar = { key = key, x0 = x, x = x, y = y, w = w, h1 = h1, rightW = rightW or 0, rows = 1 }
end

function A:barNext(bw)
    local b = self.bar
    local limit = b.x0 + b.w - ((b.rows == 1 and b.rightW > 0) and (b.rightW + 6) or 0)
    if b.x > b.x0 and b.x + bw > limit then
        b.rows = b.rows + 1
        b.x = b.x0
        b.y = b.y + b.h1 + 6
    end
    local px, py = b.x, b.y
    b.x = b.x + bw + 6
    return px, py
end

function A:barBtn(label, fn, style, opts)
    local bw = CQUI.tw((opts and opts.font) or FS, label) + 22
    if opts and opts.minW and bw < opts.minW then bw = opts.minW end
    local bx, by = self:barNext(bw)
    CQUI.btn(self, bx, by, bw, self.bar.h1, label, fn, style, opts)
end

function A:barConfirm(key, label, fn, style)
    local bw = CQUI.tw(FS, label) + 22
    local bx, by = self:barNext(bw)
    self:confirmBtn(key, bx, by, bw, self.bar.h1, label, fn, style)
end

function A:barEnd()
    self.barRows = self.barRows or {}
    self.barRows[self.bar.key] = self.bar.rows
end

function A:label(s, x, y, c)
    CQUI.text(self, s, x, y, c or C.dim)
    return fh() + 3
end

-- ===================================================================== item search
local itemIndex = nil
function CQAdmin.search(q, max)
    if not itemIndex then
        itemIndex = {}
        pcall(function()
            local all = getScriptManager():getAllItems()
            for i = 0, all:size() - 1 do
                local it = all:get(i)
                local ft = it:getFullName()
                local dn = it:getDisplayName() or ft
                if ft then itemIndex[#itemIndex + 1] = { ft = ft, n = tostring(dn), s = string.lower(ft .. " " .. tostring(dn)) } end
            end
        end)
    end
    local out = {}
    q = string.lower(CQ.trim(q or ""))
    if q == "" then return out end
    for i = 1, #itemIndex do
        local e = itemIndex[i]
        if string.find(e.s, q, 1, true) then
            out[#out + 1] = e
            if #out >= (max or 6) then break end
        end
    end
    return out
end

-- ===================================================================== shared widgets
-- single item picker row (entry + hand + validity + suggestions); returns new y, current valid fullType or nil
function A:itemPick(key, x, y, w, extraRightW)
    local name = "item_" .. key
    local h = eh()
    local handW = CQUI.tw(FS, T("IGUI_CQ_FromHand")) + 20
    local ew = w - handW - 6 - (extraRightW or 0)
    self:place(name, x, y, ew, h)
    CQUI.btn(self, x + ew + 6, y, handW, h, T("IGUI_CQ_FromHand"), function()
        local p = CQC.player()
        local it = p and p:getPrimaryHandItem()
        if it then self:setE(name, it:getFullType()); self.loaded[name] = "" end
    end, "ghost", { tip = T("IGUI_CQ_FromHandTip") })
    local q = CQ.trim(self:getE(name))
    local valid = CQC.itemValid(q)
    local ny = y + h + 3
    if q ~= "" then
        if valid then
            local tex = CQC.itemTexture(q)
            if tex then self:drawTextureScaledAspect(tex, x, ny, fh(), fh(), 1, 1, 1, 1) end
            CQUI.text(self, CQC.itemName(q), x + fh() + 4, ny, C.good)
            ny = ny + fh() + 3
        else
            local res = CQAdmin.search(q, 5)
            if #res == 0 then
                CQUI.text(self, T("IGUI_CQ_NoItem"), x, ny, C.bad)
                ny = ny + fh() + 3
            else
                for _, r in ipairs(res) do
                    local over = self:hit(x, ny, w, fh() + 2, function() self:setE(name, r.ft); self.loaded[name] = "" end)
                    if over then CQUI.rbox(self, x, ny, w, fh() + 2, C.panel3, 1, 3) end
                    CQUI.text(self, CQUI.fit(r.n .. "   " .. r.ft, FS, w - 8), x + 4, ny, over and C.gold or C.dim)
                    ny = ny + fh() + 3
                end
            end
        end
    end
    return ny, valid and q or nil
end

-- item list editor (kit / rewards); list is edited in place; returns new y
function A:itemEditor(key, list, x, y, w, onChange)
    local h = eh()
    local addW = CQUI.tw(FS, T("IGUI_CQ_Add")) + 20
    local stW = S(92)
    local n = self.addN[key] or 1
    local ny, valid = self:itemPick(key, x, y, w, stW + addW + 12)
    local ew = self.E["item_" .. key]:getWidth()
    local handW = w - ew - 6 - stW - addW - 12
    local sx = x + ew + 6 + handW + 6
    CQUI.stepper(self, sx, y, stW, h, "x" .. tostring(n),
        function() self.addN[key] = math.max(1, n - 1) end, function() self.addN[key] = math.min(999, n + 1) end)
    CQUI.btn(self, sx + stW + 6, y, addW, h, T("IGUI_CQ_Add"), function()
        list[#list + 1] = { t = valid, n = n }
        self:setE("item_" .. key, "")
        if onChange then onChange() end
    end, "primary", { disabled = valid == nil })
    y = ny + 2
    if #list == 0 then
        CQUI.text(self, T("IGUI_CQ_NoItems"), x + 4, y, C.faint)
        return y + fh() + 4
    end
    for i = 1, #list do
        local it = list[i]
        local rh = fh() + 6
        CQUI.rbox(self, x, y, w, rh, C.panel2, 1, 4)
        local tex = CQC.itemTexture(it.t)
        if tex then self:drawTextureScaledAspect(tex, x + 4, y + 3, fh(), fh(), 1, 1, 1, 1) end
        local ok = CQC.itemValid(it.t)
        CQUI.text(self, CQUI.fit(CQC.itemName(it.t) .. "  (" .. it.t .. ")", FS, w - S(170)), x + fh() + 10, y + 3, ok and C.text or C.bad)
        local bx = x + w - S(150)
        CQUI.stepper(self, bx, y + 1, S(96), rh - 2, "x" .. tostring(it.n),
            function() it.n = math.max(1, it.n - 1); if onChange then onChange() end end,
            function() it.n = math.min(999, it.n + 1); if onChange then onChange() end end)
        CQUI.btn(self, x + w - S(46), y + 1, S(42), rh - 2, "x", function()
            table.remove(list, i)
            if onChange then onChange() end
        end, "danger")
        y = y + rh + 3
    end
    return y + 2
end

-- toggle list of missions from the library (ids edited in place)
function A:missionPicker(key, ids, x, y, w, h, onChange, phMap, nPh)
    local adm = CQC.adm
    local list = {}
    for id, m in pairs((adm and adm.missions) or {}) do list[#list + 1] = m end
    table.sort(list, function(a, b) return tostring(a.title) < tostring(b.title) end)
    CQUI.rbox(self, x, y, w, h, C.bg, 1, 6)
    local off = self:beginScroll("mp" .. key, x, y + 4, w, h - 8)
    local cy = y + 6 - off
    if #list == 0 then
        CQUI.text(self, T("IGUI_CQ_NoMissionLib"), x + 8, cy, C.faint)
        cy = cy + fh() + 4
    end
    local phased = phMap ~= nil and (nPh or 1) > 1
    local cw = S(104)
    for _, m in ipairs(list) do
        local on = CQ.indexOf(ids, m.id) ~= nil
        local tw = w - S(50) - ((phased and on) and (cw + 8) or 0)
        CQUI.toggle(self, x + 8, cy, CQUI.fit(m.title .. "  (" .. tostring(#m.steps) .. ")", FS, tw), on, function()
            local idx = CQ.indexOf(ids, m.id)
            if idx then table.remove(ids, idx); if phMap then phMap[m.id] = nil end else ids[#ids + 1] = m.id end
            if onChange then onChange() end
        end)
        if phased and on then
            -- which phase this mission belongs to
            local cur = CQ.clamp(CQ.phaseOf(phMap, m.id), 1, nPh)
            local function setPh(v)
                v = CQ.clamp(v, 1, nPh)
                phMap[m.id] = (v > 1) and v or nil
                if onChange then onChange() end
            end
            CQUI.cycle(self, x + w - cw - 14, cy - 2, cw, fh() + 4, T("IGUI_CQ_PhN", cur),
                function() setPh(cur - 1) end, function() setPh(cur + 1) end, { tip = T("IGUI_CQ_PhPickTip") })
        end
        cy = cy + fh() + 6
    end
    self:endScroll(cy + off - y)
end

-- skill chips (max 5); skills edited in place
function A:skillPicker(key, skills, x, y, w, h, onChange)
    local list = CQC.skills()
    CQUI.rbox(self, x, y, w, h, C.bg, 1, 6)
    local cols = math.max(1, math.floor((w - 12) / S(150)))
    local cw = (w - 12) / cols
    local off = self:beginScroll("sk" .. key, x, y + 4, w, h - 8)
    local cy = y + 6 - off
    local col = 0
    for _, s in ipairs(list) do
        local idx = nil
        for i = 1, #skills do if string.lower(skills[i]) == string.lower(s.id) then idx = i end end
        CQUI.toggle(self, x + 8 + col * cw, cy, CQUI.fit(s.name, FS, cw - 30), idx ~= nil, function()
            if idx then table.remove(skills, idx)
            elseif #skills < 5 then skills[#skills + 1] = s.id end
            if onChange then onChange() end
        end, { disabled = (idx == nil and #skills >= 5) })
        col = col + 1
        if col >= cols then col = 0; cy = cy + fh() + 6 end
    end
    if col > 0 then cy = cy + fh() + 6 end
    self:endScroll(cy + off - y)
end

-- ===================================================================== navigation + body
function A:drawBody()
    local W, H = self.width, self.height
    local NAV_W = math.min(S(NAV_BASE), math.max(NAV_BASE, math.floor(W * 0.17)))
    local top = self.headerH + 2
    CQUI.rect(self, 0, top, NAV_W, H - top - 10, C.panel, 0.7)
    local ny = top + 12
    for _, pg in ipairs(CQAdmin.PAGES) do
        local sel = self.page == pg.key
        local ih = fh() + 18
        local over = self:hit(8, ny, NAV_W - 16, ih, function()
            if self.page ~= pg.key then self:leavePage(); self.page = pg.key end
        end)
        if sel then
            CQUI.rbox(self, 8, ny, NAV_W - 16, ih, C.panel3, 1, 6)
            CQUI.rbox(self, 8, ny + 6, 3, ih - 12, C.accent, 1, 1)
        elseif over then
            CQUI.rbox(self, 8, ny, NAV_W - 16, ih, C.panel2, 1, 6)
        end
        CQUI.icon(self, pg.icon, 20, ny + (ih - 16) / 2, 16, sel and C.accent or C.dim)
        CQUI.text(self, T("IGUI_CQ_Nav_" .. pg.key), 44, ny + (ih - fh()) / 2, sel and C.gold or C.text)
        ny = ny + ih + 4
    end
    if CQC.adm then
        CQUI.text(self, CQC.adm.build or "", 14, H - fh() - 16, C.faint)
    end
    local x, y = NAV_W + 14, top + 12
    local w, h = W - x - 14, H - y - 14
    if not CQC.adm then
        CQUI.textC(self, T("IGUI_CQ_Loading"), x + w / 2, y + 60, C.dim)
        return
    end
    self.mapUsed = false
    local fn = self["page_" .. self.page]
    if fn then fn(self, x, y, w, h) end
    -- map overlay / map pick / ground preview only while an editor that uses them is on screen
    if self.page ~= "missions" and not self.mapUsed then
        CQMap.adminZones = nil
        CQMap.pick = nil
        if CQAdmin.clearPreview then CQAdmin.clearPreview() end
    end
end

function A:leavePage()
    if self.page == "missions" and self.commitStep then self:commitStep() end
    CQMap.adminZones = nil
    CQMap.pick = nil
end

-- ===================================================================== dashboard
function A:page_dash(x, y, w, h)
    local adm = CQC.adm
    local now = CQC.now()
    local off = self:beginScroll("dash", x, y, w, h)
    local cy = y - off
    cy = cy + CQUI.section(self, x, cy, w - 10, T("IGUI_CQ_DashEvents"))
    local evs = {}
    for _, id in ipairs(CQ.sortedKeys(adm.events)) do
        local e = adm.events[id]
        if e.status == "live" or e.status == "sched" then evs[#evs + 1] = e end
    end
    if #evs == 0 then
        CQUI.text(self, T("IGUI_CQ_DashNoEvent"), x + 4, cy, C.faint)
        cy = cy + fh() + 12
    end
    for _, e in ipairs(evs) do
        local cardY = cy
        local ch = self.dashH and self.dashH[e.id] or 100
        CQUI.rbox(self, x, cardY, w - 10, ch, C.panel, 1, 8)
        CQUI.rbox(self, x, cardY, 4, ch, e.status == "live" and C.good or C.accent, 1, 2)
        local px = x + 14
        local yy = cardY + 10
        local pw = CQUI.pill(self, px, yy + 2, T("IGUI_CQ_St_" .. e.status), e.status == "live" and C.good or C.accent, FS, true)
        CQUI.text(self, CQUI.fit(e.title, FM, w - S(380)), px + pw + 8, yy, C.text, 1, FM)
        local cd
        if e.status == "sched" then cd = T("IGUI_CQ_StartsIn", CQUI.dur((e.start or now) - now))
        else cd = T("IGUI_CQ_EndsIn", CQUI.dur((e.start or now) + (e.dur or 0) * 60 - now)) end
        CQUI.textR(self, cd, x + w - 24, yy + 2, C.dim)
        yy = yy + CQUI.fh(FM) + 8
        local bx = px
        if e.status == "sched" then
            bx = bx + CQUI.btnA(self, bx, yy, eh(), T("IGUI_CQ_StartNow"), function() CQC.send("eventCtl", { id = e.id, op = "start" }) end, "primary") + 6
        else
            local lw = CQUI.tw(FS, T("IGUI_CQ_EndNow")) + 22
            self:confirmBtn("end" .. e.id, bx, yy, lw, eh(), T("IGUI_CQ_EndNow"), function() CQC.send("eventCtl", { id = e.id, op = "end" }) end, "danger")
            bx = bx + lw + 6
            bx = bx + CQUI.btnA(self, bx, yy, eh(), T("IGUI_CQ_GiveKits"), function() CQC.send("eventCtl", { id = e.id, op = "kits" }) end, "ghost", { tip = T("IGUI_CQ_GiveKitsTip") }) + 6
        end
        bx = bx + CQUI.btnA(self, bx, yy, eh(), T("IGUI_CQ_Edit"), function()
            self:leavePage(); self.page = "events"; self:selectEvent(e.id)
        end, "ghost") + 6
        yy = yy + eh() + 8
        -- phases: where the event is now, how many are in each phase, open the next one
        local nPh = #(e.phases or {})
        if e.status == "live" and nPh > 1 then
            local cur = e.phase or 1
            local nm = (e.phases[cur] and e.phases[cur].name ~= "" and e.phases[cur].name) or T("IGUI_CQ_PhN", cur)
            local tx = px + CQUI.pill(self, px, yy + 3, T("IGUI_CQ_PhOf", cur, nPh), C.gold, FS, true) + 8
            CQUI.text(self, CQUI.fit(nm, FS, S(260)), tx, yy + 3, C.text)
            local counts = {}
            for _, pt in pairs(e.parts or {}) do
                local n = pt.ph or 0
                if n > 0 then counts[n] = (counts[n] or 0) + 1 end
            end
            local cs = {}
            for i = 1, nPh do if counts[i] then cs[#cs + 1] = T("IGUI_CQ_PhCount", i, counts[i]) end end
            local rx = x + w - 24
            if cur < nPh then
                local lw = CQUI.tw(FS, T("IGUI_CQ_PhNext")) + 22
                rx = rx - lw
                self:confirmBtn("phnext" .. e.id, rx, yy, lw, eh(), T("IGUI_CQ_PhNext"), function()
                    CQC.send("eventCtl", { id = e.id, op = "phase" })
                end, "good")
                rx = rx - 10
            end
            CQUI.textR(self, CQUI.fit(table.concat(cs, "   "), FS, math.max(40, rx - tx - S(270))), rx, yy + 3, C.dim)
            yy = yy + eh() + 8
        end
        -- zombie spawn points of this event
        if e.status == "live" and e.spawns and #e.spawns > 0 then
            local on, kills = 0, 0
            for _, sp in ipairs(e.spawns) do
                local ss = e.spawnState and e.spawnState[sp.id]
                if not (ss and ss.stopped) then on = on + 1 end
                kills = kills + ((ss and ss.kills) or 0)
            end
            CQUI.icon(self, "cq_s_kill", px, yy + 3, fh(), C.bad)
            CQUI.text(self, T("IGUI_CQ_SpDash", on, #e.spawns, kills), px + fh() + 6, yy + 3, on > 0 and C.text or C.faint)
            if on > 0 then
                local lw = CQUI.tw(FS, T("IGUI_CQ_SpAllOff")) + 22
                self:confirmBtn("spoff" .. e.id, x + w - 24 - lw, yy, lw, eh(), T("IGUI_CQ_SpAllOff"), function()
                    CQC.send("eventCtl", { id = e.id, op = "spawnAll" })
                end, "danger")
            end
            yy = yy + eh() + 8
        end
        -- participants
        local parts = CQ.sortedKeys(e.parts or {})
        CQUI.text(self, T("IGUI_CQ_PartsTitle", #parts), px, yy, C.gold)
        yy = yy + fh() + 4
        for _, k in ipairs(parts) do
            local pt = e.parts[k]
            local rh = fh() + 8
            CQUI.rbox(self, px, yy, w - 38, rh, C.panel2, 1, 4)
            local onl = false
            for _, u in ipairs(adm.users or {}) do if u.k == k then onl = u.online end end
            CQUI.rbox(self, px + 8, yy + rh / 2 - 4, 8, 8, onl and C.good or C.faint, 1, 4)
            CQUI.text(self, CQUI.fit(pt.name or k, FS, S(160)), px + 22, yy + 4, C.text)
            local cx = px + S(190)
            if e.roleMode ~= "none" and #e.roles > 0 then
                local rname = T("IGUI_CQ_NoRole")
                local ri = 0
                for i, r in ipairs(e.roles) do if r.id == pt.role then rname = r.name; ri = i end end
                CQUI.cycle(self, cx, yy + 2, S(180), rh - 4, rname, function()
                    local ni = ri - 1
                    if ni < 1 then ni = #e.roles end
                    CQC.send("setRole", { eid = e.id, k = k, role = e.roles[ni].id })
                end, function()
                    local ni = ri + 1
                    if ni > #e.roles then ni = 1 end
                    CQC.send("setRole", { eid = e.id, k = k, role = e.roles[ni].id })
                end, { tip = T("IGUI_CQ_SetRoleTip") })
                cx = cx + S(190)
            end
            CQUI.stepper(self, cx, yy + 2, S(100), rh - 4, "CP " .. tostring(pt.cp or 0),
                function() CQC.send("part", { eid = e.id, k = k, op = "cp", cp = math.max(0, (pt.cp or 0) - 1) }) end,
                function() CQC.send("part", { eid = e.id, k = k, op = "cp", cp = (pt.cp or 0) + 1 }) end, { tip = T("IGUI_CQ_CpTip") })
            cx = cx + S(108)
            local ks, kc = T("IGUI_CQ_KitNo"), C.faint
            if pt.got then ks, kc = T("IGUI_CQ_KitYes"), C.good elseif pt.kit then ks, kc = T("IGUI_CQ_KitPending"), C.accent end
            CQUI.text(self, ks, cx, yy + 4, kc)
            if e.status == "live" and nPh > 1 and (pt.ph or 0) > 0 then
                CQUI.text(self, T("IGUI_CQ_PhN", pt.ph), cx + CQUI.tw(FS, ks) + 12, yy + 4, C.gold)
            end
            local rw = CQUI.tw(FS, T("IGUI_CQ_Remove")) + 18
            self:confirmBtn("rm" .. e.id .. k, px + w - 38 - rw - 4, yy + 2, rw, rh - 4, T("IGUI_CQ_Remove"), function()
                CQC.send("part", { eid = e.id, k = k, op = "remove" })
            end)
            yy = yy + rh + 3
        end
        yy = yy + 8
        self.dashH = self.dashH or {}
        self.dashH[e.id] = yy - cardY
        cy = cardY + self.dashH[e.id] + 10
    end
    -- running missions: summary here, the full list lives on the "players' missions" page
    cy = cy + 6
    cy = cy + CQUI.section(self, x, cy, w - 10, T("IGUI_CQ_DashMissions"))
    local nAct, people, stuck = 0, {}, 0
    for _, inst in ipairs(adm.inst or {}) do
        if inst.status == "active" then
            nAct = nAct + 1
            for k in pairs(inst.members or {}) do people[k] = true end
            if inst.wait and #inst.wait > 0 then stuck = stuck + 1 end
        end
    end
    CQUI.text(self, T("IGUI_CQ_PlSummary", nAct, CQ.count(people)), x + 4, cy + 4, nAct > 0 and C.text or C.faint)
    if stuck > 0 then CQUI.text(self, T("IGUI_CQ_PlStuck", stuck), x + 4 + CQUI.tw(FS, T("IGUI_CQ_PlSummary", nAct, CQ.count(people))) + 14, cy + 4, C.accent) end
    local ow = CQUI.tw(FS, T("IGUI_CQ_PlOpen")) + 26
    CQUI.btn(self, x + w - 20 - ow, cy, ow, eh(), T("IGUI_CQ_PlOpen"), function() self:leavePage(); self.page = "plays" end, "primary")
    cy = cy + eh() + 10
    -- global missions
    local gk = CQ.sortedKeys(adm.globalM or {})
    if #gk > 0 then
        cy = cy + 6
        cy = cy + CQUI.section(self, x, cy, w - 10, T("IGUI_CQ_DashGlobal"))
        for _, mid in ipairs(gk) do
            local m = adm.missions[mid]
            CQUI.text(self, (m and m.title or mid), x + 8, cy + 3, C.text)
            local lw = CQUI.tw(FS, T("IGUI_CQ_Stop")) + 22
            CQUI.btn(self, x + w - 20 - lw, cy, lw, eh(), T("IGUI_CQ_Stop"), function() CQC.send("stopGlobal", { mid = mid }) end, "danger")
            cy = cy + eh() + 4
        end
    end
    self:endScroll(cy + off - y + 10)
end


-- ===================================================================== buffs
function A:page_buffs(x, y, w, h)
    local adm = CQC.adm
    CQUI.tabs(self, x, y, w, fh() + 12, {
        { key = "now", label = T("IGUI_CQ_BuffNow") },
        { key = "sched", label = T("IGUI_CQ_BuffSched"), badge = tostring(CQ.count(adm.buffs.sched)) },
    }, self.sub.buffs, function(k) self.sub.buffs = k end)
    y = y + fh() + 20
    h = h - fh() - 20
    local sub = self.sub.buffs
    self:form("fb_" .. sub, x, y, w - 10, h, function(top)
        if sub == "now" then self:buffsNow(x, top, w - 10, h) else self:buffsSched(x, top, w - 10, h) end
    end)
end

function A:buffsNow(x, y, w, h)
    local adm = CQC.adm
    local now = CQC.now()
    y = y + CQUI.section(self, x, y, w, T("IGUI_CQ_ActiveBuffs"))
    if #(adm.active or {}) == 0 then
        CQUI.text(self, T("IGUI_CQ_NoBuff"), x + 4, y, C.faint)
        y = y + fh() + 8
    end
    for _, b in ipairs(adm.active or {}) do
        local skills = (#(b.skills or {}) == 0) and T("IGUI_CQ_AllSkills") or table.concat(b.skills, ", ")
        local src = b.k == "m" and T("IGUI_CQ_Manual") or ((b.label ~= "" and b.label) or T("IGUI_CQ_Schedule"))
        CQUI.rbox(self, x, y, w, fh() + 10, C.panel, 1, 6)
        CQUI.icon(self, "cq_buff_up", x + 8, y + 5, fh(), C.gold)
        CQUI.text(self, "EXP x" .. CQ.fmt(b.mult, 2) .. "   " .. src .. "   -   " .. CQUI.fit(skills, FS, w - S(360)), x + fh() + 14, y + 5, C.text)
        CQUI.textR(self, T("IGUI_CQ_Until", CQUI.dur(b.untilTs - now)), x + w - 10, y + 5, C.dim)
        y = y + fh() + 14
    end
    y = y + 8
    y = y + CQUI.section(self, x, y, w, T("IGUI_CQ_ManualBuff"))
    local m = self.manual
    local h1 = eh()
    self:label(T("IGUI_CQ_Mult"), x, y)
    self:label(T("IGUI_CQ_Hours"), x + S(170), y)
    self:label(T("IGUI_CQ_LabelOpt"), x + S(340), y)
    y = y + fh() + 4
    CQUI.stepper(self, x, y, S(150), h1, "x" .. CQ.fmt(m.mult, 2),
        function() m.mult = math.max(0.25, m.mult - 0.25) end, function() m.mult = math.min(10, m.mult + 0.25) end)
    CQUI.stepper(self, x + S(170), y, S(150), h1, CQ.fmt(m.hours, 2) .. " h",
        function() m.hours = math.max(0.5, m.hours - 0.5) end, function() m.hours = math.min(72, m.hours + 0.5) end)
    self:place("manLabel", x + S(340), y, w - S(340), h1)
    y = y + h1 + 10
    self:label(T("IGUI_CQ_SkillPick", #m.skills), x, y)
    y = y + fh() + 4
    self:skillPicker("man", m.skills, x, y, w, S(130))
    y = y + S(130) + 8
    local bx = x
    bx = bx + CQUI.btnA(self, bx, y, h1 + 4, T("IGUI_CQ_StartBuff"), function()
        CQC.send("manual", { mult = m.mult, hours = m.hours, skills = m.skills, label = self:getE("manLabel") })
    end, "primary") + 8
    CQUI.btnA(self, bx, y, h1 + 4, T("IGUI_CQ_StopBuff"), function() CQC.send("manual", { stop = true }) end, "danger")
    y = y + h1 + 14
    y = y + CQUI.para(self, T("IGUI_CQ_BuffNote"), x, y, w, C.faint) + 10
    y = y + CQUI.section(self, x, y, w, T("IGUI_CQ_XpTest"))
    local notes = CQC.xpNotes or {}
    if #notes == 0 then
        CQUI.para(self, T("IGUI_CQ_XpNone"), x, y, w, C.faint)
    end
    for i = 1, #notes do
        local n = notes[i]
        local sign = (CQ.num(n.bonus, 0) >= 0) and "+" or ""
        local line = T("IGUI_CQ_XpNote", sign .. CQ.fmt(n.bonus, 2), CQC.skillName(n.pid or ""), CQ.fmt(n.base, 2),
            CQ.fmt(n.mult, 2)) .. "  (" .. T("IGUI_CQ_Side_" .. tostring(n.side or "srv")) .. ")"
        CQUI.text(self, CQUI.fit(line, FS, w), x + 4, y, i == 1 and C.good or C.dim)
        y = y + fh() + 3
    end
end

function A:selectSched(id)
    local adm = CQC.adm
    self.sel.sched = id
    local b = id and adm.buffs.sched[id]
    if not b then
        b = { id = "", on = true, days = { false, false, false, false, false, false, true }, from = 1080, to = 1380, mult = 2, skills = {}, label = "" }
    end
    self.ed.sched = CQ.copy(b)
    self.dirty.sched = false
    self:setE("bLabel", b.label or "")
    self:setE("bFrom", CQ.hhmm(b.from))
    self:setE("bTo", CQ.hhmm(b.to))
end

function A:buffsSched(x, y, w, h)
    local adm = CQC.adm
    local lw = math.min(S(220), math.max(220, math.floor(w * 0.27)))
    local h1 = eh()
    CQUI.btn(self, x, y, lw, h1, T("IGUI_CQ_NewSched"), function() self:selectSched(nil); self.sel.sched = "new" end, "primary")
    local ly = y + h1 + 8
    for _, id in ipairs(CQ.sortedKeys(adm.buffs.sched)) do
        local b = adm.buffs.sched[id]
        local sel = self.sel.sched == id
        local over = self:hit(x, ly, lw, fh() * 2 + 12, function() self:selectSched(id) end)
        CQUI.rbox(self, x, ly, lw, fh() * 2 + 12, sel and C.panel3 or (over and C.panel2 or C.panel), 1, 6)
        CQUI.text(self, CQUI.fit((b.label ~= "" and b.label) or ("EXP x" .. CQ.fmt(b.mult, 2)), FS, lw - 50), x + 10, ly + 5, b.on and C.text or C.faint)
        CQUI.textR(self, "x" .. CQ.fmt(b.mult, 2), x + lw - 8, ly + 5, C.gold)
        local days = {}
        for i = 1, 7 do if b.days[i] then days[#days + 1] = T("IGUI_CQ_WdS" .. (i - 1)) end end
        CQUI.text(self, CQUI.fit(table.concat(days, " ") .. "  " .. CQ.hhmm(b.from) .. "-" .. CQ.hhmm(b.to), FS, lw - 20), x + 10, ly + fh() + 7, C.dim)
        ly = ly + fh() * 2 + 16
    end
    local ex = x + lw + 14
    local ew = w - lw - 14
    local b = self.ed.sched
    if not self.sel.sched or not b then
        CQUI.para(self, T("IGUI_CQ_SchedHint"), ex, y + 10, ew, C.faint)
        return
    end
    local ey = y
    self:label(T("IGUI_CQ_LabelOpt"), ex, ey)
    ey = ey + fh() + 4
    self:place("bLabel", ex, ey, ew - S(120), h1)
    CQUI.toggle(self, ex + ew - S(110), ey + 4, T("IGUI_CQ_Enabled"), b.on, function() b.on = not b.on; self.dirty.sched = true end)
    ey = ey + h1 + 10
    self:label(T("IGUI_CQ_Days"), ex, ey)
    ey = ey + fh() + 4
    local dx = ex
    for i = 1, 7 do
        local on = b.days[i]
        local dw = math.floor((ew - 6 * 6) / 7)
        local over = self:hit(dx, ey, dw, h1, function() b.days[i] = not b.days[i]; self.dirty.sched = true end)
        CQUI.rbox(self, dx, ey, dw, h1, on and C.accent or (over and C.panel3 or C.panel2), 1, 5)
        CQUI.textC(self, T("IGUI_CQ_WdS" .. (i - 1)), dx + dw / 2, ey + 4, on and C.dark or C.text)
        dx = dx + dw + 6
    end
    ey = ey + h1 + 10
    self:label(T("IGUI_CQ_From"), ex, ey)
    self:label(T("IGUI_CQ_To"), ex + S(110), ey)
    self:label(T("IGUI_CQ_Mult"), ex + S(220), ey)
    ey = ey + fh() + 4
    self:place("bFrom", ex, ey, S(90), h1)
    self:place("bTo", ex + S(110), ey, S(90), h1)
    CQUI.stepper(self, ex + S(220), ey, S(150), h1, "x" .. CQ.fmt(b.mult, 2),
        function() b.mult = math.max(0.25, b.mult - 0.25); self.dirty.sched = true end,
        function() b.mult = math.min(10, b.mult + 0.25); self.dirty.sched = true end)
    local fromOk = CQ.parseHHMM(self:getE("bFrom")) ~= nil
    local toOk = CQ.parseHHMM(self:getE("bTo")) ~= nil
    if not fromOk or not toOk then CQUI.text(self, T("IGUI_CQ_BadTime"), ex + S(390), ey + 4, C.bad) end
    ey = ey + h1 + 10
    self:label(T("IGUI_CQ_SkillPick", #b.skills), ex, ey)
    ey = ey + fh() + 4
    self:skillPicker("sched", b.skills, ex, ey, ew, S(150), function() self.dirty.sched = true end)
    ey = ey + S(150) + 8
    -- next run preview
    local test = CQ.copy(b)
    test.from = CQ.parseHHMM(self:getE("bFrom")) or b.from
    test.to = CQ.parseHHMM(self:getE("bTo")) or b.to
    if test.to == 1440 then test.to = 0 end
    local nx = CQ.schedNext(test, CQC.now(), CQC.utc())
    local active = CQ.schedEnd(test, CQC.now(), CQC.utc())
    local info = active and T("IGUI_CQ_SchedActive", CQUI.dateText(active)) or (nx and T("IGUI_CQ_SchedNext", CQUI.dateText(nx)) or T("IGUI_CQ_SchedNever"))
    CQUI.text(self, info, ex, ey, active and C.good or C.dim)
    ey = ey + fh() + 10
    local dirty = self.dirty.sched or self:eChanged({ "bLabel", "bFrom", "bTo" })
    local bx = ex
    bx = bx + CQUI.btnA(self, bx, ey, h1 + 4, T("IGUI_CQ_Save") .. (dirty and " *" or ""), function()
        b.label = self:getE("bLabel")
        b.from = CQ.parseHHMM(self:getE("bFrom")) or b.from
        b.to = CQ.parseHHMM(self:getE("bTo")) or b.to
        CQC.send("saveSched", { b = b })
        self.dirty.sched = false
        self.loaded.bLabel = self:getE("bLabel"); self.loaded.bFrom = self:getE("bFrom"); self.loaded.bTo = self:getE("bTo")
    end, "primary", { disabled = not (fromOk and toOk) }) + 8
    if b.id ~= "" then
        local lw = CQUI.tw(FS, T("IGUI_CQ_Delete")) + 22
        self:confirmBtn("delsched", bx, ey, lw, h1 + 4, T("IGUI_CQ_Delete"), function()
            CQC.send("delSched", { id = b.id }); self.sel.sched = nil; self.ed.sched = nil
        end)
    end
end

-- ===================================================================== radio
function A:selectRadio(id)
    local adm = CQC.adm
    self.sel.radio = id
    local r = id and adm.radio[id]
    if not r then r = { id = "", name = "", ch = 91400, iv = 30, on = true, color = 1, lines = {} } end
    self.ed.radio = CQ.copy(r)
    self.dirty.radio = false
    self:setE("rName", r.name or "")
    self:setE("rCh", CQ.chText(r.ch))
    self:setE("rLines", table.concat(r.lines or {}, "\n"))
end

local function tunedText()
    local t = CQC.lastTuned or {}
    if #t == 0 then return T("IGUI_CQ_NotTuned") end
    local parts = {}
    for i = 1, #t do parts[#parts + 1] = CQ.chText(t[i]) end
    return T("IGUI_CQ_Tuned", table.concat(parts, ", "))
end
CQAdmin.tunedText = tunedText

function A:page_radio(x, y, w, h)
    self:form("fradio", x, y, w - 10, h, function(top) self:radioPage(x, top, w - 10, h) end)
end

function A:radioPage(x, y, w, h)
    local adm = CQC.adm
    local lw = math.min(S(220), math.max(220, math.floor(w * 0.27)))
    local h1 = eh()
    CQUI.btn(self, x, y, lw, h1, T("IGUI_CQ_NewRadio"), function() self:selectRadio(nil); self.sel.radio = "new" end, "primary")
    local ly = y + h1 + 8
    for _, id in ipairs(CQ.sortedKeys(adm.radio)) do
        local r = adm.radio[id]
        local sel = self.sel.radio == id
        local over = self:hit(x, ly, lw, fh() * 2 + 12, function() self:selectRadio(id) end)
        CQUI.rbox(self, x, ly, lw, fh() * 2 + 12, sel and C.panel3 or (over and C.panel2 or C.panel), 1, 6)
        local col = CQ.RADIO_COLORS[r.color or 1] or CQ.RADIO_COLORS[1]
        CQUI.rbox(self, x + 8, ly + 8, 8, 8, { col[1], col[2], col[3] }, 1, 4)
        CQUI.text(self, CQUI.fit((r.name ~= "" and r.name) or "Radio", FS, lw - 90), x + 22, ly + 5, r.on and C.text or C.faint)
        CQUI.textR(self, CQ.chText(r.ch) .. " MHz", x + lw - 8, ly + 5, C.gold)
        CQUI.text(self, T("IGUI_CQ_NLines", #(r.lines or {}), r.iv or 30), x + 22, ly + fh() + 7, C.dim)
        ly = ly + fh() * 2 + 16
    end
    CQUI.para(self, tunedText(), x, ly + 4, lw, C.faint)
    local ex = x + lw + 14
    local ew = w - lw - 14
    local r = self.ed.radio
    if not self.sel.radio or not r then
        CQUI.para(self, T("IGUI_CQ_RadioHint"), ex, y + 10, ew, C.faint)
        return
    end
    local ey = y
    self:label(T("IGUI_CQ_RadioName"), ex, ey)
    ey = ey + fh() + 4
    self:place("rName", ex, ey, ew - S(120), h1)
    CQUI.toggle(self, ex + ew - S(110), ey + 4, T("IGUI_CQ_Enabled"), r.on, function() r.on = not r.on; self.dirty.radio = true end)
    ey = ey + h1 + 10
    self:label(T("IGUI_CQ_Freq"), ex, ey)
    self:label(T("IGUI_CQ_Interval"), ex + S(270), ey)
    self:label(T("IGUI_CQ_Color"), ex + S(430), ey)
    ey = ey + fh() + 4
    self:place("rCh", ex, ey, S(90), h1)
    CQUI.btn(self, ex + S(96), ey, S(160), h1, T("IGUI_CQ_FromRadio"), function()
        local t = CQC.lastTuned or {}
        if #t > 0 then self:setE("rCh", CQ.chText(t[1])); self.loaded.rCh = "" end
    end, "ghost", { tip = T("IGUI_CQ_FromRadioTip") })
    CQUI.stepper(self, ex + S(270), ey, S(140), h1, tostring(r.iv) .. " s",
        function() r.iv = math.max(5, r.iv - 5); self.dirty.radio = true end,
        function() r.iv = math.min(600, r.iv + 5); self.dirty.radio = true end)
    local col = CQ.RADIO_COLORS[r.color or 1]
    CQUI.cycle(self, ex + S(430), ey, S(110), h1, "", function()
        r.color = r.color - 1; if r.color < 1 then r.color = #CQ.RADIO_COLORS end; self.dirty.radio = true
    end, function()
        r.color = r.color + 1; if r.color > #CQ.RADIO_COLORS then r.color = 1 end; self.dirty.radio = true
    end)
    CQUI.rbox(self, ex + S(430) + h1 + 6, ey + 5, S(110) - h1 * 2 - 12, h1 - 10, { col[1], col[2], col[3] }, 1, 4)
    local chOk = CQ.mhzToCh(self:getE("rCh")) ~= nil
    ey = ey + h1 + 4
    CQUI.text(self, tunedText(), ex, ey, C.faint)
    ey = ey + fh() + 8
    self:label(T("IGUI_CQ_Lines"), ex, ey)
    ey = ey + fh() + 4
    local lh = fh() * 12 + 10
    self:place("rLines", ex, ey, ew, lh)
    ey = ey + lh + 8
    -- preview
    local lines = {}
    for l in string.gmatch(self:getE("rLines") .. "\n", "(.-)\n") do
        l = CQ.trim(l)
        if l ~= "" then lines[#lines + 1] = l end
    end
    local test = { lines = lines, iv = r.iv, t0 = r.t0 or CQC.now() }
    local idx, line = CQ.radioLine(test, CQC.now())
    if line then
        CQUI.text(self, CQUI.fit(T("IGUI_CQ_OnAir", idx, #lines) .. "  " .. line, FS, ew), ex, ey, { col[1], col[2], col[3] })
        ey = ey + fh() + 8
    end
    local dirty = self.dirty.radio or self:eChanged({ "rName", "rCh", "rLines" })
    local bx = ex
    bx = bx + CQUI.btnA(self, bx, ey, h1 + 4, T("IGUI_CQ_Save") .. (dirty and " *" or ""), function()
        r.name = self:getE("rName")
        r.ch = CQ.mhzToCh(self:getE("rCh")) or r.ch
        r.lines = lines
        CQC.send("saveRadio", { r = r })
        self.dirty.radio = false
        self.loaded.rName = self:getE("rName"); self.loaded.rCh = self:getE("rCh"); self.loaded.rLines = self:getE("rLines")
    end, "primary", { disabled = not chOk }) + 8
    if r.id ~= "" then
        local lw = CQUI.tw(FS, T("IGUI_CQ_Delete")) + 22
        self:confirmBtn("delradio", bx, ey, lw, h1 + 4, T("IGUI_CQ_Delete"), function()
            CQC.send("delRadio", { id = r.id }); self.sel.radio = nil; self.ed.radio = nil
        end)
    end
end

-- ===================================================================== players & penalties
function A:page_players(x, y, w, h)
    local adm = CQC.adm
    local now = CQC.now()
    local h1 = eh()
    -- controls
    CQUI.rbox(self, x, y, w, h1 * 2 + fh() + 26, C.panel, 1, 8)
    local cx = x + 12
    local cy = y + 8
    self:label(T("IGUI_CQ_PenGive"), cx, cy)
    self:label(T("IGUI_CQ_GiveMission"), cx + S(330), cy)
    cy = cy + fh() + 4
    local pg = self.penGive
    CQUI.stepper(self, cx, cy, S(140), h1, "EXP x" .. CQ.fmt(pg.mult, 2),
        function() pg.mult = math.max(0.1, pg.mult - 0.1) end, function() pg.mult = math.min(0.9, pg.mult + 0.1) end)
    CQUI.stepper(self, cx + S(150), cy, S(160), h1, T("IGUI_CQ_DaysN", CQ.fmt(pg.days, 1)),
        function() pg.days = math.max(0.5, pg.days - 0.5) end, function() pg.days = math.min(30, pg.days + 0.5) end)
    local ml = {}
    for id, m in pairs(adm.missions) do ml[#ml + 1] = m end
    table.sort(ml, function(a, b) return tostring(a.title) < tostring(b.title) end)
    local mi = 0
    for i, m in ipairs(ml) do if m.id == self.pickMission then mi = i end end
    if mi == 0 and #ml > 0 then mi = 1; self.pickMission = ml[1].id end
    CQUI.cycle(self, cx + S(330), cy, w - S(360), h1, mi > 0 and ml[mi].title or T("IGUI_CQ_NoMissionLib"), function()
        if #ml == 0 then return end
        mi = mi - 1; if mi < 1 then mi = #ml end; self.pickMission = ml[mi].id
    end, function()
        if #ml == 0 then return end
        mi = mi + 1; if mi > #ml then mi = 1 end; self.pickMission = ml[mi].id
    end)
    cy = cy + h1 + 6
    -- event target for "add to event"
    local el = {}
    for _, id in ipairs(CQ.sortedKeys(adm.events)) do
        local e = adm.events[id]
        if e.status == "sched" or e.status == "live" then el[#el + 1] = e end
    end
    local ei = 0
    for i, e in ipairs(el) do if e.id == self.pickEvent then ei = i end end
    if ei == 0 and #el > 0 then ei = 1; self.pickEvent = el[1].id end
    CQUI.text(self, T("IGUI_CQ_AddToEvent"), cx, cy + 4, C.dim)
    CQUI.cycle(self, cx + S(150), cy, S(320), h1, ei > 0 and el[ei].title or T("IGUI_CQ_NoOpenEvent"), function()
        if #el == 0 then return end
        ei = ei - 1; if ei < 1 then ei = #el end; self.pickEvent = el[ei].id
    end, function()
        if #el == 0 then return end
        ei = ei + 1; if ei > #el then ei = 1 end; self.pickEvent = el[ei].id
    end)
    y = y + h1 * 2 + fh() + 36
    -- list
    local users = {}
    for _, u in ipairs(adm.users or {}) do users[#users + 1] = u end
    table.sort(users, function(a, b)
        if a.online ~= b.online then return a.online end
        return tostring(a.name) < tostring(b.name)
    end)
    local off = self:beginScroll("players", x, y, w, h - (h1 * 2 + fh() + 36))
    local ly = y - off
    for _, u in ipairs(users) do
        local rh = fh() * 2 + 18
        CQUI.rbox(self, x, ly, w - 10, rh, C.panel, 1, 6)
        CQUI.rbox(self, x + 10, ly + 10, 8, 8, u.online and C.good or C.faint, 1, 4)
        CQUI.text(self, CQUI.fit(u.name or u.k, FS, S(200)), x + 26, ly + 6, C.text)
        local info = T("IGUI_CQ_UserInfo", u.nAct or 0, u.done or 0)
        if (u.pending or 0) > 0 then info = info .. "  " .. T("IGUI_CQ_Pending", u.pending) end
        CQUI.text(self, info, x + 26, ly + fh() + 10, C.dim)
        if u.pen then
            CQUI.text(self, T("IGUI_CQ_PenRow", "x" .. CQ.fmt(u.pen.mult, 2), CQUI.dur(u.pen.untilTs - now)), x + S(240), ly + 6, C.bad)
        end
        local bx = x + w - 20
        local bh = fh() + 8
        local function rbtn(label, fn, style, tip)
            local bw = CQUI.tw(FS, label) + 18
            bx = bx - bw
            CQUI.btn(self, bx, ly + rh - bh - 6, bw, bh, label, fn, style, { tip = tip })
            bx = bx - 6
        end
        if self.pickEvent then
            rbtn(T("IGUI_CQ_AddBtn"), function() CQC.send("part", { eid = self.pickEvent, k = u.k, op = "add" }) end, "ghost", T("IGUI_CQ_AddToEvent"))
        end
        if self.pickMission then
            rbtn(T("IGUI_CQ_GiveBtn"), function() CQC.send("give", { mid = self.pickMission, to = u.name or u.k }) end, "ghost", T("IGUI_CQ_GiveMission"))
        end
        rbtn(T("IGUI_CQ_PenBtn"), function() CQC.send("pen", { k = u.k, op = "give", mult = pg.mult, days = pg.days, reason = "admin" }) end, "danger")
        if u.pen then rbtn(T("IGUI_CQ_PenClear"), function() CQC.send("pen", { k = u.k, op = "clear" }) end, "good") end
        ly = ly + rh + 6
    end
    if #users == 0 then
        CQUI.text(self, T("IGUI_CQ_NoUsers"), x + 8, ly, C.faint)
        ly = ly + fh() + 8
    end
    self:endScroll(ly + off - y)
end

-- ===================================================================== settings + log
function A:page_settings(x, y, w, h)
    local adm = CQC.adm
    local cfg = adm.cfg
    local h1 = eh()
    local cy = y
    cy = cy + CQUI.section(self, x, cy, w, T("IGUI_CQ_Settings"))
    CQUI.text(self, T("IGUI_CQ_Utc"), x, cy + 4, C.dim)
    CQUI.stepper(self, x + S(230), cy, S(140), h1, "UTC" .. ((cfg.utc >= 0) and "+" or "") .. CQ.fmt(cfg.utc, 1),
        function() CQC.send("cfg", { utc = cfg.utc - 0.5 }) end, function() CQC.send("cfg", { utc = cfg.utc + 0.5 }) end)
    CQUI.text(self, T("IGUI_CQ_ServerTime", CQUI.dateText(CQC.now())), x + S(390), cy + 4, C.faint)
    cy = cy + h1 + 8
    CQUI.toggle(self, x, cy, T("IGUI_CQ_ShowZones"), cfg.showZones ~= false, function() CQC.send("cfg", { showZones = not (cfg.showZones ~= false) }) end,
        { tip = T("IGUI_CQ_ShowZonesTip") })
    cy = cy + fh() + 14
    cy = cy + CQUI.section(self, x, cy, w, T("IGUI_CQ_Sample"))
    local u = CQUI.para(self, T("IGUI_CQ_SampleTip"), x, cy, w - S(230), C.faint)
    CQUI.btn(self, x + w - S(210), cy, S(210), h1 + 4, T("IGUI_CQ_SampleBtn"), function()
        if CQAdmin.makeSample then CQAdmin.makeSample() end
    end, "purple")
    cy = cy + math.max(u, h1 + 4) + 14
    cy = cy + CQUI.section(self, x, cy, w, T("IGUI_CQ_Log"))
    CQUI.btn(self, x + w - S(120), cy - fh() - 8, S(120), fh() + 6, T("IGUI_CQ_ClearLog"), function() CQC.send("clearLog", {}) end, "flat")
    local off = self:beginScroll("log", x, cy, w, y + h - cy)
    local ly = cy - off
    for _, l in ipairs(adm.log or {}) do
        CQUI.text(self, CQUI.dateText(l.t), x + 4, ly, C.faint)
        CQUI.text(self, CQUI.fit(l.s, FS, w - S(190)), x + S(180), ly, C.dim)
        ly = ly + fh() + 3
    end
    self:endScroll(ly + off - cy)
end

-- ===================================================================== open / close
function A:onClosed()
    self:leavePage()
    CQC.send("watch", { on = false })
    CQC.cfg.admX = tostring(math.floor(self:getX()))
    CQC.cfg.admY = tostring(math.floor(self:getY()))
    CQC.saveCfg()
    CQAdmin.win = nil
end

function CQAdmin.open()
    if not CQC.isAdmin() then return end
    if CQAdmin.win then CQAdmin.win:bringToTop(); return end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = CQUI.size(1000, 680)
    local x = CQ.clamp(CQC.cfgNum("admX", (sw - w) / 2), 0, sw - w)
    local y = CQ.clamp(CQC.cfgNum("admY", (sh - h) / 2), 0, sh - h)
    local win = A:new(x, y, w, h)
    win:show()
    CQAdmin.win = win
    CQC.send("watch", { on = true })
end

function CQAdmin.toggle()
    if CQAdmin.win then CQAdmin.win:close() else CQAdmin.open() end
end

-- refresh editors when the server confirms a save
CQC.on(function(what)
    local win = CQAdmin.win
    if not win then return end
    local kind, id = string.match(what, "^saved:(%a+):(.+)$")
    if kind == "m" and win.onSavedMission then win:onSavedMission(id)
    elseif kind == "e" and win.onSavedEvent then win:onSavedEvent(id)
    elseif kind == "b" then
        win.sel.sched = id
        win.dirty.sched = false
        if win.ed.sched and (win.ed.sched.id == "" or win.ed.sched.id == nil) then win.ed.sched.id = id end
    elseif kind == "r" then
        win.sel.radio = id
        win.dirty.radio = false
        if win.ed.radio and (win.ed.radio.id == "" or win.ed.radio.id == nil) then win.ed.radio.id = id end
    end
end)

return CQAdmin
