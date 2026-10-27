--[[===========================================================================
    AkaShop - keep a registered counter physically present.

    Two different things can leave a shop record pointing at an empty tile:

      * the object was spawned with the debug tools and never written into the
        chunk, so it is simply gone the next time the chunk streams in;
      * the chunk streamed in BEFORE the shop index arrived from the server,
        which is exactly what an admin teleport does -- you land, the squares
        load, and the answer to "is there a shop here" shows up a moment later.

    LoadGridsquare covers the first. It cannot cover the second, because by the
    time we know about the shop those squares have already finished loading and
    will not fire the event again. So there is also a sweep that walks the known
    shops and repairs any whose square is loaded right now. The sweep runs when
    the index arrives, after a teleport, and once a minute as a safety net.

    LoadGridsquare fires for every square the game streams, thousands per second
    while running, so its miss path is one integer index and out. No string
    keys, no allocation, no pcall on the hot path.
============================================================================]]

AkaShopRestore = AkaShopRestore or {}

AkaShopRestore.placed = 0
AkaShopRestore.SWEEP_RADIUS = 80        -- tiles; beyond this nothing is loaded

local function spriteOnSquare(sq, sprite)
    local objs
    if not pcall(function() objs = sq:getObjects() end) then return false end
    if not objs then return false end
    for i = 0, objs:size() - 1 do
        if AkaShop.spriteNameOf(objs:get(i)) == sprite then return true end
    end
    return false
end

--- IsoObject's constructor signature has moved between builds; try the forms
--- that have existed and take whichever actually returns an object.
local function makeObject(sq, sprite)
    local obj
    if pcall(function() obj = IsoObject.new(sq, sprite, sprite) end) and obj then return obj end
    if pcall(function() obj = IsoObject.new(sq, sprite) end) and obj then return obj end
    if pcall(function() obj = IsoObject.new(getCell(), sq, sprite) end) and obj then return obj end
    return nil
end

local function restore(sq, sprite)
    if not sprite or sprite == "" then return false end
    if spriteOnSquare(sq, sprite) then return false end

    local obj = makeObject(sq, sprite)
    if not obj then
        print("[Traka] cannot build sprite " .. tostring(sprite) ..
              " - is the texture pack loaded?")
        return false
    end

    local ok = pcall(function() sq:AddTileObject(obj) end)
    if not ok then ok = pcall(function() sq:AddSpecialObject(obj) end) end
    if not ok then return false end

    -- In multiplayer the server now owns this repair (AkaShop_Tiles.lua), so
    -- what happens here is purely cosmetic: it stops the counter blinking out
    -- of existence in the seconds before the server's copy arrives. Pushing it
    -- up as well would race the server's own object and could leave two stacked
    -- on one square, so the client keeps its repair to itself.
    if AkaShop.isSP() then
        pcall(function() obj:transmitCompleteItemToServer() end)
    end
    pcall(function() sq:RecalcAllWithNeighbours(true) end)

    AkaShopRestore.placed = AkaShopRestore.placed + 1
    print("[Traka] restored shop counter at " ..
          sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ())
    return true
end
AkaShopRestore.restoreOn = restore

--============================================================ streaming in ==

local function onLoadSquare(sq)
    local anchors = AkaShopClient and AkaShopClient.anchors
    if not anchors then return end
    if not sq then return end

    local col = anchors[sq:getX()]
    if not col then return end                    -- the overwhelmingly common case
    local a = col[sq:getY()]
    if not a then return end
    if a.z ~= sq:getZ() then return end

    pcall(restore, sq, a.sprite)
end

Events.LoadGridsquare.Add(onLoadSquare)

--============================================== already-loaded repair pass ==

--- Repair every known shop whose square is loaded right now. Squares that are
--- not streamed in yet are skipped and will be caught by LoadGridsquare.
function AkaShopRestore.sweep(reason)
    local idx = AkaShopClient and AkaShopClient.index
    if not idx then return 0 end
    local pl = AkaShopClient.me()
    if not pl then return 0 end

    local px, py, pz, cell
    if not pcall(function()
        px, py, pz = pl:getX(), pl:getY(), math.floor(pl:getZ() + 0.5)
        cell = getCell()
    end) or not cell then return 0 end

    local R, fixed = AkaShopRestore.SWEEP_RADIUS, 0
    for _, e in pairs(idx) do
        if e.sprite and e.sprite ~= "" and (e.z or 0) == pz then
            local dx, dy = e.x - px, e.y - py
            if dx*dx + dy*dy <= R*R then            -- cheap reject, no sqrt
                local sq
                pcall(function() sq = cell:getGridSquare(e.x, e.y, e.z or 0) end)
                if sq then
                    local ok, did = pcall(restore, sq, e.sprite)
                    if ok and did then fixed = fixed + 1 end
                end
            end
        end
    end
    if fixed > 0 then
        print("[Traka] sweep (" .. tostring(reason) .. ") restored " .. fixed)
    end
    return fixed
end

-- Safety net. Once a minute over at most a handful of nearby shops is far
-- cheaper than anything tied to OnTick, and it closes the gap for any path
-- neither LoadGridsquare nor the explicit calls happened to cover.
Events.EveryOneMinute.Add(function() pcall(AkaShopRestore.sweep, "timer") end)
