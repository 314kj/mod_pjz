-- ==============================================================================
-- Akacount — client/Akacount/AC_Theme.lua
-- ธีมมืด + ตัวช่วยวาด  ที่เดียวที่นิยามสี  ห้ามมี literal สีในไฟล์อื่น
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- v0.4.0  ธีมใหม่ทั้งชุด  มืด แบน ไม่มีเส้นขอบ แยกชั้นด้วยความสว่างของพื้นอย่างเดียว
--
-- สิ่งที่ PZ วาดไม่ได้ และทางอ้อมที่ใช้
--   มุมโค้ง   -> drawRect ไม่มี radius  ใช้ texture วงกลมหนึ่งในสี่ (rc_*.png) ย้อมสีตอนวาด
--               แถบตรงกลางสามแถบวางไม่ทับกัน  alpha ต่ำกว่า 1 จึงไม่เกิดรอยซ้อน
--   วงกลม     -> circle.png ย้อมสี  ใช้กับรูปโปรไฟล์ตัวย่อชื่อ / จุดสถานะ
--   ไอคอน     -> PNG ขาวล้วน 64px  ย้อมสีตามสถานะ  (ขาวคูณสีอะไรก็ได้สีนั้น)
--   ฟอนต์     -> บันได Small / Medium / Large เท่านั้น  ความสูงจริงวัดจาก getFontHeight ทุกครั้ง
--
-- texture หาไม่เจอ = ตกกลับไปวาดสี่เหลี่ยมธรรมดา  หน้าตาจืดลงแต่ไม่พัง
-- ==============================================================================
require("Akacount/AC_Const")

ACUI = ACUI or {}
local T = ACUI

local function rgb(hex)
    return {
        r = tonumber(hex:sub(1, 2), 16) / 255,
        g = tonumber(hex:sub(3, 4), 16) / 255,
        b = tonumber(hex:sub(5, 6), 16) / 255,
    }
end

-- ------------------------------------------------------------------------------
-- สี
-- ------------------------------------------------------------------------------
T.C = {
    bg      = rgb("0e1016"),   -- พื้นหน้าต่าง
    bar     = rgb("0a0b10"),   -- แถบหัว
    surf    = rgb("161922"),   -- การ์ด / แถว
    surf2   = rgb("1e222d"),   -- ช่องกรอก / ชิป
    surf3   = rgb("2a2f3d"),   -- hover
    line    = rgb("232734"),   -- เส้นคั่นบาง ๆ
    text    = rgb("f1f2f6"),   -- ตัวหนังสือหลัก
    text2   = rgb("a4a9ba"),   -- รอง
    text3   = rgb("6c7288"),   -- จาง / ป้ายกำกับ
    accent  = rgb("7c6cff"),   -- ม่วงของแบรนด์ ยกความสว่างขึ้นให้อ่านบนพื้นมืดได้
    accent2 = rgb("968aff"),   -- hover
    accentD = rgb("262150"),   -- พื้นของที่ถูกเลือก
    hero    = rgb("5a49d6"),   -- การ์ดยอดเงิน
    good    = rgb("3ddc97"),   -- เงินเข้า / สำเร็จ
    goodD   = rgb("14352a"),
    bad     = rgb("ff6b7a"),   -- เงินออก / ผิดพลาด
    badD    = rgb("3a1a22"),
    warn    = rgb("ffb547"),   -- ค่าธรรมเนียม / อยู่นอกธนาคาร
    warnD   = rgb("3a2a12"),
    info    = rgb("4da3ff"),   -- แอดมิน
    infoD   = rgb("132a44"),
    gold    = rgb("f4c95d"),
    white   = rgb("ffffff"),
}

-- สีรูปโปรไฟล์  เลือกจากชื่อ ชื่อเดิมได้สีเดิมทุกครั้ง  ห้ามสุ่ม
T.AVATAR = {
    rgb("6c5ce7"), rgb("00a8a8"), rgb("e17055"), rgb("0984e3"),
    rgb("d6a019"), rgb("e84393"), rgb("20a162"), rgb("8e6c4f"),
}

-- ------------------------------------------------------------------------------
-- ฟอนต์
--   v0.2.3 ขยับทั้งชุดขึ้นหนึ่งขั้นเพื่ออ่านง่าย  ผลคือจอเล็กตัวหนังสือล้นทับกัน
--   v0.4.0 เนื้อหากลับมาเป็น Small  หัวข้อ/ปุ่ม Medium  ยอดเงิน Large
--   ถ้าอยากขยับอีก แก้ตรงนี้ที่เดียว  ผังทุกหน้าคำนวณจาก getFontHeight ของตารางนี้
-- ------------------------------------------------------------------------------
T.F = { xs = UIFont.Small, s = UIFont.Small, m = UIFont.Medium, l = UIFont.Large }

