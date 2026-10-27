--[[===========================================================================
    Traka - counter orders.

    A shop has two ways to trade. During self-service hours it sells itself:
    the customer clicks Buy, pays, and walks off with the goods, and the server
    takes its cut. Outside those hours the goods are still on display but
    nobody is minding the till, and until now that was simply a refusal -
    "come back later, or find the owner" - with no way to find the owner and
    nothing to find them about.

    An ORDER is that missing half. The customer builds the same cart and puts
    it aside; the shop keeper sees it waiting the next time they open their
    shop; the two of them meet at the counter and the goods change hands.

    THREE RULES THAT SHAPE EVERYTHING HERE.

    1. Money moves at the HANDOVER, never at the order.
       Taking payment up front would mean holding it in escrow, and escrow
       means refunding a player who may have logged off for a week, or been
       eaten. Every one of those paths is a way to lose somebody's money. Pay
       at the counter and the problem does not exist: the buyer is standing
       right there, or the deal simply does not happen.

    2. Stock moves at the ORDER.
       The opposite call, for the opposite reason. If the goods stayed on the
       shelf, two customers could order the last axe and one of them would be
       told "sorry" by a shop that had already promised it. Reserved stock
       lives inside the order and goes back on the shelf if the order dies.

    3. Both parties stand at the counter.
       Not one, not "the owner is online somewhere". This mode exists to make
       players meet; a handover that works across the map is just self-service
       with extra clicks.

    NO FEE ON THIS PATH. The server's sales tax is rent on the automated till.
    An order is two players talking, so the shop keeps every coin of it.
============================================================================]]

AkaShopOrders = AkaShopOrders or {}
local O = AkaShopOrders

O.MAX_PER_SHOP  = 40      -- orders waiting at one shop
O.MAX_PER_BUYER = 3       -- open orders one player may hold at one shop

--============================================================== plumbing ====

local function nowSec()
    local t
    if pcall(function() t = getTimestamp() end) and type(t) == "number" then return t end
    if pcall(function() t = getTimestampMs() end) and type(t) == "number" then
        return math.floor(t / 1000)
    end
    return 0
end
O.nowSec = nowSec

--- Orders are only ever ADDED to, never assigned over: one careless
--- `shop.orders = {}` is how a server loses every promise it made.
local function bag(shop)
    if not shop.orders then shop.orders = {} end
    return shop.orders
end
O.bag = bag

local function nextId()
    local d = AkaShopCore.db()
    if not d.nextOrderId then d.nextOrderId = 1 end
    local id = d.nextOrderId
    d.nextOrderId = id + 1
    return id
end

function O.find(shop, id)
    id = tonumber(id)
    for i, o in ipairs(bag(shop)) do
        if o.id == id then return o, i end
    end
    return nil, nil
end

--- The IsoPlayer behind a username, or nil if they are not online.
--- Wrapped because getOnlinePlayers() does not exist in singleplayer.
function O.playerNamed(username)
    if not username or username == "" then return nil end
    if AkaShop.isSP() then
        local p = getPlayer()
        if p and AkaShop.nameOf(p) == username then return p end
        return nil
    end
    local found
    pcall(function()
        local list = getOnlinePlayers()
        if not list then return end
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p and AkaShop.nameOf(p) == username then found = p; break end
        end
    end)
    return found
end

--============================================================== placing =====

--- Turn a priced, stock-reserved cart into a waiting order.
---
--- `lines` arrives already validated and already holding its `states` - the
--- exact worn rows that were lifted off the shelf - because the pricing and
--- reserving live in AkaShopCore where the listing internals are. This
--- function owns the order record and nothing else.
function O.create(shop, buyerName, lines, subtotal, discount, total, codeStr)
    local o = {
        id       = nextId(),
        buyer    = buyerName,
        lines    = lines,
        subtotal = math.floor(subtotal or 0),
        discount = math.floor(discount or 0),
        total    = math.floor(total or 0),
        code     = codeStr,
        placed   = AkaShop.clockString(),
        at       = nowSec(),
    }
    table.insert(bag(shop), o)
    return o
end

function O.countFor(shop, buyerName)
    local n = 0
    for _, o in ipairs(bag(shop)) do
        if o.buyer == buyerName then n = n + 1 end
    end
    return n
end

