-- Cookie Express : server side
-- Reads paid orders from Zomboid/Lua/CookieExpress_inbox.txt, keeps them pending per player,
-- and hands items over when the player claims them. Every hand-over is appended to
-- Zomboid/Lua/CookieExpress_outbox.txt, which is also the memory of what was already claimed.
if isClient() then return end

require "CookieExpress/CKX_Shared"

local C = CKX.Codec
CKX.S = CKX.S or {}
local S = CKX.S

S.INBOX  = "CookieExpress_inbox.txt"
S.OUTBOX = "CookieExpress_outbox.txt"
S.CONFIG = "CookieExpress_config.txt"

S.DEFAULTS = {
    pollSeconds = 29,
    autoPopup = true,
    splash = true,
    vehicleRepair = true,
    vehicleFullFuel = true,
    vehicleGiveKey = true,
    maxCommandsPerSecond = 7,
}

S.ready = false
S.cfg = {}
S.orders = {}        -- id -> order
S.orderIds = {}      -- inbox order
S.claimed = {}       -- "id#idx" -> true
S.slipUsed = {}      -- "id#idx#s" -> true
S.seen = {}          -- id -> true
S.rejected = {}      -- "id#idx" -> true (already logged as X)
S.cancelledEarly = {}
S.cancelLogged = {}  -- id -> true (K already written)
S.badLines = {}      -- raw line -> true (logged once)
S.index = nil        -- code body -> { kind, ft, dup }
S.lastPoll = 0
S.rate = {}          -- username -> { t, n }

local function log(m) CKX.log(m) end

