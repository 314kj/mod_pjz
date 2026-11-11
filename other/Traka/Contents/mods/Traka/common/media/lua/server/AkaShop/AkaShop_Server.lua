--[[===========================================================================
    AkaShop - server side network layer.
    Receives client commands, checks permissions, calls AkaShopCore, answers.
    In singleplayer AkaShopClient.send() calls AkaShopServer.handle() directly
    and reply() loops straight back into AkaShopClient.onServerCommand().
============================================================================]]

AkaShopServer = AkaShopServer or {}

local function reply(player, cmd, args)
    args = args or {}

    -- Every hand-over in the mod - a purchase, a withdrawal, stock taken back
    -- off the shelf, the contents of a deleted shop - funnels through this one
    -- reply. In multiplayer it never leaves the server: the goods are built
    -- here, in the container the server actually owns, and the client is told
    -- to pull that container down again. See AkaShop_Give.lua for why there is
    -- no other way to do this correctly.
    if cmd == "give" and not AkaShop.isSP() and AkaShopGive and player then
        local made = AkaShopGive.toPlayer(player, args.items)
        AkaShopGive.report(made)

        -- ask the client to re-read its inventory from us
        sendServerCommand(player, AkaShop.NET, "pull", {})
        if args.text then
            sendServerCommand(player, AkaShop.NET, "msg",
                              { text = args.text, err = false })
        end
        -- the server counted what it built, so the transaction closes here
        -- rather than waiting for the client to report back
        if args.txn then
            AkaShopServer.handle(player, "gave", { txn = args.txn, n = made })
        end
        return
    end

    if AkaShop.isSP() then
        if AkaShopClient and AkaShopClient.onServerCommand then
            AkaShopClient.onServerCommand(cmd, args)
        end
    elseif player then
        sendServerCommand(player, AkaShop.NET, cmd, args)
    end
end
AkaShopServer.reply = reply

local function say(player, text, isError)
    reply(player, "msg", { text = tostring(text), err = isError and true or false })
end

local function pushIndex(player)
    -- The shop list just changed (or is being handed to someone new), so the
    -- server's own map of "which square should be carrying a counter" is
    -- rebuilt at the same moment the clients get theirs.
    if AkaShopTiles then pcall(AkaShopTiles.rebuild) end
    local payload = {
        index     = AkaShopCore.index(),
        depots    = AkaShopBuy.index(),
        whitelist = AkaShopCore.whitelistTable(),
        currency  = AkaShop.getCurrencyName(),
    }
    if AkaShop.isSP() then
        payload.pending = AkaShopCore.pendingFor(AkaShop.nameOf(getPlayer()))
        reply(player, "index", payload)
    else
        sendServerCommand(AkaShop.NET, "index", payload)
        if player then
            reply(player, "pending", { pending = AkaShopCore.pendingFor(AkaShop.nameOf(player)) })
        end
    end
end
AkaShopServer.pushIndex = pushIndex

--- `open` = true means "this is a window the player just asked for, show it".
--- Anything else is a refresh that must not pop a window open by itself.
local function pushShop(player, key, mode, open)
    -- The admin flag is read off the player rather than threaded down from the
    -- command context, because this is also called for OTHER people - the shop
    -- keeper watching an order complete, for one - and their access level is
    -- not the caller's.
    local snap = AkaShopCore.snapshot(key, mode, AkaShop.nameOf(player),
                                      AkaShop.isAdmin(player))
    if snap then reply(player, "shop", { snap = snap, open = open and true or false }) end
end

--- Tell whoever is minding the shop that something happened to it, if they
--- happen to be online. Best effort by design: an order that nobody sees today
--- is still waiting tomorrow, so a missed message costs nothing.
local function tellShopKeepers(shop, text)
    local seen = {}
    local function tell(n)
        if not n or n == "" or seen[n] then return end
        seen[n] = true
        local p = AkaShopOrders.playerNamed(n)
        if p then reply(p, "msg", { text = text, err = false }) end
    end
    tell(shop.owner)
    -- shop.staff is a SET keyed by username, not a list. Iterating it with
    -- ipairs would silently reach nobody.
    for username in pairs(shop.staff or {}) do tell(username) end
end

--- `open` = true means the player asked for this window; anything else is a
--- refresh that must not pop a window open by itself. Same rule as pushShop.
local function pushDepot(player, key, open, admin)
    local snap = AkaShopBuy.snapshot(key, AkaShop.nameOf(player), admin)
    if snap then reply(player, "depot", { snap = snap, open = open and true or false }) end
end

local function pushAdmin(player, open)
    reply(player, "admin", { data = AkaShopCore.adminSnapshot(), open = open and true or false })
end

