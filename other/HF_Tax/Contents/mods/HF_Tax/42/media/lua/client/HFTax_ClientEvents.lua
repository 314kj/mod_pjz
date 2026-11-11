-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
local HFTax = HFTax or {}
HFTax.ClientEvents = HFTax.ClientEvents or {}
HFTax.ClientData = HFTax.ClientData or {
    SafehouseStatus = {},
    CutoffSafehouses = {},
    OverdueSafehouses = {},
    BankBalance = 0
}

-- [Matasa Protected Core Watermark - Client Events Bank Sync v52]
local _matasa_sec_id = "MATASA_HFTAX_2026_CLIENT_EVT_BANKSYNC_V52_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

-- The right-click entry is gone on purpose.
--
-- It used to be the only way in, and it put a tax option on every square in
-- the world -- including squares where the player was right-clicking to do
-- something else entirely. The Billing Center is now opened from the bank
-- screen instead, through the public hook below, which is also the only entry
-- that can pass a starting safehouse.
--
--     HFTaxAPI.openInvoiceManager(playerObj)
--
-- The overdue notice popup ("Pay Now") is the other way in, and the admin
-- tools are untouched -- they still open from the Admin CP.

-- One line, printed once, that answers "which build am I actually running?"
-- Two days were spent on that question with no way to tell an old copy from a
-- new one from inside the game.
local HFTAX_UI_BUILD = "UI revision by AKA - build 2026-08-18"

local function onGameStartRegisterAdminCP()
    print("[HF_Tax] " .. HFTAX_UI_BUILD)
    print("[HF_Tax] Billing Center present: " ..
        tostring(HFTaxUI ~= nil and HFTaxUI.BillingWindow ~= nil))

    local player = getPlayer()
    if player then
        sendClientCommand(player, HFTax.Config.MOD_ID, "RequestSafehouseStatus", {})
        sendClientCommand(player, HFTax.Config.MOD_ID, "RequestPlayerBills", {
            myPUUID = HFTax.Utils.getPlayerPUUID(player:getUsername()),
            username = player:getUsername()
        })
    end

    if HF_AdminCP_API and HF_AdminCP_API.RegisterPlugin then
        HF_AdminCP_API.RegisterPlugin("HF_Tax (Staging & Settings)", function(playerObj)
            if HFTaxUI and HFTaxUI.AdminUI then
                HFTaxUI.AdminUI.openWindow(playerObj)
            end
        end)

        HF_AdminCP_API.RegisterPlugin("HF_Tax (Bill & Tax Ledger)", function(playerObj)
            if HFTaxUI and HFTaxUI.AdminLedgerUI then
                HFTaxUI.AdminLedgerUI.openWindow(playerObj)
            end
        end)
    end
end

local function onServerCommand(module, command, args)
    if module ~= HFTax.Config.MOD_ID or not args then return end

    local localData = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)

    if command == "SyncSafehouseStatus" and args.statusMap then
        HFTax.ClientData.SafehouseStatus = args.statusMap or {}
        HFTax.ClientData.CutoffSafehouses = {}
        HFTax.ClientData.OverdueSafehouses = {}

        for shKey, st in pairs(args.statusMap) do
            if st.isCutoff then
                HFTax.ClientData.CutoffSafehouses[shKey] = true
            end
            if st.isOverdue then
                HFTax.ClientData.OverdueSafehouses[shKey] = true
            end
        end

        local p = getPlayer()
        if p and HFTax.AlertNotifier and HFTax.AlertNotifier.checkOnLogin then
            HFTax.AlertNotifier.checkOnLogin(p)
        end
    elseif command == "SyncAdminData" and args.globalData then
        for k, v in pairs(args.globalData) do
            localData[k] = v
        end
        if HFTaxUI and HFTaxUI.AdminUI and HFTaxUI.AdminUI.instance then
            HFTaxUI.AdminUI.instance:populateLeftList()
        end
        if HFTaxUI and HFTaxUI.AdminLedgerUI and HFTaxUI.AdminLedgerUI.instance then
            HFTaxUI.AdminLedgerUI.instance:updatePaymentTickBoxState()
            HFTaxUI.AdminLedgerUI.instance:populateLeftList()
        end
    elseif command == "SyncPlayerBills" and args.bills then
        localData.Bills = args.bills
        if args.bankBalance ~= nil then
            HFTax.ClientData.BankBalance = args.bankBalance
        end
        -- The Billing Center rebuilds its model every frame from ModData, so
        -- there is nothing to poke here; only the old window needs telling.
        if HFTaxUI and HFTaxUI.InvoiceManager and HFTaxUI.InvoiceManager.instance then
            HFTaxUI.InvoiceManager.instance:populateBills()
        end
    elseif command == "TreasuryWithdrawSuccess" then
        local player = getPlayer()
        if player and HaloTextHelper then
            HaloTextHelper.addTextWithArrow(player, string.format("Withdrawn $%d from Treasury Vault!", args.amount or 0), true, 50, 255, 50)
        end
    elseif command == "TreasuryWithdrawFailed" then
        local player = getPlayer()
        if player and HaloTextHelper then
            HaloTextHelper.addTextWithArrow(player, string.format("Withdrawal Failed: Amount exceeds Vault balance ($%d)!", args.maxAvailable or 0), false, 255, 50, 50)
        end
    elseif command == "PaymentSuccess" then
        -- The Billing Center rebuilds its model every frame from ModData, so
        -- there is nothing to poke here; only the old window needs telling.
        if HFTaxUI and HFTaxUI.InvoiceManager and HFTaxUI.InvoiceManager.instance then
            HFTaxUI.InvoiceManager.instance:populateBills()
        end
        local player = getPlayer()
        if player and HaloTextHelper then
            HaloTextHelper.addTextWithArrow(player, string.format("Tax Paid Successfully! ($%d)", args.amount or 0), true, 50, 255, 50)
        end
    elseif command == "PaymentFailed" then
        local player = getPlayer()
        if player and HaloTextHelper then
            if args and args.reason == "NOT_OWNER" then
                HaloTextHelper.addTextWithArrow(player, "Warning: Only safehouse owner can pay this tax!", false, 255, 75, 75)
            elseif args and args.reason == "MUST_PAY_OLDEST_FIRST" then
                HaloTextHelper.addTextWithArrow(player, "Warning: Please pay the oldest outstanding bill first!", false, 255, 75, 75)
            elseif args and args.reason == "BANK_PAYMENT_DISABLED" then
                HaloTextHelper.addTextWithArrow(player, "Payment Failed: Bank payments are disabled by Server!", false, 255, 75, 75)
            elseif args and args.reason == "CASH_PAYMENT_DISABLED" then
                HaloTextHelper.addTextWithArrow(player, "Payment Failed: Cash payments are disabled by Server!", false, 255, 75, 75)
            else
                HaloTextHelper.addTextWithArrow(player, "Payment Failed: Insufficient funds!", false, 255, 50, 50)
            end
        end
    end
end

Events.OnGameStart.Add(onGameStartRegisterAdminCP)
Events.OnServerCommand.Add(onServerCommand)