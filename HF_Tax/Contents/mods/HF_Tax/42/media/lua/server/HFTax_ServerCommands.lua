-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
if isClient() and not isServer() then return end

local HFTax = HFTax or {}
HFTax.ServerCommands = HFTax.ServerCommands or {}

-- [Matasa Protected Core Watermark - Server Commands Akacount Satang Conversion v53]
local _matasa_sec_id = "MATASA_HFTAX_2026_SRV_CMD_SATANG_V53_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

local function isServerAdmin(player)
    if not player then return false end
    if isCoopHost() or (getCore() and getCore():getDebug()) then return true end
    local ok, lvl = pcall(function() return player:getAccessLevel() end)
    if ok and lvl and (lvl:lower() == "admin" or lvl:lower() == "moderator" or lvl:lower() == "gm" or lvl:lower() == "overseer") then
        return true
    end
    if ok and (isAdmin() or (player.isAccessLevel and player:isAccessLevel("admin"))) then
        return true
    end
    return false
end

---Strictly count cash ONLY in main player inventory (no backpacks/bags)
local function getCashOnPerson(player)
    if not player then return 0 end
    local inv = player:getInventory()
    if not inv then return 0 end
    local count = 0
    local items = inv:getItems()
    if items then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and item:getFullType() == "Base.Money" then
                count = count + 1
            end
        end
    end
    return count
end

---Strictly remove cash ONLY from main inventory
local function removeCashFromPerson(player, amount)
    local inv = player:getInventory()
    if not inv or amount <= 0 then return end
    local countToRemove = amount
    local items = inv:getItems()
    if not items then return end

    for i = items:size() - 1, 0, -1 do
        if countToRemove <= 0 then break end
        local item = items:get(i)
        if item and item:getFullType() == "Base.Money" then
            inv:Remove(item)
            sendRemoveItemFromContainer(inv, item)
            countToRemove = countToRemove - 1
        end
    end
end

---Resolve Akacount API safely at runtime
local function getEconAPI()
    if Akacount and type(Akacount) == "table" and Akacount.available then
        return Akacount
    end
    return nil
end

HFTax.ServerCommands.SetPaymentSettings = function(player, args)
    if not isServerAdmin(player) or not args then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    globalData.PaymentSettings = globalData.PaymentSettings or { allowCash = true, allowBank = true }
    
    if args.allowCash ~= nil then globalData.PaymentSettings.allowCash = (args.allowCash == true) end
    if args.allowBank ~= nil then globalData.PaymentSettings.allowBank = (args.allowBank == true) end

    HFTax.ServerCore.syncModData()
    HFTax.ServerCore.broadcastAdminData()
end

HFTax.ServerCommands.WipeTaxSystem = function(player, args)
    if not isServerAdmin(player) then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    globalData.Safehouses = {}
    globalData.Bills = {}
    globalData.PersonalPreviews = {}
    globalData.PlayerSettings = {}
    globalData.ExemptPlayers = {}
    globalData.PaymentSettings = { allowCash = true, allowBank = true }
    globalData.Treasury = {
        vaultBalance = 0,
        totalPlayerCollected = 0,
        totalAdminSubsidized = 0,
        totalWithdrawn = 0
    }

    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local safehouses = SafeHouse.getSafehouseList()

    if safehouses then
        for i = 0, safehouses:size() - 1 do
            local sh = safehouses:get(i)
            HFTax.ServerCore.ensureSafehouseInit(sh, globalData, currentEpoch)
        end
    end

    HFTax.ServerCore.processUtilityCutoffs(globalData, currentEpoch)
    HFTax.ServerCore.syncModData()
    HFTax.ServerCore.broadcastSafehouseStatus()
    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncPlayerBills", { bills = globalData.Bills, bankBalance = 0 })
end

HFTax.ServerCommands.RequestSafehouseStatus = function(player, args)
    if not player then return end
    HFTax.ServerCore.broadcastSafehouseStatus()
end

