--[[ ============================================================
  PROJECT DUNKA  [MP]  -- client                    KACHASIG
  Placement copied from Kacha's proven pattern:
    admin right-clicks ground -> "Spawn DunKa Horde Box" ->
    ISBrushToolTileCursor paints the horde_box_ka_0 sprite.
  NO entity / NO moveable item -> never touches the admin item
  list -> no ISItemsListTable crash, no world-dictionary abort.
  Players right-click a placed box to Summon a horde with a card.
============================================================ ]]--

require "ISUI/ISContextMenu"
require "AKA_Menu"
require "DunKa_SlipEditUI"
require "DunKa_ItemPicker"
require "DunKa_RankEditUI"
require "DunKa_ConfigUI"
require "DunKa_Shared"
require "DunKa_SummonUI"
require "DunKa_WarnUI"
require "DunKa_LogUI"

local CAB_SPRITE = "horde_aka_0"   -- painted tile sprite
local CAB_DETECT = "horde_aka"     -- sprite-name fragment for detection

----------------------------------------------------------------
-- admin check (same logic Kacha uses)
----------------------------------------------------------------
local function isAdminUser()
    if DunKa.isSP() then return true end
    local pl = getPlayer and getPlayer()
    if pl and pl.getAccessLevel then
        local lvl = tostring(pl:getAccessLevel()):lower()
        if lvl=="admin" or lvl=="moderator" or lvl=="gm" then return true end
    end
    return false
end

----------------------------------------------------------------
-- detect a placed horde box on a square (sprite name or container)
----------------------------------------------------------------
local function objIsCabinet(o)
    if not o then return false end
    local spr = o.getSprite and o:getSprite()
    local name = spr and spr.getName and spr:getName()
    if name and string.find(name, CAB_DETECT, 1, true) then return true end
    local md = o.getModData and o:getModData()
    if md and md.DunKaCabinet then return true end
    return false
end

local function findCabinetOnSquare(sq)
    if not sq then return nil end
    local objs = sq:getObjects()
    if not objs then return nil end
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if objIsCabinet(o) then return o end
    end
    return nil
end

----------------------------------------------------------------
-- admin: paint the box onto the ground (Kacha brush pattern)
----------------------------------------------------------------
local function spawnBox(pl)
    -- brush placement resolves the sprite via IsoSpriteManager (NOT getTexture)
    local hasSprite = IsoSpriteManager.instance and IsoSpriteManager.instance:getSprite(CAB_SPRITE)
    local hasTex    = getTexture(CAB_SPRITE)
    print("[DunKa] sprite check '" .. CAB_SPRITE .. "': getSprite=" ..
          tostring(hasSprite ~= nil) .. " getTexture=" .. tostring(hasTex ~= nil))

    if not hasSprite and not hasTex then
        pl:setHaloNote("DunKa: sprite not loaded -> " .. CAB_SPRITE, 250, 120, 120, 300)
        return
    end
    if not ISBrushToolTileCursor then
        pl:setHaloNote("DunKa: tile cursor unavailable", 250, 120, 120, 300)
        return
    end
    local cursor = ISBrushToolTileCursor:new(CAB_SPRITE, CAB_SPRITE, pl)
    getCell():setDrag(cursor, pl:getPlayerNum())
    pl:setHaloNote("DunKa: left-click ground to place the horde box", 150, 220, 250, 300)
end

----------------------------------------------------------------
-- admin: place the box DIRECTLY on a square (no brush click)
-- fallback for when ISBrushToolTileCursor won't stamp. Wrapped in
-- pcall so a wrong API logs instead of crashing.
----------------------------------------------------------------
local function placeBoxHere(pl, sq)
    if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    if DunKa.isSP() then
        local ok = DunKa.doPlaceBox(x, y, z)
        if ok then pl:setHaloNote("DunKa box placed", 150, 230, 150, 250)
        else pl:setHaloNote("DunKa place failed (see console)", 250, 120, 120, 300) end
    else
        sendClientCommand(pl, "DunKa", "placeBox", { x = x, y = y, z = z })
        pl:setHaloNote("DunKa: placing box...", 150, 220, 250, 250)
    end
