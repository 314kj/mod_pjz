-- CookieServerPatch: Lifestyle (LifestyleHobbies) player-data repair. Client side.
--
-- Problem seen on 42.21 MP (25 Oct 2026 console.txt):
--  * Some characters' ModData.LSMoodles is missing entries (Comfort, AtHouse /
--    HomeSick, NeuralHat ...) and hygieneNeed. In MP the player's ModData can be
--    replaced after Lifestyle's own OnCreatePlayer init (the race Arcadia
--    Lifestyle MP Optimizer describes; it only repairs bladder/bath/party).
--    LSEveryMinute then dies at LSPerMinute.lua:295 every in-game minute, so the
--    rest of that function (hygiene, bladder, beauty, Neural Hat ...) never runs.
--    Same data also breaks LSCreation.lua:218, NeuralHat.lua:264, LSPerHour.lua:258.
--  * Server commands LS/makeNauseous and LS/GetEmbarrassed reach every client;
--    on clients where the target is someone else, that remote player has no
--    LSMoodles here -> ReceiveLSCommandData.lua:145 crashes.
--
-- Fix:
--  1. Before Lifestyle's EveryOneMinute / EveryTenMinutes / EveryHours handlers
--     (this file loads first: "00_" sorts before Lifestyle's client files),
--     fill in only the missing/invalid moodle fields from Lifestyle's own
--     Properties/MoodleProperties defaults. Existing values are kept.
--     hygieneNeed gets 40, the same default HygieneNeed.lua uses.
--  2. For those two server commands, give a remote target a temporary empty
--    LSMoodles table so Lifestyle's handler skips it, then remove it again.
-- No next() (Kahlua doesn't have it). Does nothing if Lifestyle isn't loaded.

if isServer() then return end

local TAG = "[CookieServerPatch] lifestyle-guard"
local FIELDS = { "Level", "Value", "Tiers", "Icon" }
local HYGIENE_DEFAULT = 40
local MAX_LOG_LINES = 20

local defs = nil
local logLines = 0

local function loadDefs()
    if defs then return defs end
    if type(require) ~= "function" then return nil end
    local ok, list = pcall(require, "Properties/MoodleProperties")
    if not ok or type(list) ~= "table" then return nil end
    local byName = {}
    local count = 0
    for _, d in pairs(list) do
        if type(d) == "table" and type(d.name) == "string" then
            byName[d.name] = d
            count = count + 1
        end
    end
    if count == 0 then return nil end
    defs = byName
    return defs
end

local function log(msg)
    if logLines >= MAX_LOG_LINES then return end
    logLines = logLines + 1
    print(TAG .. " " .. msg)
end

-- Returns the number of fields fixed.
local function repair(player, reason)
    if not LSMoodleManager then return 0 end
    if not player then return 0 end
    local okData, md = pcall(function() return player:getModData() end)
    if not okData or type(md) ~= "table" then return 0 end
    local d = loadDefs()
    if not d then return 0 end

    local fixed = 0
    local names = {}
    if type(md.LSMoodles) ~= "table" then
        md.LSMoodles = {}
        names[#names + 1] = "LSMoodles"
    end
    local moodles = md.LSMoodles
    for name, def in pairs(d) do
        local entry = moodles[name]
        if type(entry) ~= "table" then
            moodles[name] = {
                Level = def.Level, Value = def.Value, Tiers = def.Tiers,
                Icon = def.Icon, Alignment = def.Alignment,
            }
            fixed = fixed + 1
            names[#names + 1] = name
        else
            local touched = false
            for i = 1, #FIELDS do
                local f = FIELDS[i]
                if type(entry[f]) ~= "number" then
                    entry[f] = tonumber(entry[f]) or def[f]
                    touched = true
                end
            end
            if type(entry.Alignment) ~= "string" or entry.Alignment == "" then
                entry.Alignment = def.Alignment
                touched = true
            end
            if touched then
                fixed = fixed + 1
                names[#names + 1] = name .. "*"
            end
        end
    end
    if type(md.hygieneNeed) ~= "number" then
        md.hygieneNeed = tonumber(md.hygieneNeed) or HYGIENE_DEFAULT
        fixed = fixed + 1
        names[#names + 1] = "hygieneNeed"
    end

    if fixed > 0 then
        log("repaired " .. tostring(fixed) .. " (" .. tostring(reason) .. "): " .. table.concat(names, ", "))
    end
    return fixed
end

local function repairLocal(reason)
    local player = getPlayer and getPlayer() or nil
    if player and not player:isDead() then repair(player, reason) end
end

-- 1. Run right before Lifestyle's timed handlers (registered first).
Events.EveryOneMinute.Add(function() repairLocal("minute") end)
Events.EveryTenMinutes.Add(function() repairLocal("ten-minutes") end)
Events.EveryHours.Add(function() repairLocal("hour") end)
Events.OnCreatePlayer.Add(function(_, player) if player then repair(player, "create-player") end end)
Events.OnGameStart.Add(function() repairLocal("game-start") end)

-- 2. Remote targets of LS/makeNauseous and LS/GetEmbarrassed.
local TARGET_COMMANDS = { makeNauseous = true, GetEmbarrassed = true }
local temporary = {}

local function isEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

local function beforeLSCommand(module, command, args)
    if module ~= "LS" or not TARGET_COMMANDS[command] then return end
    if type(args) ~= "table" or args[1] == nil then return end
    local target = getPlayerByOnlineID(args[1])
    if not target then return end
    local okLocal, isLocal = pcall(function() return target:isLocalPlayer() end)
    if okLocal and isLocal then
        repair(target, "command " .. command)
        return
    end
    local okData, md = pcall(function() return target:getModData() end)
    if okData and type(md) == "table" and type(md.LSMoodles) ~= "table" then
        md.LSMoodles = {}
        temporary[#temporary + 1] = target
    end
end

local function afterLSCommand(module, command)
    if #temporary == 0 then return end
    for i = 1, #temporary do
        local okData, md = pcall(function() return temporary[i]:getModData() end)
        if okData and type(md) == "table" and type(md.LSMoodles) == "table" and isEmpty(md.LSMoodles) then
            md.LSMoodles = nil
        end
    end
    temporary = {}
end

Events.OnServerCommand.Add(beforeLSCommand)
-- Registered at game start, i.e. after Lifestyle's own OnServerCommand handler.
Events.OnGameStart.Add(function() Events.OnServerCommand.Add(afterLSCommand) end)

print(TAG .. " on")
