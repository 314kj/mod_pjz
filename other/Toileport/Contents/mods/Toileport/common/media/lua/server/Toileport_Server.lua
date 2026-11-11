--[[ ============================================================
  TOILEPORT  [MP]  --  server (authoritative)           KACHASIG
  Runs on dedicated/host server AND in singleplayer.
    * owns the ModData config/registry
    * gates admin-only edits with a lowercase WHITELIST (not a
      "None" blacklist -- a plain "user" would pass that)
    * validates + consumes the ticket, then orders the client to
      teleport (client owns its own position in B42 MP)
    * broadcasts config so clients can build menus
  Dispatch borrows the TraderVendingMachine shape: a handler table
  with a per-handler pcall so one bad call can't kill the event.
============================================================ ]]

require "Toileport_Shared"

local TP = Toileport

----------------------------------------------------------------
-- broadcast (payload always carries version => never all-nil)
----------------------------------------------------------------
local function broadcastConfig(toPlayer)
    local cfg = TP.getServerConfig()
    local payload = {
        version  = cfg.version or 1,
        stations = cfg.stations or {},
        tickets  = cfg.tickets or {},
    }
    pcall(function()
        if toPlayer then
            sendServerCommand(toPlayer, TP.MODULE, "syncConfig", payload)
        else
            sendServerCommand(TP.MODULE, "syncConfig", payload)
        end
    end)
end

local function notify(player, text)
    if not player then return end
    pcall(function()
        sendServerCommand(player, TP.MODULE, "notify", { text = tostring(text or "") })
    end)
end

local function isAdminPlayer(player)
    if TP.isSP() then return true end
    if not player then return false end
    local lvl
    pcall(function() lvl = string.lower(tostring(player:getAccessLevel() or "")) end)
    return lvl == "admin" or lvl == "moderator" or lvl == "gm"
end

----------------------------------------------------------------
-- handlers
----------------------------------------------------------------
local H = {}

function H.requestConfig(player, _args)
    broadcastConfig(player)
end

function H.registerStation(player, args)
    local ok, info = TP.srvRegister(player, args)
    if ok then broadcastConfig(nil)
    else notify(player, "Toileport: register failed (" .. tostring(info) .. ")") end
end

function H.unregisterStation(player, args)
    if TP.srvUnregister(args) then broadcastConfig(nil) end
end

function H.setStationName(player, args)
    if TP.srvSetStationName(args) then broadcastConfig(nil) end
end

function H.setTicketDest(player, args)
    if TP.srvSetTicketDest(args) then broadcastConfig(nil) end
end

function H.clearTicket(player, args)
    if TP.srvClearTicket(args) then broadcastConfig(nil) end
end

function H.toggleAccept(player, args)
    if TP.srvToggleAccept(args) then broadcastConfig(nil) end
end

function H.toggleMapVisible(player, args)
    if TP.srvToggleMapVisible(args) then broadcastConfig(nil) end
end

function H.forceRegister(player, args)
    local ok, info = TP.srvForceRegister(player, args)
    if ok then broadcastConfig(nil)
    else notify(player, "Toileport: force-register failed (" .. tostring(info) .. ")") end
end

function H.useTicket(player, args)
    args = args or {}
    local originKey = TP.squareKey(args.x, args.y, args.z)
    local ft = args.fullType
    local ok, a, b, c, name = TP.srvUseTicket(player, originKey, ft)
    if ok then
        pcall(function()
            sendServerCommand(player, TP.MODULE, "teleportTo", {
                x = a, y = b, z = c, name = name,
            })
        end)
    else
        local reasons = {
            not_registered = "this toilet is not a station",
            not_accepted   = "this station does not accept that ticket",
            ticket_unset   = "this ticket has no destination set",
            no_ticket      = "ticket not found in inventory",
        }
        notify(player, "Toileport: " .. (reasons[a] or tostring(a)))
    end
end

-- which commands require admin rights
local ADMIN_ONLY = {
    registerStation = true, unregisterStation = true, setStationName = true,
    setTicketDest = true, clearTicket = true, toggleAccept = true,
    toggleMapVisible = true, forceRegister = true,
}

----------------------------------------------------------------
-- single dispatcher
----------------------------------------------------------------
local function onClientCommand(module, command, player, args)
    if module ~= TP.MODULE then return end
    args = args or {}

    local h = H[command]
    if not h then return end

    if ADMIN_ONLY[command] and not isAdminPlayer(player) then
        notify(player, "Toileport: admin only.")
        return
    end

    local ok, err = pcall(h, player, args)
    if not ok then
        print("[Toileport] ERROR handler '" .. tostring(command) .. "': " .. tostring(err))
    end
end
Events.OnClientCommand.Add(onClientCommand)

-- push config to every newly connecting player (covers reconnects with no admin present)
-- guard: OnPlayerConnect exists in some B42 builds but not all
if Events.OnPlayerConnect then
    Events.OnPlayerConnect.Add(function(player)
        if not player then return end
        pcall(function() broadcastConfig(player) end)
    end)
end

print("[Toileport] server loaded")
