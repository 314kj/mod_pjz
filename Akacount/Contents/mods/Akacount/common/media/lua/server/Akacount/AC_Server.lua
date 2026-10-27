-- ==============================================================================
-- Akacount — server/Akacount/AC_Server.lua
-- OnClientCommand dispatch + การย้ายไอเทม (ฝาก/ถอนเงินสด)
-- ==============================================================================
--
-- กฎข้อเดียวที่ต้องจำ  (PZ-B42-MP-item-transfer-RULE.md)
--   เซิร์ฟเวอร์เป็นเจ้าของกระเป๋าผู้เล่น
--   ไคลเอนต์รายงานได้ว่าทำอะไรไป มีแต่เซิร์ฟเวอร์เท่านั้นที่ทำให้มันเป็นจริง
--
-- ที่นี่จึงไม่มี two-phase เลย เพราะไม่มีขั้นตอนไหนที่ไคลเอนต์ต้องขยับของเอง
-- ไคลเอนต์แค่ส่งจำนวนมา เซิร์ฟเวอร์ทำทั้งหมดจากสำเนาของตัวเอง
-- ==============================================================================
require("Akacount/AC_Const")
require("Akacount/AC_Util")
require("Akacount/AC_DB")
require("Akacount/AC_Ledger")
require("Akacount/AC_API")

local D, L, U = AC.db, AC.ledger, AC.util
local S = {}

local function alert(player, msg, tone)
    sendServerCommand(player, AC.MODULE, AC.CMD.ALERT, { msg = msg, tone = tone or "info" })
end

local function isAdmin(player)
    if not player then return false end
    local ok, lvl = pcall(function() return player:getAccessLevel() end)
    if not ok or not lvl then return false end
    lvl = tostring(lvl):lower()
    return lvl == "admin" or lvl == "overseer"
end

-- ------------------------------------------------------------------------------
-- ตู้ธนาคาร
--   ฝาก/ถอนเงินสดต้องอยู่ที่ตู้เท่านั้น เพราะไอเทมต้องมีจุดเปลี่ยนมือจริง
--   แอดมินลงทะเบียนตู้เก็บไว้ใน DB (x,y,z) แบบเดียวกับที่ AkaShop ลงทะเบียนตู้แคชเชียร์
-- ------------------------------------------------------------------------------
-- ระยะเป็น sandbox แล้ว  เจ้าของเซิร์ฟตั้งเองได้โดยไม่ต้องแก้โค้ด
-- อ่านสดทุกครั้ง ไม่ cache  แอดมินแก้ค่ากลางเซิร์ฟแล้วต้องมีผลทันที (เหตุผลเต็มอยู่ที่ U.opt)
-- วัดเป็นสี่เหลี่ยม (Chebyshev) ไม่ใช่ระยะตรง  "3 ช่องรอบ tile" ต้องหมายถึงมุมด้วย
function S.counterRange()
    local n = math.floor(tonumber(U.opt("CounterRange")) or 3)
    if n < 1 then n = 1 end
    if n > 20 then n = 20 end
    return n
end

function S.isAtCounter(player)
    if not player then return false end
    local db = D.get()
    db.counters = db.counters or {}
    local sq = player:getSquare()
    if not sq then return false end
    local r = S.counterRange()
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
    for _, c in pairs(db.counters) do
        if c.z == pz then
            local dx, dy = math.abs(c.x - px), math.abs(c.y - py)
            if dx <= r and dy <= r then return true end
        end
    end
    return false
end

