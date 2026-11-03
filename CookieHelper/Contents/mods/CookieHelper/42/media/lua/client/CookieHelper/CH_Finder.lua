-- Cookie Helper : Cookie Finder
-- "Where is X in my house": an item -> boxes list per safehouse (no counts).
-- v1.1 lag fix:
--   * no background scan any more - it only runs while the Finder window is open and the list is stale
--   * each tick scans until ~2 ms are used (or a square / item cap), floors that do not exist are skipped
--   * search waits until you stop typing; results light up only the 30 nearest spots, 6 with labels
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_Scan"

CHelp.Finder = CHelp.Finder or {}
local F = CHelp.Finder
local C = CHelp.Cl
local UI = CHelp.UI
local T = CHelp.Th
local K = T.C
local Scan = CHelp.Scan
local t = CHelp.t
local floor = math.floor

F.idx = F.idx or {}          -- shKey -> { hours, items = { ft -> { name, lname, lft, spots = { key -> {x,y,z} }, n } } }
F.job = nil
local Z_MIN, Z_MAX = -1, 7
local SQUARE_CAP = 160        -- squares per tick at most
local ITEM_CAP = 900          -- items per tick at most
local TIME_MS = 2             -- stop the tick once this much time is used
local MAX_MARKS = 30
local MAX_LABELS = 6

local function worldHours()
    return getGameTime():getWorldAgeHours()
end

local function interval()
    return CHelp.svInt("FinderScanHours", 1, 240)
end

local function playerNear(sh, margin)
    local p = C.player()
    if not p then return false end
    return CHelp.shDist(sh, floor(p:getX()), floor(p:getY())) <= (margin or 20)
end

function F.isStale(key)
    local ix = F.idx[key]
    if not ix then return true end
    return worldHours() - ix.hours >= interval()
end

-- a floor exists if any of 5 sample squares (corners + centre) is loaded on it
local function floorExists(cell, x1, y1, x2, y2, z)
    local pts = { { x1, y1 }, { x2 - 1, y1 }, { x1, y2 - 1 }, { x2 - 1, y2 - 1 }, { floor((x1 + x2) / 2), floor((y1 + y2) / 2) } }
    for _, pt in ipairs(pts) do
        if cell:getGridSquare(pt[1], pt[2], z) then return true end
    end
    return false
end

