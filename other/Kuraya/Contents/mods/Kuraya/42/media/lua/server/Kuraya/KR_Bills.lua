-- ==============================================================================
-- Kuraya — server/Kuraya/KR_Bills.lua
-- หักบิลอัตโนมัติ  สะพานไปหาม็อด HF_Tax
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- HF_Tax เป็นม็อดของคนอื่น  **เราไม่แตะซอร์สของเขาแม้แต่บรรทัดเดียว**
-- ไฟล์นี้อ่านข้อมูลของเขาและเรียกฟังก์ชันของเขาเท่านั้น
--
-- กฎเหล็กสามข้อของไฟล์นี้
--
--   1. **ตัดเงินก่อน แล้วค่อยปิดบิล  ถ้าปิดบิลไม่สำเร็จต้องคืนเงินทันที**
--      ลำดับกลับกันคือบิลถูกปิดฟรี  ลำดับนี้แย่ที่สุดคือเงินกลับเข้ากระเป๋าเขาไป
--      ระหว่างสองความผิดพลาด อันที่ผู้เล่นไม่เสียเงินคืออันที่ยอมรับได้
--
--   2. **ล้มไปทางไม่หัก**  อะไรที่ไม่แน่ใจ ไม่รู้จัก อ่านไม่ได้ = ข้ามไป
--      ระบบที่หักเงินผิดหนึ่งครั้งทำลายความเชื่อใจมากกว่าที่ระบบที่ไม่หักเลยจะทำได้
--
--   3. **ห้ามพึ่งว่าผู้เล่นออนไลน์**  เจ้าของเซิร์ฟเลือกไว้ว่า "หักเลยทันทีแม้ออฟไลน์"
--      ป้ายที่ต้องบอกเขาจึงต้องถูก **เก็บไว้** ไม่ใช่ยิงทิ้ง แล้วเด้งตอนเขาล็อกอินเข้ามา
--
-- เรื่องเวลา: ใช้ "epoch" ของ HF_Tax เอง (HFTax.Utils.getRealDaysEpoch)
-- ไม่ได้คิดนาฬิกาเอง  เพราะกำหนดค่าปรับกับรอบบิลเป็นของเขา ถ้าเราคิดเองด้วยอีกชุด
-- วันหนึ่งสองชุดจะไม่ตรงกัน แล้วเราจะหักเงินในวันที่เขายังไม่ถือว่าเลยกำหนด
-- ==============================================================================
require("Kuraya/KR_Const")
require("Kuraya/KR_Server")

print("[Kuraya] KR_Bills  v" .. KR.VERSION)

local S = KR.server
if not S then
    print("[Kuraya] !! KR_Bills: KR_Server failed to load - auto pay disabled")
    return
end

local db, key, bank, alert, P = S.db, S.key, S.bank, S.alert, S.P

-- ------------------------------------------------------------------------------
-- ม็อดภาษีอยู่ไหม  และอยู่ในสภาพที่คุยด้วยได้ไหม
--
-- เช็กทีละชิ้นที่เราจะเรียกจริง ไม่ใช่เช็กแค่ว่า HFTax มีอยู่
-- ม็อดที่โหลดครึ่งเดียวคือม็อดที่ตัวแปรมีแต่ฟังก์ชันหาย ซึ่งอันตรายกว่าไม่มีเลย
-- ------------------------------------------------------------------------------
--
-- 0.6.11 — **ด่านที่ปฏิเสธเงียบ คือด่านที่ไม่มีใครแก้ได้**
--
-- ของเดิม return nil อยู่หกทาง แล้วหน้าจอพูดประโยคเดียวกันหมดว่า
-- "ยังไม่ได้ลงม็อดบิลบนเซิร์ฟนี้" ซึ่ง **ผิดในห้าจากหกกรณี** เพราะเจ้าของเซิร์ฟลงไว้แล้ว
-- พอปุ่ม "ดูบิลของฉัน" หายไป เราจึงไม่มีทางรู้เลยว่าหายเพราะข้อไหน
-- ต้องไปนั่งเดาทีละข้อ ทั้งที่เครื่องรู้คำตอบอยู่แล้วตั้งแต่วินาทีที่มันปฏิเสธ
--
-- กฎที่ได้มาจากเรื่อง access level เมื่อ 0.6.6 (พิมพ์ค่าที่อ่านได้จริงออกมาบรรทัดเดียว
-- แล้วปัญหาจบในรอบเดียว) ใช้ที่นี่ได้ตรง ๆ:
--   **ให้ด่านบอกชื่อสิ่งที่มันหาไม่เจอ และบอกว่าที่เจอแทนคืออะไร**
--
-- พิมพ์ครั้งเดียวต่อหนึ่งเหตุผล ไม่ใช่ทุกเฟรม  แต่ถ้ากลับมาใช้ได้แล้วพังใหม่ ให้พิมพ์ใหม่
-- ------------------------------------------------------------------------------
local WHY_SEEN = {}
local taxWhy   = nil       -- โค้ดเหตุผลล่าสุด  nil = คุยกันได้อยู่

