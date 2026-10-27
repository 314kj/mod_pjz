--[[===========================================================================
    AkaShop - authoritative shop logic.
    Runs on the dedicated server and, in singleplayer, inside the same Lua
    state as the UI. Nothing in here touches the UI or the network directly.

    Items and money NEVER move on trust. Every transfer is two-phase:
      1. the server validates, reserves and opens a transaction,
      2. the client performs the inventory change and reports what it managed,
      3. the server commits exactly that amount, or rolls the reservation back.
    An abandoned transaction is swept and rolled back after TXN_TTL seconds.
============================================================================]]

-- AkaShop_Shared.lua lives in media/lua/shared and is always loaded first,
-- so the AkaShop global is available here without an explicit require.

AkaShopCore = AkaShopCore or {}

local MD_KEY = "AkaShop_DB"

AkaShopCore.MAX_DIST       = 3     -- fallback only; AkaShop.useDistance() wins
AkaShopCore.MAX_PENDING    = 3     -- pending registration requests per player
AkaShopCore.MAX_CART_LINES = 40
-- (WITHDRAW_MAX moved to the WithdrawMax sandbox option, see AkaShop.withdrawMax)
AkaShopCore.TXN_TTL        = 120   -- seconds before an abandoned transfer rolls back
AkaShopCore.CODE_COOLDOWN  = 2     -- seconds between discount-code guesses
AkaShopCore.CODE_STRIKES   = 8     -- wrong guesses before a 60s lockout

--=================================================================== store ==

local schemaChecked = false

function AkaShopCore.db()
    local d = ModData.getOrCreate(MD_KEY)
    -- Only ever ADD missing containers. Never assign over one that exists:
    -- that single line is how shop data gets wiped by an update.
    if not d.shops     then d.shops     = {} end
    if not d.requests  then d.requests  = {} end
    if not d.whitelist then d.whitelist = {} end
    if not d.txns      then d.txns      = {} end
    if not d.nextReqId then d.nextReqId = 1  end
    if not d.nextUid   then d.nextUid   = 1  end
    if not d.nextTxn   then d.nextTxn   = 1  end

    if not schemaChecked then
        schemaChecked = true
        AkaShopSchema.apply(d)
    end
    return d
end

--- True when the database is safe to write to. False after a failed migration
--- or when the save came from a newer build than this one.
function AkaShopCore.writable()
    return not AkaShopSchema.locked
end

--- Guard for every mutating entry point: refuse rather than corrupt.
function AkaShopCore.assertWritable()
    if AkaShopSchema.locked then
        return false, (AkaShopSchema.lockMsg or "Traka is in read-only mode.")
    end
    return true
end

-- Global ModData is persisted with the save automatically, and we deliberately
-- do NOT ModData.transmit() it: the DB holds sales logs and discount codes that
-- clients must never see. Everything a client needs is pushed as a snapshot.
local function save() end

local function nowSec()
    local t
    if pcall(function() t = getTimestamp() end) and type(t) == "number" then return t end
    if pcall(function() t = getTimestampMs() end) and type(t) == "number" then
        return math.floor(t / 1000)
    end
    return 0
end
AkaShopCore.nowSec = nowSec

function AkaShopCore.getShop(key)
    return AkaShopCore.db().shops[key]
end

--============================================================= permissions ==

function AkaShopCore.isStaff(shop, username)
    return shop and shop.staff and shop.staff[username] == true
end

--- Full owner rights: rename, staff, withdraw, delete, enable/disable.
function AkaShopCore.canOwn(shop, username, admin)
    if not shop then return false end
    if admin and AkaShop.adminCanEditAny() then return true end
    return shop.owner == username
end

--- Everything about running the shop: stock, prices, codes, sales, the till.
---
--- Staff USED to be here, which meant hiring somebody to hand over orders
--- while you were offline also handed them your prices, your discount codes
--- and the contents of your till. That is not what anybody meant by "staff".
--- They now have exactly one power, below.
function AkaShopCore.canManage(shop, username, admin)
    return AkaShopCore.canOwn(shop, username, admin)
end

--- The single thing a staff member may do: work the order queue.
--- Owners and admins can too, because everything an owner can do includes it.
function AkaShopCore.canOrders(shop, username, admin)
    if AkaShopCore.canOwn(shop, username, admin) then return true end
    return AkaShopCore.isStaff(shop, username)
end

--- Nobody operates a till from the other side of the map. Admins may.
function AkaShopCore.near(player, x, y, z, admin)
    if admin then return true end
    if not player then return false end
    local d, pz
    local ok = pcall(function()
        local dx = player:getX() - (x + 0.5)
        local dy = player:getY() - (y + 0.5)
        d  = math.sqrt(dx * dx + dy * dy)
        pz = math.floor(player:getZ() + 0.5)
    end)
    if not ok or type(d) ~= "number" then return true end   -- can't measure, allow
    if pz ~= math.floor(z or 0) then return false end
    return d <= AkaShop.useDistance()
end

function AkaShopCore.nearShop(player, shop, admin)
    if not shop then return false end
    return AkaShopCore.near(player, shop.x, shop.y, shop.z, admin)
end

function AkaShopCore.countShopsOf(username)
    local n = 0
    for _, s in pairs(AkaShopCore.db().shops) do
        if s.owner == username then n = n + 1 end
    end
    return n
end

--=============================================================== whitelist ==

function AkaShopCore.setWhitelist(sprite, on)
    if type(sprite) ~= "string" or sprite == "" then return false, "No sprite." end
    local d = AkaShopCore.db()
    d.whitelist[sprite] = on and true or nil
    AkaShop.spriteWhitelist = d.whitelist
    save()
    return true, (on and ("Whitelisted sprite: " .. sprite)
                      or ("Removed sprite: " .. sprite))
end

function AkaShopCore.whitelistTable()
    local d = AkaShopCore.db()
    AkaShop.spriteWhitelist = d.whitelist
    return d.whitelist
end

--================================================================ register ==

--- `serverShop` marks a counter the server itself runs: always open, never
--- takes orders, ignores the trading window. Set when an admin builds a shop
--- and keeps it, cleared when they build one FOR somebody.
function AkaShopCore.register(ownerName, x, y, z, sprite, shopName, shopNameTH,
                              bypassLimit, serverShop)
    local d = AkaShopCore.db()
    local key = AkaShop.key(x, y, z)
    if d.shops[key] then
        return false, "There is already a shop registered on that tile."
    end
    if not bypassLimit then
        local limit = AkaShop.getMaxShopsPerPlayer()
        if AkaShopCore.countShopsOf(ownerName) >= limit then
            return false, ownerName .. " already owns the maximum of " ..
                limit .. " shop(s)."
        end
    end

    -- only invent a name when BOTH boxes were left blank, so a shop really can
    -- be Thai-only (or English-only) as the dialog promises
    local names = AkaShop.pairNames(shopName, shopNameTH, ownerName .. "'s Shop")

    d.shops[key] = {
        key      = key,
        x = math.floor(x), y = math.floor(y), z = math.floor(z or 0),
        sprite   = sprite or "",
        name     = names.en,
        nameTH   = names.th,
        owner    = ownerName,
        staff    = {},
        enabled  = true,
        alwaysOpen = serverShop and true or false,
        bank     = 0,
        revenue  = 0,
        created  = AkaShop.clockString(),
        items    = {},
        codes    = {},
        sales    = {},
    }
    AkaShopCore.dropRequestsAt(key)
    save()
    return true, "Shop registered: " .. AkaShop.shopBoth(d.shops[key]), d.shops[key]