end

----------------------------------------------------------------
-- admin: remove a placed box (Kacha delete pattern)
----------------------------------------------------------------
local function deleteBox(obj, pl)
    local sq = obj.getSquare and obj:getSquare()
    if not sq then return end
    -- brush-painted tile: transmitRemove syncs the removal to everyone (Kacha pattern)
    if sq.transmitRemoveItemFromSquare then sq:transmitRemoveItemFromSquare(obj)
    else sq:RemoveTileObject(obj) end
    if pl then pl:setHaloNote("DunKa box removed", 250, 200, 120, 200) end
end

----------------------------------------------------------------
-- use a rank card at a cabinet square
----------------------------------------------------------------
local function doUse(player, sq, rankId)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()

    if DunKa.isOnCooldown() then
        DunKa.notify(player, "Cooling down: " .. DunKa.fmtRemaining(DunKa.cooldownRemainingMs()))
        return
    end

    if DunKa.isSP() then
        local ok, reason, remMs = DunKa.processUse(player, x, y, z, rankId)
        if ok then
            DunKa.applyReward(player, rankId)
            DunKa.playBoss(player)
            DunKa.notify(player, "Horde summoned! Rank " .. rankId)
        elseif reason == "cooldown" then
            DunKa.notify(player, "Cooling down: " .. DunKa.fmtRemaining(remMs))
        elseif reason == "no_card" then
            DunKa.notify(player, "No Rank " .. rankId .. " key card")
        elseif reason == "cant_spawn" then
            DunKa.notify(player, "Can't spawn a horde here (area full or blocked). Card kept.")
        else
            DunKa.notify(player, "Cannot summon (" .. tostring(reason) .. ")")
        end
    else
        sendClientCommand(player, "DunKa", "use", { x = x, y = y, z = z, rank = rankId })
        DunKa.notify(player, "Inserting Rank " .. rankId .. " card...")
    end
end

DunKa.requestSummon = doUse   -- expose for SummonUI

----------------------------------------------------------------
-- server reply (MP)
----------------------------------------------------------------
local function onServerCommand(module, command, args)
    if module ~= "DunKa" then return end
    if command == "boxList" then
        DunKa._clientBoxes = args.list or {}
        DunKa._gotBoxes = true
        return
    end
    if command == "configData" then
        DunKaConfigUI.openFor(args.slip or {}, args.rank or {})
        return
    end
    if command == "rankCfg" then
        DunKaRankEditUI.openFor(args.cfg or {})
        return
    end
    if command == "slipCfg" then
        DunKaSlipEditUI.openFor(args.cfg or {})
        return
    end
    if command == "openResult" then
        local player = getPlayer()
        if args.ok then DunKa.notifyLoot(player, args.color, args.gained)
        else DunKa.notify(player, "No "..tostring(args.color).." Slip") end
        return
    end
    if command == "logData" then
        DunKaLogUI.openFor(args.entries or {}, args.x, args.y, args.z)
        return
    end
    if command == "placeResult" then
        local player = getPlayer(); if not player then return end
        args = args or {}
        if args.ok then
            print("[DunKa][CL] placeResult OK")
            player:setHaloNote("DunKa box placed", 150, 230, 150, 250)
            -- ===== client render diagnostics (pcall-guarded) =====
            pcall(function()
            local spr = IsoSpriteManager and IsoSpriteManager.instance
                        and IsoSpriteManager.instance:getSprite("horde_aka_0")
            local tex = getTexture("horde_aka_0")
            print("[DunKa][CL] sprite 'horde_aka_0' getSprite="..tostring(spr~=nil)
                  .." getTexture="..tostring(tex~=nil))
            if spr and spr.getWidth then
                print("[DunKa][CL] sprite size = "..tostring(spr:getWidth()).."x"..tostring(spr:getHeight()))
            end
            local cell = getCell()
            local sq = cell and cell:getGridSquare(args.x, args.y, args.z)
            if sq then
                local objs = sq:getObjects()
                local n = objs and objs:size() or 0
                print("[DunKa][CL] square "..args.x..","..args.y..","..args.z.." has "..n.." object(s):")
                for i=0,n-1 do
                    local o = objs:get(i)
                    local sp = o.getSprite and o:getSprite()
                    local nm = sp and sp.getName and sp:getName()
                    print("[DunKa][CL]   ["..i.."] sprite="..tostring(nm))
                end
            else
                print("[DunKa][CL] square NOT loaded on client at "..args.x..","..args.y..","..args.z)
            end
            end) -- end pcall
        else
            print("[DunKa][CL] placeResult FAILED reason="..tostring(args.reason))
            player:setHaloNote("DunKa place FAILED: "..tostring(args.reason), 250, 120, 120, 350)
        end
        return
    end
    if command == "useResult" then
        local player = getPlayer(); if not player then return end
        args = args or {}
        if args.ok then
            DunKa.playBoss(player)
            DunKa.notify(player, "Horde summoned! Rank " .. tostring(args.rank))
        elseif args.reason == "cooldown" then
            DunKa.notify(player, "Cooling down: " .. DunKa.fmtRemaining(args.remainingMs))
        elseif args.reason == "no_card" then
            DunKa.notify(player, "No Rank " .. tostring(args.rank) .. " key card")
        elseif args.reason == "cant_spawn" then
            DunKa.notify(player, "Can't spawn a horde here (area full or blocked). Card kept.")
        else
            DunKa.notify(player, "Cannot summon (" .. tostring(args.reason) .. ")")
        end
    end
