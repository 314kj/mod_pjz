-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- AkaElixir - เมนูดื่ม + timed action + ช่วงอมตะชั่วคราวของขวดแดง
--
-- action กับเมนูอยู่ไฟล์เดียวกันโดยตั้งใจ
-- PZ โหลด lua เรียงตามชื่อไฟล์ การแยกไฟล์ที่พึ่งพากันคือทางไปสู่ "คลาสครึ่งใบ"

require "AkaElixir/AE_Shared"
require "TimedActions/ISBaseTimedAction"

local MD_UNTIL = "AkaElixir_invUntilHours"
local MD_GOD   = "AkaElixir_setGod"
local MD_INV   = "AkaElixir_setInv"

local HEAL_EVERY = 10          -- ซ่อมแผลทุก 10 เฟรม ไม่ใช่ทุกเฟรม
local logged     = {}          -- พิมพ์ diagnostic ครั้งเดียวต่อขวดต่อเซสชัน

AE.INV = { active = false, left = 0, tick = 0 }

--------------------------------------------------------------------------
-- helper
--------------------------------------------------------------------------
local function worldHours()
    local h = AE.sc(getGameTime(), "getWorldAgeHours")
    if type(h) == "number" then return h end
    return nil
end

-- ข้อความลอยเหนือหัว - ถอดออกแล้ว
-- B42 ไม่มีลายเซ็น addText() ที่ลองไปเลยสักอัน (ล็อกขึ้น error 12 ครั้งต่อรอบ)
-- ของประดับที่แลกมาด้วย error ท่วมล็อก ไม่คุ้ม ถ้าจะกลับมาทำต้องรู้ลายเซ็นจริงก่อน
local function halo(player, text, good) end

--------------------------------------------------------------------------
-- ส่งคำสั่งไปเซิร์ฟ
--
-- v1.2.0 ใช้ `if isClient() then` เป็นด่าน แล้ว **ไม่เคยผ่านเลย** -
-- ในโหมด co-op ที่โฮสต์เอง isClient() คืน false ทั้งที่มีเซิร์ฟรันอยู่จริง
-- ล็อกจึงไม่มีบรรทัด "server:" สักบรรทัด และค่าก็ยังเด้งกลับเหมือนเดิม
--
-- เลิกเดาว่าโหมดไหน: ส่งทุกครั้ง
-- ถ้าไม่มีเซิร์ฟ คำสั่งก็ไม่มีใครรับ ไม่มีผลเสีย
-- และเซิร์ฟก็ clamp ค่าเองอยู่แล้ว ต่อให้เป็นโปรเซสเดียวกันก็ไม่พัง
--------------------------------------------------------------------------
local netWarned = false
local function tellServer(player, command, args)
    if pcall(function() sendClientCommand(player, "AkaElixir", command, args) end) then return true end
    if pcall(function() sendClientCommand("AkaElixir", command, args) end) then return true end
    if not netWarned then
        netWarned = true
        print("[AkaElixir] !! sendClientCommand unavailable - server copy will not be updated")
    end
    return false
end

-- กินไอเทม
-- B42 เปลี่ยนลายเซ็นเป็น removeItem(item, playerNum:int) ไม่ใช่ตัว player
--   "expected argument of type int, got IsoPlayer at ISRemoveItemTool.lua:287"
-- ลอง int ก่อน แล้ว player object (แบบ B41) แล้วค่อย Remove ตรง ๆ
-- และ "เช็คว่าหายจริง" ทุกขั้น ไม่ใช่แค่ไม่โยน error
local function consume(player, item)
    local inv = player:getInventory()
    local function gone() return AE.sc(inv, "contains", item) ~= true end
    if gone() then return true end

    if ISRemoveItemTool and ISRemoveItemTool.removeItem then
        local pn = AE.sc(player, "getPlayerNum")
        if type(pn) == "number" then
            pcall(function() ISRemoveItemTool.removeItem(item, pn) end)
            if gone() then return true end
        end
        pcall(function() ISRemoveItemTool.removeItem(item, player) end)
        if gone() then return true end
    end

    pcall(function() inv:Remove(item) end)
    if gone() then return true end

    print("[AkaElixir] !! could not consume " .. tostring(AE.sc(item, "getFullType")))
    return false
