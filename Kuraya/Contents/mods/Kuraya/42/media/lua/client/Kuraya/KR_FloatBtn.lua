-- ==============================================================================
-- Kuraya — client/Kuraya/KR_FloatBtn.lua
-- ปุ่มลอยข้างจอ  ลากได้ ล็อกได้ ตำแหน่งเก็บบนเซิร์ฟเวอร์
-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- ==============================================================================
--
-- ทำไมเก็บตำแหน่งไว้บนเซิร์ฟเวอร์ ไม่ใช่ในไฟล์เครื่องผู้เล่น
--   ผู้เล่นส่วนใหญ่เข้าเซิร์ฟจากหลายเครื่อง และไฟล์ตั้งค่าฝั่งไคลเอนต์หายง่ายมาก
--   ย้ายปุ่มครั้งเดียวแล้วต้องจำได้ตลอด ไม่ว่าเข้าจากเครื่องไหน
--
-- ต่างจากเมนู ESC ตรงที่เห็นตลอดเวลา ไม่ต้องจำว่าเมนูอยู่ตรงไหน
-- แต่ต้องลากออกจากทางได้ ไม่งั้นมันจะไปบังของสำคัญของบางคน
-- ==============================================================================
require("Kuraya/KR_Const")
-- ต้อง require ตรง ๆ  ห้ามหวังพึ่งลำดับโหลดตามตัวอักษร
-- ถ้า KRShopUI ยังไม่มีตอนคนกดปุ่ม ปุ่มจะเงียบสนิทและหาสาเหตุยากมาก
-- ทิศทางนี้ไม่วน  KR_UI_Shop ไม่เคย require ไฟล์นี้กลับ
require("Kuraya/KR_UI_Shop")

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
if KR.__loaded_floatbtn then return end
KR.__loaded_floatbtn = true

print("[Kuraya] KR_FloatBtn  v" .. KR.VERSION)

KRFloat = ISPanel:derive("KRFloat")

-- ขนาดปุ่มลอย  เจ้าของเซิร์ฟขอ 80
--
-- ของเดิม 48 ซึ่งเล็กเกินไปสำหรับป้าย "HF SHOP" ที่มีตัวหนังสืออยู่ในรูป
-- ตัวหนังสือที่ย่อลงเหลือ 48px อ่านไม่ออก แล้วปุ่มก็เหลือแค่ "ก้อนสีส้ม"
-- ที่ไม่ได้บอกอะไรกับคนที่เพิ่งเข้าเซิร์ฟวันแรกเลย
local SIZE     = 80
local MARGIN   = 12
local TEX_PATH = "media/textures/Kuraya/shop_button.png"

function KRFloat:new(x, y)
    local o = ISPanel.new(self, x, y, SIZE, SIZE)
    o.background      = false
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor     = { r = 0, g = 0, b = 0, a = 0 }
    o.isLocked = false
    o.isClick  = false
    o.dragging = false
    return o
end

function KRFloat:initialise()
    ISPanel.initialise(self)
    -- หา texture แบบเผื่อไว้สองทาง  ถ้าไม่เจอเลยจะวาดกล่องสำรองใน prerender
    self.tex = getTexture(TEX_PATH) or getTexture("Item_KuroyaShopBtn")
end

-- ------------------------------------------------------------------------------
-- ตำแหน่ง
-- ------------------------------------------------------------------------------
function KRFloat:clampToBounds()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    if sw <= 0 or sh <= 0 then return end

    local cx = math.max(0, math.min(self.x, sw - self.width))
    local cy = math.max(0, math.min(self.y, sh - self.height))
    if cx ~= self.x then self:setX(cx) end
    if cy ~= self.y then self:setY(cy) end
end

function KRFloat:save()
    sendClientCommand(KR.MODULE, KR.CMD.SAVE_BTN, {
        x = math.floor(self.x), y = math.floor(self.y), locked = self.isLocked,
    })
end

