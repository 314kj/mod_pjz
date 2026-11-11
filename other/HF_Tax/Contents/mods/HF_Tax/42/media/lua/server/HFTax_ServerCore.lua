-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
if isClient() and not isServer() then return end

local HFTax = HFTax or {}
HFTax.ServerCore = HFTax.ServerCore or {}

-- [Matasa Protected Core Watermark - Server Core Treasury v49]
local _matasa_sec_id = "MATASA_HFTAX_2026_SRV_CORE_TREASURY_V49_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

function HFTax.ServerCore.getGlobalData()
    local data = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    data.Safehouses = data.Safehouses or {}
    data.Bills = data.Bills or {}
    data.PersonalPreviews = data.PersonalPreviews or {}
    data.PlayerSettings = data.PlayerSettings or {}
    data.ExemptPlayers = data.ExemptPlayers or {}
    data.Profiles = data.Profiles or HFTax.Config.DefaultProfiles
    data.PersonalTax = data.PersonalTax or HFTax.Config.DefaultPersonalTax
    
    -- Global Treasury State
    data.Treasury = data.Treasury or {
        vaultBalance = 0,
        totalPlayerCollected = 0,
        totalAdminSubsidized = 0,
        totalWithdrawn = 0
    }
    return data
end

function HFTax.ServerCore.syncModData()
    ModData.add(HFTax.Config.GLOBAL_DATA_KEY, HFTax.ServerCore.getGlobalData())
    ModData.transmit(HFTax.Config.GLOBAL_DATA_KEY)
end

function HFTax.ServerCore.broadcastSafehouseStatus()
    local globalData = HFTax.ServerCore.getGlobalData()
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local statusMap = {}

    for shKey, shData in pairs(globalData.Safehouses or {}) do
        local totalOutstanding = 0
        local unpaidCount = 0
        local hasOverdue = false
        local isCutoff = (shData.isCutoff == true)
        local primaryBill = nil
        local oldestEpoch = 999999999

        for _, bill in pairs(globalData.Bills or {}) do
            if bill.safehouseKey == shKey and bill.status == HFTax.Config.BILL_STATUS.UNPAID and not bill.isWaived and (bill.totalAmount or 0) > 0 then
                unpaidCount = unpaidCount + 1
                totalOutstanding = totalOutstanding + (bill.totalAmount or 0)

                local bEpoch = bill.createdEpoch or currentEpoch
                if bEpoch < oldestEpoch then
                    oldestEpoch = bEpoch
                    primaryBill = bill
                end

                if bill.isCutoffStage then
                    isCutoff = true
                elseif bill.isOverdue then
                    hasOverdue = true
                end
            end
        end

        local daysRemainingToCutoff = 0
        if primaryBill then
            local daysActive = currentEpoch - (primaryBill.createdEpoch or currentEpoch)
            local totalThreshold = HFTax.Config.STAGE1_DUE_DAYS + HFTax.Config.STAGE2_CUTOFF_DAYS
            daysRemainingToCutoff = math.max(0, math.floor(totalThreshold - daysActive))
        end

        statusMap[shKey] = {
            isCutoff = isCutoff,
            isOverdue = hasOverdue or isCutoff,
            totalOutstanding = totalOutstanding,
            unpaidCount = unpaidCount,
            primaryBillNumber = primaryBill and (primaryBill.billNumber or "001") or nil,
            shid = shData.shid or "000000",
            daysRemainingToCutoff = daysRemainingToCutoff
        }
    end

    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            sendServerCommand(p, HFTax.Config.MOD_ID, "SyncSafehouseStatus", {
                statusMap = statusMap
            })
        end
    end
end

function HFTax.ServerCore.broadcastAdminData()
    local globalData = HFTax.ServerCore.getGlobalData()
    local players = getOnlinePlayers()
    if not players then return end

    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local ok, lvl = pcall(function() return p:getAccessLevel() end)
        local isAdmin = (ok and lvl and lvl ~= "" and lvl:lower() ~= "none") or isCoopHost() or (getCore() and getCore():getDebug())
        if isAdmin then
            sendServerCommand(p, HFTax.Config.MOD_ID, "SyncAdminData", { globalData = globalData })
        end
    end
end

