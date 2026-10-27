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
HFTaxUI.InvoiceManager = ISCollapsableWindow:derive("HFTax_InvoiceManager")
HFTaxUI.InvoiceManager.instance = nil

-- [Matasa Protected Core Watermark - Invoice Manager Bank Sync v52]
local _matasa_sec_id = "MATASA_HFTAX_2026_INVOICE_MGR_BANKSYNC_V52_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

---Strictly count cash in main inventory only
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

function HFTaxUI.InvoiceManager:new(x, y, width, height, player, safehouse)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player or getPlayer()
    o.playerNum = o.player and o.player:getPlayerNum() or 0
    o.safehouse = safehouse
    o.isSafehouseMode = (safehouse ~= nil)
    o.selectedBill = nil
    o.title = "HF_Tax :: Tax Billing Center"
    o:setResizable(false)
    o.backgroundColor = {r = 0.08, g = 0.08, b = 0.08, a = 0.98}
    o.borderColor = {r = 0.35, g = 0.35, b = 0.35, a = 1.0}
    return o
end

function HFTaxUI.InvoiceManager:createChildren()
    ISCollapsableWindow.createChildren(self)

    local pad = 12
    local topOffset = 34
    local contentW = self.width - (pad * 2)
    local bottomActionH = 34

    -- Header Info Panel
    self.headerPanel = ISPanel:new(pad, topOffset, contentW, 58)
    self.headerPanel:initialise()
    self.headerPanel:instantiate()
    self.headerPanel.render = self.renderHeaderPanel
    self.headerPanel.target = self
    self:addChild(self.headerPanel)

    -- Invoices List
    local listY = topOffset + 64
    local listH = self.height - listY - bottomActionH - pad - 6

    self.billListBox = ISScrollingListBox:new(pad, listY, contentW, listH)
    self.billListBox:initialise()
    self.billListBox:instantiate()
    self.billListBox.itemheight = 68
    self.billListBox.selected = 0
    self.billListBox.joypadParent = self
    self.billListBox.doDrawItem = self.drawBillItem
    self.billListBox.onmousedown = self.onMouseDownBillItem
    self.billListBox.target = self
    self:addChild(self.billListBox)

    -- Bottom Actions
    local btnW = (contentW - pad) / 2
    local btnY = self.height - bottomActionH - pad

    self.payAllBtn = ISButton:new(pad, btnY, btnW, bottomActionH, "Pay All Outstanding Bills ($0)", self, self.onPayAllOutstanding)
    self.payAllBtn:initialise()
    self.payAllBtn:instantiate()
    self.payAllBtn.backgroundColor = {r = 0.1, g = 0.55, b = 0.25, a = 0.95}
    self:addChild(self.payAllBtn)

    self.closeBtn = ISButton:new(pad + btnW + pad, btnY, btnW, bottomActionH, "Close", self, self.close)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.backgroundColor = {r = 0.35, g = 0.35, b = 0.35, a = 0.85}
    self:addChild(self.closeBtn)

    self:populateBills()
end

