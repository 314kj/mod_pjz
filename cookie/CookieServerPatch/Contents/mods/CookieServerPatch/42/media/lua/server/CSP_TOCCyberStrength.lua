-- CookieServerPatch: The Only Cure+ (3818733381) Cyber arm Strength bonus, given by the server. Server side.
--
-- Kick, 9 Nov 2026 (one player, 6 times, every join after the first):
--   Anti-cheat="Capability" server-option="AntiCheatPermission" reason="PlayerXp: no capability" action="Kick"
-- TOC+ client/TOC/Plus/CyberStrength.lua gives +1 Strength while a Cyber base is worn. It raises the
-- level on the client (LevelPerk) and sends it with SyncXp. SyncXp sends the PlayerXp packet, which the
-- server only takes from a role with Capability.CanModifyPlayerStatsInThePlayerStatsUI (admin), so every
-- non-admin who finishes a Cyber arm is kicked a second later. The server never stored the level, so the
-- client gives it again ~5 s after every join and the player is kicked again.
--
-- In B42 the server owns XP: it sends each player their XP block (levels + traits) every second, and
-- vanilla XpUpdate (Strength traits on LevelPerk, losing levels) runs here. So the bonus is given here,
-- on the server's copy of the player, and reaches the client with the next XP sync:
--  * same rule as TOC+: one point while a Cyber base is worn on either side (tier.strengthBonus from
--    TOC+'s own data), nothing past 10, taken back when the base comes off, and a point the game already
--    took back as "not backed by XP" counts as gone and is given again.
--  * a level above the XP that this file did not give (e.g. a point an admin's SyncXp got through) is
--    never stacked on and never taken away.
--  * client/CSP_TOCCyberStrength.lua turns TOC+'s client-side version off in multiplayer.
-- What this file gave is kept in the player's ModData under CSP_CyberStr (TOC+'s TOCCyberStr is not touched).
-- Kahlua: no next().

if not isServer() then return end

local TAG = "[CookieServerPatch] toc-cyber-strength"
local KEY = "CSP_CyberStr"
local INTERVAL_MS = 2000
local MAX_LEVEL = 10

local Modular, StaticData = nil, nil
local state = "wait"          -- "wait" until TOC+ is found, then "on" or "off"
local lastRun = 0
local errorsLogged = 0

local function load()
    local okM, m = pcall(require, "TOC/Plus/ModularProsthesis")
    local okS, s = pcall(require, "TOC/StaticData")
    if not (okM and type(m) == "table" and type(m.GetWornBase) == "function") then return false end
    if not (okS and type(s) == "table" and type(s.GetProsthesisTier) == "function") then return false end
    Modular, StaticData = m, s
    return true
end

-- bonus the worn prosthesis asks for (only TOC+'s Cyber base has strengthBonus)
local function wanted(player)
    for _, side in ipairs({ "L", "R" }) do
        local base = Modular.GetWornBase(player, side)
        if base then
            local tier = StaticData.GetProsthesisTier(base:getFullType())
            if tier and type(tier.strengthBonus) == "number" and tier.strengthBonus > 0 then
                return tier.strengthBonus
            end
        end
    end
    return 0
end

-- Strength level the XP pays for (vanilla rule, as XpUpdate.checkForLosingLevel uses)
local function xpLevel(player)
    local xp = player:getXp():getXP(Perks.Strength)
    local perk = PerkFactory.getPerk(Perks.Strength)
    local lvl = 0
    for i = 1, MAX_LEVEL do
        if xp >= perk:getTotalXpForLevel(i) then lvl = i else break end
    end
    return lvl
end

local function update(player)
    local md = player:getModData()
    local stored = md[KEY]
    local want = wanted(player)
    if want == 0 and (stored == nil or stored == 0) then return end   -- nothing worn, nothing given

    local before = player:getPerkLevel(Perks.Strength)
    local extra = math.max(0, before - xpLevel(player))   -- levels above what the XP pays for
    local given = math.min(type(stored) == "number" and stored or 0, extra)   -- what the game took back is gone

    if want > given then
        -- only up to `want` levels above the XP in total: never stack on a level someone else gave
        local add = want - math.max(given, extra)
        while add > 0 and player:getPerkLevel(Perks.Strength) < MAX_LEVEL do
            player:LevelPerk(Perks.Strength)
            given = given + 1
            add = add - 1
        end
    elseif want < given then
        while given > want do
            if player:getPerkLevel(Perks.Strength) > 0 then player:LoseLevel(Perks.Strength) end
            given = given - 1
        end
    end

    if given ~= stored then md[KEY] = given end
    local after = player:getPerkLevel(Perks.Strength)
    if after ~= before then
        print(TAG .. " " .. tostring(player:getUsername()) .. " Strength " .. tostring(before) .. " -> "
            .. tostring(after) .. " (cyber bonus " .. tostring(given) .. ")")
    end
end

local function onTick()
    if state == "off" then return end
    local now = getTimestampMs()
    if now - lastRun < INTERVAL_MS then return end
    lastRun = now

    if state == "wait" then
        if not load() then
            state = "off"
            print(TAG .. " The Only Cure+ not found, patch off")
            return
        end
        state = "on"
        print(TAG .. " on")
    end

    local players = getOnlinePlayers()
    if not players then return end
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player and not player:isDead() then
            local ok, err = pcall(update, player)
            if not ok and errorsLogged < 5 then
                errorsLogged = errorsLogged + 1
                print(TAG .. " error: " .. tostring(err))
            end
        end
    end
end

Events.OnTick.Add(onTick)