function KRFloat:applyConfig(cfg)
    if not cfg then return end
    if tonumber(cfg.x) and tonumber(cfg.y) then
        self:setX(math.floor(tonumber(cfg.x)))
        self:setY(math.floor(tonumber(cfg.y)))
    end
    self.isLocked = cfg.locked and true or false
    self:clampToBounds()
end

function KRFloat:defaultPos()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    -- ขวากลางจอ  ห่างขอบเท่ากับ MARGIN  ตรงนั้นแทบไม่มี HUD ของวนิลลาอยู่
    return sw - SIZE - MARGIN, math.floor(sh * 0.5) - SIZE
end

function KRFloat:resetPos()
    local x, y = self:defaultPos()
    self:setX(x); self:setY(y)
    self.isLocked = false
    self:save()
end

-- ------------------------------------------------------------------------------
-- วาด
-- ------------------------------------------------------------------------------
function KRFloat:prerender()
    if self.tex then
        self:drawTextureScaled(self.tex, 0, 0, self.width, self.height, 1, 1, 1, 1)
    else
        -- texture หาย  ยังต้องกดได้อยู่ ห้ามกลายเป็นปุ่มล่องหน
        self:drawRect(0, 0, self.width, self.height, 0.95, 0.06, 0.06, 0.10)
        self:drawRectBorder(0, 0, self.width, self.height, 1, 0.23, 0.23, 0.36)
        self:drawTextCentre("SHOP", self.width / 2, self.height / 2 - 6, 0.80, 0.78, 0.94, 1, UIFont.Small)
    end

    if self.isHovered then
        if self.isLocked then
            self:drawRect(0, 0, self.width, self.height, 0.16, 0.88, 0.30, 0.30)
        else
            self:drawRect(0, 0, self.width, self.height, 0.14, 1, 1, 1)
        end
    end

    -- จุดแดงเล็ก ๆ บอกว่ามีของลดราคาอยู่  ไม่ต้องเปิดร้านก็รู้
    if KRClient and KRClient.saleCount and KRClient.saleCount > 0 then
        self:drawRect(self.width - 9, 3, 6, 6, 1, 0.88, 0.36, 0.36)
    end
end

-- ------------------------------------------------------------------------------
-- เมาส์
--   แยก "ลาก" กับ "คลิก" ด้วย isClick  ถ้าขยับระหว่างกดถือว่าลาก ไม่ใช่คลิก
--   ไม่งั้นทุกครั้งที่ลากเสร็จร้านจะเด้งขึ้นมาด้วย ซึ่งน่ารำคาญมาก
-- ------------------------------------------------------------------------------
function KRFloat:onMouseDown(x, y)
    self.isClick = true
    if not self.isLocked then self.dragging = true end
    return true
end

local function drag(self, dx, dy)
    if self.dragging and not self.isLocked then
        self.isClick = false
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
    return true
end
function KRFloat:onMouseMove(dx, dy)        return drag(self, dx, dy) end
function KRFloat:onMouseMoveOutside(dx, dy) return drag(self, dx, dy) end