function O.roomFor(shop, buyerName)
    if #bag(shop) >= O.MAX_PER_SHOP then
        return false, "This shop already has the maximum of " .. O.MAX_PER_SHOP ..
                      " orders waiting. Try again later."
    end
    if O.countFor(shop, buyerName) >= O.MAX_PER_BUYER then
        return false, "You already have " .. O.MAX_PER_BUYER ..
                      " orders waiting here. Collect or cancel one first."
    end
    return true
end

--============================================================== unwinding ===

--- Put an order's goods back on the shelf and drop it.
---
--- Used by decline, by cancel and by expiry, because all three mean the same
--- thing to the stock table: this promise is off. The reserved rows go back
--- exactly as they were taken, so a cancelled order restores the same chipped
--- axe rather than a fresh one.
function O.dissolve(shop, id, why)
    local o, i = O.find(shop, id)
    if not o then return false, "That order is gone." end
    if o.pending then
        return false, "That order is being handed over right now - try again in a moment."
    end

    for _, l in ipairs(o.lines or {}) do
        local e = AkaShopCore.findListing(shop, l.uid)
        if e then
            AkaShopStock.add(e, l.states or { { n = l.qty } })
        else
            -- The listing was deleted while the order waited. Recreate it
            -- rather than destroy the goods: the shop keeper took these off a
            -- customer's promise, not out of thin air.
            AkaShopCore.relist(shop, l.ft, l.name, l.price, l.states or { { n = l.qty } })
        end
    end
    if o.code then
        local c = AkaShopCore.findCode(shop, o.code)
        if c and (c.used or 0) > 0 then c.used = c.used - 1 end
    end

    table.remove(bag(shop), i)
    return true, (why or "Order cancelled") .. " - the goods are back on the shelf.", o
end

--- Orders do not wait forever. Stock sitting inside a promise nobody collects
--- is stock the shop cannot sell, so the shelf takes it back.
function O.sweep()
    local d = AkaShopCore.db()
    local ttl = AkaShop.orderHours() * 3600
    local now = nowSec()
    local gone = 0
    for _, shop in pairs(d.shops or {}) do
        local list = bag(shop)
        for i = #list, 1, -1 do
            local o = list[i]
            if not o.pending and (now - (o.at or now)) > ttl then
                local ok = O.dissolve(shop, o.id, "Order expired")
                if ok then
                    gone = gone + 1
                    local p = O.playerNamed(o.buyer)
                    if p and AkaShopServer then
                        AkaShopServer.reply(p, "msg", {
                            text = "Your order at " .. AkaShop.shopName(shop) ..
                                   " expired and was cancelled.", err = true })
                    end
                end
            end
        end
    end
    return gone
end

--- Seconds an order has left before it expires. Never negative.
function O.timeLeft(o)
    local left = (AkaShop.orderHours() * 3600) - (nowSec() - (o.at or nowSec()))
    if left < 0 then return 0 end
    return left
end

--============================================================== hand over ===

--- Phase 1 of the handover. Everything that can be checked before money moves
--- is checked here, and the order is marked `pending` so a second click - or a
--- cancel racing the handover - cannot double-spend it.
function O.beginHand(shop, id, ownerPlayer, admin)
    local o = O.find(shop, id)
    if not o then return false, "That order is gone." end
    if o.pending then return false, "That order is already being handed over." end

    if not AkaShopCore.nearShop(ownerPlayer, shop, admin) then
        return false, "Stand at the counter to hand an order over."
    end

    local buyer = O.playerNamed(o.buyer)
    if not buyer then
        return false, o.buyer .. " is not online. They have to come and collect it."
    end
    -- The buyer is never exempt from the distance check, not even an admin
    -- buyer: the whole point of this mode is that the two of them meet.
    if not AkaShopCore.near(buyer, shop.x, shop.y, shop.z, false) then
        return false, o.buyer .. " is not at the counter."
    end

    local wallet = AkaShop.countType(buyer:getInventory(), AkaShop.getCurrency(), buyer)
    if wallet < o.total then
        return false, o.buyer .. " only has " .. AkaShop.money(wallet) .. " of the " ..
                      AkaShop.money(o.total) .. " needed."
    end

    o.pending = true
    local txn = AkaShopCore.openTxn("order", o.buyer, shop.key, { id = o.id, total = o.total })
    return true, nil, { txn = txn, cost = o.total, buyer = buyer, order = o }