local function tellRequester(username, text)
    local payload = { user = username, text = text }
    if AkaShop.isSP() then
        reply(nil, "reqResult", payload)
    else
        sendServerCommand(AkaShop.NET, "reqResult", payload)
    end
end

--=============================================================== handlers ===

local H = {}

function H.hello(ctx)
    pushIndex(ctx.player)
    -- A client that just joined has no idea whether shops are serving right
    -- now, and the flip broadcast only fires when the state CHANGES - which
    -- could be hours away. Hand them the current answer directly.
    reply(ctx.player, "mode", AkaShopServer.modePayload())
    -- Somebody just walked into the world. Their chunks are streaming in now,
    -- so this is the cheapest possible moment to put back any counter that went
    -- missing while nobody was there to notice.
    if AkaShopTiles then pcall(AkaShopTiles.sweep, "hello") end
end

--------------------------------------------------------------------- gates --

local function shopGate(ctx, key, level)
    local shop = AkaShopCore.getShop(key)
    if not shop then
        say(ctx.player, "Shop not found.", true)
        return nil
    end
    if level == "own" and not AkaShopCore.canOwn(shop, ctx.name, ctx.admin) then
        say(ctx.player, "Only the owner can do that.", true)
        return nil
    end
    if level == "manage" and not AkaShopCore.canManage(shop, ctx.name, ctx.admin) then
        say(ctx.player, "You are not allowed to manage this shop.", true)
        return nil
    end
    -- The staff level. Deliberately its own rung rather than a flag on
    -- "manage": the whole point of the split is that a staff member reaching a
    -- manage-level handler is a bug, and a separate rung makes that visible in
    -- the call site instead of hidden inside a boolean.
    if level == "orders" and not AkaShopCore.canOrders(shop, ctx.name, ctx.admin) then
        say(ctx.player, "You are not allowed to handle orders for this shop.", true)
        return nil
    end
    if not AkaShopCore.nearShop(ctx.player, shop, ctx.admin) then
        say(ctx.player, "You are too far from " .. AkaShop.shopBoth(shop) .. ".", true)
        return nil
    end
    return shop
end

--------------------------------------------------------------- open windows --

function H.open(ctx, a)
    local shop = AkaShopCore.getShop(a.key)
    if not shop then return say(ctx.player, "There is no shop here.", true) end
    if not AkaShopCore.nearShop(ctx.player, shop, ctx.admin) then
        return say(ctx.player, "You are too far from " .. AkaShop.shopBoth(shop) .. ".", true)
    end

    if a.mode == "manage" then
        -- Staff get in, but into a different window: the snapshot they are
        -- handed carries only the order queue. The gate is canOrders and the
        -- CONTENT is what enforces the rest, because a staff member who can
        -- open the window but sees nothing is far easier to reason about than
        -- one who is bounced at the door and cannot do the job you hired them
        -- for.
        if not AkaShopCore.canOrders(shop, ctx.name, ctx.admin) then
            return say(ctx.player, "You are not allowed to manage this shop.", true)
        end
        pushShop(ctx.player, a.key, "manage", true)
    else
        if not shop.enabled and not AkaShopCore.canOrders(shop, ctx.name, ctx.admin) then
            return say(ctx.player, "This shop is closed.", true)
        end
        pushShop(ctx.player, a.key, "buy", true)
    end
end

function H.adminList(ctx)
    if not ctx.admin then return say(ctx.player, "Admins only.", true) end
    pushAdmin(ctx.player, true)
end

------------------------------------------------------- registration & queue --

function H.register(ctx, a)
    if not ctx.admin then
        return say(ctx.player, "Only an admin can register a shop directly.", true)
    end
    local owner = a.owner or ctx.name
    -- An admin building a counter and keeping it is building server
    -- infrastructure: open around the clock, no orders, no trading window. An
    -- admin building one FOR a player is building that player's business, and
    -- it keeps player hours. The difference is who ends up owning it, so that
    -- is what decides.
    local serverShop = (owner == ctx.name)
    local ok, msg = AkaShopCore.register(owner, a.x, a.y, a.z,
                                         a.sprite, a.name, a.nameTH, true, serverShop)
    say(ctx.player, msg, not ok)
    if ok then
        local key = AkaShop.key(a.x, a.y, a.z)
        pushIndex(ctx.player)
        pushShop(ctx.player, key, "manage", true)
        -- Somebody just became a shopkeeper. Telling them is not a nicety:
        -- a shop nobody knows they own is a shop nobody ever stocks.
        if owner ~= ctx.name then
            local p = AkaShopOrders.playerNamed(owner)
            if p then
                reply(p, "msg", { text = ctx.name .. " set up " ..
                    AkaShop.shopBoth(AkaShopCore.getShop(key)) ..
                    " for you. Right-click the counter to stock it.", err = false })
                pushIndex(p)
            end
        end
    end
