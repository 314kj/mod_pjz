-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
local HFTax = HFTax or {}
HFTax.UtilityInterceptor = HFTax.UtilityInterceptor or {}

-- [Matasa Protected Core Watermark - Strict Action & Click Interceptor v40]
local _matasa_sec_id = "MATASA_HFTAX_2026_UTIL_INTERCEPT_V40_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

---Authoritative Safehouse Cutoff Evaluator
---@param sq IsoGridSquare
---@return boolean, SafeHouse?
function HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(sq)
    if not sq then return false, nil end
    
    local safehouse = SafeHouse.getSafeHouse(sq)
    if not safehouse then return false, nil end

    local shKey = HFTax.Utils.getSafehouseKey(safehouse)

    -- 1. Primary Authority: Live Broadcast Map from Server
    if HFTax.ClientData and HFTax.ClientData.CutoffSafehouses then
        if HFTax.ClientData.CutoffSafehouses[shKey] == true then
            return true, safehouse
        else
            return false, safehouse
        end
    end

    -- 2. Fallback: Ledger Bills Check
    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local bills = globalData.Bills or {}
    for _, bill in pairs(bills) do
        if bill.safehouseKey == shKey and bill.status == HFTax.Config.BILL_STATUS.UNPAID and not bill.isWaived and (bill.totalAmount or 0) > 0 then
            if bill.isCutoffStage then
                return true, safehouse
            end
        end
    end

    return false, safehouse
end

---Recursively remove water and power options from context and submenus
---@param context ISContextMenu
---@return boolean
local function filterRestrictedOptions(context)
    if not context or not context.options then return false end
    local blockedFound = false

    local textDrink = getText("ContextMenu_Drink")
    local textFill = getText("ContextMenu_Fill")
    local textWash = getText("ContextMenu_Wash")
    local textTurnOn = getText("ContextMenu_Turn_On")
    local textTurnOff = getText("ContextMenu_Turn_Off")
    local textFillAll = getText("ContextMenu_FillAll")
    local textFillOne = getText("ContextMenu_FillOne")

    for i = #context.options, 1, -1 do
        local opt = context.options[i]
        if opt and opt.name then
            local n = opt.name
            if n == textDrink or n:find(textDrink) or n == textFill or n:find(textFill)
               or n:find(textWash) or n == textTurnOn or n == textTurnOff 
               or n == textFillAll or n == textFillOne then
                table.remove(context.options, i)
                blockedFound = true
            elseif opt.subOption then
                local subMenu = context:getSubMenu(opt.subOption)
                if subMenu and filterRestrictedOptions(subMenu) then
                    blockedFound = true
                end
            end
        end
    end

    return blockedFound
end

---Context Menu Interceptor
local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test or not worldObjects or #worldObjects == 0 then return end

    local firstObj = worldObjects[1]
    local sq = firstObj and firstObj:getSquare() or nil
    if not sq then return end

    local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(sq)
    if not isCutoff then return end

    local blocked = filterRestrictedOptions(context)
    local player = getSpecificPlayer(playerNum) or getPlayer()

    if blocked and player and HaloTextHelper then
        HaloTextHelper.addTextWithArrow(player, "Utilities are disabled in this safehouse due to overdue tax!", false, 255, 75, 75)
    end
end

---Crash-Proof Mouse Click Interceptor
local function onObjectLeftMouseButtonDown(object, x, y)
    if not object then return end
    local sq = nil
    pcall(function() sq = object:getSquare() end)
    if not sq then return end

    local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(sq)
    if not isCutoff then return end

    pcall(function()
        if instanceof(object, "IsoLightSwitch") then
            if object.setActive then
                object:setActive(false)
            end
            local player = getPlayer()
            if player and HaloTextHelper then
                HaloTextHelper.addTextWithArrow(player, "Power is CUT-OFF in this safehouse!", false, 255, 75, 75)
            end
        elseif instanceof(object, "IsoStove") then
            if object.setActivated then
                object:setActivated(false)
            end
            local player = getPlayer()
            if player and HaloTextHelper then
                HaloTextHelper.addTextWithArrow(player, "Power is CUT-OFF in this safehouse!", false, 255, 75, 75)
            end
        end
    end)