end

local function md(player)
    local t = AE.sc(player, "getModData")
    if type(t) == "table" then return t end
    return nil
end

--------------------------------------------------------------------------
-- ช่วงอมตะ
--------------------------------------------------------------------------
function AE.startInvuln(player, minutes)
    local S = AE.INV
    local m = md(player)

    -- ตัวละครใหม่ (ตายแล้วเกิดใหม่ในเซสชันเดียวกัน) ต้องไม่รับเวลาที่เหลือของคนเก่ามา
    if S.player ~= player then
        S.player = player
        S.active = false
        S.left   = 0
    end

    -- จำว่าก่อนดื่ม *ครั้งแรก* เปิดอยู่แล้วหรือเปล่า จะได้ไม่ไปปิดของแอดมินตอนหมดเวลา
    -- เช็ค == nil ไม่ใช่ `if not S.active` เพราะดื่มซ้ำระหว่างมีเกราะ
    -- godmode จะเปิดอยู่ด้วยขวดของเราเอง แล้วจะถูกอ่านผิดเป็น "แอดมินเปิดไว้"
    if m then
        if m[MD_GOD] == nil then m[MD_GOD] = (AE.sc(player, "isGodMod") ~= true) end
        if m[MD_INV] == nil then m[MD_INV] = (AE.sc(player, "isInvincible") ~= true) end
    end

    S.active = true
    S.left   = math.max(S.left or 0, minutes)   -- ดื่มซ้ำ = ต่ออายุ ไม่ซ้อนกัน

    AE.sc(player, "setGodMod", true)
    AE.sc(player, "setInvincible", true)

    local wh = worldHours()
    if m and wh then m[MD_UNTIL] = wh + (S.left / 60.0) end

    print("[AkaElixir] invulnerable for " .. tostring(S.left) .. " in-game minute(s)")
end

function AE.stopInvuln(player)
    local S = AE.INV
    S.active = false
    S.left   = 0
    S.player = nil
    local m  = md(player)

    if m == nil or m[MD_GOD] ~= false then AE.sc(player, "setGodMod", false) end
    if m == nil or m[MD_INV] ~= false then AE.sc(player, "setInvincible", false) end

    if m then m[MD_UNTIL] = nil; m[MD_GOD] = nil; m[MD_INV] = nil end
    print("[AkaElixir] invulnerability ended")
end

function AE.onEveryOneMinute()
    local S = AE.INV
    if not S.active then return end
    local player = getPlayer()
    if player == nil then return end

    S.left = S.left - 1
    if S.left <= 0 then
        AE.stopInvuln(player)
        halo(player, "The shield fades.", false)
        return
    end

    local m, wh = md(player), worldHours()
    if m and wh then m[MD_UNTIL] = wh + (S.left / 60.0) end
end

function AE.onPlayerUpdate(player)
    local S = AE.INV
    if not S.active then return end
    if player == nil or player ~= getPlayer() then return end
    if not AE.panaceaHeals() then return end

    S.tick = S.tick + 1
    if S.tick < HEAL_EVERY then return end
    S.tick = 0

    AE.healWounds(player, AE.newLog())
end

-- กู้สถานะตอนเข้าเกมใหม่
-- ถ้าออกเกมกลางช่วงอมตะ godmode จะค้าง ตัวนี้คือด่านที่เก็บกวาดให้
function AE.onCreatePlayer(_, player)
    if player == nil or player ~= getPlayer() then return end
    local m = md(player)
    if m == nil then return end

    local until_ = m[MD_UNTIL]
    if type(until_) ~= "number" then
        if m[MD_GOD] ~= nil or m[MD_INV] ~= nil then AE.stopInvuln(player) end
        return
    end

    local wh = worldHours()
    if wh == nil or wh >= until_ then
        AE.stopInvuln(player)
        return
    end

    AE.INV.active = true
    AE.INV.player = player
    AE.INV.left   = math.max(1, math.ceil((until_ - wh) * 60))
    AE.sc(player, "setGodMod", true)
    AE.sc(player, "setInvincible", true)
    print("[AkaElixir] resumed invulnerability, " .. tostring(AE.INV.left) .. " minute(s) left")
