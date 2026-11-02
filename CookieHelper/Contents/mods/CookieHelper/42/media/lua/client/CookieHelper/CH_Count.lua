-- Cookie Helper : Workshop zone window (live stock + workstations + craft from the zone)
-- Recount happens only while this window is open, at most once a second, and only after a
-- container changed (or every 5 s as a safety net). Nothing runs when it is closed.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_RecipeBox"

CHelp.Count = CHelp.Count or {}
local Count = CHelp.Count
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local Scan = CHelp.Scan
local Craft = CHelp.Craft
local RB = CHelp.RecipeBox
local t = CHelp.t
local floor = math.floor

Count.open_ = Count.open_ or {}

local W = UI.Window:derive("CHelpCount")
local COLS = 3
local CARD_H = 56
local STRIP_H = 44

-- pixel icon for a workstation name
local function stationPx(name)
    local n = string.lower(tostring(name or ""))
    if string.find(n, "loom", 1, true) or string.find(n, "ทอ", 1, true) then return "loom" end
    if string.find(n, "spin", 1, true) or string.find(n, "ปั่น", 1, true) then return "thread" end
    if string.find(n, "furnace", 1, true) or string.find(n, "kiln", 1, true) or string.find(n, "เตา", 1, true) then return "furnace" end
    return "anvil"
end
Count.stationPx = stationPx

function W:createChildren()
    UI.Window.createChildren(self)
    local hr = self:headRight()
    self.queueBtn = UI.button(self, hr - 110, floor((UI.HEAD_H - UI.BTN_H) / 2), 110, t("Queue"), self, W.onQueue, "sec")
    self.queueBtn:setIcon("list")
    self.tabs = UI.tabs(self, 0, floor((UI.HEAD_H - UI.BTN_H) / 2), {
        { id = "stock", label = t("TabStock") }, { id = "recipes", label = t("TabRecipes") }, { id = "stations", label = t("TabStations") },
    }, "recipes", self, W.onTab, UI.BTN_H)
    self.tabs:setX(self.queueBtn:getX() - 10 - self.tabs.width)
    self.headTextRight = self.tabs:getX() - 12

    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + STRIP_H
    local h = self.height - y - UI.PAD
    self.cx, self.cy, self.cw, self.ch = x, y, w, h

    -- recipes
    self.box = RB.create(self, x, y, w, h, {
        zone = function() return self.zone end,
        canCraft = function() return self:playerInZone() end,
        why = "Msg_StandInZone",
        listW = 360,
    })
    self.box.onSearch = function() self.recipeDirty = true end

    -- stock
    self.search = UI.entry(self, x, y, w - 140, "")
    self.search:setPlaceholderText(t("SearchItems"))
    self.search.onTextChange = function() self.layoutDirty = true end
    self.sortBtn = UI.button(self, x + w - 130, y, 130, t("SortName"), self, W.onSort, "sec")
    self.grid = UI.makeList(self, x, y + UI.BTN_H + 10, w, h - UI.BTN_H - 10, CARD_H + 8, self, W.drawCards)
    self.grid.bare = true
    self.grid.noSelect = true
    self.grid.onMouseDown = function(l, mx, my)
        local row = l:rowAt(mx, my)
        local it = l.items[row]
        if it then
            local cw = (l.width - (l:isVScrollBarVisible() and 14 or 0)) / COLS
            local col = floor(mx / cw) + 1
            local e = it.item.cards[col]
            if e then self:pick(e) end
        end
        return true
    end

    -- stations
    self.slist = UI.makeList(self, x, y, w, h, 64, self, W.drawStation, W.onStation)

    self.sortByCount = false
    self.dirty = true
    self.layoutDirty = true
    self.recipeDirty = true
    self.lastCount = 0
    self.lastStations = 0
    self.map = {}
    self.total = 0
    self.types = 0
    self.boxes = 0
    self.stations = { benches = {}, machines = {}, surfaces = {} }
    C.on("queue", self, W.onQueueChanged)
    self:onTab("recipes")
end

function W:onClose()
    C.off(self)
    Count.open_[self] = nil
    if Count.instance == self then Count.instance = nil end
end

function W:onTab(id)
    self.tab = id
    self.tabs.sel = id
    self.box:setVisible(id == "recipes")
    self.search:setVisible(id == "stock")
    self.sortBtn:setVisible(id == "stock")
    self.grid:setVisible(id == "stock")
    self.slist:setVisible(id == "stations")
