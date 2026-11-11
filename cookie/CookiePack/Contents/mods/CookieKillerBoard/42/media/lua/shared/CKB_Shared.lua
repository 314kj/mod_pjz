-- Cookie Killer Board - shared core
-- by lookchinnoi (AKA) for CookieCheetah
-- Zombie kills per player: this life, all lives, deaths, and the weapon that killed the most.
-- Kills come from the game's own counter (IsoPlayer zombieKills), which the server keeps.
-- NOTE: keep every .lua file ASCII only. Player-facing text lives in Translate/*/IG_UI.json
-- NOTE: Kahlua has no next(), % keeps the sign of the left side, no string.format: see CM helpers

require "CM_Shared"

CKB = CKB or {}
CKB.MOD = "CookieKillerBoard"
CKB.VERSION = "1.0.1"
CKB.BUILD = "ckb-261109-seed"
CKB.TOP = 7               -- rows one board page shows
CKB.FIST = "@fist"        -- weapon key: bare hands / not holding a weapon
CKB.CAR = "@car"          -- weapon key: run over with a vehicle

function CKB.log(msg) print("[CookieKillerBoard] " .. tostring(msg)) end

-- the weapon with the most kills in a tally { [fullType] = kills }; ties go to the lower name
function CKB.topWeapon(t)
    if type(t) ~= "table" then return nil end
    local best, bn = nil, 0
    for k, v in pairs(t) do
        local n = CM.num(v, 0)
        if n > bn or (n == bn and n > 0 and best ~= nil and tostring(k) < tostring(best)) then
            best, bn = k, n
        end
    end
    return best
end

-- 12345 -> "12,345"
function CKB.fmt(n)
    n = math.floor(CM.num(n, 0))
    local neg = n < 0
    if neg then n = -n end
    local s = tostring(n)
    local dot = string.find(s, ".", 1, true)
    if dot then s = string.sub(s, 1, dot - 1) end
    local out = ""
    while #s > 3 do
        out = "," .. string.sub(s, -3) .. out
        s = string.sub(s, 1, #s - 3)
    end
    out = s .. out
    if neg then out = "-" .. out end
    return out
end

return CKB
