-- ==============================================================================
-- Akacount — server/Akacount/AC_API.lua
-- ไฟล์เดียวที่ม็อดอื่นเห็น  กำหนด global `Akacount`
-- ==============================================================================
--
-- วิธีเรียกจากม็อดอื่น (Kuraya และม็อดสกินบัตร)
--
--   -- ผิด : ถ้า Akacount โหลดทีหลัง จะได้ nil ค้างตลอดเซสชัน
--   local Econ = Akacount
--
--   -- ถูก : resolve ตอนเรียกทุกครั้ง
--   local function econ()
--       if not Akacount then return nil end
--       return Akacount
--   end
--
-- แพตเทิร์นเดียวกับ col("money") ของ AkaShop ที่ resolve ตอนใช้เพื่อกัน load order
-- ==============================================================================
require("Akacount/AC_Const")
require("Akacount/AC_Util")
require("Akacount/AC_DB")
require("Akacount/AC_Ledger")

Akacount = Akacount or {}
local API = Akacount
local D, L, U = AC.db, AC.ledger, AC.util

API.VERSION = AC.VERSION
API.CURRENCY = "cash"          -- Akacount เป็นเจ้าของสกุลนี้สกุลเดียว
                               -- HF  -> Kuraya เป็นเจ้าของ
                               -- CP  -> HF Town Rank เป็นเจ้าของ

-- ------------------------------------------------------------------------------
-- อ่าน
-- ------------------------------------------------------------------------------
function API.balance(name)
    local a = D.account(name, false)
    return a and (a.bal or 0) or 0
end

function API.available(name)
    local a = D.account(name, false)
    return a and L.avail(a) or 0
end

function API.held(name)
    local a = D.account(name, false)
    return a and (a.hold or 0) or 0
end

function API.can(name, amt)
    return API.available(name) >= (math.floor(tonumber(amt) or 0))
end

function API.exists(name)
    return D.account(name, false) ~= nil
end

-- ยอดติดลบล็อกการ "ใช้เงิน" แต่ห้ามล็อกการ "หาเงิน"
-- ไม่งั้นคนที่ติดลบจะไม่มีทางกลับมาเป็นบวกแล้วเลิกเล่น
function API.isLocked(name)
    return API.balance(name) < 0
end

-- ------------------------------------------------------------------------------
-- เขียน  (เซิร์ฟเวอร์เท่านั้น — ไคลเอนต์เรียกแล้ว error ทันที)
-- ------------------------------------------------------------------------------
API.move    = L.move
API.mint    = L.mint
API.burn    = L.burn
API.hold    = L.hold
API.release = L.release
API.capture = L.capture

-- ------------------------------------------------------------------------------
-- ทางลัดที่ Kuraya ใช้บ่อย
-- ------------------------------------------------------------------------------
-- kind ที่ผู้เรียกส่งมาเคยถูกทิ้งเงียบ ๆ  ผลคือค่างวดเงินกู้ของ Kuraya
-- (B.charge(k, due, "repay", ...)) ไปโผล่ในสมุดว่า "ค่าธรรมเนียม"
-- ส่งต่อให้ ledger แล้ว  ชนิดที่ไม่มีอยู่จริงถูกโยนทิ้งที่นั่น
function API.charge(name, amt, kind, ref, via)
    if API.isLocked(name) then return false, "account overdrawn" end
    return L.burn(name, amt, AC.SYS.FEE, ref, via, false, kind and { kind = kind } or nil)
end

function API.payTo(from, to, amt, kind, ref, via)
    if API.isLocked(from) then return false, "account overdrawn" end
    return L.move(from, to, amt, kind or AC.KIND.SHOP, ref, via, false)
end

-- ------------------------------------------------------------------------------
-- ซื้อของที่จ่ายหลายสกุลพร้อมกัน
--
-- ปัญหาคือ CASH อยู่กับเรา แต่ CP อยู่ในม็อดคนอื่นที่เราสั่ง rollback ไม่ได้จริง
-- ถ้าหัก CASH ไปแล้วค่อยไปหัก CP ไม่ผ่าน เงินผู้เล่นหายฟรี
--
-- ทางออกคือฝั่งเราไม่หักก่อน แค่ "กันไว้"  ยอดยังอยู่ในบัญชีแต่ใช้ไม่ได้
-- ถ้าสกุลอื่นล้ม ปล่อยคืนแล้วจบ ไม่มีใครเสียอะไร
-- ถ้าครบทุกสกุลแล้วค่อยยึดเข้าคลังทีเดียว
--
-- สามฟังก์ชันนี้เป็นชื่อที่ Kuraya เรียก จะได้ไม่ต้องรู้จัก AC.SYS / AC.KIND ข้างใน
-- ------------------------------------------------------------------------------
function API.holdForPurchase(name, amt, ref)
    if API.isLocked(name) then return nil, "account overdrawn" end
    return L.hold(name, amt, ref)
end

function API.capturePurchase(holdId)
    return L.capture(holdId, AC.SYS.TAX, AC.KIND.SHOP)
end

function API.releaseHold(holdId)
    return L.release(holdId)
end

-- ------------------------------------------------------------------------------
-- ลายบัตร
--   ลายเก็บที่ผู้เล่น ไม่ใช่ที่ไอเทม  ทำบัตรหายแล้วต้องไม่เสียลายที่ซื้อไป
--   ม็อดสกินแยกเรียก registerCardSkin() ตอนโหลด
--   ถ้าม็อดสกินถูกถอด getPlayerSkin() ตกกลับมาที่ DEFAULT เอง ไม่พังและไม่ texture หาย
-- ------------------------------------------------------------------------------
local _skins, _order = {}, {}