end

function W:onQueue() CHelp.Queue.open() end
function W:onQueueChanged() self.queueBtn.badge = CHelp.Queue.count() end

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
    self.picked = e.ft
    self.recipeDirty = true
    self.box.search:setText("")
    self:onTab("recipes")
end

function W:recount()
    local p = C.player()
    local entries = self:entries()
    self.map, self.total = Scan.count(entries)
    local n = 0
    for _ in pairs(self.map) do n = n + 1 end
    self.types = n
    local nb = 0
    for _, e in ipairs(entries) do if not e.veh then nb = nb + 1 end end
    self.boxes = nb
    self.lastCount = CHelp.nowMs()
    self.layoutDirty = true
    local counts = Craft.countWithBag(p, self.map)
    if CHelp.nowMs() - self.lastStations > 5000 then
        self.lastStations = CHelp.nowMs()
        self.stations = Scan.stations(self.zone, self.zone.z)
        self:fillStations()
        self.recipeDirty = self.recipeDirty or (self.box.search:getInternalText() or "") == ""
    end
    self.box:invalidate(Craft.planContainers(p, entries), counts, self.stations)
    self.subtitle = t("CountSub", self.boxes, self.total)
end

function W:fillStations()
    self.slist:clear()
    for _, b in ipairs(self.stations.benches) do
        local n = 0
        pcall(function() n = b.bench:getRecipes():size() end)
        self.slist:addItem(b.name, { s = b, kind = "bench", px = stationPx(b.name), n = n })
    end
    for _, m in ipairs(self.stations.machines) do
        self.slist:addItem(m.name, { s = m, kind = "machine", px = "furnace" })
    end
    if #self.stations.surfaces > 0 then
        local s = self.stations.surfaces[1]
        self.slist:addItem(t("Surfaces"), { s = s, kind = "surface", px = "table", n = #self.stations.surfaces })
    end
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
    self.grid:setYScroll(keepScroll)
    self.layoutDirty = false
end

-- default list: recipes used here this session, then what the zone's workstations make
function W:defaultRecipes()
    local out, seen = {}, {}
    local function add(r) if r and not seen[r] and #out < 80 then seen[r] = true out[#out + 1] = r end end
    for _, r in ipairs(RB.recent) do add(r) end
    for _, b in ipairs(self.stations.benches) do
        pcall(function()
            local list = b.bench:getRecipes()
            for i = 0, math.min(list:size(), 60) - 1 do add(list:get(i)) end
        end)
    end
    return out
end

function W:refreshRecipes()
    local q = self.box.search:getInternalText() or ""
    local list
    if string.len(q) >= 2 then
        list = Craft.search(q, 60)
        self.picked = nil
    elseif self.picked then
        list = Craft.recipesFor(self.picked)
    else
        list = self:defaultRecipes()
    end
    self.box:setRecipes(list)
    self.recipeDirty = false
end

function W.drawCards(self, list, row, x, y, w, h)
    local cw = (w) / COLS
    local mx, my = list:getMouseX(), list:getMouseY()
    for i, e in ipairs(row.cards) do
        local cx = x + (i - 1) * cw
        local r = { x = cx + 3, y = y, w = cw - 6, h = h - 8 }
        local hov = T.hot(r, mx, my)
        if self.picked == e.ft then T.rring(list, r.x, r.y, r.w, r.h, UI.RC, K.acc, K.surf, 2)
        else T.rrect(list, r.x, r.y, r.w, r.h, UI.RC, hov and K.surf3 or K.surf) end
        T.slot(list, r.x + 8, r.y + floor((r.h - 40) / 2), 40, e.tex, nil)
        local num = tostring(e.n)
        local nw = T.tw(num, T.FM)
        T.textR(list, num, r.x + r.w - 12, r.y + floor((r.h - UI.HM) / 2), K.acc, T.FM)
        T.text(list, T.fit(e.name, r.w - 70 - nw), r.x + 56, r.y + floor((r.h - UI.HS) / 2), K.text)
    end
end

function W.drawStation(self, list, d, x, y, w, h)
    T.slot(list, x + 10, y + floor((h - 8 - 44) / 2), 44, nil, d.px)
    local tx = x + 68
    local s = d.s
    T.text(list, T.fit(s.name, w - 220), tx, y + 10, K.text)
    local sub
    if d.kind == "bench" then sub = t("BenchRecipes", d.n)
    elseif d.kind == "machine" then sub = t("MachineHint")
    else sub = t("SurfacesN", d.n) end
    T.text(list, T.fit(sub, w - 220), tx, y + 12 + UI.HS, K.text3)
    T.textR(list, t("AtCorner", s.x - self.zone.x1, s.y - self.zone.y1), x + w - 14, y + floor((h - 8 - UI.HS) / 2), K.text3)
end

function W:onStation(d)
    local s = d.s
    C.mark(s.x, s.y, s.x + 1, s.y + 1, s.z, K.acc[1], K.acc[2], K.acc[3], 0.6, 5000, s.name, "station")
end

function W:drawStrip()
    local x, y, w = UI.PAD, UI.HEAD_H, self.width - UI.PAD * 2
    local cy = y + floor((STRIP_H - UI.HS - 8) / 2) - 2
    T.text(self, t("StationsIn"), x, cy + 4, K.text3)
    local px = x + T.tw(t("StationsIn")) + 10
    local right = x + w - 200
    local function chip(label, pxName, fg, bg)
        local cw = T.pillW(label, T.FS, { px = pxName })
        if px + cw > right then return false end
        T.pill(self, px, cy, label, fg, bg, T.FS, { px = pxName })
        px = px + cw + 6
        return true
    end
    local any = false
    for _, b in ipairs(self.stations.benches) do
        any = true
        if not chip(T.fit(b.name, 160), stationPx(b.name), K.acc, K.accD) then break end
    end
    if #self.stations.surfaces > 0 then
        any = true
        chip(t("TablesN", #self.stations.surfaces), "table", K.acc, K.accD)
    end
    for _, m in ipairs(self.stations.machines) do
        any = true
        if not chip(T.fit(m.name, 160) .. " · " .. t("Auto"), "furnace", K.text2, K.surf2) then break end
    end
    if not any then T.text(self, t("NoStations"), px, cy + 4, K.text3) end
    local inside = self:playerInZone()
    local s = inside and t("InZone") or t("Msg_StandInZone")
    local col = inside and K.acc or K.bad
    T.icon(self, inside and "check" or "warn", x + w - T.tw(s) - 22, cy + 4, UI.HS, col)
    T.textR(self, s, x + w, cy + 4, col)
end

function W:drawBody()
    local ms = CHelp.nowMs()
    local near = self:near()
    if near and (self.dirty or ms - self.lastCount > 5000) and ms - self.lastCount > 800 then
        self.dirty = false
        local ok, err = pcall(function() self:recount() end)
        if not ok then CHelp.log("count failed: " .. tostring(err)) end
    end
    if self.layoutDirty and self.tab == "stock" then self:relayout() end
    if self.recipeDirty then self:refreshRecipes() end
    self:drawStrip()
    if not near then
        T.textC(self, t("CountFar"), self.width / 2, self.height - UI.PAD - UI.HS, K.bad)
    end
    if self.tab == "stock" and #self.grid.items == 0 then
        T.textC(self, near and t("EmptyZone") or t("CountFar"), self.width / 2, self.grid:getY() + 40, K.text3)
    end
    if self.tab == "stations" and #self.slist.items == 0 then
        T.textC(self, t("NoStationsLong"), self.width / 2, self.slist:getY() + 40, K.text3)
    end
end

function Count.markDirty()
    for win, _ in pairs(Count.open_) do win.dirty = true end
end

function Count.open(sh, zone)
    if Count.instance then Count.instance:close() end
    local sw, shh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = math.min(1000, sw - 20), math.min(720, shh - 20)
    local x, y = UI.center(w, h)
    local win = W:new(x, y, w, h, zone.name)
    win.sh = sh
    win.zone = zone
    win.subtitle = t("Workshop")
    win:show()
    Count.instance = win
    Count.open_[win] = true
    win:onQueueChanged()
    C.mark(zone.x1, zone.y1, zone.x2, zone.y2, zone.z, K.acc[1], K.acc[2], K.acc[3], 0.25, 2500, nil, "zone")
end

Events.OnContainerUpdate.Add(function()
    if CHelp.hasAny(Count.open_) then Count.markDirty() end
    if CHelp.Veh and CHelp.Veh.markDirty then CHelp.Veh.markDirty() end
end)
