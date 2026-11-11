-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISPanel"
require "ISUI/ISModalDialog"

HFTaxUI = HFTaxUI or {}
HFTaxUI.AdminUI = ISCollapsableWindow:derive("HFTax_AdminUI")
HFTaxUI.AdminUI.instance = nil

-- [Matasa Protected Core Watermark - Admin Master UI v19]
local _matasa_sec_id = "MATASA_HFTAX_2026_ADMIN_UI_V19_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

local function isPlayerAdmin(player)
    if not isClient() and not isServer() then return true end
    if isCoopHost() or (getCore() and getCore():getDebug()) then return true end
    if not player then return true end
    
    local ok, lvl = pcall(function() return player:getAccessLevel() end)
    if ok and lvl and lvl ~= "" and lvl:lower() ~= "none" then
        local l = lvl:lower()
        if l == "admin" or l == "moderator" or l == "gm" or l == "overseer" or l == "observer" then
            return true
        end
    end

    if isAdmin() or (player.isAccessLevel and player:isAccessLevel("admin")) then
        return true
    end

    return false
end

local function getPlayerSafehouseInfo(username)
    local safehouses = SafeHouse.getSafehouseList()
    if safehouses then
        for i = 0, safehouses:size() - 1 do
            local sh = safehouses:get(i)
            if sh:getOwner() == username or (sh:getPlayers() and sh:getPlayers():contains(username)) then
                return true, sh:getTitle() or "Safehouse", HFTax.Utils.getSafehouseSHID(sh)
            end
        end
    end
    return false, "None", "000000"
end

function HFTaxUI.AdminUI:new(x, y, width, height, player)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player or getPlayer()
    o.playerNum = o.player and o.player:getPlayerNum() or 0
    o.viewMode = "SAFES"
    o.selectedSafehouse = nil
    o.selectedPlayer = nil
    o.title = "HF_Tax :: Server Tax Master Console"
    o:setResizable(false)
    return o
end