function HFTaxUI.InvoiceManager:renderHeaderPanel()
    local parent = self.target
    local w, h = self:getWidth(), self:getHeight()

    self:drawRect(0, 0, w, h, 0.4, 0.05, 0.05, 0.05)
    self:drawRectBorder(0, 0, w, h, 0.6, 0.25, 0.25, 0.25)

    local username = parent.player:getUsername()
    local myPUUID = HFTax.Utils.getPlayerPUUID(username)

    -- Title text
    local titleText = parent.isSafehouseMode and ("Safehouse Tax Center: " .. tostring(parent.safehouse:getTitle()) .. " (ID: #" .. tostring(HFTax.Utils.getSafehouseSHID(parent.safehouse)) .. ")")
                                             or ("Personal Tax Center: " .. username .. " (ID: #" .. tostring(myPUUID) .. ")")
    self:drawText(titleText, 10, 8, 1, 1, 1, 1, UIFont.Medium)

    local unpaidCount = 0
    local totalDue = 0
    if parent.billListBox and parent.billListBox.items then
        for _, itm in ipairs(parent.billListBox.items) do
            local b = itm.item
            if b and b.status == HFTax.Config.BILL_STATUS.UNPAID then
                unpaidCount = unpaidCount + 1
                totalDue = totalDue + (b.totalAmount or 0)
            end
        end
    end

    local subText = "Unpaid Invoices: " .. tostring(unpaidCount) .. " Bills"
    self:drawText(subText, 10, 32, 0.7, 0.7, 0.7, 1, UIFont.Small)

    local dueText = "Total Outstanding: $" .. tostring(totalDue)
    self:drawText(dueText, 160, 32, 0.95, 0.3, 0.3, 1, UIFont.Medium)

    -- =========================================================================
    -- Top Right Balances: Cash on Person vs Bank (Akacount)
    -- =========================================================================
    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local pSettings = globalData.PaymentSettings or { allowCash = true, allowBank = true }

    local cashInHand = getCashOnPerson(parent.player)
    local bankBal = (HFTax.ClientData and HFTax.ClientData.BankBalance) or 0

    local badgeW, badgeH = 145, 24
    local badgeY = 6
    local badge2X = w - badgeW - 10
    local badge1X = badge2X - badgeW - 8

    -- Badge 1: Cash in Hand (Main Inventory Only)
    local cashStr = pSettings.allowCash and string.format("Cash in Hand: $%d", cashInHand) or "Cash: [DISABLED]"
    local cr, cg, cb = pSettings.allowCash and 0.2 or 0.5, pSettings.allowCash and 0.85 or 0.5, pSettings.allowCash and 0.3 or 0.5
    self:drawRect(badge1X, badgeY, badgeW, badgeH, 0.75, 0.1, 0.18, 0.12)
    self:drawRectBorder(badge1X, badgeY, badgeW, badgeH, 1.0, 0.25, 0.55, 0.3)
    self:drawTextCentre(cashStr, badge1X + (badgeW / 2), badgeY + 4, cr, cg, cb, 1, UIFont.Small)

    -- Badge 2: Bank Account (Akacount ATM Server Synced)
    local bankStr = pSettings.allowBank and string.format("Bank Account: $%d", bankBal) or "Bank: [DISABLED]"
    local br, bg, bb = pSettings.allowBank and 0.25 or 0.5, pSettings.allowBank and 0.75 or 0.5, pSettings.allowBank and 0.95 or 0.5
    self:drawRect(badge2X, badgeY, badgeW, badgeH, 0.75, 0.1, 0.15, 0.22)
    self:drawRectBorder(badge2X, badgeY, badgeW, badgeH, 1.0, 0.25, 0.45, 0.65)
    self:drawTextCentre(bankStr, badge2X + (badgeW / 2), badgeY + 4, br, bg, bb, 1, UIFont.Small)
end

function HFTaxUI.InvoiceManager:populateBills()
    self.billListBox:clear()
    self.billListBox.selected = 0

    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local bills = globalData.Bills or {}
    local username = self.player:getUsername()
    local myPUUID = HFTax.Utils.getPlayerPUUID(username)
    local matchingBills = {}
    local totalOutstanding = 0

    if self.isSafehouseMode and self.safehouse then
        local shKey = HFTax.Utils.getSafehouseKey(self.safehouse)
        for _, b in pairs(bills) do
            if b.safehouseKey == shKey then
                table.insert(matchingBills, b)
                if b.status == HFTax.Config.BILL_STATUS.UNPAID then
                    totalOutstanding = totalOutstanding + (b.totalAmount or 0)
                end
            end
        end
    else
        for _, b in pairs(bills) do
            if (b.visibilityPUUIDs and b.visibilityPUUIDs[myPUUID]) or (b.owner == username) or (b.ownerPUUID == myPUUID) then
                table.insert(matchingBills, b)
                if b.status == HFTax.Config.BILL_STATUS.UNPAID then
                    totalOutstanding = totalOutstanding + (b.totalAmount or 0)
                end
            end
        end
    end

    table.sort(matchingBills, function(a, b)
        return (a.createdEpoch or 0) > (b.createdEpoch or 0)
    end)

    for _, b in ipairs(matchingBills) do
        self.billListBox:addItem(b.billId, b)
    end

    self.payAllBtn:setTitle("Pay All Outstanding Bills ($" .. tostring(totalOutstanding) .. ")")
end

