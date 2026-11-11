-- ==============================================================================
-- AKA_Menu.lua — เมนูคลิกขวา "AKA Mod" อันเดียวที่ทุกม็อดของ AKA ใช้ร่วมกัน
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
--
-- ==============================================================================
-- ปัญหาที่ไฟล์นี้แก้
--
-- เจ้าของเซิร์ฟถ่ายคลิกขวามาให้ดู  ในเมนูเดียวมี
--     AKA Mod   >      (Kuraya)
--     AKA MOD   >      (อีกม็อด  ตัวพิมพ์ใหญ่)
--     ...
--     AKA Mod   >      (ม็อดที่สาม)
-- สามแถวที่ชื่อเหมือนกัน  ไม่มีใครเดาถูกว่าของที่ต้องการอยู่อันไหน
--
-- ต้นเหตุคือทุกม็อดแตะ ISContextMenu ตรง ๆ กันเอง
--   * ม็อดที่ไม่มองหาของเดิมเลย -> สร้างแถวใหม่ทุกครั้ง
--   * ม็อดที่มองหาแต่เทียบตัวพิมพ์ตรง ๆ -> "AKA MOD" ไม่เคยแมตช์ "AKA Mod"
--   * ลำดับโหลดคุมไม่ได้ -> ม็อดที่รันก่อนเป็นคนสร้าง คนอื่นต้องไปเจอให้ได้
--
-- **ทางแก้ไม่ใช่ให้ทุกม็อดค้นหาเก่งขึ้น  แต่คือให้ไม่มีม็อดไหนสร้างเมนูเอง**
-- ทุกม็อดลงทะเบียนแถวของตัวเองไว้ที่นี่  แล้วไฟล์นี้วาดเมนูให้ครั้งเดียว
-- จะมีม็อด AKA กี่ตัวก็ได้ผลลัพธ์เป็นแถว "AKA Mod" แถวเดียวเสมอ
--
-- ==============================================================================
-- วิธีใช้จากม็อดอื่น  (สามบรรทัด)
--
--     require("AKA/AKA_Menu")
--
--     AKAMenu.add("kuraya", 10, function(player, m)
--         m:option("Fresh Market : register a stall here", function() ... end)
--     end)
--
--   id     ชื่อม็อด  ลงทะเบียนซ้ำด้วย id เดิม = แทนของเดิม (โหลดสองรอบไม่พัง)
--   order  เลขน้อยอยู่บน  เท่ากันเรียงตาม id  ลำดับจึงคงที่ทุกเฟรม
--   m      ตัวเก็บแถว  ดูเมธอดข้างล่าง
--
--     m:option(label, onClick)       แถวกดได้
--     m:option(label, nil)           แถวที่กดไม่ได้ (ป้ายข้อมูล)
--     m:optionIf(cond, label, fn)    ใส่เฉพาะเมื่อ cond เป็นจริง
--     m:submenu(label)               คืนตัวเก็บอีกชั้น  ซ้อนได้
--
-- ห้ามเรียก context:addOption("AKA Mod", ...) เองอีก  นั่นคือสิ่งที่พังมาตลอด
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- ยามโหลดซ้ำ
--
-- ไฟล์นี้ถูกส่งไปพร้อมม็อด AKA ทุกตัว  เครื่องที่ลงสามม็อดจึงมีสามก๊อป
-- require() แคชตามชื่อ ปกติจะรันก๊อปเดียว  แต่ B42 โหลด media จาก common/ กับ
-- โฟลเดอร์บิลด์ด้วย และม็อดบางตัวอาจ dofile เอง  ยามนี้จึงต้องมี
--
-- **สำคัญ: ห้ามรีเซ็ตตารางที่ลงทะเบียนไว้แล้ว**  ก๊อปที่สองที่ล้างของทิ้ง
-- คือก๊อปที่ทำให้ม็อดที่ลงทะเบียนไปก่อนหน้าหายไปทั้งตัว
-- ------------------------------------------------------------------------------
AKAMenu = AKAMenu or {}

AKAMenu.NAME     = "AKA Mod"    -- ชื่อเดียวของทั้งตระกูล  ห้ามม็อดไหนเปลี่ยน
AKAMenu.VERSION  = "1.0.0"
AKAMenu.parts    = AKAMenu.parts or {}
AKAMenu.order    = AKAMenu.order or {}