end

function AkaShopCore.deleteShop(key)
    local d = AkaShopCore.db()
    local s = d.shops[key]
    if not s then return false, "Shop not found." end

    -- A till bigger than one cash withdrawal used to be handed back only up to
    -- the cap - and the shop was then deleted, so everything above it simply
    -- ceased to exist. Deleting a shop with 5000 in the till paid out 1000.
    --
    -- Handing back the lot is not the answer either: every unit is an item
    -- built in this one frame, which is exactly what the cap is there to stop.
    -- So a till that big is emptied FIRST, by the owner, on purpose. This has
    -- to be decided before anything below runs: AkaShopStock.take() takes the
    -- stock out of the entries, and a refusal after that would lose the goods.
    local bank = math.floor(s.bank or 0)
    local cap  = AkaShop.withdrawMax()
    if bank > cap then
        return false, "Empty the till first: " .. AkaShop.money(bank) ..
                      " is still in it, more than the " .. AkaShop.money(cap) ..
                      " that can be handed back as cash in one go. Take the money" ..
                      " or send it to the bank, then delete the shop."
    end

    -- hand every remaining unit back rather than deleting it into thin air
    local give = {}
    for _, e in ipairs(s.items or {}) do
        local n = AkaShopStock.total(e)
        if n > 0 then
            local states = AkaShopStock.take(e, n)
            table.insert(give, { ft = e.ft, count = n, states = states })
        end
    end
    if bank > 0 then
        table.insert(give, { ft = AkaShop.getCurrency(), count = bank })
    end

    d.shops[key] = nil
    save()
    return true, "Shop deleted: " .. AkaShop.shopBoth(s), give
end

function AkaShopCore.setEnabled(key, on)
    local s = AkaShopCore.getShop(key)
    if not s then return false, "Shop not found." end
    s.enabled = on and true or false
    save()
    return true, (on and "Shop opened." or "Shop closed.")
end

function AkaShopCore.setName(key, name, nameTH)
    local s = AkaShopCore.getShop(key)
    if not s then return false, "Shop not found." end
    local en = AkaShop.sanitizeNameOpt(name)
    local th = AkaShop.sanitizeNameOpt(nameTH)
    if en == "" and th == "" then
        return false, "A shop needs a name in at least one language."
    end
    s.name   = en          -- either side may now be cleared, as long as one stays
    s.nameTH = th
    save()
    return true, "Shop renamed to " .. AkaShop.shopBoth(s)
end

--================================================================ requests ==

function AkaShopCore.dropRequestsAt(key)
    local d = AkaShopCore.db()
    for i = #d.requests, 1, -1 do
        if d.requests[i].key == key then table.remove(d.requests, i) end
    end
end

function AkaShopCore.dropRequestById(id)
    local d = AkaShopCore.db()
    for i = #d.requests, 1, -1 do
        if d.requests[i].id == id then table.remove(d.requests, i) end
    end
end

function AkaShopCore.countRequestsOf(username)
    local n = 0
    for _, r in ipairs(AkaShopCore.db().requests) do
        if r.user == username then n = n + 1 end
    end
    return n
end

function AkaShopCore.addRequest(username, x, y, z, sprite, shopName, shopNameTH)
    local d = AkaShopCore.db()
    local key = AkaShop.key(x, y, z)
    if d.shops[key] then return false, "That register is already a shop." end

    for i = 1, #d.requests do
        local r = d.requests[i]
        if r.key == key then
            if r.user == username then return false, "You already have a pending request here." end
            return false, "Another player already requested this register."
        end
    end

    local limit = AkaShop.getMaxShopsPerPlayer()
    if AkaShopCore.countShopsOf(username) >= limit then
        return false, "You already own the maximum of " .. limit .. " shop(s)."
    end
    if AkaShopCore.countRequestsOf(username) >= AkaShopCore.MAX_PENDING then
        return false, "You already have " .. AkaShopCore.MAX_PENDING ..
            " requests waiting for an admin."
    end

    local names = AkaShop.pairNames(shopName, shopNameTH, username .. "'s Shop")
    local id = d.nextReqId
    d.nextReqId = id + 1
    table.insert(d.requests, {
        id     = id,
        key    = key,
        user   = username,
        x = math.floor(x), y = math.floor(y), z = math.floor(z or 0),
        sprite = sprite or "",
        name   = names.en,
        nameTH = names.th,
        when   = AkaShop.clockString(),
    })
    save()
    return true, "Request sent to the admins. Please wait for approval."
end

function AkaShopCore.findRequest(id)
    for _, r in ipairs(AkaShopCore.db().requests) do
        if r.id == id then return r end
    end
    return nil
end

function AkaShopCore.approveRequest(id)
    local r = AkaShopCore.findRequest(id)
    if not r then return false, "Request not found." end

    -- the cap is re-checked here: it was only true when the request was filed
    local copy = { id = r.id, user = r.user, name = r.name, nameTH = r.nameTH,
                   x = r.x, y = r.y, z = r.z, sprite = r.sprite }
    local ok, msg = AkaShopCore.register(copy.user, copy.x, copy.y, copy.z,
                                         copy.sprite, copy.name, copy.nameTH, false)
    if not ok then return false, msg end

    -- register() already dropped every request on that tile; remove by id
    -- (never by a cached index, which the drop above would have invalidated).
    AkaShopCore.dropRequestById(copy.id)
    save()
    return true, "Approved: " .. copy.user .. " -> " .. AkaShop.shopBoth(copy), copy
end

function AkaShopCore.denyRequest(id)
    local r = AkaShopCore.findRequest(id)
    if not r then return false, "Request not found." end
    local copy = { id = r.id, user = r.user, name = r.name, nameTH = r.nameTH }
    AkaShopCore.dropRequestById(id)
    save()
    return true, "Denied request from " .. copy.user, copy
end

function AkaShopCore.pendingFor(username)
    local out = {}
    for _, r in ipairs(AkaShopCore.db().requests) do
        if r.user == username then out[r.key] = true end
    end
    return out
end

--============================================================ transactions ==

-- Reservations live in ModData, not in a Lua local: a payout that deducted
-- stock or emptied the till must still be resolvable after a server restart,
-- otherwise the deduction would be permanent with nothing left to sweep it.

local function openTxn(kind, owner, key, data)
    local d = AkaShopCore.db()
    local id = d.nextTxn
    d.nextTxn = id + 1
    d.txns[id] = {
        id = id, kind = kind, owner = owner, key = key, data = data, t = nowSec(),
    }
    return id
end

-- The depot module reserves through this same ledger, so a depot sale that is
-- never confirmed is swept by exactly the machinery that sweeps a shop sale.
AkaShopCore.openTxn = openTxn

--- Fetch and consume a transaction. It must belong to the player confirming it
--- AND be of a kind that confirmation makes sense for - a `gave` arriving for a
--- `buy` reservation is rolled back rather than silently swallowed, which would
--- otherwise strand the reserved stock forever.
function AkaShopCore.claimTxn(id, owner, kinds)
    local d = AkaShopCore.db()
    local t = d.txns[id]
    if not t then return nil end
    if t.owner ~= owner then return nil end
    d.txns[id] = nil
    if kinds and not kinds[t.kind] then
        AkaShopCore.rollback(t)
        print("[Traka] wrong confirmation for txn #" .. tostring(id) ..
              " (" .. tostring(t.kind) .. ") - rolled back")
        return nil
    end
    return t
end

