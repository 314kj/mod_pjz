-- ==============================================================================
-- Kuraya — server/Kuraya/KR_Stats.lua
-- สถิติเศรษฐกิจ · กระดานราคาโลก · สกิล 8-10
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- ห้าอย่างที่เจ้าของเซิร์ฟสั่งมา อยู่ไฟล์เดียวกันเพราะทั้งห้าอ่านข้อมูลชุดเดียวกัน
-- (ทะเบียนผู้เล่น) และทั้งห้าเป็นของแอดมินล้วน  แยกไฟล์แล้วจะต้องส่ง S ไปมาสี่รอบ
--
--   1. ค่าเฉลี่ยเงินสดของคนที่ออนใน 7 วันล่าสุด   (mean + median + n)
--   2. Top 10 คนเงินมากสุด เลือกสกุลได้
--   3. กราฟรายรับรายจ่ายรวมทั้งเซิร์ฟ
--   4. กระดานราคาสินค้าโลก  (แอดมินพิมพ์เอง · ผู้เล่นดูอย่างเดียว)
--   5. สกิล 8-10 เฉพาะกลุ่มฝีมือ
-- ==============================================================================
require("Kuraya/KR_Const")
require("Kuraya/KR_Server")

print("[Kuraya] KR_Stats  v" .. KR.VERSION)

local S = KR.server
if type(S) ~= "table" then
    print("[Kuraya] !! KR_Stats loaded without KR.server - stats are off this session")
    return
end

local db    = S.db
local key   = S.key
local P     = S.P
local bank  = S.bank
local alert = S.alert

local function nowTs()
    return getTimestamp and getTimestamp() or os.time()
end

