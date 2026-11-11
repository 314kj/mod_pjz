-- Cookie Mastery - shared core
-- by lookchinnoi (AKA) for CookieCheetah
-- "Mastery" mode of Cookie Mission: XP earned in a skill that is already level 10 flows into a
-- separate 10-level mastery track of ONE branch chosen per life. Never written to any journal.
-- NOTE: keep every .lua file ASCII only. Player-facing text lives in Translate/*/IG_UI.json
-- NOTE: Kahlua has no next(), % keeps the sign of the left side, no string.format: see CM helpers

require "CM_Shared"

CMM = CMM or {}
CMM.MOD = "CookieMastery"
CMM.VERSION = "0.4.3"
CMM.BUILD = "cmm-261108-test1"
CMM.BOOK_TYPE = "CookieMastery.MasterBook"

function CMM.log(msg) print("[CookieMastery] " .. tostring(msg)) end

-- ===================================================================== sandbox
CMM.DEFAULTS = {
    Enabled = true,
    BarPoints = 1000,        -- points one full level-10 bar of overflow XP is worth
    LevelBase = 1000,        -- points needed for mastery level 1
    LevelGrowth = 150,       -- each next level needs this % of the previous one (150 = x1.5)
    ReportSeconds = 10,      -- unused since 0.4.1 (XP is counted on the server); kept so saved sandboxes load
    CapPerMinute = 3000,     -- server ignores overflow above this many points per player per minute
    DeathKeep = 0,           -- % of mastery points kept on death (0 = hardcore)
    MentorRadius = 10,
    MentorBonus = 25,        -- % extra skill XP for a student next to an active mentor
    MentorWindow = 30,       -- seconds a mentor counts as "active" after gaining branch XP
    ApprenticeBonus = 25,    -- % extra skill XP for an apprentice while the mentor is online
    ApprenticeLevelPoints = 250, -- mastery points the mentor gets per skill level the apprentice gains
    ApprenticeSwapDays = 7,
    BookDays = 7,            -- real days between two master books
    BookBonus = 50,          -- % extra skill XP while a master book is active
    BookHours = 6,           -- real hours a master book lasts once read
    LegacyBookHours = 24,
    BuildHpBase = 30,        -- builder T1: % extra HP at mastery level 1
    BuildHpPerLevel = 5,     -- ... plus this much per level above 1 (Lv10 = 75%)
    RepairPlanksPerFull = 2, -- builder T5: planks to repair a structure from 0 to full (rounded up)
    RepairNailsPerFull = 4,
    LiveBoard = true,        -- Hall of Fame page shows the five strongest living masters by name
    Announce = true,         -- tell everyone online when someone reaches Lv 10 / a Lv 10 master dies
}

function CMM.sv(name, def)
    if def == nil then def = CMM.DEFAULTS[name] end
    local sv = SandboxVars and SandboxVars.CookieMastery
    if sv and sv[name] ~= nil then
        if type(def) == "number" then return CM.num(sv[name], def) end
        return sv[name]
    end
    return def
end

-- ===================================================================== branches
-- side -> branches; each branch lists the B42 perk ids whose overflow it collects
CMM.SIDES = {
    { id = "combat", color = { 1.00, 0.46, 0.50 }, branches = { "gun", "melee", "power" } },
    { id = "craft",  color = { 0.40, 0.78, 1.00 }, branches = { "build", "mech", "civic" } },
    { id = "farm",   color = { 0.48, 0.95, 0.62 }, branches = { "plant", "wild", "ranch" } },
}

CMM.BRANCH = {
    gun   = { side = "combat", perks = { "Aiming", "Reloading" } },
    melee = { side = "combat", perks = { "Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear", "Maintenance" } },
    power = { side = "combat", perks = { "Strength", "Fitness", "Sprinting", "Nimble" } },
    build = { side = "craft",  perks = { "Woodwork", "Masonry", "Carving" } },
    mech  = { side = "craft",  perks = { "Mechanics", "Electricity", "MetalWelding", "Blacksmith" } },
    civic = { side = "craft",  perks = { "Cooking", "Doctor", "Tailoring" } },
    plant = { side = "farm",   perks = { "Farming" } },
    wild  = { side = "farm",   perks = { "PlantScavenging", "Tracking", "Trapping", "Fishing" } },
    ranch = { side = "farm",   perks = { "Husbandry", "Butchering" } },
}

-- perk id -> branch id
CMM.PERK_BRANCH = {}
for bid, b in pairs(CMM.BRANCH) do
    for i = 1, #b.perks do CMM.PERK_BRANCH[b.perks[i]] = bid end
end

-- the four tiers and which nodes this build actually implements
CMM.TIERS = { 1, 3, 5, 10 }
CMM.LIVE = {
    build = { [1] = true, [3] = true, [5] = true, [10] = true },
    -- every branch shares the T3 mentor node and the T5 master book
    ["*"] = { [3] = true },
}

function CMM.sideOf(bid)
    local b = CMM.BRANCH[bid]
    if not b then return nil end
    for i = 1, #CMM.SIDES do
        if CMM.SIDES[i].id == b.side then return CMM.SIDES[i] end
    end
    return nil
end

function CMM.colorOf(bid)
    local s = CMM.sideOf(bid)
    if s then return s.color end
    return { 0.56, 0.86, 1.0 }
end

function CMM.nodeLive(bid, tier)
    local b = CMM.LIVE[bid]
    if b and b[tier] then return true end
    return CMM.LIVE["*"][tier] == true
end

-- ===================================================================== perks
function CMM.perkId(perk)
    if perk == nil then return nil end
    local id = CM.call(perk, "getId")
    if id ~= nil then id = tostring(id) end
    if id == nil or id == "" then id = tostring(perk) end
    return id
end

function CMM.perkOf(id)
    if not Perks or id == nil then return nil end
    local ok, p = pcall(function() return Perks[id] end)
    if ok then return p end
    return nil
end

-- XP of one full level-10 bar of a perk (passive skills have much bigger bars)
function CMM.bar10(perk)
    local v = CM.call(perk, "getXp10")
    if v == nil then v = CM.call(perk, "getXpForLevel", 10) end
    v = CM.num(v, 0)
    if v <= 0 then v = 9000 end
    return v
end

-- raw overflow XP -> mastery points (normalized, so a fast skill is not worth more than a slow one)
function CMM.points(perk, amount)
    amount = CM.num(amount, 0)
    if amount <= 0 then return 0 end
    return amount / CMM.bar10(perk) * CMM.sv("BarPoints")
end

function CMM.perkLevel(chr, perk)
    if not chr or not perk then return 0 end
    local v = CM.call(chr, "getPerkLevel", perk)
    return CM.num(v, 0)
end

-- branches in which the character has at least one perk at level 10 (allowed to pick)
function CMM.eligible(chr)
    local out = {}
    for bid, b in pairs(CMM.BRANCH) do
        for i = 1, #b.perks do
            if CMM.perkLevel(chr, CMM.perkOf(b.perks[i])) >= 10 then out[bid] = true; break end
        end
    end
    return out
end

-- ===================================================================== mastery levels
function CMM.need(lv)
    -- points needed to go from level lv-1 to lv
    local base = math.max(1, CMM.sv("LevelBase"))
    local g = math.max(100, CMM.sv("LevelGrowth")) / 100
    local n = base
    for _ = 2, lv do n = n * g end
    return math.floor(n + 0.5)
end

function CMM.total(lv)
    local t = 0
    for i = 1, lv do t = t + CMM.need(i) end
    return t
end

-- pts -> level 0..10, points into the current level, points the next level needs (0 at 10)
function CMM.level(pts)
    pts = math.max(0, CM.num(pts, 0))
    local lv, acc = 0, 0
    while lv < 10 do
        local n = CMM.need(lv + 1)
        if pts < acc + n then return lv, pts - acc, n end
        acc = acc + n
        lv = lv + 1
    end
    return 10, pts - acc, 0
end

function CMM.tierOf(lv)
    local t = 0
    for i = 1, #CMM.TIERS do
        if lv >= CMM.TIERS[i] then t = CMM.TIERS[i] end
    end
    return t
end

function CMM.has(rec, bid, tier)
    if type(rec) ~= "table" or rec.br ~= bid then return false end
    local lv = CMM.level(rec.pts)
    return lv >= tier
end

-- builder T1: extra structure HP as a fraction (scales with mastery level, so no level is dead)
function CMM.buildBonus(lv)
    if lv < 1 then return 0 end
    local pct = CMM.sv("BuildHpBase") + CMM.sv("BuildHpPerLevel") * (math.min(10, lv) - 1)
    return math.max(0, pct) / 100
end

-- builder T5: planks / nails to repair a structure missing `frac` (0..1) of its HP
function CMM.repairCost(frac)
    frac = CM.clamp(CM.num(frac, 0), 0, 1)
    if frac <= 0 then return 0, 0 end
    local p = math.ceil(CMM.sv("RepairPlanksPerFull") * frac - 0.0001)
    local n = math.ceil(CMM.sv("RepairNailsPerFull") * frac - 0.0001)
    if p < 1 and CMM.sv("RepairPlanksPerFull") > 0 then p = 1 end
    if n < 1 and CMM.sv("RepairNailsPerFull") > 0 then n = 1 end
    return p, n
end

-- ===================================================================== world helpers
function CMM.square(x, y, z)
    local cell = getCell and getCell()
    if not cell then return nil end
    return CM.call(cell, "getGridSquare", math.floor(x), math.floor(y), math.floor(z or 0))
end

function CMM.isThump(o)
    if o == nil then return false end
    local ok, r = pcall(function() return instanceof(o, "IsoThumpable") end)
    return ok and r == true
end

function CMM.objIndex(o)
    local sq = CM.call(o, "getSquare")
    local list = sq and CM.call(sq, "getObjects")
    if not list then return -1 end
    for i = 0, list:size() - 1 do
        if list:get(i) == o then return i end
    end
    return -1
end

function CMM.objAt(x, y, z, idx)
    local sq = CMM.square(x, y, z)
    local list = sq and CM.call(sq, "getObjects")
    if not list then return nil end
    idx = math.floor(CM.num(idx, -1))
    if idx < 0 or idx >= list:size() then return nil end
    return list:get(idx)
end

function CMM.hp(o)
    return CM.num(CM.call(o, "getHealth"), 0), CM.num(CM.call(o, "getMaxHealth"), 0)
end

function CMM.dist(a, x, y)
    local ok, ax, ay = pcall(function() return a:getX(), a:getY() end)
    if not ok then return 99999 end
    local dx, dy = ax - x, ay - y
    return math.sqrt(dx * dx + dy * dy)
end

return CMM