function HFTax.ServerCore.broadcastPlayerBills()
    local globalData = HFTax.ServerCore.getGlobalData()
    local players = getOnlinePlayers()
    if not players then return end

    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local uName = p:getUsername()
        local myPUUID = HFTax.Utils.getPlayerPUUID(uName)

        local filteredBills = {}
        for billId, bill in pairs(globalData.Bills or {}) do
            if (bill.visibilityPUUIDs and bill.visibilityPUUIDs[myPUUID]) or (bill.owner == uName) or (bill.ownerPUUID == myPUUID) then
                filteredBills[billId] = bill
            end
        end
        sendServerCommand(p, HFTax.Config.MOD_ID, "SyncPlayerBills", { bills = filteredBills })
    end
end

function HFTax.ServerCore.isPlayerExempt(username, globalData)
    if not username or username == "" then return true, "NONE" end

    if globalData.PlayerSettings and globalData.PlayerSettings[username] and globalData.PlayerSettings[username].taxStatus == "WAIVE_TAX" then
        return true, "WAIVED_BY_ADMIN"
    end

    local safehouses = SafeHouse.getSafehouseList()
    if safehouses then
        for i = 0, safehouses:size() - 1 do
            local sh = safehouses:get(i)
            if sh:getOwner() == username or (sh:getPlayers() and sh:getPlayers():contains(username)) then
                return true, "IN_SAFEHOUSE"
            end
        end
    end

    return false, "NORMAL"
end

function HFTax.ServerCore.ensureSafehouseInit(sh, globalData, currentEpoch)
    local shKey = HFTax.Utils.getSafehouseKey(sh)
    local shid = HFTax.Utils.getSafehouseSHID(sh)

    globalData.Safehouses[shKey] = globalData.Safehouses[shKey] or {
        title = sh:getTitle(),
        owner = sh:getOwner(),
        profileId = "profile_default",
        shid = shid,
        billCounter = 1,
        members = {},
        isCutoff = false,
        previewBill = nil
    }

    local dbHouse = globalData.Safehouses[shKey]
    dbHouse.profileId = dbHouse.profileId or "profile_default"
    dbHouse.shid = shid
    dbHouse.billCounter = dbHouse.billCounter or 1
    dbHouse.title = sh:getTitle()
    dbHouse.owner = sh:getOwner()

    if not dbHouse.previewBill then
        local profileData = HFTax.Config.DefaultProfiles[dbHouse.profileId] or HFTax.Config.DefaultProfiles["profile_default"]
        local lTax = HFTax.Utils.calculateLandTax(sh:getW(), sh:getH(), profileData.ratePerTile)
        local mCount = sh:getPlayers() and sh:getPlayers():size() or 1
        local mTax = HFTax.Utils.calculateMemberTax(mCount, profileData.freeMembers, profileData.ratePerExtraMember)

        dbHouse.previewBill = {
            shid = shid,
            billNumber = HFTax.Utils.formatBillNumber(dbHouse.billCounter),
            landTax = lTax,
            memberTax = mTax,
            penalty = 0,
            totalAmount = lTax + mTax,
            note = "Safehouse & Land Cycle Tax",
            scheduledEpoch = currentEpoch + HFTax.Config.BILL_CYCLE_DAYS,
            customOverride = false,
            isWaived = false
        }
    elseif not dbHouse.previewBill.customOverride and not dbHouse.previewBill.isWaived then
        local profileData = HFTax.Config.DefaultProfiles[dbHouse.profileId] or HFTax.Config.DefaultProfiles["profile_default"]
        local lTax = HFTax.Utils.calculateLandTax(sh:getW(), sh:getH(), profileData.ratePerTile)
        local mCount = sh:getPlayers() and sh:getPlayers():size() or 1
        local mTax = HFTax.Utils.calculateMemberTax(mCount, profileData.freeMembers, profileData.ratePerExtraMember)

        dbHouse.previewBill.shid = shid
        dbHouse.previewBill.billNumber = HFTax.Utils.formatBillNumber(dbHouse.billCounter)
        dbHouse.previewBill.landTax = lTax
        dbHouse.previewBill.memberTax = mTax
        dbHouse.previewBill.totalAmount = lTax + mTax + (dbHouse.previewBill.penalty or 0)
    end
end

