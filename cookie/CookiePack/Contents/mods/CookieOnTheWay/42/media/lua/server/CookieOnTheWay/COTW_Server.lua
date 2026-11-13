-- Cookie On the Way : server side
-- Owns pins, scanned vehicle profiles, admin roads and every trip. Prices each trip from its own route,
-- holds the money up front (Cookie Exchange wallet), counts the distance really driven from the
-- vehicle's position every second, and refunds the unused part when a trip ends early.
-- Commands: hello, setHome, setPin, delPin, quote, book, payBill, cancel, prog, finish,
--           groupJoin, groupStart, saveProfile, delProfile, saveRoad, delRoad
if isClient() and not isServer() then return end

require "CookieOnTheWay/COTW_RoadData"

local TICK_MS = 1000
local STEP_CAP = 32          -- most tiles one 1 s sample may add (90 km/h = 25 m/s)
local STALL_MS = 60000       -- no progress report for this long = trip over (by distance)
local READY_MS = 300000      -- a booked group car waits this long for the leader to start
local ARRIVE_SLACK = 30      -- "arrived" must be this close to the route end
local HISTORY = 10
local ASK_MS = 1000

local db = nil
local trips = {}             -- id -> trip (live, not saved: a restart ends every trip by distance via db.open)
local groups = {}            -- gid -> { leader, dest, members = { tripId, ... }, started }
local lastTick = 0
local booted = false

local function nowMs() return getTimestampMs() end

local function DB()
    if db then return db end
    db = ModData.getOrCreate(COTW.DB_KEY)
    db.v = db.v or 1
    db.users = db.users or {}
    db.profiles = db.profiles or {}
    db.roads = db.roads or {}
    db.open = db.open or {}       -- trips that held money, so a crash can refund them on boot
    db.nextId = db.nextId or 1
    return db
end

-- a finite map coordinate (rejects NaN, inf and silly values a client could send)
local function coord(v) return type(v) == "number" and v == v and v > -100000 and v < 100000 end

local function nameOf(p)
    local ok, n = pcall(function() return p:getUsername() end)
    if ok and n and n ~= "" then return n end
    return nil
end

local function user(name)
    local u = DB().users[name]
    if not u then
        u = { pins = {}, hist = {} }
        DB().users[name] = u
    end
    return u
end

local function forOnline(fn)
    if not isServer() then
        local p = getSpecificPlayer(0)
        if p then fn(p) end
        return
    end
    local list = getOnlinePlayers and getOnlinePlayers()
    if not list then return end
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p then fn(p) end
    end
end

local function findOnline(name)
    local hit = nil
    forOnline(function(p) if nameOf(p) == name then hit = p end end)
    return hit
end

local function tell(p, cmd, args)
    if not p then return end
    if isServer() then
        sendServerCommand(p, COTW.MOD, cmd, args or {})
    else
        triggerEvent("OnServerCommand", COTW.MOD, cmd, args or {})
    end
end

local function tellName(name, cmd, args) tell(findOnline(name), cmd, args) end

local function isAdmin(p)
    local ok, lvl = pcall(function() return p:getAccessLevel() end)
    if not isServer() then return true end
    return ok and lvl and string.lower(tostring(lvl)) == "admin"
end

-- ------------------------------------------------------------------------------
-- wallet (Cookie Exchange when present)
-- ------------------------------------------------------------------------------
local function wallet() return CX and CX.server or nil end

local function charge(name, dollars, why)
    if dollars <= 0 then return true end
    local w = wallet()
    if not w then return true end
    return w.charge(name, dollars * 100, "COTW " .. why)
end

local function refund(name, dollars, why)
    if dollars <= 0 then return end
    local w = wallet()
    if w then w.add(name, dollars * 100, "COTW " .. why) end
end

local function canAfford(name, dollars)
    local w = wallet()
    if not w then return true end
    return w.balance(name) >= dollars * 100
end

