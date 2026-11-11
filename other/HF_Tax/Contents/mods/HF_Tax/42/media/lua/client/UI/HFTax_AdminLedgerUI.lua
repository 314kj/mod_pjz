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
require "ISUI/ISTextBox"
require "ISUI/ISTickBox"

HFTaxUI = HFTaxUI or {}
HFTaxUI.AdminLedgerUI = ISCollapsableWindow:derive("HFTax_AdminLedgerUI")
HFTaxUI.AdminLedgerUI.instance = nil

-- [Matasa Protected Core Watermark - Admin Ledger Single Line TickBox v52]
local _matasa_sec_id = "MATASA_HFTAX_2026_ADMIN_LEDGER_SINGLELINE_V52_SEC"
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

function HFTaxUI.AdminLedgerUI:new(x, y, width, height, player)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player or getPlayer()
    o.playerNum = o.player and o.player:getPlayerNum() or 0
    o.viewMode = "SAFES"
    o.selectedTarget = nil
    o.selectedBill = nil
    o.title = "HF_Tax :: Server Tax & Invoice Audit Ledger"
    o:setResizable(false)
    o.backgroundColor = {r = 0.08, g = 0.08, b = 0.08, a = 0.98}
    o.borderColor = {r = 0.35, g = 0.35, b = 0.35, a = 1.0}
    return o
end

