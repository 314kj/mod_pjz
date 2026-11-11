-- CookieServerPatch: REVIVAL (JaxeRevival 3338664412) on B42.22 multiplayer, client half (log only).
--
-- Logs when this client puts its own player down or back up, with the health this client sees,
-- so a down that only happened on the client (the server never agreed) can be told apart in the
-- next test. Nothing else is changed. See server/CSP_RevivalSync.lua.

if isServer() or not isClient() then return end

local TAG = "[CookieServerPatch] revival-sync"
local installed = false

local function install()
    if installed then return end
    local JR = JaxeRevival
    if type(JR) ~= "table" or type(JR.Incapacitation) ~= "table" then return end
    local origApply = JR.Incapacitation.apply
    local isActive = JR.Incapacitation.isActive
    if type(origApply) ~= "function" or type(isActive) ~= "function" then return end

    JR.Incapacitation.apply = function(player, value, ...)
        local mine = false
        pcall(function() mine = player ~= nil and player == getPlayer() end)
        if mine then
            local was = isActive(player)
            if (value and not was) or (not value and was) then
                local hp = "?"
                pcall(function() hp = string.format("%.1f", player:getBodyDamage():getHealth()) end)
                print(TAG .. (value and " down" or " up") .. " (client) health=" .. hp)
            end
        end
        return origApply(player, value, ...)
    end
    installed = true
    print(TAG .. " client log on")
end

Events.OnGameBoot.Add(install)
Events.OnGameStart.Add(install)
