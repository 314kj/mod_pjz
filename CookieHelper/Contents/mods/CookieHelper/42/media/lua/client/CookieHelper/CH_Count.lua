-- Cookie Helper : Auto Count (live stock of one zone + craft straight from it)
-- Recount happens only while this window is open, at most once a second, and only after
-- a container changed (or every 5 s as a safety net). Nothing runs when it is closed.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_RecipeBox"

CHelp.Count = CHelp.Count or {}
local Count = CHelp.Count
local C = CHelp.Cl
local UI = CHelp.UI
local Scan = CHelp.Scan
local Craft = CHelp.Craft
local RB = CHelp.RecipeBox
local t = CHelp.t
local floor = math.floor

Count.open_ = Count.open_ or {}

local W = UI.Window:derive("CHelpCount")
local COLS = 3
local CARD_H = 46
local GRID_H = CARD_H * 6 + 4
local RECIPE_H = 230

function W:createChildren()
    UI.Window.createChildren(self)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + UI.PAD
    self.search = UI.entry(self, x, y, w - 130, "")
    self.search:setPlaceholderText(t("SearchItems"))
    self.search.onTextChange = function() self.layoutDirty = true end
    self.sortBtn = UI.button(self, x + w - 124, y, 124, t("SortName"), self, W.onSort)
    y = y + UI.BTN_H + 4
    self.yStatus = y
    y = y + UI.HS + 6
    self.grid = UI.makeList(self, x, y, w, GRID_H, CARD_H, self, W.drawCards)
    local grid = self.grid
    grid.onMouseDown = function(l, mx, my)
        local row = l:rowAt(mx, my)
        local it = l.items[row]
        if it then
            local cw = (l.width - 4) / COLS
            local col = floor((mx - 2) / cw) + 1
            local e = it.item.cards[col]
            if e then self:pick(e) end
        end
        return true
    end
    y = y + GRID_H + 10
    self.yCraft = y
    y = y + UI.HS + 6
    self.rsearch = UI.entry(self, x, y, w, "")
    self.rsearch:setPlaceholderText(t("SearchRecipes"))
    self.rsearch.onTextChange = function() self.recipeDirty = true end
    y = y + UI.BTN_H + 6
    self.box = RB.create(self, x, y, w, RECIPE_H, {
        getEntries = function() return self:entries() end,
        canCraft = function() return self:playerInZone() end,
        why = "Msg_StandInZone",
    })
    self.sortByCount = false
    self.dirty = true
    self.layoutDirty = true
    self.recipeDirty = true
    self.lastCount = 0
    self.map = {}
    self.total = 0
    self.types = 0
end

function W:onClose()
    Count.open_[self] = nil
    if Count.instance == self then Count.instance = nil end
end

function W:entries()
    return Scan.containers(self.zone, self.zone.z, true)
end

function W:playerInZone()
    local p = C.player()
    if not p or floor(p:getZ()) ~= self.zone.z then return false end
    return CHelp.rectHas(self.zone, floor(p:getX()), floor(p:getY()), 1)
end

function W:near()
    local p = C.player()
    if not p then return false end
    local cx, cy = (self.zone.x1 + self.zone.x2) / 2, (self.zone.y1 + self.zone.y2) / 2
    return math.abs(p:getX() - cx) < 45 and math.abs(p:getY() - cy) < 45
end

function W:onSort()
    self.sortByCount = not self.sortByCount
    self.sortBtn:setTitle(self.sortByCount and t("SortCount") or t("SortName"))
    self.layoutDirty = true
end

function W:pick(e)
    if self.picked == e.ft then self.picked = nil else self.picked = e.ft end
    self.recipeDirty = true
end

function W:recount()
    local entries = self:entries()
    self.map, self.total = Scan.count(entries)
    local n = 0
    for _ in pairs(self.map) do n = n + 1 end
    self.types = n
    self.lastCount = CHelp.nowMs()
    self.layoutDirty = true
    self.planContainers = Craft.planContainers(C.player(), entries)
    self.box:invalidate(self.planContainers)
end