function HFTaxUI.InvoiceManager:drawBillItem(y, item, alt)
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
    local suffixTitle = isLand and (" (" .. tostring(bill.safehouseTitle or "Safehouse") .. ")") or ""
    local billTitle = "Invoice #" .. tostring(idPrefix) .. "-" .. tostring(bill.billNumber or "001") .. suffixTitle

    local btnViewW, btnViewH = 96, 28
    local btnPayW, btnPayH = 96, 28
    local btnViewX = listW - btnViewW - btnPayW - 24
    local btnPayX = listW - btnPayW - 14
    local btnY = y + 20

    -- Line 1: Type Tag, Overdue Tag, Title, Amount
    local curX = 12
    local tagW = isLand and 80 or 80
    self:drawRect(curX, y + 8, tagW, 20, 0.85, 0.2, 0.2, 0.2)
    self:drawRectBorder(curX, y + 8, tagW, 20, 1.0, 0.85, 0.65, 0.2)
    self:drawTextCentre(isLand and "[LAND TAX]" or "[PERSONAL]", curX + (tagW / 2), y + 10, 1, 0.85, 0.2, 1, UIFont.Small)
    curX = curX + tagW + 8

    if bill.isCutoffStage then
        self:drawRect(curX, y + 8, 120, 20, 0.85, 0.65, 0.1, 0.1)
        self:drawRectBorder(curX, y + 8, 120, 20, 1.0, 0.95, 0.2, 0.2)
        self:drawTextCentre("[CUT-OFF ACTIVE]", curX + 60, y + 10, 1, 1, 1, 1, UIFont.Small)
        curX = curX + 128
    elseif bill.isOverdue then
        self:drawRect(curX, y + 8, 85, 20, 0.85, 0.65, 0.25, 0.1)
        self:drawRectBorder(curX, y + 8, 85, 20, 1.0, 0.95, 0.4, 0.2)
        self:drawTextCentre("[OVERDUE]", curX + 42, y + 10, 1, 1, 1, 1, UIFont.Small)
        curX = curX + 93
    end

    self:drawText(billTitle, curX, y + 8, 1, 1, 1, 1, UIFont.Medium)

    local textManager = getTextManager()
    local titleW = textManager and textManager:MeasureStringX(UIFont.Medium, billTitle) or 220
    local amountColor = (bill.status == HFTax.Config.BILL_STATUS.PAID) and {r = 0.2, g = 0.9, b = 0.3} or {r = 0.95, g = 0.3, b = 0.3}
    self:drawText("$" .. tostring(bill.totalAmount or 0), curX + titleW + 12, y + 8, amountColor.r, amountColor.g, amountColor.b, 1, UIFont.Medium)

    -- Line 2: Meta info
    local subText = ""
    local sr, sg, sb = 0.65, 0.65, 0.65
    if bill.status == HFTax.Config.BILL_STATUS.PAID then
        subText = "Settled: " .. tostring(bill.paidDateStr or "Completed") .. " | Paid by: " .. tostring(bill.paidBy or "N/A")
        sr, sg, sb = 0.3, 0.8, 0.4
    elseif bill.isCutoffStage then
        subText = "Status: CUT-OFF ACTIVE (Overdue " .. tostring(bill.overdueDays or 0) .. " Days) | Penalty (+2%/Day): +$" .. tostring(bill.penalty or 0) .. " | Payer: " .. tostring(bill.owner or "N/A")
        sr, sg, sb = 0.95, 0.3, 0.3
    elseif bill.isOverdue then
        subText = "Status: OVERDUE (" .. tostring(bill.overdueDays or 0) .. " Days) | Penalty (+2%/Day): +$" .. tostring(bill.penalty or 0) .. " | Payer: " .. tostring(bill.owner or "N/A")
        sr, sg, sb = 0.95, 0.6, 0.2
    else
        subText = "Issued: " .. tostring(bill.createdDateStr or "Recent") .. " | Payer: " .. tostring(bill.owner or "N/A") .. " | Note: " .. tostring(bill.note or "Normal")
    end
    self:drawText(subText, 12, y + 38, sr, sg, sb, 1, UIFont.Small)

    -- Action Buttons
    self:drawRect(btnViewX, btnY, btnViewW, btnViewH, 0.85, 0.15, 0.45, 0.75)
    self:drawRectBorder(btnViewX, btnY, btnViewW, btnViewH, 1.0, 0.35, 0.65, 0.95)
    self:drawTextCentre("View Bill", btnViewX + (btnViewW / 2), btnY + 6, 1, 1, 1, 1, UIFont.Small)

    if bill.status == HFTax.Config.BILL_STATUS.UNPAID then
        self:drawRect(btnPayX, btnY, btnPayW, btnPayH, 0.85, 0.65, 0.2, 0.2)
        self:drawRectBorder(btnPayX, btnY, btnPayW, btnPayH, 1.0, 0.85, 0.35, 0.35)
        self:drawTextCentre("Quick Pay", btnPayX + (btnPayW / 2), btnY + 6, 1, 1, 1, 1, UIFont.Small)
    else
        self:drawTextCentre("[ PAID ]", btnPayX + (btnPayW / 2), btnY + 6, 0.3, 0.95, 0.4, 1, UIFont.Medium)
    end

    return y + itemH
end

function HFTaxUI.InvoiceManager:onMouseDownBillItem(item)
    if not item then return end

    local mouseX = self.billListBox:getMouseX()
    local listW = self.billListBox:getWidth()
    local btnViewW, btnPayW = 96, 96
    local btnViewX = listW - btnViewW - btnPayW - 24
    local btnPayX = listW - btnPayW - 14

    if mouseX >= btnViewX and mouseX <= (btnViewX + btnViewW) then
        if HFTaxUI and HFTaxUI.InvoiceUI then
            HFTaxUI.InvoiceUI.openWindow(self.player, item, self.safehouse)
        end
        return
    end

    if mouseX >= btnPayX and mouseX <= (btnPayX + btnPayW) then
        if item.status == HFTax.Config.BILL_STATUS.UNPAID then
            self:promptPaymentMethod(item.billId, item.totalAmount or 0, false)
        end
        return
    end

    self.selectedBill = item
