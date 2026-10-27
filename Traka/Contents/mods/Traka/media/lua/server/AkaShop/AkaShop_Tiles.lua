--[[===========================================================================
    Traka - the server keeps registered counters standing.

    A shop record is just data: an owner, a price list, a till and a set of
    coordinates. The physical counter on those coordinates is a different thing
    entirely, living in the map chunk, and in multiplayer the chunk belongs to
    the server. So when a counter was spawned with the debug tools, or its chunk
    was written before the object existed, the record survives every relog and
    the object does not - which is why settings could look perfect while the
    tile was simply not there any more.

    The client can paint a counter back onto a square, and it does, but that
    repair only exists inside that one player's session. Nobody else sees it and
    it is gone again next login. The repair has to happen where the chunk is
    authoritative, and that is here.

    Cost: one pass over the shop list every ten minutes, plus one integer lookup
    per square streamed in. A server with fifty shops does fifty cheap distance
    checks per pass, which is nothing next to a single zombie's pathfinding.
============================================================================]]

AkaShopTiles = AkaShopTiles or {}
local T = AkaShopTiles

T.placed = 0

--- x -> y -> {z, sprite}, rebuilt whenever the shop list changes so the
--- streaming hook can answer "is there a shop here" with two table lookups.
local anchors = nil

--- A shop whose record never captured a sprite name can never be repaired:
--- there is nothing to draw. That happens when the object's sprite could not be
--- read at the moment of registration, and it is permanent once written, so it
--- is worth healing rather than skipping.
---
--- First choice is the truth: if a counter is standing on the square right now,
--- take its name. Only when the square is loaded and genuinely empty do we fall
--- back to the default machine, and that is announced, because it may be the
--- wrong colour and the owner should know to swap it.
local function healSprite(s)
    if s.sprite and s.sprite ~= "" then return s.sprite end

    local cell, sq
    pcall(function()
        cell = getCell()
        sq = cell and cell:getGridSquare(s.x, s.y, s.z or 0)
    end)

    if sq then
        local objs
        pcall(function() objs = sq:getObjects() end)
        if objs then
            for i = 0, objs:size() - 1 do
                local n = AkaShop.spriteNameOf(objs:get(i))
                if n and AkaShop.OWN_SPRITE_SET[n] then
                    s.sprite = n
                    print("[Traka] learned the counter sprite for '" ..
                          tostring(s.name) .. "': " .. n)
                    return n
                end
            end
        end
        -- square is loaded and there is no machine on it: nothing left to read
        s.sprite = AkaShop.DEFAULT_SPRITE
        print("[Traka] shop '" .. tostring(s.name) .. "' had no sprite recorded" ..
              " and no counter on its tile - using " .. AkaShop.DEFAULT_SPRITE ..
              ". The owner may want a different colour.")
        return s.sprite
    end

    return nil          -- square not streamed in; ask again next sweep
end
T.healSprite = healSprite

--- Every square that should be carrying one of our counters, shop or depot.
local function eachAnchor(fn)
    local ok, d = pcall(function() return AkaShopCore.db() end)
    if not ok or not d then return end
    for _, s in pairs(d.shops or {}) do fn(s) end
    for _, p in pairs(d.buyers or {}) do fn(p) end
end
T.eachAnchor = eachAnchor

function T.rebuild()
    local byX = {}
    local ok, shops = pcall(function() return AkaShopCore.db().shops end)
    if ok and shops then
        for _, s in pairs(shops) do
            local sprite = s.sprite
            if sprite == "" or sprite == nil then
                local healed
                if pcall(function() healed = healSprite(s) end) then sprite = healed end
            end
            if s.x and s.y and sprite and sprite ~= "" then
                local col = byX[s.x]
                if not col then col = {}; byX[s.x] = col end
                col[s.y] = { z = s.z or 0, sprite = sprite }
            end
        end
    end
    -- Depots stand on the same counters and vanish the same way, so they go in
    -- the same list. A depot has no sprite to heal from - it is created by an
    -- admin standing at a real tile - so a blank one is simply skipped.
    local haveDb, d = pcall(function() return AkaShopCore.db() end)
    if haveDb and d then
        for _, p in pairs(d.buyers or {}) do
            if p.x and p.y and p.sprite and p.sprite ~= "" then
                local col = byX[p.x]
                if not col then col = {}; byX[p.x] = col end
                col[p.y] = { z = p.z or 0, sprite = p.sprite }
            end
        end
    end
    anchors = byX
end

--============================================================== placement ====