end

---Key Interaction Hook: Blocks toggling electrical devices via 'E' key
local function onKeyStartPressed(key)
    local interactKey = 18
    pcall(function() interactKey = getCore():getKey("Interact") end)
    
    if key == interactKey then
        local player = getPlayer()
        if not player then return end

        local sq = player:getCurrentSquare()
        if not sq then return end

        local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(sq)
        if isCutoff then
            pcall(function()
                local cell = sq:getCell() or getCell()
                if not cell then return end
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        local nSq = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                        if nSq then
                            local objects = nSq:getObjects()
                            if objects then
                                for i = 0, objects:size() - 1 do
                                    local obj = objects:get(i)
                                    if obj and instanceof(obj, "IsoLightSwitch") then
                                        if obj.setActive then
                                            obj:setActive(false)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end

---Instant Client-side Room Blackout Suppression while moving inside Cutoff Safehouse
local function onPlayerMovePassiveSuppress(player)
    if not player or not player:isLocalPlayer() then return end

    local sq = player:getCurrentSquare()
    if not sq then return end

    local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(sq)
    if not isCutoff then return end

    local room = sq:getRoom()
    if room then
        local switches = room:getLightSwitches()
        if switches then
            for i = 0, switches:size() - 1 do
                local sw = switches:get(i)
                if sw and sw.setActive and sw:isActive() then
                    sw:setActive(false)
                end
            end
        end
    end
end

---Engine-level Action Hooks: Blocks Water, Stove & Light Timed Actions
local function hookTimedActions()
    -- 1. Water Extraction
    if ISTakeWaterAction then
        local original_isValid = ISTakeWaterAction.isValid
        ISTakeWaterAction.isValid = function(self)
            if self.waterObject and self.waterObject:getSquare() then
                local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(self.waterObject:getSquare())
                if isCutoff then return false end
            end
            return original_isValid(self)
        end
    end

    -- 2. Toggle Light Action
    if ISToggleLightAction then
        local original_isValid = ISToggleLightAction.isValid
        ISToggleLightAction.isValid = function(self)
            if self.lightSwitch and self.lightSwitch:getSquare() then
                local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(self.lightSwitch:getSquare())
                if isCutoff then
                    pcall(function()
                        if self.lightSwitch.setActive then
                            self.lightSwitch:setActive(false)
                        end
                    end)
                    return false
                end
            end
            return original_isValid(self)
        end
    end

    -- 3. Toggle Stove Action
    if ISToggleStoveAction then
        local original_isValid = ISToggleStoveAction.isValid
        ISToggleStoveAction.isValid = function(self)
            if self.stove and self.stove:getSquare() then
                local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(self.stove:getSquare())
                if isCutoff then
                    pcall(function()
                        if self.stove.setActivated then
                            self.stove:setActivated(false)
                        end
                    end)
                    return false
                end
            end
            return original_isValid(self)
        end
    end

    -- 4. Washing Actions
    if ISWashClothing then
        local original_isValid = ISWashClothing.isValid
        ISWashClothing.isValid = function(self)
            if self.sink and self.sink:getSquare() then
                local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(self.sink:getSquare())
                if isCutoff then return false end
            end
            return original_isValid(self)
        end
    end

    if ISWashYourself then
        local original_isValid = ISWashYourself.isValid
        ISWashYourself.isValid = function(self)
            if self.sink and self.sink:getSquare() then
                local isCutoff, _ = HFTax.UtilityInterceptor.isSquareInCutoffSafehouse(self.sink:getSquare())
                if isCutoff then return false end
            end
            return original_isValid(self)
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnObjectLeftMouseButtonDown.Add(onObjectLeftMouseButtonDown)
Events.OnKeyStartPressed.Add(onKeyStartPressed)
Events.OnPlayerMove.Add(onPlayerMovePassiveSuppress)
Events.OnGameStart.Add(hookTimedActions)