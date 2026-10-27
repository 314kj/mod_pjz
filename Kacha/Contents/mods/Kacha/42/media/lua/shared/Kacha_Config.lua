--[[ ============================================================
     Kacha B42 [MP]  -  config + roll (SHARED)  by PIE

     SINGLE source of truth for config + roll. (Kacha_Shared.lua
     was a duplicate of this file and has been removed.)

     ROLL MODEL  =  LOCK%  +  separate SALT list
       - main items : each has an ABSOLUTE drop % (0..100). One roll
         on a 0..99.99 line, walk cumulative thresholds. The printed
         % IS the real %. Adding more items does NOT dilute anyone.
       - leftover band (100 - sum of main %) -> draw from d.salt,
         EVERY salt item equally weighted.
       - no salt set -> the leftover band returns nil = no reward.
   ============================================================ ]]
Kacha = Kacha or {}
local KEY = "Kacha"

-- 5 cabinet skins from set_aka_plus_pack.pack (set_aka_plus_0..4).
-- adding names with no matching sprite paints an invisible/broken tile,
-- which then fails isKacha detection -> "right-click does nothing".
-- NOTE: isKacha matches prefix "set_aka_", which also covers "set_aka_plus_".
Kacha.SKINS = { "set_aka_plus_0", "set_aka_plus_1", "set_aka_plus_2", "set_aka_plus_3", "set_aka_plus_4", "kacha_p2_0", "kacha_p2_1", "kacha_p2_2", "kacha_p2_3", "kacha_p2_4", "kacha_p2_5", "kacha_p2_8", "kacha_p2_9", "kacha_p2_10", "kacha_p2_11", "kacha_p2_12", "kacha_p2_13", "kacha_p2_14", "kacha_p2_15" }

-- machine detection (sprite-name prefix is the primary signal)
function Kacha.isKacha(wo)
    if not wo or not wo:getSprite() or not wo:getSprite():getName() then return false end
    local nm = wo:getSprite():getName()
    return (string.find(nm, "set_aka_") ~= nil) or (string.find(nm, "kacha_p2_") ~= nil)
end

function Kacha.getSqKacha(sq)
    if not sq then return nil end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if Kacha.isKacha(o) then return o end
    end
    return nil
end

-- SP detection (no client AND no server == true single-player)
function Kacha.isSP()
    return (not isClient()) and (not isServer())
end

-- ---- user-editable salt presets (runtime) -------------------------------
-- Presets are named bundles of item ids. They are stored globally (server
-- GlobalModData in MP, local GlobalModData in SP) and edited at runtime via
-- the Preset Editor. Kacha.Presets is the in-memory cache the UI reads.
Kacha.PRESET_KEY = "KachaPresets"
Kacha.Presets = Kacha.Presets or nil   -- nil until loaded from store

function Kacha.defaultPresets()
    -- kept tiny + valid; admins build their own. (no WaterBottleFull -> gone in B42)
    return {
        Food  = { "Base.Apple", "Base.Crisps", "Base.Crackers" },
        Tools = { "Base.Hammer", "Base.Screwdriver", "Base.Nails" }
    }
end

