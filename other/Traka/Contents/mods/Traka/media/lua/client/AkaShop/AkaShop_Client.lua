--[[===========================================================================
    AkaShop - client side network layer + world context menu.
============================================================================]]

AkaShopClient = AkaShopClient or {}

AkaShopClient.index    = {}      -- key -> { name, owner, enabled, x, y, z, staff }
AkaShopClient.pending  = {}      -- key -> true (my own pending requests)
AkaShopClient.currency = "Money"
AkaShopClient.gotIndex = false

--==================================================================== send ==

function AkaShopClient.me()
    return getSpecificPlayer(0) or getPlayer()
end

function AkaShopClient.myName()
    return AkaShop.nameOf(AkaShopClient.me())
end

function AkaShopClient.send(cmd, args)
    local pl = AkaShopClient.me()
    if not pl then return end
    if AkaShop.isSP() then
        if AkaShopServer and AkaShopServer.handle then
            AkaShopServer.handle(pl, cmd, args or {})
        end
    else
        sendClientCommand(pl, AkaShop.NET, cmd, args or {})
    end
end

--============================================================ sell queue ====
--[[ Selling a bag of jewellery in one click used to be one enormous request,
     and the frame it landed on did all of the work at once: the client hunted
     down two hundred rings and removed them, the server removed its own copy of
     each, and then the payout was MINTED - one instanceItem, one AddItem, one
     network announcement per single unit of currency. Two hundred rings at two
     hundred and fifty each is fifty thousand items built inside one frame. No
     amount of tidying the counting code fixes that; the work is real.

     So a bulk sale is a QUEUE, with one request in flight at a time.

     WHAT THE BATCH IS MEASURED IN, which is the whole lesson here. The first
     version counted items sold: three at a time, always. It fixed the freeze
     and ruined the feature. Somebody dumping thirty tin cans worth two coins
     each sat through eleven round trips to build sixty coins - a job the game
     could have done between two frames without anybody noticing. The cost was
     never in the cans. It was in the coins.

     So a batch is now as many items as fit inside a PAYOUT BUDGET. Under the
     budget the whole sale goes in a single request and behaves exactly as it
     did before any of this was written: one click, one hand-over, no pacing
     visible anywhere. Over the budget - and only there - it splits, because at
     that size there is no third option; the work is real and a frame is only so
     long.

     And there is no artificial delay between batches any more. Each one leaves
     as soon as the last comes back, which is one per frame at worst. Two
     hundred rings at two hundred and fifty each finishes in about a second
     instead of ten, and never stops the game while it does. ]]

local sellQ = {
    jobs   = {},        -- { key, uid, ft, want, lot, pay }
    busy   = false,     -- a request is out and has not come back
    sentAt = 0,         -- when the outstanding request left, for the watchdog
    total  = 0,         -- items in the whole run, for the progress readout
    sent   = 0,         -- requests this run has taken, so a single-batch sale
                        -- can be told from a paced one
    tokens = 0,         -- items this run is allowed to hand over right now
    tokAt  = 0,         -- when the bucket was last topped up
}

local SELL_WAIT  = 4000     -- ms before a silent request is assumed lost

local function nowMs()
    local t
    if pcall(function() t = getTimestampMs() end) and type(t) == "number" then return t end
    if pcall(function() t = getTimestamp() end) and type(t) == "number" then return t * 1000 end
    return 0
end

--- Items still waiting to be sold, and the total the run started with.
function AkaShopClient.sellProgress()
    local left = 0
    for _, j in ipairs(sellQ.jobs) do left = left + j.want end
    return left, sellQ.total
end

function AkaShopClient.sellBusy()
    return #sellQ.jobs > 0 or sellQ.busy
end

--- Is this run actually being PACED, or is it the ordinary one-request sale
--- that finishes before the next frame? The window asks so it can leave its
--- button alone in the common case: a progress readout that appears and
--- disappears within a frame is a flicker, not information.
function AkaShopClient.sellPaced()
    if not AkaShopClient.sellBusy() then return false end
    return sellQ.sent > 1 or #sellQ.jobs > 0
end

--- One batch has come back, so the next may go.
---
--- If nothing is left queued, that batch was the last one and the RUN is over -
--- so the counters are cleared here rather than on the next tick. Leaving them
--- to be tidied later meant a finished one-request sale still looked like a run
--- in progress until a frame went by, and the very next click inherited it.
function AkaShopClient.releaseSell()
    sellQ.busy = false
    if #sellQ.jobs == 0 then sellQ.total, sellQ.sent = 0, 0 end