function HFTax.ServerCore.ensurePersonalTaxInit(username, globalData, currentEpoch)
    if not username or username == "" then return end
    globalData.PersonalPreviews = globalData.PersonalPreviews or {}
    globalData.PlayerSettings = globalData.PlayerSettings or {}
    globalData.PlayerSettings[username] = globalData.PlayerSettings[username] or { taxStatus = "NORMAL" }

    local puuid = HFTax.Utils.getPlayerPUUID(username)
    if not globalData.PersonalPreviews[username] then
        globalData.PersonalPreviews[username] = {
            puuid = puuid,
            billCounter = 1,
            billNumber = HFTax.Utils.formatBillNumber(1),
            baseTax = HFTax.Config.DefaultPersonalTax.rate,
            penalty = 0,
            totalAmount = HFTax.Config.DefaultPersonalTax.rate,
            note = "Personal Central Cycle Tax",
            scheduledEpoch = currentEpoch + HFTax.Config.DefaultPersonalTax.cycleDays,
            customOverride = false,
            isWaived = false
        }
    end
end

function HFTax.ServerCore.onCheckSchedulesAndSync()
    local globalData = HFTax.ServerCore.getGlobalData()
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local safehouses = SafeHouse.getSafehouseList()
    local activePlayersMap = {}
    local anyDispatched = false
    local dataChanged = false

    -- 1. Sync Safehouses
    if safehouses then
        for i = 0, safehouses:size() - 1 do
            local sh = safehouses:get(i)
            local shKey = HFTax.Utils.getSafehouseKey(sh)
            local owner = sh:getOwner()
            local membersList = sh:getPlayers()

            HFTax.ServerCore.ensureSafehouseInit(sh, globalData, currentEpoch)
            local dbHouse = globalData.Safehouses[shKey]

            local currentMembersSet = {}
            if owner then
                currentMembersSet[owner] = true
                activePlayersMap[owner] = shKey
            end

            if membersList then
                for mIdx = 0, membersList:size() - 1 do
                    local username = membersList:get(mIdx)
                    currentMembersSet[username] = true
                    activePlayersMap[username] = shKey
                end
            end

            for username, _ in pairs(currentMembersSet) do
                if not dbHouse.members[username] then
                    dbHouse.members[username] = {
                        status = "ACTIVE",
                        joinedEpoch = currentEpoch,
                        leaveEpoch = nil
                    }
                elseif dbHouse.members[username].status == "PENDING" then
                    dbHouse.members[username].status = "ACTIVE"
                    dbHouse.members[username].leaveEpoch = nil
                end
            end

            for dbUser, memberData in pairs(dbHouse.members) do
                if not currentMembersSet[dbUser] and memberData.status == "ACTIVE" then
                    memberData.status = "PENDING"
                    memberData.leaveEpoch = currentEpoch
                end
            end

            local pb = dbHouse.previewBill
            if pb and currentEpoch >= (pb.scheduledEpoch or (currentEpoch + 999)) then
                HFTax.ServerCore.dispatchBillFromPreview(sh, dbHouse, currentEpoch)
                anyDispatched = true
            end
        end

        for shKey, houseData in pairs(globalData.Safehouses) do
            for username, memberData in pairs(houseData.members) do
                if memberData.status == "PENDING" then
                    if activePlayersMap[username] and activePlayersMap[username] ~= shKey then
                        houseData.members[username] = nil
                    elseif (currentEpoch - (memberData.leaveEpoch or currentEpoch)) >= HFTax.Config.PENDING_LEAVE_DAYS then
                        houseData.members[username] = nil
                    end
                end
            end
        end
    end

    -- 2. Init Online Players
    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            local uName = p:getUsername()
            HFTax.ServerCore.ensurePersonalTaxInit(uName, globalData, currentEpoch)
        end
    end

    for uName, pb in pairs(globalData.PersonalPreviews) do
        if pb and currentEpoch >= (pb.scheduledEpoch or (currentEpoch + 999)) then
            HFTax.ServerCore.dispatchPersonalBillFromPreview(uName, currentEpoch)
            anyDispatched = true
        end
    end

    -- 3. Accrue Daily Penalties and Flag Cutoff Stages
    for _, bill in pairs(globalData.Bills or {}) do
        if bill.status == HFTax.Config.BILL_STATUS.UNPAID and not bill.isWaived and (bill.basePayable or bill.totalAmount or 0) > 0 then
            local baseAmount = bill.basePayable or bill.totalAmount
            bill.basePayable = baseAmount

            local daysSinceCreated = currentEpoch - (bill.createdEpoch or currentEpoch)

            if daysSinceCreated >= HFTax.Config.STAGE1_DUE_DAYS then
                local overdueDays = daysSinceCreated - HFTax.Config.STAGE1_DUE_DAYS
                local fullOverdueDays = math.floor(overdueDays)
                
                local calculatedPenalty = math.floor(baseAmount * (fullOverdueDays * HFTax.Config.DAILY_PENALTY_RATE))
                if bill.penalty ~= calculatedPenalty or not bill.isOverdue then
                    bill.penalty = calculatedPenalty
                    bill.totalAmount = baseAmount + calculatedPenalty
                    bill.isOverdue = true
                    bill.overdueDays = fullOverdueDays
                    dataChanged = true
                end

                if daysSinceCreated >= (HFTax.Config.STAGE1_DUE_DAYS + HFTax.Config.STAGE2_CUTOFF_DAYS) then
                    bill.isCutoffStage = true
                else
                    bill.isCutoffStage = false
                end
            else
                bill.isOverdue = false
                bill.isCutoffStage = false
            end
        end
    end

    HFTax.ServerCore.processUtilityCutoffs(globalData, currentEpoch)
    HFTax.ServerCore.syncModData()

    HFTax.ServerCore.broadcastSafehouseStatus()
    if anyDispatched or dataChanged then
        HFTax.ServerCore.broadcastAdminData()
        HFTax.ServerCore.broadcastPlayerBills()
    end
