-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISLabel"

HFTaxUI = HFTaxUI or {}
HFTaxUI.AdminBillEditor = ISCollapsableWindow:derive("HFTax_AdminBillEditor")
HFTaxUI.AdminBillEditor.instance = nil

-- [Matasa Protected Core Watermark - Admin Bill Editor Engine v9]
local _matasa_sec_id = "MATASA_HFTAX_2026_BILL_EDIT_V9_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

local function isPlayerAdmin(player)
    if not player then return false end
    if not isClient() and not isServer() then return true end
    if isCoopHost() or (getCore() and getCore():getDebug()) then return true end
    local ok, lvl = pcall(function() return player:getAccessLevel() end)
    return ok and lvl and (lvl:lower() == "admin" or lvl:lower() == "moderator" or lvl:lower() == "gm" or lvl:lower() == "overseer")
end

function HFTaxUI.AdminBillEditor:new(x, y, width, height, player, safehouse, previewBill, targetUsername)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.playerNum = player:getPlayerNum()
    o.safehouse = safehouse
    o.targetUsername = targetUsername
    o.isPersonal = (targetUsername ~= nil)
    o.previewBill = previewBill or {}
    
    local targetType = o.isPersonal and "Personal Bill" or "Land Bill"
    local prefixId = o.isPersonal and (o.previewBill.puuid or "P00000") or (o.previewBill.shid or "000000")
    local bNum = o.previewBill.billNumber or "001"
    o.title = string.format("HF_Tax :: Edit %s Preset [#%s-%s]", targetType, prefixId, bNum)
    o:setResizable(false)
    return o
end

function HFTaxUI.AdminBillEditor:createChildren()
    ISCollapsableWindow.createChildren(self)

    local pad = 15
    local curY = 35
    local contentW = self.width - (pad * 2)
    local entryW = 160
    local labelW = contentW - entryW

    local infoText = ""
    if self.isPersonal then
        local puuid = HFTax.Utils.getPlayerPUUID(self.targetUsername)
        infoText = string.format("Personal Tax Target: %s | ID: #%s", self.targetUsername or "Unknown", puuid)
    else
        local titleText = self.safehouse and self.safehouse:getTitle() or "Unknown Safehouse"
        local ownerText = self.safehouse and self.safehouse:getOwner() or "No Owner"
        local shid = HFTax.Utils.getSafehouseSHID(self.safehouse)
        infoText = string.format("Safehouse: %s | Owner: %s | ID: #%s", titleText, ownerText, shid)
    end
    
    self.infoLabel = ISLabel:new(pad, curY, 20, infoText, 1, 0.85, 0.2, 1, UIFont.Medium, true)
    self.infoLabel:initialise()
    self:addChild(self.infoLabel)
    curY = curY + 28

    local curBase = self.previewBill.landTax or self.previewBill.baseTax or 0
    local curMember = self.previewBill.memberTax or 0
    local curPenalty = self.previewBill.penalty or 0
    local curNote = self.previewBill.note or (self.isPersonal and "Personal Central Cycle Tax" or "Safehouse & Land Cycle Tax")

    local baseLabelText = self.isPersonal and "Personal Base Tax ($):" or "Land Tax Area Amount ($):"
    self.baseTaxLbl = ISLabel:new(pad, curY + 4, 20, baseLabelText, 1, 1, 1, 1, UIFont.Small, true)
    self.baseTaxLbl:initialise()
    self:addChild(self.baseTaxLbl)

    self.baseTaxEntry = ISTextEntryBox:new(tostring(curBase), pad + labelW, curY, entryW, 24)
    self.baseTaxEntry:initialise()
    self.baseTaxEntry:instantiate()
    self.baseTaxEntry:setOnlyNumbers(true)
    self.baseTaxEntry.onTextChange = function() self:updateTotalCalculation() end
    self.baseTaxEntry.target = self
    self:addChild(self.baseTaxEntry)
    curY = curY + 32

    if not self.isPersonal then
        local members = self.safehouse and self.safehouse:getPlayers()
        local memberCount = members and members:size() or 1
        
        self.memberTaxLbl = ISLabel:new(pad, curY + 4, 20, string.format("Extra Member Tax (%d members):", memberCount), 1, 1, 1, 1, UIFont.Small, true)
        self.memberTaxLbl:initialise()
        self:addChild(self.memberTaxLbl)

        self.memberTaxEntry = ISTextEntryBox:new(tostring(curMember), pad + labelW, curY, entryW, 24)
        self.memberTaxEntry:initialise()
        self.memberTaxEntry:instantiate()
        self.memberTaxEntry:setOnlyNumbers(true)
        self.memberTaxEntry.onTextChange = function() self:updateTotalCalculation() end
        self.memberTaxEntry.target = self
        self:addChild(self.memberTaxEntry)
        curY = curY + 32
    end

    self.penaltyLbl = ISLabel:new(pad, curY + 4, 20, "Penalty / Extra Fees ($):", 1, 1, 1, 1, UIFont.Small, true)
    self.penaltyLbl:initialise()
    self:addChild(self.penaltyLbl)

    self.penaltyEntry = ISTextEntryBox:new(tostring(curPenalty), pad + labelW, curY, entryW, 24)
    self.penaltyEntry:initialise()
    self.penaltyEntry:instantiate()
    self.penaltyEntry:setOnlyNumbers(true)
    self.penaltyEntry.onTextChange = function() self:updateTotalCalculation() end
    self.penaltyEntry.target = self
    self:addChild(self.penaltyEntry)
    curY = curY + 32

    self.noteLbl = ISLabel:new(pad, curY + 4, 20, "Bill Note:", 1, 1, 1, 1, UIFont.Small, true)
    self.noteLbl:initialise()
    self:addChild(self.noteLbl)

    self.noteEntry = ISTextEntryBox:new(curNote, pad + labelW, curY, entryW, 24)
    self.noteEntry:initialise()
    self.noteEntry:instantiate()
    self.noteEntry:setSelectable(true)
    self:addChild(self.noteEntry)
    curY = curY + 40

    self.totalLabel = ISLabel:new(pad, curY, 25, "Net Payable Amount: $0", 0.2, 0.9, 0.3, 1, UIFont.Large, true)
    self.totalLabel:initialise()
    self:addChild(self.totalLabel)
    curY = curY + 45

    local btnW = (contentW - pad) / 2
    
    self.savePresetBtn = ISButton:new(pad, curY, btnW, 32, "Save Preset", self, self.onSavePreset)
    self.savePresetBtn:initialise()
    self.savePresetBtn:instantiate()
    self.savePresetBtn.backgroundColor = {r = 0.1, g = 0.5, b = 0.2, a = 0.9}
    self:addChild(self.savePresetBtn)

    self.cancelBtn = ISButton:new(pad + btnW + pad, curY, btnW, 32, "Cancel", self, self.onClose)
    self.cancelBtn:initialise()
    self.cancelBtn:instantiate()
    self.cancelBtn.backgroundColor = {r = 0.5, g = 0.2, b = 0.2, a = 0.9}
    self:addChild(self.cancelBtn)

    self:updateTotalCalculation()
