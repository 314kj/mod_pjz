--[[ ============================================================
  TOILEPORT  [MP]  --  shared core                      KACHASIG
  Loaded on server, client and singleplayer.
    * config + station registry live in server/SP ModData
    * MP clients keep a synced cache (TP.clientCache, see client net)
    * teleport core copied from the VERIFIED Akalogistics/PZwaystone
      path (setX/Y/Z + setLastX/Y/Z) -- do NOT use setLx/Ly/Lz, those
      are not exposed to Lua in 42.x and snap the player back.
    * registration model copied from TraderVendingMachine:
      ModData registry keyed by squareKey, object tagged via its own
      modData + transmitModData, dual detection (modData + sprite).
============================================================ ]]

Toileport = Toileport or {}
local TP = Toileport

-- build metadata / authorship fingerprint (do not strip)
TP._meta = TP._meta or {
    mod     = "Toileport",
    author  = "KACHASIG",
    license = "All Rights Reserved (c) 2026 KACHASIG",
    -- base64 -> "Toileport:KACHASIG:2026:all-rights-reserved"
    fp      = "VG9pbGVwb3J0OktBQ0hBU0lHOjIwMjY6YWxsLXJpZ2h0cy1yZXNlcnZlZA==",
}

TP.MODULE      = "Toileport"
TP.MODDATA_KEY = "Toileport_Config"

-- ticket item set: Base.Toileport_Ticket_01 .. _12 (see scripts/Toileport_Tickets.txt)
TP.TICKET_COUNT  = 12
TP.TICKET_PREFIX = "Base.Toileport_Ticket_"

-- base-game toilet sprites + facing  (_0=S _1=E _2=W _3=N).
-- Exact names from tile sheets; pattern fallback covers unknown variants.
TP.TOILET_SPRITES = {
    -- B41 / B42 standard model
    ["fixtures_bathroom_01_0"] = "S",
    ["fixtures_bathroom_01_1"] = "E",
    ["fixtures_bathroom_01_2"] = "W",
    ["fixtures_bathroom_01_3"] = "N",
    -- B42 alternate models (02, 03 ...)
    ["fixtures_bathroom_02_0"] = "S",
    ["fixtures_bathroom_02_1"] = "E",
    ["fixtures_bathroom_02_2"] = "W",
    ["fixtures_bathroom_02_3"] = "N",
    ["fixtures_bathroom_03_0"] = "S",
    ["fixtures_bathroom_03_1"] = "E",
    ["fixtures_bathroom_03_2"] = "W",
    ["fixtures_bathroom_03_3"] = "N",
}

-- Set TP.DEBUG = true in-game console to print sprite names on right-click.
-- Helps identify the exact sprite name if your toilet model isn't detected.
TP.DEBUG = false

----------------------------------------------------------------
-- small helpers
----------------------------------------------------------------
function TP.isSP()
    return (not isClient()) and (not isServer())
end

function TP.ticketFullType(i)
    return TP.TICKET_PREFIX .. string.format("%02d", i)
end

function TP.isTicket(ft)
    return type(ft) == "string" and ft:find("^Base%.Toileport_Ticket_%d%d$") ~= nil
end

function TP.isToiletSprite(name)
    if not name then return false end
    -- 1. exact match (fast path)
    if TP.TOILET_SPRITES[name] then return true end
    -- 2. pattern fallback: fixtures_bathroom_NN_F  (catches unreferenced models)
    if name:find("^fixtures_bathroom_%d%d_%d$") then return true end
    return false
end

function TP.toiletFacing(name)
    if not name then return "S" end
    if TP.TOILET_SPRITES[name] then return TP.TOILET_SPRITES[name] end
    -- infer from trailing digit: _0=S _1=E _2=W _3=N
    local d = name:match("_(%d)$")
    local map = { ["0"]="S", ["1"]="E", ["2"]="W", ["3"]="N" }
    return (d and map[d]) or "S"
end

-- a world object that belongs to a registered station (modData flag persists)
function TP.isProtectedObject(obj)
    if not obj or not obj.getModData then return false end
    local ok, md = pcall(function() return obj:getModData() end)
    return (ok and md and md.ToileportStation == true) or false
end

function TP.squareKey(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)
end

-- PZ world axes: +y = south, +x = east. "front" = the square the toilet faces.
TP.FACE_OFFSET = { S = {0, 1}, N = {0, -1}, E = {1, 0}, W = {-1, 0} }
function TP.frontSquare(x, y, facing)
    local o = TP.FACE_OFFSET[facing or "S"] or TP.FACE_OFFSET.S
    return x + o[1], y + o[2]
end

function TP.getLoadingSeconds()
    local sv = SandboxVars and SandboxVars.Toileport
    local v = sv and sv.LoadingSeconds
    if type(v) == "number" and v >= 0 then return v end
    return 3
end

