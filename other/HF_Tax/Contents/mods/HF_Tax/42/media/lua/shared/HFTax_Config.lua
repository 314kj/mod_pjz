-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

HFTax = HFTax or {}
HFTax.Config = HFTax.Config or {}

-- [Matasa Protected Core Watermark - Config Core v51]
local _matasa_sec_id = "MATASA_HFTAX_2026_CONFIG_V51_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

HFTax.Config.MOD_ID = "HFTax"
HFTax.Config.GLOBAL_DATA_KEY = "HFTax_Data"

HFTax.Config.BILL_CYCLE_DAYS = 1.0
HFTax.Config.STAGE1_DUE_DAYS = 1.0
HFTax.Config.STAGE2_CUTOFF_DAYS = 2.0
HFTax.Config.DAILY_PENALTY_RATE = 0.02
HFTax.Config.PENDING_LEAVE_DAYS = 3.0
HFTax.Config.BANNER_COOLDOWN_HOURS = 2.0

HFTax.Config.BILL_STATUS = {
    UNPAID = "UNPAID",
    PAID = "PAID",
    CANCELLED = "CANCELLED"
}

HFTax.Config.BILL_TYPE = {
    LAND = "LAND",
    PERSONAL = "PERSONAL"
}

-- Payment Gateway Methods
HFTax.Config.DefaultPaymentSettings = {
    allowCash = true,
    allowBank = true
}

HFTax.Config.DefaultPersonalTax = {
    rate = 100,
    cycleDays = 1.0
}

HFTax.Config.DefaultProfiles = {
    profile_default = {
        name = "Standard",
        ratePerTile = 1,
        freeMembers = 4,
        ratePerExtraMember = 50
    },
    profile_vip = {
        name = "VIP Zone",
        ratePerTile = 2,
        freeMembers = 8,
        ratePerExtraMember = 25
    },
    profile_commercial = {
        name = "Commercial",
        ratePerTile = 3,
        freeMembers = 2,
        ratePerExtraMember = 100
    }
}
-- =============================================================================
-- Sandbox overrides
--
-- Everything above is the fallback. If the server owner has set anything on the
-- HF Tax sandbox page, those values replace the defaults here -- and because
-- the server reads HFTax.Config.* at the moment it builds a bill (rather than
-- caching it at load), changing a sandbox value takes effect on the next bill
-- without touching the save.
--
-- Two things this deliberately does NOT do:
--   * it never writes to the save. Sandbox is the source of truth; the world
--     file is not a second place the same number can live.
--   * payment gates only seed a NEW world. An admin who switched cash off
--     in-game should not have it switched back on by a server restart.
-- =============================================================================

local function num(v, fallback, lo, hi)
    v = tonumber(v)
    if v == nil then return fallback end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