function T.th(f) return getTextManager():getFontHeight(f or T.F.s) end
function T.tw(s, f) return getTextManager():MeasureStringX(f or T.F.s, tostring(s)) end

-- ตัดข้อความตาม "ความกว้างจริง" ไม่ใช่จำนวนตัวอักษร  ความกว้างเปลี่ยนตาม UI scale
function T.clip(s, maxW, f)
    s = tostring(s or "")
    if maxW <= 0 then return "" end
    if T.tw(s, f) <= maxW then return s end
    while #s > 1 and T.tw(s .. "..", f) > maxW do s = s:sub(1, #s - 1) end
    if #s <= 1 then return "" end
    return s .. ".."
end

-- เลือกข้อความที่ยาวที่สุดที่ยังพอดี  เช่น { "Withdraw", "Draw", "" }
function T.fit(list, maxW, f)
    for i = 1, #list do
        if T.tw(list[i], f) <= maxW then return list[i] end
    end
    return ""
end

-- ------------------------------------------------------------------------------
-- texture  โหลดครั้งเดียวแล้วจำ  getTexture ทุกเฟรม = ค้นไฟล์ทุกเฟรม
-- ------------------------------------------------------------------------------
local texCache = {}
function T.tex(name)
    local v = texCache[name]
    if v == nil then
        local ok, t = pcall(getTexture, "media/textures/AkacountUI/" .. name .. ".png")
        v = (ok and t) or false
        texCache[name] = v
    end
    return v or nil
end

-- texture ที่อยู่นอกโฟลเดอร์ UI (โลโก้ เหรียญ ลายบัตร)  ส่ง path เต็ม
function T.texAt(path)
    local v = texCache[path]
    if v == nil then
        local ok, t = pcall(getTexture, path)
        v = (ok and t) or false
        texCache[path] = v
    end
    return v or nil
end

-- ------------------------------------------------------------------------------
-- ตัวช่วยวาด   el = ISUIElement   พิกัดปัดเป็นจำนวนเต็มเสมอ กันรอยต่อ 1px
-- ------------------------------------------------------------------------------
local floor = math.floor

function T.rect(el, x, y, w, h, c, a)
    if w <= 0 or h <= 0 then return end
    el:drawRect(floor(x), floor(y), floor(w), floor(h), a or 1, c.r, c.g, c.b)
end

-- ไอคอน/รูปขาวที่ย้อมสี  คืน false ถ้าไม่มีไฟล์
function T.img(el, name, x, y, w, h, c, a)
    local t = T.tex(name)
    if not t then return false end
    c = c or T.C.white
    el:drawTextureScaled(t, floor(x), floor(y), floor(w), floor(h), a or 1, c.r, c.g, c.b)
    return true
end

-- รูปสี (ไม่ย้อม)
function T.art(el, tex, x, y, w, h, a)
    if not tex then return false end
    el:drawTextureScaled(tex, floor(x), floor(y), floor(w), floor(h), a or 1, 1, 1, 1)
    return true
end

-- สี่เหลี่ยมมุมโค้ง
function T.rrect(el, x, y, w, h, r, c, a)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    if w <= 0 or h <= 0 then return end
    r = floor(math.min(r or 8, w / 2, h / 2))
    if r < 2 or not T.tex("rc_tl") then return T.rect(el, x, y, w, h, c, a) end
    T.rect(el, x + r, y, w - 2 * r, r, c, a)
    T.rect(el, x, y + r, w, h - 2 * r, c, a)
    T.rect(el, x + r, y + h - r, w - 2 * r, r, c, a)
    T.img(el, "rc_tl", x, y, r, r, c, a)
    T.img(el, "rc_tr", x + w - r, y, r, r, c, a)
    T.img(el, "rc_bl", x, y + h - r, r, r, c, a)
    T.img(el, "rc_br", x + w - r, y + h - r, r, r, c, a)
end

function T.circle(el, x, y, d, c, a)
    if not T.img(el, "circle", x, y, d, d, c, a) then T.rect(el, x, y, d, d, c, a) end
end

function T.text(el, s, x, y, c, f, a)
    c = c or T.C.text
    el:drawText(tostring(s), floor(x), floor(y), c.r, c.g, c.b, a or 1, f or T.F.s)
end
function T.textR(el, s, x, y, c, f, a)
    c = c or T.C.text
    el:drawTextRight(tostring(s), floor(x), floor(y), c.r, c.g, c.b, a or 1, f or T.F.s)
end
function T.textC(el, s, x, y, c, f, a)
    c = c or T.C.text
    el:drawTextCentre(tostring(s), floor(x), floor(y), c.r, c.g, c.b, a or 1, f or T.F.s)
end

function T.hr(el, x, y, w, c) T.rect(el, x, y, w, 1, c or T.C.line) end

