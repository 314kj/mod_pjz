-- Cookie Helper : guest guard
-- While a player visits a safehouse as a guest they are a temporary member (so the vanilla
-- trespass check lets them in). This guard stops everything that takes, breaks or removes
-- things inside that house. Role decides the extra things allowed:
--   doctor  = medical only (always allowed for everyone anyway)
--   builder = build / place / rotate furniture / paint / plaster / barricade
--   keeper  = animals, plants, generators, cleaning, water from the house
-- This is a client-side deterrent for a whitelisted PVE server, not anti-cheat: on the server a
-- guest is a normal member while the visit lasts.
-- One table lookup per queued action, and only for a player who is currently a guest.
if isServer() then return end

require "TimedActions/ISTimedActionQueue"
require "CookieHelper/CH_Client"

local C = CHelp.Cl
local t = CHelp.t
local floor = math.floor

local function set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

-- taking / destroying: blocked for every guest role
local ALWAYS = set({
    "ISGrabItemAction", "ISGrabCorpseItem", "ISTakeFuel", "ISTakeGenerator", "ISTakeCarBatteryChargerAction",
    "ISTakeTrap", "ISTakeBricks", "ISGetCompost", "ISRemoveLightSourceFuelAction", "ISItemSlotRemoveAction",
    "ISDestroyStuffAction", "ISDismantleAction", "ISUnbarricadeAction", "ISSmashWindow", "ISRemoveSheetAction",
    "ISRemoveSheetRope", "ISChopTreeAction", "ISPickAxeGroundCoverItem", "ISRemoveBush", "ISEmptyRainBarrelAction",
    "ISUninstallVehiclePart", "ISTakeGasolineFromVehicle", "ISTakeEngineParts", "ISSmashVehicleWindow",
    "ISDeflateTire", "ISRemoveBurntVehicle", "ISHotwireVehicle",
    "ISHarvestPlantAction", "ISHutchGrabAnimal", "ISHutchGrabEgg", "ISHutchGrabCorpseAction", "ISPickupAnimal",
    "ISButcherAnimal", "ISKillAnimal", "ISKillAnimalInInventory", "ISMilkAnimal", "ISShearAnimal",
    "ISGatherBloodFromAnimal", "ISRemoveMeatFromAnimal", "ISRemoveLeatherFromAnimal", "ISRemoveHeadFromAnimal",
    "ISGetAnimalBones", "ISCutAnimalOnHook", "ISPutAnimalOnHook", "ISRemoveAnimalFromHook",
    "ISAttachAnimalToPlayer", "ISAddAnimalInTrailer", "ISRemoveAnimalFromTrailer",
    -- crafting pulls ingredients from the boxes around you, i.e. the host's stock
    "ISHandcraftAction",
})

local BUILD = set({
    "ISBuildAction", "ISMultiStageBuild", "ISPaintAction", "ISPaintSignAction", "ISPlasterAction",
    "ISWallpaperAction", "ISBarricadeAction", "ISExtendedPlacementAction",
    "ISInstallVehiclePart", "ISFixGenerator", "ISShovelGround",
})

local CARE = set({
    "ISFeedAnimalFromHand", "ISGiveWaterToAnimal", "ISPetAnimal", "ISHutchCleanFloor", "ISHutchCleanNest",
    "ISToggleHutchDoor", "ISToggleHutchEggHatchDoor", "ISLureAnimal", "ISAttachAnimalToTree",
    "ISWaterPlantAction", "ISFertilizeAction", "ISCurePlantAction", "ISSeedActionNew", "ISPlowAction",
    "ISShovelAction", "ISAddCompost", "ISItemSlotAddAction", "ISAddFuel", "ISActivateGenerator",
    "ISPlugGenerator", "ISCleanBlood", "ISCleanGraffiti", "ISScything", "ISRemoveGrass",
    -- water/fluids from the host's barrels and sinks (watering cans for the garden)
    "ISFluidTransferAction", "ISTakeWaterAction", "ISDumpWaterAction", "ISTransferWaterAction",
})

-- returns (guestRecord, safehouse) when this character is a guest standing in the host house
local function guestHere(character)
    if not character or not instanceof(character, "IsoPlayer") then return nil end
    if not character:isLocalPlayer() then return nil end
    local g = C.guests[character:getUsername()]
    if not g then return nil end
    local sh = CHelp.shByKey(g.sh)
    if not sh then return nil end
    if CHelp.shDist(sh, floor(character:getX()), floor(character:getY())) > 1 then return nil end
    return g, sh
end

local function verdict(action)
    local g = guestHere(action.character)
    if not g then return nil end
    local ty = action.Type
    if ty == "ISInventoryTransferAction" then
        local src = action.srcContainer
        if src and not src:isInCharacterInventory(action.character) then return "Guard_NoTake" end
        return nil
    end
    if ty == "ISMoveablesAction" then
        if action.mode == "pickup" or action.mode == "scrap" then return "Guard_NoTake" end
        if (action.mode == "place" or action.mode == "rotate") and g.role ~= CHelp.ROLE_BUILDER then return "Guard_BuilderOnly" end
        return nil
    end
    if ALWAYS[ty] then return "Guard_NoTake" end
    if BUILD[ty] and g.role ~= CHelp.ROLE_BUILDER then return "Guard_BuilderOnly" end
    if CARE[ty] and g.role ~= CHelp.ROLE_KEEPER then return "Guard_KeeperOnly" end
    return nil
end

local lastWarn = 0
local function check(action)
    if type(action) ~= "table" then return false end
    local ok, why = pcall(verdict, action)
    if not ok or not why then return false end
    local ms = CHelp.nowMs()
    if ms - lastWarn > 1200 then
        lastWarn = ms
        HaloTextHelper.addBadText(action.character, t(why))
    end
    return true
end

local origAdd = ISTimedActionQueue.add
ISTimedActionQueue.add = function(action)
    if check(action) then return nil end
    return origAdd(action)
end

local origAfter = ISTimedActionQueue.addAfter
ISTimedActionQueue.addAfter = function(previousAction, action)
    if check(action) then return nil end
    return origAfter(previousAction, action)
end
