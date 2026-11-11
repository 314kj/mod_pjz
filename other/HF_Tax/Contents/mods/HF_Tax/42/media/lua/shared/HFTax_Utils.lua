-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Author: matasa
-- All Rights Reserved. Copyright (c) 2026 matasa.
-- Unauthorized copying, repackaging, or distribution is strictly prohibited.
-- =============================================================================

---@diagnostic disable: undefined-global
HFTax = HFTax or {}
HFTax.Utils = HFTax.Utils or {}

-- [Matasa Protected Core Watermark - Shared Utils Master v23]
local _matasa_sec_id = "MATASA_HFTAX_2026_UTILS_V23_SEC"
local _matasa_chk = function(v) return (type(v) == "string" and #v * 42) or 0 end

function HFTax.Utils.getSafehouseKey(sh)
    if not sh then return "SH_UNKNOWN" end
    local x = sh:getX() or 0
    local y = sh:getY() or 0
    local w = sh:getW() or 0
    local h = sh:getH() or 0
    return string.format("SH_%d_%d_%d_%d", x, y, w, h)
end

function HFTax.Utils.getSafehouseSHID(sh)
    if not sh then return "000000" end
    local x = sh:getX() or 0
    local y = sh:getY() or 0
    local w = sh:getW() or 0
    local hash = math.abs((x * 374761393) + (y * 668265263) + (w * 1013904223)) % 900000 + 100000
    return string.format("%06d", hash)
end

function HFTax.Utils.getPlayerPUUID(username)
    if not username or username == "" then return "P00000" end
    local hash = 0
    for i = 1, #username do
        hash = (hash * 31 + string.byte(username, i)) % 900000
    end
    return string.format("P%05d", hash + 10000)
end

function HFTax.Utils.formatBillNumber(seq)
    seq = math.max(1, tonumber(seq) or 1)
    return string.format("%03d", seq)
end

function HFTax.Utils.constructBillId(prefixType, targetId, billNumber)
    return string.format("%s_%s-%s", prefixType or "BILL", tostring(targetId or "000000"), tostring(billNumber or "001"))
end

---Days on the REAL clock, as a floating point number.
---
---This function used to read GameTime:getCalender(), which is the IN-GAME
---calendar -- the one showing 1993. So a "1 day" bill cycle was one in-game
---day, which at default speed is roughly one real hour, and every label that
---said "days" meant something else entirely. The name said Real and the body
---said game; the name won every argument it was ever in.
---
---getTimestamp() is the wall clock (seconds since 1970). Everything the mod
---schedules -- bill cycles, due dates, cut-off, late fees -- is now measured
---in real days, which is what a server owner setting "7" means.
function HFTax.Utils.getRealDaysEpoch()
    if getTimestamp then
        local t = getTimestamp()
        if type(t) == "number" and t > 0 then return t / 86400.0 end
    end
    if getTimestampMs then
        local t = getTimestampMs()
        if type(t) == "number" and t > 0 then return t / 86400000.0 end
    end
    -- Neither clock available (should not happen). Fall back to game time so
    -- the mod keeps working rather than freezing every bill at epoch 0.
    local gt = GameTime.getInstance()
    if not gt then return 0 end
    return gt:getWorldAgeHours() / 24.0
end

---True when a stored epoch was written by the old in-game-calendar version.
---In-game epochs land around 728,000 (year 1993 x 365.25); real-day epochs are
---around 20,000 and stay there for the next few centuries. Nothing legitimate
---sits between them.
HFTax.Utils.LEGACY_EPOCH_FLOOR = 100000

function HFTax.Utils.isLegacyEpoch(v)
    v = tonumber(v)
    return v ~= nil and v >= HFTax.Utils.LEGACY_EPOCH_FLOOR
end

---Calendar date from a day number, using Howard Hinnant's civil_from_days.
---Kahlua has no os.date, so the conversion has to be done by hand.
local function civilFromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524)
                            - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    if m <= 2 then y = y + 1 end
    return y, m, d
end