local function findListing(shop, uid)
    for i = 1, #shop.items do
        if shop.items[i].uid == uid then return shop.items[i], i end
    end
    return nil, nil
end

local function findListingByType(shop, ft)
    for i = 1, #shop.items do
        if shop.items[i].ft == ft then return shop.items[i], i end
    end
    return nil, nil
end

local function findCode(shop, code)
    for i = 1, #shop.codes do
        if shop.codes[i].code == code then return shop.codes[i], i end
    end
    return nil, nil
end

-- The orders module needs to reach into listings the same way this file does.
-- Exported rather than duplicated: two copies of "how do I find a listing"
-- is two chances for them to disagree about what a listing is.
AkaShopCore.findListing = findListing
AkaShopCore.findCode    = findCode

--- Put goods back on a shelf whose listing no longer exists.
---
--- Only orders need this. A purchase is over in seconds, so its listing is
--- still there when it rolls back; an order can sit for hours, and the shop
--- keeper may well have deleted the line in the meantime. Destroying the goods
--- would be robbery - they were taken off a customer's promise.
function AkaShopCore.relist(shop, ft, name, price, states)
    local e = findListingByType(shop, ft)
    if not e then
        if #shop.items >= AkaShop.getMaxListings() then return false end
        local db = AkaShopCore.db()
        e = {
            uid = db.nextUid, ft = ft,
            name = name or AkaShop.displayNameOf(ft),
            price = AkaShop.clampInt(price or 0, 0, AkaShop.MAX_PRICE),
            qty = 0, sold = 0, units = {},
        }
        db.nextUid = db.nextUid + 1
        table.insert(shop.items, e)
    end
    AkaShopStock.add(e, states)
    return true
end

--- Undo whatever a transaction had reserved.
function AkaShopCore.rollback(t)
    if not t then return end

    -- A depot is not a shop, so this has to be answered before the shop lookup
    -- below decides there is nothing to roll back and returns.
    if t.kind == "depot_sell" then
        if AkaShopBuy then pcall(AkaShopBuy.rollbackSell, t) end
        return
    end

    -- An abandoned handover restores nothing to the shelf. The goods were
    -- inside the order the whole time, never on it; "restoring" them would
    -- mint a second copy the moment the shop keeper tried again.
    if t.kind == "order" then
        if AkaShopOrders then pcall(AkaShopOrders.rollbackHand, t) end
        return
    end

    local shop = AkaShopCore.getShop(t.key)
    if not shop then return end
    local d = t.data or {}

    if t.kind == "buy" then
        for _, l in ipairs(d.lines or {}) do
            local e = findListing(shop, l.uid)
            -- put back the very rows that were reserved, so a rolled-back
            -- purchase restores the same worn axe rather than a pristine one
            if e then AkaShopStock.add(e, l.states or { { n = l.qty } }) end
        end
        if d.code then
            local c = findCode(shop, d.code)
            if c and c.used > 0 then c.used = c.used - 1 end
        end

    elseif t.kind == "payout_stock" then
        local e = findListing(shop, d.uid)
        if e then AkaShopStock.add(e, d.states or { { n = d.count } }) end

    elseif t.kind == "payout_remove" then
        local e = findListing(shop, d.uid)
        if e then AkaShopStock.add(e, d.states or { { n = d.count } }) end

    elseif t.kind == "payout_bank" then
        shop.bank = math.floor((shop.bank or 0) + d.count)
    end
    -- "deposit" reserves nothing: the stock is only credited on confirmation.
    save()
end

--- Abandoned reservations.
--- A "buy" reserved stock but created nothing on the client, so it is rolled
--- back. A payout, by contrast, has ALREADY put real items in the player's
--- inventory by the time the confirmation would have been sent - restoring the
--- shop's copy as well would mint a duplicate, so it is simply closed out.
function AkaShopCore.sweepTxns()
    local d = AkaShopCore.db()
    local now = nowSec()
    local dead = {}
    for id, t in pairs(d.txns) do
        if (now - (t.t or 0)) > AkaShopCore.TXN_TTL then table.insert(dead, id) end
    end
    for _, id in ipairs(dead) do
        local t = d.txns[id]
        d.txns[id] = nil
        if t.kind == "buy" or t.kind == "order" then
            -- "order" belongs here and not in the assumed-delivered branch: a
            -- handover that was never paid for delivered nothing, and leaving
            -- it marked pending would freeze that order forever.
            AkaShopCore.rollback(t)
            print("[Traka] rolled back abandoned " .. tostring(t.kind) ..
                  " #" .. tostring(id))
        else
            print("[Traka] closed abandoned " .. tostring(t.kind) ..
                  " transfer #" .. tostring(id) .. " (assumed delivered)")
        end
    end
end

--=========================================== stock / sales / weight helpers ==

local St = nil
local function stock() St = St or AkaShopStock; return St end

--- Split state rows into the first `k` units and the remainder. Used whenever
--- part of a reservation succeeded and the rest has to go back.
local function splitStates(states, k)
    local head, tail, left = {}, {}, math.floor(k or 0)
    for _, st in ipairs(states or {}) do
        local n = math.min(st.n or 0, math.max(left, 0))
        if n > 0 then
            local a = {}; for f,v in pairs(st) do a[f]=v end; a.n = n
            table.insert(head, a); left = left - n
        end
        local rest = (st.n or 0) - n
        if rest > 0 then
            local b = {}; for f,v in pairs(st) do b[f]=v end; b.n = rest
            table.insert(tail, b)
        end
    end
    return head, tail
end
AkaShopCore.splitStates = splitStates

--- Put reserved rows back on the listing they came from. Safe when the
--- listing was deleted mid-flight: the units are simply dropped, and the
--- caller is the one that hands the goods back to a player.
local function returnStates(shop, uid, ft, states)
    if not shop then return false end
    local e = findListing(shop, uid)
    if not e then return false end
    stock().add(e, states)
    return true
end

--- Record one sale into the bounded day buckets.
--- Deliberately NOT an ever-growing list: `daily` is capped at a retention
--- window, everything older folds into a single running total, `byItem` is
--- bounded by how many item types the shop has ever sold, and `recent` is a
--- fixed-length ring. A server can run for years without the save growing.
local function recordSale(shop, buyer, total, lines)
    local day  = AkaShop.dayStamp()
    local keep = AkaShop.getSalesDays()

    shop.daily  = shop.daily  or {}
    shop.older  = shop.older  or { rev = 0, n = 0 }
    shop.byItem = shop.byItem or {}
    shop.recent = shop.recent or {}

    local b = shop.daily[day]
    if not b then b = { rev = 0, n = 0 }; shop.daily[day] = b end
    b.rev, b.n = b.rev + total, b.n + 1

    for _, l in ipairs(lines or {}) do
        if l.ft then
            local it = shop.byItem[l.ft]
            if not it then it = { n = 0, rev = 0 }; shop.byItem[l.ft] = it end
            it.n   = it.n + (l.q or 0)
            it.rev = it.rev + (l.u or 0) * (l.q or 0)
        end
    end

    table.insert(shop.recent, 1, {
        when = AkaShop.clockString(), buyer = buyer, total = total, lines = lines,
    })
    local keepRecent = AkaShop.getSalesRecent()
    while #shop.recent > keepRecent do table.remove(shop.recent) end

    -- prune day buckets older than the window into `older`
    local days = {}
    for k in pairs(shop.daily) do table.insert(days, k) end
    if #days > keep then
        table.sort(days)
        for i = 1, #days - keep do
            local old = shop.daily[days[i]]
            shop.older.rev = shop.older.rev + (old.rev or 0)
            shop.older.n   = shop.older.n   + (old.n   or 0)
            shop.daily[days[i]] = nil
        end
    end
