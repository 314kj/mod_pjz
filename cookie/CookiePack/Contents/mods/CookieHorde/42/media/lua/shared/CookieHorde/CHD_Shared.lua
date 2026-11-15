-- Cookie Horde - shared core
-- by lookchinnoi (AKA) for CookieCheetah
-- An admin zombie spawner that lets a horde out a few at a time. The game's own horde command
-- (CreateHorde2Command) creates every zombie in one server tick: 300 at once stalls the server
-- and every client near the spot builds 300 new zombies in the same frame.
-- NOTE: keep every .lua file ASCII only. Player-facing text lives in Translate/*/IG_UI.json
-- NOTE: Kahlua has no next(), % keeps the sign of the left side, no string.format: see CM helpers

require "CM_Shared"

CHD = CHD or {}
CHD.MOD = "CookieHorde"
CHD.VERSION = "1.0.0"
CHD.BUILD = "chd-1.0.0"

-- limits per spawn spot
CHD.MAX_PER_MIN = 100
CHD.MAX_TOTAL = 1000
CHD.MAX_RADIUS = 20
CHD.MAX_POINTS = 20        -- spots running at once
CHD.PER_TICK = 3           -- zombies one spot may let out in one server tick

-- preset limits
CHD.MAX_PRESETS = 40
CHD.MAX_OUTFITS = 100
CHD.MAX_DROPS = 30
CHD.MAX_DROP_N = 20
CHD.HP_MIN = 0.25
CHD.HP_MAX = 5
CHD.HP_STEP = 0.25

-- speed keys; "server" leaves the sandbox speed alone
CHD.SPEEDS = { "server", "walk", "fast", "sprint" }
CHD.SPEED_CODE = { sprint = 1, fast = 2, walk = 3 }   -- IsoZombie.SPEED_SPRINTER / FAST_SHAMBLER / SHAMBLER

-- sluggish: walk speed in % of normal (the game has no walk slower than a shambler; clients scale
-- the zombie's movement with setMoveDelta)
CHD.SLOW_STEPS = { 100, 80, 60, 40, 25 }

-- resistance: damage cut in % per kind of hit, 100 = the hit does nothing.
-- At most two kinds may be 100, so every resistant zombie can still be killed.
CHD.RES_KINDS = { "boom", "melee", "gun" }
CHD.CUT_STEPS = { 0, 25, 50, 75, 100 }
CHD.MAX_IMMUNE = 2

-- lag estimate (advice only, never blocks). Starting numbers, to be retuned after measuring.
CHD.NEAR_R = 50            -- zombies counted around a spot
CHD.LAG_MID = 200          -- zombies around a spot when nobody kills any
CHD.LAG_HIGH = 400
CHD.RATE_MID = 150         -- zombies a minute from all spots near each other
CHD.SEEN_DIST = 15         -- a spot closer than this to a player spawns on screen
CHD.GOOD_DIST = 25

function CHD.log(msg) print("[CookieHorde] " .. tostring(msg)) end

local function isSpeed(s)
    for i = 1, #CHD.SPEEDS do
        if CHD.SPEEDS[i] == s then return true end
    end
    return false
end
CHD.isSpeed = isSpeed

-- the step in a list closest to v
local function nearestStep(steps, v, def)
    local n = CM.num(v, def)
    local best, bd = steps[1], nil
    for i = 1, #steps do
        local d = math.abs(steps[i] - n)
        if bd == nil or d < bd then best, bd = steps[i], d end
    end
    return best
end
CHD.nearestStep = nearestStep

-- 0.25 steps between HP_MIN and HP_MAX
function CHD.hpOf(v)
    local h = CM.num(v, 1)
    h = math.floor(h / CHD.HP_STEP + 0.5) * CHD.HP_STEP
    return CM.clamp(h, CHD.HP_MIN, CHD.HP_MAX)
end

function CHD.slowOf(v) return nearestStep(CHD.SLOW_STEPS, v, 100) end
function CHD.cutOf(v) return nearestStep(CHD.CUT_STEPS, v, 0) end

-- resistance settings cut to the steps; never three kinds at 100
function CHD.cleanRes(r)
    local out = { pct = 0, boom = 0, melee = 0, gun = 0 }
    if type(r) ~= "table" then return out end
    out.pct = CM.int(r.pct, 0, 0, 100)
    local immune = 0
    for _, k in ipairs(CHD.RES_KINDS) do
        local c = CHD.cutOf(r[k])
        if c >= 100 then
            immune = immune + 1
            if immune > CHD.MAX_IMMUNE then c = 75 end
        end
        out[k] = c
    end
    return out
end

-- any kind of hit cut at all
function CHD.hasRes(r)
    if type(r) ~= "table" or CM.num(r.pct, 0) <= 0 then return false end
    for _, k in ipairs(CHD.RES_KINDS) do
        if CM.num(r[k], 0) > 0 then return true end
    end
    return false
end

-- a preset from a client or from the save, cut to the limits; nil when it is not usable
function CHD.cleanPreset(p)
    if type(p) ~= "table" then return nil end
    local out = {
        id = CM.str(p.id, 24),
        name = CM.trim(CM.str(p.name, 40)),
        speed = isSpeed(p.speed) and p.speed or "server",
        slow = CHD.slowOf(p.slow),
        hp = CHD.hpOf(p.hp),
        res = CHD.cleanRes(p.res),
        outfits = {},
        drops = {},
    }
    if out.name == "" then out.name = "Horde" end
    local seen = {}
    if type(p.outfits) == "table" then
        local i = 1
        while p.outfits[i] ~= nil and #out.outfits < CHD.MAX_OUTFITS do
            local o = CM.trim(CM.str(p.outfits[i], 60))
            if o ~= "" and not seen[o] then
                seen[o] = true
                out.outfits[#out.outfits + 1] = o
            end
            i = i + 1
        end
    end
    if type(p.drops) == "table" then
        local i = 1
        while p.drops[i] ~= nil and #out.drops < CHD.MAX_DROPS do
            local d = p.drops[i]
            if type(d) == "table" then
                local ft = CM.trim(CM.str(d.ft, 80))
                if ft ~= "" and string.find(ft, ".", 1, true) then
                    out.drops[#out.drops + 1] = {
                        ft = ft,
                        pct = CM.int(d.pct, 10, 1, 100),
                        n = CM.int(d.n, 1, 1, CHD.MAX_DROP_N),
                    }
                end
            end
            i = i + 1
        end
    end
    return out
end

-- a new spot from a client; nil when it is not usable
function CHD.cleanPoint(a)
    if type(a) ~= "table" then return nil end
    local x, y = CM.int(a.x, nil), CM.int(a.y, nil)
    if not x or not y or x < 0 or y < 0 then return nil end
    return {
        x = x,
        y = y,
        z = CM.int(a.z, 0, -32, 31),
        r = CM.int(a.r, 4, 1, CHD.MAX_RADIUS),
        total = CM.int(a.total, 100, 1, CHD.MAX_TOTAL),
        perMin = CM.int(a.perMin, 60, 1, CHD.MAX_PER_MIN),
        pid = CM.str(a.pid, 24),
    }
end

-- spot ids are "s" .. seq; sort them by the number, not the text
function CHD.seqOf(id)
    return CM.num(string.sub(tostring(id or ""), 2), 0)
end

-- Lag advice from what the server counted around a spot.
-- info = { near = zombies within NEAR_R now, total = this spot's count, perMin = this spot's rate,
--          pending = zombies other spots nearby still have to let out, rateNear = their rate a minute,
--          dist = squares to the nearest player (nil = nobody near) }
-- returns level ("low" | "mid" | "high"), expected zombies around the spot, reasons { {key, a, b} },
-- and a suggested count (nil when the count is fine)
function CHD.advise(info)
    info = info or {}
    local near = math.max(0, CM.num(info.near, 0))
    local total = math.max(0, CM.num(info.total, 0))
    local perMin = math.max(0, CM.num(info.perMin, 0))
    local pending = math.max(0, CM.num(info.pending, 0))
    local rateNear = math.max(0, CM.num(info.rateNear, 0))
    local expected = near + total + pending
    local level = "low"
    local reasons = {}
    local function raise(l)
        if l == "high" or (l == "mid" and level == "low") then level = l end
    end
    if expected > CHD.LAG_HIGH then
        raise("high")
        reasons[#reasons + 1] = { key = "many", a = expected, b = CHD.LAG_HIGH }
    elseif expected > CHD.LAG_MID then
        raise("mid")
        reasons[#reasons + 1] = { key = "many", a = expected, b = CHD.LAG_MID }
    end
    if near > 0 then reasons[#reasons + 1] = { key = "near", a = near, b = CHD.NEAR_R } end
    if pending > 0 then reasons[#reasons + 1] = { key = "pending", a = pending } end
    local rate = perMin + rateNear
    if rate > CHD.RATE_MID then
        raise("mid")
        reasons[#reasons + 1] = { key = "rate", a = rate }
    end
    local dist = info.dist
    if dist ~= nil then
        dist = math.floor(CM.num(dist, 0))
        if dist < CHD.SEEN_DIST then
            raise("mid")
            reasons[#reasons + 1] = { key = "seen", a = dist, b = CHD.GOOD_DIST }
        end
    end
    local suggest = nil
    if expected > CHD.LAG_MID then
        local room = CHD.LAG_MID - near - pending
        if room < total then suggest = math.max(0, room) end
    end
    if level == "low" then reasons[#reasons + 1] = { key = "ok" } end
    return level, expected, reasons, suggest
end

-- every outfit has the same chance
function CHD.pick(list, roll)
    if type(list) ~= "table" or #list == 0 then return nil end
    local i = math.floor(CM.num(roll, 0) * #list) + 1
    if i > #list then i = #list end
    if i < 1 then i = 1 end
    return list[i]
end

return CHD