function F.start(sh)
    local key = CHelp.shKey(sh)
    if F.job and F.job.key == key then return end
    local cell = getCell()
    local floors = {}
    for z = Z_MIN, Z_MAX do
        if floorExists(cell, sh:getX(), sh:getY(), sh:getX2(), sh:getY2(), z) then floors[#floors + 1] = z end
    end
    if #floors == 0 then floors = { 0 } end
    F.job = {
        key = key, sh = sh,
        x1 = sh:getX(), y1 = sh:getY(), x2 = sh:getX2(), y2 = sh:getY2(),
        x = sh:getX(), y = sh:getY(), fi = 1, floors = floors,
        items = {}, vehSeen = {}, tickItems = 0,
        done = 0, total = (sh:getX2() - sh:getX()) * (sh:getY2() - sh:getY()) * #floors,
    }
end

local function record(job, it, k, x, y, z)
    job.tickItems = job.tickItems + 1
    local ft = it:getFullType()
    local e = job.items[ft]
    if not e then
        local name = Scan.itemName(ft, it)
        e = { name = name, lname = string.lower(name), lft = string.lower(ft), spots = {}, n = 0 }
        job.items[ft] = e
    end
    if not e.spots[k] then
        e.spots[k] = { x = x, y = y, z = z }
        e.n = e.n + 1
    end
end

local function scanContainer(job, c, k, x, y, z)
    local items = c:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        record(job, it, k, x, y, z)
        if it:IsInventoryContainer() then
            local inner = it:getItemContainer()
            if inner then
                local ii = inner:getItems()
                for j = 0, ii:size() - 1 do record(job, ii:get(j), k, x, y, z) end
            end
        end
    end
end

local function scanSquare(job, sq, x, y, z)
    local k = nil
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        for ci = 0, o:getContainerCount() - 1 do
            local c = o:getContainerByIndex(ci)
            if c then
                k = k or (x .. "," .. y .. "," .. z)
                scanContainer(job, c, k, x, y, z)
            end
        end
    end
    local wobs = sq:getWorldObjects()
    if wobs and wobs:size() > 0 then
        k = k or (x .. "," .. y .. "," .. z)
        for i = 0, wobs:size() - 1 do
            local it = wobs:get(i):getItem()
            if it then record(job, it, k, x, y, z) end
        end
    end
    local v = sq:getVehicleContainer()
    if v and not job.vehSeen[v] then
        job.vehSeen[v] = true
        k = k or (x .. "," .. y .. "," .. z)
        for i = 0, v:getPartCount() - 1 do
            local part = v:getPartByIndex(i)
            local c = part and part:getItemContainer()
            if c then scanContainer(job, c, k, x, y, z) end
        end
    end
end

local function stepJob()
    local job = F.job
    if not job then return end
    if not F.instance then return end                    -- only while the window is open
    if not CHelp.shByKey(job.key) then F.job = nil return end
    if not playerNear(job.sh, 30) then return end      -- squares not loaded: wait
    local cell = getCell()
    local t0 = CHelp.nowMs()
    local n = 0
    job.tickItems = 0
    while n < SQUARE_CAP and job.tickItems < ITEM_CAP do
        local z = job.floors[job.fi]
        if not z then
            F.idx[job.key] = { hours = worldHours(), items = job.items }
            F.job = nil
            C.emit("finder", job.key)
            return
        end
        local sq = cell:getGridSquare(job.x, job.y, z)
        if sq then scanSquare(job, sq, job.x, job.y, z) end
        job.done = job.done + 1
        n = n + 1
        job.x = job.x + 1
        if job.x >= job.x2 then
            job.x = job.x1
            job.y = job.y + 1
            if job.y >= job.y2 then
                job.y = job.y1
                job.fi = job.fi + 1
            end
            if CHelp.nowMs() - t0 >= TIME_MS then break end
        end
    end
end

Events.OnTick.Add(function()
    if not F.job then return end
    local ok, err = pcall(stepJob)
    if not ok then
        CHelp.log("finder scan failed: " .. tostring(err))
        F.job = nil
    end
end)

function F.search(key, q)
    local ix = F.idx[key]
    local out = {}
    if not ix then return out end
    q = string.lower(q or "")
    if string.len(q) < 2 then return out end
    for ft, e in pairs(ix.items) do
        if string.find(e.lname, q, 1, true) or string.find(e.lft, q, 1, true) then
            out[#out + 1] = { ft = ft, e = e }
            if #out >= 300 then break end
        end
    end
    table.sort(out, function(a, b) return a.e.name < b.e.name end)
    return out
end

-- light the nearest spots only (a house full of nails would otherwise draw hundreds of tiles)
function F.show(e)
    C.clearMarks("finder")
    local p = C.player()
    local px, py = p and p:getX() or 0, p and p:getY() or 0
    local pz = p and floor(p:getZ()) or 0
    local spots, floors = {}, {}
    for _, s in pairs(e.spots) do
        spots[#spots + 1] = { s = s, d = (s.x - px) * (s.x - px) + (s.y - py) * (s.y - py) + math.abs(s.z - pz) * 400 }
        floors[s.z] = true
    end
    table.sort(spots, function(a, b) return a.d < b.d end)
    for i = 1, math.min(#spots, MAX_MARKS) do
        local s = spots[i].s
        C.mark(s.x, s.y, s.x + 1, s.y + 1, s.z, K.warn[1], K.warn[2], K.warn[3], 0.55, 30000, (i <= MAX_LABELS) and e.name or nil, "finder")
    end
    local fl = {}
    for z, _ in pairs(floors) do fl[#fl + 1] = z end
    table.sort(fl)
    local fs = ""
    for i, z in ipairs(fl) do fs = fs .. (i > 1 and ", " or "") .. tostring(z) end
    UI.toast(t("FinderFound", e.name, e.n, fs), true)
end

-- ------------------------------------------------------------------ window
local W = UI.Window:derive("CHelpFinder")

function W:createChildren()
    UI.Window.createChildren(self)
    local x, w = UI.PAD, self.width - UI.PAD * 2
    local y = UI.HEAD_H + 2
    self.entry = UI.entry(self, x, y, w, "")
    self.entry:setPlaceholderText(t("FinderHint"))
    self.entry.onTextChange = function() self.typedMs = CHelp.nowMs() end
    y = y + UI.BTN_H + 10
    self.yStatus = y
    y = y + UI.HS + 10
    self.list = UI.makeList(self, x, y, w, self.height - y - UI.BTN_H - UI.PAD - 10, UI.HS + 26, self, W.drawRow, W.onPick)
    self.list.rowGap = 4
    local by = self.height - UI.BTN_H - UI.PAD
    local half = floor((w - 8) / 2)
    self.scanBtn = UI.button(self, x, by, half, t("FinderScanNow"), self, W.onScan, "sec")
    self.scanBtn:setIcon("refresh")
    UI.button(self, x + half + 8, by, w - half - 8, t("FinderClear"), self, W.onClearMarks, "ghost")
    C.on("finder", self, W.onFinished)
    if F.isStale(self.key) and playerNear(self.sh, 20) then F.start(self.sh) end
    self:fill()
end

function W:onClose()
    C.off(self)
    if F.instance == self then F.instance = nil end
end

function W:onFinished(key)
    if key == self.key then self:fill() end
end

function W:fill()
    self.list:clear()
    for _, r in ipairs(F.search(self.key, self.entry:getInternalText())) do
        self.list:addItem(r.e.name, r)
        if #self.list.items >= 150 then break end
    end
end

function W.drawRow(self, list, r, x, y, w, h)
    T.slot(list, x + 8, y + 4, h - 8, Scan.itemTex(r.ft), nil)
    T.text(list, T.fit(r.e.name, w - h - 130), x + h + 8, y + floor((h - UI.HS) / 2), K.text)
    local s = t("FinderSpots", r.e.n)
    T.pill(list, x + w - 12 - T.pillW(s), y + floor((h - UI.HS - 4) / 2), s, K.warn, K.warnD)
end

function W:onPick(r)
    F.show(r.e)
end

function W:onScan()
    if not F.isStale(self.key) then
        local ix = F.idx[self.key]
        local left = math.max(0, math.ceil(interval() - (worldHours() - ix.hours)))
        UI.toast(t("FinderWait", left), false)
        return
    end
    if not playerNear(self.sh, 10) then UI.toast(t("FinderGoHome"), false) return end
    F.start(self.sh)
end

function W:onClearMarks()
    C.clearMarks("finder")
end

function W:drawBody()
    if self.typedMs and CHelp.nowMs() - self.typedMs > 220 then
        self.typedMs = nil
        self:fill()
    end
    local s, col
    local x, w = UI.PAD, self.width - UI.PAD * 2
    if F.job and F.job.key == self.key then
        local pct = floor(F.job.done * 100 / math.max(1, F.job.total))
        if playerNear(self.sh, 30) then s, col = t("FinderScanning", tostring(pct) .. "%"), K.warn
        else s, col = t("FinderGoHome"), K.bad end
        T.rrect(self, x, self.yStatus + UI.HS + 2, w, 4, 2, K.bar)
        T.rrect(self, x, self.yStatus + UI.HS + 2, math.max(4, w * pct / 100), 4, 2, K.warn)
    elseif F.idx[self.key] then
        local ago = floor(worldHours() - F.idx[self.key].hours)
        local n = 0
        for _ in pairs(F.idx[self.key].items) do n = n + 1 end
        s, col = t("FinderStatus", n, ago, interval()), K.text3
    else
        s, col = t("FinderNoIndex"), K.bad
    end
    T.text(self, T.fit(s, w), x, self.yStatus, col)
    if #self.list.items == 0 and string.len(self.entry:getInternalText() or "") >= 2 and F.idx[self.key] then
        T.textC(self, t("FinderNone"), self.width / 2, self.list:getY() + 30, K.text3)
    end
end

function F.open(sh)
    if not sh then return end
    if F.instance then F.instance:close() end
    local w, h = 440, 520
    local x, y = UI.center(w, h)
    local win = W:new(x + 220, y, w, h, t("FinderTitle"))
    win.subtitle = sh:getTitle()
    win.headIcon = "px_search"
    win.sh = sh
    win.key = CHelp.shKey(sh)
    win:show()
    F.instance = win
end
