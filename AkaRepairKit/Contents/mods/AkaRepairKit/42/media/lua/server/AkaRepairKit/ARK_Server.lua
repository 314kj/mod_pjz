-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- AkaRepairKit - ฝั่งเซิร์ฟเวอร์
--
-- ทำไมต้องมีไฟล์นี้:
-- ใน co-op/MP เซิร์ฟเวอร์ถือ "สำเนาจริง" ของไอเทมในกระเป๋าผู้เล่น
-- ไคลเอนต์แก้ condition ได้แค่สำเนาของตัวเอง พอวางลงพื้นหรือย้ายเข้ากล่อง
-- เกมเขียนจากสำเนาของเซิร์ฟ ค่าจึงเด้งกลับเป็นเดิม
-- (อาการที่ Pie เจอ: "สภาพเปลี่ยนแค่ตอนถือ พอทิ้งหรือเก็บกลับไปเป็นเหมือนเดิม")
--
-- บทเรียนเดียวกับ ghost items ของ Traka:
-- ทางแก้เป็นเรื่องสถาปัตยกรรม ไม่ใช่ยิงแพ็กเก็ตเพิ่ม - ให้เจ้าของของเป็นคนแก้

require "AkaRepairKit/ARK_Shared"

if ARK.__serverReady then return end

--------------------------------------------------------------------------
-- หาไอเทมจาก id ในกระเป๋าผู้เล่น (ไล่เข้ากระเป๋าย่อยด้วย)
--------------------------------------------------------------------------
local function scanForID(container, id, depth, seen)
    if container == nil or depth > 3 then return nil end
    local list = container:getItems()
    if list == nil then return nil end
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        if it ~= nil and not seen[it] then
            seen[it] = true
            if ARK.sc(it, "getID") == id then return it end
            if instanceof(it, "InventoryContainer") then
                local hit = scanForID(ARK.sc(it, "getInventory"), id, depth + 1, seen)
                if hit ~= nil then return hit end
            end
        end
    end
    return nil
end

local function findByID(player, id)
    if type(id) ~= "number" then return nil end
    return scanForID(player:getInventory(), id, 1, {})
end

-- ลบบัตรแบบที่เกมใช้เอง: ประกาศผ่าน sendRemoveItemFromContainer ก่อน
-- แล้วค่อยลบออกจากสำเนาของเซิร์ฟ ไคลเอนต์จะเห็นบัตรหายเองโดยไม่ต้องลบเอง
local function removeServerSide(player, item)
    local cont = ARK.sc(item, "getContainer") or player:getInventory()
    local f    = ARK.gfn("sendRemoveItemFromContainer")
    if f ~= nil and cont ~= nil then
        pcall(function() f(cont, item) end)
    end
    if cont ~= nil then pcall(function() cont:Remove(item) end) end
    pcall(function() player:getInventory():Remove(item) end)
end

local function reply(player, command, args)
    local f = ARK.gfn("sendServerCommand")
    if f == nil then return false end
    if pcall(function() f(player, "AkaRepairKit", command, args) end) then return true end
    if pcall(function() f("AkaRepairKit", command, args) end) then return true end
    return false
end

--------------------------------------------------------------------------
-- คำสั่งจากไคลเอนต์  (v2.0.0)
--
-- ไคลเอนต์ส่งมาแค่ 3 ตัวเลข: id อาวุธ · id บัตร · tier
-- และ **เซิร์ฟไม่เชื่อแม้แต่ tier** - มันอ่าน tier จากตัวบัตรในมือตัวเอง
-- ตัวเลขทุกตัวที่ใช้เขียนจึงเกิดจากสำเนาของเซิร์ฟล้วน ๆ
-- คนที่แก้ไฟล์ม็อดเองส่งอะไรมาก็ไม่ได้เปรียบ
--
-- เขียนเสร็จแล้วประกาศด้วย syncItemFields() ซึ่งเป็นช่องทางเดียวกับที่เกม
-- ใช้เองตอนสภาพอาวุธเปลี่ยน - ไม่มีแพ็กเก็ตแปลกปลอมให้ anti-cheat สงสัย
--------------------------------------------------------------------------
local function onClientCommand(module, command, player, args)
    if module ~= "AkaRepairKit" or command ~= "repair" then return end
    if player == nil or type(args) ~= "table" then return end
    if type(args.weapon) ~= "number" then return end

    local function refuse(why)
        print("[AkaRepairKit] server: refused - " .. why)
        reply(player, "refused", { weapon = args.weapon, why = why })
    end

    -- บัตรต้องมีอยู่จริงในกระเป๋าของเซิร์ฟ และ tier มาจากตัวบัตร ไม่ใช่จาก args
    local card = findByID(player, args.card)
    local tier = ARK.tierOf(card)
    if card == nil or tier == nil then return refuse("no repair card") end

    local weapon = findByID(player, args.weapon)
    if weapon == nil then return refuse("weapon not found") end
    if not ARK.canRepair(weapon) then return refuse("weapon cannot be repaired") end

    local pct     = ARK.pct(tier)
    local cur     = ARK.sc(weapon, "getCondition")
    local newCond = ARK.newCondition(weapon, pct)
    if newCond == nil then return refuse("no condition to read") end
    if type(cur) == "number" and newCond <= cur then return refuse("already full") end

    ARK.sc(weapon, "setCondition", newCond)

    local wear = ARK.newWear(weapon, pct)
    if wear ~= nil then ARK.sc(weapon, "setHaveBeenRepaired", wear) end

    -- ประกาศก่อนลบบัตร ผู้เล่นจะได้ไม่เห็นบัตรหายไปเฉย ๆ โดยอาวุธยังไม่ขยับ
    local via = ARK.sync(player, weapon)
    removeServerSide(player, card)

    print("[AkaRepairKit] server: " .. tostring(ARK.sc(weapon, "getFullType"))
        .. " " .. tostring(cur) .. " -> " .. tostring(newCond)
        .. " (tier " .. tostring(tier) .. ", " .. tostring(math.floor(pct)) .. "%)"
        .. "  sync via " .. tostring(via))

    reply(player, "repaired", { weapon = args.weapon, cond = newCond, via = via })
end

Events.OnClientCommand.Add(onClientCommand)

ARK.__serverReady = true
print("[AkaRepairKit] server v" .. tostring(ARK.VERSION) .. " ready")
return ARK