-- deep-ish copy of a {name={ids}} preset table (avoid shared refs over the wire)
function Kacha.copyPresets(src)
    local out = {}
    for name, ids in pairs(src or {}) do
        local t = {}
        for _, id in ipairs(ids) do t[#t + 1] = id end
        out[name] = t
    end
    return out
end

function Kacha.getPresets()
    if type(Kacha.Presets) ~= "table" then Kacha.Presets = Kacha.defaultPresets() end
    return Kacha.Presets
end

function Kacha.setPresetsTable(tbl)
    Kacha.Presets = (type(tbl) == "table") and tbl or Kacha.defaultPresets()
    if Kacha.onPresetsChanged then pcall(Kacha.onPresetsChanged) end
end

-- sorted list of preset names (for combo boxes)
function Kacha.presetNames()
    local names = {}
    for name, _ in pairs(Kacha.getPresets()) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- ---- preset editing (operate on the in-memory cache) --------------------
function Kacha.presetCreate(name)
    name = tostring(name or ""):gsub("%s+", "_")
    if name == "" then return false end
    local p = Kacha.getPresets()
    if not p[name] then p[name] = {} end
    return true
end

function Kacha.presetDelete(name)
    Kacha.getPresets()[name] = nil
end

function Kacha.presetItems(name) return Kacha.getPresets()[name] end

function Kacha.presetAddItem(name, id)
    local p = Kacha.getPresets()
    if not p[name] then return false end
    for _, e in ipairs(p[name]) do if e == id then return false end end
    table.insert(p[name], id)
    return true
end

function Kacha.presetRemoveItemAt(name, idx)
    local p = Kacha.getPresets()
    if p[name] and p[name][idx] then table.remove(p[name], idx) end
end

-- ---- preset persistence / sync ------------------------------------------
-- SP : read/write local GlobalModData directly (no network).
-- MP : ask / save via the server command channel (server is authoritative
--      and persists the GlobalModData, then broadcasts to all clients).
function Kacha.requestPresets()
    if Kacha.isSP() then
        local g = ModData.getOrCreate(Kacha.PRESET_KEY)
        if type(g.presets) ~= "table" then g.presets = Kacha.defaultPresets() end
        Kacha.setPresetsTable(Kacha.copyPresets(g.presets))
    else
        local pl = getPlayer and getPlayer()
        if pl then sendClientCommand(pl, "Kacha", "getPresets", {}) end
    end
end

function Kacha.persistPresets()
    local snapshot = Kacha.copyPresets(Kacha.getPresets())
    if Kacha.isSP() then
        local g = ModData.getOrCreate(Kacha.PRESET_KEY)
        g.presets = snapshot
    else
        local pl = getPlayer and getPlayer()
        if pl then sendClientCommand(pl, "Kacha", "savePresets", { presets = snapshot }) end
    end
end

-- tiers used by the ADD combo + spin legend (Salt is NOT here -> it is a
-- separate, hidden consolation pool, not a pickable main tier)
Kacha.TIERS = { "D", "C", "B", "A", "S", "SS", "SS+" }
Kacha.RARE  = { S = true, SS = true, ["SS+"] = true }

Kacha.COL = {
    bg     = { r = 0.05, g = 0.07, b = 0.11, a = 0.95 },
    accent = { r = 0.22, g = 0.74, b = 0.98, a = 1.00 },   -- cyan accent (borders/result)
    red    = { r = 0.16, g = 0.36, b = 0.90, a = 1.00 },   -- title bar = BLUE now (kept key name)
    text   = { r = 0.92, g = 0.95, b = 0.99, a = 1.00 },
    sub    = { r = 0.56, g = 0.63, b = 0.74, a = 1.00 },
    bad    = { r = 0.90, g = 0.35, b = 0.40, a = 1.00 },
    slot   = { r = 0.08, g = 0.13, b = 0.22, a = 0.96 },
    gold   = { r = 0.96, g = 0.77, b = 0.26, a = 1.00 },
    ok     = { r = 0.26, g = 0.75, b = 0.54, a = 1.00 }
}

Kacha.TIERCOL = {
    ["Salt"] = { r = 0.65, g = 0.65, b = 0.65 },
    ["D"]    = { r = 0.55, g = 0.55, b = 0.52 },
    ["C"]    = { r = 0.39, g = 0.60, b = 0.13 },
    ["B"]    = { r = 0.21, g = 0.54, b = 0.86 },
    ["A"]    = { r = 0.50, g = 0.46, b = 0.86 },
    ["S"]    = { r = 0.93, g = 0.62, b = 0.15 },
    ["SS"]   = { r = 0.83, g = 0.33, b = 0.49 },
    ["SS+"]  = { r = 0.89, g = 0.29, b = 0.29 }
}

function Kacha.tierColor(t)   return Kacha.TIERCOL[t] or Kacha.TIERCOL["D"] end
function Kacha.itemExists(ft) return getScriptManager():FindItem(ft) ~= nil end
function Kacha.displayName(ft)
    local it = getScriptManager():FindItem(ft)
    return (it and it:getDisplayName()) or string.match(ft or "", "%.([^.]+)$") or "?"
end

-- staff ที่จัดการตู้ได้ (แก้รายชื่อตรงนี้ได้เลย)
local KACHA_STAFF = {
    admin     = true,
    moderator = true,
    gm        = true,
    -- observer = false,  -- ดูได้แต่แก้ไม่ได้ -> ไม่ให้
    -- priority = false,  -- user ธรรมดาที่ login ก่อน -> ไม่ให้
    -- user     = false,  -- ไม่ให้
}

function Kacha.isAkaAdmin()
    if Kacha.isSP() then return true end
    local pl = getPlayer and getPlayer()
    if not pl or not pl.getAccessLevel then return false end
    local lvl = tostring(pl:getAccessLevel() or ""):lower()   -- บังคับพิมพ์เล็ก
    return KACHA_STAFF[lvl] == true
end

-- ---- config (with salt list) --------------------------------------------
function Kacha.getConfig(obj)
    local md = obj:getModData()
    if type(md[KEY]) ~= "table" then
        md[KEY] = { winrate = 100, tokenType = "coin", tokenItem = "Base.KachaCoin",
                    costPerRoll = 1, skin = "set_aka_plus_0", items = {}, salt = {}, history = {} }
        obj:transmitModData()
    end
    -- migrate older configs that predate the salt list
    local d = md[KEY]
    if type(d.items)   ~= "table" then d.items   = {} end
    if type(d.salt)    ~= "table" then d.salt    = {} end
    if type(d.history) ~= "table" then d.history = {} end
    return d
end

function Kacha.objKey(obj)
    local sq = obj and obj.getSquare and obj:getSquare()
    if not sq then return nil end
    return sq:getX() .. "_" .. sq:getY() .. "_" .. sq:getZ()
end

-- MP: mirror the roll-relevant config to the server registry keyed by coords,
-- so the server can spin even if it can't re-find the placed tile object.
function Kacha.pushCfg(obj)
    if not (isClient and isClient()) then return end
    local sq = obj and obj.getSquare and obj:getSquare()
    if not sq then return end
    local d = Kacha.getConfig(obj)
    sendClientCommand(getPlayer(), "Kacha", "saveCfg", {
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        entries = d.entries or {}, salt = d.salt or {},
        tokenType = d.tokenType, tokenItem = d.tokenItem,
        costPerRoll = d.costPerRoll, skin = d.skin,
    })
end

function Kacha.commit(obj)
    if obj and obj.transmitModData then obj:transmitModData() end
    Kacha.pushCfg(obj)
end
function Kacha.setField(obj, k, v) local d = Kacha.getConfig(obj); d[k] = v; Kacha.commit(obj) end

-- ---- main item pool (absolute drop %) -----------------------------------
-- getters self-repair a missing field so an OLD saved machine (modData
-- created before the salt list existed) can never crash ipairs.
function Kacha.getItems(obj)
    local d = Kacha.getConfig(obj)
    if type(d.items) ~= "table" then d.items = {} end
    return d.items
end

-- ==== 2-TIER ENTRIES ====================================================
-- entry = { rate = <abs %>, tier = "S", ids = { "Base.A", "Base.B", ... } }
-- โดน rate% ของ entry ก่อน -> แล้วสุ่มของข้างในแบ่งเท่ากัน (33/33/33)
-- migrate จาก flat d.items เดิม (แต่ละอัน = entry 1 id) แบบ backward compatible.
function Kacha.getEntries(obj)
    local d = Kacha.getConfig(obj)
    if type(d.entries) ~= "table" then
        d.entries = {}
        for _, it in ipairs(d.items or {}) do
            d.entries[#d.entries + 1] = { rate = tonumber(it.rate) or 0, tier = it.tier or "D", ids = { it.id } }
        end
        Kacha.commit(obj)
    end
    return d.entries
end

-- เพิ่มของ: ถ้ามี entry ที่ tier+rate เท่ากันอยู่แล้ว -> เข้ากลุ่มเดิม (แบ่งเท่ากัน)
-- ไม่งั้นตั้ง entry ใหม่. นี่คือวิธีสร้าง 2-tier โดยไม่ต้องมี UI จัดกลุ่มแยก.
function Kacha.addItem(obj, fullType, tier, rate)
    local d = Kacha.getConfig(obj)
    Kacha.getEntries(obj)
    rate = math.floor(tonumber(rate) or 0)
    if rate < 0 then rate = 0 elseif rate > 100 then rate = 100 end
    tier = tier or "D"
    for _, e in ipairs(d.entries) do
        if e.tier == tier and (tonumber(e.rate) or 0) == rate then
            for _, id in ipairs(e.ids) do if id == fullType then Kacha.commit(obj); return end end
            table.insert(e.ids, fullType); Kacha.commit(obj); return
        end
    end
    table.insert(d.entries, { rate = rate, tier = tier, ids = { fullType } })
    Kacha.commit(obj)
end

-- ลบ id ตัวเดียวออกจาก entry (entry ว่างแล้วลบทิ้ง)
function Kacha.removeEntryId(obj, ei, ii)
    local d = Kacha.getConfig(obj)
    local e = d.entries and d.entries[ei]; if not e then return end
    if e.ids[ii] then table.remove(e.ids, ii) end
    if #e.ids == 0 then table.remove(d.entries, ei) end
    Kacha.commit(obj)
end

-- ---- explicit prize-group ops (group-centric admin UI) ----
function Kacha.addGroup(obj, rate, tier)
    local d = Kacha.getConfig(obj); Kacha.getEntries(obj)
    rate = math.max(0, math.min(100, math.floor(tonumber(rate) or 1)))
    table.insert(d.entries, { rate = rate, tier = tier or "C", ids = {} })
    Kacha.commit(obj); return #d.entries
end
function Kacha.removeGroup(obj, ei)
    local d = Kacha.getConfig(obj)
    if d.entries and d.entries[ei] then table.remove(d.entries, ei); Kacha.commit(obj) end
end
function Kacha.setGroupRate(obj, ei, rate)
    local d = Kacha.getConfig(obj); local e = d.entries and d.entries[ei]
    if e then e.rate = math.max(0, math.min(100, math.floor(tonumber(rate) or 0))); Kacha.commit(obj) end
end
function Kacha.setGroupTier(obj, ei, tier)
    local d = Kacha.getConfig(obj); local e = d.entries and d.entries[ei]
    if e then e.tier = tier or "C"; Kacha.commit(obj) end
end
function Kacha.addItemToGroup(obj, ei, id)
    local d = Kacha.getConfig(obj); local e = d.entries and d.entries[ei]
    if not e or not id or id == "" then return false end
    if not Kacha.itemExists(id) then return false end
    for _, x in ipairs(e.ids) do if x == id then return true end end
    table.insert(e.ids, id); Kacha.commit(obj); return true
end
function Kacha.removeLastFromGroup(obj, ei)
    local d = Kacha.getConfig(obj); local e = d.entries and d.entries[ei]
    if e and #e.ids > 0 then table.remove(e.ids); Kacha.commit(obj) end
end

-- remove a set of item-indices from a group (used by the double-click editor)
function Kacha.removeItemsFromGroup(obj, ei, iis)
    local d = Kacha.getConfig(obj); local e = d.entries and d.entries[ei]; if not e then return end
    table.sort(iis, function(a, b) return a > b end)   -- descending so indices stay valid
    for _, ii in ipairs(iis) do if e.ids[ii] then table.remove(e.ids, ii) end end
    if #e.ids == 0 then
        for gi, g in ipairs(d.entries) do if g == e then table.remove(d.entries, gi); break end end
    end
    Kacha.commit(obj)
end

-- แถวสำหรับหน้า Contents/Odds: rate, tier, eff(%จริงต่อชิ้น), รายชื่อของ + salt band
function Kacha.buildOdds(obj)
    local rows = {}
    for _, e in ipairs(Kacha.getEntries(obj)) do
        local n = #(e.ids or {})
        local eff = (n > 0) and ((tonumber(e.rate) or 0) / n) or 0
        local names = {}
        for _, id in ipairs(e.ids or {}) do names[#names + 1] = { id = id, name = Kacha.displayName(id) } end
        rows[#rows + 1] = { rate = tonumber(e.rate) or 0, tier = e.tier or "D", eff = eff, items = names }
    end
    local salt = 100 - Kacha.mainTotal(obj); if salt < 0 then salt = 0 end
    return rows, salt
end

-- ---- salt pool (separate list, equal weight, no rate) -------------------
-- Salt is filled ONLY by loading a preset. No per-item add (by design).
function Kacha.getSalt(obj)
    local d = Kacha.getConfig(obj)
    if type(d.salt) ~= "table" then d.salt = {} end
    return d.salt
end

-- internal: append one salt id (used by loadPreset)
local function pushSalt(d, fullType)
    table.insert(d.salt, { id = fullType, tier = "Salt" })
end

function Kacha.clearSalt(obj)
    local d = Kacha.getConfig(obj)
    d.salt = {}
    d.saltPreset = nil
    Kacha.commit(obj)
end

-- replace the machine's salt with the contents of a named preset.
-- invalid item ids are skipped (returns valid, skipped counts).
function Kacha.loadPreset(obj, presetName)
    local ids = Kacha.getPresets()[presetName]
    if not ids then return 0, 0 end
    local d = Kacha.getConfig(obj)
    d.salt = {}
    local good, bad = 0, 0
    for _, id in ipairs(ids) do
        if Kacha.itemExists(id) then pushSalt(d, id); good = good + 1
        else bad = bad + 1; print("[Kacha] preset '" .. presetName .. "' skip invalid id: " .. tostring(id)) end
    end
    d.saltPreset = presetName
    Kacha.commit(obj)
    return good, bad
end

-- sum of main % (for the admin "leftover" readout)
function Kacha.mainTotal(obj)
    local t = 0
    for _, e in ipairs(Kacha.getEntries(obj)) do t = t + (tonumber(e.rate) or 0) end
    return t
end

-- ==== COIN REGISTRY (5 สี + Cash + coin เดิม) ============================
-- แต่ละตู้ผูกได้ 1 อย่าง (admin เลือกใน Setting). tokenItem เก็บชนิดที่ใช้จ่าย.
Kacha.COINS = {
    { key = "cash",   item = "Base.Money",          label = "Cash",   icon = "Item_Money",           col = { r = 0.29, g = 0.87, b = 0.50 } },
    { key = "coin",   item = "Base.KachaCoin",      label = "Coin",   icon = "Item_KachaCoin",       col = { r = 0.96, g = 0.78, b = 0.30 } },
    { key = "red",    item = "Base.KachaCoinRed",   label = "Red",    icon = "Item_KachaCoinRed",    col = { r = 1.00, g = 0.30, b = 0.42 } },
    { key = "cyan",   item = "Base.KachaCoinCyan",  label = "Cyan",   icon = "Item_KachaCoinCyan",   col = { r = 0.22, g = 0.90, b = 1.00 } },
    { key = "purple", item = "Base.KachaCoinPurple",label = "Purple", icon = "Item_KachaCoinPurple", col = { r = 0.63, g = 0.42, b = 1.00 } },
    { key = "gold",   item = "Base.KachaCoinGold",  label = "Gold",   icon = "Item_KachaCoinGold",   col = { r = 1.00, g = 0.81, b = 0.29 } },
    { key = "lime",   item = "Base.KachaCoinLime",  label = "Lime",   icon = "Item_KachaCoinLime",   col = { r = 0.49, g = 1.00, b = 0.42 } },
}
function Kacha.coinByItem(item)
    for _, c in ipairs(Kacha.COINS) do if c.item == item then return c end end
    return Kacha.COINS[2]   -- default Coin
end
function Kacha.setToken(obj, coinKey)
    for _, c in ipairs(Kacha.COINS) do
        if c.key == coinKey then
            Kacha.setField(obj, "tokenType", (c.key == "cash") and "cash" or "coin")
            Kacha.setField(obj, "tokenItem", c.item)
            return
        end
    end
end

-- default themed names per skin (by dominant colour) - admin can override
Kacha.SKIN_NAMES = {
    ["set_aka_plus_0"] = "Red",   ["set_aka_plus_1"] = "Crimson", ["set_aka_plus_2"] = "Gold",
    ["set_aka_plus_3"] = "Steel", ["set_aka_plus_4"] = "Amber",
    ["kacha_p2_0"] = "Cache",  ["kacha_p2_1"] = "Depot",   ["kacha_p2_2"] = "Mystery",
    ["kacha_p2_3"] = "Vault",  ["kacha_p2_4"] = "Arsenal", ["kacha_p2_5"] = "Cosmic",
    ["kacha_p2_8"] = "Crystal",["kacha_p2_9"] = "Neon",    ["kacha_p2_10"] = "Ruby",
    ["kacha_p2_11"] = "Royal", ["kacha_p2_12"] = "Jade",   ["kacha_p2_13"] = "Aqua",
    ["kacha_p2_14"] = "Rose",  ["kacha_p2_15"] = "VIP",
}

-- custom machine name (admin-set); blank if not named
function Kacha.machineName(obj)
    local d = Kacha.getConfig(obj)
    if d.name and d.name ~= "" then return d.name end
    return ""
end

-- decorative mushroom-cat reel frames (media/ui/, loads via getTexture)
Kacha._mush = nil
function Kacha.mushTextures()
    if Kacha._mush and #Kacha._mush > 0 then return Kacha._mush end
    local t = {}
    for i = 0, 7 do local tx = Kacha.itemTexture("Base.KachaFX_" .. i); if tx then t[#t + 1] = tx end end
    if #t > 0 then Kacha._mush = t end
    return t
end

-- item icon texture (reliable: item-backed, unlike loose media/textures/ png)
function Kacha.itemTexture(id)
    if not id then return nil end
    local sm = getScriptManager and getScriptManager()
    local it = sm and sm:FindItem(id)
    if it then
        local ok, t = pcall(function() return it:getNormalTexture() end)
        if ok and t then return t end
    end
    return nil
end

-- icons for the spin reel (item-backed textures = reliable)
function Kacha.spinPool(obj)
    local d = Kacha.getConfig(obj)
    local pool = {}
    for _, e in ipairs(d.entries or {}) do
        for _, id in ipairs(e.ids or {}) do
            local t = Kacha.itemTexture(id); if t then pool[#pool + 1] = { tex = t, id = id } end
        end
    end
    for _, slt in ipairs(d.salt or {}) do
        local t = Kacha.itemTexture(slt.id); if t then pool[#pool + 1] = { tex = t, id = slt.id } end
    end
    return pool
end


-- robust coin texture: loose file first, then the item's own icon
function Kacha.coinTexture(coin)
    if not coin then return nil end
    local t = getTexture(coin.icon)
    if t then return t end
    local sm = getScriptManager and getScriptManager()
    local it = sm and sm:FindItem(coin.item)
    if it then
        local ok, nt = pcall(function() return it:getNormalTexture() end)
        if ok and nt then return nt end
    end
    return nil
end

-- sprite name of the placed machine (dynamic skin)
function Kacha.machineSkin(obj)
    if obj and obj.getSprite and obj:getSprite() and obj:getSprite():getName() then
        return obj:getSprite():getName()
    end
    local d = Kacha.getConfig(obj); return d.skin or "set_aka_plus_0"
end

-- ---- history (S / SS / SS+ only) ----------------------------------------
function Kacha.getHistory(obj)
    local d = Kacha.getConfig(obj)
    if type(d.history) ~= "table" then d.history = {} end
    return d.history
end

function Kacha.logRare(obj, who, name, tier)
    if not Kacha.RARE[tier] then return end
    local d = Kacha.getConfig(obj)
    table.insert(d.history, 1, { name = tostring(name), tier = tier, who = tostring(who), when = "Just now" })
    while #d.history > 20 do table.remove(d.history) end
    Kacha.commit(obj)
end

-- ---- 2-TIER roll + equal-salt fallback ----------------------------------
-- ONE signature: rollOne(obj). Used by BOTH server and SP.
-- ชั้น 1: เดิน entry สะสมบนเส้น 0..99.99 -> โดน entry ไหน
-- ชั้น 2: สุ่มของข้างใน entry นั้นแบบแบ่งเท่ากัน
-- roll from a raw cfg table (entries + salt). Server uses this with the
-- coord-registry cfg so spinning never needs the placed tile object.
function Kacha.rollFromCfg(d)
    if type(d) ~= "table" then return nil end
    local entries = d.entries or {}
    local salt    = d.salt or {}
    local r   = ZombRand(10000) / 100.0          -- 0.00 .. 99.99
    local acc = 0
    for _, e in ipairs(entries) do
        acc = acc + (tonumber(e.rate) or 0)
        if r < acc then
            local ids = e.ids or {}
            if #ids > 0 then
                local id = ids[ZombRand(#ids) + 1]
                return { id = id, tier = e.tier or "D", name = Kacha.displayName(id) }
            end
            return nil
        end
    end
    if #salt > 0 then
        local s = salt[ZombRand(#salt) + 1]
        return { id = s.id, tier = s.tier or "D", name = s.name or Kacha.displayName(s.id), salt = true }
    end
    return nil
end

function Kacha.rollOne(obj)
    local d = Kacha.getConfig(obj)
    Kacha.getEntries(obj)   -- ensure migrated before rolling
    return Kacha.rollFromCfg(d)
end

Kacha.__feed(2, 7)        -- restored seal fragment (frag1=65, frag2=7 -> b1351651292)
Kacha.__mark("config")
