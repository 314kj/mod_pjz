-- CookieServerPatch: FTZ Carts & Trolleys (3815775971) - carts become donation only.
-- Server side (multiplayer server, or the game itself in solo). ASCII only.
--
-- Pie 12 Nov 2026: carts will be given through Cookie Express (donation), so every
-- cart that the mod put in the world since it was added (11 Nov 22:16) goes away:
--   * carts standing on the ground: removed when their square loads, and every few
--     seconds around each online player (catches carts a player just let go of).
--     What was inside the cart is put on the ground of the same square, so nothing
--     a player stored in it is lost.
--   * carts in loot: taken out of containers when the game fills them (FTZ itself
--     puts none in loot today; this is only a safety net).
--   * rooms that still had carts waiting to be placed (FTZ keeps a count per room in
--     global ModData "FTZCarts") are set to 0 once at start, and the running value of
--     SandboxVars.FTZCarts.WorldSpawnChance is held at 0, so no new ones appear.
--   * a cart with bodies in it (FTZ corpse option) is left until the bodies are out.
--   * carts held in hands are let go by the player's own game (client file
--     CSP_FTZCartsDrop.lua, same drop request FTZ itself uses), then removed here.
-- Kept: carts handed out by Cookie Express (item mod data "ckx_o" = order id,
-- written by Cookie Express 1.2.5+ on FTZ carts only). The Makeshift Cart (crafted
-- from planks and tyres) is kept unless CLEAN_MAKESHIFT below is true.
-- Also set in the sandbox (so the options page says the same): FTZCarts.WorldSpawnChance = 0.
--
-- Log: "[CookieServerPatch] ftz-cleanup on" at start, one line per square with
-- removed carts. To undo: remove this file and CSP_FTZCartsDrop.lua.

if isClient() then return end

local TAG = "[CookieServerPatch] ftz-cleanup"
local CLEAN_MAKESHIFT = false
local KEEP_KEY = "ckx_o"
local SWEEP_MS = 3000   -- around online players
local SWEEP_R = 2       -- squares around the player (5x5, the player's floor)

local TYPES = {
    ["Base.FTZ_ShoppingCart"] = true,
    ["Base.FTZ_PlatformTrolley"] = true,
    ["Base.FTZ_LaundryCart"] = true,
    ["Base.FTZ_GardenCart"] = true,
    ["Base.FTZ_JanitorCart"] = true,
    ["Base.FTZ_HandTruck"] = true,
    ["Base.FTZ_Wheelbarrow"] = true,
    ["Base.FTZ_MechanicCart"] = true,
}
if CLEAN_MAKESHIFT then TYPES["Base.FTZ_MakeshiftCart"] = true end

CSP_FTZCleanup = CSP_FTZCleanup or {}
local M = CSP_FTZCleanup
M.removed = M.removed or 0

-- a cart to remove: one of the types above and not handed out by Cookie Express
function M.isTarget(item)
    if not item or not TYPES[item:getFullType()] then return false end
    if item:hasModData() and item:getModData()[KEEP_KEY] ~= nil then return false end
    return true
end

local function addToGround(sq, it)
    local x, y = ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8)
    local ok = pcall(function() sq:AddWorldInventoryItem(it, x, y, 0, true) end)
    if not ok then pcall(function() sq:AddWorldInventoryItem(it, x, y, 0) end) end
end

