-- ==============================================================================
-- Akacount — server/Akacount/AC_DB.lua
-- ModData store + schema + migrate + invariant check
-- ==============================================================================
require("Akacount/AC_Const")
require("Akacount/AC_Util")

AC.db = AC.db or {}
local D = AC.db
local U = AC.util

local _cache = nil

-- ------------------------------------------------------------------------------
-- โครง
-- ------------------------------------------------------------------------------
-- HFEcon แยกสอง key: เงินอยู่กับ Akacount, ของอยู่กับ Kuraya
-- ModData ถูก serialize ทั้ง key ทุกครั้งที่เซฟ ถ้ารวมกัน การเซฟข้อมูลร้าน
-- จะลากข้อมูลเงินไปเขียนดิสก์ด้วยทุกครั้ง และที่สำคัญกว่า — migration ของฝั่งร้าน
-- ที่พลาดจะไม่มีทางแตะเงินได้เลย เงินคือสิ่งเดียวที่หายแล้วผู้เล่นให้อภัยไม่ได้
--
-- accounts[key] = {
--     disp   = "Somchai",
--     bal    = 0,        -- สตางค์  ติดลบได้ถึง OverdraftFloor
--     hold   = 0,        -- ถูก escrow ล็อกไว้  ยอดใช้ได้จริง = bal - hold
--     accrAt = 0,        -- realTs ครั้งสุดท้ายที่คิดดอก
--     skin   = "hfpz_red",
--     owned  = { hfpz_red = true },   -- ลายที่ปลดแล้ว
--     hasCard = true,    -- เคยรับบัตรไปจากเคาน์เตอร์แล้ว  ใช้คัดว่าใครโอนหาได้
--                        -- ต้องอยู่ที่ "บัญชี" เท่านั้น ห้ามไปดูจากกระเป๋า
--                        -- เพราะกระเป๋าตอบได้เฉพาะตอนคนนั้นออนไลน์ ซึ่งเป็นสิ่งที่เราเพิ่งเลิกใช้
--                        -- ทำบัตรหาย/โดนขโมย ก็ยังรับโอนได้ตามเดิม เงินไม่ได้อยู่ในบัตร
--     sentAt = 0,        -- realTs ของการโอนครั้งล่าสุด (คูลดาวน์)
--     sentD  = 0,        -- ยอดที่โอนไปแล้ววันนี้
--     sentDK = 0,        -- dayKey ของ sentD
--     flags  = 0,        -- bit1 frozen  bit2 blacklist
-- }
-- ------------------------------------------------------------------------------

local function blank()
    return {
        v        = AC.SCHEMA,
        accounts = {},
        sys      = {},
        ledger   = { head = 0, n = 0, e = {} },
        agg      = {},
        holds    = {},
        counters = {},   -- ตู้ธนาคารที่แอดมินลงทะเบียน  ทุกตู้ใช้ค่าเดียวกัน
        meta     = { nextId = 1 },
    }
end

-- โซ่ migrate v1 -> v2 -> v3  ห้ามข้ามขั้น
local MIGRATIONS = {
    -- [1] = function(db) ... db.v = 2 end,
}

local function migrate(db)
    while db.v and db.v < AC.SCHEMA do
        local step = MIGRATIONS[db.v]
        if not step then
            U.log("no migration from schema", db.v, "-> bumping without change")
            db.v = db.v + 1
        else
            local bak = ModData.getOrCreate(string.format(AC.DB_BAK_FMT, db.v))
            if bak and not bak.saved then
                bak.saved = true
                bak.v     = db.v
                U.log("backup written before migrating from v" .. tostring(db.v))
            end
            step(db)
        end
    end
end

function D.get()
    if _cache then return _cache end
    local db = ModData.getOrCreate(AC.DB_KEY)
    if not db.v then
        for k, v in pairs(blank()) do db[k] = v end
        U.log("fresh DB created  schema v" .. AC.SCHEMA)
    else
        migrate(db)
    end
    db.counters = db.counters or {}
    _cache = db
    return db
end

function D.reset() _cache = nil end