if not AKAMenu.__printed then
    AKAMenu.__printed = true
    print("[AKA] AKA_Menu  v" .. AKAMenu.VERSION .. "  (shared right-click menu)")
end

-- ------------------------------------------------------------------------------
-- ลงทะเบียน
-- ------------------------------------------------------------------------------
function AKAMenu.add(id, order, fn)
    id = tostring(id or "")
    if id == "" or type(fn) ~= "function" then return false end
    if AKAMenu.parts[id] == nil then
        AKAMenu.order[#AKAMenu.order + 1] = id
    end
    AKAMenu.parts[id] = { order = tonumber(order) or 100, fn = fn }
    return true
end

function AKAMenu.remove(id)
    AKAMenu.parts[tostring(id or "")] = nil
end

-- ------------------------------------------------------------------------------
-- ตัวเก็บแถว
--
-- ทำไมต้องเก็บก่อน ไม่วาดลง ISContextMenu ตรง ๆ
--   1. ต้องรู้ให้ได้ก่อนว่า "มีแถวไหม" ถึงจะตัดสินใจได้ว่าจะสร้างแถวแม่หรือเปล่า
--      เมนูแม่ที่กางออกมาแล้วว่างเปล่าอ่านว่า "ม็อดพัง" ซึ่งแย่กว่าไม่มีเมนูเลย
--   2. ม็อดที่พังกลางทางต้องไม่ลากม็อดอื่นพังตาม  เก็บก่อน = pcall ล้อมได้ทีละม็อด
--   3. เรียงลำดับได้หลังเก็บครบ  วาดไปเรียงไปทำไม่ได้
-- ------------------------------------------------------------------------------
local Bag = {}
Bag.__index = Bag

local function newBag()
    return setmetatable({ rows = {} }, Bag)
end

function Bag:option(label, onClick, opts)
    label = tostring(label or "")
    if label == "" then return self end
    local row = { label = label, click = (type(onClick) == "function") and onClick or nil }
    if type(opts) == "table" then
        row.off  = opts.disabled and true or nil
        row.note = opts.note
    end
    self.rows[#self.rows + 1] = row
    return self
end

function Bag:optionIf(cond, label, onClick, opts)
    if cond then return self:option(label, onClick, opts) end
    return self
end

function Bag:submenu(label)
    label = tostring(label or "")
    if label == "" then return newBag() end        -- ทิ้งแบบไม่พัง
    local kid = newBag()
    self.rows[#self.rows + 1] = { label = label, bag = kid }
    return kid
end

-- ไม่มีเมธอดชื่อ count() โดยตั้งใจ
--
-- lint กฎ 15 ฟ้องทันทีที่เขียน: ในม็อดนี้มี `e.count = ...` เป็นฟิลด์ข้อมูลอยู่แล้ว
-- (จำนวนชิ้นต่อรายการใน KR_Server)  เมธอดที่ชื่อซ้ำกับฟิลด์ที่ใช้กันทั่วโค้ด
-- คือกับดักที่รอวันมีคนเขียน bag.count = 3 แล้วเมธอดตายถาวร
-- ใช้ #bag.rows ตรง ๆ  สั้นกว่า ชัดกว่า และไม่มีชื่อให้ชนกับใคร

-- ------------------------------------------------------------------------------
-- เก็บแถวจากทุกม็อดที่ลงทะเบียนไว้
--
-- ม็อดหนึ่งตัวระเบิดต้องไม่ทำให้เมนูทั้งอันหาย  pcall ทีละตัว แล้วพิมพ์ชื่อคนผิด
-- ลงคอนโซล  ไม่ใช่กลืนเงียบ ๆ
-- ------------------------------------------------------------------------------
function AKAMenu.collect(player)
    local ids = {}
    for i = 1, #AKAMenu.order do
        local id = AKAMenu.order[i]
        if AKAMenu.parts[id] then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local pa, pb = AKAMenu.parts[a], AKAMenu.parts[b]
        if pa.order ~= pb.order then return pa.order < pb.order end
        return a < b
    end)

    local bag = newBag()
    for i = 1, #ids do
        local id = ids[i]
        local part = AKAMenu.parts[id]
        local sub = newBag()
        local ok, err = pcall(part.fn, player, sub)
        if not ok then
            print("[AKA] menu part '" .. id .. "' failed -> " .. tostring(err))
        else
            for j = 1, #sub.rows do
                bag.rows[#bag.rows + 1] = sub.rows[j]
            end
        end
    end
    return bag
end

-- ------------------------------------------------------------------------------
-- หาแถวแม่ที่มีอยู่แล้ว  เทียบแบบ **ไม่สนตัวพิมพ์**
--
-- "AKA MOD" กับ "AKA Mod" คือเมนูเดียวกันในสายตาคน  getOptionFromName ของ PZ
-- เทียบตัวพิมพ์ตรง ๆ จึงมองไม่เห็นกัน แล้วเกิดสองแถว
-- อ่านจาก context.options โดยตรง เพราะเป็นทางเดียวที่เทียบแบบหลวมได้
-- ------------------------------------------------------------------------------
local function looksLikeOurs(name)
    local s = tostring(name or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return s:upper() == "AKA MOD"
end

local function findParent(context)
    if type(context) ~= "table" then return nil end
    local opts = context.options
    if type(opts) ~= "table" then return nil end
    for i = 1, #opts do
        local o = opts[i]
        if type(o) == "table" and looksLikeOurs(o.name) then return o end
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- วาดลง ISContextMenu จริง
-- ------------------------------------------------------------------------------
local function paint(context, menu, bag, player)
    for i = 1, #bag.rows do
        local row = bag.rows[i]
        if row.bag then
            local opt = menu:addOption(row.label, player, nil)
            local kid = ISContextMenu:getNew(menu)
            menu:addSubMenu(opt, kid)
            paint(context, kid, row.bag, player)
        else
            local opt = menu:addOption(row.label, player, row.click)
            if row.off and type(opt) == "table" then opt.notAvailable = true end
        end
    end
end

function AKAMenu.fill(playerNum, context, worldobjects, test)
    if test then return end
    if playerNum ~= 0 then return end
    if type(context) ~= "table" or type(context.addOption) ~= "function" then return end

    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player then return end

    local bag = AKAMenu.collect(player)
    -- ไม่มีแถวเลย = ไม่สร้างแม่  เมนูที่กางออกมาว่างเปล่าคือเมนูที่อ่านว่าพัง
    if #bag.rows == 0 then return end

    local parent = findParent(context)
    local menu
    if parent and parent.subOption and type(context.getSubMenu) == "function" then
        menu = context:getSubMenu(parent.subOption)
    end
    if type(menu) ~= "table" then
        parent = context:addOption(AKAMenu.NAME, player, nil)
        menu   = ISContextMenu:getNew(context)
        context:addSubMenu(parent, menu)
    end

    paint(context, menu, bag, player)
end

-- ------------------------------------------------------------------------------
-- ผูก event ครั้งเดียว  และผูก **ตอน OnGameStart ไม่ใช่ตอนโหลดไฟล์**
--
-- PZ เรียก handler ตามลำดับที่ถูกเพิ่มเข้าไป  ม็อดเกือบทุกตัวผูกตอนโหลดไฟล์
-- การผูกตอน OnGameStart จึงทำให้เราได้เป็นคนท้าย ๆ  ซึ่งแปลว่าถ้ามีม็อดที่ยัง
-- ไม่ได้แปลงมาสร้าง "AKA MOD" ไว้ก่อน เราจะ **เห็นมันและไปอาศัยแถวนั้น**
-- แทนที่จะสร้างแถวที่สองซ้อน
--
-- ผูกตอนโหลดไฟล์จะกลับกัน: เราสร้างก่อน แล้วม็อดที่ยังไม่แปลงมาสร้างซ้อนทีหลัง
-- ซึ่งเป็นภาพที่เจ้าของเซิร์ฟถ่ายมาพอดี
-- ------------------------------------------------------------------------------
if not AKAMenu.__installed then
    AKAMenu.__installed = true

    local function install()
        if AKAMenu.__bound then return end
        local ev = Events and Events.OnFillWorldObjectContextMenu
        if not ev or type(ev.Add) ~= "function" then return end
        AKAMenu.__bound = true
        ev.Add(function(...)
            local ok, err = pcall(AKAMenu.fill, ...)
            if not ok then print("[AKA] menu -> " .. tostring(err)) end
        end)
    end

    AKAMenu.install = install

    local gs = Events and Events.OnGameStart
    if gs and type(gs.Add) == "function" then
        gs.Add(function() pcall(install) end)
    else
        install()      -- บิลด์ที่ไม่มี event นั้น  ผูกทันทีดีกว่าไม่ผูกเลย
    end
end

return AKAMenu