end

--- Will this run have to be paced? Asked BEFORE the first batch goes, so the
--- window knows whether to put the character to work behind a progress bar or
--- just let the sale happen.
function AkaShopClient.sellWillPace()
    local budget, worst = AkaShop.sellBudget(), 0
    local total = 0
    for _, j in ipairs(sellQ.jobs) do
        total = total + j.want
        worst = worst + j.want * j.pay
    end
    if #sellQ.jobs > 1 then return true end
    return worst > budget
end

function AkaShopClient.cancelSell(why)
    local running = (#sellQ.jobs > 0) or sellQ.busy
    sellQ.jobs, sellQ.busy, sellQ.total, sellQ.sent = {}, false, 0, 0
    sellQ.tokens, sellQ.tokAt = 0, 0
    if running and why then AkaShopClient.notify(why, true) end
end

--- Add one item type to the run.
--- `lot` is the barter lot size, 1 for money.
--- `pay` is what ONE of this item causes to be BUILT - the price on a money
--- row, or payout-per-lot over the lot on a barter one. The batch size is
--- computed from it, and 0 (a depot that only destroys things) means the whole
--- lot can go at once, because nothing is built at all.
function AkaShopClient.queueSell(key, uid, ft, want, lot, pay)
    want = math.floor(tonumber(want) or 0)
    if want < 1 then return end
    if #sellQ.jobs == 0 and not sellQ.busy then
        -- A fresh run starts with a full second in hand, so the first batch of
        -- a paced sale leaves immediately rather than after a pause.
        sellQ.tokens, sellQ.tokAt = AkaShop.sellRate(), nowMs()
    end
    table.insert(sellQ.jobs, { key = key, uid = uid, ft = ft, want = want,
                               lot = math.max(1, math.floor(lot or 1)),
                               pay = math.max(0, tonumber(pay) or 0) })
    sellQ.total = sellQ.total + want
end

local function pumpSell()
    if sellQ.busy then
        -- A request that never came back must not wedge the queue forever. The
        -- server refusing is a message; the server dying is silence, and only
        -- the clock can tell the difference.
        if nowMs() - sellQ.sentAt > SELL_WAIT then sellQ.busy = false
        else return end
    end
    local j = sellQ.jobs[1]
    if not j then
        if sellQ.total > 0 then sellQ.total, sellQ.sent = 0, 0 end
        return
    end

    -- Re-read what is actually in the bag rather than trusting a count taken
    -- before the run started. Items leave a player by routes this queue never
    -- hears about, and asking for what is no longer there is how a bulk sale
    -- ends in a burst of red error text.
    local have = AkaShopUI and AkaShopUI.stockCount(j.ft) or j.want
    local n = math.min(j.want, have)

    -- How many fit in one frame's worth of item building. A row that pays
    -- nothing, or pays so little that the whole pile is affordable, is not
    -- capped at all - and that is the ordinary case, which is why most sales
    -- never split.
    if j.pay > 0 then
        local room = math.floor(AkaShop.sellBudget() / j.pay)
        if room < 1 then room = 1 end
        if n > room then n = room end
    end

    -- IS THIS RUN GOING TO SPLIT? Everything about how it feels hangs on that
    -- one question, and it is answered by comparing this batch against what is
    -- left. A sale that finishes here is instant - no rate, no bar, no waiting,
    -- exactly as it behaved before any pacing existed.
    local remaining = 0
    for _, other in ipairs(sellQ.jobs) do remaining = remaining + other.want end

    if n < remaining then
        -- A big one. Hand it over at a steady rate the player can watch, rather
        -- than as fast as the network happens to allow. The bucket fills at
        -- sellRate per second and every item handed over spends a token, so the
        -- pace holds however many small batches the budget forces underneath.
        local now  = nowMs()
        local rate = AkaShop.sellRate()
        local dt   = math.max(0, now - (sellQ.tokAt or now)) / 1000
        sellQ.tokAt  = now
        sellQ.tokens = math.min(rate, (sellQ.tokens or 0) + rate * dt)

        local allow = math.floor(sellQ.tokens)
        if allow < 1 then return end
        if n > allow then n = allow end
    end

    n = math.floor(n / j.lot) * j.lot
    -- A lot costing more than the whole budget, or more than a second's worth
    -- of tokens, still has to go as one whole lot: half a trade is not a trade.
    -- It simply borrows against the next second.
    if n < j.lot and j.want >= j.lot and have >= j.lot then n = j.lot end

    if n < 1 then
        table.remove(sellQ.jobs, 1)
        return
    end

    j.want = j.want - n
    if j.want < 1 then table.remove(sellQ.jobs, 1) end

    sellQ.busy   = true
    sellQ.sentAt = nowMs()
    sellQ.sent   = sellQ.sent + 1
    sellQ.tokens = (sellQ.tokens or 0) - n
    AkaShopClient.send("sellTo", { key = j.key, uid = j.uid, qty = n, ft = j.ft })
end

Events.OnTick.Add(pumpSell)

--================================================================= notify ===

function AkaShopClient.notify(text, isErr)
    local pl = AkaShopClient.me()
    if not pl then print("[Traka] " .. tostring(text)) return end
    local done = false
    if HaloTextHelper then
        if isErr and HaloTextHelper.addBadText then
            done = pcall(function() HaloTextHelper.addBadText(pl, tostring(text)) end)
        elseif HaloTextHelper.addGoodText then
            done = pcall(function() HaloTextHelper.addGoodText(pl, tostring(text)) end)
        end
    end
    if not done then
        pcall(function()
            if isErr then pl:setHaloNote(tostring(text), 240, 90, 90, 300)
            else pl:setHaloNote(tostring(text), 150, 240, 150, 300) end
        end)
    end
    print("[Traka] " .. tostring(text))
end

--======================================================= permission helpers =

function AkaShopClient.shopAt(x, y, z)
    return AkaShopClient.index[AkaShop.key(x, y, z)]
end

function AkaShopClient.canManage(entry)
    if not entry then return false end
    if AkaShop.isAdmin(AkaShopClient.me()) and AkaShop.adminCanEditAny() then return true end
    local me = AkaShopClient.myName()
    if entry.owner == me then return true end
    for _, u in ipairs(entry.staff or {}) do
        if u == me then return true end
    end
    return false
end

function AkaShopClient.isOwner(entry)
    if not entry then return false end
    if AkaShop.isAdmin(AkaShopClient.me()) and AkaShop.adminCanEditAny() then return true end
    return entry.owner == AkaShopClient.myName()
end

--=========================================================== server -> me ===

local handlers = {}

function handlers.msg(a)
    -- An error in the middle of a bulk sale stops the whole run. Walking away
    -- from the counter halfway through would otherwise produce one "you are too
    -- far from the depot" per remaining batch, which is thirty red messages for
    -- one mistake.
    if a.err and AkaShopClient.sellBusy() then
        AkaShopClient.cancelSell(nil)
    end
    AkaShopClient.notify(a.text, a.err)
end

--- Rebuild the x -> y -> anchor lookup used by AkaShop_Restore.lua.
--- LoadGridsquare fires for every square the game streams in, so that hook has
--- to reject a miss with one integer index and no string building at all.
local function rebuildAnchors()
    local byX = {}
    local function add(e)
        if not (e.sprite and e.sprite ~= "") then return end
        local col = byX[e.x]
        if not col then col = {}; byX[e.x] = col end
        col[e.y] = { z = e.z, sprite = e.sprite }
    end
    for _, e in pairs(AkaShopClient.index) do add(e) end
    -- Depots stand on the same kind of counter and go missing the same way, so
    -- they belong in the same repair list. Leaving them out would have made
    -- "the tile vanished" a bug we fixed once and then re-shipped.
    for _, e in pairs(AkaShopClient.depots or {}) do add(e) end
    AkaShopClient.anchors = byX
end

function handlers.index(a)
    AkaShopClient.index    = a.index or {}
    AkaShopClient.depots   = a.depots or {}
    AkaShopClient.currency = a.currency or AkaShopClient.currency
    AkaShopClient.gotIndex = true
    if a.whitelist then AkaShop.spriteWhitelist = a.whitelist end
    if a.pending then AkaShopClient.pending = a.pending end
    rebuildAnchors()
    -- Squares that streamed in before this index arrived never fired
    -- LoadGridsquare for us, so repair them now. This is the teleport case.
    if AkaShopRestore then pcall(AkaShopRestore.sweep, "index") end
end

function handlers.pending(a)
    AkaShopClient.pending = a.pending or {}
end

--- The same answer feeds two windows. The owner picker wins when it is open,
--- because it is modal in spirit: an admin who has it up in front of them is
--- waiting on this list, not on the manage window behind it.
function handlers.whoOnline(a)
    local pick = AkaShopOwnerPick and AkaShopOwnerPick.instance
    if a.mode == "owner" and pick then
        return pcall(function() pick:fill(a.players or {}) end)
    end
    local ui = AkaShopManageUI and AkaShopManageUI.instance
    if ui and ui.shopKey == a.key and ui.fillOnline then
        pcall(function() ui:fillOnline(a.players or {}) end)
    end
end

--- The self-service window opened or closed, or an admin moved the hours.
---
--- Patched into the open windows in place rather than asking the server for a
--- fresh snapshot: three fields changed, and a snapshot round trip would also
--- throw away whatever the customer had already put in their cart.
function handlers.mode(a)
    AkaShopClient.mode = a
    local function patch(ui)
        if not (ui and ui.snap and ui.refresh) then return end
        -- A server shop is not on the server's clock, so the server's clock
        -- flipping says nothing about it. Patching it here would slam a 24h
        -- counter shut at 5am on the strength of a broadcast that was never
        -- about it.
        if ui.snap.alwaysOpen then return end
        ui.snap.canBuyNow = a.canBuyNow
        ui.snap.modeLabel = a.modeLabel
        ui.snap.hoursText = a.hoursText
        pcall(function() ui:refresh(ui.snap) end)
    end
    patch(AkaShopBuyUI    and AkaShopBuyUI.instance)
    patch(AkaShopManageUI and AkaShopManageUI.instance)
end

function handlers.reqResult(a)
    if a.user == AkaShopClient.myName() then
        AkaShopClient.notify(a.text, false)
        AkaShopClient.send("hello", {})
    end
end

--- `a.open` marks a window the player explicitly asked for. Everything else is
--- a refresh, and a refresh must never pop a window open on its own.
function handlers.shop(a)
    local snap = a.snap
    if not snap then return end
    if snap.mode == "buy" then
        local live = AkaShopBuyUI.instance
        if a.open or (live and live.shopKey == snap.key) then
            AkaShopBuyUI.openWith(snap)
        end
    else
        local live = AkaShopManageUI.instance
        if a.open or (live and live.shopKey == snap.key) then
            AkaShopManageUI.openWith(snap)
        end
    end
end

function handlers.closeShop(a)
    if AkaShopManageUI and AkaShopManageUI.instance
        and AkaShopManageUI.instance.shopKey == a.key then
        AkaShopManageUI.instance:close()
    end
    if AkaShopBuyUI and AkaShopBuyUI.instance
        and AkaShopBuyUI.instance.shopKey == a.key then
        AkaShopBuyUI.instance:close()
    end
end

function handlers.admin(a)
    if a.open or AkaShopAdminUI.instance then
        AkaShopAdminUI.openWith(a.data)
    end
end

function handlers.depot(a)
    if a.open or AkaShopDepotUI.instance then
        AkaShopDepotUI.openWith(a.snap)
    end
end

function handlers.closeDepot(a)
    AkaShopDepotUI.closeKey(a.key)
end

function handlers.codeInfo(a)
    local ui = AkaShopBuyUI and AkaShopBuyUI.instance
    if ui and ui.shopKey == a.key then
        ui:setCode(a.code, a.percent, a.ok, a.text)
    else
        AkaShopClient.notify(a.text, not a.ok)
    end
end

--[[ Phase 2 of every transfer.
     The server has already validated and reserved; these handlers do the actual
     inventory change and report back the REAL number moved, so the server can
     commit exactly that much (or roll the reservation back). Nothing is ever
     credited or debited on the strength of what the client merely asked for. ]]

--- Take items off the seller after the server approved a deposit.
function handlers.take(a)
    local moved, units = AkaShop.removeItemsWithState(AkaShopClient.me(), a.ft,
                                                      a.count, a.exact)
    if a.exact and moved < 1 then
        AkaShopClient.notify("You no longer have enough for that trade - " ..
                             "nothing was taken.", true)
    end
    -- Only the shop deposit path reads the condition breakdown; a depot sale
    -- does not. See noUnits in AkaShop_Server.
    if a.noUnits then units = nil end
    AkaShopClient.send("took", { txn = a.txn, n = moved, units = units })
    -- The goods have left the player, so this batch is finished as far as the
    -- queue is concerned; the payout the server is about to build is its own
    -- problem. Releasing here rather than on the payout keeps the pacing tied
    -- to round trips instead of to how expensive the change was to count out.
    AkaShopClient.releaseSell()
end

--- Receive goods or money.
--- SINGLEPLAYER ONLY. In multiplayer the server builds the items itself and
--- never sends this command, because a client cannot create an item the server
--- will accept: ItemContainer has removeItemOnServer but no addItemOnServer.
--- Anything made here in multiplayer would be a ghost.
function handlers.give(a)
    if not AkaShop.isSP() then return end
    local pl = AkaShopClient.me()
    local made = 0
    for _, g in ipairs(a.items or {}) do
        if g.states and #g.states > 0 then
            made = made + AkaShop.giveItemsWithState(pl, g.ft, g.states)
        else
            made = made + AkaShop.giveItems(pl, g.ft, g.count)
        end
    end
    if a.txn then AkaShopClient.send("gave", { txn = a.txn, n = made }) end
    if a.text then AkaShopClient.notify(a.text, false) end
end

--- "Your inventory changed on my side."
---
--- REDRAW ONLY. The items themselves arrive on their own, pushed by the
--- server's sendAddItemToContainer; all this does is stop the panel drawing a
--- stale list until the next mouse-over.
---
--- v2.8.0 called requestServerItemsForContainer() here and that was a mistake
--- worth writing down: it asks the server to REPLACE this container's contents
--- with the server's copy. On a world crate that is exactly right. On the
--- player's own inventory - which the client, not the server, is authoritative
--- for - it means handing your bag over to whatever the server happened to
--- think was in it. Purchases vanished. Never point that call at a player.
function handlers.pull()
    local pl = AkaShopClient.me()
    local inv = pl and pl:getInventory()
    if not inv then return end
    pcall(function() inv:setDrawDirty(true) end)
    pcall(function()
        local page = getPlayerInventory(pl:getPlayerNum())
        if page then page:refreshBackpacks() end
    end)
end

--- Pay for a purchase the server has already reserved. All-or-nothing: a
--- half-paid basket would be worse than a failed one.
function handlers.charge(a)
    local cost = math.floor(a.cost or 0)
    local paid = 0
    if cost > 0 then
        paid = AkaShop.removeItems(AkaShopClient.me(), AkaShop.getCurrency(), cost, true)
    end
    AkaShopClient.send("paid", { txn = a.txn, n = paid })

    if paid < cost then
        AkaShopClient.notify("Payment failed - not enough " ..
            AkaShop.getCurrencyName() .. " on you.", true)
        return
    end
    local ui = AkaShopBuyUI and AkaShopBuyUI.instance
    if ui and ui.shopKey == a.key then
        ui.cart = {}
        ui.cartList.selected = 0
        ui:refreshCart()
    end
end

-- Anything on this list can leave the player's bag holding something different
-- from a moment ago, so the cached inventory index is thrown away before the
-- handler runs rather than being allowed to age out. Everything else - a shop
-- snapshot, an admin list - cannot touch the bag and must not pay for a walk.
local MOVES_ITEMS = { take = true, give = true, pull = true, charge = true }

function AkaShopClient.onServerCommand(command, args)
    local fn = handlers[command]
    if not fn then return end
    if MOVES_ITEMS[command] and AkaShopUI then AkaShopUI.stockDirty() end
    local ok, err = pcall(fn, args or {})
    if not ok then print("[Traka] client handler '" .. tostring(command) ..
                         "' failed: " .. tostring(err)) end
    if MOVES_ITEMS[command] and AkaShopUI then AkaShopUI.stockDirty() end
end

-- Harmless in singleplayer (never fires there); registered unconditionally so
-- the listener exists no matter when isClient() becomes meaningful.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AkaShop.NET then return end
    if AkaShop.isSP() then return end
    AkaShopClient.onServerCommand(command, args)
end)