function HFTaxUI.AdminLedgerUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local pad = 12
    local topOffset = 34
    local totalH = self.height - topOffset - pad
    local colW = (self.width - (pad * 3)) / 2
    local bottomActionH = 34

    -- Mode Toggle Button
    local modeBtnW = math.floor(colW * 0.40)
    self.toggleViewBtn = ISButton:new(pad, topOffset, modeBtnW, 26, "Mode: [ Safehouses ]", self, self.onToggleViewMode)
    self.toggleViewBtn:initialise()
    self.toggleViewBtn:instantiate()
    self.toggleViewBtn.backgroundColor = {r = 0.2, g = 0.3, b = 0.5, a = 0.9}
    self:addChild(self.toggleViewBtn)

    -- Single Line Side-by-Side Payment Tickboxes
    local tick1X = pad + modeBtnW + 8
    local tick1W = 120
    self.cashTickBox = ISTickBox:new(tick1X, topOffset + 3, tick1W, 20, "", self, self.onToggleCashOption)
    self.cashTickBox:initialise()
    self.cashTickBox:addOption("Cash (In Hand)")
    self:addChild(self.cashTickBox)

    local tick2X = tick1X + tick1W + 4
    local tick2W = 130
    self.bankTickBox = ISTickBox:new(tick2X, topOffset + 3, tick2W, 20, "", self, self.onToggleBankOption)
    self.bankTickBox:initialise()
    self.bankTickBox:addOption("Bank (Akacount)")
    self:addChild(self.bankTickBox)

    local leftListH = totalH - 34 - bottomActionH - 6
    self.leftListBox = ISScrollingListBox:new(pad, topOffset + 34, colW, leftListH)
    self.leftListBox:initialise()
    self.leftListBox:instantiate()
    self.leftListBox.itemheight = 54
    self.leftListBox.selected = 0
    self.leftListBox.joypadParent = self
    self.leftListBox.doDrawItem = self.drawLeftListItem
    self.leftListBox.onmousedown = self.onSelectLeftItem
    self.leftListBox.target = self
    self:addChild(self.leftListBox)

    local leftBtnW = (colW - pad) / 2
    self.refreshDataBtn = ISButton:new(pad, self.height - bottomActionH - pad, leftBtnW, bottomActionH, "Refresh Ledger", self, self.onRefreshData)
    self.refreshDataBtn:initialise()
    self.refreshDataBtn:instantiate()
    self.refreshDataBtn.backgroundColor = {r = 0.15, g = 0.45, b = 0.75, a = 0.9}
    self:addChild(self.refreshDataBtn)

    self.switchConsoleBtn = ISButton:new(pad + leftBtnW + pad, self.height - bottomActionH - pad, leftBtnW, bottomActionH, "Open Master Console", self, self.onOpenMasterConsole)
    self.switchConsoleBtn:initialise()
    self.switchConsoleBtn:instantiate()
    self.switchConsoleBtn.backgroundColor = {r = 0.45, g = 0.25, b = 0.65, a = 0.9}
    self:addChild(self.switchConsoleBtn)

    -- Right Pane: Historical Ledger & Financial Summary
    local rightX = pad * 2 + colW
    local summaryH = 76

    self.summaryPanel = ISPanel:new(rightX, topOffset, colW, summaryH)
    self.summaryPanel:initialise()
    self.summaryPanel:instantiate()
    self.summaryPanel.render = self.renderSummaryPanel
    self.summaryPanel.target = self
    self:addChild(self.summaryPanel)

    local rightListY = topOffset + summaryH + 8
    local rightListH = totalH - summaryH - 8 - bottomActionH - 6

    self.billHistoryBox = ISScrollingListBox:new(rightX, rightListY, colW, rightListH)
    self.billHistoryBox:initialise()
    self.billHistoryBox:instantiate()
    self.billHistoryBox.itemheight = 64
    self.billHistoryBox.selected = 0
    self.billHistoryBox.joypadParent = self
    self.billHistoryBox.doDrawItem = self.drawBillHistoryItem
    self.billHistoryBox.onmousedown = self.onMouseDownBillHistory
    self.billHistoryBox.target = self
    self:addChild(self.billHistoryBox)

    local rightBtnW = (colW - (pad * 2)) / 3
    local rightBtnY = self.height - bottomActionH - pad

    self.withdrawBtn = ISButton:new(rightX, rightBtnY, rightBtnW, bottomActionH, "Withdraw Cash", self, self.onOpenWithdrawModal)
    self.withdrawBtn:initialise()
    self.withdrawBtn:instantiate()
    self.withdrawBtn.backgroundColor = {r = 0.65, g = 0.45, b = 0.15, a = 0.95}
    self:addChild(self.withdrawBtn)

    self.viewInvoiceBtn = ISButton:new(rightX + rightBtnW + pad, rightBtnY, rightBtnW, bottomActionH, "View Invoice", self, self.onOpenSelectedInvoice)
    self.viewInvoiceBtn:initialise()
    self.viewInvoiceBtn:instantiate()
    self.viewInvoiceBtn.backgroundColor = {r = 0.1, g = 0.55, b = 0.25, a = 0.9}
    self:addChild(self.viewInvoiceBtn)

    self.closeBtn = ISButton:new(rightX + (rightBtnW * 2) + (pad * 2), rightBtnY, rightBtnW, bottomActionH, "Close", self, self.close)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.backgroundColor = {r = 0.35, g = 0.35, b = 0.35, a = 0.85}
    self:addChild(self.closeBtn)

    self:updatePaymentTickBoxState()
    self:onRefreshData()
end

function HFTaxUI.AdminLedgerUI:updatePaymentTickBoxState()
    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local pSettings = globalData.PaymentSettings or { allowCash = true, allowBank = true }
    if self.cashTickBox then
        self.cashTickBox:setSelected(1, pSettings.allowCash == true)
    end
    if self.bankTickBox then
        self.bankTickBox:setSelected(1, pSettings.allowBank == true)
    end
end

function HFTaxUI.AdminLedgerUI:onToggleCashOption(index, selected)
    local allowCash = self.cashTickBox:isSelected(1)
    local allowBank = self.bankTickBox:isSelected(1)
    sendClientCommand(self.player, HFTax.Config.MOD_ID, "SetPaymentSettings", {
        allowCash = allowCash,
        allowBank = allowBank
    })
end

