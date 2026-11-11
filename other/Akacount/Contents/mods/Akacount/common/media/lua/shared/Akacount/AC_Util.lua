-- ==============================================================================
-- Akacount — shared/Akacount/AC_Util.lua
-- ตัวช่วยที่ทั้งไคลเอนต์และเซิร์ฟเวอร์ใช้ร่วมกัน
-- ==============================================================================
require("Akacount/AC_Const")

AC.util = AC.util or {}
local U = AC.util

-- ------------------------------------------------------------------------------
-- คีย์ประจำตัวผู้เล่น
--   key เก็บเป็นตัวพิมพ์เล็กเสมอ  ชื่อจริงเก็บแยกไว้ในฟิลด์ disp
--   "Somchai" กับ "somchai" เป็นคนเดียวกัน ถ้าไม่ normalize จะได้บัญชีสองใบเงียบ ๆ
--   แล้วผู้เล่นจะรายงานว่า "เงินหาย" ซึ่งหาสาเหตุยากมาก
-- ------------------------------------------------------------------------------
function U.key(nameOrPlayer)
    local n = nameOrPlayer
    if type(n) == "table" or type(n) == "userdata" then
        local ok, v = pcall(function() return n:getUsername() end)
        n = ok and v or nil
    end
    if type(n) ~= "string" or n == "" then return nil end
    return n:lower()
end

function U.disp(player)
    if not player then return "?" end
    local ok, v = pcall(function() return player:getUsername() end)
    return (ok and v) or "?"
end

-- ------------------------------------------------------------------------------
-- เงิน  (integer สตางค์ เข้า / string ออก)
-- ------------------------------------------------------------------------------
function U.toSub(baht)
    return math.floor((tonumber(baht) or 0) * AC.SUBUNIT + 0.5)
end

function U.fmt(sub)
    sub = math.floor(tonumber(sub) or 0)
    local neg  = sub < 0
    local a    = math.abs(sub)
    local whole, frac = math.floor(a / AC.SUBUNIT), a % AC.SUBUNIT
    -- คั่นหลักพัน
    local s, k = tostring(whole), nil
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return (neg and "-" or "") .. s .. string.format(".%02d", frac)
end

function U.fmtShort(sub)
    local s = U.fmt(sub)
    return (s:gsub("%.00$", ""))
end

-- ------------------------------------------------------------------------------
-- sandbox  (อ่านสด ไม่ cache — แอดมินแก้ระหว่างเซิร์ฟรันได้)
-- ------------------------------------------------------------------------------
function U.opt(name)
    local sv = SandboxVars and SandboxVars.Akacount
    local v  = sv and sv[name]
    if v == nil then return AC.DEFAULTS[name] end
    return v
end

-- ------------------------------------------------------------------------------
-- เวลา
--   ทุกฟิลด์เวลาต้องประกาศหน่วยของตัวเอง เก็บคนละฟิลด์ ห้ามเก็บเลขเปล่า
--     *RealTs   = วินาทีเวลาจริง  (สินเชื่อ บิล ประมูล คูลดาวน์โอน)
--     *GameH    = ชั่วโมงในเกม     (ของหมดอายุ บริการส่งในเกม)
--   เอกสารสถาปัตยกรรมรุ่นแรกเขียนว่า "ใช้นาฬิกาเกมทุกที่" — ข้อนั้นผิดและถูกยกเลิกแล้ว
-- ------------------------------------------------------------------------------
function U.realTs()
    if getTimestamp then return getTimestamp() end
    return 0
end

function U.gameHour()
    local gt = getGameTime and getGameTime()
    if not gt then return 0 end
    local ok, v = pcall(function() return gt:getWorldAgeHours() end)
    return (ok and v) or 0
end

-- คีย์วันจริงสำหรับ aggregate  (เลขวันนับจาก epoch พอ ไม่ต้องเป็นวันที่สวย ๆ)
function U.dayKey(ts)
    return math.floor((ts or U.realTs()) / 86400)
end

-- ------------------------------------------------------------------------------
-- ค่าธรรมเนียม  เป็น % ที่มีขั้นต่ำและเพดาน
--   คงที่ล้วนจะโดนเลี่ยงด้วยการรวบโอนก้อนใหญ่ครั้งเดียว
--   % ล้วนจะทำให้โอน 20 บาทเสีย 40 สตางค์ ซึ่งไม่เป็น sink อะไรเลย
--   เพดานกันไม่ให้การโอนก้อนใหญ่ระหว่างกลุ่มกลายเป็นภาษีที่โหดเกินจริง
-- ------------------------------------------------------------------------------
function U.feeFor(amountSub, pctBp)
    pctBp = tonumber(pctBp) or 0
    if pctBp <= 0 then return 0 end
    local raw = math.floor(amountSub * pctBp / 10000)
    local lo  = tonumber(U.opt("XferFeeMin")) or 0
    local hi  = tonumber(U.opt("XferFeeMax")) or math.huge
    if raw < lo then raw = lo end
    if raw > hi then raw = hi end
    -- ห้าม clamp ด้วย amountSub
    -- เวอร์ชันแรกเขียน `if raw > amountSub then raw = amountSub end` ไว้
    -- ผลคือโอน 1.00 แล้วเสียค่าธรรมเนียม 1.00 (100%) แทนที่จะเป็นขั้นต่ำ 5.00
    -- ค่าธรรมเนียมกลายเป็นตัวเลขที่เปลี่ยนไปเงียบ ๆ ตามยอด ซึ่งอธิบายผู้เล่นไม่ได้
    -- ทางที่ตรงไปตรงมากว่าคือปฏิเสธยอดที่เล็กกว่าค่าธรรมเนียมขั้นต่ำไปเลย -> U.minSend()
    return raw