--================================================================ teleport ==

-- Confirmed from console.txt: the previous attempt called pl:setLx/setLy/setLz,
-- which do not exist on B42's IsoPlayer. The whole move ran inside one pcall,
-- so the first nil method aborted the entire thing and every teleport reported
-- "Teleport failed" - near ones included. Two changes:
--
--   * on a server, hand the job to the vanilla admin command. It runs server
--     side, which is the only place that can actually relocate a character
--     across cells, and it is the same path the built-in admin panel uses.
--   * in singleplayer, set only the setters that exist, each on its own, then
--     wait for the destination square to stream in before binding to it.

local settling = nil

--- Call obj:name(v) only if that method exists on this build. Never varargs:
--- `unpack` is not something to rely on inside Kahlua, and every caller here
--- passes exactly one value anyway.
local function callIf(obj, name, v)
    if not obj or type(obj[name]) ~= "function" then return false end
    return (pcall(function() obj[name](obj, v) end))
end

function AkaShopClient.teleport(x, y, z)
    local pl = AkaShopClient.me()
    if not pl then return end
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)

    if settling then
        Events.OnTick.Remove(settling)
        settling = nil
    end

    -- Multiplayer: let the server move us. Distance stops being our problem.
    if not AkaShop.isSP() then
        local sent = pcall(function()
            SendCommandToServer("/teleportto " .. x .. "," .. y .. "," .. z)
        end)
        if sent then
            AkaShopClient.notify("Teleporting to " .. x .. ", " .. y .. "...", false)
            -- give the server a moment, then resync the shop index and repair
            local n = 0
            local function after()
                n = n + 1
                if n < 120 then return end          -- ~2 seconds
                Events.OnTick.Remove(after)
                settling = nil
                AkaShopClient.send("hello", {})
                if AkaShopRestore then pcall(AkaShopRestore.sweep, "teleport") end
            end
            settling = after
            Events.OnTick.Add(after)
            return
        end
        -- command refused (not an admin, or no such command): fall through
    end

    local moved = callIf(pl, "setX", x + 0.5)
    callIf(pl, "setY", y + 0.5)
    callIf(pl, "setZ", z)
    -- these three only exist on some builds; a missing one must not abort
    callIf(pl, "setLx", x + 0.5)
    callIf(pl, "setLy", y + 0.5)
    callIf(pl, "setLz", z)
    if not moved then
        return AkaShopClient.notify("Teleport failed - this build will not let " ..
                                    "the mod move your character.", true)
    end
    AkaShopClient.notify("Travelling to " .. x .. ", " .. y .. "...", false)

    local tries = 0
    local function settle()
        tries = tries + 1
        local sq
        pcall(function()
            local cell = getCell()
            sq = cell and cell:getGridSquare(x, y, z)
        end)
        if sq then
            callIf(pl, "setSquare", sq)
            callIf(pl, "setX", x + 0.5)
            callIf(pl, "setY", y + 0.5)
            callIf(pl, "setZ", z)
            Events.OnTick.Remove(settle)
            settling = nil
            AkaShopClient.notify("Arrived at " .. x .. ", " .. y .. ".", false)
            AkaShopClient.send("hello", {})
            if AkaShopRestore then pcall(AkaShopRestore.sweep, "teleport") end
        elseif tries > 900 then
            Events.OnTick.Remove(settle)
            settling = nil
            AkaShopClient.notify("Moved, but that chunk never finished loading.", true)
        end
    end
    settling = settle
    Events.OnTick.Add(settle)