local function hasSprite(sq, sprite)
    local objs
    if not pcall(function() objs = sq:getObjects() end) or not objs then return true end
    for i = 0, objs:size() - 1 do
        if AkaShop.spriteNameOf(objs:get(i)) == sprite then return true end
    end
    return false
end

--- IsoObject's constructor has changed shape between builds; take whichever
--- form actually hands back an object.
local function build(sq, sprite)
    local o
    if pcall(function() o = IsoObject.new(sq, sprite, sprite) end) and o then return o end
    if pcall(function() o = IsoObject.new(sq, sprite) end) and o then return o end
    if pcall(function() o = IsoObject.new(getCell(), sq, sprite) end) and o then return o end
    return nil
end

local warned = false

--- Put the counter back on `sq` if it is missing. Returns true if it placed one.
function T.ensure(sq, sprite)
    if not sq or not sprite or sprite == "" then return false end
    if hasSprite(sq, sprite) then return false end

    local obj = build(sq, sprite)
    if not obj then
        if not warned then
            warned = true
            print("[Traka] server cannot build sprite " .. tostring(sprite) ..
                  " - the tile definition is not loaded on this server.")
        end
        return false
    end

    local ok = pcall(function() sq:AddTileObject(obj) end)
    if not ok then ok = pcall(function() sq:AddSpecialObject(obj) end) end
    if not ok then return false end

    -- Tell every connected client, then make sure the chunk knows it is dirty
    -- so the object is written to disk and survives the next restart.
    if type(obj.transmitCompleteItemToClients) == "function" then
        pcall(function() obj:transmitCompleteItemToClients() end)
    end
    pcall(function() sq:RecalcAllWithNeighbours(true) end)

    -- getChunk() can hand back nil for a square right on the streaming edge,
    -- and then :setModified is a call on nothing. pcall caught it, but Kahlua
    -- still dumped a full Java stack trace every time the sweep ran - once a
    -- minute, forever. Look before calling, on both halves.
    local chunk
    pcall(function() chunk = sq:getChunk() end)
    if chunk and type(chunk.setModified) == "function" then
        pcall(function() chunk:setModified(true) end)
    end

    T.placed = T.placed + 1
    print("[Traka] server restored shop counter at " ..
          tostring(sq:getX()) .. "," .. tostring(sq:getY()) .. "," .. tostring(sq:getZ()))
    return true
end

--============================================================ streaming in ===
-- Same discipline as the client hook: two integer lookups and out. This fires
-- for every square the server streams, so it must not allocate.

local function onLoadSquare(sq)
    if not anchors or not sq then return end
    local col = anchors[sq:getX()]
    if not col then return end
    local a = col[sq:getY()]
    if not a then return end
    if a.z ~= sq:getZ() then return end
    pcall(T.ensure, sq, a.sprite)
end

if Events and Events.LoadGridsquare then
    Events.LoadGridsquare.Add(onLoadSquare)
end

--============================================================== safety net ===

--- Walk every shop and repair the ones whose square is loaded right now.
function T.sweep(reason)
    if not anchors then T.rebuild() end
    local cell
    if not pcall(function() cell = getCell() end) or not cell then return 0 end

    local fixed = 0
    local ok, shops = pcall(function() return AkaShopCore.db().shops end)
    if not ok or not shops then return 0 end

    for _, s in pairs(shops) do
        if s.x and s.y then
            local sprite = s.sprite
            if sprite == nil or sprite == "" then
                local healed
                if pcall(function() healed = healSprite(s) end) then sprite = healed end
            end
            if sprite and sprite ~= "" then
                local sq
                pcall(function() sq = cell:getGridSquare(s.x, s.y, s.z or 0) end)
                if sq then
                    local done, did = pcall(T.ensure, sq, sprite)
                    if done and did then fixed = fixed + 1 end
                end
            end
        end
    end
    local okD, d = pcall(function() return AkaShopCore.db() end)
    if okD and d then
        for _, p in pairs(d.buyers or {}) do
            if p.x and p.y and p.sprite and p.sprite ~= "" then
                local sq
                pcall(function() sq = cell:getGridSquare(p.x, p.y, p.z or 0) end)
                if sq then
                    local done, did = pcall(T.ensure, sq, p.sprite)
                    if done and did then fixed = fixed + 1 end
                end
            end
        end
    end

    if fixed > 0 then
        print("[Traka] server sweep (" .. tostring(reason) .. ") restored " .. fixed)
    end
    return fixed
end

Events.EveryTenMinutes.Add(function() pcall(T.sweep, "timer") end)
Events.OnGameStart.Add(function() pcall(T.rebuild) end)