-- ------------------------------------------------------------------------------
-- บัญชี
-- ------------------------------------------------------------------------------
function D.account(nameOrPlayer, createIfMissing)
    local k = U.key(nameOrPlayer)
    if not k then return nil, nil end
    local db = D.get()

    if AC.isSys(nameOrPlayer) then
        db.sys[nameOrPlayer] = db.sys[nameOrPlayer] or 0
        return nil, nameOrPlayer
    end

    local a = db.accounts[k]
    if not a and createIfMissing then
        a = {
            disp = (type(nameOrPlayer) == "string") and nameOrPlayer or U.disp(nameOrPlayer),
            bal = 0, hold = 0, accrAt = U.realTs(),
            skin = AC.CARD_SKIN_DEFAULT,
            owned = { [AC.CARD_SKIN_DEFAULT] = true },
            -- เปิดบัญชีแล้วยังไม่ได้แปลว่ามีบัตร  ต้องเดินไปรับที่เคาน์เตอร์เอง
            hasCard = false,
            sentAt = 0, sentD = 0, sentDK = 0, flags = 0,
        }
        db.accounts[k] = a
    end
    return a, k
end

function D.sysBal(id)
    local db = D.get()
    return db.sys[id] or 0
end

function D.addSys(id, delta)
    local db = D.get()
    db.sys[id] = (db.sys[id] or 0) + delta
end

function D.nextId(prefix)
    local db = D.get()
    db.meta.nextId = (db.meta.nextId or 1) + 1
    return prefix .. tostring(db.meta.nextId)
end

-- ------------------------------------------------------------------------------
-- ledger  ring buffer
-- ------------------------------------------------------------------------------
function D.append(entry)
    local db  = D.get()
    local L   = db.ledger
    local cap = tonumber(U.opt("LedgerCap")) or AC.LEDGER_CAP

    L.head = (L.head % cap) + 1
    L.e[L.head] = entry
    if L.n < cap then L.n = L.n + 1 end

    -- aggregate รายวัน  ring buffer ไว้ตามรอย aggregate ไว้ทำกราฟ
    -- สองชั้นนี้ทำคนละงาน อย่าใช้อาร์เรย์เดียวทำทั้งสองอย่าง
    local dk = U.dayKey(entry.t)
    local g  = db.agg[dk]
    if not g then g = { mint = 0, burn = 0, vol = 0, n = 0 }; db.agg[dk] = g end
    g.n = g.n + 1
    -- escrow เป็นการพักเงิน ไม่ใช่การซื้อขาย  ถ้านับเข้า vol ยอดหมุนเวียนจะบวมสองเท่า
    -- จากการ hold แล้ว release ที่ไม่มีอะไรเกิดขึ้นจริง
    if entry.f ~= AC.SYS.ESCROW and entry.to ~= AC.SYS.ESCROW then
        g.vol = g.vol + math.abs(entry.a or 0)
    end
    if AC.FAUCETS[entry.f] then g.mint = g.mint + (entry.a or 0) end
    if AC.SINKS[entry.to]   then g.burn = g.burn + (entry.a or 0) end

    -- ตัด aggregate เก่าทิ้ง
    local keep = tonumber(AC.AGG_DAYS) or 30
    for k in pairs(db.agg) do
        if k < dk - keep then db.agg[k] = nil end
    end
end

-- แถวล่าสุดของผู้เล่นคนเดียว  (ไล่ย้อนจาก head)
function D.tailFor(key, limit)
    local db  = D.get()
    local L   = db.ledger
    local cap = tonumber(U.opt("LedgerCap")) or AC.LEDGER_CAP
    local out = {}
    limit = limit or AC.CLIENT_TAIL
    local i, seen = L.head, 0
    while seen < L.n and #out < limit do
        local e = L.e[i]
        if e and (e.f == key or e.to == key) then out[#out + 1] = e end
        i = i - 1; if i < 1 then i = cap end
        seen = seen + 1
    end
    return out
end

-- ------------------------------------------------------------------------------
-- invariant
--   ผลรวมของทุกบัญชี (ผู้เล่น + SYS ทั้งหมด) ต้องเท่ากับ 0 เสมอ หลังทุกการดำเนินการ
--   ถ้าไม่เป็นศูนย์ แปลว่ามีโค้ดที่บวกเงินให้ใครโดยไม่หักจากใคร
--   เทสที่สุ่มลำดับหมื่นธุรกรรมแล้วเช็คข้อนี้ข้อเดียว จับบั๊กเสกเงินได้ทั้งหมด
-- ------------------------------------------------------------------------------
function D.sumAll()
    local db, s = D.get(), 0
    for _, a in pairs(db.accounts) do s = s + (a.bal or 0) end
    for _, v in pairs(db.sys)      do s = s + v end
    return s
end

function D.checkInvariant(where)
    local s = D.sumAll()
    if s ~= 0 then
        U.log("!! LEDGER INVARIANT BROKEN at", where or "?", "sum =", s)
        return false, s
    end
    return true, 0
end

return D
