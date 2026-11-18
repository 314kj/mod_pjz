-- CookieServerPatch: vanilla 42.22.2 ISReloadWeaponAction.setReloadSpeed,
-- no error when a reload-fast item is worn without an ammo strap.
--
-- Vanilla reads strap:getClothingItemName() without checking that an ammo
-- strap is worn. It throws "attempted index: getClothingItemName of non-table"
-- when the player wears a chest rig, ALICE belt or shoulder holster (tag
-- reloadfastmagazines) but no ammo strap, while holding a gun with no magazine
-- type (loose rounds) or one that takes shotgun shells. Every action that sets
-- the reload speed (vanilla reload, rack, unload, magazine load/insert/eject,
-- and Gunworks' reload hooks) stops there, before ReloadSpeed is set.
--
-- When a reload-fast tag is held or worn and no ammo strap is worn, vanilla is
-- run on a stand-in whose ammo strap slot holds an empty strap: no clothing
-- item, no name. Vanilla then takes the branch it means for "no strap", so the
-- speed comes out as vanilla means it (skill, panic, driving, and the rig's
-- magazine bonus). Every other call goes to the original unchanged; once the
-- game fixes the bug this file changes nothing.
--
-- The check runs before the call, not on the error: Fast Reload (3775418723)
-- calls vanilla inside its own pcall, so the error never reaches a wrapper
-- around it. This file is in CookieEarlyHooks so it loads before Fast Reload,
-- which then keeps this function as "vanilla" for all its calls, magazine
-- actions included. Shared, so the server side of the action is covered too.
-- save-bound: no
--
-- Log: "[CSP] reload-strap on" once, then "[CSP] reload-strap: stepped in" the first time.
-- To undo: remove this file.

require "TimedActions/ISReloadWeaponAction"

local TAG = "[CSP] reload-strap"

if not ISReloadWeaponAction or not ISReloadWeaponAction.setReloadSpeed
    or not ItemTag or not ItemTag.RELOAD_FAST_SHELLS or not ItemTag.RELOAD_FAST_BULLETS
    or not ItemTag.RELOAD_FAST_MAGAZINES or not ItemBodyLocation or not ItemBodyLocation.AMMO_STRAP then
    print(TAG .. ": setReloadSpeed or its tags not found, off")
    return
end
local orig = ISReloadWeaponAction.setReloadSpeed
local said = false

local FAST = { ItemTag.RELOAD_FAST_SHELLS, ItemTag.RELOAD_FAST_BULLETS, ItemTag.RELOAD_FAST_MAGAZINES }

-- Stands in for obj: a call goes to obj unless over has a function by that name.
local function standIn(obj, over)
    return setmetatable({}, { __index = function(_, k)
        if over[k] then return over[k] end
        local f = obj[k]
        return function(_, ...) return f(obj, ...) end
    end })
end

-- An ammo strap that is not there: every method returns nil.
local noStrap = setmetatable({}, { __index = function() return function() return nil end end })

-- Vanilla can only reach the strap's name with a reload-fast tag and no strap.
local function needsStandIn(character)
    if character:getWornItem(ItemBodyLocation.AMMO_STRAP) then return false end
    for i = 1, #FAST do
        if character:hasEquippedTag(FAST[i]) or character:hasWornTag(FAST[i]) then return true end
    end
    return false
end

local function withEmptyStrap(character)
    local me
    me = standIn(character, {
        getWornItem = function(_, location)
            if location == ItemBodyLocation.AMMO_STRAP then return noStrap end
            return character:getWornItem(location)
        end,
        -- vanilla checks getVehicle():getDriver() == character for the driver penalty
        getVehicle = function(_)
            local v = character:getVehicle()
            if not v then return nil end
            return standIn(v, { getDriver = function(_)
                local d = v:getDriver()
                if d == character then return me end
                return d
            end })
        end,
    })
    return me
end

function ISReloadWeaponAction.setReloadSpeed(character, ...)
    if not character or not needsStandIn(character) then
        return orig(character, ...)
    end
    if not said then
        said = true
        print(TAG .. ": stepped in")
    end
    return orig(withEmptyStrap(character), ...)
end

print(TAG .. " on")
