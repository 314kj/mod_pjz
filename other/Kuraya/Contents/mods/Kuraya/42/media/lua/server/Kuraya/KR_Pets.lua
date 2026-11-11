-- ==============================================================================
-- Kuraya — server/Kuraya/KR_Pets.lua
-- ขายสัตว์  ร้านจ่ายเป็น "ใบสัตว์" แล้วผู้เล่นแกะเอง
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- ไฟล์นี้เป็นฝาแฝดของ KR_Cars.lua โดยตั้งใจ  โครงเดียวกันทุกขั้น
-- แคตตาล็อกอ่านตอนรัน -> ใบที่จำ "ตัวไหน" ไว้ใน ModData -> แกะแล้วเสกของจริง
--
-- **ทำไมไม่รวมเป็นไฟล์เดียวกับรถ**
--   สองอย่างนี้เหมือนกันแค่รูปร่าง ไม่ได้เหมือนกันที่เนื้อใน
--     รถ  : เสกด้วย addVehicleDebug  ต้องซ่อมชิ้นส่วน เติมน้ำมัน แจกกุญแจ
--     สัตว์: เสกด้วย addAnimal        ต้องรู้ชนิดกับสายพันธุ์ ไม่มีชิ้นส่วนให้ซ่อม
--   ฟังก์ชันที่รวมสองเรื่องนี้ไว้จะเต็มไปด้วย if ที่ถามว่า "นี่รถหรือสัตว์"
--   ซึ่งคือการเขียนสองฟังก์ชันไว้ในฟังก์ชันเดียวโดยไม่ได้ประหยัดอะไรเลย
--
-- กฎเหล็กสามข้อ  เหมือนของรถเป๊ะ ๆ เพราะมันคือกฎของ "ใบ" ไม่ใช่กฎของรถ
--   1. เอาใบออกก่อน แล้วค่อยเสก  เสกไม่สำเร็จต้องคืนใบทันที
--   2. pcall ผ่าน ไม่เท่ากับสัตว์เกิด  ต้องได้ตัวสัตว์กลับมาถือจริง
--   3. รายชื่อสัตว์อ่านจากเกมตอนรัน ห้ามฝังไว้ในโค้ด
--      (เซิร์ฟนี้ลงม็อดสัตว์เพิ่มเมื่อไรก็ได้ และรายชื่อที่พิมพ์เองจะผิดวันนั้นทันที)
--
-- ไอดีของสัตว์หนึ่งตัวในม็อดนี้เขียนว่า  "ชนิด"  หรือ  "ชนิด:สายพันธุ์"
--   "cow"          = วัว สายพันธุ์ไหนก็ได้ที่เกมเลือกให้
--   "cow:angus"    = วัวพันธุ์แองกัส
-- ใช้ ":" ไม่ใช่ "." เพราะ "." คือตัวคั่นของ **ไอเทม** (Base.Axe) อยู่แล้ว
-- ถ้าใช้ตัวเดียวกัน ช่องกรอกช่องเดียวกันจะแยกไม่ออกว่าแอดมินหมายถึงอะไร
-- ==============================================================================
require("Kuraya/KR_Const")
require("Kuraya/KR_Server")

print("[Kuraya] KR_Pets  v" .. KR.VERSION)

local S = KR.server
if not S then
    print("[Kuraya] !! KR_Pets: KR_Server failed to load - pets disabled")
    return
end

local key, alert = S.key, S.alert

-- ------------------------------------------------------------------------------
-- ตัวช่วยอ่านของฝั่ง Java  (สำเนาเดียวกับ KR_Cars — locals ข้ามไฟล์กันไม่ได้)
-- ------------------------------------------------------------------------------
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

-- ชื่อที่คนอ่านออก  "cow:angus" -> "Cow (Angus)"
-- ------------------------------------------------------------------------------
-- ข้อความ error ของ Java ยาวเกินกว่าจะเอาไปแปะหน้าผู้เล่น  (0.6.17)
--
-- เจ้าของเซิร์ฟส่งภาพมา: บรรทัด error พาดขวางเต็มความกว้างจอ ทับทุกอย่าง
-- อ่านไม่ออกสักคำ เพราะมันคือ exception ของ Java ทั้งก้อนรวม class path
--
-- คนที่อ่าน stack trace ออกคือคนที่เปิด console ได้  ซึ่งไม่ใช่คนที่กำลังยืนอยู่ตรงนั้น
-- **ข้อความที่ยาวจนอ่านไม่ได้ ให้ข้อมูลเท่ากับไม่มีข้อความเลย แต่กินจอมากกว่า**
-- ตัวเต็มไปอยู่ใน console ฝั่งเซิร์ฟ  บนจอเหลือเท่าที่อ่านจบในหนึ่งบรรทัด
local function brief(e)
    local t = tostring(e or "")
    -- ตัดหัวที่เป็น path ของไฟล์ Lua ออก  ("KR_Pets.lua:123: ข้อความจริง")
    t = t:gsub("^.-%.lua:%d+:%s*", "")
    -- เอาแต่ประโยคแรกของ Java  ส่วนที่เหลือเป็นรายการ class ยาวเหยียด
    local head = t:match("^([^\n]*)") or t
    head = head:gsub("%s+", " ")
    if #head > 110 then head = head:sub(1, 107) .. "..." end
    return head
end

local function titleCase(s)
    s = tostring(s or "")
    if s == "" then return s end
    return s:sub(1, 1):upper() .. s:sub(2)
end

local function labelOf(typ, breed)
    local t = titleCase(typ)
    if type(getText) == "function" then
        for _, k in ipairs({ "IGUI_AnimalType" .. tostring(typ),
                             "IGUI_Animal_" .. tostring(typ) }) do
            local ok, s = pcall(getText, k)
            if ok and type(s) == "string" and s ~= "" and s ~= k then t = s; break end
        end
    end
    if breed and breed ~= "" then return t .. " (" .. titleCase(breed) .. ")" end
    return t
end