end

-- ------------------------------------------------------------------------------
-- ยอดที่เล็กที่สุดที่ยัง "คุ้มจะส่ง"  ตามชุดค่าธรรมเนียมที่ให้มา
--
-- กติกาข้อเดียว: ค่าธรรมเนียมต้องน้อยกว่ายอดเสมอ
--   ยอด = ค่าธรรมเนียม -> ผู้รับได้ศูนย์  คนส่งจ่ายไปสองเท่าเพื่อให้เกิดอะไรขึ้นไม่รู้
--   ยอด < ค่าธรรมเนียม -> คนส่งจ่ายมากกว่าที่ส่ง  ซึ่งอธิบายให้ใครฟังก็ไม่มีวันเข้าใจ
-- XferFeeMin เป็น "พื้น" ของค่าธรรมเนียม ไม่ใช่เพดาน  ยอด 500 สตางค์ที่เรต 2%
-- จึงเสีย 500 เท่ากับยอดพอดี  นั่นคือเหตุผลที่ต้อง +1 ไม่ใช่ >= เฉย ๆ
--
-- ทั้งจอและเซิร์ฟเวอร์เรียกฟังก์ชันตัวนี้ตัวเดียวกัน  สองฝั่งจึงเถียงกันไม่ได้
-- โดยโครงสร้าง ไม่ใช่เพราะเราจำได้ว่าต้องแก้ทั้งสองที่
-- ------------------------------------------------------------------------------
function U.minSendFor(pctBp)
    pctBp = tonumber(pctBp) or 0
    if pctBp <= 0 then return 1 end          -- ไม่มีค่าธรรมเนียม  1 สตางค์ก็ถึงมือผู้รับจริง
    local a = math.floor(tonumber(U.opt("XferFeeMin")) or 0) + 1
    -- เผื่อเซิร์ฟที่ตั้งเรตไว้สูงมากจนค่าธรรมเนียมไล่ทันยอด  ไต่ขึ้นจนพ้นจริง
    -- มีเพดาน (XferFeeMax) รออยู่ข้างหน้าเสมอ ลูปนี้จบแน่นอน  guard ไว้กันคนตั้งค่าประหลาด
    for _ = 1, 64 do
        local f = U.feeFor(a, pctBp)
        if f < a then break end
        a = f + 1
    end
    return a
end

-- ยอดโอนขั้นต่ำของ "การโอนผ่านบัตร"  ไม่ส่ง pctBp มาก็ใช้เรตบัตรเป็นค่าตั้งต้น
-- ที่เคาน์เตอร์ค่าธรรมเนียมเป็น 0  ฝั่งเรียกต้องส่ง 0 เข้ามาเอง จะได้ไม่ต้องเดาที่นี่
function U.minSend(pctBp)
    if pctBp == nil then pctBp = U.opt("XferFeeCardPct") end
    return U.minSendFor(pctBp)
end

-- ------------------------------------------------------------------------------
-- ตรวจว่าเมธอด Java มีจริงก่อนเรียก
--   pcall อย่างเดียวไม่พอ  Kahlua ยัง dump stack trace เต็ม ๆ ถึงจะจับ error ได้
--   (ISRemoveItemTool.removeItem เคย dump 1,332 ครั้งต่อ session แบบนี้)
-- ------------------------------------------------------------------------------
function U.hasMethod(obj, name)
    if not obj then return false end
    local ok, v = pcall(function() return obj[name] end)
    return ok and type(v) == "function"
end

-- ------------------------------------------------------------------------------
-- ฝั่งไหนเป็นเจ้าของข้อมูล
--   PZ โหลดไฟล์ใน media/lua/server/ บนไคลเอนต์ MP ด้วย  ไม่ได้กันให้
--   ถ้าไม่เช็คตรงนี้ ไคลเอนต์จะพยายามรัน logic ของเซิร์ฟแล้วพังทุกนาที
--     dedicated server : isServer() = true
--     MP client        : isClient() = true
--     single player     : ทั้งคู่ false
-- ------------------------------------------------------------------------------
function U.isHost()
    local sv = (type(isServer) == "function") and isServer() or false
    if sv then return true end
    local cl = (type(isClient) == "function") and isClient() or false
    if cl then return false end
    return true
end

-- ------------------------------------------------------------------------------
-- ผูก event แบบไม่ทำให้เซิร์ฟไม่ขึ้น
--   ห้าม Events.X.Add(...) ตรง ๆ  ถ้าบิลด์นั้นไม่มี event X จะ error ตอนโหลดไฟล์
--   และ callback ที่เอนจินเรียกต้องห่อ pcall เสมอ
--   หลักที่ยึด: พังยังไงก็ต้องกลายเป็น "ม็อดไม่ทำงาน" ไม่ใช่ "เซิร์ฟไม่ขึ้น"
-- ------------------------------------------------------------------------------
function U.on(eventName, fn, label)
    local ev = Events and Events[eventName]
    if not ev or type(ev.Add) ~= "function" then
        U.log("event not on this build, skipped:", eventName)
        return false
    end
    ev.Add(function(...)
        local ok, err = pcall(fn, ...)
        if not ok then U.log("error in", label or eventName, "->", err) end
    end)
    return true
end

function U.log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    print("[Akacount] " .. table.concat(parts, " "))
end

return U
