-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- AkaElixir - shared config + ตัวล้างสถานะ
-- โหลดได้ทั้ง client / server / SP  ห้ามอ้างของฝั่งจอในไฟล์นี้

AE = AE or {}
if AE.__ready then return AE end

AE.NAME    = "AkaElixir"
AE.VERSION = "1.5.0"

--------------------------------------------------------------------------
-- safe call
-- Kahlua คืน object "none" (ไม่ใช่ nil) เวลา index เมธอดที่ไม่มี
-- `if obj.method then` จึงเป็นจริงเสมอแล้วไประเบิดตอนเรียก ต้องผ่านตัวนี้เท่านั้น
--------------------------------------------------------------------------
-- สำคัญ: ต้องเรียกด้วย "จำนวนอาร์กิวเมนต์เท่าที่ของจริงรับ" เป๊ะ
-- Kahlua เช็ค arity ของเมธอด Java แบบเข้มงวด การส่ง nil ต่อท้ายไม่ได้แปลว่า
-- "ไม่ส่ง" แต่นับเป็นอาร์กิวเมนต์จริง ๆ  obj[name](obj, nil, nil) บนเมธอดที่รับ 0 ตัว
-- จะได้ java.lang.RuntimeException: expected 0 arguments, got 2 ทันที
function AE.sc(obj, name, a, b)
    if obj == nil then return nil end
    local ok, res
    if a == nil then
        ok, res = pcall(function() return obj[name](obj) end)
    elseif b == nil then
        ok, res = pcall(function() return obj[name](obj, a) end)
    else
        ok, res = pcall(function() return obj[name](obj, a, b) end)
    end
    if ok then return res end
    return nil
end

--------------------------------------------------------------------------
-- log ของการพยายามเรียก API
-- เราเทสในเกมจริงไม่ได้ตอนเขียน ชื่อเมธอดของ B42 จึงต้องลองหลายทาง
-- ทางไหนเรียกไม่ผ่านจะถูกกลืนแล้วบันทึกไว้ ไม่ทำให้ขวดทั้งใบตาย
--------------------------------------------------------------------------
function AE.newLog()
    return { ok = {}, fail = {}, nOK = 0, nFail = 0 }
end

function AE.try(log, name, fn)
    local good = pcall(fn)
    if good then
        log.ok[name] = (log.ok[name] or 0) + 1
        log.nOK = log.nOK + 1
    else
        log.fail[name] = (log.fail[name] or 0) + 1
        log.nFail = log.nFail + 1
    end
    return good
end