HFTax.ServerCommands.AdminMarkBillPaid = function(player, args)
    if not isServerAdmin(player) or not args or not args.billId then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local targetBill = globalData.Bills[args.billId]
    if not targetBill or targetBill.status == HFTax.Config.BILL_STATUS.PAID then return end

    local adminName = player:getUsername()
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local billAmount = targetBill.totalAmount or 0
    
    targetBill.status = HFTax.Config.BILL_STATUS.PAID
    targetBill.paidEpoch = currentEpoch
    targetBill.paidDateStr = HFTax.Utils.getCurrentDateTimeString()
    targetBill.paidBy = "[Admin] " .. adminName
    targetBill.isOverdue = false
    targetBill.isCutoffStage = false

    globalData.Treasury = globalData.Treasury or { vaultBalance = 0, totalPlayerCollected = 0, totalAdminSubsidized = 0, totalWithdrawn = 0 }
    globalData.Treasury.totalAdminSubsidized = (globalData.Treasury.totalAdminSubsidized or 0) + billAmount

    HFTax.ServerCore.processUtilityCutoffs(globalData, currentEpoch)
    HFTax.ServerCore.syncModData()
    HFTax.ServerCore.broadcastSafehouseStatus()
    HFTax.ServerCore.broadcastAdminData()
    HFTax.ServerCore.broadcastPlayerBills()
end

HFTax.ServerCommands.WithdrawTreasury = function(player, args)
    if not isServerAdmin(player) or not args or not args.amount then return end

    local withdrawAmt = math.floor(tonumber(args.amount) or 0)
    if withdrawAmt <= 0 then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    globalData.Treasury = globalData.Treasury or { vaultBalance = 0, totalPlayerCollected = 0, totalAdminSubsidized = 0, totalWithdrawn = 0 }

    local curVault = globalData.Treasury.vaultBalance or 0
    if withdrawAmt > curVault then
        sendServerCommand(player, HFTax.Config.MOD_ID, "TreasuryWithdrawFailed", { reason = "EXCEEDS_BALANCE", maxAvailable = curVault })
        return
    end

    globalData.Treasury.vaultBalance = curVault - withdrawAmt
    globalData.Treasury.totalWithdrawn = (globalData.Treasury.totalWithdrawn or 0) + withdrawAmt

    local inv = player:getInventory()
    if inv then
        for i = 1, withdrawAmt do
            local moneyItem = inv:AddItem("Base.Money")
            if moneyItem then
                sendAddItemToContainer(inv, moneyItem)
            end
        end
    end

    HFTax.ServerCore.syncModData()
    HFTax.ServerCore.broadcastAdminData()
    sendServerCommand(player, HFTax.Config.MOD_ID, "TreasuryWithdrawSuccess", {
        amount = withdrawAmt,
        remainingVault = globalData.Treasury.vaultBalance
    })
end

HFTax.ServerCommands.SetPlayerTaxStatus = function(player, args)
    if not isServerAdmin(player) or not args or not args.username or not args.status then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    globalData.PlayerSettings = globalData.PlayerSettings or {}
    globalData.PlayerSettings[args.username] = globalData.PlayerSettings[args.username] or {}
    globalData.PlayerSettings[args.username].taxStatus = args.status

    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    HFTax.ServerCore.ensurePersonalTaxInit(args.username, globalData, currentEpoch)

    HFTax.ServerCore.syncModData()
    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
end

HFTax.ServerCommands.RequestPlayerBills = function(player, args)
    if not player then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local myUsername = player:getUsername()
    local myPUUID = (args and args.myPUUID) or HFTax.Utils.getPlayerPUUID(myUsername)

    local filteredBills = {}
    for billId, bill in pairs(globalData.Bills or {}) do
        if (bill.visibilityPUUIDs and bill.visibilityPUUIDs[myPUUID]) or (bill.owner == myUsername) or (bill.ownerPUUID == myPUUID) then
            filteredBills[billId] = bill
        end
    end

    local econ = getEconAPI()
    -- Convert raw satang (cents) to standard dollars for UI display
    local rawSatang = econ and econ.available(myUsername) or 0
    local bankBalance = math.floor(rawSatang / 100)

    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncPlayerBills", { 
        bills = filteredBills,
        bankBalance = bankBalance
    })
end

