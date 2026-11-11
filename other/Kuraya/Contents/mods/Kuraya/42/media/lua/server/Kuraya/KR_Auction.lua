-- ==============================================================================
-- Kuraya — server/Kuraya/KR_Auction.lua
-- ประมูลระหว่างผู้เล่น
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- กฎเหล็กข้อเดียวของไฟล์นี้: **เงินของผู้ประมูลห้ามหายไปอยู่ในสุญญากาศ**
--
-- วิธีที่ผิดและคนทำกันบ่อย: หักเงินคนประมูลเข้ากระเป๋ากลาง แล้วคืนตอนแพ้
--   ถ้าเซิร์ฟล่มตอนนั้นพอดี เงินจะค้างอยู่ในกระเป๋ากลางที่ไม่มีเจ้าของ
--   และ invariant ของ ledger (ผลรวมทุกบัญชี = 0) จะยังเป็น 0 อยู่
--   แปลว่าเทสจับไม่ได้ แต่ผู้เล่นเสียเงินจริง
--
-- วิธีที่ใช้: escrow ของ Akacount (hold / release / capture)
--   hold    = เงินยังเป็นของเขา แต่ใช้จ่ายไม่ได้
--   release = ปลดล็อก (แพ้ประมูล)
--   capture = ตัดจริง (ชนะ)
--   ทั้งสามอันเป็น operation ของ ledger ที่บาลานซ์ในตัวเอง
--
-- อีกกฎ: ไอเทมของคนขายถูก "ยึด" ตั้งแต่ตอนลงขาย ไม่ใช่ตอนขายได้
--   ไม่งั้นคนขายเอาของไปทิ้ง/ขายที่อื่น แล้วคนชนะจ่ายเงินไปได้ลม
--
-- ประมูลใช้ CASH สกุลเดียว  ตั้งใจแบบนั้น
--   ประมูลข้ามสกุลต้องมีอัตราแลกเปลี่ยน ซึ่งเราตัดสินใจไปแล้วว่าจะไม่มี
-- ==============================================================================
require("Kuraya/KR_Const")

-- ==============================================================================
-- ทำไมต้อง require KR_Server ตรงนี้  (บั๊กที่ทำให้ประมูลตายมาตลอด ถึง 0.3.2)
--
-- PZ เดินโฟลเดอร์ media/lua/server/ แล้วโหลดไฟล์ "เรียงตามตัวอักษร"
--     KR_Auction  <  KR_Credit  <  KR_Server  <  KR_TownRank
-- ไฟล์นี้จึงรันก่อน KR_Server เสมอ  KR.server ยังไม่มี  แล้ว return ทิ้งเงียบ ๆ
-- ผลที่ผู้เล่นเห็นคือ "That feature is not loaded on this server." ทุกครั้งที่กดประมูล
-- ยืนยันจาก console.txt ของเซิร์ฟจริง:
--     [Kuraya] KR_Auction  v0.3.2
--     [Kuraya] !! KR_Auction loaded before KR_Server - auctions disabled
--
-- ทำไมเทส 70 ข้อของประมูลถึงเขียวมาตลอด: tests/test_auction.lua เขียน
--     require("Kuraya/KR_TownRank"); require("Kuraya/KR_Server"); require("Kuraya/KR_Auction")
-- คือ **สั่งลำดับเอง** ซึ่งไม่ใช่ลำดับที่เกมใช้  เทสจึงทดสอบโลกที่ไม่มีอยู่จริง
--
-- แก้โดยประกาศ dependency ตรง ๆ แทนที่จะหวังพึ่งชื่อไฟล์
-- แพตเทิร์นเดียวกับที่ KR_Server ใช้ require KR_TownRank อยู่แล้ว (ซึ่งอยู่หลังมัน
-- ตามตัวอักษรเหมือนกัน และทำงานได้จริงบนเซิร์ฟมาตลอด)
-- KR_Server มียามกันโหลดซ้ำอยู่หัวไฟล์ เรียกซ้ำจึงไม่ผูก event สองรอบ
-- ==============================================================================
require("Kuraya/KR_Server")

print("[Kuraya] KR_Auction  v" .. KR.VERSION)

local S = KR.server
if not S then
    -- ถึงตรงนี้ไม่ได้แล้วหลัง 0.3.3  ถ้าเห็นบรรทัดนี้ใน console แปลว่า
    -- KR_Server.lua โหลดไม่ผ่าน (พังตั้งแต่ในไฟล์มัน) ไม่ใช่เรื่องลำดับไฟล์
    print("[Kuraya] !! KR_Auction: KR_Server failed to load - auctions disabled")
    return
end

local db, key, bank, alert, P = S.db, S.key, S.bank, S.alert, S.P

-- ------------------------------------------------------------------------------
-- ด่านเดียวของทั้งไฟล์  ระบบประมูลเปิดอยู่ไหม
--
-- **ต้องอยู่ฝั่งเซิร์ฟด้วย ไม่ใช่แค่จอไม่วาดปุ่ม**
-- ไคลเอนต์ที่ถูกแก้ยิง AuctSell / AuctBid มาได้ตลอดเวลา การซ่อนปุ่มคือมารยาท
-- ไม่ใช่การปิดระบบ  หลักเดียวกับที่ของที่ซ่อนไว้ต้องไม่ออกจากเซิร์ฟตั้งแต่ต้น
--
-- ตัวจับเวลา (auctionTick) ยังเดินตามปกติ  ล็อตที่ค้างอยู่กับเงินมัดจำที่ค้างอยู่
-- ต้องได้รับการดูแลต่อจนจบ ไม่ใช่ถูกแช่แข็งไปพร้อมกับการปิดระบบ
local function auctionOff(player)
    if KR.auctionOpen() then return false end
    if player then
        alert(player, "Auctions are not open on this server yet.", "bad")
    end
    return true