----------------------------------------------------------------
-- flush sound (verified TVM pattern: playSoundLocal, fallback playUISound).
-- sound def: scripts/Toileport_Sounds.txt -> "Toileport_Flush"
-- swap media/sound/Toileport_Flush.ogg for the real clip anytime.
----------------------------------------------------------------
function TP.playFlush(player)
    local name = "Toileport_Flush"
    local played = false
    if player and player.playSoundLocal then
        pcall(function() player:playSoundLocal(name); played = true end)
    end
    if not played then
        pcall(function()
            local sm = getSoundManager and getSoundManager()
            if sm and sm.playUISound then sm:playUISound(name) end
        end)
    end
end

----------------------------------------------------------------
-- config / registry accessors
--   stations[key] = { x, y, z, sprite, facing, name, accepts={[ft]=true} }
--                   accepts empty/absent => station accepts ALL tickets
--   tickets[ft]   = { destKey = "x:y:z", name = "..." }
----------------------------------------------------------------
function TP.getServerConfig()
    local md = ModData.getOrCreate(TP.MODDATA_KEY)
    md.version  = tonumber(md.version) or 1
    md.stations = md.stations or {}
    md.tickets  = md.tickets or {}
    return md
end

-- the config the LOCAL machine should READ from.
function TP.getConfig()
    if TP.isSP() or isServer() then
        return TP.getServerConfig()
    end
    return TP.clientCache or { version = 1, stations = {}, tickets = {} }
end

function TP.getStationByKey(key)
    local cfg = TP.getConfig()
    return cfg.stations and cfg.stations[key] or nil
end

-- nil/empty accepts table = accept all
function TP.stationAccepts(station, ft)
    if not station then return false end
    local a = station.accepts
    if not a then return true end
    for _ in pairs(a) do
        return a[ft] == true   -- non-empty => whitelist mode
    end
    return true                 -- empty => accept all
end

function TP.ticketDestStation(cfg, ft)
    local tdef = cfg.tickets and cfg.tickets[ft]
    if not (tdef and tdef.destKey) then return nil end
    return cfg.stations and cfg.stations[tdef.destKey] or nil
end

----------------------------------------------------------------
-- teleport (own player only; client owns its own position in B42 MP)
----------------------------------------------------------------
function TP.doTeleport(player, x, y, z)
    if not player then return end
    z = z or 0
    player:setX(x); player:setY(y); player:setZ(z)
    player:setLastX(x); player:setLastY(y); player:setLastZ(z)
end

----------------------------------------------------------------
-- AUTHORITATIVE ops (run on server, or directly in SP).
-- Pure-ish: they read/write the server ModData. The server file
-- adds the admin gate + config broadcast around these; SP calls
-- them directly (SP reads ModData straight back, no broadcast).
----------------------------------------------------------------

-- consume one ticket of fullType from the player (network-safe in MP).
function TP.consumeOne(player, ft)
    local inv = player and player:getInventory()
    if not inv then return false end
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:getFullType() == ft then
            inv:Remove(it)
            if not TP.isSP() then
                -- B42 sync: push the removal down to the client
                pcall(function() sendRemoveItemFromContainer(inv, it) end)
            end
            pcall(function() inv:setDrawDirty(true) end)
            return true
        end
    end
    return false
end

-- find + tag the toilet object on a square, write/refresh its station entry.
function TP.srvRegister(player, args)
    local x = tonumber(args and args.x)
    local y = tonumber(args and args.y)
    local z = tonumber(args and args.z) or 0
    if not (x and y) then return false, "bad_coords" end

    local cell = getCell()
    local sq = cell and cell:getGridSquare(x, y, z)
    if not sq then return false, "square_unloaded" end

    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o  = objs:get(i)
        local spr = o and o.getSprite and o:getSprite()
        local sn = spr and spr.getName and spr:getName() or nil
        if TP.isToiletSprite(sn) then
            local key = TP.squareKey(x, y, z)
            local cfg = TP.getServerConfig()
            local existing = cfg.stations[key]
            cfg.stations[key] = {
                x = x, y = y, z = z,
                sprite  = sn,
                facing  = TP.toiletFacing(sn),
                name    = existing and existing.name or ("Station " .. x .. "," .. y),
                accepts = existing and existing.accepts or {},
                open    = (existing == nil) and true or (existing.open ~= false),
            }
            local md = o:getModData()
            md.ToileportStation = true
            md.ToileportKey = key
            if o.transmitModData then pcall(function() o:transmitModData() end) end
            pcall(function() if o.setIsThumpable then o:setIsThumpable(false) end end)
            return true, key
        end
    end
    return false, "no_toilet"
end