function HFTaxUI.AdminUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local padding = 10
    local topOffset = 30
    local colW = (self.width - (padding * 3)) / 2
    local totalH = self.height - topOffset - padding
    local bottomActionH = 34
    local leftListH = totalH - 30 - bottomActionH - 4

    -- Left Pane: Display Mode Toggle & List
    self.toggleViewBtn = ISButton:new(padding, topOffset, colW, 25, "Display Mode: [ All Safehouses ]", self, self.onToggleViewMode)
    self.toggleViewBtn:initialise()
    self.toggleViewBtn:instantiate()
    self.toggleViewBtn.backgroundColor = {r = 0.2, g = 0.3, b = 0.5, a = 0.8}
    self:addChild(self.toggleViewBtn)

    self.leftListBox = ISScrollingListBox:new(padding, topOffset + 30, colW, leftListH)
    self.leftListBox:initialise()
    self.leftListBox:instantiate()
    self.leftListBox.itemheight = 48
    self.leftListBox.selected = 0
    self.leftListBox.joypadParent = self
    self.leftListBox.doDrawItem = self.drawLeftListItem
    self.leftListBox.onmousedown = self.onMouseDownLeftList
    self.leftListBox.target = self
    self:addChild(self.leftListBox)

    -- Left Pane: Bottom Wipe System Button
    local wipeBtnY = self.height - bottomActionH - padding
    self.wipeSystemBtn = ISButton:new(padding, wipeBtnY, colW, bottomActionH, "Wipe & Reset Tax System", self, self.onWipeTaxSystem)
    self.wipeSystemBtn:initialise()
    self.wipeSystemBtn:instantiate()
    self.wipeSystemBtn.backgroundColor = {r = 0.55, g = 0.12, b = 0.12, a = 0.95}
    self:addChild(self.wipeSystemBtn)

    -- Right Pane: Top Preview Panel
    local rightX = padding * 2 + colW
    local previewH = 165

    self.previewPanel = ISPanel:new(rightX, topOffset, colW, previewH)
    self.previewPanel:initialise()
    self.previewPanel:instantiate()
    self.previewPanel.target = self
    self.previewPanel.render = self.renderPreviewPanel
    self:addChild(self.previewPanel)

    local btnW = (colW - padding) / 2
    local btnY = previewH - 34

    self.billManageBtn = ISButton:new(0, btnY, btnW, 28, "Edit Bill", self, self.onOpenBillEditor)
    self.billManageBtn:initialise()
    self.billManageBtn:instantiate()
    self.billManageBtn.backgroundColor = {r = 0.1, g = 0.5, b = 0.2, a = 0.9}
    self.previewPanel:addChild(self.billManageBtn)

    self.waiveTaxBtn = ISButton:new(btnW + padding, btnY, btnW, 28, "Waive Tax", self, self.onWaiveCurrentTax)
    self.waiveTaxBtn:initialise()
    self.waiveTaxBtn:instantiate()
    self.waiveTaxBtn.backgroundColor = {r = 0.6, g = 0.4, b = 0.1, a = 0.9}
    self.previewPanel:addChild(self.waiveTaxBtn)

    -- Right Pane: Lower Member List
    local memberListY = topOffset + previewH + 8
    local memberListH = self.height - memberListY - bottomActionH - padding - 4

    self.memberListBox = ISScrollingListBox:new(rightX, memberListY, colW, memberListH)
    self.memberListBox:initialise()
    self.memberListBox:instantiate()
    self.memberListBox.itemheight = 28
    self.memberListBox.selected = 0
    self.memberListBox.doDrawItem = self.drawMemberListItem
    self:addChild(self.memberListBox)

    -- Right Pane: Bottom Force Send Button
    local forceSendY = self.height - bottomActionH - padding
    self.forceSendBtn = ISButton:new(rightX, forceSendY, colW, bottomActionH, "Force Send Bill Now", self, self.onForceSendBill)
    self.forceSendBtn:initialise()
    self.forceSendBtn:instantiate()
    self.forceSendBtn.backgroundColor = {r = 0.75, g = 0.25, b = 0.15, a = 0.95}
    self:addChild(self.forceSendBtn)

    if self.player then
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "RequestAdminData", {})
    end
    self:populateLeftList()
end

function HFTaxUI.AdminUI:onToggleViewMode()
    if self.viewMode == "SAFES" then
        self.viewMode = "PLAYERS"
        self.toggleViewBtn:setTitle("Display Mode: [ Online Players ]")
        self.toggleViewBtn.backgroundColor = {r = 0.5, g = 0.3, b = 0.2, a = 0.8}
    else
        self.viewMode = "SAFES"
        self.toggleViewBtn:setTitle("Display Mode: [ All Safehouses ]")
        self.toggleViewBtn.backgroundColor = {r = 0.2, g = 0.3, b = 0.5, a = 0.8}
    end
    self:populateLeftList()
end

function HFTaxUI.AdminUI:populateLeftList()
    self.leftListBox:clear()
    self.memberListBox:clear()

    if self.viewMode == "SAFES" then
        local safehouses = SafeHouse.getSafehouseList()
        if safehouses then
            for i = 0, safehouses:size() - 1 do
                local sh = safehouses:get(i)
                self.leftListBox:addItem(sh:getTitle() or "Safehouse", sh)
            end
        end
    else
        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                local p = players:get(i)
                self.leftListBox:addItem(p:getUsername(), p)
            end
        elseif self.player then
            self.leftListBox:addItem(self.player:getUsername(), self.player)
        end
    end
end

