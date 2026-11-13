-- Cookie Exchange : Cookie Shop, server side
-- The catalog is Zomboid/Lua/CookieExchange_Shop.json (written with the defaults on first boot, admins edit
-- it in game or by hand + Reload). Buy counts for the season live in global ModData CookieExchange_Shop.
-- Every buy / sell / unpack is decided here: the client only says which row or which item id.
-- Slips: a vehicle or animal slip is a plain item that remembers what it holds in its modData. The
-- slip is removed before the spawn and given back if the spawn fails, so one slip never makes two.
if isClient() and not isServer() then return end

require "CookieExchange/CX_Const"
require "CookieExchange/CX_Json"
require "CookieExchange/CX_ShopDefs"
require "CookieExchange/CX_Server"

local W = CX.server
local H = CX.srv
if not (W and H) then
    print("[CookieExchange] shop: wallet server missing, shop disabled")
    return
end

local nameOf, tell, call = H.nameOf, H.tell, H.call

local cat = nil          -- clean catalog
local parsed = {}        -- row id -> parsed spec
local byId, sellBy = {}, {}
local ver = 0
local loadedOk = true    -- false while the file on disk could not be read: first save keeps a copy

-- ------------------------------------------------------------------------------
-- catalog file
-- ------------------------------------------------------------------------------
local function readFile(name)
    local ok, r = pcall(getFileReader, name, false)
    if not ok or not r then return nil end
    local lines = {}
    while true do
        local line = r:readLine()
        if line == nil then break end
        lines[#lines + 1] = line
    end
    r:close()
    return table.concat(lines, "\n")
end

local function writeFile(name, text)
    local ok, w = pcall(getFileWriter, name, true, false)
    if not ok or not w then return false end
    w:write(text)
    w:close()
    return true
end

local function index()
    byId, sellBy, parsed = {}, {}, {}
    for _, r in ipairs(cat.items) do
        byId[r.id] = r
        parsed[r.id] = CX.parseSpec(r.kind, r.spec)
    end
    for _, s in ipairs(cat.sell) do sellBy[s.ft] = s end
    ver = ver + 1
end

local function save()
    if not loadedOk then
        local old = readFile(CX.SHOP_FILE)
        if old then writeFile(CX.SHOP_BAD, old) end
        loadedOk = true
    end
    if not writeFile(CX.SHOP_FILE, CX.json.encode(cat)) then
        CX.log("shop: could not write " .. CX.SHOP_FILE)
    end
end

local function load()
    local text = readFile(CX.SHOP_FILE)
    if text == nil or text == "" then
        cat = CX.cleanCatalog(CX.SHOP_DEFAULT)
        loadedOk = true
        index()
        save()
        CX.log("shop: wrote default catalog to " .. CX.SHOP_FILE)
        return true
    end
    local raw, err = CX.json.decode(text)
    if raw == nil then
        -- keep running on what we had (or the defaults); the file is left for the admin to fix
        CX.log("shop: " .. CX.SHOP_FILE .. " is not valid JSON (" .. tostring(err) .. ") - using " .. (cat and "the last good catalog" or "the defaults"))
        if not cat then cat = CX.cleanCatalog(CX.SHOP_DEFAULT) end
        loadedOk = false
        index()
        return false, err
    end
    local clean, bad = CX.cleanCatalog(raw)
    if not clean then
        CX.log("shop: catalog rejected: " .. tostring(bad and bad[1]))
        if not cat then cat = CX.cleanCatalog(CX.SHOP_DEFAULT) end
        loadedOk = false
        index()
        return false, bad and bad[1]
    end
    for _, b in ipairs(bad) do CX.log("shop: skipped " .. b) end
    cat = clean
    loadedOk = true
    index()
    CX.log("shop: catalog loaded, " .. #cat.items .. " items, " .. #cat.sell .. " buy-back")
    return true, bad[1]
end

local function C()
    if not cat then load() end
    return cat
end

-- ------------------------------------------------------------------------------
-- season buy counts
-- ------------------------------------------------------------------------------
local function counts(name)
    local d = ModData.getOrCreate(CX.SHOP_KEY)
    d.b = d.b or {}
    d.b[name] = d.b[name] or {}
    return d.b[name]
end

-- ------------------------------------------------------------------------------
-- checks
-- ------------------------------------------------------------------------------
local STAFF = { admin = true }

local function isAdmin(p)
    if not isServer() then return true end
    local okR, role = pcall(function() return p:getRole() end)
    if okR and role ~= nil then
        local ok, res = pcall(function() return role:hasAdminTool() end)
        if ok then return res == true end
    end
    local ok2, lvl = pcall(function() return p:getAccessLevel() end)
    if ok2 and lvl ~= nil then return STAFF[string.lower(tostring(lvl))] == true end
    return false
end

local function itemExists(ft)
    local sm = getScriptManager and getScriptManager()
    if not sm then return true end
    local ok, s = pcall(function() return sm:FindItem(ft) end)
    return ok and s ~= nil
end

local function vehicleExists(id)
    local sm = getScriptManager and getScriptManager()
    if not sm or type(sm.getVehicle) ~= "function" then return true end
    local ok, s = pcall(function() return sm:getVehicle(id) end)
    if not ok then return true end   -- could not ask: do not block
    return s ~= nil
end

local function animalDef(typ)
    if type(AnimalDefinitions) ~= "table" or type(AnimalDefinitions.getDef) ~= "function" then return nil end
    local ok, d = pcall(AnimalDefinitions.getDef, typ)
    if ok then return d end
    return nil
end

local function traitOf(id)
    local ok, t = pcall(function() return CharacterTrait.get(ResourceLocation.of(id)) end)
    if ok and t ~= nil then return t end
    return nil
end

local function hasTrait(p, t)
    local ok, v = pcall(function() return p:hasTrait(t) end)
    return ok and v == true
end

-- a trait the player has that the game says cannot sit with t
local function clash(p, t)
    local hit = nil
    pcall(function()
        local def = CharacterTraitDefinition.getCharacterTraitDefinition(t)
        local list = def and def:getMutuallyExclusiveTraits()
        if not list then return end
        for i = 0, list:size() - 1 do
            local x = list:get(i)
            if type(x) == "string" then x = traitOf(x) end
            if x ~= nil and hasTrait(p, x) then hit = x; return end
        end
    end)
    return hit
end

-- is this spec deliverable on this server? nil = yes, else a short reason
local function deliverable(kind, ps)
    if not ps then return "bad spec" end
    if kind == "item" then
        for _, g in ipairs(ps.give) do
            if not itemExists(g.ft) then return "no item " .. g.ft end
        end
    elseif kind == "car" then
        if not vehicleExists(ps.veh) then return "no vehicle " .. ps.veh end
        if not itemExists(CX.SLIP_CAR) then return "slip item missing" end
    elseif kind == "pet" then
        if not animalDef(ps.pet) then return "no animal " .. ps.pet end
        if not itemExists(CX.SLIP_PET) then return "slip item missing" end
    elseif kind == "trait" then
        if not traitOf(ps.trait) then return "no trait " .. ps.trait end
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- giving
-- ------------------------------------------------------------------------------
local function sendNew(inv, it)
    if isServer() and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, it) end
end

local function giveN(inv, ft, n)
    local made = 0
    for _ = 1, n do
        local ok, it = pcall(instanceItem, ft)
        if ok and it then
            inv:AddItem(it)
            sendNew(inv, it)
            made = made + 1
        end
    end
    return made
end

local function makeSlip(p, ft, md, label)
    local inv = p:getInventory()
    if not inv then return nil end
    local ok, it = pcall(instanceItem, ft)
    if not ok or not it then return nil end
    local d = it:getModData()
    for k, v in pairs(md) do d[k] = v end
    -- slips are bound to the buyer: only the owner can unpack, name shows whose it is
    local owner = nameOf(p)
    d.cxName = label
    d.cxOwner = owner
    pcall(function() it:setName(label .. " - " .. tostring(owner)) end)
    inv:AddItem(it)
    sendNew(inv, it)
    for _, m in ipairs({ "transmitModData", "syncItemFields" }) do
        if type(it[m]) == "function" then pcall(it[m], it) end
    end
    return it
end

local function applyTrait(p, t, add)
    pcall(function()
        if add then p:getCharacterTraits():add(t) else p:getCharacterTraits():remove(t) end
    end)
    pcall(function() p:modifyTraitXPBoost(t, not add) end)
end

-- ------------------------------------------------------------------------------
-- parking: outdoors, ground floor, not solid, no vehicle (same rules the old shop used)
-- ------------------------------------------------------------------------------
local function usable(sq)
    if not sq then return false end
    if call(sq, "isOutside") ~= true then return false end
    if call(sq, "isSolid") == true or call(sq, "isSolidTrans") == true then return false end
    if call(sq, "getVehicleContainer") ~= nil then return false end
    return true
end

local function facing(p)
    local v = call(p, "getForwardDirection")
    local fx, fy = call(v, "getX"), call(v, "getY")
    if type(fx) == "number" and type(fy) == "number" then
        local dx = (fx > 0.4 and 1) or (fx < -0.4 and -1) or 0
        local dy = (fy > 0.4 and 1) or (fy < -0.4 and -1) or 0
        if dx ~= 0 or dy ~= 0 then return dx, dy end
    end
    return 0, 1
end

-- returns square or nil + result key
local function spotFor(p)
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    if z ~= 0 then return nil, "GroundFloor" end
    local cell = getCell()
    local dx, dy = facing(p)
    local tries = { { dx * 2, dy * 2 }, { dx * 3, dy * 3 }, { dx, dy } }
    for r = 1, 3 do
        for ox = -r, r do
            for oy = -r, r do tries[#tries + 1] = { ox, oy } end
        end
    end
    for _, t in ipairs(tries) do
        local sq = cell:getGridSquare(x + t[1], y + t[2], z)
        if usable(sq) then return sq end
    end
    return nil, "NoSpot"
end

local function spawnCar(p, vehId, sq)
    if type(addVehicleDebug) ~= "function" then return nil end
    local ok, veh = pcall(addVehicleDebug, vehId, IsoDirections.N, nil, sq)
    if not ok then CX.log("shop: addVehicleDebug " .. vehId .. " -> " .. tostring(veh)); veh = nil end
    if veh == nil then veh = call(sq, "getVehicleContainer") end
    if veh == nil then return nil end
    -- a bought car comes whole and fuelled, with its key
    pcall(function() veh:repair() end)
    local parts = math.floor(tonumber(call(veh, "getPartCount")) or 0)
    for i = 0, parts - 1 do
        pcall(function()
            local part = veh:getPartByIndex(i)
            if part and part:getContainerContentType() == "Gasoline" then
                part:setContainerContentAmount(part:getContainerCapacity())
            end
        end)
    end
    pcall(function()
        local key = veh:createVehicleKey()
        if key then
            p:getInventory():AddItem(key)
            sendNew(p:getInventory(), key)
        end
    end)
    for _, m in ipairs({ "transmitPartUsedDelta", "transmitCompleteItemToClients" }) do
        if type(veh[m]) == "function" then pcall(veh[m], veh) end
    end
    return veh
end

local function spawnPet(typ, breedName, sq)
    local def = animalDef(typ)
    if not def then return nil end
    local breed = nil
    if breedName then
        local ok, b = pcall(function() return def:getBreedByName(breedName) end)
        if ok then breed = b end
    end
    if breed == nil then
        local ok, b = pcall(function() return def:getBreeds():get(0) end)
        if ok then breed = b end
    end
    if breed == nil then return nil end
    local ok, a = pcall(addAnimal, getCell(), sq:getX(), sq:getY(), sq:getZ(), typ, breed, false)
    if not ok or a == nil then
        CX.log("shop: addAnimal " .. tostring(typ) .. " -> " .. tostring(a))
        return nil
    end
    pcall(function() a:addToWorld() end)
    pcall(function() a:setWild(false) end)
    return a
end

-- ------------------------------------------------------------------------------
-- what the client gets
-- ------------------------------------------------------------------------------
local function iconOf(r)
    local ps = parsed[r.id]
    if r.kind == "item" and ps then return ps.give[1].ft end
    if r.kind == "car" then return CX.SLIP_CAR end
    if r.kind == "pet" then return CX.SLIP_PET end
    return nil
end

local function catalogFor(p, name)
    local c = C()
    local items = {}
    for i, r in ipairs(c.items) do
        items[i] = { id = r.id, cat = r.cat, name = r.name, kind = r.kind, spec = r.spec,
                     price = r.price, limit = r.limit, icon = iconOf(r) }
    end
    return { ver = ver, cats = c.cats, items = items, sell = c.sell, mine = counts(name), admin = isAdmin(p) }
end

local function sendCatalog(p)
    local n = nameOf(p)
    if n then tell(p, "catalog", catalogFor(p, n)) end
end

local function broadcast()
    H.forOnline(function(q) pcall(sendCatalog, q) end)
end

local function res(p, key, extra)
    local a = extra or {}
    a.key = key
    tell(p, "shopres", a)
end

-- ------------------------------------------------------------------------------
-- player commands
-- ------------------------------------------------------------------------------
local S = {}

function S.shop(p)
    sendCatalog(p)
end

-- args.id = row id, args.price = the price the player saw (dollars)
function S.buy(p, args)
    local n = nameOf(p)
    if not n or type(args) ~= "table" then return end
    C()
    local r = byId[tostring(args.id)]
    if not r then res(p, "Gone"); sendCatalog(p); return end
    if math.floor(tonumber(args.price) or -1) ~= r.price then res(p, "PriceChanged"); sendCatalog(p); return end
    local mine = counts(n)
    if r.limit > 0 and (mine[r.id] or 0) >= r.limit then res(p, "Limit"); return end
    local ps = parsed[r.id]
    local broken = deliverable(r.kind, ps)
    if broken then
        CX.log("shop: row " .. r.id .. " cannot be delivered: " .. broken)
        res(p, "Broken")
        return
    end
    local t
    if r.kind == "trait" then
        t = traitOf(ps.trait)
        local has = hasTrait(p, t)
        if ps.add and has then res(p, "HaveTrait"); return end
        if not ps.add and not has then res(p, "NoTrait"); return end
        if ps.add and clash(p, t) then res(p, "TraitClash"); return end
    end
    local inv = p:getInventory()
    if not inv then return end
    local cents = r.price * 100
    if not W.charge(n, cents, "buy " .. r.id) then res(p, "NoMoney"); return end

    local ok = true
    if r.kind == "item" then
        local want, made = 0, 0
        for _, g in ipairs(ps.give) do
            want = want + g.n
            made = made + giveN(inv, g.ft, g.n)
        end
        if made < want then
            -- pay back the share that never arrived
            local back = math.floor(cents * (want - made) / want)
            if back > 0 then W.add(n, back, "buy " .. r.id .. " refund " .. (want - made) .. "/" .. want) end
            ok = made > 0
        end
    elseif r.kind == "car" then
        ok = makeSlip(p, CX.SLIP_CAR, { cxVeh = ps.veh }, r.name) ~= nil
        if not ok then W.add(n, cents, "buy " .. r.id .. " refund") end
    elseif r.kind == "pet" then
        ok = makeSlip(p, CX.SLIP_PET, { cxPet = ps.pet, cxBreed = ps.breed, cxN = ps.n }, r.name) ~= nil
        if not ok then W.add(n, cents, "buy " .. r.id .. " refund") end
    elseif r.kind == "trait" then
        applyTrait(p, t, ps.add)
        ok = hasTrait(p, t) == ps.add
        if ok then
            tell(p, "trait", { id = ps.trait, add = ps.add })
        else
            W.add(n, cents, "buy " .. r.id .. " refund (trait did not change)")
        end
    end
    if not ok then res(p, "Broken"); return end
    mine[r.id] = (mine[r.id] or 0) + 1
    res(p, "Bought", { name = r.name, d = cents, id = r.id, n = mine[r.id], ok = true })
end

-- args.ids = item ids in the player's bags
function S.sell(p, args)
    local n = nameOf(p)
    if not n or type(args) ~= "table" or type(args.ids) ~= "table" then return end
    C()
    local sum, sold, count = 0, {}, 0
    for _, id in pairs(args.ids) do
        count = count + 1
        if count > CX.MAX_SELL then break end
        local it = H.findItemById(p, id)
        if it then
            local s = sellBy[it:getFullType()]
            local worn = call(p, "isEquipped", it) == true or call(it, "isEquipped") == true
            if s and not worn and H.removeItem(it) then
                sum = sum + s.price
                sold[#sold + 1] = id
            end
        end
    end
    if sum > 0 then
        W.add(n, sum * 100, "sell x" .. #sold)
        res(p, "Sold", { d = sum * 100, ids = sold, ok = true })
    else
        res(p, "NothingSold", { ids = {} })
    end
end

-- args.id = slip item id
function S.unpack(p, args)
    local n = nameOf(p)
    if not n or type(args) ~= "table" then return end
    local it = H.findItemById(p, args.id)
    if not it then res(p, "SlipGone"); return end
    local ft = it:getFullType()
    if ft ~= CX.SLIP_CAR and ft ~= CX.SLIP_PET then return end
    local md = it:getModData()
    local label = tostring(md.cxName or ft)
    if md.cxOwner ~= nil and md.cxOwner ~= n then res(p, "NotYourSlip"); return end
    local sq, why = spotFor(p)
    if not sq then res(p, why); return end

    -- the slip goes first, then the spawn: a slip and its spawn never exist together
    if not H.removeItem(it) then res(p, "SlipGone"); return end

    if ft == CX.SLIP_CAR then
        local vehId = tostring(md.cxVeh or "")
        local veh = vehId ~= "" and spawnCar(p, vehId, sq) or nil
        if not veh then
            local back = makeSlip(p, CX.SLIP_CAR, { cxVeh = md.cxVeh }, label)
            H.audit(n .. " slip car " .. vehId .. " failed" .. (back and " (slip returned)" or " !! SLIP LOST"))
            res(p, back and "SpawnFailed" or "SlipLost")
            return
        end
        H.audit(n .. " slip car " .. vehId .. " unpacked")
        res(p, "CarReady", { name = label, ok = true })
    else
        local typ, breed = tostring(md.cxPet or ""), md.cxBreed
        local want = math.max(1, math.min(CX.MAX_PETS, math.floor(tonumber(md.cxN) or 1)))
        local made = 0
        for _ = 1, want do
            if spawnPet(typ, breed, sq) then made = made + 1 else break end
        end
        if made < want then
            local back = makeSlip(p, CX.SLIP_PET, { cxPet = md.cxPet, cxBreed = md.cxBreed, cxN = want - made }, label)
            H.audit(n .. " slip pet " .. typ .. " " .. made .. "/" .. want .. (back and " (rest returned)" or " !! REST LOST"))
            if made == 0 then res(p, back and "SpawnFailed" or "SlipLost"); return end
        else
            H.audit(n .. " slip pet " .. typ .. " x" .. made .. " unpacked")
        end
        res(p, "PetReady", { name = label, n = made, ok = true })
    end
end

-- ------------------------------------------------------------------------------
-- admin commands
-- ------------------------------------------------------------------------------
local A = {}

function A.wallets(p)
    local list = {}
    for name, c in pairs(W.all()) do list[#list + 1] = { n = name, c = c } end
    -- online players with no wallet yet still show up, at $0
    H.forOnline(function(q)
        local qn = nameOf(q)
        if qn then
            local found = false
            for _, e in ipairs(list) do if e.n == qn then found = true; break end end
            if not found then list[#list + 1] = { n = qn, c = W.balance(qn) } end
        end
    end)
    table.sort(list, function(a, b) return string.lower(a.n) < string.lower(b.n) end)
    tell(p, "wallets", { list = list })
end

-- args.who, args.amt (dollars), args.sign "+" / "-"
function A.adjust(p, args)
    local who = tostring(args.who or "")
    local amt = math.floor(tonumber(args.amt) or 0)
    if who == "" or amt < 1 or amt > 100000000 then res(p, "BadAmount"); return end
    if W.all()[who] == nil then
        -- an online player without a wallet yet: use the exact username, never the typed case
        local q = H.findOnline(who)
        who = q and nameOf(q) or nil
        if not who then res(p, "NoWallet"); return end
    end
    local cents = amt * 100
    local me = nameOf(p) or "?"
    if args.sign == "-" then
        local bal = W.balance(who)
        if cents > bal then cents = bal end
        if cents > 0 then W.add(who, -cents, "admin " .. me) end
    else
        W.add(who, cents, "admin " .. me)
    end
    res(p, "Adjusted", { who = who, d = (args.sign == "-" and -cents or cents), ok = true })
    A.wallets(p)
end

local function catSet()
    local s = {}
    for _, c in ipairs(C().cats) do s[c.id] = true end
    return s
end

local function changed(p, key, extra)
    save()
    index()
    broadcast()
    res(p, key, extra or { ok = true })
end

-- args.row = {id, cat, name, kind, spec, price, limit}, args.edit = true when replacing a row
function A.saverow(p, args)
    local row, ps = CX.cleanItem(args.row, catSet())
    if not row then res(p, "BadRow", { why = tostring(ps) }); return end
    local broken = deliverable(row.kind, ps)
    if broken then res(p, "BadRow", { why = broken }); return end
    local items = C().items
    for i, r in ipairs(items) do
        if r.id == row.id then
            if not args.edit then res(p, "IdTaken"); return end
            items[i] = row
            changed(p, "Saved")
            return
        end
    end
    if args.edit then res(p, "Gone"); return end
    items[#items + 1] = row
    changed(p, "Saved")
end

function A.delrow(p, args)
    local items = C().items
    for i, r in ipairs(items) do
        if r.id == tostring(args.id) then
            table.remove(items, i)
            changed(p, "Deleted")
            return
        end
    end
    res(p, "Gone")
end

-- args.cat = {id, name}
function A.savecat(p, args)
    local c, why = CX.cleanCat(args.cat)
    if not c then res(p, "BadRow", { why = tostring(why) }); return end
    local cats = C().cats
    for i, x in ipairs(cats) do
        if x.id == c.id then
            cats[i] = c
            changed(p, "Saved")
            return
        end
    end
    cats[#cats + 1] = c
    changed(p, "Saved")
end

function A.delcat(p, args)
    local id = tostring(args.id)
    for _, r in ipairs(C().items) do
        if r.cat == id then res(p, "CatNotEmpty"); return end
    end
    local cats = C().cats
    for i, x in ipairs(cats) do
        if x.id == id then
            table.remove(cats, i)
            changed(p, "Deleted")
            return
        end
    end
    res(p, "Gone")
end

-- args.sell = {ft, price}
function A.savesell(p, args)
    local s, why = CX.cleanSell(args.sell)
    if not s then res(p, "BadRow", { why = tostring(why) }); return end
    if not itemExists(s.ft) then res(p, "BadRow", { why = "no item " .. s.ft }); return end
    local sell = C().sell
    for i, x in ipairs(sell) do
        if x.ft == s.ft then
            sell[i] = s
            changed(p, "Saved")
            return
        end
    end
    sell[#sell + 1] = s
    changed(p, "Saved")
end

function A.delsell(p, args)
    local sell = C().sell
    for i, x in ipairs(sell) do
        if x.ft == tostring(args.ft) then
            table.remove(sell, i)
            changed(p, "Deleted")
            return
        end
    end
    res(p, "Gone")
end

function A.reload(p)
    local ok, why = load()
    broadcast()
    if ok then res(p, "Reloaded", { why = why and tostring(why) or nil, ok = true })
    else res(p, "ReloadFailed", { why = tostring(why) }) end
end

-- ------------------------------------------------------------------------------
local function onClientCommand(module, command, player, args)
    if module ~= CX.MOD or not player then return end
    local fn = S[command]
    local admin = false
    if not fn and string.sub(command, 1, 2) == "a_" then
        fn = A[string.sub(command, 3)]
        admin = true
    end
    if not fn then return end
    if admin and not isAdmin(player) then return end
    local ok, err = pcall(fn, player, type(args) == "table" and args or {})
    if not ok then CX.log("shop command " .. tostring(command) .. " error: " .. tostring(err)) end
end

Events.OnClientCommand.Add(onClientCommand)

CX.shopServer = { load = load, catalog = function() return C() end }
