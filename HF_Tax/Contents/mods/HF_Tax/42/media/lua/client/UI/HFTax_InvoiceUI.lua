-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"

HFTaxUI = HFTaxUI or {}
HFTaxUI.InvoiceUI = ISCollapsableWindow:derive("HFTax_InvoiceUI")
HFTaxUI.InvoiceUI.instance = nil

-- [Matasa Protected Core Watermark - Detailed Invoice Viewer 2-Stage Master v23]
local _matasa_sec_id = "MATASA_HFTAX_2026_INV_DETAIL_V23_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

function HFTaxUI.InvoiceUI:new(x, y, width, height, player, bill, safehouse)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player or getPlayer()
    o.playerNum = o.player and o.player:getPlayerNum() or 0
    o.bill = bill
    o.safehouse = safehouse
    
    local prefixId = (bill.billType == HFTax.Config.BILL_TYPE.LAND) and (bill.shid or "000000") or (bill.puuid or "P00000")
    o.title = string.format("HF_Tax :: Official Tax Invoice [#%s-%s]", prefixId, tostring(bill.billNumber or "001"))
    o:setResizable(false)
    o.backgroundColor = {r = 0.08, g = 0.08, b = 0.08, a = 0.98}
    o.borderColor = {r = 0.4, g = 0.4, b = 0.4, a = 1.0}
    return o
end