end

function H.request(ctx, a)
    if not AkaShopCore.near(ctx.player, a.x, a.y, a.z, false) then
        return say(ctx.player, "Stand next to the register you want to claim.", true)
    end
    local ok, msg = AkaShopCore.addRequest(ctx.name, a.x, a.y, a.z, a.sprite,
                                           a.name, a.nameTH)
    say(ctx.player, msg, not ok)
    if ok then pushIndex(ctx.player) end
end

function H.reqApprove(ctx, a)
    if not ctx.admin then return say(ctx.player, "Admins only.", true) end
    local ok, msg, r = AkaShopCore.approveRequest(a.id)
    say(ctx.player, msg, not ok)
    if ok then
        tellRequester(r.user, "Your shop request was approved: " .. AkaShop.shopBoth(r))
        pushIndex(ctx.player)
    end
    pushAdmin(ctx.player)
end

function H.reqDeny(ctx, a)
    if not ctx.admin then return say(ctx.player, "Admins only.", true) end
    local ok, msg, r = AkaShopCore.denyRequest(a.id)
    say(ctx.player, msg, not ok)
    if ok then
        tellRequester(r.user, "Your shop request was declined.")
        pushIndex(ctx.player)
    end
    pushAdmin(ctx.player)
end

function H.whitelistSprite(ctx, a)
    if not ctx.admin then return say(ctx.player, "Admins only.", true) end
    local ok, msg = AkaShopCore.setWhitelist(a.sprite, a.on and true or false)
    say(ctx.player, msg, not ok)
    if ok then
        pushIndex(ctx.player)
        pushAdmin(ctx.player)          -- refresh only, never pops the window
    end
end

--------------------------------------------------------------- owner tools --

function H.setName(ctx, a)
    if not shopGate(ctx, a.key, "own") then return end
    local ok, msg = AkaShopCore.setName(a.key, a.name, a.nameTH)
    say(ctx.player, msg, not ok)
    pushIndex(ctx.player); pushShop(ctx.player, a.key, "manage")
end

function H.setEnabled(ctx, a)
    if not shopGate(ctx, a.key, "own") then return end
    local ok, msg = AkaShopCore.setEnabled(a.key, a.on and true or false)
    say(ctx.player, msg, not ok)
    pushIndex(ctx.player)
    pushShop(ctx.player, a.key, "manage")
    if ctx.admin then pushAdmin(ctx.player) end
end

function H.deleteShop(ctx, a)
    if not shopGate(ctx, a.key, "own") then return end
    local ok, msg, give = AkaShopCore.deleteShop(a.key)
    if not ok then
        -- The shop is still there, so its window stays open: closing it would
        -- read as "deleted" to someone who did not read the message.
        say(ctx.player, msg, true)
        return pushShop(ctx.player, a.key, "manage")
    end
    reply(ctx.player, "give", { items = give or {}, text = msg })
    pushIndex(ctx.player)
    reply(ctx.player, "closeShop", { key = a.key })
    if ctx.admin then pushAdmin(ctx.player) end
end

--- Till -> Akacount. No items, so no transaction and no cap.
function H.toBank(ctx, a)
    if not shopGate(ctx, a.key, "own") then return end
    local ok, msg = AkaShopCore.toBank(a.key, ctx.name, a.amount, ctx.player)
    say(ctx.player, msg, not ok)
    pushShop(ctx.player, a.key, "manage")
end

--- Who is online, for the owner's staff picker.
---
--- The old Staff tab was a bare text box, so hiring somebody meant typing
--- their name from memory with no feedback if you got it wrong - which is why
--- it "did not work". The server is the only place that knows who is actually
--- connected, so it answers the question rather than the client guessing.
function H.whoOnline(ctx, a)
    -- Two callers, two shapes of the same question.
    --
    --   mode "staff" - hiring for an EXISTING shop. Needs that shop, needs
    --                  owner rights on it, and hides anybody already hired.
    --   mode "owner" - who should own a shop, which is also asked BEFORE the
    --                  shop exists. There is nothing to own yet, so the gate
    --                  is simply "are you an admin".
    local owner = (a.mode == "owner")
    local shop  = AkaShopCore.getShop(a.key)

    if owner then
        if not ctx.admin then return end
    else
        if not shop then return end
        if not AkaShopCore.canOwn(shop, ctx.name, ctx.admin) then return end
    end

    local me, out = ctx.name, {}
    local sx = (shop and shop.x) or tonumber(a.x) or 0
    local sy = (shop and shop.y) or tonumber(a.y) or 0

    local function add(p)
        local n = AkaShop.nameOf(p)
        if not n or n == "" then return end
        -- Hiring: you cannot be your own staff, and somebody already hired is
        -- not a candidate. Choosing an owner: everyone is fair game, including
        -- the admin doing the choosing.
        if not owner then
            if n == me then return end
            if AkaShopCore.isStaff(shop, n) then return end
        elseif n == me then
            return          -- "me" is offered by the window itself, not here
        end
        local dist
        pcall(function()
            local dx, dy = p:getX() - sx, p:getY() - sy
            dist = math.floor(math.sqrt(dx * dx + dy * dy))
        end)
        table.insert(out, { user = n, dist = dist or -1 })
    end

    if AkaShop.isSP() then
        add(getPlayer())
    else
        pcall(function()
            local list = getOnlinePlayers()
            if not list then return end
            for i = 0, list:size() - 1 do add(list:get(i)) end
        end)
    end

    -- Nearest first: the person you are hiring is usually the one standing in
    -- front of you.
    table.sort(out, function(x, y)
        if x.dist < 0 then return false end
        if y.dist < 0 then return true end
        return x.dist < y.dist
    end)
    reply(ctx.player, "whoOnline", { key = a.key, mode = a.mode or "staff",
                                     players = out })