end

function HFTax.ServerCore.dispatchBillFromPreview(sh, dbHouse, currentEpoch)
    local globalData = HFTax.ServerCore.getGlobalData()
    local pb = dbHouse.previewBill
    if not pb then return end

    local shKey = HFTax.Utils.getSafehouseKey(sh)
    local shid = dbHouse.shid or HFTax.Utils.getSafehouseSHID(sh)
    local billNumber = pb.billNumber or HFTax.Utils.formatBillNumber(dbHouse.billCounter or 1)
    local billId = HFTax.Utils.constructBillId("BILL", shid, billNumber)

    local owner = sh:getOwner()
    local ownerPUUID = HFTax.Utils.getPlayerPUUID(owner)

    local visibilityPUUIDs = {}
    if ownerPUUID then visibilityPUUIDs[ownerPUUID] = true end

    local memberNamesList = {}
    if owner then table.insert(memberNamesList, owner .. " (Owner)") end

    for dbUser, memberData in pairs(dbHouse.members or {}) do
        local puid = HFTax.Utils.getPlayerPUUID(dbUser)
        visibilityPUUIDs[puid] = true
        if dbUser ~= owner then
            local statusTag = (memberData.status == "PENDING") and " (Pending Leave)" or ""
            table.insert(memberNamesList, dbUser .. statusTag)
        end
    end

    local profileData = HFTax.Config.DefaultProfiles[dbHouse.profileId or "profile_default"] or HFTax.Config.DefaultProfiles["profile_default"]
    local w, h = sh:getW(), sh:getH()
    local lTax = pb.landTax or HFTax.Utils.calculateLandTax(w, h, profileData.ratePerTile)
    local mCount = sh:getPlayers() and sh:getPlayers():size() or 1
    local mTax, extraCount = HFTax.Utils.calculateMemberTax(mCount, profileData.freeMembers, profileData.ratePerExtraMember)
    local penalty = pb.penalty or 0

    local isWaived = (pb.isWaived == true)
    local finalPayableAmount = isWaived and 0 or (pb.totalAmount or (lTax + mTax + penalty))
    local noteText = pb.note or "Safehouse & Land Cycle Tax"
    if isWaived then
        noteText = noteText .. " [Waived for this cycle]"
    end

    globalData.Bills[billId] = {
        billId = billId,
        billNumber = billNumber,
        shid = shid,
        safehouseKey = shKey,
        safehouseTitle = sh:getTitle(),
        owner = owner,
        ownerPUUID = ownerPUUID,
        visibilityPUUIDs = visibilityPUUIDs,
        billType = HFTax.Config.BILL_TYPE.LAND,
        landTax = lTax,
        memberTax = mTax,
        basePayable = finalPayableAmount,
        penalty = penalty,
        totalAmount = finalPayableAmount,
        isWaived = isWaived,
        isOverdue = false,
        isCutoffStage = false,
        overdueDays = 0,
        note = noteText,
        breakdown = {
            dimensions = { w = w, h = h, totalTiles = w * h },
            landRate = profileData.ratePerTile,
            landSubtotal = lTax,
            memberQuota = profileData.freeMembers,
            memberCount = mCount,
            extraMembers = extraCount,
            memberRate = profileData.ratePerExtraMember,
            memberSubtotal = mTax,
            memberList = memberNamesList,
            penalty = penalty,
            calculatedTotal = lTax + mTax + penalty,
            totalAmount = finalPayableAmount,
            isWaived = isWaived
        },
        status = HFTax.Config.BILL_STATUS.UNPAID,
        createdEpoch = currentEpoch,
        createdDateStr = HFTax.Utils.getCurrentDateTimeString(),
        dueDaysEpoch = currentEpoch + HFTax.Config.STAGE1_DUE_DAYS,
        stage2Epoch = currentEpoch + HFTax.Config.STAGE1_DUE_DAYS + HFTax.Config.STAGE2_CUTOFF_DAYS,
        paidDateStr = nil,
        paidBy = nil
    }

    dbHouse.billCounter = (dbHouse.billCounter or 1) + 1
    local nextBillNumber = HFTax.Utils.formatBillNumber(dbHouse.billCounter)

    dbHouse.previewBill = {
        shid = shid,
        billNumber = nextBillNumber,
        landTax = lTax,
        memberTax = mTax,
        penalty = 0,
        totalAmount = lTax + mTax,
        note = "Safehouse & Land Cycle Tax",
        scheduledEpoch = currentEpoch + HFTax.Config.BILL_CYCLE_DAYS,
        customOverride = false,
        isWaived = false
    }
