-- Cookie Helper : recipe browser + craft panel (used by Workshop and Vehicle Zone windows)
-- Left: search, filter chips, recipes with a live "can I make it" line (checked lazily: only rows on
-- screen, two per frame). Right: the selected recipe - what it needs and where it is, workstation,
-- skill, quantity, Link and the plan, then queue / craft / "what is missing".
if isServer() then return end

require "ISUI/ISPanel"
require "CookieHelper/CH_Client"
require "CookieHelper/CH_Craft"
require "CookieHelper/CH_Queue"
require "CookieHelper/CH_Missing"

CHelp.RecipeBox = CHelp.RecipeBox or {}
local RB = CHelp.RecipeBox
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local Scan = CHelp.Scan
local Craft = CHelp.Craft
local t = CHelp.t
local floor = math.floor

local P = ISPanel:derive("CHelpRecipeBox")
RB.Panel = P

RB.recent = RB.recent or {}       -- recipes used this session (shown first)

function RB.remember(r)
    for i, x in ipairs(RB.recent) do if x == r then table.remove(RB.recent, i) break end end
    table.insert(RB.recent, 1, r)
    while #RB.recent > 30 do table.remove(RB.recent) end
end

-- opts: { zone = fn() -> zone, entries = fn(), stations = fn(), canCraft = fn() -> bool, why = text key, listW }
function RB.create(parent, x, y, w, h, opts)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, P)
    P.__index = P
    o.opts = opts or {}
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false
    o:initialise()
    o:instantiate()
    parent:addChild(o)
    return o
end

function P:createChildren()
    ISPanel.createChildren(self)
    self.recipes = {}
    self.status = {}
    self.queue, self.queued = {}, {}
    self.gen = 0
    self.qty = 1
    self.link = true
    self.filter = "all"
    self.counts = {}
    self.benchLogics = {}
    local lw = self.opts.listW or 360
    self.lw = lw
    self.search = UI.entry(self, 0, 0, lw, "")
    self.search:setPlaceholderText(t("SearchRecipes"))
    self.search.onTextChange = function() self.searchDirty = CHelp.nowMs() end
    self.chips = UI.tabs(self, 0, UI.BTN_H + 8, {
        { id = "all", label = t("F_All") }, { id = "can", label = t("F_Can") },
        { id = "station", label = t("F_Station") }, { id = "miss", label = t("F_Miss") },
    }, "all", self, P.onFilter)
    local ly = UI.BTN_H + 8 + self.chips.height + 10
    self.list = UI.makeList(self, 0, ly, lw, self.height - ly, UI.HS * 2 + 20, self, P.drawRow, P.onPick)

    -- detail widgets
    local dx = lw + 16
    self.dx, self.dw = dx, self.width - dx
    local s = UI.BTN_H
    self.minus = UI.button(self, 0, 0, s, "", self, P.onMinus, "sec")
    self.minus:setIcon("minus")
    self.plus = UI.button(self, 0, 0, s, "", self, P.onPlus, "sec")
    self.plus:setIcon("plus")
    self.maxBtn = UI.button(self, 0, 0, 110, t("PutMax"), self, P.onMax, "ghost")
    self.linkBtn = UI.button(self, 0, 0, self.dw - 36, "", self, P.onLink, "sec", UI.HS * 2 + 22)
    self.linkBtn.drawFn = function(b, w, h, hov) self:drawLinkCard(b, w, h, hov) end
    self.queueBtn = UI.button(self, 0, 0, 160, t("AddQueue"), self, P.onQueue, "sec", UI.BTN_H + 6)
    self.queueBtn:setIcon("list")
    self.craftBtn = UI.button(self, 0, 0, 200, "", self, P.onCraft, "pri", UI.BTN_H + 6)
    self.missBtn = UI.button(self, 0, 0, 200, t("SeeMissing"), self, P.onMissing, "bad", UI.BTN_H + 6)
    self:layoutDetail()
end

