-- Cookie Mission - Die or Die (server). Teams of 2-8 each book one of the 5 spots, deploy together (insertion
-- screen, warp into the spot's safe area), get 2 minutes of recon, then Project A-Life soldiers come from the
-- spawn points an admin set. Only a real death takes a player out (the game's own rules, nothing extra).
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
local TEAMS = {}           -- teamId -> team (memory only)
local byKey = {}           -- ukey -> teamId
local watch = {}           -- ukey -> true while the Die or Die window is open
local hitLog = {}          -- npc uid -> { ukey -> ms of the last hit }
local ON = {}              -- ukey -> IsoPlayer (rebuilt every tick)
local seq = 0
local lastTick = 0
local recovered = nil      -- { tries, at } crash recovery of matches that were live at boot

local function now() return CM.now() end
local function nowMs() return getTimestampMs and getTimestampMs() or now() * 1000 end
local function rand(n) if n <= 1 then return 0 end return ZombRand(n) end
local function log(s) CMS.logLine("[DoD] " .. tostring(s)) end

-- persistent part (global ModData "CookieMission"): spot setup, cooldowns, scoreboard, live matches
local function store()
    local S = CMS.state()
    if not S then return nil end
    S.dod = S.dod or {}
    local d = S.dod
    d.locs = d.locs or {}
    d.cool = d.cool or {}
    d.board = d.board or {}
    -- 1.2.0 kept one live match as { id, groups, homes, rect }: one entry per team now
    if type(d.live) ~= "table" then d.live = {}
    elseif d.live.id then d.live = { [tostring(d.live.id)] = d.live } end
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

local function toastTeam(t, kind, a)
    for _, k in ipairs(t.list) do
        if t.phase == "room" or (t.st and t.st[k] == "in") then toast(k, kind, a) end
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

-- ===================================================================== spots
local function locCfg(id)
    local d = store()
    if not d or not D.LOC[id] then return nil end
    d.locs[id] = d.locs[id] or { spawns = {} }
    return d.locs[id]
end

local function locReady(id)
    local c = locCfg(id)
    return c ~= nil and c.safe ~= nil and #(c.spawns or {}) > 0
end

local function locTeam(id)
    for tid, t in pairs(TEAMS) do
        if t.loc == id then return tid, t end
    end
    return nil
end

local function locCenter(c)
    return math.floor((c.safe.x1 + c.safe.x2) / 2), math.floor((c.safe.y1 + c.safe.y2) / 2), c.safe.z or 0
end

local function areaRect(c)
    return { x1 = c.safe.x1 - D.AREA, y1 = c.safe.y1 - D.AREA, x2 = c.safe.x2 + D.AREA, y2 = c.safe.y2 + D.AREA }
end

-- ===================================================================== teams
local function coolLeft(k)
    local d = store()
    local t = d and d.cool[k]
    if not t then return 0 end
    return math.max(0, t - now())
end

local function teamOf(k)
    local tid = byKey[k]
    return tid and TEAMS[tid] or nil
end

-- why this player can not be in a team (nil = fine)
local function joinBlock(k, p)
    local b = CMDoD.blocked()
    if b then return b end
    if not alive(p) then return "dead" end
    if CMS.runOf(k) then return "busy" end
    if CMS.inSquad and CMS.inSquad(k) then return "sqbusy" end
    if teamOf(k) then return "dodbusy" end
    if coolLeft(k) > 0 then return "dodcool" end
    return nil
end

local function blockToast(p, k, why)
    send(p, "toast", { k = why, a = { CM.clock(coolLeft(k)) } })
end

local function addMember(t, k, p)
    t.list[#t.list + 1] = k
    t.names[k] = nameOf(p)
    t.inv[k] = nil
    t.ready[k] = (k == t.lead)
    byKey[k] = t.id
    toastTeam(t, "dodjoin", { nameOf(p), #t.list, t.size })
end

local function dropTeam(t, kind)
    for _, k in ipairs(t.list) do
        byKey[k] = nil
        if kind then toast(k, kind, {}) end
    end
    TEAMS[t.id] = nil
    local d = store()
    if d then d.live[t.id] = nil end
end

local function removeMember(t, k)
    for i = #t.list, 1, -1 do if t.list[i] == k then table.remove(t.list, i) end end
    byKey[k] = nil
    local n = t.names[k] or k
    t.ready[k] = nil
    if #t.list == 0 then dropTeam(t); return end
    if t.lead == k then
        t.lead = t.list[1]
        t.ready[t.lead] = true
        toast(t.lead, "sqlead", {})
    end
    toastTeam(t, "dodleft", { n })
end

-- ===================================================================== match helpers
local function saveLive(t)
    local d = store()
    if not d or not t.cfg then return end
    d.live[t.id] = { groups = CM.copy(t.groups), homes = CM.copy(t.homes), rect = areaRect(t.cfg) }
end

-- god mode through the warp shield record (S.shield: prev + till): given back by the shield tick or at login
local function godOn(k, p, sec)
    local S = CMS.state()
    local e = S.shield[k]
    if not e then
        local ok, was = pcall(function() return p:isGodMod() end)
        e = { prev = ok and was == true }
        S.shield[k] = e
    end
    e.till = now() + sec
    pcall(function() p:setGodMod(true) end)
end

local function godOff(k)
    local S = CMS.state()
    if not S.shield[k] then return end
    local p = ON[k]
    if p then CMS.shieldOff(k, p) else S.shield[k].till = now() end
end

local function sendHome(t, k, why)
    local h = t.homes and t.homes[k]
    if not h then return end
    local S = CMS.state()
    local r = { x = h.x, y = h.y, z = h.z, t = now(), why = why or "home", site = t.cfg and areaRect(t.cfg) or nil, tries = 0 }
    S.returns[k] = r
    local p = ON[k]
    if p and alive(p) then
        CMS.grantShield(k, "home")
        send(p, "tp", { x = r.x, y = r.y, z = r.z, why = r.why })
        r.sent = now()
    end
end

-- everything that has to be true before the team leaves (nil = go)
local function deployBlock(t)
    local b = CMDoD.blocked()
    if b then return b end
    if #t.list < D.MIN then return "dodfew" end
    if not locReady(t.loc) then return "dodnoloc" end
    for _, k in ipairs(t.list) do
        local p = ON[k]
        if not p or not alive(p) or inVehicle(p) or CMS.runOf(k) then return "dodnotready", t.names[k] end
        if not t.ready[k] then return "dodwait", t.names[k] end
        if coolLeft(k) > 0 then return "dodcool", t.names[k] end
    end
    return nil
end

local function startWarp(t)
    local a = alife()
    local facs = a and militaryFactions(a) or {}
    if #facs == 0 then toastTeam(t, "nolife", {}); return end
    local fac = facs[rand(#facs) + 1]
    local d = store()
    t.phase = "warp"
    t.phaseAt = now() + D.WARP
    t.cfg = CM.copy(locCfg(t.loc))
    t.faction, t.facName = fac.id, fac.n
    t.target = CM.dodCount(t.tier)
    t.homes, t.st, t.stats = {}, {}, {}
    t.groups, t.npcs, t.pend = {}, {}, {}
    t.inv = {}
    for _, k in ipairs(t.list) do
        local x, y, z = pos(ON[k])
        t.homes[k] = { x = x, y = y, z = z }
        t.st[k] = "in"
        t.stats[k] = { k = 0, d = 0, a = 0 }
        d.cool[k] = now() + math.floor(CM.num(CM.sv("DodCooldown"), 3) * 3600)
        -- the insertion screen hides the world: nothing may bite you while it is up
        godOn(k, ON[k], D.WARP + D.SHIELD)
    end
    t.landed = {}
    saveLive(t)
    CMS.state().stats.dodMatches = (CMS.state().stats.dodMatches or 0) + 1
    log("team " .. t.id .. " deploys to " .. t.loc .. " tier " .. t.tier .. " vs " .. t.target .. " " .. tostring(fac.id))
end

-- the warp itself, at the end of the insertion screen: a random spot of the safe area each
local function landOne(t, k, p)
    local s = t.cfg.safe
    local x = s.x1 + rand(s.x2 - s.x1 + 1)
    local y = s.y1 + rand(s.y2 - s.y1 + 1)
    godOn(k, p, D.SHIELD + D.WARP)
    send(p, "tp", { x = x, y = y, z = s.z or 0, why = "dod" })
    t.landed[k] = true
end

local function landTeam(t)
    for _, k in ipairs(t.list) do
        local p = ON[k]
        if p and t.st[k] == "in" then landOne(t, k, p) end
    end
end

-- the target in A-Life requests of at most 8, spread over the spawn points (guards first)
local function queueSpawns(t)
    local guard = math.floor(t.target * (D.GUARD[t.tier] or 50) / 100 + 0.5)
    local left = { guard = guard, assault = t.target - guard }
    local sp = t.cfg.spawns
    local i = 0
    for _, mode in ipairs({ "guard", "assault" }) do
        local n = left[mode]
        while n > 0 do
            local c = math.min(D.GROUP, n)
            i = i + 1
            t.pend[#t.pend + 1] = { n = c, mode = mode, tries = 0, sp = sp[CM.mod(i - 1, #sp) + 1] }
            n = n - c
        end
    end
    t.nextTry = 0
end

local function spawnTick(t, a)
    if #t.pend == 0 or now() < (t.nextTry or 0) then return end
    local asker = nil
    for _, k in ipairs(t.list) do if t.st[k] == "in" and ON[k] then asker = ON[k]; break end end
    if not asker then return end
    local keep = {}
    local cx, cy = locCenter(t.cfg)
    for _, g in ipairs(t.pend) do
        seq = seq + 1
        local okP, profiles = pcall(a.DebugService.hostileProfileIds, g.n, seq * 7919 + now(), t.faction, true)
        local opts = {
            requestId = "cm_dod_" .. t.id .. "_" .. tostring(seq), count = g.n,
            x = g.sp.x, y = g.sp.y, z = g.sp.z or 0, radius = 6, separation = 2, distance = 0,
            factionId = t.faction, profileIds = okP and type(profiles) == "table" and profiles or nil,
            mode = g.mode, stance = g.mode == "guard" and "defend" or nil,
            hostileOverride = true, playerStance = "hostile", adminPick = false,
            objectiveX = g.mode == "assault" and cx or nil, objectiveY = g.mode == "assault" and cy or nil,
        }
        local ok, res = pcall(a.DebugService.rawSpawn, asker, opts, false)
        local done = false
        if ok and type(res) == "table" and res.ok == true and res.groupId ~= nil then
            t.groups[tostring(res.groupId)] = true
            done = true
        else
            g.tries = g.tries + 1
            g.why = ok and type(res) == "table" and tostring(res.reason or "?") or tostring(res)
            if g.tries >= D.TRIES then
                -- refused too often: that group never comes, the target shrinks
                t.target = math.max(0, t.target - g.n)
                log("team " .. t.id .. ": group of " .. g.n .. " dropped after " .. g.tries .. " refusals (" .. g.why .. ")")
                done = true
            end
        end
        if not done then keep[#keep + 1] = g end
    end
    t.pend = keep
    if #keep > 0 then t.nextTry = now() + D.RETRY end
    saveLive(t)
end

-- who is up, who is down. A soldier that stays out of "active" (never showed up, or streamed out where nobody
-- can reach it) for STUCK seconds is retired and counts as down; A-Life prunes old dead records, so one that
-- disappears while others are still listed is down too.
local function scanNpcs(t, a)
    local seen, any = {}, false
    local tn = now()
    pcall(a.ActorRegistry.each, function(r)
        local mem = type(r.memory) == "table" and r.memory or {}
        if t.groups[tostring(mem.groupId or "")] and r.uid then
            local uid = tostring(r.uid)
            seen[uid] = true
            any = true
            local e = t.npcs[uid]
            if not e then
                e = { n = tostring(r.name or r.profileId or "?") }
                t.npcs[uid] = e
            end
            if r.lifecycle == "dead" then
                e.dead = true
            elseif r.lifecycle == "active" then
                e.since = nil
            elseif not e.dead then
                e.since = e.since or tn
                if tn - e.since >= D.STUCK then
                    pcall(a.SpawnService.retire, uid, "cookie_mission_dod_stuck")
                    e.dead = true
                    e.stuck = true
                end
            end
        end
    end)
    if any then
        for uid, e in pairs(t.npcs) do
            if not seen[uid] then e.dead = true end
        end
    end
end

local function counts(t)
    local n, dead = 0, 0
    for _, e in pairs(t.npcs or {}) do
        n = n + 1
        if e.dead then dead = dead + 1 end
    end
    return n, dead
end

local function rollList(lines)
    local out = {}
    for _, d in ipairs(lines or {}) do
        local chance = CM.dropChance(d)
        for _ = 1, d.r do
            if rand(100) < chance then
                local e = CMS.pickFrom(CMS.poolList(d.p))
                if not e and d.f then e = CMS.pickFrom(CMS.poolList(d.f)) end
                if e then out[#out + 1] = { t = e.t, n = CM.int(e.n, 1, 1, 50) } end
            end
        end
    end
    return out
end

-- scoreboard: wins per tier and MVPs, all time and this week
local function boardWin(k, name, tier, mvp, kills)
    local d = store()
    local b = d.board[k] or { n = name, w = { 0, 0, 0 }, mvp = 0, kills = 0 }
    d.board[k] = b
    b.n = name
    b.w[tier] = (b.w[tier] or 0) + 1
    b.kills = (b.kills or 0) + (kills or 0)
    if mvp then b.mvp = (b.mvp or 0) + 1 end
    local wk = CM.dodWeek()
    if not b.wk or b.wk.week ~= wk then b.wk = { week = wk, w = { 0, 0, 0 }, mvp = 0 } end
    b.wk.w[tier] = (b.wk.w[tier] or 0) + 1
    if mvp then b.wk.mvp = b.wk.mvp + 1 end
end

local function finish(t, res)
    if t.phase == "over" then return end
    local a = alife()
    if a and t.groups then pcall(retireGroups, a, t.groups, "cookie_mission_dod") end
    for uid in pairs(t.npcs or {}) do hitLog[uid] = nil end
    t.phase = "over"
    t.res = res
    t.overAt = now() + 12
    -- MVP = most kills (ties: more damage)
    local mvp, best, bestD = nil, 0, 0
    for _, k in ipairs(t.list) do
        local s = t.stats[k]
        if s and t.st[k] ~= "left" and (s.k > best or (s.k == best and s.k > 0 and s.d > bestD)) then
            mvp, best, bestD = k, s.k, s.d
        end
    end
    t.mvp = mvp
    t.rw = {}
    for _, k in ipairs(t.list) do
        local p = ON[k]
        t.rw[k] = {}
        -- a win pays everyone who did not give up (down players too: they fought); the scoreboard counts
        -- only the ones still standing at the end
        if res == "win" and t.st[k] ~= "left" then
            local ok, err = pcall(function()
                local rw = rollList(D.DROPS[t.tier])
                if k == mvp then
                    for _, e in ipairs(rollList(D.MVP[t.tier])) do rw[#rw + 1] = e end
                end
                t.rw[k] = rw
                if p and alive(p) then
                    for _, e in ipairs(rw) do CMS.giveTo(p, e.t, e.n) end
                else
                    local S = CMS.state()
                    S.pend[k] = S.pend[k] or {}
                    for _, e in ipairs(rw) do S.pend[k][#S.pend[k] + 1] = e end
                end
                if t.st[k] == "in" then boardWin(k, t.names[k], t.tier, k == mvp, t.stats[k] and t.stats[k].k or 0) end
            end)
            if not ok then CM.log("dod reward error: " .. tostring(err)) end
        end
        pcall(godOff, k)
        if t.st[k] == "in" then
            pcall(sendHome, t, k, "home")
            t.st[k] = "home"
        end
    end
    local d = store()
    if d then
        d.live[t.id] = nil
        -- the system failed (A-Life gone / refused everything / soldiers never came): cooldown given back;
        -- a team that left or went down by itself ("quit") keeps it
        if res == "abort" or res == "nofight" then for _, k in ipairs(t.list) do d.cool[k] = nil end end
    end
    local n, dead = counts(t)
    log("team " .. t.id .. " " .. res .. " at " .. t.loc .. " (" .. dead .. "/" .. n .. " soldiers down)")
end

-- a member really died: out of this match (the reward of a win still waits for the new character)
local function died(t, k)
    if t.st[k] ~= "in" then return end
    t.st[k] = "dead"
    godOff(k)
    toastTeam(t, "doddead", { t.names[k] })
end

local function matchTick(t, a)
    local tn = now()
    -- members: down / gone
    local anyIn = false
    for _, k in ipairs(t.list) do
        if t.st[k] == "in" then
            local p = ON[k]
            if p then
                if t.off then t.off[k] = nil end
                if not alive(p) then died(t, k) end
            else
                t.off = t.off or {}
                t.off[k] = t.off[k] or tn
                if tn - t.off[k] > 90 then
                    t.st[k] = "left"
                    godOff(k)
                    sendHome(t, k, "left")
                end
            end
            if t.st[k] == "in" then anyIn = true end
        end
    end
    if not anyIn then
        if t.phase == "live" then finish(t, "lose") else finish(t, "quit") end
        return
    end
    -- someone who dropped out during the warp and came back: land them now
    if (t.phase == "recon" or t.phase == "live") and t.landed then
        for _, k in ipairs(t.list) do
            if t.st[k] == "in" and ON[k] and not t.landed[k] then landOne(t, k, ON[k]) end
        end
    end
    if t.phase == "warp" then
        if tn >= t.phaseAt then
            landTeam(t)
            t.phase = "recon"
            t.phaseAt = tn + D.RECON
        end
    elseif t.phase == "recon" then
        local s = t.cfg.safe
        if tn - (t.sweptAt or 0) >= 3 then
            t.sweptAt = tn
            CMS.sweepZone({ x1 = s.x1 - D.CLEAR, y1 = s.y1 - D.CLEAR, x2 = s.x2 + D.CLEAR, y2 = s.y2 + D.CLEAR })
        end
        if tn >= t.phaseAt then
            t.phase = "live"
            t.endAt = tn + CM.int(CM.sv("DodMinutes"), 30, 5, 120) * 60
            queueSpawns(t)
            spawnTick(t, a)
            toastTeam(t, "dodinbound", { t.target })
        end
    elseif t.phase == "live" then
        spawnTick(t, a)
        scanNpcs(t, a)
        local n, dead = counts(t)
        if #t.pend == 0 and n > 0 and dead >= n then t.allDownAt = t.allDownAt or tn else t.allDownAt = nil end
        if #t.pend == 0 and n == 0 and t.target <= 0 then finish(t, "abort")
        elseif t.allDownAt and tn - t.allDownAt >= D.WIN_HOLD then
            local stuck, kills = 0, 0
            for _, e in pairs(t.npcs) do if e.stuck then stuck = stuck + 1 end end
            for _, s in pairs(t.stats) do kills = kills + s.k end
            if stuck * 2 > n or kills == 0 then finish(t, "nofight") else finish(t, "win") end
        elseif tn >= t.endAt then
            if n == 0 then finish(t, "abort") else finish(t, "lose") end
        end
    end
end

-- ===================================================================== snapshots
local function teamPub(t)
    return { id = t.id, loc = t.loc, tier = t.tier, size = t.size, lead = t.names[t.lead], n = #t.list, phase = t.phase,
        left = t.endAt and math.max(0, t.endAt - now()) or nil }
end

local function snap(k)
    local p = ON[k]
    local o = { on = CMDoD.blocked() == nil, why = CMDoD.blocked(), cool = coolLeft(k), admin = CMS.isAdmin(p) }
    local locs = {}
    for _, l in ipairs(D.LOCS) do
        local c = locCfg(l.id)
        local tid = locTeam(l.id)
        local e = { id = l.id, ok = locReady(l.id), busy = tid ~= nil, phase = tid and TEAMS[tid].phase or nil }
        if o.admin then
            e.safe = c.safe and CM.copy(c.safe) or nil
            e.c1 = c.c1 and CM.copy(c.c1) or nil
            e.spawns = CM.copy(c.spawns or {})
        end
        locs[#locs + 1] = e
    end
    o.locs = locs
    local teams = {}
    for _, tid in ipairs(CM.sortedKeys(TEAMS)) do teams[#teams + 1] = teamPub(TEAMS[tid]) end
    o.teams = teams
    local inv = {}
    for tid, t in pairs(TEAMS) do
        if t.inv[k] then inv[#inv + 1] = { id = tid, by = t.names[t.lead], loc = t.loc } end
    end
    o.inv = inv
    local t = teamOf(k)
    if t then
        local tn = now()
        local me = teamPub(t)
        me.leadMe = t.lead == k
        me.members = {}
        for _, mk in ipairs(t.list) do
            local s = t.stats and t.stats[mk] or nil
            me.members[#me.members + 1] = { k = mk, n = t.names[mk], lead = mk == t.lead, ready = t.ready[mk] == true,
                st = t.st and t.st[mk] or nil, kills = s and s.k or 0, dmg = s and math.floor(s.d * 100 + 0.5) or 0,
                ast = s and s.a or 0, on = ON[mk] ~= nil }
        end
        if t.phase == "room" and t.lead == k and #t.list < t.size then
            local free = {}
            for ok, op in pairs(ON) do
                if not byKey[ok] and #free < 40 then free[#free + 1] = { k = ok, n = nameOf(op), inv = t.inv[ok] ~= nil } end
            end
            table.sort(free, function(x, y) return x.n < y.n end)
            me.free = free
        end
        me.closeLeft = t.phase == "room" and math.max(0, D.TEAM_LIFE - (tn - t.t0)) or nil
        if t.phase ~= "room" then
            me.phaseLeft = t.phaseAt and math.max(0, t.phaseAt - tn) or nil
            me.faction = t.facName
            me.target = t.target
            local n, dead = counts(t)
            me.spawned, me.dead, me.reinf = n, dead, #(t.pend or {}) > 0
            me.res = t.res
            me.mvp = t.mvp and t.names[t.mvp] or nil
            me.rw = t.rw and t.rw[k] or nil
            local list = {}
            for _, uid in ipairs(CM.sortedKeys(t.npcs or {})) do
                if #list < 40 then list[#list + 1] = { n = t.npcs[uid].n, d = t.npcs[uid].dead == true } end
            end
            me.npcs = list
        end
        o.team = me
    end
    return o
end

local function flush()
    local to = {}
    for k in pairs(watch) do to[k] = true end
    for _, t in pairs(TEAMS) do
        for _, k in ipairs(t.list) do to[k] = true end
        for k in pairs(t.inv) do to[k] = true end
    end
    for k in pairs(to) do
        local p = ON[k]
        if p then send(p, "dod", snap(k)) else watch[k] = nil end
    end
end
CMDoD.flush = flush

-- the scoreboard (asked for when its tab opens)
local function board(k, week)
    local d = store()
    local wk = CM.dodWeek()
    local rows = {}
    for bk, b in pairs(d.board) do
        local w, mvp = b.w, b.mvp or 0
        if week then
            if b.wk and b.wk.week == wk then w, mvp = b.wk.w, b.wk.mvp else w = nil end
        end
        if w then
            local total = (w[1] or 0) + (w[2] or 0) + (w[3] or 0)
            if total > 0 then rows[#rows + 1] = { k = bk, n = b.n, w = { w[1] or 0, w[2] or 0, w[3] or 0 }, t = total, mvp = mvp } end
        end
    end
    table.sort(rows, function(x, y)
        if x.t ~= y.t then return x.t > y.t end
        if x.w[3] ~= y.w[3] then return x.w[3] > y.w[3] end
        if x.mvp ~= y.mvp then return x.mvp > y.mvp end
        return x.n < y.n
    end)
    local out, mine, total = {}, nil, 0
    for i, r in ipairs(rows) do
        total = total + r.t
        if r.k == k then mine = i end
        if i <= 20 then r.me = r.k == k; r.k = nil; out[#out + 1] = r end
    end
    return { week = week == true, rows = out, mine = mine, total = total, matches = CMS.state().stats.dodMatches or 0 }
end

-- ===================================================================== crash recovery
-- A restart mid-match: the soldiers of our groups are retired and everyone goes home on login (S.returns).
local function recoverTick()
    local d = store()
    if not d then return end
    if not recovered then
        recovered = { tries = 0, at = 0 }
        local S = CMS.state()
        for tid, live in pairs(d.live) do
            for k, h in pairs(live.homes or {}) do
                S.returns[k] = { x = h.x, y = h.y, z = h.z, t = now(), why = "back", site = live.rect }
            end
            log("team " .. tostring(tid) .. " was in a match at boot: players go home on login")
        end
    end
    local any = false
    for tid in pairs(d.live) do if not TEAMS[tid] then any = true end end
    if not any or now() < recovered.at then return end
    recovered.tries = recovered.tries + 1
    recovered.at = now() + 60
    local a = alife()
    if a then
        for tid, live in pairs(d.live) do
            if not TEAMS[tid] and live.groups then
                local n = retireGroups(a, live.groups, "cookie_mission_dod_restart")
                if n > 0 then log("retired " .. n .. " soldiers left from team " .. tostring(tid)) end
            end
        end
    end
    -- A-Life restores its actors a little after boot: look a few times, then forget them
    if recovered.tries >= 5 then
        for tid in pairs(d.live) do
            if not TEAMS[tid] then d.live[tid] = nil end
        end
    end
end

-- ===================================================================== player commands
local function sizeOk(n)
    for _, s in ipairs(D.SIZES) do if s == n then return true end end
    return false
end

function H.dodOpen(p) watch[keyOf(p)] = true; rebuild(); send(p, "dod", snap(keyOf(p))) end
function H.dodClose(p) watch[keyOf(p)] = nil end
function H.dodBoard(p, args) send(p, "dodboard", board(keyOf(p), args.week == true)) end

-- make a team: book a free, set up spot
function H.dodNew(p, args)
    local k = keyOf(p)
    local why = joinBlock(k, p)
    if why then blockToast(p, k, why); return end
    local loc = tostring(args.loc or "")
    if not D.LOC[loc] or not locReady(loc) then send(p, "toast", { k = "dodnoloc", a = {} }); return end
    if locTeam(loc) then send(p, "toast", { k = "dodlocbusy", a = {} }); return end
    local size = CM.int(args.size, 4)
    if not sizeOk(size) then size = 4 end
    seq = seq + 1
    local t = { id = "t" .. tostring(now()) .. "_" .. tostring(seq), phase = "room", loc = loc, tier = CM.int(args.tier, 2, 1, 3), size = size,
        lead = k, list = {}, names = {}, ready = {}, inv = {}, t0 = now() }
    TEAMS[t.id] = t
    addMember(t, k, p)
end

function H.dodJoin(p, args)
    local k = keyOf(p)
    local t = TEAMS[tostring(args.id or "")]
    if not t or t.phase ~= "room" then send(p, "toast", { k = "dodgone", a = {} }); return end
    local why = joinBlock(k, p)
    if why then blockToast(p, k, why); return end
    if #t.list >= t.size then send(p, "toast", { k = "full", a = {} }); return end
    addMember(t, k, p)
end

function H.dodLeave(p, args)
    local k = keyOf(p)
    local t = teamOf(k)
    if not t then return end
    if t.phase == "room" then removeMember(t, k); return end
    if t.phase ~= "over" and t.st[k] == "in" then
        -- giving up mid match: no reward, straight home
        t.st[k] = "left"
        godOff(k)
        sendHome(t, k, "left")
        toastTeam(t, "dodleft", { t.names[k] })
    end
end

function H.dodKick(p, args)
    local k = keyOf(p)
    local t = teamOf(k)
    local who = CM.ukey(args.who)
    if not t or t.lead ~= k or t.phase ~= "room" or who == k or byKey[who] ~= t.id then return end
    toast(who, "sqkicked", {})
    removeMember(t, who)
end

function H.dodDisband(p, args)
    local k = keyOf(p)
    local t = teamOf(k)
    if not t or t.lead ~= k or t.phase ~= "room" then return end
    dropTeam(t, "sqdisband")
end

function H.dodInvite(p, args)
    local k = keyOf(p)
    local t = teamOf(k)
    local who = CM.ukey(args.who)
    if not t or t.lead ~= k or t.phase ~= "room" or byKey[who] or t.inv[who] then return end
    local q = ON[who]
    if not q then return end
    t.inv[who] = now()
    send(q, "dodinv", { id = t.id, by = nameOf(p), loc = t.loc })
    send(p, "toast", { k = "sqsent", a = { nameOf(q) } })
end

function H.dodAnswer(p, args)
    local k = keyOf(p)
    local t = TEAMS[tostring(args.id or "")]
    if not t or not t.inv[k] then return end
    t.inv[k] = nil
    if args.yes == true then H.dodJoin(p, args) else toast(t.lead, "sqno", { nameOf(p) }) end
end

-- leader: spot / difficulty / team size while in the room
function H.dodSet(p, args)
    local k = keyOf(p)
    local t = teamOf(k)
    if not t or t.lead ~= k or t.phase ~= "room" then return end
    if args.loc then
        local loc = tostring(args.loc)
        local holder = locTeam(loc)
        if D.LOC[loc] and locReady(loc) and (not holder or holder == t.id) then t.loc = loc
        else send(p, "toast", { k = "dodlocbusy", a = {} }) end
    end
    if args.tier then t.tier = CM.int(args.tier, 2, 1, 3) end
    local size = CM.int(args.size, 0)
    if args.size and sizeOk(size) and size >= #t.list then t.size = size end
    if args.loc or args.tier then
        for _, mk in ipairs(t.list) do t.ready[mk] = (mk == t.lead) end
    end
end

function H.dodReady(p, args)
    local k = keyOf(p)
    local t = teamOf(k)
    if not t or t.phase ~= "room" or t.lead == k then return end
    t.ready[k] = args.yes == true
end

function H.dodDeploy(p, args)
    local k = keyOf(p)
    local t = teamOf(k)
    if not t or t.lead ~= k or t.phase ~= "room" then return end
    local why, who = deployBlock(t)
    if why then send(p, "toast", { k = why, a = { who or "" } }); return end
    startWarp(t)
end

-- ===================================================================== admin: spot setup (stand on the spot)
local function admLoc(p, args)
    local id = tostring(args.loc or "")
    if not D.LOC[id] then return nil end
    return locCfg(id), id
end

-- safe area: first press = one corner where you stand, second press = the opposite corner
function A.dodCorner(p, args)
    local c, id = admLoc(p, args)
    if not c then return end
    local x, y, z = pos(p)
    if not c.c1 or args.first == true then
        c.c1 = { x = x, y = y, z = z }
        send(p, "toast", { k = "dodc1", a = { D.LOC[id].n } })
        return
    end
    c.safe = { x1 = math.min(c.c1.x, x), y1 = math.min(c.c1.y, y), x2 = math.max(c.c1.x, x), y2 = math.max(c.c1.y, y), z = c.c1.z }
    c.c1 = nil
    log("safe area of " .. id .. " set " .. c.safe.x1 .. "," .. c.safe.y1 .. " - " .. c.safe.x2 .. "," .. c.safe.y2)
    send(p, "toast", { k = "dodsafe", a = { D.LOC[id].n, c.safe.x2 - c.safe.x1 + 1, c.safe.y2 - c.safe.y1 + 1 } })
end

function A.dodSpawn(p, args)
    local c, id = admLoc(p, args)
    if not c then return end
    local x, y, z = pos(p)
    c.spawns = c.spawns or {}
    if #c.spawns >= 16 then return end
    c.spawns[#c.spawns + 1] = { x = x, y = y, z = z }
    log("spawn point " .. #c.spawns .. " of " .. id .. " at " .. x .. "," .. y .. "," .. z)
    send(p, "toast", { k = "dodsp", a = { D.LOC[id].n, #c.spawns } })
end

function A.dodSpawnDel(p, args)
    local c, id = admLoc(p, args)
    local i = CM.int(args.i, 0)
    if not c or not c.spawns or not c.spawns[i] then return end
    table.remove(c.spawns, i)
    log("spawn point " .. i .. " of " .. id .. " removed")
end

function A.dodLocClear(p, args)
    local c, id = admLoc(p, args)
    if not c then return end
    if locTeam(id) then send(p, "toast", { k = "dodlocbusy", a = {} }); return end
    store().locs[id] = { spawns = {} }
    log("spot " .. id .. " cleared")
end

function A.dodLocGo(p, args)
    local c = admLoc(p, args)
    if not c then return end
    local x, y, z
    if c.safe then x, y, z = locCenter(c)
    elseif c.spawns and c.spawns[1] then x, y, z = c.spawns[1].x, c.spawns[1].y, c.spawns[1].z end
    if x then send(p, "tp", { x = x, y = y, z = z or 0, why = "dod" }) end
end

-- ===================================================================== hooks
local function teamOfNpc(uid)
    for _, t in pairs(TEAMS) do
        if t.npcs and t.npcs[uid] then return t end
    end
    return nil
end

-- damage and assists: every player hit on one of our soldiers
if Events.OnWeaponHitCharacter then Events.OnWeaponHitCharacter.Add(function(attacker, target, weapon, damage)
    if not attacker or not target or not instanceof(attacker, "IsoPlayer") or not instanceof(target, "IsoZombie") then return end
    local okU, uid = pcall(function() return target:getModData().ProjectALifeUID end)
    if not okU or not uid then return end
    uid = tostring(uid)
    local t = teamOfNpc(uid)
    if not t or t.phase ~= "live" then return end
    local k = keyOf(attacker)
    local s = t.stats[k]
    if not s or t.st[k] ~= "in" then return end
    s.d = s.d + math.max(0, CM.num(damage, 0))
    hitLog[uid] = hitLog[uid] or {}
    hitLog[uid][k] = nowMs()
end) end

-- a soldier body died (called from the main server file's OnZombieDead): kill to the killer, assists to the
-- others who hit it lately
function CMS.dodNpcDead(zombie, killer)
    local okU, uid = pcall(function() return zombie:getModData().ProjectALifeUID end)
    if not okU or not uid then return end
    uid = tostring(uid)
    local t = teamOfNpc(uid)
    local e = t and t.npcs[uid]
    if not e or e.dead then return end
    e.dead = true
    local kk = killer and keyOf(killer) or nil
    if kk and t.stats[kk] and t.st[kk] == "in" then t.stats[kk].k = t.stats[kk].k + 1 end
    local ms = nowMs()
    for k, at in pairs(hitLog[uid] or {}) do
        if k ~= kk and t.stats[k] and ms - at <= D.ASSIST * 1000 then t.stats[k].a = t.stats[k].a + 1 end
    end
    hitLog[uid] = nil
end

-- seen by the missions and the squads: one queue at a time
function CMS.inDod(k)
    local t = teamOf(k)
    if not t then return false end
    return t.phase == "room" or (t.st and t.st[k] == "in") or false
end

local function onTick()
    local ms = nowMs()
    if ms - lastTick < 1000 then return end
    lastTick = ms
    if not CMS.state() then return end
    rebuild()
    recoverTick()
    local a = alife()
    for _, tid in ipairs(CM.sortedKeys(TEAMS)) do
        local t = TEAMS[tid]
        if t and t.phase == "room" then
            for _, k in ipairs(CM.copy(t.list)) do
                if not ON[k] then
                    t.off = t.off or {}
                    t.off[k] = t.off[k] or now()
                    if now() - t.off[k] > 120 then removeMember(t, k) end
                elseif t.off then t.off[k] = nil end
                if not TEAMS[tid] then break end
            end
            if TEAMS[tid] and now() - t.t0 > D.TEAM_LIFE then dropTeam(t, "dodexpire") end
            if TEAMS[tid] then
                for k, at in pairs(t.inv) do if now() - at > 60 then t.inv[k] = nil end end
            end
        elseif t and t.phase == "over" then
            if now() >= t.overAt then dropTeam(t) end
        elseif t and not a then
            finish(t, "abort")
        elseif t then
            local ok, err = pcall(matchTick, t, a)
            if not ok then CM.log("dod team " .. tid .. " error: " .. tostring(err)) end
        end
    end
    flush()
end

Events.OnTick.Add(function()
    local ok, err = pcall(onTick)
    if not ok then CM.log("dod tick error: " .. tostring(err)) end
end)

return CMDoD
