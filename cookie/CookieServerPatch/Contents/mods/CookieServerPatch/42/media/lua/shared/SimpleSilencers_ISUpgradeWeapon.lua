-- CookieServerPatch: replaces Simple Silencers' (3309896124) shared/SimpleSilencers_ISUpgradeWeapon.lua.
-- Same path on purpose: CSP loads after Simple Silencers, so this file runs in its place, at the same
-- point in the load order (right after Gunworks / Guns of Marz in the CookieCheetah mod list).
--
-- Problem (9 Nov 2026, "muzzle won't go on the CAR-15"):
--   Simple Silencers' file does `ISUpgradeWeapon = ISBaseTimedAction:derive(...)` and writes the whole
--   action again. It loads after Gunworks (SWMG), so it throws away everything Gunworks hooked onto
--   ISUpgradeWeapon (WeaponSystems/Hooks/WeaponUpgradeHooks.lua):
--    * isValid: Gunworks / vanilla check part:canAttach -> Guns of Marz tools per slot
--      (muzzle + muzzle mount = wrench, scopes/rails = screwdriver). Simple Silencers' version skips
--      that and asks every part for a screwdriver instead, so a GoM muzzle that the menu offered
--      (wrench in the bag) fails as soon as the action starts if there is no screwdriver.
--    * new(): Gunworks passes the chosen outcome of a universal kit (Picatinny Rail Up/Down/...);
--      Simple Silencers' new() drops it, so the plain rail item lands on the gun
--      (the bug CSP_RailToUp.lua works around).
--    * complete(): Gunworks reapplies the attachment stats and syncs them; that step was lost too.
--   Simple Silencers rewrote the action only so its own suppressors can go on: they use a placeholder
--   MountOn (SilencerMountOn / CraftedSilencerMountOn), which the normal canAttach check refuses.
--
-- This file keeps the action Gunworks built (vanilla + Gunworks hooks) and adds Simple Silencers' rule
-- back for Simple Silencers' own suppressors only: screwdriver in the inventory, muzzle slot free,
-- both items in the inventory. Every other part follows Gunworks / vanilla as its authors intended.
-- Simple Silencers' context menu, models and sounds are untouched.

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISUpgradeWeapon"

local TAG = "[CookieServerPatch] silencer-upgrade"

if type(ISUpgradeWeapon) ~= "table" or type(ISUpgradeWeapon.isValid) ~= "function" then
    print(TAG .. " ISUpgradeWeapon not found, patch off")
    return
end

local function predicateNotBroken(item)
    return not item:isBroken()
end

local SS_TYPES = { ["Base.Silencer"] = true, ["Base.MetalPipeSilencer"] = true }

-- Simple Silencers' suppressors: their MountOn is the placeholder item, not a real gun
local function isSimpleSilencerPart(part)
    if not part then return false end
    local ok, result = pcall(function()
        if SS_TYPES[part:getFullType()] then return true end
        local mountOn = part:getMountOn()
        if not mountOn then return false end
        for i = 0, mountOn:size() - 1 do
            local name = tostring(mountOn:get(i))
            if string.find(name, "SilencerMountOn$") then return true end
        end
        return false
    end)
    return ok and result == true
end

-- Simple Silencers' own check, kept for its suppressors
local function simpleSilencerValid(self)
    local inv = self.character:getInventory()
    if not inv:containsTagEval(ItemTag.SCREWDRIVER, predicateNotBroken) then return false end
    if self.weapon:getWeaponPart(self.part:getPartType()) then return false end
    if isClient() then
        return inv:containsID(self.part:getID()) and inv:containsID(self.weapon:getID())
    end
    return inv:contains(self.part)
end

local original_isValid = ISUpgradeWeapon.isValid
function ISUpgradeWeapon:isValid()
    if not self.outcomeFullType and self.weapon and isSimpleSilencerPart(self.part) then
        return simpleSilencerValid(self)
    end
    return original_isValid(self)
end

print(TAG .. " on (Gunworks upgrade action kept, Simple Silencers rule for its suppressors only)")
