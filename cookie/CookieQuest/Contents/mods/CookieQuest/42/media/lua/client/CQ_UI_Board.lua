-- Cookie Quest - player window: events (join / roles), my missions, mission board
require "CQ_UI_Kit"

CQBoard = CQBoard or {}
local C = CQUI.C
local T = CQC.txt
local FS, FM = UIFont.Small, UIFont.Medium

CQBoard.Win = CQUI.Window:derive("CQBoard_Win")
local B = CQBoard.Win

function B:new(x, y, w, h)
    local o = CQUI.Window.new(self, x, y, w or 520, h or 640)
    o.title = "Cookie Quest"
    o.tab = "events"
    o.cardH = {}
    o.expand = {}
    o.confirm = {}
    return o
end

local function fh() return CQUI.fh(FS) end

-- ===================================================================== helpers
local function countdown(ev, now)
    if ev.status == "sched" then
        local d = (ev.start or now) - now
        if d > 0 then return T("IGUI_CQ_StartsIn", CQUI.dur(d)), C.accent end
        return T("IGUI_CQ_StartingNow"), C.accent
    elseif ev.status == "live" then
        local d = (ev.start or now) + (ev.dur or 0) * 60 - now
        return T("IGUI_CQ_EndsIn", CQUI.dur(d)), C.good
    end
    return "", C.dim
end

local function statusPill(win, x, y, status)
    if status == "live" then return CQUI.pill(win, x, y, T("IGUI_CQ_St_live"), C.good, FS, true) end
    if status == "sched" then return CQUI.pill(win, x, y, T("IGUI_CQ_St_sched"), C.accent, FS, true) end
    if status == "done" then return CQUI.pill(win, x, y, T("IGUI_CQ_St_done"), C.dim, FS) end
    if status == "active" then return CQUI.pill(win, x, y, T("IGUI_CQ_St_active"), C.accent, FS) end
    if status == "failed" then return CQUI.pill(win, x, y, T("IGUI_CQ_St_failed"), C.bad, FS) end
    if status == "expired" then return CQUI.pill(win, x, y, T("IGUI_CQ_St_expired"), C.dim, FS) end
    if status == "mdone" then return CQUI.pill(win, x, y, T("IGUI_CQ_St_mdone"), C.good, FS, true) end
    if status == "cancelled" then return CQUI.pill(win, x, y, T("IGUI_CQ_St_cancelled"), C.faint, FS) end
    return CQUI.pill(win, x, y, tostring(status), C.dim, FS)
end

function B:confirmBtn(key, x, y, w, h, label, fn, style)
    local armed = self.confirm[key] and getTimestampMs() - self.confirm[key] < 3500
    if armed then
        CQUI.btn(self, x, y, w, h, T("IGUI_CQ_Sure"), function() self.confirm[key] = nil; fn() end, "danger")
    else
        CQUI.btn(self, x, y, w, h, label, function() self.confirm[key] = getTimestampMs() end, style or "ghost")
    end
end

