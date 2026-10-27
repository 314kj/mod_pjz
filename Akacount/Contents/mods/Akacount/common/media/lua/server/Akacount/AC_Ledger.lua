-- ==============================================================================
-- Akacount — server/Akacount/AC_Ledger.lua
-- move / mint / burn  +  escrow (hold / release / capture)
-- ==============================================================================
--
-- ทำไมไม่มี two-phase ตรงนี้
--   AkaShop ต้องทำ two-phase เพราะเงินเป็นของ ไคลเอนต์ต้องเป็นคนย้าย เซิร์ฟต้องเชื่อ
--   แล้วค่อยตรวจ  พอเงินเป็นข้อมูลบนเซิร์ฟเวอร์ การหักเงินคือการเปลี่ยนตัวเลข
--   ในเครื่องเซิร์ฟ ทำได้ทันที อะตอมมิก โกงไม่ได้  ไม่ต้องมี txn ไม่ต้อง sweep
--   two-phase ยังต้องใช้อยู่ "เฉพาะตอนไอเทมเปลี่ยนมือ" เท่านั้น -> ดู AC_Server.lua
--
-- move() ต้องอะตอมมิกจริง
--   เช็ค -> หัก -> เติม -> log อยู่ในฟังก์ชันเดียว ไม่มี yield ไม่มี event
--   ไม่มี pcall คั่นกลาง  ถ้าล้มต้องล้มก่อนหักเงิน ไม่ใช่ระหว่างทาง
-- ==============================================================================
require("Akacount/AC_Const")
require("Akacount/AC_Util")
require("Akacount/AC_DB")

AC.ledger = AC.ledger or {}
local L = AC.ledger
local D = AC.db
local U = AC.util

-- guard ต้อง "คืนค่าเงียบ ๆ" ไม่ใช่ error()
--
-- เวอร์ชันแรกเขียน error(...) ไว้ ผลคือบนไคลเอนต์ MP มันโยน KahluaException
-- แล้ว **ฆ่า handler ทั้งตัวที่เรียกมัน** — OnInitGlobalModData เลยตายกลางคัน
-- ทำให้ checkInvariant กับ log "server ready" ไม่เคยรัน และ EveryOneMinute
-- สแปม stack trace ทุกนาที (เจอ 56 ครั้งใน console.txt ครั้งแรกที่เทส)
--
-- ของจริงต้องเป็น no-op เงียบ ๆ เพราะไคลเอนต์ไม่ควรรันโค้ดพวกนี้อยู่แล้ว
local _warned = {}
local function guardServer(fn)
    if AC.util.isHost() then return true end
    if not _warned[fn] then
        _warned[fn] = true
        AC.util.log(fn .. " skipped on client side (this is normal)")
    end
    return false
end

-- ยอดใช้ได้จริง = bal - hold
-- hold แยกจาก bal ไม่หักออกจาก bal  เวลา escrow ค้างเพราะเซิร์ฟล่ม ผู้เล่นจะเห็นว่า
-- "ติดค้างอยู่ 200 ที่ล็อต #77" ซึ่งตามไปแก้ได้ ไม่ใช่เห็นเงินหายไปเฉย ๆ
local function availOf(a)
    return (a.bal or 0) - (a.hold or 0)
end

local function credit(id, amt)
    if AC.isSys(id) then D.addSys(id, amt); return true end
    local a = D.account(id, true)
    if not a then return false end
    a.bal = (a.bal or 0) + amt
    return true
end

local function debit(id, amt, allowOverdraft)
    if AC.isSys(id) then D.addSys(id, -amt); return true end
    local a = D.account(id, true)
    if not a then return false, "no account" end
    local floor = allowOverdraft and (tonumber(U.opt("OverdraftFloor")) or 0) or 0
    if availOf(a) - amt < floor then return false, "insufficient" end
    a.bal = (a.bal or 0) - amt
    return true
end

-- ------------------------------------------------------------------------------
-- meta  =  { by = "ชื่อคนที่กดทำรายการ", kind = "ทับชนิดที่อนุมานได้" }
--
-- ทำไมต้องจด by ทั้งที่มี from/to อยู่แล้ว
--   from/to ของรายการที่ระบบทำให้เป็นบัญชีระบบ เช่น SYS:ADMIN  ซึ่งตอบไม่ได้ว่า
--   "แอดมินคนไหน" เป็นคนกด  สามเดือนหลังจากนั้นไม่มีใครจำได้ และย้อนไปหาไม่ได้เลย
--   เจ้าของเซิร์ฟขอมาตรง ๆ ว่าสมุดบัญชีต้องบอก "ชื่อคนทำรายการ" ไม่ใช่แค่ชนิดรายการ
--
--   เก็บเป็น "ชื่อที่ใช้โชว์" (disp) ไม่ใช่คีย์ตัวพิมพ์เล็ก เพราะฟิลด์นี้มีไว้อ่านอย่างเดียว
--   ห้ามเอาไปเทียบว่าเป็นใคร (การเทียบใช้ f/to เหมือนเดิม)
-- ------------------------------------------------------------------------------
local function write(from, to, amt, kind, ref, via, meta)
    D.append({
        t   = U.realTs(),
        gh  = U.gameHour(),
        f   = from,
        to  = to,
        a   = amt,
        k   = (meta and meta.kind and AC.KIND_OK[meta.kind] and meta.kind) or kind,
        r   = ref,
        via = via or AC.VIA.SYSTEM,
        by  = meta and meta.by or nil,
    })
end

