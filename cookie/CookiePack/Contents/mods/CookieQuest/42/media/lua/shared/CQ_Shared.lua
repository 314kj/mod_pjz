-- Cookie Quest - shared core
-- by lookchinnoi (AKA) for CookieCheetah
-- NOTE: keep every .lua file ASCII only. Player-facing text lives in Translate/*/IG_UI.json

CQ = CQ or {}
CQ.MOD = "CookieQuest"
CQ.VERSION = "1.2.3"
CQ.BUILD = "cq-261029-817596"
CQ.SHEET_TYPE = "CookieQuest.MissionSheet"

-- ===================================================================== env
-- Kahlua's % keeps the sign of the left side (-3 % 8 == -3); this one is always 0..b-1
-- Kahlua (PZ) has no next(): true when table t has at least one key
function CQ.any(t)
    if type(t) ~= "table" then return false end
    for _ in pairs(t) do return true end
    return false
end

function CQ.mod(a, b)
    return a - math.floor(a / b) * b
end

function CQ.isSP() return (not isServer()) and (not isClient()) end
function CQ.isMPClient() return isClient() and not isServer() end
function CQ.isServerSide() return isServer() or ((not isServer()) and (not isClient())) end

function CQ.log(msg)
    print("[CookieQuest] " .. tostring(msg))
end

-- ===================================================================== tables
function CQ.copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = CQ.copy(x) end
    return o
end

function CQ.count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

function CQ.indexOf(list, v)
    if type(list) ~= "table" then return nil end
    for i = 1, #list do if list[i] == v then return i end end
    return nil
end

function CQ.sortedKeys(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

-- ===================================================================== numbers / strings
function CQ.num(v, def)
    local n = tonumber(v)
    if n == nil or n ~= n then return def end
    return n
end

function CQ.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function CQ.int(v, def, lo, hi)
    local n = CQ.num(v, def)
    if n == nil then return nil end
    n = math.floor(n + 0.5)
    if lo and n < lo then n = lo end
    if hi and n > hi then n = hi end
    return n
end

-- number -> short text without trailing .0 (Kahlua and Lua 5.1 safe)
function CQ.fmt(n, dec)
    n = CQ.num(n, 0)
    dec = dec or 2
    local m = 1
    for _ = 1, dec do m = m * 10 end
    local neg = n < 0
    if neg then n = -n end
    local r = math.floor(n * m + 0.5)
    local ip = math.floor(r / m)
    local fp = r - ip * m
    local s = tostring(ip)
    if fp > 0 then
        local f = tostring(fp)
        while #f < dec do f = "0" .. f end
        while f:sub(-1) == "0" do f = f:sub(1, -2) end
        s = s .. "." .. f
    end
    if neg and r > 0 then s = "-" .. s end
    return s
end

function CQ.pad2(n)
    n = math.floor(CQ.num(n, 0))
    if n < 10 then return "0" .. tostring(n) end
    return tostring(n)
end

-- Kahlua strings are UTF-16 (one Thai letter = one unit). Under a byte-string Lua
-- (the offline test harness) multibyte UTF-8 must not be split; the harness sets this flag.
CQ.BYTE_STRINGS = CQ.BYTE_STRINGS or false

function CQ.charEnd(s, i)
    if not CQ.BYTE_STRINGS then return i end
    local b = string.byte(s, i)
    if not b or b < 192 then return i end
    if b >= 240 then return i + 3 elseif b >= 224 then return i + 2 end
    return i + 1
end

function CQ.safeCut(s, n)
    if not CQ.BYTE_STRINGS then return n end
    while n > 0 do
        local nb = string.byte(s, n + 1)
        if nb and nb >= 128 and nb < 192 then n = n - 1 else break end
    end
    return n
end

function CQ.trim(s)
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

function CQ.str(s, maxLen)
    if s == nil then return "" end
    if type(s) ~= "string" then s = tostring(s) end
    s = CQ.trim(s)
    if maxLen and #s > maxLen then s = string.sub(s, 1, CQ.safeCut(s, maxLen)) end
    return s
end

function CQ.oneOf(v, list, def)
    for i = 1, #list do if list[i] == v then return v end end
    return def
end

function CQ.ukey(name)
    if name == nil then return "" end
    return string.lower(tostring(name))
end

-- ===================================================================== time (real clock, epoch seconds)
CQ.DAY = 86400

function CQ.now()
    return math.floor(CQ.num(os.time(), 0))
end

-- days since 1970-01-01 -> y, m, d   (H. Hinnant civil_from_days)
function CQ.civil(days)
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

-- local wall clock for epoch ts at utc offset (hours)
function CQ.localT(ts, off)
    local t = math.floor(CQ.num(ts, 0)) + math.floor(CQ.num(off, 7) * 3600)
    local day = math.floor(t / 86400)
    local sod = t - day * 86400
    local y, m, d = CQ.civil(day)
    return {
        day = day,
        wday = CQ.mod(day + 4, 7),   -- 0 = Sunday
        hour = math.floor(sod / 3600),
        min = math.floor(CQ.mod(sod, 3600) / 60),
        sec = CQ.mod(sod, 60),
        mod = math.floor(sod / 60),
        y = y, m = m, d = d,
    }
end

function CQ.tsFromLocal(day, minuteOfDay, off)
    return day * 86400 + minuteOfDay * 60 - math.floor(CQ.num(off, 7) * 3600)
end

function CQ.hhmm(minuteOfDay)
    minuteOfDay = CQ.mod(math.floor(CQ.num(minuteOfDay, 0)), 1440)
    return CQ.pad2(math.floor(minuteOfDay / 60)) .. ":" .. CQ.pad2(CQ.mod(minuteOfDay, 60))
end

-- "HH:MM" -> minutes or nil
function CQ.parseHHMM(s)
    s = CQ.str(s, 8)
    local h, m = string.match(s, "^(%d+)[:%.](%d+)$")
    if not h then h = string.match(s, "^(%d+)$"); m = "0" end
    h = tonumber(h); m = tonumber(m)
    if not h or not m then return nil end
    if h == 24 and m == 0 then return 1440 end
    if h < 0 or h > 23 or m < 0 or m > 59 then return nil end
    return h * 60 + m
end

-- H:MM:SS / M:SS
function CQ.clock(sec)
    sec = math.max(0, math.floor(CQ.num(sec, 0)))
    local h = math.floor(sec / 3600)
    local m = math.floor(CQ.mod(sec, 3600) / 60)
    local s = CQ.mod(sec, 60)
    if h > 0 then return tostring(h) .. ":" .. CQ.pad2(m) .. ":" .. CQ.pad2(s) end
    return tostring(m) .. ":" .. CQ.pad2(s)
end

-- ===================================================================== zones
-- zone = { x1, y1, x2, y2, z, anyZ }
CQ.ZONE_MAX = 301

function CQ.makeZone(cx, cy, z, w, h)
    w = CQ.int(w, 3, 1, CQ.ZONE_MAX)
    h = CQ.int(h, 3, 1, CQ.ZONE_MAX)
    cx = math.floor(CQ.num(cx, 0))
    cy = math.floor(CQ.num(cy, 0))
    local x1 = cx - math.floor((w - 1) / 2)
    local y1 = cy - math.floor((h - 1) / 2)
    -- floor, never round: standing high on a staircase (z 0.7) is still floor 0
    local zf = math.floor(CQ.num(z, 0))
    return { x1 = x1, y1 = y1, x2 = x1 + w - 1, y2 = y1 + h - 1, z = CQ.clamp(zf, -32, 31), anyZ = false }
end

function CQ.zoneW(zn) return zn.x2 - zn.x1 + 1 end
function CQ.zoneH(zn) return zn.y2 - zn.y1 + 1 end

function CQ.zoneCenter(zn)
    return math.floor((zn.x1 + zn.x2) / 2), math.floor((zn.y1 + zn.y2) / 2)
end

function CQ.resizeZone(zn, w, h)
    local cx, cy = CQ.zoneCenter(zn)
    local nz = CQ.makeZone(cx, cy, zn.z, w, h)
    nz.anyZ = zn.anyZ == true
    return nz
end

function CQ.inZone(zn, x, y, z)
    if type(zn) ~= "table" or zn.x1 == nil then return false end
    x = math.floor(CQ.num(x, -99999)); y = math.floor(CQ.num(y, -99999))
    if x < zn.x1 or x > zn.x2 or y < zn.y1 or y > zn.y2 then return false end
    if not zn.anyZ and z ~= nil and math.floor(z) ~= (zn.z or 0) then return false end
    return true
end

function CQ.dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function CQ.distToZone(zn, x, y)
    if type(zn) ~= "table" or zn.x1 == nil then return 999999 end
    local dx, dy = 0, 0
    if x < zn.x1 then dx = zn.x1 - x elseif x > zn.x2 + 1 then dx = x - (zn.x2 + 1) end
    if y < zn.y1 then dy = zn.y1 - y elseif y > zn.y2 + 1 then dy = y - (zn.y2 + 1) end
    return math.sqrt(dx * dx + dy * dy)
end

function CQ.cleanZone(z)
    if type(z) ~= "table" then return nil end
    local x1, y1 = CQ.int(z.x1, nil), CQ.int(z.y1, nil)
    local x2, y2 = CQ.int(z.x2, nil), CQ.int(z.y2, nil)
    if not (x1 and y1 and x2 and y2) then return nil end
    if x2 < x1 then x1, x2 = x2, x1 end
    if y2 < y1 then y1, y2 = y2, y1 end
    if x2 - x1 + 1 > CQ.ZONE_MAX then x2 = x1 + CQ.ZONE_MAX - 1 end
    if y2 - y1 + 1 > CQ.ZONE_MAX then y2 = y1 + CQ.ZONE_MAX - 1 end
    return { x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = CQ.int(z.z, 0, -32, 31), anyZ = z.anyZ == true }
end

-- ===================================================================== step types
CQ.STEPS = { "reach", "deliver", "kill", "collect", "rescue", "hold", "radio", "others", "admin" }
CQ.STEP_INFO = {
    reach   = { zone = true },
    deliver = { zone = true, item = true, n = true },
    kill    = { n = true, zoneOpt = true },
    collect = { item = true, n = true },
    rescue  = { zone = true, target = true },
    hold    = { zone = true, sec = true },
    radio   = { ch = true },
    others  = { n = true },
    admin   = {},
}

function CQ.cleanItems(list, maxN)
    local out = {}
    if type(list) ~= "table" then return out end
    for i = 1, #list do
        local it = list[i]
        if type(it) == "table" then
            local t = CQ.str(it.t, 120)
            if t ~= "" and string.find(t, ".", 1, true) then
                out[#out + 1] = { t = t, n = CQ.int(it.n, 1, 1, 999) }
            end
        end
        if #out >= (maxN or 40) then break end
    end
    return out
end

function CQ.cleanIds(list, maxN)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for i = 1, #list do
        local id = CQ.str(list[i], 24)
        if id ~= "" and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
        if #out >= (maxN or 40) then break end
    end
    return out
end

function CQ.cleanSkills(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for i = 1, #list do
        local id = CQ.str(list[i], 40)
        if id ~= "" and string.match(id, "^[%w_]+$") and not seen[string.lower(id)] then
            seen[string.lower(id)] = true
            out[#out + 1] = id
        end
        if #out >= 5 then break end
    end
    return out
end

function CQ.cleanStep(s)
    if type(s) ~= "table" then return nil end
    local o = { t = CQ.oneOf(s.t, CQ.STEPS, "reach") }
    local info = CQ.STEP_INFO[o.t]
    o.label = CQ.str(s.label, 120)
    o.hint = CQ.str(s.hint, 300)
    if info.zone or info.zoneOpt then o.zone = CQ.cleanZone(s.zone) end
    if info.item then o.item = CQ.str(s.item, 120) end
    if info.n then o.n = CQ.int(s.n, 1, 1, 9999) end
    if info.sec then o.sec = CQ.int(s.sec, 60, 5, 7200) end
    if info.target then o.target = CQ.str(s.target, 60) end
    if info.ch then o.ch = CQ.int(s.ch, 91400, 1, 99999999) end
    o.consume = (o.t == "deliver") and s.consume == true or nil
    o.hide = s.hide == true or nil
    o.all = (o.t == "reach") and s.all == true or nil
    return o
end

function CQ.cleanMission(m)
    if type(m) ~= "table" then return nil end
    local o = {}
    o.id = CQ.str(m.id, 24)
    o.title = CQ.str(m.title, 80)
    if o.title == "" then o.title = "?" end
    o.story = CQ.str(m.story, 4000)
    o.assign = CQ.oneOf(m.assign, { "reader", "everyone", "board", "role" }, "reader")
    o.team = m.team == true
    o.showSteps = m.showSteps ~= false
    o.limit = CQ.int(m.limit, 0, 0, 999)
    o.repeatable = m.repeatable == true
    o.timeLimit = CQ.int(m.timeLimit, 0, 0, 10080)
    o.rewardTo = CQ.oneOf(m.rewardTo, { "contrib", "members" }, "contrib")
    o.rewards = CQ.cleanItems(m.rewards, 20)
    o.rewardText = CQ.str(m.rewardText, 160)
    o.steps = {}
    if type(m.steps) == "table" then
        for i = 1, #m.steps do
            local st = CQ.cleanStep(m.steps[i])
            if st then o.steps[#o.steps + 1] = st end
            if #o.steps >= 20 then break end
        end
    end
    if #o.steps == 0 then o.steps[1] = { t = "admin", label = "", hint = "" } end
    return o
end

function CQ.cleanSpawn(sp, i)
    if type(sp) ~= "table" then return nil end
    local o = {}
    o.id = CQ.str(sp.id, 24)
    if o.id == "" then o.id = "z" .. tostring(i) end
    o.name = CQ.str(sp.name, 40)
    o.zone = CQ.cleanZone(sp.zone)
    o.perMin = CQ.int(sp.perMin, 6, 1, 60)
    o.maxAlive = CQ.int(sp.maxAlive, 30, 1, 200)
    o.fromPhase = CQ.int(sp.fromPhase, 1, 1, 10)
    o.stopMid = CQ.str(sp.stopMid, 24)
    o.stopStep = CQ.int(sp.stopStep, 1, 1, 20)
    o.stopKills = CQ.int(sp.stopKills, 0, 0, 9999)
    return o
end

-- mission id -> phase number (only phases above 1 are stored)
function CQ.cleanPhaseMap(map, mids, nPh)
    local out = {}
    if type(map) ~= "table" then return out end
    for i = 1, #mids do
        local v = CQ.int(map[mids[i]], 1, 1, math.max(1, nPh))
        if v > 1 then out[mids[i]] = v end
    end
    return out
end

function CQ.phaseOf(map, mid)
    return (type(map) == "table" and tonumber(map[mid])) or 1
end

function CQ.cleanRole(r, i)
    if type(r) ~= "table" then return nil end
    local o = {}
    o.id = CQ.str(r.id, 24)
    if o.id == "" then o.id = "r" .. tostring(i) end
    o.name = CQ.str(r.name, 40)
    if o.name == "" then o.name = "Role " .. tostring(i) end
    o.desc = CQ.str(r.desc, 600)
    o.kit = CQ.cleanItems(r.kit, 30)
    o.missions = CQ.cleanIds(r.missions, 20)
    o.max = CQ.int(r.max, 0, 0, 99)
    o.secret = r.secret == true
    return o
end

function CQ.cleanEvent(e)
    if type(e) ~= "table" then return nil end
    local o = {}
    o.id = CQ.str(e.id, 24)
    o.title = CQ.str(e.title, 80)
    if o.title == "" then o.title = "?" end
    o.desc = CQ.str(e.desc, 2000)
    o.start = CQ.int(e.start, 0, 0, 4102444800)
    o.dur = CQ.int(e.dur, 120, 5, 10080)
    o.roleMode = CQ.oneOf(e.roleMode, { "none", "pick", "random", "admin" }, "none")
    o.kit = CQ.cleanItems(e.kit, 30)
    o.roles = {}
    if type(e.roles) == "table" then
        local used = {}
        for i = 1, #e.roles do
            local r = CQ.cleanRole(e.roles[i], i)
            if r then
                if used[r.id] then r.id = r.id .. "_" .. tostring(i) end
                used[r.id] = true
                o.roles[#o.roles + 1] = r
            end
            if #o.roles >= 12 then break end
        end
    end
    o.missions = CQ.cleanIds(e.missions, 30)
    -- phases 1 > 2 > 3: what moves the event (or a player/team) from each phase to the next
    o.phases = {}
    if type(e.phases) == "table" then
        for i = 1, #e.phases do
            local ph = e.phases[i]
            if type(ph) == "table" then
                o.phases[#o.phases + 1] = {
                    name = CQ.str(ph.name, 40), all = ph.all == true, key = CQ.str(ph.key, 24),
                    min = CQ.int(ph.min, 0, 0, 1440), self = ph.self == true,
                }
            end
            if #o.phases >= 10 then break end
        end
    end
    o.phaseMode = CQ.oneOf(e.phaseMode, { "strict", "parallel" }, "strict")
    -- zombie spawn points: where, how fast, from which phase, what stops them
    o.spawns = {}
    if type(e.spawns) == "table" then
        local used = {}
        for i = 1, #e.spawns do
            local sp = CQ.cleanSpawn(e.spawns[i], i)
            if sp then
                if used[sp.id] then sp.id = sp.id .. "_" .. tostring(i) end
                used[sp.id] = true
                o.spawns[#o.spawns + 1] = sp
            end
            if #o.spawns >= 12 then break end
        end
    end
    local nPh = math.max(1, #o.phases)
    o.mph = CQ.cleanPhaseMap(e.mph, o.missions, nPh)
    for i = 1, #o.roles do
        local raw = type(e.roles) == "table" and e.roles[i] or nil
        o.roles[i].mph = CQ.cleanPhaseMap(type(raw) == "table" and raw.mph or nil, o.roles[i].missions, nPh)
    end
    o.lateJoin = e.lateJoin ~= false
    local p = type(e.pen) == "table" and e.pen or {}
    o.pen = {
        on = p.on ~= false,
        mult = CQ.clamp(CQ.num(p.mult, 0.5), 0.05, 1),
        days = CQ.clamp(CQ.num(p.days, 3), 0.1, 30),
        minCp = CQ.int(p.minCp, 1, 0, 99),
    }
    return o
end

function CQ.cleanSched(b)
    if type(b) ~= "table" then return nil end
    local o = { id = CQ.str(b.id, 24) }
    o.on = b.on ~= false
    o.days = {}
    for i = 1, 7 do o.days[i] = type(b.days) == "table" and b.days[i] == true or false end
    o.from = CQ.int(b.from, 1080, 0, 1439)
    o.to = CQ.int(b.to, 1380, 0, 1440)
    if o.to == 1440 then o.to = 0 end
    o.mult = CQ.clamp(CQ.num(b.mult, 2), 0.1, 20)
    o.skills = CQ.cleanSkills(b.skills)
    o.label = CQ.str(b.label, 60)
    return o
end

function CQ.cleanRadio(r)
    if type(r) ~= "table" then return nil end
    local o = { id = CQ.str(r.id, 24) }
    o.name = CQ.str(r.name, 60)
    o.ch = CQ.int(r.ch, 91400, 1, 99999999)
    o.iv = CQ.int(r.iv, 30, 5, 3600)
    o.on = r.on ~= false
    o.color = CQ.int(r.color, 1, 1, 6)
    o.lines = {}
    if type(r.lines) == "table" then
        for i = 1, #r.lines do
            local l = CQ.str(r.lines[i], 200)
            if l ~= "" then o.lines[#o.lines + 1] = l end
            if #o.lines >= 40 then break end
        end
    end
    return o
end

-- ===================================================================== XP buffs
function CQ.skillMatch(skills, perkId)
    if type(skills) ~= "table" or #skills == 0 then return true end
    local p = string.lower(tostring(perkId or ""))
    for i = 1, #skills do
        if string.lower(skills[i]) == p then return true end
    end
    return false
end

-- returns window end (epoch) when schedule b is active at ts, else nil
function CQ.schedEnd(b, ts, off)
    if type(b) ~= "table" or not b.on or type(b.days) ~= "table" then return nil end
    local lt = CQ.localT(ts, off)
    local mod = lt.mod
    if b.from < b.to then
        if b.days[lt.wday + 1] and mod >= b.from and mod < b.to then
            return CQ.tsFromLocal(lt.day, b.to, off)
        end
    elseif b.from > b.to then
        if b.days[lt.wday + 1] and mod >= b.from then
            return CQ.tsFromLocal(lt.day + 1, b.to, off)
        end
        local yw = CQ.mod(lt.wday + 6, 7)
        if b.days[yw + 1] and mod < b.to then
            return CQ.tsFromLocal(lt.day, b.to, off)
        end
    else
        if b.days[lt.wday + 1] then
            return CQ.tsFromLocal(lt.day + 1, b.from, off)
        end
    end
    return nil
end

-- next start of schedule b after ts (within 8 days) or nil
function CQ.schedNext(b, ts, off)
    if type(b) ~= "table" or not b.on or type(b.days) ~= "table" then return nil end
    local lt = CQ.localT(ts, off)
    for d = 0, 7 do
        local wd = CQ.mod(lt.wday + d, 7)
        if b.days[wd + 1] then
            local st = CQ.tsFromLocal(lt.day + d, b.from, off)
            if st > ts then return st end
        end
    end
    return nil
end

-- buffs = { sched = {id -> b}, manual = {mult, untilTs, skills, label} }
function CQ.activeBuffs(buffs, ts, off)
    local out = {}
    if type(buffs) ~= "table" then return out end
    if type(buffs.sched) == "table" then
        for _, id in ipairs(CQ.sortedKeys(buffs.sched)) do
            local b = buffs.sched[id]
            local e = CQ.schedEnd(b, ts, off)
            if e then
                out[#out + 1] = { k = "s" .. tostring(id), mult = b.mult, skills = CQ.copy(b.skills or {}), untilTs = e, label = b.label or "" }
            end
        end
    end
    local m = buffs.manual
    if type(m) == "table" and CQ.num(m.untilTs, 0) > ts then
        out[#out + 1] = { k = "m", mult = m.mult, skills = CQ.copy(m.skills or {}), untilTs = m.untilTs, label = m.label or "" }
    end
    return out
end

-- combined multiplier for a perk: best buff >1, worst buff <1, times penalty
function CQ.multFor(perkId, active, pen, now)
    local up, down = 1, 1
    if type(active) == "table" then
        for i = 1, #active do
            local b = active[i]
            if CQ.num(b.untilTs, 0) > now and CQ.skillMatch(b.skills, perkId) then
                local m = CQ.num(b.mult, 1)
                if m > up then up = m end
                if m < down then down = m end
            end
        end
    end
    local r = up * down
    if type(pen) == "table" and CQ.num(pen.untilTs, 0) > now then
        r = r * CQ.clamp(CQ.num(pen.mult, 1), 0.01, 1)
    end
    return r
end

-- ===================================================================== radio
function CQ.chText(ch)
    ch = CQ.num(ch, 0)
    return CQ.fmt(ch / 1000, 1)
end

function CQ.mhzToCh(s)
    local v = CQ.num(s, nil)
    if not v then return nil end
    if v < 10000 then v = v * 1000 end
    return math.floor(v + 0.5)
end

-- line on air for channel r at ts: index, text, slot
function CQ.radioLine(r, ts)
    if type(r) ~= "table" or type(r.lines) ~= "table" or #r.lines == 0 then return nil end
    local iv = math.max(5, CQ.num(r.iv, 30))
    local slot = math.floor((ts - CQ.num(r.t0, 0)) / iv)
    local idx = CQ.mod(slot, #r.lines) + 1
    return idx, r.lines[idx], slot
end

CQ.RADIO_COLORS = {
    { 1.0, 0.62, 0.24 },
    { 0.65, 0.45, 0.95 },
    { 0.40, 0.88, 0.60 },
    { 0.45, 0.75, 1.0 },
    { 0.95, 0.38, 0.38 },
    { 1.0, 0.95, 0.85 },
}

-- ===================================================================== text helpers usable on both sides
-- sheet item name carries the mission id after '#'
function CQ.sheetMid(item)
    if not item then return nil end
    local ok, md = pcall(function() return item:getModData() end)
    if ok and md and md.cqMid then return tostring(md.cqMid) end
    local ok2, name = pcall(function() return item:getName() end)
    if ok2 and name then
        local mid = string.match(tostring(name), "#(m%d+)%s*$")
        if mid then return mid end
    end
    return nil
end

return CQ
