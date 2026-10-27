-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Original work: Copyright (c) 2026 matasa. All Rights Reserved.
-- UI revision: AKA (LOOKCHINNOL), published with the author's permission.
--
-- HFTax_TimeMigration.lua -- moves an existing save off the in-game clock.
--
-- Bills used to be timed by the IN-GAME calendar, so every stored epoch sits
-- around 728,000 (year 1993 x 365.25). Real-day epochs sit around 20,000. If
-- the old numbers were left alone, "now" would be 700,000 days before every
-- due date: no bill would ever come due, no late fee would ever start, and no
-- safehouse would ever be cut off -- silently, with nothing in the log.
--
-- So the rebase happens once, on the first server boot after the change, and
-- says exactly what it did.
-- =============================================================================

---@diagnostic disable: undefined-global
if isClient() then return end

local MIGRATION_KEY = "clockRebaseDone_v1"

local function rebase(bills, now, cfg)
    local moved, cleared = 0, 0

    for _, b in pairs(bills or {}) do
        local touched = false

        -- A settled bill only needs its stamp to stop claiming 1993. There is
        -- no real date to recover, so the field is dropped rather than faked;
        -- the UI already falls back to "Completed" when it is missing.
        if b.status == HFTax.Config.BILL_STATUS.PAID then
            if HFTax.Utils.isLegacyEpoch(b.paidEpoch) then b.paidEpoch = nil; touched = true end
            if HFTax.Utils.isLegacyEpoch(b.createdEpoch) then b.createdEpoch = nil; touched = true end
            if touched then cleared = cleared + 1 end
        else
            -- An outstanding bill gets a fresh, fair clock: issued now, due
            -- after the configured window, cut-off after that. Restarting the
            -- countdown is the only honest option -- the real time it was
            -- issued was never recorded, and guessing it could cut someone's
            -- power off the moment the server comes up.
            if HFTax.Utils.isLegacyEpoch(b.createdEpoch)
                or HFTax.Utils.isLegacyEpoch(b.dueDaysEpoch)
                or HFTax.Utils.isLegacyEpoch(b.stage2Epoch) then
                b.createdEpoch  = now
                b.dueDaysEpoch  = now + (cfg.STAGE1_DUE_DAYS or 1)
                b.stage2Epoch   = b.dueDaysEpoch + (cfg.STAGE2_CUTOFF_DAYS or 2)
                b.isOverdue      = false
                b.isCutoffStage  = false
                b.overdueDays    = 0
                -- Take the accrued late fee back out of the total instead of
                -- trying to rebuild the base from its parts: subtraction works
                -- for a land bill and a personal bill without knowing which.
                b.totalAmount    = math.max(0, (b.totalAmount or 0) - (b.penalty or 0))
                b.penalty        = 0
                moved = moved + 1
            end
        end
    end

    return moved, cleared
end

local function rebaseSchedules(data, now, cfg)
    local n = 0

    local function fix(rec, field, span)
        if rec and HFTax.Utils.isLegacyEpoch(rec[field]) then
            rec[field] = now + span
            n = n + 1
        end
    end

    local houseSpan = cfg.BILL_CYCLE_DAYS or 1
    for _, house in pairs(data.Houses or {}) do
        fix(house, "scheduledEpoch", houseSpan)
        -- leaveEpoch hangs off each member record, not off the house, so the
        -- walk has to go one level deeper. Missing it would leave a departed
        -- member permanently "just left" and never past the grace period.
        for _, member in pairs(house.members or {}) do
            if member and HFTax.Utils.isLegacyEpoch(member.leaveEpoch) then
                member.leaveEpoch = now
                n = n + 1
            end
        end
    end

    local personalSpan = (cfg.DefaultPersonalTax and cfg.DefaultPersonalTax.cycleDays) or 1
    for _, rec in pairs(data.Players or {}) do
        fix(rec, "scheduledEpoch", personalSpan)
    end
    for _, rec in pairs(data.PersonalPreviews or {}) do
        fix(rec, "scheduledEpoch", personalSpan)
    end

    return n
end

local function migrate()
    local data = ModData.getOrCreate(HFTax.Config.GLOBAL_DATA_KEY)
    data.meta = data.meta or {}
    if data.meta[MIGRATION_KEY] then return end

    local now = HFTax.Utils.getRealDaysEpoch()
    if now < 10000 then
        -- Wall clock not readable yet. Do nothing rather than rebase every
        -- bill onto a bogus "now" -- a wrong migration cannot be undone.
        print("[HF_Tax] clock rebase postponed: real clock not available yet")
        return
    end

    local moved, cleared = rebase(data.Bills, now, HFTax.Config)
    local sched = rebaseSchedules(data, now, HFTax.Config)

    data.meta[MIGRATION_KEY] = true

    if moved + cleared + sched > 0 then
        print(string.format(
            "[HF_Tax] clock rebase: %d outstanding bills restarted, %d settled stamps cleared, %d schedules moved",
            moved, cleared, sched))
        print("[HF_Tax] bills are now timed by the REAL clock; sandbox days mean real days")
    else
        print("[HF_Tax] clock rebase: nothing to convert (save already on the real clock)")
    end
end

Events.OnInitGlobalModData.Add(function()
    local ok, err = pcall(migrate)
    if not ok then print("[HF_Tax] !! clock rebase failed: " .. tostring(err)) end
end)
