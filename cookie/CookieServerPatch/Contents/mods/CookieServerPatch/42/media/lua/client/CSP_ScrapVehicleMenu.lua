-- CookieServerPatch: "Dismantle Vehicle" option on working vehicles.
-- Rules and the action are in shared/CSP_ScrapVehicle.lua.
--
-- Wraps ISVehicleMenu.FillMenuOutsideVehicle: after the vanilla menu is built,
-- a vehicle that is not a wreck gets one more option, with a tooltip in the
-- same style as vanilla "Dismantle Car Wreck" (mask, torch uses) plus the
-- Mechanics / Electrical levels and the reasons it cannot be done yet.
-- Wrecks keep the vanilla option only.
-- ASCII only. No next() (Kahlua).

require "Vehicles/ISUI/ISVehicleMenu"

if not (CSPScrap and CSPScrapVehicle) then return end
if ISVehicleMenu.CSP_scrap then return end
ISVehicleMenu.CSP_scrap = true

local WHITE, RED = " <RGB:1,1,1> ", " <RGB:1,0,0> "

local function isMask(item)
    return item:hasTag(ItemTag.WELDING_MASK) or item:getType() == "WeldingMask"
end

local function isTorch(item)
    return (item:hasTag(ItemTag.BLOW_TORCH) or item:getType() == "BlowTorch") and item:getCurrentUses() >= 10
end

local function mostUses(a, b)
    return a:getCurrentUses() - b:getCurrentUses()
end

local function line(ok, text)
    return " <LINE> " .. (ok and WHITE or RED) .. text
end

local function onScrap(playerObj, vehicle)
    if luautils.walkAdj(playerObj, vehicle:getSquare()) then
        ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), isTorch, true)
        local mask = playerObj:getInventory():getFirstEvalRecurse(isMask)
        if mask then
            ISInventoryPaneContextMenu.wearItem(mask, playerObj:getPlayerNum())
        end
        ISTimedActionQueue.add(CSPScrapVehicle:new(playerObj, vehicle))
    end
end

local function addOption(playerObj, context, vehicle)
    local option = context:addOption(getText("IGUI_CSP_ScrapVehicle"), playerObj, onScrap, vehicle)
    local tip = ISToolTip:new()
    tip:initialise()
    tip:setVisible(false)
    tip:setName(getText("IGUI_CSP_ScrapVehicle"))
    option.toolTip = tip

    local b = CSPScrap.blockers(playerObj, vehicle)
    local d = getText("Tooltip_CSP_ScrapVehicle") .. " <LINE> "

    local mech = playerObj:getPerkLevel(Perks.Mechanics)
    local elec = playerObj:getPerkLevel(Perks.Electricity)
    d = d .. line(not b.mechanics, PerkFactory.getPerkName(Perks.Mechanics) .. " " .. mech .. "/" .. CSPScrap.MECHANICS)
    d = d .. line(not b.electrical, PerkFactory.getPerkName(Perks.Electricity) .. " " .. elec .. "/" .. CSPScrap.ELECTRICAL)

    local inv = playerObj:getInventory()
    local hasMask = inv:containsEvalRecurse(isMask)
    d = d .. line(hasMask, getItemNameFromFullType("Base.WeldingMask") .. " " .. (hasMask and 1 or 0) .. "/1")

    local torch = inv:getBestTypeEvalRecurse("Base.BlowTorch", mostUses)
    local uses = torch and torch:getCurrentUses() or 0
    d = d .. line(uses >= 10, getItemNameFromFullType("Base.BlowTorch") .. " " .. getText("ContextMenu_Uses") .. " " .. uses .. "/10")

    if b.claimed then d = d .. line(false, getText("Tooltip_CSP_ScrapVehicle_Claimed")) end
    if b.claimUnknown then d = d .. line(false, getText("Tooltip_CSP_ScrapVehicle_ClaimWait")) end
    if b.occupied then d = d .. line(false, getText("Tooltip_CSP_ScrapVehicle_Occupied")) end
    if b.items then d = d .. line(false, getText("Tooltip_CSP_ScrapVehicle_Items")) end

    tip.description = d
    option.notAvailable = not (hasMask and uses >= 10 and CSPScrap.allowed(playerObj, vehicle))
end

local original = ISVehicleMenu.FillMenuOutsideVehicle

function ISVehicleMenu.FillMenuOutsideVehicle(player, context, vehicle, test)
    local result = original(player, context, vehicle, test)
    if not test and vehicle and not CSPScrap.isWreck(vehicle) then
        addOption(getSpecificPlayer(player), context, vehicle)
    end
    return result
end
