-- CookieServerPatch: More Traits Definitive (3799050151) Burn Ward Patient guard. Client side.
--
-- Log 25 Oct 2026 (one player, 707 times in ~35 min):
--   BurnWardPatient (MT_Weapons.lua:8) "__lt not defined for operand"
--   <- EveryOneMinute (MT_Tick.lua:108)
-- Line 8 is `if playerdata.MTModVersion < 3 or ...`: the character has the
-- burned trait but no MTModVersion in its ModData (nil < 3 throws).
-- Because the error aborts MT's EveryOneMinute, everything after line 108 never
-- runs for that player: SuperImmune recovery / fake infection, Immunocompromised,
-- self harm, blood traits, QuickRest.
--
-- Fix: wrap MT.Weapons.BurnWardPatient (MT_Tick looks it up at call time).
--  * MTModVersion missing or not a number -> treat it like an old character
--    (the same as MTModVersion < 3): skip, as line 8 intends. MTModVersion itself
--    is not written, so MT's own version handling is untouched.
--  * Any other error inside it is caught, so the rest of MT's minute still runs.
-- The sandbox option BurnedFireAversion would not help: line 8 checks the
-- version before it.

if isServer() then return end

local TAG = "[CookieServerPatch] moretraits-guard"
local installed = false
local skipped = 0
local nextSkipReport = 1
local errorsLogged = 0

local function install()
    if installed then return true end
    if type(MT) ~= "table" or type(MT.Weapons) ~= "table" then return false end
    local original = MT.Weapons.BurnWardPatient
    if type(original) ~= "function" then return false end

    MT.Weapons.BurnWardPatient = function(player, playerdata)
        if type(playerdata) ~= "table" or type(playerdata.MTModVersion) ~= "number" then
            local okTrait, hasBurned = pcall(function()
                return player:hasTrait(ToadTraitsRegistries.burned)
            end)
            if not (okTrait and hasBurned) then return end
            skipped = skipped + 1
            if skipped >= nextSkipReport then
                print(TAG .. " BurnWardPatient skipped " .. tostring(skipped) .. "x (no MTModVersion)")
                nextSkipReport = nextSkipReport * 10
            end
            return
        end
        local ok, err = pcall(original, player, playerdata)
        if not ok and errorsLogged < 5 then
            errorsLogged = errorsLogged + 1
            print(TAG .. " BurnWardPatient error caught: " .. tostring(err))
        end
    end
    MT.Weapons.CookieGuarded = true
    installed = true
    print(TAG .. " on")
    return true
end

if not install() then
    Events.OnGameStart.Add(install)
end
