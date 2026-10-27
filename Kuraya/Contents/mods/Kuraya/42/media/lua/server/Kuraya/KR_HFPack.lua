-- ==============================================================================
-- Kuraya — server/Kuraya/KR_HFPack.lua
-- แพ็ก HF Point  แอดมินตั้งราคา ผู้เล่นส่งคำขอ แอดมินกดส่งให้
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- กฎเหล็กของไฟล์นี้: **ม็อดไม่แตะเงินจริงแม้แต่บาทเดียว**
--
-- ราคาบาทที่เก็บอยู่ในนี้เป็นแค่ตัวเลขสำหรับแสดงและสำหรับให้แอดมินอ้างอิง
-- ไม่มีการเชื่อมกับช่องทางชำระเงินใด ๆ  ไม่มีการตรวจว่าจ่ายจริงหรือยัง
-- คำขอที่ผู้เล่นส่งเข้ามาคือ "ใบสั่ง" ไม่ใช่ "ใบเสร็จ"
-- คนที่ตัดสินว่าเงินเข้าแล้วคือมนุษย์ที่เป็นแอดมิน และเขาตัดสินด้วยการกดปุ่ม
--
-- ผลที่ตามมาซึ่งตั้งใจให้เป็นแบบนั้น:
--   * คำขอที่ค้างอยู่ไม่ได้แปลว่ามีใครเป็นหนี้ใคร  ลบทิ้งได้โดยไม่มีอะไรเสียหาย
--   * ไม่มีการคืนเงิน เพราะไม่เคยมีเงินเข้ามาในระบบ
--   * ประวัติที่จดไว้มีค่าทางการคุยกับผู้เล่น ไม่ใช่ทางบัญชี
--
-- อีกเรื่องที่ตั้งใจ: HF ที่ส่งให้ **ไม่ได้เดินผ่าน Akacount**
--   HF เป็นแต้มของ Kuraya เอง (P(k).hf) ไม่ใช่เงินใน ledger
--   จึงส่งให้คนที่ไม่ได้ออนไลน์ได้ ซึ่งเป็นเคสปกติ (คนโอนเงินแล้วปิดเกมไปนอน)
-- ==============================================================================
require("Kuraya/KR_Const")
require("Kuraya/KR_Server")

print("[Kuraya] KR_HFPack  v" .. KR.VERSION)

local S = KR.server
if not S then
    print("[Kuraya] !! KR_HFPack: KR_Server failed to load - HF packs disabled")
    return
end

local db, key, alert, P, isAdmin = S.db, S.key, S.alert, S.P, S.isAdmin

local function nowOf()
    return (getTimestamp and getTimestamp()) or os.time()
end

-- ------------------------------------------------------------------------------
-- ที่เก็บ  สร้างให้ครบทุกครั้งที่แตะ ไม่ใช่หวังว่า migrate ทำไว้แล้ว
--
-- เหตุผลเดียวกับที่ db() ของ KR_Server ยัง `or {}` ซ้ำหลัง migrate:
-- เซฟที่ถูกแก้ด้วยมือ หรือเซฟที่ข้ามเวอร์ชันมาหลายขั้น จะมีฟิลด์หายเป็นหลุม ๆ
-- ฟังก์ชันที่พังเพราะตารางเป็น nil คือฟังก์ชันที่ทำให้ทั้ง handler ตาย
-- ------------------------------------------------------------------------------
local function H()
    local d = db()
    d.hfpack = d.hfpack or {}
    local h = d.hfpack
    h.packs = h.packs or {}
    h.reqs  = h.reqs  or {}
    h.next  = tonumber(h.next) or 1
    return h, d
end

-- ------------------------------------------------------------------------------
-- อ่านแพ็กหนึ่งช่อง  คืนตารางเสมอ ไม่เคยคืน nil
--
-- ช่องที่แอดมินยังไม่ตั้งมีค่าเป็น { set = false } ไม่ใช่ nil
-- เพราะฝั่งจอต้องวาดช่องจาง ๆ ให้ครบหกช่องเสมอ (เจ้าของเซิร์ฟเลือกข้อ 4ก)
-- ถ้าปล่อยเป็น nil ตารางที่ส่งข้ามสายจะมีรูโหว่ แล้ว ipairs ฝั่งจอจะหยุดที่รูแรก
-- ------------------------------------------------------------------------------
local function slotOf(h, i)
    i = math.floor(tonumber(i) or 0)
    if i < 1 or i > KR.HFPACK.SLOTS then return nil end
    h.packs[i] = h.packs[i] or { set = false }
    return h.packs[i]
