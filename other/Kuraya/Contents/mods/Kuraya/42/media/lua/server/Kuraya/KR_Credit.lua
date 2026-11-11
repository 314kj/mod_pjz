-- ==============================================================================
-- Kuraya — server/Kuraya/KR_Credit.lua
-- เงินกู้
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- ทำไมเงินกู้ถึงอันตรายกว่าทุกระบบในม็อดนี้
--   ทุกระบบอื่นย้ายเงินที่มีอยู่แล้ว  เงินกู้ "สร้าง" เงินขึ้นมา
--   ถ้าผู้เล่นกู้แล้วไม่คืน = เสกเงินเข้าเซิร์ฟถาวร = เงินเฟ้อ
--
-- สามอย่างที่กันไว้
--   1. วงเงินผูกกับยศ CP  ผู้เล่นใหม่กู้ได้น้อย  ต้องเล่นก่อนถึงจะกู้เยอะได้
--   2. ผิดนัดครบ 3 งวด = ล็อกบัญชี  ซื้อของ/ประมูล/โอนไม่ได้ทั้งหมด
--      "หนีหนี้แล้วเล่นต่อได้" คือทางที่ทำให้ระบบพัง
--   3. กู้ใหม่ไม่ได้ถ้ายังมีสัญญาค้าง  หนึ่งคนหนึ่งสัญญา ไม่ซ้อนกัน
--
-- เงินกู้เดินผ่าน Akacount เสมอ  ไม่มีการบวกยอดตรง ๆ
-- เพราะ ledger ต้องรู้ว่าเงินก้อนนี้มาจาก SYS:CREDIT ไม่ใช่โผล่มาเฉย ๆ
-- ==============================================================================
require("Kuraya/KR_Const")

-- PZ โหลด media/lua/server/ เรียงตามตัวอักษร  KR_Credit มาก่อน KR_Server เสมอ
-- ไฟล์นี้เลย return ทิ้งเงียบ ๆ มาตลอด แล้วหน้าเงินกู้ในเกมก็ว่างเปล่า
-- เหตุผลเต็ม ๆ เขียนไว้หัวไฟล์ KR_Auction.lua
require("Kuraya/KR_Server")

print("[Kuraya] KR_Credit  v" .. KR.VERSION)

local S = KR.server
if not S then
    print("[Kuraya] !! KR_Credit: KR_Server failed to load - credit disabled")
    return
end

local db, key, bank, alert, P = S.db, S.key, S.bank, S.alert, S.P

local function nowOf()
    return getTimestamp and getTimestamp() or os.time()
end

local function C(k)
    local d = db()
    d.credit = d.credit or {}
    d.credit[k] = d.credit[k] or { out = 0, borrowed = 0, paid = 0, missed = 0 }
    return d.credit[k]
end

-- แต้ม CP ของคนนี้  ใช้ตัดสินวงเงิน
local function cpOf(player)
    local ok, v = pcall(KR.tr.get, player)
    return (ok and tonumber(v)) or 0
end

-- ยอดที่จะ "ค้าง" จริงถ้ากู้ก้อนนี้  คือต้นบวกดอก ไม่ใช่ต้นเปล่า
--
-- เพดานของเซฟเฮาส์ต้องเทียบกับตัวเลขนี้ ไม่ใช่ยอดที่กรอก
-- ไม่งั้นสามคนกู้คนละ 3,400 (รวม 10,200 หลังดอกเบี้ย) จะผ่านเพดาน 10,000 ไปได้
local function q0total(amount, terms)
    local q = KR.creditQuote(amount, terms)
    return q.total
end