end

-- A collected order is a sale like any other and belongs in the same books.
AkaShopCore.recordSale = recordSale

--============================================================== capacity ====

function AkaShopCore.capacityOf(shop)
    return math.floor(shop and shop.capacityKg or AkaShop.getStartCapacity())
end

--- kg still free in this shop.
function AkaShopCore.roomKg(shop)
    return AkaShopCore.capacityOf(shop) - stock().shopWeight(shop)
end

--- Buy another block of shelf space out of the till.
function AkaShopCore.buyCapacity(key)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    local step, maxKg = AkaShop.getCapacityStep(), AkaShop.getMaxCapacity()
    local cur  = AkaShopCore.capacityOf(shop)
    if cur >= maxKg then
        return false, "Already at the maximum " .. maxKg .. " kg."
    end
    local cost = AkaShop.getCapacityPrice()
    if (shop.bank or 0) < cost then
        return false, "The till needs " .. AkaShop.money(cost) ..
            " to expand (it holds " .. AkaShop.money(shop.bank or 0) .. ")."
    end
    shop.bank       = shop.bank - cost
    shop.capacityKg = math.min(cur + step, maxKg)
    save()
    return true, "Expanded to " .. shop.capacityKg .. " kg for " ..
        AkaShop.money(cost) .. "."
end

--================================================================ listings ==

--- Phase 1 of a deposit. Nothing is credited yet; we only work out how many
--- units the seller may hand over and ask the client to take exactly that many.
--- Returns ok, msg, request{ txn=, ft=, count= }
function AkaShopCore.beginDeposit(key, player, actor, ft, qty, price)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    if type(ft) ~= "string" or ft == "" then return false, "Bad item type." end

    qty = AkaShop.clampInt(qty, 1, AkaShop.MAX_STOCK)
    local have = AkaShop.countType(player:getInventory(), ft, player)
    if have < 1 then return false, "You are not carrying that item." end
    if have < qty then qty = have end

    local entry = findListingByType(shop, ft)
    if entry then
        local room = AkaShop.MAX_STOCK - AkaShopStock.total(entry)
        if room < 1 then return false, "That listing is already full." end
        if qty > room then qty = room end
    elseif #shop.items >= AkaShop.getMaxListings() then
        return false, "This shop already lists the maximum number of items."
    end

    -- shelf space. This cap is what keeps the stock table bounded, so it is
    -- enforced here on the way in rather than trusted to the UI.
    local unit = AkaShopStock.weightOf(ft)
    if unit > 0 then
        local fits = math.floor(AkaShopCore.roomKg(shop) / unit)
        if fits < 1 then
            return false, string.format(
                "No shelf space left (%.1f / %d kg). Expand the shop first.",
                AkaShopStock.shopWeight(shop), AkaShopCore.capacityOf(shop))
        end
        if qty > fits then qty = fits end
    end

    local txn = openTxn("deposit", actor, key, {
        ft = ft, count = qty, price = price,
    })
    return true, nil, { txn = txn, ft = ft, count = qty }
end

--- Phase 2: the client removed `moved` units, so credit exactly `moved`.
--- The goods are already out of the seller's hands by now, so every failure
--- path has to hand them straight back rather than let them evaporate.
--- Returns ok, msg, giveBack{ items = {...} } or nil.
function AkaShopCore.commitDeposit(t, moved, states)
    local d = t.data
    moved = AkaShop.clampInt(moved, 0, d.count)
    if moved < 1 then return false, "Nothing was taken from your inventory." end

    -- The client reports the real condition of what it handed over. Trust it
    -- for FLAVOUR only: the count is still clamped to what we authorised, so a
    -- tampered client can lie about wear but never about how much it gave.
    states = states or {}
    local sum = 0
    for _, st in ipairs(states) do sum = sum + (st.n or 0) end
    if sum ~= moved then
        states = { { n = moved } }          -- mismatch: fall back to plain units
    end

    local refund = { items = { { ft = d.ft, count = moved, states = states } } }

    local shop = AkaShopCore.getShop(t.key)
    if not shop then
        return false, "The shop is gone - your items came back.", refund
    end

    local entry = findListingByType(shop, d.ft)
    if not entry then
        if #shop.items >= AkaShop.getMaxListings() then
            return false, "This shop is full - your items came back.", refund
        end
        local db = AkaShopCore.db()
        entry = {
            uid   = db.nextUid,
            ft    = d.ft,
            name  = AkaShop.displayNameOf(d.ft),
            price = AkaShop.clampInt(d.price, 0, AkaShop.MAX_PRICE),
            qty   = 0,
            sold  = 0,
            units = {},
        }
        db.nextUid = db.nextUid + 1
        table.insert(shop.items, entry)
    elseif d.price ~= nil then
        entry.price = AkaShop.clampInt(d.price, 0, AkaShop.MAX_PRICE)
    end

    -- a concurrent deposit may have filled the listing while these units were
    -- in flight; whatever no longer fits goes back to the seller
    local room   = AkaShop.MAX_STOCK - AkaShopStock.total(entry)
    local listed = math.min(moved, math.max(room, 0))
    local put, back = splitStates(states, listed)
    AkaShopStock.add(entry, put)
    save()

    local spill = moved - listed
    local msg = "Listed " .. listed .. " x " .. entry.name .. " at " ..
        AkaShop.money(entry.price) .. " each."
    if spill > 0 then
        return true, msg .. " " .. spill .. " did not fit and came back.",
            { items = { { ft = d.ft, count = spill, states = back } } }
    end
    return true, msg
end

function AkaShopCore.setPrice(key, uid, price)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    local e = findListing(shop, uid)
    if not e then return false, "Listing not found." end
    e.price = AkaShop.clampInt(price, 0, AkaShop.MAX_PRICE)
    save()
    return true, e.name .. " is now " .. AkaShop.money(e.price) .. "."
end

--- Phase 1 of pulling stock back out. The units are reserved immediately so
--- nobody can buy them while they are in flight.
function AkaShopCore.beginTakeStock(key, actor, uid, qty, removeListing)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    local e = findListing(shop, uid)
    if not e then return false, "Listing not found." end

    local have = AkaShopStock.total(e)
    if removeListing then
        qty = have
    else
        qty = AkaShop.clampInt(qty, 1, math.max(have, 1))
        if qty > have then qty = have end
    end
    if qty < 1 and not removeListing then return false, "Nothing in stock." end

    -- pull the real rows out now, so nothing can be bought while they are in
    -- flight and a rollback puts back exactly the same items, not generic ones
    local states = AkaShopStock.take(e, qty)
    save()

    local txn = openTxn(removeListing and "payout_remove" or "payout_stock",
                        actor, key, { uid = uid, ft = e.ft, count = qty,
                                      states = states })
    return true, nil, { txn = txn,
                        items = { { ft = e.ft, count = qty, states = states } },
                        empty = (qty < 1) }
end