-- ------------------------------------------------------------------------------
-- vehicles
-- ------------------------------------------------------------------------------
local function seatsOf(vehicle)
    local out = {}
    local ok, n = pcall(function() return vehicle:getMaxPassengers() end)
    if not ok or not n then return out end
    for i = 0, n - 1 do
        local c = vehicle:getCharacter(i)
        local name = c and nameOf(c)
        if name then out[#out + 1] = { seat = i, name = name, player = c } end
    end
    return out
end

local function trailerOf(vehicle)
    local ok, t = pcall(function() return vehicle:getVehicleTowing() end)
    if ok then return t end
    return nil
end

local function fuelPct(vehicle)
    local ok, v = pcall(function() return vehicle:getRemainingFuelPercentage() end)
    if ok and type(v) == "number" then return v end
    return 100
end

local function profileOf(vehicle)
    local key = vehicle and COTW.vehicleKey(vehicle)
    return key and DB().profiles[key] or nil, key
end

-- everything about booking a trip from this vehicle to (x, y); nil + reason if it cannot be booked
local function plan(p, x, y, babyName)
    local vehicle = p:getVehicle()
    if not vehicle then return nil, "not_in_vehicle" end
    if vehicle:getDriver() ~= p then return nil, "not_driver" end
    local prof, key = profileOf(vehicle)
    if not prof then return nil, "not_scanned" end
    local trailer = trailerOf(vehicle)
    if trailer and not profileOf(trailer) then return nil, "trailer_not_scanned" end
    if COTW.opt("RequireWallet") and not wallet() then return nil, "no_wallet" end
    local okE, running = pcall(function() return vehicle:isEngineRunning() end)
    if okE and running == false then return nil, "engine" end
    if fuelPct(vehicle) < COTW.opt("MinFuelPct") then return nil, "low_fuel" end
    local route, why = COTW.Graph.route(vehicle:getX(), vehicle:getY(), x, y)
    if not route then return nil, why end

    local booker = nameOf(p)
    local base = COTW.fare(route.len)
    local seat = COTW.seatFare(base)
    local riders, adults, babyOk = {}, 0, false
    for _, s in ipairs(seatsOf(vehicle)) do
        local baby = COTW.isBaby(s.player)
        if not baby then adults = adults + 1 end
        if s.name ~= booker then
            riders[#riders + 1] = { name = s.name, fare = seat, baby = baby }
        end
    end
    -- baby seat: one per car, not the booker, an adult (anyone not a baby, the booker included) rides along
    if babyName then
        for _, r in ipairs(riders) do
            if r.name == babyName and r.baby and adults >= 1 then
                r.fare = 0
                r.babySeat = true
                babyOk = true
            end
        end
    end
    local total = base + (trailer and COTW.opt("TrailerFee") or 0)
    for _, r in ipairs(riders) do total = total + r.fare end
    return {
        vehicle = vehicle, vid = vehicle:getId(), key = key, route = route,
        base = base, seat = seat, trailerFee = trailer and COTW.opt("TrailerFee") or 0,
        riders = riders, babyOk = babyOk, total = total, booker = booker,
    }
end

local function quoteArgs(pl)
    local riders = {}
    for i, r in ipairs(pl.riders) do
        riders[i] = { name = r.name, fare = r.fare, baby = r.baby, babySeat = r.babySeat }
    end
    return {
        len = math.floor(pl.route.len), base = pl.base, seat = pl.seat, trailerFee = pl.trailerFee,
        riders = riders, total = pl.total, free = wallet() == nil, endGap = pl.route.endGap,
    }
end

-- ------------------------------------------------------------------------------
-- trips
-- ------------------------------------------------------------------------------
local function remember(name, line)
    local h = user(name).hist
    table.insert(h, 1, line)
    while #h > HISTORY do table.remove(h) end
end

local function routeArgs(route)
    return { x = route.x, y = route.y, w = route.w, len = route.len, destX = route.destX, destY = route.destY }
end

local function everyone(trip)
    local out = { trip.booker }
    for _, r in ipairs(trip.riders) do out[#out + 1] = r.name end
    return out
end

local function startTrip(trip)
    trip.state = "driving"
    trip.lastProg = nowMs()
    local v = getVehicleById(trip.vid)
    if v then trip.lx, trip.ly = v:getX(), v:getY() end
    tellName(trip.booker, "go", { id = trip.id, route = routeArgs(trip.route), gid = trip.gid, order = trip.order })
    for _, r in ipairs(trip.riders) do tellName(r.name, "riding", { id = trip.id, booker = trip.booker }) end
end

-- frac of the fare kept for each way a trip can end
local function keptFraction(trip, reason)
    if reason == "arrive" or reason == "intervene" then return 1 end
    local f = trip.route.len > 0 and trip.driven / trip.route.len or 1
    if reason == "emergency" then f = f * (1 + COTW.opt("EmergencyFeePct") / 100) end
    if f > 1 then f = 1 end
    if f < 0 then f = 0 end
    return f
end

local function finish(trip, reason)
    if trip.done then return end
    trip.done = true
    trips[trip.id] = nil
    DB().open[tostring(trip.id)] = nil
    local f = trip.state == "driving" and keptFraction(trip, reason) or 0
    local lines = {}
    for name, paid in pairs(trip.paid) do
        local back = math.floor(paid * (1 - f))
        refund(name, back, "refund trip " .. trip.id .. " (" .. reason .. ")")
        lines[name] = { paid = paid - back, back = back }
    end
    local summary = {
        id = trip.id, reason = reason, driven = math.floor(trip.driven or 0), len = math.floor(trip.route.len),
        free = trip.free,
    }
    for _, name in ipairs(everyone(trip)) do
        local mine = lines[name] or { paid = 0, back = 0 }
        local args = {}
        for k, v in pairs(summary) do args[k] = v end
        args.paid, args.back = mine.paid, mine.back
        tellName(name, "ended", args)
        if trip.state == "driving" then
            remember(name, table.concat({ trip.id, reason, summary.driven, summary.len, mine.paid, trip.booker }, "|"))
        end
    end
    COTW.log("trip " .. trip.id .. " " .. trip.booker .. " ended " .. reason .. " driven " .. summary.driven .. "/" .. summary.len)
    -- the car behind in a group trip drives on alone
    if trip.gid and groups[trip.gid] then
        local g = groups[trip.gid]
        for i, id in ipairs(g.members) do
            if id == trip.id then
                local nxt = trips[g.members[i + 1]]
                if nxt then tellName(nxt.booker, "lead", { done = true }) end
                table.remove(g.members, i)
                break
            end
        end
        if #g.members == 0 then groups[trip.gid] = nil end
    end
end

-- all bills settled (or timed out): money is held, the car may go
local function billsSettled(trip)
    for _, r in ipairs(trip.riders) do
        if r.bill and not trip.paid[r.name] then
            -- a friend who did not pay in time: the booker pays for them
            if not charge(trip.booker, r.fare, "trip " .. trip.id .. " seat of " .. r.name) then
                finish(trip, "booker_broke")
                return false
            end
            trip.paid[trip.booker] = (trip.paid[trip.booker] or 0) + r.fare
            tellName(trip.booker, "note", { key = "IGUI_COTW_PaidFor", a = r.name, b = COTW.money(r.fare) })
        end
    end
    trip.state = "ready"
    DB().open[tostring(trip.id)] = { paid = trip.paid }
    if trip.gid then
        tellName(trip.booker, "ready", { id = trip.id, gid = trip.gid })
        local g = groups[trip.gid]
        if g and g.started then startTrip(trip) end
    else
        startTrip(trip)
    end
    return true
end

local C = {}

function C.hello(p)
    local u = user(nameOf(p))
    tell(p, "state", { home = u.home, pins = u.pins, hist = u.hist, profiles = DB().profiles, roads = DB().roads })
end

function C.setHome(p, args)
    if not coord(args.x) or not coord(args.y) then return end
    user(nameOf(p)).home = { x = math.floor(args.x), y = math.floor(args.y) }
    C.hello(p)
end

function C.setPin(p, args)
    local i = tonumber(args.i)
    if not i or i ~= math.floor(i) or i < 1 or i > COTW.PINS or not coord(args.x) or not coord(args.y) then return end
    local n = tostring(args.n or ("Pin " .. i))
    if #n > 24 then n = string.sub(n, 1, 24) end
    user(nameOf(p)).pins[i] = { n = n, x = math.floor(args.x), y = math.floor(args.y) }
    C.hello(p)
end

function C.delPin(p, args)
    local i = tonumber(args.i)
    if not i or i ~= math.floor(i) or i < 1 or i > COTW.PINS then return end
    user(nameOf(p)).pins[i] = nil
    C.hello(p)
end

-- route searches cost server time: one quote/book per player per second
local lastAsk = {}
local function tooSoon(p)
    local n = nameOf(p) or "?"
    local t = nowMs()
    if lastAsk[n] and t - lastAsk[n] < ASK_MS then return true end
    lastAsk[n] = t
    return false
end

function C.quote(p, args)
    if not coord(args.x) or not coord(args.y) or tooSoon(p) then return end
    local pl, why = plan(p, args.x, args.y, args.baby)
    if not pl then tell(p, "quote", { err = why }); return end
    local q = quoteArgs(pl)
    q.route = routeArgs(pl.route)
    tell(p, "quote", q)
end

local function busy(name)
    for _, t in pairs(trips) do
        if t.booker == name then return t end
    end
    return nil
end

-- args: x, y, baby (name), bill = { name = true } riders the booker sends a bill to, group (true = new), gid (join)
function C.book(p, args)
    if not coord(args.x) or not coord(args.y) or tooSoon(p) then return end
    local name = nameOf(p)
    if busy(name) then tell(p, "quote", { err = "busy" }); return end
    local pl, why = plan(p, args.x, args.y, args.baby)
    if not pl then tell(p, "quote", { err = why }); return end
    local bill = type(args.bill) == "table" and args.bill or {}

    local mine = pl.base + pl.trailerFee
    for _, r in ipairs(pl.riders) do
        r.bill = bill[r.name] == true and r.fare > 0
        if not r.bill then mine = mine + r.fare end
    end
    if not charge(name, mine, "trip " .. DB().nextId .. " hold") then tell(p, "quote", { err = "broke" }); return end

    local id = DB().nextId
    DB().nextId = id + 1
    local trip = {
        id = id, booker = name, vid = pl.vid, route = pl.route, riders = pl.riders,
        paid = { [name] = mine }, driven = 0, state = "billing", t0 = nowMs(), free = wallet() == nil,
    }
    trips[id] = trip
    DB().open[tostring(id)] = { paid = trip.paid }

    -- group trip: a new group, or join one heading to the same place
    if args.gid and groups[args.gid] then
        local g = groups[args.gid]
        trip.gid = args.gid
        g.members[#g.members + 1] = id
        trip.order = #g.members
        tellName(g.leader, "groupMember", { gid = args.gid, name = name, n = #g.members })
    elseif args.group then
        local gid = "g" .. id
        groups[gid] = { leader = name, members = { id }, started = false, destX = args.x, destY = args.y }
        trip.gid, trip.order = gid, 1
        -- every other driver close by gets an invite
        local v = pl.vehicle
        forOnline(function(q)
            local qn = nameOf(q)
            local qv = q:getVehicle()
            if qn ~= name and qv and qv ~= v and qv:getDriver() == q and COTW.dist(qv:getX(), qv:getY(), v:getX(), v:getY()) < 60 then
                tell(q, "groupInvite", { gid = gid, leader = name, x = args.x, y = args.y })
            end
        end)
    end

    for _, r in ipairs(pl.riders) do
        if r.bill then tellName(r.name, "bill", { id = id, booker = name, amount = r.fare, secs = COTW.opt("BillSeconds") }) end
    end
    tell(p, "booked", { id = id, held = mine, gid = trip.gid })
    local pending = false
    for _, r in ipairs(pl.riders) do if r.bill then pending = true end end
    if not pending then billsSettled(trip) end
end

function C.payBill(p, args)
    local trip = trips[tonumber(args.id) or -1]
    local name = nameOf(p)
    if not trip or trip.state ~= "billing" or trip.paid[name] then return end
    for _, r in ipairs(trip.riders) do
        if r.name == name and r.bill then
            if not charge(name, r.fare, "trip " .. trip.id .. " seat") then tell(p, "note", { key = "IGUI_COTW_Err_broke" }); return end
            trip.paid[name] = r.fare
            tellName(trip.booker, "note", { key = "IGUI_COTW_FriendPaid", a = name, b = COTW.money(r.fare) })
            local all = true
            for _, x in ipairs(trip.riders) do if x.bill and not trip.paid[x.name] then all = false end end
            if all then billsSettled(trip) end
            return
        end
    end
end

-- booker cancels before the car moves: everything back
function C.cancel(p)
    local trip = busy(nameOf(p))
    if trip and trip.state ~= "driving" then finish(trip, "cancel") end
end

function C.groupStart(p, args)
    local g = groups[args.gid or ""]
    if not g or g.leader ~= nameOf(p) or g.started then return end
    g.started = true
    for _, id in ipairs(g.members) do
        local t = trips[id]
        if t and t.state == "ready" then startTrip(t) end
    end
end

-- progress from the driving client: remaining road tiles + speed, every 0.5 s
function C.prog(p, args)
    local trip = busy(nameOf(p))
    if not trip or trip.state ~= "driving" then return end
    trip.lastProg = nowMs()
    trip.rem = tonumber(args.rem)
    if trip.gid and groups[trip.gid] then
        local g = groups[trip.gid]
        for i, id in ipairs(g.members) do
            if id == trip.id and g.members[i + 1] then
                local nxt = trips[g.members[i + 1]]
                if nxt then tellName(nxt.booker, "lead", { rem = trip.rem, spd = tonumber(args.spd) or 0 }) end
            end
        end
    end
end

-- the driving client says the trip is over; the server checks what it can
function C.finish(p, args)
    local trip = busy(nameOf(p))
    if not trip or trip.state ~= "driving" then return end
    local reason = tostring(args.reason or "blocked")
    if reason ~= "arrive" and reason ~= "intervene" and reason ~= "emergency" and reason ~= "blocked" and reason ~= "stuck" and reason ~= "offroute" and reason ~= "left" then
        reason = "blocked"
    end
    if reason == "arrive" then
        local v = getVehicleById(trip.vid)
        local r = trip.route
        if not v or COTW.dist(v:getX(), v:getY(), r.x[#r.x], r.y[#r.y]) > ARRIVE_SLACK then reason = "blocked" end
    end
    finish(trip, reason)
end

-- ------------------------------------------------------------------------------
-- admin
-- ------------------------------------------------------------------------------
local function broadcastWorld()
    forOnline(function(q) tell(q, "world", { profiles = DB().profiles, roads = DB().roads }) end)
end

function C.saveProfile(p, args)
    if not isAdmin(p) or type(args.key) ~= "string" or type(args.data) ~= "table" then return end
    local d = args.data
    DB().profiles[args.key] = {
        w = tonumber(d.w) or 2, l = tonumber(d.l) or 4, mass = tonumber(d.mass) or 1000,
        decel = tonumber(d.decel) or 6, trailer = d.trailer == true, by = nameOf(p),
    }
    COTW.log("profile " .. args.key .. " saved by " .. tostring(nameOf(p)))
    broadcastWorld()
end

function C.delProfile(p, args)
    if not isAdmin(p) or type(args.key) ~= "string" then return end
    DB().profiles[args.key] = nil
    broadcastWorld()
end

function C.saveRoad(p, args)
    if not isAdmin(p) or type(args.p) ~= "table" or #args.p < 4 then return end
    local pts = {}
    for i = 1, #args.p do pts[i] = math.floor((tonumber(args.p[i]) or 0) * 2 + 0.5) / 2 end
    table.insert(DB().roads, { w = tonumber(args.w) or 8, p = pts, by = nameOf(p) })
    COTW.Graph.setExtra(DB().roads)
    COTW.log("admin road " .. #DB().roads .. " (" .. (#pts / 2) .. " points) saved by " .. tostring(nameOf(p)))
    broadcastWorld()
end

-- delete the admin road with a point closest to (x, y), within 30 tiles
function C.delRoad(p, args)
    if not isAdmin(p) or type(args.x) ~= "number" then return end
    local best, bi = 30, nil
    for i, r in ipairs(DB().roads) do
        for k = 1, #r.p, 2 do
            local d = COTW.dist(args.x, args.y, r.p[k], r.p[k + 1])
            if d < best then best, bi = d, i end
        end
    end
    if bi then
        table.remove(DB().roads, bi)
        COTW.Graph.setExtra(DB().roads)
        broadcastWorld()
    end
end

-- ------------------------------------------------------------------------------
-- tick
-- ------------------------------------------------------------------------------
local function boot()
    booted = true
    DB()
    COTW.Graph.setExtra(DB().roads)
    -- trips cut off by a restart: nothing was driven that we can prove, refund in full
    for id, rec in pairs(DB().open) do
        for name, paid in pairs(rec.paid or {}) do refund(name, paid, "refund trip " .. id .. " (restart)") end
        DB().open[id] = nil
    end
    local n, e, x = COTW.Graph.stats()
    COTW.log("server ready, junctions=" .. n .. " roads=" .. e .. " admin roads=" .. x .. " wallet=" .. tostring(wallet() ~= nil))
end

local function sample(trip, t)
    if trip.state == "billing" then
        if t - trip.t0 > COTW.opt("BillSeconds") * 1000 then billsSettled(trip) end
        return
    end
    if trip.state == "ready" then
        -- a group that never started, or its booker left: everything back
        if t - trip.t0 > READY_MS or not findOnline(trip.booker) then finish(trip, "cancel") end
        return
    end
    if trip.state ~= "driving" then return end
    local driver = findOnline(trip.booker)
    if not driver then finish(trip, "disconnect"); return end
    local v = getVehicleById(trip.vid)
    if not v or v:getDriver() ~= driver then finish(trip, "left"); return end
    local x, y = v:getX(), v:getY()
    if trip.lx then
        local step = COTW.dist(trip.lx, trip.ly, x, y)
        if step > STEP_CAP then step = STEP_CAP end
        trip.driven = trip.driven + step
    end
    trip.lx, trip.ly = x, y
    if t - trip.lastProg > STALL_MS then finish(trip, "stuck") end
end

local function onClientCommand(module, command, player, args)
    if module ~= COTW.MOD or not player then return end
    if not booted then boot() end
    local fn = C[command]
    if not fn then return end
    local ok, err = pcall(fn, player, args or {})
    if not ok then COTW.log("command " .. tostring(command) .. " error: " .. tostring(err)) end
end

local function onTick()
    local t = nowMs()
    if not booted then boot() end
    if t - lastTick < TICK_MS then return end
    lastTick = t
    for _, trip in pairs(trips) do
        local ok, err = pcall(sample, trip, t)
        if not ok then COTW.log("trip " .. tostring(trip.id) .. " error: " .. tostring(err)) end
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)
