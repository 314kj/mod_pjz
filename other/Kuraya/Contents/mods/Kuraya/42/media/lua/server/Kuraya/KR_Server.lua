-- ==============================================================================
-- Kuraya — server/Kuraya/KR_Server.lua
-- แคตตาล็อก · Fresh Market · สะพานไปสามสกุลเงิน
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
require("Kuraya/KR_Const")

-- ------------------------------------------------------------------------------
-- โหลดซ้ำได้โดยไม่พัง
--
-- ไฟล์นี้ถูกดึงเข้ามาสองทาง: PZ เดินโฟลเดอร์ media/lua/server/ เอง และ
-- KR_Auction / KR_Credit ก็ require มันตอนหัวไฟล์ (ดูเหตุผลในไฟล์พวกนั้น)
-- ถ้ารันสองรอบ Events.OnClientCommand จะถูกผูกสองครั้ง = คำสั่งเดียวทำงานสองหน
-- = หักเงินสองรอบ  ยามตัวนี้ต้องอยู่ก่อนบรรทัดอื่นทั้งหมด
-- ------------------------------------------------------------------------------
if KR.server and KR.server.__ready then return KR.server end

print("[Kuraya] KR_Server  v" .. KR.VERSION)
require("Kuraya/KR_TownRank")

local S = {}
KR.server = S

-- ------------------------------------------------------------------------------
-- กันปัญหา load order
--   ห้ามจับ Akacount หรือ HF_Town_Rank_API เก็บเป็น local ที่ file scope
--   ถ้าม็อดนั้นโหลดทีหลัง จะได้ nil ค้างตลอดเซสชัน
--   ต้อง resolve ตอนเรียกทุกครั้ง — แพตเทิร์นเดียวกับ col("money") ของ AkaShop
-- ------------------------------------------------------------------------------
local function bank()
    return Akacount            -- อาจเป็น nil ได้ ถ้า Akacount ยังไม่โหลด
end

-- ------------------------------------------------------------------------------
-- สัญญาที่เราคาดหวังจาก Akacount
--
-- ทั้งม็อดนี้ไม่ได้เป็นเจ้าของเงินสดสักบาท  ทุกอย่างที่เป็น CASH วิ่งผ่านฟังก์ชัน
-- ในตารางนี้ทั้งหมด  ถ้าฝั่งโน้นเปลี่ยนชื่อเมธอดหรือยังโหลดไม่เสร็จ อาการที่ผู้เล่นเห็น
-- คือ "กดซื้อแล้วเงินไม่หัก ของไม่เข้า" ซึ่งไม่ได้บอกเลยว่าต้นเหตุอยู่คนละม็อด
--
-- เราเสียเวลาไล่บั๊กนี้มาสองรอบแล้วเพราะมันเงียบ  รอบนี้เลยประกาศสัญญาไว้ตรง ๆ
-- แล้วพิมพ์ผลตรวจตอนเซิร์ฟขึ้น  บรรทัดเดียวใน console ตอบได้ทันทีว่าใครพัง
--
-- แยกเป็นสองชั้น
--   CORE   = ไม่มีแล้วขายของไม่ได้เลย
--   ESCROW = ทางที่ดีที่สุด (พักเงิน -> ยึด) ไม่มีก็ยังขายได้ด้วย charge ตรง ๆ
--            แต่ต้องรู้ตัวว่ากำลังเดินทางสำรองอยู่ ไม่ใช่คิดว่าทุกอย่างปกติ
-- ------------------------------------------------------------------------------
local BANK_CORE   = { "available", "exists", "charge", "payTo" }
local BANK_ESCROW = { "holdForPurchase", "capturePurchase", "releaseHold" }
local BANK_EXTRA  = { "mint", "burn", "isLocked", "recent",
                      "getCardSkins", "getPlayerSkin", "setPlayerSkin" }

local _caps, _capsFor = nil, nil

-- คืนตารางบอกว่าเมธอดไหนมีจริง  คำนวณครั้งเดียวต่อ "ตัว Akacount ที่เจอ"
-- ถ้า Akacount ถูกโหลดทับ (reload ม็อด) ตัวชี้จะเปลี่ยน แล้วเราคำนวณใหม่ให้เอง
local function caps()
    local B = bank()
    if B == nil then return nil end
    if _caps and _capsFor == B then return _caps end

    local c = {}
    local function scan(list)
        for _, name in ipairs(list) do
            c[name] = (type(B[name]) == "function")
        end
    end
    scan(BANK_CORE); scan(BANK_ESCROW); scan(BANK_EXTRA)

    c.escrow = c.holdForPurchase and c.capturePurchase and c.releaseHold
    c.core   = true
    for _, name in ipairs(BANK_CORE) do
        if not c[name] then c.core = false end
    end

    _caps, _capsFor = c, B
    return c
end
S.bankCaps = caps

