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

function Scan.itemTex(fullType)
    local si = getScriptManager():getItem(fullType)
    if si then
        local ok, tex = pcall(function() return si:getNormalTexture() end)
        if ok and tex then return tex end
    end
    return nil
end

-- totals per full type, bags inside containers are opened one level deep
function Scan.count(entries)
    local map, total = {}, 0
    local function addItem(it)
        local ft = it:getFullType()
        local e = map[ft]
        if not e then
            e = { ft = ft, n = 0, name = Scan.itemName(ft, it), tex = it:getTex(), cat = it:getDisplayCategory() or "" }
            map[ft] = e
        end
        e.n = e.n + 1
        total = total + 1
    end
    for _, en in ipairs(entries) do
        local items = en.c:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            addItem(it)
            if it:IsInventoryContainer() then
                local inner = it:getItemContainer()
                if inner then
                    local ii = inner:getItems()
                    for j = 0, ii:size() - 1 do addItem(ii:get(j)) end
                end
            end
        end
    end
    return map, total
end

function Scan.lower(s)
    return string.lower(tostring(s or ""))
end
