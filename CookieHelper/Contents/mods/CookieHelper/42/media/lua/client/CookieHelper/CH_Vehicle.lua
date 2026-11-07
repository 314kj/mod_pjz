-- Cookie Helper : Vehicle Zone (garage window)
-- Opened from the right-click menu. Two tabs on the right:
--   Car   : the model in 3D (drag to turn, wheel to zoom), a quick info card, the button for the
--           game's mechanics window, and every part of the parked car with its condition.
--           Right-click a part = repair / install with things from the zone (or the house), plus
--           the game's own part menu.
--   Parts : every part item this model uses, how many are in the zone, and the recipes that make
--           them (craft from here, same as the workshop).
-- Any model can be browsed; real part lists come from cars that have been parked in a zone
-- at least once (shared by the server), others fall back to a name match on item ids.
if isServer() then return end

require "CookieHelper/CH_Client"
require "CookieHelper/CH_RecipeBox"
require "CookieHelper/CH_VehFix"
require "Vehicles/ISUI/ISUI3DScene"

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
local PARTS_H = 150

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

local function partName(part)
    local id = part:getId()
    local s = getTextOrNull("IGUI_VehiclePart" .. id)
    return s or id
end

local function catName(cat)
    if not cat or cat == "" then return "" end
    return getTextOrNull("IGUI_VehiclePartCat" .. cat) or cat
end

local function condColor(c)
    if c >= 70 then return K.acc end
    if c >= 35 then return K.warn end
    return K.bad
end

-- ------------------------------------------------------------------ build
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
    local ty = y + UI.HM + UI.HS + 12
    self.tab = "car"
    self.tabs = UI.tabs(self, rx, ty, { { id = "car", label = t("TabCar") }, { id = "craft", label = t("TabParts") } }, self.tab, self, W.onTab)
    local cy = ty + self.tabs.height + 10
    self.cy = cy

    -- car tab: 3D view + info card + live parts
    local sceneW = floor(rw * 0.58)
    local sceneH = math.max(200, math.min(320, floor((self.height - cy - UI.PAD) * 0.48)))
    self.sceneX, self.sceneY, self.sceneW, self.sceneH = rx, cy, sceneW, sceneH
    local okS, err = pcall(function() self:makeScene() end)
    if not okS then
        CHelp.log("vehicle 3D view failed: " .. tostring(err))
        self.scene = nil
    end
    local bs = 30
    self.spinBtn = UI.iconButton(self, rx + 10, cy + sceneH - bs - 10, bs, "pause", self, W.onSpin, "sec", t("TipSpin"))
    self.resetBtn = UI.iconButton(self, rx + 10 + bs + 6, cy + sceneH - bs - 10, bs, "refresh", self, W.onResetView, "sec", t("TipResetView"))
    local ix = rx + sceneW + 14
    self.infoX, self.infoW = ix, rw - sceneW - 14
    self.mechBtn = UI.button(self, ix, cy + sceneH - UI.BTN_H, self.infoW, t("VehInfoBtn"), self, W.onMechanics, "pri")
    self.mechBtn:setIcon("car", true)
    self.yRealHead = cy + sceneH + 12
    local ly = self.yRealHead + UI.HS + 8
    self.real = UI.makeList(self, rx, ly, rw, self.height - ly - UI.PAD, UI.HS + 26, self, W.drawReal, W.onReal)
    self.real.rowGap = 4
    self.real.onRightMouseUp = function(l, mx, my) return self:onRealRight(l, mx, my) end
    self.real:setOnMouseDoubleClick(self, W.onRealDouble)

    -- parts tab: part items of the model + recipe box
    local py = cy
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

    self.data = {}          -- scriptName -> { items, extra, source }
    self.counts = {}
    self.dirty = true
    self.recipeDirty = true
    self.lastCount = 0
    C.on("vehList", self, W.onVehList)
    C.on("vehData", self, W.onVehData)
    CHelp.toServer("vehListReq", {})
    self:refreshVehicles()
    self:applyTab()
end

-- the game's 3D view, but it keeps the mouse: dragging turns the car instead of moving the window
local function sceneClass()
    if V.Scene then return V.Scene end
    if not ISUI3DScene then return nil end
    local S = ISUI3DScene:derive("CHelpScene")
    function S:onMouseDown(x, y) ISUI3DScene.onMouseDown(self, x, y) return true end
    function S:onMouseUp(x, y) ISUI3DScene.onMouseUp(self, x, y) return true end
    function S:onMouseUpOutside(x, y) ISUI3DScene.onMouseUpOutside(self, x, y) return true end
    function S:onMouseMove(dx, dy) ISUI3DScene.onMouseMove(self, dx, dy) return true end
    function S:onMouseWheel(del) ISUI3DScene.onMouseWheel(self, del) return true end
    function S:onRightMouseDown() return true end
    function S:onRightMouseUp() return true end
    V.Scene = S
    return S
