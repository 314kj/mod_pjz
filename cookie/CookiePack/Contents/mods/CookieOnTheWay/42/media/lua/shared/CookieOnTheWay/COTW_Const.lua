-- Cookie On the Way : shared constants, sandbox access, fare maths
-- Baked by lookchinnoi (AKA) for CookieCheetah.
-- Fares are whole dollars. The server prices every trip itself from its own copy of the road graph;
-- the client only shows the same numbers. Money moves through Cookie Exchange (CX.server) when that
-- mod is on; without it trips are free unless RequireWallet is set.

COTW = COTW or {}

COTW.MOD    = "CookieOnTheWay"
COTW.DB_KEY = "CookieOnTheWay"
COTW.PINS   = 5
COTW.HIGHWAY_WIDTH = 12      -- roads at least this wide use MaxSpeed, narrower ones CitySpeed
COTW.REF_FROM = { 8137, 11746 }   -- Rosewood fire station (price reference)
COTW.ROAD_GAP = 60           -- recorded roads keep a point every 6 tiles: a longer step is a teleport (a 2 s stall at 90 km/h is 50)

COTW.OPT_DEFAULTS = {
    PricePerKm      = 136,   -- Rosewood -> Louisville General Hospital (14.7 km of road) = $2,000
    MinFare         = 100,
    PassengerPct    = 20,
    TrailerFee      = 100,
    BabySeatDays    = 60,
    MaxSpeed        = 90,
    CitySpeed       = 50,
    TrailerMaxSpeed = 60,
    ZombieSpeed     = 15,
    GroupGap        = 10,
    BillSeconds     = 60,
    EmergencyFeePct = 10,
    BlockedSeconds  = 5,
    MinFuelPct      = 15,
    RequireWallet   = false,
}

function COTW.opt(key)
    local def = COTW.OPT_DEFAULTS[key]
    local sv = SandboxVars and SandboxVars.CookieOnTheWay
    local v = sv and sv[key]
    if type(def) == "boolean" then
        if type(v) == "boolean" then return v end
        return def
    end
    if type(v) == "number" then return v end
    return def
end

function COTW.log(msg)
    print("[CookieOnTheWay] " .. tostring(msg))
end

function COTW.money(dollars)
    local s = tostring(math.floor(math.abs(dollars or 0)))
    local out = ""
    while #s > 3 do
        out = "," .. string.sub(s, -3) .. out
        s = string.sub(s, 1, -4)
    end
    return (dollars and dollars < 0 and "-$" or "$") .. s .. out
end

-- base fare for a route of `tiles` road tiles (1 tile = 1 m), rounded up to $10
function COTW.fare(tiles)
    local raw = (tiles or 0) / 1000 * COTW.opt("PricePerKm")
    local f = math.ceil(raw / 10) * 10
    return math.max(COTW.opt("MinFare"), f)
end

-- one passenger seat (not the booker, not the baby seat)
function COTW.seatFare(base)
    return math.ceil(base * COTW.opt("PassengerPct") / 100)
end

function COTW.isBaby(player)
    local ok, h = pcall(function() return player:getHoursSurvived() end)
    if not ok or type(h) ~= "number" then return false end
    return h < COTW.opt("BabySeatDays") * 24
end

-- the key a scanned profile is stored under: the vehicle script's full name
function COTW.vehicleKey(vehicle)
    local ok, s = pcall(function() return vehicle:getScript():getFullName() end)
    if ok and s then return s end
    ok, s = pcall(function() return vehicle:getScriptName() end)
    if ok and s then return s end
    return nil
end

function COTW.speedCap(width, towing)
    local v = (width or 8) >= COTW.HIGHWAY_WIDTH and COTW.opt("MaxSpeed") or COTW.opt("CitySpeed")
    v = math.min(v, COTW.opt("MaxSpeed"))
    if towing then v = math.min(v, COTW.opt("TrailerMaxSpeed")) end
    return v
end

function COTW.dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end
