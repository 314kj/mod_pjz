-- Cookie Quest - server authority (dedicated server, host, or single player)
if isClient() and not isServer() then return end

require "CQ_Shared"
require "CQ_XP"

CQS = CQS or {}
local MOD = CQ.MOD
local S = nil              -- persistent state (global ModData "CookieQuest")
local online = {}          -- ukey -> IsoPlayer (refreshed every tick)
local seenSession = {}     -- ukey -> true once greeted this session
local admWatch = {}        -- ukey -> true while admin panel is open
local srvxpTold = {}       -- ukey -> true after "srvxp" sent
local dirty = { pub = false, adm = false, me = {} }
local lastFlush, lastTick, lastSlow, lastBuffSig = 0, 0, 0, ""
local lastMe, lastAdm = {}, 0
local hitCache = {}
local lastDeath = {}
local rate = {}

-- ===================================================================== state
local function defaults(s)
    s.v = s.v or 1
    s.cfg = s.cfg or {}
    if s.cfg.utc == nil then s.cfg.utc = 7 end
    if s.cfg.showZones == nil then s.cfg.showZones = true end
    s.seq = s.seq or 100
    s.missions = s.missions or {}
    s.events = s.events or {}
    s.inst = s.inst or {}
    s.users = s.users or {}
    s.buffs = s.buffs or {}
    s.buffs.sched = s.buffs.sched or {}
    s.radio = s.radio or {}
    s.globalM = s.globalM or {}
    s.takers = s.takers or {}
    s.log = s.log or {}
end

function CQS.state() return S end
function CQS.online() return online end

local function now() return CQ.now() end
local function off() return S.cfg.utc end
local function newId(prefix) S.seq = S.seq + 1; return prefix .. tostring(S.seq) end

local logActor = nil      -- admin name while an admin command runs
local function logLine(text)
    if logActor then text = "[" .. logActor .. "] " .. tostring(text) end
    table.insert(S.log, 1, { t = now(), s = tostring(text) })
    while #S.log > 80 do table.remove(S.log) end
end

local function markPub() dirty.pub = true; dirty.adm = true end
local function markMe(k) if k and k ~= "" then dirty.me[k] = true end; dirty.adm = true end
local function markInst(inst)
    if inst and inst.members then for k in pairs(inst.members) do markMe(k) end end
    dirty.adm = true
end

-- ===================================================================== players
local function nameOf(p)
    local ok, n = pcall(function() return p:getUsername() end)
    if ok and n and n ~= "" then return tostring(n) end
    local ok2, d = pcall(function() return p:getDescriptor() end)
    if ok2 and d then
        local f = d:getForename() or "Player"
        return tostring(f)
    end
    return "Player"
end
CQS.nameOf = nameOf

local function keyOf(p) return CQ.ukey(nameOf(p)) end
CQS.keyOf = keyOf

local function rebuildOnline()
    online = {}
    if CQ.isSP() then
        local p = getSpecificPlayer(0)
        if p then online[keyOf(p)] = p end
        return
    end
    local list = getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p then online[keyOf(p)] = p end
        end
    end
    if isClient() then
        local p = getSpecificPlayer(0)
        if p then online[keyOf(p)] = p end
    end
end

local function alive(p)
    if not p then return false end
    local ok, dead = pcall(function() return p:isDead() end)
    return ok and not dead
end

local function user(k, name)
    if not k or k == "" then return nil end
    local u = S.users[k]
    if not u then
        u = { name = name or k, inst = {}, items = {}, done = {} }
        S.users[k] = u
    end
    if name and name ~= "" then u.name = name end
    u.inst = u.inst or {}
    u.items = u.items or {}
    u.done = u.done or {}
    return u
end
CQS.user = user

-- staff = the vanilla "admin tool" right of the player's B42 role (same check DCS uses).
-- B42 getAccessLevel() returns the role name ("user", "priority", ...), so it is only a
-- fallback when the role API is missing, and only explicit staff names count.
local STAFF_LEVELS = { admin = true, moderator = true, overseer = true, gm = true }
function CQS.isAdmin(p)
    if CQ.isSP() then return true end
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
        if isClient() and p == getSpecificPlayer(0) then
            triggerEvent("OnServerCommand", MOD, cmd, CQ.copy(args))
        end
    else
        triggerEvent("OnServerCommand", MOD, cmd, CQ.copy(args))
    end
end
CQS.send = deliver

local function deliverAll(cmd, args)
    if isServer() then
        sendServerCommand(MOD, cmd, args)
        if isClient() then triggerEvent("OnServerCommand", MOD, cmd, CQ.copy(args)) end
    else
        triggerEvent("OnServerCommand", MOD, cmd, CQ.copy(args))
    end
end

local function toast(k, kind, a)
    local p = online[k]
    if p then deliver(p, "toast", { k = kind, a = a or {} }) end
end

local function toastAll(kind, a)
    deliverAll("toast", { k = kind, a = a or {} })
end

-- ===================================================================== items
local function itemExists(ft)
    local sm = getScriptManager()
    local ok, it = pcall(function() return sm:FindItem(ft) end)
    return ok and it ~= nil
end
CQS.itemExists = itemExists