-- ------------------------------------------------------------------------------
-- ไอเทม
-- ------------------------------------------------------------------------------
local function playerContainers(player)
    local out = {}
    local inv = player:getInventory()
    if inv then out[#out + 1] = inv end
    local worn = player:getWornItems()
    if worn then
        for i = 0, worn:size() - 1 do
            local w  = worn:get(i)
            local it = w and w:getItem()
            if it and it:IsInventoryContainer() then
                local c = it:getItemContainer()
                if c then out[#out + 1] = c end
            end
        end
    end
    return out
end

-- isEquipped() ครอบคลุมแค่ของในมือ เสื้อผ้าที่สวมอยู่ยังโผล่ในรายการกระเป๋าตามปกติ
-- คำตอบที่เชื่อถือได้มีทางเดียวคือถามรายการสวมใส่ของตัวละครเอง
local function isWorn(player, item)
    local worn = player:getWornItems()
    if not worn then return false end
    for i = 0, worn:size() - 1 do
        local w = worn:get(i)
        if w and w:getItem() == item then return true end
    end
    return false
end

-- ------------------------------------------------------------------------------
-- ปึกเงิน (Base.MoneyBundle = 100 ใบ)
--
-- ถามเกมก่อนว่ามีไอเทมนี้จริงไหม  ไม่มี = ระบบปึกปิดตัวเอง ใช้แบงก์ใบอย่างเดียว
-- จำเฉพาะคำตอบ "มี"  คำตอบ "ไม่มี" ถามใหม่ได้ เผื่อถูกถามก่อนสคริปต์โหลดครบ
-- FindItem ห่อ pcall ตามบทเรียน v0.2.8 (บางบิลด์โยนเมื่อชื่อแปลก)
-- ------------------------------------------------------------------------------
local _bundleOK = false
local function bundleOK()
    if _bundleOK then return true end
    if type(getScriptManager) ~= "function" then return false end
    local sm = getScriptManager()
    if not sm then return false end
    local ok, found = pcall(function() return sm:FindItem(AC.ITEM_BUNDLE) end)
    _bundleOK = (ok and found ~= nil) and true or false
    return _bundleOK
end
S.bundleOK = bundleOK

-- นับเงินสดทั้งตัว  คืน (มูลค่ารวมเป็นใบ, จำนวนใบ, จำนวนปึก)
-- นับทุกชิ้นรวม favorite  เป็นตัวเลขโชว์ในเมนู  ตัวที่ยึดจริงคือ cashPool ข้างล่าง
local function countCash(player)
    local loose, bundles = 0, 0
    local bOK = bundleOK()
    for _, c in ipairs(playerContainers(player)) do
        loose = loose + c:getItemCount(AC.ITEM_CASH)
        if bOK then bundles = bundles + c:getItemCount(AC.ITEM_BUNDLE) end
    end
    return loose + bundles * AC.BUNDLE_SIZE, loose, bundles
end

-- เงินสดที่ "ยึดได้จริง"  ไม่ติด favorite และไม่ได้สวมอยู่
local function poolOf(player, fullType, out)
    for _, c in ipairs(playerContainers(player)) do
        local items = c:getItemsFromType(fullType)
        if items and not items:isEmpty() then
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it and not it:isFavorite() and not isWorn(player, it) then
                    out[#out + 1] = { it = it, c = c }
                end
            end
        end
    end
    return out
end

local function removeRow(row)
    if sendRemoveItemFromContainer then sendRemoveItemFromContainer(row.c, row.it) end
    row.c:Remove(row.it)
    row.c:setDrawDirty(true)
end

-- สร้างไอเทมหนึ่งชิ้นเข้ากระเป๋า
-- instanceItem -> AddItem -> sendAddItemToContainer  ตามกฎ MP give ของโปรเจกต์
-- ไม่เรียก syncItemFields ตรงนี้แล้ว  ของที่ยังไม่ถึงมือไคลเอนต์ = แพ็กเก็ตที่หาเป้าไม่เจอ
local function addOne(inv, fullType)
    local item = instanceItem(fullType)
    if not item then return false end
    inv:AddItem(item)
    if sendAddItemToContainer then sendAddItemToContainer(inv, item) end
    return true
end

-- ไคลเอนต์สร้างไอเทมใน MP ไม่ได้เลย  ItemContainer ไม่มี addItemOnServer
-- n = มูลค่าเป็นใบ   asBundles = ทุก 100 ใบออกเป็นปึกเดียว
-- ถอน 5,000 เป็นใบ = 5,000 ไอเทม 5,000 แพ็กเก็ต  เป็นปึก = 50 ชิ้น
-- ปึกสร้างไม่ได้กลางทาง ส่วนที่เหลือตกเป็นแบงก์ใบ ไม่มีเงินหาย
local function giveCash(player, n, asBundles)
    local inv = player:getInventory()
    if not inv or n <= 0 then return 0 end
    local sm = getScriptManager()
    if not (sm and sm:FindItem(AC.ITEM_CASH)) then return 0 end
    local made, B = 0, AC.BUNDLE_SIZE
    if asBundles and bundleOK() then
        for _ = 1, math.floor(n / B) do
            if not addOne(inv, AC.ITEM_BUNDLE) then break end
            made = made + B
        end
    end
    while made < n do
        if not addOne(inv, AC.ITEM_CASH) then break end
        made = made + 1
    end
    return made
end

-- ------------------------------------------------------------------------------
-- ยึดเงินสดมูลค่า n ใบ  คืนมูลค่าที่ยึดได้จริง (หักเงินทอนแล้ว)
--
-- ใช้ปึกก่อนสำหรับหลักร้อย แล้วเติมด้วยแบงก์ใบ  ของในกระเป๋าหายน้อยชิ้นที่สุด
-- แบงก์ใบไม่พอเศษ -> แกะปึกเพิ่มอีกหนึ่งปึกแล้วทอนเป็นแบงก์ใบ
--   ฝาก 250  มีปึก 3 ไม่มีใบเลย  -> ยึด 3 ปึก (300) ทอน 50 ใบ  = ฝากเข้า 250 พอดี
-- ทอนไม่ได้ครบ (สร้างไอเทมไม่ได้) ส่วนที่ทอนไม่ได้ถูกนับเป็นเงินฝาก  ผู้เล่นไม่เสียอะไร
-- ------------------------------------------------------------------------------
local function takeCash(player, n)
    local B = AC.BUNDLE_SIZE
    local loose   = poolOf(player, AC.ITEM_CASH, {})
    local bundles = bundleOK() and poolOf(player, AC.ITEM_BUNDLE, {}) or {}

    local nb   = math.min(#bundles, math.floor(n / B))
    local rest = n - nb * B
    local nl   = math.min(#loose, rest)
    rest = rest - nl
    local change = 0
    if rest > 0 and #bundles > nb then
        nb = nb + 1
        change = B - rest
    end

    for i = 1, nb do removeRow(bundles[i]) end
    for i = 1, nl do removeRow(loose[i]) end

    local got = nb * B + nl
    if change > 0 then got = got - giveCash(player, change, false) end
    return got
end

-- ------------------------------------------------------------------------------
-- ตัวช่วยเกี่ยวกับไอเทม  ต้องประกาศตรงนี้ ก่อน S.sync
--
-- กับดักของ Lua: local function ที่ประกาศ "ทีหลัง" closure ที่เรียกมัน
-- จะถูก resolve เป็น global ที่เป็น nil แล้วพังตอนรัน ไม่ใช่ตอนคอมไพล์
-- (Traka v3.5 เคยเจอกับ adminOnly มาแล้วครั้งหนึ่ง)
-- ------------------------------------------------------------------------------
local function findItem(player, fullType)
    for _, c in ipairs(playerContainers(player)) do
        local items = c:getItemsFromType(fullType)
        if items and not items:isEmpty() then
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it and not isWorn(player, it) then return it, c end
            end
        end
    end
    return nil, nil
end

-- ------------------------------------------------------------------------------
-- sync
-- ถ้าเซิร์ฟไม่ตั้งใจให้เขาเห็น เซิร์ฟไม่ส่ง ไม่ใช่ส่งไปแล้วให้ไคลเอนต์ซ่อน
-- ห้ามเรียก ModData.transmit() กับ Akacount_DB เด็ดขาด
-- คำสั่งเดียวนั้นเท่ากับส่งยอดเงินของทุกคนบนเซิร์ฟไปให้ทุกเครื่อง
-- ------------------------------------------------------------------------------
-- ถือบัตรของตัวเองอยู่ไหม
--
-- "ถือบัตรอยู่" ไม่พอ  ต้องเป็นบัตรที่ออกให้เราด้วย
-- บัตรของคนอื่นที่เก็บได้จากพื้นใช้ไม่ได้ และต้องไม่ทำให้ปุ่ม "ขอบัตร" หายไป
function S.holdsOwnCard(player)
    local k = U.key(player); if not k then return false end
    for _, c in ipairs(playerContainers(player)) do
        for _, ft in ipairs(AC.cardTypes()) do
            local items = c:getItemsFromType(ft)
            if items and not items:isEmpty() then
                for i = 0, items:size() - 1 do
                    local it = items:get(i)
                    if it then
                        local md = it:getModData()
                        -- บัตรเก่าที่ออกก่อนระบบเจ้าของ (acOwner = nil) ให้ถือว่าเป็นของคนที่ถืออยู่
                        -- ไม่งั้นคนที่เล่นมาก่อนอัปเดตจะใช้บัตรตัวเองไม่ได้ทันที
                        if md.acOwner == nil or md.acOwner == k then return true end
                    end
                end
            end
        end
    end
    return false
end

-- ------------------------------------------------------------------------------
-- แถวเดินบัญชีที่ "พร้อมวาด"
--
-- ปัญหา: แถวใน ledger เก็บ "คีย์" (ตัวพิมพ์เล็ก) ไม่ใช่ชื่อที่เอาไว้โชว์
--        ไคลเอนต์แปลคีย์เป็นชื่อเองไม่ได้ ตารางบัญชีอยู่ฝั่งเซิร์ฟทั้งหมดและห้ามส่งออกไป
--        (ส่งตารางบัญชี = ส่งยอดเงินของทุกคนบนเซิร์ฟไปให้ทุกเครื่องด้วย)
--
-- เลือกทางไหน  เซิร์ฟเวอร์แปลคีย์ -> ชื่อ แล้วแนบไปกับแถวเลย (ฟิลด์ who)
--   อีกทางคือส่ง map คีย์->ชื่อ ไปให้ไคลเอนต์ประกอบเอง  ไม่เอา เพราะ map นั้นคือ
--   "รายชื่อคนที่เคยเล่นเซิร์ฟนี้" ซึ่งกว้างกว่าที่ 50 แถวต้องใช้จริงมาก
--   หนึ่งแถวต้องการชื่อเดียว ก็ส่งไปชื่อเดียว
--
-- ส่งไปแค่ "ชื่อ" ไม่ใช่ประโยคเต็ม  การประกอบประโยคยังเป็นงานของไคลเอนต์
-- เพราะคำเชื่อมเปลี่ยนตามภาษาที่เครื่องผู้เล่นตั้งไว้ (AC.L) ไม่ใช่ของเซิร์ฟ
--
-- ต้องคัดลอกแถวก่อนเติม who  ห้ามเขียนทับแถวจริงใน DB
--   แถวเดียวกันถูกอ่านจากสองฝั่ง (คนโอนกับคนรับ) คู่กรณีคนละคนกัน
--   เขียนทับ = ฝั่งหนึ่งเห็นชื่อผิด และขยะนั้นถูกเซฟลงไฟล์เซฟถาวรด้วย
-- ------------------------------------------------------------------------------
local function dispOf(key)
    if type(key) ~= "string" or key == "" then return nil end
    if AC.isSys(key) then return nil end
    local a = D.get().accounts[key]
    return (a and a.disp) or key
end

local function tailView(k, limit)
    local rows = D.tailFor(k, limit)
    local mine = dispOf(k)
    local out  = {}
    for i = 1, #rows do
        local e     = rows[i]
        local other = (e.to == k) and e.f or e.to
        local who

        if AC.isSys(other) then
            -- คู่กรณีเป็นบัญชีระบบ ไม่มี "คนอีกฝั่ง" ให้โชว์
            -- คนที่ควรโชว์คือคนที่กดทำรายการ  e.by จดไว้ตั้งแต่บิลด์นี้เป็นต้นไป
            who = e.by
            -- แถวที่เขียนไว้ก่อนบิลด์นี้ไม่มีฟิลด์ by ติดมาด้วย
            -- ฝาก/ถอน เป็นเรื่องของเจ้าของบัญชีเสมอ เดาแทนได้โดยไม่มีทางผิด
            -- ที่เหลือ (แอดมินเสกเงิน ดอกเบี้ย ค่าธรรมเนียม) ปล่อยเป็น nil
            -- ให้ไคลเอนต์ตกกลับไปใช้ป้ายชนิดรายการแบบเดิม  ห้ามเดาชื่อคนเด็ดขาด
            if who == nil and (e.k == AC.KIND.DEPOSIT or e.k == AC.KIND.WITHDRAW) then
                who = mine
            end
        else
            who = dispOf(other)
        end

        out[i] = {
            t = e.t, gh = e.gh, f = e.f, to = e.to,
            a = e.a, k = e.k, r = e.r, via = e.via,
            who = who,
        }
    end
    return out
end

function S.sync(player)
    if not player then return end
    local k = U.key(player)
    if not k then return end
    local acc = D.account(player, true)

    -- เติมธงให้บัญชีเก่าที่ได้บัตรไปก่อนม็อดรุ่นนี้
    --
    -- ธง hasCard เกิดตอน S.issueCard เท่านั้น  คนที่รับบัตรไปตั้งแต่ก่อนอัปเดตจึงไม่มีธง
    -- แล้วจะหายจากรายชื่อผู้รับโอนทั้งที่มีบัตรอยู่ในมือจริง ๆ
    -- ตรงนี้จึงยอมดูจากกระเป๋า "ครั้งเดียวเพื่อเติมธง" เท่านั้น  ทางเดียว ไม่มีการลบธงคืน
    -- ห้ามเอาไปใช้เป็นเงื่อนไขตอนโอน  กระเป๋าตอบได้เฉพาะตอนคนนั้นออนไลน์
    if acc and acc.hasCard ~= true and S.holdsOwnCard(player) then
        acc.hasCard = true
    end

    -- กล่องรับโอน  "อ่านถึงไหนแล้ว" เก็บที่บัญชี ไม่ใช่ที่เครื่องผู้เล่น
    -- ต้องรอดข้ามการล็อกอิน คนที่ออฟไลน์ตอนโดนโอนต้องเห็นตอนกลับมา
    -- บัญชีเก่ายังไม่มีฟิลด์นี้ -> เริ่มนับจาก "ตอนนี้"
    -- ไม่งั้นทุกการโอนย้อนหลังในสมุดจะเด้งขึ้นเป็น "ใหม่" พร้อมกันหมดในวันอัปเดต
    local now = U.realTs()
    if acc and acc.seenT == nil then acc.seenT = now end

    local cashAll, cashL, cashB = countCash(player)

    sendServerCommand(player, AC.MODULE, AC.CMD.SYNC, {
        bal     = Akacount.balance(k),
        hold    = Akacount.held(k),
        avail   = Akacount.available(k),
        locked  = Akacount.isLocked(k),
        skin    = Akacount.getPlayerSkin(k),
        skins   = Akacount.getCardSkins(k),   -- แนบราคาและว่าเราซื้อไปหรือยัง
        -- แถวพร้อมวาด  ชื่อคนถูกแปลจากคีย์มาให้แล้ว (ดู tailView ข้างบน)
        tail    = tailView(k, AC.CLIENT_TAIL),
        cash    = cashAll,          -- มูลค่ารวมเป็นใบ (ปึกละ 100)
        cashL   = cashL,            -- แบงก์ใบ
        cashB   = cashB,            -- ปึก
        bundleOK = bundleOK(),
        -- กล่องรับโอน  ไคลเอนต์คัดแถว "รับโอน" จาก tail เอง ไม่ต้องส่งรายการซ้ำ
        seenT   = acc and acc.seenT or now,
        now     = now,              -- นาฬิกาเซิร์ฟ ใช้คำนวณ "กี่นาทีก่อน" ให้ตรงกับ t ในแถว
        -- ระวังสองคำนี้  มันคนละเรื่องกันและตั้งใจให้ต่างกัน
        --   hasCard (บนสาย)  = ตอนนี้ถือบัตรของตัวเองอยู่ไหม -> ใช้ตัดสินว่าจะโชว์ปุ่ม "ขอบัตร"
        --   account.hasCard  = เคยรับบัตรไปแล้วหรือยัง       -> ใช้ตัดสินว่าใครรับโอนได้
        -- ทำบัตรหายต้องขอใบใหม่ได้ แต่ต้องไม่หายจากรายชื่อผู้รับโอน เงินไม่ได้อยู่ในบัตร
        hasCard = S.holdsOwnCard(player),
        atCntr  = S.isAtCounter(player),
        -- ส่งระยะไปด้วย  ไคลเอนต์จะได้ใช้เลขตัวเดียวกับที่เซิร์ฟใช้จริง ไม่ใช่เลขที่ฝังไว้ในจอ
        cntrRange = S.counterRange(),
        counters = D.get().counters or {},
        admin   = isAdmin(player),
        stats   = isAdmin(player) and Akacount.stats() or nil,
    })
end

-- ------------------------------------------------------------------------------
-- ฝาก  (ทุกที่ - ที่ตู้ฟรี นอกตู้เสียค่าธรรมเนียม)
-- ------------------------------------------------------------------------------
function S.deposit(player, args)
    local k = U.key(player)
    if not k then return end

    -- ฝากทำได้ทุกที่ด้วยการคลิกขวาที่เงินสด  ที่ตู้ฝากฟรี นอกตู้เสียค่าธรรมเนียม
    -- (ถอนยังเป็นที่ตู้อย่างเดียวตามที่ตกลง เพราะเซิร์ฟต้องสร้างไอเทมให้ที่จุดนั้น)
    local atCounter = S.isAtCounter(player)

    local want = math.floor(tonumber(args and args.n) or 0)
    if want <= 0 then return alert(player, "Enter an amount.", "bad") end

    local have = countCash(player)
    if want > have then want = have end
    if want <= 0 then return alert(player, "You have no cash on you.", "bad") end

    -- ------------------------------------------------------------------
    -- ยอดต้องมากกว่าค่าธรรมเนียมเสมอ  ตรวจ "ก่อน" ยึดเงินสด
    --
    -- ฝากนอกตู้ 3 บาทแล้วโดนค่าธรรมเนียมขั้นต่ำ 5 บาท = ฝากเงินแล้วบัญชีลดลง
    -- ซึ่งไม่มีทางอธิบายให้ผู้เล่นเข้าใจได้เลย  ต้องปฏิเสธไปตรง ๆ พร้อมบอกขั้นต่ำจริง
    -- ใช้ตัวคำนวณตัวเดียวกับฝั่งจอ (U.minSendFor) ตัวเลขบนจอกับที่นี่จึงตรงกันเสมอ
    -- ------------------------------------------------------------------
    local pct  = atCounter and 0 or (U.opt("DepositFeePct"))
    local minD = U.minSendFor(pct)
    if want * AC.SUBUNIT < minD then
        return alert(player, "Deposit at least " .. U.fmt(minD) ..
                             " away from a counter - the fee alone is " ..
                             U.fmt(U.feeFor(want * AC.SUBUNIT, pct)) ..
                             ". Deposits at a bank counter are free.", "bad")
    end

    local took = takeCash(player, want)
    if took <= 0 then return alert(player, "Could not take the cash.", "bad") end

    local sub = took * AC.SUBUNIT
    local fee = atCounter and 0 or U.feeFor(sub, U.opt("DepositFeePct"))

    -- เก็บได้ไม่ครบตามที่ขอ (ของติด favorite / สวมอยู่) ยอดจริงเลยเล็กกว่าที่ตรวจไว้
    -- ตรงนี้ยอมคืนเงินสดกลับไปดีกว่าปล่อยให้ค่าธรรมเนียมกินยอดจนติดลบ
    -- คืนได้เพราะแบงก์ในเกมเป็นก้อนละ 1 บาทเท่ากันหมด  ก้อนที่คืนไม่ต่างจากก้อนที่ยึดมา
    if sub <= fee then
        giveCash(player, took, true)
        return alert(player, "Deposit at least " .. U.fmt(minD) ..
                             " away from a counter. Nothing was taken.", "bad")
    end

    -- เงินสดที่เข้ามาจากโลกในเกม โผล่เป็น SYS:LOOT ถ้ามันมากกว่าที่เคยถอนออกไป
    -- ทำให้กราฟจับดูปเงินได้โดยไม่ต้องเขียนโค้ดจับดูปเลยสักบรรทัด
    --
    -- ทุกแถวจดชื่อคนที่กดด้วย  คู่กรณีของการฝากเป็นบัญชีระบบ (SYS:CASH / SYS:LOOT)
    -- ซึ่งตอบไม่ได้ว่าใครเป็นคนทำ  สมุดบัญชีต้องบอกให้ได้ว่า "ใคร ทำที่ไหน"
    local dispBy = U.disp(player)
    local vDep   = atCounter and AC.VIA.COUNTER or AC.VIA.CARD
    local outside = D.sysBal(AC.SYS.CASH)
    if outside >= sub then
        D.addSys(AC.SYS.CASH, -sub)
        local a = D.account(k, true); a.bal = (a.bal or 0) + sub
        D.append({ t = U.realTs(), gh = U.gameHour(), f = AC.SYS.CASH, to = k,
                   a = sub, k = AC.KIND.DEPOSIT, r = "deposit",
                   via = vDep, by = dispBy })
    else
        local fromCash = math.max(0, outside)
        if fromCash > 0 then
            D.addSys(AC.SYS.CASH, -fromCash)
            local a = D.account(k, true); a.bal = (a.bal or 0) + fromCash
            D.append({ t = U.realTs(), gh = U.gameHour(), f = AC.SYS.CASH, to = k,
                       a = fromCash, k = AC.KIND.DEPOSIT, r = "deposit",
                       via = vDep, by = dispBy })
        end
        local rest = sub - fromCash
        -- mint จาก SYS:LOOT เขียนชนิด "dep" แล้ว ไม่ใช่ "adm" เหมือนก่อน
        -- (นี่คือบรรทัดที่ทำให้ผู้เล่นเห็น "Admin adjustment" ตอนฝากเงินเอง)
        if rest > 0 then L.mint(k, rest, AC.SYS.LOOT, "deposit", vDep, { by = dispBy }) end
    end

    if fee > 0 then L.burn(k, fee, AC.SYS.FEE, "deposit fee", AC.VIA.CARD, false, { by = dispBy }) end

    D.checkInvariant("deposit")
    alert(player, "Deposited " .. U.fmt(sub) ..
                  (fee > 0 and ("  (fee " .. U.fmt(fee) .. ")") or "  (free at counter)"), "good")
    S.sync(player)
end

-- ------------------------------------------------------------------------------
-- ถอน  (ตู้เท่านั้น)
-- ------------------------------------------------------------------------------
function S.withdraw(player, args)
    local k = U.key(player)
    if not k then return end
    if not S.isAtCounter(player) then
        return alert(player, "Go to a bank counter to withdraw cash.", "bad")
    end

    -- หน่วยบนสาย: เงินเป็น "สตางค์" (subunit) เสมอ  ไม่ใช่บาท
    --
    -- เคยพลาดตรงนี้จนผู้เล่นถอนไม่ได้:
    --   ไคลเอนต์ส่ง 10000 (= 100.00 บาท เป็นสตางค์อยู่แล้ว)
    --   เซิร์ฟคูณ SUBUNIT ซ้ำอีกรอบ -> 1,000,000 = 10,000.00 บาท
    --   คนมี 300.00 เลยโดนบอกว่า "Not enough in your account."
    --
    -- ชื่อฟิลด์เปลี่ยนเป็น sub เพื่อให้อ่านโค้ดแล้วรู้หน่วยทันที
    -- ฟิลด์ n สงวนไว้สำหรับ "จำนวนชิ้น" เท่านั้น (เช่น ฝากเงินสดกี่ก้อน)
    local sub = math.floor(tonumber(args and (args.sub or args.n)) or 0)
    if sub <= 0 then return alert(player, "Enter an amount.", "bad") end
    local fee = U.feeFor(sub, U.opt("WithdrawFeePct"))

    if not Akacount.can(k, sub + fee) then
        return alert(player, "Not enough in your account.", "bad")
    end

    -- เงินสดในเกมเป็น "ก้อนละ 1 บาท"  ถอนเป็นสตางค์เลยต้องหารกลับก่อนเสกของ
    -- เศษสตางค์ถอนออกมาเป็นของจับต้องได้ไม่ได้  จึงปัดลงและคิดเงินตามที่เสกได้จริง
    local notes = math.floor(sub / AC.SUBUNIT)
    if notes <= 0 then
        return alert(player, "Withdraw at least " .. U.fmt(AC.SUBUNIT) .. ".", "bad")
    end

    -- bundles = true มาจากสวิตช์ "ปึก x100" บนจอถอน
    -- ไม่ส่งมา (ไคลเอนต์รุ่นเก่า) = แบงก์ใบเหมือนเดิม  ธงที่เพิ่มทีหลังต้องมีค่าเริ่มต้นเท่าพฤติกรรมเดิม
    local made = giveCash(player, notes, args and args.bundles == true)
    if made <= 0 then return alert(player, "Could not hand out the cash.", "bad") end

    local realSub = made * AC.SUBUNIT
    local a = D.account(k, true)
    a.bal = (a.bal or 0) - realSub
    D.addSys(AC.SYS.CASH, realSub)
    -- ถอนที่ตู้เท่านั้น  คนทำคือเจ้าของบัญชีเสมอ แต่ยังต้องจดชื่อไว้
    -- เพราะแถวนี้คู่กรณีเป็น SYS:CASH ซึ่งไม่ใช่คน  จอถึงจะเขียนว่า "ใคร ทำที่ไหน" ได้
    local dispBy = U.disp(player)
    D.append({ t = U.realTs(), gh = U.gameHour(), f = k, to = AC.SYS.CASH,
               a = realSub, k = AC.KIND.WITHDRAW, r = "atm", via = AC.VIA.COUNTER,
               by = dispBy })

    if fee > 0 then L.burn(k, fee, AC.SYS.FEE, "withdraw fee", AC.VIA.COUNTER, false, { by = dispBy }) end

    D.checkInvariant("withdraw")
    alert(player, "Withdrew " .. U.fmt(realSub) .. ".", "good")
    S.sync(player)
end

-- ------------------------------------------------------------------------------
-- โอน  (คลิกขวาที่บัตร — เสียค่าธรรมเนียม / ที่ตู้ — ฟรี)
-- ------------------------------------------------------------------------------
function S.transfer(player, args)
    local from = U.key(player)
    if not from then return end
    -- ไคลเอนต์รุ่นใหม่ส่ง toKey (คีย์ตัวพิมพ์เล็กที่เลือกจากรายชื่อ)
    -- รับ to ต่อไปด้วยเพื่อไม่ทิ้งไคลเอนต์รุ่นเก่ากลางทาง  ทั้งคู่ผ่าน U.key เหมือนกัน
    local to = U.key(args and (args.toKey or args.to))
    if not to        then return alert(player, "Pick someone to send to.", "bad") end
    if to == from    then return alert(player, "You cannot send to yourself.", "bad") end

    -- ------------------------------------------------------------------
    -- ผู้รับต้องมีบัตรแล้วเท่านั้น
    --
    -- ห้ามเชื่อรายชื่อที่ไคลเอนต์ถืออยู่  รายชื่อนั้นเป็นแค่ความสะดวกของจอ
    -- ใครก็ยิงคำสั่งตรงมาพร้อมชื่อที่ไม่เคยอยู่ในลิสต์ได้  ด่านจริงต้องอยู่ตรงนี้
    -- และต้องดูจากธงในบัญชี ไม่ใช่จากกระเป๋าของผู้รับ  ผู้รับอาจออฟไลน์อยู่
    -- ------------------------------------------------------------------
    local ta = D.account(to, false)
    if not ta or ta.hasCard ~= true then
        return alert(player, "That player has not collected a bank card yet. " ..
                             "Cards are handed out at the bank counter.", "bad")
    end

    -- หน่วยบนสายเป็นสตางค์เสมอ  เหตุผลเดียวกับ S.withdraw
    local sub = math.floor(tonumber(args and (args.sub or args.n)) or 0)
    if sub <= 0 then return alert(player, "Enter an amount.", "bad") end

    local a = D.account(from, true)
    local now = U.realTs()

    -- คูลดาวน์  ไม่รบกวนคนเล่นปกติเลย แต่ตัดการโอนรัวทิ้ง
    local cd = tonumber(U.opt("XferCooldownSec")) or 0
    if cd > 0 and (now - (a.sentAt or 0)) < cd then
        return alert(player, "Wait " .. math.ceil(cd - (now - a.sentAt)) .. "s before sending again.", "bad")
    end

    -- เพดานต่อวันจริง  รีเซ็ตแบบ lazy ไม่ต้องมี timer
    local dk = U.dayKey(now)
    if a.sentDK ~= dk then a.sentDK, a.sentD = dk, 0 end
    local cap = tonumber(U.opt("XferDailyCap")) or math.huge
    if (a.sentD or 0) + sub > cap then
        return alert(player, "Daily transfer limit reached.", "bad")
    end

    local atCounter = S.isAtCounter(player)
    local via = atCounter and AC.VIA.COUNTER or AC.VIA.CARD
    local pct = atCounter and 0 or (U.opt("XferFeeCardPct"))
    local fee = U.feeFor(sub, pct)

    -- ยอดต้องมากกว่าค่าธรรมเนียม  "เท่ากับ" ก็ไม่ผ่าน เพราะผู้รับจะได้ศูนย์
    -- ขั้นต่ำมาจาก U.minSendFor ตัวเดียวกับที่จอใช้เขียนบนปุ่ม  ปุ่มกับเซิร์ฟจึงพูดตรงกัน
    local minA = U.minSendFor(pct)
    if sub <= fee or sub < minA then
        return alert(player, "Send more than the fee. Minimum right now is " .. U.fmt(minA) ..
                             " (the fee on that would be " .. U.fmt(U.feeFor(minA, pct)) ..
                             "). Transfers made at a bank counter are free.", "bad")
    end

    if Akacount.isLocked(from) then return alert(player, "Your account is overdrawn.", "bad") end
    if not Akacount.can(from, sub + fee) then return alert(player, "Not enough funds.", "bad") end

    -- คนโอนอยู่ในฟิลด์ f อยู่แล้ว แต่จด by ไว้ด้วยเพื่อให้ทุกแถวตอบคำถามเดียวกันได้
    -- โดยไม่ต้องรู้ว่าแถวชนิดไหนเก็บชื่อคนทำไว้ตรงไหน
    local dispBy = U.disp(player)
    local ok, err = L.move(from, to, sub, AC.KIND.TRANSFER, "xfer", via, false, { by = dispBy })
    if not ok then return alert(player, "Transfer failed: " .. tostring(err), "bad") end
    if fee > 0 then L.burn(from, fee, AC.SYS.FEE, "transfer fee", via, false, { by = dispBy }) end

    a.sentAt = now
    a.sentD  = (a.sentD or 0) + sub

    D.checkInvariant("transfer")
    -- ชื่อที่โชว์ต้องมาจากบัญชี ไม่ใช่จากสตริงที่ไคลเอนต์ส่งมา
    -- ไคลเอนต์ส่งคีย์ตัวพิมพ์เล็กมา ถ้าเอามาโชว์ดิบ ๆ ผู้เล่นจะเห็นชื่อตัวเองผิดตัวพิมพ์
    local toDisp = ta.disp or to
    alert(player, "Sent " .. U.fmt(sub) .. " to " .. tostring(toDisp) ..
                  (fee > 0 and ("  (fee " .. U.fmt(fee) .. ")") or ""), "good")
    S.sync(player)

    -- คนรับออนไลน์อยู่ -> ขึ้นข้อความบนหัวทันที
    -- ออฟไลน์ -> ไม่ต้องทำอะไร  ตอนล็อกอินรอบหน้า sync จะเห็นว่ามีแถวรับโอนที่ t > seenT
    -- แล้วไคลเอนต์แจ้งเองว่า "มีเงินเข้าระหว่างที่ไม่อยู่"
    local target = getPlayerFromUsername and getPlayerFromUsername(toDisp)
    if target then
        sendServerCommand(target, AC.MODULE, AC.CMD.INCOMING, { who = U.disp(player), sub = sub })
        S.sync(target)
    end
end

-- ------------------------------------------------------------------------------
-- อ่านกล่องรับโอนแล้ว
-- เวลามาจากนาฬิกาเซิร์ฟเสมอ  ไม่รับเลขจากไคลเอนต์ (ไม่มีอะไรให้โกงก็จริง แต่ไม่มีเหตุให้เชื่อ)
-- ------------------------------------------------------------------------------
function S.markSeen(player)
    local acc = D.account(player, true)
    if not acc then return end
    acc.seenT = U.realTs()
    S.sync(player)
end

-- ------------------------------------------------------------------------------
-- รายชื่อคนที่โอนหาได้  =  คนที่ "มีบัตรแล้ว" ไม่ใช่คนที่ออนไลน์อยู่
--
-- ข้อกำหนดจากเจ้าของเซิร์ฟตรง ๆ:
--   "ไม่ใช่พิมพ์ชื่อแต่เป็น dropdown และโอนให้ได้แค่คนที่มีบัตรแล้วเท่านั้นไม่ใช่คน online"
--
-- ของเดิมไล่ getOnlinePlayers() ซึ่งผิดสองชั้น
--   1. คนที่ไม่ได้ออนไลน์ตอนนี้ก็รับโอนได้อยู่แล้ว เงินอยู่ในบัญชี ไม่ได้อยู่ที่ตัวคน
--   2. คนที่ออนไลน์แต่ยังไม่เคยไปรับบัตร ไม่ควรเป็นปลายทางของการโอนผ่านบัตร
-- แหล่งข้อมูลที่ถูกจึงเป็น D.get().accounts ไม่ใช่รายชื่อในเซิร์ฟ
--
-- ชื่อคำสั่งบนสายยังเป็น WHO_ONLINE / ONLINE_LIST ตามเดิม  เป็นชื่อทางประวัติศาสตร์
-- เปลี่ยนสตริงบนสาย = ไคลเอนต์ที่ยังไม่อัปเดตจะเงียบสนิทโดยไม่มี error ให้เห็น
--
-- ส่ง key มาด้วยเสมอ  จอจะได้ส่งคีย์กลับมาแทนที่จะให้เซิร์ฟเดาจากชื่อที่โชว์
-- ------------------------------------------------------------------------------
function S.cardHolders(player)
    local meKey = U.key(player)
    local list  = {}
    local db    = D.get()
    for k, a in pairs(db.accounts or {}) do
        if k ~= meKey and a and a.hasCard == true then
            list[#list + 1] = { key = k, name = a.disp or k }
        end
    end
    -- เรียงตามตัวอักษร  รายชื่อที่สลับตำแหน่งทุกครั้งที่เปิดคือรายชื่อที่กดผิดคน
    table.sort(list, function(x, y) return tostring(x.name):lower() < tostring(y.name):lower() end)
    sendServerCommand(player, AC.MODULE, AC.CMD.ONLINE_LIST, { list = list })
end

-- ------------------------------------------------------------------------------
-- แอดมิน
-- ------------------------------------------------------------------------------
function S.adminMint(player, args)
    if not isAdmin(player) then return end
    local to = U.key(args and args.to)
    -- หน่วยบนสายเป็นสตางค์เสมอ  ติดลบ = หักออก
    local n  = math.floor(tonumber(args and (args.sub or args.n)) or 0)
    if not to or n == 0 then return end
    local sub = math.abs(n)

    -- ต้องจดว่า "แอดมินคนไหน"  ไม่ใช่แค่ว่าแอดมินทำ
    --
    -- ก่อนหน้านี้แถวนี้เขียนแค่ SYS:ADMIN -> ผู้เล่น  ซึ่งตอบไม่ได้เลยว่าใครกด
    -- เซิร์ฟที่มีแอดมินหลายคน สามเดือนหลังจากนั้นไม่มีใครจำได้ และไม่มีทางย้อนไปหา
    -- ชื่อนี้จะไปโผล่ในสมุดของผู้เล่นเป็น "Admin - <ชื่อ>" ตั้งใจให้ดูออกว่าเป็นแอดมิน
    -- ห้ามทำให้มันดูเหมือนการโอนธรรมดา นั่นแย่กว่าคำเดิมอีก
    local by = { by = U.disp(player) }
    local ok, err
    if n > 0 then ok, err = L.mint(to, sub, AC.SYS.ADMIN, "admin", AC.VIA.SYSTEM, by)
    else          ok, err = L.burn(to, sub, AC.SYS.ADMIN, "admin", AC.VIA.SYSTEM, true, by) end
    alert(player, ok and ("OK  " .. tostring(args.to) .. "  " .. tostring(n))
                     or ("Failed: " .. tostring(err)), ok and "good" or "bad")
    D.checkInvariant("adminMint")
    local t = getPlayerFromUsername and getPlayerFromUsername(args.to)
    if t then S.sync(t) end
end

-- ------------------------------------------------------------------------------
-- ลงทะเบียนตู้ธนาคาร   AKA Mod > Bank link
--   ทุก tile ใช้ค่าเดียวกันหมด ไม่มีการตั้งค่ารายตู้
--   เก็บแค่พิกัดกับ sprite ไว้ให้แอดมินไล่ดูย้อนหลังได้
-- ------------------------------------------------------------------------------
local function tileId(x, y, z) return x .. ":" .. y .. ":" .. z end

function S.adminRegTile(player, args)
    if not isAdmin(player) then return end
    if not args or not args.x then return end
    local db = D.get()
    db.counters = db.counters or {}

    local id = tileId(args.x, args.y, args.z)
    if args.on == false then
        if db.counters[id] then
            db.counters[id] = nil
            alert(player, "Bank link removed.", "good")
        else
            alert(player, "No bank link on this tile.", "bad")
        end
    else
        if db.counters[id] then
            return alert(player, "This tile is already a bank.", "bad")
        end
        db.counters[id] = {
            x = args.x, y = args.y, z = args.z,
            sprite = args.sprite or "",
            by = U.disp(player), at = U.realTs(),
        }
        alert(player, "Bank link created here.", "good")
    end

    -- ทุกคนต้องรู้ว่าตู้อยู่ไหน ไม่ใช่ความลับ  ผู้เล่นต้องหาธนาคารเจออยู่แล้ว
    local online = getOnlinePlayers and getOnlinePlayers()
    if online then
        for i = 0, online:size() - 1 do
            local p = online:get(i)
            if p then S.sync(p) end
        end
    else
        S.sync(player)
    end
end

-- ------------------------------------------------------------------------------
-- เปลี่ยนลายบัตร
--
-- ทำที่เคาน์เตอร์ธนาคารเท่านั้น  เหตุผลเดียวกับการถอนเงิน
-- ถ้าเปลี่ยนได้ทุกที่ บัตรก็ไม่ต่างอะไรกับเมนูตั้งค่า และธนาคารก็ไม่มีความหมาย
--
-- ทำไมถึงเคยกดแล้วไม่ติด (บั๊กที่เจอในเกม)
--   1. AC.CMD.SET_SKIN มีนิยามอยู่ แต่ไม่มีใคร reg() มัน  คำสั่งวิ่งไปแล้วตกพื้น
--   2. API.ownsSkin() คืน true เฉพาะลาย DEFAULT  อีกสามลายเลย "not owned" ตลอด
--   3. ชื่อ texture ในค่าคงที่ไม่ตรงกับไฟล์ที่แพ็กมาจริง
--   แก้ครบทั้งสามที่แล้ว  และมีเทสคุมข้อ 2 ไว้ไม่ให้พลาดซ้ำ
-- ------------------------------------------------------------------------------
-- ซื้อลายบัตร
--
-- จ่ายด้วยเงินสดในบัญชีเท่านั้น  ไม่มี HF/CP เพราะลายบัตรเป็นของธนาคาร
-- ซื้อแล้วเป็นของถาวร  แอดมินขึ้นราคาทีหลังก็ไม่โดนยึดคืน
function S.buySkin(player, args)
    local k = U.key(player); if not k then return end
    local id = args and args.skin
    if type(id) ~= "string" or id == "" then return end

    if not S.isAtCounter(player) then
        return alert(player, "Go to a bank counter to buy a design.", "bad")
    end
    if not Akacount.skinExists(id) then
        return alert(player, "That card design does not exist.", "bad")
    end
    if Akacount.ownsSkin(k, id) then
        return alert(player, "You already own that design.", "info")
    end

    local price = Akacount.skinPrice(id)
    if price <= 0 then
        -- ราคา 0 = ของแถม  ไม่ควรมาถึงตรงนี้ แต่ถ้ามาก็แจกไปเลย
        Akacount.grantSkin(k, id)
        return S.setSkin(player, { skin = id })
    end
    if not Akacount.can(k, price) then
        return alert(player, "You need " .. U.fmt(price) .. " to buy that design.", "bad")
    end

    -- หักเงินก่อน แล้วค่อยให้สิทธิ์
    -- ให้สิทธิ์ก่อนแล้วหักพลาด = แจกลายฟรี ซึ่งย้อนกลับไม่ได้
    local okPay = pcall(L.burn, k, price, AC.SYS.FEE, "card design " .. id, AC.VIA.COUNTER, false,
                        { by = U.disp(player) })
    if not okPay then
        return alert(player, "Payment failed. Nothing was taken.", "bad")
    end
    Akacount.grantSkin(k, id)
    alert(player, "Bought " .. id .. " for " .. U.fmt(price) .. ".", "good")
    S.setSkin(player, { skin = id })
end

-- แอดมินตั้งราคาลาย
function S.adminSkinPrice(player, args)
    if not isAdmin(player) then return alert(player, "Admin only.", "bad") end
    local id = args and args.skin
    local pr = math.max(0, math.floor(tonumber(args and args.price) or 0))
    if type(id) ~= "string" or id == "" then return end
    local ok2 = Akacount.setSkinPrice(id, pr)
    if not ok2 then return alert(player, "No such design.", "bad") end
    alert(player, "Price for '" .. id .. "' set to " ..
                  (pr > 0 and U.fmt(pr) or "free") .. ".", "good")
    S.sync(player)
end

function S.setSkin(player, args)
    if not player then return end
    local id = args and args.skin
    if type(id) ~= "string" or id == "" then return end

    if not S.isAtCounter(player) then
        return alert(player, "Go to a bank counter to change your card.", "bad")
    end

    local name = U.key(player)
    local ok, why = Akacount.setPlayerSkin(name, id)
    if not ok then
        if why == "not owned" then
            return alert(player, "You do not own that card design yet.", "bad")
        end
        return alert(player, "That card design does not exist.", "bad")
    end

    -- ออกบัตรใบใหม่  ใบเก่าถูกทำลายทิ้ง
    -- ไม่ใช่ทาสีทับ เพราะใบเก่าอาจไม่ได้อยู่ในมือเจ้าของแล้ว
    -- ถ้าไปทาสีใบที่คนอื่นถืออยู่ เท่ากับเปลี่ยนของในกระเป๋าคนอื่นจากระยะไกล
    local issued, replaced = S.issueCard(player, id)
    if not issued then
        alert(player, "Design saved. Get a card at the counter to see it.", "info")
    elseif (replaced or 0) > 0 then
        alert(player, "New card issued - the old one was destroyed.", "good")
    else
        alert(player, "Card issued.", "good")
    end
    S.sync(player)
end

-- ------------------------------------------------------------------------------
-- ออกบัตรใหม่
--
-- กติกาที่ตกลงกัน: **หนึ่งคนมีได้ใบเดียว และผูกกับตัวคนนั้น**
--   เปลี่ยนลาย = ทำลายใบเก่าทิ้ง แล้วออกใบใหม่ผูกไอดีเดิม
--   ไม่ใช่ "ทาสีทับ" เพราะบัตรใบเก่าอาจอยู่ในมือคนอื่นไปแล้ว
--
-- เจ้าของถูกจดไว้ที่ตัวไอเทม (modData.acOwner) ไม่ใช่ที่บัญชี
--   บัญชีตอบไม่ได้ว่า "บัตรใบที่อยู่ในมือคนนี้เป็นของใคร"
--   ต้องถามที่ตัวบัตรเท่านั้น เพราะบัตรเปลี่ยนมือได้ (โดนขโมย/ตกพื้น/เก็บได้)
--
-- ชื่อไอเทมเขียนชื่อเจ้าของไว้เลย  คนเก็บได้จะได้รู้ทันทีว่าใช้ไม่ได้
-- โดยไม่ต้องคลิกขวาแล้วเจอข้อความปฏิเสธ
-- ------------------------------------------------------------------------------
-- ต้องไล่ทุกชนิดบัตร ไม่ใช่แค่ AC.ITEM_CARD
-- ตั้งแต่ลายบัตรกลายเป็นไอเทมคนละชนิด (ดูคอมเมนต์ยาวใน AC_Const)
-- คนที่ใช้ลาย slate อยู่ถือ Base.AkacountCardSlate ไม่ใช่ Base.AkacountCard
-- ถ้าหาแค่ชนิดเดียว "ทำลายใบเก่า" จะหาใบเก่าไม่เจอ = ผู้เล่นสะสมบัตรได้หลายใบ
local function cardsOf(player)
    local out = {}
    for _, c in ipairs(playerContainers(player)) do
        for _, ft in ipairs(AC.cardTypes()) do
            local items = c:getItemsFromType(ft)
            if items and not items:isEmpty() then
                for i = 0, items:size() - 1 do
                    local it = items:get(i)
                    if it then out[#out + 1] = { item = it, cont = c } end
                end
            end
        end
    end
    return out
end

local function stampCard(it, k, disp, skinId)
    local sk = AC.skinById(skinId) or AC.skinById(AC.CARD_SKIN_DEFAULT)
    -- ไอเทมที่ไม่มี getModData แปลว่าไม่ใช่ InventoryItem จริง
    -- ยอมข้ามการประทับเจ้าของดีกว่าทำให้ทั้งคำสั่งตาย
    if not U.hasMethod(it, "getModData") then return end
    local md = it:getModData()
    md.acOwner  = k
    md.acSkin   = skinId
    md.acIssued = U.realTs()

    if U.hasMethod(it, "setName") then
        pcall(function() it:setName("Akacount Card - " .. tostring(disp)) end)
    end

    -- หน้าตาของบัตรมาจาก "ชนิดไอเทม" แล้ว ไม่ได้มาจากสองบรรทัดนี้
    -- ยังเรียกไว้เพราะลายที่ม็อดอื่นลงทะเบียนเข้ามาไม่มีไอเทมของตัวเอง
    -- ลายพวกนั้นได้หน้าตาที่ถูกต้องเฉพาะช่วงที่เซสชันยังเปิดอยู่ ซึ่งดีกว่าไม่ได้เลย
    if sk and not sk.item then
        pcall(function() it:setTexture(getTexture("media/textures/" .. sk.icon .. ".png")) end)
        if sk.model then pcall(function() it:setStaticModel(sk.model) end) end
    end
    if U.hasMethod(it, "syncItemFields") then pcall(function() it:syncItemFields() end) end
end

-- ออกบัตรใบใหม่ให้  ทำลายทุกใบที่ถืออยู่ก่อนเสมอ
--
-- ลายไหน = ไอเทมชนิดไหน  ไม่ใช่ไอเทมเดิมทาสีทับ (ดูคอมเมนต์ยาวใน AC_Const)
-- force = ให้ผ่านด่านเคาน์เตอร์  สงวนไว้ให้แอดมิน/ระบบที่เรียกตรงเท่านั้น
function S.issueCard(player, skinId, force)
    local k = U.key(player); if not k then return false end

    -- ------------------------------------------------------------------
    -- บัตรรับได้ที่เคาน์เตอร์ธนาคารเท่านั้น
    --
    -- ด่านอยู่ที่นี่ด่านเดียว ไม่ใช่กระจายไปอยู่หลังปุ่มแต่ละปุ่ม
    -- ปุ่มมีวันเพิ่ม (ตอนนี้มีสองทาง: ขอบัตร กับ เปลี่ยนลาย) แต่ทางออกของบัตรมีทางเดียว
    -- ใครลืมเช็คที่ปุ่มใหม่ ก็ยังหลุดไม่ได้อยู่ดี
    -- ------------------------------------------------------------------
    if not force and not S.isAtCounter(player) then
        alert(player, "Cards are issued at the bank counter. Come to the bank to collect yours.", "bad")
        return false, 0
    end

    local disp = U.disp(player)
    skinId = skinId or Akacount.getPlayerSkin(k)

    local inv = player:getInventory()
    if not inv then return false end

    -- หาชนิดไอเทมที่จะออกให้ก่อน  ถ้าเกมไม่รู้จักชนิดนั้นค่อยตกกลับมาใบมาตรฐาน
    -- ต้องเช็กก่อนทำลายใบเก่า  ไม่งั้นจะกลายเป็น "ทำลายแล้วออกใหม่ไม่ได้" = บัตรหายฟรี
    local sm = getScriptManager()
    local want = AC.cardItemOf(skinId)
    local function known(ft)
        if not sm then return false end
        local okF, found = pcall(function() return sm:FindItem(ft) end)
        return okF and found ~= nil
    end
    if not known(want) then want = AC.ITEM_CARD end
    if not known(want) then return false end

    local held = cardsOf(player)
    for _, row in ipairs(held) do
        if sendRemoveItemFromContainer then
            pcall(sendRemoveItemFromContainer, row.cont, row.item)
        end
        row.cont:Remove(row.item)
        row.cont:setDrawDirty(true)
    end

    local it = instanceItem(want)
    if not it then return false end
    stampCard(it, k, disp, skinId)
    inv:AddItem(it)
    if sendAddItemToContainer then pcall(sendAddItemToContainer, inv, it) end

    -- ธงนี้คือสิ่งเดียวที่ตัดสินว่าใครรับโอนได้  ต้องติดตอน "บัตรถึงมือจริง" เท่านั้น
    -- ติดก่อนหน้านี้ = คนที่ออกบัตรไม่สำเร็จโผล่ในรายชื่อผู้รับทั้งที่ไม่เคยมีบัตร
    local a = D.account(player, true)
    if a then a.hasCard = true end

    return true, #held
end

-- ขอบัตร  ใช้ตอนยังไม่มีบัตรเลย
function S.requestCard(player)
    if not S.isAtCounter(player) then
        return alert(player, "Cards are issued at the bank counter. Come to the bank to collect yours.", "bad")
    end
    local k = U.key(player)
    if not Akacount.exists(k) then D.account(player, true) end

    local ok2, replaced = S.issueCard(player, Akacount.getPlayerSkin(k))
    if not ok2 then return alert(player, "Could not issue a card right now.", "bad") end
    alert(player, (replaced or 0) > 0 and "New card issued, the old one was destroyed."
                                      or "Card issued.", "good")
    S.sync(player)
end

-- (เลิกใช้ — เก็บไว้เป็นบันทึกว่าทำไมวิธีนี้ถึงใช้ไม่ได้)
--
-- ความคิดเดิม: ไม่ต้องออกบัตรใหม่ แค่ทาลายลงใบที่ถืออยู่
-- มันไม่ทำงานจริง เพราะ B42 อ่านไอคอนกระเป๋าจากฟิลด์ Icon ของ item script
-- และค่าที่เซ็ตตอนรันไม่ถูกเซฟ  รีล็อกอินทีเดียวลายกลับเป็นเดิม
-- นั่นคือสาเหตุที่ผู้เล่นรายงานว่า "ลายการ์ดไม่เปลี่ยน" ทั้งที่โค้ดรันผ่านหมด
--
-- ตอนนี้ S.issueCard ออกไอเทม "คนละชนิด" ต่อลายแทน  ซึ่งติดทนข้ามการเซฟ
-- ห้ามเอาฟังก์ชันนี้กลับมาใช้  ถ้าอยากเปลี่ยนลายให้เรียก S.issueCard
function S.applySkinToHeldCards() end

-- ------------------------------------------------------------------------------
-- dispatch
-- ------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------
-- ตารางคำสั่ง
--
-- ห้ามเขียน { [AC.CMD.FOO] = fn } ตรง ๆ
--   ถ้า AC.CMD.FOO สะกดผิดหรือลืมนิยาม มันจะกลายเป็น { [nil] = fn }
--   ซึ่ง Lua โยน "table index is nil" ตั้งแต่ตอนสร้างตาราง = ทั้งไฟล์ตายตั้งแต่โหลด
--   ผลคือ OnClientCommand ไม่เคยถูกลงทะเบียน ทุกอย่างฝั่งเซิร์ฟเงียบสนิท
--   และมันดูเหมือน "ปุ่มกดไม่ติด" ไม่ใช่ "ม็อดพัง" ซึ่งหาสาเหตุยากมาก
--   (เจอมาแล้วจริงกับ ADMIN_REG_TILE ที่ลืมนิยาม)
--
-- reg() บังคับให้พังพร้อมบอกชื่อคำสั่งที่ผิด แทนที่จะพังเงียบ ๆ
-- ------------------------------------------------------------------------------
local HANDLERS = {}
local function reg(name, cmd, fn)
    if type(cmd) ~= "string" or cmd == "" then
        U.log("!! command constant missing for '" .. tostring(name) .. "' - handler not installed")
        return
    end
    HANDLERS[cmd] = fn
end

reg("REQ_SYNC",       AC.CMD.REQ_SYNC,       function(p) S.sync(p) end)
reg("DEPOSIT",        AC.CMD.DEPOSIT,        S.deposit)
reg("WITHDRAW",       AC.CMD.WITHDRAW,       S.withdraw)
reg("TRANSFER",       AC.CMD.TRANSFER,       S.transfer)
-- ชื่อคำสั่งเป็นของเดิม แต่คนตอบเปลี่ยนไปแล้ว  (ดูคอมเมนต์หัว S.cardHolders)
reg("WHO_ONLINE",     AC.CMD.WHO_ONLINE,     function(p) S.cardHolders(p) end)
reg("ADMIN_MINT",     AC.CMD.ADMIN_MINT,     S.adminMint)
reg("ADMIN_REG_TILE", AC.CMD.ADMIN_REG_TILE, S.adminRegTile)
reg("SET_SKIN",       AC.CMD.SET_SKIN,       S.setSkin)
reg("GET_CARD",       AC.CMD.GET_CARD,       function(p2) S.requestCard(p2) end)
reg("BUY_SKIN",       AC.CMD.BUY_SKIN,       S.buySkin)
reg("ADMIN_SKIN_PRICE", AC.CMD.ADMIN_SKIN_PRICE, S.adminSkinPrice)
reg("MARK_SEEN",      AC.CMD.MARK_SEEN,      function(p3) S.markSeen(p3) end)

local function onClientCommand(module, command, player, args)
    if module ~= AC.MODULE then return end
    local h = HANDLERS[command]
    if h then h(player, args) end
end

-- ------------------------------------------------------------------------------
-- ผูก event เฉพาะฝั่งที่เป็นเจ้าของข้อมูลจริง
--
-- PZ โหลด media/lua/server/ บนไคลเอนต์ MP ด้วย ไม่ได้กันให้
-- ถ้าผูก EveryOneMinute ไว้เฉย ๆ ไคลเอนต์จะรัน sweepHolds ทุกนาทีแล้วพัง
-- (console.txt รอบแรกเจอ 56 ครั้ง และมันฆ่า OnInitGlobalModData ไปด้วย
--  ทำให้ log "server ready" ไม่เคยขึ้น)
-- ------------------------------------------------------------------------------
if U.isHost() then
    U.on("OnClientCommand", onClientCommand, "OnClientCommand")

    U.on("OnInitGlobalModData", function()
        D.reset()
        D.get()
        L.sweepHolds()
        D.checkInvariant("boot")
        local n = 0
        for _ in pairs(D.get().counters or {}) do n = n + 1 end
        U.log("server ready  v" .. AC.VERSION .. "  bank tiles: " .. n)
        -- บรรทัดเดียวที่บอกว่าระบบปึกเปิดอยู่ไหม  ไม่เจอ = ชื่อไอเทมไม่ตรงกับบิลด์นี้
        U.log("money bundle " .. AC.ITEM_BUNDLE .. " x" .. AC.BUNDLE_SIZE .. ": " ..
              (bundleOK() and "found - bundles on" or "NOT FOUND - loose notes only"))
    end, "boot")

    U.on("EveryOneMinute", function() L.sweepHolds() end, "sweep")
else
    U.log("client side - server handlers not installed (this is normal)")
end

AC.server = S
return S
