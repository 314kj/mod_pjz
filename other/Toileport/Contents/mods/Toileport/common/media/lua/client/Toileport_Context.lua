--[[ ============================================================
  TOILEPORT  [MP]  --  world context menu               KACHASIG
  Right-click a base-game toilet:
    * PLAYER : "Use Ticket >" lists tickets in inventory this
               station accepts, each showing its destination.
    * ADMIN  : register / set-as-destination-for-ticket /
               allowed-tickets / rename / unregister.
  All admin config is in-world (no window): standing at / clicking
  the destination toilet binds it to a ticket -- matches "define a
  ticket's destination by the XY of the placed toilet".
  Whole handler is pcall-wrapped so one bad line can't wipe the menu.
============================================================ ]]

require "ISUI/ISContextMenu"
require "ISUI/ISTextBox"
require "AKA_Menu"
require "Toileport_Shared"

local TP = Toileport

----------------------------------------------------------------
-- SP-aware admin check (lowercase whitelist, never a "None" blacklist)
----------------------------------------------------------------
local function isAdminLike()
    if TP.isSP() then return true end
    local pl = getPlayer()
    local lvl
    if pl and pl.getAccessLevel then
        pcall(function() lvl = string.lower(tostring(pl:getAccessLevel() or "")) end)
    end
    if lvl == "admin" or lvl == "moderator" or lvl == "gm" then return true end
    return (isAdmin and isAdmin() == true) or false
end

----------------------------------------------------------------
-- find the toilet object (+ its square) among clicked world objects
----------------------------------------------------------------
local function findToilet(worldobjects)
    for _, wo in ipairs(worldobjects) do
        local s = wo.getSquare and wo:getSquare() or nil
        if s then
            local objs = s:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                local spr = o and o.getSprite and o:getSprite()
                local sn = spr and spr.getName and spr:getName() or nil
                -- TP.DEBUG = true เพื่อดู sprite names ใน console
                if TP.DEBUG and sn then
                    print("[Toileport DEBUG] sprite: " .. tostring(sn))
                end
                if TP.isToiletSprite(sn) then
                    return s, o, sn
                end
            end
        end
    end
    return nil, nil, nil
end

local function ticketLabel(i)
    return "Ticket " .. string.format("%02d", i)
end

----------------------------------------------------------------
-- menu builders
----------------------------------------------------------------
local function buildPlayerUse(g, pl, sq, station)
    local inv = pl:getInventory()
    local cfg = TP.getConfig()

    local useParent = g:addOption("Use Ticket", nil, nil)
    local useSub    = ISContextMenu:getNew(g)
    g:addSubMenu(useParent, useSub)

    local any = false
    for i = 1, TP.TICKET_COUNT do
        local ft = TP.ticketFullType(i)
        local cnt = inv:getItemCount(ft)
        if cnt > 0 and TP.stationAccepts(station, ft) then
            any = true
            local dest = TP.ticketDestStation(cfg, ft)
            if dest then
                local label = (dest.name or ticketLabel(i)) .. "   x" .. cnt
                useSub:addOption(label, pl, function(p) TP.useTicket(p, sq, ft) end)
            else
                local o = useSub:addOption(ticketLabel(i) .. "  (no destination)", nil, nil)
                o.notAvailable = true
            end
        end
    end
    if not any then
        local o = useSub:addOption("No usable tickets here", nil, nil)
        o.notAvailable = true
    end
end

----------------------------------------------------------------
-- event
----------------------------------------------------------------
-- find the closest square from clicked objects (fallback for force-register)
local function anySquare(worldobjects)
    for _, wo in ipairs(worldobjects) do
        local s = wo.getSquare and wo:getSquare() or nil
        if s then return s end
    end
    return nil
end

local function onWorldMenu(playerIdx, context, worldobjects, test)
    if test then return end
    local ok, err = pcall(function()
        local pl = getSpecificPlayer(playerIdx)
        if not pl then return end

        local sq, _toilet, _sprite = findToilet(worldobjects)
        local admin = isAdminLike()

        if sq then
            -- recognized toilet sprite found
            local key = TP.squareKey(sq:getX(), sq:getY(), sq:getZ())
            local station = TP.getStationByKey(key)
            local g = AKA.getGroup(context, "Toileport")

            if station then
                buildPlayerUse(g, pl, sq, station)
                if admin then
                    g:addOption("[Admin] Open Toileport Panel", pl, function(p) ToileportPanel.open(p) end)
                end
            elseif admin then
                g:addOption("[Admin] Register this toilet", pl, function(p) TP.adminRegister(p, sq) end)
                g:addOption("[Admin] Open Toileport Panel", pl, function(p) ToileportPanel.open(p) end)
            end
        elseif admin then
            -- no recognized toilet sprite -- offer Force Register for custom tiles
            local anySq = anySquare(worldobjects)
            if anySq then
                local g = AKA.getGroup(context, "Toileport")
                local key = TP.squareKey(anySq:getX(), anySq:getY(), anySq:getZ())
                local station = TP.getStationByKey(key)
                if station then
                    -- already registered as a station (force-registered before)
                    buildPlayerUse(g, pl, anySq, station)
                    g:addOption("[Admin] Open Toileport Panel", pl, function(p) ToileportPanel.open(p) end)
                else
                    g:addOption("[Admin] Force Register as Station", pl, function(p) TP.adminForceRegister(p, anySq) end)
                    g:addOption("[Admin] Open Toileport Panel", pl, function(p) ToileportPanel.open(p) end)
                end
            end
        end
    end)
    if not ok then
        print("[Toileport] ERROR world menu: " .. tostring(err))
    end
end

Events.OnFillWorldObjectContextMenu.Remove(onWorldMenu)
Events.OnFillWorldObjectContextMenu.Add(onWorldMenu)

print("[Toileport] context menu ready")
