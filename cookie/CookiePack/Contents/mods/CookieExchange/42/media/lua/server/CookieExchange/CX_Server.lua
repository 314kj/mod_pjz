-- Cookie Exchange : server side
-- Owns every balance. Commands: hello, take (cash items -> wallet), send (to an online player),
-- withdraw (wallet -> bills), players (online names for the send list).
-- Kill cash: a 1-second poll reads each online player's getZombieKills() (the counter
-- KillerBoard trusts) and rolls once per new kill. No item ever drops on the floor.
-- PhunMart sweep (only while MigratePhunMart is on): every PhunMart wallet balance moves here
-- (change cents 1:1, 1 token = $100) and the PhunMart pools are zeroed, bound tokens included,
-- so PhunMart cannot refill them on death.
if isClient() and not isServer() then return end

require "CookieExchange/CX_Const"

local PHUN_KEY = "PhunMart_Wallet"
local POLL_MS = 1000
local SWEEP_MS = 60000
local MAX_KILLS_PER_POLL = 50

local db = nil
local seen = {}          -- username -> last zombie kill count seen this session
local lastPoll, lastSweep = 0, 0
local booted = false

local function nowMs()
    if getTimestampMs then
        local ok, v = pcall(getTimestampMs)
        if ok and v then return v end
    end
    return os.time() * 1000
end

local function stamp()
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M:%S")
    if ok and s then return s end
    return tostring(math.floor(nowMs() / 1000))
end

-- one line per balance change, the audit trail admins read when a player says money vanished
local function audit(line)
    local ok, w = pcall(getFileWriter, CX.LOG, true, true)
    if ok and w then
        w:write(stamp() .. " " .. line .. "\r\n")
        w:close()
    end
end

local function DB()
    if db then return db end
    db = ModData.getOrCreate(CX.DB_KEY)
    db.v = db.v or 1
    db.w = db.w or {}
    return db
end

local function nameOf(p)
    local ok, n = pcall(function() return p:getUsername() end)
    if ok and n and n ~= "" then return n end
    return nil
end

local function acct(name)
    local d = DB()
    local a = d.w[name]
    if not a then
        a = { c = 0 }
        d.w[name] = a
    end
    return a
end

local function add(name, delta, why)
    local a = acct(name)
    a.c = math.floor((a.c or 0) + delta)
    audit(name .. " " .. (delta >= 0 and "+" or "") .. tostring(delta) .. "c " .. tostring(why) .. " -> " .. tostring(a.c) .. "c")
    return a.c
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
    if not name then return nil end
    local lname = string.lower(name)
    forOnline(function(p)
        local n = nameOf(p)
        if n and string.lower(n) == lname then hit = p end
    end)
    return hit
end

local function tell(p, cmd, args)
    if isServer() then
        sendServerCommand(p, CX.MOD, cmd, args or {})
    else
        triggerEvent("OnServerCommand", CX.MOD, cmd, args or {})
    end
end

local function sync(p)
    local n = nameOf(p)
    if not n then return end
    tell(p, "wallet", { c = acct(n).c })
end

-- ------------------------------------------------------------------------------
-- items
-- ------------------------------------------------------------------------------
local function call(o, fn, ...)
    if not o or type(o[fn]) ~= "function" then return nil end
    local ok, v = pcall(o[fn], o, ...)
    if ok then return v end
    return nil
end

local function findItemById(p, id)
    local inv = p and p:getInventory()
    if not inv then return nil end
    id = math.floor(tonumber(id) or -1)
    local it = call(inv, "getItemWithIDRecursiv", id)
    if it == nil then it = call(inv, "getItemWithID", id) end
    if it == nil then it = call(inv, "getItemById", id) end
    return it
end

local function removeItem(item)
    local cont = call(item, "getContainer")
    if not cont then return false end
    cont:Remove(item)
    if isServer() and sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, cont, item) end
    return true
end

local function giveItem(inv, ft, flag)
    local ok, item = pcall(instanceItem, ft)
    if not ok or not item then return false end
    if flag then item:getModData()[CX.FLAG] = true end
    inv:AddItem(item)
    if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
    return true
end

-- ------------------------------------------------------------------------------
-- PhunMart sweep
-- ------------------------------------------------------------------------------
local function phunCents(rec)
    local cur = type(rec) == "table" and type(rec.current) == "table" and rec.current or nil
    if not cur then return 0 end
    local change = math.floor(tonumber(cur.change) or 0)
    local tokens = math.floor(tonumber(cur.tokens) or 0)
    if change < 0 then change = 0 end
    if tokens < 0 then tokens = 0 end
    return change + tokens * 10000, change, tokens
end