-- ------------------------------------------------------------------------------
-- กู้
-- ------------------------------------------------------------------------------
function S.creditBorrow(player, args)
    local k = key(player); if not k then return end
    local c = C(k)

    if c.plan and not c.plan.done then
        return alert(player, "Pay off your current loan first.", "bad")
    end
    if c.frozen then
        return alert(player, "Your credit is frozen. Talk to an admin.", "bad")
    end

    local B = bank()
    if not B or not B.payTo then
        return alert(player, "The bank is offline.", "bad")
    end
    if not (B.exists and B.exists(k)) then
        return alert(player, "Open an account at the bank first.", "bad")
    end

    -- ยอดเงินกู้ทุกตัวในไฟล์นี้เป็นสตางค์ (MIN_LOAN = 50000 คือ 500.00, TIERS.limit ก็หน่วยเดียวกัน)
    -- KR.fmtPrice รับ "บาท"  ส่งสตางค์เข้าไปตรง ๆ ตัวเลขบนป้ายจะโตขึ้นร้อยเท่า
    -- แปลงเฉพาะตอนจะโชว์เท่านั้น  ตัวที่เอาไปเทียบและส่งเข้า Akacount ต้องเป็นสตางค์เหมือนเดิม
    local amount = math.floor(tonumber(args and args.n) or 0)
    local minL   = KR.creditOpt("MIN_LOAN")
    if amount < minL then
        return alert(player, "Minimum loan is " ..
                     KR.fmtPrice(KR.CUR.CASH, minL / KR.SUBUNIT) .. ".", "bad")
    end

    local avail = KR.creditAvailable(cpOf(player), c.out)
    if amount > avail then
        return alert(player, "Your limit allows " ..
                     KR.fmtPrice(KR.CUR.CASH, avail / KR.SUBUNIT) .. ".", "bad")
    end

    -- ========================================================================
    -- ด่านเซฟเฮาส์  (0.5)
    --
    -- เหตุผลของทั้งสองข้อนี้เป็นข้อเดียวกัน: เงินกู้ต้องมีคนที่ตามตัวได้อยู่เบื้องหลัง
    -- คนที่เพิ่งเข้าเซิร์ฟเมื่อวาน กู้เต็มวงเงินแล้วหายไป คือการเสกเงินเข้าเซิร์ฟฟรี ๆ
    -- และเซฟเฮาส์คือหลักฐานที่ใกล้เคียงที่สุดที่เกมนี้มีว่า "คนนี้ลงหลักปักฐานแล้ว"
    --
    -- ตรวจ **หลัง** วงเงินและจำนวนงวด  เพื่อให้ข้อความที่เด้งกลับเรียงตามสิ่งที่ผู้เล่น
    -- แก้ได้ง่ายที่สุดก่อน  บอกว่า "ต้องอยู่เซฟเฮาส์อีก 2 วัน" ทั้งที่เขากรอกยอดเกินวงเงิน
    -- อยู่แล้ว = ให้เขาไปรอสองวันแล้วกลับมาเจอปัญหาเดิม
    -- ========================================================================
    local okSh, whySh, shId, members = S.safehouseGate(player)
    if not okSh then
        return alert(player, whySh or "You cannot borrow right now.", "bad")
    end

    -- ========================================================================
    -- จำนวนงวดต้องถูกตรวจ **ก่อน** เพดานรวมของเซฟเฮาส์
    --
    -- บั๊กที่เจอตอนใส่ด่านตรวจโกลบอลใน 0.6.0 (lint rule 10):
    -- ของเดิม `local terms = ...` อยู่ *ใต้* บล็อกเพดานรวม แต่บล็อกนั้นเรียก
    --     q0total(amount, terms)
    -- Lua ผูก local ตอนคอมไพล์  บรรทัดที่อยู่เหนือจุดประกาศจึงอ่าน terms เป็น
    -- **ตัวแปรโกลบอลที่ไม่มีใครตั้งค่า = nil** แล้วส่ง nil เข้า KR.creditQuote
    -- ผลคือเพดานรวม 10,000 ต่อเซฟเฮาส์ที่เจ้าของเซิร์ฟสั่งไว้ ไม่เคยทำงานถูกเลย
    -- ตั้งแต่วันที่มันถูกเขียน
    --
    -- ทำไมด่านเดิมทั้งสี่ตัวไม่จับ
    --   luac -p   ผ่าน  ไวยากรณ์ถูก  แค่อ่านตัวแปรผิดตัว
    --   lint 5b   ผ่าน  มันดูเฉพาะ `local function` ไม่ได้ดู `local x = ...`
    --   smoke     ผ่าน  เทสเพดานรวมทุกข้อทดสอบผ่านทางที่ยอดเกินอยู่แล้ว
    --                   ซึ่งเกินไม่ว่า q0total จะคืนอะไรก็ตาม
    --   client    ไม่เกี่ยว  ไฟล์ฝั่งเซิร์ฟ
    -- ด่านที่จับได้คือ rule 10 ซึ่งอ่านชื่อโกลบอลจากไบต์โค้ดจริง ไม่ใช่จากรูปแบบข้อความ
    -- ========================================================================
    local terms = math.floor(tonumber(args and args.terms) or 0)
    local okTerm = false
    for _, t in ipairs(KR.CREDIT.TERMS) do if t == terms then okTerm = true end end
    if not okTerm then return alert(player, "Pick one of the offered terms.", "bad") end

    if shId then
        -- เพดานรวมของทั้งเซฟเฮาส์
        -- กันการตั้งเซฟเฮาส์รวมหัวกันกู้ทีละคนจนได้เงินก้อนใหญ่กว่าที่ตั้งใจให้ใครคนเดียวได้
        local cap  = math.floor(KR.loanOpt("SAFEHOUSE_CAP"))
        local used = S.safehouseDebt(members)
        if used + q0total(amount, terms) > cap then
            local left = math.max(0, cap - used)
            return alert(player, "Everyone in your safehouse owes " ..
                         KR.fmtPrice(KR.CUR.CASH, used / KR.SUBUNIT) .. " together and the limit is " ..
                         KR.fmtPrice(KR.CUR.CASH, cap / KR.SUBUNIT) .. ". You can still take " ..
                         KR.fmtPrice(KR.CUR.CASH, left / KR.SUBUNIT) ..
                         " of that once the interest is added.", "bad")
        end
    end

    -- จำนวนงวดถูกตรวจไปแล้วเหนือบล็อกเพดานรวมของเซฟเฮาส์  ดูเหตุผลตรงนั้น
    -- (ไม่งั้นไคลเอนต์ส่ง terms = 100000 มาแล้วงวดละ 0 บาท = กู้ฟรีตลอดกาล)
    local q  = KR.creditQuote(amount, terms)
    local ts = nowOf()

    -- โอนเงินเข้าบัญชีก่อน  ถ้าโอนไม่ผ่านห้ามบันทึกสัญญา
    -- ถ้าบันทึกสัญญาก่อนแล้วโอนพลาด ผู้เล่นจะเป็นหนี้ทั้งที่ไม่เคยได้เงิน
    local okPay = pcall(B.payTo, "SYS:CREDIT", k, amount, "loan",
                        "loan " .. terms .. " instalments", "system")
    if not okPay then
        return alert(player, "The bank refused the transfer. No loan was created.", "bad")
    end

    c.borrowed = (c.borrowed or 0) + amount
    c.out      = (c.out or 0) + q.total
    c.plan = {
        terms = q.terms, each = q.each, last = q.last,
        total = q.total, interest = q.interest,
        paidN = 0, startAt = ts,
        dueAt = ts + KR.DAY_SEC,
        done  = false,
    }
    if S.logEvent then
        S.logEvent(k, KR.LOG.LOAN, KR.L("รับเงินกู้", "Loan drawn"),
                   amount, KR.CUR.CASH, true, terms .. " instalments")
    end
    alert(player, "Loan approved: " .. KR.fmtPrice(KR.CUR.CASH, amount / KR.SUBUNIT) ..
                  " - pay back " .. KR.fmtPrice(KR.CUR.CASH, q.total / KR.SUBUNIT) ..
                  " over " .. terms .. " instalments.", "good")
    S.sync(player)
