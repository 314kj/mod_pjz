-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- AkaRepairKit - context menu + timed action + การซ่อมจริง
--
-- ทั้ง action และเมนูอยู่ไฟล์เดียวกันโดยตั้งใจ
-- PZ โหลด lua เรียงตามชื่อไฟล์ การแยกไฟล์ที่พึ่งพากันคือทางไปสู่ "คลาสครึ่งใบ"
-- (บทเรียน KR_UI_Pages / KR_Auction)

require "AkaRepairKit/ARK_Shared"
require "TimedActions/ISBaseTimedAction"

local MAX_ROWS = 25   -- กันเมนูยาวเกินจอ

--------------------------------------------------------------------------
-- Timed action
--------------------------------------------------------------------------
ARKFixAction = ISBaseTimedAction:derive("ARKFixAction")

function ARKFixAction:isValid()
    local inv = self.character:getInventory()
    if ARK.sc(inv, "contains", self.card) ~= true then return false end
    -- อาวุธอาจอยู่ในกระเป๋าย่อย - contains() ธรรมดาไม่เห็น
    if ARK.sc(inv, "contains", self.weapon) ~= true
       and ARK.sc(inv, "containsRecursive", self.weapon) ~= true then
        return false
    end
    return ARK.canRepair(self.weapon)
end

function ARKFixAction:waitToStart()
    return false
end

function ARKFixAction:start()
    pcall(function() self:setActionAnim("Craft") end)
end

function ARKFixAction:stop()
    ISBaseTimedAction.stop(self)
end

function ARKFixAction:perform()
    ARK.requestRepair(self.character, self.card, self.weapon, self.tier)
    ISBaseTimedAction.perform(self)
end

function ARKFixAction:new(character, card, weapon, tier)
    local o = ISBaseTimedAction.new(self, character)
    o.character  = character
    o.card       = card
    o.weapon     = weapon
    o.tier       = tier
    local pct    = ARK.pct(tier)
    o.pct        = pct
    o.stopOnWalk = true
    o.stopOnRun  = true
    o.maxTime    = 50 + math.floor(pct * 2)
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

--------------------------------------------------------------------------
-- กินบัตร
-- B42 เปลี่ยนลายเซ็นเป็น removeItem(item, playerNum:int) ไม่ใช่ตัว player
--   "expected argument of type int, got IsoPlayer at ISRemoveItemTool.lua:287"
-- ลอง int ก่อน แล้ว player object (แบบ B41) แล้วค่อย Remove ตรง ๆ
-- และ "เช็คว่าหายจริง" ทุกขั้น ไม่ใช่แค่ไม่โยน error
--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- ส่งคำสั่งไปเซิร์ฟ
--
-- v1.1.0 ใช้ `if isClient() then` เป็นด่าน แล้ว **ไม่เคยผ่านเลย** -
-- ในโหมด co-op ที่โฮสต์เอง isClient() คืน false ทั้งที่มีเซิร์ฟรันอยู่จริง
-- ล็อกจึงไม่มีบรรทัด "server:" สักบรรทัด และค่าก็ยังเด้งกลับเหมือนเดิม
--
-- เลิกเดาว่าโหมดไหน: ส่งทุกครั้ง ไม่มีเซิร์ฟก็ไม่มีใครรับ ไม่มีผลเสีย
--------------------------------------------------------------------------
local netWarned = false
local function tellServer(player, command, args)
    if pcall(function() sendClientCommand(player, "AkaRepairKit", command, args) end) then return true end
    if pcall(function() sendClientCommand("AkaRepairKit", command, args) end) then return true end
    if not netWarned then
        netWarned = true
        print("[AkaRepairKit] !! sendClientCommand unavailable - server copy will not be updated")
    end
    return false
end

local function consume(player, item)
    local inv = player:getInventory()
    local function gone() return ARK.sc(inv, "contains", item) ~= true end
    if gone() then return true end

    if ISRemoveItemTool and ISRemoveItemTool.removeItem then
        local pn = ARK.sc(player, "getPlayerNum")
        if type(pn) == "number" then
            pcall(function() ISRemoveItemTool.removeItem(item, pn) end)
            if gone() then return true end
        end
        pcall(function() ISRemoveItemTool.removeItem(item, player) end)
        if gone() then return true end
    end

    pcall(function() inv:Remove(item) end)
    if gone() then return true end

    print("[AkaRepairKit] !! could not consume " .. tostring(ARK.sc(item, "getFullType")))
    return false
end

