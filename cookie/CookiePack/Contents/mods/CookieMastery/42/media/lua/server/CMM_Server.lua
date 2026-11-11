-- Cookie Mastery - server authority (dedicated server, host, or single player)
if isClient() and not isServer() then return end

require "CMM_Shared"
require "CMM_NoJournal"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISFitnessAction"
require "Entity/TimedActions/ISHandcraftAction"
require "BuildingObjects/ISBuildIsoEntity"

CMMS = CMMS or {}
local MOD = CMM.MOD
local S = nil           -- persistent state (global ModData "CookieMastery")
local online = {}       -- ukey -> IsoPlayer
local act = {}          -- ukey -> { br, t } last overflow gain (mentor counts as active)
local invites = {}      -- student ukey -> { from = mentor ukey, t }
local capMin = {}       -- ukey -> { t, n } points accepted in the current minute
local dirty = {}        -- ukey -> true: resend "me"
local builds = {}       -- queued client-side build reports
local rate = {}
local lastTick, lastSlow = 0, 0

local function now() return CM.now() end
local function nowMs()
    if getTimestampMs then
        local ok, v = pcall(getTimestampMs)
        if ok and v then return v end
    end
    return now() * 1000
end

-- ===================================================================== state
local function defaults(s)
    s.v = s.v or 1
    s.p = s.p or {}
    s.hof = s.hof or {}
    s.pend = s.pend or {}
    s.legacy = s.legacy or {}
    s.log = s.log or {}
    s.test = s.test or {}    -- admin test mode: ukey -> { rec = the real record, seal = S.seal[ukey] }
end

function CMMS.state() return S end

local function logLine(text)
    table.insert(S.log, 1, { t = now(), s = tostring(text) })
    while #S.log > 60 do table.remove(S.log) end
    CMM.log(text)
end
CMMS.logLine = logLine

local function nameOf(p)
    local ok, n = pcall(function() return p:getUsername() end)
    if ok and n and n ~= "" then return tostring(n) end
    return "Player"
end
local function keyOf(p) return CM.ukey(nameOf(p)) end
CMMS.keyOf = keyOf

local function recOf(k, name)
    local r = S.p[k]
    if not r then
        r = { pts = 0, wal = 0, pre = {}, life = 1, born = now() }
        S.p[k] = r
    end
    if name then r.name = name end
    r.pre = r.pre or {}
    r.pts = CM.num(r.pts, 0)
    r.wal = CM.num(r.wal, 0)
    return r
end

-- used by the build hook (server side or single player)
function CMMS.recFor(chr)
    if not S or not chr then return nil end
    local ok, isP = pcall(function() return instanceof(chr, "IsoPlayer") end)
    if not ok or not isP then return nil end
    return recOf(keyOf(chr), nameOf(chr))
end

-- the record of a player without creating one (journal guard)
function CMMS.peek(chr)
    if not S or not chr then return nil end
    local ok, n = pcall(function() return chr:getUsername() end)
    if not ok or not n then return nil end
    return S.p[CM.ukey(tostring(n))]
end

local function lvOf(r) return (CMM.level(r and r.pts or 0)) end

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

local function alive(p)
    if not p then return false end
    local ok, dead = pcall(function() return p:isDead() end)
    return ok and not dead
end

local STAFF_LEVELS = { admin = true, moderator = true, overseer = true, gm = true }
function CMMS.isAdmin(p)
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
CMMS.send = deliver

local function toast(k, kind, a)
    local p = online[k]
    if p then deliver(p, "toast", { k = kind, a = a or {} }) end
end
CMMS.toast = toast

-- a toast for everyone online (Lv 10 reached, a master entering the Hall of Fame)
local function announce(kind, a)
    if not CMM.sv("Announce") then return end
    for _, p in pairs(online) do deliver(p, "toast", { k = kind, a = a or {} }) end
end
CMMS.announce = announce