end

-- ------------------------------------------------------------------------------
-- ตัวช่วย
-- ------------------------------------------------------------------------------
local function A()
    local d = db()
    d.auction = d.auction or { lots = {}, next = 1 }
    d.auction.lots = d.auction.lots or {}
    return d.auction
end

local function nowOf()
    return getTimestamp and getTimestamp() or os.time()
end

local function dispOf(k)
    if not k then return "someone" end
    return (P(k).disp) or k
end

-- ปล่อยเงินที่พักไว้ของคนที่แพ้  ต้องทนต่อการที่ Akacount ไม่อยู่
-- ถ้าปล่อยไม่ได้ ห้ามลบ holdId ทิ้ง  เก็บไว้ให้แอดมินตามเก็บได้
local function releaseHold(lot)
    if not lot or not lot.hold then return true end
    local B = bank()
    if not B or not B.releaseHold then return false end
    local ok = pcall(B.releaseHold, lot.hold)
    if ok then
        lot.hold = nil
        return true
    end
    return false
end

-- ------------------------------------------------------------------------------
-- ประวัติการบิดของแต่ละล็อต  "ช่องแชทสด" ที่คนขายเฝ้าดูได้
--
-- ทำไมต้องเก็บ ทั้งที่ราคาปัจจุบันก็บอกอยู่แล้ว
--   ราคาบอกแค่ "ตอนนี้เท่าไร" แต่สิ่งที่ทำให้ประมูลมีชีวิตคือ **จังหวะ**
--   ใครสู้กับใคร ห่างกันกี่วินาที ใครถอย  ตัวเลขเดี่ยว ๆ ไม่มีข้อมูลนั้นเลย
--   คนขายที่เห็นแต่เลขนิ่ง ๆ ไม่มีทางรู้ว่าล็อตกำลังคึกหรือกำลังตาย
--
-- เก็บเป็น ring buffer ต่อล็อต ไม่ใช่ก้อนกลาง
--   ล็อตถูกลบเมื่อไร ประวัติหายตามไปเอง ไม่ต้องมีใครไล่เก็บกวาด
--
-- ห้ามเก็บ holdId หรือคีย์ผู้เล่นดิบลงในนี้  ทั้งก้อนถูกส่งออกไปให้ไคลเอนต์
-- เก็บเฉพาะ "ชื่อที่โชว์ได้" เท่านั้น
-- ------------------------------------------------------------------------------
local LOG_MAX = 24

-- ราคาขั้นต่ำครั้งถัดไป
--
-- ผู้ขายตั้ง "บิดละเท่าไร" ได้เอง  ถ้าไม่ตั้งก็ตกไปใช้เปอร์เซ็นต์ของเซิร์ฟตามเดิม
-- ขั้นบิดที่คนขายคุมเองสำคัญกับของถูก: ของราคา 100 ที่ขยับทีละ 5% คือขยับทีละ 5
-- ซึ่งทำให้ล็อตจบช้ามากและน่าเบื่อ
function S.nextBidOf(lot)
    if lot and lot.step and lot.step > 0 then
        if (lot.bids or 0) == 0 then return lot.start or lot.bid end
        return (lot.bid or 0) + lot.step
    end
    return KR.nextBid(lot)
end