end

--- Mark a shop as server infrastructure (24h) or as a normal player business.
--- Admin only: it decides which clock a counter keeps, which is a server
--- policy question, not a shopkeeper's.
function H.setAlwaysOpen(ctx, a)
    -- Checked inline rather than through adminOnly(): that helper is a `local`
    -- declared two hundred lines further down, so a closure written here would
    -- capture nothing and fail at call time with a nil call.
    if not ctx.admin then return say(ctx.player, "Admins only.", true) end
    local ok, msg = AkaShopCore.setAlwaysOpen(a.key, a.on)
    say(ctx.player, msg, not ok)
    pushIndex(ctx.player)
    pushShop(ctx.player, a.key, "manage")
end

function H.setOwner(ctx, a)
    if not shopGate(ctx, a.key, "own") then return end
    local ok, msg, was = AkaShopCore.setOwner(a.key, a.user, ctx.admin)
    say(ctx.player, msg, not ok)
    if not ok then return end

    pushIndex(ctx.player)
    -- Both ends of the handover deserve to be told, and the person who just
    -- gained a shop deserves it most - otherwise they own something they have
    -- no idea exists.
    local gained = AkaShopOrders.playerNamed(a.user)
    if gained then
        reply(gained, "msg", { text = "You are now the owner of " ..
            AkaShop.shopBoth(AkaShopCore.getShop(a.key)) .. ".", err = false })
    end
    if was and was ~= ctx.name then
        local lost = AkaShopOrders.playerNamed(was)
        if lost then
            reply(lost, "msg", { text = AkaShop.shopBoth(AkaShopCore.getShop(a.key)) ..
                " is now owned by " .. a.user .. ".", err = true })
        end
    end
    -- The person who pressed the button may no longer be allowed to see this
    -- window at all. Push them the snapshot their new standing earns.
    pushShop(ctx.player, a.key, "manage")
end

function H.addStaff(ctx, a)
    if not shopGate(ctx, a.key, "own") then return end
    local ok, msg = AkaShopCore.addStaff(a.key, a.user)
    say(ctx.player, msg, not ok); pushShop(ctx.player, a.key, "manage")
end

function H.delStaff(ctx, a)
    if not shopGate(ctx, a.key, "own") then return end
    local ok, msg = AkaShopCore.delStaff(a.key, a.user)
    say(ctx.player, msg, not ok); pushShop(ctx.player, a.key, "manage")
end

function H.clearSales(ctx, a)
    local shop = shopGate(ctx, a.key, "own")
    if not shop then return end
    shop.sales = {}
    say(ctx.player, "Sales history cleared.", false)
    pushShop(ctx.player, a.key, "manage")
end

function H.withdraw(ctx, a)
    if not shopGate(ctx, a.key, "own") then return end
    local ok, msg, req = AkaShopCore.beginWithdraw(a.key, ctx.name, a.amount)
    if not ok then
        say(ctx.player, msg, true)
        return pushShop(ctx.player, a.key, "manage")
    end
    reply(ctx.player, "give", { txn = req.txn, items = req.items })
end

------------------------------------------------------------------- stock ----

function H.addStock(ctx, a)
    if not shopGate(ctx, a.key, "manage") then return end
    local ok, msg, req = AkaShopCore.beginDeposit(a.key, ctx.player, ctx.name,
                                                  a.ft, a.qty, a.price)
    if not ok then
        say(ctx.player, msg, true)
        return pushShop(ctx.player, a.key, "manage")
    end
    reply(ctx.player, "take", { txn = req.txn, ft = req.ft, count = req.count })
