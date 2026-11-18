-- CookieServerPatch: vanilla 42.22.2 ISReloadWeaponAction.setReloadSpeed,
-- no error when a reload-fast item is worn without an ammo strap.
--
-- Vanilla reads strap:getClothingItemName() without checking that an ammo
-- strap is worn. It throws "attempted index: getClothingItemName of non-table"
-- when the player wears a chest rig, ALICE belt or shoulder holster (tag
-- reloadfastmagazines) but no ammo strap, while holding a gun with no magazine
-- type (loose rounds) or one that takes shotgun shells. Every action that sets
-- the reload speed (vanilla reload, rack, unload, magazine load/insert/eject,
-- and Gunworks' reload hooks) stops there.
--
-- When vanilla throws that error, it is run again with the reload-fast tags
-- hidden from it. With no strap worn those tags give no bonus on that gun, so
-- the speed comes out as vanilla means it (skill, panic, driving). When vanilla
-- does not throw, nothing changes; once the game fixes the bug this file does
-- nothing. Shared, so the server side of the action is covered too.
-- save-bound: no
--
-- Log: "[CSP] reload-strap on" once, then "[CSP] reload-strap: stepped in" the first time.
-- To undo: remove this file.

local TAG = "[CSP] reload-strap"

if not ISReloadWeaponAction or not ISReloadWeaponAction.setReloadSpeed then
    print(TAG .. ": setReloadSpeed not found, off")
    return
end
local orig = ISReloadWeaponAction.setReloadSpeed
local said = false

local function isFastTag(tag)
    return tag == ItemTag.RELOAD_FAST_SHELLS or tag == ItemTag.RELOAD_FAST_BULLETS
        or tag == ItemTag.RELOAD_FAST_MAGAZINES
end

-- Stands in for obj: a call goes to obj unless over has a function by that name.
local function standIn(obj, over)
    return setmetatable({}, { __index = function(_, k)
        if over[k] then return over[k] end
        local f = obj[k]
        return function(_, ...) return f(obj, ...) end
    end })
end

local function withoutFastTags(character)
    local me
    me = standIn(character, {
        hasEquippedTag = function(_, tag) return not isFastTag(tag) and character:hasEquippedTag(tag) end,
        hasWornTag = function(_, tag) return not isFastTag(tag) and character:hasWornTag(tag) end,
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
    local r = { pcall(orig, character, ...) }
    if r[1] then return unpack(r, 2) end
    if character:getWornItem(ItemBodyLocation.AMMO_STRAP)
        or not string.find(tostring(r[2]), "getClothingItemName", 1, true) then
        return orig(character, ...) -- some other error: let it show as before
    end
    if not said then
        said = true
        print(TAG .. ": stepped in")
    end
    return orig(withoutFastTags(character), ...)
end

print(TAG .. " on")
