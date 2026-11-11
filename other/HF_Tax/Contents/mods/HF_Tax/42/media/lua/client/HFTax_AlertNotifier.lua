-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
local HFTax = HFTax or {}
HFTax.AlertNotifier = HFTax.AlertNotifier or {}

-- [Matasa Protected Core Watermark - Login Alert Controller v43]
local _matasa_sec_id = "MATASA_HFTAX_2026_LOGIN_ALERT_V43_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

local _hasAlertedThisSession = false

---Check if player's safehouse has overdue or cutoff bills on login
---@param player IsoPlayer
function HFTax.AlertNotifier.checkOnLogin(player)
    if _hasAlertedThisSession then return end
    if not player or not player:isLocalPlayer() then return end

    local username = player:getUsername()
    local safehouses = SafeHouse.getSafehouseList()
    if not safehouses then return end

    local matchingSafehouse = nil
    local matchingStatus = nil

    for i = 0, safehouses:size() - 1 do
        local sh = safehouses:get(i)
        if sh then
            local isOwner = (sh:getOwner() == username)
            local isMember = sh:playerAllowed(username) or (sh:getPlayers() and sh:getPlayers():contains(username))

            if isOwner or isMember then
                local shKey = HFTax.Utils.getSafehouseKey(sh)
                local status = HFTax.ClientData and HFTax.ClientData.SafehouseStatus and HFTax.ClientData.SafehouseStatus[shKey]

                -- Fallback to local bills if status map not yet populated
                if not status or not status.totalOutstanding then
                    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
                    local bills = globalData.Bills or {}
                    local totalOut = 0
                    local unpCount = 0
                    local hasOver = false
                    local isCut = false
                    local primBillNum = "001"
                    local oldestEp = 999999999
                    local currentEpoch = HFTax.Utils.getRealDaysEpoch()

                    for _, b in pairs(bills) do
                        if b.safehouseKey == shKey and b.status == HFTax.Config.BILL_STATUS.UNPAID and not b.isWaived and (b.totalAmount or 0) > 0 then
                            unpCount = unpCount + 1
                            totalOut = totalOut + (b.totalAmount or 0)
                            local bEpoch = b.createdEpoch or currentEpoch
                            if bEpoch < oldestEp then
                                oldestEp = bEpoch
                                primBillNum = b.billNumber or "001"
                            end
                            if b.isCutoffStage then isCut = true elseif b.isOverdue then hasOver = true end
                        end
                    end

                    if unpCount > 0 then
                        local totalThreshold = HFTax.Config.STAGE1_DUE_DAYS + HFTax.Config.STAGE2_CUTOFF_DAYS
                        local daysActive = currentEpoch - oldestEp
                        local daysRemaining = math.max(0, math.floor(totalThreshold - daysActive))

                        status = {
                            isCutoff = isCut,
                            isOverdue = hasOver or isCut,
                            totalOutstanding = totalOut,
                            unpaidCount = unpCount,
                            primaryBillNumber = primBillNum,
                            shid = HFTax.Utils.getSafehouseSHID(sh),
                            daysRemainingToCutoff = daysRemaining
                        }
                    end
                end

                if status and (status.isOverdue or status.isCutoff) and (status.totalOutstanding and status.totalOutstanding > 0) then
                    matchingSafehouse = sh
                    matchingStatus = status
                    break
                end
            end
        end
    end

    if matchingSafehouse and matchingStatus then
        _hasAlertedThisSession = true
        if HFTaxUI and HFTaxUI.AlertPopupUI then
            HFTaxUI.AlertPopupUI.openWindow(player, matchingSafehouse, matchingStatus)
        end
    end
end

local function onPlayerLoginCheck(playerIndex, player)
    if player and player:isLocalPlayer() then
        HFTax.AlertNotifier.checkOnLogin(player)
    end
end

Events.OnCreatePlayer.Add(onPlayerLoginCheck)