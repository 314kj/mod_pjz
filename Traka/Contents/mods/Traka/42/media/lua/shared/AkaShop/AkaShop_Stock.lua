--[[===========================================================================
    AkaShop - stock rows: real item condition without a table per item.

    A listing is one item type at one base price. Under it sits `units`, an
    array of rows, each row being "n items that share exactly this state":

        { n=100 }                            100 nails, no state at all
        { n=2, cond=10, condMax=10 }         two pristine axes
        { n=4, age=12, cooked=false, frozen=true }

    Items with no state collapse to a single row no matter how many there are,
    which is what keeps a box of nails from becoming a thousand tables. Items
    with state split by state, and the state we record is deliberately COARSE:

      * cond  - getCondition() is already an integer 0..conditionMax (usually
                10), so it can never produce more than ~11 rows on its own.
      * uses  - drainables quantised to 5% steps, so at most 21 values.
      * age   - rounded to whole in-game hours.
      * invHeat is NOT recorded. It is a float that moves every tick, so two
        steaks put in three seconds apart would never share a row and the whole
        scheme would collapse. It also re-equilibrates within seconds of coming
        back out, so nothing is really lost. Items leave at room temperature,
        except that a frozen item comes back frozen.

    On top of that there is a hard cap of MAX_ROWS per listing. When it is hit,
    the two closest rows merge and the survivor takes the WORSE of the two
    values. The shop loses a sliver of value; the customer is never handed
    something worse than the row they were shown.
============================================================================]]

AkaShopStock = AkaShopStock or {}
local S = AkaShopStock

S.MAX_ROWS   = 24      -- rows per listing before merging kicks in
S.USES_STEPS = 20      -- drainables quantised to 1/20 = 5%
S.COND_FLOOR = 0.25    -- a wrecked item still fetches this share of the price

--==================================================== reading an item's state

local function q(v, steps)
    if type(v) ~= "number" then return nil end
    return math.floor(v * steps + 0.5) / steps
end

--- Read one no-argument getter, but only if the item really has it.
---
--- LOOK BEFORE YOU CALL. Wrapping a missing method in pcall does stop the error
--- reaching the player, but Kahlua still builds the exception and dumps a full
--- Java stack trace to console.txt first. An apple has no getUsedDelta, so
--- depositing a crate of apples wrote 192 stack traces in a single session -
--- caught, harmless, and pure cost. One type check removes all of them.
local function get(item, name)
    if type(item[name]) ~= "function" then return nil end
    local ok, v = pcall(function() return item[name](item) end)
    if ok then return v end
    return nil
end

--- Snapshot the parts of an InventoryItem worth carrying through the shop.
--- An item type that lacks a getter must not break a deposit; it just stores
--- less detail.
function S.stateOf(item)
    if not item then return {} end
    local st = {}

    local c  = get(item, "getCondition")
    local cm = get(item, "getConditionMax")
    if type(c) == "number" and type(cm) == "number" and cm > 0 and c < cm then
        st.cond, st.condMax = math.floor(c), math.floor(cm)
    end

    local ud = get(item, "getUsedDelta")
    if type(ud) == "number" and ud < 0.999 then
        st.uses = q(ud, S.USES_STEPS)
    end

    local age = get(item, "getAge")
    if type(age) == "number" and age > 0 then
        st.age = math.floor(age + 0.5)          -- whole in-game hours
    end

    if get(item, "isCooked") == true then st.cooked = true end
    if get(item, "isFrozen") == true then st.frozen = true end

    return st
end

--- In-game hours since the world began. Used only to age stored food; it is
--- deliberately NOT part of keyOf, or two deposits a minute apart would never
--- share a row and the whole collapsing scheme would fall over.
function S.worldHours()
    local h
    if pcall(function() h = getGameTime():getWorldAgeHours() end)
       and type(h) == "number" then return h end
    return 0
end

--- Stable identity for a state. Two items sharing this key share a row.
function S.keyOf(st)
    if not st then return "-" end
    return table.concat({
        st.cond or "", st.condMax or "", st.uses or "",
        st.age or "", st.cooked and 1 or "", st.frozen and 1 or "",
    }, "|")
end

