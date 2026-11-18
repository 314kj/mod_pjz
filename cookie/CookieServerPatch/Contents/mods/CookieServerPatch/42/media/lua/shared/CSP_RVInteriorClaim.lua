-- CookieServerPatch: Project RV Interior (PROJECTRVInterior42 3.0), who may
-- enter a vehicle's room.
--
-- In multiplayer RV Interior lets anyone sitting in or standing next to a
-- vehicle with a room go into that room: the server checks no claim, lock or
-- seat. The first vehicle someone enters also takes one of the 38 rooms of its
-- kind for good.
--
-- Here the server decides before a room is picked:
--   * admins (ManipulateVehicle or admin power): always
--   * others must be in the vehicle or within MAX_DIST tiles of it, and
--       - claimed with Another Vehicle Claim System: whoever AVCS lets use it
--         (owner; faction / safehouse members when AVCS allows). AVCS public
--         permissions (open trunk etc.) do not count.
--       - unclaimed, a vehicle AVCS does not handle, or AVCS not running:
--         no, while the sandbox option CookieServerPatch.RVRequireClaim is on
--         (default); anyone when it is off
-- FrotaBR's boat cabin (Base.CabineFantasmaBR) is left to that mod: AVCS cannot
-- claim a boat. Leaving a room is never touched.
--
-- How: the global GetInToRV(player, vehicle) is wrapped at OnServerStarted,
-- after every mod's files have loaded, so this check runs before PhunZones2's
-- own wrap of the same function (it records the player's zone). Wrapped once.
-- save-bound: no (only stops entries; rooms and their items stay as they are)
--
-- Log: "[CSP] rv-claim on (...)" at server start, then one line per entry:
--   "[CSP] rv-claim: <user> <script> allow|deny <reason>"
-- The player gets a red line above the head when refused.
-- ASCII only. No percent sign in translation strings.
-- To undo: remove this file (and the sandbox option).

local TAG = "[CSP] rv-claim"
local MODULE = "CSPRVClaim"

local MAX_DIST = 8 -- tiles from the vehicle's centre (step vans, trailers)
local SKIP = { ["Base.CabineFantasmaBR"] = true }

local CSPRVClaim = {}

local function requireClaim()
    local sv = SandboxVars and SandboxVars.CookieServerPatch
    return not (sv and sv.RVRequireClaim == false)
end

local function isAdmin(p)
    local ok, yes = pcall(function()
        local role = p:getRole()
        if not role then return false end
        if Capability and Capability.ManipulateVehicle and role:hasCapability(Capability.ManipulateVehicle) then
            return true
        end
        return role:hasAdminPower() == true
    end)
    return ok and yes == true
end

local function isNear(p, v)
    local ok, yes = pcall(function()
        local pv = p:getVehicle()
        if pv and pv:getId() == v:getId() then return true end
        local dx = p:getX() - v:getX()
        local dy = p:getY() - v:getY()
        local dz = math.abs(p:getZ() - v:getZ())
        return dz < 1.5 and (dx * dx + dy * dy) <= MAX_DIST * MAX_DIST
    end)
    return ok and yes == true
end

-- AVCS.checkPermission returns true = not claimed, false = vehicle AVCS does
-- not handle, table = claimed, .permissions says if this player may use it.
-- Returns true or false, plus the reason key (IGUI_CSP_RVClaim_<key> on a no).
function CSPRVClaim.decide(p, v)
    if isAdmin(p) then return true, "Admin" end
    if not isNear(p, v) then return false, "TooFar" end
    local A = AVCS
    if type(A) ~= "table" or type(A.checkPermission) ~= "function" then
        if requireClaim() then return false, "Unclaimed" end
        return true, "NoAVCS"
    end
    local ok, res = pcall(A.checkPermission, p, v)
    if not ok then
        print(TAG .. ": AVCS check failed: " .. tostring(res))
        return false, "Failed"
    end
    if res == true or res == false then
        if requireClaim() then return false, "Unclaimed" end
        return true, "Unclaimed"
    end
    if type(res) == "table" then
        if res.permissions == true then return true, "Claim" end
        return false, "NotYours"
    end
    return false, "Failed"
end

------------------------------------------------------------------------------
-- server
------------------------------------------------------------------------------
if isServer() then
    local function userName(p)
        local s = "?"
        pcall(function() s = p:getUsername() end)
        return tostring(s)
    end

    local function scriptName(v)
        local s = "?"
        pcall(function() s = v:getScript():getFullName() end)
        return tostring(s)
    end

    local installed = false
    function CSPRVClaim.install()
        if installed then return end
        installed = true
        local orig = GetInToRV
        if type(orig) ~= "function" then
            print(TAG .. ": GetInToRV not found (Project RV Interior off), patch off")
            return
        end
        GetInToRV = function(player, vehicle, ...)
            if not player or not vehicle then return orig(player, vehicle, ...) end
            local script = scriptName(vehicle)
            if SKIP[script] then return orig(player, vehicle, ...) end
            local ok, key = CSPRVClaim.decide(player, vehicle)
            print(TAG .. ": " .. userName(player) .. " " .. script .. (ok and " allow " or " deny ") .. tostring(key))
            if not ok then
                pcall(sendServerCommand, player, MODULE, "deny", { key = key })
                return
            end
            return orig(player, vehicle, ...)
        end
        print(TAG .. " on (AVCS " .. ((type(AVCS) == "table" and type(AVCS.checkPermission) == "function") and "yes" or "no")
            .. ", unclaimed " .. (requireClaim() and "refused" or "allowed")
            .. ", range " .. MAX_DIST .. " tiles)")
    end

    Events.OnServerStarted.Add(CSPRVClaim.install)
end

------------------------------------------------------------------------------
-- players
------------------------------------------------------------------------------
if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= MODULE or command ~= "deny" then return end
        local p = getPlayer()
        if not p then return end
        local key = (type(args) == "table" and args.key) or "Failed"
        pcall(HaloTextHelper.addBadText, p, getText("IGUI_CSP_RVClaim_" .. tostring(key)))
    end)
end

return CSPRVClaim
