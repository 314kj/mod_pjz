-- CookieServerPatch: dismantle a working vehicle for scrap, like a car wreck.
-- Asked for by Pie, 12 Nov 2026.
--
-- Vanilla (42.22.2) only lets you dismantle Burnt / Smashed vehicles
-- (ISVehicleMenu "Dismantle Car Wreck" -> ISRemoveBurntVehicle): welding mask,
-- propane torch with 10 uses in hand, MetalWelding decides the salvage, then
-- the wreck is removed. This file adds the same thing for every other vehicle:
--   * needs Mechanics 6 and Electrical 3 (plus the wreck's mask and torch);
--   * a vehicle claimed with Another Vehicle Claim System cannot be dismantled
--     (unclaim it first), nobody may sit in it and its containers must be
--     empty (so nothing is lost by accident);
--   * salvage is the wreck's salvage plus 20 percent: every roll the wreck
--     action makes is made once more with a 20 percent chance, so on average
--     there is 1.2 x of each scrap at every Welding level.
-- The vehicle and all parts still on it are destroyed, like a wreck.
-- The action is a subclass of ISRemoveBurntVehicle (its timing, animation,
-- sound, torch use and XP), the menu option is in client/CSP_ScrapVehicleMenu.lua.
-- The server checks the same rules again before the vehicle is removed.
--
-- Log (server): "[CSP] scrap-vehicle on" once, one line per vehicle removed.
-- ASCII only. No next() (Kahlua).

require "Vehicles/TimedActions/ISRemoveBurntVehicle"

local TAG = "[CSP] scrap-vehicle"

CSPScrap = CSPScrap or {}
CSPScrap.MECHANICS = 6
CSPScrap.ELECTRICAL = 3
CSPScrap.EXTRA_PERCENT = 20

function CSPScrap.isWreck(vehicle)
    local name = vehicle:getScript():getName()
    return string.match(name, "Burnt") ~= nil or string.match(name, "Smashed") ~= nil
end

-- true / false, or nil when AVCS is on but its claim list is not here yet
function CSPScrap.isClaimed(vehicle)
    if type(AVCS) ~= "table" then return false end
    local db = AVCS.dbByVehicleSQLID
    if type(db) ~= "table" then return nil end
    local id = vehicle:getModData().SQLID
    return id ~= nil and db[id] ~= nil
end

function CSPScrap.someoneInside(vehicle)
    for i = 0, vehicle:getMaxPassengers() - 1 do
        if vehicle:getCharacter(i) then return true end
    end
    return false
end

function CSPScrap.hasItems(vehicle)
    for i = 0, vehicle:getPartCount() - 1 do
        local c = vehicle:getPartByIndex(i):getItemContainer()
        if c and not c:isEmpty() then return true end
    end
    return false
end

-- everything except the torch and mask (the wreck action checks the torch)
function CSPScrap.blockers(character, vehicle)
    local out = {}
    if character:getPerkLevel(Perks.Mechanics) < CSPScrap.MECHANICS then out.mechanics = true end
    if character:getPerkLevel(Perks.Electricity) < CSPScrap.ELECTRICAL then out.electrical = true end
    local claimed = CSPScrap.isClaimed(vehicle)
    if claimed then out.claimed = true elseif claimed == nil then out.claimUnknown = true end
    if CSPScrap.someoneInside(vehicle) then out.occupied = true end
    if CSPScrap.hasItems(vehicle) then out.items = true end
    return out
end

function CSPScrap.allowed(character, vehicle)
    local b = CSPScrap.blockers(character, vehicle)
    return not (b.mechanics or b.electrical or b.claimed or b.claimUnknown or b.occupied or b.items)
end

CSPScrapVehicle = ISRemoveBurntVehicle:derive("CSPScrapVehicle")

function CSPScrapVehicle:isValid()
    return ISRemoveBurntVehicle.isValid(self) and CSPScrap.allowed(self.character, self.vehicle)
end

function CSPScrapVehicle:update()
    ISRemoveBurntVehicle.update(self)
    self.item:setJobType(getText("IGUI_CSP_ScrapVehicle"))
end

function CSPScrapVehicle:complete()
    if not self.vehicle or self.vehicle:isRemovedFromWorld()
            or not CSPScrap.allowed(self.character, self.vehicle) then
        return false
    end
    local name, x, y = self.vehicle:getScriptName(), self.vehicle:getX(), self.vehicle:getY()
    local done = ISRemoveBurntVehicle.complete(self)
    if done then
        print(TAG .. ": " .. tostring(self.character:getUsername()) .. " dismantled " .. tostring(name)
            .. " at " .. math.floor(x) .. "," .. math.floor(y))
    end
    return done
end

-- the wreck action rolls each scrap item through this; roll again 20% of the time
function CSPScrapVehicle:checkAddItem(item, baseChance)
    local got = ISRemoveBurntVehicle.checkAddItem(self, item, baseChance)
    if ZombRand(100) < CSPScrap.EXTRA_PERCENT then
        ISRemoveBurntVehicle.checkAddItem(self, item, baseChance)
    end
    return got
end

-- the server makes the action again from these two arguments
function CSPScrapVehicle:new(character, vehicle)
    local o = ISBaseTimedAction.new(self, character)
    if vehicle ~= nil and not CSPScrap.isWreck(vehicle) then
        o.vehicle = vehicle
    end
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = o:getDuration()
    return o
end

if isServer() then print(TAG .. " on") end