function HFTaxUI.AdminUI:drawLeftListItem(y, item, alt)
    local isSelected = self.selected == item.index
    local listW = self:getWidth()
    local itemH = item.height

    if isSelected then
        self:drawRect(0, y, listW, itemH - 1, 0.3, 0.4, 0.6, 0.8)
    elseif alt then
        self:drawRect(0, y, listW, itemH - 1, 0.1, 0.1, 0.1, 0.5)
    end

    self:drawRectBorder(0, y, listW, itemH, 0.5, 0.2, 0.2, 0.2)

    local targetObj = item.item
    if not targetObj then return y + itemH end

    if self.target.viewMode == "SAFES" then
        local sh = targetObj
        local shKey = HFTax.Utils.getSafehouseKey(sh)
        local shid = HFTax.Utils.getSafehouseSHID(sh)
        local owner = sh:getOwner() or "No Owner"
        local members = sh:getPlayers()
        local memberCount = members and members:size() or 0

        self:drawText(item.text, 10, y + 4, 1, 1, 1, 1, UIFont.Medium)

        local subText = string.format("Owner: %s | Members: %d | ID: #%s", owner, memberCount, shid)
        self:drawText(subText, 10, y + 26, 0.7, 0.7, 0.7, 1, UIFont.Small)

        local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
        local shData = globalData.Safehouses and globalData.Safehouses[shKey]
        local profileId = shData and shData.profileId or "profile_default"
        local isCommercial = (profileId == "profile_commercial")

        local btnW = 95
        local btnH = 24
        local btnX = listW - btnW - 10
        local btnY = y + 12

        local r, g, b = 0.15, 0.55, 0.2
        local badgeLabel = "Standard"
        if isCommercial then
            r, g, b = 0.15, 0.35, 0.75
            badgeLabel = "Commercial"
        end

        self:drawRect(btnX, btnY, btnW, btnH, 0.9, r, g, b)
        self:drawRectBorder(btnX, btnY, btnW, btnH, 1.0, 0.9, 0.9, 0.9)
        self:drawTextCentre(badgeLabel, btnX + (btnW / 2), btnY + 4, 1, 1, 1, 1, UIFont.Small)
    else
        local username = targetObj:getUsername()
        local puuid = HFTax.Utils.getPlayerPUUID(username)
        self:drawText(username, 10, y + 4, 1, 1, 1, 1, UIFont.Medium)

        local hasSafe, safeTitle, _ = getPlayerSafehouseInfo(username)
        if hasSafe then
            local subText = string.format("In-safe house (%s) | ID: #%s", safeTitle, puuid)
            self:drawText(subText, 10, y + 26, 0.2, 0.85, 0.5, 1, UIFont.Small)
        else
            local subText = string.format("ID: #%s", puuid)
            self:drawText(subText, 10, y + 26, 0.7, 0.7, 0.7, 1, UIFont.Small)
        end

        local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
        local pSettings = globalData.PlayerSettings and globalData.PlayerSettings[username]
        local taxStatus = pSettings and pSettings.taxStatus or "NORMAL"
        local isWaived = (taxStatus == "WAIVE_TAX")

        local btnW = 95
        local btnH = 24
        local btnX = listW - btnW - 10
        local btnY = y + 12

        local r, g, b = 0.15, 0.45, 0.75
        local badgeLabel = "Normal"
        if isWaived then
            r, g, b = 0.75, 0.45, 0.15
            badgeLabel = "Waive Tax"
        end

        self:drawRect(btnX, btnY, btnW, btnH, 0.9, r, g, b)
        self:drawRectBorder(btnX, btnY, btnW, btnH, 1.0, 0.9, 0.9, 0.9)
        self:drawTextCentre(badgeLabel, btnX + (btnW / 2), btnY + 4, 1, 1, 1, 1, UIFont.Small)
    end

    return y + itemH
end

