-- Cookie Mission - server authority (dedicated server, host, or single player)
if isClient() and not isServer() then return end

require "CM_Shared"

CMS = CMS or {}
local MOD = CM.MOD
local S = nil              -- persistent state (global ModData "CookieMission")
local online = {}          -- ukey -> IsoPlayer (rebuilt every tick)
local RT = {}              -- runId -> runtime only data (zombie objects etc.), never saved
local admWatch = {}        -- ukey -> true while the admin panel is open
local admTold = {}         -- ukey -> last isadm answer sent
local hitCache = {}        -- zombie -> { p, ms } last player hit
local rate = {}
local dirty = { pub = true, adm = true, me = {} }
local lastTick, lastFlush, lastSlow = 0, 0, 0
local badOutfit = {}

-- ===================================================================== state
local function defaults(s)
    s.v = s.v or 1
    s.seq = s.seq or 100
    s.day = s.day or -1
    s.cards = s.cards or {}
    s.claims = s.claims or {}
    s.bans = s.bans or {}
    s.pins = s.pins or {}
    s.returns = s.returns or {}
    s.pend = s.pend or {}
    s.log = s.log or {}
    s.stats = s.stats or {}
    s.hist = s.hist or {}
    s.sweeps = s.sweeps or {}
    s.shield = s.shield or {}
end

function CMS.state() return S end
function CMS.runtime() return RT end

local function now() return CM.now() end
local function nowMs()
    if getTimestampMs then
        local ok, v = pcall(getTimestampMs)
        if ok and v then return v end
    end
    return now() * 1000
end
local function newId(prefix) S.seq = S.seq + 1; return prefix .. tostring(S.seq) end

local logActor = nil
local function logLine(text)
    if logActor then text = "[" .. logActor .. "] " .. tostring(text) end
    table.insert(S.log, 1, { t = now(), s = tostring(text) })
    while #S.log > 80 do table.remove(S.log) end
    dirty.adm = true
end
CMS.logLine = logLine

local function stat(k, n)
    S.stats[k] = (S.stats[k] or 0) + (n or 1)
end

local function rand(n)
    if n <= 1 then return 0 end
    return ZombRand(n)
end

-- ===================================================================== players
local function nameOf(p)
    local ok, n = pcall(function() return p:getUsername() end)
    if ok and n and n ~= "" then return tostring(n) end
    return "Player"
end
CMS.nameOf = nameOf
local function keyOf(p) return CM.ukey(nameOf(p)) end
CMS.keyOf = keyOf

local function rebuildOnline()
    online = {}
    if CM.isSP() then
        local p = getSpecificPlayer(0)
        if p then online[keyOf(p)] = p end
        return
    end
    local list = getOnlinePlayers and getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p then online[keyOf(p)] = p end
        end
    end
end
CMS.rebuildOnline = rebuildOnline

local function alive(p)
    if not p then return false end
    local ok, dead = pcall(function() return p:isDead() end)
    return ok and not dead
end

local function pos(p)
    local ok, x, y, z = pcall(function() return p:getX(), p:getY(), p:getZ() end)
    if not ok then return 0, 0, 0 end
    return math.floor(x), math.floor(y), math.floor(z or 0)
end

-- staff = the vanilla "admin tool" right of the player's B42 role (same check CookieQuest uses)
local STAFF_LEVELS = { admin = true, moderator = true, overseer = true, gm = true }
function CMS.isAdmin(p)
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

-- ===================================================================== networking
local function deliver(p, cmd, args)
    if isServer() then
        sendServerCommand(p, MOD, cmd, args)
    else
        triggerEvent("OnServerCommand", MOD, cmd, CM.copy(args))
    end
end
CMS.send = deliver

local function deliverAll(cmd, args)
    if isServer() then
        sendServerCommand(MOD, cmd, args)
    else
        triggerEvent("OnServerCommand", MOD, cmd, CM.copy(args))
    end
end

local function toast(k, kind, a)
    local p = online[k]
    if p then deliver(p, "toast", { k = kind, a = a or {} }) end
end

local function toastPlayer(p, kind, a)
    if p then deliver(p, "toast", { k = kind, a = a or {} }) end
end

-- ===================================================================== items
local function itemExists(ft)
    local sm = getScriptManager()
    if not sm then return false end
    local ok, it = pcall(function() return sm:FindItem(ft) end)
    return ok and it ~= nil
end
CMS.itemExists = itemExists

local function giveTo(p, ft, n)
    local inv = p and p:getInventory()
    if not inv or not itemExists(ft) then return 0 end
    local got = 0
    for _ = 1, n do
        local ok, item = pcall(instanceItem, ft)
        if ok and item then
            inv:AddItem(item)
            if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
            got = got + 1
        end
    end
    return got
end
CMS.giveTo = giveTo

-- ===================================================================== reward pools
local function poolList(name)
    if S.pools and S.pools[name] then return S.pools[name] end
    return CM.DEFAULT_POOLS[name] or {}
end
CMS.poolList = poolList

local function ensurePools()
    if S.pools then return end
    S.pools = {}
    for _, n in ipairs(CM.POOLS) do S.pools[n] = CM.copy(CM.DEFAULT_POOLS[n] or {}) end
end