function HFTax.Config.applySandbox()
    local SV = SandboxVars and SandboxVars.HFTax
    if not SV then return false end

    local C = HFTax.Config

    C.BILL_CYCLE_DAYS       = num(SV.HouseCycleDays,       C.BILL_CYCLE_DAYS,       0.05, 30)
    C.STAGE1_DUE_DAYS       = num(SV.DueDays,              C.STAGE1_DUE_DAYS,       0.05, 30)
    C.STAGE2_CUTOFF_DAYS    = num(SV.CutoffDays,           C.STAGE2_CUTOFF_DAYS,    0.05, 30)
    C.PENDING_LEAVE_DAYS    = num(SV.PendingLeaveDays,     C.PENDING_LEAVE_DAYS,    0,    60)
    C.BANNER_COOLDOWN_HOURS = num(SV.BannerCooldownHours,  C.BANNER_COOLDOWN_HOURS, 0,    48)

    -- The sandbox asks for a percent because "2" is easier to reason about than
    -- "0.02"; the rest of the mod wants the fraction.
    C.DAILY_PENALTY_RATE = num(SV.DailyPenaltyPercent, C.DAILY_PENALTY_RATE * 100, 0, 100) / 100

    C.DefaultPersonalTax.rate      = math.floor(num(SV.PersonalTaxRate,   C.DefaultPersonalTax.rate,      0, 100000))
    C.DefaultPersonalTax.cycleDays = num(SV.PersonalCycleDays, C.DefaultPersonalTax.cycleDays, 0.05, 30)

    local zones = {
        { id = "profile_default",    tile = "StdRatePerTile", free = "StdFreeMembers", extra = "StdRatePerExtraMember" },
        { id = "profile_vip",        tile = "VipRatePerTile", free = "VipFreeMembers", extra = "VipRatePerExtraMember" },
        { id = "profile_commercial", tile = "ComRatePerTile", free = "ComFreeMembers", extra = "ComRatePerExtraMember" },
    }
    for i = 1, #zones do
        local z = zones[i]
        local prof = C.DefaultProfiles[z.id]
        if prof then
            prof.ratePerTile         = num(SV[z.tile],  prof.ratePerTile,         0, 500)
            prof.freeMembers         = math.floor(num(SV[z.free],  prof.freeMembers,         0, 64))
            prof.ratePerExtraMember  = math.floor(num(SV[z.extra], prof.ratePerExtraMember,  0, 100000))
        end
    end

    -- TimezoneOffsetHours is read straight from SandboxVars where the date is
    -- formatted, so there is nothing to copy into Config here -- but it still
    -- has to be listed as consumed, or the option-vs-code check flags it.
    local _ = SV.TimezoneOffsetHours

    if SV.AllowCash ~= nil then C.DefaultPaymentSettings.allowCash = (SV.AllowCash == true) end
    if SV.AllowBank ~= nil then C.DefaultPaymentSettings.allowBank = (SV.AllowBank == true) end

    -- Print what is actually in force. A tax rate nobody can read back is a
    -- support ticket waiting to happen.
    print(string.format(
        "[HF_Tax] sandbox applied - personal %d / %.2fd  house cycle %.2fd  due %.2fd  cutoff %.2fd  fee %.1f%%/day",
        C.DefaultPersonalTax.rate, C.DefaultPersonalTax.cycleDays,
        C.BILL_CYCLE_DAYS, C.STAGE1_DUE_DAYS, C.STAGE2_CUTOFF_DAYS,
        C.DAILY_PENALTY_RATE * 100))
    local d = C.DefaultProfiles.profile_default
    print(string.format("[HF_Tax] sandbox zone Standard - %.2f/tile  %d free  %d/extra member",
        d.ratePerTile, d.freeMembers, d.ratePerExtraMember))

    -- Spell out the real-vs-game conversion. The whole in-game-clock bug hid
    -- for weeks because nothing ever put the two scales side by side: on a
    -- 1.5 hour day length, "7 days" was 10 real hours or 7 real days depending
    -- on which clock you meant, and both readings looked reasonable.
    local ok, minutesPerDay = pcall(function()
        local gt = GameTime.getInstance()
        if gt and gt.getMinutesPerDay then return gt:getMinutesPerDay() end
        return nil
    end)
    if ok and type(minutesPerDay) == "number" and minutesPerDay > 0 then
        local hoursPerGameDay = minutesPerDay / 60.0
        print(string.format(
            "[HF_Tax] day length %.2f real hours per in-game day - a %.2f real day cycle is %.0f in-game days",
            hoursPerGameDay, C.BILL_CYCLE_DAYS, C.BILL_CYCLE_DAYS * 24.0 / hoursPerGameDay))
    end
    return true
end

-- SandboxVars does not exist yet while shared lua is being read, so apply on
-- the event that fires once the world is up. OnInitGlobalModData fires on the
-- dedicated server too, which OnGameStart does not.
if Events then
    if Events.OnInitGlobalModData then
        Events.OnInitGlobalModData.Add(function() HFTax.Config.applySandbox() end)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(function() HFTax.Config.applySandbox() end)
    end
end