-- empty the cart onto the square (stored things and loot stay in the world)
local function spill(sq, item)
    local cont = item.getItemContainer and item:getItemContainer()
    if not cont then return 0 end
    local items = cont:getItems()
    local list = {}
    for i = 0, items:size() - 1 do list[#list + 1] = items:get(i) end
    for _, it in ipairs(list) do
        pcall(function() cont:DoRemoveItem(it) end)
        addToGround(sq, it)
    end
    return #list
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

-- bodies loaded with FTZ's corpse option: such a cart is left alone (a body must be
-- unloaded with FTZ's own "drop the corpses" option, it cannot be put down as an item);
-- it goes on the next check once the bodies are out
local function hasCorpse(item)
    local cont = item.getItemContainer and item:getItemContainer()
    if not cont then return false end
    local items = cont:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local ok, yes = pcall(function() return it:isHumanCorpse() or it:isAnimalCorpse() end)
        if ok and yes then return true end
    end
    return false
end

M.skipped = M.skipped or {}

-- remove the carts lying on one square; returns how many
function M.cleanSquare(sq)
    if not sq then return 0 end
    local wobs = sq:getWorldObjects()
    if not wobs or wobs:size() == 0 then return 0 end
    local found = nil
    for i = 0, wobs:size() - 1 do
        local wo = wobs:get(i)
        local item = wo and wo:getItem()
        if M.isTarget(item) then
            if hasCorpse(item) then
                local id = item:getID()
                if not M.skipped[id] then
                    M.skipped[id] = true
                    print(TAG .. ": cart with bodies left at " .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
                        .. " (goes once the bodies are unloaded)")
                end
            else
                found = found or {}
                found[#found + 1] = wo
            end
        end
    end
    if not found then return 0 end
    local spilled = 0
    for _, wo in ipairs(found) do
        local item = wo:getItem()
        removeWorldItem(sq, wo)
        if item then spilled = spilled + spill(sq, item) end
    end
    M.removed = M.removed + #found
    print(TAG .. ": removed " .. #found .. " cart(s) at " .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
        .. " (" .. spilled .. " item(s) inside put on the ground, total " .. M.removed .. ")")
    return #found
end

-- loot: take carts out of a container the game has just filled
-- (for bags on zombies the game passes a loot-table object here, not a container)
function M.onFillContainer(roomType, containerType, container)
    if not container or not instanceof(container, "ItemContainer") then return end
    local items = container:getItems()
    if not items or items:size() == 0 then return end
    local hit = nil
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if M.isTarget(it) then hit = hit or {}; hit[#hit + 1] = it end
    end
    if not hit then return end
    for _, it in ipairs(hit) do pcall(function() container:DoRemoveItem(it) end) end
    M.removed = M.removed + #hit
    print(TAG .. ": " .. #hit .. " cart(s) taken out of new loot (" .. tostring(containerType) .. ")")
end

-- rooms that still had carts to place: none any more
function M.stopPending()
    if not ModData or not ModData.exists or not ModData.exists("FTZCarts") then return 0 end
    local md = ModData.get("FTZCarts")
    local rooms = md and md.rooms
    if type(rooms) ~= "table" then return 0 end
    local n = 0
    for k, left in pairs(rooms) do
        if type(left) == "number" and left > 0 then rooms[k] = 0; n = n + 1 end
    end
    return n
end

-- new rooms: FTZ reads SandboxVars.FTZCarts.WorldSpawnChance each time it rolls a room
-- (FTZCarts_WorldSpawn.lua), so 0 here means no new carts even if the sandbox still
-- says 35. Only this running copy of the value; the sandbox file is not touched.
-- (LootRate is not used by FTZ's code at all, 11 Nov version.)
local function noNewRooms()
    local t = SandboxVars and SandboxVars.FTZCarts
    if type(t) == "table" and t.WorldSpawnChance ~= 0 then
        t.WorldSpawnChance = 0
        return true
    end
    return false
end

local started = false
function M.start()
    if started then return end
    started = true
    local ok, n = pcall(M.stopPending)
    local okS, set = pcall(noNewRooms)
    print(TAG .. " on (rooms with carts still to place set to 0: " .. tostring(ok and n or ("error " .. tostring(n)))
        .. ", new rooms: " .. ((okS and set) and "spawn chance set to 0" or "spawn chance already 0") .. ")")
end

-- every few seconds: squares around each online player
local nextSweep = 0
function M.sweep(now)
    if now < nextSweep then return end
    nextSweep = now + SWEEP_MS
    pcall(noNewRooms)
    local players = getOnlinePlayers and getOnlinePlayers()
    local cell = getCell()
    if not cell then return end
    local list = {}
    if players and players:size() > 0 then
        for i = 0, players:size() - 1 do list[#list + 1] = players:get(i) end
    elseif not isServer() then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then list[#list + 1] = p end
        end
    end
    for _, p in ipairs(list) do
        local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        for x = px - SWEEP_R, px + SWEEP_R do
            for y = py - SWEEP_R, py + SWEEP_R do
                local sq = cell:getGridSquare(x, y, pz)
                if sq then pcall(M.cleanSquare, sq) end
            end
        end
    end
end

Events.OnInitGlobalModData.Add(M.start)
Events.OnServerStarted.Add(M.start)
Events.LoadGridsquare.Add(function(sq) pcall(M.cleanSquare, sq) end)
Events.OnFillContainer.Add(function(r, c, cont) pcall(M.onFillContainer, r, c, cont) end)
Events.OnTick.Add(function() M.sweep(getTimestampMs()) end)