end

--=========================================================== context menu ===

local function squareFromWorldObjects(worldobjects)
    for i = 1, #worldobjects do
        local o = worldobjects[i]
        if o and o.getSquare then
            local sq = o:getSquare()
            if sq then return sq end
        end
    end
    return nil
end

local function doRegisterFlow(playerNum, sq, obj, asAdmin)
    local pl = getSpecificPlayer(playerNum)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local sprite = AkaShop.spriteNameOf(obj) or ""

    -- A player asking for their own shop. Nothing to choose: it is theirs by
    -- definition, and an admin approves it later.
    if not asAdmin then
        AkaShopUI.askNames("Request a shop (an admin must approve it)",
                           AkaShop.nameOf(pl) .. "'s Shop", "",
            function(nameEN, nameTH)
                AkaShopClient.send("request", {
                    x = x, y = y, z = z, sprite = sprite,
                    name = nameEN, nameTH = nameTH,
                })
            end)
        return
    end

    -- An admin. Ask WHO IT IS FOR first, because the answer is almost never
    -- "me" - an admin standing at a counter setting up a shop is setting it up
    -- for somebody else, and the old flow silently made the admin the owner of
    -- every shop they built.
    AkaShopOwnerPick.open("Who is this shop for?", function(username)
        AkaShopUI.askNames("Name " .. username .. "'s shop",
                           username .. "'s Shop", "",
            function(nameEN, nameTH)
                AkaShopClient.send("register", {
                    x = x, y = y, z = z, sprite = sprite,
                    owner = username,
                    name = nameEN, nameTH = nameTH,
                })
            end)
    end, { query = { mode = "owner", x = x, y = y },
           note = "The shop, its stock and its till will belong to whoever you pick." })