--- Phase 2 of a stock payout: `made` units actually materialised.
function AkaShopCore.commitTakeStock(t, made)
    local shop = AkaShopCore.getShop(t.key)
    if not shop then return false, "Shop is gone." end
    local d = t.data
    made = AkaShop.clampInt(made, 0, d.count)
    local lost = d.count - made

    local e, idx = findListing(shop, d.uid)
    if e and lost > 0 then
        local _, back = splitStates(d.states, made)   -- what never spawned
        AkaShopStock.add(e, back)
    end

    if t.kind == "payout_remove" then
        if not e then
            save()
            return true, "Listing already gone; " .. made .. " returned to you."
        end
        if AkaShopStock.total(e) <= 0 then
            local name = e.name
            table.remove(shop.items, idx)
            save()
            return true, "Removed listing: " .. name ..
                (made > 0 and ("  (" .. made .. " returned to you)") or "")
        end
        save()
        return true, "Only " .. made .. " could be returned - the listing was kept."
    end

    save()
    if made < 1 then return false, "Nothing could be added to your inventory." end
    return true, "Took back " .. made .. " x " .. (e and e.name or "item") .. "."
end

--=========================================================== discount codes =

function AkaShopCore.addCode(key, code, percent, maxUses)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    code = AkaShop.normCode(code)
    if code == "" then return false, "Enter a code." end
    if findCode(shop, code) then return false, "That code already exists." end
    if #shop.codes >= AkaShop.MAX_CODES then return false, "Too many codes." end
    table.insert(shop.codes, {
        code    = code,
        percent = AkaShop.clampInt(percent, 1, 100),
        maxUses = AkaShop.clampInt(maxUses, 0, 99999),  -- 0 = unlimited
        used    = 0,
    })
    save()
    return true, "Code " .. code .. " created."
end

function AkaShopCore.delCode(key, code)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    local _, idx = findCode(shop, AkaShop.normCode(code))
    if not idx then return false, "Code not found." end
    table.remove(shop.codes, idx)
    save()
    return true, "Code removed."
end

-- Guessing codes is throttled: a code is a secret the shop owner hands out,
-- not something a scripted client should be able to enumerate.
local codeGuard = {}

function AkaShopCore.mayCheckCode(username)
    local g = codeGuard[username]
    local now = nowSec()
    if not g then
        codeGuard[username] = { last = now, strikes = 0, until_ = 0 }
        return true
    end
    if now < (g.until_ or 0) then return false, "Too many wrong codes - wait a minute." end
    if (now - g.last) < AkaShopCore.CODE_COOLDOWN then
        return false, "Slow down."
    end
    g.last = now
    return true
end

local function codeStrike(username, wrong)
    local g = codeGuard[username]
    if not g then return end
    if wrong then
        g.strikes = (g.strikes or 0) + 1
        if g.strikes >= AkaShopCore.CODE_STRIKES then
            g.until_ = nowSec() + 60
            g.strikes = 0
        end
    else
        g.strikes = 0
    end
end

--- Validate a code a customer typed. Returns ok, percent, message.
function AkaShopCore.checkCode(key, username, code)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, 0, "Shop not found." end
    code = AkaShop.normCode(code)
    if code == "" then return false, 0, "Enter a code." end

    local c = findCode(shop, code)
    if not c then
        codeStrike(username, true)
        return false, 0, "Unknown discount code."
    end
    if c.maxUses > 0 and c.used >= c.maxUses then
        codeStrike(username, false)
        return false, 0, "That code has been used up."
    end
    codeStrike(username, false)
    return true, c.percent, "Code " .. code .. " applied: -" .. c.percent .. "%"
end

--==================================================================== staff =

--- Hand a shop to somebody else.
---
--- The stock, the till and the sales history go with it. That is the point:
--- a shop is a thing, not a bundle of the current owner's belongings, and
--- splitting it would mean deciding who owns half a listing.
function AkaShopCore.setOwner(key, username, admin)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    username = AkaShop.trim(username)
    if username == "" then return false, "Pick a player." end
    if username == shop.owner then
        return false, username .. " already owns this shop."
    end

    -- The per-player shop limit still applies, or handing shops around becomes
    -- the way to get more of them than the server allows. An admin may
    -- override, exactly as they may when registering.
    if not admin then
        local limit = AkaShop.getMaxShopsPerPlayer()
        if AkaShopCore.countShopsOf(username) >= limit then
            return false, username .. " already owns the maximum of " ..
                limit .. " shop(s)."
        end
    end

    local was = shop.owner
    shop.owner = username
    -- Handing a server store to a player makes it that player's business, so
    -- it goes back onto player hours. An admin who wants it to stay open all
    -- night can switch the flag on again; the safe default is the one that
    -- does not quietly hand somebody a shop exempt from the server's rules.
    shop.alwaysOpen = false
    -- The new owner cannot also be their own staff, and the OLD owner is not
    -- automatically kept on: handing a shop over is a handover, not a
    -- partnership. Whoever wants that can hire the other afterwards.
    if shop.staff then shop.staff[username] = nil end
    save()
    return true, "Shop handed from " .. tostring(was) .. " to " .. username ..
        ". Stock, till and history went with it.", was
end

--- Flip a shop between "server infrastructure" and "somebody's business".
--- Admin-gated by the caller, because it is the difference between a counter
--- that keeps the server's hours and one that keeps nobody's.
function AkaShopCore.setAlwaysOpen(key, on)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    shop.alwaysOpen = on and true or false
    save()
    if shop.alwaysOpen then
        return true, AkaShop.shopName(shop) .. " is now a SERVER SHOP: open " ..
            "around the clock, and it will not take orders."
    end
    return true, AkaShop.shopName(shop) .. " now keeps the server's trading " ..
        "hours like any player shop."
end

function AkaShopCore.addStaff(key, username)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    username = AkaShop.trim(username)
    if username == "" then return false, "Enter a player name." end
    if username == shop.owner then return false, "The owner is already in charge." end
    -- Hiring somebody twice used to report success and change nothing. With a
    -- one-click list of online players that is an easy accident, and "added"
    -- when nothing happened is the kind of small lie that makes an owner stop
    -- believing the window.
    if shop.staff[username] then
        return false, username .. " is already on the staff."
    end
    local n = 0
    for _ in pairs(shop.staff) do n = n + 1 end
    if n >= AkaShop.MAX_STAFF then return false, "Too many staff." end
    shop.staff[username] = true
    save()
    -- The wording matters now that staff is not a second owner: say exactly
    -- what they gained, or the owner will assume it is what it used to be.
    return true, username .. " can now hand over orders at this shop (nothing else)."
end

function AkaShopCore.delStaff(key, username)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    if not shop.staff[username] then return false, "Not a staff member." end
    shop.staff[username] = nil
    save()
    return true, username .. " removed from staff."
end

--=================================================================== money ==

--- Phase 1 of a withdrawal: debit the till and hold it in a transaction.
function AkaShopCore.beginWithdraw(key, actor, amount)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    local bank = math.floor(shop.bank or 0)
    if bank <= 0 then return false, "The till is empty." end

    local ft = AkaShop.getCurrency()
    if not (getScriptManager() and getScriptManager():FindItem(ft)) then
        return false, "The configured currency item (" .. ft .. ") does not exist."
    end

    amount = tonumber(amount)
    if not amount or amount <= 0 then amount = bank end
    amount = AkaShop.clampInt(amount, 1, math.min(bank, AkaShop.withdrawMax()))

    shop.bank = bank - amount
    save()
    local txn = openTxn("payout_bank", actor, key, { count = amount })
    return true, nil, { txn = txn, items = { { ft = ft, count = amount } } }
end

