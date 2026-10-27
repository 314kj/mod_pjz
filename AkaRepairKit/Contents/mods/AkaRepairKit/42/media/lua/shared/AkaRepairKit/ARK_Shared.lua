-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- AkaRepairKit - shared config + pure repair math.
-- โหลดได้ทั้ง client / server / SP  ห้ามอ้างของฝั่งจอในไฟล์นี้

ARK = ARK or {}
if ARK.__ready then return ARK end

ARK.NAME    = "AkaRepairKit"
ARK.VERSION = "2.0.0"

-- บัตร 5 ระดับ  tier -> fullType / % ที่ซ่อมได้ (ค่าเริ่มต้น ปรับได้ใน Sandbox)
ARK.CARDS = {
    { tier = 1, id = "Base.AkaRepairCard_1", pct = 5   },
    { tier = 2, id = "Base.AkaRepairCard_2", pct = 10  },
    { tier = 3, id = "Base.AkaRepairCard_3", pct = 20  },
    { tier = 4, id = "Base.AkaRepairCard_4", pct = 50  },
    { tier = 5, id = "Base.AkaRepairCard_5", pct = 100 },
}

ARK.TIER_OF = {}
ARK.PCT_DEFAULT = {}
for i = 1, #ARK.CARDS do
    local c = ARK.CARDS[i]
    ARK.TIER_OF[c.id]      = c.tier
    ARK.PCT_DEFAULT[c.tier] = c.pct
end

--------------------------------------------------------------------------
-- safe call  ---------------------------------------------------------------
-- Kahlua คืน object "none" (ไม่ใช่ nil) เวลาเรียกเมธอดที่ไม่มี
-- การเช็ค `if obj.method then` จึงเป็นจริงเสมอแล้วไประเบิดตอนเรียก
-- ทุกเมธอดที่ไม่ 100% ว่ามีในทุก build ต้องผ่านตัวนี้
--------------------------------------------------------------------------
-- สำคัญ: ต้องเรียกด้วย "จำนวนอาร์กิวเมนต์เท่าที่ของจริงรับ" เป๊ะ
-- Kahlua เช็ค arity ของเมธอด Java แบบเข้มงวด การส่ง nil ต่อท้ายไม่ได้แปลว่า
-- "ไม่ส่ง" แต่นับเป็นอาร์กิวเมนต์จริง ๆ  obj[name](obj, nil, nil) บนเมธอดที่รับ 0 ตัว
-- จะได้ java.lang.RuntimeException: expected 0 arguments, got 2 ทันที
function ARK.sc(obj, name, a, b)
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
-- global function ของเกม - ต้องเช็ค "ชนิด" ก่อนเรียกเสมอ
--
-- Kahlua ไม่จับ error ของการเรียกค่าที่ไม่ใช่ฟังก์ชันให้ครบ (pcall ไม่พอ
-- มันยัง dump stack trace ทุกครั้ง) และเมธอด/ฟังก์ชันของ B42 ก็หายไปได้
-- ระหว่างเวอร์ชัน syncItemFields เพิ่งมีใน 42 ไม่มีใน 41
--------------------------------------------------------------------------
function ARK.gfn(name)
    local ok, f = pcall(function() return _G[name] end)
    if ok and type(f) == "function" then return f end
    return nil
end

