-- Cookie On the Way : client state and network
-- Keeps this player's home / pins / trip history, the scanned vehicle list and admin roads the server
-- sends, the last quote, the running trip and the navigator route. UI files read COTW.C and call
-- the helpers here; nothing on the client decides a price.

require "CookieOnTheWay/COTW_RoadData"

COTW.C = COTW.C or {
    home = nil, pins = {}, hist = {}, profiles = {},
    dest = nil,        -- { x, y, name } picked in the panel / on the map
    quote = nil,       -- last answer to "quote" (or { err = ... })
    trip = nil,        -- { id, state = "billing"|"ready"|"driving", gid, order, route, held }
    riding = nil,      -- { id, booker } when sitting in someone else's trip
    nav = nil,         -- { route, destX, destY } navigator (free, drive yourself)
    lead = nil,        -- { rem, spd, t } car in front in a group trip
    invite = nil,      -- { gid, leader, x, y }
    lastEnd = nil,     -- summary of the last trip that ended
}
local C = COTW.C

function COTW.player() return getSpecificPlayer(0) end

function COTW.send(cmd, args)
    local p = COTW.player()
    if not p then return end
    sendClientCommand(p, COTW.MOD, cmd, args or {})
end

function COTW.isAdmin()
    if not isClient() then return true end
    local lvl = getAccessLevel and getAccessLevel()
    return lvl and string.lower(tostring(lvl)) == "admin"
end

function COTW.say(key, a, b)
    local p = COTW.player()
    if not p then return end
    local text = getText(key, a, b)
    HaloTextHelper.addText(p, text)
end

-- driver seat of a running vehicle?
function COTW.driving()
    local p = COTW.player()
    local v = p and p:getVehicle()
    if v and v:getDriver() == p then return v end
    return nil
end

function COTW.profileFor(vehicle)
    local key = vehicle and COTW.vehicleKey(vehicle)
    return key and C.profiles[key] or nil, key
end

-- ------------------------------------------------------------------------------
-- destination / navigator
-- ------------------------------------------------------------------------------
function COTW.setDest(x, y, name)
    C.dest = { x = math.floor(x), y = math.floor(y), name = name }
    C.quote = nil
    if COTWPanel and COTWPanel.instance then COTWPanel.instance:refresh() end
end

-- the pin goes away with the trip / navigator it was for (and from the map menu)
function COTW.clearDest()
    C.dest = nil
    C.quote = nil
    if COTWPanel and COTWPanel.instance then COTWPanel.instance:layout() end
end

function COTW.startNav(x, y)
    local p = COTW.player()
    if not p then return false end
    local route, why = COTW.Graph.route(p:getX(), p:getY(), x, y)
    if not route then
        COTW.say("IGUI_COTW_Err_" .. tostring(why))
        return false
    end
    C.nav = { route = route, destX = x, destY = y }
    C.navIdx = 1
    return true
end

-- the pin goes with the navigator only when it is that navigator's pin
function COTW.stopNav()
    local nav = C.nav
    C.nav = nil
    if nav and C.dest and C.dest.x == nav.destX and C.dest.y == nav.destY then COTW.clearDest() end
end

-- ------------------------------------------------------------------------------
-- server -> client
-- ------------------------------------------------------------------------------
local S = {}

local function applyWorld(args)
    if type(args.profiles) == "table" then C.profiles = args.profiles end
    if type(args.roads) == "table" then COTW.Graph.setExtra(args.roads) end
end

function S.state(args)
    C.home = args.home
    C.pins = type(args.pins) == "table" and args.pins or {}
    C.hist = type(args.hist) == "table" and args.hist or {}
    applyWorld(args)
end

S.world = applyWorld

function S.quote(args)
    C.quote = args
    if args.err then COTW.say("IGUI_COTW_Err_" .. tostring(args.err)) end
end

function S.booked(args)
    C.trip = { id = args.id, state = "billing", gid = args.gid, held = args.held }
end

function S.ready(args)
    if C.trip and C.trip.id == args.id then C.trip.state = "ready" end
end

function S.go(args)
    C.trip = C.trip or {}
    C.trip.id, C.trip.state, C.trip.gid, C.trip.order = args.id, "driving", args.gid, args.order
    C.trip.route = args.route
    C.lead = nil
    C.nav = nil
    COTW.Driver.start(args.route)
    if COTWPanel and COTWPanel.instance then COTWPanel.instance:close() end
end

function S.riding(args) C.riding = { id = args.id, booker = args.booker } end

function S.ended(args)
    if C.trip and C.trip.id == args.id then
        COTW.Driver.stop()
        -- destination off the road: the navigator takes over for the last bit (the pin stays until it ends)
        local r = C.trip.route
        local handOff = args.reason == "arrive" and r and r.destX and COTW.dist(r.x[#r.x], r.y[#r.y], r.destX, r.destY) > 15
        if not (handOff and COTW.startNav(r.destX, r.destY)) then COTW.clearDest() end
        C.trip = nil
    end
    if C.riding and C.riding.id == args.id then C.riding = nil end
    C.lastEnd = args
    C.lastEnd.t = getTimestampMs()
    COTW.send("hello")
end

function S.bill(args)
    if COTWBill then COTWBill.show(args) end
end

function S.note(args) COTW.say(args.key, args.a, args.b) end

function S.groupInvite(args)
    C.invite = args
    if COTWBill then COTWBill.invite(args) end
end

function S.groupMember(args) COTW.say("IGUI_COTW_GroupJoined", args.name, tostring(args.n)) end

function S.lead(args)
    if args.done then C.lead = nil; return end
    C.lead = { rem = tonumber(args.rem), spd = tonumber(args.spd) or 0, t = getTimestampMs() }
end

local function onServerCommand(module, command, args)
    if module ~= COTW.MOD then return end
    local fn = S[command]
    if not fn then return end
    local ok, err = pcall(fn, args or {})
    if not ok then COTW.log("server command " .. tostring(command) .. " error: " .. tostring(err)) end
end

local helloAt = nil
local function onTick()
    -- ask once the player exists (a few ticks after load)
    if helloAt and getTimestampMs() >= helloAt and COTW.player() then
        helloAt = nil
        COTW.send("hello")
    end
end

local function onGameStart() helloAt = getTimestampMs() + 2000 end

Events.OnServerCommand.Add(onServerCommand)
Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
