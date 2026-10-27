--[[===========================================================================
    Traka - admin buy-back depots.

    A depot is the mirror image of a shop. A shop is owned by a player, holds
    real goods taken from that player, and sells them. A depot belongs to the
    server, holds nothing at all, and BUYS: the admin says "I will pay 40 for a
    hammer, up to fifty of them, once an hour each", the money is conjured, and
    the hammer is destroyed. It is how a server drains an item it wants fewer of
    and puts currency into players' hands for doing it.

    WHY EVERY DEPOT BELONGS TO A GROUP, even a lonely one.

    Depots can be linked so several counters around the map offer the same deal
    and draw down the same quota. The obvious implementation - each depot owns
    its list, linked depots hold a pointer to a "master" - has a nasty edge:
    delete the master and the others are holding a dangling pointer, and every
    read has to ask "am I a master or a follower" before it can do anything.

    So there are no masters. A depot owns nothing but its coordinates and a
    group id, and the list, the quota and the offer clocks always live on the
    group. A standalone depot is simply the only member of its group. Linking is
    "join that group"; unlinking is "start a fresh group with a copy of the
    list". Deleting a depot never destroys a list unless it was the last member.
    Every read is the same read, whether one depot or ten share it.

    LIMITED-TIME OFFERS, NOT PLAYER COOLDOWNS.

    An earlier version made the clock a brake on the player: sell one, wait an
    hour. That is the opposite of what a depot is for. The clock now belongs to
    the OFFER: "I am paying 240 for an axe, for the next sixty minutes." It
    pushes players to hurry rather than telling them to go away, and a server
    can run an evening event out of it.

    An offer that has run out of time, or run out of quota, is DELETED. Not
    greyed out, not kept for the admin to tidy up later - gone from the list the
    moment it stops being true. A board that still shows a deal you cannot take
    is a board players stop trusting.

    PAYING IN GOODS (v3.6.0).

    An offer may pay in an ITEM instead of money: twenty handfuls of grass for
    one tin of dog food. That needs two numbers, not one, because barter has a
    denominator - "one dog food" is not a price per handful, it is a price per
    twenty of them. So a bartering row carries a LOT (how many of the wanted
    item make one trade) and a PAYOUT (how many of the paid item come back per
    lot). Money rows are simply lot 1 with no payout item, which is why nothing
    in the old save has to change.

    The lot is also the reason the hand-over became all-or-nothing. Paying per
    item, a player who came up short just got paid less. Paying per lot, a
    player who hands over nineteen of the twenty has given the depot nineteen
    handfuls of grass in exchange for nothing at all - the items are destroyed
    at a depot, so there is nothing to give back. A lot-based sale therefore
    takes everything or takes nothing.
============================================================================]]

AkaShopBuy = AkaShopBuy or {}
local B = AkaShopBuy

B.MAX_ENTRIES  = 30        -- rows per depot group
B.MAX_DEPOTS   = 60        -- depots on the whole server
B.MAX_PRICE    = 9999999
B.MAX_QTY      = 999999
B.UNLIMITED    = -1        -- qty value meaning "never runs out"
B.MAX_MINUTES  = 60 * 24 * 7      -- a week is as long as an "offer" means anything
B.MAX_PAY      = 9999      -- items handed back per lot
B.MAX_LOT      = 9999      -- items the player hands over per lot

--- The most items one transaction may ever cause to be BUILT.
---
--- Currency is an item. A sale worth fifty thousand is fifty thousand
--- instanceItem calls on one frame, and the game stops dead while they happen.
--- The client paces its own bulk sales into small batches, but the client is
--- the one side that can be old, modded or lying, so the ceiling lives here as
--- well. Over it, the sale is simply made smaller and the rest waits for the
--- next request - nothing is refused and nothing is lost.
B.MAX_PAYOUT   = 2000

--- Real-world seconds. An offer's clock follows the wall clock for the same
--- reason trading hours do: "buying these for the next hour" has to mean an
--- hour to the player, and one in-game hour is about two and a half real
--- minutes at the default day length - nobody could get there in time.
local function nowSec()
    local t
    if pcall(function() t = getTimestamp() end) and type(t) == "number" then return t end
    if pcall(function() t = getTimestampMs() end) and type(t) == "number" then
        return math.floor(t / 1000)
    end
    return 0
