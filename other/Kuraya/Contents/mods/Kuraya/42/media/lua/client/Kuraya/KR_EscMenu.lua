-- ==============================================================================
-- Kuraya — client/Kuraya/KR_Entry.lua  (ชื่อไฟล์ยังเป็น KR_EscMenu เพื่อไม่ให้ลำดับโหลดเปลี่ยน)
-- ทางเข้าร้าน
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- เมนู ESC ถูกถอดออกแล้ว  เหตุผลคือมันเป็นทางเข้าที่ต้อง "จำ" ว่ามีอยู่
-- คนที่ไม่เคยอ่านประกาศจะไม่มีวันรู้ว่ากดตรงไหน
--
-- ตอนนี้เหลือสามทาง เรียงตามที่คนจะเจอเองได้ง่ายที่สุด
--   1. ปุ่มลอยข้างจอ   (KR_FloatBtn.lua)  เห็นตลอดเวลา ลากได้ ล็อกได้
--   2. ปุ่มลัดบนคีย์บอร์ด  ตั้งเองได้ในหน้า Options
--   3. คลิกขวาในโลก ใต้เมนู AKA Mod  รวมถึงเมนูแอดมินสำหรับลงทะเบียนแผงตลาดสด
-- ==============================================================================
require("Kuraya/KR_Const")
print("[Kuraya] KR_Entry  v" .. KR.VERSION)
require("Kuraya/KR_UI_Shop")
-- เมนูคลิกขวาใช้ตัวช่วยกลางของตระกูล AKA  shared/AKA_Menu.lua  (ดูข้อ 2 ข้างล่าง)
-- ไม่ require เอง  ไฟล์ใน shared/ ถูกโหลดก่อน client/ เสมอ  Kaandther ก็พึ่งกฎเดียวกัน

-- ------------------------------------------------------------------------------
-- ยามกันโหลดซ้ำ  ต้องอยู่ก่อนบรรทัดที่ผูก Events ทุกบรรทัด
--
-- B42 โหลด media ของม็อดจาก "สองที่" คือ common/ กับโฟลเดอร์เวอร์ชันที่ตรงกับบิลด์
-- ม็อดนี้เคยมีต้นไม้ lua เหมือนกันเป๊ะทั้งสองที่  ไฟล์ฝั่งไคลเอนต์จึงถูกรันสองรอบ
--
-- ฝั่งเซิร์ฟรอดมาได้เพราะ KR_Server มียามแบบนี้อยู่แล้ว  ฝั่งไคลเอนต์ไม่มี ผลคือ
--   Events.OnServerCommand ถูกผูกสองครั้ง   -> ป้ายเด้งซ้อนสองอัน
--   เมนูคลิกขวาถูกเติมสองครั้ง              -> มี HF Shop / Fresh Market อย่างละสองบรรทัด
--   ปุ่มลอยถูกสร้างสองอันซ้อนกัน
--
-- แพ็กเกจนี้เหลือ lua ที่เดียวแล้ว (ดู _pack.py) ยามนี้จึงไม่ควรทำงานเลย
-- แต่มันต้องอยู่: ต้นเหตุจริงคือ "ไฟล์นี้ทนการถูกรันสองรอบไม่ได้" ไม่ใช่โครงโฟลเดอร์
-- โครงโฟลเดอร์แก้อาการ ยามตัวนี้แก้สาเหตุ
-- ------------------------------------------------------------------------------
if KR.__loaded_entry then return end
KR.__loaded_entry = true

-- LABEL ถูกถอดออกพร้อมกับบรรทัดคลิกขวา  ปุ่มลอยกับปุ่มลัดคือทางเข้าที่เหลือ
local BIND_NAME = "Kuraya: Open shop"

local function openShop()
    if KRShopUI and KRShopUI.toggle then KRShopUI.toggle() end
end

-- ==============================================================================
-- 1 · ปุ่มลัดบนคีย์บอร์ด
-- ==============================================================================
local function installKeyBind()
    if not keyBinding then return end
    for _, b in ipairs(keyBinding) do
        if b.value == BIND_NAME then return end     -- ลงทะเบียนซ้ำไม่ได้
    end
    table.insert(keyBinding, { value = BIND_NAME, key = Keyboard.KEY_H })
