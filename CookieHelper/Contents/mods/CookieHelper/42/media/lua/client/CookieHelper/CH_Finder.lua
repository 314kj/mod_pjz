-- Cookie Helper : Cookie Finder
-- Builds a "what is where" list for a whole safehouse (no counts, just item -> boxes) at most
-- once every N in-game hours (sandbox), scanning a few hundred squares per tick so the game
-- never hitches. Searching only reads that list; found boxes light up like foraging icons.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_Scan"

CHelp.Finder = CHelp.Finder or {}
local F = CHelp.Finder
local C = CHelp.Cl
local UI = CHelp.UI
local Scan = CHelp.Scan
local t = CHelp.t
local floor = math.floor

F.idx = F.idx or {}          -- shKey -> { hours, items = { ft -> { name, lname, spots = { key -> {x,y,z} }, n } } }
F.job = nil
local Z_MIN, Z_MAX = -3, 7
local BUDGET = 220            -- squares per tick

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

function F.start(sh)
    local key = CHelp.shKey(sh)
    if F.job and F.job.key == key then return end
    F.job = {
        key = key, sh = sh,
        x1 = sh:getX(), y1 = sh:getY(), x2 = sh:getX2(), y2 = sh:getY2(),
        x = sh:getX(), y = sh:getY(), z = Z_MIN,
        items = {}, vehSeen = {}, tickItems = 0,
        done = 0, total = (sh:getX2() - sh:getX()) * (sh:getY2() - sh:getY()) * (Z_MAX - Z_MIN + 1),
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
    if not CHelp.shByKey(job.key) then F.job = nil return end
    if not playerNear(job.sh, 30) then return end      -- squares not loaded: wait
    local cell = getCell()
    local n = 0
    job.tickItems = 0
    while n < BUDGET and job.tickItems < 1500 do
        if job.z > Z_MAX then
            F.idx[job.key] = { hours = worldHours(), items = job.items }
            F.job = nil
            C.emit("finder", job.key)
            return
        end
        local sq = cell:getGridSquare(job.x, job.y, job.z)
        if sq then scanSquare(job, sq, job.x, job.y, job.z) end
        job.done = job.done + 1
        n = n + 1
        job.x = job.x + 1
        if job.x >= job.x2 then
            job.x = job.x1
            job.y = job.y + 1
            if job.y >= job.y2 then
                job.y = job.y1
                job.z = job.z + 1
            end
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

-- every in-game hour: refresh stale lists for houses you are standing near
Events.EveryHours.Add(function()
    if F.job then return end
    local me = C.me()
    if not me then return end
    for _, sh in ipairs(CHelp.shListFor(me)) do
        if C.isRealMember(sh) and playerNear(sh, 10) and F.isStale(CHelp.shKey(sh)) then
            F.start(sh)
            return
        end
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
        end
    end
    table.sort(out, function(a, b) return a.e.name < b.e.name end)
    return out
end

function F.show(e)
    C.clearMarks("finder")
    local p = C.player()
    local pz = p and floor(p:getZ()) or 0
    local floors, labelled, here = {}, 0, 0
    for _, s in pairs(e.spots) do
        floors[s.z] = true
        local label = nil
        if labelled < 12 then label = e.name labelled = labelled + 1 end
        C.mark(s.x, s.y, s.x + 1, s.y + 1, s.z, 1.0, 0.86, 0.32, 0.55, 30000, label)
        C.marks[#C.marks].tag = "finder"
        if s.z == pz then here = here + 1 end
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
    local y = UI.HEAD_H + UI.PAD
    self.entry = UI.entry(self, x, y, w, "")
    self.entry:setPlaceholderText(t("FinderHint"))
    self.entry.onTextChange = function() self:fill() end
    y = y + UI.BTN_H + 4
    self.yStatus = y
    y = y + UI.HS + 6
    self.list = UI.makeList(self, x, y, w, self.height - y - UI.BTN_H - UI.PAD - 8, UI.HS + 14, self, W.drawRow, W.onPick)
    local by = self.height - UI.BTN_H - UI.PAD
    self.scanBtn = UI.button(self, x, by, floor(w / 2) - 3, t("FinderScanNow"), self, W.onScan)
    UI.button(self, x + floor(w / 2) + 3, by, floor(w / 2) - 3, t("FinderClear"), self, W.onClearMarks, "red")
    C.on("finder", self, W.onFinished)
    if F.isStale(self.key) and not F.idx[self.key] then F.start(self.sh) end
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
    local tex = Scan.itemTex(r.ft)
    if tex then list:drawTextureScaledAspect(tex, x + 6, y + 4, h - 8, h - 8, 1, 1, 1, 1) end
    UI.text(list, UI.fit(r.e.name, w - h - 110), x + h + 2, y + (h - UI.HS) / 2, UI.C.text)
    UI.textR(list, t("FinderSpots", r.e.n), x + w - 8, y + (h - UI.HS) / 2, UI.C.gold)
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
    local s, col
    if F.job and F.job.key == self.key then
        if playerNear(self.sh, 30) then
            s, col = t("FinderScanning", floor(F.job.done * 100 / math.max(1, F.job.total))), UI.C.gold
        else
            s, col = t("FinderGoHome"), UI.C.red
        end
    elseif F.idx[self.key] then
        local ago = floor(worldHours() - F.idx[self.key].hours)
        local n = 0
        for _ in pairs(F.idx[self.key].items) do n = n + 1 end
        s, col = t("FinderStatus", n, ago, interval()), UI.C.muted
    else
        s, col = t("FinderNoIndex"), UI.C.red
    end
    UI.text(self, UI.fit(s, self.width - 20), UI.PAD, self.yStatus, col)
end

function F.open(sh)
    if not sh then return end
    if F.instance then F.instance:close() end
    local w, h = 420, 460
    local x, y = UI.center(w, h)
    local win = W:new(x + 220, y, w, h, t("FinderTitle", sh:getTitle()))
    win.sh = sh
    win.key = CHelp.shKey(sh)
    win:show()
    F.instance = win
end
