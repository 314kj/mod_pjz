-- CookieServerPatch: Strength / Fitness at level 10 keep dropping to 9 and back ("XP 14999", carry weight -2).
-- Server side (and single player). The game also loads server/ Lua in a player's game, so it returns there.
--
-- 10 Nov 2026: players with Strength or Fitness 10 see the XP fall to just under the level 10 line, the level
-- drop to 9 and carry weight drop by 2, then come back, over and over while playing normally.
-- Vanilla server/XpSystem/XpUpdate.lua keeps a "lazy" timer per player (ModData strengthUpTimer /
-- fitnessUpTimer). Every 10 game minutes it goes up; every Strength/Fitness XP gain takes 3000 off it through
-- Events.AddXP -> xpUpdate.addXp. Over 20000 the player counts as lazy and loses 1 XP now and then; at
-- the level 10 line that 1 XP drops the level (Java XP.AddXP calls LoseLevel when XP falls under the line).
-- The catch: at level 10 the XP is full, and XP.AddXP returns straight away for any gain without firing
-- Events.AddXP (42.22.2 jar). So for a level 10 player no training ever reaches the timer, it climbs
-- into the lazy range however much they play, they lose 1 XP and the level, the next gain (now under the
-- line) brings it back, and it repeats.
-- players.db 10 Nov: the level 10 players have timers of 15410-27800 (Bear, mixzelo, Curt Copium, Pomman);
-- everyone else sits near -50000. PerkLog 20:46:16-17: Curt Copium Strength 9 then 10 a second apart.
--
-- Fix: when a Strength/Fitness gain arrives for a player whose XP is already full, call xpUpdate.addXp
-- for it, which is what Events.AddXP would have done below the line. The gain itself still goes to the
-- game unchanged (it drops it at the cap as before). Covered: the global addXp / addXpNoMultiplier
-- (carrying a heavy load, running, weapon and tree hits in XpUpdate.lua, most mods) and exercise reps
-- (ISFitnessAction.exeLooped, which runs on the server). Players who really stop training still count as
-- lazy and still lose XP and levels the vanilla way; nothing changes below level 10.
-- Kahlua: no next().

if isClient() then return end

local TAG = "[CookieServerPatch] xp-cap-timer"
local CAP_LEVEL = 10
local hooked = {}
local seen = {}

local function timerKey(perk)
    if perk == Perks.Strength then return "strengthUpTimer" end
    if perk == Perks.Fitness then return "fitnessUpTimer" end
    return nil
end

local function atCap(player, perk)
    local ok, full = pcall(function()
        return player:getXp():getXP(perk) >= PerkFactory.getPerk(perk):getTotalXpForLevel(CAP_LEVEL)
    end)
    return ok and full == true
end

-- what Events.AddXP -> xpUpdate.addXp does for a gain under the line
local function credit(player, perk, amount)
    if not player or type(amount) ~= "number" or amount <= 0 then return end
    local key = timerKey(perk)
    if not key or not atCap(player, perk) then return end
    if type(xpUpdate) ~= "table" or type(xpUpdate.addXp) ~= "function" then return end
    local md = player:getModData()
    local before = tonumber(md[key])
    local ok, err = pcall(xpUpdate.addXp, player, perk, amount)
    if not ok then
        print(TAG .. " error: " .. tostring(err))
        return
    end
    local who = tostring(player:getUsername())
    if not seen[who .. key] then
        seen[who .. key] = true
        print(TAG .. " " .. who .. " " .. key .. " at level 10: training counted ("
            .. tostring(before) .. " -> " .. tostring(md[key]) .. ")")
    end
end

local function wrapGlobal(name)
    if hooked[name] then return end
    local original = _G[name]
    if type(original) ~= "function" then return end
    _G[name] = function(player, perk, amount, ...)
        credit(player, perk, amount)
        return original(player, perk, amount, ...)
    end
    hooked[name] = true
end

-- which of the two an exercise trains (FitnessExercises stiffness: arms/chest -> Strength, legs/abs -> Fitness)
local function exercisePerks(action)
    local s = action and action.exeData and action.exeData.stiffness
    local out = {}
    if type(s) == "string" then
        if string.find(s, "arms") or string.find(s, "chest") then out[#out + 1] = Perks.Strength end
        if string.find(s, "legs") or string.find(s, "abs") then out[#out + 1] = Perks.Fitness end
    end
    if #out == 0 then out = { Perks.Strength, Perks.Fitness } end
    return out
end

local function wrapExercise()
    if hooked.exercise then return end
    if type(ISFitnessAction) ~= "table" or type(ISFitnessAction.exeLooped) ~= "function" then return end
    local original = ISFitnessAction.exeLooped
    ISFitnessAction.exeLooped = function(self, ...)
        local result = original(self, ...)
        local player = self and self.character
        if player then
            local perks = exercisePerks(self)
            for i = 1, #perks do credit(player, perks[i], 1) end
        end
        return result
    end
    hooked.exercise = true
end

local function state()
    return tostring(hooked.addXp == true) .. "/" .. tostring(hooked.addXpNoMultiplier == true) .. "/"
        .. tostring(hooked.exercise == true)
end

local lastState = nil
local function install()
    wrapGlobal("addXp")
    wrapGlobal("addXpNoMultiplier")
    wrapExercise()
    local now = state()
    if now ~= lastState then
        lastState = now
        print(TAG .. " on (addXp/addXpNoMultiplier/exercise hooked: " .. now .. ")")
    end
end

install()
Events.OnGameBoot.Add(install)
if Events.OnServerStarted then Events.OnServerStarted.Add(install) end
