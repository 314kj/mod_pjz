-- Cookie Slicer (client): "Lighter game" - the game's own options that cost CPU / RAM
-- for little or nothing you can see, set in one press and undone in one press.
-- Measured on our server (10 Nov JFR): the player's game is limited by its main thread,
-- mostly mods' Lua (map squares, UI drawn every frame, per-zombie work), not the GPU.
-- So the useful switches are the ones that cut main-thread and memory work:
--   tiered     zombies you cannot see are updated less often
--   clothes    zombies' clothes get no blood / holes / patches baked into their own
--              texture (each zombie otherwise gets its own; your character stays as is)
--   weapons    no blood baked into weapon textures
--   uifps      with UI offscreen rendering on, every window's Lua runs at this rate: 30
--   lighting   lighting updates per second: 15 (the game's own recommendation)
--   ragdolls   at most 10 bodies simulated at once
-- Weak PC (take effect after the game starts again):
--   texcomp    compressed textures (about 1/4 of the graphics memory)
--   texsize / vehtex  textures at most 1024 px
--   corpse     no corpse shadows
-- The value before each change is kept in Zomboid/Lua/CookieSlicer_client.txt for "Undo".
-- Copyright (c) AKA / Cookie Cheetah. See workshop.txt for the license.
if isServer() then return end

local CS = CookieSlicer
if not CS then return end

local function core() return getCore() end
local function perf() return getPerformance() end

local function b2s(v) return v and "true" or "false" end
local function s2b(s) return s == "true" end

-- get: current value, good: is it already fine, set: make it fine
-- save / load: the value as text for Undo
CS.TUNE = {
    { id = "tiered",
      get = function() return core():getOptionTieredZombieUpdates() end,
      good = function(v) return v == true end,
      set = function() core():setOptionTieredZombieUpdates(true) end,
      save = b2s, load = function(s) core():setOptionTieredZombieUpdates(s2b(s)) end },
    { id = "clothes",
      get = function() return core():getOptionSimpleClothingTextures() end,
      good = function(v) return v >= 2 end,
      set = function() core():setOptionSimpleClothingTextures(2) end,
      save = tostring, load = function(s) core():setOptionSimpleClothingTextures(tonumber(s) or 1) end },
    { id = "weapons",
      get = function() return core():getOptionSimpleWeaponTextures() end,
      good = function(v) return v == true end,
      set = function() core():setOptionSimpleWeaponTextures(true) end,
      save = b2s, load = function(s) core():setOptionSimpleWeaponTextures(s2b(s)) end },
    { id = "uifps",
      get = function() return core():getOptionUIRenderFPS() end,
      good = function(v) return not core():getOptionUIFBO() or v <= 30 end,
      set = function() core():setOptionUIRenderFPS(30) end,
      save = tostring, load = function(s) core():setOptionUIRenderFPS(tonumber(s) or 60) end },
    { id = "lighting",
      get = function() return perf():getLightingFPS() end,
      good = function(v) return v <= 15 end,
      set = function() perf():setLightingFPS(15) end,
      save = tostring, load = function(s) perf():setLightingFPS(tonumber(s) or 15) end },
    { id = "ragdolls",
      get = function() return core():getMaxActiveRagdolls() end,
      good = function(v) return v <= 10 end,
      set = function() core():setMaxActiveRagdolls(10) end,
      save = tostring, load = function(s) core():setMaxActiveRagdolls(tonumber(s) or 20) end },
    -- weak PC: only with the second button; they need the game to start again
    { id = "texcomp", weak = true, restart = true,
      get = function() return core():getOptionTextureCompression() end,
      good = function(v) return v == true or not core():allowOptionTextureCompression() end,
      set = function() core():setOptionTextureCompression(true) end,
      save = b2s, load = function(s) core():setOptionTextureCompression(s2b(s)) end },
    { id = "texsize", weak = true, restart = true,
      get = function() return core():getOptionMaxTextureSize() end,
      good = function(v) return v <= 3 end,
      set = function() core():setOptionMaxTextureSize(3) end,
      save = tostring, load = function(s) core():setOptionMaxTextureSize(tonumber(s) or 4) end },
    { id = "vehtex", weak = true, restart = true,
      get = function() return core():getOptionMaxVehicleTextureSize() end,
      good = function(v) return v <= 3 end,
      set = function() core():setOptionMaxVehicleTextureSize(3) end,
      save = tostring, load = function(s) core():setOptionMaxVehicleTextureSize(tonumber(s) or 4) end },
    { id = "corpse", weak = true,
      get = function() return core():getOptionCorpseShadows() end,
      good = function(v) return v == false end,
      set = function() core():setOptionCorpseShadows(false) end,
      save = b2s, load = function(s) core():setOptionCorpseShadows(s2b(s)) end },
}

-- true / false, or nil when this game build has no such option
function CS.tuneIsGood(item)
    local ok, v = pcall(item.get)
    if not ok or v == nil then return nil end
    local ok2, good = pcall(item.good, v)
    if not ok2 then return nil end
    return good
end

-- how many of the (normal or also weak) switches could still be set
function CS.tuneRemaining(withWeak)
    local n = 0
    for _, item in ipairs(CS.TUNE) do
        if (withWeak or not item.weak) and CS.tuneIsGood(item) == false then n = n + 1 end
    end
    return n
end

local function save()
    pcall(function() core():saveOptions() end)
    CS.saveSettings()
end

-- set everything not fine yet; returns how many changed and whether a restart is needed
function CS.tuneApply(withWeak)
    local changed, restart = 0, false
    for _, item in ipairs(CS.TUNE) do
        if (withWeak or not item.weak) and CS.tuneIsGood(item) == false then
            local ok, v = pcall(item.get)
            if ok then
                local key = "prev_" .. item.id
                if CS.settings[key] == nil then CS.settings[key] = item.save(v) end
                if pcall(item.set) then
                    changed = changed + 1
                    if item.restart then restart = true end
                end
            end
        end
    end
    if changed > 0 then save(); CS.markChange() end
    return changed, restart
end

-- put back what was there before Cookie Slicer changed it
function CS.tuneUndo()
    local n, restart = 0, false
    for _, item in ipairs(CS.TUNE) do
        local key = "prev_" .. item.id
        local prev = CS.settings[key]
        if prev ~= nil then
            if pcall(item.load, prev) then
                n = n + 1
                if item.restart then restart = true end
            end
            CS.settings[key] = nil
        end
    end
    if n > 0 then save(); CS.markChange() end
    return n, restart
end

function CS.tuneHasUndo()
    for _, item in ipairs(CS.TUNE) do
        if CS.settings["prev_" .. item.id] ~= nil then return true end
    end
    return false
end

-- ---------------------------------------------------------------- switches and levels

-- "off" for a switch we never changed: the game's usual default
local OFF = { tiered = "false", clothes = "1", weapons = "false", uifps = "60", lighting = "30",
              ragdolls = "20", texcomp = "false", texsize = "4", vehtex = "4", corpse = "true" }

function CS.tuneItem(id)
    for _, item in ipairs(CS.TUNE) do
        if item.id == id then return item end
    end
    return nil
end

local function setOn(item)
    if CS.tuneIsGood(item) ~= false then return false end
    local ok, v = pcall(item.get)
    if not ok then return false end
    local key = "prev_" .. item.id
    if CS.settings[key] == nil then CS.settings[key] = item.save(v) end
    return pcall(item.set) == true
end

local function setOff(item)
    local key = "prev_" .. item.id
    local prev = CS.settings[key]
    if prev ~= nil then
        CS.settings[key] = nil
        return pcall(item.load, prev) == true
    end
    if CS.tuneIsGood(item) == true then return pcall(item.load, OFF[item.id]) == true end
    return false
end

-- one switch on the right card; returns whether the game option changed and
-- whether it needs the game to start again
function CS.tuneToggle(id)
    local item = CS.tuneItem(id)
    if not item then return false, false end
    local good = CS.tuneIsGood(item)
    if good == nil then return false, false end
    local changed
    if good then changed = setOff(item) else changed = setOn(item) end
    if changed then save(); CS.markChange() end
    return changed, changed and item.restart == true
end

-- levels: orig (put back what the player had), balanced (3), smooth (the 6
-- that work at once), max (all 10)
CS.PRESETS = { "orig", "balanced", "smooth", "max" }
local BALANCED = { tiered = true, clothes = true, uifps = true }

local function inPreset(p, item)
    if p == "max" then return true end
    if p == "smooth" then return not item.weak end
    if p == "balanced" then return BALANCED[item.id] == true end
    return false
end

function CS.tunePreset(p)
    if p == "orig" then return CS.tuneUndo() end
    local changed, restart = 0, false
    for _, item in ipairs(CS.TUNE) do
        local did = false
        if inPreset(p, item) then
            did = setOn(item)
        elseif CS.settings["prev_" .. item.id] ~= nil then
            did = setOff(item)
        end
        if did then
            changed = changed + 1
            if item.restart then restart = true end
        end
    end
    if changed > 0 then save(); CS.markChange() end
    return changed, restart
end

-- which level the switches match now ("custom" when none)
function CS.tuneCurrentPreset()
    local all, normal, bal = true, true, true
    local weakChanged, otherChanged = false, false
    for _, item in ipairs(CS.TUNE) do
        local good = CS.tuneIsGood(item) -- nil (not in this game build) counts as fine
        if good == false then
            all = false
            if not item.weak then normal = false end
            if BALANCED[item.id] then bal = false end
        end
        if CS.settings["prev_" .. item.id] ~= nil then
            if item.weak then weakChanged = true end
            if not BALANCED[item.id] then otherChanged = true end
        end
    end
    if all then return "max" end
    if normal and not weakChanged then return "smooth" end
    if bal and not otherChanged then return "balanced" end
    if not CS.tuneHasUndo() then return "orig" end
    return "custom"
end

-- ---------------------------------------------------------------- what to expect

-- Rough share of the game's main thread each change frees. Drawing windows
-- was ~15% of the main thread in our 10 Nov client recordings; the others are
-- small guesses (they matter most with many zombies around). Shown as "about".
local SHARE = { tiered = 0.05, clothes = 0.02, weapons = 0.005, ragdolls = 0.01 }

-- what changed against the player's own values: e[id] = { prev = text, now = value },
-- e.saving = estimated part of the main thread freed (0..1), e.vram = textures made lighter
function CS.tuneEstimate()
    local e = { changed = false, saving = 0, vram = false }
    for _, item in ipairs(CS.TUNE) do
        local prev = CS.settings["prev_" .. item.id]
        if prev ~= nil and CS.tuneIsGood(item) == true then
            local ok, now = pcall(item.get)
            e.changed = true
            e[item.id] = { prev = prev, now = ok and now or nil }
            if SHARE[item.id] then e.saving = e.saving + SHARE[item.id] end
            if item.id == "texcomp" or item.id == "texsize" or item.id == "vehtex" then e.vram = true end
        end
    end
    local ui = e.uifps
    if ui then
        local p, n = tonumber(ui.prev), tonumber(ui.now)
        local fbo = false
        pcall(function() fbo = getCore():getOptionUIFBO() end)
        if p and n and p > n and fbo then e.saving = e.saving + 0.15 * (1 - n / p) end
    end
    return e
end
