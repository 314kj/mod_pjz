-- ==============================================================================
-- Kuraya 蔵屋 — HaftFull Shop  [PZ Build 42]
-- shared/Kuraya/KR_Const.lua
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- 蔵 = โกดังเก็บของและของมีค่าของพ่อค้าญี่ปุ่น   屋 = คำต่อท้ายชื่อร้าน
--
-- Kuraya พึ่ง Akacount ทางเดียว  Akacount ห้ามรู้จัก Kuraya เลย
-- mod.info มี require=Akacount
-- ==============================================================================

KR = KR or {}

KR.MOD_ID  = "Kuraya"
KR.MODULE  = "Kuraya_Net"
KR.VERSION = "0.7.1"
KR.WORKSHOP_ID = "3779906331"   -- Steam Workshop item id (Kuraya)
KR.AC_WORKSHOP_ID = "3779906527" -- Steam Workshop item id (Akacount, required)
KR.SCHEMA  = 5

-- พิมพ์ทุกครั้งที่โหลด  เวลาเจอบั๊กจะได้รู้ทันทีว่ากำลังรันเวอร์ชันไหนอยู่
-- (เคยเสียเวลาไล่บั๊กที่แก้ไปแล้ว เพราะเครื่องยังโหลดไฟล์เก่าค้างอยู่)
print("[Kuraya] KR_Const  v" .. KR.VERSION .. "  schema " .. KR.SCHEMA)

KR.DB_KEY  = "Kuraya_DB"

-- ------------------------------------------------------------------------------
-- สามสกุลเงิน สามเจ้าของ
--   CASH  -> Akacount        (ฝากเงินสดที่ลูทได้ + ดอกเบี้ย)
--   HF    -> Kuraya เอง      (เควสและกิจกรรมเซิร์ฟ)
--   CP    -> HF Town Rank    (แต้มชุมชน แลกของหายาก)
-- ------------------------------------------------------------------------------
-- ==============================================================================
-- ภาษา
--
-- PZ ใช้ bitmap font แยกตามภาษา  ถ้าชุดฟอนต์ที่ผู้เล่นใช้ไม่มีอักษรไทย
-- ตัวหนังสือไทยจะกลายเป็นกล่องสี่เหลี่ยมหรือหายไปทั้งบรรทัด
--
-- แทนที่จะเดา  ให้ "วัด" เอาตอนเริ่มเกม
--   วาดสตริงไทยแล้ววัดความกว้าง  ถ้ากว้างเท่ากับสตริงว่าง แปลว่าไม่มีกลิฟ
-- แล้วสลับทุกป้ายเป็นอังกฤษอัตโนมัติ  ม็อดจะได้ไม่มีวันขึ้นเป็นกล่องทั้งจอ
--
-- ทุกป้ายในม็อดต้องเขียนผ่าน KR.L("ไทย", "English") ห้ามฝังสตริงตรง ๆ
-- ==============================================================================
-- ------------------------------------------------------------------------------
-- ภาษา  ตัดสินใจแล้วว่า UI เป็นอังกฤษล้วน
--
-- PZ B42 โหลดฟอนต์จาก media/fonts เป็น bitmap atlas ที่ทำมาสำหรับ Latin + Cyrillic
-- ไม่มี glyph ของไทยอยู่ในนั้น  พอส่งไบต์ UTF-8 ของไทยเข้าไป มันแมปมั่ว
-- ออกมาเป็น "@2L@-#L22#" อย่างที่เห็นในเกม  ไม่ใช่บั๊กของม็อด แต่คือฟอนต์ไม่มีตัวอักษร
--
-- ทางแก้จริงคือทำ bitmap font ไทยเองแล้ว inject เข้า TextManager ซึ่งต้องแตะฝั่ง Java
-- ม็อดที่โหลดผ่าน Workshop ทำไม่ได้  เลยเลือกทางที่ใช้งานได้จริง = อังกฤษล้วน
--
-- KR.L(th, en) ยังอยู่ เพราะเรียกไว้ทั่วโค้ดแล้ว  แต่มันคืน en เสมอ
-- ถ้าวันหนึ่งมีฟอนต์ไทยจริง เปลี่ยนที่เดียวตรงนี้ทั้งม็อดกลับมาเป็นไทยได้ทันที
-- ------------------------------------------------------------------------------
KR.thaiOK = false        -- ล็อกไว้ false  ไม่ต้อง probe แล้ว

function KR.probeThai() return false end

function KR.L(th, en)
    return en or th
end

-- ตัดสตริงให้สั้นลงโดยไม่ตัดกลางตัวอักษร
--
-- string.sub() ตัดเป็น "ไบต์"  ตัวอักษรนอก ASCII หนึ่งตัวกินหลายไบต์
-- ตัดที่ 32 ไบต์เฉย ๆ จะได้ครึ่งตัวอักษรติดมา แล้วชื่อจะเพี้ยนถาวรในฐานข้อมูล
-- ยังต้องใช้แม้ UI เป็นอังกฤษ  เพราะชื่อที่แอดมินพิมพ์อาจมีอักขระอะไรก็ได้
function KR.trunc(s, maxChars)
    s = tostring(s or "")
    maxChars = maxChars or 64
    local i, n, out = 1, 0, 0
    while i <= #s and n < maxChars do
        local b = s:byte(i)
        local len = 1
        if b >= 0xF0 then len = 4 elseif b >= 0xE0 then len = 3 elseif b >= 0xC0 then len = 2 end
        i = i + len
        n = n + 1
        out = i - 1
    end
    return s:sub(1, out)
end


-- จำนวนรายการเดินบัญชีที่จอ Account ข้างร้านโชว์
-- ตั้งใจให้น้อย  ถ้าอยากดูเต็มต้องไปที่ธนาคาร
KR.ACCOUNT_TAIL = 8

KR.CUR = {
    CASH = "cash",
    HF   = "hf",
    CP   = "cp",
}

KR.CUR_META = {
    [KR.CUR.CASH] = { label = "CASH", sign = "$", owner = "Akacount"    },
    [KR.CUR.HF]   = { label = "HF",   sign = "HF",owner = "Kuraya"      },
    [KR.CUR.CP]   = { label = "CP",   sign = "CP",owner = "HF_Town_Rank"},
}

-- ------------------------------------------------------------------------------
-- แคตตาล็อก
--   รายการในร้านไม่ใช่ "สต็อก" แต่เป็น "สูตรเสก"
--   ผลที่ตามมาสองอย่าง
--     1. สภาพ (condition / ammo / uses) เป็นฟิลด์ของสูตร เสกออกมาได้ตามนั้นจริง
--     2. ร้านคือ item faucet ที่ไม่มีก้น  โควตาจึงต้องเป็นตัวเลขจริง ไม่ใช่เลขประดับ
-- ------------------------------------------------------------------------------
KR.KIND = {
    ITEM    = "item",
    VEHICLE = "vehicle",
    SERVICE = "service",     -- ไม่ใช่ไอเทม เป็นออร์เดอร์ที่คนต้องไปทำ ต้องมีคิวงาน
    PET     = "pet",         -- สัตว์  จ่ายเป็นใบเหมือนรถ แล้วแกะออกมาตรงหน้า (0.6.16)
}

-- ชนิดของรายการ อนุมานจากหมวด
--
-- เดิมมีปุ่ม "Kind" แยกต่างหาก ซึ่งเป็นปุ่มที่แอดมินต้องจำว่ามีอยู่และต้องกดให้ถูก
-- ในทางปฏิบัติหมวดกับชนิดแทบไม่เคยขัดกันเลย  ของในหมวด vehicle ก็คือรถ
-- เลยถอดปุ่มออกแล้วอนุมานจากหมวดแทน  เหลือช่องเดียวที่ต้องกรอก
--
-- แอดมินตั้งชื่อหมวดเองได้อิสระ  ชื่อที่ตรงกับคำสงวนพวกนี้เท่านั้นที่เปลี่ยนชนิด
--
-- "pet" เป็นชื่อที่เจ้าของเซิร์ฟสั่งมาตรง ๆ (0.6.16)  คำพ้องอีกสามคำใส่ไว้เพราะ
-- แอดมินคนอื่นจะพิมพ์คำที่ตัวเองคุ้น ไม่ใช่คำที่เราจดไว้ในหัว  หมวดที่พิมพ์ว่า
-- "animals" แล้วกลายเป็นของธรรมดาเงียบ ๆ คือกับดักที่ไม่มีอะไรบนจอบอกเลย
function KR.kindOfCat(cat)
    local c = tostring(cat or ""):lower()
    if c == "vehicle" or c == "vehicles" or c == "car" then return KR.KIND.VEHICLE end
    if c == "service" or c == "services" then return KR.KIND.SERVICE end
    if c == "pet" or c == "pets" or c == "animal" or c == "animals" then return KR.KIND.PET end
    return KR.KIND.ITEM
end

KR.RESTOCK = {
    NEVER  = "never",
    WEEKLY = "weekly",       -- เติมเองรายสัปดาห์แบบมีเพดาน  ค่าเริ่มต้นที่แนะนำ
    DAILY  = "daily",
}

-- ------------------------------------------------------------------------------
-- Fresh Market  ตลาดสดของแอดมิน
--   เห็นรายการได้ทุกที่  แต่ซื้อได้เฉพาะตอนยืนอยู่ที่ tile ที่ลงทะเบียนไว้
--   กฎเดียวกับธนาคาร: ตัวเลขดูได้ทุกที่ ของต้องไปเอาถึงที่
-- ------------------------------------------------------------------------------
KR.MARKET_RANGE = 2

KR.CMD = {
    REQ_SYNC        = "ReqSync",
    SYNC            = "Sync",
    ALERT           = "Alert",
    BUY             = "Buy",
    SET_CARD_SKIN   = "SetCardSkin",
    SEND_HF         = "SendHF",
    SAVE_BTN        = "SaveBtn",       -- เก็บตำแหน่งปุ่มลอยไว้บนเซิร์ฟเวอร์
    REQ_BTN         = "ReqBtn",
    SYNC_BTN        = "SyncBtn",
    ADMIN_MARKET    = "AdminMarket",   -- ลงทะเบียน tile เป็นแผงตลาดสด
    SALE_ANNOUNCE   = "SaleAnnounce",  -- ประกาศของลดราคาขึ้นหัวผู้เล่น
    ADMIN_SAVE      = "AdminSave",
    ADMIN_DEL       = "AdminDel",
    ADMIN_REG_TILE  = "AdminRegTile",
    ADMIN_MARKET_SET= "AdminMarketSet",  -- เปลี่ยนชื่อ / ถอดแผง จากหน้าจัดการ
    ADMIN_GRANT     = "AdminGrant",      -- แอดมินเติม/หักเงินให้ผู้เล่น
    OPEN_BILLS      = "OpenBills",       -- (เลิกใช้) ถูกแทนด้วย ACCOUNT_ACTION ที่ทั่วไปกว่า
    ACCOUNT_ACTION  = "AccountAction",   -- กดปุ่มที่ม็อดอื่นลงทะเบียนไว้ในจอ Account

    AUCT_BID        = "AuctBid",
    AUCT_SELL       = "AuctSell",
    AUCT_CANCEL     = "AuctCancel",
    AUCT_CLAIM      = "AuctClaim",

    CREDIT_BORROW   = "CreditBorrow",
    CREDIT_REPAY    = "CreditRepay",
    SET_PREF        = "SetPref",         -- จำหมวดที่ผู้เล่นดูอยู่ / ค่าตั้งส่วนตัวอื่น ๆ
    ADMIN_CATS      = "AdminCats",       -- เปลี่ยนชื่อ / เรียง / ลบหมวด
    ADMIN_UNLOCK    = "AdminUnlock",     -- แอดมินปลดล็อกร้านให้คนที่ติดลบหนัก
    AUCT_SLOT       = "AuctSlot",        -- ซื้อช่องประมูลถาวร
    AUCT_PAY        = "AuctPay",         -- ผู้ชนะจ่ายส่วนที่เหลือ

    -- แพ็ก HF Point  เงินจริงจ่ายนอกเกม แอดมินเป็นคนกดส่งให้
    HFP_REQ         = "HfpReq",          -- ผู้เล่นส่งคำขอซื้อแพ็ก
    HFP_CANCEL      = "HfpCancel",       -- ผู้เล่นถอนคำขอที่ยังไม่ถูกอนุมัติ
    HFP_SET         = "HfpSet",          -- แอดมินตั้งค่าแพ็กหนึ่งช่อง
    HFP_ACT         = "HfpAct",          -- แอดมินอนุมัติ / ปฏิเสธ คำขอ
    HFP_SEND        = "HfpSend",         -- แอดมินส่งให้เลยโดยไม่ต้องมีคำขอ

    TILL_TAKE       = "TillTake",        -- แอดมินถอนรายได้ร้านเข้าบัญชีตัวเอง
    BILL_SET        = "BillSet",         -- เปิด/ปิด หักบิลอัตโนมัติ
    BILL_OPEN       = "BillOpen",        -- เปิดหน้าต่างของม็อดบิล (ฝั่งจอล้วน)
    ACC_VIEW        = "AccView",         -- แอดมินเปิดดูบัญชีผู้เล่นรายคน
    FIND_PLAYER     = "FindPlayer",      -- ค้นชื่อผู้เล่นสำหรับช่อง dropdown

    CAR_LIST        = "CarList",         -- แอดมินขอรายชื่อรุ่นรถที่เกมนี้มีจริง
    CAR_UNPACK      = "CarUnpack",       -- ผู้เล่นแกะใบรถ

    PET_LIST        = "PetList",         -- แอดมินขอรายชื่อสัตว์ที่เกมนี้มีจริง
    PET_UNPACK      = "PetUnpack",       -- ผู้เล่นแกะใบสัตว์

    -- ผลวินิจฉัยจากเซิร์ฟ  ส่งไปให้แอดมินพิมพ์ลง console ของเครื่องเขาเอง (0.6.18)
    --
    -- เหตุผลไม่ใช่ความสะดวก แต่เพราะ **คนที่เจอปัญหากับคนที่อ่าน log ได้
    -- ต้องเป็นคนเดียวกัน** บรรทัดที่พิมพ์อยู่ฝั่งเซิร์ฟอย่างเดียว คือบรรทัดที่
    -- ไม่มีใครได้อ่านจนกว่าจะมีคนเดินไปเปิดเครื่องนั้น
    -- (เคยเสียเวลาทั้งรอบเพราะ log ที่ส่งมาเป็นของไคลเอนต์ ไม่ใช่ของเซิร์ฟ)
    DIAG            = "Diag",

    -- ------------------------------------------------------------------------
    -- 0.7.0  สถิติเศรษฐกิจ · กระดานราคาโลก · สกิล
    --
    -- ทุกตัวเป็นของแอดมินล้วน ตามที่เจ้าของเซิร์ฟสั่ง ("แอดมินเท่านั้นทั้งหมด")
    -- ยกเว้น BOARD_GET ที่ผู้เล่นเรียกได้ เพราะกระดานราคามีไว้ให้ทุกคนดู
    -- ------------------------------------------------------------------------
    STATS_GET       = "StatsGet",      -- แอดมินขอชุดตัวเลขเศรษฐกิจ (คิดตอนขอ ไม่ใช่ทุก sync)
    STATS           = "Stats",         -- เซิร์ฟตอบกลับ
    SKILLS_GET      = "SkillsGet",     -- แอดมินขอรายชื่อสกิลกับคนที่ถึงเกณฑ์
    SKILLS          = "Skills",        -- เซิร์ฟตอบกลับ
    BOARD_SET       = "BoardSet",      -- แอดมินเพิ่ม/แก้แถวในกระดานราคา
    BOARD_DEL       = "BoardDel",      -- แอดมินลบแถว
    BOARD_CATS      = "BoardCats",     -- แอดมินจัดหมวดของกระดาน
}

-- ------------------------------------------------------------------------------
-- ใบรถ
--
-- ใบชนิดเดียวใช้กับรถทุกรุ่น  รุ่นอยู่ใน ModData ของใบ ไม่ใช่ในชนิดของไอเทม
--
-- ทางเลือกอีกทางคือทำไอเทมหนึ่งชนิดต่อรถหนึ่งรุ่น แปลว่าต้องเขียน item script เพิ่ม
-- ทุกครั้งที่เซิร์ฟลงม็อดรถใหม่ และต้องรู้ล่วงหน้าว่าเซิร์ฟจะลงอะไรบ้าง
-- ซึ่งเรารู้ไม่ได้  การออกแบบที่ต้องรู้อนาคตคือการออกแบบที่พังตั้งแต่วันที่เขียน
-- ------------------------------------------------------------------------------
KR.SLIP = "Kuraya.CarSlip"

