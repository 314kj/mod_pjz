-- Cookie Quest - admin editors: missions (A > B > C steps) and events (roles, kits, penalties)
require "CQ_UI_Admin"

local C = CQUI.C
local T = CQC.txt
local FS, FM = UIFont.Small, UIFont.Medium
local S = CQUI.S
local A = CQAdmin.Win
local fh, eh = CQAdmin.fh, CQAdmin.eh

local ZONE_PRESETS = { 1, 3, 5, 9, 15, 25, 41, 61 }

-- ===================================================================== ground preview for the selected step (admin only)
local PV = { key = nil, list = {} }
local function clearPreview()
    for i = 1, #PV.list do pcall(function() PV.list[i]:remove() end) end
    PV.list = {}
    PV.key = nil
end
CQAdmin.clearPreview = clearPreview

local function preview(zn)
    local key = zn and (zn.x1 .. "," .. zn.y1 .. "," .. zn.x2 .. "," .. zn.y2 .. "," .. tostring(zn.z)) or nil
    if key == PV.key then return end
    clearPreview()
    PV.key = key
    if not zn or not getWorldMarkers then return end
    local ok, wm = pcall(getWorldMarkers)
    if not ok or not wm then return end
    local cell = getCell()
    if not cell then return end
    local pts = { { zn.x1, zn.y1 }, { zn.x2, zn.y1 }, { zn.x1, zn.y2 }, { zn.x2, zn.y2 } }
    local cx, cy = CQ.zoneCenter(zn)
    pts[#pts + 1] = { cx, cy }
    for i = 1, #pts do
        local sq = cell:getGridSquare(pts[i][1], pts[i][2], zn.z or 0)
        if sq then
            local size = (i == #pts) and 1.2 or 0.7
            local okm, mk = pcall(function() return wm:addGridSquareMarker(sq, 1.0, 0.84, 0.35, true, size) end)
            if okm and mk then PV.list[#PV.list + 1] = mk end
        end
    end
end

-- ===================================================================== mission editor state
local function newMission()
    return {
        id = "", title = T("IGUI_CQ_NewMission"), story = "", assign = "reader", team = false, showSteps = true,
        limit = 0, repeatable = false, timeLimit = 0, rewardTo = "contrib", rewards = {}, rewardText = "",
        steps = { { t = "reach", label = "", hint = "" } },
    }
end

function A:selectMission(id)
    local adm = CQC.adm
    local m = id and adm and adm.missions[id]
    self.sel.mission = id or "new"
    self.ed.mission = CQ.copy(m or newMission())
    self.dirty.mission = false
    self.stepSel = 1
    self:setE("mTitle", self.ed.mission.title)
    self:setE("mStory", self.ed.mission.story)
    self:setE("mRewardText", self.ed.mission.rewardText)
    self:setE("item_rew", "")
    self:loadStep()
end

function A:loadStep()
    local m = self.ed.mission
    if not m then return end
    if self.stepSel > #m.steps then self.stepSel = #m.steps end
    if self.stepSel < 1 then self.stepSel = 1 end
    local st = m.steps[self.stepSel]
    if not st then return end
    self:setE("stLabel", st.label or "")
    self:setE("stHint", st.hint or "")
    self:setE("stTarget", st.target or "")
    self:setE("stCh", st.ch and CQ.chText(st.ch) or "")
    self:setE("item_st", st.item or "")
end

function A:commitStep()
    local m = self.ed.mission
    if not m then return end
    local st = m.steps[self.stepSel]
    if not st then return end
    st.label = self:getE("stLabel")
    st.hint = self:getE("stHint")
    local info = CQ.STEP_INFO[st.t] or {}
    if info.item then st.item = CQ.trim(self:getE("item_st")) end
    if info.target then st.target = CQ.trim(self:getE("stTarget")) end
    if info.ch then st.ch = CQ.mhzToCh(self:getE("stCh")) or st.ch end
end

function A:readMission()
    self:commitStep()
    local m = self.ed.mission
    m.title = self:getE("mTitle")
    m.story = self:getE("mStory")
    m.rewardText = self:getE("mRewardText")
end

function A:missionDirty()
    if not self.ed.mission then return false end
    if self.dirty.mission then return true end
    return self:eChanged({ "mTitle", "mStory", "mRewardText", "stLabel", "stHint", "stTarget", "stCh", "item_st" })
end

function A:saveMission()
    self:readMission()
    CQC.send("saveMission", { m = self.ed.mission, live = true })
    self.dirty.mission = false
    for _, n in ipairs({ "mTitle", "mStory", "mRewardText", "stLabel", "stHint", "stTarget", "stCh", "item_st" }) do
        self.loaded[n] = self:getE(n)
    end
end

function A:onSavedMission(id)
    self.sel.mission = id
    if self.ed.mission and (self.ed.mission.id == "" or self.ed.mission.id == nil) then self.ed.mission.id = id end
end

local function needsZone(st)
    local info = CQ.STEP_INFO[st.t] or {}
    return info.zone == true
end

local function defaultsFor(st, p)
    local info = CQ.STEP_INFO[st.t] or {}
    if (info.zone and not st.zone) and p then st.zone = CQ.makeZone(p:getX(), p:getY(), p:getZ(), 5, 5) end
    if info.n and not st.n then st.n = (st.t == "others") and 3 or 10 end
    if info.sec and not st.sec then st.sec = 120 end
    if info.ch and not st.ch then st.ch = 91400 end
end

-- ===================================================================== missions page
function A:page_missions(x, y, w, h)
    local adm = CQC.adm
    local lw = math.min(S(230), math.max(230, math.floor(w * 0.27)))
    local h1 = eh()
    CQUI.btn(self, x, y, lw, h1, T("IGUI_CQ_NewMissionBtn"), function()
        if self.ed.mission then self:commitStep() end
        self:selectMission(nil)
    end, "primary")
    local list = {}
    for _, m in pairs(adm.missions) do list[#list + 1] = m end
    table.sort(list, function(a, b) return tostring(a.title) < tostring(b.title) end)
    local ly0 = y + h1 + 8
    local off = self:beginScroll("mlist", x, ly0, lw, h - h1 - 8)
    local ly = ly0 - off
    for _, m in ipairs(list) do
        local sel = self.sel.mission == m.id
        local rh = fh() * 2 + 12
        local over = self:hit(x, ly, lw - 6, rh, function()
            if self.ed.mission then self:commitStep() end
            self:selectMission(m.id)
        end)
        CQUI.rbox(self, x, ly, lw - 6, rh, sel and C.panel3 or (over and C.panel2 or C.panel), 1, 6)
        if sel then CQUI.rbox(self, x, ly + 4, 3, rh - 8, C.accent, 1, 1) end
        CQUI.text(self, CQUI.fit(m.title, FS, lw - 30), x + 10, ly + 5, C.text)
        CQUI.text(self, CQUI.fit(T("IGUI_CQ_Assign_" .. m.assign) .. "  -  " .. T("IGUI_CQ_NSteps", #m.steps), FS, lw - 30), x + 10, ly + fh() + 7, C.dim)
        ly = ly + rh + 4
    end
    if #list == 0 then
        CQUI.para(self, T("IGUI_CQ_NoMissionLib"), x + 4, ly + 4, lw - 10, C.faint)
        ly = ly + 40
    end
    self:endScroll(ly + off - ly0)
    -- editor
    local ex = x + lw + 14
    local ew = w - lw - 14
    local m = self.ed.mission
    if not m or not self.sel.mission then
        CQUI.para(self, T("IGUI_CQ_MissionHint"), ex, y + 10, ew, C.faint)
        clearPreview()
        CQMap.adminZones = nil
        CQMap.pick = nil
        return
    end
    local dirty = self:missionDirty()
    CQUI.text(self, CQUI.fit((m.id ~= "" and ("#" .. m.id .. "  ") or "") .. (self:getE("mTitle") ~= "" and self:getE("mTitle") or m.title), FM, ew - S(40)), ex, y, C.gold, 1, FM)
    if dirty then CQUI.textR(self, T("IGUI_CQ_Unsaved"), ex + ew, y + 3, C.accent) end
    local ty = y + CQUI.fh(FM) + 8
    CQUI.tabs(self, ex, ty, ew, fh() + 12, {
        { key = "info", label = T("IGUI_CQ_MTab_info") },
        { key = "route", label = T("IGUI_CQ_MTab_route"), badge = tostring(#m.steps) },
        { key = "reward", label = T("IGUI_CQ_MTab_reward") },
    }, self.sub.missions, function(k)
        if self.sub.missions == "route" then self:commitStep() end
        self.sub.missions = k
    end)
    local cy = ty + fh() + 22
    local barY = self:barTop("mission", y, h, h1)
    -- map overlay of all steps of this mission
    local zones = {}
    for i, st in ipairs(m.steps) do
        if st.zone then zones[#zones + 1] = { zone = st.zone, label = tostring(i) .. ". " .. CQUI.stepLabel(st), cur = (i == self.stepSel) } end
    end
    CQMap.adminZones = zones
    self.mapUsed = true
    local sub = self.sub.missions
    local fhgt = barY - cy - 8
    self:form("fm_" .. sub, ex, cy, ew, fhgt, function(top)
        if sub == "info" then
            self:missionInfo(m, ex, top, ew, fhgt)
            clearPreview()
            CQMap.pick = nil
        elseif sub == "route" then
            self:missionRoute(m, ex, top, ew, fhgt)
        else
            self:missionReward(m, ex, top, ew, fhgt)
            clearPreview()
            CQMap.pick = nil
        end
    end)
    -- action bar (wraps to a second row when the buttons do not fit)
    CQUI.sep(self, ex, barY - 6, ew)
    local saved = m.id ~= ""
    local dw = CQUI.tw(FS, T("IGUI_CQ_Delete")) + 22
    self:barBegin("mission", ex, barY, ew, h1, saved and dw or 0)
    self:barBtn(T("IGUI_CQ_Save") .. (dirty and " *" or ""), function() self:saveMission() end, "primary", { minW = S(110) })
    self:barBtn(T("IGUI_CQ_MakeSheet"), function()
        if dirty then self:saveMission() end
        CQC.send("sheet", { mid = m.id, n = 1 })
    end, "purple", { disabled = not saved, tip = T("IGUI_CQ_MakeSheetTip") })
    self:barBtn(T("IGUI_CQ_GiveMe"), function()
        CQC.send("give", { mid = m.id, to = (CQC.me and CQC.me.name) or "" })
    end, "ghost", { disabled = not saved, tip = T("IGUI_CQ_GiveMeTip") })
    if saved then
        self:barConfirm("giveall" .. m.id, T("IGUI_CQ_GiveAll"), function() CQC.send("give", { mid = m.id, to = "*" }) end)
    else
        self:barBtn(T("IGUI_CQ_GiveAll"), nil, "ghost", { disabled = true })
    end
    self:barBtn(T("IGUI_CQ_Duplicate"), function()
        self:readMission()
        local cp = CQ.copy(self.ed.mission)
        cp.id = ""
        cp.title = cp.title .. " (2)"
        self.sel.mission = "new"
        self.ed.mission = cp
        self.dirty.mission = true
        self:setE("mTitle", cp.title)
    end, "ghost", { disabled = not saved })
    if saved then
        self:confirmBtn("delm" .. m.id, ex + ew - dw, barY, dw, h1, T("IGUI_CQ_Delete"), function()
            CQC.send("delMission", { id = m.id })
            self.sel.mission = nil
            self.ed.mission = nil
        end)
    end
    self:barEnd()
end

function A:missionInfo(m, x, y, w, h)
    local h1 = eh()
    self:label(T("IGUI_CQ_MTitle"), x, y)
    y = y + fh() + 4
    self:place("mTitle", x, y, w, h1)
    y = y + h1 + 8
    self:label(T("IGUI_CQ_MStory"), x, y)
    y = y + fh() + 4
    local sh = math.min(fh() * 12 + 10, math.max(fh() * 4 + 10, h - 230))
    self:place("mStory", x, y, w, sh)
    y = y + sh + 10
    local assigns = { "reader", "everyone", "board", "role" }
    local ai = CQ.indexOf(assigns, m.assign) or 1
    self:label(T("IGUI_CQ_AssignL"), x, y)
    y = y + fh() + 4
    CQUI.cycle(self, x, y, S(250), h1, T("IGUI_CQ_Assign_" .. m.assign), function()
        ai = ai - 1; if ai < 1 then ai = #assigns end; m.assign = assigns[ai]; self.dirty.mission = true
    end, function()
        ai = ai + 1; if ai > #assigns then ai = 1 end; m.assign = assigns[ai]; self.dirty.mission = true
    end)
    CQUI.para(self, T("IGUI_CQ_AssignD_" .. m.assign), x + S(262), y, w - S(262), C.faint, FS, 3)
    y = y + math.max(h1, CQUI.paraH(T("IGUI_CQ_AssignD_" .. m.assign), w - S(262), FS, 3)) + 10
    local tx = x
    tx = tx + CQUI.toggle(self, tx, y, T("IGUI_CQ_TeamProgress"), m.team, function() m.team = not m.team; self.dirty.mission = true end, { tip = T("IGUI_CQ_TeamTip") }) + 22
    tx = tx + CQUI.toggle(self, tx, y, T("IGUI_CQ_ShowSteps"), m.showSteps, function() m.showSteps = not m.showSteps; self.dirty.mission = true end, { tip = T("IGUI_CQ_ShowStepsTip") }) + 22
    tx = tx + CQUI.toggle(self, tx, y, T("IGUI_CQ_RepeatableL"), m.repeatable, function() m.repeatable = not m.repeatable; self.dirty.mission = true end) + 22
    y = y + fh() + 12
    self:label(T("IGUI_CQ_LimitL"), x, y)
    self:label(T("IGUI_CQ_TimeLimitL"), x + S(190), y)
    if m.team then self:label(T("IGUI_CQ_RewardToL"), x + S(380), y) end
    y = y + fh() + 4
    CQUI.stepper(self, x, y, S(170), h1, m.limit == 0 and T("IGUI_CQ_Unlimited") or tostring(m.limit),
        function() m.limit = math.max(0, m.limit - 1); self.dirty.mission = true end,
        function() m.limit = math.min(999, m.limit + 1); self.dirty.mission = true end, { tip = T("IGUI_CQ_LimitTip") })
    CQUI.stepper(self, x + S(190), y, S(170), h1, m.timeLimit == 0 and T("IGUI_CQ_NoTimeLimit") or CQUI.durMin(m.timeLimit),
        function() m.timeLimit = math.max(0, m.timeLimit - 5); self.dirty.mission = true end,
        function() m.timeLimit = math.min(10080, m.timeLimit + 5); self.dirty.mission = true end)
    if m.team then
        CQUI.cycle(self, x + S(380), y, math.min(S(260), w - S(380)), h1, T("IGUI_CQ_RewardTo_" .. m.rewardTo), function()
            m.rewardTo = (m.rewardTo == "contrib") and "members" or "contrib"; self.dirty.mission = true
        end, function()
            m.rewardTo = (m.rewardTo == "contrib") and "members" or "contrib"; self.dirty.mission = true
        end)
    end
end

function A:missionRoute(m, x, y, w, h)
    local h1 = eh()
    local p = CQC.player()
    -- chain chips (wrap to more rows)
    local n = #m.steps
    local addW = S(44)
    local avail = w - addW - 8
    local perRow = math.max(1, math.min(n, math.floor((avail + 8) / S(128))))
    local cw = math.min(S(160), math.floor((avail + 8) / perRow) - 8)
    local cx = x
    local rowY = y
    for i = 1, n do
        local st = m.steps[i]
        if i > 1 and CQ.mod(i - 1, perRow) == 0 then
            cx = x
            rowY = rowY + h1 + 5
        end
        local sel = i == self.stepSel
        local over = self:hit(cx, rowY, cw, h1, function()
            self:commitStep()
            self.stepSel = i
            self:loadStep()
        end, CQUI.stepLabel(st))
        CQUI.rbox(self, cx, rowY, cw, h1, sel and C.accentD or (over and C.panel3 or C.panel2), 1, 6)
        CQUI.icon(self, CQUI.STEP_ICON[st.t], cx + 5, rowY + (h1 - fh()) / 2, fh(), CQUI.STEP_COLOR[st.t])
        local lbl = tostring(i) .. ". " .. CQUI.stepLabel(st)
        if sel and self:getE("stLabel") ~= "" then lbl = tostring(i) .. ". " .. self:getE("stLabel") end
        CQUI.text(self, CQUI.fit(lbl, FS, cw - fh() - 14), cx + fh() + 9, rowY + 4, sel and C.gold or C.text)
        if i < n and CQ.mod(i, perRow) ~= 0 then CQUI.textC(self, ">", cx + cw + 4, rowY + 4, C.faint) end
        cx = cx + cw + 8
    end
    CQUI.btn(self, x + w - addW, y, addW, h1, "+", function()
        self:commitStep()
        if #m.steps >= 20 then return end
        local st = { t = "reach", label = "", hint = "" }
        defaultsFor(st, p)
        table.insert(m.steps, self.stepSel + 1, st)
        self.stepSel = self.stepSel + 1
        self:loadStep()
        self.dirty.mission = true
    end, "primary", { tip = T("IGUI_CQ_AddStep") })
    y = rowY + h1 + 8
    local st = m.steps[self.stepSel]
    if not st then return end
    -- step tools
    local bx = x
    bx = bx + CQUI.btnA(self, bx, y, fh() + 6, T("IGUI_CQ_MoveL"), function()
        if self.stepSel > 1 then
            self:commitStep()
            m.steps[self.stepSel], m.steps[self.stepSel - 1] = m.steps[self.stepSel - 1], m.steps[self.stepSel]
            self.stepSel = self.stepSel - 1
            self.dirty.mission = true
        end
    end, "flat") + 4
    bx = bx + CQUI.btnA(self, bx, y, fh() + 6, T("IGUI_CQ_MoveR"), function()
        if self.stepSel < #m.steps then
            self:commitStep()
            m.steps[self.stepSel], m.steps[self.stepSel + 1] = m.steps[self.stepSel + 1], m.steps[self.stepSel]
            self.stepSel = self.stepSel + 1
            self.dirty.mission = true
        end
    end, "flat") + 4
    bx = bx + CQUI.btnA(self, bx, y, fh() + 6, T("IGUI_CQ_DupStep"), function()
        self:commitStep()
        if #m.steps >= 20 then return end
        table.insert(m.steps, self.stepSel + 1, CQ.copy(st))
        self.stepSel = self.stepSel + 1
        self:loadStep()
        self.dirty.mission = true
    end, "flat") + 4
    if #m.steps > 1 then
        local dw = CQUI.tw(FS, T("IGUI_CQ_DelStep")) + 20
        self:confirmBtn("dels" .. tostring(self.stepSel), bx, y, dw, fh() + 6, T("IGUI_CQ_DelStep"), function()
            table.remove(m.steps, self.stepSel)
            if self.stepSel > #m.steps then self.stepSel = #m.steps end
            self:loadStep()
            self.dirty.mission = true
        end, "flat")
    end
    y = y + fh() + 14
    -- type
    local types = CQ.STEPS
    local ti = CQ.indexOf(types, st.t) or 1
    self:label(T("IGUI_CQ_StepType"), x, y)
    y = y + fh() + 4
    local function setType(nt)
        self:commitStep()
        st.t = nt
        defaultsFor(st, p)
        self:loadStep()
        self.dirty.mission = true
    end
    CQUI.cycle(self, x, y, S(240), h1, T("IGUI_CQ_StepT_" .. st.t), function()
        ti = ti - 1; if ti < 1 then ti = #types end; setType(types[ti])
    end, function()
        ti = ti + 1; if ti > #types then ti = 1 end; setType(types[ti])
    end, { color = CQUI.STEP_COLOR[st.t] })
    CQUI.para(self, T("IGUI_CQ_StepD_" .. st.t), x + S(252), y, w - S(252), C.faint, FS, 3)
    y = y + math.max(h1, CQUI.paraH(T("IGUI_CQ_StepD_" .. st.t), w - S(252), FS, 3)) + 8
    self:label(T("IGUI_CQ_StepLabel"), x, y)
    self:label(T("IGUI_CQ_StepHint"), x + w / 2 + 5, y)
    y = y + fh() + 4
    self:place("stLabel", x, y, w / 2 - 5, h1)
    self:place("stHint", x + w / 2 + 5, y, w / 2 - 5, h1)
    y = y + h1 + 10
    local info = CQ.STEP_INFO[st.t] or {}
    -- zone block
    local zoneOn = info.zone or (info.zoneOpt and st.zone ~= nil)
    if info.zoneOpt then
        CQUI.toggle(self, x, y, T("IGUI_CQ_KillZone"), st.zone ~= nil, function()
            if st.zone then st.zone = nil elseif p then st.zone = CQ.makeZone(p:getX(), p:getY(), p:getZ(), 15, 15) end
            self.dirty.mission = true
        end)
        y = y + fh() + 8
    end
    if zoneOn then
        local zn = st.zone
        local zx = x + 10
        -- controls flow onto more rows when the editor is narrow (big font / small screen)
        local useW = CQUI.tw(FS, T("IGUI_CQ_UseMyPos")) + 44
        local items = zn and { useW, S(120), S(120), S(140), S(150) } or { useW }
        local pos, fx, row = {}, zx, 0
        for i, iw in ipairs(items) do
            if fx > zx and fx + iw > x + w - 10 then row = row + 1; fx = zx end
            pos[i] = { fx, row }
            fx = fx + iw + 6
        end
        local blockH = 8 + fh() + 6 + (row + 1) * (h1 + 6) + 2 + h1 + 8
        CQUI.rbox(self, x, y, w, blockH, C.panel, 1, 8)
        local zy = y + 8
        local txt
        if zn then
            local cx2, cy2 = CQ.zoneCenter(zn)
            txt = T("IGUI_CQ_ZoneInfo", cx2, cy2, zn.anyZ and T("IGUI_CQ_FloorAny") or CQUI.floorText(zn.z or 0), CQ.zoneW(zn) .. "x" .. CQ.zoneH(zn))
            if p then txt = txt .. "   " .. T("IGUI_CQ_ZoneDist", math.floor(CQ.distToZone(zn, p:getX(), p:getY()) + 0.5)) end
            if p and CQ.inZone(zn, p:getX(), p:getY(), p:getZ()) then txt = txt .. "   " .. T("IGUI_CQ_YouInside") end
        else
            txt = T("IGUI_CQ_ZoneNone")
        end
        CQUI.text(self, CQUI.fit(txt, FS, w - 20), zx, zy, zn and C.text or C.bad)
        zy = zy + fh() + 6
        local function at(i) return pos[i][1], zy + pos[i][2] * (h1 + 6) end
        local bx1, by1 = at(1)
        CQUI.btn(self, bx1, by1, useW, h1, T("IGUI_CQ_UseMyPos"), function()
            if not p then return end
            local w0, h0 = 5, 5
            if st.zone then w0, h0 = CQ.zoneW(st.zone), CQ.zoneH(st.zone) end
            local any = st.zone and st.zone.anyZ
            st.zone = CQ.makeZone(p:getX(), p:getY(), p:getZ(), w0, h0)
            st.zone.anyZ = any == true
            self.dirty.mission = true
        end, "primary", { icon = "cq_s_reach" })
        if zn then
            local sx, sy = at(2)
            CQUI.stepper(self, sx, sy, S(120), h1, "W " .. tostring(CQ.zoneW(zn)),
                function() st.zone = CQ.resizeZone(zn, math.max(1, CQ.zoneW(zn) - 2), CQ.zoneH(zn)); self.dirty.mission = true end,
                function() st.zone = CQ.resizeZone(zn, CQ.zoneW(zn) + 2, CQ.zoneH(zn)); self.dirty.mission = true end)
            sx, sy = at(3)
            CQUI.stepper(self, sx, sy, S(120), h1, "H " .. tostring(CQ.zoneH(zn)),
                function() st.zone = CQ.resizeZone(zn, CQ.zoneW(zn), math.max(1, CQ.zoneH(zn) - 2)); self.dirty.mission = true end,
                function() st.zone = CQ.resizeZone(zn, CQ.zoneW(zn), CQ.zoneH(zn) + 2); self.dirty.mission = true end)
            local cur = CQ.zoneW(zn)
            local pi = 1
            for i, v in ipairs(ZONE_PRESETS) do if v <= cur then pi = i end end
            sx, sy = at(4)
            CQUI.cycle(self, sx, sy, math.min(S(140), x + w - sx - 10), h1, T("IGUI_CQ_ZonePreset"), function()
                local ni = math.max(1, pi - 1)
                st.zone = CQ.resizeZone(zn, ZONE_PRESETS[ni], ZONE_PRESETS[ni]); self.dirty.mission = true
            end, function()
                local ni = math.min(#ZONE_PRESETS, pi + 1)
                st.zone = CQ.resizeZone(zn, ZONE_PRESETS[ni], ZONE_PRESETS[ni]); self.dirty.mission = true
            end)
            -- floor / depth of the checkpoint (basements are below 1)
            sx, sy = at(5)
            CQUI.stepper(self, sx, sy, S(150), h1, CQUI.floorText(zn.z or 0),
                function() zn.z = math.max(-32, (zn.z or 0) - 1); self.dirty.mission = true end,
                function() zn.z = math.min(31, (zn.z or 0) + 1); self.dirty.mission = true end, { tip = T("IGUI_CQ_ZoneFloorTip") })
        end
        zy = zy + (row + 1) * (h1 + 6) + 2
        local tbx = zx
        if zn then
            tbx = tbx + CQUI.toggle(self, tbx, zy, T("IGUI_CQ_AnyFloor"), zn.anyZ == true, function() zn.anyZ = not zn.anyZ; self.dirty.mission = true end) + 18
        end
        tbx = tbx + CQUI.toggle(self, tbx, zy, T("IGUI_CQ_HideZone"), st.hide == true, function() st.hide = not st.hide; self.dirty.mission = true end, { tip = T("IGUI_CQ_HideZoneTip") }) + 18
        if x + w - tbx - 10 > 40 then
            CQUI.text(self, CQUI.fit(T("IGUI_CQ_MapPickTip"), FS, x + w - tbx - 10), tbx, zy, C.faint)
        end
        y = y + blockH + 8
        preview(st.zone)
        CQMap.pick = function(wx, wy)
            local w0, h0 = 5, 5
            local zz = p and math.floor(p:getZ()) or 0
            if st.zone then w0, h0, zz = CQ.zoneW(st.zone), CQ.zoneH(st.zone), st.zone.z end
            local any = st.zone and st.zone.anyZ
            st.zone = CQ.makeZone(wx, wy, zz, w0, h0)
            st.zone.anyZ = any == true
            self.dirty.mission = true
        end
    else
        preview(nil)
        CQMap.pick = nil
    end
    -- per-type fields
    if info.item then
        self:label(T("IGUI_CQ_StepItem"), x, y)
        y = y + fh() + 4
        local ny = self:itemPick("st", x, y, w - S(200))
        CQUI.stepper(self, x + w - S(190), y, S(90), h1, "x" .. tostring(st.n or 1),
            function() st.n = math.max(1, (st.n or 1) - 1); self.dirty.mission = true end,
            function() st.n = math.min(9999, (st.n or 1) + 1); self.dirty.mission = true end)
        CQUI.stepper(self, x + w - S(94), y, S(94), h1, "10",
            function() st.n = math.max(1, (st.n or 1) - 10); self.dirty.mission = true end,
            function() st.n = math.min(9999, (st.n or 1) + 10); self.dirty.mission = true end)
        y = ny + 6
    elseif info.n then
        self:label(st.t == "kill" and T("IGUI_CQ_KillN") or T("IGUI_CQ_OthersN"), x, y)
        y = y + fh() + 4
        CQUI.stepper(self, x, y, S(140), h1, tostring(st.n or 1),
            function() st.n = math.max(1, (st.n or 1) - 1); self.dirty.mission = true end,
            function() st.n = math.min(9999, (st.n or 1) + 1); self.dirty.mission = true end)
        CQUI.stepper(self, x + S(146), y, S(100), h1, "10",
            function() st.n = math.max(1, (st.n or 1) - 10); self.dirty.mission = true end,
            function() st.n = math.min(9999, (st.n or 1) + 10); self.dirty.mission = true end)
        y = y + h1 + 8
    end
    if info.sec then
        self:label(T("IGUI_CQ_HoldSec"), x, y)
        y = y + fh() + 4
        CQUI.stepper(self, x, y, S(160), h1, CQ.clock(st.sec or 60),
            function() st.sec = math.max(5, (st.sec or 60) - 10); self.dirty.mission = true end,
            function() st.sec = math.min(7200, (st.sec or 60) + 10); self.dirty.mission = true end)
        CQUI.stepper(self, x + S(166), y, S(110), h1, "60s",
            function() st.sec = math.max(5, (st.sec or 60) - 60); self.dirty.mission = true end,
            function() st.sec = math.min(7200, (st.sec or 60) + 60); self.dirty.mission = true end)
        y = y + h1 + 8
    end
    if info.target then
        self:label(T("IGUI_CQ_Target"), x, y)
        y = y + fh() + 4
        self:place("stTarget", x, y, S(220), h1)
        local px = x + S(230)
        local users = (CQC.adm and CQC.adm.users) or {}
        for _, u in ipairs(users) do
            if u.online then
                local bw = CQUI.tw(FS, u.name) + 16
                if px + bw > x + w then break end
                CQUI.btn(self, px, y, bw, h1, u.name, function() self:setE("stTarget", u.name); self.loaded.stTarget = "" end, "flat")
                px = px + bw + 4
            end
        end
        y = y + h1 + 8
    end
    if info.ch then
        self:label(T("IGUI_CQ_Freq"), x, y)
        y = y + fh() + 4
        self:place("stCh", x, y, S(100), h1)
        CQUI.btn(self, x + S(106), y, S(170), h1, T("IGUI_CQ_FromRadio"), function()
            local t = CQC.lastTuned or {}
            if #t > 0 then self:setE("stCh", CQ.chText(t[1])); self.loaded.stCh = "" end
        end, "ghost", { tip = T("IGUI_CQ_FromRadioTip") })
        CQUI.text(self, CQAdmin.tunedText(), x + S(286), y + 4, C.faint)
        y = y + h1 + 8
    end
    if st.t == "deliver" then
        CQUI.toggle(self, x, y, T("IGUI_CQ_Consume"), st.consume == true, function() st.consume = not st.consume; self.dirty.mission = true end, { tip = T("IGUI_CQ_ConsumeTip") })
        y = y + fh() + 8
    end
    if st.t == "reach" and m.team then
        CQUI.toggle(self, x, y, T("IGUI_CQ_AllMembers"), st.all == true, function() st.all = not st.all; self.dirty.mission = true end)
        y = y + fh() + 8
    end
end

function A:missionReward(m, x, y, w, h)
    local h1 = eh()
    self:label(T("IGUI_CQ_RewardTextL"), x, y)
    y = y + fh() + 4
    self:place("mRewardText", x, y, w, h1)
    y = y + h1 + 10
    self:label(T("IGUI_CQ_RewardItemsL"), x, y)
    y = y + fh() + 4
    y = self:itemEditor("rew", m.rewards, x, y, w, function() self.dirty.mission = true end)
    y = y + 8
    local who
    if not m.team then who = T("IGUI_CQ_RewardWhoSolo")
    elseif m.rewardTo == "members" then who = T("IGUI_CQ_RewardWhoMembers")
    else who = T("IGUI_CQ_RewardWhoContrib") end
    CQUI.para(self, who, x, y, w, C.faint)
end

-- ===================================================================== event editor state
local function nextSaturday()
    local utc = CQC.utc()
    local lt = CQ.localT(CQC.now(), utc)
    local ahead = CQ.mod(6 - lt.wday, 7)
    if ahead == 0 and lt.mod >= 18 * 60 then ahead = 7 end
    return CQ.tsFromLocal(lt.day + ahead, 18 * 60, utc)
end

local function newEvent()
    return {
        id = "", title = T("IGUI_CQ_NewEvent"), desc = "", start = nextSaturday(), dur = 120, roleMode = "none",
        kit = {}, roles = {}, missions = {}, lateJoin = true, pen = { on = true, mult = 0.5, days = 3, minCp = 1 },
        status = "draft", phases = {}, mph = {}, phaseMode = "strict", spawns = {},
    }
end

function A:selectEvent(id)
    local adm = CQC.adm
    local e = id and adm and adm.events[id]
    self.sel.event = id or "new"
    self.ed.event = CQ.copy(e or newEvent())
    self.dirty.event = false
    self.roleSel = 1
    self.phSel = 1
    self.spSel = 1
    local ev = self.ed.event
    ev.spawns = ev.spawns or {}
    ev.phases = ev.phases or {}
    ev.mph = ev.mph or {}
    ev.phaseMode = ev.phaseMode or "strict"
    for _, r in ipairs(ev.roles or {}) do r.mph = r.mph or {} end
    self:setE("evTitle", ev.title)
    self:setE("evDesc", ev.desc)
    local lt = CQ.localT(ev.start or CQC.now(), CQC.utc())
    self:setE("evTime", CQ.pad2(lt.hour) .. ":" .. CQ.pad2(lt.min))
    self:setE("item_kit", "")
    self:setE("item_rkit", "")
    self:loadRole()
    self:loadPhase()
    self:loadSpawn()
end

function A:loadSpawn()
    local ev = self.ed.event
    if not ev then return end
    local sp = ev.spawns[self.spSel or 1]
    self:setE("spName", sp and sp.name or "")
end

function A:commitSpawn()
    local ev = self.ed.event
    if not ev then return end
    local sp = ev.spawns[self.spSel or 1]
    if sp then sp.name = self:getE("spName") end
end

function A:loadPhase()
    local ev = self.ed.event
    if not ev then return end
    local ph = ev.phases[self.phSel or 1]
    self:setE("phName", ph and ph.name or "")
end

function A:commitPhase()
    local ev = self.ed.event
    if not ev then return end
    local ph = ev.phases[self.phSel or 1]
    if ph then ph.name = self:getE("phName") end
end

function A:loadRole()
    local ev = self.ed.event
    if not ev then return end
    local r = ev.roles[self.roleSel]
    self:setE("roleName", r and r.name or "")
    self:setE("roleDesc", r and r.desc or "")
end

function A:commitRole()
    local ev = self.ed.event
    if not ev then return end
    local r = ev.roles[self.roleSel]
    if not r then return end
    r.name = self:getE("roleName")
    r.desc = self:getE("roleDesc")
end

function A:readEvent()
    self:commitRole()
    self:commitPhase()
    self:commitSpawn()
    local ev = self.ed.event
    ev.title = self:getE("evTitle")
    ev.desc = self:getE("evDesc")
    local mins = CQ.parseHHMM(self:getE("evTime"))
    if mins then
        local lt = CQ.localT(ev.start or CQC.now(), CQC.utc())
        ev.start = CQ.tsFromLocal(lt.day, mins, CQC.utc())
    end
end

function A:eventDirty()
    if not self.ed.event then return false end
    if self.dirty.event then return true end
    return self:eChanged({ "evTitle", "evDesc", "evTime", "roleName", "roleDesc", "phName", "spName" })
end

function A:saveEvent()
    self:readEvent()
    CQC.send("saveEvent", { e = self.ed.event })
    self.dirty.event = false
    for _, n in ipairs({ "evTitle", "evDesc", "evTime", "roleName", "roleDesc", "phName", "spName" }) do self.loaded[n] = self:getE(n) end
end

function A:onSavedEvent(id)
    self.sel.event = id
    if self.ed.event and (self.ed.event.id == "" or self.ed.event.id == nil) then self.ed.event.id = id end
end

-- ===================================================================== events page
local STATUS_COL = { live = C.good, sched = C.accent, draft = C.dim, done = C.faint }

function A:page_events(x, y, w, h)
    local adm = CQC.adm
    local lw = math.min(S(230), math.max(230, math.floor(w * 0.27)))
    local h1 = eh()
    CQUI.btn(self, x, y, lw, h1, T("IGUI_CQ_NewEventBtn"), function()
        if self.ed.event then self:commitRole() end
        self:selectEvent(nil)
    end, "primary")
    local order = { live = 1, sched = 2, draft = 3, done = 4 }
    local list = {}
    for _, e in pairs(adm.events) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        local oa, ob = order[a.status] or 9, order[b.status] or 9
        if oa ~= ob then return oa < ob end
        return (a.start or 0) > (b.start or 0)
    end)
    local ly0 = y + h1 + 8
    local off = self:beginScroll("elist", x, ly0, lw, h - h1 - 8)
    local ly = ly0 - off
    for _, e in ipairs(list) do
        local sel = self.sel.event == e.id
        local rh = fh() * 2 + 12
        local over = self:hit(x, ly, lw - 6, rh, function()
            if self.ed.event then self:commitRole() end
            self:selectEvent(e.id)
        end)
        CQUI.rbox(self, x, ly, lw - 6, rh, sel and C.panel3 or (over and C.panel2 or C.panel), 1, 6)
        CQUI.rbox(self, x + 8, ly + 9, 8, 8, STATUS_COL[e.status] or C.dim, 1, 4)
        CQUI.text(self, CQUI.fit(e.title, FS, lw - 40), x + 22, ly + 5, C.text)
        CQUI.text(self, CQUI.fit(T("IGUI_CQ_St_" .. e.status) .. "  -  " .. CQUI.dateText(e.start or 0), FS, lw - 30), x + 22, ly + fh() + 7, C.dim)
        ly = ly + rh + 4
    end
    if #list == 0 then
        CQUI.para(self, T("IGUI_CQ_NoEventLib"), x + 4, ly + 4, lw - 10, C.faint)
        ly = ly + 40
    end
    self:endScroll(ly + off - ly0)
    local ex = x + lw + 14
    local ew = w - lw - 14
    local ev = self.ed.event
    if not ev or not self.sel.event then
        CQUI.para(self, T("IGUI_CQ_EventHint"), ex, y + 10, ew, C.faint)
        return
    end
    -- keep status fresh from server
    local live = ev.id ~= "" and adm.events[ev.id]
    if live then ev.status = live.status end
    local dirty = self:eventDirty()
    local pw = CQUI.pill(self, ex, y + 3, T("IGUI_CQ_St_" .. (ev.status or "draft")), STATUS_COL[ev.status] or C.dim, FS, true)
    CQUI.text(self, CQUI.fit(self:getE("evTitle"), FM, ew - pw - 120), ex + pw + 8, y, C.gold, 1, FM)
    if dirty then CQUI.textR(self, T("IGUI_CQ_Unsaved"), ex + ew, y + 3, C.accent) end
    local ty = y + CQUI.fh(FM) + 8
    CQUI.tabs(self, ex, ty, ew, fh() + 12, {
        { key = "gen", label = T("IGUI_CQ_ETab_gen") },
        { key = "roles", label = T("IGUI_CQ_ETab_roles"), badge = tostring(#ev.roles) },
        { key = "kit", label = T("IGUI_CQ_ETab_kit") },
        { key = "phase", label = T("IGUI_CQ_ETab_phase"), badge = (#ev.phases > 1) and tostring(#ev.phases) or nil },
        { key = "zombie", label = T("IGUI_CQ_ETab_zombie"), badge = (#ev.spawns > 0) and tostring(#ev.spawns) or nil },
        { key = "pen", label = T("IGUI_CQ_ETab_pen") },
    }, self.sub.events, function(k)
        if self.sub.events == "roles" then self:commitRole() end
        if self.sub.events == "phase" then self:commitPhase() end
        if self.sub.events == "zombie" then self:commitSpawn() end
        self.sub.events = k
    end)
    local cy = ty + fh() + 22
    local barY = self:barTop("event", y, h, h1)
    local sub = self.sub.events
    local fhgt = barY - cy - 8
    self:form("fe_" .. sub, ex, cy, ew, fhgt, function(top)
        if sub == "gen" then self:eventGeneral(ev, ex, top, ew, fhgt)
        elseif sub == "roles" then self:eventRoles(ev, ex, top, ew, fhgt)
        elseif sub == "kit" then self:eventKit(ev, ex, top, ew, fhgt)
        elseif sub == "phase" then self:eventPhases(ev, ex, top, ew, fhgt)
        elseif sub == "zombie" then self:eventSpawns(ev, ex, top, ew, fhgt)
        else self:eventPen(ev, ex, top, ew, fhgt) end
    end)
    -- action bar (wraps to a second row when the buttons do not fit)
    CQUI.sep(self, ex, barY - 6, ew)
    local saved = ev.id ~= ""
    local function ctl(op)
        if self:eventDirty() then self:saveEvent() end
        CQC.send("eventCtl", { id = ev.id, op = op })
    end
    local canDel = saved and ev.status ~= "live"
    local dw = CQUI.tw(FS, T("IGUI_CQ_Delete")) + 22
    self:barBegin("event", ex, barY, ew, h1, canDel and dw or 0)
    self:barBtn(T("IGUI_CQ_Save") .. (dirty and " *" or ""), function() self:saveEvent() end, "primary", { minW = S(100) })
    if ev.status == "draft" or ev.status == "done" then
        self:barBtn(T("IGUI_CQ_OpenReg"), function() ctl("sched") end, "good", { disabled = not saved, tip = T("IGUI_CQ_OpenRegTip") })
    end
    if ev.status == "sched" then
        self:barBtn(T("IGUI_CQ_ToDraft"), function() ctl("draft") end, "ghost", { tip = T("IGUI_CQ_ToDraftTip") })
    end
    if ev.status ~= "live" then
        if saved then self:barConfirm("start" .. ev.id, T("IGUI_CQ_StartNow"), function() ctl("start") end, "ghost")
        else self:barBtn(T("IGUI_CQ_StartNow"), nil, "ghost", { disabled = true }) end
    else
        self:barConfirm("endE" .. ev.id, T("IGUI_CQ_EndNow"), function() ctl("end") end, "danger")
    end
    self:barBtn(T("IGUI_CQ_Duplicate"), function()
        self:readEvent()
        local cp = CQ.copy(self.ed.event)
        cp.id = ""
        cp.status = "draft"
        cp.parts = nil
        cp.results = nil
        cp.title = cp.title .. " (2)"
        if cp.start and cp.start < CQC.now() then cp.start = cp.start + 7 * 86400 end
        self.sel.event = "new"
        self.ed.event = cp
        self.dirty.event = true
        self:setE("evTitle", cp.title)
    end, "ghost", { disabled = not saved })
    if canDel then
        self:barConfirm("reset" .. ev.id, T("IGUI_CQ_ResetEv"), function() ctl("reset") end)
        self:confirmBtn("dele" .. ev.id, ex + ew - dw, barY, dw, h1, T("IGUI_CQ_Delete"), function()
            CQC.send("delEvent", { id = ev.id })
            self.sel.event = nil
            self.ed.event = nil
        end)
    end
    self:barEnd()
end

function A:eventGeneral(ev, x, y, w, h)
    local h1 = eh()
    self:label(T("IGUI_CQ_ETitle"), x, y)
    y = y + fh() + 4
    self:place("evTitle", x, y, w, h1)
    y = y + h1 + 8
    self:label(T("IGUI_CQ_EDesc"), x, y)
    y = y + fh() + 4
    self:place("evDesc", x, y, w, fh() * 6 + 10)
    y = y + fh() * 6 + 18
    self:label(T("IGUI_CQ_EDay"), x, y)
    y = y + fh() + 4
    local lt = CQ.localT(ev.start or CQC.now(), CQC.utc())
    CQUI.cycle(self, x, y, S(240), h1, CQUI.dayText(lt.day), function()
        ev.start = (ev.start or CQC.now()) - 86400; self.dirty.event = true
    end, function()
        ev.start = (ev.start or CQC.now()) + 86400; self.dirty.event = true
    end)
    local bx = x + S(248)
    bx = bx + CQUI.btnA(self, bx, y, h1, T("IGUI_CQ_Today"), function()
        local now = CQ.localT(CQC.now(), CQC.utc())
        ev.start = CQ.tsFromLocal(now.day, lt.mod, CQC.utc()); self.dirty.event = true
    end, "ghost") + 6
    CQUI.btnA(self, bx, y, h1, T("IGUI_CQ_ThisSat"), function()
        local sat = CQ.localT(nextSaturday(), CQC.utc())
        ev.start = CQ.tsFromLocal(sat.day, lt.mod, CQC.utc()); self.dirty.event = true
    end, "ghost")
    y = y + h1 + 8
    self:label(T("IGUI_CQ_ETime"), x, y)
    self:label(T("IGUI_CQ_EDur"), x + S(100), y)
    y = y + fh() + 4
    self:place("evTime", x, y, S(88), h1)
    CQUI.stepper(self, x + S(100), y, S(170), h1, CQUI.durMin(ev.dur or 120),
        function() ev.dur = math.max(5, (ev.dur or 120) - 15); self.dirty.event = true end,
        function() ev.dur = math.min(10080, (ev.dur or 120) + 15); self.dirty.event = true end)
    local mins = CQ.parseHHMM(self:getE("evTime"))
    if not mins then
        CQUI.text(self, T("IGUI_CQ_BadTime"), x + S(282), y + 4, C.bad)
    else
        local st = CQ.tsFromLocal(lt.day, mins, CQC.utc())
        local endTs = st + (ev.dur or 120) * 60
        CQUI.para(self, T("IGUI_CQ_EWhen", CQUI.dateText(st), CQUI.dateText(endTs)), x + S(282), y + 4, w - S(282), C.faint, FS, 2)
    end
    y = y + h1 + 12
    local modes = { "none", "pick", "random", "admin" }
    local mi = CQ.indexOf(modes, ev.roleMode) or 1
    self:label(T("IGUI_CQ_RoleModeL"), x, y)
    y = y + fh() + 4
    CQUI.cycle(self, x, y, S(230), h1, T("IGUI_CQ_RM_" .. ev.roleMode), function()
        mi = mi - 1; if mi < 1 then mi = #modes end; ev.roleMode = modes[mi]; self.dirty.event = true
    end, function()
        mi = mi + 1; if mi > #modes then mi = 1 end; ev.roleMode = modes[mi]; self.dirty.event = true
    end)
    CQUI.para(self, T("IGUI_CQ_RoleMode_" .. ev.roleMode), x + S(240), y + 4, w - S(240), C.faint, FS, 2)
    y = y + h1 + 10
    CQUI.toggle(self, x, y, T("IGUI_CQ_LateJoin"), ev.lateJoin ~= false, function() ev.lateJoin = not (ev.lateJoin ~= false); self.dirty.event = true end)
    y = y + fh() + 10
    CQUI.para(self, T("IGUI_CQ_EFlow"), x, y, w, C.faint)
end

function A:eventRoles(ev, x, y, w, h)
    local h1 = eh()
    if ev.roleMode == "none" then
        local u = CQUI.para(self, T("IGUI_CQ_RolesOff"), x, y, w, C.accent)
        y = y + u + 6
    end
    -- role chips (wrap to more rows)
    local cx = x
    local rowY = y
    local maxX = x + w - S(118)
    for i, r in ipairs(ev.roles) do
        local name = (i == self.roleSel and self:getE("roleName") ~= "") and self:getE("roleName") or r.name
        local cw = math.min(S(160), CQUI.tw(FS, name) + 30)
        if cx + cw > maxX and cx > x then
            cx = x
            rowY = rowY + h1 + 5
        end
        local sel = i == self.roleSel
        local over = self:hit(cx, rowY, cw, h1, function()
            self:commitRole()
            self.roleSel = i
            self:loadRole()
        end, name)
        CQUI.rbox(self, cx, rowY, cw, h1, sel and C.accentD or (over and C.panel3 or C.panel2), 1, 6)
        CQUI.textC(self, CQUI.fit(name, FS, cw - 20), cx + cw / 2, rowY + 4, sel and C.gold or C.text)
        if r.secret then CQUI.rbox(self, cx + cw - 9, rowY + 4, 5, 5, C.purple, 1, 2) end
        cx = cx + cw + 5
    end
    CQUI.btn(self, x + w - S(110), y, S(110), h1, T("IGUI_CQ_AddRole"), function()
        self:commitRole()
        if #ev.roles >= 12 then return end
        ev.roles[#ev.roles + 1] = { id = "r" .. tostring(CQ.mod(getTimestampMs(), 100000)), name = T("IGUI_CQ_RoleN", #ev.roles + 1), desc = "", kit = {}, missions = {}, max = 0, secret = false }
        self.roleSel = #ev.roles
        self:loadRole()
        self.dirty.event = true
    end, "primary")
    y = rowY + h1 + 10
    local r = ev.roles[self.roleSel]
    if not r then
        CQUI.para(self, T("IGUI_CQ_RolesHint"), x, y, w, C.faint)
        return
    end
    local lw = math.floor(w * 0.5) - 6
    local rx = x + lw + 12
    local rw = w - lw - 12
    local ly = y
    self:label(T("IGUI_CQ_RoleNameL"), x, ly)
    ly = ly + fh() + 4
    self:place("roleName", x, ly, lw, h1)
    ly = ly + h1 + 6
    self:label(T("IGUI_CQ_RoleDescL"), x, ly)
    ly = ly + fh() + 4
    self:place("roleDesc", x, ly, lw, fh() * 4 + 10)
    ly = ly + fh() * 4 + 16
    CQUI.stepper(self, x, ly, S(150), h1, (r.max or 0) == 0 and T("IGUI_CQ_Unlimited") or T("IGUI_CQ_MaxN", r.max),
        function() r.max = math.max(0, (r.max or 0) - 1); self.dirty.event = true end,
        function() r.max = math.min(99, (r.max or 0) + 1); self.dirty.event = true end, { tip = T("IGUI_CQ_MaxTip") })
    local tgx, tgy = x + S(160), ly + 4
    if S(160) + fh() + 12 + CQUI.tw(FS, T("IGUI_CQ_SecretRole")) > lw then
        tgx, tgy = x, ly + h1 + 6
        ly = ly + h1 + 6
    end
    CQUI.toggle(self, tgx, tgy, T("IGUI_CQ_SecretRole"), r.secret == true, function() r.secret = not r.secret; self.dirty.event = true end, { tip = T("IGUI_CQ_SecretTip") })
    ly = ly + h1 + 8
    local dw = CQUI.tw(FS, T("IGUI_CQ_DelRole")) + 22
    self:confirmBtn("delrole" .. tostring(self.roleSel), x, ly, dw, fh() + 6, T("IGUI_CQ_DelRole"), function()
        table.remove(ev.roles, self.roleSel)
        self.roleSel = math.max(1, math.min(self.roleSel, #ev.roles))
        self:loadRole()
        self.dirty.event = true
    end, "flat")
    ly = ly + fh() + 14
    -- missions of the role (right column)
    self:label(T("IGUI_CQ_RoleMissions"), rx, y)
    r.mph = r.mph or {}
    self:missionPicker("role" .. tostring(self.roleSel), r.missions, rx, y + fh() + 4, rw, ly - y - fh() - 10, function() self.dirty.event = true end, r.mph, #ev.phases)
    -- kit
    self:label(T("IGUI_CQ_RoleKitL"), x, ly)
    ly = ly + fh() + 4
    self:itemEditor("rkit", r.kit, x, ly, w, function() self.dirty.event = true end)
end

function A:eventKit(ev, x, y, w, h)
    local bottom = y + h
    self:label(T("IGUI_CQ_KitCommon"), x, y)
    y = y + fh() + 4
    y = self:itemEditor("kit", ev.kit, x, y, w, function() self.dirty.event = true end) + 10
    self:label(T("IGUI_CQ_EventMissions"), x, y)
    y = y + fh() + 4
    ev.mph = ev.mph or {}
    self:missionPicker("ev", ev.missions, x, y, w, math.max(90, bottom - y), function() self.dirty.event = true end, ev.mph, #ev.phases)
end

-- ===================================================================== zombie spawn points
local function newSpawn(ev)
    local p = CQC.player()
    local zn = nil
    if p then zn = CQ.makeZone(p:getX(), p:getY(), p:getZ(), 7, 7) end
    return { id = "z" .. tostring(CQ.mod(getTimestampMs(), 100000)), name = "", zone = zn, perMin = 6, maxAlive = 30,
        fromPhase = 1, stopMid = "", stopStep = 1, stopKills = 0 }
end

-- every mission handed out in this event (common + all roles), for the "stop at checkpoint" picker
local function eventMissionIds(ev)
    local out = {}
    local function add(mid) if not CQ.indexOf(out, mid) then out[#out + 1] = mid end end
    for _, mid in ipairs(ev.missions or {}) do add(mid) end
    for _, r in ipairs(ev.roles or {}) do for _, mid in ipairs(r.missions or {}) do add(mid) end end
    return out
end

function A:eventSpawns(ev, x, y, w, h)
    local h1 = eh()
    local adm = CQC.adm
    self.mapUsed = true
    -- every spawn point of this event on the world map (red), the selected one also on the ground
    local zones = {}
    for i, sp in ipairs(ev.spawns) do
        if sp.zone then zones[#zones + 1] = { zone = sp.zone, label = "Z " .. ((sp.name ~= "" and sp.name) or tostring(i)), cur = (i == self.spSel), bad = true } end
    end
    CQMap.adminZones = zones
    if #ev.spawns == 0 then
        local u = CQUI.para(self, T("IGUI_CQ_SpHint"), x, y, w, C.dim)
        y = y + u + 10
        CQUI.btnA(self, x, y, h1 + 4, T("IGUI_CQ_SpAdd"), function()
            ev.spawns[1] = newSpawn(ev)
            self.spSel = 1
            self:loadSpawn()
            self.dirty.event = true
        end, "primary")
        CQMap.pick = nil
        if CQAdmin.clearPreview then CQAdmin.clearPreview() end
        return
    end
    -- chips
    local addW = CQUI.tw(FS, T("IGUI_CQ_SpAdd")) + 22
    local maxX = x + w - addW - 8
    local cx, rowY = x, y
    local live = adm and adm.events and adm.events[ev.id]
    for i, sp in ipairs(ev.spawns) do
        local nm = sp.name
        if i == self.spSel and self:getE("spName") ~= "" then nm = self:getE("spName") end
        local lbl = (nm ~= "" and nm) or T("IGUI_CQ_SpN", i)
        local cw = math.min(S(170), CQUI.tw(FS, lbl) + 34)
        if cx + cw > maxX and cx > x then cx = x; rowY = rowY + h1 + 5 end
        local sel = i == self.spSel
        local over = self:hit(cx, rowY, cw, h1, function() self:commitSpawn(); self.spSel = i; self:loadSpawn() end, lbl)
        CQUI.rbox(self, cx, rowY, cw, h1, sel and C.accentD or (over and C.panel3 or C.panel2), 1, 6)
        local ss = live and live.spawnState and live.spawnState[sp.id]
        local dot = C.faint
        if live and live.status == "live" then dot = (ss and ss.stopped) and C.faint or C.bad end
        CQUI.rbox(self, cx + 8, rowY + h1 / 2 - 4, 8, 8, dot, 1, 4)
        CQUI.text(self, CQUI.fit(lbl, FS, cw - 30), cx + 22, rowY + 4, sel and C.gold or C.text)
        cx = cx + cw + 6
    end
    CQUI.btn(self, x + w - addW, y, addW, h1, T("IGUI_CQ_SpAdd"), function()
        if #ev.spawns >= 12 then return end
        self:commitSpawn()
        ev.spawns[#ev.spawns + 1] = newSpawn(ev)
        self.spSel = #ev.spawns
        self:loadSpawn()
        self.dirty.event = true
    end, "primary", { disabled = #ev.spawns >= 12 })
    y = rowY + h1 + 12
    local i = CQ.clamp(self.spSel or 1, 1, #ev.spawns)
    local sp = ev.spawns[i]
    -- name + delete
    self:label(T("IGUI_CQ_SpNameL"), x, y)
    y = y + fh() + 4
    local dw = CQUI.tw(FS, T("IGUI_CQ_SpDel")) + 22
    self:place("spName", x, y, w - dw - 10, h1)
    self:confirmBtn("spdel" .. sp.id, x + w - dw, y, dw, h1, T("IGUI_CQ_SpDel"), function()
        table.remove(ev.spawns, i)
        self.spSel = CQ.clamp(i - 1, 1, math.max(1, #ev.spawns))
        self:loadSpawn()
        self.dirty.event = true
    end, "flat")
    y = y + h1 + 10
    -- live status of this spawn point (from the server)
    if live and live.status == "live" and ev.id ~= "" then
        local ss = live.spawnState and live.spawnState[sp.id] or {}
        local stTxt, stCol
        if ss.stopped then
            stTxt, stCol = T("IGUI_CQ_SpStopped_" .. tostring(ss.stopped)), C.faint
        elseif (live.phase or 1) < (sp.fromPhase or 1) then
            stTxt, stCol = T("IGUI_CQ_SpWaitPhase", sp.fromPhase), C.accent
        else
            stTxt, stCol = T("IGUI_CQ_SpRunning"), C.bad
        end
        CQUI.rbox(self, x, y, w, h1 + 8, C.panel, 1, 6)
        CQUI.text(self, stTxt, x + 10, y + 7, stCol)
        local stats = T("IGUI_CQ_SpStats", ss.spawned or 0, ss.kills or 0, ss.alive or 0)
        CQUI.text(self, CQUI.fit(stats, FS, w - S(330)), x + 10 + CQUI.tw(FS, stTxt) + 14, y + 7, C.dim)
        local bw = CQUI.tw(FS, T("IGUI_CQ_SpOff")) + 22
        if ss.stopped then
            local ow = CQUI.tw(FS, T("IGUI_CQ_SpOn")) + 22
            CQUI.btn(self, x + w - ow - 6, y + 4, ow, h1, T("IGUI_CQ_SpOn"), function()
                CQC.send("eventCtl", { id = ev.id, op = "spawn", sid = sp.id, on = true })
            end, "ghost")
        else
            self:confirmBtn("spoff1" .. sp.id, x + w - bw - 6, y + 4, bw, h1, T("IGUI_CQ_SpOff"), function()
                CQC.send("eventCtl", { id = ev.id, op = "spawn", sid = sp.id, on = false })
            end, "danger")
        end
        y = y + h1 + 16
    end
    -- area
    y = y + CQUI.section(self, x, y, w, T("IGUI_CQ_SpArea"))
    local zn = sp.zone
    local p = CQC.player()
    if zn then
        local zx, zy = CQ.zoneCenter(zn)
        local txt = T("IGUI_CQ_ZoneInfo", zx, zy, CQUI.floorText(zn.z or 0), CQ.zoneW(zn) .. "x" .. CQ.zoneH(zn))
        if p then txt = txt .. "   " .. T("IGUI_CQ_ZoneDist", math.floor(CQ.distToZone(zn, p:getX(), p:getY()) + 0.5)) end
        CQUI.text(self, CQUI.fit(txt, FS, w), x, y, C.text)
    else
        CQUI.text(self, T("IGUI_CQ_ZoneNone"), x, y, C.bad)
    end
    y = y + fh() + 6
    local useW = CQUI.tw(FS, T("IGUI_CQ_UseMyPos")) + 44
    local items = zn and { useW, S(120), S(120), S(150) } or { useW }
    local pos, fx, row = {}, x, 0
    for k, iw in ipairs(items) do
        if fx > x and fx + iw > x + w then row = row + 1; fx = x end
        pos[k] = { fx, y + row * (h1 + 6) }
        fx = fx + iw + 6
    end
    CQUI.btn(self, pos[1][1], pos[1][2], useW, h1, T("IGUI_CQ_UseMyPos"), function()
        if not p then return end
        local w0, h0 = 7, 7
        if sp.zone then w0, h0 = CQ.zoneW(sp.zone), CQ.zoneH(sp.zone) end
        sp.zone = CQ.makeZone(p:getX(), p:getY(), p:getZ(), w0, h0)
        self.dirty.event = true
    end, "primary", { icon = "cq_s_reach" })
    if zn then
        CQUI.stepper(self, pos[2][1], pos[2][2], S(120), h1, "W " .. tostring(CQ.zoneW(zn)),
            function() sp.zone = CQ.resizeZone(zn, math.max(1, CQ.zoneW(zn) - 2), CQ.zoneH(zn)); self.dirty.event = true end,
            function() sp.zone = CQ.resizeZone(zn, CQ.zoneW(zn) + 2, CQ.zoneH(zn)); self.dirty.event = true end)
        CQUI.stepper(self, pos[3][1], pos[3][2], S(120), h1, "H " .. tostring(CQ.zoneH(zn)),
            function() sp.zone = CQ.resizeZone(zn, CQ.zoneW(zn), math.max(1, CQ.zoneH(zn) - 2)); self.dirty.event = true end,
            function() sp.zone = CQ.resizeZone(zn, CQ.zoneW(zn), CQ.zoneH(zn) + 2); self.dirty.event = true end)
        CQUI.stepper(self, pos[4][1], pos[4][2], S(150), h1, CQUI.floorText(zn.z or 0),
            function() zn.z = math.max(-32, (zn.z or 0) - 1); self.dirty.event = true end,
            function() zn.z = math.min(31, (zn.z or 0) + 1); self.dirty.event = true end, { tip = T("IGUI_CQ_ZoneFloorTip") })
    end
    y = y + (row + 1) * (h1 + 6)
    CQUI.text(self, T("IGUI_CQ_MapPickTip"), x, y, C.faint)
    y = y + fh() + 10
    preview(sp.zone)
    CQMap.pick = function(wx, wy)
        local w0, h0, zz = 7, 7, (p and math.floor(p:getZ())) or 0
        if sp.zone then w0, h0, zz = CQ.zoneW(sp.zone), CQ.zoneH(sp.zone), sp.zone.z end
        sp.zone = CQ.makeZone(wx, wy, zz, w0, h0)
        self.dirty.event = true
    end
    -- rate
    y = y + CQUI.section(self, x, y, w, T("IGUI_CQ_SpRate"))
    local lw = S(190)
    self:label(T("IGUI_CQ_SpPerMin"), x, y + 4)
    CQUI.stepper(self, x + lw, y, S(160), h1, T("IGUI_CQ_SpPerMinV", sp.perMin),
        function() sp.perMin = math.max(1, sp.perMin - 1); self.dirty.event = true end,
        function() sp.perMin = math.min(60, sp.perMin + 1); self.dirty.event = true end)
    y = y + h1 + 6
    self:label(T("IGUI_CQ_SpMaxAlive"), x, y + 4)
    CQUI.stepper(self, x + lw, y, S(160), h1, tostring(sp.maxAlive),
        function() sp.maxAlive = math.max(1, sp.maxAlive - 5); self.dirty.event = true end,
        function() sp.maxAlive = math.min(200, sp.maxAlive + 5); self.dirty.event = true end, { tip = T("IGUI_CQ_SpMaxAliveTip") })
    y = y + h1 + 6
    if #ev.phases > 1 then
        self:label(T("IGUI_CQ_SpFrom"), x, y + 4)
        CQUI.cycle(self, x + lw, y, S(160), h1, T("IGUI_CQ_PhN", sp.fromPhase or 1), function()
            sp.fromPhase = math.max(1, (sp.fromPhase or 1) - 1); self.dirty.event = true
        end, function()
            sp.fromPhase = math.min(#ev.phases, (sp.fromPhase or 1) + 1); self.dirty.event = true
        end)
        y = y + h1 + 6
    end
    y = y + 6
    -- stop conditions
    y = y + CQUI.section(self, x, y, w, T("IGUI_CQ_SpStopWhen"))
    local mids = eventMissionIds(ev)
    local opts = { "" }
    for _, mid in ipairs(mids) do opts[#opts + 1] = mid end
    local mi = CQ.indexOf(opts, sp.stopMid or "") or 1
    local function mt(mid)
        if mid == "" then return T("IGUI_CQ_PhKeyNone") end
        local m = adm and adm.missions[mid]
        return m and m.title or mid
    end
    self:label(T("IGUI_CQ_SpStopCp"), x, y + 4)
    CQUI.cycle(self, x + lw, y, math.min(S(300), w - lw), h1, CQUI.fit(mt(opts[mi]), FS, S(230)), function()
        mi = mi - 1; if mi < 1 then mi = #opts end; sp.stopMid = opts[mi]; sp.stopStep = 1; self.dirty.event = true
    end, function()
        mi = mi + 1; if mi > #opts then mi = 1 end; sp.stopMid = opts[mi]; sp.stopStep = 1; self.dirty.event = true
    end)
    y = y + h1 + 6
    if (sp.stopMid or "") ~= "" then
        local m = adm and adm.missions[sp.stopMid]
        local n = m and #m.steps or 1
        sp.stopStep = CQ.clamp(sp.stopStep or 1, 1, math.max(1, n))
        local st = m and m.steps[sp.stopStep]
        local lbl = T("IGUI_CQ_SpStepN", sp.stopStep, n) .. "  " .. CQUI.stepLabel(st)
        CQUI.cycle(self, x + lw, y, math.min(S(300), w - lw), h1, CQUI.fit(lbl, FS, S(230)), function()
            sp.stopStep = (sp.stopStep <= 1) and n or (sp.stopStep - 1); self.dirty.event = true
        end, function()
            sp.stopStep = (sp.stopStep >= n) and 1 or (sp.stopStep + 1); self.dirty.event = true
        end, { tip = T("IGUI_CQ_SpStepTip") })
        y = y + h1 + 6
    end
    self:label(T("IGUI_CQ_SpStopKills"), x, y + 4)
    CQUI.stepper(self, x + lw, y, S(160), h1, (sp.stopKills or 0) == 0 and T("IGUI_CQ_PhTimerOff") or tostring(sp.stopKills),
        function() sp.stopKills = math.max(0, (sp.stopKills or 0) - 5); self.dirty.event = true end,
        function() sp.stopKills = math.min(9999, (sp.stopKills or 0) + 5); self.dirty.event = true end, { tip = T("IGUI_CQ_SpKillsTip") })
    y = y + h1 + 8
    CQUI.para(self, T("IGUI_CQ_SpNote"), x, y, w, C.faint)
end

-- ===================================================================== phases 1 > 2 > 3
local function phaseMissionLines(ev, i)
    local adm = CQC.adm
    local function title(mid) local m = adm and adm.missions[mid]; return m and m.title or mid end
    local lines = {}
    local common = {}
    for _, mid in ipairs(ev.missions or {}) do
        if CQ.phaseOf(ev.mph, mid) == i then common[#common + 1] = title(mid) end
    end
    if #common > 0 then lines[#lines + 1] = { who = T("IGUI_CQ_PhEveryone"), list = table.concat(common, ", ") } end
    if ev.roleMode ~= "none" then
        for _, r in ipairs(ev.roles or {}) do
            local l = {}
            for _, mid in ipairs(r.missions or {}) do
                if CQ.phaseOf(r.mph, mid) == i then l[#l + 1] = title(mid) end
            end
            if #l > 0 then lines[#lines + 1] = { who = r.name, list = table.concat(l, ", ") } end
        end
    end
    return lines
end

local function newPhase() return { name = "", all = false, key = "", min = 0, self = false } end

function A:removePhase(ev, i)
    table.remove(ev.phases, i)
    local function shift(map)
        if not map then return end
        for mid, v in pairs(map) do
            local nv = v
            if v > i then nv = v - 1 elseif v == i then nv = math.max(1, i - 1) end
            map[mid] = (nv > 1) and nv or nil
        end
    end
    shift(ev.mph)
    for _, r in ipairs(ev.roles or {}) do shift(r.mph) end
    if #ev.phases < 2 then
        ev.phases = {}
        ev.mph = {}
        for _, r in ipairs(ev.roles or {}) do r.mph = {} end
    end
    self.phSel = CQ.clamp(i - 1, 1, math.max(1, #ev.phases))
    self:loadPhase()
    self.dirty.event = true
end

function A:eventPhases(ev, x, y, w, h)
    local h1 = eh()
    local n = #ev.phases
    if n < 2 then
        local u = CQUI.para(self, T("IGUI_CQ_PhHint"), x, y, w, C.dim)
        y = y + u + 10
        CQUI.btnA(self, x, y, h1 + 4, T("IGUI_CQ_PhEnable"), function()
            ev.phases = { newPhase(), newPhase() }
            self.phSel = 1
            self:loadPhase()
            self.dirty.event = true
        end, "primary")
        return
    end
    -- order mode
    self:label(T("IGUI_CQ_PhModeL"), x, y)
    y = y + fh() + 4
    local mode = ev.phaseMode or "strict"
    local function flip() ev.phaseMode = (ev.phaseMode == "parallel") and "strict" or "parallel"; self.dirty.event = true end
    CQUI.cycle(self, x, y, S(250), h1, T("IGUI_CQ_PhMode_" .. mode), flip, flip)
    local u = CQUI.paraH(T("IGUI_CQ_PhModeD_" .. mode), w - S(262), FS, 3)
    CQUI.para(self, T("IGUI_CQ_PhModeD_" .. mode), x + S(262), y, w - S(262), C.faint, FS, 3)
    y = y + math.max(h1, u) + 12
    -- phase chips  1. > 2. > 3.
    local addW = CQUI.tw(FS, T("IGUI_CQ_PhAdd")) + 22
    local maxX = x + w - addW - 8
    local cx, rowY = x, y
    for i = 1, n do
        local nm = ev.phases[i].name
        if i == self.phSel and self:getE("phName") ~= "" then nm = self:getE("phName") end
        local lbl = tostring(i) .. ". " .. ((nm ~= "" and nm) or T("IGUI_CQ_PhN", i))
        local cw = math.min(S(180), CQUI.tw(FS, lbl) + 24)
        if cx + cw > maxX and cx > x then cx = x; rowY = rowY + h1 + 5 end
        local sel = i == self.phSel
        local over = self:hit(cx, rowY, cw, h1, function() self:commitPhase(); self.phSel = i; self:loadPhase() end, lbl)
        CQUI.rbox(self, cx, rowY, cw, h1, sel and C.accentD or (over and C.panel3 or C.panel2), 1, 6)
        CQUI.textC(self, CQUI.fit(lbl, FS, cw - 12), cx + cw / 2, rowY + 4, sel and C.gold or C.text)
        if i < n then CQUI.textC(self, ">", cx + cw + 6, rowY + 4, C.faint) end
        cx = cx + cw + 12
    end
    CQUI.btn(self, x + w - addW, y, addW, h1, T("IGUI_CQ_PhAdd"), function()
        if #ev.phases >= 10 then return end
        self:commitPhase()
        ev.phases[#ev.phases + 1] = newPhase()
        self.phSel = #ev.phases
        self:loadPhase()
        self.dirty.event = true
    end, "primary", { disabled = n >= 10 })
    y = rowY + h1 + 12
    -- selected phase
    local i = CQ.clamp(self.phSel or 1, 1, n)
    local ph = ev.phases[i]
    self:label(T("IGUI_CQ_PhNameL", i), x, y)
    y = y + fh() + 4
    local dw = CQUI.tw(FS, T("IGUI_CQ_PhDel")) + 22
    self:place("phName", x, y, w - dw - 10, h1)
    self:confirmBtn("phdel" .. tostring(i), x + w - dw, y, dw, h1, T("IGUI_CQ_PhDel"), function() self:removePhase(ev, i) end, "flat")
    y = y + h1 + 12
    if i < n then
        y = y + CQUI.section(self, x, y, w, T("IGUI_CQ_PhWhen", i + 1))
        CQUI.toggle(self, x, y, T("IGUI_CQ_PhAll"), ph.all == true, function() ph.all = not ph.all; self.dirty.event = true end, { tip = T("IGUI_CQ_PhAllTip") })
        y = y + fh() + 10
        CQUI.toggle(self, x, y, T("IGUI_CQ_PhSelf"), ph.self == true, function() ph.self = not ph.self; self.dirty.event = true end, { tip = T("IGUI_CQ_PhSelfTip") })
        y = y + fh() + 10
        -- key mission: one of the missions handed out in this phase
        local opts = { "" }
        for _, mid in ipairs(ev.missions or {}) do
            if CQ.phaseOf(ev.mph, mid) == i and not CQ.indexOf(opts, mid) then opts[#opts + 1] = mid end
        end
        for _, r in ipairs(ev.roles or {}) do
            for _, mid in ipairs(r.missions or {}) do
                if CQ.phaseOf(r.mph, mid) == i and not CQ.indexOf(opts, mid) then opts[#opts + 1] = mid end
            end
        end
        local ki = CQ.indexOf(opts, ph.key or "") or 1
        local adm = CQC.adm
        local function mt(mid)
            if mid == "" then return T("IGUI_CQ_PhKeyNone") end
            local m = adm and adm.missions[mid]
            return m and m.title or mid
        end
        local lw = S(150)
        self:label(T("IGUI_CQ_PhKeyL"), x, y + 4)
        CQUI.cycle(self, x + lw, y, math.min(S(320), w - lw), h1, mt(opts[ki]), function()
            ki = ki - 1; if ki < 1 then ki = #opts end; ph.key = opts[ki]; self.dirty.event = true
        end, function()
            ki = ki + 1; if ki > #opts then ki = 1 end; ph.key = opts[ki]; self.dirty.event = true
        end, { tip = T("IGUI_CQ_PhKeyTip") })
        y = y + h1 + 8
        self:label(T("IGUI_CQ_PhTimerL"), x, y + 4)
        CQUI.stepper(self, x + lw, y, S(170), h1, (ph.min or 0) == 0 and T("IGUI_CQ_PhTimerOff") or CQUI.durMin(ph.min),
            function() ph.min = math.max(0, (ph.min or 0) - 5); self.dirty.event = true end,
            function() ph.min = math.min(1440, (ph.min or 0) + 5); self.dirty.event = true end, { tip = T("IGUI_CQ_PhTimerTip") })
        y = y + h1 + 8
        y = y + CQUI.para(self, T("IGUI_CQ_PhAdminNote"), x, y, w, C.faint) + 10
    else
        y = y + CQUI.para(self, T("IGUI_CQ_PhLast"), x, y, w, C.faint) + 10
    end
    -- the whole plan: who does what in each phase
    y = y + CQUI.section(self, x, y, w, T("IGUI_CQ_PhPlan"))
    local whoW = S(130)
    for p = 1, n do
        local nm = ev.phases[p].name
        CQUI.text(self, T("IGUI_CQ_PhN", p) .. ((nm ~= "" and ("  " .. nm)) or ""), x, y, p == i and C.gold or C.text)
        y = y + fh() + 3
        local lines = phaseMissionLines(ev, p)
        if #lines == 0 then
            CQUI.text(self, T("IGUI_CQ_PhEmpty"), x + 14, y, C.faint)
            y = y + fh() + 3
        end
        for _, l in ipairs(lines) do
            CQUI.text(self, CQUI.fit(l.who, FS, whoW - 8), x + 14, y, C.dim)
            local uu = CQUI.para(self, l.list, x + 14 + whoW, y, w - 14 - whoW, C.text)
            y = y + math.max(fh(), uu) + 3
        end
        y = y + 6
    end
end

function A:eventPen(ev, x, y, w, h)
    local h1 = eh()
    local pen = ev.pen
    CQUI.toggle(self, x, y, T("IGUI_CQ_PenOn"), pen.on ~= false, function() pen.on = not (pen.on ~= false); self.dirty.event = true end)
    y = y + fh() + 12
    self:label(T("IGUI_CQ_PenMult"), x, y)
    self:label(T("IGUI_CQ_PenDays"), x + S(190), y)
    self:label(T("IGUI_CQ_PenMinCp"), x + S(380), y)
    y = y + fh() + 4
    CQUI.stepper(self, x, y, S(170), h1, "EXP x" .. CQ.fmt(pen.mult, 2),
        function() pen.mult = math.max(0.1, CQ.num(pen.mult, 0.5) - 0.1); self.dirty.event = true end,
        function() pen.mult = math.min(0.9, CQ.num(pen.mult, 0.5) + 0.1); self.dirty.event = true end)
    CQUI.stepper(self, x + S(190), y, S(170), h1, T("IGUI_CQ_DaysN", CQ.fmt(pen.days, 1)),
        function() pen.days = math.max(0.5, CQ.num(pen.days, 3) - 0.5); self.dirty.event = true end,
        function() pen.days = math.min(14, CQ.num(pen.days, 3) + 0.5); self.dirty.event = true end)
    CQUI.stepper(self, x + S(380), y, S(150), h1, tostring(pen.minCp or 1),
        function() pen.minCp = math.max(0, (pen.minCp or 1) - 1); self.dirty.event = true end,
        function() pen.minCp = math.min(20, (pen.minCp or 1) + 1); self.dirty.event = true end)
    y = y + h1 + 12
    local u = CQUI.para(self, T("IGUI_CQ_PenExplain", pen.minCp or 1, "x" .. CQ.fmt(pen.mult, 2), CQ.fmt(pen.days, 1)), x, y, w, C.text)
    y = y + u + 10
    local live = ev.id ~= "" and CQC.adm.events[ev.id]
    if live and live.status == "done" then
        local res = live.results or {}
        CQUI.text(self, T("IGUI_CQ_PenResult", res.parts or 0, res.penalized or 0), x, y, C.dim)
        y = y + fh() + 8
        if (res.penalized or 0) > 0 then
            local bw = CQUI.tw(FS, T("IGUI_CQ_PenUndo")) + 22
            self:confirmBtn("nopen" .. ev.id, x, y, bw, h1, T("IGUI_CQ_PenUndo"), function() CQC.send("eventCtl", { id = ev.id, op = "nopen" }) end, "good")
        end
    end
end

-- ===================================================================== sample event (Lord Crumble finale)
function CQAdmin.makeSample()
    local p = CQC.player()
    if not p then return end
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local function zone(dx, dy, s) return CQ.makeZone(x + dx, y + dy, z, s, s) end
    local missions = {
        { title = T("IGUI_CQ_S_M1"), story = T("IGUI_CQ_S_M1s"), assign = "role", team = true,
          steps = { { t = "deliver", label = T("IGUI_CQ_S_M1a"), item = "Base.Bandage", n = 30, zone = zone(0, 0, 5) } },
          rewardText = T("IGUI_CQ_S_Seal") },
        { title = T("IGUI_CQ_S_M2"), story = T("IGUI_CQ_S_M2s"), assign = "role", team = true,
          steps = { { t = "kill", label = T("IGUI_CQ_S_M2a"), n = 50 }, { t = "reach", label = T("IGUI_CQ_S_M2b"), zone = zone(0, 0, 5) } },
          rewardText = T("IGUI_CQ_S_Seal") },
        { title = T("IGUI_CQ_S_M3"), story = T("IGUI_CQ_S_M3s"), assign = "role", team = false,
          steps = { { t = "reach", label = T("IGUI_CQ_S_M3a"), zone = zone(8, 0, 3) } },
          rewardText = T("IGUI_CQ_S_Seal") },
        { title = T("IGUI_CQ_S_M4"), story = T("IGUI_CQ_S_M4s"), assign = "role", team = false,
          steps = { { t = "deliver", label = T("IGUI_CQ_S_M4a"), item = "Base.Doll", n = 1, zone = zone(0, 0, 3) } },
          rewardText = T("IGUI_CQ_S_Seal") },
        { title = T("IGUI_CQ_S_M5"), story = T("IGUI_CQ_S_M5s"), assign = "role", team = false,
          steps = { { t = "others", label = T("IGUI_CQ_S_M5a"), n = 3 } },
          rewardText = T("IGUI_CQ_S_Special") },
        { title = T("IGUI_CQ_S_M6"), story = T("IGUI_CQ_S_M6s"), assign = "role", team = true,
          steps = { { t = "hold", label = T("IGUI_CQ_S_M6a"), sec = 180, zone = zone(0, 0, 9) } },
          rewardText = T("IGUI_CQ_S_Seal") },
    }
    local event = {
        title = T("IGUI_CQ_S_Ev"), desc = T("IGUI_CQ_S_EvD"), start = nextSaturday(), dur = 120, roleMode = "random",
        kit = { { t = "Base.WaterBottle", n = 1 } },
        roles = {
            { id = "r1", name = T("IGUI_CQ_S_R1"), desc = T("IGUI_CQ_S_R1d"), missions = { "#1" }, kit = {}, max = 0 },
            { id = "r2", name = T("IGUI_CQ_S_R2"), desc = T("IGUI_CQ_S_R2d"), missions = { "#2" }, kit = {}, max = 0 },
            { id = "r3", name = T("IGUI_CQ_S_R3"), desc = T("IGUI_CQ_S_R3d"), missions = { "#3" }, kit = {}, max = 2 },
            { id = "r4", name = T("IGUI_CQ_S_R4"), desc = T("IGUI_CQ_S_R4d"), missions = { "#4" }, kit = { { t = "Base.Doll", n = 1 } }, max = 1 },
            { id = "r5", name = T("IGUI_CQ_S_R5"), desc = T("IGUI_CQ_S_R5d"), missions = { "#5" }, kit = {}, max = 1, secret = true },
        },
        missions = { "#6" },
        lateJoin = true,
        pen = { on = true, mult = 0.5, days = 3, minCp = 1 },
    }
    CQC.send("bundle", { missions = missions, event = event })
end

-- refresh / cleanup hooks
local baseLeave = A.leavePage
function A:leavePage()
    if self.page == "events" then self:commitRole() end
    clearPreview()
    baseLeave(self)
end

local baseClosed = A.onClosed
function A:onClosed()
    clearPreview()
    baseClosed(self)
end