end

--- Nested one level deeper than it used to be: it is handed the AKA Mod
--- submenu, not the root context, so admin tools sit beside the player ones
--- instead of beside "Walk to".
--- Fills the "AKA Mod" menu with the server-wide admin tools.
---
--- Writes straight into the menu it is given. It used to add its own "Traka
--- (Admin)" submenu inside the parent, which made every one of these three
--- entries three clicks deep - and now that the parent contains nothing BUT
--- admin tools, a level called "admin" inside a menu that is already admin
--- only was a signpost pointing at itself.
local function buildAdminSubmenu(menu, playerNum, obj)
    menu:addOption("Shop Manager...", nil, function()
        AkaShopClient.send("adminList", {})
    end)

    if obj then
        local sprite = AkaShop.spriteNameOf(obj)
        if sprite then
            local o = menu:addOption("Tile: " .. sprite, nil, nil)
            o.notAvailable = true
            -- This is the admin allow-list of tiles players may claim. It is
            -- NOT the player's permission request; that lives on the normal
            -- right-click menu as "Request permission to open a shop here".
            if AkaShop.spriteWhitelist[sprite] then
                menu:addOption("Remove this tile from the shop allow-list", nil, function()
                    AkaShopClient.send("whitelistSprite", { sprite = sprite, on = false })
                end)
            else
                menu:addOption("Allow this tile to be claimed as a shop", nil, function()
                    AkaShopClient.send("whitelistSprite", { sprite = sprite, on = true })
                end)
            end
        end
    end