function HFTaxUI.InvoiceUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local pad = 16
    local curY = 36
    local contentW = self.width - (pad * 2)

    local bill = self.bill or {}
    local isLandTax = (bill.billType == HFTax.Config.BILL_TYPE.LAND)
    local bd = bill.breakdown or {}
    local isUnpaid = (bill.status == HFTax.Config.BILL_STATUS.UNPAID)

    local timingText, isOverdue, isCutoff = HFTax.Utils.getBillTimingStatus(bill)

    -- Header Title
    local titleText = isLandTax and string.format("Safehouse: %s (ID: #%s)", tostring(bill.safehouseTitle or "Safehouse"), tostring(bill.shid or "000000")) 
                                or string.format("Personal Tax Target: %s (ID: #%s)", tostring(bill.owner or "N/A"), tostring(bill.puuid or "P00000"))
    self.headerLbl = ISLabel:new(pad, curY, 20, titleText, 1, 0.85, 0.2, 1, UIFont.Medium, true)
    self.headerLbl:initialise()
    self:addChild(self.headerLbl)
    curY = curY + 22

    -- Responsible Payer
    local ownerText = string.format("Responsible Payer: %s (ID: #%s)", tostring(bill.owner or "N/A"), tostring(bill.ownerPUUID or "P00000"))
    self.ownerLbl = ISLabel:new(pad, curY, 18, ownerText, 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    self.ownerLbl:initialise()
    self:addChild(self.ownerLbl)
    curY = curY + 18

    -- Due / Cutoff Status
    local dr, dg, db = 0.9, 0.6, 0.2
    if isUnpaid then
        if isOverdue then
            dr, dg, db = 0.95, 0.25, 0.25
        end
    else
        dr, dg, db = 0.2, 0.85, 0.3
    end

    self.timeLbl = ISLabel:new(pad, curY, 18, "Status: " .. timingText, dr, dg, db, 1, UIFont.Small, true)
    self.timeLbl:initialise()
    self:addChild(self.timeLbl)

    if isLandTax then
        local utilityText = isCutoff and "Utilities: [ CUT-OFF ]" or "Utilities: [ ACTIVE ]"
        local ur, ug, ub = isCutoff and 0.95 or 0.2, isCutoff and 0.2 or 0.85, 0.2
        self.utilityLbl = ISLabel:new(self.width - pad - 160, curY, 18, utilityText, ur, ug, ub, 1, UIFont.Small, true)
        self.utilityLbl:initialise()
        self:addChild(self.utilityLbl)
    end
    curY = curY + 22

    -- Breakdown Sections (Clean String Concatenation)
    if isLandTax then
        local dim = bd.dimensions or { w = 0, h = 0, totalTiles = 0 }
        local landDetail = "• Land & Property Tax: " .. tostring(dim.w) .. "x" .. tostring(dim.h) .. " (" .. tostring(dim.totalTiles) .. " tiles @ $" .. tostring(bd.landRate or 0.5) .. "/tile) = $" .. tostring(bill.landTax or 0)
        self.landRow = ISLabel:new(pad + 8, curY, 18, landDetail, 0.9, 0.9, 0.9, 1, UIFont.Small, true)
        self.landRow:initialise()
        self:addChild(self.landRow)
        curY = curY + 18

        local memDetail = "• Extra Member Tax: " .. tostring(bd.memberCount or 1) .. " members (" .. tostring(bd.memberQuota or 4) .. " quota, " .. tostring(bd.extraMembers or 0) .. " extra @ $" .. tostring(bd.memberRate or 100) .. "/extra) = $" .. tostring(bill.memberTax or 0)
        self.memberRow = ISLabel:new(pad + 8, curY, 18, memDetail, 0.9, 0.9, 0.9, 1, UIFont.Small, true)
        self.memberRow:initialise()
        self:addChild(self.memberRow)
        curY = curY + 18

        local memberListStr = (bd.memberList and table.concat(bd.memberList, ", ")) or "N/A"
        self.snapshotRow = ISLabel:new(pad + 18, curY, 18, "Snapshot Members: " .. memberListStr, 0.65, 0.75, 0.85, 1, UIFont.Small, true)
        self.snapshotRow:initialise()
        self:addChild(self.snapshotRow)
        curY = curY + 20
    else
        local personalDetail = "• Personal Base Tax Rate: $" .. tostring(bill.basePayable or bill.totalAmount or 0)
        self.personalRow = ISLabel:new(pad + 8, curY, 18, personalDetail, 0.9, 0.9, 0.9, 1, UIFont.Small, true)
        self.personalRow:initialise()
        self:addChild(self.personalRow)
        curY = curY + 20
    end

    -- Penalty Row (Clean String Concatenation - No string.format crash)
    if (bill.penalty or 0) > 0 then
        local penText = "• Overdue Penalty (+2% per Day x " .. tostring(bill.overdueDays or 0) .. " Days): +$" .. tostring(bill.penalty)
        self.penaltyRow = ISLabel:new(pad + 8, curY, 18, penText, 0.95, 0.3, 0.3, 1, UIFont.Small, true)
        self.penaltyRow:initialise()
        self:addChild(self.penaltyRow)
        curY = curY + 18
    end

    if bill.note and bill.note ~= "" then
        self.noteLbl = ISLabel:new(pad, curY + 2, 18, "Note: " .. tostring(bill.note), 0.7, 0.7, 0.7, 1, UIFont.Small, true)
        self.noteLbl:initialise()
        self:addChild(self.noteLbl)
        curY = curY + 22
    end

    curY = curY + 6
    local totalText = "Net Payable Amount: $" .. tostring(bill.totalAmount or 0)
    self.totalLbl = ISLabel:new(pad, curY, 26, totalText, 0.2, 0.95, 0.3, 1, UIFont.Large, true)
    self.totalLbl:initialise()
    self:addChild(self.totalLbl)
    curY = curY + 38

    -- Pay Action Buttons
    local btnW = (contentW - pad) / 2
    local isOwner = (self.player:getUsername() == bill.owner)

    local inv = self.player:getInventory()
    local moneyItems = inv and inv:getItemsFromType("Base.Money", true)
    local availableCash = moneyItems and moneyItems:size() or 0
    local hasEnoughCash = availableCash >= (bill.totalAmount or 0)

    self.payBtn = ISButton:new(pad, curY, btnW, 32, "Pay Bill ($" .. tostring(bill.totalAmount or 0) .. ")", self, self.onPayInvoice)
    self.payBtn:initialise()
    self.payBtn:instantiate()
    
    if isUnpaid and (not isLandTax or isOwner) and hasEnoughCash then
        self.payBtn.backgroundColor = {r = 0.1, g = 0.55, b = 0.2, a = 0.9}
        self.payBtn.enable = true
    else
        self.payBtn.backgroundColor = {r = 0.3, g = 0.3, b = 0.3, a = 0.5}
        self.payBtn.enable = false
        if isLandTax and not isOwner then
            self.payBtn.tooltip = "โปรดแจ้งเจ้าของบ้านเพื่อชำระ"
        elseif not isUnpaid then
            self.payBtn.tooltip = "This bill has already been settled."
        elseif not hasEnoughCash then
            self.payBtn.tooltip = string.format("Insufficient funds! You have $%d in cash.", availableCash)
        end
    end
    self:addChild(self.payBtn)

    self.closeBtn = ISButton:new(pad + btnW + pad, curY, btnW, 32, "Close", self, self.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.backgroundColor = {r = 0.35, g = 0.35, b = 0.35, a = 0.8}
    self:addChild(self.closeBtn)
end

function HFTaxUI.InvoiceUI:prerender()
    self:drawRect(0, 0, self.width, self.height, 0.98, 0.08, 0.08, 0.08)
    self:drawRectBorder(0, 0, self.width, self.height, 1.0, 0.35, 0.35, 0.35)
    ISCollapsableWindow.prerender(self)
    self:drawRect(12, 30, self.width - 24, self.height - 85, 0.35, 0.04, 0.04, 0.04)
    self:drawRectBorder(12, 30, self.width - 24, self.height - 85, 0.6, 0.25, 0.25, 0.25)
end

function HFTaxUI.InvoiceUI:onPayInvoice()
    if not self.bill or self.bill.status ~= HFTax.Config.BILL_STATUS.UNPAID then return end
    local currentUsername = self.player:getUsername()

    if self.bill.billType == HFTax.Config.BILL_TYPE.LAND and self.bill.owner ~= currentUsername then
        if HaloTextHelper then
            HaloTextHelper.addTextWithArrow(self.player, "โปรดแจ้งเจ้าของบ้านเพื่อชำระ", false, 255, 75, 75)
        end
        return
    end

    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    for _, otherBill in pairs(globalData.Bills or {}) do
        if otherBill.billId ~= self.bill.billId and otherBill.status == HFTax.Config.BILL_STATUS.UNPAID and otherBill.isOverdue then
            local isRelated = false
            if self.bill.billType == HFTax.Config.BILL_TYPE.LAND and otherBill.safehouseKey == self.bill.safehouseKey then
                isRelated = true
            elseif self.bill.billType == HFTax.Config.BILL_TYPE.PERSONAL and otherBill.owner == currentUsername then
                isRelated = true
            end

            if isRelated and (otherBill.createdEpoch or 0) < (self.bill.createdEpoch or 0) then
                if HaloTextHelper then
                    HaloTextHelper.addTextWithArrow(self.player, "โปรดชำระบิลที่ค้างชำระก่อน", false, 255, 75, 75)
                end
                return
            end
        end
    end

    sendClientCommand(self.player, HFTax.Config.MOD_ID, "PayBill", {
        billId = self.bill.billId,
        safehouseKey = self.bill.safehouseKey,
        totalAmount = self.bill.totalAmount
    })
    
    self:onClose()
end

function HFTaxUI.InvoiceUI:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    HFTaxUI.InvoiceUI.instance = nil
end

function HFTaxUI.InvoiceUI.openWindow(player, bill, safehouse)
    local targetPlayer = player or getPlayer()
    if not targetPlayer or not bill then return end

    if HFTaxUI.InvoiceUI.instance then
        HFTaxUI.InvoiceUI.instance:onClose()
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 580, 440
    local x, y = (sw - w) / 2, (sh - h) / 2

    local ui = HFTaxUI.InvoiceUI:new(x, y, w, h, targetPlayer, bill, safehouse)
    ui:initialise()
    ui:addToUIManager()
    ui:bringToTop()
    HFTaxUI.InvoiceUI.instance = ui
end