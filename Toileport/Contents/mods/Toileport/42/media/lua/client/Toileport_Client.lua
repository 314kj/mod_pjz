--[[ ============================================================
  TOILEPORT  [MP]  --  client networking                KACHASIG
    * keeps TP.clientCache synced from the server (syncConfig)
    * on "teleportTo": show the loading overlay, then warp
    * exposes senders the context menu calls; each one runs the
      shared authoritative op directly in SP, or sends a command
      to the server in MP.
============================================================ ]]

require "Toileport_Shared"

local TP = Toileport
TP.clientCache = TP.clientCache or nil

----------------------------------------------------------------
-- server -> client
----------------------------------------------------------------
local function onServerCommand(module, command, args)
    if module ~= TP.MODULE then return end
    args = args or {}

    if command == "syncConfig" then
        TP.clientCache = {
            version  = args.version or 1,
            stations = args.stations or {},
            tickets  = args.tickets or {},
        }
        if ToileportPanel and ToileportPanel.refreshIfOpen then
            pcall(function() ToileportPanel.refreshIfOpen() end)
        end
        print("[Toileport] client cache synced")

    elseif command == "teleportTo" then
        local p = getPlayer()
        if not p then return end
        local x, y, z = args.x, args.y, args.z or 0
        local name = args.name or "destination"
        TP.showLoading(TP.getLoadingSeconds(), function()
            local pl = getPlayer()
            if not pl then return end
            TP.doTeleport(pl, x, y, z)
            if pl.Say then pl:Say("Arrived: " .. tostring(name)) end
        end)

    elseif command == "notify" then
        local p = getPlayer()
        if p and args.text and p.Say then p:Say(tostring(args.text)) end
    end
end
Events.OnServerCommand.Add(onServerCommand)

----------------------------------------------------------------
-- request config on join (MP only); retry once if cache still empty
----------------------------------------------------------------
local _retryTick = 0
local _retryDone = false

local function requestConfig()
    local pl = getPlayer()
    if pl then
        pcall(function() sendClientCommand(pl, TP.MODULE, "requestConfig", { ping = true }) end)
    end
end

Events.OnGameStart.Add(function()
    if isClient() then
        _retryTick = 0
        _retryDone = false
        requestConfig()
    end
end)

-- fallback: if syncConfig never arrived (e.g. race condition), retry after ~5 s
Events.OnTick.Add(function()
    if not isClient() then return end
    if TP.clientCache or _retryDone then return end
    _retryTick = _retryTick + 1
    if _retryTick >= 300 then   -- ~5 s at 60 fps
        _retryDone = true
        requestConfig()
    end
end)

----------------------------------------------------------------
-- senders. SP runs the shared op directly + (locally) refreshes;
-- MP sends a command and the server validates + broadcasts.
----------------------------------------------------------------
local function spNotify(text)
    local p = getPlayer()
    if p and p.Say then p:Say(tostring(text)) end
end

function TP.adminRegister(player, sq)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    if TP.isSP() then
        local ok, info = TP.srvRegister(player, { x = x, y = y, z = z })
        spNotify(ok and "Toileport: station registered" or ("Toileport: " .. tostring(info)))
    else
        sendClientCommand(player, TP.MODULE, "registerStation", { x = x, y = y, z = z })
    end
end

function TP.adminUnregister(player, key)
    if TP.isSP() then
        if TP.srvUnregister({ key = key }) then spNotify("Toileport: station removed") end
    else
        sendClientCommand(player, TP.MODULE, "unregisterStation", { key = key })
    end
end

function TP.adminSetStationName(player, key, name)
    if TP.isSP() then
        TP.srvSetStationName({ key = key, name = name })
    else
        sendClientCommand(player, TP.MODULE, "setStationName", { key = key, name = name })
    end
end

function TP.adminSetTicketDest(player, ft, destKey, name)
    if TP.isSP() then
        if TP.srvSetTicketDest({ fullType = ft, destKey = destKey, name = name }) then
            spNotify("Toileport: ticket destination set")
        end
    else
        sendClientCommand(player, TP.MODULE, "setTicketDest",
            { fullType = ft, destKey = destKey, name = name })
    end
end

function TP.adminClearTicket(player, ft)
    if TP.isSP() then
        TP.srvClearTicket({ fullType = ft })
    else
        sendClientCommand(player, TP.MODULE, "clearTicket", { fullType = ft })
    end
end

function TP.adminToggleAccept(player, key, ft)
    if TP.isSP() then
        TP.srvToggleAccept({ key = key, fullType = ft })
    else
        sendClientCommand(player, TP.MODULE, "toggleAccept", { key = key, fullType = ft })
    end
end

function TP.adminToggleMap(player, key)
    if TP.isSP() then
        TP.srvToggleMapVisible({ key = key })
    else
        sendClientCommand(player, TP.MODULE, "toggleMapVisible", { key = key })
    end
end

function TP.adminForceRegister(player, sq)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    if TP.isSP() then
        local ok, info = TP.srvForceRegister(player, { x = x, y = y, z = z })
        spNotify(ok and "Toileport: station force-registered" or ("Toileport: " .. tostring(info)))
    else
        sendClientCommand(player, TP.MODULE, "forceRegister", { x = x, y = y, z = z })
    end
end

-- player: use a ticket at the origin toilet square
function TP.useTicket(player, sq, ft)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    if TP.isSP() then
        local originKey = TP.squareKey(x, y, z)
        local ok, a, b, c, name = TP.srvUseTicket(player, originKey, ft)
        if ok then
            TP.showLoading(TP.getLoadingSeconds(), function()
                local pl = getPlayer()
                if not pl then return end
                TP.doTeleport(pl, a, b, c)
                if pl.Say then pl:Say("Arrived: " .. tostring(name)) end
            end)
        else
            spNotify("Toileport: " .. tostring(a))
        end
    else
        sendClientCommand(player, TP.MODULE, "useTicket", { x = x, y = y, z = z, fullType = ft })
    end
end

print("[Toileport] client net loaded")
