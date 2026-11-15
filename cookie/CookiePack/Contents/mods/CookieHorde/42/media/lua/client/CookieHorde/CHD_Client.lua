-- Cookie Horde - client: mirrors the server's presets and spots, sends admin requests
if isServer() and not isClient() then return end

require "CookieHorde/CHD_Shared"
require "CM_Client"

CHDC = CHDC or {}
CHDC.presets = CHDC.presets or {}   -- array of presets (sorted by name on the server)
CHDC.points = CHDC.points or {}     -- array of running spots
CHDC.est = nil                     -- last lag estimate for the draft
CHDC.draft = CHDC.draft or { r = 4, total = 100, perMin = 60, pid = "" }
local MOD = CHD.MOD

local function ms()
    if getTimestampMs then return getTimestampMs() end
    return CM.now() * 1000
end
CHDC.ms = ms

function CHDC.player() return getSpecificPlayer(0) end

function CHDC.send(cmd, args)
    local p = CHDC.player()
    if not p then return end
    sendClientCommand(p, MOD, cmd, args or {})
end

-- a number for display: 35 not "35.0", 1.25 stays 1.25
function CHDC.n(v)
    local x = tonumber(v)
    if x == nil then return tostring(v or "") end
    if x == math.floor(x) then
        local s = tostring(math.floor(x))
        local dot = string.find(s, ".", 1, true)
        if dot then s = string.sub(s, 1, dot - 1) end
        return s
    end
    return tostring(math.floor(x * 100 + 0.5) / 100)
end

function CHDC.txt(key, a, b, c)
    if type(a) == "number" then a = CHDC.n(a) end
    if type(b) == "number" then b = CHDC.n(b) end
    if type(c) == "number" then c = CHDC.n(c) end
    if a == nil then return getText(key) end
    if b == nil then return getText(key, tostring(a)) end
    if c == nil then return getText(key, tostring(a), tostring(b)) end
    return getText(key, tostring(a), tostring(b), tostring(c))
end
local T = CHDC.txt

function CHDC.isAdmin()
    if CM.isSP() then return true end
    return CMC and CMC.isAdmin and CMC.isAdmin() or false
end

