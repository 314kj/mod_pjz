-- Cookie Quest - admin page "players' missions": every running mission in one compact list,
-- grouped by mission or by player, with where each member stands and one-click (bulk) controls
require "CQ_UI_Admin"

local C = CQUI.C
local T = CQC.txt
local FS, FM = UIFont.Small, UIFont.Medium
local S = CQUI.S
local A = CQAdmin.Win
local fh, eh = CQAdmin.fh, CQAdmin.eh

local ZONE_STEPS = { reach = true, deliver = true, hold = true, rescue = true }

-- ------------------------------------------------------------------ data
local function memberNames(inst)
    local out = {}
    for k, n in pairs(inst.members or {}) do out[#out + 1] = { k = k, name = tostring(n), on = inst.online and inst.online[k] } end
    table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return out
end

local function matches(self, inst)
    local f = self.playsEv
    if f == "none" and inst.eid then return false end
    if f and f ~= "none" and inst.eid ~= f then return false end
    if not self.playsAll and inst.status ~= "active" then return false end
    local q = string.lower(CQ.trim(self:getE("plSearch") or ""))
    if q ~= "" then
        if string.find(string.lower(inst.title or ""), q, 1, true) then return true end
        for _, n in pairs(inst.members or {}) do
            if string.find(string.lower(tostring(n)), q, 1, true) then return true end
        end
        return false
    end
    return true
end

local function filtered(self)
    local out = {}
    for _, inst in ipairs((CQC.adm and CQC.adm.inst) or {}) do
        if matches(self, inst) then out[#out + 1] = inst end
    end
    return out
end

-- one short line that says what is going on, plus its colour
local function issue(inst)
    if inst.status ~= "active" then
        return T("IGUI_CQ_St_" .. (inst.status == "done" and "mdone" or inst.status)), inst.status == "done" and C.good or C.faint
    end
    local st = inst.steps and inst.steps[inst.step]
    if not st then return "", C.dim end
    if ZONE_STEPS[st.t] and not st.zone then return T("IGUI_CQ_PlNoZone"), C.bad end
    if inst.wait and #inst.wait > 0 then return T("IGUI_CQ_WaitFor", table.concat(inst.wait, ", ")), C.accent end
    local anyOn = false
    for _ in pairs(inst.online or {}) do anyOn = true end
    if not anyOn then return T("IGUI_CQ_PlNobody"), C.faint end
    if inst.diag then
        local best, wrong = nil, false
        for _, d in pairs(inst.diag) do
            if d.inside then return T("IGUI_CQ_InZone"), C.good end
            if d.d == 0 and d.dz ~= 0 then wrong = true end
            if not best or d.d < best then best = d.d end
        end
        if wrong then return T("IGUI_CQ_PlWrongFloor"), C.accent end
        if best then return T("IGUI_CQ_PlNearest", best), C.dim end
    end
    return "", C.dim
end

local function progress(inst)
    local st = inst.steps and inst.steps[inst.step]
    if not st then return "" end
    if st.t == "kill" or st.t == "deliver" or st.t == "collect" or st.t == "others" then
        return tostring(inst.cnt or 0) .. "/" .. tostring(st.n or 1)
    elseif st.t == "hold" then
        return CQ.clock(inst.hold or 0) .. "/" .. CQ.clock(st.sec or 60)
    elseif st.t == "rescue" then
        return inst.armed and T("IGUI_CQ_Armed") or T("IGUI_CQ_NotArmed")
    end
    return ""
end

local function send(op, iids)
    if #iids == 0 then return end
    if #iids == 1 then CQC.send("stepCtl", { iid = iids[1], op = op })
    else CQC.send("instBulk", { iids = iids, op = op }) end
end

-- ------------------------------------------------------------------ pieces
-- details of one mission: every member's position + all controls; returns height
function A:playsDetail(inst, x, y, w)
    local yy = y + 6
    local st = inst.steps and inst.steps[inst.step]
    local lbl = T("IGUI_CQ_StepOf", inst.step, #(inst.steps or {})) .. "  " .. CQUI.stepLabel(st) .. "  -  " .. CQUI.stepGoal(st)
    CQUI.icon(self, CQUI.STEP_ICON[st and st.t or "admin"] or "cq_s_admin", x + 8, yy, fh(), CQUI.STEP_COLOR[st and st.t or "admin"])
    CQUI.text(self, CQUI.fit(lbl, FS, w - fh() - 20), x + fh() + 14, yy, C.text)
    yy = yy + fh() + 6
    if st and st.zone then
        local zx, zy = CQ.zoneCenter(st.zone)
        local zt = T("IGUI_CQ_ZoneInfo", zx, zy,
            st.zone.anyZ and T("IGUI_CQ_FloorAny") or CQUI.floorText(st.zone.z or 0), CQ.zoneW(st.zone) .. "x" .. CQ.zoneH(st.zone))
        CQUI.text(self, CQUI.fit(zt, FS, w - 24), x + 14, yy, C.dim)
        yy = yy + fh() + 4
    end
    for _, m in ipairs(memberNames(inst)) do
        CQUI.rbox(self, x + 14, yy + fh() / 2 - 3, 7, 7, m.on and C.good or C.faint, 1, 3)
        CQUI.text(self, CQUI.fit(m.name, FS, S(170)), x + 28, yy, m.on and C.text or C.faint)
        local d = inst.diag and inst.diag[m.k]
        local info, col = "", C.faint
        if not m.on then info = T("IGUI_CQ_PlOffline")
        elseif d then
            if d.inside then info, col = T("IGUI_CQ_InZone"), C.good
            else
                info = T("IGUI_CQ_Dist", d.d)
                if d.dz > 0 then info = info .. "  " .. T("IGUI_CQ_FloorUp", d.dz)
                elseif d.dz < 0 then info = info .. "  " .. T("IGUI_CQ_FloorDown", -d.dz) end
                col = (d.d == 0) and C.accent or C.dim
            end
            if d.staff then info = info .. "  [" .. T("IGUI_CQ_PlStaff") .. "]" end
        end
        local contrib = inst.contrib and inst.contrib[m.k]
        if contrib and contrib > 0 then info = info .. "  " .. T("IGUI_CQ_PlCp", contrib) end
        CQUI.text(self, CQUI.fit(info, FS, w - S(200)), x + 28 + S(178), yy, col)
        yy = yy + fh() + 3
    end
    yy = yy + 4
    local bx, bh = x + 14, fh() + 6
    local id = inst.id
    if inst.status == "active" then
        bx = bx + CQUI.btnA(self, bx, yy, bh, T("IGUI_CQ_Pass"), function() send("pass", { id }) end, "good") + 6
        bx = bx + CQUI.btnA(self, bx, yy, bh, T("IGUI_CQ_Back"), function() send("back", { id }) end, "ghost") + 6
        bx = bx + CQUI.btnA(self, bx, yy, bh, T("IGUI_CQ_Complete"), function() send("done", { id }) end, "primary", { tip = T("IGUI_CQ_CompleteTip") }) + 6
        local lw = CQUI.tw(FS, T("IGUI_CQ_Fail")) + 22
        self:confirmBtn("pfail" .. id, bx, yy, lw, bh, T("IGUI_CQ_Fail"), function() send("fail", { id }) end)
        bx = bx + lw + 6
        local cw = CQUI.tw(FS, T("IGUI_CQ_PlCancel")) + 22
        self:confirmBtn("pcan" .. id, bx, yy, cw, bh, T("IGUI_CQ_PlCancel"), function() send("cancel", { id }) end)
        bx = bx + cw + 6
    else
        bx = bx + CQUI.btnA(self, bx, yy, bh, T("IGUI_CQ_Reopen"), function() send("back", { id }) end, "ghost") + 6
    end
    local dw = CQUI.tw(FS, T("IGUI_CQ_Delete")) + 22
    self:confirmBtn("pdel" .. id, bx, yy, dw, bh, T("IGUI_CQ_Delete"), function() send("remove", { id }) end)
    yy = yy + bh + 8
    return yy - y
end

-- one compact row; returns height (row + open details)
function A:playsRow(inst, x, y, w, showTitle)
    local rh = fh() + 10
    local open = self.playsOpen[inst.id]
    local over = self:hit(x, y, w - S(250), rh, function() self.playsOpen[inst.id] = not self.playsOpen[inst.id] end)
    CQUI.rbox(self, x, y, w, rh, open and C.panel3 or (over and C.panel2 or C.panel), 1, 5)
    local tx = x + 8
    CQUI.text(self, open and "v" or ">", tx, y + 5, C.faint)
    tx = tx + 14
    if showTitle then
        CQUI.text(self, CQUI.fit(inst.title or "", FS, S(190)), tx, y + 5, C.gold)
        tx = tx + S(196)
    end
    -- who
    local names, nOn = {}, 0
    for _, m in ipairs(memberNames(inst)) do names[#names + 1] = m.name; if m.on then nOn = nOn + 1 end end
    CQUI.rbox(self, tx, y + rh / 2 - 3, 7, 7, nOn > 0 and C.good or C.faint, 1, 3)
    local who = (inst.team and (T("IGUI_CQ_Team") .. " " .. tostring(nOn) .. "/" .. tostring(#names) .. ": ") or "") .. table.concat(names, ", ")
    local whoW = showTitle and S(150) or S(220)
    CQUI.text(self, CQUI.fit(who, FS, whoW), tx + 12, y + 5, C.text)
    tx = tx + 12 + whoW + 8
    -- step + progress
    local st = inst.steps and inst.steps[inst.step]
    local stepTxt = tostring(inst.step) .. "/" .. tostring(#(inst.steps or {})) .. "  " .. CQUI.stepLabel(st)
    local pr = progress(inst)
    if pr ~= "" then stepTxt = stepTxt .. "  [" .. pr .. "]" end
    local btnX = x + w - S(246)
    local stepW = math.max(40, math.floor((btnX - tx) * 0.55))
    CQUI.text(self, CQUI.fit(stepTxt, FS, stepW), tx, y + 5, C.text)
    tx = tx + stepW + 8
    local it, ic = issue(inst)
    CQUI.text(self, CQUI.fit(it, FS, math.max(20, btnX - tx - 8)), tx, y + 5, ic)
    -- quick controls
    local bh = fh() + 4
    local bx = btnX
    if inst.status == "active" then
        CQUI.btn(self, bx, y + 3, S(70), bh, T("IGUI_CQ_PlPassS"), function() send("pass", { inst.id }) end, "good", { tip = T("IGUI_CQ_Pass") })
        bx = bx + S(76)
        CQUI.btn(self, bx, y + 3, S(164), bh, T("IGUI_CQ_PlDoneS"), function() send("done", { inst.id }) end, "primary", { tip = T("IGUI_CQ_CompleteTip") })
    else
        CQUI.btn(self, bx, y + 3, S(240), bh, T("IGUI_CQ_Reopen"), function() send("back", { inst.id }) end, "flat")
    end
    local hgt = rh
    if open then
        local dh = self:playsDetail(inst, x + 10, y + rh, w - 10)
        hgt = hgt + dh
    end
    return hgt + 4
end

-- ------------------------------------------------------------------ views
function A:playsByMission(list, x, y, w)
    local groups, order = {}, {}
    for _, inst in ipairs(list) do
        local g = groups[inst.mid]
        if not g then
            g = { mid = inst.mid, title = inst.title or inst.mid, ev = inst.evTitle, list = {} }
            groups[inst.mid] = g
            order[#order + 1] = g
        end
        g.list[#g.list + 1] = inst
    end
    table.sort(order, function(a, b) return string.lower(a.title) < string.lower(b.title) end)
    local cy = y
    for _, g in ipairs(order) do
        local active = {}
        for _, inst in ipairs(g.list) do if inst.status == "active" then active[#active + 1] = inst.id end end
        local hh = eh() + 8
        CQUI.rbox(self, x, cy, w, hh, C.panel2, 1, 6)
        CQUI.rbox(self, x, cy, 4, hh, C.gold, 1, 2)
        -- bulk controls for the whole group (right side first, the text gets what is left)
        local bx = x + w - 8
        if #active > 0 then
            local function bulk(key, label, op, style, confirm)
                local bw = CQUI.tw(FS, label) + 22
                bx = bx - bw
                if confirm then
                    self:confirmBtn(key .. g.mid, bx, cy + 4, bw, eh(), label, function() send(op, active) end, style)
                else
                    CQUI.btn(self, bx, cy + 4, bw, eh(), label, function() send(op, active) end, style)
                end
                bx = bx - 6
            end
            bulk("bcan", T("IGUI_CQ_PlCancelAll"), "cancel", "ghost", true)
            bulk("bdone", T("IGUI_CQ_PlDoneAll"), "done", "primary", true)
            bulk("bpass", T("IGUI_CQ_PlPassAll"), "pass", "good", false)
        end
        local room = bx - (x + 12) - 8
        local tx = x + 12
        local titleW = math.min(CQUI.tw(FM, g.title), math.floor(room * 0.5))
        CQUI.text(self, CQUI.fit(g.title, FM, titleW), tx, cy + (hh - CQUI.fh(FM)) / 2, C.gold, 1, FM)
        tx = tx + titleW + 10
        if g.ev and bx - tx > 60 then
            tx = tx + CQUI.pill(self, tx, cy + (hh - fh()) / 2, CQUI.fit(g.ev, FS, math.floor((bx - tx) * 0.55)), C.good) + 8
        end
        CQUI.text(self, CQUI.fit(T("IGUI_CQ_PlCount", #active, #g.list), FS, math.max(10, bx - tx - 4)), tx, cy + (hh - fh()) / 2, C.dim)
        cy = cy + hh + 4
        for _, inst in ipairs(g.list) do cy = cy + self:playsRow(inst, x + 10, cy, w - 10, false) end
        cy = cy + 8
    end
    return cy - y
end

function A:playsByPlayer(list, x, y, w)
    local adm = CQC.adm
    local users = {}
    for _, u in ipairs(adm.users or {}) do users[u.k] = u end
    local people, order = {}, {}
    for _, inst in ipairs(list) do
        for k, n in pairs(inst.members or {}) do
            local pp = people[k]
            if not pp then
                pp = { k = k, name = tostring(n), on = inst.online and inst.online[k], list = {} }
                people[k] = pp
                order[#order + 1] = pp
            end
            pp.list[#pp.list + 1] = inst
        end
    end
    table.sort(order, function(a, b)
        if (a.on and 1 or 0) ~= (b.on and 1 or 0) then return a.on and true or false end
        return string.lower(a.name) < string.lower(b.name)
    end)
    local cy = y
    for _, pp in ipairs(order) do
        -- the player's event role / phase
        local extra = {}
        for _, ev in pairs(adm.events or {}) do
            local pt = ev.parts and ev.parts[pp.k]
            if pt and ev.status == "live" then
                for _, r in ipairs(ev.roles or {}) do if r.id == pt.role then extra[#extra + 1] = r.name end end
                if #(ev.phases or {}) > 1 and pt.ph then extra[#extra + 1] = T("IGUI_CQ_PhN", pt.ph) end
            end
        end
        local hh = fh() + 12
        CQUI.rbox(self, x, cy, w, hh, C.panel2, 1, 6)
        CQUI.rbox(self, x + 10, cy + hh / 2 - 4, 8, 8, pp.on and C.good or C.faint, 1, 4)
        CQUI.text(self, CQUI.fit(pp.name, FS, S(170)), x + 26, cy + 6, pp.on and C.text or C.faint)
        local u = users[pp.k]
        local tail = table.concat(extra, " - ")
        if u and u.pen then tail = tail .. "  " .. T("IGUI_CQ_PlPen") end
        CQUI.text(self, CQUI.fit(tail, FS, S(200)), x + 26 + S(176), cy + 6, C.dim)
        -- mission chips
        local cx = x + 26 + S(384)
        for _, inst in ipairs(pp.list) do
            local lbl = CQUI.fit(inst.title or "", FS, S(150)) .. " " .. tostring(inst.step) .. "/" .. tostring(#(inst.steps or {}))
            local cw = CQUI.tw(FS, lbl) + 18
            if cx + cw > x + w - 6 then break end
            local sel = self.playsPick[pp.k] == inst.id
            local col = inst.status == "active" and (sel and C.accentD or C.panel3) or C.panel
            local ov = self:hit(cx, cy + 3, cw, hh - 6, function()
                self.playsPick[pp.k] = (self.playsPick[pp.k] == inst.id) and nil or inst.id
            end, inst.title)
            CQUI.rbox(self, cx, cy + 3, cw, hh - 6, ov and C.panel3 or col, 1, 5)
            CQUI.text(self, lbl, cx + 9, cy + 6, inst.status == "active" and C.text or C.faint)
            cx = cx + cw + 6
        end
        cy = cy + hh + 3
        local pick = self.playsPick[pp.k]
        for _, inst in ipairs(pp.list) do
            if inst.id == pick then cy = cy + self:playsDetail(inst, x + 16, cy, w - 16) + 4 end
        end
        cy = cy + 3
    end
    return cy - y
end

-- ------------------------------------------------------------------ page
function A:page_plays(x, y, w, h)
    local adm = CQC.adm
    self.playsOpen = self.playsOpen or {}
    self.playsPick = self.playsPick or {}
    local h1 = eh()
    -- row 1: view tabs + event filter
    local tabW = math.min(S(360), math.floor(w * 0.48))
    CQUI.tabs(self, x, y, tabW, fh() + 12, {
        { key = "mission", label = T("IGUI_CQ_PlByMission") },
        { key = "player", label = T("IGUI_CQ_PlByPlayer") },
    }, self.sub.plays or "mission", function(k) self.sub.plays = k end)
    local opts = { { id = nil, name = T("IGUI_CQ_PlAllSrc") }, { id = "none", name = T("IGUI_CQ_PlNoEvent") } }
    for _, id in ipairs(CQ.sortedKeys(adm.events or {})) do
        local e = adm.events[id]
        if e.status == "live" or e.status == "done" or e.status == "sched" then opts[#opts + 1] = { id = id, name = e.title } end
    end
    local oi = 1
    for i, o in ipairs(opts) do if o.id == self.playsEv then oi = i end end
    local fx = x + tabW + 12
    local fw = x + w - fx
    CQUI.cycle(self, fx, y, fw, fh() + 12, CQUI.fit(opts[oi].name, FS, fw - 2 * (fh() + 12) - 10), function()
        oi = oi - 1; if oi < 1 then oi = #opts end; self.playsEv = opts[oi].id
    end, function()
        oi = oi + 1; if oi > #opts then oi = 1 end; self.playsEv = opts[oi].id
    end, { tip = T("IGUI_CQ_PlFilterTip") })
    -- row 2: search + show finished
    local cy = y + fh() + 20
    local tgW = fh() + 14 + CQUI.tw(FS, T("IGUI_CQ_PlShowDone"))
    local lw = CQUI.tw(FS, T("IGUI_CQ_PlSearch")) + 8
    CQUI.text(self, T("IGUI_CQ_PlSearch"), x, cy + 4, C.dim)
    local sw = math.max(60, w - tgW - lw - 16)
    self:place("plSearch", x + lw, cy, sw, h1)
    CQUI.toggle(self, x + lw + sw + 12, cy + 4, T("IGUI_CQ_PlShowDone"), self.playsAll == true, function() self.playsAll = not self.playsAll end)
    cy = cy + h1 + 8
    local list = filtered(self)
    local nAct, people = 0, {}
    for _, inst in ipairs(list) do
        if inst.status == "active" then nAct = nAct + 1 end
        for k in pairs(inst.members or {}) do people[k] = true end
    end
    CQUI.text(self, T("IGUI_CQ_PlSummary", nAct, CQ.count(people)), x, cy, C.dim)
    cy = cy + fh() + 8
    local off = self:beginScroll("plays", x, cy, w, y + h - cy)
    local top = cy - off
    local used
    if #list == 0 then
        CQUI.text(self, T("IGUI_CQ_DashNoMission"), x + 4, top + 4, C.faint)
        used = fh() + 12
    elseif (self.sub.plays or "mission") == "player" then
        used = self:playsByPlayer(list, x, top, w - 10)
    else
        used = self:playsByMission(list, x, top, w - 10)
    end
    self:endScroll(used + 10)
end

return A
