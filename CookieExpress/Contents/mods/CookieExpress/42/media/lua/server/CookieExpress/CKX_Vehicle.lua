-- Cookie Express : vehicle slips (standalone, no other mod needed)
-- A slip is CookieExpress.VehicleSlip carrying the vehicle script + the order line it came from.
-- Using it spawns that vehicle next to the player on the server, then the slip is consumed.
if isClient() then return end

require "CookieExpress/CKX_Server"

local S = CKX.S
local C = CKX.Codec
local floor, abs = math.floor, math.abs

local function grid(x, y, z)
    local cell = getCell()
    return cell and cell:getGridSquare(x, y, z) or nil
end

-- ------------------------------------------------------------------ where a slip may put a car
-- v1.2.4: same rules as Kuraya's car slip (known to work on 42.21 dedicated):
--   player on the ground floor, target square outdoors, not solid, no car on it.
--   Only the target square is checked (the engine places the car body itself).
--   A square method that does not exist on this build is skipped, never counted as "blocked".
-- Sandbox page "Cookie Express" (SandboxVars.CookieExpress), read live on every use
local function sv(key, default)
    local t = SandboxVars and SandboxVars.CookieExpress
    local v = t and t[key]
    if v == nil then return default end
    return v
end

local function rules()
    local r = {
        radius = floor(tonumber(sv("VehicleSearchRadius", 3)) or 3),
        water = sv("VehicleBlockWater", true) ~= false,
        buildings = sv("VehicleBlockBuildings", true) ~= false,
        vehicles = sv("VehicleBlockVehicles", true) ~= false,
        obstacles = sv("VehicleBlockObstacles", false) == true,
        clearW = floor(tonumber(sv("VehicleClearWidth", 3)) or 3),
        clearL = floor(tonumber(sv("VehicleClearLength", 3)) or 3),
    }
    if r.radius < 1 then r.radius = 1 elseif r.radius > 20 then r.radius = 20 end
    if r.clearW < 1 then r.clearW = 1 elseif r.clearW > 9 then r.clearW = 9 end
    if r.clearL < 1 then r.clearL = 1 elseif r.clearL > 9 then r.clearL = 9 end
    return r
end
S.slipRules = rules

local function has(obj, name)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj[name] end)
    return ok and type(v) == "function"
end

-- call obj:name([arg]) if the method exists: returns (true, result) or (false) when missing / failed
local function try(obj, name, arg)
    if not has(obj, name) then return false end
    local ok, res
    if arg == nil then
        ok, res = pcall(function() return obj[name](obj) end)
    else
        ok, res = pcall(function() return obj[name](obj, arg) end)
    end
    if not ok then return false end
    return true, res
end

local function vehicleOn(sq)
    for _, m in ipairs({ "getVehicleContainer", "getVehicle" }) do
        local ok, v = try(sq, m)
        if ok and v ~= nil then return v end
    end
    return nil
end

-- why a square is refused ("" = usable); first matching rule wins
local function refuse(sq, r)
    if sq == nil then return "missing" end
    if r.buildings then
        -- outdoors is the owner's rule: if the build cannot tell, the square is not used (same as Kuraya)
        local ok, out = try(sq, "isOutside")
        if not ok or not out then return "inside" end
    end
    for _, m in ipairs({ "isSolid", "isSolidTrans" }) do
        local ok, solid = try(sq, m)
        if ok and solid then return "solid" end
    end
    if r.water and IsoFlagType ~= nil then
        local ok, wet = try(sq, "Is", IsoFlagType.water)
        if ok and wet then return "water" end
    end
    if r.vehicles and vehicleOn(sq) ~= nil then return "vehicle" end
    return ""
end

local function areaFree(cx, cy, z, r)
    local hw, hl = floor((r.clearW - 1) / 2), floor((r.clearL - 1) / 2)
    for x = cx - hw, cx + hw do
        for y = cy - hl, cy + hl do
            local sq = grid(x, y, z)
            if not sq then return false end
            local ok, free = try(sq, "isFree", true)
            if ok and not free then return false end
        end
    end
    return true
end

-- facing direction rounded to one-tile steps (south when unknown)
local function facing(player)
    local ok, v = try(player, "getForwardDirection")
    if ok and v ~= nil then
        local okX, fx = try(v, "getX")
        local okY, fy = try(v, "getY")
        if okX and okY and type(fx) == "number" and type(fy) == "number" then
            local dx = (fx > 0.4 and 1) or (fx < -0.4 and -1) or 0
            local dy = (fy > 0.4 and 1) or (fy < -0.4 and -1) or 0
            if dx ~= 0 or dy ~= 0 then return dx, dy end
        end
    end
    return 0, 1
end

