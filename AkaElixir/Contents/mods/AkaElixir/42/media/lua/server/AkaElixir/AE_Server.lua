-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- AkaElixir - ฝั่งเซิร์ฟเวอร์
--
-- ใน co-op/MP เซิร์ฟเวอร์ถือสำเนาจริงของไอเทมในกระเป๋า
-- ไคลเอนต์ลบขวดของตัวเองได้ แต่ถ้าเซิร์ฟไม่ลบตาม ขวดจะกลับมาตอนซิงก์รอบถัดไป
-- ไฟล์นี้ทำหน้าที่เดียว: ลบขวดออกจากสำเนาของเซิร์ฟ

require "AkaElixir/AE_Shared"

if AE.__serverReady then return end

local function scanForID(container, id, depth, seen)
    if container == nil or depth > 3 then return nil end
    local list = container:getItems()
    if list == nil then return nil end
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        if it ~= nil and not seen[it] then
            seen[it] = true
            if AE.sc(it, "getID") == id then return it end
            if instanceof(it, "InventoryContainer") then
                local hit = scanForID(AE.sc(it, "getInventory"), id, depth + 1, seen)
                if hit ~= nil then return hit end
            end
        end
    end
    return nil
end

local function onClientCommand(module, command, player, args)
    if module ~= "AkaElixir" or command ~= "drank" then return end
    if player == nil or type(args) ~= "table" then return end
    if type(args.item) ~= "number" then return end

    local item = scanForID(player:getInventory(), args.item, 1, {})
    if item == nil then return end                 -- ไคลเอนต์ลบไปแล้ว ปกติ

    -- ลบได้เฉพาะขวดของม็อดนี้ ไม่ใช่ไอเทมอะไรก็ได้ที่ส่ง id มา
    if AE.defOf(item) == nil then
        print("[AkaElixir] server: refused to remove a non-elixir item")
        return
    end

    local cont = AE.sc(item, "getContainer")
    if cont ~= nil then pcall(function() cont:Remove(item) end) end
    pcall(function() player:getInventory():Remove(item) end)
    print("[AkaElixir] server: consumed " .. tostring(AE.sc(item, "getFullType")))
end

Events.OnClientCommand.Add(onClientCommand)

AE.__serverReady = true
print("[AkaElixir] server v" .. tostring(AE.VERSION) .. " ready")
return AE