end

-- ------------------------------------------------------------------------------
-- จ่ายงวด
--
-- จ่ายได้ทีละงวดเท่านั้น  ตั้งใจแบบนั้น
-- จ่ายรวดเดียวทั้งก้อนได้ = ดอกเบี้ยไม่มีความหมาย และวินัยการเงินก็ไม่มี
-- (ปุ่ม "จ่ายหมด" อยู่ในแผน แต่ต้องคิดเรื่องส่วนลดดอกเบี้ยก่อน)
-- ------------------------------------------------------------------------------
function S.creditRepay(player, args)
    local k = key(player); if not k then return end
    local c = C(k)
    local plan = c.plan
    if not plan or plan.done then
        return alert(player, "You have no loan to pay.", "info")
    end

    local B = bank()
    if not B or not (B.payTo or B.charge) then
        return alert(player, "The bank is offline.", "bad")
    end

    local ts   = nowOf()
    local base = KR.creditInstalment(plan)
    local late = KR.creditLateFee(plan, ts)
    local due  = base + late

    -- due เป็นสตางค์เหมือน B.available  แปลงเป็นบาทเฉพาะตอนโชว์
    if B.available and B.available(k) < due then
        return alert(player, "You need " .. KR.fmtPrice(KR.CUR.CASH, due / KR.SUBUNIT) ..
                             " to pay this instalment.", "bad")
    end

    -- เงินที่จ่ายคืนต้องกลับเข้า SYS:CREDIT  ไม่ใช่ถูก burn ทิ้ง
    --
    -- ของเดิมเรียก B.charge ซึ่งดูดเงินเข้า SYS:FEE ตามพฤติกรรมของมัน
    -- ผลสองอย่างที่ตามมาและทั้งคู่ผิด
    --   1. SYS:CREDIT ติดลบเรื่อย ๆ ตลอดอายุเซิร์ฟ เพราะจ่ายออกอย่างเดียวไม่เคยรับคืน
    --      ยอดในบัญชีนั้นจึงไม่ได้แปลว่า "เงินที่ปล่อยกู้อยู่" อีกต่อไป = ตัวเลขที่อ่านไม่ได้
    --   2. ดอกเบี้ยไปกองรวมกับค่าธรรมเนียม แยกกันไม่ออก
    --      แล้วคำถามว่า "ระบบเงินกู้ทำกำไรหรือขาดทุน" ก็ตอบไม่ได้เลย
    --
    -- payTo เดินเป็นการโอนสองขาที่บาลานซ์ในตัวเอง ซึ่งคือสิ่งที่การจ่ายหนี้เป็นจริง ๆ
    -- ถอยไปใช้ charge เฉพาะตอน Akacount ไม่มี payTo  ดีกว่าจ่ายหนี้ไม่ได้เลย
    local okPay
    if B.payTo then
        okPay = pcall(B.payTo, k, "SYS:CREDIT", due, "repay",
                      "loan instalment " .. (plan.paidN + 1), "card")
    else
        okPay = pcall(B.charge, k, due, "repay",
                      "loan instalment " .. (plan.paidN + 1), "card")
    end
    if not okPay then
        return alert(player, "Payment failed. Nothing was taken.", "bad")
    end

    plan.paidN = plan.paidN + 1
    c.paid = (c.paid or 0) + base

    -- บันทึก "ยอดที่จ่ายจริง" คือ base + ค่าปรับ  ไม่ใช่ค่างวดเปล่า
    -- คนที่จ่ายช้าต้องเห็นในประวัติว่าโดนปรับไปเท่าไร ไม่ใช่เห็นแค่ตัวเลขค่างวดที่ดูเท่าเดิมทุกงวด
    if S.logEvent then
        S.logEvent(k, KR.LOG.LOAN,
                   KR.L("จ่ายงวดที่ ", "Instalment ") .. plan.paidN .. " / " .. plan.terms,
                   due, KR.CUR.CASH, false,
                   late > 0 and ("late " .. KR.fmtPrice(KR.CUR.CASH, late / KR.SUBUNIT)) or nil)
    end
    c.out  = math.max(0, (c.out or 0) - base)

    -- จ่ายแล้วต้องล้างสถิติผิดนัดของงวดที่เพิ่งตามทัน
    --
    -- ของเดิมไม่ล้าง  creditTick จะ return ตั้งแต่บรรทัด overdue <= 0 หลังจ่าย
    -- แล้ว c.missed ค้างเลขเดิมไว้ตลอดกาล  คนที่ตามหนี้ทันแล้วยังโดนป้ายว่าผิดนัดสองงวด
    -- และถ้าพลาดอีกครั้งเดียวจะข้ามเพดานสามงวดไปโดนแช่แข็งทั้งที่จ่ายมาตลอด
    plan.missedSeen = 0
    c.missed = 0

    if plan.paidN >= plan.terms then
        plan.done = true
        c.out = 0
        -- จ่ายครบตรงเวลา = ประวัติดี  เก็บไว้ใช้ตอนคิดวงเงินในอนาคต
        c.clean = (c.clean or 0) + 1
        -- ปิดหนี้แล้วต้องปลดแช่แข็งด้วย  ไม่งั้นการลงโทษกลายเป็นถาวรทั้งที่หนี้จบแล้ว
        -- ซึ่งไม่ใช่การลงโทษ แต่คือการไล่คนออกจากเซิร์ฟแบบเงียบ ๆ
        if c.frozen then
            c.frozen = nil
            alert(player, "Loan cleared. Your account is unfrozen.", "good")
        else
            alert(player, "Loan paid off. Nice.", "good")
        end
    else
        plan.dueAt = ts + KR.DAY_SEC
        alert(player, "Instalment " .. plan.paidN .. " of " .. plan.terms .. " paid.", "good")
    end
    S.sync(player)