-- ------------------------------------------------------------------ files
local function readLines(name)
    local ok, r = pcall(getFileReader, name, false)
    if not ok or not r then return {} end
    local out = {}
    local line = r:readLine()
    while line do
        out[#out + 1] = line
        line = r:readLine()
    end
    r:close()
    return out
end

local function appendLine(name, line)
    local ok, w = pcall(getFileWriter, name, true, true)
    if not ok or not w then
        log("cannot write " .. name)
        return false
    end
    w:writeln(line)
    w:close()
    return true
end

local function nowSec()
    local ok, v = pcall(getTimestamp)
    if ok and type(v) == "number" then return v end
    return os.time()
end

-- whole seconds as plain digits (tostring of a big double can turn scientific)
local function secStr()
    local n = math.floor(nowSec())
    local out = ""
    if n <= 0 then return "0" end
    while n > 0 do
        local d = n - math.floor(n / 10) * 10
        out = tostring(d) .. out
        n = math.floor(n / 10)
    end
    return out
end

local function outbox(kind, orderId, idx, userKey, item, info)
    appendLine(S.OUTBOX, C.makeLine({ kind, orderId, tostring(idx), userKey or "-", item or "-",
        secStr(), C.escape(info or "") }))
end
S.outbox = outbox

-- ------------------------------------------------------------------ config
local function toBool(v, d)
    if v == "true" or v == "1" or v == "yes" then return true end
    if v == "false" or v == "0" or v == "no" then return false end
    return d
end

function S.loadConfig()
    local lines = readLines(S.CONFIG)
    if #lines == 0 then
        local ok, w = pcall(getFileWriter, S.CONFIG, true, false)
        if ok and w then
            w:writeln("# Cookie Express server config. Edit while the server runs; it is re-read on every poll.")
            for _, k in ipairs({ "pollSeconds", "autoPopup", "splash", "vehicleRepair", "vehicleFullFuel",
                                 "vehicleGiveKey", "maxCommandsPerSecond" }) do
                w:writeln(k .. "=" .. tostring(S.DEFAULTS[k]))
            end
            w:close()
        end
    end
    local cfg = {}
    for k, v in pairs(S.DEFAULTS) do cfg[k] = v end
    for _, line in ipairs(lines) do
        line = C.trim(line)
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            local eq = string.find(line, "=", 1, true)
            if eq then
                local k = C.trim(string.sub(line, 1, eq - 1))
                local v = C.trim(string.sub(line, eq + 1))
                local d = S.DEFAULTS[k]
                if type(d) == "boolean" then cfg[k] = toBool(v, d)
                elseif type(d) == "number" then cfg[k] = tonumber(v) or d end
            end
        end
    end
    if cfg.pollSeconds < 5 then cfg.pollSeconds = 5 end
    S.cfg = cfg
end

-- ------------------------------------------------------------------ code index
local function vehicleFullName(v)
    local ok, n = pcall(function() return v:getFullName() end)
    if ok and n and n ~= "" then return n end
    local ok2, n2 = pcall(function() return v:getModule():getName() .. "." .. v:getName() end)
    if ok2 then return n2 end
    return nil
end

function S.buildIndex()
    local idx, items, vehicles, dup = {}, 0, 0, 0
    local sm = getScriptManager()
    local list = sm:getAllItems()
    for i = 0, list:size() - 1 do
        local ft = list:get(i):getFullName()
        local b = C.codeBody("i", ft)
        if idx[b] then idx[b].dup = true; dup = dup + 1 else idx[b] = { kind = "i", ft = ft } end
        items = items + 1
    end
    local okV, vl = pcall(function() return sm:getAllVehicleScripts() end)
    if okV and vl then
        for i = 0, vl:size() - 1 do
            local fn = vehicleFullName(vl:get(i))
            if fn then
                local b = C.codeBody("v", fn)
                if idx[b] then idx[b].dup = true; dup = dup + 1 else idx[b] = { kind = "v", ft = fn } end
                vehicles = vehicles + 1
            end
        end
    end
    S.index = idx
    log("code index: " .. items .. " items, " .. vehicles .. " vehicles, " .. dup .. " collisions")
end

function S.resolve(kind, body)
    if not S.index then S.buildIndex() end
    local e = S.index[body]
    if not e then return nil, "unknown code" end
    if e.dup then return nil, "ambiguous code" end
    if e.kind ~= kind then return nil, "wrong code type" end
    return e.ft
end

-- ------------------------------------------------------------------ outbox replay
function S.replayOutbox()
    local n = 0
    for _, line in ipairs(readLines(S.OUTBOX)) do
        local f, cnt = C.split(C.trim(line), "|")
        if cnt == 9 and f[1] == C.MAGIC then
            local head = string.sub(C.trim(line), 1, #C.trim(line) - #f[9] - 1)
            if C.lineSum(head) == f[9] then
                local kind, id, idx = f[2], f[3], f[4]
                if kind == "C" then S.claimed[id .. "#" .. idx] = true
                elseif kind == "U" then S.claimed[id .. "#" .. idx] = nil
                elseif kind == "V" then S.slipUsed[id .. "#" .. idx] = true
                elseif kind == "S" then S.seen[id] = true
                elseif kind == "X" then S.rejected[id .. "#" .. idx] = true
                elseif kind == "K" then S.cancelLogged[id] = true end
                n = n + 1
            end
        end
    end
    log("outbox replay: " .. n .. " records")
end

-- ------------------------------------------------------------------ inbox
local function lineKey(o, i) return o.id .. "#" .. i end

function S.addOrder(o)
    o.lines = {}
    for i, it in ipairs(o.items) do
        local ln = { idx = i, kind = it.kind, body = it.body, n = it.n, code = C.pretty(it.kind, it.body) }
        local ft, why = S.resolve(it.kind, it.body)
        if ft then
            ln.ft = ft
        else
            ln.bad = why
            local k = lineKey(o, i)
            if not S.rejected[k] then
                S.rejected[k] = true
                outbox("X", o.id, i, o.userKey, ln.code .. "*" .. ln.n, why)
                log("order " .. o.id .. " line " .. i .. " rejected: " .. why .. " (" .. ln.code .. ")")
            end
        end
        o.lines[i] = ln
    end
    o.items = nil
    if S.cancelledEarly[o.id] then o.cancelled = true end
    S.orders[o.id] = o
    S.orderIds[#S.orderIds + 1] = o.id
end

-- returns list of user keys whose pending list changed
function S.readInbox()
    local changed = {}
    for _, raw in ipairs(readLines(S.INBOX)) do
        local o, why = C.parseInboxLine(raw)
        if o then
            local cur = S.orders[o.id]
            if o.cancel then
                if cur and not cur.cancelled then
                    cur.cancelled = true
                    changed[cur.userKey] = true
                    if not S.cancelLogged[cur.id] then
                        S.cancelLogged[cur.id] = true
                        outbox("K", cur.id, 0, cur.userKey, "-", "cancelled")
                        log("order " .. cur.id .. " cancelled")
                    end
                elseif not cur then
                    S.cancelledEarly[o.id] = true
                end
            elseif not cur then
                S.addOrder(o)
                changed[o.userKey] = "new"
            elseif cur.userKey ~= o.userKey and not S.badLines[raw] then
                S.badLines[raw] = true
                log("duplicate order id " .. o.id .. " ignored")
            end
        elseif why ~= "skip" and why ~= "partial" and not S.badLines[raw] then
            S.badLines[raw] = true
            log("bad inbox line ignored: " .. tostring(why))
        end
    end
    return changed
end

-- ------------------------------------------------------------------ players
local function userKeyOf(player)
    local ok, u = pcall(function() return player:getUsername() end)
    if not ok or not u then return nil end
    return string.lower(C.escape(u))   -- names match ignoring A-Z case
end
S.userKeyOf = userKeyOf

function S.onlinePlayers()
    if CKX.isSP() then
        local p = getSpecificPlayer(0)
        return p and { p } or {}
    end
    local out, list = {}, getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    end
    return out
end

function S.findOnline(userKey)
    for _, p in ipairs(S.onlinePlayers()) do
        if userKeyOf(p) == userKey then return p end
    end
    return nil
end

local function vehicleDisplayName(fullName)
    local short = fullName
    local ok, script = pcall(function() return getScriptManager():getVehicle(fullName) end)
    if ok and script then short = script:getName() end
    local key = "IGUI_VehicleName" .. tostring(short)
    local t = getText(key)
    if t and t ~= key then return t end
    return short
end
S.vehicleDisplayName = vehicleDisplayName

-- pending entries for one user, in inbox order
function S.pendingFor(userKey)
    local list = {}
    for _, id in ipairs(S.orderIds) do
        local o = S.orders[id]
        if o.userKey == userKey and not o.cancelled then
            for _, ln in ipairs(o.lines) do
                if ln.ft and not S.claimed[lineKey(o, ln.idx)] then
                    list[#list + 1] = { o = o.id, i = ln.idx, k = ln.kind, ft = ln.ft, n = ln.n,
                                        note = o.note or "", code = ln.code }
                end
            end
        end
    end
    return list
end

function S.markSeen(userKey)
    for _, id in ipairs(S.orderIds) do
        local o = S.orders[id]
        if o.userKey == userKey and not o.cancelled and not S.seen[id] then
            S.seen[id] = true
            outbox("S", id, 0, userKey, "-", "shown")
        end
    end
end

function S.sendList(player, reason)
    local uk = userKeyOf(player)
    if not uk then return end
    local list = S.pendingFor(uk)
    if #list > 0 and (reason == "arrive" or reason == "login") then S.markSeen(uk) end
    CKX.toClient(player, "list", { items = list, reason = reason, autoPopup = S.cfg.autoPopup, splash = S.cfg.splash })
end

-- ------------------------------------------------------------------ poll
function S.init()
    if S.ready then return end
    S.ready = true
    S.loadConfig()
    S.replayOutbox()
    S.buildIndex()
    S.poll(true)
    log("ready v" .. CKX.VERSION .. " (" .. CKX.BUILD .. "), " .. #S.orderIds .. " orders loaded")
end

function S.poll(force)
    if not S.ready then S.init() return end
    local now = CKX.nowMs()
    if not force and now - S.lastPoll < S.cfg.pollSeconds * 1000 then return end
    S.lastPoll = now
    S.loadConfig()
    local changed = S.readInbox()
    for uk, how in pairs(changed) do
        local p = S.findOnline(uk)
        if p then S.sendList(p, how == "new" and "arrive" or "refresh") end
    end
end

-- ------------------------------------------------------------------ hand-over
local function syncAdd(container, item)
    if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, container, item) end
end
S.syncAdd = syncAdd

local function giveItem(player, ft, n)
    local inv = player:getInventory()
    local given = 0
    for _ = 1, n do
        local ok, item = pcall(instanceItem, ft)
        if ok and item then
            inv:AddItem(item)
            syncAdd(inv, item)
            given = given + 1
        end
    end
    return given
end

local function giveSlips(player, o, ln)
    local inv = player:getInventory()
    local name = vehicleDisplayName(ln.ft)
    local given = 0
    for s = 1, ln.n do
        local ok, item = pcall(instanceItem, CKX.SLIP)
        if ok and item then
            local md = item:getModData()
            md.ckx_v = ln.ft
            md.ckx_o = o.id
            md.ckx_i = ln.idx
            md.ckx_s = s
            local label = getText("UI_CKX_SlipPrefix", name)
            if not label or label == "UI_CKX_SlipPrefix" then label = "Vehicle Slip: " .. name end
            pcall(function()
                item:setName(label)
                item:setCustomName(true)
            end)
            inv:AddItem(item)
            syncAdd(inv, item)
            given = given + 1
        end
    end
    return given, name
end

-- returns ok, label
function S.claimLine(player, orderId, idx)
    local uk = userKeyOf(player)
    local o = S.orders[orderId]
    if not o or o.userKey ~= uk or o.cancelled then return false, "not yours" end
    local ln = o.lines[idx]
    if not ln or not ln.ft then return false, "bad line" end
    local k = lineKey(o, idx)
    if S.claimed[k] then return false, "already claimed" end
    -- claim first, then give: a crash can lose an item but can never duplicate one
    S.claimed[k] = true
    outbox("C", o.id, idx, uk, ln.code .. "*" .. ln.n, ln.ft)
    local given, label
    if ln.kind == "v" then
        given, label = giveSlips(player, o, ln)
    else
        given = giveItem(player, ln.ft, ln.n)
        label = ln.ft
    end
    if given < ln.n then
        outbox("F", o.id, idx, uk, ln.code .. "*" .. ln.n, "given " .. given .. " of " .. ln.n)
        log("order " .. o.id .. " line " .. idx .. " short delivery " .. given .. "/" .. ln.n .. " " .. ln.ft)
        if given == 0 then
            S.claimed[k] = nil
            outbox("U", o.id, idx, uk, ln.code .. "*" .. ln.n, "undo, nothing given")
            return false, "spawn failed"
        end
    end
    return true, label, ln
end

local function rateOk(player)
    local uk = userKeyOf(player) or "?"
    local now = CKX.nowMs()
    local r = S.rate[uk]
    if not r or now - r.t > 1000 then
        S.rate[uk] = { t = now, n = 1 }
        return true
    end
    r.n = r.n + 1
    return r.n <= S.cfg.maxCommandsPerSecond
end

-- ------------------------------------------------------------------ commands
function S.onCommand(player, cmd, args)
    if not player then return end
    if not S.ready then S.init() end
    if not rateOk(player) then return end
    args = args or {}
    if cmd == "hello" then
        S.poll(true)
        S.sendList(player, "login")
    elseif cmd == "refresh" then
        S.sendList(player, "refresh")
    elseif cmd == "claim" then
        local ok, label, ln = S.claimLine(player, tostring(args.o), tonumber(args.i))
        local got = {}
        if ok then got[1] = { ft = ln.ft, n = ln.n, k = ln.kind } end
        CKX.toClient(player, "claimed", { ok = ok, got = got, why = ok and "" or label })
        S.sendList(player, "refresh")
    elseif cmd == "claimAll" then
        local got, fails = {}, 0
        for _, e in ipairs(S.pendingFor(userKeyOf(player))) do
            local ok, _, ln = S.claimLine(player, e.o, e.i)
            if ok then got[#got + 1] = { ft = ln.ft, n = ln.n, k = ln.kind } else fails = fails + 1 end
        end
        CKX.toClient(player, "claimed", { ok = #got > 0, got = got, fails = fails })
        S.sendList(player, "refresh")
    elseif cmd == "useSlip" then
        if S.useSlip then S.useSlip(player, args) end
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= CKX.NET then return end
    S.onCommand(player, command, args)
end

Events.OnClientCommand.Add(onClientCommand)
Events.EveryOneMinute.Add(function() S.poll(false) end)
if Events.OnServerStarted then Events.OnServerStarted.Add(S.init) end
Events.OnGameStart.Add(function() if CKX.isSP() then S.init() end end)