--- Push a stored state back onto a freshly created item.
---
--- A shop is a stasis box: an item comes out in EXACTLY the state it went in.
--- There used to be an option that added the time spent in stock to the item's
--- age on the way out. It is gone, and deliberately so:
---   * the age it added was measured against the world clock, which is hundreds
---     of hours old on any established save, so a single bad path turned fresh
---     food instantly rotten rather than slightly older;
---   * it ignored the frozen flag, so frozen food rotted in a freezer;
---   * and "ages while stored" was a lie either way - nothing ticks on data,
---     the whole catch-up landed in one jump at the moment of withdrawal.
--- Keeping the recorded age untouched is both simpler and honest.
--- Same look-before-you-call rule as `get` above: a setter the item does not
--- have costs a Java stack trace per call otherwise, and the shop hands over
--- items in batches.
local function set(item, name, v)
    if type(item[name]) ~= "function" then return end
    pcall(function() item[name](item, v) end)
end

function S.applyState(item, st)
    if not item or not st then return item end
    if st.cond   then set(item, "setCondition", st.cond) end
    if st.uses   then set(item, "setUsedDelta", st.uses) end
    if st.age    then set(item, "setAge",       st.age)  end
    if st.cooked then set(item, "setCooked",    true)    end
    if st.frozen then set(item, "setFrozen",    true)    end
    return item
end

--=========================================================== row arithmetic ==

function S.total(entry)
    local n = 0
    for _, r in ipairs(entry and entry.units or {}) do n = n + (r.n or 0) end
    return n
end

--- How bad is this row, 0 (perfect) .. 1 (ruined). Used for ordering, merging
--- and pricing, so every one of those agrees on what "worse" means.
function S.wear(r)
    local w = 0
    if r.cond and r.condMax and r.condMax > 0 then
        w = math.max(w, 1 - (r.cond / r.condMax))
    end
    if r.uses then w = math.max(w, 1 - r.uses) end
    return w
end

--- Merge b into a, keeping the worse of every value.
--- Fold b into a, keeping the WORSE of every value.
---
--- Exposed because the hand-over has to collapse buckets too: see the cap in
--- AkaShop.removeItemsWithState. One definition of "worse" for the whole mod -
--- two would drift, and the day they disagree is the day a shop quietly values
--- a ruined item as a good one.
function S.mergeInto(a, b)
    a.n = (a.n or 0) + (b.n or 0)
    if b.cond and (not a.cond or b.cond < a.cond) then
        a.cond, a.condMax = b.cond, b.condMax or a.condMax
    end
    if b.uses and (not a.uses or b.uses < a.uses) then a.uses = b.uses end
    if b.age  and (not a.age  or b.age  > a.age)  then a.age  = b.age  end
    if b.at   and (not a.at   or b.at   < a.at)   then a.at   = b.at   end  -- oldest wins
    if b.cooked ~= a.cooked then a.cooked = nil end     -- ambiguous -> plain
    if not b.frozen then a.frozen = nil end             -- only frozen if all are
    if b.price and (not a.price or b.price < a.price) then a.price = b.price end
end

--- Drop empty rows, fold duplicates together and enforce MAX_ROWS.
function S.normalise(entry)
    local seen, out = {}, {}
    for _, r in ipairs(entry.units or {}) do
        if (r.n or 0) > 0 then
            local k = S.keyOf(r)
            if seen[k] then
                seen[k].n = seen[k].n + r.n
                if r.price and not seen[k].price then seen[k].price = r.price end
            else
                seen[k] = r
                table.insert(out, r)
            end
        end
    end

    -- worst first, so the cheapest stock is what sells and what merges
    table.sort(out, function(x, y)
        local wx, wy = S.wear(x), S.wear(y)
        if wx ~= wy then return wx > wy end
        return (x.age or 0) > (y.age or 0)
    end)

    while #out > S.MAX_ROWS do
        -- collapse the closest neighbouring pair; the list is already ordered
        -- by wear so neighbours are by definition the most similar
        local bi, bd = 1, math.huge
        for i = 1, #out - 1 do
            local dd = math.abs(S.wear(out[i]) - S.wear(out[i + 1]))
                     + math.abs((out[i].age or 0) - (out[i + 1].age or 0)) / 1000
            if dd < bd then bi, bd = i, dd end
        end
        S.mergeInto(out[bi], out[bi + 1])
        table.remove(out, bi + 1)
    end

    entry.units = out
    entry.qty   = S.total(entry)      -- kept in sync so older code still reads sane
    return entry
