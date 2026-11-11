-- CookieServerPatch: Project A-Life Thai translation (3806340371) radio check error guard. Client only.
--
-- ProjectALifeTH.hearsFrequency (ZZ_ProjectALife_TH_RuntimePatch.lua) decides whether a Thai Knox
-- radio line is shown to this player: a tuned radio in hand / inventory / vehicle, or a tuned radio
-- or TV within 10 tiles. For the last part it calls getDeviceData() on every object around the player;
-- most objects do not have that method, so every radio line printed "Tried to call nil" stack traces
-- (caught by pcall, but still counted in the red error box, seen 10 Nov 2026).
-- Replaced with the same check written so only radios and TVs (IsoWaveSignal), radio items (Radio)
-- and the vehicle radio part are asked for their device data. The same lines are shown as before.

if isServer() or not isClient() then return end

local TAG = "[CookieServerPatch] alife-th-radio-guard"
local installed = false

local function tuned(dd, freq)
    if dd == nil then return false end
    local on = false
    pcall(function() on = dd:getIsTurnedOn() == true end)
    if not on then return false end
    local ch = nil
    pcall(function() ch = dd:getChannel() end)
    return tonumber(ch) == freq
end

local function itemHears(item, freq)
    if item == nil or not instanceof(item, "Radio") then return false end
    local dd = nil
    pcall(function() dd = item:getDeviceData() end)
    return tuned(dd, freq)
end

local function hears(player, freq)
    if player == nil or type(freq) ~= "number" then return true end
    if itemHears(player:getPrimaryHandItem(), freq) or itemHears(player:getSecondaryHandItem(), freq) then
        return true
    end
    local items = nil
    pcall(function() items = player:getInventory():getItems() end)
    if items ~= nil then
        for i = 0, items:size() - 1 do
            if itemHears(items:get(i), freq) then return true end
        end
    end
    local vehicle = nil
    pcall(function() vehicle = player:getVehicle() end)
    if vehicle ~= nil then
        local dd = nil
        pcall(function()
            local part = vehicle:getPartById("Radio")
            if part ~= nil then dd = part:getDeviceData() end
        end)
        if tuned(dd, freq) then return true end
    end
    local okC, cell = pcall(getCell)
    if not okC or cell == nil then return true end
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for dx = -10, 10 do
        for dy = -10, 10 do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq ~= nil then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    if obj ~= nil and instanceof(obj, "IsoWaveSignal") then
                        local dd = nil
                        pcall(function() dd = obj:getDeviceData() end)
                        if tuned(dd, freq) then return true end
                    end
                end
            end
        end
    end
    return false
end

local function install()
    if installed then return true end
    local T = ProjectALifeTH
    if type(T) ~= "table" or type(T.hearsFrequency) ~= "function" then return false end
    T.hearsFrequency = hears
    installed = true
    print(TAG .. " on")
    return true
end

if not install() then
    Events.OnGameBoot.Add(install)
    Events.OnGameStart.Add(install)
end