---Stamp shown on a bill: the REAL date it was issued or settled.
---
---It used to print the in-game date, so a bill charged on a real weekly cycle
---was stamped 1993-07-12 and two bills a real week apart could carry in-game
---dates minutes apart. The timezone comes from the sandbox because Kahlua has
---no way to ask the machine what timezone it is in.
function HFTax.Utils.getCurrentDateTimeString()
    local offsetHours = 0
    if SandboxVars and SandboxVars.HFTax and SandboxVars.HFTax.TimezoneOffsetHours then
        offsetHours = tonumber(SandboxVars.HFTax.TimezoneOffsetHours) or 0
    end

    local days = HFTax.Utils.getRealDaysEpoch() + (offsetHours / 24.0)
    -- Below ~1997 means the wall clock was not available and we are looking at
    -- the game-time fallback. Say so rather than stamping a bill "1970-01-01".
    if days < 10000 then return "Unknown Date" end

    local whole = math.floor(days)
    local frac = days - whole
    local y, m, d = civilFromDays(whole)
    -- Truncate, never round: 01:46:40 is 01:46, the same way a clock shows it.
    local totalMinutes = math.floor(frac * 1440)
    if totalMinutes >= 1440 then totalMinutes = 1439 end
    local hour = math.floor(totalMinutes / 60)
    local minute = totalMinutes - hour * 60

    return string.format("%04d-%02d-%02d %02d:%02d", y, m, d, hour, minute)
end

function HFTax.Utils.calculateLandTax(width, height, ratePerTile)
    width = math.max(0, width or 0)
    height = math.max(0, height or 0)
    ratePerTile = ratePerTile or 0.5
    return math.ceil(width * height * ratePerTile)
end

function HFTax.Utils.calculateMemberTax(memberCount, freeQuota, ratePerExtra)
    memberCount = math.max(0, memberCount or 0)
    freeQuota = math.max(0, freeQuota or 0)
    ratePerExtra = math.max(0, ratePerExtra or 0)
    
    local extraMembers = math.max(0, memberCount - freeQuota)
    local memberTax = extraMembers * ratePerExtra
    return memberTax, extraMembers
end

function HFTax.Utils.formatRemainingTime(targetDaysEpoch)
    local currentDays = HFTax.Utils.getRealDaysEpoch()
    local diffDays = (targetDaysEpoch or 0) - currentDays
    
    if diffDays <= 0 then
        local overdueDays = math.floor(math.abs(diffDays))
        return string.format("Overdue (%d Days)", overdueDays), true
    end
    
    local days = math.floor(diffDays)
    local hours = math.floor((diffDays - days) * 24)
    return string.format("%d Days %d Hours", days, hours), false
end

---2-Stage Status Evaluator: Computes Stage 1 Due and Stage 2 Cutoff Countdown
---@param bill table
---@return string, boolean, boolean
function HFTax.Utils.getBillTimingStatus(bill)
    if not bill then return "N/A", false, false end
    if bill.status == HFTax.Config.BILL_STATUS.PAID then
        return "Settled", false, false
    end

    local currentEpoch = HFTax.Utils.getRealDaysEpoch()
    local dueEpoch = bill.dueDaysEpoch or (currentEpoch + HFTax.Config.STAGE1_DUE_DAYS)
    local stage2Epoch = bill.stage2Epoch or (dueEpoch + HFTax.Config.STAGE2_CUTOFF_DAYS)

    if currentEpoch < dueEpoch then
        -- Stage 1 Active: Normal Countdown
        local diffDays = dueEpoch - currentEpoch
        local days = math.floor(diffDays)
        local hours = math.floor((diffDays - days) * 24)
        return string.format("Due in: %d Days %d Hours", days, hours), false, false
    elseif currentEpoch < stage2Epoch then
        -- Stage 1 Overdue & Stage 2 Cutoff Countdown
        local overdueDays = math.floor(currentEpoch - dueEpoch)
        local diffCutoff = stage2Epoch - currentEpoch
        local cDays = math.floor(diffCutoff)
        local cHours = math.floor((diffCutoff - cDays) * 24)
        local timingStr = string.format("Overdue %d Days (Cut-off in: %d Days %d Hours)", overdueDays, cDays, cHours)
        return timingStr, true, false
    else
        -- Stage 2 Active: Cut-off Enforced
        local overdueDays = math.floor(currentEpoch - dueEpoch)
        return string.format("CUT-OFF ACTIVE (Overdue %d Days)", overdueDays), true, true
    end
end