function HFTaxUI.AdminUI:onMouseDownLeftList(item)
    if not item then return end

    local listW = self.leftListBox:getWidth()
    local mouseX = self.leftListBox:getMouseX()
    local btnW = 95
    local btnX = listW - btnW - 10

    if mouseX >= btnX and mouseX <= (btnX + btnW) then
        if self.viewMode == "SAFES" then
            local sh = item
            local shKey = HFTax.Utils.getSafehouseKey(sh)
            local shid = HFTax.Utils.getSafehouseSHID(sh)
            local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
            globalData.Safehouses = globalData.Safehouses or {}
            globalData.Safehouses[shKey] = globalData.Safehouses[shKey] or { profileId = "profile_default", shid = shid, billCounter = 1 }

            local curProfile = globalData.Safehouses[shKey].profileId or "profile_default"
            local newProfile = (curProfile == "profile_default") and "profile_commercial" or "profile_default"

            globalData.Safehouses[shKey].profileId = newProfile

            local profileData = HFTax.Config.DefaultProfiles[newProfile] or HFTax.Config.DefaultProfiles["profile_default"]
            local lTax = HFTax.Utils.calculateLandTax(sh:getW(), sh:getH(), profileData.ratePerTile)
            local mCount = sh:getPlayers() and sh:getPlayers():size() or 1
            local mTax = HFTax.Utils.calculateMemberTax(mCount, profileData.freeMembers, profileData.ratePerExtraMember)

            globalData.Safehouses[shKey].previewBill = globalData.Safehouses[shKey].previewBill or {}
            local pb = globalData.Safehouses[shKey].previewBill
            pb.shid = shid
            pb.billNumber = HFTax.Utils.formatBillNumber(globalData.Safehouses[shKey].billCounter or 1)
            pb.landTax = lTax
            pb.memberTax = mTax
            pb.totalAmount = pb.isWaived and 0 or (lTax + mTax + (pb.penalty or 0))
            pb.customOverride = false

            sendClientCommand(self.player, HFTax.Config.MOD_ID, "SetSafehouseProfile", {
                safehouseKey = shKey,
                profileId = newProfile
            })
            return
        else
            local p = item
            local username = p:getUsername()
            local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
            globalData.PlayerSettings = globalData.PlayerSettings or {}
            globalData.PlayerSettings[username] = globalData.PlayerSettings[username] or { taxStatus = "NORMAL" }

            local curStatus = globalData.PlayerSettings[username].taxStatus or "NORMAL"
            local newStatus = (curStatus == "NORMAL") and "WAIVE_TAX" or "NORMAL"

            globalData.PlayerSettings[username].taxStatus = newStatus

            sendClientCommand(self.player, HFTax.Config.MOD_ID, "SetPlayerTaxStatus", {
                username = username,
                status = newStatus
            })
            return
        end
    end

    self:onSelectLeftItem(item)
end

function HFTaxUI.AdminUI:onSelectLeftItem(item)
    self.memberListBox:clear()
    if not item then return end

    if self.viewMode == "SAFES" then
        self.selectedSafehouse = item
        local members = item:getPlayers()
        local owner = item:getOwner() or "No Owner"

        self.memberListBox:addItem("Owner: " .. tostring(owner), {status = "OWNER", username = owner})

        if members then
            for i = 0, members:size() - 1 do
                local mName = members:get(i)
                if mName ~= owner then
                    self.memberListBox:addItem("Member: " .. tostring(mName), {status = "ACTIVE", username = mName})
                end
            end
        end
    else
        self.selectedPlayer = item
        local username = item:getUsername()
        local hasSafe, safeTitle, _ = getPlayerSafehouseInfo(username)
        local puuid = HFTax.Utils.getPlayerPUUID(username)
        local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
        local pSettings = globalData.PlayerSettings and globalData.PlayerSettings[username]
        local taxStatus = pSettings and pSettings.taxStatus or "NORMAL"

        self.memberListBox:addItem("Player: " .. username .. " (ID: #" .. puuid .. ")", {status = "INFO"})
        self.memberListBox:addItem("Safehouse: " .. safeTitle, {status = "INFO"})
        
        local statusLabel = "TAXABLE (Personal Cycle)"
        if taxStatus == "WAIVE_TAX" then
            statusLabel = "EXEMPT (Admin Permanent Waive)"
        elseif hasSafe then
            statusLabel = "EXEMPT (Covered by Safehouse)"
        end
        self.memberListBox:addItem("Tax Status: " .. statusLabel, {status = (taxStatus == "WAIVE_TAX" or hasSafe) and "EXEMPT" or "ACTIVE"})
        self.memberListBox:addItem("Billing Cycle: Every 7 Real Days", {status = "INFO"})
    end
