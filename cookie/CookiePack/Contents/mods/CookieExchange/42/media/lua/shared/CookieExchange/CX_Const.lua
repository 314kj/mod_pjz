-- Cookie Exchange : shared constants, sandbox access, money helpers
-- Baked by lookchinnoi (AKA) for CookieCheetah.
-- The wallet lives on the server only (global ModData, cents). Clients get a copy of their own
-- balance after every change and never decide an amount themselves.

CX = CX or {}

CX.MOD    = "CookieExchange"
CX.DB_KEY = "CookieExchange_Wallet"
CX.LOG    = "CookieExchange_wallet.log"
CX.FLAG   = "CX_withdrawn"   -- set on bills that came out of a wallet: auto-convert leaves them alone
CX.MAX_PIECES = 200          -- most bills one withdrawal may hand out
CX.MAX_TAKE   = 50           -- most items one take command may carry

CX.OPT_DEFAULTS = {
    KillCashChance  = 10,
    KillCashMin     = 1,
    KillCashMax     = 20,
    AutoConvert     = true,
    MigratePhunMart = false,
}

function CX.opt(key)
    local def = CX.OPT_DEFAULTS[key]
    local sv = SandboxVars and SandboxVars.CookieExchange
    local v = sv and sv[key]
    if type(def) == "boolean" then
        if type(v) == "boolean" then return v end
        return def
    end
    if type(v) == "number" then return v end
    return def
end

-- withdrawal bills, biggest first
CX.BILLS = {
    { ft = "CookieExchange.Cash10000", v = 10000 },
    { ft = "CookieExchange.Cash1000",  v = 1000 },
    { ft = "Base.MoneyBundle",         v = 100 },
    { ft = "Base.Money",               v = 1 },
}

-- what the wallet takes in, value in cents
CX.CASH = {
    ["Base.Money"]               = 100,
    ["Base.MoneyBundle"]         = 10000,
    ["CookieExchange.Cash1000"]  = 100000,
    ["CookieExchange.Cash10000"] = 1000000,
}

-- PhunMart coins and tokens, only taken while MigratePhunMart is on (1 token = $100)
CX.PHUN = {
    ["PhunMart.Nickel"]  = 5,
    ["PhunMart.Dime"]    = 10,
    ["PhunMart.Quarter"] = 25,
    ["PhunMart.Token"]   = 10000,
}

function CX.cents(ft)
    if not ft then return nil end
    local v = CX.CASH[ft]
    if v then return v end
    if CX.opt("MigratePhunMart") then return CX.PHUN[ft] end
    return nil
end

-- every type the wallet would take right now
function CX.cashTypes()
    local out = {}
    for ft in pairs(CX.CASH) do out[#out + 1] = ft end
    if CX.opt("MigratePhunMart") then
        for ft in pairs(CX.PHUN) do out[#out + 1] = ft end
    end
    return out
end

-- dollars -> { {ft, n}, ... } biggest bill first, plus the piece count
function CX.breakdown(dollars)
    local left = math.floor(tonumber(dollars) or 0)
    local out, pieces = {}, 0
    for i = 1, #CX.BILLS do
        local b = CX.BILLS[i]
        local n = math.floor(left / b.v)
        if n > 0 then
            out[#out + 1] = { ft = b.ft, v = b.v, n = n }
            pieces = pieces + n
            left = left - n * b.v
        end
    end
    return out, pieces
end

local function groups(n)
    local s = tostring(math.floor(n))
    local out = s
    while true do
        local k
        out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return out
end

-- cents -> "$12,450" or "$3.25"
function CX.money(cents)
    cents = math.floor(tonumber(cents) or 0)
    local neg = cents < 0
    if neg then cents = -cents end
    local d = math.floor(cents / 100)
    local c = cents - d * 100
    local s = "$" .. groups(d)
    if c > 0 then
        s = s .. "." .. (c < 10 and "0" or "") .. tostring(c)
    end
    if neg then s = "-" .. s end
    return s
end

function CX.log(msg)
    print("[CookieExchange] " .. tostring(msg))
end