end
B.nowSec = nowSec

--=================================================================== store ==

local function db() return AkaShopCore.db() end

--- Containers are only ever ADDED, never assigned over. Same rule as the shop
--- table: one careless `d.buyers = {}` is how a server loses everything.
local function store()
    local d = db()
    if not d.buyers        then d.buyers        = {} end
    if not d.buyGroups     then d.buyGroups     = {} end
    if not d.nextBuyGroup  then d.nextBuyGroup  = 1  end
    if not d.nextBuyEntry  then d.nextBuyEntry  = 1  end
    return d
end
B.store = store

function B.get(key)   return store().buyers[key] end
function B.group(gid) return store().buyGroups[gid] end

--- The group a depot reads from. Nil only if the data was hand-edited.
function B.groupOf(key)
    local p = B.get(key)
    if not p then return nil end
    return store().buyGroups[p.group]
end

local function newGroup(name, nameTH)
    local d = store()
    local id = d.nextBuyGroup
    d.nextBuyGroup = id + 1
    d.buyGroups[id] = { id = id, name = name or "Depot",
                        nameTH = nameTH or "", entries = {} }
    return id
end

--- Drop a group once its last depot leaves, so the save does not accumulate
--- orphaned price lists nobody can reach.
local function dropGroupIfEmpty(gid)
    local d = store()
    if not d.buyGroups[gid] then return end
    for _, p in pairs(d.buyers) do
        if p.group == gid then return end
    end
    d.buyGroups[gid] = nil
end

--============================================================ depot admin ===

function B.count()
    local n = 0
    for _ in pairs(store().buyers) do n = n + 1 end
    return n
end

--- Create a depot. Admin-gated by the caller.
function B.create(x, y, z, sprite, name, nameTH)
    local d = store()
    local key = AkaShop.key(x, y, z)
    if d.buyers[key] then return false, "There is already a depot on that tile." end
    if AkaShopCore.getShop(key) then
        return false, "That tile is already a player shop. One role per tile."
    end
    if B.count() >= B.MAX_DEPOTS then
        return false, "The server already has the maximum of " .. B.MAX_DEPOTS .. " depots."
    end

    local names = AkaShop.pairNames(name, nameTH, "Buying Depot")
    local gid = newGroup(names.en, names.th)
    d.buyers[key] = {
        key = key,
        x = math.floor(x), y = math.floor(y), z = math.floor(z or 0),
        sprite = sprite or "",
        group = gid,
        created = AkaShop.clockString(),
    }
    return true, "Depot created: " .. AkaShop.shopName(d.buyGroups[gid])
end

--- Shut a buying point without dismantling it.
---
--- Until now the only way to stop a depot buying was to delete it, which threw
--- away the price list and the remaining quota with it - so "we buy scrap this
--- weekend only" meant rebuilding the whole board every Friday. Closed is a
--- state, not a demolition.
---
--- Per DEPOT, not per group: a chain of four counters where one sits in a town
--- nobody visits should be closable on its own.
function B.setEnabled(key, on)
    local p = B.get(key)
    if not p then return false, "No depot there." end
    p.enabled = on and true or false
    local g = B.groupOf(key)
    return true, AkaShop.shopName(g) .. (p.enabled and " is open again."
                                                    or " is closed. It buys nothing until you reopen it.")
end

--- Absent means open. Depots created before this existed have no flag at all,
--- and a counter that silently stopped buying after an update would be a
--- worse bug than the one this fixes.
function B.isEnabled(key)
    local p = B.get(key)
    if not p then return false end
    return p.enabled ~= false
end

function B.remove(key)
    local d = store()
    local p = d.buyers[key]
    if not p then return false, "No depot there." end
    local gid = p.group
    d.buyers[key] = nil
    dropGroupIfEmpty(gid)
    return true, "Depot removed."
end

