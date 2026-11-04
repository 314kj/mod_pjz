-- Cookie Mission - shared core
-- by lookchinnoi (AKA) for CookieCheetah
-- Daily mission board: 3 cards a day (easy / medium / very hard), each one a real
-- building somewhere in Knox County. Accept = warp there, finish = warp home.
-- NOTE: keep every .lua file ASCII only. Player-facing text lives in Translate/*/IG_UI.json
-- NOTE: Kahlua (PZ Lua) has no next(), and % keeps the sign of the left side: use CM.any / CM.mod

CM = CM or {}
CM.MOD = "CookieMission"
CM.VERSION = "1.0.0"
CM.BUILD = "cm-261104-a1c7e3"
CM.CACHE_TYPE = "CookieMission.SupplyCache"

-- ===================================================================== env
function CM.any(t)
    if type(t) ~= "table" then return false end
    for _ in pairs(t) do return true end
    return false
end

function CM.mod(a, b)
    return a - math.floor(a / b) * b
end

function CM.isSP() return (not isServer()) and (not isClient()) end
function CM.isMPClient() return isClient() and not isServer() end

function CM.log(msg)
    print("[CookieMission] " .. tostring(msg))
end

-- ===================================================================== tables / numbers / strings
function CM.copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = CM.copy(x) end
    return o
end

function CM.count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

function CM.sortedKeys(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function CM.num(v, def)
    local n = tonumber(v)
    if n == nil or n ~= n then return def end
    return n
end

function CM.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function CM.int(v, def, lo, hi)
    local n = CM.num(v, def)
    if n == nil then return nil end
    n = math.floor(n + 0.5)
    if lo and n < lo then n = lo end
    if hi and n > hi then n = hi end
    return n
end

function CM.pad2(n)
    n = math.floor(CM.num(n, 0))
    if n < 10 then return "0" .. tostring(n) end
    return tostring(n)
end

function CM.str(v, max)
    local s = tostring(v or "")
    if max and #s > max then s = string.sub(s, 1, max) end
    return s
end

function CM.trim(s)
    s = string.gsub(tostring(s or ""), "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

-- Kahlua strings are UTF-16 (one Thai letter = one unit). Under a byte-string Lua
-- (the offline test harness) multibyte UTF-8 must not be split; the harness sets this flag.
CM.BYTE_STRINGS = CM.BYTE_STRINGS or false

function CM.charEnd(s, i)
    if not CM.BYTE_STRINGS then return i end
    local b = string.byte(s, i)
    if not b or b < 192 then return i end
    if b >= 240 then return i + 3 elseif b >= 224 then return i + 2 end
    return i + 1
end

function CM.safeCut(s, n)
    if not CM.BYTE_STRINGS then return n end
    while n > 0 do
        local nb = string.byte(s, n + 1)
        if nb and nb >= 128 and nb < 192 then n = n - 1 else break end
    end
    return n
end

function CM.ukey(name)
    if name == nil then return "" end
    return string.lower(tostring(name))
end

-- split "a;b; c" -> { "a", "b", "c" } (empty parts dropped)
function CM.split(s, sep)
    local out = {}
    s = tostring(s or "")
    sep = sep or ";"
    local pos = 1
    while true do
        local i = string.find(s, sep, pos, true)
        local part = CM.trim(string.sub(s, pos, (i or 0) - 1))
        if i == nil then part = CM.trim(string.sub(s, pos)) end
        if part ~= "" then out[#out + 1] = part end
        if not i then break end
        pos = i + #sep
    end
    return out
end

-- safe Java method call: missing method or error -> nil
function CM.call(o, m, ...)
    if o == nil then return nil end
    local ok0, f = pcall(function() return o[m] end)
    if not ok0 or f == nil then return nil end
    local ok, r = pcall(f, o, ...)
    if ok then return r end
    return nil
end

-- ===================================================================== time (real clock, epoch seconds)
CM.DAY = 86400

function CM.now()
    return math.floor(CM.num(os.time(), 0))
end

-- days since 1970-01-01 -> y, m, d   (H. Hinnant civil_from_days)
function CM.civil(days)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m
    if mp < 10 then m = mp + 3 else m = mp - 9 end
    if m <= 2 then y = y + 1 end
    return y, m, d
end

-- mission day: changes every day at ResetHour local time (UtcOffset)
function CM.dayKey(ts)
    local off = CM.sv("UtcOffset", 7)
    local rh = CM.sv("ResetHour", 6)
    local t = math.floor(CM.num(ts, 0)) + math.floor((off - rh) * 3600)
    return math.floor(t / 86400)
end

-- epoch seconds when the given mission day ends (= next reset)
function CM.dayEnd(day)
    local off = CM.sv("UtcOffset", 7)
    local rh = CM.sv("ResetHour", 6)
    return (day + 1) * 86400 - math.floor((off - rh) * 3600)
end

function CM.dayText(day)
    -- the mission day starts on the calendar day of its reset hour
    local y, m, d = CM.civil(day)
    return CM.pad2(d) .. "/" .. CM.pad2(m) .. "/" .. tostring(y)
end

function CM.clock(sec)
    sec = math.max(0, math.floor(CM.num(sec, 0)))
    local h = math.floor(sec / 3600)
    local m = math.floor(CM.mod(sec, 3600) / 60)
    local s = CM.mod(sec, 60)
    if h > 0 then return tostring(h) .. ":" .. CM.pad2(m) .. ":" .. CM.pad2(s) end
    return tostring(m) .. ":" .. CM.pad2(s)
end

-- ===================================================================== sandbox
CM.DEFAULTS = {
    ResetHour = 6, UtcOffset = 7, Cooldown = 3, ReturnDelay = 20, MinPresence = 60,
    LateJoinMax = 85, LeaveDistance = 60, LeaveSeconds = 20, Grace = 20, CleanupZombies = true,
    EmptyAbort = 90, PinChance = 40, TypeKill = true, TypeGang = true, TypeFind = true, TypeSurvive = true,
    GangOutfits = "PrivateMilitia;Biker;Punk;Survivalist;ArmyCamoGreen",
    ExcludeTowns = "",
    EasyCap = 4, MediumCap = 6, HardCap = 8,
    EasyTime = 15, MediumTime = 20, HardTime = 25,
    EasyKills = 60, MediumKills = 150, HardKills = 300,
    EasyGang = 25, MediumGang = 50, HardGang = 90,
    EasyCaches = 3, MediumCaches = 5, HardCaches = 7,
    EasySurvive = 5, MediumSurvive = 8, HardSurvive = 12,
    EasyAlive = 35, MediumAlive = 70, HardAlive = 120,
    EasyRate = 40, MediumRate = 80, HardRate = 150,
}

function CM.sv(name, def)
    if def == nil then def = CM.DEFAULTS[name] end
    local sv = SandboxVars and SandboxVars.CookieMission
    if sv and sv[name] ~= nil then
        if type(def) == "number" then return CM.num(sv[name], def) end
        return sv[name]
    end
    return def
end

-- ===================================================================== tiers / types
CM.TIER_NAME = { "Easy", "Medium", "Hard" }
CM.TYPES = { "kill", "gang", "find", "survive" }
CM.TYPE_OPT = { kill = "TypeKill", gang = "TypeGang", find = "TypeFind", survive = "TypeSurvive" }

-- bounding-box area (tiles) and ground-floor room count a building needs for each tier
CM.SIZE = {
    { min = 120, max = 900, rooms = 2 },
    { min = 350, max = 2600, rooms = 4 },
    { min = 1100, max = 999999, rooms = 6 },
}

function CM.tierVal(tier, what)
    local n = CM.TIER_NAME[tier] or "Easy"
    return CM.sv(n .. what)
end

-- the goal number of a card (kills / gang kills / caches / seconds to hold)
function CM.goalFor(tier, typ)
    if typ == "kill" then return CM.int(CM.tierVal(tier, "Kills"), 60, 1, 5000) end
    if typ == "gang" then return CM.int(CM.tierVal(tier, "Gang"), 25, 1, 2000) end
    if typ == "find" then return CM.int(CM.tierVal(tier, "Caches"), 3, 1, 20) end
    if typ == "survive" then return CM.int(CM.tierVal(tier, "Survive"), 5, 1, 120) * 60 end
    return 1
end

function CM.limitFor(tier, typ)
    local lim = CM.int(CM.tierVal(tier, "Time"), 15, 3, 240) * 60
    if typ == "survive" then lim = math.max(lim, CM.goalFor(tier, typ) + 180) end
    return lim
end

function CM.capFor(tier)
    return CM.int(CM.tierVal(tier, "Cap"), 4, 1, 32)
end

function CM.typeOn(typ)
    local o = CM.TYPE_OPT[typ]
    if not o then return false end
    return CM.sv(o) ~= false
end

-- ===================================================================== zones
-- zone = building rect; "in" = within pad tiles of it on any floor
function CM.inRect(site, x, y, pad)
    if not site then return false end
    pad = pad or 0
    return x >= site.x1 - pad and x <= site.x2 + pad and y >= site.y1 - pad and y <= site.y2 + pad
end

-- distance from a point to the building rect (0 inside)
function CM.rectDist(site, x, y)
    if not site then return 99999 end
    local dx, dy = 0, 0
    if x < site.x1 then dx = site.x1 - x elseif x > site.x2 then dx = x - site.x2 end
    if y < site.y1 then dy = site.y1 - y elseif y > site.y2 then dy = y - site.y2 end
    return math.sqrt(dx * dx + dy * dy)
end

-- ===================================================================== places
-- approximate vanilla town boxes (only used to sample buildings and to name them)
CM.TOWNS = {
    { n = "Muldraugh",      x1 = 10500, y1 = 9300,  x2 = 11000, y2 = 10600 },
    { n = "West Point",     x1 = 11300, y1 = 6600,  x2 = 12200, y2 = 7300 },
    { n = "Riverside",      x1 = 5800,  y1 = 5000,  x2 = 6800,  y2 = 5600 },
    { n = "Rosewood",       x1 = 7900,  y1 = 11300, x2 = 8500,  y2 = 11900 },
    { n = "March Ridge",    x1 = 9800,  y1 = 12500, x2 = 10400, y2 = 13000 },
    { n = "Valley Station", x1 = 12700, y1 = 4600,  x2 = 13700, y2 = 5600 },
    { n = "Louisville",     x1 = 12100, y1 = 1300,  x2 = 14300, y2 = 4000 },
    { n = "Fallas Lake",    x1 = 7100,  y1 = 8100,  x2 = 7450,  y2 = 8450 },
}

function CM.townAt(x, y)
    local best, bestD = nil, 500
    for i = 1, #CM.TOWNS do
        local t = CM.TOWNS[i]
        local d = CM.rectDist(t, x, y)
        if d < bestD then best = t.n; bestD = d end
    end
    return best or "Kentucky"
end

-- room name -> building kind (first match wins, most specific first)
CM.KINDS = {
    { k = "prison",    m = { "prison", "cell", "jail" } },
    { k = "military",  m = { "military", "army", "armystorage" } },
    { k = "police",    m = { "police" } },
    { k = "hospital",  m = { "hospital", "medical", "medclinic", "operating" } },
    { k = "school",    m = { "school", "classroom", "gym", "lecture" } },
    { k = "mall",      m = { "mall", "clothingstore", "shoestore", "jewelry" } },
    { k = "warehouse", m = { "warehouse", "storageunit", "factory", "industrial", "loading" } },
    { k = "fire",      m = { "fire" } },
    { k = "store",     m = { "gigamart", "grocery", "store", "shop", "pharmacy", "liquor", "gunstore", "zippee" } },
    { k = "food",      m = { "restaurant", "kitchen_crepe", "pizza", "burger", "diner", "cafe", "bakery", "spiffo", "bar" } },
    { k = "church",    m = { "church", "chapel" } },
    { k = "office",    m = { "office", "bank", "post", "library" } },
    { k = "motel",     m = { "motel", "hotel" } },
}

function CM.kindOf(roomNames)
    for i = 1, #CM.KINDS do
        local e = CM.KINDS[i]
        for _, rn in ipairs(roomNames or {}) do
            local s = string.lower(tostring(rn))
            for j = 1, #e.m do
                if string.find(s, e.m[j], 1, true) then return e.k end
            end
        end
    end
    return "house"
end

-- ===================================================================== buildings
-- BuildingDef -> site table (or nil when the def is unusable)
function CM.siteFromDef(def)
    if not def then return nil end
    local x1 = CM.call(def, "getX")
    local y1 = CM.call(def, "getY")
    if not x1 or not y1 then return nil end
    local x2 = CM.call(def, "getX2")
    local y2 = CM.call(def, "getY2")
    if not x2 then x2 = x1 + (CM.call(def, "getW") or 1) end
    if not y2 then y2 = y1 + (CM.call(def, "getH") or 1) end
    x2 = x2 - 1; y2 = y2 - 1
    local rooms = CM.call(def, "getRooms")
    local names, nGround = {}, 0
    local best, bestA = nil, -1
    local maxZ = 0
    if rooms then
        local n = CM.call(rooms, "size") or 0
        for i = 0, n - 1 do
            local r = rooms:get(i)
            local rz = CM.call(r, "getZ") or 0
            local rn = CM.call(r, "getName")
            if rn then names[#names + 1] = tostring(rn) end
            if rz > maxZ then maxZ = rz end
            if rz == 0 then
                nGround = nGround + 1
                local rx, ry = CM.call(r, "getX"), CM.call(r, "getY")
                local rx2, ry2 = CM.call(r, "getX2"), CM.call(r, "getY2")
                if rx and ry and rx2 and ry2 then
                    local a = (rx2 - rx) * (ry2 - ry)
                    if a > bestA then
                        bestA = a
                        best = { x = math.floor((rx + rx2 - 1) / 2), y = math.floor((ry + ry2 - 1) / 2) }
                    end
                end
            end
        end
    end
    local site = {
        bid = tostring(x1) .. "_" .. tostring(y1),
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        area = (x2 - x1 + 1) * (y2 - y1 + 1),
        rooms = nGround, floors = maxZ + 1,
        kind = CM.kindOf(names),
        town = CM.townAt(math.floor((x1 + x2) / 2), math.floor((y1 + y2) / 2)),
    }
    if best then site.ax = best.x; site.ay = best.y
    else site.ax = math.floor((x1 + x2) / 2); site.ay = math.floor((y1 + y2) / 2) end
    site.az = 0
    return site
end

function CM.siteFits(site, tier)
    local sz = CM.SIZE[tier]
    if not site or not sz then return false end
    return site.area >= sz.min and site.area <= sz.max and (site.rooms or 0) >= sz.rooms
end

-- the building under a world position (client or server), as a site table
function CM.siteAt(x, y)
    local w = getWorld and getWorld()
    local mg = w and CM.call(w, "getMetaGrid")
    local def = mg and CM.call(mg, "getBuildingAt", math.floor(x), math.floor(y))
    return def and CM.siteFromDef(def) or nil
end

-- ===================================================================== rewards
-- pools: { {t = fullType, w = weight, n = count} }; the server drops entries whose item does not exist
CM.POOLS = { "melee", "guns", "legend", "meds", "medsplus" }
CM.DEFAULT_POOLS = {
    melee = {
        { t = "Base.Machete", w = 10, n = 1 }, { t = "Base.Katana", w = 4, n = 1 },
        { t = "Base.Crowbar", w = 10, n = 1 }, { t = "Base.Axe", w = 8, n = 1 },
        { t = "Base.WoodAxe", w = 6, n = 1 }, { t = "Base.Sledgehammer", w = 4, n = 1 },
        { t = "Base.BaseballBat_Nails", w = 6, n = 1 }, { t = "Base.HuntingKnife", w = 8, n = 1 },
    },
    guns = {
        { t = "Base.Pistol", w = 10, n = 1 }, { t = "Base.Pistol2", w = 8, n = 1 },
        { t = "Base.Pistol3", w = 5, n = 1 }, { t = "Base.Revolver", w = 8, n = 1 },
        { t = "Base.Revolver_Long", w = 4, n = 1 }, { t = "Base.Shotgun", w = 7, n = 1 },
        { t = "Base.DoubleBarrelShotgun", w = 6, n = 1 }, { t = "Base.VarmintRifle", w = 5, n = 1 },
        { t = "Base.HuntingRifle", w = 4, n = 1 }, { t = "Base.AssaultRifle", w = 2, n = 1 },
        { t = "Base.AssaultRifle2", w = 2, n = 1 },
    },
    legend = {},   -- filled at server boot from installed "Legendary Tactical" weapons when empty
    meds = {
        { t = "Base.Bandage", w = 10, n = 2 }, { t = "Base.AlcoholBandage", w = 8, n = 1 },
        { t = "Base.Pills", w = 8, n = 1 }, { t = "Base.Disinfectant", w = 6, n = 1 },
        { t = "Base.SutureNeedle", w = 6, n = 2 }, { t = "Base.Splint", w = 4, n = 1 },
        { t = "Base.AlcoholWipes", w = 6, n = 2 },
    },
    medsplus = {
        { t = "Base.Antibiotics", w = 10, n = 1 }, { t = "Base.SutureNeedleHolder", w = 5, n = 1 },
        { t = "Base.PillsBeta", w = 6, n = 1 }, { t = "Base.Tweezers", w = 5, n = 1 },
        { t = "Base.FirstAidKit", w = 3, n = 1 },
    },
}

-- what one finished card gives each player:
-- p = pool, r = rolls, c = chance % per roll, f = fallback pool if p is empty, alt = pool when the chance fails
CM.DROPS = {
    { { p = "melee", r = 1, c = 100 }, { p = "meds", r = 2, c = 100 } },
    { { p = "guns", r = 1, c = 60, f = "melee", alt = "melee" }, { p = "meds", r = 3, c = 100 },
      { p = "medsplus", r = 1, c = 50 } },
    { { p = "guns", r = 1, c = 100, f = "melee" }, { p = "legend", r = 1, c = 25 }, { p = "meds", r = 3, c = 100 },
      { p = "medsplus", r = 2, c = 100 } },
}

return CM