--------------------------------------------------------------------------
-- การซ่อม  (v2.0.0 - ไคลเอนต์ไม่แก้ค่าเองอีกแล้ว)
--
-- ทำไมถึงรื้อ:
-- ของในกระเป๋าเป็นของเซิร์ฟ การที่ไคลเอนต์เขียน condition เองแล้วค่อยบอก
-- ทีหลัง ทำให้สำเนาสองฝั่งไม่ตรงกันชั่วขณะ - ซึ่งเป็นรูปทรงที่ anti-cheat
-- ของ PZ เฝ้าดู (หมวดกระเป๋า/ไอเทม type 12/13) และเป็นที่มาของ
-- "Malformed packet detected" ที่เตะคนออกจากเซิร์ฟ
--
-- ของในเกมเองก็ไม่ได้ทำแบบนั้น มันแก้ที่เจ้าของของ แล้วประกาศด้วย
-- syncItemFields()  v2.0.0 ทำตามนั้นเป๊ะ
--
--   ไคลเอนต์  ->  "ขอซ่อม ด้วยบัตรใบนี้"  (ส่ง id 2 ตัวกับ tier เท่านั้น)
--   เซิร์ฟ    ->  อ่าน tier จากตัวบัตรเอง  คำนวณเอง  เขียนเอง  ลบบัตรเอง
--             ->  syncItemFields()  แล้วตอบกลับ
--   ไคลเอนต์  ->  รีเฟรชหน้าจอตอนได้คำตอบ
--------------------------------------------------------------------------
local REPLY_TICKS = 180        -- ~3 วินาที ก่อนจะถือว่าไม่มีเซิร์ฟ

ARK.PENDING = ARK.PENDING or {}

function ARK.requestRepair(player, card, weapon, tier)
    if player == nil or card == nil or weapon == nil then return false end
    if not ARK.canRepair(weapon) then return false end

    local wid = ARK.sc(weapon, "getID")
    local cid = ARK.sc(card, "getID")
    if type(wid) ~= "number" then
        -- ไม่มี id = คุยกับเซิร์ฟไม่ได้ ตกไปทางเล่นเดี่ยวทันที
        print("[AkaRepairKit] !! weapon has no id - repairing locally")
        return ARK.repairLocally(player, card, weapon, tier, "no id")
    end

    ARK.PENDING[wid] = {
        player = player, card = card, weapon = weapon, tier = tier,
        before = ARK.sc(weapon, "getCondition"), ticks = 0,
    }
    tellServer(player, "repair", { weapon = wid, card = cid, tier = tier })
    return true
end

local function refreshUI(player)
    pcall(function()
        local ui = getPlayerInventory(player:getPlayerNum())
        if ui then ui:refreshBackpacks() end
    end)
end

--------------------------------------------------------------------------
-- ทางสำรอง: เล่นเดี่ยวแท้ ๆ ที่ไม่มีเซิร์ฟรับคำสั่งเลย
-- ตรงนี้เขียนค่าเองได้ เพราะไม่มีสำเนาอีกฝั่งให้ขัดกัน และไม่มี anti-cheat
--------------------------------------------------------------------------
function ARK.repairLocally(player, card, weapon, tier, why)
    local pct     = ARK.pct(tier)
    local newCond = ARK.newCondition(weapon, pct)
    if newCond == nil then return false end

    local before = ARK.sc(weapon, "getCondition") or 0
    ARK.sc(weapon, "setCondition", newCond)
    local wear = ARK.newWear(weapon, pct)
    if wear ~= nil then ARK.sc(weapon, "setHaveBeenRepaired", wear) end
    consume(player, card)
    refreshUI(player)

    print("[AkaRepairKit] repaired LOCALLY (" .. tostring(why) .. ") "
        .. tostring(ARK.sc(weapon, "getFullType")) .. " "
        .. tostring(before) .. " -> " .. tostring(newCond))
    return true
end

--------------------------------------------------------------------------
-- คำตอบจากเซิร์ฟ
--------------------------------------------------------------------------
function ARK.onServerCommand(module, command, args)
    if module ~= "AkaRepairKit" then return end
    if type(args) ~= "table" then return end

    local p = ARK.PENDING[args.weapon]
    ARK.PENDING[args.weapon] = nil

    if command == "repaired" then
        if p ~= nil then refreshUI(p.player) end
        print("[AkaRepairKit] server repaired " .. tostring(args.weapon)
            .. " -> " .. tostring(args.cond) .. "  via " .. tostring(args.via))
    elseif command == "refused" then
        print("[AkaRepairKit] server refused: " .. tostring(args.why))
    end
end

