-- CookieServerPatch: Mythical Katana / Mythical Axe can break, and can be
-- repaired back to full for money from the Cookie Wallet.
--
-- Mythical Items (3816156460) makes its weapons unbreakable in two ways:
--   1. MI.applyGearParams sets ConditionLowerChanceOneIn = 1000000 on the
--      katana and axe scripts;
--   2. MI.fixGear puts condition, head condition and sharpness of every
--      mythical item the player carries back to full, every in-game minute.
-- This file replaces both for the 10 katanas and the axe only. Boots, gloves,
-- ring and flashlight stay as the mod made them.
--
-- How tough: like Frostburn (FS.Frostburn, read live from its script, so the
-- Frostburn sandbox values count) but 20 percent tougher. Each hit loses
-- 1 condition with chance 1 / (ConditionLowerChance + Maintenance skill), so
-- the same lower chance with 1.2 x the condition max gives 1.2 x the hits at
-- every skill level. Frostburn 35 / 1 in 50 -> mythical 42 / 1 in 50.
-- Sharpness and the axe head wear the same way as other bladed weapons
-- (a whetstone still sharpens the katana).
--
-- Broken: the vanilla OnBreak.Katana removes a broken katana and drops
-- katana parts. For a mythical katana that is skipped, so the broken weapon
-- stays in the inventory and can be repaired. The axe has no OnBreak.
--
-- Repair: right-click the weapon (only when condition or head is below full,
-- or it is broken) -> confirm -> the server checks the Cookie Wallet
-- (CookieExchange, in cents), takes COST_CENTS, and sets condition, head
-- condition and sharpness to full. CookieExchange writes the payment to
-- its own log like any other wallet change.
--
-- Log: "[CookieServerPatch] myth-repair on" at load, one line with the
-- durability values, one line per repair.
-- ASCII only. No next() (Kahlua).

local TAG = "[CookieServerPatch] myth-repair"
local MODULE = "CSPMythRepair"
local COST_CENTS = 300000          -- $3,000 (the Cookie Wallet counts cents)
local BASE_ITEM = "FS.Frostburn"   -- break like this weapon ...
local FACTOR = 1.2                 -- ... but this much tougher
local FALLBACK_MAX, FALLBACK_ONEIN = 35, 50

pcall(require, "MythicalItems_Shared")
local MI = MythicalItems
if type(MI) ~= "table" or type(MI.KATANAS) ~= "table" or not MI.AXE then
    print(TAG .. ": Mythical Items not loaded, nothing to do")
    return
end
if MI.CSP_repair then return end
MI.CSP_repair = true

local IS_WEAPON = {}
for _, t in ipairs(MI.KATANAS) do IS_WEAPON[t] = true end
IS_WEAPON[MI.AXE] = true

local function fullType(it)
    local ok, t = pcall(function() return it:getFullType() end)
    if ok then return t end
    return nil
end

local function isWeapon(it)
    local t = it and fullType(it)
    return t ~= nil and IS_WEAPON[t] == true
end

--------------------------------------------------------------
-- Durability
--------------------------------------------------------------

-- condition max and lower chance the mythical weapons should have
local function target()
    local maxC, oneIn = FALLBACK_MAX, FALLBACK_ONEIN
    pcall(function()
        local fs = ScriptManager.instance:getItem(BASE_ITEM)
        if fs then
            local m = tonumber(fs:getConditionMax())
            local c = tonumber(fs:getConditionLowerChance())
            if m and m > 0 then maxC = m end
            if c and c > 0 then oneIn = c end
        end
    end)
    return math.floor(maxC * FACTOR + 0.5), oneIn
end

local appliedKey = nil
local function applyScripts(when)
    local maxC, oneIn = target()
    for t, _ in pairs(IS_WEAPON) do
        pcall(function()
            local sc = ScriptManager.instance:getItem(t)
            if sc then
                sc:setConditionMax(maxC)
                sc:setConditionLowerChance(oneIn)
            end
        end)
    end
    local key = maxC .. "/" .. oneIn
    if appliedKey ~= key then
        appliedKey = key
        print(TAG .. " durability (" .. when .. "): condition max " .. maxC .. ", lower chance 1 in " .. oneIn
            .. " (" .. BASE_ITEM .. " x" .. FACTOR .. ")")
    end
end

-- the mod's own call (OnGameBoot, OnInitGlobalModData) goes through here
local origApply = MI.applyGearParams
MI.applyGearParams = function(...)
    if origApply then pcall(origApply, ...) end
    applyScripts("gear params")
end

local function num0(f, it)
    local ok, v = pcall(f, it)
    if ok then return tonumber(v) end
    return nil
end