end

function HFTaxUI.InvoiceManager:promptPaymentMethod(targetBillId, amount, isPayAll)
    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    local pSettings = globalData.PaymentSettings or { allowCash = true, allowBank = true }

    local cashInHand = getCashOnPerson(self.player)
    local bankBal = (HFTax.ClientData and HFTax.ClientData.BankBalance) or 0

    if pSettings.allowCash and not pSettings.allowBank then
        self:executePayment(targetBillId, "CASH", isPayAll)
        return
    elseif pSettings.allowBank and not pSettings.allowCash then
        self:executePayment(targetBillId, "BANK", isPayAll)
        return
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local modalW, modalH = 460, 200
    local modalX = (sw - modalW) / 2
    local modalY = (sh - modalH) / 2

    local promptText = string.format("Select Payment Method for Total $%d:\n\n[1] Cash in Hand: $%d\n[2] Bank ATM (Akacount): $%d\n\nChoose 'YES' for Cash or 'NO' for Bank Account.", amount, cashInHand, bankBal)

    local modal = ISModalDialog:new(modalX, modalY, modalW, modalH, promptText, true, self, function(target, button)
        if button.internal == "YES" then
            target:executePayment(targetBillId, "CASH", isPayAll)
        elseif button.internal == "NO" then
            target:executePayment(targetBillId, "BANK", isPayAll)
        end
    end, self.playerNum)

    modal:initialise()
    modal.yes:setTitle("Pay with Cash")
    modal.no:setTitle("Pay with Bank")
    modal:addToUIManager()
    modal:bringToTop()
end

function HFTaxUI.InvoiceManager:executePayment(targetBillId, method, isPayAll)
    if isPayAll then
        local unpaidIds = {}
        for _, itm in ipairs(self.billListBox.items) do
            local b = itm.item
            if b and b.status == HFTax.Config.BILL_STATUS.UNPAID then
                table.insert(unpaidIds, b.billId)
            end
        end

        if #unpaidIds > 0 then
            sendClientCommand(self.player, HFTax.Config.MOD_ID, "PayAllBills", {
                billIds = unpaidIds,
                payMethod = method
            })
        end
    else
        sendClientCommand(self.player, HFTax.Config.MOD_ID, "PayBill", {
            billId = targetBillId,
            payMethod = method
        })
    end
end

function HFTaxUI.InvoiceManager:onPayAllOutstanding()
    local totalOutstanding = 0
    local unpaidIds = {}

    for _, itm in ipairs(self.billListBox.items) do
        local b = itm.item
        if b and b.status == HFTax.Config.BILL_STATUS.UNPAID then
            table.insert(unpaidIds, b.billId)
            totalOutstanding = totalOutstanding + (b.totalAmount or 0)
        end
    end

    if #unpaidIds > 0 and totalOutstanding > 0 then
        self:promptPaymentMethod(nil, totalOutstanding, true)
    end
end

function HFTaxUI.InvoiceManager:close()
    self:setVisible(false)
    self:removeFromUIManager()
    HFTaxUI.InvoiceManager.instance = nil
end

function HFTaxUI.InvoiceManager.openWindow(player, safehouse)
    -- Catch the caller, not the call site.
    --
    -- Other mods open the tax screen by calling THIS function directly rather
    -- than going through HFTaxAPI, so pointing the API at the new window was
    -- not enough -- the old screen kept opening and nothing in the log said
    -- why. Redirecting here covers every caller that already exists, without
    -- any of them having to change a line.
    if HFTaxUI.BillingWindow and HFTaxUI.BillingWindow.openWindow then
        return HFTaxUI.BillingWindow.openWindow(player, safehouse)
    end
    print("[HF_Tax] !! Billing Center missing - opening the pre-revision Invoice Manager.")

    local targetPlayer = player or getPlayer()
    if not targetPlayer then return end

    -- Request fresh data & ATM balance upon opening
    sendClientCommand(targetPlayer, HFTax.Config.MOD_ID, "RequestPlayerBills", {
        myPUUID = HFTax.Utils.getPlayerPUUID(targetPlayer:getUsername()),
        username = targetPlayer:getUsername()
    })

    if HFTaxUI.InvoiceManager.instance then
        HFTaxUI.InvoiceManager.instance:close()
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 920, 600
    local x, y = (sw - w) / 2, (sh - h) / 2

    local ui = HFTaxUI.InvoiceManager:new(x, y, w, h, targetPlayer, safehouse)
    ui:initialise()
    ui:addToUIManager()
    ui:bringToTop()
    HFTaxUI.InvoiceManager.instance = ui
end