function API.registerCardSkin(id, def)
    if type(id) ~= "string" or id == "" or type(def) ~= "table" then return false end
    if not def.texture then return false end
    if not _skins[id] then _order[#_order + 1] = id end
    _skins[id] = {
        id      = id,
        name    = def.name or id,
        texture = def.texture,                            -- ผิวโมเดล 3D
        icon    = def.icon or def.texture,                -- ไอคอนในกระเป๋า
        model   = def.model,                              -- ชื่อบล็อก model ใน .txt
        price   = math.floor(tonumber(def.price) or 0),   -- 0 = แจกฟรี ทุกคนใช้ได้เลย
        source  = def.source or "unknown",                -- ชื่อม็อดที่ลงทะเบียน
    }
    return true
end

-- ราคาที่แอดมินตั้งเอง  เก็บใน DB เพราะต้องอยู่ข้ามการรีสตาร์ท
-- ค่าคงที่ในโค้ดเป็นแค่ "ค่าตั้งต้น"  ของจริงคือสิ่งที่แอดมินตั้งไว้
local function priceOverride(id)
    local db = D.get()
    db.skinPrice = db.skinPrice or {}
    return db.skinPrice[id]
end

function API.setSkinPrice(id, price)
    if not _skins[id] then return false, "unknown skin" end
    local db = D.get()
    db.skinPrice = db.skinPrice or {}
    db.skinPrice[id] = math.max(0, math.floor(tonumber(price) or 0))
    return true
end

function API.skinPrice(id)
    local o = priceOverride(id)
    if o ~= nil then return o end
    return (_skins[id] and _skins[id].price) or 0
end

function API.getCardSkins(name)
    local out = {}
    for _, id in ipairs(_order) do
        local sk = _skins[id]
        out[#out + 1] = {
            id = sk.id, name = sk.name, icon = sk.icon, texture = sk.texture,
            model = sk.model, source = sk.source,
            price = API.skinPrice(id),
            owned = name and API.ownsSkin(name, id) or nil,
        }
    end
    return out
end

function API.skinExists(id) return _skins[id] ~= nil end

function API.getPlayerSkin(name)
    local a = D.account(name, false)
    local id = a and a.skin
    if id and _skins[id] then return id end
    return AC.CARD_SKIN_DEFAULT           -- fallback เมื่อม็อดสกินถูกถอด
end

-- ลายที่ราคา 0 = ของแถมประจำม็อด ทุกคนใช้ได้เลย ไม่ต้องปลดล็อก
-- (บั๊กเดิม: เช็คแค่ id == DEFAULT ทำให้อีกสามลายขึ้นว่า "not owned" ตลอด
--  ผู้เล่นกดเปลี่ยนลายแล้วไม่มีอะไรเกิดขึ้น นี่คือสาเหตุ)
function API.ownsSkin(name, id)
    local sk = _skins[id]
    if not sk then return false end
    -- ต้องอ่าน "ราคาปัจจุบัน" ไม่ใช่ราคาตอนลงทะเบียน
    -- แอดมินตั้งราคาลายที่เคยฟรีได้ และคนที่ซื้อไปแล้วต้องยังใช้ได้
    if API.skinPrice(id) <= 0 then return true end
    local a = D.account(name, false)
    return (a and a.owned and a.owned[id]) == true
end

function API.grantSkin(name, id)
    if not _skins[id] then return false, "unknown skin" end
    local a = D.account(name, true)
    if not a then return false, "no account" end
    a.owned = a.owned or {}
    a.owned[id] = true
    return true
end

-- เปลี่ยนลาย  เรียกได้จาก AC_Server (ที่เคาน์เตอร์ธนาคาร) และจากม็อดอื่น
function API.setPlayerSkin(name, id)
    if not _skins[id] then return false, "unknown skin" end
    if not API.ownsSkin(name, id) then return false, "not owned" end
    local a = D.account(name, true)
    if not a then return false, "no account" end
    a.skin = id
    return true
end

-- ลายในตัวม็อดเอง  4 ใบนี้เป็นงานของเราเอง ไม่ติดลิขสิทธิ์ใคร
for _, s in ipairs(AC.CARD_SKINS_BUILTIN) do
    API.registerCardSkin(s.id, { name = s.name, texture = s.texture, price = 0, source = AC.MOD_ID })
end

-- ------------------------------------------------------------------------------
-- สรุปสำหรับแผงแอดมิน
-- ------------------------------------------------------------------------------
-- เดินบัญชีล่าสุดของคนคนหนึ่ง
--
-- เปิดให้ม็อดอื่นอ่านได้ (Kuraya เอาไปโชว์ในจอ Account ข้างร้าน)
-- แต่ให้ได้แค่ "ล่าสุดไม่กี่รายการ" เท่านั้น  ประวัติเต็มยังต้องไปดูที่ธนาคาร
-- ตั้งใจให้เป็นแบบนี้  ไม่ใช่ข้อจำกัดทางเทคนิค
function API.recent(name, limit)
    limit = math.min(math.max(math.floor(tonumber(limit) or 8), 1), 20)
    local ok, rows = pcall(D.tailFor, U.key(name), limit)
    if not ok or type(rows) ~= "table" then return {} end
    return rows
end

function API.stats()
    local db = D.get()
    local nAcc, total = 0, 0
    for _, a in pairs(db.accounts) do nAcc = nAcc + 1; total = total + (a.bal or 0) end
    local cash = db.sys[AC.SYS.CASH] or 0
    return {
        accounts  = nAcc,
        inBank    = total,
        outOfBank = cash,
        m0        = total + cash,
        sys       = db.sys,
        agg       = db.agg,
        okSum     = select(1, D.checkInvariant("stats")),
    }
end

U.log("API ready  v" .. AC.VERSION .. "  schema v" .. AC.SCHEMA)

return API
