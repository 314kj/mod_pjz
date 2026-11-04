-- Cookie Helper : world scanning helpers (client only, only on loaded squares)
if isServer() then return end

require "CookieHelper/CH_Shared"

CHelp.Scan = CHelp.Scan or {}
local Scan = CHelp.Scan
local floor = math.floor

-- every container that stands inside rect r on floor z.
-- returns { { c = ItemContainer, sq = IsoGridSquare, veh = BaseVehicle|nil }, ... }, vehicles
function Scan.containers(r, z, withVehicles)
    local out, vehicles, seenVeh = {}, {}, {}
    local cell = getCell()
    if not cell then return out, vehicles end
    for x = r.x1, r.x2 - 1 do
        for y = r.y1, r.y2 - 1 do
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    local n = o:getContainerCount()
                    for k = 0, n - 1 do
                        local c = o:getContainerByIndex(k)
                        if c then out[#out + 1] = { c = c, sq = sq } end
                    end
                end
                if withVehicles then
                    local v = sq:getVehicleContainer()
                    if v and not seenVeh[v] then
                        seenVeh[v] = true
                        vehicles[#vehicles + 1] = v
                    end
                end
            end
        end
    end
    if withVehicles then
        for _, v in ipairs(vehicles) do
            for i = 0, v:getPartCount() - 1 do
                local part = v:getPartByIndex(i)
                local c = part and part:getItemContainer()
                if c then out[#out + 1] = { c = c, sq = v:getSquare(), veh = v, part = part } end
            end
        end
    end
    return out, vehicles
end

-- every box in the whole safehouse, every floor that is loaded (basements too).
-- Cached for a moment: crafting asks for it before each craft.
Scan.Z_MIN, Scan.Z_MAX = -3, 8
local houseCache = {}
function Scan.house(sh)
    if not sh then return {} end
    local key = CHelp.shKey(sh)
    local now = CHelp.nowMs()
    local c = houseCache[key]
    if c and now - c.t < 1500 then return c.out end
    local r = CHelp.shRect(sh)
    local out = {}
    for z = Scan.Z_MIN, Scan.Z_MAX do
        for _, e in ipairs(Scan.containers(r, z, false)) do out[#out + 1] = e end
    end
    houseCache[key] = { t = now, out = out }
    return out
end

-- vehicles whose centre is inside rect r on floor z (only asks each square for its vehicle)
function Scan.vehicles(r, z)
    local out, seen = {}, {}
    local cell = getCell()
    if not cell then return out end
    for x = r.x1, r.x2 - 1 do
        for y = r.y1, r.y2 - 1 do
            local sq = cell:getGridSquare(x, y, z)
            local v = sq and sq:getVehicleContainer()
            if v and not seen[v] then
                seen[v] = true
                if floor(v:getZ()) == z and CHelp.rectHas(r, floor(v:getX()), floor(v:getY())) then out[#out + 1] = v end
            end
        end
    end
    return out
end

local nameCache = {}
function Scan.itemName(fullType, inst)
    local n = nameCache[fullType]
    if n then return n end
    local si = getScriptManager():getItem(fullType)
    if si then n = si:getDisplayName() end
    if (not n or n == "") and inst then n = inst:getDisplayName() end
    n = n or fullType
    nameCache[fullType] = n
    return n
end

local texCache = {}
function Scan.itemTex(fullType)
    local v = texCache[fullType]
    if v ~= nil then return v or nil end
    local si = getScriptManager():getItem(fullType)
    if si then
        local ok, tex = pcall(function() return si:getNormalTexture() end)
        if ok and tex then v = tex end
    end
    texCache[fullType] = v or false
    return v
end

-- "crate", "counter" ... -> the name the game shows on the container tab
local boxNameCache = {}
function Scan.boxName(c)
    local ok, ty = pcall(function() return c:getType() end)
    ty = ok and ty or "?"
    local n = boxNameCache[ty]
    if n then return n end
    n = getTextOrNull("IGUI_ContainerTitle_" .. ty) or ty
    boxNameCache[ty] = n
    return n
end

-- totals per full type, bags inside containers are opened one level deep.
-- e.boxes = up to 3 container names that hold it (for "where is it")
-- zone map + another map (the bag) without counting the zone again
function Scan.merge(a, b)
    local out = {}
    local function put(e)
        local o = out[e.ft]
        if not o then
            o = { ft = e.ft, n = 0, name = e.name, tex = e.tex, cat = e.cat, boxes = {}, boxSeen = {} }
            out[e.ft] = o
        end
        o.n = o.n + e.n
        for _, bx in ipairs(e.boxes) do
            if not o.boxSeen[bx] and #o.boxes < 3 then
                o.boxSeen[bx] = true
                o.boxes[#o.boxes + 1] = bx
            end
        end
    end
    for _, e in pairs(b or {}) do put(e) end
    for _, e in pairs(a or {}) do put(e) end
    return out
end

function Scan.count(entries)
    local map, total = {}, 0
    local function addItem(it, box)
        local ft = it:getFullType()
        local e = map[ft]
        if not e then
            e = { ft = ft, n = 0, name = Scan.itemName(ft, it), tex = it:getTex(), cat = it:getDisplayCategory() or "", boxes = {}, boxSeen = {} }
            map[ft] = e
        end
        e.n = e.n + 1
        total = total + 1
        if box and not e.boxSeen[box] and #e.boxes < 3 then
            e.boxSeen[box] = true
            e.boxes[#e.boxes + 1] = box
        end
    end
    for _, en in ipairs(entries) do
        local box = en.label or Scan.boxName(en.c)
        local items = en.c:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            addItem(it, box)
            if it:IsInventoryContainer() then
                local inner = it:getItemContainer()
                if inner then
                    local ii = inner:getItems()
                    for j = 0, ii:size() - 1 do addItem(ii:get(j), box) end
                end
            end
        end
    end
    return map, total
end

function Scan.lower(s)
    return string.lower(tostring(s or ""))
end

-- ------------------------------------------------------------------ workstations in a zone
-- benches  = anything the game treats as a crafting bench (anvil, loom, spinning wheel, mod benches)
-- machines = things that craft on their own (furnace, kiln, drying rack, ...): listed, opened by hand
-- surfaces = tables / counters for recipes that need any surface
local MACHINES = { "CraftLogic", "FurnaceLogic", "DryingLogic", "MashingLogic" }

local function entityName(o)
    local ok, n = pcall(function() return o:getEntityDisplayName() end)
    if ok and n and n ~= "" then return n end
    local okP, props = pcall(function() return o:getProperties() end)
    if okP and props then
        -- 42.21 PropertyContainer has get(); older builds had Val()
        local okN, cn = pcall(function()
            if props.get then return props:get("CustomName") end
            return props:Val("CustomName")
        end)
        if okN and cn and cn ~= "" then return getTextOrNull("IGUI_" .. cn) or cn end
    end
    local okO, on = pcall(function() return o:getObjectName() end)
    if okO and on and on ~= "" then return on end
    return "?"
end
Scan.entityName = entityName

local function comp(o, name)
    local ct = ComponentType and ComponentType[name]
    if not ct then return nil end
    local ok, has = pcall(function() return o:hasComponent(ct) end)
    if not ok or not has then return nil end
    local okG, c = pcall(function() return o:getComponent(ct) end)
    if okG then return c end
    return nil
end

function Scan.stations(r, z)
    local out = { benches = {}, machines = {}, surfaces = {} }
    local cell = getCell()
    if not cell or not r then return out end
    local seen = {}
    for x = r.x1, r.x2 - 1 do
        for y = r.y1, r.y2 - 1 do
            local sq = cell:getGridSquare(x, y, z)
            if sq then
                local objs = sq:getObjects()
                for i = 1, objs:size() - 1 do
                    local o = objs:get(i)
                    local bench = comp(o, "CraftBench")
                    if bench then
                        if not seen[bench] then
                            seen[bench] = true
                            out.benches[#out.benches + 1] = { obj = o, bench = bench, name = entityName(o), x = x, y = y, z = z }
                        end
                    else
                        local machine = nil
                        for _, m in ipairs(MACHINES) do
                            machine = machine or comp(o, m)
                        end
                        if machine then
                            if not seen[machine] then
                                seen[machine] = true
                                out.machines[#out.machines + 1] = { obj = o, name = entityName(o), x = x, y = y, z = z }
                            end
                        else
                            -- the same test the game's crafting uses (tables, counters, workbenches...)
                            local okT, tbl = pcall(function() return o:isGenericCraftingSurface() end)
                            if not okT then okT, tbl = pcall(function() return o:isTableSurface() end) end
                            if okT and tbl and #out.surfaces < 40 then
                                out.surfaces[#out.surfaces + 1] = { obj = o, name = entityName(o), x = x, y = y, z = z }
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- bench in this zone that can make recipe r (nil when none)
function Scan.benchFor(stations, r)
    if not stations or not r then return nil end
    for _, b in ipairs(stations.benches) do
        local ok, has = pcall(function() return b.bench:getRecipes():contains(r) end)
        if ok and has then return b end
    end
    return nil
end

-- nearest surface to a point
function Scan.surfaceNear(stations, x, y)
    local best, bd = nil, nil
    for _, s in ipairs(stations and stations.surfaces or {}) do
        local d = (s.x - x) * (s.x - x) + (s.y - y) * (s.y - y)
        if not bd or d < bd then best, bd = s, d end
    end
    return best
end