--------------------------------------------------------------------------
-- ไม่มีใครตอบภายใน 3 วินาที = ไม่มีเซิร์ฟ (เล่นเดี่ยว) -> ซ่อมเองที่นี่
--
-- ก่อนลงมือต้องเช็คซ้ำว่า "เซิร์ฟไม่ได้ทำไปแล้วแต่คำตอบหาย"
-- ถ้าสภาพขยับแล้ว หรือบัตรหายไปแล้ว แปลว่าเซิร์ฟทำสำเร็จ อย่าซ่อมซ้ำ
--------------------------------------------------------------------------
function ARK.onTick()
    local any = false
    for _ in pairs(ARK.PENDING) do any = true; break end
    if not any then return end

    for wid, p in pairs(ARK.PENDING) do
        p.ticks = p.ticks + 1
        if p.ticks >= REPLY_TICKS then
            ARK.PENDING[wid] = nil
            local now      = ARK.sc(p.weapon, "getCondition")
            local cardGone = ARK.sc(p.player:getInventory(), "contains", p.card) ~= true
            if now ~= p.before or cardGone then
                print("[AkaRepairKit] server handled " .. tostring(wid)
                    .. " but the reply never arrived - not repeating")
                refreshUI(p.player)
            else
                ARK.repairLocally(p.player, p.card, p.weapon, p.tier, "no server")
            end
        end
    end
end

--------------------------------------------------------------------------
-- หาอาวุธที่ซ่อมได้ในกระเป๋า (ไล่เข้าไปในกระเป๋าย่อยด้วย)
--------------------------------------------------------------------------
local function scan(container, out, depth, seen)
    if container == nil or depth > 3 then return end
    local list = container:getItems()
    if list == nil then return end
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        if it ~= nil and not seen[it] then
            seen[it] = true
            if ARK.canRepair(it) then out[#out + 1] = it end
            if instanceof(it, "InventoryContainer") then
                scan(ARK.sc(it, "getInventory"), out, depth + 1, seen)
            end
        end
    end
end

function ARK.repairableWeapons(player)
    local out = {}
    scan(player:getInventory(), out, 1, {})
    table.sort(out, function(a, b)
        local ra = (ARK.sc(a, "getCondition") or 0) / (ARK.sc(a, "getConditionMax") or 1)
        local rb = (ARK.sc(b, "getCondition") or 0) / (ARK.sc(b, "getConditionMax") or 1)
        if ra == rb then
            return tostring(ARK.sc(a, "getName")) < tostring(ARK.sc(b, "getName"))
        end
        return ra < rb
    end)
    return out
end

--------------------------------------------------------------------------
-- Context menu
--------------------------------------------------------------------------
function ARK.onPick(player, card, weapon, tier)
    if player == nil then return end
    if not ARK.canRepair(weapon) then return end
    if not player:getInventory():contains(card) then return end
    ISTimedActionQueue.add(ARKFixAction:new(player, card, weapon, tier))
end

local function unwrap(entry)
    if entry == nil then return nil end
    if entry.items ~= nil then return entry.items[1] end
    return entry
end

function ARK.onFillMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if player == nil or context == nil or items == nil then return end

    local card, tier
    for i = 1, #items do
        local it = unwrap(items[i])
        local t = ARK.tierOf(it)
        if t ~= nil then card = it; tier = t; break end
    end
    if card == nil then return end

    local pct   = ARK.pct(tier)
    local label = "Repair a weapon (+" .. tostring(math.floor(pct)) .. "%)"
    local opt   = context:addOption(label, nil, nil)

    local list = ARK.repairableWeapons(player)
    if #list == 0 then
        opt.notAvailable = true
        pcall(function()
            opt.toolTip = ISWorldObjectContextMenu.addToolTip()
            opt.toolTip.description = "No damaged weapon in your inventory."
        end)
        return
    end

    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(opt, sub)

    local shown = #list
    if shown > MAX_ROWS then shown = MAX_ROWS end

    for i = 1, shown do
        local w    = list[i]
        local cur  = ARK.sc(w, "getCondition")    or 0
        local max  = ARK.sc(w, "getConditionMax") or 0
        local nw   = ARK.newCondition(w, pct)     or cur
        local name = tostring(ARK.sc(w, "getName"))
        local row  = name .. "   " .. tostring(cur) .. "/" .. tostring(max)
                     .. "  ->  " .. tostring(nw) .. "/" .. tostring(max)
        sub:addOption(row, player, ARK.onPick, card, w, tier)
    end

    if #list > shown then
        local more = sub:addOption("... and " .. tostring(#list - shown)
            .. " more (repair the ones above first)", nil, nil)
        more.notAvailable = true
    end
end

Events.OnFillInventoryObjectContextMenu.Add(ARK.onFillMenu)
Events.OnServerCommand.Add(ARK.onServerCommand)
Events.OnTick.Add(ARK.onTick)

-- ป้ายบอกเวอร์ชันตอนโหลด - ค้นคำนี้ใน console.txt เพื่อยืนยันว่าลงตัวใหม่จริง
print("[AkaRepairKit] client v" .. tostring(ARK.VERSION) .. " loaded")