local function zeroPhun(rec)
    if type(rec.current) == "table" then
        rec.current.change = 0
        rec.current.tokens = 0
    end
    if type(rec.bound) == "table" then rec.bound.tokens = 0 end
end

-- tell PhunMart's client the new (empty) balance, same call CSP_MythicalRepair makes
local function phunSync(p)
    local pm = PhunMart
    if type(pm) ~= "table" or type(pm.wallet) ~= "table" or type(pm.commands) ~= "table" then return end
    if not pm.commands.getWallet or not isServer() then return end
    pcall(function()
        sendServerCommand(p, pm.name, pm.commands.getWallet, { username = p:getUsername(), wallet = pm.wallet:get(p) })
    end)
end

-- always zero, even with nothing to move: bound tokens left behind would be refilled into
-- current by PhunMart on death and paid out again on the next sweep
local function sweepKey(key, rec)
    local total, change, tokens = phunCents(rec)
    zeroPhun(rec)
    if total <= 0 then return 0 end
    add(key, total, "phunmart change=" .. tostring(change) .. " tokens=" .. tostring(tokens))
    return total
end

local function sweepAll()
    if not CX.opt("MigratePhunMart") then return end
    if not (ModData.exists and ModData.exists(PHUN_KEY)) then return end
    local data = ModData.get(PHUN_KEY)
    if type(data) ~= "table" then return end
    local n, sum = 0, 0
    for key, rec in pairs(data) do
        if type(key) == "string" and type(rec) == "table" then
            local moved = sweepKey(key, rec)
            if moved > 0 then n = n + 1; sum = sum + moved end
        end
    end
    if n > 0 then
        CX.log("PhunMart sweep: " .. tostring(n) .. " wallets, " .. tostring(sum) .. " cents")
        forOnline(function(p) sync(p); phunSync(p) end)
    end
end

-- ------------------------------------------------------------------------------
-- kill cash
-- ------------------------------------------------------------------------------
local function rollKills(n)
    local chance = math.floor(CX.opt("KillCashChance"))
    local lo = math.floor(CX.opt("KillCashMin"))
    local hi = math.floor(CX.opt("KillCashMax"))
    if chance <= 0 or hi <= 0 then return 0 end
    if hi < lo then lo, hi = hi, lo end
    local total = 0
    for _ = 1, n do
        if ZombRand(100) < chance then
            total = total + lo + ZombRand(hi - lo + 1)
        end
    end
    return total
end

local function lookAt(p)
    local n = nameOf(p)
    if not n then return end
    local zk = call(p, "getZombieKills")
    if zk == nil then return end
    zk = math.floor(tonumber(zk) or 0)
    local prev = seen[n]
    seen[n] = zk
    if prev == nil or zk <= prev then return end  -- first look, or a new life reset the counter
    local kills = zk - prev
    if kills > MAX_KILLS_PER_POLL then kills = MAX_KILLS_PER_POLL end
    local dollars = rollKills(kills)
    if dollars <= 0 then return end
    local bal = add(n, dollars * 100, "kill x" .. tostring(kills))
    tell(p, "earn", { d = dollars, c = bal })
end

-- ------------------------------------------------------------------------------
-- commands
-- ------------------------------------------------------------------------------
local function wholeDollars(v)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    v = math.floor(v)
    if v < 1 or v > 100000000 then return nil end
    return v
end

local C = {}

function C.hello(p)
    local n = nameOf(p)
    if not n then return end
    if CX.opt("MigratePhunMart") and ModData.exists and ModData.exists(PHUN_KEY) then
        local data = ModData.get(PHUN_KEY)
        if type(data) == "table" and type(data[n]) == "table" then
            if sweepKey(n, data[n]) > 0 then phunSync(p) end
        end
    end
    if CX.shopServer and CX.shopServer.convertOldSlips then
        local ok, err = pcall(CX.shopServer.convertOldSlips, p)
        if not ok then CX.log("kuraya slips error: " .. tostring(err)) end
    end
    if CX.shopServer and CX.shopServer.giveKit then
        local ok, err = pcall(CX.shopServer.giveKit, p)
        if not ok then CX.log("starter kit error: " .. tostring(err)) end
    end
    sync(p)
end