local function joinCounts(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = ""
    for i = 1, #keys do
        if i > 1 then out = out .. ", " end
        out = out .. keys[i]
        if t[keys[i]] > 1 then out = out .. " x" .. tostring(t[keys[i]]) end
    end
    if out == "" then out = "-" end
    return out
end

function AE.logLine(key, log)
    return "[AkaElixir] " .. key
        .. "  applied(" .. tostring(log.nOK) .. "): " .. joinCounts(log.ok)
        .. "  |  skipped(" .. tostring(log.nFail) .. "): " .. joinCounts(log.fail)
end

--------------------------------------------------------------------------
-- Sandbox
--------------------------------------------------------------------------
local function sv() return SandboxVars and SandboxVars.AkaElixir or nil end

function AE.invulnMinutes()
    local s = sv()
    local v = s and s.InvulnMinutes
    if type(v) == "number" and v > 0 then return v end
    return 1                        -- 1 นาทีในเกม ตามที่ Pie เลือก
end

function AE.curesInfection()
    local s = sv()
    if s and type(s.PanaceaCuresInfection) == "boolean" then return s.PanaceaCuresInfection end
    return false                    -- ไม่ล้างเชื้อซอมบี้ ตามที่ Pie เลือก
end

function AE.panaceaHeals()
    local s = sv()
    if s and type(s.PanaceaHeals) == "boolean" then return s.PanaceaHeals end
    return true
end

function AE.verbose()
    local s = sv()
    if s and type(s.Verbose) == "boolean" then return s.Verbose end
    return false
end

function AE.panaceaFeeds()
    local s = sv()
    if s and type(s.PanaceaFeeds) == "boolean" then return s.PanaceaFeeds end
    return true                     -- ขวดแดงล้างความหิว/กระหายด้วย
end

--------------------------------------------------------------------------
-- ชิ้นส่วนร่างกาย - สองทาง เผื่อทางแรกไม่มีใน build นั้น
--------------------------------------------------------------------------
function AE.bodyParts(player)
    local bd = AE.sc(player, "getBodyDamage")
    if bd == nil then return {}, nil end
    local out = {}

    local list = AE.sc(bd, "getBodyParts")
    local n = AE.sc(list, "size")
    if type(n) == "number" then
        for i = 0, n - 1 do
            local bp = AE.sc(list, "get", i)
            if bp ~= nil then out[#out + 1] = bp end
        end
    end

    if #out == 0 and BodyPartType ~= nil then
        local okMax, maxIdx = pcall(function() return BodyPartType.ToIndex(BodyPartType.MAX) end)
        if okMax and type(maxIdx) == "number" then
            for i = 0, maxIdx - 1 do
                local okBp, bp = pcall(function()
                    return bd:getBodyPart(BodyPartType.FromIndex(i))
                end)
                if okBp and bp ~= nil then out[#out + 1] = bp end
            end
        end
    end

    return out, bd
end

--------------------------------------------------------------------------
-- ผลของแต่ละขวด
--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- setNum - ตั้งค่าตัวเลขหนึ่งตัว โดยลองหลายทางจนกว่าจะมีทางที่ "ได้ผลจริง"
--
-- จากล็อกเกมจริง (v1.0.1) พบว่า setter ของ Stats/BodyDamage หลายตัวไม่มีใน B42
--   "Object tried to call nil in endurance / fatigue / stress / ..."
-- แต่ setAdditionalPain / setStiffness / setPainReduction / setOverallBodyHealth มี
-- สรุปคือบางค่าเป็น "เมธอด" บางค่าเป็น "ฟิลด์สาธารณะ" และเดาจากนอกเกมไม่ได้
--
-- ผู้สมัคร 2 ชนิด
--   k = "m"  เมธอด  -> เรียกแล้วไม่โยน = สำเร็จ (Kahlua โยนเสมอถ้าเมธอดไม่มี)
--   k = "f"  ฟิลด์   -> ต้องอ่านได้เป็นตัวเลข "ก่อน" เขียน แล้วอ่านซ้ำต้องได้ค่าใหม่
--            การเช็คก่อนเขียนสำคัญมาก ไม่งั้นการเขียนคีย์ที่ไม่มีจริงจะดูเหมือนสำเร็จ
--
-- ป้ายที่บันทึกจะบอกด้วยว่า "ชนะด้วยทางไหน" เช่น  endurance via .endurance
-- ล็อกรอบหน้าจึงตอบได้เลยว่า B42 ใช้ทางไหน โดยไม่ต้องเดาอีก
--------------------------------------------------------------------------
local function near(a, b) return a >= b - 0.001 and a <= b + 0.001 end

local function M(obj, name, v)      -- ผู้สมัครแบบเมธอด set<Name>()
    return { k = "m", t = "set" .. name .. "()",
             w = function() obj["set" .. name](obj, v) end }
end

local function F(obj, name, v)      -- ผู้สมัครแบบฟิลด์
    return { k = "f", t = "." .. name,
             w = function() obj[name] = v end,
             r = function() return obj[name] end }
end

function AE.setNum(log, label, target, cands)
    local why = "no candidate"
    for i = 1, #cands do
        local c = cands[i]
        local won = false

        if c.k == "v" then
            -- เขียน (อาจโยน) แล้ว "อ่านกลับมาเช็ค" ด้วยทางที่เชื่อถือได้
            local good, err = pcall(c.w)
            if not good then
                why = c.t .. " -> " .. tostring(err)
            else
                local okR, post = pcall(c.r)
                if okR and type(post) == "number" and near(post, target) then
                    won = true
                else
                    why = c.t .. " -> write ignored"
                end
            end
        elseif c.k == "m" then
            local good, err = pcall(c.w)
            won = good
            if not good then why = c.t .. " -> " .. tostring(err) end
        else
            local okPre, pre = pcall(c.r)
            if not okPre then
                why = c.t .. " -> read failed"
            elseif type(pre) ~= "number" then
                why = c.t .. " -> not a number (" .. type(pre) .. ")"
            else
                if pcall(c.w) then
                    local okPost, post = pcall(c.r)
                    won = okPost and type(post) == "number" and near(post, target)
                    if not won then why = c.t .. " -> write ignored" end
                else
                    why = c.t .. " -> write failed"
                end
            end
        end

        if won then
            local key = label .. " via " .. c.t
            log.ok[key] = (log.ok[key] or 0) + 1
            log.nOK = log.nOK + 1
            return true
        end
    end
    -- เก็บ "เพราะอะไร" ไว้ด้วย ไม่ใช่แค่ว่าไม่ผ่าน
    -- ล็อกรอบก่อนบอกได้แค่ว่า skipped ซึ่งไม่พอจะรู้ว่าเมธอดไม่มี หรือ object เป็น nil
    if #why > 70 then why = string.sub(why, 1, 70) end
    local key = label .. " [" .. why .. "]"
    log.fail[key] = (log.fail[key] or 0) + 1
    log.nFail = log.nFail + 1
    return false
end

--------------------------------------------------------------------------
-- probe - พิมพ์ "หน้าตาจริง" ของ object ที่เราต้องแก้ ครั้งเดียวต่อเซสชัน
-- เลิกเดาชื่อเมธอด แล้วให้เกมบอกเองว่ามีอะไรอ่านได้บ้าง
--------------------------------------------------------------------------
local function probeGetters(obj, names)
    local out = ""
    for i = 1, #names do
        local v = AE.sc(obj, "get" .. names[i])
        if i > 1 then out = out .. "  " end
        out = out .. names[i] .. "=" .. tostring(v)
    end
    return out
end

function AE.probe(player)
    if AE.__probed then return end
    AE.__probed = true

    local st = AE.sc(player, "getStats")
    local parts, bd = AE.bodyParts(player)

    print("[AkaElixir] probe stats  = " .. tostring(st))
    print("[AkaElixir] probe read  : Endurance=" .. tostring(AE.statRead(st, "Endurance"))
        .. "  Hunger=" .. tostring(AE.statRead(st, "Hunger"))
        .. "  Unhappiness=" .. tostring(AE.statRead(st, "Unhappiness")))
    print("[AkaElixir] probe enum  = " .. tostring(CharacterStat)
        .. "   Endurance=" .. tostring(AE.statEnum("Endurance"))
        .. "   Hunger=" .. tostring(AE.statEnum("Hunger")))
    print("[AkaElixir] probe bd     = " .. tostring(bd) .. "   parts=" .. tostring(#parts))
    print("[AkaElixir] probe bd     : " .. probeGetters(bd,
        { "OverallBodyHealth", "PainReduction" }))
    if parts[1] ~= nil then
        print("[AkaElixir] probe part   : " .. probeGetters(parts[1],
            { "Health", "AdditionalPain", "Stiffness" }))
    end
end

--------------------------------------------------------------------------
-- Stats ของ B42 - อ่านผ่าน tostring() ไม่ใช่ getter
--
-- probe ในเกมจริงบอกว่า **ไม่มี getter สักตัว** (getEndurance/getStress = nil)
-- และอ่านฟิลด์ตรง ๆ (st.Endurance) ก็ไม่ได้
-- แต่ tostring(stats) พ่นทุกค่าออกมาเป็นข้อความ:
--
--   Stats{
--     Endurance = 0.5020468
--     Unhappiness = 0.0
--     FoodSickness = 3.5472481
--     ...
--   }
--
-- ข้อความก้อนนี้จึงเป็น "ทางอ่าน" ที่ใช้ได้กับทุกค่าโดยไม่ต้องพึ่ง API เลย
-- ทำให้ตรวจได้ว่าการเขียนแต่ละแบบ "ได้ผลจริงไหม" ไม่ใช่แค่ "ไม่โยน error"
--------------------------------------------------------------------------
function AE.statRead(st, name)
    local ok, s = pcall(function() return tostring(st) end)
    if not ok or type(s) ~= "string" then return nil end
    -- ยึดกับขึ้นบรรทัดใหม่ ไม่งั้น "Sickness" จะไปแมตช์กลางคำ "FoodSickness"
    local v = string.match(s, "\n%s*" .. name .. "%s*=%s*([^%s]+)")
    return tonumber(v)
end

--------------------------------------------------------------------------
-- CharacterStat - กุญแจของทั้งเรื่อง
--
-- error จากเกมจริง (v1.4.0):
--   get("Anger"):set() -> expected argument of type CharacterStat, got String
--
-- แปลว่า st:get() / st:set() **มีอยู่จริง** แต่ไม่รับชื่อเป็นสตริง
-- มันรับ enum ชื่อ CharacterStat  ->  st:set(CharacterStat.Anger, 0)
--
-- นี่คือเหตุผลที่ทุกทางล้มมาตลอด 4 รอบ: ผมส่ง "ชนิด" ผิด ไม่ใช่ "ชื่อ" ผิด
--------------------------------------------------------------------------
function AE.statEnum(name)
    if CharacterStat == nil then return nil end
    local ok, v
    ok, v = pcall(function() return CharacterStat[name] end)
    if ok and v ~= nil then return v end
    ok, v = pcall(function() return CharacterStat.valueOf(name) end)
    if ok and v ~= nil then return v end
    ok, v = pcall(function() return CharacterStat.FromString(name) end)
    if ok and v ~= nil then return v end
    return nil
end

-- ลองเขียนหลายรูปแบบ ทุกแบบตรวจผลด้วย statRead (อ่านจาก tostring)
function AE.setStat(log, label, player, st, name, target)
    local read  = function() return AE.statRead(st, name) end
    local E     = AE.statEnum(name)
    local cands = {}

    -- ทางที่คาดว่าถูก: enum ก่อนเสมอ
    if E ~= nil then
        cands[#cands + 1] = { t = "set(CharacterStat." .. name .. ")",
                              w = function() st:set(E, target) end }
        cands[#cands + 1] = { t = "setValue(CharacterStat." .. name .. ")",
                              w = function() st:setValue(E, target) end }
        cands[#cands + 1] = { t = "setStat(CharacterStat." .. name .. ")",
                              w = function() st:setStat(E, target) end }
        cands[#cands + 1] = { t = "Set(CharacterStat." .. name .. ")",
                              w = function() st:Set(E, target) end }
        cands[#cands + 1] = { t = "char:setStat(CharacterStat." .. name .. ")",
                              w = function() player:setStat(E, target) end }
    end

    -- ทางสำรองแบบเดิม เผื่อ build อื่นยังรับสตริง
    cands[#cands + 1] = { t = "set" .. name .. "()",
                          w = function() st["set" .. name](st, target) end }
    cands[#cands + 1] = { t = 'set("' .. name .. '")',
                          w = function() st:set(name, target) end }
    cands[#cands + 1] = { t = "." .. name,
                          w = function() st[name] = target end }

    for i = 1, #cands do cands[i].k = "v"; cands[i].r = read end
    if E == nil then
        -- บอกให้ชัดว่าปัญหาอยู่ที่หา enum ไม่เจอ ไม่ใช่ชื่อค่าผิด
        cands[#cands + 1] = { k = "v", r = read, t = "CharacterStat." .. name .. " = nil",
                              w = function() error("CharacterStat enum not found", 0) end }
    end
    return AE.setNum(log, label, target, cands)
end

AE.EFFECTS = {}

-- ชื่อค่าทั้งหมดมาจาก tostring(stats) ของเกมจริง ไม่ใช่การเดา
-- ระวัง: B42 สะกด "Unhappiness" (n สองตัว) ไม่ใช่ "Unhappyness" แบบ B41
--        และใช้ "Intoxication" ไม่ใช่ "Drunkenness" · ไม่มีค่า "Fear" เลย
--        FoodSickness / Poison / Boredom / Unhappiness ย้ายมาอยู่บน Stats
--        ไม่ได้อยู่บน BodyDamage เหมือน B41 อีกแล้ว

-- ความอดทน + ความเมื่อยล้า  (ขวดเขียว)
function AE.EFFECTS.vigor(player, log)
    local st = AE.sc(player, "getStats")
    AE.setStat(log, "endurance", player, st, "Endurance", 1.0)
    AE.setStat(log, "fatigue",   player, st, "Fatigue",   0.0)
    local parts = AE.bodyParts(player)
    for i = 1, #parts do
        local bp = parts[i]
        AE.setNum(log, "stiffness", 0.0, { M(bp, "Stiffness", 0.0), F(bp, "stiffness", 0.0) })
    end
end

-- อาการปวด  (ขวดส้ม)
function AE.EFFECTS.relief(player, log)
    local st = AE.sc(player, "getStats")
    local parts, bd = AE.bodyParts(player)
    AE.setStat(log, "pain", player, st, "Pain", 0.0)
    for i = 1, #parts do
        local bp = parts[i]
        AE.setNum(log, "additionalPain", 0.0,
            { M(bp, "AdditionalPain", 0.0), F(bp, "AdditionalPain", 0.0) })
        AE.setNum(log, "stiffness", 0.0, { M(bp, "Stiffness", 0.0), F(bp, "stiffness", 0.0) })
    end
    AE.setNum(log, "painReduction", 100.0, { M(bd, "PainReduction", 100.0) })
end

-- คลื่นไส้  (ขวดทอง)
function AE.EFFECTS.settle(player, log)
    local st = AE.sc(player, "getStats")
    AE.setStat(log, "sickness",     player, st, "Sickness",     0.0)
    AE.setStat(log, "foodSickness", player, st, "FoodSickness", 0.0)
    AE.setStat(log, "poison",       player, st, "Poison",       0.0)
end

-- ซึมเศร้า + เครียด  (ขวดฟ้า)
function AE.EFFECTS.calm(player, log)
    local st = AE.sc(player, "getStats")
    AE.setStat(log, "stress",      player, st, "Stress",      0.0)
    AE.setStat(log, "panic",       player, st, "Panic",       0.0)
    AE.setStat(log, "unhappiness", player, st, "Unhappiness", 0.0)
    AE.setStat(log, "boredom",     player, st, "Boredom",     0.0)
    AE.setStat(log, "anger",       player, st, "Anger",       0.0)
    AE.setStat(log, "discomfort",  player, st, "Discomfort",  0.0)
    AE.setStat(log, "morale",      player, st, "Morale",      1.0)
    AE.setStat(log, "sanity",      player, st, "Sanity",      1.0)
end

-- ล้างทุกอย่าง  (ขวดแดง) - ส่วนอมตะชั่วคราวอยู่ฝั่ง client
-- v1.3.0 เพิ่มความหิว/กระหาย ตามที่ Pie บอกว่า "หิวแล้วกินขวดอมตะไม่หาย"
function AE.EFFECTS.panacea(player, log)
    AE.EFFECTS.vigor(player, log)
    AE.EFFECTS.relief(player, log)
    AE.EFFECTS.settle(player, log)
    AE.EFFECTS.calm(player, log)

    local st = AE.sc(player, "getStats")

    -- "ควรล้างทุก debuff" - ค่าที่เหลือทั้งหมดจาก tostring(stats)
    -- ยกเว้น ZombieInfection / ZombieFever ที่ตกลงกันว่าไม่แตะ
    AE.setStat(log, "wetness",      player, st, "Wetness",            0.0)
    AE.setStat(log, "nicotine",     player, st, "NicotineWithdrawal", 0.0)
    AE.setStat(log, "idleness",     player, st, "Idleness",           0.0)
    AE.cleanUp(player, log)

    if not AE.panaceaFeeds() then return end
    AE.setStat(log, "hunger",       player, st, "Hunger",       0.0)
    AE.setStat(log, "thirst",       player, st, "Thirst",       0.0)
    AE.setStat(log, "intoxication", player, st, "Intoxication", 0.0)
end

--------------------------------------------------------------------------
-- ความสกปรก + กลิ่นเหม็น
-- ในภาพของ Pie: "ความสกปรก 9" และ "กลิ่นเหม็นรุนแรง 25.0" ยังไม่เป็นศูนย์
-- สองค่านี้ไม่ได้อยู่บน Stats แต่มาจากคราบบนเสื้อผ้าและบนตัว
--------------------------------------------------------------------------
function AE.cleanUp(player, log)
    local worn = AE.sc(player, "getWornItems")
    local n    = AE.sc(worn, "size")
    if type(n) == "number" then
        for i = 0, n - 1 do
            local slot = AE.sc(worn, "get", i)
            local it   = AE.sc(slot, "getItem")
            if it ~= nil then
                AE.try(log, "clothDirt",  function() it:setDirtyness(0.0) end)
                AE.try(log, "clothBlood", function() it:setBloodLevel(0.0) end)
            end
        end
    end
    local parts = AE.bodyParts(player)
    for i = 1, #parts do
        local bp = parts[i]
        AE.try(log, "bodyDirt",  function() bp:setDirtyness(0.0) end)
        AE.try(log, "bodyBlood", function() bp:setBloodLevel(0.0) end)
    end
end

AE.__M, AE.__F = M, F      -- ให้ healWounds ใช้ต่อ


--------------------------------------------------------------------------
-- รักษาบาดแผล (ใช้ระหว่างช่วงอมตะของขวดแดง)
-- ห้ามแตะเชื้อซอมบี้ เว้นแต่เจ้าของเซิร์ฟเปิด Sandbox เอง
--------------------------------------------------------------------------
function AE.healWounds(player, log)
    local parts, bd = AE.bodyParts(player)
    AE.try(log, "overallHealth", function() bd:setOverallBodyHealth(100.0) end)
    for i = 1, #parts do
        local bp = parts[i]
        -- setHealth() ไม่มีใน B42 (ยืนยันจากล็อก) เดาว่าเป็นฟิลด์ Health
        -- probe: getHealth() ใช้ได้ แต่ setHealth() ไม่มี -> น่าจะเป็น SetHealth (S ใหญ่)
        -- ตรวจผลด้วย getHealth() ที่ยืนยันแล้วว่าอ่านได้จริง
        local readH = function() return AE.sc(bp, "getHealth") end
        AE.setNum(log, "partHealth", 100.0, {
            { k = "v", t = "SetHealth()", r = readH, w = function() bp:SetHealth(100.0) end },
            { k = "v", t = "setHealth()", r = readH, w = function() bp:setHealth(100.0) end },
            { k = "v", t = ".Health",     r = readH, w = function() bp.Health = 100.0 end },
        })
        AE.try(log, "bleeding",     function() bp:setBleeding(false) end)
        AE.try(log, "bleedingTime", function() bp:setBleedingTime(0.0) end)
        AE.try(log, "deepWound",    function() bp:setDeepWounded(false) end)
        AE.try(log, "fracture",     function() bp:setFractureTime(0.0) end)
        AE.try(log, "burn",         function() bp:setBurnTime(0.0) end)
        AE.try(log, "cut",          function() bp:setCut(false) end)
    end

    -- ปิดไว้เป็นค่าเริ่มต้น เชื้อซอมบี้ไม่ถูกแตะ
    if AE.curesInfection() then
        AE.try(log, "CUREinfected",      function() bd:setInfected(false) end)
        AE.try(log, "CUREinfectionLevel", function() bd:setInfectionLevel(0.0) end)
        for i = 1, #parts do
            local bp = parts[i]
            AE.try(log, "CUREpartInfect", function() bp:setInfectedWound(false) end)
            AE.try(log, "CUREbitten",     function() bp:setBitten(false) end)
        end
    end
end

--------------------------------------------------------------------------
-- ขวด 5 ใบ
--------------------------------------------------------------------------
AE.ELIXIRS = {
    { id = "Base.AkaElixir_Vigor",   key = "vigor",   invuln = false,
      done = "The ache drains out of your legs." },
    { id = "Base.AkaElixir_Relief",  key = "relief",  invuln = false,
      done = "The pain fades away." },
    { id = "Base.AkaElixir_Settle",  key = "settle",  invuln = false,
      done = "Your stomach settles." },
    { id = "Base.AkaElixir_Calm",    key = "calm",    invuln = false,
      done = "Your head clears." },
    { id = "Base.AkaElixir_Panacea", key = "panacea", invuln = true,
      done = "Everything goes quiet. Nothing can touch you." },
}

AE.BY_TYPE = {}
for i = 1, #AE.ELIXIRS do AE.BY_TYPE[AE.ELIXIRS[i].id] = AE.ELIXIRS[i] end

function AE.defOf(item)
    if item == nil then return nil end
    local ft = AE.sc(item, "getFullType")
    if type(ft) ~= "string" then return nil end
    return AE.BY_TYPE[ft]
end

AE.__ready = true
return AE