end

function H.setPrice(ctx, a)
    if not shopGate(ctx, a.key, "manage") then return end
    local ok, msg = AkaShopCore.setPrice(a.key, a.uid, a.price)
    say(ctx.player, msg, not ok); pushShop(ctx.player, a.key, "manage")
end

--- Buy another block of shelf space out of the till.
function H.buyCapacity(ctx, a)
    local shop = shopGate(ctx, a.key, "own")
    if not shop then return end
    local ok, msg = AkaShopCore.buyCapacity(a.key)
    say(ctx.player, msg, not ok)
    if ok then pushShop(ctx.player, a.key, "manage") end
end

function H.takeStock(ctx, a)
    if not shopGate(ctx, a.key, "manage") then return end
    local ok, msg, req = AkaShopCore.beginTakeStock(a.key, ctx.name, a.uid, a.qty, false)
    if not ok then
        say(ctx.player, msg, true)
        return pushShop(ctx.player, a.key, "manage")
    end
    reply(ctx.player, "give", { txn = req.txn, items = req.items })
end

function H.removeListing(ctx, a)
    if not shopGate(ctx, a.key, "manage") then return end
    local ok, msg, req = AkaShopCore.beginTakeStock(a.key, ctx.name, a.uid, 0, true)
    if not ok then
        say(ctx.player, msg, true)
        return pushShop(ctx.player, a.key, "manage")
    end
    reply(ctx.player, "give", { txn = req.txn, items = req.items })
end

function H.addCode(ctx, a)
    if not shopGate(ctx, a.key, "manage") then return end
    local ok, msg = AkaShopCore.addCode(a.key, a.code, a.percent, a.maxUses)
    say(ctx.player, msg, not ok); pushShop(ctx.player, a.key, "manage")
end

function H.delCode(ctx, a)
    if not shopGate(ctx, a.key, "manage") then return end
    local ok, msg = AkaShopCore.delCode(a.key, a.code)
    say(ctx.player, msg, not ok); pushShop(ctx.player, a.key, "manage")
end

-------------------------------------------------------------------- buying --

function H.checkCode(ctx, a)
    local shop = AkaShopCore.getShop(a.key)
    if not shop then return say(ctx.player, "Shop not found.", true) end
    if not AkaShopCore.nearShop(ctx.player, shop, ctx.admin) then
        return say(ctx.player, "You are too far from that shop.", true)
    end
    if not shop.enabled then return say(ctx.player, "This shop is closed.", true) end

    local mayCheck, why = AkaShopCore.mayCheckCode(ctx.name)
    if not mayCheck then
        return reply(ctx.player, "codeInfo", {
            key = a.key, code = "", ok = false, percent = 0, text = why,
        })
    end

    local ok, percent, msg = AkaShopCore.checkCode(a.key, ctx.name, a.code)
    reply(ctx.player, "codeInfo", {
        key = a.key, code = AkaShop.normCode(a.code),
        ok = ok, percent = percent, text = msg,
    })
end

function H.buy(ctx, a)
    local shop = AkaShopCore.getShop(a.key)
    if not shop then return say(ctx.player, "Shop not found.", true) end
    if not AkaShopCore.nearShop(ctx.player, shop, ctx.admin) then
        return say(ctx.player, "You are too far from that shop.", true)
    end

    local ok, msg, charge = AkaShopCore.beginBuy(a.key, ctx.player, ctx.name,
                                                 a.cart, a.code, a.expect)
    if not ok then
        say(ctx.player, msg, true)
        return pushShop(ctx.player, a.key, "buy")
    end
    reply(ctx.player, "charge", { txn = charge.txn, cost = charge.cost, key = a.key })
end

------------------------------------------------------------------ orders ----

function H.order(ctx, a)
    local shop = AkaShopCore.getShop(a.key)
    if not shop then return say(ctx.player, "Shop not found.", true) end
    if not AkaShopCore.nearShop(ctx.player, shop, ctx.admin) then
        return say(ctx.player, "You are too far from that shop.", true)
    end

    local ok, msg, o = AkaShopCore.beginOrder(a.key, ctx.player, ctx.name,
                                              a.cart, a.code, a.expect)
    say(ctx.player, msg, not ok)
    if ok then
        tellShopKeepers(shop, "New order at " .. AkaShop.shopName(shop) .. ": " ..
            ctx.name .. ", " .. AkaShop.money(o.total) .. " " ..
            AkaShop.getCurrencyName() .. ". Open the shop's Orders tab.")
    end
    pushShop(ctx.player, a.key, "buy")
end