end

function HFTaxUI.AdminBillEditor:updateTotalCalculation()
    local base = tonumber(self.baseTaxEntry:getText()) or 0
    local member = (self.memberTaxEntry and tonumber(self.memberTaxEntry:getText())) or 0
    local penalty = tonumber(self.penaltyEntry:getText()) or 0
    local total = math.max(0, base + member + penalty)
    
    self.totalLabel:setName(string.format("Net Payable Amount: $%d", total))
end

function HFTaxUI.AdminBillEditor:onSavePreset()
    local baseVal = tonumber(self.baseTaxEntry:getText()) or 0
    local memberVal = (self.memberTaxEntry and tonumber(self.memberTaxEntry:getText())) or 0
    local penaltyVal = tonumber(self.penaltyEntry:getText()) or 0
    local totalVal = math.max(0, baseVal + memberVal + penaltyVal)
    local noteText = self.noteEntry:getText()

    local globalData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)

    if self.isPersonal then
        local puuid = HFTax.Utils.getPlayerPUUID(self.targetUsername)
        local bNum = self.previewBill.billNumber or HFTax.Utils.formatBillNumber(1)

        -- Optimistic Local Staging Update
        globalData.PersonalPreviews = globalData.PersonalPreviews or {}
        globalData.PersonalPreviews[self.targetUsername] = {
            puuid = puuid,
            billCounter = 1,
            billNumber = bNum,
            baseTax = baseVal,
            penalty = penaltyVal,
            totalAmount = totalVal,
            note = noteText,
            scheduledEpoch = self.previewBill.scheduledEpoch or (HFTax.Utils.getRealDaysEpoch() + HFTax.Config.DefaultPersonalTax.cycleDays),
            customOverride = true
        }

        sendClientCommand(self.player, HFTax.Config.MOD_ID, "UpdatePersonalPreviewBill", {
            username = self.targetUsername,
            billNumber = bNum,
            baseTax = baseVal,
            penalty = penaltyVal,
            totalAmount = totalVal,
            note = noteText
        })
    else
        local shKey = HFTax.Utils.getSafehouseKey(self.safehouse)
        local shid = HFTax.Utils.getSafehouseSHID(self.safehouse)
        local bNum = self.previewBill.billNumber or HFTax.Utils.formatBillNumber(1)

        -- Optimistic Local Staging Update
        globalData.Safehouses = globalData.Safehouses or {}
        globalData.Safehouses[shKey] = globalData.Safehouses[shKey] or {}
        globalData.Safehouses[shKey].previewBill = {
            shid = shid,
            billNumber = bNum,
            landTax = baseVal,
            memberTax = memberVal,
            penalty = penaltyVal,
            totalAmount = totalVal,
            note = noteText,
            scheduledEpoch = self.previewBill.scheduledEpoch or (HFTax.Utils.getRealDaysEpoch() + HFTax.Config.BILL_CYCLE_DAYS),
            customOverride = true
        }

        sendClientCommand(self.player, HFTax.Config.MOD_ID, "UpdatePreviewBill", {
            safehouseKey = shKey,
            billNumber = bNum,
            landTax = baseVal,
            memberTax = memberVal,
            penalty = penaltyVal,
            totalAmount = totalVal,
            note = noteText
        })
    end

    self:onClose()
end

function HFTaxUI.AdminBillEditor:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    HFTaxUI.AdminBillEditor.instance = nil
end

function HFTaxUI.AdminBillEditor.openWindow(player, safehouse, previewBill, targetUsername)
    if not isPlayerAdmin(player) then return end

    if HFTaxUI.AdminBillEditor.instance then
        HFTaxUI.AdminBillEditor.instance:onClose()
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 500, 340
    local x, y = (sw - w) / 2, (sh - h) / 2

    local ui = HFTaxUI.AdminBillEditor:new(x, y, w, h, player, safehouse, previewBill, targetUsername)
    ui:initialise()
    ui:addToUIManager()
    HFTaxUI.AdminBillEditor.instance = ui
end