function B.rename(key, name, nameTH)
    local g = B.groupOf(key)
    if not g then return false, "No depot there." end
    local names = AkaShop.pairNames(name, nameTH, g.name or "Buying Depot")
    g.name, g.nameTH = names.en, names.th
    return true, "Renamed to " .. AkaShop.shopName(g)
end

--- Join the group `otherKey` reads from. The list, the remaining quota and the
--- offer clocks are all shared from this moment - that is the whole point.
function B.link(key, otherKey)
    local d = store()
    local a, b = d.buyers[key], d.buyers[otherKey]
    if not a then return false, "No depot there." end
    if not b then return false, "The depot you picked no longer exists." end
    if a.group == b.group then return false, "Those two are already linked." end

    local old = a.group
    a.group = b.group
    dropGroupIfEmpty(old)
    return true, "Linked to " .. AkaShop.shopName(d.buyGroups[b.group]) ..
                 ". They now share one list, one quota and one clock."
end

--- Leave the group with a COPY of the list. Copying rather than starting empty
--- is the kinder default: unlinking a depot you set up an hour ago should not
--- silently wipe the deal it was offering. The copy is exact - same remaining
--- quota, same deadline - because unlinking is a bookkeeping change, not a new
--- promise to the players standing at the counter.
function B.unlink(key)
    local d = store()
    local p = d.buyers[key]
    if not p then return false, "No depot there." end

    local shared = false
    for k, other in pairs(d.buyers) do
        if k ~= key and other.group == p.group then shared = true break end
    end
    if not shared then return false, "This depot is not linked to anything." end

    local src = d.buyGroups[p.group]
    local gid = newGroup(src and src.name, src and src.nameTH)
    local dst = d.buyGroups[gid]
    for _, e in ipairs(src and src.entries or {}) do
        table.insert(dst.entries, {
            uid = e.uid, ft = e.ft, name = e.name, price = e.price,
            qty = e.qty,
            -- endsAt is copied, not restarted: unlinking a depot must not
            -- quietly hand a five-minute flash sale another full hour.
            endsAt = e.endsAt, colour = e.colour,
        })
    end
    p.group = gid
    return true, "Unlinked. This depot now has its own copy of the list; " ..
                 "changes here no longer affect the others."
end