HFTax.ServerCommands.RequestAdminData = function(player, args)
    if not isServerAdmin(player) then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local safehouses = SafeHouse.getSafehouseList()

    if safehouses then
        for i = 0, safehouses:size() - 1 do
            local sh = safehouses:get(i)
            HFTax.ServerCore.ensureSafehouseInit(sh, globalData, currentEpoch)
        end
    end

    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            HFTax.ServerCore.ensurePersonalTaxInit(p:getUsername(), globalData, currentEpoch)
        end
    end

    HFTax.ServerCore.syncModData()
    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
end

HFTax.ServerCommands.UpdatePreviewBill = function(player, args)
    if not isServerAdmin(player) or not args or not args.safehouseKey then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local shData = globalData.Safehouses[args.safehouseKey]
    if not shData then return end

    local shid = shData.shid or "000000"
    local curCounter = shData.billCounter or 1

    shData.previewBill = shData.previewBill or {}
    shData.previewBill.shid = shid
    shData.previewBill.billNumber = args.billNumber or HFTax.Utils.formatBillNumber(curCounter)
    shData.previewBill.landTax = args.landTax or 0
    shData.previewBill.memberTax = args.memberTax or 0
    shData.previewBill.penalty = args.penalty or 0
    shData.previewBill.totalAmount = args.totalAmount or 0
    shData.previewBill.note = args.note or ""
    shData.previewBill.customOverride = true
    shData.previewBill.isWaived = false

    HFTax.ServerCore.syncModData()
    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
end

HFTax.ServerCommands.UpdatePersonalPreviewBill = function(player, args)
    if not isServerAdmin(player) or not args or not args.username then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    HFTax.ServerCore.ensurePersonalTaxInit(args.username, globalData, currentEpoch)

    local puuid = HFTax.Utils.getPlayerPUUID(args.username)
    local curCounter = (globalData.PersonalPreviews[args.username] and globalData.PersonalPreviews[args.username].billCounter) or 1

    globalData.PersonalPreviews[args.username] = {
        puuid = puuid,
        billCounter = curCounter,
        billNumber = args.billNumber or HFTax.Utils.formatBillNumber(curCounter),
        baseTax = args.baseTax or 0,
        penalty = args.penalty or 0,
        totalAmount = args.totalAmount or 0,
        note = args.note or "",
        scheduledEpoch = HFTax.Utils.getRealDaysEpoch() + HFTax.Config.DefaultPersonalTax.cycleDays,
        customOverride = true,
        isWaived = false
    }

    HFTax.ServerCore.syncModData()
    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
end

HFTax.ServerCommands.ForceSendSafehouseBill = function(player, args)
    if not isServerAdmin(player) or not args or not args.safehouseKey then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local dbHouse = globalData.Safehouses[args.safehouseKey]
    if not dbHouse then return end

    local safehouses = SafeHouse.getSafehouseList()
    local targetSh = nil
    if safehouses then
        for i = 0, safehouses:size() - 1 do
            local sh = safehouses:get(i)
            if HFTax.Utils.getSafehouseKey(sh) == args.safehouseKey then
                targetSh = sh
                break
            end
        end
    end

    if targetSh then
        HFTax.ServerCore.dispatchBillFromPreview(targetSh, dbHouse, HFTax.Utils.getRealDaysEpoch())
        HFTax.ServerCore.syncModData()
        HFTax.ServerCore.broadcastSafehouseStatus()
        sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
    end
end

HFTax.ServerCommands.ForceSendPersonalBill = function(player, args)
    if not isServerAdmin(player) or not args or not args.username then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()

    HFTax.ServerCore.ensurePersonalTaxInit(args.username, globalData, currentEpoch)
    HFTax.ServerCore.dispatchPersonalBillFromPreview(args.username, currentEpoch)
    HFTax.ServerCore.syncModData()
    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
end