-- ------------------------------------------------------------------------------
-- ย้ายเงินระหว่างสองบัญชี  ไม่สร้างไม่ทำลาย
-- ------------------------------------------------------------------------------
function L.move(from, to, amt, kind, ref, via, allowOverdraft, meta)
    if not guardServer("move") then return false, "client side" end
    amt = math.floor(tonumber(amt) or 0)
    if amt <= 0            then return false, "amount must be positive" end
    if not from or not to  then return false, "missing party" end
    if from == to          then return false, "same account" end

    local ok, err = debit(from, amt, allowOverdraft)
    if not ok then return false, err end
    credit(to, amt)
    write(from, to, amt, kind, ref, via, meta)
    return true
end

-- ------------------------------------------------------------------------------
-- เงินเกิด / เงินตาย  ต้องมาจาก faucet และไปที่ sink ที่มีชื่ออยู่ในลิสต์เท่านั้น
-- ------------------------------------------------------------------------------
function L.mint(to, amt, faucet, ref, via, meta)
    if not guardServer("mint") then return false, "client side" end
    amt = math.floor(tonumber(amt) or 0)
    if amt <= 0 then return false, "amount must be positive" end
    if not AC.FAUCETS[faucet] then return false, "not a faucet: " .. tostring(faucet) end
    D.addSys(faucet, -amt)          -- บัญชีระบบติดลบ = เงินที่ระบบปล่อยออกไป
    credit(to, amt)
    -- ชนิดมาจากก๊อกที่เงินไหลออกมา ไม่ใช่ ADMIN ทับทุกกรณีเหมือนเดิม
    -- (เหตุผลเต็ม ๆ อยู่ที่ AC.FAUCET_KIND ใน AC_Const.lua)
    write(faucet, to, amt, AC.FAUCET_KIND[faucet] or AC.KIND.ADMIN, ref, via, meta)
    return true
end

function L.burn(from, amt, sink, ref, via, allowOverdraft, meta)
    if not guardServer("burn") then return false, "client side" end
    amt = math.floor(tonumber(amt) or 0)
    if amt <= 0 then return false, "amount must be positive" end
    if not AC.SINKS[sink] then return false, "not a sink: " .. tostring(sink) end
    local ok, err = debit(from, amt, allowOverdraft)
    if not ok then return false, err end
    D.addSys(sink, amt)
    write(from, sink, amt, AC.SINK_KIND[sink] or AC.KIND.FEE, ref, via, meta)
    return true
end

-- ------------------------------------------------------------------------------
-- escrow
--   primitive ที่คุ้มที่สุดในทั้งโปรเจกต์  ประมูล กระดานสั่งซื้อ สัญญาระหว่างผู้เล่น
--   เงินมัดจำ ใช้สามฟังก์ชันนี้หมด เขียนดี ๆ ครั้งเดียวแล้วเลิกคิดเรื่องนี้ไปตลอด
-- ------------------------------------------------------------------------------
function L.hold(name, amt, ref)
    if not guardServer("hold") then return nil, "client side" end
    amt = math.floor(tonumber(amt) or 0)
    if amt <= 0 then return nil, "amount must be positive" end
    local a, k = D.account(name, true)
    if not a then return nil, "no account" end
    if availOf(a) < amt then return nil, "insufficient" end

    a.hold = (a.hold or 0) + amt
    local id = D.nextId("h")
    D.get().holds[id] = { who = k, amt = amt, ref = ref, at = U.realTs() }
    write(k, AC.SYS.ESCROW, amt, AC.KIND.ESCROW, ref, AC.VIA.SYSTEM)
    return id
end

function L.release(holdId)
    if not guardServer("release") then return false, "client side" end
    local db = D.get()
    local h  = db.holds[holdId]
    if not h then return false, "no such hold" end     -- release ซ้ำต้องไม่คืนสองรอบ
    db.holds[holdId] = nil

    local a = D.account(h.who, true)
    if a then a.hold = math.max(0, (a.hold or 0) - h.amt) end
    write(AC.SYS.ESCROW, h.who, h.amt, AC.KIND.ESCROW, h.ref, AC.VIA.SYSTEM)
    return true
end

function L.capture(holdId, to, kind)
    if not guardServer("capture") then return false, "client side" end
    local db = D.get()
    local h  = db.holds[holdId]
    if not h then return false, "no such hold" end
    db.holds[holdId] = nil

    local a = D.account(h.who, true)
    if a then
        a.hold = math.max(0, (a.hold or 0) - h.amt)
        a.bal  = (a.bal or 0) - h.amt
    end
    credit(to, h.amt)
    write(h.who, to, h.amt, kind or AC.KIND.ESCROW, h.ref, AC.VIA.SYSTEM)
    return true
end

-- กวาด escrow ที่ค้างเกินอายุ  เรียกตอนบูตและทุก 1 นาที
-- เซิร์ฟรีสตาร์ทระหว่างดีลเป็นเรื่องปกติมาก ถ้าไม่กวาดตอนบูต เงินจะล็อกอยู่ตลอดกาล
function L.sweepHolds(maxAgeSec)
    if not guardServer("sweepHolds") then return 0 end
    local db  = D.get()
    local now = U.realTs()
    local n   = 0
    for id, h in pairs(db.holds) do
        if (now - (h.at or 0)) > (maxAgeSec or 172800) then
            L.release(id); n = n + 1
        end
    end
    if n > 0 then U.log("released", n, "stale hold(s)") end
    return n
end

L.avail = availOf

return L