-- ชื่อ texture ของไอคอนใบรถ  เขียนไว้ที่เดียวเพราะมันไม่ได้เดาจากชื่อไอเทมได้
-- ไอเทมชื่อ Kuraya.CarSlip แต่ไฟล์ชื่อ Item_KR_CarSlip.png  (ตั้งใจใส่ KR_ นำหน้า
-- เพราะ texture ของ PZ ใช้ namespace ร่วมกันทั้งเกม  ชื่อ Item_CarSlip ชนกับม็อดอื่นได้)
KR.SLIP_ICON = "Item_KR_CarSlip"

-- ------------------------------------------------------------------------------
-- ใบสัตว์  (0.6.16)
--
-- เหตุผลที่สัตว์ต้องเป็นใบเหมือนรถ ไม่ใช่เหตุผลเดียวกัน และควรบันทึกไว้ให้ตรง
--   รถ  : ร้านอยู่ในอาคาร  รถที่เกิดในอาคารขยับไม่ออกตลอดไป
--   สัตว์: สัตว์ที่เกิดตอนคนซื้อยังยืนอยู่ในร้าน จะเดินตามใจตัวเองออกไปทันที
--         คนซื้อวัวแล้ววัวหายก่อนถึงบ้าน คือเรื่องที่เราไม่อยากต้องตัดสินว่าใครผิด
-- ทั้งสองข้อจบด้วยคำตอบเดียวกัน: ให้คนซื้อเลือกเองว่าจะแกะตรงไหน
--
-- ต่างจากรถอยู่ข้อเดียว **สัตว์แกะในร่มได้**  เล้าไก่กับคอกวัวอยู่ในร่มเป็นปกติ
-- บังคับให้ออกไปกลางแจ้งก่อนคือการบังคับให้ปล่อยสัตว์ไว้นอกคอก
-- ------------------------------------------------------------------------------
KR.PET_SLIP      = "Kuraya.PetSlip"
KR.PET_SLIP_ICON = "Item_KR_PetSlip"

-- รายการที่จ่ายเป็น "ใบ" มีสองชนิดแล้ว  ตารางนี้คือที่เดียวที่จับคู่ชนิดกับใบ
-- ทั้งฝั่งเซิร์ฟและฝั่งจออ่านตารางเดียวกัน  สองฝั่งจึงไม่มีทางเข้าใจไม่ตรงกัน
KR.SLIP_OF = {
    [KR.KIND.VEHICLE] = KR.SLIP,
    [KR.KIND.PET]     = KR.PET_SLIP,
}

KR.SLIP_ICON_OF = {
    [KR.KIND.VEHICLE] = KR.SLIP_ICON,
    [KR.KIND.PET]     = KR.PET_SLIP_ICON,
}

-- ชนิดนี้จ่ายเป็นใบไหม  เขียนเป็นฟังก์ชันเพราะที่เรียกใช้สนใจแค่คำตอบ ไม่ใช่ตาราง
function KR.isSlipKind(kind)
    return KR.SLIP_OF[tostring(kind or "")] ~= nil
end

-- ------------------------------------------------------------------------------
-- ชุดสินค้า  (0.6.12)
--
-- "ชุด" ไม่ใช่ชนิดของรายการ แต่เป็น **คุณสมบัติของข้อมูล**: รายการที่มี e.set
-- อย่างน้อยหนึ่งบรรทัดคือชุด  ไม่ผูกกับหมวด
--
-- ทำไมไม่ทำเป็นหมวด "set" แล้วอนุมานเหมือน vehicle/service:
-- ชุดอาวุธควรอยู่ในหมวดอาวุธ ชุดอาหารควรอยู่ในหมวดอาหาร  คนเลือกดูตามหมวด
-- ถ้าบังคับให้ทุกชุดไปกองอยู่ในหมวดเดียวชื่อ "set" คนจะหาของไม่เจอ
-- และแอดมินจะต้องเลือกระหว่าง "จัดหมวดให้ถูก" กับ "ทำเป็นชุดได้" ซึ่งไม่ควรต้องเลือก
--
-- ของในชุดหนึ่งบรรทัดหน้าตาแบบนี้
--   { item = "Base.Axe",          n = 1 }
--   { vehicle = "Base.CarNormal", n = 1 }    -- ใส่รถในชุดได้ ได้เป็นใบรถ
--   { pet = "cow",                n = 1 }    -- ใส่สัตว์ได้เหมือนกัน ได้เป็นใบสัตว์ (0.6.16)
-- ------------------------------------------------------------------------------
-- ห้าบรรทัด  **ไม่ใช่เลขที่เลือกเพราะสวย แต่คือจำนวนที่ฟอร์มรับไหวจริงที่ UI scale 1.5**
--
-- ตอนแรกตั้งไว้แปด แล้วด่านผัง (หลังถูกแก้ให้เปลี่ยน scale ได้จริง — ก่อนหน้านี้
-- มันรันที่ 1.0 สามรอบแล้วพิมพ์ว่า 1.0/1.25/1.5) ฟ้องว่าที่ scale 1.5
--   ปุ่ม New/Clear/Save ทับช่องราคา
--   ช่องราคาแถวสองตกขอบหน้าต่างออกไปเลย
-- ไล่ลดทีละขั้นพร้อมยุบแถว RARE/VISIBLE ขึ้นไปอยู่ข้างบน จนได้เลขที่ผ่านทุก scale
--
-- เลือกเลขที่พอดีกับที่ที่มีจริง ดีกว่าเลือกเลขสวย ๆ แล้วให้คนที่ตั้ง UI ใหญ่รับกรรมแทน
KR.SET_MAX = 5

function KR.isSet(e)
    return type(e) == "table" and type(e.set) == "table" and #e.set > 0
end

-- นับจำนวนชิ้นรวมในชุด  ใช้เขียนป้าย "5 ชิ้น" บนแถว
function KR.setCount(e)
    if not KR.isSet(e) then return 0 end
    local n = 0
    for _, ln in ipairs(e.set) do
        n = n + math.max(1, math.floor(tonumber(ln.n) or 1))
    end
    return n
end

-- ------------------------------------------------------------------------------
-- รูปกล่องของชุด
--
-- สิบสองแบบ: สี่หมวด × สามสี  ไฟล์อยู่ที่ media/textures/Kuraya/box/<id>.png
-- ตั้งได้เฉพาะรายการที่เป็นชุด (เจ้าของเซิร์ฟเลือกไว้แบบนั้น)
-- รายการทั่วไปใช้ไอคอนของไอเทมจริงอยู่แล้ว ซึ่งตรงกว่ารูปกล่องเสมอ
-- ------------------------------------------------------------------------------
KR.BOXES = {
    "weapon1", "weapon2", "weapon3",
    "food1",   "food2",   "food3",
    "special1","special2","special3",
    "magic1",  "magic2",  "magic3",
}

function KR.boxKnown(id)
    if type(id) ~= "string" or id == "" then return false end
    for _, b in ipairs(KR.BOXES) do
        if b == id then return true end
    end
    return false
end

function KR.boxTex(id)
    return "media/textures/Kuraya/box/" .. tostring(id) .. ".png"
end

-- ------------------------------------------------------------------------------
-- รูปสัตว์  (0.6.17)
--
-- เจ้าของเซิร์ฟส่งสไปรต์มาแล้วสั่งว่า "ใส่แทน icon แบบ auto ตามประเภท"
-- **auto แปลว่าแอดมินไม่ต้องเลือกรูป** ต่างจากรูปกล่องของชุดซึ่งเขาเลือกเอง
-- รายการสัตว์รู้อยู่แล้วว่าตัวเองเป็นสัตว์อะไร  การให้คนมากดเลือกรูปซ้ำอีกที
-- คือการขอให้เขาพิมพ์คำตอบที่ระบบมีอยู่แล้ว แล้วเปิดช่องให้เลือกผิดได้ด้วย
--
-- ชื่อไฟล์เป็น "ชนิด" หรือ "ชนิด_พันธุ์"  ตัวค้นไล่จากเจาะจงที่สุดลงมาหากว้างสุด
--   "cow:angus"  ->  cow_angus  ->  cow  ->  (ไอคอนใบสัตว์)
-- ตกลงมาถึงใบสัตว์ได้เสมอ **ช่องดำอ่านว่า "ของชิ้นนี้พัง" ซึ่งเป็นคำตอบที่ผิด**
--
-- รูปที่ไม่มีในลิสต์นี้ = ไม่มีไฟล์ ห้ามเดาชื่อไฟล์แล้วหวังว่า getTexture จะเจอ
-- เพราะ getTexture ที่หาไม่เจอคืน nil เงียบ ๆ แล้วเราจะได้ช่องดำโดยไม่รู้ตัว
KR.PET_ART = {
    "cow", "cow_angus", "cow_simmental", "cow_holstein",
    "pig", "sheep", "chicken", "turkey", "rabbit",
    "deer", "fawn", "raccoon", "mouse", "rat",
}

-- ==============================================================================
-- ชื่อชนิดจริงของ B42 -> ไฟล์รูปที่เรามี  (0.6.18)
--
-- "บางอันรูปไม่มา" — เจ้าของเซิร์ฟพูดถูก และนี่คือเหตุผล
--
-- **B42 แยกชนิดตามเพศและช่วงวัย ไม่ได้แยกตามสัตว์**
-- ดรอปดาวน์ในเกมของเขาขึ้นว่า: boar · buck · bull · chick · cockerel · cow
-- ไม่มีคำว่า chicken / pig / sheep / deer อยู่เลยสักคำ ซึ่งเป็นชื่อที่เราตั้งไฟล์ไว้
--
-- ไก่หนึ่งตัวจึงเป็นได้สามชนิด: chick (ลูก) · hen (ตัวเมีย) · cockerel (ตัวผู้)
-- และทั้งสามควรใช้รูปไก่รูปเดียวกัน เพราะเรามีรูปไก่รูปเดียว
--
-- ตารางนี้จึงไม่ใช่ "ทางลัด" แต่คือการแปลภาษาของเกมเป็นภาษาของโฟลเดอร์เรา
-- ชื่อที่ไม่มีจริงในเกมก็แค่ไม่เคยถูกค้นหา ไม่ได้ทำให้อะไรพัง
KR.PET_ART_ALIAS = {
    -- วัว  ตัวผู้ใช้รูปสีเข้ม ตัวเมียกับลูกใช้รูปมาตรฐาน
    bull = "cow_angus",  calf = "cow",   heifer = "cow",  steer = "cow_angus",
    -- หมู
    pig = "pig",  sow = "pig",  boar = "pig",  piglet = "pig",
    -- แกะ
    sheep = "sheep",  ewe = "sheep",  ram = "sheep",  lamb = "sheep",
    -- ไก่
    chicken = "chicken",  hen = "chicken",  cockerel = "chicken",
    rooster = "chicken",  chick = "chicken",
    -- ไก่งวง
    turkey = "turkey",  turkeyhen = "turkey",  tom = "turkey",  poult = "turkey",
    -- กวาง  ตัวผู้มีเขา ตัวเมียกับลูกใช้รูปลูกกวาง
    deer = "deer",  buck = "deer",  stag = "deer",  doe = "fawn",  fawn = "fawn",
    -- อื่น ๆ
    rabbit = "rabbit",  bunny = "rabbit",
    raccoon = "raccoon",  mouse = "mouse",  rat = "rat",
}

local PET_ART_SET = nil