end

--- Fold a list of raw states into rows and add them to the listing.
function S.add(entry, states)
    entry.units = entry.units or {}
    for _, st in ipairs(states or {}) do
        local n = math.floor(st.n or 1)
        if n > 0 then
            local row = { n = n, at = st.at or S.worldHours() }
            for _, f in ipairs({"cond","condMax","uses","age","cooked","frozen"}) do
                row[f] = st[f]
            end
            table.insert(entry.units, row)
        end
    end
    return S.normalise(entry)
end

--- Remove `want` units, worst condition first, and return what was taken as
--- state descriptors ready to be turned back into real items.
function S.take(entry, want)
    local out, left = {}, math.floor(want or 0)
    local rows = entry.units or {}
    for i = 1, #rows do
        if left <= 0 then break end
        local r = rows[i]
        local n = math.min(r.n or 0, left)
        if n > 0 then
            local st = { n = n, at = r.at }
            for _, f in ipairs({"cond","condMax","uses","age","cooked","frozen"}) do
                st[f] = r[f]
            end
            table.insert(out, st)
            r.n  = r.n - n
            left = left - n
        end
    end
    S.normalise(entry)
    return out, (math.floor(want or 0) - left)
end

--============================================================== pricing =====

--- Price for one unit of a row.
--- The owner sets ONE price, for the item in perfect shape, and worn stock is
--- discounted from it automatically. Setting a price per row by hand is still
--- possible (row.price wins) but nobody has to: a listing that splits into
--- eight rows would otherwise mean eight prices to maintain by hand every time
--- stock comes in. Age is shown but never priced -- rot is the buyer's call.
function S.priceOf(entry, row)
    if row and row.price then return math.max(0, math.floor(row.price)) end
    local p = math.max(0, math.floor(entry.price or 0))
    if not row then return p end
    local w = S.wear(row)
    if w <= 0 then return p end
    local f = S.COND_FLOOR + (1 - S.COND_FLOOR) * (1 - w)
    return math.max(0, math.floor(p * f + 0.5))
end

--- Cheapest-first cost of buying `want` units, matching the order S.take uses
--- so the quote and the goods can never disagree.
function S.quote(entry, want)
    local left, cost, lines = math.floor(want or 0), 0, {}
    for _, r in ipairs(entry.units or {}) do
        if left <= 0 then break end
        local n = math.min(r.n or 0, left)
        if n > 0 then
            local unit = S.priceOf(entry, r)
            cost = cost + unit * n
            table.insert(lines, { n = n, unit = unit, wear = S.wear(r) })
            left = left - n
        end
    end
    return cost, lines, (math.floor(want or 0) - left)
end

--- Same walk as S.quote, but over the trimmed rows a client gets in a
--- snapshot (each already carrying its own `unit` price). The buy window MUST
--- price a cart with this and not with the listing's base price: worn stock is
--- discounted per row, so base-price maths would disagree with the server's
--- quote and every purchase would bounce off the "prices changed" guard.
function S.quoteRows(rows, want)
    local left, cost = math.floor(want or 0), 0
    for _, r in ipairs(rows or {}) do
        if left <= 0 then break end
        local n = math.min(r.n or 0, left)
        if n > 0 then
            cost = cost + (r.unit or 0) * n
            left = left - n
        end
    end
    return cost, (math.floor(want or 0) - left)
end

--============================================================== weight ======

local weightCache = {}

--- Weight of one unit of `ft`, cached: FindItem is a script lookup and this is
--- called per row while totalling a shop.
function S.weightOf(ft)
    local w = weightCache[ft]
    if w ~= nil then return w end
    w = 0
    pcall(function()
        local si = getScriptManager():FindItem(ft)
        if si then w = si:getActualWeight() or si:getWeight() or 0 end
    end)
    if type(w) ~= "number" then w = 0 end
    weightCache[ft] = w
    return w
end

function S.shopWeight(shop)
    local t = 0
    for _, e in ipairs(shop and shop.items or {}) do
        t = t + S.weightOf(e.ft) * S.total(e)
    end
    return t
end
