-- CookieServerPatch: SyncXp kick guard. Client side, multiplayer only.
--
-- SyncXp (vanilla Lua global) sends the PlayerXp packet. The server only takes it from a role with
-- Capability.CanModifyPlayerStatsInThePlayerStatsUI (admin) and kicks anyone else
-- (AntiCheatPermission, reason "PlayerXp: no capability"). Vanilla only calls it from the admin
-- Player Stats window, but mods call it too (The Only Cure+ Cyber arm, 9 Nov 2026).
-- For a player without that capability the call is dropped here instead: the server would refuse the
-- packet anyway and sends its own copy of the XP back every second, so the only thing that changes is
-- that nobody gets kicked. Admins are not affected.

if isServer() or not isClient() then return end

local TAG = "[CookieServerPatch] syncxp-guard"
local original = SyncXp
if type(original) ~= "function" then
    print(TAG .. " SyncXp not found, patch off")
    return
end

local dropped = 0
local nextReport = 1

local function allowed()
    local ok, yes = pcall(function()
        local player = getPlayer()
        local role = player and player:getRole()
        return role ~= nil and role:hasCapability(Capability.CanModifyPlayerStatsInThePlayerStatsUI)
    end)
    if not ok then return true end   -- can't tell: keep vanilla behaviour
    return yes == true
end

SyncXp = function(player, ...)
    if not allowed() then
        dropped = dropped + 1
        if dropped >= nextReport then
            print(TAG .. " dropped " .. tostring(dropped) .. "x (no capability, the server would kick)")
            nextReport = nextReport * 10
        end
        return
    end
    return original(player, ...)
end

print(TAG .. " on")
