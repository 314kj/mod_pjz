-- CookieServerPatch: REVIVAL (JaxeRevival 3338664412) on B42.22 multiplayer, server half.
--
-- Since 42.22 the server owns player damage and health. A client can now show REVIVAL's
-- "incapacitated" screen while the server-side player is not down at all (its health never went
-- under IncapacitatedHealth there). REVIVAL's Give Up is then ignored by the server
-- (Health.kill returns when the server-side player is not incapacitated), so the player stays stuck
-- on the floor until the timer runs out (seen 10 Nov 05:49, Give Up x4 with no effect).
-- Here: Give Up for a player the server does not see as down stands that client back up instead of
-- doing nothing. A real down (the server agrees) is left to REVIVAL as before.
-- Also logs every down / get-up on the server with health, god mode and asleep, so the next test
-- shows where a down came from.

if not isServer() then return end

local TAG = "[CookieServerPatch] revival-sync"
local installed = false

local function name(p)
    local ok, n = pcall(function() return p:getUsername() end)
    return ok and tostring(n) or "?"
end

local function state(p)
    local hp, gm, sl = "?", "?", "?"
    pcall(function() hp = string.format("%.1f", p:getBodyDamage():getHealth()) end)
    pcall(function() gm = tostring(p:isGodMod()) end)
    pcall(function() sl = tostring(p:isAsleep()) end)
    return "health=" .. hp .. " godmod=" .. gm .. " asleep=" .. sl
end

local function install()
    if installed then return true end
    local JR = JaxeRevival
    if type(JR) ~= "table" or type(JR.Health) ~= "table" or type(JR.Incapacitation) ~= "table"
        or type(JR.Server) ~= "table" then
        return false
    end
    local origKill = JR.Health.kill
    local origApply = JR.Incapacitation.apply
    local isActive = JR.Incapacitation.isActive
    if type(origKill) ~= "function" or type(origApply) ~= "function" or type(isActive) ~= "function" then
        print(TAG .. " REVIVAL functions not found, patch off")
        installed = true
        return true
    end

    JR.Health.kill = function(player, ...)
        local okD, dead = pcall(function() return player:isDead() end)
        if player and okD and not dead and not isActive(player) then
            print(TAG .. " give-up from " .. name(player) .. " but the server does not see them down ("
                .. state(player) .. "): standing the client back up")
            pcall(JR.Server.sendIncapacitate, name(player), false)
            return
        end
        return origKill(player, ...)
    end

    JR.Incapacitation.apply = function(player, value, ...)
        local was = player and isActive(player)
        if value and not was then
            print(TAG .. " down " .. name(player) .. " " .. state(player))
        elseif not value and was then
            print(TAG .. " up " .. name(player) .. " " .. state(player))
        end
        return origApply(player, value, ...)
    end

    installed = true
    print(TAG .. " on")
    return true
end

if not install() then
    Events.OnServerStarted.Add(install)
    Events.OnGameBoot.Add(install)
end