-- Java list หรือ table ธรรมดา -> array ของ Lua
--
-- เขียนซ้ำที่นี่แทนที่จะ import จาก KR_Pets โดยตั้งใจ
-- ไฟล์นั้นเป็นเรื่องสัตว์  การพึ่งมันเพื่อฟังก์ชันสามบรรทัดคือการผูกสองเรื่อง
-- ที่ไม่เกี่ยวกันเข้าด้วยกัน แล้ววันที่ใครลบ KR_Pets ออก สถิติจะตายตาม
local function listOf(v)
    if type(v) == "table" and v.size == nil then
        local out = {}
        for i = 1, #v do out[i] = v[i] end
        return out
    end
    if type(v) ~= "table" and type(v) ~= "userdata" then return nil end
    local okN, n = pcall(function() return v:size() end)
    if not okN or type(n) ~= "number" then return nil end
    local out = {}
    for i = 0, n - 1 do
        local okG, item = pcall(function() return v:get(i) end)
        if okG then out[#out + 1] = item end
    end
    return out
end

-- ==============================================================================
-- ยอดรวมรายวัน  (ฟีเจอร์ 3)
--
-- ทำไมไม่คิดจาก p.log ตรง ๆ
--   p.log เป็น ring buffer ที่ตัดทิ้งตาม KR.LOG_MAX  คนที่ซื้อของเยอะแถวเก่าหายไปแล้ว
--   กราฟที่คิดจาก log จึงเป็นกราฟที่ **"ยิ่งคนใช้เงินเยอะ ยิ่งมองย้อนได้สั้น"**
--   ซึ่งอ่านผิดได้ง่ายมาก และผิดในทางที่ทำให้เซิร์ฟดูซบเซากว่าความจริง
--
-- ยอดรวมรายวันไม่ได้ซ้ำซ้อนกับ log  log ตอบ "ใครซื้ออะไร"
-- ยอดรวมตอบ "เซิร์ฟไหลเงินเท่าไร" คนละคำถาม และตัวที่สองต้องอยู่ทนกว่า
-- ==============================================================================
local function statsTable(d)
    d.stats = d.stats or {}
    d.stats.day = d.stats.day or {}
    return d.stats
end

-- ตัดวันที่เก่ากว่าเพดานทิ้ง  เรียกตอนเขียน ไม่ใช่ตอนอ่าน
-- ตัดตอนอ่าน = ตารางโตไปเรื่อย ๆ บนเซิร์ฟที่ไม่มีแอดมินเปิดดูเลย
local function trimDays(st, today)
    local cut = today - KR.STATS_DAYS
    local drop = {}
    for dayNo in pairs(st.day) do
        if (tonumber(dayNo) or 0) < cut then drop[#drop + 1] = dayNo end
    end
    for i = 1, #drop do st.day[drop[i]] = nil end
    return #drop
end

-- บวกเงินหนึ่งก้อนเข้ายอดรวมของวันนี้
--   cur  สกุล
--   amt  จำนวนในหน่วยของสกุลนั้นเอง (cash = สตางค์)
--   inc  true = เงินเข้ากระเป๋าผู้เล่น  false/nil = เงินออก
function S.statsBump(cur, amt, inc, ts)
    local n = math.floor(tonumber(amt) or 0)
    if n <= 0 then return false end
    if not KR.CUR_META[cur] then return false end

    local d  = db()
    local st = statsTable(d)
    local day = KR.dayOf(ts or nowTs())

    local row = st.day[day]
    if row == nil then
        row = {}
        st.day[day] = row
        trimDays(st, day)
    end
    local c = row[cur]
    if c == nil then c = { inc = 0, out = 0 }; row[cur] = c end

    if inc then c.inc = (tonumber(c.inc) or 0) + n
    else        c.out = (tonumber(c.out) or 0) + n end
    return true
end

-- ชุดข้อมูลสำหรับกราฟ  คืนเรียงจากเก่าไปใหม่ **รวมวันที่ไม่มีข้อมูล**
--
-- วันที่ยังไม่เคยมีข้อมูล (ก่อนอัปเดตนี้) ต้องส่ง have = false ไปให้จอ
-- ห้ามส่ง 0  ศูนย์แปลว่า "ไม่มีเงินไหลวันนั้น" ซึ่งไม่จริงและอ่านผิดทันที
function S.statsSeries(cur, days)
    local d   = db()
    local st  = statsTable(d)
    local today = KR.dayOf(nowTs())
    days = math.max(1, math.min(KR.STATS_DAYS, math.floor(tonumber(days) or 7)))

    local out = {}
    for i = days - 1, 0, -1 do
        local dayNo = today - i
        local row = st.day[dayNo]
        local c   = row and row[cur]
        out[#out + 1] = {
            day  = dayNo,
            have = (c ~= nil) or nil,
            inc  = c and math.floor(tonumber(c.inc) or 0) or 0,
            out  = c and math.floor(tonumber(c.out) or 0) or 0,
        }
    end
    return out
end

-- ==============================================================================
-- ยอดเงินของผู้เล่นรายคน
-- ==============================================================================

-- CASH อยู่ใน Akacount ไม่ใช่ของเรา  อ่านทีละคีย์เพราะไม่มี API แบบ bulk
-- ราคาของการอ่านคือเหตุผลที่ทั้งไฟล์นี้ทำงานแบบ "คิดตอนถูกขอ แล้วแคช"
local function cashOf(k)
    local B = bank()
    if not B or type(B.available) ~= "function" then return nil end
    local ok, v = pcall(B.available, k)
    if not ok or type(v) ~= "number" then return nil end
    return v
end

local function hfOf(k)
    local row = db().players[k]
    return math.floor(tonumber(row and row.hf) or 0)
end

-- CP อ่านได้เฉพาะคนที่ออนไลน์  HF_Town_Rank_API รับ IsoPlayer ไม่ใช่ชื่อ
-- คนออฟไลน์จึงคืน nil ไม่ใช่ 0  **0 แปลว่า "ไม่มีแต้ม" ซึ่งเป็นคำตอบคนละอันกับ "ไม่รู้"**
local function cpOf(k)
    local pl = S.onlineByKey and S.onlineByKey(k) or nil
    if not pl then return nil end
    if type(KR.tr) ~= "table" or type(KR.tr.get) ~= "function" then return nil end
    local ok, v = pcall(KR.tr.get, pl)
    if not ok or type(v) ~= "number" then return nil end
    return math.floor(v)
end

local function balOf(k, cur)
    if cur == KR.CUR.HF then return hfOf(k) end
    if cur == KR.CUR.CP then return cpOf(k) end
    return cashOf(k)
end

-- ==============================================================================
-- ค่าเฉลี่ย + มัธยฐาน ของคนที่ยัง active  (ฟีเจอร์ 1)
--
-- **ต้องสามตัวเลข ไม่ใช่ตัวเดียว**
-- คนรวยคนเดียวดึงค่าเฉลี่ยขึ้นได้ทั้งเซิร์ฟ  ค่าเฉลี่ยที่อยู่ลำพังจึงตอบคำถาม
-- "คนทั่วไปมีเงินเท่าไร" ผิด และมันจะถูกเอาไปใช้ตั้งราคาของในร้าน
-- มัธยฐานตอบคำถามนั้นถูก  และ n บอกว่าเชื่อได้แค่ไหน (n=3 กับ n=60 คนละเรื่อง)
-- ==============================================================================
local CACHE = nil      -- { at = ts, data = {...} }

local function activeKeys(d, nowT)
    local cut = nowT - KR.ACTIVE_DAYS * 86400
    local out = {}
    for k, row in pairs(d.players or {}) do
        local seen = tonumber(row and row.lastSeen) or 0
        if seen >= cut and seen > 0 then out[#out + 1] = k end
    end
    table.sort(out)         -- ลำดับคงที่  ไม่งั้นมัธยฐานของยอดเท่ากันสลับไปมา
    return out
end

local function meanMedian(vals)
    local n = #vals
    if n == 0 then return nil, nil, 0 end
    table.sort(vals)
    local sum = 0
    for i = 1, n do sum = sum + vals[i] end
    local mean = sum / n
    local med
    if n % 2 == 1 then
        med = vals[(n + 1) / 2]
    else
        med = (vals[n / 2] + vals[n / 2 + 1]) / 2
    end
    return mean, med, n
end

function S.statsCompute()
    local d = db()
    local nowT = nowTs()
    local keys = activeKeys(d, nowT)

    -- ---- ค่าเฉลี่ยเงินสด ----------------------------------------------------
    local cashVals, noBank = {}, 0
    for i = 1, #keys do
        local v = cashOf(keys[i])
        if v == nil then noBank = noBank + 1
        else cashVals[#cashVals + 1] = v end
    end
    local mean, med, n = meanMedian(cashVals)

    -- ---- Top 10 ทุกสกุล  (ฟีเจอร์ 2) ---------------------------------------
    --
    -- คิดทั้งสามสกุลรอบเดียวแล้วส่งไปพร้อมกัน  ไม่ใช่ยิงถามใหม่ทุกครั้งที่กดชิป
    -- การกดชิปเปลี่ยนสกุลคือการเปลี่ยน "มุมมองของข้อมูลชุดเดิม" ไม่ใช่การขอข้อมูลใหม่
    local tops = {}
    for _, cur in ipairs({ KR.CUR.CASH, KR.CUR.HF, KR.CUR.CP }) do
        local rows = {}
        for i = 1, #keys do
            local k = keys[i]
            local v = balOf(k, cur)
            if v ~= nil and v > 0 then
                rows[#rows + 1] = { k = k, disp = (d.players[k] or {}).disp or k, v = v }
            end
        end
        -- ยอดเท่ากันต้องเรียงด้วยชื่อ  ไม่งั้น table.sort สลับที่ทุกครั้งที่เปิด
        -- และแอดมินจะเห็นอันดับ 4 กับ 5 สลับกันไปมาโดยไม่มีอะไรเปลี่ยน
        table.sort(rows, function(a, b)
            if a.v ~= b.v then return a.v > b.v end
            return a.k < b.k
        end)
        local cut = {}
        for i = 1, math.min(#rows, KR.TOP_N) do
            local r = rows[i]
            cut[i] = { k = r.k, n = r.disp, v = r.v,
                       on = (S.onlineByKey and S.onlineByKey(r.k)) and true or nil }
        end
        tops[cur] = cut
    end

    -- ---- คนที่เซิร์ฟยังไม่เคยเห็นสกิล ---------------------------------------
    local unseen = 0
    for _, k in ipairs(keys) do
        if (d.players[k] or {}).skillsAt == nil then unseen = unseen + 1 end
    end

    local data = {
        at       = nowT,
        activeN  = #keys,
        days     = KR.ACTIVE_DAYS,
        cash     = { mean = mean, med = med, n = n, noBank = noBank },
        top      = tops,
        skUnseen = unseen,
    }
    CACHE = { at = nowT, data = data }
    return data
end

function S.statsGet(player, args)
    if not S.isStaff(player) then return alert(player, "Admin only.", "bad") end

    local nowT = nowTs()
    local fresh = (args and args.fresh) and true or false
    if fresh or CACHE == nil or (nowT - (CACHE.at or 0)) >= KR.STATS_CACHE_SEC then
        S.statsCompute()
    end

    local cur  = KR.CUR_META[args and args.cur] and args.cur or KR.CUR.CASH
    local days = math.floor(tonumber(args and args.days) or 7)
    if days ~= 7 and days ~= 30 then days = 7 end

    local out = {}
    for k, v in pairs(CACHE.data) do out[k] = v end
    out.cur    = cur
    out.days   = days
    out.series = S.statsSeries(cur, days)
    out.cached = (nowT - (CACHE.at or 0))

    sendServerCommand(player, KR.MODULE, KR.CMD.STATS, out)
end

-- ==============================================================================
-- สกิล  (ฟีเจอร์ 5)
-- ==============================================================================

-- รายชื่อสกิลทั้งเกม พร้อมกลุ่มของมัน  อ่านตอนรัน ไม่ฝังรายชื่อไว้
--
-- PerkFactory.PerkList เป็น list ของ Perk  แต่ละตัวมี getParent() ที่คืนกลุ่ม
-- ทั้งสองชื่อยังไม่เคยยืนยันบนบิลด์นี้ด้วยตาตัวเอง  จึงต้อง type() กันทุกชั้น
-- และถ้าอ่านไม่ได้ ต้องคืนลิสต์ว่างพร้อมเหตุผล ไม่ใช่คืนรายชื่อที่เดาเอา
local PERKS, PERK_WHY = nil, nil

local function perkName(p)
    for _, m in ipairs({ "getName", "getId" }) do
        local ok, v = pcall(function() return p[m](p) end)
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    local ok, v = pcall(function() return tostring(p) end)
    return (ok and v) or nil
end

local function groupName(p)
    local ok, parent = pcall(function() return p:getParent() end)
    if not ok or parent == nil then return nil end
    if type(parent) == "string" then return parent end
    for _, m in ipairs({ "getName", "name", "toString" }) do
        local ok2, v = pcall(function()
            local f = parent[m]
            if type(f) == "function" then return f(parent) end
            return parent[m]
        end)
        if ok2 and type(v) == "string" and v ~= "" then return v end
    end
    local ok3, v = pcall(function() return tostring(parent) end)
    return (ok3 and v) or nil
end

function S.perkList(refresh)
    if PERKS ~= nil and not refresh then return PERKS, PERK_WHY end
    PERKS, PERK_WHY = {}, nil

    if type(PerkFactory) ~= "table" and type(PerkFactory) ~= "userdata" then
        PERK_WHY = "PerkFactory is " .. type(PerkFactory)
        return PERKS, PERK_WHY
    end
    local raw = nil
    local ok = pcall(function() raw = PerkFactory.PerkList end)
    if not ok or raw == nil then
        PERK_WHY = "PerkFactory.PerkList is not readable on this build"
        return PERKS, PERK_WHY
    end
    local arr = listOf(raw)
    if arr == nil then
        PERK_WHY = "PerkFactory.PerkList is not a list we can walk"
        return PERKS, PERK_WHY
    end

    local kept, seen = 0, {}
    for i = 1, #arr do
        local p = arr[i]
        local nm = p and perkName(p)
        local gp = p and groupName(p)
        if nm and gp and not seen[nm] then
            seen[nm] = true
            -- กรองด้วย **ชื่อกลุ่ม** ไม่ใช่รายชื่อสกิล
            -- สกิลที่ม็อดอื่นเติมเข้ามาในกลุ่มเดียวกันจึงโผล่เองโดยเราไม่ต้องรู้จักมัน
            if KR.SKILL_GROUP_SET[tostring(gp):lower()] then
                kept = kept + 1
                PERKS[kept] = { id = nm, group = gp, perk = p }
            end
        end
    end
    table.sort(PERKS, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.id < b.id
    end)
    if kept == 0 and PERK_WHY == nil then
        PERK_WHY = "no skill on this build is in " .. table.concat(KR.SKILL_GROUPS, " / ")
    end
    return PERKS, PERK_WHY
end

-- เก็บ snapshot ของคนหนึ่งคน  เรียกจาก S.touch
--
-- ❗ สกิลอยู่บนตัวละคร ไม่ได้อยู่ในฐานข้อมูลของม็อด  getPerkLevel() เรียกได้เฉพาะ
-- คนที่ออนไลน์  **หน้าที่โชว์เฉพาะคนที่ออนอยู่ตอบคำถาม "ใครมี 8-10" ผิด**
-- ช่างฝีมือที่เก่งที่สุดของเซิร์ฟอาจไม่ได้ออนตอนแอดมินเปิดดู
function S.skillSnapshot(player)
    local k = key(player)
    if not k then return nil end
    if type(player.getPerkLevel) ~= "function" then return nil end

    local perks = S.perkList()
    if #perks == 0 then return nil end

    local from = KR.skillFrom()
    local got, n = {}, 0
    for i = 1, #perks do
        local row = perks[i]
        local ok, lv = pcall(function() return player:getPerkLevel(row.perk) end)
        if ok and type(lv) == "number" and lv >= from then
            got[row.id] = math.floor(lv)
            n = n + 1
        end
    end

    local p = P(k)
    -- เก็บเฉพาะตัวที่ถึงเกณฑ์  ตารางจึงเล็กมาก (คนหนึ่งไม่เกินสิบตัว)
    p.skills   = got
    p.skillsAt = nowTs()
    p.skillsFrom = from      -- เก็บเกณฑ์ที่ใช้ตอนนั้นไว้ด้วย  ไม่งั้นเปลี่ยน sandbox
                             -- แล้วข้อมูลเก่ากับใหม่ปนกันโดยไม่มีใครรู้
    return n
end

function S.skillsGet(player, args)
    if not S.isStaff(player) then return alert(player, "Admin only.", "bad") end

    local perks, why = S.perkList(args and args.refresh)
    local d = db()
    local from = KR.skillFrom()

    -- รายชื่อสกิลที่มีในเกมนี้  จอเอาไปทำลิสต์ให้เลือก
    local skills = {}
    for i = 1, #perks do
        skills[i] = { id = perks[i].id, group = perks[i].group }
    end

    -- ใครถึงเกณฑ์บ้าง  เดินทะเบียนรอบเดียว แล้วจอเลือกมุมมองเอง
    -- (มุม "รายสกิล" กับ "รายคน" เป็นข้อมูลชุดเดียวกันมองคนละด้าน
    --  ยิงถามสองรอบคือการให้เซิร์ฟทำงานซ้ำเพื่อผลลัพธ์เดิม)
    local people, n = {}, 0
    for k, row in pairs(d.players or {}) do
        local sk = row.skills
        if type(sk) == "table" then
            local keep, any = {}, false
            for id, lv in pairs(sk) do
                if (tonumber(lv) or 0) >= from then keep[id] = math.floor(lv); any = true end
            end
            if any then
                n = n + 1
                people[n] = {
                    k    = k,
                    n    = row.disp or k,
                    at   = row.skillsAt,
                    on   = (S.onlineByKey and S.onlineByKey(k)) and true or nil,
                    s    = keep,
                }
            end
        end
    end
    table.sort(people, function(a, b) return a.k < b.k end)

    -- คนที่เซิร์ฟยังไม่เคยเห็นสกิลเลย  ต้องบอกจำนวนออกไป
    -- วันแรกที่ลง หน้านี้จะมีเฉพาะคนที่เข้ามาแล้วหลังอัปเดต
    -- **ห้ามให้ดูเหมือนว่าไม่มีใครเก่ง** ต้องเขียนตรง ๆ ว่ายังไม่เคยเห็นกี่คน
    local unseen = 0
    for _, row in pairs(d.players or {}) do
        if row.skillsAt == nil then unseen = unseen + 1 end
    end

    sendServerCommand(player, KR.MODULE, KR.CMD.SKILLS, {
        from   = from,
        groups = KR.SKILL_GROUPS,
        skills = skills,
        people = people,
        unseen = unseen,
        why    = why,
        at     = nowTs(),
    })
end

-- ==============================================================================
-- กระดานราคาสินค้าโลก  (ฟีเจอร์ 4)
--
-- ❗ ไม่มีเส้นทางไหนจากตารางนี้ไปถึง S.buy() เลย  และนั่นเป็นข้อที่มีด่านยืนยัน
-- แถวในกระดานไม่มี item type ไม่มี pay ไม่มี stock  มันคือ ชื่อ · ราคา · สกุล · หมายเหตุ
-- ==============================================================================
local function boardTable(d)
    d.board = d.board or {}
    d.board.cats = d.board.cats or {}
    d.board.list = d.board.list or {}
    d.board.next = tonumber(d.board.next) or 1
    return d.board
end

S.boardTable = boardTable

local function cleanCat(v)
    return KR.trunc(tostring(v or ""), KR.BOARD_CAT_MAX)
end

function S.boardSet(player, args)
    if not S.isStaff(player) then return alert(player, "Admin only.", "bad") end
    local d = db()
    local b = boardTable(d)
    local a = args or {}

    local name = KR.trunc(a.name, KR.BOARD_NAME_MAX)
    if name == "" then return alert(player, "Name required.", "bad") end

    local price = math.floor(tonumber(a.price) or 0)
    if price < 0 then return alert(player, "Price cannot be negative.", "bad") end

    local cur = KR.CUR_META[a.cur] and a.cur or KR.CUR.CASH
    local cat = cleanCat(a.cat)
    if cat == "" then cat = "general" end
    local note = KR.trunc(a.note, KR.BOARD_NOTE_MAX)

    local id = tostring(a.id or ""):gsub("[^%w_%-]", ""):sub(1, 32)
    local found = nil
    for i = 1, #b.list do
        if b.list[i].id == id then found = i end
    end

    if found == nil then
        if #b.list >= KR.BOARD_MAX then
            return alert(player, "The board is full (" .. KR.BOARD_MAX ..
                                 " rows). Delete something first.", "bad")
        end
        id = "bd_" .. tostring(b.next)
        b.next = b.next + 1
        found = #b.list + 1
    end

    b.list[found] = { id = id, name = name, cat = cat, price = price, cur = cur,
                      note = (note ~= "") and note or nil,
                      by = P(key(player)).disp or key(player), at = nowTs() }

    -- หมวดใหม่โผล่เองจากของที่ลงไว้  เหมือนหมวดของร้าน
    -- ลำดับที่แอดมินจัดไว้อยู่ใน b.cats  หมวดที่ไม่อยู่ในลิสต์ไปต่อท้าย
    local known = false
    for i = 1, #b.cats do if b.cats[i] == cat then known = true end end
    if not known and #b.cats < KR.BOARD_CAT_MAX then
        b.cats[#b.cats + 1] = cat
    end

    alert(player, "Saved " .. name .. " to the price board.", "good")
    S.syncAll()
end

function S.boardDel(player, args)
    if not S.isStaff(player) then return alert(player, "Admin only.", "bad") end
    local b = boardTable(db())
    local id = tostring(args and args.id or "")
    for i = #b.list, 1, -1 do
        if b.list[i].id == id then
            local nm = b.list[i].name
            table.remove(b.list, i)
            alert(player, "Removed " .. tostring(nm) .. " from the price board.", "good")
            S.syncAll()
            return
        end
    end
    alert(player, "No such row on the board.", "bad")
end

function S.boardCats(player, args)
    if not S.isStaff(player) then return alert(player, "Admin only.", "bad") end
    local b = boardTable(db())
    local a = args or {}

    if a.act == "order" and type(a.cats) == "table" then
        local out, seen = {}, {}
        for i = 1, math.min(#a.cats, KR.BOARD_CAT_MAX) do
            local c = cleanCat(a.cats[i])
            if c ~= "" and not seen[c] then seen[c] = true; out[#out + 1] = c end
        end
        b.cats = out

    elseif a.act == "rename" then
        local from, to = cleanCat(a.from), cleanCat(a.to)
        if from == "" or to == "" then return alert(player, "Bad category name.", "bad") end
        for i = 1, #b.cats do if b.cats[i] == from then b.cats[i] = to end end
        for i = 1, #b.list do if b.list[i].cat == from then b.list[i].cat = to end end

    elseif a.act == "del" then
        local c = cleanCat(a.cat)
        for i = #b.cats, 1, -1 do if b.cats[i] == c then table.remove(b.cats, i) end end
        -- ของในหมวดที่ถูกลบไม่หาย  ย้ายไป general
        -- ลบหมวดแล้วของหายคือการลบที่ผู้ใช้ไม่ได้สั่ง
        for i = 1, #b.list do
            if b.list[i].cat == c then b.list[i].cat = "general" end
        end

    else
        return alert(player, "Unknown board action.", "bad")
    end

    S.syncAll()
end

-- สิ่งที่ส่งไปให้ทุกคนใน sync  เล็กพอที่จะส่งได้ทุกรอบ
-- (400 แถว x ห้าฟิลด์สั้น ๆ เทียบกับแคตตาล็อกร้านแล้วเล็กกว่ามาก)
function S.boardPayload()
    local b = boardTable(db())
    return { cats = b.cats, list = b.list }
end

print("[Kuraya] KR_Stats ready")

return true