-- public board for the Hall of Fame page: rebuilt at most every 30 s, sent only to whoever asks
local board, boardAt = nil, -1
local function buildBoard()
    local power, live, n = {}, {}, 0
    for bid in pairs(CMM.BRANCH) do power[bid] = 0 end
    for _, r in pairs(S.p) do
        if type(r) == "table" and r.br and CMM.BRANCH[r.br] and not r.test then
            n = n + 1
            power[r.br] = power[r.br] + CM.num(r.pts, 0)
            live[#live + 1] = r
        end
    end
    table.sort(live, function(a, b) return CM.num(a.pts, 0) > CM.num(b.pts, 0) end)
    local top = nil
    if CMM.sv("LiveBoard") then
        top = {}
        for i = 1, math.min(5, #live) do
            local r = live[i]
            local lv, into, need = CMM.level(r.pts)
            top[i] = { n = r.name, br = r.br, lv = lv, fr = lv >= 10 and 1 or into / math.max(1, need) }
        end
    end
    local hof = {}
    for i = 1, math.min(12, #S.hof) do hof[i] = CM.copy(S.hof[i]) end
    return { now = now(), n = n, power = power, live = top, hof = hof }
end
function CMMS.board()
    local t = nowMs()
    if not board or t - boardAt > 30000 or t < boardAt then
        board = buildBoard()
        boardAt = t
    end
    return board
end
function CMMS.boardDirty() board = nil end

local function nameOfKey(k)
    local r = k and S.p[k]
    if r and r.name then return r.name end
    return k
end

local function snap(k, p)
    local r = recOf(k)
    local o = {
        br = r.br, pts = r.pts, wal = r.wal, pre = CM.copy(r.pre), life = r.life,
        mentor = r.mentorOf and nameOfKey(r.mentorOf) or nil,
        appr = r.appr and nameOfKey(r.appr) or nil,
        apprAt = r.apprAt, bookAt = r.bookAt, now = now(),
        admin = CMMS.isAdmin(p), seen = r.seen or 0, got = math.floor(r.got or 0), x10 = math.floor(r.x10 or 0),
        nj = CM.copy(r.nj or {}),
        test = r.test == true or nil,
    }
    if r.buff and now() < CM.num(r.buff.u, 0) then
        o.buff = { br = r.buff.br, by = r.buff.by, left = CM.num(r.buff.u, 0) - now(), pct = r.buff.pct }
    end
    local inv = invites[k]
    if inv then o.inv = { from = nameOfKey(inv.from), br = S.p[inv.from] and S.p[inv.from].br } end
    local hof = {}
    for i = 1, math.min(5, #S.hof) do hof[i] = CM.copy(S.hof[i]) end
    o.hof = hof
    return o
end

local function flush()
    for k in pairs(dirty) do
        local p = online[k]
        if p then deliver(p, "me", snap(k, p)) end
    end
    dirty = {}
end
CMMS.flush = flush

local function allow(p)
    local k = keyOf(p)
    local t = nowMs()
    local e = rate[k]
    if not e or t - e.t > 1000 then e = { t = t, n = 0 }; rate[k] = e end
    e.n = e.n + 1
    return e.n <= 20
end

-- ===================================================================== items
local function giveItem(p, ft, md)
    local inv = p and p:getInventory()
    local sm = getScriptManager()
    if not inv or not (sm and sm:FindItem(ft)) then return false end
    local ok, item = pcall(instanceItem, ft)
    if not ok or not item then return false end
    if md then
        local d = item:getModData()
        for kk, v in pairs(md) do d[kk] = v end
        if md.cmmTitle and item.setName then pcall(function() item:setName(md.cmmTitle) end) end
    end
    inv:AddItem(item)
    if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
    return true
end

local function removeItem(item)
    local cont = CM.call(item, "getContainer")
    if not cont then return false end
    cont:Remove(item)
    if isServer() and sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, cont, item) end
    return true
end

local function findItemById(p, id)
    local inv = p and p:getInventory()
    if not inv then return nil end
    id = math.floor(CM.num(id, -1))
    local it = CM.call(inv, "getItemWithIDRecursiv", id)
    if it == nil then it = CM.call(inv, "getItemWithID", id) end
    if it == nil then it = CM.call(inv, "getItemById", id) end
    return it
end

-- n items of a type anywhere in the main inventory or worn bags
local function takeItems(p, ft, n)
    if n <= 0 then return true end
    local inv = p:getInventory()
    local list = CM.call(inv, "getAllTypeRecurse", ft)
    if not list or list:size() < n then return false end
    local picked = {}
    for i = 0, n - 1 do picked[#picked + 1] = list:get(i) end
    for i = 1, #picked do removeItem(picked[i]) end
    return true
end

local function countItems(p, ft)
    local inv = p:getInventory()
    return CM.num(CM.call(inv, "getCountTypeRecurse", ft), 0)
end

CMMS.HAMMERS = { "Base.Hammer", "Base.HammerStone", "Base.BallPeenHammer", "Base.ClubHammer", "Base.WoodenMallet" }
local function hasHammer(p)
    local inv = p:getInventory()
    if CM.call(inv, "containsTagRecurse", "Hammer") == true then return true end
    for i = 1, #CMMS.HAMMERS do
        if CM.call(inv, "getFirstTypeRecurse", CMMS.HAMMERS[i]) then return true end
    end
    return false
end
CMMS.hasHammer = hasHammer

local function deliverPending(k)
    local p = online[k]
    local list = S.pend[k]
    if not p or not list or #list == 0 then return end
    local keep = {}
    for i = 1, #list do
        local e = list[i]
        if not giveItem(p, e.ft, e.md) then keep[#keep + 1] = e end
    end
    if #keep > 0 then S.pend[k] = keep else S.pend[k] = nil end
end

local function giveOrQueue(k, ft, md)
    local p = online[k]
    if p and giveItem(p, ft, md) then return true end
    S.pend[k] = S.pend[k] or {}
    table.insert(S.pend[k], { ft = ft, md = md })
    return false
end

-- ===================================================================== mastery points
local function addPoints(k, r, pts, why)
    if pts <= 0 then return end
    local before = lvOf(r)
    r.pts = r.pts + pts
    r.wal = r.wal + pts
    local after = lvOf(r)
    if after > before then
        toast(k, "lvup", { after })
        for i = 1, #CMM.TIERS do
            local t = CMM.TIERS[i]
            if before < t and after >= t then toast(k, "tier", { t }) end
        end
        logLine(nameOfKey(k) .. " mastery " .. tostring(r.br) .. " Lv" .. after .. " (" .. tostring(why) .. ")")
        if before < 10 and after >= 10 and r.br and not r.test then announce("ann10", { nameOfKey(k), r.br }) end
        CMMS.boardDirty()
    end
    dirty[k] = true
end
CMMS.addPoints = addPoints

-- per player per minute ceiling on accepted overflow points (a modified client cannot farm)
local function capped(k, pts)
    local t = nowMs()
    local e = capMin[k]
    if not e or t - e.t >= 60000 then e = { t = t, n = 0 }; capMin[k] = e end
    local room = math.max(0, CMM.sv("CapPerMinute") - e.n)
    if pts > room then pts = room end
    e.n = e.n + pts
    return pts
end

local function giveXp(p, perk, amount)
    if amount <= 0 then return false end
    if addXpNoMultiplier then
        local ok = pcall(addXpNoMultiplier, p, perk, amount)
        if ok then return true end
    end
    if addXp then
        local ok = pcall(addXp, p, perk, amount)
        if ok then return true end
    end
    local ok = pcall(function() p:getXp():AddXP(perk, amount, false, false, true) end)
    return ok
end
CMMS.giveXp = giveXp

local function overflow(k, r, p, bid, perk, amount)
    local pts = capped(k, CMM.points(perk, amount))
    r.seen = (r.seen or 0) + 1
    if pts <= 0 then return end
    if r.br == nil then
        local had = r.pre[bid] ~= nil
        r.pre[bid] = (r.pre[bid] or 0) + pts
        if not had then toast(k, "canpick", { bid }) end
        dirty[k] = true
    elseif r.br == bid then
        act[k] = { br = bid, t = nowMs() }
        addPoints(k, r, pts, "xp")
    end
end

-- skill XP below level 10: mentor aura, apprentice link and master book add on top
local function studentXp(k, r, p, bid, perk, id, amount)
    local pct = 0
    local t = nowMs()
    local mk = r.mentorOf
    local mr = mk and S.p[mk]
    if mr and online[mk] and mr.br == bid and lvOf(mr) >= 3 then
        pct = CMM.sv("ApprenticeBonus")
    end
    if pct == 0 then
        local okP, px, py = pcall(function() return p:getX(), p:getY() end)
        if okP then
            local radius = CMM.sv("MentorRadius")
            local window = CMM.sv("MentorWindow") * 1000
            for ok2, mp in pairs(online) do
                if ok2 ~= k then
                    local r2 = S.p[ok2]
                    local a = act[ok2]
                    if r2 and r2.br == bid and a and a.br == bid and t - a.t <= window and lvOf(r2) >= 3
                        and alive(mp) and CMM.dist(mp, px, py) <= radius then
                        pct = CMM.sv("MentorBonus")
                        break
                    end
                end
            end
        end
    end
    local b = r.buff
    if b and b.br == bid and now() < CM.num(b.u, 0) then pct = pct + CM.num(b.pct, CMM.sv("BookBonus")) end
    if pct <= 0 then return end
    local bonus = amount * pct / 100
    CMMNJ.flat(true)
    local given = giveXp(p, perk, bonus)
    CMMNJ.flat(false)
    if given then
        r.got = (r.got or 0) + bonus
        -- journals must not write this XP down (see CMM_NoJournal)
        r.nj = r.nj or {}
        r.nj[id] = (r.nj[id] or 0) + bonus
        dirty[k] = true
    end
end

-- ===================================================================== XP capture
-- From the B42 engine (IsoGameCharacter.XP.AddXP): a perk that already holds its level-10 XP returns
-- at once - no XP and no Lua event - and the AddXP event only fires where XP is applied (server or
-- single player), never on an MP client. So everything is counted here, on the server:
--   level 10: the grant is caught before the engine drops it (addXp globals, crafting, exercise)
--   below 10: the AddXP event (mentor / apprentice / book bonuses)
local NO_CUT = { Sprinting = true, Fitness = true, Strength = true }
local NO_UP = { Fitness = true, Strength = true }
local PACIFIST = { SmallBlade = true, LongBlade = true, SmallBlunt = true, Spear = true, Blunt = true, Axe = true, Aiming = true }

local function hasTrait(p, name)
    local ok, v = pcall(function()
        local t = CharacterTrait and CharacterTrait[name]
        if t == nil then return false end
        return p:hasTrait(t)
    end)
    return ok and v == true
end

-- the multiplier the engine puts on a grant (profession / trait boost, learner traits, sandbox)
function CMMS.xpScale(p, perk, id)
    local f = 1
    local found, v = false, 0
    pcall(function()
        local b = p:getDescriptor():getXPBoostMap():get(perk)
        if b ~= nil then found = true; v = CM.num(b, 0) end
    end)
    if found then
        if v == 0 then
            if not NO_CUT[id] then f = 0.25 end
        elseif v == 1 then
            if id == "Sprinting" then f = 1.25 end
        elseif v == 2 then
            if not NO_UP[id] then f = 1.33 end
        elseif not NO_UP[id] then
            f = 1.66
        end
    elseif not NO_CUT[id] then
        f = 0.25
    end
    if not NO_UP[id] and hasTrait(p, "FAST_LEARNER") then f = f * 1.3 end
    if not NO_CUT[id] and hasTrait(p, "SLOW_LEARNER") then f = f * 0.7 end
    if PACIFIST[id] and hasTrait(p, "PACIFIST") then f = f * 0.75 end
    if Perks and Perks.Crafting and hasTrait(p, "CRAFTY") and CM.call(perk, "getParent") == Perks.Crafting then f = f * 1.3 end
    local m = CM.num(CM.call(CM.call(p, "getXp"), "getMultiplier", perk), 1)
    if m > 1 then f = f * m end
    local mc = SandboxVars and SandboxVars.MultiplierConfig
    if type(mc) == "table" then
        if mc.GlobalToggle == true or mc.GlobalToggle == nil then
            if mc.Global ~= nil then f = f * CM.num(mc.Global, 1) end
        elseif mc[id] ~= nil then
            f = f * CM.num(mc[id], 1)
        end
    end
    return f
end

-- XP granted to a branch perk that is already full at level 10 -> mastery overflow
function CMMS.atCap(chr, perk, amount, scaled)
    if not S or chr == nil or perk == nil or not CMM.sv("Enabled") then return 0 end
    amount = CM.num(amount, 0)
    if amount <= 0 or not instanceof(chr, "IsoPlayer") then return 0 end
    local id = CMM.perkId(perk)
    local bid = id and CMM.PERK_BRANCH[id]
    if not bid or CMM.perkLevel(chr, perk) < 10 then return 0 end
    if scaled then amount = amount * CMMS.xpScale(chr, perk, id) end
    -- the part that still fits under the level-10 cap is real skill XP
    local cap = CM.num(CM.call(perk, "getTotalXpForLevel", 10), 0)
    if cap > 0 then
        local cur = CM.num(CM.call(CM.call(chr, "getXp"), "getXP", perk), cap)
        if cur < cap then amount = amount - (cap - cur) end
    end
    if amount <= 0 then return 0 end
    local k = keyOf(chr)
    local r = recOf(k, nameOf(chr))
    r.x10 = (r.x10 or 0) + amount
    overflow(k, r, chr, bid, perk, amount)
    return amount
end

-- below level 10: the engine reports the XP it applied (after its multipliers)
local busy = false
function CMMS.onXp(chr, perk, amount)
    if busy or not S or chr == nil or perk == nil or not CMM.sv("Enabled") then return end
    amount = CM.num(amount, 0)
    if amount <= 0 or not instanceof(chr, "IsoPlayer") then return end
    local id = CMM.perkId(perk)
    local bid = id and CMM.PERK_BRANCH[id]
    if not bid or CMM.perkLevel(chr, perk) >= 10 then return end
    local k = keyOf(chr)
    -- the bonus itself comes back through this event: busy keeps it from being bonus-ed again
    busy = true
    local ok, err = pcall(studentXp, k, recOf(k, nameOf(chr)), chr, bid, perk, id, amount)
    busy = false
    if not ok then CMM.log("xp bonus error: " .. tostring(err)) end
end

local warned = {}
local function safeCap(tag, chr, perk, amount, scaled)
    local ok, err = pcall(CMMS.atCap, chr, perk, amount, scaled)
    if not ok and not warned[tag] then
        warned[tag] = true
        CMM.log("xp hook (" .. tag .. ") error: " .. tostring(err))
    end
end

-- crafting / building: the engine gives the recipe's XP awards (CraftRecipe.addXP) inside
-- logic:performCurrentRecipe() when it returns true (HandcraftLogic / BuildLogic -> CraftRecipeData.perform).
-- Vanilla does not hand that result back, and the craft history entry is not exposed to Lua, so for the
-- length of the call the logic object is swapped for a proxy that forwards every method to it and
-- remembers how many times performCurrentRecipe succeeded.
function CMMS.craftXp(chr, recipe)
    local n = CM.num(CM.call(recipe, "getXPAwardCount"), 0)
    for i = 0, n - 1 do
        local a = CM.call(recipe, "getXPAward", i)
        local amt = CM.num(a and CM.call(a, "getAmount"), 0)
        if amt > 0 then safeCap("craft", chr, CM.call(a, "getPerk"), amt, true) end
    end
end

local function proxyLogic(real, box)
    return setmetatable({}, { __index = function(_, k)
        local f = real[k]
        if f == nil then return nil end
        if k == "performCurrentRecipe" then
            return function(_, ...)
                local ok = f(real, ...)
                if ok then box.n = box.n + 1 end
                return ok
            end
        end
        return function(_, ...) return f(real, ...) end
    end })
end

local function wrapCraft(cls, method, field, label)
    if type(cls) ~= "table" or rawget(cls, "__cmmXp" .. method) then return false end
    local orig = rawget(cls, method)
    if type(orig) ~= "function" then return false end
    cls["__cmmXp" .. method] = true
    cls[method] = function(self, ...)
        local chr = self and self.character
        local recipe = self and self.craftRecipe
        local real = self and self[field]
        if not S or not chr or not recipe or real == nil then return orig(self, ...) end
        local box = { n = 0 }
        self[field] = proxyLogic(real, box)
        local ok, r1, r2, r3 = pcall(orig, self, ...)
        self[field] = real
        if not ok then error(r1) end
        for _ = 1, box.n do
            local ok2, err = pcall(CMMS.craftXp, chr, recipe)
            if not ok2 and not warned[label] then warned[label] = true; CMM.log("xp hook (" .. label .. ") error: " .. tostring(err)) end
        end
        return r1, r2, r3
    end
    return true
end

-- exercise: Fitness.incStats gives Strength (arms 4, chest 2) and Fitness (legs 4, abs 2) per rep,
-- times the exercise xpMod (the level bonus is 0 at level 10)
local STIFF = { arms = { "Strength", 4 }, chest = { "Strength", 2 }, legs = { "Fitness", 4 }, abs = { "Fitness", 2 } }
function CMMS.exerciseXp(chr, kind)
    local defs = FitnessExercises and FitnessExercises.exercisesType
    local def = defs and defs[kind]
    if not def then return end
    local sum = { Strength = 0, Fitness = 0 }
    local parts = CM.split(def.stiffness or "", ",")
    for i = 1, #parts do
        local s = STIFF[parts[i]]
        if s then sum[s[1]] = sum[s[1]] + s[2] end
    end
    local mod = CM.num(def.xpMod, 1)
    for id, v in pairs(sum) do
        local a = math.floor(v * mod)
        if a > 0 then safeCap("exercise", chr, CMM.perkOf(id), a, true) end
    end
end

local function wrapExercise(cls)
    if type(cls) ~= "table" or rawget(cls, "__cmmXp") then return false end
    local orig = rawget(cls, "exeLooped")
    if type(orig) ~= "function" then return false end
    cls.__cmmXp = true
    cls.exeLooped = function(self, ...)
        if S and self and self.character then
            local ok, err = pcall(CMMS.exerciseXp, self.character, self.exeDataType)
            if not ok and not warned.exe then warned.exe = true; CMM.log("xp hook (exercise) error: " .. tostring(err)) end
        end
        return orig(self, ...)
    end
    return true
end

-- the Lua addXp globals (weapon hits, most timed actions, other mods): addXp gets the engine
-- multipliers, addXpNoMultiplier does not
local function wrapGlobal(name, scaled)
    if CMMS["__xp_" .. name] then return false end
    local orig = _G[name]
    if type(orig) ~= "function" and type(orig) ~= "userdata" then return false end
    CMMS["__xp_" .. name] = true
    _G[name] = function(chr, perk, amount, ...)
        if S then safeCap(name, chr, perk, amount, scaled) end
        return orig(chr, perk, amount, ...)
    end
    return true
end

function CMMS.hookXp()
    local n = 0
    if wrapGlobal("addXp", true) then n = n + 1 end
    if wrapGlobal("addXpNoMultiplier", false) then n = n + 1 end
    if wrapCraft(ISHandcraftAction, "performRecipe", "logic", "handcraft") then n = n + 1 end
    if wrapCraft(ISBuildIsoEntity, "create", "buildPanelLogic", "build") then n = n + 1 end
    if wrapExercise(ISFitnessAction) then n = n + 1 end
    if n > 0 then CMM.log("xp hooks installed: " .. n) end
end

-- ===================================================================== builder
-- extra HP + maker tag on a freshly built structure; false when already tagged
local function applyBuild(o, name, lv)
    if not CMM.isThump(o) then return false end
    local md = CM.call(o, "getModData")
    if not md or md.cmmBy then return false end
    local h, m = CMM.hp(o)
    if m <= 0 then return false end
    local b = CMM.buildBonus(lv)
    local nm = math.floor(m * (1 + b) + 0.5)
    pcall(function() o:setMaxHealth(nm) end)
    pcall(function() o:setHealth(math.floor(h * (1 + b) + 0.5)) end)
    md.cmmBy = name
    md.cmmLv = lv
    pcall(function() o:transmitModData() end)
    pcall(function() o:syncIsoThumpable() end)
    pcall(function() o:sync() end)
    return true
end
CMMS.applyBuild = applyBuild

-- scan the 3x3 around a build spot; `before` = objects that were already there (nil = any untouched one)
function CMMS.tagAround(chr, x, y, z, before)
    local r = CMMS.recFor(chr)
    if not CMM.has(r, "build", 1) then return 0 end
    local lv = lvOf(r)
    local n = 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = CMM.square(x + dx, y + dy, z)
            local list = sq and CM.call(sq, "getObjects")
            if list then
                for i = 0, list:size() - 1 do
                    local o = list:get(i)
                    local fresh
                    if before then
                        fresh = not before[o]
                    else
                        local h, m = CMM.hp(o)
                        fresh = m > 0 and h >= m
                    end
                    if fresh and applyBuild(o, r.name or nameOf(chr), lv) then n = n + 1 end
                end
            end
        end
    end
    if n > 0 then
        r.built = (r.built or 0) + n
        logLine(tostring(r.name) .. " built " .. n .. " structure(s) at " .. math.floor(x) .. "," .. math.floor(y))
    end
    return n
end

local function fixBones(p)
    local bd = CM.call(p, "getBodyDamage")
    local parts = bd and CM.call(bd, "getBodyParts")
    if not parts then return end
    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        if CM.num(CM.call(bp, "getFractureTime"), 0) > 0 then
            pcall(function() bp:setFractureTime(0) end)
            pcall(function() bp:setSplintFactor(0) end)
            if isServer() and syncBodyPart and BodyPartSyncPacket then
                pcall(syncBodyPart, bp, BodyPartSyncPacket.BD_fractureTime)
            end
        end
    end
end
CMMS.fixBones = fixBones

-- ===================================================================== admin test mode
-- An admin plays a throw-away copy of the record: any branch, any level, every node, reset at will.
-- The real record (and the mechanic seal flag) is kept in S.test and put back on exit or on death.
-- A test record never reaches the board, the Hall of Fame or the Lv 10 announcement.
local function unlinkStale(k)
    local r = S.p[k]
    for ok2, r2 in pairs(S.p) do
        if ok2 ~= k and type(r2) == "table" then
            if r2.mentorOf == k and (not r or r.appr ~= ok2) then r2.mentorOf = nil; dirty[ok2] = true end
            if r2.appr == k and (not r or r.mentorOf ~= ok2) then r2.appr = nil; dirty[ok2] = true end
        end
    end
    if r then
        if r.appr and (not S.p[r.appr] or S.p[r.appr].mentorOf ~= k) then r.appr = nil end
        if r.mentorOf and (not S.p[r.mentorOf] or S.p[r.mentorOf].appr ~= k) then r.mentorOf = nil end
    end
end

local function testOn(k)
    local r = S.p[k]
    if not r or r.test then return false end
    S.test[k] = { rec = CM.copy(r), seal = S.seal and S.seal[k], t = now() }
    r.test = true
    act[k] = nil
    dirty[k] = true
    CMMS.boardDirty()
    return true
end

local function testOff(k)
    local e = S.test[k]
    if not e then
        if S.p[k] then S.p[k].test = nil; dirty[k] = true end
        return false
    end
    local real = e.rec or { pts = 0, wal = 0, pre = {}, life = 1, born = now() }
    real.test = nil
    S.p[k] = real
    if S.seal then S.seal[k] = e.seal end
    S.test[k] = nil
    invites[k] = nil
    act[k] = nil
    unlinkStale(k)
    dirty[k] = true
    CMMS.boardDirty()
    return true
end
CMMS.testOn = testOn
CMMS.testOff = testOff

-- ===================================================================== death / legacy
local function addHof(r)
    local lv = lvOf(r)
    if lv < 1 or not r.br then return end
    table.insert(S.hof, { n = r.name, br = r.br, lv = lv, t = now(), life = r.life or 1 })
    if lv >= 10 then announce("annhof", { r.name, r.br, lv }) end
    CMMS.boardDirty()
    table.sort(S.hof, function(a, b)
        if a.lv ~= b.lv then return a.lv > b.lv end
        return CM.num(a.t, 0) > CM.num(b.t, 0)
    end)
    while #S.hof > 30 do table.remove(S.hof) end
end

local function onDeath(k)
    local r = S.p[k]
    if not r then return end
    if r.deadAt and now() - r.deadAt < 60 then return end
    if r.test then
        testOff(k)
        r = S.p[k]
        logLine(tostring(r.name) .. " died in mastery test mode: the real record goes on")
    end
    local lv = lvOf(r)
    addHof(r)
    local keep = CM.clamp(CMM.sv("DeathKeep"), 0, 100)
    local nr = { pts = 0, wal = 0, pre = {}, life = (r.life or 1) + 1, born = now(), name = r.name, deadAt = now(),
        bookAt = r.bookAt }
    if keep > 0 and r.br then
        nr.br = r.br
        nr.pts = r.pts * keep / 100
    end
    if lv >= 10 and r.br then
        -- legacy: the next life starts in the same branch at Lv1, the apprentice inherits a last book
        nr.br = r.br
        nr.pts = math.max(nr.pts, CMM.total(1))
        nr.legacy = true
        if r.appr then
            giveOrQueue(r.appr, CMM.BOOK_TYPE, { cmmBr = r.br, cmmBy = r.name, cmmLv = lv,
                cmmH = CMM.sv("LegacyBookHours"), cmmLast = true })
            toast(r.appr, "lastbook", { r.name })
        end
    end
    if r.appr and S.p[r.appr] and S.p[r.appr].mentorOf == k then S.p[r.appr].mentorOf = nil; dirty[r.appr] = true end
    if r.mentorOf and S.p[r.mentorOf] and S.p[r.mentorOf].appr == k then S.p[r.mentorOf].appr = nil; dirty[r.mentorOf] = true end
    S.p[k] = nr
    invites[k] = nil
    act[k] = nil
    dirty[k] = true
    logLine(tostring(r.name) .. " died at mastery " .. tostring(r.br) .. " Lv" .. lv .. (nr.legacy and " (legacy)" or ""))
end
CMMS.onDeath = onDeath

-- ===================================================================== commands
local H = {}

function H.hello(p, args)
    local k = keyOf(p)
    recOf(k, nameOf(p))
    deliver(p, "hi", { b = CMM.BUILD })
    deliverPending(k)
    dirty[k] = true
end

function H.board(p, args)
    deliver(p, "board", CMMS.board())
end

-- old clients reported XP from the client AddXP event; XP is counted on the server now (see XP capture)
function H.xp(p, args) end

-- server-side check that the player has a level-10 perk in the branch; trust the client only
-- when this server cannot read perk levels at all
local function canPick(p, bid)
    if CMM.eligible(p)[bid] then return true end
    local readable = CMM.perkLevel(p, CMM.perkOf("Strength")) > 0 or CMM.perkLevel(p, CMM.perkOf("Fitness")) > 0
    return not readable
end

function H.pick(p, args)
    local bid = tostring(args.br or "")
    if not CMM.BRANCH[bid] then return end
    local k = keyOf(p)
    local r = recOf(k, nameOf(p))
    if r.br and not r.test then toast(k, "locked", { r.br }); return end
    if not r.test and not canPick(p, bid) then toast(k, "notready", { bid }); return end
    r.br = bid
    local banked = CM.num(r.pre[bid], 0)
    r.pre = {}
    r.pts = r.pts + banked
    r.wal = r.wal + banked
    toast(k, "picked", { bid })
    logLine(r.name .. " picked " .. bid .. " (banked " .. math.floor(banked) .. ")")
    dirty[k] = true
end

local function findOnline(name)
    local want = CM.ukey(CM.trim(name))
    if want == "" then return nil, nil end
    if online[want] then return want, online[want] end
    return nil, nil
end

function H.invite(p, args)
    local k = keyOf(p)
    local r = recOf(k, nameOf(p))
    if not r.br or lvOf(r) < 3 then return end
    local tk, tp = findOnline(args.name)
    if not tk or tk == k then toast(k, "nobody", {}); return end
    local tr = recOf(tk, nameOf(tp))
    if tr.mentorOf == k then return end
    local swap = CMM.sv("ApprenticeSwapDays") * 86400
    if r.apprAt and now() - r.apprAt < swap then
        toast(k, "swapwait", { swap - (now() - r.apprAt) })
        return
    end
    invites[tk] = { from = k, t = nowMs() }
    toast(tk, "invited", { r.name, r.br })
    toast(k, "invsent", { tr.name or tk })
    dirty[tk] = true
end

function H.answer(p, args)
    local k = keyOf(p)
    local inv = invites[k]
    invites[k] = nil
    dirty[k] = true
    if not inv or nowMs() - inv.t > 300000 then return end
    local mr = S.p[inv.from]
    if args.ok ~= true then toast(inv.from, "declined", { nameOf(p) }); return end
    if not mr or not mr.br or lvOf(mr) < 3 then return end
    local r = recOf(k, nameOf(p))
    if r.mentorOf and S.p[r.mentorOf] and S.p[r.mentorOf].appr == k then
        S.p[r.mentorOf].appr = nil; dirty[r.mentorOf] = true
    end
    if mr.appr and S.p[mr.appr] and S.p[mr.appr].mentorOf == inv.from then
        S.p[mr.appr].mentorOf = nil; dirty[mr.appr] = true
    end
    mr.appr = k
    mr.apprAt = now()
    r.mentorOf = inv.from
    toast(inv.from, "newappr", { r.name })
    toast(k, "newmentor", { mr.name })
    dirty[inv.from] = true
    logLine(tostring(mr.name) .. " took " .. tostring(r.name) .. " as apprentice")
end

function H.leave(p, args)
    local k = keyOf(p)
    local r = recOf(k, nameOf(p))
    if r.mentorOf then
        local mr = S.p[r.mentorOf]
        if mr and mr.appr == k then mr.appr = nil; dirty[r.mentorOf] = true end
        r.mentorOf = nil
    end
    if r.appr then
        local ar = S.p[r.appr]
        if ar and ar.mentorOf == k then ar.mentorOf = nil; dirty[r.appr] = true end
        r.appr = nil
    end
    dirty[k] = true
end

function H.book(p, args)
    local k = keyOf(p)
    local r = recOf(k, nameOf(p))
    if not r.br or lvOf(r) < 5 then return end
    local wait = CMM.sv("BookDays") * 86400
    if r.bookAt and now() - r.bookAt < wait then
        toast(k, "bookwait", { wait - (now() - r.bookAt) })
        return
    end
    if giveItem(p, CMM.BOOK_TYPE, { cmmBr = r.br, cmmBy = r.name, cmmLv = lvOf(r), cmmH = CMM.sv("BookHours") }) then
        r.bookAt = now()
        toast(k, "bookdone", { r.br })
        logLine(r.name .. " wrote a master book (" .. r.br .. ")")
        dirty[k] = true
    end
end

function H.read(p, args)
    local k = keyOf(p)
    local item = findItemById(p, args.id)
    if not item then return end
    if CM.call(item, "getFullType") ~= CMM.BOOK_TYPE then return end
    local md = item:getModData()
    local bid = md.cmmBr
    if not CMM.BRANCH[bid] then return end
    local hours = CM.num(md.cmmH, CMM.sv("BookHours"))
    local by = md.cmmBy or "?"
    if not removeItem(item) then return end
    local r = recOf(k, nameOf(p))
    r.buff = { br = bid, by = by, u = now() + math.floor(hours * 3600), pct = CMM.sv("BookBonus") }
    toast(k, "bookread", { by, bid })
    dirty[k] = true
end

function H.repair(p, args)
    local k = keyOf(p)
    local r = recOf(k, nameOf(p))
    if not CMM.has(r, "build", 5) then return end
    local o = CMM.objAt(args.x, args.y, args.z, args.i)
    if not CMM.isThump(o) then return end
    local sq = CM.call(o, "getSquare")
    if not sq or CMM.dist(p, CM.num(sq:getX(), 0) + 0.5, CM.num(sq:getY(), 0) + 0.5) > 3 then return end
    local h, m = CMM.hp(o)
    if m <= 0 or h >= m then return end
    local planks, nails = CMM.repairCost((m - h) / m)
    if not hasHammer(p) then toast(k, "nohammer", {}); return end
    if countItems(p, "Base.Plank") < planks or countItems(p, "Base.Nails") < nails then
        toast(k, "nomats", { planks, nails })
        return
    end
    takeItems(p, "Base.Plank", planks)
    takeItems(p, "Base.Nails", nails)
    pcall(function() o:setHealth(m) end)
    pcall(function() o:syncIsoThumpable() end)
    pcall(function() o:sync() end)
    toast(k, "repaired", { math.floor(m) })
end

-- an MP client built something (its build ran client side): tag what appears around it shortly
function H.built(p, args)
    local x, y, z = CM.num(args.x, 0), CM.num(args.y, 0), CM.num(args.z, 0)
    if CMM.dist(p, x, y) > 8 then return end
    if #builds > 200 then return end
    builds[#builds + 1] = { k = keyOf(p), x = x, y = y, z = z, t = nowMs(), tries = 0 }
end

function H.dead(p, args)
    if alive(p) then return end
    onDeath(keyOf(p))
end

-- admin: test helpers (target = self unless a name is given)
local A = {}
function A.adm(p, args)
    local tk = keyOf(p)
    local tp = p
    if args.name and args.name ~= "" then
        tk, tp = findOnline(args.name)
        if not tk then return end
    end
    local r = recOf(tk, nameOf(tp))
    local op = tostring(args.op or "")
    if op == "bar" then
        addPoints(tk, r, CMM.sv("BarPoints") * CM.int(args.n, 1, 1, 1000), "admin")
    elseif op == "lv" then
        local n = CM.int(args.n, 0, 0, 10)
        r.pts = CMM.total(n)
        dirty[tk] = true
    elseif op == "reset" then
        S.p[tk] = { pts = 0, wal = 0, pre = {}, life = r.life or 1, born = now(), name = r.name, test = r.test }
        -- in test mode the mechanic seal can be tried again (the real flag comes back on exit)
        if r.test and S.seal then S.seal[tk] = nil end
        if not r.test then unlinkStale(tk) end
        dirty[tk] = true
    elseif op == "unpick" then
        r.br = nil
        dirty[tk] = true
    elseif op == "book" then
        r.bookAt = nil
        dirty[tk] = true
    elseif op == "test" then
        if testOn(tk) then toast(tk, "teston", {}) end
    elseif op == "testoff" then
        if testOff(tk) then toast(tk, "testoff", {}) end
    elseif op == "br" then
        -- test mode only: switch to any branch, keeping the level
        local bid = tostring(args.br or "")
        if not r.test or not CMM.BRANCH[bid] then return end
        r.br = bid
        r.pre = {}
        act[tk] = nil
        dirty[tk] = true
    end
    logLine("[" .. nameOf(p) .. "] admin " .. op .. (args.br and (" " .. tostring(args.br)) or "")
        .. " on " .. tostring(r.name) .. (r.test and " (test)" or ""))
end

local function onClientCommand(module, command, p, args)
    if module ~= MOD or not p or not S then return end
    if args ~= nil and type(args) ~= "table" then return end
    args = args or {}
    if not allow(p) then return end
    rebuildOnline()
    local h = H[command]
    local admin = false
    if not h then h = A[command]; admin = true end
    if not h then return end
    if admin and not CMMS.isAdmin(p) then
        CMM.log("rejected admin command " .. tostring(command) .. " from " .. nameOf(p))
        return
    end
    local ok, err = pcall(h, p, args)
    if not ok then CMM.log("command " .. tostring(command) .. " failed: " .. tostring(err)) end
    flush()
end
CMMS.onClientCommand = onClientCommand

-- ===================================================================== ticking
local function slowTick()
    -- deliver queued items, expire invites
    for k in pairs(S.pend) do deliverPending(k) end
    local t = nowMs()
    for k, inv in pairs(invites) do
        if t - inv.t > 300000 then invites[k] = nil; dirty[k] = true end
    end
end

local function onTick()
    if not S then return end
    local ms = nowMs()
    if ms - lastTick < 1000 then return end
    lastTick = ms
    rebuildOnline()
    for k, p in pairs(online) do
        local r = S.p[k]
        if r and CMM.has(r, "build", 10) and alive(p) then pcall(fixBones, p) end
    end
    if #builds > 0 then
        local keep = {}
        for i = 1, #builds do
            local b = builds[i]
            if ms - b.t >= 1500 then
                b.tries = b.tries + 1
                local p = online[b.k]
                local n = 0
                if p then n = CMMS.tagAround(p, b.x, b.y, b.z, nil) end
                if n == 0 and b.tries < 3 then b.t = ms; keep[#keep + 1] = b end
            else
                keep[#keep + 1] = b
            end
        end
        builds = keep
    end
    if ms - lastSlow >= 10000 then
        lastSlow = ms
        pcall(slowTick)
    end
    flush()
end
CMMS.onTick = onTick

local function onBoot()
    S = ModData.getOrCreate(MOD)
    defaults(S)
    CMM.log("server ready " .. CMM.BUILD .. " players=" .. CM.count(S.p))
end
CMMS.onBoot = onBoot

Events.OnInitGlobalModData.Add(function()
    local ok, err = pcall(onBoot)
    if not ok then CMM.log("boot error: " .. tostring(err)) end
end)
Events.OnClientCommand.Add(onClientCommand)
Events.AddXP.Add(function(chr, perk, amount)
    local ok, err = pcall(CMMS.onXp, chr, perk, amount)
    if not ok and not CMMS.xpWarned then
        CMMS.xpWarned = true
        CMM.log("AddXP error: " .. tostring(err))
    end
end)
-- after every mod's lua is in (another mod may wrap the same functions while loading)
pcall(CMMS.hookXp)
if Events.OnGameBoot then Events.OnGameBoot.Add(function() pcall(CMMS.hookXp) end) end
if Events.OnServerStarted then Events.OnServerStarted.Add(function() pcall(CMMS.hookXp) end) end
if Events.OnGameStart then Events.OnGameStart.Add(function() pcall(CMMS.hookXp) end) end
Events.OnTick.Add(function()
    local ok, err = pcall(onTick)
    if not ok then CMM.log("tick error: " .. tostring(err)) end
end)

if Events.LevelPerk then Events.LevelPerk.Add(function(chr, perk, level, increased)
    if not S or not increased or not chr then return end
    pcall(function()
        if not instanceof(chr, "IsoPlayer") then return end
        local k = keyOf(chr)
        local r = S.p[k]
        if not r or not r.mentorOf then return end
        local mr = S.p[r.mentorOf]
        local bid = CMM.PERK_BRANCH[CMM.perkId(perk)]
        if mr and bid and mr.br == bid and lvOf(mr) >= 3 then
            addPoints(r.mentorOf, mr, CMM.sv("ApprenticeLevelPoints"), "apprentice")
            toast(r.mentorOf, "apprlv", { r.name, CM.num(level, 0) })
        end
    end)
end) end

if Events.OnCharacterDeath then Events.OnCharacterDeath.Add(function(ch)
    if not S or not ch then return end
    pcall(function()
        if instanceof(ch, "IsoPlayer") then onDeath(keyOf(ch)) end
    end)
end) end

return CMMS
