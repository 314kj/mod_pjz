--[[===========================================================================
    Traka - taking goods off a player, on the server.

    THE BUG THIS EXISTS TO FIX.

    A player sold a gold ring to a depot. The money arrived, the ring left
    their bag, the log said "Sold 1 x Gold Ring with Ruby for 5 Money". They
    logged out, logged back in, and the ring was on them again. They had been
    paid for an item they still owned.

    console.txt named it exactly:

        ERROR: addToItemRemoveSendBuffer parent=IsoPlayer{ Name:null, ID:134 }
               item=Clothing{ clothingItemName="Ring_Left_RingFinger_GoldRuby" }

    The removal happened on the CLIENT. The client's copy of the inventory lost
    the ring, so everything looked right on screen, but the announcement to the
    server failed and the server's copy - the authoritative one, the one a
    relog is rebuilt from - never lost anything.

    This is the exact mirror of the ghost-item bug in AkaShop_Give.lua, and it
    has the same answer, pointed the other way:

        THE SERVER OWNS THE PLAYER'S INVENTORY.
        A client may report what it did. Only the server may make it true.

    So after a client confirms a hand-over, the server reaps the same items out
    of its own copy. The client keeps removing locally too - that is what makes
    the screen respond instantly - but its removal is now a courtesy rather
    than the thing the save depends on.

    WHY REAPING IS BOUNDED BY WHAT WAS AUTHORISED. `n` never comes straight
    from the client into this function; every caller has already clamped it to
    the count the server itself agreed to in phase one. A client that claims to
    have handed over nine hundred rings gets nine hundred rings' worth of
    nothing, because the transaction it is confirming only ever said one.
============================================================================]]

AkaShopTake = AkaShopTake or {}
local T = AkaShopTake

--- Tell everyone else that this item is gone from that container.
---
--- Tried in order, because the two calls are not available on every build and
--- neither is worth crashing over: the local Remove below is what actually
--- matters, and an un-announced removal costs one stale inventory window until
--- the next refresh, not a lost item.
local announced = nil
local function announce(container, item)
    if type(sendRemoveItemFromContainer) == "function" then
        if pcall(function() sendRemoveItemFromContainer(container, item) end) then
            announced = true
            return true
        end
    end
    if type(container.removeItemOnServer) == "function" then
        if pcall(function() container:removeItemOnServer(item) end) then
            announced = true
            return true
        end
    end
    if not announced then
        announced = false
        print("[Traka] no way to announce an item removal on this build - " ..
              "inventories may look stale until they are reopened.")
    end
    return false
end

--- Take `n` items of `ft` out of the server's copy of a player's inventory.
--- Returns how many it actually found and removed.
function T.reap(player, ft, n)
    n = math.floor(tonumber(n) or 0)
    if not player or type(ft) ~= "string" or ft == "" or n < 1 then return 0 end
    if AkaShop.isSP() then return 0 end        -- one inventory, already handled

    local inv
    if not pcall(function() inv = player:getInventory() end) or not inv then return 0 end

    -- Same collector the client used, so the server reaps the same class of
    -- item: nothing worn, nothing favourited, nothing in a hand.
    local found = AkaShop.collectItems(inv, ft, n, player)
    local gone = 0
    for i = 1, #found do
        if gone >= n then break end
        local it = found[i]
        local c
        pcall(function() c = it:getContainer() end)
        if not c then c = inv end
        announce(c, it)
        if pcall(function() c:Remove(it) end) then
            gone = gone + 1
            pcall(function() c:setDrawDirty(true) end)
        end
    end

    if gone < n then
        -- Not an error. The client removed its copy a moment ago and the
        -- server may have already caught up through the normal sync, in which
        -- case there is genuinely nothing left to reap. Worth a line, because
        -- if it is ALWAYS zero something upstream has changed.
        print("[Traka] reaped " .. gone .. "/" .. n .. " x " .. ft ..
              " from " .. tostring(AkaShop.nameOf(player)))
    end
    return gone
end

--- Convenience for the money side of a purchase. Currency has exactly the same
--- problem and it is the worse one: an un-reaped payment is minted money.
function T.reapCurrency(player, n)
    return T.reap(player, AkaShop.getCurrency(), n)
end
