-- Cookie Horde - server authority (dedicated server, host, or single player)
-- Spawn spots live in global ModData, so a restart carries on where it stopped. Every server tick a
-- spot earns perMin / 60 zombies a second and lets out at most CHD.PER_TICK of them, on a free
-- square inside its radius. A spot is removed once it has let out its count.
-- Zombie modData: chP = spot id, chD = drops, chR = resistance, chS = walk speed % (the game wipes
-- modData when it reuses a zombie object, so a reused zombie carries none of these).
if isClient() and not isServer() then return end

require "CookieHorde/CHD_Shared"

CHDS = CHDS or {}
local MOD = CHD.MOD
local S = nil            -- global ModData "CookieHorde": { v, seq, presets = { id -> preset }, points = { id -> point } }
local rate = {}          -- ukey .. cmd -> ms of the last request
local outfitM, outfitF = nil, nil
local unknownOutfit = {}
local lastMs = nil
local lastLog = {}       -- key -> ms of the last line for errors that repeat
local LOG_GAP_MS = 60000

-- point: { id, x, y, z, r, total, done, dead, perMin, acc, pre = preset copy, by, at, wait }

-- marked zombies (sluggish and / or resistant): the client that owns a zombie moves it and works out
-- its health, so every client gets them by online id. Ids are known a moment after the spawn.
local markRef = {}       -- online id -> { z = zombie, f = walk factor or 0, r = resistance or nil }
local markWait = {}      -- { z, f, r, at } waiting for an online id
local markAdd, markDel = {}, {}   -- changes not sent yet: add = CHD.MARK_N numbers a zombie, del = { id ... }
local lastMarkStep = 0
local markKeys, markAt = nil, 1
local MARK_STEP_MS = 1000
local MARK_CHECKS = 200  -- known marked zombies looked at per step

local hits = CHD.newHits()   -- resistance boosts and avoid flags, undone next tick

local function nowMs()
    if getTimestampMs then
        local ok, v = pcall(getTimestampMs)
        if ok and v then return v end
    end
    return CM.now() * 1000
end

local function logEvery(key, msg)
    local t = nowMs()
    if not lastLog[key] or t - lastLog[key] >= LOG_GAP_MS then
        lastLog[key] = t
        CHD.log(msg)
    end
end

local function defaults(s)
    s.v = s.v or 1
    s.seq = CM.num(s.seq, 0)
    if type(s.presets) ~= "table" then s.presets = {} end
    if type(s.points) ~= "table" then s.points = {} end
end

function CHDS.state() return S end

local function nameOf(p)
    local ok, n = pcall(function() return p:getUsername() end)
    if ok and n and n ~= "" then return tostring(n) end
    return nil
end

local STAFF_LEVELS = { admin = true, moderator = true, overseer = true, gm = true }
function CHDS.isAdmin(p)
    if CM.isSP() then return true end
    if not p then return false end
    local okR, role = pcall(function() return p:getRole() end)
    if okR and role ~= nil then
        local ok, res = pcall(function() return role:hasAdminTool() end)
        if ok then return res == true end
    end
    local ok2, lvl = pcall(function() return p:getAccessLevel() end)
    if ok2 and lvl ~= nil then return STAFF_LEVELS[string.lower(tostring(lvl))] == true end
    return false
end

local function deliver(p, cmd, args)
    if isServer() then
        sendServerCommand(p, MOD, cmd, args)
    else
        triggerEvent("OnServerCommand", MOD, cmd, CM.copy(args))
    end
end
CHDS.send = deliver

local function deliverAll(cmd, args)
    if isServer() then
        sendServerCommand(MOD, cmd, args)
    else
        triggerEvent("OnServerCommand", MOD, cmd, CM.copy(args))
    end
end

local function onlinePlayers()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers()
        if list then
            for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
        end
    else
        local p = getSpecificPlayer(0)
        if p then out[1] = p end
    end
    return out
