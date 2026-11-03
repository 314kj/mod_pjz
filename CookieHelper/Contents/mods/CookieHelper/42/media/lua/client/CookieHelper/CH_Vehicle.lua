-- Cookie Helper : Vehicle Zone
-- Park a car in the zone and stand in it: a panel lists every part item this model uses,
-- how many of each are already in the zone, and the recipes that make them (craft from here).
-- Any model can be browsed; real part lists come from cars that have been parked in a zone
-- at least once (shared by the server), others fall back to a name match on item ids.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_RecipeBox"

CHelp.Veh = CHelp.Veh or {}
local V = CHelp.Veh
local C = CHelp.Cl
local UI = CHelp.UI
local Scan = CHelp.Scan
local Craft = CHelp.Craft
local RB = CHelp.RecipeBox
local t = CHelp.t
local floor = math.floor

local T = CHelp.Th
local K = T.C
local W = UI.Window:derive("CHelpVehicle")
local LEFT_W = 220
local PARTS_H = 170

local function normType(s)
    if not s or s == "" then return nil end
    if string.find(s, ".", 1, true) then return s end
    return "Base." .. s
end

local labelCache = {}
local function modelLabel(scriptName)
    local cached = labelCache[scriptName]
    if cached then return cached end
    local short = scriptName
    local dot = string.find(scriptName, ".", 1, true)
    if dot then short = string.sub(scriptName, dot + 1) end
    local tx = getText("IGUI_VehicleName" .. short)
    if not tx or tx == ("IGUI_VehicleName" .. short) then tx = short end
    labelCache[scriptName] = tx
    return tx
end