HFTax.ServerCommands.SetSafehouseProfile = function(player, args)
    if not isServerAdmin(player) or not args or not args.safehouseKey or not args.profileId then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    if globalData.Safehouses[args.safehouseKey] then
        local dbHouse = globalData.Safehouses[args.safehouseKey]
        dbHouse.profileId = args.profileId

        local profileData = HFTax.Config.DefaultProfiles[args.profileId] or HFTax.Config.DefaultProfiles["profile_default"]
        local safehouses = SafeHouse.getSafehouseList()

        if safehouses then
            for i = 0, safehouses:size() - 1 do
                local sh = safehouses:get(i)
                if HFTax.Utils.getSafehouseKey(sh) == args.safehouseKey then
                    local lTax = HFTax.Utils.calculateLandTax(sh:getW(), sh:getH(), profileData.ratePerTile)
                    local mCount = sh:getPlayers() and sh:getPlayers():size() or 1
                    local mTax = HFTax.Utils.calculateMemberTax(mCount, profileData.freeMembers, profileData.ratePerExtraMember)

                    dbHouse.previewBill = dbHouse.previewBill or {}
                    local pb = dbHouse.previewBill

                    pb.shid = dbHouse.shid or HFTax.Utils.getSafehouseSHID(sh)
                    pb.billNumber = HFTax.Utils.formatBillNumber(dbHouse.billCounter or 1)
                    pb.landTax = lTax
                    pb.memberTax = mTax
                    pb.totalAmount = pb.isWaived and 0 or (lTax + mTax + (pb.penalty or 0))
                    pb.customOverride = false
                    break
                end
            end
        end

        HFTax.ServerCore.syncModData()
        sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
    end
end

HFTax.ServerCommands.WaiveSafehouseTax = function(player, args)
    if not isServerAdmin(player) or not args or not args.safehouseKey then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local dbHouse = globalData.Safehouses[args.safehouseKey]
    if not dbHouse then return end

    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local safehouses = SafeHouse.getSafehouseList()
    local targetSh = nil
    if safehouses then
        for i = 0, safehouses:size() - 1 do
            local sh = safehouses:get(i)
            if HFTax.Utils.getSafehouseKey(sh) == args.safehouseKey then
                targetSh = sh
                break
            end
        end
    end

    if targetSh then
        HFTax.ServerCore.ensureSafehouseInit(targetSh, globalData, currentEpoch)
        local pb = dbHouse.previewBill
        if pb then
            pb.isWaived = not (pb.isWaived or false)
            if pb.isWaived then
                pb.savedCalculatedTotal = pb.totalAmount
                pb.totalAmount = 0
            else
                local profileData = HFTax.Config.DefaultProfiles[dbHouse.profileId or "profile_default"] or HFTax.Config.DefaultProfiles["profile_default"]
                local lTax = pb.landTax or HFTax.Utils.calculateLandTax(targetSh:getW(), targetSh:getH(), profileData.ratePerTile)
                local mCount = targetSh:getPlayers() and targetSh:getPlayers():size() or 1
                local mTax = pb.memberTax or HFTax.Utils.calculateMemberTax(mCount, profileData.freeMembers, profileData.ratePerExtraMember)
                pb.totalAmount = lTax + mTax + (pb.penalty or 0)
            end
        end

        HFTax.ServerCore.processUtilityCutoffs(globalData, currentEpoch)
        HFTax.ServerCore.syncModData()
        HFTax.ServerCore.broadcastSafehouseStatus()
        sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
    end
end