end

--- The buyer's client could not pay, or never answered. The goods stay in the
--- order: they were never on the shelf during the handover, and putting them
--- back would mint a duplicate the moment the owner tried again.
function O.rollbackHand(t)
    local shop = AkaShopCore.getShop(t.key)
    if not shop then return end
    local o = O.find(shop, (t.data or {}).id)
    if o then o.pending = nil end
end

--- Phase 2. The buyer paid; hand over the goods and pay the shop.
--- Returns ok, msg, give{ items = {...} }
function O.commitHand(t, paid)
    local d    = t.data or {}
    local shop = AkaShopCore.getShop(t.key)
    paid = math.floor(tonumber(paid) or 0)

    if not shop then
        -- The counter was scrapped mid-handover. The money has already left
        -- the buyer, so it goes straight back; the goods went with the shop.
        if paid > 0 then
            return false, "The shop vanished - you have been refunded.",
                { items = { { ft = AkaShop.getCurrency(), count = paid } } }
        end
        return false, "The shop vanished; nothing was charged."
    end

    local o, i = O.find(shop, d.id)
    if not o then
        if paid > 0 then
            return false, "That order was cancelled - you have been refunded.",
                { items = { { ft = AkaShop.getCurrency(), count = paid } } }
        end
        return false, "That order was cancelled."
    end

    if paid < (d.total or 0) then
        o.pending = nil
        return false, "Payment failed - the order is still waiting."
    end

    local give, logLines = {}, {}
    for _, l in ipairs(o.lines or {}) do
        local e = AkaShopCore.findListing(shop, l.uid)
        if e then e.sold = (e.sold or 0) + l.qty end
        table.insert(give, { ft = l.ft, count = l.qty, states = l.states })
        table.insert(logLines, { n = l.name, q = l.qty, u = l.price, ft = l.ft })
    end

    -- NO TAX. The server charges rent on the automated till, and this sale did
    -- not use it - two players stood at a counter and did it themselves.
    shop.bank    = math.floor((shop.bank or 0) + o.total)
    shop.revenue = math.floor((shop.revenue or 0) + o.total)
    AkaShopCore.recordSale(shop, o.buyer, o.total, logLines)

    table.remove(bag(shop), i)

    local msg = "Collected your order - paid " .. AkaShop.money(o.total)
    if (o.discount or 0) > 0 then
        msg = msg .. " (saved " .. AkaShop.money(o.discount) .. ")"
    end
    return true, msg, { items = give }
end

--============================================================== snapshots ===

local function lineText(o)
    local bits = {}
    for _, l in ipairs(o.lines or {}) do
        table.insert(bits, l.qty .. "x " .. tostring(l.name))
    end
    return table.concat(bits, ", ")
end

--- Everyone currently online, as a name set.
--- Built once per snapshot rather than once per order: this window repaints
--- whenever anybody moves, and walking the player list forty times to answer
--- forty copies of the same question is exactly the sort of thing that makes a
--- busy server stutter.
local function onlineSet()
    local set = {}
    if AkaShop.isSP() then
        local p = getPlayer()
        if p then set[AkaShop.nameOf(p)] = true end
        return set
    end
    pcall(function()
        local list = getOnlinePlayers()
        if not list then return end
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p then set[AkaShop.nameOf(p)] = true end
        end
    end)
    return set
end

--- What the shop keeper sees in the Orders tab.
function O.list(shop)
    local here, out = onlineSet(), {}
    for _, o in ipairs(bag(shop)) do
        table.insert(out, {
            id = o.id, buyer = o.buyer, total = o.total,
            what = lineText(o), placed = o.placed,
            left = O.timeLeft(o),
            here = here[o.buyer] == true,
            pending = o.pending and true or false,
        })
    end
    return out
end

--- What a customer sees about their OWN orders, and nothing about anyone
--- else's: who is buying what is the shop keeper's business.
function O.mine(shop, buyerName)
    local out = {}
    for _, o in ipairs(bag(shop)) do
        if o.buyer == buyerName then
            table.insert(out, {
                id = o.id, total = o.total, what = lineText(o),
                placed = o.placed, left = O.timeLeft(o),
            })
        end
    end
    return out
end