-- ชื่อฟิลด์ที่มีอยู่จริง  ใช้ตอบคำถาม "แล้วเขาย้ายไปชื่อไหน"
-- เคสที่เจอคือม็อดภาษีอัปเดตแล้วเปลี่ยนชื่อของที่เราเรียก  รายชื่อนี้ตอบได้ทันที
local function keysOf(t, want)
    local ok, list = pcall(function()
        local acc, n = {}, 0
        for k, v in pairs(t) do
            if n >= 40 then break end
            if want == nil or type(v) == want then
                n = n + 1
                acc[n] = tostring(k)
            end
        end
        table.sort(acc)
        return table.concat(acc, ", ")
    end)
    if not ok or list == nil or list == "" then return "(none)" end
    return list
end

local function taxFail(code, msg)
    taxWhy = code
    if not WHY_SEEN[code] then
        WHY_SEEN[code] = true
        print("[Kuraya] bills OFF (" .. code .. ") - " .. msg)
    end
    return nil
end

local function taxOK(T)
    if taxWhy ~= nil then
        print("[Kuraya] bills ON - HFTax answers again after '" .. tostring(taxWhy) .. "'")
        taxWhy   = nil
        WHY_SEEN = {}
    end
    return T
end

local function tax()
    if type(HFTax) ~= "table" then
        return taxFail("nomod",
            "global HFTax is " .. type(HFTax) ..
            " - the tax mod is not on this server, or it loads after Kuraya")
    end

    local C  = HFTax.Config
    local U2 = HFTax.Utils
    local SC = HFTax.ServerCore

    if type(C) ~= "table" then
        return taxFail("nocfg", "HFTax.Config is " .. type(C) ..
            " - HFTax has: " .. keysOf(HFTax))
    end
    if type(U2) ~= "table" then
        return taxFail("noutil", "HFTax.Utils is " .. type(U2) ..
            " - HFTax has: " .. keysOf(HFTax))
    end
    if type(SC) ~= "table" then
        return taxFail("nocore", "HFTax.ServerCore is " .. type(SC) ..
            " - HFTax has: " .. keysOf(HFTax))
    end

    if type(SC.getGlobalData) ~= "function" then
        return taxFail("noglobal", "HFTax.ServerCore.getGlobalData is " ..
            type(SC.getGlobalData) ..
            " - ServerCore functions: " .. keysOf(SC, "function"))
    end
    if type(U2.getRealDaysEpoch) ~= "function" then
        return taxFail("noepoch", "HFTax.Utils.getRealDaysEpoch is " ..
            type(U2.getRealDaysEpoch) ..
            " - Utils functions: " .. keysOf(U2, "function"))
    end
    if type(C.BILL_STATUS) ~= "table" or type(C.BILL_TYPE) ~= "table" then
        return taxFail("nostatus", "HFTax.Config.BILL_STATUS is " ..
            type(C.BILL_STATUS) .. " and BILL_TYPE is " .. type(C.BILL_TYPE) ..
            " - Config has: " .. keysOf(C))
    end

    return taxOK({ C = C, U = U2, SC = SC })
end

S.billsAvailable = function() return tax() ~= nil end

