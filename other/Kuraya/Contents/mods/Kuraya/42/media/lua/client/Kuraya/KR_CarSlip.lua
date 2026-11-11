-- ==============================================================================
-- Kuraya — client/Kuraya/KR_CarSlip.lua
-- คลิกขวาที่ "ใบ" แล้วแกะเป็นของจริง   ใบรถ -> รถ   ใบสัตว์ -> สัตว์
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- **ชื่อไฟล์บอกแค่ครึ่งเดียวของสิ่งที่มันทำ และนั่นตั้งใจ**  (0.6.16)
--
-- 0.6.16 เพิ่มใบสัตว์เข้ามา ตอนนั้นชื่อที่ตรงคือ KR_SlipMenu.lua
-- แต่การเปลี่ยนชื่อไฟล์ในม็อดที่คนอัปเดตด้วยการ "ก๊อปทับโฟลเดอร์" เป็นกับดัก:
-- เครื่องที่ก๊อปทับจะเหลือ KR_CarSlip.lua ตัวเก่าค้างอยู่ด้วย  PZ โหลดทั้งสองไฟล์
-- แล้วยามกันโหลดซ้ำคนละชื่อกัน = เมนูคลิกขวาขึ้น "แกะใบรถ" สองบรรทัด
-- และไม่มีอะไรบนจอบอกว่าทำไม
--
-- ชื่อที่อธิบายไม่ครบ แก้ได้ด้วยคอมเมนต์  ไฟล์ค้างแก้ไม่ได้ด้วยอะไรเลย
--
-- ทางเลือกอีกทางคือก๊อปทั้งไฟล์เป็น KR_PetSlip.lua ซึ่งแปลว่านับจากวันนั้น
-- ทุกการแก้เมนูต้องจำให้ได้ว่ามีสองที่  และวันที่ลืม มันจะพังแค่ฝั่งเดียว
--
-- ไฟล์นี้ทำอย่างเดียว: เติมหนึ่งบรรทัดลงเมนูคลิกขวาของใบ แล้วส่งไอดีใบไปให้เซิร์ฟ
-- **มันไม่ตัดสินอะไรเลย** ที่ว่าง รุ่นรถ ชนิดสัตว์ สิทธิ์ เซิร์ฟตัดสินหมด
--
-- เหตุผลไม่ใช่ความสวยงามของสถาปัตยกรรม แต่เป็นเรื่องความปลอดภัยตรง ๆ:
-- ถ้าไคลเอนต์บอกได้ว่าใบนี้เป็นของอะไร ใครก็ขอของที่แพงที่สุดได้ด้วยแพ็กเก็ตปลอมใบเดียว
-- ไคลเอนต์จึงบอกได้แค่ "ใบไหน" ส่วน "ใบนั้นเป็นอะไร" เซิร์ฟอ่านจากของของตัวเอง
--
-- อีกข้อ: เมนูนี้ **ขึ้นเสมอ** ไม่ได้ซ่อนตอนอยู่ในร่มหรือที่แคบ
-- เมนูที่หายไปคือเมนูที่ผู้เล่นคิดว่าม็อดพัง  เมนูที่ขึ้นแล้วบอกว่า "ออกไปที่โล่งก่อน"
-- คือเมนูที่สอนให้เขาทำถูกในครั้งหน้า
-- ==============================================================================
require("Kuraya/KR_Const")
require("Kuraya/KR_Client")

print("[Kuraya] KR_CarSlip  v" .. KR.VERSION .. "  (car + pet slips)")

-- ยามกันโหลดซ้ำ ต้องอยู่ก่อนบรรทัดที่ผูก Events (เหตุผลเดียวกับ KR_Entry)
if KR.__loaded_carslip then return end
KR.__loaded_carslip = true

