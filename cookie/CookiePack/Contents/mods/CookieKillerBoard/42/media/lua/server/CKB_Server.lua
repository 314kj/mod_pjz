-- Cookie Killer Board - server authority (dedicated server, host, or single player)
-- The server already counts every zombie kill on the killer (IsoPlayer zombieKills, saved with the
-- character). This file reads that counter every 2 s for each online player, keeps it per life,
-- banks it on death, and notes which weapon was in hand when the counter went up.
if isClient() and not isServer() then return end

require "CKB_Shared"

CKBS = CKBS or {}
local MOD = CKB.MOD
local S = nil            -- global ModData "CookieKillerBoard": { v, p = { ukey -> record } }
local seen = {}          -- ukey -> the game's kill counter at the last look (this server session)
local cache = {}         -- list key -> { at, list } sorted board
local rate = {}          -- ukey .. cmd -> ms of the last request
local lastPoll = 0
local POLL_MS = 2000
local CACHE_MS = 2500
local MAX_W = 16         -- weapon kinds kept per tally (the smallest one goes first)
local MAX_STEP = 300     -- a bigger jump between two looks is a load/sync, not kills

-- record: { n = name, life = kills this life, bank = kills of earlier lives, d = deaths,
--           wl = { ft = kills } this life, wa = { ft = kills } all lives, hs = hours survived,
--           seenAt, deadAt, hide = true (admin took it off the board) }

local function now() return CM.now() end
local function nowMs()
    if getTimestampMs then
        local ok, v = pcall(getTimestampMs)
        if ok and v then return v end
    end
    return now() * 1000
end

local function defaults(s)
    s.v = s.v or 1
    s.p = s.p or {}
end

function CKBS.state() return S end

local function nameOf(p)
    local ok, n = pcall(function() return p:getUsername() end)
    if ok and n and n ~= "" then return tostring(n) end
    return nil
end
local function keyOf(p)
    local n = nameOf(p)
    if not n then return nil end
    return CM.ukey(n)
end
CKBS.keyOf = keyOf

local function recOf(k, name)
    local r = S.p[k]
    if not r then
        r = { life = 0, bank = 0, d = 0, wl = {}, wa = {} }
        S.p[k] = r
    end
    if name then r.n = name end
    r.life = CM.num(r.life, 0)
    r.bank = CM.num(r.bank, 0)
    r.d = CM.num(r.d, 0)
    if type(r.wl) ~= "table" then r.wl = {} end
    if type(r.wa) ~= "table" then r.wa = {} end
    return r
end

local function alive(p)
    if not p then return false end
    local ok, dead = pcall(function() return p:isDead() end)
    return ok and not dead
end

local STAFF_LEVELS = { admin = true, moderator = true, overseer = true, gm = true }
function CKBS.isAdmin(p)
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
CKBS.send = deliver

-- ===================================================================== counting
-- what was in hand when the counter went up
local function weaponKey(p)
    local inCar = false
    pcall(function() inCar = p:getVehicle() ~= nil end)
    if inCar then return CKB.CAR end
    local ft = nil
    pcall(function()
        local it = p:getPrimaryHandItem()
        if it and instanceof(it, "HandWeapon") then ft = it:getFullType() end
    end)
    if not ft or ft == "" or ft == "Base.BareHands" then return CKB.FIST end
    return tostring(ft)
end
CKBS.weaponKey = weaponKey

local function tally(t, key, n)
    t[key] = CM.num(t[key], 0) + n
    if CM.count(t) > MAX_W then
        local lo, ln = nil, nil
        for k, v in pairs(t) do
            local x = CM.num(v, 0)
            if k ~= key and (ln == nil or x < ln) then lo, ln = k, x end
        end
        if lo ~= nil then t[lo] = nil end
    end
end

local function hoursOf(p)
    local ok, h = pcall(function() return p:getHoursSurvived() end)
    if ok and h ~= nil then return CM.num(h, nil) end
    return nil
end

local function killsOf(p)
    local ok, z = pcall(function() return p:getZombieKills() end)
    if ok and z ~= nil then return math.floor(CM.num(z, 0)) end
    return nil
end

-- the life is over: its kills go to the bank, a new life starts at 0
local function newLife(k, r, why)
    r.bank = CM.num(r.bank, 0) + CM.num(r.life, 0)
    r.life = 0
    r.d = CM.num(r.d, 0) + 1
    r.wl = {}
    r.hs = nil
    r.deadAt = now()
    seen[k] = nil
    cache = {}
    CKB.log(tostring(r.n or k) .. " life over (" .. tostring(why) .. "): bank=" .. tostring(r.bank) .. " deaths=" .. tostring(r.d))
end

