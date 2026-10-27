-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
HFTaxAPI = HFTaxAPI or {}

-- [Matasa Protected Core Watermark - Public API]
local _matasa_sec_id = "MATASA_HFTAX_2026_API_SEC"

---Open invoice management UI for external mod hooks
---@param playerObj IsoPlayer
function HFTaxAPI.openInvoiceManager(playerObj)
    if not playerObj then return end
    
    if isClient() or not isServer() then
        if HFTaxUI and HFTaxUI.BillingWindow then
            HFTaxUI.BillingWindow.openWindow(playerObj, nil)
        elseif HFTaxUI and HFTaxUI.InvoiceManager then
            -- Falling back to the pre-revision window. This used to happen
            -- silently, which made "the new UI did not load" look exactly like
            -- "the new UI is ugly" -- the player just saw the old screen and
            -- had no way to tell which build was running. Say it out loud.
            print("[HF_Tax] !! Billing Center did not load - falling back to the old Invoice Manager.")
            print("[HF_Tax] !! Two copies of HF_Tax are probably installed, or the build in use is missing")
            print("[HF_Tax] !! media/lua/client/UI/HFTax_BillingCenterWindow.lua")
            HFTaxUI.InvoiceManager.openWindow(playerObj, nil)
        end
    end
end