--- The customer changed their mind. Their own orders only - the shop keeper
--- turns orders away with orderDecline, which is a different verb on purpose
--- so the message each side reads is the truth about who did it.
function H.orderCancel(ctx, a)
    local shop = AkaShopCore.getShop(a.key)
    if not shop then return say(ctx.player, "Shop not found.", true) end
    local o = AkaShopOrders.find(shop, a.id)
    if not o then return say(ctx.player, "That order is gone.", true) end
    if o.buyer ~= ctx.name and not ctx.admin then
        return say(ctx.player, "That is not your order.", true)
    end
    local ok, msg = AkaShopOrders.dissolve(shop, a.id, "Order cancelled")
    say(ctx.player, ok and "Your order was cancelled." or msg, not ok)
    if ok then
        tellShopKeepers(shop, ctx.name .. " cancelled their order at " ..
                              AkaShop.shopName(shop) .. ".")
    end
    pushShop(ctx.player, a.key, "buy")
end

function H.orderDecline(ctx, a)
    -- Owner only. Declining dissolves the order and puts the goods back on
    -- sale; a destructive verb belongs to whoever owns the goods, and the
    -- staff role was asked for as "accept, and nothing else".
    local shop = shopGate(ctx, a.key, "own")
    if not shop then return end
    local ok, msg, o = AkaShopOrders.dissolve(shop, a.id, "Order declined")
    say(ctx.player, msg, not ok)
    if ok and o then
        local p = AkaShopOrders.playerNamed(o.buyer)
        if p then
            reply(p, "msg", { text = AkaShop.shopName(shop) ..
                " turned down your order.", err = true })
            pushShop(p, a.key, "buy")
        end
    end
    pushShop(ctx.player, a.key, "manage")
end

--- Phase 1 of the handover. The charge goes to the BUYER's client, not to the
--- shop keeper who pressed the button - they are the one with the money.
function H.orderHand(ctx, a)
    local shop = shopGate(ctx, a.key, "orders")
    if not shop then return end

    local ok, msg, req = AkaShopOrders.beginHand(shop, a.id, ctx.player, ctx.admin)
    if not ok then
        say(ctx.player, msg, true)
        return pushShop(ctx.player, a.key, "manage")
    end

    reply(req.buyer, "charge", { txn = req.txn, cost = req.cost, key = a.key })
    reply(req.buyer, "msg", { text = "Collecting order #" .. req.order.id ..
        " - paying " .. AkaShop.money(req.cost) .. " " ..
        AkaShop.getCurrencyName() .. ".", err = false })
    say(ctx.player, "Handing order #" .. req.order.id .. " to " ..
                    req.order.buyer .. "...", false)
end

------------------------------------------------------------------ depots ----
-- Everything here is admin-gated except openDepot and sell. A depot is server
-- furniture: players may use it, only an admin may shape it.

local function adminOnly(ctx)
    if ctx.admin then return true end
    say(ctx.player, "Admins only.", true)
    return false
end

function H.openDepot(ctx, a)
    if not AkaShopBuy.get(a.key) then
        return say(ctx.player, "There is no depot here.", true)
    end
    pushDepot(ctx.player, a.key, true, ctx.admin)
end

