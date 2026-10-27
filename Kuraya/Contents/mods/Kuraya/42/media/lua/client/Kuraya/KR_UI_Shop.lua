-- ==============================================================================
-- Kuraya — client/Kuraya/KR_UI_Shop.lua
-- หน้าต่างร้านค้า  แถบซ้าย + หัวเรื่อง + ค้นหา/กรอง/เรียง + ลิสต์ + หน้าต่างจ่ายเงิน
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- โครงเดียวกันทุกหน้า  ต่างกันแค่ "เอาอะไรมาใส่ลิสต์" กับ "ปุ่มขวาสุดเขียนว่าอะไร"
-- เพิ่มหน้าใหม่ = เพิ่มหนึ่ง entry ใน PAGES กับหนึ่งฟังก์ชัน rows()
--
-- ห้าม require KR_Client จากไฟล์นี้  มันจะกลายเป็น require วนกันแล้วม็อดขึ้น [ERRORS]
-- อ่าน KRClient เป็น global ตอนเรียกใช้แทน  ตอนนั้นมันโหลดเสร็จแล้วแน่นอน
-- ==============================================================================
require("Kuraya/KR_Const")
print("[Kuraya] KR_UI_Shop  v" .. KR.VERSION)
require("Kuraya/KR_Theme")

local U = KRUI

-- ------------------------------------------------------------------------------
-- ความสูงของปุ่มเลือกและช่องกรอก
--
-- ต้องประกาศ "บนสุด" ของไฟล์  ไม่ใช่ตรงที่ใช้ครั้งแรก
--
-- Lua ผูก local ตอนคอมไพล์  ฟังก์ชันที่เขียนไว้ก่อนบรรทัด `local function tagH`
-- จะมองคำว่า tagH เป็น global (= nil) แล้วพังตอนรันเท่านั้น ไม่พังตอนโหลด
-- (เจอมาแล้วสองรอบในไฟล์นี้: drawCatBar และ S.openBills ฝั่งเซิร์ฟ)
--
-- ผูกกับความสูงฟอนต์จริง ไม่ใช่เลขตายตัว  ผู้เล่นที่ตั้ง UI scale 1.5
-- จะได้กล่องที่โตตามตัวหนังสือ ไม่ใช่ตัวหนังสือล้นกล่อง
-- ------------------------------------------------------------------------------
-- ปรับขนาดช่องกรอกให้ถูกวิธี
--
-- `box.width = 100` **ไม่** ทำให้ช่องกรอกกว้างขึ้นจริง
-- ISUIElement เก็บขนาดจริงไว้ที่ javaObject  การเซ็ตฟิลด์ Lua ตรง ๆ เปลี่ยนแค่ตัวเลขฝั่ง Lua
-- ผลคือ "วาดออกมากว้าง แต่พื้นที่รับคลิกยังเป็นขนาดเดิม" -> จิ้มแล้วไม่โฟกัส
-- (ผู้เล่นรายงานว่า "ช่องกรอกของแอดมินกดไม่ค่อยติด")
--
-- ต้องเรียก setWidth / setHeight เท่านั้น  มันไปอัปเดต javaObject ให้ด้วย
-- ==============================================================================
-- ช่องกรอกโผล่ได้ก็ต่อเมื่อ "เฟรมนี้มีคนวางมันจริง"
--
-- ปัญหาที่ต้องแก้ (เจ้าของเซิร์ฟส่งรูปมาสี่ใบ):
--   * เปิดร้านแพ็ก HF แล้วช่องกรอกของหน้าจัดการลอยทับป๊อปอัปอยู่
--   * อยู่แท็บย่อย "คำขอ" แต่ช่องของแท็บ "ตั้งแพ็ก" ยังลอยอยู่กลางลิสต์
--
-- ทำไมของเดิมพัง: ISTextEntryBox เป็น **ลูกจริงของหน้าต่าง** มันวาดตัวเองทับ
-- ทุกอย่างที่เราวาด  การ "ไม่วาดมัน" จึงไม่มีความหมายเลย ต้องสั่ง setVisible เท่านั้น
-- และของเดิมสั่งจากตาราง `show` ที่ไล่ตามแท็บด้วยมือ = ต้องจำให้ครบทุกครั้งที่เพิ่มหน้าใหม่
-- ความครบที่พึ่งความจำของคนเขียนคนถัดไป คือความครบที่จะพังในรอบถัดไปเสมอ
--
-- ของใหม่กลับด้านความรับผิดชอบ: ไม่มีใครต้องประกาศว่า "แท็บนี้ใช้ช่องอะไร" อีก
-- ใครวาดช่องไหน ช่องนั้นถูกประทับเลขเฟรมไว้  ตอนจบเฟรมค่อยเปิดเฉพาะตัวที่ถูกประทับ
-- ช่องที่ไม่มีใครวาง = ไม่มีใครเห็น โดยอัตโนมัติ ไม่ว่าจะเพิ่มหน้าใหม่กี่หน้าก็ตาม
--
-- ทุกจุดที่วางช่องกรอกในม็อดเรียก sizeBox อยู่แล้วทั้งหมด จึงประทับที่นี่ที่เดียวพอ
-- ==============================================================================
-- ตัวนับต้องเป็น local ของไฟล์  ไม่ใช่ฟิลด์บน KRShop
--
-- ตอนแรกผมเขียน `KRShop.__frame = 0` ตรงนี้ แล้วด่าน client_load ตีกลับทันที:
--     KR_UI_Shop.lua:57: attempt to index a nil value (global 'KRShop')
-- เพราะบรรทัดนี้อยู่เหนือจุดที่คลาส KRShop ถูกประกาศ  ทั้งไฟล์เลยตายตั้งแต่โหลด
-- ซึ่งคือบั๊กชนิดเดียวกับที่ทำให้ร้านเปิดมาเป็นกรอบเปล่าใน 0.5.0/0.5.1 เป๊ะ ๆ
-- ต่างกันแค่ครั้งนี้มีด่านจับได้ก่อนถึงมือใคร
local frameNo = 0

local function sizeBox(box, w, h)
    if not box then return end
    box.__krFrame = frameNo
    if w then pcall(function() box:setWidth(math.max(8, math.floor(w))) end) end
    if h then pcall(function() box:setHeight(math.max(8, math.floor(h))) end) end
end

-- มีเมธอดนี้จริงไหม
--
-- pcall อย่างเดียวไม่พอ  Kahlua ยัง dump stack trace เต็ม ๆ ลง console
-- ถึงจะจับ error ได้ (ISRemoveItemTool.removeItem เคย dump 1,332 ครั้งต่อ session แบบนั้น)
-- ฝั่งเซิร์ฟมี U_hasMethod อยู่แล้ว ฝั่งจอต้องมีของตัวเองเพราะคนละไฟล์คนละสโคป
local function U_hasMethod2(obj, name)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj[name] end)
    return ok and type(v) == "function"
end

local function tagH() return U.h(U.F.s) + 12 end
local function boxH() return U.h(U.F.s) + 12 end

KRShop   = ISPanel:derive("KRShop")
KRShopUI = KRShopUI or {}

-- ขนาดหน้าต่าง
--   900x580 -> 1180x740 (ฟอนต์ขยับขึ้นหนึ่งขั้น ของเดิมอัดกันเกินไป)
--   1180x740 -> 1280x800 (หน้า Account แบ่งสามคอลัมน์ + ตารางประวัติที่เลื่อนได้)
--   1280x800 -> 1280x960 (เจ้าของเซิร์ฟส่งภาพมาว่าตารางประวัติล่างสุดโดนตัดหัวตัดหาง)
--
-- ทำไมเพิ่มความสูงอย่างเดียว ไม่เพิ่มความกว้าง
--   สิ่งที่ล้นคือ "แถวที่ต่อกันลงไป" (ประวัติการใช้จ่าย รายชื่อผู้เล่น รายการของ)
--   แถวพวกนี้ยาวลง ไม่ได้ยาวออกข้าง  เพิ่มความกว้างจึงได้แค่ช่องว่างข้างตัวหนังสือ
--
-- 960 ไม่ใช่ตัวเลขมั่ว  จอ 1080p เหลือขอบบน-ล่างอย่างละ 60 พอให้ยังเห็นว่าเป็นหน้าต่าง
-- ไม่ใช่โหมดเต็มจอ  ส่วนจอที่เตี้ยกว่านี้ fitHeight() ย่อให้เองอยู่แล้ว
local W, H = 1280, 960

-- เปิดให้เทสอ้างถึงได้  เทสที่ฮาร์ดโค้ด 1180 ไว้เองจะแดงทุกครั้งที่ขยายหน้าต่าง
-- ซึ่งเป็นเทสที่วัด "ตัวเลขที่พิมพ์ไว้" ไม่ได้วัด "พฤติกรรม"
KRShop.MAX_W, KRShop.MAX_H = W, H

-- ------------------------------------------------------------------------------
-- หน้าในแถบซ้าย
-- ------------------------------------------------------------------------------
-- ACCOUNT กลับมาเป็น "หน้า" ธรรมดาอีกครั้ง
--
-- รอบก่อนมันเป็นแผงยาวแยกที่เกาะขอบขวาของหน้าต่างนี้ (ไฟล์ KR_UI_Account.lua)
-- ตั้งใจดี: อยากให้เห็นยอดเงินพร้อมกับของที่กำลังเลือก
-- แต่ในเกมจริงมันพังสามชั้นซ้อนกัน
--   1. `self:dock()` โยน "Object none did not have __call metatable set" ทุกเฟรม
--      (890 ครั้งใน console เดียว)  แผงเลยไม่เคยถูกวาดเลยแม้แต่เฟรมเดียว
--   2. แผงที่วาดไม่ออก **ยังกินคลิกอยู่**  เพราะมันยังอยู่ใน UIManager
--      และ onMouseDown ของมัน return true  = คลิกหายไปเฉย ๆ ในบางพื้นที่ของจอ
--   3. ร้านต้องหดความกว้างเพื่อแบ่งที่ให้แผง  แผงไม่โผล่ = ร้านแคบลงฟรี ๆ
--
-- บทเรียน: หน้าต่างที่สองที่ "ต้องเกาะ" หน้าต่างแรกมีจุดพังเยอะกว่าที่ได้คืนมามาก
-- เจ้าของเซิร์ฟสั่งตรง ๆ ว่า "ลง ui ใน shop นั่นแหละ ไม่ต้องแยกละ"  ซึ่งถูกแล้ว
-- ยอดเงินสามสกุลโชว์อยู่บนหัวหน้าต่างตลอดเวลาอยู่แล้ว (drawHead) ข้อดีเดิมจึงไม่ได้หายไป
local PAGES = {
    { id = "account", label = "ACCOUNT", title = "Account" },
    { id = "store",   label = "STORE",   title = "Store"        },
    { id = "market",  label = "MARKET",  title = "Fresh Market" },
    { id = "sale",    label = "SALE",    title = "Flash Sale"   },
    { id = "auction", label = "AUCTION", title = "Auction"      },
    { id = "credit",  label = "CREDIT",  title = "Credit"       },
    -- 0.7.0  กระดานราคาสินค้าโลก  **ดูอย่างเดียว ไม่มีปุ่มซื้อที่ไหนเลย**
    -- ทุกคนเห็น เพราะมันคือกระดาษราคาอ้างอิงสำหรับคนที่ซื้อขายกันเอง
    { id = "board",   label = "PRICES",  title = "World Prices" },
    -- 0.7.0  สถิติเศรษฐกิจ + สกิล  แอดมินเท่านั้น ตามที่เจ้าของเซิร์ฟสั่ง
    { id = "stats",   label = "STATS",   title = "Economy", adminOnly = true },
    { id = "admin",   label = "ADMIN",   title = "Admin",  adminOnly = true },
}

local function data()
    return (KRClient and KRClient.data) or {}
end

-- แอดมินดูจอแบบผู้เล่นธรรมดา
--
-- เจ้าของเซิร์ฟบอกว่าเดี๋ยวมีคนมาเทส  แต่ตัวเองเป็นแอดมิน เลยไม่มีทางเห็นสิ่งที่ผู้เล่นเห็น
-- ธงนี้ทำให้จอทำตัวเหมือนไม่ใช่แอดมิน: ไม่มีแท็บ ADMIN ไม่เห็นของที่ปิดอยู่
-- เป็นค่าฝั่งจอล้วน ๆ  ไม่ได้ถอดสิทธิ์จริง เซิร์ฟยังรู้ว่าเป็นแอดมินอยู่
KRShopUI.asPlayer = false

local function isAdminView()
    return (data().admin == true) and not KRShopUI.asPlayer
end

-- เปิดล็อตประมูลได้ไหม
--
-- สองเหตุผลที่ต่างกันโดยสิ้นเชิงและต้องแยกออกจากกัน
--   แอดมิน  ล็อตของร้าน  เซิร์ฟเสกของตอน Claim ไม่มีใครเสียของ
--   ผู้เล่น  ล็อตของตัวเอง  ของถูกยึดออกจากกระเป๋าตั้งแต่วินาทีที่กด
--
-- ผู้เล่นได้สิทธิ์นี้ก็ต่อเมื่อเซิร์ฟเปิด AuctionPlayerSell เท่านั้น
-- และคำตอบมาจากเซิร์ฟ (data().auctSell) ไม่ใช่จากการเดาฝั่งจอ
local function canOpenLot()
    if isAdminView() then return true end
    if data().admin == true then return false end   -- แอดมินที่กดดูแบบผู้เล่น = ทำตัวเป็นผู้เล่น
    return data().auctSell == true
end

-- หน้าไหนเป็น "ลิสต์ของในร้าน" จริง ๆ
--
-- ช่องค้นหา  ตัวนับ "N of M items"  ชิปสกุล  ชิปเรียง  ล้วนพูดถึงของในแคตตาล็อก
-- หน้าประมูลกับหน้าเงินกู้ไม่ได้อ่านแคตตาล็อกเลยสักบรรทัด
-- แต่ของพวกนี้ถูกวาดทุกหน้ามาตลอด  เจ้าของเซิร์ฟส่งรูปมาแล้วถามว่า
-- "0 of 4 items" บนหน้าประมูลคืออะไร -- คำตอบคือจำนวนของในร้าน ซึ่งไม่เกี่ยวกันเลย
--
-- หน้าจัดการอยู่ในกลุ่มนี้ด้วย  ลิสต์ซ้ายของมันคือ self:rows() ตัวเดียวกับหน้าร้าน
-- ค้นหาและตัวนับจึงมีความหมายจริงที่นั่น
local LIST_PAGES = { store = true, market = true, sale = true, admin = true }
local function isListPage(p)
    return LIST_PAGES[p] == true
end

-- เงินสดเก็บเป็นสตางค์  แปลงเป็นข้อความตอนวาดเท่านั้น
local function money(v)
    return string.format("%.2f", (tonumber(v) or 0) / KR.SUBUNIT)
end

-- basis point -> ข้อความเปอร์เซ็นต์
--
-- เขียนแยกเพราะเครื่องหมาย % ต้องต่อเอง ห้ามใส่ "%%" ลงใน string.format
--
-- Kahlua ของ PZ โยน "invalid option '%' to 'format'" ใส่รูปแบบที่มี %% แล้วทั้งเฟรมตาย
-- สองจุดที่ใช้มันอยู่ในหน้า CREDIT ทั้งคู่ = หน้าเงินกู้ที่รายงานว่า "ว่างเปล่า" มาตลอด
-- (error ใน prerender ไม่ได้ทำให้แค่บรรทัดนั้นหาย มันตัดทุกอย่างที่ยังไม่ได้วาดในเฟรมนั้นทิ้ง)
--
-- %.1f เฉย ๆ ปลอดภัย  KR.fmtPrice ใช้ %.2f มาตลอดและไม่เคยมีปัญหา
-- ตัวที่มีปัญหาคือ %% ตัวเดียว
local function pct(bp)
    return string.format("%.1f", (tonumber(bp) or 0) / 100) .. "%"
end

local function req(cmd, args)
    if KRClient then KRClient.req(cmd, args) end
end

-- ------------------------------------------------------------------------------
-- ยิงคำสั่งซื้อ  ใช้ทั้งแถวที่มีทางจ่ายเดียวและหน้าต่างเลือกทางจ่าย
--
-- ทำไมต้องมีฟังก์ชันแยกแค่เพื่อยิงคำสั่งเดียว
--
-- อาการที่รายงานมาคือ "กดซื้อไม่ติด"  ซึ่งจากฝั่งผู้เล่นแยกไม่ออกเลยว่า
--   ก) คลิกไม่โดนปุ่ม
--   ข) คลิกโดน ส่งไปแล้ว แต่เซิร์ฟเงียบ
--   ค) คลิกโดน เซิร์ฟตอบแล้ว แต่คำตอบไปโผล่หลังหน้าต่าง
-- สามอย่างนี้แก้คนละทางกันหมด แต่หน้าจอเหมือนกันเป๊ะ = ไล่บั๊กไม่ได้เลย
--
-- ป้ายที่ขึ้นทันทีตอนกดตัดข้อ (ก) ออกจากสมการถาวร
-- เห็นป้าย = คลิกโดนแล้ว ปัญหาอยู่ฝั่งเซิร์ฟ  ไม่เห็นป้าย = ปัญหาอยู่ที่ปุ่ม
-- และฝั่งเซิร์ฟก็พิมพ์ทุกคำสั่งซื้อลง console แล้ว สองอันนี้ประกบกันได้พอดี
--
-- ป้ายจะถูกทับด้วยคำตอบจริงจากเซิร์ฟภายในเสี้ยววินาที  ผู้เล่นแทบไม่ทันเห็น
-- ที่เห็นค้างคือตอนเซิร์ฟไม่ตอบ ซึ่งคือตอนที่เราต้องการให้เห็นพอดี
--
-- และ "ค้าง" เฉย ๆ ยังไม่พอ  ป้ายที่ค้างอยู่ยังอ่านได้ว่า "กำลังส่ง" ซึ่งแปลว่า
-- ยังมีความหวัง ทั้งที่จริงจบไปแล้ว  จับเวลาไว้แล้วเปลี่ยนข้อความเองเมื่อครบเวลา
-- (เจ้าของเซิร์ฟรายงานเป๊ะ ๆ ว่า "จบที่ sending order ไม่มีไรต่อ")
KR.ANSWER_MS = 5000

local function sendBuy(entryId, optIdx)
    KRShop.notify(KR.L("กำลังส่งคำสั่งซื้อ...", "Sending your order..."), "info")
    local w = KRShop.instance
    if w then
        w.awaitAt   = getTimestampMs and getTimestampMs() or 0
        w.awaitWhat = KR.L("คำสั่งซื้อ", "your order")
    end
    req(KR.CMD.BUY, { id = entryId, opt = optIdx })
end

local function nowTs()
    return tonumber(data().now) or 0
end

-- ==============================================================================
-- ของที่ร้านจ่ายเป็น "ใบ"   รถ (0.6.11) และสัตว์ (0.6.16)
--
-- ไคลเอนต์ไม่ได้อ่านรายชื่อเอง  เซิร์ฟอ่านจากเกมแล้วส่งมาให้
-- (ดู KR_Cars.lua / KR_Pets.lua)  เหตุผล: เซิร์ฟคือที่เดียวที่รู้ว่าลงม็อดอะไรไว้จริง
-- และเป็นที่เดียวที่คำตอบมีผลกับการเสกของ  ให้จอเดาเองแล้วสองที่จะไม่ตรงกัน
-- ในวันที่ม็อดตัวนั้นอัปเดต
--
-- ขอครั้งเดียวต่อเซสชัน  ขอทุกเฟรมคือยิงแพ็กเก็ตหกสิบครั้งต่อวินาที
--
-- **ทำไมเป็นตารางเดียว ไม่ใช่ carRows กับ petRows แยกกัน**
-- ตอน 0.6.16 เพิ่มสัตว์ ทุกที่ที่เคยถามว่า "นี่รถหรือเปล่า" ต้องกลายเป็นสามทาง
-- ถ้าเขียนเป็น if ทุกจุด เราจะมีจุดตัดสินใจสิบกว่าจุดที่ต้องแก้ให้ครบพร้อมกัน
-- และวันที่แก้ไม่ครบ มันจะพังแค่บางหน้า ซึ่งเป็นบั๊กที่หาที่มายากที่สุด
-- เขียนความต่างไว้เป็น **ข้อมูล** แล้วทุกที่อ่านตารางเดียวกัน
-- ==============================================================================
local SPEC = {
    [KR.KIND.VEHICLE] = {
        kind  = KR.KIND.VEHICLE,
        field = "vehicle",                 -- ชื่อฟิลด์บนตัวรายการและบนบรรทัดในชุด
        store = "cars",                    -- ช่องที่ KRClient เก็บรายชื่อไว้
        asked = "carsAsked",
        cmd   = KR.CMD.CAR_LIST,
        icon  = KR.SLIP_ICON,
        cap   = function() return KR.L("รุ่นรถ", "MODEL") end,
        chip  = function() return KR.L("รถ", "CAR") end,
        col   = function() return U.C.gold end,
        okTxt = function() return KR.L("พบรุ่นนี้ในเซิร์ฟ", "found on this server") end,
        noTxt = function() return KR.L("ไม่พบรุ่นนี้", "not a vehicle here") end,
        unTxt = function() return KR.L("อ่านรายชื่อรถไม่ได้", "model list unavailable") end,
        emTxt = function() return KR.L("ไม่พบรุ่นที่ตรง", "no model matches") end,
        nlTxt = function() return KR.L("เซิร์ฟยังไม่ได้ส่งรายชื่อรถมา",
                                       "the server sent no model list") end,
    },
    [KR.KIND.PET] = {
        kind  = KR.KIND.PET,
        field = "pet",
        store = "pets",
        asked = "petsAsked",
        cmd   = KR.CMD.PET_LIST,
        icon  = KR.PET_SLIP_ICON,
        cap   = function() return KR.L("สัตว์", "ANIMAL") end,
        chip  = function() return KR.L("สัตว์", "PET") end,
        col   = function() return U.C.good end,
        okTxt = function() return KR.L("พบสัตว์นี้ในเซิร์ฟ", "found on this server") end,
        noTxt = function() return KR.L("ไม่พบสัตว์นี้", "not an animal here") end,
        unTxt = function() return KR.L("อ่านรายชื่อสัตว์ไม่ได้", "animal list unavailable") end,
        emTxt = function() return KR.L("ไม่พบสัตว์ที่ตรง", "no animal matches") end,
        nlTxt = function() return KR.L("เซิร์ฟยังไม่ได้ส่งรายชื่อสัตว์มา",
                                       "the server sent no animal list") end,
    },
}

-- ลำดับที่ปุ่มชนิดของบรรทัดในชุดจะวนไป  ITEM -> CAR -> PET -> ITEM
-- เขียนเป็นลิสต์เพราะปุ่มต้องวนตามลำดับที่คนเห็น ซึ่ง pairs ไม่รับประกัน
local SPEC_ORDER = { KR.KIND.VEHICLE, KR.KIND.PET }

-- รูปของ "ตัวที่จะได้จริง"  ตอนนี้มีแค่สัตว์ที่มีรูปรายตัว  (0.6.17)
--
-- รถไม่มีรูปรายรุ่น (มีเป็นร้อยรุ่นและม็อดเพิ่มได้ตลอด) จึงใช้ไอคอนใบรถเหมือนเดิม
-- สัตว์มีไม่กี่ชนิดและเป็นของวานิลลา  รูปรายตัวจึงทำได้จริงและอ่านง่ายกว่ามาก
local function specThingTex(sp, id)
    if sp and sp.kind == KR.KIND.PET then
        local art = KR.petArt(id)
        if art then
            local t = getTexture(KR.petTex(art))
            if t then return t end
        end
    end
    return getTexture(sp and sp.icon or KR.SLIP_ICON)
end

local function specRows(sp)
    local C = KRClient
    if not C or not sp then return {} end
    if C[sp.store] == nil then
        if not C[sp.asked] then
            C[sp.asked] = true
            if C.req then pcall(C.req, sp.cmd, {}) end
        end
        return {}
    end
    return C[sp.store]
end

local function specLabel(sp, id)
    for _, r in ipairs(specRows(sp)) do
        if r.id == id then return r.label or r.id end
    end
    -- ไม่รู้จักก็ตัดหน้าโมดูลออกให้อ่านง่ายขึ้น  รถใช้ "." สัตว์ใช้ ":"
    return tostring(id or ""):gsub("^.*%.", "")
end

-- คืนสามค่า ไม่ใช่สอง  **"ไม่รู้" ไม่ใช่ "ไม่มี"**
--   true  = ของชิ้นนี้มีจริง
--   false = รายชื่ออ่านได้ และของชิ้นนี้ไม่อยู่ในนั้น
--   nil   = อ่านรายชื่อไม่ได้เลย  ห้ามบอกแอดมินว่า "ไม่มี" ในกรณีนี้
local function specKnown(sp, id)
    if type(id) ~= "string" or id == "" then return false end
    local rows = specRows(sp)
    if #rows == 0 then return nil end
    for _, r in ipairs(rows) do
        if r.id == id then return true end
    end
    -- สัตว์เขียนได้สองแบบ  "cow" กับ "cow:angus"  พันธุ์ที่เราไม่รู้จักแต่ชนิดรู้จัก
    -- ยังใช้ได้จริง (เซิร์ฟตัดสินแบบเดียวกันใน S.petKnown)  ตอบ false ที่นี่
    -- ทั้งที่เซิร์ฟจะรับ = ป้ายแดงใต้ช่องที่โกหกแอดมิน
    if sp and sp.kind == KR.KIND.PET then
        local base = tostring(id):match("^([^:]+)")
        if base and base ~= id then
            for _, r in ipairs(rows) do
                if r.id == base then return true end
            end
        end
    end
    return false
end

-- ------------------------------------------------------------------------------
-- รูปไอเทม
--
-- ย้ายขึ้นมาจากตรงลิสต์สินค้า  ไม่ใช่เพราะอยากจัดระเบียบ แต่เพราะจำเป็น
-- เมนูเลือกไอคอนของหน้าประมูล (drawMenus) อยู่ "เหนือ" จุดประกาศเดิม
-- Lua ผูก local ตอนคอมไพล์  โค้ดที่อยู่เหนือบรรทัด `local function itemTex`
-- จะอ่านคำว่า itemTex เป็นตัวแปรโกลบอลที่ยังไม่มีค่า = nil แล้วพังตอนรันเท่านั้น
-- (บทเรียนเดียวกับ tagH ที่คอมเมนต์ไว้บนสุดของไฟล์  เจอมาแล้วสองรอบ)
--
-- โหลด texture ครั้งเดียวแล้วเก็บไว้  getTexture ทุกเฟรมคือการค้นหาไฟล์ทุกเฟรม
-- ------------------------------------------------------------------------------
local iconCache = {}

-- รายการนี้เป็นของที่จ่ายเป็นใบไหม  ถ้าใช่ คืนก้อน SPEC ของมัน ถ้าไม่ คืน nil
--
-- อนุมานจากหมวดเหมือนที่ทั้งม็อดทำ (KR.kindOfCat) ไม่ได้ดูที่ e.kind อย่างเดียว
-- เพราะฟอร์มที่แอดมินกำลังพิมพ์อยู่ยังไม่มี kind — มันจะมีตอนเซิร์ฟบันทึกแล้วเท่านั้น
local function slipSpec(e)
    if not e then return nil end
    local byKind = SPEC[e.kind]
    if byKind then return byKind end
    for _, k in ipairs(SPEC_ORDER) do
        local sp = SPEC[k]
        local v = e[sp.field]
        if v ~= nil and v ~= "" then return sp end
    end
    return SPEC[KR.kindOfCat(e.cat)]
end

local function itemTex(e)
    -- ---- รูปกล่องของชุดมาก่อนทุกอย่าง  (0.6.12) ----------------------------
    -- แอดมินเลือกรูปนี้เอง  ของที่คนเลือกไว้เองต้องชนะของที่เราเดาให้เสมอ
    -- เลือกไว้แล้วแต่ไฟล์หาย = ตกไปใช้ทางเดาต่อข้างล่าง ไม่ใช่ช่องดำ
    if e and e.box and KR.boxKnown(e.box) then
        local t = getTexture(KR.boxTex(e.box))
        if t then return t end
    end

    -- รถกับสัตว์ไม่มีไอเทมให้หยิบไอคอนมา  ของที่ผู้เล่นได้จริงคือ "ใบ" จึงใช้ไอคอนใบ
    -- ช่องเปล่า ๆ ในลิสต์อ่านว่า "ของชิ้นนี้พัง" ไม่ได้อ่านว่า "ของชนิดนี้ไม่มีรูป"
    if e and (e.item == nil or e.item == "") then
        local sp = slipSpec(e)
        if sp then return specThingTex(sp, e[sp.field]) end
    end

    -- ชุดที่ยังไม่ได้เลือกรูปกล่อง  ใช้รูปของชิ้นแรกในชุดไปก่อน
    -- มันคือคำใบ้ที่ถูกต้องเสมอ และดีกว่าช่องว่างในทุกกรณี
    if e and KR.isSet(e) and (e.item == nil or e.item == "") then
        local first = e.set[1]
        if first then
            for _, k in ipairs(SPEC_ORDER) do
                local sp = SPEC[k]
                if first[sp.field] then return specThingTex(sp, first[sp.field]) end
            end
            if first.item then e = { item = first.item } end
        end
    end

    if not e or not e.item then return nil end
    local key = e.item
    if iconCache[key] ~= nil then return iconCache[key] or nil end
    local t = getTexture("Item_" .. tostring(key):gsub("^.*%.", ""))
    if not t then
        local ok, inst = pcall(instanceItem, key)
        if ok and inst and inst.getTexture then
            local ok2, tex = pcall(function() return inst:getTexture() end)
            if ok2 then t = tex end
        end
    end
    iconCache[key] = t or false
    return t
end

-- Base.Bag_ALICEpack -> Bag_ALICEpack
-- ชื่อเต็มยาวจนดันความกว้างเมนูเกินจอ และส่วนหน้า "Base." เหมือนกันหมดจนไม่ได้แยกอะไร
local function shortType(t)
    local s = tostring(t or ""):gsub("^.*%.", "")
    return s
end

-- ------------------------------------------------------------------------------
-- ทะเบียนไอเทมของบิลด์นี้
--
-- ทำไมต้องรื้อ: ของเดิมเป็นลิสต์ชื่อที่ "พิมพ์ไว้ในโค้ด" บวกของในร้าน
-- ชื่อที่พิมพ์ไว้เป็นชื่อยุค B41 หลายตัวที่ B42 ไม่มีแล้ว (Base.WaterBottleFull
-- หายไปตอนรื้อระบบของเหลว  Base.Radio ไม่เคยมีในบิลด์นี้)
-- แอดมินเลือกตัวพวกนั้น แล้วเซิร์ฟตีกลับว่า "ไม่มีไอเทมนี้" แล้วล็อตก็ไม่ถูกสร้าง
-- อาการที่เจ้าของเซิร์ฟเห็นคือ "ตั้งไอคอนอื่นไม่ได้นอกจาก apple" — apple บังเอิญ
-- เป็นตัวเดียวที่มีอยู่จริง เพราะมันมาจากแคตตาล็อกร้านที่ผ่านด่านตรวจมาแล้ว
--
-- ทางแก้ที่ถูกคือ **ห้ามเดาว่าบิลด์นี้มีอะไร ให้ไปถามมัน**
-- getScriptManager():getAllItems() คือทะเบียนตัวจริงของบิลด์ที่กำลังรันอยู่
-- อ่านชื่ออย่างเดียว ไม่ instanceItem สักตัว  (การไล่สร้างทุกไอเทมคือสิ่งที่ทำให้
-- หน้า Items List ของแอดมินพังทั้งหน้าเมื่อมีม็อดที่สคริปต์เสียปนอยู่)
--
-- สร้างครั้งเดียวต่อเซสชัน  รายการไอเทมไม่เปลี่ยนระหว่างเล่น
-- ------------------------------------------------------------------------------
local _itemIndex = nil

local function itemIndex()
    if _itemIndex then return _itemIndex end
    local out = {}

    local sm = getScriptManager and getScriptManager()
    local ok, list = pcall(function() return sm and sm:getAllItems() end)
    if ok and list then
        local okN, n = pcall(function() return list:size() end)
        for i = 0, (okN and n or 0) - 1 do
            local okIt, it = pcall(function() return list:get(i) end)
            if okIt and it then
                local okF, full = pcall(function()
                    return tostring(it:getModuleName()) .. "." .. tostring(it:getName())
                end)
                if okF and full and full ~= "" and not full:find("^nil%.") then
                    local disp = full
                    local okD, dn = pcall(function() return it:getDisplayName() end)
                    if okD and dn and dn ~= "" then disp = tostring(dn) end
                    out[#out + 1] = { t = full, d = disp, l = (disp .. " " .. full):lower() }
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.t < b.t
    end)
    print("[Kuraya] item index built: " .. #out .. " items in this build")
    _itemIndex = out
    return out
end

-- ตัวเดียวจากชื่อเต็ม  ใช้เช็กว่าสิ่งที่เลือกไว้ยังมีอยู่จริงก่อนส่งไปเซิร์ฟ
local function itemKnown(full)
    if type(full) ~= "string" or full == "" then return false end
    local sm = getScriptManager and getScriptManager()
    if not sm then return true end     -- เช็กไม่ได้ = ปล่อยผ่าน เซิร์ฟเป็นด่านจริงอยู่แล้ว
    local ok, found = pcall(function() return sm:FindItem(full) end)
    return (ok and found) and true or false
end

local function itemDisplay(full)
    for _, r in ipairs(itemIndex()) do
        if r.t == full then return r.d end
    end
    return tostring(full or ""):gsub("^.*%.", "")
end


-- ------------------------------------------------------------------------------
-- สร้าง / เปิด-ปิด
-- ------------------------------------------------------------------------------
-- ความกว้างที่ร้านควรเป็นบนจอนี้
--
-- ไม่ต้องเผื่อที่ให้แผงข้างอีกแล้ว (ดูคอมเมนต์ตรง PAGES)  ร้านกินเต็มที่ที่มี
-- ยังคงชื่อเดิมไว้เพื่อไม่ให้โค้ด/เทสเดิมพัง  พารามิเตอร์ถูกละเลยโดยตั้งใจ
function KRShop.fitWidth()
    local room = getCore():getScreenWidth() - 20
    return math.max(320, math.min(W, room))
end

-- ความสูงที่ร้านควรเป็นบนจอนี้  คู่กับ fitWidth
--
-- เคยเป็นบรรทัดเดียวฝังอยู่ใน :new() ซึ่งแปลว่าหน้าต่างที่เปิดค้างไว้ตอนผู้เล่น
-- เปลี่ยนความละเอียดจอจะสูงเท่าเดิมตลอด  ย้ายออกมาให้ relayout() เรียกได้ด้วย
function KRShop.fitHeight()
    local room = getCore():getScreenHeight() - 20
    return math.max(420, math.min(H, room))
end

-- จัดตำแหน่งร้านใหม่หลังขนาดจอเปลี่ยน  วางกลางจอ
function KRShop:relayout()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h   = KRShop.fitWidth(), KRShop.fitHeight()
    self:setWidth(w)
    self:setHeight(h)
    local x = math.floor((sw - w) / 2)
    if x < 10 then x = 10 end
    self:setX(x)
    local y = math.floor((sh - h) / 2)
    if y < 10 then y = 10 end
    self:setY(y)
end

function KRShop:new()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    -- จอเล็กกว่าหน้าต่างก็ต้องเปิดได้  ย่อลงแทนที่จะล้นออกนอกจอ
    local w = KRShop.fitWidth()
    local h = KRShop.fitHeight()
    local o = ISPanel.new(self, math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
    o.background      = false
    o.moveWithMouse   = true
    o.page      = "store"
    o.scroll    = 0
    o.hoverRow  = -1
    o.sortOpen  = false
    o.curOpen   = false
    o.catScroll = 0        -- แถบหมวดเลื่อนไปแล้วกี่พิกเซล
    o.pay       = nil       -- ตัวเลือกการจ่ายที่กำลังเปิดอยู่  { entry, opts, sel }
    o.mx, o.my  = -1, -1
    o.btns      = {}        -- ปุ่มที่วาดรอบล่าสุด  onMouseUp เอาไปเทียบ
    return o
end

function KRShop:initialise()
    ISPanel.initialise(self)
end

function KRShop:createChildren()
    ISPanel.createChildren(self)
    local x = U.NAV + U.PAD
    local y = U.TITL + U.HEAD + 4
    self.search = ISTextEntryBox:new("", x, y, 260, 30)
    self.search:initialise()
    self.search:instantiate()
    self.search.onTextChange = function() self.scroll = 0 end
    self:addChild(self.search)

    -- ช่องกรอกของหน้าจัดการ  สร้างไว้ครั้งเดียว แล้วย้ายตำแหน่ง/ซ่อนตามแท็บ
    self.fields = {}
    for _, k in ipairs({ "name","item","cat","stock","quota","salePct","saleHrs",
                         "count",
                         "a1","a2","a3","a4","b1","b2","b3","b4",
                         "stallName","grantTo","grantAmt","grantWhy",
                         "sendAmt",
                         -- ค้นชื่อในลิสต์ "โอนให้ใคร"  (0.6.23)
                         -- ช่องของตัวเอง ไม่ยืม whoFind เหตุผลเดียวกับ peopleFind:
                         -- whoFind เป็นดร็อปดาวน์ที่เลือกแล้วปิด  อันนี้ต้องค้างค่าไว้
                         -- กรองลิสต์อยู่ตลอดเวลาที่ฟอร์มโอนเปิดอยู่
                         "sendFind",
                         -- กระดานราคาโลก  (0.7.0)
                         "bdName", "bdCat", "bdPrice", "bdNote", "bdFind",
                         -- ตัวเลือกไอเทมของล็อตประมูล  ช่องค้นหา + จำนวนชิ้น
                         "itemFind", "auctCount", "auctStep", "auctBuy",
                         -- ใส่ราคาบิดเองในหน้ารายละเอียดล็อต
                         "auctBid",
                         -- แพ็ก HF  ฟอร์มของแอดมิน
                         "hfpName","hfpHf","hfpBonus","hfpThb","hfpCut",
                         "hfpMins","hfpCutMins","hfpStock","hfpPer",
                         "hfpTo","hfpAmt","hfpWhy","hfpNote",
                         -- ช่องพิมพ์-เลือกชื่อผู้เล่น  ใช้ร่วมกันทุกที่ที่ต้องเลือกคน
                         "whoFind",
                         -- ค้นชื่อในรายชื่อผู้เล่นของแอดมิน  (0.6.16)
                         -- ใช้ช่องของตัวเอง ไม่ยืม whoFind  เพราะ whoFind เป็น
                         -- ตัวเลือกคนแบบดร็อปดาวน์ที่ "เลือกแล้วปิด"  ส่วนอันนี้
                         -- ต้องค้างค่าไว้ให้ลิสต์กรองอยู่ตลอดเวลาที่แอดมินเปิดแท็บนี้
                         "peopleFind",
                         -- ของในชุด  หนึ่งบรรทัดสองช่อง (ของ / จำนวน)  (0.6.14)
                         -- สร้างครบแปดบรรทัดตั้งแต่ต้นแล้วซ่อนอันที่ยังไม่ใช้
                         -- สร้างเพิ่มระหว่างวาดไม่ได้ เพราะนั่นคือการแก้ลิสต์ลูก
                         -- ระหว่างที่ PZ กำลังเดินลิสต์นั้นอยู่
                         "setI1","setI2","setI3","setI4","setI5","setI6","setI7","setI8",
                         "setN1","setN2","setN3","setN4","setN5","setN6","setN7","setN8" }) do
        local box = ISTextEntryBox:new("", 0, 0, 60, 20)
        box:initialise(); box:instantiate()
        box:setVisible(false)
        -- ติดชื่อไว้กับตัวกล่องเลย  ตอนไล่ทั้งตารางเราวนด้วย pairs ซึ่งไม่ให้คีย์กลับมา
        -- ในบริบทที่ต้องตัดสินเป็นรายกล่อง (0.6.13 — แผ่นตัวจัดของในชุดยืมสองกล่องไปใช้)
        box.__krName = k
        self.fields[k] = box
        self:addChild(box)
    end

    -- พิมพ์ค้นแล้วลิสต์สั้นลง  ถ้าไม่รีเซ็ตการเลื่อน จอจะว่างทั้งที่มีผลค้นอยู่
    -- (เลื่อนลงไปคนที่ 40 แล้วพิมพ์จนเหลือ 3 คน = เห็นช่องว่าง)
    if self.fields.peopleFind then
        self.fields.peopleFind.onTextChange = function() self.scroll = 0 end
    end
    -- เหตุผลเดียวกันกับ peopleFind  พิมพ์ต่อ = ผลค้นเป็นคนละชุด ต้องเด้งกลับบรรทัดแรก
    if self.fields.sendFind then
        self.fields.sendFind.onTextChange = function() self.sendScroll = 0 end
    end
end

function KRShopUI.toggle()
    if KRShop.instance then
        KRShop.instance:close()
        return
    end
    local w = KRShop:new()
    w:initialise(); w:instantiate()
    w:addToUIManager()
    KRShop.instance = w
    pcall(function() w:relayout() end)
    req(KR.CMD.REQ_SYNC)
end

function KRShopUI.close()
    if KRShop.instance then KRShop.instance:close() end
end

function KRShop:close()
    self:removeFromUIManager()
    KRShop.instance = nil
end

function KRShop:refresh()
    -- เซิร์ฟเวอร์ส่งข้อมูลใหม่มา  ไม่ต้องทำอะไรมาก เพราะเราอ่านจาก KRClient.data ตอนวาดอยู่แล้ว
    self.scroll = math.max(0, self.scroll)
end

-- ------------------------------------------------------------------------------
-- เตรียมแถวของแต่ละหน้า
-- ------------------------------------------------------------------------------
local function passSearch(e, q)
    return KR.matches(e, q)
end

function KRShop:rows()
    local d  = data()
    local q  = self.search and self.search:getInternalText() or ""
    local ts = nowTs()
    local cur = (KRClient and KRClient.filterCur) or "all"
    local out = {}

    for id, e in pairs(d.catalog or {}) do
        e.id = e.id or id
        local adminPage = (self.page == "admin") and isAdminView()
        -- หมวดที่ผู้เล่นเลือกอยู่  หน้าจัดการไม่กรอง แอดมินต้องเห็นทุกอย่าง
        local wantCat = (KRClient and KRClient.filterCat) or KR.CAT_ALL
        local catOk = adminPage or wantCat == KR.CAT_ALL or KR.catKey(e.cat) == wantCat

        local keep = (adminPage or e.enabled ~= false) and passSearch(e, q) and catOk
                     and (adminPage or KR.acceptsCurrency(e, cur))

        if keep then
            if self.page == "sale" then
                keep = KR.saleActive(e, ts)
            elseif self.page == "market" then
                keep = e.market ~= nil
            elseif self.page == "admin" then
                keep = true                     -- แอดมินเห็นทุกอย่าง รวมของที่ปิดอยู่
            elseif self.page == "store" then
                keep = e.market == nil          -- ของตลาดสดมีหน้าของตัวเอง ไม่ปนกับร้านหลัก
            else
                keep = false
            end
        end

        if keep then out[#out + 1] = e end
    end

    local mode = (KRClient and KRClient.sortMode) or KR.SORT_DEFAULT
    if self.page == "sale" and not (KRClient and KRClient.sortMode) then
        mode = KR.SORT.DISCOUNT          -- หน้าลดราคาเริ่มที่ "ลดเยอะสุด" ถ้าผู้เล่นยังไม่ได้เลือกเอง
    end
    KR.sortList(out, mode, ts)
    return out
end

-- ------------------------------------------------------------------------------
-- วาด : แถบซ้าย
-- ------------------------------------------------------------------------------
function KRShop:drawNav(h)
    U.fill(self, 0, U.TITL, U.NAV, h - U.TITL, U.C.bgDark)

    local d   = data()
    local y   = U.TITL + 6
    local ih  = 62
    self.navBtns = {}

    for i = 1, #PAGES do
        local pg  = PAGES[i]
        -- หน้าที่ยังไม่เปิดใช้ยังอยู่ในแถบ  ไม่ได้ซ่อน
        -- ผู้เล่นควรรู้ว่ามีของกำลังจะมา ดีกว่าให้มันโผล่มาเฉย ๆ วันหนึ่ง
        local soon = (pg.id == "auction") and not KR.auctionOpen()
        if not (pg.adminOnly and not isAdminView()) then
        local on  = (self.page == pg.id)
        local hot = self.mx >= 0 and self.mx < U.NAV and self.my >= y and self.my < y + ih

        if on then
            U.fill(self, 0, y, U.NAV, ih, U.C.bgRow)
            U.fill(self, 0, y, 2, ih, U.C.accent)
        elseif hot then
            U.fill(self, 0, y, U.NAV, ih, U.C.bg, 0.5)
        end

        -- ไอคอน  ยังเป็นบล็อกสีจนกว่าจะมีอาร์ตจริงของแต่ละหน้า
        -- ไอคอนใช้สีประจำหน้าของตัวเอง ไม่ใช่สีของหน้าที่เปิดอยู่
        -- แถบซ้ายจึงกลายเป็นแถบสีที่จำตำแหน่งได้ ไม่ใช่รายการที่ต้องอ่านทุกครั้ง
        local ix = math.floor(U.NAV / 2 - 16)
        local pcol = U.pageColor(pg.id)
        U.fill(self, ix, y + 8, 32, 32, on and U.C.accent2 or U.C.bgCard)
        U.navIcon(self, pg.id, ix, y + 8, 32,
                  on and U.C.text or (hot and pcol or U.dimC(pcol)))

        U.textC(self, pg.label, U.NAV / 2, y + 42,
                soon and U.C.dim or (on and U.C.text or U.C.mute), U.F.xs)
        if soon then
            U.textC(self, KR.L("เร็ว ๆ นี้", "soon"), U.NAV / 2, y + 42 + U.h(U.F.xs),
                    U.C.dim, U.F.xs)
        end

        -- จุดแจ้งเตือน
        if pg.id == "sale" and (KRClient and (KRClient.saleCount or 0) > 0) then
            -- ป้ายแดงมุมขวาบนพร้อมจำนวน  จุดเล็ก ๆ มองข้ามง่ายเกินไป
            local n2  = KRClient.saleCount or 0
            local lbl = (n2 > 9) and "9+" or tostring(n2)
            local bw3 = U.w(lbl, U.F.xs) + 8
            U.fill(self, U.NAV - bw3 - 4, y + 6, bw3, U.h(U.F.xs) + 4, U.C.bad)
            U.textC(self, lbl, U.NAV - bw3 / 2 - 4, y + 8, U.C.bgDark, U.F.xs)
        elseif pg.id == "market" and d.atMarket then
            U.fill(self, U.NAV - 18, y + 10, 6, 6, U.C.good)
        end

        self.navBtns[#self.navBtns + 1] = { x = 0, y = y, w = U.NAV, h = ih, page = pg.id }
        y = y + ih
        end
    end

    -- ท้ายแถบ  บอกว่าธนาคารกับ Town Rank ติดต่อได้ไหม
    -- ถ้าอันใดอันหนึ่งหลุด ราคาบางสกุลจะซื้อไม่ได้ ผู้เล่นควรรู้ก่อนกด
    local by = h - U.STAT - 44

    -- แอดมินได้คำตอบละเอียดกว่า  "BANK OK" ไม่พอเวลาไล่บั๊ก "กดซื้อแล้วเงินไม่หัก"
    --
    -- d.bank มาจาก S.bankCaps() ฝั่งเซิร์ฟ และถูกส่งให้เฉพาะแอดมิน
    -- สามสถานะที่ความหมายคนละเรื่องกันเลย  ของเดิมยุบเหลือสองจนแยกไม่ออก
    --   ไม่มี Akacount        ราคาเงินสดตายทั้งเซิร์ฟ
    --   มีแต่ไม่มี escrow      ยังขายได้ผ่านทางสำรอง  แต่ควรรู้ตัวว่าเดินทางไหนอยู่
    --   มีครบ                 ปกติ
    local bankTxt, bankCol = "BANK OFF", U.C.bad
    if d.bankOk then
        bankTxt, bankCol = "BANK OK", U.C.good
        if d.bank and d.bank.core == false then
            bankTxt, bankCol = "BANK BROKEN", U.C.bad
        elseif d.bank and d.bank.escrow == false then
            bankTxt, bankCol = "BANK OK*", U.C.warn      -- * = ไม่มี escrow ใช้ทางสำรอง
        end
    end
    U.text(self, bankTxt, 10, by, bankCol, U.F.xs)
    U.text(self, d.trOk and "RANK OK" or "RANK OFF", 10, by + U.h(U.F.xs) + 4,
           d.trOk and U.C.good or U.C.bad, U.F.xs)

    -- ปุ่มสลับมุมมองถูกถอดออกใน 0.6.0
    --
    -- เจ้าของเซิร์ฟสั่งตรง ๆ ว่า "แบ่งแยกการเปิดเมนูสำหรับ user admin อัตโนมัติ
    -- ไม่เอาปุ่มสลับโหมด"  ซึ่งถูกด้วยเหตุผลที่ลึกกว่าความชอบ:
    --
    -- สวิตช์ที่ค้างสถานะไว้ข้ามเซสชันคือสวิตช์ที่ผู้ใช้ลืมว่าตัวเองกดไว้
    -- แอดมินที่กด AS PLAYER ไว้เมื่อวานแล้วเปิดร้านวันนี้จะไม่เห็นแท็บ ADMIN
    -- อาการที่เขาเห็นคือ "ม็อดพัง หน้าแอดมินหายไปแล้ว" ไม่ใช่ "ฉันกดสวิตช์ไว้"
    -- และปุ่มนี้ก็ไม่เคยให้สิทธิ์อะไรเลย มันแค่ซ่อนเมนู  ด่านจริงอยู่ที่ ADMIN_ONLY
    -- ฝั่งเซิร์ฟมาตลอด  การถอดออกจึงไม่ทำให้อะไรหลวมลงแม้แต่นิดเดียว
    --
    -- ความสามารถ "ดูว่าผู้เล่นเห็นอะไร" ยังอยู่ แต่ย้ายไปเป็นปุ่มพรีวิวชั่วคราว
    -- ในหน้าแอดมิน และมีแถบเตือนคาหัวจอตลอดเวลาที่พรีวิวอยู่ (ดู drawPreviewBar)
    -- ต่างกันตรงที่แบบใหม่ **บอกสถานะตัวเองตลอดเวลา** แบบเก่าไม่เคยบอก
end

-- ------------------------------------------------------------------------------
-- วาด : หัวเรื่อง + ยอดสามสกุล
-- ------------------------------------------------------------------------------
local function fmtNum(cur, v)
    if cur == KR.CUR.CASH then
        return string.format("%.2f", (tonumber(v) or 0) / KR.SUBUNIT)
    end
    return tostring(math.floor(tonumber(v) or 0))
end

function KRShop:drawHead(w)
    local d = data()
    U.fill(self, U.NAV, U.TITL, w - U.NAV, U.HEAD, U.C.bgHead)

    local title = "Kuraya"
    for i = 1, #PAGES do if PAGES[i].id == self.page then title = PAGES[i].title end end
    U.text(self, title, U.NAV + U.PAD, U.TITL + math.floor((U.HEAD - U.h(U.F.l)) / 2),
           U.C.text, U.F.l)

    -- ยอดเงิน  ไล่จากขวาไปซ้าย จะได้ไม่ต้องคำนวณความกว้างรวมล่วงหน้า
    --
    -- ลำดับที่วาดคือ CASH -> CP -> HF  แต่วาดจากขวาไปซ้าย ผลบนจอจึงเป็น HF CP CASH
    -- HF อยู่ซ้ายสุดโดยตั้งใจ เพราะปุ่มเติมเกาะอยู่กับมันและต้องไม่ไปชนขอบขวา
    local bal = d.bal or {}
    local x   = w - U.PAD
    local ty  = U.TITL + math.floor((U.HEAD - U.h(U.F.m)) / 2)
    self.bHfTop = nil

    for _, cur in ipairs({ KR.CUR.CASH, KR.CUR.CP, KR.CUR.HF }) do
        local s = fmtNum(cur, bal[cur])
        U.textR(self, s, x, ty, U.curCol(cur), U.F.m)
        x = x - U.w(s, U.F.m) - 8
        U.coin(self, cur, x - 18, ty + 3, 18)
        x = x - 18 - 20

        -- --------------------------------------------------------------------
        -- ปุ่มเติม HF  เกาะซ้ายของเหรียญ HF
        --
        -- เจ้าของเซิร์ฟสั่งว่า "หน้าแพ็กเกจจะมาจากปุ่ม + ข้างๆ ไอคอน HF point ข้างบน"
        -- วางบนแถบหัวแทนที่จะเป็นหน้าใหม่ในแถบซ้าย เพราะแถบหัวอยู่ทุกหน้า
        -- คนที่รู้ตัวว่า HF ไม่พอมักรู้ตอนกำลังยืนอยู่หน้าของที่อยากซื้อ
        -- ไม่ใช่ตอนที่ตั้งใจเดินไปหน้าเติมเงิน
        --
        -- ป้ายแดงบนปุ่มคือจำนวนคำขอที่ยังรออยู่ของ **ตัวเอง**
        -- ไม่ใช่ของทั้งเซิร์ฟ  ผู้เล่นต้องเห็นว่าใบที่ตัวเองส่งไปยังไม่มีใครกด
        -- --------------------------------------------------------------------
        if cur == KR.CUR.HF then
            local bw2 = 22
            local bh2 = 22
            local bx2 = x - bw2 + 12
            local by2 = ty + math.floor((U.h(U.F.m) - bh2) / 2)
            local hot = U.hit({ x = bx2, y = by2, w = bw2, h = bh2 }, self.mx, self.my)
            U.fill(self, bx2, by2, bw2, bh2, hot and U.C.accent or U.C.accent2)
            U.border(self, bx2, by2, bw2, bh2, U.C.accent)
            U.textC(self, "+", bx2 + bw2 / 2, by2 + math.floor((bh2 - U.h(U.F.m)) / 2),
                    U.C.text, U.F.m)
            self.bHfTop = { x = bx2, y = by2, w = bw2, h = bh2 }

            local mine = ((d.hfp or {}).mine) or {}
            local nWait = 0
            for _, r in ipairs(mine) do
                if r.st == KR.HFP_ST.WAIT then nWait = nWait + 1 end
            end
            if nWait > 0 then
                local lbl = tostring(nWait)
                local pw  = U.w(lbl, U.F.xs) + 6
                U.fill(self, bx2 + bw2 - pw + 2, by2 - 5, pw, U.h(U.F.xs) + 2, U.C.warn)
                U.textC(self, lbl, bx2 + bw2 - pw / 2 + 2, by2 - 5, U.C.bgDark, U.F.xs)
            end
            x = x - bw2 - 6
        end
    end
end

-- ------------------------------------------------------------------------------
-- แถบเตือนตอนแอดมินกำลังดูมุมผู้เล่น
--
-- นี่คือสิ่งที่ปุ่ม AS PLAYER แบบเดิมไม่เคยมี และเป็นสาเหตุที่มันต้องถูกถอด
-- โหมดที่เปลี่ยนสิ่งที่คุณเห็นแต่ไม่บอกว่าตัวเองเปิดอยู่ คือโหมดที่จะถูกลืมค้างไว้
--
-- แถบนี้กินความกว้างเต็มจอ นั่งอยู่เหนือแถบสถานะ และตัวมันเองคือปุ่มออก
-- ไม่มีทางที่แอดมินจะพรีวิวค้างไว้โดยไม่รู้ตัว เพราะมันอยู่ในสายตาทุกเฟรม
--
-- วางล่างแทนที่จะวางบนเพราะแถบบนมีปุ่มปิดกับปุ่มคู่มืออยู่แล้ว
-- แถบที่ไปทับปุ่มปิดคือแถบที่ทำให้ปิดหน้าต่างไม่ได้ ซึ่งแย่กว่าปัญหาที่มันมาแก้
-- คืนความสูงของตัวเองออกไป  prerender เอาไปหักออกจากพื้นที่เนื้อหา
-- ------------------------------------------------------------------------------
function KRShop:drawPreviewBar(w, h)
    self.bPreviewOff = nil
    if not (data().admin == true and KRShopUI.asPlayer) then return 0 end

    local bh2 = U.h(U.F.s) + 10
    local by2 = h - U.STAT - bh2
    U.fill(self, 0, by2, w, bh2, U.C.warn)
    U.textC(self, KR.L("กำลังดูมุมผู้เล่นอยู่  ·  กดตรงนี้เพื่อกลับเป็นแอดมิน",
                       "PLAYER PREVIEW  ·  click here to go back to admin"),
            w / 2, by2 + 5, U.C.bgDark, U.F.s)
    self.bPreviewOff = { x = 0, y = by2, w = w, h = bh2 }
    return bh2
end

-- ------------------------------------------------------------------------------
-- วาด : แถบค้นหา / กรอง / เรียง
-- ------------------------------------------------------------------------------
local function chip(p, x, y, cap, val, active, mx, my)
    local wCap = U.w(cap, U.F.s)
    local wVal = U.w(val, U.F.s)
    local w    = wCap + wVal + 34
    local h    = 30
    U.fill(p, x, y, w, h, active and U.C.accent2 or U.C.bgCard)
    local ty = y + math.floor((h - U.h(U.F.s)) / 2)
    U.text(p, cap, x + 10, ty, active and U.C.text or U.C.dim, U.F.s)
    U.text(p, val, x + 10 + wCap + 6, ty, active and U.C.text or U.C.lite, U.F.s)
    U.text(p, "v", x + w - 14, ty, active and U.C.accent or U.C.mute, U.F.xs)
    return { x = x, y = y, w = w, h = h }
end

-- คู่ภาษา  แปลตอนวาดเท่านั้น  ตอนโหลดไฟล์ getTextManager() ยังไม่พร้อม
local CUR_LABEL = {
    all  = { "ทั้งหมด", "All"  },
    cash = { "เงินสด",  "Cash" },
    hf   = { "HF", "HF" },
    cp   = { "CP", "CP" },
}
local function curLabel(k)
    local p = CUR_LABEL[k or "all"] or CUR_LABEL.all
    return KR.L(p[1], p[2])
end

function KRShop:drawTool(w, nRows, nAll)
    -- หน้าที่ไม่ใช่ลิสต์ของ ไม่มีอะไรในแถบนี้ที่จริงสำหรับมันเลย
    --
    -- ต้องล้าง bSort/bCur ทิ้งด้วย ไม่ใช่แค่ "ไม่วาด"
    -- onMouseUp เทียบพิกัดจากตัวแปรสองตัวนี้โดยตรง  ปล่อยค่าเก่าไว้ = ชิปที่มองไม่เห็น
    -- ยังกินคลิกอยู่ตรงมุมขวาบนของหน้าประมูล แล้วเมนูเรียงจะเด้งขึ้นมาบนหน้าที่ไม่มีลิสต์
    if not isListPage(self.page) then
        self.bSort, self.bCur       = nil, nil
        self.sortOpen, self.curOpen = false, false
        return
    end

    local y = U.TITL + U.HEAD + 4
    U.text(self, nRows .. " of " .. nAll .. " items",
           U.NAV + U.PAD + 274, y + 8, U.C.off, U.F.s)

    local C = KRClient or {}
    local sortLabel = KR.sortLabel(C.sortMode or KR.SORT_DEFAULT)

    local sx = w - U.PAD
    local sw = U.w(sortLabel, U.F.s) + U.w(KR.L("เรียง", "Sort"), U.F.s) + 30
    self.bSort = chip(self, sx - sw, y, KR.L("เรียง", "Sort"), sortLabel, self.sortOpen, self.mx, self.my)

    local cl = curLabel(C.filterCur)
    local cw = U.w(cl, U.F.s) + U.w(KR.L("สกุล", "Currency"), U.F.s) + 30
    self.bCur = chip(self, sx - sw - cw - U.GAP, y, KR.L("สกุล", "Currency"), cl,
                     self.curOpen or (C.filterCur and C.filterCur ~= "all"), self.mx, self.my)
end

-- ------------------------------------------------------------------------------
-- แถบหมวด
--
-- อยู่เหนือลิสต์  กดแล้วกรองทันที และเซิร์ฟจำไว้ว่าดูหมวดไหนอยู่
-- ชื่อหมวดมาจากของที่แอดมินลงจริง ๆ ไม่ได้ประกาศไว้ในโค้ด
--
-- หมวดเยอะเกินความกว้าง = มีลูกศรสองข้างให้เลื่อน
-- ไม่ตัดขึ้นบรรทัดที่สอง เพราะแถวที่สองจะดันลิสต์ลงจนเสียที่ไปเปล่า ๆ
-- ------------------------------------------------------------------------------
function KRShop:catBarH()
    local d = data()
    if #(d.cats or {}) == 0 then return 0 end
    return tagH() + 10
end

function KRShop:drawCatBar(x, y, w)
    local d    = data()
    local cats = d.cats or {}
    self.catBtns = {}
    if #cats == 0 then return end

    local cur = (KRClient and KRClient.filterCat) or KR.CAT_ALL
    local hh  = tagH()

    local items = { { id = KR.CAT_ALL, label = KR.L("ทั้งหมด", "All") } }
    for i = 1, #cats do
        items[#items + 1] = { id = cats[i].id,
                              label = tostring(cats[i].id) .. "  " .. tostring(cats[i].n) }
    end

    local total = 0
    for i = 1, #items do
        items[i].w = U.w(items[i].label, U.F.s) + 24
        total = total + items[i].w + 6
    end

    local arrowW    = 22
    local needArrow = total > w
    local viewX = x + (needArrow and (arrowW + 4) or 0)
    local viewW = w - (needArrow and (arrowW + 4) * 2 or 0)

    if needArrow then
        local maxScroll = math.max(0, total - viewW)
        if self.catScroll > maxScroll then self.catScroll = maxScroll end
        if self.catScroll < 0 then self.catScroll = 0 end

        local bl = U.btn(self, x, y, arrowW, hh, "<",
                         self.catScroll > 0 and "neu" or "offb", self.mx, self.my)
        bl.act = "catleft"
        if self.catScroll > 0 then self.catBtns[#self.catBtns + 1] = bl end

        local br = U.btn(self, x + w - arrowW, y, arrowW, hh, ">",
                         self.catScroll < maxScroll and "neu" or "offb", self.mx, self.my)
        br.act = "catright"
        if self.catScroll < maxScroll then self.catBtns[#self.catBtns + 1] = br end
    else
        self.catScroll = 0
    end

    self:setStencilRect(viewX, y, viewW, hh)
    local cx = viewX - self.catScroll
    for i = 1, #items do
        local it = items[i]
        local on = (cur == it.id)
        if cx + it.w > viewX and cx < viewX + viewW then
            local hot = U.hit({ x = cx, y = y, w = it.w, h = hh }, self.mx, self.my)
            U.fill(self, cx, y, it.w, hh, on and U.C.accent2 or (hot and U.C.bgRow or U.C.bgCard))
            if on then U.fill(self, cx, y + hh - 2, it.w, 2, U.C.accent) end
            U.textC(self, it.label, cx + it.w / 2, y + 6, on and U.C.text or U.C.mute, U.F.s)
            self.catBtns[#self.catBtns + 1] = { x = cx, y = y, w = it.w, h = hh,
                                                act = "cat", cat = it.id }
        end
        cx = cx + it.w + 6
    end
    self:clearStencilRect()
end

-- เมนูดร็อปดาวน์  วาดทีหลังสุดเสมอ ไม่งั้นแถวข้างล่างจะทับ
function KRShop:drawMenus()
    self.menuBtns = {}
    -- กรอบของเมนูที่เปิดอยู่  ด่านสุดท้ายของเฟรมใช้ตัวนี้สั่งซ่อนช่องกรอกที่โดนทับ
    --
    -- 0.6.13 — เจ้าของเซิร์ฟรายงาน "ตรง category มันบัคๆ กดแล้วไปกดช่องอื่น"
    -- ต้นเหตุคือกับดักเดิมของม็อดนี้: ISTextEntryBox เป็นลูกจริงของ PZ
    -- มันวาดทับสิ่งที่เราวาด **และกินคลิกก่อนเราเสมอ**
    -- เมนูหมวดกางลงมาทับช่อง PER BUY / VISIBLE พอดี คลิกที่ตั้งใจเลือกหมวด
    -- จึงไปตกที่ช่องข้างหลังแทน
    --
    -- ที่อื่นในม็อดแก้ด้วยการซ่อนช่องทั้งหมดตอนมีแผ่นทับ แต่เมนูนี้เล็ก
    -- ซ่อนทั้งฟอร์มเพื่อเมนูหกบรรทัดคือการรักษาที่แรงเกินโรค  ซ่อนเฉพาะช่องที่โดนทับพอ
    local function menu(anchor, items, curVal, onPick)
        local wmax = 60
        for i = 1, #items do wmax = math.max(wmax, U.w(items[i].label, U.F.s) + 40) end
        local ih = 24
        local x  = anchor.x + anchor.w - wmax
        local y  = anchor.y + anchor.h + 2
        local h  = #items * ih + 8

        self:cover(x, y, wmax, h)
        U.solid(self, x, y, wmax, h, U.C.bgSel)
        U.border(self, x, y, wmax, h, U.C.line3)

        for i = 1, #items do
            local iy  = y + 4 + (i - 1) * ih
            local sel = items[i].value == curVal
            local hot = U.hit({ x = x, y = iy, w = wmax, h = ih }, self.mx, self.my)
            if sel then U.fill(self, x, iy, wmax, ih, U.C.accent2)
            elseif hot then U.fill(self, x, iy, wmax, ih, U.C.bgRow) end
            if sel then U.text(self, "-", x + 8, iy + 5, U.C.accent, U.F.s) end
            U.text(self, items[i].label, x + 20, iy + 5,
                   sel and U.C.text or U.C.lite, U.F.s)
            self.menuBtns[#self.menuBtns + 1] =
                { x = x, y = iy, w = wmax, h = ih, fn = onPick, value = items[i].value }
        end
    end

    -- เมนูหมวดของหน้าจัดการ  วางตำแหน่งเองเพราะมันไม่ได้ผูกกับ chip ด้านบน
    if self.catMenu then
        local m = self.catMenu
        local items = {}
        for i = 1, math.min(#m.items, 12) do
            items[#items + 1] = { label = tostring(m.items[i]), value = m.items[i] }
        end
        if #items > 0 then
            menu({ x = m.x, y = m.y - tagH() - 2, w = 104, h = tagH() }, items,
                 self.fields.cat and self.fields.cat:getInternalText() or "",
                 function(v)
                     if self.fields.cat then self.fields.cat:setText(tostring(v)) end
                     self.catMenu = nil
                 end)
        else
            self.catMenu = nil
        end
    end

    -- เมนูเลือกไอคอนของล็อตประมูล
    --
    -- ไม่ใช้ menu() ตัวบนเพราะแถวต้องมี "รูป" ไม่ใช่แค่ตัวหนังสือ
    -- ชื่อชนิดอย่าง Bag_ALICEpack ไม่ได้บอกอะไรกับตาเลย แต่รูปเป้บอกทันที
    -- และเมนูนี้ยาวกว่าเมนูอื่นมาก (ของในร้านทุกชิ้น) จึงต้องเลื่อนได้
    --
    -- ยังเก็บปุ่มลง self.menuBtns ชุดเดิม  onMouseUp จึงไม่ต้องรู้ว่ามีเมนูสองแบบ
    -- และยังถูกปิดด้วยกฎ "คลิกที่ว่าง = ปิดเมนู" ที่มีอยู่แล้วโดยไม่ต้องแก้อะไร
    --
    -- ปิดเองเมื่อสิ่งที่มันเกาะอยู่หายไป  เมนูวาดทีหลังสุดเสมอ ถ้าไม่เก็บมันจะไปลอยทับหน้าอื่น
    -- โดยที่ผู้เล่นหาปุ่มที่เปิดมันไม่เจอแล้ว (drawMenus ถูกเรียกทุกหน้า ไม่ใช่เฉพาะหน้าประมูล)
    if self.auctMenu and not (self.page == "auction" and self.auctNew) then
        self.auctMenu = nil
    end

    -- ช่องค้นหาเป็นลูกจริงของหน้าต่าง  ปิดเมนูแล้วต้องซ่อน "และ" ปล่อยโฟกัสด้วย
    -- กล่องที่ยังถือโฟกัสอยู่กินคีย์บอร์ดต่อแม้มองไม่เห็น ผู้เล่นจะกดเดินไม่ได้
    -- แล้วไม่มีอะไรบนจอบอกได้ว่าเพราะอะไร (บทเรียนเดียวกับ self.search)
    if not self.auctMenu and self.fields and self.fields.itemFind then
        if self.findOn then
            pcall(function() self.fields.itemFind:unfocus() end)
            self.findOn = false
        end
        self.fields.itemFind:setVisible(false)
    end

    if self.auctMenu then
        self.findOn = true
        local m = self.auctMenu

        -- รายการถูกสร้างใหม่ทุกเฟรมจากคำค้นในช่อง  ไม่ใช่ค้างไว้ตั้งแต่ตอนเปิดเมนู
        -- ไม่งั้นพิมพ์แล้วลิสต์ไม่ขยับ ซึ่งอ่านได้อย่างเดียวว่า "ช่องค้นหาเสีย"
        local findBox = self.fields.itemFind
        local find    = findBox and findBox:getInternalText() or ""
        local its     = self:itemPickList(find)

        local cur    = self.fields.item and self.fields.item:getInternalText() or ""
        local ih     = math.max(30, U.h(U.F.s) + 14)
        local thumb  = ih - 8
        local noIcon = KR.L("ไม่ผูกไอเทม", "No item (hand over yourself)")

        local wmax = 260
        for i = 1, math.min(#its, 40) do
            local lbl = (its[i] == "") and noIcon or itemDisplay(its[i])
            wmax = math.max(wmax, U.w(lbl, U.F.s) + thumb + 34)
        end
        wmax = math.min(wmax, math.max(260, math.floor(self.width * 0.42)))

        -- กล่องห้ามทะลุขอบขวาและห้ามเลยแถบสถานะล่าง
        -- เมนูที่ยาวกว่าหน้าต่างคือเมนูที่เลือกบรรทัดท้าย ๆ ไม่ได้เลย
        local mx2 = math.max(0, math.min(m.x, self.width - wmax - 6))
        local top = m.y + 2

        -- ช่องค้นหาอยู่ในเมนู  วางก่อนคำนวณที่เหลือ เพราะมันกินความสูงคงที่
        local fh3 = boxH()
        U.solid(self, mx2, top, wmax, fh3 + 8, U.C.bgHead)
        U.border(self, mx2, top, wmax, fh3 + 8, U.C.line3)
        if findBox then
            findBox:setVisible(true)
            findBox:setX(mx2 + 5); findBox:setY(top + 4)
            sizeBox(findBox, wmax - 10, fh3)
        end
        local listTop = top + fh3 + 8

        local room = self.height - U.STAT - 6 - listTop
        local nvis = math.max(1, math.min(math.max(#its, 1), math.floor((room - 8) / ih)))
        local mh   = nvis * ih + 8

        local maxScroll = math.max(0, #its - nvis)
        m.scroll = math.max(0, math.min(math.floor(m.scroll or 0), maxScroll))
        m.view, m.total = nvis, #its

        U.solid(self, mx2, listTop, wmax, mh, U.C.bgSel)
        U.border(self, mx2, listTop, wmax, mh, U.C.line3)

        if #its == 0 then
            U.textC(self, isAdminView()
                      and KR.L("ไม่เจอไอเทมที่ตรงกับคำนี้", "Nothing in this build matches that")
                      or  KR.L("ไม่มีของในกระเป๋าที่ลงขายได้",
                               "Nothing in your bag can be listed (worn and equipped items cannot)"),
                    mx2 + wmax / 2, listTop + 8, U.C.mute, U.F.xs)
        end

        for k = 1, nvis do
            local it = its[k + m.scroll]
            if it ~= nil then
                local iy  = listTop + 4 + (k - 1) * ih
                local sel = (it == cur)
                local hot = U.hit({ x = mx2, y = iy, w = wmax, h = ih }, self.mx, self.my)
                if sel then U.fill(self, mx2, iy, wmax, ih, U.C.accent2)
                elseif hot then U.fill(self, mx2, iy, wmax, ih, U.C.bgRow) end

                local lbl
                if it == "" then
                    lbl = noIcon
                    U.slot(self, mx2 + 6, iy + 4, thumb, nil, false)
                    U.textC(self, "-", mx2 + 6 + thumb / 2,
                            iy + 4 + math.floor((thumb - U.h(U.F.xs)) / 2), U.C.mute, U.F.xs)
                else
                    -- ชื่อที่คนอ่านรู้เรื่อง ไม่ใช่ชื่อชนิด  "Fire Axe" บอกอะไรกว่า "Axe" เยอะ
                    -- ชื่อชนิดเต็มไปอยู่บรรทัดจาง ๆ ข้างหลัง เผื่อคนที่ต้องการมันจริง ๆ
                    lbl = itemDisplay(it)
                    U.slot(self, mx2 + 6, iy + 4, thumb, itemTex({ item = it }), false)
                end
                local lx2 = mx2 + 6 + thumb + 10
                U.text(self, lbl, lx2, iy + math.floor((ih - U.h(U.F.s)) / 2),
                       sel and U.C.text or U.C.lite, U.F.s)
                if it ~= "" then
                    U.textR(self, shortType(it), mx2 + wmax - 12,
                            iy + math.floor((ih - U.h(U.F.xs)) / 2), U.C.dim, U.F.xs)
                end

                self.menuBtns[#self.menuBtns + 1] = {
                    x = mx2, y = iy, w = wmax, h = ih, value = it,
                    fn = function(v)
                        -- เก็บลงช่องเดิม  คำสั่งสร้างล็อตจึงไม่ต้องรู้ว่าที่มาเปลี่ยนไป
                        if self.fields.item then self.fields.item:setText(tostring(v)) end
                        print("[Kuraya] auction item picked: '" .. tostring(v) .. "'")
                        self.auctMenu = nil
                    end,
                }
            end
        end

        U.scrollbar(self, mx2 + wmax - 4, listTop + 4, mh - 8, #its * ih, nvis * ih, m.scroll * ih)
    end

    if self.sortOpen and self.bSort then
        local items = {}
        for _, m in ipairs(KR.SORT_ORDER) do
            items[#items + 1] = { label = KR.sortLabel(m), value = m }
        end
        menu(self.bSort, items, (KRClient and KRClient.sortMode) or KR.SORT_DEFAULT,
             function(v) KRClient.sortMode = v; self.sortOpen = false; self.scroll = 0 end)
    end

    if self.curOpen and self.bCur then
        local items = {
            { label = curLabel("all"),  value = "all"       },
            { label = curLabel("cash"), value = KR.CUR.CASH },
            { label = curLabel("hf"),   value = KR.CUR.HF   },
            { label = curLabel("cp"),   value = KR.CUR.CP   },
        }
        menu(self.bCur, items, (KRClient and KRClient.filterCur) or "all",
             function(v) KRClient.filterCur = v; self.curOpen = false; self.scroll = 0 end)
    end
end

-- ------------------------------------------------------------------------------
-- วาด : ลิสต์สินค้า
-- ------------------------------------------------------------------------------
-- ความสูงของแถวขึ้นกับจำนวนบรรทัดราคา  ต้องคำนวณก่อนวาดเพื่อให้ scroll ตรง
local LINE_H = 21
local function rowHeight(nLines)
    return math.max(U.ROW, 26 + nLines * LINE_H)
end

function KRShop:drawList(x, y, w, h, rows)
    local d   = data()
    local ts  = nowTs()
    self.rowBtns = {}

    if #rows == 0 then
        local t, hint
        if self.page == "sale" then
            t, hint = KR.L("ยังไม่มีของลดราคา", "No flash sale right now"), KR.L("รอบหน้าจะมีประกาศขึ้นเหนือหัวเอง", "You will see an announcement when the next one starts")
        elseif self.page == "market" then
            t, hint = KR.L("ยังไม่มีแผงตลาดสด", "No market stalls yet"), KR.L("แอดมินคลิกขวาบนพื้น เลือก AKA Mod > Fresh Market", "Admin: right-click the ground, AKA Mod > Fresh Market")
        elseif (KRClient and KRClient.filterCur or "all") ~= "all" then
            -- ร้านอาจมีของ แต่ตัวกรองสกุลตัดออกหมด  ต้องบอกให้ตรงเหตุ
            -- ไม่งั้นแอดมินจะนึกว่าของหาย ทั้งที่แค่กรองอยู่
            t, hint = KR.L("ไม่มีของที่จ่ายด้วยสกุลนี้", "Nothing takes that currency"),
                      KR.L("กดชิป Currency แล้วเลือก All", "Set the Currency chip back to All")
        elseif d.admin then
            t, hint = KR.L("ร้านยังว่าง", "The shop is empty"),
                      KR.L("ไปที่หน้า ADMIN แล้วกด New เพื่อลงของชิ้นแรก",
                           "Open the ADMIN page and press New to list your first item")
        else
            t, hint = KR.L("ร้านยังว่าง", "The shop is empty"),
                      KR.L("แอดมินยังไม่ได้ลงของ", "No admin has listed anything yet")
        end
        U.emptyState(self, x, y, w, h, t, hint)
        return
    end

    -- ความสูงรวม  ใช้ตัดสินว่าจะมีแถบเลื่อนไหม
    local heights, total = {}, 0
    for i = 1, #rows do
        local n = math.max(1, #KR.priceLines(rows[i], ts, KRClient and KRClient.filterCur))
        heights[i] = rowHeight(n)
        total = total + heights[i]
    end
    if self.scroll > math.max(0, total - h) then self.scroll = math.max(0, total - h) end

    -- คลิปให้อยู่ในกรอบ  ไม่งั้นแถวล่างจะทะลุไปทับแถบสถานะ
    self:setStencilRect(x, y, w, h)

    local cy = y - self.scroll
    for i = 1, #rows do
        local e  = rows[i]
        local rh = heights[i]

        if cy + rh > y and cy < y + h then
            local hot = self.mx >= x and self.mx < x + w and self.my >= cy and self.my < cy + rh
            if hot then U.fill(self, x, cy, w, rh, U.C.bgRow) end
            if i > 1 and not hot then U.hr(self, x, cy, w) end

            local sx = x + 4
            U.slot(self, sx, cy + math.floor((rh - 46) / 2), 46, itemTex(e), e.rare)

            -- ประกาศก่อนใช้
            -- เวอร์ชันก่อนหน้าประกาศสองตัวนี้ "ใต้" จุดที่เอาไปใช้
            -- Lua ไม่เตือนอะไรเลย  มันแค่อ่านเป็นตัวแปรโกลบอลที่ยังไม่มีค่า = nil
            -- ผลคือป้าย NEW ไม่เคยขึ้นสักครั้ง และของหมดไม่เคยถูกทำให้จาง
            local sold  = KR.isSoldOut(e)
            local isNew = KR.isNew(e, ts)

            local tx = sx + 46 + 13
            U.text(self, e.name or e.id, tx, cy + 11,
                   sold and U.C.mute or U.C.text, U.F.m)
            -- ป้าย NEW เป็นสีทอง  ต้องเด่นกว่าตัวหนังสือรอบข้าง ไม่งั้นไม่มีใครเห็น
            local tagX = tx + U.w(e.name or e.id, U.F.m) + 10
            if isNew then
                U.text(self, "NEW", tagX, cy + 13, U.C.gold, U.F.xs)
                tagX = tagX + U.w("NEW", U.F.xs) + 8
            end
            -- ป้าย SALE แดงจัดติดข้างชื่อ  ต้องเห็นก่อนอ่านราคา
            if KR.saleActive(e, ts) then
                local pct = math.floor((KR.discountBp(e, ts) or 0) / 100)
                local lbl = "SALE" .. (pct > 0 and ("  -" .. pct .. "%") or "")
                local pw  = U.w(lbl, U.F.xs) + 10
                U.fill(self, tagX, cy + 11, pw, U.h(U.F.xs) + 5, U.C.bad)
                U.textC(self, lbl, tagX + pw / 2, cy + 13, U.C.bgDark, U.F.xs)
            end

            -- ของหมดไม่ถูกซ่อน  มันกลายเป็นแถวสีจางพร้อมกำหนดเข้าใหม่
            -- ซ่อนไปเลยทำให้ร้านดูเหมือนไม่เคยมีของชิ้นนั้นอยู่จริง
            local meta = tostring(e.cat or ""):upper()
            if sold then
                local left2 = KR.restockIn(e, ts)
                if left2 == nil then
                    meta = meta .. "  SOLD OUT"
                elseif left2 <= 0 then
                    meta = meta .. "  BACK ANY MOMENT"
                else
                    meta = meta .. "  BACK IN " .. KR.fmtDur(left2)
                end
            elseif e.stock then
                meta = meta .. "  " .. e.stock .. " LEFT"
            end
            local qLeft = (d.quota or {})[e.id]
            if qLeft ~= nil then meta = meta .. "  " .. qLeft .. " LEFT FOR YOU" end
            if e.market then
                local m = (d.markets or {})[e.market]
                meta = meta .. "  " .. ((m and m.name) or e.market)
            end
            -- ชุดต้องบอกตั้งแต่บรรทัดสรุปว่ามันเป็นชุด และมีกี่ชิ้น
            -- ไม่งั้นมันดูเหมือนของชิ้นเดียวที่ราคาแพงอย่างไม่มีเหตุผล
            if KR.isSet(e) then
                meta = KR.L("ชุด ", "SET ") .. KR.setCount(e) ..
                       KR.L(" ชิ้น", " ITEMS") .. "  " .. meta
            end
            local metaY = cy + 11 + U.h(U.F.m) + 3
            U.text(self, meta, tx, metaY, U.C.dim, U.F.xs)

            -- ---- ปุ่ม More ของชุด  (0.6.12) ------------------------------------
            -- วางต่อท้ายบรรทัดสรุป ไม่ใช่เป็นปุ่มเต็มก้อนข้าง ๆ ปุ่มซื้อ
            -- แถวหนึ่งแถวมีที่พอสำหรับปุ่มใหญ่ปุ่มเดียว และปุ่มนั้นต้องเป็นปุ่มซื้อ
            if KR.isSet(e) then
                local mlbl = KR.L("ดูของในชุด", "More")
                local mw   = U.w(mlbl, U.F.xs) + 14
                local mx3  = tx + U.w(meta, U.F.xs) + 10
                local mh   = U.h(U.F.xs) + 4
                local mhot = U.hit({ x = mx3, y = metaY - 2, w = mw, h = mh }, self.mx, self.my)
                U.fill(self, mx3, metaY - 2, mw, mh, mhot and U.C.bgSel or U.C.bgCard)
                U.border(self, mx3, metaY - 2, mw, mh, mhot and U.C.accent or U.C.line3)
                U.textC(self, mlbl, mx3 + mw / 2, metaY, mhot and U.C.text or U.C.lite, U.F.xs)
                self.rowBtns[#self.rowBtns + 1] =
                    { x = mx3, y = metaY - 2, w = mw, h = mh, act = "setmore", entry = e }
            end

            -- ราคาทุกสกุล  แยกด้วยสี  ชิดขวาก่อนถึงปุ่ม
            local lines = KR.priceLines(e, ts, KRClient and KRClient.filterCur)
            local bw    = 112
            local px    = x + w - bw - U.GAP - 8
            local ly    = cy + math.floor((rh - #lines * LINE_H) / 2)
            for k = 1, #lines do
                local ln = lines[k]
                local c  = ln.combo and U.C.mute or U.curCol(ln.cur)
                U.textR(self, ln.text, px, ly + (k - 1) * LINE_H, c, U.F.s)
                U.coin(self, ln.cur, px - U.w(ln.text, U.F.s) - 21, ly + (k - 1) * LINE_H + 1, 16)
            end

            -- ปุ่มขวาสุด  ข้อความบอกเหตุผลเมื่อกดไม่ได้ ไม่ใช่แค่เทาแล้วเงียบ
            local label, style, act = KR.L("ซื้อ", "Buy"), "pri", true
            if e.kind == KR.KIND.SERVICE then label = KR.L("สั่ง", "Order"); style = "ok" end
            if #lines == 0 then
                label, style, act = KR.L("ไม่รับสกุลนี้", "N/A"), "offb", false
            elseif e.stock ~= nil and e.stock <= 0 then
                label, style, act = KR.L("หมด", "Sold out"), "offb", false
            elseif qLeft ~= nil and qLeft <= 0 then
                label, style, act = KR.L("ครบโควตา", "Limit reached"), "offb", false
            elseif e.market and d.atMarket ~= e.market then
                local m = (d.markets or {})[e.market]
                label, style, act = KR.L("ไปที่ ", "Go to ") .. ((m and m.name) or KR.L("แผง", "stall")), "offb", false
            elseif KR.saleActive(e, ts) then
                style = "sale"
            end

            local b = U.btn(self, x + w - bw - 8, cy + math.floor((rh - 34) / 2), bw, 34,
                            label, style, self.mx, self.my)
            if act then
                b.entry = e
                self.rowBtns[#self.rowBtns + 1] = b
            end
        end
        cy = cy + rh
    end

    self:clearStencilRect()
    U.scrollbar(self, x + w - 3, y, h, total, h, self.scroll)
end


-- ==============================================================================
-- หน้าจัดการ (แอดมิน)
--
-- แบ่งสองฝั่ง  ซ้ายคือรายการ ขวาคือตัวแก้
-- ที่ไม่ทำเป็นหน้าต่างเด้งใหม่ เพราะแอดมินต้องเห็นของทั้งหมดตอนแก้ทีละชิ้น
-- ไม่งั้นจะตั้งราคาชนกันเองโดยไม่รู้ตัว
--
-- สามแท็บ  ของในร้าน / แผงตลาด / ผู้เล่น
-- ==============================================================================
local ATABS = {
    { id = "items",   th = "ของในร้าน", en = "Listings" },
    { id = "stalls",  th = "แผงตลาด",  en = "Stalls"   },
    { id = "people",  th = "ผู้เล่น",   en = "Players"  },
    { id = "hfp",     th = "แพ็ก HF",   en = "HF packs" },
    -- 0.7.0  กระดานราคาโลก  แก้ที่นี่ ผู้เล่นดูที่หน้า PRICES
    { id = "board",   th = "กระดานราคา", en = "Price board" },
}

-- "pet" อยู่ในลิสต์นี้เพราะมันเป็นคำสงวนของ KR.kindOfCat (0.6.16)
-- หมวดที่เปลี่ยนพฤติกรรมของทั้งรายการ ต้องกดเลือกได้ ไม่ใช่ต้องรู้เองว่าพิมพ์ได้
local CATS  = { "general", "food", "medical", "weapon", "building",
                "vehicle", "pet", "service", "fresh" }
local KINDS = { KR.KIND.ITEM, KR.KIND.VEHICLE, KR.KIND.PET, KR.KIND.SERVICE }
local CURS  = { KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP }

-- ช่องกรอกทั้งหมดที่หน้าจัดการใช้  สร้างครั้งเดียวแล้วย้ายตำแหน่งเอา
local FIELDS = {
    "name", "item", "stock", "quota", "salePct", "saleHrs", "count",
    "a1", "a2", "a3", "a4", "b1", "b2", "b3", "b4",
    "stallName", "grantTo", "grantAmt", "grantWhy",
}

-- ปุ่มเล็ก ๆ ที่กดแล้ววนค่า  ใช้แทน dropdown เพราะตัวเลือกน้อยและกดเร็วกว่า
local function cycle(list, cur, back)
    local i = 1
    for k = 1, #list do if list[k] == cur then i = k end end
    i = i + (back and -1 or 1)
    if i > #list then i = 1 elseif i < 1 then i = #list end
    return list[i]
end

function KRShop:adminInit()
    if self.adm then return end
    self.adm = {
        tab   = "items",
        cat   = "general",
        kind  = KR.KIND.ITEM,
        rare  = false,
        restock = KR.RESTOCK.NEVER,
        qper  = KR.PERIOD.SALE,
        market = nil,
        -- ของใหม่เริ่มที่ "เปิดขาย"  แอดมินที่อยากตั้งราคาไว้เงียบ ๆ ต้องกดซ่อนเอง
        enabled = true,
        cur   = { KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP, nil },   -- สกุลของแต่ละแถวราคา
        cur2  = { nil, nil, nil, nil },                        -- สกุลที่สอง = จ่ายผสม
        edit  = nil,
        gcur  = KR.CUR.HF,
        set   = nil,        -- ของในชุด  nil = รายการนี้ไม่ใช่ชุด  (0.6.12)
        box   = nil,        -- รูปกล่องของชุด
    }
end

-- อ่านฟอร์มเป็น args ที่เซิร์ฟเวอร์เข้าใจ
function KRShop:admArgs()
    local a  = self.adm
    local f  = self.fields
    local function v(k) return f[k] and f[k]:getInternalText() or "" end
    local function n(k) return tonumber(v(k)) end

    local pay = {}
    for i = 1, 4 do
        local c1, p1 = a.cur[i],  n("a" .. i)
        local c2, p2 = a.cur2[i], n("b" .. i)
        if c1 and p1 and p1 > 0 then
            if c2 and p2 and p2 > 0 then
                pay[#pay + 1] = { { cur = c1, price = p1 }, { cur = c2, price = p2 } }
            else
                pay[#pay + 1] = { cur = c1, price = p1 }
            end
        end
    end

    -- ช่องเดียวส่งไปคนละฟิลด์ตามหมวด  (0.6.11 รถ · 0.6.16 สัตว์)
    --
    -- หมวดรถ -> เซิร์ฟต้องได้ entry.vehicle  หมวดสัตว์ -> entry.pet  หมวดอื่น -> entry.item
    -- ส่งไปหลายฟิลด์พร้อมกันไม่ได้: ของที่เคยเป็นไอเทมแล้วแอดมินย้ายไปหมวดรถ
    -- จะเหลือ item ค้างอยู่ แล้ว itemTex กับ S.buy จะเห็นมันคนละอย่างกัน
    local spForm = SPEC[KR.kindOfCat(KR.catKey(v("cat")))]
    local typed  = v("item") ~= "" and v("item") or nil

    return {
        id      = a.edit,
        rev     = a.rev,
        name    = v("name"),
        item    = (not spForm) and typed or nil,
        vehicle = (spForm and spForm.kind == KR.KIND.VEHICLE) and typed or nil,
        pet     = (spForm and spForm.kind == KR.KIND.PET) and typed or nil,
        -- ของในชุด  อ่านจากช่องในฟอร์มตรง ๆ (0.6.14)
        -- **ช่องคือความจริง ไม่ใช่ตารางที่เก็บไว้ข้าง ๆ**
        -- เก็บสองที่แล้วมันจะไม่ตรงกันในวันที่ใครสักคนลืมอัปเดตอันหนึ่ง
        set     = self:admSetLines(),
        box     = (a.mode == "set") and a.box or nil,
        cat     = KR.catKey(v("cat")),
        -- ต้องอนุมานจากหมวดที่ "พิมพ์อยู่ในช่อง" ตัวเดียวกับที่ส่งเป็น cat
        -- a.cat เป็นค่าค้างที่ถูกตั้งเป็น "general" ตอน adminInit แล้วไม่มีใครอัปเดตอีก
        -- (ปุ่มเลือกหมวดเขียนลงช่องข้อความอย่างเดียว)  ของที่ตั้งเป็นรถหรือบริการ
        -- จึงถูกส่งไปเป็น kind = item แล้วโดนด่านเช็กชนิดไอเทมใน S.adminSave ตีกลับทุกครั้ง
        kind    = KR.kindOfCat(KR.catKey(v("cat"))),   -- อนุมานจากหมวด  ไม่มีปุ่มแยกแล้ว
        rare    = a.rare,
        -- ต้องส่งไปทุกครั้ง  ฟอร์มที่ไม่ส่งฟิลด์นี้เท่ากับสั่ง "เปิดขาย" โดยไม่ได้ตั้งใจ
        -- (เซิร์ฟกันไว้อีกชั้นแล้วใน cleanEntry แต่ที่นี่คือที่ที่แอดมินเห็นสวิตช์จริง)
        enabled = a.enabled ~= false,
        stock   = n("stock"),
        restock = a.restock,
        quota   = n("quota") or 0,
        quotaPeriod = a.qper,
        saleBp  = n("salePct") and math.floor(n("salePct") * 100) or nil,
        -- ช่องนี้เป็น "นาที" แล้วตั้งแต่ 0.6.0  ชื่อฟิลด์ที่ส่งจึงเปลี่ยนตามไปด้วย
        -- ส่ง saleHours ไปด้วยไม่ได้ เพราะเซิร์ฟจะเลือกอ่าน saleMins ก่อนอยู่แล้ว
        -- แต่ถ้าวันหนึ่งมีคนลบ saleMins ทิ้ง การมี saleHours ค้างอยู่จะทำให้
        -- ค่าที่กรอกเป็นนาทีถูกอ่านเป็นชั่วโมงเงียบ ๆ = โปรลดราคายาว 60 เท่า
        saleMins = n("saleHrs") or (24 * 60),
        -- ได้ครั้งละกี่ชิ้น  S.buy อ่าน entry.count มาตลอด แต่ไม่เคยมีใครเขียนค่าลงไป
        count   = n("count") or 1,
        market  = a.market,
        pay     = pay,
    }
end

-- เอาของที่มีอยู่มาเติมฟอร์ม
function KRShop:admLoad(e)
    local a, f = self.adm, self.fields
    local function set(k, val) if f[k] then f[k]:setText(val ~= nil and tostring(val) or "") end end

    if not e then
        a.edit = nil
        a.rev  = nil
        a.cat, a.kind, a.rare = "general", KR.KIND.ITEM, false
        if self.fields.cat then self.fields.cat:setText("general") end
        a.restock, a.qper, a.market = KR.RESTOCK.NEVER, KR.PERIOD.SALE, nil
        a.enabled = true
        a.cur  = { KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP, nil }
        a.cur2 = { nil, nil, nil, nil }
        -- ของในชุดต้องล้างด้วย  ไม่งั้นกด Clear แล้วของจากรายการก่อนหน้ายังค้างอยู่
        -- แล้วรายการใหม่จะถูกบันทึกเป็นชุดของคนอื่นโดยที่ไม่มีใครสั่ง (0.6.12)
        a.box, a.setKinds, a.setPick, a.mode = nil, {}, nil, "single"
        for i = 1, KR.SET_MAX do
            set("setI" .. i, "")
            set("setN" .. i, "")
        end
        for _, k in ipairs(FIELDS) do set(k, "") end
        set("saleHrs", 60)      -- นาที  ค่าเริ่มต้นหนึ่งชั่วโมง
        set("count", 1)
        return
    end

    a.edit    = e.id
    a.rev     = e.rev          -- เลขรอบตอนที่โหลดมา  ใช้จับว่ามีแอดมินอื่นแก้แซง
    a.cat     = e.cat or "general"
    a.kind    = e.kind or KR.KIND.ITEM
    if self.fields.cat then self.fields.cat:setText(tostring(e.cat or "general")) end
    a.rare    = e.rare and true or false
    a.restock = e.restock or KR.RESTOCK.NEVER
    a.qper    = e.quotaPeriod or KR.PERIOD.SALE
    a.market  = e.market
    a.enabled = e.enabled ~= false      -- ของเก่าที่ยังไม่มีฟิลด์นี้ = เปิดขายอยู่

    -- ---- ของในชุด  เทลงช่องในฟอร์ม  (0.6.14) --------------------------------
    -- ไม่เก็บสำเนาไว้ใน a.set อีกแล้ว  ช่องคือความจริงที่เดียว
    a.box      = e.box
    a.setKinds = {}
    a.setPick  = nil
    a.mode     = (type(e.set) == "table" and #e.set > 0) and "set" or "single"
    for i = 1, KR.SET_MAX do
        local ln = (type(e.set) == "table") and e.set[i] or nil
        -- ชนิดของบรรทัดอ่านจากฟิลด์ที่มีค่าจริง ไม่ใช่จากหมวดของรายการ
        -- ชุดหนึ่งชุดปนได้ทุกชนิด (0.6.13) หมวดจึงตอบแทนบรรทัดไม่ได้
        local lk, lv = "item", nil
        if ln then
            for _, kk in ipairs(SPEC_ORDER) do
                local sp = SPEC[kk]
                if ln[sp.field] then lk, lv = sp.kind, ln[sp.field] end
            end
            if lv == nil then lv = ln.item end
        end
        a.setKinds[i] = lk
        set("setI" .. i, lv or "")
        set("setN" .. i, ln and math.max(1, math.floor(tonumber(ln.n) or 1)) or "")
    end

    -- ช่องเดียวรับได้ทั้งไอเทม รุ่นรถ และสัตว์  ของเก่าเก็บไว้คนละฟิลด์กัน
    set("name", e.name); set("item", e.vehicle or e.pet or e.item); set("stock", e.stock)
    set("quota", (e.quota and e.quota > 0) and e.quota or "")
    set("salePct", e.saleBp and (e.saleBp / 100) or "")
    -- ระยะเวลาลดราคาไม่ได้ถูกเก็บไว้  ของที่เก็บคือ e.saleEndsAt (เวลาจริงที่ราคาเด้งกลับ)
    -- ตอนแก้ของเก่าจึงเริ่มที่ค่าเริ่มต้นเสมอ ไม่ได้เดาย้อนกลับจากเวลาที่เหลือ
    -- เพราะการเดาย้อนกลับแล้วกดบันทึกจะ **ต่อเวลาโปรออกไปอีก** โดยที่แอดมินไม่ได้สั่ง
    set("saleHrs", 60)
    set("count", (e.count and e.count > 1) and e.count or 1)

    a.cur, a.cur2 = { nil, nil, nil, nil }, { nil, nil, nil, nil }
    for i = 1, 4 do set("a" .. i, ""); set("b" .. i, "") end
    local opts = KR.payOptions(e)
    for i = 1, math.min(#opts, 4) do
        local o = opts[i]
        a.cur[i] = o[1].cur;  set("a" .. i, o[1].price)
        if o[2] then a.cur2[i] = o[2].cur; set("b" .. i, o[2].price) end
    end
end

-- สิ่งที่ยังกรอกไม่ครบ  บอกก่อนกดบันทึก ไม่ใช่รอเซิร์ฟเวอร์ด่ากลับมา
-- ของในชุด อ่านจากช่องในฟอร์ม  (0.6.14)
--
-- คืน nil ตอนไม่ได้อยู่โหมดชุด ไม่ใช่ตารางว่าง
-- ตารางว่างกับ nil เดินทางข้ามสายไม่เหมือนกัน และ KR.isSet() ก็ตอบไม่เหมือนกัน
function KRShop:admSetLines()
    local a = self.adm
    if not a or a.mode ~= "set" then return nil end

    local out = {}
    for i = 1, KR.SET_MAX do
        local f = self.fields["setI" .. i]
        local s = f and (f:getInternalText() or "") or ""
        s = (s:gsub("^%s+", ""):gsub("%s+$", ""))
        if s ~= "" then
            local q = self.fields["setN" .. i]
            local n = math.max(1, math.floor(tonumber(q and q:getInternalText()) or 1))
            local sp = SPEC[(a.setKinds or {})[i]]
            if sp then
                out[#out + 1] = { [sp.field] = s, n = n }
            else
                out[#out + 1] = { item = s, n = n }
            end
        end
    end
    return (#out > 0) and out or nil
end

function KRShop:admProblems()
    local a = self:admArgs()
    local out = {}
    if a.name == "" then out[#out + 1] = KR.L("ยังไม่ได้ตั้งชื่อ", "Name is empty") end
    if #a.pay == 0 then out[#out + 1] = KR.L("ยังไม่มีราคาสักสกุล", "No price set") end
    if a.kind == KR.KIND.ITEM and not a.item and not a.set then
        out[#out + 1] = KR.L("ไม่ได้ระบุไอเทม  ซื้อแล้วจะไม่ได้ของ", "No item type - buying gives nothing")
    end
    if self.adm and self.adm.mode == "set" then
        if not a.set then
            out[#out + 1] = KR.L("ชุดนี้ยังไม่มีของสักชิ้น", "This set has nothing in it yet")
        end
    end
    -- รถกับสัตว์ใช้เกณฑ์เดียวกัน  ไม่ได้ระบุ = ซื้อแล้วไม่ได้อะไร
    local spProb = SPEC[a.kind]
    if spProb and not a.set then
        local picked = a[spProb.field]
        if not picked then
            out[#out + 1] = (spProb.kind == KR.KIND.PET)
                and KR.L("ไม่ได้ระบุสัตว์  ซื้อแล้วจะไม่ได้สัตว์",
                         "No animal - buying gives nothing")
                or  KR.L("ไม่ได้ระบุรุ่นรถ  ซื้อแล้วจะไม่ได้รถ",
                         "No vehicle model - buying gives nothing")
        elseif specKnown(spProb, picked) == false then
            -- ค้านเฉพาะตอนรู้แน่ว่าไม่มี  ตอนอ่านรายชื่อไม่ได้ (nil) ต้องไม่ค้าน
            -- ไม่งั้นบิลด์ที่เราอ่านรายชื่อไม่ออกจะกดบันทึกไม่ได้เลยสักชิ้น
            out[#out + 1] = (spProb.kind == KR.KIND.PET)
                and KR.L("เซิร์ฟนี้ไม่มีสัตว์ชนิดนี้", "This server has no such animal")
                or  KR.L("เซิร์ฟนี้ไม่มีรถรุ่นนี้", "This server has no such vehicle")
        end
    end
    if a.saleBp and (a.saleBp <= 0 or a.saleBp >= 10000) then
        out[#out + 1] = KR.L("ส่วนลดต้องอยู่ระหว่าง 1-99", "Discount must be 1-99")
    end
    return out
end

-- ------------------------------------------------------------------------------
-- ตัวช่วยวาดของหน้าจัดการ
-- ------------------------------------------------------------------------------
-- ความสูงของแท็บ/ช่องกรอก ผูกกับความสูงฟอนต์จริง ไม่ใช่ตัวเลขตายตัว
-- ผู้เล่นที่ตั้ง UI scale 1.5 จะได้กล่องที่โตตามตัวหนังสือ ไม่ใช่ตัวหนังสือล้นกล่อง
-- tagH / boxH ถูกย้ายขึ้นไปไว้บนสุดของไฟล์  ดูคอมเมนต์ตรงนั้น

local function tag(p, x, y, w, label, on, mx, my)
    local th2 = tagH()
    local hot = U.hit({ x = x, y = y, w = w, h = th2 }, mx, my)
    U.fill(p, x, y, w, th2, on and U.C.accent2 or (hot and U.C.bgRow or U.C.bgCard))
    U.textC(p, label, x + w / 2, y + 6, on and U.C.text or U.C.mute, U.F.s)
    return { x = x, y = y, w = w, h = th2 }
end

local function fieldBox(p, box, x, y, w, label)
    U.text(p, label, x, y, U.C.dim, U.F.xs)
    local by  = y + U.h(U.F.xs) + 3
    local bh2 = boxH()
    U.fill(p, x, by, w, bh2, U.C.bgDark)
    U.border(p, x, by, w, bh2, U.C.line3)
    if box then
        box:setX(x + 5); box:setY(by + 3)
        sizeBox(box, w - 10, bh2 - 6)
    end
    return by + bh2 + 8
end

-- ------------------------------------------------------------------------------
-- วาด : หน้าจัดการ
-- ------------------------------------------------------------------------------
function KRShop:drawAdmin(x, y, w, h, rows)
    self:adminInit()
    local a = self.adm
    self.admBtns, self.rowBtns = {}, {}

    -- ล้างปุ่มของแท็บก่อนหน้าทุกครั้ง
    -- ไม่งั้นปุ่ม "บันทึก" ของแท็บของในร้านจะยังกินคลิกอยู่ตอนสลับไปแท็บอื่น
    -- เพราะมันอยู่มุมขวาล่างตำแหน่งเดียวกันพอดี
    self.bAdmSave, self.bAdmClear, self.bAdmNew = nil, nil, nil
    self.bStallSave, self.bStallDel, self.bGrant, self.bUnlock = nil, nil, nil, nil

    -- แท็บย่อย
    local tx = x
    for i = 1, #ATABS do
        local t = ATABS[i]
        local lbl = KR.L(t.th, t.en)
        -- ป้ายแดงบนแท็บแพ็ก HF  จำนวนคำขอที่รออยู่จริง
        if t.id == "hfp" then
            local nw = #(((data().hfp or {}).pend) or {})
            if nw > 0 then lbl = lbl .. "  " .. nw end
        end
        local tw2 = U.w(lbl, U.F.s) + 24
        local b = tag(self, tx, y, tw2, lbl, a.tab == t.id, self.mx, self.my)
        b.act, b.tab = "tab", t.id
        self.admBtns[#self.admBtns + 1] = b
        tx = tx + tw2 + 4
    end

    -- ---- ปุ่มดูมุมผู้เล่น  อยู่แถวแท็บ จึงเห็นได้จากทุกแท็บ -------------------
    --
    -- เดิมซ่อนอยู่ก้นแท็บ "ผู้เล่น" ซึ่งแปลว่าคนที่ต้องการมันหาไม่เจอ
    -- และเจ้าของเซิร์ฟถามมาตรง ๆ ว่า "ทำไมเป็น user คนเดียวยังเห็น admin"
    -- คำตอบคือ PZ ถือว่า **คนที่โฮสต์เซิร์ฟคือแอดมินเสมอ** ไม่ว่าจะเล่นคนเดียวหรือไม่
    -- ม็อดแค่เชื่อสิ่งที่ getAccessLevel() ตอบ  จะแกล้งไม่เชื่อก็ผิดยิ่งกว่า
    -- ปุ่มนี้จึงคือคำตอบของคำถามนั้น และมันต้องอยู่ในที่ที่มองเห็นตั้งแต่แรก
    local pvLbl = KR.L("ดูมุมผู้เล่น", "View as player")
    local pvW   = U.w(pvLbl, U.F.s) + 28
    local pvb   = U.btn(self, x + w - pvW, y, pvW, tagH(), pvLbl, "neu", self.mx, self.my)
    pvb.act = "preview"
    self.admBtns[#self.admBtns + 1] = pvb

    local tabH = tagH() + 8
    local by  = y + tabH
    local bh  = h - tabH
    local lw  = math.floor(w * 0.46)          -- ฝั่งซ้าย : รายการ
    local rx  = x + lw + 10
    local rw  = w - lw - 10

    -- ไม่มีตาราง "แท็บนี้ใช้ช่องอะไร" อีกแล้ว  ดูคอมเมนต์ที่ sizeBox
    -- ช่องไหนถูกวางในเฟรมนี้ ช่องนั้นเห็น  ที่เหลือหายเองโดยไม่ต้องมีใครจำ

    if a.tab == "items"  then self:admItems(x, by, lw, bh, rx, rw, rows) end
    if a.tab == "stalls" then self:admStalls(x, by, lw, bh, rx, rw) end
    if a.tab == "people" then self:admPeople(x, by, lw, bh, rx, rw) end
    if a.tab == "hfp"    then self:admHfp(x, by, w, bh) end
    if a.tab == "board"  then self:admBoard(x, by, w, bh) end
end

-- ---- แท็บ : ของในร้าน ----------------------------------------------------------
function KRShop:admItems(x, y, lw, h, rx, rw, rows)
    local a  = self.adm
    local d  = data()
    local ts = nowTs()

    -- ซ้าย : รายการ
    if #rows == 0 then
        U.emptyState(self, x, y, lw, h,
                     KR.L("ยังไม่มีของในร้าน", "Nothing listed"),
                     KR.L("กรอกฝั่งขวาแล้วกดเพิ่ม", "Fill the form on the right"))
    else
        self:setStencilRect(x, y, lw, h)

        -- ความสูงแถวต้องมาจากฟอนต์จริง  ไม่ใช่ 30 ตายตัว
        --
        -- แถวหนึ่งมีสองบรรทัด (ชื่อ + หมวด/สต็อก)  ตอนฟอนต์ยังเป็น Small มันพอดี 30 px
        -- พอฟอนต์ขยับขึ้นเป็น Medium สองบรรทัดรวมกันสูงกว่า 30
        -- ผลคือบรรทัดที่สองของแถวนี้ไปทับบรรทัดแรกของแถวถัดไป
        -- (เจ้าของเซิร์ฟถ่ายรูปมาให้ดู: "ui ซ้อนบางจุด")
        local bh2 = math.max(26, U.h(U.F.s) + 8)
        local rh  = math.max(bh2 + 6, 8 + U.h(U.F.s) + U.h(U.F.xs) + 2)
        local cy  = y - self.scroll
        for i = 1, #rows do
            local e = rows[i]
            if cy + rh > y and cy < y + h then
                local on  = (a.edit == e.id)
                local hot = self.mx >= x and self.mx < x + lw and self.my >= cy and self.my < cy + rh
                if on then U.fill(self, x, cy, lw, rh, U.C.bgSel)
                elseif hot then U.fill(self, x, cy, lw, rh, U.C.bgRow) end
                if on then U.fill(self, x, cy, 2, rh, U.C.accent) end
                if i > 1 and not (on or hot) then U.hr(self, x, cy, lw) end

                local off = (e.enabled == false)

                -- ปุ่มขวาสุดก่อน  ที่เหลือคือความกว้างที่ตัวหนังสือใช้ได้จริง
                --
                -- ป้ายเดิมเขียนว่า on/off ซึ่งอ่านไม่ออกว่าเป็น "สถานะตอนนี้" หรือ "กดแล้วจะเป็น"
                -- ปุ่มต้องบอกสิ่งที่จะเกิดขึ้นเมื่อกด  สถานะตอนนี้ให้ชิปข้างชื่อเป็นคนบอก
                local togLbl = off and KR.L("โชว์", "Show") or KR.L("ซ่อน", "Hide")
                local togW   = math.max(44, U.w(togLbl, U.F.s) + 14)
                local delW   = 28
                local bx2 = x + lw - togW - 4
                local by2 = cy + math.floor((rh - bh2) / 2)
                local bo = U.btn(self, bx2, by2, togW, bh2,
                                 togLbl, off and "ok" or "neu", self.mx, self.my)
                bo.act, bo.e = "toggle", e
                local bd = U.btn(self, bx2 - delW - 4, by2, delW, bh2, "x", "bad", self.mx, self.my)
                bd.act, bd.e = "del", e

                local textR = bd.x - 8
                local nm = KR.trunc(e.name or e.id, 30)
                U.text(self, nm, x + 8, cy + 4, off and U.C.dim or U.C.text, U.F.s)

                -- ชิปแดงข้างชื่อ  เจ้าของเซิร์ฟต้องกวาดตาแถวเดียวแล้วรู้ว่าอันไหนผู้เล่นไม่เห็น
                -- ตัวหนังสือจาง ๆ ในบรรทัดล่างอย่างเดียวมองข้ามง่ายเกินไป
                if off then
                    local chip = KR.L("ซ่อนอยู่", "HIDDEN")
                    local cwd  = U.w(chip, U.F.xs) + 8
                    local cxx  = x + 8 + U.w(nm, U.F.s) + 6
                    if cxx + cwd < textR then
                        U.fill(self, cxx, cy + 5, cwd, U.h(U.F.xs) + 2, U.C.bad)
                        U.text(self, chip, cxx + 4, cy + 5, U.C.bgDark, U.F.xs)
                    end
                end

                local meta = tostring(e.cat or "")
                if e.stock then meta = meta .. "  x" .. e.stock end
                if e.saleBp then meta = meta .. "  -" .. math.floor(e.saleBp / 100) .. "%" end
                if e.market then meta = meta .. "  " .. KR.L("แผง", "stall") end
                if off then meta = meta .. "  " .. KR.L("ผู้เล่นไม่เห็นรายการนี้", "players cannot see this") end
                if not e.item and (e.kind or KR.KIND.ITEM) == KR.KIND.ITEM then
                    -- ของเก่าที่ลงไว้ก่อนจะมีการบังคับกรอกช่องไอเทม  ซื้อแล้วจะไม่ได้ของ
                    meta = meta .. "  " .. KR.L("ไม่มีไอเทม", "NO ITEM")
                end
                U.text(self, meta, x + 8, cy + 4 + U.h(U.F.s), U.C.dim, U.F.xs)

                local lines = KR.priceLines(e, ts, nil)
                if lines[1] then
                    U.textR(self, lines[1].text .. (#lines > 1 and ("  +" .. (#lines - 1)) or ""),
                            textR, cy + math.floor((rh - U.h(U.F.s)) / 2),
                            U.curCol(lines[1].cur), U.F.s)
                end

                local br = { x = x, y = cy, w = math.max(10, bd.x - x - 6), h = rh, act = "pick", e = e }
                self.admBtns[#self.admBtns + 1] = br
                self.admBtns[#self.admBtns + 1] = bd
                self.admBtns[#self.admBtns + 1] = bo
            end
            cy = cy + rh
        end
        self:clearStencilRect()
        U.scrollbar(self, x + lw - 3, y, h, #rows * rh, h, self.scroll)
    end

    -- ------------------------------------------------------------------------
    -- ขวา : ตัวแก้  รื้อใหม่ใน 0.6.0
    --
    -- ปัญหาของฟอร์มเดิมไม่ใช่ว่ามันผิด  มันถูกทุกช่อง  แต่มันอ่านไม่ได้
    --   ป้ายกำกับยาวกว่าช่องกรอกเอง  ("สต็อก  ว่าง = ไม่จำกัด" กว้างกว่าช่องที่มันอธิบาย)
    --   ทุกช่องดูสำคัญเท่ากันหมด ทั้งที่ของส่วนใหญ่ในร้านใช้แค่ชื่อ+ไอเทม+ราคา
    --   และคำอธิบายทั้งหมดเป็นภาษาไทย = คนที่อ่านไทยไม่ออกใช้ฟอร์มนี้ไม่ได้เลย
    --
    -- หลักที่ใช้แก้ ตามที่เจ้าของเซิร์ฟสั่งว่า "ทำให้เมคเซนส์ได้แม้ไม่มีภาษาไทย"
    --   1. ป้ายเหลือหนึ่งถึงสองคำ  คำอธิบายยาวย้ายไปเป็นบรรทัดจาง ๆ ใต้ช่อง
    --   2. หน่วยอยู่ในกล่องติดขวาของช่อง (บาท / HF / นาที / ชิ้น / %)
    --      หน่วยที่ซ่อนอยู่ในประโยคภาษาไทยคือหน่วยที่คนอ่านไทยไม่ออกไม่มีทางรู้
    --   3. จัดเป็นกลุ่มมีหัวข้อเป็นคำอังกฤษคำเดียว  BASIC / PRICE / STOCK / SALE / PLACE
    --   4. การ์ดตัวอย่าง "ผู้เล่นจะเห็นแบบนี้" อยู่บนสุด อัปเดตสดทุกเฟรม
    --
    -- ทุกความสูงยังมาจาก U.h(font) เหมือนเดิม  ห้ามกลับไปใช้ offset ตายตัวเด็ดขาด
    -- (ผู้เล่นเคยรายงานว่า "ui admin ซ้อนกัน" ตอนที่ฟอนต์ขยับขึ้นหนึ่งขั้น)
    -- ------------------------------------------------------------------------
    U.fill(self, rx, y, rw, h, U.C.bgHead)
    local cx, cw = rx + 14, rw - 28
    local cy     = y + 10
    local LH     = U.h(U.F.s)
    local XH     = U.h(U.F.xs)
    local BH     = boxH()
    local TH     = tagH()
    local SH     = U.h(U.F.s)
    local GAP    = 9

    -- หัวกลุ่มหนึ่งอัน  คืน y ถัดไป
    local function head(label, col)
        U.fill(self, cx, cy, cw, XH + 6, U.C.bgCard)
        U.fill(self, cx, cy, 3, XH + 6, col or U.C.accent)
        U.text(self, label, cx + 10, cy + 3, col or U.C.lite, U.F.xs)
        return cy + XH + 6 + 6
    end

    -- ช่องกรอกที่มีกล่องหน่วยติดขวา  คืน y ถัดไป
    local function unitBox(box, bx, by, bw, label, unit, hint)
        U.text(self, label, bx, by, U.C.dim, U.F.xs)
        local fy2 = by + XH + 3
        local uw  = (unit and unit ~= "") and (U.w(unit, U.F.xs) + 14) or 0
        U.fill(self, bx, fy2, bw - uw, BH, U.C.bgDark)
        U.border(self, bx, fy2, bw - uw, BH, U.C.line3)
        if uw > 0 then
            U.fill(self, bx + bw - uw, fy2, uw, BH, U.C.bgCard)
            U.border(self, bx + bw - uw, fy2, uw, BH, U.C.line3)
            U.textC(self, unit, bx + bw - uw / 2, fy2 + math.floor((BH - XH) / 2), U.C.mute, U.F.xs)
        end
        if box then
            box:setX(bx + 5); box:setY(fy2 + 3)
            sizeBox(box, bw - uw - 10, BH - 6)
        end
        if hint and hint ~= "" then
            U.text(self, hint, bx, fy2 + BH + 2, U.C.dim, U.F.xs)
            return fy2 + BH + XH + 4
        end
        return fy2 + BH + 6
    end

    -- ---- การ์ดตัวอย่าง ------------------------------------------------------
    --
    -- ทำไมต้องมี: ทุกช่องในฟอร์มนี้มีผลกับสิ่งเดียวคือ "แถวที่ผู้เล่นเห็น"
    -- แต่แอดมินไม่เคยเห็นแถวนั้นจนกว่าจะกดบันทึกแล้วไปเปิดหน้าร้าน
    -- ระยะห่างระหว่างการกระทำกับผลลัพธ์คือที่ที่ความผิดพลาดไปนอนอยู่
    local preview = self:admArgs()
    local pvH = math.max(46, BH + 16)
    U.fill(self, cx, cy, cw, pvH, U.C.bgCard)
    U.border(self, cx, cy, cw, pvH, U.C.line3)
    do
        local isz = math.min(pvH - 14, 40)
        local ix2 = cx + 8
        -- ส่งทั้งก้อน ไม่ใช่แค่ item
        --
        -- ของเดิมเขียน `{ item = preview.item }` ซึ่งทิ้ง cat/kind/vehicle ทิ้งไปหมด
        -- พอเป็นรถ (ไม่มี item) มันจึงเหลือช่องดำ ๆ ทั้งที่ itemTex หาไอคอนใบรถให้ได้
        -- ม็อกอัปเป็นคนจับได้ ไม่ใช่ด่าน  บทเรียนเดิมกับตอนข้อความล้นขอบ
        U.slot(self, ix2, cy + math.floor((pvH - isz) / 2), isz,
               itemTex(preview), preview.rare)

        local tx2 = ix2 + isz + 10
        local nm  = preview.name
        if nm == nil or nm == "" then nm = KR.L("(ยังไม่ได้ตั้งชื่อ)", "(no name yet)") end
        U.text(self, KR.trunc(nm, 28), tx2, cy + 6, U.C.text, U.F.s)

        local meta = tostring(preview.cat or "")
        if (preview.count or 1) > 1 then
            meta = meta .. "  x" .. preview.count .. KR.L(" ต่อครั้ง", " each buy")
        end
        if preview.stock then meta = meta .. "  " .. KR.L("มี ", "stock ") .. preview.stock end
        U.text(self, meta, tx2, cy + 6 + LH, U.C.dim, U.F.xs)

        -- ราคาที่ผู้เล่นจะเห็นจริง  ผ่านตัวคำนวณตัวเดียวกับที่หน้าร้านใช้
        local fake = { pay = preview.pay, saleBp = preview.saleBp,
                       saleEndsAt = preview.saleMins and (ts + 60) or nil }
        local lines = KR.priceLines(fake, ts, nil)
        local px2 = cx + cw - 10
        for i = 1, math.min(#lines, 2) do
            local sTxt = lines[i].text
            U.textR(self, sTxt, px2, cy + 6 + (i - 1) * LH,
                    lines[i].combo and U.C.mute or U.curCol(lines[i].cur), U.F.s)
        end
        if #lines == 0 then
            U.textR(self, KR.L("ยังไม่มีราคา", "no price yet"), px2, cy + 8, U.C.bad, U.F.xs)
        end
    end
    cy = cy + pvH + GAP

    -- ---- BASIC --------------------------------------------------------------
    cy = head("BASIC  ·  " .. KR.L("ของชิ้นนี้คืออะไร", "what is it"), U.C.accent)

    local third = math.floor((cw - GAP * 2) / 3)

    -- ---- โหมด : ชิ้นเดียว หรือ ชุด  (0.6.14) --------------------------------
    --
    -- ของเดิม "เป็นชุด" ถูกซ่อนอยู่หลังชิปเล็ก ๆ ที่มุมล่าง แล้วเปิดเป็นหน้าต่างซ้อน
    -- เจ้าของเซิร์ฟบอกตรง ๆ ว่างง และว่า "ไม่จำเป็นต้องล็อค set ไว้ตลอด"
    --
    -- ตอนนี้มันเป็นคำถามแรกของฟอร์ม เพราะมันคือคำถามแรกจริง ๆ:
    -- **ของชิ้นนี้คือของชิ้นเดียว หรือหลายชิ้นในกล่องเดียว**
    -- ตอบแล้วฟอร์มค่อยเปลี่ยนหน้าตาตาม  ไม่ใช่ให้กรอกไปครึ่งทางแล้วค่อยรู้
    a.mode = a.mode or ((#(a.set or {}) > 0) and "set" or "single")
    local isSet = (a.mode == "set")
    do
        local mw = math.floor((third - GAP) / 2)
        for i, m in ipairs({ { id = "single", th = "ชิ้นเดียว", en = "SINGLE" },
                             { id = "set",    th = "เป็นชุด",   en = "SET" } }) do
            local bx  = cx + (i - 1) * (mw + GAP)
            local on  = (a.mode == m.id)
            local hot = U.hit({ x = bx, y = cy, w = mw, h = TH }, self.mx, self.my)
            U.fill(self, bx, cy, mw, TH, on and U.C.accent2 or (hot and U.C.bgRow or U.C.bgCard))
            U.border(self, bx, cy, mw, TH, on and U.C.accent or U.C.line3)
            U.textC(self, KR.L(m.th, m.en), bx + mw / 2, cy + math.floor((TH - SH) / 2),
                    on and U.C.text or U.C.mute, U.F.s)
            self.admBtns[#self.admBtns + 1] =
                { x = bx, y = cy, w = mw, h = TH, act = "admmode", val = m.id }
        end
        U.text(self, isSet and KR.L("หลายชิ้นในกล่องเดียว", "many things in one box")
                            or KR.L("ของชิ้นเดียว", "one thing"),
               cx + third + GAP, cy + math.floor((TH - XH) / 2), U.C.dim, U.F.xs)
        cy = cy + TH + 8
    end

    unitBox(self.fields.name, cx, cy, third, KR.L("ชื่อ", "NAME"), nil, nil)

    -- ช่องไอเทมมีตัวช่วยค้น  พิมพ์แล้วรายการโผล่ใต้ช่องพร้อมรูปกับชื่อในเกม
    -- ช่องต้องหดให้พอดีกับปุ่มลูกศร ไม่ใช่กินเต็มความกว้างแล้วให้ปุ่มไปวางทับ
    --
    -- ด่านผังจับได้: "field 'item' sits on top of a clickable button at 1034,277"
    -- ช่องกรอกเป็นลูกจริงของ PZ มันกินคลิกในสี่เหลี่ยมของตัวเองเสมอ
    -- ปุ่มที่วางทับมันจึงเป็นปุ่มที่เห็นอยู่แต่กดไม่ติด ซึ่งแจ้งบั๊กได้ยากที่สุด
    local itemX = cx + third + GAP
    local chevW = 26

    -- ---- ช่องเดียว ความหมายตามหมวด (0.6.11 รถ · 0.6.16 สัตว์) ---------------
    -- หมวดรถ = ช่องนี้คือ "รุ่นรถ"  หมวด pet = "สัตว์"  หมวดอื่น = "ไอเทม"
    -- หลักเดียวกับที่ 0.6.0 ถอดปุ่ม Kind ออกแล้วอนุมานจากหมวดแทน
    -- (KR.kindOfCat) — ช่องที่ต้องกรอกน้อยลงหนึ่งช่อง คือช่องที่กรอกผิดไม่ได้หนึ่งช่อง
    local spMode = SPEC[KR.kindOfCat(KR.catKey(
        self.fields.cat and self.fields.cat:getInternalText() or ""))]

    local itemTxt = self.fields.item and self.fields.item:getInternalText() or ""

    if isSet then
        -- โหมดชุดไม่มี "ไอเทมของรายการ"  ของทั้งหมดอยู่ในบรรทัดข้างล่าง
        -- ช่องตรงนี้จึงว่าง  เอา RARE กับ VISIBLE ขึ้นมาอยู่แทน
        --
        -- ไม่ใช่เรื่องความสวย: โหมดชุดยาวกว่าโหมดชิ้นเดียวอยู่แล้ว การยุบหนึ่งแถว
        -- คือสิ่งที่ทำให้ชุดหกบรรทัดยังพอดีจอตอนผู้เล่นตั้ง UI scale 1.5
        -- (ด่านผังฟ้องตรงนี้จริง ๆ หลังจากมันถูกแก้ให้เปลี่ยน scale ได้)
        local hw = math.floor((third - chevW - 2 - GAP) / 2)
        U.text(self, KR.L("ของหายาก", "RARE"), itemX, cy, U.C.dim, U.F.xs)
        local rb2 = tag(self, itemX, cy + XH + 3, hw,
                        a.rare and KR.L("ใช่", "Yes") or KR.L("ไม่", "No"),
                        a.rare, self.mx, self.my)
        rb2.act = "rare"; self.admBtns[#self.admBtns + 1] = rb2

        U.text(self, KR.L("ผู้เล่นเห็น", "VISIBLE"), itemX + hw + GAP, cy, U.C.dim, U.F.xs)
        local vb2 = tag(self, itemX + hw + GAP, cy + XH + 3, hw,
                        a.enabled ~= false and KR.L("เปิดขาย", "On shelf")
                                            or KR.L("ซ่อนอยู่", "Hidden"),
                        a.enabled ~= false, self.mx, self.my)
        vb2.act = "vis"; self.admBtns[#self.admBtns + 1] = vb2
    else
    unitBox(self.fields.item, itemX, cy, third - chevW - 2,
            spMode and spMode.cap() or KR.L("ไอเทม", "ITEM"), nil, nil)
    do
        -- สถานะของสิ่งที่พิมพ์อยู่  ต้องรู้ก่อนกดบันทึก ไม่ใช่ตอนผู้เล่นซื้อแล้วของไม่เข้า
        local st, col
        if itemTxt == "" then
            st, col = KR.L("ยังไม่ได้ใส่", "empty"), U.C.dim
        elseif spMode then
            -- สามสถานะ ไม่ใช่สอง  "อ่านรายชื่อไม่ได้" ต้องไม่ถูกเขียนว่า "ไม่มีของชิ้นนี้"
            -- ไม่งั้นแอดมินจะนั่งแก้ชื่อที่ถูกอยู่แล้วทั้งวัน
            local k = specKnown(spMode, itemTxt)
            if k == true then st, col = spMode.okTxt(), U.C.good
            elseif k == false then st, col = spMode.noTxt(), U.C.bad
            else st, col = spMode.unTxt(), U.C.warn end
        elseif itemKnown(itemTxt) then
            st, col = KR.L("พบในเกม", "found"), U.C.good
        else
            st, col = KR.L("ไม่พบไอเทมนี้", "not in this build"), U.C.bad
        end
        U.text(self, st, itemX, cy + XH + 3 + BH + 2, col, U.F.xs)

        self.itemMenuY = cy + XH + 3 + BH
        local pb = tag(self, itemX + third - chevW, cy + XH + 3, chevW,
                       self.itemOpen and "^" or "v", self.itemOpen == true, self.mx, self.my)
        pb.act = "itempick"
        pb.menuX, pb.menuY = itemX, cy + XH + 3 + BH
        self.admBtns[#self.admBtns + 1] = pb
    end
    end

    unitBox(self.fields.cat, cx + (third + GAP) * 2, cy, third - chevW - 2,
            KR.L("หมวด", "CATEGORY"), nil, nil)
    local mb = tag(self, cx + (third + GAP) * 2 + third - chevW, cy + XH + 3, chevW, "v",
                   self.catMenu ~= nil, self.mx, self.my)
    mb.act = "catmenu"
    mb.menuX, mb.menuY = cx + (third + GAP) * 2, cy + XH + 3 + tagH()
    self.admBtns[#self.admBtns + 1] = mb

    cy = cy + XH + 3 + BH + XH + 6

    -- ==========================================================================
    -- ของในชุด  อยู่ในฟอร์มเลย ทีละบรรทัด  (0.6.14)
    --
    -- ของเดิมเป็นหน้าต่างซ้อนที่ต้องกดเปิด แล้วเพิ่มทีละชิ้นผ่านปุ่ม "Add"
    -- ซึ่งเป็นสามขั้นตอนสำหรับงานที่ควรเป็นขั้นตอนเดียว: พิมพ์ลงไปในบรรทัด
    --
    -- แสดงเท่าที่กรอกแล้ว บวกอีกหนึ่งบรรทัดว่างเสมอ  ฟอร์มจึงสั้นตอนชุดเล็ก
    -- และยาวขึ้นเองตอนของเยอะ โดยไม่ต้องมีปุ่ม "เพิ่มบรรทัด" ให้กดอีกปุ่ม
    -- ==========================================================================
    if isSet then
        a.setKinds = a.setKinds or {}

        -- ---- รูปกล่อง  ป้ายกับรูปอยู่บรรทัดเดียวกัน --------------------------
        -- โหมดชุดยาวอยู่แล้ว  ทุกบรรทัดที่ประหยัดได้คือบรรทัดที่ของข้างล่างไม่ต้องชนกัน
        local capW = U.w(KR.L("รูปกล่อง", "BOX"), U.F.xs) + 10
        local bs = math.max(22, math.min(34, math.floor((cw - capW - 11 * 3) / 12)))
        local bx0 = cx + capW
        U.text(self, KR.L("รูปกล่อง", "BOX"), cx, cy + math.floor((bs - XH) / 2),
               U.C.dim, U.F.xs)
        local byy = cy
        for i, id in ipairs(KR.BOXES) do
            local bx  = bx0 + (i - 1) * (bs + 3)
            local on  = (a.box == id)
            local hot = U.hit({ x = bx, y = byy, w = bs, h = bs }, self.mx, self.my)
            U.fill(self, bx, byy, bs, bs, on and U.C.bgSel or (hot and U.C.bgRow or U.C.slot))
            if on then U.border(self, bx, byy, bs, bs, U.C.accent) end
            local t = getTexture(KR.boxTex(id))
            if t then
                self:drawTextureScaled(t, bx + 2, byy + 2, bs - 4, bs - 4, 1, 1, 1, 1)
            else
                U.textC(self, id:sub(1, 1):upper() .. id:sub(-1), bx + bs / 2,
                        byy + math.floor((bs - XH) / 2), U.C.dim, U.F.xs)
            end
            self.admBtns[#self.admBtns + 1] =
                { x = bx, y = byy, w = bs, h = bs, act = "setbox", val = id }
        end
        cy = byy + bs + 6

        -- ---- บรรทัดของ --------------------------------------------------------
        local filled = 0
        for i = 1, KR.SET_MAX do
            local f = self.fields["setI" .. i]
            if f and (f:getInternalText() or "") ~= "" then filled = i end
        end
        local nShow = math.min(KR.SET_MAX, filled + 1)

        local kindW, qtyW, delW = 62, 58, 22
        local nameW = cw - kindW - qtyW - delW - chevW - GAP * 4

        for i = 1, nShow do
            local ry = cy + (i - 1) * (BH + 3)
            local spLine = SPEC[a.setKinds[i] or "item"]

            -- ปุ่มชนิด  เล็ก แต่อยู่ต้นบรรทัดที่มันคุมอยู่ ไม่ใช่ที่อื่น
            -- สามสถานะแล้ว (0.6.16)  กดวน ITEM -> CAR -> PET -> ITEM
            local lineCol = spLine and spLine.col() or U.C.line3
            local hotK = U.hit({ x = cx, y = ry, w = kindW, h = BH }, self.mx, self.my)
            U.fill(self, cx, ry, kindW, BH, hotK and U.C.bgRow or U.C.bgCard)
            U.border(self, cx, ry, kindW, BH, lineCol)
            U.textC(self, spLine and spLine.chip() or KR.L("ของ", "ITEM"),
                    cx + kindW / 2, ry + math.floor((BH - XH) / 2),
                    spLine and spLine.col() or U.C.mute, U.F.xs)
            self.admBtns[#self.admBtns + 1] =
                { x = cx, y = ry, w = kindW, h = BH, act = "setkind", val = i }

            local nx = cx + kindW + GAP
            U.fill(self, nx, ry, nameW, BH, U.C.bgDark)
            U.border(self, nx, ry, nameW, BH, U.C.line3)
            local f = self.fields["setI" .. i]
            if f then
                f:setX(nx + 5); f:setY(ry + 3)
                sizeBox(f, nameW - 10, BH - 6)
            end

            -- ปุ่มค้นของบรรทัดนี้  ลิสต์ผลค้นวาดท้ายสุดเพราะมันต้องทับทุกอย่าง
            local pb = tag(self, nx + nameW + 2, ry, chevW,
                           (a.setPick == i) and "^" or "v", a.setPick == i, self.mx, self.my)
            pb.act = "setpick"; pb.val = i
            pb.menuX, pb.menuY = nx, ry + BH
            self.admBtns[#self.admBtns + 1] = pb

            local qx = nx + nameW + 2 + chevW + GAP
            U.fill(self, qx, ry, qtyW, BH, U.C.bgDark)
            U.border(self, qx, ry, qtyW, BH, U.C.line3)
            local q = self.fields["setN" .. i]
            if q then
                q:setX(qx + 5); q:setY(ry + 3)
                sizeBox(q, qtyW - 10, BH - 6)
            end

            -- ลบบรรทัด  เฉพาะบรรทัดที่มีของอยู่จริง
            if f and (f:getInternalText() or "") ~= "" then
                local dx = qx + qtyW + GAP
                local hotD = U.hit({ x = dx, y = ry, w = delW, h = BH }, self.mx, self.my)
                U.fill(self, dx, ry, delW, BH, hotD and U.C.bad or U.C.bgCard)
                U.textC(self, "x", dx + delW / 2, ry + math.floor((BH - XH) / 2),
                        hotD and U.C.bgDark or U.C.mute, U.F.xs)
                self.admBtns[#self.admBtns + 1] =
                    { x = dx, y = ry, w = delW, h = BH, act = "setdel", val = i }
            end
        end

        -- ไม่ต้องสั่งซ่อนบรรทัดที่ยังไม่ถึงคิวเอง
        --
        -- ด่านสุดท้ายของเฟรมซ่อนทุกช่องที่ "ไม่ได้ถูกวางในเฟรมนี้" อยู่แล้ว
        -- (box.__krFrame == frameNo)  เขียนซ้ำตรงนี้คือโค้ดที่ไม่มีวันทำงาน
        -- และไม่มีด่านไหนพิสูจน์ได้ว่ามันยังถูกอยู่ — ลองถอดออกแล้วด่านยังเขียว

        cy = cy + nShow * (BH + 3) + 4
    end

    -- แถวสอง : ได้ครั้งละ / หายาก / เปิดขาย
    -- ชุดไม่มี "ได้ครั้งละ"  จำนวนอยู่ที่บรรทัดของแต่ละชิ้นแล้ว
    if not isSet then
        unitBox(self.fields.count, cx, cy, third, KR.L("ได้ครั้งละ", "PER BUY"),
                KR.L("ชิ้น", "pcs"), nil)
    end

    if isSet then
        -- แถวนี้ถูกยุบไปอยู่ข้างบนแล้วในโหมดชุด  เหลือแค่ขยับ cy ให้เท่ากัน
        cy = cy + XH + 3 + TH + XH + 6
    else
    U.text(self, KR.L("ของหายาก", "RARE"), cx + third + GAP, cy, U.C.dim, U.F.xs)
    local rb = tag(self, cx + third + GAP, cy + XH + 3, third,
                   a.rare and KR.L("ใช่", "Yes") or KR.L("ไม่", "No"), a.rare, self.mx, self.my)
    rb.act = "rare"; self.admBtns[#self.admBtns + 1] = rb
    U.text(self, KR.L("= กรอบทองในลิสต์", "= gold frame"), cx + third + GAP,
           cy + XH + 3 + TH + 2, U.C.dim, U.F.xs)

    U.text(self, KR.L("ผู้เล่นเห็น", "VISIBLE"), cx + (third + GAP) * 2, cy, U.C.dim, U.F.xs)
    local vb = tag(self, cx + (third + GAP) * 2, cy + XH + 3, third,
                   a.enabled ~= false and KR.L("เปิดขาย", "On the shelf")
                                       or KR.L("ซ่อนอยู่", "Hidden"),
                   a.enabled ~= false, self.mx, self.my)
    vb.act = "vis"; self.admBtns[#self.admBtns + 1] = vb
    U.text(self, a.enabled ~= false and KR.L("กดเพื่อซ่อน", "click to hide")
                                     or KR.L("ตั้งราคาไว้ได้ ยังไม่ขึ้นร้าน", "priced, not listed"),
           cx + (third + GAP) * 2, cy + XH + 3 + TH + 2,
           a.enabled ~= false and U.C.dim or U.C.bad, U.F.xs)

    cy = cy + XH + 3 + math.max(BH, TH) + XH + 6
    end

    -- ---- PRICE --------------------------------------------------------------
    cy = head("PRICE  ·  " .. KR.L("จ่ายได้กี่ทาง", "ways to pay"), U.C.cash)

    local curW  = math.max(72, U.w("CASH", U.F.s) + 34)
    local plusW = 18
    local fldW  = math.floor((cw - curW * 2 - plusW - 22) / 2)

    -- วาดเฉพาะแถวที่ใช้อยู่จริง บวกแถวว่างไว้ให้อีกหนึ่ง
    --
    -- ของเดิมวาดสี่แถวเสมอ กินไปราว 130px ทั้งที่ของเกือบทุกชิ้นในร้านมีทางจ่ายเดียว
    -- ที่ว่างที่ได้คืนมาคือที่ที่กลุ่ม STOCK/SALE/STALL ต้องใช้ตอนกาง
    -- แถวที่สี่ยังเข้าถึงได้เสมอ แค่โผล่ตอนที่สามถูกใช้แล้ว
    -- โหมดชุดไม่มีที่เหลือให้แถวราคาเปล่า ๆ  แสดงเท่าที่ใช้อยู่จริง
    -- อยากเพิ่มทางจ่ายก็สลับกลับไปโหมดชิ้นเดียวหนึ่งที เพิ่ม แล้วสลับกลับมา
    -- ซึ่งฟังดูงี่เง่า แต่ดีกว่าฟอร์มที่ปุ่มบันทึกถูกทับจนกดไม่ได้
    local spare = isSet and 0 or 1
    local used = 0
    for i = 1, 4 do
        if a.cur[i] ~= nil then used = i end
    end
    local rowsShown = math.max(1, math.min(4, used + spare))

    for i = 1, rowsShown do
        local rowH = math.max(BH, TH)
        local c1 = a.cur[i]
        local b2 = tag(self, cx, cy, curW, c1 and tostring(c1):upper() or "-",
                       c1 ~= nil, self.mx, self.my)
        b2.act, b2.row = "cur1", i; self.admBtns[#self.admBtns + 1] = b2
        if c1 then U.coin(self, c1, cx + 5, cy + math.floor((TH - 14) / 2), 14) end

        local x1 = cx + curW + 6
        U.fill(self, x1, cy, fldW, BH, U.C.bgDark)
        U.border(self, x1, cy, fldW, BH, U.C.line3)
        local f1 = self.fields["a" .. i]
        if f1 then
            f1:setX(x1 + 5); f1:setY(cy + 3)
            sizeBox(f1, fldW - 10, BH - 6)
        end

        local xp = x1 + fldW + 4
        U.textC(self, "+", xp + plusW / 2, cy + math.floor((rowH - LH) / 2), U.C.dim, U.F.s)

        local x2 = xp + plusW
        local c2 = a.cur2[i]
        local b3 = tag(self, x2, cy, curW, c2 and tostring(c2):upper() or "-",
                       c2 ~= nil, self.mx, self.my)
        b3.act, b3.row = "cur2", i; self.admBtns[#self.admBtns + 1] = b3
        if c2 then U.coin(self, c2, x2 + 5, cy + math.floor((TH - 14) / 2), 14) end

        local x3 = x2 + curW + 6
        U.fill(self, x3, cy, fldW, BH, U.C.bgDark)
        U.border(self, x3, cy, fldW, BH, U.C.line3)
        local f2 = self.fields["b" .. i]
        if f2 then
            f2:setX(x3 + 5); f2:setY(cy + 3)
            sizeBox(f2, fldW - 10, BH - 6)
        end

        cy = cy + rowH + 4
    end
    -- ประโยคนี้ยาวกว่าคอลัมน์ตอนผู้เล่นตั้ง UI scale 1.5  ด่านผังจับได้ที่สเกลนั้น
    -- (ที่ 1.0 มันพอดีสวย ๆ ซึ่งเป็นเหตุผลที่มันอยู่มาได้นาน)
    --
    -- ความยาวที่นับเป็น "ตัวอักษร" ไม่มีวันพอดีทุกสเกล เพราะฟอนต์โตตามสเกล
    -- ต้องวัดความกว้างจริงแล้วตัดบรรทัด  U.wrap ทำให้อยู่แล้ว ใช้มันสิ
    local payHint = U.wrap(
        KR.L("แต่ละแถวคือหนึ่งทางที่จ่ายได้  สองช่องในแถวเดียวกัน = ต้องจ่ายพร้อมกัน",
             "Each row is one way to pay. Two boxes on a row must be paid together."),
        U.F.xs, cw, 2)
    for hi = 1, #payHint do
        U.text(self, payHint[hi], cx, cy + (hi - 1) * XH, U.C.dim, U.F.xs)
    end
    cy = cy + XH * #payHint + GAP

    -- ---- STOCK / SALE / STALL  พับเก็บได้ทีละอัน ---------------------------
    --
    -- ทำไมต้องพับ  ไม่ใช่เรื่องความสวย แต่เพราะมันล้นจริง
    --
    -- ห้ากลุ่มกางพร้อมกันสูงกว่าพื้นที่ที่มี  ผลที่เจ้าของเซิร์ฟถ่ายมาคือ
    -- บรรทัดเตือน "Name is empty / No price set" ไปทับแถว RESTOCK / PER PLAYER
    -- และปุ่ม Clear / Add ไปทับกลุ่ม SALE  ส่วนกลุ่มล่างสุดตกขอบหน้าต่างหายไปเลย
    --
    -- รากของปัญหา: เนื้อหาไหลลงจากบน ส่วนปุ่มยึดจากขอบล่างขึ้นบน
    -- สองทิศทางนี้จะชนกันเสมอเมื่อเนื้อหายาวพอ  และ "เนื้อหายาวพอ" ขึ้นกับ UI scale
    -- ของผู้เล่นแต่ละคน = บั๊กที่เครื่องคนหนึ่งเห็นแต่อีกคนไม่เห็น
    --
    -- ทางแก้ที่ถูกคือทำให้เนื้อหา "สั้นเสมอ" ไม่ใช่ไปหาที่ให้มันเพิ่ม
    -- ของส่วนใหญ่ในร้านใช้แค่ BASIC กับ PRICE จริง ๆ (ตามที่เขียนไว้ตั้งแต่ตอนออกแบบ)
    -- สามกลุ่มนี้จึงเป็นหัวข้อที่กดกางทีละอัน กางได้ครั้งละหนึ่ง
    a.sect = a.sect or nil          -- nil = พับหมด

    local SECTS = {
        { id = "stock", cap = "STOCK", th = "มีเท่าไหร่",  en = "how many", col = U.C.hf },
        { id = "sale",  cap = "SALE",  th = "ลดราคา",      en = "discount", col = U.C.warn },
        { id = "place", cap = "STALL", th = "ขายที่ไหน",   en = "where",    col = U.C.good },
    }

    -- ยึดกลุ่มพับได้ไว้กับ "ขอบล่าง" เหมือนปุ่ม  ไม่ให้ไหลต่อจากเนื้อหาข้างบน
    --
    -- นี่คือหัวใจของการแก้ครั้งนี้  ของที่ไหลลงจากบนกับของที่ยึดจากล่าง
    -- จะชนกันเสมอเมื่อเนื้อหายาวพอ และ "ยาวพอ" ขึ้นกับ UI scale ของแต่ละคน
    -- พอทั้งสองฝั่งยึดจากล่างเหมือนกัน ระยะห่างระหว่างมันเป็นค่าคงที่ที่เราคุมได้
    local probPre = self:admProblems()
    local probPreH = (#probPre > 0) and (math.min(#probPre, 3) * (XH + 3) + 4) or 0
    local bodyH = (a.sect ~= nil) and (XH + 3 + math.max(BH, TH) + XH + 4) or 0
    local sectY = (y + h - 40) - probPreH - 10 - bodyH - (XH + 8) - 8

    -- ถ้าเนื้อหาข้างบนยาวจนจะทับ ให้กลุ่มถอยลงไปชิดล่างสุดเท่าที่ยังไม่ทับปุ่ม
    -- ดีกว่าปล่อยให้ซ้อนกันแล้วอ่านไม่ออกทั้งสองฝั่ง
    if sectY < cy then sectY = cy end
    cy = sectY

    -- หัวข้อสี่อันเรียงกันในแถวเดียว  กินที่แค่แถวเดียวตอนพับหมด
    -- อันที่สี่ (SET) ไม่ได้กางลงมา มันเปิดแผ่นลอยแทน  เหตุผลอยู่ที่ตัวจัดการคลิก
    local nSect = #SECTS + 1
    local sw2 = math.floor((cw - GAP * (nSect - 1)) / nSect)
    for i2, sc in ipairs(SECTS) do
        local sx = cx + (sw2 + GAP) * (i2 - 1)
        local on = (a.sect == sc.id)
        local hot = U.hit({ x = sx, y = cy, w = sw2, h = XH + 8 }, self.mx, self.my)
        U.fill(self, sx, cy, sw2, XH + 8, on and U.C.bgSel or (hot and U.C.bgRow or U.C.bgCard))
        U.fill(self, sx, cy, 3, XH + 8, sc.col)
        U.text(self, sc.cap, sx + 10, cy + 4, on and U.C.text or U.C.lite, U.F.xs)
        U.textR(self, on and "-" or "+", sx + sw2 - 8, cy + 4, U.C.mute, U.F.xs)
        self.admBtns[#self.admBtns + 1] =
            { x = sx, y = cy, w = sw2, h = XH + 8, act = "sect", val = sc.id }
    end
    cy = cy + XH + 8 + 8

    local q = math.floor((cw - GAP * 3) / 4)
    local function col(i2) return cx + (q + GAP) * (i2 - 1) end

    if a.sect == "stock" then
        unitBox(self.fields.stock, col(1), cy, q, KR.L("สต็อก", "STOCK"),
                KR.L("ชิ้น", "pcs"), KR.L("ว่าง = ไม่จำกัด", "blank = unlimited"))
        U.text(self, KR.L("เติมทุก", "RESTOCK"), col(2), cy, U.C.dim, U.F.xs)
        local b4 = tag(self, col(2), cy + XH + 3, q, a.restock, true, self.mx, self.my)
        b4.act = "restock"; self.admBtns[#self.admBtns + 1] = b4

        unitBox(self.fields.quota, col(3), cy, q, KR.L("คนละไม่เกิน", "PER PLAYER"),
                KR.L("ชิ้น", "pcs"), KR.L("ว่าง = ไม่จำกัด", "blank = unlimited"))
        U.text(self, KR.L("รีเซ็ตทุก", "RESETS"), col(4), cy, U.C.dim, U.F.xs)
        local b5 = tag(self, col(4), cy + XH + 3, q, a.qper, true, self.mx, self.my)
        b5.act = "qper"; self.admBtns[#self.admBtns + 1] = b5

    elseif a.sect == "sale" then
        unitBox(self.fields.salePct, col(1), cy, q, KR.L("ลด", "OFF"), "%",
                KR.L("ว่าง = ไม่ลด", "blank = no sale"))
        local mv = self.fields.saleHrs and tonumber(self.fields.saleHrs:getInternalText() or "")
        unitBox(self.fields.saleHrs, col(2), cy, q, KR.L("ลดนาน", "LASTS"),
                KR.L("นาที", "min"), KR.minsHint(mv) and ("= " .. KR.minsHint(mv)) or nil)
        U.text(self, KR.L("ตั้งลดแล้วของจะไปโผล่หน้า SALE ด้วย  ผู้เล่นที่เปิดร้านอยู่จะเห็นป้ายเด้ง",
                          "A discount also lists it on the SALE page and pings anyone in the shop."),
               col(3), cy + XH + 6, U.C.dim, U.F.xs)

    elseif a.sect == "place" then
        U.text(self, KR.L("ขายที่แผงไหน", "STALL"), cx, cy, U.C.dim, U.F.xs)
        local mName = KR.L("ร้านหลัก", "Main store")
        if a.market then
            local m = (d.markets or {})[a.market]
            mName = (m and m.name) or a.market
        end
        local b6 = tag(self, cx, cy + XH + 3, q * 2 + GAP, mName, a.market ~= nil,
                       self.mx, self.my)
        b6.act = "market"; self.admBtns[#self.admBtns + 1] = b6
        U.text(self, KR.L("ของที่ผูกกับแผง ซื้อได้เฉพาะตอนยืนอยู่ที่แผงนั้น",
                          "Stall listings can only be bought while standing at that stall."),
               cx + q * 2 + GAP * 2, cy + XH + 6, U.C.dim, U.F.xs)
    end

    -- ---- ปัญหาที่ต้องแก้ก่อนบันทึก ------------------------------------------
    --
    -- วางไว้ "เหนือปุ่ม" โดยยึดจากขอบล่างเหมือนปุ่ม  ไม่ใช่ไหลต่อจากเนื้อหา
    -- แล้วเนื้อหาข้างบนถูกบังคับให้สั้นพอด้วยการพับกลุ่ม จึงไม่มีทางชนกันอีก
    local prob = self:admProblems()
    local probH = (#prob > 0) and (math.min(#prob, 3) * (XH + 3) + 4) or 0
    local fy = y + h - 40
    if #prob > 0 then
        local py2 = fy - probH
        U.fill(self, cx, py2 - 2, cw, probH, U.C.bgCard)
        for i2 = 1, math.min(#prob, 3) do
            U.text(self, "!  " .. prob[i2], cx + 8, py2, U.C.bad, U.F.xs)
            py2 = py2 + XH + 3
        end
    end

    -- ---- ปุ่มล่าง  ยึดจากขอบล่าง ไม่ใช่จาก cy --------------------------------
    if a.edit then
        self.bAdmNew = U.btn(self, cx, fy, 120, 32, KR.L("เพิ่มใหม่", "New"), "neu", self.mx, self.my)
    end
    self.bAdmClear = U.btn(self, cx + cw - 250, fy, 120, 32, KR.L("ล้างฟอร์ม", "Clear"), "neu",
                           self.mx, self.my)
    self.bAdmSave  = U.btn(self, cx + cw - 120, fy, 120, 32,
                           a.edit and KR.L("บันทึก", "Save") or KR.L("เพิ่มของ", "Add"),
                           #prob == 0 and "pri" or "offb", self.mx, self.my)
    if #prob > 0 then self.bAdmSave = nil end

    -- ---- ลิสต์ผลค้นของบรรทัดในชุด  วาดท้ายสุดเพราะมันต้องทับทุกอย่าง ---------
    -- ใช้โครงเดียวกับลิสต์ของช่อง ITEM แต่สั้นกว่า เพราะบรรทัดมีที่ให้น้อยกว่า
    if isSet and a.setPick then
        local i  = a.setPick
        local f  = self.fields["setI" .. i]
        local q  = tostring(f and f:getInternalText() or "")
        local spPick = SPEC[a.setKinds[i] or "item"]
        local list = spPick and self:specPickList(spPick, q) or self:itemPickList(q)

        local rows, ROWS = {}, 6
        for _, t in ipairs(list) do
            if t ~= "" and #rows < ROWS then rows[#rows + 1] = t end
        end

        local anchor = nil
        for _, b in ipairs(self.admBtns) do
            if b.act == "setpick" and b.val == i then anchor = b end
        end
        if anchor then
            -- แถวในลิสต์ผลค้นมีสองบรรทัด (ชื่อที่คนอ่าน / ไอดีจริง)
            -- ความสูงต้องมาจาก "สองบรรทัดนั้น" ไม่ใช่จากความสูงของฟอนต์บรรทัดเดียว
            --
            -- ของเดิมใช้ LH + 8 ซึ่งพอที่ scale 1.0 แล้วเริ่มไม่พอที่ 1.25 ขึ้นไป
            -- ม็อกอัปที่ scale 1.5 เปิดโปงให้เห็น: บรรทัดล่างของแถวสุดท้ายถูกขอบแผงตัดครึ่ง
            -- และไอคอนของแถวว่างไปทับแถวถัดไป  ด่านผังเขียวสนิทตลอด เพราะมันตรวจ
            -- "ช่องกรอกกับปุ่ม" ไม่ได้ตรวจ "ตัวหนังสือที่ล้นออกนอกแผงของตัวเอง"
            local rh2 = math.max(26, LH + 8, XH * 2 + 8)
            local lx2, ly2 = anchor.menuX, anchor.menuY
            local lw2 = math.max(260, math.floor(cw * 0.55))
            local lh3 = math.max(rh2, #rows * rh2)

            self:cover(lx2, ly2, lw2, lh3)
            U.solid(self, lx2, ly2, lw2, lh3, U.C.bgDark)
            U.border(self, lx2, ly2, lw2, lh3, U.C.accent)
            if #rows == 0 then
                U.textC(self, spPick and spPick.emTxt()
                                     or KR.L("ไม่พบไอเทมที่ตรง", "nothing matches"),
                        lx2 + lw2 / 2, ly2 + math.floor((rh2 - XH) / 2), U.C.dim, U.F.xs)
            end
            for k = 1, #rows do
                local t   = rows[k]
                local ry2 = ly2 + (k - 1) * rh2
                local hot = U.hit({ x = lx2, y = ry2, w = lw2, h = rh2 }, self.mx, self.my)
                if hot then U.fill(self, lx2, ry2, lw2, rh2, U.C.bgRow) end
                U.slot(self, lx2 + 4, ry2 + 3, rh2 - 6,
                       spPick and specThingTex(spPick, t) or itemTex({ item = t }), false)
                -- ตัดด้วย "ความกว้างที่มีจริง" ไม่ใช่จำนวนตัวอักษรตายตัว
                -- 26 ตัวอักษรพอดีแผงที่ scale 1.0 แล้วล้นออกไป 10px ที่ 1.5
                -- ("Base.Screwdriver" คือแถวที่ด่านผังจับได้)  จำนวนตัวอักษร
                -- ไม่รู้จักขนาดฟอนต์ จึงตอบคำถามนี้ไม่ได้ตั้งแต่ต้น
                local tw2 = lw2 - rh2 - 10
                U.text(self, U.wrap(spPick and specLabel(spPick, t) or itemDisplay(t),
                                    U.F.xs, tw2, 1)[1],
                       lx2 + rh2 + 6, ry2 + 2, U.C.text, U.F.xs)
                U.text(self, U.wrap(t, U.F.xs, tw2, 1)[1],
                       lx2 + rh2 + 6, ry2 + 2 + XH, U.C.dim, U.F.xs)
                self.admBtns[#self.admBtns + 1] =
                    { x = lx2, y = ry2, w = lw2, h = rh2, act = "setfill", val = t,
                      line = i, top = true }
            end
        end
    end

    -- ---- รายการไอเทมที่ค้นเจอ  วาดท้ายสุดเพื่อให้ทับทุกอย่าง -----------------
    if self.itemOpen and not isSet then
        -- ---- ลิสต์ผลค้นไอเทม  เลื่อนได้ (0.6.11) ------------------------------
        --
        -- ของเดิม `shown = math.min(#list, 7)` แล้วจบ — ไม่มีทางเลื่อนเลย
        -- ผลคือของที่แมตช์ตัวที่ 8 เป็นต้นไป **กดไม่ถึงตลอดกาล**
        -- และมันไม่มีอะไรบอกด้วยว่ายังมีต่อ ลิสต์แค่จบห้วน ๆ ที่เจ็ดบรรทัด
        -- ผู้ใช้อ่านออกได้ทางเดียวว่า "ค้นแล้วไม่เจอ" ทั้งที่ของอยู่ในลิสต์
        --
        -- B42 มีไอเทมหลายพันชิ้น คำค้นสั้น ๆ อย่าง "bag" แมตช์เป็นร้อย
        -- เจ็ดบรรทัดจึงไม่ใช่ "พอดีแล้ว" แต่คือ "เห็นแค่เศษเสี้ยว"
        -- หมวดรถ = ลิสต์เดียวกันนี้เปลี่ยนเป็นรายชื่อรุ่นรถ
        -- ตัวลิสต์ยังเก็บ "ค่าที่จะเขียนลงช่อง" เหมือนเดิม  เปลี่ยนแค่ที่มาและวิธีวาดแถว
        local list = spMode and self:specPickList(spMode, itemTxt) or self:itemPickList(itemTxt)
        -- แถวในลิสต์ผลค้นมีสองบรรทัด (ชื่อที่คนอ่าน / ไอดีจริง)
        -- ความสูงต้องมาจาก "สองบรรทัดนั้น" ไม่ใช่จากความสูงของฟอนต์บรรทัดเดียว
        --
        -- ของเดิมใช้ LH + 8 ซึ่งพอที่ scale 1.0 แล้วเริ่มไม่พอที่ 1.25 ขึ้นไป
        -- ม็อกอัปที่ scale 1.5 เปิดโปงให้เห็น: บรรทัดล่างของแถวสุดท้ายถูกขอบแผงตัดครึ่ง
        -- และไอคอนของแถวว่างไปทับแถวถัดไป  ด่านผังเขียวสนิทตลอด เพราะมันตรวจ
        -- "ช่องกรอกกับปุ่ม" ไม่ได้ตรวจ "ตัวหนังสือที่ล้นออกนอกแผงของตัวเอง"
        local rh2  = math.max(26, LH + 8, XH * 2 + 8)
        local ROWS = 7
        local shown = math.min(#list, ROWS)
        local lx2 = itemX
        local lw2 = math.max(third, 220)
        local ly2 = self.itemMenuY or (y + 100)

        -- ค่าเลื่อนต้องถูกหนีบทุกเฟรม  ไม่ใช่แค่ตอนหมุนล้อ
        -- เพราะลิสต์สั้นลงได้ระหว่างที่เลื่อนค้างอยู่ (ผู้ใช้พิมพ์ต่อ = ผลค้นแคบลง)
        -- ถ้าไม่หนีบ จะเหลือลิสต์ว่างเปล่าทั้งที่มีของ ซึ่งอ่านเหมือนบั๊กพอดี
        -- พิมพ์ต่อ = ผลค้นเป็นคนละชุด  ต้องเด้งกลับไปบรรทัดแรกของชุดใหม่
        -- ไม่งั้นพิมพ์เพิ่มหนึ่งตัวแล้วลิสต์ค้างอยู่กลางเรื่องของผลค้นเก่า
        if self.itemFindLast ~= itemTxt then
            self.itemFindLast = itemTxt
            self.itemScroll = 0
        end

        self.itemMax = math.max(0, #list - ROWS)
        if (self.itemScroll or 0) > self.itemMax then self.itemScroll = self.itemMax end
        local off = math.floor(self.itemScroll or 0)

        local lh3 = math.max(rh2, shown * rh2)
        self:cover(lx2, ly2, lw2, lh3)
        U.solid(self, lx2, ly2, lw2, lh3, U.C.bgDark)
        U.border(self, lx2, ly2, lw2, lh3, U.C.accent)
        if shown == 0 then
            U.textC(self, spMode
                        and (#specRows(spMode) == 0 and spMode.nlTxt() or spMode.emTxt())
                        or KR.L("ไม่พบไอเทมที่ตรง", "nothing matches"),
                    lx2 + lw2 / 2, ly2 + math.floor((rh2 - XH) / 2), U.C.dim, U.F.xs)
        end
        for i = 1, shown do
            local t = list[i + off]
            if t == nil then break end
            local ry2 = ly2 + (i - 1) * rh2
            local hot = U.hit({ x = lx2, y = ry2, w = lw2, h = rh2 }, self.mx, self.my)
            if hot then U.fill(self, lx2, ry2, lw2, rh2, U.C.bgRow) end

            -- คิดเฉพาะแถวที่วาดจริง  ไม่ใช่ทั้งลิสต์
            -- คำค้นสั้น ๆ แมตช์ได้เป็นพัน  การเตรียม texture ให้ครบทุกแถวคือ
            -- งานที่ทิ้งทันทีเก้าสิบเก้าเปอร์เซ็นต์ ทุกเฟรม
            local top, sub, tex
            if spMode then
                top, sub, tex = specLabel(spMode, t), t, specThingTex(spMode, t)
            else
                top, sub, tex = itemDisplay(t), shortType(t), itemTex({ item = t })
            end

            U.slot(self, lx2 + 4, ry2 + 3, rh2 - 6, tex, false)
            -- เหตุผลเดียวกับลิสต์ของบรรทัดในชุด  วัดความกว้าง อย่านับตัวอักษร
            local tw3 = lw2 - rh2 - 10
            U.text(self, U.wrap(top, U.F.xs, tw3, 1)[1],
                   lx2 + rh2 + 6, ry2 + 2, U.C.text, U.F.xs)
            U.text(self, U.wrap(sub, U.F.xs, tw3, 1)[1],
                   lx2 + rh2 + 6, ry2 + 2 + XH, U.C.dim, U.F.xs)
            self.admBtns[#self.admBtns + 1] =
                { x = lx2, y = ry2, w = lw2, h = rh2, act = "itemset", val = t, top = true }
        end

        -- บอกว่ายังมีต่อ  แถบเลื่อนอย่างเดียวเล็กเกินกว่าจะสังเกตบนลิสต์เจ็ดแถว
        if self.itemMax > 0 then
            U.scrollbar(self, lx2 + lw2 - 4, ly2, lh3, #list, ROWS, off)
            U.textR(self, (off + shown) .. " / " .. #list,
                    lx2 + lw2 - 10, ly2 - XH - 2, U.C.dim, U.F.xs)
        end
    end
end

-- ---- แท็บ : แผงตลาด ------------------------------------------------------------
function KRShop:admStalls(x, y, lw, h, rx, rw)
    local a, d = self.adm, data()
    local list = {}
    for id, m in pairs(d.markets or {}) do list[#list + 1] = { id = id, m = m } end
    table.sort(list, function(p, q) return tostring(p.id) < tostring(q.id) end)

    if #list == 0 then
        U.emptyState(self, x, y, lw, h,
                     KR.L("ยังไม่มีแผง", "No stalls yet"),
                     KR.L("ไปยืนตรงที่ต้องการ แล้วคลิกขวา > AKA Mod > Fresh Market",
                          "Stand where you want it, right-click > AKA Mod > Fresh Market"))
    else
        -- ความสูงแถวต้องมาจากฟอนต์จริง  ไม่ใช่ 30 ตายตัว
        --
        -- แถวหนึ่งมีสองบรรทัด (ชื่อแผง + ไอดีกับพิกัด)  ตอนฟอนต์เป็น Small มันพอดี 30
        -- พอฟอนต์ทั้งม็อดขยับขึ้นหนึ่งขั้น สองบรรทัดรวมกันสูงกว่า 30 แล้วบรรทัดที่สอง
        -- ของแถวนี้ไปทับบรรทัดแรกของแถวถัดไป  (เจ้าของเซิร์ฟถ่ายรูปมา:
        -- "Stall m10 / Stall m4 / Stall m8" ซ้อนกันจนอ่านพิกัดไม่ออก)
        --
        -- นี่คือบั๊กชนิดเดียวกับที่เคยแก้ในลิสต์ของในร้านไปแล้วรอบหนึ่ง
        -- แต่แผงตลาดถูกลืม เพราะตอนนั้นไล่แก้ทีละจุดที่เห็นแทนที่จะไล่หาทุกจุดที่ใช้เลขตายตัว
        local rh = math.max(30, 6 + U.h(U.F.s) + U.h(U.F.xs) + 4)
        local cy = y
        for i = 1, #list do
            local it  = list[i]
            local on  = (a.stall == it.id)
            local hot = U.hit({ x = x, y = cy, w = lw, h = rh }, self.mx, self.my)
            if on then U.fill(self, x, cy, lw, rh, U.C.bgSel)
            elseif hot then U.fill(self, x, cy, lw, rh, U.C.bgRow) end
            if on then U.fill(self, x, cy, 2, rh, U.C.accent) end
            if i > 1 and not (on or hot) then U.hr(self, x, cy, lw) end

            local n = 0
            for _, e in pairs(d.catalog or {}) do if e.market == it.id then n = n + 1 end end
            local cnt = n .. " " .. KR.L("รายการ", "items")
            local right = x + lw - 10 - U.w(cnt, U.F.xs) - 10

            U.text(self, KR.trunc(it.m.name or it.id, 18), x + 8, cy + 4, U.C.text, U.F.s)
            U.text(self, tostring(it.id) .. "   " ..
                   math.floor(it.m.x or 0) .. ", " .. math.floor(it.m.y or 0) ..
                   ", " .. math.floor(it.m.z or 0),
                   x + 8, cy + 4 + U.h(U.F.s), U.C.dim, U.F.xs)
            U.textR(self, cnt, x + lw - 10,
                    cy + math.floor((rh - U.h(U.F.xs)) / 2), U.C.mute, U.F.xs)

            local b = { x = x, y = cy, w = lw, h = rh, act = "stall", id = it.id, m = it.m }
            self.admBtns[#self.admBtns + 1] = b
            cy = cy + rh
        end
    end

    U.fill(self, rx, y, rw, h, U.C.bgHead)
    local cx, cw = rx + 12, rw - 24
    if not a.stall then
        U.emptyState(self, rx, y, rw, h,
                     KR.L("เลือกแผงทางซ้าย", "Pick a stall on the left"), nil)
        self.bStallSave, self.bStallDel = nil, nil
        return
    end

    local m = (d.markets or {})[a.stall]
    if not m then a.stall = nil; return end

    U.text(self, KR.L("แผง  ", "Stall  ") .. a.stall, cx, y + 10, U.C.gold, U.F.m)
    local cy2 = y + 10 + U.h(U.F.m) + 8
    cy2 = fieldBox(self, self.fields.stallName, cx, cy2, cw, KR.L("ชื่อแผง", "Stall name"))

    U.text(self, KR.L("พิกัด  ", "At  ") .. string.format("%d, %d, %d",
           math.floor(m.x or 0), math.floor(m.y or 0), math.floor(m.z or 0)),
           cx, cy2, U.C.mute, U.F.s)
    cy2 = cy2 + 18
    U.text(self, KR.L("ถอดแผงแล้วของที่ผูกไว้จะกลับไปอยู่ร้านหลัก ไม่ได้ถูกลบ",
                      "Removing a stall moves its listings back to the main store"),
           cx, cy2, U.C.dim, U.F.s)

    local fy = y + h - 32
    self.bStallSave = U.btn(self, rx + rw - 260, fy, 120, 32, KR.L("เปลี่ยนชื่อ", "Rename"), "pri", self.mx, self.my)
    self.bStallDel  = U.btn(self, rx + rw - 132, fy, 120, 32, KR.L("ถอดแผง", "Remove"), "bad", self.mx, self.my)
end

-- ---- แท็บ : ผู้เล่น -------------------------------------------------------------
--
-- หน้านี้ตอบคำถามสองข้อที่แอดมินถามบ่อยที่สุด และของเดิมตอบไม่ได้สักข้อ
--   "มีใครติดปัญหาอยู่บ้าง"    -> แผงแดงบนสุด อ่านจากสถานะจริงในฐานข้อมูล
--   "คนนี้เกิดอะไรขึ้น"        -> กดชื่อแล้วเห็นบัญชีของเขาทั้งใบทางขวา
--
-- ทำไมแผงแดงต้องอ่านจากสถานะ ไม่ใช่จากคิวแจ้งเตือน
--   คนมักโดนล็อกตอนที่ไม่มีแอดมินออนไลน์เลยสักคน  ป้ายที่เด้งแล้วหายจะพาเรื่องนั้น
--   หายไปด้วย  แต่ c.shopLock ยังอยู่ในฐานข้อมูลจนกว่าจะมีคนปลด
--   แผงนี้จึงอ่านจากตรงนั้น = ไม่ว่าจะผ่านไปกี่วันหรือแอดมินคนไหนมาเปิด เรื่องยังอยู่
--   และเลขแดงบนแถบซ้ายผูกกับ "ยังล็อกอยู่กี่คน" ไม่ใช่ "ยังไม่ได้อ่านกี่อัน"
--   ตัวเลขที่กดดูแล้วหายทั้งที่ปัญหายังอยู่ คือตัวเลขที่สอนให้คนเลิกสนใจมัน
-- ค้นชื่อในรายชื่อผู้เล่น  (0.6.16)
--
-- ค้นแบบ "ตัวอักษรดิบ" ด้วย find(..., 1, true) ไม่ใช่แพตเทิร์น
-- เหตุผลไม่ใช่เรื่องความเร็ว แต่เพราะชื่อคนไทยมี - ( ) . ปนอยู่จริง
-- และในแพตเทิร์นของ Lua ตัวพวกนั้นแปลว่าอย่างอื่น  พิมพ์ชื่อตัวเองแล้วหาไม่เจอ
-- คือบั๊กที่คนเจอจะรายงานว่า "ช่องค้นหาพัง" ซึ่งไม่ผิด
--
-- lower() ปลอดภัยกับไทย  ไบต์ UTF-8 ของไทยมีค่า >= 0x80 ทั้งหมด
-- string.lower แตะเฉพาะ a-z จึงไม่ไปทำให้ไบต์ไทยเพี้ยน
local function peopleMatch(pr, q)
    if q == "" then return true end
    local hay = (tostring(pr.disp or "") .. " " .. tostring(pr.key or "")):lower()
    return hay:find(q, 1, true) ~= nil
end

function KRShop:admPeople(x, y, lw, h, rx, rw)
    local a = self.adm
    local all = data().players or {}

    local q = ""
    if self.fields and self.fields.peopleFind then
        q = tostring(self.fields.peopleFind:getInternalText() or "")
        q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")
    end

    -- กรองเฉพาะ "รายชื่อทั้งหมด" ที่อยู่ล่างช่องค้นหา
    -- แผงแดงกับแถบเหลืองไม่กรอง  มันคือของที่ต้องเห็นไม่ว่ากำลังค้นอะไรอยู่
    -- (ค้นชื่อคนหนึ่งอยู่ แล้วแผงเตือนคนที่ติดลบหายไป คือการซ่อนเรื่องด่วนด้วยอุบัติเหตุ)
    local list = all
    if q ~= "" then
        list = {}
        for i = 1, #all do
            if peopleMatch(all[i], q) then list[#list + 1] = all[i] end
        end
    end

    -- แยกคนออกเป็นสามกอง  กองแรกสองกองคือคนที่ต้องมีมนุษย์มาดู
    local locked, watch = {}, {}
    for i = 1, #all do
        local pr = all[i]
        if pr.locked then locked[#locked + 1] = pr
        elseif pr.frozen or (pr.missed or 0) > 0 then watch[#watch + 1] = pr end
    end

    local XH  = U.h(U.F.xs)
    local rh  = math.max(26, U.h(U.F.s) + 8)
    local cy  = y

    -- ---- แผงแดง : ถูกล็อกอยู่ -----------------------------------------------
    if #locked > 0 then
        local ph = XH + 4 + math.min(#locked, 4) * rh + 6
        U.fill(self, x, cy, lw, ph, U.C.bgCard)
        U.border(self, x, cy, lw, ph, U.C.bad)
        U.fill(self, x, cy, 3, ph, U.C.bad)

        U.text(self, KR.L("ต้องจัดการ  ·  ถูกล็อกอยู่ ", "NEEDS YOU  ·  locked ") .. #locked,
               x + 10, cy + 3, U.C.bad, U.F.xs)
        local ry = cy + XH + 6

        for i = 1, math.min(#locked, 4) do
            local pr  = locked[i]
            local hot = U.hit({ x = x, y = ry, w = lw, h = rh }, self.mx, self.my)
            if hot then U.fill(self, x + 3, ry, lw - 3, rh, U.C.bgRow) end

            U.fill(self, x + 10, ry + math.floor(rh / 2) - 3, 6, 6,
                   pr.online and U.C.good or U.C.off)
            U.text(self, KR.trunc(pr.disp or pr.key, 14), x + 24,
                   ry + math.floor((rh - U.h(U.F.s)) / 2), U.C.text, U.F.s)

            -- ยอดติดลบคือตัวเลขที่ตอบว่า "หนักแค่ไหน" ได้ในตัวเดียว
            if pr.bal then
                U.text(self, money(pr.bal), x + math.floor(lw * 0.46),
                       ry + math.floor((rh - U.h(U.F.s)) / 2), U.C.bad, U.F.s)
            end

            local ub = U.btn(self, x + lw - 84, ry + 1, 78, rh - 2,
                             KR.L("ปลดล็อก", "Unlock"), "ok", self.mx, self.my)
            ub.act, ub.who = "unlockone", pr.key
            self.admBtns[#self.admBtns + 1] = ub

            self.admBtns[#self.admBtns + 1] =
                { x = x, y = ry, w = lw - 88, h = rh, act = "person",
                  disp = pr.disp, key = pr.key }
            ry = ry + rh
        end

        if #locked > 4 then
            U.textR(self, "+" .. (#locked - 4), x + lw - 8, cy + 3, U.C.bad, U.F.xs)
        end
        cy = cy + ph + 6
    end

    -- ---- แถบเหลือง : เฝ้าดู -------------------------------------------------
    --
    -- ของที่ผมเพิ่มเอง  คนที่ผิดนัดแล้วแต่ยังไม่ถึงเส้น -5,000
    -- เตือนตอนนี้ยังคุยกันได้  ปล่อยไว้อีกสองสามวันก็กลายเป็นแถวแดง
    if #watch > 0 then
        local wh = XH + 6
        U.fill(self, x, cy, lw, wh, U.C.bgCard)
        U.fill(self, x, cy, 3, wh, U.C.warn)
        local names = {}
        for i = 1, math.min(#watch, 3) do names[#names + 1] = watch[i].disp or watch[i].key end
        U.text(self, KR.L("เฝ้าดู  ", "WATCH  ") .. table.concat(names, ", ") ..
                     (#watch > 3 and (" +" .. (#watch - 3)) or ""),
               x + 10, cy + 2, U.C.warn, U.F.xs)
        cy = cy + wh + 6
    end

    -- ---- ช่องค้นชื่อ  (0.6.16) ----------------------------------------------
    --
    -- "ตอน admin ดู players ใน HF shop ให้ search ชื่อได้" — คำสั่งตรงจากเจ้าของเซิร์ฟ
    -- เซิร์ฟที่มีคนเล่นเป็นร้อย รายชื่อยาวเกินกว่าจะเลื่อนหาทีละคน
    local lbl = KR.L("ค้นชื่อผู้เล่น", "FIND A PLAYER")
    if q ~= "" then
        lbl = lbl .. "   " .. #list .. "/" .. #all
    end
    local afterFind = fieldBox(self, self.fields.peopleFind, x, cy, lw - 4, lbl)
    cy = afterFind

    -- ---- รายชื่อทั้งหมด -----------------------------------------------------
    local listH = math.max(60, h - (cy - y))

    -- กันการเลื่อนค้างเกินท้ายลิสต์  onTextChange รีเซ็ตให้อยู่แล้วตอนพิมพ์
    -- แต่ลิสต์ยังสั้นลงได้เองจาก sync ที่วิ่งเข้ามาโดยไม่มีใครพิมพ์อะไร
    local maxScroll = math.max(0, #list * rh - listH)
    if (self.scroll or 0) > maxScroll then self.scroll = maxScroll end

    if #list == 0 then
        local msg = (q ~= "")
            and KR.L("ไม่มีชื่อที่ตรงกับที่ค้น", "No name matches that search")
            or  KR.L("ยังไม่มีใครเข้าเซิร์ฟ", "No players yet")
        U.emptyState(self, x, cy, lw, listH, msg, nil)
    else
        self:setStencilRect(x, cy, lw, listH)
        local ry = cy - self.scroll
        for i = 1, #list do
            local pr = list[i]
            if ry + rh > cy and ry < cy + listH then
                local on  = (a.personKey == pr.key)
                local hot = U.hit({ x = x, y = ry, w = lw, h = rh }, self.mx, self.my)
                if on then U.fill(self, x, ry, lw, rh, U.C.bgSel)
                elseif hot then U.fill(self, x, ry, lw, rh, U.C.bgRow) end
                if on then U.fill(self, x, ry, 2, rh, U.C.accent) end
                if i > 1 and not (on or hot) then U.hr(self, x, ry, lw) end

                local ty2 = ry + math.floor((rh - U.h(U.F.s)) / 2)
                U.fill(self, x + 8, ry + math.floor(rh / 2) - 3, 5, 5,
                       pr.online and U.C.good or U.C.off)
                U.text(self, KR.trunc(pr.disp or pr.key, 16), x + 20, ty2, U.C.text, U.F.s)

                if pr.locked or pr.frozen then
                    local tg = pr.locked and KR.L("ล็อก", "LOCKED") or KR.L("แช่แข็ง", "FROZEN")
                    local tw3 = U.w(tg, U.F.xs) + 10
                    U.fill(self, x + lw - 88 - tw3, ry + 4, tw3, U.h(U.F.xs) + 4,
                           pr.locked and U.C.bad or U.C.warn)
                    U.textC(self, tg, x + lw - 88 - tw3 / 2, ry + 5, U.C.bgDark, U.F.xs)
                end
                U.coin(self, KR.CUR.HF, x + lw - 78, ty2 + 1, 12)
                U.textR(self, tostring(pr.hf or 0), x + lw - 10, ty2, U.C.hf, U.F.s)

                self.admBtns[#self.admBtns + 1] =
                    { x = x, y = ry, w = lw, h = rh, act = "person",
                      disp = pr.disp, key = pr.key }
            end
            ry = ry + rh
        end
        self:clearStencilRect()
        U.scrollbar(self, x + lw - 3, cy, listH, #list * rh, listH, self.scroll)
    end

    -- ---- ฝั่งขวา ------------------------------------------------------------
    U.fill(self, rx, y, rw, h, U.C.bgHead)
    local cx, cw = rx + 12, rw - 24

    -- บัญชีรายคน  โผล่เมื่อเลือกคนแล้วและข้อมูลของ "คนคนนั้น" มาถึงแล้ว
    -- เทียบคีย์ก่อนวาดเสมอ  คำตอบของคนก่อนหน้าที่มาช้ากว่าจะได้ไม่โผล่ใต้ชื่อคนใหม่
    local av = (KRClient or {}).accView
    local accH = 0
    if a.personKey and av and av.key == a.personKey then
        accH = self:drawAccView(cx, y + 10, cw, h - 150, av)
    elseif a.personKey then
        U.text(self, KR.L("กำลังเปิดบัญชีของ ", "Opening ") .. tostring(a.person) .. "...",
               cx, y + 12, U.C.mute, U.F.s)
        accH = U.h(U.F.s) + 10
    else
        -- ตัดบรรทัดตามคอลัมน์จริง  ประโยคนี้ยาวเลยขอบหน้าต่างที่ UI scale 1.5
        -- (ด่านผังจับได้ทันทีที่มันเริ่มวาดแท็บแอดมินครบทุกแท็บ)
        local hint = U.wrap(KR.L("กดชื่อผู้เล่นทางซ้ายเพื่อเปิดบัญชีของเขา",
                                 "Click a name on the left to open their account"),
                            U.F.s, cw, 2)
        for hi = 1, #hint do
            U.text(self, hint[hi], cx, y + 12 + (hi - 1) * U.h(U.F.s), U.C.mute, U.F.s)
        end
        accH = U.h(U.F.s) * #hint + 10
    end

    -- ---- แถวเติม/หักเงิน  ยึดจากขอบล่างเสมอ ---------------------------------
    local BH  = boxH()
    local TH  = tagH()
    local fy  = y + h - 32
    local gy  = fy - math.max(BH, TH) - 10
    local gl  = gy - XH - 3

    -- ---- ประวัติของคนที่เลือกไว้  (0.6.16) ----------------------------------
    --
    -- "แสดงประวัติให้ admin ดูด้วยว่าแต่ละคนซื้ออะไรไป" — คำสั่งตรงจากเจ้าของเซิร์ฟ
    --
    -- ใช้ **ตารางตัวเดียวกัน** กับที่ผู้เล่นเห็นในหน้า Account ไม่ได้เขียนตัวที่สอง
    -- ตารางที่สองคือตารางที่จะขาดคอลัมน์ที่ตัวแรกเพิ่งได้มา ในวันที่ไม่มีใครสังเกต
    self.logRectAdm = nil
    if a.personKey and av and av.key == a.personKey then
        local hy = y + 10 + accH + 10
        local hh = (gl - XH - 10) - hy
        if hh > 90 then
            self.logRectAdm = { x = cx, y = hy, w = cw, h = hh }
            self:accHistory(cx, hy, cw, hh, av, "adm")
        end
    end

    U.text(self, KR.L("เติมหรือหักเงินให้คนที่เลือกไว้", "ADJUST THE SELECTED PLAYER"),
           cx, gl - XH - 4, U.C.dim, U.F.xs)

    local third = math.floor((cw - 20) / 3)
    U.text(self, KR.L("สกุล", "CURRENCY"), cx, gl, U.C.dim, U.F.xs)
    local b = tag(self, cx, gy, third, tostring(a.gcur):upper(), true, self.mx, self.my)
    b.act = "gcur"; self.admBtns[#self.admBtns + 1] = b

    fieldBox(self, self.fields.grantAmt, cx + third + 10, gl, third,
             KR.L("จำนวน  ใส่ลบเพื่อหัก", "AMOUNT  minus to take"))
    fieldBox(self, self.fields.grantWhy, cx + (third + 10) * 2, gl, third,
             KR.L("เหตุผล  บังคับ", "REASON  required"))

    self.bGrant = U.btn(self, rx + rw - 132, fy, 120, 32, KR.L("ยืนยัน", "Apply"), "pri",
                        self.mx, self.my)

    -- ปุ่มปลดล็อกของคนที่เลือกไว้  อยู่ติดกับปุ่มยืนยันเพราะเป็นเรื่องเดียวกัน
    -- ในสายตาแอดมิน: "คนนี้มีปัญหาเรื่องเงิน ต้องทำอะไรสักอย่างให้เขา"
    -- ไล่จาก all ไม่ใช่ list  คนที่เลือกไว้อาจถูกช่องค้นหากรองออกไปแล้ว
    -- แต่บัญชีของเขายังเปิดอยู่ทางขวา  ปุ่มปลดล็อกหายไปเพราะพิมพ์ค้นคนอื่น
    -- คืออาการที่อธิบายไม่ถูกว่าเกิดจากอะไร
    local lockedNow = false
    for _, pr in ipairs(all) do
        if pr.locked and pr.key == a.personKey then lockedNow = true end
    end
    if lockedNow then
        self.bUnlock = U.btn(self, cx, fy, 180, 32,
                             KR.L("ปลดล็อกร้านให้ ", "Unlock ") .. tostring(a.person),
                             "ok", self.mx, self.my)
    else
        self.bUnlock = nil
    end

    -- ปุ่มดูมุมผู้เล่นย้ายไปอยู่แถวแท็บแล้ว  เห็นได้จากทุกแท็บ ไม่ใช่แค่แท็บนี้
end

-- ------------------------------------------------------------------------------
-- บัญชีของผู้เล่นหนึ่งคน  แอดมินอ่านอย่างเดียว
--
-- คืนความสูงที่ใช้ไปจริง  ผู้เรียกเอาไปวางของถัดไปต่อ
-- ทุกตัวเลขมาจากแพ็กเก็ต ACC_VIEW ที่ขอไปตอนกดชื่อ ไม่ได้เกาะไปกับ sync
-- (sync วิ่งทุกสองวินาทีให้ทุกคน  การแนบข้อมูลเต็มของผู้เล่นอีกคนไปกับมัน
--  คือการจ่ายค่าแบนด์วิดท์ตลอดเวลาเพื่อของที่แอดมินเปิดดูนาน ๆ ครั้ง)
-- ------------------------------------------------------------------------------
function KRShop:drawAccView(x, y, w, h, av)
    local XH = U.h(U.F.xs)
    local SH = U.h(U.F.s)
    local cy = y

    -- ---- หัว ----------------------------------------------------------------
    U.fill(self, x, cy + math.floor(U.h(U.F.m) / 2) - 3, 7, 7, av.online and U.C.good or U.C.off)
    U.text(self, tostring(av.disp or av.key), x + 14, cy, U.C.text, U.F.m)
    local nx = x + 14 + U.w(tostring(av.disp or av.key), U.F.m) + 10

    if av.locked then
        local tg = KR.L("ร้านถูกล็อก", "SHOP LOCKED")
        local tw2 = U.w(tg, U.F.xs) + 10
        U.fill(self, nx, cy + 3, tw2, XH + 4, U.C.bad)
        U.textC(self, tg, nx + tw2 / 2, cy + 4, U.C.bgDark, U.F.xs)
    elseif av.frozen then
        local tg = KR.L("ถูกแช่แข็ง", "FROZEN")
        local tw2 = U.w(tg, U.F.xs) + 10
        U.fill(self, nx, cy + 3, tw2, XH + 4, U.C.warn)
        U.textC(self, tg, nx + tw2 / 2, cy + 4, U.C.bgDark, U.F.xs)
    end

    U.textR(self, av.online and KR.L("ออนไลน์อยู่", "online now")
                             or KR.L("ออฟไลน์", "offline"),
            x + w, cy + 4, U.C.dim, U.F.xs)
    cy = cy + U.h(U.F.m) + 10

    -- ---- ยอดสี่ช่อง ---------------------------------------------------------
    local q = math.floor((w - 24) / 4)
    local function box(i, cap, val, col)
        local bx = x + (q + 8) * (i - 1)
        U.fill(self, bx, cy, q, XH + SH + 12, U.C.bgCard)
        U.text(self, cap, bx + 8, cy + 4, U.C.dim, U.F.xs)
        U.text(self, val, bx + 8, cy + 4 + XH + 2, col, U.F.s)
    end
    box(1, KR.L("เงินสด", "CASH"),
        av.cash and money(av.cash) or "-",
        (av.cash or 0) < 0 and U.C.bad or U.C.cash)
    box(2, "HF", tostring(av.hf or 0), U.C.hf)
    box(3, KR.L("หนี้ค้าง", "OWED"),
        (av.owed or 0) > 0 and money(av.owed) or "-",
        (av.owed or 0) > 0 and U.C.warn or U.C.mute)
    box(4, KR.L("ผิดนัด", "MISSED"),
        tostring(av.missed or 0),
        (av.missed or 0) > 0 and U.C.bad or U.C.mute)
    cy = cy + XH + SH + 12 + 10

    -- ---- สรุปเรื่องที่ต้องรู้ ------------------------------------------------
    local function line(cap, val, col)
        if cy + XH > y + h then return end
        U.text(self, cap, x, cy, U.C.dim, U.F.xs)
        U.textR(self, val, x + w, cy, col or U.C.lite, U.F.xs)
        cy = cy + XH + 4
    end

    if av.plan then
        line(KR.L("ยอดกู้", "Loan taken"), money(av.plan.amount or 0))
        if av.plan.nextAt then
            local left = (tonumber(av.plan.nextAt) or 0) - (tonumber(av.now) or 0)
            line(KR.L("งวดถัดไปอีก", "Next instalment in"),
                 left > 0 and KR.fmtDur(left) or KR.L("เลยกำหนดแล้ว", "overdue"),
                 left > 0 and U.C.lite or U.C.bad)
        end
    else
        line(KR.L("เงินกู้", "Loan"), KR.L("ไม่มีสัญญา", "none"))
    end

    line(KR.L("ช่องประมูลที่มี", "Auction slots"), tostring(av.slots or 1))
    if (av.lots or 0) > 0 then
        line(KR.L("ล็อตที่เปิดอยู่", "Open lots"), tostring(av.lots))
    end
    if (av.owing or 0) > 0 then
        line(KR.L("ค้างจ่ายส่วนที่เหลือ", "Auction balance unpaid"),
             tostring(av.owing) .. KR.L(" ล็อต", " lot(s)"), U.C.warn)
    end
    if (av.waiting or 0) > 0 then
        line(KR.L("คำขอแพ็ก HF ที่รออยู่", "HF pack requests waiting"),
             tostring(av.waiting), U.C.warn)
    end
    if av.lockedAt then
        local ago = (tonumber(av.now) or 0) - (tonumber(av.lockedAt) or 0)
        line(KR.L("โดนล็อกมาแล้ว", "Locked for"), KR.fmtDur(math.max(0, ago)), U.C.bad)
    end

    -- ---- ประวัติ ----------------------------------------------------------
    --
    -- 0.6.16 — ของเดิมอยู่ตรงนี้ และมัน **ไม่เคยแสดงยอดเลยสักครั้ง**
    --
    -- มันอ่าน r.name กับ r.amount  แต่ S.logSpend เก็บเป็น r.n / r.a / r.cur
    -- ชื่อจึงตกไปใช้ fallback เป็น r.k (ชนิดรายการ) และยอดเป็น nil เสมอ
    -- = แอดมินเห็นคำว่า "buy buy buy" หกบรรทัดโดยไม่มีตัวเลขสักตัว
    --
    -- ไม่มี error ไม่มี log ไม่มีอะไรฟ้อง เพราะการอ่านฟิลด์ที่ไม่มีใน Lua คือ nil เฉย ๆ
    -- **ตารางที่วาดออกมาได้โดยไม่มีข้อมูล คือบั๊กที่ไม่มีวันมีใครแจ้ง**
    --
    -- ตอนนี้ประวัติเต็ม ๆ ถูกวาดโดย admPeople ด้านล่างแผงนี้ ด้วยตารางตัวเดียว
    -- กับที่ผู้เล่นเห็นในหน้า Account — ครบทุกสกุล กรองได้ เลื่อนได้
    return cy - y
end


-- ------------------------------------------------------------------------------
-- วาด : หน้าต่างยืนยันการซื้อ
--
-- เขียนใหม่ทั้งหมดในรอบนี้  ของเดิมใช้ตัวเลขตายตัวเกือบทุกจุด
--   pw = 400 คงที่          -> ชื่อของยาว ๆ ล้นออกนอกกล่อง
--   หัวกล่องสูง 48 คงที่    -> ชื่อ (ฟอนต์ Large) + หมวด (ฟอนต์ Medium) รวมกันสูงกว่านั้น
--                              หมวดจึงไปทับแถวหัวคอลัมน์ที่ py+52  (ผู้เล่นถ่ายรูปมาให้ดู)
--   c2 = c3 - 104 คงที่     -> ราคาหลักหมื่นชนคอลัมน์ "เหลือหลังจ่าย"
--
-- รอบนี้ทุกความสูง/ความกว้างวัดจากฟอนต์จริงด้วย U.w / U.h
-- และเพิ่มบรรทัดสรุป "คุณกำลังจะจ่าย ..." ก่อนปุ่มยืนยัน
-- เพราะปุ่มเดียวที่เขียนว่า Confirm ไม่ได้บอกว่ากำลังจะเสียอะไรไปเท่าไร
-- ------------------------------------------------------------------------------
-- ==============================================================================
-- ของในชุด  (0.6.12)
--
-- **คนต้องเห็นของก่อนจ่าย**  ชุดที่ต้องซื้อก่อนถึงจะรู้ว่ามีอะไรอยู่ข้างใน
-- ไม่ใช่ชุด มันคือการพนัน  และร้านนี้ไม่ได้ขายการพนัน
--
-- แผงนี้จึงเป็นรายการอ่านอย่างเดียว: รูป ชื่อ จำนวน ครบทุกบรรทัด ไม่มีอะไรถูกย่อ
-- ปุ่มเดียวที่มีคือปิด  การซื้ออยู่ที่แถวในร้านเหมือนเดิม ไม่ย้ายมาที่นี่
-- (ปุ่มซื้อสองที่ = สองเส้นทางที่ต้องแก้เท่ากันตอนมีบั๊ก)
-- ==============================================================================
function KRShop:drawSetView(w, h)
    if not self.setView then return end

    local e = (data().catalog or {})[self.setView]
    if not e or not KR.isSet(e) then self.setView = nil; return end

    local XH2, SH2 = U.h(U.F.xs), U.h(U.F.s)
    local rowH = math.max(40, SH2 + XH2 + 12)
    local n    = #e.set

    U.fill(self, 0, 0, w, h, U.C.bgDark, 0.74)

    local pw = math.min(math.floor(w * 0.6), 520)
    local capH = U.capH(true)
    local ph = capH + n * rowH + 12 + 34 + 12
    local px = math.floor((w - pw) / 2)
    local py = math.floor((h - ph) / 2)

    -- แผ่นทึบก่อน  U.fill ของแผงเป็นแบบโปร่ง (U.OPACITY) ซึ่งถูกสำหรับแผงในหน้า
    -- แต่ผิดสำหรับของที่ลอยอยู่ข้างบน ตัวหนังสือข้างหลังจะทะลุขึ้นมาปนกันจนอ่านไม่ออก
    U.solid(self, px, py, pw, ph, U.C.bgHead)

    local cy = U.panel(self, px, py, pw, ph, {
        bg = U.C.bgHead, accent = U.C.gold, line = U.C.gold,
        cap = KR.L("ของในชุด", "WHAT IS IN THIS SET"), capCol = U.C.gold,
        capRight = KR.trunc(e.name or e.id, 28),
        pad = 6,
    })

    for i = 1, n do
        local ln = e.set[i]
        local ry = cy + (i - 1) * rowH
        if i % 2 == 0 then U.fill(self, px + 6, ry, pw - 12, rowH, U.C.bgRow, 0.7) end

        -- บรรทัดในชุดเป็นได้สามอย่าง  ไอเทม / รถ / สัตว์  (0.6.16)
        -- หาก่อนว่าบรรทัดนี้เป็นของชนิดไหน แล้วค่อยวาด  ไม่ใช่ถามทีละชนิดตอนวาด
        local spLn, idLn = nil, ln.item
        for _, kk in ipairs(SPEC_ORDER) do
            local sp = SPEC[kk]
            if ln[sp.field] then spLn, idLn = sp, ln[sp.field] end
        end

        local isz = rowH - 10
        U.slot(self, px + 12, ry + 5, isz,
               spLn and specThingTex(spLn, idLn) or itemTex({ item = ln.item }), false)

        local tx = px + 12 + isz + 10
        local nm = spLn and (spLn.cap() .. ": " .. specLabel(spLn, idLn))
                        or itemDisplay(ln.item)
        U.text(self, KR.trunc(nm, 30), tx, ry + 5, U.C.text, U.F.s)
        U.text(self, KR.trunc(idLn or "", 34), tx, ry + 5 + SH2, U.C.dim, U.F.xs)

        local cnt = math.max(1, math.floor(tonumber(ln.n) or 1))
        U.textR(self, "x" .. cnt, px + pw - 14, ry + math.floor((rowH - SH2) / 2),
                cnt > 1 and U.C.gold or U.C.mute, U.F.s)
    end

    local by = py + ph - 34 - 8
    local b = U.btn(self, px + pw - 120 - 10, by, 120, 30,
                    KR.L("ปิด", "Close"), "neu", self.mx, self.my)
    b.act = "setclose"
    self.rowBtns[#self.rowBtns + 1] = b
end

function KRShop:drawPay(w, h)
    local p = self.pay
    if not p then return end
    local d   = data()
    local ts  = nowTs()
    local bal = d.bal or {}

    U.fill(self, 0, 0, w, h, U.C.bgDark, 0.74)

    local fs, fm = U.F.s, U.F.m
    local hs, hm = U.h(fs), U.h(fm)

    -- ---- ความกว้าง  วัดจากของจริงทุกชิ้นแล้วเอาที่กว้างสุด --------------------
    local nameW = U.w(p.entry.name or p.entry.id, fm)
    local lblLeft = KR.L("เหลือหลังจ่าย", "Left after")

    local priceW, leftW = U.w(KR.L("ราคา", "Price"), fs), U.w(lblLeft, fs)
    for i = 1, #p.opts do
        local need = KR.optionCost(p.opts[i], p.entry, ts)
        for j = 1, #p.opts[i] do
            local part = p.opts[i][j]
            local amt  = KR.applyDiscount(part.cur, part.price, KR.discountBp(p.entry, ts))
            priceW = math.max(priceW, U.w(KR.fmtPrice(part.cur, amt):gsub("^%S+%s", ""), fm))
            local have = tonumber(bal[part.cur]) or 0
            local left = have - (need[part.cur] or 0)
            local s = (left >= 0) and fmtNum(part.cur, left)
                                  or (KR.L("ขาด ", "Short ") .. fmtNum(part.cur, -left))
            leftW = math.max(leftW, U.w(s, fs))
        end
    end

    local curColW = 130                       -- เหรียญ + ชื่อสกุล + เครื่องหมาย +
    local pw = curColW + priceW + leftW + 90
    pw = math.max(430, math.min(pw, math.max(360, w - 80), math.max(360, nameW + 130)))
    pw = math.min(pw, w - 40)

    -- ---- ความสูง  ทุกก้อนคำนวณจากฟอนต์ ------------------------------------
    local headH = math.max(52, 12 + hm + 3 + hs + 10)
    local colH  = hs + 14                     -- แถวหัวคอลัมน์
    local rowH  = math.max(28, hm + 10)
    local noteH = hs + 6                      -- บรรทัด "จ่ายพร้อมกันทั้งสองบรรทัด"
    local btnH  = math.max(30, hs + 14)
    local sumH  = hs + 12                     -- บรรทัดสรุปเหนือปุ่ม

    local optH = {}
    local body = 0
    for i = 1, #p.opts do
        local oh = #p.opts[i] * rowH + 8 + ((#p.opts[i] > 1) and noteH or 0)
        optH[i] = oh
        body = body + oh + 4
    end

    local ph = headH + colH + body + sumH + btnH + 22
    local px = math.floor((w - pw) / 2)
    local py = math.max(U.TITL + 6, math.floor((h - ph) / 2))
    if py + ph > h - 6 then py = math.max(U.TITL + 6, h - 6 - ph) end

    U.solid(self, px, py, pw, ph, U.C.bgSel)
    U.border(self, px, py, pw, ph, U.C.line3)

    -- ---- หัว ----------------------------------------------------------------
    U.fill(self, px, py, pw, headH, U.C.bgRow)
    local icoS = math.min(38, headH - 14)
    U.slot(self, px + 10, py + math.floor((headH - icoS) / 2), icoS, itemTex(p.entry), p.entry.rare)

    local tx = px + 10 + icoS + 12
    local nameMax = pw - (tx - px) - 14
    local nm = p.entry.name or p.entry.id
    -- ตัดชื่อให้พอดีกล่อง  ตัดที่ความกว้างจริง ไม่ใช่จำนวนตัวอักษร
    while U.w(nm, fm) > nameMax and #nm > 4 do nm = nm:sub(1, #nm - 2) end
    if nm ~= (p.entry.name or p.entry.id) then nm = nm .. ".." end
    U.text(self, nm, tx, py + 10, U.C.text, fm)

    local sub = tostring(p.entry.cat or ""):upper()
    if KR.saleActive(p.entry, ts) then
        local pct = math.floor((KR.discountBp(p.entry, ts) or 0) / 100)
        sub = sub .. (pct > 0 and ("   SALE -" .. pct .. "%") or "   SALE")
    end
    U.text(self, sub, tx, py + 10 + hm + 3, KR.saleActive(p.entry, ts) and U.C.bad or U.C.dim, fs)

    -- ---- หัวคอลัมน์ ----------------------------------------------------------
    local c1 = px + 14                        -- สกุล  ชิดซ้าย
    local c3 = px + pw - 14                   -- เหลือหลังจ่าย  ชิดขวา
    local c2 = c3 - leftW - 22                -- เส้นคั่น  ราคาชิดขวาก่อนเส้นนี้
    local hy = py + headH + 4
    U.fill(self, px, py + headH, pw, colH, U.C.bgHead)
    U.text(self,  KR.L("สกุล", "Currency"), c1, hy, U.C.dim, fs)
    U.textR(self, KR.L("ราคา", "Price"), c2 - 10, hy, U.C.dim, fs)
    U.textR(self, lblLeft, c3, hy, U.C.dim, fs)

    -- ---- ตัวเลือกการจ่าย ------------------------------------------------------
    local y = py + headH + colH
    self.payBtns = {}

    for i = 1, #p.opts do
        local opt  = p.opts[i]
        local sel  = (p.sel == i)
        local need = KR.optionCost(opt, p.entry, ts)
        local can  = KR.canAfford(opt, p.entry, bal, ts)
        local oh   = optH[i]

        local hot = U.hit({ x = px, y = y, w = pw, h = oh }, self.mx, self.my)
        if sel then
            U.fill(self, px, y, pw, oh, U.C.accent2, 0.55)
            U.fill(self, px, y, 3, oh, U.C.accent)
        elseif hot and can then
            U.fill(self, px, y, pw, oh, U.C.bgRow, 0.6)
        end
        if i > 1 then U.hr(self, px, y, pw, U.C.line3, 0.7) end

        for j = 1, #opt do
            local part = opt[j]
            local ry   = y + 4 + (j - 1) * rowH
            local ty   = ry + math.floor((rowH - hm) / 2)
            local tys  = ry + math.floor((rowH - hs) / 2)
            local col  = can and U.curCol(part.cur) or U.C.dim

            local ox = c1
            if j > 1 then
                U.text(self, "+", c1, tys, U.C.dim, fs)
                ox = c1 + U.w("+", fs) + 6
            end
            U.coin(self, part.cur, ox, ry + math.floor((rowH - 16) / 2), 16)
            U.text(self, (KR.CUR_META[part.cur] or {}).label or "?", ox + 22, tys,
                   can and U.C.lite or U.C.dim, fs)

            local amt = KR.applyDiscount(part.cur, part.price, KR.discountBp(p.entry, ts))
            U.textR(self, KR.fmtPrice(part.cur, amt):gsub("^%S+%s", ""), c2 - 10, ty, col, fm)

            -- เส้นตั้ง  แยกฝั่งราคากับฝั่งคงเหลือ ไม่ต้องตีกรอบเพิ่ม
            U.vr(self, c2, ry, rowH, U.C.line3, 0.8)

            local have = tonumber(bal[part.cur]) or 0
            local left = have - (need[part.cur] or 0)
            if left >= 0 then
                U.textR(self, fmtNum(part.cur, left), c3, tys, U.C.mute, fs)
            else
                U.textR(self, KR.L("ขาด ", "Short ") .. fmtNum(part.cur, -left), c3, tys, U.C.bad, fs)
            end
        end

        if #opt > 1 then
            U.text(self, KR.L("จ่ายพร้อมกันทั้งสองบรรทัด", "Both lines are charged together"),
                   c1, y + oh - noteH, U.C.warn, fs)
        end

        if can then
            self.payBtns[#self.payBtns + 1] = { x = px, y = y, w = pw, h = oh, sel = i }
        end
        y = y + oh + 4
    end

    -- ---- สรุป + ปุ่ม ---------------------------------------------------------
    local by  = py + ph - btnH - 12
    local sy  = by - sumH

    local okAble = false
    if p.sel and p.opts[p.sel] then
        okAble = KR.canAfford(p.opts[p.sel], p.entry, bal, ts)
    end

    if p.sel and p.opts[p.sel] then
        -- บอกเป็นตัวหนังสือว่ากำลังจะจ่ายอะไรไปเท่าไร  ปุ่ม Confirm เฉย ๆ ไม่พอ
        local parts = {}
        local need  = KR.optionCost(p.opts[p.sel], p.entry, ts)
        for _, cur in ipairs({ KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP }) do
            if (need[cur] or 0) > 0 then
                parts[#parts + 1] = fmtNum(cur, need[cur]) .. " " ..
                                    ((KR.CUR_META[cur] or {}).label or cur)
            end
        end
        local verb = (p.entry.kind == KR.KIND.SERVICE) and KR.L("สั่ง", "Order")
                                                        or KR.L("ซื้อ", "Buy")
        U.text(self, verb .. "  " .. table.concat(parts, " + "), c1, sy,
               okAble and U.C.text or U.C.bad, fs)
    else
        U.text(self, KR.L("เลือกวิธีจ่ายก่อน", "Pick how you want to pay"), c1, sy, U.C.mute, fs)
    end

    local cw2 = math.max(96, U.w(KR.L("ยกเลิก", "Cancel"), fs) + 34)
    local ow2 = math.max(130, U.w(KR.L("ยืนยันซื้อ", "Confirm"), fs) + 44)
    self.bPayCancel = U.btn(self, px + pw - 14 - ow2 - U.GAP - cw2, by, cw2, btnH,
                            KR.L("ยกเลิก", "Cancel"), "neu", self.mx, self.my)
    self.bPayOk = U.btn(self, px + pw - 14 - ow2, by, ow2, btnH,
                        okAble and KR.L("ยืนยันซื้อ", "Confirm")
                               or KR.L("จ่ายไม่ไหว", "Cannot afford"),
                        okAble and "pri" or "offb", self.mx, self.my)
    if not okAble then self.bPayOk = nil end
end

-- ------------------------------------------------------------------------------
-- prerender  วาดทั้งหมดที่นี่ที่เดียว
-- ------------------------------------------------------------------------------
-- ขอข้อมูลใหม่เป็นระยะระหว่างที่หน้าต่างเปิดอยู่
--
-- ทำไมต้องมี: Kuraya ไม่ได้เป็นเจ้าของเงินสด  Akacount เป็น
-- ผู้เล่นไปฝากเงินที่ธนาคารแล้วยอดในร้านไม่ขยับ เพราะร้านถือข้อมูลตอนเปิดค้างไว้
-- (ผู้เล่นรายงานจริง: "ตอนฝากเงินยอดไม่เปลี่ยนนะ cash อะ")
--
-- ทางเลือกอื่นคือให้ Akacount ยิงบอก Kuraya ทุกครั้งที่ยอดขยับ
-- แต่นั่นทำให้ธนาคารต้องรู้จักร้าน ซึ่งผิดทิศทางการพึ่งพา (Kuraya -> Akacount ทางเดียว)
-- ถามเองเป็นระยะง่ายกว่า และหยุดเองเมื่อปิดหน้าต่าง
--
-- ยังทำให้นาฬิกานับถอยหลังของประมูล / ป้ายไฟ / โปรลดราคา เดินตรงไปด้วย
local POLL_MS = 2000

function KRShop:poll()
    local t = getTimestampMs and getTimestampMs() or nil
    if t == nil then return end
    if self.lastPoll and (t - self.lastPoll) < POLL_MS then return end
    self.lastPoll = t
    req(KR.CMD.REQ_SYNC)
end

-- ==============================================================================
-- หน้านี้วาดไม่ผ่าน  (0.6.15)
--
-- สองอย่างที่ต้องทำ และมันคนละเรื่องกัน
--   1. บอกผู้เล่นว่าเกิดอะไร และให้ทางออกที่กดได้จริง
--   2. บอกคนที่แก้ได้ว่ามันพังตรงไหน — ลง console ครั้งเดียว ไม่ใช่ทุกเฟรม
--      (หกสิบบรรทัดต่อวินาทีคือ log ที่ไม่มีใครอ่าน)
-- ==============================================================================
local BROKEN_SEEN = {}

function KRShop:drawPageBroken(x, y, w, h, err)
    local msg = tostring(err or "?")

    local kseen = tostring(self.page) .. "|" .. msg
    if not BROKEN_SEEN[kseen] then
        BROKEN_SEEN[kseen] = true
        print("[Kuraya] page '" .. tostring(self.page) .. "' failed to draw -> " .. msg)
    end

    local XH2, SH2 = U.h(U.F.xs), U.h(U.F.s)
    local ph = U.capH(true) + SH2 + 4 + XH2 * 2 + 8 + 30 + 12
    local py = y + math.floor((h - ph) / 2)

    U.solid(self, x, py, w, ph, U.C.bgHead)
    local cy = U.panel(self, x, py, w, ph, {
        bg = U.C.bgHead, accent = U.C.bad, line = U.C.bad,
        cap = KR.L("หน้านี้เปิดไม่ได้", "THIS PAGE COULD NOT OPEN"), capCol = U.C.bad,
        pad = 6,
    })

    U.text(self, KR.L("หน้าอื่นยังใช้ได้ปกติ  ลองกดแถบซ้ายเพื่อไปหน้าอื่น",
                      "The other pages still work - use the tabs on the left"),
           x + 12, cy, U.C.text, U.F.s)

    -- ข้อความดิบของ Lua ไม่สวย แต่มันคือข้อมูลจริง และมันต้องไปถึงคนที่แก้ได้
    -- ผู้เล่นแคปหน้าจอส่งให้แอดมินได้ทันทีโดยไม่ต้องไปงมหา console
    for i, ln in ipairs(U.wrap(msg, U.F.xs, w - 24, 2)) do
        U.text(self, ln, x + 12, cy + SH2 + 4 + (i - 1) * XH2, U.C.dim, U.F.xs)
    end

    -- ทางออกที่กดได้จริง  ลงทะเบียนใน navBtns เพราะตัวจัดการคลิกของแถบซ้าย
    -- อ่านตารางนั้นอยู่แล้ว และมันทำงานก่อนตัวจัดการของหน้า
    local bw = math.min(220, w - 24)
    local b = U.btn(self, x + 12, py + ph - 30 - 8, bw, 30,
                    KR.L("กลับไปหน้าร้าน", "Back to the shop"), "pri", self.mx, self.my)
    b.page = "store"
    self.navBtns[#self.navBtns + 1] = b
end

function KRShop:prerender()
    self:poll()
    self:whoPoll()
    self.whoBtns = {}

    -- เลขเฟรมสำหรับด่านช่องกรอก  ดูคอมเมนต์ยาวที่ sizeBox
    frameNo = frameNo + 1

    -- หน้าที่เป็นของแอดมินล้วน ต้องเด้งออกทันทีที่สิทธิ์หายไป
    --
    -- เคสที่เกิดจริง: แอดมินเปิดหน้า ADMIN ค้างไว้ แล้วถูกถอดสิทธิ์ (หรือกด AS PLAYER)
    -- แถบซ้ายซ่อนปุ่มให้แล้วก็จริง แต่ self.page ยังค้างเป็น "admin" อยู่
    -- หน้าจึงถูกวาดต่อไปเรื่อย ๆ ทั้งที่ไม่ควรมีอยู่ — ซ่อนทางเข้าไม่เท่ากับปิดห้อง
    --
    -- ฝั่งเซิร์ฟปฏิเสธคำสั่งอยู่แล้ว จอที่ค้างจึงไม่อันตราย แต่มันคือจอที่โกหก
    -- และเจ้าของเซิร์ฟสั่งชัดว่าสองฝั่งต้อง "ต่างกันมาเลย"
    if self.page == "admin" and not isAdminView() then
        self.page  = "store"
        self.scroll = 0
        self.auctMenu = nil
    end

    -- ธีมสีของหน้าที่กำลังเปิดอยู่  ต้องตั้งก่อนวาดอะไรสักอย่าง
    -- ทุกอย่างใต้บรรทัดนี้อ่าน U.C.accent ตัวเดียวกันหมด
    U.applyPage(self.page)

    local w, h = self.width, self.height
    self.mx = self:getMouseX()
    self.my = self:getMouseY()

    U.fill(self, 0, 0, w, h, U.C.bg)
    U.border(self, 0, 0, w, h, U.C.line2)

    -- แมวเปลี่ยนอารมณ์ตามสิ่งที่เกิดขึ้นจริงในร้าน  ไม่ใช่รูปนิ่ง
    -- เวอร์ชันบนแถบชื่อ  เซิร์ฟรันคนละรุ่นกับเครื่องนี้ต้องเห็นตรงนี้ทันที
    --
    -- เคสจริงที่กินเวลาไล่บั๊กไปเยอะ: ไคลเอนต์อัปจาก Workshop แล้ว แต่เซิร์ฟยังไม่ได้รีสตาร์ท
    -- อาการที่เห็นคือฟีเจอร์ใหม่ "ไม่ทำงาน" ทั้งที่โค้ดถูก — มันแค่ไม่ได้รันอยู่
    -- ตัวเลขสองตัววางข้างกันตอบคำถามนี้ได้โดยไม่ต้องเปิด log อะไรเลย
    local sver = tostring(data().ver or "")
    local vtxt = "蔵屋 v" .. KR.VERSION
    if sver ~= "" and sver ~= KR.VERSION then
        vtxt = vtxt .. "   SERVER v" .. sver
    end
    self.bClose, self.bHelp = U.titleBar(self, w, "KURAYA", vtxt,
                                         self.mx, self.my, KR.mood(data()))

    -- ช่องค้นหาเป็น ISTextEntryBox จริง เป็นลูกของหน้าต่างนี้
    --
    -- "ไม่วาดมัน" ไม่พอ  มันไม่ได้ถูกวาดโดยเราอยู่แล้ว มันวาดตัวเอง
    -- และตราบใดที่ยัง visible มันยังกินคลิกกับคีย์บอร์ดในสี่เหลี่ยมของมันอยู่
    -- บนหน้าประมูลนั่นคือพื้นที่ทับแท็บพอดี  กดแท็บแล้วไม่ติดโดยไม่มีอะไรบอก
    -- ทำแบบเดียวกับ self.fields ที่ล่างนี้: สั่ง setVisible ตรง ๆ ทุกเฟรม
    --
    -- ต้องปล่อยโฟกัสตอนซ่อนด้วย  ซ่อนอย่างเดียวไม่พอ
    -- กล่องที่ยังถือโฟกัสอยู่กินคีย์บอร์ดต่อแม้จะมองไม่เห็น  ผู้เล่นจะกดเดินไม่ได้
    -- แล้วไม่มีอะไรบนจอบอกได้เลยว่าเพราะอะไร (บั๊กแบบที่ไม่มีใครแจ้งได้ถูก)
    -- ปล่อยเฉพาะ "เฟรมที่เปลี่ยนหน้า" เท่านั้น  เรียกทุกเฟรมเสี่ยงไปแย่งโฟกัสของกล่องอื่น
    -- ใช้ธงของตัวเองแทน getIsVisible()  ชื่อเมธอดจริงของ PZ ไม่ใช่ isVisible() ตามที่เคยพลาดมาแล้ว
    if self.search then
        local wantSearch = isListPage(self.page)
        if self.searchOn == nil then self.searchOn = true end
        if self.searchOn and not wantSearch then
            pcall(function() self.search:unfocus() end)
        end
        self.searchOn = wantSearch
        self.search:setVisible(wantSearch)
    end

    self:drawNav(h)
    self:drawHead(w)

    local rows = self:rows()
    local nAll = 0
    for _ in pairs(data().catalog or {}) do nAll = nAll + 1 end
    self:drawTool(w, #rows, nAll)

    local lx = U.NAV + 6
    local ly = U.TITL + U.HEAD + U.TOOL + 4
    local lw = w - lx - 6

    -- แถบหมวด  โผล่เฉพาะหน้าที่เป็นลิสต์ของ และเฉพาะตอนมีหมวดจริง ๆ
    if self.page == "store" or self.page == "market" or self.page == "sale" then
        local cbh = self:catBarH()
        if cbh > 0 then
            self:drawCatBar(lx, ly, lw)
            ly = ly + cbh
        end
    else
        self.catBtns = {}
    end

    -- แถบเตือนพรีวิวกินที่ของเนื้อหา  ต้องหักออกก่อนที่หน้าไหนจะเริ่มวาด
    -- ไม่ใช่วาดทับทีหลัง  การวาดทับแปลว่ามันไปบังแถวล่างสุดของทุกหน้า
    local previewH = self:drawPreviewBar(w, h)
    local lh = h - ly - U.STAT - previewH

    -- ==========================================================================
    -- ตัวหน้า  ห่อกันไว้หนึ่งชั้น  (0.6.15)
    --
    -- **error ตัวเดียวใน prerender ทำให้ PZ ทิ้งทั้งเฟรม**
    -- ทุกอย่างใต้จุดที่ระเบิดจึงไม่ได้ถูกวาด และปุ่มที่ยังไม่ได้ลงทะเบียนก็ไม่มีอยู่จริง
    -- (ปุ่มของม็อดนี้ไม่ใช่ลูกของ PZ  มันเป็นสี่เหลี่ยมที่ถูกเก็บลงตารางระหว่างวาด
    --  แล้ว onMouseDown ไล่ดูทีหลัง  ไม่ได้วาด = ไม่มีปุ่ม)
    --
    -- สิ่งที่ผู้เล่นเห็นคือ **"กดปุ่มไม่ติดทั้งหน้าต่าง"** โดยไม่มีอะไรบนจอบอกว่าทำไม
    -- และมันเกิดกับคนเดียวได้ ถ้าข้อมูลของคนนั้นเป็นตัวจุดชนวน
    -- (ไฟล์ console ที่เจ้าของเซิร์ฟส่งมามี drawAccount ระเบิดทุกเฟรมของผู้เล่นคนหนึ่ง)
    --
    -- ห่อแล้วอย่างน้อยแถบซ้าย ปุ่มปิด ปุ่มคู่มือ ยังกดได้ เพราะมันถูกวาดไปก่อนแล้ว
    -- และมีป้ายบอกว่าหน้านี้พัง พร้อมทางออก แทนพื้นที่ว่างที่กดอะไรไม่ได้
    -- ==========================================================================
    -- ล้างรายการแผ่นลอยก่อนวาดหน้า  ของค้างจากเฟรมก่อนจะซ่อนช่องที่ไม่ได้ถูกทับ
    self.covers = {}

    local okPage, perr = pcall(function()
        if self.page == "admin" then
            self:drawAdmin(lx, ly, lw, lh, rows)
        elseif self.page == "auction" then
            self:drawAuction(lx, ly, lw, lh)
        elseif self.page == "credit" then
            self:drawCredit(lx, ly, lw, lh)
        elseif self.page == "account" then
            self:drawAccount(lx, ly, lw, lh)
        elseif self.page == "board" then
            self:drawBoard(lx, ly, lw, lh)
        elseif self.page == "stats" then
            self:drawStats(lx, ly, lw, lh)
        else
            self:drawList(lx, ly, lw, lh, rows)
        end
    end)
    if not okPage then
        self:drawPageBroken(lx, ly, lw, lh, perr)
    end

    -- ป้ายไฟ  วนข้อความจากเหตุการณ์จริงบนเซิร์ฟ
    --
    -- ดัชนีคำนวณจาก "เวลาของเซิร์ฟ" ไม่ใช่ตัวนับของไคลเอนต์
    -- ทุกคนที่เปิดร้านอยู่จะเห็นข้อความเดียวกันพร้อมกัน ซึ่งทำให้รู้สึกเหมือนป้ายจริง
    -- และไม่ต้องเก็บ state อะไรเลย  รีเฟรชจอกี่ครั้งก็ยังตรงกัน
    local d2   = data()
    local feed = d2.feed or {}
    local left
    if #feed > 0 then
        local tick = math.floor((tonumber(d2.now) or 0) / KR.FEED_SEC)
        local idx  = (tick % #feed) + 1
        left = KR.feedText(feed[idx], d2.now)
    elseif self.page == "market" and d2.atMarket then
        local m = (d2.markets or {})[d2.atMarket]
        left = KR.L("คุณกำลังยืนอยู่ที่ ", "You are standing at ") .. ((m and m.name) or KR.L("แผง", "stall"))
    elseif self.page == "account" then
        left = KR.L("ประวัติเต็มดูที่ธนาคาร", "Full statement is at the bank")
    elseif self.page == "auction" then
        left = KR.L("เงินถูกพักไว้ตอนประมูล ยังไม่ได้ถูกตัด", "Bids are held, not spent")
    elseif self.page == "credit" then
        left = KR.L("จ่ายงวดตรงเวลา วงเงินจะโตตามยศ CP", "Pay on time and your CP tier raises the limit")
    elseif self.page == "board" then
        -- ประโยคนี้ต้องอยู่ตรงนี้ ไม่ใช่ในคู่มือ  คนที่เข้าใจผิดว่าเป็นของในร้าน
        -- จะเข้าใจผิดตั้งแต่วินาทีแรกที่เห็นราคา ไม่ใช่ตอนที่ไปเปิดคู่มือ
        left = KR.L("ราคาอ้างอิงเท่านั้น  ซื้อขายกันเอง",
                    "Reference prices only - trade with each other, not with the shop")
    elseif self.page == "stats" then
        left = KR.L("ตัวเลขคิดตอนเปิดหน้า", "Figures are worked out when you open this page")
    else
        left = KR.L("คลิกที่แถวเพื่อดูวิธีจ่าย", "Click a row to pick how to pay")
    end
    -- ตัวเลขขวาล่างคือ "ของในร้านกี่ชิ้น"  หน้าประมูล/เงินกู้/บัญชีไม่ได้พูดถึงของในร้าน
    -- ปล่อยไว้เท่ากับโกหกผู้ใช้ด้วยตัวเลขที่ดูเหมือนเกี่ยวข้องแต่ไม่เกี่ยว
    U.statusBar(self, h - U.STAT, w, left,
                isListPage(self.page) and (#rows .. " / " .. nAll) or nil)

    self:drawMenus()
    -- แผงของในชุดอยู่ "ใต้" หน้าจ่ายเงิน  คนกดดูของก่อน แล้วค่อยกดซื้อ
    -- ถ้ามันทับหน้าจ่ายเงิน คนจะกดซื้อไม่ได้ทั้งที่เพิ่งอ่านจบ
    self:drawSetView(w, h)
    self:drawPay(w, h)
    -- ร้านแพ็ก HF วางไว้ใต้คู่มือแต่เหนือทุกอย่างอื่น
    -- มันเปิดจากปุ่มบนแถบหัวซึ่งมีอยู่ทุกหน้า จึงต้องทับได้ทุกหน้าเหมือนกัน
    self:drawHfp(w, h)
    self:drawHelp(w, h)
    self:watchAnswer()
    self:drawBillPop(w, h)
    self:drawToast(w, h)

    -- ==========================================================================
    -- ด่านสุดท้ายของเฟรม : ช่องกรอกไหนได้โผล่บ้าง
    --
    -- ต้องอยู่ **ท้ายสุด** หลังทุกอย่างวาดเสร็จ  เพราะกว่าจะรู้ว่าใครวางช่องไหนไว้
    -- ก็ต่อเมื่อทุกคนวาดเสร็จแล้ว
    --
    -- แผ่นทับกินทุกอย่าง: คู่มือ / หน้าต่างจ่ายเงิน / ร้านแพ็ก HF
    -- สามอันนี้วาดทับทั้งหน้าต่าง แต่ ISTextEntryBox เป็นลูกจริงของ PZ
    -- มันวาดตัวเองทับแผ่นพวกนั้นอีกที  ไม่สั่งซ่อน = ช่องกรอกลอยอยู่บนป๊อปอัป
    -- (เจ้าของเซิร์ฟถ่ายรูปมาให้ดู: ช่องชื่อแพ็กกับราคาลอยกลางหน้าเติม HF)
    -- ==========================================================================
    -- แผงเลือกรูปแพ็กนับเป็นแผ่นทับด้วย
    --
    -- มันลอยอยู่กลางฟอร์มและมีช่องกรอกอยู่ข้างใต้  ช่องกรอกวาดทับแผงเสมอ
    -- (ด่านผังจับได้: "field 'hfpName' sits on top of a clickable button")
    -- ซ่อนทั้งหมดตอนแผงเปิดง่ายกว่าและถูกกว่าการไล่เช็กว่าช่องไหนอยู่ใต้แผงบ้าง
    -- แผงนี้เป็นของชั่วคราวอยู่แล้ว  กดรูปหนึ่งทีมันก็ปิด
    -- 0.6.12 — แผงของในชุด กับ ตัวจัดของในชุด เป็นแผ่นทับด้วย
    -- ด่านผังจับได้ทันทีที่เพิ่มจอเข้ามา: "field 'a1' sits on top of a clickable button"
    -- ช่องราคา a1/a2 ลอยอยู่บนตัวจัดของในชุดพอดี  กดปุ่มลบบรรทัดไม่ติดเพราะช่องกินคลิกไปก่อน
    -- นี่คือกับดักเดิมกับหน้าเติม HF เป๊ะ ๆ  รายชื่อนี้จึงต้องโตทุกครั้งที่มีแผ่นทับใหม่
    local modal = (self.billPop ~= nil) or (self.help ~= nil) or (self.pay ~= nil)
               or (self.hfpOpen == true) or (self.hfpIconOpen == true)
               or (self.setView ~= nil)
    for _, box in pairs(self.fields or {}) do
        local show = (not modal) and box.__krFrame == frameNo
        -- ช่องที่โดนแผ่นลอยทับ ต้องหลบให้แผ่น  ไม่งั้นมันวาดทับ (ดูเหมือนแผ่นใส)
        -- แล้วกินคลิกของแผ่นไปกิน (ดูเหมือนกดโดนของข้างหลัง)
        if show and box.getX then
            local bx, by = box:getX(), box:getY()
            local bw, bh = box:getWidth(), box:getHeight()
            for _, mr in ipairs(self.covers or {}) do
                if bx < mr.x + mr.w and mr.x < bx + bw
                   and by < mr.y + mr.h and mr.y < by + bh then
                    show = false
                    break
                end
            end
        end
        box:setVisible(show)
    end
    if modal and self.search then self.search:setVisible(false) end
end

-- ------------------------------------------------------------------------------
-- เซิร์ฟไม่ตอบ
--
-- ปุ่มที่กดแล้วเงียบมีสองความหมายที่แยกไม่ออกจากเก้าอี้ผู้เล่น
--   "กำลังทำงานอยู่" กับ "ตายไปแล้ว"
-- ป้าย "Sending your order..." ที่ค้างอยู่เฉย ๆ อ่านได้ว่าอย่างแรก ซึ่งเป็นการโกหก
--
-- ครบเวลาแล้วยังไม่มีคำตอบ = พูดออกมาตรง ๆ พร้อมบอกว่าให้ไปดูที่ไหนต่อ
-- ข้อความต้องชี้ไปที่ console ของ **เซิร์ฟ** ไม่ใช่ของเครื่องผู้เล่น
-- เพราะ handler ที่ระเบิดพิมพ์ลงฝั่งโน้น (0.4.1 ส่ง error กลับมาแล้ว แต่ถ้าเซิร์ฟ
-- ยังเป็นรุ่นเก่ากว่านั้น มันจะเงียบอยู่ดี ซึ่งเป็นเคสที่ป้ายนี้มีไว้เพื่อ)
-- ------------------------------------------------------------------------------
function KRShop:watchAnswer()
    if not self.awaitAt then return end
    local now = getTimestampMs and getTimestampMs() or 0
    if now - self.awaitAt < KR.ANSWER_MS then return end
    self.awaitAt = nil
    KRShop.notify(KR.L("เซิร์ฟไม่ตอบ", "The server did not answer ") ..
                  tostring(self.awaitWhat or "") ..
                  KR.L("  ดู console ฝั่งเซิร์ฟ บรรทัด [Kuraya]",
                       ". Check the SERVER console for [Kuraya] lines."), "bad")
end

-- ------------------------------------------------------------------------------
-- ข้อความตอบกลับจากเซิร์ฟ  วาดในหน้าต่างร้าน ไม่ใช่ลอยเหนือหัวตัวละคร
--
-- เดิมคำตอบทุกอย่าง ("ซื้อแล้ว" / "จ่ายไม่พอ" / "ส่งของไม่สำเร็จ คืนเงินแล้ว")
-- ไปโผล่เป็น HaloText เหนือหัวตัวละคร  ซึ่ง **อยู่หลังหน้าต่างร้านที่เปิดเต็มจอ**
-- ผู้เล่นจึงเห็นแค่ "กดแล้วไม่มีอะไรเกิดขึ้น" และรายงานว่า "กดซื้ออะไรไม่ได้"
-- ทั้งที่เซิร์ฟตอบกลับมาแล้วทุกครั้ง แค่ตอบไปยังที่ที่มองไม่เห็น
--
-- ตรงนี้รับข้อความเดียวกันมาแปะไว้กลางล่างของหน้าต่าง 6 วินาที
-- HaloText ยังยิงเหมือนเดิม  คนที่ปิดร้านไปแล้วยังได้รับ
-- ------------------------------------------------------------------------------
KR.TOAST_MS = 6000

function KRShop.notify(msg, tone)
    local w = KRShop.instance
    if not w or not msg then return end
    -- คำตอบมาถึงแล้ว  เลิกจับเวลา
    -- ตั้งที่นี่ที่เดียวเพราะทุกคำตอบจากเซิร์ฟผ่านฟังก์ชันนี้หมด
    -- (ยกเว้นป้ายที่ตัวจับเวลาเองเป็นคนตั้ง ซึ่งเคลียร์ awaitAt ไปก่อนเรียกแล้ว)
    w.awaitAt = nil
    w.toast   = { msg = tostring(msg), tone = tone or "info" }
    w.toastAt = getTimestampMs and getTimestampMs() or 0
end

function KRShop:drawToast(w, h)
    local t = self.toast
    if not t then return end
    local now = getTimestampMs and getTimestampMs() or 0
    if now - (self.toastAt or 0) > KR.TOAST_MS then self.toast = nil; return end

    local pad  = 14
    local tw   = math.min(w - 80, U.w(t.msg, U.F.s) + pad * 2)
    local th   = U.h(U.F.s) + 16
    local tx   = math.floor((w - tw) / 2)
    local ty   = h - U.STAT - th - 12

    local col = U.C.line3
    if t.tone == "good" then col = U.C.good end
    if t.tone == "bad"  then col = U.C.bad  end

    U.fill(self, tx, ty, tw, th, U.C.bgDark, 0.96)
    U.border(self, tx, ty, tw, th, col)
    U.fill(self, tx, ty, 3, th, col)
    U.textC(self, t.msg, tx + tw / 2, ty + 8, U.C.text, U.F.s)
end

-- ==============================================================================
-- แผ่นลอย  (0.6.19)
--
-- เจ้าของเซิร์ฟรายงานว่า "เมนูตรงนี้มันใส จอเป็นทึบได้ปะ มันไปกดโดนข้างหลัง"
--
-- **มันไม่ได้ใส และพื้นหลังก็ทึบอยู่แล้ว** (U.solid วาดที่ alpha 1)
-- ของที่มองทะลุคือ **ISTextEntryBox ซึ่งเป็นลูกจริงของ PZ** มันวาดตัวเองทีหลัง
-- ทับทุกอย่างที่เราวาด และ **กินคลิกก่อนเราเสมอ**
-- สองอาการที่เขาเห็น (ใส + กดโดนข้างหลัง) จึงเป็นเรื่องเดียวกันเรื่องเดิม
--
-- กลไกแก้มีอยู่ในม็อดแล้วตั้งแต่ 0.6.13 (self.menuRect) แต่ **ผูกไว้กับเมนูหมวด
-- อันเดียว** ลิสต์เลือกไอเทม/รถ/สัตว์ กับลิสต์ของบรรทัดในชุด ไม่เคยลงทะเบียน
--
-- รอบนี้เปลี่ยนเป็น "รายการ" แล้วให้ทุกแผ่นลอยลงทะเบียนตัวเอง
-- แผ่นใหม่ในอนาคตเรียก self:cover(...) บรรทัดเดียวก็ได้ของครบ
-- ไม่ต้องไปจำว่ามีกลไกนี้อยู่ ซึ่งเป็นเหตุผลที่รอบนี้ลืม
-- ==============================================================================
function KRShop:cover(x, y, w, h)
    self.covers = self.covers or {}
    self.covers[#self.covers + 1] = { x = x, y = y, w = w, h = h }
end

function KRShop:coveredAt(x, y)
    for _, r in ipairs(self.covers or {}) do
        if U.hit(r, x, y) then return true end
    end
    return false
end

function KRShop:render() end

-- ------------------------------------------------------------------------------
-- เมาส์
-- ------------------------------------------------------------------------------
function KRShop:onMouseDown(x, y)
    -- กดตรงแถบชื่อเท่านั้นถึงลากหน้าต่างได้  ไม่งั้นกดปุ่มแล้วหน้าต่างเลื่อนตาม
    self.moveWithMouse = (y < U.TITL) and not self.pay
    return ISPanel.onMouseDown(self, x, y)
end

function KRShop:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    self.moveWithMouse = false

    -- คู่มือเปิดอยู่ = กินคลิกทั้งหมด  มันทับทุกอย่างรวมถึงหน้าต่างจ่ายเงิน
    -- ป้ายบิลอยู่บนสุดของทุกอย่าง  มันคือเรื่องเงินที่เพิ่งถูกหักไปจากบัญชีเขา
    -- ห้ามให้คลิกทะลุไปโดนอย่างอื่นก่อนที่เขาจะได้อ่าน
    if self.billPop then
        if U.hit(self.bBillOk, x, y) then
            table.remove((KRClient or {}).billQueue or {}, 1)
            self.billPop = nil
        end
        return true
    end

    if self.help then
        if self:helpClick(x, y) then return true end
        return true
    end

    -- ร้านแพ็ก HF เปิดอยู่ = กินคลิกทั้งหมดเหมือนกัน  ลำดับต้องตรงกับลำดับที่วาด
    -- (วาด: drawPay -> drawHfp -> drawHelp   อ่านคลิก: help -> hfp -> pay)
    if self.hfpOpen then
        return self:hfpClick(x, y)
    end

    -- รายการเลือกชื่อผู้เล่นลอยทับปุ่มอื่นอยู่  ต้องได้สิทธิ์อ่านคลิกก่อนใคร
    -- ไม่งั้นคลิกที่ตั้งใจเลือกชื่อจะทะลุไปโดนปุ่มที่บังเอิญอยู่ข้างหลังรายการ
    if self:whoClick(x, y) then return true end

    -- หน้าต่างจ่ายเงินเปิดอยู่ = กินคลิกทั้งหมด ห้ามทะลุไปโดนของข้างหลัง
    if self.pay then
        if U.hit(self.bPayCancel, x, y) then self.pay = nil; return true end
        if self.bPayOk and U.hit(self.bPayOk, x, y) then
            sendBuy(self.pay.entry.id, self.pay.sel)
            self.pay = nil
            return true
        end
        for _, b in ipairs(self.payBtns or {}) do
            if U.hit(b, x, y) then self.pay.sel = b.sel; return true end
        end
        return true
    end

    -- เมนูดร็อปดาวน์อยู่บนสุด เช็กก่อนเพื่อน
    for _, b in ipairs(self.menuBtns or {}) do
        if U.hit(b, x, y) then b.fn(b.value); return true end
    end
    if self.sortOpen or self.curOpen or self.catMenu or self.auctMenu then
        self.sortOpen, self.curOpen, self.catMenu, self.auctMenu = false, false, nil, nil
        return true
    end

    if U.hit(self.bHfTop, x, y) then
        self.hfpOpen = true
        return true
    end
    if U.hit(self.bPreviewOff, x, y) then
        -- ออกจากพรีวิว  แถบเตือนทั้งแถบคือปุ่มออก
        KRShopUI.asPlayer = false
        self.scroll = 0
        return true
    end
    if U.hit(self.bClose, x, y) then self:close(); return true end
    if U.hit(self.bHelp, x, y) then self:openHelp(); return true end
    if U.hit(self.bSort, x, y) then self.sortOpen = true; self.curOpen = false; return true end
    if U.hit(self.bCur,  x, y) then self.curOpen  = true; self.sortOpen = false; return true end

    for _, b in ipairs(self.catBtns or {}) do
        if U.hit(b, x, y) then
            if b.act == "catleft" then
                self.catScroll = math.max(0, self.catScroll - 160)
            elseif b.act == "catright" then
                self.catScroll = self.catScroll + 160
            else
                if KRClient then KRClient.filterCat = b.cat end
                self.scroll = 0
                -- ให้เซิร์ฟจำไว้  ผู้เล่นย้ายเครื่องแล้วต้องยังอยู่หมวดเดิม
                req(KR.CMD.SET_PREF, { cat = b.cat })
            end
            return true
        end
    end

    for _, b in ipairs(self.navBtns or {}) do
        if U.hit(b, x, y) then
            self.page   = b.page
            self.scroll = 0
            -- ออกจากหน้า Account = ปิดฟอร์มโอนที่ค้างอยู่ด้วย
            -- ไม่งั้นกลับเข้ามาอีกทีเจอฟอร์มเปิดค้างพร้อมชื่อผู้รับเดิม  ซึ่งอันตราย
            if b.page ~= "account" then self.sendOpen = false end
            return true
        end
    end

    -- หน้า Auction / Credit จัดการคลิกของตัวเอง
    if self.page == "auction" or self.page == "credit" then
        if self:pagesClick(x, y) then return true end
    end

    if self.page == "account" then return self:accountClick(x, y) end
    if self.page == "board"   then return self:boardClick(x, y) end
    if self.page == "stats"   then return self:statsClick(x, y) end

    if self.page == "admin" then
        local a = self.adm or {}

        -- ==================================================================
        -- **ปุ่มที่อยู่บนแผ่นลอย ต้องได้คลิกก่อนปุ่มที่อยู่ข้างหลัง**  (0.6.19)
        --
        -- admBtns เป็นลิสต์เรียงตาม "ลำดับที่ถูกวาด" และตัวไล่หาเอาตัวแรกที่โดน
        -- แผ่นลอยถูกวาดท้ายสุดเสมอ (เพื่อให้ทับของอื่นได้) ปุ่มของมันจึงอยู่
        -- **ท้ายลิสต์** แล้วปุ่มที่อยู่ข้างใต้ซึ่งถูกวาดก่อน กินคลิกไปก่อนทุกครั้ง
        --
        -- นี่คืออีกครึ่งของอาการ "มันไปกดโดนข้างหลัง" ที่เจ้าของเซิร์ฟเจอ
        -- ครึ่งแรกคือช่องกรอกของ PZ (แก้ด้วย self:cover ข้างบน) ครึ่งนี้คือปุ่มของเราเอง
        -- ซ่อนช่องกรอกอย่างเดียวไม่พอ เพราะปุ่มของเราไม่ใช่ช่องกรอก
        --
        -- และคลิกที่ลงในแผ่นแต่ไม่โดนแถวไหนเลย ต้อง **กินทิ้ง** ไม่ใช่ปล่อยทะลุ
        -- คลิกขอบแผ่นแล้วไปโดนปุ่มลบของข้างหลัง คือความเสียหายที่กู้คืนไม่ได้
        -- ==================================================================
        -- คลิกลงในแผ่นลอย = ให้เห็นเฉพาะปุ่มของแผ่นนั้น  ที่เหลือมองไม่เห็นเลย
        local inCover = self:coveredAt(x, y)
        local order = self.admBtns or {}
        if inCover then
            order = {}
            for _, b in ipairs(self.admBtns or {}) do
                if b.top then order[#order + 1] = b end
            end
        end

        for _, b in ipairs(order) do
            if U.hit(b, x, y) then
                if b.act == "tab" then
                    a.tab = b.tab; self.scroll = 0
                    -- เข้าแท็บแพ็ก HF ครั้งแรกต้องมีค่าในฟอร์ม
                    -- ฟอร์มว่างเปล่าที่ดูเหมือนแก้ได้แต่กดบันทึกแล้วโดนตีกลับ
                    -- คือฟอร์มที่สอนให้คนเลิกเชื่อปุ่มบันทึก
                    if b.tab == "hfp" then self:hfpLoad(a.hfpSlot or 1) end

                -- ---- แพ็ก HF ------------------------------------------------
                elseif b.act == "htab" then
                    a.hfpTab = b.htab; self.scroll = 0
                    if b.htab == "packs" then self:hfpLoad(a.hfpSlot or 1) end
                elseif b.act == "hfppick" then
                    a.hfpReq = b.id
                    if self.fields.hfpNote then self.fields.hfpNote:setText("") end
                elseif b.act == "hfpok" or b.act == "hfpno" then
                    local note = self.fields.hfpNote
                                 and self.fields.hfpNote:getInternalText() or ""
                    req(KR.CMD.HFP_ACT, { id = b.id, ok = (b.act == "hfpok"), note = note })
                    if self.fields.hfpNote then self.fields.hfpNote:setText("") end
                    a.hfpReq = nil
                elseif b.act == "hfpsend" then
                    local to = self:whoValue("hfpTo")
                    if not to then
                        KRShop.notify(KR.L("ยังไม่ได้เลือกผู้เล่น", "Pick a player first"), "bad")
                        return true
                    end
                    local amt = tonumber(self.fields.hfpAmt
                                         and self.fields.hfpAmt:getInternalText() or "") or 0
                    local why = self.fields.hfpWhy
                                and self.fields.hfpWhy:getInternalText() or ""
                    req(KR.CMD.HFP_SEND, { to = to, hf = amt, reason = why })
                elseif b.act == "hfpslot" then
                    self:hfpLoad(b.slot)
                    self.hfpIconOpen = false
                elseif b.act == "hfpiconmenu" then
                    -- กดปุ่มเดิมซ้ำ = ปิด  พฤติกรรมเดียวกับเมนูหมวดและตัวเลือกไอเทม
                    self.hfpIconOpen = not self.hfpIconOpen
                    self.hfpIconX, self.hfpIconY = b.menuX, b.menuY
                elseif b.act == "hfpicon" then
                    a.hfpIcon = b.val
                    self.hfpIconOpen = false
                elseif b.act == "hfpoff" then
                    a.hfpOff = not a.hfpOff
                elseif b.act == "hfpclear" then
                    req(KR.CMD.HFP_SET, { slot = a.hfpSlot, clear = true })
                elseif b.act == "hfpgive" then
                    local to = self:whoValue("hfpTo")
                    if not to then
                        KRShop.notify(KR.L("ยังไม่ได้เลือกผู้เล่น", "Pick a player first"), "bad")
                        return true
                    end
                    local why = self.fields.hfpWhy
                                and self.fields.hfpWhy:getInternalText() or ""
                    if why:gsub("%s", "") == "" then
                        why = KR.L("ส่งแพ็กให้โดยแอดมิน", "pack sent by an admin")
                    end
                    req(KR.CMD.HFP_SEND, { to = to, slot = a.hfpSlot, reason = why })
                elseif b.act == "hfpsave" then
                    local function num(k)
                        return tonumber(self.fields[k] and self.fields[k]:getInternalText() or "")
                    end
                    req(KR.CMD.HFP_SET, {
                        slot  = a.hfpSlot,
                        name  = self.fields.hfpName and self.fields.hfpName:getInternalText() or "",
                        hf    = num("hfpHf") or 0,
                        bonus = num("hfpBonus") or 0,
                        thb   = num("hfpThb") or 0,
                        icon  = a.hfpIcon or KR.HFP_ICON_DEFAULT,
                        off   = a.hfpOff and true or nil,
                        -- ช่องพิเศษ  เซิร์ฟอ่านเฉพาะตัวที่ตรงกับชนิดของช่องนั้น
                        mins    = num("hfpMins"),
                        stock   = num("hfpStock") or 0,
                        per     = num("hfpPer") or 0,
                        thbCut  = num("hfpCut"),
                        cutMins = num("hfpCutMins"),
                    })

                elseif b.act == "pick" then
                    self:admLoad(b.e)
                elseif b.act == "del" then
                    req(KR.CMD.ADMIN_DEL, { id = b.e.id })
                    if a.edit == b.e.id then self:admLoad(nil) end
                elseif b.act == "toggle" then
                    -- ส่งของเดิมกลับไปทั้งชุด แค่พลิกสถานะ  ถ้าส่งแค่ enabled ราคาจะหายหมด
                    local pay = {}
                    for _, opt in ipairs(KR.payOptions(b.e)) do pay[#pay + 1] = opt end
                    req(KR.CMD.ADMIN_SAVE, {
                        id = b.e.id, name = b.e.name, cat = b.e.cat, kind = b.e.kind,
                        item = b.e.item, rare = b.e.rare, stock = b.e.stock,
                        restock = b.e.restock, quota = b.e.quota, quotaPeriod = b.e.quotaPeriod,
                        market = b.e.market, pay = pay,
                        enabled = (b.e.enabled == false),
                    })

                    -- ถ้ากำลังแก้ตัวเดียวกันอยู่ในฟอร์มด้านขวา ต้องพลิกสวิตช์ในฟอร์มตามไปด้วย
                    -- ไม่งั้นแอดมินกดซ่อนจากลิสต์ แล้วกดบันทึกฟอร์ม = สั่งเปิดขายกลับเงียบ ๆ
                    -- เลขรอบก็ต้องเดินตาม เพราะเซิร์ฟเวอร์บวกหนึ่งทุกครั้งที่บันทึก
                    -- (ถ้าเดาผิดก็แค่โดนตีกลับว่า "มีคนแก้แซง" ซึ่งเป็นทางที่ปลอดภัยอยู่แล้ว)
                    if a.edit == b.e.id then
                        a.enabled = (b.e.enabled == false)
                        a.rev     = (tonumber(b.e.rev) or 0) + 1
                    end

                elseif b.act == "catmenu" then
                    -- เปิดเมนูหมวด  ปิดของเดิมถ้าเปิดอยู่ (กดปุ่มเดิมซ้ำ = ปิด)
                    if self.catMenu then
                        self.catMenu = nil
                    else
                        -- ใช้ catsAll ก่อน  มันคือทุกหมวดที่เคยใช้ ไม่ใช่แค่หมวดที่มีของอยู่
                        -- (0.6.13 — ดูเหตุผลเต็มที่ KR_Server ตรงที่ส่ง catsAll)
                        local names = {}
                        for _, c in ipairs(data().catsAll or {}) do names[#names + 1] = c end
                        if #names == 0 then
                            for _, c in ipairs(data().cats or {}) do names[#names + 1] = c.id end
                        end
                        if #names == 0 then names = CATS end
                        self.catMenu = { x = b.menuX, y = b.menuY, items = names }
                    end
                elseif b.act == "itempick" then
                    -- กดปุ่มเดิมซ้ำ = ปิด  พฤติกรรมเดียวกับเมนูหมวด
                    self.itemOpen = not self.itemOpen
                    self.itemScroll = 0
                elseif b.act == "itemset" then
                    if self.fields.item then self.fields.item:setText(b.val or "") end
                    self.itemOpen = false
                    self.itemScroll = 0
                elseif b.act == "sect" then
                    -- กางได้ครั้งละหนึ่ง  กดอันที่กางอยู่ซ้ำ = พับ
                    a.sect = (a.sect == b.val) and nil or b.val

                -- ---- โหมด ชิ้นเดียว / เป็นชุด  (0.6.14) ------------------------
                elseif b.act == "admmode" then
                    a.mode = b.val
                    a.setPick = nil
                elseif b.act == "setbox" then
                    -- กดอันที่เลือกอยู่ซ้ำ = เอารูปออก  ทางกลับต้องมีเสมอ
                    a.box = (a.box == b.val) and nil or b.val
                -- ---- บรรทัดของในชุด  (0.6.14) --------------------------------
                elseif b.act == "setkind" and b.val then
                    -- สลับชนิดแล้วล้างบรรทัด  ชื่อไอเทม ชื่อรุ่นรถ และชื่อสัตว์
                    -- อยู่คนละจักรวาล  ปล่อยค่าเดิมค้างไว้ = ผลค้นว่างเปล่า
                    -- โดยไม่มีใครบอกว่าทำไม
                    --
                    -- วนตามลิสต์ ไม่ใช่สลับสองทาง (0.6.16)  ITEM -> CAR -> PET -> ITEM
                    -- ลำดับมาจาก SPEC_ORDER เพื่อให้ปุ่มวนตามลำดับที่คนเห็นในตาราง
                    a.setKinds = a.setKinds or {}
                    local cur  = a.setKinds[b.val] or "item"
                    local nxt  = SPEC_ORDER[1]
                    for idx, kk in ipairs(SPEC_ORDER) do
                        if cur == kk then nxt = SPEC_ORDER[idx + 1] or "item" end
                    end
                    a.setKinds[b.val] = nxt
                    local f = self.fields["setI" .. b.val]
                    if f then f:setText("") end
                elseif b.act == "setpick" and b.val then
                    a.setPick = (a.setPick == b.val) and nil or b.val
                elseif b.act == "setfill" and b.line then
                    local f = self.fields["setI" .. b.line]
                    if f then f:setText(b.val or "") end
                    local q = self.fields["setN" .. b.line]
                    if q and (q:getInternalText() or "") == "" then q:setText("1") end
                    a.setPick = nil
                elseif b.act == "setdel" and b.val then
                    -- เลื่อนบรรทัดล่างขึ้นมาแทน  ช่องว่างกลางลิสต์คือช่องที่คนคิดว่าพัง
                    a.setKinds = a.setKinds or {}
                    for i = b.val, KR.SET_MAX - 1 do
                        local f1, f2 = self.fields["setI" .. i], self.fields["setI" .. (i + 1)]
                        local q1, q2 = self.fields["setN" .. i], self.fields["setN" .. (i + 1)]
                        if f1 and f2 then f1:setText(f2:getInternalText() or "") end
                        if q1 and q2 then q1:setText(q2:getInternalText() or "") end
                        a.setKinds[i] = a.setKinds[i + 1]
                    end
                    local fl, ql = self.fields["setI" .. KR.SET_MAX], self.fields["setN" .. KR.SET_MAX]
                    if fl then fl:setText("") end
                    if ql then ql:setText("") end
                    a.setKinds[KR.SET_MAX] = nil
                    a.setPick = nil
                elseif b.act == "rare"    then a.rare = not a.rare
                elseif b.act == "vis"     then a.enabled = (a.enabled == false)
                elseif b.act == "restock" then
                    a.restock = cycle({ KR.RESTOCK.NEVER, KR.RESTOCK.DAILY, KR.RESTOCK.WEEKLY }, a.restock)
                elseif b.act == "qper"    then
                    a.qper = cycle({ KR.PERIOD.SALE, KR.PERIOD.DAILY, KR.PERIOD.WEEKLY, KR.PERIOD.EVER }, a.qper)

                elseif b.act == "cur1" or b.act == "cur2" then
                    -- วนสกุล  จบรอบแล้วกลับเป็นว่าง = ปิดทางจ่ายนั้น
                    local t   = (b.act == "cur1") and a.cur or a.cur2
                    local cur = t[b.row]
                    if cur == nil then t[b.row] = CURS[1]
                    elseif cur == CURS[#CURS] then t[b.row] = nil
                    else t[b.row] = cycle(CURS, cur) end

                elseif b.act == "market" then
                    -- วนแผงทั้งหมด แล้วจบที่ "ร้านหลัก"
                    local ids = { }
                    for id in pairs(data().markets or {}) do ids[#ids + 1] = id end
                    table.sort(ids)
                    if #ids == 0 then a.market = nil
                    elseif a.market == nil then a.market = ids[1]
                    else
                        local at
                        for k2 = 1, #ids do if ids[k2] == a.market then at = k2 end end
                        a.market = (at and ids[at + 1]) or nil
                    end

                elseif b.act == "stall" then
                    a.stall = b.id
                    if self.fields.stallName then self.fields.stallName:setText(b.m.name or "") end
                elseif b.act == "person" then
                    -- เก็บทั้งคีย์และชื่อที่โชว์
                    -- คีย์คือสิ่งที่เซิร์ฟใช้  ชื่อที่โชว์คือสิ่งที่แอดมินอ่าน
                    -- ของเดิมเก็บแค่ชื่อที่โชว์แล้วส่งมันเป็นคีย์ ซึ่งบังเอิญตรงกัน
                    -- เพราะคีย์คือชื่อตัวพิมพ์เล็ก  บังเอิญไม่ใช่การออกแบบ
                    a.person    = b.disp
                    a.personKey = b.key
                    -- ขอบัญชีของคนนี้จากเซิร์ฟ  ไม่ได้เกาะไปกับ sync (ดู S.accView)
                    if b.key then req(KR.CMD.ACC_VIEW, { to = b.key }) end
                elseif b.act == "unlockone" then
                    req(KR.CMD.ADMIN_UNLOCK, { to = b.who })
                elseif b.act == "preview" then
                    -- พรีวิวมุมผู้เล่น  ออกได้จากแถบเตือนที่คาอยู่ก้นจอตลอดเวลา
                    KRShopUI.asPlayer = true
                    self.page   = "store"
                    self.scroll = 0

                elseif b.act == "gcur" then
                    a.gcur = cycle({ KR.CUR.HF, KR.CUR.CASH }, a.gcur)
                end
                return true
            end
        end

        -- กระดานราคา  ชิปสกุล · กดแถวเพื่อแก้ · ปุ่มลบ
        for _, b in ipairs(order) do
            if U.hit(b, x, y) and b.act then
                if b.act == "bdcur" then
                    a.bdCur = b.val
                    return true
                elseif b.act == "bdedit" then
                    self:bdLoad(b.val)
                    return true
                elseif b.act == "bddel" then
                    req(KR.CMD.BOARD_DEL, { id = b.val })
                    if a.bdId == b.val then self:bdLoad(nil) end
                    return true
                end
            end
        end

        -- อยู่ในแผ่นลอยแต่ไม่โดนแถวไหนเลย = **กินคลิกทิ้ง** ห้ามปล่อยทะลุ
        -- คลิกขอบแผ่นแล้วไปโดนปุ่ม Save หรือปุ่มลบของข้างหลัง คือความเสียหายที่กู้ไม่ได้
        if inCover then return true end

        -- ---- กระดานราคาโลก  (0.7.0) ------------------------------------
        if self.bBdSave and U.hit(self.bBdSave, x, y) then
            req(KR.CMD.BOARD_SET, {
                id    = a.bdId,
                name  = self.fields.bdName:getInternalText(),
                cat   = self.fields.bdCat:getInternalText(),
                price = math.floor(tonumber(self.fields.bdPrice:getInternalText() or "") or 0),
                cur   = a.bdCur or KR.CUR.CASH,
                note  = self.fields.bdNote:getInternalText(),
            })
            self:bdLoad(nil)
            return true
        end
        if self.bBdClear and U.hit(self.bBdClear, x, y) then
            self:bdLoad(nil); return true
        end

        if U.hit(self.bAdmSave, x, y) then
            req(KR.CMD.ADMIN_SAVE, self:admArgs())
            self:admLoad(nil)
            return true
        end
        if U.hit(self.bAdmClear, x, y) or U.hit(self.bAdmNew, x, y) then
            self:admLoad(nil); return true
        end
        if U.hit(self.bStallSave, x, y) then
            req(KR.CMD.ADMIN_MARKET_SET,
                { id = a.stall, name = self.fields.stallName:getInternalText() })
            return true
        end
        if U.hit(self.bStallDel, x, y) then
            req(KR.CMD.ADMIN_MARKET_SET, { id = a.stall, del = true })
            a.stall = nil
            return true
        end
        if self.bUnlock and U.hit(self.bUnlock, x, y) then
            req(KR.CMD.ADMIN_UNLOCK, { to = a.personKey or a.person })
            return true
        end
        if U.hit(self.bGrant, x, y) then
            -- ผู้รับคือคนที่เลือกไว้ในลิสต์  ไม่มีช่องพิมพ์ชื่ออีกแล้ว
            -- ชื่อที่พิมพ์เองคือชื่อที่พิมพ์ผิดได้ และเงินที่โอนผิดคนคือเงินที่เอาคืนไม่ได้
            if not a.personKey then
                KRShop.notify(KR.L("เลือกผู้เล่นจากลิสต์ทางซ้ายก่อน",
                                   "Pick a player from the list first"), "bad")
                return true
            end
            req(KR.CMD.ADMIN_GRANT, {
                to     = a.personKey,
                cur    = a.gcur,
                amt    = tonumber(self.fields.grantAmt:getInternalText()),
                reason = self.fields.grantWhy:getInternalText(),
            })
            self.fields.grantAmt:setText("")
            return true
        end
        return true
    end

    -- ---- แผงของในชุดเปิดอยู่ = มันกินคลิกทั้งหมด  (0.6.12) -------------------
    -- แผ่นลอยที่ไม่กินคลิกคือแผ่นที่คนกดทะลุไปโดนแถวข้างหลังโดยไม่ตั้งใจ
    -- ในร้านที่กดแล้วเสียเงิน อุบัติเหตุแบบนั้นแพงเป็นตัวเงินจริง
    if self.setView then
        for _, b in ipairs(self.rowBtns or {}) do
            if b.act == "setclose" and U.hit(b, x, y) then
                self.setView = nil
                return true
            end
        end
        -- กดนอกแผงก็ปิด  ทางออกที่หาไม่เจอคือกับดัก
        self.setView = nil
        return true
    end

    for _, b in ipairs(self.rowBtns or {}) do
        if U.hit(b, x, y) then
            -- ปุ่ม More ของชุด  เปิดแผงบอกว่าในชุดมีอะไร ไม่ใช่เริ่มซื้อ
            -- **คนต้องเห็นของก่อนจ่าย** ชุดที่ต้องซื้อก่อนถึงจะรู้ว่ามีอะไร ไม่ใช่ชุด มันคือการพนัน
            if b.act == "setmore" then
                self.setView = b.entry and b.entry.id or nil
                return true
            end
            if b.act then return true end        -- ปุ่มอื่นที่ไม่ใช่ปุ่มซื้อ
            local opts = KR.payOptions(b.entry)
            if #opts == 0 then return true end
            -- ถ้ามีทางเดียว ไม่ต้องถามให้เสียเวลา  ซื้อเลย
            if #opts == 1 then
                sendBuy(b.entry.id, 1)
            else
                -- เทียบด้วย "หมายเลข" ไม่ใช่ตัวตาราง
                -- KR.payOptions สร้างตารางใหม่ทุกครั้งที่เรียก  เทียบด้วย == จะไม่มีวันตรง
                local best = KR.bestOption(b.entry, nowTs())
                self.pay = { entry = b.entry, opts = opts, sel = best or 1 }
            end
            return true
        end
    end
    return true
end

function KRShop:onMouseWheel(del)
    if self.help then return true end
    if self.pay then return true end
    -- ลิสต์ผลค้นไอเทมลอยอยู่บนสุด  ล้อต้องเลื่อนมัน ไม่ใช่ลิสต์ที่อยู่ข้างหลัง
    -- (กติกาเดียวกับ auctMenu ข้างล่าง)
    if self.itemOpen then
        self.itemScroll = math.max(0, math.min((self.itemScroll or 0) + del,
                                               self.itemMax or 0))
        return true
    end
    -- เมนูไอคอนยาวกว่าที่ว่างเสมอ  ล้อเมาส์ต้องเลื่อน "เมนู" ไม่ใช่ลิสต์ที่อยู่ข้างหลังมัน
    -- view/total ถูกเซ็ตไว้ตอนวาด เพราะจำนวนแถวที่โผล่ได้ขึ้นกับที่ว่างจริงในเฟรมนั้น
    if self.auctMenu then
        local m = self.auctMenu
        local maxScroll = math.max(0, (m.total or 0) - (m.view or 1))
        m.scroll = math.max(0, math.min((m.scroll or 0) + del, maxScroll))
        return true
    end
    -- ฟอร์มโอนเปิดอยู่ = ล้อต้องเลื่อน "รายชื่อผู้รับ" ไม่ใช่ตารางประวัติที่อยู่ข้างหลัง
    -- ต้องมาก่อนสาขาของหน้า Account เพราะฟอร์มนี้วาดทับหน้านั้นทั้งหน้า
    -- (นี่คือครึ่งหนึ่งของบั๊ก "เลื่อนไม่ได้" — อีกครึ่งคือลิสต์ไม่มีที่ให้เลื่อนตั้งแต่ต้น)
    if self.page == "account" and self.sendOpen then
        self.sendScroll = math.max(0, math.min((self.sendScroll or 0) + del,
                                               self.sendMax or 0))
        return true
    end
    if self.page == "board" then
        self.boardScroll = math.max(0, (self.boardScroll or 0) + del * 40)
        return true
    end
    if self.page == "stats" then
        self.statScroll = math.max(0, (self.statScroll or 0) + del * 40)
        return true
    end
    -- หน้า Account เลื่อนตารางประวัติ ไม่ใช่ลิสต์ของ  มันเป็นสิ่งเดียวในหน้านั้นที่ยาวเกินจอ
    if self.page == "account" and not self.sendOpen then
        self.logScroll = math.max(0, (self.logScroll or 0) + del * 40)
        return true
    end
    -- แท็บ Players: เมาส์อยู่เหนือตารางประวัติของคนที่เปิดดูอยู่ = เลื่อนตารางนั้น
    -- ไม่งั้นล้อไปเลื่อนรายชื่อทางซ้ายแทน ซึ่งคือสิ่งที่คนไม่ได้ตั้งใจเลื่อนตอนกำลังอ่านประวัติ
    if self.page == "admin" and self.adm and self.adm.tab == "people"
       and self.logRectAdm and U.hit(self.logRectAdm, self.mx, self.my) then
        self.logScroll_adm = math.max(0, (self.logScroll_adm or 0) + del * 40)
        return true
    end
    self.scroll = math.max(0, self.scroll + del * 40)
    return true
end

function KRShop:onRightMouseUp(x, y)
    -- คลิกขวาปิดสิ่งที่เปิดอยู่บนสุดทีละชั้น  ไม่ใช่ปิดทุกอย่างพร้อมกัน
    if self.help then self.help = nil; return true end
    if self.pay  then self.pay  = nil; return true end
    return true
end

-- ==============================================================================
-- หน้า Auction กับ Credit
--
-- เคยแยกเป็นไฟล์ KR_UI_Pages.lua  ซึ่งเป็นความผิดพลาดที่ทำให้ทั้งสองหน้าตายสนิท
--
-- PZ โหลดไฟล์ใน media/lua/client แบบ "เรียงตามชื่อ" แล้วรันทีละไฟล์
--   KR_UI_Account -> KR_UI_Pages -> KR_UI_Shop
-- แปลว่า KR_UI_Pages ถูกรันตอนที่ยังไม่มี KRShop
-- บรรทัดแรกของมันคือ KRShop.ATABS = {...} -> index ของ nil -> ไฟล์ตายทั้งไฟล์
-- แล้ว require ที่ท้าย KR_UI_Shop ก็ไม่ช่วย เพราะ package.loaded ถูกตั้งไปแล้ว
--
-- ผลคือ drawAuction / drawCredit / pagesClick ไม่เคยถูกผูกเข้ากับ KRShop เลย
-- กด AUCTION แล้วเจอ error ทุกเฟรม (ผู้เล่นรายงานว่า "เทสการประมูลไม่ได้")
--
-- บทเรียน: ไฟล์ที่ "เติมเมธอดให้คลาสในอีกไฟล์" ห้ามแยกไฟล์ใน PZ
-- เพราะเราคุมลำดับโหลดไม่ได้  ต้องอยู่ไฟล์เดียวกับที่ประกาศคลาสนั้น
-- ==============================================================================

-- ==============================================================================
-- ประมูล
-- ==============================================================================
KRShop.ATABS = {
    { id = "open", label = "Open lots" },
    { id = "mine", label = "My bids"   },
    { id = "sell", label = "My lots"   },
}

-- ชุดสำรองของไอคอนล็อต
--
-- มีไว้เพื่อกรณีเดียว: ร้านยังไม่มีของสักชิ้น (เซิร์ฟเปิดใหม่)
-- ถ้าไม่มีชุดนี้ เมนูจะว่างเปล่า แล้วแอดมินจะเจอ "ปุ่มที่กดแล้วไม่มีอะไรขึ้น"
-- ซึ่งแย่กว่าช่องพิมพ์อิสระที่เพิ่งถอดออกไปเสียอีก
-- เลือกเฉพาะชนิดวนิลลาที่มีมาตั้งแต่ B41 และยังอยู่ใน B42  โอกาสหายน้อยที่สุด

-- ของในกระเป๋าตัวเอง  ใช้ตอนผู้เล่นธรรมดาเปิดล็อต
--
-- ผู้เล่นลงขายได้เฉพาะของที่ตัวเองถืออยู่จริง เพราะเซิร์ฟจะยึดของนั้นทันทีที่กด
-- เอาทะเบียนไอเทมทั้งบิลด์มาให้เลือกจึงเป็นการหลอกให้เลือกของที่ไม่มีวันผ่าน
--
-- กรองของที่สวมอยู่ / ถือในมือ / ติดดาว ออกตั้งแต่ตรงนี้ ให้ตรงกับที่เซิร์ฟกรอง
-- ด่านจริงอยู่ฝั่งเซิร์ฟ แต่ลิสต์ที่โชว์ของที่กดแล้วโดนปฏิเสธคือลิสต์ที่โกหก
--
-- isEquipped() ครอบคลุมแค่ของในมือ  เสื้อผ้าที่สวมอยู่ต้องถาม getWornItems() ต่างหาก
-- แหวนบนนิ้วคือตัวที่คนเผลอลงขายบ่อยที่สุด เพราะมันดูเหมือนของหลวมในกระเป๋า
local function invItemList()
    local out, seen = {}, {}
    local p = getSpecificPlayer and getSpecificPlayer(0)
    local inv = p and p:getInventory()
    if not inv then return out end

    local worn = {}
    local okW, wl = pcall(function() return p:getWornItems() end)
    if okW and wl then
        local okN, n = pcall(function() return wl:size() end)
        for i = 0, (okN and n or 0) - 1 do
            local slot = wl:get(i)
            if slot then
                local okI, it = pcall(function() return slot:getItem() end)
                if okI and it then worn[it] = true end
            end
        end
    end

    local okL, list = pcall(function() return inv:getItems() end)
    if not okL or not list then return out end
    local okN, n = pcall(function() return list:size() end)
    for i = 0, (okN and n or 0) - 1 do
        local it = list:get(i)
        if it and not worn[it] then
            local skip = false
            for _, m in ipairs({ "isFavorite", "isEquipped" }) do
                if not skip then
                    local okV, v = pcall(function() return it[m](it) end)
                    if okV and v then skip = true end
                end
            end
            if not skip then
                local okT, ft = pcall(function() return it:getFullType() end)
                if okT and ft then
                    if not seen[ft] then seen[ft] = 0 end
                    seen[ft] = seen[ft] + 1
                end
            end
        end
    end

    for ft, cnt in pairs(seen) do out[#out + 1] = { t = ft, n = cnt } end
    table.sort(out, function(a, b) return itemDisplay(a.t) < itemDisplay(b.t) end)
    return out
end

-- จำนวนที่ลงขายได้ของชนิดหนึ่ง  ใช้กันไม่ให้กรอกเกินของที่มี
function KRShop:invCountOf(fullType)
    for _, r in ipairs(invItemList()) do
        if r.t == fullType then return r.n end
    end
    return 0
end

-- รายการที่จะโชว์ในตัวเลือก
--
-- ผู้เล่น   ของในกระเป๋าตัวเองเท่านั้น  ไม่มีตัวเลือก "ไม่ผูกไอเทม"
--          เพราะล็อตที่ไม่มีของคือสัญญาว่าจะส่งมือ ซึ่งบังคับให้ทำจริงไม่ได้
--          จึงเป็นสิทธิ์ของแอดมินอย่างเดียว
--
-- แอดมิน   1. ""             ไม่ผูกไอเทม  อยู่บนสุดเพราะเป็นทางออกจากการเลือกผิด
--          2. ของในร้านจริง   แอดมินมักลงประมูลของแนวเดียวกับที่ขายอยู่
--          3. ทั้งบิลด์        กรองด้วยคำค้น
-- ทุกตัวถูกยืนยันกับ ScriptManager แล้วว่ามีจริง จึงไม่มีทางเลือกของที่เซิร์ฟจะตีกลับ
-- รายชื่อรุ่นรถที่ตรงคำค้น  รูปทรงเดียวกับ itemPickList เป๊ะ (array ของค่าที่จะเขียนลงช่อง)
-- เพื่อให้ลิสต์แบบเลื่อนได้ตัวเดียวรับได้ทั้งสองแบบโดยไม่ต้องเขียนลิสต์ที่สอง
-- ลิสต์ที่สองคือลิสต์ที่แถบเลื่อนพังคนละแบบกับลิสต์แรก แล้วไม่มีใครสังเกต
-- ลิสต์ของที่จ่ายเป็นใบ  รถหรือสัตว์ตาม sp ที่ส่งมา
-- เมธอดเดียวสองชนิด  ลิสต์ที่สองจะเริ่มขาดของที่ตัวแรกเพิ่งได้มาในวันที่ไม่มีใครดู
function KRShop:specPickList(sp, find)
    find = tostring(find or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local out = { "" }            -- แถวว่างไว้ล้างค่า  เหมือนลิสต์ไอเทม
    for _, r in ipairs(specRows(sp)) do
        local hay = (tostring(r.id) .. " " .. tostring(r.label or "")):lower()
        if find == "" or hay:find(find, 1, true) then out[#out + 1] = r.id end
    end
    return out
end

function KRShop:itemPickList(find)
    find = tostring(find or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if not isAdminView() then
        local out = {}
        for _, r in ipairs(invItemList()) do
            if find == "" or (r.t .. " " .. itemDisplay(r.t)):lower():find(find, 1, true) then
                out[#out + 1] = r.t
            end
        end
        return out
    end

    local seen, out = {}, { "" }

    local function push(t)
        if t == "" or seen[t] then return end
        seen[t] = true
        out[#out + 1] = t
    end

    local shop = {}
    for _, e in pairs(data().catalog or {}) do
        if type(e.item) == "string" and e.item ~= "" and not shop[e.item] then
            shop[e.item] = true
        end
    end
    local shopList = {}
    for t in pairs(shop) do shopList[#shopList + 1] = t end
    table.sort(shopList)
    for _, t in ipairs(shopList) do
        if itemKnown(t) and (find == "" or (t .. " " .. itemDisplay(t)):lower():find(find, 1, true)) then
            push(t)
        end
    end

    -- ไม่ได้พิมพ์ค้นหา = ไม่เทของทั้งเกมลงมา  หลายพันบรรทัดไม่ได้ช่วยใครเลือกเร็วขึ้น
    -- พิมพ์แล้วค่อยไล่  และจำกัดจำนวนแถวไว้ ไม่งั้นคำว่า "a" ลากทั้งทะเบียนมาวาด
    if find ~= "" then
        local n = 0
        for _, r in ipairs(itemIndex()) do
            if r.l:find(find, 1, true) then
                push(r.t)
                n = n + 1
                if n >= 120 then break end
            end
        end
    end

    return out
end

function KRShop:auctRows()
    local all = data().auction or {}
    local tab = self.auctTab or "open"
    local out = {}
    for i = 1, #all do
        local r = all[i]
        local keep
        if tab == "mine" then
            keep = r.iBid == true
        elseif tab == "sell" then
            keep = r.mine == true
        else
            keep = not r.done
        end
        if keep then out[#out + 1] = r end
    end
    return out
end

function KRShop:drawAuction(x, y, w, h)
    local d = data()
    self.auctTab  = self.auctTab or "open"
    self.auctBtns = {}
    self.tabBtns  = {}

    -- ------------------------------------------------------------------------
    -- ระบบประมูลพักไว้  ดูเหตุผลที่ KR.AUCTION_ON ใน KR_Const
    --
    -- ล้าง auctOpen / auctNew ทิ้งด้วย  ไม่ใช่แค่ไม่วาด
    -- ค่าที่ค้างอยู่แปลว่าฟอร์มเปิดล็อตยังกินคีย์บอร์ดอยู่ผ่านช่องกรอกของมัน
    -- (ตอนนี้ด่านผังจับเรื่องนี้ได้แล้ว แต่ทางที่ถูกคือไม่สร้างเคสให้มันต้องจับ)
    -- ------------------------------------------------------------------------
    if not KR.auctionOpen() then
        self.auctOpen, self.auctNew, self.auctMenu = nil, false, nil
        U.emptyState(self, x, y, w, h,
                     KR.L("ระบบประมูล  ·  เร็ว ๆ นี้", "Auctions  ·  coming soon"),
                     KR.L("กำลังเก็บรายละเอียดอยู่  จะเปิดให้ใช้พร้อมกันทั้งเซิร์ฟเมื่อพร้อม",
                          "Still being finished. It will open for the whole server at once."))
        return
    end

    -- ------------------------------------------------------------------------
    -- เปิดล็อตเดียวอยู่ = วาดหน้ารายละเอียดแทนกระดานทั้งหน้า
    --
    -- หาจากรายการที่เซิร์ฟส่งมารอบล่าสุดเสมอ ไม่ได้เก็บสำเนาของล็อตไว้ฝั่งจอ
    -- ล็อตที่หายไประหว่างที่เปิดค้างไว้ (หมดเวลา ถูกกวาด ถูกถอน) จะเด้งกลับกระดานเอง
    -- ถ้าเก็บสำเนาไว้ หน้าจะค้างแสดงราคาเก่าของล็อตที่ไม่มีอยู่แล้ว แล้วกดบิดไม่ติด
    -- โดยไม่มีอะไรอธิบายว่าทำไม
    -- ------------------------------------------------------------------------
    if self.auctOpen then
        local lots = d.auction or {}
        local one
        for i = 1, #lots do
            if lots[i].id == self.auctOpen then one = lots[i]; break end
        end
        if one then
            self:drawAuctLot(x, y, w, h, one)
            return
        end
        self.auctOpen = nil
    end

    -- แท็บย่อย  แต่ละแท็บบอกจำนวนของตัวเองด้วย
    -- ไม่มีตัวเลขแล้วต้องกดเข้าไปดูทีละแท็บถึงจะรู้ว่ามีอะไรอยู่หรือเปล่า
    local all = d.auction or {}
    local nOpen, nMine, nSell = 0, 0, 0
    for i = 1, #all do
        local r = all[i]
        if not r.done then nOpen = nOpen + 1 end
        if r.iBid == true then nMine = nMine + 1 end
        if r.mine == true then nSell = nSell + 1 end
    end
    local counts = { open = nOpen, mine = nMine, sell = nSell }

    local tx = x
    local th2 = math.max(28, U.h(U.F.s) + 12)
    for i = 1, #KRShop.ATABS do
        local t   = KRShop.ATABS[i]
        local on  = (self.auctTab == t.id)
        local lbl = t.label .. "  " .. tostring(counts[t.id] or 0)
        local tw2 = U.w(lbl, U.F.s) + 26
        local hot = U.hit({ x = tx, y = y, w = tw2, h = th2 }, self.mx, self.my)
        U.fill(self, tx, y, tw2, th2, on and U.C.accent2 or (hot and U.C.bgRow or U.C.bgCard))
        if on then U.fill(self, tx, y + th2 - 2, tw2, 2, U.C.accent) end
        U.textC(self, lbl, tx + tw2 / 2, y + math.floor((th2 - U.h(U.F.s)) / 2),
                on and U.C.text or U.C.mute, U.F.s)
        self.tabBtns[#self.tabBtns + 1] = { x = tx, y = y, w = tw2, h = th2, tab = t.id }
        tx = tx + tw2 + 5
    end

    -- แอดมินเปิดล็อตได้จากตรงนี้
    --
    -- ก่อนหน้านี้ไม่มีทางสร้างล็อตจากในเกมเลย  ต้องแก้ DB มือ
    -- ผู้เล่นรายงานว่า "เทสการประมูลไม่ได้" ซึ่งถูก — ไม่มีปุ่มให้กดจริง ๆ
    --
    -- ใครเปิดล็อตได้
    --   แอดมิน (ในมุมมองแอดมิน)  ได้เสมอ  ล็อตของร้านไม่ได้ยึดของจากใคร
    --   ผู้เล่น                    ได้เมื่อเซิร์ฟเปิด AuctionPlayerSell
    --                              ของจะถูกยึดจากกระเป๋าตั้งแต่ตอนกดลงขาย
    --
    -- ธง canSell มาจากเซิร์ฟ ไม่ได้เดาจากฝั่งจอ  ปุ่มที่กดแล้วโดนปฏิเสธคือปุ่มที่ไม่ควรมี
    if canOpenLot() then
        local nb = U.btn(self, x + w - 150, y, 150, th2,
                         self.auctNew and KR.L("ปิดฟอร์ม", "Close form")
                                       or KR.L("+ เปิดล็อตใหม่", "+ New lot"),
                         self.auctNew and "neu" or "pri", self.mx, self.my)
        nb.act = "auctform"
        self.auctBtns[#self.auctBtns + 1] = nb

        -- ช่องประมูล  บอกว่าใช้ไปกี่ช่องจากกี่ช่อง แล้วขายช่องเพิ่มตรงนั้นเลย
        --
        -- วางไว้ติดกับปุ่มเปิดล็อตเพราะนั่นคือวินาทีที่คนรู้ตัวว่าช่องไม่พอ
        -- เอาไปซ่อนในหน้าอื่นแปลว่าคนที่ต้องการมันจะหาไม่เจอตอนที่ต้องการ
        local used = 0
        for i = 1, #all do
            if all[i].mine and not all[i].done then used = used + 1 end
        end
        local slots = tonumber(d.auctSlots) or 1
        local sTxt  = KR.L("ช่อง ", "Slots ") .. used .. " / " .. slots
        local sw    = U.w(sTxt, U.F.xs) + 16
        local sx    = x + w - 150 - 8 - sw
        U.textR(self, sTxt, x + w - 158, y + math.floor((th2 - U.h(U.F.xs)) / 2),
                used >= slots and U.C.warn or U.C.mute, U.F.xs)

        if slots < (tonumber(d.auctSlotMax) or 10) then
            local price = tonumber(d.auctSlotPrice) or 0
            local lbl   = KR.L("+ ซื้อช่อง ", "+ Slot ") .. money(price)
            local bw3   = U.w(lbl, U.F.s) + 24
            local bx3   = sx - bw3 - 8
            if bx3 > x + 240 then
                local sb = U.btn(self, bx3, y, bw3, th2, lbl,
                                 ((d.bal or {}).cash or 0) >= price and "neu" or "offb",
                                 self.mx, self.my)
                if ((d.bal or {}).cash or 0) >= price then
                    sb.act = "auctslot"
                    self.auctBtns[#self.auctBtns + 1] = sb
                end
            end
        end
    end

    local ly = y + th2 + 8

    -- ฟอร์มเปิดล็อต  ใช้ช่องกรอกตัวเดิมจากหน้าจัดการ ไม่สร้างใหม่
    --
    -- ทำไมต้องเป็นสองแถว
    --   ของเดิมยัดหกชิ้นลงแถวเดียว: สี่ช่องกรอกกว้าง quarter + ปุ่มเลือก 92 + พรีวิว 46
    --   quarter คิดจาก (w - 40 - 46 - 92) / 4  แต่ระหว่างชิ้นยังมีช่องไฟชิ้นละ 8 อีกห้าที่
    --   ซึ่งไม่ได้ถูกหักออกจากตัวหาร  พิกเซลขวาสุดจึงตกที่ x + w + 8 คือเลยขอบไปแล้ว
    --   ปุ่มเลือกกับกล่องพรีวิวเลยโดนขอบหน้าต่างตัดทิ้ง
    --   (เจ้าของเซิร์ฟส่งรูปมา กล่องพรีวิวถูกผ่าครึ่งพอดี)
    --
    --   รากของปัญหาคือทิศทางการคิด: เอา "เลขที่พิมพ์ไว้" มาหารก่อน แล้วค่อยวางเรียงไปเรื่อย ๆ
    --   แบบนั้นความกว้างรวมเป็นผลลัพธ์ที่ไม่มีใครควบคุม  จะเกินหรือไม่เกินก็แล้วแต่โชค
    --   ของใหม่คิดกลับด้าน: ตรึงขอบซ้ายกับขอบขวาไว้ก่อน แล้วให้ช่องที่ยืดได้กินที่ที่เหลือ
    --   ทุกพิกัดมาจาก x กับ w เท่านั้น  พิกเซลขวาสุดของทั้งสองแถวเท่ากับ right เป๊ะโดยนิยาม
    if self.auctNew and canOpenLot() then
        -- --------------------------------------------------------------------
        -- ฟอร์มเปิดล็อต  (0.5)
        --
        -- ไม่มีช่องเลือกไอเทมแล้ว  ล็อตไม่ได้ผูกกับของในกระเป๋าอีกต่อไป
        -- ผู้ขายเขียนเองว่าขายอะไร แล้วไปนัดรับกับผู้ชนะเอง ระบบดูแลแต่เงิน
        --
        -- สามแถว เรียงตามลำดับที่คนกรอกจริง ๆ
        --   1. ขายอะไร ราคาเท่าไร
        --   2. บิดละเท่าไร ซื้อทันทีเท่าไร กี่ชั่วโมง
        --   3. หน้าตาการ์ด (รูปปก + สีพื้น) แล้วปุ่มเปิด
        -- --------------------------------------------------------------------
        local fh2  = boxH()
        local pad  = 8
        local gap  = 8
        local lblH = U.h(U.F.xs) + 3
        local left  = x + pad
        local right = x + w - pad
        local avail = right - left

        local row1Y = ly + 8
        local row2Y = row1Y + lblH + fh2 + 10
        local row3Y = row2Y + lblH + fh2 + 12
        local artY  = row3Y + lblH
        local artH  = math.max(fh2, 44)
        local hintY = artY + artH + 8
        local formH = (hintY + U.h(U.F.xs) + 10) - ly
        U.fill(self, x, ly, w, formH, U.C.bgHead)

        -- แถว 1 : ชื่อสินค้า (ยืด) + ราคาเริ่ม
        local startW = math.floor(math.min(180, avail * 0.30))
        local nameW  = avail - startW - gap
        fieldBox(self, self.fields.name, left, row1Y, nameW,
                 KR.L("ขายอะไร", "What are you selling"))
        fieldBox(self, self.fields.stock, left + nameW + gap, row1Y, startW,
                 KR.L("ราคาเริ่ม (บาท)", "Start price (baht)"))

        -- แถว 2 : บิดละ + ซื้อทันที + ชั่วโมง  สามช่องเท่ากัน
        local third = math.floor((avail - gap * 2) / 3)
        local last3 = avail - gap * 2 - third * 2
        fieldBox(self, self.fields.auctStep, left, row2Y, third,
                 KR.L("บิดละ (0 = อัตโนมัติ)", "Bid step (0 = auto)"))
        fieldBox(self, self.fields.auctBuy, left + third + gap, row2Y, third,
                 KR.L("ซื้อทันที (0 = ไม่มี)", "Buy now (0 = none)"))
        -- ระยะเวลาเป็น "นาที" ทั้งม็อดตั้งแต่ 0.6.0
        -- ชั่วโมงเป็นหน่วยที่หยาบเกินไปสำหรับล็อตที่คนอยากเปิดสั้น ๆ ตอนคนออนไลน์เยอะ
        fieldBox(self, self.fields.quota, left + (third + gap) * 2, row2Y, last3,
                 KR.L("กี่นาที", "Minutes"))

        -- แถว 3 : รูปปก  ชิปเรียงกันไป เลือกด้วยการกด
        self.auctArt = self.auctArt or KR.AUCT_ART_DEFAULT
        self.auctBg  = self.auctBg  or KR.AUCT_BG_DEFAULT
        U.text(self, KR.L("รูปปก", "Cover"), left, row3Y, U.C.dim, U.F.xs)

        local openW = math.floor(math.min(160, math.max(110, avail * 0.24)))
        local artArea = avail - openW - gap
        local cell = math.max(30, math.min(44, math.floor((artArea - 13 * 4) / 14)))
        local ax = left
        for _, a in ipairs(KR.AUCT_ART) do
            local on  = (self.auctArt == a.id)
            local hot = U.hit({ x = ax, y = artY, w = cell, h = cell }, self.mx, self.my)
            U.fill(self, ax, artY, cell, cell, on and U.C.accent2 or (hot and U.C.bgRow or U.C.bgCard))
            if on then U.border(self, ax, artY, cell, cell, U.C.accent) end
            U.auctArt(self, a.id, ax + 3, artY + 3, cell - 6,
                      on and U.C.text or (hot and U.C.lite or U.C.mute))
            local ab = { x = ax, y = artY, w = cell, h = cell, act = "auctart", val = a.id }
            self.auctBtns[#self.auctBtns + 1] = ab
            ax = ax + cell + 4
        end

        local ob = U.btn(self, right - openW, artY, openW, math.max(fh2, 34),
                         KR.L("เปิดประมูล", "Open the lot"), "ok", self.mx, self.my)
        ob.act = "auctcreate"
        self.auctBtns[#self.auctBtns + 1] = ob

        -- สีพื้นการ์ด  แถบสีเล็ก ๆ ใต้แถวรูปปก
        local by2 = artY + cell + 6
        if by2 + 16 < hintY then
            local bx2 = left
            for _, b in ipairs(KR.AUCT_BG) do
                local fillC, lineC = U.auctBg(b.id)
                local on = (self.auctBg == b.id)
                U.fill(self, bx2, by2, 34, 14, fillC)
                U.border(self, bx2, by2, 34, 14, on and U.C.accent or lineC)
                self.auctBtns[#self.auctBtns + 1] =
                    { x = bx2, y = by2, w = 34, h = 14, act = "auctbg", val = b.id }
                bx2 = bx2 + 38
            end
        end

        U.text(self, KR.L("ระบบไม่ได้ยึดของจากกระเป๋า  ผู้ชนะจ่ายมัดจำครึ่งหนึ่งตอนปิดล็อต แล้วคุณกับเขานัดรับกันเอง",
                          "Nothing is taken from your bag. The winner pays half up front, " ..
                          "then you two meet up to hand it over."),
               left, hintY, U.C.dim, U.F.xs)

        ly = ly + formH + 8
    end

    local lh = h - (ly - y)
    local rows = self:auctRows()

    if #rows == 0 then
        local t, hint
        if self.auctTab == "mine" then
            t, hint = KR.L("ยังไม่ได้ประมูลอะไร", "You have no bids"),
                      KR.L("ไปที่แท็บ Open lots แล้วกดประมูล", "Open lots is where the action is")
        elseif self.auctTab == "sell" then
            t = KR.L("ยังไม่ได้ลงขายอะไร", "You have nothing listed")
            if canOpenLot() then
                hint = KR.L("กด + เปิดล็อตใหม่ แล้วเลือกของจากกระเป๋า",
                            "Press + New lot and pick something out of your bag")
            else
                hint = KR.L("เซิร์ฟนี้ให้แอดมินลงขายเท่านั้น",
                            "This server keeps listing to admins")
            end
        else
            t = KR.L("ยังไม่มีของประมูล", "No open lots")
            -- คำใบ้ต้องตรงกับสิ่งที่อยู่บนจอตอนนั้นจริง ๆ
            -- ฟอร์มเปิดอยู่แล้วยังบอกให้ "กด + เปิดล็อตใหม่" ทั้งที่ปุ่มนั้นเขียนว่า ปิดฟอร์ม
            -- = สั่งให้ผู้ใช้ทำสิ่งที่จะพาถอยหลัง  แล้วเขาจะเชื่อคำใบ้อันอื่นน้อยลงไปด้วย
            if not isAdminView() then
                hint = KR.L("รอบหน้าจะขึ้นป้ายไฟบอกเอง", "The ticker will say when one opens")
            elseif self.auctNew then
                hint = KR.L("กรอกฟอร์มด้านบนแล้วกด เปิดประมูล",
                            "Fill in the form above, then press Open the lot")
            else
                hint = KR.L("กด + เปิดล็อตใหม่ ที่มุมขวาบนเพื่อเปิดล็อตแรก",
                            "Press + New lot at the top right to open the first one")
            end
        end
        U.emptyState(self, x, ly, w, lh, t, hint)
        self.auctSel = nil
        return
    end

    -- ------------------------------------------------------------------------
    -- ช่องบิดสดย้ายไปอยู่ในหน้ารายละเอียดล็อตแล้ว (0.6.0)
    --
    -- ของเดิมมันเกาะขวาของกระดานตลอดเวลาและกินความกว้างไปราวสามในสิบ
    -- เพื่อแสดงการบิดของล็อต "ที่ถูกเลือกอยู่" ซึ่งเป็นล็อตที่ระบบเดาให้เอง
    -- คนที่กำลังกวาดตาดูกระดานไม่ได้กำลังสนใจล็อตใดล็อตหนึ่ง = จ่ายที่ไปเปล่า ๆ
    -- ส่วนคนที่สนใจล็อตหนึ่งจริง ๆ ตอนนี้กด "เข้าไปดู" แล้วได้ช่องบิดที่กว้างกว่าเดิม
    --
    -- ผลพลอยได้: การ์ดได้ความกว้างคืนมาทั้งหมด รูปปกจึงใหญ่ได้ตามที่สั่ง
    self.auctSel = nil

    self:setStencilRect(x, ly, w, lh)

    -- ------------------------------------------------------------------------
    -- ตารางการ์ด แถวละสามใบ
    --
    -- ทำไมทิ้งลิสต์แถวยาวแบบเดิม
    --   แถวยาวเต็มความกว้างเหมาะกับของที่ "อ่านทีละบรรทัด" อย่างแคตตาล็อกร้าน
    --   ที่ตากวาดลงมาหาชื่อกับราคา  แต่ล็อตประมูลไม่ได้ถูกอ่านแบบนั้น
    --   คนดูประมูลกวาดหา "รูป + เวลาที่เหลือ" ก่อนเสมอ แล้วค่อยอ่านชื่อทีหลัง
    --   การ์ดวางรูปใหญ่กลางใบได้ และเอาสามใบมาเทียบกันในสายตาเดียว
    --
    -- ความกว้างการ์ดคิดย้อนจากขอบขวาเหมือนฟอร์มเปิดล็อต
    -- พิกเซลขวาสุดของคอลัมน์ที่สามเท่ากับ x + w - pad พอดีโดยนิยาม ไม่ได้เดา
    -- ------------------------------------------------------------------------
    local COLS = 3
    local pad  = 8
    local gap  = 10
    local availW = w - pad * 2 - gap * (COLS - 1)
    local cw   = math.floor(availW / COLS)
    -- เศษที่หารไม่ลงยกให้ใบสุดท้าย  ไม่งั้นขอบขวาจะขาดไปหนึ่งถึงสองพิกเซล
    local lastW = availW - cw * (COLS - 1)

    local btnH  = math.max(32, U.h(U.F.s) + 14)

    -- ความสูงของโซนรูป  ผูกกับความกว้างการ์ด ไม่ใช่ตัวเลขตายตัว
    --
    -- อัตราส่วนราว 5:3 ทำให้รูปดูเป็น "ปก" ไม่ใช่ "แถบสี"
    -- และเพราะมันคิดจาก cw ที่คิดย้อนจากขอบขวาอยู่แล้ว การ์ดจึงยังพอดีขอบเสมอ
    -- แม้ผู้เล่นจะตั้ง UI scale เท่าไรก็ตาม
    local artH  = math.max(72, math.min(140, math.floor(cw * 0.60)))
    local ch    = artH + 8 + U.h(U.F.m) + 2 + U.h(U.F.xs) + 6
                  + U.h(U.F.s) + 8 + btnH + 10
    local rowH  = ch + gap

    local cy = ly - (self.scroll or 0)

    for i = 1, #rows, COLS do
        if cy + ch > ly and cy < ly + lh then
            for c = 0, COLS - 1 do
                local r = rows[i + c]
                if r then
                    local bx = x + pad + c * (cw + gap)
                    local bw2 = (c == COLS - 1) and lastW or cw
                    self:drawAuctCard(bx, cy, bw2, ch, r, artH, btnH)
                end
            end
        end
        cy = cy + rowH
    end

    self:clearStencilRect()
    local totalRows = math.ceil(#rows / COLS)
    U.scrollbar(self, x + w - 3, ly, lh, totalRows * rowH, lh, self.scroll or 0)
end

-- ------------------------------------------------------------------------------
-- การ์ดล็อตหนึ่งใบ
--
-- ลำดับสายตาที่ตั้งใจ: รูป -> เวลาที่เหลือ -> ชื่อ -> ราคา -> ปุ่ม
-- เวลาที่เหลืออยู่บนรูปเลยเพราะมันคือตัวเลขที่ตัดสินว่า "ต้องรีบไหม"
-- ซึ่งสำคัญกว่าราคาในวินาทีแรกที่มองการ์ด
--
-- ล็อตของร้าน (official) ได้ขอบแดงกับป้าย SHOP  ไม่ใช่แค่สีต่าง
-- สีอย่างเดียวคนตาบอดสีอ่านไม่ออก และป้ายบอกด้วยว่า "ทำไม" มันเด่น
-- ------------------------------------------------------------------------------
function KRShop:drawAuctCard(x, y, w, h, r, artH, btnH)
    local hot = U.hit({ x = x, y = y, w = w, h = h }, self.mx, self.my)

    -- พื้นการ์ดเป็นสีของธีมเสมอ  สีที่ผู้ขายเลือกไปอยู่บน "พื้นที่รูป" อย่างเดียว
    --
    -- ของเดิมย้อมทั้งใบด้วยสีที่ผู้ขายเลือก  ผลคือตัวหนังสือชื่อกับราคาต้องอ่านบน
    -- พื้นหกสีที่ต่างกัน แล้วคู่สีบางคู่ก็อ่านไม่ออกจริง ๆ (amber กับ U.C.gold)
    -- แยกเป็นสองโซนแล้วสีของผู้ขายยังทำหน้าที่เดิมได้ครบ คือทำให้กระดานไม่จืด
    -- แต่โซนตัวหนังสือกลับมาอยู่บนพื้นเดียวที่คุมคอนทราสต์ได้
    U.fill(self, x, y, w, h, hot and U.C.bgRow or U.C.bgCard)

    -- ขอบ  แดง = ของร้าน  เขียว = เรานำอยู่  ส้ม = โดนแซง  ทอง = ล็อตเรา
    local bgC, edgeC = U.auctBg(r.bg)
    local edge = edgeC
    if r.official  then edge = U.C.bad
    elseif r.iAmTop then edge = U.C.good
    elseif r.iBid   then edge = U.C.warn
    elseif r.mine   then edge = U.C.gold end
    U.border(self, x, y, w, h, edge)

    -- ---- โซนรูป -------------------------------------------------------------
    -- เจ้าของเซิร์ฟสั่งว่า "ด้านบนเป็นไอคอนใหญ่ๆ"  รูปจึงกินความกว้างเต็มใบ
    -- ไม่ใช่รูปเล็กชิดซ้ายแบบเดิมที่ต้องแบ่งบรรทัดกับตัวหนังสือ
    U.fill(self, x + 1, y + 1, w - 2, artH, bgC)
    local isz = math.min(artH - 18, math.floor(w * 0.42))
    U.auctArt(self, r.art, x + math.floor((w - isz) / 2), y + math.floor((artH - isz) / 2) + 1,
              isz, r.done and U.C.mute or U.C.lite)
    if r.official then U.fill(self, x + 1, y + 1, w - 2, 3, U.C.bad) end

    -- ป้ายมุมซ้ายบน
    local tag, tagCol
    if r.official then tag, tagCol = KR.L("ของร้าน", "SHOP"), U.C.bad
    elseif r.mine  then tag, tagCol = KR.L("ของคุณ", "YOURS"), U.C.gold end
    if tag then
        local pw = U.w(tag, U.F.xs) + 10
        U.fill(self, x + 6, y + 6, pw, U.h(U.F.xs) + 4, tagCol)
        U.textC(self, tag, x + 6 + pw / 2, y + 7, U.C.bgDark, U.F.xs)
    end

    -- นาฬิกามุมขวาบน  วางบนแผ่นดำจาง ๆ เพื่อให้อ่านออกบนพื้นทั้งหกสี
    local timeS, timeCol
    if r.payIn then
        timeS, timeCol = KR.L("จ่ายใน ", "pay in ") .. KR.fmtDur(r.payIn), U.C.warn
    elseif r.done then
        if r.settled       then timeS, timeCol = KR.L("จ่ายครบแล้ว", "PAID"),    U.C.good
        elseif r.refunded  then timeS, timeCol = KR.L("หมดเวลา", "EXPIRED"),    U.C.mute
        elseif r.sold      then timeS, timeCol = KR.L("ขายแล้ว", "SOLD"),       U.C.good
        else                    timeS, timeCol = KR.L("ไม่มีคนซื้อ", "UNSOLD"), U.C.mute end
    else
        timeS   = KR.fmtDur(r.left or 0)
        timeCol = (r.left or 0) <= 300 and U.C.warn or U.C.lite
    end
    local tw2 = U.w(timeS, U.F.xs) + 12
    U.fill(self, x + w - tw2 - 6, y + 6, tw2, U.h(U.F.xs) + 4, U.C.bgDark, 0.75)
    U.textC(self, timeS, x + w - tw2 / 2 - 6, y + 7, timeCol, U.F.xs)

    -- ---- โซนตัวหนังสือ ------------------------------------------------------
    local cx = x + 10
    local cy = y + artH + 8

    U.text(self, KR.trunc(tostring(r.name or r.id), 22), cx, cy,
           r.done and U.C.mute or U.C.text, U.F.m)
    cy = cy + U.h(U.F.m) + 2

    U.text(self, KR.L("โดย ", "by ") .. tostring(r.seller or "-") ..
                 "   " .. tostring(r.bids or 0) .. KR.L(" บิด", " bids"),
           cx, cy, U.C.dim, U.F.xs)
    cy = cy + U.h(U.F.xs) + 6

    -- ราคาปัจจุบัน
    --
    -- เจ้าของเซิร์ฟสั่งมาว่าการ์ดมีแค่ ไอคอน/ชื่อ/ผู้ลง/เวลา/ปุ่ม แล้วผมถามกลับว่า
    -- ควรเก็บบรรทัดราคาไว้ไหม (คำถามข้อ 2) คำตอบคือ "ก. เก็บไว้"
    -- เหตุผลที่ผมเสนอ: กระดานที่ไม่บอกราคาบังคับให้เปิดทีละใบเพื่อรู้ว่าสู้ไหว
    U.coin(self, KR.CUR.CASH, cx, cy + 2, 15)
    U.text(self, money(r.bid), cx + 20, cy, U.C.cash, U.F.s)

    local note, nc
    if r.iAmTop then      note, nc = KR.L("คุณนำอยู่", "winning"), U.C.good
    elseif r.iBid then    note, nc = KR.L("โดนแซง", "outbid"),    U.C.bad
    elseif (r.bids or 0) == 0 then note, nc = KR.L("ราคาเริ่ม", "start"), U.C.mute
    else                  note, nc = tostring(r.top or "-"),      U.C.mute end
    U.textR(self, note, x + w - 10, cy + 1, nc, U.F.xs)

    -- ---- ปุ่ม ---------------------------------------------------------------
    -- ใบละหนึ่งปุ่มเสมอ = "เข้าไปดู"
    --
    -- ของเดิมยัด บิด / ซื้อเลย / ถอน / จ่าย ปนกันบนการ์ดตามสถานะ
    -- ปัญหาไม่ใช่เรื่องพื้นที่ แต่คือปุ่มที่ **เปลี่ยนความหมายไปเรื่อย ๆ ตำแหน่งเดิม**
    -- คนที่ชินกับการกดมุมล่างซ้ายเพื่อบิด วันหนึ่งจะกดโดน "ซื้อเลย" ในราคาสิบเท่า
    --
    -- ข้อยกเว้นเดียวคือใบที่ **ต้องจ่ายเงิน** ซึ่งพลาดแล้วเสียเงินจริง (เกิน 24 ชม.
    -- แล้วยังไม่จ่าย = คืนเงินให้ผู้ชนะ ล็อตหาย ทั้งสองฝ่ายเสียเวลาฟรี)
    -- เรื่องที่มีนาฬิกาเดินอยู่ต้องกดได้จากที่ที่เห็นมันครั้งแรก
    local by = y + h - btnH - 8
    local label, style, act = KR.L("เข้าไปดู", "View lot"), "pri", "open"
    if r.done and r.iAmTop and r.payIn and not r.settled then
        label, style, act = KR.L("จ่าย ", "Pay ") .. money(r.rest or 0), "ok", "auctpay"
    elseif r.done then
        style = "neu"
    end

    local b = U.btn(self, x + 8, by, w - 16, btnH, label, style, self.mx, self.my)
    b.act, b.lot, b.need = act, r.id, r.next
    self.auctBtns[#self.auctBtns + 1] = b

    -- ทั้งใบกดได้ด้วย  คนคาดหวังว่าการ์ดคือของชิ้นเดียว ไม่ใช่ปุ่มที่มีรูปประกอบ
    self.auctBtns[#self.auctBtns + 1] =
        { x = x, y = y, w = w, h = math.max(10, by - y - 4), act = "open", lot = r.id }
end

-- ------------------------------------------------------------------------------
-- หน้ารายละเอียดล็อต  เปิดจากปุ่ม "เข้าไปดู"
--
-- ทำไมต้องมีหน้านี้แทนที่จะยัดทุกอย่างลงการ์ด
--   การ์ดถูกออกแบบให้ "กวาดตาเทียบกันหลายใบ"  หน้านี้ถูกออกแบบให้ "ตัดสินใจใบเดียว"
--   สองงานนี้ต้องการข้อมูลคนละชุดและคนละความหนาแน่น
--   ยัดรวมกันแปลว่ากระดานรกจนกวาดตาไม่ได้ และหน้าตัดสินใจก็ยังข้อมูลไม่พอ
--
-- ช่องบิดสด (drawAuctFeed) ย้ายมาอยู่ที่นี่  ของเดิมมันเกาะขวาของกระดานตลอดเวลา
-- และกินความกว้างไปสามในสิบทั้งที่คนส่วนใหญ่ไม่ได้กำลังดูล็อตใดล็อตหนึ่งอยู่
-- ------------------------------------------------------------------------------
function KRShop:drawAuctLot(x, y, w, h, r)
    local d  = data()
    local ts = nowTs()

    -- ปุ่มกลับ  อยู่บนสุดซ้ายเสมอ ตำแหน่งเดียวกับที่ทุกโปรแกรมวางไว้
    local bh2 = math.max(28, U.h(U.F.s) + 12)
    local bb  = U.btn(self, x, y, 120, bh2, KR.L("< กลับ", "< Back"), "neu", self.mx, self.my)
    bb.act = "auctback"
    self.auctBtns[#self.auctBtns + 1] = bb
    U.textR(self, "#" .. tostring(r.id), x + w, y + math.floor((bh2 - U.h(U.F.xs)) / 2),
            U.C.dim, U.F.xs)

    local ly = y + bh2 + 10
    local lh = h - (ly - y)

    -- สามคอลัมน์  รูป / เนื้อหา / ช่องบิดสด
    -- ช่องบิดสดหายไปเมื่อจอแคบ  ข้อมูลที่สำคัญกว่าคือปุ่มบิด
    local feedW = (w >= 640) and math.max(200, math.min(300, math.floor(w * 0.28))) or 0
    local artW  = (w >= 520) and math.max(150, math.min(230, math.floor(w * 0.22))) or 0
    local midX  = x + (artW > 0 and (artW + U.GAP) or 0)
    local midW  = w - (artW > 0 and (artW + U.GAP) or 0) - (feedW > 0 and (feedW + U.GAP) or 0)

    -- ---- คอลัมน์รูป ---------------------------------------------------------
    if artW > 0 then
        local bgC, edgeC = U.auctBg(r.bg)
        local ah = math.min(math.floor(lh * 0.45), artW)
        U.fill(self, x, ly, artW, ah, bgC)
        U.border(self, x, ly, artW, ah, r.official and U.C.bad or edgeC)
        local isz = math.floor(math.min(ah, artW) * 0.62)
        U.auctArt(self, r.art, x + math.floor((artW - isz) / 2), ly + math.floor((ah - isz) / 2),
                  isz, r.done and U.C.mute or U.C.lite)

        local iy = ly + ah + 10
        local function pair(cap, val, col)
            U.text(self, cap, x, iy, U.C.dim, U.F.xs)
            iy = iy + U.h(U.F.xs) + 1
            U.text(self, val, x, iy, col or U.C.lite, U.F.s)
            iy = iy + U.h(U.F.s) + 8
        end
        pair(KR.L("ผู้ลงประมูล", "Seller"),
             r.official and KR.L("ระบบร้าน", "The shop") or tostring(r.seller or "-"),
             r.official and U.C.bad or U.C.text)
        pair(KR.L("บิดละ", "Bid step"), money(r.step or 0))
        if r.payIn then
            pair(KR.L("ต้องจ่ายภายใน", "Pay within"), KR.fmtDur(r.payIn), U.C.warn)
        elseif not r.done then
            pair(KR.L("ปิดใน", "Ends in"), KR.fmtDur(r.left or 0),
                 (r.left or 0) <= 300 and U.C.warn or U.C.lite)
        end
    end

    -- ---- คอลัมน์เนื้อหา -----------------------------------------------------
    local cy = ly
    U.text(self, KR.trunc(tostring(r.name or r.id), 40), midX, cy, U.C.text, U.F.l)
    cy = cy + U.h(U.F.l) + 4
    U.text(self, KR.L("จบประมูลแล้วนัดรับของกันเองในเกม  ระบบไม่ได้เก็บของไว้",
                      "You two meet up in game to hand it over. The system holds no items."),
           midX, cy, U.C.mute, U.F.xs)
    cy = cy + U.h(U.F.xs) + 14

    -- ราคาสองก้อนวางคู่กัน
    local half = math.floor((midW - U.GAP) / 2)
    U.text(self, KR.L("ราคาปัจจุบัน", "Current bid"), midX, cy, U.C.dim, U.F.xs)
    if r.buy and not r.done then
        U.text(self, KR.L("ซื้อทันที", "Buy now"), midX + half + U.GAP, cy, U.C.dim, U.F.xs)
    end
    cy = cy + U.h(U.F.xs) + 2
    U.text(self, money(r.bid), midX, cy, U.C.cash, U.F.l)
    if r.buy and not r.done then
        U.text(self, money(r.buy), midX + half + U.GAP, cy, U.C.gold, U.F.l)
    end
    cy = cy + U.h(U.F.l) + 2

    local note, nc
    if r.iAmTop then      note, nc = KR.L("คุณนำอยู่", "You are winning"), U.C.good
    elseif r.iBid then    note, nc = KR.L("คุณโดนแซงแล้ว", "You were outbid"), U.C.bad
    elseif (r.bids or 0) == 0 then note, nc = KR.L("ยังไม่มีใครบิด", "No bids yet"), U.C.mute
    else note, nc = KR.L("ผู้นำ ", "Leader ") .. tostring(r.top or "-"), U.C.mute end
    U.text(self, note, midX, cy, nc, U.F.xs)
    cy = cy + U.h(U.F.xs) + 14

    -- ---- ปุ่มลงมือ ----------------------------------------------------------
    local abh  = math.max(34, U.h(U.F.s) + 16)
    local cash = (d.bal or {}).cash or 0

    if r.done then
        if r.iAmTop and r.payIn and not r.settled then
            local pb = U.btn(self, midX, cy, midW, abh,
                             KR.L("จ่ายส่วนที่เหลือ ", "Pay the rest ") .. money(r.rest or 0),
                             cash >= (r.rest or 0) and "ok" or "offb", self.mx, self.my)
            if cash >= (r.rest or 0) then
                pb.act, pb.lot = "auctpay", r.id
                self.auctBtns[#self.auctBtns + 1] = pb
            end
        else
            local why = KR.L("ล็อตนี้จบแล้ว", "This lot has ended")
            if r.settled then why = KR.L("จ่ายครบแล้ว ไปนัดรับของได้เลย",
                                         "Paid in full. Go and collect it.") end
            if r.refunded then why = KR.L("หมดเวลาจ่าย เงินถูกคืนให้ผู้ชนะแล้ว",
                                          "Payment window expired. The winner was refunded.") end
            U.fill(self, midX, cy, midW, abh, U.C.bgCard)
            U.textC(self, why, midX + midW / 2, cy + math.floor((abh - U.h(U.F.s)) / 2),
                    U.C.mute, U.F.s)
        end
        cy = cy + abh + 10

    elseif r.mine then
        if (r.bids or 0) > 0 then
            U.fill(self, midX, cy, midW, abh, U.C.bgCard)
            U.textC(self, KR.L("มีคนบิดแล้ว ถอนล็อตไม่ได้", "Someone has bid. You cannot pull it."),
                    midX + midW / 2, cy + math.floor((abh - U.h(U.F.s)) / 2), U.C.mute, U.F.s)
        else
            local xb = U.btn(self, midX, cy, midW, abh,
                             KR.L("ถอนล็อตนี้", "Pull this lot"), "bad", self.mx, self.my)
            xb.act, xb.lot = "cancel", r.id
            self.auctBtns[#self.auctBtns + 1] = xb
        end
        cy = cy + abh + 10

    else
        local need = r.next or 0
        local bw3  = r.buy and math.floor((midW - U.GAP) / 2) or midW
        local ok1  = cash >= need and not r.iAmTop

        local b1 = U.btn(self, midX, cy, bw3, abh,
                         r.iAmTop and KR.L("คุณนำอยู่", "You are winning")
                                   or (KR.L("บิด ", "Bid ") .. money(need)),
                         ok1 and "pri" or "offb", self.mx, self.my)
        if ok1 then
            b1.act, b1.lot, b1.need = "bid", r.id, need
            self.auctBtns[#self.auctBtns + 1] = b1
        end

        if r.buy then
            local ok2 = cash >= r.buy
            local b2 = U.btn(self, midX + bw3 + U.GAP, cy, midW - bw3 - U.GAP, abh,
                             KR.L("ซื้อเลย ", "Buy now ") .. money(r.buy),
                             ok2 and "ok" or "offb", self.mx, self.my)
            if ok2 then
                b2.act, b2.lot, b2.need = "bid", r.id, r.buy
                self.auctBtns[#self.auctBtns + 1] = b2
            end
        end
        cy = cy + abh + 8

        -- ------------------------------------------------------------------
        -- ใส่ราคาเอง
        --
        -- ของเดิมบิดได้ทีละขั้นเท่านั้น  ล็อตที่ราคาวิ่งไปไกลแล้วต้องกดสิบกว่าครั้ง
        -- และทุกครั้งที่กดคือหนึ่งรอบไป-กลับกับเซิร์ฟ ซึ่งช้าพอที่คนอื่นจะแซงระหว่างนั้น
        -- ผลคือคนที่อยากทุ่มทีเดียวจบทำไม่ได้เลย ทั้งที่นั่นคือวิธีเล่นประมูลปกติ
        -- ------------------------------------------------------------------
        if self.fields and self.fields.auctBid then
            local fh2 = boxH()
            local f = self.fields.auctBid
            f:setX(midX + 1); f:setY(cy + 1)
            sizeBox(f, 130, fh2 - 2)
            U.fill(self, midX, cy, 132, fh2, U.C.bgDark)
            U.border(self, midX, cy, 132, fh2, U.C.line3)

            local ob = U.btn(self, midX + 140, cy, 150, fh2,
                             KR.L("บิดตามที่ใส่", "Bid that amount"), "neu", self.mx, self.my)
            ob.act, ob.lot = "bidown", r.id
            self.auctBtns[#self.auctBtns + 1] = ob

            U.text(self, KR.L("ต้องไม่ต่ำกว่า ", "at least ") .. money(need),
                   midX + 298, cy + math.floor((fh2 - U.h(U.F.xs)) / 2), U.C.dim, U.F.xs)
            cy = cy + fh2 + 12
        end
    end

    -- กติกาการจ่ายสองรอบ  เขียนไว้ตรงที่คนกำลังจะกดบิด ไม่ใช่ในคู่มือหน้า 12
    U.text(self, KR.L("ปิดล็อตแล้วผู้ชนะจ่าย 50% เข้าระบบก่อน  ผู้ขายได้เงินเต็มเมื่อจ่ายส่วนที่เหลือครบ",
                      "When it closes the winner pays 50% up front. The seller is paid in full"),
           midX, cy, U.C.dim, U.F.xs)
    cy = cy + U.h(U.F.xs) + 2
    U.text(self, KR.L("ไม่จ่ายภายใน 24 ชม.จริง ระบบคืนเงินให้ผู้ชนะเต็มจำนวน",
                      "once the balance is paid. No payment in 24 real hours means a full refund."),
           midX, cy, U.C.dim, U.F.xs)

    -- ---- ช่องบิดสด ----------------------------------------------------------
    if feedW > 0 then
        self:drawAuctFeed(x + w - feedW, ly, feedW, lh, r)
    end
end

-- ------------------------------------------------------------------------------
-- ช่องบิดสดของล็อตหนึ่ง
--
-- อ่านจาก r.log ที่เซิร์ฟส่งมา  ไม่มีการเก็บสถานะฝั่งจอเลย
-- ทุกคนที่เปิดดูล็อตเดียวกันจึงเห็นเหมือนกันเป๊ะ ต่างกันแค่รอบ poll (2 วิ)
--
-- แถวใหม่อยู่ "ล่างสุด" เหมือนหน้าต่างแชท ไม่ใช่บนสุดเหมือนฟีดข่าว
-- เพราะตาคนอ่านประมูลจะจับที่ราคาปัจจุบัน ซึ่งคือแถวล่างสุดพอดี
-- ------------------------------------------------------------------------------
local FEED_WORD = {
    open  = { KR.L("เปิดล็อต", "listed"),        function(c) return c.mute end },
    bid   = { nil,                                function(c) return c.text end },
    ext   = { KR.L("ต่อเวลา", "time extended"),  function(c) return c.warn end },
    won   = { KR.L("ชนะ", "won"),                 function(c) return c.good end },
    ["end"] = { KR.L("จบแบบไม่มีคนซื้อ", "ended with no bids"), function(c) return c.mute end },
    fail  = { KR.L("ตัดเงินไม่ผ่าน", "payment failed"), function(c) return c.bad  end },
    claim = { KR.L("รับของแล้ว", "collected"),   function(c) return c.good end },
    buynow= { KR.L("กดซื้อทันที", "bought now"),  function(c) return c.gold end },
    paid  = { KR.L("จ่ายครบแล้ว", "paid in full"), function(c) return c.good end },
}

function KRShop:drawAuctFeed(x, y, w, h, r)
    if not r then return end
    U.fill(self, x, y, w, h, U.C.bgCard)
    U.border(self, x, y, w, h, U.C.line2)

    local pad = 10
    local cy  = y + pad

    U.text(self, KR.L("ช่องบิดสด", "LIVE BIDS"), x + pad, cy, U.C.accent, U.F.xs)
    cy = cy + U.h(U.F.xs) + 4

    U.text(self, r.name or r.id, x + pad, cy, U.C.text, U.F.m)
    cy = cy + U.h(U.F.m) + 3

    local sub = KR.L("ขาย ", "Seller ") .. tostring(r.seller or "-")
    if r.buy then sub = sub .. KR.L("   ซื้อทันที ", "   buy now ") .. money(r.buy) end
    U.text(self, sub, x + pad, cy, U.C.dim, U.F.xs)
    cy = cy + U.h(U.F.xs) + 8

    -- ราคาปัจจุบันตัวใหญ่  นี่คือตัวเลขที่ทุกคนในห้องจ้องอยู่
    local bidS = money(r.bid)
    U.coin(self, KR.CUR.CASH, x + pad, cy + 2, 18)
    U.text(self, bidS, x + pad + 24, cy, U.C.cash, U.F.m)
    if not r.done then
        U.textR(self, KR.fmtDur(r.left or 0) .. KR.L(" เหลือ", " left"), x + w - pad, cy + 2,
                (r.left or 0) <= 300 and U.C.warn or U.C.mute, U.F.xs)
    else
        U.textR(self, r.sold and KR.L("ขายแล้ว", "SOLD") or KR.L("ไม่มีคนซื้อ", "UNSOLD"),
                x + w - pad, cy + 2, r.sold and U.C.good or U.C.mute, U.F.xs)
    end
    cy = cy + U.h(U.F.m) + 8
    U.hr(self, x + pad, cy, w - pad * 2, U.C.line2)
    cy = cy + 6

    local log = r.log or {}
    if #log == 0 then
        U.textC(self, KR.L("ยังไม่มีใครเสนอราคา", "No one has bid yet"),
                x + w / 2, cy + 10, U.C.mute, U.F.xs)
        return
    end

    -- วาดจากล่างขึ้นบน  แถวใหม่สุดชิดขอบล่างเสมอ ไม่ว่าจะมีกี่แถว
    local lh2 = U.h(U.F.xs) + U.h(U.F.s) + 7
    local bottom = y + h - pad
    local room   = bottom - cy
    local nvis   = math.max(1, math.floor(room / lh2))
    local first  = math.max(1, #log - nvis + 1)

    local ry = bottom - math.min(#log - first + 1, nvis) * lh2
    for i = first, #log do
        local e = log[i]
        local word = FEED_WORD[e.k or ""] or FEED_WORD.bid
        local col  = word[2](U.C)

        if e.k == "bid" then
            U.text(self, tostring(e.who or "?"), x + pad, ry, col, U.F.s)
            U.textR(self, money(e.a or 0), x + w - pad, ry, U.C.cash, U.F.s)
        else
            local txt = tostring(word[1] or e.k or "")
            if e.who then txt = tostring(e.who) .. " - " .. txt end
            U.text(self, txt, x + pad, ry, col, U.F.s)
        end

        -- เวลาสัมพัทธ์  "3m ago" อ่านง่ายกว่านาฬิกา เพราะสิ่งที่สนใจคือ "เพิ่งเกิดหรือนานแล้ว"
        local nowT = tonumber(data().now) or 0
        local ago  = math.max(0, nowT - (tonumber(e.t) or nowT))
        U.text(self, KR.fmtDur(ago) .. KR.L(" ที่แล้ว", " ago"),
               x + pad, ry + U.h(U.F.s) + 1, U.C.dim, U.F.xs)

        ry = ry + lh2
    end
end

-- ==============================================================================
-- เงินกู้
-- ==============================================================================
-- ------------------------------------------------------------------------------
-- ทำไมหน้านี้ถูกรื้อใหม่
--
-- เจ้าของเซิร์ฟรายงานว่า "หน้ากู้เงินไม่มีอะไรขึ้นเลย"  ต้นเหตุจริงอยู่ฝั่งเซิร์ฟ
-- (โหลดผิดลำดับจน d.credit เป็น nil แล้วหน้านี้ตกเข้า emptyState ทั้งจอ  แก้ไปแล้วอีกไฟล์)
-- แต่ต่อให้ข้อมูลมาครบ ของเดิมก็ยังอ่านไม่รู้เรื่องอยู่ดี
--   สองคอลัมน์ยาวเท่ากันทั้งที่ซ้ายเป็น "สถานะ" ขวาเป็น "ฟอร์ม" คนละน้ำหนักกัน
--   และฟอร์มขอกู้ยังโผล่เต็มครึ่งจอทั้งที่มีหนี้ค้างอยู่ ซึ่งกู้ไม่ได้อยู่แล้ว
--   = ครึ่งหนึ่งของจอเป็นของที่กดไม่ได้ตลอดเวลาที่ผู้เล่นเป็นหนี้ ซึ่งคือตอนที่เขาเข้าหน้านี้บ่อยที่สุด
--
-- โครงใหม่แยกตามสถานะเดียวที่สำคัญที่สุด คือ "มีสัญญาค้างอยู่หรือเปล่า"
--   ไม่มีหนี้ -> แถบสรุป + แผงขอกู้ (ซ้ายกรอก ขวาใบเสนอราคา)
--   มีหนี้    -> แถบสรุป + แผงผ่อน  ไม่มีฟอร์มขอกู้ให้เกะกะ
--
-- หน่วยเงินทั้งหน้าเป็น "สตางค์" ตามที่เซิร์ฟส่งมา  แสดงผ่าน money() ที่หารร้อยให้แล้ว
-- ห้ามหารเองซ้ำ  ขาออกต้องคูณ KR.SUBUNIT กลับขึ้นไปเสมอ
--
-- ฟิลด์ทุกตัวที่ใช้ในหน้านี้มาจาก S.creditRow ใน server/Kuraya/KR_Credit.lua ตัวจริง
--   cp tier limit nextTier nextCp nextLimit borrowed paid out avail
--   frozen missed terms rateBp lateBp minLoan
--   plan = { terms, paidN, each, late, dueIn, overdue }
-- plan ไม่ได้ส่ง dueAt มาด้วย  "กำหนดจ่าย" จึงแสดงจาก dueIn ได้อย่างเดียว
-- ห้ามเดาชื่อฟิลด์เพิ่มเอง  ฟิลด์ที่ไม่มีจริงจะขึ้นเป็น 0.00 เงียบ ๆ ซึ่งดูเหมือนข้อมูลจริง
-- ------------------------------------------------------------------------------
function KRShop:creditInit()
    if self.cr then return end
    self.cr = { amt = "", terms = KR.CREDIT.TERMS[2] or 10 }
end

-- แถบสรุปบนสุด  สี่ช่องที่ตอบ "ฉันกู้ได้อีกเท่าไร" ได้ในสายตาเดียว
-- อยู่บนสุดของทั้งสองสถานะ  เป็นสิ่งเดียวในหน้านี้ที่ไม่เปลี่ยนที่ทาง
function KRShop:crHeader(x, y, w, c)
    local padx = 16
    local topY = y + 12
    local valY = topY + U.h(U.F.xs) + 4
    local subY = valY + U.h(U.F.m) + 10
    local hh   = (subY + U.h(U.F.xs) + 12) - y

    U.fill(self, x, y, w, hh, U.C.bgHead)

    -- ยศ CP มาก่อนวงเงิน  เพราะยศเป็นเหตุ วงเงินเป็นผล
    local cells = {
        { KR.L("ชั้นเครดิต", "TIER"), tostring(c.tier or "-"), U.C.gold,
          "CP " .. tostring(math.floor(tonumber(c.cp) or 0)) },
        { KR.L("วงเงินของชั้นนี้", "CREDIT LIMIT"), money(c.limit), U.C.cash },
        { KR.L("ยอดค้าง", "OUTSTANDING"), money(c.out),
          (tonumber(c.out) or 0) > 0 and U.C.warn or U.C.mute },
        { KR.L("กู้เพิ่มได้อีก", "AVAILABLE"), money(c.avail), U.C.text },
    }
    local cw = math.floor((w - padx * 2) / #cells)
    for i = 1, #cells do
        local cd = cells[i]
        local cx = x + padx + (i - 1) * cw
        if i > 1 then U.vr(self, cx - 10, topY, hh - 24, U.C.line2) end
        U.text(self, cd[1], cx, topY, U.C.dim, U.F.xs)
        U.text(self, cd[2], cx, valY, cd[3], U.F.m)
        if cd[4] then
            U.text(self, cd[4], cx + U.w(cd[2], U.F.m) + 10,
                   valY + math.floor((U.h(U.F.m) - U.h(U.F.xs)) / 2), U.C.mute, U.F.xs)
        end
    end

    U.hr(self, x + padx, subY - 6, w - padx * 2, U.C.line2)

    -- บรรทัดล่าง  ซ้ายบอกทางไปข้างหน้า ขวาบอกความเสี่ยงที่ค้างอยู่
    local lead
    if c.nextTier then
        lead = KR.L("ชั้นถัดไป ", "Next tier ") .. tostring(c.nextTier) ..
               KR.L(" ที่ CP ", " at CP ") .. tostring(c.nextCp or 0) ..
               "  ->  " .. money(c.nextLimit)
    else
        lead = KR.L("ชั้นสูงสุดแล้ว", "Top tier reached")
    end

    local missed = math.floor(tonumber(c.missed) or 0)
    local tail, tcol, warn
    if c.frozen then
        tail, tcol, warn = KR.L("บัญชีถูกล็อกเพราะผิดนัดชำระ  ติดต่อแอดมิน",
                                "FROZEN for missed payments - talk to an admin"), U.C.bad, true
    elseif missed > 0 then
        -- อ่านผ่าน creditOpt ไม่ใช่ค่าคงที่ตรง ๆ  แอดมินตั้ง sandbox ให้ต่างจากค่าเริ่มต้นได้
        -- ตัวเลขที่จอบอกต้องเป็นตัวเลขที่เซิร์ฟใช้จริง ไม่งั้นเตือนผิดแล้วโดนล็อกก่อนที่บอกไว้
        tail, tcol, warn = KR.L("ผิดนัดแล้ว ", "Missed ") .. tostring(missed) .. " / " ..
                           tostring(KR.creditOpt("MISS_FREEZE")) ..
                           KR.L(" งวด แล้วบัญชีจะถูกล็อก", " before your account is frozen"),
                           U.C.warn, true
    else
        tail, tcol, warn = KR.L("ดอกเบี้ยคิดครั้งเดียวตอนกู้ ", "Interest is flat, charged once: ") ..
                           pct(c.rateBp), U.C.dim, false
    end

    -- สองก้อนนี้อยู่บรรทัดเดียวกัน  จอแคบแล้วมันจะทับกันจนอ่านไม่ออกทั้งคู่
    -- เลือกทิ้งทีละก้อนดีกว่า: คำเตือนสำคัญกว่าเสมอ  ส่วนคำอธิบายดอกเบี้ยยอมหายได้
    local fits = (U.w(lead, U.F.xs) + U.w(tail, U.F.xs) + 24) <= (w - padx * 2)
    if fits or not warn then
        U.text(self, lead, x + padx, subY, c.nextTier and U.C.mute or U.C.gold, U.F.xs)
    end
    if fits or warn then
        U.textR(self, tail, x + w - padx, subY, tcol, U.F.xs)
    end

    return hh
end

-- แผงขอกู้  วาดเฉพาะตอนไม่มีสัญญาค้าง
-- ซ้าย = สิ่งที่ผู้เล่นกรอก   ขวา = ผลที่จะเกิดขึ้นจากสิ่งที่กรอก + ปุ่มยืนยัน
-- แยกสองฝั่งแบบนี้เพราะปุ่มยืนยันควรอยู่ติดกับตัวเลขที่มันจะทำให้เป็นจริง ไม่ใช่ติดกับช่องกรอก
function KRShop:crBorrow(x, y, w, h, c)
    local gap = U.GAP
    local lw  = math.floor((w - gap) * 0.52)
    local rx  = x + lw + gap
    local rw  = w - lw - gap

    U.fill(self, x,  y, lw, h, U.C.bgHead)
    U.fill(self, rx, y, rw, h, U.C.bgCard)

    local ax, ay = x + 16, y + 14
    local iw     = lw - 32

    U.text(self, KR.L("ขอกู้", "TAKE A LOAN"), ax, ay, U.C.dim, U.F.xs)
    ay = ay + U.h(U.F.xs) + 10

    -- ช่องจำนวน  ยืมกล่องเดิมจากหน้าจัดการ ไม่สร้าง ISTextEntryBox ตัวใหม่
    -- prerender ซ่อนกล่องทุกตัวทุกเฟรมอยู่แล้ว  ที่นี่จึงเป็นที่เดียวที่สั่งให้มันโผล่
    -- แปลว่าพอมีหนี้ค้าง (ไม่ได้วาดแผงนี้) กล่องจะหายไปเองโดยไม่ต้องมีใครสั่งซ่อน
    U.text(self, KR.L("จำนวน (บาท)", "AMOUNT (baht)"), ax, ay, U.C.dim, U.F.xs)
    ay = ay + U.h(U.F.xs) + 5
    local bxh = boxH() + 6
    U.fill(self, ax, ay, iw, bxh, U.C.bgDark)
    U.border(self, ax, ay, iw, bxh, U.C.line3)
    local box = self.fields and self.fields.grantAmt
    if box then
        box:setVisible(true)
        box:setX(ax + 5); box:setY(ay + 3)
        sizeBox(box, iw - 10, bxh - 6)
    end
    ay = ay + bxh + gap

    -- ปุ่มลัดจำนวน  สี่ปุ่มพอดีความกว้างแผง  ปุ่มสุดท้ายรับเศษที่หารไม่ลงตัว
    local qh    = math.max(28, U.h(U.F.s) + 12)
    local quick = { 100000, 500000, 1000000 }
    local qgap  = 6
    local qw    = math.floor((iw - qgap * 3) / 4)
    for i = 1, #quick do
        local qb = U.btn(self, ax + (i - 1) * (qw + qgap), ay, qw, qh,
                         money(quick[i]), "neu", self.mx, self.my)
        qb.act, qb.val = "amt", quick[i]
        self.crBtns[#self.crBtns + 1] = qb
    end
    local mb = U.btn(self, ax + 3 * (qw + qgap), ay, iw - 3 * (qw + qgap), qh,
                     KR.L("เต็ม", "Max"), "neu", self.mx, self.my)
    mb.act, mb.val = "amt", c.avail
    self.crBtns[#self.crBtns + 1] = mb
    ay = ay + qh + gap + 4

    -- จำนวนงวด  ชุดที่เซิร์ฟเปิดให้เท่านั้น (c.terms)  ไม่ใช่ชุดที่ไคลเอนต์คิดเอง
    local terms = c.terms or KR.CREDIT.TERMS
    local okTerm = false
    for i = 1, #terms do if terms[i] == self.cr.terms then okTerm = true end end
    -- ค่าตั้งต้นอาจไม่อยู่ในชุดที่เซิร์ฟเปิด (แอดมินแก้ sandbox ได้)
    -- ไม่สแนปกลับ = ไม่มีปุ่มไหนสว่างสักปุ่ม แล้วผู้เล่นจะไม่รู้ว่าตัวเองกำลังจะกู้กี่งวด
    if not okTerm then self.cr.terms = terms[1] or 1 end

    U.text(self, KR.L("ผ่อนกี่งวด", "PAY BACK OVER"), ax, ay, U.C.dim, U.F.xs)
    ay = ay + U.h(U.F.xs) + 5
    local tgap = 6
    local tw3  = math.floor((iw - (#terms - 1) * tgap) / math.max(1, #terms))
    for i = 1, #terms do
        local on = (self.cr.terms == terms[i])
        local tb = U.btn(self, ax + (i - 1) * (tw3 + tgap), ay, tw3, qh,
                         tostring(terms[i]) .. KR.L(" งวด", "x"),
                         on and "pri" or "neu", self.mx, self.my)
        tb.act, tb.val = "terms", terms[i]
        self.crBtns[#self.crBtns + 1] = tb
    end
    ay = ay + qh + gap

    U.text(self, KR.L("เงินเข้าบัญชี Akacount ทันทีที่กด  จ่ายคืนวันละงวด",
                      "The money lands in your Akacount right away. One instalment per day."),
           ax, ay, U.C.dim, U.F.xs)

    -- ---------------- ขวา : ใบเสนอราคา ----------------
    -- คิดด้วย KR.creditQuote ตัวเดียวกับที่เซิร์ฟใช้ตอนอนุมัติจริง  ห้ามคิดสูตรเอง
    --
    -- การปัดเศษต้องเหมือนตอนส่งด้วย  ของเดิมตรงนี้ floor "บาท" ก่อนคูณร้อย
    -- แต่ปุ่มกู้ floor "สตางค์"  กรอก 500.50 จึงเห็นใบเสนอราคาของ 500.00
    -- แล้วได้เงินจริง 500.50  ต่างกันนิดเดียว แต่เป็นตัวเลขเงินที่ไม่ตรงกับที่โชว์ไว้
    local raw  = box and box:getInternalText() or ""
    local want = math.floor((tonumber(raw) or 0) * KR.SUBUNIT)
    if want < 0 then want = 0 end
    local q = KR.creditQuote(want, self.cr.terms)

    local qx, qy = rx + 14, y + 14
    local qiw    = rw - 28
    U.text(self, KR.L("ถ้ากดตอนนี้", "IF YOU BORROW NOW"), qx, qy, U.C.dim, U.F.xs)
    qy = qy + U.h(U.F.xs) + 12

    local function qkv(label, value, col, font)
        font = font or U.F.s
        U.text(self,  label, qx, qy + math.floor((U.h(font) - U.h(U.F.xs)) / 2), U.C.mute, U.F.xs)
        U.textR(self, value, qx + qiw, qy, col or U.C.text, font)
        qy = qy + U.h(font) + 8
    end
    qkv(KR.L("ได้รับตอนนี้", "You receive now"), money(q.amount), U.C.cash)
    qkv(KR.L("ดอกเบี้ย", "Interest") .. "  " ..
        pct(c.rateBp), money(q.interest))
    U.hr(self, qx, qy + 2, qiw, U.C.line2)
    qy = qy + 10
    qkv(KR.L("ต้องคืนรวม", "You pay back"), money(q.total), U.C.text, U.F.m)
    qkv(KR.L("งวดละ", "Per instalment"),
        money(q.each) .. "  x " .. tostring(q.terms), U.C.warn)
    -- งวดสุดท้ายรับเศษไปทั้งหมด (creditQuote ตั้งใจให้ผลรวมตรง total เป๊ะ)
    -- ไม่บอกไว้ตรงนี้ มันจะกลายเป็นเซอร์ไพรส์ตอนงวดท้ายซึ่งเป็นตอนที่เชื่อใจกันน้อยที่สุด
    if q.terms > 1 and q.last ~= q.each then
        qkv(KR.L("งวดสุดท้าย", "Final instalment"), money(q.last), U.C.mute)
    end

    -- ปุ่มกู้  เหตุผลที่กดไม่ได้ต้องอยู่บนปุ่ม ไม่ใช่เทาเฉย ๆ แล้วให้เดาเอง
    local bh2 = math.max(34, U.h(U.F.s) + 18)
    local by2 = y + h - 14 - bh2
    local why
    if c.frozen then
        why = KR.L("บัญชีถูกล็อก", "Account frozen")
    elseif (tonumber(c.avail) or 0) <= 0 then
        why = KR.L("วงเงินเต็มแล้ว", "No credit left")
    elseif want < (tonumber(c.minLoan) or 0) then
        why = KR.L("ขั้นต่ำ ", "Min ") .. money(c.minLoan)
    elseif want > (tonumber(c.avail) or 0) then
        why = KR.L("เกินวงเงิน", "Over your limit")
    end

    local bb = U.btn(self, qx, by2, qiw, bh2,
                     why or (KR.L("กู้ ", "Borrow ") .. money(want)),
                     why and "offb" or "pri", self.mx, self.my)
    if not why then
        bb.act = "borrow"
        self.crBtns[#self.crBtns + 1] = bb
    end
end

-- แผงผ่อน  วาดเฉพาะตอนมีสัญญาค้าง
-- คำถามเดียวที่คนเป็นหนี้เปิดหน้านี้มาถามคือ "ต้องจ่ายเท่าไร เมื่อไร"
-- ทุกอย่างในแผงนี้เรียงตามลำดับนั้น  ประวัติสะสมไปอยู่ท้ายสุด
function KRShop:crLoan(x, y, w, h, c)
    local p    = c.plan or {}
    local n    = math.max(1, math.floor(tonumber(p.terms) or 1))
    local done = math.max(0, math.floor(tonumber(p.paidN) or 0))
    local each = math.max(0, math.floor(tonumber(p.each) or 0))
    local late = math.max(0, math.floor(tonumber(p.late) or 0))
    local dueNow = each + late

    U.fill(self, x, y, w, h, U.C.bgHead)
    local ax = x + 16
    local iw = w - 32
    local ay = y + 14

    U.text(self, KR.L("สัญญาที่ค้างอยู่", "YOUR OPEN LOAN"), ax, ay, U.C.dim, U.F.xs)
    if p.overdue then
        U.textR(self, KR.L("เลยกำหนดชำระแล้ว", "OVERDUE"), ax + iw, ay, U.C.bad, U.F.xs)
    end
    ay = ay + U.h(U.F.xs) + 12

    -- หลอดความคืบหน้า  มีขีดแบ่งงวด จะได้เห็นว่าหนึ่งงวดคือเท่าไรของทั้งก้อน
    -- หลอดเปล่า ๆ บอกได้แค่ "ใกล้จบหรือยัง" ซึ่งตอบไม่ได้ว่าเหลืออีกกี่ครั้ง
    local barH = 8
    U.fill(self, ax, ay, iw, barH, U.C.bgDark)
    U.fill(self, ax, ay, math.floor(iw * math.min(1, done / n)), barH,
           p.overdue and U.C.warn or U.C.good)
    for i = 1, n - 1 do
        U.vr(self, ax + math.floor(iw * i / n), ay, barH, U.C.bg)
    end
    ay = ay + barH + 8
    U.text(self, tostring(done) .. " / " .. tostring(n) .. KR.L(" งวด", " instalments") ..
                 KR.L("   เหลืออีก ", "   ") .. tostring(math.max(0, n - done)) ..
                 KR.L(" งวด", " to go"),
           ax, ay, U.C.lite, U.F.s)
    ay = ay + U.h(U.F.s) + 14

    local function kv(label, value, col, font)
        font = font or U.F.s
        U.text(self,  label, ax, ay + math.floor((U.h(font) - U.h(U.F.s)) / 2), U.C.mute, U.F.s)
        U.textR(self, value, ax + iw, ay, col or U.C.text, font)
        ay = ay + U.h(font) + 8
    end
    kv(KR.L("งวดละ", "Per instalment"), money(each))
    kv(KR.L("กำหนดจ่ายงวดถัดไป", "Next payment due"),
       p.overdue and KR.L("เลยกำหนดแล้ว", "overdue now")
                 or (KR.L("อีก ", "in ") .. KR.fmtDur(p.dueIn or 0)),
       p.overdue and U.C.bad or U.C.warn)
    if late > 0 then
        kv(KR.L("ค่าปรับจ่ายช้า", "Late fee"), money(late), U.C.bad)
    end
    kv(KR.L("ยอดค้างทั้งหมด", "Outstanding"), money(c.out), U.C.warn)
    U.hr(self, ax, ay + 2, iw, U.C.line2)
    ay = ay + 10
    kv(KR.L("ต้องจ่ายตอนนี้", "Pay now"), money(dueNow), U.C.cash, U.F.m)

    -- ประวัติสะสม  ตัวเล็กท้ายสุด  ไม่ใช่ข้อมูลที่ต้องใช้ตัดสินใจอะไรตอนนี้
    ay = ay + 4
    U.text(self, KR.L("รวมกู้ไปแล้ว ", "Borrowed to date ") .. money(c.borrowed) ..
                 KR.L("   คืนไปแล้ว ", "   repaid ") .. money(c.paid),
           ax, ay, U.C.dim, U.F.xs)

    -- ---------------- ล่าง : คำเตือน + ปุ่มจ่าย ----------------
    local bh2 = math.max(34, U.h(U.F.s) + 18)
    local by2 = y + h - 14 - bh2
    local bw2 = math.min(math.max(200, math.floor(w * 0.32)), iw)

    -- เงินที่ใช้จ่ายงวดคือยอดในบัญชี Akacount ตัวเดียวกับ bal.cash ที่หัวหน้าต่าง
    -- (S.creditRepay เรียก B.charge  ส่วน S.balances เอา B.available มาใส่ bal.cash)
    -- เทียบฝั่งจอได้ตรง ๆ จึงบอกได้ก่อนกดว่าจ่ายไม่ไหว แทนที่จะให้กดแล้วโดนปฏิเสธ
    local haveCash = math.floor(tonumber((data().bal or {}).cash) or 0)
    local short    = haveCash < dueNow

    local rb = U.btn(self, ax + iw - bw2, by2, bw2, bh2,
                     short and (KR.L("เงินไม่พอ ต้องมี ", "Need ") .. money(dueNow))
                           or  (KR.L("จ่ายงวดนี้ ", "Pay instalment ") .. money(dueNow)),
                     short and "offb" or "ok", self.mx, self.my)
    if not short then
        rb.act = "repay"
        self.crBtns[#self.crBtns + 1] = rb
    end

    local warnY = by2 + math.floor((bh2 - U.h(U.F.xs)) / 2)
    if c.frozen then
        U.text(self, KR.L("บัญชีถูกล็อกเพราะผิดนัดชำระ  ติดต่อแอดมิน",
                          "Account frozen for missed payments. Talk to an admin."),
               ax, warnY, U.C.bad, U.F.xs)
    elseif p.overdue then
        U.text(self, KR.L("เลยกำหนดแล้ว  ค่าปรับเดินทุกวันจนกว่าจะจ่าย",
                          "Overdue. The late fee grows every day until you pay."),
               ax, warnY, U.C.bad, U.F.xs)
    else
        local miss = tostring(KR.creditOpt("MISS_FREEZE"))
        U.text(self, KR.L("ผิดนัด " .. miss .. " งวดแล้วบัญชีจะถูกล็อกทั้งหมด",
                          "Miss " .. miss .. " instalments and your whole account is frozen."),
               ax, warnY, U.C.warn, U.F.xs)
    end
end

function KRShop:drawCredit(x, y, w, h)
    self:creditInit()
    local d = data()
    local c = d.credit
    self.crBtns = {}

    -- emptyState เหลือไว้เฉพาะกรณีที่ "ธนาคารใช้งานไม่ได้จริง ๆ" เท่านั้น
    -- สภาพ "ไม่มีหนี้" ไม่ใช่หน้าว่าง  มันคือหน้าที่ควรชวนให้กู้ ซึ่งมีของให้แสดงเต็มไปหมด

    -- ยังไม่เคยได้ sync สักครั้ง  (เพิ่งเปิดหน้าต่าง หรือเซิร์ฟยังไม่ตอบ)
    -- ห้ามโทษธนาคารในจังหวะนี้  ตอนนี้เรายังไม่รู้อะไรเลยแม้แต่ว่าธนาคารมีอยู่ไหม
    -- d.now มากับทุก sync เสมอ  ไม่มีมัน = ยังไม่เคยคุยกับเซิร์ฟ
    if d.now == nil then
        U.emptyState(self, x, y, w, h,
                     KR.L("กำลังต่อกับเซิร์ฟ", "Talking to the server"),
                     KR.L("ถ้าค้างอยู่ตรงนี้นานให้ปิดแล้วเปิดร้านใหม่",
                          "If this stays up, close the shop and open it again"))
        return
    end
    if not d.bankOk then
        U.emptyState(self, x, y, w, h,
                     KR.L("ธนาคารไม่ตอบ", "The bank is offline"),
                     KR.L("ต้องมีม็อด Akacount ทำงานอยู่บนเซิร์ฟ  บอกแอดมินได้เลย",
                          "Akacount has to be running on this server. Tell an admin."))
        return
    end
    if not c then
        U.emptyState(self, x, y, w, h,
                     KR.L("ยังไม่มีข้อมูลเครดิต", "No credit record yet"),
                     KR.L("ต้องเปิดบัญชี Akacount ก่อน แล้วเปิดหน้านี้ใหม่",
                          "Open an Akacount first, then come back to this page"))
        return
    end

    local hh = self:crHeader(x, y, w, c)
    local by = y + hh + U.GAP
    local bh = h - hh - U.GAP

    if c.plan then
        self:crLoan(x, by, w, bh, c)
    else
        self:crBorrow(x, by, w, bh, c)
    end
end

-- ==============================================================================
-- คู่มือในเกม  (ปุ่ม ? บนแถบชื่อ)
--
-- ทำไมเป็น overlay ในหน้าต่างเดิม ไม่ใช่หน้าต่างที่สอง
--   บทเรียนจากแผง Account ที่ถูกลบทิ้งไปเมื่อ 0.2.8:
--   หน้าต่างที่สองที่วาดไม่ออกจะ "ยังกินคลิกอยู่" และทำให้ดูเหมือนหน้าต่างแรกพัง
--   overlay ตายพร้อมหน้าต่างแม่เสมอ ไม่มีทางค้างเป็นผี
--
-- โปร่งแสงแบบเมนูของเกมหลัก: ฉากหลังยังเห็นราง ๆ ผู้เล่นจึงไม่หลุดบริบทว่าตัวเองอยู่หน้าไหน
--
-- รูปประกอบโหลดจาก media/textures/Kuraya/help/<img>.png
-- ไฟล์ไหนยังไม่มี วาดกรอบว่างพร้อมชื่อไฟล์ที่รออยู่  เอารูปมาใส่ทีหลังได้โดยไม่ต้องแตะโค้ด
-- ==============================================================================
local helpTexCache = {}
local function helpTex(name)
    if not name then return nil end
    if helpTexCache[name] ~= nil then return helpTexCache[name] or nil end

    local ok, t = pcall(getTexture, KR.HELP_DIR .. name .. ".png")
    if not ok then t = nil end

    -- ------------------------------------------------------------------------
    -- "ได้ texture object กลับมา" ไม่เท่ากับ "โหลดรูปสำเร็จ"
    --
    -- PZ ถอดรหัส PNG บนสี่ช่องสัญญาณ  ไฟล์ 24-bit RGB (ไม่มีอัลฟา) คืน object
    -- กลับมาจริง getTexture จึงไม่เป็น nil แต่ตอนวาดออกมาเป็นสี่เหลี่ยมใส ๆ
    --
    -- ของเดิมเชื่อแค่ว่า t ไม่ใช่ nil  ทางที่รองรับ "ไม่มีรูป" (วาดกรอบพร้อมชื่อไฟล์)
    -- จึงไม่เคยถูกเดินเลย ผู้ใช้ได้กรอบเปล่าที่ไม่มีข้อความอะไรบอกสักตัว
    -- = อาการที่แย่กว่าไฟล์หายจริง ๆ เสียอีก
    --
    -- ถามความกว้างเพิ่มอีกชั้น  รูปที่ถอดรหัสไม่สำเร็จได้ศูนย์
    -- (เช็กว่ามีเมธอดก่อนเรียกตามกฎ  ไม่ใช่ทุกบิลด์ที่มี getWidth)
    if t and U_hasMethod2(t, "getWidth") then
        local okW, wpx = pcall(function() return t:getWidth() end)
        if not okW or not wpx or wpx <= 0 then t = nil end
    end

    helpTexCache[name] = t or false
    return t
end

-- ตัดข้อความยาวเป็นหลายบรรทัดตามความกว้างจริง
-- PZ ไม่มี word wrap ให้  drawText วาดทะลุขอบไปเฉย ๆ โดยไม่บอกอะไร
local function wrap(text, maxW, font)
    local lines, line = {}, ""
    for word in tostring(text):gmatch("%S+") do
        local try = (line == "") and word or (line .. " " .. word)
        if U.w(try, font) > maxW and line ~= "" then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

function KRShop:openHelp()
    -- เปิดมาที่หมวดที่ตรงกับหน้าที่ผู้เล่นยืนอยู่  ไม่ใช่หน้าแรกเสมอ
    -- คนกด ? ตอนงงอยู่หน้าประมูล ไม่ได้อยากอ่านเรื่องปุ่มลอย
    local want = ({ store = "buying", market = "buying", sale = "buying",
                    account = "account", auction = "auction", credit = "credit",
                    admin = "admin" })[self.page] or "start"
    local ci = 1
    for i = 1, #KR.HELP do if KR.HELP[i].id == want then ci = i end end
    self.help = { cat = ci, page = 1 }
end

function KRShop:drawHelp(w, h)
    local hp = self.help
    if not hp then return end

    U.fill(self, 0, 0, w, h, U.C.bgDark, 0.55)

    local pw = math.min(w - 40, 940)
    local ph = math.min(h - 40, 620)
    local px = math.floor((w - pw) / 2)
    local py = math.floor((h - ph) / 2)

    U.solid(self, px, py, pw, ph, U.C.bg)
    U.border(self, px, py, pw, ph, U.C.line3)

    local cat, pageN = KR.helpCat(hp.cat), 0
    local page
    page, pageN = KR.helpPage(hp.cat, hp.page)

    -- หัว
    local hb = math.max(30, U.h(U.F.s) + 14)
    U.fill(self, px, py, pw, hb, U.C.bgDark, 0.9)
    local ly = py + math.floor((hb - U.h(U.F.s)) / 2)
    local lg = U.logo(self, px + 6, py + 4, hb - 8, KR.MOOD.WOW)
    U.text(self, KR.L("วิธีใช้ Kuraya", "HOW TO USE KURAYA"),
           px + (lg > 0 and (lg + 12) or 12), ly, U.C.text, U.F.s)

    self.bHelpX = U.btn(self, px + pw - hb, py, hb, hb, "X", "neu", self.mx, self.my)
    U.textR(self, cat.label .. "   " .. hp.page .. " / " .. pageN,
            px + pw - hb - 12, ly, U.C.dim, U.F.xs)

    -- หมวด
    local cw = math.min(220, math.floor(pw * 0.24))
    U.fill(self, px, py + hb, cw, ph - hb, U.C.bgDark, 0.5)
    U.vr(self, px + cw, py + hb, ph - hb, U.C.line2)

    self.helpCats = {}
    local rowH = math.max(30, U.h(U.F.s) + 14)
    local cy = py + hb + 8
    for i = 1, #KR.HELP do
        local c   = KR.HELP[i]
        local on  = (i == hp.cat)
        local hot = U.hit({ x = px, y = cy, w = cw, h = rowH }, self.mx, self.my)
        if on then
            U.fill(self, px, cy, cw, rowH, U.C.accent2)
            U.fill(self, px, cy, 2, rowH, U.C.accent)
        elseif hot then
            U.fill(self, px, cy, cw, rowH, U.C.bgRow, 0.6)
        end
        U.text(self, c.label, px + 14, cy + math.floor((rowH - U.h(U.F.s)) / 2),
               on and U.C.text or U.C.mute, U.F.s)
        U.textR(self, tostring(#c.pages), px + cw - 12,
                cy + math.floor((rowH - U.h(U.F.xs)) / 2), U.C.dim, U.F.xs)
        self.helpCats[#self.helpCats + 1] = { x = px, y = cy, w = cw, h = rowH, cat = i }
        cy = cy + rowH
    end

    -- เนื้อหา
    local ix = px + cw + 16
    local iw = pw - cw - 32
    local iy = py + hb + 14

    -- รูป  อัตราส่วน 16:9 ตามที่กำหนดไว้ในสเปค
    local ih = math.floor(iw * 9 / 16)
    local btnH = math.max(30, U.h(U.F.s) + 14)
    local footH = btnH + 14
    local textH = U.h(U.F.m) + 8 + U.h(U.F.s) * 4
    local maxIh = ph - hb - 28 - textH - footH
    if ih > maxIh then ih = math.max(80, maxIh) end

    local t = helpTex(page and page.img)
    if t then
        self:drawTextureScaled(t, ix, iy, iw, ih, 1, 1, 1, 1)
    else
        U.fill(self, ix, iy, iw, ih, U.C.bgDark)
        U.textC(self, KR.L("ยังไม่มีรูปประกอบของหน้านี้", "No picture for this page yet"),
                ix + iw / 2, iy + ih / 2 - U.h(U.F.s), U.C.mute, U.F.s)
        U.textC(self, KR.HELP_DIR .. tostring(page and page.img or "?") .. ".png   1280 x 720",
                ix + iw / 2, iy + ih / 2 + 4, U.C.dim, U.F.xs)
    end
    U.border(self, ix, iy, iw, ih, U.C.line3)

    local ty = iy + ih + 12
    U.text(self, page and page.title or "", ix, ty, U.C.text, U.F.m)
    ty = ty + U.h(U.F.m) + 6

    local bottom = py + ph - footH - 4
    for _, ln in ipairs(wrap(page and page.body or "", iw, U.F.s)) do
        if ty + U.h(U.F.s) > bottom then break end
        U.text(self, ln, ix, ty, U.C.lite, U.F.s)
        ty = ty + U.h(U.F.s) + 3
    end

    -- ปุ่มเลื่อนหน้า  ข้ามหมวดได้ด้วย ไม่ใช่ตันอยู่ท้ายหมวด
    local by = py + ph - btnH - 12
    local bw = math.max(110, U.w(KR.L("ย้อนกลับ", "Back"), U.F.s) + 44)

    local hasPrev = not (hp.cat == 1 and hp.page == 1)
    local hasNext = not (hp.cat == #KR.HELP and hp.page == pageN)
    self.bHelpPrev = U.btn(self, ix, by, bw, btnH,
                           "< " .. KR.L("ย้อนกลับ", "Back"),
                           hasPrev and "neu" or "offb", self.mx, self.my)
    self.bHelpNext = U.btn(self, ix + iw - bw, by, bw, btnH,
                           KR.L("ถัดไป", "Next") .. " >",
                           hasNext and "pri" or "offb", self.mx, self.my)
    if not hasPrev then self.bHelpPrev = nil end
    if not hasNext then self.bHelpNext = nil end

    -- จุดบอกหน้าในหมวดนี้
    local dw, dg = 7, 5
    local tot = pageN * dw + (pageN - 1) * dg
    local dx  = ix + math.floor((iw - tot) / 2)
    local dy  = by + math.floor((btnH - dw) / 2)
    self.helpDots = {}
    for i = 1, pageN do
        U.fill(self, dx, dy, dw, dw, (i == hp.page) and U.C.accent or U.C.line3)
        self.helpDots[#self.helpDots + 1] = { x = dx - 3, y = by, w = dw + 6, h = btnH, page = i }
        dx = dx + dw + dg
    end
end

function KRShop:helpStep(dir)
    local hp = self.help
    if not hp then return end
    local _, n = KR.helpPage(hp.cat, hp.page)
    hp.page = hp.page + dir
    if hp.page > n then
        if hp.cat < #KR.HELP then hp.cat, hp.page = hp.cat + 1, 1 else hp.page = n end
    elseif hp.page < 1 then
        if hp.cat > 1 then
            hp.cat = hp.cat - 1
            local _, pn = KR.helpPage(hp.cat, 1)
            hp.page = pn
        else
            hp.page = 1
        end
    end
end

function KRShop:helpClick(x, y)
    if U.hit(self.bHelpX, x, y) then self.help = nil; return true end
    if self.bHelpNext and U.hit(self.bHelpNext, x, y) then self:helpStep(1);  return true end
    if self.bHelpPrev and U.hit(self.bHelpPrev, x, y) then self:helpStep(-1); return true end
    for _, b in ipairs(self.helpDots or {}) do
        if U.hit(b, x, y) then self.help.page = b.page; return true end
    end
    for _, b in ipairs(self.helpCats or {}) do
        if U.hit(b, x, y) then self.help.cat, self.help.page = b.cat, 1; return true end
    end
    return true
end

-- ==============================================================================
-- หน้า Account
--
-- ย้ายมาจากไฟล์ KR_UI_Account.lua ซึ่งถูกลบทิ้งแล้ว (ดูเหตุผลตรง PAGES ด้านบน)
-- ตอนเป็นแผงแยกมันกว้างแค่ 300px เลยต้องเรียงทุกอย่างลงมาเป็นแถวเดียว
-- อยู่ในหน้าต่างร้านแล้วมีที่กว้างเป็นพันพิกเซล  จึงจัดเป็นสองคอลัมน์ได้
--
--   ซ้าย  บัตร -> ยอดสามสกุล -> บัตรสะสมแต้ม      (ของที่ "เป็นตัวเรา")
--   ขวา   เดินบัญชีล่าสุด -> ปุ่มโอน -> ปุ่มม็อดอื่น (ของที่ "ทำอะไรได้")
--
-- ความกว้างคอลัมน์ซ้ายผูกกับความกว้างบัตร ไม่ใช่ตัวเลขคงที่
-- บัตรเครดิตจริงอัตราส่วน 1.586:1  ถ้าฝืนยืดจะดูปลอมทันที
-- ==============================================================================
local skinTexCache = {}
local function cardTex(name)
    if not name then return nil end
    if skinTexCache[name] ~= nil then return skinTexCache[name] or nil end
    local ok, t = pcall(getTexture, "media/textures/" .. name .. ".png")
    skinTexCache[name] = (ok and t) or false
    return (ok and t) or nil
end

local function skinDef(d)
    local want = d.skin
    for _, s in ipairs(d.skins or {}) do
        if s.id == want then return s end
    end
    return (d.skins or {})[1]
end

local KIND_EN = {
    dep = "Cash deposit",   wdr = "Cash withdrawal", xfr = "Sent to player",
    fee = "Fee",            int = "Savings interest", loan = "Loan received",
    repay = "Loan payment", bill = "Bill paid",      shop = "Shop purchase",
    esc = "Held in escrow", adm = "Admin adjustment",
}

-- ---- บัตร --------------------------------------------------------------------
function KRShop:accCard(x, y, w, d)
    local ch = math.floor(w / 1.586)
    local sk = skinDef(d)
    local t  = sk and cardTex(sk.texture or sk.icon)

    U.fill(self, x, y, w, ch, U.C.bgCard)
    if t then
        -- อาร์ตลายบัตรเป็นภาพจัตุรัส (128x128) แต่บัตรเป็นสี่เหลี่ยมผืนผ้า 1.586:1
        -- ยืดให้เต็มกรอบตรง ๆ = ลายบิดจนดูเป็นของปลอม
        -- วาดแบบ "ครอบเต็ม" แทน: ขยายตามด้านกว้าง แล้วตัดส่วนเกินบน-ล่างด้วย stencil
        local side = w
        self:setStencilRect(x, y, w, ch)
        self:drawTextureScaled(t, x, y - math.floor((side - ch) / 2), side, side, 1, 1, 1, 1)
        self:clearStencilRect()
    end
    U.border(self, x, y, w, ch, U.C.line3)

    -- ตัวหนังสือบนบัตร  วางบนแถบทึบบาง ๆ จะได้อ่านออกทุกลาย
    local band = U.h(U.F.s) + U.h(U.F.xs) + 16
    U.fill(self, x, y + ch - band, w, band, U.C.bgDark, 0.72)
    U.text(self, tostring(d.name or "PLAYER"):upper(), x + 12, y + ch - band + 6, U.C.text, U.F.s)
    U.text(self, sk and (sk.name or sk.id) or "NO CARD",
           x + 12, y + ch - band + 8 + U.h(U.F.s), U.C.mute, U.F.xs)

    U.text(self, "AKACOUNT", x + 12, y + 10, U.C.text, U.F.xs)
    if not d.card then
        U.textC(self, KR.L("ยังไม่มีบัตร  ขอที่ธนาคาร", "No card yet - ask at the bank"),
                x + w / 2, y + ch / 2 - 8, U.C.warn, U.F.xs)
    end
    return y + ch + U.GAP
end

-- ---- ยอดสามสกุล ---------------------------------------------------------------
function KRShop:accBalances(x, y, w, d)
    local rowH = math.max(26, U.h(U.F.m) + 10)
    local bh   = rowH * 3 + 16
    U.fill(self, x, y, w, bh, U.C.bgCard)
    U.border(self, x, y, w, bh, U.C.line2)

    local bal = d.bal or {}
    local ry  = y + 8
    for _, cur in ipairs({ KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP }) do
        local meta = KR.CUR_META[cur] or {}
        U.coin(self, cur, x + 12, ry + math.floor((rowH - 20) / 2), 20)
        U.text(self, meta.label or cur:upper(), x + 40,
               ry + math.floor((rowH - U.h(U.F.s)) / 2), U.C.mute, U.F.s)
        U.textR(self, fmtNum(cur, bal[cur]), x + w - 12,
                ry + math.floor((rowH - U.h(U.F.m)) / 2), U.curCol(cur), U.F.m)
        ry = ry + rowH
    end
    return y + bh + U.GAP
end

-- ---- ระดับการใช้จ่าย -----------------------------------------------------------
--
-- แทนที่บัตรสะสมแต้มบนจอ  ตัวบัตรสะสมยังนับอยู่ข้างหลัง ไม่ได้ถอดออก
-- สองอย่างนี้ตอบคนละคำถาม: บัตรนับ "กี่ครั้ง" · tier นับ "กี่บาท"
function KRShop:accTier(x, y, w, d)
    local st = d.tier
    if not st then return y end

    local barH = 14
    local bh   = U.h(U.F.m) + U.h(U.F.xs) * 2 + barH + 34
    U.fill(self, x, y, w, bh, U.C.bgCard)
    U.border(self, x, y, w, bh, U.C.line2)

    local cy = y + 10
    U.text(self, "TIER " .. tostring(st.tier), x + 12, cy, U.C.gold, U.F.m)
    U.textR(self, st.maxed and KR.L("สูงสุดแล้ว", "top tier")
                            or (money(st.need) .. KR.L(" ถึง Tier ", " to Tier ") .. (st.tier + 1)),
            x + w - 12, cy + 4, U.C.mute, U.F.xs)
    cy = cy + U.h(U.F.m) + 8

    -- แถบความคืบหน้าใน tier ปัจจุบัน
    U.fill(self, x + 12, cy, w - 24, barH, U.C.bgDark)
    U.border(self, x + 12, cy, w - 24, barH, U.C.line3)
    local fillW = math.floor((w - 26) * math.max(0, math.min(1, st.pct or 0)))
    if fillW > 0 then U.fill(self, x + 13, cy + 1, fillW, barH - 2, U.C.gold) end
    cy = cy + barH + 8

    -- ขีดบอกว่ามีทั้งหมดกี่ tier  เห็นปลายทางแล้วรู้ว่าเหลืออีกไกลแค่ไหน
    local pipW = math.floor((w - 24 - (st.max - 1) * 4) / st.max)
    for i = 1, st.max do
        local pxp = x + 12 + (i - 1) * (pipW + 4)
        U.fill(self, pxp, cy, pipW, 4, (i <= st.tier) and U.C.gold or U.C.line2)
    end
    cy = cy + 12

    U.text(self, KR.L("ใช้จ่ายสะสม ", "Spent ") .. money(st.spent) ..
                 KR.L("  ·  ครบ ", "  ·  every ") .. money(st.step) ..
                 KR.L(" ได้หนึ่งระดับ", " is one tier"),
           x + 12, cy, U.C.dim, U.F.xs)

    return y + bh + U.GAP
end

-- ---- คอลัมน์ ACTION ------------------------------------------------------------
--
-- เจ้าของเซิร์ฟสั่งไว้ตรง ๆ ว่าคอลัมน์นี้มีแค่สามอย่าง:
--   ชื่อผู้เล่น + โลโก้ใหญ่ ๆ / บิลค่าบ้าน / ยอดรวมใช้จ่าย 7 วันล่าสุด
-- ปุ่มม็อดอื่นที่ไม่ใช่การ์ดยังอยู่ แต่ไปต่อท้ายแบบเล็ก ๆ ไม่แย่งที่สามอย่างข้างบน
function KRShop:accWho(x, y, w, d)
    local lg   = 54
    local bh   = math.max(lg + 20, U.h(U.F.l) + U.h(U.F.xs) + 26)
    -- แผงชื่อไม่มีหัวเรื่อง  แต่ยังได้ขอบสองเส้นกับแถบสีประจำหน้าเหมือนแผงอื่น
    -- มันคือแผงบนสุดของคอลัมน์ สีตรงนี้จึงเป็นตัวประกาศว่าหน้านี้คือหน้าอะไร
    U.panel(self, x, y, w, bh, { bg = U.C.bgHead, accent = U.C.accent })

    local drew = U.logo(self, x + 12, y + math.floor((bh - lg) / 2), lg, KR.mood(d))
    local tx = x + 12 + (drew > 0 and (lg + 14) or 0)
    local ty = y + math.floor((bh - U.h(U.F.l) - U.h(U.F.xs) - 4) / 2)
    U.text(self, tostring(d.name or "PLAYER"), tx, ty, U.C.text, U.F.l)

    -- ---- บรรทัดรองใต้ชื่อ ---------------------------------------------------
    --
    -- 0.6.8 — เคยหยิบ c.head ของการ์ดใบแรกมาใช้  ซึ่งผิดชนิดของข้อมูล
    --
    -- c.head คือ "หัวเรื่องของการ์ดใบนั้น" ไม่ใช่ "คำอธิบายตัวผู้เล่น"
    -- พอการ์ดบิลตั้ง head = "House bills" หน้าจอจึงอ่านออกมาเป็น
    --     ninjaaa
    --     HOUSE BILLS
    -- เหมือนบอกว่าผู้เล่นคนนี้มีตำแหน่งว่า "บิลค่าบ้าน" ซึ่งไม่มีความหมายอะไรเลย
    -- (เจ้าของเซิร์ฟถ่ายรูปมาให้ดู)
    --
    -- ตั้งใจเดิมคืออยากได้ประโยคอย่าง "หัวบ้าน · Rosewood Lot 14" ซึ่งเป็นเรื่องของ
    -- ผู้เล่นจริง ๆ  ฟิลด์นั้นจึงต้องเป็นฟิลด์ของตัวเอง ไม่ใช่ยืมฟิลด์อื่นที่บังเอิญมีค่า
    -- ม็อดไหนอยากเติมบรรทัดนี้ให้ส่ง who มาใน state ของการ์ด  ไม่ส่ง = ใช้สถานะบัญชี
    local sub = nil
    for _, c in ipairs(d.cards or {}) do
        if c.who then sub = c.who; break end
    end
    U.text(self, tostring(sub or (d.card and KR.L("มีบัตร Akacount แล้ว", "AKACOUNT CARD HOLDER")
                                          or KR.L("ยังไม่มีบัตร", "NO CARD YET"))):upper(),
           tx, ty + U.h(U.F.l) + 4, U.C.mute, U.F.xs)

    return y + bh + U.GAP
end

-- สีของแถบสถานะบนหัวการ์ด
local CARD_TONE = {
    none = { bg = "line2",  fg = "mute" },
    paid = { bg = "good",   fg = "bgDark" },
    due  = { bg = "warn",   fg = "bgDark" },
    late = { bg = "bad",    fg = "bgDark" },
    sent = { bg = "accent", fg = "bgDark" },
}

function KRShop:accCards(x, y, w, d)
    local cards = d.cards or {}
    if #cards == 0 then return y end

    for _, c in ipairs(cards) do
        if c.dead then
            -- ม็อดเจ้าของการ์ดพัง  ต้องดูออกว่าพัง ไม่ใช่หายไปเฉย ๆ
            local bh = U.h(U.F.s) + 20
            U.fill(self, x, y, w, bh, U.C.bgCard)
            U.border(self, x, y, w, bh, U.C.bad)
            U.text(self, tostring(c.title) .. KR.L(" — ม็อดมีปัญหา", " - add-on error"),
                   x + 12, y + 10, U.C.bad, U.F.s)
            y = y + bh + U.GAP
        else
            local tone   = CARD_TONE[c.status] or CARD_TONE.none
            local stripH = U.h(U.F.xs) + 12
            local btnH   = math.max(32, U.h(U.F.s) + 16)
            local nAct   = #(c.actions or {})
            local bh = stripH + 14 + U.h(U.F.s) + 6 + U.h(U.F.l) + 6 + U.h(U.F.xs) + 12
                       + (nAct > 0 and (btnH + 10) or 0)

            U.fill(self, x, y, w, bh, U.C.bgCard)

            -- แถบสถานะ  สีเดียวที่ต้องกวาดตาแล้วรู้ทันทีว่าต้องทำอะไรไหม
            U.fill(self, x, y, w, stripH, U.C[tone.bg])
            U.text(self, tostring(c.statusText or c.status or ""):upper(),
                   x + 12, y + 6, U.C[tone.fg], U.F.xs)

            local cy = y + stripH + 12
            U.text(self, tostring(c.head or c.title), x + 14, cy, U.C.lite, U.F.s)
            cy = cy + U.h(U.F.s) + 6

            -- ตัวเลขใหญ่  นี่คือสิ่งที่คนเปิดหน้านี้มาดู
            --
            -- การ์ดที่จองที่ไว้เฉย ๆ ต้องขึ้นขีด ไม่ใช่ 0.00
            -- ศูนย์เป็นตัวเลขจริงที่แปลว่า "ไม่ต้องจ่ายอะไร" ซึ่งคนละความหมายกับ
            -- "ยังไม่มีระบบนี้"  เอามาปนกันคือการรายงานข้อมูลที่ไม่มีอยู่จริง
            if c.placeholder then
                U.text(self, "—", x + 14, cy, U.C.dim, U.F.l)
            else
                local amtCol = U.C.text
                if c.status == KR.CARD_STATUS.LATE then amtCol = U.C.bad
                elseif c.status == KR.CARD_STATUS.PAID or c.status == KR.CARD_STATUS.NONE then amtCol = U.C.good end
                U.coin(self, c.cur or KR.CUR.CASH, x + 14, cy + 4, 22)
                U.text(self, fmtNum(c.cur or KR.CUR.CASH, c.amount or 0), x + 44, cy, amtCol, U.F.l)
            end
            cy = cy + U.h(U.F.l) + 6

            if c.note then
                U.text(self, tostring(c.note), x + 14, cy, U.C.dim, U.F.xs)
            end
            cy = cy + U.h(U.F.xs) + 8

            local bw = math.floor((w - 28 - (nAct - 1) * 8) / math.max(1, nAct))
            for i, a in ipairs(c.actions or {}) do
                local bx = x + 14 + (i - 1) * (bw + 8)
                local ab = U.btn(self, bx, cy, bw, btnH, a.label,
                                 a.disabled and "offb" or (a.style or "pri"), self.mx, self.my)
                if not a.disabled then
                    ab.act, ab.card, ab.id = "card", c.id, a.id
                    self.accBtns[#self.accBtns + 1] = ab
                end
            end

            U.border(self, x, y, w, bh, U.C.line3)
            y = y + bh + U.GAP
        end
    end
    return y
end

function KRShop:accSpend7(x, y, w, d)
    local bh = U.capH(false) + U.h(U.F.m) + U.h(U.F.xs) + 16
    local cy = U.panel(self, x, y, w, bh, {
        cap = KR.L("ใช้จ่าย 7 วันล่าสุด", "SPENT IN THE LAST 7 DAYS"), pad = 5,
    })
    U.coin(self, KR.CUR.CASH, x + 14, cy + 3, 19)
    U.text(self, money(d.spent7 or 0), x + 40, cy, U.C.cash, U.F.m)
    cy = cy + U.h(U.F.m) + 5
    U.text(self, tostring(math.floor(tonumber(d.spent7n) or 0)) ..
                 KR.L(" รายการ", " entries"), x + 14, cy, U.C.mute, U.F.xs)

    return y + bh + U.GAP
end

-- ---- ตารางประวัติการใช้จ่าย ------------------------------------------------------
--
-- ย้ายลงมาเต็มความกว้างด้านล่างตามที่สั่ง และเลื่อนได้ด้วยล้อเมาส์
-- **ไม่มีรายการของธนาคารในนี้** ฝาก/ถอน/โอน อยู่ที่สมุดบัญชีของธนาคาร
-- tag = nil คือประวัติของตัวเอง (หน้า Account)  "adm" คือของคนที่แอดมินเปิดดูอยู่
-- สองที่นี้ไม่เคยอยู่บนจอพร้อมกัน แต่ **ค่าเลื่อนต้องแยกกัน**
-- ใช้ตัวเดียวกันแปลว่าเลื่อนดูของคนอื่นค้างไว้ แล้วกลับมาหน้าตัวเองเจอตารางลอยอยู่กลางเรื่อง
function KRShop:accHistory(x, y, w, h, d, tag)
    -- ใหม่สุดอยู่บนสุด  ไม่ใช่ล่างสุด
    --
    -- เซิร์ฟ append ต่อท้าย p.log  ตารางจึงเคยวาดเก่าสุดไว้บรรทัดแรก
    -- และ logScroll เริ่มที่ 0 = ค้างอยู่หัวตาราง
    -- ผลคือ **ซื้อของเสร็จแล้วแถวใหม่ไปโผล่นอกจอ** ต้องเลื่อนลงสุดถึงจะเห็น
    -- อาการที่ผู้เล่นเห็นคือ "ประวัติไม่อัปเดต" ทั้งที่ข้อมูลเข้ามาครบทุกแถว
    --
    -- สมุดบัญชีทุกเล่มในโลกจริงเรียงใหม่ก่อน  ที่นี่ก็ควรเป็นอย่างนั้น
    -- กลับด้านตอนวาด ไม่ใช่ตอนเก็บ  ฝั่งเซิร์ฟ append ต่อท้ายคือวิธีที่ถูกอยู่แล้ว
    -- (ตัดแถวเก่าทิ้งด้วย table.remove(1) เมื่อเต็ม ซึ่งจะกลับหัวถ้าเก็บสลับด้าน)
    local rows = {}
    local src  = d.log or {}
    for i = #src, 1, -1 do
        local r = src[i]
        if KR.logPass(r, self.logFilter) then rows[#rows + 1] = r end
    end

    -- หัวตาราง + ชิปกรอง
    local chH = math.max(24, U.h(U.F.xs) + 12)
    self.logBtns = {}
    U.text(self, KR.L("ประวัติการใช้จ่าย", "SPENDING HISTORY"), x, y + 6, U.C.dim, U.F.xs)

    local cx = x + U.w(KR.L("ประวัติการใช้จ่าย", "SPENDING HISTORY"), U.F.xs) + 16
    local chips = { { id = "all", label = KR.L("ทั้งหมด", "All") } }
    for _, f in ipairs(KR.LOG_FILTERS) do chips[#chips + 1] = f end
    for _, f in ipairs(chips) do
        local on  = ((self.logFilter or "all") == f.id)
        local cwv = U.w(f.label, U.F.xs) + 22
        local hot = U.hit({ x = cx, y = y, w = cwv, h = chH }, self.mx, self.my)
        U.fill(self, cx, y, cwv, chH, on and U.C.accent2 or (hot and U.C.bgRow or U.C.bgCard))
        U.textC(self, f.label, cx + cwv / 2, y + math.floor((chH - U.h(U.F.xs)) / 2),
                on and U.C.text or U.C.mute, U.F.xs)
        self.logBtns[#self.logBtns + 1] = { x = cx, y = y, w = cwv, h = chH, filter = f.id }
        cx = cx + cwv + 6
    end
    U.textR(self, KR.L("ฝาก/ถอนของธนาคารไม่อยู่ในนี้", "bank deposits and withdrawals are not listed here"),
            x + w, y + 6, U.C.dim, U.F.xs)

    y = y + chH + 6
    h = h - chH - 6
    if h < 50 then return end

    U.fill(self, x, y, w, h, U.C.bgHead)
    U.border(self, x, y, w, h, U.C.line)

    if #rows == 0 then
        U.textC(self, KR.L("ยังไม่มีรายการ", "Nothing here yet"),
                x + w / 2, y + math.floor(h / 2) - 8, U.C.mute, U.F.s)
        return
    end

    -- คอลัมน์  ความกว้างวัดจากข้อความจริง ไม่ใช่เดา
    local cDate = x + 14
    local wDate = math.max(U.w("Aug 07  21:14", U.F.s), U.w(KR.L("วันที่", "DATE"), U.F.xs)) + 22
    local cType = cDate + wDate
    local wType = 0
    for _, lbl in pairs(KR.LOG_LABEL) do wType = math.max(wType, U.w(lbl, U.F.xs) + 20) end
    wType = wType + 14
    local cAmt  = x + w - 14
    local wAmt  = 150          -- +20 ให้เหรียญสกุลเงิน (0.6.16)  ไม่ใช่เบียดตัวเลข
    local cStat = cAmt - wAmt
    local wStat = 120
    local cItem = cType + wType

    local hh = U.h(U.F.xs) + 12
    U.fill(self, x, y, w, hh, U.C.bgDark, 0.5)
    U.text(self,  KR.L("วันที่", "DATE"),   cDate, y + 5, U.C.dim, U.F.xs)
    U.text(self,  KR.L("ประเภท", "TYPE"),   cType, y + 5, U.C.dim, U.F.xs)
    U.text(self,  KR.L("รายการ", "ITEM"),   cItem, y + 5, U.C.dim, U.F.xs)
    U.text(self,  KR.L("สถานะ", "STATUS"),  cStat - wStat + 10, y + 5, U.C.dim, U.F.xs)
    U.textR(self, KR.L("จำนวน", "AMOUNT"),  cAmt, y + 5, U.C.dim, U.F.xs)
    U.hr(self, x, y + hh, w, U.C.line2)

    local top   = y + hh + 1
    local view  = h - hh - 1
    -- แถวสูงขึ้นจาก +14 เป็น +18 (0.6.8)
    -- ตัวหนังสือขนาดเดิมแต่มีอากาศรอบตัวมากขึ้น = กวาดตาลงคอลัมน์ได้โดยไม่ต้องเพ่ง
    local rowH  = math.max(32, U.h(U.F.s) + 18)
    local total = #rows * rowH

    -- เลื่อนได้  ค่าเลื่อนเก็บแยกจากลิสต์ของหน้าอื่น
    local sKey = tag and ("logScroll_" .. tag) or "logScroll"
    if self[sKey] == nil then self[sKey] = 0 end
    if self[sKey] > math.max(0, total - view) then self[sKey] = math.max(0, total - view) end

    self:setStencilRect(x, top, w, view)
    local cy2 = top - self[sKey]
    for i = 1, #rows do
        local r = rows[i]
        if cy2 + rowH > top and cy2 < top + view then
            -- แถบสลับชัดขึ้น (0.35 -> 0.7) และเลิกตีเส้นใต้ทุกแถว
            -- เส้นทุกแถว + แถบสลับ = ลายสองชั้นที่แข่งกันเอง ตาต้องเลือกว่าจะตามอันไหน
            -- เหลืออย่างเดียวคือแถบสลับ ซึ่งบอก "ขอบเขตของแถว" ได้เท่ากันแต่เงียบกว่า
            if i % 2 == 0 then U.fill(self, x, cy2, w, rowH, U.C.bgRow, 0.7) end
            -- แถวที่เมาส์ชี้อยู่  ประวัติยาว ๆ ต้องมีอะไรยึดสายตาไว้ตอนไล่หา
            if U.hit({ x = x, y = cy2, w = w, h = rowH }, self.mx, self.my) then
                U.fill(self, x, cy2, w, rowH, U.C.bgSel, 0.55)
            end
            local ty2 = cy2 + math.floor((rowH - U.h(U.F.s)) / 2)

            -- เวลาแบบ "เมื่อ 2 ชม.ที่แล้ว"  ไม่ใช่วันที่จริง
            -- PZ ไม่มี os.date ให้ใช้ และเวลาในเกมกับเวลาจริงคนละเรื่องกัน
            -- ผู้เล่นสนใจว่า "เพิ่งเกิด" หรือ "นานแล้ว" มากกว่าตัวเลขวันที่อยู่แล้ว
            local ago = math.max(0, (tonumber(d.now) or 0) - (tonumber(r.t) or 0))
            U.text(self, (ago < 60) and KR.L("เมื่อครู่", "just now")
                                     or (KR.fmtDur(ago) .. KR.L(" ที่แล้ว", " ago")),
                   cDate, ty2, U.C.mute, U.F.s)

            -- ป้ายประเภท  พื้นทึบเล็ก ๆ กวาดตาหาชนิดที่ต้องการได้เร็วกว่าตัวหนังสือเปล่า
            local lbl = KR.LOG_LABEL[r.k] or tostring(r.k)
            local lw2 = U.w(lbl, U.F.xs) + 16
            U.fill(self, cType, cy2 + math.floor((rowH - U.h(U.F.xs) - 6) / 2), lw2, U.h(U.F.xs) + 6, U.C.accent2)
            U.textC(self, lbl, cType + lw2 / 2, cy2 + math.floor((rowH - U.h(U.F.xs)) / 2), U.C.text, U.F.xs)

            -- ชื่อรายการ  ตัดตามความกว้างจริงของช่องที่เหลือ
            local nm, room = tostring(r.n or "-"), cStat - cItem - 16
            while U.w(nm, U.F.s) > room and #nm > 4 do nm = nm:sub(1, #nm - 2) end
            if nm ~= tostring(r.n or "-") then nm = nm .. ".." end
            U.text(self, nm, cItem, ty2, U.C.lite, U.F.s)

            if r.st then
                U.text(self, tostring(r.st), cStat - wStat + 10, ty2, U.C.mute, U.F.s)
            end

            -- ---- ยอด + สกุลเงิน  (0.6.16) ------------------------------------
            --
            -- ของเดิมพิมพ์ตัวเลขเปล่า ๆ  "-2500" จึงเป็นได้ทั้งเงินสด HF และ CP
            -- แถวที่ไม่บอกหน่วย คือแถวที่อ่านแล้วยังต้องเดาอยู่ดี
            -- และมันหลอกตาด้วย: HF 2500 กับเงินสด 2500 ไม่ได้ใกล้เคียงกันเลย
            --
            -- เหรียญ + สีประจำสกุล ใช้ชุดเดียวกับที่ราคาในร้านใช้อยู่แล้ว
            -- คนที่จำสีได้จากหน้าร้าน อ่านหน้านี้ได้ทันทีโดยไม่ต้องเรียนใหม่
            local cur = r.cur or KR.CUR.CASH
            local amt = (r.inc and "+" or "-") .. fmtNum(cur, r.a or 0)
            U.textR(self, amt, cAmt, ty2, r.inc and U.C.good or U.curCol(cur), U.F.s)
            U.coin(self, cur, cAmt - U.w(amt, U.F.s) - 21, ty2 + 1, 16)

        end
        cy2 = cy2 + rowH
    end
    self:clearStencilRect()
    U.scrollbar(self, x + w - 4, top, view, total, view, self[sKey])
end

-- ---- ทั้งหน้า ------------------------------------------------------------------
--
-- แถวบน  บัตร+ยอด | ระดับการใช้จ่าย+ปุ่มโอน | ACTION (ชื่อ+โลโก้ / บิล / ยอด 7 วัน)
-- แถวล่าง  ตารางประวัติการใช้จ่ายเต็มความกว้าง เลื่อนได้
--
-- ความสูงแถวบนไม่ได้ตั้งไว้ตายตัว  วาดสองคอลัมน์ข้างก่อนแล้วดูว่าอันไหนยาวกว่า
-- ถ้าตั้งไว้ตายตัว วันที่ม็อดบิลส่งการ์ดมาสองใบพร้อมกันมันจะล้นทับตารางข้างล่างทันที
-- ---- รายได้ร้าน  เห็นเฉพาะแอดมิน ---------------------------------------------
--
-- เจ้าของเซิร์ฟสั่งว่าเงินสดที่ผู้เล่นจ่ายในร้าน "ให้เก็บเป็นของแอดมินที่ถอนได้ในหน้า account"
-- จึงอยู่ในหน้านี้ ไม่ใช่หน้าจัดการ  เพราะมันคือเงินของคนที่กำลังดูอยู่ ไม่ใช่เครื่องมือ
--
-- ยอดนี้ไม่ได้นอนอยู่ในบัญชีไหน  มันคือยอดที่ร้านขายได้และยังไม่มีใครถอน
-- (เหตุผลเชิงเทคนิคอยู่ที่ payOption ฝั่งเซิร์ฟ)
function KRShop:accTill(x, y, w, d)
    -- สองด่าน ไม่ใช่ด่านเดียว
    --   1. isAdminView()  — จอนี้ควรวาดของแอดมินไหม
    --   2. d.till ~= nil  — มีข้อมูลจริงไหม
    -- ด่านที่ 1 เพิ่งเพิ่มใน 0.6.8  ก่อนหน้านี้มีแต่ด่านที่ 2 ซึ่งไม่พอ เพราะ
    -- ข้อมูลเก่าค้างอยู่ใน C.data ได้หลังถูกถอดสิทธิ์ (ดูคอมเมนต์ยาวใน KR_Client)
    -- ตอนนี้ข้างโน้นล้างให้แล้ว ด่านนี้จึงเป็นแค่ชั้นสอง — แต่ต้องมี
    -- เพราะข้อมูลของแอดมินไม่ควรวาดออกมาแม้แต่เฟรมเดียวถ้าคนดูไม่ใช่แอดมิน
    if not isAdminView() then return y end
    local t = d.till
    if not t then return y end

    -- ---- ย่อลงเหลือสองบรรทัด (0.6.8) ---------------------------------------
    -- ของเดิมสูงห้าชั้น: หัวเรื่อง / ตัวเลขใหญ่ / ยอดที่ถอนไปแล้ว / ปุ่มเต็มความกว้าง
    -- กินที่คอลัมน์ขวาไปเยอะมากทั้งที่เกือบทุกวันมันแสดงคำว่า "ยังไม่มีรายได้"
    -- ตัวเลขที่เป็นศูนย์เกือบตลอดเวลาไม่ควรได้ฟอนต์ใหญ่ที่สุดในหน้า
    local XH   = U.h(U.F.xs)
    local SH   = U.h(U.F.s)
    local have = tonumber(t.cash) or 0
    local btnH = math.max(28, SH + 10)
    local bh   = U.capH(true) + 4 + math.max(U.h(U.F.m), btnH) + 10

    local cy = U.panel(self, x, y, w, bh, {
        bg = U.C.bgHead, accent = U.C.gold, line = U.C.gold,
        cap = KR.L("รายได้ร้าน", "SHOP TILL"), capCol = U.C.gold,
        capRight = KR.L("ถอนไปแล้ว ", "taken ") .. money(tonumber(t.taken) or 0),
        pad = 4,
    })
    U.text(self, money(have), x + 12, cy, have > 0 and U.C.cash or U.C.mute, U.F.m)

    if have > 0 then
        local bw = math.min(150, math.floor(w * 0.5))
        local b = U.btn(self, x + w - bw - 12, cy - 2, bw, btnH,
                        KR.L("ถอนเข้าบัญชี", "Take it all"), "ok", self.mx, self.my)
        b.act = "tilltake"
        self.accBtns[#self.accBtns + 1] = b
    end

    return y + bh + U.GAP
end

-- ---- บิลค่าบ้าน / ภาษี  สามปุ่มตามที่เจ้าของเซิร์ฟสั่ง -------------------------
--
-- 0.6.8 — บีบให้เหลือกล่องเดียว  เจ้าของเซิร์ฟบอกว่า "มันกินที่จัง แถมเป็นเหลี่ยม ๆ ไปหมด"
--
-- ก่อนหน้านี้เรื่องบิลกินคอลัมน์ขวาไป **สองกล่อง** ที่พูดเรื่องเดียวกัน
--   การ์ด House bills (จาก accCards)  : ยอดค้าง + ปุ่มดูบิล
--   แผง HOUSE BILLS · TAX (ตรงนี้)    : ยอดค้าง + ปุ่มดูบิล + สวิตช์อีกสองปุ่ม
-- รวมเป็นปุ่มเต็มความกว้างสามปุ่มซ้อนกัน + หัวเรื่องสองอัน = สี่เหลี่ยมเรียงกันหกชั้น
-- ตารางประวัติข้างล่างจึงเหลือที่แค่สองแถว ซึ่งเป็นเหตุผลที่มัน "ดูยากมาก"
--
-- สาเหตุเชิงโครงสร้าง: 0.6.7 ทำให้การ์ดที่ร้านสังเคราะห์เองมี "ของจริง" อยู่ในนั้น
-- แต่ไม่ได้ถอดแผงเดิมออก  ผลคือแก้บั๊กหนึ่งตัวแล้วสร้างของซ้ำขึ้นมาแทน
-- ตอนนี้ฝั่งเซิร์ฟเลิกสังเคราะห์การ์ดใบนั้นแล้ว (ดู S.accountCards) เรื่องบิลอยู่ที่นี่ที่เดียว
--
-- ผังใหม่สามบรรทัด แทนที่จะเป็นหกชั้น
--   แถบหัว : ชื่อ + ยอดค้าง (สีบอกว่าต้องรีบไหม)
--   ปุ่มเดียว : ดูบิล
--   สวิตช์สองอันวางคู่กันในแถวเดียว  ไม่ใช่ปุ่มเต็มความกว้างสองปุ่มซ้อน
--
-- สวิตช์ยัง **บอกสถานะตัวเองตลอดเวลา** ไม่ใช่ปุ่มที่กดแล้วต้องไปเดา
-- (บทเรียนเดียวกับสวิตช์ AS PLAYER ที่ต้องถอดออกไปเมื่อ 0.6.0)
function KRShop:accBill(x, y, w, d)
    local b = d.bill
    if not b then return y end

    local XH   = U.h(U.F.xs)
    local SH   = U.h(U.F.s)

    -- ---- คุยกับม็อดภาษีไม่ได้ : บอกให้ตรงว่าเพราะอะไร -----------------------
    -- ยังต้องบอก ไม่ใช่หายไปเฉย ๆ เจ้าของเซิร์ฟจะได้รู้ว่าต้องลงอะไรเพิ่ม
    -- แต่ไม่ต้องใช้กล่องสี่ชั้นเพื่อบอกว่า "ไม่มี"
    --
    -- 0.6.11 — เดิมช่องนี้พูดว่า "ยังไม่ได้ลงม็อดบิลบนเซิร์ฟนี้" ทุกกรณี
    -- ซึ่งผิดในเกือบทุกกรณี เพราะม็อดลงอยู่แล้ว แค่ของที่เราเรียกมันย้ายที่
    -- ประโยคที่บอกสาเหตุผิด แย่กว่าไม่บอกอะไรเลย เพราะมันส่งคนไปแก้ผิดที่
    if not b.on then
        local why = tostring(b.why or "")
        local head, hint

        if why == "nocfg" or why == "noutil" or why == "nocore" then
            head = KR.L("ม็อดบิลโหลดไม่ครบ", "The bill add-on loaded only halfway")
            hint = KR.L("ดูบรรทัด [Kuraya] bills OFF ใน console ของเซิร์ฟเวอร์",
                        "look for [Kuraya] bills OFF in the server console")
        elseif why == "noglobal" or why == "noepoch" or why == "nostatus" then
            head = KR.L("ม็อดบิลเปลี่ยนไป  Kuraya ต้องอัปเดตตาม",
                        "The bill add-on changed - Kuraya needs updating")
            hint = KR.L("console เซิร์ฟเวอร์บอกไว้แล้วว่าฟังก์ชันไหนหาย",
                        "the server console names the function it could not find")
        else
            head = KR.L("ยังไม่ได้ลงม็อดบิลบนเซิร์ฟนี้",
                        "The bill add-on is not installed here")
            hint = nil
        end

        -- ตัดบรรทัดจริง ๆ  ไม่ใช่หวังว่าประโยคจะสั้นพอ
        -- คอลัมน์ขวาแคบที่สุดในหน้านี้ และแคบลงอีกตอน UI scale สูง
        local tw = w - 24
        local hl = U.wrap(head, U.F.s, tw, 3)
        local il = hint and U.wrap(hint, U.F.xs, tw, 2) or nil

        local bh0 = U.capH(false) + (#hl * SH)
                    + (il and (2 + #il * XH) or 0) + 12
        local c0 = U.panel(self, x, y, w, bh0, {
            bg = U.C.bgHead, cap = KR.L("บิลค่าบ้าน · ภาษี", "HOUSE BILLS · TAX"), pad = 4,
        })
        for i = 1, #hl do
            U.text(self, hl[i], x + 12, c0 + (i - 1) * SH, U.C.mute, U.F.s)
        end
        if il then
            local iy = c0 + #hl * SH + 2
            for i = 1, #il do
                U.text(self, il[i], x + 12, iy + (i - 1) * XH, U.C.dim, U.F.xs)
            end
        end
        return y + bh0 + U.GAP
    end

    local due  = tonumber(b.due) or 0
    local n    = (tonumber(b.land_n) or 0) + (tonumber(b.tax_n) or 0)
    local tone = (n > 0) and U.C.warn or U.C.good

    local btnH = math.max(30, SH + 12)
    local swH  = math.max(26, XH + 14)
    local bh   = U.capH(true) + btnH + 6 + swH + 10

    -- ยอดกับจำนวนใบอยู่บรรทัดเดียวกับหัวเรื่อง  มันคือคำตอบของคำถามเดียวที่คนเปิดมาถาม
    -- ("ต้องรีบไหม") ไม่จำเป็นต้องได้บรรทัดของตัวเองและฟอนต์ใหญ่
    local cy = U.panel(self, x, y, w, bh, {
        bg = U.C.bgHead, accent = tone,
        cap = KR.L("บิลค่าบ้าน · ภาษี", "HOUSE BILLS · TAX"),
        capRight = (n > 0) and (KR.L("ค้าง ", "unpaid ") .. n .. KR.L(" ใบ  ·  ", "  ·  ") ..
                                tostring(due) .. KR.L(" บาท", ""))
                           or KR.L("ไม่มีบิลค้าง", "all paid"),
        capRightCol = tone, pad = 4,
    })

    -- ---- ปุ่มดูบิล ----------------------------------------------------------
    local vb = U.btn(self, x + 12, cy, w - 24, btnH,
                     KR.L("ดูบิลของฉัน", "Open my bills"), "pri", self.mx, self.my)
    vb.act = "billopen"
    self.accBtns[#self.accBtns + 1] = vb
    cy = cy + btnH + 6

    -- ---- สวิตช์หักอัตโนมัติ  สองอันในแถวเดียว ------------------------------
    --
    -- เขียนสั้นลงมาก: ของเดิมทั้งปุ่มคือประโยค "Auto pay ON · safehouse"
    -- ซึ่งยาวจนต้องใช้ปุ่มเต็มความกว้าง  ตอนนี้คำว่า AUTO PAY เป็นป้ายกำกับตัวเดียว
    -- อยู่ซ้ายสุด แล้วสวิตช์บอกแค่ "เรื่องอะไร" กับ "เปิดหรือปิด"
    local capW = U.w(KR.L("หักอัตโนมัติ", "AUTO PAY"), U.F.xs) + 10
    U.text(self, KR.L("หักอัตโนมัติ", "AUTO PAY"), x + 12,
           cy + math.floor((swH - XH) / 2), U.C.dim, U.F.xs)

    local sx   = x + 12 + capW
    local room = (x + w - 12) - sx
    local sw2  = math.floor((room - 6) / 2)

    local function sw(i, flag, th, en, cnt)
        local on  = (b[flag] == true)
        local bx  = sx + (i - 1) * (sw2 + 6)
        local hot = U.hit({ x = bx, y = cy, w = sw2, h = swH }, self.mx, self.my)

        U.fill(self, bx, cy, sw2, swH, on and U.C.accent2 or (hot and U.C.bgRow or U.C.bgCard))
        U.border(self, bx, cy, sw2, swH, on and U.C.good or U.C.line3)
        -- จุดเล็ก ๆ ซ้ายสุดคือสถานะ  ตากวาดเจอเร็วกว่าอ่านคำว่า ON/OFF
        U.fill(self, bx + 6, cy + math.floor(swH / 2) - 3, 6, 6, on and U.C.good or U.C.off)

        local lbl = KR.L(th, en)
        if (cnt or 0) > 0 then lbl = lbl .. " (" .. cnt .. ")" end
        U.text(self, KR.trunc(lbl, 18), bx + 18, cy + math.floor((swH - XH) / 2),
               on and U.C.text or U.C.mute, U.F.xs)

        self.accBtns[#self.accBtns + 1] =
            { x = bx, y = cy, w = sw2, h = swH, act = "billset", which = flag, on = not on }
    end
    sw(1, "land", "เซฟเฮาส์", "safehouse",    b.land_n)
    sw(2, "tax",  "ภาษี",     "personal tax", b.tax_n)

    return y + bh + U.GAP
end

function KRShop:drawAccount(x, y, w, h)
    local d = data()
    self.accBtns = {}

    if self.sendOpen then
        self:drawSendForm(x, y, w, h, d)
        return
    end
    if self.fields and self.fields.sendAmt then self.fields.sendAmt:setVisible(false) end
    if self.fields and self.fields.sendFind then self.fields.sendFind:setVisible(false) end

    local gap  = U.GAP * 2
    local wide = (w >= 900)

    local lw = math.max(280, math.min(340, math.floor(w * 0.26)))
    local aw = wide and math.max(300, math.min(380, math.floor(w * 0.29))) or 0
    local mw = w - lw - gap - (wide and (aw + gap) or 0)

    local mx = x + lw + gap
    local ax = wide and (x + w - aw) or mx

    -- ---- ซ้าย : บัตร + ยอด --------------------------------------------------
    local yA = y
    yA = self:accCard(x, yA, lw, d)
    yA = self:accBalances(x, yA, lw, d)

    -- ---- กลาง : ระดับการใช้จ่าย + ปุ่มโอน ------------------------------------
    local yB = y
    if wide then
        yB = self:accTier(mx, yB, mw, d)

        local btnH = math.max(32, U.h(U.F.s) + 16)
        local b = U.btn(self, mx, yB, mw, btnH,
                        KR.L("โอนเงิน / แต้ม ให้ผู้เล่น", "Send money or points"),
                        "pri", self.mx, self.my)
        b.act = "send"
        self.accBtns[#self.accBtns + 1] = b
        yB = yB + btnH + U.GAP

        -- ปุ่มม็อดอื่นที่ไม่ใช่การ์ด  อยู่ตรงนี้เพราะคอลัมน์ ACTION สงวนไว้สามอย่างตามที่สั่ง
        local acts = d.acts or {}
        for i = 1, #acts do
            local a2    = acts[i]
            local dead  = (a2.dead == true)
            local style = dead and "offb" or (a2.act and "neu" or "offb")
            local lbl   = dead and (tostring(a2.label) .. KR.L(" — ม็อดมีปัญหา", " - add-on error"))
                               or tostring(a2.label)
            local ab = U.btn(self, mx, yB, mw, btnH, lbl, style, self.mx, self.my)
            local ty = yB + math.floor((btnH - U.h(U.F.xs)) / 2)
            if not dead and a2.badge then
                U.textR(self, tostring(a2.badge), mx + mw - 12, ty, U.C.bad, U.F.xs)
            elseif not dead and a2.note then
                U.textR(self, tostring(a2.note), mx + mw - 12, ty, U.C.mute, U.F.xs)
            end
            if a2.act and not dead then
                ab.act, ab.id = "addon", a2.id
                self.accBtns[#self.accBtns + 1] = ab
            end
            yB = yB + btnH + U.GAP
        end
    else
        -- จอแคบ  ระดับการใช้จ่ายไปต่อท้ายคอลัมน์ซ้าย
        yA = self:accTier(x, yA, lw, d)
    end

    -- ---- ขวา : ACTION -------------------------------------------------------
    local yC = y
    yC = self:accWho(ax, yC, wide and aw or mw, d)
    yC = self:accTill(ax, yC, wide and aw or mw, d)
    yC = self:accCards(ax, yC, wide and aw or mw, d)
    yC = self:accBill(ax, yC, wide and aw or mw, d)
    yC = self:accSpend7(ax, yC, wide and aw or mw, d)

    if not wide then
        local btnH = math.max(32, U.h(U.F.s) + 16)
        local b = U.btn(self, ax, yC, mw, btnH,
                        KR.L("โอนเงิน / แต้ม ให้ผู้เล่น", "Send money or points"),
                        "pri", self.mx, self.my)
        b.act = "send"
        self.accBtns[#self.accBtns + 1] = b
        yC = yC + btnH + U.GAP
    end

    -- ---- ล่าง : ประวัติการใช้จ่าย --------------------------------------------
    --
    -- 0.6.8 — พื้นขั้นต่ำเดิมคือ 120px ซึ่งพอดีกับ "หัวตาราง + สองแถว"
    -- เจ้าของเซิร์ฟบอกว่า "ประวัติข้างล่างดูยากมาก" และนั่นคือเหตุผล:
    -- ตารางที่เห็นสองแถวไม่ใช่ตาราง มันคือรายการล่าสุดที่บังเอิญมีเส้นตาราง
    --
    -- ขั้นต่ำใหม่คิดจาก "กี่แถวถึงจะอ่านเป็นประวัติได้" แล้วคูณกลับเป็นพิกเซล
    -- ไม่ใช่ตัวเลขที่พิมพ์ลงไปเฉย ๆ  พอฟอนต์ผู้เล่นใหญ่ขึ้น ขั้นต่ำก็โตตาม
    local MIN_ROWS = 6
    local minH = (U.h(U.F.xs) + 12)                 -- แถบชิปกรอง
                 + (U.h(U.F.xs) + 12)               -- หัวคอลัมน์
                 + MIN_ROWS * math.max(28, U.h(U.F.s) + 14)

    local topH = math.max(yA, yB, yC) - y
    local hy   = y + topH + U.GAP
    local hh   = h - topH - U.GAP
    -- ตารางต้องเหลือที่พออ่านได้เสมอ  ถ้าไม่พอให้บีบแถวบนแทนที่จะซ่อนตาราง
    if hh < minH then
        hh = math.min(h, minH)
        hy = y + h - hh
    end
    self:accHistory(x, hy, w, hh, d)
end

-- ---- ฟอร์มโอน ------------------------------------------------------------------
-- ทับลงบนหน้า Account ไปเลย  ไม่เปิดหน้าต่างที่สอง
-- บทเรียนจากแผง Account เดิม: หน้าต่างที่สองมีจุดพังเยอะกว่าที่ได้คืนมา
function KRShop:drawSendForm(x, y, w, h, d)
    local snd = d.send or {}
    -- เผื่อค่าเก่าที่ค้างอยู่จากรุ่นก่อน  ผู้เล่นที่เคยเลือก CASH ไว้ต้องไม่ค้างอยู่ในสกุลที่ถอดออกแล้ว
    if self.sendCur == KR.CUR.CASH then self.sendCur = nil end
    self.sendCur = self.sendCur or KR.CUR.HF
    local cur  = self.sendCur
    local meta = KR.CUR_META[cur] or {}

    -- ฟอร์มไม่ต้องกินความกว้างพันพิกเซล  จำกัดไว้แล้ววางชิดซ้ายของพื้นที่เนื้อหา
    local fw = math.max(320, math.min(460, math.floor(w * 0.42)))
    local cy = y

    U.text(self, KR.L("โอนให้ผู้เล่น", "Send to a player"), x, cy, U.C.text, U.F.m)
    cy = cy + U.h(U.F.m) + 10

    -- เลือกสกุล  ใช้ช่องกรอกและปุ่มเดียวกัน ต่างกันแค่หน่วยกับกติกา
    --
    -- **ไม่มีเงินสดในนี้แล้ว** ตามที่เจ้าของเซิร์ฟสั่ง
    --
    -- เหตุผลที่ถูกต้องด้วย ไม่ใช่แค่ทำตามคำสั่ง: เงินสดเป็นของ Akacount
    -- การโอนเงินสดต้องเดินผ่าน ledger ของธนาคาร ซึ่งมีหน้าจอ กติกา ค่าธรรมเนียม
    -- และประวัติของมันเองอยู่แล้ว  การมีทางโอนเงินสดทางที่สองในร้าน
    -- แปลว่ามีสองที่ที่ต้องแก้ทุกครั้งที่กติกาการโอนเปลี่ยน แล้ววันหนึ่งมันจะไม่ตรงกัน
    --
    -- ร้านเป็นเจ้าของ HF  Town Rank เป็นเจ้าของ CP  สองอันนี้จึงอยู่ที่นี่ได้เต็มปาก
    -- เซิร์ฟปฏิเสธ cur = cash ซ้ำอีกชั้นใน S.send  ชิปที่หายไปคือความสุภาพ ด่านจริงอยู่โน่น
    self.curBtns = {}
    local SEND_CURS = { KR.CUR.HF, KR.CUR.CP }
    local chH = math.max(30, U.h(U.F.s) + 12)
    local cw3 = math.floor((fw - 6) / #SEND_CURS)
    for i, c in ipairs(SEND_CURS) do
        local on = (cur == c)
        local bx = x + (i - 1) * (cw3 + 6)
        local m2 = KR.CUR_META[c] or {}
        local hot = U.hit({ x = bx, y = cy, w = cw3, h = chH }, self.mx, self.my)
        U.fill(self, bx, cy, cw3, chH, on and U.C.accent2 or (hot and U.C.bgRow or U.C.bgCard))
        if on then U.fill(self, bx, cy + chH - 2, cw3, 2, U.C.accent) end
        U.coin(self, c, bx + 8, cy + math.floor((chH - 18) / 2), 18)
        U.text(self, m2.label or c:upper(), bx + 32,
               cy + math.floor((chH - U.h(U.F.xs)) / 2), on and U.C.text or U.C.mute, U.F.xs)
        self.curBtns[#self.curBtns + 1] = { x = bx, y = cy, w = cw3, h = chH, cur = c }
    end
    cy = cy + chH + U.GAP

    -- ยอดที่ใช้ได้  ต้องเห็นก่อนกรอก ไม่ใช่รู้ตอนกดแล้วเด้งว่าไม่พอ
    local rawHave = tonumber((d.bal or {})[cur]) or 0
    local have    = (cur == KR.CUR.CASH) and math.floor(rawHave / KR.SUBUNIT) or math.floor(rawHave)
    local hh      = math.max(30, U.h(U.F.s) + 12)
    U.fill(self, x, cy, fw, hh, U.C.bgCard)
    U.coin(self, cur, x + 10, cy + math.floor((hh - 18) / 2), 18)
    U.text(self, KR.L("มีอยู่", "You have"), x + 34, cy + math.floor((hh - U.h(U.F.xs)) / 2),
           U.C.mute, U.F.xs)
    U.textR(self, (cur == KR.CUR.CASH) and string.format("%.2f", rawHave / KR.SUBUNIT)
                                        or tostring(have),
            x + fw - 10, cy + math.floor((hh - U.h(U.F.s)) / 2), U.curCol(cur), U.F.s)
    cy = cy + hh + U.GAP

    -- ==========================================================================
    -- รายชื่อผู้รับ  (0.6.23 — เขียนใหม่ทั้งบล็อก)
    --
    -- ของเดิม: `for i = 1, math.min(#names, 6)` แล้วจบ  **ไม่มีทางเลื่อนเลย**
    -- เจ้าของเซิร์ฟรายงานตรง ๆ ว่า "รายชื่อตรงนี้เลื่อนไม่ได้" พร้อมรูปที่เห็น
    -- หกชื่อแรกเรียงตามตัวอักษร: 2B4A · admin · Air22435 · Akm398 · Am Capp · Anamimai
    --
    -- แปลว่าบนเซิร์ฟที่มีคนห้าสิบคน **คนที่ชื่อขึ้นต้นหลัง "An" โอนให้ไม่ได้ตลอดกาล**
    -- และจอไม่ได้บอกด้วยว่ายังมีต่อ  ลิสต์แค่จบห้วน ๆ ที่หกบรรทัด
    -- คนอ่านออกได้ทางเดียวว่า "เพื่อนไม่ได้ออนไลน์" ทั้งที่เขาออนอยู่
    --
    -- นี่คือบั๊กตัวเดียวกับลิสต์ค้นไอเทมของ 0.6.11 เป๊ะ ๆ (shown = min(#list, 7))
    -- ตอนนั้นแก้ด้วยการใส่ที่เลื่อน  ตอนนี้ใส่ทั้งที่เลื่อนและช่องค้น เพราะการเลื่อน
    -- ทีละหกชื่อผ่านคนสองร้อยคนคือการแก้ที่ตอบว่า "ทำได้" แต่ไม่ได้ตอบว่า "ใช้ได้"
    -- ==========================================================================
    local all  = snd.names or {}
    local rowH = U.h(U.F.s) + 12

    U.text(self, KR.L("โอนให้ใคร", "Send to"), x, cy, U.C.dim, U.F.xs)
    U.textR(self, tostring(#all) .. KR.L(" คน", " online"),
            x + fw, cy, U.C.mute, U.F.xs)
    cy = cy + U.h(U.F.xs) + 5

    -- ช่องค้น  โผล่เมื่อมีคนมากพอที่การเลื่อนอย่างเดียวจะน่ารำคาญ
    local SEND_ROWS = 6
    local findBox = self.fields and self.fields.sendFind
    local q = ""
    if findBox and #all > SEND_ROWS then
        local fh2 = boxH() + 6
        U.fill(self, x, cy, fw, fh2, U.C.bgDark)
        U.border(self, x, cy, fw, fh2, U.C.line3)
        findBox:setVisible(true)
        findBox:setX(x + 5); findBox:setY(cy + 3)
        sizeBox(findBox, fw - 10, fh2 - 6)
        q = tostring(findBox:getInternalText() or "")
        if q == "" then
            U.text(self, KR.L("พิมพ์ชื่อเพื่อค้น", "type a name to search"),
                   x + 12, cy + math.floor((fh2 - U.h(U.F.xs)) / 2), U.C.mute, U.F.xs)
        end
        cy = cy + fh2 + 6
    elseif findBox then
        findBox:setVisible(false)
    end

    -- กรองแบบ "ตัวอักษรตรง ๆ" ไม่ใช่แพตเทิร์น  ชื่อผู้เล่นมี ( ) - % ได้
    -- ถ้าส่งเข้า find() แบบแพตเทิร์น ชื่อพวกนั้นจะทำให้ทั้งหน้าตายตอนพิมพ์ค้น
    local names = all
    if q ~= "" then
        local ql = q:lower()
        names = {}
        for i = 1, #all do
            if tostring(all[i]):lower():find(ql, 1, true) then
                names[#names + 1] = all[i]
            end
        end
    end

    self.nameBtns = {}
    self.sendMax = math.max(0, #names - SEND_ROWS)
    -- หนีบทุกเฟรม ไม่ใช่แค่ตอนหมุนล้อ  ลิสต์สั้นลงได้ระหว่างที่เลื่อนค้างอยู่
    -- (พิมพ์ค้นต่อ = ผลค้นแคบลง)  ไม่หนีบ = เห็นช่องว่างทั้งที่มีคนอยู่
    if (self.sendScroll or 0) > self.sendMax then self.sendScroll = self.sendMax end
    local off = math.max(0, math.floor(self.sendScroll or 0))

    local shown = math.min(#names, SEND_ROWS)
    local listY = cy
    if #names == 0 then
        U.text(self, (#all == 0)
                   and KR.L("ยังไม่มีใครให้โอน", "Nobody else is online")
                    or KR.L("ไม่มีชื่อที่ตรงกับที่ค้น", "No name matches that"),
               x + 4, cy + 2, U.C.mute, U.F.xs)
        cy = cy + rowH
    end
    for i = 1, shown do
        local nm = names[i + off]
        if nm == nil then break end
        local on  = (self.to == nm)
        local hot = U.hit({ x = x, y = cy, w = fw, h = rowH }, self.mx, self.my)
        U.fill(self, x, cy, fw, rowH, on and U.C.bgSel or (hot and U.C.bgRow or U.C.bgCard))
        if on then U.fill(self, x, cy, 3, rowH, U.C.accent) end
        -- ตัดด้วยความกว้างที่มีจริง  ชื่อผู้เล่นยาวได้ไม่จำกัด และฟอนต์โตตาม UI scale
        U.text(self, U.wrap(nm, U.F.s, fw - 24, 1)[1], x + 12, cy + 5,
               on and U.C.text or U.C.lite, U.F.s)
        self.nameBtns[#self.nameBtns + 1] = { x = x, y = cy, w = fw, h = rowH, name = nm }
        cy = cy + rowH + 3
    end

    -- บอกว่ายังมีต่อ  ลิสต์ที่จบห้วน ๆ อ่านว่า "หมดแล้ว" ซึ่งเป็นคำตอบที่ผิด
    -- นี่คือครึ่งที่ขาดไปของบั๊กเดิม ไม่ใช่แค่เลื่อนไม่ได้ แต่ไม่มีอะไรบอกว่าควรเลื่อน
    local listH = cy - listY
    self.sendListRect = { x = x, y = listY, w = fw, h = math.max(rowH, listH) }
    if self.sendMax > 0 then
        U.scrollbar(self, x + fw - 4, listY, listH, #names, SEND_ROWS, off)
        U.textR(self, (off + shown) .. " / " .. #names, x + fw - 10, listY - U.h(U.F.xs) - 2,
                U.C.dim, U.F.xs)
    end
    cy = cy + U.GAP

    -- จำนวน
    U.text(self, KR.L("จำนวน", "Amount"), x, cy, U.C.dim, U.F.xs)
    cy = cy + U.h(U.F.xs) + 5
    local bxh = boxH() + 6
    U.fill(self, x, cy, fw, bxh, U.C.bgDark)
    U.border(self, x, cy, fw, bxh, U.C.line3)
    local box = self.fields.sendAmt
    box:setVisible(true)
    box:setX(x + 5); box:setY(cy + 3)
    sizeBox(box, fw - 10, bxh - 6)
    cy = cy + bxh + U.GAP

    -- ค่าธรรมเนียม  โชว์ก่อนกด ไม่ใช่หักเงียบ ๆ แล้วค่อยรู้ทีหลัง
    local amt   = math.floor(tonumber(box:getInternalText() or "") or 0)
    local fee   = KR.hfSendFee(amt)
    local total = amt + fee
    -- ขั้นต่ำมีเฉพาะ HF  อีกสองสกุลไม่มีเหตุผลจะกันยอดเล็ก
    local minS  = (cur == KR.CUR.HF) and (snd.min or KR.hfSendOpt("MIN")) or 1

    local lnH = U.h(U.F.s) + 8
    local sumH = lnH * 3 + 16
    U.fill(self, x, cy, fw, sumH, U.C.bgHead)
    U.text(self,  KR.L("ผู้รับได้", "They get"), x + 12, cy + 8, U.C.mute, U.F.xs)
    U.textR(self, tostring(amt), x + fw - 12, cy + 7, U.C.lite, U.F.s)
    U.text(self,  KR.L("ค่าธรรมเนียม", "Fee"), x + 12, cy + 8 + lnH, U.C.mute, U.F.xs)
    U.textR(self, tostring(fee), x + fw - 12, cy + 7 + lnH,
            fee > 0 and U.C.warn or U.C.good, U.F.s)
    U.hr(self, x + 12, cy + 6 + lnH * 2, fw - 24, U.C.line2)
    U.text(self,  KR.L("คุณจ่ายรวม", "You pay"), x + 12, cy + 10 + lnH * 2, U.C.lite, U.F.xs)
    U.textR(self, tostring(total), x + fw - 12, cy + 9 + lnH * 2,
            total > have and U.C.bad or U.C.text, U.F.s)
    cy = cy + sumH + U.GAP

    -- เพดานต่อวัน  ถ้ามีตั้งไว้
    if (snd.daily or 0) > 0 then
        U.text(self, KR.L("วันนี้โอนไปแล้ว ", "Sent today ") ..
                     tostring(snd.usedToday or 0) .. " / " .. tostring(snd.daily),
               x, cy, U.C.dim, U.F.xs)
        cy = cy + U.h(U.F.xs) + 6
    end

    U.text(self, KR.L("โอนแล้วเรียกคืนไม่ได้", "Transfers are final"), x, cy, U.C.mute, U.F.xs)

    -- ปุ่ม
    local btnH = math.max(32, U.h(U.F.s) + 16)
    local by   = y + h - btnH
    local half = math.floor((fw - U.GAP) / 2)
    self.bSendCancel = U.btn(self, x, by, half, btnH, KR.L("ยกเลิก", "Cancel"),
                             "neu", self.mx, self.my)

    local why
    if self.to == nil   then why = KR.L("เลือกผู้รับ", "Pick someone")
    elseif amt < minS   then why = KR.L("ขั้นต่ำ ", "Min ") .. tostring(minS)
    elseif total > have then why = KR.L("ไม่พอ", "Not enough ") .. (meta.label or "") end

    self.bSendOk = U.btn(self, x + half + U.GAP, by, half, btnH,
                         why or (KR.L("โอน ", "Send ") .. tostring(amt) .. " " .. (meta.label or "")),
                         why and "offb" or "pri", self.mx, self.my)
    if why then self.bSendOk = nil end
end

function KRShop:accountClick(x, y)
    if self.sendOpen then
        if U.hit(self.bSendCancel, x, y) then self.sendOpen = false; return true end
        for _, b in ipairs(self.nameBtns or {}) do
            if U.hit(b, x, y) then self.to = b.name; return true end
        end
        for _, b in ipairs(self.curBtns or {}) do
            if U.hit(b, x, y) then self.sendCur = b.cur; return true end
        end
        if self.bSendOk and U.hit(self.bSendOk, x, y) then
            local box = self.fields.sendAmt
            req(KR.CMD.SEND_HF, {
                to  = self.to,
                cur = self.sendCur or KR.CUR.HF,
                n   = math.floor(tonumber(box and box:getInternalText() or "") or 0),
            })
            if box then box:setText("") end
            self.sendOpen = false
            return true
        end
        return true
    end

    -- ชิปกรองประวัติ
    for _, b in ipairs(self.logBtns or {}) do
        if U.hit(b, x, y) then
            self.logFilter = (b.filter ~= "all") and b.filter or nil
            self.logScroll, self.logScroll_adm = 0, 0
            return true
        end
    end

    for _, b in ipairs(self.accBtns or {}) do
        if U.hit(b, x, y) then
            if b.act == "send" then
                self.sendOpen = true
                self.to = nil
                self.sendCur = self.sendCur or KR.CUR.HF
                -- เปิดฟอร์มใหม่ = เริ่มที่บรรทัดแรกและไม่มีคำค้นค้าง
                -- คำค้นที่ค้างจากครั้งก่อนอ่านว่า "เพื่อนคนนั้นไม่ออนไลน์แล้ว"
                self.sendScroll = 0
                if self.fields and self.fields.sendFind then
                    self.fields.sendFind:setText("")
                end
            elseif b.act == "billset" then
                req(KR.CMD.BILL_SET, { which = b.which, on = b.on })
            elseif b.act == "billopen" then
                -- ---- เปิดม็อดภาษีตรง ๆ  ไม่มีทางอื่น ------------------------
                --
                -- 0.6.10 — เจ้าของเซิร์ฟสั่งชัด: "ให้คนกด Open my bills
                -- ไปเปิดม็อด Tax ตรง ๆ เลย"
                --
                -- 0.6.6 เคยทำลิสต์บิลอ่านอย่างเดียวของร้านขึ้นมา ตอนนั้นเหตุผลคือ
                -- หน้าต่างของม็อดภาษีวาดไม่ออก  พอบั๊กนั้นถูกแก้ (มันเป็นบั๊กของเราเอง
                -- เรื่อง tex.h — ดู PZ-B42-texture-getWidth-RULE) ลิสต์นั้นก็กลายเป็น
                -- ทางที่สองที่ทำได้น้อยกว่าทางแรก: ดูได้อย่างเดียว จ่ายไม่ได้
                --
                -- ทางที่สองที่ทำได้น้อยกว่า ไม่ใช่ตัวเลือก มันคือทางตันที่มีปุ่มสวย ๆ
                -- ลิสต์ทั้งชุดจึงถูกถอดออกใน 0.6.10 (ทั้ง drawBillList, S.billList
                -- และคำสั่ง BILL_OPEN)  เรื่องบิลมีหน้าจอเดียวคือของม็อดภาษี
                -- ร้านเก็บไว้แค่สวิตช์หักอัตโนมัติ ซึ่งเป็นของร้านจริง ๆ
                local pl = getSpecificPlayer(0)
                local ok = false

                if pl and type(HFTaxUI) == "table"
                   and type(HFTaxUI.InvoiceManager) == "table"
                   and type(HFTaxUI.InvoiceManager.openWindow) == "function" then

                    -- ส่ง safehouse ไปด้วยเหมือนที่คลิกขวาที่พื้นทำ
                    --
                    -- 0.6.12 หมายเหตุจากการอ่านซอร์สจริงของ HF_Tax (ยังไม่แก้ เพราะ
                    -- เจ้าของเซิร์ฟบอกว่าปุ่มนี้ใช้งานได้อยู่ และรอบนี้ขอให้แตะแค่รถกับชุด):
                    -- `HFTax_InvoiceManagerUI.lua:169 populateBills()` ระบุว่า
                    -- การส่ง safehouse เข้าไป = isSafehouseMode = กรองเฉพาะ
                    -- b.safehouseKey == shKey อย่างเดียว ซึ่ง **ซ่อนภาษีส่วนตัว**
                    -- ส่วนการไม่ส่ง = เห็นทั้งบิลบ้านที่ตัวเองเกี่ยวข้อง และภาษีส่วนตัว
                    -- ถ้าวันหนึ่งมีคนบอกว่า "กดดูบิลแล้วภาษีส่วนตัวหาย" คำตอบอยู่ตรงนี้
                    local sh = nil
                    if (tonumber((data().bill or {}).land_n) or 0) > 0 and SafeHouse ~= nil then
                        local okSh, got = pcall(function() return SafeHouse.hasSafehouse(pl) end)
                        if okSh then sh = got end
                    end
                    ok = pcall(HFTaxUI.InvoiceManager.openWindow, pl, sh)
                end

                -- เปิดไม่ได้ = บอกตรง ๆ  ไม่ใช่พาไปหน้าอื่นแทนแบบเงียบ ๆ
                -- (ok ยืนยันได้แค่ว่าเรียกแล้วไม่ระเบิดทันที ไม่ได้ยืนยันว่าวาดออก
                --  บทเรียนที่จ่ายไปแล้วใน 0.6.6)
                if not ok then
                    KRShop.notify(KR.L("เปิดหน้าบิลไม่ได้  ม็อดภาษีอาจยังไม่พร้อม",
                                       "Could not open the bill window - the tax mod is not ready"),
                                  "bad")
                end
            elseif b.act == "tilltake" then
                -- ไม่ส่ง n ไป = ถอนทั้งหมด  เซิร์ฟเป็นคนตัดสินยอด ไม่ใช่จอ
                -- (จอที่ถูกแก้ส่งยอดเท่าไรก็ได้ ฝั่งเซิร์ฟจึงต้องคุมเพดานเอง)
                req(KR.CMD.TILL_TAKE, {})
            elseif b.act == "addon" and b.id then
                -- ส่งไปแค่ id  เซิร์ฟหา onClick เองจากทะเบียนของมัน
                req(KR.CMD.ACCOUNT_ACTION, { id = b.id })
            elseif b.act == "card" and b.card and b.id then
                -- การ์ดจากม็อดอื่น  ส่งทั้ง id การ์ดและ id ปุ่มไป เซิร์ฟหา onAction เอง
                req(KR.CMD.ACCOUNT_ACTION, { card = b.card, action = b.id })
            end
            return true
        end
    end
    return true
end

-- ==============================================================================
-- คลิก
-- ==============================================================================
function KRShop:pagesClick(x, y)
    if self.page == "auction" then
        for _, b in ipairs(self.tabBtns or {}) do
            if U.hit(b, x, y) then self.auctTab = b.tab; self.scroll = 0; return true end
        end
        for _, b in ipairs(self.auctBtns or {}) do
            if U.hit(b, x, y) then
                if b.act == "auctart" then
                    self.auctArt = b.val
                elseif b.act == "auctbg" then
                    self.auctBg = b.val
                elseif b.act == "auctslot" then
                    req(KR.CMD.AUCT_SLOT, {})
                elseif b.act == "auctpay" then
                    req(KR.CMD.AUCT_PAY, { id = b.lot })
                elseif b.act == "auctform" then
                    -- ผู้เล่นธรรมดาไม่มีทางมาถึงบรรทัดนี้ได้อยู่แล้ว (ปุ่มไม่ถูกวาด)
                    -- แต่กันไว้อีกชั้น  ปุ่มที่ไม่ถูกวาดกับสิทธิ์ที่ไม่มีเป็นคนละเรื่องกัน
                    if not canOpenLot() then return true end
                    self.auctNew = not self.auctNew
                    if self.auctNew then
                        -- เติมค่าเริ่มต้นที่ใช้ได้ทันที  ไม่ต้องเดาว่ากรอกอะไร
                        if self.fields.name     then self.fields.name:setText("") end
                        if self.fields.stock    then self.fields.stock:setText("100") end
                        if self.fields.quota    then self.fields.quota:setText("360") end
                        if self.fields.auctStep then self.fields.auctStep:setText("0") end
                        if self.fields.auctBuy  then self.fields.auctBuy:setText("0") end
                        self.auctArt = self.auctArt or KR.AUCT_ART_DEFAULT
                        self.auctBg  = self.auctBg  or KR.AUCT_BG_DEFAULT
                    else
                        self.auctMenu = nil
                    end
                elseif b.act == "open" then
                    -- เข้าไปดูล็อตเดียว  ล้างช่องใส่ราคาเองทุกครั้งที่เปิดใบใหม่
                    -- ไม่งั้นตัวเลขของล็อตที่แล้วจะค้างอยู่ แล้วคนกด "บิดตามที่ใส่"
                    -- ในราคาที่ตั้งใจไว้กับของอีกชิ้น
                    self.auctOpen = b.lot
                    self.auctNew  = false
                    self.scroll   = 0
                    if self.fields and self.fields.auctBid then self.fields.auctBid:setText("") end
                elseif b.act == "auctback" then
                    self.auctOpen = nil
                    self.scroll   = 0
                elseif b.act == "bidown" then
                    -- ราคาที่พิมพ์เองเป็น "บาท" เหมือนทุกช่องเงินในม็อด  ส่งเป็นสตางค์
                    local box = self.fields and self.fields.auctBid
                    local n = math.floor((tonumber(box and box:getInternalText() or "") or 0)
                                         * KR.SUBUNIT)
                    if n <= 0 then
                        KRShop.notify(KR.L("ยังไม่ได้ใส่ราคา", "Type an amount first"), "bad")
                        return true
                    end
                    req(KR.CMD.AUCT_BID, { id = b.lot, n = n })
                    if box then box:setText("") end
                elseif b.act == "select" then
                    self.auctSel = b.lot
                elseif b.act == "auctpick" then
                    -- กดปุ่มเดิมซ้ำ = ปิด  ตามพฤติกรรมเดียวกับเมนูหมวดของหน้าจัดการ
                    if self.auctMenu then
                        self.auctMenu = nil
                    else
                        -- รายการถูกสร้างตอนวาดจากคำค้นในช่อง  ตรงนี้เก็บแค่ตำแหน่ง
                        self.auctMenu = { x = b.menuX, y = b.menuY, scroll = 0 }
                    end
                elseif b.act == "auctcreate" then
                    local nm = self.fields.name  and self.fields.name:getInternalText()  or ""
                    local st = tonumber(self.fields.stock and self.fields.stock:getInternalText() or "") or 0
                    local hr = tonumber(self.fields.quota and self.fields.quota:getInternalText() or "") or 0
                    local sp = tonumber(self.fields.auctStep and self.fields.auctStep:getInternalText() or "") or 0
                    local bn = tonumber(self.fields.auctBuy and self.fields.auctBuy:getInternalText() or "") or 0

                    -- ตรวจฝั่งจอก่อนยิง  ไม่ใช่เพื่อความปลอดภัย เซิร์ฟตรวจซ้ำอยู่แล้ว
                    -- แต่คำปฏิเสธจากเซิร์ฟไปโผล่เป็นป้ายเล็ก ๆ ส่วนตรงนี้อยู่ติดกับช่องที่กรอกผิด
                    if nm:gsub("%s", "") == "" then
                        KRShop.notify(KR.L("ยังไม่ได้กรอกว่าขายอะไร", "Say what you are selling first"), "bad")
                        return true
                    end
                    if st <= 0 then
                        KRShop.notify(KR.L("ราคาเริ่มต้องมากกว่าศูนย์", "Start price must be above zero"), "bad")
                        return true
                    end
                    if bn > 0 and bn <= st then
                        KRShop.notify(KR.L("ราคาซื้อทันทีต้องสูงกว่าราคาเริ่ม",
                                           "Buy now has to be above the start price"), "bad")
                        return true
                    end

                    req(KR.CMD.AUCT_SELL, {
                        name  = nm,
                        start = math.floor(st * KR.SUBUNIT),   -- กรอกเป็นบาท ส่งเป็นสตางค์
                        mins  = math.floor(hr),                -- ช่องนี้เป็นนาทีแล้วตั้งแต่ 0.6.0
                        step  = math.floor(math.max(0, sp) * KR.SUBUNIT),
                        buy   = math.floor(math.max(0, bn) * KR.SUBUNIT),
                        art   = self.auctArt or KR.AUCT_ART_DEFAULT,
                        bg    = self.auctBg  or KR.AUCT_BG_DEFAULT,
                    })
                    self.auctNew = false
                    self.auctMenu = nil
                elseif b.act == "bid" then
                    req(KR.CMD.AUCT_BID, { id = b.lot, n = b.need })
                elseif b.act == "claim" then
                    req(KR.CMD.AUCT_CLAIM, { id = b.lot })
                elseif b.act == "cancel" then
                    req(KR.CMD.AUCT_CANCEL, { id = b.lot })
                end
                return true
            end
        end
        return false
    end

    if self.page == "credit" then
        self:creditInit()
        for _, b in ipairs(self.crBtns or {}) do
            if U.hit(b, x, y) then
                if b.act == "amt" then
                    local box = self.fields and self.fields.grantAmt
                    if box then box:setText(string.format("%.2f", (b.val or 0) / KR.SUBUNIT)) end
                elseif b.act == "terms" then
                    self.cr.terms = b.val
                elseif b.act == "borrow" then
                    local box = self.fields and self.fields.grantAmt
                    local n = math.floor((tonumber(box and box:getInternalText() or "") or 0) * KR.SUBUNIT)
                    req(KR.CMD.CREDIT_BORROW, { n = n, terms = self.cr.terms })
                elseif b.act == "repay" then
                    req(KR.CMD.CREDIT_REPAY, {})
                end
                return true
            end
        end
        return false
    end

    return false
end


-- ==============================================================================
-- ช่องพิมพ์แล้วเลื่อนเลือกชื่อผู้เล่น
--
-- ทำไมทุกช่องชื่อในม็อดต้องกลายเป็นแบบนี้
--   ชื่อที่พิมพ์ผิดหนึ่งตัวอักษรคือเงินที่โอนไปหาบัญชีที่ไม่มีตัวตน
--   ของเดิมรับสตริงดิบจากช่องพิมพ์ แล้วไปรู้ว่าผิดตอน handler ทำงาน
--   = ผู้เล่นรู้ว่าพิมพ์ผิดหลังจากที่กดยืนยันไปแล้ว ซึ่งสายเกินไปหนึ่งขั้นเสมอ
--
-- รายชื่อมาจากเซิร์ฟทุกครั้ง (KR.CMD.FIND_PLAYER) ไม่ได้เดาจากข้อมูลที่จอมีอยู่
-- และเซิร์ฟเป็นคนตัดสินว่าใครเห็นใครได้ตามที่เจ้าของเซิร์ฟเคาะไว้ (ข้อ 1 ตอบ "ข"):
--   ผู้เล่น  เห็นเฉพาะคนที่ออนไลน์ตอนนี้
--   แอดมิน  ค้นคนออฟไลน์ได้ด้วย เพราะเคสที่ต้องสืบมากที่สุดคือเคสที่เจ้าตัวไม่อยู่
--
-- มีกล่องพิมพ์จริงอยู่ใบเดียวทั้งม็อด (self.fields.whoFind) แล้วย้ายไปมา
-- ช่องที่ไม่ได้กำลังแก้อยู่จะวาดเป็น "ชิปชื่อที่เลือกไว้" ซึ่งกดแล้วสลับมาเป็นกล่องพิมพ์
-- ทำแบบนี้เพราะ ISTextEntryBox แต่ละใบเป็น child จริงของหน้าต่าง  การมีสิบใบ
-- ลอยอยู่พร้อมกันแปลว่ามีสิบสี่เหลี่ยมที่กินคลิกและกินคีย์บอร์ดอยู่ตลอดเวลา
-- ==============================================================================
function KRShop:whoValue(id)
    self.who = self.who or {}
    local v = self.who[id]
    return v and v.key or nil, v and v.disp or nil
end

function KRShop:whoSet(id, k, disp)
    self.who = self.who or {}
    if k then self.who[id] = { key = k, disp = disp or k }
    else self.who[id] = nil end
end

-- ยิงคำค้นไปเซิร์ฟเมื่อข้อความเปลี่ยน  ไม่ใช่ทุกเฟรม
--
-- ช่องพิมพ์ไม่มี event บอกว่า "ข้อความเปลี่ยนแล้ว" ที่เชื่อถือได้ในทุกบิลด์
-- จึงเทียบกับค่าที่เห็นรอบก่อนเอง  ซึ่งได้ผลเดียวกันและไม่พึ่ง API ที่อาจไม่มี
-- เป็นเมธอดไม่ใช่ local function โดยตั้งใจ
--
-- prerender อยู่ "เหนือ" บล็อกนี้ในไฟล์  และ Lua ผูก local ตอนคอมไพล์
-- โค้ดเหนือบรรทัด `local function whoPoll` จะอ่านชื่อนี้เป็นโกลบอลที่ยังไม่มีค่า
-- = nil แล้วพังตอนรันเฉพาะเฟรมที่เดินเข้าเส้นนั้นเท่านั้น
-- (กับดักเดียวกับ itemDisplay ที่เคยพัง 1,017 ครั้งใน console เดียว
--  ตอนนี้ lint rule 5b จับได้แล้ว แต่ทางที่ถูกคือไม่สร้างเคสให้มันต้องจับ)
-- เมธอดบนตาราง KRShop ถูกหาตอนเรียก ไม่ใช่ตอนคอมไพล์ จึงไม่มีเรื่องลำดับเข้ามาเกี่ยว
function KRShop:whoPoll()
    if not self.whoFor then return end
    local box = self.fields and self.fields.whoFind
    if not box then return end
    local txt = box:getInternalText() or ""
    if txt == self.whoLast then return end
    self.whoLast = txt
    req(KR.CMD.FIND_PLAYER, { q = txt })
end

-- วาดช่องหนึ่งช่อง  คืนความสูงที่ใช้ไปจริง
--
-- id คือชื่อช่อง ("hfpTo", "grantTo", "sendTo", "accWho") ใช้แยกว่าค่าที่เลือกไว้
-- เป็นของช่องไหน  สองช่องบนหน้าเดียวกันจึงจำค่าของตัวเองแยกกันได้
function KRShop:whoField(id, x, y, w, label)
    self.whoBtns = self.whoBtns or {}
    local BH  = boxH()
    local XH  = U.h(U.F.xs)

    if label and label ~= "" then
        U.text(self, label, x, y, U.C.dim, U.F.xs)
        y = y + XH + 3
    end

    local selKey, selDisp = self:whoValue(id)
    local active = (self.whoFor == id)

    -- ---- ยังไม่ได้แก้ช่องนี้  วาดเป็นชิป -------------------------------------
    if not active then
        local hot = U.hit({ x = x, y = y, w = w, h = BH }, self.mx, self.my)
        U.fill(self, x, y, w, BH, hot and U.C.bgRow or U.C.bgDark)
        U.border(self, x, y, w, BH, selKey and U.C.line3 or U.C.line2)
        local ty = y + math.floor((BH - U.h(U.F.s)) / 2)
        if selKey then
            U.fill(self, x + 8, y + math.floor(BH / 2) - 3, 6, 6, U.C.good)
            U.text(self, KR.trunc(selDisp or selKey, 22), x + 20, ty, U.C.text, U.F.s)
        else
            U.text(self, KR.L("เลือกผู้เล่น", "Pick a player"), x + 8, ty, U.C.dim, U.F.s)
        end
        U.textR(self, "v", x + w - 8, ty, U.C.mute, U.F.s)
        self.whoBtns[#self.whoBtns + 1] =
            { x = x, y = y, w = w, h = BH, act = "whoopen", id = id }
        return BH + (label and label ~= "" and (XH + 3) or 0)
    end

    -- ---- กำลังแก้อยู่  กล่องพิมพ์จริง + รายการ ------------------------------
    local box = self.fields and self.fields.whoFind
    if box then
        box:setX(x + 5); box:setY(y + 3)
        sizeBox(box, w - 10, BH - 6)
    end
    U.fill(self, x, y, w, BH, U.C.bgDark)
    U.border(self, x, y, w, BH, U.C.accent)

    local C2   = KRClient or {}
    local rows = C2.findRows or {}
    local typed = box and (box:getInternalText() or "") or ""

    -- คำตอบของคำค้นเก่าที่มาช้าต้องไม่ไปทับรายการของคำค้นใหม่
    -- เทียบแบบ "ขึ้นต้นด้วย" ไม่ใช่ "เท่ากันเป๊ะ" เพราะระหว่างพิมพ์ต่อ
    -- รายการของคำสั้นกว่ายังใช้ได้อยู่และดีกว่าการโชว์ว่างเปล่า
    local stale = (C2.findQ ~= nil) and
                  (typed:lower():sub(1, #tostring(C2.findQ)) ~= tostring(C2.findQ):lower())

    local rh = math.max(26, U.h(U.F.s) + 10)
    local shown = math.min(#rows, 6)
    local lh2 = (shown > 0 and shown * rh or rh)
    U.solid(self, x, y + BH, w, lh2, U.C.bgDark)
    U.border(self, x, y + BH, w, lh2, U.C.accent)

    if #rows == 0 then
        U.textC(self, stale and KR.L("กำลังค้น...", "searching...")
                             or KR.L("ไม่พบใครที่ตรง", "nobody matches"),
                x + w / 2, y + BH + math.floor((rh - U.h(U.F.xs)) / 2), U.C.dim, U.F.xs)
    else
        local ry = y + BH
        for i = 1, shown do
            local r = rows[i]
            local hot = U.hit({ x = x, y = ry, w = w, h = rh }, self.mx, self.my)
            if hot then U.fill(self, x, ry, w, rh, U.C.bgRow) end
            U.fill(self, x + 8, ry + math.floor(rh / 2) - 3, 6, 6,
                   r.online and U.C.good or U.C.off)
            U.text(self, KR.trunc(r.disp or r.key, 20), x + 20,
                   ry + math.floor((rh - U.h(U.F.s)) / 2), U.C.text, U.F.s)
            if not r.online then
                U.textR(self, KR.L("ออฟไลน์", "offline"), x + w - 8,
                        ry + math.floor((rh - U.h(U.F.xs)) / 2), U.C.dim, U.F.xs)
            end
            self.whoBtns[#self.whoBtns + 1] =
                { x = x, y = ry, w = w, h = rh, act = "whopick", id = id,
                  key = r.key, disp = r.disp }
            ry = ry + rh
        end
        if #rows > shown then
            U.textR(self, "+" .. (#rows - shown), x + w - 8, y + BH + lh2 - U.h(U.F.xs) - 2,
                    U.C.dim, U.F.xs)
        end
    end

    return BH + lh2 + (label and label ~= "" and (XH + 3) or 0)
end

-- คลิกที่เกี่ยวกับช่องเลือกชื่อ  ต้องถูกเรียก **ก่อน** ตัวจัดการคลิกของหน้า
-- ไม่งั้นรายการที่ลอยทับปุ่มอื่นอยู่จะปล่อยให้คลิกทะลุไปโดนปุ่มข้างหลัง
function KRShop:whoClick(x, y)
    for _, b in ipairs(self.whoBtns or {}) do
        if U.hit(b, x, y) then
            if b.act == "whoopen" then
                self.whoFor  = b.id
                self.whoLast = nil
                if self.fields and self.fields.whoFind then
                    self.fields.whoFind:setText("")
                    pcall(function() self.fields.whoFind:focus() end)
                end
                req(KR.CMD.FIND_PLAYER, { q = "" })
            elseif b.act == "whopick" then
                self:whoSet(b.id, b.key, b.disp)
                self.whoFor = nil
                if self.fields and self.fields.whoFind then
                    pcall(function() self.fields.whoFind:unfocus() end)
                    self.fields.whoFind:setVisible(false)
                end
            end
            return true
        end
    end

    -- คลิกที่อื่นทั้งจอ = ปิดรายการ  แต่ไม่กินคลิกนั้นทิ้ง
    -- (คืน false เพื่อให้คลิกเดินต่อไปหาปุ่มที่เขาตั้งใจกดจริง ๆ)
    if self.whoFor then
        self.whoFor = nil
        if self.fields and self.fields.whoFind then
            pcall(function() self.fields.whoFind:unfocus() end)
            self.fields.whoFind:setVisible(false)
        end
    end
    return false
end

-- ==============================================================================
-- ร้านแพ็ก HF Point  ฝั่งผู้เล่น
--
-- เปิดจากปุ่ม + ข้างเหรียญ HF บนแถบหัว  ซึ่งอยู่ทุกหน้า
-- วาดเป็นแผ่นทับทั้งหน้าต่างเหมือน drawPay ไม่ใช่หน้าต่างใหม่
-- (หน้าต่างที่ต้องเกาะหน้าต่างอื่นมีจุดพังเยอะกว่าที่ได้คืนมามาก
--  — บทเรียนที่จ่ายไปแล้วกับ KR_UI_Account.lua)
-- ==============================================================================
function KRShop:drawHfp(w, h)
    self.hfpBtns = {}
    if not self.hfpOpen then return end

    local d  = data()
    local hp = d.hfp or {}
    local packs = hp.packs or {}
    local ts = nowTs()

    U.fill(self, 0, 0, w, h, U.C.bgDark, 0.72)

    local pw = math.min(w - 40, 780)
    local ph = h - 40
    local px = math.floor((w - pw) / 2)
    local py = math.floor((h - ph) / 2)
    U.solid(self, px, py, pw, ph, U.C.bg)
    U.border(self, px, py, pw, ph, U.C.accent)

    -- ---- หัว ---------------------------------------------------------------
    local hh = U.h(U.F.l) + 18
    U.fill(self, px, py, pw, hh, U.C.bgHead)
    U.text(self, KR.L("เติม HF Point", "Top up HF Point"), px + 16,
           py + math.floor((hh - U.h(U.F.l)) / 2), U.C.text, U.F.l)
    U.text(self, KR.L("ยอดตอนนี้ ", "You have ") ..
                 math.floor(((d.bal or {}).hf) or 0) .. " HF",
           px + 20 + U.w(KR.L("เติม HF Point", "Top up HF Point"), U.F.l),
           py + math.floor((hh - U.h(U.F.xs)) / 2), U.C.mute, U.F.xs)
    self.bHfpClose = U.btn(self, px + pw - 40, py + 6, 32, hh - 12, "x", "neu", self.mx, self.my)

    local cx = px + 14
    local cw = pw - 28
    local cy = py + hh + 12

    -- ---- หกช่องปกติ  สามคอลัมน์ -------------------------------------------
    --
    -- ความสูงของการ์ดคิด **ย้อนจากที่ที่เหลือจริง** ไม่ใช่ตั้งเป็นตัวเลขแล้วหวังว่าพอ
    --
    -- ของที่ต้องมีในกล่องนี้เยอะกว่าที่คิด: หกการ์ด + แถบพิเศษสองแถบ + ตารางคำขอ
    -- + บรรทัดเตือนเรื่องเงินจริง  ถ้าตั้งความสูงการ์ดตายตัว พอผู้เล่นตั้ง UI scale 1.5
    -- ตัวหนังสือจะโตขึ้นแต่การ์ดไม่โต แล้วสองแถบล่างจะถูกดันตกขอบกล่องหายไปเลย
    -- ซึ่งเป็นบั๊กที่ผู้เล่นเห็นแต่บอกไม่ถูกว่าเห็นอะไร ("แพ็กใหญ่หายไปไหน")
    local COLS = 3
    local gap  = 10
    local cellW = math.floor((cw - gap * (COLS - 1)) / COLS)
    local lastW = cw - (cellW + gap) * (COLS - 1)

    local wideH = math.max(92, U.h(U.F.m) + U.h(U.F.xs) * 3 + 44)
    local reqH  = U.h(U.F.xs) * 2 + (U.h(U.F.s) + 8) * 3 + 10      -- ตารางคำขอ
    local noteH = U.h(U.F.xs) + 10                                  -- บรรทัดเงินจริง
    local rest  = (py + ph) - cy - (wideH * 2 + gap * 2) - reqH - noteH - 12

    -- การ์ดต้องสูงพอที่ตัวหนังสือจะอยู่ครบ **บวก** ที่ให้รูปพออ่านออก
    -- ขั้นต่ำคือ textH + 56 (รูปเล็กสุดที่ยังดูรู้เรื่อง)  ที่เกินจากนั้นยกให้รูปทั้งหมด
    local textH = U.h(U.F.m) * 2 + U.h(U.F.xs) + math.max(26, U.h(U.F.s) + 10) + 26
    local cellH = math.max(textH + 56, math.floor((rest - gap) / 2))
    cellH = math.min(cellH, textH + 130)

    for i = 1, 6 do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local bx  = cx + col * (cellW + gap)
        local bw2 = (col == COLS - 1) and lastW or cellW
        local by  = cy + row * (cellH + gap)
        self:drawHfpCard(bx, by, bw2, cellH, packs[i], i, ts)
    end
    cy = cy + (cellH + gap) * 2

    -- ---- ช่อง 7 จำกัดเวลา และช่อง 8 ชุดใหญ่  เต็มความกว้าง ------------------
    self:drawHfpWide(cx, cy, cw, wideH, packs[KR.HFPACK.LIMITED], KR.HFPACK.LIMITED, ts)
    cy = cy + wideH + gap
    self:drawHfpWide(cx, cy, cw, wideH, packs[KR.HFPACK.MEGA], KR.HFPACK.MEGA, ts)
    cy = cy + wideH + 12

    -- ---- คำขอของตัวเอง ------------------------------------------------------
    --
    -- จำเป็นไม่ใช่ตกแต่ง  ถ้ากดขอซื้อแล้วไม่มีอะไรบนจอเปลี่ยน คนจะกดซ้ำ
    -- แล้วแอดมินได้ใบซ้ำสิบใบจากคนเดียว (ฝั่งเซิร์ฟกันไว้อีกชั้นแล้ว แต่การกันด้วย
    -- ข้อความปฏิเสธคือการแก้ที่ปลายทาง  บอกสถานะให้เห็นคือการแก้ที่ต้นทาง)
    local mine = hp.mine or {}
    local rest = py + ph - 12 - cy
    if rest > U.h(U.F.xs) * 3 then
        U.text(self, KR.L("คำขอของคุณ", "YOUR REQUESTS"), cx, cy, U.C.dim, U.F.xs)
        cy = cy + U.h(U.F.xs) + 4

        if #mine == 0 then
            U.text(self, KR.L("ยังไม่ได้ส่งคำขอ  ·  กดขอซื้อที่แพ็กด้านบน",
                              "Nothing sent yet. Pick a pack above."),
                   cx, cy, U.C.mute, U.F.xs)
        else
            local rh = U.h(U.F.s) + 8
            for i = #mine, 1, -1 do
                if cy + rh > py + ph - 10 then break end
                local r = mine[i]
                local st, col = KR.L("รออนุมัติ", "waiting"), U.C.warn
                if r.st == KR.HFP_ST.DONE then st, col = KR.L("ส่งให้แล้ว", "sent"), U.C.good
                elseif r.st == KR.HFP_ST.DENY then st, col = KR.L("ถูกปฏิเสธ", "rejected"), U.C.bad
                elseif r.st == KR.HFP_ST.GONE then st, col = KR.L("ถอนแล้ว", "withdrawn"), U.C.mute end

                U.text(self, KR.trunc(r.name or "-", 28), cx, cy, U.C.lite, U.F.s)
                U.text(self, r.hf .. " HF", cx + math.floor(cw * 0.42), cy, U.C.hf, U.F.s)
                U.text(self, (r.thb or 0) .. KR.L(" บาท", " THB"),
                       cx + math.floor(cw * 0.58), cy, U.C.gold, U.F.s)
                U.text(self, st, cx + math.floor(cw * 0.74), cy, col, U.F.s)

                if r.st == KR.HFP_ST.WAIT then
                    local xb = U.btn(self, cx + cw - 76, cy - 2, 76, rh,
                                     KR.L("ยกเลิก", "Cancel"), "bad", self.mx, self.my)
                    xb.act, xb.id = "hfpcancel", r.id
                    self.hfpBtns[#self.hfpBtns + 1] = xb
                end
                cy = cy + rh
            end
        end
    end

    -- ---- ข้อความที่ห้ามไม่มี ------------------------------------------------
    U.text(self, KR.L("เงินจริงไม่ได้จ่ายผ่านเกม  โอนตามช่องทางที่เซิร์ฟประกาศ แล้วแอดมินจะกดส่ง HF ให้",
                      "No real money goes through the game. Transfer the way the server announced, " ..
                      "then an admin sends the HF."),
           px + 14, py + ph - U.h(U.F.xs) - 6, U.C.dim, U.F.xs)
end

-- การ์ดแพ็กปกติหนึ่งใบ
function KRShop:drawHfpCard(x, y, w, h, p, slot, ts)
    p = p or {}
    local set  = p.set and p.name ~= nil
    local open = p.open == true

    U.fill(self, x, y, w, h, set and U.C.bgCard or U.C.bgDark)
    U.border(self, x, y, w, h, set and U.C.line3 or U.C.line)

    -- ช่องที่แอดมินยังไม่ตั้ง  โชว์จาง ๆ ไม่ซ่อน (เจ้าของเซิร์ฟเลือกข้อ 4ก)
    -- เหตุผล: ผู้เล่นเห็นว่ามีที่ว่างอยู่จริง ไม่ได้คิดว่าม็อดโหลดมาไม่ครบ
    if not set then
        U.textC(self, KR.L("แอดมินยังไม่ตั้ง", "not set up yet"),
                x + w / 2, y + math.floor((h - U.h(U.F.xs)) / 2), U.C.dim, U.F.xs)
        return
    end

    -- ---- วางจากล่างขึ้นบน  รูปได้ที่ที่เหลือ ---------------------------------
    --
    -- ของเดิมคิดกลับกัน: ให้รูปกินสัดส่วน 0.46 ของใบก่อน แล้ววางตัวหนังสือไล่ลงมา
    -- แบบนั้นตำแหน่งล่างสุดของตัวหนังสือเป็น "ผลลัพธ์ที่ไม่มีใครคุม" แล้วแต่ว่า
    -- ใบสูงเท่าไรกับฟอนต์ใหญ่แค่ไหน  พอใบเตี้ยลง ราคาก็ไหลลงไปทับปุ่ม
    -- (เจ้าของเซิร์ฟถ่ายมา: บรรทัดโบนัสถูกปุ่ม Request ทับจนอ่านไม่ออก)
    --
    -- คิดจากล่างขึ้นบนแทน: ปุ่มอยู่ตรงไหนแน่นอน ราคาอยู่เหนือปุ่ม โบนัสเหนือราคา
    -- ยอด HF เหนือโบนัส  แล้ว "ที่ที่เหลือข้างบน" ทั้งหมดคือรูป
    -- ผลคือไม่มีทางทับกันได้เลยไม่ว่าฟอนต์หรือขนาดใบจะเป็นเท่าไร
    local MH, XH2 = U.h(U.F.m), U.h(U.F.xs)
    local bh2 = math.max(26, U.h(U.F.s) + 10)
    local by  = y + h - bh2 - 8

    local thbY   = by - 6 - MH
    local bonusY = thbY - 2 - XH2
    local amtY   = bonusY - 1 - MH
    local artH   = math.max(24, amtY - y - 10)
    local isz    = math.min(w - 20, artH)

    U.hfpIcon(self, p.icon, x + math.floor((w - isz) / 2),
              y + 6 + math.floor((artH - isz) / 2), isz,
              open and nil or U.dimC(U.C.text, 0.45))

    U.textC(self, tostring(p.total or p.hf or 0) .. " HF", x + w / 2, amtY,
            open and U.C.hf or U.C.mute, U.F.m)
    if (p.bonus or 0) > 0 then
        U.textC(self, "+" .. p.bonus .. KR.L(" โบนัส", " bonus"), x + w / 2, bonusY,
                open and U.C.good or U.C.dim, U.F.xs)
    end
    U.textC(self, (p.thb or 0) .. KR.L(" บาท", " THB"), x + w / 2, thbY,
            open and U.C.gold or U.C.dim, U.F.m)
    if open then
        local b = U.btn(self, x + 8, by, w - 16, bh2, KR.L("ขอซื้อ", "Request"), "pri",
                        self.mx, self.my)
        b.act, b.slot = "hfpreq", slot
        self.hfpBtns[#self.hfpBtns + 1] = b
    else
        U.fill(self, x + 8, by, w - 16, bh2, U.C.bgDark)
        U.textC(self, KR.L("ปิดอยู่", "closed"), x + w / 2,
                by + math.floor((bh2 - U.h(U.F.xs)) / 2), U.C.off, U.F.xs)
    end
end

-- การ์ดแพ็กพิเศษ  ช่อง 7 (จำกัดเวลา+จำนวน) และช่อง 8 (ชุดใหญ่ลดช่วง)
function KRShop:drawHfpWide(x, y, w, h, p, slot, ts)
    p = p or {}
    local set  = p.set and p.name ~= nil
    local open = p.open == true
    local lim  = (slot == KR.HFPACK.LIMITED)
    local edge = lim and U.C.warn or U.C.gold

    U.fill(self, x, y, w, h, set and U.C.bgCard or U.C.bgDark)
    U.border(self, x, y, w, h, set and edge or U.C.line)

    if not set then
        U.textC(self, lim and KR.L("ยังไม่มีแพ็กจำกัดเวลา", "no limited pack right now")
                           or KR.L("ยังไม่มีแพ็กชุดใหญ่", "no bundle right now"),
                x + w / 2, y + math.floor((h - U.h(U.F.xs)) / 2), U.C.dim, U.F.xs)
        return
    end

    local isz = math.min(h - 12, 78)
    U.hfpIcon(self, p.icon, x + 10, y + math.floor((h - isz) / 2), isz,
              open and nil or U.dimC(U.C.text, 0.45))

    local tx = x + 10 + isz + 14
    local cy = y + 10

    local tag = lim and KR.L("จำกัดเวลา", "LIMITED") or KR.L("ชุดใหญ่ ลดพิเศษ", "BUNDLE DEAL")
    local tw2 = U.w(tag, U.F.xs) + 10
    U.fill(self, tx, cy, tw2, U.h(U.F.xs) + 4, edge)
    U.textC(self, tag, tx + tw2 / 2, cy + 1, U.C.bgDark, U.F.xs)
    U.text(self, KR.trunc(p.name or "-", 34), tx + tw2 + 10, cy,
           open and U.C.text or U.C.mute, U.F.s)
    cy = cy + math.max(U.h(U.F.xs) + 4, U.h(U.F.s)) + 4

    -- บรรทัดสถานะ  ต่างกันคนละเรื่องระหว่างสองช่อง
    if lim then
        local parts = {}
        if p.left then parts[#parts + 1] = KR.L("เหลือเวลา ", "ends in ") .. KR.fmtDur(p.left) end
        if p.stock then
            parts[#parts + 1] = KR.L("เหลือ ", "left ") ..
                                math.max(0, p.stock - (p.sold or 0)) .. " / " .. p.stock
        end
        if p.per then parts[#parts + 1] = KR.L("คนละ ", "max ") .. p.per end
        U.text(self, #parts > 0 and table.concat(parts, "   ")
                                 or KR.L("ไม่จำกัด", "no limit"),
               tx, cy, U.C.mute, U.F.xs)

        -- แถบบอกว่าขายไปแล้วเท่าไร  ตัวเลขอย่างเดียวไม่สื่อว่า "ใกล้หมดแล้ว"
        if p.stock and p.stock > 0 then
            local frac = math.min(1, (p.sold or 0) / p.stock)
            local bw3 = math.min(200, math.floor(w * 0.28))
            local byy = cy + U.h(U.F.xs) + 4
            U.fill(self, tx, byy, bw3, 5, U.C.bgDark)
            U.fill(self, tx, byy, math.floor(bw3 * frac), 5, U.C.warn)
        end
    else
        local when = p.left and (KR.L("ลดอีก ", "deal ends in ") .. KR.fmtDur(p.left))
                             or KR.L("ราคาปกติ", "standard price")
        U.text(self, when, tx, cy, U.C.mute, U.F.xs)
    end

    -- ราคาชิดขวา
    local rx = x + w - 12
    local ry = y + 10
    U.textR(self, tostring(p.total or p.hf or 0) .. " HF", rx, ry,
            open and U.C.hf or U.C.mute, U.F.m)
    ry = ry + U.h(U.F.m) + 2
    if p.was then
        -- ราคาก่อนลดวางไว้ซ้ายของราคาจริง  ขีดฆ่าวาดเองเพราะฟอนต์ทำให้ไม่ได้
        local nowS = (p.thb or 0) .. KR.L(" บาท", " THB")
        local wasS = tostring(p.was)
        local nw = U.w(nowS, U.F.m)
        local ww = U.w(wasS, U.F.xs)
        U.textR(self, nowS, rx, ry, U.C.gold, U.F.m)
        U.textR(self, wasS, rx - nw - 8, ry + 3, U.C.dim, U.F.xs)
        U.fill(self, rx - nw - 8 - ww, ry + 3 + math.floor(U.h(U.F.xs) / 2), ww, 1, U.C.dim)
    else
        U.textR(self, (p.thb or 0) .. KR.L(" บาท", " THB"), rx, ry,
                open and U.C.gold or U.C.dim, U.F.m)
    end

    local bh2 = math.max(26, U.h(U.F.s) + 10)
    local bx2 = x + w - 110 - 12
    local by2 = y + h - bh2 - 8
    if open then
        local b = U.btn(self, bx2, by2, 110, bh2, KR.L("ขอซื้อ", "Request"), "pri", self.mx, self.my)
        b.act, b.slot = "hfpreq", slot
        self.hfpBtns[#self.hfpBtns + 1] = b
    else
        local why = KR.L("ปิดอยู่", "closed")
        if p.why == "sold"  then why = KR.L("ขายหมดแล้ว", "sold out") end
        if p.why == "ended" then why = KR.L("หมดเวลาแล้ว", "ended") end
        U.fill(self, bx2, by2, 110, bh2, U.C.bgDark)
        U.textC(self, why, bx2 + 55, by2 + math.floor((bh2 - U.h(U.F.xs)) / 2), U.C.off, U.F.xs)
    end
end

function KRShop:hfpClick(x, y)
    if not self.hfpOpen then return false end

    if U.hit(self.bHfpClose, x, y) then self.hfpOpen = false; return true end
    for _, b in ipairs(self.hfpBtns or {}) do
        if U.hit(b, x, y) then
            if b.act == "hfpreq" then
                req(KR.CMD.HFP_REQ, { slot = b.slot })
            elseif b.act == "hfpcancel" then
                req(KR.CMD.HFP_CANCEL, { id = b.id })
            end
            return true
        end
    end
    -- แผ่นทับกินคลิกทั้งหมด  ห้ามทะลุไปโดนของข้างหลัง (กฎเดียวกับ drawPay)
    return true
end

-- ---- แท็บ : แพ็ก HF ------------------------------------------------------------
--
-- สามงานคนละเรื่องกันอยู่ในแท็บเดียว จึงแบ่งเป็นแท็บย่อยอีกชั้น
--   คำขอ     งานประจำวัน  แอดมินเปิดมาดูว่ามีใครรออยู่
--   ตั้งแพ็ก  งานที่ทำเดือนละครั้ง  ตั้งราคาแล้วก็ปล่อยไว้
-- ถ้ายัดรวมหน้าเดียว งานที่ทำทุกวันจะถูกฟอร์มที่แทบไม่ได้แตะดันตกลงไปข้างล่าง
KRShop.HTABS = {
    { id = "req",   th = "คำขอ",    en = "Requests" },
    { id = "packs", th = "ตั้งแพ็ก", en = "Packs"    },
}

function KRShop:admHfp(x, y, w, h)
    local a  = self.adm
    local d  = data()
    local hp = d.hfp or {}
    a.hfpTab = a.hfpTab or "req"
    a.hfpSlot = a.hfpSlot or 1

    local pend = hp.pend or {}

    -- แท็บย่อย  ตัวเลขบนแท็บคำขอคือจำนวนที่รออยู่จริง
    local tx = x
    for i = 1, #KRShop.HTABS do
        local t = KRShop.HTABS[i]
        local lbl = KR.L(t.th, t.en)
        if t.id == "req" and #pend > 0 then lbl = lbl .. "  " .. #pend end
        local tw2 = U.w(lbl, U.F.s) + 24
        local b = tag(self, tx, y, tw2, lbl, a.hfpTab == t.id, self.mx, self.my)
        b.act, b.htab = "htab", t.id
        self.admBtns[#self.admBtns + 1] = b
        tx = tx + tw2 + 4
    end

    local ty = y + tagH() + 10
    local th3 = h - (ty - y)

    if a.hfpTab == "packs" then
        self:admHfpPacks(x, ty, w, th3)
    else
        self:admHfpReq(x, ty, w, th3, pend)
    end
end

-- ---- แท็บย่อย : คำขอ ------------------------------------------------------------
function KRShop:admHfpReq(x, y, w, h, pend)
    local a  = self.adm
    local hp = data().hfp or {}

    -- เลือกคำขอที่ยังมีอยู่จริงเสมอ
    -- คำขอที่ถูกแอดมินคนอื่นกดไปแล้วจะหายจากลิสต์ระหว่างที่เราเปิดหน้าค้างอยู่
    -- ถ้าไม่เช็ก แถบล่างจะยังโชว์รายละเอียดของใบที่ไม่มีอยู่แล้ว แล้วกดอนุมัติไม่ติด
    local sel
    for _, r in ipairs(pend) do
        if r.id == a.hfpReq then sel = r; break end
    end
    if not sel then sel = pend[1]; a.hfpReq = sel and sel.id or nil end

    -- ---- แถบล่าง : ส่งให้เลย  จองที่ก่อน ------------------------------------
    local BH   = boxH()
    local XH   = U.h(U.F.xs)
    local sendH = XH + 3 + BH + 12
    local detH  = (sel and (XH + 3 + BH + 14) or 0)
    local listH = math.max(60, h - sendH - detH - 8)

    -- ---- ลิสต์คำขอ ----------------------------------------------------------
    if #pend == 0 then
        U.emptyState(self, x, y, w, listH,
                     KR.L("ไม่มีคำขอค้างอยู่", "No requests waiting"),
                     KR.L("ผู้เล่นกดขอซื้อจากปุ่ม + ข้างยอด HF บนหัวจอ",
                          "Players ask from the + next to their HF balance"))
    else
        local rh = math.max(30, U.h(U.F.s) + 14)
        U.fill(self, x, y, w, listH, U.C.bgHead)
        self:setStencilRect(x, y, w, listH)
        local cy = y - (self.scroll or 0)
        for i = 1, #pend do
            local r = pend[i]
            if cy + rh > y and cy < y + listH then
                local on  = (r.id == a.hfpReq)
                local hot = U.hit({ x = x, y = cy, w = w, h = rh }, self.mx, self.my)
                if on then U.fill(self, x, cy, w, rh, U.C.bgSel)
                elseif hot then U.fill(self, x, cy, w, rh, U.C.bgRow) end
                if on then U.fill(self, x, cy, 2, rh, U.C.accent) end

                local ty2 = cy + math.floor((rh - U.h(U.F.s)) / 2)
                U.fill(self, x + 10, cy + math.floor(rh / 2) - 3, 6, 6,
                       r.online and U.C.good or U.C.off)
                U.text(self, KR.trunc(r.who or r.k, 18), x + 24, ty2, U.C.text, U.F.s)
                U.text(self, KR.trunc(r.name or "-", 26), x + math.floor(w * 0.28), ty2,
                       U.C.lite, U.F.s)
                U.text(self, (r.hf or 0) .. " HF", x + math.floor(w * 0.60), ty2, U.C.hf, U.F.s)
                U.textR(self, (r.thb or 0) .. KR.L(" บาท", " THB"),
                        x + w - 12, ty2, U.C.gold, U.F.s)

                self.admBtns[#self.admBtns + 1] =
                    { x = x, y = cy, w = w, h = rh, act = "hfppick", id = r.id }
            end
            cy = cy + rh
        end
        self:clearStencilRect()
        U.scrollbar(self, x + w - 3, y, listH, #pend * rh, listH, self.scroll or 0)
    end

    local cy = y + listH + 8

    -- ---- แถบรายละเอียดของใบที่เลือก -----------------------------------------
    if sel then
        U.text(self, KR.L("อ้างอิงการโอน  ·  เก็บไว้ในประวัติ",
                          "PAYMENT REFERENCE  ·  goes in the log"), x, cy, U.C.dim, U.F.xs)
        local ry = cy + XH + 3

        local okW  = math.max(140, U.w(KR.L("อนุมัติ + ส่ง", "Approve + send"), U.F.s) + 30)
        local noW  = math.max(100, U.w(KR.L("ปฏิเสธ", "Reject"), U.F.s) + 30)
        local noteW = math.max(120, w - okW - noW - 20)

        U.fill(self, x, ry, noteW, BH, U.C.bgDark)
        U.border(self, x, ry, noteW, BH, U.C.line3)
        if self.fields.hfpNote then
            self.fields.hfpNote:setX(x + 5); self.fields.hfpNote:setY(ry + 3)
            sizeBox(self.fields.hfpNote, noteW - 10, BH - 6)
        end

        local ob = U.btn(self, x + noteW + 10, ry, okW, BH,
                         KR.L("อนุมัติ + ส่ง", "Approve + send"), "ok", self.mx, self.my)
        ob.act, ob.id = "hfpok", sel.id
        self.admBtns[#self.admBtns + 1] = ob

        local nb = U.btn(self, x + noteW + okW + 20, ry, noW, BH,
                         KR.L("ปฏิเสธ", "Reject"), "bad", self.mx, self.my)
        nb.act, nb.id = "hfpno", sel.id
        self.admBtns[#self.admBtns + 1] = nb

        cy = ry + BH + 14
    end

    -- ---- ส่งให้เลย  ไม่ต้องมีคำขอ -------------------------------------------
    --
    -- ใช้จริงบ่อยกว่าที่คิด: ชดเชยของหาย แจกรางวัลกิจกรรม คนที่ทักมาทางไลน์
    -- และเคสที่แอดมินคุยจบนอกเกมแล้วไม่อยากให้ผู้เล่นต้องมากดขอซ้ำ
    U.text(self, KR.L("ส่งให้เลย  ·  ไม่ต้องมีคำขอ", "SEND DIRECTLY  ·  no request needed"),
           x, cy, U.C.dim, U.F.xs)
    cy = cy + XH + 3

    local whoW = math.max(160, math.floor(w * 0.24))
    local amtW = math.max(90,  math.floor(w * 0.13))
    local btnW = math.max(110, U.w(KR.L("ส่งเลย", "Send"), U.F.s) + 34)
    local whyW = math.max(120, w - whoW - amtW - btnW - 30)

    -- ช่องเลือกชื่อวาดทีหลังสุดของแถวไม่ได้  รายการของมันต้องทับปุ่มที่อยู่ขวามือ
    -- แต่ตัวมันต้องถูก "วาด" ก่อนเพื่อจองพิกัด  จึงเรียกตรงนี้แล้วปุ่มค่อยวาดทับตำแหน่งเดิม
    self:whoField("hfpTo", x, cy, whoW, nil)

    U.fill(self, x + whoW + 10, cy, amtW, BH, U.C.bgDark)
    U.border(self, x + whoW + 10, cy, amtW, BH, U.C.line3)
    if self.fields.hfpAmt then
        self.fields.hfpAmt:setX(x + whoW + 15); self.fields.hfpAmt:setY(cy + 3)
        sizeBox(self.fields.hfpAmt, amtW - 10, BH - 6)
    end
    U.textR(self, "HF", x + whoW + 10 + amtW - 4, cy + math.floor((BH - U.h(U.F.xs)) / 2),
            U.C.dim, U.F.xs)

    U.fill(self, x + whoW + amtW + 20, cy, whyW, BH, U.C.bgDark)
    U.border(self, x + whoW + amtW + 20, cy, whyW, BH, U.C.line3)
    if self.fields.hfpWhy then
        self.fields.hfpWhy:setX(x + whoW + amtW + 25); self.fields.hfpWhy:setY(cy + 3)
        sizeBox(self.fields.hfpWhy, whyW - 10, BH - 6)
    end

    local sb = U.btn(self, x + whoW + amtW + whyW + 30, cy, btnW, BH,
                     KR.L("ส่งเลย", "Send"), "pri", self.mx, self.my)
    sb.act = "hfpsend"
    self.admBtns[#self.admBtns + 1] = sb

    U.text(self, KR.L("ใส่จำนวน HF เอง หรือเลือกช่องแพ็กจากแท็บ ตั้งแพ็ก แล้วกด ส่งแพ็กนี้ให้",
                      "Type an HF amount, or use Send this pack in the Packs tab"),
           x, cy + BH + 4, U.C.dim, U.F.xs)
end

-- ---- แท็บย่อย : ตั้งแพ็ก ---------------------------------------------------------
function KRShop:admHfpPacks(x, y, w, h)
    local a  = self.adm
    local hp = data().hfp or {}
    local packs = hp.packs or {}
    local slot = math.max(1, math.min(KR.HFPACK.SLOTS, math.floor(a.hfpSlot or 1)))
    local kind = KR.hfpKind(slot)

    local lw = math.max(180, math.floor(w * 0.32))
    local rx = x + lw + 12
    local rw = w - lw - 12

    -- ---- ซ้าย : แปดช่อง -----------------------------------------------------
    local rh = math.max(30, U.h(U.F.s) + 14)
    U.fill(self, x, y, lw, h, U.C.bgHead)
    local cy = y
    for i = 1, KR.HFPACK.SLOTS do
        local p   = packs[i] or {}
        local on  = (i == slot)
        local hot = U.hit({ x = x, y = cy, w = lw, h = rh }, self.mx, self.my)
        if on then U.fill(self, x, cy, lw, rh, U.C.bgSel)
        elseif hot then U.fill(self, x, cy, lw, rh, U.C.bgRow) end
        if on then U.fill(self, x, cy, 2, rh, U.C.accent) end

        local ty2 = cy + math.floor((rh - U.h(U.F.s)) / 2)
        local numC = U.C.dim
        if i == KR.HFPACK.LIMITED then numC = U.C.warn end
        if i == KR.HFPACK.MEGA    then numC = U.C.gold end
        U.text(self, tostring(i), x + 10, ty2, numC, U.F.s)

        if p.set then
            U.text(self, KR.trunc(p.name or "-", 16), x + 30, ty2, U.C.text, U.F.s)
            U.textR(self, tostring(p.thbFull or p.thb or 0), x + lw - 10, ty2, U.C.gold, U.F.s)
            if p.off then
                U.fill(self, x + lw - 6, cy + 4, 4, rh - 8, U.C.bad)
            end
        else
            U.text(self, KR.L("ว่าง", "empty"), x + 30, ty2, U.C.dim, U.F.s)
        end

        self.admBtns[#self.admBtns + 1] =
            { x = x, y = cy, w = lw, h = rh, act = "hfpslot", slot = i }
        cy = cy + rh
    end

    -- คำอธิบายว่าช่อง 7/8 ต่างจากช่องอื่นยังไง  วางใต้ลิสต์ ไม่ใช่ในฟอร์ม
    -- ในฟอร์มมันจะกลายเป็นคำอธิบายที่อ่านซ้ำทุกครั้งที่แก้ค่า
    if cy + U.h(U.F.xs) * 3 < y + h then
        cy = cy + 8
        U.text(self, KR.L("ช่อง 7 = จำกัดเวลา + จำนวน", "7 = time and stock limited"),
               x + 8, cy, U.C.warn, U.F.xs)
        cy = cy + U.h(U.F.xs) + 2
        U.text(self, KR.L("ช่อง 8 = ชุดใหญ่ ลดเฉพาะช่วง", "8 = bundle, discounted for a while"),
               x + 8, cy, U.C.gold, U.F.xs)
    end

    -- ---- ขวา : ฟอร์ม --------------------------------------------------------
    local p = packs[slot] or {}
    U.fill(self, rx, y, rw, h, U.C.bgHead)

    local cx  = rx + 14
    local cw  = rw - 28
    local BH  = boxH()
    local XH  = U.h(U.F.xs)
    local TH  = tagH()
    local GAP = 10
    local fy  = y + 12

    local head = KR.L("กำลังแก้ช่อง ", "Editing slot ") .. slot
    if kind == "limited" then head = head .. KR.L("  ·  จำกัดเวลาและจำนวน", "  ·  limited")
    elseif kind == "mega" then head = head .. KR.L("  ·  ชุดใหญ่ลดช่วง", "  ·  bundle deal") end
    U.text(self, head, cx, fy, kind == "normal" and U.C.text or U.C.gold, U.F.m)
    fy = fy + U.h(U.F.m) + GAP

    -- แถว 1 : ชื่อ / HF / โบนัส
    local third = math.floor((cw - GAP * 2) / 3)
    fieldBox(self, self.fields.hfpName, cx, fy, third, KR.L("ชื่อ", "NAME"))
    fieldBox(self, self.fields.hfpHf, cx + third + GAP, fy, third, "HF")
    fieldBox(self, self.fields.hfpBonus, cx + (third + GAP) * 2, fy, third,
             KR.L("โบนัส", "BONUS"))
    fy = fy + XH + 3 + BH + GAP

    -- แถว 2 : ราคา / ไอคอน / เปิด-ปิด
    fieldBox(self, self.fields.hfpThb, cx, fy, third, KR.L("ราคา (บาท)", "PRICE (THB)"))

    -- ---- รูปแพ็ก ------------------------------------------------------------
    --
    -- ของเดิมเป็นแถวไอคอนจิ๋วหกอันเรียงกัน  ใช้ได้ตอนที่มันเป็นรูปวาดด้วยกล่องสี
    -- พอเป็นอาร์ตจริงแล้วรูป 28px แยกไม่ออกเลยว่าอันไหนคืออันไหน
    -- จึงเหลือแค่ "รูปที่เลือกอยู่" ขนาดใหญ่พอดู แล้วให้ตัวเลือกทั้งเก้าเป็นแผงลอย
    -- ที่เปิดทับฟอร์มตอนกด  ตาราง 3x3 เหมือนรูปต้นฉบับที่เจ้าของเซิร์ฟส่งมาเป๊ะ
    U.text(self, KR.L("รูปแพ็ก", "ARTWORK"), cx + third + GAP, fy, U.C.dim, U.F.xs)
    local ix = cx + third + GAP
    local iy = fy + XH + 3
    local isz = math.max(BH, TH)
    local cur = a.hfpIcon or p.icon or KR.HFP_ICON_DEFAULT

    U.fill(self, ix, iy, isz, isz, U.C.slot)
    U.hfpIcon(self, cur, ix + 1, iy + 1, isz - 2, nil)
    U.border(self, ix, iy, isz, isz, U.C.line3)

    local pickW = third - isz - 6
    local pb2 = tag(self, ix + isz + 6, iy, pickW,
                    KR.L("เปลี่ยนรูป", "Change") .. "  v",
                    self.hfpIconOpen == true, self.mx, self.my)
    pb2.act = "hfpiconmenu"
    pb2.menuX, pb2.menuY = ix, iy + isz + 2
    self.admBtns[#self.admBtns + 1] = pb2

    U.text(self, KR.L("ขายอยู่", "ON SALE"), cx + (third + GAP) * 2, fy, U.C.dim, U.F.xs)
    local vb = tag(self, cx + (third + GAP) * 2, fy + XH + 3, third,
                   a.hfpOff and KR.L("ปิดอยู่", "Closed") or KR.L("ผู้เล่นเห็น", "Open"),
                   not a.hfpOff, self.mx, self.my)
    vb.act = "hfpoff"
    self.admBtns[#self.admBtns + 1] = vb
    fy = fy + XH + 3 + math.max(BH, TH) + GAP

    -- แถว 3 : เฉพาะช่องพิเศษ
    if kind == "limited" then
        fieldBox(self, self.fields.hfpMins, cx, fy, third, KR.L("เปิดขายนาน (นาที)", "OPEN FOR (MIN)"))
        fieldBox(self, self.fields.hfpStock, cx + third + GAP, fy, third,
                 KR.L("จำกัดกี่ชุด  0 = ไม่จำกัด", "STOCK  0 = unlimited"))
        fieldBox(self, self.fields.hfpPer, cx + (third + GAP) * 2, fy, third,
                 KR.L("คนละไม่เกิน  0 = ไม่จำกัด", "PER PLAYER  0 = unlimited"))

        -- บรรทัดแปลงนาทีเป็นวัน  คนกรอก 4320 ต้องเห็นทันทีว่ามันคือสามวัน
        local mv = self.fields.hfpMins and tonumber(self.fields.hfpMins:getInternalText() or "")
        local hint = KR.minsHint(mv)
        if hint then
            U.text(self, "= " .. hint, cx, fy + XH + 3 + BH + 2, U.C.mute, U.F.xs)
        end
        if p.sold and (tonumber(p.sold) or 0) > 0 then
            U.textR(self, KR.L("ขายไปแล้ว ", "sold so far ") .. p.sold,
                    cx + cw, fy + XH + 3 + BH + 2, U.C.warn, U.F.xs)
        end
        fy = fy + XH + 3 + BH + U.h(U.F.xs) + GAP

    elseif kind == "mega" then
        fieldBox(self, self.fields.hfpCut, cx, fy, third,
                 KR.L("ราคาช่วงลด (บาท)", "DEAL PRICE (THB)"))
        fieldBox(self, self.fields.hfpCutMins, cx + third + GAP, fy, third,
                 KR.L("ลดนาน (นาที)", "DEAL LASTS (MIN)"))
        U.text(self, KR.L("ช่องราคาด้านบนคือราคาเต็ม  ช่องนี้คือราคาช่วงลด",
                          "The price above is the full price. This is the deal price."),
               cx + (third + GAP) * 2, fy + XH + 6, U.C.dim, U.F.xs)

        local mv = self.fields.hfpCutMins and tonumber(self.fields.hfpCutMins:getInternalText() or "")
        local hint = KR.minsHint(mv)
        if hint then
            U.text(self, "= " .. hint, cx + third + GAP, fy + XH + 3 + BH + 2, U.C.mute, U.F.xs)
        end
        fy = fy + XH + 3 + BH + U.h(U.F.xs) + GAP
    end

    -- ---- ปุ่มล่าง  ยึดจากขอบล่าง ไม่ใช่จาก fy --------------------------------
    local by = y + h - 44
    local bw2 = math.max(110, math.floor((cw - 20) / 3))

    local db = U.btn(self, cx, by, bw2, 32, KR.L("ล้างช่องนี้", "Clear slot"), "bad",
                     self.mx, self.my)
    db.act = "hfpclear"
    self.admBtns[#self.admBtns + 1] = db

    if p.set then
        local gb = U.btn(self, cx + bw2 + 10, by, bw2, 32,
                         KR.L("ส่งแพ็กนี้ให้", "Send this pack"), "neu", self.mx, self.my)
        gb.act = "hfpgive"
        self.admBtns[#self.admBtns + 1] = gb
    end

    local sb = U.btn(self, cx + cw - bw2, by, bw2, 32, KR.L("บันทึก", "Save"), "pri",
                     self.mx, self.my)
    sb.act = "hfpsave"
    self.admBtns[#self.admBtns + 1] = sb

    -- ช่องเลือกคนสำหรับปุ่ม "ส่งแพ็กนี้ให้"  วางเหนือปุ่ม
    if p.set then
        self:whoField("hfpTo", cx, by - boxH() - 8, math.floor(cw * 0.5), nil)
    end

    -- ---- แผงเลือกรูป  วาดท้ายสุดเพื่อให้ทับทุกอย่างในฟอร์ม -------------------
    if self.hfpIconOpen then
        local COLS = 3
        local cell = math.min(76, math.floor((cw - 8 * (COLS + 1)) / COLS))
        local gapI = 8
        local panW = COLS * cell + gapI * (COLS + 1)
        local rowsI = math.ceil(#KR.HFP_ICON / COLS)
        local panH = rowsI * (cell + U.h(U.F.xs) + 6) + gapI

        local panX = self.hfpIconX or cx
        local panY = self.hfpIconY or (y + 60)
        -- ไม่ให้แผงตกขอบล่างของหน้าจัดการ  ถ้าตกก็ดันขึ้นไปเปิดด้านบนแทน
        if panY + panH > y + h then panY = math.max(y + 4, y + h - panH - 4) end
        if panX + panW > rx + rw then panX = math.max(rx + 4, rx + rw - panW - 4) end

        U.solid(self, panX, panY, panW, panH, U.C.bgDark)
        U.border(self, panX, panY, panW, panH, U.C.accent)

        for i, ic in ipairs(KR.HFP_ICON) do
            local col2 = (i - 1) % COLS
            local row2 = math.floor((i - 1) / COLS)
            local bx2  = panX + gapI + col2 * (cell + gapI)
            local by2  = panY + gapI + row2 * (cell + U.h(U.F.xs) + 6)
            local on   = (cur == ic.id)
            local hot  = U.hit({ x = bx2, y = by2, w = cell, h = cell }, self.mx, self.my)

            U.fill(self, bx2, by2, cell, cell, U.C.slot)
            U.hfpIcon(self, ic.id, bx2 + 1, by2 + 1, cell - 2, nil)
            U.border(self, bx2, by2, cell, cell,
                     on and U.C.accent or (hot and U.C.lite or U.C.line3))
            if on then
                U.fill(self, bx2, by2 + cell - 3, cell, 3, U.C.accent)
            end
            U.textC(self, KR.L(ic.th, ic.en), bx2 + cell / 2, by2 + cell + 2,
                    on and U.C.text or U.C.dim, U.F.xs)

            self.admBtns[#self.admBtns + 1] =
                { x = bx2, y = by2, w = cell, h = cell + U.h(U.F.xs) + 2,
                  act = "hfpicon", val = ic.id }
        end
    end
end

-- โหลดค่าของช่องหนึ่งเข้าฟอร์ม  เรียกตอนสลับช่อง
function KRShop:hfpLoad(slot)
    local a = self.adm
    local packs = (data().hfp or {}).packs or {}
    local p = packs[slot] or {}
    a.hfpSlot = slot
    a.hfpIcon = p.icon or KR.HFP_ICON_DEFAULT
    a.hfpOff  = p.off and true or false

    local function set(k, v)
        if self.fields[k] then self.fields[k]:setText(v == nil and "" or tostring(v)) end
    end
    set("hfpName",  p.name)
    set("hfpHf",    p.hf)
    set("hfpBonus", p.bonus and p.bonus > 0 and p.bonus or nil)
    set("hfpThb",   p.thbFull or p.thb)
    set("hfpCut",   p.thbCut)
    set("hfpMins",  p.rawMins)
    set("hfpCutMins", p.rawCut)
    set("hfpStock", p.stock)
    set("hfpPer",   p.per)
end


-- ==============================================================================
-- ป้ายบิล  กลางจอ
--
-- เจ้าของเซิร์ฟสั่งไว้ว่าต้องเป็น "pop up กลางจอ" ไม่ใช่ป้ายเล็ก ๆ มุมจอ  ซึ่งถูก:
-- นี่คือเงินที่ถูกหักออกจากบัญชีเขาไปแล้วโดยที่เขาอาจไม่ได้อยู่ตรงนั้นด้วยซ้ำ
-- ป้ายที่เลื่อนหายเองใน 5 วินาทีไม่เหมาะกับข่าวแบบนี้  อันนี้ต้องกดรับทราบ
--
-- คิวถูกส่งมาจากเซิร์ฟครั้งเดียวแล้วล้าง  ฝั่งจอจึงเก็บต่อและโชว์ทีละใบ
-- ==============================================================================
function KRShop:drawBillPop(w, h)
    self.bBillOk = nil
    local q = (KRClient or {}).billQueue
    self.billPop = q and q[1] or nil
    local n = self.billPop
    if not n then return end

    U.fill(self, 0, 0, w, h, U.C.bgDark, 0.78)

    local okPay = (n.ok == true)
    local edge  = okPay and U.C.good or U.C.bad
    local XH, SH, MH = U.h(U.F.xs), U.h(U.F.s), U.h(U.F.m)
    local btnH = math.max(32, SH + 16)

    local pw = math.min(w - 60, 460)
    local ph = MH + 10 + SH * 4 + 18 + btnH + 34
    local px = math.floor((w - pw) / 2)
    local py = math.floor((h - ph) / 2)

    U.solid(self, px, py, pw, ph, U.C.bg)
    U.border(self, px, py, pw, ph, edge)
    U.fill(self, px, py, pw, 4, edge)

    local cy = py + 14
    U.text(self, okPay and KR.L("คุณได้ชำระบิลแล้ว", "Bill paid")
                        or KR.L("เงินไม่พอชำระบิล", "Not enough money"),
           px + 16, cy, edge, U.F.m)
    cy = cy + MH + 10

    local what = (n.kind == "land") and KR.L("บิลเซฟเฮาส์", "Safehouse bill")
                                     or KR.L("ภาษีส่วนตัว", "Personal tax")
    local function line(cap, val, col)
        U.text(self, cap, px + 16, cy, U.C.dim, U.F.s)
        U.textR(self, val, px + pw - 16, cy, col or U.C.text, U.F.s)
        cy = cy + SH + 4
    end

    line(KR.L("รายการ", "For"), what)
    if n.what then line(KR.L("เลขที่บิล", "Bill no."), tostring(n.what), U.C.lite) end
    line(KR.L("จำนวนเงิน", "Amount"), tostring(n.n or 0) .. KR.L(" บาท", ""),
         okPay and U.C.cash or U.C.bad)

    if okPay then
        line(KR.L("ยอดคงเหลือในบัญชี", "Left in your account"), money(n.left or 0), U.C.cash)
    else
        cy = cy + 4
        U.text(self, KR.L("ระบบปิดการหักอัตโนมัติของรายการนี้ให้แล้ว",
                          "Auto pay has been switched off for this one."),
               px + 16, cy, U.C.warn, U.F.xs)
        cy = cy + XH + 2
        U.text(self, KR.L("เติมเงินแล้วเปิดใหม่ได้ที่หน้า Account",
                          "Top up, then turn it back on from the Account page."),
               px + 16, cy, U.C.dim, U.F.xs)
        cy = cy + XH + 4
    end

    self.bBillOk = U.btn(self, px + pw - 130 - 16, py + ph - btnH - 14, 130, btnH,
                         KR.L("รับทราบ", "Got it"), okPay and "ok" or "pri",
                         self.mx, self.my)

    -- มีอีกกี่ใบรอ  คนที่ออฟไลน์ไปสามวันจะเจอหลายใบซ้อนกัน ต้องรู้ว่าเหลืออีกเท่าไร
    if #q > 1 then
        U.text(self, KR.L("อีก ", "") .. (#q - 1) .. KR.L(" รายการ", " more"),
               px + 16, py + ph - btnH - 14 + math.floor((btnH - XH) / 2), U.C.dim, U.F.xs)
    end
end


-- 0.6.10 — drawBillList() ถูกถอดออกทั้งฟังก์ชัน
-- เรื่องบิลมีหน้าจอเดียวแล้วคือหน้าต่างของม็อดภาษี  ดูเหตุผลที่ปุ่ม "billopen"
-- ร้านเหลือหน้าที่เดียวคือสวิตช์หักอัตโนมัติ ซึ่งเป็นกติกาของร้านจริง ๆ

-- ==============================================================================
-- ==============================================================================
-- 0.7.0 — กระดานราคาสินค้าโลก
--
-- **หน้านี้ดูอย่างเดียว** ไม่มีปุ่มซื้อ ไม่มีทางไปถึง S.buy() และมีด่านยืนยันข้อนั้น
-- มันคือกระดาษราคาอ้างอิงสำหรับคนที่ซื้อขายกันเอง ไม่ใช่แคตตาล็อกร้าน
--
-- เรียกดูได้สองทางตามที่เจ้าของเซิร์ฟสั่ง: ตามหมวด และตามตัวอักษร
-- สองทางนี้ตอบคำถามคนละข้อ ("ของประเภทนี้ราคาเท่าไร" กับ "ของชิ้นนี้ราคาเท่าไร")
-- จึงต้องมีทั้งคู่ ไม่ใช่เลือกอันที่ดูดีกว่า
-- ==============================================================================
local AZ = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
             "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "#" }

-- ตัวอักษรแรกของชื่อ  ชื่อที่ไม่ได้เริ่มด้วย A-Z ไปกอง "#"
-- (ชื่อไทยทั้งหมดจะไปอยู่ที่นั่น ซึ่งถูกแล้ว - เรียงไทยตามตัวอักษรต้องใช้ตารางเทียบ
--  ที่ Kahlua ไม่มี และการเดาลำดับผิดแย่กว่าการกองไว้ที่เดียวอย่างซื่อสัตย์)
local function azOf(name)
    local c = tostring(name or ""):sub(1, 1):upper()
    if c >= "A" and c <= "Z" then return c end
    return "#"
end

function KRShop:boardRows()
    local b = data().board or {}
    local all = b.list or {}
    local q = tostring(self.search and self.search:getInternalText() or "")
    q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")

    local out = {}
    for i = 1, #all do
        local r = all[i]
        local keep = true
        if self.boardCat and self.boardCat ~= "" and r.cat ~= self.boardCat then keep = false end
        if keep and self.boardAZ and azOf(r.name) ~= self.boardAZ then keep = false end
        if keep and q ~= "" then
            local hay = (tostring(r.name) .. " " .. tostring(r.cat or "") .. " " ..
                         tostring(r.note or "")):lower()
            if not hay:find(q, 1, true) then keep = false end
        end
        if keep then out[#out + 1] = r end
    end
    table.sort(out, function(x, y)
        if x.cat ~= y.cat then return tostring(x.cat) < tostring(y.cat) end
        return tostring(x.name) < tostring(y.name)
    end)
    return out, #all
end

function KRShop:drawBoard(x, y, w, h)
    local XH2 = U.h(U.F.xs)
    local SH3 = U.h(U.F.s)
    self.boardBtns = {}

    local b    = data().board or {}
    local cats = b.cats or {}
    local cy   = y

    -- ---- ป้ายบอกว่านี่คืออะไร --------------------------------------------------
    -- สองบรรทัดนี้คือสิ่งที่กันไม่ให้ทั้งหน้าถูกอ่านผิด  ห้ามย้ายไปคู่มือ
    U.text(self, KR.L("ราคาอ้างอิงของโลก", "Reference prices"), x, cy, U.C.text, U.F.m)
    cy = cy + U.h(U.F.m) + 2
    for _, ln in ipairs(U.wrap(
            KR.L("ราคาที่แอดมินจดไว้ให้คนซื้อขายกันเอง  ร้านไม่ได้ขายของพวกนี้",
                 "Prices an admin wrote down so players can trade with each other. " ..
                 "The shop does not sell these."),
            U.F.xs, w, 2)) do
        U.text(self, ln, x, cy, U.C.mute, U.F.xs)
        cy = cy + XH2
    end
    cy = cy + 6

    -- ---- ชิปหมวด ---------------------------------------------------------------
    local chH = math.max(24, XH2 + 10)
    local function chip(cx, label, on, act, val)
        local tw = U.w(label, U.F.xs) + 18
        U.fill(self, cx, cy, tw, chH, on and U.C.accent2 or U.C.bgCard)
        if on then U.fill(self, cx, cy + chH - 2, tw, 2, U.C.accent) end
        U.text(self, label, cx + 9, cy + math.floor((chH - XH2) / 2),
               on and U.C.text or U.C.mute, U.F.xs)
        self.boardBtns[#self.boardBtns + 1] =
            { x = cx, y = cy, w = tw, h = chH, act = act, val = val }
        return cx + tw + 5
    end

    local cx = x
    cx = chip(cx, KR.L("ทั้งหมด", "ALL"), self.boardCat == nil, "cat", nil)
    for i = 1, #cats do
        local label = tostring(cats[i]):upper()
        if cx + U.w(label, U.F.xs) + 24 > x + w then
            cx = x
            cy = cy + chH + 4
        end
        cx = chip(cx, label, self.boardCat == cats[i], "cat", cats[i])
    end
    cy = cy + chH + 6

    -- ---- ชิปตัวอักษร -----------------------------------------------------------
    cx = x
    cx = chip(cx, KR.L("ก-ฮ / A-Z", "A-Z"), self.boardAZ == nil, "az", nil)
    for i = 1, #AZ do
        if cx + U.w(AZ[i], U.F.xs) + 22 > x + w then
            cx = x
            cy = cy + chH + 4
        end
        cx = chip(cx, AZ[i], self.boardAZ == AZ[i], "az", AZ[i])
    end
    cy = cy + chH + U.GAP

    -- ---- ตาราง -----------------------------------------------------------------
    local rows, total = self:boardRows()
    local listY = cy
    local listH = math.max(60, y + h - cy)
    local rowH  = math.max(30, SH3 + 14)

    if #rows == 0 then
        U.emptyState(self, x, listY, w, listH,
                     (total == 0) and KR.L("ยังไม่มีราคาบนกระดาน", "The board is empty")
                                   or KR.L("ไม่มีรายการที่ตรง", "Nothing matches that"),
                     (total == 0)
                        and KR.L("แอดมินเพิ่มได้ที่หน้า ADMIN > กระดานราคา",
                                 "An admin adds prices in ADMIN > Price board")
                        or  KR.L("ลองเลือกหมวดอื่นหรือล้างคำค้น",
                                 "Try another category, or clear the search"))
        return
    end

    local view  = math.floor(listH / rowH)
    local maxSc = math.max(0, #rows * rowH - view * rowH)
    if (self.boardScroll or 0) > maxSc then self.boardScroll = maxSc end
    local off = math.floor((self.boardScroll or 0) / rowH)

    -- หัวคอลัมน์
    local cName  = x + 8
    local cPrice = x + w - 14
    local cCat   = x + math.floor(w * 0.52)

    self:setStencilRect(x, listY, w, listH)
    local ry = listY - ((self.boardScroll or 0) % rowH)
    for i = off + 1, math.min(#rows, off + view + 2) do
        local r = rows[i]
        if (i - off) % 2 == 0 then U.fill(self, x, ry, w, rowH, U.C.bgCard) end

        U.text(self, U.wrap(r.name, U.F.s, cCat - cName - 10, 1)[1],
               cName, ry + math.floor((rowH - SH3) / 2), U.C.text, U.F.s)

        U.text(self, tostring(r.cat or ""), cCat,
               ry + math.floor((rowH - XH2) / 2), U.C.dim, U.F.xs)

        local cur = r.cur or KR.CUR.CASH
        local amt = KR.comma and KR.comma(r.price) or tostring(r.price)
        U.textR(self, amt, cPrice, ry + math.floor((rowH - SH3) / 2), U.curCol(cur), U.F.s)
        U.coin(self, cur, cPrice - U.w(amt, U.F.s) - 20,
               ry + math.floor((rowH - 14) / 2), 14)

        if r.note and r.note ~= "" then
            local nx = cCat + U.w(tostring(r.cat or ""), U.F.xs) + 10
            local room = cPrice - nx - 120
            if room > 40 then
                U.text(self, U.wrap(r.note, U.F.xs, room, 1)[1], nx,
                       ry + math.floor((rowH - XH2) / 2), U.C.mute, U.F.xs)
            end
        end
        ry = ry + rowH
    end
    self:clearStencilRect()

    if #rows > view then
        U.scrollbar(self, x + w - 3, listY, listH, #rows * rowH, listH,
                    self.boardScroll or 0)
    end
end

function KRShop:boardClick(x, y)
    for _, b in ipairs(self.boardBtns or {}) do
        if U.hit(b, x, y) then
            if b.act == "cat" then self.boardCat = b.val
            elseif b.act == "az" then self.boardAZ = b.val end
            self.boardScroll = 0
            return true
        end
    end
    return true
end

-- ==============================================================================
-- 0.7.0 — หน้าสถิติเศรษฐกิจ + สกิล   (แอดมินเท่านั้น)
--
-- สามแท็บ เพราะเป็นคำถามสามข้อที่ไม่ได้ถามพร้อมกัน
--   MONEY   ตอนนี้ใครมีเท่าไร        (ค่าเฉลี่ย · มัธยฐาน · Top 10)
--   FLOW    เงินไหลเท่าไรในแต่ละวัน  (กราฟเข้า-ออก)
--   SKILLS  ใครทำอะไรเป็น            (8-10 เฉพาะกลุ่มฝีมือ)
-- ==============================================================================
local STABS = {
    { id = "money",  th = "เงิน",   en = "Money"  },
    { id = "flow",   th = "กระแส",  en = "Flow"   },
    { id = "skills", th = "สกิล",   en = "Skills" },
}

-- ขอตัวเลขจากเซิร์ฟ  ไม่ยิงรัว  (เซิร์ฟแคชอยู่แล้ว แต่แพ็กเก็ตก็ยังมีราคา)
function KRShop:statsPoll(force)
    local now = getTimestampMs and getTimestampMs() or 0
    if not force and self.statAskedAt and (now - self.statAskedAt) < 5000 then return end
    self.statAskedAt = now
    req(KR.CMD.STATS_GET, { cur = self.statCur or KR.CUR.CASH,
                            days = self.statDays or 7,
                            fresh = force and true or nil })
end

function KRShop:skillsPoll(force)
    local now = getTimestampMs and getTimestampMs() or 0
    if not force and self.skAskedAt and (now - self.skAskedAt) < 5000 then return end
    self.skAskedAt = now
    req(KR.CMD.SKILLS_GET, {})
end

-- "เมื่อกี้" ที่คนอ่านเข้าใจ  ตัวเลข epoch ดิบไม่ได้ตอบอะไรเลย
local function agoText(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 60 then return KR.L("เมื่อครู่", "just now") end
    if sec < 3600 then return math.floor(sec / 60) .. KR.L(" นาทีก่อน", "m ago") end
    if sec < 86400 then return math.floor(sec / 3600) .. KR.L(" ชม.ก่อน", "h ago") end
    return math.floor(sec / 86400) .. KR.L(" วันก่อน", "d ago") end

local function moneyText(cur, v)
    if v == nil then return KR.L("ไม่มีข้อมูล", "no data") end
    if cur == KR.CUR.CASH then
        return KR.comma(math.floor(v / KR.SUBUNIT))
    end
    return KR.comma(v)
end

function KRShop:drawStats(x, y, w, h)
    local XH2, SH3, MH2 = U.h(U.F.xs), U.h(U.F.s), U.h(U.F.m)
    self.statBtns = {}
    self.statCur  = self.statCur or KR.CUR.CASH
    self.statDays = self.statDays or 7
    self.statTab  = self.statTab or "money"

    if self.statTab == "skills" then self:skillsPoll() else self:statsPoll() end

    local st = KRClient and KRClient.stats
    local cy = y

    -- ---- แท็บ -------------------------------------------------------------
    local tabH = math.max(28, SH3 + 12)
    local tx = x
    for i = 1, #STABS do
        local t  = STABS[i]
        local lb = KR.L(t.th, t.en):upper()
        local tw = U.w(lb, U.F.xs) + 24
        local on = (self.statTab == t.id)
        U.fill(self, tx, cy, tw, tabH, on and U.C.accent2 or U.C.bgCard)
        if on then U.fill(self, tx, cy + tabH - 2, tw, 2, U.C.accent) end
        U.text(self, lb, tx + 12, cy + math.floor((tabH - XH2) / 2),
               on and U.C.text or U.C.mute, U.F.xs)
        self.statBtns[#self.statBtns + 1] =
            { x = tx, y = cy, w = tw, h = tabH, act = "tab", val = t.id }
        tx = tx + tw + 5
    end

    -- ปุ่มคิดใหม่  อยู่ขวาสุดของแถวแท็บ
    local rw = U.w(KR.L("คิดใหม่", "Refresh"), U.F.xs) + 24
    self.statBtns[#self.statBtns + 1] =
        { x = x + w - rw, y = cy, w = rw, h = tabH, act = "refresh" }
    U.fill(self, x + w - rw, cy, rw, tabH, U.C.bgCard)
    U.text(self, KR.L("คิดใหม่", "Refresh"), x + w - rw + 12,
           cy + math.floor((tabH - XH2) / 2), U.C.lite, U.F.xs)
    cy = cy + tabH + U.GAP

    if self.statTab == "skills" then
        return self:drawStatSkills(x, cy, w, y + h - cy)
    end

    if st == nil then
        U.emptyState(self, x, cy, w, y + h - cy,
                     KR.L("กำลังคิด...", "Working it out..."),
                     KR.L("เซิร์ฟกำลังอ่านยอดเงินของทุกคนที่ยัง active",
                          "The server is reading the balance of everyone still active"))
        return
    end

    if self.statTab == "flow" then
        return self:drawStatFlow(x, cy, w, y + h - cy, st)
    end
    return self:drawStatMoney(x, cy, w, y + h - cy, st)
end

-- ------------------------------------------------------------------------------
-- แท็บ MONEY
-- ------------------------------------------------------------------------------
function KRShop:drawStatMoney(x, y, w, h, st)
    local XH2, SH3, MH2, LH2 = U.h(U.F.xs), U.h(U.F.s), U.h(U.F.m), U.h(U.F.l)
    local cy = y
    local c  = st.cash or {}

    -- ---- การ์ดสามตัวเลข ----------------------------------------------------
    --
    -- **ค่าเฉลี่ยอยู่ลำพังไม่ได้**  คนรวยคนเดียวดึงมันขึ้นได้ทั้งเซิร์ฟ แล้วมันจะถูก
    -- เอาไปใช้ตั้งราคาของในร้าน  มัธยฐานตอบ "คนทั่วไปมีเท่าไร" ถูก
    -- และ n บอกว่าเชื่อได้แค่ไหน — n=3 กับ n=60 คนละเรื่องกันสิ้นเชิง
    local cardH = MH2 + LH2 + XH2 + 26
    U.fill(self, x, cy, w, cardH, U.C.bgCard)
    U.text(self, KR.L("เงินสดของคนที่ยังเล่นอยู่", "Cash held by active players"),
           x + 14, cy + 10, U.C.text, U.F.s)
    U.textR(self, KR.L("ใน ", "last ") .. tostring(st.days or 7) .. KR.L(" วัน", " days"),
            x + w - 14, cy + 10, U.C.mute, U.F.xs)

    local cellW = math.floor((w - 28) / 3)
    local by = cy + 10 + SH3 + 8
    local function cell(i, label, val, col, hint)
        local bx = x + 14 + (i - 1) * cellW
        U.text(self, label, bx, by, U.C.mute, U.F.xs)
        U.text(self, val, bx, by + XH2 + 2, col, U.F.l)
        if hint then
            U.text(self, hint, bx, by + XH2 + 2 + LH2 + 1, U.C.dim, U.F.xs)
        end
    end
    cell(1, KR.L("ค่าเฉลี่ย", "MEAN"), moneyText(KR.CUR.CASH, c.mean),
         c.mean and U.C.cash or U.C.dim)
    cell(2, KR.L("มัธยฐาน", "MEDIAN"), moneyText(KR.CUR.CASH, c.med),
         c.med and U.C.text or U.C.dim,
         KR.L("คนตรงกลางมีเท่านี้", "what a typical player has"))
    cell(3, KR.L("นับจากกี่คน", "PLAYERS"), tostring(c.n or 0),
         (c.n or 0) > 0 and U.C.lite or U.C.bad,
         (c.n or 0) == 0 and KR.L("ไม่มีใครเลย", "nobody to count") or nil)
    cy = cy + cardH + 6

    -- คนที่ธนาคารอ่านยอดไม่ได้  ต้องบอก ไม่ใช่เงียบแล้วให้ค่าเฉลี่ยเพี้ยน
    if (c.noBank or 0) > 0 then
        U.text(self, KR.L("อ่านยอดไม่ได้ ", "Could not read ") .. tostring(c.noBank) ..
                     KR.L(" คน  ไม่ได้ถูกนับในตัวเลขข้างบน",
                          " players - they are not in the numbers above"),
               x, cy, U.C.warn, U.F.xs)
        cy = cy + XH2 + 4
    end
    U.text(self, KR.L("คิดเมื่อ ", "worked out ") .. agoText(st.cached or 0),
           x, cy, U.C.dim, U.F.xs)
    cy = cy + XH2 + U.GAP

    -- ---- Top 10 ------------------------------------------------------------
    U.text(self, KR.L("รวยที่สุดสิบอันดับ", "Top ten"), x, cy, U.C.text, U.F.s)
    local chH = math.max(24, XH2 + 10)
    local cw2 = math.floor((w * 0.4) / 3)
    for i, cur in ipairs({ KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP }) do
        local bx = x + w - (4 - i) * (cw2 + 5)
        local on = (self.statCur == cur)
        U.fill(self, bx, cy - 4, cw2, chH, on and U.C.accent2 or U.C.bgCard)
        if on then U.fill(self, bx, cy - 4 + chH - 2, cw2, 2, U.C.accent) end
        U.coin(self, cur, bx + 6, cy - 4 + math.floor((chH - 14) / 2), 14)
        U.text(self, (KR.CUR_META[cur] or {}).label or cur, bx + 24,
               cy - 4 + math.floor((chH - XH2) / 2), on and U.C.text or U.C.mute, U.F.xs)
        self.statBtns[#self.statBtns + 1] =
            { x = bx, y = cy - 4, w = cw2, h = chH, act = "cur", val = cur }
    end
    cy = cy + math.max(SH3, chH) + 6

    local list = (st.top or {})[self.statCur] or {}
    local rowH = math.max(26, SH3 + 10)
    if #list == 0 then
        U.text(self, KR.L("ยังไม่มีใครถือสกุลนี้", "Nobody holds any of this yet"),
               x + 4, cy + 2, U.C.mute, U.F.xs)
        return
    end
    for i = 1, #list do
        local r  = list[i]
        local ry = cy + (i - 1) * rowH
        if ry + rowH > y + h then break end
        if i % 2 == 1 then U.fill(self, x, ry, w, rowH, U.C.bgCard) end
        U.text(self, tostring(i) .. ".", x + 8, ry + math.floor((rowH - XH2) / 2),
               U.C.dim, U.F.xs)
        U.text(self, U.wrap(r.n or r.k, U.F.s, w * 0.45, 1)[1], x + 34,
               ry + math.floor((rowH - SH3) / 2), U.C.text, U.F.s)
        if r.on then
            U.fill(self, x + 34 + U.w(tostring(r.n or r.k), U.F.s) + 8,
                   ry + math.floor(rowH / 2) - 3, 6, 6, U.C.good)
        end
        local amt = moneyText(self.statCur, r.v)
        U.textR(self, amt, x + w - 12, ry + math.floor((rowH - SH3) / 2),
                U.curCol(self.statCur), U.F.s)
        -- กดแล้วเปิดบัญชีคนนั้น  ใช้ทางเดิมของแท็บ Players ไม่เขียนทางที่สอง
        self.statBtns[#self.statBtns + 1] =
            { x = x, y = ry, w = w, h = rowH, act = "person", val = r.k }
    end
end

-- ------------------------------------------------------------------------------
-- แท็บ FLOW  กราฟเงินเข้า-ออกรวมทั้งเซิร์ฟ
--
-- วันที่ยังไม่มีข้อมูล (ก่อนอัปเดตนี้) วาดเป็นช่องว่างที่มีป้ายบอก
-- **ห้ามวาดเป็นศูนย์** ศูนย์แปลว่า "ไม่มีเงินไหลวันนั้น" ซึ่งไม่จริง
-- ------------------------------------------------------------------------------
function KRShop:drawStatFlow(x, y, w, h, st)
    local XH2, SH3 = U.h(U.F.xs), U.h(U.F.s)
    local cy = y
    local ser = st.series or {}

    -- ชิปช่วงเวลา + สกุล
    local chH = math.max(24, XH2 + 10)
    local bx = x
    for _, dd in ipairs({ 7, 30 }) do
        local lb = tostring(dd) .. KR.L(" วัน", "d")
        local tw = U.w(lb, U.F.xs) + 20
        local on = (self.statDays == dd)
        U.fill(self, bx, cy, tw, chH, on and U.C.accent2 or U.C.bgCard)
        if on then U.fill(self, bx, cy + chH - 2, tw, 2, U.C.accent) end
        U.text(self, lb, bx + 10, cy + math.floor((chH - XH2) / 2),
               on and U.C.text or U.C.mute, U.F.xs)
        self.statBtns[#self.statBtns + 1] =
            { x = bx, y = cy, w = tw, h = chH, act = "days", val = dd }
        bx = bx + tw + 5
    end
    local cw2 = math.floor((w * 0.4) / 3)
    for i, cur in ipairs({ KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP }) do
        local cx2 = x + w - (4 - i) * (cw2 + 5)
        local on = (self.statCur == cur)
        U.fill(self, cx2, cy, cw2, chH, on and U.C.accent2 or U.C.bgCard)
        if on then U.fill(self, cx2, cy + chH - 2, cw2, 2, U.C.accent) end
        U.coin(self, cur, cx2 + 6, cy + math.floor((chH - 14) / 2), 14)
        U.text(self, (KR.CUR_META[cur] or {}).label or cur, cx2 + 24,
               cy + math.floor((chH - XH2) / 2), on and U.C.text or U.C.mute, U.F.xs)
        self.statBtns[#self.statBtns + 1] =
            { x = cx2, y = cy, w = cw2, h = chH, act = "cur", val = cur }
    end
    cy = cy + chH + 8

    -- คำอธิบายสี
    U.fill(self, x, cy + 2, 10, 10, U.C.good)
    U.text(self, KR.L("เข้า", "in"), x + 15, cy, U.C.mute, U.F.xs)
    U.fill(self, x + 15 + U.w(KR.L("เข้า", "in"), U.F.xs) + 10, cy + 2, 10, 10, U.C.bad)
    U.text(self, KR.L("ออก", "out"),
           x + 15 + U.w(KR.L("เข้า", "in"), U.F.xs) + 25, cy, U.C.mute, U.F.xs)
    cy = cy + XH2 + 8

    local gx, gy = x, cy
    local gw = w
    local gh = math.max(80, y + h - cy - XH2 - 26)

    local peak = 1
    local anyData = false
    for i = 1, #ser do
        local r = ser[i]
        if r.have then
            anyData = true
            if r.inc > peak then peak = r.inc end
            if r.out > peak then peak = r.out end
        end
    end

    U.fill(self, gx, gy, gw, gh, U.C.bgCard)
    if not anyData then
        U.textC(self, KR.L("ยังไม่มีข้อมูลสักวัน", "No days recorded yet"),
                gx + gw / 2, gy + math.floor(gh / 2) - XH2, U.C.mute, U.F.s)
        U.textC(self, KR.L("ยอดรวมรายวันเริ่มเก็บตั้งแต่รุ่นนี้เป็นต้นไป",
                           "Daily totals start from this version onward"),
                gx + gw / 2, gy + math.floor(gh / 2) + 4, U.C.dim, U.F.xs)
        return
    end

    local n    = math.max(1, #ser)
    local slot = gw / n
    local barW = math.max(2, math.floor(slot / 2) - 1)

    for i = 1, #ser do
        local r  = ser[i]
        local bx2 = gx + math.floor((i - 1) * slot)
        if not r.have then
            -- ช่องว่างที่บอกว่าว่าง  ไม่ใช่แท่งสูงศูนย์
            -- แท่งสูงศูนย์กับ "ไม่มีข้อมูล" หน้าตาเหมือนกันเป๊ะ และหมายความคนละอย่าง
            U.fill(self, bx2, gy + gh - 3, math.max(2, math.floor(slot) - 2), 2, U.C.line3)
        else
            local hi = math.floor((r.inc / peak) * (gh - 6))
            local ho = math.floor((r.out / peak) * (gh - 6))
            U.fill(self, bx2, gy + gh - hi, barW, math.max(1, hi), U.C.good)
            U.fill(self, bx2 + barW + 1, gy + gh - ho, barW, math.max(1, ho), U.C.bad)
        end
    end

    cy = gy + gh + 4
    U.text(self, KR.L("เก่าสุด", "oldest"), gx, cy, U.C.dim, U.F.xs)
    U.textR(self, KR.L("วันนี้", "today"), gx + gw, cy, U.C.dim, U.F.xs)
    cy = cy + XH2 + 4
    U.text(self, KR.L("สูงสุดในช่วงนี้ ", "peak in this window ") ..
                 moneyText(self.statCur, peak), gx, cy, U.C.mute, U.F.xs)
end

-- ------------------------------------------------------------------------------
-- แท็บ SKILLS
-- ------------------------------------------------------------------------------
function KRShop:drawStatSkills(x, y, w, h)
    local XH2, SH3 = U.h(U.F.xs), U.h(U.F.s)
    local sk = KRClient and KRClient.skills
    local cy = y

    if sk == nil then
        U.emptyState(self, x, cy, w, h,
                     KR.L("กำลังอ่านสกิล...", "Reading skills..."), nil)
        return
    end

    if sk.why then
        U.text(self, KR.L("อ่านรายชื่อสกิลจากเกมนี้ไม่ได้", "Cannot read this build's skill list"),
               x, cy, U.C.bad, U.F.s)
        cy = cy + SH3 + 2
        U.text(self, tostring(sk.why), x, cy, U.C.mute, U.F.xs)
        return
    end

    U.text(self, KR.L("ตั้งแต่ระดับ ", "From level ") .. tostring(sk.from or 8) ..
                 KR.L(" ขึ้นไป  เฉพาะ ", " up, only ") ..
                 table.concat(sk.groups or {}, " / "),
           x, cy, U.C.mute, U.F.xs)
    cy = cy + XH2 + 2
    if (sk.unseen or 0) > 0 then
        -- **ห้ามให้ดูเหมือนว่าไม่มีใครเก่ง**  วันแรกที่ลง หน้านี้จะมีเฉพาะคนที่
        -- เข้ามาแล้วหลังอัปเดต  ต้องเขียนตรง ๆ ว่ายังไม่เคยเห็นกี่คน
        U.text(self, KR.L("ยังไม่เคยเห็นสกิลของ ", "Never seen the skills of ") ..
                     tostring(sk.unseen) ..
                     KR.L(" คน  เขาต้องเข้าเกมสักครั้งก่อน",
                          " players - they each need to log in once"),
               x, cy, U.C.warn, U.F.xs)
        cy = cy + XH2 + 2
    end
    cy = cy + 6

    local lw = math.max(160, math.floor(w * 0.34))
    local rx = x + lw + U.GAP
    local rw = w - lw - U.GAP
    local rowH = math.max(24, SH3 + 8)

    -- ---- ซ้าย: รายชื่อสกิล  กดเพื่อดูว่าใครถึงเกณฑ์ -------------------------
    U.text(self, KR.L("รายสกิล", "By skill"), x, cy, U.C.dim, U.F.xs)
    local ly = cy + XH2 + 4
    local skills = sk.skills or {}
    for i = 1, #skills do
        local r  = skills[i]
        local ry = ly + (i - 1) * rowH
        if ry + rowH > y + h then break end
        local on = (self.skPick == r.id)
        U.fill(self, x, ry, lw, rowH, on and U.C.bgSel or (i % 2 == 1 and U.C.bgCard or nil))
        if on then U.fill(self, x, ry, 3, rowH, U.C.accent) end
        U.text(self, U.wrap(r.id, U.F.s, lw - 50, 1)[1], x + 10,
               ry + math.floor((rowH - SH3) / 2), on and U.C.text or U.C.lite, U.F.s)
        -- กี่คนถึงเกณฑ์ในสกิลนี้
        local n = 0
        for _, pr in ipairs(sk.people or {}) do
            if pr.s and pr.s[r.id] then n = n + 1 end
        end
        U.textR(self, tostring(n), x + lw - 10, ry + math.floor((rowH - XH2) / 2),
                n > 0 and U.C.good or U.C.dim, U.F.xs)
        self.statBtns[#self.statBtns + 1] =
            { x = x, y = ry, w = lw, h = rowH, act = "skill", val = r.id }
    end

    -- ---- ขวา: ผลของสิ่งที่เลือกอยู่ ------------------------------------------
    local ry2 = cy
    if self.skWho then
        -- มุม "รายคน"  เขามีสกิลไหนถึงเกณฑ์บ้าง
        local who = nil
        for _, pr in ipairs(sk.people or {}) do if pr.k == self.skWho then who = pr end end
        U.text(self, KR.L("ของคนนี้", "This player"), rx, ry2, U.C.dim, U.F.xs)
        self.statBtns[#self.statBtns + 1] =
            { x = rx + rw - 70, y = ry2 - 4, w = 70, h = XH2 + 10, act = "backskill" }
        U.textR(self, KR.L("ย้อนกลับ", "back"), rx + rw - 8, ry2, U.C.lite, U.F.xs)
        ry2 = ry2 + XH2 + 4

        if who == nil then
            U.text(self, KR.L("ไม่มีข้อมูลของคนนี้", "Nothing recorded for them"),
                   rx + 4, ry2, U.C.mute, U.F.xs)
            return
        end
        U.text(self, tostring(who.n or who.k), rx + 4, ry2, U.C.text, U.F.s)
        ry2 = ry2 + SH3 + 2
        U.text(self, who.on and KR.L("ออนไลน์อยู่", "online now")
                             or (KR.L("เก็บไว้เมื่อ ", "snapshot taken ") ..
                                 agoText((data().now or 0) - (who.at or 0))),
               rx + 4, ry2, who.on and U.C.good or U.C.warn, U.F.xs)
        ry2 = ry2 + XH2 + 6

        local i = 0
        for id, lv in pairs(who.s or {}) do
            local yy = ry2 + i * rowH
            if yy + rowH > y + h then break end
            if i % 2 == 0 then U.fill(self, rx, yy, rw, rowH, U.C.bgCard) end
            U.text(self, id, rx + 10, yy + math.floor((rowH - SH3) / 2), U.C.text, U.F.s)
            U.textR(self, tostring(lv), rx + rw - 12, yy + math.floor((rowH - SH3) / 2),
                    U.C.good, U.F.s)
            i = i + 1
        end
        if i == 0 then
            U.text(self, KR.L("ไม่มีสกิลถึงเกณฑ์", "Nothing at that level"),
                   rx + 4, ry2, U.C.mute, U.F.xs)
        end
        return
    end

    -- มุม "รายสกิล"  ใครถึงเกณฑ์ในสกิลที่เลือก
    U.text(self, self.skPick and (KR.L("ใครมี ", "Who has ") .. self.skPick)
                             or KR.L("เลือกสกิลทางซ้าย", "Pick a skill on the left"),
           rx, ry2, U.C.dim, U.F.xs)
    ry2 = ry2 + XH2 + 4
    if not self.skPick then
        U.text(self, KR.L("หรือกดชื่อคนเพื่อดูของเขาทั้งหมด",
                          "or click a name to see everything they have"),
               rx + 4, ry2, U.C.mute, U.F.xs)
        return
    end

    local hits = {}
    for _, pr in ipairs(sk.people or {}) do
        local lv = pr.s and pr.s[self.skPick]
        if lv then hits[#hits + 1] = { p = pr, lv = lv } end
    end
    table.sort(hits, function(a, b)
        if a.lv ~= b.lv then return a.lv > b.lv end
        return tostring(a.p.k) < tostring(b.p.k)
    end)

    if #hits == 0 then
        U.text(self, KR.L("ยังไม่มีใครถึงเกณฑ์นี้", "Nobody has reached that yet"),
               rx + 4, ry2, U.C.mute, U.F.xs)
        return
    end
    for i = 1, #hits do
        local r  = hits[i]
        local yy = ry2 + (i - 1) * rowH
        if yy + rowH > y + h then break end
        if i % 2 == 1 then U.fill(self, rx, yy, rw, rowH, U.C.bgCard) end
        U.text(self, U.wrap(r.p.n or r.p.k, U.F.s, rw * 0.5, 1)[1], rx + 10,
               yy + math.floor((rowH - SH3) / 2), U.C.text, U.F.s)
        U.textR(self, tostring(r.lv), rx + rw - 12, yy + math.floor((rowH - SH3) / 2),
                U.C.good, U.F.s)
        -- ตัวเลขที่ไม่บอกว่าเก่าแค่ไหน คือตัวเลขที่คนอ่านว่าเป็นปัจจุบัน
        -- ซึ่งเป็นการโกหกโดยการละเว้น
        U.textR(self, r.p.on and KR.L("ออน", "online")
                              or agoText((data().now or 0) - (r.p.at or 0)),
                rx + rw - 46, yy + math.floor((rowH - XH2) / 2),
                r.p.on and U.C.good or U.C.dim, U.F.xs)
        self.statBtns[#self.statBtns + 1] =
            { x = rx, y = yy, w = rw, h = rowH, act = "skwho", val = r.p.k }
    end
end

function KRShop:statsClick(x, y)
    for _, b in ipairs(self.statBtns or {}) do
        if U.hit(b, x, y) then
            if b.act == "tab" then
                self.statTab = b.val
                self.statScroll = 0
            elseif b.act == "cur" then
                self.statCur = b.val
                self:statsPoll(true)
            elseif b.act == "days" then
                self.statDays = b.val
                self:statsPoll(true)
            elseif b.act == "refresh" then
                if self.statTab == "skills" then self:skillsPoll(true)
                else self:statsPoll(true) end
            elseif b.act == "skill" then
                self.skPick = (self.skPick == b.val) and nil or b.val
                self.skWho  = nil
            elseif b.act == "skwho" then
                -- กดชื่อคนในมุมรายสกิล = สลับไปมุมรายคนของคนนั้นเลย
                -- ไม่ใช่เปิดหน้าต่างอีกอัน  ที่เจ้าของเซิร์ฟสั่งคือ "แบบรวมของคนนี้"
                self.skWho = b.val
            elseif b.act == "backskill" then
                self.skWho = nil
            elseif b.act == "person" then
                -- ใช้ทางเดิมของแท็บ Players  ไม่เขียนทางเปิดบัญชีอันที่สอง
                req(KR.CMD.ACC_VIEW, { key = b.val })
                self.page = "admin"
                if self.adm then self.adm.tab = "people" end
            end
            return true
        end
    end
    return true
end

-- ==============================================================================
-- 0.7.0 — แท็บแอดมิน: กระดานราคาโลก
--
-- ฟอร์มซ้าย เพิ่ม/แก้  ลิสต์ขวา ของที่อยู่บนกระดานแล้ว
-- ตั้งใจให้หน้าตาเหมือนแท็บ Listings เพราะเป็นงานเดียวกันในสายตาแอดมิน
-- แต่ **ข้อมูลอยู่คนละตาราง** และไม่มีช่อง item / stock / pay อยู่ในฟอร์มนี้เลย
-- ถ้าวันหนึ่งมีใครเพิ่มช่องพวกนั้นเข้ามา นั่นคือวันที่กระดานกลายเป็นร้านที่สอง
-- ==============================================================================
-- โหลดแถวบนกระดานเข้าฟอร์ม  nil = ล้างฟอร์ม
--
-- ชื่อ bdLoad ไม่ใช่ boardLoad โดยตั้งใจ  lint กฎ 15 ห้ามชื่อฟิลด์ชนชื่อเมธอด
-- และ "board" เป็นชื่อฟิลด์ที่ข้อมูลใช้อยู่แล้ว (data().board)
function KRShop:bdLoad(id)
    local a = self.adm
    a.bdId = nil
    local row = nil
    if id then
        for _, r in ipairs((data().board or {}).list or {}) do
            if r.id == id then row = r end
        end
    end
    a.bdId  = row and row.id or nil
    a.bdCur = row and (row.cur or KR.CUR.CASH) or KR.CUR.CASH
    local function put(f, v)
        if self.fields[f] then self.fields[f]:setText(v == nil and "" or tostring(v)) end
    end
    put("bdName",  row and row.name)
    put("bdCat",   row and row.cat)
    put("bdPrice", row and row.price)
    put("bdNote",  row and row.note)
end

function KRShop:admBoard(x, y, w, h)
    local XH2, SH3 = U.h(U.F.xs), U.h(U.F.s)
    local a = self.adm
    a.bdCur = a.bdCur or KR.CUR.CASH

    local lw = math.max(280, math.floor(w * 0.40))
    local rx = x + lw + U.GAP * 2
    local rw = w - lw - U.GAP * 2

    -- ---------------- ซ้าย: ฟอร์ม ------------------------------------------
    local cy = y
    U.text(self, a.bdId and KR.L("แก้รายการ", "Edit row") or KR.L("เพิ่มรายการ", "Add a row"),
           x, cy, U.C.text, U.F.s)
    cy = cy + SH3 + 6

    local bxh = boxH() + 6
    local function field(label, id, wide)
        U.text(self, label, x, cy, U.C.dim, U.F.xs)
        cy = cy + XH2 + 3
        local fw = wide and lw or math.floor(lw * 0.5)
        U.fill(self, x, cy, fw, bxh, U.C.bgDark)
        U.border(self, x, cy, fw, bxh, U.C.line3)
        local f = self.fields[id]
        if f then
            f:setVisible(true)
            f:setX(x + 5); f:setY(cy + 3)
            sizeBox(f, fw - 10, bxh - 6)
        end
        cy = cy + bxh + 6
        return f
    end

    field(KR.L("ชื่อของ", "Name"), "bdName", true)
    field(KR.L("หมวด", "Category"), "bdCat", true)
    field(KR.L("ราคา", "Price"), "bdPrice", false)

    -- สกุล  ชิปสามอัน
    local chH = math.max(24, XH2 + 10)
    local cw2 = math.floor((lw - 10) / 3)
    for i, cur in ipairs({ KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP }) do
        local bx = x + (i - 1) * (cw2 + 5)
        local on = (a.bdCur == cur)
        U.fill(self, bx, cy, cw2, chH, on and U.C.accent2 or U.C.bgCard)
        if on then U.fill(self, bx, cy + chH - 2, cw2, 2, U.C.accent) end
        U.coin(self, cur, bx + 6, cy + math.floor((chH - 14) / 2), 14)
        U.text(self, (KR.CUR_META[cur] or {}).label or cur, bx + 24,
               cy + math.floor((chH - XH2) / 2), on and U.C.text or U.C.mute, U.F.xs)
        self.admBtns[#self.admBtns + 1] =
            { x = bx, y = cy, w = cw2, h = chH, act = "bdcur", val = cur }
    end
    cy = cy + chH + 8

    field(KR.L("หมายเหตุ", "Note"), "bdNote", true)

    -- ---- ปุ่ม ---------------------------------------------------------------
    local btnH = math.max(30, SH3 + 14)
    local half = math.floor((lw - U.GAP) / 2)
    local nameTxt  = tostring(self.fields.bdName and self.fields.bdName:getInternalText() or "")
    local priceTxt = tonumber(self.fields.bdPrice and self.fields.bdPrice:getInternalText() or "")

    local why
    if nameTxt:gsub("%s", "") == "" then why = KR.L("ใส่ชื่อก่อน", "Name it first")
    elseif priceTxt == nil        then why = KR.L("ใส่ราคาเป็นตัวเลข", "Price must be a number")
    elseif priceTxt < 0           then why = KR.L("ราคาติดลบไม่ได้", "Price cannot be negative") end

    self.bBdClear = U.btn(self, x, cy, half, btnH, KR.L("ล้างฟอร์ม", "Clear"),
                          "neu", self.mx, self.my)
    self.bBdSave = U.btn(self, x + half + U.GAP, cy, half, btnH,
                         why or (a.bdId and KR.L("บันทึก", "Save") or KR.L("เพิ่ม", "Add")),
                         why and "offb" or "pri", self.mx, self.my)
    if why then self.bBdSave = nil end
    cy = cy + btnH + 6

    U.text(self, KR.L("กระดานนี้ไม่ใช่ของในร้าน  ไม่มีปุ่มซื้อ",
                      "This board is not the shop. Nothing here can be bought."),
           x, cy, U.C.mute, U.F.xs)

    -- ---------------- ขวา: ของบนกระดาน --------------------------------------
    local b = data().board or {}
    local all = b.list or {}
    local ry = y

    U.text(self, KR.L("บนกระดานตอนนี้ ", "On the board ") .. "(" .. #all .. "/" ..
                 KR.BOARD_MAX .. ")", rx, ry, U.C.dim, U.F.xs)
    ry = ry + XH2 + 4

    local fbh = boxH() + 6
    U.fill(self, rx, ry, rw, fbh, U.C.bgDark)
    U.border(self, rx, ry, rw, fbh, U.C.line3)
    local ff = self.fields.bdFind
    local q = ""
    if ff then
        ff:setVisible(true)
        ff:setX(rx + 5); ff:setY(ry + 3)
        sizeBox(ff, rw - 10, fbh - 6)
        q = tostring(ff:getInternalText() or ""):lower()
        if q == "" then
            U.text(self, KR.L("ค้นชื่อ", "search the board"), rx + 12,
                   ry + math.floor((fbh - XH2) / 2), U.C.mute, U.F.xs)
        end
    end
    ry = ry + fbh + 6

    local rows = {}
    for i = 1, #all do
        local r = all[i]
        if q == "" or tostring(r.name):lower():find(q, 1, true)
                   or tostring(r.cat or ""):lower():find(q, 1, true) then
            rows[#rows + 1] = r
        end
    end
    table.sort(rows, function(p2, q2)
        if p2.cat ~= q2.cat then return tostring(p2.cat) < tostring(q2.cat) end
        return tostring(p2.name) < tostring(q2.name)
    end)

    local rowH = math.max(26, SH3 + 10)
    local room = y + h - ry
    local view = math.max(1, math.floor(room / rowH))
    if (self.bdScroll or 0) > math.max(0, #rows - view) then
        self.bdScroll = math.max(0, #rows - view)
    end
    local off = math.floor(self.bdScroll or 0)

    if #rows == 0 then
        U.text(self, (#all == 0) and KR.L("ยังไม่มีอะไรบนกระดาน", "The board is empty")
                                  or KR.L("ไม่มีรายการที่ตรง", "Nothing matches"),
               rx + 4, ry + 2, U.C.mute, U.F.xs)
        return
    end

    for i = 1, math.min(view, #rows - off) do
        local r  = rows[i + off]
        local yy = ry + (i - 1) * rowH
        if i % 2 == 1 then U.fill(self, rx, yy, rw, rowH, U.C.bgCard) end
        local delW = 26
        U.text(self, U.wrap(r.name, U.F.s, rw * 0.44, 1)[1], rx + 8,
               yy + math.floor((rowH - SH3) / 2), U.C.text, U.F.s)
        U.text(self, tostring(r.cat or ""), rx + math.floor(rw * 0.46),
               yy + math.floor((rowH - XH2) / 2), U.C.dim, U.F.xs)
        U.textR(self, KR.comma(r.price), rx + rw - delW - 10,
                yy + math.floor((rowH - SH3) / 2), U.curCol(r.cur or KR.CUR.CASH), U.F.s)

        self.admBtns[#self.admBtns + 1] =
            { x = rx, y = yy, w = rw - delW, h = rowH, act = "bdedit", val = r.id }
        local db2 = U.btn(self, rx + rw - delW, yy + 2, delW - 4, rowH - 4, "X",
                          "bad", self.mx, self.my)
        db2.act, db2.val = "bddel", r.id
        self.admBtns[#self.admBtns + 1] = db2
    end

    if #rows > view then
        U.scrollbar(self, rx + rw - 3, ry, room, #rows, view, off)
    end
end

return KRShop