end

local function nextId(prefix)
    S.seq = CM.num(S.seq, 0) + 1
    return prefix .. tostring(S.seq)
end

local function sortedPoints()
    local ids = {}
    for id in pairs(S.points) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return CHD.seqOf(a) < CHD.seqOf(b) end)
    return ids
end

-- ===================================================================== outfits
-- the game's outfit names, per body: a male-only outfit on a female body comes out undressed
local function loadOutfits()
    if outfitM then return end
    outfitM, outfitF = {}, {}
    pcall(function()
        local m = getAllOutfits(false)
        for i = 0, m:size() - 1 do outfitM[tostring(m:get(i))] = true end
    end)
    pcall(function()
        local f = getAllOutfits(true)
        for i = 0, f:size() - 1 do outfitF[tostring(f:get(i))] = true end
    end)
end

-- female chance for an outfit name (nil name = random outfit, 50 / 50)
local function femaleChance(name)
    if not name then return 50 end
    loadOutfits()
    local m, f = outfitM[name] == true, outfitF[name] == true
    if m and f then return 50 end
    if f then return 100 end
    if m then return 0 end
    return nil       -- the game does not know it
end
CHDS.femaleChance = femaleChance

-- ===================================================================== spawning
local function freeSquare(pt)
    local cell = getCell()
    if not cell then return nil end
    local r = pt.r
    for _ = 1, 10 do
        local dx = ZombRand(r * 2 + 1) - r
        local dy = ZombRand(r * 2 + 1) - r
        if dx * dx + dy * dy <= r * r then
            local sq = cell:getGridSquare(pt.x + dx, pt.y + dy, pt.z)
            if sq then
                local okS, solid = pcall(function() return sq:isSolid() or sq:isSolidTrans() end)
                if okS and not solid then return pt.x + dx, pt.y + dy end
            end
        end
    end
    return nil
end