--- Phase 2: only `made` coins actually appeared, refund the difference.
function AkaShopCore.commitWithdraw(t, made)
    local shop = AkaShopCore.getShop(t.key)
    local asked = t.data.count
    made = AkaShop.clampInt(made, 0, asked)
    local lost = asked - made
    if shop and lost > 0 then
        shop.bank = math.floor((shop.bank or 0) + lost)
    end
    save()
    if made < 1 then return false, "Your inventory would not take the money." end
    local msg = "Withdrew " .. AkaShop.money(made) .. " " .. AkaShop.getCurrencyName() .. "."
    if shop and (shop.bank or 0) > 0 then
        msg = msg .. " " .. AkaShop.money(shop.bank) .. " still in the till."
    end
    return true, msg
end

--- Pay the till straight into the actor's Akacount account.
---
--- One phase, unlike a cash withdrawal: no item changes hands, so there is
--- nothing a client has to build or report back, and no cap either - the cap
--- on cash exists only because every unit is an item.
---
--- The till is debited BEFORE the bank is asked and restored in full if the
--- bank says no, so there is no moment at which the money exists in both
--- places. The bank checks everything before it writes anything (Akacount's
--- depositFrom contract), which is what makes "put it all back" correct: a
--- refusal means nothing happened on its side.
function AkaShopCore.toBank(key, actor, amount, player)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end

    local linked, why = AkaShop.bankLink()
    if not linked then return false, why end
    -- Resolved here, every call: Akacount may load after Traka.
    local api = Akacount
    if type(api) ~= "table" or type(api.depositFrom) ~= "function" then
        return false, "This server's Akacount is too old to take shop transfers (needs 0.4.1)."
    end

    local bank = math.floor(shop.bank or 0)
    if bank <= 0 then return false, "The till is empty." end
    amount = tonumber(amount)
    if not amount or amount <= 0 then amount = bank end
    amount = AkaShop.clampInt(amount, 1, bank)

    shop.bank = bank - amount
    local called, done, err, info = false, false, nil, nil
    called = pcall(function()
        done, err, info = api.depositFrom(actor, amount, {
            label = shop.name or shop.nameTH, by = actor, player = player })
    end)
    if not called or done ~= true then
        shop.bank = bank
        save()
        return false, (called and err) or "The bank did not accept the transfer. Nothing was moved."
    end
    save()

    local msg = "Sent " .. AkaShop.money(amount) .. " to your bank account."
    if type(info) == "table" and (info.fee or 0) > 0 then
        msg = msg .. " Bank fee " .. AkaShop.bankMoney(info.fee) .. "."
    end
    if (shop.bank or 0) > 0 then
        msg = msg .. " " .. AkaShop.money(shop.bank) .. " still in the till."
    end
    return true, msg
end

--================================================================ purchase ==

--- Merge duplicate lines and drop nonsense before anything is reserved.
local function normaliseCart(cart)
    if type(cart) ~= "table" then return nil, "Your cart is empty." end
    local merged, order = {}, {}
    local lines = 0
    for i = 1, #cart do
        local row = cart[i]
        if type(row) == "table" then
            local uid = tonumber(row.uid)
            local qty = AkaShop.clampInt(row.qty, 0, AkaShop.MAX_STOCK)
            if uid and qty > 0 then
                if not merged[uid] then
                    lines = lines + 1
                    if lines > AkaShopCore.MAX_CART_LINES then
                        return nil, "Too many different items in one purchase."
                    end
                    merged[uid] = 0
                    table.insert(order, uid)
                end
                merged[uid] = AkaShop.clampInt(merged[uid] + qty, 0, AkaShop.MAX_STOCK)
            end
        end
    end
    if #order == 0 then return nil, "Your cart is empty." end
    local out = {}
    for _, uid in ipairs(order) do
        table.insert(out, { uid = uid, qty = merged[uid] })
    end
    return out
end

--- Phase 1: validate, price, reserve the stock, ask the client to pay.
--- Returns ok, msg, charge{ txn=, cost= }
function AkaShopCore.beginBuy(key, player, buyerName, cart, codeStr, expect)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    if not shop.enabled then return false, "This shop is closed." end
    -- Trading hours. Outside the window the goods stay on display but the shop
    -- will not serve itself; the owner has to be there. Off by default.
    if not AkaShop.shopSelfServeNow(shop) then
        return false, "This shop only serves customers between " ..
            AkaShop.hoursText() .. ". Place an order instead, or find the owner."
    end
    if shop.owner == buyerName and not AkaShop.ownerCanBuyOwn() then
        return false, "Use the management window to take your own stock."
    end

    local lines, err = normaliseCart(cart)
    if not lines then return false, err end

    local subtotal = 0
    for _, l in ipairs(lines) do
        local e = findListing(shop, l.uid)
        if not e then return false, "An item in your cart is no longer for sale." end
        local have = AkaShopStock.total(e)
        if have < l.qty then
            return false, "Only " .. have .. " x " .. e.name .. " left in stock."
        end
        -- price the exact units that will be handed over: worn stock is sold
        -- worst-first and discounted per row, so the quote and the goods can
        -- never disagree about which axe this is
        local cost = AkaShopStock.quote(e, l.qty)
        l.name  = e.name
        l.price = math.floor(cost / math.max(l.qty, 1))
        l.cost  = cost
        l.ft    = e.ft          -- kept so a listing deleted mid-flight still pays out
        subtotal = subtotal + cost
    end

    local percent, codeRec = 0, nil
    codeStr = AkaShop.normCode(codeStr)
    if codeStr ~= "" then
        codeRec = findCode(shop, codeStr)
        if not codeRec then return false, "Unknown discount code." end
        if codeRec.maxUses > 0 and codeRec.used >= codeRec.maxUses then
            return false, "That code has been used up."
        end
        percent = codeRec.percent
    end

    local discount = math.floor(subtotal * percent / 100)
    local total    = subtotal - discount
    if total < 0 then total = 0 end

    -- the price the customer was actually shown must be the price they pay
    expect = tonumber(expect)
    if expect and math.floor(expect) ~= total then
        return false, "Prices changed while you were shopping - total is now " ..
            AkaShop.money(total) .. ". Check your cart and try again."
    end

    local wallet = AkaShop.countType(player:getInventory(), AkaShop.getCurrency(), player)
    if wallet < total then
        return false, "You need " .. AkaShop.money(total) .. " " ..
            AkaShop.getCurrencyName() .. " (you have " .. AkaShop.money(wallet) .. ")."
    end

    -- reserve the actual rows
    for _, l in ipairs(lines) do
        local e = findListing(shop, l.uid)
        l.states = AkaShopStock.take(e, l.qty)
    end
    if codeRec then codeRec.used = codeRec.used + 1 end
    save()

    local txn = openTxn("buy", buyerName, key, {
        lines = lines, code = (codeStr ~= "" and codeStr or nil),
        subtotal = subtotal, discount = discount, total = total,
    })
    return true, nil, { txn = txn, cost = total }
end