--------------------------------------------------------------------------
-- ประกาศการเปลี่ยนสภาพไอเทมด้วย "ช่องทางของเกมเอง"
--
-- นี่คือหัวใจของ v2.0.0
-- เดิมเราแก้ค่าฝั่งไคลเอนต์แล้วยิงคำสั่งของม็อดเองไปบอกเซิร์ฟ
-- สำเนาสองฝั่งจึงไม่ตรงกันชั่วขณะ ซึ่งตรงกับรูปทรงที่ anti-cheat ของ PZ
-- (AntiCheatProtectionType12/13 - หมวดกระเป๋า/ไอเทม) เฝ้าดูอยู่พอดี
--
-- ตอนนี้เซิร์ฟเป็นคนแก้ แล้วบอกทุกคนด้วย syncItemFields() ซึ่งเป็น
-- ฟังก์ชันเดียวกับที่เกมใช้เองตอนสภาพอาวุธเปลี่ยน
-- คืนชื่อทางที่ใช้ได้จริง เพื่อให้ console.txt ตอบได้ว่า build นี้ใช้ทางไหน
--------------------------------------------------------------------------
function ARK.sync(player, item)
    local used = {}

    local f = ARK.gfn("syncItemFields")
    if f ~= nil and pcall(function() f(player, item) end) then
        used[#used + 1] = "syncItemFields"
    end

    if ARK.sc(item, "IsWeapon") == true then
        local g = ARK.gfn("syncHandWeaponFields")
        if g ~= nil and pcall(function() g(player, item) end) then
            used[#used + 1] = "syncHandWeaponFields"
        end
    end

    if #used == 0 then                      -- build เก่าที่ยังไม่มีสองตัวบน
        local h = ARK.gfn("sendItemStats")
        if h ~= nil and pcall(function() h(item) end) then
            used[#used + 1] = "sendItemStats"
        end
    end

    if #used == 0 then return "none" end
    return table.concat(used, "+")
end

--------------------------------------------------------------------------
-- Sandbox
--------------------------------------------------------------------------
local function sv()
    return SandboxVars and SandboxVars.AkaRepairKit or nil
end

function ARK.pct(tier)
    local s = sv()
    local v = s and s["Tier" .. tostring(tier) .. "Percent"]
    if type(v) == "number" and v > 0 then return v end
    return ARK.PCT_DEFAULT[tier] or 0
end

function ARK.allowFirearms()
    local s = sv()
    if s and type(s.AllowFirearms) == "boolean" then return s.AllowFirearms end
    return true
end

function ARK.reduceWear()
    local s = sv()
    if s and type(s.ReduceWear) == "boolean" then return s.ReduceWear end
    return true
end

--------------------------------------------------------------------------
-- ไอเทม
--------------------------------------------------------------------------

-- บัตรใบนี้ tier อะไร (nil = ไม่ใช่บัตรของเรา)
function ARK.tierOf(item)
    if item == nil then return nil end
    local ft = ARK.sc(item, "getFullType")
    if type(ft) ~= "string" then return nil end
    return ARK.TIER_OF[ft]
end

-- อาวุธชิ้นนี้ซ่อมด้วยบัตรได้ไหม
-- ใช้การเช็ค "คลาส" ตอนรันจริง ไม่ใช่รายชื่อไอเทมตายตัว
-- อาวุธจากม็อดตัวไหนก็เข้าเงื่อนไขนี้เองโดยไม่ต้องรู้จักกันมาก่อน
function ARK.canRepair(item)
    if item == nil then return false end

    -- ปืนกับอาวุธประชิดผ่านทางเดียวกัน ทั้งคู่เป็น HandWeapon
    -- ถาม 2 ทาง: IsWeapon() ของ InventoryItem และคลาสตรง ๆ
    -- ม็อดที่ทำ subclass แปลก ๆ จน IsWeapon() ตอบไม่ตรง ยังรอดทางที่สอง
    local isW = (ARK.sc(item, "IsWeapon") == true)
    if not isW then
        local okI, res = pcall(function() return instanceof(item, "HandWeapon") end)
        isW = (okI and res == true)
    end
    if not isW then return false end

    -- บัตรของเราเองห้ามซ่อม (กันเคสประหลาด)
    if ARK.tierOf(item) then return false end

    local max = ARK.sc(item, "getConditionMax")
    local cur = ARK.sc(item, "getCondition")
    if type(max) ~= "number" or type(cur) ~= "number" then return false end
    if max <= 0 then return false end
    if cur >= max then return false end

    if not ARK.allowFirearms() then
        if ARK.sc(item, "isRanged") == true then return false end
    end

    return true
end

-- ซ่อมแล้วจะได้ condition เท่าไหร่ (คำนวณล้วน ไม่แตะไอเทม)
function ARK.newCondition(item, pct)
    local max = ARK.sc(item, "getConditionMax")
    local cur = ARK.sc(item, "getCondition")
    if type(max) ~= "number" or type(cur) ~= "number" or max <= 0 then return nil end

    local add = math.ceil(max * pct / 100)
    if add < 1 then add = 1 end          -- 5% ของอาวุธ 10 ขีด ต้องได้อย่างน้อย 1
    local newCond = cur + add
    if newCond > max then newCond = max end
    return newCond
end

-- ค่า haveBeenRepaired ใหม่ (nil = ไม่ต้องแตะ)
-- ลดได้อย่างเดียว ห้ามเพิ่ม และไม่ต่ำกว่า 1
-- (ของใหม่ที่ยังไม่เคยซ่อมจะไม่ถูกแตะเลย เพราะสูตรของเกมหารด้วยค่านี้)
function ARK.newWear(item, pct)
    if not ARK.reduceWear() then return nil end
    local hbr = ARK.sc(item, "getHaveBeenRepaired")
    if type(hbr) ~= "number" then return nil end

    local target
    if pct >= 100 then target = 1 else target = hbr - 1 end
    if target < 1 then target = 1 end
    if target >= hbr then return nil end
    return target
end

ARK.__ready = true
return ARK