-- the mod's restore, kept for the mythical items that stay unbreakable
local function restoreOther(it)
    if instanceof(it, "Clothing") then
        local holes = num0(it.getHolesNumber, it) or 0
        if holes > 0 or it:getCondition() < it:getConditionMax() then
            it:fullyRestore()
        end
        return false
    end
    local changed = false
    if it:getConditionMax() > 0 and it:getCondition() < it:getConditionMax() then
        it:setCondition(it:getConditionMax())
        changed = true
    end
    local headMax = num0(it.getHeadConditionMax, it) or 0
    if headMax > 0 and (num0(it.getHeadCondition, it) or headMax) < headMax then
        it:setHeadCondition(headMax)
        changed = true
    end
    local sharpMax = num0(it.getMaxSharpness, it) or 0
    if sharpMax > 0 and (num0(it.getSharpness, it) or sharpMax) < sharpMax then
        it:setSharpness(sharpMax)
        changed = true
    end
    return changed
end

-- a weapon only gets the new limits; it is never restored for free
local function alignWeapon(it, maxC, oneIn)
    local changed = false
    local oldMax = it:getConditionMax()
    if oldMax ~= maxC then
        local cond = it:getCondition()
        it:setConditionMax(maxC)
        if oldMax > 0 and cond > 0 then
            local scaled = math.floor(cond * maxC / oldMax + 0.5)
            if scaled < 1 then scaled = 1 end
            it:setConditionNoSound(scaled)
        end
        changed = true
    end
    if instanceof(it, "HandWeapon") and it:getConditionLowerChance() ~= oneIn then
        it:setConditionLowerChance(oneIn)
    end
    return changed
end

MI.fixGear = function(p, cfg, sync)
    local inv = p:getInventory()
    if not inv then return end
    local maxC, oneIn = target()
    local treeDamage = MI.axeTreeDamage()
    local items = inv:getAllEvalRecurse(function(it) return MI.isMythicalType(it:getFullType()) end, ArrayList.new())
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local ft = it:getFullType()
        local changed
        if IS_WEAPON[ft] then
            changed = alignWeapon(it, maxC, oneIn)
        else
            changed = restoreOther(it)
        end
        if ft == MI.FLASHLIGHT then
            if it:getCurrentUses() < it:getMaxUses() then
                it:setCurrentUses(it:getMaxUses())
                changed = true
            end
            if it:getLightDistance() ~= cfg.flashlightRange then
                it:setLightDistance(cfg.flashlightRange)
                changed = true
            end
        elseif ft == MI.AXE and it:getTreeDamage() ~= treeDamage then
            it:setTreeDamage(treeDamage)
            changed = true
        end
        if changed and sync and it.syncItemFields then pcall(it.syncItemFields, it) end
    end
end

-- a broken mythical katana stays a (broken) mythical katana
local function guardOnBreak()
    if type(OnBreak) ~= "table" or type(OnBreak.Katana) ~= "function" then return false end
    if OnBreak.CSP_mythGuard then return true end
    local orig = OnBreak.Katana
    OnBreak.Katana = function(item, player)
        if isWeapon(item) then return end
        return orig(item, player)
    end
    OnBreak.CSP_mythGuard = true
    return true
end

guardOnBreak()
applyScripts("load")
Events.OnGameBoot.Add(function()
    guardOnBreak()
    applyScripts("OnGameBoot")
end)
-- after the Frostburn sandbox values are in its script
Events.OnInitGlobalModData.Add(function() applyScripts("OnInitGlobalModData") end)

--------------------------------------------------------------
-- Repair (shared helpers)
--------------------------------------------------------------

local function needsRepair(it)
    if it:isBroken() then return true end
    if it:getCondition() < it:getConditionMax() then return true end
    if it:hasHeadCondition() and it:getHeadCondition() < it:getHeadConditionMax() then return true end
    return false
end

-- server: CX.server (CookieExchange). client: CX.bal is the synced balance of this player
local function wallet()
    if type(CX) == "table" and type(CX.server) == "table" then return CX.server end
    return nil
end

local function balance(p)
    if type(CX) ~= "table" then return nil end
    if CX.bal ~= nil then return tonumber(CX.bal) end
    local w = wallet()
    if not w then return nil end
    local ok, v = pcall(function() return w.balance(p:getUsername()) end)
    if ok then return tonumber(v) end
    return nil
end

local function toClient(p, command, args)
    if isServer() then
        sendServerCommand(p, MODULE, command, args)
    else
        triggerEvent("OnServerCommand", MODULE, command, args)
    end
end

--------------------------------------------------------------
-- Server
--------------------------------------------------------------

local function repairFull(it)
    it:setConditionNoSound(it:getConditionMax())   -- also clears "broken"
    if it:hasHeadCondition() then it:setHeadCondition(it:getHeadConditionMax()) end
    if it:hasSharpness() then it:setSharpness(it:getMaxSharpness()) end