function HFTaxUI.AdminLedgerUI:onToggleBankOption(index, selected)
    local allowCash = self.cashTickBox:isSelected(1)
    local allowBank = self.bankTickBox:isSelected(1)
    sendClientCommand(self.player, HFTax.Config.MOD_ID, "SetPaymentSettings", {
        allowCash = allowCash,
        allowBank = allowBank
    })
end

function HFTaxUI.AdminLedgerUI:onOpenMasterConsole()
    if HFTaxUI and HFTaxUI.AdminUI then
        HFTaxUI.AdminUI.openWindow(self.player)
    end
end

function HFTaxUI.AdminLedgerUI:onOpenWithdrawModal()
    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local treasury = globalData.Treasury or { vaultBalance = 0 }
    local maxVault = treasury.vaultBalance or 0

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local modalW, modalH = 340, 170
    local modalX = (sw - modalW) / 2
    local modalY = (sh - modalH) / 2

    local promptText = string.format("Enter amount to withdraw ($):\n[ Available in Vault: $%d ]", maxVault)
    local defaultVal = tostring(math.min(100, maxVault))
    
    local modal = ISTextBox:new(modalX, modalY, modalW, modalH, promptText, defaultVal, self, self.onConfirmWithdraw, self.playerNum)
    modal:initialise()
    modal:setOnlyNumbers(true)
    modal:addToUIManager()
    modal:bringToTop()
end

function HFTaxUI.AdminLedgerUI:onConfirmWithdraw(button)
    if not button then return end
    if button.internal == "OK" then
        local modal = button.parent
        local entryText = (modal and modal.entry and modal.entry.getText and modal.entry:getText()) or ""
        local requestedAmount = math.floor(tonumber(entryText) or 0)

        if requestedAmount > 0 then
            sendClientCommand(self.player, HFTax.Config.MOD_ID, "WithdrawTreasury", {
                amount = requestedAmount
            })
        end
    end
end

function HFTaxUI.AdminLedgerUI:onToggleViewMode()
    if self.viewMode == "SAFES" then
        self.viewMode = "PLAYERS"
        self.toggleViewBtn:setTitle("Mode: [ Players ]")
        self.toggleViewBtn.backgroundColor = {r = 0.5, g = 0.3, b = 0.2, a = 0.9}
    else
        self.viewMode = "SAFES"
        self.toggleViewBtn:setTitle("Mode: [ Safehouses ]")
        self.toggleViewBtn.backgroundColor = {r = 0.2, g = 0.3, b = 0.5, a = 0.9}
    end
    self.selectedTarget = nil
    self.selectedBill = nil
    self.leftListBox.selected = 0
    self:populateLeftList()
end

function HFTaxUI.AdminLedgerUI:onRefreshData()
    if self.player then
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "RequestAdminData", {})
    end
    self:updatePaymentTickBoxState()
    self:populateLeftList()
end