-- candidate offsets: 2, 3, 1 tiles in front, then every square in rings 1..radius (never the player's own square)
local function candidates(dx, dy, radius)
    local out, seen = {}, {}
    local function add(ox, oy)
        local k = ox .. "," .. oy
        if (ox ~= 0 or oy ~= 0) and not seen[k] then
            seen[k] = true
            out[#out + 1] = { ox, oy }
        end
    end
    add(dx * 2, dy * 2); add(dx * 3, dy * 3); add(dx, dy)
    for d = 1, radius do
        for ox = -d, d do
            for oy = -d, d do
                if abs(ox) == d or abs(oy) == d then add(ox, oy) end
            end
        end
    end
    return out
end

-- returns square, or nil + summary of why nothing was usable (for the server log)
function S.findSpot(player)
    local r = rules()
    local px, py, pz = floor(player:getX()), floor(player:getY()), floor(player:getZ())
    local dx, dy = facing(player)
    local count = {}
    for _, o in ipairs(candidates(dx, dy, r.radius)) do
        local x, y = px + o[1], py + o[2]
        local sq = grid(x, y, pz)
        local why = refuse(sq, r)
        if why == "" and r.obstacles and not areaFree(x, y, pz, r) then why = "objects" end
        if why == "" then return sq, dx, dy end
        count[why] = (count[why] or 0) + 1
    end
    local parts = {}
    for _, k in ipairs({ "inside", "solid", "water", "vehicle", "objects", "missing" }) do
        if count[k] then parts[#parts + 1] = k .. "=" .. count[k] end
    end
    return nil, table.concat(parts, " ")
end

-- which square methods this build has (printed once, helps when a game update renames them)
local apiLogged = false
local function logApi(sq)
    if apiLogged or sq == nil then return end
    apiLogged = true
    local got = {}
    for _, m in ipairs({ "isOutside", "isSolid", "isSolidTrans", "Is", "getVehicleContainer", "getVehicle", "isFree" }) do
        got[#got + 1] = m .. (has(sq, m) and "+" or "-")
    end
    CKX.log("slip square api: " .. table.concat(got, " "))
end

local function findItem(inv, id)
    local item = nil
    for _, fn in ipairs({ "getItemWithIDRecursiv", "getItemWithIDRecursive", "getItemWithID", "getItemById" }) do
        if not item then
            local ok, r = pcall(function() return inv[fn](inv, id) end)
            if ok and r then item = r end
        end
    end
    return item
end

local function removeItem(item)
    local cont = item:getContainer()
    if not cont then return end
    cont:Remove(item)
    if isServer() and sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, cont, item) end
end

local function reply(player, ok, why, name)
    CKX.toClient(player, "slip", { ok = ok, why = why or "", name = name or "" })
end

function S.useSlip(player, args)
    local uk = S.userKeyOf(player)
    local id = tonumber(args.id)
    if not id then return end
    local item = findItem(player:getInventory(), id)
    if not item or item:getFullType() ~= CKX.SLIP then return reply(player, false, "invalid") end
    local md = item:getModData()
    local vName, oid, idx, s = md.ckx_v, md.ckx_o, tonumber(md.ckx_i), tonumber(md.ckx_s) or 1
    local o = oid and S.orders[oid]
    local ln = o and idx and o.lines[idx]
    if not (ln and ln.kind == "v" and ln.ft == vName and S.claimed[oid .. "#" .. idx]) then
        return reply(player, false, "invalid")
    end
    local useKey = oid .. "#" .. idx .. "#" .. s
    if S.slipUsed[useKey] then
        removeItem(item)
        return reply(player, false, "used")
    end
    if player:getVehicle() then return reply(player, false, "invehicle") end
    local here = player:getCurrentSquare()
    logApi(here)
    if not here or floor(player:getZ()) ~= 0 then
        return reply(player, false, "outside")
    end
    local spot, fx, fy = S.findSpot(player)
    if not spot then
        CKX.log("slip " .. useKey .. " no spot near " .. floor(player:getX()) .. "," .. floor(player:getY()) ..
            " radius " .. rules().radius .. " (" .. tostring(fx) .. ")")
        return reply(player, false, "nospace")
    end

    -- car side-on to the player: facing east/west -> car points north, facing north/south -> car points east
    local dir = IsoDirections.N
    if fx == 0 then dir = IsoDirections.E end
    local okV, v = pcall(addVehicleDebug, vName, dir, nil, spot)
    if not okV then
        CKX.log("vehicle spawn failed for " .. tostring(vName) .. ": " .. tostring(v))
        return reply(player, false, "failed")
    end
    if v == nil then v = vehicleOn(spot) end
    if v == nil then
        CKX.log("vehicle spawn returned nothing for " .. tostring(vName))
        return reply(player, false, "failed")
    end
    -- like Kuraya: a returned vehicle counts as spawned; note whether the engine already gave it a square
    local okSq, vsq = try(v, "getSquare")
    if not (okSq and vsq) then CKX.log("note: " .. tostring(vName) .. " has no square yet right after spawn") end
    -- consume first so the slip can never be used twice
    S.slipUsed[useKey] = true
    removeItem(item)
    local where = floor(spot:getX()) .. "," .. floor(spot:getY())
    S.outbox("V", oid, idx .. "#" .. s, uk, ln.code, vName .. " at " .. where)

    if S.cfg.vehicleRepair then pcall(function() v:repair() end) end
    if S.cfg.vehicleFullFuel then
        pcall(function()
            local tank = v:getPartById("GasTank")
            if tank then
                tank:setContainerContentAmount(tank:getContainerCapacity())
                v:transmitPartModData(tank)
            end
        end)
    end
    if S.cfg.vehicleGiveKey then
        pcall(function()
            local key = v:createVehicleKey()
            if key then
                local inv = player:getInventory()
                inv:AddItem(key)
                S.syncAdd(inv, key)
            end
        end)
    end
    pcall(function()
        v:getModData().ckx = { u = uk, o = oid }
        v:transmitModData()
    end)
    local name = S.vehicleDisplayName(vName)
    CKX.log("slip " .. useKey .. " -> " .. vName .. " at " .. where)
    reply(player, true, "", name)
end