end

function HFTax.ServerCore.dispatchPersonalBillFromPreview(username, currentEpoch)
    local globalData = HFTax.ServerCore.getGlobalData()
    HFTax.ServerCore.ensurePersonalTaxInit(username, globalData, currentEpoch)

    local pb = globalData.PersonalPreviews[username]
    if not pb then return end

    local puuid = pb.puuid or HFTax.Utils.getPlayerPUUID(username)
    local curCounter = pb.billCounter or 1
    local billNumber = pb.billNumber or HFTax.Utils.formatBillNumber(curCounter)
    local billId = HFTax.Utils.constructBillId("PERS", puuid, billNumber)

    local isExempt, reason = HFTax.ServerCore.isPlayerExempt(username, globalData)
    local isWaived = (pb.isWaived == true) or isExempt
    local baseTax = pb.baseTax or HFTax.Config.DefaultPersonalTax.rate
    local penalty = pb.penalty or 0
    local finalPayableAmount = isWaived and 0 or (baseTax + penalty)

    local noteText = pb.note or "Personal Central Cycle Tax"
    if pb.isWaived then
        noteText = noteText .. " [Waived for this cycle]"
    elseif isExempt then
        if reason == "WAIVED_BY_ADMIN" then
            noteText = noteText .. " [Exempt: Waived by Admin]"
        elseif reason == "IN_SAFEHOUSE" then
            noteText = noteText .. " [Exempt: In Safehouse]"
        end
    end

    globalData.Bills[billId] = {
        billId = billId,
        billNumber = billNumber,
        puuid = puuid,
        safehouseKey = nil,
        safehouseTitle = nil,
        owner = username,
        ownerPUUID = puuid,
        visibilityPUUIDs = { [puuid] = true },
        billType = HFTax.Config.BILL_TYPE.PERSONAL,
        landTax = 0,
        memberTax = 0,
        basePayable = finalPayableAmount,
        penalty = penalty,
        totalAmount = finalPayableAmount,
        isWaived = isWaived,
        isOverdue = false,
        isCutoffStage = false,
        overdueDays = 0,
        note = noteText,
        breakdown = {
            baseTax = baseTax,
            penalty = penalty,
            calculatedTotal = baseTax + penalty,
            totalAmount = finalPayableAmount,
            isExempt = isExempt,
            exemptReason = reason,
            isWaived = isWaived
        },
        status = HFTax.Config.BILL_STATUS.UNPAID,
        createdEpoch = currentEpoch,
        createdDateStr = HFTax.Utils.getCurrentDateTimeString(),
        dueDaysEpoch = currentEpoch + HFTax.Config.STAGE1_DUE_DAYS,
        stage2Epoch = currentEpoch + HFTax.Config.STAGE1_DUE_DAYS + HFTax.Config.STAGE2_CUTOFF_DAYS,
        paidDateStr = nil,
        paidBy = nil
    }

    local nextCounter = curCounter + 1
    local nextBillNumber = HFTax.Utils.formatBillNumber(nextCounter)

    globalData.PersonalPreviews[username] = {
        puuid = puuid,
        billCounter = nextCounter,
        billNumber = nextBillNumber,
        baseTax = HFTax.Config.DefaultPersonalTax.rate,
        penalty = 0,
        totalAmount = HFTax.Config.DefaultPersonalTax.rate,
        note = "Personal Central Cycle Tax",
        scheduledEpoch = currentEpoch + HFTax.Config.DefaultPersonalTax.cycleDays,
        customOverride = false,
        isWaived = false
    }