end

function HFTaxUI.AdminUI:renderPreviewPanel()
    local parent = self.target
    local w, h = self:getWidth(), self:getHeight()

    self:drawRect(0, 0, w, h, 0.25, 0.05, 0.05, 0.05)
    self:drawRectBorder(0, 0, w, h, 0.8, 0.85, 0.7, 0.2)

    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local currentEpoch = HFTax.Utils.getRealDaysEpoch()

    if parent.viewMode == "SAFES" then
        local sh = parent.selectedSafehouse
        if not sh then
            self:drawText("Select a safehouse to preview next cycle bill.", 12, 20, 0.6, 0.6, 0.6, 1, UIFont.Small)
            return
        end

        local shKey = HFTax.Utils.getSafehouseKey(sh)
        local shid = HFTax.Utils.getSafehouseSHID(sh)
        local shData = globalData.Safehouses and globalData.Safehouses[shKey]
        local profileId = (shData and shData.profileId) or "profile_default"
        local profileData = HFTax.Config.DefaultProfiles[profileId] or HFTax.Config.DefaultProfiles["profile_default"]

        local pb = shData and shData.previewBill
        if not pb then
            local lTax = HFTax.Utils.calculateLandTax(sh:getW(), sh:getH(), profileData.ratePerTile)
            local mCount = sh:getPlayers() and sh:getPlayers():size() or 1
            local mTax = HFTax.Utils.calculateMemberTax(mCount, profileData.freeMembers, profileData.ratePerExtraMember)
            pb = {
                shid = shid,
                billNumber = HFTax.Utils.formatBillNumber((shData and shData.billCounter) or 1),
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

        local headerTitle = string.format("Upcoming Land Bill Preview [#%s-%s]", pb.shid or shid, pb.billNumber or "001")
        self:drawText(headerTitle, 10, 8, 1, 0.85, 0.2, 1, UIFont.Medium)

        local countdownText = "Schedule: Auto-Send in " .. HFTax.Utils.formatRemainingTime(pb.scheduledEpoch or (currentEpoch + 7))
        self:drawText(countdownText, 10, 30, 0.35, 0.8, 1, 1, UIFont.Small)

        local overrideBadge = "[Auto-Sync]"
        if pb.isWaived then
            overrideBadge = "[Waived Draft]"
        elseif pb.customOverride then
            overrideBadge = "[Custom Preset]"
        end

        local line1 = string.format("Land: $%d | Extra Members: $%d | Penalty: $%d  %s", pb.landTax or 0, pb.memberTax or 0, pb.penalty or 0, overrideBadge)
        self:drawText(line1, 10, 48, 0.8, 0.8, 0.8, 1, UIFont.Small)

        local finalAmt = pb.isWaived and 0 or (pb.totalAmount or 0)
        local totalText = string.format("Net Estimated Amount: $%d", finalAmt)
        local r, g, b = pb.isWaived and 0.95 or 0.2, pb.isWaived and 0.7 or 0.95, pb.isWaived and 0.2 or 0.3
        self:drawText(totalText, 10, 68, r, g, b, 1, UIFont.Medium)

        local noteText = string.format("Note: %s", pb.note or "N/A")
        self:drawText(noteText, 10, 92, 0.65, 0.65, 0.65, 1, UIFont.Small)
    else
        local playerObj = parent.selectedPlayer
        if not playerObj then
            self:drawText("Select an online player to preview personal tax bill.", 12, 20, 0.6, 0.6, 0.6, 1, UIFont.Small)
            return
        end

        local username = playerObj:getUsername()
        local puuid = HFTax.Utils.getPlayerPUUID(username)
        local pb = globalData.PersonalPreviews and globalData.PersonalPreviews[username]
        if not pb then
            pb = {
                puuid = puuid,
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

        local hasSafe, _, _ = getPlayerSafehouseInfo(username)
        local pSettings = globalData.PlayerSettings and globalData.PlayerSettings[username]
        local taxStatus = pSettings and pSettings.taxStatus or "NORMAL"
        local isPermanentWaive = (taxStatus == "WAIVE_TAX")
        local isDraftWaive = (pb.isWaived == true)
        local isExempt = isPermanentWaive or hasSafe or isDraftWaive

        local headerTitle = string.format("Upcoming Personal Bill [#%s-%s]", pb.puuid or puuid, pb.billNumber or "001")
        self:drawText(headerTitle, 10, 8, 1, 0.85, 0.2, 1, UIFont.Medium)

        local countdownText = "Schedule: Auto-Send in " .. HFTax.Utils.formatRemainingTime(pb.scheduledEpoch or (currentEpoch + 7))
        self:drawText(countdownText, 10, 30, 0.35, 0.8, 1, 1, UIFont.Small)

        local statusTag = "[Standard Rate]"
        if isDraftWaive then
            statusTag = "[Waived Draft]"
        elseif isPermanentWaive then
            statusTag = "[EXEMPT - Admin Waived]"
        elseif hasSafe then
            statusTag = "[EXEMPT - In Safehouse]"
        elseif pb.customOverride then
            statusTag = "[Custom Preset]"
        end

        local line1 = string.format("Personal Base: $%d | Penalty: $%d  %s", pb.baseTax or 0, pb.penalty or 0, statusTag)
        self:drawText(line1, 10, 48, 0.8, 0.8, 0.8, 1, UIFont.Small)

        local finalAmt = isExempt and 0 or (pb.totalAmount or 0)
        local totalText = string.format("Net Estimated Amount: $%d", finalAmt)
        self:drawText(totalText, 10, 68, isExempt and 0.5 or 0.2, isExempt and 0.8 or 0.95, isExempt and 1.0 or 0.3, 1, UIFont.Medium)

        local noteText = string.format("Note: %s", pb.note or "N/A")
        self:drawText(noteText, 10, 92, 0.65, 0.65, 0.65, 1, UIFont.Small)
    end
end

function HFTaxUI.AdminUI:drawMemberListItem(y, item, alt)
    if alt then
        self:drawRect(0, y, self:getWidth(), item.height - 1, 0.1, 0.1, 0.1, 0.4)
    end

    local d = item.item
    local statusText = "[ACTIVE]"
    local r, g, b = 0.2, 0.8, 0.2

    if d and d.status == "OWNER" then
        statusText = "[OWNER]"
        r, g, b = 1.0, 0.8, 0.2
    elseif d and d.status == "PENDING" then
        statusText = "[LEAVE 7D]"
        r, g, b = 0.9, 0.3, 0.2
    elseif d and d.status == "EXEMPT" then
        statusText = "[EXEMPT]"
        r, g, b = 0.4, 0.7, 1.0
    elseif d and d.status == "INFO" then
        statusText = ""
    end

    self:drawText(item.text, 10, y + 5, 1, 1, 1, 1, UIFont.Small)
    if statusText ~= "" then
        self:drawTextRight(statusText, self:getWidth() - 10, y + 5, r, g, b, 1, UIFont.Small)
    end
    return y + item.height
end

function HFTaxUI.AdminUI:onOpenBillEditor()
    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)

    if self.viewMode == "SAFES" then
        if not self.selectedSafehouse then return end
        local shKey = HFTax.Utils.getSafehouseKey(self.selectedSafehouse)
        local shid = HFTax.Utils.getSafehouseSHID(self.selectedSafehouse)
        local shData = globalData.Safehouses and globalData.Safehouses[shKey]
        local profileId = (shData and shData.profileId) or "profile_default"
        local profileData = HFTax.Config.DefaultProfiles[profileId] or HFTax.Config.DefaultProfiles["profile_default"]

        local pb = shData and shData.previewBill
        if not pb then
            local lTax = HFTax.Utils.calculateLandTax(self.selectedSafehouse:getW(), self.selectedSafehouse:getH(), profileData.ratePerTile)
            local mCount = self.selectedSafehouse:getPlayers() and self.selectedSafehouse:getPlayers():size() or 1
            local mTax = HFTax.Utils.calculateMemberTax(mCount, profileData.freeMembers, profileData.ratePerExtraMember)
            pb = {
                shid = shid,
                billNumber = HFTax.Utils.formatBillNumber((shData and shData.billCounter) or 1),
                landTax = lTax,
                memberTax = mTax,
                penalty = 0,
                totalAmount = lTax + mTax,
                note = "Safehouse & Land Cycle Tax"
            }
        end

        if HFTaxUI and HFTaxUI.AdminBillEditor then
            HFTaxUI.AdminBillEditor.openWindow(self.player, self.selectedSafehouse, pb, nil)
        end
    else
        if not self.selectedPlayer then return end
        local username = self.selectedPlayer:getUsername()
        local puuid = HFTax.Utils.getPlayerPUUID(username)
        local pb = globalData.PersonalPreviews and globalData.PersonalPreviews[username]
        if not pb then
            pb = {
                puuid = puuid,
                billNumber = HFTax.Utils.formatBillNumber(1),
                baseTax = HFTax.Config.DefaultPersonalTax.rate,
                penalty = 0,
                totalAmount = HFTax.Config.DefaultPersonalTax.rate,
                note = "Personal Central Cycle Tax"
            }
        end

        if HFTaxUI and HFTaxUI.AdminBillEditor then
            HFTaxUI.AdminBillEditor.openWindow(self.player, nil, pb, username)
        end
    end
end

function HFTaxUI.AdminUI:onWaiveCurrentTax()
    if self.viewMode == "SAFES" then
        if not self.selectedSafehouse then return end
        local shKey = HFTax.Utils.getSafehouseKey(self.selectedSafehouse)
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "WaiveSafehouseTax", {
            safehouseKey = shKey
        })
    else
        if not self.selectedPlayer then return end
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "WaivePersonalTax", {
            username = self.selectedPlayer:getUsername()
        })
    end
