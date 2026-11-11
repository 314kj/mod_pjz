-- CSP_MonorailsPlain.lua  (CookieServerPatch, media/lua/server)
-- Monorails 1.3.1 (3814657376): track and footings built from the build menu
-- are entities (SpriteConfig), one GameEntity per tile. The mod itself keeps
-- the network in global ModData, finds track by sprite name, and its rail
-- laying car / elevated beams / prebuilt lines already use plain IsoObjects.
-- This file swaps each build-menu track or footing tile for a plain IsoObject
-- with the same sprite a moment after it is built, so the world keeps no
-- Monorails track entities. Station signs and the elevated station stay as
-- they are (a few per network; their removal handler would drop the station).
-- Squares that load with an old entity track tile get swapped too.
-- ASCII only.

if not MR_TrackServer or not MR_TrackState or not MR_TrackSprites then return end
if MR_TrackServer.CSP_plain then return end
MR_TrackServer.CSP_plain = true

local DELAY_MS = 500     -- let the build finish all tiles of the piece first
local PER_TICK = 40      -- squares per tick at most
local GUARD_MS = 10000   -- how long a swapped object stays in the guard list

local queue, queued = {}, {}
local swapped, swappedCount = {}, 0
local total = 0

local function isTrackSprite(name)
    if not name then return false end
    local a = MR_TrackSprites.byName and MR_TrackSprites.byName[name]
    local b = MR_TrackSprites.footingByName and MR_TrackSprites.footingByName[name]
    return (a ~= nil) or (b ~= nil)
end

local function push(x, y, z, now)
    local k = x .. "," .. y .. "," .. z
    if queued[k] then return end
    queued[k] = true
    queue[#queue + 1] = { x, y, z, now + DELAY_MS, k }
end

-- Swap every entity track/footing tile on the square for a plain object.
local function swapSquare(sq)
    local objs = sq:getObjects()
    local n = 0
    for i = objs:size() - 1, 0, -1 do
        local o = objs:get(i)
        if o and instanceof(o, "IsoThumpable") then
            local sp = o:getSprite()
            local name = sp and sp:getName()
            if isTrackSprite(name) then
                swapped[o] = getTimestampMs()
                swappedCount = swappedCount + 1
                sq:transmitRemoveItemFromSquare(o)
                o:removeFromWorld()
                o:removeFromSquare()
                local plain = IsoObject.new(getCell(), sq, name)
                if i <= sq:getObjects():size() then sq:AddTileObject(plain, i) else sq:AddTileObject(plain) end
                if isServer() then plain:transmitCompleteItemToClients() end
                n = n + 1
            end
        end
    end
    return n
end

-- New pieces from the build menu: queue their squares (and the footing level).
local origAdd = MR_TrackServer.addPiece
MR_TrackServer.addPiece = function(kind, x, y, z, r, quiet, ...)
    local id, err = origAdd(kind, x, y, z, r, quiet, ...)
    if id and not quiet then
        local piece = MR_TrackState.network().pieces[id]
        local geo = piece and piece.geo
        if geo and geo.tiles then
            local now = getTimestampMs()
            for _, t in ipairs(geo.tiles) do
                push(t[1], t[2], piece.z, now)
                if piece.z > 0 then push(t[1], t[2], piece.z - 1, now) end
            end
        end
    end
    return id, err
end

-- A square that loads with an entity track tile (built before this patch).
local origLoaded = MR_TrackServer.squareLoaded
MR_TrackServer.squareLoaded = function(sq, info, ...)
    if info and info.track and instanceof(info.track, "IsoThumpable") then
        push(sq:getX(), sq:getY(), sq:getZ(), getTimestampMs())
    end
    return origLoaded(sq, info, ...)
end

-- The mod queues a piece for removal when one of its tiles goes away.
-- A tile we swapped is not a removal.
local origRemove = MR_TrackServer.removePiece
MR_TrackServer.removePiece = function(id, except, ...)
    if except ~= nil and swapped[except] then return nil end
    return origRemove(id, except, ...)
end

local function onTick()
    local now = getTimestampMs()
    if #queue > 0 then
        local keep, done, n = {}, 0, 0
        local cell = getCell()
        for _, e in ipairs(queue) do
            if done < PER_TICK and now >= e[4] then
                done = done + 1
                queued[e[5]] = nil
                local sq = cell and cell:getGridSquare(e[1], e[2], e[3])
                if sq then
                    local ok, res = pcall(swapSquare, sq)
                    if ok then n = n + res else print("[CSP] monorails-plain ERROR at " .. e[5] .. ": " .. tostring(res)) end
                end
            else
                keep[#keep + 1] = e
            end
        end
        queue = keep
        if n > 0 then
            total = total + n
            print("[CSP] monorails-plain: " .. n .. " tile(s) -> plain (total " .. total .. ")")
        end
    end
    if swappedCount > 0 then
        for o, t in pairs(swapped) do
            if now - t > GUARD_MS then swapped[o] = nil; swappedCount = swappedCount - 1 end
        end
    end
end
Events.OnTick.Add(onTick)

print("[CSP] monorails-plain on")