end
Events.OnServerCommand.Add(onServerCommand)

----------------------------------------------------------------
-- world context menu
----------------------------------------------------------------
function DunKa.notifyLoot(player, color, gained)
    if not gained or #gained == 0 then DunKa.notify(player, color.." Slip: nothing this time..."); return end
    local parts = {}
    for _, g in ipairs(gained) do
        parts[#parts+1] = (tostring(g.item):gsub("^.*%.", "")).." x"..tostring(g.qty or 1)
    end
    DunKa.notify(player, color.." Slip opened: "..table.concat(parts, ", "))
end

function DunKa.requestOpenSlip(player, color)
    if DunKa.isSP() then
        local ok, gained = DunKa.openSlip(player, color)
        if ok then DunKa.notifyLoot(player, color, gained)
        else DunKa.notify(player, "No "..tostring(color).." Slip") end
    else
        sendClientCommand(player, "DunKa", "openSlip", { color = color })
    end
end

function DunKa.requestConfig(player)
    if DunKa.isSP() then
        DunKaConfigUI.openFor(DunKa.getSlipConfig(), DunKa.getRankConfig())
    else
        sendClientCommand(player, "DunKa", "getConfig", {})
    end
end

function DunKa.requestRankEdit(player)
    if DunKa.isSP() then
        DunKaRankEditUI.openFor(DunKa.getRankConfig())
    else
        sendClientCommand(player, "DunKa", "getRankCfg", {})
    end
end

function DunKa.requestSlipEdit(player)
    if DunKa.isSP() then
        DunKaSlipEditUI.openFor(DunKa.getSlipConfig())
    else
        sendClientCommand(player, "DunKa", "getSlipCfg", {})
    end
end

function DunKa.requestLog(player, sq)
    if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    if DunKa.isSP() then
        DunKaLogUI.openFor(DunKa.getLog(x, y, z), x, y, z)
    else
        sendClientCommand(player, "DunKa", "getLog", { x = x, y = y, z = z })
    end
end

local function onWorldMenu(playerIdx, context, worldobjects, test)
    if test then return end
    local pl = getSpecificPlayer(playerIdx); if not pl then return end

    local sq = nil
    for _, wo in ipairs(worldobjects) do
        local s = wo:getSquare(); if s then sq = s; break end
    end

    local cab = findCabinetOnSquare(sq)

    if cab then
        local md = cab.getModData and cab:getModData()
        if md then md.DunKaCabinet = true end

        local inv = pl:getInventory()
        local g = AKA.getGroup(context, "Dunka")
        local top = g:addOption("Horde Box", nil, nil)
        local sub = ISContextMenu:getNew(g)
        g:addSubMenu(top, sub)

        sub:addOption("Open Verification Terminal", pl, function(p) DunKaWarnUI.openFor(p, sq) end)
        local bm = DunKa.bossMusicOn(pl)
        sub:addOption("Boss Music: " .. (bm and "ON" or "OFF"), pl, function(p) DunKa.toggleBossMusic(p) end)
        if DunKa.isOnCooldown() then
            local o = sub:addOption("Cooling down: " .. DunKa.fmtRemaining(DunKa.cooldownRemainingMs()), nil, nil)
            o.notAvailable = true
        end

        if isAdminUser() then
            g:addOption("Delete Box", cab, function() deleteBox(cab, pl) end)
            g:addOption("View Usage Log", pl, function(p) DunKa.requestLog(p, sq) end)
            g:addOption("DunKa Config", pl, function(p) DunKa.requestConfig(p) end)
        end

    elseif isAdminUser() and sq then
        local g = AKA.getGroup(context, "Dunka")
        g:addOption("Spawn Horde Box", pl, function(p) spawnBox(p) end)
    end
end

Events.OnFillWorldObjectContextMenu.Remove(onWorldMenu)
Events.OnFillWorldObjectContextMenu.Add(onWorldMenu)

-- ---- inventory right-click: Open Slip ----
local SLIP_COLOR_BY_FT = {}
for c, ft in pairs(DunKa.SLIP_ITEM) do SLIP_COLOR_BY_FT[ft] = c end

local function onInvMenu(playerIdx, context, items)
    local pl = getSpecificPlayer(playerIdx); if not pl then return end
    for _, entry in ipairs(items) do
        local item = entry
        if not instanceof(entry, "InventoryItem") then item = entry.items and entry.items[1] end
        if item and item.getFullType then
            local color = SLIP_COLOR_BY_FT[item:getFullType()]
            if color then
                context:addOption("Open Slip", pl, function(p) DunKa.requestOpenSlip(p, color) end)
                return
            end
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onInvMenu)