-- read the game's counter for one player and move the record along
local function look(p, k, r)
    local zk = killsOf(p)
    if zk == nil then return end
    if zk < 0 then zk = 0 end
    local hs = hoursOf(p)
    local prev = seen[k]
    if prev == nil then
        -- first look this session: line the record up with the game's counter
        if zk < r.life then
            if hs ~= nil and r.hs ~= nil and hs + 0.5 < r.hs then
                newLife(k, r, "new character")
            end
            -- otherwise the save went back a little (crash / rollback): follow the game
        end
        if zk ~= r.life then cache = {} end
        r.life = zk          -- kills made while the board was not looking have no known weapon
    elseif zk > prev then
        local n = zk - prev
        if n <= MAX_STEP then
            local w = weaponKey(p)
            tally(r.wl, w, n)
            tally(r.wa, w, n)
        end
        r.life = zk
        cache = {}
    elseif zk < prev then
        -- the counter went down while online: a new character after a death we did not hear about
        if hs ~= nil and r.hs ~= nil and hs + 0.5 < r.hs then
            newLife(k, r, "counter reset")
        end
        r.life = zk
        cache = {}
    end
    seen[k] = zk
    if hs ~= nil then r.hs = hs end
    r.seenAt = now()
end
CKBS.look = look

local function lookAt(p)
    if not S or not p then return nil end
    local k = keyOf(p)
    if not k or k == "" then return nil end
    local r = recOf(k, nameOf(p))
    if alive(p) then look(p, k, r) end
    return k, r
end
CKBS.lookAt = lookAt

local function onDeath(p)
    if not S or not p then return end
    local k = keyOf(p)
    if not k or k == "" then return end
    local r = recOf(k, nameOf(p))
    if r.deadAt and now() - r.deadAt < 60 then return end
    r.seenAt = r.seenAt or now()
    -- the kills since the last look still count for the life that just ended
    if seen[k] ~= nil then pcall(look, p, k, r) end
    newLife(k, r, "death")
end
CKBS.onDeath = onDeath

local function forOnline(fn)
    if CM.isSP() then
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

local function poll()
    forOnline(function(p)
        local ok, err = pcall(lookAt, p)
        if not ok then CKB.log("look error: " .. tostring(err)) end
    end)
end
CKBS.poll = poll

-- ===================================================================== board
local function totalOf(r) return CM.num(r.bank, 0) + CM.num(r.life, 0) end

local function valOf(r, tab)
    if tab == "all" then return totalOf(r) end
    return CM.num(r.life, 0)
end

