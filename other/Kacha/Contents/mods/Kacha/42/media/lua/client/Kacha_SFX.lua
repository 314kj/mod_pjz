--[[ ============================================================
     Kacha B42 [MP]  -  sound + spin dispatch + give  by PIE  (KACHASIG)
     SP : roll locally (client authoritative).
     MP : ask the server (RNG anti-cheat), results come back async,
          and the GIVE is deferred to the next OnTick (outside the
          network callback) so items are real + usable on a
          dedicated server -- this is the ghost-item fix.
   ============================================================ ]]

Kacha = Kacha or {}

-- ---- sound --------------------------------------------------------------
function Kacha.playSpin(pl)
    local sm = getSoundManager()
    if sm then sm:playUISound("Kacha_Spin") end
end

function Kacha.playResult(pl, win)
    local sm = getSoundManager()
    if sm then sm:playUISound("Kacha_Spin") end
end


-- ---- SP-only local spin (client is authoritative in SP) -----------------
local function takeCoins(inv, fullType, amount)
    local removed = 0
    for _ = 1, amount do
        local it = inv:FindAndReturn(fullType)
        if not it then break end
        inv:Remove(it); removed = removed + 1
    end
    return removed
end

function Kacha.localSpin(obj, pl, count)
    count = tonumber(count) or 1
    local d = Kacha.getConfig(obj)
    if (#Kacha.getEntries(obj) == 0) and (#d.salt == 0) then return {} end

    local cost      = (tonumber(d.costPerRoll) or 1) * count
    local tokenItem = d.tokenItem or "Base.KachaCoin"
    local inv       = pl:getInventory()
    if inv:getItemCount(tokenItem) < cost then return nil end

    local paid = takeCoins(inv, tokenItem, cost)
    if paid < cost then
        for _ = 1, paid do inv:AddItem(tokenItem) end   -- refund partial
        return nil
    end

    local results = {}
    local who = (pl.getUsername and pl:getUsername()) or "player"
    for _ = 1, count do
        local pick = Kacha.rollOne(obj)                 -- <-- obj, not items
        if pick then
            local newItem = instanceItem(pick.id)
            if newItem then inv:AddItem(newItem) end
            local nm = (newItem and newItem.getName and newItem:getName()) or Kacha.displayName(pick.id)
            table.insert(results, { id = pick.id, tier = pick.tier, name = nm })
            if Kacha.RARE[pick.tier] then Kacha.logRare(obj, who, nm, pick.tier) end
        end
    end
    return results
end

-- ---- dispatch -----------------------------------------------------------
-- SP -> results table (or nil = broke, {} = empty machine)
-- MP -> "pending"; real results arrive via OnServerCommand (deferred give)
function Kacha.requestSpin(obj, pl, count)
    if Kacha.isSP() then
        return Kacha.localSpin(obj, pl, count)
    end
    local sq = obj:getSquare(); if not sq then return nil end
    sendClientCommand(pl, "Kacha", "spin", { x = sq:getX(), y = sq:getY(), z = sq:getZ(), count = count })
    return "pending"
end

-- ---- MP results coming back from the server -----------------------------
-- Kacha.deliverResults (in Kacha_SpinPanel.lua) does the client-side
-- charge + give on the player's own inventory.
local function onServerCommand(module, command, args)
    if module ~= "Kacha" then return end
    if command == "spinResult" then
        if Kacha.deliverResults then Kacha.deliverResults(args) end
    elseif command == "presets" then
        if args and Kacha.setPresetsTable then Kacha.setPresetsTable(args.presets) end
    elseif command == "feed" then
        if Kacha.showFeed then Kacha.showFeed(args) end
    end
end
Events.OnServerCommand.Add(onServerCommand)

Kacha.__mark("sfx")