end

function W:makeScene()
    local Scene = sceneClass()
    if not Scene then error("ISUI3DScene missing") end
    local sc = Scene:new(self.sceneX, self.sceneY, self.sceneW, self.sceneH)
    sc:initialise()
    sc:instantiate()
    sc.background = false
    self:addChild(sc)
    local js = sc.javaObject
    js:fromLua1("setMaxZoom", 20)
    js:fromLua1("setZoom", 2)
    js:fromLua1("setDrawGrid", false)
    pcall(function() js:fromLua1("setDrawGridAxes", false) end)
    pcall(function() js:fromLua1("setGizmoVisible", "none") end)
    js:fromLua1("createVehicle", "veh")
    pcall(function() js:fromLua2("setObjectVisible", "veh", false) end)
    self.scene = sc
    self.spin = true
end

function W:showModel3D(name)
    if not self.scene then return end
    local ok, err = pcall(function()
        local js = self.scene.javaObject
        js:fromLua2("setVehicleScript", "veh", name)
        pcall(function() js:fromLua2("setObjectVisible", "veh", true) end)
        pcall(function() js:fromLua2("setObjectAutoRotate", "veh", self.spin) end)
    end)
    if not ok then CHelp.log("3D model failed for " .. tostring(name) .. ": " .. tostring(err)) end
    self.scene3D = ok and name or nil
end

function W:onSpin()
    self.spin = not self.spin
    self.spinBtn:setIcon(self.spin and "pause" or "play")
    if self.scene then pcall(function() self.scene.javaObject:fromLua2("setObjectAutoRotate", "veh", self.spin) end) end
end

function W:onResetView()
    if not self.scene then return end
    pcall(function()
        self.scene:setView("UserDefined")
        self.scene.javaObject:fromLua1("setZoom", 2)
    end)
end

function W:onTab(id)
    self.tab = id
    self:applyTab()
end

function W:applyTab()
    local car = self.tab == "car"
    for _, el in ipairs({ self.spinBtn, self.resetBtn, self.mechBtn, self.real }) do el:setVisible(car) end
    if self.scene then self.scene:setVisible(car) end
    for _, el in ipairs({ self.parts, self.addBtn, self.delBtn, self.box }) do el:setVisible(not car) end
end

function W:onClose()
    C.off(self)
    if V.instance == self then V.instance = nil end
end

function W:entries()
    return Scan.containers(self.zone, self.zone.z, true)
end

function W:houseEntries()
    if not self.sh then return nil end
    return CHelp.Queue.zoneFns(self.zone, self.sh)()
end

function W:playerInZone()
    local p = C.player()
    if not p or floor(p:getZ()) ~= self.zone.z then return false end
    return CHelp.zoneHas(self.zone, floor(p:getX()), floor(p:getY()), 1)
end

-- the parked car of the selected model (nil = just browsing a model)
function W:vehicle()
    local v = self.selModel and self.inZone[self.selModel]
    if v and v:getSquare() then return v end
    return nil
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
        self:fillReal()
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
    self:fillReal()
    self:showModel3D(name)
    self.recipeDirty = true
end

