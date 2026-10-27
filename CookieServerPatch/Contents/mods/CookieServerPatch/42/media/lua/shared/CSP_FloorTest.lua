-- CookieServerPatch: floor test (admin only). Shared file: client adds a
-- right-click option, server does the work.
--
-- Question: if we replace a build-menu floor (an "entity") with a plain floor
-- that has the same tile, does the game keep it plain, or make it an entity
-- again (now, or after a restart)? The answer decides whether a permanent
-- "floors are not entities" fix can be done in Lua.
--
-- Admin right-clicks a floor -> "[CSP test] Make this floor plain".
-- Server swaps that one floor and logs:
--   [CookieServerPatch] floortest x,y,z sprite=<name> before=entity|plain after=entity|plain
-- The square is remembered; after the next restart, when it loads:
--   [CookieServerPatch] floortest reload x,y,z sprite=<name> now=entity|plain
-- Remove this file after the test. No next() (Kahlua).

local MODULE = "CSPFloorTest"
local TAG = "[CookieServerPatch] floortest"

local function isEntity(obj)
    local ok, sc = pcall(function() return obj:getSpriteConfig() end)
    if not ok then return "unknown" end
    return sc ~= nil and "entity" or "plain"
end

local function isAdmin(player)
    local ok, lvl = pcall(function() return player:getAccessLevel() end)
    return ok and type(lvl) == "string" and string.lower(lvl) == "admin"
end

-- ---------------------------------------------------------------- client
if isClient() then
    local function onContext(playerNum, context, worldobjects, test)
        if test then return end
        local player = getSpecificPlayer(playerNum)
        if not player or not isAdmin(player) then return end
        local square
        for _, o in ipairs(worldobjects) do
            local ok, sq = pcall(function() return o:getSquare() end)
            if ok and sq then square = sq break end
        end
        if not square or not square:getFloor() then return end
        context:addOption("[CSP test] Make this floor plain", nil, function()
            sendClientCommand(player, MODULE, "convert",
                { x = square:getX(), y = square:getY(), z = square:getZ() })
        end)
    end
    Events.OnFillWorldObjectContextMenu.Add(onContext)
    return
end

-- ---------------------------------------------------------------- server
if not isServer() then return end

local function store()
    local data = ModData.getOrCreate("CookieServerPatch_FloorTest")
    data.squares = data.squares or {}
    return data.squares
end

local function convert(player, args)
    if not isAdmin(player) then return end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not x or not y or not z then return end
    local square = getCell():getGridSquare(x, y, z)
    if not square then print(TAG .. " " .. x .. "," .. y .. "," .. z .. " not loaded") return end
    local old = square:getFloor()
    if not old then print(TAG .. " " .. x .. "," .. y .. "," .. z .. " has no floor") return end
    local okName, name = pcall(function() return old:getSprite():getName() end)
    if not okName or not name then print(TAG .. " no sprite name") return end
    local before = isEntity(old)

    local ok, err = pcall(function()
        square:transmitRemoveItemFromSquare(old)
        square:RemoveTileObject(old)
        local plain = IsoObject.new(getCell(), square, getSprite(name))
        square:AddTileObject(plain, 0)
        square:RecalcAllWithNeighbours(true)
        plain:transmitCompleteItemToClients()
        local after = isEntity(plain)
        print(TAG .. " " .. x .. "," .. y .. "," .. z .. " sprite=" .. name ..
            " before=" .. before .. " after=" .. after)
    end)
    if not ok then
        print(TAG .. " " .. x .. "," .. y .. "," .. z .. " failed: " .. tostring(err))
        return
    end
    store()[x .. "," .. y .. "," .. z] = name
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module == MODULE and command == "convert" and type(args) == "table" then
        convert(player, args)
    end
end)

Events.LoadGridsquare.Add(function(square)
    local data = ModData.exists("CookieServerPatch_FloorTest") and ModData.get("CookieServerPatch_FloorTest")
    if not data or not data.squares then return end
    local key = square:getX() .. "," .. square:getY() .. "," .. square:getZ()
    local name = data.squares[key]
    if not name then return end
    local floor = square:getFloor()
    local okN, now = pcall(function() return floor:getSprite():getName() end)
    print(TAG .. " reload " .. key .. " sprite=" .. tostring(okN and now or "?") ..
        " now=" .. (floor and isEntity(floor) or "nofloor"))
end)

print(TAG .. " on")