-- พิมพ์ผลตรวจ  เรียกตอนบูตและตอนแอดมินกดปุ่มตรวจในเกม
-- ข้อความเป็นอังกฤษล้วนตามกฎ  console.txt ของ PZ อ่านไทยไม่ออก
function S.bankReport()
    local B = bank()
    if not B then
        print("[Kuraya] BANK CHECK: Akacount is NOT loaded. Every CASH price is dead.")
        print("[Kuraya]   - check mod load order, Akacount must be enabled on the SERVER too")
        return false
    end
    local c = caps()
    local missing = {}
    for _, name in ipairs(BANK_CORE) do
        if not c[name] then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        print("[Kuraya] BANK CHECK: Akacount is loaded but missing " .. #missing ..
              " required function(s): " .. table.concat(missing, ", "))
        print("[Kuraya]   -> buying with CASH will fail until this is fixed")
        return false
    end
    if c.escrow then
        print("[Kuraya] BANK CHECK: ok - escrow path available (hold -> capture)")
    else
        local m2 = {}
        for _, name in ipairs(BANK_ESCROW) do
            if not c[name] then m2[#m2 + 1] = name end
        end
        print("[Kuraya] BANK CHECK: ok - but NO escrow (" .. table.concat(m2, ", ") ..
              "). Falling back to direct charge. Multi-currency prices are less safe.")
    end
    return true
end

-- ------------------------------------------------------------------------------
-- ปุ่มที่ม็อดอื่นฝากไว้ในจอ Account
--
-- ก่อนหน้านี้เป็นการผูกกับม็อดบิลค่าบ้านตรง ๆ ซึ่งผิด
-- Kuraya ไม่ควรรู้จักม็อดใดม็อดหนึ่งเป็นพิเศษ  หน้าที่ของเราคือ "ให้ที่ยืน"
-- ตอนนี้เลยเป็นทะเบียนกลาง ม็อดอะไรก็มาฝากปุ่มได้ รวมถึงบิลค่าบ้าน
--
-- ม็อดอื่นเรียกแบบนี้ (ฝั่งเซิร์ฟ ตอนโหลด):
--
--   if Kuraya and Kuraya.registerAccountButton then
--       Kuraya.registerAccountButton("hf_house_bills", {
--           label   = "House bills",
--           order   = 10,
--           badge   = function(key) return "2 due" end,   -- nil = ไม่โชว์
--           note    = function(key) return "700.00" end,  -- nil = ไม่โชว์
--           onClick = function(player) HFBills.openFor(player) end,
--       })
--   end
--
-- กติกาที่ยึด
--   1. ไคลเอนต์ส่งได้แค่ "id" เท่านั้น  เซิร์ฟหา onClick เองจากทะเบียน
--      ถ้าให้ไคลเอนต์ส่งชื่อฟังก์ชันมา = ให้ไคลเอนต์สั่งรันอะไรก็ได้บนเซิร์ฟ
--   2. badge / note / onClick ของม็อดอื่นห่อ pcall ทุกครั้ง
--      ม็อดอื่นพังต้องไม่ลากจอ Account ของเราพังตาม
--   3. เกินเพดานแล้วปฏิเสธพร้อม log บอกชื่อ  ไม่ใช่รับไว้เงียบ ๆ แล้วปุ่มตกจอ
-- ------------------------------------------------------------------------------
Kuraya = Kuraya or {}
local API = Kuraya

local _btn, _btnOrder = {}, {}

function API.registerAccountButton(id, def)
    if type(id) ~= "string" or id == "" then
        print("[Kuraya] registerAccountButton: id must be a non-empty string")
        return false
    end
    if type(def) ~= "table" or type(def.label) ~= "string" or def.label == "" then
        print("[Kuraya] registerAccountButton '" .. id .. "': label is required")
        return false
    end
    if not _btn[id] and #_btnOrder >= KR.ACCOUNT_BTN_MAX then
        print("[Kuraya] registerAccountButton '" .. id .. "' refused - the Account panel is full ("
              .. KR.ACCOUNT_BTN_MAX .. " buttons max)")
        return false
    end

    if not _btn[id] then _btnOrder[#_btnOrder + 1] = id end
    _btn[id] = {
        id      = id,
        label   = KR.trunc(def.label, 28),
        order   = tonumber(def.order) or 100,
        badge   = type(def.badge)   == "function" and def.badge   or nil,
        note    = type(def.note)    == "function" and def.note    or nil,
        onClick = type(def.onClick) == "function" and def.onClick or nil,
        source  = tostring(def.source or id),
    }
    return true
end

function API.unregisterAccountButton(id)
    if not _btn[id] then return false end
    _btn[id] = nil
    for i = #_btnOrder, 1, -1 do
        if _btnOrder[i] == id then table.remove(_btnOrder, i) end
    end
    return true
end

-- เรียกฟังก์ชันของม็อดอื่นแบบไม่ยอมให้มันลากเราตาย
-- คืนค่าที่ได้ หรือ nil พร้อมธง "พัง" เพื่อให้ UI ขึ้นสถานะ error ได้
local function safeCall(fn, arg)
    if fn == nil then return nil, false end
    local ok, res = pcall(fn, arg)
    if not ok then return nil, true end
    if res == nil then return nil, false end
    return KR.trunc(tostring(res), 20), false
end

-- แปลงทะเบียนเป็นรายการที่ส่งให้ไคลเอนต์วาด
function S.accountButtons(k)
    local rows = {}
    for i = 1, #_btnOrder do
        local b = _btn[_btnOrder[i]]
        if b then
            local badge, e1 = safeCall(b.badge, k)
            local note,  e2 = safeCall(b.note,  k)
            rows[#rows + 1] = {
                id    = b.id,
                label = b.label,
                order = b.order,
                badge = badge,
                note  = note,
                -- ม็อดที่ไม่มี onClick = ปุ่มโชว์ข้อมูลเฉย ๆ  ไม่ใช่ error
                dead  = (e1 or e2) and true or nil,
                act   = b.onClick ~= nil and true or nil,
            }
        end
    end
    -- order น้อยอยู่บน  เท่ากันเรียงตาม id เพื่อให้ลำดับคงที่ทุกเฟรม
    table.sort(rows, function(x, y)
        if x.order ~= y.order then return x.order < y.order end
        return x.id < y.id
    end)
    return rows
end

-- ------------------------------------------------------------------------------
-- การ์ดใหญ่ที่ม็อดอื่นฝากไว้ในหน้า Account  (บิลค่าบ้านคือเคสแรก)
--
-- ปุ่มแถวเดียวไม่พอสำหรับบิล  เจ้าของเซิร์ฟบอกไว้ชัดว่าอยากเห็น
-- "ใหญ่ ชัดเจน เห็นตัวเลขเลยว่าจ่ายเท่าไหร่" ซึ่งปุ่มที่มีแค่ label ทำไม่ได้
--
-- Kuraya ยังไม่รู้จักกติกาบ้านอยู่ดี และไม่ควรรู้
--   ม็อดบิลเป็นคนตอบว่า "คนนี้เป็นหัวบ้านหรือลูกบ้าน / ค้างเท่าไร / กดอะไรได้บ้าง"
--   Kuraya วาดตามที่บอก แล้วส่ง id ของปุ่มที่ถูกกดกลับไปให้ม็อดนั้นจัดการเอง
--
-- ม็อดอื่นเรียกแบบนี้ (ฝั่งเซิร์ฟ ตอนโหลด):
--
--   Kuraya.registerAccountCard("hf_house_bill", {
--       title = "House bill",
--       order = 10,
--       state = function(player)          -- เรียกทุกครั้งที่ sync  ต้องเร็ว
--           return {
--               amount     = 45000,                  -- หน่วยย่อย  0 = ไม่มีอะไรต้องจ่าย
--               cur        = "cash",
--               status     = KR.CARD_STATUS.DUE,     -- none / due / late / paid / sent
--               statusText = "DUE IN 2 DAYS",
--               head       = "House bill  period 12",
--               note       = "Rosewood Lot 14  ·  3 residents",
--               actions    = { { id = "pay", label = "Go to the payment page", style = "warn" } },
--           }
--       end,
--       onAction = function(player, actionId) ... end,
--   })
--
-- กติกาเดียวกับปุ่ม: ไคลเอนต์ส่งได้แค่ id  และทุก callback ห่อ pcall
-- ------------------------------------------------------------------------------
local _card, _cardOrder = {}, {}

function API.registerAccountCard(id, def)
    if type(id) ~= "string" or id == "" then
        print("[Kuraya] registerAccountCard: id must be a non-empty string")
        return false
    end
    if type(def) ~= "table" or type(def.state) ~= "function" then
        print("[Kuraya] registerAccountCard '" .. id .. "': state must be a function")
        return false
    end
    if not _card[id] and #_cardOrder >= KR.ACCOUNT_CARD_MAX then
        print("[Kuraya] registerAccountCard '" .. id .. "' refused - only "
              .. KR.ACCOUNT_CARD_MAX .. " cards fit in the Account column")
        return false
    end

    if not _card[id] then _cardOrder[#_cardOrder + 1] = id end
    _card[id] = {
        id       = id,
        title    = KR.trunc(def.title or id, 28),
        order    = tonumber(def.order) or 100,
        state    = def.state,
        onAction = type(def.onAction) == "function" and def.onAction or nil,
        source   = tostring(def.source or id),
    }
    return true
end

function API.unregisterAccountCard(id)
    if not _card[id] then return false end
    _card[id] = nil
    for i = #_cardOrder, 1, -1 do
        if _cardOrder[i] == id then table.remove(_cardOrder, i) end
    end
    return true
end

-- ล้างของที่ม็อดอื่นส่งมาให้เหลือเฉพาะรูปทรงที่เราวาดได้
-- ม็อดอื่นส่งอะไรแปลก ๆ มาต้องไม่ทำให้จอพัง และต้องไม่ยาวจนล้นการ์ด
local function cleanCardState(st)
    if type(st) ~= "table" then return nil end
    local ok = {
        [KR.CARD_STATUS.NONE] = true, [KR.CARD_STATUS.DUE]  = true,
        [KR.CARD_STATUS.LATE] = true, [KR.CARD_STATUS.PAID] = true,
        [KR.CARD_STATUS.SENT] = true,
    }
    local out = {
        amount     = math.max(0, math.floor(tonumber(st.amount) or 0)),
        cur        = KR.CUR_META[st.cur] and st.cur or KR.CUR.CASH,
        status     = ok[st.status] and st.status or KR.CARD_STATUS.NONE,
        statusText = st.statusText and KR.trunc(tostring(st.statusText), 34) or nil,
        head       = st.head and KR.trunc(tostring(st.head), 40) or nil,
        -- บรรทัดสั้นที่ "อธิบายตัวผู้เล่น" เช่น "หัวบ้าน · Rosewood Lot 14"
        -- ไปโผล่ใต้ชื่อผู้เล่นบนหัวคอลัมน์ขวา  เป็นฟิลด์แยกโดยตั้งใจ (ดู accWho)
        who        = st.who and KR.trunc(tostring(st.who), 40) or nil,
        note       = st.note and KR.trunc(tostring(st.note), 56) or nil,
        actions    = {},
    }
    for _, a in ipairs(st.actions or {}) do
        if type(a) == "table" and type(a.id) == "string" and a.id ~= "" and #out.actions < 2 then
            out.actions[#out.actions + 1] = {
                id       = a.id,
                label    = KR.trunc(tostring(a.label or a.id), 30),
                style    = tostring(a.style or "pri"),
                disabled = a.disabled and true or nil,
            }
        end
    end
    return out
end

function S.accountCards(player)
    local rows = {}
    for i = 1, #_cardOrder do
        local c = _card[_cardOrder[i]]
        if c then
            local okRun, st = pcall(c.state, player)
            if not okRun then
                print("[Kuraya] account card '" .. c.id .. "' errored: " .. tostring(st))
                rows[#rows + 1] = { id = c.id, title = c.title, order = c.order, dead = true }
            else
                local clean = cleanCardState(st)
                if clean then
                    clean.id, clean.title, clean.order = c.id, c.title, c.order
                    rows[#rows + 1] = clean
                end
            end
        end
    end
    -- ------------------------------------------------------------------------
    -- 0.6.8 — ร้าน **ไม่สังเคราะห์การ์ดบิลของตัวเองอีกแล้ว**
    --
    -- ประวัติของช่องนี้ เพราะมันเป็นบทเรียนเรื่องการแก้บั๊กผิดชั้น
    --   0.2   จองช่องไว้ให้ม็อดบิลที่ยังไม่มา  เขียนว่า "Coming soon"
    --   0.6.7 รู้ว่า HF_Tax ไม่มีวันมาลงทะเบียน (เขาไม่รู้จัก Kuraya)
    --         จึงให้ร้านสังเคราะห์การ์ดจริงจากข้อมูลที่เราอ่านเองได้
    --   0.6.8 เจ้าของเซิร์ฟ: "มันกินที่จัง แถมเป็นเหลี่ยม ๆ ไปหมด"
    --
    -- ที่ 0.6.7 พลาดคือมันแก้ "การ์ดโกหก" ด้วยการทำการ์ดให้พูดความจริง
    -- ทั้งที่คำถามจริงคือ **ควรมีการ์ดใบนี้ไหม** — ไม่ควร
    -- หน้า Account มีแผง HOUSE BILLS · TAX ที่พูดเรื่องเดียวกันอยู่แล้ว
    -- และแผงนั้นทำได้มากกว่า (มีสวิตช์หักอัตโนมัติในตัว) การ์ดจึงเป็นของซ้ำล้วน ๆ
    -- สองกล่องที่ตอบคำถามเดียวกันคือสองกล่องที่ต้องดูแลให้ตรงกันตลอดไป
    --
    -- ที่จองไว้ก็ถอดออกด้วย  ช่องที่เขียนว่า "เร็ว ๆ นี้" ให้ม็อดที่ไม่มีวันมา
    -- คือพื้นที่ที่เสียไปเปล่า ๆ ทุกเฟรม บนหน้าจอที่แน่นอยู่แล้ว
    --
    -- ทะเบียนยังอยู่ครบ  ม็อดไหนเรียก registerAccountCard(KR.BILLS_CARD_ID, ...)
    -- ก็ยังได้การ์ดของตัวเองเหมือนเดิม ลูปข้างบนวาดให้อยู่แล้ว
    -- ------------------------------------------------------------------------

    table.sort(rows, function(x, y)
        if x.order ~= y.order then return x.order < y.order end
        return x.id < y.id
    end)
    return rows
end

-- S.accountAction อยู่ใต้ alert()  ดูคอมเมนต์ตรงนั้นว่าทำไม


local function key(p)
    if not p then return nil end
    local ok, n = pcall(function() return p:getUsername() end)
    return (ok and n) and n:lower() or nil
end

-- ==============================================================================
-- คนนี้เป็นทีมงานไหม  ด่านเดียวที่ทั้งม็อดใช้ตัดสินสิทธิ์แอดมิน
--
-- 0.6.5b — เขียนใหม่ทั้งฟังก์ชัน เจ้าของเซิร์ฟรายงานว่า **ผู้เล่นทุกคนเห็นแท็บ ADMIN**
--
-- ของเดิมเป็นแบบนี้
--     lv = tostring(lv):lower()
--     return lv ~= "none" and lv ~= ""
--
-- มันคือ "บัญชีดำ" — อะไรก็ตามที่ไม่ใช่คำว่า none คือแอดมิน
-- ด่านความปลอดภัยที่เขียนเป็นบัญชีดำจะ **ล้มไปทางเปิด** เสมอ และนั่นคือสิ่งที่เกิดขึ้น
-- ค่าที่หลุดผ่านได้โดยที่เราไม่เคยเห็นมาก่อนแม้แต่ค่าเดียวก็พอ เช่น
--     "None " ที่มีช่องว่างต่อท้าย   ->  ไม่เท่ากับ "none"  = แอดมิน
--     ตัวเลข 0 จากบิลด์ที่คืนเป็น int ->  tostring(0) = "0"  = แอดมิน
--     Java object ที่ tostring ออกมาเป็น zombie.xxx@1a2b  = แอดมิน
--     "player" / "user" / "" ที่บิลด์ไหนสักบิลด์คืนมา      = แอดมิน
--
-- ตอนนี้เป็น "บัญชีขาว" — ต้องตรงกับระดับที่เรารู้จักเท่านั้น อย่างอื่นคือผู้เล่นธรรมดา
-- ล้มไปทางปิด: บิลด์ไหนคืนค่าแปลก ๆ ผลคือแอดมินตัวจริงไม่เห็นแท็บ ซึ่งเห็นได้ทันที
-- และแก้ได้ ต่างจากผู้เล่นทุกคนได้สิทธิ์แอดมินเงียบ ๆ ซึ่งไม่มีใครสังเกต
--
-- observer ไม่นับเป็นทีมงานที่นี่โดยตั้งใจ  มันคือสิทธิ์ "ดู" ไม่ใช่สิทธิ์ "แก้"
-- และหน้าจัดการของร้านเสกเงินเข้าเซิร์ฟได้
-- ==============================================================================
local STAFF_LEVEL = {
    admin     = true,
    moderator = true,
    overseer  = true,
    gm        = true,
}

-- พิมพ์ค่าดิบที่ getAccessLevel() คืนมา คนละครั้งเดียวต่อรอบเซิร์ฟ
--
-- ถ้าบิลด์ไหนคืนคำที่ไม่อยู่ในบัญชีขาว เราจะได้เห็นคำนั้นตรง ๆ ใน console
-- แทนที่จะต้องเดาอีกรอบ  บรรทัดเดียวนี้ประหยัดการไล่บั๊กไปทั้งวัน
local LEVEL_SEEN = {}

local function isStaff(player)
    if not player then return false end

    local ok, lv = pcall(function() return player:getAccessLevel() end)
    if not ok or lv == nil then return false end

    -- วงเล็บรอบ gsub จำเป็น  gsub คืนสองค่า ถ้าไม่ครอบ ค่าที่สองจะไหลไปที่อื่น
    local s = (tostring(lv):lower():gsub("%s", ""))

    local ok2, who = pcall(function() return player:getUsername() end)
    who = (ok2 and who) or "?"
    if LEVEL_SEEN[who] ~= s then
        LEVEL_SEEN[who] = s
        print("[Kuraya] access level of " .. tostring(who) .. " = '" .. tostring(lv) ..
              "' -> " .. (STAFF_LEVEL[s] and "STAFF" or "player"))
    end

    return STAFF_LEVEL[s] == true
end

-- **ห้ามตั้งชื่อ local ว่า isAdmin ในไฟล์นี้เด็ดขาด**
-- PZ มีฟังก์ชันโกลบอลชื่อ isAdmin() อยู่แล้ว ซึ่งไม่รับพารามิเตอร์และตอบเรื่อง
-- "เครื่องนี้" ไม่ใช่ "คนนี้"  ถ้าวันหนึ่งมีใครย้ายฟังก์ชันที่เรียก isAdmin(player)
-- ขึ้นไปอยู่เหนือบรรทัดที่ประกาศ local ตัวนั้น Lua จะไปหยิบโกลบอลของ PZ มาแทน
-- แล้วทุกคำสั่งของทุกคนจะถูกตัดสินด้วยสิทธิ์ของเครื่องเซิร์ฟเวอร์ = ผ่านหมด
-- และ lint กฎ 10 จับไม่ได้ เพราะ isAdmin เป็นชื่อโกลบอลของ PZ ที่ถูกต้องตามกฎ
-- ชื่อ isStaff ไม่ชนกับอะไรเลย กับดักนี้จึงถูกปิดถาวร (ดู lint กฎ 12)

local function alert(player, msg, tone)
    sendServerCommand(player, KR.MODULE, KR.CMD.ALERT, { msg = msg, tone = tone or "info" })
end
S.alert = alert

-- ต้องประกาศ "ใต้" alert() เท่านั้น
-- Lua ผูก local ตอนคอมไพล์  ถ้าฟังก์ชันนี้อยู่เหนือ `local function alert`
-- คำว่า alert ในตัวมันจะกลายเป็น global (= nil) แล้วพังตอนรันจริงเท่านั้น
-- ซึ่งแปลว่าเทสโหลดไฟล์ผ่าน แต่ผู้เล่นกดปุ่มแล้วเซิร์ฟ error เงียบ ๆ
function S.accountAction(player, args)
    -- การ์ดใหญ่ (บิลค่าบ้าน ฯลฯ)  ส่งมาเป็น card + action ไม่ใช่ id เดี่ยว ๆ
    local cid = args and args.card
    if type(cid) == "string" and cid ~= "" then
        local c = _card[cid]
        if not c then
            return alert(player, "That card is no longer available.", "bad")
        end
        if not c.onAction then
            return alert(player, tostring(c.title) .. " has nothing to do.", "info")
        end
        local aid = args.action
        if type(aid) ~= "string" or aid == "" then return end
        local okRun, err = pcall(c.onAction, player, aid)
        if not okRun then
            print("[Kuraya] account card '" .. cid .. "' action '" .. aid ..
                  "' errored: " .. tostring(err))
            return alert(player, tostring(c.title) .. " failed.", "bad")
        end
        return S.sync(player)
    end

    local id = args and args.id
    if type(id) ~= "string" or id == "" then return end

    local b = _btn[id]
    if not b then
        -- ไคลเอนต์ส่ง id ที่ไม่มีในทะเบียน  อาจเป็นม็อดที่เพิ่งถูกถอด
        -- หรืออาจเป็นคนพยายามยิงคำสั่งมั่ว  ทั้งสองกรณีตอบเหมือนกัน
        return alert(player, "That button is no longer available.", "bad")
    end
    if not b.onClick then
        return alert(player, tostring(b.label) .. " has nothing to open.", "info")
    end

    local ok, err = pcall(b.onClick, player)
    if not ok then
        print("[Kuraya] account button '" .. id .. "' errored: " .. tostring(err))
        return alert(player, tostring(b.label) .. " failed to open.", "bad")
    end
end

-- ==============================================================================
-- โครงฐานข้อมูล  schema 2
--
-- ของเดิมกระจายข้อมูลผู้เล่นไว้สามที่ (points / names / ui) คีย์เดียวกันทั้งหมด
-- ทุกครั้งที่เพิ่มฟิลด์ใหม่ก็ต้องไปสร้างตารางที่สี่ ซึ่งจะพังตอนลบผู้เล่นทิ้ง
-- schema 2 รวมเป็นตารางเดียว d.players[key] แล้วย้ายของเก่าให้อัตโนมัติ
--
--   d.v        = เลข schema
--   d.meta     = { nextId, seeded, createdAt }
--   d.catalog  = [id] -> สูตรเสก        (ของในร้าน)
--   d.markets  = [id] -> { x,y,z,name } (แผงตลาดสด)
--   d.players  = [key] -> {
--                    disp      ชื่อตัวพิมพ์จริง
--                    hf        แต้ม HF ที่ Kuraya เป็นเจ้าของ
--                    sent      { d = วันที่, n = ยอดที่โอนไปวันนั้น }
--                    ui        { x, y, locked }  ตำแหน่งปุ่มลอย
--                    bought    [itemId] -> { n, p }  โควตาที่ใช้ไปในรอบ p
--                    firstSeen / lastSeen
--                }
--   d.services = คิวงานของ SERVICE
--   d.hflog    = ring buffer ประวัติโอนแต้ม
--
-- คีย์ผู้เล่นเป็นตัวพิมพ์เล็กเสมอ  ชื่อจริงเก็บใน disp
-- ==============================================================================
local function blank()
    return {
        v        = KR.SCHEMA,
        meta     = { nextId = 1, seeded = false, createdAt = 0 },
        catalog  = {},
        markets  = {},
        players  = {},
        services = {},
        hflog    = {},
        feed     = {},                       -- ป้ายไฟหน้าร้าน
        auction  = { lots = {}, next = 1 },  -- ประมูล
        credit   = {},                       -- สัญญาเงินกู้รายคน
        rotate   = { day = -1, ids = {} },   -- ของเข้าใหม่ของวันนี้
        hfpack   = { packs = {}, reqs = {}, next = 1 },   -- แพ็ก HF Point
        till     = { cash = 0, taken = 0, log = {} },     -- ลิ้นชักร้าน  รายได้ที่แอดมินถอนได้

        -- 0.7.0
        stats    = { day = {} },                          -- ยอดเงินเข้า/ออกรวมรายวัน
        board    = { cats = {}, list = {}, next = 1 },    -- กระดานราคาสินค้าโลก
    }
end

-- ย้ายเซฟเก่ามาโครงใหม่  ต้องทำครั้งเดียวและต้องทำก่อนใครแตะข้อมูล
local function migrate(d)
    local from = tonumber(d.v) or 0
    if from >= KR.SCHEMA then return end

    d.meta     = d.meta     or { nextId = 1 }
    d.catalog  = d.catalog  or {}
    d.markets  = d.markets  or {}
    d.services = d.services or {}
    d.hflog    = d.hflog    or {}
    d.players  = d.players  or {}

    -- v2 -> v3  ตารางใหม่ล้วน  ไม่มีข้อมูลเก่าให้ย้าย แค่สร้างให้ครบ
    d.feed    = d.feed    or {}
    d.auction = d.auction or { lots = {}, next = 1 }
    d.credit  = d.credit  or {}
    d.rotate  = d.rotate  or { day = -1, ids = {} }
    d.cats     = d.cats     or {}

    -- v3 -> v4  แพ็ก HF Point  ตารางใหม่ล้วนเหมือนกัน
    --
    -- ของที่ตั้งไว้เป็น "ลดราคากี่ชั่วโมง" ไม่ต้องย้าย  e.saleEndsAt เก็บเป็นเวลาจริง
    -- ที่ราคาจะเด้งกลับอยู่แล้ว ไม่ได้เก็บระยะเวลา  หน่วยที่เปลี่ยนคือหน่วยของ
    -- "ช่องกรอก" เท่านั้น ไม่ใช่หน่วยของข้อมูลที่เก็บไว้
    d.till = d.till or { cash = 0, taken = 0, log = {} }
    d.till.cash  = tonumber(d.till.cash)  or 0
    d.till.taken = tonumber(d.till.taken) or 0
    d.till.log   = d.till.log or {}

    d.hfpack = d.hfpack or { packs = {}, reqs = {}, next = 1 }
    d.hfpack.packs = d.hfpack.packs or {}
    d.hfpack.reqs  = d.hfpack.reqs  or {}
    d.hfpack.next  = tonumber(d.hfpack.next) or 1

    -- v1 -> v2  รวม points / names / ui / bought เข้า players
    local function P(k)
        d.players[k] = d.players[k] or { hf = 0 }
        return d.players[k]
    end
    for k, v in pairs(d.points or {}) do P(k).hf   = tonumber(v.hf) or 0
                                         P(k).sent = v.sent end
    for k, v in pairs(d.names  or {}) do P(k).disp = v end
    for k, v in pairs(d.ui     or {}) do P(k).ui   = v end
    for k, v in pairs(d.bought or {}) do P(k).bought = v end

    -- v4 -> v5  ตารางใหม่ล้วนทั้งสองอัน  ไม่มีข้อมูลเก่าให้ย้าย แค่สร้างให้ครบ
    --
    -- **เติมอย่างเดียว ไม่ล้างอะไรเลย** แคตตาล็อก · แต้ม HF · ประวัติ · ลิ้นชัก · แพ็ก
    -- อยู่ครบเหมือนเดิมทุกตัว  (เจ้าของเซิร์ฟถามข้อนี้ตรง ๆ ตอน 0.6.16 และคำตอบ
    --  ต้องเป็นด่าน ไม่ใช่คำพูด — smoke มีเทสต์ที่ยัดเซฟรุ่นก่อนแล้วให้โค้ดใหม่โหลด)
    d.stats = d.stats or { day = {} }
    d.stats.day = d.stats.day or {}

    d.board = d.board or { cats = {}, list = {}, next = 1 }
    d.board.cats = d.board.cats or {}
    d.board.list = d.board.list or {}
    d.board.next = tonumber(d.board.next) or 1

    d.points, d.names, d.ui, d.bought = nil, nil, nil, nil
    d.v = KR.SCHEMA
    print("[Kuraya] migrated DB  schema " .. from .. " -> " .. KR.SCHEMA)
end

local function db()
    local d = ModData.getOrCreate(KR.DB_KEY)
    if not d.v then
        for k, v in pairs(blank()) do d[k] = v end
        d.meta.createdAt = getTimestamp and getTimestamp() or os.time()
        d.needSeed = true
        print("[Kuraya] created fresh DB  schema " .. KR.SCHEMA)
    else
        migrate(d)
    end
    -- กันเซฟที่ถูกแก้มือจนฟิลด์หาย
    d.meta     = d.meta     or { nextId = 1 }
    d.catalog  = d.catalog  or {}
    d.markets  = d.markets  or {}
    d.players  = d.players  or {}
    d.services = d.services or {}
    d.hflog    = d.hflog    or {}
    d.feed     = d.feed     or {}
    d.auction  = d.auction  or { lots = {}, next = 1 }
    d.credit   = d.credit   or {}
    d.rotate   = d.rotate   or { day = -1, ids = {} }
    d.cats     = d.cats     or {}

    -- seed ต้องทำหลัง db() คืนค่าครบแล้ว  แต่ seedCatalog ประกาศทีหลัง
    -- เลยตั้งธงไว้แล้วให้ ensureSeed เก็บกวาดตอนเรียกใช้จริง
    return d
end

local seedCatalog     -- ประกาศไว้ก่อน  ตัวจริงอยู่ข้างล่าง (กับดัก local function ของ Lua)
local function ensureSeed()
    local d = db()
    if d.needSeed and seedCatalog then
        d.needSeed = nil
        seedCatalog(d, getTimestamp and getTimestamp() or os.time())
    end
    return d
end

-- แถวของผู้เล่นหนึ่งคน  สร้างให้ถ้ายังไม่มี
local function P(k)
    if not k then return nil end
    local d = db()
    local row = d.players[k]
    if not row then
        row = { hf = 0, firstSeen = getTimestamp and getTimestamp() or 0 }
        d.players[k] = row
    end
    return row
end
-- เปิดให้ไฟล์เซิร์ฟเวอร์ไฟล์อื่น (ประมูล / เงินกู้) เข้าถึงของกลางได้
-- ไฟล์พวกนั้นแยกออกไปเพราะ KR_Server.lua ยาวเกินจะอ่านรู้เรื่องแล้ว
-- แต่มันต้องใช้ db / key / bank / alert ชุดเดียวกัน ห้ามมีสำเนาที่สอง
S.P     = P
S.db    = db
S.key   = key
S.bank  = bank
S.isStaff = isStaff
S.isAdmin = isStaff   -- ชื่อเดิม  ไฟล์เซิร์ฟไฟล์อื่นเรียกผ่านชื่อนี้อยู่ ไม่มีกับดัก local ที่นั่น

-- จำชื่อไว้ตั้งแต่ล็อกอินครั้งแรก  ผู้เล่นที่ยังไม่เคยเข้ามาจะไม่มีสิทธิ์เป็นผู้รับ
-- กันเคสพิมพ์ชื่อผิดแล้วแต้มลอยหายเข้าบัญชีที่ไม่มีตัวตน
-- ชื่อที่เอาไปโชว์ให้คนอื่นเห็น  ถ้าอ่านไม่ได้ค่อยตกไปที่คีย์
local function dispOf(player)
    local k = key(player)
    if not k then return "someone" end
    return (P(k).disp) or k
end

local function touch(player)
    local k = key(player)
    if not k then return nil end
    local row = P(k)
    local ok, disp = pcall(function() return player:getUsername() end)
    if ok and disp then row.disp = disp end
    row.lastSeen = getTimestamp and getTimestamp() or 0

    -- สกิลอยู่บนตัวละคร ไม่ได้อยู่ในฐานข้อมูลของม็อด  และอ่านได้เฉพาะคนที่ออนไลน์
    -- เก็บไว้ทุกครั้งที่เห็นตัว  ไม่งั้นหน้าสกิลจะตอบได้แค่ "ใครที่ออนอยู่ตอนนี้มี 8-10"
    -- ซึ่งเป็นคำตอบของคำถามคนละข้อกับที่เจ้าของเซิร์ฟถาม
    if type(S.skillSnapshot) == "function" then
        pcall(S.skillSnapshot, player)
    end
    return k
end
S.touch = touch


-- ==============================================================================
-- ของตั้งต้น
--
-- ร้านที่ว่างเปล่าคือร้านที่เทสไม่ได้  แอดมินต้องกรอกของเองสิบชิ้นก่อนถึงจะรู้ว่าระบบทำงานไหม
-- ใส่ของชุดเริ่มต้นให้เลยตอนสร้าง DB ครั้งแรก แล้วแอดมินค่อยลบหรือแก้ทีหลัง
--
-- ลงครั้งเดียวตลอดชีพ ดูจาก meta.seeded  ลบของทิ้งแล้วมันจะไม่กลับมาอีก
-- ราคาทั้งหมดกรอกเป็นหน่วยที่คนอ่านเข้าใจ (บาท / แต้ม) ไม่ใช่สตางค์
-- ==============================================================================
-- ของตั้งต้น
--
-- ปิดเป็นค่าเริ่มต้นตั้งแต่ 0.2.5
-- เจ้าของเซิร์ฟบอกตรง ๆ ว่าอยากเริ่มจากร้านว่างแล้วลงของจริงเอง
-- ของตั้งต้นมีประโยชน์แค่ตอนลองเล่นครั้งแรก  หลังจากนั้นมันคือขยะที่ต้องมาไล่ลบ
--
-- เปิดกลับได้ที่ sandbox: Kuraya.SeedCatalog
-- (เปิดแล้วมีผลเฉพาะเซิร์ฟที่ยังไม่เคย seed เท่านั้น  ไม่งอกทับของที่ลงไว้แล้ว)
local function seedEnabled()
    return KR.svBool("SeedCatalog", false)
end

function seedCatalog(d, nowTs)
    if d.meta.seeded then return 0 end
    if not seedEnabled() then
        -- ทำเครื่องหมายไว้เลยว่าผ่านขั้นตอนนี้แล้ว
        -- ไม่งั้นถ้าวันหลังมีคนเปิดสวิตช์ ของ 12 ชิ้นจะโผล่มากลางเซิร์ฟที่รันมาสองเดือนแล้ว
        d.meta.seeded = true
        print("[Kuraya] starter catalog is off - shop starts empty (SandboxVars.Kuraya.SeedCatalog)")
        return 0
    end

    local S_ = {
        { id = "kr_water",  name = "Water Bottle x4",      cat = "food",     item = "Base.WaterBottleFull",
          stock = 40, restock = KR.RESTOCK.DAILY,
          pay = { { cur = KR.CUR.CASH, price = 45 } } },

        { id = "kr_canned", name = "Canned Food Crate x10", cat = "food",    item = "Base.TinnedBeans",
          stock = 25,
          pay = { { cur = KR.CUR.CASH, price = 320 }, { cur = KR.CUR.HF, price = 40 } } },

        { id = "kr_bandage", name = "Bandage x5",          cat = "medical",  item = "Base.Bandage",
          stock = 60,
          pay = { { cur = KR.CUR.CASH, price = 120 } } },

        { id = "kr_antibio", name = "Antibiotics x2",      cat = "medical",  item = "Base.Antibiotics",
          stock = 12, quota = 2, quotaPeriod = KR.PERIOD.DAILY,
          pay = { { cur = KR.CUR.CASH, price = 900 }, { cur = KR.CUR.HF, price = 110 },
                  { cur = KR.CUR.CP, price = 40 } } },

        { id = "kr_hammer", name = "Hammer",               cat = "general",  item = "Base.Hammer",
          stock = 20,
          pay = { { cur = KR.CUR.CASH, price = 260 } } },

        { id = "kr_nails",  name = "Nails x50",            cat = "building", item = "Base.Nails",
          stock = 50, restock = KR.RESTOCK.WEEKLY,
          pay = { { cur = KR.CUR.CASH, price = 180 } } },

        { id = "kr_plank",  name = "Plank x10",            cat = "building", item = "Base.Plank",
          stock = 50,
          pay = { { cur = KR.CUR.CASH, price = 220 } } },

        { id = "kr_axe",    name = "Fire Axe",             cat = "weapon",   item = "Base.Axe",
          stock = 3, rare = true, quota = 1, quotaPeriod = KR.PERIOD.WEEKLY,
          pay = { { cur = KR.CUR.HF, price = 900 }, { cur = KR.CUR.CP, price = 300 },
                  { { cur = KR.CUR.CP, price = 90 }, { cur = KR.CUR.CASH, price = 4000 } } } },

        { id = "kr_pistol", name = "M9 Pistol + 2 Mag",    cat = "weapon",   item = "Base.Pistol",
          stock = 2, rare = true,
          pay = { { cur = KR.CUR.CP, price = 850 }, { cur = KR.CUR.HF, price = 2400 } } },

        { id = "kr_gas",    name = "Fuel Delivery 200L",   cat = "service",  kind = KR.KIND.SERVICE,
          pay = { { cur = KR.CUR.CASH, price = 950 } } },

        { id = "kr_dart",   name = "Chevalier Dart",       cat = "vehicle",  kind = KR.KIND.VEHICLE,
          stock = 2, rare = true, vehicle = "Base.CarNormal",
          pay = { { cur = KR.CUR.CASH, price = 22400 }, { cur = KR.CUR.HF, price = 2600 } } },

        -- ของลดราคาตัวอย่าง  จะได้เห็นหน้า Sale ทำงานตั้งแต่เข้าครั้งแรก
        { id = "kr_deal",   name = "Sardines x6",          cat = "food",     item = "Base.TinnedSardines",
          stock = 30, quota = 2,
          saleBp = 4000, saleEndsAt = nowTs + 3 * KR.DAY_SEC,
          pay = { { cur = KR.CUR.CASH, price = 200 } } },
    }

    local n = 0
    for i = 1, #S_ do
        local e = S_[i]
        e.listedAt = nowTs - (#S_ - i)     -- ให้ลำดับ "ลงล่าสุด" ดูสมจริง
        e.enabled  = true
        d.catalog[e.id] = e
        n = n + 1
    end

    d.meta.seeded = true
    print("[Kuraya] seeded catalog with " .. n .. " items")
    return n
end


-- ==============================================================================
-- สะพานไป SafeHouse ของ PZ
--
-- ทำไมต้องมีไฟล์ส่วนนี้แทนที่จะเรียกตรง ๆ
--   ชื่อเมธอดของ SafeHouse ต่างกันระหว่างบิลด์ และเราไม่มีทางยืนยันจากที่นี่ได้
--   กฎของโปรเจกต์ข้อ 5 ใน PZ-B42-MP-item-transfer-RULE บอกไว้แล้วว่า
--   "เมธอด Java ที่ไม่แน่ใจว่ามีไหม -> type(obj.method) == 'function' ก่อนเรียก
--    pcall อย่างเดียวไม่พอ เพราะ Kahlua ยัง dump stack trace เต็ม ๆ ถึงจะจับ error ได้"
--   (ISRemoveItemTool.removeItem เคย dump 1,332 ครั้งต่อ session แบบนั้น)
--
-- ทุกอย่างในนี้จึงเช็กก่อนเรียกทุกครั้ง และ **ล้มไปทางปิด**
--   หาเซฟเฮาส์ไม่เจอ = กู้ไม่ได้  ไม่ใช่ = กู้ได้เลย
--   ระบบปล่อยกู้ที่เดาไปทางอนุญาตตอนไม่รู้ข้อมูล คือระบบที่เสกเงินให้คนที่หาไม่เจอ
--
-- ถ้าบิลด์ไหนชื่อไม่ตรงจริง ๆ เจ้าของเซิร์ฟปิด sandbox LoanRequireSafehouse ได้
-- แล้วเงื่อนไขข้ออื่นยังทำงานเหมือนเดิม
-- ==============================================================================
local function m(obj, name)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[name] end)
    if ok and type(v) == "function" then return v end
    return nil
end

-- คืน object เซฟเฮาส์ของผู้เล่นคนนี้  หรือ nil
local function safehouseOf(player)
    if not player then return nil end
    local SH = SafeHouse
    if type(SH) ~= "table" and type(SH) ~= "userdata" then return nil end

    -- ทางที่ตรงที่สุด  ถามจากตัวผู้เล่นเลย
    local f = m(SH, "hasSafehouse")
    if f then
        local ok, sh = pcall(f, player)
        if ok and sh then return sh end
    end

    -- ทางสำรอง  ถามจากช่องที่ยืนอยู่
    local g = m(SH, "getSafeHouse")
    if g then
        local okSq, sq = pcall(function() return player:getSquare() end)
        if okSq and sq then
            local ok2, sh2 = pcall(g, sq)
            if ok2 and sh2 then return sh2 end
        end
    end
    return nil
end

-- ไอดีของเซฟเฮาส์  ใช้เป็นคีย์ในตารางของเราเอง
--
-- ไม่มี getId ทุกบิลด์  ตกไปใช้พิกัดกับขนาดซึ่งไม่เปลี่ยนตลอดอายุของเซฟเฮาส์นั้น
-- (ย้ายเซฟเฮาส์ไม่ได้ ต้องลบแล้วตั้งใหม่ ซึ่งควรนับเป็นคนละหลังอยู่แล้ว)
local function safehouseId(sh)
    local f = m(sh, "getId")
    if f then
        local ok, v = pcall(f, sh)
        if ok and v then return "sh" .. tostring(v) end
    end
    local parts = {}
    for _, name in ipairs({ "getX", "getY", "getW", "getH" }) do
        local g = m(sh, name)
        if not g then return nil end
        local ok, v = pcall(g, sh)
        if not ok or v == nil then return nil end
        parts[#parts + 1] = tostring(v)
    end
    return "sh:" .. table.concat(parts, ":")
end

-- รายชื่อสมาชิก  เจ้าของนับเป็นสมาชิกด้วยเสมอ
local function safehouseMembers(sh)
    local out, seen = {}, {}
    local function push(nm)
        if type(nm) ~= "string" or nm == "" then return end
        nm = nm:lower()
        if seen[nm] then return end
        seen[nm] = true
        out[#out + 1] = nm
    end

    local go = m(sh, "getOwner")
    if go then
        local ok, v = pcall(go, sh)
        if ok then push(v) end
    end

    local gp = m(sh, "getPlayers")
    if gp then
        local ok, list = pcall(gp, sh)
        if ok and list then
            local okN, n = pcall(function() return list:size() end)
            for i = 0, (okN and n or 0) - 1 do
                local okV, v = pcall(function() return list:get(i) end)
                if okV then push(v) end
            end
        end
    end
    return out
end

-- ------------------------------------------------------------------------------
-- จดว่าเห็นคนนี้อยู่ในเซฟเฮาส์หลังนี้ครั้งแรกเมื่อไร
--
-- PZ ไม่ได้เก็บ "วันที่เข้าเป็นสมาชิก" ให้  เราจึงต้องจดเอง
-- ผลที่ตามมาและต้องยอมรับตรง ๆ: สมาชิกที่มีอยู่ก่อนอัปเดตนี้เริ่มนับจากศูนย์วันนี้
-- ทางเลือกอื่นคือเดาว่าเขาอยู่มานานแล้ว ซึ่งเป็นการแจกสิทธิ์กู้จากข้อมูลที่ไม่มีอยู่จริง
--
-- เรียกจาก S.sync  จึงเดินทุกสองวินาทีตอนเปิดร้าน และตอนล็อกอิน
-- ------------------------------------------------------------------------------
-- เปิดให้ KR_Bills ใช้  มันต้องรู้ว่า "ตอนนี้ใครเป็นเจ้าของบ้านหลังนี้"
-- ซึ่งเป็นคำถามที่ตอบจากตัวบิลไม่ได้ ในบิลเก็บชื่อเจ้าของ ณ วันที่ออกบิลเท่านั้น
S.safehouseOf = safehouseOf

function S.safehouseTouch(player)
    local k = key(player); if not k then return nil end
    local sh = safehouseOf(player)
    if not sh then return nil end
    local id = safehouseId(sh)
    if not id then return nil end

    local d = db()
    d.shouse = d.shouse or {}
    local row = d.shouse[id]
    if not row then
        row = { since = {} }
        d.shouse[id] = row
    end
    local nowTs = getTimestamp and getTimestamp() or os.time()
    if not row.since[k] then row.since[k] = nowTs end
    row.seenAt = nowTs
    return id, sh, row
end

-- ผ่านเงื่อนไขเซฟเฮาส์ไหม  คืน ok, เหตุผล, id, สมาชิก
function S.safehouseGate(player)
    if not KR.loanNeedsSafehouse() then return true, nil, nil, nil end

    local k = key(player)
    local id, sh, row = S.safehouseTouch(player)
    if not id then
        return false, "You need to be in a safehouse to borrow. Stand inside yours and try again."
    end

    local nowTs = getTimestamp and getTimestamp() or os.time()
    local since = (row.since or {})[k] or nowTs
    local need  = math.floor(KR.loanOpt("SAFEHOUSE_DAYS")) * KR.DAY_SEC
    local been  = nowTs - since
    if been < need then
        local left = math.max(1, math.ceil((need - been) / KR.DAY_SEC))
        return false, "You have to be in this safehouse for " ..
                      math.floor(KR.loanOpt("SAFEHOUSE_DAYS")) ..
                      " real days before you can borrow. About " .. left ..
                      " more to go."
    end

    return true, nil, id, safehouseMembers(sh)
end

-- หนี้คงค้างรวมของทุกคนในเซฟเฮาส์
--
-- นับจาก c.out ซึ่งเป็นยอดที่ยังต้องคืน (รวมดอกเบี้ยแล้ว) ของทุกสัญญาที่ยังไม่ปิด
-- ไม่ได้นับจากยอดที่กู้ไป เพราะสิ่งที่เซิร์ฟแบกความเสี่ยงอยู่คือยอดที่ยังไม่ได้คืน
function S.safehouseDebt(members)
    local d = db()
    local total = 0
    for _, nm in ipairs(members or {}) do
        local c = (d.credit or {})[nm]
        if c then total = total + math.max(0, math.floor(tonumber(c.out) or 0)) end
    end
    return total
end

-- ------------------------------------------------------------------------------
-- ยอดสามสกุล  อ่านจากเจ้าของแต่ละสกุล ไม่เก็บซ้ำเอง
-- ------------------------------------------------------------------------------
function S.balances(player)
    local k = key(player)
    local d = db()
    local B = bank()

    local cash = 0
    if B and B.available then cash = B.available(k) end

    local cp = KR.tr.get(player)

    local hf = k and (P(k).hf or 0) or 0
    return { [KR.CUR.CASH] = cash, [KR.CUR.HF] = hf, [KR.CUR.CP] = cp }
end

function S.addHF(player, n)
    local k = key(player); if not k then return end
    local row = P(k)
    row.hf = math.max(0, (row.hf or 0) + math.floor(n or 0))
end

-- ==============================================================================
-- โควตา  ซื้อได้คนละกี่ชิ้นต่อรอบ
--
-- ยอดที่ใช้ไปเก็บคู่กับ "คีย์รอบ" ที่ใช้ตอนนั้น  พออ่านเจอว่าคีย์ไม่ตรงกับรอบปัจจุบัน
-- แปลว่าขึ้นรอบใหม่แล้ว ให้ถือว่ายอดเป็นศูนย์ทันทีโดยไม่ต้องมีใครไปไล่ล้างตาราง
-- ==============================================================================
function S.quotaLeft(player, e, nowTs)
    local q = KR.quotaOf(e)
    if q <= 0 then return nil end          -- nil = ไม่จำกัด  ต่างจาก 0 ที่แปลว่าเต็มแล้ว

    local k = key(player)
    if not k then return 0 end

    local pr  = P(k)
    local row = pr.bought and pr.bought[e.id]
    if not row then return q end
    if row.p ~= KR.quotaPeriodKey(e, nowTs) then return q end   -- คนละรอบ = เริ่มนับใหม่
    return math.max(0, q - (tonumber(row.n) or 0))
end

local function quotaConsume(player, e, nowTs)
    if KR.quotaOf(e) <= 0 then return end
    local k = key(player); if not k then return end
    local pr = P(k)
    pr.bought = pr.bought or {}

    local pk  = KR.quotaPeriodKey(e, nowTs)
    local row = pr.bought[e.id]
    if not row or row.p ~= pk then
        row = { n = 0, p = pk }
        pr.bought[e.id] = row
    end
    row.n = (tonumber(row.n) or 0) + 1
end

-- คืนสิทธิ์ที่เพิ่งกินไป  ใช้ตอนจ่ายเงินผ่านแล้วส่งของไม่ได้จนต้องคืนเงิน
--
-- ลดเฉพาะตอนคีย์รอบที่เก็บไว้ยังเป็นรอบปัจจุบัน  ถ้าข้ามรอบไปแล้วยอดที่เห็นอยู่
-- เป็นของรอบใหม่ ไปลดมันคือแจกสิทธิ์ฟรีให้รอบที่ผู้เล่นยังไม่ได้ใช้
-- ข้อนี้สำคัญที่สุดกับ quotaPeriod = "ever" เพราะรอบนั้นไม่มีวันรีเซ็ตให้เอง
-- ซื้อของที่ส่งไม่ได้ครั้งเดียวก็เสียสิทธิ์ถาวร
local function quotaRelease(player, e, nowTs)
    if KR.quotaOf(e) <= 0 then return end
    local k = key(player); if not k then return end
    local pr  = P(k)
    local row = pr.bought and pr.bought[e.id]
    if not row then return end
    if row.p ~= KR.quotaPeriodKey(e, nowTs) then return end
    row.n = math.max(0, (tonumber(row.n) or 0) - 1)
end

-- ==============================================================================
-- จ่ายเงินหนึ่งตัวเลือก  อาจเป็นสกุลเดียวหรือหลายสกุลพร้อมกัน
--
-- ของหนึ่งชิ้นตั้งราคาได้หลายแบบ เช่น "HF 420" หรือ "$ 4,200" หรือ "CP 90 + $ 500"
-- ตัวเลือกที่มีหลายสกุลคือจุดที่เงินหายได้ง่ายที่สุดในม็อดนี้
-- ถ้าหักสกุลแรกผ่านแล้วสกุลที่สองไม่ผ่าน ผู้เล่นเสียเงินฟรีโดยไม่ได้ของ
--
-- ลำดับที่ใช้ตั้งใจเรียงตาม "คืนยากแค่ไหน" จากง่ายไปยาก
--   1. CASH  Akacount เป็นของเรา กันไว้ได้ ปล่อยคืนสะอาด ไม่กระทบบัญชีแยกประเภท
--   2. HF    ตารางของเราเอง บวกกลับได้ตรง ๆ
--   3. CP    อยู่ในม็อด HF Town Rank คืนแล้วต้องอ่านกลับมาเช็กว่าเข้าจริงไหม
--
-- ของที่คืนยากที่สุดจึงหักเป็นอันสุดท้าย  ถ้ามันล้ม เรายังไม่ได้แตะมันเลย
-- มีแต่ของฝั่งเราที่ต้องถอย ซึ่งถอยได้แน่นอน
--
-- ทั้งฟังก์ชันรันจบในเทิร์นเดียว ไม่มี yield ระหว่างทาง จึงไม่มีใครแทรกกลางได้
-- ==============================================================================
local function payOption(player, e, opt, nowTs, ref)
    local k = key(player)
    if not k then return false, "no player" end

    local need = KR.optionCost(opt, e, nowTs)

    -- ==========================================================================
    -- ทำไมไม่ใช้ next(need)
    --
    -- **นี่คือบรรทัดที่ทำให้ "กดซื้อแล้วเงินไม่หัก ของไม่เข้า" มาตลอดทุกเวอร์ชัน**
    --
    -- Kahlua (ตัว Lua ที่ PZ ใช้) ไม่ได้ลงทะเบียน `next` เป็นฟังก์ชันโกลบอล
    -- ทั้งที่ `pairs` / `ipairs` / `select` มีครบ  บรรทัดนี้จึงเป็น
    --     java.lang.RuntimeException: Object tried to call nil in payOption
    -- ทุกครั้งที่มีคนกดซื้อ ตั้งแต่บรรทัดที่สี่ของฟังก์ชัน
    --
    -- ผลที่ตามมาอธิบายอาการได้ครบทุกข้อ
    --   ระเบิดก่อนแตะเงิน      -> เงินไม่หัก
    --   ระเบิดก่อนส่งของ       -> ของไม่เข้า
    --   ระเบิดก่อน alert ตัวแรก -> ผู้เล่นไม่เห็นอะไรเลย เงียบสนิท
    --   pcall ใน on() กลืนไว้   -> ขึ้นแต่ใน console ของเซิร์ฟที่ไม่มีใครเปิดดูตอนนั้น
    --
    -- ทำไมกว่าจะเจอถึงนานขนาดนี้
    --   `next` ถูกใช้ **ที่เดียวในทั้งม็อด** คือบรรทัดนี้ จึงไม่เคยมีเส้นทางไหน
    --   พิสูจน์ว่ามันใช้ได้จริง  และเทสฝั่งเรารันบน Lua 5.3 มาตรฐานซึ่งมี next ครบ
    --   = เทสยืนยันโลกที่ไม่มีอยู่จริง แบบเดียวกับเรื่องลำดับโหลดไฟล์
    --
    -- บทเรียนที่กว้างกว่าบรรทัดนี้: ฟังก์ชันมาตรฐานของ Lua ที่ทั้งม็อดเรียกอยู่ที่เดียว
    -- คือฟังก์ชันที่ยังไม่เคยถูกพิสูจน์ว่ามีอยู่บนเอนจินนี้
    -- ตอนนี้มีด่าน lint ห้ามใช้ next / loadstring / setfenv / getfenv แล้ว
    -- ==========================================================================
    local hasPrice = false
    for _ in pairs(need) do hasPrice = true; break end
    if not hasPrice then return false, "no price on this option" end

    -- เช็กให้ครบทุกสกุลก่อน  เคสส่วนใหญ่จบตรงนี้โดยไม่ต้องแตะเงินเลย
    local can, short = KR.canAfford(opt, e, S.balances(player), nowTs)
    if not can then
        local m = KR.CUR_META[short]
        return false, "not enough " .. ((m and m.label) or tostring(short))
    end

    local heldCash, tookHF, tookCash = nil, 0, 0

    local function rollback()
        if heldCash then
            local B = bank()
            if B and B.releaseHold then pcall(B.releaseHold, heldCash) end
            heldCash = nil
        end
        if tookCash > 0 then
            -- เดินทางสำรอง (ไม่มี escrow) เงินถูกตัดจริงไปแล้ว ต้องโอนกลับ ไม่ใช่แค่ปลดล็อก
            local B = bank()
            if B and B.payTo then
                pcall(B.payTo, "SYS:SHOP", k, tookCash, "shop", "rollback " .. tostring(ref), "system")
            else
                print("[Kuraya] !! cannot roll back " .. tookCash .. " cash for " .. k)
            end
            tookCash = 0
        end
        if tookHF > 0 then
            S.addHF(player, tookHF)
            tookHF = 0
        end
    end

    -- 1. CASH  แค่กันไว้ ยังไม่ตัดออกจากบัญชี
    --
    -- ทางหลักคือ escrow ของ Akacount  แต่ถ้าเซิร์ฟรัน Akacount รุ่นที่ยังไม่มี escrow
    -- ของเดิมจะตอบว่า "Akacount not loaded" ซึ่ง **โกหก** — มันโหลดอยู่ แค่ไม่มีเมธอดนั้น
    -- แล้วเจ้าของเซิร์ฟก็ไปไล่หาสาเหตุผิดที่ (นี่คืออาการ "กดซื้อไม่ติด เงินไม่หัก" ที่รายงานมา)
    --
    -- ตอนนี้จึงถอยไปใช้ charge ตรง ๆ ได้  ยอมรับความเสี่ยงที่ต่ำกว่านิดหน่อยในเคสหลายสกุล
    -- (ตัดเงินแล้ว CP อาจล้ม -> ต้องโอนคืน ซึ่งเราทำใน rollback แล้ว)
    -- ดีกว่าปิดร้านทั้งเซิร์ฟเพราะเมธอดเดียวหาย
    local nCash = need[KR.CUR.CASH] or 0
    if nCash > 0 then
        local B = bank()
        if not B then return false, "Akacount is not loaded on this server" end
        local c = caps()
        if not c.available or not c.charge then
            return false, "Akacount is missing charge/available - tell the server owner"
        end
        if (B.available(k) or 0) < nCash then
            return false, "not enough CASH"
        end

        if c.escrow then
            local id, err = B.holdForPurchase(k, nCash, ref)
            if not id then
                rollback()
                return false, "cash hold refused: " .. tostring(err)
            end
            heldCash = id
        else
            local okCh, errCh = pcall(B.charge, k, nCash, "shop", tostring(ref), "card")
            if not okCh then
                rollback()
                return false, "cash charge refused: " .. tostring(errCh)
            end
            tookCash = nCash
        end
    end

    -- 2. HF
    local nHF = need[KR.CUR.HF] or 0
    if nHF > 0 then
        local d = db()
        local row = P(k)
        if (row.hf or 0) < nHF then
            rollback()
            return false, "not enough HF"
        end
        row.hf = row.hf - nHF
        tookHF = nHF
    end

    -- 3. CP  ม็อดนอก หักท้ายสุด
    local nCP = need[KR.CUR.CP] or 0
    if nCP > 0 then
        local okCP, errCP = KR.tr.deduct(player, nCP)
        if not okCP then
            rollback()
            return false, "cp: " .. tostring(errCP)
        end
    end

    -- 4. ครบทุกสกุลแล้ว ค่อยยึดเงินที่กันไว้เข้าคลัง
    if heldCash then
        local B = bank()
        local okCap = B and B.capturePurchase and B.capturePurchase(heldCash)
        if not okCap then
            -- ไม่ควรเกิดเลย  แต่ถ้าเกิดต้องคืนทุกอย่างที่หักไปแล้วให้ครบ
            if nCP > 0 then KR.tr.refund(player, nCP) end
            rollback()
            return false, "payment failed while settling"
        end
        heldCash = nil
    end

    -- เดินทางสำรองมาถึงตรงนี้ = ตัดเงินจริงไปแล้วและทุกสกุลผ่านหมด  ไม่ต้องถอยอีก
    tookCash = 0

    -- ==========================================================================
    -- 5. เงินสดที่ตัดไปแล้วเข้า "ลิ้นชักร้าน"
    --
    -- เจ้าของเซิร์ฟสั่งว่า "ถ้ามีคนซื้อของใน shop เป็น cash ให้เก็บเข้าเป็นของแอดมิน
    -- ที่ถอนได้ในหน้า account"
    --
    -- ทำไมจดเป็นตัวเลขในฐานของเราเอง แทนที่จะย้ายเงินเข้าบัญชีกลางใน ledger
    --   capturePurchase ของ Akacount ไม่รับปลายทาง มันแค่ "ตัด"  และ charge ก็เหมือนกัน
    --   จะบังคับให้มันโอนเข้าบัญชีกลางต้องแก้ Akacount ซึ่งเราไม่แตะซอร์สม็อดอื่น
    --   ตอนถอน เราจึง mint กลับเข้าบัญชีแอดมินตามยอดที่จดไว้ ซึ่งเป็นการกลับทิศ
    --   ของการตัดที่เพิ่งเกิดขึ้นพอดี  ผลรวมของ ledger จึงไม่ได้ถูกเสก
    --
    -- ยอดนี้ไม่ใช่เงินที่ "มีอยู่จริง" ในบัญชีไหน มันคือสิทธิ์ในการ mint ตามยอดที่ขายได้
    -- จึงต้องกันไม่ให้ถอนเกินยอด และต้องจดทุกครั้งที่ถอนพร้อมชื่อคนถอน
    -- ==========================================================================
    local nCashPaid = need[KR.CUR.CASH] or 0
    if nCashPaid > 0 then
        local d = db()
        d.till = d.till or { cash = 0, taken = 0, log = {} }
        d.till.cash = (tonumber(d.till.cash) or 0) + nCashPaid
    end

    return true
end

-- ------------------------------------------------------------------------------
-- Fresh Market
--   เห็นรายการได้ทุกที่ แต่ซื้อได้เฉพาะตอนยืนอยู่ที่ tile
-- ------------------------------------------------------------------------------
function S.marketAt(player)
    local d  = db()
    local sq = player and player:getSquare()
    if not sq then return nil end
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
    for id, m in pairs(d.markets) do
        if m.z == pz
           and math.abs(m.x - px) <= KR.MARKET_RANGE
           and math.abs(m.y - py) <= KR.MARKET_RANGE then
            return id, m
        end
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- ซื้อ
-- ------------------------------------------------------------------------------
-- คืนเงินที่เพิ่งเก็บไป
--
-- ใช้ตอนจ่ายผ่านแล้วแต่ส่งของไม่ได้  ต้องคืนให้ครบทุกสกุลที่หักไป
-- ไม่ใช่ระบบ escrow เพราะเงินถูก capture ไปแล้ว  นี่คือการโอนกลับตรง ๆ
local function refundOption(player, e, opt, nowTs, ref)
    local k = key(player); if not k then return false end
    local need = KR.optionCost(opt, e, nowTs)

    local nCash = need[KR.CUR.CASH] or 0
    if nCash > 0 then
        local B = bank()
        if B and B.payTo then
            pcall(B.payTo, "SYS:SHOP", k, nCash, "shop", "refund " .. tostring(ref), "system")
        else
            print("[Kuraya] !! cannot refund " .. nCash .. " cash to " .. k .. " - bank offline")
        end
    end

    local nHF = need[KR.CUR.HF] or 0
    if nHF > 0 then S.addHF(player, nHF) end

    local nCP = need[KR.CUR.CP] or 0
    if nCP > 0 then KR.tr.refund(player, nCP) end

    -- คืนเงินเต็มจำนวนเพราะร้านทำงานไม่สำเร็จ = ยอดสะสมต้องถอยด้วย
    -- ไม่งั้นซื้อของที่ส่งไม่ได้รัว ๆ แล้วไต่ Spending Tier ฟรีโดยไม่ได้เสียอะไรเลย
    S.unlogSpend(k, KR.spendValue(need))
    return true
end

-- ------------------------------------------------------------------------------
-- ส่งของให้ผู้เล่น
--
-- นี่คือชิ้นส่วนที่หายไปมาตลอด  เดิมมีแค่คอมเมนต์ TODO
-- ผู้เล่นจ่ายเงินแล้วไม่ได้ของ ซึ่งแย่กว่าไม่มีร้านเลย
--
-- กฎของ MP (PZ-B42-MP-item-transfer-RULE.md):
--   **เซิร์ฟเวอร์เท่านั้นที่สร้างไอเทมได้**  ไคลเอนต์ทำไม่ได้เลย
--   สร้างเสร็จต้อง sendAddItemToContainer ไม่งั้นเครื่องผู้เล่นไม่เห็นจนกว่าจะ relog
--
-- คืนจำนวนที่ทำได้จริง  ถ้าได้ไม่ครบ คนเรียกต้องคืนเงินส่วนที่ขาด
local function giveItems(player, fullType, count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if type(fullType) ~= "string" or fullType == "" then return 0, "no item type" end

    local inv = player and player:getInventory()
    if not inv then return 0, "no inventory" end

    local sm = getScriptManager and getScriptManager()
    if not sm then return 0, "no script manager" end
    -- ชื่อไอเทมผิดคือความผิดของแอดมิน  ต้องบอกให้ชัด ไม่ใช่เงียบแล้วผู้เล่นเสียเงินฟรี
    -- ห่อ pcall เพราะ FindItem ของบางบิลด์โยนเมื่อชื่อไม่มีโมดูลนำหน้า ("Axe" แทน "Base.Axe")
    local okFind, found = pcall(function() return sm:FindItem(fullType) end)
    if not okFind or not found then return 0, "unknown item '" .. fullType .. "'" end

    -- instanceItem อาจคืน nil ได้จริง ๆ ในบิลด์ 42 ถ้าสคริปต์ของไอเทมยังเขียนแบบ B41
    -- (`Type = Normal` แทน `ItemType = base:normal`)  ItemFactory คืน null แล้ว NPE
    -- เคสนี้ไม่ใช่ชื่อผิด แต่คือไอเทมของม็อดอื่นที่พัง  ต้องแยกข้อความให้ต่างกัน
    -- ไม่งั้นแอดมินจะไปนั่งแก้ชื่อที่ถูกอยู่แล้ว
    local made = 0
    local firstErr = nil
    local madeItems = {}
    for _ = 1, count do
        local okMake, it = pcall(instanceItem, fullType)
        if not okMake then
            firstErr = firstErr or ("engine refused to build '" .. fullType ..
                                    "' (" .. tostring(it) .. ")")
            break
        end
        if not it then
            firstErr = firstErr or ("'" .. fullType .. "' exists but cannot be created" ..
                                    " - its item script is probably still B41 style")
            break
        end
        inv:AddItem(it)
        -- MP: ไคลเอนต์สร้างไอเทมเองไม่ได้  ต้องประกาศจากเซิร์ฟ ไม่งั้นของโผล่ตอน relog เท่านั้น
        --
        -- **ลำดับสำคัญ**  ประกาศก่อน แล้วค่อยซิงก์ฟิลด์  (0.6.13)
        -- ของเดิมซิงก์ก่อนประกาศ  ไคลเอนต์จึงได้แพ็กเก็ต SyncItemFields ของไอเทม
        -- ที่ตัวเองยังไม่รู้จัก แล้วพังที่ฝั่งเขา:
        --   NullPointerException: Cannot invoke "InventoryItem.hasSharpness()"
        --   because "item" is null at SyncItemFieldsPacket.parse
        -- (เจอในไฟล์ console ที่เจ้าของเซิร์ฟส่งมา — เป็นของเรา ไม่ใช่ของม็อดอื่น)
        if type(sendAddItemToContainer) == "function" then
            pcall(sendAddItemToContainer, inv, it)
        end
        if U_hasMethod(it, "syncItemFields") then pcall(function() it:syncItemFields() end) end
        made = made + 1
        madeItems[made] = it
    end
    -- คืนตัวของที่สร้างไปด้วย  ชุดสินค้าต้องเก็บของคืนได้ถ้าบรรทัดหลัง ๆ ล้ม
    -- คนเรียกเดิมรับแค่สองค่า ค่าที่สามจึงไม่กระทบใคร
    return made, firstErr, madeItems
end

-- ประมูลใช้ตัวเดียวกันตอนผู้ชนะมารับของ
-- ห้ามเขียนทางส่งของทางที่สอง  ทางที่สองคือทางที่ไม่มีใครแก้ตอนเจอบั๊ก
S.giveItems = giveItems

-- ==============================================================================
-- ชุดสินค้า  (0.6.12)
--
-- **ตรวจให้ครบก่อนส่งชิ้นแรก**
-- ชุดที่ส่งไปได้ครึ่งเดียวบังคับให้เราตัดสินใจว่าจะเก็บของคืนหรือปล่อยไป
-- ซึ่งเป็นการตัดสินใจที่ไม่ควรมีอยู่ตั้งแต่แรก  ตรวจก่อนทำให้กรณีนั้นแทบไม่เกิด
--
-- แต่ "แทบไม่เกิด" ไม่เท่ากับ "ไม่เกิด" — เอนจินยังปฏิเสธกลางทางได้
-- ตอนนั้นเราเก็บของคืนแล้วคืนเงิน  เก็บคืนได้จริงเพราะเราถือตัวของที่สร้างไว้อยู่
-- ไม่ใช่ไปไล่หาในกระเป๋าด้วยชื่อชนิด (ซึ่งจะไปโดนของเดิมที่เขามีอยู่ก่อนแล้ว)
-- ==============================================================================

-- ชุดนี้ส่งมอบได้ไหม  คืน nil ถ้าได้  คืนข้อความถ้าไม่ได้
function S.setCheck(entry)
    if not KR.isSet(entry) then return "not a set" end
    local sm = getScriptManager and getScriptManager()
    for i, ln in ipairs(entry.set) do
        if ln.vehicle then
            if type(S.carKnown) ~= "function" then
                return "line " .. i .. ": the vehicle add-on is not loaded"
            end
            if not S.carKnown(ln.vehicle) then
                return "line " .. i .. ": '" .. tostring(ln.vehicle) .. "' is not a vehicle here"
            end
        elseif ln.pet then
            -- สัตว์เดินทางเดียวกับรถทุกประการ  (0.6.16)
            if type(S.petKnown) ~= "function" then
                return "line " .. i .. ": the pet add-on is not loaded"
            end
            if not S.petKnown(ln.pet) then
                return "line " .. i .. ": '" .. tostring(ln.pet) .. "' is not an animal here"
            end
        elseif ln.item then
            if sm then
                local okF, found = pcall(function() return sm:FindItem(tostring(ln.item)) end)
                if not okF or not found then
                    return "line " .. i .. ": this game has no item '" .. tostring(ln.item) .. "'"
                end
            end
        else
            return "line " .. i .. ": points at nothing"
        end
    end
    return nil
end

function S.setDeliver(player, entry)
    local bad = S.setCheck(entry)
    if bad then return false, bad end

    local given = {}
    local function rollback()
        -- เก็บคืนย้อนลำดับ  ไม่จำเป็นเชิงตรรกะ แต่ทำให้ log อ่านง่ายตอนไล่ปัญหา
        local inv = player and player:getInventory()
        for i = #given, 1, -1 do
            local it = given[i]
            if inv then
                if type(sendRemoveItemFromContainer) == "function" then
                    pcall(sendRemoveItemFromContainer, inv, it)
                end
                pcall(function() inv:Remove(it) end)
            end
        end
    end

    for i, ln in ipairs(entry.set) do
        local n = math.max(1, math.floor(tonumber(ln.n) or 1))

        if ln.vehicle or ln.pet then
            -- รถกับสัตว์ต่างกันแค่ "ใครออกใบ"  ที่เหลือเหมือนกันทุกบรรทัด
            -- รวมเป็นทางเดียวเพราะสองทางที่เหมือนกันจะเริ่มต่างกันตอนมีคนแก้ทางเดียว
            local giver, what, missing
            if ln.vehicle then
                giver, what, missing = S.carGiveSlip, ln.vehicle, "the vehicle add-on is not loaded"
            else
                giver, what, missing = S.petGiveSlip, ln.pet, "the pet add-on is not loaded"
            end
            for _ = 1, n do
                local slip, cerr = nil, missing
                if type(giver) == "function" then
                    slip, cerr = giver(player, what, entry.name)
                end
                if not slip then
                    rollback()
                    return false, "line " .. i .. ": " .. tostring(cerr)
                end
                given[#given + 1] = slip
            end
        else
            local made, err, items = giveItems(player, ln.item, n)
            for _, it in ipairs(items or {}) do given[#given + 1] = it end
            if made < n then
                rollback()
                return false, "line " .. i .. ": " .. tostring(err or "partial delivery")
            end
        end
    end

    return true, nil
end

-- ------------------------------------------------------------------------------
-- เก็บของออกจากกระเป๋าผู้เล่น  ทิศทางตรงข้ามกับ giveItems
--
-- ใช้ตอนผู้เล่นลงประมูลของตัวเอง  ของต้องออกจากมือ **ตั้งแต่ตอนลงขาย**
-- ไม่ใช่ตอนขายได้  ไม่งั้นคนขายเอาของไปทิ้ง/ขายที่อื่นแล้วคนชนะจ่ายเงินได้ลม
--
-- กฎของ MP (PZ-B42-MP-item-transfer-RULE.md) ที่ต้องทำให้ครบ
--   1. เซิร์ฟต้องลบจาก **สำเนาของเซิร์ฟ** ไม่ใช่แค่บอกไคลเอนต์ให้ลบ
--      ลบแต่ฝั่งไคลเอนต์ = ของกลับมาตอน relog = ได้เงินฟรีโดยยังมีของ
--   2. isEquipped() ครอบคลุมแค่ของในมือ  เสื้อผ้าที่ "สวมอยู่" ยังโผล่ในลิสต์กระเป๋า
--      ต้องถาม getWornItems() ต่างหาก  แหวนบนนิ้วคือจุดที่เจ็บที่สุด
--      เพราะไม่มีใครคิดว่ามันเป็นของที่สวมอยู่
--   3. เก็บรายการให้ครบก่อนแล้วค่อยลบ  ลบระหว่างวนลูปทำให้ index เลื่อน
-- ------------------------------------------------------------------------------
local function isWorn(player, item)
    local ok, worn = pcall(function() return player:getWornItems() end)
    if not ok or not worn then return false end
    local okN, n = pcall(function() return worn:size() end)
    if not okN then return false end
    for i = 0, n - 1 do
        local slot = worn:get(i)
        if slot then
            local okI, it = pcall(function() return slot:getItem() end)
            if okI and it == item then return true end
        end
    end
    return false
end

function S.takeItems(player, fullType, count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    local inv = player and player:getInventory()
    if not inv then return 0, "no inventory" end

    local okL, list = pcall(function() return inv:getItems() end)
    if not okL or not list then return 0, "cannot read your bag" end

    local found = {}
    local okN, n = pcall(function() return list:size() end)
    for i = 0, (okN and n or 0) - 1 do
        if #found >= count then break end
        local it = list:get(i)
        local ft
        if it then
            local okT, t = pcall(function() return it:getFullType() end)
            ft = okT and t or nil
        end
        if ft == fullType then
            local skip = false
            for _, m in ipairs({ "isFavorite", "isEquipped" }) do
                if not skip and U_hasMethod(it, m) then
                    local okV, v = pcall(function() return it[m](it) end)
                    if okV and v then skip = true end
                end
            end
            if not skip and isWorn(player, it) then skip = true end
            if not skip then found[#found + 1] = it end
        end
    end

    if #found < count then
        return 0, "you only have " .. #found .. " free to list"
    end

    for _, it in ipairs(found) do
        local c = it:getContainer() or inv
        if type(sendRemoveItemFromContainer) == "function" then
            pcall(sendRemoveItemFromContainer, c, it)
        end
        pcall(function() c:Remove(it) end)
        pcall(function() c:setDrawDirty(true) end)
    end
    return #found
end

-- PZ ไม่มี hasMethod ให้  เขียนเองเพราะ pcall ทุกที่อ่านไม่รู้เรื่อง
function U_hasMethod(obj, name)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj[name] end)
    return ok and type(v) == "function"
end

-- ------------------------------------------------------------------------------
-- ทางลัดสำหรับรายการที่ "ไม่ใช่การซื้อของ"
--
-- ทำไมต้องมี: ถึง 0.4.2 มีแค่ S.buy ที่เดียวในทั้งม็อดที่เขียนประวัติลงมา
-- ประมูล เงินกู้ และการโอนแต้ม ย้ายเงินจริงทุกวันแต่ไม่เคยฝากรอยไว้เลยสักบรรทัด
-- ผู้เล่นเปิดหน้า Account แล้วเห็นตารางที่ไม่ขยับ จึงรายงานว่า "ประวัติไม่อัปเดต"
-- ซึ่งเป็นคำอธิบายที่ตรงกับสิ่งที่เกิดขึ้นเป๊ะ
--
-- ตัวนี้ไม่แตะ p.spent ของ Spending Tier  ตั้งใจแบบนั้น
-- tier ตอบคำถามว่า "อุดหนุนร้านไปเท่าไร" การโอนแต้มให้เพื่อนหรือกู้เงินไม่ใช่การอุดหนุนร้าน
-- (S.logSpend บวก p.spent เฉพาะแถวที่ inc ไม่เป็นจริงและมี v > 0  ตรงนี้จึงส่ง value = 0)
--
-- คีย์เป็นสตริง ไม่ใช่ IsoPlayer  ผู้รับโอนอาจออฟไลน์อยู่ตอนที่เงินถึง
local function logEvent(k, kind, name, amount, cur, incoming, status)
    if not k then return end
    S.logSpend(k, {
        k      = kind,
        name   = name,
        status = status,
        amount = amount,
        cur    = cur,
        value  = 0,          -- ไม่นับเข้า Spending Tier
        inc    = incoming or nil,
    })
end
S.logEvent = logEvent

-- ทุกทางออกที่ล้มเหลวของ S.buy ต้องผ่านตัวนี้
--
-- เหตุผล: อาการที่รายงานมาคือ "กดแล้วไม่มีอะไรเกิดขึ้น"  ซึ่งเป็นไปได้สองแบบ
--   ก) เซิร์ฟตอบ alert มาแล้วแต่ผู้เล่นไม่เห็น (HaloText อยู่หลังหน้าต่างร้าน)
--   ข) เซิร์ฟไม่เคยได้รับคำสั่งเลย
-- สองอย่างนี้แก้คนละทางกันสิ้นเชิง แต่หน้าจอผู้เล่นเหมือนกันเป๊ะ
-- พิมพ์ลง console ฝั่งเซิร์ฟทุกครั้ง = แยกสองเคสนี้ออกจากกันได้ในบรรทัดเดียว
local function buyFail(player, who, id, msg)
    print("[Kuraya] BUY  " .. tostring(who) .. "  " .. tostring(id) .. "  REFUSED: " .. tostring(msg))
    return alert(player, msg, "bad")
end

-- ------------------------------------------------------------------------------
-- บัญชีที่โดนแช่แข็งเพราะหนี้
--
-- KR_Credit ตั้งธง c.frozen ไว้ตั้งแต่แรกและมี S.creditFrozen ให้เรียก
-- แต่ **ไม่เคยมีใครเรียกมันเลย**  ผลคือคำโฆษณาของระบบเงินกู้ที่ว่า
-- "ผิดนัดสามงวดแล้วซื้อของ/ประมูล/โอนไม่ได้" ไม่เป็นความจริงสักข้อ
-- ผู้เล่นกู้เงินมาแล้วไม่คืนก็ยังเล่นต่อได้ปกติทุกอย่าง = ระบบเงินกู้คือเงินฟรี
--
-- ต่อสายให้ครบทั้งสามทางที่เงินออก  ไฟล์นี้เป็นเจ้าของทั้งสามทางอยู่แล้ว
-- (ประมูลอยู่คนละไฟล์แต่เรียกตัวนี้ผ่าน S. เหมือนกัน)
--
-- ต้องบอกด้วยว่า **แก้ยังไง** ไม่ใช่แค่บอกว่าถูกล็อก
-- คนที่อ่านข้อความนี้คือคนที่กำลังงงว่าทำไมกดอะไรไม่ได้เลย
function S.frozenBlock(player, what)
    -- ล็อกร้านเพราะติดลบหนัก  ตรวจก่อน เพราะมันหนักกว่าและแก้คนละทาง
    --
    -- สองอย่างนี้ต้องพูดคนละประโยค
    --   แช่แข็งเพราะผิดนัด  -> "ไปจ่ายงวดสิ" ผู้เล่นแก้เองได้
    --   ล็อกเพราะติดลบ      -> "ไปหาแอดมิน" ผู้เล่นแก้เองไม่ได้ ต่อให้จ่ายหนี้หมด
    -- บอกผิดข้อ = ส่งคนไปทำสิ่งที่ไม่ช่วยอะไร แล้วเขาจะเชื่อข้อความอื่นน้อยลงด้วย
    if S.shopLocked and S.shopLocked(player) then
        alert(player, "Your shop access is locked - your balance went too far into the red. " ..
                      "Only an admin can unlock it. Paying the loan off is not enough.", "bad")
        return true
    end
    if not (S.creditFrozen and S.creditFrozen(player)) then return false end
    alert(player, "Your account is frozen for missed loan payments. " ..
                  "Pay an instalment on the CREDIT page to use " .. tostring(what) .. " again.", "bad")
    return true
end

function S.buy(player, args)
    local d  = db()
    local id = args and args.id
    local entry = id and d.catalog[id]
    local who = key(player) or "?"

    print("[Kuraya] BUY  " .. who .. "  id=" .. tostring(id) ..
          "  opt=" .. tostring(args and args.opt))

    -- ด่านหนี้ก่อนด่านอื่นทั้งหมด  ห้ามให้คนที่โดนแช่แข็งเดินไปถึงจุดที่แตะเงินได้
    if S.frozenBlock(player, "the shop") then
        print("[Kuraya] BUY  " .. who .. "  " .. tostring(id) .. "  REFUSED: account frozen")
        return
    end

    -- ของที่ปิดอยู่ซื้อไม่ได้ ไม่ว่าแพ็กเก็ตจะมาจากไหน
    --
    -- ไอดีของที่ซ่อนไว้ไม่ได้ถูกส่งให้ไคลเอนต์ตั้งแต่ต้น (ดู S.sync) แต่ไอดีเป็นแค่สตริง
    -- คนที่เคยเห็นตอนของยังเปิดขาย หรือเดาเอาก็ยิงคำสั่งซื้อมาได้
    -- ด่านที่กันจริงคือด่านนี้ ไม่ใช่การที่ไคลเอนต์ไม่มีปุ่มให้กด
    --
    -- ข้อความต้องไม่บอกผู้เล่นว่า "มีของชิ้นนี้อยู่แต่ถูกซ่อน"
    -- แค่บอกว่าไม่มี  แอดมินเท่านั้นที่ได้เหตุผลจริง เพราะเป็นคนที่แก้ได้
    if not entry or entry.enabled == false then
        if entry and isStaff(player) then
            return buyFail(player, who, id, "That listing is hidden from players. Turn it on in the admin page to sell it.")
        end
        return buyFail(player, who, id, "That listing is gone.")
    end

    -- ของจาก Fresh Market ต้องยืนอยู่ที่ tile
    if entry.market then
        local hereId = S.marketAt(player)
        if hereId ~= entry.market then
            return buyFail(player, who, id, "You must be at the market stall to buy this.")
        end
    end

    if entry.stock ~= nil and entry.stock <= 0 then
        return buyFail(player, who, id, "Sold out.")
    end

    -- ผู้เล่นเลือกว่าจะจ่ายด้วยแบบไหน  ไคลเอนต์ส่งมาแค่ "หมายเลขตัวเลือก"
    -- ราคาคำนวณใหม่ที่นี่ทั้งหมด  ไม่แตะตัวเลขที่ไคลเอนต์ส่งมาเลยแม้แต่ค่าเดียว
    local opts = KR.payOptions(entry)
    if #opts == 0 then return buyFail(player, who, id, "This listing has no price set.") end

    local oi  = math.floor(tonumber(args and args.opt) or 1)
    local opt = opts[oi]
    if not opt then return buyFail(player, who, id, "That payment option is gone.") end

    -- ส่วนลดต้องคิดจากเวลาจริงฝั่งเซิร์ฟเวอร์  ไม่ใช่เวลาที่ไคลเอนต์บอกมา
    local nowTs = getTimestamp and getTimestamp() or os.time()

    -- โควตาต้องเช็กก่อนแตะเงิน  ไม่งั้นหักไปแล้วค่อยมาบอกว่าซื้อไม่ได้
    local left = S.quotaLeft(player, entry, nowTs)
    if left ~= nil and left <= 0 then
        return buyFail(player, who, id, "You have reached your limit for this round.")
    end

    local ok, err = payOption(player, entry, opt, nowTs, "buy:" .. tostring(id))
    if not ok then return buyFail(player, who, id, "Cannot pay: " .. tostring(err)) end

    quotaConsume(player, entry, nowTs)
    if entry.stock ~= nil then
        entry.stock = entry.stock - 1
        -- หมดพอดี  ตั้งเวลาเข้าใหม่ไว้เลย จะได้โชว์ "back in 2 days" ได้
        -- ของหมดไม่หายไปจากลิสต์  มันกลายเป็นสีเทาพร้อมกำหนดเข้าใหม่
        if entry.stock <= 0 and entry.restockAt == nil then
            local days = KR.restockDays(entry)
            entry.restockAt = nowTs + days * KR.DAY_SEC
            entry.restockTo = entry.restockTo or math.max(1, math.floor(tonumber(entry.stock0) or 5))
        end
    end

    -- ส่งของจริง
    --
    -- ถ้าส่งไม่สำเร็จต้อง **คืนเงิน** ไม่ใช่ปล่อยผ่าน
    -- จ่ายแล้วไม่ได้ของคือบั๊กที่ทำลายความเชื่อใจเร็วที่สุดในเกมที่มีเศรษฐกิจ
    local kind = entry.kind or KR.kindOfCat(entry.cat)

    -- ประวัติการใช้จ่าย + ยอดสะสมสำหรับ tier
    -- บันทึกหลังจ่ายเงินสำเร็จแล้ว  ถ้าส่งของไม่สำเร็จค่อยถอนคืนตอนคืนเงิน
    local need     = KR.optionCost(opt, entry, nowTs)
    local spendVal = KR.spendValue(need)
    local mainCur, mainAmt = KR.CUR.CASH, 0
    for _, c in ipairs({ KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP }) do
        if (need[c] or 0) > 0 and (need[c] or 0) * KR.sortWeight(c) > mainAmt * KR.sortWeight(mainCur) then
            mainCur, mainAmt = c, need[c]
        end
    end

    if KR.isSet(entry) then
        -- ---- ชุดสินค้า  ได้ครบทุกบรรทัดหรือไม่ได้เลย  (0.6.12) ---------------
        -- ชุดมาก่อน kind เสมอ  รายการที่มีของในชุดคือชุด ไม่ว่าหมวดจะเป็นอะไร
        -- e.item / e.vehicle ของตัวรายการเองถูกข้ามไป — ของที่ได้คือของในชุดเท่านั้น
        local okSet, serr = S.setDeliver(player, entry)
        if not okSet then
            refundOption(player, entry, opt, nowTs, "buy:" .. tostring(id))
            quotaRelease(player, entry, nowTs)
            if entry.stock ~= nil then
                entry.stock = entry.stock + 1
                if entry.stock > 0 then entry.restockAt, entry.restockTo = nil, nil end
            end
            S.sync(player)
            return buyFail(player, who, id, "Could not hand over the set (" ..
                           tostring(serr) .. "). You were refunded.")
        end

        S.logSpend(key(player), { k = KR.LOG.BUY, name = entry.name or id,
                                  status = "delivered", amount = mainAmt, cur = mainCur,
                                  value = spendVal, t = nowTs })
        print("[Kuraya] BUY  " .. who .. "  " .. tostring(id) .. "  OK  set of " ..
              #entry.set .. " lines  paid " .. tostring(mainAmt) .. " " .. tostring(mainCur))
        alert(player, "Bought " .. tostring(entry.name) .. " (" ..
                      KR.setCount(entry) .. " items).", "good")

    elseif kind == KR.KIND.SERVICE then
        -- บริการไม่ใช่ของ  เข้าคิวให้สตาฟไปทำ แล้วบอกผู้เล่นว่าสั่งแล้ว
        d.services = d.services or {}
        d.services[#d.services + 1] = {
            t = nowTs, who = key(player), disp = dispOf(player),
            id = id, name = entry.name, done = false,
        }
        S.logSpend(key(player), { k = KR.LOG.ORDER, name = entry.name or id,
                                  status = "queued", amount = mainAmt, cur = mainCur,
                                  value = spendVal, t = nowTs })
        alert(player, "Ordered " .. tostring(entry.name) ..
                      ". Staff will deliver it.", "good")

    elseif KR.isSlipKind(kind) then
        -- ร้านจ่ายรถเป็น "ใบรถ" และจ่ายสัตว์เป็น "ใบสัตว์"  ไม่ใช่ของจริงทันที
        --
        -- ร้านอยู่ในอาคาร รถเกิดในอาคารแล้วขยับไม่ออก  ร้านจึงเดาที่จอดให้ไม่ได้
        -- สัตว์ที่เกิดในร้านก็เดินหายไปก่อนคนซื้อจะพากลับบ้านได้
        -- ใบย้ายการเลือกจุดไปให้คนที่รู้ว่าจะเอาไว้ตรงไหน คือคนซื้อ
        -- รายละเอียดอยู่ใน KR_Cars.lua และ KR_Pets.lua
        local isPet = (kind == KR.KIND.PET)
        local giver = isPet and S.petGiveSlip or S.carGiveSlip
        local what  = isPet and entry.pet or entry.vehicle
        local slip, cerr = nil,
            isPet and "the pet add-on is not loaded on this server"
                  or  "the vehicle add-on is not loaded on this server"
        if type(giver) == "function" then
            slip, cerr = giver(player, what, entry.name)
        end

        if not slip then
            -- ส่งของไม่ได้ = คืนเงินทั้งก้อน  เหมือนทางของไอเทมทุกประการ
            -- **ห้ามกินเงินแล้วเงียบ** ไม่ว่าจะพังด้วยเหตุผลอะไร
            refundOption(player, entry, opt, nowTs, "buy:" .. tostring(id))
            quotaRelease(player, entry, nowTs)
            if entry.stock ~= nil then
                entry.stock = entry.stock + 1
                -- คืนของเข้าชั้นแล้วต้องล้างกำหนดเข้าใหม่ที่เพิ่งประทับไว้ตอนของหมดด้วย
                -- ไม่งั้นแถวจะขึ้น "BACK IN 2 days" ทั้งที่มีของ แล้วรอบ restock
                -- ก็จะมาเขียนทับ stock ทีหลังจนจำนวนเพี้ยน
                if entry.stock > 0 then entry.restockAt, entry.restockTo = nil, nil end
            end
            -- คืนเงิน/คืนสต็อก/คืนโควตาไปแล้ว ไคลเอนต์ต้องเห็นเลขใหม่ทันที
            -- ไม่ใช่ค้างเลขเก่าไว้จนกว่าจะมี sync รอบถัดไป
            S.sync(player)
            return buyFail(player, who, id, "Could not hand over the " ..
                           (isPet and "animal" or "vehicle") .. " slip (" ..
                           tostring(cerr) .. "). You were refunded.")
        end

        S.logSpend(key(player), { k = KR.LOG.BUY, name = entry.name or id,
                                  status = "delivered", amount = mainAmt, cur = mainCur,
                                  value = spendVal, t = nowTs })
        print("[Kuraya] BUY  " .. who .. "  " .. tostring(id) .. "  OK  slip for " ..
              tostring(what) .. "  paid " .. tostring(mainAmt) .. " " .. tostring(mainCur))
        -- คำแนะนำต้องตรงกับกติกาจริงของใบใบนั้น  รถต้องกลางแจ้ง สัตว์ไม่ต้อง
        -- บอกให้ออกไปกลางแจ้งทั้งที่ไม่จำเป็น = คนเดินออกจากคอกไปปล่อยวัวกลางถนน
        alert(player, "Bought " .. tostring(entry.name) ..
                      (isPet and ". Right-click the slip to let it out."
                              or ". Right-click the slip outdoors to unpack it."), "good")

    else
        local n = math.max(1, math.floor(tonumber(entry.count) or 1))
        local made, err = giveItems(player, entry.item, n)
        if made < n then
            -- ได้ไม่ครบ  คืนเงินทั้งก้อนแล้วคืนสต็อกด้วย
            refundOption(player, entry, opt, nowTs, "buy:" .. tostring(id))
            quotaRelease(player, entry, nowTs)
            if entry.stock ~= nil then
                entry.stock = entry.stock + 1
                -- เหตุผลเดียวกับทางคืนเงินของรถ  สต็อกกลับมาแล้วกำหนดเข้าใหม่ต้องหายไปด้วย
                if entry.stock > 0 then entry.restockAt, entry.restockTo = nil, nil end
            end
            -- ยอดเงิน สต็อก และโควตาเปลี่ยนหมดแล้ว  ต้องดันไปให้ไคลเอนต์ก่อนตอบกลับ
            S.sync(player)
            return buyFail(player, who, id, "Could not hand over the item (" ..
                           tostring(err or "partial delivery") .. "). You were refunded.")
        end
        S.logSpend(key(player), { k = KR.LOG.BUY, name = entry.name or id,
                                  status = "delivered", amount = mainAmt, cur = mainCur,
                                  value = spendVal, t = nowTs })
        print("[Kuraya] BUY  " .. who .. "  " .. tostring(id) .. "  OK  x" .. n ..
              "  paid " .. tostring(mainAmt) .. " " .. tostring(mainCur))
        alert(player, "Bought " .. tostring(entry.name) ..
                      (n > 1 and (" x" .. n) or "") .. ".", "good")
    end

    -- ป้ายไฟ  ทำให้คนอื่นเห็นว่าร้านมีคนใช้อยู่
    S.feedPush(KR.FEED.BUY, dispOf(player), entry.name or id)

    -- บัตรสะสม  เต็มใบแล้วแจกแต้มทันที
    if S.stampBump(player) then
        local reward = math.max(0, math.floor(KR.stampOpt("REWARD_HF")))
        if reward > 0 then
            local pl = P(key(player))
            pl.hf = (tonumber(pl.hf) or 0) + reward
            logEvent(key(player), KR.LOG.REWARD, KR.L("บัตรสะสมเต็ม", "Loyalty card full"),
                     reward, KR.CUR.HF, true)
            alert(player, "Loyalty card full - " .. reward .. " HF added.", "good")
            S.feedPush(KR.FEED.STAMP, dispOf(player), nil)
        end
    end

    S.sync(player)
end

-- ==============================================================================
-- ป้ายไฟหน้าร้าน  /  บัตรสะสมแต้ม  /  ของเข้าใหม่รายวัน
--
-- สามอย่างนี้อยู่ด้วยกันเพราะมันแตะจุดเดียวกัน: "ตอนมีคนซื้อของ"
-- ==============================================================================

-- ==============================================================================
-- ประวัติการใช้จ่าย + ระดับการใช้จ่าย
--
-- เก็บต่อผู้เล่นใน P(k).log เป็น ring buffer  ไม่ใช่ก้อนกลางแล้วมากรองทีหลัง
-- เพราะ sync ส่งเฉพาะของคนนั้นอยู่แล้ว เก็บรวมกัน = เตรียมข้อมูลคนอื่นไว้ส่งเปล่า ๆ
--
-- **ไม่มีรายการของธนาคารในนี้** ฝาก/ถอน/โอน/ดอกเบี้ยอยู่ที่สมุดบัญชีของ Akacount
-- เอามาปนแล้วรายการ "ถอน 2,000" จะกลบ "ซื้อยา 420" ที่ผู้เล่นอยากดูจริง ๆ
-- ==============================================================================
function S.spendLog(k)
    local p = P(k)
    p.log = p.log or {}
    return p.log
end

-- amount = จำนวนในหน่วยของสกุลนั้นเอง (ไว้แสดง)
-- value  = ค่าเทียบเป็นหน่วยย่อยเงินสด (ไว้บวกยอดสะสมกับยอด 7 วัน)
-- inc    = true คือเงินเข้า  ไม่นับเข้ายอดใช้จ่ายและไม่ดัน tier
function S.logSpend(k, row)
    if not k or type(row) ~= "table" then return false end
    local p = P(k)
    p.log = p.log or {}

    local inc = row.inc and true or nil
    local e = {
        t   = math.floor(tonumber(row.t) or (getTimestamp and getTimestamp() or os.time())),
        k   = KR.LOG_LABEL[row.k] and row.k or KR.LOG.BUY,
        n   = KR.trunc(tostring(row.name or "-"), 44),
        st  = row.status and KR.trunc(tostring(row.status), 16) or nil,
        a   = math.max(0, math.floor(tonumber(row.amount) or 0)),
        cur = KR.CUR_META[row.cur] and row.cur or KR.CUR.CASH,
        v   = math.max(0, math.floor(tonumber(row.value) or 0)),
        inc = inc,
    }
    p.log[#p.log + 1] = e
    while #p.log > KR.LOG_MAX do table.remove(p.log, 1) end

    -- ยอดรวมรายวันของทั้งเซิร์ฟ  (0.7.0)
    --
    -- บวกตรงนี้จุดเดียว เพราะทุกเส้นทางที่เงินไหลผ่าน **ต้อง** เขียนแถวประวัติอยู่แล้ว
    -- ไปบวกที่จุดที่เงินไหลจริงทีละจุดแทน = ต้องแก้สิบที่ และวันหนึ่งจะมีจุดที่ลืม
    if type(S.statsBump) == "function" then
        pcall(S.statsBump, e.cur, e.a, inc, e.t)
    end

    -- ยอดสะสมตลอดกาล  ไม่มีวันลด แม้จะได้เงินคืน
    -- เพราะ tier ตอบคำถามว่า "เคยอุดหนุนร้านไปเท่าไร" ไม่ใช่ "ตอนนี้เหลือเท่าไร"
    -- ยกเว้นการคืนเงินเต็มจำนวนจากความผิดของร้านเอง ซึ่งเรียก S.unlogSpend แทน
    if not inc and e.v > 0 then
        local before = KR.tierState(p).tier
        p.spent = math.max(0, math.floor(tonumber(p.spent) or 0)) + e.v
        local after = KR.tierState(p).tier
        if after > before then
            S.feedPush(KR.FEED.TIER, p.disp or k, tostring(after))
            return true, after
        end
    end
    return true
end

-- ถอนยอดคืนตอนร้านส่งของไม่สำเร็จแล้วคืนเงิน
-- ไม่ทำแบบนี้ = ซื้อของที่ส่งไม่ได้รัว ๆ แล้วไต่ tier ฟรีทั้งที่ไม่ได้เสียอะไรเลย
function S.unlogSpend(k, value)
    local p = P(k)
    local v = math.max(0, math.floor(tonumber(value) or 0))
    if v == 0 then return end
    p.spent = math.max(0, (math.floor(tonumber(p.spent) or 0)) - v)
    -- เอาแถวล่าสุดที่ตรงกันออกด้วย  ไม่งั้นประวัติจะโชว์รายการที่ถูกยกเลิกไปแล้ว
    for i = #(p.log or {}), 1, -1 do
        if not p.log[i].inc and p.log[i].v == v then table.remove(p.log, i); break end
    end
end


-- ให้ม็อดอื่นเขียนประวัติของตัวเองลงมาได้ (บิลค่าบ้าน / ค่าเช่า / ค่าปรับ)
-- รับ IsoPlayer หรือชื่อก็ได้  ม็อดอื่นไม่ควรต้องรู้ว่าเราคีย์ด้วยอะไร
function API.logSpend(who, row)
    local k = type(who) == "string" and who:lower() or key(who)
    if not k then return false end
    return S.logSpend(k, row)
end

-- เก็บเหตุการณ์ลงป้ายไฟ  เป็น ring buffer เหมือน hflog
-- ห้ามใส่ยอดเงินลงไป  ป้ายนี้ทุกคนเห็น ไม่ใช่ข้อมูลส่วนตัว
function S.feedPush(kind, who, what)
    local d = db()
    d.feed = d.feed or {}
    d.feed[#d.feed + 1] = {
        t    = getTimestamp and getTimestamp() or os.time(),
        k    = kind,
        who  = who  and KR.trunc(tostring(who), 18)  or nil,
        what = what and KR.trunc(tostring(what), 28) or nil,
    }
    while #d.feed > KR.FEED_MAX do table.remove(d.feed, 1) end
end

-- ส่งให้ไคลเอนต์เฉพาะท้าย ๆ  ไม่ต้องส่งทั้งวงแหวนทุก sync
local function feedTail(d)
    local out = {}
    local from = math.max(1, #(d.feed or {}) - KR.FEED_SHOW + 1)
    for i = from, #(d.feed or {}) do out[#out + 1] = d.feed[i] end
    return out
end

-- บัตรสะสม  นับเป็น "ครั้งที่ซื้อ" ไม่ใช่จำนวนเงิน
-- คืน true ถ้าเพิ่งเต็มใบพอดี เพื่อให้คนเรียกไปแจกรางวัลต่อ
function S.stampBump(player)
    local p = P(key(player))
    p.buys = (tonumber(p.buys) or 0) + 1

    local perStamp = math.max(1, KR.stampOpt("PER_STAMP"))
    local perCard  = math.max(1, KR.stampOpt("PER_CARD"))
    local needed   = perStamp * perCard

    if p.buys >= needed then
        -- เต็มใบ  ตัดออกไปหนึ่งใบ เศษที่เหลือยกไปใบถัดไป
        -- (ลบออกแทนที่จะรีเซ็ตเป็น 0  ไม่งั้นคนที่ซื้อรวดเดียวหลายครั้งจะเสียเศษฟรี)
        p.buys  = p.buys - needed
        p.cards = (tonumber(p.cards) or 0) + 1
        return true
    end
    return false
end

-- ของเข้าใหม่รายวัน
--
-- เรียกทุกครั้งที่มีคน sync  แต่ทำงานจริงวันละครั้ง
-- ไม่ใช้ตัวจับเวลาเพราะเซิร์ฟอาจปิดข้ามวัน  แล้ว event รายวันจะไม่เคยยิง
-- เทียบ "เลขวันวันนี้" กับ "เลขวันที่ทำไปแล้ว" ตรงไปตรงมากว่าและกันเซิร์ฟล่มได้
function S.rotateDaily(nowTs)
    local d   = db()
    local day = KR.dayOf(nowTs)
    d.rotate  = d.rotate or { day = -1, ids = {} }
    if d.rotate.day == day then return false end

    -- รายชื่อของที่หมุนได้  เรียงก่อนเสมอ  pairs() ไม่รับประกันลำดับ
    local ids = {}
    for id, e in pairs(d.catalog) do
        if e.enabled ~= false and e.market == nil and e.kind ~= KR.KIND.SERVICE then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    if #ids == 0 then
        d.rotate.day = day
        return false
    end

    -- ล้างป้าย NEW ของเมื่อวาน
    for _, id in ipairs(d.rotate.ids or {}) do
        local e = d.catalog[id]
        if e then e.newAt = nil end
    end

    local pick = KR.pickRotation(ids, day, KR.ROTATE_COUNT)
    for _, id in ipairs(pick) do
        local e = d.catalog[id]
        if e then
            e.newAt = nowTs
            -- เติมสต็อกให้ของที่หมด  ของที่ยังมีอยู่ไม่ต้องแตะ
            --
            -- ต้องเคารพกำหนดเข้าใหม่ของตัวมันเองด้วย
            -- ของที่เพิ่งหมดเมื่อกี้และป้ายบอกว่า "เข้าใหม่อีก 2 วัน"
            -- ห้ามถูกรอบหมุนรายวันเติมกลับมาทันที ไม่งั้นป้ายที่โชว์ก็โกหกผู้เล่น
            if e.stock ~= nil and e.stock <= 0
               and (e.restockAt == nil or e.restockAt <= nowTs) then
                e.stock     = math.max(1, math.floor(tonumber(e.restockTo) or 5))
                e.restockAt = nil
            end
        end
    end

    d.rotate.day = day
    d.rotate.ids = pick
    S.feedPush(KR.FEED.STOCK, nil, tostring(#pick))
    return true
end

-- ==============================================================================
-- โอนแต้ม HF ระหว่างผู้เล่น
--
-- HF อยู่ในตารางเดียวของเราทั้งหมด ไม่ต้องข้ามม็อด จึงไม่ต้องใช้ hold/capture
-- แต่มีกฎข้อเดียวที่ห้ามพลาด: **หักผู้ส่งก่อน แล้วค่อยบวกผู้รับ**
-- ถ้าบวกก่อนแล้วหักทีหลังแล้วหักไม่ผ่าน = เสกแต้มขึ้นมาใหม่ฟรี ๆ
-- เทสจึงเช็กผลรวมแต้มทั้งเซิร์ฟก่อนและหลังโอนว่าเท่ากันเสมอ (ลบด้วยค่าธรรมเนียม)
-- ==============================================================================
local function hfLog(d, row)
    local log = d.hflog
    log[#log + 1] = row
    local max = KR.HF_SEND.LOG_MAX
    if #log > max then
        -- ตัดหัวทิ้งทีละก้อน ไม่ใช่ทีละแถว  table.remove(1) ทุกครั้งคือ O(n) ทุกครั้ง
        local keep = {}
        for i = #log - max + 1, #log do keep[#keep + 1] = log[i] end
        d.hflog = keep
    end
end

local function sentToday(d, k, dayKey)
    local row = P(k).sent
    if not row or row.d ~= dayKey then return 0 end
    return tonumber(row.n) or 0
end

-- จดว่าวันนี้ส่งไปแล้วเท่าไร  เพดานรายวันอ่านจากตรงนี้
local function bumpSent(d, k, dayKey, amount)
    local p = P(k)
    if not p.sent or p.sent.d ~= dayKey then p.sent = { d = dayKey, n = 0 } end
    p.sent.n = (tonumber(p.sent.n) or 0) + math.max(0, math.floor(amount or 0))
end

-- ------------------------------------------------------------------------------
-- โอนให้ผู้เล่นคนอื่น  รองรับทั้ง CASH / HF / CP
--
-- เดิมรองรับแค่ HF และ **ชื่อฟิลด์ไม่ตรงกับที่ไคลเอนต์ส่งมา**
--   ไคลเอนต์ส่ง { to = ..., n = ... }   เซิร์ฟอ่าน args.amt
-- ผลคือ amount = 0 เสมอ แล้วเด้งว่า "ต่ำกว่าขั้นต่ำ" ทุกครั้ง
-- ผู้เล่นรายงานว่า "Send cash hf cp ไม่ติด"  (บั๊กชนิดเดียวกับหน่วยเงินของ Akacount)
--
-- รับทั้ง n และ amt เพื่อไม่ให้ไคลเอนต์รุ่นเก่าพัง แต่ตัวจริงคือ n
--
-- ข้อจำกัดที่ตั้งใจ:
--   CASH เดินผ่าน Akacount เสมอ  ledger ต้องรู้ว่าเงินย้ายมือ
--   CP โอนได้เฉพาะตอนผู้รับออนไลน์ เพราะ HF Town Rank ไม่มี API แก้แต้มคนออฟไลน์
-- ------------------------------------------------------------------------------
local function onlinePlayerByKey(k)
    local list = getOnlinePlayers and getOnlinePlayers()
    if not list then return nil end
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p and key(p) == k then return p end
    end
    return nil
end
-- ประมูลต้องใช้ตัวนี้ด้วย (แจ้งคนที่โดนแซงราคา)  ห้ามมีสำเนาที่สองในไฟล์นั้น
S.onlineByKey = onlinePlayerByKey

function S.send(player, args)
    local from = touch(player)
    if not from then return end

    local d      = db()
    local toRaw  = tostring((args and args.to) or "")
    local to     = toRaw:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local amount = math.floor(tonumber(args and (args.n or args.amt)) or 0)
    local cur    = tostring((args and args.cur) or KR.CUR.HF)
    local nowTs  = getTimestamp and getTimestamp() or os.time()

    -- ร้านโอนได้เฉพาะสกุลที่ร้านเป็นเจ้าของ
    --
    -- เงินสดถูกถอดออกตามที่เจ้าของเซิร์ฟสั่ง และมันถูกต้องเชิงโครงสร้างด้วย
    -- เงินสดเป็นของ Akacount  ธนาคารมีหน้าจอโอน กติกา ค่าธรรมเนียม และสมุดบัญชีของตัวเองอยู่แล้ว
    -- ทางโอนเงินสดทางที่สองในร้าน = สองที่ที่ต้องแก้ทุกครั้งที่กติกาเปลี่ยน
    -- แล้ววันหนึ่งมันจะไม่ตรงกัน ซึ่งในระบบเศรษฐกิจแปลว่าเงินหายหรือเงินงอก
    --
    -- ข้อความต้องบอก **ที่ที่ทำได้** ไม่ใช่แค่บอกว่าทำไม่ได้
    -- ไคลเอนต์รุ่นเก่าที่ยังมีชิป CASH อยู่จะมาถึงบรรทัดนี้ ต้องได้คำตอบที่เอาไปทำต่อได้
    if cur == KR.CUR.CASH then
        return alert(player, "Cash transfers happen at the bank now - use your Akacount card there. " ..
                             "The shop sends HF and CP only.", "bad")
    end
    if cur ~= KR.CUR.HF and cur ~= KR.CUR.CP then
        return alert(player, "Unknown currency.", "bad")
    end
    if S.frozenBlock(player, "transfers") then return end
    if amount <= 0 then return alert(player, "Enter an amount.", "bad") end
    if to == "" then return alert(player, "Pick someone to send to.", "bad") end
    if to == from then return alert(player, "You cannot send to yourself.", "bad") end
    if not d.players[to] then
        return alert(player, "No player named '" .. toRaw .. "' on this server.", "bad")
    end

    local fee   = KR.hfSendFee(amount)
    local total = amount + fee
    local meta  = KR.CUR_META[cur] or {}
    local label = meta.label or cur:upper()

    -- ---------------- HF ----------------
    if cur == KR.CUR.HF then
        local minAmt = KR.hfSendOpt("MIN")
        if amount < minAmt then
            return alert(player, "Minimum transfer is " .. minAmt .. " HF.", "bad")
        end
        local mine = P(from)
        if (mine.hf or 0) < total then
            return alert(player, "Not enough HF. You need " .. total ..
                                 " (" .. amount .. " + " .. fee .. " fee).", "bad")
        end

        local dayKey = math.floor(nowTs / KR.DAY_SEC)
        local cap    = KR.hfSendOpt("DAILY")
        if cap > 0 and (sentToday(d, from, dayKey) + amount) > cap then
            return alert(player, "Daily transfer cap reached.", "bad")
        end

        -- หักผู้ส่งก่อนเสมอ  บวกผู้รับทีหลัง  สลับกันเมื่อไรคือเสกแต้มขึ้นมาใหม่
        mine.hf = mine.hf - total
        P(to).hf = (P(to).hf or 0) + amount
        bumpSent(d, from, dayKey, amount)

    -- ---------------- CP ----------------
    -- (ทางเงินสดถูกลบทั้งบล็อกแล้ว ไม่ได้แค่กันไว้ข้างบน
    --  โค้ดที่ไปถึงไม่ได้แต่ยังอ่านเหมือนใช้งานได้ คือกับดักของคนที่มาแก้ไฟล์นี้ต่อ)
    else
        local rcv = onlinePlayerByKey(to)
        if not rcv then
            return alert(player, toRaw .. " must be online to receive CP.", "bad")
        end
        if KR.tr.get(player) < total then
            return alert(player, "Not enough CP. You need " .. total .. ".", "bad")
        end
        local okCp = KR.tr.deduct(player, total)
        if not okCp then return alert(player, "Could not take your CP.", "bad") end
        local okAdd = KR.tr.refund(rcv, amount)
        if not okAdd then
            -- ให้ไม่สำเร็จ  คืนคนส่งทันที ห้ามให้แต้มหายกลางทาง
            KR.tr.refund(player, total)
            return alert(player, "Could not deliver the CP. Nothing was taken.", "bad")
        end
    end

    hfLog(d, { t = nowTs, f = from, to = to, a = amount, fee = fee, cur = cur })

    -- ประวัติของทั้งสองฝั่ง  ผู้รับต้องเห็นด้วยแม้ตอนนี้จะออฟไลน์อยู่
    -- (logEvent คีย์ด้วยสตริง ไม่ต้องมี IsoPlayer)
    --
    -- ฝั่งผู้ส่งบันทึก "ยอดที่หายไปจากกระเป๋าจริง" = amount + fee ไม่ใช่ amount เปล่า
    -- ไม่งั้นเลขในประวัติกับเลขที่หายไปจากยอดคงเหลือไม่ตรงกัน แล้วจะมีคนมาถามว่าเงินหายไปไหน
    logEvent(from, KR.LOG.XFER, KR.L("โอนให้ ", "Sent to ") .. (P(to).disp or toRaw),
             total, cur, false, fee > 0 and ("fee " .. fee) or nil)
    logEvent(to,   KR.LOG.XFER, KR.L("รับจาก ", "From ") .. (P(from).disp or from),
             amount, cur, true)

    alert(player, "Sent " .. amount .. " " .. label .. " to " .. (P(to).disp or toRaw) ..
                  (fee > 0 and ("  (fee " .. fee .. ")") or ""), "good")
    S.syncAll()
end

-- ชื่อเดิม  ยังมีคนเรียกอยู่ (และม็อดอื่นอาจเรียก)
function S.sendHF(player, args)
    args = args or {}
    args.cur = args.cur or KR.CUR.HF
    return S.send(player, args)
end

function S.adminDel(player, args)
    if not isStaff(player) then return alert(player, "Admin only.", "bad") end
    local d  = ensureSeed()
    local id = args and args.id
    local e  = id and d.catalog[id]
    if not e then return alert(player, "No such listing.", "bad") end
    d.catalog[id] = nil
    alert(player, "Removed " .. tostring(e.name), "good")
    S.syncAll()
end

-- ส่ง sync ให้ทุกคนที่ออนไลน์  ใช้ตอนแคตตาล็อกเปลี่ยน
function S.syncAll()
    local list = getOnlinePlayers and getOnlinePlayers() or nil
    if not list then return end
    for i = 0, list:size() - 1 do S.sync(list:get(i)) end
end



-- รายชื่อผู้รับที่เลือกได้  ส่งไปให้ไคลเอนต์ทำ autocomplete
-- ส่งเฉพาะชื่อ ไม่ส่งยอดแต้มของคนอื่นไปด้วย
function S.recipients()
    local d, out = db(), {}
    for k, row in pairs(d.players) do out[#out + 1] = row.disp or k end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

-- ==============================================================================
-- ตำแหน่งปุ่มลอย
--
-- เก็บไว้บนเซิร์ฟเวอร์เป็นรายคน  ผู้เล่นย้ายปุ่มครั้งเดียวแล้วต้องจำได้ตลอด
-- ไม่ว่าจะเข้าจากเครื่องไหน  ไฟล์ตั้งค่าฝั่งไคลเอนต์หายง่ายเกินกว่าจะพึ่งได้
-- ==============================================================================
function S.saveBtn(player, args)
    local k = touch(player); if not k then return end
    local d = db()
    P(k).ui = {
        x      = math.floor(tonumber(args and args.x) or 0),
        y      = math.floor(tonumber(args and args.y) or 0),
        locked = (args and args.locked) and true or false,
    }
    -- ไม่ต้องตอบกลับ  ไคลเอนต์รู้ตำแหน่งตัวเองอยู่แล้ว ตอบไปก็แค่กระพริบเปล่า ๆ
end

function S.reqBtn(player)
    local k = touch(player); if not k then return end
    local cfg = P(k).ui
    if not cfg then return end     -- ไม่เคยตั้ง = ให้ไคลเอนต์ใช้ตำแหน่งเริ่มต้นของมันเอง
    sendServerCommand(player, KR.MODULE, KR.CMD.SYNC_BTN, cfg)
end

-- ==============================================================================
-- ตลาดสด  แอดมินลงทะเบียน tile ที่ยืนอยู่
--
-- กฎเดียวกับธนาคาร: ตัวเลขดูได้ทุกที่ ของต้องไปเอาถึงที่
-- รายการของแผงโผล่ในร้านให้ทุกคนเห็นตลอด แต่ปุ่มซื้อจะกดได้ก็ต่อเมื่อยืนอยู่ที่แผง
-- ==============================================================================
function S.adminMarket(player, args)
    if not isStaff(player) then
        return alert(player, "Admin only.", "bad")
    end
    local sq = player and player:getSquare()
    if not sq then return alert(player, "Stand somewhere first.", "bad") end

    local d = db()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()

    -- ยืนอยู่บนแผงที่ลงทะเบียนไว้แล้ว = สั่งซ้ำแปลว่าอยากถอด
    local hereId = S.marketAt(player)
    if hereId then
        local nm = d.markets[hereId] and d.markets[hereId].name or hereId
        d.markets[hereId] = nil
        alert(player, "Market stall removed: " .. tostring(nm), "good")
        return S.sync(player)
    end

    local id = "m" .. tostring(d.meta.nextId or 1)
    d.meta.nextId = (d.meta.nextId or 1) + 1
    d.markets[id] = {
        x = x, y = y, z = z,
        name = KR.trunc((args and args.name) or ("Stall " .. id), 24),
        items = {},
    }
    alert(player, "Market stall registered: " .. d.markets[id].name, "good")
    S.sync(player)
end

-- ==============================================================================
-- ประกาศของลดราคา
--
-- ขึ้นเป็นข้อความเขียวเหนือหัวผู้เล่น  ไม่ใช่ป็อปอัปกลางจอ
-- เพราะคนกำลังวิ่งหนีซอมบี้อยู่ก็ได้ ห้ามไปบังจอเขา
--
-- ยิงตอนล็อกอินหนึ่งครั้ง และตอนแอดมินลงของลดราคาใหม่
-- ไม่ยิงซ้ำทุกนาที ไม่งั้นกลายเป็นสแปม
-- ==============================================================================
function S.saleCount(nowTs)
    local n = 0
    for _, e in pairs(db().catalog) do
        -- ของที่ปิดอยู่ไม่นับ  ป้ายแดง "ลดราคา 3 ชิ้น" ที่พาไปหน้าที่มีของสองชิ้น
        -- คือการบอกผู้เล่นเป็นนัยว่ามีของที่เขาไม่เห็น ซึ่งเป็นข้อมูลรั่วแบบหนึ่ง
        if e.enabled ~= false and KR.saleActive(e, nowTs) then n = n + 1 end
    end
    return n
end

function S.announceSale(target)
    local nowTs = getTimestamp and getTimestamp() or os.time()
    local n = S.saleCount(nowTs)
    if n <= 0 then return end

    local payload = { n = n }
    if target then
        return sendServerCommand(target, KR.MODULE, KR.CMD.SALE_ANNOUNCE, payload)
    end
    local list = getOnlinePlayers and getOnlinePlayers() or nil
    if not list then return end
    for i = 0, list:size() - 1 do
        sendServerCommand(list:get(i), KR.MODULE, KR.CMD.SALE_ANNOUNCE, payload)
    end
end


-- ==============================================================================
-- แอดมินจัดการของในร้าน
--
-- ทุกฟิลด์ที่ไคลเอนต์ส่งมาโดนล้างใหม่หมดตรงนี้ ไม่มีการเอา args ไปยัดใส่ตารางตรง ๆ
-- ถ้าปล่อยผ่าน แอดมินที่โดนแฮกบัญชี (หรือแอดมินที่พิมพ์พลาด) จะเขียนฟิลด์อะไรก็ได้
-- ลงฐานข้อมูล รวมถึงฟิลด์ที่โค้ดเราคาดว่าเป็นตัวเลขแต่กลายเป็นสตริง แล้วพังตอนคิดเงิน
-- ==============================================================================
local ALLOWED_CUR = { [KR.CUR.CASH] = true, [KR.CUR.HF] = true, [KR.CUR.CP] = true }

local function cleanPay(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for i = 1, math.min(#raw, 6) do              -- ตัวเลือกการจ่ายเกิน 6 แบบคือกรอกผิดแน่นอน
        local o, parts = raw[i], {}
        if type(o) == "table" then
            local src = o.cur and { o } or o
            for j = 1, math.min(#src, 3) do      -- จ่ายผสมเกินสามสกุลไม่มีความหมาย
                local q = src[j]
                if type(q) == "table" and ALLOWED_CUR[q.cur] then
                    local pr = tonumber(q.price) or 0
                    if pr > 0 then parts[#parts + 1] = { cur = q.cur, price = pr } end
                end
            end
        end
        if #parts > 0 then out[#out + 1] = parts end
    end
    return out
end

local function cleanEntry(a, old, nowTs)
    local e = {}
    e.id      = tostring(a.id or ""):gsub("[^%w_%-]", ""):sub(1, 32)
    e.name    = KR.trunc(a.name, 48)
    e.cat     = KR.trunc(tostring(a.cat or "general"):lower(), 20)
    e.kind    = (a.kind == KR.KIND.VEHICLE or a.kind == KR.KIND.SERVICE
                 or a.kind == KR.KIND.PET) and a.kind or KR.KIND.ITEM
    e.item    = a.item and KR.trunc(a.item, 64) or nil
    e.vehicle = a.vehicle and KR.trunc(a.vehicle, 64) or nil
    e.pet     = a.pet and KR.trunc(a.pet, 64) or nil
    e.rare    = a.rare and true or false

    -- ---- ของในชุด  (0.6.12) ------------------------------------------------
    -- ล้างทีละบรรทัด และ **ตัดที่เพดานเสมอ**  ไคลเอนต์ที่ถูกแก้ส่งมากี่บรรทัดก็ได้
    -- ชุดที่มีของพันชิ้นคือชุดที่ทำให้แพ็กเก็ต sync บวมจนหลุดทั้งเซิร์ฟ
    if type(a.set) == "table" and #a.set > 0 then
        local lines = {}
        for _, ln in ipairs(a.set) do
            if #lines >= KR.SET_MAX then break end
            if type(ln) == "table" then
                local it  = (type(ln.item) == "string" and ln.item ~= "") and KR.trunc(ln.item, 64) or nil
                local veh = (type(ln.vehicle) == "string" and ln.vehicle ~= "") and KR.trunc(ln.vehicle, 64) or nil
                local pet = (type(ln.pet) == "string" and ln.pet ~= "") and KR.trunc(ln.pet, 64) or nil
                -- บรรทัดที่ไม่ได้ชี้ของอะไรเลย ไม่ใช่บรรทัด  ทิ้งเงียบ ๆ ตรงนี้
                -- ดีกว่าเก็บไว้แล้วไปพังตอนคนซื้อ
                --
                -- **หนึ่งบรรทัดชี้ของได้อย่างเดียว** ไคลเอนต์ที่ถูกแก้ส่งมาครบสามช่องได้
                -- บรรทัดที่มีทั้ง item และ vehicle จะส่งมอบทางไหนก็ตอบไม่ได้
                -- ลำดับที่ชนะคือ รถ > สัตว์ > ของ  ตรงกับที่ setDeliver อ่าน
                if it or veh or pet then
                    lines[#lines + 1] = {
                        item    = (veh or pet) and nil or it,
                        vehicle = veh,
                        pet     = (not veh) and pet or nil,
                        n       = math.max(1, math.min(999, math.floor(tonumber(ln.n) or 1))),
                    }
                end
            end
        end
        e.set = (#lines > 0) and lines or nil
    else
        e.set = nil
    end

    -- รูปกล่อง  ตั้งได้เฉพาะชุด และต้องเป็นรูปที่เรามีจริง
    -- ไอดีมั่วจาก client ที่ถูกแก้ = getTexture คืน nil = ช่องดำ ซึ่งอ่านว่าของพัง
    e.box = (KR.isSet(e) and KR.boxKnown(a.box)) and a.box or nil

    -- "ซ่อนจากผู้เล่น" คือสถานะที่ต้องอยู่ทน ห้ามหลุดเพราะการกดบันทึกครั้งถัดไป
    --
    -- ของเดิมเขียน `e.enabled = a.enabled ~= false` เฉย ๆ  ซึ่งแปลว่า
    -- ฟอร์มที่ไม่ได้ส่งฟิลด์นี้มาด้วย (ฟอร์มแก้ไขเดิมไม่เคยส่ง) = เปิดขายทันที
    -- แอดมินซ่อนของไว้ แก้ราคา กดบันทึก แล้วของโผล่ขึ้นร้านเงียบ ๆ โดยไม่มีใครสั่ง
    -- ตอนนี้ฟอร์มส่งมาแล้ว แต่ยังต้องกันไว้เผื่อไคลเอนต์รุ่นเก่าหรือคำสั่งจากม็อดอื่น
    if a.enabled == nil and old then
        e.enabled = old.enabled ~= false
    else
        e.enabled = a.enabled ~= false
    end

    e.stock   = a.stock ~= nil and math.max(0, math.floor(tonumber(a.stock) or 0)) or nil
    e.restock = (a.restock == KR.RESTOCK.DAILY or a.restock == KR.RESTOCK.WEEKLY)
                and a.restock or KR.RESTOCK.NEVER

    -- ได้ครั้งละกี่ชิ้น
    --
    -- S.buy อ่าน entry.count มาตั้งแต่ต้นและส่งของตามนั้นถูกต้องอยู่แล้ว
    -- แต่ **ไม่เคยมีอะไรเขียนค่านี้ลงไป** เพราะ cleanEntry ไม่ได้ก๊อปมันมา
    -- ทุกรายการจึงตกไปที่ค่าสำรอง 1 เสมอ  ของอย่าง "กระสุน 200 นัด" ตั้งไม่ได้เลย
    -- เพดาน 999 ไม่ใช่เรื่องความปลอดภัย แต่กันแอดมินพิมพ์เลขหลุดแล้วยัดกระเป๋าผู้เล่นจนล้น
    local cnt = math.floor(tonumber(a.count) or 1)
    e.count = (cnt > 1) and math.min(999, cnt) or nil

    e.quota       = math.max(0, math.floor(tonumber(a.quota) or 0))
    e.quotaPeriod = (a.quotaPeriod == KR.PERIOD.DAILY or a.quotaPeriod == KR.PERIOD.WEEKLY
                     or a.quotaPeriod == KR.PERIOD.EVER) and a.quotaPeriod or KR.PERIOD.SALE

    -- ส่วนลดต้องอยู่ใน 1-99%  0 หรือ 100 ทำให้ราคาหายหรือของฟรี
    local bp = math.floor(tonumber(a.saleBp) or 0)
    if bp > 0 and bp < 10000 then
        e.saleBp = bp
        -- ระยะเวลาลดราคาเป็น **นาที** ตั้งแต่ 0.6.0 ตามที่เจ้าของเซิร์ฟสั่ง
        --
        -- ยังรับ saleHours ของไคลเอนต์รุ่นเก่าอยู่ เพราะระหว่างที่ผู้เล่นทยอยอัปเดต
        -- จะมีช่วงที่จอเก่ากับเซิร์ฟใหม่คุยกัน  ถ้าตัดทิ้งเลย ค่าที่ส่งมาจะกลายเป็น 0
        -- แล้วโปรลดราคาจะจบทันทีที่กดบันทึก ซึ่งเป็นบั๊กที่หาสาเหตุยากมาก
        --
        -- ไม่ต้องย้ายข้อมูลเก่า: e.saleEndsAt เก็บเป็น "เวลาจริงที่ราคาเด้งกลับ"
        -- ไม่ได้เก็บระยะเวลา  ของที่ตั้งไว้ก่อนอัปเดตจึงจบตรงเวลาเดิมเป๊ะ
        local mins = tonumber(a.saleMins)
        if not mins then
            local hrs = tonumber(a.saleHours)
            mins = hrs and (hrs * 60) or nil
        end
        mins = math.max(1, math.floor(mins or (24 * 60)))
        e.saleEndsAt = nowTs + mins * 60
    end

    e.market = a.market and KR.trunc(a.market, 16) or nil
    e.pay    = cleanPay(a.pay)

    -- listedAt ต้องเป็นของเดิมถ้าแก้ของเก่า  ไม่งั้นแก้ราคาทีของเด้งขึ้นบนสุดทุกที
    e.listedAt = (old and old.listedAt) or nowTs

    -- เลขรอบการแก้  เพิ่มทุกครั้งที่บันทึก  ใช้จับว่ามีแอดมินอีกคนแก้แซงไปแล้ว
    e.rev = ((old and tonumber(old.rev)) or 0) + 1
    e.by  = nil        -- เติมทีหลังใน adminSave  ตรงนี้ยังไม่รู้ว่าใครกด
    return e
end

function S.adminSave(player, args)
    if not isStaff(player) then return alert(player, "Admin only.", "bad") end
    local d = ensureSeed()
    local nowTs = getTimestamp and getTimestamp() or os.time()

    local a = args or {}
    if tostring(a.id or "") == "" then
        a.id = "kr_" .. tostring(d.meta.nextId or 1)
        d.meta.nextId = (d.meta.nextId or 1) + 1
    end

    local old = d.catalog[a.id]

    -- ==========================================================================
    -- แอดมินทุกคนในเซิร์ฟแก้ข้อมูลชุดเดียวกัน  ไม่ได้แยกกันคนละชุด
    -- ข้อดีคือทุกคนเห็นตรงกัน  ข้อเสียคือสองคนเปิดของชิ้นเดียวกันพร้อมกันได้
    --
    -- ถ้าปล่อยไว้ คนกดบันทึกทีหลังจะทับงานคนแรกแบบเงียบ ๆ
    -- และคนแรกจะไม่มีทางรู้เลยว่างานตัวเองหายไปไหน
    --
    -- เลยให้ไคลเอนต์ส่ง "เลขรอบ" ที่ตอนโหลดมาด้วย  ถ้าไม่ตรงกับของจริงแปลว่ามีคนแก้แซง
    -- ปฏิเสธแล้วบอกให้กดโหลดใหม่  ดีกว่าทับกันเงียบ ๆ
    -- ==========================================================================
    if old and a.rev ~= nil and tonumber(a.rev) ~= (tonumber(old.rev) or 0) then
        local who = old.by and (" (" .. tostring(old.by) .. ")") or ""
        return alert(player, "Someone else edited '" .. tostring(old.name) ..
                             "' while you had it open" .. who ..
                             ". Click it again to reload.", "bad")
    end

    local e = cleanEntry(a, old, nowTs)

    if e.id == "" then return alert(player, "Bad id.", "bad") end
    if e.name == "" then return alert(player, "Name required.", "bad") end
    if #e.pay == 0 then return alert(player, "Set at least one price.", "bad") end

    -- ==========================================================================
    -- ของที่ต้องส่งมอบจริง ต้องมีชนิดไอเทมที่เกมรู้จัก  ห้ามบันทึกถ้าไม่มี
    --
    -- ทำไมต้องดุขนาดนี้: ลิสต์ที่ไม่มี item type ดูปกติทุกอย่างในหน้าร้าน
    -- มีชื่อ มีราคา มีปุ่ม Buy สีม่วงกดได้  จนกว่าจะมีคนกดซื้อจริง
    -- แล้วเซิร์ฟจะหักเงิน -> ส่งของไม่ได้ -> คืนเงิน -> ผู้เล่นเห็นแค่ "กดซื้อไม่ได้"
    -- (เกิดขึ้นจริงในเกม เจ้าของเซิร์ฟรายงานว่า "กดซื้ออะไรไม่ได้")
    --
    -- ดักตอนบันทึกดีกว่าตอนซื้อ  เพราะตอนบันทึกคนที่ทำผิดคือคนที่แก้ได้
    -- ตอนซื้อคนที่เจอปัญหาคือผู้เล่นที่ทำอะไรไม่ได้เลย
    -- ==========================================================================
    -- ชุดตรวจของในชุดแทน  ตัวรายการเองไม่ต้องมี item เพราะของอยู่ในบรรทัด
    -- เหตุผลเดียวกับด่านข้างบน: ดักตอนบันทึก คนที่ทำผิดกับคนที่แก้ได้คือคนเดียวกัน
    if KR.isSet(e) then
        local bad = S.setCheck(e)
        if bad then
            return alert(player, "This set cannot be delivered - " .. tostring(bad), "bad")
        end

    elseif e.kind == KR.KIND.ITEM then
        if e.item == nil or tostring(e.item) == "" then
            return alert(player, "Item type is required. Example: Base.Axe", "bad")
        end
        local sm = getScriptManager and getScriptManager()
        if sm then
            local okFind, found = pcall(function() return sm:FindItem(tostring(e.item)) end)
            if not okFind or not found then
                return alert(player, "This game has no item called '" .. tostring(e.item) ..
                                     "'. Use the full type with its module, like Base.Axe.", "bad")
            end
        end
    end

    -- รถใช้เหตุผลเดียวกันเป๊ะ  รายการรถที่ไม่มีรุ่น หรือมีรุ่นที่เซิร์ฟนี้ไม่มี
    -- จะดูปกติทุกอย่างจนกว่าจะมีคนกดซื้อ แล้วเจอ "จ่ายแล้วคืนเงิน" ซึ่งอ่านว่าม็อดพัง
    -- ดักตอนบันทึก = คนที่ทำผิดกับคนที่แก้ได้คือคนเดียวกัน และเขากำลังมองจออยู่
    if e.kind == KR.KIND.VEHICLE and not KR.isSet(e) then
        if e.vehicle == nil or tostring(e.vehicle) == "" then
            return alert(player, "Vehicle model is required." ..
                                 " Pick one from the MODEL box. Example: Base.CarNormal", "bad")
        end
        if type(S.carKnown) == "function" and not S.carKnown(tostring(e.vehicle)) then
            return alert(player, "This server has no vehicle called '" .. tostring(e.vehicle) ..
                                 "'. Pick one from the MODEL box.", "bad")
        end
    end

    -- สัตว์ก็เหมือนกัน  (0.6.16)
    -- ดักตอนบันทึก = คนที่ทำผิดกับคนที่แก้ได้คือคนเดียวกัน และเขากำลังมองจออยู่
    if e.kind == KR.KIND.PET and not KR.isSet(e) then
        if e.pet == nil or tostring(e.pet) == "" then
            return alert(player, "Animal is required." ..
                                 " Pick one from the ANIMAL box. Example: cow", "bad")
        end
        if type(S.petKnown) == "function" and not S.petKnown(tostring(e.pet)) then
            return alert(player, "This server has no animal called '" .. tostring(e.pet) ..
                                 "'. Pick one from the ANIMAL box.", "bad")
        end
    end

    e.by = P(key(player)).disp or key(player)
    d.catalog[e.id] = e
    alert(player, (old and "Updated " or "Added ") .. e.name, "good")

    -- ตั้งของลดราคาใหม่ = ประกาศให้ทุกคนรู้ทันที
    if e.saleBp and (not old or old.saleEndsAt ~= e.saleEndsAt) then S.announceSale() end
    S.syncAll()
end

-- ==============================================================================
-- หน้าจัดการ : แผงตลาด
--
-- ลงทะเบียนแผงยังทำจากในโลก (ต้องยืนอยู่ตรงนั้น)  แต่ตั้งชื่อกับถอดทำจากหน้าจัดการได้
-- เพราะแอดมินมักตั้งชื่อทีหลังตอนนั่งดูรายการทั้งหมดพร้อมกัน
-- ==============================================================================
function S.adminMarketSet(player, args)
    if not isStaff(player) then return alert(player, "Admin only.", "bad") end
    local d  = ensureSeed()
    local id = args and args.id
    local m  = id and d.markets[id]
    if not m then return alert(player, "No such stall.", "bad") end

    if args.del then
        -- ของที่ผูกกับแผงนี้ต้องไม่ค้างเป็นผี  ปลดออกให้กลายเป็นของร้านปกติ
        local moved = 0
        for _, e in pairs(d.catalog) do
            if e.market == id then e.market = nil; moved = moved + 1 end
        end
        d.markets[id] = nil
        alert(player, "Stall removed. " .. moved .. " listing(s) moved back to the main store.", "good")
    else
        local nm = KR.trunc(args.name, 24)
        if nm == "" then return alert(player, "Name required.", "bad") end
        m.name = nm
        alert(player, "Stall renamed to " .. nm, "good")
    end
    S.syncAll()
end

-- ==============================================================================
-- หน้าจัดการ : เติมเงินให้ผู้เล่น
--
-- ทุกครั้งที่แอดมินเสกเงิน ต้องมีเหตุผลติดไปด้วยและต้องบันทึกไว้เสมอ
-- ไม่ใช่เพราะไม่ไว้ใจแอดมิน แต่เพราะสามเดือนหลังจากนี้จะไม่มีใครจำได้ว่าเงินก้อนนั้นมาจากไหน
--
-- HF เป็นของเราเอง บวกได้ตรง ๆ
-- CASH ต้องผ่าน Akacount เพราะมันมีบัญชีแยกประเภทที่ต้องบาลานซ์
-- CP ไม่รองรับ เพราะเป็นแต้มของ HF Town Rank ต้องไปเติมที่ม็อดนั้น
-- ==============================================================================
function S.adminGrant(player, args)
    if not isStaff(player) then return alert(player, "Admin only.", "bad") end
    local d = ensureSeed()

    local to  = tostring((args and args.to) or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cur = (args and args.cur) or KR.CUR.HF
    local amt = math.floor(tonumber(args and args.amt) or 0)
    local why = KR.trunc(args and args.reason, 48)

    if to == "" or not d.players[to] then
        return alert(player, "No player named '" .. tostring(args and args.to) .. "'.", "bad")
    end
    if amt == 0 then return alert(player, "Amount cannot be zero.", "bad") end
    if why == "" then return alert(player, "Write a reason. It goes in the log.", "bad") end

    local by = key(player)

    if cur == KR.CUR.HF then
        local row = P(to)
        local before = row.hf or 0
        row.hf = math.max(0, before + amt)
        amt = row.hf - before                     -- หักเกินยอดที่มีไม่ได้  บันทึกเท่าที่เกิดขึ้นจริง

    elseif cur == KR.CUR.CASH then
        local B = bank()
        if not B then return alert(player, "Akacount not loaded.", "bad") end
        -- ช่องกรอกของแอดมินเป็น "บาท" เหมือนทุกช่องเงินในม็อด  แต่ ledger เดินเป็นสตางค์
        -- เดิมยัดเลขดิบเข้า mint/burn ตรง ๆ  พิมพ์ 500 เลยได้จริงแค่ 5.00
        -- แปลงจุดเดียวด้วย KR.toCharge เหมือนที่ S.send และ payOption ทำ
        local sub = KR.toCharge(KR.CUR.CASH, math.abs(amt))
        if sub <= 0 then return alert(player, "Amount cannot be zero.", "bad") end
        local ok, err
        if amt > 0 then
            ok, err = B.mint and B.mint(to, sub, "SYS:ADMIN", "kuraya:" .. why, "admin")
        else
            ok, err = B.burn and B.burn(to, sub, "SYS:ADMIN", "kuraya:" .. why, "admin", true)
        end
        if not ok then return alert(player, "Bank refused: " .. tostring(err), "bad") end

    else
        return alert(player, "CP must be granted from HF Town Rank, not here.", "bad")
    end

    hfLog(d, { at = getTimestamp and getTimestamp() or 0, kind = "grant",
               from = by, to = to, amt = amt, cur = cur, why = why })

    -- ป้ายยืนยันต้องบอกยอดที่เกิดขึ้นจริง  amt ยังเป็นบาทอยู่ (ไม่ใช่ตัวที่แปลงแล้ว)
    -- จึงส่งเข้า KR.fmtPrice ได้ตรง ๆ  แต้มยังใช้คำเดิมเพราะไม่มีหน่วยย่อย
    local shown = (cur == KR.CUR.CASH) and KR.fmtPrice(KR.CUR.CASH, amt)
                  or (amt .. " " .. tostring(cur):upper())

    alert(player, "Gave " .. shown .. " to " .. (P(to).disp or to) .. ".", "good")

    local list = getOnlinePlayers and getOnlinePlayers() or nil
    if list then
        for i = 0, list:size() - 1 do
            local pl = list:get(i)
            if key(pl) == to then
                alert(pl, "An admin adjusted your balance: " .. shown ..
                          "  (" .. why .. ")", "good")
                S.sync(pl)
                break
            end
        end
    end
    -- แอดมินคนอื่นที่เปิดหน้าจัดการอยู่ต้องเห็นยอดใหม่ทันที ไม่ใช่ต้องปิดเปิดใหม่
    S.syncAll()
end

-- รายชื่อผู้เล่นพร้อมยอด  ส่งให้แอดมินเท่านั้น
-- ตัดที่ 200 คน  เซิร์ฟที่เล่นมานานจะมีชื่อสะสมเป็นพันและไม่มีใครเลื่อนดูจริง
-- แอดมินปลดล็อกร้านให้ผู้เล่น
function S.adminUnlock(player, args)
    local who = tostring((args and args.to) or "")
    local ok, why = (S.shopUnlock or function() return false, "credit not loaded" end)(who)
    if not ok then return alert(player, "Cannot unlock: " .. tostring(why), "bad") end
    alert(player, "Unlocked " .. who .. ".", "good")
    S.syncAll()
end

-- ------------------------------------------------------------------------------
-- บอกแอดมินทุกคนที่ออนไลน์อยู่พร้อมกัน
--
-- อยู่ที่ไฟล์นี้เพราะไฟล์อื่นเรียกใช้กันหลายที่ (KR_Credit ตอนล็อกร้าน,
-- KR_HFPack ตอนมีคำขอใหม่) และ KR_Server โหลด **หลัง** KR_Credit ตามตัวอักษร
-- ทั้งสองที่จึงเรียกแบบ late-bound (เช็ก type ก่อนเรียก) ไม่ใช่จับ reference ไว้ตอนโหลด
--
-- ข้อจำกัดที่ต้องรู้: นี่คือป้ายที่เด้งแล้วหาย  มันไม่ใช่ที่เก็บงานค้าง
-- เรื่องที่ต้องไม่หลุดหาย (เช่นใครโดนล็อกร้าง) ต้องอยู่ในฐานข้อมูลด้วยเสมอ
-- แล้วให้หน้าจอแอดมินอ่านจากฐาน  ป้ายนี้เป็นแค่การสะกิดคนที่บังเอิญออนไลน์อยู่
-- ------------------------------------------------------------------------------
function S.tellAdmins(msg, tone)
    local list = getOnlinePlayers and getOnlinePlayers()
    if not list then return 0 end
    local n = 0
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p and isStaff(p) then
            alert(p, msg, tone or "warn")
            n = n + 1
        end
    end
    return n
end

-- ------------------------------------------------------------------------------
-- ค้นชื่อผู้เล่นสำหรับช่อง dropdown
--
-- กฎที่เจ้าของเซิร์ฟเคาะไว้ (คำถามข้อ 1 ตอบ "ข"):
--   ผู้เล่นธรรมดา -> เห็นเฉพาะคนที่ **ออนไลน์อยู่ตอนนี้**
--   แอดมิน        -> ค้นคนออฟไลน์ได้ด้วย เพราะเคสที่ต้องสืบมากที่สุด
--                    คือเคสที่เจ้าตัวไม่ได้อยู่ในเกม
--
-- ทำไมรายชื่อต้องมาจากเซิร์ฟ ไม่ใช่ให้จอพิมพ์เอาเอง
--   ชื่อที่พิมพ์ผิดหนึ่งตัวอักษรคือเงินที่โอนเข้าบัญชีที่ไม่มีตัวตน
--   ของเดิมรับสตริงดิบจากช่องพิมพ์แล้วค่อยไปเช็กตอน handler ทำงาน
--   ซึ่งแปลว่าผู้เล่นรู้ว่าพิมพ์ผิดหลังจากกดยืนยันไปแล้ว
-- ------------------------------------------------------------------------------
function S.findPlayer(player, args)
    local d   = db()
    local adm = isStaff(player)
    local me  = key(player)
    local q   = tostring((args and args.q) or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local withSelf = (args and args.self) and true or false

    -- ใครออนไลน์อยู่บ้าง  เก็บเป็นชุดก่อน จะได้ไม่ต้องวนซ้อนกันทีละชื่อ
    local on = {}
    local list = getOnlinePlayers and getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            local k = p and key(p)
            if k then on[k] = true end
        end
    end

    local out = {}
    local function push(k, online)
        if k == me and not withSelf then return end
        if #out >= 40 then return end
        local row = d.players[k]
        local disp = (row and row.disp) or k
        if q ~= "" and not tostring(disp):lower():find(q, 1, true) then return end
        out[#out + 1] = { key = k, disp = disp, online = online or nil }
    end

    for k in pairs(on) do push(k, true) end

    if adm then
        for k in pairs(d.players) do
            if not on[k] then push(k, false) end
        end
    end

    -- ออนไลน์ขึ้นก่อนเสมอ แล้วค่อยเรียงตามชื่อ
    -- คนที่อยู่ในเกมตอนนี้คือคนที่แอดมินจะกดถึง 90% ของเวลา
    table.sort(out, function(a, b)
        if (a.online and true or false) ~= (b.online and true or false) then
            return a.online and true or false
        end
        return tostring(a.disp):lower() < tostring(b.disp):lower()
    end)

    sendServerCommand(player, KR.MODULE, KR.CMD.FIND_PLAYER, { q = q, rows = out })
end

-- ------------------------------------------------------------------------------
-- แอดมินเปิดดูบัญชีของผู้เล่นรายคน
--
-- อ่านอย่างเดียว  ทุกการกระทำ (ปลดล็อก / เติมเงิน / ส่ง HF) ยังต้องเดินผ่าน
-- handler ของมันเองที่มีด่านแอดมินของตัวเอง  หน้านี้ไม่ได้เปิดทางลัดให้ใคร
--
-- ส่งเป็นแพ็กเก็ตแยก ไม่ยัดรวมใน sync  เพราะ sync วิ่งทุกสองวินาทีให้ทุกคน
-- การแนบข้อมูลเต็มของผู้เล่นอีกคนไปกับมันคือการจ่ายค่าแบนด์วิดท์ตลอดเวลา
-- เพื่อของที่แอดมินเปิดดูนาน ๆ ครั้ง
-- ------------------------------------------------------------------------------
function S.accView(player, args)
    local d  = db()
    local to = tostring((args and args.to) or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if to == "" or not d.players[to] then
        return alert(player, "No player named '" .. tostring(args and args.to) .. "'.", "bad")
    end

    local B   = bank()
    local row = P(to)
    local c   = (d.credit or {})[to]
    local ts  = getTimestamp and getTimestamp() or os.time()

    local cash = nil
    if B and B.available then
        local ok, v = pcall(B.available, to)
        if ok and type(v) == "number" then cash = v end
    end

    -- ล็อตประมูลของคนนี้  นับจากตารางจริง ไม่ได้เก็บตัวนับแยกไว้ให้เพี้ยน
    local lots, owing = 0, 0
    for _, lot in pairs(((d.auction or {}).lots) or {}) do
        if lot.seller == to and not lot.done then lots = lots + 1 end
        if lot.top == to and lot.payBy and not lot.settled then owing = owing + 1 end
    end

    -- คำขอแพ็ก HF ที่ยังค้าง  แอดมินมักเปิดหน้านี้เพราะเรื่องนี้พอดี
    local waiting = 0
    for _, r in ipairs(((d.hfpack or {}).reqs) or {}) do
        if r.k == to and r.st == KR.HFP_ST.WAIT then waiting = waiting + 1 end
    end

    sendServerCommand(player, KR.MODULE, KR.CMD.ACC_VIEW, {
        key      = to,
        disp     = row.disp or to,
        online   = (onlinePlayerByKey(to) ~= nil),
        firstSeen = row.firstSeen,
        lastSeen  = row.lastSeen,
        hf       = row.hf or 0,
        cash     = cash,
        card     = (B and B.exists) and B.exists(to) or false,
        locked   = (c and c.shopLock) or nil,
        lockedAt = (c and c.shopLockAt) or nil,
        frozen   = (c and c.frozen) or nil,
        missed   = (c and c.missed) or 0,
        owed     = (c and c.out) or 0,
        plan     = c and c.plan and { at = c.plan.at, amount = c.plan.amount,
                                      nextAt = c.plan.nextAt, rateBp = c.plan.rateBp,
                                      left = c.plan.left } or nil,
        lots     = lots,
        owing    = owing,
        waiting  = waiting,
        slots    = (S.auctSlots and S.auctSlots(to)) or 1,
        tail     = (B and B.recent) and B.recent(to, KR.ACCOUNT_TAIL) or {},
        log      = S.spendLog(to),
        now      = ts,
    })
end

-- ------------------------------------------------------------------------------
-- แอดมินถอนรายได้ร้าน
--
-- ยอดในลิ้นชักคือ "สิทธิ์ในการ mint ตามยอดที่ขายได้" ไม่ใช่เงินที่นอนอยู่ในบัญชีไหน
-- (ดูเหตุผลเต็มที่ปลาย payOption)  จึงต้องกันสองอย่างให้แน่น
--   1. ถอนเกินยอดไม่ได้เด็ดขาด  ไม่งั้นแอดมินเสกเงินเข้าเซิร์ฟได้ไม่จำกัด
--   2. ทุกครั้งที่ถอนต้องจดชื่อคนถอน  เซิร์ฟที่มีแอดมินหลายคนต้องตามได้ว่าใครเอาไป
-- ------------------------------------------------------------------------------
function S.tillTake(player, args)
    local d = ensureSeed()
    d.till = d.till or { cash = 0, taken = 0, log = {} }

    local B = bank()
    if not (B and B.mint) then
        return alert(player, "Akacount cannot pay out right now (no mint).", "bad")
    end

    local have = math.max(0, math.floor(tonumber(d.till.cash) or 0))
    if have <= 0 then return alert(player, "The till is empty.", "bad") end

    -- ว่างไว้ = ถอนทั้งหมด  ตัวเลขที่กรอกเป็นบาท ลิ้นชักเก็บเป็นสตางค์
    local want = tonumber(args and args.n)
    local take = want and math.floor(want * KR.SUBUNIT) or have
    take = math.max(0, math.min(take, have))
    if take <= 0 then return alert(player, "Enter an amount above zero.", "bad") end

    local k = key(player)
    local okMint = pcall(B.mint, k, take, "SYS:SHOP", "kuraya:till", "admin")
    if not okMint then
        return alert(player, "Akacount refused the payout. Nothing was taken.", "bad")
    end

    -- ลดยอดหลังจ่ายสำเร็จเท่านั้น  ลดก่อนแล้วจ่ายพลาด = รายได้หายไปเฉย ๆ
    d.till.cash  = have - take
    d.till.taken = (tonumber(d.till.taken) or 0) + take
    d.till.log   = d.till.log or {}
    d.till.log[#d.till.log + 1] = { at = getTimestamp and getTimestamp() or 0,
                                    by = k, n = take }
    while #d.till.log > 50 do table.remove(d.till.log, 1) end

    alert(player, "Took " .. KR.fmtPrice(KR.CUR.CASH, take / KR.SUBUNIT) ..
                  " from the shop till.", "good")
    S.syncAll()
end

function S.playerRows()
    local d, out = db(), {}
    local B = bank()

    -- ใครออนไลน์อยู่  แผงแจ้งเตือนต้องบอกได้ว่าคนที่โดนล็อกอยู่ในเกมไหม
    -- (คนที่อยู่ในเกมคือคนที่ปลดล็อกให้แล้วเขารู้ทันที)
    local on = {}
    local list = getOnlinePlayers and getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            local kk = p and key(p)
            if kk then on[kk] = true end
        end
    end

    for k, row in pairs(d.players) do
        -- ส่งสถานะหนี้มาด้วย  แอดมินต้องเห็นว่าใครโดนล็อกอยู่โดยไม่ต้องไล่ถามทีละคน
        -- คนที่โดนล็อกร้านมักไม่รู้ตัวว่าต้องมาบอกใคร เขาแค่เห็นว่าซื้อของไม่ได้
        local c = (d.credit or {})[k]
        local r = { key = k, disp = row.disp or k, hf = row.hf or 0,
                    lastSeen = row.lastSeen,
                    online = on[k] or nil,
                    locked = (c and c.shopLock) or nil,
                    lockedAt = (c and c.shopLockAt) or nil,
                    frozen = (c and c.frozen) or nil,
                    missed = (c and c.missed) or nil,
                    owed   = (c and c.out) or nil }

        -- ยอดคงเหลือจริงส่งเฉพาะคนที่มีปัญหาเรื่องเงิน
        --
        -- B.available เป็นการอ่านข้าม ledger  เรียกให้ครบสองร้อยคนทุก ๆ สองวินาที
        -- คือค่าใช้จ่ายถาวรเพื่อข้อมูลที่แทบไม่มีใครดู
        -- แผงที่ต้องใช้ตัวเลขนี้จริง ๆ มีแค่แผงคนโดนล็อกกับคนที่ผิดนัด ซึ่งมีไม่กี่คน
        if B and B.available and (r.locked or r.frozen or (r.owed or 0) > 0) then
            local ok, v = pcall(B.available, k)
            if ok and type(v) == "number" then r.bal = v end
        end

        out[#out + 1] = r
        if #out >= 200 then break end
    end
    table.sort(out, function(a, b) return (a.disp or ""):lower() < (b.disp or ""):lower() end)
    return out
end

-- ------------------------------------------------------------------------------
-- ลายบัตร  Kuraya เป็นที่เดียวที่เปลี่ยนลายได้ (เลือกแล้วเลือกเลย เปลี่ยนที่ร้าน)
-- ------------------------------------------------------------------------------
function S.setCardSkin(player, args)
    local B = bank()
    if not (B and B.setPlayerSkin) then return alert(player, "Bank offline.", "bad") end
    local k = key(player)
    local id = args and args.skin
    local ok, err = B.setPlayerSkin(k, id)
    alert(player, ok and "Card design updated." or ("Cannot use that design: " .. tostring(err)),
          ok and "good" or "bad")
    S.sync(player)
end

-- ------------------------------------------------------------------------------
-- sync  ส่งเฉพาะสิ่งที่ผู้เล่นคนนี้ควรเห็น
-- ------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------
-- หมวดสินค้า
--
-- รายการหมวดไม่ได้ถูกประกาศไว้ในโค้ด  มันมาจากของที่แอดมินลงจริง ๆ
-- ข้อดี: ลบของชิ้นสุดท้ายในหมวดไหน หมวดนั้นหายไปเอง ไม่ต้องมาไล่เก็บกวาด
-- d.cats เก็บแค่ "ลำดับ" ที่แอดมินจัดไว้  หมวดที่ไม่มีของแล้วจะถูกข้าม
-- ------------------------------------------------------------------------------
function S.catList()
    local d = db()
    d.cats = d.cats or {}

    local count = {}
    for _, e in pairs(d.catalog) do
        if e.enabled ~= false then
            local c = KR.catKey(e.cat)
            count[c] = (count[c] or 0) + 1
        end
    end

    local order, seen = {}, {}
    for _, c in ipairs(d.cats) do
        if count[c] and not seen[c] then
            seen[c] = true
            order[#order + 1] = { id = c, n = count[c] }
        end
    end

    -- หมวดใหม่ที่ยังไม่เคยจัดลำดับ ต่อท้ายแบบเรียงชื่อ เพื่อให้ลำดับคงที่ทุกเฟรม
    local rest = {}
    for c in pairs(count) do
        if not seen[c] then rest[#rest + 1] = c end
    end
    table.sort(rest)
    for _, c in ipairs(rest) do
        order[#order + 1] = { id = c, n = count[c] }
        d.cats[#d.cats + 1] = c
    end
    return order
end

-- ค่าตั้งส่วนตัวของผู้เล่น  ตอนนี้มีแค่ "หมวดที่ดูอยู่ล่าสุด"
-- เก็บฝั่งเซิร์ฟเพราะผู้เล่นย้ายเครื่องแล้วต้องยังจำได้
function S.setPref(player, args)
    local k = key(player); if not k then return end
    local p = P(k)
    p.ui = p.ui or {}
    if args and args.cat ~= nil then
        p.ui.cat = (args.cat == KR.CAT_ALL) and KR.CAT_ALL or KR.catKey(args.cat)
    end
end

-- แอดมินจัดหมวด  เปลี่ยนชื่อ (ตามไปแก้ของทุกชิ้น) หรือเลื่อนลำดับ
function S.adminCats(player, args)
    if not isStaff(player) then return alert(player, "Admin only.", "bad") end
    local d = ensureSeed()
    d.cats = d.cats or {}
    local from = args and args.cat and KR.catKey(args.cat)
    if not from then return end

    if args.rename then
        local to = KR.catKey(args.rename)
        if to == from then return end
        local n = 0
        for _, e in pairs(d.catalog) do
            if KR.catKey(e.cat) == from then e.cat = to; n = n + 1 end
        end
        for i, c in ipairs(d.cats) do if c == from then d.cats[i] = to end end
        alert(player, "Renamed to '" .. to .. "' on " .. n .. " listing(s).", "good")

    elseif args.move then
        local dir = (tonumber(args.move) or 0) >= 0 and 1 or -1
        for i, c in ipairs(d.cats) do
            if c == from then
                local j = i + dir
                if j >= 1 and j <= #d.cats then d.cats[i], d.cats[j] = d.cats[j], d.cats[i] end
                break
            end
        end
    end
    S.syncAll()
end

function S.sync(player)
    if not player then return end
    touch(player)

    local d = ensureSeed()
    local B = bank()
    local hereId = S.marketAt(player)
    local nowTs  = getTimestamp and getTimestamp() or os.time()

    -- ของเข้าใหม่รายวัน  ทำงานจริงวันละครั้ง ที่เหลือคืน false ทันที
    -- เกาะกับ sync แทนที่จะใช้ตัวจับเวลา เพราะเซิร์ฟที่ปิดข้ามวันจะพลาด event รายวัน
    S.rotateDaily(nowTs)

    -- ปิดประมูลที่หมดเวลา  เหตุผลเดียวกัน
    if S.auctionTick then S.auctionTick(nowTs) end

    -- หักบิลอัตโนมัติ  เกาะกับ sync ด้วยเหตุผลเดียวกันอีกเช่นกัน
    -- ตัวมันเองมีตัวกันไม่ให้ทำงานถี่กว่านาทีละครั้ง  และมันหักให้ "ทุกคน" ไม่ใช่แค่คนนี้
    -- เพราะเจ้าของเซิร์ฟเลือกไว้ว่าต้องหักแม้เจ้าตัวไม่ได้ออนไลน์
    if S.billTick then pcall(S.billTick) end

    -- จดว่าเห็นคนนี้อยู่ในเซฟเฮาส์หลังไหน  นาฬิกา 3 วันของเงินกู้เริ่มเดินจากตรงนี้
    -- เกาะกับ sync เพราะมันคือจุดเดียวที่เรารู้ว่าผู้เล่นอยู่ตรงไหน "ตอนนี้"
    -- และมันเดินทุกสองวินาทีตอนเปิดร้าน ซึ่งถี่พอสำหรับความละเอียดระดับวัน
    if S.safehouseTouch then pcall(S.safehouseTouch, player) end

    -- ==========================================================================
    -- ของที่ปิดอยู่ (enabled = false) ต้องไม่ออกจากเครื่องเซิร์ฟเวอร์เลย
    --
    -- ไคลเอนต์กรองให้อยู่แล้วก็จริง (KRShop:rows ข้ามของที่ปิด) แต่นั่นเป็นแค่มารยาท
    -- ของที่ส่งออกไปแล้วถือว่าหลุดแล้ว  ไคลเอนต์ที่ถูกแก้จะวาดทุกอย่างที่ได้รับ
    -- ชื่อของที่ยังไม่เปิดตัว ราคาที่ยังตั้งไม่เสร็จ และของที่แอดมินตั้งใจซ่อน
    -- จึงต้องถูกตัดออกตั้งแต่ตอนประกอบแพ็กเก็ต ไม่ใช่ตอนวาด
    --
    -- ทำสำเนาแค่ชั้นเดียว (คีย์ -> ตารางเดิม) ไม่ได้ก๊อปตัวรายการ
    -- ราคาคือ O(n) เท่าเดิมกับที่ S.catList กับลูปโควตาข้างล่างทำอยู่ทุก sync แล้ว
    -- ==========================================================================
    local isAdm  = isStaff(player)
    local pubCat = d.catalog
    if not isAdm then
        pubCat = {}
        for id, e in pairs(d.catalog) do
            if e.enabled ~= false then pubCat[id] = e end
        end
    end

    -- โควตาเป็นของรายคน ส่งแยกจากแคตตาล็อกที่ทุกคนเห็นเหมือนกัน
    -- ส่งเฉพาะรายการที่ตั้งโควตาไว้จริง  ที่เหลือไม่ต้องเปลืองแพ็กเก็ต
    -- ต้องเดินบน pubCat ไม่ใช่ d.catalog  ไม่งั้นไอดีของที่ซ่อนไว้จะรั่วไปทางตารางโควตา
    local quota = {}
    for id, e in pairs(pubCat) do
        if KR.quotaOf(e) > 0 then
            e.id = e.id or id
            quota[id] = S.quotaLeft(player, e, nowTs)
        end
    end

    local dayKey = math.floor(nowTs / KR.DAY_SEC)

    sendServerCommand(player, KR.MODULE, KR.CMD.SYNC, {
        me       = key(player),          -- ประวัติต้องรู้ว่า "ฉัน" คือใคร ถึงจะแยกเข้า/ออกได้
        name     = KR.trunc(tostring((player.getUsername and player:getUsername()) or key(player)), 20),
        catalog  = pubCat,              -- แอดมินได้ของจริงทั้งชุด  ผู้เล่นได้เฉพาะของที่เปิดขาย
        markets  = d.markets,           -- รายการเห็นได้ทุกที่  ซื้อไม่ได้ถ้าไม่ได้อยู่
        atMarket = hereId,
        bal      = S.balances(player),
        quota    = quota,
        now      = nowTs,
        saleCount = S.saleCount(nowTs),               -- ไคลเอนต์นับถอยหลังโปรจากเวลานี้ ไม่ใช่นาฬิกาเครื่องตัวเอง
        newCount  = #((d.rotate or {}).ids or {}),    -- ของเข้าใหม่วันนี้กี่ชิ้น  ใช้ตัดสินอารมณ์แมวด้วย
        cats      = S.catList(),                      -- หมวดที่มีของอยู่จริง เรียงตามที่แอดมินจัด
        -- ---- หมวดทั้งหมดที่เคยใช้  สำหรับดร็อปดาวน์ของแอดมินเท่านั้น  (0.6.13) ----
        --
        -- เจ้าของเซิร์ฟรายงาน "พอเพิ่มไปหมวดนึง หมวดอื่นหาย"
        -- ต้นเหตุ: ดร็อปดาวน์หมวดในฟอร์มอ่านจาก cats ตัวเดียวกับที่ร้านใช้
        -- ซึ่ง S.catList() กรองเฉพาะหมวด **ที่มีของเปิดขายอยู่**
        --
        -- กติกานั้นถูกสำหรับผู้เล่น (ไม่ควรเห็นหมวดว่าง) แต่ผิดสำหรับแอดมิน:
        -- ย้ายของชิ้นสุดท้ายออกจากหมวดหนึ่ง = หมวดนั้นหายจากดร็อปดาวน์ทันที
        -- แล้วเขาก็พิมพ์ชื่อเองใหม่ ซึ่งพิมพ์ผิดได้ และกลายเป็นหมวดที่สองที่ชื่อคล้ายกัน
        --
        -- d.cats จำลำดับไว้อยู่แล้วและไม่เคยลบใคร  ส่งตัวนั้นไปตรง ๆ
        catsAll   = isStaff(player) and (function()
            local out = {}
            for i, c in ipairs(d.cats or {}) do out[i] = c end
            return out
        end)() or nil,
        -- กระดานราคาสินค้าโลก  (0.7.0)  ส่งให้ทุกคน ไม่ใช่แค่แอดมิน
        -- มันคือกระดาษราคาอ้างอิงที่มีไว้ให้คนซื้อขายกันเองอ่าน  ซ่อนจากผู้เล่นแล้วมันไม่มีประโยชน์
        -- **ไม่มีราคาซื้อ ไม่มีชนิดไอเทม ไม่มีสต็อก** อยู่ในนี้ ดู KR_Stats.boardPayload
        board     = S.boardPayload and S.boardPayload() or nil,
        pref      = P(key(player)).ui or {},          -- หมวดที่ผู้เล่นดูอยู่ล่าสุด
        feed      = feedTail(d),                      -- ป้ายไฟ
        stamp     = KR.stampState(P(key(player))),    -- บัตรสะสม
        auction   = S.auctionRows and S.auctionRows(player, nowTs) or nil,
        -- เซิร์ฟนี้เปิดให้ผู้เล่นลงประมูลเองไหม  จอใช้ตัดสินว่าจะวาดปุ่มเปิดล็อตให้ใคร
        auctSell  = (S.auctSellAllowed and S.auctSellAllowed()) or false,
        auctSlots = (S.auctSlots and S.auctSlots(key(player))) or 1,
        auctSlotPrice = KR.auctSlotOpt("PRICE"),
        auctSlotMax   = KR.auctSlotOpt("MAX"),
        credit    = S.creditRow  and S.creditRow(player, nowTs)  or nil,
        -- แพ็ก HF  ฝั่งเซิร์ฟตัดสินแล้วว่าคนนี้ควรเห็นอะไร ไม่ใช่ส่งทั้งหมดให้จอเลือก
        hfp       = S.hfpRows    and S.hfpRows(player, nowTs)    or nil,
        -- บิลค่าบ้าน / ภาษี  สถานะการหักอัตโนมัติกับยอดค้าง
        bill      = S.billRow    and S.billRow(player)           or nil,
        -- ป้ายที่ค้างไว้ตอนเขาไม่อยู่  ดึงออกมาแล้วล้างทิ้ง ส่งครั้งเดียวเท่านั้น
        billNote  = S.billNotes  and S.billNotes(player)         or nil,
        skin     = (B and B.getPlayerSkin) and B.getPlayerSkin(key(player)) or nil,
        skins    = (B and B.getCardSkins)  and B.getCardSkins()             or {},
        -- เดินบัญชีล่าสุด  โชว์ในจอ Account ที่เกาะข้างร้าน
        -- ตั้งใจให้ได้แค่ไม่กี่รายการ  ประวัติเต็มยังต้องไปที่ธนาคารตามที่ตกลงกันไว้
        tail     = (B and B.recent) and B.recent(key(player), KR.ACCOUNT_TAIL) or {},
        card     = (B and B.exists) and B.exists(key(player)) or false,
        acts     = S.accountButtons(key(player)),   -- ปุ่มจากม็อดอื่น  ว่าง = ยังไม่มีใครลงทะเบียน
        cards    = S.accountCards(player),          -- การ์ดใหญ่จากม็อดอื่น เช่น บิลค่าบ้าน

        -- ระดับการใช้จ่าย + ประวัติการใช้จ่ายในร้าน
        -- ตั้งใจแยกจาก tail ของธนาคารด้านบน  คนละเรื่องกันคนละสมุด
        tier     = KR.tierState(P(key(player))),
        log      = S.spendLog(key(player)),
        spent7   = select(1, KR.spendWindow(S.spendLog(key(player)), nowTs)),
        spent7n  = select(2, KR.spendWindow(S.spendLog(key(player)), nowTs)),
        bankOk   = B ~= nil,
        trOk     = KR.tr.available(),
        -- ธงเดียวที่จอทั้งม็อดใช้ตัดสินว่าจะวาดของแอดมินไหม
        -- รวมถึงเมนูคลิกขวาในโลก (KR_EscMenu) ที่เคยถาม getAccessLevel เองแล้วตอบผิด
        admin    = isAdm,
        -- สิ่งที่มีเฉพาะแอดมิน ต้องเป็น nil ไปเลยสำหรับผู้เล่น ไม่ใช่ส่งตารางว่าง
        -- ส่งตารางว่าง = ยอมรับว่าฟิลด์นี้มีอยู่ แล้ววันหลังจะมีคนเผลอเติมของลงไป
        players  = isAdm and S.playerRows() or nil,
        -- รายได้ร้าน  เป็นของแอดมินล้วน ผู้เล่นไม่ต้องรู้ว่าร้านเก็บได้เท่าไร
        till     = isAdm and { cash = (d.till or {}).cash or 0,
                               taken = (d.till or {}).taken or 0 } or nil,
        bank     = isAdm and caps() or nil,   -- ผลตรวจ Akacount  แอดมินเห็นในหน้าจัดการ
        ver      = KR.VERSION,
        send     = {
            min     = KR.hfSendOpt("MIN"),
            feeBp   = KR.hfSendOpt("FEE_BP"),
            daily   = KR.hfSendOpt("DAILY"),
            usedToday = sentToday(d, key(player), dayKey),
            names   = S.recipients(),
        },
    })
end

-- ------------------------------------------------------------------------------
-- ตารางคำสั่ง
--
-- ห้ามเขียนเป็น table literal เด็ดขาด  ถ้ามีค่าคงที่ตัวไหนสะกดผิดหรือลืมประกาศ
-- มันจะกลายเป็น { [nil] = fn } ซึ่ง Lua โยน "table index is nil" ทันที
-- ผลคือ **ทั้งไฟล์นี้โหลดไม่ผ่าน** และไม่มี handler ตัวไหนถูกลงทะเบียนเลย
-- Akacount เคยโดนมาแล้วครั้งหนึ่ง กว่าจะรู้ว่าเป็นเพราะอะไรก็หลายรอบ
-- ------------------------------------------------------------------------------
-- ทะเบียนคำสั่ง  แต่ละแถวประกาศไปเลยว่าต้องเป็นแอดมินไหม
--
-- ทำไมด่านต้องอยู่ที่ dispatcher ไม่ใช่ในตัว handler
--   ของเดิม handler แต่ละตัวเช็ก isAdmin เองที่บรรทัดแรก  ซึ่ง "ตอนนี้" ครบทุกตัวจริง
--   แต่มันเป็นความครบที่ต้องพึ่งความจำของคนเขียนคนถัดไป
--   handler ใหม่ที่ลืมบรรทัดนั้นไปหนึ่งบรรทัด = ผู้เล่นสั่งงานแอดมินได้ทันที
--   และไม่มีอะไรบนจอหรือใน log บอกเลย
--
--   พอย้ายมาอยู่ตรงนี้ ด่านกลายเป็น "ข้อมูล" ที่อ่านได้ทั้งตารางในสิบวินาที
--   ไม่ใช่ "พฤติกรรม" ที่ต้องไล่เปิดทีละฟังก์ชันเพื่อยืนยัน
--
-- handler ยังเช็กซ้ำในตัวเองได้ตามเดิม  ด่านสองชั้นไม่เสียหาย
local HANDLERS = {}
local ADMIN_ONLY = {}

local function reg(name, cmd, fn, adminOnly)
    if type(cmd) ~= "string" or cmd == "" then
        print("[Kuraya] !! command constant missing for '" .. tostring(name) .. "' - handler not installed")
        return
    end
    if type(fn) ~= "function" then
        print("[Kuraya] !! handler for '" .. tostring(name) .. "' is not a function - skipped")
        return
    end
    HANDLERS[cmd] = fn
    if adminOnly then ADMIN_ONLY[cmd] = name end
end

local ADMIN = true    -- อ่านที่ท้ายบรรทัดแล้วรู้ทันทีว่าแถวไหนเป็นของแอดมิน

reg("REQ_SYNC",      KR.CMD.REQ_SYNC,      function(p) S.sync(p) end)
reg("BUY",           KR.CMD.BUY,           S.buy)
reg("SET_CARD_SKIN", KR.CMD.SET_CARD_SKIN, S.setCardSkin)
reg("SEND_HF",       KR.CMD.SEND_HF,       S.send)   -- รองรับ hf/cp ผ่าน args.cur
reg("SAVE_BTN",      KR.CMD.SAVE_BTN,      S.saveBtn)
reg("REQ_BTN",       KR.CMD.REQ_BTN,       S.reqBtn)
reg("ACCOUNT_ACTION",KR.CMD.ACCOUNT_ACTION,S.accountAction)

reg("ADMIN_MARKET",  KR.CMD.ADMIN_MARKET,  S.adminMarket,    ADMIN)
reg("ADMIN_SAVE",    KR.CMD.ADMIN_SAVE,    S.adminSave,      ADMIN)
reg("ADMIN_DEL",     KR.CMD.ADMIN_DEL,     S.adminDel,       ADMIN)
reg("ADMIN_MARKET_SET", KR.CMD.ADMIN_MARKET_SET, S.adminMarketSet, ADMIN)
reg("ADMIN_GRANT",   KR.CMD.ADMIN_GRANT,   S.adminGrant,     ADMIN)
reg("ADMIN_UNLOCK",  KR.CMD.ADMIN_UNLOCK,  S.adminUnlock,    ADMIN)

-- ประมูลกับเงินกู้อยู่คนละไฟล์  ลงทะเบียนที่นี่เพราะ dispatch อยู่ที่นี่ที่เดียว
-- ห่อด้วย function() end แทนที่จะส่ง S.auctBid ตรง ๆ
-- เพราะตอนบรรทัดนี้ทำงาน KR_Auction.lua อาจยังไม่ถูกโหลด (PZ ไม่รับประกันลำดับ)
-- ถ้าส่งตรง ๆ จะได้ nil ค้างไว้ตลอดเซสชัน แล้วปุ่มกดไม่ติดแบบเงียบ ๆ
local function later(name)
    return function(p, a2)
        local fn = S[name]
        if type(fn) ~= "function" then
            return alert(p, "That feature is not loaded on this server.", "bad")
        end
        fn(p, a2)
    end
end

reg("AUCT_BID",      KR.CMD.AUCT_BID,      later("auctBid"))
reg("AUCT_SELL",     KR.CMD.AUCT_SELL,     later("auctSell"))
reg("AUCT_CANCEL",   KR.CMD.AUCT_CANCEL,   later("auctCancel"))
reg("AUCT_CLAIM",    KR.CMD.AUCT_CLAIM,    later("auctClaim"))
reg("AUCT_PAY",      KR.CMD.AUCT_PAY,      later("auctPay"))
reg("AUCT_SLOT",     KR.CMD.AUCT_SLOT,     later("auctBuySlot"))
reg("CREDIT_BORROW", KR.CMD.CREDIT_BORROW, later("creditBorrow"))
reg("CREDIT_REPAY",  KR.CMD.CREDIT_REPAY,  later("creditRepay"))
reg("SET_PREF",      KR.CMD.SET_PREF,      S.setPref)
reg("ADMIN_CATS",    KR.CMD.ADMIN_CATS,    S.adminCats,      ADMIN)

-- แพ็ก HF Point  อยู่คนละไฟล์เหมือนประมูล จึงต้องผูกแบบ late-bound
-- สองแถวแรกเป็นของผู้เล่น  สามแถวหลังเป็นของแอดมินล้วน
reg("HFP_REQ",       KR.CMD.HFP_REQ,       later("hfpReq"))
reg("HFP_CANCEL",    KR.CMD.HFP_CANCEL,    later("hfpCancel"))
reg("HFP_SET",       KR.CMD.HFP_SET,       later("hfpSet"),  ADMIN)
reg("HFP_ACT",       KR.CMD.HFP_ACT,       later("hfpAct"),  ADMIN)
reg("HFP_SEND",      KR.CMD.HFP_SEND,      later("hfpSend"), ADMIN)

-- ค้นชื่อผู้เล่น  ไม่ใช่ของแอดมินอย่างเดียว ผู้เล่นก็ใช้ตอนโอนเงิน
-- ตัว handler เป็นคนตัดสินเองว่าคนถามเป็นแอดมินไหม แล้วค่อยตัดคนออฟไลน์ออก
reg("FIND_PLAYER",   KR.CMD.FIND_PLAYER,   S.findPlayer)
reg("ACC_VIEW",      KR.CMD.ACC_VIEW,      S.accView,        ADMIN)
reg("TILL_TAKE",     KR.CMD.TILL_TAKE,     S.tillTake,       ADMIN)
reg("BILL_SET",      KR.CMD.BILL_SET,      later("billSet"))
reg("CAR_LIST",      KR.CMD.CAR_LIST,      later("carList"),   ADMIN)
reg("CAR_UNPACK",    KR.CMD.CAR_UNPACK,    later("carUnpack"))
reg("PET_LIST",      KR.CMD.PET_LIST,      later("petList"),   ADMIN)
reg("PET_UNPACK",    KR.CMD.PET_UNPACK,    later("petUnpack"))

-- 0.7.0  สถิติ · สกิล · กระดานราคา  ทุกตัวเป็นของแอดมินล้วน
-- late-bound เหมือนประมูลกับสัตว์  KR_Stats.lua อาจยังไม่ถูกโหลดตอนบรรทัดนี้ทำงาน
reg("STATS_GET",     KR.CMD.STATS_GET,     later("statsGet"),  ADMIN)
reg("SKILLS_GET",    KR.CMD.SKILLS_GET,    later("skillsGet"), ADMIN)
reg("BOARD_SET",     KR.CMD.BOARD_SET,     later("boardSet"),  ADMIN)
reg("BOARD_DEL",     KR.CMD.BOARD_DEL,     later("boardDel"),  ADMIN)
reg("BOARD_CATS",    KR.CMD.BOARD_CATS,    later("boardCats"), ADMIN)

-- ------------------------------------------------------------------------------
-- ผูก event เฉพาะฝั่งที่เป็นเจ้าของข้อมูล
-- PZ โหลด media/lua/server/ บนไคลเอนต์ MP ด้วย ไม่ได้กันให้
-- ------------------------------------------------------------------------------
local function isHost()
    local sv = (type(isServer) == "function") and isServer() or false
    if sv then return true end
    local cl = (type(isClient) == "function") and isClient() or false
    if cl then return false end
    return true
end

local function on(name, fn, label)
    local ev = Events and Events[name]
    if not ev or type(ev.Add) ~= "function" then
        print("[Kuraya] event not on this build, skipped: " .. tostring(name))
        return
    end
    ev.Add(function(...)
        local ok, err = pcall(fn, ...)
        if not ok then print("[Kuraya] error in " .. tostring(label or name) .. " -> " .. tostring(err)) end
    end)
end

if isHost() then
    on("OnClientCommand", function(module, command, player, args)
        if module ~= KR.MODULE then return end
        local h = HANDLERS[command]
        if not h then return end

        -- ด่านเดียวของทั้งม็อด
        -- ปฏิเสธแล้วต้อง **จด** ด้วย  แพ็กเก็ตแอดมินที่มาจากคนที่ไม่ใช่แอดมิน
        -- ไม่ใช่อุบัติเหตุ  จอไม่เคยวาดปุ่มพวกนั้นให้เขาตั้งแต่ต้น
        local why = ADMIN_ONLY[command]
        if why and not isStaff(player) then
            print("[Kuraya] SECURITY: " .. tostring(key(player) or "?") ..
                  " sent admin command " .. tostring(why) .. " without access")
            return alert(player, "Admin only.", "bad")
        end

        -- ==================================================================
        -- handler ที่ระเบิดต้อง **ตอบกลับ** ไม่ใช่เงียบ
        --
        -- อาการที่เจ้าของเซิร์ฟรายงาน: กดซื้อแล้วป้ายค้างที่ "Sending your order..."
        -- แล้วไม่มีอะไรต่อเลย
        --
        -- สาเหตุเชิงโครงสร้าง: `on()` ห่อ pcall ไว้รอบ OnClientCommand ทั้งก้อน
        -- error จึงถูกกลืนแล้วพิมพ์ลง console **ของเซิร์ฟ** ที่เดียว
        -- ผู้เล่นบนไคลเอนต์ไม่มีทางรู้เลยว่าเกิดอะไรขึ้น และเจ้าของเซิร์ฟที่ไม่ได้
        -- เปิด console ค้างไว้ตอนนั้นก็ไม่รู้เหมือนกัน
        -- = บั๊กที่มองไม่เห็นทั้งสองฝั่งพร้อมกัน ซึ่งเป็นชนิดที่แพงที่สุด
        --
        -- pcall ตรงนี้แคบกว่า (ล้อมแค่ handler เดียว) และสำคัญกว่าตรงที่มัน **พูด**
        -- ข้อความ Lua ดิบไม่สวย แต่มันคือข้อมูลจริง และมันไปถึงคนที่แก้ได้
        -- ยังพิมพ์ลง console เหมือนเดิมด้วย  สองทางไม่ได้ทับกัน
        local okRun, err = pcall(h, player, args)
        if not okRun then
            print("[Kuraya] !! handler '" .. tostring(command) .. "' crashed for " ..
                  tostring(key(player) or "?") .. " -> " .. tostring(err))
            alert(player, "Server error in '" .. tostring(command) .. "': " ..
                          tostring(err), "bad")
        end
    end, "OnClientCommand")

    on("OnInitGlobalModData", function()
        db()
        S.bankReport()
        print("[Kuraya] server ready  v" .. KR.VERSION)
    end, "boot")

    -- ตรวจซ้ำตอนเซิร์ฟขึ้นจริง
    --
    -- OnInitGlobalModData ยิงตอนโหลด mod data ซึ่งบางบิลด์มาก่อนที่ Akacount
    -- จะประกาศ API ของตัวเองเสร็จ  ผลตรวจรอบแรกเลยอาจบอกว่า "ไม่มี" ทั้งที่เดี๋ยวก็มี
    -- รอบสองนี้คือรอบที่เชื่อได้  บรรทัดที่ต่างกันสองรอบก็บอกอะไรได้เองอยู่แล้ว
    on("OnServerStarted", function()
        _caps, _capsFor = nil, nil     -- ล้างของที่แคชไว้ก่อน ไม่งั้นได้คำตอบเดิม
        S.bankReport()
    end, "boot2")
else
    print("[Kuraya] client side - server handlers not installed (this is normal)")
end

-- ตั้งธงท้ายสุด  ถ้าไฟล์นี้ระเบิดกลางทาง รอบหน้าจะได้โหลดใหม่แทนที่จะคืนของครึ่ง ๆ กลาง ๆ
S.__ready = true

return S