end

function HFTaxUI.AdminUI:onForceSendBill()
    if self.viewMode == "SAFES" then
        if not self.selectedSafehouse then return end
        local shKey = HFTax.Utils.getSafehouseKey(self.selectedSafehouse)
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "ForceSendSafehouseBill", {
            safehouseKey = shKey
        })
    else
        if not self.selectedPlayer then return end
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "ForceSendPersonalBill", {
            username = self.selectedPlayer:getUsername()
        })
    end
end

function HFTaxUI.AdminUI:onWipeTaxSystem()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local modalW, modalH = 380, 150
    local modalX = (sw - modalW) / 2
    local modalY = (sh - modalH) / 2

    local modal = ISModalDialog:new(modalX, modalY, modalW, modalH, "Are you sure you want to WIPE and RESET all tax data?\nThis will clear all active bills, drafts, and restart counters.", true, self, self.onConfirmWipe)
    modal:initialise()
    modal:addToUIManager()
end

function HFTaxUI.AdminUI:onConfirmWipe(button)
    if button.internal == "YES" then
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "WipeTaxSystem", {})
    end
end

function HFTaxUI.AdminUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    HFTaxUI.AdminUI.instance = nil
end

function HFTaxUI.AdminUI.openWindow(player)
    local targetPlayer = player
    if not targetPlayer or type(targetPlayer) == "number" then
        targetPlayer = (type(player) == "number" and getSpecificPlayer(player)) or getPlayer()
    end

    if not isPlayerAdmin(targetPlayer) then return end

    if HFTaxUI.AdminUI.instance then
        HFTaxUI.AdminUI.instance:setVisible(true)
        HFTaxUI.AdminUI.instance:addToUIManager()
        if targetPlayer then
            sendClientCommand(targetPlayer, HFTax.Config.MOD_ID, "RequestAdminData", {})
        end
        return
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 840, 540
    local x, y = (sw - w) / 2, (sh - h) / 2

    local ui = HFTaxUI.AdminUI:new(x, y, w, h, targetPlayer)
    ui:initialise()
    ui:addToUIManager()
    HFTaxUI.AdminUI.instance = ui
end