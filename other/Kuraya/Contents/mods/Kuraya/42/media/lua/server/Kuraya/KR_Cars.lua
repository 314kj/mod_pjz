-- ==============================================================================
-- Kuraya — server/Kuraya/KR_Cars.lua
-- ขายรถ  ร้านจ่ายเป็น "ใบรถ" แล้วผู้เล่นแกะเอง
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- ทำไมต้องเป็นใบ ไม่ใช่รถโผล่มาเลยตอนกดซื้อ
--
--   ร้านอยู่ในอาคาร  รถเกิดในอาคารไม่ได้ (หรือเกิดได้แต่ติดกำแพงจนขยับไม่ออก)
--   ถ้าจ่ายเป็นรถทันที ร้านต้องเดาว่าลานจอดอยู่ตรงไหน ซึ่งเดาไม่ได้จริง
--   ใบรถย้ายการตัดสินใจนั้นไปให้คนที่รู้ดีที่สุดว่าจะจอดตรงไหน คือคนซื้อ
--
--   ผลพลอยได้ที่สำคัญกว่า: ใบเป็นไอเทมปกติ  ส่งต่อ ขายต่อ เก็บไว้ก่อนได้
--   รถที่โผล่ทันทีเป็นของที่ "ต้องใช้เดี๋ยวนี้" ใบรถเป็นของที่ "มีค่าเก็บไว้ได้"
--   อย่างหลังทำให้มันเป็นสินค้าในเศรษฐกิจเซิร์ฟจริง ๆ ไม่ใช่แค่ปุ่มเสกของ
--
-- กฎเหล็กสามข้อของไฟล์นี้
--
--   1. **เอาใบออกก่อน แล้วค่อยเสกรถ  เสกไม่สำเร็จต้องคืนใบทันที**
--      ลำดับกลับกันคือมีทั้งรถและใบอยู่พร้อมกันหนึ่งเฟรม = แกะซ้ำได้สองคัน
--      กฎเดียวกับ KR_Bills ข้อ 1 เป๊ะ ๆ  แค่สลับ "เงิน" เป็น "ใบ"
--
--   2. **ห้ามเชื่อว่า pcall ผ่าน = รถเกิดแล้ว**
--      ต้องได้ตัวรถกลับมาถือไว้จริง ๆ ไม่งั้นถือว่าไม่เกิด
--      (บทเรียนเดียวกับตอนเปิดหน้าต่างของม็อดภาษี — pcall ผ่านแต่จอพังเฟรมถัดไป)
--
--   3. **รุ่นรถอ่านจากเกมจริงตอนรัน  ห้ามฝังรายชื่อไว้ในโค้ด**
--      เซิร์ฟนี้ลงม็อดรถของ KI5 ไว้  รายชื่อที่พิมพ์เองจะขาดของพวกนั้นเสมอ
--      และจะผิดอีกครั้งทุกครั้งที่เขาอัปเดต
-- ==============================================================================
require("Kuraya/KR_Const")
require("Kuraya/KR_Server")

print("[Kuraya] KR_Cars  v" .. KR.VERSION)

local S = KR.server
if not S then
    print("[Kuraya] !! KR_Cars: KR_Server failed to load - vehicles disabled")
    return
end

local key, alert = S.key, S.alert

-- ------------------------------------------------------------------------------
-- ตัวช่วยอ่านของฝั่ง Java
-- ------------------------------------------------------------------------------

