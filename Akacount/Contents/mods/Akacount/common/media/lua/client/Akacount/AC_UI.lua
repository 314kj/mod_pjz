-- ==============================================================================
-- Akacount — client/Akacount/AC_UI.lua
-- หน้าต่างสองบาน  เคาน์เตอร์ธนาคาร / บัตร (โอนเงิน + กล่องรับโอน)
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- v0.4.0  รื้อหน้าตาใหม่ทั้งหมด (ธีมมืด)  ตรรกะเงินไม่ได้แตะ
--
-- กฎผังที่ทำให้ "ตัวหนังสือซ้อนกัน" หายไปจริง  (ดู PZ-B42-UI-layout-gate-RULE)
--   1. ไม่มี offset ตายตัวที่ผูกกับตัวหนังสือเลยสักจุด  ทุกความสูงมาจาก metrics()
--      ซึ่งวัด getFontHeight สด ๆ   ของเดิม "+15" ใต้ฟอนต์ Medium ที่สูง 19 = ทับกัน 4px
--   2. ข้อความทุกบรรทัดถูกตัดตามความกว้างที่เหลือจริง  ป้ายซ้าย+ตัวเลขขวาในแถวเดียวกัน
--      ป้ายซ้ายถูกตัดก่อนเสมอ ตัวเลขเงินห้ามถูกตัด
--   3. ความสูงหน้าต่างคำนวณจากเนื้อหา (needH) แล้ว clamp กับจอ
--      ไม่พอ -> โหมดกระชับ (การ์ดยอดเงินแถวเดียว / ซ่อนแถวคนที่โอนบ่อย)
--   4. ปุ่มหลักยึดล่างเสมอ  needH รับประกันว่าเนื้อหาบนไม่ไหลลงมาชน
--   5. ช่องกรอกเปิด/ปิดด้วยการประทับเลขเฟรม  ใครไม่วางมันในเฟรมนี้ = มองไม่เห็นเอง
--      และถูกซ่อนอัตโนมัติเมื่อ dropdown ลอยทับ
--
-- หน้าต่างวาดเองทั้งหมด ไม่ใช้ ISCollapsableWindow (แถบชื่อสูงเกิน + ปุ่มย่อที่ไม่ได้ใช้)
-- ==============================================================================
require("ISUI/ISPanel")
require("ISUI/ISTextEntryBox")
require("Akacount/AC_Const")
require("Akacount/AC_Util")
require("Akacount/AC_Theme")

print("[Akacount] AC_UI  v" .. AC.VERSION)

local U = AC.util
local T = ACUI
local C, F = T.C, T.F
local floor = math.floor

ACWindows = ACWindows or { open = {} }

-- ------------------------------------------------------------------------------
-- ขนาดทุกอย่างมาจากความสูงฟอนต์จริง  เรียกทุกเฟรม (ถูกมาก เป็นแค่บวกลบ)
-- ------------------------------------------------------------------------------
local function metrics()
    local s, m, l = T.th(F.s), T.th(F.m), T.th(F.l)
    return {
        s = s, m = m, l = l,
        pad   = math.max(10, floor(s * 0.75)),
        gap   = math.max(6, floor(s * 0.42)),
        hdr   = m + 16,
        field = s + 16,
        btn   = math.max(s + 18, m + 12),
        tab   = s + 16,
        chip  = s + 12,
        row   = s * 2 + 14,     -- แถวสองบรรทัด
        row1  = s + 14,         -- แถวบรรทัดเดียว (รายชื่อ)
        sumRow = s + 6,
    }
end

local function heroH(m, compact)
    if compact then return m.l + 14 end
    return 12 + m.s + 2 + m.l + 8 + (m.s + 4) + 12
end
local function rowsH(m, n) return n * m.sumRow + 12 end
local function labelH(m) return m.s + 4 end
local function recentsH(m) return (m.m + 14) + 4 + m.s end

-- ------------------------------------------------------------------------------
-- ปรับขนาดช่องกรอกให้ถูกวิธี
-- `box.width = 100` ไม่ทำให้พื้นที่รับคลิกกว้างขึ้นจริง ต้อง setWidth/setHeight เท่านั้น
-- ------------------------------------------------------------------------------
local function sizeBox(box, w, h)
    if not box then return end
    if w then box:setWidth(math.max(8, floor(w))) end
    if h then box:setHeight(math.max(8, floor(h))) end
end

local function overlaps(a, b)
    return a and b and a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- ค้นแบบ "มีคำนี้อยู่ข้างใน" โดยไม่ใช้ pattern  ชื่อตัวละครมี . - ( ) ได้ ซึ่งเป็นอักขระพิเศษของ pattern
local function contains(hay, needle)
    if needle == "" then return true end
    local n, k = #hay, #needle
    for i = 1, n - k + 1 do
        if hay:sub(i, i + k - 1) == needle then return true end
    end
    return false
end

-- ------------------------------------------------------------------------------
-- คำอธิบายรายการเดินบัญชี  (ยกมาจาก v0.3.4 ทั้งชุด  ตรรกะไม่ได้เปลี่ยน)
-- ------------------------------------------------------------------------------
local KIND_TH = {
    dep   = { "ฝากเงินสด", "Cash deposit" },
    wdr   = { "ถอนเงินสด", "Cash withdrawal" },
    xfr   = { "โอนให้ผู้เล่น", "Sent to player" },
    fee   = { "ค่าธรรมเนียม", "Fee" },
    int   = { "ดอกเบี้ยเงินฝาก", "Savings interest" },
    loan  = { "รับเงินกู้", "Loan received" },
    repay = { "ผ่อนชำระ", "Loan payment" },
    bill  = { "ชำระบิล", "Bill paid" },
    shop  = { "ซื้อของที่ร้าน", "Shop purchase" },
    esc   = { "พักเงินไว้ในระบบ", "Held in escrow" },
    adm   = { "แอดมินปรับยอด", "Admin adjustment" },
}
local KIND_IN = { xfr = { "รับโอนจากผู้เล่น", "Received from player" } }
local WHERE = {
    counter = { "ที่ธนาคาร", "from bank" },
    card    = { "ส่งทางไกล", "Remote send" },
}
local SYS_ACT = {
    dep = { "ฝากเงิน", "Deposit" }, wdr = { "ถอนเงิน", "Withdrawal" }, int = { "ดอกเบี้ย", "Interest" },
    bill = { "บิล", "Bill" }, loan = { "เงินกู้", "Loan" }, repay = { "ผ่อนชำระ", "Loan payment" },
    fee = { "ค่าธรรมเนียม", "Fee" }, esc = { "พักเงิน", "Escrow" }, shop = { "ร้านค้า", "Shop" },
    adm = { "แอดมิน", "Admin" },
}
local REF_SKIP = { admin = true, deposit = true, atm = true, xfer = true, shop = true }

local function isIncoming(e, me) return e.to == me end
local function L2(pair, fallback)
    if type(pair) == "table" then return AC.L(pair[1], pair[2]) end
    return fallback
end
local function whereOf(e)
    if WHERE[e.via] then return L2(WHERE[e.via]) end
    return L2(SYS_ACT[e.k], AC.L("ระบบ", "System"))
end

