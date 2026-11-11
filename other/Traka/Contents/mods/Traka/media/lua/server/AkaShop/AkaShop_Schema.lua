--[[===========================================================================
    AkaShop - schema versioning and migration.

    THE RULE THIS FILE EXISTS TO ENFORCE:
    updating the mod must never cost a player their shops, stock, till or
    settings. Everything lives in global ModData, which the save keeps across
    mod updates on its own -- what actually destroys data is CODE: a field that
    quietly changed shape, a table reset "just to be safe", or a newer save
    opened by an older mod.

    So four guarantees:

    1. NON-DESTRUCTIVE. A migration may add fields and reshape ones it owns.
       It may never delete a key it does not recognise. Anything a future
       version wrote and this version does not understand is carried along
       untouched.
    2. BACKUP FIRST. Before the first migrating write, the whole shop table is
       deep-copied to d._bak. If a migration turns out to be wrong, the data is
       still sitting there. The backup is dropped on the NEXT clean boot, so
       there is always exactly one generation of headroom and never two.
    3. NO DOWNGRADE WRITES. If the save carries a schema NEWER than this build
       understands, the player rolled the mod back. We do not guess at the
       newer layout -- the mod goes read-only and says so loudly. A refusal to
       start is recoverable; a mangled shop table is not.
    4. IDEMPOTENT. Running the ladder twice is a no-op. Every step checks for
       its own result before doing anything.
============================================================================]]

AkaShopSchema = AkaShopSchema or {}

AkaShopSchema.CURRENT = 4
AkaShopSchema.locked  = false      -- true when the save is from a newer build
AkaShopSchema.lockMsg = nil

local function log(m) print("[Traka/schema] " .. tostring(m)) end

