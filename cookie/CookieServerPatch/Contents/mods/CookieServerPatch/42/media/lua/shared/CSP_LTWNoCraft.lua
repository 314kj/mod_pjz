--[[
CookieServerPatch - CSP_LTWNoCraft  (Legendary Tactical Weapons, Mod ID LTWB42)

Goal on CookieCheetah: LTW weapons come only from Cookie Mission rewards (and admins).
Nobody can learn or craft them.

  Spawn is switched off in the sandbox (page LTWO):
    every <Weapon>Rare / <Weapon>Common = 0, WeaponsZombies = 0, Magazine = 0,
    every StartWithLTW<Weapon> = false.

  This file makes every player forget the 20 LTW recipes (forge parts, make weapons,
  make sheaths), whether they came from the LTW magazine or from skill auto-learn:
    - at login / respawn
    - right after any skill level up
    - every 10 seconds for the players on this machine (client) / online (server)
  Does nothing when LTW is not installed.
]]

CSP_LTWNoCraft = CSP_LTWNoCraft or {}
local M = CSP_LTWNoCraft

M.RECIPES = {
    "Forge_LegendaryTacticalSwordBlade", "Forge_LegendaryTacticalAxeHead", "Forge_LegendaryTacticalDoubleAxeHead",
    "Forge_LegendaryTacticalBatHead", "Forge_LegendaryTacticalHammerHead", "Forge_LegendaryTacticalKnifeBlade",
    "Forge_LegendaryTacticalSledgehammerHead", "Forge_LegendaryTacticalSpearHead", "Forge_LegendaryTacticalBar",
    "MakeLegendaryTacticalSword", "MakeLegendaryTacticalTomahawk", "MakeLegendaryTacticalAxe",
    "MakeLegendaryTacticalCrowbar", "MakeLegendaryTacticalBat", "MakeLegendaryTacticalHammer",
    "MakeLegendaryTacticalKnife", "MakeLegendaryTacticalSledgehammer", "MakeLegendaryTacticalSpear",
    "MakeLegendarySwordSheath", "MakeLegendaryKnifeSheath",
}

local function log(msg)
    print("[CSP_LTWNoCraft] " .. tostring(msg))
end

local active = nil
local function ltwInstalled()
    if active ~= nil then return active end
    local sm = getScriptManager and getScriptManager()
    local ok, it = pcall(function() return sm and sm:FindItem("LTW.LegendaryTacticalSword") end)
    active = (ok and it ~= nil) and true or false
    return active
end

-- remove the LTW recipes from one character, returns how many were removed
function M.forget(chr)
    if not chr or not ltwInstalled() then return 0 end
    local ok, list = pcall(function() return chr:getKnownRecipes() end)
    if not ok or not list then return 0 end
    local n = 0
    for _, r in ipairs(M.RECIPES) do
        local okC, has = pcall(function() return list:contains(r) end)
        if okC and has then
            pcall(function() list:remove(r) end)
            n = n + 1
        end
    end
    if n > 0 then
        local who = "?"
        pcall(function() who = tostring(chr:getUsername()) end)
        log("removed " .. n .. " recipe(s) from " .. who)
    end
    return n
end

local function eachPlayer(fn)
    if isServer() then
        local ok, list = pcall(getOnlinePlayers)
        if ok and list then
            for i = 0, list:size() - 1 do fn(list:get(i)) end
        end
    else
        for i = 0, 3 do
            local p = getSpecificPlayer(i)
            if p then fn(p) end
        end
    end
end

local last = 0
local function tick()
    local now = getTimestampMs()
    if now - last < 10000 then return end
    last = now
    eachPlayer(M.forget)
end

Events.OnGameStart.Add(function()
    if ltwInstalled() then log("ready (" .. #M.RECIPES .. " recipes blocked)") end
end)
if Events.OnServerStarted then
    Events.OnServerStarted.Add(function()
        if ltwInstalled() then log("ready on server (" .. #M.RECIPES .. " recipes blocked)") end
    end)
end
Events.OnCreatePlayer.Add(function(_, player) M.forget(player) end)
Events.LevelPerk.Add(function(chr) M.forget(chr) end)
Events.OnTick.Add(function()
    local ok, err = pcall(tick)
    if not ok then log("error: " .. tostring(err)) end
end)

return M