local function sorted(tab, withHidden)
    local ck = tab .. (withHidden and "+h" or "")
    local t = nowMs()
    local c = cache[ck]
    if c and t - c.at < CACHE_MS then return c.list end
    local list = {}
    for k, r in pairs(S.p) do
        if (withHidden or not r.hide) and valOf(r, tab) > 0 then
            list[#list + 1] = { k = k, r = r, v = valOf(r, tab), t = totalOf(r) }
        end
    end
    table.sort(list, function(a, b)
        if a.v ~= b.v then return a.v > b.v end
        if a.t ~= b.t then return a.t > b.t end
        return a.k < b.k
    end)
    cache[ck] = { at = t, list = list }
    return list
end
CKBS.sorted = sorted

local function rowOf(k, r, rank, tab)
    return { i = rank, k = k, n = r.n or k, l = CM.num(r.life, 0), t = totalOf(r), d = CM.num(r.d, 0),
        w = CKB.topWeapon(tab == "all" and r.wa or r.wl), hid = r.hide and true or nil }
end

function CKBS.board(p, tab, adm)
    tab = tab == "all" and "all" or "life"
    local k, r = lookAt(p)
    local list = sorted(tab, adm)
    local rows = {}
    local rank = 0
    local myRank = nil
    local hidden = 0
    for i = 1, #list do
        local e = list[i]
        if e.r.hide then
            -- staff only: the hidden players that would sit inside the top rows, marked, to put them back
            if adm and rank < CKB.TOP and hidden < 4 then
                hidden = hidden + 1
                rows[#rows + 1] = rowOf(e.k, e.r, "-", tab)
            end
        else
            rank = rank + 1
            if rank <= CKB.TOP then rows[#rows + 1] = rowOf(e.k, e.r, rank, tab) end
            if e.k == k then myRank = rank end
        end
    end
    local me = nil
    if k and r then me = rowOf(k, r, myRank, tab) end
    return { tab = tab, rows = rows, me = me, n = rank, adm = adm and true or nil }
end

-- ===================================================================== commands
local H = {}
CKBS.H = H

function H.board(p, args)
    local adm = args.adm == true and CKBS.isAdmin(p)
    deliver(p, "board", CKBS.board(p, args.tab, adm))
end

function H.dead(p, args)
    if alive(p) then return end
    onDeath(p)
end

-- admin: take a player off the board / put back, or clear the bank, deaths and weapons
function H.adm(p, args)
    if not CKBS.isAdmin(p) then return end
    local k = CM.ukey(args.k)
    local r = S.p[k]
    if not r then return end
    if args.op == "hide" then
        r.hide = (not r.hide) or nil
    elseif args.op == "reset" then
        r.bank = 0
        r.d = 0
        r.wl = {}
        r.wa = {}
    else
        return
    end
    cache = {}
    CKB.log("admin " .. tostring(nameOf(p)) .. " " .. tostring(args.op) .. " " .. tostring(r.n or k)
        .. (r.hide and " (hidden)" or ""))
    deliver(p, "adm", { op = args.op, n = r.n or k, hide = r.hide and true or nil })
end

local function onClientCommand(module, command, p, args)
    if module ~= MOD or not S or not p then return end
    local h = H[command]
    if not h then return end
    local k = keyOf(p) or "?"
    local t = nowMs()
    local rk = k .. ":" .. tostring(command)
    if rate[rk] and t - rate[rk] < 400 then return end
    rate[rk] = t
    local ok, err = pcall(h, p, args or {})
    if not ok then CKB.log("command " .. tostring(command) .. " error: " .. tostring(err)) end
end
CKBS.onClientCommand = onClientCommand

-- ===================================================================== boot / tick
local function onTick()
    if not S then return end
    local t = nowMs()
    if t - lastPoll < POLL_MS then return end
    lastPoll = t
    poll()
end
CKBS.onTick = onTick

-- ===================================================================== seed (players the board has not seen yet)
-- Zomboid/Lua/CookieKillerBoard_seed.txt, made from players.db while the server is off or from a copy:
--   line 1: ckb-seed <id>
--   then one player per line: username <TAB> kills <TAB> hours survived <TAB> dead (1/0)
-- Read once per <id>. A player the board already has is left alone (live numbers are newer).
-- A dead row is a character that died and was not remade yet: its kills go to the bank, 1 death.
local SEED_FILE = "CookieKillerBoard_seed.txt"

local function splitTabs(line)
    local out = {}
    local from = 1
    while true do
        local at = string.find(line, "\t", from, true)
        if not at then
            out[#out + 1] = string.sub(line, from)
            break
        end
        out[#out + 1] = string.sub(line, from, at - 1)
        from = at + 1
    end
    return out
end

function CKBS.importSeed()
    local r = getFileReader(SEED_FILE, false)
    if not r then return 0 end
    local head = r:readLine()
    local id = nil
    if head and string.sub(head, 1, 9) == "ckb-seed " then id = string.sub(head, 10) end
    if not id or id == "" or S.seed == id then
        r:close()
        return 0
    end
    local added = 0
    while true do
        local line = r:readLine()
        if not line then break end
        local f = splitTabs(line)
        local name = f[1]
        local kills = math.floor(CM.num(f[2], -1))
        local hours = CM.num(f[3], nil)
        local dead = f[4] == "1"
        if name and name ~= "" and kills >= 0 then
            local k = CM.ukey(name)
            if not S.p[k] then
                local rec = { n = name, life = 0, bank = 0, d = 0, wl = {}, wa = {}, seed = id }
                if dead then
                    rec.bank = kills
                    rec.d = 1
                else
                    rec.life = kills
                    rec.hs = hours
                end
                S.p[k] = rec
                added = added + 1
            end
        end
    end
    r:close()
    S.seed = id
    cache = {}
    CKB.log("seed " .. tostring(id) .. ": added " .. tostring(added) .. " players")
    return added
end

-- 1.0.0 also counted NPC deaths (A-Life survivors are IsoPlayers): drop records that were never
-- an online player, never seeded, and hold no kills
local function dropGhosts()
    local gone = {}
    for k, r in pairs(S.p) do
        if not r.seenAt and not r.seed and CM.num(r.life, 0) == 0 and CM.num(r.bank, 0) == 0 then
            gone[#gone + 1] = k
        end
    end
    for _, k in ipairs(gone) do S.p[k] = nil end
    if #gone > 0 then CKB.log("dropped " .. #gone .. " non-player records") end
end
CKBS.dropGhosts = dropGhosts

local function onBoot()
    S = ModData.getOrCreate(MOD)
    defaults(S)
    seen = {}
    cache = {}
    pcall(dropGhosts)
    local ok, err = pcall(CKBS.importSeed)
    if not ok then CKB.log("seed error: " .. tostring(err)) end
    CKB.log("server ready " .. CKB.BUILD .. " players=" .. CM.count(S.p))
end
CKBS.onBoot = onBoot

Events.OnInitGlobalModData.Add(function()
    local ok, err = pcall(onBoot)
    if not ok then CKB.log("boot error: " .. tostring(err)) end
end)
Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(function()
    local ok, err = pcall(onTick)
    if not ok then CKB.log("tick error: " .. tostring(err)) end
end)
-- NPC mods (A-Life survivors) are IsoPlayers too: only a real connected player counts
local function isRealPlayer(ch)
    if CM.isSP() then return ch == getSpecificPlayer(0) end
    local list = getOnlinePlayers and getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            if list:get(i) == ch then return true end
        end
    end
    local k = keyOf(ch)
    return k ~= nil and seen[k] ~= nil
end
CKBS.isRealPlayer = isRealPlayer

if Events.OnCharacterDeath then Events.OnCharacterDeath.Add(function(ch)
    if not S or not ch then return end
    pcall(function()
        if instanceof(ch, "IsoPlayer") and isRealPlayer(ch) then onDeath(ch) end
    end)
end) end

return CKBS
