-- Cookie Mission - client state, networking, warps
if isServer() and not isClient() then return end

require "CM_Shared"

CMC = CMC or {}
local MOD = CM.MOD
CMC.listeners = CMC.listeners or {}
CMC.toasts = CMC.toasts or {}

local function ms()
    if getTimestampMs then return getTimestampMs() end
    return CM.now() * 1000
end
CMC.ms = ms

function CMC.player() return getSpecificPlayer(0) end

function CMC.send(cmd, args)
    local p = CMC.player()
    if not p then return end
    sendClientCommand(p, MOD, cmd, args or {})
end

function CMC.on(fn) CMC.listeners[#CMC.listeners + 1] = fn end

function CMC.emit(what)
    for i = 1, #CMC.listeners do
        local ok, err = pcall(CMC.listeners[i], what)
        if not ok then CM.log("listener error: " .. tostring(err)) end
    end
end

function CMC.txt(key, a, b, c, d)
    if a == nil then return getText(key) end
    if b == nil then return getText(key, tostring(a)) end
    if c == nil then return getText(key, tostring(a), tostring(b)) end
    if d == nil then return getText(key, tostring(a), tostring(b), tostring(c)) end
    return getText(key, tostring(a), tostring(b), tostring(c), tostring(d))
end
local T = CMC.txt

-- the server decides who is staff; the client only mirrors its answer
function CMC.isAdmin()
    if CM.isSP() then return true end
    return CMC.adminOk == true
end

-- seconds since a snapshot arrived
function CMC.age(at)
    if not at then return 0 end
    return math.max(0, (ms() - at) / 1000)
end

-- a relative countdown from a snapshot, ticking down locally
function CMC.left(v, at)
    if v == nil then return nil end
    return math.max(0, v - CMC.age(at))
end

function CMC.run()
    return CMC.me and CMC.me.run or nil
end

function CMC.claimed(cardId)
    local me = CMC.me
    if not me or not me.claims then return false end
    for i = 1, #me.claims do if me.claims[i] == cardId then return true end end
    return false
end

local nameCache = {}
function CMC.itemName(ft)
    if not ft or ft == "" then return "?" end
    local c = nameCache[ft]
    if c then return c end
    local name = ft
    pcall(function()
        local it = getScriptManager():FindItem(ft)
        if it then name = it:getDisplayName() or ft end
    end)
    nameCache[ft] = name
    return name
end

-- names of things (translated, with an English fallback)
function CMC.typeName(t) return T("IGUI_CM_Type_" .. tostring(t)) end
function CMC.tierName(t) return T("IGUI_CM_Tier" .. tostring(t)) end
function CMC.kindName(k) return T("IGUI_CM_Kind_" .. tostring(k or "house")) end

function CMC.placeText(c)
    if not c or not c.town then return T("IGUI_CM_NoPlace") end
    return CMC.kindName(c.kind) .. " - " .. tostring(c.town)
end

function CMC.goalText(typ, goal)
    if typ == "survive" then return T("IGUI_CM_Goal_survive", math.floor((goal or 0) / 60)) end
    return T("IGUI_CM_Goal_" .. tostring(typ), goal or 0)
end

-- ===================================================================== toasts
function CMC.toast(text, color, sec)
    table.insert(CMC.toasts, 1, { s = tostring(text), c = color, at = ms(), ttl = (sec or 6) * 1000 })
    while #CMC.toasts > 5 do table.remove(CMC.toasts) end
end

local TOAST_COLOR = { farwarn = "bad", left = "bad", busy = "bad", vehicle = "bad", full = "bad", almost = "bad",
    nocard = "bad", rejoin = "bad", nobuilding = "bad", noitem = "bad", found = "good", joined = "good",
    pinned = "good", banned = "bad", cool = "dim", tdone = "good", tfail = "bad", tgone = "dim", tfar = "bad",
    tbusy = "bad", tlost = "bad", tnoreach = "bad", swept = "good", sweepbusy = "bad",
    mhit = "good", mfake = "bad", mgone = "dim",
    sqbusy = "bad", sqsize = "bad", sqmade = "good", sqin = "good", sqjoin = "good", sqleft = "bad", sqlead = "good",
    sqgone = "bad", sqexpire = "bad", sqdisband = "bad", sqkicked = "bad", sqtaken = "bad", sqsent = "good", sqno = "bad",
    sqcount = "good", sqhold = "bad", sqfix = "bad",
    off = "bad", nolife = "bad", dead = "bad", dodjoin = "good", dodleft = "bad", doddead = "bad", dodcool = "bad",
    dodbusy = "bad", dodfew = "bad", dodnopoint = "bad", dodnotready = "bad", dodnowarn = "bad", dodgone = "bad",
    dodvote = "good", dodexpire = "bad", dodsaved = "good",
    dodnoloc = "bad", dodlocbusy = "bad", dodwait = "bad", doddown = "bad", dodyoudown = "bad", dodinbound = "bad",
    dodc1 = "good", dodsafe = "good", dodsp = "good" }

-- ===================================================================== warps
-- wp = { x, y, z, why, stage = "wait"|"go"|"settle", t0, tries }
CMC.warp = nil

local function squareGood(sq, preferRoom)
    if not sq then return false end
    local okS, solid = pcall(function() return sq:isSolid() or sq:isSolidTrans() end)
    if okS and solid then return false end
    local okF, floor = pcall(function() return sq:getFloor() end)
    if okF and floor == nil then return false end
    local free = CM.call(sq, "isFree", false)
    if free == false then return false end
    if preferRoom and CM.call(sq, "getRoom") == nil then return false end
    return true
end
CMC.squareGood = squareGood

local function doTeleport(p, x, y, z)
    p:setX(x); p:setY(y); p:setZ(z)
    p:setLastX(x); p:setLastY(y); p:setLastZ(z)
end
CMC.doTeleport = doTeleport

-- the square we warped onto is a wall / furniture / void: step to the nearest usable one
local function settle(wp, p)
    local c = getCell()
    if not c then return false end
    local sq = c:getGridSquare(wp.x, wp.y, wp.z)
    if not sq then return false end
    if squareGood(sq, false) then return true end
    for r = 1, 12 do
        for pass = 1, 2 do
            for dx = -r, r do
                for dy = -r, r do
                    if math.abs(dx) == r or math.abs(dy) == r then
                        local s2 = c:getGridSquare(wp.x + dx, wp.y + dy, wp.z)
                        if squareGood(s2, pass == 1 and wp.why == "go") then
                            doTeleport(p, wp.x + dx + 0.5, wp.y + dy + 0.5, wp.z)
                            return true
                        end
                    end
                end
            end
        end
    end
    return true
end

function CMC.startWarp(args)
    local x, y, z = math.floor(CM.num(args.x, 0)), math.floor(CM.num(args.y, 0)), math.floor(CM.num(args.z, 0))
    -- the server sends a warp again until it sees it land: one already on the way to that spot is enough
    local wp = CMC.warp
    if wp and wp.x == x and wp.y == y and wp.z == z then return end
    CMC.warp = { x = x, y = y, z = z, why = args.why or "go", stage = "wait", t0 = ms(), toldVeh = false }
    CMC.emit("warp")
end

-- ===================================================================== warp shield
-- A few seconds where zombies leave you alone after a mission warp, counting down at once (no need to move).
-- Same calls as the Safe User Login mod this server already runs: setZombiesDontAttack on our own player,
-- and zombies close by stand still (setUseless) until it ends.
CMC.shield = nil       -- { till = ms, sec, shown, zs = { zombie = true } }

local function halo(text, good)
    local p = CMC.player()
    if not p or not HaloTextHelper then return end
    local ok = pcall(function()
        if good then HaloTextHelper.addGoodText(p, text) else HaloTextHelper.addBadText(p, text) end
    end)
    if not ok then
        pcall(function()
            HaloTextHelper.addText(p, text, good and HaloTextHelper.getColorGreen() or HaloTextHelper.getColorRed())
        end)
    end
end

local shieldZombie
local function endShield(quiet)
    local sh = CMC.shield
    CMC.shield = nil
    if not sh then return end
    pcall(function() Events.OnZombieUpdate.Remove(shieldZombie) end)
    local p = CMC.player()
    if p then pcall(function() p:setZombiesDontAttack(false) end) end
    for z in pairs(sh.zs) do pcall(function() z:setUseless(false) end) end
    if not quiet then halo(T("IGUI_CM_Shield_off"), false) end
    CMC.emit("shield")
end
CMC.endShield = endShield

-- zombies within 8 tiles freeze while the shield is up (remembered so they wake up again)
shieldZombie = function(z)
    local sh = CMC.shield
    if not sh or sh.zs[z] then return end
    local p = CMC.player()
    if not p then return end
    local ok, near = pcall(function()
        local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
        return dx * dx + dy * dy < 64
    end)
    if ok and near then
        pcall(function() z:setUseless(true) end)
        sh.zs[z] = true
    end
end

function CMC.startShield(sec)
    sec = math.floor(CM.num(sec, 0))
    if sec <= 0 then return end
    local p = CMC.player()
    if not p then return end
    if CMC.shield then endShield(true) end
    CMC.shield = { till = ms() + sec * 1000, sec = sec, shown = sec + 1, zs = {} }
    pcall(function() p:setZombiesDontAttack(true) end)
    pcall(function() Events.OnZombieUpdate.Add(shieldZombie) end)
    halo(T("IGUI_CM_Shield_on", sec), true)
    CMC.emit("shield")
end

-- seconds left (0 = off)
function CMC.shieldLeft()
    local sh = CMC.shield
    if not sh then return 0 end
    return math.max(0, math.ceil((sh.till - ms()) / 1000))
end

local function shieldTick()
    local sh = CMC.shield
    if not sh then return end
    local p = CMC.player()
    local okD, dead = pcall(function() return p:isDead() end)
    if not p or (okD and dead) then endShield(true); return end
    local left = CMC.shieldLeft()
    if left <= 0 then endShield(false); return end
    -- keep it on: another mod (login protection) may switch it off while ours still runs
    pcall(function() p:setZombiesDontAttack(true) end)
    if left < sh.shown then
        sh.shown = left
        if left < sh.sec and left <= 5 then halo(T("IGUI_CM_Shield_tick", left), true) end
    end
end

local function warpTick()
    local wp = CMC.warp
    if not wp then return end
    local p = CMC.player()
    if not p then return end
    local t = ms()
    if wp.stage == "wait" then
        local okV, veh = pcall(function() return p:getVehicle() end)
        if okV and veh then
            if not wp.toldVeh then wp.toldVeh = true; CMC.toast(T("IGUI_CM_T_vehicle_wait"), "bad", 8) end
            if t - wp.t0 > 180000 then CMC.warp = nil end
            return
        end
        wp.stage = "fade"
        local text = T((wp.why == "go" or wp.why == "dod") and "IGUI_CM_WarpGo" or "IGUI_CM_WarpHome")
        local function jump()
            local pl = CMC.player()
            if not pl then CMC.warp = nil; return end
            doTeleport(pl, wp.x + 0.5, wp.y + 0.5, wp.z)
            wp.stage = "settle"
            wp.ts = ms()
            -- mission warps (in and home) get the shield; the login return keeps the login protection mod's own
            if wp.why == "go" or wp.why == "home" then
                -- the screen is still black for a moment: add it so the player sees the full count
                CMC.startShield(CM.int(CM.sv("WarpShield"), 10, 0, 60) + (wp.why == "go" and 1 or 0))
                -- the server half (god mode on the server-side player) stops Silent Hill / Cry of Fear monsters
                CMC.send("shield", { why = wp.why })
            end
        end
        if CMFade and CMFade.run then CMFade.run(text, jump) else jump() end
    elseif wp.stage == "settle" then
        local done = false
        local ok, r = pcall(settle, wp, p)
        if ok and r then done = true end
        if done or t - (wp.ts or t) > 12000 then
            CMC.warp = nil
            if CMFade and CMFade.release then CMFade.release() end
            CMC.emit("warped")
        end
    end
end

-- ===================================================================== supply caches in my inventory
-- The client never deletes items itself: in B42 MP a client-side delete sends SyncItemDelete,
-- which the server answers with an AntiCheatPermission kick ("no capability"). The server removes
-- caches from inventories and the change reaches the client by itself.
local reported = {}
local function askDrop(item, rid, idx)
    local t = ms()
    local last = reported[item]
    if last and t - last < 8000 then return end
    reported[item] = t
    CMC.send("dropcache", { run = rid, i = idx or 0 })
end

local function cacheItems()
    local p = CMC.player()
    local inv = p and p:getInventory()
    if not inv then return {} end
    local list = CM.call(inv, "getAllTypeRecurse", CM.CACHE_TYPE)
    local out = {}
    if list then
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    end
    return out
end

local function cacheTick()
    local items = cacheItems()
    if #items == 0 then return end
    local run = CMC.run()
    local t = ms()
    for _, it in ipairs(items) do
        local md = CM.call(it, "getModData") or {}
        local rid, idx = md.cmRun, md.cmIdx
        if run and run.type == "find" and run.phase == "live" and (rid == nil or rid == run.id) then
            local last = reported[it]
            if not last or t - last > 8000 then
                reported[it] = t
                CMC.send("found", { run = rid, i = idx or 0 })
            end
        elseif rid ~= nil and (not run or rid ~= run.id or run.phase ~= "live") then
            -- a cache from a finished mission: it is worthless, the server takes it away
            askDrop(it, rid, idx)
        end
    end
end

-- the server already took the cache out of the inventory: only forget it here
local function removeCache(args)
    for _, it in ipairs(cacheItems()) do
        local md = CM.call(it, "getModData") or {}
        if (args.run == nil or md.cmRun == nil or md.cmRun == args.run) and (CM.num(args.i, 0) == 0 or md.cmIdx == args.i) then
            reported[it] = nil
            return
        end
    end
end

-- ===================================================================== server -> client
local function onServerCommand(module, command, args)
    if module ~= MOD then return end
    args = args or {}
    if command == "hi" then
        CMC.helloOk = true
    elseif command == "pub" then
        CMC.pub = args; CMC.pubAt = ms()
        CMC.emit("pub")
    elseif command == "me" then
        local hadRun = CMC.me and CMC.me.run
        CMC.me = args; CMC.meAt = ms()
        if args.run and not hadRun then CMC.result = nil end
        CMC.emit("me")
    elseif command == "adm" then
        CMC.adm = args; CMC.admAt = ms()
        CMC.emit("adm")
    elseif command == "isadm" then
        CMC.adminOk = args.v == true
        if not CMC.adminOk and CMAdmin and CMAdmin.close then CMAdmin.close() end
        CMC.emit("isadm")
    elseif command == "tp" then
        CMC.startWarp(args)
    elseif command == "result" then
        CMC.result = args; CMC.resultAt = ms()
        CMC.emit("result")
    elseif command == "toast" then
        local k = tostring(args.k or "")
        local a = args.a or {}
        CMC.toast(T("IGUI_CM_T_" .. k, a[1], a[2], a[3]), TOAST_COLOR[k] or "text", 7)
    elseif command == "pulse" then
        local p = CMC.player()
        if p and addSound then
            pcall(addSound, p, math.floor(CM.num(args.x, 0)), math.floor(CM.num(args.y, 0)), math.floor(CM.num(args.z, 0)),
                CM.int(args.r, 40, 10, 120), CM.int(args.r, 40, 10, 120))
        end
    elseif command == "rmcache" then
        removeCache(args)
    end
end
Events.OnServerCommand.Add(onServerCommand)
CMC.onServerCommand = onServerCommand

-- ===================================================================== kill fallback
local sentKill = {}
local function onZombieDead(z)
    local run = CMC.run()
    if not run or run.phase ~= "live" or not run.zone then return end
    local p = CMC.player()
    if not p then return end
    local ok, x, y = pcall(function() return z:getX(), z:getY() end)
    if not ok or not CM.inRect(run.zone, x, y, 20) then return end
    local okA, a = pcall(function() return z:getAttackedBy() end)
    if not okA or a ~= p then return end
    local okI, id = pcall(function() return z:getOnlineID() end)
    if not okI or id == nil or id < 0 or sentKill[id] then return end
    sentKill[id] = true
    CMC.send("kill", { id = id, x = math.floor(x), y = math.floor(y) })
end
Events.OnZombieDead.Add(function(z) pcall(onZombieDead, z) end)

if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(function(p)
    if p == CMC.player() and CMC.run() then CMC.send("dead", {}) end
end) end

-- ===================================================================== ticking / hello
local helloAt, helloTries, lastSlow = 0, 0, 0
local function onTick()
    local t = ms()
    pcall(warpTick)
    pcall(shieldTick)
    -- hello until the server answered this player (a broadcast "pub" is not an answer)
    if not CMC.helloOk and helloAt > 0 and t >= helloAt and helloTries < 10 and CMC.player() then
        helloTries = helloTries + 1
        helloAt = t + 5000
        CMC.send("hello", {})
    end
    if t - lastSlow >= 2000 then
        lastSlow = t
        local ok, err = pcall(cacheTick)
        if not ok then CM.log("cache tick error: " .. tostring(err)) end
        if #CMC.toasts > 0 then
            for i = #CMC.toasts, 1, -1 do
                if t - CMC.toasts[i].at > CMC.toasts[i].ttl then table.remove(CMC.toasts, i) end
            end
        end
        if CM.count(sentKill) > 2000 then sentKill = {} end
    end
end
Events.OnTick.Add(onTick)

Events.OnGameStart.Add(function()
    helloAt = ms() + 1500
    helloTries = 0
    CMC.helloOk = false
end)

return CMC
