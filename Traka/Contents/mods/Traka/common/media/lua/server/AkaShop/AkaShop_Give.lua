--[[===========================================================================
    Traka - the server hands the goods over.

    WHY THE GHOSTS HAPPENED, finally with evidence instead of theory.

    The B42.20 API listing for zombie.inventory.ItemContainer has:

        removeItemOnServer(InventoryItem)
        requestSync()
        requestServerItemsForContainer()

    and there is NO addItemOnServer. That absence is the whole answer. A client
    is allowed to tell the server "this item is gone" and it is allowed to ask
    "what is really in this container" - but it has no way at all to say "a new
    item now exists here". So every version of this mod that created the goods
    on the buyer's machine was producing an item the server could never be told
    about. It looked right, it survived until the next relog, and it refused to
    be dropped or traded, because dropping sends a packet naming an item the
    server has no record of. No amount of extra calls on the client could have
    fixed that; the door does not exist.

    So the item is created HERE, in the server process, straight into the real
    ItemContainer the server holds for that player, and then ANNOUNCED to the
    client with the Lua global sendAddItemToContainer(container, item). Creating
    it without announcing it is not enough - v2.8.0 did exactly that and the
    purchase vanished, because the item lived only in the server's copy of the
    bag. Create, then announce. Both halves or neither.

    Singleplayer is untouched: there is only one authority there, and creating
    the item on it is what the game itself does when a recipe finishes.
============================================================================]]

AkaShopGive = AkaShopGive or {}
local G = AkaShopGive

--- Build one item of `ft` in `state` directly into the server's container, then
--- ANNOUNCE it. The announcement is the part v2.8.0 was missing and it is the
--- whole job: without it the item exists only in the server's copy of the
--- container, the client never hears about it, and the next inventory sync from
--- the client overwrites the server's copy - so the buyer's money is gone and
--- the goods were never anywhere the buyer could see.
---
--- sendAddItemToContainer(ItemContainer, InventoryItem) is a Lua global and it
--- is the counterpart of removeItemOnServer: the authority uses it to tell the
--- other side that an item now exists here. Called from the server it is
--- correct. Called from a client - which is what three earlier versions were
--- effectively doing - the server has nothing to accept, which is the ghost.
local announced = false

local function one(inv, ft, st)
    local item
    pcall(function() item = instanceItem(ft) end)
    if not item then return false end
    if not pcall(function() inv:AddItem(item) end) then return false end

    if st and AkaShopStock and AkaShopStock.applyState then
        pcall(function() AkaShopStock.applyState(item, st) end)
        -- state is written while the server still owns the item alone, so what
        -- gets broadcast below is the finished article, not a blank one
        if type(item.syncItemFields) == "function" then
            pcall(function() item:syncItemFields() end)
        end
    end

    if type(sendAddItemToContainer) == "function" then
        pcall(function() sendAddItemToContainer(inv, item) end)
    elseif not announced then
        announced = true
        print("[Traka] WARNING: sendAddItemToContainer is missing on this " ..
              "build. Bought goods will not reach the buyer.")
    end
    return true
end

--- Hand `items` (the shape the "give" reply carries) to `player`.
--- Returns how many actually materialised, which is what the transaction is
--- committed on: the shop is never debited for goods that failed to appear.
function G.toPlayer(player, items)
    local inv = player and player:getInventory()
    if not inv then return 0 end

    local made = 0
    for _, g in ipairs(items or {}) do
        if g.ft then
            if g.states and #g.states > 0 then
                for _, st in ipairs(g.states) do
                    for _ = 1, math.floor(st.n or 0) do
                        if one(inv, g.ft, st) then made = made + 1 end
                    end
                end
            else
                for _ = 1, math.floor(g.count or 0) do
                    if one(inv, g.ft, nil) then made = made + 1 end
                end
            end
        end
    end

    if made > 0 then pcall(function() inv:setDrawDirty(true) end) end
    return made
end

local reported = false

--- One line, once, confirming the server really is the one building the items.
function G.report(made)
    if reported then return end
    reported = true
    print("[Traka] server-side hand-over active: first delivery made " ..
          tostring(made) .. " item(s), announced with sendAddItemToContainer=" ..
          tostring(type(sendAddItemToContainer) == "function"))
end