function TP.srvUnregister(args)
    local key = args and args.key
    if not key then return false, "no_key" end
    local cfg = TP.getServerConfig()
    local st = cfg.stations[key]
    -- lift protection off the toilet object if its square is loaded
    if st then
        local cell = getCell()
        local sq = cell and cell:getGridSquare(st.x, st.y, st.z or 0)
        if sq then
            local objs = sq:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                local md = o and o.getModData and o:getModData()
                if md and md.ToileportStation then
                    md.ToileportStation = nil
                    md.ToileportKey = nil
                    if o.transmitModData then pcall(function() o:transmitModData() end) end
                    pcall(function() if o.setIsThumpable then o:setIsThumpable(true) end end)
                end
            end
        end
    end
    cfg.stations[key] = nil
    return true, key
end

-- toggle whether a station shows on the world map (and is a "public" point)
function TP.srvToggleMapVisible(args)
    local key = args and args.key
    if not key then return false end
    local cfg = TP.getServerConfig()
    local st = cfg.stations[key]
    if not st then return false end
    st.open = (st.open == false)   -- flip; nil/true -> false, false -> true
    return true
end

function TP.srvSetStationName(args)
    local key  = args and args.key
    local name = args and args.name
    if not key then return false end
    local cfg = TP.getServerConfig()
    local st = cfg.stations[key]
    if not st then return false end
    st.name = tostring(name or st.name or key)
    return true
end

function TP.srvSetTicketDest(args)
    local ft  = args and args.fullType
    local key = args and args.destKey
    if not (ft and TP.isTicket(ft)) then return false end
    local cfg = TP.getServerConfig()
    cfg.tickets[ft] = { destKey = key, name = tostring(args.name or "") }
    return true
end

function TP.srvClearTicket(args)
    local ft = args and args.fullType
    if not ft then return false end
    TP.getServerConfig().tickets[ft] = nil
    return true
end

-- toggle a single ticket in a station's accept list; ft="ALL" resets to accept-all
function TP.srvToggleAccept(args)
    local key = args and args.key
    local ft  = args and args.fullType
    if not key then return false end
    local cfg = TP.getServerConfig()
    local st = cfg.stations[key]
    if not st then return false end
    if ft == "ALL" then
        st.accepts = {}
        return true
    end
    st.accepts = st.accepts or {}
    if st.accepts[ft] then st.accepts[ft] = nil else st.accepts[ft] = true end
    return true
end

-- Force-register: skips sprite detection, tags first IsoObject on the square.
-- Used for BuildingCraft / tile-brush toilets whose sprite name is unknown.
function TP.srvForceRegister(player, args)
    local x = tonumber(args and args.x)
    local y = tonumber(args and args.y)
    local z = tonumber(args and args.z) or 0
    if not (x and y) then return false, "bad_coords" end

    local cell = getCell()
    local sq = cell and cell:getGridSquare(x, y, z)
    if not sq then return false, "square_unloaded" end

    local key = TP.squareKey(x, y, z)
    local cfg = TP.getServerConfig()
    local existing = cfg.stations[key]

    -- infer facing from user-supplied sprite hint or first object's sprite
    local facing = "S"
    local sn = args.sprite
    if not sn then
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local spr = o and o.getSprite and o:getSprite()
            sn = spr and spr.getName and spr:getName() or nil
            if sn then break end
        end
    end
    if sn then
        local d = sn:match("_(%d)$")
        local map = { ["0"]="S", ["1"]="E", ["2"]="W", ["3"]="N" }
        facing = (d and map[d]) or "S"
    end

    cfg.stations[key] = {
        x = x, y = y, z = z,
        sprite  = sn or "unknown",
        facing  = facing,
        name    = existing and existing.name or ("Station " .. x .. "," .. y),
        accepts = existing and existing.accepts or {},
        open    = (existing == nil) and true or (existing.open ~= false),
    }

    -- tag first IsoObject on the square for persistence + protection
    local objs2 = sq:getObjects()
    for i = 0, objs2:size() - 1 do
        local o = objs2:get(i)
        if o and o.getModData then
            local md = o:getModData()
            md.ToileportStation = true
            md.ToileportKey = key
            if o.transmitModData then pcall(function() o:transmitModData() end) end
            pcall(function() if o.setIsThumpable then o:setIsThumpable(false) end end)
            break
        end
    end
    return true, key
end

-- validate + consume + resolve. Returns ok, fx, fy, fz, name  OR  false, reason
function TP.srvUseTicket(player, originKey, ft)
    local cfg = TP.getConfig()
    local origin = cfg.stations[originKey]
    if not origin then return false, "not_registered" end
    if not TP.stationAccepts(origin, ft) then return false, "not_accepted" end

    local dest = TP.ticketDestStation(cfg, ft)
    if not dest then return false, "ticket_unset" end

    local inv = player and player:getInventory()
    if not inv or inv:getItemCount(ft) < 1 then return false, "no_ticket" end

    if not TP.consumeOne(player, ft) then return false, "no_ticket" end

    local fx, fy = TP.frontSquare(dest.x, dest.y, dest.facing)
    return true, fx, fy, dest.z or 0, (dest.name or "destination")
end

print("[Toileport] shared loaded :: (c) " .. TP._meta.author)