end

-- ------------------------------------------------------------------------------
-- ตรวจงวดที่เลยกำหนด
--
-- เรียกจาก sync เหมือน rotateDaily  เหตุผลเดียวกัน: เซิร์ฟปิดข้ามวันได้
-- นับ "จำนวนงวดที่เลย" จากเวลาจริง ไม่ใช่จากจำนวนครั้งที่ฟังก์ชันนี้ถูกเรียก
-- ไม่งั้นคนที่ล็อกอินบ่อยจะโดนปรับหนักกว่าคนที่ไม่ล็อกอิน ซึ่งกลับหัวกลับหาง
-- ------------------------------------------------------------------------------
function S.creditTick(player, ts)
    local k = key(player); if not k then return end
    ts = ts or nowOf()
    local c = C(k)

    -- ------------------------------------------------------------------------
    -- ล็อกร้านเมื่อบัญชีติดลบมากเกินไป  ตรวจก่อนเรื่องงวด
    --
    -- ต่างจากการแช่แข็งเพราะผิดนัดสามงวดตรงที่ **จ่ายหนี้เองแล้วไม่ปลด**
    -- ต้องให้แอดมินปลดเท่านั้น ตามที่เจ้าของเซิร์ฟสั่ง
    -- เหตุผลที่ต่างกัน: ผิดนัดสามงวดคือ "ยังคุยกันได้" ส่วนติดลบห้าพันคือ
    -- คนที่ระบบหักเงินไม่ได้แล้วและยังใช้เซิร์ฟต่อโดยติดหนี้ก้อนโต ซึ่งควรมีคนจริงมาดู
    --
    -- ปลดล็อกเองตอนยอดกลับมาบวกไม่ได้ เพราะจะกลายเป็นวนซ้ำ:
    -- โดนล็อก -> เอาเงินเข้ามาพอให้พ้นเส้น -> ปลด -> ถอนออก -> โดนล็อก
    -- ------------------------------------------------------------------------
    local B = bank()
    if B and B.available then
        local okBal, bal = pcall(B.available, k)
        if okBal and type(bal) == "number" then
            local floorAt = -math.floor(KR.loanOpt("SHOP_LOCK_DEBT"))
            if bal < floorAt and not c.shopLock then
                c.shopLock   = true
                c.shopLockAt = ts
                print("[Kuraya] SHOP LOCK  " .. tostring(k) .. "  balance " .. tostring(bal))
                alert(player, "Your balance is below " ..
                              KR.fmtPrice(KR.CUR.CASH, math.abs(floorAt) / KR.SUBUNIT) ..
                              " in the red. The shop is locked until an admin unlocks it.", "bad")

                -- ------------------------------------------------------------
                -- บอกแอดมินด้วย  ของเดิมเตือนแค่ตัวผู้เล่นกับพิมพ์ลง console
                --
                -- ปัญหาของแบบเดิม: คนที่โดนล็อกคือคนที่ **ทำอะไรเองไม่ได้แล้ว**
                -- ทางออกทางเดียวของเขาคือหาแอดมินให้เจอ  แต่ระบบไม่เคยบอกแอดมินเลย
                -- ผลคือคนเงียบ ๆ ที่ไม่กล้าทักใครจะติดค้างอยู่แบบนั้นไปเรื่อย ๆ
                -- แล้วเจ้าของเซิร์ฟจะรู้อีกทีตอนเขาเลิกเล่นไปแล้ว
                --
                -- ป้ายนี้เด้งให้เฉพาะแอดมินที่ออนไลน์อยู่ตอนนั้น ซึ่งอาจเป็นศูนย์คน
                -- ตัวที่ไม่หายคือ c.shopLock ในฐานข้อมูล ซึ่งหน้าจอแอดมินอ่านทุก sync
                -- (ดู S.playerRows) ป้ายนี้จึงเป็นแค่การสะกิด ไม่ใช่ที่เก็บงานค้าง
                -- ------------------------------------------------------------
                if type(S.tellAdmins) == "function" then
                    S.tellAdmins("SHOP LOCKED: " .. tostring(P(k).disp or k) ..
                                 "  balance " .. KR.fmtPrice(KR.CUR.CASH, bal / KR.SUBUNIT) ..
                                 "  - needs an admin to unlock", "bad")
                end
            end
        end
    end

    local plan = c.plan
    if not plan or plan.done then return end

    -- ------------------------------------------------------------------------
    -- ระบบไล่หักเอง
    --
    -- เจ้าของเซิร์ฟบอกว่า "หากไม่จ่ายหนี้เลย ระบบหักแล้วติดลบเกิน 5,000 จะถูกล็อก"
    -- ประโยคนั้นมีสองส่วน และส่วนแรกคือส่วนที่ยังไม่เคยมี: **ระบบต้องหักเอง**
    -- ของเดิมรอผู้เล่นกดจ่ายอย่างเดียว คนที่ตั้งใจไม่จ่ายจึงไม่มีอะไรเกิดขึ้นกับเขาเลย
    --
    -- หักได้แค่ไหนก็เอาแค่นั้น  บัญชีที่ยอมติดลบจะถูกดันลงไปเอง แล้วด่านข้างบนจับต่อ
    -- บัญชีที่ไม่ยอมติดลบจะหักไม่ผ่าน แล้วงวดก็ค้างไว้ตามเดิม ซึ่งยังนับเป็นผิดนัดอยู่ดี
    -- ------------------------------------------------------------------------
    local overdueNow = (plan.dueAt or ts) < ts
    if overdueNow and B and B.charge then
        local lastTry = tonumber(plan.autoAt) or 0
        if ts - lastTry >= KR.DAY_SEC then
            plan.autoAt = ts
            local base = KR.creditInstalment(plan)
            local late = KR.creditLateFee(plan, ts)
            local due  = base + late
            local okAuto = pcall(B.charge, k, due, "repay",
                                 "auto instalment " .. (plan.paidN + 1), "system")
            if okAuto then
                plan.paidN = plan.paidN + 1
                c.paid = (c.paid or 0) + base
                c.out  = math.max(0, (c.out or 0) - base)
                plan.missedSeen = 0
                c.missed = 0
                if S.logEvent then
                    S.logEvent(k, KR.LOG.LOAN,
                               KR.L("ระบบหักงวดที่ ", "Auto instalment ") .. plan.paidN ..
                               " / " .. plan.terms, due, KR.CUR.CASH, false, "automatic")
                end
                if plan.paidN >= plan.terms then
                    plan.done = true
                    c.out = 0
                    c.clean = (c.clean or 0) + 1
                    alert(player, "Your loan was paid off automatically.", "good")
                else
                    plan.dueAt = ts + KR.DAY_SEC
                    alert(player, "Instalment " .. plan.paidN .. " was collected automatically.", "info")
                end
                return
            end
        end
    end

    local overdue = math.floor((ts - (plan.dueAt or ts)) / KR.DAY_SEC)
    if overdue <= 0 then return end

    -- จำนวนงวดที่ควรจะจ่ายไปแล้วแต่ยังไม่จ่าย
    local missed = math.min(overdue, plan.terms - plan.paidN)
    if missed <= (plan.missedSeen or 0) then return end
    plan.missedSeen = missed
    c.missed = missed

    if missed >= KR.creditOpt("MISS_FREEZE") and not c.frozen then
        c.frozen = true
        alert(player, "You missed " .. missed .. " instalments. Your account is frozen.", "bad")
    end
