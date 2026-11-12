-- CookieServerPatch: six items of the new maps become donation only.
-- Server side (multiplayer server, or the game itself in solo). ASCII only.
--
-- Pie 12 Nov 2026: these items of Raccoon City (3388468313) and AnruisiTown
-- (3659676359) will be given through Cookie Express, so the game stops handing
-- them out by itself, and the ones already found are taken away:
--   Base.ResidentEvilBackPack, Base.ResidentEvilSuspenders,
--   Base.BiochemicalVaccines, Base.dabaojian          (Raccoon City)
--   Base.MilitaryStorageBackpack, Base.WoodChainsaw   (AnruisiTown)
--
-- What it does:
--   * loot tables: the six items are taken out of every loot list
--     (SuburbsDistributions, ProceduralDistributions, VehicleDistributions)
--     before the game reads them at start;
--   * new loot: if a container still gets one when the game fills it (a mod
--     adding it another way), it is taken out again;
--   * AnruisiTown's soldier zombies ("heavy" gets a Military Storage Backpack
--     when it dies): taken off the body;
--   * items that already exist (Pie 12 Nov, second step): every few seconds the
--     server looks at each online player - everything carried, worn or held,
--     bags inside bags - and at the 5x5 squares around the player: items on the
--     floor, furniture and crates, bodies. Any of the six found there is
--     removed. A removed bag is emptied first: its contents go to the place the
--     bag was in (the player's inventory, the crate, the floor).
-- Kept: items handed out by Cookie Express. They carry item mod data
-- "ckx_o" = order id. Cookie Express writes that mark itself only on FTZ carts,
-- so this file adds it for the six items: it wraps CKX.S.claimLine (the
-- function that hands over one order line) and marks the new items right after
-- the hand-over. Cookie Express's own files are not changed.
-- Safety: if Cookie Express is not found, nothing that already exists is
-- removed (only the loot part runs), so a donated item can never be deleted
-- because the mark was missing.
-- An item spawned by an admin (item list, /additem) has no mark and is removed
-- like found loot: give these six through Cookie Express only.
--
-- Not covered: items stored in a car (boot, seats, glove box) stay until a
-- player takes them out; then they are removed from the player.
--
-- Log: "[CookieServerPatch] map-donation-items on" with the number of loot
-- entries removed, "... cleanup of existing items on/off", then one line each
-- time something is removed.
-- To undo: remove this file.

if isClient() then return end

local TAG = "[CookieServerPatch] map-donation-items"
local KEEP_KEY = "ckx_o"
local SWEEP_MS = 5000   -- how often online players are checked
local SWEEP_R = 2       -- squares around the player (5x5, the player's floor)

local TYPES = {
    "ResidentEvilBackPack",
    "ResidentEvilSuspenders",
    "BiochemicalVaccines",
    "dabaojian",
    "MilitaryStorageBackpack",
    "WoodChainsaw",
}

CSP_MapDonationItems = CSP_MapDonationItems or {}
local M = CSP_MapDonationItems
M.removed = M.removed or 0

-- "Base.X" and "X" (loot lists use either form)
local NAMES, FULL = {}, {}
for _, t in ipairs(TYPES) do
    NAMES[t] = true
    NAMES["Base." .. t] = true
    FULL["Base." .. t] = true
end

-- one of the six, whoever gave it
function M.isType(item)
    return item ~= nil and FULL[item:getFullType()] == true
end

-- one of the six and not handed out by Cookie Express
function M.isTarget(item)
    if not M.isType(item) then return false end
    if item:hasModData() and item:getModData()[KEEP_KEY] ~= nil then return false end
    return true
end

-- ---------------------------------------------------------------- loot tables

-- items = { "Name", weight, "Name", weight, ... } -> same list without ours
local function stripList(list)
    local n, i, out = #list, 1, 0
    while i <= n do
        local name = list[i]
        if type(name) == "string" and NAMES[name] then
            table.remove(list, i)
            if type(list[i]) == "number" then table.remove(list, i); n = n - 1 end
            n = n - 1
            out = out + 1
        else
            i = i + 1
        end
    end
    return out
end

local function walk(t, seen, depth)
    if type(t) ~= "table" or seen[t] or depth > 12 then return 0 end
    seen[t] = true
    local out = 0
    for k, v in pairs(t) do
        if type(v) == "table" then
            if k == "items" then out = out + stripList(v) end
            out = out + walk(v, seen, depth + 1)
        end
    end
    return out
end

function M.stripTables()
    local seen, out = {}, 0
    out = out + walk(SuburbsDistributions, seen, 0)
    out = out + walk(ProceduralDistributions, seen, 0)
    out = out + walk(VehicleDistributions, seen, 0)
    out = out + walk(Distributions, seen, 0)
    return out
end

function M.onDistribution()
    local ok, n = pcall(M.stripTables)
    if ok then
        print(TAG .. " on (loot entries removed: " .. tostring(n) .. ")")
    else
        print(TAG .. ": loot tables not changed (" .. tostring(n) .. ")")
    end
end

-- ---------------------------------------------------------------- containers

local function isItemContainer(c)
    return c ~= nil and instanceof(c, "ItemContainer")
end

-- tell the players' games about a change (only for things that already exist;
-- loot that is being made right now needs none)
local function syncRemove(container, item)
    if isServer() and sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, container, item) end