-- ชื่อไฟล์ที่ตรงกับสัตว์ตัวนี้มากที่สุด  ไม่มีเลยคืน nil
function KR.petArt(petId)
    local s = tostring(petId or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end

    if PET_ART_SET == nil then
        PET_ART_SET = {}
        for _, n in ipairs(KR.PET_ART) do PET_ART_SET[n] = true end
    end

    local typ, breed = s:match("^([^:]+):(.+)$")
    if not typ then typ = s end

    -- ตัวคั่นของชื่อไฟล์คือ "_"  ชื่อพันธุ์ในเกมมีเว้นวรรคและขีดได้
    local function clean(v)
        return (tostring(v or ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
    end

    typ = clean(typ)

    -- เจาะจงที่สุดก่อน: ชนิด_พันธุ์  แล้วค่อยชนิดล้วน แล้วค่อยชื่อที่แปลแล้ว
    if breed then
        local b = clean(breed)
        local both = typ .. "_" .. b
        if PET_ART_SET[both] then return both end

        -- ไอดีเต็มของ B42 เขียนติดกัน ("henleghorn")  ชนิดอยู่ข้างหน้า
        -- ตัดชนิดออกแล้วลองอีกที เผื่อพันธุ์ถูกส่งมาเป็นไอดีเต็ม
        if b:sub(1, #typ) == typ then
            local tail = b:sub(#typ + 1)
            if tail ~= "" and PET_ART_SET[typ .. "_" .. tail] then
                return typ .. "_" .. tail
            end
        end

        local alias = KR.PET_ART_ALIAS[typ]
        if alias and PET_ART_SET[alias .. "_" .. b] then return alias .. "_" .. b end
    end

    if PET_ART_SET[typ] then return typ end

    -- ชื่อชนิดของเกมไม่ตรงกับชื่อไฟล์ของเรา  แปลก่อนแล้วลองใหม่
    local alias = KR.PET_ART_ALIAS[typ]
    if alias and PET_ART_SET[alias] then return alias end

    return nil
end

function KR.petTex(name)
    return "media/textures/Kuraya/pet/" .. tostring(name) .. ".png"
end

-- ==============================================================================
-- 0.7.0 — สถิติเศรษฐกิจ
-- ==============================================================================

-- "ยัง active" คือเห็นตัวใน 7 วันล่าสุด  อ่านจาก d.players[k].lastSeen ที่มีอยู่แล้ว
KR.ACTIVE_DAYS = 7

-- ยอดรวมรายวันเก็บกี่วัน  ตารางนี้เล็กมาก (วันละ 3 สกุล x 2 ตัวเลข)
-- 60 วันคือประมาณสองเดือนจริง ซึ่งยาวพอจะเห็นแนวโน้มและสั้นพอจะไม่บวมข้ามปี
KR.STATS_DAYS = 60

-- แคชผลคำนวณกี่วินาที
--
-- **ห้ามวนอ่านยอดเงินทุกคนใน S.sync()** sync วิ่งทุกสองวินาทีให้ทุกคนที่ออนไลน์
-- การวนเรียก Akacount ร้อยครั้งทุกสองวินาที = ฆ่าเซิร์ฟเพื่อเลขที่แอดมินเปิดดูนาน ๆ ครั้ง
-- คิดตอนแอดมินกดเปิดหน้า แล้วแคชไว้ พร้อมบอกเวลาที่คิด
KR.STATS_CACHE_SEC = 60

KR.TOP_N = 10

-- ==============================================================================
-- 0.7.0 — กระดานราคาสินค้าโลก
--
-- **ไม่ใช่แคตตาล็อกร้าน** มันคือกระดาษราคาอ้างอิงสำหรับคนที่ซื้อขายกันเอง
-- อยู่คนละตารางกับ d.catalog โดยตั้งใจ  ปนกันเมื่อไรจะมีวันที่ปุ่ม Buy
-- โผล่บนของที่ร้านไม่เคยมี แล้วผู้เล่นกดแล้วเจอ error ที่อธิบายไม่ได้
-- ==============================================================================
KR.BOARD_MAX      = 400      -- กันแพ็กเก็ต sync บวมจนหลุด
KR.BOARD_CAT_MAX  = 24
KR.BOARD_NAME_MAX = 48
KR.BOARD_NOTE_MAX = 64

-- ==============================================================================
-- 0.7.0 — สกิล
--
-- เจ้าของเซิร์ฟสั่ง "ไม่สนใจความแข็งแรง ฟิต วิ่ง ย่อง" = กลุ่ม Passiv กับ Agility
-- ที่เอาคือกลุ่มฝีมือ  เก็บเป็น **ชื่อกลุ่ม** ไม่ใช่รายชื่อสกิล
--
-- เหตุผลเดียวกับรายชื่อรุ่นรถใน 0.6.11: เซิร์ฟนี้ลงม็อดเพิ่มสกิลได้เสมอ
-- รายชื่อที่พิมพ์เองจะขาดของพวกนั้นเสมอ และจะผิดอีกครั้งทุกครั้งที่ B42 อัพเดต
-- กลุ่มอ่านจาก perk:getParent() ตอนรัน
-- ==============================================================================
KR.SKILL_GROUPS = { "Crafting", "Survivalist" }

KR.SKILL_GROUP_SET = {}
for _, g in ipairs(KR.SKILL_GROUPS) do
    KR.SKILL_GROUP_SET[tostring(g):lower()] = true
end

-- เกณฑ์เป็น sandbox ไม่ใช่เลข 8 ตายตัว
-- เขาขอ 8-10 วันนี้  พรุ่งนี้อยากดู 7 ขึ้นก็เปลี่ยนในหน้าตั้งค่า ไม่ต้องออกบิลด์ใหม่
-- **เลขที่ฝังไว้คือเลขที่ต้องขอรุ่นใหม่เพื่อเปลี่ยนมัน**
function KR.skillFrom()
    local v = KR.svInt("SkillWatchFrom", 8)
    if v < 1 then return 1 end
    if v > 10 then return 10 end
    return v
end

-- คีย์ของวัน  ใช้เป็นดัชนีของ d.stats.day
-- เก็บเป็นเลขวันตั้งแต่ epoch ไม่ใช่ "YYYYMMDD"
--
-- os.date ไม่มีในแซนด์บ็อกซ์ของ PZ (lint กฎ 5c) จะแปลงเป็นปฏิทินฝั่งเซิร์ฟไม่ได้เลย
-- เลขวันตอบทุกคำถามที่กราฟถาม ("ย้อนไป 7 วัน" = ลบ 7) โดยไม่ต้องรู้ปฏิทิน
-- และฝั่งจอเป็นคนแปลงเป็นวันที่ให้คนอ่านตอนวาด ซึ่งมันทำได้อยู่แล้ว
-- คั่นหลักพันด้วยลูกน้ำ  ตัวเลขเศรษฐกิจโตถึงเจ็ดหลักได้ง่าย ๆ
-- "1200000" กับ "1,200,000" อ่านต่างกันคนละเรื่องเวลากวาดตาผ่านตาราง
--
-- ทำเองเพราะ string.format("%d") ของ Kahlua ไม่มีตัวเลือกคั่นหลัก
-- และวนแทนที่ด้วย gsub ซ้ำ ๆ จนกว่าจะไม่เปลี่ยน คือวิธีที่ไม่ต้องใช้ pattern
-- ที่ Kahlua อาจไม่รองรับ
function KR.comma(n)
    local neg = false
    local v = math.floor(tonumber(n) or 0)
    if v < 0 then neg = true; v = -v end
    local s = tostring(v)
    local out = ""
    while #s > 3 do
        out = "," .. s:sub(#s - 2) .. out
        s = s:sub(1, #s - 3)
    end
    out = s .. out
    return neg and ("-" .. out) or out
end

function KR.dayOf(ts)
    return math.floor((tonumber(ts) or 0) / 86400)
end

-- ------------------------------------------------------------------------------
-- หมวดสินค้า
--
-- แอดมินตั้งชื่อเองได้อิสระ  ไม่มีรายการตายตัวในโค้ด
-- เซิร์ฟเก็บ "ลำดับ" ไว้ใน d.cats  ส่วนตัวหมวดเองมาจากของที่ลงไว้จริง
-- แปลว่าลบของชิ้นสุดท้ายในหมวดไหน หมวดนั้นก็หายไปเองโดยไม่ต้องมาไล่ลบ
-- ------------------------------------------------------------------------------
-- ==============================================================================
-- ระบบประมูลถูกพักไว้  (0.6.3)
--
-- เจ้าของเซิร์ฟสั่งว่า "ทำให้ระบบประมูลทั้งหมดเป็น coming soon"
--
-- ทำเป็นธงตัวเดียวที่คุมทั้งฝั่งจอและฝั่งเซิร์ฟ ไม่ใช่ไล่ลบโค้ดออก  เพราะ
--   1. โค้ดประมูลผ่านเทส 70 กว่าข้อมาแล้ว การลบทิ้งคือการทิ้งงานที่ยืนยันแล้ว
--   2. วันที่จะเปิดใช้จริงจะได้แค่พลิกธง ไม่ต้องเขียนใหม่แล้วมาไล่บั๊กชุดเดิมอีกรอบ
--   3. ที่สำคัญที่สุด: **ฝั่งเซิร์ฟต้องปฏิเสธด้วย** ไม่ใช่แค่จอไม่วาดปุ่ม
--      ไคลเอนต์ที่ถูกแก้ยิงคำสั่ง AuctSell มาได้ตลอดเวลา  การซ่อนปุ่มไม่ใช่การปิดระบบ
--
-- ล็อตที่ค้างอยู่ในฐานข้อมูลไม่ถูกแตะ  เงินมัดจำที่ค้างอยู่ก็ไม่ถูกแตะ
-- เปิดกลับมาเมื่อไหร่ทุกอย่างอยู่ที่เดิม
KR.AUCTION_ON = false

function KR.auctionOpen()
    return KR.svBool("AuctionEnabled", KR.AUCTION_ON == true)
end

-- ==============================================================================
-- สะพานไปหาหน้าตั้งค่าเซิร์ฟ (sandbox options)
--
-- 0.6.5 รื้อหน้าตั้งค่าใหม่ทั้งหน้า  จาก 28 ช่องกองรวมกันหน้าเดียว เหลือ 17 ช่อง
-- แยกสามหน้า  เจ้าของเซิร์ฟบอกตรง ๆ ว่า "ตั้งค่าเยอะไปมั้ย แอบงง"
--
-- หลักที่ใช้ตัด — ตัดออกถ้าเข้าข้อใดข้อหนึ่ง
--   1. แก้ในหน้าแอดมินในเกมได้อยู่แล้ว (เช่น วันเติมของ ตั้งรายชิ้นในฟอร์มสินค้า)
--   2. เป็นค่าปรับจูนที่คนตั้งเซิร์ฟไม่มีทางรู้ว่าควรใส่เท่าไร (น้ำหนักการเรียงราคา)
--   3. ถูกแทนที่ด้วยของใหม่ไปแล้ว (AuctionMAX_OPEN ถูกแทนด้วยระบบช่อง)
-- ของที่ตัดไม่ได้หายไปจากโค้ด  มันกลับไปใช้ค่าคงที่ในไฟล์นี้แทน
--
-- และหลักที่ใช้ "แปลงหน่วย"
--   ในโค้ดคิดเป็นหน่วยเล็กสุดเสมอ — สตางค์ กับ เบสิสพอยต์ — เพราะคูณหารแล้วไม่มีเศษหาย
--   แต่ไม่มีเจ้าของเซิร์ฟคนไหนอยากกรอกคำว่า "500 basis points" หรือ "500000 สตางค์"
--   หน้าตั้งค่าจึงถามเป็น เปอร์เซ็นต์ กับ บาท  แล้วคูณกลับตรงนี้ที่เดียว
--   ตารางในแต่ละ *Opt คือจุดเดียวที่สองหน่วยนี้เจอกัน  ไม่มีการคูณกระจายอยู่ที่อื่น
-- ==============================================================================
local function svTable()
    return (SandboxVars and SandboxVars.Kuraya) or nil
end

-- อ่านค่าตัวเลข  map[name] = { ชื่อในหน้าตั้งค่า, ตัวคูณกลับเป็นหน่วยของโค้ด }
-- ชื่อที่ไม่อยู่ใน map แปลว่า "ตัวนี้ไม่เปิดให้ตั้ง" และคืนค่าคงที่ไปตรง ๆ
function KR.svOpt(map, name, fallback)
    local m = map and map[name]
    if m then
        local sv = svTable()
        local v  = sv and tonumber(sv[m[1]])
        -- ปัดแบบ +0.5 เพราะฝั่งหน้าตั้งค่าเป็นทศนิยม  2.5% -> 250 ไม่ใช่ 249
        if v then return math.floor(v * (m[2] or 1) + 0.5) end
    end
    return fallback
end

-- อ่านค่าสวิตช์  ต้องเช็ค type ไม่ใช่ truthiness
-- false ที่เจ้าของเซิร์ฟตั้งเอง กับ nil ที่แปลว่า "ยังไม่เคยตั้ง" ต้องไม่ถูกมองเป็นอันเดียวกัน
function KR.svBool(name, fallback)
    local sv = svTable()
    if sv and type(sv[name]) == "boolean" then return sv[name] end
    return fallback
end

-- อ่านค่าที่เป็นข้อความ  (0.6.13 — ชื่อไอเทมที่แถมไปกับรถ)
--
-- ตัดช่องว่างหัวท้ายทิ้งเสมอ  หน้าตั้งค่าของเซิร์ฟเก็บสิ่งที่พิมพ์มาทั้งบรรทัด
-- " Base.CarKey " กับ "Base.CarKey" ต่างกันหนึ่งช่องว่างและอย่างแรกหาไม่เจอ
-- ซึ่งจะกลายเป็น "ตั้งถูกแล้วแต่ไม่ทำงาน" ที่หาสาเหตุยากที่สุดแบบหนึ่ง
function KR.svStr(name, fallback)
    local sv = svTable()
    local v  = sv and sv[name]
    if type(v) == "string" then
        v = v:gsub("^%s+", ""):gsub("%s+$", "")
        if v ~= "" then return v end
    end
    return fallback or ""
end

-- อ่านค่าที่เป็นจำนวนเต็มตรง ๆ  ไม่มีการคูณหน่วยเหมือน KR.svOpt
function KR.svInt(name, fallback)
    local sv = svTable()
    local v  = sv and tonumber(sv[name])
    if v then return math.floor(v) end
    return fallback
end

KR.CAT_ALL = "__all"
KR.CAT_MAX = 20          -- ความยาวชื่อหมวด

-- เลือกหมวดที่ควรกำลังดูอยู่ หลังได้ข้อมูลใหม่จากเซิร์ฟ
--
-- กติกาสามข้อ
--   1. ยังไม่เคยเลือก -> ใช้ค่าที่เซิร์ฟจำไว้
--   2. เลือกไว้แล้ว   -> ไคลเอนต์เป็นเจ้าของค่านี้ ห้าม sync ดีดกลับ
--      (sync วิ่งทุก 2 วิ ถ้าดีดกลับ ผู้เล่นจะกดเปลี่ยนหมวดไม่ติดเลย)
--   3. หมวดที่เลือกไม่มีของแล้ว -> เด้งกลับ All
--      ไม่งั้นผู้เล่นเห็นลิสต์ว่างโดยไม่รู้ว่าทำไม
--
-- แยกออกมาเป็นฟังก์ชันบริสุทธิ์เพราะตรรกะสามข้อนี้ผิดง่ายและต้องมีเทสคุม
function KR.pickCat(current, cats, pref)
    if current == nil then
        return (pref and pref.cat) or KR.CAT_ALL
    end
    if current == KR.CAT_ALL then return KR.CAT_ALL end
    for _, c in ipairs(cats or {}) do
        if c.id == current then return current end
    end
    return KR.CAT_ALL
end

function KR.catKey(s2)
    s2 = tostring(s2 or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s2 == "" then return "general" end
    return KR.trunc(s2, KR.CAT_MAX)
end

-- ------------------------------------------------------------------------------
-- ปุ่มที่ม็อดอื่นฝากไว้ในจอ Account
--
-- เพดานมีไว้เพื่อ UI ไม่ใช่เพื่อความปลอดภัย
-- แผงสูงประมาณ 700px  ถ้าปล่อยให้ลงทะเบียนไม่จำกัด ปุ่มล่างจะโดนดันตกจอ
-- แล้วผู้เล่นจะกดปุ่ม "ประวัติเต็ม" ไม่ได้โดยไม่มีอะไรบอกว่าทำไม
-- ------------------------------------------------------------------------------
KR.ACCOUNT_BTN_MAX = 6

-- ------------------------------------------------------------------------------
-- หน่วยของแต่ละสกุล  จุดที่พลาดง่ายที่สุดในทั้งม็อด
--   CASH -> Akacount เก็บเป็น integer "สตางค์"   250.75 บาท = 25075
--   HF   -> แต้มเต็ม
--   CP   -> Town Rank เก็บ PersonalRep เป็นแต้มเต็ม
--
-- ราคาในแคตตาล็อกกรอกเป็น "หน่วยที่คนอ่านเข้าใจ" เสมอ (บาท / แต้ม)
-- แล้วแปลงตอนจะหักจริงที่นี่ที่เดียว  ห้ามแปลงกระจายตามที่ต่าง ๆ
-- ------------------------------------------------------------------------------
KR.SUBUNIT = 100

function KR.toCharge(currency, price)
    price = tonumber(price) or 0
    if currency == KR.CUR.CASH then
        return math.floor(price * KR.SUBUNIT + 0.5)   -- บาท -> สตางค์
    end
    return math.floor(price)                          -- แต้มเต็ม
end

function KR.fmtPrice(currency, price)
    local m = KR.CUR_META[currency]
    local sign = m and m.sign or "?"
    if currency == KR.CUR.CASH then
        return string.format("%s %.2f", sign, tonumber(price) or 0)
    end
    return string.format("%s %d", sign, math.floor(tonumber(price) or 0))
end

-- ==============================================================================
-- ลดราคาจำกัดเวลา
--   saleBp     = ส่วนลดหน่วย basis point   4000 = ลด 40%
--   saleEndsAt = เวลาจริง (epoch วินาที) ที่ราคาเด้งกลับ  ไม่ใช่เวลาในเกม
--   saleQuota  = ซื้อได้คนละกี่ชิ้นต่อรอบ  nil = ไม่จำกัด
--
-- ราคาที่ "หัก" จริงต้องเรียก KR.effPrice ที่ฝั่งเซิร์ฟเวอร์เท่านั้น
-- ห้ามเชื่อราคาที่ไคลเอนต์ส่งมา  ไคลเอนต์คำนวณได้แค่เพื่อ "แสดง" กับ "เรียง"
-- ==============================================================================
function KR.saleActive(e, nowTs)
    if not e then return false end
    local bp = tonumber(e.saleBp) or 0
    if bp <= 0 or bp >= 10000 then return false end
    local ends = tonumber(e.saleEndsAt)
    if ends and nowTs and nowTs >= ends then return false end
    return true
end

function KR.discountBp(e, nowTs)
    if not KR.saleActive(e, nowTs) then return 0 end
    return math.floor(tonumber(e.saleBp) or 0)
end

-- ราคาหลังลด  ยังเป็น "หน่วยที่คนอ่านเข้าใจ" อยู่  ยังไม่แปลงเป็นสตางค์
function KR.applyDiscount(currency, price, bp)
    price = tonumber(price) or 0
    bp = math.floor(tonumber(bp) or 0)
    if bp <= 0 or bp >= 10000 then return price end
    if currency == KR.CUR.CASH then
        -- ปัดที่สตางค์ก่อนแล้วค่อยคืนเป็นบาท  กันเศษลอยหลุด
        return math.floor(price * KR.SUBUNIT * (10000 - bp) / 10000 + 0.5) / KR.SUBUNIT
    end
    return math.floor(price * (10000 - bp) / 10000 + 0.5)
end

function KR.effPrice(e, nowTs)
    return KR.applyDiscount(e and e.currency, e and e.price, KR.discountBp(e, nowTs))
end

-- ==============================================================================
-- ราคาหลายสกุล
--
-- ของหนึ่งชิ้นมี "ตัวเลือกการจ่าย" ได้หลายแบบ  ผู้เล่นเลือกเองว่าจะจ่ายแบบไหน
-- แต่ละตัวเลือกคือลิสต์ของ "ส่วนที่ต้องจ่าย"  ถ้ามีมากกว่าหนึ่งส่วนคือต้องจ่ายครบทุกส่วน
--
--   e.pay = {
--       { cur = "hf",   price = 420  },                       -- เขียนย่อได้ ถ้าสกุลเดียว
--       { cur = "cash", price = 4200 },
--       { { cur = "cp", price = 90 }, { cur = "cash", price = 500 } },   -- CP 90 บวกเงิน 500
--   }
--
-- ระหว่างตัวเลือกคือ "หรือ"  ภายในตัวเลือกเดียวกันคือ "และ"
-- ของเก่าที่มีแค่ e.currency กับ e.price ยังใช้ได้ ไม่ต้องไปแก้แคตตาล็อก
-- ==============================================================================
function KR.payOptions(e)
    if type(e) ~= "table" then return {} end
    local raw = e.pay

    -- รูปแบบเดิม  สกุลเดียวราคาเดียว
    if type(raw) ~= "table" or #raw == 0 then
        if e.currency then
            return { { { cur = e.currency, price = tonumber(e.price) or 0 } } }
        end
        return {}
    end

    local out = {}
    for i = 1, #raw do
        local o = raw[i]
        local parts = {}
        if type(o) == "table" then
            if o.cur then
                -- เขียนย่อ  ตัวเลือกที่มีส่วนเดียว
                parts[1] = { cur = o.cur, price = tonumber(o.price) or 0 }
            else
                for j = 1, #o do
                    local p = o[j]
                    if type(p) == "table" and p.cur then
                        parts[#parts + 1] = { cur = p.cur, price = tonumber(p.price) or 0 }
                    end
                end
            end
        end
        if #parts > 0 then out[#out + 1] = parts end
    end
    return out
end

function KR.isCombo(opt)
    return type(opt) == "table" and #opt > 1
end

-- ------------------------------------------------------------------------------
-- สีประจำสกุล  ใช้ทั้งตอนวาดราคาและตอนวาดเหรียญ
-- เก็บเป็น 0-1 เพราะ drawText ของ PZ รับแบบนั้น  ไม่ใช่ 0-255
-- ------------------------------------------------------------------------------
KR.CUR_COLOR = {
    [KR.CUR.CASH] = { r = 0.62, g = 0.88, b = 0.68 },   -- เขียว
    [KR.CUR.HF]   = { r = 0.76, g = 0.73, b = 0.91 },   -- ม่วง
    [KR.CUR.CP]   = { r = 0.90, g = 0.83, b = 0.66 },   -- ทอง
}

function KR.curColor(cur)
    return KR.CUR_COLOR[cur] or { r = 0.66, g = 0.65, b = 0.77 }
end

-- ------------------------------------------------------------------------------
-- บรรทัดราคาที่จะโชว์ในลิสต์
--
-- ของที่จ่ายได้หลายสกุลให้โชว์ครบทุกสกุล ไม่ใช่โชว์แค่อันที่ถูกที่สุด
-- แยกกันด้วยสีของแต่ละสกุล ตาจึงกวาดเจอสกุลที่ตัวเองมีได้ทันที
--
-- แต่พอผู้เล่นกรองสกุลใดสกุลหนึ่งแล้ว การโชว์ครบกลายเป็นเสียงรบกวน
-- เพราะเขาบอกไปแล้วว่าสนใจสกุลเดียว  ตอนนั้นจึงตัดที่เหลือออก
--
-- คืน { {cur=, price=, text=, combo=bool}, ... }  ไคลเอนต์เอาไปวาดเองตามสี
-- ------------------------------------------------------------------------------
function KR.priceLines(e, nowTs, filterCur)
    local opts = KR.payOptions(e)
    local out  = {}
    local bp   = KR.discountBp(e, nowTs)

    for i = 1, #opts do
        local opt   = opts[i]
        local combo = KR.isCombo(opt)

        if combo then
            -- ตัวเลือกแบบจ่ายผสมย่อเป็นบรรทัดเดียว  ใช้สีของส่วนแรกเป็นตัวแทน
            -- กรองสกุลแล้วต้องยังเห็นอยู่ ถ้าสกุลนั้นเป็นส่วนหนึ่งของการจ่ายผสม
            local keep = true
            if filterCur and filterCur ~= "" and filterCur ~= "all" then
                keep = false
                for j = 1, #opt do
                    if opt[j].cur == filterCur then keep = true; break end
                end
            end
            if keep then
                out[#out + 1] = {
                    cur   = opt[1].cur,
                    combo = true,
                    idx   = i,
                    text  = KR.fmtOption(opt, e, nowTs),
                }
            end
        else
            local p = opt[1]
            if not filterCur or filterCur == "" or filterCur == "all" or p.cur == filterCur then
                out[#out + 1] = {
                    cur   = p.cur,
                    combo = false,
                    idx   = i,
                    price = KR.applyDiscount(p.cur, p.price, bp),
                    text  = KR.fmtPrice(p.cur, KR.applyDiscount(p.cur, p.price, bp)),
                }
            end
        end
    end

    -- เรียงให้สกุลเดียวขึ้นก่อนแบบผสม แล้วค่อยเรียงตามราคาถูกไปแพง
    -- ผู้เล่นจะได้เห็นทางที่ง่ายที่สุดก่อนเสมอ
    table.sort(out, function(a, b)
        if a.combo ~= b.combo then return not a.combo end
        local x = KR.optionValue(opts[a.idx], e, nowTs)
        local y = KR.optionValue(opts[b.idx], e, nowTs)
        if x ~= y then return x < y end
        return a.idx < b.idx
    end)
    return out
end

-- ยอดที่ต้องหักจริงของตัวเลือกหนึ่ง  คืนเป็น [สกุล] = จำนวนหน่วยหักจริง (สตางค์ / แต้ม)
-- รวมส่วนที่เป็นสกุลเดียวกันเข้าด้วยกัน  ไม่งั้นเช็กยอดผ่านแต่หักไม่ครบ
function KR.optionCost(opt, e, nowTs)
    local bp = KR.discountBp(e, nowTs)
    local need = {}
    for i = 1, #(opt or {}) do
        local p = opt[i]
        local amt = KR.toCharge(p.cur, KR.applyDiscount(p.cur, p.price, bp))
        need[p.cur] = (need[p.cur] or 0) + amt
    end
    return need
end

-- ค่าถ่วงน้ำหนักของตัวเลือก  ใช้เทียบว่าตัวเลือกไหนถูกกว่ากัน และใช้เรียงราคา
function KR.optionValue(opt, e, nowTs)
    local bp = KR.discountBp(e, nowTs)
    local v = 0
    for i = 1, #(opt or {}) do
        local p = opt[i]
        v = v + KR.applyDiscount(p.cur, p.price, bp) * KR.sortWeight(p.cur)
    end
    return v
end

-- ตัวเลือกที่ถูกที่สุด  คือราคาที่เอาไปโชว์ในลิสต์และใช้เรียง
function KR.bestOption(e, nowTs)
    local opts = KR.payOptions(e)
    local bi, bv
    for i = 1, #opts do
        local v = KR.optionValue(opts[i], e, nowTs)
        if bv == nil or v < bv then bi, bv = i, v end
    end
    if not bi then return nil, 0, nil end
    return bi, bv, opts[bi]
end

-- bal เป็นหน่วยหักจริง (สตางค์ / แต้ม) เหมือนที่ optionCost คืนมา
function KR.canAfford(opt, e, bal, nowTs)
    local need = KR.optionCost(opt, e, nowTs)
    for cur, amt in pairs(need) do
        if (tonumber(bal and bal[cur]) or 0) < amt then return false, cur end
    end
    return true
end

-- ตัวกรองสกุล  ความหมายคือ "ซื้อด้วยสกุลนี้ได้ไหม" ไม่ใช่ "ราคาตั้งเป็นสกุลนี้"
function KR.acceptsCurrency(e, cur)
    if not cur or cur == "" or cur == "all" then return true end
    local opts = KR.payOptions(e)
    for i = 1, #opts do
        for j = 1, #opts[i] do
            if opts[i][j].cur == cur then return true end
        end
    end
    return false
end

function KR.currenciesOf(e)
    local seen, out = {}, {}
    local opts = KR.payOptions(e)
    for i = 1, #opts do
        for j = 1, #opts[i] do
            local c = opts[i][j].cur
            if not seen[c] then seen[c] = true; out[#out + 1] = c end
        end
    end
    return out
end

function KR.fmtOption(opt, e, nowTs)
    local bp = KR.discountBp(e, nowTs)
    local t = {}
    for i = 1, #(opt or {}) do
        local p = opt[i]
        t[#t + 1] = KR.fmtPrice(p.cur, KR.applyDiscount(p.cur, p.price, bp))
    end
    return table.concat(t, " + ")
end

-- ==============================================================================
-- โควตา  ซื้อได้คนละกี่ชิ้นต่อรอบ
--
--   e.quota       = จำนวนต่อผู้เล่นต่อรอบ   nil หรือ 0 = ไม่จำกัด
--   e.quotaPeriod = รอบนับยังไง
--
-- "รอบ" ไม่ใช่แค่ตัวเลข แต่เป็นคีย์  พอคีย์เปลี่ยนแปลว่าขึ้นรอบใหม่ ยอดที่ซื้อไปรีเซ็ตเอง
-- วิธีนี้ไม่ต้องมีงานเบื้องหลังคอยไล่ล้างตาราง และเซิร์ฟดับข้ามคืนก็ยังคิดถูก
-- ==============================================================================
KR.PERIOD = {
    SALE   = "sale",     -- ผูกกับรอบลดราคา  หมดโปรแล้วเริ่มนับใหม่  (ค่าเริ่มต้น)
    DAILY  = "daily",
    WEEKLY = "weekly",
    EVER   = "ever",     -- ตลอดกาล  ของจำกัดจำนวนจริง ๆ เช่นของยูนีค
}

KR.DAY_SEC  = 86400
KR.WEEK_SEC = 604800

-- ==============================================================================
-- โอนแต้ม HF ระหว่างผู้เล่น
--
-- HF เป็นแต้มที่เสกมาจากเควส ไม่ใช่เงินที่ลูทได้  พอโอนกันได้มันจะกลายเป็นตลาดทันที
-- สามอย่างข้างล่างเลยไม่ใช่ของประดับ แต่เป็นเบรกที่ต้องมีตั้งแต่วันแรก
--
--   ค่าธรรมเนียม  ทำให้การโอนวนไปวนมามีต้นทุน และเป็น sink ที่ดูดแต้มออกจากระบบ
--   เพดานต่อวัน   จำกัดความเสียหายตอนบัญชีใครโดนขโมย
--   บันทึกทุกครั้ง ไม่มีทางรู้ว่ามีการฟาร์มแต้มถ้าไม่เก็บ ตอนรู้ตัวจะสายไปแล้ว
--
-- ค่าเริ่มต้นตั้งไว้หลวม ๆ  ปรับเข้มได้ที่ sandbox โดยไม่ต้องแก้โค้ด
-- ==============================================================================
KR.HF_SEND = {
    MIN      = 10,      -- โอนน้อยกว่านี้ไม่ได้  กันสแปมโอนทีละแต้ม
    FEE_BP   = 500,     -- 5%  หักจากผู้ส่ง  ผู้รับได้เต็มจำนวนที่เห็นบนหน้าจอ
    DAILY    = 0,       -- เพดานต่อวันของผู้ส่ง  0 = ไม่จำกัด
    LOG_MAX  = 500,     -- เก็บประวัติกี่รายการ
}

-- MIN ไม่เปิดให้ตั้งแล้ว  ยอดโอนขั้นต่ำ 10 แต้มไม่ใช่เรื่องที่ใครอยากปรับ
-- FEE_BP หน้าตั้งค่าถามเป็นเปอร์เซ็นต์  5.0 -> 500 เบสิสพอยต์
local HF_SEND_SV = {
    FEE_BP = { "HFSendFeePercent", 100 },
    DAILY  = { "HFSendDailyLimit",   1 },
}

function KR.hfSendOpt(name)
    return KR.svOpt(HF_SEND_SV, name, KR.HF_SEND[name])
end

-- ค่าธรรมเนียมคิดจากยอดที่ผู้รับจะได้  ผู้ส่งจ่าย ยอด + ค่าธรรมเนียม
-- ทำแบบนี้เพราะคนกรอกตัวเลขคิดในหัวว่า "อยากให้เพื่อนได้เท่านี้" ไม่ใช่ "อยากเสียเท่านี้"
function KR.hfSendFee(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end
    local bp = KR.hfSendOpt("FEE_BP")
    if bp <= 0 then return 0 end
    return math.floor(amount * bp / 10000 + 0.5)
end

function KR.hfSendTotal(amount)
    amount = math.floor(tonumber(amount) or 0)
    return amount + KR.hfSendFee(amount)
end

function KR.quotaOf(e)
    local q = math.floor(tonumber(e and e.quota) or 0)
    if q <= 0 then return 0 end   -- 0 = ไม่จำกัด
    return q
end

-- คีย์ของรอบปัจจุบัน  ผู้เล่นสองคนอยู่รอบเดียวกันเสมอ ไม่ได้นับแยกตามเวลาที่แต่ละคนซื้อครั้งแรก
function KR.quotaPeriodKey(e, nowTs)
    nowTs = tonumber(nowTs) or 0
    local mode = (e and e.quotaPeriod) or KR.PERIOD.SALE

    if mode == KR.PERIOD.EVER then
        return "ever"

    elseif mode == KR.PERIOD.DAILY then
        return "d" .. math.floor(nowTs / KR.DAY_SEC)

    elseif mode == KR.PERIOD.WEEKLY then
        return "w" .. math.floor(nowTs / KR.WEEK_SEC)
    end

    -- SALE  ผูกกับเวลาสิ้นสุดโปร  ตั้งโปรรอบใหม่ = คีย์ใหม่ = โควตารีเซ็ต
    -- ของที่ไม่ได้ลดราคาแต่ตั้งโควตาไว้ ให้ตกไปนับรายวันแทน
    -- ไม่งั้นทุกคนจะติดเพดานถาวรตั้งแต่ซื้อครั้งแรกโดยไม่มีวันหลุด
    local ends = tonumber(e and e.saleEndsAt)
    if ends then return "s" .. math.floor(ends) end
    return "d" .. math.floor(nowTs / KR.DAY_SEC)
end

-- ==============================================================================
-- การเรียงลำดับในหน้าร้าน
-- ==============================================================================
KR.SORT = {
    NEW        = "new",          -- ลงล่าสุด  (ค่าเริ่มต้น)
    PRICE_DESC = "price_desc",   -- ราคา สูง -> ต่ำ
    PRICE_ASC  = "price_asc",    -- ราคา ต่ำ -> สูง
    NAME       = "name",         -- ชื่อ ก -> ฮ / A -> Z
    DISCOUNT   = "discount",     -- ส่วนลดมากสุด  (ใช้ในหน้า Sale)
}

-- ลำดับที่โผล่ในเมนู  แก้ที่นี่ที่เดียว UI จะตามเอง
KR.SORT_ORDER = {
    KR.SORT.NEW,
    KR.SORT.PRICE_DESC,
    KR.SORT.PRICE_ASC,
    KR.SORT.NAME,
    KR.SORT.DISCOUNT,
}

-- คู่ภาษา  อ่านผ่าน KR.sortLabel() เท่านั้น
KR.SORT_LABEL_PAIR = {
    [KR.SORT.NEW]        = { "ลงล่าสุด",            "Newest"          },
    [KR.SORT.PRICE_DESC] = { "ราคา สูง -> ต่ำ",      "Price high-low"  },
    [KR.SORT.PRICE_ASC]  = { "ราคา ต่ำ -> สูง",      "Price low-high"  },
    [KR.SORT.NAME]       = { "ชื่อ ก -> ฮ / A -> Z", "Name A-Z"        },
    [KR.SORT.DISCOUNT]   = { "ส่วนลดมากสุด",         "Biggest discount"},
}

function KR.sortLabel(mode)
    local p = KR.SORT_LABEL_PAIR[mode]
    if not p then return tostring(mode) end
    return KR.L(p[1], p[2])
end

-- เก็บชื่อเดิมไว้ให้เทสเก่าและโค้ดที่ยังเรียกอยู่ใช้ได้
KR.SORT_LABEL = setmetatable({}, { __index = function(_, k) return KR.sortLabel(k) end })

KR.SORT_DEFAULT = KR.SORT.NEW

-- ------------------------------------------------------------------------------
-- น้ำหนักสำหรับ "เรียงราคา" ข้ามสกุลเท่านั้น
--
-- นี่ไม่ใช่อัตราแลกเปลี่ยน  ห้ามเอาไปแปลงเงินจริงเด็ดขาด
-- มีไว้ตอบคำถามเดียวคือ "HF 8,500 กับ $ 22,400 อันไหนควรอยู่บนกว่ากัน"
-- ถ้าไม่ตั้ง ทุกสกุลน้ำหนัก 1  ผลคือเทียบตัวเลขดิบ ซึ่งจะเพี้ยนแน่นอน
-- ------------------------------------------------------------------------------
KR.SORT_WEIGHT = {
    [KR.CUR.CASH] = 1,
    [KR.CUR.HF]   = 10,
    [KR.CUR.CP]   = 25,
}

-- แอดมินปรับได้ที่ sandbox options  อ่านตอนเรียกใช้ ไม่แคชไว้ตอนโหลดไฟล์
-- (โหลดไฟล์เร็วกว่า SandboxVars จะพร้อม  แคชไว้ตอนนั้นจะได้ค่า default ค้างตลอดเกม)
-- 0.6.5 ถอดออกจากหน้าตั้งค่า
--
-- ค่านี้ไม่ใช่อัตราแลกเปลี่ยน มันเป็นแค่ "น้ำหนักตอนเรียงราคาข้ามสกุล"
-- ซึ่งไม่มีเจ้าของเซิร์ฟคนไหนตอบได้ว่าควรใส่เท่าไร และใส่ผิดก็ไม่มีอะไรพัง
-- แค่ลำดับในลิสต์ดูแปลก ๆ  ช่องตั้งค่าที่ตอบไม่ได้ว่าควรใส่อะไรคือช่องที่ควรหายไป
function KR.sortWeight(currency)
    return KR.SORT_WEIGHT[currency] or 1
end

-- ของที่จ่ายได้หลายสกุล ให้เรียงด้วยตัวเลือกที่ถูกที่สุด
-- คือตัวเลขเดียวกับที่โชว์ในลิสต์ ("จาก HF 420")  ลำดับที่เห็นจึงตรงกับราคาที่เห็น
function KR.sortValue(e, nowTs)
    local _, v = KR.bestOption(e, nowTs)
    return v or 0
end

-- ------------------------------------------------------------------------------
-- คีย์เรียงชื่อ
--   ภาษาไทยพังสองแบบถ้าเรียงตาม byte ตรง ๆ
--
--   1. สระหน้า เ แ โ ใ ไ เขียนก่อนพยัญชนะแต่ออกเสียงทีหลัง
--      "เกลือ" จะไปกองท้ายสุดแทนที่จะอยู่หมวด ก   -> สลับกับพยัญชนะถัดไปก่อนเรียง
--
--   2. วรรณยุกต์ ่ ้ ๊ ๋ ์ แทรกกลางคำและมีรหัสสูงกว่าสระทุกตัว
--      "ข้าวสาร" กับ "ไข่" จะสลับที่กัน เพราะไปเทียบ ้ กับ ไ แทนที่จะเทียบ า กับ ไ
--      -> ดึงวรรณยุกต์ออกจากคีย์หลัก ไปต่อท้ายเป็นคีย์รอง ใช้ตัดสินเฉพาะตอนคีย์หลักเท่ากัน
--
--   ตัวอักษรไทย ก-ฮ กับสระ เรียงตาม Unicode ตรงกับลำดับพจนานุกรมอยู่แล้ว ที่เหลือจึงพอดี
-- ------------------------------------------------------------------------------
local LEAD_VOWEL = {
    ["\224\185\128"] = true,  -- เ
    ["\224\185\129"] = true,  -- แ
    ["\224\185\130"] = true,  -- โ
    ["\224\185\131"] = true,  -- ใ
    ["\224\185\132"] = true,  -- ไ
}

-- วรรณยุกต์และเครื่องหมายกำกับที่ไม่นับในคีย์หลัก
local TONE_MARK = {
    ["\224\184\186"] = true,  -- ฺ  พินทุ
    ["\224\185\135"] = true,  -- ็  ไม้ไต่คู้
    ["\224\185\136"] = true,  -- ่
    ["\224\185\137"] = true,  -- ้
    ["\224\185\138"] = true,  -- ๊
    ["\224\185\139"] = true,  -- ๋
    ["\224\185\140"] = true,  -- ์  ทัณฑฆาต
    ["\224\185\141"] = true,  -- ํ  นิคหิต
    ["\224\185\142"] = true,  -- ๎  ยามักการ
}

local function utf8len(b)
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
end

function KR.nameKey(s)
    s = tostring(s or "")
    local main, sub, i, n = {}, {}, 1, #s
    while i <= n do
        local len = utf8len(s:byte(i))
        local ch  = s:sub(i, i + len - 1)

        if TONE_MARK[ch] then
            sub[#sub + 1] = ch                                    -- เก็บไว้ตัดสินทีหลัง
            i = i + len

        elseif LEAD_VOWEL[ch] and i + len <= n then
            local len2 = utf8len(s:byte(i + len))
            main[#main + 1] = s:sub(i + len, i + len + len2 - 1)  -- พยัญชนะขึ้นก่อน
            main[#main + 1] = ch                                  -- สระหน้าตามหลัง
            i = i + len + len2

        else
            main[#main + 1] = ch
            i = i + len
        end
    end
    -- \1 เป็นตัวคั่นที่เล็กกว่าอักขระที่ใช้ได้ทุกตัว  คีย์หลักจึงตัดสินก่อนเสมอ
    return string.lower(table.concat(main) .. "\1" .. table.concat(sub))
end

-- ------------------------------------------------------------------------------
-- KR.sortList  เรียง in-place แล้วคืน table เดิม
--
-- ทุก comparator ต้องตัดสินให้ขาดเสมอ  ถ้าคืน false ทั้งสองทางตอนค่าเท่ากัน
-- table.sort ของ Lua จะโยน "invalid order function for sorting" แบบสุ่ม
-- เลยปิดท้ายด้วย id ทุกอัน  id ไม่ซ้ำจึงตัดสินได้เสมอ
-- ------------------------------------------------------------------------------
local function byId(a, b)
    return tostring(a.id or "") < tostring(b.id or "")
end

function KR.sortList(rows, mode, nowTs)
    if type(rows) ~= "table" then return rows end
    mode = mode or KR.SORT_DEFAULT

    local cmp
    if mode == KR.SORT.PRICE_DESC then
        cmp = function(a, b)
            local x, y = KR.sortValue(a, nowTs), KR.sortValue(b, nowTs)
            if x ~= y then return x > y end
            return byId(a, b)
        end

    elseif mode == KR.SORT.PRICE_ASC then
        cmp = function(a, b)
            local x, y = KR.sortValue(a, nowTs), KR.sortValue(b, nowTs)
            if x ~= y then return x < y end
            return byId(a, b)
        end

    elseif mode == KR.SORT.NAME then
        cmp = function(a, b)
            local x, y = KR.nameKey(a.name), KR.nameKey(b.name)
            if x ~= y then return x < y end
            return byId(a, b)
        end

    elseif mode == KR.SORT.DISCOUNT then
        cmp = function(a, b)
            local x, y = KR.discountBp(a, nowTs), KR.discountBp(b, nowTs)
            if x ~= y then return x > y end
            return byId(a, b)
        end

    else -- KR.SORT.NEW
        cmp = function(a, b)
            local x = tonumber(a.listedAt) or 0
            local y = tonumber(b.listedAt) or 0
            if x ~= y then return x > y end
            return byId(a, b)
        end
    end

    table.sort(rows, cmp)
    return rows
end

-- ค้นหา  เทียบทั้งชื่อและหมวด  ตัดช่องว่างหัวท้ายและไม่สนตัวพิมพ์
function KR.matches(e, q)
    if not q or q == "" then return true end
    q = string.lower((tostring(q):gsub("^%s+", ""):gsub("%s+$", "")))
    if q == "" then return true end
    local hay = string.lower(tostring(e.name or "") .. " " .. tostring(e.cat or ""))
    return string.find(hay, q, 1, true) ~= nil
end


-- ==============================================================================
-- v0.2.4 — ป้ายไฟ / อารมณ์แมว / บัตรสะสม / ของเข้าใหม่ / ประมูล / เงินกู้
--
-- ทุกอย่างในบล็อกนี้เป็น "กติกาบริสุทธิ์" ไม่แตะ ModData ไม่แตะ UI
-- เขียนไว้ตรงนี้เพื่อให้ทั้งเซิร์ฟและไคลเอนต์คิดเลขออกมาตรงกันเป๊ะ
-- ถ้าฝั่งไหนคิดเองจะเกิดอาการ "จอบอกอย่าง เซิร์ฟทำอีกอย่าง" ซึ่งไล่บั๊กยากมาก
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- ป้ายไฟหน้าร้าน  (feed)
--
-- เก็บเหตุการณ์ล่าสุดไว้ไม่กี่รายการแล้ววนโชว์
-- จุดประสงค์คือทำให้เซิร์ฟที่มีคนออนไลน์ 2 คนรู้สึกว่ามีคนอยู่
-- ห้ามใส่ข้อมูลที่เป็นความลับลงไป  ทุกคนเห็นป้ายนี้เหมือนกันหมด
-- ------------------------------------------------------------------------------
KR.FEED_MAX  = 20        -- เก็บกี่รายการ
KR.FEED_SHOW = 8         -- ส่งให้ไคลเอนต์กี่รายการ
KR.FEED_SEC  = 6         -- เปลี่ยนข้อความทุกกี่วินาที

KR.FEED = {
    BUY    = "buy",      -- ใครซื้ออะไร
    SALE   = "sale",     -- โปรรอบใหม่เริ่ม
    STOCK  = "stock",    -- ของเข้าใหม่
    BID    = "bid",      -- ประมูล
    WIN    = "win",      -- ประมูลจบ
    STAMP  = "stamp",    -- ใครสะสมครบใบ
    TIER   = "tier",     -- ใครขึ้นระดับการใช้จ่าย
}

-- แปลงหนึ่งเหตุการณ์เป็นข้อความ  ทั้งสองฝั่งเรียกตัวนี้ตัวเดียวกัน
function KR.feedText(row, nowTs)
    if type(row) ~= "table" then return "" end
    local who  = tostring(row.who or "someone")
    local what = tostring(row.what or "something")
    local ago  = ""
    local dt   = (tonumber(nowTs) or 0) - (tonumber(row.t) or 0)
    if dt >= 60 then
        ago = "  (" .. math.floor(dt / 60) .. "m ago)"
    elseif dt >= 0 then
        ago = "  (just now)"
    end

    if row.k == KR.FEED.BUY   then return who .. " bought " .. what .. ago end
    if row.k == KR.FEED.SALE  then return "Flash sale started - " .. what .. " item(s) off" end
    if row.k == KR.FEED.STOCK then return "Delivery arrived - " .. what .. " new item(s) in stock" end
    if row.k == KR.FEED.BID   then return who .. " bid on " .. what .. ago end
    if row.k == KR.FEED.WIN   then return who .. " won " .. what .. ago end
    if row.k == KR.FEED.STAMP then return who .. " filled a loyalty card" end
    if row.k == KR.FEED.TIER  then return who .. " reached Spending Tier " .. what end
    return what
end

-- ------------------------------------------------------------------------------
-- อารมณ์แมว
--
-- แมวคือหน้าตาของร้าน  มันควรตอบสนองสิ่งที่เกิดขึ้นจริง ไม่ใช่รูปนิ่ง
-- ลำดับความสำคัญสำคัญมาก: เรื่องที่ "ผู้เล่นควรรู้เดี๋ยวนี้" ต้องชนะเสมอ
-- ------------------------------------------------------------------------------
KR.MOOD = {
    SLEEP = "sleep",     -- ร้านเงียบ ไม่มีอะไรพิเศษ
    COIN  = "coin",      -- มีของลดราคาอยู่
    WOW   = "wow",       -- มีของเข้าใหม่วันนี้
    FLAT  = "flat",      -- ผู้เล่นจ่ายไม่ไหวสักอย่างในหน้านี้
}

-- d = ข้อมูลที่เซิร์ฟส่งมา  ไคลเอนต์เรียกตอนวาด
function KR.mood(d)
    d = d or {}
    if (tonumber(d.saleCount) or 0) > 0 then return KR.MOOD.COIN end
    if (tonumber(d.newCount)  or 0) > 0 then return KR.MOOD.WOW  end
    if d.brokeHint == true               then return KR.MOOD.FLAT end
    return KR.MOOD.SLEEP
end

-- ------------------------------------------------------------------------------
-- ของหมด  ไม่ซ่อน แต่บอกว่าจะกลับมาเมื่อไร
--
-- ซ่อนของที่หมดทำให้ร้านดูเหมือนไม่เคยมีของนั้นเลย
-- โชว์เป็นสีเทาพร้อมเวลาเข้าใหม่ทำให้โลกรู้สึกว่ามีสายส่งของอยู่จริง
-- ------------------------------------------------------------------------------
function KR.isSoldOut(e)
    return e ~= nil and e.stock ~= nil and (tonumber(e.stock) or 0) <= 0
end

-- ของหมดแล้วกี่วันถึงเข้าใหม่  ใช้เมื่อรายการนั้นไม่ได้ตั้งค่าของตัวเองไว้
--
-- 0.3.1 มี option Kuraya.RestockDays อยู่ใน sandbox-options.txt แต่ไม่มีโค้ดไหนอ่านเลย
-- แอดมินหมุนเลขในหน้าตั้งค่าแล้วไม่มีอะไรเกิดขึ้น  ตรงนี้คือที่ที่มันควรถูกอ่าน
-- ค่าเริ่มต้นคง 2 ไว้เท่าเดิม เพราะเซิร์ฟที่รันอยู่แล้วต้องไม่รู้สึกว่าอะไรเปลี่ยน
KR.RESTOCK_DAYS = 2

-- 0.6.5 ถอดออกจากหน้าตั้งค่า
--
-- ฟอร์มสินค้าในหน้าแอดมินตั้งวันเติมของรายชิ้นได้อยู่แล้ว (กล่อง STOCK)
-- ค่านี้เป็นแค่ค่าตั้งต้นของชิ้นที่ยังไม่ได้ตั้ง  มีสองที่ที่ตั้งเรื่องเดียวกัน
-- คือมีสองที่ที่ต้องไปหาเวลาของไม่กลับมา  เหลือที่เดียวที่แอดมินเห็นอยู่ตรงหน้าดีกว่า
function KR.restockDays(entry)
    local own = tonumber(entry and entry.restockDays)
    if own then return math.max(1, math.floor(own)) end
    return KR.RESTOCK_DAYS
end

-- คืนวินาทีที่เหลือจนกว่าจะเติมของ  nil = ไม่มีกำหนด
function KR.restockIn(e, nowTs)
    if e == nil or e.restockAt == nil then return nil end
    local left = (tonumber(e.restockAt) or 0) - (tonumber(nowTs) or 0)
    if left <= 0 then return 0 end
    return left
end

function KR.fmtDur(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    if sec >= 86400 then
        local dd = math.floor(sec / 86400)
        return dd .. (dd == 1 and " day" or " days")
    end
    if sec >= 3600 then return math.floor(sec / 3600) .. " h" end
    if sec >= 60   then return math.floor(sec / 60)   .. " m" end
    return sec .. " s"
end

-- ------------------------------------------------------------------------------
-- ของเข้าใหม่รายวัน
--
-- ทุกวันในเกม ของกลุ่มหนึ่งจะถูกทำเครื่องหมายว่า "ใหม่" และเติมสต็อก
-- ให้เหตุผลผู้เล่นเปิดร้านทุกเช้า โดยไม่ต้องให้แอดมินมานั่งกดเอง
--
-- ตัวเลือกรายการใช้วิธี deterministic จากเลขวัน ไม่ใช่ random
-- เพราะ random ทำให้เซิร์ฟกับไคลเอนต์เห็นคนละชุด และ resume ไม่ได้
-- ------------------------------------------------------------------------------
KR.ROTATE_COUNT = 4      -- กี่ชิ้นต่อวัน
KR.NEW_SEC      = 86400  -- ป้าย NEW อยู่นานแค่ไหน

function KR.dayOf(nowTs)
    return math.floor((tonumber(nowTs) or 0) / KR.DAY_SEC)
end

function KR.isNew(e, nowTs)
    if e == nil or e.newAt == nil then return false end
    return ((tonumber(nowTs) or 0) - (tonumber(e.newAt) or 0)) < KR.NEW_SEC
end

-- เลือกรายการของวันนั้น  วันเดียวกัน = ได้ชุดเดิมเสมอ
-- ids ต้องถูกเรียงมาแล้ว ไม่งั้นลำดับจาก pairs() จะทำให้ผลไม่คงที่
function KR.pickRotation(ids, day, count)
    local out = {}
    local n = #ids
    if n == 0 then return out end
    count = math.min(count or KR.ROTATE_COUNT, n)
    -- เดินแบบ step คงที่ที่ไม่หารลงตัวกับ n จะได้ไม่วนซ้ำที่เดิม
    local step = 7
    local i = (day * 3) % n
    local seen = {}
    while #out < count do
        local k = (i % n) + 1
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = ids[k]
        end
        i = i + step
        if #seen >= n then break end
    end
    return out
end

-- ------------------------------------------------------------------------------
-- บัตรสะสมแต้ม
--
-- ซื้อครบ N ครั้ง = ปั๊มหนึ่งดวง  ครบ M ดวง = ได้รางวัลแล้วบัตรรีเซ็ต
-- นับเป็น "ครั้ง" ไม่ใช่ "จำนวนเงิน" ตั้งใจแบบนั้น
-- ถ้านับเป็นเงิน คนรวยจะได้รางวัลรัว ๆ ส่วนคนใหม่ไม่มีวันได้เลย
-- ------------------------------------------------------------------------------
KR.STAMP = {
    PER_STAMP = 3,      -- ซื้อกี่ครั้งได้หนึ่งดวง
    PER_CARD  = 10,     -- กี่ดวงเต็มหนึ่งใบ
    REWARD_HF = 200,    -- เต็มใบแล้วได้กี่แต้ม
}

-- PER_STAMP (ซื้อกี่ครั้งได้หนึ่งดวง) ไม่เปิดให้ตั้งแล้ว
-- สองช่องที่คูณกันเพื่อตอบคำถามเดียว ("ซื้อกี่ครั้งได้รางวัล") คือช่องที่ทำให้คนงง
-- เหลือช่องที่ตอบคำถามตรง ๆ: เต็มใบใช้กี่ดวง และเต็มใบแล้วได้เท่าไร
local STAMP_SV = {
    PER_CARD  = { "StampsPerCard", 1 },
    REWARD_HF = { "StampReward",   1 },
}

function KR.stampOpt(name)
    return KR.svOpt(STAMP_SV, name, KR.STAMP[name])
end

-- p = players[key]  คืนสถานะบัตรที่พร้อมวาด
function KR.stampState(p)
    p = p or {}
    local perStamp = math.max(1, KR.stampOpt("PER_STAMP"))
    local perCard  = math.max(1, KR.stampOpt("PER_CARD"))
    local buys     = math.max(0, math.floor(tonumber(p.buys) or 0))
    local stamps   = math.floor(buys / perStamp) % perCard
    local toNext   = perStamp - (buys % perStamp)
    return {
        stamps  = stamps,
        of      = perCard,
        cards   = math.floor(tonumber(p.cards) or 0),
        toNext  = toNext,
        perStamp= perStamp,
    }
end

-- ==============================================================================
-- ระดับการใช้จ่าย  (Spending Tier)
--
-- มาแทนบัตรสะสมแต้มบนหน้าจอ  ตัวบัตรสะสมยังทำงานอยู่ข้างหลังไม่ได้ถอดออก
-- เพราะมันนับ "จำนวนครั้ง" ซึ่งเป็นคนละเรื่องกับ tier ที่นับ "จำนวนเงิน"
--
-- ยอดสะสมตลอดกาล ไม่มีวันลด  ตัดสินใจแบบนี้เพราะ:
--   ผู้เล่นที่ทำ tier ได้แล้วต้องไม่ตื่นมาเจอว่าตัวเองตกชั้นเพราะสัปดาห์นี้ไม่ได้เล่น
--   เซิร์ฟนี้คนเข้า ๆ ออก ๆ  ระบบที่ลงโทษการหายไปสองอาทิตย์จะไล่คนออกเงียบ ๆ
--
-- ยอดถูกแปลงเป็น "หน่วยย่อยของเงินสด" ด้วยน้ำหนักชุดเดียวกับที่ใช้เรียงราคา
-- ย้ำอีกครั้ง: **น้ำหนักไม่ใช่อัตราแลกเปลี่ยน** ใช้ตอบได้แค่ว่าอันไหนใหญ่กว่ากัน
-- ที่ยอมใช้ตรงนี้เพราะ tier เป็นเรื่องของ "ซื้อเยอะแค่ไหน" ไม่ใช่การเคลื่อนย้ายเงินจริง
-- ==============================================================================
KR.TIER = {
    STEP = 200000,      -- หน่วยย่อย  200000 = 2,000.00
    MAX  = 5,
}

-- เคยอ่าน sv["Tier"..name] ซึ่งไม่เคยมี option ชื่อนั้นอยู่ในไฟล์ sandbox เลยสักรุ่น
-- = โค้ดที่อ่านของที่ไม่มีวันมี  ตัดทิ้งตอนรื้อหน้าตั้งค่า 0.6.5
function KR.tierOpt(name)
    return KR.TIER[name]
end

-- แปลงตารางค่าใช้จ่ายหลายสกุลเป็นตัวเลขเดียว (หน่วยย่อยของเงินสด)
-- need = { cash = 42000, hf = 900 }  แบบเดียวกับที่ KR.optionCost คืนมา
function KR.spendValue(need)
    local v = 0
    for cur, amt in pairs(need or {}) do
        v = v + (tonumber(amt) or 0) * KR.sortWeight(cur)
    end
    return math.floor(v)
end

-- p = players[key]  คืนสถานะ tier ที่พร้อมวาด
function KR.tierState(p)
    local step  = math.max(1, math.floor(KR.tierOpt("STEP")))
    local maxT  = math.max(1, math.floor(KR.tierOpt("MAX")))
    local spent = math.max(0, math.floor(tonumber((p or {}).spent) or 0))

    -- ใช้จ่ายครบหนึ่ง step = ขึ้นหนึ่ง tier  เริ่มที่ Tier 1 ตั้งแต่ยังไม่ซื้ออะไร
    local tier = math.min(maxT, 1 + math.floor(spent / step))
    local maxed = (tier >= maxT)
    local into  = maxed and step or (spent % step)
    local need  = maxed and 0 or (step - into)
    return {
        tier = tier, max = maxT, step = step, spent = spent,
        into = into, need = need, maxed = maxed,
        pct  = maxed and 1 or (into / step),
    }
end

-- ==============================================================================
-- ประวัติการใช้จ่าย
--
-- **เฉพาะการใช้จ่ายในระบบร้าน** ฝาก/ถอน/โอนของธนาคารไม่อยู่ในนี้
-- ตั้งใจแบบนั้น: ธนาคารมีสมุดบัญชีของตัวเองอยู่แล้วที่เคาน์เตอร์
-- เอามาปนกันแล้วรายการ "ถอนเงิน 2,000" จะกลบรายการ "ซื้อยา 420" ที่คนอยากดูจริง ๆ
--
-- เก็บเป็น ring buffer ต่อผู้เล่น  ไม่ใช่ก้อนกลาง
-- เพราะทุก sync ส่งเฉพาะของคนนั้น การเก็บรวมแล้วมากรองทีหลังคือส่งข้อมูลคนอื่นไปเปล่า ๆ
-- ==============================================================================
KR.LOG_MAX = 60          -- เก็บย้อนหลังกี่รายการต่อคน

KR.LOG = {
    BUY    = "buy",      -- ซื้อของในร้าน
    ORDER  = "order",    -- สั่งบริการ
    AUCT   = "auct",     -- ประมูล (จ่ายออก)
    SALE   = "sale",     -- ขายของ / ประมูลได้เงิน (รับเข้า)
    BILL   = "bill",     -- บิลจากม็อดอื่น
    LOAN   = "loan",     -- เงินกู้ / ผ่อนคืน
    REWARD = "reward",   -- รางวัลจากระบบ
    XFER   = "xfer",     -- โอนแต้มระหว่างผู้เล่น (ส่งออก / รับเข้า)
}

KR.LOG_LABEL = {
    buy = "Buy", order = "Order", auct = "Auction", sale = "Sale",
    bill = "Bill", loan = "Loan", reward = "Reward", xfer = "Transfer",
}

-- ชิปกรองบนหัวตาราง  "ทั้งหมด" ไม่ได้อยู่ในนี้ ไคลเอนต์เติมเอง
-- ชิปกรองต้องมีเฉพาะชนิดที่ **มีโค้ดเขียนลงมาจริง**
--
-- ถึง 0.4.2 มีแต่ S.buy ที่เรียก S.logSpend  ชิป Auction / Loan / Bill จึงว่างเปล่า
-- ตลอดกาลโดยไม่มีอะไรบอก  ผู้เล่นกดแล้วเจอตารางเปล่า แล้วสรุปว่า "ประวัติไม่อัปเดต"
-- ซึ่งเขาสรุปถูก
--
-- ชิปที่กดแล้วว่างเสมอแย่กว่าไม่มีชิปนั้นเลย เพราะมันสัญญาว่ามีข้อมูลอยู่
KR.LOG_FILTERS = {
    { id = "buy",  label = "Buy",      kinds = { buy = true, order = true } },
    { id = "auct", label = "Auction",  kinds = { auct = true, sale = true } },
    { id = "xfer", label = "Transfer", kinds = { xfer = true } },
    { id = "loan", label = "Loan",     kinds = { loan = true } },
    { id = "bill", label = "Bill",     kinds = { bill = true, reward = true } },
}

function KR.logPass(row, filterId)
    if filterId == nil or filterId == "all" then return true end
    for _, f in ipairs(KR.LOG_FILTERS) do
        if f.id == filterId then return f.kinds[row.k] == true end
    end
    return true
end

-- ยอดใช้จ่ายในกี่วันล่าสุด  นับเฉพาะขาจ่ายออก
KR.SPEND_WINDOW_DAYS = 7

function KR.spendWindow(log, nowTs, days)
    days = days or KR.SPEND_WINDOW_DAYS
    local from = (tonumber(nowTs) or 0) - days * KR.DAY_SEC
    local total, n = 0, 0
    for _, r in ipairs(log or {}) do
        if not r.inc and (tonumber(r.t) or 0) >= from then
            total = total + (tonumber(r.v) or 0)
            n = n + 1
        end
    end
    return total, n
end

-- ==============================================================================
-- สถานะการ์ดที่ม็อดอื่นฝากไว้ในหน้า Account  (เช่น บิลค่าบ้าน)
--
-- ม็อดเจ้าของบิลเป็นคนบอกสถานะมา  Kuraya แค่วาดตามและส่งการกดกลับไป
-- Kuraya ไม่รู้จักกติกาบ้าน ไม่รู้ว่าใครเป็นหัวบ้าน และไม่ควรรู้ด้วย
-- ==============================================================================
-- ------------------------------------------------------------------------------
-- id ของการ์ดบิลค่าบ้าน  เป็น "สัญญา" ระหว่าง Kuraya กับม็อดบิลที่ยังไม่ได้เขียน
--
-- Kuraya วาดการ์ดเปล่าที่เขียนว่า Coming soon ไว้ตราบใดที่ยังไม่มีใครลงทะเบียน id นี้
-- ม็อดบิลเรียกแบบนี้ตอนโหลด (ฝั่งเซิร์ฟ) แล้วการ์ดเปล่าจะหายไปเอง:
--
--   if Kuraya and Kuraya.registerAccountCard then
--       Kuraya.registerAccountCard("hf_house_bills", {
--           title = "House bills",
--           order = 20,
--           state = function(player)
--               return { status = "due", statusText = "DUE IN 2 DAYS",
--                        head = "Rosewood Lot 14", amount = 70000, cur = "cash",
--                        note = "Rent for this week",
--                        actions = { { id = "pay", label = "Pay now" } } }
--           end,
--           onAction = function(player, actionId) ... end,
--       })
--   end
--
-- ตั้งเป็นค่าคงที่ ไม่ใช่สตริงลอยในโค้ด  เพราะพิมพ์ผิดที่เดียวจะได้การ์ดสองใบ
-- โดยไม่มี error อะไรขึ้นเลย ซึ่งเป็นความผิดพลาดที่หายากที่สุดชนิดหนึ่ง
KR.BILLS_CARD_ID    = "hf_house_bills"
KR.BILLS_CARD_ORDER = 20

KR.CARD_STATUS = {
    NONE = "none",   -- ไม่มีอะไรต้องจ่าย
    DUE  = "due",    -- ถึงกำหนดแล้ว ยังไม่เลย
    LATE = "late",   -- เลยกำหนด
    PAID = "paid",   -- จ่ายแล้ว
    SENT = "sent",   -- ลูกบ้านกดเตือนหัวบ้านไปแล้ว
}
KR.ACCOUNT_CARD_MAX = 3    -- การ์ดใหญ่เกินสามใบแล้วคอลัมน์ล้น

-- ------------------------------------------------------------------------------
-- ประมูล
--
-- เงินของผู้ประมูลถูก "พัก" ไว้ (escrow ของ Akacount) ไม่ใช่หักทิ้ง
-- แพ้เมื่อไรคืนทันที  ชนะถึงค่อยตัดจริง
-- นั่นแปลว่าเงินไม่เคยหายไปอยู่ในสุญญากาศ และ invariant ของ ledger ยังเป็น 0
--
-- ขั้นต่ำการขึ้นราคาเป็น % ไม่ใช่ค่าคงที่  ไม่งั้นของแพงจะโดนขึ้นทีละบาท
-- ------------------------------------------------------------------------------
KR.AUCTION = {
    MIN_HOURS   = 1,        -- ตั้งได้สั้นสุดกี่ชั่วโมง
    MAX_HOURS   = 72,
    RAISE_BP    = 500,      -- ขึ้นขั้นต่ำ 5% ของราคาปัจจุบัน
    RAISE_MIN   = 100,      -- แต่ไม่น้อยกว่านี้ (หน่วยย่อย)
    ANTISNIPE   = 120,      -- ประมูลใน 2 นาทีสุดท้าย = ต่อเวลาอีก 2 นาที
    MAX_OPEN    = 3,        -- คนหนึ่งเปิดขายพร้อมกันได้กี่ชิ้น
    FEE_BP      = 300,      -- ค่าธรรมเนียมหักจากคนขายตอนขายได้
}

-- เหลือช่องเดียว: ค่าธรรมเนียมคนขาย  ถามเป็นเปอร์เซ็นต์  3.0 -> 300 เบสิสพอยต์
-- RAISE_BP / ANTISNIPE / MAX_OPEN กลับไปใช้ค่าคงที่
-- MAX_OPEN ตายไปตั้งแต่ 0.5 แล้วด้วยซ้ำ — ระบบช่องประมูลมาแทนที่ แต่ช่องตั้งค่ายังค้างอยู่
local AUCT_SV = {
    FEE_BP = { "AuctionFeePercent", 100 },
}

function KR.auctOpt(name)
    return KR.svOpt(AUCT_SV, name, KR.AUCTION[name])
end

-- ราคาต่ำสุดที่ยอมรับสำหรับการประมูลครั้งถัดไป
function KR.nextBid(lot)
    lot = lot or {}
    local cur = math.floor(tonumber(lot.bid) or tonumber(lot.start) or 0)
    if (tonumber(lot.bids) or 0) <= 0 then
        return cur                      -- ยังไม่มีใครประมูล  จ่ายราคาเริ่มต้นได้เลย
    end
    local step = math.floor(cur * KR.auctOpt("RAISE_BP") / 10000)
    if step < KR.auctOpt("RAISE_MIN") then step = KR.auctOpt("RAISE_MIN") end
    return cur + step
end

function KR.auctionLeft(lot, nowTs)
    return math.max(0, (tonumber(lot and lot.endsAt) or 0) - (tonumber(nowTs) or 0))
end

function KR.auctionClosed(lot, nowTs)
    if lot == nil then return true end
    if lot.done then return true end
    return KR.auctionLeft(lot, nowTs) <= 0
end

-- ค่าธรรมเนียมที่คนขายโดนหัก
function KR.auctionFee(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    return math.floor(amount * KR.auctOpt("FEE_BP") / 10000)
end

-- ------------------------------------------------------------------------------
-- เงินกู้
--
-- วงเงินมาจากยศ CP  ยศสูง = เชื่อใจได้มากกว่า
-- ผ่อนเป็นงวดเท่า ๆ กัน  ดอกเบี้ยคิดแบบ flat ครั้งเดียวตอนกู้ ไม่ทบต้น
-- เลือก flat เพราะผู้เล่นต้องคำนวณในหัวได้ว่า "กู้ห้าพันคืนห้าพันสาม"
-- ดอกเบี้ยทบต้นถูกกว่าในทางคณิตศาสตร์ แต่ไม่มีใครเข้าใจมันในเกม
-- ------------------------------------------------------------------------------
KR.CREDIT = {
    TIERS = {
        -- ต้องเรียงจาก CP น้อยไปมาก
        { cp = 0,   name = "BRONZE", limit = 1000000  },   -- 10,000.00
        { cp = 50,  name = "SILVER", limit = 2500000  },   -- 25,000.00
        { cp = 150, name = "GOLD",   limit = 5000000  },   -- 50,000.00
        { cp = 400, name = "BLACK",  limit = 12000000 },   -- 120,000.00
    },
    RATE_BP     = 600,      -- ดอกเบี้ย flat 6%
    LATE_BP     = 200,      -- ค่าปรับต่อวันที่เลย
    TERMS       = { 5, 10, 20 },   -- ผ่อนกี่งวด
    MISS_FREEZE = 3,        -- ผิดนัดกี่งวดแล้วโดนล็อกบัญชี
    MIN_LOAN    = 50000,    -- 500.00
    -- เพดานรวมของทั้งเซิร์ฟ  0 = ไม่จำกัดเพิ่ม ใช้เพดานตามยศอย่างเดียว
    -- ตั้งได้ที่ sandbox: Kuraya.LoanMaxCredit (หน่วยบาท)
    MAX_CREDIT  = 0,
}

-- MIN_LOAN ไม่เปิดให้ตั้งแล้ว  ยอดกู้ขั้นต่ำ 500 บาทไม่ใช่คันโยกของเศรษฐกิจ
-- ระวัง: KR.CREDIT.TIERS เป็นตาราง  ทางที่ไม่มีใน map ต้องคืนของเดิมไปทั้งก้อน
local CREDIT_SV = {
    RATE_BP     = { "LoanInterestPercent",     100 },
    LATE_BP     = { "LoanLateFeePercent",      100 },
    MISS_FREEZE = { "LoanMissedBeforeFreeze",    1 },
    -- หน้าตั้งค่าถามเป็นบาท  โค้ดคิดเป็นสตางค์ เหมือนทุกตัวที่เป็นเงิน
    MAX_CREDIT  = { "LoanMaxCredit",           100 },
}

function KR.creditOpt(name)
    return KR.svOpt(CREDIT_SV, name, KR.CREDIT[name])
end

-- ยศจากแต้ม CP
function KR.creditTier(cp)
    cp = math.floor(tonumber(cp) or 0)
    local best = KR.CREDIT.TIERS[1]
    for i = 1, #KR.CREDIT.TIERS do
        if cp >= KR.CREDIT.TIERS[i].cp then best = KR.CREDIT.TIERS[i] end
    end
    return best
end

function KR.creditNextTier(cp)
    cp = math.floor(tonumber(cp) or 0)
    for i = 1, #KR.CREDIT.TIERS do
        if cp < KR.CREDIT.TIERS[i].cp then return KR.CREDIT.TIERS[i] end
    end
    return nil                       -- ยศสูงสุดแล้ว
end

-- วงเงินจริง = เพดานของยศ ลบยอดที่ยังค้างอยู่
-- ==============================================================================
-- เพดานวงเงินที่ใช้ได้จริงของคนนี้
--
-- 0.6.11 — เพิ่มเพดานรวมของทั้งเซิร์ฟ (sandbox: Kuraya.LoanMaxCredit)
--
-- ของเดิมเพดานมาจากยศ CP อย่างเดียว (BRONZE 10,000 -> BLACK 120,000)
-- ซึ่งเป็นกติกาที่ดีสำหรับ "ใครควรได้มากกว่าใคร" แต่ตอบไม่ได้เลยว่า
-- **เซิร์ฟนี้อยากปล่อยกู้สูงสุดเท่าไร** ซึ่งเป็นคำถามของเจ้าของเซิร์ฟ ไม่ใช่ของผู้เล่น
--
-- สองอย่างนี้ทำงานคู่กัน ไม่ใช่แทนกัน
--   ยศ  = สัดส่วน  ใครขยันสะสม CP ได้เพดานสูงกว่า
--   เพดานรวม = ฝา  ต่อให้ยศสูงแค่ไหนก็ไม่เกินตัวเลขนี้
-- เอาตัวที่ **น้อยกว่า** เสมอ  เพราะฝาที่ยกให้สูงขึ้นได้ไม่ใช่ฝา
--
-- 0 = ไม่มีฝา ใช้เพดานตามยศล้วน ๆ เหมือนก่อนหน้านี้ทุกประการ
function KR.creditLimit(cp)
    local lim = KR.creditTier(cp).limit
    local cap = math.floor(tonumber(KR.creditOpt("MAX_CREDIT")) or 0)
    if cap > 0 and cap < lim then lim = cap end
    return lim
end

function KR.creditAvailable(cp, out)
    return math.max(0, KR.creditLimit(cp) - math.max(0, math.floor(tonumber(out) or 0)))
end

-- คำนวณสัญญาก่อนกด  ทั้งสองฝั่งเรียกตัวนี้ตัวเดียวกัน จะได้ไม่มีทางไม่ตรงกัน
function KR.creditQuote(amount, terms)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    terms  = math.max(1, math.floor(tonumber(terms) or 1))
    local interest = math.floor(amount * KR.creditOpt("RATE_BP") / 10000)
    local total    = amount + interest
    -- งวดสุดท้ายรับเศษไปทั้งหมด  ผลรวมต้องเท่ากับ total เป๊ะ ห้ามขาดห้ามเกิน
    local each     = math.floor(total / terms)
    local last     = total - each * (terms - 1)
    return {
        amount = amount, terms = terms,
        interest = interest, total = total,
        each = each, last = last,
    }
end

-- ยอดที่ต้องจ่ายงวดนี้ (งวดสุดท้ายไม่เท่ากับงวดอื่น)
function KR.creditInstalment(plan)
    plan = plan or {}
    local n     = math.floor(tonumber(plan.terms) or 0)
    local paidN = math.floor(tonumber(plan.paidN) or 0)
    if paidN >= n then return 0 end
    if paidN == n - 1 then return math.floor(tonumber(plan.last) or 0) end
    return math.floor(tonumber(plan.each) or 0)
end

-- ค่าปรับสะสมจากการจ่ายช้า
function KR.creditLateFee(plan, nowTs)
    plan = plan or {}
    local due = tonumber(plan.dueAt) or 0
    local dt  = (tonumber(nowTs) or 0) - due
    if dt <= 0 then return 0, 0 end
    local days = math.floor(dt / KR.DAY_SEC) + 1
    local amt  = KR.creditInstalment(plan)
    return math.floor(amt * KR.creditOpt("LATE_BP") * days / 10000), days
end

-- ==============================================================================
-- คู่มือในเกม  (ปุ่ม ? มุมขวาบน)
--
-- ทำไมเนื้อหาอยู่ในไฟล์ shared ไม่ใช่ไฟล์ UI
--   ไฟล์นี้โหลดก่อนทุกอย่างเสมอและไม่พึ่งอะไรเลย
--   วางไว้ในไฟล์ UI แล้ววันหนึ่งอยากให้ฝั่งเซิร์ฟอ้างถึงหน้าไหน จะอ้างไม่ได้
--
-- รูปประกอบ: media/textures/Kuraya/help/<img>.png  ขนาด 1280x720
--   ไฟล์ไหนยังไม่มี จอจะขึ้นกรอบว่างพร้อมชื่อไฟล์ที่รออยู่  ไม่พัง
--   แปลว่าเอารูปมาใส่ทีหลังได้โดยไม่ต้องแตะโค้ดเลย แค่วางไฟล์ให้ชื่อตรง
--
-- ข้อความ caption เป็นอังกฤษเพราะฟอนต์ bitmap ของ PZ ไม่มี glyph ไทย
-- แต่ **ในรูปใส่ไทยได้เต็มที่** เพราะรูปคือภาพ ไม่ใช่ตัวหนังสือ
-- นั่นเป็นทางเดียวที่คู่มือภาษาไทยจะมีอยู่จริงในเกมนี้
-- ==============================================================================
KR.HELP_DIR = "media/textures/Kuraya/help/"

KR.HELP = {
    { id = "start", label = "Getting started", pages = {
        { img = "help_start_1", title = "Opening the shop",
          body = "The cat button floats at the side of your screen. Click it to open Kuraya. " ..
                 "Drag it anywhere you like - the position is saved on the server, so it stays " ..
                 "where you put it even on another machine." },
        { img = "help_start_2", title = "Finding your way around",
          body = "Pages are on the left. Your three balances are always in the top right, on every " ..
                 "page, so you never have to leave what you are doing to check them. The bar at the " ..
                 "bottom shows what is happening in the shop right now." },
        { img = "help_start_3", title = "The three currencies",
          body = "Cash lives in your Akacount and is what most things cost. HF points are the server " ..
                 "currency and can be sent between players. CP comes from HF Town Rank and cannot be " ..
                 "bought - you earn it by helping the town." },
    } },

    { id = "buying", label = "Buying", pages = {
        { img = "help_buying_1", title = "Reading a listing",
          body = "Each row shows every currency that listing accepts, one line per option. " ..
                 "Sold out items are not hidden - they stay in the list, greyed out, with the date " ..
                 "they come back so you know whether it is worth waiting." },
        { img = "help_buying_2", title = "Picking how you pay",
          body = "Click a row and the shop asks which currency to use. The right-hand column shows " ..
                 "what you will have left after paying. If you cannot afford any option, the confirm " ..
                 "button says so instead of letting you press it and be refused." },
        { img = "help_buying_3", title = "Categories, filter and sort",
          body = "The category strip sits above the list and the server remembers which one you were " ..
                 "looking at. The Currency chip hides anything that does not take the currency you " ..
                 "picked, which is the fastest way to see what your HF can actually buy." },
        { img = "help_buying_4", title = "What the tags mean",
          body = "NEW is anything listed today. SALE is a timed discount and the price shown is " ..
                 "already the discounted one. SOLD OUT with no date means nobody has said when it " ..
                 "comes back." },
    } },

    { id = "account", label = "Your account", pages = {
        { img = "help_account_1", title = "The Account page",
          body = "Your card and balances on the left, what you have spent in the middle, and " ..
                 "anything that needs your attention on the right. Nothing here needs you to walk " ..
                 "anywhere - but deposits, withdrawals and card designs still happen at the bank." },
        { img = "help_account_2", title = "Spending Tier",
          body = "Every 2,000 you spend in the shop moves you up one tier, to a maximum of Tier 5. " ..
                 "It counts your total ever spent and never goes down, so taking a week off does not " ..
                 "cost you anything." },
        { img = "help_account_3", title = "Sending money and points",
          body = "You can send cash, HF or CP to another player who is online. The fee is shown " ..
                 "before you press, not taken quietly afterwards. Transfers are final - there is no " ..
                 "undo, so check the name." },
        { img = "help_account_4", title = "Your spending history",
          body = "This lists what you spent in the shop: purchases, auctions, bills and loan " ..
                 "payments. Bank deposits and withdrawals are deliberately not here - your full " ..
                 "statement is at the bank counter." },
    } },

    { id = "bill", label = "House bill", pages = {
        { img = "help_bill_1", title = "If you are the house head",
          body = "The bill card shows what is owed and how long you have. The button takes you " ..
                 "straight to the payment screen. The strip across the top turns orange when it is " ..
                 "due and red once it is late." },
        { img = "help_bill_2", title = "If you live there but are not the head",
          body = "You cannot pay someone else's bill, but you can press the button to remind the " ..
                 "house head. They see it immediately. Once you have sent it the card says so, so " ..
                 "two people do not spam the same reminder." },
    } },

    { id = "auction", label = "Auction", pages = {
        { img = "help_auction_1", title = "Reading the board",
          body = "Players list their own lots. Every lot is a card with the cover art and colour " ..
                 "the seller picked. A red card is a shop lot and is pinned to the top. The card " ..
                 "border is about you: green you are winning, orange you were outbid, gold your own." },
        { img = "help_auction_2", title = "Bidding",
          body = "The number on the button is the minimum next bid, not the current price. Your " ..
                 "money is held, not spent - if somebody outbids you it comes straight back. " ..
                 "If the seller set a Buy now price you can end it there and then." },
        { img = "help_auction_3", title = "Winning, and paying in two steps",
          body = "A bid in the last two minutes pushes the end back two minutes, so nothing is won " ..
                 "by sniping. When a lot closes the winner is charged half as a deposit and the " ..
                 "seller is NOT paid yet. Pay the balance within 24 real hours and the seller gets " ..
                 "the money; miss it and the deposit is refunded in full and the lot disappears." },
        { img = "help_auction_4", title = "Listing your own lot, and slots",
          body = "Everyone can open a lot and everyone starts with one slot. Fill in what you are " ..
                 "selling, the start price, the bid step and an optional Buy now price, then pick " ..
                 "the cover art and card colour. Nothing is taken from your bag - you and the " ..
                 "winner meet up to hand it over. Extra permanent slots are bought on the page." },
    } },

    { id = "credit", label = "Credit", pages = {
        { img = "help_credit_1", title = "Who is allowed to borrow",
          body = "You have to be in a safehouse and have been in it for three days of real time - " ..
                 "survivor days do not count and dying does not reset it. Everyone in one safehouse " ..
                 "shares a combined debt cap. Your own limit still comes from your CP tier, and you " ..
                 "can only have one loan running at a time." },
        { img = "help_credit_2", title = "Paying it back",
          body = "Instalments are taken automatically. Paying late adds a fee per day, and an " ..
                 "account in arrears cannot borrow again until it is cleared." },
        { img = "help_credit_3", title = "If you do not pay",
          body = "Miss a due date and the system starts collecting the instalment from your account " ..
                 "by itself. If that pushes your balance more than 5,000 into the red the whole shop " ..
                 "locks - no buying, no bidding, no transfers - and only an admin can lift it. " ..
                 "Paying the loan off afterwards is not enough." },
    } },

    { id = "bank", label = "The bank", pages = {
        { img = "help_bank_1", title = "Finding a counter",
          body = "Withdrawals, card designs and your full statement only happen at a bank counter. " ..
                 "Deposits you can do anywhere by right-clicking cash." },
        { img = "help_bank_2", title = "Depositing cash",
          body = "Right-click money in your inventory and choose deposit. The notes leave your bag " ..
                 "and land in your account - nothing is created or destroyed on the way." },
        { img = "help_bank_3", title = "Withdrawing",
          body = "Stand at a counter, type the amount and press withdraw. You get physical notes " ..
                 "back, which can be stolen, so only carry what you need." },
        { img = "help_bank_4", title = "Card designs",
          body = "One card per player, bound to you - nobody else can use it. Changing the design " ..
                 "destroys the old card and issues a new one. Designs an admin has priced must be " ..
                 "bought once and are yours forever after that." },
    } },

}

function KR.helpCat(i)
    return KR.HELP[math.max(1, math.min(#KR.HELP, math.floor(tonumber(i) or 1)))]
end

function KR.helpPage(ci, pi)
    local cat = KR.helpCat(ci)
    local n = #cat.pages
    return cat.pages[math.max(1, math.min(n, math.floor(tonumber(pi) or 1)))], n
end


-- ==============================================================================
-- เงื่อนไขการกู้เงิน  (0.5)
--
-- เจ้าของเซิร์ฟสั่งมาสามข้อ และทั้งสามข้อมีเหตุผลเดียวกันคือ
-- "เงินกู้ต้องมีคนที่ตามตัวได้อยู่เบื้องหลัง"
--
--   1. ต้องอยู่เซฟเฮาส์ และอยู่มาแล้วเกิน 3 วัน **จริง**
--      ไม่ใช่วันในเกม  ตัวละครตายแล้วสร้างใหม่ไม่ได้รีเซ็ตเวลานี้
--      เพราะสิ่งที่เรากำลังวัดคือ "คนนี้อยู่กับเซิร์ฟมานานพอไหม" ไม่ใช่อายุตัวละคร
--   2. หนี้ของทุกคนในเซฟเฮาส์เดียวกันรวมกันไม่เกิน 10,000
--      กันการตั้งเซฟเฮาส์รวมหัวกันกู้ทีละคนจนได้เงินก้อนใหญ่
--   3. ยอดในบัญชีติดลบเกิน 5,000 = ล็อกร้านทั้งหมด จนกว่าแอดมินจะปลด
--      ต่างจากการแช่แข็งเพราะผิดนัดสามงวด ซึ่งจ่ายงวดเดียวก็ปลดเอง
-- ==============================================================================
KR.LOAN_GATE = {
    SAFEHOUSE_DAYS  = 3,          -- วันจริงที่ต้องอยู่ในเซฟเฮาส์ก่อนถึงจะกู้ได้
    SAFEHOUSE_CAP   = 1000000,    -- 10,000.00  หนี้รวมของทั้งเซฟเฮาส์ (สตางค์)
    SHOP_LOCK_DEBT  = 500000,     -- 5,000.00   ติดลบเกินนี้แล้วร้านล็อก (สตางค์)
}

-- สองตัวที่เป็นเงินถามเป็น "บาท" ในหน้าตั้งค่า แล้วคูณ 100 กลับเป็นสตางค์ตรงนี้
-- เจ้าของเซิร์ฟสั่งไว้ว่าติดลบถึง 5,000 แล้วร้านล็อก  ในหน้าตั้งค่าจึงต้องเห็นเลข 5000
-- ไม่ใช่ 500000 ซึ่งเป็นเลขที่ต้องแปลในหัวก่อนถึงจะรู้ว่าตรงกับที่สั่งไว้หรือเปล่า
local LOAN_SV = {
    SAFEHOUSE_DAYS = { "LoanSafehouseDays",      1 },
    SAFEHOUSE_CAP  = { "LoanSafehouseMaxDebt", 100 },
    SHOP_LOCK_DEBT = { "ShopLockDebt",         100 },
}

function KR.loanOpt(name)
    return KR.svOpt(LOAN_SV, name, KR.LOAN_GATE[name])
end

-- ต้องอยู่เซฟเฮาส์ถึงจะกู้ได้ไหม
--
-- เปิดให้ปิดได้เพราะสะพานไปหา SafeHouse API ของ PZ เป็นสิ่งที่เรายืนยันจากในเกมไม่ได้
-- ถ้าบิลด์ไหนชื่อเมธอดไม่ตรง ระบบจะปฏิเสธทุกคนแทนที่จะปล่อยผ่านทุกคน (ล้มไปทางปิด)
-- สวิตช์นี้คือทางออกให้เจ้าของเซิร์ฟโดยไม่ต้องรอเราแก้โค้ด
function KR.loanNeedsSafehouse()
    return KR.svBool("LoanNeedSafehouse", true)
end


-- ==============================================================================
-- ประมูลแบบผู้เล่นลงเอง  (0.5)
--
-- เปลี่ยนหลักคิดจากรอบก่อนหนึ่งข้อ และเป็นข้อใหญ่:
-- **ระบบไม่ยึดของอีกแล้ว**  ผู้ขายกับผู้ชนะไปนัดรับกันเอง
--
-- ทำไมถึงเป็นทางที่ถูกสำหรับเซิร์ฟนี้
--   ของใน PZ มีสภาพ กระสุน ความคม และของบางอย่างเป็นภาชนะที่มีของอยู่ข้างใน
--   ระบบที่ยึดของแล้วเสกคืนทำสิ่งเหล่านั้นหายหมด ปืนที่ยิงมาครึ่งแม็กกลับมาเต็มแม็ก
--   กระเป๋าที่มีของอยู่ข้างในกลับมาเป็นกระเป๋าเปล่า
--   การให้คนไปเจอกันเองรักษาของไว้ได้ครบทุกอย่าง และเป็นเรื่องที่คนเล่นเซิร์ฟนี้ทำกันอยู่แล้ว
--
-- สิ่งที่ระบบดูแลจึงเหลืออย่างเดียวคือ **เงิน** ซึ่งเป็นสิ่งที่คนโกงกันได้จริง
-- ------------------------------------------------------------------------------
-- รูปปกล็อต  ผู้ขายเลือกจากชุดนี้
-- ไม่ให้พิมพ์ชนิดไอเทมแล้ว เพราะล็อตไม่ได้ผูกกับไอเทมอีกต่อไป
-- และ "ปืน" สื่อกับคนซื้อได้ดีกว่า "Base.Pistol" อยู่แล้ว
-- ==============================================================================
KR.AUCT_ART = {
    { id = "car",    th = "รถ",        en = "Vehicle"  },
    { id = "weapon", th = "อาวุธ",     en = "Weapon"   },
    { id = "gun",    th = "ปืน",       en = "Gun"      },
    { id = "food",   th = "อาหาร",     en = "Food"     },
    { id = "tool",   th = "เครื่องมือ", en = "Tools"    },
    { id = "gem",    th = "เพชร",      en = "Valuables"},
    { id = "cat",    th = "แมว",       en = "Cat"      },
    { id = "dog",    th = "หมา",       en = "Dog"      },
    { id = "hen",    th = "ไก่",        en = "Chicken"  },
    { id = "cow",    th = "วัว",        en = "Cow"      },
    { id = "pig",    th = "หมู",        en = "Pig"      },
    { id = "house",  th = "บ้าน",       en = "House"    },
    { id = "shirt",  th = "เสื้อ",      en = "Clothing" },
    { id = "star",   th = "ดาว",       en = "Other"    },
}
KR.AUCT_ART_DEFAULT = "star"

function KR.auctArtOk(id)
    for _, a in ipairs(KR.AUCT_ART) do
        if a.id == id then return true end
    end
    return false
end

-- สีพื้นหลังของการ์ด  ผู้ขายเลือกได้ ทำให้กระดานอ่านง่ายขึ้นเวลามีล็อตเยอะ
-- เก็บเป็น id ไม่ใช่ค่าสี  ไคลเอนต์แปลงเป็นสีเอง ธีมเปลี่ยนทีหลังได้โดยไม่ต้องแก้ข้อมูลเก่า
KR.AUCT_BG = {
    { id = "slate",  th = "เทา",    en = "Slate"  },
    { id = "rose",   th = "ชมพู",   en = "Rose"   },
    { id = "amber",  th = "ส้ม",    en = "Amber"  },
    { id = "forest", th = "เขียว",  en = "Forest" },
    { id = "ocean",  th = "ฟ้า",    en = "Ocean"  },
    { id = "plum",   th = "ม่วง",   en = "Plum"   },
}
KR.AUCT_BG_DEFAULT = "slate"

function KR.auctBgOk(id)
    for _, b in ipairs(KR.AUCT_BG) do
        if b.id == id then return true end
    end
    return false
end

KR.AUCT_SLOT = {
    FREE  = 1,        -- ทุกคนได้ฟรีคนละหนึ่งช่อง
    PRICE = 250000,   -- 2,500.00  ซื้อช่องถาวรเพิ่ม (สตางค์)
    MAX   = 10,       -- เพดานกันคนซื้อจนถล่มกระดาน
}

-- MAX (เพดานจำนวนช่องที่ซื้อได้) ไม่เปิดให้ตั้งแล้ว  10 ช่องคือกันคนถล่มกระดาน
-- ไม่ใช่ตัวเลขที่แต่ละเซิร์ฟควรต่างกัน  PRICE ถามเป็นบาท คูณ 100 กลับเป็นสตางค์
local AUCT_SLOT_SV = {
    FREE  = { "AuctionFreeSlots",   1 },
    PRICE = { "AuctionSlotPrice", 100 },
}

function KR.auctSlotOpt(name)
    return KR.svOpt(AUCT_SLOT_SV, name, KR.AUCT_SLOT[name])
end

-- การชำระเงินสองรอบ
--
-- ปิดล็อต -> เก็บมัดจำครึ่งหนึ่งไว้ที่ระบบ คนขายยังไม่ได้เงิน
-- ผู้ชนะจ่ายส่วนที่เหลือ -> คนขายได้เต็มจำนวน (หักค่าธรรมเนียม)
-- เลยกำหนดแล้วไม่จ่าย -> คืนมัดจำเต็มจำนวน ล็อตหายไป ไม่มีใครได้อะไร
--
-- ทำไมต้องมัดจำครึ่งเดียวแทนที่จะตัดเต็มตอนปิด
--   เพราะของยังไม่ได้ส่ง  การตัดเงินเต็มก่อนเจอตัวคนขายคือการบังคับให้ผู้ซื้อเชื่อใจฝ่ายเดียว
--   ครึ่งหนึ่งพอที่จะทำให้การบิดเล่นเจ็บ แต่ไม่มากพอที่จะทำให้คนกลัวการบิด
KR.AUCT_PAY = {
    DEPOSIT_BP = 5000,      -- 50.00%  มัดจำตอนปิดล็อต
    WINDOW     = 86400,     -- 24 ชม.จริง  เวลาที่ผู้ชนะมีให้จ่ายส่วนที่เหลือ
}

-- 0.6.5 ถอดทั้งสองช่องออกจากหน้าตั้งค่า
-- มัดจำครึ่งหนึ่ง + จ่ายส่วนที่เหลือใน 24 ชม. เป็นกติกาของระบบ ไม่ใช่รสนิยมของเซิร์ฟ
-- คนที่ขยับสองตัวนี้โดยไม่ได้อ่านโค้ดมีโอกาสตั้งค่าที่ทำให้ล็อตค้างมากกว่าจะได้อะไรคืน
function KR.auctPayOpt(name)
    return KR.AUCT_PAY[name]
end

function KR.auctDeposit(bid)
    bid = math.max(0, math.floor(tonumber(bid) or 0))
    return math.floor(bid * KR.auctPayOpt("DEPOSIT_BP") / 10000)
end

-- ==============================================================================
-- แพ็ก HF Point
--
-- เรื่องสำคัญที่สุดของทั้งบล็อกนี้: **ม็อดไม่ยุ่งกับเงินจริงเลย**
-- ราคาบาทที่เก็บไว้เป็นแค่ตัวเลขให้แสดงกับให้แอดมินอ้างอิง
-- ไม่มีการเชื่อมกับช่องทางชำระเงินใด ๆ ทั้งสิ้น  ผู้เล่นโอนกันนอกเกม
-- แล้วแอดมินเป็นคนกดส่ง HF ให้เอง  คำขอในระบบคือ "ใบสั่ง" ไม่ใช่ "ใบเสร็จ"
--
-- แปดช่องแบ่งหน้าที่ตายตัวตามที่เจ้าของเซิร์ฟสั่ง
--   1-6  แพ็กปกติ
--   7    แพ็กจำกัดเวลาและจำนวน
--   8    แพ็กชุดใหญ่ลดเฉพาะช่วง
-- เก็บเป็นดัชนีคงที่ ไม่ใช่ลิสต์ที่ไหลได้  เพราะฝั่งจอวางตำแหน่งตามหมายเลขช่อง
-- ถ้าปล่อยให้เลื่อนได้ ช่อง 7 จะไปโผล่กลางแถวแพ็กปกติแล้วฟอร์มพิเศษจะตามไม่ทัน
-- ==============================================================================
KR.HFPACK = {
    SLOTS    = 8,
    LIMITED  = 7,       -- ช่องจำกัดเวลา + จำกัดจำนวน
    MEGA     = 8,       -- ช่องชุดใหญ่ลดเฉพาะช่วง
    NAME_MAX = 28,
    NOTE_MAX = 40,      -- ช่องอ้างอิงการโอนที่แอดมินกรอก
    REQ_MAX  = 3,       -- คำขอที่ยัง "รออนุมัติ" ได้พร้อมกันต่อคน
    LOG_MAX  = 200,     -- ประวัติที่เก็บไว้ทั้งเซิร์ฟ
}

-- รูปแพ็ก  แอดมินเลือกได้ว่ารูปไหนอยู่ช่องไหน
--
-- เก็บเป็น id ไม่ใช่ path  ไคลเอนต์แปลงเป็นไฟล์เอง (ดู U.hfpIcon)
-- เหตุผลเดียวกับสีพื้นการ์ดประมูล: เปลี่ยนอาร์ตทีหลังได้โดยไม่ต้องแตะข้อมูลที่บันทึกไว้แล้ว
--
-- เรียงจาก "เล็ก" ไป "ใหญ่" ตามที่ตาคนอ่านภาพ  ไม่ได้เรียงตามลำดับในไฟล์ต้นฉบับ
-- แอดมินที่ไล่เลือกจากบนซ้ายไปล่างขวาจะได้ลำดับที่สื่อความหมายเองโดยไม่ต้องคิด
KR.HFP_ICON = {
    { id = "hfp1", th = "ถุงเงิน",       en = "Coin pouch"   },
    { id = "hfp2", th = "หีบไม้",        en = "Wooden chest" },
    { id = "hfp3", th = "หีบทอง",        en = "Gold chest"   },
    { id = "hfp4", th = "หีบใหญ่",       en = "Big chest"    },
    { id = "hfp7", th = "หีบบนแท่น",     en = "Pedestal"     },
    { id = "hfp5", th = "รถเข็นมงกุฎ",   en = "Party cart"   },
    { id = "hfp8", th = "รถเข็นราชา",    en = "King cart"    },
    { id = "hfp6", th = "กองสมบัติ",     en = "Treasure pile"},
    { id = "hfp9", th = "ปราสาท",        en = "Castle"       },
}
KR.HFP_ICON_DEFAULT = "hfp1"

function KR.hfpIconOk(id)
    for _, a in ipairs(KR.HFP_ICON) do
        if a.id == id then return true end
    end
    return false
end

-- สถานะคำขอ  เก็บเป็นสตริงสั้น ๆ เพราะต้องส่งข้ามสายทุกครั้งที่ sync
KR.HFP_ST = {
    WAIT = "wait",      -- รออนุมัติ
    DONE = "done",      -- อนุมัติและส่งให้แล้ว
    DENY = "deny",      -- แอดมินปฏิเสธ
    GONE = "gone",      -- ผู้เล่นถอนคำขอเอง
}

-- ช่องนี้เป็นช่องพิเศษไหม  ใช้ทั้งฝั่งเซิร์ฟตอนตรวจค่าและฝั่งจอตอนวางฟอร์ม
function KR.hfpKind(slot)
    slot = math.floor(tonumber(slot) or 0)
    if slot == KR.HFPACK.LIMITED then return "limited" end
    if slot == KR.HFPACK.MEGA    then return "mega"    end
    return "normal"
end

-- ราคาที่ควรโชว์ตอนนี้ของแพ็กหนึ่งใบ  คืน ราคาจริง, ราคาก่อนลด (ถ้ามี)
--
-- ช่อง 8 มีสองราคาและช่วงลดที่หมดอายุได้  ตรรกะนี้ต้องอยู่ที่เดียว
-- ไม่งั้นฝั่งจอกับฝั่งเซิร์ฟจะคิดคนละแบบแล้วผู้เล่นขอซื้อในราคาที่แอดมินไม่ได้ตั้ง
function KR.hfpPrice(p, ts)
    if type(p) ~= "table" then return 0, nil end
    local full = math.max(0, math.floor(tonumber(p.thb) or 0))
    local cut  = tonumber(p.thbCut)
    if not cut or cut <= 0 or cut >= full then return full, nil end
    local ends = tonumber(p.cutEndsAt)
    if ends and ts and ts >= ends then return full, nil end
    return math.floor(cut), full
end

-- แพ็กนี้ผู้เล่นกดขอซื้อได้ไหมตอนนี้  คืน ได้ไหม, เหตุผลถ้าไม่ได้
--
-- เหตุผลถูกส่งกลับไปโชว์จริง  "ขอซื้อไม่ได้" เฉย ๆ คือข้อความที่ทำให้คนมาทักแอดมิน
function KR.hfpOpen(p, ts)
    if type(p) ~= "table" or not p.set then return false, "empty"  end
    if p.off                            then return false, "off"   end

    local ends = tonumber(p.endsAt)
    if ends and ts and ts >= ends       then return false, "ended" end

    local cap  = tonumber(p.stock)
    if cap and cap > 0 then
        if (tonumber(p.sold) or 0) >= cap then return false, "sold" end
    end
    return true
end

-- นาที -> วินาที  ทุกช่องเวลาที่แอดมินกรอกในม็อดนี้เป็น "นาที" แล้ว
--
-- เจ้าของเซิร์ฟสั่งเปลี่ยนหน่วยจากชั่วโมงเป็นนาทีเพราะของลดราคาส่วนใหญ่
-- เปิดกันสั้นกว่าหนึ่งชั่วโมง แล้วช่องที่กรอกได้แต่จำนวนเต็มทำให้ตั้ง 30 นาทีไม่ได้เลย
function KR.minsToSec(m)
    m = tonumber(m)
    if not m or m <= 0 then return nil end
    return math.floor(m * 60)
end

-- วินาที -> ข้อความบอกว่ากี่วันกี่ชั่วโมง  ใช้เป็นบรรทัดใบ้ใต้ช่องกรอก
-- คนกรอก 20160 นาทีต้องเห็นทันทีว่ามันคือสองสัปดาห์ ไม่ใช่ไปเปิดเครื่องคิดเลข
function KR.minsHint(m)
    m = tonumber(m)
    if not m or m <= 0 then return nil end
    if m < 60 then return math.floor(m) .. KR.L(" นาที", " min") end
    local h = m / 60
    if h < 24 then
        local s = (h % 1 == 0) and tostring(math.floor(h)) or string.format("%.1f", h)
        return s .. KR.L(" ชม.", " hr")
    end
    local d = h / 24
    local s = (d % 1 == 0) and tostring(math.floor(d)) or string.format("%.1f", d)
    return s .. KR.L(" วัน", " days")
end

return KR