-- เหตุผลล่าสุดที่ด่านปฏิเสธ  ส่งเป็น "โค้ด" ไม่ใช่ประโยค
-- คำแปลอยู่ฝั่งไคลเอนต์ เพราะภาษาเป็นเรื่องของคนที่มองจอ ไม่ใช่ของเซิร์ฟเวอร์
S.billsWhy = function()
    tax()
    return taxWhy
end

-- ------------------------------------------------------------------------------
-- ค่าตั้งของผู้เล่นหนึ่งคน
-- ------------------------------------------------------------------------------
local function pref(k)
    local row = P(k)
    row.bill = row.bill or {}
    row.bill.notes = row.bill.notes or {}
    return row.bill
end

-- ------------------------------------------------------------------------------
-- ป้ายที่ต้องบอกผู้เล่น  เก็บไว้ก่อน ส่งตอนเขาอยู่
--
-- นี่คือข้อ 3 ของกฎเหล็ก  การหักเกิดขึ้นได้ตอนเขาไม่อยู่ ป้ายที่ยิงทิ้งตอนนั้น
-- แปลว่าเขาจะรู้ตัวอีกทีตอนเปิดกระเป๋าแล้วเงินหาย ซึ่งเป็นความรู้สึกที่แย่ที่สุด
-- ที่ระบบหักเงินอัตโนมัติจะให้ได้
-- ------------------------------------------------------------------------------
local NOTE_MAX = 8