local function describe(e, me)
    local inc = isIncoming(e, me)
    local who = e.who
    local wh  = whereOf(e)
    local lbl = (inc and KIND_IN[e.k]) and L2(KIND_IN[e.k]) or L2(KIND_TH[e.k], e.k or "-")
    local head, whDone, lblDone = lbl, false, false
    if e.k == AC.KIND.ADMIN then
        if who then head = AC.L("แอดมิน - ", "Admin - ") .. who; whDone = true end
    elseif e.k == AC.KIND.TRANSFER then
        if inc then
            if who then head = who .. " - " .. wh; whDone = true end
        elseif who then
            head, lblDone = AC.L("โอนเงินให้ - ", "Send money to - ") .. who, true
        end
    elseif e.k == AC.KIND.DEPOSIT or e.k == AC.KIND.WITHDRAW then
        if who then head = who .. " - " .. wh; whDone = true end
    end
    local bits = {}
    if head ~= lbl and not lblDone then bits[#bits + 1] = lbl end
    if not whDone and (WHERE[e.via] or head ~= lbl) then bits[#bits + 1] = wh end
    if e.r and not REF_SKIP[tostring(e.r)] then bits[#bits + 1] = tostring(e.r) end
    return head, table.concat(bits, "  ")
end

-- ไอคอน + สีของแต่ละชนิดรายการ  บอกประเภทได้โดยไม่ต้องอ่าน
local function kindLook(k, inc)
    if k == AC.KIND.TRANSFER then
        if inc then return "ic_deposit", C.good, C.goodD end
        return "ic_send", C.accent2, C.accentD
    end
    if k == AC.KIND.DEPOSIT  then return "ic_deposit", C.good, C.goodD end
    if k == AC.KIND.WITHDRAW then return "ic_withdraw", C.text2, C.surf2 end
    if k == AC.KIND.FEE      then return "ic_card", C.warn, C.warnD end
    if k == AC.KIND.ADMIN    then return "ic_check", C.info, C.infoD end
    return "ic_history", C.text2, C.surf2
end

local function ago(t)
    if ACClient and ACClient.ago then return ACClient.ago(t) end
    return ""
end

-- basis points -> "2%" / "2.5%"   ห้ามใส่ % ลง string.format (Kahlua)
local function pctText(bp)
    bp = floor(tonumber(bp) or 0)
    local whole, frac = floor(bp / 100), bp % 100
    local s = tostring(whole)
    if frac > 0 then
        if frac % 10 == 0 then s = s .. "." .. tostring(floor(frac / 10))
        else s = s .. "." .. ((frac < 10) and "0" or "") .. tostring(frac) end
    end
    return s .. "%"
end

-- เลขในช่องกรอก  ไม่มีจุลภาค (ช่องรับเฉพาะตัวเลข)
local function plainNum(sub)
    sub = floor(tonumber(sub) or 0)
    if sub % 100 == 0 then return tostring(floor(sub / 100)) end
    return string.format("%.2f", sub / 100)
end

-- ==============================================================================
-- ฐานหน้าต่าง
-- ==============================================================================
local Base = ISPanel:derive("Akacount_Base")

function Base:new(x, y, w, h, title, sub)
    local o = ISPanel.new(self, x, y, w, h)
    o.background    = false
    o.moveWithMouse = false
    o.title, o.sub  = title, sub
    o.mx, o.my      = -1, -1
    o.frameNo       = 0
    o.boxes         = {}
    o.sc            = {}     -- ตำแหน่งเลื่อนของแต่ละลิสต์
    o.areas         = {}     -- ลิสต์ที่เลื่อนได้ในเฟรมล่าสุด
    o.zones, o.ozones = {}, {}
    o.hdrH          = 30
    o.dense         = 0
    return o
end

-- ช่องกรอก  โปร่งใส เราวาดพื้นเอง (มุมโค้ง)  ตัวมันเองเป็นลูกจริงของหน้าต่าง
function Base:newBox(numbers)
    local b = ISTextEntryBox:new("", 0, 0, 100, T.th(F.s) + 6)
    b:initialise(); b:instantiate()
    if numbers then b:setOnlyNumbers(true) end
    b.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    b.borderColor     = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(b)
    self.boxes[#self.boxes + 1] = b
    return b
end

function Base:placeBox(b, x, y, w, h)
    local bh = T.th(F.s) + 6
    b.__acFrame = self.frameNo
    b.__acRect  = { x = floor(x), y = floor(y), w = floor(w), h = floor(h) }
    b:setX(floor(x)); b:setY(floor(y + (h - bh) / 2))
    sizeBox(b, w, bh)
end

-- ท้ายเฟรม  เปิดเฉพาะช่องที่ถูกวางในเฟรมนี้ และไม่โดน dropdown ทับ
function Base:finishBoxes()
    for _, b in ipairs(self.boxes) do
        local on = (b.__acFrame == self.frameNo)
        if on and self.overlay and overlaps(b.__acRect, self.overlay) then on = false end
        if b.__acShown ~= on then
            b:setVisible(on)
            b.__acShown = on
            if not on and U.hasMethod(b, "unfocus") then pcall(function() b:unfocus() end) end
        end
        if not on then b:setY(self.height + 40) end
    end
end

function Base:zone(r, fn, layer)
    if not r then return end
    local list = (layer == 1) and self.ozones or self.zones
    list[#list + 1] = { x = r.x, y = r.y, w = r.w, h = r.h, fn = fn }
end

function Base:prerender()
    self.mx, self.my = self:getMouseX(), self:getMouseY()
    self.frameNo = self.frameNo + 1
    self.zones, self.ozones, self.areas = {}, {}, {}
    self.overlay = nil
    local ok, err = pcall(self.draw, self)
    if not ok then
        if not self.errShown then
            self.errShown = true
            print("[Akacount] UI draw error: " .. tostring(err))
        end
        self.zones, self.ozones, self.areas, self.overlay = {}, {}, {}, nil
        T.rect(self, 0, 0, self.width, self.height, C.bg)
        T.text(self, "Akacount UI error - see console.txt", 10, 10, C.bad, F.s)
        T.text(self, T.clip(tostring(err), self.width - 20, F.xs), 10, 14 + T.th(F.s), C.text2, F.xs)
        T.text(self, "Click to close", 10, 18 + T.th(F.s) * 2, C.text3, F.xs)
        self:zone({ x = 0, y = 0, w = self.width, h = self.height }, function() self:close() end)
    end
    self:finishBoxes()
end

function Base:render() end
function Base:draw() end

function Base:close()
    self:removeFromUIManager()
    if self.acKey then ACWindows.open[self.acKey] = nil end
end

-- ------------------------------------------------------------------------------
-- ลิสต์ที่เลื่อนได้  ล้อเมาส์ + ลากแถบเลื่อน + คลิกที่ราง
-- ------------------------------------------------------------------------------
function Base:scrollList(key, x, y, w, h, n, rowH, drawRow, layer)
    local st = self.sc[key]
    if not st then st = { off = 0 }; self.sc[key] = st end
    local vis    = math.max(1, floor(h / rowH))
    local maxOff = math.max(0, n - vis)
    st.off = math.max(0, math.min(maxOff, floor(tonumber(st.off) or 0)))

    local barW = (maxOff > 0) and math.max(5, floor(T.th(F.s) * 0.35)) or 0
    local rw   = w - ((barW > 0) and (barW + 6) or 0)
    for i = 1, math.min(vis, n) do
        drawRow(i + st.off, x, y + (i - 1) * rowH, rw, rowH)
    end

    local area = { key = key, x = x, y = y, w = w, h = h, maxOff = maxOff, layer = layer or 0 }
    if maxOff > 0 then
        local trackH = h
        local thH = math.max(floor(rowH * 0.75), floor(trackH * vis / n))
        local thY = y + floor((trackH - thH) * st.off / maxOff)
        local tx  = x + w - barW
        -- พื้นที่กดกว้างกว่าที่วาด  แถบบาง 5px จิ้มโดนยาก
        area.track  = { x = tx - 5, y = y, w = barW + 5, h = trackH }
        area.thumb  = { x = tx - 5, y = thY, w = barW + 5, h = thH }
        area.thH, area.trackY, area.trackH = thH, y, trackH
        local hot = (self.drag and self.drag.key == key) or T.hot(area.thumb, self.mx, self.my)
        T.rrect(self, tx, y, barW, trackH, floor(barW / 2), C.surf2)
        T.rrect(self, tx, thY, barW, thH, floor(barW / 2), hot and C.accent2 or C.text3)
    end
    self.areas[#self.areas + 1] = area
    return vis, maxOff
end

function Base:areaOf(key)
    for i = #self.areas, 1, -1 do
        if self.areas[i].key == key then return self.areas[i] end
    end
    return nil
end

-- ลิสต์ชั้นล่างที่ถูก dropdown บังอยู่ ห้ามรับเมาส์
function Base:blocked(a, x, y)
    return self.overlay and (a.layer or 0) == 0 and T.hot(self.overlay, x, y)
end

function Base:scrollGrab(x, y)
    for i = #self.areas, 1, -1 do
        local a = self.areas[i]
        if a.track and T.hot(a.track, x, y) and not self:blocked(a, x, y) then
            if T.hot(a.thumb, x, y) then
                self.drag = { key = a.key, dy = y - a.thumb.y }
            else
                self.drag = { key = a.key, dy = floor(a.thH / 2) }
                self:scrollDragTo(y)
            end
            return true
        end
    end
    return false
end

function Base:scrollDragTo(my)
    local d = self.drag
    if not d then return end
    local a = self:areaOf(d.key)
    if not a or not a.track then return end
    local span = a.trackH - a.thH
    if span <= 0 then return end
    local off = floor((my - d.dy - a.trackY) / span * a.maxOff + 0.5)
    self.sc[d.key].off = math.max(0, math.min(a.maxOff, off))
end

function Base:onMouseWheel(del)
    local mx, my = self:getMouseX(), self:getMouseY()
    for i = #self.areas, 1, -1 do
        local a = self.areas[i]
        if a.maxOff > 0 and mx >= a.x and mx < a.x + a.w and my >= a.y and my < a.y + a.h
           and not self:blocked(a, mx, my) then
            local st = self.sc[a.key]
            st.off = math.max(0, math.min(a.maxOff, st.off + (((del or 0) > 0) and 1 or -1)))
            return true
        end
    end
    return true     -- ล้อบนหน้าต่างต้องไม่ไปซูมกล้องข้างหลัง
end

function Base:onMouseDown(x, y)
    if self:scrollGrab(x, y) then self.moveWithMouse = false; return true end
    self.moveWithMouse = (y < self.hdrH)
    return ISPanel.onMouseDown(self, x, y)
end

function Base:onMouseMove(dx, dy)
    if self.drag then self:scrollDragTo(self:getMouseY()); return true end
    return ISPanel.onMouseMove(self, dx, dy)
end

function Base:onMouseMoveOutside(dx, dy)
    if self.drag then self:scrollDragTo(self:getMouseY()); return true end
    if ISPanel.onMouseMoveOutside then return ISPanel.onMouseMoveOutside(self, dx, dy) end
end

function Base:onMouseUpOutside(x, y)
    if self.drag then self.drag = nil; return true end
    if ISPanel.onMouseUpOutside then return ISPanel.onMouseUpOutside(self, x, y) end
end

function Base:onMouseUp(x, y)
    if self.drag then self.drag = nil; return true end
    ISPanel.onMouseUp(self, x, y)
    self.moveWithMouse = false

    -- dropdown ถูกถามก่อนทุกอย่าง เพราะมันลอยทับทุกอย่าง
    if self.overlay then
        for i = #self.ozones, 1, -1 do
            local z = self.ozones[i]
            if T.hot(z, x, y) then z.fn(); return true end
        end
        -- คลิกนอก dropdown = ปิด แล้วจบ  ห้ามทะลุไปโดนปุ่มที่ถูกบังอยู่
        if not T.hot(self.overlay, x, y) then self:closeOverlay() end
        return true
    end

    for i = #self.zones, 1, -1 do
        local z = self.zones[i]
        if T.hot(z, x, y) then z.fn(); return true end
    end
    return true
end

function Base:closeOverlay() end

-- ------------------------------------------------------------------------------
-- ชิ้นส่วนร่วม
-- ------------------------------------------------------------------------------
function Base:drawShell(m)
    local W, H = self.width, self.height
    T.rrect(self, 0, 0, W, H, 12, C.bg)

    local hh = m.hdr
    self.hdrH = hh
    local lx = m.pad
    local ls = math.min(hh - 12, m.m + 2)
    local logo = T.texAt("media/textures/bank_logo.png")
    if logo then T.art(self, logo, lx, floor((hh - ls) / 2), ls, ls); lx = lx + ls + 8 end

    local cw = hh - 10
    local cr = { x = W - cw - 6, y = 5, w = cw, h = cw }
    local room = cr.x - 8 - lx
    local ty = floor((hh - m.m) / 2)
    local title = T.clip(self.title, room, F.m)
    T.text(self, title, lx, ty, C.text, F.m)
    local used = T.tw(title, F.m)
    if self.sub and room - used - 8 > 24 then
        T.text(self, T.clip(self.sub, room - used - 8, F.s), lx + used + 8, ty + (m.m - m.s), C.text3, F.s)
    end

    local hot = T.hot(cr, self.mx, self.my)
    if hot then T.rrect(self, cr.x, cr.y, cr.w, cr.h, 6, C.surf2) end
    local isz = math.max(10, m.s - 4)
    T.img(self, "ic_close", cr.x + floor((cr.w - isz) / 2), cr.y + floor((cr.h - isz) / 2), isz, isz,
          hot and C.text or C.text3)
    self:zone(cr, function() self:close() end)
    T.hr(self, 0, hh, W, C.line)
    return hh + 1
end

-- การ์ดยอดเงิน   o = { label, amount, pill, tone, right, compact }
function Base:hero(m, y, o)
    local x, w = m.pad, self.width - 2 * m.pad
    local fg = (o.tone == "good") and C.good or C.warn
    local amt = U.fmt(o.amount or 0)
    local pw, ph = T.pillW(o.pill, F.xs, true)

    if o.compact then
        local h = heroH(m, true)
        T.rrect(self, x, y, w, h, 10, C.hero)
        T.text(self, amt, x + 12, y + 7, C.white, F.l)
        if x + 12 + T.tw(amt, F.l) + 10 + pw <= x + w - 10 then
            T.pill(self, x + w - 10 - pw, y + floor((h - ph) / 2), o.pill, fg, C.bar, F.xs, true, 0.55)
        end
        return y + h
    end

    local h = heroH(m, false)
    T.rrect(self, x, y, w, h, 12, C.hero)
    -- วงกลมจาง ๆ ตกแต่ง  ตัดด้วย stencil ให้อยู่ในการ์ด
    self:setStencilRect(x, y, w, h)
    T.circle(self, x + w - floor(h * 0.95), y - floor(h * 0.6), floor(h * 1.35), C.white, 0.07)
    T.circle(self, x + w - floor(h * 0.4), y + floor(h * 0.4), floor(h * 0.95), C.white, 0.05)
    self:clearStencilRect()

    local cs = m.s + 4
    local coinTex = T.texAt("media/textures/coin_cash.png")
    T.text(self, T.clip(o.label, w - 28 - cs - 8, F.s), x + 14, y + 12, C.white, F.s, 0.75)
    if coinTex then T.art(self, coinTex, x + w - 14 - cs, y + 10, cs, cs) end
    T.text(self, T.clip(amt, w - 28, F.l), x + 14, y + 12 + m.s + 2, C.white, F.l)

    local py = y + 12 + m.s + 2 + m.l + 8
    T.pill(self, x + 14, py, o.pill, fg, C.bar, F.xs, true, 0.55)
    if o.right then
        local room = w - 28 - pw - 10
        T.textR(self, T.clip(o.right, room, F.xs), x + w - 14, py + 2, C.white, F.xs, 0.8)
    end
    return y + h
end

-- แท็บแบบแคปซูล   items = { { id, icon, label = {ยาว, สั้น, ""}, badge } }
function Base:tabs(m, y, items, cur, onPick)
    local x, w = m.pad, self.width - 2 * m.pad
    local h = m.tab
    T.rrect(self, x, y, w, h, 9, C.surf)
    local n  = #items
    local sw = floor((w - 4) / n)
    for i, it in ipairs(items) do
        local r   = { x = x + 2 + (i - 1) * sw, y = y + 2, w = sw, h = h - 4 }
        local on  = (it.id == cur)
        local hov = T.hot(r, self.mx, self.my)
        if on then T.rrect(self, r.x, r.y, r.w, r.h, 7, C.accentD)
        elseif hov then T.rrect(self, r.x, r.y, r.w, r.h, 7, C.surf2) end

        local isz   = math.max(10, m.s - 2)
        local badge = (it.badge and it.badge > 0) and tostring(it.badge) or nil
        local bw    = badge and (T.pillW(badge, F.xs)) or 0
        local room  = r.w - 12 - isz - 4 - (badge and (bw + 4) or 0)
        local lbl   = T.fit(it.label, room, F.s)
        local tw    = (lbl ~= "") and T.tw(lbl, F.s) or 0
        local total = isz + ((lbl ~= "") and (4 + tw) or 0) + (badge and (4 + bw) or 0)
        local cx    = r.x + floor((r.w - total) / 2)
        T.img(self, it.icon, cx, r.y + floor((r.h - isz) / 2), isz, isz, on and C.accent2 or C.text3)
        cx = cx + isz
        if lbl ~= "" then
            T.text(self, lbl, cx + 4, r.y + floor((r.h - m.s) / 2), on and C.text or C.text2, F.s)
            cx = cx + 4 + tw
        end
        if badge then
            local _, bh = T.pillW(badge, F.xs)
            T.pill(self, cx + 4, r.y + floor((r.h - bh) / 2), badge, C.white, C.bad, F.xs)
        end
        local id = it.id
        self:zone(r, function() onPick(id) end)
    end
    return y + h
end

-- ป้ายหัวข้อเล็ก ซ้าย + ข้อความขวา  ป้ายซ้ายถูกตัดก่อนเสมอ
function Base:label(m, y, left, right, rightColor, leftColor)
    local x, w = m.pad, self.width - 2 * m.pad
    local rw = 0
    if right and right ~= "" then
        right = T.clip(right, floor(w * 0.6), F.xs)
        rw = T.tw(right, F.xs)
        T.textR(self, right, x + w, y, rightColor or C.text3, F.xs)
    end
    T.text(self, T.clip(left, w - rw - 10, F.xs), x, y, leftColor or C.text3, F.xs)
    return y + labelH(m)
end

-- ช่องกรอก  icon = ชื่อไอคอน หรือ "coin"   tail = { icon, fn } ปุ่มเล็กชิดขวาในช่อง
function Base:field(m, box, x, y, w, icon, placeholder, suffix, tail)
    local h = m.field
    T.rrect(self, x, y, w, h, 8, C.surf2)
    local isz = math.max(10, m.s - 2)
    local ix  = x + 10
    if icon == "coin" then
        local ct = T.texAt("media/textures/coin_cash.png")
        if ct then T.art(self, ct, ix, y + floor((h - isz) / 2), isz, isz) end
        ix = ix + isz + 8
    elseif icon then
        T.img(self, icon, ix, y + floor((h - isz) / 2), isz, isz, C.text3)
        ix = ix + isz + 8
    end
    local right = x + w - 8
    if tail then
        local tr = { x = x + w - h, y = y, w = h, h = h }
        local hot = T.hot(tr, self.mx, self.my)
        if hot then T.rrect(self, tr.x + 3, tr.y + 3, tr.w - 6, tr.h - 6, 6, C.surf3) end
        T.img(self, tail.icon, tr.x + floor((tr.w - isz) / 2), tr.y + floor((tr.h - isz) / 2), isz, isz,
              hot and C.text or C.text3)
        self:zone(tr, tail.fn)
        right = tr.x - 2
    end
    if suffix then
        local sw = T.tw(suffix, F.xs)
        T.text(self, suffix, right - sw, y + floor((h - m.s) / 2), C.text3, F.xs)
        right = right - sw - 8
    end
    local bw = right - ix
    self:placeBox(box, ix, y, bw, h)
    local txt = box:getInternalText() or ""
    if placeholder and txt == "" then
        T.text(self, T.clip(placeholder, bw - 6, F.s), ix + 3, y + floor((h - m.s) / 2), C.text3, F.s)
    end
    return y + h
end

-- แถวปุ่มลัด   list = { { label, fn, disabled } }
function Base:chips(m, y, list)
    local x, w = m.pad, self.width - 2 * m.pad
    local n, g = #list, 6
    local cw = floor((w - g * (n - 1)) / n)
    for i, c in ipairs(list) do
        local r = T.button(self, x + (i - 1) * (cw + g), y, cw, m.chip, c.label,
                           c.disabled and "off" or "sec", nil, self.mx, self.my)
        if not c.disabled then self:zone(r, c.fn) end
    end
    return y + m.chip
end

-- กล่องสรุป   list = { { label, value, color, strong } }
function Base:rows(m, y, list)
    local x, w = m.pad, self.width - 2 * m.pad
    local h = rowsH(m, #list)
    T.rrect(self, x, y, w, h, 10, C.surf)
    local ry = y + 6
    for i, r in ipairs(list) do
        if r.strong and i > 1 then T.hr(self, x + 12, ry, w - 24, C.line) end
        local v  = tostring(r.value or "")
        local vw = T.tw(v, F.s)
        T.textR(self, v, x + w - 12, ry + 3, r.color or C.text, F.s)
        T.text(self, T.clip(r.label, w - 24 - vw - 10, F.s), x + 12, ry + 3,
               r.strong and C.text or C.text2, F.s)
        ry = ry + m.sumRow
    end
    return y + h
end

function Base:emptyState(m, x, y, w, h, icon, line1, line2)
    local isz = m.l + 8
    local total = isz + 8 + m.s + (line2 and (4 + m.s) or 0)
    local cy = y + floor((h - total) / 2)
    T.circle(self, x + floor((w - isz - 16) / 2), cy - 8, isz + 16, C.surf2)
    T.img(self, icon, x + floor((w - isz) / 2), cy, isz, isz, C.text3)
    cy = cy + isz + 16
    T.textC(self, T.clip(line1, w - 16, F.s), x + w / 2, cy, C.text2, F.s)
    if line2 then T.textC(self, T.clip(line2, w - 16, F.xs), x + w / 2, cy + m.s + 4, C.text3, F.xs) end
end

-- แถวเดินบัญชีหนึ่งแถว  ใช้ทั้งหน้าประวัติและกล่องรับโอน
local function txRow(self, m, e, me, rx, ry, rw, rh, first, highlight)
    local inc = isIncoming(e, me)
    local icon, fg, bg = kindLook(e.k, inc)
    if highlight then T.rrect(self, rx, ry + 1, rw, rh - 2, 8, C.accentD) end
    if not first and not highlight then T.hr(self, rx + 8, ry, rw - 16, C.line) end

    local d = math.min(rh - 12, m.m + 14)
    local cy = ry + floor((rh - d) / 2)
    T.circle(self, rx + 8, cy, d, bg)
    local isz = floor(d * 0.5)
    T.img(self, icon, rx + 8 + floor((d - isz) / 2), cy + floor((d - isz) / 2), isz, isz, fg)

    local head, sub = describe(e, me)
    local amtS = (inc and "+" or "-") .. U.fmt(e.a or 0)
    local when = ago(e.t)
    local aw   = T.tw(amtS, F.s)
    local tx   = rx + 8 + d + 10
    local top  = ry + floor((rh - m.s * 2 - 2) / 2)
    T.textR(self, amtS, rx + rw - 8, top, inc and C.good or C.text, F.s)
    T.text(self, T.clip(head, rx + rw - 8 - aw - 10 - tx, F.s), tx, top, C.text, F.s)

    local ww = (when ~= "") and T.tw(when, F.xs) or 0
    if when ~= "" then T.textR(self, when, rx + rw - 8, top + m.s + 2, C.text3, F.xs) end
    if sub ~= "" then
        T.text(self, T.clip(sub, rx + rw - 8 - ww - 10 - tx, F.xs), tx, top + m.s + 2, C.text3, F.xs)
    end
end

-- ==============================================================================
-- เคาน์เตอร์ธนาคาร   ฝาก / ถอน / ลายบัตร / ประวัติ
-- ==============================================================================
local Counter = Base:derive("Akacount_Counter")

local QUICK = { 100, 500, 1000 }

function Counter.needH(m, dense)
    local top = m.hdr + 1 + m.gap + heroH(m, dense >= 1) + m.gap + m.tab + m.gap
    local dep = labelH(m) + m.field + m.gap + m.chip + m.gap + rowsH(m, 3) + m.gap + m.btn
    local wdr = labelH(m) + m.field + m.gap + m.chip + m.gap + m.chip + m.gap + rowsH(m, 3) + m.gap + m.btn
    return top + math.max(dep, wdr) + m.pad
end

function Counter:createChildren()
    ISPanel.createChildren(self)
    self.amount = self:newBox(true)
    self.tab = self.tab or "dep"
    if self.asBundles == nil then self.asBundles = true end
end

function Counter:setTab(id)
    if self.tab ~= id then self.amount:setText("") end
    self.tab = id
end

-- ฝาก/ถอนเป็น "ใบ" เต็ม ๆ  เงินสดในเกมไม่มีเศษสตางค์
function Counter:notes()
    local n = tonumber(self.amount and self.amount:getInternalText() or "") or 0
    return math.max(0, floor(n))
end

-- ราคาลายบัตร (แอดมิน)  กรอกเป็นบาท ส่งเป็นสตางค์
function Counter:wantSub()
    return U.toSub(tonumber(self.amount and self.amount:getInternalText() or "") or 0)
end

function Counter:draw()
    local d = ACClient.data
    local m = metrics()
    local y = self:drawShell(m) + m.gap

    local cashS = U.fmtShort((d.cash or 0) * AC.SUBUNIT)
    y = self:hero(m, y, {
        label   = AC.L("ยอดในบัญชี", "Balance"),
        amount  = d.avail or 0,
        pill    = d.atCntr and AC.L("ที่เคาน์เตอร์", "At counter") or AC.L("นอกธนาคาร", "Away"),
        tone    = d.atCntr and "good" or "warn",
        right   = AC.L("เงินสด ", "Cash ") .. cashS,
        compact = self.dense >= 1,
    }) + m.gap

    y = self:tabs(m, y, {
        { id = "dep",  icon = "ic_deposit",  label = { "Deposit", "Dep", "" } },
        { id = "wdr",  icon = "ic_withdraw", label = { "Withdraw", "Draw", "" } },
        { id = "card", icon = "ic_card",     label = { "Card", "" } },
        { id = "log",  icon = "ic_history",  label = { "History", "Log", "" } },
    }, self.tab, function(id) self:setTab(id) end) + m.gap

    local bottom = self.height - m.pad
    if     self.tab == "wdr"  then self:drawWithdraw(m, y, bottom, d)
    elseif self.tab == "card" then self:drawSkins(m, y, bottom, d)
    elseif self.tab == "log"  then self:drawHistory(m, y, bottom, d)
    else                            self:drawDeposit(m, y, bottom, d) end
end

-- ------------------------------------------------------------------------------
-- ฝาก  (แบงก์ใบ + ปึก)
-- ------------------------------------------------------------------------------
function Counter:drawDeposit(m, y, bottom, d)
    local x, w = m.pad, self.width - 2 * m.pad
    local have = floor(d.cash or 0)
    local nB, nL = floor(d.cashB or 0), floor(d.cashL or have)
    local mix = (nB > 0) and (nB .. "x100 + " .. nL) or nil

    y = self:label(m, y, AC.L("เงินสดในตัว", "Cash on you"),
                   U.fmtShort(have * AC.SUBUNIT) .. (mix and ("  (" .. mix .. ")") or ""), C.text2)
    y = self:field(m, self.amount, x, y, w, "coin",
                   have > 0 and ("All: " .. U.fmtShort(have * AC.SUBUNIT)) or "0", "CASH") + m.gap

    local chips = {}
    for i = 1, #QUICK do
        local q = QUICK[i]
        chips[#chips + 1] = { label = U.fmtShort(q * AC.SUBUNIT), disabled = have < q,
                              fn = function() self.amount:setText(tostring(q)) end }
    end
    chips[#chips + 1] = { label = AC.L("ทั้งหมด", "All"), disabled = have <= 0,
                          fn = function() self.amount:setText(tostring(have)) end }
    y = self:chips(m, y, chips) + m.gap

    local n    = self:notes()
    local sub  = n * AC.SUBUNIT
    local pct  = d.atCntr and 0 or U.opt("DepositFeePct")
    local fee  = (sub > 0) and U.feeFor(sub, pct) or 0
    local minD = U.minSendFor(pct)
    self:rows(m, y, {
        { label = AC.L("ฝากเข้า", "Deposit"), value = U.fmt(sub) },
        { label = AC.L("ค่าธรรมเนียม", "Fee"), value = (fee > 0) and U.fmt(fee) or AC.L("ฟรี", "Free"),
          color = (fee > 0) and C.warn or C.good },
        { label = AC.L("ยอดหลังฝาก", "New balance"), value = U.fmt((d.avail or 0) + math.max(0, sub - fee)),
          strong = true },
    })

    local ok = have > 0 and n > 0 and n <= have and sub >= minD and sub > fee
    local label
    if have <= 0 then          label = AC.L("ไม่มีเงินสด", "No cash on you")
    elseif n <= 0 then         label = AC.L("ใส่จำนวน", "Enter amount")
    elseif n > have then       label = AC.L("มีแค่ ", "You have ") .. U.fmtShort(have * AC.SUBUNIT)
    elseif not ok then         label = AC.L("ขั้นต่ำ ", "At least ") .. U.fmt(minD)
    else                       label = { AC.L("ฝาก ", "Deposit ") .. U.fmtShort(sub), U.fmtShort(sub) } end

    local r = T.button(self, x, bottom - m.btn, w, m.btn, label, ok and "ok" or "off",
                       ok and "ic_deposit" or nil, self.mx, self.my)
    if ok then
        self:zone(r, function()
            ACClient.req(AC.CMD.DEPOSIT, { n = n })
            self.amount:setText("")
        end)
    end
end

-- ------------------------------------------------------------------------------
-- ถอน  (ที่เคาน์เตอร์เท่านั้น  ออกเป็นปึกได้)
-- ------------------------------------------------------------------------------
function Counter:drawWithdraw(m, y, bottom, d)
    local x, w = m.pad, self.width - 2 * m.pad
    local avail = d.avail or 0
    local maxN  = math.max(0, floor(avail / AC.SUBUNIT))

    y = self:label(m, y, AC.L("จำนวนที่จะถอน", "Amount"),
                   AC.L("ถอนได้ ", "Up to ") .. U.fmtShort(maxN * AC.SUBUNIT), C.text2)
    y = self:field(m, self.amount, x, y, w, "coin", "0", "CASH") + m.gap

    local chips = {}
    for i = 1, #QUICK do
        local q = QUICK[i]
        chips[#chips + 1] = { label = U.fmtShort(q * AC.SUBUNIT), disabled = maxN < q,
                              fn = function() self.amount:setText(tostring(q)) end }
    end
    chips[#chips + 1] = { label = AC.L("ทั้งหมด", "All"), disabled = maxN <= 0,
                          fn = function() self.amount:setText(tostring(maxN)) end }
    y = self:chips(m, y, chips) + m.gap

    -- สวิตช์ปึก  ถอน 5,000 เป็นใบ = ของ 5,000 ชิ้นในกระเป๋า  เป็นปึก = 50 ชิ้น
    local n = self:notes()
    local bOK = (d.bundleOK == true)
    local tr = { x = x, y = y, w = w, h = m.chip }
    local hot = bOK and T.hot(tr, self.mx, self.my)
    T.rrect(self, x, y, w, m.chip, 8, hot and C.surf2 or C.surf)
    local bsz = m.s
    local on = bOK and self.asBundles
    T.rrect(self, x + 10, y + floor((m.chip - bsz) / 2), bsz, bsz, 4, on and C.accent or C.surf3)
    if on then
        local ci = bsz - 4
        T.img(self, "ic_check", x + 12, y + floor((m.chip - ci) / 2), ci, ci, C.white)
    end
    local hint
    if not bOK then hint = AC.L("แบงก์ใบเท่านั้น", "Loose notes only")
    elseif on and n > 0 then
        hint = floor(n / AC.BUNDLE_SIZE) .. "x100 + " .. (n % AC.BUNDLE_SIZE)
    else hint = "" end
    local hw = (hint ~= "") and T.tw(hint, F.xs) or 0
    if hint ~= "" then T.textR(self, hint, x + w - 10, y + floor((m.chip - m.s) / 2), C.text3, F.xs) end
    T.text(self, T.clip(AC.L("รับเป็นปึก (ปึกละ 100)", "Take bundles of 100"), w - 30 - bsz - hw, F.s),
           x + 18 + bsz, y + floor((m.chip - m.s) / 2), bOK and C.text or C.text3, F.s)
    if bOK then self:zone(tr, function() self.asBundles = not self.asBundles end) end
    y = y + m.chip + m.gap

    local sub = n * AC.SUBUNIT
    local fee = U.feeFor(sub, U.opt("WithdrawFeePct"))
    self:rows(m, y, {
        { label = AC.L("ถอนออก", "Withdraw"), value = U.fmt(sub) },
        { label = AC.L("ค่าธรรมเนียม", "Fee"), value = (fee > 0) and U.fmt(fee) or AC.L("ฟรี", "Free"),
          color = (fee > 0) and C.warn or C.good },
        { label = AC.L("ยอดหลังถอน", "Balance after"), value = U.fmt(math.max(0, avail - sub - fee)),
          strong = true },
    })

    local ok = d.atCntr and n > 0 and (sub + fee) <= avail
    local label
    if not d.atCntr then          label = { AC.L("ต้องไปที่ตู้", "Go to a bank counter"), "Go to a counter" }
    elseif n <= 0 then            label = AC.L("ใส่จำนวน", "Enter amount")
    elseif (sub + fee) > avail then label = AC.L("เงินไม่พอ", "Not enough")
    else                          label = { AC.L("ถอน ", "Withdraw ") .. U.fmtShort(sub), U.fmtShort(sub) } end

    local r = T.button(self, x, bottom - m.btn, w, m.btn, label, ok and "pri" or "off",
                       ok and "ic_withdraw" or nil, self.mx, self.my)
    if ok then
        local useB = on
        self:zone(r, function()
            ACClient.req(AC.CMD.WITHDRAW, { sub = sub, bundles = useB })
            self.amount:setText("")
        end)
    end
end

-- ------------------------------------------------------------------------------
-- ประวัติ
-- ------------------------------------------------------------------------------
function Counter:drawHistory(m, y, bottom, d)
    local x, w = m.pad, self.width - 2 * m.pad
    local h = bottom - y
    local me = ACClient.myKey and ACClient.myKey() or nil
    local tail = d.tail or {}
    T.rrect(self, x, y, w, h, 10, C.surf)
    if #tail == 0 then
        self:emptyState(m, x, y, w, h, "ic_history", AC.L("ยังไม่มีรายการ", "No activity yet"), nil)
        return
    end
    self:scrollList("log", x + 4, y + 4, w - 8, h - 8, #tail, m.row, function(i, rx, ry, rw, rh)
        txRow(self, m, tail[i], me, rx, ry, rw, rh, i == 1 or ry == y + 4, false)
    end)
end

-- ------------------------------------------------------------------------------
-- ลายบัตร   (ตรรกะเดิมจาก v0.3.4  แค่จัดหน้าใหม่ + เลื่อนได้)
-- ------------------------------------------------------------------------------
local skinTexCache = {}
local function skinTex(name)
    if name == nil then return nil end
    if skinTexCache[name] ~= nil then return skinTexCache[name] or nil end
    local ok, t = pcall(getTexture, "media/textures/" .. name .. ".png")
    skinTexCache[name] = (ok and t) or false
    return (ok and t) or nil
end

function Counter:drawSkins(m, y, bottom, d)
    local x, w  = m.pad, self.width - 2 * m.pad
    local cur   = d.skin or AC.CARD_SKIN_DEFAULT
    local skins = d.skins or {}
    local admin = (d.admin == true)

    if admin then
        y = self:label(m, y, AC.L("แอดมิน  ราคาลาย", "ADMIN  design price"), "0 = free", C.text3, C.gold)
        y = self:field(m, self.amount, x, y, w, "coin", "Price", "CASH") + m.gap
    end

    -- ล่างขึ้นบน: ปุ่มขอบัตร -> บรรทัดกติกา -> ที่เหลือคือรายการลาย
    local fy = bottom
    if d.hasCard == false then
        fy = fy - m.btn
        local r = T.button(self, x, fy, w, m.btn,
                           d.atCntr and AC.L("ขอบัตร", "Get my card") or { "Get your card at a counter", "At a counter" },
                           d.atCntr and "ok" or "off", d.atCntr and "ic_card" or nil, self.mx, self.my)
        if d.atCntr then self:zone(r, function() ACClient.req(AC.CMD.GET_CARD, {}) end) end
        fy = fy - m.gap
    end
    fy = fy - m.s
    local note = d.atCntr and AC.L("แตะลายเพื่อเปลี่ยน  ออกบัตรใหม่ ใบเก่าถูกทำลาย",
                                   "Tap a design to switch - old card is replaced")
                          or  AC.L("เปลี่ยนลายได้ที่เคาน์เตอร์เท่านั้น", "Change designs at a bank counter")
    T.text(self, T.clip(note, w, F.xs), x, fy, d.atCntr and C.text2 or C.warn, F.xs)
    local listBottom = fy - m.gap

    if #skins == 0 then
        T.rrect(self, x, y, w, listBottom - y, 10, C.surf)
        self:emptyState(m, x, y, w, listBottom - y, "ic_card", AC.L("ยังโหลดลายไม่ขึ้น", "No designs loaded"), nil)
        return
    end

    local rowH = m.row + 6
    self:scrollList("skins", x, y, w, listBottom - y, #skins, rowH, function(i, rx, ry, rw, rh)
        local sk  = skins[i]
        local on  = (sk.id == cur)
        local ih  = rh - 6
        local card = { x = rx, y = ry, w = rw, h = ih }
        local hov = T.hot(card, self.mx, self.my)
        T.rrect(self, rx, ry, rw, ih, 10, on and C.accentD or (hov and C.surf2 or C.surf))

        local iw = ih - 12
        local t  = skinTex(sk.icon or sk.texture)
        T.rrect(self, rx + 6, ry + 6, iw, iw, 6, C.bar)
        if t then T.art(self, t, rx + 6, ry + 6, iw, iw) end

        local price = floor(tonumber(sk.price) or 0)
        local owned = (sk.owned == true) or price <= 0

        -- ปุ่มชิดขวา  วางก่อนเพื่อรู้ว่าชื่อเหลือที่เท่าไร
        local bh = m.s + 10
        local by = ry + floor((ih - bh) / 2)
        local bx = rx + rw - 8
        local btns = {}
        if not owned then
            local canBuy = (d.atCntr == true) and ((d.avail or 0) >= price)
            local bw = math.max(56, T.tw("Buy", F.m) + 24)
            bx = bx - bw
            btns[#btns + 1] = { r = T.button(self, bx, by, bw, bh, AC.L("ซื้อ", "Buy"), canBuy and "ok" or "off",
                                             nil, self.mx, self.my),
                                fn = canBuy and function() ACClient.req(AC.CMD.BUY_SKIN, { skin = sk.id }) end or nil }
            bx = bx - 6
        end
        if admin then
            local bw = math.max(56, T.tw("Price", F.m) + 24)
            bx = bx - bw
            btns[#btns + 1] = { r = T.button(self, bx, by, bw, bh, "Price", "sec", nil, self.mx, self.my),
                                fn = function()
                                    ACClient.req(AC.CMD.ADMIN_SKIN_PRICE, { skin = sk.id, price = self:wantSub() })
                                end }
            bx = bx - 6
        end

        local tx = rx + 6 + iw + 10
        local room = bx - tx - 4
        local top = ry + floor((ih - m.s * 2 - 2) / 2)
        T.text(self, T.clip(sk.name or sk.id, room, F.s), tx, top, on and C.text or C.text2, F.s)
        local note2, nc
        if on then        note2, nc = AC.L("ใช้อยู่", "In use"), C.gold
        elseif owned then note2, nc = AC.L("กดเพื่อใช้", "Tap to use"), C.good
        else              note2, nc = U.fmt(price), C.text end
        if admin and owned then note2 = note2 .. "  |  " .. ((price > 0) and U.fmt(price) or "free") end
        T.text(self, T.clip(note2, room, F.xs), tx, top + m.s + 2, nc, F.xs)

        if owned and not on then
            self:zone(card, function() ACClient.req(AC.CMD.SET_SKIN, { skin = sk.id }) end)
        end
        for _, b in ipairs(btns) do if b.fn then self:zone(b.r, b.fn) end end
    end)
end

-- ==============================================================================
-- บัตร   ส่งเงิน / กล่องรับโอน
-- ==============================================================================
local Card = Base:derive("Akacount_Card")

function Card.needH(m, dense)
    local top  = m.hdr + 1 + m.gap + heroH(m, dense >= 1) + m.gap + m.tab + m.gap
    local send = labelH(m) + m.field + m.gap
               + ((dense < 2) and (recentsH(m) + m.gap) or 0)
               + labelH(m) + m.field + m.gap + m.chip + m.gap + rowsH(m, 3) + m.gap + m.btn
    return top + send + m.pad
end

function Card:createChildren()
    ISPanel.createChildren(self)
    self.search = self:newBox(false)
    self.amount = self:newBox(true)
    self.toKey, self.toName = nil, nil
    self.ddOpen, self.lastQ = false, ""
    self.tab = self.tab or "send"
    -- Enter ในช่องค้นหา = เลือกชื่อบนสุด
    local me = self
    self.search.onCommandEntered = function() me:pickFirst() end
end

function Card:setTab(id)
    self.tab = id
    self.ddOpen = false
    if id == "inbox" then
        local d = ACClient.data
        -- ภาพนิ่งของ "อ่านถึงไหน" ตอนเปิดแท็บ  แถวใหม่ยังไฮไลต์อยู่ตลอดการดูรอบนี้
        -- ทั้งที่เซิร์ฟจดว่าอ่านแล้วไปตั้งแต่วินาทีแรก
        self.inboxSeen = tonumber(d.seenT) or 0
        ACClient.req(AC.CMD.MARK_SEEN, {})
        self.markAt = U.realTs()
    end
end

function Card:want()
    return U.toSub(tonumber(self.amount and self.amount:getInternalText() or "") or 0)
end

-- ผู้รับที่ตรงกับคำค้น  ขึ้นต้นด้วยคำค้นมาก่อน  มีอยู่ข้างในตามหลัง
function Card:filtered()
    local list = ACClient.holders or {}
    local q = tostring(self.lastQ or ""):lower()
    if q == "" then return list end
    local pre, mid = {}, {}
    for _, h in ipairs(list) do
        local n = tostring(h.name or h.key):lower()
        if n:sub(1, #q) == q then pre[#pre + 1] = h
        elseif contains(n, q) or contains(tostring(h.key), q) then mid[#mid + 1] = h end
    end
    for _, h in ipairs(mid) do pre[#pre + 1] = h end
    return pre
end

function Card:pick(key, name)
    self.toKey, self.toName = key, name
    self.ddOpen = false
    self.search:setText("")
    self.lastQ = ""
end

function Card:pickFirst()
    local rows = self:filtered()
    if rows[1] then self:pick(rows[1].key, rows[1].name) end
end

function Card:openPicker()
    self.ddOpen = true
    self.sc.dd = { off = 0 }
    ACClient.req(AC.CMD.WHO_ONLINE)       -- ขอรายชื่อสดทุกครั้งที่เปิด
end

function Card:closeOverlay() self.ddOpen = false end

-- คนที่เคยโอนหา/รับโอนด้วยล่าสุด  เฉพาะคนที่ยังอยู่ในรายชื่อคนมีบัตร
function Card:recents(d)
    local me = ACClient.myKey and ACClient.myKey() or nil
    local hk = {}
    for _, h in ipairs(ACClient.holders or {}) do hk[h.key] = h.name end
    local out, seen = {}, {}
    for _, e in ipairs(d.tail or {}) do
        if e.k == AC.KIND.TRANSFER then
            local other = (e.to == me) and e.f or e.to
            if other and not seen[other] and hk[other] then
                seen[other] = true
                out[#out + 1] = { key = other, name = hk[other] }
            end
        end
    end
    return out
end

function Card:maxSend(avail, pct)
    avail = floor(avail or 0)
    if avail <= 0 then return 0 end
    local best = 0
    local lo = floor(tonumber(U.opt("XferFeeMin")) or 0)
    local hi = floor(tonumber(U.opt("XferFeeMax")) or 0)
    local base = floor(avail * 10000 / (10000 + math.max(0, pct)))
    local cands = { avail - lo, avail - hi, base - 1, base, base + 1, avail }
    for _, c in ipairs(cands) do
        if c > best and c + U.feeFor(c, pct) <= avail then best = c end
    end
    return best
end

function Card:draw()
    local d = ACClient.data
    local m = metrics()
    local y = self:drawShell(m) + m.gap

    local pct = d.atCntr and 0 or U.opt("XferFeeCardPct")
    local hold = d.hold or 0
    y = self:hero(m, y, {
        label   = AC.L("ใช้ได้จริง", "Available"),
        amount  = d.avail or 0,
        pill    = d.atCntr and AC.L("ที่เคาน์เตอร์ โอนฟรี", "At counter - free")
                            or (AC.L("นอกธนาคาร ค่าโอน ", "Away - fee ") .. pctText(pct)),
        tone    = d.atCntr and "good" or "warn",
        right   = (hold > 0) and (AC.L("พักไว้ ", "Held ") .. U.fmt(hold)) or nil,
        compact = self.dense >= 1,
    }) + m.gap

    local _, unread = ACClient.inbox()
    y = self:tabs(m, y, {
        { id = "send",  icon = "ic_send", label = { "Send money", "Send", "" } },
        { id = "inbox", icon = "ic_bell", label = { "Inbox", "" }, badge = unread },
    }, self.tab, function(id) self:setTab(id) end) + m.gap

    local bottom = self.height - m.pad
    if self.tab == "inbox" then
        self:drawInbox(m, y, bottom, d, unread)
    else
        self:drawSend(m, y, bottom, d, pct)
    end
end

function Card:drawSend(m, y, bottom, d, pct)
    local x, w = m.pad, self.width - 2 * m.pad
    local holders = ACClient.holders or {}

    -- คำค้นเปลี่ยน = เปิดรายชื่อ + กลับไปแถวบนสุด  (อ่านจากช่องทุกเฟรม ไม่ต้องพึ่ง event ของช่องกรอก)
    local q = self.search:getInternalText() or ""
    if q ~= self.lastQ then
        self.lastQ = q
        self.sc.dd = { off = 0 }
        if q ~= "" and not self.toKey then self.ddOpen = true end
    end

    y = self:label(m, y, AC.L("โอนให้", "To"),
                   (#holders > 0) and (#holders .. AC.L(" คนมีบัตร", " with a card")) or AC.L("ยังไม่มีใครมีบัตร", "Nobody has a card yet"))
    local fy = y
    if self.toKey then
        -- ผู้รับที่เลือกแล้ว  แตะที่ไหนก็ได้บนแถบ = เปลี่ยนคน
        local r = { x = x, y = y, w = w, h = m.field }
        local hot = T.hot(r, self.mx, self.my)
        T.rrect(self, x, y, w, m.field, 8, hot and C.surf3 or C.accentD)
        local ad = m.field - 10
        T.avatar(self, x + 6, y + 5, ad, self.toName, self.toKey)
        local isz = math.max(10, m.s - 4)
        T.img(self, "ic_close", x + w - 10 - isz, y + floor((m.field - isz) / 2), isz, isz, hot and C.text or C.text2)
        T.text(self, T.clip(self.toName, w - ad - 30 - isz, F.s), x + 6 + ad + 8,
               y + floor((m.field - m.s) / 2), C.text, F.s)
        self:zone(r, function()
            self.toKey, self.toName = nil, nil
            self:openPicker()
        end)
    else
        self:field(m, self.search, x, y, w, "ic_search", AC.L("พิมพ์ชื่อเพื่อค้นหา", "Type a name to search"), nil,
                   { icon = "ic_chev", fn = function()
                        if self.ddOpen then self.ddOpen = false else self:openPicker() end
                     end })
    end
    y = fy + m.field
    local anchor = { x = x, y = y + 3, w = w }
    y = y + m.gap

    -- คนที่โอนด้วยบ่อย  แตะเดียวเลือกเลย ไม่ต้องค้น
    if self.dense < 2 then
        local rec = self:recents(d)
        local ad  = m.m + 14
        local cellW = math.max(ad + 16, T.tw("Wwwwww", F.xs))
        local fits = math.max(1, floor((w + 8) / (cellW + 8)))
        if #rec == 0 then
            T.rrect(self, x, y, w, recentsH(m), 10, C.surf)
            T.textC(self, T.clip(AC.L("คนที่โอนหาล่าสุดจะขึ้นตรงนี้", "People you pay show up here"), w - 16, F.xs),
                    x + w / 2, y + floor((recentsH(m) - m.s) / 2), C.text3, F.xs)
        else
            local n = math.min(#rec, fits)
            for i = 1, n do
                local p  = rec[i]
                local cx = x + (i - 1) * (cellW + 8)
                local cell = { x = cx, y = y, w = cellW, h = recentsH(m) }
                local hot = T.hot(cell, self.mx, self.my)
                if hot then T.rrect(self, cx, y, cellW, recentsH(m), 8, C.surf) end
                T.avatar(self, cx + floor((cellW - ad + 4) / 2), y + 2, ad - 4, p.name, p.key, p.key == self.toKey)
                T.textC(self, T.clip(p.name, cellW - 4, F.xs), cx + cellW / 2, y + ad + 2,
                        (p.key == self.toKey) and C.text or C.text2, F.xs)
                local key, name = p.key, p.name
                self:zone(cell, function() self:pick(key, name) end)
            end
        end
        y = y + recentsH(m) + m.gap
    end

    local amt  = self:want()
    local fee  = (amt > 0) and U.feeFor(amt, pct) or 0      -- ยังไม่กรอก = ยังไม่มีค่าธรรมเนียมให้โชว์
    local minA = U.minSendFor(pct)
    local tooSmall = (amt > 0 and amt < minA)
    y = self:label(m, y, AC.L("จำนวน", "Amount"), AC.L("ขั้นต่ำ ", "Min ") .. U.fmt(minA),
                   tooSmall and C.bad or C.text3)
    y = self:field(m, self.amount, x, y, w, "coin", "0.00", "CASH") + m.gap

    local avail = d.avail or 0
    local maxA = self:maxSend(avail, pct)
    y = self:chips(m, y, {
        { label = "100",   disabled = maxA < 10000,  fn = function() self.amount:setText("100") end },
        { label = "500",   disabled = maxA < 50000,  fn = function() self.amount:setText("500") end },
        { label = { "1,000", "1k" }, disabled = maxA < 100000, fn = function() self.amount:setText("1000") end },
        { label = AC.L("สูงสุด", "Max"), disabled = maxA < minA, fn = function() self.amount:setText(plainNum(maxA)) end },
    }) + m.gap

    self:rows(m, y, {
        { label = AC.L("ผู้รับได้", "They get"), value = U.fmt(amt) },
        { label = AC.L("ค่าธรรมเนียม", "Fee"),
          value = (amt <= 0) and "-" or ((fee > 0) and U.fmt(fee) or AC.L("ฟรี", "Free")),
          color = (amt <= 0) and C.text3 or ((fee > 0) and C.warn or C.good) },
        { label = AC.L("คุณจ่ายทั้งหมด", "You pay"), value = U.fmt(amt + fee), strong = true },
    })

    -- ปุ่มล่าง  ปุ่มที่กดไม่ได้ต้องบอกเหตุผลบนตัวเอง
    local by   = bottom - m.btn
    local half = floor((w - 8) / 2)
    local cb = T.button(self, x, by, half, m.btn, AC.L("ยกเลิก", "Cancel"), "sec", nil, self.mx, self.my)
    self:zone(cb, function() self:close() end)

    local canSend = (self.toKey ~= nil) and amt >= minA and amt > fee and (amt + fee) <= avail and not d.locked
    local label
    if not self.toKey then                     label = { AC.L("เลือกผู้รับ", "Pick someone"), "Pick" }
    elseif amt <= 0 then                       label = { AC.L("ใส่จำนวน", "Enter amount"), "Amount?" }
    elseif amt < minA or amt <= fee then       label = { AC.L("ขั้นต่ำ ", "Min ") .. U.fmt(minA), "Too small" }
    elseif d.locked then                       label = { AC.L("บัญชีติดลบ", "Overdrawn"), "Locked" }
    elseif (amt + fee) > avail then            label = { AC.L("เงินไม่พอ", "Not enough"), "Low" }
    else                                       label = { AC.L("โอน ", "Send ") .. U.fmt(amt), "Send" } end
    local sb = T.button(self, x + half + 8, by, w - half - 8, m.btn, label, canSend and "pri" or "off",
                        canSend and "ic_send" or nil, self.mx, self.my)
    if canSend then
        self:zone(sb, function()
            ACClient.req(AC.CMD.TRANSFER, {
                toKey = self.toKey,       -- ของจริงคือคีย์  ห้ามให้เซิร์ฟไปเดาจากชื่อที่โชว์
                to    = self.toName,
                sub   = amt,              -- เงินบนสายเป็นสตางค์เสมอ
            })
            self:close()
        end)
    end

    -- รายชื่อผู้รับ  วาดท้ายสุด = ชั้นบนสุด   ความสูงถูกจำกัดไม่ให้ลงไปทับปุ่มล่าง
    if self.ddOpen and not self.toKey then self:drawPicker(m, anchor, by - m.gap) end
end

function Card:drawPicker(m, a, maxBottom)
    local rows = self:filtered()
    local rh   = m.row1
    local room = math.max(rh * 2, maxBottom - a.y - 8)
    local fitN = math.max(2, floor(room / rh))
    local shown = math.min(#rows, fitN)
    local h = ((shown > 0) and (shown * rh) or (m.s * 2 + 20)) + 8
    -- รายชื่อยาวกว่าที่ว่าง -> กินที่จนถึงปุ่มล่างเต็ม ๆ  ไม่ให้แถวสรุปยอดโผล่ครึ่งบรรทัดใต้รายชื่อ
    if #rows > fitN then h = math.max(h, maxBottom - a.y) end
    local r = { x = a.x, y = a.y, w = a.w, h = h }
    self.overlay = r

    T.rrect(self, r.x, r.y + 4, r.w, r.h, 10, C.bar, 0.7)       -- เงา
    T.rrect(self, r.x, r.y, r.w, r.h, 10, C.surf3)

    if #rows == 0 then
        local l1 = (#(ACClient.holders or {}) == 0) and AC.L("ยังไม่มีใครไปรับบัตรเลย", "Nobody else has a card yet")
                   or (AC.L("ไม่พบ ", "No match for ") .. "'" .. tostring(self.lastQ) .. "'")
        local l2 = AC.L("บัตรรับได้ที่เคาน์เตอร์ธนาคาร", "Cards are handed out at the bank counter")
        T.textC(self, T.clip(l1, r.w - 16, F.s), r.x + r.w / 2, r.y + 8, C.text, F.s)
        T.textC(self, T.clip(l2, r.w - 16, F.xs), r.x + r.w / 2, r.y + 12 + m.s, C.text2, F.xs)
        return
    end

    self:scrollList("dd", r.x + 4, r.y + 4, r.w - 8, r.h - 8, #rows, rh, function(i, rx, ry, rw, rhh)
        local row = rows[i]
        local rr  = { x = rx, y = ry, w = rw, h = rhh }
        local hov = T.hot(rr, self.mx, self.my)
        if hov then T.rrect(self, rx, ry, rw, rhh, 7, C.accentD) end
        local ad = rhh - 8
        T.avatar(self, rx + 6, ry + 4, ad, row.name, row.key)
        T.text(self, T.clip(row.name, rw - ad - 24, F.s), rx + 6 + ad + 10, ry + floor((rhh - m.s) / 2),
               hov and C.text or C.text2, F.s)
        local key, name = row.key, row.name
        self:zone(rr, function() self:pick(key, name) end, 1)
    end, 1)
end

-- ------------------------------------------------------------------------------
-- กล่องรับโอน
-- ------------------------------------------------------------------------------
function Card:drawInbox(m, y, bottom, d, unread)
    local x, w = m.pad, self.width - 2 * m.pad
    local rows = ACClient.inbox()
    local snap = self.inboxSeen or tonumber(d.seenT) or 0
    local me = ACClient.myKey and ACClient.myKey() or nil

    -- มีเงินเข้าระหว่างที่เปิดดูอยู่ -> จดว่าอ่านแล้ว  (ถี่สุดทุก 3 วินาที)
    if unread and unread > 0 and (U.realTs() - (self.markAt or 0)) >= 3 then
        self.markAt = U.realTs()
        ACClient.req(AC.CMD.MARK_SEEN, {})
    end

    local h = bottom - y
    T.rrect(self, x, y, w, h, 10, C.surf)
    if #rows == 0 then
        self:emptyState(m, x, y, w, h, "ic_bell", AC.L("ยังไม่มีใครโอนมา", "No transfers received yet"),
                        AC.L("เงินเข้าจะขึ้นเหนือหัวด้วย", "You also get a note over your head"))
        return
    end
    self:scrollList("inbox", x + 4, y + 4, w - 8, h - 8, #rows, m.row, function(i, rx, ry, rw, rh)
        local row = rows[i]
        txRow(self, m, row.e, me, rx, ry, rw, rh, ry == y + 4, (tonumber(row.e.t) or 0) > snap)
    end)
end

-- ==============================================================================
-- ตัวเปิด
-- ==============================================================================
local function sizeFor(cls)
    local m = metrics()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local W = math.min(math.max(340, math.min(440, floor(m.s * 24))), sw - 20)
    local H, dense = 0, 0
    for lvl = 0, 2 do
        dense = lvl
        H = cls.needH(m, lvl)
        if H <= sh - 40 then break end
    end
    return W, math.min(H, sh - 40), dense
end

local function spawn(cls, key, title, sub, tab)
    local win = ACWindows.open[key]
    if win then
        if tab then win:setTab(tab); return win end
        win:close()
        return nil
    end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h, dense = sizeFor(cls)
    win = cls:new(floor(sw / 2 - w / 2), floor(sh / 2 - h / 2), w, h, title, sub)
    win.acKey = key
    win.dense = dense
    win:initialise(); win:instantiate()
    if tab then win:setTab(tab) end
    win:addToUIManager()
    ACWindows.open[key] = win
    if ACClient and ACClient.sync then ACClient.sync() end
    return win
end

function ACWindows.openCounter(tab)
    return spawn(Counter, "counter", "AKACOUNT", AC.L("เคาน์เตอร์ธนาคาร", "Bank"), tab)
end

-- tab = "send" | "inbox"
function ACWindows.openCard(tab)
    if ACClient and ACClient.req then ACClient.req(AC.CMD.WHO_ONLINE) end
    return spawn(Card, "card", "AKACOUNT", AC.L("บัตร", "Card"), tab)
end

function ACWindows.refreshAll()
    for _, win in pairs(ACWindows.open) do
        if win and win.setVisible then win:setVisible(true) end
    end
end

-- ให้ harness เข้าถึงคลาสได้  (ไม่มีผลในเกม)
ACWindows._cls = { Counter = Counter, Card = Card, metrics = metrics }

return ACWindows
