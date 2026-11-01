-- Cookie Helper : server side
-- Owns: offline member add, guest visits (temporary membership + timer), zones, shared vehicle-part cache.
-- Cost on the server: a few table lookups per command and one 2-second timer that only
-- walks the (tiny) guest list. Nothing here scans the world.
if isClient() and not isServer() then return end

require "CookieHelper/CH_Shared"

CHelp.S = CHelp.S or {}
local S = CHelp.S

local MODDATA = "CookieHelper"
local GUEST_FILE = "CookieHelper_guests.txt"
-- removing a name that is not in the list is a no-op, but kickUserFromSafehouse still
-- broadcasts SafehouseSync for that safehouse - that is how we push membership changes.
local SYNC_DUMMY = "~cookiehelper-sync~"
local ASK_TIMEOUT_MS = 60000
local MAX_KNOWN = 400
local MAX_VEH_MODELS = 600
local MAX_VEH_ITEMS = 160
local MAX_VEH_EXTRA = 40

local D = nil
local pending = {}       -- reqId -> { guest, sh, ts, title }
local lastReq = {}       -- username -> ms
local reqSeq = 0
local started = false
local startMs = 0
local lastTick = 0

-- ------------------------------------------------------------------ data
local function data()
    if not D then D = ModData.getOrCreate(MODDATA) end
    D.guests = D.guests or {}
    D.zones = D.zones or {}
    D.known = D.known or {}
    D.vparts = D.vparts or {}
    D.vextra = D.vextra or {}
    D.zseq = D.zseq or 0
    return D
end

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function uname(p)
    if not p then return nil end
    local ok, n = pcall(function() return p:getUsername() end)
    if ok then return n end
    return nil
end

local function playerByName(name)
    for _, p in ipairs(CHelp.onlinePlayers()) do
        if uname(p) == name then return p end
    end
    return nil
end

local function isAdmin(p)
    if CHelp.isSP() then return true end
    if not p then return false end
    local okR, role = pcall(function() return p:getRole() end)
    if okR and role ~= nil then
        local ok, res = pcall(function() return role:hasAdminTool() end)
        if ok and res == true then return true end
        local ok2, res2 = pcall(function() return role:hasCapability(Capability.CanSetupSafehouses) end)
        if ok2 and res2 == true then return true end
    end
    return false
end

local function msg(p, key, a, b)
    CHelp.toClient(p, "msg", { k = key, a = a, b = b })
end

local function guestOf(user, key)
    local g = data().guests[user]
    return g ~= nil and g.sh == key
end

-- the guest's host house; if it was moved/resized (key changed) fall back to the owner's house
local function guestHouse(g)
    local sh = CHelp.shByKey(g.sh)
    if sh then return sh end
    if g.owner then
        local ok, byOwner = pcall(function() return SafeHouse.getSafehouseByOwner(g.owner) end)
        if ok and byOwner then
            g.sh = CHelp.shKey(byOwner)
            return byOwner
        end
    end
    return nil
end

-- real member = owner or listed member that is not only visiting as a guest
local function isRealMember(sh, user)
    if not sh or not user then return false end
    if not sh:playerAllowed(user) then return false end
    return not guestOf(user, CHelp.shKey(sh))
end

local function syncSafehouse(sh)
    if not sh or not isServer() then return end
    local ok, err = pcall(function() SafeHouse.kickUserFromSafehouse(sh, SYNC_DUMMY) end)
    if not ok then CHelp.log("sync failed: " .. tostring(err)) end
end

