-- ==============================================================================
-- Kuraya — client/Kuraya/KR_Client.lua
-- net layer + เมนูเปิดร้าน
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
require("Kuraya/KR_Const")
print("[Kuraya] KR_Client  v" .. KR.VERSION)
require("Kuraya/KR_Theme")

-- ------------------------------------------------------------------------------
-- ยามกันโหลดซ้ำ  ต้องอยู่ก่อนบรรทัดที่ผูก Events ทุกบรรทัด
--
-- B42 โหลด media ของม็อดจาก "สองที่" คือ common/ กับโฟลเดอร์เวอร์ชันที่ตรงกับบิลด์
-- ม็อดนี้เคยมีต้นไม้ lua เหมือนกันเป๊ะทั้งสองที่  ไฟล์ฝั่งไคลเอนต์จึงถูกรันสองรอบ
--
-- ฝั่งเซิร์ฟรอดมาได้เพราะ KR_Server มียามแบบนี้อยู่แล้ว  ฝั่งไคลเอนต์ไม่มี ผลคือ
--   Events.OnServerCommand ถูกผูกสองครั้ง   -> ป้ายเด้งซ้อนสองอัน
--   เมนูคลิกขวาถูกเติมสองครั้ง              -> มี HF Shop / Fresh Market อย่างละสองบรรทัด
--   ปุ่มลอยถูกสร้างสองอันซ้อนกัน
--
-- แพ็กเกจนี้เหลือ lua ที่เดียวแล้ว (ดู _pack.py) ยามนี้จึงไม่ควรทำงานเลย
-- แต่มันต้องอยู่: ต้นเหตุจริงคือ "ไฟล์นี้ทนการถูกรันสองรอบไม่ได้" ไม่ใช่โครงโฟลเดอร์
-- โครงโฟลเดอร์แก้อาการ ยามตัวนี้แก้สาเหตุ
-- ------------------------------------------------------------------------------
if KR.__loaded_client then return end
KR.__loaded_client = true

KRClient = KRClient or {}
local C = KRClient
C.data = C.data or { catalog = {}, markets = {}, bal = {}, skins = {}, quota = {},
                     bankOk = false, trOk = false, atMarket = nil }
C.saleCount = 0
C.filterCur = "all"      -- ตัวกรองสกุลที่ผู้เล่นเลือกอยู่  มีผลกับราคาที่แสดงในลิสต์
C.filterCat = nil        -- หมวดที่ดูอยู่  nil = ยังไม่เคยรับค่าจากเซิร์ฟ
C.sortMode  = nil        -- nil = ใช้ KR.SORT_DEFAULT

function C.req(cmd, args) sendClientCommand(KR.MODULE, cmd, args or {}) end
function C.sync() C.req(KR.CMD.REQ_SYNC) end