--- Price a cart exactly the way beginBuy does, without touching anything.
--- Split out so an order and a purchase can never quote different numbers for
--- the same basket - the day those two drift apart is the day a customer is
--- charged something they were never shown.
local function priceCart(shop, cart, codeStr)
    local lines, err = normaliseCart(cart)
    if not lines then return nil, err end

    local subtotal = 0
    for _, l in ipairs(lines) do
        local e = findListing(shop, l.uid)
        if not e then return nil, "An item in your cart is no longer for sale." end
        local have = AkaShopStock.total(e)
        if have < l.qty then
            return nil, "Only " .. have .. " x " .. e.name .. " left in stock."
        end
        local cost = AkaShopStock.quote(e, l.qty)
        l.name  = e.name
        l.price = math.floor(cost / math.max(l.qty, 1))
        l.cost  = cost
        l.ft    = e.ft
        subtotal = subtotal + cost
    end

    local percent, codeRec = 0, nil
    codeStr = AkaShop.normCode(codeStr)
    if codeStr ~= "" then
        codeRec = findCode(shop, codeStr)
        if not codeRec then return nil, "Unknown discount code." end
        if codeRec.maxUses > 0 and codeRec.used >= codeRec.maxUses then
            return nil, "That code has been used up."
        end
        percent = codeRec.percent
    end

    local discount = math.floor(subtotal * percent / 100)
    local total    = subtotal - discount
    if total < 0 then total = 0 end
    return lines, nil, subtotal, discount, total, codeRec,
           (codeStr ~= "" and codeStr or nil)
end

--- Put a cart aside for the shop keeper to hand over in person.
---
--- Deliberately does NOT check the trading window: this is the path that
--- exists BECAUSE the window is shut. It also does not check the buyer's
--- wallet - they pay at the counter, and demanding the money now would only
--- stop somebody who intends to go and earn it.
function AkaShopCore.beginOrder(key, player, buyerName, cart, codeStr, expect)
    local shop = AkaShopCore.getShop(key)
    if not shop then return false, "Shop not found." end
    if not shop.enabled then return false, "This shop is closed." end
    if shop.owner == buyerName then
        return false, "You cannot order from your own shop."
    end
    -- An order is what you do when the shop cannot serve you. If it can, this
    -- is not a feature, it is a way to make the shop keeper come and do by
    -- hand what the till would have done by itself.
    if AkaShop.shopSelfServeNow(shop) then
        return false, "This shop is open - buy what you want directly."
    end

    local ok, msg = AkaShopOrders.roomFor(shop, buyerName)
    if not ok then return false, msg end

    local lines, err, subtotal, discount, total, codeRec, code =
        priceCart(shop, cart, codeStr)
    if not lines then return false, err end

    expect = tonumber(expect)
    if expect and math.floor(expect) ~= total then
        return false, "Prices changed while you were shopping - the total is now " ..
            AkaShop.money(total) .. ". Check your cart and try again."
    end

    -- Reserve for real. An order that leaves the goods on the shelf is a
    -- promise the shop can break by selling them to somebody else.
    for _, l in ipairs(lines) do
        local e = findListing(shop, l.uid)
        l.states = AkaShopStock.take(e, l.qty)
    end
    if codeRec then codeRec.used = codeRec.used + 1 end

    local o = AkaShopOrders.create(shop, buyerName, lines, subtotal, discount, total, code)
    save()
    return true, "Order #" .. o.id .. " placed for " .. AkaShop.money(total) .. " " ..
        AkaShop.getCurrencyName() .. ". Meet " .. tostring(shop.owner) ..
        " at the counter to collect it - you pay on collection.", o
end

--- Phase 2: the client reports what it managed to pay.
--- Returns ok, msg, give{ items = {...} }
function AkaShopCore.commitBuy(t, paid)
    local d = t.data
    paid = math.floor(tonumber(paid) or 0)

    local shop = AkaShopCore.getShop(t.key)
    if not shop then
        AkaShopCore.rollback(t)
        -- the money has already left the buyer's pockets: give it straight back
        if paid > 0 then
            return false, "The shop vanished - you have been refunded.",
                { items = { { ft = AkaShop.getCurrency(), count = paid } } }
        end
        return false, "The shop vanished; nothing was charged."
    end

    if paid < d.total then
        AkaShopCore.rollback(t)
        return false, "Payment failed - the stock has been put back."
    end

    local give, logLines = {}, {}
    for _, l in ipairs(d.lines) do
        local e = findListing(shop, l.uid)
        if e then e.sold = (e.sold or 0) + l.qty end
        table.insert(give, { ft = (e and e.ft) or l.ft, count = l.qty,
                             states = l.states })
        table.insert(logLines, { n = l.name, q = l.qty, u = l.price,
                                 ft = (e and e.ft) or l.ft })
    end

    local tax      = AkaShop.getTaxPercent()
    local ownerCut = math.floor(d.total * (100 - tax) / 100)
    shop.bank    = math.floor((shop.bank or 0) + ownerCut)
    shop.revenue = math.floor((shop.revenue or 0) + d.total)

    recordSale(shop, t.owner, d.total, logLines)
    save()

    local msg = "Paid " .. AkaShop.money(d.total)
    if d.discount > 0 then msg = msg .. " (saved " .. AkaShop.money(d.discount) .. ")" end
    return true, msg, { items = give }
end

--================================================================ reporting =

--- Totals now come from the day buckets. They used to be summed out of
--- shop.sales, which recordSale stopped writing to when sales became per-day,
--- so every shop reported 0 sold today and an empty history no matter how much
--- it actually traded.
function AkaShopCore.totals(shop)
    local stamp = AkaShop.dayStamp()
    local b = (shop.daily or {})[stamp] or { rev = 0, n = 0 }
    local today, todayCount = b.rev or 0, b.n or 0

    local allTime  = (shop.older or {}).rev or 0
    local allCount = (shop.older or {}).n   or 0
    for _, day in pairs(shop.daily or {}) do
        allTime  = allTime  + (day.rev or 0)
        allCount = allCount + (day.n   or 0)
    end
    return {
        today = today, todayCount = todayCount,
        logged = allTime, loggedCount = allCount,
        revenue = math.floor(shop.revenue or 0),
        bank = math.floor(shop.bank or 0),
    }
end

--=============================================================== snapshots ==

--- Rows for the client. Only the collapsed rows travel, never per-item data:
--- a listing is at most MAX_ROWS entries no matter how much stock sits in it,
--- so a shop with 2,000 nails still sends one row.
local function copyRows(e)
    local out = {}
    for _, r in ipairs(e.units or {}) do
        table.insert(out, {
            n = r.n, cond = r.cond, condMax = r.condMax, uses = r.uses,
            age = r.age, cooked = r.cooked, frozen = r.frozen,
            unit = AkaShopStock.priceOf(e, r),
            wear = AkaShopStock.wear(r),
        })
    end
    return out
end

local function copyItems(shop, publicOnly)
    local out, today = {}, AkaShop.dayStamp()
    for _, e in ipairs(shop.items) do
        local n = AkaShopStock.total(e)
        -- A sold-out listing stays on the customer's shelf until the end of
        -- the day it ran out, then disappears on its own. The owner always
        -- sees everything.
        local show = (not publicOnly) or n > 0 or (e.outDay == today)
        if show then
            table.insert(out, {
                uid = e.uid, ft = e.ft, name = e.name,
                price = e.price, qty = n, sold = e.sold or 0,
                kg = AkaShopStock.weightOf(e.ft),
                rows = copyRows(e),
                outToday = (n <= 0 and e.outDay == today) or nil,
            })
        end
    end
    return out
end

local function staffList(shop)
    local out = {}
    for u in pairs(shop.staff or {}) do table.insert(out, u) end
    table.sort(out)
    return out
end

--- mode = "manage" (owner/staff/admin) or "buy" (customer)
--- Called after anything that can empty a listing, so `outDay` marks the day
--- it ran out and the customer view can retire it tomorrow.
function AkaShopCore.stampEmpties(shop)
    if not shop then return end
    local today = AkaShop.dayStamp()
    for _, e in ipairs(shop.items or {}) do
        if AkaShopStock.total(e) <= 0 then
            if not e.outDay then e.outDay = today end
        else
            e.outDay = nil
        end
    end