-- ปล่อยเมาส์
--
-- ลำดับตรงนี้เคยทำให้เกิดบั๊กที่หนักที่สุดตัวหนึ่ง  ต้องอ่านก่อนแก้
--
--   ของเดิม:  เรียก toggle() ก่อน  แล้วค่อย self.isClick = false ท้ายฟังก์ชัน
--   ผลคือถ้า toggle() โยน error (ซึ่งเกิดจริงจาก KRAccount:dock)
--   บรรทัด isClick = false ไม่เคยทำงาน  ธงค้างเป็น true ตลอดเซสชัน
--   จากนั้น "คลิกซ้ายที่ไหนก็ได้บนจอ" จะเปิด/ปิดร้านทุกครั้ง
--
--   บทเรียน: ล้าง state ก่อนเรียกอะไรที่พังได้เสมอ
--   และห่อ pcall ไว้ด้วย  บั๊กของหน้าต่างร้านต้องไม่ทำให้ปุ่มลอยใช้ไม่ได้
local function release(self, wasInside)
    if self.dragging then
        self.dragging = false
        self:clampToBounds()
        self:save()
    end

    local click = self.isClick
    self.isClick = false          -- ล้างก่อนเสมอ  ห้ามอยู่ท้ายฟังก์ชัน

    -- ปล่อยเมาส์นอกปุ่มไม่นับเป็นคลิก  ตั้งใจกดแล้วเปลี่ยนใจลากออกไปปล่อย
    if not click or not wasInside then return true end

    if not (KRShopUI and KRShopUI.toggle) then
        -- ถ้ามาถึงตรงนี้แปลว่า KR_UI_Shop โหลดไม่ผ่าน  ต้องบอกให้รู้ ไม่ใช่เงียบ
        print("[Kuraya] !! KRShopUI missing - KR_UI_Shop.lua failed to load")
        return true
    end

    local ok, err = pcall(KRShopUI.toggle)
    if not ok then
        print("[Kuraya] !! shop window failed to open: " .. tostring(err))
    end
    return true
end
function KRFloat:onMouseUp(x, y)        return release(self, true)  end
function KRFloat:onMouseUpOutside(x, y) return release(self, false) end

function KRFloat:onRightMouseUp(x, y)
    local ctx = ISContextMenu.get(0, getMouseX(), getMouseY())
    if self.isLocked then
        ctx:addOption(getText("IGUI_Kuraya_Unlock"), self, KRFloat.toggleLock)
    else
        ctx:addOption(getText("IGUI_Kuraya_Lock"), self, KRFloat.toggleLock)
    end
    ctx:addOption(getText("IGUI_Kuraya_ResetPos"), self, KRFloat.resetPos)
    return true
end

function KRFloat:toggleLock()
    self.isLocked = not self.isLocked
    self:save()
end

-- ------------------------------------------------------------------------------
-- ติดตั้ง
-- ------------------------------------------------------------------------------
local function build(playerIndex, player)
    if playerIndex ~= 0 or not player then return end

    if KRFloat.instance then
        KRFloat.instance:removeFromUIManager()
        KRFloat.instance = nil
    end

    local btn = KRFloat:new(0, 0)
    local x, y = btn:defaultPos()
    btn:setX(x); btn:setY(y)
    btn:initialise()
    btn:addToUIManager()
    btn:clampToBounds()
    KRFloat.instance = btn

    -- ถ้าเคยได้ config มาแล้วในเซสชันนี้ ใช้เลยไม่ต้องรอ
    if KRFloat.cached then btn:applyConfig(KRFloat.cached) end

    -- ขอตำแหน่งจากเซิร์ฟเวอร์  หน่วงไว้ก่อนเพราะตอน OnCreatePlayer
    -- การเชื่อมต่อยังไม่พร้อมรับคำสั่งเสมอไป
    local ticks = 0
    local function ask()
        ticks = ticks + 1
        if ticks >= 90 then
            Events.OnTickEvenPaused.Remove(ask)
            sendClientCommand(KR.MODULE, KR.CMD.REQ_BTN, {})
        end
    end
    Events.OnTickEvenPaused.Add(ask)
end

local function onServerCommand(module, command, args)
    if module ~= KR.MODULE then return end
    if command ~= KR.CMD.SYNC_BTN then return end
    KRFloat.cached = args
    if KRFloat.instance then KRFloat.instance:applyConfig(args) end
end

local function onResolutionChange()
    -- ย่อจอแล้วปุ่มต้องไม่หลุดออกนอกจอ  แต่ห้ามเซฟทับตำแหน่งที่ผู้เล่นตั้งใจตั้งไว้
    if KRFloat.instance then KRFloat.instance:clampToBounds() end
end

Events.OnCreatePlayer.Add(build)
Events.OnServerCommand.Add(onServerCommand)
Events.OnResolutionChange.Add(onResolutionChange)