end

local function onKeyPressed(key)
    local want
    pcall(function() want = getCore():getKey(BIND_NAME) end)
    if want and key == want then
        if ISTextEntryBox and ISTextEntryBox.focusedEntry then return end   -- กำลังพิมพ์อยู่
        openShop()
    end
end

-- ==============================================================================
-- 2 · คลิกขวาในโลก  ใต้เมนูแม่ AKA Mod
-- ==============================================================================
-- ------------------------------------------------------------------------------
-- "คนนี้เป็นแอดมินไหม" — คำตอบต้องมาจากเซิร์ฟเวอร์เท่านั้น
--
-- ของเดิมถาม player:getAccessLevel() ฝั่งไคลเอนต์ล้วน ซึ่งพังได้สองทาง
--   1. เกมที่โฮสต์เองหรือเปิดจากในเกม ผู้เล่นได้ระดับสิทธิ์ติดตัวมาโดยไม่ได้ตั้งใจ
--      แล้วบรรทัด "Fresh Market" ก็โผล่ในคลิกขวาของทุกคน
--      ตรงกับที่เจ้าของเซิร์ฟรายงานว่า "player/user คลิกขวาต้องไม่มี Fresh Market"
--   2. ต่อให้ค่านั้นถูก มันก็เป็นคำตอบที่ไคลเอนต์คำนวณเอง ซึ่งไม่ใช่แหล่งอ้างอิง
--
-- d.admin มาจาก isStaff() ฝั่งเซิร์ฟใน S.sync  เป็นค่าตัวเดียวกับที่เซิร์ฟใช้
-- ตัดสินตอนรับคำสั่งจริง  จอกับเซิร์ฟจึงพูดตรงกันเสมอ ไม่มีเมนูที่กดแล้วโดนปฏิเสธ
--
-- ยังไม่เคย sync = ยังไม่รู้ = ถือว่าไม่ใช่แอดมิน  ล้มไปทางปิดเสมอ
-- อย่างมากแอดมินที่เพิ่งเข้าเกมคลิกขวาอีกครั้งหลังร้าน sync รอบแรก (ไม่เกินสองวินาที)
-- ------------------------------------------------------------------------------
-- ชื่อ isStaff ไม่ใช่ isAdmin โดยตั้งใจ  PZ มีโกลบอลชื่อ isAdmin() อยู่แล้ว
-- ถ้าตั้งชื่อชนกัน โค้ดบรรทัดไหนที่อยู่เหนือบรรทัดนี้จะไปหยิบของ PZ มาใช้แทน
-- ซึ่งตอบเรื่อง "เครื่องนี้" ไม่ใช่ "คนนี้" = ผู้เล่นทุกคนกลายเป็นแอดมิน (lint กฎ 12)
local function isStaff(player)
    local d = KRClient and KRClient.data
    return (d and d.admin) == true
end

