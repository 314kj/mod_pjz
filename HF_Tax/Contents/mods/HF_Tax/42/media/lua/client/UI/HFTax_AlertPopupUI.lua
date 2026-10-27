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
require "ISUI/ISPanel"

HFTaxUI = HFTaxUI or {}
HFTaxUI.AlertPopupUI = ISCollapsableWindow:derive("HFTax_AlertPopupUI")
HFTaxUI.AlertPopupUI.instance = nil

-- [Matasa Protected Core Watermark - Overdue Alert Popup UI v43]
local _matasa_sec_id = "MATASA_HFTAX_2026_ALERT_POPUP_V43_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

function HFTaxUI.AlertPopupUI:new(x, y, width, height, player, safehouse, statusData)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player or getPlayer()
    o.safehouse = safehouse
    o.status = statusData or {}
    o.title = "HF_Tax :: URGENT TAX NOTICE"
    o:setResizable(false)
    o.backgroundColor = {r = 0.1, g = 0.04, b = 0.04, a = 0.98}
    o.borderColor = {r = 0.85, g = 0.2, b = 0.2, a = 1.0}
    return o
end

function HFTaxUI.AlertPopupUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local pad = 16
    local curY = 38
    local contentW = self.width - (pad * 2)

    local isCutoff = (self.status.isCutoff == true)
    local bannerText = isCutoff and "CRITICAL WARNING: UTILITIES CUT-OFF ACTIVE!" or "WARNING: OVERDUE TAX BILL DETECTED!"
    local br, bg, bb = isCutoff and 1.0 or 1.0, isCutoff and 0.2 or 0.5, 0.2
    
    self.bannerLbl = ISLabel:new(pad, curY, 22, bannerText, br, bg, bb, 1, UIFont.Medium, true)
    self.bannerLbl:initialise()
    self:addChild(self.bannerLbl)
    curY = curY + 26

    local shTitle = self.safehouse and self.safehouse:getTitle() or "Safehouse"
    local shid = self.status.shid or (self.safehouse and HFTax.Utils.getSafehouseSHID(self.safehouse)) or "000000"
    local infoText = "Safehouse: " .. shTitle .. " (ID: #" .. tostring(shid) .. ")"
    self.infoLbl = ISLabel:new(pad, curY, 18, infoText, 0.9, 0.9, 0.9, 1, UIFont.Small, true)
    self.infoLbl:initialise()
    self:addChild(self.infoLbl)
    curY = curY + 20

    local billNum = self.status.primaryBillNumber or "001"
    local billCount = self.status.unpaidCount or 1
    local billIdText = "Primary Overdue Invoice: #" .. tostring(shid) .. "-" .. tostring(billNum)
    if billCount > 1 then
        billIdText = billIdText .. " (+" .. tostring(billCount - 1) .. " more pending bills)"
    end
    self.billIdLbl = ISLabel:new(pad, curY, 18, billIdText, 1.0, 0.85, 0.2, 1, UIFont.Small, true)
    self.billIdLbl:initialise()
    self:addChild(self.billIdLbl)
    curY = curY + 20

    local totalAmt = self.status.totalOutstanding or 0
    local amountText = "Total Outstanding Balance: $" .. tostring(totalAmt)
    self.amountLbl = ISLabel:new(pad, curY, 22, amountText, 0.95, 0.3, 0.3, 1, UIFont.Medium, true)
    self.amountLbl:initialise()
    self:addChild(self.amountLbl)
    curY = curY + 26

    local timingText = ""
    if isCutoff then
        timingText = "Enforcement: Water and Power are currently SUSPENDED."
    else
        local daysLeft = self.status.daysRemainingToCutoff or 0
        timingText = "Stage 2 Enforcement: " .. tostring(daysLeft) .. " Days remaining before utility cut-off."
    end

    self.timingLbl = ISLabel:new(pad, curY, 18, timingText, 0.95, 0.7, 0.2, 1, UIFont.Small, true)
    self.timingLbl:initialise()
    self:addChild(self.timingLbl)
    curY = curY + 36

    local btnH = 34
    local btnW = (contentW - pad) / 2

    self.openManagerBtn = ISButton:new(pad, curY, btnW, btnH, "Pay Now", self, self.onOpenBillingCenter)
    self.openManagerBtn:initialise()
    self.openManagerBtn:instantiate()
    self.openManagerBtn.backgroundColor = {r = 0.1, g = 0.55, b = 0.25, a = 0.95}
    self:addChild(self.openManagerBtn)

    self.dismissBtn = ISButton:new(pad + btnW + pad, curY, btnW, btnH, "Acknowledge", self, self.onClose)
    self.dismissBtn:initialise()
    self.dismissBtn:instantiate()
    self.dismissBtn.backgroundColor = {r = 0.35, g = 0.35, b = 0.35, a = 0.85}
    self:addChild(self.dismissBtn)
end

function HFTaxUI.AlertPopupUI:prerender()
    self:drawRect(0, 0, self.width, self.height, 0.98, 0.1, 0.04, 0.04)
    self:drawRectBorder(0, 0, self.width, self.height, 1.0, 0.85, 0.2, 0.2)
    ISCollapsableWindow.prerender(self)
    self:drawRect(12, 30, self.width - 24, self.height - 84, 0.35, 0.02, 0.02, 0.02)
    self:drawRectBorder(12, 30, self.width - 24, self.height - 84, 0.6, 0.45, 0.15, 0.15)
end

function HFTaxUI.AlertPopupUI:onOpenBillingCenter()
    if HFTaxUI and HFTaxUI.BillingWindow then
        HFTaxUI.BillingWindow.openWindow(self.player, self.safehouse)
    end
    self:onClose()
end

function HFTaxUI.AlertPopupUI:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    HFTaxUI.AlertPopupUI.instance = nil
end

function HFTaxUI.AlertPopupUI.openWindow(player, safehouse, statusData)
    local targetPlayer = player or getPlayer()
    if not targetPlayer then return end

    if HFTaxUI.AlertPopupUI.instance then
        HFTaxUI.AlertPopupUI.instance:onClose()
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 540, 240
    local x, y = (sw - w) / 2, (sh - h) / 2

    local ui = HFTaxUI.AlertPopupUI:new(x, y, w, h, targetPlayer, safehouse, statusData)
    ui:initialise()
    ui:addToUIManager()
    ui:bringToTop()
    HFTaxUI.AlertPopupUI.instance = ui
end