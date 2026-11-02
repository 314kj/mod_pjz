-- Cookie Helper : shared constants, sandbox access, safehouse helpers, transport
-- Baked by lookchinnoi (AKA) for CookieCheetah.
-- Load budget rule for this mod: the server only handles tiny commands, every scan/count
-- runs on the client that asked for it, in small slices, and only while it is needed.

CHelp = CHelp or {}
CHelp.VERSION = "1.1.0"
CHelp.BUILD = "chp-261103-t3b2"
CHelp.NET = "CookieHelper"

CHelp.ROLE_DOCTOR = "doctor"
CHelp.ROLE_BUILDER = "builder"
CHelp.ROLE_KEEPER = "keeper"
CHelp.ROLES = { CHelp.ROLE_DOCTOR, CHelp.ROLE_BUILDER, CHelp.ROLE_KEEPER }

CHelp.ZONE_COUNT = "count"
CHelp.ZONE_VEHICLE = "vehicle"

function CHelp.log(msg)
    print("[CookieHelper] " .. tostring(msg))
end

function CHelp.isSP()
    return (not isClient()) and (not isServer())
end

-- unix seconds (same clock on server and client, the client keeps an offset anyway)
function CHelp.now()
    local ok, v = pcall(getTimestamp)
    if ok and type(v) == "number" then return v end
    return os.time()
end

function CHelp.nowMs()
    local ok, v = pcall(getTimestampMs)
    if ok and type(v) == "number" then return v end
    return CHelp.now() * 1000
end

-- ------------------------------------------------------------------ sandbox
local DEFAULTS = {
    GuestMinutes = 10,
    GuestRequestRange = 8,
    GuestRequestCooldown = 30,
    AllowOfflineAdd = true,
    CountZonesPerSafehouse = 3,
    VehicleZonesPerSafehouse = 1,
    MaxZoneSide = 20,
    FinderScanHours = 6,
    AutoWearWeldingMask = true,
    ReturnToolsAfterCraft = true,
    MaxOwnedSafehouses = 3,
    MaxMemberships = 5,
    LinkDepth = 2,
}

function CHelp.sv(name)
    local sv = SandboxVars and SandboxVars.CookieHelper
    local v = sv and sv[name]
    if v == nil then return DEFAULTS[name] end
    return v
end

function CHelp.svInt(name, lo, hi)
    local v = tonumber(CHelp.sv(name)) or DEFAULTS[name] or 0
    v = math.floor(v)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

-- ------------------------------------------------------------------ safehouses
function CHelp.shKey(sh)
    if not sh then return nil end
    return tostring(sh:getX()) .. "_" .. tostring(sh:getY())
end

function CHelp.shByKey(key)
    if not key then return nil end
    local list = SafeHouse.getSafehouseList()
    if not list then return nil end
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if CHelp.shKey(sh) == key then return sh end
    end
    return nil
end

function CHelp.shAt(x, y)
    local list = SafeHouse.getSafehouseList()
    if not list then return nil end
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if x >= sh:getX() and x < sh:getX2() and y >= sh:getY() and y < sh:getY2() then
            return sh
        end
    end
    return nil
end

-- tiles between a point and the safehouse rectangle (0 = inside)
function CHelp.shDist(sh, x, y)
    local dx, dy = 0, 0
    if x < sh:getX() then dx = sh:getX() - x elseif x >= sh:getX2() then dx = x - (sh:getX2() - 1) end
    if y < sh:getY() then dy = sh:getY() - y elseif y >= sh:getY2() then dy = y - (sh:getY2() - 1) end
    return math.max(dx, dy)
end

function CHelp.shNearest(x, y, range)
    local list = SafeHouse.getSafehouseList()
    if not list then return nil end
    local best, bestD = nil, (range or 0) + 1
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        local d = CHelp.shDist(sh, x, y)
        if d < bestD then best, bestD = sh, d end
    end
    return best, bestD
end

function CHelp.isOwner(sh, username)
    return sh ~= nil and username ~= nil and sh:getOwner() == username
end

-- owner or listed member (guests are listed members too while their visit lasts)
function CHelp.isAllowed(sh, username)
    return sh ~= nil and username ~= nil and sh:playerAllowed(username)
end