-- ------------------------------------------------------------------ car tab: live parts
function W:fillReal()
    self.lastReal = CHelp.nowMs()
    local v = self:vehicle()
    if not v then
        if self.realSig ~= "" then self.real:clear() end
        self.realSig, self.info = "", nil
        return
    end
    local rows = {}
    local sum, n, missing, bad = 0, 0, 0, 0
    for i = 0, v:getPartCount() - 1 do
        local part = v:getPartByIndex(i)
        local cat = part and part:getCategory() or "Other"
        if part and part:getId() and cat ~= "nodisplay" then
            local item = part:getInventoryItem()
            local types = part:getItemType()
            local slot = types and not types:isEmpty()
            local has = item ~= nil or not slot
            local cond = part:getCondition()
            if has then
                sum, n = sum + cond, n + 1
                if cond < 35 then bad = bad + 1 end
            else
                missing = missing + 1
            end
            rows[#rows + 1] = { part = part, id = part:getId(), name = partName(part), cat = cat, catName = catName(cat),
                cond = cond, has = has, tex = item and item:getTex() or nil,
                ft = item and item:getFullType() or (slot and normType(types:get(0)) or nil) }
        end
    end
    table.sort(rows, function(a, b)
        if a.has ~= b.has then return not a.has end          -- missing first
        if a.cond ~= b.cond then return a.cond < b.cond end  -- then the worst
        return a.name < b.name
    end)
    -- rebuild only when something changed (keeps the scroll position while repairing)
    local sig = { tostring(v:getId()) }
    for _, r in ipairs(rows) do sig[#sig + 1] = r.id .. (r.has and "+" or "-") .. r.cond end
    sig = table.concat(sig, ";")
    local changed = sig ~= self.realSig
    self.realSig = sig
    local keep = self.real.selected
    local keepId = keep and self.real.items[keep] and self.real.items[keep].item.id or nil
    if changed then self.real:clear() end
    for i, r in ipairs(changed and rows or {}) do
        self.real:addItem(r.name, r)
        if r.id == keepId then self.real.selected = i end
    end
    local info = { cond = n > 0 and floor(sum / n) or 0, missing = missing, bad = bad, total = #rows }
    pcall(function() info.engine = v:getEngineQuality() end)
    pcall(function()
        local gas = v:getPartById("GasTank")
        if gas and gas:getContainerCapacity() > 0 then
            info.fuel = floor(gas:getContainerContentAmount() * 100 / gas:getContainerCapacity())
        end
    end)
    pcall(function()
        local bat = v:getPartById("Battery")
        local it = bat and bat:getInventoryItem()
        if it then info.battery = floor((it:getCurrentUsesFloat() or 0) * 100) end
    end)
    self.info = info
end

function W.drawReal(self, list, r, x, y, w, h)
    T.slot(list, x + 8, y + 4, h - 8, r.tex, (not r.tex) and (r.has and "car" or nil) or nil)
    local tx = x + h + 8
    local barW = 120
    local right = x + w - 12
    if r.has then
        local col = condColor(r.cond)
        local pct = r.cond .. "%"
        T.textR(list, pct, right, y + floor((h - UI.HS) / 2), col)
        local bx = right - T.tw("100%") - 10 - barW
        local by = y + floor(h / 2) - 3
        T.rrect(list, bx, by, barW, 6, 3, K.bar)
        T.rrect(list, bx, by, math.max(6, floor(barW * r.cond / 100)), 6, 3, col)
        right = bx - 12
    else
        local lw = T.pill(list, right - T.pillW(t("PartMissing")), y + floor((h - UI.HS - 4) / 2), t("PartMissing"), K.bad, K.badD)
        right = right - lw - 12
    end
    T.text(list, T.fit(r.name, right - tx - 10), tx, y + floor(h / 2) - UI.HS - 1, K.text)
    T.text(list, T.fit(r.catName, right - tx - 10), tx, y + floor(h / 2) + 1, K.text3)
end

function W:onReal(r)
    -- left click only selects
end

function W:onRealDouble(r)
    if r and r.ft then self:showCraftFor(r.ft) end
end

function W:onRealRight(list, mx, my)
    local row = list:rowAt(mx, my)
    local it = row and list.items[row]
    if not it then return true end
    list.selected = row
    local r = it.item
    local p = C.player()
    if not p or not r.part then return true end
    CHelp.VehFix.partMenu(p, r.part, getMouseX(), getMouseY(), {
        zoneFn = function() return self:entries() end,
        houseFn = function() return self:houseEntries() end,
        onCraft = function(ft) self:showCraftFor(ft) end,
    })
    return true
end

-- jump to the parts tab with this item picked (its recipes show below)
function W:showCraftFor(ft)
    self.tab = "craft"
    self.tabs.sel = "craft"
    self:applyTab()
    self.selPart = ft
    self.parts.selected = 0
    for i, it in ipairs(self.parts.items) do
        if it.item.ft == ft then self.parts.selected = i end
    end
    self.recipeDirty = true
end

function W:onMechanics()
    local p = C.player()
    local v = self:vehicle()
    if not p or not v then return end
    local ok, err = pcall(function() ISVehicleMenu.onMechanic(p, v) end)
    if not ok then
        CHelp.log("open mechanics failed: " .. tostring(err))
        ISTimedActionQueue.add(ISOpenMechanicsUIAction:new(p, v))
    end
end

-- ------------------------------------------------------------------ parts tab
function W:fillParts()
    self.parts:clear()
    local d = self.selModel and self.data[self.selModel]
    if not d then return end
    for _, ft in ipairs(d.items or {}) do
        self.parts:addItem(Scan.itemName(ft), { ft = ft, tex = Scan.itemTex(ft), recipes = #Craft.recipesFor(ft) })
    end
    self.parts.selected = 0
    for i, it in ipairs(self.parts.items) do
        if it.item.ft == self.selPart then self.parts.selected = i end
    end
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

-- ------------------------------------------------------------------ draw
function W:drawInfo()
    local x, w = self.infoX, self.infoW
    local y = self.sceneY
    local h = self.sceneH - UI.BTN_H - 10
    T.rrect(self, x, y, w, h, 14, K.surf)
    local v = self:vehicle()
    local cx, cy = x + 14, y + 12
    if not v then
        T.text(self, t("VehNotHere"), cx, cy, K.warn)
        cy = cy + UI.HS + 8
        for _, l in ipairs(T.wrap(t("VehNotHereSub"), w - 28, T.FS, 5)) do
            T.text(self, l, cx, cy, K.text3)
            cy = cy + UI.HS + 3
        end
        return
    end
    local info = self.info or {}
    T.text(self, t("VehCondition"), cx, cy, K.text3)
    T.textR(self, (info.cond or 0) .. "%", x + w - 14, cy - 4, condColor(info.cond or 0), T.FL)
    cy = cy + UI.HL + 2
    T.rrect(self, cx, cy, w - 28, 8, 4, K.bar)
    T.rrect(self, cx, cy, math.max(8, floor((w - 28) * (info.cond or 0) / 100)), 8, 4, condColor(info.cond or 0))
    cy = cy + 18
    local function line(label, value, col)
        T.text(self, label, cx, cy, K.text2)
        T.textR(self, value, x + w - 14, cy, col or K.text)
        cy = cy + UI.HS + 6
    end
    if info.engine then line(t("VehEngine"), info.engine .. "%", condColor(info.engine)) end
    if info.fuel then line(t("VehFuel"), info.fuel .. "%", info.fuel > 20 and K.text or K.warn) end
    if info.battery then line(t("VehBattery"), info.battery .. "%", info.battery > 20 and K.text or K.warn) end
    line(t("VehMissing"), tostring(info.missing or 0), (info.missing or 0) > 0 and K.bad or K.acc)
    line(t("VehBad"), tostring(info.bad or 0), (info.bad or 0) > 0 and K.warn or K.acc)
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
    if self.tab == "craft" and self.recipeDirty then self:refreshRecipes() end
    -- part conditions change while repairing: refresh the live list now and then
    if self.tab == "car" and ms - (self.lastReal or 0) > 2000 then
        local ok, err = pcall(function() self:fillReal() end)
        if not ok then CHelp.log("vehicle parts failed: " .. tostring(err)) self.lastReal = ms end
    end

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

    if self.tab == "car" then
        -- showroom card behind the 3D view
        T.rrect(self, self.sceneX, self.sceneY, self.sceneW, self.sceneH, 14, K.bar)
        T.rrect(self, self.sceneX + 2, self.sceneY + 2, self.sceneW - 4, floor(self.sceneH * 0.55), 12, K.surf, 0.55)
        if not self.scene3D then
            T.textC(self, self.scene and t("PickModel") or t("No3D"), self.sceneX + self.sceneW / 2, self.sceneY + self.sceneH / 2 - UI.HS, K.text3)
        end
        self:drawInfo()
        self.mechBtn:setEnable(self:vehicle() ~= nil)
        local head = self:vehicle() and t("PartsOnCar", self.real.items and #self.real.items or 0) or t("PartsOnCarNone")
        local hint = self:vehicle() and t("PartsRightClick") or ""
        local hw = (hint ~= "") and math.min(T.tw(hint), floor(self.rw * 0.55)) or 0
        T.text(self, T.fit(head, self.rw - hw - 20), rx, self.yRealHead, K.text2)
        if hint ~= "" then T.textR(self, T.fit(hint, hw), rx + self.rw, self.yRealHead, K.text3) end
    else
        local head = self.selPart and t("CraftFor", Scan.itemName(self.selPart)) or t("ModelRecipes")
        T.text(self, T.fit(head, self.rw - 280), rx, self.yRecipes + floor((UI.BTN_H - UI.HS) / 2) - 4, K.text2)
    end
end

-- drawn after the 3D view, so it sits on top of it
function W:drawOver()
    if self.tab == "car" and self.scene3D then
        T.textR(self, t("Tip3D"), self.sceneX + self.sceneW - 12, self.sceneY + self.sceneH - UI.HS - 12, K.text3)
    end
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

function V.open(sh, zone)
    if V.instance then V.instance:close() end
    local sw, shh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = math.min(1080, sw - 20), math.min(820, shh - 20)
    local x, y = UI.center(w, h)
    local win = W:new(x, y, w, h, zone.name)
    win.subtitle = t("Garage")
    win.headIcon = "px_car"
    win.sh = sh
    win.zone = zone
    win:show()
    V.instance = win
end
