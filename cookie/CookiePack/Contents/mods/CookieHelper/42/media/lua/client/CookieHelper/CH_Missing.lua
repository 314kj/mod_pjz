-- Cookie Helper : "can't craft this - here is everything that is missing"
-- One snapshot when opened: ingredients (with what Link could make), workstation / skill / recipe,
-- boxes that cannot be reached and whether it fits in the bag.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_Craft"
require "CookieHelper/CH_Queue"

CHelp.Missing = CHelp.Missing or {}
local M = CHelp.Missing
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local Scan = CHelp.Scan
local Craft = CHelp.Craft
local t = CHelp.t
local floor = math.floor

local W = UI.Window:derive("CHelpMissing")

-- ctx = { recipe, qty, zone, link }
local function analyse(ctx)
    local p = C.player()
    local entries = Scan.containers(ctx.zone, ctx.zone.z, true)
    local stations = Scan.stations(ctx.zone, ctx.zone.z)
    local counts = Craft.countAll(p, entries)
    local cont = Craft.planContainers(p, entries)
    local r = ctx.recipe
    local station = Scan.benchFor(stations, r)
    local logic = Craft.newLogic(p, cont, r, station)
    local pctx = { p = p, counts = counts, stations = stations, link = false }
    local maxNow = Craft.maxPlan(pctx, r, 50)
    pctx.link = true
    local maxLink = Craft.maxPlan(pctx, r, 50)
    local planLink = Craft.plan(pctx, r, ctx.qty)
    -- the whole safehouse: everything in every box of the house (all floors)
    local house = ctx.house or CHelp.shAt(ctx.zone.x1, ctx.zone.y1)
    local maxHouse = 0
    if house then
        local hEntries = CHelp.Queue.zoneFns(ctx.zone, house)()
        local hctx = { p = p, counts = Craft.countAll(p, hEntries), stations = stations, link = true }
        maxHouse = Craft.maxPlan(hctx, r, 50)
    end

    local refill = nil
    local rows = {}
    for _, rq in ipairs(Craft.requirements(r, ctx.qty, counts, logic)) do
        local row = { name = rq.name .. (rq.tool and (" " .. t("ToolTag")) or ""), tex = rq.tex, kind = rq.ok and "ok" or "bad" }
        local torch = false
        for _, ft in ipairs(rq.fts) do if ft == "Base.BlowTorch" then torch = true end end
        if rq.uses and not rq.ok and torch then
            if refill == nil then refill = Craft.refillCovers(logic, r, p) end
            rq.refill = refill
        end
        if rq.uses then
            row.right = rq.ok and t("UsesOk") or (rq.refill and t("UsesRefill") or t("UsesLow"))
        else
            row.right = rq.have .. "/" .. rq.need .. (rq.ok and "" or ("  ·  " .. t("ShortN", rq.need - rq.have)))
        end
        row.lines = {}
        if rq.refill then
            row.kind = "link"
            row.lines[#row.lines + 1] = { s = t("TorchWillRefill"), c = K.warn }
        elseif rq.ok then
            if #rq.boxes > 0 then row.lines[#row.lines + 1] = { s = table.concat(rq.boxes, ", "), c = K.text3 } end
        else
            -- what Link would do about it
            local made = nil
            for _, s in ipairs(planLink.steps) do
                if s.recipe ~= r then
                    local out = Craft.mainOutput(s.recipe)
                    for _, ft in ipairs(rq.fts) do if ft == out then made = s end end
                end
            end
            local stillShort = false
            for _, m in ipairs(planLink.missing) do
                for _, ft in ipairs(m.fts) do if ft == rq.ft then stillShort = m.short end end
            end
            if made and not stillShort then
                row.kind = "link"
                row.lines[#row.lines + 1] = { s = t("LinkWillMake", Craft.label(made.recipe), made.qty), c = K.warn }
            elseif rq.tool then
                row.lines[#row.lines + 1] = { s = t("NoToolMake"), c = K.bad }
            else
                local any = #Craft.recipesFor(rq.ft or "") > 0
                row.lines[#row.lines + 1] = { s = any and t("CantMakeHere") or t("NoRecipeHere"), c = K.bad }
            end
        end
        rows[#rows + 1] = row
    end

    -- station / skill / recipe
    local req = {}
    local okB, needsBench = pcall(function() return r:requiresSpecificWorkstation() end)
    if okB and needsBench then
        if station then
            req[#req + 1] = { name = t("StationHere", station.name, station.x - ctx.zone.x1, station.y - ctx.zone.y1), kind = "ok", px = "anvil" }
        else
            req[#req + 1] = { name = t("StationMissing"), kind = "bad", px = "anvil" }
        end
    end
    local okS, surf = pcall(function() return r:isAnySurfaceCraft() end)
    if okS and surf and not (okB and needsBench) then
        local n = #stations.surfaces
        local near = false
        if n == 0 then
            local okF, f = pcall(function() return ISEntityUI.FindCraftSurface(p, 2) end)
            near = okF and f ~= nil
        end
        local name = (n > 0) and t("SurfaceHere", n) or (near and t("SurfaceNearOk") or t("TableMissing"))
        req[#req + 1] = { name = name, kind = (n > 0 or near) and "ok" or "bad", px = "table",
            lines = (n == 0 and not near) and { { s = t("TableHint"), c = K.text3 } } or nil }
    end
    local needsLight = false
    pcall(function() needsLight = not r:canBeDoneInDark() end)
    if needsLight then
        local dark = Craft.tooDark(r, p)
        req[#req + 1] = { name = dark and t("LightDark") or t("LightOk"), kind = dark and "bad" or "ok",
            lines = dark and { { s = t("LightHint"), c = K.text3 } } or nil }
    end
    local learned = true
    pcall(function() learned = (not r:needToBeLearn()) or r:hasPlayerLearned(p) end)
    req[#req + 1] = { name = learned and t("Learned") or t("NotLearned"), kind = learned and "ok" or "bad" }
    pcall(function()
        for i = 0, r:getRequiredSkillCount() - 1 do
            local rs = r:getRequiredSkill(i)
            local perk = rs:getPerk()
            local have = p:getPerkLevel(perk)
            local nm = perk:getName()
            req[#req + 1] = { name = t("SkillLine", nm, rs:getLevel(), have), kind = have >= rs:getLevel() and "ok" or "bad" }
        end
    end)

    -- reach / weight
    local reach = {}
    local unreachable = 0
    local checked = 0
    local wanted = {}
    for _, rq in ipairs(Craft.requirements(r, ctx.qty, counts, nil)) do
        for _, ft in ipairs(rq.fts) do wanted[ft] = true end
    end
    for _, e in ipairs(entries) do
        if checked >= 16 then break end
        if not e.veh then
            local items = e.c:getItems()
            local holds = nil
            for i = 0, items:size() - 1 do
                local ft = items:get(i):getFullType()
                if wanted[ft] then holds = ft break end
            end
            if holds then
                checked = checked + 1
                if Craft.standFor(p, e.c) == false then
                    unreachable = unreachable + 1
                    if #reach < 3 then
                        reach[#reach + 1] = { name = t("BoxUnreachable", Scan.boxName(e.c)), kind = "bad",
                            lines = { { s = t("BoxHolds", Scan.itemName(holds)), c = K.text3 } } }
                    end
                end
            end
        end
    end
    local weight = 0
    for _, rq in ipairs(Craft.requirements(r, ctx.qty, counts, nil)) do
        if not rq.uses and rq.ft then
            local si = getScriptManager():getItem(rq.ft)
            local okW, wv = pcall(function() return si:getActualWeight() end)
            weight = weight + ((okW and wv) or 0) * (rq.tool and 1 or rq.need)
        end
    end
    local inv = p:getInventory()
    local fits = inv:hasRoomFor(p, weight)
    reach[#reach + 1] = { name = t("WeightLine", floor(weight * 10) / 10), kind = fits and "ok" or "bad" }
    if unreachable == 0 then table.insert(reach, 1, { name = t("AllReachable"), kind = "ok" }) end

    return { rows = rows, req = req, reach = reach, maxNow = maxNow, maxLink = maxLink, maxHouse = maxHouse, house = house }
end

function W:createChildren()
    UI.Window.createChildren(self)
    local bw = self.width - UI.PAD * 2
    local by = self.height - UI.BTN_H - UI.PAD
    local wLink = floor(bw * 0.46)
    local wQueue = floor(bw * 0.32)
    self.linkBtn = UI.button(self, UI.PAD, by, wLink, "", self, W.onLink, "pri")
    self.queueBtn = UI.button(self, UI.PAD + wLink + 8, by, wQueue, t("QueueAnyway"), self, W.onQueue, "sec")
    UI.button(self, UI.PAD + wLink + wQueue + 16, by, bw - wLink - wQueue - 16, t("Close"), self, W.onCloseClick, "ghost")
    self.houseBtn = UI.button(self, UI.PAD, by - UI.BTN_H - 8, bw, "", self, W.onHouse, "soft")
    self.houseBtn:setIcon("house", true)
    self.houseBtn:setVisible(false)
    local ok, res = pcall(analyse, self.ctx)
    if ok then self.data = res else
        CHelp.log("missing analyse failed: " .. tostring(res))
        self.data = { rows = {}, req = {}, reach = {}, maxNow = 0, maxLink = 0, maxHouse = 0 }
    end
    -- the zone is short but the rest of the house has it: offer to fetch from the whole house
    local best = math.max(self.data.maxNow, self.data.maxLink)
    self.offerHouse = self.data.house ~= nil and self.data.maxHouse > best and best < self.ctx.qty
    if self.offerHouse then
        self.houseBtn:setTitle(t("HouseAsk", math.min(self.data.maxHouse, self.ctx.qty)))
        self.houseBtn:setVisible(true)
    end
    local n = self.data.maxLink
    self.linkBtn:setTitle(n > 0 and t("LinkDoN", math.min(n, self.ctx.qty)) or t("LinkNone"))
    self.linkBtn:setEnable(n > 0)
    self.linkBtn:setIcon("link")
end

local function section(self, y, title, rows)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    T.text(self, title, x, y, K.text2)
    y = y + UI.HS + 6
    local rowH = {}
    local total = 0
    for i, r in ipairs(rows) do
        local hasSlot = r.tex or r.px
        local h = math.max(hasSlot and 48 or (UI.HS + 18), UI.HS + 18 + #(r.lines or {}) * (UI.HS + 2))
        rowH[i] = h
        total = total + h
    end
    T.rrect(self, x, y, w, total + 8, UI.RC, K.surf)
    local cy = y + 4
    for i, r in ipairs(rows) do
        local h = rowH[i]
        local tx = x + 14
        if r.tex or r.px then
            T.slot(self, x + 12, cy + floor((h - 40) / 2), 40, r.tex, r.px)
            T.badge(self, x + 12 + 40 - 14, cy + floor((h - 40) / 2) + 40 - 14, 18, r.kind)
            tx = x + 12 + 40 + 14
        else
            T.badge(self, x + 14, cy + floor((h - 18) / 2), 18, r.kind)
            tx = x + 14 + 18 + 12
        end
        local nl = #(r.lines or {})
        local ty = cy + floor((h - (UI.HS + nl * (UI.HS + 2))) / 2)
        local col = r.kind == "bad" and K.bad or (r.kind == "link" and K.warn or K.acc)
        if r.right then T.textR(self, r.right, x + w - 14, ty, col) end
        local rw = r.right and (T.tw(r.right) + 20) or 0
        T.text(self, T.fit(r.name, w - (tx - x) - rw - 14), tx, ty, K.text)
        for j, l in ipairs(r.lines or {}) do
            T.text(self, T.fit(l.s, w - (tx - x) - 14), tx, ty + UI.HS + 2 + (j - 1) * (UI.HS + 2), l.c)
        end
        if i < #rows then T.rect(self, x + 14, cy + h, w - 28, 1, K.text, 0.06) end
        cy = cy + h
    end
    return y + total + 8 + 12
end

function W:drawBody()
    local d = self.data
    if not d then return end
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + 2
    local cards = { { t("CanNow"), d.maxNow, d.maxNow > 0 and K.acc or K.bad }, { t("WithLink"), d.maxLink, d.maxLink > 0 and K.warn or K.bad } }
    if d.house then cards[3] = { t("WholeHouse"), d.maxHouse or 0, (d.maxHouse or 0) > 0 and K.warn or K.bad } end
    local cw = floor((w - 10 * (#cards - 1)) / #cards)
    for i, c in ipairs(cards) do
        local cx = x + (i - 1) * (cw + 10)
        T.rrect(self, cx, y, cw, UI.HS + UI.HL + 18, UI.RC, K.surf)
        T.text(self, c[1], cx + 14, y + 8, K.text3)
        T.text(self, tostring(c[2]), cx + 14, y + 10 + UI.HS, c[3], T.FL)
        T.text(self, t("Times"), cx + 20 + T.tw(tostring(c[2]), T.FL), y + 10 + UI.HS + UI.HL - UI.HS - 2, K.text3)
    end
    y = y + UI.HS + UI.HL + 18 + 12
    -- long recipes scroll (mouse wheel) inside the area above the buttons
    local top = y
    local bottom = self.height - UI.BTN_H - UI.PAD - 10 - (self.offerHouse and (UI.BTN_H + 8) or 0)
    self.viewH = bottom - top
    self.scroll = self.scroll or 0
    self:setStencilRect(0, top, self.width, self.viewH)
    y = top - self.scroll
    y = section(self, y, t("SecNeed"), d.rows)
    y = section(self, y, t("SecStation"), d.req)
    y = section(self, y, t("SecReach"), d.reach)
    self:clearStencilRect()
    self.contentH = y + self.scroll - top
    local maxS = math.max(0, self.contentH - self.viewH)
    if self.scroll > maxS then self.scroll = maxS end
    if maxS > 0 then
        local barH = math.max(24, floor(self.viewH * self.viewH / self.contentH))
        local barY = top + floor((self.viewH - barH) * self.scroll / maxS)
        T.rrect(self, self.width - 8, barY, 4, barH, 2, K.text3, 0.6)
    end
end

function W:onMouseWheel(del)
    local maxS = math.max(0, (self.contentH or 0) - (self.viewH or 0))
    self.scroll = math.max(0, math.min(maxS, (self.scroll or 0) + del * 40))
    return true
end

function W:onLink()
    local n = math.min(self.data.maxLink, self.ctx.qty)
    if n <= 0 then return end
    CHelp.Queue.add({ recipe = self.ctx.recipe, qty = n, link = true, zone = self.ctx.zone })
    self:close()
end

function W:onHouse()
    local d = self.data
    local n = math.min(d.maxHouse or 0, self.ctx.qty)
    if n <= 0 or not d.house then return end
    CHelp.Queue.add({ recipe = self.ctx.recipe, qty = n, link = true, zone = self.ctx.zone, house = d.house })
    self:close()
end

function W:onQueue()
    CHelp.Queue.add({ recipe = self.ctx.recipe, qty = self.ctx.qty, link = self.ctx.link, zone = self.ctx.zone })
    self:close()
end

function M.open(ctx)
    if M.instance then M.instance:close() end
    local w, h = 600, 700
    h = math.min(h, getCore():getScreenHeight() - 20)
    local x, y = UI.center(w, h)
    local win = W:new(x, y, w, h, t("MissingTitle", Craft.label(ctx.recipe), ctx.qty))
    win.ctx = ctx
    win.headIcon = "ic_warn"
    win.headTint = K.bad
    win.subtitle = t("MissingSub", ctx.zone.name or "")
    win:show()
    M.instance = win
    return win
end