-- ------------------------------------------------------------------------------
-- ปุ่ม
--   kind: pri (ม่วงทึบ) / ok (เขียว) / sec (เทา) / ghost (โปร่ง) / off (กดไม่ได้)
--   ป้ายลองฟอนต์ Medium ก่อน ไม่พอดีค่อยลง Small ไม่พอดีอีกค่อยตัด
--   ไอคอนไปก่อนป้าย  ถ้าที่ไม่พอแม้แต่ป้ายสั้นสุด เหลือไอคอนอย่างเดียว
--   คืนสี่เหลี่ยมพื้นที่กด  ตัวเลขชุดเดียวกับที่วาด  ปุ่มที่เห็นแต่กดไม่ติดจึงเกิดไม่ได้
-- ------------------------------------------------------------------------------
local BTN = {
    pri   = { bg = "accent", hov = "accent2", fg = "white" },
    ok    = { bg = "good",   hov = "good",    fg = "bg"    },
    sec   = { bg = "surf2",  hov = "surf3",   fg = "text"  },
    ghost = { bg = nil,      hov = "surf2",   fg = "text2" },
    off   = { bg = "surf",   hov = "surf",    fg = "text3" },
    bad   = { bg = "badD",   hov = "badD",    fg = "bad"   },
}

function T.hot(r, mx, my)
    return r and mx and my and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

function T.button(el, x, y, w, h, label, kind, icon, mx, my)
    local st = BTN[kind or "pri"] or BTN.pri
    local r = { x = floor(x), y = floor(y), w = floor(w), h = floor(h) }
    local hov = (kind ~= "off") and T.hot(r, mx, my)
    local bgName = hov and st.hov or st.bg
    if bgName then T.rrect(el, r.x, r.y, r.w, r.h, math.min(8, floor(r.h / 3)), T.C[bgName]) end
    local fg = T.C[st.fg]

    local isz  = icon and math.max(10, math.min(r.h - 10, T.th(T.F.s) - 1)) or 0
    local gap  = icon and 5 or 0
    local room = r.w - 12 - isz - gap
    local f    = T.F.m
    local lbl  = label or ""
    if type(lbl) == "table" then
        local pick = T.fit(lbl, room, T.F.m)
        if pick == "" then f = T.F.s; pick = T.fit(lbl, room, T.F.s) end
        lbl = pick
    else
        if T.tw(lbl, f) > room then f = T.F.s end
        lbl = T.clip(lbl, room, f)
    end
    if T.th(f) > r.h - 2 then f = T.F.s end
    if lbl == "" then gap = 0 end

    local tw = (lbl ~= "") and T.tw(lbl, f) or 0
    local total = isz + gap + tw
    local cx = r.x + floor((r.w - total) / 2)
    if icon then T.img(el, icon, cx, r.y + floor((r.h - isz) / 2), isz, isz, fg) end
    if lbl ~= "" then T.text(el, lbl, cx + isz + gap, r.y + floor((r.h - T.th(f)) / 2), fg, f) end
    return r
end

-- ป้ายเล็กทรงเม็ดยา  คืนความกว้างที่ใช้
function T.pill(el, x, y, label, fg, bg, f, dot, bgA)
    f = f or T.F.xs
    local h = T.th(f) + 4
    local dw = dot and (floor(h * 0.4) + 5) or 0
    local w = T.tw(label, f) + 14 + dw
    T.rrect(el, x, y, w, h, floor(h / 2), bg, bgA)
    if dot then T.circle(el, x + 7, y + floor((h - floor(h * 0.4)) / 2), floor(h * 0.4), fg) end
    T.text(el, label, x + 7 + dw, y + 2, fg, f)
    return w, h
end
function T.pillW(label, f, dot)
    f = f or T.F.xs
    local h = T.th(f) + 4
    return T.tw(label, f) + 14 + (dot and (floor(h * 0.4) + 5) or 0), h
end

-- รูปโปรไฟล์ตัวย่อชื่อ  สีมาจากชื่อ
function T.avatarColor(key)
    local s, n = tostring(key or "?"), 0
    for i = 1, #s do n = (n * 31 + s:byte(i)) % 100003 end
    return T.AVATAR[(n % #T.AVATAR) + 1]
end

function T.avatar(el, x, y, d, name, key, ring)
    if ring then T.circle(el, x - 2, y - 2, d + 4, T.C.accent) end
    T.circle(el, x, y, d, T.avatarColor(key or name))
    local ch = tostring(name or "?"):sub(1, 1):upper()
    local f = (d >= T.th(T.F.m) + 6) and T.F.m or T.F.s
    T.textC(el, ch, x + d / 2, y + floor((d - T.th(f)) / 2), T.C.white, f)
end

return ACUI