local function note(k, row)
    local b = pref(k)
    b.notes[#b.notes + 1] = row
    while #b.notes > NOTE_MAX do table.remove(b.notes, 1) end
end

-- ดึงป้ายออกมาส่ง แล้วล้างทิ้ง  เรียกจาก S.sync
function S.billNotes(player)
    local k = key(player); if not k then return nil end
    local b = pref(k)
    if #b.notes == 0 then return nil end
    local out = b.notes
    P(k).bill.notes = {}
    return out
end

-- ==============================================================================
-- ใครเห็นบิลใบไหน  และใครต้องจ่ายบิลใบไหน
--
-- 0.6.7 — สองคำถามนี้ **ไม่ใช่คำถามเดียวกัน** และของเดิมตอบทั้งคู่ด้วยบรรทัดเดียว
--     b.owner == username
--
-- อาการที่เจ้าของเซิร์ฟรายงาน: "ตอนเปลี่ยนเจ้าของเซฟแล้วบิลไม่เจอทันที"
-- ตรงเป๊ะกับข้อจำกัดของบรรทัดนั้น: ในบิลเก็บชื่อเจ้าของ **ณ วันที่ออกบิล**
-- ย้ายสิทธิ์เจ้าของบ้านเมื่อไหร่ ใบที่ค้างอยู่ยังชี้ไปที่คนเก่าตลอดไป
-- เจ้าของใหม่จึงไม่เห็นอะไรเลย ทั้งที่หน้าต่างของม็อดภาษีเองแสดงให้เขาเห็นอยู่
-- ------------------------------------------------------------------------------

-- ---- เห็นไหม  ใช้กติกาของ HF_Tax เอง ไม่ใช่กติกาที่เราคิดขึ้นใหม่ --------------
--
-- ลอกมาจาก HFTax.ServerCore.broadcastPlayerBills ตรง ๆ (และมันซ้ำอยู่สี่ที่ในม็อดเขา
-- ทั้ง ServerCommands กับ InvoiceManagerUI ก็ใช้เงื่อนไขเดียวกัน)
--     visibilityPUUIDs[myPUUID]  or  owner == username  or  ownerPUUID == myPUUID
--
-- ทำไมต้องลอกแทนที่จะคิดเอง: ลิสต์ของเรากับหน้าต่างของเขาต้องโชว์ชุดเดียวกัน
-- ถ้าคนละชุด ผู้เล่นจะเจอสองหน้าจอที่บอกไม่ตรงกันเรื่องเงินของตัวเอง
-- ซึ่งแย่กว่ามีหน้าจอเดียว  เขาเป็นเจ้าของข้อมูล กติกาการมองเห็นจึงเป็นของเขา
--
-- getPlayerPUUID เป็นแฮชของชื่อล้วน ๆ ไม่มี state จึงเรียกได้ทุกเมื่อ
-- แต่ยังเช็กก่อนเรียกตามกฎ  วันที่เขาถอดฟังก์ชันนี้ออก เราต้องตกไปใช้ชื่อ ไม่ใช่พัง
local function canSee(T, b, username, houseKey)
    if b.owner == username then return true end

    -- บ้านที่ตอนนี้เราเป็นเจ้าของ  ข้อนี้ไม่ได้อยู่ในกติกาของ HF_Tax แต่ต้องมี
    --
    -- **กติกาที่ห้ามพังเด็ดขาด: อะไรที่เราอาจหักเงินเขาได้ เขาต้องเห็นมันได้**
    -- ข้างล่างนี้ (myHouseKey) เปิดให้หักบิลของบ้านที่ย้ายสิทธิ์มาแล้ว
    -- ถ้าตรงนี้ไม่เปิดให้เห็นด้วย จะมีบิลที่ถูกหักเงินโดยที่เจ้าตัวไม่เคยเห็นมันเลย
    -- ซึ่งแย่กว่าไม่หักเลยมาก  ชุด "เห็น" ต้องครอบชุด "จ่าย" เสมอ
    if houseKey ~= nil and b.billType == T.C.BILL_TYPE.LAND
       and b.safehouseKey ~= nil and b.safehouseKey == houseKey then
        return true
    end

    local f = T.U.getPlayerPUUID
    if type(f) ~= "function" then return false end
    local okId, myId = pcall(f, username)
    if not okId or myId == nil then return false end
    if b.ownerPUUID == myId then return true end
    return (type(b.visibilityPUUIDs) == "table") and (b.visibilityPUUIDs[myId] == true)
end

-- ---- ต้องจ่ายไหม  แคบกว่า "เห็น" มาก และตั้งใจให้แคบ -------------------------
--
-- **เห็น ≠ ต้องจ่าย**  สมาชิกในบ้านทุกคนเห็นบิลค่าบ้าน แต่ถ้าเราหักเงินทุกคนที่เห็น
-- แปลว่าคนที่แค่ไปอาศัยอยู่ด้วยจะโดนดูดเงินไปจ่ายบ้านที่ไม่ใช่ของเขา
-- นั่นคือกฎเหล็กข้อ 2 พังทันที ("ระบบที่หักเงินผิดหนึ่งครั้งทำลายความเชื่อใจ
-- มากกว่าที่ระบบที่ไม่หักเลยจะทำได้")
--
-- กติกาจึงมีสองทางเท่านั้น
--   1. ชื่อในบิลคือเรา                       -> จ่าย  (เคสปกติ ไม่เปลี่ยนจากเดิม)
--   2. บิลนี้เป็นของบ้านที่ **ตอนนี้เราเป็นเจ้าของ** -> จ่าย  (เคสย้ายสิทธิ์)
-- อ่านเซฟเฮาส์ไม่ได้ = เหลือแค่ข้อ 1  ล้มไปทางไม่หัก
--
-- ภาษีส่วนตัวไม่มีข้อ 2  มันไม่เคยย้ายไปไหน
local function myHouseKey(T, player)
    if type(T.U.getSafehouseKey) ~= "function" then return nil end
    if type(S.safehouseOf) ~= "function" then return nil end
    local sh = S.safehouseOf(player)
    if not sh then return nil end

    -- ต้องเป็น "เจ้าของ" ไม่ใช่แค่ "สมาชิก"
    local okOwn, owner = pcall(function() return sh:getOwner() end)
    if not okOwn or owner == nil then return nil end
    local me = (player.getUsername and player:getUsername()) or nil
    if me == nil or tostring(owner) ~= tostring(me) then return nil end

    local okKey, k2 = pcall(T.U.getSafehouseKey, sh)
    if not okKey or k2 == nil then return nil end
    return k2
end

-- ------------------------------------------------------------------------------
-- บิลของคนนี้ที่ยังไม่จ่าย  เรียงเก่าก่อน
--
-- ต้องเรียงเก่าก่อนเพราะ HF_Tax บังคับ "จ่ายใบเก่าสุดก่อน" อยู่แล้ว
-- ถ้าเราจ่ายข้ามใบ ใบที่เราจ่ายจะโดนตีกลับตอนผู้เล่นไปกดจ่ายเองในหน้าของเขา
-- ------------------------------------------------------------------------------
local function unpaidOf(T, gd, username, kind, houseKey)
    local out = {}
    for id, b in pairs(gd.Bills or {}) do
        if type(b) == "table"
           and b.status == T.C.BILL_STATUS.UNPAID
           and b.billType == kind then
            local mine = (b.owner == username)
            if not mine and houseKey ~= nil and kind == T.C.BILL_TYPE.LAND then
                mine = (b.safehouseKey ~= nil and b.safehouseKey == houseKey)
            end
            if mine then
                b.billId = b.billId or id
                out[#out + 1] = b
            end
        end
    end
    table.sort(out, function(p, q)
        return (tonumber(p.createdEpoch) or 0) < (tonumber(q.createdEpoch) or 0)
    end)
    return out
end

-- ------------------------------------------------------------------------------
-- จ่ายบิลหนึ่งใบ  คืน ok, เหตุผลถ้าไม่สำเร็จ, ยอดที่จ่าย
--
-- ทำตามลำดับเดียวกับ HFTax.ServerCommands.PayBill ทุกขั้น แล้วเรียกฟังก์ชัน
-- ของเขาปิดท้าย  ที่ทำเองไม่ได้คือขั้นแรกเท่านั้น: PayBill ต้องการ "ตัวผู้เล่น"
-- ซึ่งคนออฟไลน์ไม่มี  และเจ้าของเซิร์ฟสั่งให้หักแม้เขาไม่อยู่
-- ------------------------------------------------------------------------------
local function payOne(T, gd, k, username, bill)
    local amount = math.max(0, math.floor(tonumber(bill.totalAmount) or 0))
    if amount <= 0 then return false, "zero" end

    local B = bank()
    if not (B and B.available and B.charge) then return false, "nobank" end

    -- ยอดของ HF_Tax เป็น "บาท"  ledger เดินเป็นสตางค์  แปลงจุดเดียวตรงนี้
    -- (ม็อดเขาก็คูณ 100 ที่จุดเดียวกันนี้  ถ้าเราคูณคนละที่ วันหนึ่งจะไม่ตรงกัน)
    local satang = amount * KR.SUBUNIT

    local okAvail, have = pcall(B.available, k)
    if not okAvail or type(have) ~= "number" then return false, "nobank" end
    if have < satang then return false, "short", amount end

    local okCh = pcall(B.charge, k, satang, "TAX", tostring(bill.billId), "kuraya:auto")
    if not okCh then return false, "refused", amount end

    -- ---- ตัดเงินไปแล้ว  ตั้งแต่บรรทัดนี้ห้ามออกโดยไม่คืนเงิน -------------------
    local okMark = pcall(function()
        local nowE = T.U.getRealDaysEpoch()
        bill.status  = T.C.BILL_STATUS.PAID
        bill.paidEpoch = nowE
        if type(T.U.getCurrentDateTimeString) == "function" then
            bill.paidDateStr = T.U.getCurrentDateTimeString()
        end
        bill.paidBy = username .. " [Kuraya auto]"
        bill.isOverdue = false
        bill.isCutoffStage = false

        gd.Treasury = gd.Treasury or { vaultBalance = 0, totalPlayerCollected = 0,
                                       totalAdminSubsidized = 0, totalWithdrawn = 0 }
        gd.Treasury.vaultBalance = (gd.Treasury.vaultBalance or 0) + amount
        gd.Treasury.totalPlayerCollected = (gd.Treasury.totalPlayerCollected or 0) + amount

        if type(T.SC.processUtilityCutoffs) == "function" then
            T.SC.processUtilityCutoffs(gd, nowE)
        end
        if type(T.SC.syncModData) == "function" then T.SC.syncModData() end
        if type(T.SC.broadcastSafehouseStatus) == "function" then T.SC.broadcastSafehouseStatus() end
        if type(T.SC.broadcastAdminData) == "function" then T.SC.broadcastAdminData() end
    end)

    if not okMark then
        -- กฎเหล็กข้อ 1  ปิดบิลไม่สำเร็จ = คืนเงินทันที
        -- ถ้าคืนไม่ได้อีก ต้องดังให้สุดใน console  เงินหายเงียบ ๆ คือสิ่งที่ยอมไม่ได้
        local okBack = B.payTo and pcall(B.payTo, "SYS:TAX", k, satang, "TAX",
                                         "refund " .. tostring(bill.billId), "system")
        if not okBack then
            print("[Kuraya] !!!! BILL AUTO PAY: charged " .. tostring(satang) ..
                  " from " .. tostring(k) .. " but could NOT close bill " ..
                  tostring(bill.billId) .. " and could NOT refund. FIX BY HAND.")
        else
            print("[Kuraya] bill auto pay: could not close " .. tostring(bill.billId) ..
                  " for " .. tostring(k) .. " - refunded")
        end
        return false, "failed", amount
    end

    return true, nil, amount
end

-- ==============================================================================
-- รอบตรวจ  เรียกจาก S.sync เหมือน rotateDaily และ auctionTick
--
-- ทำไมเกาะกับ sync แทนที่จะใช้ตัวจับเวลาของตัวเอง
--   เซิร์ฟที่ปิดข้ามวันจะพลาด event รายวันทั้งหมด  แต่ sync วิ่งแน่นอนเมื่อมีคนเล่น
--   และเรานับ "วัน" จาก epoch ของ HF_Tax ไม่ใช่จากจำนวนครั้งที่ฟังก์ชันนี้ถูกเรียก
--   คนที่ล็อกอินบ่อยจึงไม่ได้โดนหักถี่กว่าคนที่ไม่ล็อกอิน
--
-- **หักให้ทุกคน ไม่ใช่แค่คนที่กำลัง sync อยู่** เพราะต้องหักคนออฟไลน์ด้วย
-- แต่จำกัดรอบละครั้งด้วย d.bills.lastRun กัน sync ทุกสองวินาทีลากงานนี้ไปด้วย
-- ==============================================================================
local RUN_EVERY = 60          -- วินาทีจริง  ถี่กว่านี้ไม่ได้อะไรเพิ่ม

function S.billTick(force)
    local T = tax()
    if not T then return false end

    local d = db()
    d.bills = d.bills or { lastRun = 0 }
    local now = getTimestamp and getTimestamp() or os.time()
    if not force and (now - (tonumber(d.bills.lastRun) or 0)) < RUN_EVERY then return false end
    d.bills.lastRun = now

    local okGd, gd = pcall(T.SC.getGlobalData)
    if not okGd or type(gd) ~= "table" or type(gd.Bills) ~= "table" then return false end

    local okE, epoch = pcall(T.U.getRealDaysEpoch)
    if not okE or type(epoch) ~= "number" then return false end

    -- กี่วันหลังบิลออกถึงจะหัก
    --
    -- เจ้าของเซิร์ฟสั่งว่า "หักในวันที่ 2 หรือวันถัดไปที่บิลมา"
    -- และ "ถ้าผู้เล่นจ่ายตั้งแต่วันแรก ก็ไม่ต้องหักต่อ" ซึ่งเกิดขึ้นเองอยู่แล้ว
    -- เพราะใบที่จ่ายแล้วไม่อยู่ในลิสต์ UNPAID อีกต่อไป
    --
    -- วันแรกจึงเป็นวันของผู้เล่น  เขามีเวลาหนึ่งวันเต็มที่จะจัดการเอง
    -- ระบบเข้ามาทำงานวันถัดไปเท่านั้น  ไม่ใช่ตัดทันทีที่บิลออก
    local WAIT = 1.0

    local kinds = {
        { flag = "land", type = T.C.BILL_TYPE.LAND,
          th = "บิลเซฟเฮาส์", en = "safehouse bill" },
        { flag = "tax",  type = T.C.BILL_TYPE.PERSONAL,
          th = "ภาษีส่วนตัว", en = "personal tax" },
    }

    local worked = false
    for k, row in pairs(d.players or {}) do
        local b = row.bill
        if type(b) == "table" and (b.land or b.tax) then
            local username = row.disp or k

            -- key ของบ้านที่ "ตอนนี้" คนนี้เป็นเจ้าของ  nil ได้หลายเหตุผลและทุกเหตุผลปลอดภัย
            -- ออฟไลน์อยู่ / ไม่ได้อยู่ในบ้าน / เป็นแค่สมาชิกไม่ใช่เจ้าของ / อ่าน API ไม่ได้
            -- nil = เหลือแค่กติกา "ชื่อในบิลคือเรา" ซึ่งคือพฤติกรรมเดิมทุกประการ
            local online = S.onlineByKey and S.onlineByKey(k) or nil
            local hKey   = online and myHouseKey(T, online) or nil

            for _, kind in ipairs(kinds) do
                if b[kind.flag] then
                    local list = unpaidOf(T, gd, username, kind.type, hKey)
                    for _, bill in ipairs(list) do
                        local age = epoch - (tonumber(bill.createdEpoch) or epoch)
                        if age >= WAIT then
                            local ok, why, amt = payOne(T, gd, k, username, bill)
                            worked = true
                            if ok then
                                local left = 0
                                local B = bank()
                                if B and B.available then
                                    local okA, v = pcall(B.available, k)
                                    if okA and type(v) == "number" then left = v end
                                end

                                -- ---- ลงประวัติการใช้จ่ายของร้าน ------------------
                                --
                                -- 0.6.9 — ก่อนหน้านี้ **ไม่มีบรรทัดนี้เลย**
                                -- บิลหักเงินจริงทุกวันแต่ไม่เคยฝากรอยไว้ในตารางประวัติ
                                -- ชิป "Bill" บนหัวตารางจึงว่างเปล่าตลอดกาล
                                -- เจ้าของเซิร์ฟรายงานสั้น ๆ ว่า "ประวัติบิลไม่ขึ้น" ซึ่งถูกทุกคำ
                                --
                                -- น่าเจ็บใจตรงที่คอมเมนต์เหนือ KR.LOG_FILTERS ใน KR_Const
                                -- เตือนเรื่องนี้ไว้แล้วตั้งแต่ 0.4.2:
                                --   "ชิปที่กดแล้วว่างเสมอแย่กว่าไม่มีชิปนั้นเลย
                                --    เพราะมันสัญญาว่ามีข้อมูลอยู่"
                                -- แล้วเราก็เพิ่มชิป bill เข้าไปโดยไม่ได้เขียนฝั่งที่ผลิตข้อมูล
                                --
                                -- ยอดของม็อดภาษีเป็นบาท  ประวัติเดินเป็นสตางค์เหมือนทุกแถว
                                if S.logEvent then
                                    S.logEvent(k, KR.LOG.BILL,
                                               KR.L(kind.th, kind.en) .. "  " .. tostring(bill.billId),
                                               amt * KR.SUBUNIT, KR.CUR.CASH, false,
                                               KR.L("หักอัตโนมัติ", "auto paid"))
                                end

                                note(k, { ok = true, kind = kind.flag,
                                          what = bill.billId, n = amt, left = left,
                                          at = now })
                                print("[Kuraya] bill auto pay  " .. tostring(k) .. "  " ..
                                      tostring(bill.billId) .. "  " .. tostring(amt))
                            else
                                -- ---- เงินไม่พอ = ปิดการหักอัตโนมัติให้เอง -------
                                --
                                -- เจ้าของเซิร์ฟสั่งไว้ตรง ๆ  และมันถูก:
                                -- ระบบที่พยายามหักซ้ำทุกวันโดยที่รู้อยู่แล้วว่าไม่พอ
                                -- คือระบบที่ส่งป้ายเตือนวันละใบจนคนเลิกอ่านป้าย
                                -- ปิดแล้วบอกครั้งเดียว แล้วให้เขากลับมาเปิดเองเมื่อพร้อม
                                b[kind.flag] = false
                                note(k, { ok = false, kind = kind.flag,
                                          what = bill.billId, n = amt or 0,
                                          why = why, at = now })
                                print("[Kuraya] bill auto pay OFF  " .. tostring(k) ..
                                      "  " .. tostring(kind.flag) .. "  (" .. tostring(why) .. ")")
                                break        -- ใบถัดไปก็ไม่พออยู่ดี
                            end
                        end
                    end
                end
            end
        end
    end
    return worked
end

-- ==============================================================================
-- สิ่งที่ส่งให้ไคลเอนต์ทุก sync
-- ==============================================================================
function S.billRow(player)
    local T = tax()
    local k = key(player); if not k then return nil end
    local b = pref(k)

    local row = { on = (T ~= nil), land = b.land or false, tax = b.tax or false }
    if not T then
        -- โค้ดเหตุผล ไม่ใช่ประโยค  ฝั่งจอเป็นคนแปล
        -- แผงที่บอกว่า "ไม่ได้ลงม็อด" ทั้งที่ลงแล้ว คือแผงที่ส่งคนไปแก้ผิดที่
        row.why = taxWhy
        return row
    end

    local okGd, gd = pcall(T.SC.getGlobalData)
    if not okGd or type(gd) ~= "table" then return row end

    local username = P(k).disp or k
    local hKey = myHouseKey(T, player)
    local nLand, nTax, due = 0, 0, 0
    for _, bill in pairs(gd.Bills or {}) do
        if type(bill) == "table" and bill.status == T.C.BILL_STATUS.UNPAID
           and canSee(T, bill, username, hKey) then
            local amt = math.max(0, math.floor(tonumber(bill.totalAmount) or 0))
            due = due + amt
            if bill.billType == T.C.BILL_TYPE.LAND then nLand = nLand + 1
            elseif bill.billType == T.C.BILL_TYPE.PERSONAL then nTax = nTax + 1 end
        end
    end
    row.land_n = nLand
    row.tax_n  = nTax
    row.due    = due                       -- บาท  ไม่ใช่สตางค์  ตามหน่วยของม็อดภาษี
    return row
end

-- 0.6.10 — S.billList() กับ S.billOpen() ถูกถอดออก
--
-- ทำขึ้นตอน 0.6.6 เพราะหน้าต่างของม็อดภาษีวาดไม่ออก ซึ่งกลายเป็นว่าเป็นบั๊กของเราเอง
-- (tex.h บน Texture object — PZ-B42-texture-getWidth-RULE) พอบั๊กนั้นถูกแก้
-- ลิสต์นี้ก็เหลือสถานะเป็น "ทางที่สองที่ทำได้น้อยกว่าทางแรก": ดูได้อย่างเดียว จ่ายไม่ได้
--
-- เจ้าของเซิร์ฟสั่งให้ปุ่มไปเปิดม็อดภาษีตรง ๆ  เรื่องบิลจึงมีหน้าจอเดียว
-- ไฟล์นี้เหลือหน้าที่ที่เป็นของร้านจริง ๆ: หักอัตโนมัติ กับ ยอดสรุปบนแผง Account
--
-- canSee() / myHouseKey() ยังอยู่ เพราะ S.billRow ใช้นับยอดค้าง และ billTick ใช้ตัดสินว่าใครจ่าย

-- ==============================================================================
-- ผู้เล่นเปิด / ปิด การหักอัตโนมัติ
-- ==============================================================================
function S.billSet(player, args)
    local k = key(player); if not k then return end
    local b = pref(k)

    local which = tostring((args and args.which) or "")
    if which ~= "land" and which ~= "tax" then return end

    if not tax() then
        return alert(player, "The bill add-on cannot be reached (" ..
                     tostring(taxWhy) .. "). See the server console.", "bad")
    end

    b[which] = (args and args.on) and true or false

    local what = (which == "land") and KR.L("บิลเซฟเฮาส์", "safehouse bills")
                                    or KR.L("ภาษีส่วนตัว", "personal tax")
    alert(player, b[which] and ("Auto pay is ON for " .. what ..
                                ". It runs the day after a bill arrives.")
                            or ("Auto pay is OFF for " .. what .. "."),
          b[which] and "good" or "warn")
    S.sync(player)
end

print("[Kuraya] KR_Bills ready")
return true