--- Plain-tree deep copy. The DB holds only tables, numbers, strings and
--- booleans, so this never has to worry about cycles or userdata.
local function deep(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deep(x) end
    return t
end
AkaShopSchema.deepCopy = deep

--=============================================================== migrations ==
-- steps[n] upgrades a database sitting at version n to version n+1.

local steps = {}

--- 1 -> 2 : stock rows gain identity.
--- v1 kept a listing as { ft, qty, price, name } -- a bare count, so a pristine
--- axe and a nearly-broken one were the same number. v2 keeps the same listing
--- but hangs a `units` array off it, one row per distinct condition, each with
--- its own count. Existing stock has no recorded condition, so it becomes a
--- single full-condition row: exactly what those units already behaved like.
--- The old `qty` field is KEPT and kept in sync, so a half-updated server or a
--- rollback still reads sane numbers.
steps[1] = function(d)
    for _, shop in pairs(d.shops or {}) do
        for _, e in ipairs(shop.items or {}) do
            if not e.units then
                local n = math.floor(tonumber(e.qty) or 0)
                e.units = (n > 0) and { { n = n, cond = nil, age = nil } } or {}
            end
        end
        -- additive fields; only fill when absent so a re-run changes nothing
        if shop.mode      == nil then shop.mode      = "auto"  end
        if shop.capacityKg== nil then shop.capacityKg= 20      end
        if shop.orders    == nil then shop.orders    = {}      end
        if shop.nextOrder == nil then shop.nextOrder = 1       end
    end
    if d.nextOrderId == nil then d.nextOrderId = 1 end
end

--- 2 -> 3 : sales become day buckets, plus the weight quota and mode fields.
--- v2 appended one row per sale forever, so a server that ran for a year kept
--- growing its save with no ceiling. v3 keeps a per-day total (bounded by the
--- retention window), a single rolled-up "everything older", a per-item running
--- total, and a short ring buffer of recent sales for the "who bought what"
--- view. Old rows are folded into those buckets rather than thrown away.
steps[2] = function(d)
    for _, shop in pairs(d.shops or {}) do
        if not shop.daily then
            shop.daily  = {}
            shop.older  = { rev = 0, n = 0 }
            shop.byItem = {}
            shop.recent = {}
            for _, s in ipairs(shop.sales or {}) do
                -- v1/v2 wrote the day key as `stamp`; the others are only
                -- here in case a hand-edited save used a different name.
                -- `when` is deliberately last: it is a full clock string, so
                -- using it as a day key would scatter one day across many rows.
                local day = tostring(s.stamp or s.day or s.date or "?")
                local rev = math.floor(tonumber(s.total or s.rev or 0) or 0)
                local b = shop.daily[day]
                if not b then b = { rev = 0, n = 0 }; shop.daily[day] = b end
                b.rev, b.n = b.rev + rev, b.n + 1
                if s.ft then
                    local it = shop.byItem[s.ft]
                    if not it then it = { n = 0, rev = 0 }; shop.byItem[s.ft] = it end
                    it.n   = it.n + (tonumber(s.qty) or tonumber(s.q) or 1)
                    it.rev = it.rev + rev
                end
                if #shop.recent < 30 then table.insert(shop.recent, s) end
            end
            -- shop.sales is deliberately LEFT IN PLACE. It costs a little space
            -- until the next prune but means a rollback still has the detail.
            shop.salesLegacy = true
        end
        if shop.capacityKg == nil then shop.capacityKg = 20 end
        if shop.mode       == nil then shop.mode       = "auto" end
        if shop.orders     == nil then shop.orders     = {} end
        -- listings gain the row array if the v1->v2 step never saw them
        for _, e in ipairs(shop.items or {}) do
            if not e.units then
                local n = math.floor(tonumber(e.qty) or 0)
                e.units = (n > 0) and { { n = n } } or {}
            end
        end
    end
end

--- 3 -> 4 : admin buy-back depots arrive.
--- Purely additive. Depots live in their own containers and touch nothing that
--- already exists, so this step only has to make sure the containers are there
--- and the counters start at 1. A save that has never seen a depot migrates in
--- microseconds and every shop in it is untouched, which is the point.
steps[3] = function(d)
    if d.buyers       == nil then d.buyers       = {} end
    if d.buyGroups    == nil then d.buyGroups    = {} end
    if d.nextBuyGroup == nil then d.nextBuyGroup = 1  end
    if d.nextBuyEntry == nil then d.nextBuyEntry = 1  end
end

--============================================================ the ladder ====

--- Bring `d` up to CURRENT. Returns true when the DB is safe to write to.
function AkaShopSchema.apply(d)
    if type(d) ~= "table" then return false end

    local have = tonumber(d.schema)
    if have == nil then
        -- Either a brand new database or one written before versioning existed.
        -- An empty DB is new; a populated one is a v1 save and must be migrated
        -- rather than stamped as current, or its stock would keep the old shape.
        local populated = false
        for _ in pairs(d.shops or {}) do populated = true break end
        have = populated and 1 or AkaShopSchema.CURRENT
        d.schema = have
        log(populated and "unversioned save detected, treating as v1"
                       or ("fresh database, stamped v" .. have))
    end

    if have > AkaShopSchema.CURRENT then
        AkaShopSchema.locked  = true
        AkaShopSchema.lockMsg = string.format(
            "This save was written by Traka schema v%d but this build only " ..
            "understands v%d. Install the newer Traka again - your shops are " ..
            "intact and untouched.", have, AkaShopSchema.CURRENT)
        log("LOCKED: " .. AkaShopSchema.lockMsg)
        return false
    end

    if have == AkaShopSchema.CURRENT then
        -- clean boot on the current schema: last update went fine, release the
        -- safety copy so it is not carried in memory and in the save forever
        if d._bak then
            log("previous migration verified, dropping backup from v" ..
                tostring(d._bakFrom))
            d._bak, d._bakFrom, d._bakAt = nil, nil, nil
        end
        return true
    end

    log(string.format("migrating v%d -> v%d", have, AkaShopSchema.CURRENT))
    d._bak     = deep(d.shops or {})
    d._bakFrom = have
    d._bakAt   = AkaShop and AkaShop.clockString and AkaShop.clockString() or "?"
    log("backup taken: " .. tostring(d._bakFrom))

    while have < AkaShopSchema.CURRENT do
        local step = steps[have]
        if not step then
            log("no migration step from v" .. have .. " - stopping here")
            break
        end
        local ok, err = pcall(step, d)
        if not ok then
            AkaShopSchema.locked  = true
            AkaShopSchema.lockMsg = "Migration from v" .. have ..
                " failed: " .. tostring(err) ..
                ". Your data has NOT been changed - see console.txt."
            log("FAILED: " .. tostring(err))
            d.shops = deep(d._bak)          -- put it back exactly as it was
            return false
        end
        have = have + 1
        d.schema = have
        log("now at v" .. have)
    end

    return true
end

--- Restore the pre-migration snapshot. Only reachable by hand from the admin
--- console, deliberately: it is a recovery tool, not something to click.
function AkaShopSchema.rollback(d)
    if not d or not d._bak then return false, "No backup stored." end
    d.shops  = deep(d._bak)
    d.schema = d._bakFrom
    log("rolled back to v" .. tostring(d._bakFrom))
    return true, "Restored the snapshot taken before the last migration."
end

--- Human-readable state for the admin panel.
function AkaShopSchema.status(d)
    return {
        schema  = d and d.schema or nil,
        current = AkaShopSchema.CURRENT,
        locked  = AkaShopSchema.locked,
        message = AkaShopSchema.lockMsg,
        backup  = d and d._bak ~= nil or false,
    }
end