function H.depotCreate(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.create(a.x, a.y, a.z, a.sprite, a.name, a.nameTH)
    say(ctx.player, msg, not ok)
    if ok then
        pushIndex(ctx.player)
        pushDepot(ctx.player, AkaShop.key(a.x, a.y, a.z), true, true)
    end
end

function H.depotEnable(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.setEnabled(a.key, a.on)
    say(ctx.player, msg, not ok)
    pushIndex(ctx.player); pushDepot(ctx.player, a.key, false, true)
end

function H.depotRemove(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.remove(a.key)
    say(ctx.player, msg, not ok)
    pushIndex(ctx.player)
    reply(ctx.player, "closeDepot", { key = a.key })
end

function H.depotRename(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.rename(a.key, a.name, a.nameTH)
    say(ctx.player, msg, not ok)
    pushIndex(ctx.player); pushDepot(ctx.player, a.key, false, true)
end

function H.depotLink(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.link(a.key, a.other)
    say(ctx.player, msg, not ok)
    pushIndex(ctx.player); pushDepot(ctx.player, a.key, false, true)
end

function H.depotUnlink(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.unlink(a.key)
    say(ctx.player, msg, not ok)
    pushIndex(ctx.player); pushDepot(ctx.player, a.key, false, true)
end

function H.depotAdd(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.addEntry(a.key, a.ft, a.price, a.qty, a.minutes,
                                        a.colour, a.pay)
    say(ctx.player, msg, not ok)
    pushDepot(ctx.player, a.key, false, true)
end

function H.depotDel(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.delEntry(a.key, a.uid)
    say(ctx.player, msg, not ok)
    pushDepot(ctx.player, a.key, false, true)
end

function H.depotSet(ctx, a)
    if not adminOnly(ctx) then return end
    local ok, msg = AkaShopBuy.setEntry(a.key, a.uid, a.field, a.value)
    say(ctx.player, msg, not ok)
    pushDepot(ctx.player, a.key, false, true)
end

--- A player selling into a depot. Phase 1 only: reserve and ask for the goods.
function H.sellTo(ctx, a)
    local ok, msg, req = AkaShopBuy.beginSell(a.key, ctx.player, ctx.name,
                                              a.uid, a.qty, ctx.admin, a.ft)
    if not ok then
        say(ctx.player, msg, true)
        return pushDepot(ctx.player, a.key, false, ctx.admin)
    end
    -- noUnits: a depot destroys what it buys, so commitSell never looks at the
    -- condition of any of it. Shipping that table back would be a packet built
    -- entirely out of data nobody reads - and on a bulk sale of cheap goods it
    -- is the biggest packet the mod sends. ABSENT means "send them", so an old
    -- client talking to this server still stocks shops correctly.
    reply(ctx.player, "take", { txn = req.txn, ft = req.ft, count = req.count,
                                exact = req.exact, noUnits = true })
end

--============================================ phase 2: client confirmations ==

local DEPOSIT_KINDS = { deposit = true, depot_sell = true }
local PAYOUT_KINDS  = { payout_stock = true, payout_remove = true, payout_bank = true }
-- "order" rides the same confirmation as a purchase because it IS one: the
-- buyer's client is being asked for money and reports back what it paid. Only
-- the settlement differs, and H.paid branches on the kind to pick it.
local BUY_KINDS     = { buy = true, order = true }

--- The client reports how many units it actually removed from the seller.
--- Any failure hands the goods straight back - they have already left the
--- seller's inventory, so "reject" is never an option, only "return".
function H.took(ctx, a)
    local t = AkaShopCore.claimTxn(tonumber(a.txn), ctx.name, DEPOSIT_KINDS)
    if not t then return end

    -- The client says it handed the goods over. Make that true on the server,
    -- which is the copy a relog is rebuilt from - otherwise the player is paid
    -- for an item they still own the moment they reconnect. Clamped to the
    -- count this transaction authorised, never to what the client claims.
    local asked = math.floor((t.data or {}).count or 0)
    local moved = AkaShop.clampInt(a.n, 0, asked)
    if AkaShopTake and moved > 0 then
        pcall(AkaShopTake.reap, ctx.player, (t.data or {}).ft, moved)
    end

    -- The same "I handed the goods over" confirmation serves both directions:
    -- stocking your own shop, and selling into a depot. The txn kind decides,
    -- never the client - it is the only side that cannot be lied to.
    if t.kind == "depot_sell" then
        local ok, msg, pay = AkaShopBuy.commitSell(t, a.n)
        if pay and pay.items then
            reply(ctx.player, "give", { items = pay.items, text = msg })
        else
            say(ctx.player, msg, not ok)
        end
        return pushDepot(ctx.player, t.key, false, ctx.admin)
    end

    local ok, msg, back = AkaShopCore.commitDeposit(t, a.n, a.units)
    if back and back.items then
        reply(ctx.player, "give", { items = back.items, text = msg })
    else
        say(ctx.player, msg, not ok)
    end
    pushShop(ctx.player, t.key, "manage")
end

--- The client reports how many items/coins it actually created.
function H.gave(ctx, a)
    local t = AkaShopCore.claimTxn(tonumber(a.txn), ctx.name, PAYOUT_KINDS)
    if not t then return end
    local ok, msg
    if t.kind == "payout_bank" then
        ok, msg = AkaShopCore.commitWithdraw(t, a.n)
    else
        ok, msg = AkaShopCore.commitTakeStock(t, a.n)
    end
    say(ctx.player, msg, not ok)
    pushShop(ctx.player, t.key, "manage")
end

--- The client reports how much currency it actually handed over.
function H.paid(ctx, a)
    local t = AkaShopCore.claimTxn(tonumber(a.txn), ctx.name, BUY_KINDS)
    if not t then return end

    -- Money is the worse half of the same problem. An un-reaped payment is not
    -- a lost item, it is minted currency: the buyer keeps the coins AND the
    -- goods the moment they reconnect.
    local due  = math.floor((t.data or {}).total or 0)
    local paid = AkaShop.clampInt(a.n, 0, due)
    if AkaShopTake and paid > 0 then
        pcall(AkaShopTake.reapCurrency, ctx.player, paid)
    end

    local ok, msg, give
    if t.kind == "order" then
        ok, msg, give = AkaShopOrders.commitHand(t, a.n)
    else
        ok, msg, give = AkaShopCore.commitBuy(t, a.n)
    end

    if give and give.items then
        reply(ctx.player, "give", { items = give.items, text = msg })
    else
        say(ctx.player, msg, not ok)
    end
    pushShop(ctx.player, t.key, "buy")

    -- The shop keeper is standing right there watching, and their Orders tab
    -- is now one row out of date. Push them a fresh one rather than making
    -- them close and reopen the window to believe the handover happened.
    if t.kind == "order" then
        local shop = AkaShopCore.getShop(t.key)
        if shop then
            tellShopKeepers(shop, ctx.name .. " collected their order at " ..
                AkaShop.shopName(shop) .. " (" .. AkaShop.money(a.n or 0) .. ").")
            local keeper = AkaShopOrders.playerNamed(shop.owner)
            if keeper then pushShop(keeper, t.key, "manage") end
        end
    end
end

--============================================================== dispatcher ==

-- Commands that only read. Everything else is refused while the database is
-- locked, so a save written by a newer AkaShop can still be browsed but never
-- written into a shape this build would mangle.
local READ_ONLY_OK = {
    hello = true, index = true, shop = true, adminList = true, buyOpen = true,
}

function AkaShopServer.handle(player, command, args)
    local fn = H[command]
    if not fn then
        print("[Traka] unknown command: " .. tostring(command))
        return
    end

    AkaShopCore.db()                      -- forces the schema check on first use
    if AkaShopSchema.locked and not READ_ONLY_OK[command] then
        say(player, AkaShopSchema.lockMsg or
            "Traka is read-only: this save is newer than the installed mod.", true)
        return
    end

    local ctx = {
        player = player,
        name   = AkaShop.nameOf(player),
        admin  = AkaShop.isAdmin(player),
    }
    local ok, err = pcall(fn, ctx, args or {})
    if not ok then
        print("[Traka] error in '" .. tostring(command) .. "': " .. tostring(err))
        say(player, "Server error handling '" .. tostring(command) .. "'.", true)
    end
end

--=========================================================== hours watch ====
--[[ Whether a shop serves itself is a server fact that changes with the clock,
     and nothing was watching the clock. The mode was baked into a snapshot at
     the moment a window opened, so a shop window opened at 04:59 went on
     claiming ONLINE all night, and an admin who moved the trading hours to
     cover right now saw no change at all until something else happened to
     trigger a fresh snapshot.

     The watcher fires on the FLIP, not every tick. The state changes twice a
     day; broadcasting it every minute to every client would be pure chatter.
     The signature includes hoursText, so an admin editing the sandbox option
     mid-session counts as a flip too and is believed immediately. ]]

local lastModeSig = nil

local function modePayload()
    return {
        canBuyNow = AkaShop.onlineAllowedNow() and true or false,
        modeLabel = AkaShop.modeLabel(),
        hoursText = AkaShop.hoursText(),
    }
end
AkaShopServer.modePayload = modePayload

local function watchHours(force)
    local p   = modePayload()
    local sig = tostring(p.canBuyNow) .. "|" .. tostring(p.hoursText)
    if not force and sig == lastModeSig then return false end
    lastModeSig = sig
    if AkaShop.isSP() then
        reply(getPlayer(), "mode", p)
    else
        sendServerCommand(AkaShop.NET, "mode", p)
    end
    return true
end
AkaShopServer.watchHours = watchHours

Events.EveryOneMinute.Add(function()
    local ok, err = pcall(watchHours, false)
    if not ok then print("[Traka] hours watch failed: " .. tostring(err)) end
end)

-- Orders expire on the wall clock, so they are swept on the same tick. Ten
-- in-game minutes is roughly every twenty-five real seconds at the default day
-- length, which is far finer than an expiry measured in hours needs.
Events.EveryTenMinutes.Add(function()
    local ok, err = pcall(AkaShopOrders.sweep)
    if not ok then print("[Traka] order sweep failed: " .. tostring(err)) end
end)

if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= AkaShop.NET then return end
        AkaShopServer.handle(player, command, args)
    end)
    print("[Traka] server command listener installed")
end

-- Run the schema check at boot rather than on the first player interaction, so
-- a version problem shows up in console.txt before anybody trades.
Events.OnGameStart.Add(function()
    local d = AkaShopCore.db()
    if AkaShopSchema.locked then
        print("[Traka] ================ READ ONLY ================")
        print("[Traka] " .. tostring(AkaShopSchema.lockMsg))
        print("[Traka] ===========================================")
    else
        local n = 0
        for _ in pairs(d.shops) do n = n + 1 end
        print("[Traka] schema v" .. tostring(d.schema) .. ", " .. n .. " shops loaded")
    end
end)