end

--------------------------------------------------------------------------
-- ดื่ม
--------------------------------------------------------------------------
function AE.drink(player, item)
    local def = AE.defOf(item)
    if def == nil then return false end
    if AE.sc(player:getInventory(), "contains", item) ~= true then return false end

    AE.probe(player)

    local log = AE.newLog()
    local fn  = AE.EFFECTS[def.key]
    if type(fn) == "function" then pcall(function() fn(player, log) end) end

    if def.invuln then
        AE.startInvuln(player, AE.invulnMinutes())
    end

    -- MP/co-op: บอกเซิร์ฟให้ลบสำเนาของมันด้วย ไม่งั้นขวดจะกลับมาตอนซิงก์รอบถัดไป
    local iid = AE.sc(item, "getID")
    if iid ~= nil then tellServer(player, "drank", { item = iid }) end

    consume(player, item)
    halo(player, def.done, true)

    -- พิมพ์ครั้งเดียวต่อขวดต่อเซสชัน (หรือทุกครั้งถ้าเปิด Verbose)
    -- บรรทัดนี้คือหลักฐานว่าเมธอดไหนของ B42 ใช้ได้จริง ถ้ามีอันไหน skipped
    -- ส่ง console.txt มาแล้วตัดทิ้ง/หาชื่อที่ถูกได้เลย
    if AE.verbose() or not logged[def.key] then
        logged[def.key] = true
        print(AE.logLine(def.key, log))
    end
    return true
end

--------------------------------------------------------------------------
-- Timed action
--------------------------------------------------------------------------
AEDrinkAction = ISBaseTimedAction:derive("AEDrinkAction")

function AEDrinkAction:isValid()
    return AE.sc(self.character:getInventory(), "contains", self.item) == true
end

function AEDrinkAction:waitToStart() return false end

function AEDrinkAction:start()
    pcall(function() self:setActionAnim("Drink") end)
    pcall(function() self.item:setJobDelta(0.0) end)
end

function AEDrinkAction:stop()
    pcall(function() self.item:setJobDelta(0.0) end)
    ISBaseTimedAction.stop(self)
end

function AEDrinkAction:perform()
    pcall(function() self.item:setJobDelta(0.0) end)
    AE.drink(self.character, self.item)
    ISBaseTimedAction.perform(self)
end

function AEDrinkAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.character  = character
    o.item       = item
    o.stopOnWalk = false
    o.stopOnRun  = true
    o.maxTime    = 40
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

--------------------------------------------------------------------------
-- Context menu
--------------------------------------------------------------------------
function AE.onDrinkPicked(player, item)
    if player == nil or item == nil then return end
    if AE.defOf(item) == nil then return end
    ISTimedActionQueue.add(AEDrinkAction:new(player, item))
end

local function unwrap(entry)
    if entry == nil then return nil end
    if entry.items ~= nil then return entry.items[1] end
    return entry
end

function AE.onFillMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if player == nil or context == nil or items == nil then return end

    local item, def
    for i = 1, #items do
        local it = unwrap(items[i])
        local d  = AE.defOf(it)
        if d ~= nil then item = it; def = d; break end
    end
    if item == nil then return end

    local label = "Drink"
    if def.invuln then
        label = "Drink  (" .. tostring(math.floor(AE.invulnMinutes())) .. " min of protection)"
    end
    context:addOption(label, player, AE.onDrinkPicked, item)
end

Events.OnFillInventoryObjectContextMenu.Add(AE.onFillMenu)
Events.EveryOneMinute.Add(AE.onEveryOneMinute)
Events.OnPlayerUpdate.Add(AE.onPlayerUpdate)
Events.OnCreatePlayer.Add(AE.onCreatePlayer)

-- ป้ายบอกเวอร์ชันตอนโหลด - ค้นคำนี้ใน console.txt เพื่อยืนยันว่าลงตัวใหม่จริง
print("[AkaElixir] client v" .. tostring(AE.VERSION) .. " loaded")
