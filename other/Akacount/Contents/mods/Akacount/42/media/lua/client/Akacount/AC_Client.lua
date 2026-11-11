-- ==============================================================================
-- Akacount — client/Akacount/AC_Client.lua
-- net layer + เมนูคลิกขวา
-- ==============================================================================
--
-- เมนูคลิกขวามีสามจุด และแบ่งงานตามกฎข้อเดียวของทั้งระบบ
--
--   ตัวเลขดูได้ทุกที่  ·  ของต้องไปเอาถึงที่  ·  ความสะดวกมีราคา
--
--   เงินสด -> ฝากเข้าธนาคาร      ทำได้ทุกที่ เสียค่าธรรมเนียม (ที่ตู้ฟรี)
--   บัตร   -> โอนเงิน            ทำได้ทุกที่ เสียค่าธรรมเนียม (ที่ตู้ฟรี)
--   ตู้     -> ถอนเงินสด          ที่ตู้อย่างเดียว เพราะเซิร์ฟต้องสร้างไอเทมให้ที่จุดนั้น
--   มือถือ -> ดูยอด / ประวัติ     อ่านอย่างเดียว ต้องมีถ่าน
--
-- กฎนี้ไม่ได้ตั้งขึ้นมาเพื่อบาลานซ์ มันตกลงมาจากสถาปัตยกรรมโดยตรง
-- ==============================================================================
require("Akacount/AC_Const")
require("Akacount/AC_Util")
require("Akacount/AC_Theme")

ACClient = ACClient or {}
local C = ACClient
local U = AC.util

C.data = C.data or { bal = 0, hold = 0, avail = 0, locked = false,
                     skin = AC.CARD_SKIN_DEFAULT, skins = {}, tail = {},
                     cash = 0, atCntr = false, admin = false, counters = {} }

-- รายชื่อคนที่โอนหาได้  แถวละ { key = "somchai", name = "Somchai" }
--
-- ชื่อเดิมคือ C.online และเก็บ "คนที่ออนไลน์" ซึ่งเป็นคนละเรื่องกับสิ่งที่ต้องใช้
-- ตอนนี้เซิร์ฟส่ง "คนที่มีบัตรแล้ว" มาให้ (ดู S.cardHolders)  ชื่อตัวแปรจึงต้องตามความจริง
-- ห้ามเอา name ไปส่งกลับเป็นปลายทาง  ต้องส่ง key เสมอ เซิร์ฟจะได้ไม่ต้องเดาจากตัวพิมพ์
C.holders = C.holders or {}

local function me() return getSpecificPlayer(0) end

-- ชื่อตัวเองแบบตัวพิมพ์เล็ก  ใช้เทียบว่าแถวในเดินบัญชีเป็นเงินเข้าหรือเงินออก
function C.myKey()
    local p = me()
    if not p then return nil end
    local ok, n = pcall(function() return p:getUsername() end)
    return (ok and n) and n:lower() or nil
end

function C.req(cmd, args) sendClientCommand(AC.MODULE, cmd, args or {}) end
function C.sync()          C.req(AC.CMD.REQ_SYNC) end

-- ------------------------------------------------------------------------------
-- ข้อความเหนือหัว  (HaloTextHelper.addTextWithArrow 6 อาร์กิวเมนต์ มีจริงใน 42.20 JavaDocs)
-- ------------------------------------------------------------------------------
function C.halo(msg, tone)
    local p = me()
    if not (p and msg and HaloTextHelper) then return end
    local r, g, b = 210, 210, 235
    if tone == "good" then r, g, b = 61, 220, 151 end
    if tone == "bad"  then r, g, b = 255, 120, 130 end
    pcall(function() HaloTextHelper.addTextWithArrow(p, tostring(msg), true, r, g, b) end)
end

