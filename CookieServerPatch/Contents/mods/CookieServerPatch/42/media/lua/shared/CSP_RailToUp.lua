--[[
CookieServerPatch - CSP_RailToUp  (Guns of Marz / Gunworks)

Problem on the CookieCheetah MP server:
  Installing the generic "Picatinny Rail" (MarzGuns.Picatinny_Rail) through
  Add Weapon Upgrade -> Picatinny Rail -> Up/Down/Left/Right loses the chosen
  direction on the server, so the generic item itself lands in the
  "GenericRail" slot (tooltip shows "Railing: Picatinny Rail").
  Scopes require MarzGuns.Picatinny_Rail_Up, so no scope can be installed.

What this patch does:
  1. When that upgrade completes and no direction arrived, it picks one:
     Up first, otherwise the first free direction the gun supports.
  2. Guns that already carry a generic rail are converted the same way when
     the player equips them, and once shortly after login (whole inventory).
  3. If a gun has no free direction (or does not take Picatinny at all),
     the generic rail is taken off and given back, so nothing is lost.
  Rails installed correctly (any direction) are never touched.
]]

CSP_RailToUp = CSP_RailToUp or {}
local M = CSP_RailToUp

local GENERIC      = "MarzGuns.Picatinny_Rail"
local GENERIC_SLOT = "GenericRail"
local PREFERRED    = "MarzGuns.Picatinny_Rail_Up"
local CMD_MODULE   = "CookieServerPatch"
local CMD_NAME     = "RailToUp"

local function log(msg)
    print("[CSP_RailToUp] " .. tostring(msg))
end

local function req(path)
    local ok, mod = pcall(require, path)
    if ok and type(mod) == "table" then return mod end
    return nil
end

local function partTypeOf(fullType)
    local item = instanceItem(fullType)
    if item and instanceof(item, "WeaponPart") then
        return item:getPartType()
    end
    return nil
end

--- The generic rail installed on this gun, or nil.
function M.getGenericRail(weapon)
    if not weapon or not instanceof(weapon, "HandWeapon") then return nil end
    local part = weapon:getWeaponPart(GENERIC_SLOT)
    if part and part:getFullType() == GENERIC then return part end
    return nil
end

--- Direction to use for this gun: Up first, then the gun's other directions
--- in GoM's own order. Skips occupied slots and anything Gunworks would block.
--- No tool check here: converting a rail that is already on the gun.
function M.pickOutcome(weapon)
    local UA = req("WeaponSystems/Utils/UniversalAttachment")
    if not UA or not UA.GetOutcomes then return nil end
    local outcomes = UA.GetOutcomes(weapon, GENERIC)
    if not outcomes then return nil end

    local ordered = {}
    for _, outcome in ipairs(outcomes) do
        if outcome == PREFERRED then
            table.insert(ordered, 1, outcome)
        else
            ordered[#ordered + 1] = outcome
        end
    end

    local RA = req("WeaponSystems/Utils/RequiredAttachment")
    local UE = req("WeaponSystems/Utils/UpgradeExclusives")

    for _, outcome in ipairs(ordered) do
        local slot = partTypeOf(outcome)
        if slot and weapon:getWeaponPart(slot) == nil then
            local blocked = false
            if RA and RA.IsInstallationBlocked then
                local ok, res = pcall(RA.IsInstallationBlocked, weapon, outcome)
                blocked = ok and res == true
            end
            if not blocked and UE and UE.IsBlockedByExclusive then
                local ok, res = pcall(UE.IsBlockedByExclusive, weapon, outcome)
                blocked = ok and res == true
            end
            if not blocked then return outcome, slot end
        end
    end
    return nil
end

local function detachGeneric(weapon, character, part)
    if character then pcall(weapon.detachWeaponPart, weapon, character, part) end
    if M.getGenericRail(weapon) then pcall(weapon.detachWeaponPart, weapon, part) end
    return M.getGenericRail(weapon) == nil
end

local function attachPart(weapon, character, newPart, slot)
    if character then pcall(weapon.attachWeaponPart, weapon, character, newPart) end
    if weapon:getWeaponPart(slot) == nil then pcall(weapon.attachWeaponPart, weapon, newPart, true) end
    return weapon:getWeaponPart(slot) ~= nil
end

local function giveBackGeneric(character)
    if not character then return end
    local inv = character:getInventory()
    local item = inv:AddItem(GENERIC)
    if item and isServer() then sendAddItemToContainer(inv, item) end
end

local function afterChange(weapon, character)
    local SF = req("WeaponSystems/Utils/StatsFactory")
    if SF and SF.ReapplyAllModifiers then pcall(SF.ReapplyAllModifiers, weapon) end

    if isServer() then
        if not character then return end
        local SS = req("WeaponSystems/Utils/StatsSync")
        if SS and SS.SendToClients then
            pcall(SS.SendToClients, character, weapon)   -- syncHandWeaponFields + sendEquip
        else
            pcall(syncHandWeaponFields, character, weapon)
        end
    elseif character and character.resetEquippedHandsModels then
        pcall(character.resetEquippedHandsModels, character)
    end
end

--- Swap a generic rail on this gun for a directional one. Runs where the item
--- is authoritative: the server in MP, the local game in SP.
function M.fixWeapon(weapon, character)
    local generic = M.getGenericRail(weapon)
    if not generic then return false end

    local outcome, slot = M.pickOutcome(weapon)
    if not detachGeneric(weapon, character, generic) then
        log("could not detach generic rail from " .. weapon:getFullType())
        return false
    end

    local ok = false
    if outcome then
        local newPart = instanceItem(outcome)
        if newPart and instanceof(newPart, "WeaponPart") then
            ok = attachPart(weapon, character, newPart, slot)
        end
    end
    if not ok then giveBackGeneric(character) end

    afterChange(weapon, character)

    local who = character and character.getUsername and character:getUsername() or "?"
    if ok then
        log(who .. ": " .. weapon:getFullType() .. " generic rail -> " .. outcome)
    else
        log(who .. ": " .. weapon:getFullType() .. " no free rail slot, generic rail returned")
    end
    return ok
end

-------------------------------------------------
-- 1) New installs: fill in the lost direction
-------------------------------------------------
local hookInstalled = false