end

-- แช่แข็งแล้วห้ามใช้ระบบอื่น  ตัวนี้ให้ไฟล์อื่นเรียกเช็ค
function S.creditFrozen(player)
    local k = key(player); if not k then return false end
    local d = db()
    local c = (d.credit or {})[k]
    return (c and c.frozen) == true
end

-- ร้านถูกล็อกเพราะติดลบหนัก  ปลดได้โดยแอดมินเท่านั้น
function S.shopLocked(player)
    local k = key(player); if not k then return false end
    local d = db()
    local c = (d.credit or {})[k]
    return (c and c.shopLock) == true
end

-- แอดมินปลดล็อก  คืน ok, ข้อความ
function S.shopUnlock(name)
    local k = tostring(name or ""):lower()
    if k == "" then return false, "no player" end
    local d = db()
    d.credit = d.credit or {}
    local c = d.credit[k]
    if not c or not c.shopLock then return false, "that player is not locked" end
    c.shopLock, c.shopLockAt = nil, nil
    print("[Kuraya] SHOP UNLOCK  " .. k)
    local p = S.onlineByKey and S.onlineByKey(k)
    if p then alert(p, "An admin unlocked your shop access. Keep an eye on that balance.", "good") end
    return true
end

-- ------------------------------------------------------------------------------
-- ส่งให้ไคลเอนต์
-- ------------------------------------------------------------------------------
function S.creditRow(player, ts)
    local k = key(player); if not k then return nil end
    ts = ts or nowOf()
    S.creditTick(player, ts)

    local c    = C(k)
    local cp   = cpOf(player)
    local tier = KR.creditTier(cp)
    local nxt  = KR.creditNextTier(cp)
    local plan = c.plan

    local row = {
        cp       = cp,
        tier     = tier.name,
        -- เพดานที่ **ใช้ได้จริง** ไม่ใช่เพดานของยศ
        -- ถ้าเซิร์ฟตั้งฝารวมไว้ต่ำกว่ายศ จอต้องโชว์ฝา ไม่งั้นจอสัญญาวงเงินที่กู้ไม่ได้จริง
        limit    = KR.creditLimit(cp),
        tierLimit= tier.limit,
        nextTier = nxt and nxt.name or nil,
        nextCp   = nxt and nxt.cp   or nil,
        -- เพดานของยศถัดไปก็ต้องผ่านฝาเหมือนกัน  ไม่งั้นจอชวนให้ไต่ยศไปหาตัวเลข
        -- ที่เซิร์ฟไม่ได้ตั้งใจจะให้  ("ขึ้น GOLD แล้วได้ 50,000" ทั้งที่ฝาอยู่ที่ 20,000)
        nextLimit= nxt and KR.creditLimit(nxt.cp) or nil,
        borrowed = c.borrowed or 0,
        paid     = c.paid or 0,
        out      = c.out or 0,
        avail    = KR.creditAvailable(cp, c.out),
        frozen   = c.frozen or nil,
        shopLock = c.shopLock or nil,
        missed   = c.missed or 0,
        terms    = KR.CREDIT.TERMS,
        rateBp   = KR.creditOpt("RATE_BP"),
        lateBp   = KR.creditOpt("LATE_BP"),
        minLoan  = KR.creditOpt("MIN_LOAN"),
    }

    -- สถานะเซฟเฮาส์  จอต้องบอกได้ว่า "ทำไมกู้ไม่ได้" ก่อนที่ผู้เล่นจะกดแล้วโดนปฏิเสธ
    -- ปุ่มที่กดแล้วโดนด่าคือปุ่มที่ไม่ควรมี  หน้านี้จึงต้องรู้เหตุผลตั้งแต่ตอนวาด
    if KR.loanNeedsSafehouse() then
        local okSh, whySh, shId, members = S.safehouseGate(player)
        row.shOk  = okSh or nil
        row.shWhy = (not okSh) and whySh or nil
        if shId then
            row.shDebt = S.safehouseDebt(members)
            row.shCap  = math.floor(KR.loanOpt("SAFEHOUSE_CAP"))
        end
    else
        row.shOk = true
    end

    if plan and not plan.done then
        local late = KR.creditLateFee(plan, ts)
        row.plan = {
            terms = plan.terms, paidN = plan.paidN,
            each  = KR.creditInstalment(plan),
            late  = late,
            dueIn = math.max(0, (plan.dueAt or ts) - ts),
            overdue = ((plan.dueAt or ts) < ts) or nil,
        }
    end
    return row
end