-- ตั้งชื่อไว้แทนที่จะเป็น closure นิรนาม
-- เทสจะได้ป้อนแพ็กเก็ตจากเซิร์ฟเข้ามาตรง ๆ ได้ ไม่ต้องเดาว่ามันทำอะไร
function C.onCommand(module, command, args)
    if module ~= KR.MODULE then return end
    if command == KR.CMD.SYNC and args then
        -- ป้ายบิลถูกส่งครั้งเดียวแล้วเซิร์ฟล้างทิ้ง  ต้องเก็บต่อท้ายคิวของเรา
        -- ไม่ใช่ปล่อยให้ลูปข้างล่างเขียนทับ ไม่งั้นป้ายที่ยังไม่ได้อ่านจะหายไปกับ sync รอบถัดไป
        if args.billNote then
            C.billQueue = C.billQueue or {}
            for _, n in ipairs(args.billNote) do
                C.billQueue[#C.billQueue + 1] = n
            end
        end
        for k, v in pairs(args) do C.data[k] = v end
        C.saleCount = tonumber(args.saleCount) or 0   -- ปุ่มลอยอ่านค่านี้ไปขึ้นจุดแดง

        -- ======================================================================
        -- ของแอดมินต้องหายไปพร้อมกับสิทธิ์แอดมิน
        --
        -- 0.6.8 — เจ้าของเซิร์ฟถ่ายรูปมา: ผู้เล่นที่ไม่มีแท็บ ADMIN ยังเห็นการ์ด
        -- SHOP TILL พร้อมยอด "ถอนไปแล้ว 300.00" อยู่ในหน้า Account ของตัวเอง
        --
        -- ฝั่งเซิร์ฟถูกแล้ว  มันส่ง till/players/bank เป็น nil ให้คนที่ไม่ใช่แอดมิน
        -- **แต่ nil ส่งข้ามสายไม่ได้**  คีย์ที่เป็น nil หายไปจากตาราง args ทั้งคีย์
        -- ลูป `for k, v in pairs(args)` ข้างบนจึงไม่มีทางรู้ว่ามีคีย์ไหน "ถูกถอน"
        -- ค่าที่เคยได้มาตอนเป็นแอดมินจึงนอนอยู่ใน C.data ต่อไปจนกว่าจะปิดเกม
        --
        -- นี่เป็นข้อจำกัดของ "sync แบบผสาน" ที่ต้องรู้ไว้ทั้งม็อด:
        --   **การไม่ส่งอะไรมา ไม่เท่ากับการส่งว่าไม่มี**
        -- ฟิลด์ไหนที่ "หายไปได้" ต้องมีคนล้างให้ชัด ๆ ไม่ใช่หวังว่าลูปจะล้างให้
        --
        -- ล้างที่นี่ที่เดียวหลังผสานเสร็จ  ไม่ใช่ไปไล่เช็กที่ทุกจุดที่วาด
        -- (จุดวาดยังเช็กซ้ำอีกชั้นด้วย แต่ด่านจริงอยู่ตรงนี้ ข้อมูลไม่ควรมีอยู่ตั้งแต่แรก)
        -- ======================================================================
        if C.data.admin ~= true then
            C.data.till    = nil
            C.data.players = nil
            C.data.bank    = nil
            C.accView      = nil
        end

        -- ตรรกะการเลือกหมวดอยู่ใน KR.pickCat  ดูคอมเมนต์ที่นั่น
        C.filterCat = KR.pickCat(C.filterCat, args.cats, args.pref)
        if KRShop and KRShop.instance then KRShop.instance:refresh() end

    elseif command == KR.CMD.SALE_ANNOUNCE and args then
        -- ขึ้นเหนือหัวผู้เล่นเป็นสีเขียว  ไม่ใช่ป็อปอัปกลางจอ
        -- คนอาจกำลังวิ่งหนีซอมบี้อยู่ ห้ามไปบังจอเขา
        local p = getSpecificPlayer(0)
        local n = tonumber(args.n) or 0
        if p and n > 0 and HaloTextHelper then
            C.saleCount = n
            HaloTextHelper.addTextWithArrow(p,
                "Now " .. n .. (n == 1 and " item" or " items") .. " on flash sale",
                true, 110, 220, 130)
        end

    elseif command == KR.CMD.FIND_PLAYER and args then
        -- ผลค้นชื่อผู้เล่นสำหรับช่องพิมพ์-เลือก
        --
        -- เก็บคำค้นที่ใช้ค้นมาด้วย  หน้าจอเทียบกับสิ่งที่พิมพ์อยู่ตอนนี้ก่อนเอาไปโชว์
        -- ไม่งั้นคำตอบของคำค้นเก่าที่มาช้าจะไปทับรายการของคำค้นใหม่
        -- (พิมพ์เร็ว ๆ แล้วรายการกระพริบสลับไปมา คือบั๊กที่หาสาเหตุยากมาก)
        C.findQ    = tostring(args.q or "")
        C.findRows = args.rows or {}
        C.findAt   = getTimestampMs and getTimestampMs() or 0

    elseif command == KR.CMD.CAR_LIST and args then
        -- รายชื่อรุ่นรถที่เกมนี้มีจริง  อ่านมาจากเซิร์ฟ ไม่ใช่ลิสต์ที่เราพิมพ์เอง
        --
        -- เก็บ how ไว้ด้วย  มันคือชื่อเมธอดที่ตอบได้จริงบนบิลด์นั้น
        -- วันที่ลิสต์ว่าง เจ้าของเซิร์ฟต้องอ่านออกได้ว่า "อ่านไม่ได้" ต่างจาก "ไม่มีรถ"
        C.cars    = args.rows or {}
        C.carsHow = args.how
        C.carsAt  = getTimestampMs and getTimestampMs() or 0

    elseif command == KR.CMD.PET_LIST and args then
        -- รายชื่อสัตว์  เหตุผลเดียวกับรถทุกข้อ  (0.6.16)
        -- เซิร์ฟคือที่เดียวที่รู้ว่าลงม็อดสัตว์อะไรไว้ และเป็นที่เดียวที่คำตอบมีผลจริง
        C.pets    = args.rows or {}
        C.petsHow = args.how
        C.petsAt  = getTimestampMs and getTimestampMs() or 0

    elseif command == KR.CMD.STATS and args then
        -- ตัวเลขเศรษฐกิจ  (0.7.0)
        -- เก็บไว้ทั้งก้อน  จอเลือกมุมมองเอาเอง ไม่ต้องยิงถามใหม่ทุกครั้งที่กดชิป
        -- (การกดชิปเปลี่ยนสกุลคือการมองข้อมูลชุดเดิมคนละด้าน ไม่ใช่การขอข้อมูลใหม่
        --  ยกเว้นกราฟที่ช่วงวันเปลี่ยน ซึ่งต้องใช้ชุดใหม่จริง)
        C.stats = args

    elseif command == KR.CMD.SKILLS and args then
        C.skills = args

    elseif command == KR.CMD.DIAG and args then
        -- พิมพ์ลง console ของเครื่องนี้  ไม่ใช่ของเซิร์ฟ
        -- แอดมินจะได้ส่งไฟล์ที่เขาเปิดได้อยู่แล้วมาให้ดูได้เลย
        print("[Kuraya] ---- " .. tostring(args.title or "diagnostic") .. " ----")
        for _, l in ipairs(args.lines or {}) do
            print("[Kuraya] " .. tostring(l))
        end
        print("[Kuraya] ---- end ----")

    elseif command == KR.CMD.ACC_VIEW and args then
        -- บัญชีรายคนที่แอดมินขอดู  เก็บทั้งก้อนไว้ให้หน้าจออ่าน
        --
        -- ==========================================================================
        -- **ห้ามเขียนฟิลด์ลงบนหน้าต่างด้วยชื่อที่ชนกับเมธอด**  (แก้ 0.6.17)
        --
        -- บรรทัดที่เคยอยู่ตรงนี้คือ  KRShop.instance.accWho = args.key
        -- ซึ่งเป็นระเบิดเวลาที่ฝังอยู่เงียบ ๆ มาหลายรุ่น:
        --
        --   KRShop:accWho(x, y, w, d)  เป็น **เมธอด** ที่หน้า Account วาดคอลัมน์ขวาด้วย
        --   การเขียน instance.accWho = "ninjaaa" ทำให้ฟิลด์บนตัวอินสแตนซ์
        --   บังเมธอดบนคลาส (lookup ของ Lua เจอฟิลด์ก่อน metatable เสมอ)
        --   เฟรมถัดไป self:accWho(...) จึงกลายเป็นการ "เรียกสตริงเป็นฟังก์ชัน"
        --   -> Object ninjaaa did not have __call metatable set
        --   -> ทั้งหน้า Account พังทุกเฟรม  ในล็อกของเจ้าของเซิร์ฟนับได้ 491 ครั้ง
        --
        -- มันเพิ่งโผล่ตอน 0.6.16 เพราะ 0.6.16 คือรุ่นแรกที่แอดมิน "เปิดดูบัญชีรายคน"
        -- เป็นเรื่องปกติ  ของเก่าไม่ได้พังน้อยกว่า มันแค่ยังไม่มีใครเดินไปเหยียบ
        --
        -- และไม่มีใครอ่านฟิลด์นี้เลยสักที่ (grep ทั้งม็อดแล้ว) มันเขียนอย่างเดียว
        -- คนที่ต้องการคีย์อ่านจาก KRClient.accView.key ซึ่งเป็นแหล่งเดียวอยู่แล้ว
        -- ==========================================================================
        C.accView = args

    elseif command == KR.CMD.ALERT and args then
        -- ในหน้าต่างร้านก่อน  แล้วค่อยเหนือหัว
        --
        -- HaloText อยู่ "หลัง" หน้าต่างร้านเสมอ  ถ้าร้านเปิดอยู่ ผู้เล่นไม่มีทางเห็น
        -- นั่นคือสาเหตุที่ผู้เล่นรายงานว่า "กดซื้ออะไรไม่ได้" ทั้งที่เซิร์ฟตอบมาทุกครั้ง
        if KRShop and KRShop.notify then
            pcall(KRShop.notify, args.msg, args.tone)
        end
        local p = getSpecificPlayer(0)
        if p and args.msg and HaloTextHelper then
            local r, g, b = 210, 210, 235
            if args.tone == "good" then r, g, b = 127, 209, 143 end
            if args.tone == "bad"  then r, g, b = 255, 199, 199 end
            HaloTextHelper.addTextWithArrow(p, args.msg, true, r, g, b)
        end
    end
end

Events.OnServerCommand.Add(C.onCommand)

Events.OnCreatePlayer.Add(function(n) if n == 0 then C.sync() end end)

-- ------------------------------------------------------------------------------
-- ราคาที่จะโชว์ในลิสต์
--
-- ปกติโชว์ครบทุกสกุลที่ซื้อได้ แยกกันด้วยสี ตาจะได้กวาดเจอสกุลที่ตัวเองมี
-- แต่พอผู้เล่นกรองสกุลใดสกุลหนึ่ง เขาบอกไปแล้วว่าสนใจสกุลเดียว
-- ตอนนั้นการโชว์ครบกลายเป็นเสียงรบกวน จึงตัดที่เหลือออก
-- ------------------------------------------------------------------------------
function C.linesFor(entry)
    local now = tonumber(C.data.now) or 0
    return KR.priceLines(entry, now, C.filterCur)
end

-- ห้าม require KR_UI_Shop / KR_EscMenu จากตรงนี้
--
-- เวอร์ชันก่อนหน้าเรียกไว้ตรงนี้ แล้ว KR_UI_Shop ก็ require KR_Client กลับ
-- = require วนกันเอง  ผลคือม็อดขึ้น [ERRORS] ในหน้ารายการม็อด
-- (Akacount ไม่เจอปัญหานี้เพราะ AC_Client ไม่เคย require AC_UI กลับ)
--
-- PZ โหลดไฟล์ในโฟลเดอร์เดียวกันเรียงตามตัวอักษรอยู่แล้ว
--   KR_Client -> KR_EscMenu -> KR_Theme -> KR_UI_Shop
-- KR_EscMenu เป็นคน require KR_UI_Shop ต่อให้เอง ซึ่งเป็นทิศทางเดียว ไม่วน

return C