HFTax.ServerCommands.WaivePersonalTax = function(player, args)
    if not isServerAdmin(player) or not args or not args.username then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    HFTax.ServerCore.ensurePersonalTaxInit(args.username, globalData, currentEpoch)

    local pb = globalData.PersonalPreviews and globalData.PersonalPreviews[args.username]
    if pb then
        pb.isWaived = not (pb.isWaived or false)
        if pb.isWaived then
            pb.savedCalculatedTotal = pb.totalAmount
            pb.totalAmount = 0
        else
            pb.totalAmount = (pb.baseTax or HFTax.Config.DefaultPersonalTax.rate) + (pb.penalty or 0)
        end

        HFTax.ServerCore.syncModData()
        sendServerCommand(player, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
    end
end

---Player Pay Bill: Converts Dollars to Satang (x100) when charging Akacount
HFTax.ServerCommands.PayBill = function(player, args)
    if not player or not args or not args.billId then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local targetBill = globalData.Bills[args.billId]
    if not targetBill or targetBill.status ~= HFTax.Config.BILL_STATUS.UNPAID then return end

    local username = player:getUsername()
    local myPUUID = HFTax.Utils.getPlayerPUUID(username)

    if targetBill.billType == HFTax.Config.BILL_TYPE.LAND and targetBill.owner ~= username and not isServerAdmin(player) then
        sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "NOT_OWNER" })
        return
    end

    local targetEpoch = targetBill.createdEpoch or 0
    for otherId, otherBill in pairs(globalData.Bills or {}) do
        if otherId ~= args.billId and otherBill.status == HFTax.Config.BILL_STATUS.UNPAID then
            local isSameTarget = false
            if targetBill.billType == HFTax.Config.BILL_TYPE.LAND and otherBill.safehouseKey == targetBill.safehouseKey then
                isSameTarget = true
            elseif targetBill.billType == HFTax.Config.BILL_TYPE.PERSONAL and otherBill.owner == username then
                isSameTarget = true
            end

            if isSameTarget then
                local otherEpoch = otherBill.createdEpoch or 0
                if otherEpoch < (targetEpoch - 0.0001) then
                    sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "MUST_PAY_OLDEST_FIRST" })
                    return
                end
            end
        end
    end

    local totalAmount = targetBill.totalAmount or 0
    local pSettings = globalData.PaymentSettings or { allowCash = true, allowBank = true }
    local payMethod = args.payMethod or "CASH"

    if totalAmount > 0 then
        if payMethod == "BANK" then
            if not pSettings.allowBank then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "BANK_PAYMENT_DISABLED" })
                return
            end

            local econ = getEconAPI()
            if not econ then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "BANK_UNAVAILABLE" })
                return
            end

            local satangAmount = totalAmount * 100
            if not econ.can(username, satangAmount) then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "INSUFFICIENT_FUNDS" })
                return
            end

            local success, err = econ.charge(username, satangAmount, "TAX", targetBill.billId, "HF_Tax")
            if not success then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "BANK_CHARGE_FAILED" })
                return
            end
        else
            if not pSettings.allowCash then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "CASH_PAYMENT_DISABLED" })
                return
            end

            local cashOnPerson = getCashOnPerson(player)
            if cashOnPerson < totalAmount then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "INSUFFICIENT_FUNDS" })
                return
            end

            removeCashFromPerson(player, totalAmount)
        end
    end

    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    targetBill.status = HFTax.Config.BILL_STATUS.PAID
    targetBill.paidEpoch = currentEpoch
    targetBill.paidDateStr = HFTax.Utils.getCurrentDateTimeString()
    targetBill.paidBy = username .. (payMethod == "BANK" and " [Bank ATM]" or " [Cash]")
    targetBill.isOverdue = false
    targetBill.isCutoffStage = false

    globalData.Treasury = globalData.Treasury or { vaultBalance = 0, totalPlayerCollected = 0, totalAdminSubsidized = 0, totalWithdrawn = 0 }
    globalData.Treasury.vaultBalance = (globalData.Treasury.vaultBalance or 0) + totalAmount
    globalData.Treasury.totalPlayerCollected = (globalData.Treasury.totalPlayerCollected or 0) + totalAmount

    HFTax.ServerCore.processUtilityCutoffs(globalData, currentEpoch)
    HFTax.ServerCore.syncModData()
    HFTax.ServerCore.broadcastSafehouseStatus()
    HFTax.ServerCore.broadcastAdminData()

    local filteredBills = {}
    for bId, bData in pairs(globalData.Bills or {}) do
        if (bData.visibilityPUUIDs and bData.visibilityPUUIDs[myPUUID]) or (bData.owner == username) or (bData.ownerPUUID == myPUUID) then
            filteredBills[bId] = bData
        end
    end

    local econ = getEconAPI()
    local rawSatang = econ and econ.available(username) or 0
    local bankBalance = math.floor(rawSatang / 100)

    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncPlayerBills", { 
        bills = filteredBills,
        bankBalance = bankBalance
    })
    sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentSuccess", { billId = args.billId, amount = totalAmount })
end