-- every safehouse this username belongs to (owner or member)
function CHelp.shListFor(username)
    local out = {}
    local list = SafeHouse.getSafehouseList()
    if not list or not username then return out end
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh:playerAllowed(username) then out[#out + 1] = sh end
    end
    return out
end

-- houses this username owns (stable order: by position)
function CHelp.ownedBy(username)
    local out = {}
    local list = SafeHouse.getSafehouseList()
    if not list or not username then return out end
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh:getOwner() == username then out[#out + 1] = sh end
    end
    table.sort(out, function(a, b) return CHelp.shKey(a) < CHelp.shKey(b) end)
    return out
end

-- houses where this username is a listed member but not the owner (guests included)
function CHelp.memberOf(username)
    local out = {}
    local list = SafeHouse.getSafehouseList()
    if not list or not username then return out end
    for i = 0, list:size() - 1 do
        local sh = list:get(i)
        if sh:getOwner() ~= username and sh:playerAllowed(username) then out[#out + 1] = sh end
    end
    table.sort(out, function(a, b) return CHelp.shKey(a) < CHelp.shKey(b) end)
    return out
end

-- Kahlua has no next(): this is the "is the table empty" check for the whole mod
function CHelp.hasAny(tbl)
    if type(tbl) ~= "table" then return false end
    for _ in pairs(tbl) do return true end
    return false
end

function CHelp.trim(s)
    if type(s) ~= "string" then return "" end
    return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- the vanilla check refuses anyone who already belongs to a house; we allow that (up to the cap)
-- and keep every other rule (days survived, spawn points, people inside, overlap, ...)
-- the game answers nil when claiming is off for this player (PlayerSafehouse off / admin-only)
function CHelp.claimAllowed(p)
    local ok, v = pcall(function() return getServerOptions():getBoolean("PlayerSafehouse") end)
    if ok and v == true then return true end
    if CHelp.isSP() then return true end
    return false
end

function CHelp.claimProblem(sq, p)
    local ok, res = pcall(function() return SafeHouse.canBeSafehouse(sq, p) end)
    if not ok then return "?" end
    if res == nil then return getText("IGUI_CH_Msg_ClaimDisabled") end
    res = tostring(res)
    local already = getText("IGUI_Safehouse_AlreadyHaveSafehouse")
    if already and already ~= "" then
        local a, b = string.find(res, already, 1, true)
        while a do
            res = string.sub(res, 1, a - 1) .. string.sub(res, b + 1)
            a, b = string.find(res, already, 1, true)
        end
    end
    res = CHelp.trim(res)
    if res == "" then return nil end
    return res
end

-- ------------------------------------------------------------------ rectangles
-- zone / safehouse rects use x1,y1 inclusive and x2,y2 exclusive (same as SafeHouse getX2)
function CHelp.rectHas(r, x, y, margin)
    margin = margin or 0
    return x >= r.x1 - margin and x < r.x2 + margin and y >= r.y1 - margin and y < r.y2 + margin
end

function CHelp.shRect(sh)
    return { x1 = sh:getX(), y1 = sh:getY(), x2 = sh:getX2(), y2 = sh:getY2() }
end

function CHelp.rectInside(inner, outer)
    return inner.x1 >= outer.x1 and inner.y1 >= outer.y1 and inner.x2 <= outer.x2 and inner.y2 <= outer.y2
end

function CHelp.copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = CHelp.copy(v) end
    return o
end

-- ------------------------------------------------------------------ transport
function CHelp.toServer(cmd, args)
    args = args or {}
    if CHelp.isSP() then
        if CHelp.S and CHelp.S.onCommand then CHelp.S.onCommand(getSpecificPlayer(0), cmd, args) end
        return
    end
    local p = getSpecificPlayer(0)
    if p then sendClientCommand(p, CHelp.NET, cmd, args) end
end

function CHelp.toClient(player, cmd, args)
    args = args or {}
    if CHelp.isSP() then
        if CHelp.Cl and CHelp.Cl.onCommand then CHelp.Cl.onCommand(cmd, CHelp.copy(args)) end
        return
    end
    if player then sendServerCommand(player, CHelp.NET, cmd, args) end
end

function CHelp.toAll(cmd, args)
    args = args or {}
    if CHelp.isSP() then
        if CHelp.Cl and CHelp.Cl.onCommand then CHelp.Cl.onCommand(cmd, CHelp.copy(args)) end
        return
    end
    sendServerCommand(CHelp.NET, cmd, args)
end

function CHelp.onlinePlayers()
    local out = {}
    if CHelp.isSP() then
        local p = getSpecificPlayer(0)
        if p then out[1] = p end
        return out
    end
    local list = getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    end
    return out
end
