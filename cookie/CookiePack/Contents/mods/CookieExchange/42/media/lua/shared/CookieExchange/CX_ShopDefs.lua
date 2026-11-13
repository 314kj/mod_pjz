-- Cookie Exchange : shop catalog shape, first-boot defaults, and the "spec" text every row uses
-- The catalog lives in Zomboid/Lua/CookieExchange_Shop.json (server). Prices there are whole dollars.
-- A row says what it gives with one line of text, the same text the admin form edits:
--   item  : "Base.Hammer, Base.NailsBox x2"
--   car   : "Base.SmallCar"                 (vehicle script name, gives a vehicle slip)
--   pet   : "hen:leghorn x3"                (animal type : breed, gives an animal slip)
--   trait : "+base:fastlearner" / "-base:smoker"

require "CookieExchange/CX_Const"

CX.SHOP_FILE  = "CookieExchange_Shop.json"
CX.SHOP_BAD   = "CookieExchange_Shop.bad.json"
CX.SHOP_KEY   = "CookieExchange_Shop"          -- global ModData: per-player buy counts this season
CX.SLIP_CAR   = "CookieExchange.VehicleSlip"
CX.SLIP_PET   = "CookieExchange.AnimalSlip"
CX.KIT_CAT    = "kit"    -- rows in this category are the starter kit: never sold, only admins see it
CX.KIT_KEY    = "CookieExchange_Kit"           -- global ModData: who already got (or never gets) the kit
CX.KINDS      = { "item", "car", "pet", "trait" }
CX.MAX_GIVE   = 100      -- most of one item a row may give
CX.MAX_PETS   = 10
CX.MAX_PRICE  = 10000000 -- dollars
CX.MAX_SELL   = 50       -- most items one sell command may carry

CX.SHOP_DEFAULT = {
    v = 1,
    cats = {
        { id = "food",    name = "อาหาร" },
        { id = "tools",   name = "เครื่องมือ" },
        { id = "weapons", name = "อาวุธ" },
        { id = "packs",   name = "แพ็ค" },
        { id = "cars",    name = "รถ" },
        { id = "animals", name = "สัตว์" },
        { id = "traits",  name = "Trait" },
    },
    items = {
        { id = "beans5",   cat = "food",    name = "Beans x5",     kind = "item",  spec = "Base.TinnedBeans x5", price = 40,    limit = 0 },
        { id = "chili5",   cat = "food",    name = "Chili x5",     kind = "item",  spec = "Base.CannedChili x5", price = 50,    limit = 0 },
        { id = "water3",   cat = "food",    name = "Water x3",     kind = "item",  spec = "Base.WaterBottle x3", price = 30,    limit = 0 },
        { id = "snacks",   cat = "food",    name = "Snacks",       kind = "item",  spec = "Base.Crisps x3, Base.Chocolate x3", price = 25, limit = 0 },
        { id = "hammer",   cat = "tools",   name = "Hammer",       kind = "item",  spec = "Base.Hammer",         price = 150,   limit = 0 },
        { id = "saw",      cat = "tools",   name = "Saw",          kind = "item",  spec = "Base.Saw",            price = 150,   limit = 0 },
        { id = "nails2",   cat = "tools",   name = "Nails x2 box", kind = "item",  spec = "Base.NailsBox x2",    price = 80,    limit = 0 },
        { id = "handaxe",  cat = "weapons", name = "Hand Axe",     kind = "item",  spec = "Base.HandAxe",        price = 300,   limit = 0 },
        { id = "bat",      cat = "weapons", name = "Baseball Bat", kind = "item",  spec = "Base.BaseballBat",    price = 120,   limit = 0 },
        { id = "pistol",   cat = "weapons", name = "Pistol set",   kind = "item",  spec = "Base.Pistol, Base.9mmClip x2, Base.Bullets9mmBox x2", price = 2500, limit = 2 },
        { id = "medpack",  cat = "packs",   name = "แพ็คหมอ",       kind = "item",  spec = "Base.Bandage x5, Base.AlcoholWipes x3, Base.Pills, Base.Antibiotics", price = 600, limit = 1 },
        { id = "woodpack", cat = "packs",   name = "แพ็คช่างไม้",     kind = "item",  spec = "Base.Hammer, Base.Saw, Base.NailsBox x2, Base.Screwdriver", price = 500, limit = 1 },
        { id = "carpack",  cat = "packs",   name = "แพ็คซ่อมรถ",     kind = "item",  spec = "Base.Wrench, Base.Jack, Base.LugWrench, Base.TirePump, Base.PetrolCan", price = 900, limit = 1 },
        { id = "smallcar", cat = "cars",    name = "Slip เก๋งเล็ก",   kind = "car",   spec = "Base.SmallCar",       price = 8000,  limit = 1 },
        { id = "car",      cat = "cars",    name = "Slip เก๋ง",      kind = "car",   spec = "Base.CarNormal",      price = 12000, limit = 1 },
        { id = "pickup",   cat = "cars",    name = "Slip กระบะ",     kind = "car",   spec = "Base.PickUpTruck",    price = 18000, limit = 1 },
        { id = "hens3",    cat = "animals", name = "Slip ไก่ x3",    kind = "pet",   spec = "hen:leghorn x3",      price = 900,   limit = 2 },
        { id = "sheep",    cat = "animals", name = "Slip แกะ",       kind = "pet",   spec = "ewe:rambouillet",     price = 2000,  limit = 2 },
        { id = "cow",      cat = "animals", name = "Slip วัว",       kind = "pet",   spec = "cow:holstein",        price = 3500,  limit = 2 },
        { id = "t_fast",   cat = "traits",  name = "ซื้อ Fast Learner", kind = "trait", spec = "+base:fastlearner",  price = 12000, limit = 1 },
        { id = "t_org",    cat = "traits",  name = "ซื้อ Organized",   kind = "trait", spec = "+base:organized",    price = 8000,  limit = 1 },
        { id = "t_light",  cat = "traits",  name = "ซื้อ Light Eater", kind = "trait", spec = "+base:lighteater",   price = 6000,  limit = 1 },
        { id = "t_smoker", cat = "traits",  name = "ถอด Smoker",      kind = "trait", spec = "-base:smoker",       price = 3000,  limit = 1 },
        { id = "t_insom",  cat = "traits",  name = "ถอด Insomniac",   kind = "trait", spec = "-base:insomniac",    price = 4000,  limit = 1 },
    },
    sell = {
        { ft = "Base.GoldBar",                    price = 500 },
        { ft = "Base.Diamond",                    price = 300 },
        { ft = "Base.Earring_Dangly_Diamond",     price = 150 },
        { ft = "Base.Necklace_Gold",              price = 80 },
        { ft = "Base.Ring_Left_RingFinger_Gold",  price = 50 },
        { ft = "Base.WristWatch_Left_DigitalBlack", price = 20 },
    },
}