function W:relayout()
    local q = string.lower(self.search:getInternalText() or "")
    local arr = {}
    for _, e in pairs(self.map) do
        if q == "" or string.find(string.lower(e.name), q, 1, true) or string.find(string.lower(e.ft), q, 1, true) then
            arr[#arr + 1] = e
        end
    end
    if self.sortByCount then
        table.sort(arr, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    else
        table.sort(arr, function(a, b) return a.name < b.name end)
    end
    local keepScroll = self.grid:getYScroll()
    self.grid:clear()
    local row = nil
    for i, e in ipairs(arr) do
        if (i - 1) % COLS == 0 then
            row = { cards = {} }
            self.grid:addItem("", row)
        end
        row.cards[#row.cards + 1] = e
    end
    self.grid.selected = 0
    self.grid:setYScroll(keepScroll)
    self.layoutDirty = false
end

function W:refreshRecipes()
    local q = self.rsearch:getInternalText() or ""
    local list
    if string.len(q) >= 2 then
        list = Craft.search(q, 40)
    elseif self.picked then
        list = Craft.recipesFor(self.picked)
    else
        list = {}
    end
    self.box:setRecipes(list)
    self.recipeDirty = false
end

function W.drawCards(self, list, row, x, y, w, h)
    local cw = (w) / COLS
    for i, e in ipairs(row.cards) do
        local cx = x + (i - 1) * cw
        local sel = self.picked == e.ft
        UI.rect(list, cx + 2, y + 2, cw - 4, h - 4, sel and UI.C.btnMint or UI.C.card)
        if e.tex then list:drawTextureScaledAspect(e.tex, cx + 6, y + 7, 32, 32, 1, 1, 1, 1) end
        local num = "x" .. tostring(e.n)
        local nw = getTextManager():MeasureStringX(UI.FONT_M, num)
        UI.textR(list, num, cx + cw - 8, y + (h - UI.HM) / 2, UI.C.gold, UI.FONT_M)
        UI.text(list, UI.fit(e.name, cw - 52 - nw), cx + 42, y + (h - UI.HS) / 2, UI.C.text)
    end
end

function W:drawBody()
    local ms = CHelp.nowMs()
    local near = self:near()
    if near and (self.dirty or ms - self.lastCount > 5000) and ms - self.lastCount > 800 then
        self.dirty = false
        local ok, err = pcall(function() self:recount() end)
        if not ok then CHelp.log("count failed: " .. tostring(err)) end
    end
    if self.layoutDirty then self:relayout() end
    if self.recipeDirty then self:refreshRecipes() end
    self.box:pump(2)
    local status
    if not near then
        status = t("CountFar")
    else
        status = t("CountStatus", self.types, self.total, floor((ms - self.lastCount) / 1000))
    end
    UI.text(self, UI.fit(status, self.width - 20), UI.PAD, self.yStatus, near and UI.C.muted or UI.C.red)
    local craftHead = self.picked and t("CraftFor", CHelp.Scan.itemName(self.picked)) or t("CraftHead")
    UI.text(self, UI.fit(craftHead, self.width - 20), UI.PAD, self.yCraft, UI.C.gold)
    if not self:playerInZone() then
        UI.textR(self, t("Msg_StandInZone"), self.width - UI.PAD, self.yCraft, UI.C.red)
    end
end

function Count.markDirty()
    for win, _ in pairs(Count.open_) do win.dirty = true end
end

function Count.open(sh, zone)
    if Count.instance then Count.instance:close() end
    local w = 600
    local h = UI.HEAD_H + UI.PAD + UI.BTN_H + 4 + UI.HS + 6 + GRID_H + 10 + UI.HS + 6 + UI.BTN_H + 6 + RECIPE_H + UI.PAD
    local x, y = UI.center(w, h)
    local win = W:new(x, y, w, h, t("CountTitle", zone.name))
    win.sh = sh
    win.zone = zone
    win:show()
    Count.instance = win
    Count.open_[win] = true
end

Events.OnContainerUpdate.Add(function()
    if next(Count.open_) ~= nil then Count.markDirty() end
    if CHelp.Veh and CHelp.Veh.markDirty then CHelp.Veh.markDirty() end
end)