end
local function syncAdd(container, item)
    if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, container, item) end
end

-- same steps the game uses when a player takes an item off (ISUnequipAction,
-- ISTransferAction): off the belt or back, off the body, out of the hands
local function takeOff(player, item)
    pcall(function() player:removeAttachedItem(item) end)
    local ok, on = pcall(function() return player:isEquipped(item) end)
    if not ok or not on then return end
    pcall(function() player:removeWornItem(item) end)
    pcall(function()
        if player:getPrimaryHandItem() == item then player:setPrimaryHandItem(nil) end
        if player:getSecondaryHandItem() == item then player:setSecondaryHandItem(nil) end
    end)
    if sendEquip then pcall(sendEquip, player) end
    pcall(triggerEvent, "OnClothingUpdated", player)
end

-- take our items out of a container (and out of bags inside it); returns count.
-- A removed bag's contents are moved into the container it was in.
--   sync   : true for things that already exist (players are told)
--   player : the owner when the container is on a player (item is taken off first)
function M.cleanContainer(container, depth, sync, player)
    if not isItemContainer(container) then return 0 end
    depth = depth or 0
    local items = container:getItems()
    if not items or items:size() == 0 then return 0 end
    local list = {}
    for i = 0, items:size() - 1 do list[#list + 1] = items:get(i) end
    local out = 0
    for _, it in ipairs(list) do
        local inner = instanceof(it, "InventoryContainer") and it:getItemContainer() or nil
        if M.isTarget(it) then
            if player then takeOff(player, it) end
            if inner then
                local kept = {}
                local inItems = inner:getItems()
                for i = 0, inItems:size() - 1 do kept[#kept + 1] = inItems:get(i) end
                for _, k in ipairs(kept) do
                    if not M.isTarget(k) then
                        inner:DoRemoveItem(k)
                        if sync then syncRemove(inner, k) end
                        container:AddItem(k)
                        if sync then syncAdd(container, k) end
                    end
                end
            end
            container:DoRemoveItem(it)
            if sync then syncRemove(container, it) end
            out = out + 1
        elseif inner and depth < 4 then
            out = out + M.cleanContainer(inner, depth + 1, sync, player)
        end
    end
    return out
end

-- the game calls this with a loot-table object instead of a container for
-- bags on zombies ("Zombie Bag"); those are skipped by isItemContainer
function M.onFillContainer(roomType, containerType, container)
    if not isItemContainer(container) then return end
    local n = M.cleanContainer(container, 0, false, nil)
    if n > 0 then
        M.removed = M.removed + n
        print(TAG .. ": " .. n .. " item(s) taken out of new loot (" .. tostring(roomType) .. " / "
            .. tostring(containerType) .. ", total " .. M.removed .. ")")
    end
end

function M.onZombieDead(zombie)
    if not zombie then return end
    local inv = zombie:getInventory()
    if not isItemContainer(inv) then return end
    local n = M.cleanContainer(inv, 0, false, nil)
    if n > 0 then
        M.removed = M.removed + n
        print(TAG .. ": " .. n .. " item(s) taken off a zombie at " .. math.floor(zombie:getX()) .. ","
            .. math.floor(zombie:getY()) .. " (total " .. M.removed .. ")")
    end
end

-- ------------------------------------------------- Cookie Express: mark items

-- ids of the six items a player carries (marked or not), bags included
local function collect(container, depth, into)
    if not isItemContainer(container) then return into end
    local items = container:getItems()
    if not items then return into end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if M.isType(it) then into[#into + 1] = it end
        if depth < 4 and instanceof(it, "InventoryContainer") then
            collect(it:getItemContainer(), depth + 1, into)
        end
    end
    return into
end

local function markNew(player, before, orderId)
    local n = 0
    for _, it in ipairs(collect(player:getInventory(), 0, {})) do
        if not before[it:getID()] and it:getModData()[KEEP_KEY] == nil then
            it:getModData()[KEEP_KEY] = orderId
            if isServer() and syncItemModData then pcall(syncItemModData, player, it) end
            n = n + 1
        end
    end
    if n > 0 then
        print(TAG .. ": " .. n .. " item(s) of order " .. tostring(orderId) .. " marked as given by Cookie Express")
    end
end

M.hooked = M.hooked or false
function M.hookExpress()
    if M.hooked then return true end
    if not (CKX and CKX.S and type(CKX.S.claimLine) == "function") then return false end
    local orig = CKX.S.claimLine
    CKX.S.claimLine = function(player, orderId, idx, ...)
        local before = {}
        pcall(function()
            for _, it in ipairs(collect(player:getInventory(), 0, {})) do before[it:getID()] = true end
        end)
        local ok, a, b, c, d = pcall(orig, player, orderId, idx, ...)
        pcall(markNew, player, before, orderId)
        if not ok then error(a) end
        return a, b, c, d
    end
    M.hooked = true
    return true
end

-- ------------------------------------------------ items that already exist

local function addToGround(sq, it)
    local x, y = ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8)
    local ok = pcall(function() sq:AddWorldInventoryItem(it, x, y, 0, true) end)
    if not ok then pcall(function() sq:AddWorldInventoryItem(it, x, y, 0) end) end
end

-- same steps the game uses when an item is taken off the ground
local function removeWorldItem(sq, wo)
    local item = wo:getItem()
    pcall(function() sq:transmitRemoveItemFromSquare(wo) end)
    pcall(function() wo:removeFromWorld() end)
    pcall(function() wo:removeFromSquare() end)
    pcall(function() wo:setSquare(nil) end)
    if item then pcall(function() item:setWorldItem(nil) end) end
end

-- floor, furniture and bodies of one square; returns how many were removed
function M.cleanSquare(sq)
    if not sq then return 0 end
    local out = 0
    -- on the floor
    local wobs = sq:getWorldObjects()
    if wobs and wobs:size() > 0 then
        local list = {}
        for i = 0, wobs:size() - 1 do list[#list + 1] = wobs:get(i) end
        for _, wo in ipairs(list) do
            local item = wo and wo:getItem()
            if item then
                local inner = instanceof(item, "InventoryContainer") and item:getItemContainer() or nil
                if M.isTarget(item) then
                    removeWorldItem(sq, wo)
                    if inner then
                        local kept = {}
                        local inItems = inner:getItems()
                        for i = 0, inItems:size() - 1 do kept[#kept + 1] = inItems:get(i) end
                        for _, k in ipairs(kept) do
                            if not M.isTarget(k) then
                                pcall(function() inner:DoRemoveItem(k) end)
                                addToGround(sq, k)
                            end
                        end
                    end
                    out = out + 1
                elseif inner then
                    out = out + M.cleanContainer(inner, 1, true, nil)
                end
            end
        end
    end
    -- furniture, crates
    local objs = sq:getObjects()
    if objs then
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local ok, n = pcall(function() return o:getContainerCount() end)
            if ok and n and n > 0 then
                for c = 0, n - 1 do
                    out = out + M.cleanContainer(o:getContainerByIndex(c), 0, true, nil)
                end
            end
        end
    end
    -- bodies
    local okB, bodies = pcall(function() return sq:getDeadBodys() end)
    if okB and bodies then
        for i = 0, bodies:size() - 1 do
            local okC, cont = pcall(function() return bodies:get(i):getContainer() end)
            if okC then out = out + M.cleanContainer(cont, 0, true, nil) end
        end
    end
    return out
end

local function playerName(p)
    local ok, n = pcall(function() return p:getUsername() end)
    return (ok and n) or "?"
end

function M.cleanPlayer(p, cell)
    local n = M.cleanContainer(p:getInventory(), 0, true, p)
    if n > 0 then
        M.removed = M.removed + n
        print(TAG .. ": " .. n .. " item(s) removed from player " .. playerName(p) .. " (total " .. M.removed .. ")")
    end
    if not cell then return end
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local near = 0
    for x = px - SWEEP_R, px + SWEEP_R do
        for y = py - SWEEP_R, py + SWEEP_R do
            local sq = cell:getGridSquare(x, y, pz)
            if sq then
                local ok, m = pcall(M.cleanSquare, sq)
                if ok and m then near = near + m end
            end
        end
    end
    if near > 0 then
        M.removed = M.removed + near
        print(TAG .. ": " .. near .. " item(s) removed near " .. px .. "," .. py .. "," .. pz
            .. " (player " .. playerName(p) .. ", total " .. M.removed .. ")")
    end
end

local nextSweep = 0
function M.sweep(now)
    if now < nextSweep then return end
    nextSweep = now + SWEEP_MS
    if not M.hooked then return end
    local cell = getCell()
    local list = {}
    local players = getOnlinePlayers and getOnlinePlayers()
    if players and players:size() > 0 then
        for i = 0, players:size() - 1 do list[#list + 1] = players:get(i) end
    elseif not isServer() then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then list[#list + 1] = p end
        end
    end
    for _, p in ipairs(list) do pcall(M.cleanPlayer, p, cell) end
end

local started = false
function M.start()
    if started then return end
    started = true
    local ok, yes = pcall(M.hookExpress)
    if ok and yes then
        print(TAG .. ": cleanup of existing items on (Cookie Express items are marked and kept)")
    else
        print(TAG .. ": cleanup of existing items OFF - Cookie Express not found, only new loot is blocked")
    end
end

Events.OnPostDistributionMerge.Add(M.onDistribution)
Events.OnFillContainer.Add(M.onFillContainer)
Events.OnZombieDead.Add(M.onZombieDead)
Events.OnServerStarted.Add(M.start)
Events.OnGameStart.Add(M.start)
Events.OnTick.Add(function() M.sweep(getTimestampMs()) end)