local function membersOnline(sh, exceptName)
    local out = {}
    local key = CHelp.shKey(sh)
    for _, p in ipairs(CHelp.onlinePlayers()) do
        local n = uname(p)
        if n and n ~= exceptName and sh:playerAllowed(n) and not guestOf(n, key) then
            out[#out + 1] = p
        end
    end
    return out
end

-- ------------------------------------------------------------------ guest file (crash safety)
-- membership is saved with the world, the guest list is written here the moment it changes,
-- so a crash can never leave a visitor as a permanent member.
local function saveGuestFile()
    local ok, err = pcall(function()
        local w = getFileWriter(GUEST_FILE, true, false)
        if not w then return end
        for user, g in pairs(data().guests) do
            w:write(tostring(user) .. "|" .. tostring(g.sh) .. "|" .. tostring(math.floor(tonumber(g.exp) or 0))
                .. "|" .. tostring(g.owner or "") .. "\n")
        end
        w:close()
    end)
    if not ok then CHelp.log("guest file write failed: " .. tostring(err)) end
end

local function loadGuestFile()
    local ok, err = pcall(function()
        local r = getFileReader(GUEST_FILE, false)
        if not r then return end
        local line = r:readLine()
        while line do
            local user, key, exp, owner = string.match(line, "^(.-)|(.-)|([%d%.eE%+%-]+)|?(.*)$")
            exp = tonumber(exp)
            if user and key and exp and not data().guests[user] then
                data().guests[user] = { sh = key, role = CHelp.ROLE_DOCTOR, exp = exp, host = "?", title = "",
                    owner = (owner ~= "" and owner or nil) }
            end
            line = r:readLine()
        end
        r:close()
    end)
    if not ok then CHelp.log("guest file read failed: " .. tostring(err)) end
end

-- ------------------------------------------------------------------ broadcasts
local function guestPayload()
    local list = {}
    for user, g in pairs(data().guests) do
        list[user] = { sh = g.sh, role = g.role, exp = g.exp, title = g.title }
    end
    return { now = CHelp.now(), list = list }
end

local function broadcastGuests()
    CHelp.toAll("guests", guestPayload())
end

local function zonesPayload(key)
    local list = {}
    for _, z in ipairs(data().zones[key] or {}) do list[#list + 1] = z end
    return { sh = key, list = list }
end

local function sendZonesTo(p, key)
    CHelp.toClient(p, "zones", zonesPayload(key))
end

local function sendZonesToMembers(sh)
    local key = CHelp.shKey(sh)
    for _, p in ipairs(membersOnline(sh)) do sendZonesTo(p, key) end
end

-- ------------------------------------------------------------------ guests
local function endGuest(user, reason, by)
    local g = data().guests[user]
    if not g then return end
    data().guests[user] = nil
    local sh = guestHouse(g)
    if sh and sh:getOwner() ~= user and sh:getPlayers():contains(user) then
        if isServer() then
            local ok, err = pcall(function() SafeHouse.kickUserFromSafehouse(sh, user) end)
            if not ok then
                CHelp.log("kick failed, removing directly: " .. tostring(err))
                sh:removePlayer(user)
                syncSafehouse(sh)
            end
        else
            sh:removePlayer(user)
        end
    end
    saveGuestFile()
    broadcastGuests()
    local gp = playerByName(user)
    if gp then msg(gp, "GuestEnded_" .. tostring(reason or "expired"), by or "") end
    if sh then
        for _, p in ipairs(membersOnline(sh, user)) do msg(p, "HostGuestLeft", user) end
    end
    CHelp.log("guest ended: " .. tostring(user) .. " reason=" .. tostring(reason))
end

local function startupCleanup()
    loadGuestFile()
    local now = CHelp.now()
    local drop = {}
    for user, g in pairs(data().guests) do
        if (tonumber(g.exp) or 0) <= now then drop[#drop + 1] = user end
    end
    for _, user in ipairs(drop) do endGuest(user, "expired") end
    saveGuestFile()
    CHelp.log("ready v" .. CHelp.VERSION .. " (" .. tostring(#drop) .. " expired guests cleared)")
end

local function tick()
    local ms = CHelp.nowMs()
    if ms - lastTick < 2000 then return end
    lastTick = ms
    if not started then
        if startMs == 0 then startMs = ms end
        if ms - startMs < 5000 then return end   -- let the safehouse list finish loading
        started = true
        startupCleanup()
        return
    end
    local now = CHelp.now()
    local finished, gone = {}, {}
    for user, g in pairs(data().guests) do
        local sh = guestHouse(g)
        if not sh then
            gone[#gone + 1] = user
        elseif (tonumber(g.exp) or 0) <= now then
            finished[#finished + 1] = user
        elseif not sh:playerAllowed(user) then
            gone[#gone + 1] = user   -- removed / quit through the vanilla safehouse window
        end
    end
    for _, user in ipairs(finished) do endGuest(user, "expired") end
    if #gone > 0 then
        for _, user in ipairs(gone) do data().guests[user] = nil end
        saveGuestFile()
        broadcastGuests()
    end
    for id, r in pairs(pending) do
        if ms - r.ts > ASK_TIMEOUT_MS then
            pending[id] = nil
            local gp = playerByName(r.guest)
            if gp then msg(gp, "ReqTimeout") end
        end
    end
end

-- ------------------------------------------------------------------ command handlers
local H = {}

function H.hello(p, user, args)
    data().known[user] = CHelp.now()
    local n = 0
    for _ in pairs(data().known) do n = n + 1 end
    if n > MAX_KNOWN then
        local oldestU, oldestT = nil, 9007199254740991
        for u, t in pairs(data().known) do
            if t < oldestT then oldestU, oldestT = u, t end
        end
        if oldestU then data().known[oldestU] = nil end
    end
    CHelp.toClient(p, "guests", guestPayload())
    for _, sh in ipairs(CHelp.shListFor(user)) do
        if isRealMember(sh, user) then sendZonesTo(p, CHelp.shKey(sh)) end
    end
end

function H.knownReq(p, user, args)
    local names = {}
    for u, _ in pairs(data().known) do names[#names + 1] = u end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    CHelp.toClient(p, "known", { list = names })
end

function H.zonesReq(p, user, args)
    local sh = CHelp.shByKey(args.sh)
    if sh and (isRealMember(sh, user) or isAdmin(p)) then sendZonesTo(p, args.sh) end
end

function H.addMember(p, user, args)
    local sh = CHelp.shByKey(args.sh)
    local name = trim(args.name)
    if not sh then return msg(p, "NoSafehouse") end
    if not (CHelp.isOwner(sh, user) or isAdmin(p)) then return msg(p, "OwnerOnly") end
    if not CHelp.sv("AllowOfflineAdd") and not isAdmin(p) then return msg(p, "AddDisabled") end
    if name == "" or string.len(name) > 64 then return msg(p, "BadName") end
    if sh:getOwner() == name then return msg(p, "AlreadyMember", name) end
    local key = CHelp.shKey(sh)
    if guestOf(name, key) then
        -- a visitor becomes a real member: keep the membership, drop the timer
        data().guests[name] = nil
        saveGuestFile()
        broadcastGuests()
        msg(p, "AddedFromGuest", name)
        local tp = playerByName(name)
        if tp then msg(tp, "YouWereAdded", sh:getTitle()); sendZonesTo(tp, key) end
        return
    end
    if sh:getPlayers():contains(name) then return msg(p, "AlreadyMember", name) end
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local other = list:get(i)
        if other ~= sh and other:playerAllowed(name) and not guestOf(name, CHelp.shKey(other)) then
            return msg(p, "HasOtherSafehouse", name, other:getTitle())
        end
    end
    sh:addPlayer(name)
    syncSafehouse(sh)
    msg(p, "Added", name)
    local tp = playerByName(name)
    if tp then msg(tp, "YouWereAdded", sh:getTitle()); sendZonesTo(tp, key) end
    CHelp.log(tostring(user) .. " added " .. tostring(name) .. " to safehouse " .. key)
end

function H.guestRequest(p, user, args)
    local sh = CHelp.shByKey(args.sh)
    if not sh then return msg(p, "NoSafehouse") end
    local key = CHelp.shKey(sh)
    if sh:playerAllowed(user) then return msg(p, "AlreadyInside") end
    if data().guests[user] then return msg(p, "AlreadyGuest") end
    local range = CHelp.svInt("GuestRequestRange", 1, 60)
    local d = CHelp.shDist(sh, math.floor(p:getX()), math.floor(p:getY()))
    if d > range then return msg(p, "TooFar", range) end
    local ms = CHelp.nowMs()
    local cd = CHelp.svInt("GuestRequestCooldown", 0, 600) * 1000
    if lastReq[user] and ms - lastReq[user] < cd then
        return msg(p, "Cooldown", math.ceil((cd - (ms - lastReq[user])) / 1000))
    end
    for _, r in pairs(pending) do
        if r.guest == user then return msg(p, "ReqAlreadyWaiting") end
    end
    local hosts = membersOnline(sh, user)
    if #hosts == 0 then return msg(p, "NoHostOnline") end
    lastReq[user] = ms
    reqSeq = reqSeq + 1
    local id = tostring(reqSeq) .. "_" .. tostring(ms)
    pending[id] = { guest = user, sh = key, ts = ms, title = sh:getTitle() }
    for _, h in ipairs(hosts) do
        CHelp.toClient(h, "guestAsk", { id = id, guest = user, sh = key, title = sh:getTitle(),
            minutes = CHelp.svInt("GuestMinutes", 1, 240) })
    end
    msg(p, "ReqSent", #hosts)
end

function H.guestAnswer(p, user, args)
    local r = pending[args.id]
    if not r then return msg(p, "ReqGone") end
    local sh = CHelp.shByKey(r.sh)
    if not sh or not isRealMember(sh, user) then return end
    pending[args.id] = nil
    for _, h in ipairs(membersOnline(sh)) do CHelp.toClient(h, "guestAskClose", { id = args.id }) end
    local gp = playerByName(r.guest)
    local role = args.role
    if role ~= CHelp.ROLE_DOCTOR and role ~= CHelp.ROLE_BUILDER and role ~= CHelp.ROLE_KEEPER then
        if gp then msg(gp, "ReqDenied", user) end
        return
    end
    if sh:playerAllowed(r.guest) then return msg(p, "AlreadyMember", r.guest) end
    if data().guests[r.guest] then return msg(p, "GuestBusy", r.guest) end
    local minutes = CHelp.svInt("GuestMinutes", 1, 240)
    sh:addPlayer(r.guest)
    syncSafehouse(sh)
    data().guests[r.guest] = { sh = r.sh, role = role, exp = CHelp.now() + minutes * 60, host = user, title = sh:getTitle(),
        owner = sh:getOwner() }
    saveGuestFile()
    broadcastGuests()
    if gp then msg(gp, "Approved_" .. role, user, minutes) end
    for _, h in ipairs(membersOnline(sh, r.guest)) do msg(h, "HostApproved_" .. role, r.guest, user) end
    CHelp.log(tostring(user) .. " let " .. tostring(r.guest) .. " in as " .. role .. " for " .. minutes .. "m (" .. r.sh .. ")")
end

function H.guestEnd(p, user, args)
    local target = trim(args.user)
    if target == "" then target = user end
    local g = data().guests[target]
    if not g then return end
    local sh = CHelp.shByKey(g.sh)
    if target ~= user and not (isAdmin(p) or (sh and isRealMember(sh, user))) then return msg(p, "OwnerOnly") end
    endGuest(target, target == user and "left" or "kicked", user)
end

local function cleanName(s, fallback)
    s = trim(s)
    if s == "" then s = fallback end
    if string.len(s) > 28 then s = string.sub(s, 1, 28) end
    return s
end

function H.zoneAdd(p, user, args)
    local sh = CHelp.shByKey(args.sh)
    if not sh then return msg(p, "NoSafehouse") end
    if not (isRealMember(sh, user) or isAdmin(p)) then return msg(p, "MembersOnly") end
    local kind = args.kind == CHelp.ZONE_VEHICLE and CHelp.ZONE_VEHICLE or CHelp.ZONE_COUNT
    local r = {
        x1 = math.floor(tonumber(args.x1) or 0), y1 = math.floor(tonumber(args.y1) or 0),
        x2 = math.floor(tonumber(args.x2) or 0), y2 = math.floor(tonumber(args.y2) or 0),
    }
    if r.x2 <= r.x1 or r.y2 <= r.y1 then return msg(p, "ZoneBad") end
    local side = CHelp.svInt("MaxZoneSide", 2, 200)
    if r.x2 - r.x1 > side or r.y2 - r.y1 > side then return msg(p, "ZoneTooBig", side) end
    if not CHelp.rectInside(r, CHelp.shRect(sh)) then return msg(p, "ZoneOutside") end
    local key = CHelp.shKey(sh)
    local list = data().zones[key] or {}
    local limit = kind == CHelp.ZONE_VEHICLE and CHelp.svInt("VehicleZonesPerSafehouse", 0, 20)
        or CHelp.svInt("CountZonesPerSafehouse", 0, 20)
    local have = 0
    for _, z in ipairs(list) do if z.kind == kind then have = have + 1 end end
    if have >= limit then return msg(p, "ZoneLimit", limit) end
    data().zseq = data().zseq + 1
    local z = {
        id = data().zseq, kind = kind,
        name = cleanName(args.name, (kind == CHelp.ZONE_VEHICLE and "Garage " or "Stock ") .. tostring(have + 1)),
        x1 = r.x1, y1 = r.y1, x2 = r.x2, y2 = r.y2, z = math.floor(tonumber(args.z) or 0), by = user,
    }
    list[#list + 1] = z
    data().zones[key] = list
    sendZonesToMembers(sh)
    msg(p, "ZoneSaved", z.name)
end

function H.zoneDel(p, user, args)
    local sh = CHelp.shByKey(args.sh)
    if not sh or not (isRealMember(sh, user) or isAdmin(p)) then return msg(p, "MembersOnly") end
    local key = CHelp.shKey(sh)
    local list = data().zones[key] or {}
    for i = #list, 1, -1 do
        if list[i].id == tonumber(args.id) then table.remove(list, i) end
    end
    data().zones[key] = list
    sendZonesToMembers(sh)
end

function H.zoneRename(p, user, args)
    local sh = CHelp.shByKey(args.sh)
    if not sh or not (isRealMember(sh, user) or isAdmin(p)) then return msg(p, "MembersOnly") end
    for _, z in ipairs(data().zones[CHelp.shKey(sh)] or {}) do
        if z.id == tonumber(args.id) then z.name = cleanName(args.name, z.name) end
    end
    sendZonesToMembers(sh)
end

-- vehicle part lists are only known for models someone has actually parked in a zone;
-- the first client that sees one reports it so every safehouse can browse it later.
function H.vparts(p, user, args)
    local veh = trim(args.veh)
    if veh == "" or string.len(veh) > 120 or type(args.items) ~= "table" then return end
    local items, n = {}, 0
    for _, it in pairs(args.items) do
        if type(it) == "string" and string.len(it) <= 140 and n < MAX_VEH_ITEMS then
            n = n + 1
            items[n] = it
        end
    end
    if n == 0 then return end
    local cur = data().vparts[veh]
    if cur and #cur >= n then return end
    if not cur then
        local count = 0
        for _ in pairs(data().vparts) do count = count + 1 end
        if count >= MAX_VEH_MODELS then return end
    end
    data().vparts[veh] = items
end

function H.vehListReq(p, user, args)
    local names = {}
    for veh, _ in pairs(data().vparts) do names[#names + 1] = veh end
    table.sort(names)
    CHelp.toClient(p, "vehList", { list = names })
end

function H.vehDataReq(p, user, args)
    local veh = trim(args.veh)
    CHelp.toClient(p, "vehData", { veh = veh, items = data().vparts[veh], extra = data().vextra[veh] })
end

function H.vextra(p, user, args)
    local veh = trim(args.veh)
    local recipe = trim(args.recipe)
    if veh == "" or recipe == "" or string.len(veh) > 120 or string.len(recipe) > 120 then return end
    if #CHelp.shListFor(user) == 0 and not isAdmin(p) then return msg(p, "MembersOnly") end
    local list = data().vextra[veh] or {}
    local found = nil
    for i, r in ipairs(list) do if r == recipe then found = i end end
    if args.add then
        if not found and #list < MAX_VEH_EXTRA then list[#list + 1] = recipe end
    elseif found then
        table.remove(list, found)
    end
    data().vextra[veh] = list
    CHelp.toClient(p, "vehData", { veh = veh, items = data().vparts[veh], extra = list })
end

function S.onCommand(p, cmd, args)
    local f = H[cmd]
    if not f or not p then return end
    local user = uname(p)
    if not user then return end
    local ok, err = pcall(f, p, user, args or {})
    if not ok then CHelp.log("command " .. tostring(cmd) .. " failed: " .. tostring(err)) end
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= CHelp.NET then return end
    S.onCommand(player, command, args)
end)

Events.OnInitGlobalModData.Add(function() data() end)
Events.OnTick.Add(tick)
