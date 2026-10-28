-- 000_CookieDefaultSkin.lua   (put in media/lua/shared of Cookie Express)
-- The "000_" prefix is required: this file must load BEFORE CuddySkins.lua and
-- CarSkinsB42KI5.lua, so the snapshot only sees each vehicle's own (default) skins.
-- Skin mods append their skins to the end of the list, so default = index 0 .. N-1.

CookieDefaultSkin = CookieDefaultSkin or {}
local CDS = CookieDefaultSkin
CDS.defaults = CDS.defaults or {}

-- Snapshot every vehicle script (vanilla + all vehicle mods) before skin mods add theirs
local function snapshot()
    local list = getScriptManager():getAllVehicleScripts()
    if not list then return 0 end
    local n = 0
    for i = 0, list:size() - 1 do
        local s = list:get(i)
        local name = s:getFullName()
        if CDS.defaults[name] == nil then
            CDS.defaults[name] = s:getSkinCount()
            n = n + 1
        end
    end
    return n
end
CDS.snapCount = snapshot()

-- Random default skin index for a model, e.g. "Base.92amgeneralM998" (nil = leave as is)
function CDS.pick(scriptName)
    local d = CDS.defaults[scriptName]
    if not d or d <= 0 then return nil end
    return ZombRand(d)
end

-- Force an already-spawned vehicle onto a default skin (call on the server, right after spawning)
function CDS.apply(vehicle)
    if not vehicle or not vehicle:getScript() then return end
    local d = CDS.defaults[vehicle:getScriptName()] or CDS.defaults[vehicle:getScript():getFullName()]
    if not d or d <= 0 then return end
    if vehicle:getSkinIndex() < d then return end -- already a default skin
    vehicle:setSkinIndex(ZombRand(math.min(d, vehicle:getScript():getSkinCount())))
    vehicle:updateSkin()
end

-- Diagnostic line in console.txt: confirms the snapshot ran before the skin mods
Events.OnInitGlobalModData.Add(function()
    local list = getScriptManager():getAllVehicleScripts()
    local grown = 0
    for i = 0, list:size() - 1 do
        local s = list:get(i)
        local d = CDS.defaults[s:getFullName()]
        if d and s:getSkinCount() > d then grown = grown + 1 end
    end
    print(string.format("[CookieDefaultSkin] snapshot=%d vehicles, %d vehicles have extra mod skins (should be > 0)", CDS.snapCount, grown))
end)