end

local function onRepair(p, args)
    local id = args and tonumber(args.id)
    if not id then return end
    local inv = p:getInventory()
    local it = inv and inv:getItemWithIDRecursiv(id)
    if not it or not isWeapon(it) then
        toClient(p, "result", { ok = false, key = "NotFound" })
        return
    end
    if not needsRepair(it) then
        toClient(p, "result", { ok = false, key = "Full" })
        return
    end
    local w = wallet()
    if not w then
        toClient(p, "result", { ok = false, key = "NoWallet" })
        return
    end
    local name = p:getUsername()
    local bal = tonumber(w.balance(name)) or 0
    if not w.charge(name, COST_CENTS, "myth-repair " .. tostring(it:getFullType())) then
        toClient(p, "result", { ok = false, key = "NoMoney", balance = bal })
        return
    end
    local ok, err = pcall(repairFull, it)
    if not ok then
        w.add(name, COST_CENTS, "myth-repair refund")   -- give the money back
        print(TAG .. ": repair failed for " .. tostring(name) .. ": " .. tostring(err))
        toClient(p, "result", { ok = false, key = "Failed" })
        return
    end
    pcall(function() it:syncItemFields() end)
    print(TAG .. ": " .. tostring(p:getUsername()) .. " repaired " .. tostring(it:getFullType()) .. " for "
        .. COST_CENTS .. " cents (balance " .. bal .. " -> " .. (bal - COST_CENTS) .. ")")
    toClient(p, "result", { ok = true, key = "Done", balance = bal - COST_CENTS })
end

if not isClient() then
    Events.OnClientCommand.Add(function(module, command, p, args)
        if module ~= MODULE or command ~= "repair" or not p then return end
        local ok, err = pcall(onRepair, p, args)
        if not ok then print(TAG .. ": " .. tostring(err)) end
    end)
end

--------------------------------------------------------------
-- Client: right-click option, confirm, result text
--------------------------------------------------------------

local function money(cents)
    cents = math.floor(tonumber(cents) or 0)
    local d = math.floor(cents / 100)
    local c = cents - d * 100
    local s = tostring(d)
    local out = ""
    while string.len(s) > 3 do
        out = "," .. string.sub(s, -3) .. out
        s = string.sub(s, 1, -4)
    end
    out = "$" .. s .. out
    if c > 0 then out = out .. string.format(".%02d", c) end
    return out
end

local function onChoose(it, p)
    local text = getText("IGUI_CSP_MythRepair_Confirm") .. " " .. money(COST_CENTS) .. " ?"
    local w, h = 380, 130
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local modal = ISModalDialog:new(x, y, w, h, text, true, nil, function(_, button)
        if button and button.internal == "YES" then
            sendClientCommand(p, MODULE, "repair", { id = it:getID() })
        end
    end, p:getPlayerNum())
    modal:initialise()
    modal:addToUIManager()
end

local function findWeapon(items)
    for _, v in ipairs(items or {}) do
        local it = v
        if type(v) == "table" and v.items then it = v.items[1] end
        if it and isWeapon(it) then return it end
    end
    return nil
end

if not isServer() then
    Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
        local p = getSpecificPlayer(playerNum)
        local it = findWeapon(items)
        if not p or not it then return end
        local ok, mine = pcall(function() return it:isInPlayerInventory() end)
        if not ok or not mine then return end
        if not needsRepair(it) then return end
        local opt = context:addOption(getText("IGUI_CSP_MythRepair") .. " (" .. money(COST_CENTS) .. ")", it, onChoose, p)
        local bal = balance(p)
        local tip = ISInventoryPaneContextMenu.addToolTip()
        tip.description = getText("IGUI_CSP_MythRepair_Tip") .. " <LINE> " .. getText("IGUI_CSP_MythRepair_Wallet")
            .. " " .. (bal and money(bal) or "?")
        if bal and bal < COST_CENTS then
            tip.description = tip.description .. " <LINE> <RGB:1,0.4,0.4> " .. getText("IGUI_CSP_MythRepair_NoMoney")
        end
        opt.toolTip = tip
    end)

    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= MODULE or command ~= "result" then return end
        local p = getPlayer()
        if not p then return end
        local key = (args and args.key) or "Failed"
        local text = getText("IGUI_CSP_MythRepair_" .. key)
        if args and args.ok then
            pcall(HaloTextHelper.addGoodText, p, text)
        else
            pcall(HaloTextHelper.addBadText, p, text)
        end
    end)
end

print(TAG .. " on (cost " .. money(COST_CENTS) .. " from the Cookie Wallet, durability "
    .. BASE_ITEM .. " x" .. FACTOR .. ")")