end

--[[ MENU LAYOUT, and why it changed.

     Everything used to hang off one "AKA Mod" parent. That is the polite thing
     to do with a shared surface like the right-click menu, and it is still
     what happens to the server-wide admin tools. But it turned out to cost
     more than it saved, in two ways.

     One: it put a click between a customer and the shop they are standing in
     front of, for a verb the tile exists to offer.

     Two, and worse: it hid the difference between a player's shop and an
     admin's buy-back counter. Both were "AKA Mod ▸ something At Shop", and
     "Buy At Shop" against "Sell At Shop" is a one-word difference read at a
     glance in a list of grey rows. Admins genuinely could not tell which tile
     was which.

     So the rule is now: if the verb acts on THE TILE YOU CLICKED, it is a
     top-level row and it names the shop. If it is a server-wide tool that
     happens to be reachable from anywhere, it stays under "AKA Mod".

     The labels changed with it. Every one now leads with a verb that says
     which way the money moves - "Buy from", "Sell to" - and every admin-only
     row is suffixed "(admin)" so an admin can see at a glance which rows the
     players around them can also see. ]]

--- Admin rows get a suffix rather than a colour, because a context menu gives
--- no reliable way to colour one row and a suffix survives every skin.
local ADMIN = "   (admin)"

local function onFillWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    local pl = getSpecificPlayer(playerNum)
    if not pl then return end

    if not AkaShopClient.gotIndex then AkaShopClient.send("hello", {}) end

    local sq = squareFromWorldObjects(worldobjects)
    if not sq then return end

    local admin = AkaShop.isAdmin(pl)
    local key   = AkaShop.key(sq:getX(), sq:getY(), sq:getZ())
    local entry = AkaShopClient.index[key]
    local depot = (AkaShopClient.depots or {})[key]
    local obj   = AkaShop.findCashier(sq, admin and AkaShop.adminAnyObject())

    if not (entry or depot or obj or admin) then return end

    -- Top-level rows are added in reverse, because addOptionOnTop puts each
    -- new row above the last. Building the list first and walking it backwards
    -- keeps the code reading in the order the player sees.
    local rows = {}
    local function row(text, fn) table.insert(rows, { text = text, fn = fn }) end

    if depot then
        ------------------------------------------------------------ depot tile
        -- The depot BUYS, so the player's verb is "sell". Saying so in the
        -- label is the entire fix for "which one is the admin counter".
        local shut = (depot.enabled == false)
        row("Sell to " .. AkaShop.shopName(depot) ..
            (shut and "   (CLOSED)" or ("   [buying " .. (depot.rows or 0) .. "]")),
            function()
                AkaShopClient.send("openDepot", { key = key })
            end)
        if admin then
            row("Set up buying point" .. ADMIN, function()
                AkaShopClient.send("openDepot", { key = key })
            end)
            -- Removing a counter is a thing you decide while standing at it,
            -- so the verb lives here too. It was only ever inside the window,
            -- which meant opening the thing you wanted gone to find the way to
            -- get rid of it.
            row("Remove this buying point" .. ADMIN, function()
                AkaShopUI.confirm("Remove the buying point \"" ..
                    AkaShop.shopName(depot) .. "\"?\n" ..
                    "The tile stays where it is; only the deal goes.", {},
                    function()
                        AkaShopClient.send("depotRemove", { key = key })
                    end)
            end)
        end

    elseif entry then
        --------------------------------------------------------- existing shop
        local title = AkaShop.shopName(entry)
        if entry.enabled or AkaShopClient.canManage(entry) then
            row("Buy from " .. title .. (entry.enabled and "" or "   (CLOSED)"),
                function()
                    AkaShopClient.send("open", { key = key, mode = "buy" })
                end)
        end
        if AkaShopClient.canManage(entry) then
            -- Staff open the same window but reach a different shop inside it:
            -- the order queue and nothing else. Calling their row "Manage"
            -- promised a job they do not have, and left the one job they DO
            -- have with no name on the menu at all - which is how a staff
            -- member ends up asking where orders are accepted.
            local mine = AkaShopClient.isOwner(entry)
            row((mine and ("Manage " .. title) or ("Orders at " .. title)),
                function()
                    AkaShopClient.send("open", { key = key, mode = "manage" })
                end)
        end
        -- Same reasoning as the buying point: an admin clearing up a counter
        -- should not have to open it first. Admin only - a player deleting
        -- their own shop still does it from Settings, where the consequences
        -- are spelled out next to the button.
        if admin then
            row("Remove this shop" .. ADMIN, function()
                AkaShopUI.confirm("Delete \"" .. title .. "\" owned by " ..
                    tostring(entry.owner) .. "?\n" ..
                    "Anything still in stock comes to you.", {}, function()
                        AkaShopClient.send("deleteShop", { key = key })
                    end)
            end)
        end

    elseif obj then
        ------------------------------------------------- unregistered cashier
        if admin then
            -- The same tile can become either thing. Nothing about the sprite
            -- decides it; the admin does, right here, and the two rows sit
            -- side by side so the choice is visibly a choice.
            row("Make this a player shop..." .. ADMIN,
                function() doRegisterFlow(playerNum, sq, obj, true) end)
            row("Make this a buying point..." .. ADMIN, function()
                local sprite = AkaShop.spriteNameOf(obj) or ""
                AkaShopUI.askNames("New buying point", "", "", function(en, th)
                    AkaShopClient.send("depotCreate", {
                        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                        sprite = sprite, name = en, nameTH = th })
                end)
            end)
        elseif AkaShopClient.pending[key] then
            row("Shop request pending approval...", nil)
        else
            row("Request permission to open a shop here...",
                function() doRegisterFlow(playerNum, sq, obj, false) end)
        end
    end

    -- Server-wide admin tools keep their parent. They are not about this tile,
    -- they are reachable from any tile, and an admin should not have to hunt
    -- for them among the verbs everybody else can see.
    if admin then
        -- The parent is not ours to build. The AKA family already has ONE
        -- menu helper - Kaandther's AKA_Menu.lua, global AKA - and every AKA
        -- mod files its admin tools under it: AKA MOD > Traka > ...
        -- (3.7.5 shipped a second helper of its own. A second
        -- registry under a different global does not merge anything; it is
        -- the "everyone builds their own" bug in a new file. Removed.)
        -- The admin check above comes first on purpose: the helper builds the
        -- parent row the moment it is asked, so asking for a player who has
        -- nothing to see would hand them an empty menu.
        buildAdminSubmenu(AkaShopMenu.adminRoot(context), playerNum, obj or worldobjects[1])
    end

    for i = #rows, 1, -1 do
        local r = rows[i]
        local o = context:addOptionOnTop(r.text, nil, r.fn)
        if not r.fn then o.notAvailable = true end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldMenu)

--=================================================================== boot ===

-- Keep asking until the index actually arrives. The old version gave up after
-- six tries, which on a busy server or a slow reconnect meant a client that
-- never learned about any shop and silently had no context menus for the rest
-- of the session. One tiny packet a minute costs nothing and stops the instant
-- the index lands.
local function tick()
    if AkaShopClient.gotIndex then return end
    AkaShopClient.send("hello", {})
end

Events.OnGameStart.Add(function()
    AkaShopClient.send("hello", {})
    print("[Traka] client ready v" .. AkaShop.VERSION)
end)

-- OnGameStart can land before the connection is usable in multiplayer, and it
-- does not fire again after a respawn. This does.
Events.OnCreatePlayer.Add(function()
    AkaShopClient.gotIndex = false
    AkaShopClient.send("hello", {})
end)

Events.EveryOneMinute.Add(tick)