-- ------------------------------------------------------------------------------
-- แยก "ชนิด:สายพันธุ์" ออกจากกัน  ไม่มี ":" ก็คือชนิดล้วน
--
-- ต้องทนกับช่องว่างที่คนพิมพ์ติดมา  แอดมินคัดลอกชื่อมาวางแล้วมีเว้นวรรคท้าย
-- คือเรื่องปกติ และมันจะกลายเป็น "ไม่พบสัตว์ชนิดนี้" ที่ไม่มีใครมองออกว่าทำไม
-- ------------------------------------------------------------------------------
local function splitId(id)
    local s = tostring(id or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil, nil end
    local t, b = s:match("^([^:]+):(.+)$")
    if t then
        t = t:gsub("%s+$", ""):lower()
        b = b:gsub("^%s+", "")
        return t, b
    end
    return s:lower(), nil
end

local function joinId(typ, breed)
    if breed and breed ~= "" then return tostring(typ) .. ":" .. tostring(breed) end
    return tostring(typ)
end

-- ------------------------------------------------------------------------------
-- แคตตาล็อกสัตว์  อ่านจากเกมจริง
--
-- **รูปร่างของสิ่งที่ getAllAnimalsDefinitions() คืนมา คือข้อที่เราไม่รู้แน่**
-- เอกสารของ 42.20 ยืนยันแค่ว่าฟังก์ชันนี้มีอยู่ ไม่ได้บอกว่าข้างในหน้าตายังไง
-- จึงรับได้ทุกแบบที่เป็นไปได้แล้ว **บอกด้วยว่าอันไหนตอบ** เหมือนที่ทำกับรถ
--
--   แบบ A  ตาราง Lua ที่คีย์คือชื่อชนิด  ค่าคือ def ที่มี .breeds
--   แบบ B  ตาราง Lua ที่มี .animals อยู่ข้างใน (โครงของ AnimalDefinitions วานิลลา)
--   แบบ C  ลิสต์ Java ที่เดินด้วย size()/get(i)
--
-- อ่านไม่ออกสักแบบ = รายการว่าง แอดมินยังพิมพ์ชื่อชนิดเองได้ ฟีเจอร์ไม่ตาย
-- ------------------------------------------------------------------------------
local CATALOG, BY_ID, HOW = nil, nil, nil

-- ชื่อสายพันธุ์จาก def หนึ่งก้อน  def มาได้หลายทรงเหมือนกัน
-- ชื่อของก้อนพันธุ์หนึ่งก้อน  มันมาได้ทั้งสตริง ตาราง Lua และออบเจกต์ Java
local function breedName(v)
    if type(v) == "string" then return v end
    if type(v) == "table" then
        for _, k in ipairs({ "name", "breedName", "id" }) do
            if type(v[k]) == "string" and v[k] ~= "" then return v[k] end
        end
    end
    for _, m in ipairs({ "getName", "getBreedName", "getId" }) do
        if U_hasMethod(v, m) then
            local ok, r = pcall(function() return v[m](v) end)
            if ok and type(r) == "string" and r ~= "" then return r end
        end
    end
    return nil
end

-- ==============================================================================
-- สายพันธุ์ของชนิดหนึ่ง
--
-- **นี่คือจุดที่พังจริงบนเซิร์ฟ และมันพังเงียบสนิท**  (แก้ 0.6.18)
--
-- ภาพดรอปดาวน์จากเจ้าของเซิร์ฟแสดงชนิดครบ (boar / buck / bull / chick /
-- cockerel / cow) แต่ **ไม่มีสายพันธุ์เลยสักตัว**  ซึ่งแปลว่า:
--   getAllAnimalsDefinitions() ตอบแล้ว และเราอ่านชนิดได้
--   แต่ breedsOf() คืนตารางว่างทุกครั้ง
--
-- ผลที่ตามมาคือสิ่งที่ทำให้ "เสกไม่ได้ทุกวิธี": breedsToTry() ได้ลิสต์ว่าง
-- -> ทุกรูปแบบที่ต้องมีพันธุ์ถูก **ข้าม** -> เหลือแต่รูปแบบที่ไม่ส่งพันธุ์
-- ซึ่ง 42.20 ไม่มี overload ให้เลยสักอัน -> ล้มครบทุกทาง
--
-- ของเดิมผิดสองข้อ และทั้งสองข้อคือ "คิดว่าของจาก Java เป็นตาราง Lua"
--   1. `if type(def) ~= "table" then return out end`
--      def ที่เป็นออบเจกต์ Java (userdata) เด้งออกตั้งแต่บรรทัดแรก
--   2. `if type(br) == "table"`
--      ลิสต์ของ Java ไม่ใช่ table  ต้องเดินด้วย size()/get(i) ซึ่ง listOf() ทำอยู่แล้ว
--
-- **listOf() มีอยู่ในไฟล์นี้ตั้งแต่แรก แต่ตรงนี้ไม่ได้เรียกใช้**
-- เขียนตัวอ่านเองซ้ำในที่ที่มีตัวอ่านที่ถูกต้องอยู่แล้ว คือวิธีที่บั๊กแบบนี้เกิด
-- ==============================================================================
local function breedsOf(def)
    local out, seen = {}, {}
    if def == nil then return out end

    local function add(v)
        local n = breedName(v)
        if n and not seen[n] then seen[n] = true; out[#out + 1] = n end
    end

    -- หาก้อนที่เก็บพันธุ์ไว้  ทั้งแบบฟิลด์และแบบเมธอด
    local cands = {}
    if type(def) == "table" then
        cands[#cands + 1] = def.breeds
        cands[#cands + 1] = def.breedList
        cands[#cands + 1] = def.Breeds
    end
    for _, m in ipairs({ "getBreeds", "getAllBreeds", "getBreedList" }) do
        if U_hasMethod(def, m) then
            local ok, r = pcall(function() return def[m](def) end)
            if ok then cands[#cands + 1] = r end
        end
    end

    for _, br in ipairs(cands) do
        -- ลิสต์ Java ก่อน  listOf() เดินด้วย size()/get(i) ให้เอง
        local arr = listOf(br)
        if arr then
            for _, v in ipairs(arr) do add(v) end
        end
        -- แล้วค่อยตารางที่คีย์คือชื่อพันธุ์
        if type(br) == "table" then
            for k, v in pairs(br) do
                add(v)
                if type(k) == "string" then add(k) end
            end
        end
    end

    table.sort(out, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return out
end

local function addRow(rows, seen, typ, breed)
    local id = joinId(typ, breed)
    if seen[id] then return end
    seen[id] = true
    rows[#rows + 1] = { id = id, label = labelOf(typ, breed) }
end

-- เดินตาราง type -> def แล้วแตกเป็นแถว  คืนจำนวนชนิดที่อ่านได้
local function harvest(map, rows, seen)
    local n = 0
    for typ, def in pairs(map) do
        if type(typ) == "string" and typ ~= "" then
            n = n + 1
            addRow(rows, seen, typ, nil)      -- ชนิดล้วน  เกมเลือกพันธุ์ให้เอง
            for _, b in ipairs(breedsOf(def)) do
                addRow(rows, seen, typ, b)
            end
        end
    end
    return n
end

local function build(force)
    if CATALOG and not force then return CATALOG end

    CATALOG, BY_ID, HOW = {}, {}, nil
    local rows, seen = {}, {}

    -- ==========================================================================
    -- ทางที่หนึ่ง  **ตาราง Lua ของวานิลลา — ยืนยันรูปร่างแล้วด้วยตา**  (0.6.20)
    --
    -- ผลดัมป์จากเซิร์ฟจริงบอกชัดว่าสายพันธุ์อยู่ที่นี่ และอยู่ในรูปที่อ่านง่ายที่สุด:
    --
    --   AnimalDefinitions.animals.chick.breeds  =  table (2 keys)
    --       rhodeisland : table (17 keys)
    --       leghorn     : table (17 keys)
    --
    -- คีย์ของตารางคือชื่อพันธุ์ตรง ๆ  ไม่ต้องเดาอะไรอีก
    --
    -- **ทำไมย้ายมาไว้ก่อน getAllAnimalsDefinitions()**
    -- เพราะนั่นคือบั๊กของ 0.6.18-0.6.19 เป๊ะ ๆ: ฟังก์ชันนั้นคืน "ลิสต์ Java ของ def"
    -- โค้ดจึงเข้าสาขา java-list ซึ่ง **อ่านแต่ชนิด ไม่เคยอ่านสายพันธุ์เลย**
    -- แล้วเพราะได้แถวมาแล้ว (#rows > 0) ทางของ AnimalDefinitions ที่มีพันธุ์ครบ
    -- ก็ไม่เคยถูกเรียกใช้  ผลคือ breeds tried=0 ทุกครั้ง
    -- และรูปแบบ 6 อาร์กิวเมนต์ที่น่าจะถูกที่สุด **ถูกข้ามทุกครั้ง ไม่เคยได้ลองเลย**
    -- (log นับได้: ข้าม 7 แบบ ลองจริงแค่ 6 แบบ)
    --
    -- บทเรียน: ทางที่ "เอกสารบอกว่ามี" ไม่จำเป็นต้องเป็นทางที่ให้ข้อมูลครบที่สุด
    -- เลือกทางที่ **เราเห็นรูปร่างของมันแล้ว** ก่อนทางที่เรายังต้องเดา
    -- ==========================================================================
    if type(AnimalDefinitions) == "table" then
        local src = (type(AnimalDefinitions.animals) == "table")
                    and AnimalDefinitions.animals or AnimalDefinitions
        if harvest(src, rows, seen) > 0 then
            HOW = (type(AnimalDefinitions.animals) == "table")
                  and "AnimalDefinitions.animals" or "AnimalDefinitions"
        end
    end

    -- ทางที่สอง  ฟังก์ชันโกลบอลที่เอกสารระบุ  ใช้ตอนทางแรกไม่ตอบ
    if #rows == 0 and type(getAllAnimalsDefinitions) == "function" then
        local okV, v = pcall(getAllAnimalsDefinitions)
        if okV and type(v) == "table" then
            if type(v.animals) == "table" and harvest(v.animals, rows, seen) > 0 then
                HOW = "getAllAnimalsDefinitions().animals"
            elseif harvest(v, rows, seen) > 0 then
                HOW = "getAllAnimalsDefinitions()"
            end
        elseif okV and v ~= nil then
            local arr = listOf(v)
            for _, e in ipairs(arr or {}) do
                local t = nil
                if type(e) == "string" then t = e
                elseif U_hasMethod(e, "getAnimalType") then
                    local okT, s = pcall(function() return e:getAnimalType() end)
                    if okT and type(s) == "string" then t = s end
                end
                if t then addRow(rows, seen, t, nil) end
            end
            if #rows > 0 then HOW = "getAllAnimalsDefinitions() [java list]" end
        end
    end

    if #rows > 0 then
        -- ตัวเทียบต้องตัดสินให้ขาดเสมอ  เท่ากันแล้วคืน false ทั้งสองทาง
        -- table.sort จะพังแบบสุ่ม (กฎเดียวกับ KR.sortList และแคตตาล็อกรถ)
        table.sort(rows, function(a, b)
            local x, y = a.label:lower(), b.label:lower()
            if x ~= y then return x < y end
            return a.id < b.id
        end)
        CATALOG = rows
        for _, r in ipairs(rows) do BY_ID[r.id] = r end
    end

    print("[Kuraya] pets: " .. #CATALOG .. " animals read via " ..
          tostring(HOW or "nothing that answered"))
    return CATALOG
end

S.petsBuild = build

-- สัตว์ตัวนี้มีอยู่จริงไหม
--
-- แคตตาล็อกว่าง = เราอ่านรายชื่อไม่ได้ ไม่ได้แปลว่าสัตว์ชนิดนั้นไม่มี
-- ตอบว่า "ไม่มี" ตอนที่ความจริงคือ "ไม่รู้" คือการโกหก และมันบล็อกทุกการซื้อ
-- บนบิลด์ที่เราอ่านรายชื่อไม่ออก  (เหตุผลเดียวกับ S.carKnown ทุกตัวอักษร)
function S.petKnown(id)
    local typ = splitId(id)
    if not typ then return false end
    build()
    if #CATALOG == 0 then return true end
    if BY_ID[joinId(splitId(id))] ~= nil then return true end
    -- สายพันธุ์ที่เราไม่รู้จัก แต่ชนิดรู้จัก ยังถือว่าใช้ได้
    -- เกมมีพันธุ์ที่ม็อดอื่นเติมเข้ามาได้ และการปฏิเสธจะบล็อกของที่ใช้ได้จริง
    return BY_ID[typ] ~= nil
end

function S.petLabel(id)
    build()
    local row = BY_ID[tostring(id or "")]
    if row then return row.label end
    local typ, breed = splitId(id)
    if not typ then return tostring(id or "") end
    return labelOf(typ, breed)
end

-- แอดมินขอรายชื่อไปใส่ในฟอร์ม
function S.petList(player, args)
    build(args and args.refresh and true or false)
    sendServerCommand(player, KR.MODULE, KR.CMD.PET_LIST, {
        rows = CATALOG,
        how  = HOW,
    })
end

-- ==============================================================================
-- ใบสัตว์
-- ==============================================================================

-- ใบทุกใบเป็นไอเทมชนิดเดียวกัน  ตัวสัตว์อยู่ใน ModData ไม่ใช่ในชนิดไอเทม
-- **ฝั่งเซิร์ฟเป็นเจ้าของความจริงเสมอ** ตอนแกะ เซิร์ฟอ่าน ModData ของตัวเอง
-- ไคลเอนต์บอกได้แค่ "ใบไหน" ไม่ได้บอกว่า "ใบนี้เป็นสัตว์อะไร"
local function stamp(it, petId, label)
    local okMd, md = pcall(function() return it:getModData() end)
    if not okMd or type(md) ~= "table" then return false end

    md.krPet     = petId
    md.krPetName = label

    if U_hasMethod(it, "setName") then
        pcall(function() it:setName(KR.L("ใบสัตว์ - ", "Animal slip - ") .. tostring(label)) end)
    end

    for _, m in ipairs({ "transmitModData", "syncItemFields" }) do
        if U_hasMethod(it, m) then pcall(function() it[m](it) end) end
    end
    return true
end

local function makeSlip(player, petId, label)
    local inv = player and player:getInventory()
    if not inv then return nil, "no inventory" end

    local okMake, it = pcall(instanceItem, KR.PET_SLIP)
    if not okMake then
        return nil, "engine refused to build " .. KR.PET_SLIP .. " (" .. tostring(it) .. ")"
    end
    if it == nil then
        return nil, KR.PET_SLIP .. " could not be created - is the Kuraya item script installed?"
    end

    stamp(it, petId, label)
    inv:AddItem(it)
    -- ประกาศก่อน แล้วค่อยซิงก์  ซิงก์ฟิลด์ของไอเทมที่ไคลเอนต์ยังไม่รู้จัก = NPE ฝั่งเขา
    if type(sendAddItemToContainer) == "function" then
        pcall(sendAddItemToContainer, inv, it)
    end
    if U_hasMethod(it, "syncItemFields") then pcall(function() it:syncItemFields() end) end
    return it
end

-- ชื่อรายการในร้าน กับ ตัวสัตว์ ไม่ใช่สิ่งเดียวกัน  เขียนทั้งคู่เมื่อมันต่างกัน
local function slipLabel(petId, shopName)
    local animal = S.petLabel(petId)
    local nm = tostring(shopName or "")
    if nm == "" or nm == animal then return animal end
    return nm .. " (" .. animal .. ")"
end

-- ร้านเรียกตัวนี้ตอนซื้อสัตว์สำเร็จ
function S.petGiveSlip(player, petId, name)
    if type(petId) ~= "string" or petId == "" then
        return nil, "this listing has no animal set"
    end
    if not S.petKnown(petId) then
        return nil, "'" .. petId .. "' is not an animal on this server"
    end
    return makeSlip(player, petId, slipLabel(petId, name))
end

-- ------------------------------------------------------------------------------
-- หาใบในกระเป๋าจากไอดี  ไคลเอนต์ส่งมาแค่ "ใบไหน" ที่เหลือเซิร์ฟอ่านเอง
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
        if okT and ft == KR.PET_SLIP then
            local okI, iid = pcall(function() return it:getID() end)
            if okI and tostring(iid) == want then return it, inv end
        end
    end
    return nil, inv
end

-- ------------------------------------------------------------------------------
-- ที่ยืนของสัตว์
--
-- ต่างจากรถสองข้อ และทั้งสองข้อมีเหตุผล
--   1. ในร่มได้  เล้ากับคอกอยู่ในร่ม  บังคับออกกลางแจ้ง = บังคับให้ปล่อยสัตว์นอกคอก
--   2. ชั้นบนได้  สัตว์เดินลงบันไดเองได้ ต่างจากรถที่ขึ้นไปแล้วลงไม่ได้ตลอดกาล
-- เหลือเงื่อนไขเดียวคือ "ช่องนั้นมีที่ให้ยืนจริง"
-- ------------------------------------------------------------------------------
local function squareAt(x, y, z)
    local cell = (type(getCell) == "function") and getCell() or nil
    if cell == nil or not U_hasMethod(cell, "getGridSquare") then return nil end
    local ok, sq = pcall(function() return cell:getGridSquare(x, y, z) end)
    return ok and sq or nil
end

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
    return 0, 1
end

local function usable(sq)
    if sq == nil then return false end

    for _, m in ipairs({ "isSolid", "isSolidTrans" }) do
        if U_hasMethod(sq, m) then
            local okS, solid = pcall(function() return sq[m](sq) end)
            if okS and solid then return false end
        end
    end

    -- มีรถจอดอยู่ตรงนั้น = ไม่ใช่ที่ยืน  สัตว์ที่เกิดใต้ท้องรถคือสัตว์ที่ติดอยู่
    for _, m in ipairs({ "getVehicleContainer", "getVehicle" }) do
        if U_hasMethod(sq, m) then
            local okV, veh = pcall(function() return sq[m](sq) end)
            if okV and veh ~= nil then return false end
        end
    end

    return true
end

local function spotFor(player)
    local okX, px = pcall(function() return player:getX() end)
    local okY, py = pcall(function() return player:getY() end)
    local okZ, pz = pcall(function() return player:getZ() end)
    if not okX or not okY then return nil end
    local x, y = math.floor(px), math.floor(py)
    local z = (okZ and math.floor(pz)) or 0

    local dx, dy = facing(player)

    -- ตรงหน้าก่อนเสมอ  เจ้าของเซิร์ฟสั่งว่า "แกะออกมาเป็นสัตว์ตรงหน้า"
    -- ช่องรอบตัวเป็นแผนสำรอง ไม่ใช่ทางเลือกแรก
    local tries = { { dx, dy }, { dx * 2, dy * 2 } }
    for r = 1, 2 do
        for ox = -r, r do
            for oy = -r, r do
                if not (ox == 0 and oy == 0) then tries[#tries + 1] = { ox, oy } end
            end
        end
    end

    for _, t in ipairs(tries) do
        local sq = squareAt(x + t[1], y + t[2], z)
        if usable(sq) then return sq end
    end
    return nil, KR.L("ไม่มีที่ว่างรอบตัว  ขยับออกจากมุมห้องก่อน",
                     "no clear tile around you - step away from the wall first")
end

-- ==============================================================================
-- เสกสัตว์
--
-- **ลายเซ็นจริงของ addAnimal คือสิ่งที่เราไม่รู้ และเคยเดาผิดมาแล้ว**  (0.6.17)
--
-- 0.6.16 เรียกด้วยห้าอาร์กิวเมนต์ตามที่เอกสารบอกว่า breed เป็นตัวเลือก
-- เซิร์ฟจริงตอบกลับมาว่า:
--
--   java.lang.RuntimeException: No implementation found for function:
--   addAnimal(class zombie.iso.IsoCell, class java.lang.Double 4184.0,
--             class java.lang.Double 1385.0, class java.lang.Double 0.0,
--             class java.lang.String cow)
--
-- แปลว่า overload ห้าตัวไม่มีอยู่จริงบนบิลด์ 42.20  "ตัวเลือก" ในเอกสาร Lua
-- หมายถึง overload คนละตัว ไม่ได้แปลว่าละได้
--
-- และ **Kahlua เช็ค arity เป๊ะ  nil ต่อท้ายนับเป็นอาร์กิวเมนต์**
-- (PZ-B42-kahlua-java-method-arity-RULE — ม็อดสองตัวเคยตายเงียบเพราะข้อนี้)
-- ตัวช่วยตัวเดียวที่รับ b แล้วส่งต่อจึงใช้ไม่ได้  ต้องเขียนแยกเป็นรูปแบบละก้อน
-- ที่เรียกด้วยจำนวนอาร์กิวเมนต์ของตัวเองตายตัว
--
-- วิธีที่ใช้แทนการเดา: **ลองทีละรูปแบบ แล้วบอกว่าอันไหนตอบ**
-- อันเดียวกับที่ใช้อ่านรายชื่อรถ (0.6.11) และรายชื่อสัตว์  ระบบที่บอกได้ว่า
-- มันเห็นอะไร ต่างจากระบบที่เงียบแล้วให้เราเดา
--
-- **pcall ผ่าน ไม่เท่ากับสัตว์เกิด** ต้องได้ตัวกลับมาถือจริง
-- ==============================================================================

-- ==============================================================================
-- **ลายเซ็นจริง ยืนยันจาก JavaDocs ของ 42.20 แล้ว**  (0.6.21)
--
--   static IsoAnimal addAnimal(IsoCell cell, int x, int y, int z,
--                              String animalType, AnimalBreed breed)
--   static IsoAnimal addAnimal(IsoCell cell, int x, int y, int z,
--                              String animalType, AnimalBreed breed, boolean skeleton)
--
-- **พารามิเตอร์ตัวที่หกเป็นออบเจกต์ AnimalBreed ไม่ใช่สตริง**
--
-- นี่คือคำตอบของทุกอย่างที่ผ่านมา  ทุกรูปแบบที่เราส่ง "ชื่อพันธุ์เป็นสตริง"
-- ถูกปฏิเสธด้วย No implementation found ไม่ใช่เพราะอาร์ริตี้ผิด แต่เพราะ **ชนิดผิด**
-- และเอกสาร Lua ที่เขียนว่า `breed` ไม่ได้บอกว่าเป็นชนิดอะไร เราจึงเดาว่าสตริง
--
-- บทเรียน: "ลองทุกอาร์ริตี้" แก้ปัญหาอาร์ริตี้ได้ แต่แก้ปัญหา **ชนิด** ไม่ได้เลย
-- ไล่รูปแบบสิบแบบแล้วยังผิดทุกแบบ = สัญญาณว่าเราผิดที่สมมติฐาน ไม่ใช่ผิดที่จำนวน
-- ตอนนั้นควรไปหาลายเซ็นจริง ไม่ใช่เพิ่มแบบที่สิบเอ็ด
--
-- วิธีได้ AnimalBreed (JavaDocs ของ AnimalDefinitions):
--   AnimalDefinitions.getDef(animalType)  -> AnimalDefinitions   (static)
--       :getBreedByName(name)  -> AnimalBreed
--       :getBreeds()           -> ArrayList<AnimalBreed>
--       :getRandomBreed()      -> AnimalBreed
--
-- ตรงกับผลดัมป์จากเซิร์ฟเป๊ะ ๆ: ตาราง AnimalDefinitions มี getDef / getAnimalDefs /
-- getAnimalDefsArray เป็น function อยู่จริง
-- ==============================================================================
local function breedObj(typ, name)
    if type(AnimalDefinitions) ~= "table" then
        return nil, "AnimalDefinitions is " .. type(AnimalDefinitions)
    end
    local getDef = AnimalDefinitions.getDef
    if type(getDef) ~= "function" then
        return nil, "AnimalDefinitions.getDef is " .. type(getDef)
    end

    -- getDef เป็น static  เรียกด้วยจุด ไม่ใช่ทวิภาค  (ทวิภาคจะส่งตารางไปเป็น arg แรก)
    local okD, def = pcall(getDef, typ)
    if not okD or def == nil then
        return nil, "getDef('" .. tostring(typ) .. "') gave " ..
                    (okD and "nil" or tostring(def))
    end

    -- ชื่อที่แอดมินเลือกไว้ก่อน
    if name and name ~= "" and U_hasMethod(def, "getBreedByName") then
        local ok, b = pcall(function() return def:getBreedByName(name) end)
        if ok and b ~= nil then return b end
    end

    -- ชื่อไม่ตรง ก็เอาพันธุ์แรกที่ def มีจริง  **สัตว์ที่ได้พันธุ์ไม่ตรงยังเป็นสัตว์**
    if U_hasMethod(def, "getBreeds") then
        local ok, lst = pcall(function() return def:getBreeds() end)
        if ok then
            local arr = listOf(lst)
            if arr and arr[1] ~= nil then return arr[1] end
        end
    end

    if U_hasMethod(def, "getRandomBreed") then
        local ok, b = pcall(function() return def:getRandomBreed() end)
        if ok and b ~= nil then return b end
    end

    return nil, "def for '" .. tostring(typ) .. "' has no breed we could read"
end

-- แต่ละก้อนเรียก addAnimal ด้วยจำนวนอาร์กิวเมนต์ของตัวเองเป๊ะ ๆ ห้ามส่ง nil ต่อท้าย
-- needBreed = ต้องมีชื่อพันธุ์ถึงจะลองได้  ไม่มีพันธุ์ก็ข้ามก้อนนั้นไป
local SHAPES = {
    -- ยืนยันจาก JavaDocs  ลองก่อนทุกอย่าง
    { id = "cell,x,y,z,type,AnimalBreed", needObj = true,
      go = function(cell, x, y, z, t, b) return addAnimal(cell, x, y, z, t, b) end },

    { id = "cell,x,y,z,type,AnimalBreed,skeleton=false", needObj = true,
      go = function(cell, x, y, z, t, b) return addAnimal(cell, x, y, z, t, b, false) end },

    { id = "cell,x,y,z,type,breed", needBreed = true,
      go = function(cell, x, y, z, t, b) return addAnimal(cell, x, y, z, t, b) end },

    { id = "cell,x,y,z,type,breed,skeleton=false", needBreed = true,
      go = function(cell, x, y, z, t, b) return addAnimal(cell, x, y, z, t, b, false) end },

    -- ไม่รู้จักพันธุ์เลย  ส่งสตริงว่างไปเพื่อให้ arity ครบหก
    { id = "cell,x,y,z,type,breed=''",
      go = function(cell, x, y, z, t) return addAnimal(cell, x, y, z, t, "") end },

    -- รูปแบบของ 0.6.16  บิลด์นี้ปฏิเสธ แต่บิลด์อื่นอาจรับ  เก็บไว้ท้ายสุด
    { id = "cell,x,y,z,type",
      go = function(cell, x, y, z, t) return addAnimal(cell, x, y, z, t) end },

    -- เผื่อว่ามันรับช่องตรง ๆ ไม่ใช่ cell + พิกัด
    { id = "square,type,breed", needBreed = true, square = true,
      go = function(sq, t, b) return addAnimal(sq, t, b) end },

    { id = "square,type", square = true,
      go = function(sq, t) return addAnimal(sq, t) end },

    -- skeleton เป็นสตริง แทนที่จะเป็น boolean
    { id = "cell,x,y,z,type,breed,skeleton=''", needBreed = true,
      go = function(cell, x, y, z, t, b) return addAnimal(cell, x, y, z, t, b, "") end },

    -- ไม่ส่ง cell เลย  บางโกลบอลของ PZ หาเซลล์เอง
    { id = "x,y,z,type,breed", needBreed = true, noCell = true,
      go = function(x, y, z, t, b) return addAnimal(x, y, z, t, b) end },

    { id = "x,y,z,type", noCell = true,
      go = function(x, y, z, t) return addAnimal(x, y, z, t) end },
}

-- ==============================================================================
-- ทางที่สอง: สร้างจากคลาสเอง  (0.6.19)
--
-- ผลสำรวจจากเซิร์ฟจริงบอกว่า **IsoAnimal = table** ไม่ใช่ MISSING
-- แปลว่า PZ เปิดคลาสนี้ให้ Lua เห็น และคลาสที่ Lua เห็นมักเรียก .new() ได้
-- ส่วน addAnimal มีจริง (= function) แต่ยังไม่มีอาร์ริตี้ไหนที่ตรง
--
-- ลองทางนี้หลังจาก addAnimal หมดทางแล้ว  ไม่ใช่ก่อน
-- เพราะ addAnimal เป็นทางที่เอกสารระบุ และถ้ามันได้ มันจะจัดการเรื่องลงทะเบียน
-- สัตว์เข้าโลกให้ครบกว่าการสร้างออบเจกต์เองแน่นอน
local CLASS_SHAPES = {
    { id = "IsoAnimal.new(cell,x,y,z,type)",
      go = function(cell, x, y, z, t) return IsoAnimal.new(cell, x, y, z, t) end },
    { id = "IsoAnimal.new(cell,x,y,z,type,breed)", needBreed = true,
      go = function(cell, x, y, z, t, b) return IsoAnimal.new(cell, x, y, z, t, b) end },
    { id = "IsoAnimal.new(square,type)", square = true,
      go = function(sq, t) return IsoAnimal.new(sq, t) end },
    { id = "IsoAnimal.new(square,type,breed)", needBreed = true, square = true,
      go = function(sq, t, b) return IsoAnimal.new(sq, t, b) end },
}

-- ------------------------------------------------------------------------------
-- บิลด์นี้มีอะไรให้เราใช้บ้าง  (0.6.18)
--
-- ห้าแบบแรกล้มหมดบนเซิร์ฟจริง แปลว่าเราเดาผิดที่ "ลายเซ็น" หรือผิดที่ "ชื่อ"
-- สองอย่างนี้แยกกันไม่ออกจากข้อความ error อันเดียว  จึงต้องถามตรง ๆ ว่า
-- **เอนจินตัวนี้มีชื่ออะไรอยู่จริงบ้าง** แล้วรายงานกลับไปให้คนที่อ่านได้
--
-- ไม่เดาแทนผู้ใช้ ไม่สรุปแทนตัวเอง  รายงานสิ่งที่เห็นแล้วให้คนตัดสิน
-- **อ่านชื่อตรง ๆ ไม่ผ่าน _G**  Kahlua ของ PZ ไม่รับประกันว่ามี _G ให้ใช้
-- และการอ่านโกลบอลที่ไม่มีอยู่ใน Lua คืนค่า nil เฉย ๆ ไม่ได้ error
-- เขียนยาวกว่าแต่ทำงานได้จริงทุกบิลด์ (lint กฎ 10 ค้าน _G ให้ตั้งแต่แรกแล้ว)
local PROBE_NAMES = {
    { "addAnimal",                function() return addAnimal end },
    { "createAnimal",             function() return createAnimal end },
    { "spawnAnimal",              function() return spawnAnimal end },
    { "addAnimalDebug",           function() return addAnimalDebug end },
    { "getAnimal",                function() return getAnimal end },
    { "removeAnimal",             function() return removeAnimal end },
    { "getAllAnimalsDefinitions", function() return getAllAnimalsDefinitions end },
    { "getAnimalChunk",           function() return getAnimalChunk end },
    { "getHutch",                 function() return getHutch end },
    { "AnimalDefinitions",        function() return AnimalDefinitions end },
    { "IsoAnimal",                function() return IsoAnimal end },
    { "AnimalPopulationManager",  function() return AnimalPopulationManager end },
    { "getCell",                  function() return getCell end },
    { "addVehicleDebug",          function() return addVehicleDebug end },
}

-- ==============================================================================
-- สายพันธุ์เก็บไว้ที่ไหน — ยังไม่รู้ และเดาไปสองรอบแล้ว  (0.6.19)
--
-- ผลสำรวจจากเซิร์ฟบอกว่า `AnimalDefinitions = table` (ตาราง Lua ธรรมดา)
-- และชนิดอ่านได้ครบ (ดรอปดาวน์ขึ้น boar/buck/bull/chick/cockerel/cow)
-- แต่ `breeds tried=0` ทุกครั้ง แปลว่าสายพันธุ์ **ไม่ได้อยู่ใต้คีย์ชื่อ breeds**
--
-- เลิกเดาชื่อคีย์  **ดัมป์ชื่อคีย์จริงออกมาดู** แล้วรอบเดียวจะรู้คำตอบ
-- นี่คือวิธีเดียวกับที่ปิดเรื่องรายชื่อรถใน 0.6.11 และรายชื่อสัตว์ใน 0.6.16
local function keyDump(t, label, out, depth)
    out[#out + 1] = label .. "  (" .. type(t) .. ")"
    if type(t) ~= "table" then return end

    local n = 0
    for k, v in pairs(t) do
        n = n + 1
        if n > 25 then
            out[#out + 1] = "    ... more keys not listed"
            break
        end
        local tv = type(v)
        local extra = ""
        if tv == "string" then extra = " = " .. tostring(v):sub(1, 40)
        elseif tv == "table" then
            local cnt = 0
            for _ in pairs(v) do cnt = cnt + 1 end
            extra = "  (" .. cnt .. " keys)"
        end
        out[#out + 1] = "    " .. tostring(k) .. " : " .. tv .. extra

        -- ลงลึกหนึ่งชั้นสำหรับก้อนที่ชื่อส่อว่าเป็นสายพันธุ์
        if depth and depth > 0 and tv == "table"
           and tostring(k):lower():find("breed", 1, true) then
            keyDump(v, "      " .. tostring(k), out, depth - 1)
        end
    end
end

local function probeLines()
    local out = {}
    for _, row in ipairs(PROBE_NAMES) do
        local ok2, v = pcall(row[2])
        local t = ok2 and type(v) or "?"
        if t == "nil" then t = "MISSING" end
        out[#out + 1] = "  " .. row[1] .. "  =  " .. t
    end
    return out
end

-- รูปแบบที่บิลด์นี้รับ  จำไว้หลังเจอครั้งแรก จะได้ไม่ต้องไล่ใหม่ทุกครั้ง
local SHAPE_OK   = nil
local SHAPE_SEEN = false

-- พันธุ์ที่จะลองส่งไป  เรียงตามลำดับที่ควรลอง
--
--   1. พันธุ์ที่แอดมินระบุ  ของที่คนเลือกเองต้องได้ลองก่อนเสมอ
--   2. พันธุ์แรกที่เกมบอกว่ามีจริงสำหรับชนิดนั้น
--
-- ข้อสองไม่ใช่ของฟุ่มเฟือย  ม็อดสัตว์ถูกถอดออกจากเซิร์ฟได้ แล้วใบที่ขายไปแล้ว
-- จะชี้ไปที่พันธุ์ที่ไม่มีอยู่อีกต่อไป  **ล้มทั้งใบเพราะชื่อพันธุ์ = คนจ่ายเงินแล้ว
-- ไม่ได้สัตว์เพราะตัวอักษรไม่กี่ตัว**  สัตว์ที่ได้พันธุ์ไม่ตรงยังเป็นสัตว์
--
-- ส่งสตริงว่างเป็นทางสุดท้ายเท่านั้น (อยู่ในตาราง SHAPES) เพราะ overload
-- ที่ไม่มีพันธุ์ไม่มีอยู่จริงบนบิลด์ 42.20
-- ==============================================================================
-- **"Full breed ID" ของ B42 คือชนิดต่อท้ายด้วยพันธุ์ ติดกันไปเลย**  (0.6.18)
--
-- ตารางจากวิกิที่เจ้าของเซิร์ฟส่งมา:
--
--   Name                  Breed             Stage   Full breed ID
--   Leghorn Chick         Leghorn           Baby    chickleghorn
--   Rhode Island Red Hen  Rhode Island Red  Female  henrhodeisland
--   Leghorn Cockerel      Leghorn           Male    cockerelleghorn
--
-- อ่านได้สามข้อ และทั้งสามข้อสำคัญ:
--   1. "ชนิด" คือ chick / hen / cockerel — **แยกตามช่วงวัยและเพศ** ไม่ใช่ "chicken"
--   2. พันธุ์คือ leghorn / rhodeisland — ตัวเล็ก ไม่มีเว้นวรรค
--      และ "Rhode Island Red" ตัดเหลือ "rhodeisland" ไม่ใช่ "rhodeislandred"
--   3. ไอดีเต็ม = ชนิด .. พันธุ์ ติดกัน ไม่มีตัวคั่น
--
-- เรายังไม่รู้ว่า addAnimal อยากได้ "พันธุ์" หรือ "ไอดีเต็ม"
-- **จึงลองทั้งสองแบบ แทนที่จะเลือกข้างแล้วหวัง**
-- ==============================================================================
local function breedsToTry(typ, breed)
    local out, seen = {}, {}
    local function add(b)
        b = tostring(b or "")
        if b ~= "" and not seen[b] then seen[b] = true; out[#out + 1] = b end
    end

    -- ทุกพันธุ์ที่รู้จัก ใส่ทั้งรูปที่อ่านมาได้และรูป "ไอดีเต็ม"
    local function addAll(b)
        if not b or b == "" then return end
        add(b)

        -- ตัวเล็กไม่มีอักขระพิเศษ  "Rhode Island Red" -> "rhodeislandred"
        local flat = tostring(b):lower():gsub("[^%w]", "")
        add(flat)

        -- ไอดีเต็ม = ชนิด .. พันธุ์  ถ้าพันธุ์ยังไม่ได้ขึ้นต้นด้วยชนิดอยู่แล้ว
        if flat ~= "" and flat:sub(1, #typ) ~= typ then add(typ .. flat) end
    end

    addAll(breed)

    build()
    for _, r in ipairs(CATALOG) do
        local t, b = splitId(r.id)
        if t == typ then addAll(b) end
    end
    return out
end
local function spawn(petId, sq, player)
    if type(addAnimal) ~= "function" then
        return nil, KR.L("บิลด์นี้เสกสัตว์จาก Lua ไม่ได้",
                         "this build cannot spawn animals from Lua")
    end

    local typ, breed = splitId(petId)
    if not typ then return nil, "this slip does not name an animal" end

    local cell = (type(getCell) == "function") and getCell() or nil
    if cell == nil then
        return nil, KR.L("เข้าถึงโลกไม่ได้ตอนนี้", "the world is not available right now")
    end

    local okX, sx = pcall(function() return sq:getX() end)
    local okY, sy = pcall(function() return sq:getY() end)
    local okZ, sz = pcall(function() return sq:getZ() end)
    if not okX or not okY then
        return nil, KR.L("อ่านพิกัดช่องนั้นไม่ได้", "could not read that tile's position")
    end
    -- JavaDocs ระบุว่า x/y/z เป็น int  ปัดก่อนส่งเพื่อไม่ต้องพึ่งการแปลงของ Kahlua
    sx = math.floor(sx)
    sy = math.floor(sy)
    local z = math.floor((okZ and sz) or 0)

    local breeds = breedsToTry(typ, breed)

    -- รูปแบบที่เคยสำเร็จมาก่อน ลองก่อนเสมอ  ไม่สำเร็จค่อยไล่ใหม่ทั้งชุด
    -- (บิลด์เปลี่ยนได้ตอนอัปเดตเกม  การจำไว้ตลอดกาลคือการจำของที่หมดอายุแล้ว)
    local order = {}
    if SHAPE_OK then order[#order + 1] = SHAPE_OK end
    for _, sh in ipairs(SHAPES) do
        if sh ~= SHAPE_OK then order[#order + 1] = sh end
    end

    -- กางเป็นรายการความพยายามให้ครบก่อนลงมือ  รูปแบบที่ต้องมีพันธุ์ถูกลองซ้ำ
    -- ทุกพันธุ์ที่มีให้ลอง  รูปแบบที่ไม่ต้องมีพันธุ์ลองครั้งเดียวพอ
    --
    -- **จำนวนครั้งที่จะลอง ต้องเป็นสิ่งที่เราเขียนไว้ ไม่ใช่สิ่งที่เราหวัง**
    -- ทางของคลาสต่อท้าย  ลองหลัง addAnimal หมดทางแล้ว
    if type(IsoAnimal) == "table" then
        for _, sh in ipairs(CLASS_SHAPES) do order[#order + 1] = sh end
    end

    -- ออบเจกต์ AnimalBreed  หาครั้งเดียวพอ  ใช้ได้ทุกรูปแบบที่ต้องการมัน
    local bObj, bWhy = breedObj(typ, breeds[1])

    local plan = {}
    for _, sh in ipairs(order) do
        if sh.needObj then
            if bObj ~= nil then
                plan[#plan + 1] = { sh = sh, obj = bObj }
            else
                plan[#plan + 1] = { sh = sh, skip = tostring(bWhy) }
            end
        elseif sh.needBreed then
            for _, b in ipairs(breeds) do
                plan[#plan + 1] = { sh = sh, breed = b }
            end
            if #breeds == 0 then
                plan[#plan + 1] = { sh = sh, skip = "no breed known" }
            end
        else
            plan[#plan + 1] = { sh = sh }
        end
    end

    local tried = {}
    for _, a in ipairs(plan) do
        local sh, b = a.sh, (a.obj or a.breed)
        local label = sh.id .. (a.breed and ("  breed=" .. a.breed) or "")

        if a.skip then
            tried[#tried + 1] = label .. " [skipped: " .. a.skip .. "]"
        else
            local okRun, got
            if sh.square then
                okRun, got = pcall(sh.go, sq, typ, b)
            elseif sh.noCell then
                okRun, got = pcall(sh.go, sx, sy, z, typ, b)
            else
                okRun, got = pcall(sh.go, cell, sx, sy, z, typ, b)
            end

            if okRun and got ~= nil then
                if SHAPE_OK ~= sh or not SHAPE_SEEN then
                    SHAPE_OK, SHAPE_SEEN = sh, true
                    print("[Kuraya] pets: addAnimal works on this build as  " .. sh.id)
                end
                return got
            end

            -- **pcall ผ่านแต่ได้ nil ก็คือไม่เกิด**  ต้องนับเป็นล้มเหลวเหมือนกัน
            -- **ห้ามตัดข้อความใน log**  brief() มีไว้สำหรับจอ ไม่ใช่สำหรับ log
            -- รอบก่อนตัดที่ 110 ตัวอักษร แล้วส่วนที่บอก "พารามิเตอร์ที่มันอยากได้"
            -- ถูกตัดหายไปพอดี ซึ่งเป็นข้อมูลชิ้นเดียวที่เราต้องการจริง ๆ
            tried[#tried + 1] = label .. " -> " ..
                (okRun and "returned nil" or tostring(got))
        end
    end

    -- ล้มทุกทาง  พิมพ์ให้ครบว่าไล่อะไรไปบ้างและเอนจินตอบว่าอะไร
    -- บรรทัดเดียวนี้คือสิ่งที่จะบอกเราว่าลายเซ็นจริงคืออะไร ในรอบถัดไป
    local head = "addAnimal refused every shape for '" .. tostring(petId) ..
                 "'  (type=" .. tostring(typ) .. "  breeds tried=" .. #breeds .. ")"

    print("[Kuraya] pets: " .. head)
    for _, t in ipairs(tried) do print("[Kuraya] pets:   " .. t) end

    -- ส่งไปเข้า console ของคนที่กดด้วย ถ้าเขาเป็นแอดมิน  (0.6.18)
    -- **บรรทัดที่พิมพ์อยู่ฝั่งเซิร์ฟอย่างเดียว คือบรรทัดที่ไม่มีใครได้อ่าน**
    if player and type(S.isStaff) == "function" and S.isStaff(player)
       and type(sendServerCommand) == "function" then
        local lines = { head, "", "shapes tried:" }
        for _, t in ipairs(tried) do lines[#lines + 1] = "  " .. t end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "what this build actually has:"
        for _, l in ipairs(probeLines()) do lines[#lines + 1] = l end

        -- ที่เก็บสายพันธุ์  ยังหาไม่เจอ จึงต้องดูชื่อคีย์จริง
        lines[#lines + 1] = ""
        lines[#lines + 1] = "where the breeds might be:"
        if type(AnimalDefinitions) == "table" then
            keyDump(AnimalDefinitions, "AnimalDefinitions", lines, 0)
            local animals = AnimalDefinitions.animals
            if type(animals) == "table" then
                keyDump(animals[typ], "AnimalDefinitions.animals." .. tostring(typ),
                        lines, 1)
            else
                keyDump(AnimalDefinitions[typ], "AnimalDefinitions." .. tostring(typ),
                        lines, 1)
            end
        end
        if type(getAllAnimalsDefinitions) == "function" then
            local okD, d = pcall(getAllAnimalsDefinitions)
            if okD and type(d) == "table" then
                local src = (type(d.animals) == "table") and d.animals or d
                keyDump(src[typ], "getAllAnimalsDefinitions()." .. tostring(typ), lines, 1)
            end
        end
        pcall(sendServerCommand, player, KR.MODULE, KR.CMD.DIAG,
              { title = "pets: addAnimal probe", lines = lines })
    end

    -- ชื่อสัตว์ต้องอยู่ในข้อความบนจอ  "เสกไม่ได้" เฉย ๆ ไม่บอกว่าใบไหนมีปัญหา
    -- คนที่มีใบหลายใบในกระเป๋าจะไม่รู้เลยว่าต้องไปดูตัวไหน
    return nil, KR.L("เสก ", "Could not spawn ") .. tostring(S.petLabel(petId)) ..
                KR.L(" ไม่ได้ - เอนจินไม่รับวิธีไหนเลย  แอดมินดู console ของตัวเองได้",
                     " - this build refused every way we know." ..
                     " Admins: the details are in your own console now.")
end

-- ------------------------------------------------------------------------------
-- แต่งตัวสัตว์ที่เพิ่งเกิด
--
-- ทุกขั้นห่อ pcall แยกกัน  ทำข้อไหนไม่ได้ก็เสียแค่ข้อนั้น
-- **ห้ามให้ขั้นตอนแต่งตัวทำให้ "สัตว์ที่เกิดแล้ว" กลายเป็นความล้มเหลว**
-- (บทเรียนตรง ๆ จาก makeFresh ของรถใน 0.6.13)
-- ------------------------------------------------------------------------------
local SETTLE_SEEN = false

local function settle(player, animal, label)
    local did = {}

    -- สัตว์ที่ซื้อมาไม่ใช่สัตว์ป่า  ตัวที่ยังถูกนับเป็นสัตว์ป่าจะหนีและถูกล่าได้
    if U_hasMethod(animal, "setWild") then
        if pcall(function() animal:setWild(false) end) then did[#did + 1] = "tame" end
    end

    -- ตั้งชื่อให้ตรงกับที่เขียนบนใบ  ชื่อเป็นของวานิลลา รอด save/reload เอง
    if KR.svBool("PetNameFromSlip", true) and U_hasMethod(animal, "setCustomName") then
        local nm = KR.trunc(tostring(label or ""), 32)
        if nm ~= "" and pcall(function() animal:setCustomName(nm) end) then
            did[#did + 1] = "name"
        end
    end

    -- สัตว์ที่มาถึงพร้อมหิวจัดคือสัตว์ที่จะตายก่อนคนซื้อหาอาหารทัน
    for _, m in ipairs({ "setHunger", "setThirst", "setStress" }) do
        if U_hasMethod(animal, m) then
            if pcall(function() animal[m](animal, 0) end) then did[#did + 1] = m end
        end
    end

    -- ของแถมที่เจ้าของเซิร์ฟตั้งไว้เอง  ช่องเดียวกับของรถ คนละชื่อ
    local extra = KR.svStr("PetExtraItem", "")
    if extra ~= "" then
        local n = math.max(1, math.min(20, KR.svInt("PetExtraCount", 1) or 1))
        local made, err = S.giveItems(player, extra, n)
        if made >= n then
            did[#did + 1] = "extra:" .. extra .. "x" .. n
        else
            print("[Kuraya] pets: extra item '" .. extra .. "' could not be given -> " ..
                  tostring(err or "partial"))
        end
    end

    if not SETTLE_SEEN then
        SETTLE_SEEN = true
        print("[Kuraya] pets: settle steps that worked on this build: " ..
              (#did > 0 and table.concat(did, ", ") or "none - animals spawn as the engine makes them"))
    end
end

-- ==============================================================================
-- ผู้เล่นกดแกะใบ
-- ==============================================================================
function S.petUnpack(player, args)
    local k = key(player); if not k then return end

    local it, inv = findSlip(player, args and args.item)
    if not it then
        return alert(player, "That slip is not in your inventory any more.", "bad")
    end

    local okMd, md = pcall(function() return it:getModData() end)
    local petId = (okMd and type(md) == "table") and tostring(md.krPet or "") or ""
    if petId == "" then
        return alert(player, "This slip does not say which animal it is for." ..
                             " Show it to an admin.", "bad")
    end

    local sq, why = spotFor(player)
    if not sq then
        return alert(player, why or "No room here.", "warn")
    end

    -- ---- เอาใบออกก่อน  แล้วค่อยเสก -------------------------------------------
    -- เสกก่อนแล้วค่อยเอาใบออก = มีหนึ่งเฟรมที่ทั้งสัตว์และใบอยู่ด้วยกัน
    -- คนที่กดรัว ๆ ได้สองตัวจากใบเดียว  ทางนี้แย่ที่สุดคือใบหายแล้วสัตว์ไม่มา
    -- ซึ่งเราคืนใบให้ทันทีในบรรทัดถัดไป
    if type(sendRemoveItemFromContainer) == "function" then
        pcall(sendRemoveItemFromContainer, inv, it)
    end
    pcall(function() inv:Remove(it) end)

    local label = (okMd and md.krPetName) or S.petLabel(petId)

    local animal, err = spawn(petId, sq, player)
    if not animal then
        local back = makeSlip(player, petId, label)
        print("[Kuraya] pets: " .. tostring(k) .. " could not unpack '" .. petId ..
              "' -> " .. tostring(err) .. (back and "  (slip returned)" or "  !! SLIP LOST"))
        -- บนจอเอาแบบสั้น  ตัวเต็มอยู่ใน console บรรทัดข้างบนนี้แล้ว
        return alert(player, brief(err) ..
                     (back and " Your slip was returned." or
                              " YOUR SLIP COULD NOT BE RETURNED - tell an admin now."), "bad")
    end

    settle(player, animal, label)

    print("[Kuraya] pets: " .. tostring(k) .. " unpacked " .. petId)
    alert(player, KR.L("สัตว์ของคุณอยู่ตรงหน้าแล้ว: ", "Your animal is right in front of you: ") ..
                  tostring(label), "good")
end

print("[Kuraya] KR_Pets ready")
return true
