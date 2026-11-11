-- CookieServerPatch: Silent Hill Monsters (3821752171) right-click error guard. Client only.
--
-- On every world right-click SHM looks at the corpses around the click (SHM_CorpseRemove.monster)
-- and asks each one for its outfit name. A corpse without a human visual (animal corpses and the
-- like) makes that Java call throw a NullPointerException. SHM catches it with pcall, but the game
-- still prints the stack trace and counts it in the red error box, so players think something broke
-- (seen 10 Nov 2026, 42.22.2).
-- Here a corpse without a human visual skips the outfit call. It is checked only by SHM's own
-- mod-data mark and by its worn items, the same two checks SHM falls back to after the error, so the
-- right-click menu shows exactly the same options. Every other corpse goes through SHM unchanged.

if isServer() then return end

local TAG = "[CookieServerPatch] shm-corpse-guard"
local installed = false

local function roster()
    local ok, R = pcall(require, "SHM_Roster")
    if ok and type(R) == "table" then return R end
    return nil
end

-- mod-data mark (SHM_<monster>) and worn SHM body pieces, without the outfit call
local function checkWithoutOutfit(CR, body)
    local R = roster()
    local names = (R and type(R.names) == "function" and R.names()) or {}
    local okD, data = pcall(function() return body:getModData() end)
    if okD and data then
        for _, name in ipairs(names) do
            if CR.Names == nil or CR.Names[name] then
                if data["SHM_" .. name] then return name end
            end
        end
    end
    if not R or type(R.Monsters) ~= "table" then return nil end
    local found = nil
    pcall(function()
        local visuals = ItemVisuals.new()
        body:getItemVisuals(visuals)
        local bodies = type(R.bodies) == "function" and R.bodies() or {}
        for i = 0, visuals:size() - 1 do
            local v = visuals:get(i)
            local item = v and v:getClothingItemName()
            if type(item) == "string" then
                local model = item:match("^SHM_(.+)CorpseBody$") or item:match("^SHM_(.+)Body$")
                if model then
                    model = bodies[model] or model
                    if R.Monsters[model] then found = model; return end
                end
            end
        end
    end)
    return found
end

local function install()
    if installed then return true end
    local CR = SHM_CorpseRemove
    if type(CR) ~= "table" or type(CR.monster) ~= "function" then return false end
    local prev = CR.monster
    CR.monster = function(body, ...)
        if body ~= nil and instanceof(body, "IsoDeadBody") then
            local ok, hv = pcall(function() return body:getHumanVisual() end)
            if ok and hv == nil then return checkWithoutOutfit(CR, body) end
        end
        return prev(body, ...)
    end
    installed = true
    print(TAG .. " on")
    return true
end

if not install() then
    Events.OnGameBoot.Add(install)
    Events.OnGameStart.Add(install)
end