-- rows arrive as a table with 1..n keys; copy into a plain array
local function arr(t)
    local out = {}
    if type(t) ~= "table" then return out end
    local i = 1
    while t[i] ~= nil do
        out[#out + 1] = t[i]
        i = i + 1
    end
    return out
end
CHDC.arr = arr

function CHDC.presetById(id)
    for i = 1, #CHDC.presets do
        if CHDC.presets[i].id == id then return CHDC.presets[i] end
    end
    return nil
end

-- ===================================================================== draft spot + estimate
CHDC.estDirtyAt = nil
CHDC.estAskedAt = 0

function CHDC.touchDraft()
    CHDC.estDirtyAt = ms()
    CHDC.est = nil
end

function CHDC.setSpot(x, y, z)
    local d = CHDC.draft
    d.x, d.y, d.z = math.floor(x), math.floor(y), math.floor(z or 0)
    CHDC.est = nil
    CHDC.touchDraft()
end

function CHDC.askEstimate()
    local d = CHDC.draft
    if d.x == nil then return end
    CHDC.estAskedAt = ms()
    CHDC.estDirtyAt = nil
    CHDC.send("estimate", { x = d.x, y = d.y, z = d.z, total = d.total, perMin = d.perMin })
end

-- called every frame while the window shows the spawn tab
function CHDC.pumpEstimate()
    local t = ms()
    local since = t - CHDC.estAskedAt
    if since < 1100 then return end      -- the server answers at most once a second
    if CHDC.estDirtyAt and t - CHDC.estDirtyAt > 400 then
        CHDC.askEstimate()
    elseif CHDC.draft.x ~= nil and CHDC.est == nil and since > 1500 then
        CHDC.askEstimate()                 -- no answer for the current values: ask again
    elseif CHDC.draft.x ~= nil and since > 15000 then
        CHDC.askEstimate()
    end
end

-- one spot per click: a second click within 1.5 s would start a second spot
function CHDC.canStart()
    return CHDC.draft.x ~= nil and ms() - (CHDC.startedAt or 0) > 1500
end

function CHDC.start()
    local d = CHDC.draft
    if not CHDC.canStart() then return end
    CHDC.startedAt = ms()
    CHDC.send("start", { x = d.x, y = d.y, z = d.z, r = d.r, total = d.total, perMin = d.perMin, pid = d.pid })
end

-- one save per click: a quick second click on a new preset would make two
function CHDC.canSave()
    return ms() - (CHDC.savedAt or 0) > 1500
end

function CHDC.savePreset(pre)
    if not CHDC.canSave() then return false end
    CHDC.savedAt = ms()
    CHDC.send("savePreset", { preset = pre })
    return true
end

-- ===================================================================== sluggish zombies
-- The server sends the online ids of sluggish zombies; this client scales their movement.
-- touched remembers every zombie object slowed here, so a reused object gets its speed back.
CHDC.slow = CHDC.slow or {}     -- online id -> factor
local slowN = 0
local touched = {}              -- zombie -> factor applied
local touchedN = 0
local lastSlowPass = 0
local SLOW_PASS_MS = 1000

local function applySlow(args)
    if args.all then
        CHDC.slow = {}
        slowN = 0
    end
    local add = arr(args.add)
    for i = 1, #add - 1, 2 do
        local id, f = add[i], CM.num(add[i + 1], 1)
        if CHDC.slow[id] == nil then slowN = slowN + 1 end
        CHDC.slow[id] = f
    end
    for _, id in ipairs(arr(args.del)) do
        if CHDC.slow[id] ~= nil then
            CHDC.slow[id] = nil
            slowN = slowN - 1
        end
    end
end
CHDC.applySlow = applySlow

function CHDC.slowPass()
    if slowN <= 0 and touchedN <= 0 then return end
    local t = ms()
    if t - lastSlowPass < SLOW_PASS_MS then return end
    lastSlowPass = t
    -- zombies slowed here: back to normal when gone, dead, reused for another id or taken off the list
    local keep, keepN = {}, 0
    for z, f in pairs(touched) do
        local ok, stay = pcall(function()
            return not z:isDead() and z:getCurrentSquare() ~= nil and CHDC.slow[z:getOnlineID()] == f
        end)
        if ok and stay then
            keep[z] = f
            keepN = keepN + 1
        else
            pcall(function() z:setMoveDelta(1) end)
        end
    end
    touched, touchedN = keep, keepN
    if slowN <= 0 then return end
    -- listed zombies this client has loaded and not slowed yet
    local cell = getCell()
    if not cell then return end
    local list = cell:getZombieList()
    if not list then return end
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if touched[z] == nil then
            local f = CHDC.slow[z:getOnlineID()]
            if f then
                z:setMoveDelta(f)
                touched[z] = f
                touchedN = touchedN + 1
            end
        end
    end
end

local helloSent = false
Events.OnTick.Add(function()
    if not helloSent and CHDC.player() then
        helloSent = true
        if not CM.isSP() then CHDC.send("hello", {}) end
    end
    local ok, err = pcall(CHDC.slowPass)
    if not ok then CHD.log("slow pass error: " .. tostring(err)) end
end)

-- ===================================================================== server answers
local TOAST_COLOR = { started = "good", noPreset = "bad", pointsFull = "bad", presetFull = "bad", cancelled = "dim" }

local function onServerCommand(module, command, args)
    if module ~= MOD then return end
    args = args or {}
    if command == "state" then
        CHDC.presets = arr(args.presets)
        CHDC.points = arr(args.points)
        CHDC.stateAt = ms()
        local d = CHDC.draft
        if d.pid ~= "" and not CHDC.presetById(d.pid) then d.pid = "" end
    elseif command == "points" then
        CHDC.points = arr(args.points)
    elseif command == "estimate" then
        local d = CHDC.draft
        if args.x == d.x and args.y == d.y and args.z == d.z and args.total == d.total and args.perMin == d.perMin then
            args.reasons = arr(args.reasons)
            CHDC.est = args
        end
    elseif command == "slow" then
        applySlow(args)
    elseif command == "saved" then
        CHDC.savedId = args.id
    elseif command == "toast" then
        if CMC and CMC.toast then
            CMC.toast(T("IGUI_CHD_T_" .. tostring(args.key), args.a, args.b), TOAST_COLOR[args.key] or "dim")
        end
    end
end
CHDC.onServerCommand = onServerCommand
Events.OnServerCommand.Add(onServerCommand)

-- ===================================================================== look-ups for the preset editor
local outfitNames = nil
function CHDC.outfits()
    if outfitNames then return outfitNames end
    local seen, out = {}, {}
    for _, fem in ipairs({ false, true }) do
        pcall(function()
            local list = getAllOutfits(fem)
            for i = 0, list:size() - 1 do
                local n = tostring(list:get(i))
                if not seen[n] then
                    seen[n] = true
                    out[#out + 1] = n
                end
            end
        end)
    end
    table.sort(out, function(a, b) return string.lower(a) < string.lower(b) end)
    outfitNames = out
    return out
end

local itemIndex = nil   -- { { ft, low } }
local function items()
    if itemIndex then return itemIndex end
    itemIndex = {}
    pcall(function()
        local all = getScriptManager():getAllItems()
        for i = 0, all:size() - 1 do
            local it = all:get(i)
            local ok, ft = pcall(function() return it:getFullName() end)
            if ok and ft then
                local okN, dn = pcall(function() return it:getDisplayName() end)
                local low = string.lower(tostring(ft) .. " " .. tostring(okN and dn or ""))
                itemIndex[#itemIndex + 1] = { ft = tostring(ft), low = low }
            end
        end
    end)
    return itemIndex
end

-- every word of the query somewhere in the text, any order
local function matches(low, words)
    for i = 1, #words do
        if not string.find(low, words[i], 1, true) then return false end
    end
    return true
end

local function wordsOf(q)
    local out = {}
    for w in string.gmatch(string.lower(CM.trim(q)), "%S+") do out[#out + 1] = w end
    return out
end

-- the window asks every frame while a search box has text: answer from the last search when it is the same
local lastFind = { kind = nil, q = nil, out = nil }
local function cached(kind, q)
    if lastFind.kind == kind and lastFind.q == q then return lastFind.out end
    return nil
end
local function remember(kind, q, out)
    lastFind = { kind = kind, q = q, out = out }
    return out
end

function CHDC.findOutfits(q, max)
    local c = cached("o", q)
    if c then return c end
    local words = wordsOf(q)
    local out = {}
    if #words == 0 then return out end
    for _, n in ipairs(CHDC.outfits()) do
        if matches(string.lower(n), words) then
            out[#out + 1] = n
            if #out >= max then break end
        end
    end
    return remember("o", q, out)
end

function CHDC.findItems(q, max)
    local c = cached("i", q)
    if c then return c end
    local words = wordsOf(q)
    local out = {}
    if #words == 0 then return out end
    for _, it in ipairs(items()) do
        if matches(it.low, words) then
            out[#out + 1] = it.ft
            if #out >= max then break end
        end
    end
    return remember("i", q, out)
end

local texCache = {}
function CHDC.itemTex(ft)
    if not ft or ft == "" then return nil end
    local t = texCache[ft]
    if t == nil then
        t = false
        pcall(function()
            local it = getScriptManager():FindItem(ft)
            if it then t = it:getNormalTexture() or false end
        end)
        texCache[ft] = t
    end
    return t or nil
end

function CHDC.itemName(ft)
    if CMC and CMC.itemName then return CMC.itemName(ft) end
    return ft
end

-- ===================================================================== right click on the ground
local function onFillWorld(playerNum, context, worldobjects, test)
    if test or not CHDC.isAdmin() then return end
    local sq = nil
    for _, o in ipairs(worldobjects or {}) do
        sq = CM.call(o, "getSquare")
        if sq then break end
    end
    if not sq then return end
    local x, y, z = CM.call(sq, "getX"), CM.call(sq, "getY"), CM.call(sq, "getZ")
    if not x then return end
    context:addOption(T("IGUI_CHD_Menu"), nil, function()
        CHDC.setSpot(x, y, z)
        if CHDUI and CHDUI.open then CHDUI.open("spawn") end
    end)
end
if Events.OnFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
        local ok, err = pcall(onFillWorld, playerNum, context, worldobjects, test)
        if not ok then CHD.log("context error: " .. tostring(err)) end
    end)
end

return CHDC