-- ------------------------------------------------------------------ data in
function P:setRecipes(list)
    local keep = self.sel
    self.recipes = list or {}
    self:refill()
    local found = false
    for i, it in ipairs(self.list.items) do
        if it.item == keep then self.list.selected = i found = true end
    end
    if not found then
        self.list.selected = (#self.list.items > 0) and 1 or 0
        local it = self.list.items[self.list.selected]
        self:select(it and it.item or nil)
    end
end

function P:refill()
    self.list:clear()
    if self.filter ~= "all" then
        -- hidden rows are never drawn, so check them here (the list refills once they are known)
        for i, r in ipairs(self.recipes) do
            if i > 80 then break end
            self:need(r)
        end
    end
    for _, r in ipairs(self.recipes) do
        if self:passes(r) then self.list:addItem(Craft.label(r), r) end
    end
end

function P:passes(r)
    if self.filter == "all" then return true end
    local st = self.status[r]
    if not st then return self.filter ~= "can" end
    if self.filter == "can" then return st.can end
    if self.filter == "miss" then return not st.can end
    if self.filter == "station" then
        local okS, surf = pcall(function() return r:isAnySurfaceCraft() end)
        return st.station ~= nil or (okS and surf)
    end
    return true
end

-- new stock -> cached answers become stale (still shown until rechecked)
function P:invalidate(containers, counts, stations)
    self.containers = containers
    self.counts = counts or {}
    self.stations = stations
    self.logic = nil
    self.benchLogics = {}
    self.gen = self.gen + 1
    self.queue, self.queued = {}, {}
    -- stock changes come in bursts while crafting: redo the (heavy) detail plan once it settles
    if self.detail then self.detailStale = CHelp.nowMs() else self.detail = nil end
end

function P:need(r)
    local st = self.status[r]
    if (not st or st.gen ~= self.gen) and not self.queued[r] then
        self.queued[r] = true
        self.queue[#self.queue + 1] = r
    end
end

function P:benchLogic(station)
    local lg = self.benchLogics[station.bench]
    if not lg then
        local p = C.player()
        lg = Craft.makeLogic(p, station.bench, station.obj)
        lg:setContainers(self.containers)
        self.benchLogics[station.bench] = lg
    end
    return lg
end

function P:pump(n)
    if not self.containers or #self.queue == 0 then return end
    local p = C.player()
    if not p then return end
    if not self.logic then
        self.logic = Craft.makeLogic(p, nil, nil)
        self.logic:setContainers(self.containers)
    end
    for _ = 1, n or 2 do
        local r = table.remove(self.queue, 1)
        if not r then break end
        self.queued[r] = nil
        local st = Craft.statusOne(self.logic, r, p, self.stations, function(s) return self:benchLogic(s) end)
        st.gen = self.gen
        self.status[r] = st
        self.pumped = true
    end
end

function P:select(r)
    self.sel = r
    self.detail = nil
    self:layoutDetail()
end

-- ------------------------------------------------------------------ detail (computed on change)
function P:ctx()
    return { p = C.player(), counts = self.counts, stations = self.stations, link = self.link }
end

function P:compute()
    local r = self.sel
    if not r or not self.containers then return nil end
    local p = C.player()
    local d = { r = r }
    local station = Scan.benchFor(self.stations, r)
    local okB, needsBench = pcall(function() return r:requiresSpecificWorkstation() end)
    local okS, surf = pcall(function() return r:isAnySurfaceCraft() end)
    d.needsBench = okB and needsBench
    d.station = station
    d.surface = okS and surf
    local logic = Craft.newLogic(p, self.containers, r, station)
    d.rows = Craft.requirements(r, self.qty, self.counts, logic)
    local ctx = self:ctx()
    d.plan = Craft.plan(ctx, r, self.qty)
    d.max = Craft.maxPlan(ctx, r, 50)
    d.learned = true
    d.skills = true
    pcall(function()
        d.learned = (not r:needToBeLearn()) or r:hasPlayerLearned(p)
        d.skills = r:characterHasRequiredSkills(p)
    end)
    d.skillText = ""
    pcall(function()
        local parts = {}
        for i = 0, r:getRequiredSkillCount() - 1 do
            local rs = r:getRequiredSkill(i)
            parts[#parts + 1] = rs:getPerk():getName() .. " " .. rs:getLevel() .. " (" .. p:getPerkLevel(rs:getPerk()) .. ")"
        end
        d.skillText = table.concat(parts, ", ")
    end)
    d.outPer = Craft.outPer(r)
    d.needsLight = false
    pcall(function() d.needsLight = not r:canBeDoneInDark() end)
    d.dark = Craft.tooDark(r, p)
    if d.surface and not d.needsBench and (not self.stations or #self.stations.surfaces == 0) then
        local okF, f = pcall(function() return ISEntityUI.FindCraftSurface(p, 2) end)
        d.noTable = not (okF and f)
    end
    d.refill = false
    for _, rq in ipairs(d.rows) do
        if rq.uses and not rq.ok then
            for _, ft in ipairs(rq.fts) do
                if ft == "Base.BlowTorch" then
                    d.refill = Craft.refillCovers(logic, r, p)
                    rq.refill = d.refill
                end
            end
        end
    end
    d.can = d.plan.ok and d.learned and d.skills and ((not d.needsBench) or station ~= nil) and not d.noTable
    return d
end

-- ------------------------------------------------------------------ list rows
function P.drawRow(self, list, r, x, y, w, h, hover, sel)
    self:need(r)
    local st = self.status[r]
    local s = h - 16
    local out = Craft.mainOutput(r)
    T.slot(list, x + 10, y + 8, s, Craft.icon(r) or (out and Scan.itemTex(out)), nil)
    local tx = x + 10 + s + 12
    local cat = Craft.category(r)
    local cw = math.min(90, T.tw(cat))
    T.text(list, T.fit(Craft.label(r), w - (tx - x) - cw - 18), tx, y + floor(h / 2) - UI.HS - 1, K.text)
    T.textR(list, T.fit(cat, 90), x + w - 10, y + floor(h / 2) - UI.HS - 1, K.text3)
    local line, col = t("St_Checking"), K.text3
    if st then
        if not st.learned then line, col = t("St_NotLearned"), K.bad
        elseif not st.skills then line, col = t("St_NoSkill"), K.bad
        elseif st.needsBench and not st.station then line, col = t("St_NeedBench"), K.bad
        elseif st.noTable then line, col = t("St_NeedTable"), K.bad
        elseif st.can and st.dark then line, col = t("St_Dark"), K.warn
        elseif st.can and st.refill then line, col = t("St_Refill"), K.warn
        elseif st.can then line, col = t("St_Can", st.max), K.acc
        else line, col = t("St_Missing"), K.warn end
    end
    T.text(list, T.fit(line, w - (tx - x) - 10), tx, y + floor(h / 2) + 1, col)
end

function P:onPick(r)
    self:select(r)
end

function P:onFilter(id)
    self.filter = id
    self:refill()
    self.list.selected = 0
    for i, it in ipairs(self.list.items) do if it.item == self.sel then self.list.selected = i end end
end

-- ------------------------------------------------------------------ detail layout + drawing
function P:layoutDetail()
    local has = self.sel ~= nil
    for _, b in ipairs({ self.minus, self.plus, self.maxBtn, self.linkBtn, self.queueBtn, self.craftBtn, self.missBtn }) do
        b:setVisible(has)
    end
    if not has then return end
    local x0 = self.dx + 18
    local w = self.dw - 36
    local by = self.height - 18 - self.craftBtn.height
    local half = floor((w - 8) / 2)
    self.queueBtn:setX(x0) self.queueBtn:setY(by) self.queueBtn:setWidth(half)
    self.craftBtn:setX(x0 + half + 8) self.craftBtn:setY(by) self.craftBtn:setWidth(w - half - 8)
    self.missBtn:setX(x0 + half + 8) self.missBtn:setY(by) self.missBtn:setWidth(w - half - 8)
    local planH = self.planH or 0
    local ly = by - 12 - planH - self.linkBtn.height
    self.linkBtn:setX(x0) self.linkBtn:setY(ly) self.linkBtn:setWidth(w)
    local qy = ly - 12 - UI.BTN_H
    self.qtyY = qy
    local lx = x0 + T.tw(t("Qty")) + 14
    self.minus:setX(lx) self.minus:setY(qy)
    self.qtyX = lx + UI.BTN_H
    self.plus:setX(self.qtyX + 54) self.plus:setY(qy)
    self.maxBtn:setX(self.plus:getX() + UI.BTN_H + 10) self.maxBtn:setY(qy)
    self.reqBottom = qy - 12
end

function P:drawLinkCard(b, w, h, hov)
    T.rrect(b, 0, 0, w, h, UI.RC, self.link and K.accD or (hov and K.surf3 or K.surf2))
    UI.drawSwitch(b, 12, floor((h - 22) / 2), self.link)
    local tx = 64
    T.icon(b, "link", tx, floor(h / 2) - UI.HS - 1, UI.HS, self.link and K.acc or K.text2)
    T.text(b, t("LinkTitle"), tx + UI.HS + 6, floor(h / 2) - UI.HS - 2, K.text)
    T.text(b, T.fit(t("LinkSub"), w - tx - 70), tx, floor(h / 2) + 2, K.text2)
    T.textR(b, self.link and t("On") or t("Off"), w - 14, floor((h - UI.HS) / 2), self.link and K.acc or K.text2)
end

function P:prerender()
    -- refresh the search at most a few times a second
    if self.searchDirty and CHelp.nowMs() - self.searchDirty > 250 then
        self.searchDirty = nil
        if self.onSearch then self.onSearch(self.search:getInternalText() or "") end
    end
    self:pump(2)
    if self.filter ~= "all" and self.pumped and #self.queue == 0 then
        self.pumped = false
        self:onFilter(self.filter)
    end
    -- detail panel background
    T.rrect(self, self.dx, 0, self.dw, self.height, 16, K.surf)
    if not self.sel then
        T.textC(self, t("PickRecipe"), self.dx + self.dw / 2, floor(self.height / 2) - UI.HS, K.text3)
        return
    end
    if self.detailStale and CHelp.nowMs() - self.detailStale > 1200 then
        self.detailStale = nil
        self.detail = nil
    end
    if not self.detail then
        local ok, d = pcall(function() return self:compute() end)
        self.detail = ok and d or nil
        if not ok then CHelp.log("recipe detail failed: " .. tostring(d)) end
        local ph = 0
        if self.detail and self.link and #self.detail.plan.steps > 1 then
            ph = 16 + UI.HS + 4 + #self.detail.plan.steps * (UI.HS + 3)
        end
        if ph ~= (self.planH or 0) then
            self.planH = ph
            self:layoutDetail()
        end
    end
    local d = self.detail
    if not d then return end
    local x0 = self.dx + 18
    local w = self.dw - 36
    local y = 16
    -- header
    local s = 56
    local out = Craft.mainOutput(d.r)
    T.slot(self, x0, y, s, Craft.icon(d.r) or (out and Scan.itemTex(out)), nil)
    local bigW = math.max(T.tw(t("MaxTimes")), T.tw(tostring(d.max), T.FL) + T.tw(t("Times")) + 6)
    T.text(self, T.fit(Craft.label(d.r), w - s - bigW - 30, T.FM), x0 + s + 14, y + 4, K.text, T.FM)
    T.text(self, T.fit(t("OutPerCat", d.outPer, Craft.category(d.r)), w - s - bigW - 30), x0 + s + 14, y + 8 + UI.HM, K.text3)
    T.textR(self, t("MaxTimes"), x0 + w, y + 2, K.text3)
    local nmx = x0 + w - T.tw(t("Times")) - 4
    T.textR(self, t("Times"), x0 + w, y + 4 + UI.HS + UI.HL - UI.HS - 2, K.text3)
    T.textR(self, tostring(d.max), nmx, y + 4 + UI.HS, d.max > 0 and K.acc or K.bad, T.FL)
    y = y + s + 10
    -- station line
    local stText, stCol, stPx = t("InHand"), K.text2, nil
    if d.needsBench then
        if d.station then stText, stCol, stPx = t("BenchHere", d.station.name), K.acc, "anvil"
        else stText, stCol, stPx = t("BenchMissing"), K.bad, "anvil" end
    elseif d.surface then
        local n = self.stations and #self.stations.surfaces or 0
        if n > 0 then stText, stCol, stPx = t("SurfaceUse", n), K.acc, "table"
        elseif d.noTable then stText, stCol, stPx = t("TableMissing"), K.bad, "table"
        else stText, stCol, stPx = t("SurfaceNear"), K.warn, "table" end
    end
    if stPx then T.slot(self, x0, y, 24, nil, nil) T.px(self, stPx, x0 + 4, y + 4, 16) end
    T.text(self, T.fit(stText, w - 34), x0 + 32, y + floor((24 - UI.HS) / 2), stCol)
    y = y + 32
    if d.needsLight then
        T.slot(self, x0, y, 24, nil, nil)
        T.icon(self, d.dark and "warn" or "check", x0 + 5, y + 5, 14, d.dark and K.bad or K.acc)
        T.text(self, T.fit(d.dark and t("LightDark") or t("LightOk"), w - 34), x0 + 32, y + floor((24 - UI.HS) / 2), d.dark and K.bad or K.text2)
        y = y + 32
    end
    -- requirements
    T.text(self, t("NeedFor", self.qty), x0, y, K.text2)
    y = y + UI.HS + 6
    local rowH = 50
    local room = (self.reqBottom or (self.height - 200)) - y - (UI.HS + 10)
    local maxRows = math.max(1, floor(room / rowH))
    for i, rq in ipairs(d.rows) do
        if i > maxRows then
            T.text(self, t("MoreRows", #d.rows - maxRows), x0, y, K.text3)
            y = y + UI.HS + 4
            break
        end
        local kind = rq.ok and "ok" or (rq.refill and "link" or "bad")
        local fix, fixCol = nil, nil
        if not rq.ok and not rq.refill then
            for _, st in ipairs(d.plan.steps) do
                if st.recipe ~= d.r then
                    local o = Craft.mainOutput(st.recipe)
                    for _, ft in ipairs(rq.fts) do if ft == o then fix = st end end
                end
            end
            if fix and self.link then kind = "link" end
        end
        T.slot(self, x0, y + 4, 40, rq.tex, nil)
        T.badge(self, x0 + 40 - 14, y + 4 + 40 - 14, 18, kind)
        local tx = x0 + 54
        local right = rq.uses and (rq.ok and t("UsesOk") or (rq.refill and t("UsesRefill") or t("UsesLow"))) or (rq.have .. "/" .. rq.need)
        local rc = kind == "ok" and K.acc or (kind == "link" and K.warn or K.bad)
        T.textR(self, right, x0 + w, y + 6, rc)
        T.text(self, T.fit(rq.name .. (rq.tool and (" " .. t("ToolTag")) or ""), w - 60 - T.tw(right) - 10), tx, y + 6, K.text)
        local sub, sc = (#rq.boxes > 0) and table.concat(rq.boxes, ", ") or t("NotInZone"), K.text3
        if rq.refill then
            sub, sc = t("TorchWillRefill"), K.warn
        elseif not rq.ok then
            if fix then
                sub = self.link and t("LinkWillMake", Craft.label(fix.recipe), fix.qty) or t("LinkCould", Craft.label(fix.recipe))
                sc = K.warn
            elseif rq.tool then sub, sc = t("NoToolMake"), K.bad
            else sub, sc = t("NoRecipeHere"), K.bad end
        end
        T.text(self, T.fit(sub, w - 60), tx, y + 8 + UI.HS, sc)
        if i < #d.rows and i < maxRows then T.rect(self, x0, y + rowH - 1, w, 1, K.text, 0.06) end
        y = y + rowH
    end
    -- skill / learned chips
    local cy = y + 4
    local cx = x0
    if d.skillText ~= "" then
        cx = cx + T.pill(self, cx, cy, T.fit(t("SkillChip", d.skillText), w / 2), d.skills and K.acc or K.bad, K.surf2) + 6
    end
    T.pill(self, cx, cy, d.learned and t("Learned") or t("NotLearned"), d.learned and K.acc or K.bad, K.surf2)
    -- quantity row
    if self.qtyY then
        T.text(self, t("Qty"), x0, self.qtyY + floor((UI.BTN_H - UI.HS) / 2), K.text)
        T.rrect(self, self.qtyX, self.qtyY, 54, UI.BTN_H, 8, K.bar)
        T.textC(self, tostring(self.qty), self.qtyX + 27, self.qtyY + floor((UI.BTN_H - UI.HM) / 2), K.text, T.FM)
        local info, ic
        if not d.learned then info, ic = t("St_NotLearned"), K.bad
        elseif d.needsBench and not d.station then info, ic = t("BenchMissing"), K.bad
        elseif d.noTable then info, ic = t("St_NeedTable"), K.bad
        elseif d.can then info, ic = t("EnoughGives", self.qty * d.outPer), K.acc
        elseif d.max > 0 then info, ic = t("OnlyN", d.max), K.warn
        else info, ic = t("CantYet"), K.bad end
        local ix = self.maxBtn:getX() + self.maxBtn.width + 10
        T.textR(self, T.fit(info, x0 + w - ix), x0 + w, self.qtyY + floor((UI.BTN_H - UI.HS) / 2), ic)
    end
    -- plan box
    if (self.planH or 0) > 0 then
        local py = self.linkBtn:getY() + self.linkBtn.height + 10
        T.rrect(self, x0, py, w, self.planH - 4, UI.RC, K.bar)
        T.text(self, t("PlanTitle"), x0 + 12, py + 8, K.acc)
        for i, st in ipairs(d.plan.steps) do
            local ly = py + 12 + UI.HS + (i - 1) * (UI.HS + 3)
            T.text(self, tostring(i), x0 + 12, ly, K.text3)
            T.text(self, T.fit(t("Q_StepLine", Craft.label(st.recipe), st.qty), w - 40), x0 + 30, ly, K.text)
        end
    end
    -- buttons
    self.craftBtn:setVisible(d.can)
    self.missBtn:setVisible(not d.can)
    self.craftBtn:setTitle(t("CraftNow", self.qty))
end

-- ------------------------------------------------------------------ actions
function P:setQty(q)
    q = math.max(1, math.min(50, floor(q)))
    if q ~= self.qty then
        self.qty = q
        self.detail = nil
    end
end

function P:onMinus() self:setQty(self.qty - 1) end
function P:onPlus() self:setQty(self.qty + 1) end
function P:onMax()
    if self.detail and self.detail.max > 0 then self:setQty(self.detail.max) end
end

function P:onLink()
    self.link = not self.link
    self.detail = nil
end

function P:zone()
    return self.opts.zone and self.opts.zone() or nil
end

function P:ready()
    if self.opts.canCraft and not self.opts.canCraft() then
        UI.toast(t(self.opts.why or "Msg_StandInZone"), false)
        return false
    end
    return true
end

function P:onQueue()
    if not self.sel or not self:zone() then return end
    RB.remember(self.sel)
    CHelp.Queue.add({ recipe = self.sel, qty = self.qty, link = self.link, zone = self:zone() })
end

function P:onCraft()
    if not self.sel or not self:zone() then return end
    if not self:ready() then return end
    RB.remember(self.sel)
    if CHelp.Queue.running then UI.toast(t("Msg_AfterCurrent"), true) end
    CHelp.Queue.add({ recipe = self.sel, qty = self.qty, link = self.link, zone = self:zone() })
end

function P:onMissing()
    if not self.sel or not self:zone() then return end
    CHelp.Missing.open({ recipe = self.sel, qty = self.qty, zone = self:zone(), link = self.link })
end

function P:selected()
    return self.sel
end