function HFTaxUI.AdminLedgerUI:populateLeftList()
    local savedShKey = (self.viewMode == "SAFES" and self.selectedTarget) and self.selectedTarget.shKey or nil
    local savedUsername = (self.viewMode == "PLAYERS" and self.selectedTarget) and self.selectedTarget.username or nil
    local restoreItem = nil
    local restoreIndex = 0

    self.leftListBox:clear()
    self.selectedTarget = nil

    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local bills = globalData.Bills or {}

    if self.viewMode == "SAFES" then
        local safehouses = SafeHouse.getSafehouseList()
        if safehouses then
            for i = 0, safehouses:size() - 1 do
                local sh = safehouses:get(i)
                local shKey = HFTax.Utils.getSafehouseKey(sh)
                
                local billCount = 0
                local unpaidCount = 0
                for _, b in pairs(bills) do
                    if b.safehouseKey == shKey then
                        billCount = billCount + 1
                        if b.status == HFTax.Config.BILL_STATUS.UNPAID then
                            unpaidCount = unpaidCount + 1
                        end
                    end
                end

                local itemData = {
                    obj = sh,
                    shKey = shKey,
                    shid = HFTax.Utils.getSafehouseSHID(sh),
                    owner = sh:getOwner() or "None",
                    totalBills = billCount,
                    unpaidBills = unpaidCount
                }

                self.leftListBox:addItem(sh:getTitle() or "Safehouse", itemData)
                local currentNumericIdx = #self.leftListBox.items

                if savedShKey and shKey == savedShKey then
                    restoreItem = itemData
                    restoreIndex = currentNumericIdx
                end
            end
        end
    else
        local playersMap = {}

        local onlinePlayers = getOnlinePlayers()
        if onlinePlayers then
            for i = 0, onlinePlayers:size() - 1 do
                local p = onlinePlayers:get(i)
                playersMap[p:getUsername()] = true
            end
        elseif self.player then
            playersMap[self.player:getUsername()] = true
        end

        for _, b in pairs(bills) do
            if b.billType == HFTax.Config.BILL_TYPE.PERSONAL and b.owner then
                playersMap[b.owner] = true
            end
        end

        for username, _ in pairs(playersMap) do
            local puuid = HFTax.Utils.getPlayerPUUID(username)
            local billCount = 0
            local unpaidCount = 0
            for _, b in pairs(bills) do
                if (b.billType == HFTax.Config.BILL_TYPE.PERSONAL and b.owner == username) or (b.ownerPUUID == puuid) then
                    billCount = billCount + 1
                    if b.status == HFTax.Config.BILL_STATUS.UNPAID then
                        unpaidCount = unpaidCount + 1
                    end
                end
            end

            local itemData = {
                username = username,
                puuid = puuid,
                totalBills = billCount,
                unpaidBills = unpaidCount
            }

            self.leftListBox:addItem(username, itemData)
            local currentNumericIdx = #self.leftListBox.items

            if savedUsername and username == savedUsername then
                restoreItem = itemData
                restoreIndex = currentNumericIdx
            end
        end
    end

    if restoreItem and restoreIndex > 0 then
        self.selectedTarget = restoreItem
        self.leftListBox.selected = restoreIndex
        self:populateBillHistory()
    else
        self.leftListBox.selected = 0
        self.billHistoryBox:clear()
        self.selectedBill = nil
    end
end

function HFTaxUI.AdminLedgerUI:drawLeftListItem(y, item, alt)
    local isSelected = (self.selected == item.itemindex) or (self.selected == item.index)
    local listW = self:getWidth()
    local itemH = item.height

    if isSelected then
        self:drawRect(0, y, listW, itemH - 1, 0.3, 0.4, 0.6, 0.8)
    elseif alt then
        self:drawRect(0, y, listW, itemH - 1, 0.1, 0.1, 0.1, 0.5)
    end

    self:drawRectBorder(0, y, listW, itemH, 0.5, 0.2, 0.2, 0.2)

    local data = item.item
    if not data then return y + itemH end

    if self.target.viewMode == "SAFES" then
        self:drawText(item.text, 12, y + 6, 1, 1, 1, 1, UIFont.Medium)
        local subText = "Owner: " .. tostring(data.owner) .. " | ID: #" .. tostring(data.shid)
        self:drawText(subText, 12, y + 30, 0.7, 0.7, 0.7, 1, UIFont.Small)

        local badgeText = "Bills: " .. tostring(data.totalBills) .. " (" .. tostring(data.unpaidBills) .. " Unpaid)"
        local br, bg, bb = (data.unpaidBills > 0) and 0.95 or 0.4, (data.unpaidBills > 0) and 0.3 or 0.8, 0.4
        self:drawTextRight(badgeText, listW - 14, y + 16, br, bg, bb, 1, UIFont.Small)
    else
        self:drawText(data.username, 12, y + 6, 1, 1, 1, 1, UIFont.Medium)
        local subText = "Player ID: #" .. tostring(data.puuid)
        self:drawText(subText, 12, y + 30, 0.7, 0.7, 0.7, 1, UIFont.Small)

        local badgeText = "Bills: " .. tostring(data.totalBills) .. " (" .. tostring(data.unpaidBills) .. " Unpaid)"
        local br, bg, bb = (data.unpaidBills > 0) and 0.95 or 0.4, (data.unpaidBills > 0) and 0.3 or 0.8, 0.4
        self:drawTextRight(badgeText, listW - 14, y + 16, br, bg, bb, 1, UIFont.Small)
    end

    return y + itemH