end

--- `who` is the username the snapshot is being built FOR, and `admin` whether
--- they are staff-of-the-server rather than staff-of-the-shop.
---
--- Both exist because one window now has two audiences. A customer needs to
--- know which orders are theirs; a shop's staff member needs the order queue
--- and nothing else. Answering that here, at the point the data is assembled,
--- is the only place it can be answered safely - a client cannot be trusted to
--- hide something it was sent.
function AkaShopCore.snapshot(key, mode, who, admin)
    local shop = AkaShopCore.getShop(key)
    if not shop then return nil end
    AkaShopCore.stampEmpties(shop)
    local full = AkaShopCore.canOwn(shop, who, admin)

    local snap = {
        key      = shop.key,
        name     = shop.name,
        nameTH   = shop.nameTH or "",
        owner    = shop.owner,
        enabled  = shop.enabled and true or false,
        x = shop.x, y = shop.y, z = shop.z,
        currency = AkaShop.getCurrencyName(),
        items    = copyItems(shop, mode == "buy"),
        mode     = mode,
        weightKg   = AkaShopStock.shopWeight(shop),
        capacityKg = AkaShopCore.capacityOf(shop),
        capStep    = AkaShop.getCapacityStep(),
        capMax     = AkaShop.getMaxCapacity(),
        capPrice   = AkaShop.getCapacityPrice(),
        -- All four answered FOR THIS SHOP, not for the server. A server store
        -- and the corner shop next door are on different clocks now.
        hoursText  = AkaShop.shopHoursText(shop),
        modeLabel  = AkaShop.shopModeLabel(shop),
        canBuyNow  = AkaShop.shopSelfServeNow(shop),
        alwaysOpen = shop.alwaysOpen and true or false,
        orderHours = AkaShop.orderHours(),
        -- Whether an order can EVER be placed at this shop, which is a
        -- different question from whether one has been. Orders only exist
        -- outside self-service hours, and self-service hours are off by
        -- default - so on a fresh server the whole order/staff feature is
        -- switched off and looks broken instead of switched off. A 24h server
        -- shop never closes, so it never takes orders either.
        ordersOn   = AkaShop.shopOrdersOn(shop),
    }

    if mode == "buy" then
        snap.myOrders = AkaShopOrders.mine(shop, who)
        return snap
    end

    snap.orders = AkaShopOrders.list(shop)

    -- A staff member opens the same window but is handed a different shop.
    -- Everything below this line - stock, prices, codes, the till, the sales
    -- history - is simply absent from their copy rather than sent and hidden,
    -- because a client can un-hide anything it was sent.
    snap.full = full and true or false
    if not full then
        snap.items  = {}
        snap.totals = nil
        snap.staff  = nil
        snap.codes  = nil
        snap.sales  = nil
        return snap
    end

    if mode ~= "buy" then
        snap.staff  = staffList(shop)
        snap.codes  = {}
        for _, c in ipairs(shop.codes) do
            table.insert(snap.codes, {
                code = c.code, percent = c.percent,
                maxUses = c.maxUses, used = c.used,
            })
        end
        snap.totals  = AkaShopCore.totals(shop)
        snap.created = shop.created
        snap.tax     = AkaShop.getTaxPercent()

        -- Recent sales, newest first, straight out of the ring buffer.
        snap.sales = {}
        for _, r in ipairs(shop.recent or {}) do
            local what = {}
            for _, l in ipairs(r.lines or {}) do
                table.insert(what, (l.q or 1) .. "x " .. tostring(l.n))
            end
            table.insert(snap.sales, {
                when  = r.when,
                buyer = r.buyer,
                total = r.total,
                what  = table.concat(what, ", "),
                today = true,
            })
        end

        -- Day-by-day history, newest day first, for the same tab.
        local days = {}
        for k in pairs(shop.daily or {}) do table.insert(days, k) end
        table.sort(days, function(a, b) return a > b end)
        snap.days = {}
        for _, k in ipairs(days) do
            local d2 = shop.daily[k]
            table.insert(snap.days, { day = k, rev = d2.rev or 0, n = d2.n or 0 })
        end
        snap.older = shop.older or { rev = 0, n = 0 }
    end
    return snap
end

--- Lightweight table pushed to every client so context menus know what's what.
function AkaShopCore.index()
    local out = {}
    for k, s in pairs(AkaShopCore.db().shops) do
        out[k] = {
            name = s.name, nameTH = s.nameTH or "", owner = s.owner,
            enabled = s.enabled and true or false,
            x = s.x, y = s.y, z = s.z,
            -- The sprite MUST travel with the index. Without it the client has
            -- a shop's coordinates but no idea what to draw there, so the
            -- counter-restoring sweep silently repaired nothing and the tile
            -- looked like it vanished on every relog while the settings, which
            -- live in ModData and never depended on this, survived. That exact
            -- pair of symptoms - "settings fine, tile gone" - was this line.
            sprite = s.sprite or "",
            staff = staffList(s),
        }
    end
    return out
end

function AkaShopCore.adminSnapshot()
    local d = AkaShopCore.db()
    local shops = {}
    for k, s in pairs(d.shops) do
        local t = AkaShopCore.totals(s)
        table.insert(shops, {
            key = k, name = s.name, nameTH = s.nameTH or "", owner = s.owner,
            enabled = s.enabled and true or false,
            x = s.x, y = s.y, z = s.z,
            listings = #s.items,
            today = t.today, revenue = t.revenue, bank = t.bank,
            created = s.created,
        })
    end
    -- Depots ride in the same list. They are server furniture, so they get the
    -- server's name in the owner column and a zero till, and the admin's
    -- existing "Teleport to shop" button reaches them without a second tab.
    for k, p in pairs(d.buyers or {}) do
        local g = (d.buyGroups or {})[p.group]
        table.insert(shops, {
            key = k, name = (g and g.name or "Depot"), nameTH = (g and g.nameTH or ""),
            owner = "[DEPOT]", enabled = true, depot = true,
            x = p.x, y = p.y, z = p.z,
            listings = g and #(g.entries or {}) or 0,
            today = 0, revenue = 0, bank = 0, created = p.created,
        })
    end

    -- sort by the name that will actually be drawn, not the raw English field
    table.sort(shops, function(a, b)
        if a.owner == b.owner then return AkaShop.shopName(a) < AkaShop.shopName(b) end
        return a.owner < b.owner
    end)

    local reqs = {}
    for _, r in ipairs(d.requests) do
        table.insert(reqs, {
            id = r.id, user = r.user, name = r.name, nameTH = r.nameTH or "",
            x = r.x, y = r.y, z = r.z, when = r.when, sprite = r.sprite,
        })
    end

    local wl = {}
    for sprite in pairs(d.whitelist) do table.insert(wl, sprite) end
    table.sort(wl)

    return { shops = shops, requests = reqs, whitelist = wl,
             currency = AkaShop.getCurrencyName() }
end

--================================================================== boot ====

local function boot()
    local d = AkaShopCore.db()
    AkaShop.spriteWhitelist = d.whitelist
    local n = 0
    for _ in pairs(d.shops) do n = n + 1 end
    print("[Traka] core ready - " .. n .. " shop(s), " ..
          #d.requests .. " pending request(s)")
end

Events.OnInitGlobalModData.Add(boot)
Events.EveryOneMinute.Add(function()
    local ok, err = pcall(AkaShopCore.sweepTxns)
    if not ok then print("[Traka] txn sweep failed: " .. tostring(err)) end
end)