print("[DunKa] client menu ready (Kacha-style placer)")


----------------------------------------------------------------
-- boot diagnostic: prints the running BUILD tag + client texture
-- status the moment you load in (so we know which zip is live)
----------------------------------------------------------------
local function dunkaBootDiag()
    pcall(function()
        local spr = IsoSpriteManager and IsoSpriteManager.instance
                    and IsoSpriteManager.instance:getSprite("horde_aka_0")
        local tex = getTexture("horde_aka_0")
        print("[DunKa][CL] BUILD=picker-Q  horde_aka_0  getSprite="
              ..tostring(spr~=nil).."  getTexture="..tostring(tex~=nil))
        if spr and spr.getWidth then
            print("[DunKa][CL] horde_aka_0 size="..tostring(spr:getWidth())
                  .."x"..tostring(spr:getHeight()))
        end
        -- also report the loose-png sprite, which DOES render if the pack fails
        local sprPng = IsoSpriteManager and IsoSpriteManager.instance
                       and IsoSpriteManager.instance:getSprite("horde_aka")
        print("[DunKa][CL] fallback 'horde_aka' getSprite="..tostring(sprPng~=nil)
              .."  getTexture="..tostring(getTexture("horde_aka")~=nil))
    end)
end
Events.OnGameStart.Add(dunkaBootDiag)

local function dunkaHelloBoxes()
    if DunKa.isSP and DunKa.isSP() then return end
    if DunKa._gotBoxes then return end
    if sendClientCommand then sendClientCommand(getPlayer(), "DunKa", "helloBoxes", {}) end
end
Events.OnGameStart.Add(dunkaHelloBoxes)
Events.EveryOneMinute.Add(dunkaHelloBoxes)
