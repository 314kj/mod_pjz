-- Cookie Mastery - builder T1 hook: structures built by a builder get extra HP + a maker tag.
-- Vanilla build classes live in lua/server and load on both sides; whichever side runs create()
-- handles it: server / single player tags directly, an MP client asks the server to tag.
require "CMM_Shared"
require "BuildingObjects/ISBuildingObject"
require "BuildingObjects/ISBuildIsoEntity"
require "BuildingObjects/ISWoodenWall"
require "BuildingObjects/ISWoodenDoor"
require "BuildingObjects/ISWoodenDoorFrame"
require "BuildingObjects/ISDoubleDoor"
require "BuildingObjects/ISWoodenStairs"
require "BuildingObjects/ISWoodenFloor"
require "BuildingObjects/ISWoodenContainer"
require "BuildingObjects/ISSimpleFurniture"
require "BuildingObjects/ISDoubleTileFurniture"

CMMB = CMMB or {}

local function builderOf(self)
    if self == nil then return nil end
    if self.character then return self.character end
    if type(self.player) == "number" and getSpecificPlayer then return getSpecificPlayer(self.player) end
    if self.player and type(self.player) ~= "number" then return self.player end
    return nil
end

local function snapshot(x, y, z)
    local seen = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = CMM.square(x + dx, y + dy, z)
            local list = sq and CM.call(sq, "getObjects")
            if list then
                for i = 0, list:size() - 1 do seen[list:get(i)] = true end
            end
        end
    end
    return seen
end

function CMMB.after(self, x, y, z, before)
    local chr = builderOf(self)
    if not chr then return end
    if isClient() and not isServer() then
        -- the build ran on this MP client: the server tags it once the object reached it
        if CMMC and CMMC.me and CMM.has(CMMC.me, "build", 1) and chr == getSpecificPlayer(0) then
            CMMC.send("built", { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) })
        end
        return
    end
    if CMMS and CMMS.tagAround then CMMS.tagAround(chr, x, y, z or 0, before) end
end

local function wrap(cls, label)
    if type(cls) ~= "table" or rawget(cls, "__cmmWrapped") then return end
    local orig = rawget(cls, "create")
    if type(orig) ~= "function" then return end
    cls.__cmmWrapped = true
    cls.create = function(self, x, y, z, north, sprite, ...)
        local before = nil
        local okS, s = pcall(snapshot, x, y, z or 0)
        if okS then before = s end
        local r = orig(self, x, y, z, north, sprite, ...)
        if before then
            local ok, err = pcall(CMMB.after, self, x, y, z or 0, before)
            if not ok then CMM.log("build hook (" .. label .. ") error: " .. tostring(err)) end
        end
        return r
    end
end

function CMMB.install()
    local list = {
        { ISBuildIsoEntity, "ISBuildIsoEntity" }, { ISWoodenWall, "ISWoodenWall" }, { ISWoodenDoor, "ISWoodenDoor" },
        { ISWoodenDoorFrame, "ISWoodenDoorFrame" }, { ISDoubleDoor, "ISDoubleDoor" }, { ISWoodenStairs, "ISWoodenStairs" },
        { ISWoodenFloor, "ISWoodenFloor" }, { ISWoodenContainer, "ISWoodenContainer" },
        { ISSimpleFurniture, "ISSimpleFurniture" }, { ISDoubleTileFurniture, "ISDoubleTileFurniture" },
    }
    local n = 0
    for i = 1, #list do
        local cls = list[i][1]
        if type(cls) == "table" and type(rawget(cls, "create")) == "function" and not rawget(cls, "__cmmWrapped") then
            wrap(cls, list[i][2])
            n = n + 1
        end
    end
    CMM.log("build hooks installed: " .. n)
end

-- after every mod's lua is in (another mod may replace a build class while loading)
if Events.OnGameBoot then Events.OnGameBoot.Add(function() pcall(CMMB.install) end) end
if Events.OnServerStarted then Events.OnServerStarted.Add(function() pcall(CMMB.install) end) end
if Events.OnGameStart then Events.OnGameStart.Add(function() pcall(CMMB.install) end) end

return CMMB