function C.players(p)
    local me = nameOf(p)
    local list = {}
    forOnline(function(q)
        local n = nameOf(q)
        if n and n ~= me then list[#list + 1] = n end
    end)
    table.sort(list, function(a, b) return string.lower(a) < string.lower(b) end)
    tell(p, "players", { list = list })
end

-- args.ids = item ids in the player's inventory, args.auto = true from the background scan
function C.take(p, args)
    local n = nameOf(p)
    if not n or type(args) ~= "table" or type(args.ids) ~= "table" then return end
    if args.auto and not CX.opt("AutoConvert") then return end
    local sum, took, skip, count = 0, {}, {}, 0
    for _, id in pairs(args.ids) do
        count = count + 1
        if count > CX.MAX_TAKE then break end
        local it = findItemById(p, id)
        if it then
            local v = CX.cents(it:getFullType())
            local flagged = it:getModData()[CX.FLAG] == true
            if v and not (args.auto and flagged) and removeItem(it) then
                sum = sum + v
                took[#took + 1] = id
            elseif args.auto then
                skip[#skip + 1] = id   -- the client's copy may not show the flag: stop it asking again
            end
        end
    end
    if sum > 0 then
        local bal = add(n, sum, (args.auto and "auto" or "take") .. " x" .. tostring(#took))
        tell(p, "took", { ids = took, skip = skip, d = sum, c = bal, auto = args.auto == true })
    else
        tell(p, "took", { ids = {}, skip = skip, d = 0 })
    end
end

function C.send(p, args)
    local n = nameOf(p)
    if not n or type(args) ~= "table" then return end
    local amt = wholeDollars(args.amt)
    if not amt then tell(p, "result", { key = "BadAmount" }); return end
    local q = findOnline(args.to)
    local to = q and nameOf(q)
    if not to then tell(p, "result", { key = "NotOnline" }); return end
    if to == n then tell(p, "result", { key = "SelfSend" }); return end
    local cents = amt * 100
    if acct(n).c < cents then tell(p, "result", { key = "NoMoney" }); return end
    add(n, -cents, "send to " .. to)
    add(to, cents, "from " .. n)
    sync(p)
    sync(q)
    tell(p, "result", { key = "Sent", d = cents, who = to, ok = true })
    tell(q, "got", { d = cents, who = n })
end

function C.withdraw(p, args)
    local n = nameOf(p)
    if not n or type(args) ~= "table" then return end
    local amt = wholeDollars(args.amt)
    if not amt then tell(p, "result", { key = "BadAmount" }); return end
    local cents = amt * 100
    if acct(n).c < cents then tell(p, "result", { key = "NoMoney" }); return end
    local parts, pieces = CX.breakdown(amt)
    if pieces > CX.MAX_PIECES then tell(p, "result", { key = "TooMany" }); return end
    local inv = p:getInventory()
    if not inv then return end
    add(n, -cents, "withdraw")
    local given = 0
    for i = 1, #parts do
        for _ = 1, parts[i].n do
            if giveItem(inv, parts[i].ft, true) then given = given + parts[i].v end
        end
    end
    if given < amt then
        -- an item failed to spawn: pay the rest back so nothing is lost
        add(n, (amt - given) * 100, "withdraw refund")
    end
    sync(p)
    tell(p, "result", { key = "Withdrawn", d = given * 100, ok = true })
end

local function onClientCommand(module, command, player, args)
    if module ~= CX.MOD or not player then return end
    local fn = C[command]
    if not fn then return end
    local ok, err = pcall(fn, player, args)
    if not ok then CX.log("command " .. tostring(command) .. " error: " .. tostring(err)) end
end

local function onTick()
    local t = nowMs()
    if not booted then
        booted = true
        DB()
        lastSweep = t
        local ok, err = pcall(sweepAll)
        if not ok then CX.log("sweep error: " .. tostring(err)) end
        CX.log("server ready, wallets=" .. tostring((function() local k = 0; for _ in pairs(DB().w) do k = k + 1 end; return k end)()))
    end
    if t - lastPoll >= POLL_MS then
        lastPoll = t
        forOnline(function(p)
            local ok, err = pcall(lookAt, p)
            if not ok then CX.log("kill poll error: " .. tostring(err)) end
        end)
    end
    if t - lastSweep >= SWEEP_MS then
        lastSweep = t
        local ok, err = pcall(sweepAll)
        if not ok then CX.log("sweep error: " .. tostring(err)) end
    end
end

-- other Cookie mods (Mythical repair, shop) go through these, never through ModData directly
CX.server = {
    balance = function(name) return acct(name).c end,
    -- name -> cents, for the admin wallet list
    all = function()
        local out = {}
        for k, a in pairs(DB().w) do out[k] = a.c or 0 end
        return out
    end,
    add = function(name, cents, why) local c = add(name, cents, why); local q = findOnline(name); if q then sync(q) end; return c end,
    charge = function(name, cents, why)
        if acct(name).c < cents then return false end
        add(name, -cents, why)
        local q = findOnline(name)
        if q then sync(q) end
        return true
    end,
}

-- helpers the shop file (CX_ShopServer) shares with the wallet
CX.srv = {
    nameOf = nameOf, tell = tell, sync = sync, call = call, audit = audit,
    findItemById = findItemById, removeItem = removeItem, findOnline = findOnline, forOnline = forOnline,
}

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)