-- parts straight from a parked vehicle (exact)
local function partsOfVehicle(v)
    local out, seen = {}, {}
    for i = 0, v:getPartCount() - 1 do
        local part = v:getPartByIndex(i)
        local types = part and part:getItemType()
        if types then
            for j = 0, types:size() - 1 do
                local ft = normType(types:get(j))
                if ft and not seen[ft] and getScriptManager():getItem(ft) then
                    seen[ft] = true
                    out[#out + 1] = ft
                end
            end
        end
    end
    table.sort(out)
    return out
end

-- name match fallback for models nobody has parked yet (KI5 names items after the car)
local guessCache = {}
local function guessParts(scriptName)
    if guessCache[scriptName] then return guessCache[scriptName] end
    local short = scriptName
    local dot = string.find(scriptName, ".", 1, true)
    if dot then short = string.sub(scriptName, dot + 1) end
    short = string.lower(short)
    local out = {}
    if string.len(short) >= 4 then
        local all = getScriptManager():getAllItems()
        for i = 0, all:size() - 1 do
            local it = all:get(i)
            local fn = it:getFullName()
            if string.find(string.lower(fn), short, 1, true) and not it:getObsolete() then out[#out + 1] = fn end
            if #out >= 120 then break end
        end
    end
    table.sort(out)
    guessCache[scriptName] = out
    return out
end

function W:createChildren()
    UI.Window.createChildren(self)
    self.inZone = {}
    self.known = {}
    local x = UI.PAD
    local y = UI.HEAD_H + 2
    local fullH = self.height - y - UI.PAD
    self.mfilter = UI.entry(self, x, y, LEFT_W, "")
    self.mfilter:setPlaceholderText(t("FilterModels"))
    self.mfilter.onTextChange = function() self:fillModels() end
    self.models = UI.makeList(self, x, y + UI.BTN_H + 8, LEFT_W, fullH - UI.BTN_H - 8, UI.HS + 16, self, W.drawModel, W.onModel)
    self.models.rowGap = 4

    local rx = x + LEFT_W + 16
    local rw = self.width - rx - UI.PAD
    self.rx, self.rw = rx, rw
    self.yTitle = y
    local py = y + UI.HM + UI.HS + 12
    self.parts = UI.makeList(self, rx, py, rw, PARTS_H, UI.HS + 26, self, W.drawPart, W.onPart)
    self.parts.rowGap = 4
    py = py + PARTS_H + 10
    self.yRecipes = py
    self.addBtn = UI.button(self, rx + rw - 260, py - 4, 130, t("AddToModel"), self, W.onAddExtra, "soft")
    self.addBtn:setIcon("plus")
    self.delBtn = UI.button(self, rx + rw - 124, py - 4, 124, t("RemoveFromModel"), self, W.onDelExtra, "bad")
    py = py + UI.BTN_H + 6
    self.box = RB.create(self, rx, py, rw, self.height - py - UI.PAD, {
        zone = function() return self.zone end,
        canCraft = function() return self:playerInZone() end,
        why = "Msg_StandInZone",
        listW = 300,
    })
    self.box.onSearch = function() self.recipeDirty = true end

    self.known = {}
    self.data = {}          -- scriptName -> { items, extra, source }
    self.counts = {}
    self.dirty = true
    self.recipeDirty = true
    self.lastCount = 0
    C.on("vehList", self, W.onVehList)
    C.on("vehData", self, W.onVehData)
    CHelp.toServer("vehListReq", {})
    self:refreshVehicles()
end

function W:onClose()
    C.off(self)
    if V.instance == self then V.instance = nil end
end

function W:entries()
    return Scan.containers(self.zone, self.zone.z, true)
end

function W:playerInZone()
    local p = C.player()
    if not p or floor(p:getZ()) ~= self.zone.z then return false end
    return CHelp.rectHas(self.zone, floor(p:getX()), floor(p:getY()), 1)
end

function W:refreshVehicles()
    self.reported = self.reported or {}
    local now, sig = {}, ""
    for _, v in ipairs(Scan.vehicles(self.zone, self.zone.z)) do
        local sc = v:getScript()
        if sc then
            local name = sc:getFullName()
            now[name] = v
            sig = sig .. name .. ";"
            if not self.reported[name] then
                self.reported[name] = true
                local items = partsOfVehicle(v)
                self.data[name] = { items = items, extra = (self.data[name] and self.data[name].extra) or {}, source = "real" }
                CHelp.toServer("vparts", { veh = name, items = items })
                CHelp.toServer("vehDataReq", { veh = name })
            end
        end
    end
    self.inZone = now
    if sig ~= self.vehSig then
        self.vehSig = sig
        self:fillModels()
    end
end

function W:onVehList(list)
    self.known = {}
    for _, n in ipairs(list or {}) do self.known[n] = true end
    self:fillModels()
end

function W:onVehData(veh, d)
    local cur = self.data[veh] or {}
    local items = cur.items
    local source = cur.source
    if source ~= "real" then
        if d.known and #d.items > 0 then items, source = d.items, "shared"
        else items, source = guessParts(veh), "guess" end
    end
    self.data[veh] = { items = items or {}, extra = d.extra or {}, source = source }
    if self.selModel == veh then self:fillParts() end
end

function W:fillModels()
    local q = string.lower(self.mfilter:getInternalText() or "")
    local keepSel = self.selModel
    self.models:clear()
    local seen = {}
    local function add(name)
        if seen[name] then return end
        local lab = modelLabel(name)
        if q ~= "" and not string.find(string.lower(lab), q, 1, true) and not string.find(string.lower(name), q, 1, true) then return end
        seen[name] = true
        self.models:addItem(lab, { name = name, label = lab, here = self.inZone[name] ~= nil, known = self.known[name] })
    end
    for name, _ in pairs(self.inZone) do add(name) end
    for _, name in ipairs(V.allModels()) do add(name) end
    self.models.selected = 0
    for i, it in ipairs(self.models.items) do
        if it.item.name == keepSel then self.models.selected = i end
    end
    if not self.selModel and #self.models.items > 0 and self.models.items[1].item.here then
        self.models.selected = 1
        self:selectModel(self.models.items[1].item.name)
    end
end

function W.drawModel(self, list, m, x, y, w, h)
    local col = m.here and K.acc or (m.known and K.text or K.text3)
    local tx = x + 12
    if m.here then
        T.px(list, "car", x + 8, y + floor((h - 16) / 2), 16)
        tx = x + 30
    end
    T.text(list, T.fit(m.label, w - (tx - x) - 8), tx, y + floor((h - UI.HS) / 2), col)
end

function W:onModel(m)
    self:selectModel(m.name)
end

function W:selectModel(name)
    self.selModel = name
    self.selPart = nil
    if not self.data[name] then
        self.data[name] = { items = {}, extra = {}, source = "loading" }
        CHelp.toServer("vehDataReq", { veh = name })
    end
    self:fillParts()
    self.recipeDirty = true
end

function W:fillParts()
    self.parts:clear()
    local d = self.selModel and self.data[self.selModel]
    if not d then return end
    for _, ft in ipairs(d.items or {}) do
        self.parts:addItem(Scan.itemName(ft), { ft = ft, tex = Scan.itemTex(ft), recipes = #Craft.recipesFor(ft) })
    end
    self.parts.selected = 0
    self.recipeDirty = true
end

function W.drawPart(self, list, p, x, y, w, h)
    T.slot(list, x + 8, y + 4, h - 8, p.tex, nil)
    local tx = x + h + 8
    T.text(list, T.fit(Scan.itemName(p.ft), w - (tx - x) - 190), tx, y + floor((h - UI.HS) / 2), K.text)
    local have = self.counts[p.ft] or 0
    T.pill(list, x + w - 180, y + floor((h - UI.HS - 4) / 2), t("InZoneN", have), have > 0 and K.acc or K.text3, have > 0 and K.accD or K.surf2)
    T.pill(list, x + w - 84, y + floor((h - UI.HS - 4) / 2), t("Recipes", p.recipes), p.recipes > 0 and K.warn or K.text3, p.recipes > 0 and K.warnD or K.surf2)
end

function W:onPart(p)
    if self.selPart == p.ft then self.selPart = nil else self.selPart = p.ft end
    self.recipeDirty = true
end

function W:refreshRecipes()
    local q = self.box.search:getInternalText() or ""
    local list = {}
    if string.len(q) >= 2 then
        list = Craft.search(q, 60)
    else
        local seen = {}
        local function add(r) if r and not seen[r] then seen[r] = true list[#list + 1] = r end end
        if self.selPart then
            for _, r in ipairs(Craft.recipesFor(self.selPart)) do add(r) end
        end
        local d = self.selModel and self.data[self.selModel]
        for _, name in ipairs(d and d.extra or {}) do add(Craft.byName(name)) end
    end
    self.box:setRecipes(list)
    self.recipeDirty = false
end

function W:onAddExtra()
    local r = self.box:selected()
    if not r or not self.selModel then return end
    CHelp.toServer("vextra", { veh = self.selModel, recipe = r:getName(), add = true })
end

function W:onDelExtra()
    local r = self.box:selected()
    if not r or not self.selModel then return end
    CHelp.toServer("vextra", { veh = self.selModel, recipe = r:getName(), add = false })
end

function W:recount()
    local p = C.player()
    local entries = self:entries()
    local map = Scan.count(entries)
    self.counts = {}
    for ft, e in pairs(map) do self.counts[ft] = e.n end
    self.lastCount = CHelp.nowMs()
    if CHelp.nowMs() - (self.lastStations or 0) > 5000 then
        self.lastStations = CHelp.nowMs()
        self.stations = Scan.stations(self.zone, self.zone.z)
    end
    self.box:invalidate(Craft.planContainers(p, entries), Craft.countWithBag(p, map), self.stations)
end

function W:drawBody()
    local ms = CHelp.nowMs()
    if (self.dirty or ms - self.lastCount > 5000) and ms - self.lastCount > 900 then
        self.dirty = false
        local ok, err = pcall(function() self:recount() end)
        if not ok then CHelp.log("vehicle count failed: " .. tostring(err)) end
        if ms - (self.lastVehScan or 0) > 4000 then
            self.lastVehScan = ms
            pcall(function() self:refreshVehicles() end)
        end
    end
    if self.recipeDirty then self:refreshRecipes() end

    local rx = self.rx
    local d = self.selModel and self.data[self.selModel]
    local title = self.selModel and modelLabel(self.selModel) or t("PickModel")
    T.text(self, T.fit(title, self.rw - 200, T.FM), rx, self.yTitle, K.text, T.FM)
    local src = ""
    if d then
        if d.source == "real" then src = t("SrcReal", #d.items)
        elseif d.source == "shared" then src = t("SrcShared", #d.items)
        elseif d.source == "guess" then src = (#d.items > 0) and t("SrcGuess", #d.items) or t("SrcNone")
        else src = t("St_Checking") end
    end
    T.text(self, T.fit(src, self.rw), rx, self.yTitle + UI.HM + 4, K.text3)
    local inside = self:playerInZone()
    local s = inside and t("InZone") or t("Msg_StandInZone")
    T.textR(self, s, rx + self.rw, self.yTitle + 4, inside and K.acc or K.bad)
    local head = self.selPart and t("CraftFor", Scan.itemName(self.selPart)) or t("ModelRecipes")
    T.text(self, T.fit(head, self.rw - 280), rx, self.yRecipes + floor((UI.BTN_H - UI.HS) / 2) - 4, K.text2)
end

local sortedModels = nil
function V.allModels()
    if sortedModels then return sortedModels end
    sortedModels = {}
    local all = getScriptManager():getAllVehicleScripts()
    for i = 0, all:size() - 1 do sortedModels[#sortedModels + 1] = all:get(i):getFullName() end
    table.sort(sortedModels, function(a, b) return modelLabel(a) < modelLabel(b) end)
    return sortedModels
end

function V.markDirty()
    if V.instance then V.instance.dirty = true end
end

function V.open(sh, zone, auto)
    if V.instance then V.instance:close() end
    local sw, shh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = math.min(1020, sw - 20), math.min(760, shh - 20)
    local x, y = UI.center(w, h)
    local win = W:new(x, y, w, h, zone.name)
    win.subtitle = t("Garage")
    win.headIcon = "px_car"
    win.sh = sh
    win.zone = zone
    win.autoOpened = auto == true
    win:show()
    V.instance = win
end

-- auto-open when you and a car are both in a vehicle zone (checked once a second)
local lastCheck, lastZone = 0, nil
Events.OnTick.Add(function()
    local ms = CHelp.nowMs()
    if ms - lastCheck < 1000 then return end
    lastCheck = ms
    local p = C.player()
    if not p then return end
    local x, y, z = floor(p:getX()), floor(p:getY()), floor(p:getZ())
    local sh = CHelp.shAt(x, y)
    local zn = sh and C.isRealMember(sh) and C.zoneAt(sh, x, y, z, CHelp.ZONE_VEHICLE) or nil
    if not zn then
        if lastZone and V.instance and V.instance.autoOpened then V.instance:close() end
        lastZone = nil
        return
    end
    if lastZone == zn.id then return end
    if #Scan.vehicles(zn, z) > 0 then
        lastZone = zn.id
        if not V.instance then V.open(sh, zn, true) end
    end
end)
