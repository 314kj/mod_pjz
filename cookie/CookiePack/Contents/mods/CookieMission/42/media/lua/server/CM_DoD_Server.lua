-- Cookie Mission - Die or Die (server): one lobby at a time, vote a saved spot, warp the squad there locked and
-- immortal, clear the zombies, ready check, then Project A-Life soldiers come for them. Death is real.
-- Our own calls into A-Life's server API; if A-Life is missing or its API changed, Die or Die switches itself off.
if isClient() and not isServer() then return end

require "CM_Shared"
require "CM_DoD"
require "CM_Server"
if not CMS or not CMS.H then return end

CMDoD = CMDoD or {}
local H, A = CMS.H, CMS.A
local send, keyOf, nameOf = CMS.send, CMS.keyOf, CMS.nameOf
local D = CM.DOD
local L = nil              -- the one lobby / match, memory only
local watch = {}           -- ukey -> true while the Die or Die window is open
local ON = {}              -- ukey -> IsoPlayer (rebuilt every tick)
local seq = 0
local lastTick = 0
local recover = nil        -- { tries, at } crash recovery of a match that was live at boot

local function now() return CM.now() end
local function rand(n) if n <= 1 then return 0 end return ZombRand(n) end
local function log(s) CMS.logLine("[DoD] " .. tostring(s)) end

-- persistent part (global ModData "CookieMission"): saved spots, cooldowns, the live match for crash recovery
local function store()
    local S = CMS.state()
    if not S then return nil end
    S.dod = S.dod or {}
    local d = S.dod
    d.points = d.points or {}
    d.cool = d.cool or {}
    d.seq = d.seq or 0
    return d
end

local function rebuild()
    ON = {}
    if CM.isSP() then
        local p = getSpecificPlayer(0)
        if p then ON[keyOf(p)] = p end
        return
    end
    local list = getOnlinePlayers and getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p then ON[keyOf(p)] = p end
        end
    end
end

local function alive(p)
    if not p then return false end
    local ok, dead = pcall(function() return p:isDead() end)
    return ok and not dead
end

local function inVehicle(p)
    local ok, v = pcall(function() return p:getVehicle() end)
    return ok and v ~= nil
end

local function pos(p)
    local ok, x, y, z = pcall(function() return p:getX(), p:getY(), p:getZ() end)
    if not ok then return 0, 0, 0 end
    return math.floor(x), math.floor(y), math.floor(z or 0)
end

local function toast(k, kind, a)
    local p = ON[k]
    if p then send(p, "toast", { k = kind, a = a or {} }) end
end

local function toastAll(kind, a)
    if not L then return end
    for _, k in ipairs(L.list) do
        if not L.st or L.st[k] == "in" or L.phase == "lobby" then toast(k, kind, a) end
    end
end

-- ===================================================================== A-Life
local function alife()
    local a = ProjectALife
    if type(a) ~= "table" then return nil end
    local ds = a.DebugService
    if type(ds) ~= "table" or type(ds.rawSpawn) ~= "function" or type(ds.hostileProfileIds) ~= "function" then return nil end
    if type(a.SpawnService) ~= "table" or type(a.SpawnService.retire) ~= "function" then return nil end
    if type(a.ActorRegistry) ~= "table" or type(a.ActorRegistry.each) ~= "function" then return nil end
    return a
end

-- nil when Die or Die can run, else a reason key
function CMDoD.blocked()
    if not CM.dodOn() then return "off" end
    if not alife() then return "nolife" end
    return nil
end