local function spawnOne(pt)
    local x, y = freeSquare(pt)
    if not x then return false, "area" end
    local pre = pt.pre or {}
    local outfit = CHD.pick(pre.outfits, ZombRand(10000) / 10000)
    local fem = femaleChance(outfit)
    if fem == nil then
        if outfit and not unknownOutfit[outfit] then
            unknownOutfit[outfit] = true
            CHD.log("unknown outfit '" .. tostring(outfit) .. "': a random outfit is used")
        end
        outfit, fem = nil, 50
    end
    local ok, list = pcall(addZombiesInOutfit, x, y, pt.z, 1, outfit, fem)
    if not ok or not list or list:size() == 0 then
        logEvery("spawn", "zombie spawn failed at " .. tostring(x) .. "," .. tostring(y) .. ": " .. tostring(list))
        return false, "fail"
    end
    local res = pre.res
    local resOn = CHD.hasRes(res)
    local slow = CHD.slowOf(pre.slow)
    local drops = (type(pre.drops) == "table" and #pre.drops > 0) and pre.drops or nil
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local code = CHD.SPEED_CODE[pre.speed or ""]
        if slow < 100 then code = CHD.SPEED_CODE.walk end   -- the slow walk nodes copy the shambler
        if code then pcall(function() z:doZombieSpeed(code) end) end
        local hp = CM.num(pre.hp, 1)
        if hp ~= 1 then pcall(function() z:setHealth(z:getHealth() * hp) end) end
        local tough = resOn and ZombRand(100) < CM.num(res.pct, 0)
        pcall(function()
            local md = z:getModData()
            md.chP = pt.id
            md.chD = drops
            md.chR = tough and res or nil
            md.chS = slow < 100 and slow or nil
        end)
        if CM.isSP() then
            if slow < 100 then pcall(CHD.setSlow, z, slow / 100, ZombRand(3)) end
        elseif slow < 100 or tough then
            markWait[#markWait + 1] = { z = z, f = slow < 100 and slow / 100 or 0, r = tough and res or nil, at = nowMs() }
        end
    end
    return true
end
CHDS.spawnOne = spawnOne

-- ===================================================================== marked zombies
local function pushMark(list, id, m)
    local r = m.r or {}
    list[#list + 1] = id
    list[#list + 1] = m.f
    list[#list + 1] = CM.num(r.boom, 0)
    list[#list + 1] = CM.num(r.melee, 0)
    list[#list + 1] = CM.num(r.gun, 0)
end

local function markForget(id)
    local m = markRef[id]
    if not m then return end
    markRef[id] = nil
    markDel[#markDel + 1] = id
    if m.f > 0 then pcall(CHD.clearSlow, m.z) end   -- the server copy (the object may be reused)
end

local function markStep(t)
    if t - lastMarkStep < MARK_STEP_MS then return end
    lastMarkStep = t
    -- online ids of new zombies (given up after 30 s: died or went away before it had one); ids are
    -- shorts that wrap below zero, only -1 means "none yet"
    local keep = {}
    for _, w in ipairs(markWait) do
        local ok, id = pcall(function() return w.z:getOnlineID() end)
        local okD, dead = pcall(function() return w.z:isDead() end)
        if okD and dead then
            -- died before it was sent: nothing to send
        elseif ok and id and id ~= -1 then
            local m = { z = w.z, f = w.f, r = w.r }
            markRef[id] = m
            pushMark(markAdd, id, m)
            if m.f > 0 then pcall(CHD.setSlow, m.z, m.f, id) end   -- the server copy walks the same
        elseif t - w.at < 30000 then
            keep[#keep + 1] = w
        else
            logEvery("noid", "a marked zombie got no online id in 30 s: clients cannot slow or protect it")
        end
    end
    markWait = keep
    -- dead, gone or reused: a slice of the known ones each step
    if not markKeys or markAt > #markKeys then
        markKeys = {}
        for id in pairs(markRef) do markKeys[#markKeys + 1] = id end
        markAt = 1
    end
    local stop = math.min(#markKeys, markAt + MARK_CHECKS - 1)
    for i = markAt, stop do
        local id = markKeys[i]
        local m = markRef[id]
        if m then
            local ok, alive = pcall(function()
                local md = m.z:getModData()
                return not m.z:isDead() and m.z:getCurrentSquare() ~= nil and m.z:getOnlineID() == id
                    and (md.chS ~= nil or md.chR ~= nil)
            end)
            if not ok or not alive then markForget(id) end
        end
    end
    markAt = stop + 1
    if #markAdd > 0 or #markDel > 0 then
        deliverAll("marks", { add = markAdd, del = markDel })
        markAdd, markDel = {}, {}
    end
end

local function markAll()
    local add = {}
    for id, m in pairs(markRef) do pushMark(add, id, m) end
    return { all = true, add = add, del = {} }
end

-- ===================================================================== resistance
-- a client owns the zombie: its health comes from that client
local function ownedByClient(z)
    local ok, o = pcall(function() return z:getOwner() end)
    return ok and o ~= nil
end

local function onHitZombie(zombie, attacker, part, weapon)
    if not zombie or not zombie:hasModData() then return end
    local res = zombie:getModData().chR
    if type(res) ~= "table" then return end
    local ok, err = CHD.resHit(hits, zombie, res, weapon, not CM.isSP() and ownedByClient(zombie))
    if not ok then logEvery("kind", "cannot read the weapon kind: " .. tostring(err)) end
end
CHDS.onHitZombie = onHitZombie

-- ===================================================================== state to the admins
local function pointRow(pt)
    return {
        id = pt.id, x = pt.x, y = pt.y, z = pt.z, r = pt.r,
        total = pt.total, done = pt.done, perMin = pt.perMin,
        name = pt.pre and pt.pre.name or "", by = pt.by, at = pt.at,
        alive = math.max(0, CM.num(pt.done, 0) - CM.num(pt.dead, 0)), wait = pt.wait,
    }
end

local function pointRows()
    local points = {}
    for _, id in ipairs(sortedPoints()) do points[#points + 1] = pointRow(S.points[id]) end
    return points
end

local function stateFor()
    local presets = {}
    for _, id in ipairs(CM.sortedKeys(S.presets)) do presets[#presets + 1] = S.presets[id] end
    table.sort(presets, function(a, b) return string.lower(tostring(a.name)) < string.lower(tostring(b.name)) end)
    return { presets = presets, points = pointRows(), build = CHD.BUILD }
end

local function sendState(p)
    deliver(p, "state", stateFor())
end

local function broadcast()
    for _, p in ipairs(onlinePlayers()) do
        if CHDS.isAdmin(p) then sendState(p) end
    end
end
CHDS.broadcast = broadcast

-- progress only (no presets), at most once a second while spots run
local lastProgress = 0
local PROGRESS_MS = 1000
local function progress(force)
    local t = nowMs()
    if not force and t - lastProgress < PROGRESS_MS then return false end
    lastProgress = t
    local points = pointRows()
    for _, p in ipairs(onlinePlayers()) do
        if CHDS.isAdmin(p) then deliver(p, "points", { points = points }) end
    end
    return true
end

local function toast(p, key, a, b)
    deliver(p, "toast", { key = key, a = a, b = b })
end

-- ===================================================================== tick
local function removePoint(id, why)
    local pt = S.points[id]
    if not pt then return end
    S.points[id] = nil
    CHD.log("spot " .. tostring(id) .. " " .. tostring(why) .. ": " .. tostring(pt.done) .. "/" .. tostring(pt.total)
        .. " at " .. tostring(pt.x) .. "," .. tostring(pt.y) .. "," .. tostring(pt.z))
end

local lastBeat = 0
local function tick()
    if not S then return end
    CHD.resTick(hits)
    local t = nowMs()
    if not lastMs then lastMs = t end
    local dt = t - lastMs
    lastMs = t
    if dt < 0 or dt > 5000 then dt = 0 end      -- clock jump / long pause: do not pile up
    local changed, finished = false, false
    for _, id in ipairs(sortedPoints()) do
        local pt = S.points[id]
        pt.acc = math.min(CM.num(pt.acc, 0) + pt.perMin * dt / 60000, CHD.PER_TICK)
        local n = 0
        local wait = nil
        while pt.acc >= 1 and pt.done < pt.total and n < CHD.PER_TICK do
            local ok, why = spawnOne(pt)
            if not ok then wait = why; break end
            pt.acc = pt.acc - 1
            pt.done = pt.done + 1
            n = n + 1
        end
        if wait ~= pt.wait then pt.wait = wait; changed = true end
        if n > 0 then changed = true end
        if pt.done >= pt.total then
            removePoint(id, "done")
            finished = true
        end
    end
    markStep(t)
    if t - lastBeat >= 2000 then
        lastBeat = t
        if CM.any(S.points) then changed = true end
    end
    if finished then progress(true) elseif changed then progress(false) end
end
CHDS.tick = tick

-- ===================================================================== deaths: count, drops
local function onZombieDead(z)
    if not z or not z:hasModData() then return end
    local md = z:getModData()
    local pid = md.chP
    if pid == nil then return end
    md.chP = nil
    local pt = S and S.points[pid]
    if pt then pt.dead = CM.num(pt.dead, 0) + 1 end
    if md.chS ~= nil or md.chR ~= nil then
        if CM.isSP() then
            if md.chS ~= nil then pcall(CHD.clearSlow, z) end
        else
            local ok, id = pcall(function() return z:getOnlineID() end)
            if ok and id then markForget(id) end
        end
    end
    md.chS = nil
    md.chR = nil
    local drops = md.chD
    md.chD = nil
    if type(drops) ~= "table" then return end
    local inv = z:getInventory()
    if not inv then return end
    local i = 1
    while drops[i] ~= nil do
        local d = drops[i]
        if ZombRand(100) < CM.num(d.pct, 0) then
            for _ = 1, CM.int(d.n, 1, 1, CHD.MAX_DROP_N) do
                local okI, item = pcall(instanceItem, d.ft)
                if okI and item then inv:AddItem(item) end
            end
        end
        i = i + 1
    end
end
CHDS.onZombieDead = onZombieDead

-- ===================================================================== lag estimate
-- counting walks every loaded zombie: keep the count of the last spot for a few seconds
local nearCache = { key = nil, at = 0, n = 0 }
local NEAR_CACHE_MS = 3000

local function countNear(x, y, z)
    local key = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
    local t = nowMs()
    if nearCache.key == key and t - nearCache.at < NEAR_CACHE_MS then return nearCache.n end
    local nr2 = CHD.NEAR_R * CHD.NEAR_R
    local near = 0
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local zz = list:get(i)
            local dx = zz:getX() - x
            if dx * dx <= nr2 then
                local dy = zz:getY() - y
                if dx * dx + dy * dy <= nr2 and math.abs(zz:getZ() - z) <= 1 and not zz:isDead() then near = near + 1 end
            end
        end
    end)
    nearCache = { key = key, at = t, n = near }
    return near
end

local function estimate(a)
    local x, y, z = CM.int(a.x, 0), CM.int(a.y, 0), CM.int(a.z, 0)
    local near = countNear(x, y, z)
    local pending, rateNear = 0, 0
    local far2 = (CHD.NEAR_R * 2) * (CHD.NEAR_R * 2)
    for _, pt in pairs(S.points) do
        local dx, dy = pt.x - x, pt.y - y
        if dx * dx + dy * dy <= far2 then
            pending = pending + math.max(0, pt.total - pt.done)
            rateNear = rateNear + pt.perMin
        end
    end
    local dist = nil
    for _, p in ipairs(onlinePlayers()) do
        local ok, d = pcall(function()
            local dx, dy = p:getX() - x, p:getY() - y
            return math.sqrt(dx * dx + dy * dy)
        end)
        if ok and d and d <= 300 and (dist == nil or d < dist) then dist = d end
    end
    local info = { near = near, total = CM.int(a.total, 0, 0, CHD.MAX_TOTAL), perMin = CM.int(a.perMin, 0, 0, CHD.MAX_PER_MIN),
        pending = pending, rateNear = rateNear, dist = dist }
    local level, expected, reasons, suggest = CHD.advise(info)
    return { level = level, expected = expected, reasons = reasons, suggest = suggest, near = near,
        dist = dist and math.floor(dist) or nil, x = x, y = y, z = z, total = info.total, perMin = info.perMin }
end
CHDS.estimate = estimate

-- ===================================================================== commands
local MIN_GAP = { estimate = 1000, hello = 5000 }

local function onClientCommand(module, command, p, args)
    if module ~= MOD then return end
    if not S or not p then return end
    args = args or {}
    local who = nameOf(p) or "?"
    local rk = CM.ukey(who) .. command
    local t = nowMs()
    if rate[rk] and t - rate[rk] < (MIN_GAP[command] or 150) then return end
    rate[rk] = t

    -- every player: the marked zombies their client has to slow down and protect
    if command == "hello" then
        deliver(p, "marks", markAll())
        return
    end
    if not CHDS.isAdmin(p) then return end

    if command == "state" then
        sendState(p)
    elseif command == "estimate" then
        deliver(p, "estimate", estimate(args))
    elseif command == "savePreset" then
        local pre = CHD.cleanPreset(args.preset)
        if not pre then return end
        if pre.id == "" or not S.presets[pre.id] then
            if CM.count(S.presets) >= CHD.MAX_PRESETS then toast(p, "presetFull", CHD.MAX_PRESETS); return end
            pre.id = nextId("p")
        end
        S.presets[pre.id] = pre
        CHD.log("preset " .. pre.id .. " saved by " .. who .. ": " .. pre.name .. " speed=" .. pre.speed
            .. " slow=" .. tostring(pre.slow) .. " hp=" .. tostring(pre.hp) .. " res=" .. tostring(pre.res.pct) .. "%/"
            .. tostring(pre.res.boom) .. "/" .. tostring(pre.res.melee) .. "/" .. tostring(pre.res.gun)
            .. " outfits=" .. tostring(#pre.outfits) .. " drops=" .. tostring(#pre.drops))
        deliver(p, "saved", { id = pre.id })
        broadcast()
    elseif command == "delPreset" then
        local id = CM.str(args.id, 24)
        if S.presets[id] then
            S.presets[id] = nil
            CHD.log("preset " .. id .. " deleted by " .. who)
            broadcast()
        end
    elseif command == "start" then
        local pt = CHD.cleanPoint(args)
        if not pt then return end
        local pre = S.presets[pt.pid]
        if pt.pid ~= "" and not pre then toast(p, "noPreset"); return end
        if CM.count(S.points) >= CHD.MAX_POINTS then toast(p, "pointsFull", CHD.MAX_POINTS); return end
        pt.pre = pre and CHD.cleanPreset(pre) or CHD.cleanPreset({ name = "Random" })
        pt.id = nextId("s")
        pt.done = 0
        pt.dead = 0
        pt.acc = 0
        pt.by = who
        pt.at = CM.now()
        S.points[pt.id] = pt
        CHD.log("spot " .. pt.id .. " started by " .. who .. " at " .. tostring(pt.x) .. "," .. tostring(pt.y) .. ","
            .. tostring(pt.z) .. " count=" .. tostring(pt.total) .. " perMin=" .. tostring(pt.perMin) .. " r=" .. tostring(pt.r)
            .. " preset=" .. tostring(pt.pre.name))
        toast(p, "started", pt.total, pt.perMin)
        broadcast()
    elseif command == "cancel" then
        local id = CM.str(args.id, 24)
        if S.points[id] then
            removePoint(id, "cancelled by " .. who)
            toast(p, "cancelled", id)
            broadcast()
        end
    end
end
CHDS.onClientCommand = onClientCommand

local function init()
    S = ModData.getOrCreate(MOD)
    defaults(S)
    for _, pt in pairs(S.points) do
        pt.wait = nil
        pt.dead = CM.num(pt.dead, 0)
    end
    CHD.log("server ready " .. CHD.BUILD .. " presets=" .. tostring(CM.count(S.presets)) .. " spots=" .. tostring(CM.count(S.points)))
end

Events.OnInitGlobalModData.Add(function()
    local ok, err = pcall(init)
    if not ok then CHD.log("init error: " .. tostring(err)) end
end)
Events.OnClientCommand.Add(function(module, command, p, args)
    if module ~= MOD then return end
    local ok, err = pcall(onClientCommand, module, command, p, args)
    if not ok then logEvery("cmd" .. tostring(command), "command error " .. tostring(command) .. ": " .. tostring(err)) end
end)
Events.OnTick.Add(function()
    local ok, err = pcall(tick)
    if not ok then logEvery("tick", "tick error: " .. tostring(err)) end
end)
Events.OnZombieDead.Add(function(z)
    local ok, err = pcall(onZombieDead, z)
    if not ok then logEvery("dead", "zombie dead error: " .. tostring(err)) end
end)
if Events.OnHitZombie then
    Events.OnHitZombie.Add(function(zombie, attacker, part, weapon)
        local ok, err = pcall(onHitZombie, zombie, attacker, part, weapon)
        if not ok then logEvery("hit", "hit zombie error: " .. tostring(err)) end
    end)
else
    CHD.log("OnHitZombie not found: resistance is off")
end

return CHDS