-- ===================================================================== event card
function B:drawEvent(ev, x, y, w, now)
    local id = "e" .. ev.id
    local h = self.cardH[id] or 120
    CQUI.rbox(self, x, y, w, h, C.panel, 1, 8)
    if ev.status == "live" then CQUI.rbox(self, x, y, 4, h, C.good, 1, 2) elseif ev.status == "sched" then CQUI.rbox(self, x, y, 4, h, C.accent, 1, 2) end
    local px, pw = x + 14, w - 28
    local cy = y + 12
    local pw1 = statusPill(self, px, cy + 2, ev.status)
    CQUI.text(self, CQUI.fit(ev.title, FM, pw - pw1 - 10), px + pw1 + 10, cy, C.text, 1, FM)
    cy = cy + CQUI.fh(FM) + 6
    local when = CQUI.dateText(ev.start or now) .. "  -  " .. T("IGUI_CQ_DurMin", CQUI.durMin(ev.dur or 0))
    CQUI.text(self, when, px, cy, C.dim)
    local cd, cdc = countdown(ev, now)
    CQUI.textR(self, cd, px + pw, cy, cdc)
    cy = cy + fh() + 8
    if ev.desc and ev.desc ~= "" then
        local maxL = self.expand[id] and nil or 5
        local used, total = CQUI.para(self, ev.desc, px, cy, pw, C.text, FS, maxL)
        cy = cy + used
        if total > 5 then
            local lbl = self.expand[id] and T("IGUI_CQ_Less") or T("IGUI_CQ_More")
            local lw = CQUI.tw(FS, lbl)
            local over = self:hit(px, cy, lw + 4, fh(), function() self.expand[id] = not self.expand[id] end)
            CQUI.text(self, lbl, px, cy, over and C.gold or C.accent)
            cy = cy + fh() + 2
        end
        cy = cy + 6
    end
    -- info pills
    local ix = px
    ix = ix + CQUI.pill(self, ix, cy, T("IGUI_CQ_Parts", ev.nParts or 0), C.blue) + 6
    if ev.pen and ev.pen.on then
        ix = ix + CQUI.pill(self, ix, cy, T("IGUI_CQ_PenShort", "x" .. CQ.fmt(ev.pen.mult, 2), CQ.fmt(ev.pen.days, 1)), C.bad) + 6
    end
    cy = cy + fh() + 8
    -- current phase (future phases stay hidden)
    if ev.status == "live" and ev.phased and ev.phase then
        local nm = (ev.phName and ev.phName ~= "") and T("IGUI_CQ_PhNow", ev.phase, ev.phName) or T("IGUI_CQ_PhN", ev.phase)
        local pw2 = CQUI.pill(self, px, cy, nm, C.gold)
        local mineP = CQC.me and CQC.me.parts and CQC.me.parts[ev.id]
        if mineP and mineP.ph and mineP.ph > 0 and mineP.ph ~= ev.phase then
            CQUI.text(self, T("IGUI_CQ_PhMine", mineP.ph), px + pw2 + 10, cy, C.accent)
        end
        cy = cy + fh() + 8
    end
    if ev.pen and ev.pen.on and ev.status ~= "done" then
        local u = CQUI.para(self, T("IGUI_CQ_PenRule", ev.pen.minCp or 1, "x" .. CQ.fmt(ev.pen.mult, 2), CQ.fmt(ev.pen.days, 1)), px, cy, pw, C.faint)
        cy = cy + u + 4
    end
    if ev.kit and #ev.kit > 0 then
        local u = CQUI.para(self, T("IGUI_CQ_KitAll", CQUI.itemsText(ev.kit, 6)), px, cy, pw, C.dim)
        cy = cy + u + 4
    end
    local mine = CQC.me and CQC.me.parts and CQC.me.parts[ev.id]
    -- roles
    if ev.roleMode ~= "none" and ev.roles and #ev.roles > 0 then
        cy = cy + 4
        cy = cy + CQUI.section(self, px, cy, pw, T("IGUI_CQ_Roles"))
        CQUI.text(self, T("IGUI_CQ_RoleMode_" .. ev.roleMode), px, cy, C.dim)
        cy = cy + fh() + 6
        for _, r in ipairs(ev.roles) do
            local rowY = cy
            local chosen = mine and mine.role == r.id
            local rh = 0
            local slots = ""
            if r.secret then slots = T("IGUI_CQ_Secret")
            elseif (r.max or 0) > 0 then slots = tostring(r.n or 0) .. "/" .. tostring(r.max)
            else slots = tostring(r.n or 0) end
            CQUI.rbox(self, px, rowY, pw, self.cardH[id .. r.id] or 40, chosen and C.accentD or C.panel2, 1, 6)
            local ry = rowY + 6
            CQUI.text(self, r.name, px + 10, ry, chosen and C.gold or C.text)
            CQUI.textR(self, slots, px + pw - 10, ry, r.secret and C.purple or C.dim)
            ry = ry + fh() + 2
            if r.desc and r.desc ~= "" then
                local u = CQUI.para(self, r.desc, px + 10, ry, pw - 20, C.dim, FS, self.expand[id .. r.id] and nil or 3)
                ry = ry + u + 2
            end
            if r.kit and #r.kit > 0 then
                local u = CQUI.para(self, T("IGUI_CQ_RoleKit", CQUI.itemsText(r.kit, 5)), px + 10, ry, pw - 20, C.faint)
                ry = ry + u + 2
            end
            if ev.roleMode == "pick" and (ev.status == "sched" or (ev.status == "live" and ev.lateJoin)) and not (mine and mine.kit) then
                if chosen then
                    CQUI.text(self, T("IGUI_CQ_Picked"), px + 10, ry + 2, C.good)
                    ry = ry + fh() + 6
                else
                    local full = (not r.secret) and (r.max or 0) > 0 and (r.n or 0) >= r.max
                    CQUI.btn(self, px + 10, ry + 2, 130, fh() + 8, full and T("IGUI_CQ_Full") or T("IGUI_CQ_PickRole"),
                        function() CQC.send("join", { eid = ev.id, role = r.id }) end, "ghost", { disabled = full })
                    ry = ry + fh() + 14
                end
            end
            rh = ry - rowY + 4
            self.cardH[id .. r.id] = rh
            cy = rowY + rh + 6
        end
    end
    -- my status / join
    cy = cy + 4
    if mine then
        local boxY = cy
        local bh = self.cardH[id .. "me"] or 60
        CQUI.rbox(self, px, boxY, pw, bh, { 0.12, 0.26, 0.19 }, 1, 6)
        local by = boxY + 8
        CQUI.text(self, T("IGUI_CQ_Joined"), px + 10, by, C.good)
        by = by + fh() + 4
        if mine.role and mine.roleName ~= "" then
            local rt = T("IGUI_CQ_YourRole", mine.roleName)
            if mine.secret then rt = rt .. "  " .. T("IGUI_CQ_SecretNote") end
            local u = CQUI.para(self, rt, px + 10, by, pw - 20, C.gold)
            by = by + u + 2
            if mine.roleDesc and mine.roleDesc ~= "" then
                local u2 = CQUI.para(self, mine.roleDesc, px + 10, by, pw - 20, C.text)
                by = by + u2 + 2
            end
        elseif ev.roleMode ~= "none" then
            CQUI.text(self, T("IGUI_CQ_RoleLater"), px + 10, by, C.dim)
            by = by + fh() + 2
        end
        if ev.status ~= "sched" then
            CQUI.text(self, T("IGUI_CQ_MyCp", mine.cp or 0, (ev.pen and ev.pen.minCp) or 0), px + 10, by, (mine.cp or 0) >= ((ev.pen and ev.pen.minCp) or 0) and C.good or C.accent)
            by = by + fh() + 2
        end
        if mine.got then
            CQUI.text(self, T("IGUI_CQ_KitGot"), px + 10, by, C.dim)
        elseif mine.kit then
            CQUI.text(self, T("IGUI_CQ_KitPending"), px + 10, by, C.accent)
        else
            CQUI.text(self, T("IGUI_CQ_KitSoon"), px + 10, by, C.dim)
        end
        by = by + fh() + 4
        if mine.pen then
            CQUI.text(self, T("IGUI_CQ_GotPen"), px + 10, by, C.bad)
            by = by + fh() + 4
        end
        if ev.status == "sched" and not mine.kit then
            self:confirmBtn("leave" .. ev.id, px + 10, by + 2, 150, fh() + 8, T("IGUI_CQ_Leave"), function() CQC.send("leave", { eid = ev.id }) end)
            by = by + fh() + 14
        end
        self.cardH[id .. "me"] = by - boxY + 4
        cy = boxY + self.cardH[id .. "me"] + 8
    elseif ev.status == "sched" or (ev.status == "live" and ev.lateJoin) then
        CQUI.btn(self, px, cy, pw, fh() + 16, T("IGUI_CQ_Join"), function() CQC.send("join", { eid = ev.id }) end, "primary", { font = FS })
        cy = cy + fh() + 22
    elseif ev.status == "live" then
        CQUI.text(self, T("IGUI_CQ_NoLateJoin"), px, cy, C.dim)
        cy = cy + fh() + 8
    end
    if ev.status == "done" and ev.results then
        CQUI.text(self, T("IGUI_CQ_Results", ev.results.parts or 0, ev.results.done or 0), px, cy, C.dim)
        cy = cy + fh() + 8
    end
    self.cardH[id] = cy - y + 6
    return self.cardH[id]