local function lotLog(lot, kind, who, amt, ts)
    lot.log = lot.log or {}
    lot.log[#lot.log + 1] = { t = ts, k = kind, who = who, a = amt }
    while #lot.log > LOG_MAX do table.remove(lot.log, 1) end
end

-- ------------------------------------------------------------------------------
-- เปิดประมูล
--
-- ตั้งแต่ 0.5 ล็อตไม่ผูกกับไอเทมแล้ว  ระบบดูแลเฉพาะเงิน ของนัดรับกันเอง
-- (เหตุผลเต็ม ๆ อยู่ในตัวฟังก์ชัน S.auctSell ด้านล่าง)
--
-- ตั้งแต่ 0.4.1 ผู้เล่นลงขายเองได้  รูที่เคยทำให้ต้องปิดถูกอุดแล้ว
-- ของถูกยึดออกจากกระเป๋าตั้งแต่วินาทีที่กดลงขาย ไม่ใช่ตอนขายได้ (ดูใน S.auctSell)
-- ธงยังอยู่ที่ sandbox AuctionPlayerSell เผื่อเซิร์ฟไหนอยากกลับไปเป็นห้องประมูลของแอดมินล้วน
-- ------------------------------------------------------------------------------
local function playerSellAllowed()
    -- ค่าท้ายต้องตรงกับ default ในไฟล์ sandbox เสมอ  ใช้เฉพาะตอนเซิร์ฟไม่ได้ตั้งมาเลย
    return KR.svBool("AuctionPlayerSell", true)
end

-- ไคลเอนต์ต้องรู้ว่าเซิร์ฟนี้เปิดให้ผู้เล่นลงขายไหม  ไม่งั้นมันวาดปุ่ม "เปิดล็อตใหม่"
-- ให้ทุกคนแล้วครึ่งหนึ่งกดไปโดนคำปฏิเสธ  ปุ่มที่กดแล้วโดนด่าคือปุ่มที่ไม่ควรมี
function S.auctSellAllowed()
    if not KR.auctionOpen() then return false end
    return playerSellAllowed()
end

-- ------------------------------------------------------------------------------
-- ช่องประมูลที่คนนี้มี  ฟรีหนึ่ง บวกที่ซื้อเพิ่ม
-- ------------------------------------------------------------------------------
function S.auctSlots(k)
    if not k then return 0 end
    local extra = math.max(0, math.floor(tonumber(P(k).slots) or 0))
    return math.floor(KR.auctSlotOpt("FREE")) + extra
end

-- ซื้อช่องถาวรเพิ่มหนึ่งช่อง  ผู้เล่นกดเองได้ ไม่ต้องรอแอดมิน
function S.auctBuySlot(player, args)
    if auctionOff(player) then return end
    local k = key(player); if not k then return end
    if S.frozenBlock and S.frozenBlock(player, "the auction") then return end

    local have = S.auctSlots(k)
    local cap  = math.floor(KR.auctSlotOpt("MAX"))
    if have >= cap then
        return alert(player, "You already have the maximum of " .. cap .. " slots.", "bad")
    end

    local price = math.floor(KR.auctSlotOpt("PRICE"))
    local B = bank()
    if not B or not B.charge then return alert(player, "The bank is offline.", "bad") end
    if B.available and (B.available(k) or 0) < price then
        return alert(player, "An extra slot costs " ..
                     KR.fmtPrice(KR.CUR.CASH, price / KR.SUBUNIT) ..
                     ". You do not have that in your account.", "bad")
    end

    -- ตัดเงินก่อน แล้วค่อยให้ของ  ลำดับนี้ห้ามสลับ
    -- ให้ของก่อนแล้วตัดเงินไม่ผ่าน = แจกช่องฟรี ซึ่งย้อนคืนยากกว่าการคืนเงินมาก
    local okPay = pcall(B.charge, k, price, "shop", "auction slot", "card")
    if not okPay then
        return alert(player, "The bank refused the payment. Nothing was bought.", "bad")
    end

    local row = P(k)
    row.slots = math.max(0, math.floor(tonumber(row.slots) or 0)) + 1
    if S.logEvent then
        S.logEvent(k, KR.LOG.BUY, KR.L("ซื้อช่องประมูล", "Auction slot"),
                   price, KR.CUR.CASH, false, "permanent")
    end
    alert(player, "Slot bought. You can now run " .. S.auctSlots(k) .. " lots at once.", "good")
    S.sync(player)
end

function S.auctSell(player, args)
    if auctionOff(player) then return end
    local k = key(player); if not k then return end
    if not playerSellAllowed() and not S.isAdmin(player) then
        return alert(player, "Player selling is off on this server. Ask an admin to list it.", "bad")
    end

    local a    = A()
    local name = KR.trunc(tostring((args and args.name) or ""), 40)
    if name == "" then return alert(player, "Give the lot a name.", "bad") end

    local start = math.floor(tonumber(args and args.start) or 0)
    if start <= 0 then return alert(player, "Starting price must be above zero.", "bad") end

    -- ระยะเวลาเป็น "นาที" ตั้งแต่ 0.6.0
    --
    -- ยังรับ args.hours ของไคลเอนต์รุ่นเก่าอยู่ เพราะระหว่างที่ผู้เล่นทยอยอัปเดต
    -- จะมีช่วงที่จอเก่ากับเซิร์ฟใหม่คุยกัน  ถ้าตัดทิ้งเลย จอเก่าจะเปิดล็อตไม่ได้เลย
    -- โดยได้ข้อความ "ต้องอยู่ระหว่าง 60 ถึง 10080 นาที" ทั้งที่เขากรอก 6 ไปตามที่จอบอก
    --
    -- ขอบเขตยังคิดเป็นชั่วโมงตาม sandbox option เดิม แล้วคูณ 60 ตอนเทียบ
    -- ไม่ได้เปลี่ยนชื่อ option เพราะเซิร์ฟที่ตั้งค่าไว้แล้วจะเสียค่าที่ตั้งไป
    local mins = tonumber(args and args.mins)
    if not mins then
        local hr = tonumber(args and args.hours)
        mins = hr and (hr * 60) or 0
    end
    mins = math.floor(mins)

    local lo = math.floor(KR.auctOpt("MIN_HOURS") * 60)
    local hi = math.floor(KR.auctOpt("MAX_HOURS") * 60)
    if mins < lo or mins > hi then
        return alert(player, "Duration must be between " .. lo .. " and " .. hi ..
                             " minutes (" .. KR.auctOpt("MIN_HOURS") .. "-" ..
                             KR.auctOpt("MAX_HOURS") .. " hours).", "bad")
    end

    -- ช่องประมูล
    --
    -- ทุกคนได้ฟรีหนึ่งช่อง อยากเปิดพร้อมกันหลายล็อตต้องซื้อช่องถาวรเพิ่ม
    -- ตั้งใจให้เป็นของที่ซื้อครั้งเดียวใช้ตลอด ไม่ใช่ค่าเช่ารายรอบ
    -- ค่าเช่ารายรอบทำให้คนที่หยุดเล่นไปเดือนหนึ่งกลับมาแล้วเสียของที่ซื้อไปแล้ว
    -- ซึ่งเป็นความรู้สึกที่แย่ที่สุดที่ระบบซื้อขายจะให้ได้
    local slots = S.auctSlots(k)
    local mine = 0
    for _, lot in pairs(a.lots) do
        if lot.seller == k and not lot.done then mine = mine + 1 end
    end
    if mine >= slots then
        return alert(player, "You are using all " .. slots ..
                     (slots == 1 and " of your auction slots. Buy another one to run more than one lot at a time."
                                  or " of your auction slots. Buy another to run more."), "bad")
    end

    -- ========================================================================
    -- ล็อตไม่ผูกกับไอเทมอีกแล้ว  (0.5)
    --
    -- เจ้าของเซิร์ฟตัดสินใจว่า "ตอนลงเราไม่ได้ให้เอาของเข้ามาผูก แต่พวกเขาจะไปนัดรับกันเอง"
    -- ซึ่งถูกกับเกมนี้มากกว่าที่เราทำไว้ใน 0.4.1
    --
    -- ของใน PZ มีสภาพ กระสุน ความคม และบางอย่างเป็นภาชนะที่มีของอยู่ข้างใน
    -- ระบบที่ยึดของแล้ว "เสกคืน" ทำสิ่งเหล่านั้นหายหมด ปืนที่ยิงมาครึ่งแม็กกลับมาเต็มแม็ก
    -- กระเป๋าที่มีของอยู่ข้างในกลับมาเป็นกระเป๋าเปล่า
    -- การให้คนไปเจอกันเองรักษาของไว้ได้ครบ และเป็นสิ่งที่คนในเซิร์ฟทำกันอยู่แล้ว
    --
    -- ระบบจึงดูแลอย่างเดียวคือ **เงิน** ซึ่งเป็นสิ่งที่โกงกันได้จริง
    -- ส่วนของนั้นสองฝ่ายรับผิดชอบกันเอง เหมือนซื้อขายนอกระบบที่ทำกันอยู่ทุกวัน
    -- ========================================================================
    local step = math.floor(tonumber(args and args.step) or 0)
    if step < 0 then step = 0 end

    local buy = math.floor(tonumber(args and args.buy) or 0)
    if buy > 0 and buy <= start then
        return alert(player, "Buy now has to be above the starting price.", "bad")
    end

    local art = tostring((args and args.art) or "")
    if not KR.auctArtOk(art) then art = KR.AUCT_ART_DEFAULT end
    local bg = tostring((args and args.bg) or "")
    if not KR.auctBgOk(bg) then bg = KR.AUCT_BG_DEFAULT end

    local ts = nowOf()
    local id = "L" .. tostring(a.next or 1)
    a.next = (a.next or 1) + 1

    local isAdm = S.isAdmin(player)

    local lot = {
        id     = id,
        name   = name,
        seller = k,
        -- official = ร้านเป็นคนลง  ไคลเอนต์ปักการ์ดแดงไว้บนสุด
        official = isAdm or nil,
        art    = art,
        bg     = bg,
        start  = start,
        bid    = start,
        step   = step > 0 and step or nil,
        buy    = buy > 0 and buy or nil,
        bids   = 0,
        top    = nil,
        hold   = nil,
        endsAt = ts + mins * 60,
        listedAt = ts,
    }
    a.lots[id] = lot
    lotLog(lot, "open", dispOf(k), start, ts)

    alert(player, "Lot listed: " .. name, "good")
    S.syncAll()
end

-- ------------------------------------------------------------------------------
-- ประมูล
--
-- ลำดับสำคัญมาก และมันคือจุดที่พังง่ายที่สุดในทั้งไฟล์:
--   1. พักเงินของคนใหม่ก่อน
--   2. ถ้าพักสำเร็จ ค่อยปล่อยเงินของคนเก่า
-- ห้ามสลับ  ถ้าปล่อยของเก่าก่อนแล้วพักของใหม่ไม่สำเร็จ
-- lot จะกลายเป็นไม่มีใครถือเงินไว้เลย ทั้งที่ยังมีราคาค้างอยู่
-- ------------------------------------------------------------------------------
function S.auctBid(player, args)
    if auctionOff(player) then return end
    local k = key(player); if not k then return end
    local a  = A()
    local id = args and args.id
    local lot = id and a.lots[id]
    if not lot then return alert(player, "That lot is gone.", "bad") end

    -- คนที่โดนแช่แข็งเพราะหนี้ประมูลไม่ได้  ด่านเดียวกับหน้าร้าน
    -- ถ้าไม่กันตรงนี้ ประมูลจะกลายเป็นทางอ้อมที่ทำให้การแช่แข็งไม่มีความหมาย
    if S.frozenBlock and S.frozenBlock(player, "the auction") then return end

    local ts = nowOf()
    if KR.auctionClosed(lot, ts) then return alert(player, "That lot has ended.", "bad") end
    if lot.seller == k then return alert(player, "You cannot bid on your own lot.", "bad") end
    if lot.top == k then return alert(player, "You are already the top bidder.", "info") end

    -- ราคาประมูลเดินเป็นสตางค์ทั้งสาย (holdForPurchase / available ก็หน่วยนี้)
    -- แต่ KR.fmtPrice รับ "บาท" แล้วเติมทศนิยมสองตำแหน่งให้เอง
    -- ยัดสตางค์เข้าไปตรง ๆ ป้ายจะขึ้น "$ 10000.00" ตอนที่ราคาจริงคือ $ 100.00
    -- จึงหารด้วย KR.SUBUNIT ที่จุดเรียกทุกครั้ง  ไม่แตะตัวเลขที่ใช้คำนวณจริง
    local want = math.floor(tonumber(args and args.n) or 0)
    local need = S.nextBidOf(lot)
    if want < need then
        return alert(player, "Bid at least " ..
                     KR.fmtPrice(KR.CUR.CASH, need / KR.SUBUNIT) .. ".", "bad")
    end

    local B = bank()
    if not B or not B.holdForPurchase then
        return alert(player, "The bank is offline, bidding is closed.", "bad")
    end
    if B.isLocked and B.isLocked(k) then
        return alert(player, "Your account is frozen.", "bad")
    end
    if B.available and B.available(k) < want then
        return alert(player, "Not enough in your account.", "bad")
    end

    -- 1. พักเงินคนใหม่
    local okHold, newHold = pcall(B.holdForPurchase, k, want, "auction:" .. id)
    if not okHold or not newHold then
        return alert(player, "Could not hold your money, bid not placed.", "bad")
    end

    -- 2. คนเก่าได้เงินคืน  ทำหลังเสมอ
    local prevK, prevHold = lot.top, lot.hold
    lot.hold = newHold
    lot.top  = k
    lot.bid  = want
    lot.bids = (lot.bids or 0) + 1

    if prevHold then
        local okRel = pcall(B.releaseHold, prevHold)
        if not okRel then
            -- ปล่อยไม่ได้  จดไว้ให้แอดมินเก็บกวาด ห้ามเงียบ
            lot.stuck = lot.stuck or {}
            lot.stuck[#lot.stuck + 1] = { who = prevK, hold = prevHold }
            print("[Kuraya] !! could not release hold " .. tostring(prevHold) ..
                  " for " .. tostring(prevK) .. " on lot " .. id)
        end
    end

    -- บันทึกลงช่องสด **ก่อน** ต่อเวลา  ลำดับนี้ตั้งใจ
    -- ถ้าบันทึกทีหลัง แถวที่ขึ้นว่า "ต่อเวลา" จะมาก่อนแถวที่ทำให้ต่อเวลา ซึ่งอ่านแล้วงง
    lotLog(lot, "bid", dispOf(k), want, ts)

    -- ประมูลท้ายเกม = ต่อเวลา  กันคนกดวินาทีสุดท้ายแล้วจบเลย
    local left = KR.auctionLeft(lot, ts)
    local anti = KR.auctOpt("ANTISNIPE")
    if left < anti then
        lot.endsAt = ts + anti
        lot.extended = (lot.extended or 0) + 1
        lotLog(lot, "ext", nil, anti, ts)
    end

    -- คนที่เพิ่งโดนแซงต้องรู้ตัว **ทันที** ไม่ใช่มารู้ตอนล็อตปิดแล้วว่าแพ้
    -- นี่คือครึ่งหนึ่งของสิ่งที่ทำให้ประมูลเป็นประมูล  เงินเขาถูกปล่อยคืนไปแล้วด้วย
    -- ส่งเฉพาะตอนที่เขาออนไลน์อยู่  ออฟไลน์อยู่ก็ยังเห็นย้อนหลังในช่องสดอยู่ดี
    if prevK and prevK ~= k then
        local pp = S.onlineByKey and S.onlineByKey(prevK) or nil
        if pp then
            alert(pp, "You were outbid on " .. tostring(lot.name) .. " - now " ..
                      KR.fmtPrice(KR.CUR.CASH, want / KR.SUBUNIT) ..
                      ". Your money was released.", "info")
        end
    end

    S.feedPush(KR.FEED.BID, dispOf(k), lot.name)
    alert(player, "Bid placed: " .. KR.fmtPrice(KR.CUR.CASH, want / KR.SUBUNIT), "good")

    -- ซื้อทันที  ถึงราคาที่ผู้ขายตั้งไว้แล้วจบเลย ไม่ต้องรอหมดเวลา
    --
    -- ทำโดยดึงเวลาจบมาไว้ตอนนี้ แล้วปล่อยให้ auctionTick ปิดล็อตตามทางเดิม
    -- ไม่เขียนทางปิดล็อตทางที่สอง  ทางที่สองคือทางที่ไม่มีใครแก้ตอนเจอบั๊ก
    if lot.buy and want >= lot.buy then
        lot.endsAt = ts
        lotLog(lot, "buynow", dispOf(k), want, ts)
        S.auctionTick(ts)
        return
    end

    S.syncAll()
end

-- ------------------------------------------------------------------------------
-- ยกเลิกล็อตของตัวเอง  ทำได้เฉพาะตอนยังไม่มีใครประมูล
-- มีคนประมูลแล้วยกเลิกได้ = คนขายเอาไว้หลอกดันราคาแล้วถอนได้
-- ------------------------------------------------------------------------------
function S.auctCancel(player, args)
    if auctionOff(player) then return end
    local k = key(player); if not k then return end
    local a = A()
    local lot = args and args.id and a.lots[args.id]
    if not lot then return alert(player, "That lot is gone.", "bad") end
    if lot.seller ~= k and not S.isAdmin(player) then
        return alert(player, "That is not your lot.", "bad")
    end
    if (lot.bids or 0) > 0 and not S.isAdmin(player) then
        return alert(player, "Someone already bid. You cannot pull it now.", "bad")
    end

    -- ปล่อยเงินที่พักไว้ของคนที่บิดค้างอยู่ก่อนเสมอ
    -- ล็อตหายไปพร้อมเงินที่ยังถูกกันไว้ = เงินของคนอื่นค้างอยู่ในสุญญากาศตลอดกาล
    releaseHold(lot)
    if lot.hold then
        return alert(player, "Could not release the current bidder's money. Try again in a moment.", "bad")
    end

    a.lots[lot.id] = nil
    alert(player, "Lot removed.", "good")
    S.syncAll()
end

-- ------------------------------------------------------------------------------
-- ปิดล็อตที่หมดเวลา
--
-- เรียกจาก S.sync  วิ่งบ่อยแต่ทำงานจริงเฉพาะล็อตที่หมดเวลาแล้ว
-- ใช้ตัวจับเวลาไม่ได้ เพราะเซิร์ฟที่ปิดข้ามคืนจะไม่มีใครมาปิดล็อตให้
-- ------------------------------------------------------------------------------
function S.auctionTick(ts)
    ts = ts or nowOf()
    local a = A()
    local B = bank()
    local changed = false

    for id, lot in pairs(a.lots) do
        -- ==================================================================
        -- ปิดล็อต  เก็บมัดจำครึ่งเดียว
        --
        -- คนขายยังไม่ได้เงินตรงนี้  เงินค้างอยู่ที่ระบบจนกว่าผู้ชนะจะจ่ายส่วนที่เหลือ
        -- เพราะของยังไม่ได้ส่ง การจ่ายเต็มก่อนเจอตัวคนขายคือการบังคับให้ผู้ซื้อเชื่อใจฝ่ายเดียว
        --
        -- ลำดับสำคัญ: ปล่อยเงินที่พักไว้ทั้งก้อนก่อน แล้วค่อยตัดครึ่ง
        -- ถ้าตัดก่อนปล่อย ยอดที่ใช้ได้ของเขายังถูกกันไว้เต็มจำนวนอยู่ การตัดจะไม่ผ่าน
        -- ทั้งสองบรรทัดอยู่ในเทิร์นเดียวกัน ไม่มี yield คั่น จึงไม่มีใครแทรกกลางได้
        -- ==================================================================
        if not lot.done and KR.auctionLeft(lot, ts) <= 0 then
            lot.done   = true
            lot.doneAt = ts
            changed    = true

            if lot.top and B then
                releaseHold(lot)

                local dep = KR.auctDeposit(lot.bid)
                local okDep = false
                if B.charge and dep > 0 then
                    okDep = pcall(B.charge, lot.top, dep, "shop",
                                  "auction deposit " .. tostring(lot.name), "card")
                end

                if okDep then
                    lot.deposit = dep
                    lot.rest    = math.max(0, lot.bid - dep)
                    lot.payBy   = ts + math.floor(KR.auctPayOpt("WINDOW"))
                    lotLog(lot, "won", dispOf(lot.top), lot.bid, ts)
                    S.feedPush(KR.FEED.WIN, dispOf(lot.top), lot.name)

                    if S.logEvent then
                        S.logEvent(lot.top, KR.LOG.AUCT,
                                   KR.L("มัดจำ ", "Deposit on ") .. tostring(lot.name),
                                   dep, KR.CUR.CASH, false, "50%")
                    end

                    local pw = S.onlineByKey and S.onlineByKey(lot.top) or nil
                    if pw then
                        alert(pw, "You won " .. tostring(lot.name) .. ". " ..
                                  KR.fmtPrice(KR.CUR.CASH, dep / KR.SUBUNIT) ..
                                  " was taken as a deposit. Pay the rest within 24 hours " ..
                                  "on the AUCTION page or it is refunded and the deal is off.", "good")
                    end
                    local ps = S.onlineByKey and S.onlineByKey(lot.seller) or nil
                    if ps then
                        alert(ps, tostring(lot.name) .. " sold for " ..
                                  KR.fmtPrice(KR.CUR.CASH, lot.bid / KR.SUBUNIT) ..
                                  ". You get paid once the winner settles the balance.", "good")
                    end
                else
                    -- เก็บมัดจำไม่ได้  ถือว่าไม่มีการขาย ไม่มีใครเสียอะไร
                    lot.failed = true
                    lotLog(lot, "fail", nil, 0, ts)
                    print("[Kuraya] !! deposit failed on lot " .. tostring(id))
                    local pw = S.onlineByKey and S.onlineByKey(lot.top) or nil
                    if pw then
                        alert(pw, "You won " .. tostring(lot.name) ..
                                  " but the deposit could not be taken. The sale is off.", "bad")
                    end
                end
            else
                -- ไม่มีใครประมูล  ล็อตหมดอายุเฉย ๆ
                releaseHold(lot)
                lotLog(lot, "end", nil, 0, ts)
            end
        end

        -- ==================================================================
        -- ผู้ชนะไม่จ่ายส่วนที่เหลือใน 24 ชม.จริง
        --
        -- คืนมัดจำเต็มจำนวนตามที่เจ้าของเซิร์ฟสั่ง  คนขายไม่ได้อะไร
        -- ตั้งใจไม่ยึดมัดจำ เพราะระบบไม่ได้ถือของไว้เป็นหลักประกันให้ทั้งสองฝ่าย
        -- ยึดเงินฝ่ายเดียวโดยที่อีกฝ่ายไม่เคยต้องพิสูจน์ว่ามีของอยู่จริง ไม่ยุติธรรม
        -- ==================================================================
        if lot.done and lot.payBy and not lot.settled and not lot.refunded
           and ts > lot.payBy then
            local dep = math.max(0, math.floor(tonumber(lot.deposit) or 0))
            if dep > 0 and B and B.payTo then
                pcall(B.payTo, "SYS:AUCTION", lot.top, dep, "shop",
                      "auction refund " .. tostring(lot.name), "system")
                if S.logEvent then
                    S.logEvent(lot.top, KR.LOG.AUCT,
                               KR.L("คืนมัดจำ ", "Deposit back ") .. tostring(lot.name),
                               dep, KR.CUR.CASH, true, "expired")
                end
            end
            lot.refunded = true
            changed = true
            local pw = S.onlineByKey and S.onlineByKey(lot.top) or nil
            if pw then
                alert(pw, "You did not settle " .. tostring(lot.name) ..
                          " in time. Your deposit came back in full.", "info")
            end
            local ps = S.onlineByKey and S.onlineByKey(lot.seller) or nil
            if ps then
                alert(ps, tostring(lot.name) .. " fell through - the winner never paid. " ..
                          "Nothing changed hands.", "bad")
            end
        end

        -- ==================================================================
        -- เก็บกวาด
        --
        -- "ทุกการประมูลที่จบลงจะลบออกอัตโนมัติ" ตามที่สั่ง
        -- ล็อตที่จบแล้วเก็บไว้แค่พอให้คนที่ออนไลน์อยู่ได้เห็นว่ามันจบยังไง
        -- แต่ห้ามลบล็อตที่ยังมีเงินค้างอยู่ในระบบ ไม่ว่ากรณีใด
        -- ==================================================================
        if lot.done then
            local settled = lot.settled or lot.refunded or lot.failed or (not lot.top)
            local age     = ts - (lot.doneAt or ts)
            if settled and age > KR.DAY_SEC then
                if lot.hold then releaseHold(lot) end
                if not lot.hold then
                    a.lots[id] = nil
                    changed = true
                end
            end
        end
    end
    return changed
end

-- ------------------------------------------------------------------------------
-- ผู้ชนะจ่ายส่วนที่เหลือ  คนขายได้เงินตรงนี้ที่เดียว
-- ------------------------------------------------------------------------------
function S.auctPay(player, args)
    if auctionOff(player) then return end
    local k = key(player); if not k then return end
    local a = A()
    local lot = args and args.id and a.lots[args.id]
    if not lot then return alert(player, "That lot is gone.", "bad") end
    if lot.top ~= k then return alert(player, "You did not win that lot.", "bad") end
    if lot.settled then return alert(player, "You already paid this one.", "info") end
    if lot.refunded then
        return alert(player, "That one already expired and your deposit came back.", "bad")
    end
    if not lot.done or not lot.payBy then
        return alert(player, "That lot has not ended yet.", "bad")
    end

    local rest = math.max(0, math.floor(tonumber(lot.rest) or 0))
    local B = bank()
    if not B or not B.charge then return alert(player, "The bank is offline.", "bad") end
    if rest > 0 then
        if B.available and (B.available(k) or 0) < rest then
            return alert(player, "You need " .. KR.fmtPrice(KR.CUR.CASH, rest / KR.SUBUNIT) ..
                                 " to settle this.", "bad")
        end
        local okPay = pcall(B.charge, k, rest, "shop",
                            "auction balance " .. tostring(lot.name), "card")
        if not okPay then
            return alert(player, "The bank refused the payment. Nothing was taken.", "bad")
        end
    end

    -- คนขายได้เงินเต็มจำนวนหักค่าธรรมเนียม  จ่ายตรงนี้ที่เดียวในทั้งไฟล์
    local ts   = nowOf()
    local fee  = KR.auctionFee(lot.bid)
    local net  = math.max(0, lot.bid - fee)
    lot.fee, lot.net = fee, net
    lot.settled = true
    lot.sold    = true

    if B.payTo then
        pcall(B.payTo, "SYS:AUCTION", lot.seller, net, "shop",
              "auction " .. tostring(lot.name), "system")
    end

    if S.logEvent then
        S.logEvent(k, KR.LOG.AUCT, KR.L("จ่ายส่วนที่เหลือ ", "Balance on ") .. tostring(lot.name),
                   rest, KR.CUR.CASH, false)
        S.logEvent(lot.seller, KR.LOG.SALE, KR.L("ขายได้ ", "Sold ") .. tostring(lot.name),
                   net, KR.CUR.CASH, true,
                   fee > 0 and ("fee " .. KR.fmtPrice(KR.CUR.CASH, fee / KR.SUBUNIT)) or nil)
    end

    lotLog(lot, "paid", dispOf(k), lot.bid, ts)
    alert(player, "Paid in full. Go and meet " .. dispOf(lot.seller) .. " to collect.", "good")

    local ps = S.onlineByKey and S.onlineByKey(lot.seller) or nil
    if ps then
        alert(ps, dispOf(k) .. " paid for " .. tostring(lot.name) .. " in full. " ..
                  KR.fmtPrice(KR.CUR.CASH, net / KR.SUBUNIT) ..
                  " is in your account - hand the goods over.", "good")
    end
    S.syncAll()
end

-- ------------------------------------------------------------------------------
-- ไม่มี auctClaim อีกแล้ว
--
-- ล็อตไม่ได้ผูกกับไอเทม  จึงไม่มี "ของ" ให้มารับจากระบบ
-- ผู้ชนะจ่ายครบแล้วไปนัดเจอคนขายเอง  คำสั่งที่เหลือคือ S.auctPay อย่างเดียว
--
-- ตัวคำสั่ง AUCT_CLAIM ยังลงทะเบียนอยู่เพื่อรับไคลเอนต์รุ่นเก่าที่ยังยิงมา
-- แต่มันตอบกลับไปว่าให้ไปกดปุ่มจ่ายเงินแทน  ไม่ปล่อยให้กดแล้วเงียบ
-- ------------------------------------------------------------------------------
function S.auctClaim(player, args)
    if auctionOff(player) then return end
    return alert(player, "Lots do not hold items any more. Press Pay balance instead, " ..
                         "then meet the seller in person.", "info")
end

-- ------------------------------------------------------------------------------
-- ส่งให้ไคลเอนต์
--
-- ส่งเฉพาะสิ่งที่ผู้เล่นคนนี้ควรเห็น
-- ห้ามส่ง holdId ออกไป มันเป็นของภายในของ ledger
-- ------------------------------------------------------------------------------
function S.auctionRows(player, ts)
    local k = key(player)
    ts = ts or nowOf()
    local a = A()
    local rows = {}

    for id, lot in pairs(a.lots) do
        -- "เคยร่วมประมูลล็อตนี้ไหม"  ต้องอ่านจากประวัติ ไม่ใช่จากการเป็นผู้นำอยู่ตอนนี้
        --
        -- ของเดิมเขียน iBid = (lot.top == k) ซึ่งแปลว่า **แท็บ My bids จะว่างทันที
        -- ที่โดนใครแซง** ทั้งที่นั่นคือช่วงเวลาที่คนอยากเปิดดูมากที่สุดในทั้งรอบ
        local joined = (lot.top == k) or nil
        if not joined and lot.log then
            for i = 1, #lot.log do
                local e = lot.log[i]
                if e.k == "bid" and e.who == dispOf(k) then joined = true; break end
            end
        end

        rows[#rows + 1] = {
            id      = id,
            name    = lot.name,
            art     = lot.art or KR.AUCT_ART_DEFAULT,   -- รูปปกที่ผู้ขายเลือก
            bg      = lot.bg  or KR.AUCT_BG_DEFAULT,    -- สีพื้นการ์ด
            seller  = dispOf(lot.seller),
            mine    = (lot.seller == k) or nil,
            bid     = lot.bid,
            bids    = lot.bids or 0,
            top     = lot.top and dispOf(lot.top) or nil,
            iAmTop  = (lot.top == k) or nil,
            iBid    = joined,
            next    = S.nextBidOf(lot),
            step    = lot.step,
            buy     = lot.buy,
            left    = KR.auctionLeft(lot, ts),
            done    = lot.done or nil,
            sold    = lot.sold or nil,
            official= lot.official or nil,   -- ล็อตของร้าน  ไคลเอนต์ปักไว้บนสุด
            failed  = lot.failed or nil,
            -- การชำระสองรอบ  จอต้องรู้ว่าตอนนี้อยู่ขั้นไหน
            deposit = lot.deposit,
            rest    = lot.rest,
            payIn   = (lot.payBy and not lot.settled and not lot.refunded)
                      and math.max(0, lot.payBy - ts) or nil,
            settled = lot.settled or nil,
            refunded= lot.refunded or nil,
            extended= (lot.extended or 0) > 0 or nil,
            -- ช่องสด  ส่งไปทั้งก้อน  มันเป็นข้อมูลสาธารณะของห้องประมูลอยู่แล้ว
            -- (ราคาที่เสนอกับชื่อคนเสนอ ทุกคนในห้องเห็นพร้อมกัน นั่นคือนิยามของการประมูล)
            -- ที่ห้ามส่งคือ holdId กับคีย์ผู้เล่นดิบ ซึ่ง lotLog ไม่เคยเก็บอยู่แล้ว
            log     = lot.log,
        }
    end

    -- เรียงจากใกล้จบก่อน  ล็อตที่จบแล้วไปอยู่ท้าย
    -- เรียง: ล็อตของร้านขึ้นก่อนเสมอ -> ที่ยังเปิดอยู่ -> ใกล้จบก่อน
    --
    -- ล็อตของร้านขึ้นบนสุดเพราะมันคือของที่การันตีว่ามาแน่ (เซิร์ฟเป็นคนเสก)
    -- ส่วนล็อตของผู้เล่นด้วยกันคือของที่ถูกยึดไว้จริงก็จริง แต่คนละระดับความเชื่อมั่น
    -- และเจ้าของเซิร์ฟสั่งไว้ว่าของแอดมินต้อง "ถูก pin ไว้บนสุด"
    table.sort(rows, function(x, y)
        local dx, dy = x.done and 1 or 0, y.done and 1 or 0
        if dx ~= dy then return dx < dy end
        local ox, oy = x.official and 0 or 1, y.official and 0 or 1
        if ox ~= oy then return ox < oy end
        if x.left ~= y.left then return x.left < y.left end
        return x.id < y.id
    end)
    return rows
end
