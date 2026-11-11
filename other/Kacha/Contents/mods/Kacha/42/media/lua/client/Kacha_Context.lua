--[[ ============================================================
     Kacha B42 [MP]  -  world right-click menu  by PIE

     Spin / Setting / Delete on a machine; Spawn on empty ground
     (admin). The AKA.getGroup call is pcall-guarded: if any other
     AKA mod (e.g. Dunka) ships a different AKA_Menu and its grouper
     throws, we fall back to a local submenu so our options NEVER
     vanish from the menu.
   ============================================================ ]]
require "ISUI/ISContextMenu"
pcall(require, "AKA_Menu")

local function spawnSkin(pl, spr, sq)
    -- use the brush cursor for VISUAL positioning (admin moves + clicks a tile).
    -- In MP the actual placement is re-routed to the server in onKachaObjAdded
    -- below, so every client sees it. In SP the brush placement stands as-is.
    Kacha.placing = spr
    if ISBrushToolTileCursor then
        local cursor = ISBrushToolTileCursor:new(spr, spr, pl)
        getCell():setDrag(cursor, pl:getPlayerNum())
    elseif sq and isClient and isClient() then
        sendClientCommand(pl, "Kacha", "place", { x = sq:getX(), y = sq:getY(), z = sq:getZ(), sprite = spr })
    end
end

-- MP: when the brush drops a Kacha tile on THIS client, hand it to the server
-- (authoritative + visible to everyone) and remove the client-only copy.
local function onKachaObjAdded(obj)
    pcall(function()
        if not (isClient and isClient()) then return end   -- SP: let the brush copy stand
        if not Kacha.placing then return end
        if not (Kacha and Kacha.isKacha and Kacha.isKacha(obj)) then return end
        local s = obj:getSquare(); if not s then return end
        local x, y, z, spr = s:getX(), s:getY(), s:getZ(), Kacha.placing
        Kacha.placing = nil
        pcall(function() s:transmitRemoveItemFromSquare(obj) end)   -- drop the local-only copy
        sendClientCommand(getPlayer(), "Kacha", "place", { x = x, y = y, z = z, sprite = spr })
    end)
end
if Events and Events.OnObjectAdded then Events.OnObjectAdded.Add(onKachaObjAdded) end

-- always returns a usable submenu; never throws
local function gachaSub(context)
    if AKA and AKA.getGroup then
        local ok, sub = pcall(AKA.getGroup, context, "Gacha")
        if ok and sub then return sub end
    end
    -- fallback: local "AKA MOD > Gacha"
    local rootOpt = context:addOption("AKA MOD", nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(rootOpt, sub)
    return sub
end

local function onFillWorldObjectContextMenu(playerIdx, context, worldobjects, test)
    if test then return end
    -- HARD GUARD: never let our menu code throw, or it kills the rest of the
    -- world context menu (including vanilla "Drop"). Wrap everything.
    local ok, err = pcall(function()
        local pl = getSpecificPlayer(playerIdx)
        if not pl then return end

        local obj, sq = nil, nil
        for _, wo in ipairs(worldobjects) do
            if not sq then sq = wo:getSquare() end
            if Kacha and Kacha.isKacha and Kacha.isKacha(wo) then obj = wo; break end
        end

        -- FALLBACK: right-clicking truly empty ground can hand us an empty
        -- worldobjects list, leaving sq nil -> the admin Spawn menu would never
        -- appear. Anchor the menu to the player's square instead (the actual
        -- placement still uses the brush cursor, so the anchor only gates
        -- visibility). This only ADDS the menu; it never hides an existing one.
        if not sq and pl.getCurrentSquare then sq = pl:getCurrentSquare() end

        -- 1) clicked a machine
        if obj then
            local sub = gachaSub(context)
            if Kacha.openSpin then
                sub:addOption("Spin", obj, function() Kacha.openSpin(obj, pl) end)
            end
            if Kacha.openOdds then
                sub:addOption("Item", obj, function() Kacha.openOdds(obj) end)
            end
            if Kacha.isAkaAdmin and Kacha.isAkaAdmin() then
                if Kacha.openAdmin then
                    sub:addOption("Setting", obj, function() Kacha.openAdmin(obj) end)
                end
                sub:addOption("Delete", obj, function()
                    local s = obj:getSquare()
                    if s then s:transmitRemoveItemFromSquare(obj) end
                end)
            end

        -- 2) clicked empty ground (admin) -> spawn
        elseif sq and Kacha.isAkaAdmin and Kacha.isAkaAdmin() then
            local sub = gachaSub(context)
            local spawnOpt = sub:addOption("Spawn Kacha", nil, nil)
            local spawnSub = ISContextMenu:getNew(sub)
            sub:addSubMenu(spawnOpt, spawnSub)
            if Kacha.SKINS then
                for i, spr in ipairs(Kacha.SKINS) do
                    local label = (Kacha.SKIN_NAMES and Kacha.SKIN_NAMES[spr]) or ("Skin " .. i)
                    spawnSub:addOption(label, nil, function() spawnSkin(pl, spr, sq) end)
                end
            end
        end
    end)
    if not ok then print("[Kacha] context menu error (suppressed): " .. tostring(err)) end
end

-- store the ref so we never double-register on a hot reload
if Kacha.onWorldMenu then
    Events.OnFillWorldObjectContextMenu.Remove(Kacha.onWorldMenu)
end
Kacha.onWorldMenu = onFillWorldObjectContextMenu
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

Kacha.__mark("ctx")
