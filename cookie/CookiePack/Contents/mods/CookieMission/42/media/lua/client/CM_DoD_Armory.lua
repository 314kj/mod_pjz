-- Cookie Mission - Die or Die armory (client): before a deploy each member picks gear per slot (an admin lists it with
-- prices, 0 = free), presets (admin ones on the server, 3 of my own on this machine), my character wearing the picks
-- (turn it with the arrows / a drag / auto spin), the admin list editor, and putting the gear on after the landing.
require "CM_DoD_Client"

local T = CMC.txt
local D = CM.DOD
local K = CMDoDc.K
local mbtn = CMDoDc.btn

local function S(n) return CMUI.S(n) end
local function rect(win, x, y, w, h, c, a) win:drawRect(x, y, w, h, a or 1, c[1], c[2], c[3]) end
local function border(win, x, y, w, h, c, a) win:drawRectBorder(x, y, w, h, a or 1, c[1], c[2], c[3]) end
local function team() return CMDoDc.snap and CMDoDc.snap.team or nil end
local function money(cents) return "$" .. CMDoDc.num(math.floor((cents or 0) / 100)) end

CMDoDc.gear = nil          -- { v, list, pre } as the server sent it

-- ===================================================================== list helpers
local itemCache = {}
local function itemOf(ft)
    local c = itemCache[ft]
    if c == nil then
        local ok, it = pcall(instanceItem, ft)
        c = ok and it or false
        itemCache[ft] = c
    end
    return c or nil
end

local function entryById(id)
    for _, e in ipairs((CMDoDc.gear and CMDoDc.gear.list) or {}) do
        if e.id == id then return e end
    end
    return nil
end

local function options(slot)
    local c = D.GEAR_SLOT[slot].c
    local out = {}
    for _, e in ipairs((CMDoDc.gear and CMDoDc.gear.list) or {}) do
        if e.s == c then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) if a.p ~= b.p then return a.p < b.p end return a.id < b.id end)
    return out
end

local function entryName(e)
    if e.n and e.n ~= "" then return e.n end
    local first = e.it and e.it[1]
    local it = first and itemOf(first.t)
    local n = (it and it:getDisplayName()) or (first and first.t) or "?"
    if first and (first.n or 1) > 1 then n = n .. " x" .. first.n end
    if #(e.it or {}) > 1 then n = n .. " +" .. (#e.it - 1) end
    return n
end

local function entryTex(e)
    local first = e.it and e.it[1]
    local it = first and itemOf(first.t)
    if not it then return nil end
    local ok, tx = pcall(function() return it:getTex() end)
    return ok and tx or nil
end