-- ลิสต์ของ Java เดินด้วย size()/get(i) ฐานศูนย์  ตาราง Lua เดินด้วย ipairs
-- ม็อดอื่นอาจคืนมาแบบไหนก็ได้  ตัวเรียกไม่ควรต้องรู้
local function listOf(v)
    if v == nil then return nil end

    if U_hasMethod(v, "size") and U_hasMethod(v, "get") then
        local okN, n = pcall(function() return v:size() end)
        if not okN or type(n) ~= "number" then return nil end
        local out = {}
        for i = 0, n - 1 do
            local okE, e = pcall(function() return v:get(i) end)
            if okE and e ~= nil then out[#out + 1] = e end
        end
        return out
    end

    if type(v) == "table" then
        local out = {}
        for _, e in ipairs(v) do out[#out + 1] = e end
        if #out > 0 then return out end
    end

    return nil
end

-- ข้อความ error ของ Java ยาวเกินกว่าจะเอาไปแปะหน้าผู้เล่น  (0.6.17)
--
-- ฝั่งสัตว์เจอของจริงมาแล้ว: บรรทัด exception พาดขวางเต็มจอจนอ่านไม่ออกสักคำ
-- รถเดินโค้ดเส้นเดียวกันเป๊ะ มันแค่ยังไม่เคยล้มด้วย exception ที่ยาวขนาดนั้น
-- **ตัวเต็มไปอยู่ใน console ฝั่งเซิร์ฟ บนจอเหลือเท่าที่อ่านจบในหนึ่งบรรทัด**
local function brief(e)
    local t = tostring(e or "")
    t = t:gsub("^.-%.lua:%d+:%s*", "")
    local head = t:match("^([^\n]*)") or t
    head = head:gsub("%s+", " ")
    if #head > 110 then head = head:sub(1, 107) .. "..." end
    return head
end

-- ชื่อเต็มคือชื่อที่เอาไปเสกได้  ชื่อสั้นเสกไม่ได้ในบางบิลด์
local function idOf(sc)
    if type(sc) == "string" then return sc end
    for _, m in ipairs({ "getFullName", "getName" }) do
        if U_hasMethod(sc, m) then
            local ok, v = pcall(function() return sc[m](sc) end)
            if ok and type(v) == "string" and v ~= "" then return v end
        end
    end
    return nil
end

-- ชื่อที่คนอ่านรู้เรื่อง  เกมแปลไว้ให้แล้วถ้ามันรู้จักรุ่นนั้น
-- ไม่รู้จักก็ใช้ชื่อสคริปต์ ซึ่งยังดีกว่าเว้นว่าง
local function labelOf(id)
    local short = tostring(id):match("([^%.]+)$") or tostring(id)
    if type(getText) == "function" then
        local tkey = "IGUI_VehicleName" .. short
        local ok, s = pcall(getText, tkey)
        if ok and type(s) == "string" and s ~= "" and s ~= tkey then return s end
    end
    return short
end

-- ------------------------------------------------------------------------------
-- แคตตาล็อกรุ่นรถ  อ่านจากเกมจริง
--
-- **ชื่อเมธอดที่ใช้อ่านคือสิ่งที่เราไม่รู้แน่** ต่างบิลด์อาจไม่เหมือนกัน
-- แทนที่จะเดาอันเดียวแล้วภาวนา ให้ลองทีละอันแล้ว **บอกว่าอันไหนตอบ**
-- อันไหนก็ตอบไม่ได้ = รายการว่าง แอดมินยังพิมพ์ไอดีเองได้ ฟีเจอร์ไม่ตาย
--
-- นี่คือรูปแบบเดียวกับที่ใช้แก้เรื่องบิลเมื่อ 0.6.11: ให้ระบบบอกว่ามันเห็นอะไร
-- ------------------------------------------------------------------------------
local PROBES = { "getAllVehicleScripts", "getVehicleScripts", "getAllVehicles" }

local CATALOG, BY_ID, HOW = nil, nil, nil

local function build(force)
    if CATALOG and not force then return CATALOG end

    CATALOG, BY_ID, HOW = {}, {}, nil

    local sm = (type(getScriptManager) == "function") and getScriptManager() or nil
    if sm == nil then
        print("[Kuraya] cars: no script manager on this build" ..
              " - the model list is empty, admins must type ids by hand")
        return CATALOG
    end

    for _, m in ipairs(PROBES) do
        if U_hasMethod(sm, m) then
            local okV, v = pcall(function() return sm[m](sm) end)
            local arr = okV and listOf(v) or nil
            if arr and #arr > 0 then
                local rows, seen = {}, {}
                for _, sc in ipairs(arr) do
                    local id = idOf(sc)
                    if id and not seen[id] then
                        seen[id] = true
                        rows[#rows + 1] = { id = id, label = labelOf(id) }
                    end
                end
                if #rows > 0 then
                    -- ตัวเทียบต้องตัดสินให้ขาดเสมอ  คืน false ทั้งสองทางตอนเท่ากัน
                    -- แล้ว table.sort จะพังแบบสุ่ม (กฎเดียวกับ KR.sortList)
                    table.sort(rows, function(a, b)
                        local x, y = a.label:lower(), b.label:lower()
                        if x ~= y then return x < y end
                        return a.id < b.id
                    end)
                    CATALOG, HOW = rows, m
                    for _, r in ipairs(rows) do BY_ID[r.id] = r end
                    break
                end
            end
        end
    end

    print("[Kuraya] cars: " .. #CATALOG .. " models read via " ..
          tostring(HOW or "nothing that answered"))
    return CATALOG
end

S.carsBuild = build

-- รุ่นนี้มีอยู่จริงไหม
--
-- แคตตาล็อกว่าง = เราอ่านรายชื่อไม่ได้ ไม่ได้แปลว่ารุ่นนั้นไม่มี
-- **ตอบว่า "ไม่มี" ตอนที่ความจริงคือ "ไม่รู้" คือการโกหก** และมันจะบล็อกทุกการซื้อ
-- บนบิลด์ที่เราอ่านรายชื่อไม่ออก ทั้งที่รถอาจใช้ได้ปกติ
function S.carKnown(id)
    if type(id) ~= "string" or id == "" then return false end
    build()
    if #CATALOG == 0 then return true end
    return BY_ID[id] ~= nil
end

function S.carLabel(id)
    build()
    local row = BY_ID[tostring(id or "")]
    return (row and row.label) or labelOf(id)
end

-- แอดมินขอรายชื่อไปใส่ในฟอร์ม
function S.carList(player, args)
    build(args and args.refresh and true or false)
    sendServerCommand(player, KR.MODULE, KR.CMD.CAR_LIST, {
        rows = CATALOG,
        how  = HOW,
    })
end

-- ==============================================================================
-- ใบรถ
-- ==============================================================================

-- ใบทุกใบเป็นไอเทมชนิดเดียวกัน  รุ่นรถอยู่ใน ModData ไม่ใช่ในชนิดไอเทม
--
-- ทางเลือกอีกทางคือทำไอเทมหนึ่งชนิดต่อรถหนึ่งรุ่น ซึ่งแปลว่าเซิร์ฟนี้ต้องมี
-- item script ~200 อัน และต้องเขียนเพิ่มทุกครั้งที่ลงม็อดรถใหม่ = พังโดยการออกแบบ
--
-- **ฝั่งเซิร์ฟเป็นเจ้าของความจริงเสมอ**  ตอนแกะ เซิร์ฟอ่าน ModData ของตัวเอง
-- ไม่ได้อ่านค่าที่ไคลเอนต์ส่งมาว่าใบนี้เป็นรถรุ่นไหน  ไคลเอนต์บอกได้แค่ "ใบไหน"
local function stamp(it, vehId, label)
    local okMd, md = pcall(function() return it:getModData() end)
    if not okMd or type(md) ~= "table" then return false end

    md.krVehicle = vehId
    md.krVehName = label

    -- ชื่อบนใบ  ผู้เล่นต้องอ่านออกจากกระเป๋าว่าใบนี้เป็นรถอะไร
    -- ใบที่ทุกใบชื่อเหมือนกันคือใบที่ต้องแกะเพื่อจะรู้ว่าแกะอะไรอยู่
    if U_hasMethod(it, "setName") then
        pcall(function() it:setName(KR.L("ใบรถ - ", "Vehicle slip - ") .. tostring(label)) end)
    end

    -- ModData ของไอเทมไม่ได้วิ่งข้ามสายเอง  ต้องสั่งส่ง
    for _, m in ipairs({ "transmitModData", "syncItemFields" }) do
        if U_hasMethod(it, m) then pcall(function() it[m](it) end) end
    end
    return true
end

-- คืนตัวไอเทมกลับมาด้วย เพราะคนเรียกต้องประทับรุ่นรถลงไป
-- S.giveItems เดิมคืนแค่จำนวน ซึ่งพอสำหรับของทั่วไปแต่ไม่พอสำหรับของที่มีข้อมูลติดตัว
local function makeSlip(player, vehId, label)
    local inv = player and player:getInventory()
    if not inv then return nil, "no inventory" end

    local okMake, it = pcall(instanceItem, KR.SLIP)
    if not okMake then
        return nil, "engine refused to build " .. KR.SLIP .. " (" .. tostring(it) .. ")"
    end
    if it == nil then
        return nil, KR.SLIP .. " could not be created - is the Kuraya item script installed?"
    end

    stamp(it, vehId, label)
    inv:AddItem(it)
    -- ประกาศก่อน แล้วค่อยซิงก์  เหตุผลเดียวกับ giveItems ใน KR_Server (0.6.13)
    -- ซิงก์ฟิลด์ของไอเทมที่ไคลเอนต์ยังไม่รู้จัก = NPE ที่ฝั่งเขา
    if type(sendAddItemToContainer) == "function" then
        pcall(sendAddItemToContainer, inv, it)
    end
    if U_hasMethod(it, "syncItemFields") then pcall(function() it:syncItemFields() end) end
    return it
end

-- ชื่อที่จะเขียนบนใบ
--
-- **ชื่อรายการในร้าน กับ รุ่นรถ ไม่ใช่สิ่งเดียวกัน** แอดมินตั้งชื่อรายการว่าอะไรก็ได้
-- ("รถหรู VIP") ส่วนรุ่นคือสิ่งที่จะออกมาจริง ๆ ตอนแกะ
-- ใบที่เขียนแต่ชื่อรายการ = ผู้เล่นไม่มีทางรู้ว่าจะได้รถอะไรจนกว่าจะแกะ
-- ใบที่เขียนแต่รุ่น = ผู้เล่นจำไม่ได้ว่านี่คือของที่ซื้อมาจากรายการไหน
-- เขียนทั้งคู่เมื่อมันต่างกัน  เขียนอันเดียวเมื่อมันซ้ำกัน
local function slipLabel(vehId, shopName)
    local model = S.carLabel(vehId)
    local nm = tostring(shopName or "")
    if nm == "" or nm == model then return model end
    return nm .. " (" .. model .. ")"
end

-- ร้านเรียกตัวนี้ตอนซื้อรถสำเร็จ
function S.carGiveSlip(player, vehId, name)
    if type(vehId) ~= "string" or vehId == "" then
        return nil, "this listing has no vehicle model set"
    end
    if not S.carKnown(vehId) then
        return nil, "'" .. vehId .. "' is not a vehicle on this server"
    end
    return makeSlip(player, vehId, slipLabel(vehId, name))
end

-- ------------------------------------------------------------------------------
-- หาใบในกระเป๋าจากไอดี
--
-- ไคลเอนต์ส่งมาแค่ "ใบไหน"  ที่เหลือเซิร์ฟอ่านเอง
-- ถ้ารับรุ่นรถจากไคลเอนต์ด้วย ใครก็ขอรถรุ่นแพงสุดได้ด้วยแพ็กเก็ตปลอมใบเดียว
-- ------------------------------------------------------------------------------
local function findSlip(player, wantId)
    local inv = player and player:getInventory()
    if not inv then return nil, nil end

    local okItems, items = pcall(function() return inv:getItems() end)
    if not okItems or items == nil then return nil, nil end
    local arr = listOf(items)
    if not arr then return nil, nil end

    local want = tostring(wantId or "")
    for _, it in ipairs(arr) do
        local okT, ft = pcall(function() return it:getFullType() end)
        if okT and ft == KR.SLIP then
            local okI, iid = pcall(function() return it:getID() end)
            if okI and tostring(iid) == want then return it, inv end
        end
    end
    return nil, inv
end

-- ------------------------------------------------------------------------------
-- ที่จอด
--
-- เจ้าของเซิร์ฟเลือกไว้ว่า "หน้าตัวผู้เล่น ต้องมีที่ว่างกลางแจ้ง"
-- ในร่มถูกปฏิเสธเพราะรถที่เกิดในบ้านคือรถที่ขยับไม่ได้ตลอดไป
-- ------------------------------------------------------------------------------
local function squareAt(x, y, z)
    local cell = (type(getCell) == "function") and getCell() or nil
    if cell == nil or not U_hasMethod(cell, "getGridSquare") then return nil end
    local ok, sq = pcall(function() return cell:getGridSquare(x, y, z) end)
    return ok and sq or nil
end

-- ทิศที่ตัวละครหันอยู่  ได้เวกเตอร์มาก็ปัดเป็นก้าวละหนึ่งช่อง
local function facing(player)
    if U_hasMethod(player, "getForwardDirection") then
        local ok, v = pcall(function() return player:getForwardDirection() end)
        if ok and v ~= nil and U_hasMethod(v, "getX") and U_hasMethod(v, "getY") then
            local okX, fx = pcall(function() return v:getX() end)
            local okY, fy = pcall(function() return v:getY() end)
            if okX and okY and type(fx) == "number" and type(fy) == "number" then
                local dx = (fx > 0.4 and 1) or (fx < -0.4 and -1) or 0
                local dy = (fy > 0.4 and 1) or (fy < -0.4 and -1) or 0
                if dx ~= 0 or dy ~= 0 then return dx, dy end
            end
        end
    end
    return 0, 1     -- ไม่รู้ทิศก็เอาใต้ไว้ก่อน  ดีกว่าไม่ทำอะไรเลย
end

local function usable(sq)
    if sq == nil then return false end

    -- กลางแจ้งเป็นเงื่อนไขที่เจ้าของเซิร์ฟสั่ง  ไม่ใช่ของที่ข้ามได้ตอนอ่านไม่ออก
    if not U_hasMethod(sq, "isOutside") then return false end
    local okO, out = pcall(function() return sq:isOutside() end)
    if not okO or not out then return false end

    for _, m in ipairs({ "isSolid", "isSolidTrans" }) do
        if U_hasMethod(sq, m) then
            local okS, solid = pcall(function() return sq[m](sq) end)
            if okS and solid then return false end
        end
    end

    -- มีรถจอดอยู่แล้วก็ไม่เอา  ซ้อนกันแล้วทั้งสองคันเด้งออกจากกัน
    for _, m in ipairs({ "getVehicleContainer", "getVehicle" }) do
        if U_hasMethod(sq, m) then
            local okV, veh = pcall(function() return sq[m](sq) end)
            if okV and veh ~= nil then return false end
        end
    end

    return true
end

-- ห่างออกไปสองช่องก่อน (รถยาวกว่าหนึ่งช่อง) ไม่ได้ค่อยไล่หาที่ว่างรอบ ๆ
local function parkingFor(player)
    local okX, px = pcall(function() return player:getX() end)
    local okY, py = pcall(function() return player:getY() end)
    local okZ, pz = pcall(function() return player:getZ() end)
    if not okX or not okY then return nil end
    local x, y = math.floor(px), math.floor(py)
    local z = (okZ and math.floor(pz)) or 0

    if z ~= 0 then return nil, KR.L("ต้องอยู่ชั้นล่างสุด", "you must be on the ground floor") end

    local dx, dy = facing(player)

    local tries = { { dx * 2, dy * 2 }, { dx * 3, dy * 3 }, { dx, dy } }
    for r = 1, 3 do
        for ox = -r, r do
            for oy = -r, r do
                tries[#tries + 1] = { ox, oy }
            end
        end
    end

    for _, t in ipairs(tries) do
        local sq = squareAt(x + t[1], y + t[2], z)
        if usable(sq) then return sq end
    end
    return nil, KR.L("ไม่มีที่ว่างกลางแจ้งรอบตัว  ออกไปที่โล่งก่อน",
                     "no clear spot outdoors around you - step outside first")
end

-- ------------------------------------------------------------------------------
-- เสกรถ
--
-- **pcall ผ่าน ไม่เท่ากับรถเกิด**  ต้องได้ตัวรถกลับมาถือจริง ๆ
-- ไม่ได้กลับมาก็ไปคุ้ยที่ช่องนั้นดูอีกที  ยังไม่เจอ = ถือว่าไม่เกิด
-- ------------------------------------------------------------------------------
local function vehicleOn(sq)
    for _, m in ipairs({ "getVehicleContainer", "getVehicle" }) do
        if U_hasMethod(sq, m) then
            local ok, veh = pcall(function() return sq[m](sq) end)
            if ok and veh ~= nil then return veh end
        end
    end
    return nil
end

local FRESH_SEEN = false

-- ==============================================================================
-- ทำให้รถที่เกิดมา "เป็นรถ" ไม่ใช่ซาก  (0.6.13)
--
-- เจ้าของเซิร์ฟรายงาน: "ตอนเสกรถมันมีเป็นซากด้วย"
--
-- ต้นเหตุ: addVehicleDebug เสกรถตามที่เอนจินจะเสกในโลก ซึ่งรวมสภาพสุ่มและชิ้นส่วนที่หาย
-- ของเดิมเรียกแค่ setGeneralPartCondition(100, 0) ซึ่งตั้ง "ค่าฐาน" ให้ตอนสร้าง
-- ไม่ได้ย้อนไปซ่อมชิ้นที่ถูกสร้างพังไปแล้ว และไม่ได้ใส่ชิ้นที่หายไปกลับเข้ามา
--
-- **รถที่ซื้อด้วยเงินมาถึงเป็นซาก ไม่ใช่รสนิยม มันคือบั๊ก**
-- จึงไม่มี sandbox ให้ปิด  มันถูกแก้ในโค้ด
--
-- ทุกขั้นห่อ pcall แยกกัน  ทำไม่ได้ข้อไหนก็เสียแค่ข้อนั้น
-- ห้ามให้ขั้นตอนแต่งสภาพทำให้ "รถที่เกิดแล้ว" กลายเป็นความล้มเหลว
-- ==============================================================================
local function fixParts(veh, did)
    if not U_hasMethod(veh, "getPartCount") or not U_hasMethod(veh, "getPartByIndex") then
        return
    end
    local okN, n = pcall(function() return veh:getPartCount() end)
    if not okN or type(n) ~= "number" then return end

    local fixed, filled = 0, 0
    for i = 0, n - 1 do
        local okP, part = pcall(function() return veh:getPartByIndex(i) end)
        if okP and part ~= nil then
            -- ชิ้นที่ยังไม่มีของอยู่ในนั้น ต้องใส่ให้ก่อน ไม่งั้นซ่อมความว่างเปล่า
            if U_hasMethod(part, "getInventoryItem") and U_hasMethod(part, "setInventoryItem") then
                local okI, inv = pcall(function() return part:getInventoryItem() end)
                if okI and inv == nil and U_hasMethod(part, "getItemType") then
                    pcall(function()
                        local t = part:getItemType()
                        if t and t:size() > 0 then
                            local it = instanceItem(t:get(0))
                            if it then part:setInventoryItem(it) end
                        end
                    end)
                end
            end

            if U_hasMethod(part, "setCondition") then
                if pcall(function() part:setCondition(100) end) then fixed = fixed + 1 end
            end

            -- ถังน้ำมัน / ถังอื่น ๆ ที่บรรจุของเหลวได้ เติมให้เต็ม
            if U_hasMethod(part, "getContainerCapacity")
               and U_hasMethod(part, "setContainerContentAmount") then
                local okC, cap = pcall(function() return part:getContainerCapacity() end)
                if okC and type(cap) == "number" and cap > 0 then
                    if pcall(function() part:setContainerContentAmount(cap) end) then
                        filled = filled + 1
                    end
                end
            end
        end
    end
    if fixed  > 0 then did[#did + 1] = "parts:" .. fixed end
    if filled > 0 then did[#did + 1] = "tanks:" .. filled end
end

-- กุญแจที่ตรงกับรถคันนั้น  ไม่ใช่กุญแจเปล่า ๆ ที่เปิดอะไรไม่ได้
local function giveKey(player, veh, did)
    if not KR.svBool("CarGiveKey", true) then return end

    local okId, keyId = pcall(function() return veh:getKeyId() end)
    if not okId or keyId == nil then return end

    local okMake, key = pcall(instanceItem, "Base.CarKey")
    if not okMake or key == nil then return end

    -- ประทับไอดีให้ครบทุกทางที่บิลด์ไหนอาจอ่าน  ทางที่ไม่มีก็แค่ข้าม
    if U_hasMethod(key, "setKeyId") then pcall(function() key:setKeyId(keyId) end) end
    pcall(function()
        local md = key:getModData()
        if type(md) == "table" then md.keyId = keyId end
    end)
    if U_hasMethod(key, "setName") then
        pcall(function() key:setName(S.carLabel(veh:getScript():getName()) .. " Key") end)
    end

    local inv = player and player:getInventory()
    if inv then
        inv:AddItem(key)
        if type(sendAddItemToContainer) == "function" then
            pcall(sendAddItemToContainer, inv, key)
        end
        if U_hasMethod(key, "syncItemFields") then pcall(function() key:syncItemFields() end) end
        did[#did + 1] = "key"
    end

    -- สำรองไว้ในสวิตช์กุญแจด้วย  คนทำใบรถหายยังขับได้
    if U_hasMethod(veh, "setKeysInIgnition") then
        pcall(function() veh:setKeysInIgnition(true) end)
    end
end

-- เหรียญ claim หรืออะไรก็ตามที่เจ้าของเซิร์ฟตั้งไว้ใน sandbox
-- ตอนนี้ยังว่าง  เขาบอกว่าจะเพิ่มไอเทมทีหลังเอง แล้วมาใส่ชื่อ Base.xxx ตรงนี้
local function giveExtra(player, did)
    local id = KR.svStr("CarExtraItem", "")
    if id == "" then return end
    local n = math.max(1, math.min(20, KR.svInt("CarExtraCount", 1) or 1))

    local made, err = S.giveItems(player, id, n)
    if made >= n then
        did[#did + 1] = "extra:" .. id .. "x" .. n
    else
        -- รถมาแล้ว ของแถมไม่มา  ห้ามเงียบ เจ้าของเซิร์ฟตั้งชื่อผิดได้
        print("[Kuraya] cars: extra item '" .. id .. "' could not be given -> " ..
              tostring(err or "partial"))
    end
end

local function makeFresh(player, veh)
    local did = {}

    if U_hasMethod(veh, "setGeneralPartCondition") then
        if pcall(function() veh:setGeneralPartCondition(100, 0) end) then
            did[#did + 1] = "general"
        end
    end

    fixParts(veh, did)
    giveKey(player, veh, did)
    giveExtra(player, did)

    for _, m in ipairs({ "transmitPartUsedDelta", "transmitCompleteItemToClients" }) do
        if U_hasMethod(veh, m) then pcall(function() veh[m](veh) end) end
    end

    -- พิมพ์ครั้งเดียวพอ  เจ้าของเซิร์ฟอยากรู้ว่า "ใหม่เอี่ยม" ทำได้จริงกี่ข้อ
    if not FRESH_SEEN then
        FRESH_SEEN = true
        print("[Kuraya] cars: fresh-car steps that worked on this build: " ..
              (#did > 0 and table.concat(did, ", ") or "none - cars spawn as the engine makes them"))
    end
end

local function spawn(vehId, sq)
    if type(addVehicleDebug) ~= "function" then
        return nil, KR.L("บิลด์นี้เสกรถจากสคริปต์ไม่ได้", "this build cannot spawn vehicles from Lua")
    end

    local dir = nil
    if IsoDirections ~= nil then
        local okD, d = pcall(function() return IsoDirections.N end)
        if okD then dir = d end
    end

    local okRun, got = pcall(addVehicleDebug, vehId, dir, nil, sq)
    if not okRun then
        return nil, KR.L("เอนจินปฏิเสธ: ", "the engine refused: ") .. tostring(got)
    end

    local veh = got
    if veh == nil then veh = vehicleOn(sq) end
    if veh == nil then
        return nil, KR.L("เรียกเสกไปแล้วแต่ไม่มีรถโผล่ที่ช่องนั้น",
                         "the spawn call returned but no vehicle appeared on that tile")
    end
    return veh
end

-- ==============================================================================
-- ผู้เล่นกดแกะใบ
-- ==============================================================================
function S.carUnpack(player, args)
    local k = key(player); if not k then return end

    local it, inv = findSlip(player, args and args.item)
    if not it then
        return alert(player, "That slip is not in your inventory any more.", "bad")
    end

    -- รุ่นรถอ่านจากใบ ไม่ใช่จากแพ็กเก็ต
    local okMd, md = pcall(function() return it:getModData() end)
    local vehId = (okMd and type(md) == "table") and tostring(md.krVehicle or "") or ""
    if vehId == "" then
        return alert(player, "This slip does not say which vehicle it is for." ..
                             " Show it to an admin.", "bad")
    end

    local sq, why = parkingFor(player)
    if not sq then
        return alert(player, why or "No room here.", "warn")
    end

    -- ---- เอาใบออกก่อน  แล้วค่อยเสก -------------------------------------------
    -- ลำดับนี้สำคัญกว่าที่มันดู  ถ้าเสกก่อนแล้วค่อยเอาใบออก จะมีหนึ่งเฟรมที่
    -- ทั้งรถและใบอยู่ด้วยกัน  ผู้เล่นที่กดรัว ๆ ได้สองคันจากใบเดียว
    -- ทางนี้แย่ที่สุดคือใบหายแล้วรถไม่มา ซึ่งเราคืนใบให้ทันทีในบรรทัดถัดไป
    if type(sendRemoveItemFromContainer) == "function" then
        pcall(sendRemoveItemFromContainer, inv, it)
    end
    pcall(function() inv:Remove(it) end)

    local veh, err = spawn(vehId, sq)
    if not veh then
        -- คืนใบใบใหม่ที่เหมือนเดิมทุกอย่าง  เรารู้รุ่นอยู่แล้วจึงสร้างคืนได้แน่นอน
        local back = makeSlip(player, vehId, (okMd and md.krVehName) or S.carLabel(vehId))
        print("[Kuraya] cars: " .. tostring(k) .. " could not unpack '" .. vehId ..
              "' -> " .. tostring(err) .. (back and "  (slip returned)" or "  !! SLIP LOST"))
        -- บนจอเอาแบบสั้น  ตัวเต็มอยู่ใน console บรรทัดข้างบนนี้แล้ว
        return alert(player, brief(err) ..
                     (back and " Your slip was returned." or
                              " YOUR SLIP COULD NOT BE RETURNED - tell an admin now."), "bad")
    end

    makeFresh(player, veh)

    local name = (okMd and md.krVehName) or S.carLabel(vehId)
    print("[Kuraya] cars: " .. tostring(k) .. " unpacked " .. vehId)
    alert(player, KR.L("รถของคุณจอดอยู่ข้าง ๆ แล้ว: ", "Your vehicle is parked beside you: ") ..
                  tostring(name), "good")
end

print("[Kuraya] KR_Cars ready")
return true
