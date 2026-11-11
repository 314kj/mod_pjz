-- ==============================================================================
-- Kuraya — server/Kuraya/KR_TownRank.lua
-- สะพานไป HF Town Rank สำหรับดึง CP
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- API จริงของ HF Town Rank (อ่านจากโค้ดม็อดโดยตรง ไม่ได้เดา)
--   HF_Town_Rank_API.GetHonorPoints(player)          -> integer   (0 ถ้าไม่มี player)
--   HF_Town_Rank_API.DeductHonorPoints(player, n)    -> boolean   (false ถ้าแต้มไม่พอ)
--   HF_Town_Rank_API.AddHonorPoints(player, n)       -> ไม่คืนค่า
--   HF_Town_Rank_API.GetPlayerStats(player)          -> table | nil
--
-- สามข้อที่ต้องระวัง และเป็นเหตุผลที่ต้องมีไฟล์นี้แทนที่จะเรียกตรง ๆ
--
-- 1. รับ IsoPlayer ไม่ใช่ชื่อ
--    ทุกฟังก์ชันรับ object ของผู้เล่น ไม่ใช่ username string เหมือน Akacount
--    ถ้าส่งชื่อไปจะได้ 0 เงียบ ๆ ไม่ error  ซึ่งเป็นบั๊กที่หายากที่สุด
--    -> ผู้เล่นออฟไลน์อ่าน/หัก CP ไม่ได้เลย ต้องออกแบบให้ไม่ต้องทำ
--
-- 2. CP เป็นจำนวนเต็ม  CASH เป็นสตางค์
--    Akacount เก็บเงินเป็น integer สตางค์ (250.75 -> 25075)
--    Town Rank เก็บ PersonalRep เป็นแต้มเต็ม ๆ
--    ห้ามเอาสองหน่วยนี้มาบวกกันหรือส่งข้ามกันเด็ดขาด -> KR.toCharge()
--
-- 3. เป็น server-only
--    HF_Town_Rank_API วางอยู่ใน media/lua/server/ ซึ่ง PZ โหลดบนไคลเอนต์ MP ด้วย
--    ตัวแปรจะ "มีอยู่" บนไคลเอนต์ แต่ DB ที่มันอ่านเป็นสำเนาไคลเอนต์ ไม่ใช่ของจริง
--    เรียกจากไคลเอนต์แล้วจะได้เลขที่ดูเหมือนถูกแต่ผิด -> ต้อง guard ด้วย isHost()
-- ==============================================================================
require("Kuraya/KR_Const")

KR.tr = KR.tr or {}
local T = KR.tr

local function isHost()
    local sv = (type(isServer) == "function") and isServer() or false
    if sv then return true end
    local cl = (type(isClient) == "function") and isClient() or false
    if cl then return false end
    return true
end

-- resolve ตอนเรียกทุกครั้ง ห้ามจับเก็บเป็น local ที่ file scope
-- ถ้า HF Town Rank โหลดทีหลัง จะได้ nil ค้างตลอดเซสชัน
local function api()
    local a = HF_Town_Rank_API
    if type(a) ~= "table" then return nil end
    return a
end

local _loggedMissing = false
local function warnOnce()
    if _loggedMissing then return end
    _loggedMissing = true
    print("[Kuraya] HF Town Rank not found - CP will read as 0 and CP purchases will be refused")
end

-- ------------------------------------------------------------------------------
-- มีให้ใช้ไหม
-- ------------------------------------------------------------------------------
function T.available()
    local a = api()
    return a ~= nil and type(a.GetHonorPoints) == "function"
end

-- ------------------------------------------------------------------------------
-- อ่าน CP   คืน 0 เสมอถ้าอะไรผิดพลาด ไม่โยน error
-- ------------------------------------------------------------------------------
function T.get(player)
    if not isHost() then return 0 end
    if not player then return 0 end
    local a = api()
    if not (a and a.GetHonorPoints) then warnOnce(); return 0 end
    local ok, v = pcall(a.GetHonorPoints, player)
    if not ok then
        print("[Kuraya] GetHonorPoints failed -> " .. tostring(v))
        return 0
    end
    return math.floor(tonumber(v) or 0)
end

-- ------------------------------------------------------------------------------
-- หัก CP
--   คืน (ok, err)  ไม่เคยโยน error ออกไป
--   DeductHonorPoints คืน false เมื่อแต้มไม่พอ ซึ่งเป็นกรณีปกติ ไม่ใช่ความผิดพลาด
-- ------------------------------------------------------------------------------
function T.deduct(player, amount)
    if not isHost() then return false, "client side" end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "bad amount" end
    if not player   then return false, "no player" end

    local a = api()
    if not (a and a.DeductHonorPoints) then warnOnce(); return false, "Town Rank not loaded" end

    local ok, res = pcall(a.DeductHonorPoints, player, amount)
    if not ok then
        print("[Kuraya] DeductHonorPoints failed -> " .. tostring(res))
        return false, "town rank error"
    end
    if res ~= true then return false, "not enough CP" end
    return true
end

-- ------------------------------------------------------------------------------
-- คืน CP  (ใช้ตอน rollback เมื่อหักไปแล้วแต่ส่งของไม่สำเร็จ)
--   AddHonorPoints ไม่คืนค่า จึงยืนยันไม่ได้ว่าสำเร็จ
--   ต้องอ่านยอดก่อนและหลังเพื่อพิสูจน์ ไม่งั้นเงินคืนหายเงียบ ๆ แล้วไม่มีใครรู้
-- ------------------------------------------------------------------------------
function T.refund(player, amount)
    if not isHost() then return false end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or not player then return false end

    local a = api()
    if not (a and a.AddHonorPoints) then warnOnce(); return false end

    local before = T.get(player)
    local ok, err = pcall(a.AddHonorPoints, player, amount)
    if not ok then
        print("[Kuraya] AddHonorPoints failed -> " .. tostring(err))
        return false
    end
    local after = T.get(player)
    if after < before + amount then
        -- ต่อสตริงเอง ไม่ใช้ string.format
        --
        -- Kahlua (ตัว Lua ที่ PZ ใช้) โยน "invalid option '%' to 'format'" กับรูปแบบบางแบบ
        -- ที่ Lua มาตรฐานรับได้  และบรรทัดนี้ทำงานเฉพาะตอนมีอะไรผิดพลาดอยู่แล้ว
        -- = ทางที่ไม่มีใครเคยเดินตอนเทส
        -- บรรทัด log ที่พังเองในทางแก้ปัญหา คือการเปลี่ยนบั๊กเล็กให้กลายเป็นบั๊กที่มองไม่เห็น
        print("[Kuraya] CP refund did not land  before=" .. tostring(before) ..
              "  after=" .. tostring(after) ..
              "  expected=" .. tostring(before + amount))
        return false
    end
    return true
end

-- ------------------------------------------------------------------------------
-- ข้อมูลประกอบ (ยศ / สถิติ) ไว้โชว์ในหน้าร้าน  ไม่มีก็ไม่เป็นไร
-- ------------------------------------------------------------------------------
function T.stats(player)
    if not isHost() or not player then return nil end
    local a = api()
    if not (a and a.GetPlayerStats) then return nil end
    local ok, v = pcall(a.GetPlayerStats, player)
    return ok and v or nil
end

return T
