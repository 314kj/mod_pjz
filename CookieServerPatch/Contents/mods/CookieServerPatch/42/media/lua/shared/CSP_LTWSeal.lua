-- CookieServerPatch: Legendary Tactical Weapons (LTW) need a seal to craft.
--
-- scripts/generated/recipes/LTW_Recipes.txt in this mod replaces LTW's own file
-- (same path, CookieServerPatch loads after LTW). In it the 9 Forge_* and 11
-- Make* recipes also need CSP.LTWForgeSeal (scripts/CSP_items.txt). The seal is
-- in no loot table, so even a player who knows every recipe cannot craft an LTW
-- weapon. LTW weapons come from Cookie Mission; repair (RepairLTWSheet /
-- RepairLTWScrap) and opening the sealed cases are unchanged.
--
-- This file:
--   1. server: keeps the seal out of every PhunMart machine;
--   2. logs how many LTW recipes really need the seal:
--      "[CookieServerPatch] ltw-seal on: seal in 20/20 LTW recipes"
--      0/20 means LTW's own recipe file is in use (CookieServerPatch must load
--      after LTW in the mod list).
-- ASCII only. No next() (Kahlua).

local TAG = "[CookieServerPatch] ltw-seal"
local SEAL = "CSP.LTWForgeSeal"
local RECIPES = {
    "Forge_LegendaryTacticalSwordBlade", "Forge_LegendaryTacticalAxeHead", "Forge_LegendaryTacticalDoubleAxeHead",
    "Forge_LegendaryTacticalBar", "Forge_LegendaryTacticalBatHead", "Forge_LegendaryTacticalHammerHead",
    "Forge_LegendaryTacticalKnifeBlade", "Forge_LegendaryTacticalSledgehammerHead", "Forge_LegendaryTacticalSpearHead",
    "MakeLegendaryTacticalSword", "MakeLegendaryTacticalTomahawk", "MakeLegendaryTacticalAxe",
    "MakeLegendaryTacticalCrowbar", "MakeLegendaryTacticalBat", "MakeLegendaryTacticalHammer",
    "MakeLegendaryTacticalKnife", "MakeLegendaryTacticalSledgehammer", "MakeLegendaryTacticalSpear",
    "MakeLegendarySwordSheath", "MakeLegendaryKnifeSheath",
}

local function findRecipe(sm, name)
    local r = nil
    pcall(function() r = sm:getCraftRecipe(name) end)
    if not r then pcall(function() r = sm:getCraftRecipe("Base." .. name) end) end
    return r
end

-- returns found, total, missingNames (nil when the script manager is not there)
local function countSeal()
    local sm = getScriptManager and getScriptManager()
    if not sm then return nil end
    local seal = nil
    pcall(function() seal = sm:getItem(SEAL) end)
    if not seal then return -1, 0, {} end
    local found, total, missing = 0, 0, {}
    for _, name in ipairs(RECIPES) do
        local r = findRecipe(sm, name)
        if r then
            total = total + 1
            local has = false
            pcall(function()
                local ins = r:getInputs()
                for i = 0, ins:size() - 1 do
                    if ins:get(i):containsItem(seal) then has = true end
                end
            end)
            if has then found = found + 1 else missing[#missing + 1] = name end
        end
    end
    return found, total, missing
end

local function report(when)
    local found, total, missing = countSeal()
    if found == nil then return end
    if found == -1 then
        print(TAG .. ": item " .. SEAL .. " not loaded (scripts/CSP_items.txt missing?)")
        return
    end
    if total == 0 then
        print(TAG .. ": LTW recipes not found (LTW not loaded?), nothing to check")
        return
    end
    local line = TAG .. " on (" .. when .. "): seal in " .. found .. "/" .. total .. " LTW recipes"
    if found < total then
        line = line .. " - WITHOUT seal: " .. table.concat(missing, ", ")
    end
    print(line)
end

local function hideFromPhunMart()
    if isClient() then return end
    local Core = PhunMart
    if type(Core) ~= "table" or type(Core.getBlacklist) ~= "function" then return end
    if Core.cspLTWSeal then return end
    local orig = Core.getBlacklist
    Core.getBlacklist = function(...)
        local list = orig(...)
        if type(list) == "table" then
            list.items = list.items or {}
            list.items.exclude = list.items.exclude or {}
            list.items.exclude[SEAL] = true
        end
        return list
    end
    Core.cspLTWSeal = true
end

Events.OnGameBoot.Add(hideFromPhunMart)
if Events.OnServerStarted then
    Events.OnServerStarted.Add(function() report("server") end)
end
Events.OnGameStart.Add(function()
    if not isServer() then report("client") end
end)
