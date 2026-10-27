-- Cookie Server Patches: Building Clipboard [B42] (BuildingClipboardB42) access fix.
--
-- The mod decides "staff" by access level: anything except "" and "none" counts.
-- On 42.21 a normal player's access level is "user", so every player counted as staff.
--
-- Mod 1.6.1+ (has the sandbox option "Who can use Copy & Paste Anything",
-- SandboxVars.BuildingClipboard.Access: 1 Everyone, 2 Admins only, 3 Admins + chosen players):
--   only the staff check is fixed (staff = admin). The sandbox option decides the rest,
--   and only admins see "Manage access". If the mod's own staff check is already correct,
--   the patch does nothing.
-- Older versions (no sandbox option): only admins can use it.
--
-- The result is logged at server start as "[CookieServerPatch] Building Clipboard: ...".

local STAFF_LEVELS = { admin = true }

-- Older versions only: extra accounts allowed besides admins (lower-case username)
local ALLOW_USERS = {}

local TAG = "[CookieServerPatch] Building Clipboard"
local MODE_NAMES = { "Everyone", "Admins only", "Admins + chosen players" }

local originalAllowed, originalStaff
local state -- nil until decided: "staff-fixed", "mod-ok", "admin-only", "mod-blocks"

local function lower(v)
    if v == nil then return nil end
    return string.lower(tostring(v))
end

local function safeCall(object, method)
    if object == nil then return nil end
    local ok, fn = pcall(function() return object[method] end)
    if not ok or fn == nil then return nil end
    local ok2, result = pcall(fn, object)
    if ok2 then return result end
    return nil
end

local function isMultiplayer()
    return isClient() or isServer()
end

-- admin by access level or role name (no single-player shortcut)
local function isAdminLevel(player)
    if not player then return false end
    local level = lower(safeCall(player, "getAccessLevel"))
    if level and STAFF_LEVELS[level] then return true end
    local role = safeCall(player, "getRole")
    local roleName = role and lower(safeCall(role, "getName"))
    return roleName ~= nil and STAFF_LEVELS[roleName] == true
end

local function isAdminPlayer(player)
    if not player then return false end
    if not isMultiplayer() then return true end -- single player
    local user = lower(safeCall(player, "getUsername"))
    if user and ALLOW_USERS[user] then return true end
    return isAdminLevel(player)
end

local function mockPlayer(level)
    local role = { getName = function() return level end }
    return {
        getAccessLevel = function() return level end,
        getUsername = function() return "csp_probe_" .. level end,
        getRole = function() return role end,
        getPlayerNum = function() return 0 end,
    }
end

-- true when fn already says no to "user" and yes to "admin"
local function rejectsUsers(fn)
    if type(fn) ~= "function" then return false end
    local ok1, userResult = pcall(fn, mockPlayer("user"))
    local ok2, adminResult = pcall(fn, mockPlayer("admin"))
    return ok1 and ok2 and (not userResult) and (adminResult and true or false)
end

local function username(player)
    return tostring(safeCall(player, "getUsername"))
end

-- ---------- mod 1.6.1+: fix the staff check, let the sandbox decide ----------
local function applyStaffFix(B)
    if state == nil then
        originalStaff = B.isStaff
        state = rejectsUsers(originalStaff) and "mod-ok" or "staff-fixed"
    end
    if state == "staff-fixed" and B.isStaff ~= isAdminLevel then
        B.isStaff = isAdminLevel
    end
    if isServer() and type(B.request) == "function" and not B.cspRequestLog then
        local original = B.request
        B.request = function(player, command, args)
            if command == "setAccess" then
                if not B.isStaff(player) then print(TAG .. " blocked: " .. username(player) .. " tried 'setAccess'") end
            elseif command ~= "sync" and command ~= "getAccess" and not B.allowed(player) then
                print(TAG .. " blocked: " .. username(player) .. " tried '" .. tostring(command) .. "'")
            end
            return original(player, command, args)
        end
        B.cspRequestLog = true
    end
end

-- ---------- older versions: admin only ----------
local function guardedAllowed(player)
    if state == "mod-blocks" and originalAllowed then return originalAllowed(player) end
    return isAdminPlayer(player)
end

local function applyAdminOnly(B)
    if B.allowed ~= guardedAllowed then
        if type(B.allowed) == "function" then originalAllowed = B.allowed end
        B.allowed = guardedAllowed
    end
    if state == nil then
        state = rejectsUsers(originalAllowed) and "mod-blocks" or "admin-only"
    end
    if isServer() and type(B.request) == "function" and not B.cspRequestGuard then
        local original = B.request
        B.request = function(player, command, args)
            if command ~= "sync" and state ~= "mod-blocks" and not isAdminPlayer(player) then
                print(TAG .. " blocked: " .. username(player) .. " tried '" .. tostring(command) .. "'")
                return
            end
            return original(player, command, args)
        end
        B.cspRequestGuard = true
    end
end

local function apply()
    local B = BuildingClipboard
    if type(B) ~= "table" then return false end
    if type(B.isStaff) == "function" or B.isStaff == isAdminLevel then
        applyStaffFix(B)
    else
        applyAdminOnly(B)
    end
    return true
end

local function report()
    local B = BuildingClipboard
    if not apply() then
        print(TAG .. " not loaded - nothing to patch")
        return
    end
    local mode = type(B.accessMode) == "function" and B.accessMode() or nil
    local setting = mode and (" Sandbox 'Who can use' = " .. tostring(MODE_NAMES[mode] or mode) .. ".") or ""
    if state == "staff-fixed" then
        print(TAG .. ": staff check fixed (staff = admin)." .. setting)
    elseif state == "mod-ok" then
        print(TAG .. ": the mod's own staff check is fine now - patch OFF." .. setting)
    elseif state == "mod-blocks" then
        print(TAG .. ": patch OFF - the mod blocks normal players by itself now")
    else
        print(TAG .. ": admin only (patch ON)")
    end
end

apply()
Events.OnGameBoot.Add(apply)
Events.OnGameStart.Add(apply)
if Events.OnServerStarted then Events.OnServerStarted.Add(report) end