---Player Pay All: Converts Batch Total to Satang (x100) when charging Akacount
HFTax.ServerCommands.PayAllBills = function(player, args)
    if not player or not args or not args.billIds or #args.billIds == 0 then return end

    local globalData = HFTax.ServerCore.getGlobalData()
    local username = player:getUsername()
    local pSettings = globalData.PaymentSettings or { allowCash = true, allowBank = true }
    local payMethod = args.payMethod or "CASH"

    local validBillsToPay = {}
    local totalSumRequired = 0

    for _, bId in ipairs(args.billIds) do
        local bill = globalData.Bills[bId]
        if bill and bill.status == HFTax.Config.BILL_STATUS.UNPAID then
            if bill.billType == HFTax.Config.BILL_TYPE.LAND and bill.owner ~= username and not isServerAdmin(player) then
                -- Skip unowned land bill
            else
                table.insert(validBillsToPay, bill)
                totalSumRequired = totalSumRequired + (bill.totalAmount or 0)
            end
        end
    end

    if #validBillsToPay == 0 then
        sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "NOT_OWNER" })
        return
    end

    if totalSumRequired > 0 then
        if payMethod == "BANK" then
            if not pSettings.allowBank then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "BANK_PAYMENT_DISABLED" })
                return
            end

            local econ = getEconAPI()
            if not econ then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "BANK_UNAVAILABLE" })
                return
            end

            local satangSumRequired = totalSumRequired * 100
            if not econ.can(username, satangSumRequired) then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "INSUFFICIENT_FUNDS" })
                return
            end

            local success, err = econ.charge(username, satangSumRequired, "TAX", "BATCH_PAY_ALL", "HF_Tax")
            if not success then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "BANK_CHARGE_FAILED" })
                return
            end
        else
            if not pSettings.allowCash then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "CASH_PAYMENT_DISABLED" })
                return
            end

            local cashOnPerson = getCashOnPerson(player)
            if cashOnPerson < totalSumRequired then
                sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentFailed", { reason = "INSUFFICIENT_FUNDS" })
                return
            end

            removeCashFromPerson(player, totalSumRequired)
        end
    end

    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local currentDateStr = HFTax.Utils.getCurrentDateTimeString()
    local payerSuffix = username .. (payMethod == "BANK" and " [Bank ATM]" or " [Cash]")

    for _, bill in ipairs(validBillsToPay) do
        bill.status = HFTax.Config.BILL_STATUS.PAID
        bill.paidEpoch = currentEpoch
        bill.paidDateStr = currentDateStr
        bill.paidBy = payerSuffix
        bill.isOverdue = false
        bill.isCutoffStage = false
    end

    globalData.Treasury = globalData.Treasury or { vaultBalance = 0, totalPlayerCollected = 0, totalAdminSubsidized = 0, totalWithdrawn = 0 }
    globalData.Treasury.vaultBalance = (globalData.Treasury.vaultBalance or 0) + totalSumRequired
    globalData.Treasury.totalPlayerCollected = (globalData.Treasury.totalPlayerCollected or 0) + totalSumRequired

    HFTax.ServerCore.processUtilityCutoffs(globalData, currentEpoch)
    HFTax.ServerCore.syncModData()
    HFTax.ServerCore.broadcastSafehouseStatus()
    HFTax.ServerCore.broadcastAdminData()

    local myPUUID = HFTax.Utils.getPlayerPUUID(username)
    local filteredBills = {}
    for bId, bData in pairs(globalData.Bills or {}) do
        if (bData.visibilityPUUIDs and bData.visibilityPUUIDs[myPUUID]) or (bData.owner == username) or (bData.ownerPUUID == myPUUID) then
            filteredBills[bId] = bData
        end
    end

    local econ = getEconAPI()
    local rawSatang = econ and econ.available(username) or 0
    local bankBalance = math.floor(rawSatang / 100)

    sendServerCommand(player, HFTax.Config.MOD_ID, "SyncPlayerBills", { 
        bills = filteredBills,
        bankBalance = bankBalance
    })
    sendServerCommand(player, HFTax.Config.MOD_ID, "PaymentSuccess", { amount = totalSumRequired, count = #validBillsToPay })
end

local function onClientCommand(module, command, player, args)
    if module ~= HFTax.Config.MOD_ID then return end
    if HFTax.ServerCommands[command] then
        HFTax.ServerCommands[command](player, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)