-- ------------------------------------------------------------------------------
-- กล่องรับโอน  คัดจาก tail ที่เซิร์ฟส่งมาอยู่แล้ว  ไม่มีแพ็กเก็ตเพิ่ม
--   แถว "ใหม่" = แถวรับโอนที่ t > seenT (เวลาที่เซิร์ฟจดว่าเราอ่านถึง)
-- คืน rows, unread, sumUnread
-- ------------------------------------------------------------------------------
function C.inbox()
    local mine = C.myKey()
    local d    = C.data
    local seen = tonumber(d.seenT) or 0
    local rows, unread, sum = {}, 0, 0
    if not mine then return rows, 0, 0 end
    for _, e in ipairs(d.tail or {}) do
        if e.k == AC.KIND.TRANSFER and e.to == mine then
            local new = (tonumber(e.t) or 0) > seen
            rows[#rows + 1] = { e = e, new = new }
            if new then
                unread = unread + 1
                sum = sum + (tonumber(e.a) or 0)
            end
            if #rows >= AC.INBOX_MAX then break end
        end
    end
    return rows, unread, sum
end

-- "กี่นาทีก่อน"  ใช้นาฬิกาเซิร์ฟ (d.now) + เวลาที่ผ่านไปตั้งแต่ sync  ไม่ใช่นาฬิกาเครื่องเรา
function C.ago(t)
    local d = C.data
    t = tonumber(t)
    if not t or not d.now then return "" end
    local now = d.now + math.max(0, U.realTs() - (C.syncAt or U.realTs()))
    local s = math.max(0, now - t)
    if s < 60 then return "now" end
    if s < 3600 then return math.floor(s / 60) .. "m" end
    if s < 86400 then return math.floor(s / 3600) .. "h" end
    return math.floor(s / 86400) .. "d"
end

-- ------------------------------------------------------------------------------
-- รับข้อมูลจากเซิร์ฟเวอร์
-- ------------------------------------------------------------------------------
local function onServerCommand(module, command, args)
    if module ~= AC.MODULE then return end

    if command == AC.CMD.SYNC and args then
        for k, v in pairs(args) do C.data[k] = v end
        C.syncAt = U.realTs()
        -- sync แรกของรอบเล่น: มีเงินเข้าระหว่างที่ออฟไลน์ไหม  บอกครั้งเดียว
        if not C.greeted and C.data.seenT ~= nil then
            C.greeted = true
            local _, n, sum = C.inbox()
            if n > 0 then
                C.halo("+" .. U.fmt(sum) .. "  (" .. n .. (n > 1 and " transfers" or " transfer") ..
                       " while away - check your card)", "good")
            end
        end
        if ACWindows then ACWindows.refreshAll() end

    elseif command == AC.CMD.INCOMING and args then
        -- มีคนโอนเข้ามาตอนนี้  ขึ้นเหนือหัว  ยอดกับกล่องรับโอนตามมากับ sync ที่เซิร์ฟส่งต่อท้าย
        C.halo("+" .. U.fmt(args.sub or 0) .. "  from " .. tostring(args.who or "?"), "good")

    elseif command == AC.CMD.ONLINE_LIST and args then
        -- ชื่อคำสั่งเป็นของเดิม เนื้อในเป็นรายชื่อคนมีบัตร
        -- กรองแถวที่ไม่มี key ทิ้งตั้งแต่ตรงนี้  แถวพิการหนึ่งแถวไม่ควรทำให้ทั้งจอวาดไม่ขึ้น
        local out = {}
        for _, row in ipairs(args.list or {}) do
            if type(row) == "table" and type(row.key) == "string" and row.key ~= "" then
                out[#out + 1] = { key = row.key, name = tostring(row.name or row.key) }
            end
        end
        C.holders = out
        if ACWindows then ACWindows.refreshAll() end

    elseif command == AC.CMD.ALERT and args then
        C.halo(args.msg, args.tone)
    end
end
Events.OnServerCommand.Add(onServerCommand)

-- ------------------------------------------------------------------------------
-- คลิกขวาที่ไอเทมในกระเป๋า  (บัตร / มือถือ)
-- ------------------------------------------------------------------------------
local function firstOf(items)
    if not items then return nil end
    if items.items then items = items.items end
    for i = 1, #items do
        local it = items[i]
        if type(it) == "table" and it.items then it = it.items[1] end
        if it then return it end
    end
    return nil
end

-- นับเงินสดทั้งตัว (ไว้โชว์ในเมนู) ฝั่งไคลเอนต์นับคร่าว ๆ พอ
-- เซิร์ฟเวอร์นับใหม่อยู่แล้วตอนฝากจริง ไคลเอนต์โกหกได้แต่ไม่มีผล
-- คืน (มูลค่ารวมเป็นใบ, แบงก์ใบ, ปึก)   ปึกละ AC.BUNDLE_SIZE ใบ
local function cashOnMe(player)
    local loose, bundles = 0, 0
    local function add(c)
        if not c then return end
        loose   = loose + c:getItemCount(AC.ITEM_CASH)
        bundles = bundles + c:getItemCount(AC.ITEM_BUNDLE)
    end
    add(player:getInventory())
    local worn = player:getWornItems()
    if worn then
        for i = 0, worn:size() - 1 do
            local w  = worn:get(i)
            local it = w and w:getItem()
            if it and it:IsInventoryContainer() then add(it:getItemContainer()) end
        end
    end
    return loose + bundles * AC.BUNDLE_SIZE, loose, bundles
end

-- ค่าธรรมเนียมฝากคิดจากเรตเดียวกับเซิร์ฟ  n = จำนวนแบงก์ (ก้อนละ 1 บาท)
local function depPct()
    return ACClient.data.atCntr and 0 or U.opt("DepositFeePct")
end

local function feeText(n)
    if ACClient.data.atCntr then return "free at counter" end
    local fee = U.feeFor(n * AC.SUBUNIT, depPct())
    return "fee " .. U.fmt(fee)
end

-- ฝากได้จริงไหม  ยอดต้องมากกว่าค่าธรรมเนียม ไม่งั้นฝากแล้วบัญชีลดลง
-- ใช้ตัวคำนวณตัวเดียวกับเซิร์ฟ (U.minSendFor)  เมนูจึงไม่มีทางเสนอสิ่งที่เซิร์ฟจะปฏิเสธ
local function depOK(n)
    return (n * AC.SUBUNIT) >= U.minSendFor(depPct())
end

local function onInventoryMenu(playerNum, context, items)
    if playerNum ~= 0 then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    local item = firstOf(items)
    if not item then return end

    local ft = item.getFullType and item:getFullType() or nil

    -- ------------------------------------------------------------------
    -- เงินสด -> ฝากเข้าธนาคารได้จากตรงนี้เลย ทุกที่ เสียค่าธรรมเนียม
    -- (ถอนไม่มีตรงนี้ เพราะเซิร์ฟต้องสร้างไอเทมให้ที่จุดจริง -> ต้องไปที่ตู้)
    -- ------------------------------------------------------------------
    -- แบงก์ใบหรือปึก ก็เปิดเมนูเดียวกัน  ฝาก "ทั้งหมด" = ทั้งใบทั้งปึก
    if ft == AC.ITEM_CASH or ft == AC.ITEM_BUNDLE then
        local have, nL, nB = cashOnMe(player)
        if have <= 0 then return end

        local parent = context:addOption("HF Bank", player, nil)
        local menu   = ISContextMenu:getNew(context)
        context:addSubMenu(parent, menu)

        local mix = (nB > 0) and ("  = " .. nB .. "x100 + " .. nL) or ""
        if depOK(have) then
            menu:addOption("Deposit all  " .. U.fmtShort(have * AC.SUBUNIT) .. mix .. "   " .. feeText(have), player, function()
                C.req(AC.CMD.DEPOSIT, { n = have })
            end)
        else
            -- บอกไปตรง ๆ ว่าทำไมกดไม่ได้  ปุ่มเทาเฉย ๆ คือปุ่มที่ผู้เล่นเดาเหตุผลเอง
            local why = menu:addOption("Too small to deposit here  (" .. feeText(have) ..
                                       ", need " .. U.fmt(U.minSendFor(depPct())) .. ")", player, nil)
            why.notAvailable = true
        end

        for _, n in ipairs({ 100, 500, 1000 }) do
            if have >= n and depOK(n) then
                menu:addOption("Deposit " .. n .. "   " .. feeText(n), player, function()
                    C.req(AC.CMD.DEPOSIT, { n = n })
                end)
            end
        end

        local info = menu:addOption("Balance  " .. U.fmt(C.data.avail or 0), player, nil)
        info.notAvailable = true
        if not C.data.atCntr then
            local hint = menu:addOption("Free if you deposit at a bank counter", player, nil)
            hint.notAvailable = true
        end
        return
    end

    -- ทุกลายเป็นไอเทมคนละชนิด  เทียบกับ AC.ITEM_CARD ตรง ๆ ไม่ได้แล้ว
    -- ถ้าเทียบตรง ๆ คนที่ใช้ลายอื่นจะคลิกขวาที่บัตรตัวเองแล้วไม่มีเมนูโผล่
    if AC.isCardItem(ft) then
        -- บัตรใช้ได้เฉพาะเจ้าของ
        --
        -- เจ้าของถูกจดไว้ที่ตัวไอเทม ไม่ใช่ที่บัญชี
        -- เพราะบัตรเปลี่ยนมือได้จริง (ตกพื้น โดนขโมย ศพเก็บได้)
        -- บัตรเก่าที่ออกก่อนระบบนี้ไม่มี acOwner  ให้ผ่านไปก่อน ไม่งั้นคนเดิมใช้ไม่ได้ทันที
        local md    = item and item:getModData() or {}
        local mine  = (md.acOwner == nil) or (md.acOwner == C.myKey())

        -- ป้ายบอกจำนวนเงินเข้าที่ยังไม่อ่านติดไว้ที่ชื่อเมนูเลย  เห็นตั้งแต่คลิกขวา ไม่ต้องเปิดเมนูย่อย
        local rows, unread = {}, 0
        if mine then rows, unread = C.inbox() end
        local parent = context:addOption("HF Bank Card" .. ((unread > 0) and ("   (" .. unread .. " new)") or ""),
                                         player, nil)
        if U.hasMethod(item, "getTex") then
            local okT, tex = pcall(function() return item:getTex() end)
            if okT and tex then parent.iconTexture = tex end
        end
        local menu   = ISContextMenu:getNew(context)
        context:addSubMenu(parent, menu)

        if not mine then
            local no = menu:addOption("This card belongs to " .. tostring(md.acOwner), player, nil)
            no.notAvailable = true
            local hint = menu:addOption("Get your own at a bank counter", player, nil)
            hint.notAvailable = true
            return
        end

        -- ขอรายชื่อคนมีบัตรก่อนเปิดจอ  จอไม่มีช่องพิมพ์ชื่อแล้ว ถ้าไม่มีรายชื่อก็เลือกใครไม่ได้เลย
        menu:addOption("Send money...", player, function()
            C.req(AC.CMD.WHO_ONLINE)
            if ACWindows then ACWindows.openCard("send") end
        end)
        menu:addOption((unread > 0) and ("Inbox  (" .. unread .. " new)...") or "Inbox...", player, function()
            if ACWindows then ACWindows.openCard("inbox") end
        end)
        local b = menu:addOption("Balance  " .. U.fmt(C.data.avail or 0), player, nil)
        b.notAvailable = true

        -- เงินเข้าล่าสุด 5 แถว  แตะแถวไหนก็เปิดกล่องรับโอน
        for i = 1, math.min(5, #rows) do
            local e = rows[i].e
            local when = C.ago(e.t)
            local lbl = (rows[i].new and "NEW  " or "") .. "+" .. U.fmt(e.a or 0) .. "  from " ..
                        tostring(e.who or e.f or "?") .. ((when ~= "") and ("   " .. when) or "")
            menu:addOption(lbl, player, function()
                if ACWindows then ACWindows.openCard("inbox") end
            end)
        end
        if unread > 0 then
            menu:addOption("Mark all as read", player, function() C.req(AC.CMD.MARK_SEEN, {}) end)
        end
        if (C.data.hold or 0) > 0 then
            local h = menu:addOption("Held  " .. U.fmt(C.data.hold), player, nil)
            h.notAvailable = true
        end
        if C.data.locked then
            local l = menu:addOption("Account overdrawn - spending locked", player, nil)
            l.notAvailable = true
        end

    end
end
Events.OnFillInventoryObjectContextMenu.Add(onInventoryMenu)

-- ------------------------------------------------------------------------------
-- คลิกขวาในโลก
--
--   คำสั่งที่ทำกับ tile ที่คลิกอยู่  -> แถวบนสุด กดได้เลย
--   เครื่องมือระดับเซิร์ฟ            -> อยู่ใต้เมนูแม่ "AKA Mod"
--   ทุกแถวของแอดมินลงท้าย "(admin)"  เมนูคลิกขวาใส่สีรายแถวไม่ได้อย่างเชื่อถือได้
--                                     แต่ suffix รอดทุกสกิน
-- ------------------------------------------------------------------------------
local function tileId(x, y, z) return x .. ":" .. y .. ":" .. z end

-- ไคลเอนต์คำนวณเองว่ายืนอยู่ใกล้ตู้ไหม เพื่อให้เมนูตอบสนองทันที
-- เซิร์ฟเวอร์ยังเช็คซ้ำอยู่ดีตอนกดฝาก/ถอน ไคลเอนต์โกหกได้แต่ไม่มีผล
--
-- ระยะต้องเป็นเลขตัวเดียวกับที่เซิร์ฟใช้  เลข 3 ที่เคยฝังไว้ตรงนี้จะเพี้ยนทันที
-- ที่เจ้าของเซิร์ฟไปเลื่อน Akacount.CounterRange  ผลคือเมนูขึ้นแต่กดแล้วเซิร์ฟปฏิเสธ
-- เอาค่าที่เซิร์ฟส่งมากับ sync ก่อน  ยังไม่ sync ค่อยอ่าน sandbox ของตัวเอง
function C.counterRange()
    local n = tonumber(C.data.cntrRange) or tonumber(U.opt("CounterRange")) or 3
    return math.floor(n)
end

function C.nearCounter(player)
    local sq = player and player:getSquare()
    if not sq then return false end
    local r = C.counterRange()
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
    for _, c in pairs(C.data.counters or {}) do
        if c.z == pz and math.abs(c.x - px) <= r and math.abs(c.y - py) <= r then
            return true
        end
    end
    return false
end

local function squareOf(worldobjects)
    for i = 1, #(worldobjects or {}) do
        local o = worldobjects[i]
        local sq = o and o.getSquare and o:getSquare()
        if sq then return sq, o end
    end
    return nil, nil
end

local function onWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    if playerNum ~= 0 then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local sq, obj = squareOf(worldobjects)
    if not sq then return end

    -- แถวบนสุด: สิ่งที่ทำกับตรงนี้ได้เลย
    local rows = {}
    if C.nearCounter(player) then
        rows[#rows + 1] = { "Bank  -  Deposit / Withdraw", function()
            C.sync()
            if ACWindows then ACWindows.openCounter() end
        end }
    end
    for i = #rows, 1, -1 do
        context:addOptionOnTop(rows[i][1], player, rows[i][2])
    end

    if not C.data.admin then return end

    -- ใต้เมนูแม่ AKA Mod  (ใช้ชื่อเดียวกับม็อดตัวอื่นในตระกูล)
    -- ต้องเช็คด้วยจุด ไม่ใช่ทวิภาค  `context:getOptionFromName and ...` ไม่ใช่ Lua ที่ถูก
    -- เพราะ a:b คือการเรียกเมธอดซึ่งต้องมีวงเล็บตามเสมอ
    local parent
    if type(context.getOptionFromName) == "function" then
        parent = context:getOptionFromName("AKA Mod")
    end
    local sub
    if parent and parent.subOption then
        sub = context:getSubMenu(parent.subOption)
    else
        parent = context:addOption("AKA Mod", player, nil)
        sub    = ISContextMenu:getNew(context)
        context:addSubMenu(parent, sub)
    end

    local bankOpt  = sub:addOption("Bank link   (admin)", player, nil)
    local bankMenu = ISContextMenu:getNew(sub)
    sub:addSubMenu(bankOpt, bankMenu)

    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local id      = tileId(x, y, z)
    local linked  = (C.data.counters or {})[id] ~= nil

    local sprite = ""
    if obj and obj.getSprite then
        local sp = obj:getSprite()
        if sp and sp.getName then sprite = sp:getName() or "" end
    end

    if linked then
        bankMenu:addOption("Unlink this tile", player, function()
            C.req(AC.CMD.ADMIN_REG_TILE, { x = x, y = y, z = z, on = false })
        end)
        bankMenu:addOption("Already a bank  (" .. id .. ")", player, nil).notAvailable = true
    else
        bankMenu:addOption("Link this tile as a bank", player, function()
            C.req(AC.CMD.ADMIN_REG_TILE, { x = x, y = y, z = z, on = true, sprite = sprite })
        end)
    end

    local n = 0
    for _ in pairs(C.data.counters or {}) do n = n + 1 end
    bankMenu:addOption("Linked tiles on this server: " .. n, player, nil).notAvailable = true
    bankMenu:addOption("All bank tiles share the same settings", player, nil).notAvailable = true
end
Events.OnFillWorldObjectContextMenu.Add(onWorldMenu)

Events.OnCreatePlayer.Add(function(n) if n == 0 then C.sync() end end)

-- ขอ sync เป็นระยะ เพื่อให้เมนูคลิกขวารู้ยอดและรู้ว่ายืนอยู่ใกล้ตู้ไหม
-- ทุก 1 นาทีพอ ห้ามผูกกับ OnTick
if Events.EveryOneMinute then
    Events.EveryOneMinute.Add(function() C.sync() end)
end

return C