-- army / National Guard factions of A-Life (bloc "military"); one is picked per match
local function militaryFactions(a)
    local out = {}
    local cat = a.Catalog
    local cur = cat and (cat.current or (type(cat.load) == "function" and cat.load()) or nil)
    for _, f in ipairs((cur and cur.factionOrder) or {}) do
        local bloc = type(f.relations) == "table" and f.relations.bloc or nil
        if bloc == "military" or f.id == "alife_guard" or f.id == "alife_cordon" then
            local g = type(f.general) == "table" and f.general or {}
            out[#out + 1] = { id = f.id, n = tostring(g.name or g.label or f.id) }
        end
    end
    return out
end

local function retireGroups(a, groups, reason)
    local uids = {}
    pcall(a.ActorRegistry.each, function(r)
        local mem = type(r.memory) == "table" and r.memory or {}
        if groups[tostring(mem.groupId or "")] and r.uid and r.lifecycle ~= "dead" then uids[#uids + 1] = tostring(r.uid) end
    end)
    for _, uid in ipairs(uids) do pcall(a.SpawnService.retire, uid, reason) end
    return #uids
end

-- ===================================================================== lobby
local function inLobby(k)
    if not L then return false end
    for _, x in ipairs(L.list) do if x == k then return true end end
    return false
end

local function coolLeft(k)
    local d = store()
    local t = d and d.cool[k]
    if not t then return 0 end
    return math.max(0, t - now())
end

-- why this player can not join a lobby (nil = fine)
local function joinBlock(k, p)
    local b = CMDoD.blocked()
    if b then return b end
    if not alive(p) then return "dead" end
    if CMS.runOf(k) then return "busy" end
    if CMS.inSquad and CMS.inSquad(k) then return "sqbusy" end
    if coolLeft(k) > 0 then return "dodcool" end
    return nil
end

local function freeColor()
    local used = {}
    for _, i in pairs(L.color) do used[i] = true end
    for i = 1, 8 do if not used[i] then return i end end
    return 1
end

local function addMember(k, p)
    L.list[#L.list + 1] = k
    L.names[k] = nameOf(p)
    L.color[k] = freeColor()
    L.sign[k] = L.color[k]
    L.inv[k] = nil
    toastAll("dodjoin", { nameOf(p), #L.list, D.MAX })
end

local function removeMember(k)
    if not L then return end
    for i = #L.list, 1, -1 do if L.list[i] == k then table.remove(L.list, i) end end
    local n = L.names[k] or k
    L.names[k], L.color[k], L.sign[k], L.ok[k], L.votes[k] = nil, nil, nil, nil, nil
    if #L.list == 0 then L = nil; return end
    if L.lead == k then
        L.lead = L.list[1]
        toast(L.lead, "sqlead", {})
    end
    toastAll("dodleft", { n })
end

-- ===================================================================== match
local function pointList()
    local d = store()
    local out = {}
    for _, id in ipairs(CM.sortedKeys(d and d.points or {})) do out[#out + 1] = d.points[id] end
    return out
end

-- god mode goes through the warp shield record (S.shield: prev + till) like every other warp: the shield tick
-- and the login check give the old value back even after a drop-out or a crash. The till is pushed forward
-- every second while the squad is locked, so it runs out by itself within GOD_PAD seconds of anything going wrong.
local GOD_PAD = 20

local function godOn(k, p)
    local S = CMS.state()
    local e = S.shield[k]
    if not e then
        local ok, was = pcall(function() return p:isGodMod() end)
        e = { prev = ok and was == true }
        S.shield[k] = e
    end
    e.till = now() + GOD_PAD
    pcall(function() p:setGodMod(true) end)
end

local function godOff(k)
    local S = CMS.state()
    if not S.shield[k] then return end
    local p = ON[k]
    if p then
        CMS.shieldOff(k, p)
    else
        -- offline: ends now, given back at login
        S.shield[k].till = now()
    end
end

local function areaRect(pt)
    return { x1 = pt.x - D.AREA, y1 = pt.y - D.AREA, x2 = pt.x + D.AREA, y2 = pt.y + D.AREA }
end

local function saveLive()
    local d = store()
    if not d or not L or not L.point then return end
    d.live = { id = L.id, groups = CM.copy(L.groups), homes = CM.copy(L.homes), rect = areaRect(L.point) }
end

local function sendHome(k, why)
    local h = L.homes[k]
    if not h then return end
    local S = CMS.state()
    local r = { x = h.x, y = h.y, z = h.z, t = now(), why = why or "home", site = areaRect(L.point), tries = 0 }
    S.returns[k] = r
    local p = ON[k]
    if p and alive(p) then
        CMS.grantShield(k, "home")
        send(p, "tp", { x = r.x, y = r.y, z = r.z, why = r.why })
        r.sent = now()
    end
end

local function tally()
    local pts = pointList()
    local count, best = {}, 0
    for _, pid in pairs(L.votes) do count[pid] = (count[pid] or 0) + 1 end
    local top = {}
    for _, pt in ipairs(pts) do
        local n = count[pt.id] or 0
        if n > best then best = n; top = { pt } elseif n == best then top[#top + 1] = pt end
    end
    if #top == 0 then return nil end
    return top[rand(#top) + 1]
end

-- everything that has to be true before the squad leaves (nil = go)
local function startBlock()
    local b = CMDoD.blocked()
    if b then return b end
    if #L.list < D.MIN then return "dodfew" end
    if #pointList() == 0 then return "dodnopoint" end
    for _, k in ipairs(L.list) do
        local p = ON[k]
        if not p or not alive(p) or inVehicle(p) or CMS.runOf(k) then return "dodnotready", L.names[k] end
        if not L.ok[k] then return "dodnowarn", L.names[k] end
        if coolLeft(k) > 0 then return "dodcool", L.names[k] end
    end
    return nil
end

local function beginLoad()
    local why, who = startBlock()
    if why then
        L.voteEnd = nil
        toastAll(why, { who or "" })
        return
    end
    local a = alife()
    local facs = militaryFactions(a)
    if #facs == 0 then toastAll("nolife", {}); L.voteEnd = nil; return end
    local fac = facs[rand(#facs) + 1]
    local pt = tally()
    local d = store()
    L.phase = "load"
    L.point = CM.copy(pt)
    L.faction, L.facName = fac.id, fac.n
    L.target = CM.dodCount(L.tier)
    L.homes, L.st, L.ready, L.kills = {}, {}, {}, {}
    L.inv = {}
    L.groups, L.npcs, L.pend = {}, {}, {}
    L.spawned = 0
    L.phaseAt = now() + D.LOAD
    for _, k in ipairs(L.list) do
        local p = ON[k]
        local x, y, z = pos(p)
        L.homes[k] = { x = x, y = y, z = z }
        L.st[k] = "in"
        L.kills[k] = 0
        d.cool[k] = now() + math.floor(CM.num(CM.sv("DodCooldown"), 3) * 3600)
        godOn(k, p)
        send(p, "tp", { x = pt.x, y = pt.y, z = pt.z or 0, why = "dod" })
    end
    saveLive()
    CMS.state().stats.dodMatches = (CMS.state().stats.dodMatches or 0) + 1
    log("match " .. L.id .. " at " .. tostring(pt.name) .. " tier " .. L.tier .. " vs " .. L.target .. " " .. tostring(fac.id))
end

-- split the target into A-Life requests of at most 8: guards first, then assault
local function queueSpawns()
    local guard = math.floor(L.target * (D.GUARD[L.tier] or 50) / 100 + 0.5)
    local left = { guard = guard, assault = L.target - guard }
    for _, mode in ipairs({ "guard", "assault" }) do
        local n = left[mode]
        while n > 0 do
            local c = math.min(D.GROUP, n)
            L.pend[#L.pend + 1] = { n = c, mode = mode, tries = 0 }
            n = n - c
        end
    end
    L.nextTry = 0
end

-- a spot SPAWN_MIN..SPAWN_MAX from the point, at least SPAWN_MIN from every member in the match
local function spawnSpot()
    local pt = L.point
    for _ = 1, 24 do
        local ang = rand(360) * math.pi / 180
        local dist = D.SPAWN_MIN + 3 + rand(D.SPAWN_MAX - D.SPAWN_MIN)
        local x = math.floor(pt.x + math.cos(ang) * dist)
        local y = math.floor(pt.y + math.sin(ang) * dist)
        local okP = true
        for _, k in ipairs(L.list) do
            local p = ON[k]
            if p and L.st[k] == "in" then
                local px, py = pos(p)
                local dx, dy = px - x, py - y
                if dx * dx + dy * dy < D.SPAWN_MIN * D.SPAWN_MIN then okP = false end
            end
        end
        if okP then return x, y end
    end
    return nil
end

local SPAWN_TRIES = 6
local WIN_HOLD = 20

local function spawnTick(a)
    if #L.pend == 0 or now() < (L.nextTry or 0) then return end
    local asker = nil
    for _, k in ipairs(L.list) do if L.st[k] == "in" and ON[k] then asker = ON[k]; break end end
    if not asker then return end
    local keep = {}
    for _, g in ipairs(L.pend) do
        local x, y = spawnSpot()
        local done = false
        if x then
            seq = seq + 1
            local okP, profiles = pcall(a.DebugService.hostileProfileIds, g.n, seq * 7919 + now(), L.faction, true)
            local opts = {
                requestId = "cm_dod_" .. L.id .. "_" .. tostring(seq), count = g.n,
                x = x, y = y, z = L.point.z or 0, radius = 6, separation = 2, distance = 0,
                factionId = L.faction, profileIds = okP and type(profiles) == "table" and profiles or nil,
                mode = g.mode, stance = g.mode == "guard" and "defend" or nil,
                hostileOverride = true, playerStance = "hostile", adminPick = false,
                objectiveX = g.mode == "assault" and L.point.x or nil, objectiveY = g.mode == "assault" and L.point.y or nil,
            }
            local ok, res = pcall(a.DebugService.rawSpawn, asker, opts, false)
            if ok and type(res) == "table" and res.ok == true and res.groupId ~= nil then
                L.groups[tostring(res.groupId)] = true
                L.spawned = L.spawned + g.n
                done = true
            else
                g.tries = g.tries + 1
                g.why = ok and type(res) == "table" and tostring(res.reason or "?") or tostring(res)
            end
        end
        -- refused too often: that group never comes (the target shrinks, the HUD counts what came)
        if not done and g.tries >= SPAWN_TRIES then
            L.target = math.max(0, L.target - g.n)
            log("group of " .. g.n .. " dropped after " .. g.tries .. " refusals (" .. tostring(g.why) .. ")")
            done = true
        end
        if not done then keep[#keep + 1] = g end
    end
    if #keep > 0 then
        L.nextTry = now() + D.RETRY
        if not L.toldWhy or now() - L.toldWhy > 60 then
            L.toldWhy = now()
            log("spawn refused (" .. tostring(keep[1].why) .. "), " .. #keep .. " groups waiting")
        end
    end
    L.pend = keep
    saveLive()
end

-- who is up, who is down (A-Life prunes old dead records: a soldier we knew that is gone counts as dead)
local function scanNpcs(a)
    local seen = {}
    pcall(a.ActorRegistry.each, function(r)
        local mem = type(r.memory) == "table" and r.memory or {}
        if L.groups[tostring(mem.groupId or "")] and r.uid then
            local uid = tostring(r.uid)
            seen[uid] = true
            local e = L.npcs[uid]
            if not e then
                e = { n = tostring(r.name or r.profileId or "?") }
                L.npcs[uid] = e
            end
            if r.lifecycle == "dead" then e.dead = true end
        end
    end)
    -- an empty scan (A-Life reloading) says nothing: only trust "gone = dead" when others are still listed
    -- or the soldier was killed by a player; the win also waits WIN_HOLD seconds (see matchTick)
    local any = false
    for _ in pairs(seen) do any = true; break end
    if any then
        for uid, e in pairs(L.npcs) do
            if not seen[uid] then e.dead = true end
        end
    end
end

local function counts()
    local n, dead = 0, 0
    for _, e in pairs(L.npcs) do
        n = n + 1
        if e.dead then dead = dead + 1 end
    end
    return n, dead
end

local function rollList(lines)
    local out = {}
    for _, d in ipairs(lines or {}) do
        for _ = 1, d.r do
            if rand(100) < d.c then
                local e = CMS.pickFrom(CMS.poolList(d.p))
                if not e and d.f then e = CMS.pickFrom(CMS.poolList(d.f)) end
                if e then out[#out + 1] = { t = e.t, n = CM.int(e.n, 1, 1, 50) } end
            end
        end
    end
    return out
end

local function finish(res)
    if not L or L.phase == "over" then return end
    local a = alife()
    if a then retireGroups(a, L.groups, "cookie_mission_dod") end
    L.phase = "over"
    L.res = res
    L.overAt = now() + 10
    -- top killer among the survivors gets the MVP lines
    local mvp, best = nil, 0
    for _, k in ipairs(L.list) do
        if L.st[k] == "in" and (L.kills[k] or 0) > best then mvp, best = k, L.kills[k] end
    end
    L.mvp = mvp and L.names[mvp] or nil
    for _, k in ipairs(L.list) do
        godOff(k)
        local p = ON[k]
        if L.st[k] == "in" then
            local rw = {}
            if res == "win" and p and alive(p) then
                rw = rollList(D.DROPS[L.tier])
                if k == mvp then
                    for _, e in ipairs(rollList(D.MVP[L.tier])) do rw[#rw + 1] = e end
                end
                for _, e in ipairs(rw) do CMS.giveTo(p, e.t, e.n) end
            end
            if p then send(p, "dodres", { res = res, rw = rw, mvp = L.mvp, kills = L.kills[k] or 0 }) end
            sendHome(k, "home")
            L.st[k] = "home"
        elseif p then
            send(p, "dodres", { res = res, rw = {}, mvp = L.mvp, kills = L.kills[k] or 0 })
        end
    end
    local d = store()
    if d then
        d.live = nil
        -- an aborted match (A-Life gone / refused everything) gives the cooldown back
        if res == "abort" then for _, k in ipairs(L.list) do d.cool[k] = nil end end
    end
    local n, dead = counts()
    log("match " .. L.id .. " " .. res .. " (" .. dead .. "/" .. n .. " soldiers down)")
end

local function matchTick(a)
    local t = now()
    -- members: dead / gone
    local anyIn = false
    for _, k in ipairs(L.list) do
        if L.st[k] == "in" then
            local p = ON[k]
            if p and not alive(p) then
                L.st[k] = "dead"
                godOff(k)
                toastAll("doddead", { L.names[k] })
            elseif not p then
                L.off = L.off or {}
                L.off[k] = L.off[k] or t
                if t - L.off[k] > 90 then
                    L.st[k] = "left"
                    godOff(k)
                    sendHome(k, "left")
                end
            else
                if L.off then L.off[k] = nil end
            end
            if L.st[k] == "in" then anyIn = true end
        end
    end
    if not anyIn then
        if L.phase == "live" then finish("lose") else finish("abort") end
        return
    end
    if L.phase == "load" or L.phase == "ready" or L.phase == "count" then
        for _, k in ipairs(L.list) do
            if L.st[k] == "in" and ON[k] then godOn(k, ON[k]) end
        end
    end
    if L.phase == "load" then
        if t >= L.phaseAt then
            L.phase = "ready"
            L.phaseAt = t + D.READY
        end
    elseif L.phase == "ready" then
        CMS.sweepZone({ x1 = L.point.x - D.CLEAR, y1 = L.point.y - D.CLEAR, x2 = L.point.x + D.CLEAR, y2 = L.point.y + D.CLEAR })
        local all = true
        for _, k in ipairs(L.list) do
            if L.st[k] == "in" and not L.ready[k] then all = false end
        end
        if all or t >= L.phaseAt then
            L.phase = "count"
            L.phaseAt = t + D.COUNT
        end
    elseif L.phase == "count" then
        if t >= L.phaseAt then
            L.phase = "live"
            L.endAt = t + CM.int(CM.sv("DodMinutes"), 30, 5, 120) * 60
            for _, k in ipairs(L.list) do godOff(k) end
            queueSpawns()
            spawnTick(a)
        end
    elseif L.phase == "live" then
        spawnTick(a)
        scanNpcs(a)
        local n, dead = counts()
        if #L.pend == 0 and n > 0 and dead >= n then
            L.allDownAt = L.allDownAt or t
        else
            L.allDownAt = nil
        end
        if #L.pend == 0 and n == 0 and L.target <= 0 then finish("abort")
        elseif L.allDownAt and t - L.allDownAt >= WIN_HOLD then finish("win")
        elseif t >= L.endAt then
            -- nobody to fight (A-Life refused every request): not the squad's fault
            if n == 0 then finish("abort") else finish("lose") end
        end
    end
end

-- ===================================================================== snapshots
local function snap(k)
    local d = store()
    local o = { on = CMDoD.blocked() == nil, why = CMDoD.blocked(), cool = coolLeft(k), admin = CMS.isAdmin(ON[k]) }
    local pts = {}
    for _, pt in ipairs(pointList()) do pts[#pts + 1] = { id = pt.id, name = pt.name, desc = pt.desc, x = pt.x, y = pt.y } end
    o.points = pts
    if L and L.inv[k] then o.inv = { by = L.names[L.lead] or "?" } end
    if not L then return o end
    local t = now()
    local lb = { id = L.id, phase = L.phase, lead = L.names[L.lead], leadMe = L.lead == k, me = inLobby(k), tier = L.tier,
        voteLeft = L.voteEnd and math.max(0, L.voteEnd - t) or nil, members = {}, votes = {}, myVote = L.votes[k] }
    for _, pid in pairs(L.votes) do lb.votes[pid] = (lb.votes[pid] or 0) + 1 end
    if L.lead == k and L.phase == "lobby" and #L.list < D.MAX then
        local free = {}
        for ok in pairs(ON) do
            if not inLobby(ok) and #free < 40 then free[#free + 1] = { k = ok, n = nameOf(ON[ok]), inv = L.inv[ok] ~= nil } end
        end
        table.sort(free, function(x, y) return x.n < y.n end)
        lb.free = free
    end
    for _, mk in ipairs(L.list) do
        lb.members[#lb.members + 1] = { k = mk, n = L.names[mk], c = L.color[mk], s = L.sign[mk], ok = L.ok[mk] == true,
            ready = L.ready and L.ready[mk] == true, st = L.st and L.st[mk] or nil, kills = L.kills and L.kills[mk] or 0,
            lead = mk == L.lead }
    end
    if L.phase ~= "lobby" then
        lb.point = L.point and { name = L.point.name, desc = L.point.desc, id = L.point.id, x = L.point.x, y = L.point.y,
            z = L.point.z } or nil
        lb.faction = L.facName
        lb.target = L.target
        lb.phaseLeft = L.phaseAt and math.max(0, L.phaseAt - t) or nil
        lb.left = L.endAt and math.max(0, L.endAt - t) or nil
        local n, dead = counts()
        lb.spawned, lb.dead, lb.reinf = n, dead, #L.pend > 0
        local list = {}
        for _, uid in ipairs(CM.sortedKeys(L.npcs)) do
            if #list < 40 then list[#list + 1] = { n = L.npcs[uid].n, d = L.npcs[uid].dead == true } end
        end
        lb.npcs = list
        lb.res, lb.mvp = L.res, L.mvp
    end
    o.lobby = lb
    return o
end

local function flush()
    local to = {}
    for k in pairs(watch) do to[k] = true end
    if L then
        for _, k in ipairs(L.list) do to[k] = true end
        for k in pairs(L.inv) do to[k] = true end
    end
    for k in pairs(to) do
        local p = ON[k]
        if p then send(p, "dod", snap(k)) else watch[k] = nil end
    end
end
CMDoD.flush = flush

-- ===================================================================== crash recovery
-- A restart mid-match: the soldiers of our groups are retired and everyone goes home on login (S.returns).
local function recoverTick()
    local d = store()
    if not d then return end
    if not recover then
        recover = { tries = 0, at = 0 }
        local live = d.live
        if live and live.homes then
            local S = CMS.state()
            for k, h in pairs(live.homes) do
                S.returns[k] = { x = h.x, y = h.y, z = h.z, t = now(), why = "back", site = live.rect }
            end
            log("match " .. tostring(live.id) .. " was live at boot: players go home on login")
        end
    end
    local live = d.live
    if not live then return end
    if now() < recover.at then return end
    recover.tries = recover.tries + 1
    recover.at = now() + 60
    local a = alife()
    if a and live.groups then
        local n = retireGroups(a, live.groups, "cookie_mission_dod_restart")
        if n > 0 then log("retired " .. n .. " soldiers left from match " .. tostring(live.id)) end
    end
    -- A-Life restores its actors a little after boot: look a few times, then forget the match
    if recover.tries >= 5 then d.live = nil end
end

-- ===================================================================== commands
function H.dodOpen(p) watch[keyOf(p)] = true; rebuild(); send(p, "dod", snap(keyOf(p))) end
function H.dodClose(p) watch[keyOf(p)] = nil end

function H.dodNew(p, args)
    local k = keyOf(p)
    if L then
        if inLobby(k) then return end
        return H.dodJoin(p, args)
    end
    local why = joinBlock(k, p)
    if why then send(p, "toast", { k = why, a = { CM.clock(coolLeft(k)) } }); return end
    seq = seq + 1
    L = { id = "d" .. tostring(seq), phase = "lobby", lead = k, list = {}, names = {}, color = {}, sign = {}, ok = {},
        votes = {}, inv = {}, tier = 2, t0 = now() }
    addMember(k, p)
end

function H.dodJoin(p, args)
    local k = keyOf(p)
    if not L or L.phase ~= "lobby" then send(p, "toast", { k = "dodgone", a = {} }); return end
    if inLobby(k) then return end
    local why = joinBlock(k, p)
    if why then send(p, "toast", { k = why, a = { CM.clock(coolLeft(k)) } }); return end
    if #L.list >= D.MAX then send(p, "toast", { k = "full", a = {} }); return end
    addMember(k, p)
end

function H.dodLeave(p, args)
    local k = keyOf(p)
    if not L or not inLobby(k) then return end
    if L.phase == "lobby" then removeMember(k); return end
    if L.phase ~= "over" and L.st[k] == "in" then
        -- leaving a match: no reward, straight home
        L.st[k] = "left"
        godOff(k)
        sendHome(k, "left")
        toastAll("dodleft", { L.names[k] })
    end
end

function H.dodKick(p, args)
    local k = keyOf(p)
    local who = CM.ukey(args.who)
    if not L or L.lead ~= k or L.phase ~= "lobby" or who == k or not inLobby(who) then return end
    toast(who, "sqkicked", {})
    removeMember(who)
end

function H.dodInvite(p, args)
    local k = keyOf(p)
    local who = CM.ukey(args.who)
    if not L or L.lead ~= k or L.phase ~= "lobby" or inLobby(who) then return end
    local q = ON[who]
    if not q or L.inv[who] then return end
    L.inv[who] = now()
    send(q, "dodinv", { by = nameOf(p) })
    send(p, "toast", { k = "sqsent", a = { nameOf(q) } })
end

function H.dodAnswer(p, args)
    local k = keyOf(p)
    if not L or not L.inv[k] then return end
    L.inv[k] = nil
    if args.yes == true then H.dodJoin(p, args) else toast(L.lead, "sqno", { nameOf(p) }) end
end

function H.dodPick(p, args)
    local k = keyOf(p)
    if not L or not inLobby(k) or L.phase ~= "lobby" then return end
    if args.c then L.color[k] = CM.int(args.c, 1, 1, 8) end
    if args.s then L.sign[k] = CM.int(args.s, 1, 1, 8) end
end

-- the hardcore warning: death in the match is real
function H.dodWarn(p, args)
    local k = keyOf(p)
    if not L or not inLobby(k) or L.phase ~= "lobby" then return end
    L.ok[k] = args.yes == true
end

function H.dodVote(p, args)
    local k = keyOf(p)
    local d = store()
    if not L or not inLobby(k) or L.phase ~= "lobby" then return end
    local pid = tostring(args.id or "")
    if d.points[pid] then L.votes[k] = pid end
end

function H.dodTier(p, args)
    local k = keyOf(p)
    if not L or L.lead ~= k or L.phase ~= "lobby" then return end
    L.tier = CM.int(args.tier, 2, 1, 3)
end

-- leader: start the 60 s vote; again (force) = go now
function H.dodStart(p, args)
    local k = keyOf(p)
    if not L or L.lead ~= k or L.phase ~= "lobby" then return end
    local why, who = startBlock()
    if why then send(p, "toast", { k = why, a = { who or "" } }); return end
    if L.voteEnd and args.force == true then
        L.voteEnd = now()
    elseif not L.voteEnd then
        L.voteEnd = now() + D.VOTE
        toastAll("dodvote", { D.VOTE })
    end
end

function H.dodReady(p, args)
    local k = keyOf(p)
    if not L or L.phase ~= "ready" or L.st[k] ~= "in" then return end
    L.ready[k] = true
end

-- admin: save the spot under your feet / remove one
function A.dodSave(p, args)
    local d = store()
    local x, y, z = pos(p)
    d.seq = d.seq + 1
    local id = "p" .. tostring(d.seq)
    local name = CM.trim(CM.str(args.name, 40))
    if name == "" then name = CM.townAt(x, y) .. " #" .. tostring(d.seq) end
    d.points[id] = { id = id, name = name, desc = CM.trim(CM.str(args.desc, 240)), x = x, y = y, z = z, by = nameOf(p), t = now() }
    log("spot " .. id .. " saved at " .. x .. "," .. y .. "," .. z .. " (" .. name .. ")")
    send(p, "toast", { k = "dodsaved", a = { name } })
end

function A.dodDel(p, args)
    local d = store()
    local id = tostring(args.id or "")
    if not d.points[id] then return end
    log("spot " .. id .. " removed (" .. tostring(d.points[id].name) .. ")")
    d.points[id] = nil
end

-- ===================================================================== hooks
-- a soldier body died: credit the last player who hit it (the OnZombieDead of the main server file calls this)
function CMS.dodNpcDead(zombie, killer)
    if not L or L.phase ~= "live" then return end
    local okU, uid = pcall(function() return zombie:getModData().ProjectALifeUID end)
    local e = okU and uid and L.npcs[tostring(uid)] or nil
    if not e or e.dead then return end
    e.dead = true
    if killer then
        local k = keyOf(killer)
        if L.st[k] == "in" then L.kills[k] = (L.kills[k] or 0) + 1 end
    end
end

-- seen by the squad code: one queue at a time
function CMS.inDod(k)
    if not inLobby(k) then return false end
    return L.phase == "lobby" or (L.st and L.st[k] == "in") or false
end

local function onTick()
    local ms = getTimestampMs and getTimestampMs() or now() * 1000
    if ms - lastTick < 1000 then return end
    lastTick = ms
    if not CMS.state() then return end
    rebuild()
    recoverTick()
    if L then
        local a = alife()
        if L.phase == "lobby" then
            for _, k in ipairs(CM.copy(L.list)) do
                if not ON[k] then
                    L.off = L.off or {}
                    L.off[k] = L.off[k] or now()
                    if now() - L.off[k] > 120 then removeMember(k) end
                elseif L.off then L.off[k] = nil end
                if not L then break end
            end
            if L and now() - L.t0 > 30 * 60 then
                toastAll("dodexpire", {})
                L = nil
            elseif L and L.voteEnd and now() >= L.voteEnd then
                beginLoad()
            end
        elseif L.phase == "over" then
            if now() >= L.overAt then L = nil end
        elseif not a then
            -- A-Life went away mid-match: stop safely
            finish("abort")
        else
            matchTick(a)
        end
    end
    flush()
end

Events.OnTick.Add(function()
    local ok, err = pcall(onTick)
    if not ok then CM.log("dod tick error: " .. tostring(err)) end
end)

return CMDoD