end

function HFTax.ServerCore.processUtilityCutoffs(globalData, currentEpoch)
    local overdueSafehouses = {}

    for _, bill in pairs(globalData.Bills or {}) do
        if bill.safehouseKey and bill.status == HFTax.Config.BILL_STATUS.UNPAID and not bill.isWaived and (bill.totalAmount or 0) > 0 then
            local daysSinceCreated = currentEpoch - (bill.createdEpoch or currentEpoch)
            if daysSinceCreated >= (HFTax.Config.STAGE1_DUE_DAYS + HFTax.Config.STAGE2_CUTOFF_DAYS) or bill.isCutoffStage then
                overdueSafehouses[bill.safehouseKey] = true
            end
        end
    end

    local safehouses = SafeHouse.getSafehouseList()
    if not safehouses then return end

    for i = 0, safehouses:size() - 1 do
        local sh = safehouses:get(i)
        if sh then
            local shKey = HFTax.Utils.getSafehouseKey(sh)
            local dbHouse = globalData.Safehouses[shKey]

            if dbHouse then
                local shouldCutoff = overdueSafehouses[shKey] or false
                dbHouse.isCutoff = shouldCutoff

                if shouldCutoff then
                    local x1 = sh:getX() or 0
                    local y1 = sh:getY() or 0
                    local w = sh:getW() or 0
                    local h = sh:getH() or 0
                    local x2 = x1 + w - 1
                    local y2 = y1 + h - 1

                    HFTax.ServerCore.enforceAreaShutdown(x1, y1, x2, y2)
                end
            end
        end
    end
end

function HFTax.ServerCore.enforceAreaShutdown(x1, y1, x2, y2)
    local cell = getCell()
    if not cell then return end

    for z = 0, 7 do
        for x = x1, x2 do
            for y = y1, y2 do
                local sq = getSquare(x, y, z) or (cell.getGridSquare and cell:getGridSquare(x, y, z))
                if sq then
                    local generator = sq:getGenerator()
                    if generator then
                        pcall(function()
                            if generator.isActivated and generator:isActivated() then
                                generator:setActivated(false)
                            end
                        end)
                    end

                    local objects = sq:getObjects()
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local obj = objects:get(i)
                            if obj then
                                pcall(function()
                                    if instanceof(obj, "IsoLightSwitch") then
                                        if obj.setActive then
                                            obj:setActive(false)
                                        end
                                    elseif instanceof(obj, "IsoStove") then
                                        if obj.setActivated then
                                            obj:setActivated(false)
                                        end
                                    elseif instanceof(obj, "IsoRadio") or instanceof(obj, "IsoTelevision") then
                                        if obj.getDeviceData then
                                            local devData = obj:getDeviceData()
                                            if devData and devData.setIsTurnedOn then
                                                devData:setIsTurnedOn(false)
                                            end
                                        end
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
end

Events.OnInitGlobalModData.Add(function()
    local globalData = HFTax.ServerCore.getGlobalData()
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local safehouses = SafeHouse.getSafehouseList()

    if safehouses then
        for i = 0, safehouses:size() - 1 do
            local sh = safehouses:get(i)
            HFTax.ServerCore.ensureSafehouseInit(sh, globalData, currentEpoch)
        end
    end
    HFTax.ServerCore.syncModData()
end)

Events.EveryOneMinute.Add(HFTax.ServerCore.onCheckSchedulesAndSync)