end

function HFTaxUI.AdminLedgerUI:onSelectLeftItem(item)
    self.selectedTarget = item
    self.selectedBill = nil
    self:populateBillHistory()
end

function HFTaxUI.AdminLedgerUI:populateBillHistory()
    self.billHistoryBox:clear()
    self.billHistoryBox.selected = 0
    if not self.selectedTarget then return end

    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local bills = globalData.Bills or {}
    local matchingBills = {}

    if self.viewMode == "SAFES" then
        local shKey = self.selectedTarget.shKey
        for _, b in pairs(bills) do
            if b.safehouseKey == shKey then
                table.insert(matchingBills, b)
            end
        end
    else
        local username = self.selectedTarget.username
        local puuid = self.selectedTarget.puuid
        for _, b in pairs(bills) do
            if (b.billType == HFTax.Config.BILL_TYPE.PERSONAL and b.owner == username) or (b.ownerPUUID == puuid) then
                table.insert(matchingBills, b)
            end
        end
    end

    table.sort(matchingBills, function(a, b)
        return (a.createdEpoch or 0) > (b.createdEpoch or 0)
    end)

    for _, b in ipairs(matchingBills) do
        self.billHistoryBox:addItem(b.billId, b)
    end
end

function HFTaxUI.AdminLedgerUI:renderSummaryPanel()
    local parent = self.target
    local w, h = self:getWidth(), self:getHeight()

    self:drawRect(0, 0, w, h, 0.35, 0.05, 0.05, 0.05)
    self:drawRectBorder(0, 0, w, h, 0.7, 0.85, 0.7, 0.2)

    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local treasury = globalData.Treasury or { vaultBalance = 0, totalPlayerCollected = 0, totalAdminSubsidized = 0, totalWithdrawn = 0 }
    
    local vaultLine = string.format("TREASURY VAULT: $%d | Player Paid: $%d | Subsidized: $%d", 
        treasury.vaultBalance or 0, treasury.totalPlayerCollected or 0, treasury.totalAdminSubsidized or 0)
    self:drawText(vaultLine, 12, 6, 0.3, 0.95, 0.3, 1, UIFont.Small)

    if not parent.selectedTarget then
        self:drawText("Select a safehouse or player on the left to view audit ledger.", 12, 38, 0.65, 0.65, 0.65, 1, UIFont.Small)
        return
    end

    local bills = globalData.Bills or {}
    local totalInvoiced = 0
    local totalCollected = 0
    local totalOutstanding = 0

    if parent.viewMode == "SAFES" then
        local shKey = parent.selectedTarget.shKey
        for _, b in pairs(bills) do
            if b.safehouseKey == shKey then
                local amt = b.totalAmount or 0
                totalInvoiced = totalInvoiced + amt
                if b.status == HFTax.Config.BILL_STATUS.PAID then
                    totalCollected = totalCollected + amt
                elseif b.status == HFTax.Config.BILL_STATUS.UNPAID then
                    totalOutstanding = totalOutstanding + amt
                end
            end
        end
    else
        local username = parent.selectedTarget.username
        local puuid = parent.selectedTarget.puuid
        for _, b in pairs(bills) do
            if (b.billType == HFTax.Config.BILL_TYPE.PERSONAL and b.owner == username) or (b.ownerPUUID == puuid) then
                local amt = b.totalAmount or 0
                totalInvoiced = totalInvoiced + amt
                if b.status == HFTax.Config.BILL_STATUS.PAID then
                    totalCollected = totalCollected + amt
                elseif b.status == HFTax.Config.BILL_STATUS.UNPAID then
                    totalOutstanding = totalOutstanding + amt
                end
            end
        end
    end

    local titleStr = (parent.viewMode == "SAFES") and ("Target: " .. tostring(parent.selectedTarget.obj:getTitle()) .. " (#" .. tostring(parent.selectedTarget.shid) .. ")")
                                                  or ("Target: " .. tostring(parent.selectedTarget.username) .. " (#" .. tostring(parent.selectedTarget.puuid) .. ")")
    self:drawText(titleStr, 12, 28, 1, 0.85, 0.2, 1, UIFont.Small)

    local statStr = "Invoiced: $" .. tostring(totalInvoiced) .. " | Collected: $" .. tostring(totalCollected) .. " | Outstanding: $" .. tostring(totalOutstanding)
    self:drawText(statStr, 12, 50, 0.85, 0.85, 0.85, 1, UIFont.Small)