-- ------------------------------------------------------------------------------
-- 0.7.1 — ใช้ตัวช่วยของตระกูลที่ Kaandther ใช้อยู่แล้ว  AKA.getGroup(context, "Kuraya")
--
-- เจ้าของเซิร์ฟถ่ายคลิกขวามาให้ดู  มี "AKA Mod" สามแถวในเมนูเดียว
--
-- 0.7.0 แก้ด้วยการเขียนทะเบียนกลางขึ้นมาเอง (AKAMenu)  ซึ่ง **ผิดทาง**
-- ตระกูล AKA มีตัวช่วยกลางอยู่แล้วตั้งแต่ Kaandther:  media/lua/shared/AKA_Menu.lua
-- ใช้อยู่ใน Kaandther · Toileport · Kacha · Dunka  ทะเบียนตัวที่สองที่ใช้ชื่อโกลบอลคนละชื่อ
-- ไม่ได้รวมอะไรเลย มันแค่เพิ่ม "มาตรฐาน" เป็นสองอัน  ซึ่งคือต้นเหตุเดิมในร่างใหม่
--
-- ตอนนี้ส่งไฟล์นั้น **เหมือนกันทุกไบต์** ตามที่หัวไฟล์สั่ง แล้วเรียกแบบเดียวกับ Kaandther
--   AKA MOD  >  Kaandther  > ...
--            >  Kuraya     > Fresh Market : register a stall here
--            >  Toileport  > ...
-- ตัวช่วยมียามรุ่น (รุ่นสูงสุดชนะ ไม่ว่าโหลดลำดับไหน) และรับแถว "AKA MOD"/"AKA Mod"
-- ที่ม็อดอื่นสร้างไว้ก่อนมาใช้ต่อ  ม็อดจึงรวมกันได้แม้ตัวพิมพ์ต่างกัน
--
-- ถ้าตัวช่วยไม่โหลดด้วยเหตุผลใดก็ตาม  ตกไปวางแถวไว้ชั้นบนสุด (แบบเดียวกับ Kaandther)
-- แถวของแอดมินที่อยู่ผิดชั้น ดีกว่าแถวของแอดมินที่หายไปเลย
-- ------------------------------------------------------------------------------
local function krGroup(context)
    if type(AKA) == "table" and type(AKA.getGroup) == "function" then
        local ok, g = pcall(AKA.getGroup, context, "Kuraya")
        if ok and type(g) == "table" and type(g.addOption) == "function" then return g end
        print("[Kuraya] AKA.getGroup failed -> " .. tostring(g) .. "  (row goes top-level)")
    end
    return context
end

local function onWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    if playerNum ~= 0 then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    -- ------------------------------------------------------------------------
    -- ตรวจสิทธิ์ **ก่อน** ขอกลุ่ม  ไม่ใช่หลัง
    --
    -- AKA.getGroup สร้างแถว "AKA MOD" ทันทีที่ถูกเรียก
    -- เรียกก่อนเช็กสิทธิ์ = ผู้เล่นธรรมดาได้เมนูที่กางออกมาแล้วว่างเปล่า
    -- ซึ่งอ่านว่า "ม็อดพัง" และแย่กว่าไม่มีเมนูเลย
    -- ------------------------------------------------------------------------
    if not isStaff(player) then return end

    local d = KRClient and KRClient.data

    -- ------------------------------------------------------------------------
    -- บรรทัด "HF Shop" ถูกถอดออกใน 0.6.3
    --
    -- เจ้าของเซิร์ฟสั่งตรง ๆ ว่า "เอาคลิกขวาเปิด shop ออก ทางเข้าคือปุ่มลอย"
    -- ทางเข้าสองทางที่ทำเรื่องเดียวกันแปลว่าต้องดูแลสองทางตลอดไป
    --
    -- แผงตลาดสดยังต้องอยู่ที่นี่ เพราะมันผูกกับ "ตำแหน่งที่ยืนอยู่" ซึ่งเป็นข้อมูล
    -- ที่มีอยู่แค่ในเมนูคลิกขวา  และมันเห็นเฉพาะแอดมิน
    -- ------------------------------------------------------------------------
    local g = krGroup(context)
    local txt = (d and d.atMarket) and "Fresh Market : remove this stall"
                                    or "Fresh Market : register a stall here"
    g:addOption(txt, player, function()
        if KRClient then KRClient.req(KR.CMD.ADMIN_MARKET, {}) end
    end)
end

-- ==============================================================================
local function safeOn(name, fn)
    local ev = Events and Events[name]
    if ev and type(ev.Add) == "function" then
        ev.Add(function(...)
            local ok, e = pcall(fn, ...)
            if not ok then print("[Kuraya] " .. name .. " -> " .. tostring(e)) end
        end)
    end
end

safeOn("OnGameStart",                  function() pcall(installKeyBind) end)
safeOn("OnKeyPressed",                 onKeyPressed)
safeOn("OnFillWorldObjectContextMenu", onWorldMenu)

pcall(installKeyBind)

return true