function M.installUpgradeHook()
    if hookInstalled then return end
    if not ISUpgradeWeapon then pcall(require, "TimedActions/ISUpgradeWeapon") end
    if not ISUpgradeWeapon or not ISUpgradeWeapon.complete then return end
    hookInstalled = true

    local original = ISUpgradeWeapon.complete
    function ISUpgradeWeapon:complete()
        local isGeneric = self.part ~= nil and self.part:getFullType() == GENERIC
        if isGeneric and self.weapon and not self.outcomeFullType then
            local outcome = M.pickOutcome(self.weapon)
            if outcome then self.outcomeFullType = outcome end
        end

        local result = original(self)

        -- Safety net: if the generic item still ended up on the gun, convert it now.
        if isGeneric and self.weapon then
            pcall(M.fixWeapon, self.weapon, self.character)
        end
        return result
    end
    log("upgrade hook installed")
end

-- Install after every mod's Lua has loaded, so this wraps Gunworks' own hook.
Events.OnGameBoot.Add(M.installUpgradeHook)
if Events.OnServerStarted then Events.OnServerStarted.Add(M.installUpgradeHook) end
Events.OnInitGlobalModData.Add(M.installUpgradeHook)

-------------------------------------------------
-- 2) Guns already carrying a generic rail
-------------------------------------------------
local lastSent = {}

local function requestFix(player, weapon)
    if not M.getGenericRail(weapon) then return end
    if isClient() then
        local id = weapon:getID()
        local now = getTimestampMs()
        if lastSent[id] and now - lastSent[id] < 5000 then return end
        lastSent[id] = now
        sendClientCommand(player, CMD_MODULE, CMD_NAME, { itemId = id })
    elseif not isServer() then
        M.fixWeapon(weapon, player)   -- singleplayer
    end
end

local function onEquip(character, item)
    if isServer() then return end
    if not character or not item or not character:isLocalPlayer() then return end
    if instanceof(item, "HandWeapon") then requestFix(character, item) end
end

Events.OnEquipPrimary.Add(onEquip)

local function scanInventory(player)
    local inv = player and player:getInventory()
    if not inv then return end
    local ok, list = pcall(inv.getAllEvalRecurse, inv, function(it)
        return instanceof(it, "HandWeapon") and M.getGenericRail(it) ~= nil
    end)
    if not ok or not list then return end
    for i = 0, list:size() - 1 do
        requestFix(player, list:get(i))
    end
end

local scanTicks = -1
local function onTickScan()
    if scanTicks < 0 then return end
    scanTicks = scanTicks - 1
    if scanTicks > 0 then return end
    scanTicks = -1
    Events.OnTick.Remove(onTickScan)
    local player = getSpecificPlayer(0)
    if player then scanInventory(player) end
end

Events.OnGameStart.Add(function()
    if isServer() then return end
    scanTicks = 600   -- ~10 s after login, once
    Events.OnTick.Add(onTickScan)
end)

-------------------------------------------------
-- Server side of the request
-------------------------------------------------
local function onClientCommand(module, command, player, args)
    if module ~= CMD_MODULE or command ~= CMD_NAME then return end
    if not player or type(args) ~= "table" or not args.itemId then return end
    local weapon = player:getInventory():getItemWithIDRecursiv(args.itemId)
    if weapon and instanceof(weapon, "HandWeapon") then
        M.fixWeapon(weapon, player)
    end
end

if isServer() then
    Events.OnClientCommand.Add(onClientCommand)
end