end

-- ===================================================================== mission card
function B:drawInst(inst, x, y, w, now)
    local id = "i" .. inst.id
    local h = self.cardH[id] or 120
    local active = inst.status == "active"
    CQUI.rbox(self, x, y, w, h, C.panel, active and 1 or 0.7, 8)
    local tracked = CQC.cfg.track == inst.id
    if tracked and active then CQUI.rbox(self, x, y, 4, h, C.accent, 1, 2) end
    local px, pw = x + 14, w - 28
    local cy = y + 12
    local pills = 0
    pills = pills + CQUI.pill(self, px + pills, cy + 2, inst.team and T("IGUI_CQ_Team") or T("IGUI_CQ_Solo"), inst.team and C.purple or C.blue) + 6
    if inst.ph and inst.eid then
        for _, e in ipairs((CQC.pub and CQC.pub.events) or {}) do
            if e.id == inst.eid and e.phased then
                pills = pills + CQUI.pill(self, px + pills, cy + 2, T("IGUI_CQ_PhN", inst.ph), C.gold) + 6
            end
        end
    end
    if not active then pills = pills + statusPill(self, px + pills, cy + 2, inst.status == "done" and "mdone" or inst.status) + 6 end

    CQUI.text(self, CQUI.fit(inst.title or "", FM, pw - pills - 4), px + pills + 4, cy, active and C.gold or C.dim, 1, FM)
    cy = cy + CQUI.fh(FM) + 8
    -- where it came from (event name / board / sheet / admin)
    local src, srcCol = CQUI.sourceText(inst)
    if src then
        local lw = CQUI.tw(FS, T("IGUI_CQ_SrcFrom")) + 6
        CQUI.text(self, T("IGUI_CQ_SrcFrom"), px, cy + 1, C.faint)
        CQUI.pill(self, px + lw, cy, CQUI.fit(src, FS, pw - lw - 20), srcCol)
        cy = cy + fh() + 8
    end
    if not active then
        if inst.status == "done" and inst.rewardText and inst.rewardText ~= "" then
            CQUI.text(self, T("IGUI_CQ_RewardIs", inst.rewardText), px, cy, C.good)
            cy = cy + fh() + 4
        end
        self.cardH[id] = cy - y + 8
        return self.cardH[id]
    end
    CQUI.chain(self, px, cy, pw, inst)
    cy = cy + 28
    local st = CQC.curStep(inst)
    CQUI.text(self, T("IGUI_CQ_StepOf", inst.step, inst.nSteps), px, cy, C.accent)
    local sw = CQUI.tw(FS, T("IGUI_CQ_StepOf", inst.step, inst.nSteps)) + 8
    CQUI.text(self, CQUI.fit(CQUI.stepLabel(st), FS, pw - sw), px + sw, cy, C.text)
    cy = cy + fh() + 4
    local goal = CQUI.stepGoal(st)
    if goal ~= "" then
        local u = CQUI.para(self, goal, px, cy, pw, C.dim)
        cy = cy + u + 2
    end
    if st and st.hint and st.hint ~= "" then
        local u = CQUI.para(self, T("IGUI_CQ_Hint", st.hint), px, cy, pw, C.faint)
        cy = cy + u + 2
    end
    if st and (st.t == "kill" or st.t == "deliver" or st.t == "collect" or st.t == "others" or st.t == "hold") then
        local frac, txt
        if st.t == "hold" then
            frac = (inst.hold or 0) / math.max(1, st.sec or 60)
            txt = CQ.clock(inst.hold or 0) .. " / " .. CQ.clock(st.sec or 60)
        else
            frac = (inst.cnt or 0) / math.max(1, st.n or 1)
            txt = tostring(inst.cnt or 0) .. " / " .. tostring(st.n or 1)
        end
        CQUI.bar(self, px, cy + 4, pw - 90, 7, frac, CQUI.STEP_COLOR[st.t])
        CQUI.textR(self, txt, px + pw, cy, C.text)
        cy = cy + fh() + 6
    end
    if st and st.t == "rescue" then
        CQUI.text(self, inst.armed and T("IGUI_CQ_RescueArmed") or T("IGUI_CQ_RescueWait"), px, cy, inst.armed and C.good or C.dim)
        cy = cy + fh() + 4
    end
    -- location
    local p = CQC.player()
    if st and st.zone and p then
        local cx, cyz = CQ.zoneCenter(st.zone)
        local d = CQ.distToZone(st.zone, p:getX(), p:getY())
        local wrong = CQUI.wrongFloor(st.zone, p:getX(), p:getY(), p:getZ())
        if CQ.inZone(st.zone, p:getX(), p:getY(), p:getZ()) then
            CQUI.text(self, T("IGUI_CQ_InZone"), px, cy, C.good)
        elseif wrong then
            CQUI.text(self, CQUI.fit(wrong, FS, pw), px, cy, C.accent)
        else
            local dk = CQUI.dirKey(cx - p:getX(), cyz - p:getY())
            CQUI.icon(self, "cq_dir_" .. dk, px, cy, fh(), C.accent)
            CQUI.text(self, CQUI.fit(T("IGUI_CQ_DistDir", math.floor(d + 0.5), T("IGUI_CQ_Dir_" .. dk)) .. "  " .. CQUI.floorInfo(st.zone, p:getZ()), FS, pw - fh() - 4), px + fh() + 4, cy, C.text)
        end
        cy = cy + fh() + 4
    elseif st and (st.t == "reach" or st.t == "deliver" or st.t == "hold" or st.t == "rescue") then
        CQUI.text(self, T("IGUI_CQ_SecretPlace"), px, cy, C.purple)
        cy = cy + fh() + 4
    end
    if inst.wait and #inst.wait > 0 then
        local u = CQUI.para(self, T("IGUI_CQ_WaitFor", table.concat(inst.wait, ", ")), px, cy, pw, C.accent)
        cy = cy + u + 2
    end
    if inst.deadline then
        CQUI.text(self, T("IGUI_CQ_TimeLeft", CQUI.dur(inst.deadline - now)), px, cy, C.bad)
        cy = cy + fh() + 4
    end
    if inst.team then
        CQUI.text(self, T("IGUI_CQ_TeamInfo", inst.nMembers or 1, inst.contrib or 0), px, cy, C.faint)
        cy = cy + fh() + 4
    end
    if (inst.rewardText and inst.rewardText ~= "") or (inst.rewards and #inst.rewards > 0) then
        local rt = inst.rewardText ~= "" and inst.rewardText or CQUI.itemsText(inst.rewards, 4)
        local u = CQUI.para(self, T("IGUI_CQ_RewardIs", rt), px, cy, pw, C.gold)
        cy = cy + u + 2
    end
    -- story
    if inst.story and inst.story ~= "" then
        local lbl = self.expand[id] and T("IGUI_CQ_StoryHide") or T("IGUI_CQ_StoryShow")
        local over = self:hit(px, cy, CQUI.tw(FS, lbl) + 6, fh(), function() self.expand[id] = not self.expand[id] end)
        CQUI.text(self, lbl, px, cy, over and C.gold or C.accent)
        cy = cy + fh() + 4
        if self.expand[id] then
            CQUI.rbox(self, px, cy, pw, (self.cardH[id .. "s"] or 40), C.bg, 1, 5)
            local u = CQUI.para(self, inst.story, px + 8, cy + 6, pw - 16, C.text)
            self.cardH[id .. "s"] = u + 12
            cy = cy + u + 16
        end
    end
    -- buttons
    cy = cy + 4
    local bx = px
    local bh = fh() + 10
    local hasZone = st and st.zone ~= nil
    if tracked then
        bx = bx + CQUI.btnA(self, bx, cy, bh, T("IGUI_CQ_Tracking"), function() CQC.setTrack(nil) end, "sel", { icon = "cq_s_reach" }) + 6
    else
        bx = bx + CQUI.btnA(self, bx, cy, bh, T("IGUI_CQ_Track"), function() CQC.setTrack(inst.id) end, "ghost", { icon = "cq_s_reach" }) + 6
    end
    if hasZone and CQC.navigatorReady() then
        bx = bx + CQUI.btnA(self, bx, cy, bh, T("IGUI_CQ_NavBtn"), function()
            CQC.setTrack(inst.id)
            CQC.routeWithNavigator(false)
        end, "ghost", { tip = T("IGUI_CQ_NavTip") }) + 6
    end
    if not inst.team and not inst.eid and inst.owner == (CQC.me and CQC.me.k) then
        local lw = CQUI.tw(FS, T("IGUI_CQ_Abandon")) + 22
        self:confirmBtn("ab" .. inst.id, px + pw - lw, cy, lw, bh, T("IGUI_CQ_Abandon"), function() CQC.send("abandon", { iid = inst.id }) end)
    end
    cy = cy + bh + 10
    self.cardH[id] = cy - y
    return self.cardH[id]
end

-- ===================================================================== board card
function B:drawBoardItem(m, x, y, w, now)
    local id = "b" .. m.id
    local h = self.cardH[id] or 100
    CQUI.rbox(self, x, y, w, h, C.panel, 1, 8)
    local px, pw = x + 14, w - 28
    local cy = y + 12
    local pills = 0
    pills = pills + CQUI.pill(self, px, cy + 2, m.team and T("IGUI_CQ_Team") or T("IGUI_CQ_Solo"), m.team and C.purple or C.blue) + 6
    if m.left and m.left >= 0 then
        pills = pills + CQUI.pill(self, px + pills, cy + 2, T("IGUI_CQ_Left", m.left), m.left > 0 and C.gold or C.bad) + 6
    end
    CQUI.text(self, CQUI.fit(m.title, FM, pw - pills - 4), px + pills + 4, cy, C.text, 1, FM)
    cy = cy + CQUI.fh(FM) + 8
    if m.story and m.story ~= "" then
        local u, total = CQUI.para(self, m.story, px, cy, pw, C.dim, FS, self.expand[id] and nil or 4)
        cy = cy + u
        if total > 4 then
            local lbl = self.expand[id] and T("IGUI_CQ_Less") or T("IGUI_CQ_More")
            local over = self:hit(px, cy, CQUI.tw(FS, lbl) + 4, fh(), function() self.expand[id] = not self.expand[id] end)
            CQUI.text(self, lbl, px, cy, over and C.gold or C.accent)
            cy = cy + fh() + 2
        end
        cy = cy + 6
    end
    local info = T("IGUI_CQ_NSteps", m.nSteps or 1)
    if m.timeLimit and m.timeLimit > 0 then info = info .. "  -  " .. T("IGUI_CQ_TimeLimit", CQUI.durMin(m.timeLimit)) end
    if m.repeatable then info = info .. "  -  " .. T("IGUI_CQ_Repeatable") end
    CQUI.text(self, info, px, cy, C.faint)
    cy = cy + fh() + 4
    if (m.rewardText and m.rewardText ~= "") or (m.rewards and #m.rewards > 0) then
        local rt = (m.rewardText and m.rewardText ~= "") and m.rewardText or CQUI.itemsText(m.rewards, 4)
        local u = CQUI.para(self, T("IGUI_CQ_RewardIs", rt), px, cy, pw, C.gold)
        cy = cy + u + 4
    end
    local have = false
    for _, i in ipairs(CQC.activeInst()) do if i.mid == m.id then have = true end end
    local dis = have or (m.left == 0)
    CQUI.btn(self, px, cy + 2, 170, fh() + 12, have and T("IGUI_CQ_HaveIt") or T("IGUI_CQ_Accept"),
        function() CQC.send("accept", { mid = m.id, via = "board" }) end, have and "good" or "primary", { disabled = dis })
    cy = cy + fh() + 24
    self.cardH[id] = cy - y
    return self.cardH[id]
end

-- ===================================================================== body
function B:drawBody()
    local W, H = self.width, self.height
    local now = CQC.now()
    local y = self.headerH + 10
    local fhv = fh()
    -- buff strip
    local chips = CQHUD and CQHUD.chips() or {}
    local stripH = fhv + 16
    CQUI.rbox(self, 12, y, W - 24, stripH, C.panel, 1, 7)
    if #chips > 0 then
        local x = 22
        for _, c in ipairs(chips) do
            local col = c.up and C.gold or C.bad
            CQUI.icon(self, c.up and "cq_buff_up" or "cq_buff_down", x, y + (stripH - 16) / 2, 16, col)
            local txt = c.text .. "  " .. CQUI.dur(c.left)
            self:hit(x, y, CQUI.tw(FS, txt) + 22, stripH, nil, c.tip)
            CQUI.text(self, txt, x + 20, y + 8, col)
            x = x + CQUI.tw(FS, txt) + 40
        end
    else
        local txt = T("IGUI_CQ_NoBuff")
        local nb = CQC.pub and CQC.pub.nextBuff
        if nb then txt = txt .. "   " .. T("IGUI_CQ_NextBuff", CQUI.dateText(nb.at), "x" .. CQ.fmt(nb.mult, 2)) end
        CQUI.icon(self, "cq_buff_up", 22, y + (stripH - 16) / 2, 16, C.faint)
        CQUI.text(self, CQUI.fit(txt, FS, W - 70), 44, y + 8, C.dim)
    end
    y = y + stripH + 8
    -- tabs
    local nAct = #CQC.activeInst()
    local nBoard = (CQC.pub and CQC.pub.board) and #CQC.pub.board or 0
    local nEv = 0
    for _, e in ipairs((CQC.pub and CQC.pub.events) or {}) do if e.status ~= "done" then nEv = nEv + 1 end end
    CQUI.tabs(self, 12, y, W - 24, fhv + 14, {
        { key = "events", label = T("IGUI_CQ_Tab_Events"), badge = tostring(nEv) },
        { key = "missions", label = T("IGUI_CQ_Tab_Missions"), badge = tostring(nAct) },
        { key = "board", label = T("IGUI_CQ_Tab_Board"), badge = tostring(nBoard) },
    }, self.tab, function(k) self.tab = k end)
    y = y + fhv + 22
    -- footer
    local footH = fhv + 22
    local areaH = H - y - footH - 6
    local off = self:beginScroll(self.tab, 12, y, W - 24, areaH)
    local cy = y - off
    local cw = W - 24 - 8
    if not CQC.pub then
        CQUI.textC(self, T("IGUI_CQ_Loading"), W / 2, cy + 40, C.dim)
        cy = cy + 100
    elseif self.tab == "events" then
        local list = {}
        for _, e in ipairs(CQC.pub.events or {}) do if e.status == "live" then list[#list + 1] = e end end
        for _, e in ipairs(CQC.pub.events or {}) do if e.status == "sched" then list[#list + 1] = e end end
        for _, e in ipairs(CQC.pub.events or {}) do if e.status == "done" then list[#list + 1] = e end end
        if #list == 0 then
            CQUI.icon(self, "cq_icon_off", W / 2 - 32, cy + 30, 64)
            CQUI.textC(self, T("IGUI_CQ_NoEvents"), W / 2, cy + 104, C.dim)
            cy = cy + 140
        end
        for _, e in ipairs(list) do cy = cy + self:drawEvent(e, 12, cy, cw, now) + 10 end
    elseif self.tab == "missions" then
        local list = {}
        for _, i in ipairs((CQC.me and CQC.me.inst) or {}) do if i.status == "active" then list[#list + 1] = i end end
        for _, i in ipairs((CQC.me and CQC.me.inst) or {}) do if i.status ~= "active" then list[#list + 1] = i end end
        if #list == 0 then
            CQUI.icon(self, "cq_s_reach", W / 2 - 24, cy + 30, 48, C.faint)
            CQUI.textC(self, T("IGUI_CQ_NoMissions"), W / 2, cy + 90, C.dim)
            cy = cy + 130
        end
        for _, i in ipairs(list) do cy = cy + self:drawInst(i, 12, cy, cw, now) + 10 end
    else
        local list = CQC.pub.board or {}
        if #list == 0 then
            CQUI.icon(self, "cq_s_collect", W / 2 - 24, cy + 30, 48, C.faint)
            CQUI.textC(self, T("IGUI_CQ_NoBoard"), W / 2, cy + 90, C.dim)
            cy = cy + 130
        end
        for _, m in ipairs(list) do cy = cy + self:drawBoardItem(m, 12, cy, cw, now) + 10 end
    end
    self:endScroll(cy + off - y)
    -- footer
    local fy = H - footH - 2
    CQUI.sep(self, 12, fy - 4, W - 24)
    local fx = 16
    fx = fx + CQUI.toggle(self, fx, fy + 6, T("IGUI_CQ_ShowHud"), CQC.cfg.hud ~= "0", function()
        CQC.cfgSet("hud", CQC.cfg.hud == "0" and "1" or "0")
    end) + 18
    fx = fx + CQUI.toggle(self, fx, fy + 6, T("IGUI_CQ_ShowArrow"), CQC.cfg.navOff ~= "1", function()
        CQC.cfgSet("navOff", CQC.cfg.navOff == "1" and "0" or "1")
    end) + 18
    fx = fx + CQUI.toggle(self, fx, fy + 6, T("IGUI_CQ_ShowRoute"), CQC.cfg.routeOff ~= "1", function()
        CQC.cfgSet("routeOff", CQC.cfg.routeOff == "1" and "0" or "1")
    end, { tip = T("IGUI_CQ_ShowRouteTip") }) + 18
    if CQC.isAdmin() then
        local lw = CQUI.tw(FS, T("IGUI_CQ_AdminPanel")) + 26
        CQUI.btn(self, W - lw - 14, fy + 2, lw, fhv + 10, T("IGUI_CQ_AdminPanel"), function()
            if CQAdmin then CQAdmin.toggle() end
        end, "purple")
    end
end

function B:onClosed()
    CQC.cfg.boardX = tostring(math.floor(self:getX()))
    CQC.cfg.boardY = tostring(math.floor(self:getY()))
    CQC.saveCfg()
    CQBoard.win = nil
end

-- ===================================================================== open / close
function CQBoard.open(tab)
    if CQBoard.win then
        if tab then CQBoard.win.tab = tab end
        CQBoard.win:bringToTop()
        return
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local bw, bh = CQUI.size(520, 640)
    local x = CQC.cfgNum("boardX", (sw - bw) / 2)
    local y = CQC.cfgNum("boardY", math.max(10, (sh - bh) / 2))
    local w = B:new(CQ.clamp(x, 0, math.max(0, sw - bw)), CQ.clamp(y, 0, math.max(0, sh - bh)), bw, bh)
    if tab then w.tab = tab
    elseif #CQC.activeInst() > 0 then w.tab = "missions" end
    w:show()
    CQBoard.win = w
    if CQIcon then CQIcon.markSeen() end
    CQC.send("hello", {})
end

function CQBoard.toggle(tab)
    if CQBoard.win then CQBoard.win:close() else CQBoard.open(tab) end
end

return CQBoard