-- ------------------------------------------------------------------------------
-- ใบแต่ละชนิดต่างกันแค่สี่อย่าง  ชนิดไอเทม / คำสั่งที่ยิง / ช่อง ModData / คำบนเมนู
-- เขียนไว้เป็นข้อมูล ไม่ใช่เป็น if  ใบชนิดที่สามเพิ่มได้ด้วยการเติมหนึ่งก้อน
-- ------------------------------------------------------------------------------
local SLIPS = {
    {
        type  = KR.SLIP,
        cmd   = KR.CMD.CAR_UNPACK,
        md    = { "krVehName", "krVehicle" },
        named = function(n) return KR.L("แกะใบรถ: ", "Unpack vehicle: ") .. tostring(n) end,
        plain = function()  return KR.L("แกะใบรถ", "Unpack vehicle") end,
    },
    {
        type  = KR.PET_SLIP,
        cmd   = KR.CMD.PET_UNPACK,
        md    = { "krPetName", "krPet" },
        named = function(n) return KR.L("ปล่อยสัตว์ออกมา: ", "Let the animal out: ") .. tostring(n) end,
        plain = function()  return KR.L("ปล่อยสัตว์ออกมา", "Let the animal out") end,
    },
}

-- ------------------------------------------------------------------------------
-- เมนูส่งของมาได้สองทรง  ไอเทมเดี่ยว ๆ กับกล่องที่มี .items ข้างใน
-- ตัวเรียกไม่ควรต้องรู้ว่าครั้งนี้เป็นทรงไหน
-- ------------------------------------------------------------------------------
local function flatten(items)
    local out = {}
    for i = 1, #items do
        local v = items[i]
        if type(v) == "table" and v.items then
            for j = 1, #v.items do out[#out + 1] = v.items[j] end
        else
            out[#out + 1] = v
        end
    end
    return out
end

local function hasMethod(obj, name)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj[name] end)
    return ok and type(v) == "function"
end

-- ใบใบนี้เป็นใบชนิดไหน  ไม่ใช่ใบของเราเลยก็คืน nil
local function slipKindOf(it)
    if not hasMethod(it, "getFullType") then return nil end
    local ok, ft = pcall(function() return it:getFullType() end)
    if not ok then return nil end
    for _, s in ipairs(SLIPS) do
        if ft == s.type then return s end
    end
    return nil
end

-- ชื่อของที่จะโชว์บนเมนู
--
-- ModData ของไอเทมอาจยังไม่วิ่งมาถึงไคลเอนต์  นั่นไม่ใช่เหตุให้ซ่อนเมนู
-- ไม่รู้ชื่อก็เขียนกลาง ๆ ไป เซิร์ฟรู้อยู่แล้วว่าใบนี้เป็นอะไร
local function thingName(it, spec)
    local ok, md = pcall(function() return it:getModData() end)
    if ok and type(md) == "table" then
        for _, k in ipairs(spec.md) do
            local n = md[k]
            if type(n) == "string" and n ~= "" then return n end
        end
    end
    if hasMethod(it, "getName") then
        local okN, n = pcall(function() return it:getName() end)
        -- ชื่อที่เซิร์ฟประทับไว้คือ "<ชนิดใบ> - <ของ>"  ตัดหัวออกให้เหลือของ
        if okN and type(n) == "string" then
            local tail = n:match("%-%s*(.+)$")
            if tail and tail ~= "" then return tail end
        end
    end
    return nil
end

local function idOf(it)
    if not hasMethod(it, "getID") then return nil end
    local ok, v = pcall(function() return it:getID() end)
    if not ok or v == nil then return nil end
    return tostring(v)
end

-- ------------------------------------------------------------------------------
local function onInvMenu(playerNum, context, items)
    if playerNum ~= 0 then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local seen = {}
    for _, it in ipairs(flatten(items or {})) do
        local spec = slipKindOf(it)
        local id   = spec and idOf(it) or nil
        if id and not seen[id] then
            seen[id] = true

            local name  = thingName(it, spec)
            local label = name and spec.named(name) or spec.plain()

            context:addOption(label, player, function()
                if KRClient and KRClient.req then
                    KRClient.req(spec.cmd, { item = id })
                end
            end)
        end
    end
end

-- ==============================================================================
-- event ที่บิลด์นี้อาจไม่มี ต้องเช็กก่อนผูก  ผูกตรง ๆ แล้วบิลด์ที่ไม่มี = ม็อดไม่โหลดทั้งตัว
-- ==============================================================================
local function safeOn(name, fn)
    local ev = Events and Events[name]
    if not ev or type(ev.Add) ~= "function" then
        print("[Kuraya] event not on this build, skipped: " .. tostring(name))
        return
    end
    ev.Add(function(...)
        local ok, e = pcall(fn, ...)
        if not ok then print("[Kuraya] " .. name .. " -> " .. tostring(e)) end
    end)
end

safeOn("OnFillInventoryObjectContextMenu", onInvMenu)

return true