-- ------------------------------------------------------------------------------
-- spec text
-- ------------------------------------------------------------------------------
local function trim(s)
    return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1"))
end

-- "Base.Hammer x2" / "Base.Hammer*2" / "Base.Hammer" -> "Base.Hammer", 2
local function nameCount(part)
    part = trim(part)
    local name, n = string.match(part, "^(%S+)%s*[xX%*]%s*(%d+)$")
    if not name then
        name, n = string.match(part, "^(%S+)%s+[xX]?(%d+)$")
    end
    if not name then name, n = part, "1" end
    return name, math.floor(tonumber(n) or 1)
end

local function isFullType(ft)
    return type(ft) == "string" and string.match(ft, "^[%w_]+%.[%w_%-]+$") ~= nil
end

-- returns a parsed table or nil + reason (english, for the admin)
function CX.parseSpec(kind, spec)
    spec = trim(spec)
    if spec == "" then return nil, "empty" end
    if kind == "item" then
        local give = {}
        for part in string.gmatch(spec, "[^,]+") do
            if trim(part) ~= "" then
                local ft, n = nameCount(part)
                if not isFullType(ft) then return nil, "not an item id: " .. ft end
                if n < 1 or n > CX.MAX_GIVE then return nil, "count 1-" .. CX.MAX_GIVE .. ": " .. ft end
                give[#give + 1] = { ft = ft, n = n }
            end
        end
        if #give == 0 then return nil, "no items" end
        if #give > 20 then return nil, "at most 20 lines" end
        return { give = give }
    elseif kind == "car" then
        if not isFullType(spec) then return nil, "not a vehicle id: " .. spec end
        return { veh = spec }
    elseif kind == "pet" then
        local id, n = nameCount(spec)
        local typ, breed = string.match(id, "^([%w_]+):([%w_]+)$")
        if not typ then typ = string.match(id, "^([%w_]+)$") end
        if not typ then return nil, "write type:breed, e.g. hen:leghorn x3" end
        if n < 1 or n > CX.MAX_PETS then return nil, "count 1-" .. CX.MAX_PETS end
        return { pet = string.lower(typ), breed = breed and string.lower(breed) or nil, n = n }
    elseif kind == "trait" then
        local sign, id = string.match(spec, "^([%+%-])%s*([%w_:%. ]+)$")
        if not sign then return nil, "write +base:trait or -base:trait" end
        id = string.lower(trim(id))
        if not string.find(id, ":", 1, true) then id = "base:" .. id end
        return { trait = id, add = sign == "+" }
    end
    return nil, "unknown kind " .. tostring(kind)
end

-- cut to at most max bytes without splitting a UTF-8 character (Thai is 3 bytes each)
local function cut(s, max)
    if #s <= max then return s end
    local i = max + 1
    while i > 1 do
        local b = string.byte(s, i)
        if not b or b < 128 or b >= 192 then break end
        i = i - 1
    end
    return string.sub(s, 1, i - 1)
end
CX.cut = cut

local function knownKind(k)
    for _, v in ipairs(CX.KINDS) do if v == k then return true end end
    return false
end

local function cleanId(s)
    s = string.lower(trim(s))
    s = string.gsub(s, "[^%w_]", "_")
    if #s > 24 then s = string.sub(s, 1, 24) end
    return s
end
CX.cleanId = cleanId

local function wholePrice(v)
    v = math.floor(tonumber(v) or -1)
    if v < 0 or v > CX.MAX_PRICE then return nil end
    return v
end

-- one row from the file or the admin form -> clean row, or nil + reason
function CX.cleanItem(r, cats)
    if type(r) ~= "table" then return nil, "not a row" end
    local id = cleanId(r.id)
    if id == "" then return nil, "no id" end
    local kind = tostring(r.kind or "item")
    if not knownKind(kind) then return nil, "kind must be item / car / pet / trait" end
    local cat = cleanId(r.cat)
    if cats and not cats[cat] then return nil, "no category " .. cat end
    local price = wholePrice(r.price)
    if not price then return nil, "price 0-" .. CX.MAX_PRICE end
    local limit = math.floor(tonumber(r.limit) or 0)
    if limit < 0 then limit = 0 end
    if limit > 1000 then limit = 1000 end
    local spec = trim(r.spec)
    local parsed, why = CX.parseSpec(kind, spec)
    if not parsed then return nil, why end
    local name = trim(r.name)
    if name == "" then name = id end
    name = cut(name, 90)
    return { id = id, cat = cat, name = name, kind = kind, spec = spec, price = price, limit = limit }, parsed
end

function CX.cleanCat(c)
    if type(c) ~= "table" then return nil, "not a category" end
    local id = cleanId(c.id)
    if id == "" then return nil, "no id" end
    local name = trim(c.name)
    if name == "" then name = id end
    name = cut(name, 60)
    return { id = id, name = name }
end

function CX.cleanSell(s)
    if type(s) ~= "table" then return nil, "not a row" end
    local ft = trim(s.ft)
    if not isFullType(ft) then return nil, "not an item id: " .. ft end
    local price = wholePrice(s.price)
    if not price or price < 1 then return nil, "price 1-" .. CX.MAX_PRICE end
    return { ft = ft, price = price }
end

-- whole catalog -> clean catalog + list of problems (bad rows are dropped, never the whole file)
function CX.cleanCatalog(raw)
    local out, bad = { v = 1, cats = {}, items = {}, sell = {} }, {}
    if type(raw) ~= "table" then return nil, { "file is not a JSON object" } end
    local cats, seen = {}, {}
    for i, c in ipairs(type(raw.cats) == "table" and raw.cats or {}) do
        local cc, why = CX.cleanCat(c)
        if cc and not cats[cc.id] then
            cats[cc.id] = true
            out.cats[#out.cats + 1] = cc
        else
            bad[#bad + 1] = "cats[" .. i .. "] " .. tostring(why or "duplicate id")
        end
    end
    for i, r in ipairs(type(raw.items) == "table" and raw.items or {}) do
        local rr, why = CX.cleanItem(r, cats)
        if rr and not seen[rr.id] then
            seen[rr.id] = true
            out.items[#out.items + 1] = rr
        else
            bad[#bad + 1] = "items[" .. i .. "] " .. tostring(why or "duplicate id")
        end
    end
    local sold = {}
    for i, s in ipairs(type(raw.sell) == "table" and raw.sell or {}) do
        local ss, why = CX.cleanSell(s)
        if ss and not sold[ss.ft] then
            sold[ss.ft] = true
            out.sell[#out.sell + 1] = ss
        else
            bad[#bad + 1] = "sell[" .. i .. "] " .. tostring(why or "duplicate item")
        end
    end
    return out, bad
end