-- installed Legendary Tactical Weapons (or anything named like them) -> legend pool, once
local SKIP_SUFFIX = { " Blade", " Handle", " Head", " Bar", " Case", " Sheath", " Component", " Parts" }
local LEGEND_WORDS = { "Sword", "Tomahawk", "Axe", "Crowbar", "Bat", "Hammer", "Knife", "Sledgehammer", "Spear" }
function CMS.scanLegend()
    local sm = getScriptManager()
    if not sm then return {} end
    local ok, all = pcall(function() return sm:getAllItems() end)
    if not ok or not all then return {} end
    local out = {}
    for i = 0, all:size() - 1 do
        local it = all:get(i)
        local okN, ft, dn = pcall(function() return it:getFullName(), it:getDisplayName() end)
        if okN and ft and dn then
            dn = tostring(dn)
            if string.find(dn, "Legendary", 1, true) and not string.find(dn, "Magazine", 1, true) then
                local skip = false
                for _, s in ipairs(SKIP_SUFFIX) do
                    if string.sub(dn, -#s) == s then skip = true end
                end
                local weapon = false
                for _, w in ipairs(LEGEND_WORDS) do
                    if string.find(dn, w, 1, true) then weapon = true end
                end
                if weapon and not skip then out[#out + 1] = { t = tostring(ft), w = 10, n = 1 } end
            end
        end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- legend pool = default entries (Frostburn ...) + every installed "Legendary" weapon, no duplicates
function CMS.legendPool()
    local out, seen = {}, {}
    for _, e in ipairs(CM.DEFAULT_POOLS.legend or {}) do
        if not seen[e.t] then seen[e.t] = true; out[#out + 1] = CM.copy(e) end
    end
    for _, e in ipairs(CMS.scanLegend()) do
        if not seen[e.t] then seen[e.t] = true; out[#out + 1] = e end
    end
    return out
end

local function pickFrom(list)
    local total = 0
    local ok = {}
    for i = 1, #list do
        local e = list[i]
        if e and e.t and itemExists(e.t) and (e.w or 0) > 0 then
            ok[#ok + 1] = e
            total = total + e.w
        end
    end
    if total <= 0 then return nil end
    local r = rand(total)
    for i = 1, #ok do
        r = r - ok[i].w
        if r < 0 then return ok[i] end
    end
    return ok[#ok]
end
CMS.pickFrom = pickFrom

-- roll the reward list for one player of a tier: { {t, n} }
function CMS.rollRewards(tier)
    local drops = CM.DROPS[tier] or CM.DROPS[1]
    local out = {}
    for _, d in ipairs(drops) do
        local chance = CM.dropChance(d)
        for _ = 1, d.r do
            local e = nil
            if rand(100) < chance then
                -- f = fallback pool when this pool has nothing that exists on the server
                e = pickFrom(poolList(d.p))
                if not e and d.f then e = pickFrom(poolList(d.f)) end
            elseif d.alt then
                -- alt = consolation pool when the chance roll fails
                e = pickFrom(poolList(d.alt))
            end
            if e then out[#out + 1] = { t = e.t, n = CM.int(e.n, 1, 1, 50) } end
        end
    end
    return out
end

-- ===================================================================== building scan
local function metaGrid()
    local w = getWorld and getWorld()
    if not w then return nil end
    return CM.call(w, "getMetaGrid")
end


local function overlapsSafehouse(x1, y1, x2, y2)
    if not SafeHouse then return false end
    local ok, list = pcall(function() return SafeHouse.getSafehouseList() end)
    if not ok or not list then return false end
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        local okS, sx, sy, sw, shh = pcall(function() return sh:getX(), sh:getY(), sh:getW(), sh:getH() end)
        if okS and sx then
            if not (x2 + 10 < sx or x1 - 10 > sx + sw or y2 + 10 < sy or y1 - 10 > sy + shh) then return true end
        end
    end
    return false
end

-- BuildingDef -> site table lives in shared (the admin panel reads it too)
CMS.siteFromDef = CM.siteFromDef

local function siteFits(site, tier) return CM.siteFits(site, tier) end
CMS.siteFits = siteFits

local function townExcluded(name)
    for _, t in ipairs(CM.split(CM.sv("ExcludeTowns"), ";")) do
        if string.lower(t) == string.lower(tostring(name)) then return true end
    end
    return false
end

-- random real building for a tier; avoid = { bid = true }
function CMS.scanSite(tier, avoid)
    avoid = avoid or {}
    -- admin pins first (by chance)
    local pins = {}
    for _, bid in ipairs(CM.sortedKeys(S.pins)) do
        local pn = S.pins[bid]
        if pn and not avoid[bid] and not S.bans[bid] and (pn.tiers == nil or pn.tiers[tier]) then pins[#pins + 1] = pn end
    end
    if #pins > 0 and rand(100) < CM.sv("PinChance") then
        local pn = pins[rand(#pins) + 1]
        local site = CM.copy(pn.site)
        site.pinned = true
        return site
    end
    local mg = metaGrid()
    local towns = {}
    local total = 0
    for _, t in ipairs(CM.TOWNS) do
        if not townExcluded(t.n) and CM.townOn(t) then
            local w = math.floor(math.sqrt((t.x2 - t.x1) * (t.y2 - t.y1)))
            towns[#towns + 1] = { t = t, w = w }
            total = total + w
        end
    end
    local found = {}
    local tries = 0
    if mg and total > 0 then
        while tries < 450 and #found < 8 do
            tries = tries + 1
            local r = rand(total)
            local tw = towns[#towns]
            for i = 1, #towns do
                r = r - towns[i].w
                if r < 0 then tw = towns[i]; break end
            end
            local t = tw.t
            local x = t.x1 + rand(t.x2 - t.x1 + 1)
            local y = t.y1 + rand(t.y2 - t.y1 + 1)
            local def = CM.call(mg, "getBuildingAt", x, y)
            if def then
                local site = CMS.siteFromDef(def)
                if site and not avoid[site.bid] and not S.bans[site.bid] and siteFits(site, tier)
                    and not overlapsSafehouse(site.x1, site.y1, site.x2, site.y2) then
                    local dup = false
                    for i = 1, #found do if found[i].bid == site.bid then dup = true end end
                    if not dup then found[#found + 1] = site end
                end
            end
        end
    end
    S.stats.lastScan = { tier = tier, tries = tries, found = #found, grid = mg ~= nil }
    if #found > 0 then return found[rand(#found) + 1] end
    if #pins > 0 then
        local site = CM.copy(pins[rand(#pins) + 1].site)
        site.pinned = true
        return site
    end
    return nil
end

-- ===================================================================== cards
local function pickType(tier, used)
    local opts = {}
    for _, t in ipairs(CM.TYPES) do
        if CM.typeOn(t) and not used[t] then opts[#opts + 1] = t end
    end
    if #opts == 0 then
        for _, t in ipairs(CM.TYPES) do if CM.typeOn(t) then opts[#opts + 1] = t end end
    end
    if #opts == 0 then return "kill" end
    return opts[rand(#opts) + 1]
end

local function usedSites(exceptSlot)
    local u = {}
    for s = 1, 3 do
        local c = S.cards[s]
        if c and s ~= exceptSlot and c.site then u[c.site.bid] = true end
    end
    return u
end

local function usedTypes(exceptSlot)
    local u = {}
    for s = 1, 3 do
        local c = S.cards[s]
        if c and s ~= exceptSlot and c.type then u[c.type] = true end
    end
    return u
end

function CMS.makeCard(slot, typ)
    local tier = slot
    typ = typ or pickType(tier, usedTypes(slot))
    local site = CMS.scanSite(tier, usedSites(slot))
    S.seq = S.seq + 1
    local c = {
        id = "d" .. tostring(S.day) .. "s" .. tostring(slot) .. "n" .. tostring(S.seq),
        slot = slot, tier = tier, type = typ, day = S.day,
        site = site,
        goal = CM.goalFor(tier, typ),
        limit = CM.limitFor(tier, typ),
        cap = CM.capFor(tier),
        status = site and "open" or "none",
        runs = 0,
    }
    S.cards[slot] = c
    dirty.pub = true
    dirty.adm = true
    if site then
        logLine("card " .. slot .. " " .. typ .. " @ " .. tostring(site.town) .. " " .. tostring(site.kind) .. " " .. site.bid)
    else
        logLine("card " .. slot .. " has no place (scan found nothing)")
    end
    return c
end

-- ===================================================================== runs
local function rt(run)
    local r = RT[run.id]
    if not r then
        r = { zs = {}, dead = {}, gang = {}, objGang = {}, pulse = 0, placed = false, alive = 0, gangAlive = 0 }
        RT[run.id] = r
    end
    return r
end
CMS.rt = rt

local function memberCount(run, onlyIn)
    local n = 0
    for _, m in pairs(run.members or {}) do
        if m.st == "in" or (not onlyIn and m.st == "off") then n = n + 1 end
    end
    return n
end
CMS.memberCount = memberCount

local function runOf(k)
    for s = 1, 3 do
        local c = S.cards[s]
        local run = c and c.run
        if run and run.phase ~= "closed" then
            local m = run.members[k]
            if m and (m.st == "in" or m.st == "off" or (run.phase == "over" and m.st ~= "dead" and m.st ~= "home" and m.st ~= "left")) then
                return c, run, m
            end
        end
    end
    return nil
end
CMS.runOf = runOf

local function markRun(run)
    for k in pairs(run.members or {}) do dirty.me[k] = true end
    dirty.pub = true
    dirty.adm = true
end

-- ===================================================================== warp shield (server half)
-- The client part (setZombiesDontAttack + frozen zombies) stops vanilla zombies. Silent Hill Monsters
-- (incl. the Cry of Fear ones) hurt players through their own server command, which only checks
-- victim:isGodMod() on the server -> god mode on the server-side player for the same few seconds.
-- Only granted right after a mission warp the server itself sent; always switched back (also after a relog).
local shieldGrant = {}     -- ukey -> { t, why } : a "go"/"home" warp was sent, the client may ask once

local function grantShield(k, why)
    shieldGrant[k] = { t = now(), why = why }
end
CMS.grantShield = grantShield

local function shieldOff(k, p)
    local e = S.shield[k]
    if not e then return end
    if p then pcall(function() p:setGodMod(e.prev == true) end) end
    S.shield[k] = nil
end
CMS.shieldOff = shieldOff

local function shieldTick()
    local t = now()
    for k, e in pairs(S.shield) do
        local p = online[k]
        if p then
            if t >= (e.till or 0) or not alive(p) then shieldOff(k, p) end
        elseif t - (e.till or 0) > 7 * 86400 then
            S.shield[k] = nil
        end
    end
end
CMS.shieldTick = shieldTick

-- ===================================================================== confirmed warps
-- A warp is done by the client; the server only learns the new spot from the player's position
-- packets, and the speed anti-cheat drops those for about a second after any long jump. A client
-- that drops out during that second is saved where it started (seen 8 Nov: warp home, crash,
-- back at the mission). So a return stays on file until the server itself sees the player home,
-- is sent again on login, and again every RESEND_S seconds while it has not landed.
local ARRIVE_R = 30      -- tiles from the target that count as arrived
local RESEND_S = 60      -- seconds between resends while online
local RESEND_MAX = 6     -- resends while online before giving up (a login starts the count again)
local GO_MAX = 4

local function siteRect(card)
    local s = card and card.site
    if not s then return nil end
    return { x1 = s.x1, y1 = s.y1, x2 = s.x2, y2 = s.y2 }
end

local function inVehicle(p)
    local ok, veh = pcall(function() return p:getVehicle() end)
    return ok and veh ~= nil
end

local function sendHome(k, m, why, card)
    if not m or not m.home then return end
    why = why or "home"
    local r = { x = m.home.x, y = m.home.y, z = m.home.z, t = now(), why = why, site = siteRect(card), tries = 0 }
    S.returns[k] = r
    local p = online[k]
    if p and alive(p) then
        if why == "home" then grantShield(k, "home") end
        deliver(p, "tp", { x = r.x, y = r.y, z = r.z, why = why })
        r.sent = now()
    end
end
CMS.sendHome = sendHome

-- fromHello = the player just logged in: send at once, the resend count starts again
local function checkReturn(k, p, fromHello)
    local r = S.returns[k]
    if not r then return end
    if not alive(p) then S.returns[k] = nil; return end
    if runOf(k) then return end
    local t = now()
    if t - (r.t or t) > 7 * 86400 then S.returns[k] = nil; return end
    local okP, px, py = pcall(function() return p:getX(), p:getY() end)
    if not okP or px == nil or py == nil then return end
    local dx, dy = px - r.x, py - r.y
    if dx * dx + dy * dy <= ARRIVE_R * ARRIVE_R then
        if (r.tries or 0) > 0 or r.again then
            logLine(nameOf(p) .. " is home now (warp sent again " .. ((r.tries or 0) + (r.again or 0)) .. "x)")
        end
        S.returns[k] = nil
        return
    end
    -- neither home nor at the mission (walked or drove off): leave them alone
    if r.site and CM.rectDist(r.site, px, py) > CM.sv("LeaveDistance") + 40 then
        S.returns[k] = nil
        return
    end
    if inVehicle(p) then return end
    local why = "back"
    if fromHello then
        r.tries = 0
        if r.sent or r.rescue then
            r.again = (r.again or 0) + 1
            logLine(nameOf(p) .. " logged in at the mission, not home: warp home sent again")
        end
    elseif r.sent then
        if t - r.sent < RESEND_S then return end
        if (r.tries or 0) >= RESEND_MAX then
            logLine(nameOf(p) .. " still not home after " .. RESEND_MAX .. " warps, gave up")
            S.returns[k] = nil
            return
        end
        r.tries = (r.tries or 0) + 1
        why = r.why or "back"
        logLine("warp home sent again to " .. nameOf(p) .. " (" .. r.tries .. ")")
    end
    if why == "home" then grantShield(k, "home") end
    deliver(p, "tp", { x = r.x, y = r.y, z = r.z, why = why })
    r.sent = t
end
CMS.checkReturn = checkReturn

local lastReturnTick = 0
local function returnTick()
    local t = now()
    if t - lastReturnTick < 3 then return end
    lastReturnTick = t
    for _, k in ipairs(CM.sortedKeys(S.returns)) do
        local p = online[k]
        if p then checkReturn(k, p, false) end
    end
end
CMS.returnTick = returnTick

local function sendGo(k, p, card)
    local site = card.site
    grantShield(k, "go")
    deliver(p, "tp", { x = site.ax, y = site.ay, z = site.az or 0, why = "go", slot = card.slot,
        zone = { x1 = site.x1, y1 = site.y1, x2 = site.x2, y2 = site.y2 } })
end

-- the mission warp has not landed (m.go is cleared once the server sees the player in the zone)
local function resendGo(k, p, card, run, m, fromHello)
    local g = m.go
    if not g or not card.site then return end
    if inVehicle(p) then return end
    if not fromHello then
        if now() - (g.t or 0) < RESEND_S then return end
        if (g.n or 0) >= GO_MAX then m.go = nil; return end   -- the normal leave rules take over
        g.n = (g.n or 0) + 1
    end
    g.t = now()
    m.out = 0; m.warned = nil
    sendGo(k, p, card)
    logLine("mission warp sent again to " .. tostring(m.n) .. " (run " .. tostring(run.id) .. ")")
end
CMS.resendGo = resendGo

-- reward check for one member at the end of a successful run
local function eligible(card, run, k, m, t)
    if m.st ~= "in" and m.st ~= "off" then return false, "gone" end
    if S.claims[k] and S.claims[k][card.id] then return false, "claimed" end
    if card.type == "survive" and (m.st ~= "in" or (m.d or 0) > 12) then return false, "away" end
    local stay = t - (m.at or t)
    if stay >= CM.sv("MinPresence") then return true end
    if (m.kills or 0) >= 3 or (m.found or 0) >= 1 or (m.tasks or 0) >= 1 then return true end
    return false, "late"
end

local function finishRun(card, run, result)
    if run.phase ~= "live" then return end
    local t = now()
    run.phase = "over"
    run.result = result
    run.endT = t
    run.returnAt = t + CM.sv("ReturnDelay")
    pcall(CMS.afterRun, card, run, true)
    local names = {}
    for _, k in ipairs(CM.sortedKeys(run.members)) do
        local m = run.members[k]
        names[#names + 1] = m.n
        if result == "ok" then
            local ok, why = eligible(card, run, k, m, t)
            if ok then
                local list = CMS.rollRewards(card.tier)
                m.rw = list
                S.claims[k] = S.claims[k] or {}
                S.claims[k][card.id] = true
                local p = online[k]
                if p and alive(p) and m.st == "in" then
                    for _, it in ipairs(list) do giveTo(p, it.t, it.n) end
                else
                    S.pend[k] = S.pend[k] or {}
                    for _, it in ipairs(list) do S.pend[k][#S.pend[k] + 1] = { t = it.t, n = it.n } end
                end
                stat("rewarded")
            else
                m.nr = why
            end
        end
        if m.st == "in" or m.st == "off" then
            local p = online[k]
            if p then deliver(p, "result", { slot = card.slot, res = result, rw = m.rw or {}, nr = m.nr, back = CM.sv("ReturnDelay") }) end
        end
    end
    card.runs = (card.runs or 0) + 1
    card.last = { res = result, t = t, who = names, kills = run.kills, id = run.id }
    table.insert(S.hist, 1, { t = t, card = card.id, slot = card.slot, type = card.type, res = result, who = names, place = card.site and card.site.town })
    while #S.hist > 30 do table.remove(S.hist) end
    stat("runs_" .. tostring(result))
    logLine("run " .. run.id .. " slot " .. card.slot .. " ended: " .. tostring(result) .. " (" .. table.concat(names, ",") .. ")")
    markRun(run)
end
CMS.finishRun = finishRun

local function removeZombie(z)
    pcall(function() z:removeFromWorld() end)
    pcall(function() z:removeFromSquare() end)
end

local function cleanupRun(run)
    local r = RT[run.id]
    if r and CM.sv("CleanupZombies") ~= false then
        local n = 0
        for i = 1, #r.zs do
            local z = r.zs[i]
            local ok, dead, sq = pcall(function() return z:isDead(), z:getCurrentSquare() end)
            if ok and not dead and sq ~= nil then removeZombie(z); n = n + 1 end
        end
        if n > 0 then
            logLine("run " .. run.id .. " cleared " .. n .. " zombies")
            CM.log("run " .. run.id .. " cleared " .. n .. " tracked zombies")
        end
    end
    -- leftover supply caches that nobody picked up
    if r and r.cacheObjs then
        for _, c in ipairs(r.cacheObjs) do
            if c.cont and c.item then
                pcall(function() c.cont:Remove(c.item) end)
                if isServer() and sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, c.cont, c.item) end
            end
        end
    end
    RT[run.id] = nil
end

local function closeRun(card, run)
    for _, k in ipairs(CM.sortedKeys(run.members)) do
        local m = run.members[k]
        if m.st == "in" or m.st == "off" then
            sendHome(k, m, "home", card)
            m.st = "home"
        end
    end
    run.phase = "closed"
    cleanupRun(run)
    pcall(CMS.afterRun, card, run, false)
    card.status = "cool"
    card.coolUntil = now() + CM.int(CM.sv("Cooldown"), 3, 0, 240) * 60
    markRun(run)
end
CMS.closeRun = closeRun

-- admin reroll / forced stop: end the run now and send everyone home
local function abortRun(card, why)
    local run = card.run
    if not run or run.phase == "closed" then return end
    if run.phase == "live" then finishRun(card, run, why or "abort") end
    closeRun(card, run)
end
CMS.abortRun = abortRun

local function newRun(card)
    local run = {
        id = newId("r"), phase = "live", t0 = now(), members = {},
        kills = 0, gang = 0, held = 0, spawned = 0, gangSpawned = 0,
        found = {}, caches = {}, emptyFor = 0,
        tasks = {}, tdone = {}, tlock = {}, whacked = 0,
    }
    run.endAt = run.t0 + card.limit
    card.run = run
    card.status = "live"
    stat("runs")
    logLine("run " .. run.id .. " started on slot " .. card.slot)
    return run
end

-- ===================================================================== spawning
local function cell() return getCell and getCell() or nil end

-- ===================================================================== zombie sweeps
-- Zombies are cleared by AREA, not only from the spawn list: the list loses every zombie that was unloaded and
-- loaded again, and nothing can be removed from squares that are not loaded (everyone pressed "go home").
-- A zone (building + SWEEP_MARGIN) is swept when the run ends, again every 15 s for CleanupMinutes, and if it
-- was not loaded at the end of that window, the first time somebody brings it back (up to 3 days).
local SWEEP_MARGIN = 30
local SWEEP_EVERY = 15
local SWEEP_MAX_AGE = 3 * 86400

local function zoneOf(site, margin)
    margin = margin or SWEEP_MARGIN
    return { x1 = site.x1 - margin, y1 = site.y1 - margin, x2 = site.x2 + margin, y2 = site.y2 + margin }
end
CMS.zoneOf = zoneOf

local function overlap(a, b)
    return a.x1 <= b.x2 and b.x1 <= a.x2 and a.y1 <= b.y2 and b.y1 <= a.y2
end

-- share of a coarse grid of ground squares that the server has loaded (0..1)
local function zoneLoaded(zn)
    local c = cell()
    if not c then return 0 end
    local n, got = 0, 0
    for x = zn.x1, zn.x2, 8 do
        for y = zn.y1, zn.y2, 8 do
            n = n + 1
            if c:getGridSquare(x, y, 0) then got = got + 1 end
        end
    end
    if n == 0 then return 0 end
    return got / n
end
CMS.zoneLoaded = zoneLoaded

-- never touch Project A-Life NPCs (zombies underneath) or players who turned
local function sparedZombie(z)
    local okR, rp = pcall(function() return z:isReanimatedPlayer() end)
    if okR and rp == true then return true end
    local okM, npc = pcall(function() return z:getModData().ProjectALifeOwned end)
    if okM and npc == true then return true end
    return false
end

local function inZone(zn, x, y)
    return x >= zn.x1 and x < zn.x2 + 1 and y >= zn.y1 and y < zn.y2 + 1
end

-- remove every loaded zombie inside the zone; returns how many
local function sweepZone(zn)
    local c = cell()
    if not c then return 0 end
    local hits = {}
    local list = CM.call(c, "getZombieList")
    local size = list and CM.call(list, "size") or nil
    if size then
        for i = 0, size - 1 do
            local z = list:get(i)
            local ok, x, y = pcall(function() return z:getX(), z:getY() end)
            if ok and inZone(zn, x, y) and not sparedZombie(z) then hits[#hits + 1] = z end
        end
    else
        -- no zombie list: walk the ground squares of the zone
        for x = zn.x1, zn.x2 do
            for y = zn.y1, zn.y2 do
                local sq = c:getGridSquare(x, y, 0)
                local mo = sq and CM.call(sq, "getMovingObjects")
                local n = mo and (CM.call(mo, "size") or 0) or 0
                for i = 0, n - 1 do
                    local z = mo:get(i)
                    if instanceof(z, "IsoZombie") and not sparedZombie(z) then hits[#hits + 1] = z end
                end
            end
        end
    end
    for _, z in ipairs(hits) do removeZombie(z) end
    return #hits
end
CMS.sweepZone = sweepZone

-- is a live run using (part of) this zone?
local function zoneBusy(zn)
    for s = 1, 3 do
        local c = S.cards[s]
        local run = c and c.run
        if run and run.phase == "live" and c.site and overlap(zoneOf(c.site, 20), zn) then return true end
    end
    return false
end

-- register (or refresh) the cleanup zone of a run's building; sweep it now when asked
function CMS.afterRun(card, run, now_)
    if not S or CM.sv("CleanupZombies") == false or not card.site then return 0 end
    local zn = zoneOf(card.site)
    local t = now()
    local mins = CM.int(CM.sv("CleanupMinutes"), 20, 0, 240)
    local found = nil
    for _, e in ipairs(S.sweeps) do
        if e.run == run.id then found = e end
    end
    if not found then
        found = { run = run.id, x1 = zn.x1, y1 = zn.y1, x2 = zn.x2, y2 = zn.y2, t0 = t, till = t + mins * 60, n = 0 }
        S.sweeps[#S.sweeps + 1] = found
        while #S.sweeps > 40 do table.remove(S.sweeps, 1) end
    end
    if not now_ then return 0 end
    local n = sweepZone(found)
    found.n = found.n + n
    if n > 0 then
        logLine("run " .. run.id .. " swept " .. n .. " zombies around the building")
        CM.log("run " .. run.id .. " swept " .. n .. " zombies around the building")
    end
    return n
end

local lastSweep = 0
local function sweepTick()
    local t = now()
    if t - lastSweep < SWEEP_EVERY then return end
    lastSweep = t
    if not S.sweeps or #S.sweeps == 0 then return end
    local keep = {}
    for _, zn in ipairs(S.sweeps) do
        local young = t - (zn.t0 or t) < SWEEP_MAX_AGE
        if young and not zoneBusy(zn) then
            local frac = zoneLoaded(zn)
            if frac > 0 then
                local n = sweepZone(zn)
                zn.n = (zn.n or 0) + n
                if n > 0 then
                    logLine("sweep " .. tostring(zn.run) .. ": " .. n .. " zombies")
                    CM.log("sweep " .. tostring(zn.run) .. " removed " .. n .. " zombies (loaded " .. math.floor(frac * 100) .. "%)")
                end
                if frac >= 0.5 and t >= (zn.till or 0) then zn.done = true end
            end
        end
        if young and not zn.done then keep[#keep + 1] = zn end
    end
    S.sweeps = keep
end
CMS.sweepTick = sweepTick

local function squareOk(sq, wantInside)
    if not sq then return false end
    local okS, solid = pcall(function() return sq:isSolid() or sq:isSolidTrans() end)
    if okS and solid then return false end
    local room = CM.call(sq, "getRoom")
    if wantInside == true and room == nil then return false end
    if wantInside == false and room ~= nil then return false end
    local free = CM.call(sq, "isFree", false)
    if free == false then return false end
    return true
end

local function farFromMembers(run, x, y, minD, arrivalMin)
    for k, m in pairs(run.members) do
        if m.st == "in" then
            local p = online[k]
            if p then
                local px, py = pos(p)
                local dx, dy = px - x, py - y
                if dx * dx + dy * dy < minD * minD then return false end
            end
        end
    end
    return true
end

local function pickSpawn(card, run, inside)
    local site = card.site
    local c = cell()
    if not c then return nil end
    local graceOn = now() - (run.lastJoin or run.t0) < CM.sv("Grace")
    for _ = 1, 10 do
        local x, y
        if inside then
            x = site.x1 + rand(site.x2 - site.x1 + 1)
            y = site.y1 + rand(site.y2 - site.y1 + 1)
        else
            local d = 4 + rand(13)
            local side = rand(4)
            if side == 0 then x = site.x1 - d; y = site.y1 - d + rand(site.y2 - site.y1 + 1 + d * 2)
            elseif side == 1 then x = site.x2 + d; y = site.y1 - d + rand(site.y2 - site.y1 + 1 + d * 2)
            elseif side == 2 then y = site.y1 - d; x = site.x1 - d + rand(site.x2 - site.x1 + 1 + d * 2)
            else y = site.y2 + d; x = site.x1 - d + rand(site.x2 - site.x1 + 1 + d * 2) end
        end
        local sq = c:getGridSquare(x, y, 0)
        if squareOk(sq, inside) and farFromMembers(run, x, y, 7) then
            local okA = true
            if graceOn then
                local dx, dy = x - site.ax, y - site.ay
                okA = dx * dx + dy * dy >= 144
            end
            if okA then return x, y end
        end
    end
    return nil
end

local function gangOutfit()
    local list = {}
    for _, o in ipairs(CM.split(CM.sv("GangOutfits"), ";")) do
        if not badOutfit[o] then list[#list + 1] = o end
    end
    if #list == 0 then return nil end
    return list[rand(#list) + 1]
end

local function zid(z)
    local ok, id = pcall(function() return z:getOnlineID() end)
    if ok and id ~= nil and id >= 0 then return id end
    return nil
end

local function spawnOne(card, run, gang)
    local inside = gang and rand(100) < 80 or rand(100) < 45
    local x, y = pickSpawn(card, run, inside)
    if not x then
        x, y = pickSpawn(card, run, not inside)
        if not x then return false end
    end
    local outfit = gang and gangOutfit() or nil
    local ok, list = pcall(addZombiesInOutfit, x, y, 0, 1, outfit, 50)
    if (not ok or not list or list:size() == 0) and outfit then
        badOutfit[outfit] = true
        logLine("outfit not usable, skipped: " .. tostring(outfit))
        ok, list = pcall(addZombiesInOutfit, x, y, 0, 1, nil, 50)
    end
    if not ok or not list then
        if not S.stats.spawnErr then S.stats.spawnErr = tostring(list); CM.log("zombie spawn failed: " .. tostring(list)) end
        return false
    end
    return CMS.track(run, list, gang) > 0
end

-- remember spawned zombies for counting and cleanup; returns how many
function CMS.track(run, list, gang)
    local r = rt(run)
    local n = 0
    pcall(function()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            r.zs[#r.zs + 1] = z
            pcall(function()
                local md = z:getModData()
                md.cmRun = run.id
                if gang then md.cmGang = 1 end
            end)
            if gang then
                r.objGang[z] = true
                local id = zid(z)
                if id then r.gang[id] = true end
            end
            n = n + 1
        end
    end)
    run.spawned = run.spawned + n
    if gang then run.gangSpawned = run.gangSpawned + n end
    return n
end

-- a burst of zombies 5-12 tiles from a point (a failed minigame was heard)
local function spawnNear(card, run, x, y, z, n)
    local c = cell()
    if not c or n <= 0 then return 0 end
    local got = 0
    for _ = 1, n do
        for _ = 1, 10 do
            local d = 5 + rand(8)
            local dx = rand(d * 2 + 1) - d
            local dy = d - math.abs(dx)
            if rand(2) == 0 then dy = -dy end
            local zz = z
            local sq = c:getGridSquare(x + dx, y + dy, zz)
            if not squareOk(sq, nil) then zz = 0; sq = c:getGridSquare(x + dx, y + dy, 0) end
            if squareOk(sq, nil) and farFromMembers(run, x + dx, y + dy, 3) then
                local ok, list = pcall(addZombiesInOutfit, x + dx, y + dy, zz, 1, nil, 50)
                if ok and list then got = got + CMS.track(run, list, false) end
                break
            end
        end
    end
    return got
end
CMS.spawnNear = spawnNear

-- a tracked or in-zone zombie died; dedupe by online id (or object) so server + client reports count once
local function countKill(card, run, z, killerKey, viaClient, cid)
    local r = rt(run)
    local id = cid or (z and zid(z))
    if id == nil and z == nil then return false end
    if (id ~= nil and r.dead[id]) or (z ~= nil and r.dead[z]) then return false end
    if id ~= nil then r.dead[id] = true end
    if z ~= nil then r.dead[z] = true end
    run.kills = run.kills + 1
    local isGang = (id and r.gang[id]) or (z and r.objGang[z])
    if not isGang and z then
        local ok, g = pcall(function() return z:getModData().cmGang end)
        isGang = ok and g == 1
    end
    if isGang then run.gang = run.gang + 1 end
    if killerKey and run.members[killerKey] then
        local m = run.members[killerKey]
        m.kills = (m.kills or 0) + 1
    end
    if viaClient then stat("killsClient") else stat("killsServer") end
    markRun(run)
    return true
end
CMS.countKill = countKill

local function pruneZombies(card, run)
    local r = rt(run)
    local keep = {}
    local aliveN, gangN = 0, 0
    for i = 1, #r.zs do
        local z = r.zs[i]
        local ok, dead, sq = pcall(function() return z:isDead(), z:getCurrentSquare() end)
        if ok and dead then
            countKill(card, run, z, nil, false)
            r.objGang[z] = nil
        elseif ok and sq ~= nil then
            keep[#keep + 1] = z
            aliveN = aliveN + 1
            if r.objGang[z] then gangN = gangN + 1 end
        else
            r.objGang[z] = nil
        end
    end
    r.zs = keep
    r.alive = aliveN
    r.gangAlive = gangN
end

local function spawnTick(card, run, dt)
    local tier = card.tier
    local nIn = memberCount(run, true)
    if nIn == 0 then return end
    if now() - run.t0 < 6 then return end
    local r = rt(run)
    pruneZombies(card, run)
    local f = 0.5 + 0.5 * math.min(nIn, card.cap) / math.max(1, card.cap)
    local maxAlive = math.floor(CM.num(CM.tierVal(tier, "Alive"), 35) * f + 0.5)
    local perMin = CM.num(CM.tierVal(tier, "Rate"), 40) * f
    if card.type == "survive" then
        perMin = perMin * (0.6 + 0.9 * math.min(1, run.held / math.max(1, card.goal)))
    end
    -- gang: the gang itself, plus a thinner horde around it
    if card.type == "gang" then
        local need = card.goal - run.gang - r.gangAlive
        r.gacc = math.min((r.gacc or 0) + perMin * 0.7 * dt / 60, 8)
        local n = 0
        while need > 0 and r.gacc >= 1 and r.alive < maxAlive and n < 6 do
            if not spawnOne(card, run, true) then break end
            r.gacc = r.gacc - 1; r.alive = r.alive + 1; r.gangAlive = r.gangAlive + 1
            need = need - 1; n = n + 1
        end
        perMin = perMin * 0.35
    end
    local capTotal = 2500
    if card.type == "kill" then
        -- stop feeding once enough are on the map to finish
        if run.kills + r.alive >= math.floor(card.goal * 1.15) + 5 then return end
        capTotal = card.goal * 2 + 20
    end
    if run.spawned >= capTotal then return end
    r.acc = math.min((r.acc or 0) + perMin * dt / 60, 8)
    local n = 0
    while r.acc >= 1 and r.alive < maxAlive and n < 6 do
        if not spawnOne(card, run, false) then break end
        r.acc = r.acc - 1; r.alive = r.alive + 1; n = n + 1
    end
end

-- noise at the building every 25 s: the horde comes to the players
local function pulseTick(card, run)
    local r = rt(run)
    local t = now()
    if t - (r.pulse or 0) < 25 then return end
    r.pulse = t
    local site = card.site
    local cx, cy = math.floor((site.x1 + site.x2) / 2), math.floor((site.y1 + site.y2) / 2)
    local rad = math.min(80, math.max(35, math.floor(math.sqrt(site.area)) + 25))
    pcall(function() getWorldSoundManager():addSound(nil, cx, cy, 0, rad, rad) end)
    for _, k in ipairs(CM.sortedKeys(run.members)) do
        local m = run.members[k]
        local p = online[k]
        if m.st == "in" and p then
            deliver(p, "pulse", { x = cx, y = cy, z = 0, r = rad })
            break
        end
    end
end

-- ===================================================================== supply caches (find)
local function containersIn(site)
    local c = cell()
    if not c then return nil end
    local list = {}
    local loaded = 0
    for z = 0, math.min(3, (site.floors or 1) - 1) do
        for x = site.x1, site.x2 do
            for y = site.y1, site.y2 do
                local sq = c:getGridSquare(x, y, z)
                if sq then
                    loaded = loaded + 1
                    local objs = CM.call(sq, "getObjects")
                    local n = objs and (CM.call(objs, "size") or 0) or 0
                    for i = 0, n - 1 do
                        local o = objs:get(i)
                        local cont = CM.call(o, "getContainer")
                        if cont then list[#list + 1] = { cont = cont, x = x, y = y, z = z } end
                    end
                end
            end
        end
    end
    return list, loaded
end

local function placeCaches(card, run)
    local r = rt(run)
    if r.placed then return true end
    local site = card.site
    local list, loaded = containersIn(site)
    if not list then return false end
    -- wait until most of the ground floor is loaded on the server
    if loaded < math.floor(site.area * 0.6) then return false end
    local want = card.goal
    local picked = {}
    local tries = 0
    while #picked < want and #list > 0 and tries < 400 do
        tries = tries + 1
        local i = rand(#list) + 1
        local e = list[i]
        local okD = true
        for j = 1, #picked do
            local dx, dy = picked[j].x - e.x, picked[j].y - e.y
            if dx * dx + dy * dy < 25 and tries < 300 then okD = false end
        end
        if okD then
            picked[#picked + 1] = e
            table.remove(list, i)
        end
    end
    -- not enough containers: floor of random rooms
    local c = cell()
    local floorTries = 0
    while #picked < want and floorTries < 200 do
        floorTries = floorTries + 1
        local x = site.x1 + rand(site.x2 - site.x1 + 1)
        local y = site.y1 + rand(site.y2 - site.y1 + 1)
        local sq = c and c:getGridSquare(x, y, 0)
        if squareOk(sq, true) then picked[#picked + 1] = { sq = sq, x = x, y = y, z = 0 } end
    end
    r.cacheObjs = {}
    for i = 1, #picked do
        local e = picked[i]
        local ok, item = pcall(instanceItem, CM.CACHE_TYPE)
        if ok and item then
            pcall(function()
                local md = item:getModData()
                md.cmRun = run.id
                md.cmIdx = i
            end)
            if e.cont then
                e.cont:AddItem(item)
                if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, e.cont, item) end
                r.cacheObjs[#r.cacheObjs + 1] = { cont = e.cont, item = item }
            elseif e.sq then
                pcall(function() e.sq:AddWorldInventoryItem(item, 0.5, 0.5, 0) end)
                pcall(function() item:getWorldItem():transmitCompleteItemToClients() end)
            end
            run.caches[#run.caches + 1] = { x = e.x, y = e.y, z = e.z, i = i }
        end
    end
    r.placed = true
    if #run.caches < want then
        -- the goal can never be more than what is actually hidden
        logLine("run " .. run.id .. " hid " .. #run.caches .. "/" .. want .. " caches")
        card.goal = math.max(1, #run.caches)
    end
    markRun(run)
    return true
end

local function foundCount(run)
    return CM.count(run.found)
end
CMS.foundCount = foundCount

-- ===================================================================== task targets (wire / safe / pipe / board / trap)
-- every object in the building (all floors, +1 tile east/south for the outer walls) that fits the task type
local function taskCandidates(site, typ, minLoaded)
    local c = cell()
    if not c then return nil, 0 end
    local good, spare = {}, {}
    -- cheap check first: most of the ground floor must be loaded before the objects are read
    local loaded = 0
    for x = site.x1, site.x2 do
        for y = site.y1, site.y2 do
            if c:getGridSquare(x, y, 0) then loaded = loaded + 1 end
        end
    end
    if minLoaded and loaded < minLoaded then return good, loaded, spare end
    for z = 0, math.min(3, (site.floors or 1) - 1) do
        for x = site.x1, site.x2 + 1 do
            for y = site.y1, site.y2 + 1 do
                local sq = c:getGridSquare(x, y, z)
                if sq then
                    local objs = CM.call(sq, "getObjects")
                    local n = objs and (CM.call(objs, "size") or 0) or 0
                    for i = 0, n - 1 do
                        local o = objs:get(i)
                        local okS, sc = pcall(CM.taskScore, typ, o)
                        if okS and sc and sc > 0 then
                            good[#good + 1] = { x = x, y = y, z = z, sc = sc, s = CM.spriteName(o), c = CM.objKind(o) }
                        else
                            local okF, fb = pcall(CM.taskFallback, typ, o)
                            if okF and fb and fb > 0 then
                                spare[#spare + 1] = { x = x, y = y, z = z, sc = fb, s = CM.spriteName(o), c = CM.objKind(o) }
                            end
                        end
                    end
                end
            end
        end
    end
    return good, loaded, spare
end
CMS.taskCandidates = taskCandidates

-- best score first (random among equals), spread out: 4 tiles apart, then 2, then anything on another square
local function pickTargets(list, want, picked)
    for i = 1, #list do list[i].r = rand(1000) end
    table.sort(list, function(a, b)
        if a.sc ~= b.sc then return a.sc > b.sc end
        return a.r < b.r
    end)
    for _, gap in ipairs({ 16, 4, 1 }) do
        for i = 1, #list do
            if #picked >= want then return picked end
            local e = list[i]
            local okD = not e.used
            for j = 1, #picked do
                local p = picked[j]
                local dx, dy = p.x - e.x, p.y - e.y
                if p.z == e.z and dx * dx + dy * dy < gap then okD = false end
            end
            if okD then e.used = true; picked[#picked + 1] = e end
        end
    end
    return picked
end
CMS.pickTargets = pickTargets

local function placeTasks(card, run)
    local r = rt(run)
    if r.placed then return true end
    local site = card.site
    local need = math.floor(site.area * 0.6)
    local good, loaded, spare = taskCandidates(site, card.type, need)
    if not good then return false end
    if loaded < need then return false end
    local want = card.goal
    local picked = pickTargets(good, want, {})
    if #picked < want then pickTargets(spare, want, picked) end
    run.tasks = {}
    for i = 1, #picked do
        local e = picked[i]
        run.tasks[i] = { x = e.x, y = e.y, z = e.z, i = i, s = e.s, c = e.c }
    end
    r.placed = true
    if #run.tasks < want then
        logLine("run " .. run.id .. " found " .. #run.tasks .. "/" .. want .. " " .. card.type .. " targets")
        card.goal = math.max(1, #run.tasks)
    end
    markRun(run)
    return true
end
CMS.placeTasks = placeTasks

local function taskOf(run, i)
    for _, t in ipairs(run.tasks or {}) do
        if t.i == i then return t end
    end
    return nil
end
CMS.taskOf = taskOf

-- ===================================================================== mole: cookie dolls pop up in the building
-- Dolls are runtime only (RT, never saved, not items): the server picks a free floor square inside a room,
-- each doll lives a few seconds, the members see them in their tracker and whack one from up to 2 tiles.
local function moleSquareOk(c, x, y, z, moles)
    local sq = c:getGridSquare(x, y, z)
    if not sq or CM.call(sq, "getRoom") == nil then return false end
    if CM.call(sq, "isFree", false) ~= true then return false end
    for _, o in pairs(moles) do
        local dx, dy = o.x - x, o.y - y
        if o.z == z and dx * dx + dy * dy < 9 then return false end
    end
    return true
end

local function moleTick(card, run)
    local r = rt(run)
    r.moles = r.moles or {}
    r.moleSeq = r.moleSeq or 0
    local t = nowMs()
    local n = 0
    for i, o in pairs(r.moles) do
        if t >= o.exp then r.moles[i] = nil; markRun(run) else n = n + 1 end
    end
    local c = cell()
    local site = card.site
    if not c or not site then return end
    local up = CM.gameVal("mole", "up", card.tier) or 3
    local life = CM.gameVal("mole", "life", card.tier) or 20
    local fake = CM.gameVal("mole", "fake", card.tier) or 0
    local floors = math.min(4, site.floors or 1)
    local tries = 0
    while n < up and tries < 40 do
        tries = tries + 1
        local x = site.x1 + rand(site.x2 - site.x1 + 1)
        local y = site.y1 + rand(site.y2 - site.y1 + 1)
        local z = rand(floors)
        if moleSquareOk(c, x, y, z, r.moles) then
            r.moleSeq = r.moleSeq + 1
            -- spread the end times a little so the dolls do not all vanish together
            r.moles[r.moleSeq] = { i = r.moleSeq, x = x, y = y, z = z, exp = t + (life * 1000) * (0.8 + rand(40) / 100),
                red = rand(100) < fake }
            n = n + 1
            markRun(run)
        end
    end
end
CMS.moleTick = moleTick

-- ===================================================================== progress / goals
local function progress(card, run)
    if not run then return 0, card.goal end
    if card.type == "kill" then return run.kills, card.goal end
    if card.type == "gang" then return run.gang, card.goal end
    if card.type == "find" then return foundCount(run), card.goal end
    if card.type == "survive" then return run.held, card.goal end
    if CM.isTask(card.type) then return CM.count(run.tdone), card.goal end
    if card.type == "mole" then return run.whacked or 0, card.goal end
    return 0, card.goal
end
CMS.progress = progress

local function memberTick(card, run, dt)
    local site = card.site
    local leaveD = CM.sv("LeaveDistance")
    local anyIn, anyNear = false, false
    for _, k in ipairs(CM.sortedKeys(run.members)) do
        local m = run.members[k]
        local p = online[k]
        if m.st == "in" or m.st == "off" then
            if not p then
                if m.st ~= "off" then m.st = "off"; m.offAt = now(); dirty.adm = true end
            elseif not alive(p) then
                m.st = "dead"; S.returns[k] = nil; markRun(run)
                logLine(m.n .. " died in run " .. run.id)
            else
                if m.st == "off" then m.st = "in"; markRun(run) end
                local x, y = pos(p)
                local d = CM.rectDist(site, x, y)
                m.d = math.floor(d)
                if d > leaveD and m.go then
                    resendGo(k, p, card, run, m, false)
                elseif d > leaveD then
                    m.out = (m.out or 0) + dt
                    if m.out >= CM.sv("LeaveSeconds") then
                        m.st = "left"
                        sendHome(k, m, "left", card)
                        toast(k, "left", {})
                        logLine(m.n .. " left the zone of run " .. run.id)
                        markRun(run)
                    elseif not m.warned then
                        m.warned = true
                        toast(k, "farwarn", { CM.sv("LeaveSeconds") })
                    end
                else
                    m.go = nil
                    m.out = 0; m.warned = nil
                    anyIn = true
                    if d <= 8 then anyNear = true end
                end
            end
        end
    end
    return anyIn, anyNear
end

local function runTick(card, run, dt)
    local t = now()
    if run.phase == "over" then
        if t >= (run.returnAt or t) then closeRun(card, run) end
        return
    end
    if run.phase ~= "live" then return end
    local anyIn, anyNear = memberTick(card, run, dt)
    if run.phase ~= "live" then return end
    if memberCount(run, false) == 0 then finishRun(card, run, "empty"); return end
    if not anyIn then
        run.emptyFor = (run.emptyFor or 0) + dt
        if run.emptyFor >= CM.sv("EmptyAbort") then finishRun(card, run, "empty"); return end
    else
        run.emptyFor = 0
    end
    if card.type == "survive" and anyNear then run.held = math.min(card.goal, run.held + dt) end
    if card.type == "find" then
        local r = rt(run)
        if not r.placed and now() - (r.placeTry or 0) >= 3 then
            r.placeTry = now()
            placeCaches(card, run)
        end
    elseif card.type == "mole" then
        if anyIn then moleTick(card, run) end
    elseif CM.isTask(card.type) then
        local r = rt(run)
        if not r.placed and now() - (r.placeTry or 0) >= 3 then
            r.placeTry = now()
            placeTasks(card, run)
            if r.placed and #run.tasks == 0 then finishRun(card, run, "notask"); return end
        end
    end
    if anyIn then
        spawnTick(card, run, dt)
        pulseTick(card, run)
    else
        pruneZombies(card, run)
    end
    local cur, goal = progress(card, run)
    if cur >= goal then
        finishRun(card, run, "ok")
    elseif t >= run.endAt then
        finishRun(card, run, "time")
    end
end

-- ===================================================================== day roll
local function rollDay(day)
    S.day = day
    S.claims = {}
    for slot = 1, 3 do
        local c = S.cards[slot]
        if c and c.run and c.run.phase ~= "closed" then
            c.stale = true
        else
            CMS.makeCard(slot)
        end
    end
    logLine("new mission day " .. CM.dayText(day))
end
CMS.rollDay = rollDay

local function cardTick(card, dt)
    if card.status == "live" and card.run then
        runTick(card, card.run, dt)
    elseif card.status == "cool" then
        if card.stale then
            CMS.makeCard(card.slot)
        elseif now() >= (card.coolUntil or 0) then
            card.status = "open"
            card.run = nil
            dirty.pub = true; dirty.adm = true
        end
    elseif card.status == "none" then
        -- retry the scan now and then (chunks / pins may have changed)
        if now() - (card.retryAt or 0) > 120 then
            card.retryAt = now()
            local c = CMS.makeCard(card.slot, card.type)
            c.retryAt = now()
        end
    end
end

-- ===================================================================== snapshots
-- ===================================================================== squads (wait until full, then warp together)
-- Memory only (never saved): a restart drops every queue. A squad holds `size` seats of one card; the rest of
-- the card stays open for solo players and other squads. Full -> 10 s countdown -> every member is accepted.
CM.SQUAD_SIZES = { 2, 3, 4, 6 }
local SQ = {}              -- sid -> { id, slot, card, size, lead, list = { k... }, names = { k = n }, t0, inv = { k = t }, cdAt, warned }
local sqOf = {}            -- ukey -> sid
local sqSeq = 0
local SQ_LIFE = 20 * 60
local SQ_COUNT = 10
local SQ_INVITE = 60
local SQ_OFFLINE = 120

local function sqToast(sq, kind, a, except)
    for _, k in ipairs(sq.list) do
        if k ~= except then toast(k, kind, a) end
    end
end

local function sqDirty(sq)
    for _, k in ipairs(sq.list) do dirty.me[k] = true end
    dirty.pub = true
end

-- seats held by squads on a card (minus the asker's own squad when it is the one launching)
local function sqSeats(slot, exceptSid)
    local n = 0
    for sid, sq in pairs(SQ) do
        if sq.slot == slot and sid ~= exceptSid then n = n + sq.size end
    end
    return n
end
CMS.sqSeats = sqSeats

local function sqDrop(sid, kind)
    local sq = SQ[sid]
    if not sq then return end
    SQ[sid] = nil
    for _, k in ipairs(sq.list) do
        sqOf[k] = nil
        dirty.me[k] = true
        if kind then toast(k, kind, {}) end
    end
    dirty.pub = true
end
CMS.sqDrop = sqDrop
function CMS.inSquad(k) return sqOf[k] ~= nil end

local function sqRemove(sq, k, kind)
    for i = #sq.list, 1, -1 do
        if sq.list[i] == k then table.remove(sq.list, i) end
    end
    sqOf[k] = nil
    dirty.me[k] = true
    local n = sq.names[k] or k
    sq.names[k] = nil
    sq.cdAt = nil
    if #sq.list == 0 then sqDrop(sq.id); return end
    if sq.lead == k then
        sq.lead = sq.list[1]
        toast(sq.lead, "sqlead", {})
    end
    sqToast(sq, kind or "sqleft", { n, sq.size - #sq.list })
    sqDirty(sq)
end

-- free seats on the card for one more squad of this size
local function cardRoom(card, size)
    if not card or (card.status ~= "open" and card.status ~= "live") then return false end
    local used = sqSeats(card.slot)
    if card.status == "live" and card.run then used = used + memberCount(card.run, false) end
    return used + size <= card.cap
end

local function sqAdd(sq, k, p)
    sq.list[#sq.list + 1] = k
    sq.names[k] = nameOf(p)
    sq.inv[k] = nil
    sqOf[k] = sq.id
    sqToast(sq, "sqjoin", { nameOf(p), sq.size - #sq.list }, k)
    toastPlayer(p, "sqin", { sq.names[sq.lead] or "?", sq.size - #sq.list })
    sqDirty(sq)
end

-- why this player can not be in a squad right now (nil = fine)
local function sqBlock(k, p)
    if not alive(p) then return "dead" end
    if runOf(k) then return "busy" end
    if CMS.inDod and CMS.inDod(k) then return "dodbusy" end
    if sqOf[k] then return "sqbusy" end
    return nil
end

-- the countdown: everyone online, alive, on foot; any problem stops it until it is fixed
local function sqReady(sq)
    local bad = nil
    for _, k in ipairs(sq.list) do
        local p = online[k]
        if not p or not alive(p) or inVehicle(p) or runOf(k) then bad = k; break end
    end
    return bad
end

local function sqLaunch(sq)
    local card = S.cards[sq.slot]
    local list = CM.copy(sq.list)
    sqDrop(sq.id)
    for _, k in ipairs(list) do
        local p = online[k]
        if p then
            local ok, err = pcall(CMS.H.accept, p, { slot = sq.slot })
            if not ok then CM.log("squad accept failed: " .. tostring(err)) end
        end
    end
    logLine("squad of " .. #list .. " launched on slot " .. sq.slot .. (card and card.run and (" run " .. card.run.id) or ""))
    stat("squads")
end

local function squadTick()
    local t = now()
    for sid, sq in pairs(SQ) do
        local card = S.cards[sq.slot]
        if not card or card.id ~= sq.card or (card.status ~= "open" and card.status ~= "live")
            or (card.run and card.run.phase ~= "live" and card.status == "live") then
            sqDrop(sid, "sqgone")
        elseif t - sq.t0 >= SQ_LIFE then
            sqDrop(sid, "sqexpire")
        else
            for _, k in ipairs(CM.copy(sq.list)) do
                if online[k] then sq.off = sq.off or {}; sq.off[k] = nil
                else
                    sq.off = sq.off or {}
                    sq.off[k] = sq.off[k] or t
                    if t - sq.off[k] >= SQ_OFFLINE then sqRemove(sq, k) end
                end
            end
            for k, at in pairs(sq.inv) do
                if t - at > SQ_INVITE then sq.inv[k] = nil end
            end
            if SQ[sid] and #sq.list >= sq.size then
                local bad = sqReady(sq)
                if bad then
                    if sq.cdAt then sqToast(sq, "sqhold", { sq.names[bad] or bad }) end
                    sq.cdAt = nil
                    if not sq.warned or t - sq.warned >= 10 then
                        sq.warned = t
                        toast(bad, "sqfix", {})
                    end
                elseif not sq.cdAt then
                    sq.cdAt = t + SQ_COUNT
                    sqToast(sq, "sqcount", { SQ_COUNT })
                elseif t >= sq.cdAt then
                    sqLaunch(sq)
                end
            end
            if SQ[sid] then
                for _, k in ipairs(sq.list) do dirty.me[k] = true end
            end
        end
    end
end
CMS.squadTick = squadTick

-- what one player sees: the squad they are in (+ who can be invited when they lead it) and open invites
local function sqMine(k)
    local out = nil
    local sid = sqOf[k]
    local sq = sid and SQ[sid]
    if sq then
        local mem = {}
        for _, mk in ipairs(sq.list) do
            mem[#mem + 1] = { k = mk, n = sq.names[mk] or mk, lead = mk == sq.lead, off = online[mk] == nil }
        end
        out = { id = sq.id, slot = sq.slot, size = sq.size, lead = sq.lead == k, members = mem,
            left = math.max(0, SQ_LIFE - (now() - sq.t0)), cd = sq.cdAt and math.max(0, sq.cdAt - now()) or nil }
        if sq.lead == k and #sq.list < sq.size then
            local free = {}
            for ok, p in pairs(online) do
                if ok ~= k and not sqOf[ok] and not runOf(ok) and #free < 40 then
                    free[#free + 1] = { k = ok, n = nameOf(p), inv = sq.inv[ok] ~= nil }
                end
            end
            table.sort(free, function(a, b) return a.n < b.n end)
            out.free = free
        end
    end
    local inv = {}
    for isid, isq in pairs(SQ) do
        if isq.inv[k] then
            inv[#inv + 1] = { id = isid, slot = isq.slot, size = isq.size, n = #isq.list, by = isq.names[isq.lead] or "?" }
        end
    end
    return out, inv
end

-- squads shown on a card
local function sqPub(slot)
    local out = {}
    for sid, sq in pairs(SQ) do
        if sq.slot == slot then
            out[#out + 1] = { id = sid, by = sq.names[sq.lead] or "?", n = #sq.list, size = sq.size }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function cardPub(c)
    if not c then return nil end
    local o = {
        slot = c.slot, id = c.id, tier = c.tier, type = c.type, status = c.status,
        goal = c.goal, limit = c.limit, cap = c.cap, n = 0,
    }
    if c.site then
        o.town = c.site.town; o.kind = c.site.kind; o.area = c.site.area; o.floors = c.site.floors
        o.pinned = c.site.pinned
    end
    if c.status == "cool" then o.coolLeft = math.max(0, (c.coolUntil or 0) - now()) end
    local run = c.run
    if run and run.phase == "live" then
        o.n = memberCount(run, false)
        local cur = progress(c, run)
        o.prog = cur
        o.left = math.max(0, run.endAt - now())
    end
    if c.last then o.last = { res = c.last.res, t = c.last.t } end
    o.squads = sqPub(c.slot)
    o.seats = sqSeats(c.slot)
    return o
end

function CMS.pubSnapshot()
    local cards = {}
    for s = 1, 3 do cards[s] = cardPub(S.cards[s]) or { slot = s, status = "none" } end
    return { day = S.day, cards = cards, reset = math.max(0, CM.dayEnd(S.day) - now()), v = CM.VERSION }
end

function CMS.meSnapshot(k)
    local me = { claims = {}, pending = S.returns[k] ~= nil }
    for id in pairs(S.claims[k] or {}) do me.claims[#me.claims + 1] = id end
    me.sq, me.inv = sqMine(k)
    local card, run, m = runOf(k)
    if card and run then
        local cur, goal = progress(card, run)
        local mem = {}
        for _, mk in ipairs(CM.sortedKeys(run.members)) do
            local mm = run.members[mk]
            mem[#mem + 1] = { n = mm.n, st = mm.st, k = mm.kills or 0 }
        end
        local s = card.site
        me.run = {
            id = run.id, slot = card.slot, tier = card.tier, type = card.type, phase = run.phase,
            cur = cur, goal = goal, left = math.max(0, run.endAt - now()), res = run.result,
            zone = { x1 = s.x1, y1 = s.y1, x2 = s.x2, y2 = s.y2, ax = s.ax, ay = s.ay },
            town = s.town, kind = s.kind, members = mem, myKills = m.kills or 0, myFound = m.found or 0,
            out = math.floor(m.out or 0), backIn = run.returnAt and math.max(0, run.returnAt - now()) or nil,
            claimed = S.claims[k] and S.claims[k][card.id] == true or false,
            alive = RT[run.id] and RT[run.id].alive or 0,
        }
        if card.type == "find" then
            local cs = {}
            for _, c in ipairs(run.caches) do
                if not run.found[c.i] then cs[#cs + 1] = { x = c.x, y = c.y, z = c.z, i = c.i } end
            end
            me.run.caches = cs
        elseif CM.isTask(card.type) then
            local ts = {}
            local t = now()
            for _, tk in ipairs(run.tasks or {}) do
                if not run.tdone[tk.i] then
                    local e = { x = tk.x, y = tk.y, z = tk.z, i = tk.i, s = tk.s, c = tk.c }
                    local L = run.tlock[tk.i]
                    if L and t - L.t0 < CM.TASK_LOCK then
                        if L.k == k then e.mine = true else e.b = L.n end
                    end
                    ts[#ts + 1] = e
                end
            end
            me.run.tasks = ts
            me.run.myTasks = m.tasks or 0
        elseif card.type == "mole" then
            local ms = {}
            local r = RT[run.id]
            local t = nowMs()
            for _, o in pairs((r and r.moles) or {}) do
                ms[#ms + 1] = { i = o.i, x = o.x, y = o.y, z = o.z, red = o.red, left = math.max(0, math.floor((o.exp - t) / 1000)) }
            end
            me.run.moles = ms
            me.run.myTasks = m.tasks or 0
        end
    end
    return me
end

local function admSnapshot()
    local cards = {}
    for s = 1, 3 do
        local c = S.cards[s]
        local o = cardPub(c) or { slot = s, status = "none" }
        if c and c.site then
            o.site = CM.copy(c.site)
        end
        if c and c.run then
            local run = c.run
            local r = RT[run.id]
            o.run = {
                id = run.id, phase = run.phase, kills = run.kills, gang = run.gang, held = run.held,
                spawned = run.spawned, alive = r and r.alive or 0, found = foundCount(run), caches = #run.caches,
                tdone = CM.count(run.tdone or {}), tasks = #(run.tasks or {}), whacked = run.whacked or 0,
                members = {},
            }
            for _, k in ipairs(CM.sortedKeys(run.members)) do
                local m = run.members[k]
                o.run.members[#o.run.members + 1] = { n = m.n, st = m.st, k = m.kills or 0, d = m.d or 0 }
            end
        end
        cards[s] = o
    end
    local bans = {}
    for _, bid in ipairs(CM.sortedKeys(S.bans)) do
        local b = S.bans[bid]
        bans[#bans + 1] = { bid = bid, town = b.town, kind = b.kind, by = b.by, t = b.t }
    end
    local pins = {}
    for _, bid in ipairs(CM.sortedKeys(S.pins)) do
        local pn = S.pins[bid]
        pins[#pins + 1] = { bid = bid, town = pn.site and pn.site.town, kind = pn.site and pn.site.kind,
            area = pn.site and pn.site.area, by = pn.by }
    end
    local pools = {}
    for _, name in ipairs(CM.POOLS) do
        local l = {}
        for i, e in ipairs(poolList(name)) do l[#l + 1] = { i = i, t = e.t, w = e.w, n = e.n, ok = itemExists(e.t) } end
        pools[name] = l
    end
    local runs = {}
    for _, h in ipairs(S.hist) do runs[#runs + 1] = h end
    return {
        cards = cards, bans = bans, pins = pins, pools = pools, log = S.log, hist = runs,
        stats = CM.copy(S.stats), day = S.day, reset = math.max(0, CM.dayEnd(S.day) - now()),
        build = CM.BUILD, edited = S.pools ~= nil,
    }
end
CMS.admSnapshot = admSnapshot

local function flush(force)
    local ms = nowMs()
    if not force and ms - lastFlush < 1000 then return end
    lastFlush = ms
    if dirty.pub then
        dirty.pub = false
        deliverAll("pub", CMS.pubSnapshot())
    end
    -- live members get their tracker every flush (timer, progress)
    for s = 1, 3 do
        local c = S.cards[s]
        if c and c.run and c.run.phase ~= "closed" then
            for k in pairs(c.run.members) do dirty.me[k] = true end
        end
    end
    for k in pairs(dirty.me) do
        local p = online[k]
        if p then deliver(p, "me", CMS.meSnapshot(k)) end
    end
    dirty.me = {}
    if dirty.adm then
        dirty.adm = false
        local snap = nil
        for k in pairs(admWatch) do
            local p = online[k]
            if p and CMS.isAdmin(p) then
                snap = snap or admSnapshot()
                deliver(p, "adm", snap)
            else
                admWatch[k] = nil
            end
        end
    end
end
CMS.flush = flush

-- ===================================================================== player commands
local H = {}
local A = {}
CMS.H = H
CMS.A = A

local function tellAdmin(p, force)
    local k = keyOf(p)
    local v = CMS.isAdmin(p)
    if force or admTold[k] ~= v then
        admTold[k] = v
        deliver(p, "isadm", { v = v })
    end
end

local takeCaches, sweepCaches -- defined with the cache handlers below

function H.hello(p, args)
    local k = keyOf(p)
    online[k] = p
    deliver(p, "hi", { v = CM.VERSION })
    deliver(p, "pub", CMS.pubSnapshot())
    deliver(p, "me", CMS.meSnapshot(k))
    pcall(sweepCaches, p)
    if S.shield[k] and now() >= (S.shield[k].till or 0) then pcall(shieldOff, k, p) end
    tellAdmin(p, true)
    -- the run ended while this player was away, or the warp home never landed: go home
    local card, run, m = runOf(k)
    if S.returns[k] and not card then pcall(checkReturn, k, p, true) end
    -- dropped out during the mission warp itself: send it again
    if card and run and m and m.go and run.phase == "live" then pcall(resendGo, k, p, card, run, m, true) end
    if S.pend[k] and #S.pend[k] > 0 and alive(p) then
        local list = S.pend[k]
        S.pend[k] = nil
        for _, it in ipairs(list) do giveTo(p, it.t, it.n) end
        deliver(p, "result", { res = "late", rw = list })
    end
end

function H.accept(p, args)
    local k = keyOf(p)
    local slot = CM.int(args.slot, 0, 0, 3)
    local card = S.cards[slot]
    if not card or not card.site then toastPlayer(p, "nocard"); return end
    if not alive(p) then return end
    if runOf(k) then toastPlayer(p, "busy"); return end
    if sqOf[k] then toastPlayer(p, "sqbusy"); return end
    if CMS.inDod and CMS.inDod(k) then toastPlayer(p, "dodbusy"); return end
    local okV, veh = pcall(function() return p:getVehicle() end)
    if okV and veh then toastPlayer(p, "vehicle"); return end
    if card.status == "cool" then toastPlayer(p, "cool", { CM.clock((card.coolUntil or 0) - now()) }); return end
    if card.status ~= "open" and card.status ~= "live" then toastPlayer(p, "nocard"); return end
    local run = card.run
    if card.status == "live" and run then
        if run.phase ~= "live" then toastPlayer(p, "cool", { "0:00" }); return end
        if memberCount(run, false) + sqSeats(slot) >= card.cap then toastPlayer(p, "full"); return end
        local cur, goal = progress(card, run)
        if goal > 0 and cur * 100 >= goal * CM.sv("LateJoinMax") then toastPlayer(p, "almost"); return end
        if run.endAt - now() < 60 then toastPlayer(p, "almost"); return end
        local old = run.members[k]
        if old and (old.st == "left" or old.st == "dead") then toastPlayer(p, "rejoin"); return end
    else
        if sqSeats(slot) >= card.cap then toastPlayer(p, "full"); return end
        run = newRun(card)
    end
    local x, y, z = pos(p)
    run.members[k] = { n = nameOf(p), at = now(), home = { x = x, y = y, z = z }, st = "in", kills = 0, found = 0,
        go = { t = now(), n = 0 } }
    run.lastJoin = now()
    S.returns[k] = nil
    sendGo(k, p, card)
    logLine(nameOf(p) .. " joined run " .. run.id .. " (slot " .. slot .. ")")
    for mk, m in pairs(run.members) do
        if mk ~= k and m.st == "in" then toast(mk, "joined", { nameOf(p) }) end
    end
    markRun(run)
end

-- give up: straight home, no reward
function H.leave(p, args)
    local k = keyOf(p)
    local card, run, m = runOf(k)
    if not card then return end
    if run.phase == "live" then
        m.st = "left"
        sendHome(k, m, "left", card)
        logLine(m.n .. " gave up run " .. run.id)
    else
        sendHome(k, m, "home", card)
        m.st = "home"
    end
    markRun(run)
end

-- the client landed after a mission warp: god mode on the server-side player for WarpShield seconds
function H.shield(p, args)
    local k = keyOf(p)
    local g = shieldGrant[k]
    shieldGrant[k] = nil
    if not g or now() - g.t > 240 or not alive(p) then return end
    local sec = CM.int(CM.sv("WarpShield"), 10, 0, 60)
    if sec <= 0 then return end
    local e = S.shield[k]
    if not e then
        local okG, was = pcall(function() return p:isGodMod() end)
        e = { prev = okG and was == true }
        S.shield[k] = e
    end
    e.till = now() + sec + 1
    pcall(function() p:setGodMod(true) end)
    stat("shields")
end

-- after the end: go home now instead of waiting for the countdown
function H.home(p, args)
    local k = keyOf(p)
    local card, run, m = runOf(k)
    if not card or run.phase ~= "over" then return end
    sendHome(k, m, "home", card)
    m.st = "home"
    markRun(run)
end

-- client fallback kill report (server OnZombieDead may not see every death in MP)
function H.kill(p, args)
    local k = keyOf(p)
    local card, run, m = runOf(k)
    if not card or run.phase ~= "live" or m.st ~= "in" then return end
    local id = CM.int(args.id, -1)
    if not id or id < 0 then return end
    local x, y = CM.num(args.x, 0), CM.num(args.y, 0)
    -- the horde is spawned up to 16 tiles outside the building
    if not CM.inRect(card.site, x, y, 20) then return end
    local px, py = pos(p)
    -- guns reach far: only reject reports clearly from somewhere else
    if math.abs(px - x) > 90 or math.abs(py - y) > 90 then return end
    local m2 = run.members[k]
    m2.ckills = (m2.ckills or 0) + 1
    if m2.ckills > 400 then return end
    countKill(card, run, nil, k, true, id)
end

-- a supply cache is in this player's inventory
-- remove supply caches from a player's inventory on the server; keep(md) decides which, max = how many
takeCaches = function(p, match, max)
    local inv = p and p:getInventory()
    local list = inv and CM.call(inv, "getAllTypeRecurse", CM.CACHE_TYPE)
    if not list then return 0 end
    local picked = {}
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        local md = CM.call(it, "getModData") or {}
        if match(md) and (not max or #picked < max) then picked[#picked + 1] = it end
    end
    for _, it in ipairs(picked) do
        local cont = CM.call(it, "getContainer")
        if cont then
            pcall(function() cont:Remove(it) end)
            if isServer() and sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, cont, it) end
        end
    end
    return #picked
end

-- caches that do not belong to a live "find" run of this player are worthless: take them away
sweepCaches = function(p)
    local card, run = runOf(keyOf(p))
    local live = card and card.type == "find" and run and run.phase == "live" and run.id or nil
    local n = takeCaches(p, function(md) return live == nil or md.cmRun ~= live end)
    if n > 0 then logLine(tostring(keyOf(p)) .. ": removed " .. n .. " old supply cache(s)") end
    return n
end
CMS.sweepCaches = sweepCaches

function H.dropcache(p, args)
    sweepCaches(p)
end

function H.found(p, args)
    local k = keyOf(p)
    local card, run, m = runOf(k)
    if not card or card.type ~= "find" or run.phase ~= "live" then return end
    local idx = CM.int(args.i, 0)
    local valid = false
    if args.run == run.id and idx and idx > 0 then
        for _, c in ipairs(run.caches) do if c.i == idx then valid = true end end
    end
    if not valid then
        -- modData did not reach the client: take the next unfound one
        idx = nil
        for _, c in ipairs(run.caches) do
            if not run.found[c.i] and idx == nil then idx = c.i end
        end
    end
    -- the server owns inventories in B42 MP: take the cache out here (never on the client)
    pcall(takeCaches, p, function(md)
        return (md.cmRun == nil or md.cmRun == args.run) and (CM.int(args.i, 0) == 0 or md.cmIdx == CM.int(args.i, 0))
    end, 1)
    if not idx or run.found[idx] then
        deliver(p, "rmcache", { i = CM.int(args.i, 0), run = args.run })
        return
    end
    run.found[idx] = k
    m.found = (m.found or 0) + 1
    deliver(p, "rmcache", { i = CM.int(args.i, 0), run = args.run })
    for mk, mm in pairs(run.members) do
        if mm.st == "in" then toast(mk, "found", { m.n, foundCount(run), card.goal }) end
    end
    markRun(run)
end

-- ===================================================================== task targets: start / done / fail
local function taskReach(p, t)
    local x, y, z = pos(p)
    local dx, dy = x - t.x, y - t.y
    return dx * dx + dy * dy <= CM.TASK_REACH * CM.TASK_REACH and math.abs(z - t.z) <= 1
end

local function taskRun(p)
    local k = keyOf(p)
    local card, run, m = runOf(k)
    if not card or not CM.isTask(card.type) or run.phase ~= "live" or m.st ~= "in" then return nil end
    return k, card, run, m
end

-- a player reached a target and wants its minigame: lock it to them and hand out a token
function H.tstart(p, args)
    local k, card, run, m = taskRun(p)
    if not k then return end
    local i = CM.int(args.i, 0)
    local t = taskOf(run, i)
    if not t or args.run ~= run.id then deliver(p, "tno", { i = i }); return end
    if run.tdone[i] then toastPlayer(p, "tgone"); deliver(p, "tno", { i = i }); return end
    if not taskReach(p, t) then toastPlayer(p, "tfar"); deliver(p, "tno", { i = i }); return end
    local L = run.tlock[i]
    if L and L.k ~= k and now() - L.t0 < CM.TASK_LOCK then
        toastPlayer(p, "tbusy", { L.n }); deliver(p, "tno", { i = i }); return
    end
    local tok = 100000 + rand(900000)
    run.tlock[i] = { k = k, n = m.n, t0 = now(), tok = tok }
    deliver(p, "tgo", { i = i, tok = tok, type = card.type, tier = card.tier, run = run.id, x = t.x, y = t.y, z = t.z })
    markRun(run)
end

-- minigame won and the work action finished
function H.tdone(p, args)
    local k, card, run, m = taskRun(p)
    if not k then return end
    local i = CM.int(args.i, 0)
    local t = taskOf(run, i)
    local L = run.tlock[i]
    local tok = CM.int(args.tok, -1)
    if not t or run.tdone[i] then toastPlayer(p, "tgone"); deliver(p, "tno", { i = i }); return end
    if not L or L.k ~= k or L.tok ~= tok then toastPlayer(p, "tlost"); deliver(p, "tno", { i = i }); return end
    if now() - L.t0 < CM.TASK_MIN then deliver(p, "tno", { i = i }); return end
    if not taskReach(p, t) then toastPlayer(p, "tfar"); deliver(p, "tno", { i = i }); return end
    run.tdone[i] = k
    run.tlock[i] = nil
    m.tasks = (m.tasks or 0) + 1
    stat("tasksDone")
    local rad = CM.gameVal(card.type, "noise") or 10
    pcall(function() getWorldSoundManager():addSound(nil, t.x, t.y, t.z, rad, rad) end)
    local cur = CM.count(run.tdone)
    for mk, mm in pairs(run.members) do
        if mm.st == "in" then toast(mk, "tdone", { m.n, cur, card.goal }) end
    end
    deliver(p, "tok", { i = i })
    markRun(run)
end

-- minigame lost (noise + a burst of zombies) or given up (no penalty)
function H.tfail(p, args)
    local k, card, run, m = taskRun(p)
    if not k then return end
    local i = CM.int(args.i, 0)
    local t = taskOf(run, i)
    local L = run.tlock[i]
    if not t or not L or L.k ~= k or L.tok ~= CM.int(args.tok, -1) then return end
    run.tlock[i] = nil
    local why = CM.str(args.why, 12)
    if why ~= "cancel" and why ~= "far" then
        stat("tasksFailed")
        local rad = CM.gameVal(card.type, "failNoise") or 30
        pcall(function() getWorldSoundManager():addSound(nil, t.x, t.y, t.z, rad, rad) end)
        local n = math.floor(CM.int(CM.sv("FailZombies"), 4, 0, 30) * (CM.gameVal(card.type, "spawn") or 1) * (0.75 + 0.25 * card.tier) + 0.5)
        local got = spawnNear(card, run, t.x, t.y, t.z, n)
        for mk, mm in pairs(run.members) do
            if mm.st == "in" then toast(mk, "tfail", { m.n }) end
        end
        logLine(m.n .. " failed a " .. card.type .. " minigame (" .. why .. "), +" .. got .. " zombies")
    end
    markRun(run)
end

-- whack a cookie doll; a red one is a decoy: noise and zombies
function H.whack(p, args)
    local k = keyOf(p)
    local card, run, m = runOf(k)
    if not card or card.type ~= "mole" or run.phase ~= "live" or m.st ~= "in" then return end
    local r = rt(run)
    local i = CM.int(args.i, 0)
    local o = r.moles and r.moles[i]
    if not o or nowMs() >= o.exp then toastPlayer(p, "mgone"); return end
    -- 2 tiles from the middle of the doll's square, measured on the real (not rounded) position
    local okP, fx, fy, fz = pcall(function() return p:getX(), p:getY(), p:getZ() end)
    if not okP then return end
    local dx, dy = fx - (o.x + 0.5), fy - (o.y + 0.5)
    local reach = (CM.gameVal("mole", "reach") or 2) + (CM.gameVal("mole", "slack") or 0.5)
    if math.floor(fz) ~= o.z or dx * dx + dy * dy > reach * reach then toastPlayer(p, "tfar"); return end
    r.moles[i] = nil
    if o.red then
        stat("molesFake")
        local rad = CM.gameVal("mole", "failNoise") or 30
        pcall(function() getWorldSoundManager():addSound(nil, o.x, o.y, o.z, rad, rad) end)
        local n = math.floor(CM.int(CM.sv("FailZombies"), 4, 0, 30) * (CM.gameVal("mole", "spawn") or 1) * (0.75 + 0.25 * card.tier) + 0.5)
        local got = spawnNear(card, run, o.x, o.y, o.z, n)
        for mk, mm in pairs(run.members) do
            if mm.st == "in" then toast(mk, "mfake", { m.n }) end
        end
        logLine(m.n .. " hit a decoy doll, +" .. got .. " zombies")
    else
        run.whacked = (run.whacked or 0) + 1
        m.tasks = (m.tasks or 0) + 1
        stat("molesHit")
        local rad = CM.gameVal("mole", "noise") or 6
        pcall(function() getWorldSoundManager():addSound(nil, o.x, o.y, o.z, rad, rad) end)
        toastPlayer(p, "mhit", { run.whacked, card.goal })
    end
    deliver(p, "mpop", { i = i, red = o.red == true })
    markRun(run)
end

-- ===================================================================== squad commands
local function sizeOk(n)
    for _, s in ipairs(CM.SQUAD_SIZES) do if s == n then return true end end
    return false
end

function H.sqNew(p, args)
    local k = keyOf(p)
    local slot = CM.int(args.slot, 0, 0, 3)
    local card = S.cards[slot]
    local size = CM.int(args.size, 0)
    if not card or not card.site then toastPlayer(p, "nocard"); return end
    local why = sqBlock(k, p)
    if why then toastPlayer(p, why == "dead" and "nocard" or why); return end
    if not sizeOk(size) or size > card.cap then toastPlayer(p, "sqsize", { card.cap }); return end
    if not cardRoom(card, size) then toastPlayer(p, "full"); return end
    sqSeq = sqSeq + 1
    local sid = "q" .. tostring(sqSeq)
    local sq = { id = sid, slot = slot, card = card.id, size = size, lead = k, list = { k }, names = { [k] = nameOf(p) },
        t0 = now(), inv = {} }
    SQ[sid] = sq
    sqOf[k] = sid
    toastPlayer(p, "sqmade", { size - 1 })
    sqDirty(sq)
end

function H.sqJoin(p, args)
    local k = keyOf(p)
    local sq = SQ[tostring(args.id or "")]
    if not sq then toastPlayer(p, "sqgone"); return end
    local why = sqBlock(k, p)
    if why then toastPlayer(p, why == "dead" and "nocard" or why); return end
    if #sq.list >= sq.size then toastPlayer(p, "full"); return end
    sqAdd(sq, k, p)
end

function H.sqInvite(p, args)
    local k = keyOf(p)
    local sq = SQ[sqOf[k] or ""]
    if not sq or sq.lead ~= k then return end
    local who = CM.ukey(args.who)
    local q = online[who]
    if not q or who == k then return end
    if sqOf[who] or runOf(who) then toastPlayer(p, "sqtaken", { nameOf(q) }); return end
    if sq.inv[who] then return end
    if #sq.list >= sq.size then toastPlayer(p, "full"); return end
    sq.inv[who] = now()
    local card = S.cards[sq.slot]
    deliver(q, "sqinv", { id = sq.id, by = nameOf(p), slot = sq.slot, size = sq.size, n = #sq.list,
        type = card and card.type, tier = card and card.tier })
    toastPlayer(p, "sqsent", { nameOf(q) })
    sqDirty(sq)
end

function H.sqAnswer(p, args)
    local k = keyOf(p)
    local sq = SQ[tostring(args.id or "")]
    if not sq or not sq.inv[k] then toastPlayer(p, "sqgone"); return end
    if args.yes ~= true then
        sq.inv[k] = nil
        toast(sq.lead, "sqno", { nameOf(p) })
        sqDirty(sq)
        return
    end
    local why = sqBlock(k, p)
    if why then toastPlayer(p, why == "dead" and "nocard" or why); return end
    if #sq.list >= sq.size then toastPlayer(p, "full"); return end
    sqAdd(sq, k, p)
end

function H.sqKick(p, args)
    local k = keyOf(p)
    local sq = SQ[sqOf[k] or ""]
    local who = CM.ukey(args.who)
    if not sq or sq.lead ~= k or who == k or sqOf[who] ~= sq.id then return end
    toast(who, "sqkicked", {})
    sqRemove(sq, who)
end

function H.sqLeave(p, args)
    local k = keyOf(p)
    local sq = SQ[sqOf[k] or ""]
    if not sq then return end
    sqRemove(sq, k)
end

function H.sqDisband(p, args)
    local k = keyOf(p)
    local sq = SQ[sqOf[k] or ""]
    if not sq or sq.lead ~= k then return end
    sqDrop(sq.id, "sqdisband")
end

function H.dead(p, args)
    local k = keyOf(p)
    local card, run, m = runOf(k)
    S.returns[k] = nil
    if card and m then
        m.st = "dead"
        markRun(run)
    end
end

-- ===================================================================== admin commands
function A.admOpen(p, args)
    admWatch[keyOf(p)] = true
    dirty.adm = true
end

function A.admClose(p, args)
    admWatch[keyOf(p)] = nil
end

function A.reroll(p, args)
    local slot = CM.int(args.slot, 0, 0, 3)
    local typ = args.type
    if typ and not CM.TYPE_OPT[typ] then typ = nil end
    for s = 1, 3 do
        if slot == 0 or slot == s then
            local c = S.cards[s]
            if c then abortRun(c, "abort") end
            CMS.makeCard(s, typ)
        end
    end
    logLine("reroll " .. (slot == 0 and "all" or tostring(slot)) .. (typ and (" as " .. typ) or ""))
end

function A.forceEnd(p, args)
    local c = S.cards[CM.int(args.slot, 0, 0, 3)]
    if not c or not c.run then return end
    local run = c.run
    if run.phase == "live" then finishRun(c, run, args.ok and "ok" or "abort") end
    logLine("force end slot " .. c.slot .. (args.ok and " (success)" or ""))
end

function A.sweepCard(p, args)
    local c = S.cards[CM.int(args.slot, 0, 0, 3)]
    if not c or not c.site then return end
    if c.run and c.run.phase == "live" then return end
    local n = sweepZone(zoneOf(c.site))
    logLine("swept slot " .. c.slot .. ": " .. n .. " zombies")
    toastPlayer(p, "swept", { n })
end

function A.sweepHere(p, args)
    local x, y = pos(p)
    local r = CM.int(args.r, 60, 5, 200)
    local zn = { x1 = math.floor(x) - r, y1 = math.floor(y) - r, x2 = math.floor(x) + r, y2 = math.floor(y) + r }
    if zoneBusy(zn) then toastPlayer(p, "sweepbusy"); return end
    local n = sweepZone(zn)
    logLine("swept " .. r .. " tiles around " .. nameOf(p) .. ": " .. n .. " zombies")
    toastPlayer(p, "swept", { n })
end

function A.openNow(p, args)
    local c = S.cards[CM.int(args.slot, 0, 0, 3)]
    if c and c.status == "cool" then c.coolUntil = 0 end
end

local function banSite(site, by)
    if not site then return end
    S.bans[site.bid] = { town = site.town, kind = site.kind, by = by, t = now(), x = site.x1, y = site.y1 }
    S.pins[site.bid] = nil
    logLine("ban " .. site.bid .. " " .. tostring(site.town) .. " " .. tostring(site.kind))
end

function A.banCard(p, args)
    local c = S.cards[CM.int(args.slot, 0, 0, 3)]
    if not c or not c.site then return end
    banSite(c.site, nameOf(p))
    abortRun(c, "abort")
    CMS.makeCard(c.slot, c.type)
end

local function siteHere(p)
    local mg = metaGrid()
    local x, y = pos(p)
    local def = mg and CM.call(mg, "getBuildingAt", x, y)
    return def and CMS.siteFromDef(def) or nil
end
CMS.siteHere = siteHere

function A.banHere(p, args)
    local site = siteHere(p)
    if not site then toastPlayer(p, "nobuilding"); return end
    banSite(site, nameOf(p))
    toastPlayer(p, "banned", { site.bid })
end

function A.unban(p, args)
    local bid = CM.str(args.bid, 40)
    if S.bans[bid] then S.bans[bid] = nil; logLine("unban " .. bid) end
end

function A.pinHere(p, args)
    local site = siteHere(p)
    if not site then toastPlayer(p, "nobuilding"); return end
    local tiers = nil
    if type(args.tiers) == "table" then
        tiers = {}
        for _, t in ipairs(args.tiers) do
            local n = CM.int(t, 0, 0, 3)
            if n and n > 0 then tiers[n] = true end
        end
        if not CM.any(tiers) then tiers = nil end
    end
    S.pins[site.bid] = { site = site, tiers = tiers, by = nameOf(p), t = now() }
    S.bans[site.bid] = nil
    logLine("pin " .. site.bid .. " " .. tostring(site.town) .. " " .. tostring(site.kind) .. " area " .. site.area)
    toastPlayer(p, "pinned", { site.bid })
end

function A.unpin(p, args)
    local bid = CM.str(args.bid, 40)
    if S.pins[bid] then S.pins[bid] = nil; logLine("unpin " .. bid) end
end

function A.poolAdd(p, args)
    local name = CM.str(args.pool, 20)
    local ft = CM.str(args.t, 120)
    if not CM.DEFAULT_POOLS[name] then return end
    if not itemExists(ft) then toastPlayer(p, "noitem", { ft }); return end
    ensurePools()
    local list = S.pools[name]
    for _, e in ipairs(list) do
        if e.t == ft then
            e.w = CM.int(args.w, e.w or 10, 1, 1000); e.n = CM.int(args.n, e.n or 1, 1, 50)
            logLine("pool " .. name .. " update " .. ft)
            return
        end
    end
    list[#list + 1] = { t = ft, w = CM.int(args.w, 10, 1, 1000), n = CM.int(args.n, 1, 1, 50) }
    logLine("pool " .. name .. " + " .. ft)
end

function A.poolDel(p, args)
    local name = CM.str(args.pool, 20)
    if not CM.DEFAULT_POOLS[name] then return end
    ensurePools()
    local list = S.pools[name]
    local i = CM.int(args.i, 0)
    if list[i] and list[i].t == args.t then
        logLine("pool " .. name .. " - " .. tostring(list[i].t))
        table.remove(list, i)
    end
end

function A.poolSet(p, args)
    local name = CM.str(args.pool, 20)
    if not CM.DEFAULT_POOLS[name] then return end
    ensurePools()
    local e = S.pools[name][CM.int(args.i, 0)]
    if e and e.t == args.t then
        if args.w then e.w = CM.int(args.w, e.w, 1, 1000) end
        if args.n then e.n = CM.int(args.n, e.n, 1, 50) end
    end
end

function A.poolReset(p, args)
    local name = CM.str(args.pool, 20)
    if not CM.DEFAULT_POOLS[name] then return end
    ensurePools()
    if name == "legend" then S.pools.legend = CMS.legendPool()
    else S.pools[name] = CM.copy(CM.DEFAULT_POOLS[name]) end
    logLine("pool " .. name .. " reset (" .. #S.pools[name] .. ")")
end

-- debug: roll a reward list into the admin's own hands
function A.testReward(p, args)
    local tier = CM.int(args.tier, 1, 1, 3)
    local list = CMS.rollRewards(tier)
    for _, it in ipairs(list) do giveTo(p, it.t, it.n) end
    deliver(p, "result", { res = "test", rw = list })
end

-- ===================================================================== dispatch
local function allow(p)
    local k = keyOf(p)
    local t = now()
    local r = rate[k]
    if not r or r.t ~= t then r = { t = t, n = 0 }; rate[k] = r end
    r.n = r.n + 1
    return r.n <= 30
end

local function onClientCommand(module, command, p, args)
    if module ~= MOD or not p then return end
    if not S then return end
    if args ~= nil and type(args) ~= "table" then return end
    args = args or {}
    if not allow(p) then return end
    rebuildOnline()
    local h = H[command]
    local admin = false
    if not h then
        h = A[command]
        admin = true
    end
    if not h then return end
    if admin and not CMS.isAdmin(p) then
        CM.log("rejected admin command " .. tostring(command) .. " from " .. nameOf(p))
        tellAdmin(p, true)
        return
    end
    if admin and command ~= "admOpen" and command ~= "admClose" then logActor = nameOf(p) end
    local ok, err = pcall(h, p, args)
    logActor = nil
    if not ok then CM.log("command " .. tostring(command) .. " failed: " .. tostring(err)) end
    if admin then dirty.adm = true end
    flush(true)
end
CMS.onClientCommand = onClientCommand

-- ===================================================================== ticking
local function slowTick()
    for _, p in pairs(online) do tellAdmin(p, false) end
end

local function onTick()
    if not S then return end
    local ms = nowMs()
    if lastTick == 0 then lastTick = ms end
    local dtMs = ms - lastTick
    if dtMs < 1000 then return end
    lastTick = ms
    local dt = math.min(dtMs / 1000, 15)
    rebuildOnline()
    local day = CM.dayKey(now())
    if day ~= S.day then rollDay(day) end
    for s = 1, 3 do
        local c = S.cards[s]
        if not c then c = CMS.makeCard(s) end
        local ok, err = pcall(cardTick, c, dt)
        if not ok then CM.log("card " .. s .. " tick error: " .. tostring(err)) end
    end
    if ms - lastSlow >= 5000 then
        lastSlow = ms
        pcall(slowTick)
    end
    local okS, errS = pcall(sweepTick)
    if not okS then CM.log("sweep error: " .. tostring(errS)) end
    local okH, errH = pcall(shieldTick)
    if not okH then CM.log("shield error: " .. tostring(errH)) end
    local okR, errR = pcall(returnTick)
    if not okR then CM.log("return error: " .. tostring(errR)) end
    local okQ, errQ = pcall(squadTick)
    if not okQ then CM.log("squad error: " .. tostring(errQ)) end
    flush(false)
end
CMS.onTick = onTick

local function onBoot()
    S = ModData.getOrCreate(MOD)
    defaults(S)
    -- a restart kills every runtime zombie list: close live runs, players go home on login
    for s = 1, 3 do
        local c = S.cards[s]
        if c and c.run and c.run.phase ~= "closed" then
            local run = c.run
            for k, m in pairs(run.members) do
                if (m.st == "in" or m.st == "off") and m.home then
                    S.returns[k] = { x = m.home.x, y = m.home.y, z = m.home.z, t = now(), why = "back", site = siteRect(c) }
                    m.st = "home"
                end
            end
            run.phase = "closed"
            if not run.result then run.result = "restart" end
            c.status = "cool"
            c.coolUntil = 0
            pcall(CMS.afterRun, c, run, false)
            logLine("run " .. run.id .. " closed by restart")
        end
    end
    -- before 1.1.4 a return was dropped as soon as it was sent: anyone from a recent run who is still
    -- standing at that mission gets sent home on login (checkReturn drops it if they are not there)
    if not S.rescued114 then
        S.rescued114 = true
        local n = 0
        for s = 1, 3 do
            local c = S.cards[s]
            local run = c and c.run
            if run and c.site and now() - (run.endT or run.lastJoin or 0) < 2 * 86400 then
                for k, m in pairs(run.members) do
                    if (m.st == "left" or m.st == "home") and m.home and not S.returns[k] then
                        S.returns[k] = { x = m.home.x, y = m.home.y, z = m.home.z, t = now(), why = "back",
                            site = siteRect(c), rescue = 1 }
                        n = n + 1
                    end
                end
            end
        end
        if n > 0 then logLine("checking " .. n .. " player(s) from recent runs for a lost warp home") end
    end
    if not S.pools then
        ensurePools()
        S.pools.legend = CMS.legendPool()
        CM.log("legend pool: " .. #S.pools.legend .. " items")
    end
    -- a pool added in a newer version (cure) starts from its defaults
    for _, n in ipairs(CM.POOLS) do
        if S.pools[n] == nil then S.pools[n] = CM.copy(CM.DEFAULT_POOLS[n] or {}) end
    end
    CM.log("server ready " .. CM.BUILD .. " day=" .. tostring(S.day) .. " grid=" .. tostring(metaGrid() ~= nil))
end
CMS.onBoot = onBoot

Events.OnInitGlobalModData.Add(function()
    local ok, err = pcall(onBoot)
    if not ok then CM.log("boot error: " .. tostring(err)) end
end)

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(function()
    local ok, err = pcall(onTick)
    if not ok then CM.log("tick error: " .. tostring(err)) end
end)

if Events.OnWeaponHitCharacter then Events.OnWeaponHitCharacter.Add(function(attacker, target, weapon, damage)
    if not S or not attacker or not target then return end
    if not instanceof(attacker, "IsoPlayer") or not instanceof(target, "IsoZombie") then return end
    hitCache[target] = { p = attacker, t = nowMs() }
end) end

local function onZombieDead(zombie)
    if not S or not zombie then return end
    local c0 = hitCache[zombie]
    hitCache[zombie] = nil
    local okP, x, y = pcall(function() return zombie:getX(), zombie:getY() end)
    if not okP then return end
    local okM, tag, npc = pcall(function()
        local md = zombie:getModData()
        return md.cmRun, md.ProjectALifeOwned
    end)
    if not okM then tag = nil end
    -- Project A-Life NPC bodies are zombies underneath: never count them (their own docs ask for this);
    -- Die or Die counts its own soldiers
    if npc == true then
        if CMS.dodNpcDead then pcall(CMS.dodNpcDead, zombie, c0 and c0.p or nil) end
        return
    end
    for s = 1, 3 do
        local card = S.cards[s]
        local run = card and card.run
        -- ours (spawned for this run, wherever it died) or any zombie dying at the building
        if run and run.phase == "live" and card.site and (tag == run.id or CM.inRect(card.site, x, y, 8)) then
            local killer = c0 and c0.p
            if not killer then
                local ok, a = pcall(function() return zombie:getAttackedBy() end)
                if ok and a and instanceof(a, "IsoPlayer") then killer = a end
            end
            local kk = killer and keyOf(killer) or nil
            countKill(card, run, zombie, kk, false)
            return
        end
    end
end
CMS.onZombieDead = onZombieDead
Events.OnZombieDead.Add(function(z)
    local ok, err = pcall(onZombieDead, z)
    if not ok then CM.log("zombie dead error: " .. tostring(err)) end
end)

if Events.OnCharacterDeath then Events.OnCharacterDeath.Add(function(ch)
    if not S or not ch then return end
    if instanceof(ch, "IsoPlayer") then
        pcall(function()
            local k = keyOf(ch)
            S.returns[k] = nil
            local card, run, m = runOf(k)
            if card and m then m.st = "dead"; markRun(run) end
        end)
    end
end) end

return CMS