end

function HFTaxUI.AdminLedgerUI:drawBillHistoryItem(y, item, alt)
    local isSelected = (self.selected == item.itemindex) or (self.selected == item.index)
    local listW = self:getWidth()
    local itemH = item.height

    if isSelected then
        self:drawRect(0, y, listW, itemH - 1, 0.25, 0.3, 0.45, 0.7)
    elseif alt then
        self:drawRect(0, y, listW, itemH - 1, 0.08, 0.08, 0.08, 0.4)
    end

    self:drawRectBorder(0, y, listW, itemH, 0.4, 0.25, 0.25, 0.25)

    local bill = item.item
    if not bill then return y + itemH end

    local isLand = (bill.billType == HFTax.Config.BILL_TYPE.LAND)
    local idPrefix = isLand and (bill.shid or "000000") or (bill.puuid or "P00000")
    local billTitle = "Invoice #" .. tostring(idPrefix) .. "-" .. tostring(bill.billNumber or "001")
    
    local btnStatusW, btnStatusH = 110, 28
    local btnStatusX = listW - btnStatusW - 14
    local btnStatusY = y + 18

    self:drawText(billTitle, 12, y + 8, 1, 1, 1, 1, UIFont.Medium)

    local textManager = getTextManager()
    local titleW = textManager and textManager:MeasureStringX(UIFont.Medium, billTitle) or 160
    local amountText = "$" .. tostring(bill.totalAmount or 0)
    self:drawText(amountText, 12 + titleW + 12, y + 8, 0.2, 0.95, 0.3, 1, UIFont.Medium)

    local subText = "Issued: " .. tostring(bill.createdDateStr or "Recent") .. " | Payer: " .. tostring(bill.owner or "N/A")
    if bill.status == HFTax.Config.BILL_STATUS.PAID then
        subText = subText .. " | Paid by: " .. tostring(bill.paidBy or "N/A")
    elseif bill.isOverdue then
        subText = subText .. " | Overdue: " .. tostring(bill.overdueDays or 0) .. " Days"
    end
    self:drawText(subText, 12, y + 36, 0.65, 0.65, 0.65, 1, UIFont.Small)

    local status = bill.status or HFTax.Config.BILL_STATUS.UNPAID
    local statusLabel = "UNPAID"
    local r, g, b, a = 0.55, 0.15, 0.15, 0.9

    if status == HFTax.Config.BILL_STATUS.PAID then
        statusLabel = "PAID"
        r, g, b, a = 0.1, 0.55, 0.25, 0.8
    elseif status == HFTax.Config.BILL_STATUS.CANCELLED or bill.isWaived then
        statusLabel = "WAIVED"
        r, g, b, a = 0.65, 0.45, 0.15, 0.8
    elseif bill.isCutoffStage then
        statusLabel = "CUT-OFF"
        r, g, b, a = 0.75, 0.1, 0.1, 0.95
    elseif bill.isOverdue then
        statusLabel = "OVERDUE"
        r, g, b, a = 0.65, 0.15, 0.15, 0.9
    end

    self:drawRect(btnStatusX, btnStatusY, btnStatusW, btnStatusH, a, r, g, b)
    self:drawRectBorder(btnStatusX, btnStatusY, btnStatusW, btnStatusH, 1.0, 0.85, 0.85, 0.85)
    self:drawTextCentre(statusLabel, btnStatusX + (btnStatusW / 2), btnStatusY + 6, 1, 1, 1, 1, UIFont.Small)

    return y + itemH