end

-- ------------------------------------------------------------------------------
-- จำนวน HF ที่ผู้เล่นจะได้จริงจากแพ็กใบนี้  รวมโบนัสแล้ว
-- แยกออกมาเพราะมีสามที่ที่ต้องใช้ (ตอนโชว์ ตอนอนุมัติ ตอนจดประวัติ)
-- และตัวเลขที่คิดคนละที่คือตัวเลขที่วันหนึ่งจะไม่ตรงกัน
-- ------------------------------------------------------------------------------
local function hfOf(p)
    if type(p) ~= "table" then return 0 end
    return math.max(0, math.floor(tonumber(p.hf) or 0))
         + math.max(0, math.floor(tonumber(p.bonus) or 0))
end

-- ------------------------------------------------------------------------------
-- ประวัติ  วงแหวนเหมือน hflog ของ KR_Server
-- ตัดหัวเป็นก้อนไม่ใช่ทีละแถว  table.remove(1) ทุกครั้งคือ O(n) ทุกครั้ง
-- ------------------------------------------------------------------------------
local function logPack(h, row)
    h.log = h.log or {}
    h.log[#h.log + 1] = row
    local max = KR.HFPACK.LOG_MAX
    if #h.log > max then
        local keep = {}
        for i = #h.log - max + 1, #h.log do keep[#keep + 1] = h.log[i] end
        h.log = keep
    end
end

-- ------------------------------------------------------------------------------
-- เก็บกวาดคำขอที่จบแล้ว
--
-- คำขอที่ยัง "รออนุมัติ" ห้ามลบเด็ดขาดไม่ว่าจะเก่าแค่ไหน  มันคือคนที่จ่ายเงินมาแล้ว
-- ที่ลบได้คือคำขอที่มีคนตัดสินไปแล้ว (ส่งแล้ว / ปฏิเสธ / ผู้เล่นถอนเอง)
-- และเก็บไว้อีกสามวันให้ผู้เล่นเห็นผลก่อน ไม่ใช่หายทันทีจนเขาไม่รู้ว่าเกิดอะไรขึ้น
-- ------------------------------------------------------------------------------
local KEEP_DONE = 3 * 86400

local function sweep(h, ts)
    local keep = {}
    for _, r in ipairs(h.reqs) do
        local live = (r.st == KR.HFP_ST.WAIT)
                  or ((tonumber(r.doneAt) or ts) + KEEP_DONE > ts)
        if live then keep[#keep + 1] = r end
    end
    h.reqs = keep
end

-- ------------------------------------------------------------------------------
-- หาคำขอจากไอดี  คืนตัวแถวกับตำแหน่ง
-- ------------------------------------------------------------------------------
local function reqOf(h, id)
    id = tonumber(id)
    if not id then return nil end
    for i, r in ipairs(h.reqs) do
        if r.id == id then return r, i end
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- เติม HF ให้คีย์หนึ่ง  ใช้ได้ทั้งคนออนไลน์และออฟไลน์
--
-- S.addHF ของ KR_Server รับ "ตัวผู้เล่น" ไม่ใช่คีย์  จึงใช้กับคนออฟไลน์ไม่ได้
-- และเคสหลักของไฟล์นี้คือคนออฟไลน์ (โอนเงินแล้วปิดเกม)
-- เขียนตัวที่รับคีย์แทนที่จะดัดของเดิม เพราะของเดิมมีที่ใช้อยู่แล้วหลายที่
-- ------------------------------------------------------------------------------
local function giveHF(k, n)
    local row = P(k)
    local before = row.hf or 0
    row.hf = math.max(0, before + math.floor(tonumber(n) or 0))
    return row.hf - before
end

-- ------------------------------------------------------------------------------
-- บอกผู้เล่นคนหนึ่ง ถ้าเขาออนไลน์อยู่  ออฟไลน์ก็เงียบไป ไม่ใช่ error
-- ------------------------------------------------------------------------------
local function tell(k, msg, tone)
    local p = S.onlineByKey and S.onlineByKey(k)
    if not p then return false end
    alert(p, msg, tone or "good")
    S.sync(p)
    return true
end

-- ------------------------------------------------------------------------------
-- บอกแอดมินทุกคนที่ออนไลน์อยู่
--
-- ตัวจริงอยู่ใน KR_Server เพราะ KR_Credit ก็ต้องใช้ (ตอนมีคนโดนล็อกร้าน)
-- และ KR_Credit โหลดก่อนไฟล์นี้ตามตัวอักษร  ถ้าประกาศไว้ที่นี่มันจะเป็น nil ตอนนั้น
-- ห่อไว้กันเคสที่ KR_Server รุ่นเก่ายังไม่มี
-- ------------------------------------------------------------------------------
local function tellAdmins(msg, tone)
    if type(S.tellAdmins) == "function" then return S.tellAdmins(msg, tone) end
    return 0
end

-- ==============================================================================
-- สิ่งที่ส่งให้ไคลเอนต์ทุก sync
--
-- แยกฝั่งผู้เล่นกับฝั่งแอดมินตั้งแต่ตรงนี้ ไม่ใช่ส่งทุกอย่างแล้วให้จอเลือกวาด
-- ของที่ส่งออกจากเซิร์ฟแล้วถือว่าหลุดแล้ว  ไคลเอนต์ที่ถูกแก้จะวาดทุกอย่างที่ได้รับ
-- (หลักเดียวกับที่ S.sync ตัดของที่ซ่อนไว้ออกจาก catalog ของผู้เล่นธรรมดา)
--
-- ผู้เล่นจึงไม่ได้เห็น: ช่องอ้างอิงการโอนของคนอื่น · คำขอของคนอื่น · แพ็กที่ปิดอยู่
-- ==============================================================================
function S.hfpRows(player, ts)
    ts = ts or nowOf()
    local h = H()
    local k = key(player)
    local adm = isAdmin(player)

    sweep(h, ts)

    -- ---- แพ็ก ----------------------------------------------------------------
    local packs = {}
    for i = 1, KR.HFPACK.SLOTS do
        local p = slotOf(h, i)
        local price, was = KR.hfpPrice(p, ts)
        local open, why  = KR.hfpOpen(p, ts)

        -- ผู้เล่นเห็นช่องว่างเป็นช่องว่าง  แต่ไม่เห็นค่าที่แอดมินตั้งค้างไว้แล้วปิดไว้
        -- แอดมินเห็นทุกอย่างเพราะเขาคือคนที่ต้องแก้มัน
        local row = {
            slot = i,
            kind = KR.hfpKind(i),
            set  = p.set and true or false,
            open = open,
            why  = (not open) and why or nil,
        }
        if p.set and (adm or not p.off) then
            row.name  = p.name
            row.hf    = math.floor(tonumber(p.hf) or 0)
            row.bonus = math.floor(tonumber(p.bonus) or 0)
            row.total = hfOf(p)
            row.thb   = price
            row.was   = was                      -- ราคาก่อนลด  มีเฉพาะช่อง 8 ตอนลดอยู่
            row.icon  = p.icon or KR.HFP_ICON_DEFAULT

            if i == KR.HFPACK.LIMITED then
                local cap = tonumber(p.stock) or 0
                row.stock = cap > 0 and cap or nil
                row.sold  = math.floor(tonumber(p.sold) or 0)
                local e = tonumber(p.endsAt)
                row.left  = e and math.max(0, e - ts) or nil
                row.per   = tonumber(p.per)
            elseif i == KR.HFPACK.MEGA then
                local e = tonumber(p.cutEndsAt)
                row.left = e and math.max(0, e - ts) or nil
            end
        end
        if adm then
            row.off      = p.off and true or nil
            row.rawMins  = p.rawMins                 -- ค่าที่แอดมินพิมพ์ไว้ ไม่ใช่ที่คำนวณแล้ว
            row.rawCut   = p.rawCut
            row.thbFull  = math.floor(tonumber(p.thb) or 0)
            row.thbCut   = tonumber(p.thbCut)
        end
        packs[i] = row
    end

    -- ---- คำขอ ----------------------------------------------------------------
    local mine, pend = {}, nil
    for _, r in ipairs(h.reqs) do
        if r.k == k then
            mine[#mine + 1] = { id = r.id, slot = r.slot, name = r.name,
                                hf = r.hf, thb = r.thb, at = r.at,
                                st = r.st, by = r.by, doneAt = r.doneAt }
        end
    end

    if adm then
        pend = {}
        for _, r in ipairs(h.reqs) do
            if r.st == KR.HFP_ST.WAIT then
                pend[#pend + 1] = { id = r.id, who = r.disp or r.k, k = r.k,
                                    slot = r.slot, name = r.name,
                                    hf = r.hf, thb = r.thb, at = r.at,
                                    online = (S.onlineByKey and S.onlineByKey(r.k)) ~= nil }
            end
        end
        -- เก่าสุดขึ้นก่อน  คนที่รอนานที่สุดควรได้รับการจัดการก่อน
        table.sort(pend, function(a, b) return (a.at or 0) < (b.at or 0) end)
    end

    return { packs = packs, mine = mine, pend = pend,
             waiting = pend and #pend or nil }
end

-- ==============================================================================
-- ผู้เล่น : ส่งคำขอซื้อ
-- ==============================================================================
function S.hfpReq(player, args)
    local k = key(player); if not k then return end
    local ts = nowOf()
    local h  = H()
    sweep(h, ts)

    local i = math.floor(tonumber(args and args.slot) or 0)
    local p = slotOf(h, i)
    if not p then return alert(player, "No such pack.", "bad") end

    -- ต้องตรวจซ้ำที่นี่แม้จอจะตรวจให้แล้ว
    -- จอที่ถูกแก้ส่งอะไรมาก็ได้ และแพ็กอาจหมดไปแล้วระหว่างที่เขาเปิดจอค้างไว้
    local open, why = KR.hfpOpen(p, ts)
    if not open then
        local msg = "That pack is not available."
        if why == "sold"  then msg = "That pack is sold out." end
        if why == "ended" then msg = "That pack has ended." end
        return alert(player, msg, "bad")
    end

    -- กันคำขอซ้ำ  คนที่กดแล้วไม่เห็นอะไรเปลี่ยนจะกดอีก แล้วแอดมินได้ใบซ้ำสิบใบ
    local waiting, sameSlot = 0, false
    for _, r in ipairs(h.reqs) do
        if r.k == k and r.st == KR.HFP_ST.WAIT then
            waiting = waiting + 1
            if r.slot == i then sameSlot = true end
        end
    end
    if sameSlot then
        return alert(player, "You already have a pending request for that pack.", "bad")
    end
    if waiting >= KR.HFPACK.REQ_MAX then
        return alert(player, "You already have " .. waiting ..
                             " requests waiting. Wait for an admin first.", "bad")
    end

    -- เพดานรายคนของแพ็กจำกัด  นับทั้งที่ส่งแล้วและที่ยังรออยู่
    -- ถ้านับแต่ที่ส่งแล้ว คนหนึ่งจะยิงคำขอสิบใบก่อนแอดมินตื่นแล้วได้ครบสิบ
    local per = tonumber(p.per)
    if per and per > 0 then
        local got = 0
        for _, r in ipairs(h.reqs) do
            if r.k == k and r.slot == i
               and (r.st == KR.HFP_ST.WAIT or r.st == KR.HFP_ST.DONE) then
                got = got + 1
            end
        end
        if got >= per then
            return alert(player, "This pack is limited to " .. per .. " per player.", "bad")
        end
    end

    local price = KR.hfpPrice(p, ts)
    local row = {
        id   = h.next,
        k    = k,
        disp = P(k).disp or k,
        slot = i,
        name = p.name or ("Pack " .. i),
        hf   = hfOf(p),
        thb  = price,
        at   = ts,
        st   = KR.HFP_ST.WAIT,
    }
    h.next = h.next + 1
    h.reqs[#h.reqs + 1] = row

    alert(player, "Request sent to the admins: " .. tostring(row.name) ..
                  "  (" .. row.hf .. " HF)  " .. price .. " THB. " ..
                  "Transfer the money the way the server announced, then wait for an admin.",
          "good")

    tellAdmins("HF pack request from " .. tostring(row.disp) ..
                 ": " .. tostring(row.name) .. "  " .. price .. " THB", "warn")

    S.sync(player)
    S.syncAll()
end

-- ==============================================================================
-- ผู้เล่น : ถอนคำขอของตัวเอง
-- ==============================================================================
function S.hfpCancel(player, args)
    local k = key(player); if not k then return end
    local h = H()
    local r = reqOf(h, args and args.id)

    if not r or r.k ~= k then return alert(player, "No such request.", "bad") end
    if r.st ~= KR.HFP_ST.WAIT then
        return alert(player, "That request was already handled.", "bad")
    end

    r.st     = KR.HFP_ST.GONE
    r.doneAt = nowOf()
    alert(player, "Request withdrawn.", "good")
    S.sync(player)
    S.syncAll()
end

-- ==============================================================================
-- แอดมิน : อนุมัติ (= ส่งให้เลย) หรือ ปฏิเสธ
--
-- อนุมัติกับส่งเป็นปุ่มเดียวโดยตั้งใจ  ไม่มีเคสที่อนุมัติแล้วไม่ส่ง
-- การแยกสองขั้นจะสร้างสถานะที่สามที่ไม่มีใครดูแล และคำขอจะไปค้างอยู่ตรงนั้น
-- ==============================================================================
function S.hfpAct(player, args)
    local ts = nowOf()
    local h  = H()
    local r  = reqOf(h, args and args.id)
    if not r then return alert(player, "No such request.", "bad") end
    if r.st ~= KR.HFP_ST.WAIT then
        return alert(player, "Already handled by " .. tostring(r.by or "someone") .. ".", "bad")
    end

    local by   = key(player)
    local note = KR.trunc(args and args.note, KR.HFPACK.NOTE_MAX)
    local ok   = (args and args.ok) and true or false

    if not ok then
        r.st, r.by, r.doneAt, r.note = KR.HFP_ST.DENY, by, ts, note
        logPack(h, { at = ts, kind = "deny", to = r.k, by = by,
                     slot = r.slot, hf = r.hf, thb = r.thb, note = note })
        alert(player, "Rejected " .. tostring(r.disp) .. "'s request.", "good")
        tell(r.k, "An admin rejected your HF pack request." ..
                  (note ~= "" and ("  (" .. note .. ")") or ""), "bad")
        S.syncAll()
        return
    end

    -- ---- อนุมัติ -------------------------------------------------------------
    local got = giveHF(r.k, r.hf)

    -- นับยอดขายของแพ็กจำกัด **ตอนอนุมัติ** ไม่ใช่ตอนขอ
    -- ตอนขอยังไม่มีเงินเข้า  ถ้านับตอนนั้นคนที่กดขอเล่นแล้วถอนจะกินโควตาของคนที่จ่ายจริง
    local p = slotOf(h, r.slot)
    if p and r.slot == KR.HFPACK.LIMITED then
        p.sold = math.floor(tonumber(p.sold) or 0) + 1
    end

    r.st, r.by, r.doneAt, r.note = KR.HFP_ST.DONE, by, ts, note

    logPack(h, { at = ts, kind = "send", to = r.k, by = by,
                 slot = r.slot, hf = got, thb = r.thb, note = note })

    alert(player, "Sent " .. got .. " HF to " .. tostring(r.disp) .. ".", "good")
    tell(r.k, "An admin approved your request. " .. got .. " HF added to your account.", "good")
    S.syncAll()
end

-- ==============================================================================
-- แอดมิน : ส่งให้เลยโดยไม่ต้องมีคำขอ
--
-- ใช้ได้สองแบบ  ระบุช่องแพ็ก หรือใส่จำนวน HF เอง
-- เหตุผลต้องกรอกเสมอ  มันเข้าประวัติ และประวัติที่ไม่มีเหตุผลคือประวัติที่อ่านไม่รู้เรื่อง
-- (กฎเดียวกับ S.adminGrant ที่บังคับกรอก reason มาตั้งแต่ต้น)
-- ==============================================================================
function S.hfpSend(player, args)
    local ts = nowOf()
    local h, d = H()

    local to = tostring((args and args.to) or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if to == "" or not d.players[to] then
        return alert(player, "No player named '" .. tostring(args and args.to) .. "'.", "bad")
    end

    local why = KR.trunc(args and args.reason, 48)
    if why == "" then return alert(player, "Write a reason. It goes in the log.", "bad") end

    local slot = math.floor(tonumber(args and args.slot) or 0)
    local amt, label = 0, why

    if slot >= 1 and slot <= KR.HFPACK.SLOTS then
        local p = slotOf(h, slot)
        if not p.set then return alert(player, "That pack slot is empty.", "bad") end
        amt   = hfOf(p)
        label = tostring(p.name or ("Pack " .. slot))
        if slot == KR.HFPACK.LIMITED then
            p.sold = math.floor(tonumber(p.sold) or 0) + 1
        end
    else
        amt = math.floor(tonumber(args and args.hf) or 0)
        if amt <= 0 then return alert(player, "Enter an HF amount or pick a pack.", "bad") end
    end

    local got = giveHF(to, amt)
    logPack(h, { at = ts, kind = "direct", to = to, by = key(player),
                 slot = (slot >= 1 and slot <= KR.HFPACK.SLOTS) and slot or nil,
                 hf = got, note = why })

    alert(player, "Sent " .. got .. " HF to " .. tostring(P(to).disp or to) ..
                  "  (" .. label .. ")", "good")
    tell(to, "An admin sent you " .. got .. " HF.  (" .. why .. ")", "good")
    S.syncAll()
end

-- ==============================================================================
-- แอดมิน : ตั้งค่าแพ็กหนึ่งช่อง
--
-- ทุกช่องเวลาที่รับเข้ามาเป็น **นาที** ตามที่เจ้าของเซิร์ฟสั่ง
-- แล้วเก็บลงฐานเป็นเวลาจริง (epoch วินาที) ที่มันจะหมดอายุ
--
-- ทำไมเก็บเป็นเวลาหมดอายุแทนที่จะเก็บ "นาน 3 วัน"
--   เพราะ "นาน 3 วัน" ต้องมีจุดเริ่มต้น แล้วจุดเริ่มต้นนั้นจะขยับทุกครั้งที่แอดมิน
--   เผลอกดบันทึกซ้ำ  แพ็กที่ตั้งใจให้จบวันเสาร์จะเลื่อนไปเรื่อย ๆ โดยไม่มีใครสังเกต
-- เก็บนาทีที่กรอกไว้ด้วย (rawMins) เพื่อให้เปิดฟอร์มมาเห็นค่าเดิมที่ตัวเองพิมพ์
-- ==============================================================================
function S.hfpSet(player, args)
    local ts = nowOf()
    local h  = H()

    local i = math.floor(tonumber(args and args.slot) or 0)
    local p = slotOf(h, i)
    if not p then return alert(player, "No such pack slot.", "bad") end

    -- ล้างช่อง
    if args and args.clear then
        h.packs[i] = { set = false }
        alert(player, "Cleared pack slot " .. i .. ".", "good")
        S.syncAll()
        return
    end

    local name  = KR.trunc(args and args.name, KR.HFPACK.NAME_MAX)
    local hf    = math.floor(tonumber(args and args.hf) or 0)
    local bonus = math.max(0, math.floor(tonumber(args and args.bonus) or 0))
    local thb   = math.floor(tonumber(args and args.thb) or 0)

    if name == "" then return alert(player, "The pack needs a name.", "bad") end
    if hf <= 0     then return alert(player, "HF amount must be more than zero.", "bad") end
    if thb <= 0    then return alert(player, "Price must be more than zero.", "bad") end

    p.set   = true
    p.name  = name
    p.hf    = hf
    p.bonus = bonus
    p.thb   = thb
    p.icon  = KR.hfpIconOk(args and args.icon) and args.icon or KR.HFP_ICON_DEFAULT
    p.off   = (args and args.off) and true or nil

    if i == KR.HFPACK.LIMITED then
        local mins = tonumber(args and args.mins)
        p.rawMins  = mins
        local sec  = KR.minsToSec(mins)
        p.endsAt   = sec and (ts + sec) or nil
        p.stock    = math.max(0, math.floor(tonumber(args and args.stock) or 0))
        p.per      = math.max(0, math.floor(tonumber(args and args.per) or 0))
        if p.stock == 0 then p.stock = nil end
        if p.per   == 0 then p.per   = nil end
        -- ยอดขายเดิมไม่รีเซ็ตตอนแก้ค่า  แอดมินที่แค่แก้ราคาไม่ได้ตั้งใจเปิดรอบใหม่
        -- ถ้าอยากเริ่มนับใหม่ ให้ล้างช่องแล้วตั้งใหม่ ซึ่งเป็นการกระทำที่ชัดเจนกว่า
        p.sold = math.floor(tonumber(p.sold) or 0)

    elseif i == KR.HFPACK.MEGA then
        local cut = tonumber(args and args.thbCut)
        if cut and cut > 0 and cut < thb then
            p.thbCut = math.floor(cut)
            local mins = tonumber(args and args.cutMins)
            p.rawCut   = mins
            local sec  = KR.minsToSec(mins)
            p.cutEndsAt = sec and (ts + sec) or nil
        else
            p.thbCut, p.cutEndsAt, p.rawCut = nil, nil, nil
        end
    end

    alert(player, "Saved pack slot " .. i .. ".", "good")
    S.syncAll()
end

print("[Kuraya] KR_HFPack ready")
return true