function CQS.giveItems(p, list)
    local inv = p:getInventory()
    local given, missing = 0, {}
    for i = 1, #list do
        local it = list[i]
        if itemExists(it.t) then
            for _ = 1, it.n do
                local ok, item = pcall(instanceItem, it.t)
                if ok and item then
                    inv:AddItem(item)
                    if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
                    given = given + 1
                end
            end
        else
            missing[#missing + 1] = it.t
        end
    end
    if #missing > 0 then CQ.log("unknown item(s) skipped: " .. table.concat(missing, ",")) end
    return given
end

local function markGot(eid, k)
    local ev = eid and S.events[eid]
    if ev and ev.parts and ev.parts[k] then ev.parts[k].got = true; markMe(k) end
end

local function queueItems(k, list, why, title, eid)
    if type(list) ~= "table" or #list == 0 then return end
    local u = user(k)
    local p = online[k]
    if p and alive(p) then
        local n = CQS.giveItems(p, list)
        toast(k, "items", { why, tostring(n), title or "" })
        markGot(eid, k)
    else
        u.items[#u.items + 1] = { list = CQ.copy(list), why = why, title = title or "", eid = eid }
    end
end

local function flushPendingItems(k)
    local u = S.users[k]
    local p = online[k]
    if not u or not p or not alive(p) or #u.items == 0 then return end
    local pending = u.items
    u.items = {}
    for i = 1, #pending do
        local e = pending[i]
        local n = CQS.giveItems(p, e.list)
        toast(k, "items", { e.why, tostring(n), e.title or "" })
        markGot(e.eid, k)
    end
end

-- ===================================================================== events (participation helpers)
local function liveEvent()
    for _, id in ipairs(CQ.sortedKeys(S.events)) do
        local e = S.events[id]
        if e.status == "live" then return e end
    end
    return nil
end

local function roleOf(ev, roleId)
    if not ev or not roleId then return nil end
    for i = 1, #ev.roles do if ev.roles[i].id == roleId then return ev.roles[i] end end
    return nil
end

local function creditCp(inst, k)
    local ev = inst.eid and S.events[inst.eid]
    if ev and ev.parts and ev.parts[k] then
        ev.parts[k].cp = (ev.parts[k].cp or 0) + 1
    end
end

-- ===================================================================== instances
local function stepOf(inst) return inst.steps and inst.steps[inst.step] end

local function onlineMembers(inst)
    local out = {}
    for k in pairs(inst.members) do
        local p = online[k]
        if p and alive(p) then out[k] = p end
    end
    return out
end

local function keysOf(t)
    local o = {}
    for k in pairs(t) do o[k] = true end
    return o
end

local function onStepEnter(inst)
    inst.cnt = 0
    inst.hold = 0
    inst.armed = false
    inst.cntBy = {}
    inst.stepAt = now()
    inst.holdBy = {}
end

local completeMission

local function passStep(inst, credit, byAdmin)
    if inst.status ~= "active" then return end
    local st = stepOf(inst)
    if not st then return end
    if not credit or not CQ.any(credit) then credit = keysOf(onlineMembers(inst)) end
    if not CQ.any(credit) and inst.owner then credit = { [inst.owner] = true } end
    inst.contrib = inst.contrib or {}
    for k in pairs(credit) do
        inst.contrib[k] = (inst.contrib[k] or 0) + 1
        creditCp(inst, k)
        if S.events[inst.eid or ""] then markMe(k) end
    end
    local total = #inst.steps
    local label = st.label or ""
    for k in pairs(inst.members) do
        toast(k, "cp", { inst.title or "", label, tostring(inst.step), tostring(total), st.t })
    end
    inst.step = inst.step + 1
    if inst.step > total then
        completeMission(inst)
    else
        onStepEnter(inst)
    end
    markInst(inst)
    if byAdmin then logLine("admin pass " .. tostring(inst.id) .. " step " .. tostring(inst.step - 1)) end
end
CQS.passStep = passStep

completeMission = function(inst)
    inst.status = "done"
    inst.finished = now()
    inst.step = #inst.steps
    local m = S.missions[inst.mid]
    local rewards = (m and m.rewards) or inst.rewards or {}
    local rewardTo = (m and m.rewardTo) or "contrib"
    local who = {}
    if not inst.team then
        if inst.owner then who[inst.owner] = true end
    elseif rewardTo == "members" then
        who = keysOf(inst.members)
    else
        for k, c in pairs(inst.contrib or {}) do if c > 0 then who[k] = true end end
        if not CQ.any(who) then who = keysOf(onlineMembers(inst)) end
    end
    for k in pairs(who) do
        local u = user(k)
        u.done[inst.mid] = (u.done[inst.mid] or 0) + 1
        if #rewards > 0 then queueItems(k, rewards, "reward", inst.title) end
    end
    for k in pairs(inst.members) do
        toast(k, "mdone", { inst.title or "", (m and m.rewardText) or inst.rewardText or "" })
    end
    local g = S.globalM[inst.mid]
    if g and g.iid == inst.id then S.globalM[inst.mid] = nil end
    logLine("mission done " .. tostring(inst.mid) .. " (" .. tostring(inst.id) .. ")")
    markInst(inst)
end

local function hasActive(k, mid)
    local u = S.users[k]
    if not u then return nil end
    for iid in pairs(u.inst) do
        local inst = S.inst[iid]
        if inst and inst.mid == mid and inst.status == "active" then return inst end
    end
    return nil
end

local function createInst(m, members, team, eid, owner, via)
    local iid = newId("i")
    local inst = {
        id = iid, mid = m.id, title = m.title, eid = eid, team = team == true, owner = owner,
        members = members or {}, contrib = {}, steps = CQ.copy(m.steps), step = 1,
        status = "active", started = now(), via = via or "",
        rewardText = m.rewardText,
    }
    if m.timeLimit and m.timeLimit > 0 then inst.deadline = now() + m.timeLimit * 60 end
    onStepEnter(inst)
    S.inst[iid] = inst
    for k, name in pairs(inst.members) do
        local u = user(k, type(name) == "string" and name or nil)
        u.inst[iid] = true
        toast(k, "mnew", { m.title })
    end
    markInst(inst)
    return inst
end
CQS.createInst = createInst

local function addMember(inst, k, name)
    if inst.members[k] then return end
    inst.members[k] = name or k
    local u = user(k, name)
    u.inst[inst.id] = true
    toast(k, "mnew", { inst.title or "" })
    markInst(inst)
end

-- stop an unfinished mission for everyone in it (mission / event deleted, admin cancel)
local function cancelInst(inst)
    if not inst or inst.status ~= "active" then return end
    inst.status = "cancelled"
    inst.finished = now()
    for k in pairs(inst.members) do toast(k, "mcancel", { inst.title or "" }) end
    local g = S.globalM[inst.mid]
    if g and g.iid == inst.id then S.globalM[inst.mid] = nil end
    markInst(inst)
end
CQS.cancelInst = cancelInst

local function removeInst(iid)
    local inst = S.inst[iid]
    if not inst then return end
    for k in pairs(inst.members) do
        local u = S.users[k]
        if u then u.inst[iid] = nil end
        markMe(k)
    end
    S.inst[iid] = nil
    dirty.adm = true
end

-- event membership context for a player taking a mission now
local function eventContext(k)
    local ev = liveEvent()
    if ev and ev.parts and ev.parts[k] then return ev end
    return nil
end

local function canTake(k, m)
    if hasActive(k, m.id) then return false, "already" end
    local u = S.users[k]
    if u and u.done[m.id] and not m.repeatable then return false, "done" end
    if m.limit and m.limit > 0 and (S.takers[m.id] or 0) >= m.limit then return false, "full" end
    return true
end

-- activate a mission for "everyone"
local function activateEveryone(m, by)
    local ev = by and eventContext(by) or liveEvent()
    local members = {}
    if ev and ev.parts and by and ev.parts[by] then
        for k, p in pairs(ev.parts) do members[k] = p.name or k end
    else
        ev = nil
        for k, p in pairs(online) do members[k] = nameOf(p) end
    end
    if m.team then
        local g = S.globalM[m.id]
        local inst = g and S.inst[g.iid]
        if inst and inst.status == "active" then
            for k, n in pairs(members) do addMember(inst, k, n) end
            return inst
        end
        inst = createInst(m, members, true, ev and ev.id or nil, nil, "everyone")
        S.globalM[m.id] = { iid = inst.id, since = now(), eid = ev and ev.id or nil }
        return inst
    end
    for k, n in pairs(members) do
        if not hasActive(k, m.id) then createInst(m, { [k] = n }, false, ev and ev.id or nil, k, "everyone") end
    end
    S.globalM[m.id] = { since = now(), solo = true, eid = ev and ev.id or nil }
    return true
end

function CQS.accept(p, mid, via)
    local k = keyOf(p)
    local m = S.missions[mid]
    if not m then toast(k, "err", { "nomission" }); return false end
    if m.assign == "everyone" and via == "sheet" then
        if S.globalM[mid] then
            local g = S.globalM[mid]
            local inst = g.iid and S.inst[g.iid]
            if inst and inst.status == "active" then
                addMember(inst, k, nameOf(p))
                return true
            end
            if g.solo and not hasActive(k, mid) then
                local ok, why = canTake(k, m)
                if not ok then toast(k, "err", { why }); return false end
                createInst(m, { [k] = nameOf(p) }, false, g.eid, k, "everyone")
                return true
            end
        end
        activateEveryone(m, k)
        toastAll("mglobal", { m.title, nameOf(p) })
        logLine(nameOf(p) .. " activated " .. tostring(mid) .. " for everyone")
        return true
    end
    if via == "board" and m.assign ~= "board" then toast(k, "err", { "nomission" }); return false end
    local ok, why = canTake(k, m)
    if not ok then toast(k, "err", { why }); return false end
    local ev = eventContext(k)
    S.takers[mid] = (S.takers[mid] or 0) + 1
    createInst(m, { [k] = nameOf(p) }, false, ev and ev.id or nil, k, via)
    logLine(nameOf(p) .. " took " .. tostring(mid) .. " via " .. tostring(via))
    markPub()
    return true
end

-- ===================================================================== checkpoint scanning
local function cellSquare(x, y, z)
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(x, y, z)
end

local function eachSquare(zn, fn)
    for x = zn.x1, zn.x2 do
        for y = zn.y1, zn.y2 do
            local sq = cellSquare(x, y, zn.z or 0)
            if sq then fn(sq) end
        end
    end
end

local function containersOf(obj)
    local out = {}
    local ok, n = pcall(function() return obj:getContainerCount() end)
    if ok and type(n) == "number" and n > 0 then
        for i = 0, n - 1 do
            local okc, c = pcall(function() return obj:getContainerByIndex(i) end)
            if okc and c then out[#out + 1] = c end
        end
    else
        local okc, c = pcall(function() return obj:getContainer() end)
        if okc and c then out[#out + 1] = c end
    end
    return out
end

function CQS.countInZone(zn, ft)
    local total = 0
    eachSquare(zn, function(sq)
        local wobs = sq:getWorldObjects()
        if wobs then
            for i = 0, wobs:size() - 1 do
                local o = wobs:get(i)
                local okI, it = pcall(function() return o:getItem() end)
                if okI and it then
                    if it:getFullType() == ft then total = total + 1 end
                    local okC, inv = pcall(function() return it:getInventory() end)
                    if okC and inv and inv.getCountTypeRecurse then
                        total = total + (inv:getCountTypeRecurse(ft) or 0)
                    end
                end
            end
        end
        local objs = sq:getObjects()
        if objs then
            for i = 0, objs:size() - 1 do
                local cs = containersOf(objs:get(i))
                for c = 1, #cs do total = total + (cs[c]:getCountTypeRecurse(ft) or 0) end
            end
        end
    end)
    return total
end

-- best effort removal of delivered items (experimental, server side)
function CQS.consumeInZone(zn, ft, n)
    local left = n
    eachSquare(zn, function(sq)
        if left <= 0 then return end
        local wobs = sq:getWorldObjects()
        if wobs then
            for i = wobs:size() - 1, 0, -1 do
                if left <= 0 then break end
                local o = wobs:get(i)
                local okI, it = pcall(function() return o:getItem() end)
                if okI and it and it:getFullType() == ft then
                    pcall(function() sq:transmitRemoveItemFromSquare(o) end)
                    pcall(function() sq:removeWorldObject(o) end)
                    left = left - 1
                end
            end
        end
        local objs = sq:getObjects()
        if objs then
            for i = 0, objs:size() - 1 do
                local cs = containersOf(objs:get(i))
                for c = 1, #cs do
                    if left <= 0 then break end
                    local list = cs[c]:getAllTypeRecurse(ft)
                    if list then
                        for j = list:size() - 1, 0, -1 do
                            if left <= 0 then break end
                            local item = list:get(j)
                            local cont = item:getContainer() or cs[c]
                            pcall(function()
                                cont:DoRemoveItem(item)
                                if isServer() and sendRemoveItemFromContainer then sendRemoveItemFromContainer(cont, item) end
                            end)
                            left = left - 1
                        end
                    end
                end
            end
        end
    end)
    return n - left
end

local function pX(p) return p:getX() end
local function pY(p) return p:getY() end
local function pZ(p) return p:getZ() end

local function checkInst(inst, dt)
    local st = stepOf(inst)
    if not st then completeMission(inst); return end
    if inst.deadline and now() >= inst.deadline then
        inst.status = "failed"
        inst.finished = now()
        for k in pairs(inst.members) do toast(k, "mfail", { inst.title or "" }) end
        markInst(inst)
        return
    end
    local t = st.t
    if t == "reach" then
        if not st.zone then return end
        local mem = onlineMembers(inst)
        local inside, nIn = {}, 0
        for k, p in pairs(mem) do
            if CQ.inZone(st.zone, pX(p), pY(p), pZ(p)) then inside[k] = true; nIn = nIn + 1 end
        end
        if st.all and inst.team then
            -- staff (admins who joined a team by opening it for everyone) never hold the team back
            local need, missing = 0, {}
            local anyPlayer = false
            for k, p in pairs(mem) do if not CQS.isAdmin(p) then anyPlayer = true end end
            for k, p in pairs(mem) do
                if not anyPlayer or not CQS.isAdmin(p) then
                    need = need + 1
                    if not inside[k] then missing[#missing + 1] = nameOf(p) end
                end
            end
            table.sort(missing)
            local sig = table.concat(missing, ",")
            if sig ~= (inst.waitSig or "") then inst.waitSig = sig; inst.wait = missing; markInst(inst) end
            if need > 0 and #missing == 0 then inst.wait = nil; inst.waitSig = nil; passStep(inst, inside) end
        elseif nIn > 0 then
            passStep(inst, inside)
        end
    elseif t == "hold" then
        if not st.zone then return end
        local any = false
        for k, p in pairs(onlineMembers(inst)) do
            if CQ.inZone(st.zone, pX(p), pY(p), pZ(p)) then any = true; inst.holdBy[k] = true end
        end
        if any then
            local before = math.floor(inst.hold or 0)
            inst.hold = (inst.hold or 0) + dt
            if math.floor(inst.hold / 5) ~= math.floor(before / 5) then markInst(inst) end
        end
        -- also passes when the admin shortened the time after everyone already left the zone
        if (inst.hold or 0) >= (st.sec or 60) then
            passStep(inst, (inst.holdBy and CQ.any(inst.holdBy)) and inst.holdBy or nil)
        end
    elseif t == "deliver" then
        if not st.zone or not st.item or st.item == "" then return end
        local near = {}
        local anyNear = false
        for k, p in pairs(onlineMembers(inst)) do
            if CQ.distToZone(st.zone, pX(p), pY(p)) <= 25 then
                anyNear = true
                if CQ.inZone(st.zone, pX(p), pY(p), pZ(p)) or CQ.distToZone(st.zone, pX(p), pY(p)) <= 3 then near[k] = true end
            end
        end
        if not anyNear then return end
        if now() - (inst.scanAt or 0) < 2 then return end
        inst.scanAt = now()
        local scanZone = st.zone
        if CQ.zoneW(scanZone) > 51 or CQ.zoneH(scanZone) > 51 then
            local cx, cy = CQ.zoneCenter(scanZone)
            scanZone = CQ.makeZone(cx, cy, scanZone.z, math.min(51, CQ.zoneW(scanZone)), math.min(51, CQ.zoneH(scanZone)))
        end
        local c = CQS.countInZone(scanZone, st.item)
        if c ~= inst.cnt then inst.cnt = c; markInst(inst) end
        if c >= (st.n or 1) then
            if st.consume then CQS.consumeInZone(scanZone, st.item, st.n or 1) end
            passStep(inst, near)
        end
    elseif t == "rescue" then
        if not st.zone or not st.target or st.target == "" then return end
        local tp = online[CQ.ukey(st.target)]
        if tp and alive(tp) then
            local inZ = CQ.inZone(st.zone, pX(tp), pY(tp), pZ(tp))
            if inZ then
                if not inst.armed then inst.armed = true; markInst(inst) end
            elseif inst.armed then
                local credit = {}
                for k, p in pairs(onlineMembers(inst)) do
                    if CQ.dist(pX(p), pY(p), pX(tp), pY(tp)) <= 12 then credit[k] = true end
                end
                passStep(inst, credit)
            end
        end
    end
end

-- ===================================================================== event hooks: kills, deaths, reports
local function onKill(p, zombie)
    local k = keyOf(p)
    local u = S.users[k]
    if not u then return end
    for iid in pairs(u.inst) do
        local inst = S.inst[iid]
        if inst and inst.status == "active" then
            local st = stepOf(inst)
            if st and st.t == "kill" then
                local ok = true
                if st.zone then
                    ok = CQ.inZone(st.zone, pX(p), pY(p), pZ(p))
                    if not ok and zombie then
                        local okz, zx = pcall(function() return zombie:getX() end)
                        if okz then ok = CQ.inZone(st.zone, zx, zombie:getY(), zombie:getZ()) end
                    end
                end
                if ok then
                    inst.cnt = (inst.cnt or 0) + 1
                    inst.cntBy[k] = (inst.cntBy[k] or 0) + 1
                    markInst(inst)
                    if inst.cnt >= (st.n or 1) then passStep(inst, keysOf(inst.cntBy)) end
                end
            end
        end
    end
end
CQS.onKill = onKill

function CQS.onPlayerDied(name)
    if not S then return end
    local k = CQ.ukey(name)
    if k == "" then return end
    local t = now()
    if lastDeath[k] and t - lastDeath[k] < 30 then return end
    lastDeath[k] = t
    for _, iid in ipairs(CQ.sortedKeys(S.inst)) do
        local inst = S.inst[iid]
        if inst and inst.status == "active" and not inst.members[k] then
            local st = stepOf(inst)
            if st and st.t == "others" then
                local ev = inst.eid and S.events[inst.eid]
                local counts = true
                if ev and ev.parts then counts = ev.parts[k] ~= nil end
                if counts then
                    inst.cnt = (inst.cnt or 0) + 1
                    markInst(inst)
                    if inst.cnt >= (st.n or 1) then passStep(inst, nil) end
                end
            end
        end
    end
end

local function onCollectReport(p, iid, n)
    local inst = S.inst[iid]
    local k = keyOf(p)
    if not inst or inst.status ~= "active" or not inst.members[k] then return end
    local st = stepOf(inst)
    if not st or st.t ~= "collect" then return end
    inst.cntBy[k] = CQ.int(n, 0, 0, 99999)
    local total = 0
    for _, c in pairs(inst.cntBy) do total = total + c end
    if total ~= inst.cnt then inst.cnt = total; markInst(inst) end
    if total >= (st.n or 1) then
        local credit = {}
        for kk, c in pairs(inst.cntBy) do if c > 0 then credit[kk] = true end end
        passStep(inst, credit)
    end
end

local function onRadioReport(p, ch)
    ch = CQ.int(ch, 0)
    local k = keyOf(p)
    local u = S.users[k]
    if not u or not ch then return end
    for iid in pairs(u.inst) do
        local inst = S.inst[iid]
        if inst and inst.status == "active" then
            local st = stepOf(inst)
            if st and st.t == "radio" and math.abs((st.ch or 0) - ch) <= 100 then
                passStep(inst, { [k] = true })
            end
        end
    end
end

-- ===================================================================== event lifecycle
local function assignRoles(ev)
    if ev.roleMode == "none" or #ev.roles == 0 then return end
    local counts = {}
    for i = 1, #ev.roles do counts[ev.roles[i].id] = 0 end
    local pending = {}
    for _, k in ipairs(CQ.sortedKeys(ev.parts)) do
        local p = ev.parts[k]
        if p.role and counts[p.role] ~= nil then counts[p.role] = counts[p.role] + 1
        else p.role = nil; pending[#pending + 1] = k end
    end
    for i = #pending, 2, -1 do
        local j = ZombRand(i) + 1
        pending[i], pending[j] = pending[j], pending[i]
    end
    for _, k in ipairs(pending) do
        local best, bestN = nil, nil
        local start = ZombRand(#ev.roles) + 1
        for n = 0, #ev.roles - 1 do
            local r = ev.roles[CQ.mod(start - 1 + n, #ev.roles) + 1]
            local c = counts[r.id]
            if (r.max == 0 or c < r.max) and (bestN == nil or c < bestN) then best, bestN = r, c end
        end
        if best then
            ev.parts[k].role = best.id
            counts[best.id] = counts[best.id] + 1
        end
    end
end

local function deliverKit(ev, k)
    local part = ev.parts[k]
    if not part or part.kit then return end
    part.kit = true
    local list = CQ.copy(ev.kit or {})
    if ev.roleMode ~= "none" then
        local r = roleOf(ev, part.role)
        if r then for i = 1, #r.kit do list[#list + 1] = CQ.copy(r.kit[i]) end end
    end
    if #list > 0 then queueItems(k, list, "kit", ev.title, ev.id) else part.got = true end
    markMe(k)
end

local function hasEventInst(k, mid, eid)
    local u = S.users[k]
    if not u then return false end
    for iid in pairs(u.inst) do
        local inst = S.inst[iid]
        if inst and inst.mid == mid and inst.eid == eid then return true end
    end
    return false
end

-- missions of one phase of an event for one participant (or join the shared team ones); safe to repeat
local function joinEventMissions(ev, k, ph)
    ph = ph or 1
    ev.teamInst = ev.teamInst or {}
    local part = ev.parts[k]
    local lists = { { key = "*", mids = ev.missions, mph = ev.mph } }
    local r = roleOf(ev, part and part.role)
    if r and ev.roleMode ~= "none" then lists[#lists + 1] = { key = r.id, mids = r.missions, mph = r.mph } end
    for _, L in ipairs(lists) do
        for _, mid in ipairs(L.mids or {}) do
            local m = S.missions[mid]
            if m and CQ.phaseOf(L.mph, mid) == ph then
                if m.team then
                    local tk = L.key .. ":" .. mid
                    local inst = ev.teamInst[tk] and S.inst[ev.teamInst[tk]]
                    if inst and inst.status == "active" then
                        addMember(inst, k, part.name)
                    elseif not inst then
                        inst = createInst(m, { [k] = part.name or k }, true, ev.id, nil, "event")
                        inst.ph = ph
                        ev.teamInst[tk] = inst.id
                    end
                elseif not hasEventInst(k, mid, ev.id) then
                    local inst = createInst(m, { [k] = part.name or k }, false, ev.id, k, "event")
                    inst.ph = ph
                end
            end
        end
    end
end

-- ===================================================================== phases 1 > 2 > 3
local function nPhases(ev) return math.max(1, #(ev.phases or {})) end

local function phaseName(ev, n)
    local ph = ev.phases and ev.phases[n]
    return (ph and ph.name ~= "" and ph.name) or ""
end

-- every event mission of phase n that k takes part in is finished (none at all also counts)
local function unitDone(ev, k, n)
    local u = S.users[k]
    if not u then return true end
    for iid in pairs(u.inst) do
        local inst = S.inst[iid]
        if inst and inst.eid == ev.id and (inst.ph or 1) == n and inst.status == "active" then return false end
    end
    return true
end

-- hand out every phase this participant may have now
local function syncPhases(ev, k)
    local part = ev.parts and ev.parts[k]
    if not part or ev.status ~= "live" then return end
    local N = nPhases(ev)
    local open = ev.phase or 1
    part.ph = part.ph or 0
    for _ = 1, N do
        if part.ph >= N then break end
        local cur = part.ph
        local go
        if cur == 0 then
            go = true
        else
            local done = unitDone(ev, k, cur)
            local selfGo = ev.phases[cur] and ev.phases[cur].self and done
            local opened = (cur + 1) <= open
            if ev.phaseMode == "parallel" then go = opened or selfGo
            else go = done and (opened or selfGo) end
        end
        if not go then break end
        part.ph = cur + 1
        joinEventMissions(ev, k, part.ph)
        if part.ph > 1 then toast(k, "myphase", { tostring(part.ph), phaseName(ev, part.ph), ev.title }) end
        markMe(k)
    end
end

local function openPhase(ev, n)
    local N = nPhases(ev)
    n = CQ.clamp(n, 1, N)
    if n <= (ev.phase or 1) then return end
    ev.phaseAt = ev.phaseAt or {}
    for i = (ev.phase or 1) + 1, n do ev.phaseAt[i] = now() end
    ev.phase = n
    for k in pairs(ev.parts or {}) do toast(k, "phase", { tostring(n), phaseName(ev, n), ev.title }) end
    logLine("event " .. tostring(ev.id) .. " phase " .. tostring(n))
    for _, k in ipairs(CQ.sortedKeys(ev.parts or {})) do syncPhases(ev, k) end
    markPub()
end
CQS.openPhase = openPhase

-- automatic triggers for leaving the phase that is open now
local function checkPhase(ev)
    local open = ev.phase or 1
    if open >= nPhases(ev) then return end
    local ph = ev.phases[open] or {}
    local go = false
    if (ph.min or 0) > 0 then
        local at = (ev.phaseAt and ev.phaseAt[open]) or ev.startedAt or now()
        if now() >= at + ph.min * 60 then go = true end
    end
    if not go and (ph.all or (ph.key or "") ~= "") then
        local any, active, keyDone = false, false, false
        for _, inst in pairs(S.inst) do
            if inst.eid == ev.id then
                if (inst.ph or 1) == open then
                    any = true
                    if inst.status == "active" then active = true end
                end
                if inst.mid == ph.key and inst.status == "done" then keyDone = true end
            end
        end
        if ph.all and any and not active then go = true end
        if keyDone then go = true end
    end
    if go then openPhase(ev, open + 1) end
end

local function phaseTick()
    for _, id in ipairs(CQ.sortedKeys(S.events)) do
        local ev = S.events[id]
        if ev.status == "live" then
            checkPhase(ev)
            for _, k in ipairs(CQ.sortedKeys(ev.parts or {})) do syncPhases(ev, k) end
        end
    end
end

-- ===================================================================== zombie spawn points
local spawnLive = {}     -- "eid:sid" -> { zombie objects } (runtime only)
local spawnedBy = {}     -- zombie object -> "eid:sid"

local function spState(ev, sid)
    ev.spawnState = ev.spawnState or {}
    local s = ev.spawnState[sid]
    if not s then s = { on = true, kills = 0, spawned = 0, alive = 0, acc = 0 }; ev.spawnState[sid] = s end
    return s
end

local function stopSpawn(ev, sp, why)
    local s = spState(ev, sp.id)
    if s.stopped then return end
    s.stopped = why or "admin"
    s.stoppedAt = now()
    s.on = false
    logLine("spawn " .. tostring(ev.id) .. "/" .. tostring(sp.id) .. " stopped: " .. tostring(s.stopped))
    dirty.adm = true
end
CQS.stopSpawn = stopSpawn

-- the checkpoint that ends a spawn point has been passed by anyone in this event
local function checkpointPassed(ev, sp)
    if (sp.stopMid or "") == "" then return false end
    for _, inst in pairs(S.inst) do
        if inst.eid == ev.id and inst.mid == sp.stopMid then
            if inst.status == "done" or (inst.step or 1) > (sp.stopStep or 1) then return true end
        end
    end
    return false
end

local function freeSquare(zn)
    local cell = getCell()
    if not cell then return nil end
    for _ = 1, 8 do
        local x = zn.x1 + ZombRand(zn.x2 - zn.x1 + 1)
        local y = zn.y1 + ZombRand(zn.y2 - zn.y1 + 1)
        local sq = cell:getGridSquare(x, y, zn.z or 0)
        if sq then
            local okS, solid = pcall(function() return sq:isSolid() or sq:isSolidTrans() end)
            if not (okS and solid) then return x, y end
        end
    end
    return nil
end

local function spawnOne(ev, sp)
    local x, y = freeSquare(sp.zone)
    if not x then return false end
    local ok, list = pcall(addZombiesInOutfit, x, y, sp.zone.z or 0, 1, nil, 50)
    if not ok or not list then
        if not CQS.spawnErr then CQS.spawnErr = true; CQ.log("zombie spawn failed: " .. tostring(list)) end
        return false
    end
    local key = ev.id .. ":" .. sp.id
    spawnLive[key] = spawnLive[key] or {}
    local n = 0
    pcall(function()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            spawnLive[key][#spawnLive[key] + 1] = z
            spawnedBy[z] = key
            pcall(function() z:getModData().cqSp = key end)
            n = n + 1
        end
    end)
    return n > 0, n
end

local function pruneAlive(key)
    local list = spawnLive[key]
    if not list then return 0 end
    local keep = {}
    for i = 1, #list do
        local z = list[i]
        local ok, alive = pcall(function() return not z:isDead() and z:getCurrentSquare() ~= nil end)
        if ok and alive then keep[#keep + 1] = z else spawnedBy[z] = nil end
    end
    spawnLive[key] = keep
    return #keep
end

local function spawnTick(dt)
    for _, eid in ipairs(CQ.sortedKeys(S.events)) do
        local ev = S.events[eid]
        if ev.status == "live" and ev.spawns and #ev.spawns > 0 then
            for _, sp in ipairs(ev.spawns) do
                local s = spState(ev, sp.id)
                if not s.stopped and sp.zone then
                    if (sp.stopKills or 0) > 0 and s.kills >= sp.stopKills then stopSpawn(ev, sp, "kills")
                    elseif checkpointPassed(ev, sp) then stopSpawn(ev, sp, "cp") end
                end
                local running = s.on and not s.stopped and sp.zone and (ev.phase or 1) >= (sp.fromPhase or 1)
                if running then
                    local key = ev.id .. ":" .. sp.id
                    local alive = pruneAlive(key)
                    if alive ~= s.alive then s.alive = alive; dirty.adm = true end
                    s.acc = math.min((s.acc or 0) + sp.perMin * dt / 60, 10)
                    while s.acc >= 1 and s.alive < sp.maxAlive do
                        local ok, n = spawnOne(ev, sp)
                        if not ok then break end
                        s.acc = s.acc - 1
                        s.spawned = s.spawned + (n or 1)
                        s.alive = s.alive + (n or 1)
                        dirty.adm = true
                    end
                    if s.alive >= sp.maxAlive then s.acc = math.min(s.acc, 1) end
                end
            end
        end
    end
end

local function onSpawnedDead(zombie)
    local key = spawnedBy[zombie]
    if not key then
        local ok, md = pcall(function() return zombie:getModData() end)
        if ok and md and type(md.cqSp) == "string" then key = md.cqSp end
    end
    if not key then return end
    spawnedBy[zombie] = nil
    local eid, sid = string.match(key, "^([^:]+):(.+)$")
    local ev = eid and S.events[eid]
    if not ev or not ev.spawnState or not ev.spawnState[sid] then return end
    local s = ev.spawnState[sid]
    s.kills = (s.kills or 0) + 1
    s.alive = math.max(0, (s.alive or 0) - 1)
    dirty.adm = true
end
CQS.onSpawnedDead = onSpawnedDead

function CQS.startEvent(ev)
    if ev.status == "live" then return end
    ev.status = "live"
    ev.startedAt = now()
    if not ev.start or ev.start > now() then ev.start = now() end
    ev.teamInst = {}
    ev.phase = 1
    ev.phaseAt = { now() }
    ev.spawnState = {}
    assignRoles(ev)
    for _, k in ipairs(CQ.sortedKeys(ev.parts)) do
        deliverKit(ev, k)
        ev.parts[k].ph = 0
        syncPhases(ev, k)
    end
    toastAll("evstart", { ev.title })
    logLine("event start " .. tostring(ev.id))
    markPub()
end

local function applyPenalty(k, mult, days, reason)
    local u = user(k)
    local untilTs = now() + math.floor(days * 86400)
    if u.pen and CQ.num(u.pen.untilTs, 0) > now() then
        untilTs = math.max(untilTs, u.pen.untilTs)
        mult = math.min(mult, CQ.num(u.pen.mult, 1))
    end
    u.pen = { untilTs = untilTs, mult = mult, reason = reason or "" }
    toast(k, "pen", { CQ.fmt(mult, 2), CQ.fmt(days, 1), reason or "" })
    markMe(k)
end
CQS.applyPenalty = applyPenalty

function CQS.endEvent(ev)
    if ev.status ~= "live" then return end
    ev.status = "done"
    ev.endedAt = now()
    for _, sp in ipairs(ev.spawns or {}) do stopSpawn(ev, sp, "end") end
    local doneN = 0
    for _, iid in ipairs(CQ.sortedKeys(S.inst)) do
        local inst = S.inst[iid]
        if inst.eid == ev.id then
            if inst.status == "active" then
                inst.status = "expired"
                inst.finished = now()
                markInst(inst)
            elseif inst.status == "done" then
                doneN = doneN + 1
            end
        end
    end
    local penN = 0
    if ev.pen and ev.pen.on then
        for _, k in ipairs(CQ.sortedKeys(ev.parts)) do
            local p = ev.parts[k]
            if p.got and (p.cp or 0) < (ev.pen.minCp or 1) then
                applyPenalty(k, ev.pen.mult, ev.pen.days, ev.title)
                p.pen = true
                penN = penN + 1
            end
        end
    end
    for mid, g in pairs(S.globalM) do
        if g.eid == ev.id then S.globalM[mid] = nil end
    end
    -- no-shows never get the kit after the event
    for k in pairs(ev.parts or {}) do
        local u = S.users[k]
        if u and #u.items > 0 then
            local keep = {}
            for i = 1, #u.items do
                if u.items[i].eid ~= ev.id or u.items[i].why ~= "kit" then keep[#keep + 1] = u.items[i] end
            end
            u.items = keep
        end
    end
    ev.results = { parts = CQ.count(ev.parts), penalized = penN, done = doneN }
    toastAll("evend", { ev.title, tostring(doneN) })
    logLine("event end " .. tostring(ev.id) .. " penalized=" .. tostring(penN))
    markPub()
end

local function joinEvent(p, eid, roleId)
    local k = keyOf(p)
    local ev = S.events[eid]
    if not ev then return end
    if ev.status ~= "sched" and not (ev.status == "live" and ev.lateJoin) then toast(k, "err", { "closed" }); return end
    ev.parts = ev.parts or {}
    local part = ev.parts[k]
    if not part then
        part = { name = nameOf(p), joined = now(), cp = 0, kit = false }
        ev.parts[k] = part
    end
    if ev.roleMode == "pick" and roleId and not part.kit then
        local r = roleOf(ev, roleId)
        if r then
            local c = 0
            for kk, pp in pairs(ev.parts) do if kk ~= k and pp.role == r.id then c = c + 1 end end
            if r.max > 0 and c >= r.max then toast(k, "err", { "rolefull" }); markMe(k); return end
            part.role = r.id
        end
    end
    if ev.status == "live" then
        if not part.role and ev.roleMode ~= "none" and #ev.roles > 0 then assignRoles(ev) end
        deliverKit(ev, k)
        syncPhases(ev, k)
    end
    toast(k, "joined", { ev.title })
    markMe(k)
    markPub()
end

local function leaveEvent(p, eid)
    local k = keyOf(p)
    local ev = S.events[eid]
    if not ev or not ev.parts or not ev.parts[k] then return end
    if ev.parts[k].kit or ev.status == "live" then toast(k, "err", { "noleave" }); return end
    ev.parts[k] = nil
    toast(k, "left", { ev.title })
    markMe(k)
    markPub()
end

-- ===================================================================== sync payloads
local function publicEvent(ev)
    local roles = {}
    local counts = {}
    for _, p in pairs(ev.parts or {}) do if p.role then counts[p.role] = (counts[p.role] or 0) + 1 end end
    for i = 1, #ev.roles do
        local r = ev.roles[i]
        roles[#roles + 1] = { id = r.id, name = r.name, desc = r.desc, max = r.max, secret = r.secret,
            n = r.secret and -1 or (counts[r.id] or 0), kit = r.secret and {} or CQ.copy(r.kit) }
    end
    return {
        id = ev.id, title = ev.title, desc = ev.desc, start = ev.start, dur = ev.dur, status = ev.status,
        roleMode = ev.roleMode, roles = roles, nParts = CQ.count(ev.parts), lateJoin = ev.lateJoin,
        phased = #(ev.phases or {}) > 1, phase = ev.status == "live" and (ev.phase or 1) or nil,
        phName = ev.status == "live" and phaseName(ev, ev.phase or 1) or nil,
        pen = CQ.copy(ev.pen), kit = CQ.copy(ev.kit), results = CQ.copy(ev.results),
    }
end

local function buildPub()
    local t = now()
    local evs = {}
    for _, id in ipairs(CQ.sortedKeys(S.events)) do
        local ev = S.events[id]
        if ev.status == "sched" or ev.status == "live" or (ev.status == "done" and t - CQ.num(ev.endedAt, 0) < 6 * 3600) then
            evs[#evs + 1] = publicEvent(ev)
        end
    end
    local board = {}
    for _, id in ipairs(CQ.sortedKeys(S.missions)) do
        local m = S.missions[id]
        if m.assign == "board" then
            local left = -1
            if m.limit and m.limit > 0 then left = math.max(0, m.limit - (S.takers[id] or 0)) end
            board[#board + 1] = { id = id, title = m.title, story = m.story, nSteps = #m.steps, team = m.team,
                rewardText = m.rewardText, rewards = CQ.copy(m.rewards), left = left, repeatable = m.repeatable,
                timeLimit = m.timeLimit }
        end
    end
    local radio = {}
    for _, id in ipairs(CQ.sortedKeys(S.radio)) do
        local r = S.radio[id]
        if r.on and #r.lines > 0 then
            radio[#radio + 1] = { id = id, ch = r.ch, lines = CQ.copy(r.lines), iv = r.iv, t0 = r.t0 or 0, color = r.color }
        end
    end
    local nextBuff = nil
    for _, id in ipairs(CQ.sortedKeys(S.buffs.sched)) do
        local b = S.buffs.sched[id]
        local n = CQ.schedNext(b, t, off())
        if n and (not nextBuff or n < nextBuff.at) then nextBuff = { at = n, mult = b.mult, label = b.label } end
    end
    return {
        now = t, utc = off(), buffs = CQ.activeBuffs(S.buffs, t, off()), nextBuff = nextBuff,
        events = evs, board = board, radio = radio, showZones = S.cfg.showZones,
    }
end

local function instView(inst, k)
    local m = S.missions[inst.mid]
    local showAll = (m == nil) or m.showSteps ~= false
    local steps = {}
    for i = 1, #inst.steps do
        local st = inst.steps[i]
        if showAll or i <= inst.step or inst.status ~= "active" then
            local v = CQ.copy(st)
            if st.hide and i >= inst.step and inst.status == "active" then v.zone = nil end
            if not S.cfg.showZones and i >= inst.step and st.t ~= "rescue" then v.zone = nil end
            steps[#steps + 1] = v
        else
            steps[#steps + 1] = { t = "?", label = "" }
        end
    end
    return {
        id = inst.id, mid = inst.mid, title = inst.title, story = m and m.story or "", team = inst.team,
        status = inst.status, step = inst.step, nSteps = #inst.steps, cnt = inst.cnt or 0, hold = math.floor(inst.hold or 0),
        armed = inst.armed, steps = steps, started = inst.started, finished = inst.finished, deadline = inst.deadline,
        eid = inst.eid, nMembers = CQ.count(inst.members), mine = (inst.cntBy and inst.cntBy[k]) or 0,
        rewards = m and CQ.copy(m.rewards) or {}, rewardText = (m and m.rewardText) or inst.rewardText or "",
        contrib = (inst.contrib and inst.contrib[k]) or 0, owner = inst.owner, ph = inst.ph,
        via = inst.via, evTitle = (inst.eid and S.events[inst.eid] and S.events[inst.eid].title) or nil,
        wait = inst.wait and CQ.copy(inst.wait) or nil,
    }
end

local function buildMe(k)
    local u = S.users[k]
    local t = now()
    local out = { now = t, k = k, inst = {}, parts = {}, pen = nil, pendingItems = 0 }
    if not u then return out end
    out.name = u.name
    for _, iid in ipairs(CQ.sortedKeys(u.inst)) do
        local inst = S.inst[iid]
        if inst then
            if inst.status == "active" or t - CQ.num(inst.finished, 0) < 3 * 3600 then
                out.inst[#out.inst + 1] = instView(inst, k)
            end
        else
            u.inst[iid] = nil
        end
    end
    for _, id in ipairs(CQ.sortedKeys(S.events)) do
        local ev = S.events[id]
        local p = ev.parts and ev.parts[k]
        if p then
            local r = roleOf(ev, p.role)
            out.parts[id] = { role = p.role, roleName = r and r.name or "", roleDesc = r and r.desc or "",
                secret = r and r.secret or false, cp = p.cp or 0, kit = p.kit, got = p.got, pen = p.pen,
                roleKit = r and CQ.copy(r.kit) or {}, ph = p.ph, phName = p.ph and phaseName(ev, p.ph) or "" }
        end
    end
    if u.pen and CQ.num(u.pen.untilTs, 0) > t then out.pen = CQ.copy(u.pen) end
    for i = 1, #u.items do out.pendingItems = out.pendingItems + #u.items[i].list end
    return out
end

local function buildAdm()
    local t = now()
    local users = {}
    for _, k in ipairs(CQ.sortedKeys(S.users)) do
        local u = S.users[k]
        local nAct = 0
        for iid in pairs(u.inst) do
            local inst = S.inst[iid]
            if inst and inst.status == "active" then nAct = nAct + 1 end
        end
        users[#users + 1] = { k = k, name = u.name, online = online[k] ~= nil, pen = (u.pen and CQ.num(u.pen.untilTs, 0) > t) and CQ.copy(u.pen) or nil,
            nAct = nAct, pending = #u.items, done = CQ.count(u.done) }
    end
    local inst = {}
    for _, iid in ipairs(CQ.sortedKeys(S.inst)) do
        local i = S.inst[iid]
        if i.status == "active" or t - CQ.num(i.finished, 0) < 6 * 3600 then
            local v = CQ.copy(i)
            v.online = {}
            for k in pairs(i.members) do if online[k] then v.online[k] = true end end
            local st = i.status == "active" and i.steps and i.steps[i.step]
            if st and st.zone then
                v.diag = {}
                for k in pairs(i.members) do
                    local pl = online[k]
                    if pl then
                        local zf = math.floor(pZ(pl))
                        v.diag[k] = { d = math.floor(CQ.distToZone(st.zone, pX(pl), pY(pl)) + 0.5),
                            dz = st.zone.anyZ and 0 or ((st.zone.z or 0) - zf), inside = CQ.inZone(st.zone, pX(pl), pY(pl), pZ(pl)),
                            staff = CQS.isAdmin(pl) == true }
                    end
                end
            end
            local ev = i.eid and S.events[i.eid]
            v.evTitle = ev and ev.title or nil
            inst[#inst + 1] = v
        end
    end
    return {
        now = t, cfg = CQ.copy(S.cfg), missions = CQ.copy(S.missions), events = CQ.copy(S.events),
        inst = inst, users = users, buffs = CQ.copy(S.buffs), radio = CQ.copy(S.radio),
        active = CQ.activeBuffs(S.buffs, t, off()), log = CQ.copy(S.log), takers = CQ.copy(S.takers),
        globalM = CQ.copy(S.globalM), build = CQ.BUILD,
    }
end

function CQS.flush(force)
    local t = getTimestampMs and getTimestampMs() or now() * 1000
    if t < lastFlush then lastFlush = 0 end
    if not force and t - lastFlush < 700 then return end
    lastFlush = t
    if dirty.pub then
        dirty.pub = false
        deliverAll("pub", buildPub())
    end
    local still = {}
    for k in pairs(dirty.me) do
        local p = online[k]
        if p then
            if force or t - (lastMe[k] or 0) >= 1500 or t < (lastMe[k] or 0) then
                lastMe[k] = t
                deliver(p, "me", buildMe(k))
            else
                still[k] = true
            end
        end
    end
    dirty.me = still
    if t < lastAdm then lastAdm = 0 end
    if dirty.adm and (force or t - lastAdm >= 2000) then
        lastAdm = t
        dirty.adm = false
        local payload = nil
        for k in pairs(admWatch) do
            local p = online[k]
            if p and CQS.isAdmin(p) then
                payload = payload or buildAdm()
                deliver(p, "adm", payload)
            else
                admWatch[k] = nil
            end
        end
    end
end

-- ===================================================================== greeting / login
local function greet(p)
    local k = keyOf(p)
    user(k, nameOf(p))
    seenSession[k] = true
    for mid, g in pairs(S.globalM) do
        local m = S.missions[mid]
        if m and (not g.eid) then
            if g.iid then
                local inst = S.inst[g.iid]
                if inst and inst.status == "active" then addMember(inst, k, nameOf(p)) end
            elseif g.solo and not hasActive(k, mid) and canTake(k, m) then
                createInst(m, { [k] = nameOf(p) }, false, nil, k, "everyone")
            end
        end
    end
    flushPendingItems(k)
    deliver(p, "pub", buildPub())
    deliver(p, "me", buildMe(k))
end

-- ===================================================================== commands
local SELF_LOGGED = { saveMission = true, delMission = true, saveEvent = true, delEvent = true, eventCtl = true, stepCtl = true, bundle = true, clearLog = true, instBulk = true }
local H = {}       -- player commands
local A = {}       -- admin commands

local adminSeen = {}       -- ukey -> last admin state told to that client
local function tellAdmin(p, force)
    local k = keyOf(p)
    local a = CQS.isAdmin(p) == true
    if force or adminSeen[k] ~= a then
        adminSeen[k] = a
        deliver(p, "isadm", { ok = a })
        if not a then admWatch[k] = nil end
    end
end
CQS.tellAdmin = tellAdmin

H.hello = function(p, a)
    greet(p)
    tellAdmin(p, true)
end
H.join = function(p, a) joinEvent(p, CQ.str(a.eid, 24), a.role and CQ.str(a.role, 24) or nil) end
H.leave = function(p, a) leaveEvent(p, CQ.str(a.eid, 24)) end
H.accept = function(p, a)
    local via = CQ.oneOf(a.via, { "sheet", "board" }, "board")
    CQS.accept(p, CQ.str(a.mid, 24), via)
end
H.abandon = function(p, a)
    local inst = S.inst[CQ.str(a.iid, 24)]
    local k = keyOf(p)
    if not inst or inst.status ~= "active" or inst.team or inst.owner ~= k or inst.eid then return end
    inst.status = "failed"
    inst.finished = now()
    toast(k, "mfail", { inst.title or "" })
    markInst(inst)
end
H.peek = function(p, a)
    local mid = CQ.str(a.mid, 24)
    local m = S.missions[mid]
    if not m then deliver(p, "sheet", { mid = mid, missing = true }); return end
    local k = keyOf(p)
    local ok, why = canTake(k, m)
    if m.assign == "everyone" and S.globalM[mid] then ok, why = true, "active" end
    local steps = {}
    for i = 1, #m.steps do
        local st = m.steps[i]
        steps[#steps + 1] = { t = st.t, label = st.label, n = st.n, sec = st.sec, item = st.item }
    end
    deliver(p, "sheet", { mid = mid, title = m.title, story = m.story, assign = m.assign, team = m.team,
        showSteps = m.showSteps, steps = m.showSteps and steps or { steps[1] }, nSteps = #m.steps,
        rewardText = m.rewardText, rewards = CQ.copy(m.rewards), can = ok, why = why or "", timeLimit = m.timeLimit })
end
H.collect = function(p, a) onCollectReport(p, CQ.str(a.iid, 24), a.n) end
H.radio = function(p, a) onRadioReport(p, a.ch) end
H.died = function(p, a) CQS.onPlayerDied(nameOf(p)) end
H.watch = function(p, a)
    if not CQS.isAdmin(p) then tellAdmin(p, true); return end
    local k = keyOf(p)
    if a.on then admWatch[k] = true; deliver(p, "adm", buildAdm()) else admWatch[k] = nil end
end

local function saved(p, kind, id) deliver(p, "saved", { kind = kind, id = id }) end

-- after a live edit: a lowered target that is already reached passes right away
local function recheckStep(inst)
    if inst.status ~= "active" then return end
    local st = stepOf(inst)
    if not st then return end
    if (st.t == "kill" or st.t == "others") and (inst.cnt or 0) >= (st.n or 1) then
        passStep(inst, (inst.cntBy and CQ.any(inst.cntBy)) and keysOf(inst.cntBy) or nil)
    end
end

A.saveMission = function(p, a)
    local m = CQ.cleanMission(a.m)
    if not m then return end
    local old = m.id ~= "" and S.missions[m.id] or nil
    if not old then m.id = newId("m"); m.created = now() else m.created = old.created end
    m.updated = now()
    S.missions[m.id] = m
    if a.live ~= false then
        for _, iid in ipairs(CQ.sortedKeys(S.inst)) do
            local inst = S.inst[iid]
            if inst.mid == m.id and inst.status == "active" then
                inst.steps = CQ.copy(m.steps)
                inst.title = m.title
                if inst.step > #inst.steps then inst.step = #inst.steps; onStepEnter(inst) end
                markInst(inst)
                recheckStep(inst)
            end
        end
    end
    logLine("saved mission " .. m.id)
    markPub()
    saved(p, "m", m.id)
end
A.delMission = function(p, a)
    local id = CQ.str(a.id, 24)
    if not S.missions[id] then return end
    S.missions[id] = nil
    for _, ev in pairs(S.events) do
        local keep = {}
        for _, mid in ipairs(ev.missions or {}) do if mid ~= id then keep[#keep + 1] = mid end end
        ev.missions = keep
        for _, r in ipairs(ev.roles or {}) do
            local rk = {}
            for _, mid in ipairs(r.missions or {}) do if mid ~= id then rk[#rk + 1] = mid end end
            r.missions = rk
        end
    end
    S.globalM[id] = nil
    -- players that still have it get it cancelled
    local n = 0
    for _, iid in ipairs(CQ.sortedKeys(S.inst)) do
        local inst = S.inst[iid]
        if inst.mid == id and inst.status == "active" then cancelInst(inst); n = n + 1 end
    end
    logLine("deleted mission " .. id .. " (cancelled " .. tostring(n) .. ")")
    markPub()
end
A.saveEvent = function(p, a)
    local e = CQ.cleanEvent(a.e)
    if not e then return end
    local old = e.id ~= "" and S.events[e.id] or nil
    if old then
        e.status, e.parts, e.results, e.startedAt, e.endedAt, e.teamInst, e.created =
            old.status, old.parts, old.results, old.startedAt, old.endedAt, old.teamInst, old.created
        e.phase, e.phaseAt, e.spawnState = old.phase, old.phaseAt, old.spawnState
        for _, part in pairs(e.parts or {}) do
            if part.role and not roleOf(e, part.role) then part.role = nil end
        end
    else
        e.id = newId("e")
        e.status = "draft"
        e.parts = {}
        e.created = now()
    end
    e.updated = now()
    S.events[e.id] = e
    logLine("saved event " .. e.id)
    markPub()
    saved(p, "e", e.id)
end
A.delEvent = function(p, a)
    local id = CQ.str(a.id, 24)
    local ev = S.events[id]
    if not ev then return end
    -- its unfinished missions, everyone-missions and undelivered kits go with it (no penalty)
    local n = 0
    for _, iid in ipairs(CQ.sortedKeys(S.inst)) do
        local inst = S.inst[iid]
        if inst.eid == id and inst.status == "active" then cancelInst(inst); n = n + 1 end
    end
    for mid, g in pairs(S.globalM) do if g.eid == id then S.globalM[mid] = nil end end
    for k in pairs(ev.parts or {}) do
        local u = S.users[k]
        if u and #u.items > 0 then
            local keep = {}
            for i = 1, #u.items do if u.items[i].eid ~= id then keep[#keep + 1] = u.items[i] end end
            u.items = keep
        end
        markMe(k)
    end
    S.events[id] = nil
    logLine("deleted event " .. id .. " (cancelled " .. tostring(n) .. ")")
    markPub()
end
A.eventCtl = function(p, a)
    local ev = S.events[CQ.str(a.id, 24)]
    if not ev then return end
    local op = a.op
    if op == "sched" and ev.status ~= "live" then
        if not ev.start or ev.start < now() - 60 then ev.start = now() + 60 end
        ev.status = "sched"
        toastAll("evopen", { ev.title })
    elseif op == "start" then CQS.startEvent(ev)
    elseif op == "end" then CQS.endEvent(ev)
    elseif op == "draft" and ev.status ~= "live" then ev.status = "draft"
    elseif op == "reset" and ev.status ~= "live" then
        ev.status = "draft"; ev.parts = {}; ev.results = nil; ev.teamInst = {}; ev.phase = nil; ev.phaseAt = nil; ev.spawnState = nil
    elseif op == "phase" and ev.status == "live" then
        openPhase(ev, CQ.int(a.n, (ev.phase or 1) + 1, 1, 10))
    elseif op == "spawn" then
        -- one spawn point off (gone) or back on
        for _, sp in ipairs(ev.spawns or {}) do
            if sp.id == CQ.str(a.sid, 24) then
                if a.on then
                    local s = spState(ev, sp.id)
                    s.stopped, s.stoppedAt, s.on, s.acc = nil, nil, true, 0
                else
                    stopSpawn(ev, sp, "admin")
                end
            end
        end
    elseif op == "spawnAll" then
        for _, sp in ipairs(ev.spawns or {}) do stopSpawn(ev, sp, "admin") end
    elseif op == "kits" then
        for _, k in ipairs(CQ.sortedKeys(ev.parts or {})) do deliverKit(ev, k) end
    elseif op == "nopen" then
        for _, k in ipairs(CQ.sortedKeys(ev.parts or {})) do
            local u = S.users[k]
            if ev.parts[k].pen and u and u.pen and u.pen.reason == ev.title then u.pen = nil; markMe(k) end
            ev.parts[k].pen = nil
        end
    end
    logLine("event " .. tostring(ev.id) .. " op " .. tostring(op))
    markPub()
end
A.setRole = function(p, a)
    local ev = S.events[CQ.str(a.eid, 24)]
    local k = CQ.ukey(a.k)
    if not ev or not ev.parts or not ev.parts[k] then return end
    local r = roleOf(ev, a.role)
    ev.parts[k].role = r and r.id or nil
    if ev.status == "live" and r then
        for n = 1, ev.parts[k].ph or 0 do joinEventMissions(ev, k, n) end
        syncPhases(ev, k)
    end
    markMe(k); markPub()
end
A.part = function(p, a)
    local ev = S.events[CQ.str(a.eid, 24)]
    local k = CQ.ukey(a.k)
    if not ev or k == "" then return end
    ev.parts = ev.parts or {}
    if a.op == "remove" then
        ev.parts[k] = nil
    elseif a.op == "add" and not ev.parts[k] then
        local pl = online[k]
        ev.parts[k] = { name = pl and nameOf(pl) or CQ.str(a.k, 60), joined = now(), cp = 0, kit = false }
        if ev.status == "live" then
            if ev.roleMode ~= "none" then assignRoles(ev) end
            deliverKit(ev, k); syncPhases(ev, k)
        end
    elseif a.op == "cp" and ev.parts[k] then
        ev.parts[k].cp = CQ.int(a.cp, 0, 0, 999)
    end
    markMe(k); markPub()
end
local function instOp(inst, op)
    if not inst then return end
    if op == "pass" and inst.status == "active" then passStep(inst, nil, true)
    elseif op == "back" then
        if inst.status ~= "active" then
            inst.status = "active"; inst.finished = nil
        elseif inst.step > 1 then
            inst.step = inst.step - 1
        end
        onStepEnter(inst); markInst(inst)
    elseif op == "reset" then
        inst.step = 1; inst.status = "active"; inst.finished = nil; onStepEnter(inst); markInst(inst)
    elseif op == "fail" and inst.status == "active" then
        inst.status = "failed"; inst.finished = now(); markInst(inst)
        for k in pairs(inst.members) do toast(k, "mfail", { inst.title or "" }) end
    elseif op == "done" and inst.status == "active" then completeMission(inst)
    elseif op == "cancel" and inst.status == "active" then cancelInst(inst)
    elseif op == "remove" then removeInst(inst.id)
    end
end

A.stepCtl = function(p, a)
    local inst = S.inst[CQ.str(a.iid, 24)]
    if not inst then return end
    instOp(inst, a.op)
    logLine("inst " .. tostring(a.iid) .. " op " .. tostring(a.op))
end

-- the same control for many missions at once (admin "players' missions" page)
A.instBulk = function(p, a)
    if type(a.iids) ~= "table" then return end
    local op = CQ.oneOf(a.op, { "pass", "done", "fail", "cancel", "remove", "back" }, "")
    if op == "" then return end
    local n = 0
    for i = 1, math.min(#a.iids, 300) do
        local inst = S.inst[CQ.str(a.iids[i], 24)]
        if inst then instOp(inst, op); n = n + 1 end
    end
    logLine("bulk " .. op .. " x" .. tostring(n))
end
A.give = function(p, a)
    local m = S.missions[CQ.str(a.mid, 24)]
    if not m then return end
    local to = CQ.str(a.to, 60)
    if to == "*" then
        activateEveryone(m, nil)
        toastAll("mglobal", { m.title, nameOf(p) })
    else
        local k = CQ.ukey(to)
        local pl = online[k]
        local ev = eventContext(k)
        if not hasActive(k, m.id) then
            createInst(m, { [k] = pl and nameOf(pl) or to }, false, ev and ev.id or nil, k, "admin")
        end
    end
end
A.stopGlobal = function(p, a)
    local mid = CQ.str(a.mid, 24)
    local g = S.globalM[mid]
    if not g then return end
    if g.iid and S.inst[g.iid] and S.inst[g.iid].status == "active" then
        S.inst[g.iid].status = "expired"; S.inst[g.iid].finished = now(); markInst(S.inst[g.iid])
    end
    S.globalM[mid] = nil
    markPub()
end
A.sheet = function(p, a)
    local m = S.missions[CQ.str(a.mid, 24)]
    if not m then return end
    local n = CQ.int(a.n, 1, 1, 10)
    local inv = p:getInventory()
    for _ = 1, n do
        local ok, item = pcall(instanceItem, CQ.SHEET_TYPE)
        if ok and item then
            item:getModData().cqMid = m.id
            pcall(function() item:setName(m.title .. "  #" .. m.id) end)
            pcall(function() item:setCustomName(true) end)
            inv:AddItem(item)
            if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
        end
    end
    toast(keyOf(p), "sheet", { m.title, tostring(n) })
end
A.saveSched = function(p, a)
    local b = CQ.cleanSched(a.b)
    if not b then return end
    if b.id == "" or not S.buffs.sched[b.id] then b.id = newId("b") end
    S.buffs.sched[b.id] = b
    markPub()
    saved(p, "b", b.id)
end
A.delSched = function(p, a)
    S.buffs.sched[CQ.str(a.id, 24)] = nil
    markPub()
end
A.manual = function(p, a)
    if a.stop then
        S.buffs.manual = nil
    else
        local hours = CQ.clamp(CQ.num(a.hours, 1), 0.05, 168)
        S.buffs.manual = { mult = CQ.clamp(CQ.num(a.mult, 2), 0.1, 20), untilTs = now() + math.floor(hours * 3600),
            skills = CQ.cleanSkills(a.skills), label = CQ.str(a.label, 60), by = nameOf(p) }
    end
    lastSlow = 0
    markPub()
end
A.saveRadio = function(p, a)
    local r = CQ.cleanRadio(a.r)
    if not r then return end
    if r.id == "" or not S.radio[r.id] then r.id = newId("r") end
    r.t0 = now()
    S.radio[r.id] = r
    markPub()
    saved(p, "r", r.id)
end
A.delRadio = function(p, a)
    S.radio[CQ.str(a.id, 24)] = nil
    markPub()
end
A.pen = function(p, a)
    local k = CQ.ukey(a.k)
    if k == "" then return end
    if a.op == "clear" then
        local u = S.users[k]
        if u then u.pen = nil end
        toast(k, "penclear", {})
        markMe(k)
    elseif a.op == "give" then
        applyPenalty(k, CQ.clamp(CQ.num(a.mult, 0.5), 0.05, 1), CQ.clamp(CQ.num(a.days, 3), 0.05, 30), CQ.str(a.reason, 60))
    end
end
A.cfg = function(p, a)
    if a.utc ~= nil then S.cfg.utc = CQ.clamp(CQ.num(a.utc, 7), -12, 14) end
    if a.showZones ~= nil then S.cfg.showZones = a.showZones == true end
    markPub()
end
A.clearLog = function(p, a) S.log = {}; dirty.adm = true end
-- create several missions + one draft event at once ("#n" in the event refers to the n-th mission)
A.bundle = function(p, a)
    local map = {}
    if type(a.missions) == "table" then
        for i = 1, math.min(#a.missions, 30) do
            local m = CQ.cleanMission(a.missions[i])
            if m then
                m.id = newId("m")
                m.created = now()
                m.updated = now()
                S.missions[m.id] = m
                map["#" .. tostring(i)] = m.id
            end
        end
    end
    local function remap(list)
        local out = {}
        for _, id in ipairs(list or {}) do out[#out + 1] = map[id] or id end
        return out
    end
    if type(a.event) == "table" then
        local e = CQ.cleanEvent(a.event)
        if e then
            e.missions = remap(e.missions)
            for _, r in ipairs(e.roles) do r.missions = remap(r.missions) end
            e.id = newId("e")
            e.status = "draft"
            e.parts = {}
            e.created = now()
            S.events[e.id] = e
            saved(p, "e", e.id)
        end
    end
    logLine("bundle created by " .. nameOf(p))
    markPub()
end

local function allow(p, cmd)
    local k = keyOf(p)
    local t = now()
    local r = rate[k]
    if not r or r.t ~= t then r = { t = t, n = 0 }; rate[k] = r end
    r.n = r.n + 1
    return r.n <= 25
end

local function onClientCommand(module, command, p, args)
    if module ~= MOD or not p then return end
    if not S then return end
    if args ~= nil and type(args) ~= "table" then return end
    args = args or {}
    if not allow(p, command) then return end
    local h = H[command]
    local admin = false
    if not h then
        h = A[command]
        admin = true
    end
    if not h then return end
    if admin and not CQS.isAdmin(p) then
        CQ.log("rejected admin command " .. tostring(command) .. " from " .. nameOf(p))
        tellAdmin(p, true)
        return
    end
    if admin then
        logActor = nameOf(p)
        if not SELF_LOGGED[command] then
            local extra = ""
            if command == "give" then extra = " " .. tostring(args.mid) .. " -> " .. tostring(args.to) end
            logLine(command .. extra)
        end
    end
    local ok, err = pcall(h, p, args)
    logActor = nil
    if not ok then CQ.log("command " .. tostring(command) .. " failed: " .. tostring(err)) end
    if admin then dirty.adm = true end
    CQS.flush(true)
end
CQS.onClientCommand = onClientCommand

-- ===================================================================== ticking
local function slowTick()
    local t = now()
    -- promotions / demotions reach the client without relogging
    for _, p in pairs(online) do tellAdmin(p, false) end
    -- event schedule
    for _, id in ipairs(CQ.sortedKeys(S.events)) do
        local ev = S.events[id]
        if ev.status == "sched" and ev.start and t >= ev.start then CQS.startEvent(ev)
        elseif ev.status == "live" and ev.start and t >= ev.start + (ev.dur or 120) * 60 then CQS.endEvent(ev) end
    end
    -- buffs signature
    local act = CQ.activeBuffs(S.buffs, t, off())
    local sig = ""
    for i = 1, #act do sig = sig .. act[i].k .. ":" .. tostring(act[i].untilTs) .. ":" .. tostring(act[i].mult) .. ";" end
    if sig ~= lastBuffSig then
        if lastBuffSig ~= "" or sig ~= "" then markPub() end
        if sig ~= "" and #act > 0 and lastBuffSig ~= "init" then
            for i = 1, #act do
                if not string.find(lastBuffSig, act[i].k .. ":", 1, true) then
                    toastAll("buffon", { CQ.fmt(act[i].mult, 2), act[i].label or "" })
                end
            end
        end
        lastBuffSig = sig
    end
    if S.buffs.manual and CQ.num(S.buffs.manual.untilTs, 0) <= t then S.buffs.manual = nil; markPub() end
    -- penalties expiry
    for k, u in pairs(S.users) do
        if u.pen and CQ.num(u.pen.untilTs, 0) <= t then u.pen = nil; markMe(k) end
    end
    -- old finished instances (7 days)
    for _, iid in ipairs(CQ.sortedKeys(S.inst)) do
        local inst = S.inst[iid]
        if inst.status ~= "active" and t - CQ.num(inst.finished, t) > 7 * 86400 then
            for k in pairs(inst.members) do
                local u = S.users[k]
                if u then u.inst[iid] = nil end
            end
            S.inst[iid] = nil
        end
    end
    -- hit cache pruning
    local ms = getTimestampMs and getTimestampMs() or t * 1000
    for z, c in pairs(hitCache) do if ms - c.t > 60000 then hitCache[z] = nil end end
end

local function onTick()
    if not S then return end
    local ms = getTimestampMs and getTimestampMs() or now() * 1000
    if ms < lastTick then lastTick = ms - 1000; lastSlow = 0 end
    if ms - lastTick < 1000 then return end
    local dt = math.min(5, (ms - lastTick) / 1000)
    if lastTick == 0 then dt = 1 end
    lastTick = ms
    rebuildOnline()
    for k, p in pairs(online) do
        if not seenSession[k] then greet(p) end
        if S.users[k] and #S.users[k].items > 0 then flushPendingItems(k) end
    end
    if ms - lastSlow >= 5000 then
        lastSlow = ms
        slowTick()
    end
    for _, iid in ipairs(CQ.sortedKeys(S.inst)) do
        local inst = S.inst[iid]
        if inst and inst.status == "active" then
            local ok, err = pcall(checkInst, inst, dt)
            if not ok then CQ.log("check " .. tostring(iid) .. " failed: " .. tostring(err)) end
        end
    end
    local okP, errP = pcall(phaseTick)
    if not okP then CQ.log("phase tick failed: " .. tostring(errP)) end
    local okZ, errZ = pcall(spawnTick, dt)
    if not okZ then CQ.log("spawn tick failed: " .. tostring(errZ)) end
    CQS.flush(false)
end
CQS.onTick = onTick

-- ===================================================================== XP provider (server side)
CQ.XP.provider = function(p, pid)
    if not S then return 1 end
    local u = S.users[keyOf(p)]
    local t = now()
    return CQ.multFor(pid, CQ.activeBuffs(S.buffs, t, off()), u and u.pen or nil, t)
end
local lastNote = {}
CQ.XP.onNote = function(p, n)
    if not S or not p or not CQS.isAdmin(p) then return end
    local k = keyOf(p)
    local ms = getTimestampMs and getTimestampMs() or now() * 1000
    if lastNote[k] and ms - lastNote[k] < 1000 then return end
    lastNote[k] = ms
    deliver(p, "xpn", { pid = n.pid, base = n.base, bonus = n.bonus, mult = n.mult, side = n.side })
end
CQ.XP.onServerApplied = function(p)
    if not isServer() then return end
    local k = keyOf(p)
    if srvxpTold[k] then return end
    srvxpTold[k] = true
    deliver(p, "srvxp", {})
end

-- ===================================================================== registration
Events.OnInitGlobalModData.Add(function()
    S = ModData.getOrCreate("CookieQuest")
    defaults(S)
    lastBuffSig = "init"
    CQ.log("server ready " .. CQ.BUILD .. " missions=" .. tostring(CQ.count(S.missions)) .. " events=" .. tostring(CQ.count(S.events)))
end)

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(function()
    local ok, err = pcall(onTick)
    if not ok then CQ.log("tick error: " .. tostring(err)) end
end)

if Events.OnWeaponHitCharacter then Events.OnWeaponHitCharacter.Add(function(attacker, target, weapon, damage)
    if not S or not attacker or not target then return end
    if not instanceof(attacker, "IsoPlayer") or not instanceof(target, "IsoZombie") then return end
    local ms = getTimestampMs and getTimestampMs() or now() * 1000
    hitCache[target] = { p = attacker, t = ms }
end) end

Events.OnZombieDead.Add(function(zombie)
    if not S or not zombie then return end
    pcall(CQS.onSpawnedDead, zombie)
    local c = hitCache[zombie]
    hitCache[zombie] = nil
    local p = c and c.p
    if not p then
        local ok, a = pcall(function() return zombie:getAttackedBy() end)
        if ok and a and instanceof(a, "IsoPlayer") then p = a end
    end
    if p then
        local ok, err = pcall(onKill, p, zombie)
        if not ok then CQ.log("kill error: " .. tostring(err)) end
    end
end)

if Events.OnCharacterDeath then Events.OnCharacterDeath.Add(function(ch)
    if not S or not ch then return end
    if instanceof(ch, "IsoPlayer") then
        local ok, err = pcall(CQS.onPlayerDied, nameOf(ch))
        if not ok then CQ.log("death error: " .. tostring(err)) end
    end
end) end

return CQS