end

function HFTaxUI.AdminLedgerUI:onMouseDownBillHistory(item)
    if not item then return end

    local mouseX = self.billHistoryBox:getMouseX()
    local listW = self.billHistoryBox:getWidth()
    local btnStatusW = 110
    local btnStatusX = listW - btnStatusW - 14

    if mouseX >= btnStatusX and mouseX <= (btnStatusX + btnStatusW) then
        if item.status == HFTax.Config.BILL_STATUS.UNPAID then
            local isLand = (item.billType == HFTax.Config.BILL_TYPE.LAND)
            local idPrefix = isLand and (item.shid or "000000") or (item.puuid or "P00000")
            local invoiceCode = "#" .. tostring(idPrefix) .. "-" .. tostring(item.billNumber or "001")

            local sw = getCore():getScreenWidth()
            local sh = getCore():getScreenHeight()
            local modalW, modalH = 460, 180
            local modalX = (sw - modalW) / 2
            local modalY = (sh - modalH) / 2

            local confirmText = "Confirm Admin Payment for Invoice " .. invoiceCode .. "?\n\nTotal Amount: $" .. tostring(item.totalAmount or 0) .. "\n\nNote: Admin payments will NOT add cash into the Treasury Vault."

            local modal = ISModalDialog:new(modalX, modalY, modalW, modalH, confirmText, true, self, self.onConfirmAdminPay, self.playerNum, item)
            modal:initialise()
            modal:addToUIManager()
            modal:bringToTop()
            return
        end
    end

    self.selectedBill = item
end

function HFTaxUI.AdminLedgerUI:onConfirmAdminPay(button, bill)
    if button and button.internal == "YES" and bill then
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "AdminMarkBillPaid", {
            billId = bill.billId
        })
    end
end

function HFTaxUI.AdminLedgerUI:onOpenSelectedInvoice()
    local selected = self.selectedBill or (self.billHistoryBox.items[self.billHistoryBox.selected] and self.billHistoryBox.items[self.billHistoryBox.selected].item)
    if not selected then return end

    local targetSh = nil
    if selected.billType == HFTax.Config.BILL_TYPE.LAND and selected.safehouseKey then
        local safehouses = SafeHouse.getSafehouseList()
        if safehouses then
            for i = 0, safehouses:size() - 1 do
                local sh = safehouses:get(i)
                if HFTax.Utils.getSafehouseKey(sh) == selected.safehouseKey then
                    targetSh = sh
                    break
                end
            end
        end
    end

    if HFTaxUI and HFTaxUI.InvoiceUI then
        HFTaxUI.InvoiceUI.openWindow(self.player, selected, targetSh)
    end
end

function HFTaxUI.AdminLedgerUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    HFTaxUI.AdminLedgerUI.instance = nil
end

function HFTaxUI.AdminLedgerUI.openWindow(player)
    local targetPlayer = player
    if not targetPlayer or type(targetPlayer) == "number" then
        targetPlayer = (type(player) == "number" and getSpecificPlayer(player)) or getPlayer()
    end

    if not isPlayerAdmin(targetPlayer) then return end

    if HFTaxUI.AdminLedgerUI.instance then
        HFTaxUI.AdminLedgerUI.instance:close()
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 1150, 730
    local x, y = math.max(20, (sw - w) / 2 - 40), math.max(20, (sh - h) / 2 - 30)

    local ui = HFTaxUI.AdminLedgerUI:new(x, y, w, h, targetPlayer)
    ui:initialise()
    ui:addToUIManager()
    ui:bringToTop()
    HFTaxUI.AdminLedgerUI.instance = ui
end