local function itemsText(e)
    local parts = {}
    for _, x in ipairs(e.it or {}) do parts[#parts + 1] = x.t .. ((x.n or 1) > 1 and (" x" .. x.n) or "") end
    return table.concat(parts, ", ")
end

local function cost(pk)
    local usd = 0
    for slot, id in pairs(pk or {}) do
        local e = entryById(id)
        if e and D.GEAR_SLOT[slot] and e.s == D.GEAR_SLOT[slot].c then usd = usd + (e.p or 0) end
    end
    return usd
end

-- the slot an item most likely fills (the admin can change it in the form)
local function guessCat(it)
    if not it then return "top" end
    if instanceof(it, "HandWeapon") then
        local okR, ranged = pcall(function() return it:isRanged() end)
        local okT, two = pcall(function() return it:isTwoHandWeapon() end)
        if okR and ranged and okT and two then return "gun" end
        return "side"
    end
    local okC, cat = pcall(function() return tostring(it:getDisplayCategory() or it:getCategory() or "") end)
    if okC and string.find(string.lower(cat), "ammo", 1, true) then return "ammo" end
    local okL, loc = pcall(function()
        local l = it:getBodyLocation()
        if not l and it.canBeEquipped then l = it:canBeEquipped() end
        return string.lower(tostring(l or ""))
    end)
    loc = okL and loc or ""
    local function has(w) return string.find(loc, w, 1, true) ~= nil end
    if has("back") then return "back" end
    if has("hat") or has("helmet") then return "head" end
    if has("mask") or has("eyes") or has("face") or has("neck") or has("ears") then return "face" end
    if has("vest") then return "body" end
    if has("forearm") or has("elbow") or has("shoulder") or has("arm") then return "arms" end
    if has("hand") or has("glove") then return "hands" end
    if has("pants") or has("leg") or has("thigh") or has("shin") or has("knee") or has("skirt") then return "legs" end
    if has("shoe") or has("feet") or has("foot") or has("sock") then return "feet" end
    return "top"
end

-- ===================================================================== my presets (this machine)
local KIT_FILE = "CookieMission_dodkit.txt"
local mine = nil
local function minesLoad()
    mine = {}
    pcall(function()
        local r = getFileReader(KIT_FILE, false)
        if not r then return end
        for i = 1, 3 do
            local line = r:readLine()
            if not line then break end
            local pk = {}
            for slot, id in string.gmatch(line, "([%w_]+)=(%d+)") do
                if D.GEAR_SLOT[slot] then pk[slot] = tonumber(id) end
            end
            mine[i] = CM.any(pk) and pk or nil
        end
        r:close()
    end)
end

local function minesSave()
    pcall(function()
        local w = getFileWriter(KIT_FILE, true, false)
        for i = 1, 3 do
            local parts = {}
            for _, s in ipairs(D.GEAR_SLOTS) do
                if mine[i] and mine[i][s.id] then parts[#parts + 1] = s.id .. "=" .. mine[i][s.id] end
            end
            w:writeln(table.concat(parts, ";"))
        end
        w:close()
    end)
end

-- ===================================================================== the window
CMDoDc.Armory = CMUI.Window:derive("CMDoD_Armory")
local AR = CMDoDc.Armory

function AR:new(x, y, w, h, edit)
    local o = CMUI.Window.new(self, x, y, w, h)
    o.title = "ARMORY"
    local tm = team()
    o.pk = CM.copy((tm and tm.phase == "room" and tm.gear) or {})
    o.edit = edit == true
    o.cat = "head"
    o.saving = false
    o.spin = false
    o.spinAt = 0
    o.dirty = true
    o.editId = nil
    return o
end

function AR:drawFrame()
    local w, h = self.width, self.height
    CMDoDc.backdrop(self, 0, 0, w, h, CMDoDc.bg or 1)
    border(self, 0, 0, w, h, K.line2, 1)
    local hh = self.headerH
    rect(self, 0, hh, w, 1, K.g, 0.25)
    CMDoDc.crosshair(self, S(26), hh / 2, S(11), K.g, 2)
    CMUI.text(self, "ARMORY", S(46), (hh - CMUI.fh(UIFont.Medium)) / 2, K.text, 1, UIFont.Medium)
    local tm = team()
    if tm and tm.loc and D.LOC[tm.loc] then
        CMUI.text(self, string.upper(D.LOC[tm.loc].n) .. "  -  " .. D.TIER_TAG[tm.tier], S(60) + CMUI.tw(UIFont.Medium, "ARMORY"),
            (hh - CMUI.fh(UIFont.Small)) / 2, K.g, 1, UIFont.Small)
    end
    local cs = hh - S(16)
    local cx = w - cs - S(10)
    local over = self:hit(cx, S(8), cs, cs, function() self:close() end)
    rect(self, cx, S(8), cs, cs, over and K.red or K.panel, over and 0.6 or 0.9)
    border(self, cx, S(8), cs, cs, K.line2, 1)
    CMUI.textC(self, "x", cx + cs / 2, S(8) + (cs - CMUI.fh(UIFont.Small)) / 2 - 1, K.text, 1, UIFont.Small)
    -- the wallet, amber like money everywhere in Die or Die
    local bal = (tm and tm.wallet) or CX and CX.bal or nil
    if bal then
        local label = "COOKIE WALLET  " .. money(bal)
        local bw = CMUI.tw(UIFont.Small, label) + S(28)
        local bx = cx - bw - S(10)
        rect(self, bx, S(8), bw, cs, { 0.10, 0.08, 0.03 }, 0.95)
        border(self, bx, S(8), bw, cs, K.amber, 1)
        CMUI.textC(self, label, bx + bw / 2, S(8) + (cs - CMUI.fh(UIFont.Small)) / 2, K.amber, 1, UIFont.Small)
    end
end

function AR:send()
    local tm = team()
    if tm and tm.phase == "room" then CMC.send("dodGearPick", { pk = self.pk }) end
    self.dirty = true
end

function AR:setPick(slot, id)
    self.pk[slot] = id
    self:send()
end

function AR:apply(pk)
    self.pk = {}
    for slot, id in pairs(pk or {}) do
        local e = entryById(id)
        if e and D.GEAR_SLOT[slot] and e.s == D.GEAR_SLOT[slot].c then self.pk[slot] = id end
    end
    self:send()
end

-- my character wearing the picks: a copy of my look and clothes, the picked gear on top (weapons are not drawn)
function AR:dress()
    self.dirty = false
    local mo, p = self.model, CMC.player()
    if not mo or not p then return end
    local ok = pcall(function()
        local desc = SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, p:isFemale())
        desc:getHumanVisual():copyFrom(p:getHumanVisual())
        local worn = p:getWornItems()
        for i = 0, worn:size() - 1 do
            local wi = worn:get(i)
            pcall(function()
                local copy = instanceItem(wi:getItem():getFullType())
                pcall(function() copy:getVisual():copyFrom(wi:getItem():getVisual()) end)
                desc:setWornItem(wi:getLocation(), copy)
            end)
        end
        for _, s in ipairs(D.GEAR_SLOTS) do
            local e = self.pk[s.id] and entryById(self.pk[s.id])
            for _, x in ipairs((e and e.it) or {}) do
                pcall(function()
                    local it = instanceItem(x.t)
                    local loc = it:getBodyLocation()
                    if not loc and it.canBeEquipped then loc = it:canBeEquipped() end
                    if loc then desc:setWornItem(loc, it) end
                end)
            end
        end
        mo:setSurvivorDesc(desc)
    end)
    if not ok then pcall(function() mo:setCharacter(p) end) end
end

function AR:turn(step)
    local mo = self.model
    if mo then pcall(function() mo:setDirection(IsoDirectionSet.rotate(mo:getDirection(), step)) end) end
end

function AR:drawModel(x, y, w, h)
    rect(self, x, y, w, h, K.ink, 0.55)
    border(self, x, y, w, h, K.line, 1)
    CMUI.glow(self, x + w / 2, y + h * 0.82, w * 0.42, S(26), K.g, 0.35)
    CMUI.text(self, T("IGUI_CM_Dod_gearMe"), x + S(10), y + S(8), K.g, 1, UIFont.Small)
    local mh = h - S(72)
    if not self.model then
        pcall(function()
            local a = ISUI3DModel:new(x, y + S(24), w, mh)
            a:initialise()
            a:instantiate()
            a:setVisible(true)
            self:addChild(a)
            a:setState("idle")
            a:setDirection(IsoDirections.S)
            a:setIsometric(false)
            self.model = a
        end)
        self.dirty = true
    end
    if self.model then
        self.model:setX(x); self.model:setY(y + S(24)); self.model:setWidth(w); self.model:setHeight(mh)
        if self.dirty then self:dress() end
        if self.spin and CMC.ms() - self.spinAt > 350 then
            self.spinAt = CMC.ms()
            self:turn(1)
        end
    end
    local by = y + h - S(40)
    local bw = S(44)
    mbtn(self, x + S(10), by, bw, S(32), "<", function() self.spin = false; self:turn(-1) end, "ghost", { font = UIFont.Medium })
    mbtn(self, x + w - S(10) - bw, by, bw, S(32), ">", function() self.spin = false; self:turn(1) end, "ghost", { font = UIFont.Medium })
    mbtn(self, x + S(18) + bw, by, w - S(36) - bw * 2, S(32), T("IGUI_CM_Dod_gearSpin"), function() self.spin = not self.spin end,
        self.spin and "on" or "ghost")
end

-- one slot card: slot name, price tag, the item picture, its name, arrows through the options (first = nothing)
function AR:card(s, x, y, w, h)
    local opts = options(s.id)
    local id = self.pk[s.id]
    local idx = 0
    for i, e in ipairs(opts) do if e.id == id then idx = i end end
    local e = idx > 0 and opts[idx] or nil
    rect(self, x, y, w, h, e and { 0.07, 0.10, 0.05 } or K.panel, 0.93)
    border(self, x, y, w, h, e and K.g or K.line, 1)
    -- the cut corners
    rect(self, x, y, S(8), S(2), K.bg, 1); rect(self, x, y, S(2), S(8), K.bg, 1)
    rect(self, x + w - S(8), y + h - S(2), S(8), S(2), K.bg, 1); rect(self, x + w - S(2), y + h - S(8), S(2), S(8), K.bg, 1)
    CMUI.text(self, s.n, x + S(10), y + S(6), e and K.g or K.dim, 1, UIFont.Small)
    CMUI.text(self, T("IGUI_CM_Dod_slot_" .. s.c), x + S(10), y + S(6) + CMUI.fh(UIFont.Small), K.faint, 1, UIFont.Small)
    if e then
        local tag = (e.p or 0) == 0 and "FREE" or ("$" .. CMDoDc.num(e.p))
        local tw = CMUI.tw(UIFont.Small, tag) + S(14)
        rect(self, x + w - tw - S(6), y + S(6), tw, CMUI.fh(UIFont.Small) + S(4), (e.p or 0) == 0 and K.g or K.amber, 1)
        CMUI.textC(self, tag, x + w - tw / 2 - S(6), y + S(8), K.ink, 1, UIFont.Small)
    end
    local isz = math.min(S(52), h - S(100))
    local iy = y + S(10) + CMUI.fh(UIFont.Small) * 2
    if e then
        local tx = entryTex(e)
        CMUI.glow(self, x + w / 2, iy + isz / 2, isz * 0.9, isz * 0.6, K.g, 0.18)
        if tx then self:drawTextureScaledAspect(tx, x + (w - isz) / 2, iy, isz, isz, 1, 1, 1, 1) end
        CMUI.textC(self, CMUI.fit(entryName(e), UIFont.Small, w - S(16)), x + w / 2, iy + isz + S(4), K.text, 1, UIFont.Small)
    else
        CMUI.textC(self, #opts == 0 and "-" or T("IGUI_CM_Dod_gearNone"), x + w / 2, iy + isz / 2 - CMUI.fh(UIFont.Small) / 2, K.faint, 1, UIFont.Small)
    end
    local by = y + h - S(32)
    local bw = S(34)
    local n = #opts + 1
    local function go(d)
        local ni = CM.mod(idx + d, n)
        self:setPick(s.id, ni > 0 and opts[ni].id or nil)
    end
    mbtn(self, x + S(8), by, bw, S(26), "<", function() go(-1) end, "ghost", { disabled = #opts == 0 })
    mbtn(self, x + w - S(8) - bw, by, bw, S(26), ">", function() go(1) end, "ghost", { disabled = #opts == 0 })
    CMUI.textC(self, idx .. " / " .. #opts, x + w / 2, by + (S(26) - CMUI.fh(UIFont.Small)) / 2, K.dim, 1, UIFont.Small)
end

-- presets: the admin ones (name + price) and my 3 slots (click = put on, SAVE then a slot = keep this kit there)
function AR:drawPresets(x, y, w)
    local bh = S(30)
    local bx = x
    local g = CMDoDc.gear or {}
    for _, pr in ipairs(g.pre or {}) do
        local usd = cost(pr.pk)
        local label = pr.n .. "  " .. (usd == 0 and "FREE" or ("$" .. CMDoDc.num(usd)))
        local bw = CMUI.tw(UIFont.Small, label) + S(24)
        if bx + bw > x + w * 0.62 then break end
        mbtn(self, bx, y, bw, bh, label, function() self:apply(pr.pk) end, "on")
        bx = bx + bw + S(6)
    end
    if not mine then minesLoad() end
    local rx = x + w
    local cw = CMUI.tw(UIFont.Small, T("IGUI_CM_Dod_gearClear")) + S(24)
    rx = rx - cw
    mbtn(self, rx, y, cw, bh, T("IGUI_CM_Dod_gearClear"), function() self:apply({}) end, "ghost")
    local sw = CMUI.tw(UIFont.Small, T("IGUI_CM_Dod_gearSave")) + S(24)
    rx = rx - sw - S(12)
    mbtn(self, rx, y, sw, bh, T("IGUI_CM_Dod_gearSave"), function() self.saving = not self.saving end, self.saving and "go" or "ghost",
        { tip = T("IGUI_CM_Dod_gearSaveTip") })
    for i = 3, 1, -1 do
        local label = T("IGUI_CM_Dod_gearMine", i)
        local mw = CMUI.tw(UIFont.Small, label) + S(20)
        rx = rx - mw - S(6)
        mbtn(self, rx, y, mw, bh, label, function()
            if self.saving then
                mine[i] = CM.copy(self.pk)
                minesSave()
                self.saving = false
            elseif mine[i] then self:apply(mine[i]) end
        end, self.saving and "red" or (mine[i] and "on" or "ghost"), { disabled = not self.saving and not mine[i] })
    end
end

-- ===================================================================== admin editor
function AR:entries()
    if self.ents then return end
    local fs = UIFont.Small
    self.ents = {
        it = CMUI.entry(self, 0, 0, S(200), CMUI.fh(fs) + S(10), { max = 400, tip = T("IGUI_CM_Dod_gearItems") }),
        p = CMUI.entry(self, 0, 0, S(80), CMUI.fh(fs) + S(10), { num = true, max = 7, text = "0" }),
        n = CMUI.entry(self, 0, 0, S(140), CMUI.fh(fs) + S(10), { max = 40, tip = T("IGUI_CM_Dod_gearName") }),
        pre = CMUI.entry(self, 0, 0, S(140), CMUI.fh(fs) + S(10), { max = 30, tip = T("IGUI_CM_Dod_gearPresetName") }),
    }
end

function AR:showEntries(on)
    for _, e in pairs(self.ents or {}) do e:setVisible(on) end
end

local function place(e, x, y, w)
    e:setX(x); e:setY(y)
    if w then e:setWidth(w) end
end

-- what I wear and hold, each as its own entry at $0 (the price is set after)
function AR:addWorn()
    local p = CMC.player()
    if not p then return end
    local seen = {}
    local function add(it)
        if not it then return end
        local ft = it:getFullType()
        if seen[ft] then return end
        seen[ft] = true
        CMC.send("dodGearSet", { s = guessCat(it), it = ft, p = 0 })
    end
    pcall(function()
        local worn = p:getWornItems()
        for i = 0, worn:size() - 1 do add(worn:get(i):getItem()) end
    end)
    pcall(function() add(p:getPrimaryHandItem()) end)
    pcall(function() add(p:getSecondaryHandItem()) end)
end

function AR:drawEditor(x, y, w, h)
    self:entries()
    local fs = UIFont.Small
    local fh = CMUI.fh(fs) + S(10)
    -- category tabs
    local tx, ty = x, y
    for _, c in ipairs(D.GEAR_CATS) do
        local label = T("IGUI_CM_Dod_slot_" .. c)
        local tw = CMUI.tw(fs, label) + S(20)
        if tx + tw > x + w then tx, ty = x, ty + S(32) end
        mbtn(self, tx, ty, tw, S(28), label, function() self.cat = c; self.editId = nil end, self.cat == c and "on" or "ghost")
        tx = tx + tw + S(4)
    end
    local ly = ty + S(38)
    -- the form: items, price, name, add / save
    local e = self.editId and entryById(self.editId) or nil
    CMUI.text(self, T("IGUI_CM_Dod_gearItems"), x, ly, K.dim, 1, fs)
    ly = ly + CMUI.fh(fs) + S(2)
    local bw = S(110)
    local iw = w - S(80) - S(150) - bw - S(24)
    place(self.ents.it, x, ly, iw)
    place(self.ents.p, x + iw + S(8), ly, S(80))
    place(self.ents.n, x + iw + S(96), ly, S(150))
    mbtn(self, x + w - bw, ly, bw, fh, e and T("IGUI_CM_Dod_gearSaveOne") or T("IGUI_CM_Dod_gearAdd"), function()
        CMC.send("dodGearSet", { id = self.editId, s = self.cat, it = CMUI.val(self.ents.it), p = CM.int(CMUI.val(self.ents.p), 0, 0, 1000000),
            n = CMUI.val(self.ents.n) })
        self.editId = nil
        CMUI.setVal(self.ents.it, ""); CMUI.setVal(self.ents.p, "0"); CMUI.setVal(self.ents.n, "")
    end, "go")
    CMUI.text(self, T("IGUI_CM_Dod_gearPrice"), x + iw + S(8), ly - CMUI.fh(fs) - S(2), K.dim, 1, fs)
    CMUI.text(self, T("IGUI_CM_Dod_gearName"), x + iw + S(96), ly - CMUI.fh(fs) - S(2), K.dim, 1, fs)
    ly = ly + fh + S(10)
    -- the list of this category
    local listH = h - (ly - y) - S(84)
    local off = self:beginScroll("gearlist", x, ly, w, listH)
    local ry = ly - off
    local rh = S(40)
    for _, en in ipairs((CMDoDc.gear and CMDoDc.gear.list) or {}) do
        if en.s == self.cat then
            rect(self, x, ry, w - S(8), rh, en.id == self.editId and K.panel2 or K.panel, 0.92)
            border(self, x, ry, w - S(8), rh, K.line, 1)
            local tex = entryTex(en)
            if tex then self:drawTextureScaledAspect(tex, x + S(6), ry + S(4), rh - S(8), rh - S(8), 1, 1, 1, 1) end
            CMUI.text(self, CMUI.fit(entryName(en), UIFont.Medium, w * 0.35), x + rh + S(6), ry + (rh - CMUI.fh(UIFont.Medium)) / 2, K.text, 1, UIFont.Medium)
            CMUI.text(self, CMUI.fit(itemsText(en), fs, w * 0.30), x + rh + S(12) + w * 0.35, ry + (rh - CMUI.fh(fs)) / 2, K.faint, 1, fs)
            CMUI.textR(self, (en.p or 0) == 0 and "FREE" or ("$" .. CMDoDc.num(en.p)), x + w - S(150), ry + (rh - CMUI.fh(UIFont.Medium)) / 2,
                (en.p or 0) == 0 and K.g or K.amber, 1, UIFont.Medium)
            mbtn(self, x + w - S(140), ry + S(6), S(60), rh - S(12), T("IGUI_CM_Dod_gearEditOne"), function()
                self.editId = en.id
                CMUI.setVal(self.ents.it, itemsText(en)); CMUI.setVal(self.ents.p, tostring(en.p or 0)); CMUI.setVal(self.ents.n, en.n or "")
            end, "ghost")
            mbtn(self, x + w - S(74), ry + S(6), S(60), rh - S(12), T("IGUI_CM_Dod_del"), function()
                CMC.send("dodGearDel", { id = en.id })
            end, "red")
            ry = ry + rh + S(4)
        end
    end
    self:endScroll(ry + off - ly)
    -- bottom: add what I wear, save the current picks as a preset, the presets with a delete each
    local by = y + h - S(76)
    mbtn(self, x, by, S(260), S(32), T("IGUI_CM_Dod_gearAddWorn"), function() self:addWorn() end, "on")
    place(self.ents.pre, x + S(270), by + (S(32) - fh) / 2, S(160))
    mbtn(self, x + S(440), by, S(220), S(32), T("IGUI_CM_Dod_gearPreset"), function()
        CMC.send("dodPresetSave", { n = CMUI.val(self.ents.pre), pk = self.pk })
        CMUI.setVal(self.ents.pre, "")
    end, "go", { disabled = not CM.any(self.pk) })
    local px = x
    local py = by + S(40)
    for _, pr in ipairs((CMDoDc.gear and CMDoDc.gear.pre) or {}) do
        local label = "x  " .. pr.n
        local pw = CMUI.tw(fs, label) + S(20)
        if px + pw > x + w then break end
        mbtn(self, px, py, pw, S(28), label, function() CMC.send("dodPresetDel", { id = pr.id }) end, "red")
        px = px + pw + S(6)
    end
end

-- ===================================================================== body
function AR:drawBody()
    local pad = S(18)
    local w, h = self.width, self.height
    local x, y = pad, self.headerH + S(12)
    local g = CMDoDc.gear
    local sn = CMDoDc.snap
    if not g then
        CMUI.text(self, T("IGUI_CM_Loading"), x, y, K.dim, 1, UIFont.Medium)
        self:showEntries(false)
        return
    end
    -- the list changed on the server (an admin edit): ask again
    if sn and sn.gearV and sn.gearV ~= g.v and CMC.ms() - (CMDoDc.gearAsk or 0) > 2000 then
        CMDoDc.gearAsk = CMC.ms()
        CMC.send("dodGearGet", {})
    end
    local modelW = math.floor(math.min(S(320), w * 0.28))
    local mainW = w - pad * 3 - modelW
    local footH = S(56)
    self:drawModel(w - pad - modelW, y, modelW, h - y - pad - footH - S(8))
    if self.edit then
        self:drawEditor(x, y, mainW, h - y - pad - footH - S(8))
        self:showEntries(true)
    else
        self:showEntries(false)
        self:drawPresets(x, y, mainW)
        local gy = y + S(42)
        local gh = h - gy - pad - footH - S(8)
        local slots = {}
        for _, s in ipairs(D.GEAR_SLOTS) do
            if #options(s.id) > 0 then slots[#slots + 1] = s end
        end
        if #slots == 0 then
            CMUI.text(self, T("IGUI_CM_Dod_gearEmpty"), x, gy + S(10), K.dim, 1, UIFont.Medium)
        else
            local cols = mainW > S(760) and 4 or 3
            local gap = S(10)
            local cw = math.floor((mainW - gap * (cols - 1) - S(8)) / cols)
            local ch = S(158)
            local off = self:beginScroll("gear", x, gy, mainW, gh)
            for i, s in ipairs(slots) do
                local cx = x + CM.mod(i - 1, cols) * (cw + gap)
                local cy = gy - off + math.floor((i - 1) / cols) * (ch + gap)
                self:card(s, cx, cy, cw, ch)
            end
            self:endScroll(math.ceil(#slots / cols) * (ch + gap))
        end
    end
    -- footer: what this kit costs, the wallet after it, close
    local fy = h - pad - footH
    rect(self, pad, fy - S(6), w - pad * 2, 1, K.line2, 1)
    local usd = cost(self.pk)
    local tm = team()
    local bal = (tm and tm.wallet) or CX and CX.bal or nil
    CMUI.para(self, T("IGUI_CM_Dod_gearHint"), x, fy + S(6), mainW * 0.55, K.faint, UIFont.Small, 2)
    local rx = w - pad
    local bw = S(200)
    mbtn(self, rx - bw, fy + S(6), bw, footH - S(12), T("IGUI_CM_Dod_close"), function() self:close() end, "go", { font = UIFont.Medium })
    rx = rx - bw - S(20)
    local over = bal and usd * 100 > bal
    CMUI.textR(self, T("IGUI_CM_Dod_gearTotal"), rx, fy + S(4), K.dim, 1, UIFont.Small)
    CMUI.textR(self, usd == 0 and "FREE" or ("$" .. CMDoDc.num(usd)), rx, fy + S(4) + CMUI.fh(UIFont.Small), over and K.red or K.text, 1, UIFont.Large)
    if bal then
        rx = rx - S(170)
        CMUI.textR(self, T("IGUI_CM_Dod_gearAfter"), rx, fy + S(4), K.dim, 1, UIFont.Small)
        CMUI.textR(self, over and T("IGUI_CM_Dod_gearShort") or money(bal - usd * 100), rx, fy + S(4) + CMUI.fh(UIFont.Small),
            over and K.red or K.amber, 1, UIFont.Large)
    end
    if sn and sn.admin then
        mbtn(self, rx - S(330), fy + S(10), S(140), footH - S(20), self.edit and T("IGUI_CM_Dod_gearPick") or T("IGUI_CM_Dod_gearEdit"),
            function() self.edit = not self.edit end, "red")
    end
end

function AR:onClosed()
    if self.model then
        pcall(function() self.model:setCharacter(nil); self:removeChild(self.model) end)
        self.model = nil
    end
    if CMDoDc.armory == self then CMDoDc.armory = nil end
end

function CMDoDc.openArmory(edit)
    if CMDoDc.armory then CMDoDc.armory:close() end
    CMUI.k = CMUI.fontScale()
    local w, h = CMUI.size(1240, 720)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local win = AR:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h, edit)
    win:show()
    CMDoDc.armory = win
    CMDoDc.gearAsk = CMC.ms()
    CMC.send("dodGearGet", {})
end

-- ===================================================================== putting the gear on after the landing
-- the server sent the items with the warp: once they are in the bag, wear the clothes, hold the primary
-- (the sidearm too when there is no primary); ammo and the rest stay in the bag
local function wearTick()
    local q = CMDoDc.wearQ
    if not q then return end
    local p = CMC.player()
    if not p or CMC.ms() > q.till then CMDoDc.wearQ = nil; return end
    if CMC.ms() < q.at then return end
    local items = p:getInventory():getItems()
    local left = {}
    for _, e in ipairs(q.list) do
        local item = nil
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it and it:getFullType() == e.t and not p:isEquipped(it) and not p:isEquippedClothing(it) and not q.used[it] then item = it; break end
        end
        if item then
            q.used[item] = true
            if instanceof(item, "HandWeapon") then
                if e.s == "gun" or (e.s == "side" and not q.gun) then
                    ISTimedActionQueue.add(ISEquipWeaponAction:new(p, item, 50, true, item:isTwoHandWeapon()))
                end
            elseif item:IsClothing() or (item:IsInventoryContainer() and item:canBeEquipped()) then
                ISTimedActionQueue.add(ISWearClothing:new(p, item))
            end
        else
            left[#left + 1] = e
        end
    end
    q.list = left
    if #left == 0 then CMDoDc.wearQ = nil end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CM.MOD or type(args) ~= "table" then return end
    if command == "dodgear" then
        CMDoDc.gear = args
        if CMDoDc.armory then CMDoDc.armory.dirty = true end
    elseif command == "dodwear" then
        local list, gun = {}, false
        for _, e in ipairs(args.w or {}) do
            if type(e) == "table" and type(e.t) == "string" then
                list[#list + 1] = { t = e.t, s = e.s }
                if e.s == "gun" then gun = true end
            end
        end
        CMDoDc.wearQ = { list = list, gun = gun, used = {}, at = CMC.ms() + D.WEAR_DELAY * 1000, till = CMC.ms() + 30000 }
    end
end)

local lastWear = 0
Events.OnTick.Add(function()
    local t = CMC.ms()
    if t - lastWear < 500 then return end
    lastWear = t
    local ok, err = pcall(wearTick)
    if not ok then CMDoDc.wearQ = nil; CM.log("dod wear error: " .. tostring(err)) end
    -- the armory belongs to the room: it closes when the team leaves it (deploy, gone)
    local a = CMDoDc.armory
    if a and not a.edit then
        local tm = team()
        if not tm or tm.phase ~= "room" then a:close() end
    end
end)

return CMDoDc
