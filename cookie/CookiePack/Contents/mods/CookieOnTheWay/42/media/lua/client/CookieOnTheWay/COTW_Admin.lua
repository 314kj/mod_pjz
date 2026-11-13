-- Cookie On the Way : admin tools (driver seat)
-- Scan: reads size and mass from the vehicle script, then a brake test (cruise to 40 km/h on a clear
-- straight road, full brake, measure the stopping distance). A towed trailer is scanned in the same go
-- (size and mass only). Unscanned vehicles and trailers cannot use the autopilot.
-- Record road: drive a road the map data does not know (map mods that do not reach the main roads);
-- a point is kept every 6 tiles and the road is saved when recording stops. Its ends snap onto the
-- nearest known road within 25 tiles.

require "CookieOnTheWay/COTW_Client"

COTW.Admin = COTW.Admin or {}
local A = COTW.Admin

local TEST_KMH = 40
local TEST_MS = 25000
local REC_STEP = 6

local scan = nil     -- { phase, v, t0, x, y, v0 }
local rec = nil      -- { pts = { x1, y1, ... } }

local function dims(vehicle)
    local w, l, mass = 2, 4, 1000
    pcall(function()
        local ext = vehicle:getScript():getExtents()
        w, l = ext:x(), ext:z()
    end)
    pcall(function() mass = vehicle:getMass() end)
    return w, l, mass
end

function A.scan()
    local v = COTW.driving()
    if not v or not COTW.isAdmin() then return end
    if math.abs(v:getCurrentSpeedKmHour()) > 1 then COTW.say("IGUI_COTW_Scan_Stop"); return end
    if not v:isEngineRunning() then COTW.say("IGUI_COTW_Err_engine"); return end
    local trailer = nil
    pcall(function() trailer = v:getVehicleTowing() end)
    if trailer then
        local key = COTW.vehicleKey(trailer)
        local w, l, mass = dims(trailer)
        if key then COTW.send("saveProfile", { key = key, data = { w = w, l = l, mass = mass, decel = 6, trailer = true } }) end
    end
    scan = { phase = "accel", v = v, t0 = getTimestampMs() }
    COTW.say("IGUI_COTW_Scan_Go")
end

function A.scanning() return scan ~= nil end

local function scanTick()
    local v = COTW.driving()
    if not v or v ~= scan.v or getTimestampMs() - scan.t0 > TEST_MS then
        pcall(function() scan.v:setRegulator(false) end)
        scan = nil
        COTW.say("IGUI_COTW_Scan_Fail")
        return
    end
    local speed = math.abs(v:getCurrentSpeedKmHour())
    if scan.phase == "accel" then
        v:setRegulator(true)
        v:setRegulatorSpeed(TEST_KMH)
        if speed >= TEST_KMH - 2 then
            scan.phase = "brake"
            scan.x, scan.y, scan.v0 = v:getX(), v:getY(), speed / 3.6
            v:setRegulator(false)
        end
    else
        v:setForceBrake()
        if speed < 1 then
            local d = COTW.dist(scan.x, scan.y, v:getX(), v:getY())
            local decel = d > 0.5 and scan.v0 * scan.v0 / (2 * d) or 6
            if decel > 12 then decel = 12 end
            if decel < 2 then decel = 2 end
            local w, l, mass = dims(v)
            local key = COTW.vehicleKey(v)
            COTW.send("saveProfile", { key = key, data = { w = w, l = l, mass = mass, decel = decel } })
            COTW.say("IGUI_COTW_Scan_Done", tostring(key), string.format("%.1f", decel))
            scan = nil
        end
    end
end

function A.recordToggle()
    if rec then
        if #rec.pts >= 4 then
            COTW.send("saveRoad", { w = 8, p = rec.pts })
            COTW.say("IGUI_COTW_Rec_Saved", tostring(#rec.pts / 2))
        end
        rec = nil
        return
    end
    local p = COTW.player()
    if not p or not COTW.isAdmin() then return end
    rec = { pts = { math.floor(p:getX()), math.floor(p:getY()) } }
    COTW.say("IGUI_COTW_Rec_Start")
end

function A.recording() return rec ~= nil, rec and #rec.pts / 2 or 0 end

local function recTick()
    local p = COTW.player()
    if not p then return end
    local n = #rec.pts
    if COTW.dist(rec.pts[n - 1], rec.pts[n], p:getX(), p:getY()) >= REC_STEP then
        rec.pts[n + 1] = math.floor(p:getX())
        rec.pts[n + 2] = math.floor(p:getY())
    end
end

Events.OnTick.Add(function()
    if scan then
        local ok, err = pcall(scanTick)
        if not ok then COTW.log("scan error: " .. tostring(err)); scan = nil end
    end
    if rec then pcall(recTick) end
end)