--- Every group that has at least one depot, for the admin's link picker.
function B.groupList()
    local d, out = store(), {}
    for gid, g in pairs(d.buyGroups) do
        local n, first = 0, nil
        for k, p in pairs(d.buyers) do
            if p.group == gid then n = n + 1; first = first or k end
        end
        if n > 0 then
            table.insert(out, { gid = gid, key = first, n = n,
                                name = g.name, nameTH = g.nameTH,
                                rows = #(g.entries or {}) })
        end
    end
    table.sort(out, function(x, y) return (x.name or "") < (y.name or "") end)
    return out
end

--============================================================== entries =====

local function findEntry(g, uid)
    for i, e in ipairs(g.entries or {}) do
        if e.uid == uid then return e, i end
    end
    return nil
end
B.findEntry = findEntry

--============================================================== bartering ===

--- How many of the wanted item make one trade. Absent means one, which is
--- every row written before v3.6.0 and every money row since.
function B.lotOf(e)  return math.max(1, math.floor((e and e.lot) or 1)) end
function B.payNOf(e) return math.max(1, math.floor((e and e.payN) or 1)) end

--- Is this row paid in goods rather than money?
function B.isBarter(e) return type(e) == "table" and type(e.payFt) == "string"
                              and e.payFt ~= "" end

--- Read an admin's barter settings into the three fields an entry stores, or
--- into three nils meaning "pay money as usual".
---
--- A pack cannot be the PAYOUT. A pack is a question - "any ring" - and a
--- payout has to be an answer, because the server has to build a specific item
--- and hand it over. Wanting any ring is sensible; paying out any ring is not.
local function readPay(pay)
    if type(pay) ~= "table" then return nil, nil, nil, nil end
    local ft = pay.ft
    if type(ft) ~= "string" or ft == "" then return nil, nil, nil, nil end
    if AkaShopPacks.idOf(ft) then
        return nil, nil, nil, "A pack cannot be the payment - pick one real item."
    end
    local sm = getScriptManager()
    if not (sm and sm:FindItem(ft)) then
        return nil, nil, nil, "There is no item called " .. tostring(ft) .. "."
    end
    local n   = AkaShop.clampInt(tonumber(pay.n)   or 1, 1, B.MAX_PAY)
    local lot = AkaShop.clampInt(tonumber(pay.lot) or 1, 1, B.MAX_LOT)
    return ft, n, lot, nil
end

function B.addEntry(key, ft, price, qty, minutes, colour, pay)
    local g = B.groupOf(key)
    if not g then return false, "No depot there." end
    if #g.entries >= B.MAX_ENTRIES then
        return false, "This depot already lists the maximum of " .. B.MAX_ENTRIES .. " items."
    end
    if type(ft) ~= "string" or ft == "" then return false, "No item chosen." end

    -- A pack sits in `ft` behind a reserved prefix, so the duplicate check
    -- below and every other "which row is this" lookup keeps working without
    -- knowing packs exist.
    local packId = AkaShopPacks.idOf(ft)
    local rowName
    if packId then
        local pk = AkaShopPacks.get(packId)
        if not pk or pk.n < 1 then
            return false, "That pack matches no items on this server."
        end
        rowName = pk.name
    else
        local sm = getScriptManager()
        if not (sm and sm:FindItem(ft)) then
            return false, "There is no item called " .. tostring(ft) .. "."
        end
        rowName = AkaShop.displayNameOf(ft)
    end

    for _, e in ipairs(g.entries) do
        if e.ft == ft then return false, "That item is already on the list." end
    end

    price = AkaShop.clampInt(tonumber(price) or 0, 0, B.MAX_PRICE)

    qty = tonumber(qty)
    if qty == nil or qty < 0 then qty = B.UNLIMITED
    else qty = AkaShop.clampInt(qty, 0, B.MAX_QTY) end

    minutes = AkaShop.clampInt(tonumber(minutes) or 0, 0, B.MAX_MINUTES)
    colour  = AkaShop.clampInt(tonumber(colour) or 1, 1, #AkaShop.CARD_COLOURS)

    local payFt, payN, lot, payErr = readPay(pay)
    if payErr then return false, payErr end

    local d = store()
    local uid = d.nextBuyEntry
    d.nextBuyEntry = uid + 1

    table.insert(g.entries, {
        uid = uid, ft = ft, name = rowName,
        pack = packId,                       -- nil for an ordinary item row
        price = price, qty = qty,
        -- Absent on every money row, which is what every pre-3.6 save has.
        payFt = payFt, payN = payN, lot = lot,
        -- endsAt is an ABSOLUTE second, not a duration. Storing "60 minutes"
        -- would restart the countdown every time the server rebooted.
        endsAt = (minutes > 0) and (nowSec() + minutes * 60) or 0,
        colour = colour,
    })

    local how = payFt
        and (" at " .. AkaShop.rateText(lot, payN, AkaShop.displayNameOf(payFt)))
        or  ""
    return true, (minutes > 0)
        and ("Now buying " .. rowName .. how .. " for the next " ..
             AkaShop.durationText(minutes * 60) .. ".")
        or  ("Now buying " .. rowName .. how .. ".")
end

function B.delEntry(key, uid)
    local g = B.groupOf(key)
    if not g then return false, "No depot there." end
    local e, i = findEntry(g, tonumber(uid))
    if not e then return false, "That item is not on the list." end
    table.remove(g.entries, i)
    return true, "Stopped buying " .. tostring(e.name) .. "."
end

--- Edit one field of one row. Kept as a single entry point so the network layer
--- never has to know the shape of an entry.
function B.setEntry(key, uid, field, value)
    local g = B.groupOf(key)
    if not g then return false, "No depot there." end
    local e = findEntry(g, tonumber(uid))
    if not e then return false, "That item is not on the list." end

    if field == "price" then
        e.price = AkaShop.clampInt(tonumber(value) or 0, 0, B.MAX_PRICE)
        return true, "Price set to " .. AkaShop.money(e.price) .. "."

    elseif field == "qty" then
        local q = tonumber(value)
        if q == nil or q < 0 then
            e.qty = B.UNLIMITED
            return true, "Quantity set to unlimited."
        end
        e.qty = AkaShop.clampInt(q, 0, B.MAX_QTY)
        return true, "Quantity set to " .. e.qty .. "."

    elseif field == "minutes" then
        local m = AkaShop.clampInt(tonumber(value) or 0, 0, B.MAX_MINUTES)
        e.endsAt = (m > 0) and (nowSec() + m * 60) or 0
        return true, (m > 0)
            and ("Buying this for the next " .. AkaShop.durationText(m * 60) .. ".")
            or  "This offer no longer expires."

    elseif field == "colour" then
        e.colour = AkaShop.clampInt(tonumber(value) or 1, 1, #AkaShop.CARD_COLOURS)
        return true, "Card colour set to " .. (AkaShop.cardColour(e.colour)[4]) .. "."

    -- The three barter fields arrive together, as one edit, because a rate is
    -- only meaningful as a whole. Sending them one at a time would leave the
    -- row briefly saying "20 handfuls of grass for 1 money", which is a deal
    -- somebody would take.
    elseif field == "pay" then
        if type(value) ~= "table" or type(value.ft) ~= "string" or value.ft == "" then
            e.payFt, e.payN, e.lot = nil, nil, nil
            return true, "This offer pays in " .. AkaShop.getCurrencyName() .. " again."
        end
        local payFt, payN, lot, err = readPay(value)
        if err then return false, err end
        e.payFt, e.payN, e.lot = payFt, payN, lot
        return true, "Now trading " ..
               AkaShop.rateText(lot, payN, AkaShop.displayNameOf(payFt)) .. "."
    end
    return false, "Unknown field."
end

--========================================================== time and prune ==

--- Seconds this offer has left. 0 means "does not expire"; a negative result is
--- normalised to -1, which is the signal that it is finished.
function B.timeLeft(e)
    local ends = math.floor(e.endsAt or 0)
    if ends <= 0 then return 0 end
    local left = ends - nowSec()
    if left <= 0 then return -1 end
    return left
end

--- True once an offer has stopped being true: out of time, or out of quota.
function B.finished(e)
    if B.timeLeft(e) < 0 then return true end
    if e.qty ~= B.UNLIMITED and math.floor(e.qty or 0) <= 0 then return true end
    return false
end

--- Delete every finished offer from a group. Returns how many went.
---
--- Called on every read, not on a timer. A timer would leave a dead offer on
--- the board for up to a minute, and "it let me click Sell then said no" is a
--- worse bug than a slightly slower snapshot. The list is at most 30 rows.
function B.prune(g)
    if not g or not g.entries then return 0 end
    local gone = 0
    for i = #g.entries, 1, -1 do
        if B.finished(g.entries[i]) then
            table.remove(g.entries, i)
            gone = gone + 1
        end
    end
    return gone
end

--- Prune every group. Cheap enough to run whenever the index is pushed.
function B.pruneAll()
    local d, gone = store(), 0
    for _, g in pairs(d.buyGroups or {}) do gone = gone + B.prune(g) end
    return gone
end

--============================================================== snapshot ====

--- What one client is allowed to see about a depot.
function B.snapshot(key, username, admin)
    local d = store()
    local p = d.buyers[key]
    if not p then return nil end
    local g = d.buyGroups[p.group]
    if not g then return nil end

    local linked = 0
    for _, o in pairs(d.buyers) do if o.group == p.group then linked = linked + 1 end end

    B.prune(g)

    local rows = {}
    for _, e in ipairs(g.entries) do
        local left = B.timeLeft(e)
        table.insert(rows, {
            uid = e.uid, ft = e.ft, name = e.name or AkaShop.displayNameOf(e.ft),
            -- The client rebuilds pack membership from its own script manager
            -- rather than being sent fourteen fullTypes per row. Both sides
            -- read the same scripts, and the server re-checks membership when
            -- the sale actually happens, so a disagreeing client gains nothing.
            pack = e.pack,
            price = e.price or 0,
            -- Barter. payFt absent means this row pays money, which is what
            -- every row in a save written before v3.6.0 says.
            payFt   = e.payFt,
            payName = e.payFt and AkaShop.displayNameOf(e.payFt) or nil,
            payN    = e.payFt and B.payNOf(e) or nil,
            lot     = B.lotOf(e),
            qty = e.qty,                       -- -1 = unlimited
            left = left,                       -- 0 = never expires
            special = left > 0,
            colour = e.colour or 1,
        })
    end

    return {
        key = key, x = p.x, y = p.y, z = p.z,
        name = g.name, nameTH = g.nameTH,
        enabled = p.enabled ~= false,
        group = p.group, linked = linked,
        admin = admin and true or false,
        currency = AkaShop.getCurrencyName(),
        rows = rows,
        groups = admin and B.groupList() or nil,
    }
end

--- Depots for the world map and the admin teleport list.
function B.index()
    local d, out = store(), {}
    B.pruneAll()
    for key, p in pairs(d.buyers) do
        local g = d.buyGroups[p.group]
        out[key] = {
            key = key, x = p.x, y = p.y, z = p.z, sprite = p.sprite or "",
            name = g and g.name or "Depot", nameTH = g and g.nameTH or "",
            enabled = p.enabled ~= false,
            group = p.group, rows = g and #(g.entries or {}) or 0,
        }
    end
    return out
end

--============================================================== selling =====

--- Phase 1: check everything, RESERVE the quota, then ask the client to hand
--- the goods over. Reserving up front is deliberate: two
--- players clicking Sell in the same second must not both pass a quota check
--- that only one of them can actually satisfy. Whatever is not delivered comes
--- back in commitSell.
--- `offerFt` is the concrete item the client says it will hand over. It only
--- matters for a pack row, where the server cannot know which of fourteen
--- rings the seller is actually carrying. The client CHOOSES; the server
--- VERIFIES the choice is in the pack. A tampered client can pick an awkward
--- member, never a member that is not there.
function B.beginSell(key, player, username, uid, want, admin, offerFt)
    local p = B.get(key)
    if not p then return false, "There is no depot here." end
    if p.enabled == false then
        return false, "This buying point is closed right now."
    end
    if not AkaShopCore.near(player, p.x, p.y, p.z, admin) then
        return false, "You are too far from the depot."
    end
    local g = B.groupOf(key)
    if not g then return false, "This depot has no list." end

    B.prune(g)

    local e = findEntry(g, tonumber(uid))
    if not e then return false, "That item is not being bought here any more." end

    local takeFt = e.ft
    if e.pack then
        if type(offerFt) ~= "string" or offerFt == "" then
            return false, "Nothing of that kind on you."
        end
        if not AkaShopPacks.contains(e.pack, offerFt) then
            return false, "That is not something " .. tostring(e.name) .. " accepts."
        end
        takeFt = offerFt
    end

    -- Round down to whole trades. On a money row the lot is 1 and this is the
    -- identity, which is why the two kinds of row share one path.
    local lot = B.lotOf(e)
    want = AkaShop.clampInt(tonumber(want) or 0, 1, 10000)
    want = math.floor(want / lot) * lot
    if want < lot then
        return false, "This deal trades " .. lot .. " at a time - you need " ..
                      lot .. " x " .. tostring(e.name) .. "."
    end

    -- Cap the SIZE OF THE PAYOUT, not the size of the sale. See B.MAX_PAYOUT.
    -- Always leaves at least one whole trade, because one trade is the smallest
    -- thing that can happen and refusing it outright would be a depot that
    -- pays so well nobody can sell to it.
    local perTrade = B.isBarter(e) and B.payNOf(e)
                                   or (math.floor(e.price or 0) * lot)
    if perTrade > 0 then
        local maxTrades = math.floor(B.MAX_PAYOUT / perTrade)
        if maxTrades < 1 then maxTrades = 1 end
        local ceiling = maxTrades * lot
        if want > ceiling then want = ceiling end
    end

    if e.qty ~= B.UNLIMITED then
        local have = math.floor(e.qty or 0)
        if have <= 0 then return false, "That item is fully bought up." end
        if want > have then want = math.floor(have / lot) * lot end
        if want < lot then
            return false, "There is not enough left in this offer for a full trade."
        end
        e.qty = have - want                      -- reserve now, refund later
    end

    -- The whole rate travels with the transaction. The row can be pruned out of
    -- existence between the reservation and the confirmation - that is exactly
    -- what happens when a sale takes the last of the quota - and the player
    -- must still be paid what they were promised when they clicked.
    local txn = AkaShopCore.openTxn("depot_sell", username, key,
                                    { uid = e.uid, ft = takeFt, count = want,
                                      price = e.price or 0,
                                      payFt = e.payFt, payN = B.payNOf(e),
                                      lot = lot,
                                      name = e.name })
    -- A lot-based sale is all-or-nothing; see the header. A money row keeps the
    -- old forgiving behaviour, where handing over fewer simply pays less.
    return true, nil, { txn = txn, ft = takeFt, count = want, exact = lot > 1 }
end

--- Phase 2: `moved` is how many the client actually managed to hand over.
--- Anything short goes back on the shelf. Then the money is minted.
function B.commitSell(t, moved)
    local asked = math.floor(t.data.count or 0)
    moved = AkaShop.clampInt(moved, 0, asked)

    local g = B.groupOf(t.key)
    local e = g and findEntry(g, t.data.uid)
    local short = asked - moved
    if e and e.qty ~= B.UNLIMITED and short > 0 then
        e.qty = math.floor((e.qty or 0) + short)
    end

    if moved < 1 then
        return false, "Nothing was handed over.", nil
    end

    -- The row may have just hit zero, in which case it stops existing now
    -- rather than lingering as an offer nobody can take.
    if g then B.prune(g) end

    -- The row's own name, not the item's: on a pack row "Sold 1 x Jewelry -
    -- Ring" is the deal the player took, and naming the exact finger it came
    -- off reads like the depot misunderstood them.
    local name = (e and e.name) or t.data.name or AkaShop.displayNameOf(t.data.ft)

    -- Paid in goods.
    if type(t.data.payFt) == "string" and t.data.payFt ~= "" then
        local lot  = math.max(1, math.floor(t.data.lot or 1))
        local lots = math.floor(moved / lot)
        local n    = lots * math.max(1, math.floor(t.data.payN or 1))
        local payName = AkaShop.displayNameOf(t.data.payFt)
        if n < 1 then
            -- Only reachable if a client handed over part of a lot, which the
            -- all-or-nothing take is there to prevent. Say plainly what
            -- happened rather than paying nothing in silence.
            return true, "Handed over " .. moved .. " x " .. name ..
                         ", which is not a full trade of " .. lot .. ".", nil
        end
        return true,
               "Traded " .. moved .. " x " .. name .. " for " .. n .. " x " .. payName .. ".",
               { items = { { ft = t.data.payFt, count = n } } }
    end

    local pay = math.floor((t.data.price or 0) * moved)
    local msg = "Sold " .. moved .. " x " .. name .. " for " ..
                AkaShop.money(pay) .. " " .. AkaShop.getCurrencyName() .. "."

    if pay < 1 then
        -- A zero-price row is legitimate: a depot can exist purely to make an
        -- item disappear. Say so rather than sending an empty payout.
        return true, "Handed over " .. moved .. " x " .. name .. ".", nil
    end
    return true, msg, { items = { { ft = AkaShop.getCurrency(), count = pay } } }
end

--- Undo a reservation whose confirmation never came back.
function B.rollbackSell(t)
    local g = B.groupOf(t.key)
    local e = g and findEntry(g, t.data.uid)
    if e and e.qty ~= B.UNLIMITED then
        e.qty = math.floor((e.qty or 0) + math.floor(t.data.count or 0))
    end
end
